import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../models/sync_models.dart';

/// A durable log of what has actually gone to Drive — unlike the Backup tab's
/// live queue, this survives "Clear finished" and app restarts, so "did I
/// already back up X" has an answer weeks later.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  FileCategory? _filter;
  bool _failedOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.sync.history();
    final records = all
        .where((r) => _filter == null || r.category == _filter)
        .where((r) => !_failedOnly || !r.succeeded)
        .toList();

    final totalUploaded = all.where((r) => r.succeeded).fold(0, (a, r) => a + r.bytes);
    final categories = all.map((r) => r.category).toSet().toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Upload history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (all.isNotEmpty)
                Text(
                  '${all.where((r) => r.succeeded).length} uploaded · '
                  '${formatBytes(totalUploaded)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<FileCategory?>(
                  value: _filter,
                  hint: const Text('All types'),
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _filter = v),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All types')),
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                ),
                FilterChip(
                  label: const Text('Failed only'),
                  selected: _failedOnly,
                  onSelected: (v) => setState(() => _failedOnly = v),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _confirmClear(context, state),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear history'),
                ),
              ],
            ),
          ),
        Expanded(
          child: records.isEmpty
              ? _Empty(hasAny: all.isNotEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _HistoryRow(record: records[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear upload history?'),
        content: const Text(
          'This only clears the log on this device — files already uploaded '
          'stay in your Google Drive untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await state.sync.clearHistory();
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});
  final UploadRecord record;

  IconData get _icon => switch (record.category) {
        FileCategory.images => Icons.image_outlined,
        FileCategory.videos => Icons.movie_outlined,
        FileCategory.audio => Icons.audiotrack_outlined,
        FileCategory.documents => Icons.description_outlined,
        FileCategory.archives => Icons.folder_zip_outlined,
        FileCategory.code => Icons.code,
        FileCategory.apps => Icons.apps_outlined,
        FileCategory.other => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateFormat.yMMMd().add_jm().format(record.uploadedAt);
    return ListTile(
      leading: Icon(
        record.succeeded ? _icon : Icons.error_outline,
        color: record.succeeded ? null : scheme.error,
      ),
      title: Text(record.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        record.succeeded
            ? 'DriveSync/${record.deviceLabel} · $when'
            : 'Failed · $when',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: record.succeeded ? null : scheme.error),
      ),
      trailing: Text(formatBytes(record.bytes), style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasAny});
  final bool hasAny;

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
                  hasAny ? Icons.filter_alt_off_outlined : Icons.history,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 14),
                Text(
                  hasAny ? 'No entries match' : 'Nothing uploaded yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  hasAny
                      ? 'Try a different filter.'
                      : 'Files you back up will show up here, even after you '
                          'clear the Backup tab\'s queue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
}
