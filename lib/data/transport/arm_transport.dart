// lib/data/transport/arm_transport.dart
// Abstract interface for the BLE transport layer.
// Allows substituting SimulatedTransport for testing without hardware.

import 'dart:async';

/// BLE connection state machine.
/// Renamed to avoid ambiguity with Flutter's ConnectionState.
enum BleConnectionState {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
}

/// A discovered BLE device (name + identifier + RSSI).
class DiscoveredDevice {
  final String id;
  final String name;
  final int rssi;
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

/// Abstract transport interface. Inject via Riverpod.
abstract class ArmTransport {
  // ── Scanning ───────────────────────────────────────────────────────────────

  /// Start scanning; yields discovered devices.
  Stream<List<DiscoveredDevice>> get scanResults;

  Future<void> startScan();
  Future<void> stopScan();

  // ── Connection ─────────────────────────────────────────────────────────────

  /// Emits the current connection state.
  Stream<BleConnectionState> get connectionStateStream;

  BleConnectionState get connectionState;

  /// Connect to device with [deviceId].
  Future<void> connect(String deviceId);

  /// Disconnect from the current device.
  Future<void> disconnect();

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Send all 6 servo angles at once using the 'M' packet (7 bytes).
  Future<void> sendAngles(List<int> angles);

  /// Send 'H' (home) command.
  Future<void> sendHome();

  /// Send 'G' (request state) command.
  Future<void> requestState();

  /// Send 'S' ch angle (single joint) command.
  Future<void> sendSingleJoint(int channel, int angle);

  // ── Incoming data from ESP32 ───────────────────────────────────────────────

  /// Raw bytes received on TX characteristic (notifications from ESP32).
  Stream<List<int>> get incomingStream;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> dispose();
}
