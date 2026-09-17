import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'services/offline_cache.dart';
import 'services/settings_service.dart';
import 'ui/home_shell.dart';
import 'ui/splash_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.load();
  final cache = await OfflineCache.load();
  runApp(DriveSyncApp(settings: settings, cache: cache));
}

class DriveSyncApp extends StatelessWidget {
  const DriveSyncApp({super.key, required this.settings, required this.cache});

  final SettingsService settings;
  final OfflineCache cache;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState(settings: settings, cache: cache)..init(),
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'DriveSync',
          debugShowCheckedModeBanner: false,
          theme: buildDriveSyncTheme(Brightness.light),
          darkTheme: buildDriveSyncTheme(Brightness.dark),
          themeMode: switch (settings.value.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          home: const HomeShell(),
        ),
      ),
    );
  }
}
