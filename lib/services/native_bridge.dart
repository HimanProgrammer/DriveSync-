import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/sim_models.dart';
import '../models/storage_models.dart';

/// Thin wrapper over the Android platform channel. Every call degrades to a
/// safe empty answer on platforms (and web) where the channel is absent, so
/// callers never have to branch on the host OS.
class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _channel = MethodChannel('drivesync/native');

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<List<VolumeInfo>> volumes() async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getVolumes');
      return (raw ?? const []).map(VolumeInfo.fromMap).toList();
    } on PlatformException catch (e) {
      debugPrint('DriveSync: getVolumes failed: ${e.message}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<String>> readableRoots() async {
    if (!_supported) return const [];
    try {
      return await _channel.invokeListMethod<String>('getReadableRoots') ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Reads the subscription list. Returns an unchecked [CarrierOffer] when the
  /// platform cannot tell us (desktop, web, or READ_PHONE_STATE denied) so the
  /// UI can say "not checked" rather than "no Jio".
  Future<CarrierOffer> carrierOffer() async {
    if (!_supported) return const CarrierOffer(sims: [], checked: false);
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getSimInfo');
      if (raw == null) return const CarrierOffer(sims: [], checked: false);
      return CarrierOffer(sims: raw.map(SimInfo.fromMap).toList(), checked: true);
    } on PlatformException catch (e) {
      debugPrint('DriveSync: getSimInfo failed: ${e.message}');
      return const CarrierOffer(sims: [], checked: false);
    } on MissingPluginException {
      return const CarrierOffer(sims: [], checked: false);
    }
  }

  /// Manufacturer + model, used as the Drive subfolder name.
  Future<String> deviceName() async {
    if (!_supported) return '';
    try {
      return await _channel.invokeMethod<String>('getDeviceName') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Asks Android for READ_PHONE_STATE. False when denied or unavailable.
  Future<bool> requestPhonePermission() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPhonePermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks for the storage / media read grants used by the scanner.
  Future<bool> requestStoragePermission() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestStoragePermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
