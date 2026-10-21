// lib/data/transport/ble_transport.dart
// flutter_blue_plus implementation of ArmTransport.

import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../../core/constants.dart';
import 'arm_transport.dart';

class BleTransport implements ArmTransport {
  // ── Scan state ─────────────────────────────────────────────────────────────
  final StreamController<List<DiscoveredDevice>> _scanController =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final Map<String, DiscoveredDevice> _foundDevices = {};

  // ── Connection state ───────────────────────────────────────────────────────
  final StreamController<BleConnectionState> _connController =
      StreamController<BleConnectionState>.broadcast();
  BleConnectionState _state = BleConnectionState.idle;

  // ── Incoming data ──────────────────────────────────────────────────────────
  final StreamController<List<int>> _incomingController =
      StreamController<List<int>>.broadcast();

  // ── BLE handles ───────────────────────────────────────────────────────────
  fbp.BluetoothDevice? _device;
  fbp.BluetoothCharacteristic? _rxChar;
  fbp.BluetoothCharacteristic? _txChar;
  StreamSubscription<fbp.BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<fbp.ScanResult>>? _scanSub;

  // Reconnect state
  int _reconnectAttempts = 0;
  String? _lastDeviceId;
  Timer? _reconnectTimer;

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanController.stream;

  @override
  Stream<BleConnectionState> get connectionStateStream => _connController.stream;

  @override
  BleConnectionState get connectionState => _state;

  @override
  Stream<List<int>> get incomingStream => _incomingController.stream;

  // ── Scanning ───────────────────────────────────────────────────────────────

  @override
  Future<void> startScan() async {
    _foundDevices.clear();
    _setState(BleConnectionState.scanning);

    _scanSub?.cancel();
    await fbp.FlutterBluePlus.stopScan();

    _scanSub = fbp.FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        final hasService = r.advertisementData.serviceUuids.any(
          (uuid) =>
              uuid.toString().toUpperCase() == kServiceUUID.toUpperCase(),
        );
        if (!hasService && name != kDeviceName) continue;
        _foundDevices[r.device.remoteId.str] = DiscoveredDevice(
          id: r.device.remoteId.str,
          name: name.isNotEmpty ? name : 'Unknown',
          rssi: r.rssi,
        );
      }
      _scanController.add(_foundDevices.values.toList());
    });

    await fbp.FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withNames: [kDeviceName],
    );
  }

  @override
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.idle);
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  @override
  Future<void> connect(String deviceId) async {
    _lastDeviceId = deviceId;
    _reconnectAttempts = 0;
    await _doConnect(deviceId);
  }

  Future<void> _doConnect(String deviceId) async {
    _setState(BleConnectionState.connecting);
    try {
      final remoteId = fbp.DeviceIdentifier(deviceId);
      _device = fbp.BluetoothDevice(remoteId: remoteId);

      _connSub?.cancel();
      _connSub = _device!.connectionState.listen(_onConnectionStateChange);

      await _device!.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      if (Platform.isAndroid) {
        await _device!.requestMtu(512);
      }

      await _discoverServices();
      _reconnectAttempts = 0;
      _setState(BleConnectionState.connected);
    } catch (e) {
      _scheduleReconnect();
    }
  }

  Future<void> _discoverServices() async {
    if (_device == null) return;
    final services = await _device!.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toUpperCase() ==
          kServiceUUID.toUpperCase()) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toUpperCase();
          if (uuid == kRxCharUUID.toUpperCase()) _rxChar = char;
          if (uuid == kTxCharUUID.toUpperCase()) _txChar = char;
        }
      }
    }

    if (_txChar != null && _txChar!.properties.notify) {
      await _txChar!.setNotifyValue(true);
      _notifySub?.cancel();
      _notifySub = _txChar!.onValueReceived.listen(_onDataReceived);
    }
  }

  void _onConnectionStateChange(fbp.BluetoothConnectionState state) {
    if (state == fbp.BluetoothConnectionState.disconnected) {
      _rxChar = null;
      _txChar = null;
      _notifySub?.cancel();
      _setState(BleConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_lastDeviceId == null) return;
    final delaySeconds = _backoffSeconds(_reconnectAttempts);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_lastDeviceId != null &&
          _state != BleConnectionState.connected) {
        _doConnect(_lastDeviceId!);
      }
    });
  }

  int _backoffSeconds(int attempt) =>
      [2, 4, 8, 16, 30, 60][attempt.clamp(0, 5)];

  void _onDataReceived(List<int> data) {
    _incomingController.add(data);
  }

  @override
  Future<void> disconnect() async {
    _lastDeviceId = null;
    _reconnectTimer?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    await _device?.disconnect();
    _device = null;
    _rxChar = null;
    _txChar = null;
    _setState(BleConnectionState.idle);
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  @override
  Future<void> sendAngles(List<int> angles) async {
    if (_rxChar == null || angles.length != 6) return;
    final packet = [
      kCmdMove,
      ...angles.map((a) => a.clamp(0, 180)),
    ];
    await _write(packet);
  }

  @override
  Future<void> sendHome() async {
    if (_rxChar == null) return;
    await _write([kCmdHome]);
  }

  @override
  Future<void> requestState() async {
    if (_rxChar == null) return;
    await _write([kCmdGet]);
  }

  @override
  Future<void> sendSingleJoint(int channel, int angle) async {
    if (_rxChar == null) return;
    await _write([kCmdSetOne, channel.clamp(0, 5), angle.clamp(0, 180)]);
  }

  Future<void> _write(List<int> bytes) async {
    if (_rxChar == null) return;
    final char = _rxChar!;
    final withoutResponse = char.properties.writeWithoutResponse;
    await char.write(bytes, withoutResponse: withoutResponse);
  }

  void _setState(BleConnectionState s) {
    _state = s;
    _connController.add(s);
  }

  @override
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    _scanSub?.cancel();
    await _device?.disconnect();
    await _scanController.close();
    await _connController.close();
    await _incomingController.close();
  }
}
