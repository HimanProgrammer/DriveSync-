import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Port the agent listens on. Any app on this PC can talk through the agent
/// by sending: POST http://127.0.0.1:47823/say  {"app": "...", "text": "..."}
const agentPort = 47823;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();
  const options = WindowOptions(
    size: Size(420, 190),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setAlignment(Alignment.bottomRight);
    await windowManager.show();
  });
  runApp(const AgentApp());
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF1D4ED8),
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
    ),
    home: const FloatingAgent(),
  );
}

class AgentMessage {
  AgentMessage(this.app, this.text);
  final String app;
  final String text;
}

class FloatingAgent extends StatefulWidget {
  const FloatingAgent({super.key});

  @override
  State<FloatingAgent> createState() => _FloatingAgentState();
}

class _FloatingAgentState extends State<FloatingAgent>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  HttpServer? _server;
  AgentMessage? _current;
  AgentMessage? _last;
  Timer? _hide;
  bool _muted = false;
  String _serverStatus = 'starting';
  bool _panelOpen = false;
  final List<String> _commandQueue = [];
  final List<(bool, String)> _chat = [];
  final TextEditingController _input = TextEditingController();
  Map<String, dynamic>? _status;
  DateTime? _statusAt;
  Timer? _staleCheck;

  static const _small = Size(420, 190);
  static const _big = Size(420, 560);

  bool get _driveSyncLive =>
      _statusAt != null &&
      DateTime.now().difference(_statusAt!) < const Duration(seconds: 15);

  /// Grows/shrinks the window upward so the agent stays where you put him.
  Future<void> _togglePanel() async {
    final open = !_panelOpen;
    final b = await windowManager.getBounds();
    final size = open ? _big : _small;
    await windowManager.setBounds(
      Rect.fromLTWH(
        b.right - size.width,
        b.bottom - size.height,
        size.width,
        size.height,
      ),
    );
    setState(() => _panelOpen = open);
  }

  @override
  void initState() {
    super.initState();
    _voice(() => _tts.setPitch(1.25));
    _voice(() => _tts.setSpeechRate(0.5));
    _registerHotkey();
    _tts.setStartHandler(() => _bob.repeat(reverse: true));
    _tts.setCompletionHandler(() => _bob.animateTo(0));
    _tts.setCancelHandler(() => _bob.animateTo(0));
    _tts.setErrorHandler((_) => _bob.animateTo(0));
    _startServer();
    _staleCheck = Timer.periodic(
      const Duration(seconds: 5),
      (_) => mounted ? setState(() {}) : null,
    );
    _show(
      AgentMessage(
        'Assistant',
        "Hi! I'm your personal assistant. Press Ctrl+Alt+Space any time, "
            'or tap me and type help.',
      ),
    );
  }

  Future<void> _startServer() async {
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        agentPort,
      );
      _server = server;
      setState(() => _serverStatus = 'listening on $agentPort');
      server.listen(_handle);
    } catch (e) {
      // Usually means another copy of the agent is already running.
      setState(() => _serverStatus = 'port $agentPort busy');
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method == 'GET' && req.uri.path == '/ping') {
        res.write('ok');
      } else if (req.method == 'POST' && req.uri.path == '/commands/take') {
        // DriveSync collects typed commands here every few seconds.
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(_commandQueue));
        _commandQueue.clear();
      } else if (req.method == 'POST' && req.uri.path == '/chat') {
        // Same as typing in the chat box: {"text": "remind me in 5 min to ..."}
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        await _send('${body['text'] ?? ''}');
        res.write('ok');
      } else if (req.method == 'POST' && req.uri.path == '/show') {
        await _summon();
        res.write('ok');
      } else if (req.method == 'POST' && req.uri.path == '/hide') {
        await _dismiss();
        res.write('ok');
      } else if (req.method == 'POST' && req.uri.path == '/status') {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        if (body is Map<String, dynamic>) {
          final wasLive = _driveSyncLive;
          setState(() {
            _status = body;
            _statusAt = DateTime.now();
          });
          if (!wasLive) {
            _show(
              AgentMessage(
                'DriveSync',
                'Connected to DriveSync. I am watching everything now.',
              ),
            );
          }
        }
        res.write('ok');
      } else if (req.method == 'GET' && req.uri.path == '/status') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'live': _driveSyncLive, 'status': _status}));
      } else if (req.method == 'POST' && req.uri.path == '/say') {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        final text = (body['text'] as String? ?? '').trim();
        if (text.isEmpty) {
          res.statusCode = HttpStatus.badRequest;
        } else {
          final app = (body['app'] as String? ?? 'App').trim();
          _show(
            AgentMessage(
              app,
              text.length > 400 ? text.substring(0, 400) : text,
            ),
          );
          res.write('ok');
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      res.statusCode = HttpStatus.badRequest;
    }
    await res.close();
  }

  /// Speech is best-effort: a PC without a voice installed must not break
  /// the agent.
  Future<void> _voice(Future<dynamic> Function() call) async {
    try {
      await call();
    } catch (_) {}
  }

  /// The summon hotkey: Ctrl + Alt + Space. Press it anywhere to call the
  /// agent; press again to send him away.
  static final _summonKey = HotKey(
    key: PhysicalKeyboardKey.space,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );

  Future<void> _registerHotkey() async {
    try {
      await hotKeyManager.register(
        _summonKey,
        keyDownHandler: (_) async {
          if (await windowManager.isVisible()) {
            await _dismiss();
          } else {
            await _summon();
          }
        },
      );
    } catch (_) {
      // Another app owns the shortcut; /show and the tray still work.
    }
  }

  static const _greetings = [
    "Yes? I'm here!",
    'You called? What do you need?',
    'Hey! Ready when you are.',
  ];
  int _greet = 0;

  /// Brings the agent back on screen and greets with a quick status line.
  Future<void> _summon({String? reason}) async {
    await windowManager.show();
    await windowManager.setAlwaysOnTop(true);
    final s = _status;
    var line = _greetings[_greet++ % _greetings.length];
    if (_driveSyncLive && s != null) {
      final pending = (s['pending'] as num?)?.toInt() ?? 0;
      final todos = (s['todos'] as List?)?.length ?? 0;
      line +=
          ' ${pending == 0 ? 'Backups are up to date.' : '$pending files waiting to back up.'}'
          '${todos > 0 ? ' $todos to-do tasks left.' : ''}';
    }
    await _show(AgentMessage(reason ?? 'Assistant', line));
  }

  static const _help =
      'I can: tell the time or date, remind me in 10 min to <something>, '
      'open <website or app>, note <text>, notes, status, mute, unmute, hide. '
      'With DriveSync open: backup, scan, storage, add <task> [30 min], list, '
      'done <number>, daily 9pm, daily off.';

  final List<String> _notes = [];

  /// Personal-assistant commands that work on their own, without DriveSync.
  /// Returns true when handled.
  Future<bool> _personal(String text) async {
    final lower = text.toLowerCase();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');

    if (RegExp(r'^(time|what.*time.*)$').hasMatch(lower)) {
      final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
      await _say('It is $h:${two(now.minute)} ${now.hour < 12 ? 'AM' : 'PM'}.');
      return true;
    }
    if (RegExp(r'^(date|today|what.*(date|day).*)$').hasMatch(lower)) {
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      await _say(
        'Today is ${days[now.weekday - 1]}, ${now.day} '
        '${months[now.month - 1]} ${now.year}.',
      );
      return true;
    }
    final remind = RegExp(
      r'^remind me in (\d+)\s*(s|sec|secs|seconds|m|min|mins|minutes|h|hr|hrs|hours?)\s+(?:to\s+)?(.+)$',
    ).firstMatch(lower);
    if (remind != null) {
      final n = int.parse(remind.group(1)!);
      final unit = remind.group(2)!;
      final d = unit.startsWith('h')
          ? Duration(hours: n)
          : unit.startsWith('s')
          ? Duration(seconds: n)
          : Duration(minutes: n);
      final what = text.substring(text.length - remind.group(3)!.length);
      Timer(d, () async {
        await windowManager.show();
        await _show(AgentMessage('Reminder', 'Hey! Time to $what.'));
      });
      await _say(
        'Okay, I will remind you in $n ${unit.startsWith('h')
            ? 'hours'
            : unit.startsWith('s')
            ? 'seconds'
            : 'minutes'}.',
      );
      return true;
    }
    final open = RegExp(r'^open\s+(.+)$').firstMatch(text);
    if (open != null) {
      var target = open.group(1)!.trim();
      final looksLikeSite = target.contains('.') && !target.contains(' ');
      if (looksLikeSite && !target.startsWith('http')) {
        target = 'https://$target';
      }
      try {
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', target]);
        } else {
          await Process.run('xdg-open', [target]);
        }
        await _say('Opening $target.');
      } catch (_) {
        await _say("I couldn't open $target.");
      }
      return true;
    }
    final note = RegExp(r'^note\s+(.+)$').firstMatch(text);
    if (note != null) {
      _notes.add(note.group(1)!);
      await _say('Noted. You have ${_notes.length} notes.');
      return true;
    }
    if (lower == 'notes') {
      await _say(
        _notes.isEmpty
            ? 'You have no notes yet. Say: note buy milk'
            : 'Your notes: ${[for (var i = 0; i < _notes.length; i++) '${i + 1}. ${_notes[i]}'].join('. ')}.',
      );
      return true;
    }
    if (RegExp(r'^(hi|hello|hey)\b').hasMatch(lower)) {
      await _say('Hi! What can I do for you? Type help to see my skills.');
      return true;
    }
    if (RegExp(r'^(thanks|thank you)').hasMatch(lower)) {
      await _say("You're welcome!");
      return true;
    }
    return false;
  }

  Future<void> _say(String text) => _show(AgentMessage('Assistant', text));

  /// Handles what you type in the chat box. Agent-only commands run here;
  /// the rest go to DriveSync, which picks them up within a few seconds.
  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() => _chat.add((true, text)));
    final lower = text.toLowerCase();
    if (lower == 'help' || lower == '?') {
      await _show(AgentMessage('Assistant', _help));
    } else if (lower == 'hide') {
      await _dismiss();
    } else if (lower == 'mute') {
      setState(() => _muted = true);
      await _show(
        AgentMessage('Assistant', 'Muted. I will only show bubbles.'),
      );
    } else if (lower == 'unmute') {
      setState(() => _muted = false);
      await _show(AgentMessage('Assistant', "I'm back with my voice!"));
    } else if (lower == 'status') {
      await _summon(reason: 'Assistant');
    } else if (await _personal(text)) {
      // Handled by the assistant itself.
    } else if (!_driveSyncLive) {
      await _say(
        "I don't know that one yet. Type help to see what I can do. "
        '(Backup and to-do commands need DriveSync open.)',
      );
    } else {
      _commandQueue.add(text);
      await _say('Okay, asking DriveSync...');
    }
  }

  Future<void> _dismiss() async {
    await _voice(_tts.stop);
    await windowManager.hide();
  }

  Future<void> _show(AgentMessage m) async {
    _chat.add((false, m.text));
    if (_chat.length > 50) _chat.removeAt(0);
    setState(() {
      _current = m;
      _last = m;
    });
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _current = null);
    });
    if (!_muted) {
      await _voice(_tts.stop);
      await _voice(() => _tts.speak(m.text));
    }
  }

  Future<void> _menu(Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'mute', child: Text(_muted ? 'Unmute' : 'Mute')),
        PopupMenuItem(enabled: false, child: Text('Server: $_serverStatus')),
        PopupMenuItem(
          enabled: false,
          child: Text(
            _driveSyncLive ? 'DriveSync: connected' : 'DriveSync: not running',
          ),
        ),
        const PopupMenuItem(
          value: 'hide',
          child: Text('Hide (Ctrl+Alt+Space to call me)'),
        ),
        const PopupMenuItem(value: 'quit', child: Text('Quit agent')),
      ],
    );
    if (choice == 'mute') {
      setState(() => _muted = !_muted);
      if (_muted) await _voice(_tts.stop);
    } else if (choice == 'hide') {
      await _dismiss();
    } else if (choice == 'quit') {
      await hotKeyManager.unregisterAll();
      await _server?.close(force: true);
      await windowManager.close();
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _staleCheck?.cancel();
    _input.dispose();
    _server?.close(force: true);
    _voice(_tts.stop);
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = _current;
    return Scaffold(
      body: Column(
        children: [
          if (_panelOpen)
            Expanded(
              child: _MonitorPanel(
                live: _driveSyncLive,
                status: _status,
                at: _statusAt,
                onClose: _togglePanel,
                chat: _chat,
                input: _input,
                onSend: _send,
              ),
            ),
          SizedBox(
            height: _small.height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedOpacity(
                    opacity: m == null ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: m == null
                        ? const SizedBox.shrink()
                        : Container(
                            margin: const EdgeInsets.only(bottom: 40, right: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(blurRadius: 8, color: Colors.black26),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.app,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.text,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                // Drag him anywhere; tap to repeat; right-click for the menu.
                GestureDetector(
                  onPanStart: (_) => windowManager.startDragging(),
                  onTap: _togglePanel,
                  onDoubleTap: () {
                    final last = _last;
                    if (last != null) _show(last);
                  },
                  onSecondaryTapDown: (d) => _menu(d.globalPosition),
                  onLongPressStart: (d) => _menu(d.globalPosition),
                  child: AnimatedBuilder(
                    animation: _bob,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, -8 * _bob.value),
                      child: child,
                    ),
                    child: Image.asset('assets/agent_mascot.webp', height: 170),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything DriveSync reports, at a glance.
class _MonitorPanel extends StatelessWidget {
  const _MonitorPanel({
    required this.live,
    required this.status,
    required this.at,
    required this.onClose,
    required this.chat,
    required this.input,
    required this.onSend,
  });

  final List<(bool, String)> chat;
  final TextEditingController input;
  final ValueChanged<String> onSend;
  final bool live;
  final Map<String, dynamic>? status;
  final DateTime? at;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    Widget row(IconData icon, String label, String value, {Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(label)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );

    final children = <Widget>[
      Row(
        children: [
          Icon(Icons.circle, size: 12, color: live ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              live ? 'DriveSync connected' : 'DriveSync not running',
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ],
      ),
    ];

    if (s == null) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Open DriveSync on this PC and I will start monitoring it.',
          ),
        ),
      );
    } else {
      final failed = (s['failed'] as num?)?.toInt() ?? 0;
      final drivePct = s['driveUsedPercent'] as num?;
      children.addAll([
        const Divider(),
        row(Icons.computer, 'Device', '${s['device'] ?? '-'}'),
        row(Icons.wifi, 'Internet', '${s['link'] ?? '-'}'),
        row(
          Icons.cloud,
          'Google Drive',
          s['driveConnected'] == true
              ? '${s['driveAccount'] ?? 'connected'}'
              : 'not connected',
        ),
        if (drivePct != null)
          row(
            Icons.pie_chart,
            'Drive used',
            '$drivePct%',
            color: drivePct >= 90 ? Colors.red : null,
          ),
        const Divider(),
        row(
          Icons.cloud_upload,
          'Backup',
          s['backupRunning'] == true ? 'running' : 'idle',
        ),
        row(Icons.check_circle, 'Uploaded', '${s['done'] ?? 0}'),
        row(Icons.schedule, 'Waiting', '${s['pending'] ?? 0}'),
        row(
          Icons.error,
          'Failed',
          '$failed',
          color: failed > 0 ? Colors.red : null,
        ),
        row(Icons.alarm, 'Daily backup', '${s['dailyBackup'] ?? 'off'}'),
        if (s['lastRun'] != null)
          row(
            Icons.history,
            'Last backup',
            _ago(DateTime.tryParse('${s['lastRun']}')),
          ),
        const Divider(),
        for (final v in (s['volumes'] as List? ?? const []))
          row(
            Icons.storage,
            '${v['label']}',
            '${v['usedPercent']}% full',
            color: ((v['usedPercent'] as num?) ?? 0) >= 90 ? Colors.red : null,
          ),
        const Divider(),
        Text(
          'To-Do (${(s['todos'] as List? ?? const []).length})',
          style: theme.textTheme.titleSmall,
        ),
        for (final t in (s['todos'] as List? ?? const []))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.check_box_outline_blank, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text('$t')),
              ],
            ),
          ),
        if (((s['todoMinutes'] as num?) ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'About ${s['todoMinutes']} minutes in total',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (at != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Updated ${_ago(at)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ]);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                children.first,
                if (chat.isNotEmpty) ...[
                  for (final (mine, text)
                      in chat.reversed.take(6).toList().reversed)
                    Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                          color: mine
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: mine
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                ],
                ...children.skip(1),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Type a command (try "help")',
                      isDense: true,
                    ),
                    onSubmitted: onSend,
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                  onPressed: () => onSend(input.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime? t) {
    if (t == null) return '-';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} days ago';
  }
}
