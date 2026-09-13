import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/storage_models.dart';
import '../../services/settings_service.dart';

/// The first-run popup: "keep files on Drive automatically, or ask me first?"
/// Answering either way records the choice so this never reappears; it can be
/// changed later from Settings.
Future<void> showAutoModeDialog(BuildContext context, AppState state) async {
  final s = state.settings.value;
  final chosen = await showDialog<SyncMode>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.cloud_sync_outlined, size: 32),
      title: const Text('Turn on Auto mode?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In Auto mode DriveSync watches your storage and copies large, '
            'older files to your Google Drive on its own once a volume passes '
            '${(s.triggerFraction * 100).round()}% full.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _Bullet('Only files over ${formatBytes(s.minFileBytes)} are considered.'),
          _Bullet('Local copies are kept unless you turn that off in Settings.'),
          _Bullet('You can switch to Manual at any time.'),
          const SizedBox(height: 12),
          Text(
            'In Manual mode nothing is uploaded until you press Back up now.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, SyncMode.manual),
          child: const Text('Keep Manual'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, SyncMode.auto),
          child: const Text('Turn on Auto'),
        ),
      ],
    ),
  );

  // A dismissed dialog still counts as answered: default to the safer Manual.
  await state.settings.setMode(chosen ?? SyncMode.manual);
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
}
