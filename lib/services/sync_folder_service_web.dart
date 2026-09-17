import 'package:flutter/foundation.dart';

import '../models/sync_folder_models.dart';
import 'drive_service.dart';
import 'sync_folder_service.dart';

SyncFolderService createSyncFolderService() => WebSyncFolderService();

class WebSyncFolderService extends ChangeNotifier implements SyncFolderService {
  @override
  bool get isSupported => false;

  @override
  bool get enabled => false;

  @override
  String? get localPath => null;

  @override
  String get suggestedLocalPath => '';

  @override
  bool get isSyncing => false;

  @override
  DateTime? get lastSyncAt => null;

  @override
  String? get lastError => null;

  @override
  List<SyncFolderEvent> get recentEvents => const [];

  @override
  int get pendingCount => 0;

  @override
  void attachDrive(DriveService? drive) {}

  @override
  Future<void> enable(String localPath) async {
    throw UnsupportedError(
      'Sync Folder is only available on Windows desktop and Android.',
    );
  }

  @override
  Future<void> disable() async {}

  @override
  Future<void> syncNow() async {}
}
