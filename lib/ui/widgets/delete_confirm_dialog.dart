import 'package:flutter/material.dart';

import '../../app_state.dart';
import 'partition_path.dart';

/// Works through [AppState.sync.pendingDeletions] one popup at a time: each
/// uploaded file gets its own Delete / Keep prompt rather than being deleted
/// silently. Safe to call repeatedly — it no-ops while a dialog is already up
/// or the list is empty, and re-checks after each answer in case more
/// arrived while this one was open.
Future<void> maybeShowDeleteConfirmations(
  BuildContext context,
  AppState state,
) async {
  while (state.sync.pendingDeletions.isNotEmpty) {
    if (!context.mounted) return;
    final task = state.sync.pendingDeletions.first;
    final volume = volumeForPath(state.volumes, task.file.path);

    final delete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cloud_done_outlined, size: 32),
        title: const Text('Uploaded — delete the original?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${task.file.name} is confirmed in your Drive.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            PartitionPath(volume: volume, path: task.file.path),
            const SizedBox(height: 12),
            Text(
              'Deleting the local copy cannot be undone from here — the '
              'only remaining copy will be the one in Drive.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (delete == true) {
      await state.sync.confirmDelete(task);
    } else {
      // A dismissed dialog (back button, etc.) counts as "keep" — never
      // delete without an explicit yes.
      state.sync.keepFile(task);
    }
  }
}
