import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications (Windows toasts, Android notifications). Used to
/// tell the user before any uploaded file is deleted. Does nothing on web.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'DriveSync',
            appUserModelId: 'HimanProgrammer.DriveSync',
            guid: '6c5e6b2e-4f0b-4c1f-9c0d-6d1a2b3c4d5e',
          ),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  Future<void> show(int id, String title, String body) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'deletes',
            'Files ready to delete',
            channelDescription:
                'Asks before DriveSync deletes files that are safely on Drive',
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
