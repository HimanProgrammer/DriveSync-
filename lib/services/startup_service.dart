import 'startup_service_web.dart'
    if (dart.library.io) 'startup_service_io.dart';

/// Starts DriveSync automatically when the user signs in to Windows, so the
/// agent's automations (auto-backup, daily backup) keep running. Only
/// supported on Windows; elsewhere [isSupported] is false.
abstract class StartupService {
  factory StartupService() => createStartupService();

  bool get isSupported;
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}
