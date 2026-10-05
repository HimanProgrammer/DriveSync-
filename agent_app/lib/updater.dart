import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the assistant up to date from the GitHub Releases page: downloads
/// the newest build, then a small PowerShell script waits for this app to
/// close, replaces the files in the app folder and starts it again.
class Updater {
  static const _release =
      'https://api.github.com/repos/HimanProgrammer/DriveSync-/releases/tags/agent-windows-latest';
  static const _kVersion = 'installedBuild';

  /// Returns the new build's id if one is available, else null.
  static Future<String?> check() async {
    if (!Platform.isWindows) return null;
    final prefs = await SharedPreferences.getInstance();
    final info = await _latest();
    if (info == null) return null;
    final installed = prefs.getString(_kVersion);
    if (installed == null) {
      // First run after a manual download: this build is the current one.
      await prefs.setString(_kVersion, info.id);
      return null;
    }
    return installed == info.id ? null : info.id;
  }

  /// Downloads and installs the newest build, then restarts the app.
  /// Returns an error message, or null when the restart has been scheduled.
  static Future<String?> install() async {
    if (!Platform.isWindows) return 'Updates install on Windows only.';
    final info = await _latest();
    if (info == null) return "I couldn't reach GitHub to download the update.";
    final temp = Directory.systemTemp.createTempSync('agent_update_');
    final zip = File('${temp.path}\\update.zip');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(info.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        return 'Download failed (HTTP ${res.statusCode}).';
      }
      await res.pipe(zip.openWrite());
    } catch (e) {
      return 'Download failed: $e';
    } finally {
      client.close();
    }

    final appDir = File(Platform.resolvedExecutable).parent.path;
    final exe = Platform.resolvedExecutable;
    final script = File('${temp.path}\\update.ps1');
    script.writeAsStringSync('''
\$ErrorActionPreference = "Stop"
Wait-Process -Id $pid -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Expand-Archive -Path "${zip.path}" -DestinationPath "$appDir" -Force
Start-Process -FilePath "$exe"
Remove-Item -Recurse -Force "${temp.path}"
''');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVersion, info.id);
    await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
    ], mode: ProcessStartMode.detached);
    return null;
  }

  static Future<({String id, String url})?> _latest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_release));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'drivesync-agent');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = jsonDecode(await utf8.decoder.bind(res).join());
      final asset = (body['assets'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((a) => '${a['name']}'.endsWith('.zip'));
      // The asset's digest changes with every build.
      final id = '${asset['digest'] ?? asset['updated_at']}';
      return (id: id, url: '${asset['browser_download_url']}');
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
