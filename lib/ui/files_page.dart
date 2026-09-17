import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import 'widgets/file_sort.dart';
import 'widgets/partition_path.dart';

/// A file paired with the volume it was found on — the unit this page works
/// in once "All scanned volumes" pulls rows from more than one scan.
class _Row {
  const _Row(this.file, this.volume);
  final FileEntry file;
  final VolumeInfo volume;
}

/// The biggest files on a scanned volume — or across all of them at once — as
/// the offload shortlist. Files are checkbox-selectable so several can be
/// queued for backup together, and every row names the partition/drive it
/// actually lives on.
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

/// null means "the volume currently selected on the Dashboard"; any other
/// value pins the list to that volume regardless of what's selected there;
/// the sentinel below means "every volume that has been scanned".
const _allVolumesId = '__all__';

class _FilesPageState extends State<FilesPage> {
  FileCategory? _filter;
  SortLevel _primarySort = const SortLevel(
    FileSortKey.partition,
    descending: false,
  );
  SortLevel? _secondarySort = const SortLevel(
    FileSortKey.size,
    descending: true,
  );
  String? _volumeId; // null = follow Dashboard's selection
  final Set<String> _selected = {}; // FileEntry.path

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scans = state.scans.values.toList();

    if (scans.isEmpty) {
      return _Empty(
        icon: Icons.folder_open_outlined,
        title: 'Nothing analysed yet',
        body: state.selected == null
            ? 'Pick a volume on the Dashboard first.'
            : 'Run "Analyse storage" on the Dashboard to list the largest '
                  'files on ${state.selected!.label}.',
      );
    }

    final effectiveVolumeId = _volumeId ?? state.selected?.id;
    final showAll = effectiveVolumeId == _allVolumesId;
    final activeScans = showAll
        ? scans
        : scans.where((s) => s.volume.id == effectiveVolumeId).toList();

    var rows = [
      for (final s in activeScans)
        for (final f in s.largestFiles) _Row(f, s.volume),
    ];
    if (_filter != null) {
      rows = rows.where((r) => r.file.category == _filter).toList();
    }
    rows = _sortedRows(rows);
    final date = DateFormat.yMMMd();

    // Drop stale selections when the filter/volume changes what's visible or
    // a re-scan replaces the file list entirely.
    final visiblePaths = rows.map((r) => r.file.path).toSet();
    _selected.removeWhere((p) => !visiblePaths.contains(p));
    final allSelected = rows.isNotEmpty && _selected.length == rows.length;

    // Categories available to filter by, across whichever scans are active.
    final categories = {
      for (final s in activeScans)
        for (final c in s.categories) c.category,
    }.toList()..sort((a, b) => a.label.compareTo(b.label));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: rows.isEmpty
                    ? null
                    : () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(visiblePaths);
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
                        onChanged: rows.isEmpty
                            ? null
                            : (v) => setState(() {
                                if (allSelected) {
                                  _selected.clear();
                                } else {
                                  _selected
                                    ..clear()
                                    ..addAll(visiblePaths);
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
              DropdownButton<String>(
                value: showAll ? _allVolumesId : effectiveVolumeId,
                underline: const SizedBox.shrink(),
                onChanged: (v) => setState(() => _volumeId = v),
                items: [
                  DropdownMenuItem(
                    value: _allVolumesId,
                    child: Text('All scanned volumes (${scans.length})'),
                  ),
                  for (final s in scans)
                    DropdownMenuItem(
                      value: s.volume.id,
                      child: Text(s.volume.label),
                    ),
                ],
              ),
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
              FileSortControl(
                primary: _primarySort,
                secondary: _secondarySort,
                onPrimaryChanged: (v) => setState(() {
                  _primarySort = v;
                  // A secondary sort on the same key as the new primary has
                  // nothing left to break ties on — and would leave the
                  // "then:" dropdown holding a value its own item list just
                  // filtered out, which Flutter treats as a fatal assertion.
                  if (_secondarySort?.key == v.key) _secondarySort = null;
                }),
                onSecondaryChanged: (v) => setState(() => _secondarySort = v),
              ),
            ],
          ),
        ),
        if (_selected.isNotEmpty)
          _SelectionBar(
            count: _selected.length,
            total: rows.length,
            totalBytes: rows
                .where((r) => _selected.contains(r.file.path))
                .fold(0, (a, r) => a + r.file.bytes),
            onSelectAll: allSelected
                ? null
                : () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(visiblePaths);
                  }),
            onQueue: () {
              final chosen = rows
                  .where((r) => _selected.contains(r.file.path))
                  .map((r) => r.file)
                  .toList();
              state.sync.queue(chosen);
              final n = chosen.length;
              setState(_selected.clear);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$n file(s) queued for backup')),
              );
            },
            onClear: () => setState(_selected.clear),
          ),
        Expanded(
          child: rows.isEmpty
              ? const _Empty(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No files match',
                  body: 'Try a different type or volume filter.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final f = row.file;
                    final checked = _selected.contains(f.path);
                    return CheckboxListTile(
                      value: checked,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _selected.add(f.path);
                        } else {
                          _selected.remove(f.path);
                        }
                      }),
                      title: Row(
                        children: [
                          Icon(_iconFor(f.category), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            formatBytes(f.bytes),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          PartitionPath(volume: row.volume, path: f.path),
                          const SizedBox(height: 2),
                          Text(
                            '${f.category.label} · modified '
                            '${date.format(f.modified)} (${f.ageInDays}d ago)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<_Row> _sortedRows(List<_Row> rows) => sortByFileKey(
    items: rows,
    primary: _primarySort,
    secondary: _secondarySort,
    name: (r) => r.file.name,
    bytes: (r) => r.file.bytes,
    date: (r) => r.file.modified,
    partitionLabel: (r) => r.volume.label,
  );

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
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.totalBytes,
    required this.onQueue,
    required this.onClear,
    this.onSelectAll,
  });

  final int count;
  final int total;
  final int totalBytes;
  final VoidCallback onQueue;
  final VoidCallback onClear;

  /// Null once everything visible is already selected.
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count of $total selected · ${formatBytes(totalBytes)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (onSelectAll != null)
            TextButton(onPressed: onSelectAll, child: const Text('Select all')),
          TextButton(onPressed: onClear, child: const Text('Clear')),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: onQueue,
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Queue selected'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
