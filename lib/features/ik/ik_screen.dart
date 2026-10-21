// lib/features/ik/ik_screen.dart
// Cartesian / IK control mode: 2D joystick for X/Y, vertical Z slider,
// wrist-pitch slider, workspace indicator.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/transport/arm_transport.dart';
import '../../domain/kinematics/kinematics.dart';
import '../../domain/models/arm_state.dart';
import '../../domain/models/calibration.dart';
import '../../providers/arm_provider.dart';
import '../../widgets/arm_painter.dart';
import '../../widgets/connection_guard.dart';

class IkScreen extends ConsumerWidget {
  const IkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(ikTargetProvider);
    final params = ref.watch(ikParamsProvider);
    final cal = ref.watch(calibrationProvider);
    final connState =
        ref.watch(connectionStateProvider).valueOrNull ??
            BleConnectionState.idle;
    final isConnected = connState == BleConnectionState.connected;

    final x = target['x']!;
    final y = target['y']!;
    final z = target['z']!;
    final phi = target['phi']!;

    final kin = Kinematics(params);
    final tipTarget = Vec3(x, y, z);
    final ikResult = kin.inverseKinematics(tipTarget, phi);
    final servoAngles =
        kin.anglesRadToServo(ikResult.anglesRad, cal);
    final armState = ArmState.fromAngles(servoAngles);

    final maxR = params.l1 + params.l2 + params.l3;
    final reachable = ikResult.reachable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IK Control'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _WorkspaceChip(reachable: reachable),
          ),
        ],
      ),
      body: ConnectionGuard(
        showOverlay: !isConnected,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Arm visualizer ─────────────────────────────────────────────
              Container(
                height: 210,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ArmVisualizerWidget(
                  armState: armState,
                  params: params,
                ),
              ),
              const SizedBox(height: 16),

              // ── IK values readout ──────────────────────────────────────────
              _IkReadoutRow(x: x, y: y, z: z, phi: phi, reachable: reachable),
              const SizedBox(height: 16),

              // ── Joystick + Z slider ────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        const Text(
                          'X / Y JOYSTICK',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _Joystick2D(
                          x: x,
                          y: y,
                          maxR: maxR,
                          enabled: isConnected,
                          onChanged: (nx, ny) {
                            ref
                                .read(ikTargetProvider.notifier)
                                .setXY(nx, ny);
                            _sendIk(ref, kin, nx, ny, z, phi, cal,
                                isConnected);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Z HEIGHT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _VerticalSlider(
                          value: z,
                          min: -50,
                          max: params.l1 + params.l2,
                          enabled: isConnected,
                          onChanged: (nz) {
                            ref.read(ikTargetProvider.notifier).setZ(nz);
                            _sendIk(ref, kin, x, y, nz, phi, cal,
                                isConnected);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Wrist pitch slider ─────────────────────────────────────────
              _WristPitchSlider(
                value: phi,
                enabled: isConnected,
                onChanged: (np) {
                  ref.read(ikTargetProvider.notifier).setPhi(np);
                  _sendIk(ref, kin, x, y, z, np, cal, isConnected);
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _sendIk(
    WidgetRef ref,
    Kinematics kin,
    double x,
    double y,
    double z,
    double phi,
    ArmCalibration cal,
    bool connected,
  ) {
    if (!connected) return;
    final result = kin.inverseKinematics(Vec3(x, y, z), phi);
    final servos = kin.anglesRadToServo(result.anglesRad, cal);
    ref.read(motionControllerProvider).liveInput(servos);
  }
}

// ── Workspace chip ────────────────────────────────────────────────────────────

class _WorkspaceChip extends StatelessWidget {
  final bool reachable;
  const _WorkspaceChip({required this.reachable});

  @override
  Widget build(BuildContext context) {
    final color =
        reachable ? StatusColors.connected : StatusColors.warning;
    return Chip(
      avatar: Icon(
        reachable ? Icons.check_circle : Icons.warning_amber,
        size: 16,
        color: color,
      ),
      label: Text(
        reachable ? 'Reachable' : 'Clamped!',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide(color: color.withOpacity(0.4)),
    );
  }
}

// ── IK Readout row ────────────────────────────────────────────────────────────

class _IkReadoutRow extends StatelessWidget {
  final double x, y, z, phi;
  final bool reachable;
  const _IkReadoutRow({
    required this.x,
    required this.y,
    required this.z,
    required this.phi,
    required this.reachable,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Val('X', '${x.toStringAsFixed(1)} mm',
              const Color(0xFFFF5252)),
          _Val('Y', '${y.toStringAsFixed(1)} mm',
              const Color(0xFF00E676)),
          _Val('Z', '${z.toStringAsFixed(1)} mm',
              const Color(0xFF40C4FF)),
          _Val('φ', '${(phi * 180 / math.pi).toStringAsFixed(1)}°',
              const Color(0xFFFFD740)),
        ],
      ),
    );
  }
}

class _Val extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Val(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            )),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            )),
      ],
    );
  }
}

// ── 2D Joystick ───────────────────────────────────────────────────────────────

class _Joystick2D extends StatefulWidget {
  final double x, y, maxR;
  final bool enabled;
  final void Function(double x, double y) onChanged;

  const _Joystick2D({
    required this.x,
    required this.y,
    required this.maxR,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_Joystick2D> createState() => _Joystick2DState();
}

class _Joystick2DState extends State<_Joystick2D> {
  Offset _thumb = Offset.zero;
  static const double _padSize = 200;
  static const double _thumbSize = 36;

  void _handleDrag(Offset local) {
    const center = Offset(_padSize / 2, _padSize / 2);
    var delta = local - center;
    const maxRadius = _padSize / 2 - _thumbSize / 2;
    if (delta.distance > maxRadius) {
      delta = delta * (maxRadius / delta.distance);
    }
    setState(() => _thumb = delta);

    final xRatio = delta.dx / maxRadius;
    final yRatio = -delta.dy / maxRadius; // flip Y
    final newX = xRatio * widget.maxR;
    final newY = yRatio * widget.maxR;
    HapticFeedback.selectionClick();
    widget.onChanged(newX, newY);
  }

  void _handleRelease() {
    setState(() => _thumb = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanUpdate: widget.enabled
          ? (d) => _handleDrag(d.localPosition)
          : null,
      onPanEnd: widget.enabled ? (_) => _handleRelease() : null,
      child: Container(
        width: _padSize,
        height: _padSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surfaceContainerHighest,
          border: Border.all(
            color: cs.primary.withOpacity(0.4),
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Crosshairs
            Positioned.fill(
              child: CustomPaint(painter: _CrosshairPainter()),
            ),
            // Thumb
            Positioned(
              left: _padSize / 2 + _thumb.dx - _thumbSize / 2,
              top: _padSize / 2 + _thumb.dy - _thumbSize / 2,
              child: Container(
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: electricGradient,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint);
    canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint);
    // Workspace circle
    final cp = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width / 2 - 2,
        cp);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Vertical Z slider ─────────────────────────────────────────────────────────

class _VerticalSlider extends StatelessWidget {
  final double value, min, max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _VerticalSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: RotatedBox(
        quarterTurns: 3,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF40C4FF),
            thumbColor: const Color(0xFF40C4FF),
            overlayColor: const Color(0xFF40C4FF).withOpacity(0.2),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

// ── Wrist pitch slider ────────────────────────────────────────────────────────

class _WristPitchSlider extends StatelessWidget {
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _WristPitchSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '↕️  Wrist Pitch',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${(value * 180 / math.pi).toStringAsFixed(1)}°',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFFD740),
              thumbColor: const Color(0xFFFFD740),
            ),
            child: Slider(
              value: value.clamp(-math.pi / 2, math.pi / 2),
              min: -math.pi / 2,
              max: math.pi / 2,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}
