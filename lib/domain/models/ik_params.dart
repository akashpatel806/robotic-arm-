// lib/domain/models/ik_params.dart
import '../../core/constants.dart';

/// Link lengths and base height for the 4-DOF arm kinematics.
class IkParams {
  /// Base height (mm) – vertical offset from ground to shoulder joint.
  final double d1;

  /// Link 1 length (mm) – shoulder to elbow.
  final double l1;

  /// Link 2 length (mm) – elbow to wrist.
  final double l2;

  /// Link 3 length (mm) – wrist to gripper tip.
  final double l3;

  const IkParams({
    this.d1 = kDefaultD1,
    this.l1 = kDefaultL1,
    this.l2 = kDefaultL2,
    this.l3 = kDefaultL3,
  });

  /// Maximum reach (ignoring d1): l1 + l2 + l3.
  double get maxReach => l1 + l2 + l3;

  /// Minimum reach (rough) for elbow-up config.
  double get minReach => (l1 - l2).abs();

  IkParams copyWith({double? d1, double? l1, double? l2, double? l3}) =>
      IkParams(
        d1: d1 ?? this.d1,
        l1: l1 ?? this.l1,
        l2: l2 ?? this.l2,
        l3: l3 ?? this.l3,
      );

  Map<String, dynamic> toJson() => {
        'd1': d1,
        'l1': l1,
        'l2': l2,
        'l3': l3,
      };

  factory IkParams.fromJson(Map<String, dynamic> j) => IkParams(
        d1: (j['d1'] as num?)?.toDouble() ?? kDefaultD1,
        l1: (j['l1'] as num?)?.toDouble() ?? kDefaultL1,
        l2: (j['l2'] as num?)?.toDouble() ?? kDefaultL2,
        l3: (j['l3'] as num?)?.toDouble() ?? kDefaultL3,
      );
}
