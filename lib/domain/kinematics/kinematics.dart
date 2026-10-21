// lib/domain/kinematics/kinematics.dart
// Pure-Dart kinematics: forward kinematics (FK), inverse kinematics (IK),
// angle <-> servo mapping, and workspace validation.
// No Flutter dependencies; fully unit-testable.

import 'dart:math' as math;
import '../models/ik_params.dart';
import '../models/calibration.dart';

// ── Cartesian point ──────────────────────────────────────────────────────────

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);

  double get length => math.sqrt(x * x + y * y + z * z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

// ── IK result ────────────────────────────────────────────────────────────────

class IkResult {
  /// Joint angles in radians: [theta0, theta1, theta2, theta3, 0, 0]
  /// (wristRot and gripper are unchanged in IK mode).
  final List<double> anglesRad;

  /// Whether the target was reachable without clamping.
  final bool reachable;

  /// The actual (possibly clamped) tip position.
  final Vec3 actualTip;

  const IkResult({
    required this.anglesRad,
    required this.reachable,
    required this.actualTip,
  });
}

// ── FK result ────────────────────────────────────────────────────────────────

class FkResult {
  final Vec3 shoulderPos;
  final Vec3 elbowPos;
  final Vec3 wristPos;
  final Vec3 tipPos;

  const FkResult({
    required this.shoulderPos,
    required this.elbowPos,
    required this.wristPos,
    required this.tipPos,
  });
}

// ── Kinematics engine ────────────────────────────────────────────────────────

class Kinematics {
  final IkParams params;

  const Kinematics(this.params);

  // ── Forward Kinematics ───────────────────────────────────────────────────

  /// Compute forward kinematics from joint angles (radians).
  /// angles: [theta0_base, theta1_shoulder, theta2_elbow, theta3_wristPitch, ...]
  FkResult forwardKinematics(List<double> anglesRad) {
    final t0 = anglesRad[0]; // base rotation (about Z)
    final t1 = anglesRad[1]; // shoulder elevation
    final t2 = anglesRad[2]; // elbow
    final t3 = anglesRad[3]; // wrist pitch

    // Shoulder is at height d1.
    final shoulder = Vec3(0, 0, params.d1);

    // In the vertical plane at angle t0:
    // Elbow position relative to shoulder
    final elbowR = params.l1 * math.cos(t1);
    final elbowZ = params.l1 * math.sin(t1);
    final elbow = Vec3(
      shoulder.x + elbowR * math.cos(t0),
      shoulder.y + elbowR * math.sin(t0),
      shoulder.z + elbowZ,
    );

    // Wrist position relative to elbow
    final t12 = t1 + t2; // cumulative angle
    final wristR = params.l2 * math.cos(t12);
    final wristZ = params.l2 * math.sin(t12);
    final wrist = Vec3(
      elbow.x + wristR * math.cos(t0),
      elbow.y + wristR * math.sin(t0),
      elbow.z + wristZ,
    );

    // Tip position relative to wrist
    final t123 = t12 + t3;
    final tipR = params.l3 * math.cos(t123);
    final tipZ = params.l3 * math.sin(t123);
    final tip = Vec3(
      wrist.x + tipR * math.cos(t0),
      wrist.y + tipR * math.sin(t0),
      wrist.z + tipZ,
    );

    return FkResult(
      shoulderPos: shoulder,
      elbowPos: elbow,
      wristPos: wrist,
      tipPos: tip,
    );
  }

  // ── Inverse Kinematics ───────────────────────────────────────────────────

  /// Compute IK for target tip position [target] with desired wrist pitch [phi]
  /// (radians, measured from horizontal).
  /// Returns null angles if completely unreachable (shouldn't happen after clamping).
  IkResult inverseKinematics(Vec3 target, double phi) {
    final x = target.x, y = target.y, z = target.z;

    // Base rotation
    final theta0 = math.atan2(y, x);

    // Horizontal distance from base axis
    final r = math.sqrt(x * x + y * y);

    // Height above shoulder plane
    final zPrime = z - params.d1;

    // Wrist centre (subtract L3 contribution along wrist axis direction)
    final rw = r - params.l3 * math.cos(phi);
    final zw = zPrime - params.l3 * math.sin(phi);

    // Two-link planar IK (Law of Cosines)
    final distSq = rw * rw + zw * zw;
    final dist = math.sqrt(distSq);

    double dVal =
        (distSq - params.l1 * params.l1 - params.l2 * params.l2) /
            (2 * params.l1 * params.l2);

    bool reachable = true;
    Vec3 actualTip = target;

    if (dVal > 1.0 || dVal < -1.0) {
      // Clamp to reachable boundary
      reachable = false;
      dVal = dVal.clamp(-1.0, 1.0);
      // Scale rw/zw to lie on the boundary
      final maxDist = dVal > 0
          ? params.l1 + params.l2 // fully extended
          : (params.l1 - params.l2).abs(); // fully folded
      final scale = maxDist / (dist == 0 ? 1 : dist);
      final rwC = rw * scale;
      final zwC = zw * scale;
      actualTip = _tipFromWristCenter(theta0, rwC, zwC, phi);
    }

    // Elbow-up solution: positive sqrt
    final theta2 = math.atan2(math.sqrt(1 - dVal * dVal), dVal);
    final theta1 = math.atan2(zw, rw) -
        math.atan2(
          params.l2 * math.sin(theta2),
          params.l1 + params.l2 * math.cos(theta2),
        );
    final theta3 = phi - theta1 - theta2;

    return IkResult(
      anglesRad: [theta0, theta1, theta2, theta3, 0, 0],
      reachable: reachable,
      actualTip: actualTip,
    );
  }

  Vec3 _tipFromWristCenter(double theta0, double rw, double zw, double phi) {
    final r = rw + params.l3 * math.cos(phi);
    final zPrime = zw + params.l3 * math.sin(phi);
    return Vec3(r * math.cos(theta0), r * math.sin(theta0),
        zPrime + params.d1);
  }

  // ── Angle mapping ────────────────────────────────────────────────────────

  /// Map IK joint angles (radians) to servo angles (degrees, 0..180).
  /// Servo 0 = base: 0°→0 servo, 180°→180 servo (linear).
  /// Servos 1-3: neutral is 90°, +angle maps to >90.
  List<int> anglesRadToServo(List<double> anglesRad,
      ArmCalibration cal) {
    // Joint servo mappings (raw degrees before calibration):
    // theta0 (base) is 0..180 rad mapped to 0..180
    // theta1, theta2, theta3 are roughly -π/2..π/2; map to 0..180 centred at 90
    List<double> rawDeg = [
      _radToServo180(anglesRad[0], -math.pi / 2, math.pi / 2),
      _radToServo180(anglesRad[1], -math.pi / 2, math.pi / 2),
      _radToServo180(anglesRad[2], -math.pi / 2, math.pi / 2),
      _radToServo180(anglesRad[3], -math.pi / 2, math.pi / 2),
      90.0, // wrist rot: unaffected by IK
      90.0, // gripper: unaffected by IK
    ];
    final ints = rawDeg.map((d) => d.round().clamp(0, 180)).toList();
    return cal.applyAll(ints);
  }

  /// Map servo angle (degrees 0..180) to joint angle (radians).
  List<double> servoToAnglesRad(List<int> servoDeg, ArmCalibration cal) {
    // Reverse calibration first (not implemented fully, simplified)
    final reversed = List<int>.from(servoDeg);
    return List.generate(6, (i) {
      return _servoToRad(reversed[i].toDouble(), -math.pi / 2, math.pi / 2);
    });
  }

  double _radToServo180(double rad, double minRad, double maxRad) {
    final t = (rad - minRad) / (maxRad - minRad);
    return (t * 180.0).clamp(0.0, 180.0);
  }

  double _servoToRad(double servo, double minRad, double maxRad) {
    final t = servo / 180.0;
    return minRad + t * (maxRad - minRad);
  }

  // ── Workspace check ──────────────────────────────────────────────────────

  /// Returns true if a point is within the reachable workspace.
  bool isReachable(Vec3 point, double phi) {
    final x = point.x, y = point.y, z = point.z;
    final r = math.sqrt(x * x + y * y);
    final zPrime = z - params.d1;
    final rw = r - params.l3 * math.cos(phi);
    final zw = zPrime - params.l3 * math.sin(phi);
    final d = (rw * rw + zw * zw - params.l1 * params.l1 - params.l2 * params.l2) /
        (2 * params.l1 * params.l2);
    return d.abs() <= 1.0;
  }

  /// Maximum horizontal reach from the base axis.
  double get maxHorizontalReach => params.l1 + params.l2 + params.l3;
}
