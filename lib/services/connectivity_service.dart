import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum LinkState {
  offline,

  /// Mobile data / metered link.
  metered,

  /// Wi-Fi, Ethernet, or another connection we treat as unmetered.
  unmetered,
}

/// Tracks whether we have a link at all, and whether it is one the user has
/// allowed automatic uploads on.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  LinkState state = LinkState.unmetered;
  bool get isOffline => state == LinkState.offline;
  bool get isMetered => state == LinkState.metered;

  Future<void> start() async {
    _apply(await _connectivity.checkConnectivity());
    _sub = _connectivity.onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    final next = _classify(results);
    if (next == state) return;
    state = next;
    notifyListeners();
  }

  LinkState _classify(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return LinkState.offline;
    }
    // A device can report several transports at once; any unmetered one wins.
    const unmetered = {
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.vpn,
    };
    if (results.any(unmetered.contains)) return LinkState.unmetered;
    if (results.contains(ConnectivityResult.mobile)) return LinkState.metered;
    // `other` / bluetooth: assume usable but treat as metered, which is the
    // conservative choice for automatic uploads.
    return LinkState.metered;
  }

  /// Whether an automatic upload may start right now.
  /// [wifiOnly] mirrors the Settings toggle.
  ({bool allowed, String? reason}) canUpload({required bool wifiOnly}) {
    return switch (state) {
      LinkState.offline => (
          allowed: false,
          reason: 'No network connection — queued for when you are back online.',
        ),
      LinkState.metered when wifiOnly => (
          allowed: false,
          reason: 'On mobile data, and uploads are limited to Wi-Fi in Settings.',
        ),
      _ => (allowed: true, reason: null),
    };
  }

  String get label => switch (state) {
        LinkState.offline => 'Offline',
        LinkState.metered => 'Mobile data',
        LinkState.unmetered => 'Online',
      };

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
