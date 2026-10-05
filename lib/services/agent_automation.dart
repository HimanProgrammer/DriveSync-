import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import 'agent_bridge.dart';
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
    _statusTicker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _safe(_pushStatus),
    );
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _safe(_tick));
    _safe(_pushStatus);
    _safe(_tick);
  }

  /// One failing check must never stop the link to the floating agent.
  void _safe(void Function() f) {
    try {
      f();
    } catch (e) {
      debugPrint('Agent automation: $e');
    }
  }

  Timer? _statusTicker;

  /// Keeps the floating agent's monitor panel up to date.
  void _pushStatus() {
    fetchFloatingAgentCommands().then((cmds) => cmds.forEach(handleCommand));
    final s = _app.sync.status;
    final q = _app.quota;
    sendStatusToFloatingAgent({
      'device': _app.deviceLabel,
      'link': _app.link.label,
      'driveConnected': _app.isConnected,
      'driveAccount': _app.account?.email,
      'driveUsedPercent': (q == null || q.isUnlimited || q.limit <= 0)
          ? null
          : (q.usage * 100 / q.limit).round(),
      'backupRunning': s.running,
      'done': s.doneCount,
      'pending': s.pendingCount,
      'failed': s.failedCount,
      'lastRun': s.lastRun?.toIso8601String(),
      'dailyBackup': dailyLabel,
      'volumes': [
        for (final v in _app.volumes)
          {'label': v.label, 'usedPercent': (v.usedFraction * 100).round()},
      ],
      'todos': [for (final t in _app.todos.open) t.title],
      'todoMinutes': _app.todos.openMinutes,
    });
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
    sendToFloatingAgent(text);
  }

  void _onLinkChanged() {
    final now = _app.link.state;
    final before = _lastLink;
    _lastLink = now;
    if (now == before) return;

    switch (now) {
      case LinkState.offline:
        _say(
          "Uh oh, the internet is gone. I'll wait and back up when it's back.",
        );
        return;
      case LinkState.metered:
        _say(
          _app.settings.value.wifiOnly
              ? "I'm on mobile data. Uploads wait for Wi-Fi, as you asked."
              : "I'm on mobile data. Uploads are allowed.",
        );
      case LinkState.unmetered:
        _say(
          before == LinkState.offline
              ? "We're back online on Wi-Fi!"
              : "Switched to Wi-Fi. Uploads are allowed.",
        );
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
    _say(
      reason == 'daily'
          ? "It's backup time! Uploading ${status.pendingCount} files."
          : 'Starting the backup of ${status.pendingCount} waiting files.',
    );
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
      _say(
        "It's backup time, but we're offline. I'll go when the internet is back.",
      );
    } else {
      _autoBackup(reason: 'daily');
    }
  }

  void _checkStorage() {
    final q = _app.quota;
    if (q != null && !q.isUnlimited && q.limit > 0) {
      final used = q.usage / q.limit;
      if (used >= _alertFraction && _warned.add('drive')) {
        _say(
          'Heads up! Google Drive is ${(used * 100).round()}% full. '
          'Free some space or upgrade your storage.',
        );
        return;
      }
    }
    for (final v in _app.volumes) {
      if (v.usedFraction >= _alertFraction && _warned.add('vol:${v.id}')) {
        _say(
          'Your ${v.label} drive is ${(v.usedFraction * 100).round()}% full. '
          'Try Cleanup, or let me move big files to Drive.',
        );
        return;
      }
    }
  }

  /// Runs a command typed into the floating agent's chat box. Plain words,
  /// no AI: matches simple phrases and replies through the agent.
  void handleCommand(String raw) {
    final cmd = raw.trim();
    final lower = cmd.toLowerCase();
    final status = _app.sync.status;

    if (RegExp(r'^(back ?up|sync)( now)?$').hasMatch(lower)) {
      if (!_app.isConnected) {
        _say('Connect Google Drive in DriveSync first, then I can back up.');
      } else if (status.running) {
        _say(
          'A backup is already running: ${status.pendingCount} files to go.',
        );
      } else if (status.pendingCount == 0) {
        _say(
          'Nothing is waiting. Run a scan in DriveSync to find files to back up.',
        );
      } else if (!_app.link
          .canUpload(wifiOnly: _app.settings.value.wifiOnly)
          .allowed) {
        _say(
          "I can't upload on this connection right now. I'll go when Wi-Fi is back.",
        );
      } else {
        _say('On it! Backing up ${status.pendingCount} files.');
        _app.backupNow();
      }
      return;
    }

    if (lower == 'maintain') {
      _maintain();
      return;
    }

    if (lower == 'pending') {
      if (status.running) {
        _say('Already working: ${status.pendingCount} files to go.');
      } else if (status.pendingCount > 0) {
        handleCommand('backup');
      } else {
        _say('DriveSync has no pending backups.');
      }
      return;
    }

    if (lower == 'scan') {
      _say('Scanning your drive for big files.');
      _app.startScan();
      return;
    }

    final add = RegExp(
      r'^(?:add|todo|remind me to)\s+(.+?)(?:\s+(\d+)\s*(?:m|min|mins|minutes))?$',
      caseSensitive: false,
    ).firstMatch(cmd);
    if (add != null) {
      final minutes = int.tryParse(add.group(2) ?? '');
      _app.todos.add(add.group(1)!, minutes: minutes);
      _say(
        'Added "${add.group(1)}" to your to-do list'
        '${minutes != null ? ', about $minutes minutes' : ''}.',
      );
      return;
    }

    if (RegExp(
      r'^(list|read( my)?( list)?|todos?|what.*to ?do.*)$',
    ).hasMatch(lower)) {
      _say(_app.todos.spokenSummary());
      return;
    }

    final done = RegExp(r'^done\s+(\d+)$').firstMatch(lower);
    if (done != null) {
      final open = _app.todos.open;
      final n = int.parse(done.group(1)!);
      if (n < 1 || n > open.length) {
        _say('There is no task number $n. You have ${open.length} open.');
      } else {
        _app.todos.toggle(open[n - 1]);
        _say('Nice! Marked "${open[n - 1].title}" as done.');
      }
      return;
    }

    if (RegExp(r'^daily (off|stop|none)$').hasMatch(lower)) {
      setDailyTime(null, null);
      return;
    }
    final daily = RegExp(
      r'^daily(?: backup)?(?: at)? (\d{1,2})(?::(\d{2}))? ?(am|pm)?$',
    ).firstMatch(lower);
    if (daily != null) {
      var h = int.parse(daily.group(1)!);
      final m = int.tryParse(daily.group(2) ?? '0') ?? 0;
      final ap = daily.group(3);
      if (ap == 'pm' && h < 12) h += 12;
      if (ap == 'am' && h == 12) h = 0;
      if (h > 23 || m > 59) {
        _say("That time doesn't look right. Try: daily 9pm");
      } else {
        setDailyTime(h, m);
      }
      return;
    }

    if (RegExp(r'^(storage|space|disk)$').hasMatch(lower)) {
      final parts = [
        for (final v in _app.volumes)
          '${v.label} is ${(v.usedFraction * 100).round()}% full',
      ];
      final q = _app.quota;
      if (q != null && !q.isUnlimited && q.limit > 0) {
        parts.add('Google Drive is ${(q.usage * 100 / q.limit).round()}% full');
      }
      _say(parts.isEmpty ? 'No storage info yet.' : '${parts.join('. ')}.');
      return;
    }

    _say("Sorry, I don't know \"$cmd\" yet. Type help to see what I can do.");
  }

  /// Keeps the disk healthy: scans for big files you haven't used in a
  /// while (the scan plan already prefers large, old files), queues them,
  /// and uploads them to Google Drive.
  Future<void> _maintain() async {
    if (!_app.isConnected) {
      _say(
        'Connect Google Drive in DriveSync first, then I can free up space.',
      );
      return;
    }
    await _app.startScan();
    final pending = _app.sync.status.pendingCount;
    if (pending == 0) {
      _say('Your disk looks tidy. No big unused files to move right now.');
    } else if (!_app.sync.status.running) {
      handleCommand('backup');
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
    _statusTicker?.cancel();
    _app.link.removeListener(_onLinkChanged);
    super.dispose();
  }
}
