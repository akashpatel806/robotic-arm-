// lib/widgets/connection_guard.dart
// Shows a "disconnected" overlay or warning when not connected.
// Allows buttons to be disabled.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transport/arm_transport.dart';
import '../providers/arm_provider.dart';

class ConnectionGuard extends ConsumerWidget {
  final Widget child;
  final bool showOverlay;

  const ConnectionGuard({
    super.key,
    required this.child,
    this.showOverlay = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState =
        ref.watch(connectionStateProvider).valueOrNull;
    final isConnected = connState == BleConnectionState.connected;

    if (showOverlay && !isConnected) {
      return Stack(
        children: [
          IgnorePointer(
            ignoring: true,
            child: Opacity(opacity: 0.3, child: child),
          ),
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.redAccent.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bluetooth_disabled,
                        color: Colors.redAccent, size: 40),
                    const SizedBox(height: 8),
                    const Text(
                      'Not Connected',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Go to Connect tab to pair with RobotArm-BLE',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

/// A button that is disabled when not connected.
class ConnectedButton extends ConsumerWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  const ConnectedButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.style,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionStateProvider).valueOrNull;
    final isConnected = connState == BleConnectionState.connected;
    return ElevatedButton(
      onPressed: isConnected ? onPressed : null,
      style: style,
      child: child,
    );
  }
}
