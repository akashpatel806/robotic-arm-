// lib/data/storage/settings_storage.dart
// SharedPreferences wrapper for all app settings.

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../domain/models/calibration.dart';
import '../../domain/models/ik_params.dart';

class SettingsStorage {
  final SharedPreferences _prefs;
  const SettingsStorage(this._prefs);

  static Future<SettingsStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStorage(prefs);
  }

  // ── Last device ─────────────────────────────────────────────────────────────
  String? get lastDeviceId => _prefs.getString(kPrefLastDeviceId);
  Future<void> saveLastDeviceId(String id) =>
      _prefs.setString(kPrefLastDeviceId, id);
  Future<void> clearLastDeviceId() => _prefs.remove(kPrefLastDeviceId);

  // ── Simulation mode ─────────────────────────────────────────────────────────
  bool get simMode => _prefs.getBool(kPrefSimMode) ?? false;
  Future<void> setSimMode(bool v) => _prefs.setBool(kPrefSimMode, v);

  // ── Theme ───────────────────────────────────────────────────────────────────
  bool get darkMode => _prefs.getBool(kPrefDarkMode) ?? true;
  Future<void> setDarkMode(bool v) => _prefs.setBool(kPrefDarkMode, v);

  // ── Speed factor (0.1..1.0) ─────────────────────────────────────────────────
  double get speedFactor => _prefs.getDouble(kPrefSpeedFactor) ?? 0.5;
  Future<void> setSpeedFactor(double v) =>
      _prefs.setDouble(kPrefSpeedFactor, v);

  // ── IK link lengths ─────────────────────────────────────────────────────────
  IkParams loadIkParams() => IkParams(
        d1: _prefs.getDouble(kPrefD1) ?? kDefaultD1,
        l1: _prefs.getDouble(kPrefL1) ?? kDefaultL1,
        l2: _prefs.getDouble(kPrefL2) ?? kDefaultL2,
        l3: _prefs.getDouble(kPrefL3) ?? kDefaultL3,
      );

  Future<void> saveIkParams(IkParams p) async {
    await _prefs.setDouble(kPrefD1, p.d1);
    await _prefs.setDouble(kPrefL1, p.l1);
    await _prefs.setDouble(kPrefL2, p.l2);
    await _prefs.setDouble(kPrefL3, p.l3);
  }

  // ── Calibration ─────────────────────────────────────────────────────────────
  ArmCalibration loadCalibration() {
    final s = _prefs.getString(kPrefCalibration);
    if (s == null) return ArmCalibration.defaults();
    try {
      return ArmCalibration.fromJsonString(s);
    } catch (_) {
      return ArmCalibration.defaults();
    }
  }

  Future<void> saveCalibration(ArmCalibration cal) =>
      _prefs.setString(kPrefCalibration, cal.toJsonString());
}
