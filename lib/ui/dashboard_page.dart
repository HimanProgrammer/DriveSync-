import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import 'widgets/drive_card.dart';
import 'widgets/jio_card.dart';
import 'widgets/usage_donut.dart';
import 'widgets/volume_tile.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    if (state.busy && state.volumes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VolumePicker(state: state),
        const SizedBox(height: 16),
        _ScanCard(state: state),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DriveCard(state: state),
        const SizedBox(height: 16),
        JioCard(offer: state.carrier, onRecheck: state.refreshCarrier),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (state.isOffline) ...[
          const _OfflineBanner(),
          const SizedBox(height: 16),
        ],
        if (state.error != null) ...[
          _ErrorBanner(message: state.error!),
          const SizedBox(height: 16),
        ],
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: left),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: right),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 16), right],
          ),
      ],
    );
  }
}

class _VolumePicker extends StatelessWidget {
  const _VolumePicker({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.volumes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'No storage volumes were reported. On Android, grant the storage '
            'permission; on desktop, check that DriveSync may run PowerShell '
            'to read disk capacity.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Storage on ${state.deviceLabel}',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Refresh volumes',
                  onPressed: state.refreshVolumes,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth > 720 ? 3 : (c.maxWidth > 420 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.3,
                  children: [
                    for (final v in state.volumes)
                      VolumeTile(
                        volume: v,
                        selected: v.id == state.selected?.id,
                        onTap: () => state.selectVolume(v),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final volume = state.selected;
    if (volume == null) return const SizedBox.shrink();
    final scan = state.currentScan;
    final progress = state.progress;
    final scanning = progress != null && !progress.isDone;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(volume.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(volume.path, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            UsageDonut(volume: volume, categories: scan?.categories ?? const []),
            const SizedBox(height: 18),
            if (scanning)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Scanned ${progress.filesSeen} files · '
                    '${formatBytes(progress.bytesSeen)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    progress.currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: state.cancelScan,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop scan'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: state.startScan,
                    icon: const Icon(Icons.search),
                    label: Text(scan == null ? 'Analyse storage' : 'Re-scan'),
                  ),
                  const SizedBox(width: 12),
                  if (scan != null)
                    Expanded(
                      child: Text(
                        '${scan.scannedFiles} files · '
                        '${formatBytes(scan.scannedBytes)} in '
                        '${scan.duration.inSeconds}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            if (scan != null) ...[
              const SizedBox(height: 8),
              Text(
                'Snapshot from '
                '${DateFormat.yMMMd().add_jm().format(scan.takenAt)}'
                '${state.isOffline ? ' · offline, showing saved data' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (scan?.partial == true) ...[
              const SizedBox(height: 12),
              _PartialNotice(scan: scan!),
            ],
          ],
        ),
      ),
    );
  }
}

class _PartialNotice extends StatelessWidget {
  const _PartialNotice({required this.scan});
  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Partial result',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Some locations were not readable or the scan hit its time budget, '
            'so the breakdown below covers less than the whole volume.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (scan.skippedPaths.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              scan.skippedPaths.take(3).join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You are offline. Scanning still works, saved results are shown, '
              'and anything you queue is uploaded automatically once a '
              'connection returns.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
