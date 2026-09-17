import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' show AuthClient;

import '../config.dart';
import '../models/storage_models.dart';

/// Drive quota for the signed-in account.
class DriveQuota {
  const DriveQuota({
    required this.limit,
    required this.usage,
    required this.driveUsage,
  });
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
  const DriveUploadResult({
    required this.fileId,
    required this.name,
    required this.bytes,
  });
  final String fileId;
  final String name;
  final int bytes;
}

/// One file as it actually exists in Drive right now — read straight from the
/// API, not from anything cached locally.
class DriveFileInfo {
  const DriveFileInfo({
    required this.id,
    required this.name,
    required this.bytes,
    required this.modifiedTime,
    required this.deviceFolder,
    this.webViewLink,
    this.iconLink,
  });

  final String id;
  final String name;
  final int bytes;
  final DateTime modifiedTime;

  /// Which `DriveSync/<device>` subfolder this file is in.
  final String deviceFolder;
  final String? webViewLink;
  final String? iconLink;
}

/// Everything DriveSync does against the Drive v3 API.
class DriveService {
  DriveService(AuthClient client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;

  // Futures, not resolved ids: with several files uploading at once, two
  // workers can ask for the same not-yet-created folder in the same tick.
  // Caching the in-flight Future (rather than only the eventual id) means the
  // second caller awaits the first's creation instead of racing it and
  // creating a duplicate folder of the same name.
  final Map<String, Future<String>> _folderCache = {};

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

  /// Finds or creates `DriveSync/<deviceFolder>/<segments[0]>/<segments[1]>/…`
  /// and returns the innermost folder's id — used to mirror a file's local
  /// folder structure inside Drive rather than flattening every upload into
  /// one folder.
  Future<String> ensurePathFolder(
    String deviceFolder,
    List<String> segments,
  ) async {
    var parent = await ensureDeviceFolder(deviceFolder);
    for (final segment in segments) {
      if (segment.trim().isEmpty) continue;
      parent = await _ensureFolder(segment, parent);
    }
    return parent;
  }

  Future<String> _ensureFolder(String name, String? parentId) {
    final key = '${parentId ?? 'root'}/$name';
    return _folderCache[key] ??= _createOrFindFolder(name, parentId);
  }

  Future<String> _createOrFindFolder(String name, String? parentId) async {
    final escaped = name.replaceAll(r"\", r"\\").replaceAll("'", r"\'");
    final q = [
      "mimeType = 'application/vnd.google-apps.folder'",
      "name = '$escaped'",
      'trashed = false',
      "'${parentId ?? 'root'}' in parents",
    ].join(' and ');

    final found = await _api.files.list(
      q: q,
      $fields: 'files(id,name)',
      pageSize: 1,
    );
    final existing = found.files?.isNotEmpty == true
        ? found.files!.first.id
        : null;
    if (existing != null) return existing;

    final created = await _api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId ?? 'root'],
      $fields: 'id',
    );
    return created.id!;
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

  /// The file DriveSync previously uploaded from [sourcePath], anywhere in
  /// Drive — not limited to one folder, since a file's Drive location now
  /// mirrors its local folder structure rather than sitting in one flat
  /// bucket. Used to skip re-uploads and to resolve replacements.
  Future<drive.File?> findBySourcePath(String sourcePath) async {
    final escaped = sourcePath.replaceAll(r"\", r"\\").replaceAll("'", r"\'");
    final found = await _api.files.list(
      q:
          "appProperties has { key='dvSourcePath' and value='$escaped' } "
          'and trashed = false',
      $fields: 'files(id,name,size,modifiedTime)',
      pageSize: 1,
    );
    return found.files?.isNotEmpty == true ? found.files!.first : null;
  }

  Future<void> delete(String fileId) => _api.files.delete(fileId);

  /// Every file DriveSync has ever put in Drive, across every device that has
  /// backed up to this account — read live from the API, newest first. Not
  /// cached: this reflects Drive's actual current state, including files
  /// deleted or renamed from the Drive web UI since the last local sync.
  Future<List<DriveFileInfo>> listAllUploads() async {
    final rootQuery = [
      "mimeType = 'application/vnd.google-apps.folder'",
      "name = '${DriveConfig.rootFolderName}'",
      'trashed = false',
      "'root' in parents",
    ].join(' and ');
    final rootResult = await _api.files.list(
      q: rootQuery,
      $fields: 'files(id)',
      pageSize: 1,
    );
    final rootId = rootResult.files?.isNotEmpty == true
        ? rootResult.files!.first.id
        : null;
    if (rootId == null) return const [];

    final deviceFolders = await _api.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false "
          "and '$rootId' in parents",
      $fields: 'files(id,name)',
      pageSize: 100,
    );

    final out = <DriveFileInfo>[];
    for (final folder in deviceFolders.files ?? const <drive.File>[]) {
      final deviceName = folder.name ?? 'Unknown device';
      String? pageToken;
      do {
        final page = await _api.files.list(
          q:
              "'${folder.id}' in parents and trashed = false and "
              "mimeType != 'application/vnd.google-apps.folder'",
          $fields:
              'nextPageToken,files(id,name,size,modifiedTime,webViewLink,iconLink)',
          pageSize: 200,
          pageToken: pageToken,
          orderBy: 'modifiedTime desc',
        );
        for (final f in page.files ?? const <drive.File>[]) {
          out.add(
            DriveFileInfo(
              id: f.id!,
              name: f.name ?? '(unnamed)',
              bytes: int.tryParse(f.size ?? '') ?? 0,
              modifiedTime:
                  f.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0),
              deviceFolder: deviceName,
              webViewLink: f.webViewLink,
              iconLink: f.iconLink,
            ),
          );
        }
        pageToken = page.nextPageToken;
      } while (pageToken != null);
    }
    out.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return out;
  }
}
