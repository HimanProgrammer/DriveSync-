import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/sim_models.dart';

/// The carrier check. On Android we read the SIM subscriptions; a Jio SIM
/// unlocks the Gemini Pro Pack message. Desktop and web have no SIM, so they
/// say so plainly instead of implying the user missed out.
class JioCard extends StatelessWidget {
  const JioCard({super.key, required this.offer, required this.onRecheck});

  final CarrierOffer offer;
  final VoidCallback onRecheck;

  bool get _simCapable => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activated = offer.hasJio;

    final (icon, title, body) = switch ((_simCapable, offer.checked, activated)) {
      (false, _, _) => (
          Icons.desktop_windows_outlined,
          'No SIM on this device',
          'The Jio / Gemini Pro Pack check runs on the Android app. Your '
              'Drive backups here work the same either way.',
        ),
      (true, false, _) => (
          Icons.sim_card_alert_outlined,
          'SIM not checked yet',
          'DriveSync needs the phone-state permission to read your carrier. '
              'Grant it to check for a Jio SIM.',
        ),
      (true, true, true) => (
          Icons.workspace_premium_outlined,
          CarrierOffer.geminiProTitle,
          offer.geminiProMessage,
        ),
      (true, true, false) => (
          Icons.sim_card_outlined,
          'No Jio SIM found',
          offer.sims.isEmpty
              ? 'No active SIM was reported by the device. '
                  '${offer.geminiProMessage}'
              : 'Detected: ${offer.sims.map((s) => s.carrierName).join(', ')}. '
                  '${offer.geminiProMessage}',
        ),
    };

    return Card(
      color: activated ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: activated ? scheme.onPrimaryContainer : scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                  if (_simCapable) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: onRecheck,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(offer.checked ? 'Re-check SIM' : 'Check SIM'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
