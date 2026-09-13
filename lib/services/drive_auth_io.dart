import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'drive_auth.dart';
import 'drive_auth_web.dart';

DriveAuth createDriveAuth() {
  // Android has Play Services, so reuse the Google Sign-In path there and keep
  // the loopback browser flow for desktop only.
  if (defaultTargetPlatform == TargetPlatform.android) {
    return GoogleSignInAuth(clientId: null);
  }
  return DesktopDriveAuth();
}

/// Desktop OAuth using the installed-app loopback flow: we open the system
/// browser, googleapis_auth listens on 127.0.0.1 for the redirect, and the
/// resulting refresh token is cached so later launches are silent.
class DesktopDriveAuth implements DriveAuth {
  DriveAccount? _account;
  http.Client? _base;

  @override
  DriveAccount? get account => _account;

  auth_io.ClientId get _clientId => auth_io.ClientId(
        DriveConfig.desktopClientId,
        DriveConfig.desktopClientSecret,
      );

  File get _credentialsFile {
    final home = Platform.environment['APPDATA'] ??
        Platform.environment['XDG_CONFIG_HOME'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return File(p.join(home, 'DriveSync', 'credentials.json'));
  }

  @override
  Future<AuthClient?> signInSilently() async {
    final file = _credentialsFile;
    if (!file.existsSync()) return null;
    try {
      final stored = AccessCredentials.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      if (stored.refreshToken == null) return null;
      _base = http.Client();
      final client = auth_io.autoRefreshingClient(_clientId, stored, _base!);
      client.credentialUpdates.listen(_persist);
      await _loadProfile(client);
      return client;
    } catch (e) {
      debugPrint('DriveSync: cached desktop credentials unusable ($e); '
          'removing so the next sign-in is interactive.');
      await file.delete().catchError((_) => file);
      return null;
    }
  }

  @override
  Future<AuthClient?> signIn() async {
    if (DriveConfig.desktopClientId.startsWith('REPLACE_')) {
      throw DriveAuthException(
        'No desktop OAuth client configured. Build with '
        '--dart-define=DV_DESKTOP_CLIENT_ID=... and '
        '--dart-define=DV_DESKTOP_CLIENT_SECRET=... (see lib/config.dart).',
      );
    }
    _base = http.Client();
    try {
      final client = await auth_io.clientViaUserConsent(
        _clientId,
        DriveConfig.scopes,
        (url) async {
          final uri = Uri.parse(url);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw DriveAuthException(
              'Could not open the browser for Google sign-in. Visit this URL '
              'manually to continue:\n$url',
            );
          }
        },
        baseClient: _base,
      );
      await _persist(client.credentials);
      client.credentialUpdates.listen(_persist);
      await _loadProfile(client);
      return client;
    } on auth_io.UserConsentException catch (e) {
      throw DriveAuthException('Google sign-in was cancelled or denied: ${e.message}');
    }
  }

  Future<void> _persist(AccessCredentials c) async {
    final file = _credentialsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(c.toJson()), flush: true);
  }

  Future<void> _loadProfile(AuthClient client) async {
    try {
      final r = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      if (r.statusCode != 200) {
        _account = const DriveAccount(email: 'signed in', displayName: 'Google account');
        return;
      }
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      _account = DriveAccount(
        email: m['email'] as String? ?? 'signed in',
        displayName: m['name'] as String? ?? m['email'] as String? ?? 'Google account',
        photoUrl: m['picture'] as String?,
      );
    } catch (_) {
      // userinfo needs the profile scope; absence of it is not fatal.
      _account = const DriveAccount(email: 'signed in', displayName: 'Google account');
    }
  }

  @override
  Future<void> signOut() async {
    final file = _credentialsFile;
    if (file.existsSync()) await file.delete();
    _base?.close();
    _base = null;
    _account = null;
  }
}
