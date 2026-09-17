import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../models/sync_models.dart';
import 'widgets/partition_path.dart';

/// Uploaded files waiting on a "delete the original?" decision — reviewed
/// here as a list rather than one popup per file, so a big backup doesn't
/// interrupt you dozens of times in a row. Select individually, per drive, or
/// all at once, then act in bulk.
class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key});

  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState extends State<CleanupPage> {
  final Set<String> _selected = {}; // SyncTask.file.path

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pending = state.sync.pendingDeletions;
    final pendingPaths = pending.map((t) => t.file.path).toSet();
    _selected.removeWhere((p) => !pendingPaths.contains(p));

    if (pending.isEmpty) {
      return const _Empty();
    }

    final allSelected = _selected.length == pending.length;
    final selectedTasks = pending
        .where((t) => _selected.contains(t.file.path))
        .toList();
    final selectedBytes = selectedTasks.fold(0, (a, t) => a + t.file.bytes);

    // Group by partition, in the order each drive's files first appear.
    final order = <String>[];
    final byLabel = <String, List<SyncTask>>{};
    for (final task in pending) {
      final label =
          volumeForPath(state.volumes, task.file.path)?.label ??
          'Unknown volume';
      if (!byLabel.containsKey(label)) order.add(label);
      (byLabel[label] ??= []).add(task);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  if (allSelected) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(pendingPaths);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: allSelected,
                        tristate: _selected.isNotEmpty && !allSelected,
                        onChanged: (v) => setState(() {
                          if (allSelected) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(pendingPaths);
                          }
                        }),
                      ),
                      Text(
                        allSelected ? 'Deselect all' : 'Select all',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${pending.length} uploaded file(s) awaiting a decision',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              for (final label in order) ...[
                _PartitionGroupHeader(
                  label: label,
                  tasks: byLabel[label]!,
                  selected: _selected,
                  onToggleGroup: (paths, select) => setState(() {
                    if (select) {
                      _selected.addAll(paths);
                    } else {
                      _selected.removeAll(paths);
                    }
                  }),
                ),
                for (final task in byLabel[label]!)
                  _CleanupRow(
                    task: task,
                    volume: volumeForPath(state.volumes, task.file.path),
                    selected: _selected.contains(task.file.path),
                    onChanged: (v) => setState(() {
                      if (v) {
                        _selected.add(task.file.path);
                      } else {
                        _selected.remove(task.file.path);
                      }
                    }),
                  ),
              ],
            ],
          ),
        ),
        if (_selected.isNotEmpty)
          _ActionBar(
            count: _selected.length,
            totalBytes: selectedBytes,
            onKeep: () {
              state.sync.keepMany(selectedTasks);
              setState(_selected.clear);
            },
            onDelete: () => _confirmBulkDelete(context, state, selectedTasks),
          ),
      ],
    );
  }

  Future<void> _confirmBulkDelete(
    BuildContext context,
    AppState state,
    List<SyncTask> tasks,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${tasks.length} local file(s)?'),
        content: const Text(
          'These are already confirmed in your Drive. Deleting the local '
          'copies cannot be undone from here — the only remaining copies '
          'will be the ones in Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await state.sync.confirmDeleteMany(tasks);
      setState(_selected.clear);
    }
  }
}

class _PartitionGroupHeader extends StatelessWidget {
  const _PartitionGroupHeader({
    required this.label,
    required this.tasks,
    required this.selected,
    required this.onToggleGroup,
  });

  final String label;
  final List<SyncTask> tasks;
  final Set<String> selected;
  final void Function(List<String> paths, bool select) onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paths = tasks.map((t) => t.file.path).toList();
    final selectedInGroup = paths.where(selected.contains).length;
    final allSelected = selectedInGroup == paths.length;
    final totalBytes = tasks.fold(0, (a, t) => a + t.file.bytes);

    return InkWell(
      onTap: () => onToggleGroup(paths, !allSelected),
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: selectedInGroup > 0 && !allSelected,
              onChanged: (v) => onToggleGroup(paths, v ?? false),
            ),
            Icon(Icons.storage_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
            ),
            Text(
              '${tasks.length} file(s) · ${formatBytes(totalBytes)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CleanupRow extends StatelessWidget {
  const _CleanupRow({
    required this.task,
    required this.volume,
    required this.selected,
    required this.onChanged,
  });

  final SyncTask task;
  final VolumeInfo? volume;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: selected,
    controlAffinity: ListTileControlAffinity.leading,
    onChanged: (v) => onChanged(v ?? false),
    title: Text(task.file.name, overflow: TextOverflow.ellipsis),
    subtitle: PartitionPath(volume: volume, path: task.file.path),
    secondary: Text(
      formatBytes(task.file.bytes),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.count,
    required this.totalBytes,
    required this.onKeep,
    required this.onDelete,
  });

  final int count;
  final int totalBytes;
  final VoidCallback onKeep;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count selected · ${formatBytes(totalBytes)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          OutlinedButton(onPressed: onKeep, child: const Text('Keep')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete selected'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing to review',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Files confirmed in Drive show up here for you to keep or '
              'delete locally, once "Check uploaded, then delete the file" '
              'is on in Settings.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
