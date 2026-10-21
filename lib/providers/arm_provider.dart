// lib/providers/arm_provider.dart
// Core Riverpod providers for transport, arm state, motion controller.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/storage/settings_storage.dart';
import '../data/storage/pose_storage.dart';
import '../data/transport/arm_transport.dart';
import '../data/transport/ble_transport.dart';
import '../data/transport/simulated_transport.dart';
import '../domain/models/arm_state.dart';
import '../domain/models/calibration.dart';
import '../domain/models/ik_params.dart';
import '../domain/models/pose.dart';
import '../domain/motion/motion_controller.dart';

// ── SharedPreferences ─────────────────────────────────────────────────────────

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

// ── Storage providers ─────────────────────────────────────────────────────────

final settingsStorageProvider =
    FutureProvider<SettingsStorage>((ref) async {
  final prefs = await ref.watch(sharedPrefsProvider.future);
  return SettingsStorage(prefs);
});

final poseStorageProvider = FutureProvider<PoseStorage>((ref) async {
  final prefs = await ref.watch(sharedPrefsProvider.future);
  return PoseStorage(prefs);
});

// ── Settings providers ────────────────────────────────────────────────────────

final simModeProvider = StateProvider<bool>((ref) {
  // Loaded synchronously from cached storage after first load.
  return false;
});

final darkModeProvider = StateProvider<bool>((ref) => true);

final speedFactorProvider = StateProvider<double>((ref) => 0.5);

final ikParamsProvider = StateProvider<IkParams>((ref) => const IkParams());

final calibrationProvider =
    StateProvider<ArmCalibration>((ref) => ArmCalibration.defaults());

// ── Transport provider ────────────────────────────────────────────────────────

final transportProvider = Provider<ArmTransport>((ref) {
  final simMode = ref.watch(simModeProvider);
  if (simMode) {
    final t = SimulatedTransport();
    ref.onDispose(() => t.dispose());
    return t;
  } else {
    final t = BleTransport();
    ref.onDispose(() => t.dispose());
    return t;
  }
});

// ── Connection state ──────────────────────────────────────────────────────────

final connectionStateProvider =
    StreamProvider<BleConnectionState>((ref) {
  final transport = ref.watch(transportProvider);
  return transport.connectionStateStream;
});

// ── Scan results ──────────────────────────────────────────────────────────────

final scanResultsProvider =
    StreamProvider<List<DiscoveredDevice>>((ref) {
  final transport = ref.watch(transportProvider);
  return transport.scanResults;
});

// ── Arm state ─────────────────────────────────────────────────────────────────

class ArmStateNotifier extends StateNotifier<ArmState> {
  ArmStateNotifier(this._transport) : super(ArmState.home()) {
    _sub = _transport.incomingStream.listen(_onData);
  }

  final ArmTransport _transport;
  StreamSubscription<List<int>>? _sub;

  void _onData(List<int> data) {
    if (data.isNotEmpty && data[0] == kCmdAck && data.length >= 7) {
      state = ArmState.fromBytes(data);
    }
  }

  void updateFrom(List<int> angles) {
    state = ArmState.fromAngles(angles);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final armStateProvider =
    StateNotifierProvider<ArmStateNotifier, ArmState>((ref) {
  final transport = ref.watch(transportProvider);
  return ArmStateNotifier(transport);
});

// ── Motion controller ─────────────────────────────────────────────────────────

final motionControllerProvider = Provider<MotionController>((ref) {
  final transport = ref.watch(transportProvider);
  final speedFactor = ref.watch(speedFactorProvider);
  final cal = ref.watch(calibrationProvider);

  final ctrl = MotionController(
    onSendAngles: (angles) async {
      final calibrated = cal.applyAll(angles);
      await transport.sendAngles(calibrated);
      ref.read(armStateProvider.notifier).updateFrom(angles);
    },
    speedDegPerSec: kFirmwareMaxDegPerSec * speedFactor,
  );
  ctrl.start();

  ref.onDispose(ctrl.dispose);
  return ctrl;
});

// ── Poses ─────────────────────────────────────────────────────────────────────

class PoseListNotifier extends StateNotifier<List<Pose>> {
  PoseListNotifier(this._storage) : super(_storage.loadPoses());
  final PoseStorage _storage;

  void add(Pose p) {
    state = [...state, p];
    _storage.savePoses(state);
  }

  void update(Pose p) {
    state = state.map((e) => e.id == p.id ? p : e).toList();
    _storage.savePoses(state);
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _storage.savePoses(state);
  }

  void reorder(int oldIdx, int newIdx) {
    final list = List<Pose>.from(state);
    final item = list.removeAt(oldIdx);
    list.insert(newIdx > oldIdx ? newIdx - 1 : newIdx, item);
    state = list;
    _storage.savePoses(state);
  }
}

final poseListProvider =
    StateNotifierProvider<PoseListNotifier, List<Pose>>((ref) {
  final storage = ref.watch(poseStorageProvider).value;
  if (storage == null) return PoseListNotifier(const PoseStorage.empty());
  return PoseListNotifier(storage);
});

// ── Sequences ─────────────────────────────────────────────────────────────────

class SequenceListNotifier extends StateNotifier<List<PoseSequence>> {
  SequenceListNotifier(this._storage)
      : super(_storage.loadSequences());
  final PoseStorage _storage;

  void add(PoseSequence s) {
    state = [...state, s];
    _storage.saveSequences(state);
  }

  void update(PoseSequence s) {
    state = state.map((e) => e.id == s.id ? s : e).toList();
    _storage.saveSequences(state);
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _storage.saveSequences(state);
  }
}

final sequenceListProvider =
    StateNotifierProvider<SequenceListNotifier, List<PoseSequence>>((ref) {
  final storage = ref.watch(poseStorageProvider).value;
  if (storage == null) return SequenceListNotifier(const PoseStorage.empty());
  return SequenceListNotifier(storage);
});

// ── Sequence player state ─────────────────────────────────────────────────────

enum PlaybackState { stopped, playing, paused }

class SequencePlayerNotifier extends StateNotifier<PlaybackState> {
  SequencePlayerNotifier() : super(PlaybackState.stopped);

  PoseSequence? _sequence;
  int _poseIndex = 0;
  Timer? _timer;
  MotionController? _controller;
  bool _confirmed = false;

  void attach(MotionController ctrl) => _controller = ctrl;

  void play(PoseSequence seq, {bool confirmed = false}) {
    if (!confirmed && !_confirmed) {
      // First play: caller should confirm
      return;
    }
    _confirmed = true;
    _sequence = seq;
    _poseIndex = 0;
    state = PlaybackState.playing;
    _playNext();
  }

  void confirm() => _confirmed = true;

  void pause() {
    _timer?.cancel();
    if (state == PlaybackState.playing) state = PlaybackState.paused;
  }

  void resume() {
    if (state == PlaybackState.paused && _sequence != null) {
      state = PlaybackState.playing;
      _playNext();
    }
  }

  void stop() {
    _timer?.cancel();
    _controller?.stopNow();
    state = PlaybackState.stopped;
    _sequence = null;
    _poseIndex = 0;
    _confirmed = false;
  }

  void _playNext() {
    final seq = _sequence;
    if (seq == null || state != PlaybackState.playing) return;

    if (_poseIndex >= seq.poses.length) {
      if (seq.loop) {
        _poseIndex = 0;
      } else {
        stop();
        return;
      }
    }

    final pose = seq.poses[_poseIndex];
    _controller?.moveTo(pose.angles);
    _poseIndex++;

    // Schedule next after hold time
    final holdMs = pose.holdMs;
    _timer = Timer(Duration(milliseconds: holdMs + 1000), _playNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sequencePlayerProvider =
    StateNotifierProvider<SequencePlayerNotifier, PlaybackState>((ref) {
  final notifier = SequencePlayerNotifier();
  final ctrl = ref.watch(motionControllerProvider);
  notifier.attach(ctrl);
  return notifier;
});

// ── IK target state ───────────────────────────────────────────────────────────

class IkTargetNotifier extends StateNotifier<Map<String, double>> {
  IkTargetNotifier()
      : super({'x': 150.0, 'y': 0.0, 'z': 100.0, 'phi': 0.0});

  void setX(double v) => state = {...state, 'x': v};
  void setY(double v) => state = {...state, 'y': v};
  void setZ(double v) => state = {...state, 'z': v};
  void setPhi(double v) => state = {...state, 'phi': v};

  void setXY(double x, double y) => state = {...state, 'x': x, 'y': y};
}

final ikTargetProvider =
    StateNotifierProvider<IkTargetNotifier, Map<String, double>>(
        (ref) => IkTargetNotifier());
