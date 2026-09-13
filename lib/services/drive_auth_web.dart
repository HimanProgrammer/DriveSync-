import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' show AuthClient;

import '../config.dart';
import 'drive_auth.dart';

DriveAuth createDriveAuth() => GoogleSignInAuth();

/// Web (and Android) auth: Google Sign-In hands us an [AuthClient] via the
/// googleapis_auth extension, so token refresh is handled for us.
class GoogleSignInAuth implements DriveAuth {
  GoogleSignInAuth({String? clientId})
      : _signIn = GoogleSignIn(
          clientId: clientId ?? DriveConfig.webClientId,
          scopes: DriveConfig.scopes,
        );

  final GoogleSignIn _signIn;
  DriveAccount? _account;

  @override
  DriveAccount? get account => _account;

  @override
  Future<AuthClient?> signInSilently() =>
      _clientFor(() => _signIn.signInSilently());

  @override
  Future<AuthClient?> signIn() => _clientFor(() => _signIn.signIn());

  Future<AuthClient?> _clientFor(
    Future<GoogleSignInAccount?> Function() step,
  ) async {
    final user = await step();
    if (user == null) return null;

    // On web the sign-in itself does not imply the Drive scope was granted.
    if (!await _signIn.canAccessScopes(DriveConfig.scopes)) {
      if (!await _signIn.requestScopes(DriveConfig.scopes)) {
        throw DriveAuthException(
          'DriveSync needs permission to manage the files it creates in your '
          'Drive. Sign-in succeeded but the Drive scope was declined.',
        );
      }
    }

    final client = await _signIn.authenticatedClient();
    if (client == null) {
      throw DriveAuthException('Google returned no access token for this session.');
    }
    _account = DriveAccount(
      email: user.email,
      displayName: user.displayName ?? user.email,
      photoUrl: user.photoUrl,
    );
    return client;
  }

  @override
  Future<void> signOut() async {
    await _signIn.disconnect().catchError((_) {});
    await _signIn.signOut();
    _account = null;
  }
}
