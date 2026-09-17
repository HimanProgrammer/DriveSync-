import 'power_service.dart';

PowerService createPowerService() => WebPowerService();

class WebPowerService implements PowerService {
  @override
  bool get canShutdown => false;

  @override
  Future<void> scheduleShutdown(Duration delay) async {
    throw UnsupportedError('Shutdown is not available in the browser.');
  }

  @override
  Future<void> cancelShutdown() async {}
}
