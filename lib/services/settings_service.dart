import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/storage_models.dart';

/// Manual = nothing leaves the device until the user presses Back up.
/// Auto = DriveSync watches the volume and offloads on its own.
enum SyncMode { auto, manual }

class Settings {
  const Settings({
    this.mode = SyncMode.manual,
    this.autoPromptShown = false,
    this.triggerFraction = 0.85,
    this.minFileBytes = 25 * 1024 * 1024,
    this.deleteLocalAfterUpload = false,
    this.wifiOnly = true,
    this.autoMobileBackup = false,
    this.categories = const {
      FileCategory.videos,
      FileCategory.images,
      FileCategory.archives,
      FileCategory.documents,
    },
  });

  final SyncMode mode;

  /// Whether the "turn on Auto mode?" popup has already been answered.
  final bool autoPromptShown;

  /// Auto mode starts offloading once a volume passes this fullness.
  final double triggerFraction;

  /// Files smaller than this are not worth a round trip.
  final int minFileBytes;

  /// Off by default: deleting the local copy is destructive and irreversible.
  final bool deleteLocalAfterUpload;
  final bool wifiOnly;

  /// Auto Mobile Backup: sweep the camera roll for new photos and videos and
  /// send them to Drive without being asked each time.
  final bool autoMobileBackup;

  final Set<FileCategory> categories;

  bool get isAuto => mode == SyncMode.auto;

  Settings copyWith({
    SyncMode? mode,
    bool? autoPromptShown,
    double? triggerFraction,
    int? minFileBytes,
    bool? deleteLocalAfterUpload,
    bool? wifiOnly,
    bool? autoMobileBackup,
    Set<FileCategory>? categories,
  }) =>
      Settings(
        mode: mode ?? this.mode,
        autoPromptShown: autoPromptShown ?? this.autoPromptShown,
        triggerFraction: triggerFraction ?? this.triggerFraction,
        minFileBytes: minFileBytes ?? this.minFileBytes,
        deleteLocalAfterUpload: deleteLocalAfterUpload ?? this.deleteLocalAfterUpload,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        autoMobileBackup: autoMobileBackup ?? this.autoMobileBackup,
        categories: categories ?? this.categories,
      );
}

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs) : _settings = _read(_prefs);

  static const _kMode = 'dv.mode';
  static const _kPrompt = 'dv.autoPromptShown';
  static const _kTrigger = 'dv.triggerFraction';
  static const _kMinBytes = 'dv.minFileBytes';
  static const _kDelete = 'dv.deleteLocalAfterUpload';
  static const _kWifi = 'dv.wifiOnly';
  static const _kMobileBackup = 'dv.autoMobileBackup';
  static const _kCategories = 'dv.categories';

  final SharedPreferences _prefs;
  Settings _settings;

  Settings get value => _settings;

  static Future<SettingsService> load() async =>
      SettingsService(await SharedPreferences.getInstance());

  static Settings _read(SharedPreferences p) {
    const defaults = Settings();
    final names = p.getStringList(_kCategories);
    return Settings(
      mode: p.getString(_kMode) == 'auto' ? SyncMode.auto : SyncMode.manual,
      autoPromptShown: p.getBool(_kPrompt) ?? false,
      triggerFraction: p.getDouble(_kTrigger) ?? defaults.triggerFraction,
      minFileBytes: p.getInt(_kMinBytes) ?? defaults.minFileBytes,
      deleteLocalAfterUpload: p.getBool(_kDelete) ?? false,
      wifiOnly: p.getBool(_kWifi) ?? true,
      autoMobileBackup: p.getBool(_kMobileBackup) ?? false,
      categories: names == null
          ? defaults.categories
          : names
              .map((n) => FileCategory.values.where((c) => c.name == n).firstOrNull)
              .whereType<FileCategory>()
              .toSet(),
    );
  }

  Future<void> update(Settings next) async {
    _settings = next;
    notifyListeners();
    await Future.wait([
      _prefs.setString(_kMode, next.mode.name),
      _prefs.setBool(_kPrompt, next.autoPromptShown),
      _prefs.setDouble(_kTrigger, next.triggerFraction),
      _prefs.setInt(_kMinBytes, next.minFileBytes),
      _prefs.setBool(_kDelete, next.deleteLocalAfterUpload),
      _prefs.setBool(_kWifi, next.wifiOnly),
      _prefs.setBool(_kMobileBackup, next.autoMobileBackup),
      _prefs.setStringList(
        _kCategories,
        next.categories.map((c) => c.name).toList(),
      ),
    ]);
  }

  Future<void> setMode(SyncMode mode) =>
      update(_settings.copyWith(mode: mode, autoPromptShown: true));

  Future<void> markPromptShown() =>
      update(_settings.copyWith(autoPromptShown: true));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
