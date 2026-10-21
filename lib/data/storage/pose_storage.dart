// lib/data/storage/pose_storage.dart
// Local JSON persistence for poses and sequences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../domain/models/pose.dart';

class PoseStorage {
  final SharedPreferences? _prefs;
  const PoseStorage([this._prefs]);
  const PoseStorage.empty() : _prefs = null;

  static Future<PoseStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PoseStorage(prefs);
  }

  // ── Poses ───────────────────────────────────────────────────────────────────

  List<Pose> loadPoses() {
    final s = _prefs?.getString(kPrefPoses);
    if (s == null) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) => Pose.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePoses(List<Pose> poses) async {
    await _prefs?.setString(
      kPrefPoses,
      jsonEncode(poses.map((p) => p.toJson()).toList()),
    );
  }

  // ── Sequences ───────────────────────────────────────────────────────────────

  static const _kSeqKey = 'sequences_json';

  List<PoseSequence> loadSequences() {
    final s = _prefs?.getString(_kSeqKey);
    if (s == null) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) => PoseSequence.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSequences(List<PoseSequence> seqs) async {
    await _prefs?.setString(
      _kSeqKey,
      jsonEncode(seqs.map((s) => s.toJson()).toList()),
    );
  }
}
