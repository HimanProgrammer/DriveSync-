import 'dart:io';

import 'power_service.dart';

PowerService createPowerService() => IoPowerService();

/// Windows-only: Android has no concept of "shut down the device" available
/// to a regular app, and desktop Linux/macOS builds aren't shipped here, so
/// this only ever does something real under `Platform.isWindows`.
class IoPowerService implements PowerService {
  @override
  bool get canShutdown => Platform.isWindows;

  @override
  Future<void> scheduleShutdown(Duration delay) async {
    if (!canShutdown) {
      throw UnsupportedError('Shutdown is only available on Windows.');
    }
    // `shutdown /t` schedules Windows' own countdown, which the user can
    // still cancel from Windows itself (or via cancelShutdown below) even if
    // DriveSync is closed in the meantime.
    await Process.run('shutdown', [
      '/s',
      '/t',
      '${delay.inSeconds}',
      '/c',
      'DriveSync finished backing up and is shutting this PC down.',
    ]);
  }

  @override
  Future<void> cancelShutdown() async {
    if (!canShutdown) return;
    // Exit code is nonzero when nothing was scheduled — not an error worth
    // surfacing, so this stays fire-and-forget from the caller's view.
    await Process.run('shutdown', ['/a']);
  }
}
