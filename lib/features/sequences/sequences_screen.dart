// lib/features/sequences/sequences_screen.dart
// Pose recorder, sequence builder, and player.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/transport/arm_transport.dart';
import '../../domain/models/arm_state.dart';
import '../../domain/models/pose.dart';
import '../../providers/arm_provider.dart';

class SequencesScreen extends ConsumerStatefulWidget {
  const SequencesScreen({super.key});

  @override
  ConsumerState<SequencesScreen> createState() =>
      _SequencesScreenState();
}

class _SequencesScreenState extends ConsumerState<SequencesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sequences'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Poses'),
            Tab(icon: Icon(Icons.play_circle), text: 'Sequences'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _PosesTab(),
          _SequencesTab(),
        ],
      ),
    );
  }
}

// ── Poses tab ─────────────────────────────────────────────────────────────────

class _PosesTab extends ConsumerWidget {
  const _PosesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poses = ref.watch(poseListProvider);
    final armState = ref.watch(armStateProvider);
    final connState =
        ref.watch(connectionStateProvider).valueOrNull ??
            BleConnectionState.idle;
    final isConnected = connState == BleConnectionState.connected;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isConnected
                  ? () => _savePose(context, ref, armState)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Save Current Pose'),
            ),
          ),
        ),
        Expanded(
          child: poses.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.save_outlined,
                          size: 64, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('No saved poses',
                          style: TextStyle(color: Colors.white54)),
                      SizedBox(height: 4),
                      Text('Connect and move the arm, then save a pose',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: poses.length,
                  onReorder: (o, n) =>
                      ref.read(poseListProvider.notifier).reorder(o, n),
                  itemBuilder: (_, i) =>
                      _PoseTile(
                    key: ValueKey(poses[i].id),
                    pose: poses[i],
                    onPlay: isConnected
                        ? () => _playPose(ref, poses[i])
                        : null,
                    onDelete: () => ref
                        .read(poseListProvider.notifier)
                        .remove(poses[i].id),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _savePose(
    BuildContext context,
    WidgetRef ref,
    ArmState state,
  ) async {
    final name = await _promptName(context, 'Pose Name', 'Pose 1');
    if (name == null || name.isEmpty) return;
    final pose = Pose(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      angles: List<int>.from(state.angles),
    );
    ref.read(poseListProvider.notifier).add(pose);
    HapticFeedback.lightImpact();
  }

  void _playPose(WidgetRef ref, Pose pose) {
    HapticFeedback.mediumImpact();
    ref.read(motionControllerProvider).moveTo(pose.angles);
  }
}

Future<String?> _promptName(
    BuildContext ctx, String title, String hint) async {
  final ctrl = TextEditingController(text: hint);
  return showDialog<String>(
    context: ctx,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _PoseTile extends StatelessWidget {
  final Pose pose;
  final VoidCallback? onPlay;
  final VoidCallback onDelete;

  const _PoseTile({
    super.key,
    required this.pose,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.accessibility_new, size: 20),
        ),
        title: Text(pose.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${pose.angles.join('°, ')}°',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Color(0xFF00E676)),
              onPressed: onPlay,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white38),
              onPressed: () => _confirmDelete(context),
            ),
            const Icon(Icons.drag_handle, color: Colors.white24),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete Pose?'),
        content: Text('Delete "${pose.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}

// ── Sequences tab ─────────────────────────────────────────────────────────────

class _SequencesTab extends ConsumerWidget {
  const _SequencesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sequences = ref.watch(sequenceListProvider);
    final poses = ref.watch(poseListProvider);
    final playState = ref.watch(sequencePlayerProvider);
    final connState =
        ref.watch(connectionStateProvider).valueOrNull ??
            BleConnectionState.idle;
    final isConnected = connState == BleConnectionState.connected;

    return Column(
      children: [
        // Player controls
        if (playState != PlaybackState.stopped)
          _PlayerBar(playState: playState),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: poses.isEmpty
                      ? null
                      : () => _newSequence(context, ref, poses),
                  icon: const Icon(Icons.add),
                  label: const Text('New Sequence'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sequences.isEmpty
              ? const Center(
                  child: Text(
                    'No sequences. Create one from saved poses.',
                    style: TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sequences.length,
                  itemBuilder: (_, i) => _SequenceTile(
                    sequence: sequences[i],
                    enabled: isConnected,
                    onPlay: () =>
                        _playSequence(context, ref, sequences[i]),
                    onDelete: () => ref
                        .read(sequenceListProvider.notifier)
                        .remove(sequences[i].id),
                    onExport: () =>
                        _exportSequence(context, sequences[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _newSequence(
    BuildContext context,
    WidgetRef ref,
    List<Pose> poses,
  ) async {
    final name = await _promptName(
        context, 'Sequence Name', 'Sequence 1');
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;

    // Show pose picker
    final selected = await showDialog<List<Pose>>(
      context: context,
      builder: (ctx) => _PosePickerDialog(poses: poses),
    );
    if (selected == null || selected.isEmpty) return;

    final seq = PoseSequence(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      poses: selected,
    );
    ref.read(sequenceListProvider.notifier).add(seq);
  }

  Future<void> _playSequence(
    BuildContext context,
    WidgetRef ref,
    PoseSequence seq,
  ) async {
    final player = ref.read(sequencePlayerProvider.notifier);
    // First-time confirmation
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Play "${seq.name}"?'),
        content: Text(
          'This will move the arm through ${seq.poses.length} poses. '
          'Make sure the workspace is clear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    player.confirm();
    player.play(seq, confirmed: true);
  }

  void _exportSequence(BuildContext context, PoseSequence seq) {
    final json = seq.toJsonString();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Sequence JSON'),
        content: SingleChildScrollView(
          child: SelectableText(
            json,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PlayerBar extends ConsumerWidget {
  final PlaybackState playState;
  const _PlayerBar({required this.playState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(sequencePlayerProvider.notifier);
    return Container(
      color: const Color(0xFF7B2FFF).withOpacity(0.2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.movie_outlined, color: Color(0xFF7B2FFF)),
          const SizedBox(width: 8),
          Text(
            playState == PlaybackState.playing
                ? 'Playing…'
                : 'Paused',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (playState == PlaybackState.playing)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: player.pause,
            )
          else
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: player.resume,
            ),
          IconButton(
            icon: const Icon(Icons.stop, color: Colors.redAccent),
            onPressed: player.stop,
          ),
        ],
      ),
    );
  }
}

class _SequenceTile extends StatelessWidget {
  final PoseSequence sequence;
  final bool enabled;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _SequenceTile({
    required this.sequence,
    required this.enabled,
    required this.onPlay,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.movie_outlined, size: 20),
        ),
        title: Text(sequence.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Text('${sequence.poses.length} poses'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle,
                  color: Color(0xFF00E676)),
              onPressed: enabled ? onPlay : null,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'export') onExport();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.share),
                    title: Text('Export JSON'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Delete',
                        style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        children: sequence.poses.map((p) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_right, size: 16),
            title: Text(p.name),
            subtitle: Text('${p.angles.join('°, ')}°',
                style: const TextStyle(fontSize: 10)),
            trailing: Text('${p.holdMs} ms'),
          );
        }).toList(),
      ),
    );
  }
}

class _PosePickerDialog extends StatefulWidget {
  final List<Pose> poses;
  const _PosePickerDialog({required this.poses});

  @override
  State<_PosePickerDialog> createState() => _PosePickerDialogState();
}

class _PosePickerDialogState extends State<_PosePickerDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Poses'),
      content: SizedBox(
        width: 300,
        child: ListView(
          shrinkWrap: true,
          children: widget.poses.map((p) {
            return CheckboxListTile(
              title: Text(p.name),
              value: _selected.contains(p.id),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(p.id);
                  } else {
                    _selected.remove(p.id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final selected = widget.poses
                .where((p) => _selected.contains(p.id))
                .toList();
            Navigator.pop(context, selected);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
