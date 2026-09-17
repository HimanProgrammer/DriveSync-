import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/sim_models.dart';
import 'models/storage_models.dart';
import 'services/connectivity_service.dart';
import 'services/drive_auth.dart';
import 'services/drive_service.dart';
import 'services/local_file_source.dart';
import 'services/media_backup_service.dart';
import 'services/native_bridge.dart';
import 'services/offline_cache.dart';
import 'services/power_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/sync_engine.dart';
import 'services/sync_folder_service.dart';

/// One controller for the whole app: volumes, scans, Drive connection, carrier
/// check, offline cache and the sync engine. The dashboard is a view over this.
class AppState extends ChangeNotifier {
  AppState({
    required this.settings,
    required OfflineCache cache,
    StorageService? storage,
    DriveAuth? auth,
    LocalFileSource? files,
    ConnectivityService? connectivity,
    PowerService? power,
    SyncFolderService? syncFolder,
  }) : _cache = cache,
       _storage = storage ?? StorageService(),
       _auth = auth ?? DriveAuth(),
       link = connectivity ?? ConnectivityService(),
       power = power ?? PowerService(),
       syncFolder = syncFolder ?? SyncFolderService() {
    sync = SyncEngine(
      files: files ?? LocalFileSource(),
      settings: settings,
      connectivity: link,
      cache: cache,
      volumesProvider: () => volumes,
    );
    media = MediaBackupService(
      storage: _storage,
      settings: settings,
      cache: cache,
      connectivity: link,
      onNewMedia: _handleNewMedia,
    );

    // Offline-first: show the last known numbers immediately, before any scan.
    scans.addAll(cache.scans());
    final cachedQuota = cache.quota();
    if (cachedQuota != null) {
      quota = DriveQuota(
        limit: (cachedQuota['limit'] as num?)?.toInt() ?? 0,
        usage: (cachedQuota['usage'] as num?)?.toInt() ?? 0,
        driveUsage: (cachedQuota['driveUsage'] as num?)?.toInt() ?? 0,
      );
      quotaAsOf = DateTime.tryParse(cachedQuota['at'] as String? ?? '');
    }

    sync.addListener(notifyListeners);
    media.addListener(notifyListeners);
    settings.addListener(_onSettingsChanged);
    link.addListener(notifyListeners);
    this.syncFolder.addListener(notifyListeners);
  }

  final SettingsService settings;
  final OfflineCache _cache;
  final StorageService _storage;
  final DriveAuth _auth;
  final ConnectivityService link;
  final PowerService power;
  final SyncFolderService syncFolder;
  late final SyncEngine sync;
  late final MediaBackupService media;

  List<VolumeInfo> volumes = const [];
  VolumeInfo? selected;
  final Map<String, ScanResult> scans = {};
  ScanProgress? progress;
  StreamSubscription<ScanProgress>? _scanSub;

  DriveService? drive;
  DriveQuota? quota;

  /// When [quota] was read. Non-null and old means we are showing cached data.
  DateTime? quotaAsOf;
  DriveAccount? get account => _auth.account;
  bool get isConnected => drive != null;
  bool get isOffline => link.isOffline;

  CarrierOffer carrier = const CarrierOffer(sims: [], checked: false);
  String deviceLabel = 'This device';

  bool busy = true;
  String? error;

  /// The Auto-mode popup is shown once, before anything is uploaded.
  bool get needsAutoModePrompt => !settings.value.autoPromptShown;

  ScanResult? get currentScan => selected == null ? null : scans[selected!.id];

  Future<void> init() async {
    busy = true;
    notifyListeners();
    try {
      await link.start();
      deviceLabel = await _storage.deviceLabel();
      volumes = await _storage.listVolumes();
      selected =
          volumes.where((v) => v.isPrimary).firstOrNull ??
          (volumes.isEmpty ? null : volumes.first);
      await refreshCarrier();
      await _restoreDriveSession();
      if (settings.value.autoMobileBackup) media.start();
    } catch (e) {
      error = 'Startup failed: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onSettingsChanged() {
    // Keep the media sweeper in step with its toggle.
    if (settings.value.autoMobileBackup) {
      media.start();
    } else {
      media.stop();
    }
    notifyListeners();
  }

  /// Auto Mobile Backup found new camera-roll items: queue them, and upload now
  /// if the mode and the link both allow it.
  Future<void> _handleNewMedia(List<FileEntry> newMedia) async {
    sync.queue(newMedia);
    if (settings.value.isAuto && isConnected) {
      await backupNow();
    }
  }

  Future<void> refreshVolumes() async {
    volumes = await _storage.listVolumes();
    if (selected != null) {
      selected =
          volumes.where((v) => v.id == selected!.id).firstOrNull ??
          (volumes.isEmpty ? null : volumes.first);
    }
    notifyListeners();
  }

  Future<void> refreshCarrier() async {
    carrier = await NativeBridge.instance.carrierOffer();
    if (!carrier.checked) {
      // On Android an unchecked result usually means READ_PHONE_STATE has not
      // been granted yet; ask once, then re-read.
      if (await NativeBridge.instance.requestPhonePermission()) {
        carrier = await NativeBridge.instance.carrierOffer();
      }
    }
    notifyListeners();
  }

  void selectVolume(VolumeInfo volume) {
    selected = volume;
    progress = null;
    notifyListeners();
  }

  Future<void> _restoreDriveSession() async {
    if (link.isOffline) {
      // Nothing to gain from an auth round trip with no link; the cached
      // quota and scans already render, and we retry on the next launch.
      return;
    }
    try {
      final client = await _auth.signInSilently();
      if (client != null) await _useClient(client);
    } catch (e) {
      debugPrint('DriveSync: silent sign-in skipped: $e');
    }
  }

  Future<void> connectDrive() async {
    error = null;
    if (link.isOffline) {
      error = 'You are offline. Connect to a network to sign in to Drive.';
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final client = await _auth.signIn();
      if (client == null) {
        error = 'Sign-in was cancelled.';
      } else {
        await _useClient(client);
      }
    } on DriveAuthException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not connect to Google Drive: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _useClient(dynamic client) async {
    final service = DriveService(client);
    drive = service;
    sync.attachDrive(service);
    syncFolder.attachDrive(service);
    await refreshQuota();
  }

  Future<void> refreshQuota() async {
    final service = drive;
    if (service == null || link.isOffline) return;
    try {
      final fresh = await service.quota();
      quota = fresh;
      quotaAsOf = DateTime.now();
      await _cache.saveQuota(
        limit: fresh.limit,
        usage: fresh.usage,
        driveUsage: fresh.driveUsage,
      );
    } catch (e) {
      error = 'Drive quota unavailable: $e';
    }
    notifyListeners();
  }

  Future<void> disconnectDrive() async {
    await _auth.signOut();
    drive = null;
    quota = null;
    quotaAsOf = null;
    sync.attachDrive(null);
    notifyListeners();
  }

  Future<void> startScan() async {
    final volume = selected;
    if (volume == null) return;
    await _scanSub?.cancel();
    progress = const ScanProgress(filesSeen: 0, bytesSeen: 0, currentPath: '');
    error = null;
    notifyListeners();

    final completer = Completer<void>();
    _scanSub = _storage
        .scan(volume)
        .listen(
          (p) {
            progress = p;
            if (p.result != null) scans[volume.id] = p.result!;
            notifyListeners();
          },
          onError: (Object e) {
            error = 'Scan failed: $e';
            progress = null;
            notifyListeners();
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    await completer.future;
    await refreshVolumes();

    final result = scans[volume.id];
    if (result != null) {
      // Cache first: a scan is expensive, and it is what makes the app useful
      // with no network.
      await _cache.saveScan(result);
      sync.queue(sync.plan(result));
      if (sync.shouldAutoRun(result)) {
        await backupNow();
      }
    }
  }

  void cancelScan() {
    _scanSub?.cancel();
    _scanSub = null;
    progress = null;
    notifyListeners();
  }

  Future<void> backupNow({Set<String>? only}) =>
      sync.run(deviceFolder: deviceLabel, only: only);

  Future<void> checkForNewMedia() => media.check(manual: true);

  @override
  void dispose() {
    _scanSub?.cancel();
    sync.removeListener(notifyListeners);
    media.removeListener(notifyListeners);
    settings.removeListener(_onSettingsChanged);
    link.removeListener(notifyListeners);
    syncFolder.removeListener(notifyListeners);
    media.dispose();
    sync.dispose();
    link.dispose();
    syncFolder.dispose();
    super.dispose();
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
