// test/kinematics_test.dart
// Unit tests for IK/FK round-trip, unreachable clamping, joint limit clamping.

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:robo_arm_ble/domain/kinematics/kinematics.dart';
import 'package:robo_arm_ble/domain/models/calibration.dart';
import 'package:robo_arm_ble/domain/models/ik_params.dart';

void main() {
  const params = IkParams(d1: 60, l1: 100, l2: 100, l3: 80);
  const kin = Kinematics(params);

  group('Forward Kinematics', () {
    test('Home position (all 90°) gives expected shoulder height', () {
      // All joints at 90° servo = 0° joint angle
      final rads = <double>[
        math.pi / 2, // base
        0.0, // shoulder
        0.0, // elbow
        0.0, // wrist
        0.0,
        0.0,
      ];
      final fk = kin.forwardKinematics(rads);
      // Shoulder should be at height d1 = 60mm
      expect(fk.shoulderPos.z, closeTo(60.0, 0.1));
    });

    test('Base angle at 0 rad: arm points along +X axis', () {
      final rads = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final fk = kin.forwardKinematics(rads);
      // With all angles 0 and base=0, elbow and wrist should be on X-Z plane
      expect(fk.elbowPos.y, closeTo(0.0, 0.01));
    });
  });

  group('Inverse Kinematics', () {
    test('IK then FK round-trip within 1.0mm for a reachable point', () {
      // A point we know is reachable
      const target = Vec3(150, 0, 80);
      const phi = 0.0;
      final result = kin.inverseKinematics(target, phi);
      expect(result.reachable, isTrue);

      final fk = kin.forwardKinematics(result.anglesRad);
      expect(fk.tipPos.x, closeTo(target.x, 1.0));
      expect(fk.tipPos.z, closeTo(target.z, 1.0));
    });

    test('IK clamps unreachable points and sets reachable=false', () {
      // Way out of reach
      const target = Vec3(500, 0, 0);
      final result = kin.inverseKinematics(target, 0.0);
      expect(result.reachable, isFalse);
      // Should still produce valid angles
      expect(result.anglesRad.length, equals(6));
    });

    test('IK round-trip accuracy for random reachable workspace points', () {
      final rand = math.Random(42);
      int passed = 0;
      const count = 20;

      for (int i = 0; i < count; i++) {
        // Pick reachable cylindrical coords: r ∈ [120, 220], z ∈ [20, 160], theta ∈ [-π/3, π/3]
        final r = 120.0 + rand.nextDouble() * 100.0;
        final theta = (rand.nextDouble() - 0.5) * (math.pi * 2 / 3);
        final z = 20.0 + rand.nextDouble() * 120.0;
        final x = r * math.cos(theta);
        final y = r * math.sin(theta);
        final target = Vec3(x, y, z);

        final ik = kin.inverseKinematics(target, 0.0);
        if (!ik.reachable) continue;

        final fk = kin.forwardKinematics(ik.anglesRad);
        final err = (fk.tipPos - target).length;
        if (err < 2.0) passed++;
      }

      expect(passed, greaterThanOrEqualTo(15),
          reason: 'At least 15 of 20 reachable points should have <2mm error');
    });

    test('Unreachable target: D clamped to [-1, 1]', () {
      const farTarget = Vec3(1000, 0, 0);
      final result = kin.inverseKinematics(farTarget, 0.0);
      // Angles should be finite (not NaN)
      for (final a in result.anglesRad) {
        expect(a.isFinite, isTrue,
            reason: 'Angle should be finite even for unreachable target');
      }
    });
  });

  group('Workspace', () {
    test('Point near max reach is reachable', () {
      final point = Vec3(params.l1 + params.l2 - 10, 0,
          params.d1);
      expect(kin.isReachable(point, 0.0), isTrue);
    });

    test('Point far beyond max reach is not reachable', () {
      final point = Vec3(params.l1 + params.l2 + params.l3 + 50, 0,
          params.d1);
      expect(kin.isReachable(point, 0.0), isFalse);
    });
  });

  group('Joint limit clamping (calibration)', () {
    test('Calibration apply clamps to min/max', () {
      const jcal = JointCalibration(minAngle: 30, maxAngle: 150);
      expect(jcal.apply(10), equals(30));
      expect(jcal.apply(170), equals(150));
      expect(jcal.apply(90), equals(90));
    });

    test('Calibration invert flips the value', () {
      const jcal = JointCalibration(
        minAngle: 0, maxAngle: 180, invert: true,
      );
      expect(jcal.apply(0), equals(180));
      expect(jcal.apply(180), equals(0));
      expect(jcal.apply(90), equals(90));
    });

    test('Calibration offset shifts value and clamps to 0..180', () {
      const jcal = JointCalibration(
        minAngle: 0, maxAngle: 180, offset: 10,
      );
      expect(jcal.apply(170), equals(180)); // 170+10=180, clamped
      expect(jcal.apply(90), equals(100));
    });
  });
}
