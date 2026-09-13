import 'storage_models.dart';

enum SyncTaskState { queued, uploading, done, skipped, failed }

class SyncTask {
  SyncTask({
    required this.file,
    this.state = SyncTaskState.queued,
    this.uploadedBytes = 0,
    this.driveFileId,
    this.error,
  });

  final FileEntry file;
  SyncTaskState state;
  int uploadedBytes;
  String? driveFileId;
  String? error;

  double get progress =>
      file.bytes == 0 ? 0 : (uploadedBytes / file.bytes).clamp(0.0, 1.0);

  bool get isFinished =>
      state == SyncTaskState.done ||
      state == SyncTaskState.skipped ||
      state == SyncTaskState.failed;
}

/// A snapshot of the sync engine, rebuilt on every notify.
class SyncStatus {
  const SyncStatus({
    required this.tasks,
    required this.running,
    required this.uploadedBytes,
    required this.freedBytes,
    this.lastRun,
    this.message,
  });

  final List<SyncTask> tasks;
  final bool running;
  final int uploadedBytes;

  /// Bytes reclaimed locally — non-zero only when "delete local copy" is on.
  final int freedBytes;
  final DateTime? lastRun;
  final String? message;

  int get doneCount => tasks.where((t) => t.state == SyncTaskState.done).length;
  int get failedCount =>
      tasks.where((t) => t.state == SyncTaskState.failed).length;
  int get pendingCount => tasks.where((t) => !t.isFinished).length;
  int get totalBytes => tasks.fold(0, (a, t) => a + t.file.bytes);

  static const idle = SyncStatus(
    tasks: [],
    running: false,
    uploadedBytes: 0,
    freedBytes: 0,
  );
}
