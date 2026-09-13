import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_file_source.dart';

LocalFileSource createLocalFileSource() => IoFileSource();

class IoFileSource implements LocalFileSource {
  static const _mimeTypes = <String, String>{
    '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
    '.gif': 'image/gif', '.webp': 'image/webp', '.heic': 'image/heic',
    '.mp4': 'video/mp4', '.mkv': 'video/x-matroska', '.mov': 'video/quicktime',
    '.webm': 'video/webm', '.avi': 'video/x-msvideo',
    '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.flac': 'audio/flac',
    '.m4a': 'audio/mp4', '.aac': 'audio/aac',
    '.pdf': 'application/pdf', '.txt': 'text/plain', '.md': 'text/markdown',
    '.csv': 'text/csv', '.json': 'application/json',
    '.zip': 'application/zip', '.rar': 'application/vnd.rar',
    '.7z': 'application/x-7z-compressed', '.tar': 'application/x-tar',
    '.gz': 'application/gzip', '.iso': 'application/x-iso9660-image',
    '.apk': 'application/vnd.android.package-archive',
    '.exe': 'application/vnd.microsoft.portable-executable',
  };

  @override
  bool get canReadLocalFiles => true;

  @override
  Future<int> lengthOf(String path) => File(path).length();

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();

  @override
  Future<void> delete(String path) => File(path).delete();

  @override
  String mimeTypeFor(String path) =>
      _mimeTypes[p.extension(path).toLowerCase()] ?? 'application/octet-stream';
}
