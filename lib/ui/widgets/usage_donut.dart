import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/storage_models.dart';
import '../theme.dart';

/// Category breakdown as a donut, with the volume's used/total in the hole.
class UsageDonut extends StatelessWidget {
  const UsageDonut({super.key, required this.volume, this.categories = const []});

  final VolumeInfo volume;
  final List<CategoryUsage> categories;

  static const _palette = <Color>[
    Color(0xFF1A73E8),
    Color(0xFF1E8E3E),
    Color(0xFFF9AB00),
    Color(0xFFD93025),
    Color(0xFF9334E6),
    Color(0xFF12B5CB),
    Color(0xFFE8710A),
    Color(0xFF5F6368),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBreakdown = categories.isNotEmpty;

    // Before a scan we still know used vs free from the OS, so show that.
    final sections = hasBreakdown
        ? [
            for (var i = 0; i < categories.length; i++)
              PieChartSectionData(
                value: categories[i].bytes.toDouble(),
                color: _palette[i % _palette.length],
                radius: 26,
                showTitle: false,
              ),
          ]
        : [
            PieChartSectionData(
              value: volume.usedBytes.toDouble().clamp(1, double.infinity),
              color: fullnessColor(scheme, volume.usedFraction),
              radius: 26,
              showTitle: false,
            ),
            PieChartSectionData(
              value: volume.freeBytes.toDouble().clamp(1, double.infinity),
              color: scheme.surfaceContainerHighest,
              radius: 26,
              showTitle: false,
            ),
          ];

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 62,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    volume.totalBytes == 0
                        ? '—'
                        : '${(volume.usedFraction * 100).round()}%',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    volume.totalBytes == 0
                        ? 'capacity unknown'
                        : '${formatBytes(volume.usedBytes)} of '
                            '${formatBytes(volume.totalBytes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasBreakdown)
          Wrap(
            spacing: 14,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < categories.length; i++)
                _Legend(
                  color: _palette[i % _palette.length],
                  label: categories[i].category.label,
                  value: formatBytes(categories[i].bytes),
                ),
            ],
          )
        else
          Text(
            'Run a scan to see what is using the space.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$label · $value', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
