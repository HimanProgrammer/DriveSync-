import 'package:flutter/material.dart';

import '../../app_state.dart';

/// The DriveSync agent character, with a speech bubble describing what the
/// sync is doing right now.
class AgentMascotCard extends StatelessWidget {
  const AgentMascotCard({super.key, required this.state});
  final AppState state;

  String _message() {
    final s = state.sync.status;
    if (state.isOffline) {
      return "You're offline. I'll pick up the backup as soon as you're back.";
    }
    if (!state.isConnected) {
      return 'Hi! Connect Google Drive and I\'ll keep your files backed up.';
    }
    if (s.running) {
      return 'Uploading… ${s.doneCount} done, ${s.pendingCount} to go.';
    }
    if (s.failedCount > 0) {
      return '${s.failedCount} file(s) failed. Check History and I\'ll retry.';
    }
    if (s.pendingCount > 0) {
      return '${s.pendingCount} file(s) are waiting. Tap Back up when ready!';
    }
    if (s.lastRun != null) {
      return 'All caught up! Your files are safe on Google Drive.';
    }
    return 'Ready when you are. Pick a drive and run a scan.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
        child: Row(
          children: [
            Image.asset(
              'assets/branding/agent_mascot.webp',
              height: 110,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DriveSync Agent',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _message(),
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
