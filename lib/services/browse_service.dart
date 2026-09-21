import '../models/storage_models.dart';
import 'browse_service_web.dart' if (dart.library.io) 'browse_service_io.dart';

/// One item in a folder listing — a sub-folder or a file.
class BrowseEntry {
  const BrowseEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.bytes = 0,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDir;
  final int bytes;
  final DateTime? modified;
}

class BrowseException implements Exception {
  BrowseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads folders straight off the disk so the Browse tab can show them like a
/// file manager. Desktop and Android only — a browser has no filesystem.
abstract class BrowseService {
  factory BrowseService() => createBrowseService();

  bool get available;

  /// Folders first, then files, each A–Z. Throws [BrowseException] when the
  /// folder cannot be opened (permissions, unplugged drive).
  Future<List<BrowseEntry>> list(String path);

  /// Every file under the given entries — files as themselves, folders
  /// expanded recursively — ready to queue for backup.
  Future<List<FileEntry>> collectFiles(Iterable<BrowseEntry> entries);
}
