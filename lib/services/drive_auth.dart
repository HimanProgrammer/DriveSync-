import 'package:googleapis_auth/googleapis_auth.dart' show AuthClient;

import 'drive_auth_web.dart' if (dart.library.io) 'drive_auth_io.dart';

class DriveAccount {
  const DriveAccount({required this.email, required this.displayName, this.photoUrl});
  final String email;
  final String displayName;
  final String? photoUrl;
}

class DriveAuthException implements Exception {
  DriveAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class DriveAuth {
  factory DriveAuth() => createDriveAuth();

  /// Restores a session without showing UI. Null when there is none.
  Future<AuthClient?> signInSilently();

  /// Shows the consent screen / account chooser.
  Future<AuthClient?> signIn();

  Future<void> signOut();

  /// The account behind the most recent successful sign-in.
  DriveAccount? get account;
}
