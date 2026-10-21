// test/widget_test.dart
// Basic widget tests for custom UI components.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robo_arm_ble/data/transport/arm_transport.dart';
import 'package:robo_arm_ble/widgets/status_chip.dart';

void main() {
  testWidgets('ConnectionStatusChip displays Connected label when connected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionStatusChip(state: BleConnectionState.connected),
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
  });

  testWidgets('ConnectionStatusChip displays Disconnected label when disconnected', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionStatusChip(state: BleConnectionState.disconnected),
        ),
      ),
    );

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_disabled), findsOneWidget);
  });
}
