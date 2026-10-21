// lib/data/transport/simulated_transport.dart
import 'dart:async';
import 'dart:math' as math;

import '../../core/constants.dart';
import 'arm_transport.dart';

class SimulatedTransport implements ArmTransport {
  final StreamController<List<DiscoveredDevice>> _scanController =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final StreamController<BleConnectionState> _connController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<int>> _incomingController =
      StreamController<List<int>>.broadcast();

  BleConnectionState _state = BleConnectionState.idle;
  List<int> _angles = List<int>.from(kHomeAngles);
  Timer? _scanTimer;

  static const _fakeDevices = [
    DiscoveredDevice(
      id: 'SIM:AA:BB:CC:DD:EE:FF',
      name: 'RobotArm-BLE (Simulated)',
      rssi: -55,
    ),
    DiscoveredDevice(
      id: 'SIM:11:22:33:44:55:66',
      name: 'RobotArm-BLE (Sim 2)',
      rssi: -72,
    ),
  ];

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanController.stream;

  @override
  Stream<BleConnectionState> get connectionStateStream => _connController.stream;

  @override
  BleConnectionState get connectionState => _state;

  @override
  Stream<List<int>> get incomingStream => _incomingController.stream;

  @override
  Future<void> startScan() async {
    _setState(BleConnectionState.scanning);
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(milliseconds: 600), () {
      _scanController.add(_fakeDevices);
    });
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.idle);
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    _setState(BleConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _setState(BleConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _incomingController.add([kCmdAck, ..._angles]);
  }

  @override
  Future<void> disconnect() async {
    _setState(BleConnectionState.disconnected);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _setState(BleConnectionState.idle);
  }

  @override
  Future<void> sendAngles(List<int> angles) async {
    if (_state != BleConnectionState.connected) return;
    _angles = angles.map((a) => a.clamp(0, 180)).toList();
  }

  @override
  Future<void> sendHome() async {
    if (_state != BleConnectionState.connected) return;
    _angles = List<int>.from(kHomeAngles);
  }

  @override
  Future<void> requestState() async {
    if (_state != BleConnectionState.connected) return;
    final rng = math.Random();
    final jittered = _angles
        .map((a) => (a + rng.nextInt(3) - 1).clamp(0, 180))
        .toList();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _incomingController.add([kCmdAck, ...jittered]);
  }

  @override
  Future<void> sendSingleJoint(int channel, int angle) async {
    if (_state != BleConnectionState.connected) return;
    if (channel >= 0 && channel < 6) {
      _angles[channel] = angle.clamp(0, 180);
    }
  }

  void _setState(BleConnectionState s) {
    _state = s;
    _connController.add(s);
  }

  @override
  Future<void> dispose() async {
    _scanTimer?.cancel();
    await _scanController.close();
    await _connController.close();
    await _incomingController.close();
  }
}
