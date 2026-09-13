import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../models/storage_models.dart';

/// Google Drive connection + quota, and the destination folder this device
/// writes into.
class DriveCard extends StatelessWidget {
  const DriveCard({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quota = state.quota;
    final account = state.account;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_to_drive, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Google Drive',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (state.isConnected)
                  IconButton(
                    tooltip: 'Refresh quota',
                    onPressed: state.refreshQuota,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!state.isConnected) ...[
              Text(
                'Connect an account to keep large files on Drive. DriveSync '
                'asks only for the drive.file scope, so it can see and manage '
                'the files it uploads — nothing else in your Drive.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!DriveConfig.isConfigured) ...[
                const SizedBox(height: 10),
                Text(
                  'No OAuth client is configured yet. See lib/config.dart for '
                  'the --dart-define values this build expects.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.error),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: state.busy ? null : state.connectDrive,
                icon: const Icon(Icons.login),
                label: const Text('Connect Google Drive'),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: account?.photoUrl == null
                      ? null
                      : NetworkImage(account!.photoUrl!),
                  child: account?.photoUrl == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                title: Text(account?.displayName ?? 'Connected'),
                subtitle: Text(account?.email ?? ''),
              ),
              if (quota != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: quota.isUnlimited ? null : quota.usedFraction,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 8),
                Text(quota.summary,
                    style: Theme.of(context).textTheme.bodySmall),
                if (!quota.isUnlimited)
                  Text('${formatBytes(quota.freeBytes)} free for backups',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              Text(
                'Uploads go to '
                '${DriveConfig.rootFolderName}/${state.deviceLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: state.disconnectDrive,
                icon: const Icon(Icons.logout),
                label: const Text('Disconnect'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
