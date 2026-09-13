import 'local_file_source_web.dart'
    if (dart.library.io) 'local_file_source_io.dart';

/// Reads local files for upload. Split per platform because the browser has no
/// path-addressable filesystem.
abstract class LocalFileSource {
  factory LocalFileSource() => createLocalFileSource();

  bool get canReadLocalFiles;
  Future<int> lengthOf(String path);
  Stream<List<int>> openRead(String path);
  Future<void> delete(String path);
  String mimeTypeFor(String path);
}
