// test/motion_test.dart
// Unit tests for minimum-jerk profile and trajectory.

import 'package:flutter_test/flutter_test.dart';
import 'package:robo_arm_ble/domain/motion/trajectory.dart';

void main() {
  const profile = MinJerkProfile();

  group('MinJerkProfile', () {
    test('s(0) = 0', () {
      expect(profile.position(0.0), closeTo(0.0, 1e-9));
    });

    test('s(1) = 1', () {
      expect(profile.position(1.0), closeTo(1.0, 1e-9));
    });

    test('velocity at t=0 is 0 (zero start velocity)', () {
      expect(profile.velocity(0.0), closeTo(0.0, 1e-9));
    });

    test('velocity at t=1 is 0 (zero end velocity)', () {
      expect(profile.velocity(1.0), closeTo(0.0, 1e-9));
    });

    test('position is monotonically increasing for t in [0,1]', () {
      double prev = profile.position(0.0);
      for (int i = 1; i <= 100; i++) {
        final cur = profile.position(i / 100.0);
        expect(cur, greaterThanOrEqualTo(prev - 1e-9));
        prev = cur;
      }
    });

    test('clamps t < 0 to position 0', () {
      expect(profile.position(-0.5), closeTo(0.0, 1e-9));
    });

    test('clamps t > 1 to position 1', () {
      expect(profile.position(1.5), closeTo(1.0, 1e-9));
    });
  });

  group('JointTrajectory', () {
    final start = [0.0, 90.0, 90.0, 90.0, 90.0, 90.0];
    final target = [90.0, 90.0, 90.0, 90.0, 90.0, 90.0];

    test('At t=0: returns start angles', () {
      final traj = JointTrajectory(
        startAngles: start,
        targetAngles: target,
        durationMs: 1000,
      );
      final sampled = traj.sample(0);
      expect(sampled[0], closeTo(0.0, 0.01));
    });

    test('At t=duration: returns target angles', () {
      final traj = JointTrajectory(
        startAngles: start,
        targetAngles: target,
        durationMs: 1000,
      );
      final sampled = traj.sample(1000);
      expect(sampled[0], closeTo(90.0, 0.01));
    });

    test('isComplete returns false mid-trajectory', () {
      final traj = JointTrajectory(
        startAngles: start,
        targetAngles: target,
        durationMs: 1000,
      );
      expect(traj.isComplete(500), isFalse);
    });

    test('isComplete returns true at or after duration', () {
      final traj = JointTrajectory(
        startAngles: start,
        targetAngles: target,
        durationMs: 1000,
      );
      expect(traj.isComplete(1000), isTrue);
      expect(traj.isComplete(1200), isTrue);
    });

    test('Mid-trajectory value is between start and target', () {
      final traj = JointTrajectory(
        startAngles: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        targetAngles: [180.0, 180.0, 180.0, 180.0, 180.0, 180.0],
        durationMs: 2000,
      );
      final mid = traj.sample(1000);
      for (final v in mid) {
        expect(v, greaterThan(0));
        expect(v, lessThan(180));
      }
    });
  });

  group('computeDuration', () {
    test('Large delta → longer duration at slow speed', () {
      final slow = computeDuration(90, 10);
      final fast = computeDuration(90, 60);
      expect(slow, greaterThan(fast));
    });

    test('Zero delta → 50ms floor', () {
      expect(computeDuration(0, 30), closeTo(50.0, 0.1));
    });

    test('Duration floored at 50ms', () {
      expect(computeDuration(0.1, 66), greaterThanOrEqualTo(50));
    });

    test('Speed capped at 66 deg/s', () {
      final d1 = computeDuration(66, 66);
      final d2 = computeDuration(66, 200); // over limit
      expect(d1, closeTo(d2, 1.0));
    });
  });
}
