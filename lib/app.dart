// lib/app.dart
// Root widget: MaterialApp with routing, theme, bottom nav, startup init.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/connect/connect_screen.dart';
import 'features/control/control_screen.dart';
import 'features/ik/ik_screen.dart';
import 'features/sequences/sequences_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/calibration_screen.dart';
import 'providers/arm_provider.dart';

class RoboArmApp extends ConsumerStatefulWidget {
  const RoboArmApp({super.key});

  @override
  ConsumerState<RoboArmApp> createState() => _RoboArmAppState();
}

class _RoboArmAppState extends ConsumerState<RoboArmApp> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Load persisted settings on startup
    final storage = await ref.read(settingsStorageProvider.future);
    ref.read(simModeProvider.notifier).state = storage.simMode;
    ref.read(darkModeProvider.notifier).state = storage.darkMode;
    ref.read(speedFactorProvider.notifier).state = storage.speedFactor;
    ref.read(ikParamsProvider.notifier).state = storage.loadIkParams();
    ref.read(calibrationProvider.notifier).state =
        storage.loadCalibration();

    // Auto-connect to last known device
    final lastId = storage.lastDeviceId;
    if (lastId != null && !storage.simMode) {
      final transport = ref.read(transportProvider);
      await transport.connect(lastId);
    }
  }

  static const _screens = [
    ConnectScreen(),
    ControlScreen(),
    IkScreen(),
    SequencesScreen(),
    SettingsScreen(),
  ];

  static const _navItems = [
    NavigationDestination(
      icon: Icon(Icons.bluetooth_searching),
      selectedIcon: Icon(Icons.bluetooth_connected),
      label: 'Connect',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: 'Control',
    ),
    NavigationDestination(
      icon: Icon(Icons.spatial_tracking_outlined),
      selectedIcon: Icon(Icons.spatial_tracking),
      label: 'IK',
    ),
    NavigationDestination(
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie),
      label: 'Sequences',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final darkMode = ref.watch(darkModeProvider);

    return MaterialApp(
      title: 'RoboArm BLE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      routes: {
        '/calibration': (_) => const CalibrationScreen(),
      },
      home: Scaffold(
        body: IndexedStack(
          index: _navIndex,
          children: _screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: (i) =>
              setState(() => _navIndex = i),
          destinations: _navItems,
        ),
      ),
    );
  }
}
