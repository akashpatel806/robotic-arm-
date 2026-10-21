// lib/features/connect/connect_screen.dart
// BLE scan, connect, and status screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../data/transport/arm_transport.dart';
import '../../providers/arm_provider.dart';
import '../../widgets/status_chip.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _permissionsGranted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final granted = await _requestPermissions();
    if (mounted) {
      setState(() {
        _permissionsGranted = granted;
        _checking = false;
      });
    }
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

  Future<void> _startScan() async {
    HapticFeedback.lightImpact();
    final transport = ref.read(transportProvider);
    await transport.startScan();
  }

  Future<void> _connect(String deviceId) async {
    HapticFeedback.mediumImpact();
    final transport = ref.read(transportProvider);
    await transport.stopScan();
    await transport.connect(deviceId);

    // Save last device
    final storage = await ref.read(settingsStorageProvider.future);
    await storage.saveLastDeviceId(deviceId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connecting to RobotArm-BLE…'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    HapticFeedback.mediumImpact();
    final transport = ref.read(transportProvider);
    await transport.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final connState =
        ref.watch(connectionStateProvider).valueOrNull ??
            BleConnectionState.idle;
    final devices =
        ref.watch(scanResultsProvider).valueOrNull ?? [];
    final isConnected = connState == BleConnectionState.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ConnectionStatusChip(state: connState),
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_permissionsGranted
              ? _buildPermissionDenied()
              : Column(
                  children: [
                    _buildStatusCard(connState, isConnected),
                    _buildScanButton(connState),
                    const SizedBox(height: 8),
                    Expanded(
                      child: devices.isEmpty
                          ? _buildEmptyState(connState)
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: devices.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) =>
                                  _DeviceTile(
                                device: devices[i],
                                isConnected: isConnected &&
                                    devices[i].name
                                        .contains('RobotArm'),
                                onTap: () => isConnected
                                    ? _disconnect()
                                    : _connect(devices[i].id),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatusCard(
      BleConnectionState state, bool isConnected) {
    final color = isConnected
        ? StatusColors.connected
        : StatusColors.disconnected;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.15),
            color.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            color: color,
            size: 32,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isConnected ? 'RobotArm-BLE' : 'No Device',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isConnected
                    ? 'Connected via Bluetooth LE'
                    : 'Tap "Scan" to find your arm',
                style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (isConnected)
            TextButton(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            ),
        ],
      ),
    );
  }

  Widget _buildScanButton(BleConnectionState state) {
    final scanning = state == BleConnectionState.scanning;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: scanning ? null : _startScan,
          icon: scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.search),
          label: Text(scanning ? 'Scanning…' : 'Scan for Devices'),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BleConnectionState state) {
    if (state == BleConnectionState.scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Looking for RobotArm-BLE…'),
          ],
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_searching, size: 64, color: Colors.white24),
          SizedBox(height: 12),
          Text(
            'No devices found',
            style: TextStyle(color: Colors.white54),
          ),
          SizedBox(height: 4),
          Text(
            'Make sure your robot arm is powered on',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Bluetooth Permission Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'This app needs Bluetooth and Location permissions to '
              'scan and connect to your robotic arm.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _checkPermissions,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DiscoveredDevice device;
  final bool isConnected;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isConnected,
    required this.onTap,
  });

  int _rssiToSignal(int rssi) {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final signal = _rssiToSignal(device.rssi);
    final signalIcon = signal >= 4
        ? Icons.signal_cellular_4_bar
        : (signal >= 2 ? Icons.signal_cellular_alt : Icons.signal_cellular_null);

    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isConnected
                ? StatusColors.connected.withOpacity(0.15)
                : cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: isConnected ? StatusColors.connected : cs.primary,
          ),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${device.id} • ${device.rssi} dBm',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(signalIcon, size: 18, color: Colors.white54),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: isConnected
                    ? Colors.redAccent
                    : cs.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8,
                ),
                minimumSize: const Size(80, 36),
              ),
              child: Text(isConnected ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4,
        ),
      ),
    );
  }
}
