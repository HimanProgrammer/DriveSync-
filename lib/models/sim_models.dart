/// What we learned about the SIM(s) in the device.
class SimInfo {
  const SimInfo({
    required this.carrierName,
    required this.operatorNumeric,
    required this.slotIndex,
    required this.isJio,
  });

  final String carrierName;

  /// MCC+MNC. Reliance Jio India uses MCC 405 with a block of MNCs.
  final String operatorNumeric;
  final int slotIndex;
  final bool isJio;

  factory SimInfo.fromMap(Map<dynamic, dynamic> m) {
    final name = (m['carrierName'] as String? ?? '').trim();
    final numeric = (m['operatorNumeric'] as String? ?? '').trim();
    return SimInfo(
      carrierName: name.isEmpty ? 'Unknown carrier' : name,
      operatorNumeric: numeric,
      slotIndex: (m['slotIndex'] as num?)?.toInt() ?? 0,
      isJio: detectJio(name, numeric),
    );
  }

  /// Jio shows up under several display names ("Jio 4G", "JIO", "RJIO") and a
  /// wide MNC block under India's MCC 405, so we check both signals.
  static bool detectJio(String carrierName, String operatorNumeric) {
    final n = carrierName.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (n.contains('jio') || n.contains('reliance')) return true;
    if (operatorNumeric.startsWith('405')) {
      final mnc = int.tryParse(operatorNumeric.substring(3));
      // 405-840..405-874 and 405-8xx are the Reliance Jio allocations.
      if (mnc != null && mnc >= 800 && mnc <= 899) return true;
    }
    return false;
  }
}

/// Result of the carrier check, including the perk we unlock for Jio users.
class CarrierOffer {
  const CarrierOffer({
    required this.sims,
    required this.checked,
  });

  final List<SimInfo> sims;
  final bool checked;

  SimInfo? get jioSim => sims.where((s) => s.isJio).firstOrNull;
  bool get hasJio => jioSim != null;

  static const geminiProTitle = 'Gemini Pro Pack activated';
  String get geminiProMessage => hasJio
      ? 'Jio SIM detected on slot ${jioSim!.slotIndex + 1} '
          '(${jioSim!.carrierName}). Your Gemini Pro Pack is activated — '
          'DriveSync will use the bundled Drive quota for automatic backups.'
      : 'No Jio SIM detected, so the Gemini Pro Pack offer does not apply to '
          'this device.';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
