import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../models/sync_models.dart';
import 'widgets/drive_card.dart';
import 'widgets/jio_card.dart';
import 'widgets/partition_path.dart';
import 'widgets/usage_donut.dart';
import 'widgets/volume_tile.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    if (state.busy && state.volumes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final backupStatus = state.sync.status;
    final showBackupCard =
        backupStatus.running || backupStatus.tasks.any((t) => t.isFinished);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBackupCard) ...[
          _BackupProgressCard(state: state, status: backupStatus),
          const SizedBox(height: 16),
        ],
        _VolumePicker(state: state),
        const SizedBox(height: 16),
        _ScanCard(state: state),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DriveCard(state: state),
        const SizedBox(height: 16),
        JioCard(offer: state.carrier, onRecheck: state.refreshCarrier),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (state.isOffline) ...[
          const _OfflineBanner(),
          const SizedBox(height: 16),
        ],
        if (state.error != null) ...[
          _ErrorBanner(message: state.error!),
          const SizedBox(height: 16),
        ],
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: left),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: right),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 16), right],
          ),
      ],
    );
  }
}

class _VolumePicker extends StatelessWidget {
  const _VolumePicker({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.volumes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'No storage volumes were reported. On Android, grant the storage '
            'permission; on desktop, check that DriveSync may run PowerShell '
            'to read disk capacity.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Storage on ${state.deviceLabel}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh volumes',
                  onPressed: state.refreshVolumes,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth > 720
                    ? 3
                    : (c.maxWidth > 420 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.3,
                  children: [
                    for (final v in state.volumes)
                      VolumeTile(
                        volume: v,
                        selected: v.id == state.selected?.id,
                        onTap: () => state.selectVolume(v),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final volume = state.selected;
    if (volume == null) return const SizedBox.shrink();
    final scan = state.currentScan;
    final progress = state.progress;
    final scanning = progress != null && !progress.isDone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(volume.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(volume.path, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            UsageDonut(
              volume: volume,
              categories: scan?.categories ?? const [],
            ),
            const SizedBox(height: 18),
            if (scanning)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Scanned ${progress.filesSeen} files · '
                    '${formatBytes(progress.bytesSeen)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    progress.currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: state.cancelScan,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop scan'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: state.startScan,
                    icon: const Icon(Icons.search),
                    label: Text(scan == null ? 'Analyse storage' : 'Re-scan'),
                  ),
                  const SizedBox(width: 12),
                  if (scan != null)
                    Expanded(
                      child: Text(
                        '${scan.scannedFiles} files · '
                        '${formatBytes(scan.scannedBytes)} in '
                        '${scan.duration.inSeconds}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            if (scan != null) ...[
              const SizedBox(height: 8),
              Text(
                'Snapshot from '
                '${DateFormat.yMMMd().add_jm().format(scan.takenAt)}'
                '${state.isOffline ? ' · offline, showing saved data' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (scan?.partial == true) ...[
              const SizedBox(height: 12),
              _PartialNotice(scan: scan!),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact three-part view of the backup: what's uploading right now, what
/// is coming up next, and what finished most recently — so the state of a
/// running backup is visible without switching to the Backup tab.
class _BackupProgressCard extends StatelessWidget {
  const _BackupProgressCard({required this.state, required this.status});
  final AppState state;
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = status.tasks
        .where((t) => t.state == SyncTaskState.uploading)
        .toList();
    final upNext = status.tasks
        .where((t) => t.state == SyncTaskState.queued)
        .take(3)
        .toList();
    final recent = status.tasks
        .where((t) => t.isFinished)
        .toList()
        .reversed
        .take(3)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.running
                      ? (state.sync.isPaused
                            ? Icons.pause_circle_outline
                            : Icons.cloud_upload_outlined)
                      : Icons.cloud_done_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status.running
                        ? (state.sync.isPaused
                              ? 'Backup paused'
                              : 'Backing up…')
                        : 'Backup',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (status.pendingCount > 0)
                  Text(
                    '${status.pendingCount} pending',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'Current',
              icon: Icons.cloud_upload_outlined,
              child: current.isEmpty
                  ? _Muted(
                      status.running
                          ? 'Starting…'
                          : 'Nothing uploading right now.',
                    )
                  : Column(
                      children: [
                        for (final t in current)
                          _CurrentFileRow(task: t, state: state),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'Next up',
              icon: Icons.schedule,
              child: upNext.isEmpty
                  ? const _Muted('Nothing else queued.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in upNext)
                          _SimpleFileLine(task: t, state: state),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            _Section(
              title: 'Just finished',
              icon: Icons.history,
              child: recent.isEmpty
                  ? const _Muted('Nothing finished yet.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in recent)
                          _RecentFileLine(task: t, state: state),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall);
}

class _CurrentFileRow extends StatelessWidget {
  const _CurrentFileRow({required this.task, required this.state});
  final SyncTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final volume = volumeForPath(state.volumes, task.file.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(task.file.name, overflow: TextOverflow.ellipsis),
              ),
              Text(
                '${(task.progress * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          PartitionPath(volume: volume, path: task.file.path),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: task.progress, minHeight: 6),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (task.speedLabel != null) task.speedLabel!,
              if (task.eta != null && task.eta != Duration.zero)
                '${_eta(task.eta!)} left',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _eta(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

class _SimpleFileLine extends StatelessWidget {
  const _SimpleFileLine({required this.task, required this.state});
  final SyncTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final volume = volumeForPath(state.volumes, task.file.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: PartitionPath(
              volume: volume,
              path: task.file.path,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatBytes(task.file.bytes),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecentFileLine extends StatelessWidget {
  const _RecentFileLine({required this.task, required this.state});
  final SyncTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (task.state) {
      SyncTaskState.done => (
        Icons.check_circle_outline,
        const Color(0xFF1E8E3E),
      ),
      SyncTaskState.skipped => (Icons.done_all, scheme.onSurfaceVariant),
      SyncTaskState.failed => (Icons.error_outline, scheme.error),
      _ => (Icons.check_circle_outline, scheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              task.file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            task.state == SyncTaskState.failed
                ? 'failed'
                : formatBytes(task.file.bytes),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: task.state == SyncTaskState.failed ? scheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartialNotice extends StatelessWidget {
  const _PartialNotice({required this.scan});
  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Partial result',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Some locations were not readable or the scan hit its time budget, '
            'so the breakdown below covers less than the whole volume.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (scan.skippedPaths.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              scan.skippedPaths.take(3).join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are offline. Scanning still works, saved results are shown, '
              'and anything you queue is uploaded automatically once a '
              'connection returns.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
