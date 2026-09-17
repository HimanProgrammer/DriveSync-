import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../models/sync_models.dart';

enum _DateFilter { all, today, month, year }

extension on _DateFilter {
  String get label => switch (this) {
    _DateFilter.all => 'All time',
    _DateFilter.today => 'Today',
    _DateFilter.month => 'This month',
    _DateFilter.year => 'This year',
  };

  bool includes(DateTime at) {
    final now = DateTime.now();
    return switch (this) {
      _DateFilter.all => true,
      _DateFilter.today =>
        at.year == now.year && at.month == now.month && at.day == now.day,
      _DateFilter.month => at.year == now.year && at.month == now.month,
      _DateFilter.year => at.year == now.year,
    };
  }
}

enum _ViewMode { list, grid }

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
  _DateFilter _dateFilter = _DateFilter.all;
  _ViewMode _view = _ViewMode.list;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.sync.history();
    final records = all
        .where((r) => _filter == null || r.category == _filter)
        .where((r) => !_failedOnly || !r.succeeded)
        .where((r) => _dateFilter.includes(r.uploadedAt))
        .toList();
    final failedInView = records.where((r) => !r.succeeded).toList();

    final totalUploaded = all
        .where((r) => r.succeeded)
        .fold(0, (a, r) => a + r.bytes);
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
              const SizedBox(width: 12),
              IconButton(
                tooltip: _view == _ViewMode.list
                    ? 'Switch to grid'
                    : 'Switch to list',
                onPressed: () => setState(
                  () => _view = _view == _ViewMode.list
                      ? _ViewMode.grid
                      : _ViewMode.list,
                ),
                icon: Icon(
                  _view == _ViewMode.list
                      ? Icons.grid_view_outlined
                      : Icons.view_list_outlined,
                ),
              ),
            ],
          ),
        ),
        if (all.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<_DateFilter>(
                  value: _dateFilter,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) =>
                      v == null ? null : setState(() => _dateFilter = v),
                  items: [
                    for (final d in _DateFilter.values)
                      DropdownMenuItem(value: d, child: Text(d.label)),
                  ],
                ),
                DropdownButton<FileCategory?>(
                  value: _filter,
                  hint: const Text('All types'),
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _filter = v),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All types'),
                    ),
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                ),
                FilterChip(
                  label: const Text('Failed only'),
                  selected: _failedOnly,
                  onSelected: (v) => setState(() => _failedOnly = v),
                ),
                if (failedInView.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      for (final r in failedInView) {
                        state.sync.requeueFromHistory(r);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${failedInView.length} file(s) queued for retry '
                            'in the Backup tab.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text('Retry all ${failedInView.length} failed'),
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
              : _view == _ViewMode.list
              ? ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _HistoryRow(
                    record: records[i],
                    onRetry: () => _retry(context, state, records[i]),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: records.length,
                  itemBuilder: (context, i) => _HistoryTile(
                    record: records[i],
                    onRetry: () => _retry(context, state, records[i]),
                  ),
                ),
        ),
      ],
    );
  }

  void _retry(BuildContext context, AppState state, UploadRecord record) {
    state.sync.requeueFromHistory(record);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${record.name} queued for retry in the Backup tab.'),
      ),
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

IconData _iconFor(FileCategory c) => switch (c) {
  FileCategory.images => Icons.image_outlined,
  FileCategory.videos => Icons.movie_outlined,
  FileCategory.audio => Icons.audiotrack_outlined,
  FileCategory.documents => Icons.description_outlined,
  FileCategory.archives => Icons.folder_zip_outlined,
  FileCategory.code => Icons.code,
  FileCategory.apps => Icons.apps_outlined,
  FileCategory.other => Icons.insert_drive_file_outlined,
};

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record, required this.onRetry});
  final UploadRecord record;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateFormat.yMMMd().add_jm().format(record.uploadedAt);
    return ListTile(
      leading: Icon(
        record.succeeded ? _iconFor(record.category) : Icons.error_outline,
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
      trailing: record.succeeded
          ? Text(
              formatBytes(record.bytes),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatBytes(record.bytes),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Retry',
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.onRetry});
  final UploadRecord record;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateFormat.yMMMd().format(record.uploadedAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              record.succeeded
                  ? _iconFor(record.category)
                  : Icons.error_outline,
              size: 32,
              color: record.succeeded ? scheme.primary : scheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              record.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              formatBytes(record.bytes),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              record.succeeded ? when : 'Failed · $when',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: record.succeeded ? null : scheme.error,
              ),
            ),
            if (!record.succeeded)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ),
          ],
        ),
      ),
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
