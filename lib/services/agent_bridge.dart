import 'agent_bridge_web.dart' if (dart.library.io) 'agent_bridge_io.dart';

/// Sends what the agent says to the separate floating DriveSync Agent app
/// (agent_app/), if it is running on this PC. Silently does nothing if not.
Future<void> sendToFloatingAgent(String text, {String app = 'DriveSync'}) =>
    sendToFloatingAgentImpl(text, app);
