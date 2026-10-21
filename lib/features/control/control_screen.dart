// lib/features/control/control_screen.dart
// Joint control mode: Interactive 3D robotic arm model, live geared claw animation,
// micro-step adjustment, and demo sequence routines.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/transport/arm_transport.dart';
import '../../domain/models/arm_state.dart';
import '../../providers/arm_provider.dart';
import '../../widgets/arm_painter.dart';
import '../../widgets/connection_guard.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  late List<int> _angles;
  bool _initialized = false;
  int? _activeJoint;
  bool _isExpandedViewport = false;
  bool _isRunningRoutine = false;
  Timer? _routineTimer;

  @override
  void initState() {
    super.initState();
    _angles = List<int>.from(kHomeAngles);
  }

  @override
  void dispose() {
    _routineTimer?.cancel();
    super.dispose();
  }

  void _syncFromArm(ArmState state) {
    if (!_initialized) {
      _angles = List<int>.from(state.angles);
      _initialized = true;
    }
  }

  void _onSliderChange(int joint, double value) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeJoint = joint;
      _angles[joint] = value.round();
    });
    _dispatchAngles();
  }

  void _nudgeAngle(int joint, int delta) {
    HapticFeedback.selectionClick();
    final cal = ref.read(calibrationProvider);
    final jCal = cal.joints[joint];
    setState(() {
      _activeJoint = joint;
      _angles[joint] = (_angles[joint] + delta).clamp(jCal.minAngle, jCal.maxAngle);
    });
    _dispatchAngles();
  }

  void _dispatchAngles() {
    final cal = ref.read(calibrationProvider);
    final clamped = List<int>.generate(
      6,
      (i) => _angles[i].clamp(
        cal.joints[i].minAngle,
        cal.joints[i].maxAngle,
      ),
    );
    ref.read(motionControllerProvider).liveInput(clamped);
  }

  void _sendHome() {
    HapticFeedback.heavyImpact();
    _cancelRoutine();
    setState(() {
      _activeJoint = null;
      _angles = List<int>.from(kHomeAngles);
    });
    ref.read(motionControllerProvider).goHome();
    ref.read(transportProvider).sendHome();
  }

  void _sendStop() {
    HapticFeedback.heavyImpact();
    _cancelRoutine();
    ref.read(motionControllerProvider).stopNow();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ STOPPED – arm frozen at current position'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleGripper() {
    HapticFeedback.lightImpact();
    _cancelRoutine();
    setState(() {
      _activeJoint = 5;
      // Toggle between open (160°) and closed (20°)
      _angles[5] = (_angles[5] > 90) ? 20 : 160;
    });
    _dispatchAngles();
  }

  void _cancelRoutine() {
    if (_isRunningRoutine) {
      _routineTimer?.cancel();
      _routineTimer = null;
      setState(() => _isRunningRoutine = false);
    }
  }

  // ── Preset Routines ───────────────────────────────────────────────────────

  void _runParkRoutine() {
    _cancelRoutine();
    HapticFeedback.mediumImpact();
    const parkAngles = [90, 150, 30, 150, 90, 30];
    setState(() {
      _angles = List<int>.from(parkAngles);
      _activeJoint = null;
    });
    ref.read(motionControllerProvider).moveTo(parkAngles);
  }

  void _runReachRoutine() {
    _cancelRoutine();
    HapticFeedback.mediumImpact();
    const reachAngles = [90, 65, 120, 60, 90, 160];
    setState(() {
      _angles = List<int>.from(reachAngles);
      _activeJoint = null;
    });
    ref.read(motionControllerProvider).moveTo(reachAngles);
  }

  void _runWaveRoutine() async {
    _cancelRoutine();
    setState(() => _isRunningRoutine = true);
    HapticFeedback.mediumImpact();

    final steps = [
      [90, 120, 60, 90, 90, 120], // Ready pose
      [90, 120, 60, 90, 45, 120], // Wave left
      [90, 120, 60, 90, 135, 120], // Wave right
      [90, 120, 60, 90, 45, 120], // Wave left
      [90, 120, 60, 90, 135, 120], // Wave right
      [90, 90, 90, 90, 90, 90], // Home
    ];

    int stepIdx = 0;
    _routineTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      if (stepIdx >= steps.length) {
        t.cancel();
        if (mounted) setState(() => _isRunningRoutine = false);
        return;
      }
      final step = steps[stepIdx];
      setState(() {
        _angles = List<int>.from(step);
      });
      ref.read(motionControllerProvider).moveTo(step);
      stepIdx++;
    });
  }

  void _runPickPlaceRoutine() async {
    _cancelRoutine();
    setState(() => _isRunningRoutine = true);
    HapticFeedback.mediumImpact();

    final steps = [
      [60, 60, 120, 60, 90, 160], // 1. Approach pick pos (open claw)
      [60, 60, 120, 60, 90, 20], // 2. Clamp object
      [60, 95, 80, 80, 90, 20], // 3. Lift object
      [125, 95, 80, 80, 90, 20], // 4. Rotate base to drop site
      [125, 60, 120, 60, 90, 20], // 5. Lower down
      [125, 60, 120, 60, 90, 160], // 6. Open claw (release)
      [125, 95, 80, 80, 90, 90], // 7. Lift clear
      [90, 90, 90, 90, 90, 90], // 8. Return Home
    ];

    int stepIdx = 0;
    _routineTimer = Timer.periodic(const Duration(milliseconds: 1050), (t) {
      if (stepIdx >= steps.length) {
        t.cancel();
        if (mounted) setState(() => _isRunningRoutine = false);
        return;
      }
      final step = steps[stepIdx];
      setState(() {
        _angles = List<int>.from(step);
      });
      ref.read(motionControllerProvider).moveTo(step);
      stepIdx++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final armState = ref.watch(armStateProvider);
    _syncFromArm(armState);

    final cal = ref.watch(calibrationProvider);
    final ikParams = ref.watch(ikParamsProvider);
    final connState =
        ref.watch(connectionStateProvider).valueOrNull ??
            BleConnectionState.idle;
    final isConnected = connState == BleConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Robotic Arm 3D'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00B04F).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF00B04F).withOpacity(0.5)),
              ),
              child: const Text(
                '6-AXIS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00E676),
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isExpandedViewport ? Icons.unfold_less : Icons.unfold_more,
            ),
            tooltip: _isExpandedViewport ? 'Compact 3D View' : 'Expand 3D View',
            onPressed: () {
              setState(() => _isExpandedViewport = !_isExpandedViewport);
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Calibration',
            onPressed: () =>
                Navigator.of(context).pushNamed('/calibration'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 3D Arm Visualizer Viewport ──────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            height: _isExpandedViewport ? 340 : 220,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ArmVisualizerWidget(
              armState: ArmState.fromAngles(_angles),
              params: ikParams,
              activeJoint: _activeJoint,
              onToggleGrip: _toggleGripper,
              onHome: _sendHome,
            ),
          ),

          // ── Routine Presets Bar ─────────────────────────────────────────
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PresetChip(
                  icon: Icons.home_outlined,
                  label: 'Home (90°)',
                  onPressed: isConnected ? _sendHome : null,
                ),
                const SizedBox(width: 6),
                _PresetChip(
                  icon: Icons.pinch,
                  label: (_angles[5] > 90) ? 'Close Claw' : 'Open Claw',
                  color: const Color(0xFF00B04F),
                  onPressed: isConnected ? _toggleGripper : null,
                ),
                const SizedBox(width: 6),
                _PresetChip(
                  icon: Icons.pan_tool_alt_outlined,
                  label: 'Reach',
                  onPressed: isConnected ? _runReachRoutine : null,
                ),
                const SizedBox(width: 6),
                _PresetChip(
                  icon: Icons.waving_hand_outlined,
                  label: 'Wave Demo',
                  isActive: _isRunningRoutine,
                  onPressed: isConnected ? _runWaveRoutine : null,
                ),
                const SizedBox(width: 6),
                _PresetChip(
                  icon: Icons.inventory_2_outlined,
                  label: 'Pick & Place',
                  isActive: _isRunningRoutine,
                  onPressed: isConnected ? _runPickPlaceRoutine : null,
                ),
                const SizedBox(width: 6),
                _PresetChip(
                  icon: Icons.bedtime_outlined,
                  label: 'Park / Rest',
                  onPressed: isConnected ? _runParkRoutine : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ── Stop / Home Bar ─────────────────────────────────────────────
          _StopHomeBar(
            onStop: isConnected ? _sendStop : null,
            onHome: isConnected ? _sendHome : null,
          ),

          const SizedBox(height: 6),

          // ── Joint Sliders with Micro-Step Controls ──────────────────────
          Expanded(
            child: ConnectionGuard(
              showOverlay: !isConnected,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                itemCount: 6,
                itemBuilder: (_, i) {
                  final jCal = cal.joints[i];
                  return _InteractiveJointCard(
                    index: i,
                    value: _angles[i].toDouble(),
                    min: jCal.minAngle.toDouble(),
                    max: jCal.maxAngle.toDouble(),
                    isActive: _activeJoint == i,
                    onChanged: isConnected ? (v) => _onSliderChange(i, v) : null,
                    onNudge: isConnected ? (delta) => _nudgeAngle(i, delta) : null,
                    onActive: () => setState(() => _activeJoint = i),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Preset Chip ─────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool isActive;

  const _PresetChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFF1E293B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF00E676).withOpacity(0.2)
                : effectiveColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF00E676)
                  : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive ? const Color(0xFF00E676) : Colors.white70,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive ? const Color(0xFF00E676) : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stop / Home Bar ─────────────────────────────────────────────────────────

class _StopHomeBar extends StatelessWidget {
  final VoidCallback? onStop;
  final VoidCallback? onHome;

  const _StopHomeBar({this.onStop, this.onHome});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              label: const Text('STOP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onHome,
              icon: const Icon(Icons.home_outlined, size: 20),
              label: const Text('HOME'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B04F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Interactive Joint Card with Micro-Step Jog Buttons ─────────────────────

class _InteractiveJointCard extends StatelessWidget {
  final int index;
  final double value;
  final double min;
  final double max;
  final bool isActive;
  final ValueChanged<double>? onChanged;
  final void Function(int delta)? onNudge;
  final VoidCallback onActive;

  const _InteractiveJointCard({
    required this.index,
    required this.value,
    required this.min,
    required this.max,
    required this.isActive,
    required this.onChanged,
    required this.onNudge,
    required this.onActive,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Palette with Bambu Green theme integration
    final jointColors = [
      [const Color(0xFF00B04F), const Color(0xFF10B981)], // Base
      [const Color(0xFF10B981), const Color(0xFF22C55E)], // Shoulder
      [const Color(0xFF22C55E), const Color(0xFF4ADE80)], // Elbow
      [const Color(0xFF00F0FF), const Color(0xFF0284C7)], // Wrist Pitch
      [const Color(0xFFA855F7), const Color(0xFF7C3AED)], // Wrist Rot
      [const Color(0xFFF59E0B), const Color(0xFFD97706)], // Gripper
    ];
    final colors = jointColors[index % jointColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? colors[0].withOpacity(0.12)
            : cs.surfaceContainerHighest.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? colors[0]
              : colors[0].withOpacity(0.25),
          width: isActive ? 1.8 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colors[0].withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon, Name, Joint ID, Angle Badge
          Row(
            children: [
              Text(
                kJointIcons[index],
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'J${index + 1}: ${kJointNames[index]}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
                ),
              ),
              const Spacer(),
              // Angle Value Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withOpacity(0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  '${value.round()}°',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colors[0],
              inactiveTrackColor: colors[0].withOpacity(0.2),
              thumbColor: colors[1],
              overlayColor: colors[1].withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: (v) {
                onActive();
                onChanged?.call(v);
              },
            ),
          ),

          // Micro-Step Buttons [-5°], [-1°], Limits, [+1°], [+5°]
          Row(
            children: [
              Text(
                '${min.round()}°',
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
              const Spacer(),
              _NudgeButton(
                label: '-5°',
                onPressed: onNudge != null ? () => onNudge!(-5) : null,
              ),
              const SizedBox(width: 4),
              _NudgeButton(
                label: '-1°',
                onPressed: onNudge != null ? () => onNudge!(-1) : null,
              ),
              const SizedBox(width: 8),
              _NudgeButton(
                label: '+1°',
                onPressed: onNudge != null ? () => onNudge!(1) : null,
              ),
              const SizedBox(width: 4),
              _NudgeButton(
                label: '+5°',
                onPressed: onNudge != null ? () => onNudge!(5) : null,
              ),
              const Spacer(),
              Text(
                '${max.round()}°',
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _NudgeButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
