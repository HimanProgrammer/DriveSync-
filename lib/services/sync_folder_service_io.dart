import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../models/sync_folder_models.dart';
import 'drive_service.dart';
import 'sync_folder_service.dart';

SyncFolderService createSyncFolderService() => IoSyncFolderService();

const _manifestFileName = '.drivesync-manifest.json';
const _skipNames = {
  _manifestFileName,
  '.git',
  'node_modules',
  'desktop.ini',
  'thumbs.db',
  '.ds_store',
};

/// Marks an in-progress download; never itself treated as a syncable file.
const _tempSuffix = '.drivesync.tmp';

/// A `.tmp` file left behind by an interrupted download older than this is
/// assumed abandoned (the app crashed, or was killed mid-transfer) and is
/// swept away rather than sitting there taking up space indefinitely.
const _staleTempAge = Duration(hours: 1);

/// See [SyncFolderService] for the behavioural contract. Active on Windows
/// desktop and Android; other IO targets report [isSupported] == false and
/// refuse [enable].
class IoSyncFolderService extends ChangeNotifier implements SyncFolderService {
  DriveService? _drive;
  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _watchSub;
  Timer? _pollTimer;
  Timer? _debounce;

  bool _enabled = false;
  String? _localPath;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String? _lastError;
  int _pendingCount = 0;
  final List<SyncFolderEvent> _events = [];
  Map<String, SyncFileRecord> _manifest = {};

  @override
  bool get isSupported => !kIsWeb && (Platform.isWindows || Platform.isAndroid);

  @override
  bool get enabled => _enabled;

  @override
  String? get localPath => _localPath;

  @override
  String get suggestedLocalPath {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '';
      return home.isEmpty ? '' : p.join(home, 'Documents', 'DriveSync');
    }
    if (Platform.isAndroid) {
      // The public shared-storage root — the same place a phone's Files app
      // shows folders like DCIM and Download.
      return p.join('/storage/emulated/0', 'DriveSync');
    }
    return '';
  }

  @override
  bool get isSyncing => _syncing;

  @override
  DateTime? get lastSyncAt => _lastSyncAt;

  @override
  String? get lastError => _lastError;

  @override
  int get pendingCount => _pendingCount;

  @override
  List<SyncFolderEvent> get recentEvents => List.unmodifiable(_events);

  @override
  void attachDrive(DriveService? drive) {
    _drive = drive;
    notifyListeners();
  }

  @override
  Future<void> enable(String localPath) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Sync Folder is only available on Windows desktop and Android.',
      );
    }
    final dir = Directory(localPath);
    await dir.create(recursive: true);

    _localPath = localPath;
    _enabled = true;
    _lastError = null;
    await _loadManifest();
    notifyListeners();

    _watcher = DirectoryWatcher(localPath);
    _watchSub = _watcher!.events.listen((_) => _scheduleDebouncedSync());
    _pollTimer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());

    unawaited(syncNow());
  }

  @override
  Future<void> disable() async {
    _enabled = false;
    await _watchSub?.cancel();
    _watchSub = null;
    _watcher = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounce?.cancel();
    _debounce = null;
    notifyListeners();
  }

  void _scheduleDebouncedSync() {
    _debounce?.cancel();
    // Batches a burst of file events (e.g. a big copy-paste) into one pass
    // instead of racing a sync per file.
    _debounce = Timer(const Duration(seconds: 3), () => syncNow());
  }

  @override
  Future<void> syncNow() async {
    if (!_enabled || _syncing) return;
    final drive = _drive;
    final localPath = _localPath;
    if (drive == null || localPath == null) return;

    _syncing = true;
    _lastError = null;
    notifyListeners();

    try {
      await _cleanupStaleTempFiles(Directory(localPath));
      final rootId = await drive.ensureSyncFolder(const []);
      final local = await _scanLocal(Directory(localPath), localPath);
      final remote = await _scanRemote(drive, rootId, '');

      final allPaths = {...local.keys, ...remote.keys, ..._manifest.keys};
      _pendingCount = allPaths.length;
      notifyListeners();

      final nextManifest = <String, SyncFileRecord>{};
      for (final path in allPaths) {
        final l = local[path];
        final r = remote[path];
        final prior = _manifest[path];
        final updated = await _resolveOne(
          drive: drive,
          localPath: localPath,
          relativePath: path,
          localFile: l,
          remoteFile: r,
          prior: prior,
        );
        if (updated != null) nextManifest[path] = updated;
      }

      _manifest = nextManifest;
      await _saveManifest();
      _lastSyncAt = DateTime.now();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _syncing = false;
      _pendingCount = 0;
      notifyListeners();
    }
  }

  /// Decides and applies the action for one relative path, returning its new
  /// manifest record (or null if the file no longer exists on either side).
  Future<SyncFileRecord?> _resolveOne({
    required DriveService drive,
    required String localPath,
    required String relativePath,
    required _LocalFile? localFile,
    required gdrive.File? remoteFile,
    required SyncFileRecord? prior,
  }) async {
    final absPath = p.join(localPath, relativePath);
    final remoteModifiedMs = remoteFile?.modifiedTime?.millisecondsSinceEpoch;
    final remoteSize = int.tryParse(remoteFile?.size ?? '');

    // Present nowhere: nothing to do, drop from the manifest.
    if (localFile == null && remoteFile == null) return null;

    // New on one side only.
    if (localFile != null && remoteFile == null && prior?.remoteId == null) {
      return _upload(
        drive,
        localPath,
        relativePath,
        SyncFolderAction.uploadNew,
      );
    }
    if (remoteFile != null &&
        localFile == null &&
        prior?.localModifiedMs == null) {
      return _download(
        drive,
        localPath,
        relativePath,
        remoteFile,
        SyncFolderAction.downloadNew,
      );
    }

    // Was synced before; now missing on one side — the other side deleted it.
    if (localFile == null &&
        remoteFile != null &&
        prior?.localModifiedMs != null) {
      await drive.delete(remoteFile.id!);
      _log(relativePath, SyncFolderAction.deleteRemote);
      return null;
    }
    if (remoteFile == null && localFile != null && prior?.remoteId != null) {
      await File(absPath).delete();
      _log(relativePath, SyncFolderAction.deleteLocal);
      return null;
    }

    // Present on both sides.
    if (localFile != null && remoteFile != null) {
      final localChanged =
          prior == null || prior.localModifiedMs != localFile.modifiedMs;
      final remoteChanged =
          prior == null || prior.remoteModifiedMs != remoteModifiedMs;

      if (!localChanged && !remoteChanged) {
        _log(relativePath, SyncFolderAction.unchanged);
        return SyncFileRecord(
          relativePath: relativePath,
          localModifiedMs: localFile.modifiedMs,
          localSize: localFile.size,
          remoteId: remoteFile.id,
          remoteModifiedMs: remoteModifiedMs,
          remoteSize: remoteSize,
        );
      }
      if (localChanged && !remoteChanged) {
        return _upload(
          drive,
          localPath,
          relativePath,
          SyncFolderAction.uploadChanged,
          existingFileId: remoteFile.id,
        );
      }
      if (remoteChanged && !localChanged) {
        return _download(
          drive,
          localPath,
          relativePath,
          remoteFile,
          SyncFolderAction.downloadChanged,
        );
      }

      // Both changed since the last pass: never silently pick one. Keep the
      // remote version at the original name, and preserve the local edit as
      // a clearly-named sibling that also gets uploaded, so nothing is lost.
      return _resolveConflict(drive, localPath, relativePath, remoteFile);
    }

    // First time this path has ever been seen on both sides (no prior
    // record) with matching size: treat as already the same file rather than
    // a conflict.
    if (localFile != null &&
        remoteFile != null &&
        localFile.size == remoteSize) {
      return SyncFileRecord(
        relativePath: relativePath,
        localModifiedMs: localFile.modifiedMs,
        localSize: localFile.size,
        remoteId: remoteFile.id,
        remoteModifiedMs: remoteModifiedMs,
        remoteSize: remoteSize,
      );
    }

    return prior;
  }

  Future<SyncFileRecord> _upload(
    DriveService drive,
    String localPath,
    String relativePath,
    SyncFolderAction action, {
    String? existingFileId,
  }) async {
    final absPath = p.join(localPath, relativePath);
    final file = File(absPath);
    final stat = await file.stat();
    final segments = p
        .split(p.dirname(relativePath))
        .where((s) => s != '.')
        .toList();
    final folderId = await drive.ensureSyncFolder(segments);
    final result = await drive.upload(
      name: p.basename(relativePath),
      length: stat.size,
      content: file.openRead(),
      parentId: folderId,
      existingFileId: existingFileId,
    );
    _log(relativePath, action);
    return SyncFileRecord(
      relativePath: relativePath,
      localModifiedMs: stat.modified.millisecondsSinceEpoch,
      localSize: stat.size,
      remoteId: result.fileId,
      remoteModifiedMs: DateTime.now().millisecondsSinceEpoch,
      remoteSize: result.bytes,
    );
  }

  Future<SyncFileRecord> _download(
    DriveService drive,
    String localPath,
    String relativePath,
    gdrive.File remoteFile,
    SyncFolderAction action,
  ) async {
    final absPath = p.join(localPath, relativePath);
    await Directory(p.dirname(absPath)).create(recursive: true);

    // Download to a temp file first and rename into place only once complete
    // — an interrupted download (crash, network drop) then leaves a `.tmp`
    // file behind instead of a half-written file the next pass would treat
    // as the real, synced copy.
    final tempPath = '$absPath$_tempSuffix';
    final stream = await drive.downloadFile(remoteFile.id!);
    final sink = File(tempPath).openWrite();
    try {
      await stream.pipe(sink);
    } catch (e) {
      await File(tempPath).delete().catchError((_) => File(tempPath));
      rethrow;
    }
    await File(tempPath).rename(absPath);
    final stat = await File(absPath).stat();
    _log(relativePath, action);
    return SyncFileRecord(
      relativePath: relativePath,
      localModifiedMs: stat.modified.millisecondsSinceEpoch,
      localSize: stat.size,
      remoteId: remoteFile.id,
      remoteModifiedMs: remoteFile.modifiedTime?.millisecondsSinceEpoch,
      remoteSize: int.tryParse(remoteFile.size ?? ''),
    );
  }

  Future<SyncFileRecord> _resolveConflict(
    DriveService drive,
    String localPath,
    String relativePath,
    gdrive.File remoteFile,
  ) async {
    final ext = p.extension(relativePath);
    final base = p.basenameWithoutExtension(relativePath);
    final dir = p.dirname(relativePath);
    final stamp = DateFormatStamp.now();
    final conflictRelative = p.join(
      dir == '.' ? '' : dir,
      '$base (conflict copy $stamp)$ext',
    );

    // Move the local edit aside, then bring the local tree back in line with
    // Drive's version at the original name.
    final absOriginal = p.join(localPath, relativePath);
    final absConflict = p.join(localPath, conflictRelative);
    await File(absOriginal).rename(absConflict);
    await _download(
      drive,
      localPath,
      relativePath,
      remoteFile,
      SyncFolderAction.downloadChanged,
    );
    await _upload(
      drive,
      localPath,
      conflictRelative,
      SyncFolderAction.conflictKeepBoth,
    );

    _log(relativePath, SyncFolderAction.conflictKeepBoth);
    final stat = await File(absOriginal).stat();
    return SyncFileRecord(
      relativePath: relativePath,
      localModifiedMs: stat.modified.millisecondsSinceEpoch,
      localSize: stat.size,
      remoteId: remoteFile.id,
      remoteModifiedMs: remoteFile.modifiedTime?.millisecondsSinceEpoch,
      remoteSize: int.tryParse(remoteFile.size ?? ''),
    );
  }

  void _log(String relativePath, SyncFolderAction action, {String? error}) {
    _events.insert(
      0,
      SyncFolderEvent(relativePath: relativePath, action: action, error: error),
    );
    if (_events.length > 200) _events.removeRange(200, _events.length);
  }

  /// Deletes any `.drivesync.tmp` file older than [_staleTempAge] — the
  /// remains of a download that never finished. Never touches anything else,
  /// so this stays purely a cleanup of DriveSync's own scratch files.
  Future<void> _cleanupStaleTempFiles(Directory dir) async {
    if (!dir.existsSync()) return;
    final cutoff = DateTime.now().subtract(_staleTempAge);
    final queue = <Directory>[dir];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        if (e is Directory) {
          queue.add(e);
        } else if (e is File && e.path.endsWith(_tempSuffix)) {
          try {
            if (e.statSync().modified.isBefore(cutoff)) {
              await e.delete();
            }
          } on FileSystemException {
            // Already gone, or briefly locked — either way, next pass
            // catches it.
          }
        }
      }
    }
  }

  Future<Map<String, _LocalFile>> _scanLocal(Directory dir, String root) async {
    final out = <String, _LocalFile>{};
    if (!dir.existsSync()) return out;
    final queue = <Directory>[dir];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        final name = p.basename(e.path);
        if (_skipNames.contains(name.toLowerCase())) continue;
        if (name.endsWith(_tempSuffix)) continue;
        if (e is Directory) {
          queue.add(e);
        } else if (e is File) {
          FileStat stat;
          try {
            stat = e.statSync();
          } on FileSystemException {
            continue;
          }
          final relative = p.relative(e.path, from: root).replaceAll(r'\', '/');
          out[relative] = _LocalFile(
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            size: stat.size,
          );
        }
      }
    }
    return out;
  }

  Future<Map<String, gdrive.File>> _scanRemote(
    DriveService drive,
    String folderId,
    String prefix,
  ) async {
    final out = <String, gdrive.File>{};
    final entries = await drive.listFolder(folderId);
    for (final entry in entries) {
      final relative = prefix.isEmpty ? entry.name! : '$prefix/${entry.name}';
      if (entry.mimeType == 'application/vnd.google-apps.folder') {
        out.addAll(await _scanRemote(drive, entry.id!, relative));
      } else {
        out[relative] = entry;
      }
    }
    return out;
  }

  Future<void> _loadManifest() async {
    final file = _manifestFile;
    if (file == null || !file.existsSync()) {
      _manifest = {};
      return;
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as List;
      _manifest = {
        for (final m in raw.cast<Map<String, dynamic>>())
          SyncFileRecord.fromJson(m).relativePath: SyncFileRecord.fromJson(m),
      };
    } catch (e) {
      debugPrint('DriveSync: unreadable sync manifest, starting fresh ($e)');
      _manifest = {};
    }
  }

  Future<void> _saveManifest() async {
    final file = _manifestFile;
    if (file == null) return;
    await file.writeAsString(
      jsonEncode([for (final r in _manifest.values) r.toJson()]),
    );
  }

  File? get _manifestFile {
    final path = _localPath;
    if (path == null) return null;
    return File(p.join(path, _manifestFileName));
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _pollTimer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}

class _LocalFile {
  const _LocalFile({required this.modifiedMs, required this.size});
  final int modifiedMs;
  final int size;
}

/// A filename-safe timestamp for conflict copies, e.g. "2026-09-17 14-32".
class DateFormatStamp {
  static String now() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}-${two(n.minute)}';
  }
}
