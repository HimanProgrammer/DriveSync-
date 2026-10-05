import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../services/settings_service.dart';
import '../services/startup_service.dart';
import 'sync_folder_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final s = settings.value;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Column(
            children: [
              // The headline control: Auto vs Manual.
              SwitchListTile(
                value: s.isAuto,
                onChanged: (on) =>
                    settings.setMode(on ? SyncMode.auto : SyncMode.manual),
                title: const Text('Auto mode'),
                subtitle: Text(
                  s.isAuto
                      ? 'DriveSync offloads large, older files to Drive by '
                            'itself once a volume passes '
                            '${(s.triggerFraction * 100).round()}% full.'
                      : 'Manual: files are only uploaded when you press '
                            '"Back up now".',
                ),
                secondary: Icon(
                  s.isAuto ? Icons.autorenew : Icons.pan_tool_alt_outlined,
                ),
              ),
              const Divider(height: 1),
              SegmentedButtonRow(mode: s.mode, onChanged: settings.setMode),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Appearance'),
            subtitle: Text(switch (s.themeMode) {
              AppThemeMode.system => 'Follows your device setting.',
              AppThemeMode.light => 'Light, regardless of device setting.',
              AppThemeMode.dark => 'Dark, regardless of device setting.',
            }),
            trailing: DropdownButton<AppThemeMode>(
              value: s.themeMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: AppThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: AppThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(value: AppThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (m) =>
                  m == null ? null : settings.update(s.copyWith(themeMode: m)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('When Auto mode runs'),
              ),
              ListTile(
                title: const Text('Trigger at fullness'),
                subtitle: Slider(
                  value: s.triggerFraction,
                  min: 0.5,
                  max: 0.98,
                  divisions: 24,
                  label: '${(s.triggerFraction * 100).round()}%',
                  onChanged: (v) =>
                      settings.update(s.copyWith(triggerFraction: v)),
                ),
                trailing: Text('${(s.triggerFraction * 100).round()}%'),
              ),
              ListTile(
                title: const Text('Smallest file to offload'),
                subtitle: Slider(
                  value: (s.minFileBytes / (1024 * 1024)).clamp(1, 2048),
                  min: 1,
                  max: 2048,
                  divisions: 32,
                  label: formatBytes(s.minFileBytes),
                  onChanged: (mb) => settings.update(
                    s.copyWith(minFileBytes: (mb * 1024 * 1024).round()),
                  ),
                ),
                trailing: Text(formatBytes(s.minFileBytes)),
              ),
              ListTile(
                title: const Text('Simultaneous uploads'),
                subtitle: Text(
                  s.maxConcurrentUploads == 1
                      ? 'One file at a time.'
                      : 'Up to ${s.maxConcurrentUploads} files uploading at once.',
                ),
                trailing: DropdownButton<int>(
                  value: s.maxConcurrentUploads,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final n in [1, 2, 3, 4, 5, 6])
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (n) => n == null
                      ? null
                      : settings.update(s.copyWith(maxConcurrentUploads: n)),
                ),
              ),
              const _StartupTile(),
              const _FloatingAgentTile(),
              SwitchListTile(
                value: s.wifiOnly,
                onChanged: (v) => settings.update(s.copyWith(wifiOnly: v)),
                title: const Text('Upload on Wi-Fi / unmetered networks only'),
                subtitle: const Text(
                  'Keeps automatic backups off your mobile data allowance.',
                ),
              ),
              if (!s.wifiOnly)
                _MobileDataLimitTile(state: state, settings: settings, s: s),
              if (!state.sync.canDeleteLocalFiles)
                ListTile(
                  leading: Icon(Icons.shield_outlined, color: scheme.primary),
                  title: const Text('Check uploaded, then delete the file'),
                  subtitle: const Text(
                    'Not available — DriveSync never deletes files or '
                    'folders on this device, on any platform. Backed-up '
                    'files stay right where they are in addition to the '
                    'copy now in Drive.',
                  ),
                )
              else ...[
                SwitchListTile(
                  value: s.deleteLocalAfterUpload,
                  onChanged: (v) => v
                      ? _confirmDelete(context, settings, s)
                      : settings.update(
                          s.copyWith(deleteLocalAfterUpload: false),
                        ),
                  title: const Text('Check uploaded, then delete the file'),
                  subtitle: Text(
                    'Off by default. Once Drive confirms a file was received, '
                    'DriveSync notifies you and offers to remove the local copy.',
                    style: TextStyle(
                      color: s.deleteLocalAfterUpload ? scheme.error : null,
                    ),
                  ),
                ),
                if (s.deleteLocalAfterUpload)
                  const ListTile(
                    leading: Icon(Icons.notifications_active_outlined),
                    title: Text('You always approve deletes'),
                    subtitle: Text(
                      'After uploading, DriveSync sends a notification and '
                      'waits. Nothing is deleted until you tap Delete. System '
                      'and program files are never deleted.',
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                value: s.autoMobileBackup,
                onChanged: (v) =>
                    settings.update(s.copyWith(autoMobileBackup: v)),
                title: const Text('Auto Mobile Backup'),
                subtitle: const Text(
                  'Sweep the camera roll every 10 minutes and send new photos '
                  'and videos to Drive. Uploads wait for an allowed connection.',
                ),
                secondary: const Icon(Icons.photo_camera_back_outlined),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Last media check'),
                subtitle: Text(
                  state.media.lastCheck == null
                      ? 'Not run yet on this device.'
                      : '${state.media.status ?? ''} '
                            '(${state.media.lastFoundCount} found)',
                ),
                trailing: TextButton(
                  onPressed: state.checkForNewMedia,
                  child: const Text('Check now'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  state.link.isOffline
                      ? Icons.cloud_off
                      : Icons.cloud_done_outlined,
                ),
                title: const Text('Connection'),
                subtitle: Text(
                  state.link.isOffline
                      ? 'Offline. Scans, saved results and queueing all still '
                            'work; uploads resume by themselves.'
                      : '${state.link.label} — automatic uploads '
                            '${state.link.canUpload(wifiOnly: s.wifiOnly).allowed ? 'allowed' : 'held back'}.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('File types to offload'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in FileCategory.values)
                      FilterChip(
                        label: Text(c.label),
                        selected: s.categories.contains(c),
                        onSelected: (on) {
                          final next = {...s.categories};
                          on ? next.add(c) : next.remove(c);
                          settings.update(s.copyWith(categories: next));
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (state.syncFolder.isSupported) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.sync,
                color: state.syncFolder.enabled ? scheme.primary : null,
              ),
              title: const Text('Sync Folder'),
              subtitle: Text(
                state.syncFolder.enabled
                    ? 'On — mirroring ${state.syncFolder.localPath} with '
                          'Drive, deletions included.'
                    : 'Off — a OneDrive-style two-way mirror between one '
                          'local folder and Drive.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Sync Folder')),
                    body: const SyncFolderPage(),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('This device'),
                subtitle: Text(state.deviceLabel),
              ),
              ListTile(
                leading: const Icon(Icons.sim_card_outlined),
                title: const Text('Carrier check'),
                subtitle: Text(
                  state.carrier.checked
                      ? state.carrier.geminiProMessage
                      : 'Not checked on this platform.',
                ),
                trailing: TextButton(
                  onPressed: state.refreshCarrier,
                  child: const Text('Re-check'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SettingsService settings,
    Settings s,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete local files after upload?'),
        content: const Text(
          'Once Drive confirms a file was received, DriveSync will ask — with '
          'a popup, Delete or Keep — whether to remove that file from this '
          'device. You can turn off the popup and delete automatically '
          'instead, in the setting right below this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep local copies'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await settings.update(
        s.copyWith(deleteLocalAfterUpload: true, confirmBeforeDelete: true),
      );
    }
  }
}

/// Only shown once "Wi-Fi only" is off — a byte budget for the metered
/// uploads that setting now allows, so "I don't mind mobile data" doesn't
/// have to mean "unlimited mobile data".
class _MobileDataLimitTile extends StatelessWidget {
  const _MobileDataLimitTile({
    required this.state,
    required this.settings,
    required this.s,
  });

  final AppState state;
  final SettingsService settings;
  final Settings s;

  static const _optionsMb = [0, 100, 250, 500, 1024, 2048, 5120];

  String _labelFor(int mb) {
    if (mb == 0) return 'No limit';
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(mb % 1024 == 0 ? 0 : 1)} GB'
        : '$mb MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final used = state.sync.meteredBytesUsedThisCycle;
    final exceeded = state.sync.mobileDataLimitExceeded;

    return Column(
      children: [
        ListTile(
          title: const Text('Mobile data limit'),
          subtitle: Text(
            s.mobileDataLimitMb == 0
                ? 'DriveSync will use as much mobile data as needed.'
                : '${formatBytes(used)} used this month of '
                      '${_labelFor(s.mobileDataLimitMb)}.',
            style: TextStyle(color: exceeded ? scheme.error : null),
          ),
          trailing: DropdownButton<int>(
            value: s.mobileDataLimitMb,
            underline: const SizedBox.shrink(),
            items: [
              for (final mb in _optionsMb)
                DropdownMenuItem(value: mb, child: Text(_labelFor(mb))),
            ],
            onChanged: (mb) => mb == null
                ? null
                : settings.update(s.copyWith(mobileDataLimitMb: mb)),
          ),
        ),
        if (s.mobileDataLimitMb > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (used / (s.mobileDataLimitMb * 1024 * 1024)).clamp(
                        0,
                        1,
                      ),
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: exceeded ? scheme.error : scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _confirmReset(context),
                  child: const Text('Reset counter'),
                ),
              ],
            ),
          ),
        if (exceeded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Limit reached — new uploads over mobile data are held '
                    'back until Wi-Fi returns, the month rolls over, or you '
                    'raise the limit above.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset mobile data counter?'),
        content: const Text(
          'This zeroes this month\'s usage count immediately, without '
          'waiting for the calendar to roll over. It does not affect '
          'anything already uploaded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) await state.sync.resetMobileDataUsage();
  }
}

/// The explicit Auto / Manual pair, for people who want to see both options
/// rather than reason about which way a switch points.
class SegmentedButtonRow extends StatelessWidget {
  const SegmentedButtonRow({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final SyncMode mode;
  final ValueChanged<SyncMode> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: SegmentedButton<SyncMode>(
      segments: const [
        ButtonSegment(
          value: SyncMode.auto,
          icon: Icon(Icons.autorenew),
          label: Text('Auto'),
        ),
        ButtonSegment(
          value: SyncMode.manual,
          icon: Icon(Icons.pan_tool_alt_outlined),
          label: Text('Manual'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (sel) => onChanged(sel.first),
    ),
  );
}

/// "Start with Windows" toggle. Hidden on platforms that don't support it.
class _StartupTile extends StatefulWidget {
  const _StartupTile();

  @override
  State<_StartupTile> createState() => _StartupTileState();
}

class _StartupTileState extends State<_StartupTile> {
  final StartupService _startup = StartupService();
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    if (_startup.isSupported) {
      _startup.isEnabled().then((v) {
        if (mounted) setState(() => _enabled = v);
      });
    }
  }

  Future<void> _toggle(bool v) async {
    try {
      await _startup.setEnabled(v);
      if (mounted) setState(() => _enabled = v);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change startup setting: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_startup.isSupported) return const SizedBox.shrink();
    return SwitchListTile(
      value: _enabled ?? false,
      onChanged: _enabled == null ? null : _toggle,
      title: const Text('Start DriveSync when Windows starts'),
      subtitle: const Text(
        'Keeps the agent running so auto-backup and the daily backup happen '
        'without opening the app.',
      ),
    );
  }
}

/// Android: show the DriveSync Agent floating over other apps.
class _FloatingAgentTile extends StatefulWidget {
  const _FloatingAgentTile();

  @override
  State<_FloatingAgentTile> createState() => _FloatingAgentTileState();
}

class _FloatingAgentTileState extends State<_FloatingAgentTile> {
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    if (_supported) {
      FlutterOverlayWindow.isActive().then((v) {
        if (mounted) setState(() => _active = v);
      });
    }
  }

  Future<void> _toggle(bool on) async {
    if (!on) {
      await FlutterOverlayWindow.closeOverlay();
      if (mounted) setState(() => _active = false);
      return;
    }
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      final granted = await FlutterOverlayWindow.requestPermission() ?? false;
      if (!granted) return;
    }
    await FlutterOverlayWindow.showOverlay(
      height: 520,
      width: 600,
      alignment: OverlayAlignment.bottomRight,
      enableDrag: true,
      positionGravity: PositionGravity.auto,
      overlayTitle: 'DriveSync Agent',
      overlayContent: 'Watching your backups',
      flag: OverlayFlag.defaultFlag,
    );
    await FlutterOverlayWindow.shareData({
      'app': 'Agent',
      'text': "Hi! I'll float here and keep you posted.",
    });
    if (mounted) setState(() => _active = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return SwitchListTile(
      value: _active,
      onChanged: _toggle,
      title: const Text('Floating agent over other apps'),
      subtitle: const Text(
        'The DriveSync Agent floats on your screen and tells you about '
        'backups. Drag to move, tap to hear status, long-press to close.',
      ),
    );
  }
}
