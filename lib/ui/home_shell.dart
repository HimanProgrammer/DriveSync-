import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'backup_page.dart';
import 'dashboard_page.dart';
import 'files_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'splash_screen.dart';
import 'widgets/auto_mode_dialog.dart';
import 'widgets/delete_confirm_dialog.dart';
import 'widgets/demo_tour.dart';
import 'widgets/drivesync_logo.dart';

/// Adaptive shell: a rail on desktop/tablet, a bottom bar on phones. Same
/// pages everywhere, so the Android app and the web dashboard stay in step.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _promptScheduled = false;
  bool _handlingDeletions = false;

  /// Shown fresh on every launch (no "seen it" flag) — Skip is always visible.
  bool _showTour = true;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.donut_small_outlined),
      selectedIcon: Icon(Icons.donut_small),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Files',
    ),
    NavigationDestination(
      icon: Icon(Icons.cloud_upload_outlined),
      selectedIcon: Icon(Icons.cloud_upload),
      label: 'Backup',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.busy && state.volumes.isEmpty) {
      return const DriveSyncSplash();
    }
    // The auto-mode choice waits until the tour is out of the way so the two
    // overlays never compete for the screen.
    if (!_showTour) _maybePromptForAutoMode(state);
    _maybeShowDeleteConfirmations(state);

    final pages = [
      const DashboardPage(),
      const FilesPage(),
      const BackupPage(),
      const HistoryPage(),
      const SettingsPage(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const DriveSyncLogo(size: 26),
            const SizedBox(width: 10),
            const Text('DriveSync'),
            const SizedBox(width: 12),
            if (wide)
              Text(
                state.deviceLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          _LinkChip(state: state),
          const SizedBox(width: 8),
          _ModeChip(auto: state.settings.value.isAuto),
          const SizedBox(width: 12),
          if (!_showTour)
            IconButton(
              tooltip: 'Show tour again',
              onPressed: () => setState(() => _showTour = true),
              icon: const Icon(Icons.help_outline),
            ),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                  ],
                ),
              Expanded(child: pages[_index]),
            ],
          ),
          if (_showTour)
            DemoTour(
              wide: wide,
              onStepChanged: (i) => setState(() => _index = i),
              onFinished: () => setState(() => _showTour = false),
            ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
    );
  }

  /// Auto mode is opt-in and the choice is asked for exactly once, before any
  /// file is uploaded — never silently enabled.
  void _maybePromptForAutoMode(AppState state) {
    if (_promptScheduled || state.busy || !state.needsAutoModePrompt) return;
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showAutoModeDialog(context, state);
    });
  }

  /// Runs the Delete/Keep popup loop as soon as an upload lands in
  /// pendingDeletions. Guarded so a rebuild while the loop is already running
  /// (e.g. another file finishing uploading) doesn't start a second one.
  void _maybeShowDeleteConfirmations(AppState state) {
    if (_handlingDeletions || state.sync.pendingDeletions.isEmpty) return;
    _handlingDeletions = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _handlingDeletions = false;
        return;
      }
      await maybeShowDeleteConfirmations(context, state);
      _handlingDeletions = false;
    });
  }
}

/// Offline / mobile-data / online, so it is always obvious why an upload is
/// waiting rather than running.
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offline = state.link.isOffline;
    final metered = state.link.isMetered;
    return Tooltip(
      message: offline
          ? 'Offline — showing saved results. Uploads resume automatically.'
          : metered
          ? 'On mobile data'
          : 'Online',
      child: Chip(
        avatar: Icon(
          offline
              ? Icons.cloud_off
              : metered
              ? Icons.signal_cellular_alt
              : Icons.wifi,
          size: 18,
          color: offline ? scheme.onErrorContainer : scheme.onSurfaceVariant,
        ),
        label: Text(state.link.label),
        backgroundColor: offline
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest,
        side: BorderSide.none,
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.auto});
  final bool auto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        auto ? Icons.autorenew : Icons.pan_tool_alt_outlined,
        size: 18,
        color: auto ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      label: Text(auto ? 'Auto' : 'Manual'),
      backgroundColor: auto
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      side: BorderSide.none,
    );
  }
}
