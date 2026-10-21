// lib/domain/motion/trajectory.dart
// Pure-Dart minimum-jerk trajectory profile and joint-space interpolation.

import 'dart:math' as math;

/// Minimum-jerk normalized profile: s(t) = 10t³ − 15t⁴ + 6t⁵, t ∈ [0,1].
/// Guarantees zero velocity and acceleration at start and end.
class MinJerkProfile {
  const MinJerkProfile();

  /// Evaluate position at normalized time [t] ∈ [0,1].
  double position(double t) {
    final tc = t.clamp(0.0, 1.0);
    return 10 * _pow3(tc) - 15 * _pow4(tc) + 6 * _pow5(tc);
  }

  /// Evaluate velocity (ds/dt) at normalized time [t].
  double velocity(double t) {
    final tc = t.clamp(0.0, 1.0);
    return 30 * _pow2(tc) - 60 * _pow3(tc) + 30 * _pow4(tc);
  }

  double _pow2(double x) => x * x;
  double _pow3(double x) => x * x * x;
  double _pow4(double x) => x * x * x * x;
  double _pow5(double x) => x * x * x * x * x;
}

/// A joint-space trajectory from [startAngles] to [targetAngles].
class JointTrajectory {
  final List<double> startAngles; // degrees (float)
  final List<double> targetAngles; // degrees (float)
  final double durationMs;
  final MinJerkProfile _profile;

  JointTrajectory({
    required this.startAngles,
    required this.targetAngles,
    required this.durationMs,
  }) : _profile = const MinJerkProfile();

  /// Sample the trajectory at elapsed time [elapsedMs].
  /// Returns interpolated angles in degrees.
  List<double> sample(double elapsedMs) {
    final t = durationMs > 0
        ? (elapsedMs / durationMs).clamp(0.0, 1.0)
        : 1.0;
    final s = _profile.position(t);
    return List.generate(
      startAngles.length,
      (i) => startAngles[i] + (targetAngles[i] - startAngles[i]) * s,
    );
  }

  bool isComplete(double elapsedMs) => elapsedMs >= durationMs;
}

/// Compute trajectory duration given the maximum joint change and speed factor.
///
/// [maxDelta]     maximum angular change across all joints (degrees).
/// [speedDegPerS] desired speed (deg/s). Capped to [kFirmwareMaxDegPerSec].
double computeDuration(double maxDelta, double speedDegPerS) {
  const firmwareMax = 66.0;
  final speed = speedDegPerS.clamp(1.0, firmwareMax);
  final ms = (math.max(0.0, maxDelta) / speed) * 1000.0;
  return math.max(ms, 50.0); // floor at 50 ms
}
