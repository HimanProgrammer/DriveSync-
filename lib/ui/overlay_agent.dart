import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// The floating agent drawn over other apps on Android. Runs in its own
/// engine (see `overlayMain` in main.dart); DriveSync sends it messages with
/// `FlutterOverlayWindow.shareData({'text': ..., 'app': ...})`.
class OverlayAgentApp extends StatelessWidget {
  const OverlayAgentApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1D4ED8)),
    home: const _OverlayAgent(),
  );
}

class _OverlayAgent extends StatefulWidget {
  const _OverlayAgent();

  @override
  State<_OverlayAgent> createState() => _OverlayAgentState();
}

class _OverlayAgentState extends State<_OverlayAgent>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  StreamSubscription<dynamic>? _sub;
  String? _text;
  String _app = 'DriveSync';
  String? _last;
  String? _status;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _voice(() => _tts.setPitch(1.25));
    _voice(() => _tts.setSpeechRate(0.5));
    _tts.setStartHandler(() => _bob.repeat(reverse: true));
    _tts.setCompletionHandler(() => _bob.animateTo(0));
    _tts.setErrorHandler((_) => _bob.animateTo(0));
    _sub = FlutterOverlayWindow.overlayListener.listen(_onData);
  }

  Future<void> _voice(Future<dynamic> Function() call) async {
    try {
      await call();
    } catch (_) {}
  }

  void _onData(dynamic data) {
    if (data is! Map) return;
    if (data['type'] == 'status') {
      setState(() => _status = data['summary'] as String?);
      return;
    }
    final text = data['text'] as String?;
    if (text == null || text.isEmpty) return;
    _say(text, app: data['app'] as String? ?? 'DriveSync');
  }

  void _say(String text, {String app = 'DriveSync'}) {
    setState(() {
      _text = text;
      _app = app;
      _last = text;
    });
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _text = null);
    });
    _voice(_tts.stop);
    _voice(() => _tts.speak(text));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = _text;
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (text != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(blurRadius: 6, color: Colors.black26),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _app,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          GestureDetector(
            // Tap: hear the status (or the last message) again.
            onTap: () =>
                _say(_status ?? _last ?? "Hi! I'm watching your backups."),
            // Long-press: put the agent away.
            onLongPress: FlutterOverlayWindow.closeOverlay,
            child: AnimatedBuilder(
              animation: _bob,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, -6 * _bob.value),
                child: child,
              ),
              child: Image.asset(
                'assets/branding/agent_mascot.webp',
                height: 110,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
