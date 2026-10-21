// lib/widgets/status_chip.dart
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/transport/arm_transport.dart';

class ConnectionStatusChip extends StatelessWidget {
  final BleConnectionState state;
  const ConnectionStatusChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      BleConnectionState.connected =>
        ('Connected', StatusColors.connected, Icons.bluetooth_connected),
      BleConnectionState.connecting =>
        ('Connecting…', StatusColors.connecting, Icons.bluetooth_searching),
      BleConnectionState.scanning =>
        ('Scanning…', StatusColors.scanning, Icons.radar),
      BleConnectionState.disconnected =>
        ('Disconnected', StatusColors.disconnected, Icons.bluetooth_disabled),
      BleConnectionState.idle =>
        ('Idle', Colors.grey, Icons.bluetooth),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Chip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color.withOpacity(0.12),
        side: BorderSide(color: color.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      ),
    );
  }
}
