import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/storage_models.dart';
import 'native_bridge.dart';
import 'storage_service.dart';

StorageService createStorageService() => IoStorageService();

/// Directory names that are never worth walking: they are either virtual,
/// enormous, or actively hostile to a recursive stat().
const _skipDirNames = <String>{
  r'$recycle.bin',
  r'$windows.~bt',
  r'$windows.~ws',
  'system volume information',
  'windows.old',
  'node_modules',
  '.git',
  '.dart_tool',
  'proc',
  'sys',
  'dev',
};

class IoStorageService implements StorageService {
  @override
  Future<List<VolumeInfo>> listVolumes() async {
    if (Platform.isAndroid) return NativeBridge.instance.volumes();
    if (Platform.isWindows) return _windowsVolumes();
    return _posixVolumes();
  }

  Future<List<VolumeInfo>> _windowsVolumes() async {
    // CIM is the supported replacement for wmic, which ships disabled on
    // current Windows builds.
    const script =
        r'Get-CimInstance Win32_LogicalDisk | ForEach-Object { '
        r'"$($_.DeviceID)|$($_.VolumeName)|$($_.Size)|$($_.FreeSpace)|$($_.DriveType)" }';
    try {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      );
      if (r.exitCode != 0) return _fallbackWindowsVolume();
      final volumes = <VolumeInfo>[];
      for (final line in (r.stdout as String).split('\n')) {
        final parts = line.trim().split('|');
        if (parts.length < 5) continue;
        final total = int.tryParse(parts[2]) ?? 0;
        if (total == 0) continue; // empty optical / card reader slot
        final letter = parts[0];
        volumes.add(VolumeInfo(
          id: letter,
          label: parts[1].isEmpty ? 'Local Disk ($letter)' : '${parts[1]} ($letter)',
          path: '$letter\\',
          totalBytes: total,
          freeBytes: int.tryParse(parts[3]) ?? 0,
          isRemovable: parts[4] == '2',
          isPrimary: letter.toUpperCase() ==
              (Platform.environment['SystemDrive'] ?? 'C:').toUpperCase(),
        ));
      }
      return volumes.isEmpty ? _fallbackWindowsVolume() : volumes;
    } on ProcessException {
      return _fallbackWindowsVolume();
    }
  }

  List<VolumeInfo> _fallbackWindowsVolume() {
    final sys = Platform.environment['SystemDrive'] ?? 'C:';
    return [
      VolumeInfo(
        id: sys,
        label: 'Local Disk ($sys)',
        path: '$sys\\',
        totalBytes: 0,
        freeBytes: 0,
        isPrimary: true,
      ),
    ];
  }

  Future<List<VolumeInfo>> _posixVolumes() async {
    try {
      final r = await Process.run('df', ['-kP']);
      final volumes = <VolumeInfo>[];
      final lines = (r.stdout as String).split('\n').skip(1);
      for (final line in lines) {
        final f = line.trim().split(RegExp(r'\s+'));
        if (f.length < 6) continue;
        final total = (int.tryParse(f[1]) ?? 0) * 1024;
        final free = (int.tryParse(f[3]) ?? 0) * 1024;
        if (total == 0 || !f[0].startsWith('/dev/')) continue;
        volumes.add(VolumeInfo(
          id: f[5],
          label: '${f[5]} (${f[0]})',
          path: f[5],
          totalBytes: total,
          freeBytes: free,
          isPrimary: f[5] == '/',
        ));
      }
      return volumes;
    } on ProcessException {
      return const [
        VolumeInfo(
            id: '/', label: 'Root', path: '/', totalBytes: 0, freeBytes: 0, isPrimary: true),
      ];
    }
  }

  /// The folders a phone (or a desktop with a synced camera folder) puts new
  /// photos and videos in.
  Future<List<String>> _mediaRoots() async {
    if (Platform.isAndroid) {
      final roots = await NativeBridge.instance.readableRoots();
      return roots
          .where((r) {
            final n = p.basename(r).toLowerCase();
            return n == 'dcim' || n == 'pictures' || n == 'movies' || n == 'camera';
          })
          .toList();
    }
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return const [];
    return [
      for (final name in const ['Pictures', 'Videos', 'Camera Roll'])
        if (Directory(p.join(home, name)).existsSync()) p.join(home, name),
    ];
  }

  @override
  Future<List<FileEntry>> newMediaSince(DateTime? since, {int limit = 200}) async {
    final cutoff = since ?? DateTime.fromMillisecondsSinceEpoch(0);
    final found = <FileEntry>[];
    final queue = <Directory>[for (final r in await _mediaRoots()) Directory(r)];

    while (queue.isNotEmpty && found.length < limit) {
      final dir = queue.removeLast();
      if (_skipDirNames.contains(p.basename(dir.path).toLowerCase())) continue;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        if (e is Directory) {
          queue.add(e);
          continue;
        }
        if (e is! File) continue;
        final cat = FileCategory.forExtension(p.extension(e.path));
        if (cat != FileCategory.images && cat != FileCategory.videos) continue;
        FileStat st;
        try {
          st = e.statSync();
        } on FileSystemException {
          continue;
        }
        if (!st.modified.isAfter(cutoff)) continue;
        found.add(FileEntry(
          path: e.path,
          name: p.basename(e.path),
          bytes: st.size,
          modified: st.modified,
          category: cat,
        ));
      }
    }
    found.sort((a, b) => b.modified.compareTo(a.modified));
    return found.take(limit).toList();
  }

  @override
  Future<String> deviceLabel() async {
    if (Platform.isAndroid) {
      final name = await NativeBridge.instance.deviceName();
      return name.isEmpty ? 'Android device' : name;
    }
    final host = Platform.localHostname;
    return host.isEmpty ? '${Platform.operatingSystem} device' : host;
  }

  @override
  Future<List<String>> readableRoots(VolumeInfo volume) async {
    if (!Platform.isAndroid) return [volume.path];
    return NativeBridge.instance.readableRoots();
  }

  @override
  Stream<ScanProgress> scan(
    VolumeInfo volume, {
    Duration budget = const Duration(seconds: 45),
    int maxLargestFiles = 50,
  }) async* {
    final started = DateTime.now();
    final deadline = started.add(budget);
    final categories = <FileCategory, CategoryUsage>{
      for (final c in FileCategory.values) c: CategoryUsage(c, 0, 0),
    };
    final largest = <FileEntry>[];
    final skipped = <String>[];
    var files = 0;
    var bytes = 0;
    var partial = false;
    var lastEmit = DateTime.now();

    final roots = await readableRoots(volume);
    final queue = <Directory>[for (final r in roots) Directory(r)];

    while (queue.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        partial = true;
        skipped.add('Time budget reached with ${queue.length} folders unvisited.');
        break;
      }
      final dir = queue.removeLast();
      final name = p.basename(dir.path).toLowerCase();
      if (_skipDirNames.contains(name)) continue;

      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        skipped.add(dir.path);
        partial = true;
        continue;
      }

      for (final e in entries) {
        if (e is Directory) {
          queue.add(e);
        } else if (e is File) {
          FileStat st;
          try {
            st = e.statSync();
          } on FileSystemException {
            continue;
          }
          if (st.type != FileSystemEntityType.file) continue;
          final cat = FileCategory.forExtension(p.extension(e.path));
          final usage = categories[cat]!;
          usage.bytes += st.size;
          usage.fileCount += 1;
          files += 1;
          bytes += st.size;

          _insertLargest(
            largest,
            FileEntry(
              path: e.path,
              name: p.basename(e.path),
              bytes: st.size,
              modified: st.modified,
              category: cat,
            ),
            maxLargestFiles,
          );
        }
      }

      // Throttle UI updates: one per 120ms keeps the bar smooth without
      // drowning the event loop on a disk with millions of files.
      final now = DateTime.now();
      if (now.difference(lastEmit).inMilliseconds > 120) {
        lastEmit = now;
        yield ScanProgress(filesSeen: files, bytesSeen: bytes, currentPath: dir.path);
      }
    }

    final result = ScanResult(
      volume: volume,
      categories: categories.values.where((c) => c.fileCount > 0).toList()
        ..sort((a, b) => b.bytes.compareTo(a.bytes)),
      largestFiles: largest,
      scannedFiles: files,
      scannedBytes: bytes,
      duration: DateTime.now().difference(started),
      partial: partial,
      skippedPaths: skipped.take(25).toList(),
    );
    yield ScanProgress(
      filesSeen: files,
      bytesSeen: bytes,
      currentPath: '',
      result: result,
    );
  }

  void _insertLargest(List<FileEntry> list, FileEntry entry, int cap) {
    if (list.length >= cap && entry.bytes <= list.last.bytes) return;
    var i = list.indexWhere((e) => e.bytes < entry.bytes);
    if (i < 0) i = list.length;
    list.insert(i, entry);
    if (list.length > cap) list.removeLast();
  }
}
