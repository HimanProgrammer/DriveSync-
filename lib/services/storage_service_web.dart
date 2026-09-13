import '../models/storage_models.dart';
import 'storage_service.dart';

StorageService createStorageService() => WebStorageService();

/// The browser has no filesystem to walk. We report the origin's storage
/// quota instead, and the web dashboard drives the *desktop* and *phone*
/// numbers that those clients push up to Drive.
class WebStorageService implements StorageService {
  @override
  Future<List<VolumeInfo>> listVolumes() async {
    // navigator.storage.estimate() would refine this; the quota is advisory
    // and browser-specific, so we present it as a single synthetic volume.
    return const [
      VolumeInfo(
        id: 'browser',
        label: 'Browser storage (this origin)',
        path: '/',
        totalBytes: 0,
        freeBytes: 0,
        isPrimary: true,
      ),
    ];
  }

  @override
  Future<List<FileEntry>> newMediaSince(DateTime? since, {int limit = 200}) async =>
      const [];

  @override
  Future<String> deviceLabel() async => 'Web dashboard';

  @override
  Future<List<String>> readableRoots(VolumeInfo volume) async => const [];

  @override
  Stream<ScanProgress> scan(
    VolumeInfo volume, {
    Duration budget = const Duration(seconds: 45),
    int maxLargestFiles = 50,
  }) async* {
    yield ScanProgress(
      filesSeen: 0,
      bytesSeen: 0,
      currentPath: '',
      result: ScanResult(
        volume: volume,
        categories: const [],
        largestFiles: const [],
        scannedFiles: 0,
        scannedBytes: 0,
        duration: Duration.zero,
        partial: true,
        skippedPaths: const [
          'Browsers cannot enumerate the local disk. Open DriveSync on '
              'Windows or Android to scan real volumes; this dashboard shows '
              'what those devices reported.',
        ],
      ),
    );
  }
}
