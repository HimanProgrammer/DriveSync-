import 'startup_service.dart';

StartupService createStartupService() => _UnsupportedStartupService();

class _UnsupportedStartupService implements StartupService {
  @override
  bool get isSupported => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}
}
