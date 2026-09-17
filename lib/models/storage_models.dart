import 'dart:math' as math;

/// A mounted volume: a Windows drive letter, an Android storage volume,
/// or the single synthetic "browser" volume on web.
class VolumeInfo {
  const VolumeInfo({
    required this.id,
    required this.label,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    this.isRemovable = false,
    this.isPrimary = false,
  });

  final String id;
  final String label;
  final String path;
  final int totalBytes;
  final int freeBytes;
  final bool isRemovable;
  final bool isPrimary;

  int get usedBytes => math.max(0, totalBytes - freeBytes);
  double get usedFraction => totalBytes == 0 ? 0 : usedBytes / totalBytes;

  /// Volumes above this are what triggers an auto-offload suggestion.
  bool get isCritical => usedFraction >= 0.90;
  bool get isWarning => usedFraction >= 0.75;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'path': path,
    'totalBytes': totalBytes,
    'freeBytes': freeBytes,
    'isRemovable': isRemovable,
    'isPrimary': isPrimary,
  };

  factory VolumeInfo.fromMap(Map<dynamic, dynamic> m) => VolumeInfo(
    id: m['id'] as String,
    label: (m['label'] as String?)?.trim().isNotEmpty == true
        ? m['label'] as String
        : m['id'] as String,
    path: m['path'] as String,
    totalBytes: (m['totalBytes'] as num).toInt(),
    freeBytes: (m['freeBytes'] as num).toInt(),
    isRemovable: m['isRemovable'] as bool? ?? false,
    isPrimary: m['isPrimary'] as bool? ?? false,
  );
}

/// One row in the "what is eating my disk" breakdown.
class CategoryUsage {
  CategoryUsage(this.category, this.bytes, this.fileCount);

  final FileCategory category;
  int bytes;
  int fileCount;
}

enum FileCategory {
  images('Images', [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.bmp',
    '.tiff',
    '.svg',
  ]),
  videos('Videos', [
    '.mp4',
    '.mkv',
    '.mov',
    '.avi',
    '.webm',
    '.flv',
    '.wmv',
    '.m4v',
  ]),
  audio('Audio', ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.opus']),
  documents('Documents', [
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.txt',
    '.md',
    '.csv',
    '.odt',
  ]),
  archives('Archives', [
    '.zip',
    '.rar',
    '.7z',
    '.tar',
    '.gz',
    '.bz2',
    '.xz',
    '.iso',
  ]),
  code('Code', [
    '.dart',
    '.js',
    '.ts',
    '.py',
    '.java',
    '.kt',
    '.c',
    '.cpp',
    '.h',
    '.cs',
    '.go',
    '.rs',
    '.html',
    '.css',
    '.json',
    '.yaml',
    '.yml',
  ]),
  apps('Apps & Installers', [
    '.exe',
    '.msi',
    '.apk',
    '.dmg',
    '.deb',
    '.rpm',
    '.appx',
  ]),
  other('Other', <String>[]);

  const FileCategory(this.label, this.extensions);
  final String label;
  final List<String> extensions;

  static FileCategory forExtension(String ext) {
    final e = ext.toLowerCase();
    for (final c in FileCategory.values) {
      if (c.extensions.contains(e)) return c;
    }
    return FileCategory.other;
  }
}

/// A large file candidate for offloading to Drive.
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modified,
    required this.category,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime modified;
  final FileCategory category;

  int get ageInDays => DateTime.now().difference(modified).inDays;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'bytes': bytes,
    'modified': modified.toIso8601String(),
    'category': category.name,
  };

  factory FileEntry.fromJson(Map<String, dynamic> m) => FileEntry(
    path: m['path'] as String,
    name: m['name'] as String,
    bytes: (m['bytes'] as num).toInt(),
    modified: DateTime.parse(m['modified'] as String),
    category: FileCategory.values.firstWhere(
      (c) => c.name == m['category'],
      orElse: () => FileCategory.other,
    ),
  );
}

/// Result of a full analysis pass over one volume.
class ScanResult {
  ScanResult({
    required this.volume,
    required this.categories,
    required this.largestFiles,
    required this.scannedFiles,
    required this.scannedBytes,
    required this.duration,
    this.partial = false,
    this.skippedPaths = const <String>[],
    DateTime? takenAt,
  }) : takenAt = takenAt ?? DateTime.now();

  final VolumeInfo volume;
  final List<CategoryUsage> categories;
  final List<FileEntry> largestFiles;
  final int scannedFiles;
  final int scannedBytes;
  final Duration duration;

  /// True when the walk was cut short (permission walls, depth/time budget).
  final bool partial;
  final List<String> skippedPaths;

  /// When this snapshot was taken. Offline views surface it so a stale
  /// breakdown is never mistaken for a live one.
  final DateTime takenAt;

  Map<String, dynamic> toJson() => {
    'volume': volume.toJson(),
    'categories': [
      for (final c in categories)
        {'category': c.category.name, 'bytes': c.bytes, 'files': c.fileCount},
    ],
    'largestFiles': [for (final f in largestFiles) f.toJson()],
    'scannedFiles': scannedFiles,
    'scannedBytes': scannedBytes,
    'durationMs': duration.inMilliseconds,
    'partial': partial,
    'skippedPaths': skippedPaths,
    'takenAt': takenAt.toIso8601String(),
  };

  factory ScanResult.fromJson(Map<String, dynamic> m) => ScanResult(
    volume: VolumeInfo.fromMap(m['volume'] as Map<dynamic, dynamic>),
    categories: [
      for (final c in (m['categories'] as List).cast<Map<String, dynamic>>())
        CategoryUsage(
          FileCategory.values.firstWhere(
            (v) => v.name == c['category'],
            orElse: () => FileCategory.other,
          ),
          (c['bytes'] as num).toInt(),
          (c['files'] as num).toInt(),
        ),
    ],
    largestFiles: [
      for (final f in (m['largestFiles'] as List).cast<Map<String, dynamic>>())
        FileEntry.fromJson(f),
    ],
    scannedFiles: (m['scannedFiles'] as num).toInt(),
    scannedBytes: (m['scannedBytes'] as num).toInt(),
    duration: Duration(milliseconds: (m['durationMs'] as num).toInt()),
    partial: m['partial'] as bool? ?? false,
    skippedPaths: (m['skippedPaths'] as List?)?.cast<String>() ?? const [],
    takenAt: DateTime.tryParse(m['takenAt'] as String? ?? ''),
  );
}

/// Finds the volume a path belongs to, by longest matching path prefix — so a
/// nested mount point wins over its parent. Null when nothing matches (the
/// volume may have been unplugged, or this is a cached task from another run).
VolumeInfo? volumeForPath(Iterable<VolumeInfo> volumes, String path) {
  VolumeInfo? best;
  for (final v in volumes) {
    if (v.path.isNotEmpty &&
        path.toLowerCase().startsWith(v.path.toLowerCase()) &&
        (best == null || v.path.length > best.path.length)) {
      best = v;
    }
  }
  return best;
}

/// The folder segments a path sits in below its volume root, e.g. for
/// `C:\Users\me\Videos\clip.mp4` on a volume rooted at `C:\`, this is
/// `[Users, me, Videos]` — everything except the volume root and the
/// filename itself.
List<String> pathSegmentsUnderVolume(VolumeInfo? volume, String path) {
  var relative = path;
  if (volume != null &&
      relative.toLowerCase().startsWith(volume.path.toLowerCase())) {
    relative = relative.substring(volume.path.length);
  }
  final parts = relative
      .split(RegExp(r'[\\/]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isNotEmpty) parts.removeLast(); // drop the filename
  return parts;
}

String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final i = (math.log(bytes) / math.log(1024)).floor().clamp(
    0,
    units.length - 1,
  );
  final value = bytes / math.pow(1024, i);
  return '${value.toStringAsFixed(i == 0 ? 0 : decimals)} ${units[i]}';
}
