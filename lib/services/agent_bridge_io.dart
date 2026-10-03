import 'dart:convert';
import 'dart:io';

const _agentPort = 47823;

Future<void> sendToFloatingAgentImpl(String text, String app) async {
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final req = await client.post('127.0.0.1', _agentPort, '/say');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'app': app, 'text': text}));
    await (await req.close()).drain<void>();
  } catch (_) {
    // Floating agent not running; the in-app agent still speaks.
  } finally {
    client.close();
  }
}
