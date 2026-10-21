// lib/features/settings/calibration_screen.dart
// Per-joint calibration: min/max limits, invert flag, offset.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/models/calibration.dart';
import '../../providers/arm_provider.dart';

class CalibrationScreen extends ConsumerWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cal = ref.watch(calibrationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibration'),
        actions: [
          TextButton(
            onPressed: () async {
              final defaults = ArmCalibration.defaults();
              ref.read(calibrationProvider.notifier).state = defaults;
              final storage =
                  await ref.read(settingsStorageProvider.future);
              await storage.saveCalibration(defaults);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, i) => _JointCalibrationCard(
          index: i,
          calibration: cal.joints[i],
          onChanged: (newCal) async {
            final updated = cal.withJoint(i, newCal);
            ref.read(calibrationProvider.notifier).state = updated;
            final storage =
                await ref.read(settingsStorageProvider.future);
            await storage.saveCalibration(updated);
          },
        ),
      ),
    );
  }
}

class _JointCalibrationCard extends StatefulWidget {
  final int index;
  final JointCalibration calibration;
  final ValueChanged<JointCalibration> onChanged;

  const _JointCalibrationCard({
    required this.index,
    required this.calibration,
    required this.onChanged,
  });

  @override
  State<_JointCalibrationCard> createState() =>
      _JointCalibrationCardState();
}

class _JointCalibrationCardState
    extends State<_JointCalibrationCard> {
  late JointCalibration _cal;

  @override
  void initState() {
    super.initState();
    _cal = widget.calibration;
  }

  @override
  void didUpdateWidget(_JointCalibrationCard old) {
    super.didUpdateWidget(old);
    _cal = widget.calibration;
  }

  void _update(JointCalibration c) {
    setState(() => _cal = c);
    widget.onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final name = kJointNames[widget.index];
    final icon = kJointIcons[widget.index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _cal.invert,
                  onChanged: (v) =>
                      _update(_cal.copyWith(invert: v)),
                ),
                const Text('Invert',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),

            // Min angle
            _Row(
              label: 'Min Angle',
              value: _cal.minAngle.toDouble(),
              min: 0,
              max: _cal.maxAngle.toDouble() - 1,
              unit: '°',
              onChanged: (v) =>
                  _update(_cal.copyWith(minAngle: v.round())),
            ),

            // Max angle
            _Row(
              label: 'Max Angle',
              value: _cal.maxAngle.toDouble(),
              min: _cal.minAngle.toDouble() + 1,
              max: 180,
              unit: '°',
              onChanged: (v) =>
                  _update(_cal.copyWith(maxAngle: v.round())),
            ),

            // Offset
            _Row(
              label: 'Offset',
              value: _cal.offset.toDouble(),
              min: -45,
              max: 45,
              unit: '°',
              onChanged: (v) =>
                  _update(_cal.copyWith(offset: v.round())),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double value, min, max;
  final String unit;
  final ValueChanged<double> onChanged;

  const _Row({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 12,
                    color: Colors.white60)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${value.round()}$unit',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
