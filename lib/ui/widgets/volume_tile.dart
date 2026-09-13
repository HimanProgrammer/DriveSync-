import 'package:flutter/material.dart';

import '../../models/storage_models.dart';
import '../theme.dart';

class VolumeTile extends StatelessWidget {
  const VolumeTile({
    super.key,
    required this.volume,
    required this.selected,
    required this.onTap,
  });

  final VolumeInfo volume;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = volume.totalBytes > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  volume.isRemovable ? Icons.usb : Icons.storage_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    volume.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (volume.isCritical)
                  Icon(Icons.error_outline, size: 18, color: scheme.error),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: known ? volume.usedFraction : null,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: fullnessColor(scheme, volume.usedFraction),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              known
                  ? '${formatBytes(volume.freeBytes)} free of '
                      '${formatBytes(volume.totalBytes)}'
                  : 'Capacity not reported by the OS',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
