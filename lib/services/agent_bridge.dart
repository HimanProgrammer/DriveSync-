import 'agent_bridge_web.dart' if (dart.library.io) 'agent_bridge_io.dart';

/// Sends what the agent says to the separate floating DriveSync Agent app
/// (agent_app/), if it is running on this PC. Silently does nothing if not.
Future<void> sendToFloatingAgent(String text, {String app = 'DriveSync'}) =>
    postToFloatingAgent('/say', {'app': app, 'text': text});

/// Sends a status snapshot the floating agent shows in its monitor panel.
Future<void> sendStatusToFloatingAgent(Map<String, Object?> status) =>
    postToFloatingAgent('/status', status);
