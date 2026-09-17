import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;

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
    required this.volumesProvider,
  }) : _files = files,
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

  /// Current volumes, read fresh on each upload — used to mirror a file's
  /// local folder structure inside Drive.
  final List<VolumeInfo> Function() volumesProvider;

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

  /// Bytes sent over a metered connection this run, not yet flushed to the
  /// persistent counter — batched so every chunk doesn't trigger a disk
  /// write. Flushed every ~1 MB and whenever a run ends.
  int _meteredBytesPending = 0;

  /// Bytes uploaded over mobile data this billing cycle (resets monthly, or
  /// on demand — see [resetMobileDataUsage]), including anything not yet
  /// flushed from the current run.
  int get meteredBytesUsedThisCycle =>
      _cache.meteredBytesUsed + _meteredBytesPending;

  /// True once this cycle's mobile-data usage has reached the Settings cap.
  /// Always false when the cap (mobileDataLimitMb) is 0 — "no limit".
  bool get mobileDataLimitExceeded {
    final limitMb = settings.value.mobileDataLimitMb;
    if (limitMb <= 0) return false;
    return meteredBytesUsedThisCycle >= limitMb * 1024 * 1024;
  }

  Future<void> resetMobileDataUsage() async {
    _meteredBytesPending = 0;
    await _cache.resetMeteredUsage();
    notifyListeners();
  }

  /// Uploaded files waiting on a "delete the original?" answer from the UI —
  /// populated instead of deleting automatically when confirmBeforeDelete is
  /// on. Oldest first, so the UI can work through them one at a time.
  final List<SyncTask> _pendingDeletions = [];
  List<SyncTask> get pendingDeletions => List.unmodifiable(_pendingDeletions);

  /// Paused holds the in-flight upload's byte stream open (mid-file) and
  /// blocks the next file from starting, without losing queue position —
  /// unlike Stop, which ends the run entirely.
  bool _paused = false;
  Completer<void>? _pauseGate;
  bool get isPaused => _paused;

  void pause() {
    if (!_running || _paused) return;
    _paused = true;
    _pauseGate = Completer<void>();
    _message = 'Paused. Resume to continue from where it left off.';
    notifyListeners();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _pauseGate?.complete();
    _pauseGate = null;
    _message = 'Resuming…';
    notifyListeners();
  }

  void attachDrive(DriveService? drive) {
    _drive = drive;
    notifyListeners();
  }

  bool get isConnected => _drive != null;

  /// False on Android and web — see [LocalFileSource.canDeleteLocalFiles].
  bool get canDeleteLocalFiles => _files.canDeleteLocalFiles;

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
    if (!connectivity.canUpload(wifiOnly: settings.value.wifiOnly).allowed)
      return;
    _deferred = false;
    run(deviceFolder: folder);
  }

  void cancel() {
    if (!_running) return;
    _cancelled = true;
    _message = 'Stopping after the current file…';
    // Release a pause so the loop can observe the cancellation and unwind
    // instead of waiting forever for a resume that will never come.
    if (_paused) {
      _paused = false;
      _pauseGate?.complete();
      _pauseGate = null;
    }
    notifyListeners();
  }

  /// Uploads everything queued, or — when [only] is given — just those paths.
  /// [deviceFolder] separates this machine's backup from the other devices
  /// under the same Drive account.
  Future<void> run({required String deviceFolder, Set<String>? only}) async {
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
      final deleteLocal =
          settings.value.deleteLocalAfterUpload && _files.canDeleteLocalFiles;
      final pending =
          _tasks
              .where((t) => !t.isFinished)
              .where((t) => only == null || only.contains(t.file.path))
              .toList()
            // Smallest first: quick wins finish fast and free up a concurrency
            // slot sooner, so a handful of huge files don't stall everything
            // behind them right at the start of a run.
            ..sort((a, b) => a.file.bytes.compareTo(b.file.bytes));

      if (pending.isEmpty) {
        _message = 'Nothing selected to back up.';
        notifyListeners();
        return;
      }

      // A shared cursor into `pending`, advanced by whichever worker asks for
      // the next task next — safe without locks since Dart workers only
      // interleave at `await` points, and the increment itself has none.
      var cursor = 0;
      var meteredLimitHit = false;
      final concurrency = settings.value.maxConcurrentUploads.clamp(1, 8);

      Future<void> worker() async {
        while (true) {
          if (_paused) await _pauseGate?.future;
          if (_cancelled || cursor >= pending.length) return;
          if (connectivity.isMetered && mobileDataLimitExceeded) {
            // Don't start anything new over mobile data past the cap — but
            // leave whatever's already in flight to finish rather than
            // aborting it, and leave the rest of the queue untouched for
            // next time (Wi-Fi, or a raised limit).
            meteredLimitHit = true;
            return;
          }
          final task = pending[cursor++];
          await _uploadOne(
            task: task,
            drive: drive,
            deviceFolder: deviceFolder,
            deleteLocal: deleteLocal,
          );
        }
      }

      _message = pending.length > 1
          ? 'Uploading up to $concurrency file(s) at once…'
          : 'Uploading ${pending.isEmpty ? '' : pending.first.file.name}…';
      notifyListeners();

      await Future.wait(List.generate(concurrency, (_) => worker()));

      // Flush whatever metered usage hasn't hit the persistent counter yet,
      // so the cap is checked against an up-to-date total next time.
      if (_meteredBytesPending > 0) {
        final leftover = _meteredBytesPending;
        _meteredBytesPending = 0;
        await _cache.addMeteredBytes(leftover);
      }

      if (_cancelled) {
        _message = 'Backup stopped. ${_pendingSummary()}';
      } else if (meteredLimitHit) {
        _message =
            'Mobile data limit reached '
            '(${settings.value.mobileDataLimitMb} MB this cycle) — '
            'remaining uploads are waiting for Wi-Fi. Raise the limit in '
            'Settings to keep going now.';
      }
      _persistQueue();
      _lastRun = DateTime.now();
      if (!_cancelled && !meteredLimitHit) {
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

  /// Uploads one file, or marks it skipped/failed. Safe to run several of
  /// these concurrently — each resolves its own destination folder and
  /// touches only its own [task], so nothing here needs a lock.
  Future<void> _uploadOne({
    required SyncTask task,
    required DriveService drive,
    required String deviceFolder,
    required bool deleteLocal,
  }) async {
    if (_cancelled) return;
    final volume = volumeForPath(volumesProvider(), task.file.path);
    final segments = pathSegmentsUnderVolume(volume, task.file.path);
    // The volume label leads the path in Drive too, e.g.
    // "DriveSync/<device>/Local Disk (C:)/Users/me/Videos/clip.mp4" — so two
    // drives with an identically named subfolder never collide.
    final folderSegments = [volume?.label ?? 'Unknown volume', ...segments];
    task.protectedFromDeletion = isProtectedSystemPath(volume, task.file.path);

    gdrive.File? prior;
    try {
      prior = await drive.findBySourcePath(task.file.path);
    } catch (_) {
      // A lookup failure just means we upload fresh instead of updating in
      // place — not worth failing the whole task over.
    }
    final priorSize = int.tryParse(prior?.size ?? '');
    if (prior != null && priorSize == task.file.bytes) {
      // Same path, same size: already in Drive, nothing to send.
      task.state = SyncTaskState.skipped;
      _persistQueue();
      notifyListeners();
      return;
    }

    if (_cancelled) return;
    task.state = SyncTaskState.uploading;
    notifyListeners();

    try {
      final parentId = await drive.ensurePathFolder(
        deviceFolder,
        folderSegments,
      );
      if (_cancelled) throw StateError('Upload cancelled');
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
      await _cache.addHistoryEntry(
        UploadRecord(
          name: task.file.name,
          path: task.file.path,
          bytes: task.file.bytes,
          category: task.file.category,
          deviceLabel: deviceFolder,
          uploadedAt: DateTime.now(),
          driveFileId: result.fileId,
        ),
      );

      if (deleteLocal && !task.protectedFromDeletion) {
        if (settings.value.confirmBeforeDelete) {
          // Held for the UI to ask about — see pendingDeletions.
          _pendingDeletions.add(task);
        } else {
          await _files.delete(task.file.path);
          _freed += task.file.bytes;
        }
      }

      // Persist immediately rather than waiting for the whole run to end —
      // if the app is killed or crashes mid-run, whatever already finished
      // stays finished on the next launch instead of being re-checked.
      _persistQueue();
    } catch (e) {
      if (_cancelled) {
        // Stop, not a real failure: put it back exactly as it was queued so
        // the next run tries it fresh, with nothing logged against it.
        task.state = SyncTaskState.queued;
        task.uploadedBytes = 0;
        task.bytesPerSecond = 0;
      } else {
        task.state = SyncTaskState.failed;
        task.error = e.toString();
        await _cache.addHistoryEntry(
          UploadRecord(
            name: task.file.name,
            path: task.file.path,
            bytes: task.file.bytes,
            category: task.file.category,
            deviceLabel: deviceFolder,
            uploadedAt: DateTime.now(),
            succeeded: false,
          ),
        );
      }
      _persistQueue();
    }
    notifyListeners();
  }

  /// The user chose to delete this uploaded file's local copy.
  Future<void> confirmDelete(SyncTask task) async {
    try {
      await _files.delete(task.file.path);
      _freed += task.file.bytes;
    } catch (e) {
      task.error = 'Uploaded, but could not delete the local copy: $e';
    }
    _pendingDeletions.remove(task);
    notifyListeners();
  }

  /// The user chose to keep this uploaded file's local copy.
  void keepFile(SyncTask task) {
    _pendingDeletions.remove(task);
    notifyListeners();
  }

  /// Deletes several uploaded files' local copies at once — the bulk form of
  /// [confirmDelete], for a "Delete selected" action over the review list.
  Future<void> confirmDeleteMany(Iterable<SyncTask> tasks) async {
    for (final task in tasks.toList()) {
      try {
        await _files.delete(task.file.path);
        _freed += task.file.bytes;
      } catch (e) {
        task.error = 'Uploaded, but could not delete the local copy: $e';
      }
      _pendingDeletions.remove(task);
    }
    notifyListeners();
  }

  /// Keeps several uploaded files' local copies at once — the bulk form of
  /// [keepFile].
  void keepMany(Iterable<SyncTask> tasks) {
    for (final task in tasks.toList()) {
      _pendingDeletions.remove(task);
    }
    notifyListeners();
  }

  /// Puts one failed task back at the head of the queue to try again.
  void retryTask(SyncTask task) {
    if (task.state != SyncTaskState.failed) return;
    task.state = SyncTaskState.queued;
    task.error = null;
    task.uploadedBytes = 0;
    task.bytesPerSecond = 0;
    _persistQueue();
    notifyListeners();
  }

  /// Retries every currently-failed task at once.
  void retryAllFailed() {
    final failed = _tasks.where((t) => t.state == SyncTaskState.failed);
    if (failed.isEmpty) return;
    for (final task in failed) {
      task.state = SyncTaskState.queued;
      task.error = null;
      task.uploadedBytes = 0;
      task.bytesPerSecond = 0;
    }
    _persistQueue();
    notifyListeners();
  }

  /// Re-queues a file from the permanent history log — used to retry an
  /// upload that failed in a past run. If it's still sitting in the live
  /// queue (nothing dropped it via "Clear finished") this just retries that
  /// task directly, since [queue] would otherwise silently skip it as a
  /// duplicate path.
  void requeueFromHistory(UploadRecord record) {
    final existing = _tasks.where((t) => t.file.path == record.path);
    if (existing.isNotEmpty) {
      retryTask(existing.first);
      return;
    }
    queue([
      FileEntry(
        path: record.path,
        name: record.name,
        bytes: record.bytes,
        modified: record.uploadedAt,
        category: record.category,
      ),
    ]);
  }

  String _pendingSummary() {
    final n = status.pendingCount;
    return n == 0 ? 'Nothing left in the queue.' : '$n file(s) still queued.';
  }

  /// True when work is waiting only on the network.
  bool get isWaitingForNetwork => _deferred;

  /// The persistent upload log, newest first — survives "Clear finished" and
  /// app restarts, unlike the live [status] queue.
  List<UploadRecord> history() => _cache.history();

  Future<void> clearHistory() async {
    await _cache.clearHistory();
    notifyListeners();
  }

  @override
  void dispose() {
    connectivity.removeListener(_onLinkChanged);
    super.dispose();
  }

  Stream<List<int>> _countingStream(
    SyncTask task,
    Stream<List<int>> source,
  ) async* {
    var windowStart = DateTime.now();
    var windowBytes = 0;
    var lastNotify = DateTime.now();

    await for (final chunk in source) {
      // Pausing here holds the request body open mid-transfer rather than
      // only between files — the connection idles until resumed.
      if (_paused) await _pauseGate?.future;

      // Stop must interrupt an upload that's already in flight, not just
      // block the *next* one from starting — ending the stream here breaks
      // the HTTP request, which _uploadOne's catch turns back into a queued
      // task rather than a failure.
      if (_cancelled) {
        throw StateError('Upload cancelled');
      }

      task.uploadedBytes += chunk.length;
      windowBytes += chunk.length;

      if (connectivity.isMetered) {
        _meteredBytesPending += chunk.length;
        // Batch the persisted write rather than hitting SharedPreferences on
        // every chunk; the rest is flushed when the run ends.
        if (_meteredBytesPending >= 1 << 20) {
          final toFlush = _meteredBytesPending;
          _meteredBytesPending = 0;
          unawaited(_cache.addMeteredBytes(toFlush));
        }
      }

      final now = DateTime.now();
      final elapsed = now.difference(windowStart).inMilliseconds;
      if (elapsed >= 500) {
        task.bytesPerSecond = (windowBytes * 1000 / elapsed).round();
        windowStart = now;
        windowBytes = 0;
      }

      // Notify sparsely: chunk callbacks arrive far faster than frames.
      if (now.difference(lastNotify).inMilliseconds > 120) {
        lastNotify = now;
        notifyListeners();
      }
      yield chunk;
    }
    task.bytesPerSecond = 0;
  }
}
