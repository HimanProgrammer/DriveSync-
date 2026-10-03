import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import 'connectivity_service.dart';

/// The talking agent's automations. Lives on [AppState] so it keeps working
/// whichever page is open. Each automation posts a line to [announcement]
/// for the agent to say out loud.
///
/// - Internet status: announces going offline / online and the link type.
/// - Auto-backup when online: when the link comes back and files are queued,
///   starts the backup on its own (respecting the Wi-Fi-only setting).
/// - Daily backup: at the chosen time each day, runs a backup.
/// - Storage alerts: warns once per session when Drive or a local volume is
///   90% full.
class AgentAutomation extends ChangeNotifier {
  AgentAutomation(this._app);

  final AppState _app;
  SharedPreferences? _prefs;
  Timer? _ticker;
  LinkState? _lastLink;
  final Set<String> _warned = {};

  static const _kHour = 'agent.dailyHour';
  static const _kMinute = 'agent.dailyMinute';
  static const _kLastDaily = 'agent.lastDailyRun';
  static const _alertFraction = 0.9;

  /// The latest thing the agent wants to say, with a counter so the same
  /// text said twice still counts as new.
  String? announcement;
  int announcementId = 0;

  /// Daily backup time as (hour, minute), or null when off.
  (int, int)? get dailyTime {
    final h = _prefs?.getInt(_kHour);
    final m = _prefs?.getInt(_kMinute);
    return (h == null || m == null) ? null : (h, m);
  }

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    _lastLink = _app.link.state;
    _app.link.addListener(_onLinkChanged);
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    _tick();
  }

  Future<void> setDailyTime(int? hour, int? minute) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    if (hour == null || minute == null) {
      await prefs.remove(_kHour);
      await prefs.remove(_kMinute);
      _say('Daily backup is off.');
    } else {
      await prefs.setInt(_kHour, hour);
      await prefs.setInt(_kMinute, minute);
      _say('Got it! I will back up every day at ${_fmt(hour, minute)}.');
    }
    notifyListeners();
  }

  void _say(String text) {
    announcement = text;
    announcementId++;
    notifyListeners();
  }

  void _onLinkChanged() {
    final now = _app.link.state;
    final before = _lastLink;
    _lastLink = now;
    if (now == before) return;

    switch (now) {
      case LinkState.offline:
        _say("Uh oh, the internet is gone. I'll wait and back up when it's back.");
        return;
      case LinkState.metered:
        _say(_app.settings.value.wifiOnly
            ? "I'm on mobile data. Uploads wait for Wi-Fi, as you asked."
            : "I'm on mobile data. Uploads are allowed.");
      case LinkState.unmetered:
        _say(before == LinkState.offline
            ? "We're back online on Wi-Fi!"
            : "Switched to Wi-Fi. Uploads are allowed.");
    }
    _autoBackup(reason: 'online');
  }

  /// Starts a backup if there is something queued and it is allowed now.
  void _autoBackup({required String reason}) {
    final status = _app.sync.status;
    if (!_app.isConnected || status.running || status.pendingCount == 0) {
      return;
    }
    final link = _app.link.canUpload(wifiOnly: _app.settings.value.wifiOnly);
    if (!link.allowed) return;
    _say(reason == 'daily'
        ? "It's backup time! Uploading ${status.pendingCount} files."
        : 'Starting the backup of ${status.pendingCount} waiting files.');
    _app.backupNow();
  }

  void _tick() {
    _checkDaily();
    _checkStorage();
  }

  void _checkDaily() {
    final time = dailyTime;
    final prefs = _prefs;
    if (time == null || prefs == null) return;
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day, time.$1, time.$2);
    final today = '${now.year}-${now.month}-${now.day}';
    if (now.isBefore(due) || prefs.getString(_kLastDaily) == today) return;
    prefs.setString(_kLastDaily, today);

    if (_app.sync.status.pendingCount == 0) {
      _say('Daily check done: nothing new to back up.');
    } else if (_app.link.isOffline) {
      _say("It's backup time, but we're offline. I'll go when the internet is back.");
    } else {
      _autoBackup(reason: 'daily');
    }
  }

  void _checkStorage() {
    final q = _app.quota;
    if (q != null && !q.isUnlimited && q.limit > 0) {
      final used = q.usage / q.limit;
      if (used >= _alertFraction && _warned.add('drive')) {
        _say('Heads up! Google Drive is ${(used * 100).round()}% full. '
            'Free some space or upgrade your storage.');
        return;
      }
    }
    for (final v in _app.volumes) {
      if (v.usedFraction >= _alertFraction && _warned.add('vol:${v.id}')) {
        _say('Your ${v.label} drive is ${(v.usedFraction * 100).round()}% full. '
            'Try Cleanup, or let me move big files to Drive.');
        return;
      }
    }
  }

  static String _fmt(int h, int m) {
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  String? get dailyLabel {
    final t = dailyTime;
    return t == null ? null : _fmt(t.$1, t.$2);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _app.link.removeListener(_onLinkChanged);
    super.dispose();
  }
}
