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

  /// Rolling transfer rate, recomputed roughly twice a second while
  /// uploading; zero once the file finishes, fails, or pauses.
  int bytesPerSecond = 0;

  double get progress =>
      file.bytes == 0 ? 0 : (uploadedBytes / file.bytes).clamp(0.0, 1.0);

  /// e.g. "12.4 MB/s", or null when there's no rate to show.
  String? get speedLabel =>
      bytesPerSecond <= 0 ? null : '${formatBytes(bytesPerSecond)}/s';

  /// Rough time remaining at the current rate; null when unknown.
  Duration? get eta {
    if (bytesPerSecond <= 0) return null;
    final remaining = file.bytes - uploadedBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / bytesPerSecond).ceil());
  }

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

/// One completed (or failed) upload, kept after the live queue is cleared so
/// "what did I already send to Drive" survives across sessions.
class UploadRecord {
  const UploadRecord({
    required this.name,
    required this.path,
    required this.bytes,
    required this.category,
    required this.deviceLabel,
    required this.uploadedAt,
    this.driveFileId,
    this.succeeded = true,
  });

  final String name;
  final String path;
  final int bytes;
  final FileCategory category;

  /// Which device's DriveSync folder this went into.
  final String deviceLabel;
  final DateTime uploadedAt;

  /// Null for a failed attempt.
  final String? driveFileId;
  final bool succeeded;

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'bytes': bytes,
        'category': category.name,
        'deviceLabel': deviceLabel,
        'uploadedAt': uploadedAt.toIso8601String(),
        'driveFileId': driveFileId,
        'succeeded': succeeded,
      };

  factory UploadRecord.fromJson(Map<String, dynamic> m) => UploadRecord(
        name: m['name'] as String,
        path: m['path'] as String,
        bytes: (m['bytes'] as num).toInt(),
        category: FileCategory.values.firstWhere(
          (c) => c.name == m['category'],
          orElse: () => FileCategory.other,
        ),
        deviceLabel: m['deviceLabel'] as String? ?? 'This device',
        uploadedAt: DateTime.tryParse(m['uploadedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        driveFileId: m['driveFileId'] as String?,
        succeeded: m['succeeded'] as bool? ?? true,
      );
}
