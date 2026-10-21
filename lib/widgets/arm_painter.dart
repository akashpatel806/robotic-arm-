// lib/widgets/arm_painter.dart
// Arm visualizer widget with high-fidelity 3D model & 2D side/top views.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/kinematics/kinematics.dart';
import '../domain/models/arm_state.dart';
import '../domain/models/ik_params.dart';
import 'arm_3d/arm_3d_viewport.dart';

export 'arm_3d/arm_3d_viewport.dart';
export 'arm_3d/arm_mesh_builder.dart';
export 'arm_3d/vector3d.dart';

class ArmVisualizerWidget extends StatefulWidget {
  final ArmState armState;
  final IkParams params;
  final int? activeJoint;
  final VoidCallback? onToggleGrip;
  final VoidCallback? onHome;

  const ArmVisualizerWidget({
    super.key,
    required this.armState,
    required this.params,
    this.activeJoint,
    this.onToggleGrip,
    this.onHome,
  });

  @override
  State<ArmVisualizerWidget> createState() => _ArmVisualizerWidgetState();
}

class _ArmVisualizerWidgetState extends State<ArmVisualizerWidget> {
  bool _is3DMode = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_is3DMode)
          Positioned.fill(
            child: Arm3DViewport(
              angles: widget.armState.angles,
              activeJoint: widget.activeJoint,
              onToggleGrip: widget.onToggleGrip,
              onHome: widget.onHome,
            ),
          )
        else
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _SideViewPainter(widget.armState, widget.params),
                    ),
                  ),
                ),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _TopViewPainter(widget.armState, widget.params),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Mode Switcher (3D Model / 2D Ortho) in top right
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewModeTab(
                  label: '3D BODY',
                  icon: Icons.view_in_ar,
                  isSelected: _is3DMode,
                  onTap: () => setState(() => _is3DMode = true),
                ),
                _ViewModeTab(
                  label: '2D PLAN',
                  icon: Icons.architecture,
                  isSelected: !_is3DMode,
                  onTap: () => setState(() => _is3DMode = false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00B04F) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : Colors.white60,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Side view painter (shoulder / elbow / wrist plane) ──────────────────────

class _SideViewPainter extends CustomPainter {
  final ArmState arm;
  final IkParams p;

  _SideViewPainter(this.arm, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    const scale = 0.8;
    final cx = size.width / 2;
    final cy = size.height * 0.85;

    final kin = Kinematics(p);
    final rads = _servoToRads();
    final fk = kin.forwardKinematics(rads);

    final maxReach = p.l1 + p.l2 + p.l3 + p.d1;
    final pxPerMm = (size.height * scale) / maxReach;

    Offset world2canvas(double r, double z) {
      return Offset(cx + r * pxPerMm, cy - z * pxPerMm);
    }

    final basePos = world2canvas(0, 0);
    final shoulderPos = world2canvas(0, p.d1);

    final t0 = rads[0];
    final cosPhi = math.cos(t0);
    final sinPhi = math.sin(t0);

    Offset fkToCanvas(Vec3 v) {
      final r = math.sqrt(v.x * v.x + v.y * v.y) *
          (v.x * cosPhi + v.y * sinPhi >= 0 ? 1 : -1);
      return world2canvas(r, v.z);
    }

    final elbowPos = fkToCanvas(fk.elbowPos);
    final wristPos = fkToCanvas(fk.wristPos);
    final tipPos = fkToCanvas(fk.tipPos);

    // Workspace boundary
    final workspacePaint = Paint()
      ..color = const Color(0xFF00B04F).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final maxR = (p.l1 + p.l2 + p.l3) * pxPerMm;
    canvas.drawCircle(shoulderPos, maxR, workspacePaint);

    // Ground line
    final groundPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      groundPaint,
    );

    // Base column
    final linkPaint = Paint()
      ..color = const Color(0xFF00B04F)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(basePos, shoulderPos, linkPaint);

    // Links (styled with Bambu Green palette)
    final link1Paint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final link2Paint = Paint()
      ..color = const Color(0xFF22C55E)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final link3Paint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(shoulderPos, elbowPos, link1Paint);
    canvas.drawLine(elbowPos, wristPos, link2Paint);
    canvas.drawLine(wristPos, tipPos, link3Paint);

    // Joints
    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final pos in [shoulderPos, elbowPos, wristPos]) {
      canvas.drawCircle(pos, 5, jointPaint);
    }

    // Tip
    final tipPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(tipPos, 6, tipPaint);

    // Label
    _drawLabel(canvas, const Offset(8, 8), 'SIDE PROFILE', size);
  }

  List<double> _servoToRads() {
    final a = arm.angles;
    return [
      (a[0] / 180.0) * math.pi,
      ((a[1] - 90) / 90.0) * (math.pi / 2),
      ((a[2] - 90) / 90.0) * (math.pi / 2),
      ((a[3] - 90) / 90.0) * (math.pi / 2),
      0.0,
      0.0,
    ];
  }

  void _drawLabel(Canvas c, Offset pos, String text, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, pos);
  }

  @override
  bool shouldRepaint(_SideViewPainter old) =>
      old.arm != arm || old.p != p;
}

// ── Top view painter (base rotation) ────────────────────────────────────────

class _TopViewPainter extends CustomPainter {
  final ArmState arm;
  final IkParams p;

  _TopViewPainter(this.arm, this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final maxReach = p.l1 + p.l2 + p.l3;
    final pxPerMm = (size.width * 0.42) / maxReach;

    // Base circle
    final basePaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), maxReach * pxPerMm, basePaint);

    // Arm direction line (base angle)
    final baseAngle = (arm.angles[0] / 180.0) * math.pi;
    final tipR = maxReach * pxPerMm;
    final armEnd = Offset(
      cx + tipR * math.cos(baseAngle),
      cy - tipR * math.sin(baseAngle),
    );

    final armPaint = Paint()
      ..color = const Color(0xFF00B04F)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), armEnd, armPaint);

    // Base dot
    final dotPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 6, dotPaint);

    // Tip dot
    final tipPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(armEnd, 5, tipPaint);

    // Label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'TOP DOWN',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(8, 8));
  }

  @override
  bool shouldRepaint(_TopViewPainter old) =>
      old.arm != arm || old.p != p;
}
