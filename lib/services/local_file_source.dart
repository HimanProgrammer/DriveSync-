import 'local_file_source_web.dart'
    if (dart.library.io) 'local_file_source_io.dart';

/// Reads local files for upload. Split per platform because the browser has no
/// path-addressable filesystem.
abstract class LocalFileSource {
  factory LocalFileSource() => createLocalFileSource();

  bool get canReadLocalFiles;

  /// False on Android: a phone's storage holds the user's only copy of their
  /// photos and documents, so DriveSync backs it up but never deletes
  /// anything there — the "check uploaded, then delete" setting in Settings
  /// simply has no effect on mobile, regardless of its value.
  bool get canDeleteLocalFiles;

  Future<int> lengthOf(String path);
  Stream<List<int>> openRead(String path);
  Future<void> delete(String path);
  String mimeTypeFor(String path);
}
