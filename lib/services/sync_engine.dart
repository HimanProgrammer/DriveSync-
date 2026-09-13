import 'package:flutter/foundation.dart';

import '../models/storage_models.dart';
import '../models/sync_models.dart';
import 'connectivity_service.dart';
import 'drive_service.dart';
import 'local_file_source.dart';
import 'offline_cache.dart';
import 'settings_service.dart';

/// Decides *what* to offload and then does it, one file at a time so a big
/// queue never saturates the connection or the API quota.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required LocalFileSource files,
    required this.settings,
    required this.connectivity,
    required OfflineCache cache,
  })  : _files = files,
        _cache = cache {
    // Restore anything chosen before the app was last closed (or while it was
    // offline) so the queue is never silently lost.
    for (final entry in _cache.queue()) {
      _tasks.add(SyncTask(file: entry));
    }
    connectivity.addListener(_onLinkChanged);
  }

  final LocalFileSource _files;
  final SettingsService settings;
  final ConnectivityService connectivity;
  final OfflineCache _cache;

  /// Set when auto mode wanted to run but the link did not allow it, so we can
  /// resume the moment a usable connection appears.
  bool _deferred = false;
  String? _deviceFolder;

  DriveService? _drive;
  final List<SyncTask> _tasks = [];
  bool _running = false;
  bool _cancelled = false;
  int _uploaded = 0;
  int _freed = 0;
  DateTime? _lastRun;
  String? _message;

  void attachDrive(DriveService? drive) {
    _drive = drive;
    notifyListeners();
  }

  bool get isConnected => _drive != null;

  SyncStatus get status => SyncStatus(
        tasks: List.unmodifiable(_tasks),
        running: _running,
        uploadedBytes: _uploaded,
        freedBytes: _freed,
        lastRun: _lastRun,
        message: _message,
      );

  /// Files worth sending: over the size floor, in an enabled category. Oldest
  /// first, then largest, so the least-missed bytes leave the device first.
  List<FileEntry> plan(ScanResult scan) {
    final s = settings.value;
    final candidates = scan.largestFiles
        .where((f) => f.bytes >= s.minFileBytes)
        .where((f) => s.categories.contains(f.category))
        .toList();
    candidates.sort((a, b) {
      final byAge = b.ageInDays.compareTo(a.ageInDays);
      return byAge != 0 ? byAge : b.bytes.compareTo(a.bytes);
    });
    return candidates;
  }

  /// True when auto mode should fire for this volume right now.
  bool shouldAutoRun(ScanResult scan) {
    final s = settings.value;
    if (!s.isAuto || _drive == null || _running) return false;
    if (scan.volume.totalBytes == 0) return false;
    return scan.volume.usedFraction >= s.triggerFraction &&
        plan(scan).isNotEmpty;
  }

  void queue(List<FileEntry> entries) {
    final known = _tasks.map((t) => t.file.path).toSet();
    for (final e in entries) {
      if (known.contains(e.path)) continue;
      _tasks.add(SyncTask(file: e));
    }
    _persistQueue();
    notifyListeners();
  }

  void clearFinished() {
    _tasks.removeWhere((t) => t.isFinished);
    _persistQueue();
    notifyListeners();
  }

  void _persistQueue() {
    _cache.saveQueue([
      for (final t in _tasks.where((t) => !t.isFinished)) t.file,
    ]);
  }

  /// Picks up a deferred run once we are back on an allowed connection.
  void _onLinkChanged() {
    if (!_deferred || _running) return;
    final folder = _deviceFolder;
    if (folder == null) return;
    if (!connectivity.canUpload(wifiOnly: settings.value.wifiOnly).allowed) return;
    _deferred = false;
    run(deviceFolder: folder);
  }

  void cancel() {
    if (!_running) return;
    _cancelled = true;
    _message = 'Stopping after the current file…';
    notifyListeners();
  }

  /// Uploads everything queued. [deviceFolder] separates this machine's backup
  /// from the other devices under the same Drive account.
  Future<void> run({required String deviceFolder}) async {
    final drive = _drive;
    if (drive == null) {
      _message = 'Connect a Google account before backing up.';
      notifyListeners();
      return;
    }
    if (_running) return;
    if (!_files.canReadLocalFiles) {
      _message = 'This platform cannot read local files for upload.';
      notifyListeners();
      return;
    }

    _deviceFolder = deviceFolder;
    final link = connectivity.canUpload(wifiOnly: settings.value.wifiOnly);
    if (!link.allowed) {
      // Not a failure: the queue is durable and we retry when the link allows.
      _deferred = true;
      _message = link.reason;
      notifyListeners();
      return;
    }

    _running = true;
    _cancelled = false;
    _message = 'Preparing…';
    notifyListeners();

    try {
      final parentId = await drive.ensureDeviceFolder(deviceFolder);
      final existing = await drive.indexOf(parentId);
      final deleteLocal = settings.value.deleteLocalAfterUpload;

      for (final task in _tasks.where((t) => !t.isFinished).toList()) {
        if (_cancelled) {
          _message = 'Backup stopped. ${_pendingSummary()}';
          break;
        }

        final prior = existing[task.file.path];
        final priorSize = int.tryParse(prior?.size ?? '');
        if (prior != null && priorSize == task.file.bytes) {
          // Same path, same size: already in Drive, nothing to send.
          task.state = SyncTaskState.skipped;
          notifyListeners();
          continue;
        }

        task.state = SyncTaskState.uploading;
        _message = 'Uploading ${task.file.name}…';
        notifyListeners();

        try {
          final length = await _files.lengthOf(task.file.path);
          final result = await drive.upload(
            name: task.file.name,
            length: length,
            content: _countingStream(task, _files.openRead(task.file.path)),
            parentId: parentId,
            mimeType: _files.mimeTypeFor(task.file.path),
            existingFileId: prior?.id,
            appProperties: {
              'dvSourcePath': task.file.path,
              'dvDevice': deviceFolder,
              'dvCategory': task.file.category.name,
            },
          );
          task.driveFileId = result.fileId;
          task.uploadedBytes = task.file.bytes;
          task.state = SyncTaskState.done;
          _uploaded += result.bytes;

          if (deleteLocal) {
            await _files.delete(task.file.path);
            _freed += task.file.bytes;
          }
        } catch (e) {
          task.state = SyncTaskState.failed;
          task.error = e.toString();
        }
        notifyListeners();
      }

      _persistQueue();
      _lastRun = DateTime.now();
      if (!_cancelled) {
        final s = status;
        _message = s.failedCount == 0
            ? 'Backup complete — ${s.doneCount} file(s), '
                '${formatBytes(_uploaded)} uploaded.'
            : '${s.doneCount} uploaded, ${s.failedCount} failed. '
                'Open a failed row for the reason.';
      }
    } catch (e) {
      _message = 'Backup could not start: $e';
    } finally {
      _running = false;
      _cancelled = false;
      notifyListeners();
    }
  }

  String _pendingSummary() {
    final n = status.pendingCount;
    return n == 0 ? 'Nothing left in the queue.' : '$n file(s) still queued.';
  }

  /// True when work is waiting only on the network.
  bool get isWaitingForNetwork => _deferred;

  @override
  void dispose() {
    connectivity.removeListener(_onLinkChanged);
    super.dispose();
  }

  Stream<List<int>> _countingStream(SyncTask task, Stream<List<int>> source) {
    return source.map((chunk) {
      task.uploadedBytes += chunk.length;
      // Notify sparsely: chunk callbacks arrive far faster than frames.
      if (task.uploadedBytes % (1 << 20) < chunk.length) notifyListeners();
      return chunk;
    });
  }
}
