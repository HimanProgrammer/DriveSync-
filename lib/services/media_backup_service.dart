import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/storage_models.dart';
import 'connectivity_service.dart';
import 'offline_cache.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Auto Mobile Backup: keeps an eye on the camera roll and pushes new photos
/// and videos to Drive without the user asking each time.
///
/// It is deliberately poll-based on a timer rather than a filesystem watcher:
/// media folders on Android churn (thumbnails, `.pending` files), and a
/// watermark + periodic sweep is both cheaper and restart-safe.
class MediaBackupService extends ChangeNotifier {
  MediaBackupService({
    required StorageService storage,
    required SettingsService settings,
    required OfflineCache cache,
    required ConnectivityService connectivity,
    required Future<void> Function(List<FileEntry> media) onNewMedia,
    this.interval = const Duration(minutes: 10),
  })  : _storage = storage,
        _settings = settings,
        _cache = cache,
        _connectivity = connectivity,
        _onNewMedia = onNewMedia;

  final StorageService _storage;
  final SettingsService _settings;
  final OfflineCache _cache;
  final ConnectivityService _connectivity;
  final Future<void> Function(List<FileEntry> media) _onNewMedia;
  final Duration interval;

  Timer? _timer;
  bool _checking = false;

  DateTime? lastCheck;
  int lastFoundCount = 0;
  String? status;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => check());
    // Sweep once at launch so a phone that was off overnight catches up.
    check();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Looks for media newer than the stored watermark and hands it to the sync
  /// engine. Safe to call at any time; overlapping calls are ignored.
  Future<void> check({bool manual = false}) async {
    if (_checking) return;
    final s = _settings.value;
    if (!manual && !s.autoMobileBackup) return;

    _checking = true;
    try {
      final media = await _storage.newMediaSince(_cache.mediaCursor);
      lastCheck = DateTime.now();
      lastFoundCount = media.length;

      if (media.isEmpty) {
        status = 'No new photos or videos since the last check.';
        notifyListeners();
        return;
      }

      // Queue regardless of the link state — an offline queue is the point.
      await _onNewMedia(media);

      final link = _connectivity.canUpload(wifiOnly: s.wifiOnly);
      status = link.allowed
          ? '${media.length} new item(s) queued for backup.'
          : '${media.length} new item(s) queued. ${link.reason}';

      // Advance the watermark only to the newest item we have taken
      // responsibility for, so a crash mid-upload re-queues rather than skips.
      final newest = media
          .map((m) => m.modified)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      await _cache.setMediaCursor(newest);
    } catch (e) {
      status = 'Media check failed: $e';
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
