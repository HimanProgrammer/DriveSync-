import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../models/sync_models.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final status = state.sync.status;
    final scheme = Theme.of(context).colorScheme;

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
                          : state.backupNow,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        status.pendingCount == 0
                            ? 'Back up now'
                            : 'Back up ${status.pendingCount} file(s) · '
                                '${formatBytes(status.tasks.where((t) => !t.isFinished).fold(0, (a, t) => a + t.file.bytes))}',
                      ),
                    ),
                    if (status.running)
                      OutlinedButton.icon(
                        onPressed: state.sync.cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop'),
                      ),
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
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ],
                if (state.link.isOffline) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.cloud_off, size: 18, color: scheme.onSurfaceVariant),
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
                if (state.sync.isWaitingForNetwork && !state.link.isOffline) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for Wi-Fi before uploading. Turn off "Wi-Fi only" '
                    'in Settings to use mobile data.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (status.message != null) ...[
                  const SizedBox(height: 12),
                  Text(status.message!,
                      style: Theme.of(context).textTheme.bodyMedium),
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
              color: state.settings.value.autoMobileBackup ? scheme.primary : null,
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
        if (status.tasks.isEmpty)
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
        else
          Card(
            child: Column(
              children: [
                for (final task in status.tasks) _TaskRow(task: task),
              ],
            ),
          ),
      ],
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
  const _TaskRow({required this.task});
  final SyncTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (task.state) {
      SyncTaskState.queued => (Icons.schedule, scheme.onSurfaceVariant),
      SyncTaskState.uploading => (Icons.cloud_upload_outlined, scheme.primary),
      SyncTaskState.done => (Icons.check_circle_outline, const Color(0xFF1E8E3E)),
      SyncTaskState.skipped => (Icons.done_all, scheme.onSurfaceVariant),
      SyncTaskState.failed => (Icons.error_outline, scheme.error),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(task.file.name, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.state == SyncTaskState.failed
                ? task.error ?? 'Upload failed'
                : task.file.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: task.state == SyncTaskState.failed ? scheme.error : null,
            ),
          ),
          if (task.state == SyncTaskState.uploading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: task.progress),
          ],
        ],
      ),
      isThreeLine: task.state == SyncTaskState.uploading,
      trailing: Text(
        task.state == SyncTaskState.skipped
            ? 'already in Drive'
            : formatBytes(task.file.bytes),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
