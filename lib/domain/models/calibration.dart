// lib/domain/models/calibration.dart
import 'dart:convert';
import '../../core/constants.dart';

/// Per-joint calibration: min/max limits, invert flag, offset in degrees.
class JointCalibration {
  final int minAngle;
  final int maxAngle;
  final bool invert;
  final int offset; // degrees added before sending to servo

  const JointCalibration({
    this.minAngle = 0,
    this.maxAngle = 180,
    this.invert = false,
    this.offset = 0,
  });

  /// Apply calibration: clamp to limits, invert, add offset.
  int apply(int rawAngle) {
    int a = rawAngle.clamp(minAngle, maxAngle);
    if (invert) a = minAngle + maxAngle - a;
    a = (a + offset).clamp(0, 180);
    return a;
  }

  /// Reverse calibration (for display): remove offset, invert.
  int reverse(int servoAngle) {
    int a = (servoAngle - offset).clamp(0, 180);
    if (invert) a = (minAngle + maxAngle - a).clamp(0, 180);
    return a;
  }

  JointCalibration copyWith({
    int? minAngle,
    int? maxAngle,
    bool? invert,
    int? offset,
  }) =>
      JointCalibration(
        minAngle: minAngle ?? this.minAngle,
        maxAngle: maxAngle ?? this.maxAngle,
        invert: invert ?? this.invert,
        offset: offset ?? this.offset,
      );

  Map<String, dynamic> toJson() => {
        'minAngle': minAngle,
        'maxAngle': maxAngle,
        'invert': invert,
        'offset': offset,
      };

  factory JointCalibration.fromJson(Map<String, dynamic> j) =>
      JointCalibration(
        minAngle: (j['minAngle'] as int?) ?? 0,
        maxAngle: (j['maxAngle'] as int?) ?? 180,
        invert: (j['invert'] as bool?) ?? false,
        offset: (j['offset'] as int?) ?? 0,
      );
}

/// All 6 joints' calibrations.
class ArmCalibration {
  final List<JointCalibration> joints;

  ArmCalibration(this.joints) : assert(joints.length == 6);

  factory ArmCalibration.defaults() => ArmCalibration(
        List.generate(6, (i) {
          final lim = kDefaultJointLimits[i];
          return JointCalibration(minAngle: lim[0], maxAngle: lim[1]);
        }),
      );

  ArmCalibration withJoint(int index, JointCalibration cal) {
    final list = List<JointCalibration>.from(joints);
    list[index] = cal;
    return ArmCalibration(list);
  }

  /// Apply calibration to all angles.
  List<int> applyAll(List<int> raw) =>
      List.generate(6, (i) => joints[i].apply(raw[i]));

  String toJsonString() =>
      jsonEncode(joints.map((j) => j.toJson()).toList());

  factory ArmCalibration.fromJsonString(String s) {
    final list = jsonDecode(s) as List;
    return ArmCalibration(
      list.map((e) => JointCalibration.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
