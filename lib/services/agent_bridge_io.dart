import 'dart:convert';
import 'dart:io';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

const _agentPort = 47823;

Future<void> postToFloatingAgent(String path, Map<String, Object?> body) async {
  if (Platform.isAndroid) return _postToOverlay(path, body);
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final req = await client.post('127.0.0.1', _agentPort, path);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    await (await req.close()).drain<void>();
  } catch (_) {
    // Floating agent not running; the in-app agent still speaks.
  } finally {
    client.close();
  }
}

/// On Android the floating agent is an overlay of this same app.
Future<void> _postToOverlay(String path, Map<String, Object?> body) async {
  try {
    if (!await FlutterOverlayWindow.isActive()) return;
    if (path == '/say') {
      await FlutterOverlayWindow.shareData(body);
    } else if (path == '/status') {
      await FlutterOverlayWindow.shareData({
        'type': 'status',
        'summary': _summary(body),
      });
    }
  } catch (_) {}
}

String _summary(Map<String, Object?> s) {
  final pending = s['pending'] ?? 0;
  final failed = s['failed'] ?? 0;
  final todos = (s['todos'] as List?)?.length ?? 0;
  final b = StringBuffer('${s['link']}. ');
  b.write(
    s['backupRunning'] == true
        ? 'Backup running, $pending files to go. '
        : (pending == 0
              ? 'Backups are up to date. '
              : '$pending files waiting. '),
  );
  if (failed != 0) b.write('$failed failed. ');
  if (todos > 0) b.write('$todos to-do tasks left.');
  return b.toString();
}
