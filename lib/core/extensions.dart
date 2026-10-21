// lib/core/extensions.dart
import 'dart:math' as math;

extension DoubleExt on double {
  /// Clamp to [min, max] and return the clamped value.
  double clampDouble(double min, double max) =>
      this < min ? min : (this > max ? max : this);

  /// Convert radians to degrees.
  double get toDeg => this * 180.0 / math.pi;

  /// Convert degrees to radians.
  double get toRad => this * math.pi / 180.0;
}

extension IntExt on int {
  /// Clamp an integer angle to [0, 180].
  int clampAngle() => clamp(0, 180).toInt();
}

extension ListIntExt on List<int> {
  /// Clamp all servo angles to [0, 180].
  List<int> clampAngles() => map((a) => a.clamp(0, 180).toInt()).toList();

  /// True if every value equals the other list's corresponding value.
  bool equalsAngles(List<int> other) {
    if (length != other.length) return false;
    for (int i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}

extension ListDoubleExt on List<double> {
  List<double> clampTo(List<double> mins, List<double> maxs) {
    return List.generate(length,
        (i) => this[i].clampDouble(mins[i], maxs[i]));
  }
}
