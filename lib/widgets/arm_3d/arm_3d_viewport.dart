// lib/widgets/arm_3d/arm_3d_viewport.dart
// Interactive 3D robotic arm viewport with orbit gestures, realistic lighting,
// geared gripper animation, and camera view presets.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'arm_mesh_builder.dart';
import 'vector3d.dart';

enum CameraPreset {
  perspective3D,
  front,
  side,
  top,
  gripper,
}

class Arm3DViewport extends StatefulWidget {
  final List<int> angles; // Current servo angles [0..180]
  final int? activeJoint; // Currently touched/adjusted joint index
  final bool autoRotate;
  final VoidCallback? onToggleGrip;
  final VoidCallback? onHome;
  final bool showControls;

  const Arm3DViewport({
    super.key,
    required this.angles,
    this.activeJoint,
    this.autoRotate = false,
    this.onToggleGrip,
    this.onHome,
    this.showControls = true,
  });

  @override
  State<Arm3DViewport> createState() => _Arm3DViewportState();
}

class _Arm3DViewportState extends State<Arm3DViewport>
    with SingleTickerProviderStateMixin {
  // Camera orbit angles (radians)
  double _yaw = 0.65; // Horizontal rotation
  double _pitch = 0.38; // Vertical elevation
  double _zoom = 1.0; // Zoom multiplier

  // Pan offsets
  double _panX = 0.0;
  double _panY = 15.0;

  // Auto-spin
  bool _isAutoSpinning = false;
  late AnimationController _ticker;

  // Smooth lerp for servo animation
  List<double> _currentDisplayAngles = [90, 90, 90, 90, 90, 90];

  // Touch tracking
  Offset? _lastPanPos;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _currentDisplayAngles = widget.angles.map((e) => e.toDouble()).toList();
    _isAutoSpinning = widget.autoRotate;

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _ticker.repeat();
  }

  @override
  void didUpdateWidget(Arm3DViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoRotate != oldWidget.autoRotate) {
      _isAutoSpinning = widget.autoRotate;
    }
  }

  void _onTick() {
    bool needsRepaint = false;

    // Smoothly interpolate displayed angles towards target angles
    for (int i = 0; i < 6; i++) {
      final target = (i < widget.angles.length ? widget.angles[i] : 90).toDouble();
      final current = _currentDisplayAngles[i];
      final diff = target - current;
      if (diff.abs() > 0.1) {
        _currentDisplayAngles[i] = current + diff * 0.22; // Smooth 60fps lerp
        needsRepaint = true;
      } else {
        _currentDisplayAngles[i] = target;
      }
    }

    // Auto turntable rotation
    if (_isAutoSpinning) {
      _yaw = (_yaw + 0.008) % (math.pi * 2);
      needsRepaint = true;
    }

    if (needsRepaint && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setPreset(CameraPreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _isAutoSpinning = false;
      _panX = 0;
      switch (preset) {
        case CameraPreset.perspective3D:
          _yaw = 0.65;
          _pitch = 0.38;
          _zoom = 1.0;
          _panY = 15.0;
          break;
        case CameraPreset.front:
          _yaw = 0.0;
          _pitch = 0.12;
          _zoom = 1.05;
          _panY = 15.0;
          break;
        case CameraPreset.side:
          _yaw = math.pi / 2;
          _pitch = 0.08;
          _zoom = 1.0;
          _panY = 15.0;
          break;
        case CameraPreset.top:
          _yaw = 0.0;
          _pitch = 1.48; // Near 90 degrees top down
          _zoom = 0.95;
          _panY = 0.0;
          break;
        case CameraPreset.gripper:
          _yaw = 0.35;
          _pitch = 0.25;
          _zoom = 1.75;
          _panY = -65.0; // Focus on claw
          break;
      }
    });
  }

  void _resetCamera() {
    _setPreset(CameraPreset.perspective3D);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // ── Interactive Gesture Detector for Orbit & Zoom ─────────────
          GestureDetector(
            onScaleStart: (details) {
              _lastPanPos = details.focalPoint;
              _baseZoom = _zoom;
            },
            onScaleUpdate: (details) {
              setState(() {
                if (details.pointerCount >= 2) {
                  // Pinch to zoom
                  _zoom = (_baseZoom * details.scale).clamp(0.55, 2.6);
                } else if (_lastPanPos != null) {
                  // 1-finger Orbit Drag
                  final dx = details.focalPoint.dx - _lastPanPos!.dx;
                  final dy = details.focalPoint.dy - _lastPanPos!.dy;

                  _yaw = (_yaw - dx * 0.012) % (math.pi * 2);
                  _pitch = (_pitch + dy * 0.01).clamp(-0.25, 1.50);
                  _isAutoSpinning = false;
                }
                _lastPanPos = details.focalPoint;
              });
            },
            onScaleEnd: (_) => _lastPanPos = null,
            onDoubleTap: _resetCamera,
            child: CustomPaint(
              size: Size.infinite,
              painter: _Arm3DPainter(
                servoAngles: _currentDisplayAngles,
                activeJoint: widget.activeJoint,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
                panX: _panX,
                panY: _panY,
              ),
            ),
          ),

          // ── Top Bar: Camera Presets & Badges ───────────────────────────
          if (widget.showControls)
            Positioned(
              top: 8,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  // Title / Model Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'BAMBU 6-DOF',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Camera Preset Chips
                  _CameraPresetButton(
                    label: '3D',
                    tooltip: '3D Isometric Orbit',
                    onPressed: () => _setPreset(CameraPreset.perspective3D),
                  ),
                  const SizedBox(width: 4),
                  _CameraPresetButton(
                    label: 'FRONT',
                    tooltip: 'Front View',
                    onPressed: () => _setPreset(CameraPreset.front),
                  ),
                  const SizedBox(width: 4),
                  _CameraPresetButton(
                    label: 'SIDE',
                    tooltip: 'Side Profile',
                    onPressed: () => _setPreset(CameraPreset.side),
                  ),
                  const SizedBox(width: 4),
                  _CameraPresetButton(
                    label: 'TOP',
                    tooltip: 'Top Down View',
                    onPressed: () => _setPreset(CameraPreset.top),
                  ),
                  const SizedBox(width: 4),
                  _CameraPresetButton(
                    label: 'CLAW',
                    tooltip: 'Gripper Close-Up',
                    onPressed: () => _setPreset(CameraPreset.gripper),
                  ),
                ],
              ),
            ),

          // ── Bottom Floating Action Bar ─────────────────────────────────
          if (widget.showControls)
            Positioned(
              bottom: 8,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  // Turntable Auto-Spin Toggle
                  _GlassIconButton(
                    icon: _isAutoSpinning ? Icons.rotate_right : Icons.threesixty,
                    color: _isAutoSpinning ? const Color(0xFF00E676) : Colors.white70,
                    tooltip: _isAutoSpinning ? 'Pause Auto-Spin' : 'Auto Turntable Spin',
                    onPressed: () {
                      setState(() => _isAutoSpinning = !_isAutoSpinning);
                    },
                  ),
                  const SizedBox(width: 6),
                  // Reset Camera
                  _GlassIconButton(
                    icon: Icons.center_focus_strong,
                    tooltip: 'Reset View (Double Tap)',
                    onPressed: _resetCamera,
                  ),
                  const Spacer(),
                  // Quick Toggle Grip (Claw Open/Close)
                  if (widget.onToggleGrip != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onToggleGrip!();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00B04F), Color(0xFF10B981)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00B04F).withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.pinch, size: 16, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                (_currentDisplayAngles[5] > 90) ? 'CLOSE CLAW' : 'OPEN CLAW',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (widget.onHome != null) ...[
                    const SizedBox(width: 6),
                    _GlassIconButton(
                      icon: Icons.home_outlined,
                      tooltip: 'Home Pose',
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        widget.onHome!();
                      },
                    ),
                  ],
                ],
              ),
            ),

          // ── Active Joint Floating Indicator ────────────────────────────
          if (widget.activeJoint != null && widget.activeJoint! < 6)
            Positioned(
              top: 44,
              left: 12,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, size: 14, color: Color(0xFF00F0FF)),
                      const SizedBox(width: 4),
                      Text(
                        'J${widget.activeJoint! + 1}: ${_currentDisplayAngles[widget.activeJoint!].round()}°',
                        style: const TextStyle(
                          color: Color(0xFF00F0FF),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraPresetButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  const _CameraPresetButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

/// 3D Custom Painter with camera projection and directional lighting
class _Arm3DPainter extends CustomPainter {
  final List<double> servoAngles;
  final int? activeJoint;
  final double yaw;
  final double pitch;
  final double zoom;
  final double panX;
  final double panY;

  _Arm3DPainter({
    required this.servoAngles,
    required this.activeJoint,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.panX,
    required this.panY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + panX;
    final cy = size.height / 2 + panY + 20;

    // Background gradient for sleek dark industrial studio environment
    final bgRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.2),
        radius: 1.2,
        colors: [
          Color(0xFF1E262B),
          Color(0xFF101417),
          Color(0xFF0A0C0E),
        ],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // Camera view matrix: Yaw around Y, Pitch around X
    final mCam = Mat4.rotationX(pitch) * Mat4.rotationY(yaw);

    // Light source vector in camera/world space
    final lightDir = const Vec3D(0.45, 0.85, 0.65).normalized();

    // Build arm mesh faces
    final builder = ArmMeshBuilder(
      servoDegrees: servoAngles,
      activeJoint: activeJoint,
      viewMatrix: mCam,
    );
    final faces = builder.buildFaces();

    // 3D Perspective settings
    const double cameraDistance = 380.0;
    final double scale = (size.height * 0.95 * zoom) / cameraDistance;

    // Draw polygons sorted back to front (Painter's algorithm)
    for (final face in faces) {
      if (face.worldVertices.length < 3) continue;

      // 3D projection onto 2D canvas
      final Path path = Path();
      bool isBehindCamera = false;

      for (int i = 0; i < face.viewVertices.length; i++) {
        final v = face.viewVertices[i];
        final zDist = cameraDistance - v.z;
        if (zDist <= 10.0) {
          isBehindCamera = true;
          break;
        }

        // Perspective foreshortening
        final factor = cameraDistance / zDist;
        final px = cx + v.x * factor * (scale / 1.0);
        final py = cy - v.y * factor * (scale / 1.0);

        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }

      if (isBehindCamera) continue;
      path.close();

      // Lighting calculation (Lambertian diffuse + ambient + specular)
      final double dot = math.max(0.0, face.worldNormal.dot(lightDir));
      final double ambient = face.isGlowing ? 0.85 : 0.40;
      final double diffuse = dot * (1.0 - ambient);
      final double intensity = (ambient + diffuse).clamp(0.0, 1.0);

      Color shadedColor = _applyLighting(face.baseColor, intensity, face.isMetallic, dot);

      // Draw filled face
      final facePaint = Paint()
        ..color = shadedColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, facePaint);

      // Subtle edge outline for crisp CAD / Bambu Studio 3D look
      final strokePaint = Paint()
        ..color = face.hasOutline
            ? (face.outlineColor ?? Colors.white10)
            : (face.isGlowing
                ? const Color(0xFF00F0FF).withOpacity(0.6)
                : Colors.black.withOpacity(0.18))
        ..style = PaintingStyle.stroke
        ..strokeWidth = face.isGlowing ? 1.4 : 0.7;
      canvas.drawPath(path, strokePaint);
    }

    // Draw coordinate axes indicator in bottom-left corner
    _drawCoordinateAxes(canvas, size, mCam);
  }

  Color _applyLighting(Color base, double intensity, bool isMetallic, double dot) {
    final hsv = HSVColor.fromColor(base);
    double v = (hsv.value * intensity).clamp(0.0, 1.0);

    // Specular highlight boost for shiny PLA and metallic screws
    if (dot > 0.75) {
      final spec = math.pow((dot - 0.75) / 0.25, 3) * (isMetallic ? 0.35 : 0.20);
      v = (v + spec).clamp(0.0, 1.0);
    }

    return hsv.withValue(v).toColor();
  }

  void _drawCoordinateAxes(Canvas canvas, Size size, Mat4 mCam) {
    const origin = Offset(36, 36);
    const length = 22.0;

    // Transform axis unit vectors
    final xDir = mCam.transformPoint(const Vec3D(1, 0, 0));
    final yDir = mCam.transformPoint(const Vec3D(0, 1, 0));
    final zDir = mCam.transformPoint(const Vec3D(0, 0, 1));

    void drawAxis(Vec3D dir, Color color, String label) {
      final end = Offset(origin.dx + dir.x * length, origin.dy - dir.y * length);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(origin, end, paint);

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, end + const Offset(2, -5));
    }

    drawAxis(xDir, Colors.redAccent, 'X');
    drawAxis(yDir, const Color(0xFF00E676), 'Z'); // Z is UP in slicing/print space
    drawAxis(zDir, Colors.blueAccent, 'Y');
  }

  @override
  bool shouldRepaint(_Arm3DPainter old) {
    return old.yaw != yaw ||
        old.pitch != pitch ||
        old.zoom != zoom ||
        old.panX != panX ||
        old.panY != panY ||
        old.activeJoint != activeJoint ||
        old.servoAngles != servoAngles;
  }
}
