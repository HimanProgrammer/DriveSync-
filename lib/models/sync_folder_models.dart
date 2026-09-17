/// One file's bookkeeping inside the two-way Sync Folder — what DriveSync
/// last knew about it on both sides, so a poll can tell "changed" from
/// "unchanged" and "deleted" from "never existed".
class SyncFileRecord {
  const SyncFileRecord({
    required this.relativePath,
    this.localModifiedMs,
    this.localSize,
    this.remoteId,
    this.remoteModifiedMs,
    this.remoteSize,
  });

  /// Path relative to the sync folder root, forward-slash separated so it's
  /// stable across platforms.
  final String relativePath;

  final int? localModifiedMs;
  final int? localSize;

  final String? remoteId;
  final int? remoteModifiedMs;
  final int? remoteSize;

  bool get existsLocally => localModifiedMs != null;
  bool get existsRemotely => remoteId != null;

  SyncFileRecord copyWith({
    Object? localModifiedMs = _sentinel,
    Object? localSize = _sentinel,
    Object? remoteId = _sentinel,
    Object? remoteModifiedMs = _sentinel,
    Object? remoteSize = _sentinel,
  }) => SyncFileRecord(
    relativePath: relativePath,
    localModifiedMs: localModifiedMs == _sentinel
        ? this.localModifiedMs
        : localModifiedMs as int?,
    localSize: localSize == _sentinel ? this.localSize : localSize as int?,
    remoteId: remoteId == _sentinel ? this.remoteId : remoteId as String?,
    remoteModifiedMs: remoteModifiedMs == _sentinel
        ? this.remoteModifiedMs
        : remoteModifiedMs as int?,
    remoteSize: remoteSize == _sentinel ? this.remoteSize : remoteSize as int?,
  );

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'localModifiedMs': localModifiedMs,
    'localSize': localSize,
    'remoteId': remoteId,
    'remoteModifiedMs': remoteModifiedMs,
    'remoteSize': remoteSize,
  };

  factory SyncFileRecord.fromJson(Map<String, dynamic> m) => SyncFileRecord(
    relativePath: m['relativePath'] as String,
    localModifiedMs: (m['localModifiedMs'] as num?)?.toInt(),
    localSize: (m['localSize'] as num?)?.toInt(),
    remoteId: m['remoteId'] as String?,
    remoteModifiedMs: (m['remoteModifiedMs'] as num?)?.toInt(),
    remoteSize: (m['remoteSize'] as num?)?.toInt(),
  );
}

const _sentinel = Object();

enum SyncFolderAction {
  uploadNew,
  uploadChanged,
  downloadNew,
  downloadChanged,
  deleteLocal,
  deleteRemote,
  conflictKeepBoth,
  unchanged,
}

/// One planned or completed step of a sync pass — surfaced in the UI as an
/// activity log entry.
class SyncFolderEvent {
  SyncFolderEvent({
    required this.relativePath,
    required this.action,
    DateTime? at,
    this.error,
  }) : at = at ?? DateTime.now();

  final String relativePath;
  final SyncFolderAction action;
  final DateTime at;
  final String? error;

  bool get failed => error != null;

  String get label => switch (action) {
    SyncFolderAction.uploadNew => 'Uploaded (new)',
    SyncFolderAction.uploadChanged => 'Uploaded (changed)',
    SyncFolderAction.downloadNew => 'Downloaded (new)',
    SyncFolderAction.downloadChanged => 'Downloaded (changed)',
    SyncFolderAction.deleteLocal => 'Removed locally (deleted in Drive)',
    SyncFolderAction.deleteRemote => 'Removed from Drive (deleted locally)',
    SyncFolderAction.conflictKeepBoth => 'Kept both — changed on both sides',
    SyncFolderAction.unchanged => 'Unchanged',
  };
}
