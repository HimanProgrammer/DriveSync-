import '../models/storage_models.dart';
import 'storage_service_web.dart'
    if (dart.library.io) 'storage_service_io.dart';

/// Incremental progress so the dashboard can animate while a big disk walks.
class ScanProgress {
  const ScanProgress({
    required this.filesSeen,
    required this.bytesSeen,
    required this.currentPath,
    this.result,
  });

  final int filesSeen;
  final int bytesSeen;
  final String currentPath;

  /// Non-null only on the final event.
  final ScanResult? result;

  bool get isDone => result != null;
}

abstract class StorageService {
  /// The concrete implementation for the platform we were compiled for.
  factory StorageService() => createStorageService();

  /// Mounted volumes with their total/free capacity.
  Future<List<VolumeInfo>> listVolumes();

  /// Walk [volume] and classify what is on it. Emits progress, ends with a
  /// [ScanProgress] carrying the [ScanResult].
  Stream<ScanProgress> scan(
    VolumeInfo volume, {
    Duration budget = const Duration(seconds: 45),
    int maxLargestFiles = 50,
  });

  /// Camera-roll style media added since [since], newest first. Powers Auto
  /// Mobile Backup; empty on platforms with no media roots we can read.
  Future<List<FileEntry>> newMediaSince(DateTime? since, {int limit = 200});

  /// A stable, human-readable name for this device. Becomes the Drive
  /// subfolder so each machine keeps its own backup tree.
  Future<String> deviceLabel();

  /// Roots the platform lets us read without extra grants. Used as the scan
  /// seed on Android, where walking `/` is pointless.
  Future<List<String>> readableRoots(VolumeInfo volume);
}
