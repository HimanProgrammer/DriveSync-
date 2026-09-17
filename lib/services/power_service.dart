import 'power_service_web.dart' if (dart.library.io) 'power_service_io.dart';

/// Lets DriveSync shut the machine down once a backup finishes — used by the
/// optional "Shut down this PC when done" checkbox. Not available on Android
/// or web, where [canShutdown] is simply false.
abstract class PowerService {
  factory PowerService() => createPowerService();

  bool get canShutdown;

  /// Schedules a shutdown after [delay], giving the OS's own countdown UI a
  /// chance to show and be cancelled.
  Future<void> scheduleShutdown(Duration delay);

  /// Cancels a shutdown scheduled by [scheduleShutdown], if one is pending.
  Future<void> cancelShutdown();
}
