import 'dart:io';

import 'startup_service.dart';

StartupService createStartupService() => IoStartupService();

/// Uses the per-user Run key, so no admin rights are needed and the user can
/// also turn it off from Task Manager → Startup apps.
class IoStartupService implements StartupService {
  static const _key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'DriveSync';

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final r = await Process.run('reg', ['query', _key, '/v', _name]);
    return r.exitCode == 0;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    final args = enabled
        ? [
            'add',
            _key,
            '/v',
            _name,
            '/t',
            'REG_SZ',
            '/d',
            '"${Platform.resolvedExecutable}"',
            '/f',
          ]
        : ['delete', _key, '/v', _name, '/f'];
    final r = await Process.run('reg', args);
    if (r.exitCode != 0) {
      throw ProcessException('reg', args, '${r.stderr}'.trim(), r.exitCode);
    }
  }
}
