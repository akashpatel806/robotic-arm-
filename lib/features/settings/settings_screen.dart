// lib/features/settings/settings_screen.dart
// App settings: simulation mode, theme, speed, IK link lengths.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/models/ik_params.dart';
import '../../providers/arm_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simMode = ref.watch(simModeProvider);
    final darkMode = ref.watch(darkModeProvider);
    final speed = ref.watch(speedFactorProvider);
    final params = ref.watch(ikParamsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Calibration',
            onPressed: () =>
                Navigator.of(context).pushNamed('/calibration'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Connectivity ──────────────────────────────────────────────────
          const _SectionHeader('Connectivity'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.computer),
                  title: const Text('Simulation Mode'),
                  subtitle: const Text(
                    'Use a fake BLE device for testing without hardware',
                  ),
                  value: simMode,
                  onChanged: (v) async {
                    ref.read(simModeProvider.notifier).state = v;
                    final storage =
                        await ref.read(settingsStorageProvider.future);
                    await storage.setSimMode(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Appearance ────────────────────────────────────────────────────
          const _SectionHeader('Appearance'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('Dark Mode'),
              value: darkMode,
              onChanged: (v) async {
                ref.read(darkModeProvider.notifier).state = v;
                final storage =
                    await ref.read(settingsStorageProvider.future);
                await storage.setDarkMode(v);
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── Motion ────────────────────────────────────────────────────────
          const _SectionHeader('Motion'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Speed',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(speed * kFirmwareMaxDegPerSec).toStringAsFixed(0)} deg/s',
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: speed,
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    onChanged: (v) async {
                      ref.read(speedFactorProvider.notifier).state = v;
                      final storage =
                          await ref.read(settingsStorageProvider.future);
                      await storage.setSpeedFactor(v);
                    },
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Slow',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white38)),
                      Text('Fast',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white38)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── IK Parameters ─────────────────────────────────────────────────
          const _SectionHeader('Inverse Kinematics (Link Lengths, mm)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _LengthField(
                    label: 'Base Height (d1)',
                    value: params.d1,
                    onChanged: (v) => _updateParams(ref,
                        params.copyWith(d1: v)),
                  ),
                  _LengthField(
                    label: 'L1: Shoulder → Elbow',
                    value: params.l1,
                    onChanged: (v) => _updateParams(ref,
                        params.copyWith(l1: v)),
                  ),
                  _LengthField(
                    label: 'L2: Elbow → Wrist',
                    value: params.l2,
                    onChanged: (v) => _updateParams(ref,
                        params.copyWith(l2: v)),
                  ),
                  _LengthField(
                    label: 'L3: Wrist → Tip',
                    value: params.l3,
                    onChanged: (v) => _updateParams(ref,
                        params.copyWith(l3: v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── About ─────────────────────────────────────────────────────────
          const _SectionHeader('About'),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('RoboArm BLE Controller'),
                  subtitle: Text('v1.0.0 – Built with Flutter'),
                ),
                ListTile(
                  leading: Icon(Icons.bluetooth),
                  title: Text('Target Device'),
                  subtitle: Text('RobotArm-BLE (NodeMCU-32S + PCA9685)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _updateParams(WidgetRef ref, IkParams p) async {
    ref.read(ikParamsProvider.notifier).state = p;
    final storage = await ref.read(settingsStorageProvider.future);
    await storage.saveIkParams(p);
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _LengthField extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _LengthField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl =
        TextEditingController(text: value.toStringAsFixed(1));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
        ),
        onSubmitted: (s) {
          final v = double.tryParse(s);
          if (v != null && v > 0) onChanged(v);
        },
      ),
    );
  }
}
