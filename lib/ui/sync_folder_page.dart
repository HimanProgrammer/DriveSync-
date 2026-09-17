import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/sync_folder_models.dart';

/// The OneDrive-style two-way Sync Folder: one local folder mirrored with one
/// Drive folder, deletions included in both directions. Deliberately
/// separate from the Backup tab's one-way upload queue.
class SyncFolderPage extends StatefulWidget {
  const SyncFolderPage({super.key});

  @override
  State<SyncFolderPage> createState() => _SyncFolderPageState();
}

class _SyncFolderPageState extends State<SyncFolderPage> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _pathController = TextEditingController(
      text: state.syncFolder.localPath ?? state.syncFolder.suggestedLocalPath,
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final folder = state.syncFolder;
    final scheme = Theme.of(context).colorScheme;

    if (!folder.isSupported) {
      return _Unsupported(scheme: scheme);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sync Folder',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Switch(
                      value: folder.enabled,
                      onChanged: state.isConnected
                          ? (v) => v ? _enable(state) : folder.disable()
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Keeps one folder on this device and "DriveSync/Sync" in '
                  'your Drive identical — like OneDrive. New or changed '
                  'files copy in whichever direction they changed, and '
                  'deleting a file on either side deletes it on the other '
                  'too, including subfolders.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pathController,
                  enabled: !folder.enabled,
                  decoration: const InputDecoration(
                    labelText: 'Local folder',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (!state.isConnected) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Connect Google Drive on the Dashboard first.',
                    style: TextStyle(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (folder.enabled) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (folder.isSyncing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          Icons.check_circle_outline,
                          color: scheme.primary,
                          size: 18,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          folder.isSyncing
                              ? 'Syncing… (${folder.pendingCount} file(s) being checked)'
                              : folder.lastSyncAt == null
                              ? 'Not synced yet.'
                              : 'Last synced '
                                    '${DateFormat.yMMMd().add_jm().format(folder.lastSyncAt!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: folder.isSyncing ? null : folder.syncNow,
                        child: const Text('Sync now'),
                      ),
                    ],
                  ),
                  if (folder.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last error: ${folder.lastError}',
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Recent activity'),
                ),
                if (folder.recentEvents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('Nothing synced yet.'),
                  )
                else
                  ...folder.recentEvents
                      .take(30)
                      .map((e) => _EventRow(event: e)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _enable(AppState state) async {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    try {
      await state.syncFolder.enable(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not enable sync: $e')));
    }
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final SyncFolderEvent event;

  IconData get _icon => switch (event.action) {
    SyncFolderAction.uploadNew ||
    SyncFolderAction.uploadChanged => Icons.cloud_upload_outlined,
    SyncFolderAction.downloadNew ||
    SyncFolderAction.downloadChanged => Icons.cloud_download_outlined,
    SyncFolderAction.deleteLocal ||
    SyncFolderAction.deleteRemote => Icons.delete_outline,
    SyncFolderAction.conflictKeepBoth => Icons.call_split,
    SyncFolderAction.unchanged => Icons.check,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(_icon, size: 18, color: event.failed ? scheme.error : null),
      title: Text(event.relativePath, overflow: TextOverflow.ellipsis),
      subtitle: Text(event.error ?? event.label),
      trailing: Text(
        DateFormat.jm().format(event.at),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_disabled, size: 48, color: scheme.outline),
            const SizedBox(height: 14),
            Text(
              'Not available here',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sync Folder works on Windows desktop and Android. Use the '
              'Backup tab on this platform for one-way uploads to Drive.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
