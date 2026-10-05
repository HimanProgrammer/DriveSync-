import 'package:drivesync/services/storage_service_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone internal storage is used', () {
    for (final p in [
      '/storage/emulated/0',
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/Download',
      '/sdcard/Pictures',
      '/data/user/0/com.drivesync.drivesync/files',
    ]) {
      expect(isAndroidInternalPath(p), isTrue, reason: p);
    }
  });

  test('SD cards and USB drives are left alone', () {
    for (final p in [
      '/storage/1A2B-3C4D',
      '/storage/1A2B-3C4D/DCIM',
      '/storage/usbotg/Movies',
      '/mnt/media_rw/1A2B-3C4D',
    ]) {
      expect(isAndroidInternalPath(p), isFalse, reason: p);
    }
  });
}
