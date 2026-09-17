import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../models/sync_models.dart';
import 'history_page.dart';
import 'widgets/file_sort.dart';
import 'widgets/partition_path.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  /// Paths ticked as "back up these specifically" — empty means "everything
  /// pending", so the page behaves exactly as before until someone opts in.
  final Set<String> _selected = {};

  SortLevel _primarySort = const SortLevel(FileSortKey.name);
  SortLevel? _secondarySort;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final status = state.sync.status;
    final scheme = Theme.of(context).colorScheme;

    final sortedTasks = sortByFileKey(
      items: status.tasks,
      primary: _primarySort,
      secondary: _secondarySort,
      name: (t) => t.file.name,
      bytes: (t) => t.file.bytes,
      date: (t) => t.file.modified,
      partitionLabel: (t) =>
          volumeForPath(state.volumes, t.file.path)?.label ?? '',
    );
    final pending = sortedTasks.where((t) => !t.isFinished).toList();
    final pendingPaths = pending.map((t) => t.file.path).toSet();
    _selected.removeWhere((p) => !pendingPaths.contains(p));
    final hasSelection = _selected.isNotEmpty;
    final allPendingSelected =
        pending.isNotEmpty && _selected.length == pending.length;
    final selectedBytes = pending
        .where((t) => _selected.contains(t.file.path))
        .fold(0, (a, t) => a + t.file.bytes);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.settings.value.isAuto
                      ? 'Auto mode — DriveSync offloads on its own'
                      : 'Manual mode — nothing leaves this device until you say so',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Destination: DriveSync/${state.deviceLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: status.running || !state.isConnected
                          ? null
                          : () {
                              final only = hasSelection
                                  ? Set<String>.from(_selected)
                                  : null;
                              state.backupNow(only: only);
                            },
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        hasSelection
                            ? 'Back up ${_selected.length} selected · '
                                  '${formatBytes(selectedBytes)}'
                            : status.pendingCount == 0
                            ? 'Back up now'
                            : 'Back up all ${status.pendingCount} file(s) · '
                                  '${formatBytes(pending.fold(0, (a, t) => a + t.file.bytes))}',
                      ),
                    ),
                    if (status.running) ...[
                      OutlinedButton.icon(
                        onPressed: state.sync.isPaused
                            ? state.sync.resume
                            : state.sync.pause,
                        icon: Icon(
                          state.sync.isPaused
                              ? Icons.play_circle_outline
                              : Icons.pause_circle_outline,
                        ),
                        label: Text(state.sync.isPaused ? 'Resume' : 'Pause'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.sync.cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop'),
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: status.tasks.any((t) => t.isFinished)
                          ? state.sync.clearFinished
                          : null,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Clear finished'),
                    ),
                  ],
                ),
                if (!state.isConnected) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Connect Google Drive on the Dashboard first.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ],
                if (state.link.isOffline) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline — the queue is saved and uploads start on '
                          'their own when you are back on an allowed network.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                if (state.sync.isWaitingForNetwork &&
                    !state.link.isOffline) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for Wi-Fi before uploading. Turn off "Wi-Fi only" '
                    'in Settings to use mobile data.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (state.sync.mobileDataLimitExceeded) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.data_usage, size: 18, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mobile data limit reached this month — new '
                          'uploads over mobile data are held back. Adjust '
                          'the limit in Settings.',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
                if (status.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    status.message!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _Stat('Uploaded', formatBytes(status.uploadedBytes)),
                    _Stat('Done', '${status.doneCount}'),
                    _Stat('Failed', '${status.failedCount}'),
                    _Stat('Reclaimed locally', formatBytes(status.freedBytes)),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Upload history')),
                          body: const HistoryPage(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text(
                      'View full upload history'
                      '${state.sync.history().isEmpty ? '' : ' (${state.sync.history().length})'}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(
              state.settings.value.autoMobileBackup
                  ? Icons.photo_camera_back
                  : Icons.photo_camera_back_outlined,
              color: state.settings.value.autoMobileBackup
                  ? scheme.primary
                  : null,
            ),
            title: Text(
              state.settings.value.autoMobileBackup
                  ? 'Auto Mobile Backup is on'
                  : 'Auto Mobile Backup is off',
            ),
            subtitle: Text(
              state.media.status ??
                  (state.settings.value.autoMobileBackup
                      ? 'Watching the camera roll for new photos and videos.'
                      : 'Turn it on in Settings to back up new photos and '
                            'videos without asking.'),
            ),
            trailing: TextButton(
              onPressed: state.checkForNewMedia,
              child: const Text('Check now'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (sortedTasks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'The queue is empty. Analyse a volume, then queue files from '
                'the Files tab — or let Auto mode fill it after a scan.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (pending.isNotEmpty) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() {
                      if (allPendingSelected) {
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
                            value: allPendingSelected,
                            tristate: hasSelection && !allPendingSelected,
                            onChanged: (v) => setState(() {
                              if (allPendingSelected) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(pendingPaths);
                              }
                            }),
                          ),
                          Text(
                            allPendingSelected ? 'Deselect all' : 'Select all',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Tick to pick specific files to send now — leave all '
                      'unticked to back up everything pending.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ] else
                  const Spacer(),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasSelection)
                      TextButton(
                        onPressed: () => setState(_selected.clear),
                        child: const Text('Clear selection'),
                      ),
                    FileSortControl(
                      primary: _primarySort,
                      secondary: _secondarySort,
                      onPrimaryChanged: (v) => setState(() {
                        _primarySort = v;
                        if (_secondarySort?.key == v.key) {
                          _secondarySort = null;
                        }
                      }),
                      onSecondaryChanged: (v) =>
                          setState(() => _secondarySort = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: _buildTaskRows(
                context,
                sortedTasks,
                state,
                status,
                groupByPartition: _primarySort.key == FileSortKey.partition,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Builds the task rows, inserting a header — with its own select-all
  /// checkbox for that drive's pending files — before each new partition's
  /// group when [groupByPartition] is on (i.e. the list is actually sorted by
  /// partition, so same-drive files are contiguous rather than scattered).
  List<Widget> _buildTaskRows(
    BuildContext context,
    List<SyncTask> tasks,
    AppState state,
    SyncStatus status, {
    required bool groupByPartition,
  }) {
    final widgets = <Widget>[];
    String? lastLabel;

    if (groupByPartition) {
      // Pre-compute each group's pending paths up front, so the header can
      // show the right select-all state before its own rows are reached.
      final byLabel = <String, List<String>>{};
      for (final t in tasks) {
        if (t.isFinished || status.running) continue;
        final label =
            volumeForPath(state.volumes, t.file.path)?.label ??
            'Unknown volume';
        (byLabel[label] ??= []).add(t.file.path);
      }
      for (final task in tasks) {
        final volume = volumeForPath(state.volumes, task.file.path);
        final label = volume?.label ?? 'Unknown volume';
        if (label != lastLabel) {
          final paths = byLabel[label] ?? const [];
          final selectedInGroup = paths
              .where((p) => _selected.contains(p))
              .length;
          widgets.add(
            _PartitionHeader(
              label: label,
              selectable: paths.isNotEmpty,
              allSelected: paths.isNotEmpty && selectedInGroup == paths.length,
              tristate: selectedInGroup > 0 && selectedInGroup < paths.length,
              onChanged: (allSelected) => setState(() {
                if (allSelected) {
                  _selected.addAll(paths);
                } else {
                  _selected.removeAll(paths);
                }
              }),
            ),
          );
          lastLabel = label;
        }
        widgets.add(_taskRowFor(task, state, status));
      }
      return widgets;
    }

    for (final task in tasks) {
      widgets.add(_taskRowFor(task, state, status));
    }
    return widgets;
  }

  _TaskRow _taskRowFor(SyncTask task, AppState state, SyncStatus status) {
    final volume = volumeForPath(state.volumes, task.file.path);
    return _TaskRow(
      task: task,
      volume: volume,
      paused: state.sync.isPaused,
      selectable: !task.isFinished && !status.running,
      selected: _selected.contains(task.file.path),
      onSelectedChanged: (v) => setState(() {
        if (v) {
          _selected.add(task.file.path);
        } else {
          _selected.remove(task.file.path);
        }
      }),
    );
  }
}

class _PartitionHeader extends StatelessWidget {
  const _PartitionHeader({
    required this.label,
    this.selectable = false,
    this.allSelected = false,
    this.tristate = false,
    this.onChanged,
  });

  final String label;

  /// False when this drive has nothing pending right now (e.g. everything
  /// already uploaded, or a backup is running) — the checkbox is hidden
  /// rather than shown disabled, since there is nothing to act on.
  final bool selectable;
  final bool allSelected;
  final bool tristate;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: selectable ? () => onChanged?.call(!allSelected) : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
        color: scheme.surfaceContainerHighest,
        child: Row(
          children: [
            if (selectable)
              Checkbox(
                value: allSelected,
                tristate: tristate,
                onChanged: (v) => onChanged?.call(v ?? false),
              )
            else
              const SizedBox(width: 12),
            Icon(Icons.storage_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    this.volume,
    this.paused = false,
    this.selectable = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final SyncTask task;
  final VolumeInfo? volume;
  final bool paused;

  /// Whether this row can be marked "important" right now — false while it's
  /// uploading or once a run is in progress, since the plan is already fixed.
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uploading = task.state == SyncTaskState.uploading;
    final (icon, color) = switch (task.state) {
      SyncTaskState.queued => (Icons.schedule, scheme.onSurfaceVariant),
      SyncTaskState.uploading => (
        paused ? Icons.pause_circle_outline : Icons.cloud_upload_outlined,
        scheme.primary,
      ),
      SyncTaskState.done => (
        Icons.check_circle_outline,
        const Color(0xFF1E8E3E),
      ),
      SyncTaskState.skipped => (Icons.done_all, scheme.onSurfaceVariant),
      SyncTaskState.failed => (Icons.error_outline, scheme.error),
    };

    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.state == SyncTaskState.failed)
          Text(
            task.error ?? 'Upload failed',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.error),
          )
        else
          PartitionPath(volume: volume, path: task.file.path),
        if (uploading) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: task.progress),
          const SizedBox(height: 4),
          Text(
            paused
                ? 'Paused · ${formatBytes(task.uploadedBytes)} of '
                      '${formatBytes(task.file.bytes)}'
                : [
                    if (task.speedLabel != null) task.speedLabel,
                    if (task.eta != null && task.eta != Duration.zero)
                      '${_etaLabel(task.eta!)} left',
                  ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );

    if (selectable) {
      return CheckboxListTile(
        value: selected,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => onSelectedChanged?.call(v ?? false),
        secondary: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(
              formatBytes(task.file.bytes),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        title: Text(task.file.name, overflow: TextOverflow.ellipsis),
        subtitle: subtitle,
        isThreeLine: uploading,
      );
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(task.file.name, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      isThreeLine: uploading,
      trailing: Text(
        task.state == SyncTaskState.skipped
            ? 'already in Drive'
            : formatBytes(task.file.bytes),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  String _etaLabel(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}
