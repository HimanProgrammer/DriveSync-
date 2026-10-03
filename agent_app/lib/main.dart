import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:window_manager/window_manager.dart';

/// Port the agent listens on. Any app on this PC can talk through the agent
/// by sending: POST http://127.0.0.1:47823/say  {"app": "...", "text": "..."}
const agentPort = 47823;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
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

  @override
  void initState() {
    super.initState();
    _tts.setPitch(1.25);
    _tts.setSpeechRate(0.5);
    _tts.setStartHandler(() => _bob.repeat(reverse: true));
    _tts.setCompletionHandler(() => _bob.animateTo(0));
    _tts.setCancelHandler(() => _bob.animateTo(0));
    _tts.setErrorHandler((_) => _bob.animateTo(0));
    _startServer();
    _show(AgentMessage('Agent', "Hi! I'm your DriveSync Agent. I'll tell you "
        "what your apps are up to."));
  }

  Future<void> _startServer() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, agentPort);
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
      } else if (req.method == 'POST' && req.uri.path == '/say') {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        final text = (body['text'] as String? ?? '').trim();
        if (text.isEmpty) {
          res.statusCode = HttpStatus.badRequest;
        } else {
          final app = (body['app'] as String? ?? 'App').trim();
          _show(AgentMessage(app, text.length > 400 ? text.substring(0, 400) : text));
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

  Future<void> _show(AgentMessage m) async {
    setState(() {
      _current = m;
      _last = m;
    });
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _current = null);
    });
    if (!_muted) {
      await _tts.stop();
      await _tts.speak(m.text);
    }
  }

  Future<void> _menu(Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'mute', child: Text(_muted ? 'Unmute' : 'Mute')),
        PopupMenuItem(enabled: false, child: Text('Server: $_serverStatus')),
        const PopupMenuItem(value: 'quit', child: Text('Quit agent')),
      ],
    );
    if (choice == 'mute') {
      setState(() => _muted = !_muted);
      if (_muted) await _tts.stop();
    } else if (choice == 'quit') {
      await _server?.close(force: true);
      await windowManager.close();
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _server?.close(force: true);
    _tts.stop();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = _current;
    return Scaffold(
      body: Row(
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
                          Text(m.app,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onPrimaryContainer)),
                          const SizedBox(height: 4),
                          Text(m.text,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onPrimaryContainer)),
                        ],
                      ),
                    ),
            ),
          ),
          // Drag him anywhere; tap to repeat; right-click for the menu.
          GestureDetector(
            onPanStart: (_) => windowManager.startDragging(),
            onTap: () {
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
    );
  }
}
