import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' show AuthClient;

import '../config.dart';
import '../models/storage_models.dart';

/// Drive quota for the signed-in account.
class DriveQuota {
  const DriveQuota({required this.limit, required this.usage, required this.driveUsage});
  final int limit;
  final int usage;
  final int driveUsage;

  /// Consumer accounts report a limit; some Workspace accounts are unlimited
  /// and omit it, in which case a percentage is meaningless.
  bool get isUnlimited => limit <= 0;
  double get usedFraction => isUnlimited ? 0 : (usage / limit).clamp(0, 1);
  int get freeBytes => isUnlimited ? 0 : (limit - usage).clamp(0, limit);

  String get summary => isUnlimited
      ? '${formatBytes(usage)} used (no quota limit reported)'
      : '${formatBytes(usage)} of ${formatBytes(limit)} used';
}

class DriveUploadResult {
  const DriveUploadResult({required this.fileId, required this.name, required this.bytes});
  final String fileId;
  final String name;
  final int bytes;
}

/// Everything DriveSync does against the Drive v3 API.
class DriveService {
  DriveService(AuthClient client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;
  final Map<String, String> _folderCache = {};

  Future<DriveQuota> quota() async {
    final about = await _api.about.get($fields: 'storageQuota');
    final q = about.storageQuota;
    return DriveQuota(
      limit: int.tryParse(q?.limit ?? '') ?? 0,
      usage: int.tryParse(q?.usage ?? '') ?? 0,
      driveUsage: int.tryParse(q?.usageInDrive ?? '') ?? 0,
    );
  }

  /// Finds or creates `DriveSync/<deviceFolder>` and returns its id.
  Future<String> ensureDeviceFolder(String deviceFolder) async {
    final root = await _ensureFolder(DriveConfig.rootFolderName, null);
    return _ensureFolder(deviceFolder, root);
  }

  Future<String> _ensureFolder(String name, String? parentId) async {
    final key = '${parentId ?? 'root'}/$name';
    final cached = _folderCache[key];
    if (cached != null) return cached;

    final escaped = name.replaceAll(r"\", r"\\").replaceAll("'", r"\'");
    final q = [
      "mimeType = 'application/vnd.google-apps.folder'",
      "name = '$escaped'",
      'trashed = false',
      "'${parentId ?? 'root'}' in parents",
    ].join(' and ');

    final found = await _api.files.list(q: q, $fields: 'files(id,name)', pageSize: 1);
    final existing = found.files?.isNotEmpty == true ? found.files!.first.id : null;
    if (existing != null) return _folderCache[key] = existing;

    final created = await _api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId ?? 'root'],
      $fields: 'id',
    );
    return _folderCache[key] = created.id!;
  }

  /// Uploads (or, when [existingFileId] is given, replaces) one file.
  Future<DriveUploadResult> upload({
    required String name,
    required int length,
    required Stream<List<int>> content,
    required String parentId,
    String mimeType = 'application/octet-stream',
    String? existingFileId,
    Map<String, String>? appProperties,
  }) async {
    final media = drive.Media(content, length, contentType: mimeType);
    final metadata = drive.File()
      ..name = name
      ..appProperties = appProperties;

    final drive.File result;
    if (existingFileId != null) {
      result = await _api.files.update(
        metadata,
        existingFileId,
        uploadMedia: media,
        $fields: 'id,name,size',
      );
    } else {
      result = await _api.files.create(
        metadata..parents = [parentId],
        uploadMedia: media,
        $fields: 'id,name,size',
      );
    }
    return DriveUploadResult(
      fileId: result.id!,
      name: result.name ?? name,
      bytes: int.tryParse(result.size ?? '') ?? length,
    );
  }

  /// Files DriveSync already put in [parentId], keyed by the original local
  /// path we stored in appProperties. Used to skip re-uploads and to resolve
  /// replacements.
  Future<Map<String, drive.File>> indexOf(String parentId) async {
    final index = <String, drive.File>{};
    String? pageToken;
    do {
      final page = await _api.files.list(
        q: "'$parentId' in parents and trashed = false",
        $fields: 'nextPageToken,files(id,name,size,modifiedTime,appProperties)',
        pageSize: 200,
        pageToken: pageToken,
      );
      for (final f in page.files ?? const <drive.File>[]) {
        final key = f.appProperties?['dvSourcePath'] ?? f.name;
        if (key != null) index[key] = f;
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return index;
  }

  Future<void> delete(String fileId) => _api.files.delete(fileId);
}
