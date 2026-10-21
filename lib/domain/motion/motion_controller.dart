// lib/domain/motion/motion_controller.dart
// 30 Hz control loop: smooth trajectory execution, rate limiting,
// exponential smoothing for live input, and BLE command coalescing.

import 'dart:async';
import 'dart:math' as math;

import '../../core/constants.dart';
import '../models/arm_state.dart';
import 'trajectory.dart';

/// Callback invoked with the current servo angles (0..180) to send to the arm.
typedef SendAnglesCallback = Future<void> Function(List<int> angles);

/// The motion controller drives the arm smoothly at 30 Hz.
///
/// Usage:
/// 1. Set [currentAngles] from the synced arm state.
/// 2. Call [moveTo] to start a trajectory to new target angles.
/// 3. Call [stopNow] to freeze.
/// 4. Call [goHome] to return to home angles.
/// 5. Dispose with [dispose].
class MotionController {
  MotionController({
    required this.onSendAngles,
    this.speedDegPerSec = 30.0,
  }) {
    _currentF = List<double>.from(
        kHomeAngles.map((a) => a.toDouble()));
  }

  /// Callback to send angles over BLE.
  final SendAnglesCallback onSendAngles;

  /// Desired movement speed in degrees/second (1..66).
  double speedDegPerSec;

  // Internal state
  late List<double> _currentF; // float angles, degrees
  JointTrajectory? _trajectory;
  DateTime? _trajStart;
  bool _running = false;
  Timer? _timer;
  List<int>? _lastSent;

  // Exponential smoothing factor for live (slider/joystick) input.
  final double _alpha = 0.3;
  List<double>? _smoothedTarget;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Current estimated servo angles (integer, 0..180).
  List<int> get currentAngles =>
      _currentF.map((a) => a.round().clamp(0, 180)).toList();

  /// Set current angles from synced state (on connect).
  void syncFrom(ArmState state) {
    _currentF = state.angles.map((a) => a.toDouble()).toList();
    _smoothedTarget = List<double>.from(_currentF);
  }

  /// Command: move to [targetAngles] with trajectory interpolation.
  void moveTo(List<int> targetAngles) {
    final targetF = targetAngles.map((a) => a.toDouble()).toList();
    _startTrajectory(targetF);
  }

  /// Command: live input (slider/joystick) – exponentially smooth then
  /// re-plan trajectory from current interpolated state.
  void liveInput(List<int> targetAngles) {
    final targetF = targetAngles.map((a) => a.toDouble()).toList();
    _smoothedTarget ??= List<double>.from(_currentF);
    for (int i = 0; i < 6; i++) {
      _smoothedTarget![i] =
          _alpha * targetF[i] + (1 - _alpha) * _smoothedTarget![i];
    }
    _startTrajectory(List<double>.from(_smoothedTarget!));
  }

  /// Command: freeze immediately at current interpolated position.
  void stopNow() {
    _trajectory = null;
    _trajStart = null;
    // Snap _currentF to the tick value.
  }

  /// Command: go to home position.
  void goHome() {
    moveTo(List<int>.from(kHomeAngles));
  }

  /// Start the 30 Hz control loop (call once after creation).
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / kControlHz).round()),
      _onTick,
    );
  }

  /// Stop the control loop and release resources.
  void dispose() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _startTrajectory(List<double> targetF) {
    // Sample current position from the active trajectory (if any).
    if (_trajectory != null && _trajStart != null) {
      final elapsed =
          DateTime.now().difference(_trajStart!).inMilliseconds.toDouble();
      _currentF = _trajectory!.sample(elapsed);
    }

    final maxDelta = List.generate(6, (i) {
      return (targetF[i] - _currentF[i]).abs();
    }).reduce(math.max);

    if (maxDelta < 0.5) return; // negligible move

    final duration = computeDuration(maxDelta, speedDegPerSec);
    _trajectory = JointTrajectory(
      startAngles: List<double>.from(_currentF),
      targetAngles: targetF,
      durationMs: duration,
    );
    _trajStart = DateTime.now();
  }

  void _onTick(Timer _) {
    if (!_running) return;

    List<double> angles;

    if (_trajectory != null && _trajStart != null) {
      final elapsed =
          DateTime.now().difference(_trajStart!).inMilliseconds.toDouble();
      angles = _trajectory!.sample(elapsed);
      _currentF = angles;

      if (_trajectory!.isComplete(elapsed)) {
        _currentF = List<double>.from(_trajectory!.targetAngles);
        _trajectory = null;
        _trajStart = null;
      }
    } else {
      angles = _currentF;
    }

    final intAngles = angles.map((a) => a.round().clamp(0, 180)).toList();

    // Only send if something changed.
    if (_lastSent != null) {
      bool changed = false;
      for (int i = 0; i < 6; i++) {
        if (intAngles[i] != _lastSent![i]) {
          changed = true;
          break;
        }
      }
      if (!changed) return;
    }

    _lastSent = List<int>.from(intAngles);
    onSendAngles(intAngles);
  }
}
