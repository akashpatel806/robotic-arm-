// lib/widgets/arm_3d/arm_mesh_builder.dart
// Builds accurate 3D geometry matching the user's Bambu green 3D-printed robotic arm.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'vector3d.dart';

class ArmMeshBuilder {
  // Palette matching user's Bambu Lab green PLA 3D model
  static const Color bambuGreen = Color(0xFF00B04F);
  static const Color bambuGreenDark = Color(0xFF007A37);
  static const Color bambuGreenLight = Color(0xFF1DD668);
  static const Color servoBlack = Color(0xFF1E293B);
  static const Color servoDark = Color(0xFF0F172A);
  static const Color metallicBolt = Color(0xFFD1D5DB);
  static const Color metallicGear = Color(0xFF38A169);
  static const Color accentCyan = Color(0xFF00F0FF);
  static const Color gripPad = Color(0xFF10B981);

  final List<double> servoDegrees; // [Base, Shoulder, Elbow, WristPitch, WristRot, Gripper]
  final int? activeJoint; // Highlighted joint index 0..5
  final Mat4 viewMatrix;

  ArmMeshBuilder({
    required this.servoDegrees,
    this.activeJoint,
    required this.viewMatrix,
  });

  /// Build all polygonal faces sorted for depth rendering
  List<PolyFace> buildFaces() {
    final List<PolyFace> faces = [];

    // Servo angles
    final double degBase = servoDegrees.isNotEmpty ? servoDegrees[0] : 90;
    final double degShoulder = servoDegrees.length > 1 ? servoDegrees[1] : 90;
    final double degElbow = servoDegrees.length > 2 ? servoDegrees[2] : 90;
    final double degWristPitch = servoDegrees.length > 3 ? servoDegrees[3] : 90;
    final double degWristRot = servoDegrees.length > 4 ? servoDegrees[4] : 90;
    final double degGripper = servoDegrees.length > 5 ? servoDegrees[5] : 90;

    // Convert to relative joint radians
    // Base: 0..180 -> -PI/2..+PI/2 rotation around Y (turntable)
    final double radBase = ((degBase - 90) / 180.0) * math.pi;

    // Shoulder: 0..180 -> -PI/2..+PI/2 pitch around X
    final double radShoulder = -((degShoulder - 90) / 180.0) * math.pi;

    // Elbow: 0..180 -> -PI/2..+PI/2 pitch around X
    final double radElbow = -((degElbow - 90) / 180.0) * math.pi;

    // Wrist Pitch: 0..180 -> pitch around X
    final double radWristPitch = -((degWristPitch - 90) / 180.0) * math.pi;

    // Wrist Roll: 0..180 -> roll around Z / Y
    final double radWristRot = ((degWristRot - 90) / 180.0) * math.pi;

    // Gripper: 0..180 -> claw opening 0 (fully closed) to 1.0 (fully open)
    final double gripFactor = (degGripper / 180.0).clamp(0.0, 1.0);

    // ── 0. Bambu Textured PEI Bed Plate ─────────────────────────────────────
    _buildBedPlate(faces);

    // ── 1. Static Base Flange ───────────────────────────────────────────────
    _buildBaseFlange(faces);

    // ── 2. Rotating Turntable & Base Cylinder (Joint 0) ──────────────────────
    final Mat4 mBase = Mat4.translation(0, 0, 0) * Mat4.rotationY(radBase);
    _buildTurntable(faces, mBase, isHighlighted: activeJoint == 0);

    // ── 3. Shoulder Bracket & Servo Motor (Joint 0 frame) ───────────────────
    const double shoulderHeight = 52.0;
    final Mat4 mShoulderPivot = mBase * Mat4.translation(0, shoulderHeight, 0);
    _buildShoulderBracket(faces, mShoulderPivot, isHighlighted: activeJoint == 1);

    // ── 4. Upper Arm / Bicep (Joint 1: Shoulder Pitch) ───────────────────────
    final Mat4 mUpperArm = mShoulderPivot * Mat4.rotationX(radShoulder);
    _buildUpperArm(faces, mUpperArm, isHighlighted: activeJoint == 1);

    // ── 5. Forearm Link & Elbow Servo (Joint 2: Elbow Pitch) ────────────────
    const double bicepLength = 105.0; // Length along upper arm
    // Notice curvature offset
    final Mat4 mElbowPivot = mUpperArm * Mat4.translation(0, bicepLength, 0);
    _buildElbowJointAndServo(faces, mElbowPivot, isHighlighted: activeJoint == 2);

    final Mat4 mForearm = mElbowPivot * Mat4.rotationX(radElbow);
    _buildForearm(faces, mForearm, isHighlighted: activeJoint == 2);

    // ── 6. Wrist Pitch & Roll Assembly (Joint 3 & 4) ────────────────────────
    const double forearmLength = 95.0;
    final Mat4 mWristPitchPivot = mForearm * Mat4.translation(0, forearmLength, 0);
    _buildWristPitchJoint(faces, mWristPitchPivot, isHighlighted: activeJoint == 3);

    final Mat4 mWristPitch = mWristPitchPivot * Mat4.rotationX(radWristPitch);
    final Mat4 mWristRotPivot = mWristPitch * Mat4.translation(0, 22.0, 0);
    _buildWristRotCollar(faces, mWristRotPivot, isHighlighted: activeJoint == 4);

    final Mat4 mWristAssembly = mWristRotPivot * Mat4.rotationY(radWristRot);

    // ── 7. Geared 2-Finger Gripper Mechanism (Joint 5) ───────────────────────
    _buildGearedGripper(faces, mWristAssembly, gripFactor, isHighlighted: activeJoint == 5);

    // Sort polygons by depth (Back-to-Front: farthest Z first)
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    return faces;
  }

  // ── 3D Geometry Helpers ───────────────────────────────────────────────────

  void _addQuad(
    List<PolyFace> faces,
    Vec3D p0,
    Vec3D p1,
    Vec3D p2,
    Vec3D p3, {
    required Color color,
    int? jointId,
    bool isHighlighted = false,
    bool isMetallic = false,
    bool hasOutline = false,
    Color? outlineColor,
  }) {
    // Transform vertices to view space
    final v0 = viewMatrix.transformPoint(p0);
    final v1 = viewMatrix.transformPoint(p1);
    final v2 = viewMatrix.transformPoint(p2);
    final v3 = viewMatrix.transformPoint(p3);

    // Normal calculation in world space
    final edge1 = p1 - p0;
    final edge2 = p2 - p0;
    final normal = edge1.cross(edge2).normalized();

    // Average camera depth
    final avgDepth = (v0.z + v1.z + v2.z + v3.z) * 0.25;

    final displayColor = isHighlighted ? _highlightColor(color) : color;

    faces.add(PolyFace(
      worldVertices: [p0, p1, p2, p3],
      viewVertices: [v0, v1, v2, v3],
      worldNormal: normal,
      depth: avgDepth,
      baseColor: displayColor,
      isMetallic: isMetallic,
      hasOutline: hasOutline,
      outlineColor: outlineColor,
      jointId: jointId,
      isGlowing: isHighlighted,
    ));
  }

  void _addTriangle(
    List<PolyFace> faces,
    Vec3D p0,
    Vec3D p1,
    Vec3D p2, {
    required Color color,
    int? jointId,
    bool isHighlighted = false,
    bool isMetallic = false,
    bool hasOutline = false,
    Color? outlineColor,
  }) {
    final v0 = viewMatrix.transformPoint(p0);
    final v1 = viewMatrix.transformPoint(p1);
    final v2 = viewMatrix.transformPoint(p2);

    final edge1 = p1 - p0;
    final edge2 = p2 - p0;
    final normal = edge1.cross(edge2).normalized();

    final avgDepth = (v0.z + v1.z + v2.z) / 3.0;
    final displayColor = isHighlighted ? _highlightColor(color) : color;

    faces.add(PolyFace(
      worldVertices: [p0, p1, p2],
      viewVertices: [v0, v1, v2],
      worldNormal: normal,
      depth: avgDepth,
      baseColor: displayColor,
      isMetallic: isMetallic,
      hasOutline: hasOutline,
      outlineColor: outlineColor,
      jointId: jointId,
      isGlowing: isHighlighted,
    ));
  }

  Color _highlightColor(Color base) {
    return Color.lerp(base, const Color(0xFF00F0FF), 0.65)!;
  }

  /// Add a 3D box (prism) transformed by matrix M
  void _addBox(
    List<PolyFace> faces,
    Mat4 m,
    double dx,
    double dy,
    double dz, {
    required Color color,
    int? jointId,
    bool isHighlighted = false,
    bool isMetallic = false,
  }) {
    final hx = dx / 2;
    final hy = dy / 2;
    final hz = dz / 2;

    // 8 box vertices in local space
    final p0 = m.transformPoint(Vec3D(-hx, -hy, -hz));
    final p1 = m.transformPoint(Vec3D(hx, -hy, -hz));
    final p2 = m.transformPoint(Vec3D(hx, hy, -hz));
    final p3 = m.transformPoint(Vec3D(-hx, hy, -hz));
    final p4 = m.transformPoint(Vec3D(-hx, -hy, hz));
    final p5 = m.transformPoint(Vec3D(hx, -hy, hz));
    final p6 = m.transformPoint(Vec3D(hx, hy, hz));
    final p7 = m.transformPoint(Vec3D(-hx, hy, hz));

    // Front (Z+)
    _addQuad(faces, p4, p5, p6, p7, color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    // Back (Z-)
    _addQuad(faces, p1, p0, p3, p2, color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    // Top (Y+)
    _addQuad(faces, p3, p2, p6, p7, color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    // Bottom (Y-)
    _addQuad(faces, p0, p1, p5, p4, color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    // Right (X+)
    _addQuad(faces, p1, p5, p6, p2, color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    // Left (X-)
    _addQuad(faces, p4, p0, p3, p7, color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
  }

  /// Add a 3D cylinder along Y axis transformed by matrix M
  void _addCylinderY(
    List<PolyFace> faces,
    Mat4 m,
    double radius,
    double height, {
    required Color color,
    int segments = 12,
    int? jointId,
    bool isHighlighted = false,
    bool isMetallic = false,
  }) {
    final halfH = height / 2;
    final List<Vec3D> topRing = [];
    final List<Vec3D> btmRing = [];

    for (int i = 0; i < segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      final x = radius * math.cos(angle);
      final z = radius * math.sin(angle);
      topRing.add(m.transformPoint(Vec3D(x, halfH, z)));
      btmRing.add(m.transformPoint(Vec3D(x, -halfH, z)));
    }

    final topCenter = m.transformPoint(Vec3D(0, halfH, 0));
    final btmCenter = m.transformPoint(Vec3D(0, -halfH, 0));

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      // Side quad
      _addQuad(faces, btmRing[i], btmRing[next], topRing[next], topRing[i],
          color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
      // Top cap triangle
      _addTriangle(faces, topCenter, topRing[i], topRing[next],
          color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
      // Bottom cap triangle
      _addTriangle(faces, btmCenter, btmRing[next], btmRing[i],
          color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    }
  }

  /// Add a 3D cylinder along X axis (for joint pivots and bearing hubs)
  void _addCylinderX(
    List<PolyFace> faces,
    Mat4 m,
    double radius,
    double length, {
    required Color color,
    int segments = 10,
    int? jointId,
    bool isHighlighted = false,
    bool isMetallic = false,
  }) {
    final halfL = length / 2;
    final List<Vec3D> leftRing = [];
    final List<Vec3D> rightRing = [];

    for (int i = 0; i < segments; i++) {
      final angle = (i / segments) * 2 * math.pi;
      final y = radius * math.cos(angle);
      final z = radius * math.sin(angle);
      leftRing.add(m.transformPoint(Vec3D(-halfL, y, z)));
      rightRing.add(m.transformPoint(Vec3D(halfL, y, z)));
    }

    final leftCenter = m.transformPoint(Vec3D(-halfL, 0, 0));
    final rightCenter = m.transformPoint(Vec3D(halfL, 0, 0));

    for (int i = 0; i < segments; i++) {
      final next = (i + 1) % segments;
      _addQuad(faces, leftRing[i], rightRing[i], rightRing[next], leftRing[next],
          color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
      _addTriangle(faces, rightCenter, rightRing[i], rightRing[next],
          color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
      _addTriangle(faces, leftCenter, leftRing[next], leftRing[i],
          color: color, jointId: jointId, isHighlighted: isHighlighted, isMetallic: isMetallic);
    }
  }

  // ── Arm Components ────────────────────────────────────────────────────────

  /// Bambu Textured PEI plate
  void _buildBedPlate(List<PolyFace> faces) {
    const size = 180.0;
    const y = -1.0;
    final m = Mat4.identity();

    // Plate top surface
    final p0 = m.transformPoint(const Vec3D(-size, y, -size));
    final p1 = m.transformPoint(const Vec3D(size, y, -size));
    final p2 = m.transformPoint(const Vec3D(size, y, size));
    final p3 = m.transformPoint(const Vec3D(-size, y, size));

    _addQuad(faces, p3, p2, p1, p0,
        color: const Color(0xFF1E2124), hasOutline: true, outlineColor: const Color(0xFF32383E));

    // Plate edge thickness
    _addBox(faces, Mat4.translation(0, y - 2, 0), size * 2, 3.5, size * 2,
        color: const Color(0xFF14171A));

    // Plate alignment tab (Bambu style)
    _addBox(faces, Mat4.translation(0, y, size + 8), 45, 2, 16,
        color: const Color(0xFF2B3036));

    // 4 Corner green markers (like Bambu plate calibration lines)
    _addBox(faces, Mat4.translation(-size + 20, y + 0.2, -size + 20), 12, 0.4, 12,
        color: const Color(0xFF10B981));
    _addBox(faces, Mat4.translation(size - 20, y + 0.2, -size + 20), 12, 0.4, 12,
        color: const Color(0xFF10B981));
  }

  /// Base mounting flange with 4 screw holes
  void _buildBaseFlange(List<PolyFace> faces) {
    final mFlange = Mat4.translation(0, 3, 0);
    // Base outer flange disc
    _addCylinderY(faces, mFlange, 62.0, 5.0, color: bambuGreenDark, segments: 16);

    // 4 Mounting screw holes / bolts
    for (int i = 0; i < 4; i++) {
      final angle = (i * math.pi / 2) + (math.pi / 4);
      final bx = 52.0 * math.cos(angle);
      final bz = 52.0 * math.sin(angle);
      _addCylinderY(faces, Mat4.translation(bx, 5.5, bz), 3.2, 1.2,
          color: metallicBolt, segments: 6, isMetallic: true);
    }
  }

  /// Cylindrical waist and rotating turntable (Joint 0)
  void _buildTurntable(List<PolyFace> faces, Mat4 mBase, {required bool isHighlighted}) {
    // Lower cylindrical pedestal
    _addCylinderY(faces, Mat4.translation(0, 18, 0), 48.0, 26.0,
        color: bambuGreen, segments: 16, jointId: 0, isHighlighted: isHighlighted);

    // Turntable rotating ring (moves with mBase)
    _addCylinderY(faces, mBase * Mat4.translation(0, 32, 0), 45.0, 6.0,
        color: bambuGreenLight, segments: 16, jointId: 0, isHighlighted: isHighlighted);

    // Cable notch cutout indicator
    _addBox(faces, Mat4.translation(0, 12, 47), 10, 8, 4,
        color: const Color(0xFF0F172A));
  }

  /// Shoulder Bracket & Servo Motor (Joint 1 pivot point)
  void _buildShoulderBracket(List<PolyFace> faces, Mat4 mPivot, {required bool isHighlighted}) {
    // Dual mounting clevis forks on the turntable
    // Right fork
    _addBox(faces, mPivot * Mat4.translation(18, -12, 0), 8, 30, 32,
        color: bambuGreen, jointId: 1, isHighlighted: isHighlighted);
    // Left fork
    _addBox(faces, mPivot * Mat4.translation(-18, -12, 0), 8, 30, 32,
        color: bambuGreen, jointId: 1, isHighlighted: isHighlighted);

    // Horizontal turntable cross-tie
    _addBox(faces, mPivot * Mat4.translation(0, -22, 0), 42, 8, 34,
        color: bambuGreenDark, jointId: 1, isHighlighted: isHighlighted);

    // Shoulder Servo Motor Housing on the left side (prominent in user's image 3)
    _addBox(faces, mPivot * Mat4.translation(-28, -6, 2), 14, 28, 22,
        color: servoBlack, jointId: 1, isHighlighted: isHighlighted, isMetallic: true);

    // Shoulder Pivot Bearing hubs (round caps on both sides)
    _addCylinderX(faces, mPivot * Mat4.translation(22, 0, 0), 13.0, 4.0,
        color: bambuGreenLight, segments: 12, jointId: 1, isHighlighted: isHighlighted);
    _addCylinderX(faces, mPivot * Mat4.translation(24, 0, 0), 5.0, 2.0,
        color: metallicBolt, segments: 8, isMetallic: true);
  }

  /// Upper Arm (Bicep) - Curved boom link with channeled structure & cable clips
  void _buildUpperArm(List<PolyFace> faces, Mat4 mArm, {required bool isHighlighted}) {
    // The user's upper arm has a distinctive forward-curved, channeled industrial shape!
    // We construct it with segmented curved sections from shoulder (0,0,0) to elbow (0, 105, 0).
    const int segments = 6;
    const double totalLength = 105.0;

    for (int i = 0; i < segments; i++) {
      final t = i / segments;
      final tNext = (i + 1) / segments;

      final y1 = t * totalLength;
      final y2 = tNext * totalLength;

      // Subtle forward curvature arc (parabolic offset in Z)
      final z1 = math.sin(t * math.pi) * 14.0;
      final z2 = math.sin(tNext * math.pi) * 14.0;

      // Width tapering
      final w1 = 28.0 - t * 4.0;
      final w2 = 28.0 - tNext * 4.0;

      final pMid = Vec3D(0, (y1 + y2) / 2, (z1 + z2) / 2);
      final dy = y2 - y1;
      final dz = z2 - z1;
      final linkAngle = math.atan2(dz, dy);

      final mSeg = mArm *
          Mat4.translation(pMid.x, pMid.y, pMid.z) *
          Mat4.rotationX(-linkAngle);

      // Main structural arm spine
      _addBox(faces, mSeg, (w1 + w2) / 2, dy + 1.5, 20.0,
          color: bambuGreen, jointId: 1, isHighlighted: isHighlighted);

      // Inner hollowed channel ribbing
      if (i >= 1 && i <= 4) {
        _addBox(faces, mSeg * Mat4.translation(0, 0, -8.5), (w1 + w2) / 2 - 6, dy, 4.0,
            color: bambuGreenDark, jointId: 1, isHighlighted: isHighlighted);
      }
    }

    // Shoulder end hub boss
    _addCylinderX(faces, mArm * Mat4.translation(0, 0, 0), 16.0, 26.0,
        color: bambuGreen, segments: 12, jointId: 1, isHighlighted: isHighlighted);

    // Cable clips along arm spine (visible in image 4)
    _addBox(faces, mArm * Mat4.translation(12, 45, 14), 5, 8, 7,
        color: bambuGreenDark);
    _addBox(faces, mArm * Mat4.translation(12, 75, 11), 5, 8, 7,
        color: bambuGreenDark);
  }

  /// Elbow Joint Pivot & Servo Motor Box
  void _buildElbowJointAndServo(List<PolyFace> faces, Mat4 mElbow, {required bool isHighlighted}) {
    // Elbow circular pivot hub
    _addCylinderX(faces, mElbow * Mat4.translation(0, 0, 0), 15.0, 28.0,
        color: bambuGreen, segments: 12, jointId: 2, isHighlighted: isHighlighted);

    // Elbow servo motor casing attached on the side (seen prominently in images 1, 3)
    _addBox(faces, mElbow * Mat4.translation(22, -6, 6), 16, 28, 22,
        color: servoBlack, jointId: 2, isHighlighted: isHighlighted, isMetallic: true);

    // Pivot bearing cap & center screw
    _addCylinderX(faces, mElbow * Mat4.translation(-15, 0, 0), 12.0, 3.0,
        color: bambuGreenLight, segments: 10, jointId: 2, isHighlighted: isHighlighted);
    _addCylinderX(faces, mElbow * Mat4.translation(-16, 0, 0), 5.0, 2.0,
        color: metallicBolt, segments: 8, isMetallic: true);
  }

  /// Forearm Link - Houses wrist servo compartment
  void _buildForearm(List<PolyFace> faces, Mat4 mForearm, {required bool isHighlighted}) {
    const double length = 95.0;

    // Base of forearm link
    _addBox(faces, mForearm * Mat4.translation(0, length * 0.42, 0), 24.0, length * 0.84, 20.0,
        color: bambuGreen, jointId: 2, isHighlighted: isHighlighted);

    // Wrist servo box integrated inside forearm (image 3)
    _addBox(faces, mForearm * Mat4.translation(0, 52, 4), 18, 26, 18,
        color: servoBlack, jointId: 2, isHighlighted: isHighlighted, isMetallic: true);

    // Tapered end bracket toward wrist
    _addBox(faces, mForearm * Mat4.translation(0, length - 6, 0), 20.0, 14.0, 16.0,
        color: bambuGreenDark, jointId: 2, isHighlighted: isHighlighted);
  }

  /// Wrist Pitch Joint (Joint 3)
  void _buildWristPitchJoint(List<PolyFace> faces, Mat4 mWrist, {required bool isHighlighted}) {
    // Wrist pivot clevis fork
    _addCylinderX(faces, mWrist * Mat4.translation(0, 0, 0), 10.0, 22.0,
        color: bambuGreen, segments: 10, jointId: 3, isHighlighted: isHighlighted);
    _addCylinderX(faces, mWrist * Mat4.translation(12, 0, 0), 4.0, 2.0,
        color: metallicBolt, segments: 6, isMetallic: true);
  }

  /// Wrist Roll Rotational Collar (Joint 4)
  void _buildWristRotCollar(List<PolyFace> faces, Mat4 mWristRot, {required bool isHighlighted}) {
    // Cylindrical twist collar
    _addCylinderY(faces, mWristRot * Mat4.translation(0, 0, 0), 12.0, 16.0,
        color: bambuGreenLight, segments: 12, jointId: 4, isHighlighted: isHighlighted);

    // Gripper mount flange
    _addBox(faces, mWristRot * Mat4.translation(0, 9, 0), 28, 4, 24,
        color: bambuGreenDark, jointId: 4, isHighlighted: isHighlighted);
  }

  /// Geared 2-Finger Gripper Mechanism (Joint 5)
  /// Features dual intermeshing spur gears, 4-bar parallel linkages, and curved claw jaws!
  void _buildGearedGripper(List<PolyFace> faces, Mat4 mMount, double gripFactor, {required bool isHighlighted}) {
    // Base plate of the gripper mechanism
    final mGripperBase = mMount * Mat4.translation(0, 12, 0);
    _addBox(faces, mGripperBase, 36, 6, 26,
        color: bambuGreen, jointId: 5, isHighlighted: isHighlighted);

    // Small servo block driving the gripper
    _addBox(faces, mGripperBase * Mat4.translation(0, -6, -8), 16, 16, 18,
        color: servoBlack, jointId: 5, isHighlighted: isHighlighted, isMetallic: true);

    // Gripper claw opening angle:
    // gripFactor: 0.0 (fully closed/pinched) to 1.0 (fully open)
    // Angular rotation of gears: 0 rad (closed) to 0.75 rad (~43 degrees open)
    final double gearRot = gripFactor * 0.78; // Left gear rotates +gearRot, Right gear rotates -gearRot
    const double gearCenterDist = 8.5; // Half-distance between gear centers

    // ── Left Drive Gear & Linkage ──
    final mLeftGear = mGripperBase *
        Mat4.translation(-gearCenterDist, 5, 0) *
        Mat4.rotationZ(gearRot);

    // Left Gear Disc & Teeth
    _buildSpurGear(faces, mLeftGear, radius: 10.0, thickness: 3.5, teeth: 10,
        color: metallicGear, jointId: 5, isHighlighted: isHighlighted);

    // ── Right Driven Gear (Meshes with Left Gear, counter-rotates!) ──
    final mRightGear = mGripperBase *
        Mat4.translation(gearCenterDist, 5, 0) *
        Mat4.rotationZ(-gearRot + (math.pi / 10)); // Offset for meshing teeth!

    // Right Gear Disc & Teeth
    _buildSpurGear(faces, mRightGear, radius: 10.0, thickness: 3.5, teeth: 10,
        color: metallicGear, jointId: 5, isHighlighted: isHighlighted);

    // Center pivot screw pins on both gears
    _addCylinderY(faces, mGripperBase * Mat4.translation(-gearCenterDist, 7.5, 0), 2.2, 2.0,
        color: metallicBolt, segments: 6, isMetallic: true);
    _addCylinderY(faces, mGripperBase * Mat4.translation(gearCenterDist, 7.5, 0), 2.2, 2.0,
        color: metallicBolt, segments: 6, isMetallic: true);

    // ── 4-Bar Parallel Linkage & Claws ──
    // Left Claw Assembly
    _buildClawArm(
      faces,
      baseMatrix: mGripperBase,
      gearAngle: gearRot,
      isLeft: true,
      isHighlighted: isHighlighted,
    );

    // Right Claw Assembly (Symmetric)
    _buildClawArm(
      faces,
      baseMatrix: mGripperBase,
      gearAngle: -gearRot,
      isLeft: false,
      isHighlighted: isHighlighted,
    );
  }

  /// Builds a detailed spur gear with teeth
  void _buildSpurGear(
    List<PolyFace> faces,
    Mat4 mGear, {
    required double radius,
    required double thickness,
    required int teeth,
    required Color color,
    int? jointId,
    bool isHighlighted = false,
  }) {
    // Gear core disc
    _addCylinderY(faces, mGear, radius * 0.85, thickness,
        color: color, segments: 14, jointId: jointId, isHighlighted: isHighlighted);

    // Gear teeth around perimeter
    for (int i = 0; i < teeth; i++) {
      final angle = (i / teeth) * 2 * math.pi;
      final tx = radius * math.cos(angle);
      final tz = radius * math.sin(angle);
      final mTooth = mGear *
          Mat4.translation(tx, 0, tz) *
          Mat4.rotationY(-angle);
      _addBox(faces, mTooth, 2.8, thickness, 3.2,
          color: bambuGreenDark, jointId: jointId, isHighlighted: isHighlighted);
    }
  }

  /// Builds one side of the 2-finger claw mechanism (gear link, parallel stabilizer link, and curved claw jaw)
  void _buildClawArm(
    List<PolyFace> faces, {
    required Mat4 baseMatrix,
    required double gearAngle,
    required bool isLeft,
    required bool isHighlighted,
  }) {
    final double sideSign = isLeft ? -1.0 : 1.0;
    final double gearCenter = sideSign * 8.5;

    // Primary Drive Link connected to gear
    // Pivot at gear center, rotates by gearAngle
    final mDriveLink = baseMatrix *
        Mat4.translation(gearCenter, 6, 0) *
        Mat4.rotationZ(gearAngle) *
        Mat4.translation(sideSign * 10, 10, 0);

    _addBox(faces, mDriveLink, 4.0, 20.0, 3.0,
        color: bambuGreenLight, jointId: 5, isHighlighted: isHighlighted);

    // Secondary parallel stabilizer link (attached at base bracket offset)
    final mStabLink = baseMatrix *
        Mat4.translation(sideSign * 16, 6, 0) *
        Mat4.rotationZ(gearAngle * 0.9) *
        Mat4.translation(sideSign * 6, 12, 0);

    _addBox(faces, mStabLink, 3.0, 18.0, 2.5,
        color: bambuGreenDark, jointId: 5, isHighlighted: isHighlighted);

    // Claw Finger (Curved Jaw)
    // The jaw sits at the end of the linkage
    // Finger curves inwards towards center
    final mFingerBase = baseMatrix *
        Mat4.translation(gearCenter + sideSign * (10 + math.sin(gearAngle.abs()) * 14), 26, 0) *
        Mat4.rotationZ(gearAngle * 0.45);

    // Main finger body
    _addBox(faces, mFingerBase * Mat4.translation(0, 12, 0), 6.0, 24.0, 5.0,
        color: bambuGreen, jointId: 5, isHighlighted: isHighlighted);

    // Curved claw tip (pointed slightly inward)
    final mTip = mFingerBase *
        Mat4.translation(-sideSign * 4, 25, 0) *
        Mat4.rotationZ(-sideSign * 0.45);

    _addBox(faces, mTip, 5.0, 14.0, 4.0,
        color: bambuGreenLight, jointId: 5, isHighlighted: isHighlighted);

    // Gripping silicone / textured pad on the inside face of the claw
    _addBox(faces, mFingerBase * Mat4.translation(-sideSign * 3.2, 12, 0), 1.5, 18.0, 4.5,
        color: gripPad, jointId: 5, isHighlighted: isHighlighted);

    // Pivot pin dots
    _addCylinderY(faces, mFingerBase * Mat4.translation(0, 0, 0), 1.8, 5.5,
        color: metallicBolt, segments: 6, isMetallic: true);
  }
}
