import 'package:flutter/material.dart';

import 'widgets/drivesync_logo.dart';

/// The in-Flutter boot screen shown while [AppState.init] runs. The native
/// splash (flutter_native_splash) covers the gap before the engine starts;
/// this covers the gap between engine start and the first real frame, so the
/// animated mark is on screen for the entire cold start rather than flashing
/// in only at the very end.
class DriveSyncSplash extends StatelessWidget {
  const DriveSyncSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimatedDriveSyncLogo(size: 120),
            const SizedBox(height: 28),
            Text(
              'DriveSync',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Simple. Secure. Synced.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
