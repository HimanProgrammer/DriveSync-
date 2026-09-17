import 'package:flutter/foundation.dart';

import '../models/sync_folder_models.dart';
import 'drive_service.dart';
import 'sync_folder_service_web.dart'
    if (dart.library.io) 'sync_folder_service_io.dart';

/// A OneDrive-style two-way mirror between one local folder and one Drive
/// folder: new or changed files copy across in whichever direction they
/// changed, and — unlike the one-way Backup feature — a delete on either side
/// deletes the other side's copy too, since that's what "in sync" means.
///
/// Windows desktop and Android. On web this is present but permanently
/// [isSupported] == false, so the rest of the app can hold a reference to it
/// unconditionally.
///
/// `implements Listenable` rather than `extends ChangeNotifier`: this is a
/// pure interface with a factory constructor, and concrete implementations
/// mix in the real `ChangeNotifier` themselves (`extends ChangeNotifier
/// implements SyncFolderService`) since a class can't both declare only a
/// factory constructor and be `extends`-ed.
abstract class SyncFolderService implements Listenable {
  factory SyncFolderService() => createSyncFolderService();

  bool get isSupported;

  bool get enabled;
  String? get localPath;

  /// A sensible starting folder to offer before the user has chosen one —
  /// e.g. `Documents\DriveSync` on Windows. Empty where there's no sane
  /// default (web).
  String get suggestedLocalPath;
  bool get isSyncing;
  DateTime? get lastSyncAt;
  String? get lastError;
  List<SyncFolderEvent> get recentEvents;

  /// Files currently believed to differ between the two sides — reset after
  /// each pass, non-empty only while `isSyncing`.
  int get pendingCount;

  void attachDrive(DriveService? drive);

  /// Turns syncing on for [localPath], creating it if it doesn't exist yet.
  /// A pass runs immediately, then on a timer and on local file-system
  /// events for as long as [enabled] stays true.
  Future<void> enable(String localPath);

  Future<void> disable();

  /// Forces an immediate pass instead of waiting for the timer or the next
  /// file-system event.
  Future<void> syncNow();

  void dispose();
}
