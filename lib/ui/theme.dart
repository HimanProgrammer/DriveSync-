import 'package:flutter/material.dart';

const kBrandSeed = Color(0xFF1A73E8);

ThemeData buildDriveSyncTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF6F8FB)
        : scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

/// Colour for a fullness bar: green while there is room, amber when it is
/// getting tight, red once offloading is genuinely overdue.
Color fullnessColor(ColorScheme scheme, double fraction) {
  if (fraction >= 0.90) return scheme.error;
  if (fraction >= 0.75) return const Color(0xFFF9AB00);
  return const Color(0xFF1E8E3E);
}
