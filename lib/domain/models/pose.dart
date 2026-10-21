// lib/domain/models/pose.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// A named snapshot of the arm's 6 joint angles.
@immutable
class Pose {
  final String id;
  final String name;
  final List<int> angles; // 6 values, 0..180
  final double speedFactor; // 0.1..1.0
  final int holdMs; // milliseconds to hold before next pose

  const Pose({
    required this.id,
    required this.name,
    required this.angles,
    this.speedFactor = 0.5,
    this.holdMs = 500,
  });

  Pose copyWith({
    String? name,
    List<int>? angles,
    double? speedFactor,
    int? holdMs,
  }) =>
      Pose(
        id: id,
        name: name ?? this.name,
        angles: angles ?? this.angles,
        speedFactor: speedFactor ?? this.speedFactor,
        holdMs: holdMs ?? this.holdMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'angles': angles,
        'speedFactor': speedFactor,
        'holdMs': holdMs,
      };

  factory Pose.fromJson(Map<String, dynamic> j) => Pose(
        id: j['id'] as String,
        name: j['name'] as String,
        angles: List<int>.from(j['angles'] as List),
        speedFactor: (j['speedFactor'] as num?)?.toDouble() ?? 0.5,
        holdMs: (j['holdMs'] as int?) ?? 500,
      );

  @override
  bool operator ==(Object other) =>
      other is Pose && id == other.id && listEquals(angles, other.angles);

  @override
  int get hashCode => id.hashCode;
}

/// An ordered sequence of poses with loop setting.
class PoseSequence {
  final String id;
  final String name;
  final List<Pose> poses;
  final bool loop;

  const PoseSequence({
    required this.id,
    required this.name,
    required this.poses,
    this.loop = false,
  });

  PoseSequence copyWith({
    String? name,
    List<Pose>? poses,
    bool? loop,
  }) =>
      PoseSequence(
        id: id,
        name: name ?? this.name,
        poses: poses ?? this.poses,
        loop: loop ?? this.loop,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'poses': poses.map((p) => p.toJson()).toList(),
        'loop': loop,
      };

  factory PoseSequence.fromJson(Map<String, dynamic> j) => PoseSequence(
        id: j['id'] as String,
        name: j['name'] as String,
        poses: (j['poses'] as List)
            .map((e) => Pose.fromJson(e as Map<String, dynamic>))
            .toList(),
        loop: (j['loop'] as bool?) ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  factory PoseSequence.fromJsonString(String s) =>
      PoseSequence.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
