import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../services/settings_service.dart';

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
                secondary: Icon(s.isAuto ? Icons.autorenew : Icons.pan_tool_alt_outlined),
              ),
              const Divider(height: 1),
              SegmentedButtonRow(
                mode: s.mode,
                onChanged: settings.setMode,
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
              SwitchListTile(
                value: s.wifiOnly,
                onChanged: (v) => settings.update(s.copyWith(wifiOnly: v)),
                title: const Text('Upload on Wi-Fi / unmetered networks only'),
                subtitle: const Text(
                  'Keeps automatic backups off your mobile data allowance.',
                ),
              ),
              SwitchListTile(
                value: s.deleteLocalAfterUpload,
                onChanged: (v) => v
                    ? _confirmDelete(context, settings, s)
                    : settings.update(s.copyWith(deleteLocalAfterUpload: false)),
                title: const Text('Delete the local copy after upload'),
                subtitle: Text(
                  'Off by default. This permanently removes the local file '
                  'once Drive confirms the upload.',
                  style: TextStyle(color: s.deleteLocalAfterUpload ? scheme.error : null),
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
                  state.link.isOffline ? Icons.cloud_off : Icons.cloud_done_outlined,
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
          'Once a file is confirmed in Drive, DriveSync will delete it from '
          'this device. That cannot be undone from here — the only copy will '
          'be the one in your Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep local copies'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete after upload'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await settings.update(s.copyWith(deleteLocalAfterUpload: true));
    }
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
