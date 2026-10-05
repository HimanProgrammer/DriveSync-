import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/storage_models.dart';
import 'browse_service.dart';

BrowseService createBrowseService() => IoBrowseService();

/// Windows/Android housekeeping folders nobody browses on purpose.
const _hidden = {
  r'$recycle.bin',
  'system volume information',
  'desktop.ini',
  'thumbs.db',
  r'$windows.~bt',
  r'$windows.~ws',
};

class IoBrowseService implements BrowseService {
  @override
  bool get available => true;

  @override
  Future<List<BrowseEntry>> list(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw BrowseException('This folder is no longer available.');
    }
    final entries = <BrowseEntry>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (_hidden.contains(name.toLowerCase())) continue;
        if (e is Directory) {
          entries.add(BrowseEntry(name: name, path: e.path, isDir: true));
        } else if (e is File) {
          try {
            final st = await e.stat();
            entries.add(
              BrowseEntry(
                name: name,
                path: e.path,
                isDir: false,
                bytes: st.size,
                modified: st.modified,
              ),
            );
          } on FileSystemException {
            // Locked or vanished between listing and stat — skip it.
          }
        }
      }
    } on FileSystemException catch (e) {
      if (entries.isEmpty) {
        throw BrowseException(
          'Cannot open this folder: ${e.osError?.message ?? e.message}',
        );
      }
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<List<FileEntry>> collectFiles(Iterable<BrowseEntry> entries) async {
    final out = <FileEntry>[];
    final seen = <String>{};

    Future<void> addFile(File f) async {
      if (!seen.add(f.path)) return;
      try {
        final st = await f.stat();
        out.add(
          FileEntry(
            path: f.path,
            name: p.basename(f.path),
            bytes: st.size,
            modified: st.modified,
            category: FileCategory.forExtension(p.extension(f.path)),
          ),
        );
      } on FileSystemException {
        // Unreadable file: leave it out rather than failing the whole batch.
      }
    }

    for (final e in entries) {
      if (!e.isDir) {
        await addFile(File(e.path));
        continue;
      }
      try {
        await for (final child in Directory(
          e.path,
        ).list(recursive: true, followLinks: false)) {
          if (child is File &&
              !_hidden.contains(p.basename(child.path).toLowerCase())) {
            await addFile(child);
          }
        }
      } on FileSystemException {
        // A sub-folder we may not enter ends that branch, not the batch.
      }
    }
    return out;
  }
}
