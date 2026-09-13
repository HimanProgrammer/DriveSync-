import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/storage_models.dart';

/// Everything DriveSync keeps on disk so it is useful with no network: the
/// last scan per volume, the last known Drive quota, and the pending upload
/// queue (so files chosen offline are still uploaded when the link returns).
class OfflineCache {
  OfflineCache(this._prefs);

  static const _kScanPrefix = 'dv.scan.';
  static const _kScanIds = 'dv.scan.ids';
  static const _kQuota = 'dv.quota';
  static const _kQueue = 'dv.queue';
  static const _kMediaCursor = 'dv.mediaCursor';

  final SharedPreferences _prefs;

  static Future<OfflineCache> load() async =>
      OfflineCache(await SharedPreferences.getInstance());

  // ------------------------------------------------------------------- scans

  Future<void> saveScan(ScanResult result) async {
    final ids = _prefs.getStringList(_kScanIds)?.toSet() ?? <String>{};
    ids.add(result.volume.id);
    await _prefs.setStringList(_kScanIds, ids.toList());
    await _prefs.setString(
      '$_kScanPrefix${result.volume.id}',
      jsonEncode(result.toJson()),
    );
  }

  /// Cached scans keyed by volume id. A row that fails to decode (model change
  /// between versions) is dropped rather than blocking startup.
  Map<String, ScanResult> scans() {
    final out = <String, ScanResult>{};
    for (final id in _prefs.getStringList(_kScanIds) ?? const <String>[]) {
      final raw = _prefs.getString('$_kScanPrefix$id');
      if (raw == null) continue;
      try {
        out[id] = ScanResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('DriveSync: dropping unreadable cached scan for $id ($e)');
        _prefs.remove('$_kScanPrefix$id');
      }
    }
    return out;
  }

  // ------------------------------------------------------------------- quota

  Future<void> saveQuota({
    required int limit,
    required int usage,
    required int driveUsage,
  }) =>
      _prefs.setString(
        _kQuota,
        jsonEncode({
          'limit': limit,
          'usage': usage,
          'driveUsage': driveUsage,
          'at': DateTime.now().toIso8601String(),
        }),
      );

  Map<String, dynamic>? quota() {
    final raw = _prefs.getString(_kQuota);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------- queue

  /// Persists the not-yet-uploaded files so an offline session's choices, and
  /// an interrupted backup, both survive a restart.
  Future<void> saveQueue(List<FileEntry> pending) => _prefs.setString(
        _kQueue,
        jsonEncode([for (final f in pending) f.toJson()]),
      );

  List<FileEntry> queue() {
    final raw = _prefs.getString(_kQueue);
    if (raw == null) return const [];
    try {
      return [
        for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          FileEntry.fromJson(m),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------- mobile backup watermark

  /// Newest media modification time already backed up, so Auto Mobile Backup
  /// only ever looks at what arrived since.
  DateTime? get mediaCursor {
    final raw = _prefs.getString(_kMediaCursor);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setMediaCursor(DateTime at) =>
      _prefs.setString(_kMediaCursor, at.toIso8601String());

  Future<void> clear() async {
    for (final id in _prefs.getStringList(_kScanIds) ?? const <String>[]) {
      await _prefs.remove('$_kScanPrefix$id');
    }
    await _prefs.remove(_kScanIds);
    await _prefs.remove(_kQuota);
    await _prefs.remove(_kQueue);
  }
}
