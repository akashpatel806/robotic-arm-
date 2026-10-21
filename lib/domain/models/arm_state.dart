// lib/domain/models/arm_state.dart
import 'package:flutter/foundation.dart';
import '../../core/constants.dart';

/// Immutable snapshot of the arm's joint angles (degrees, 0..180).
@immutable
class ArmState {
  final List<int> angles;
  final DateTime timestamp;

  const ArmState._({
    required this.angles,
    required this.timestamp,
  });

  factory ArmState.home() => ArmState._(
        angles: List<int>.from(kHomeAngles),
        timestamp: DateTime.now(),
      );

  factory ArmState.fromAngles(List<int> angles) {
    assert(angles.length == 6, 'ArmState requires exactly 6 angles');
    return ArmState._(
      angles: List<int>.from(angles.map((a) => a.clamp(0, 180))),
      timestamp: DateTime.now(),
    );
  }

  factory ArmState.fromBytes(List<int> bytes) {
    // Expects format: 'A' a0 a1 a2 a3 a4 a5
    if (bytes.length < 7 || bytes[0] != kCmdAck) {
      return ArmState.home();
    }
    return ArmState.fromAngles(bytes.sublist(1, 7));
  }

  int get base => angles[kJointBase];
  int get shoulder => angles[kJointShoulder];
  int get elbow => angles[kJointElbow];
  int get wristPitch => angles[kJointWristPitch];
  int get wristRot => angles[kJointWristRot];
  int get gripper => angles[kJointGripper];

  ArmState copyWith(List<int> newAngles) =>
      ArmState.fromAngles(newAngles);

  ArmState withJoint(int joint, int angle) {
    final a = List<int>.from(angles);
    a[joint] = angle.clamp(0, 180);
    return ArmState.fromAngles(a);
  }

  @override
  bool operator ==(Object other) =>
      other is ArmState && listEquals(angles, other.angles);

  @override
  int get hashCode => Object.hashAll(angles);

  @override
  String toString() => 'ArmState(${angles.join(', ')})';
}
