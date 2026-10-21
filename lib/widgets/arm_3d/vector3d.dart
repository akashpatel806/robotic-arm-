// lib/widgets/arm_3d/vector3d.dart
// Lightweight, high-performance 3D vector & matrix library for CustomPainter rendering.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class Vec3D {
  final double x;
  final double y;
  final double z;

  const Vec3D(this.x, this.y, this.z);

  static const zero = Vec3D(0, 0, 0);

  Vec3D operator +(Vec3D o) => Vec3D(x + o.x, y + o.y, z + o.z);
  Vec3D operator -(Vec3D o) => Vec3D(x - o.x, y - o.y, z - o.z);
  Vec3D operator *(double s) => Vec3D(x * s, y * s, z * s);
  Vec3D operator /(double s) => Vec3D(x / s, y / s, z / s);
  Vec3D operator -() => Vec3D(-x, -y, -z);

  double dot(Vec3D o) => x * o.x + y * o.y + z * o.z;

  Vec3D cross(Vec3D o) => Vec3D(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3D normalized() {
    final len = length;
    if (len < 1e-6) return const Vec3D(0, 1, 0);
    return Vec3D(x / len, y / len, z / len);
  }

  @override
  String toString() => 'Vec3D(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, ${z.toStringAsFixed(1)})';
}

class Mat4 {
  final List<double> m; // 16 elements column-major

  Mat4._(this.m);

  factory Mat4.identity() {
    return Mat4._([
      1, 0, 0, 0, // col 0
      0, 1, 0, 0, // col 1
      0, 0, 1, 0, // col 2
      0, 0, 0, 1, // col 3
    ]);
  }

  factory Mat4.translation(double tx, double ty, double tz) {
    return Mat4._([
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      tx, ty, tz, 1,
    ]);
  }

  factory Mat4.rotationX(double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Mat4._([
      1, 0, 0, 0,
      0, c, s, 0,
      0, -s, c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.rotationY(double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Mat4._([
      c, 0, -s, 0,
      0, 1, 0, 0,
      s, 0, c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.rotationZ(double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Mat4._([
      c, s, 0, 0,
      -s, c, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.scale(double sx, double sy, double sz) {
    return Mat4._([
      sx, 0, 0, 0,
      0, sy, 0, 0,
      0, 0, sz, 0,
      0, 0, 0, 1,
    ]);
  }

  Mat4 multiply(Mat4 o) {
    final r = List<double>.filled(16, 0.0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double sum = 0.0;
        for (int k = 0; k < 4; k++) {
          sum += m[k * 4 + i] * o.m[j * 4 + k];
        }
        r[j * 4 + i] = sum;
      }
    }
    return Mat4._(r);
  }

  Mat4 operator *(Mat4 o) => multiply(o);

  Vec3D transformPoint(Vec3D p) {
    final rx = m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12];
    final ry = m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13];
    final rz = m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14];
    final rw = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15];
    if (rw != 0.0 && rw != 1.0) {
      return Vec3D(rx / rw, ry / rw, rz / rw);
    }
    return Vec3D(rx, ry, rz);
  }

  Vec3D transformDirection(Vec3D d) {
    final rx = m[0] * d.x + m[4] * d.y + m[8] * d.z;
    final ry = m[1] * d.x + m[5] * d.y + m[9] * d.z;
    final rz = m[2] * d.x + m[6] * d.y + m[10] * d.z;
    return Vec3D(rx, ry, rz).normalized();
  }
}

/// Represents a 3D polygon face for rasterization with shading and depth sorting.
class PolyFace {
  final List<Vec3D> worldVertices;
  final List<Vec3D> viewVertices;
  final Vec3D worldNormal;
  final double depth; // camera space Z for painter's algorithm
  final Color baseColor;
  final bool isMetallic;
  final bool hasOutline;
  final Color? outlineColor;
  final int? jointId; // If highlighted
  final bool isGlowing;

  const PolyFace({
    required this.worldVertices,
    required this.viewVertices,
    required this.worldNormal,
    required this.depth,
    required this.baseColor,
    this.isMetallic = false,
    this.hasOutline = false,
    this.outlineColor,
    this.jointId,
    this.isGlowing = false,
  });
}
