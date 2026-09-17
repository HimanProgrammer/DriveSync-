import 'package:flutter/material.dart';

enum FileSortKey { name, size, date, partition }

extension FileSortKeyLabel on FileSortKey {
  String get label => switch (this) {
    FileSortKey.name => 'Name',
    FileSortKey.size => 'File size',
    FileSortKey.date => 'Date modified',
    FileSortKey.partition => 'Partition',
  };

  /// What ascending vs. descending actually means for this key, so the
  /// direction control reads as "Small to big" rather than a bare arrow.
  String directionLabel(bool descending) => switch (this) {
    FileSortKey.size => descending ? 'Big to small' : 'Small to big',
    FileSortKey.date => descending ? 'Newest to oldest' : 'Oldest to newest',
    FileSortKey.name => descending ? 'Z to A' : 'A to Z',
    FileSortKey.partition => descending ? 'Z to A' : 'A to Z',
  };
}

/// One level of a sort — [key] to compare by, [descending] for its direction.
class SortLevel {
  const SortLevel(this.key, {this.descending = false});
  final FileSortKey key;
  final bool descending;

  SortLevel copyWith({FileSortKey? key, bool? descending}) =>
      SortLevel(key ?? this.key, descending: descending ?? this.descending);
}

/// "Sort: <primary> [asc/desc]  then: <secondary> [asc/desc]" — a primary key
/// plus an optional secondary key that breaks ties within the primary, e.g.
/// group by Partition, then order each partition's files by File size.
class FileSortControl extends StatelessWidget {
  const FileSortControl({
    super.key,
    required this.primary,
    required this.secondary,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
  });

  final SortLevel primary;

  /// Null means "no secondary sort — just fall back to Name for a stable
  /// order", shown in the dropdown as "then: None".
  final SortLevel? secondary;
  final ValueChanged<SortLevel> onPrimaryChanged;
  final ValueChanged<SortLevel?> onSecondaryChanged;

  @override
  Widget build(BuildContext context) {
    // A secondary sort on the same key as the primary has nothing left to
    // break ties on, and — since the key list below excludes primary.key —
    // would leave this dropdown holding a value with no matching item, which
    // Flutter treats as a fatal assertion. Treat that combination as "None"
    // defensively, on top of both callers already avoiding it.
    final effectiveSecondary = secondary?.key == primary.key ? null : secondary;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 4,
      children: [
        DropdownButton<FileSortKey>(
          value: primary.key,
          underline: const SizedBox.shrink(),
          onChanged: (v) =>
              v == null ? null : onPrimaryChanged(primary.copyWith(key: v)),
          items: [
            for (final k in FileSortKey.values)
              DropdownMenuItem(value: k, child: Text('Sort: ${k.label}')),
          ],
        ),
        DropdownButton<bool>(
          value: primary.descending,
          underline: const SizedBox.shrink(),
          onChanged: (v) => v == null
              ? null
              : onPrimaryChanged(primary.copyWith(descending: v)),
          items: [
            DropdownMenuItem(
              value: false,
              child: Text(primary.key.directionLabel(false)),
            ),
            DropdownMenuItem(
              value: true,
              child: Text(primary.key.directionLabel(true)),
            ),
          ],
        ),
        DropdownButton<FileSortKey?>(
          value: effectiveSecondary?.key,
          underline: const SizedBox.shrink(),
          onChanged: (v) => onSecondaryChanged(v == null ? null : SortLevel(v)),
          items: [
            const DropdownMenuItem(value: null, child: Text('then: None')),
            for (final k in FileSortKey.values)
              if (k != primary.key)
                DropdownMenuItem(value: k, child: Text('then: ${k.label}')),
          ],
        ),
        if (effectiveSecondary != null)
          DropdownButton<bool>(
            value: effectiveSecondary.descending,
            underline: const SizedBox.shrink(),
            onChanged: (v) => v == null
                ? null
                : onSecondaryChanged(
                    effectiveSecondary.copyWith(descending: v),
                  ),
            items: [
              DropdownMenuItem(
                value: false,
                child: Text(effectiveSecondary.key.directionLabel(false)),
              ),
              DropdownMenuItem(
                value: true,
                child: Text(effectiveSecondary.key.directionLabel(true)),
              ),
            ],
          ),
      ],
    );
  }
}

/// Sorts anything reducible to a name/size/date/partition-label tuple, first
/// by [primary] then — for anything still tied — by [secondary]. A final tie
/// always falls back to Name, so the order stays stable rather than jumping
/// around on every rebuild.
List<T> sortByFileKey<T>({
  required List<T> items,
  required SortLevel primary,
  SortLevel? secondary,
  required String Function(T) name,
  required int Function(T) bytes,
  required DateTime Function(T) date,
  required String Function(T) partitionLabel,
}) {
  int compareBy(FileSortKey key, T a, T b) => switch (key) {
    FileSortKey.name => name(a).toLowerCase().compareTo(name(b).toLowerCase()),
    FileSortKey.size => bytes(a).compareTo(bytes(b)),
    FileSortKey.date => date(a).compareTo(date(b)),
    FileSortKey.partition => partitionLabel(
      a,
    ).toLowerCase().compareTo(partitionLabel(b).toLowerCase()),
  };

  int applyLevel(SortLevel level, T a, T b) {
    final r = compareBy(level.key, a, b);
    return level.descending ? -r : r;
  }

  final sorted = [...items];
  sorted.sort((a, b) {
    final byPrimary = applyLevel(primary, a, b);
    if (byPrimary != 0) return byPrimary;

    if (secondary != null) {
      final bySecondary = applyLevel(secondary, a, b);
      if (bySecondary != 0) return bySecondary;
    }

    if (primary.key == FileSortKey.name) return 0;
    return name(a).toLowerCase().compareTo(name(b).toLowerCase());
  });
  return sorted;
}
