import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';

/// The biggest files on the selected volume — the offload shortlist.
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  FileCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scan = state.currentScan;

    if (scan == null) {
      return _Empty(
        icon: Icons.folder_open_outlined,
        title: 'Nothing analysed yet',
        body: state.selected == null
            ? 'Pick a volume on the Dashboard first.'
            : 'Run "Analyse storage" on the Dashboard to list the largest '
                'files on ${state.selected!.label}.',
      );
    }

    final files = _filter == null
        ? scan.largestFiles
        : scan.largestFiles.where((f) => f.category == _filter).toList();
    final date = DateFormat.yMMMd();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Largest files on ${scan.volume.label}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              DropdownButton<FileCategory?>(
                value: _filter,
                hint: const Text('All types'),
                underline: const SizedBox.shrink(),
                onChanged: (v) => setState(() => _filter = v),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All types')),
                  for (final c in scan.categories)
                    DropdownMenuItem(
                      value: c.category,
                      child: Text(c.category.label),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? const _Empty(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No files match',
                  body: 'Try a different type filter.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final f = files[i];
                    return ListTile(
                      leading: Icon(_iconFor(f.category)),
                      title: Text(f.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${f.path}\n${f.category.label} · modified '
                        '${date.format(f.modified)} (${f.ageInDays}d ago)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatBytes(f.bytes),
                              style: Theme.of(context).textTheme.titleSmall),
                          TextButton(
                            onPressed: () {
                              state.sync.queue([f]);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${f.name} queued for backup'),
                                ),
                              );
                            },
                            child: const Text('Queue'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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
                Text(body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}
