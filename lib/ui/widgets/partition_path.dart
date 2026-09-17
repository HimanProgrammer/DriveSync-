import 'package:flutter/material.dart';

import '../../models/storage_models.dart';

export '../../models/storage_models.dart' show volumeForPath;

/// A path prefixed with the partition/drive it lives on, e.g.
/// "Local Disk (C:) › Users › me › Videos › clip.mp4" — so it's obvious which
/// physical volume a file will be copied off before or while it's queued.
///
/// When [volume] is null (no scan on hand for this path, e.g. a task queued
/// from a previous session) the raw path is shown instead, since there is
/// nothing to strip a prefix against.
class PartitionPath extends StatelessWidget {
  const PartitionPath({super.key, required this.path, this.volume, this.style});

  final String path;
  final VolumeInfo? volume;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final v = volume;
    final baseStyle = style ?? Theme.of(context).textTheme.bodySmall;
    if (v == null) {
      return Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    var relative = path;
    if (relative.startsWith(v.path)) {
      relative = relative.substring(v.path.length);
    }
    final segments = relative
        .split(RegExp(r'[\\/]+'))
        .where((s) => s.isNotEmpty)
        .toList();

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: v.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          for (final s in segments) ...[
            const TextSpan(text: '  ›  '),
            TextSpan(text: s),
          ],
        ],
      ),
    );
  }
}
