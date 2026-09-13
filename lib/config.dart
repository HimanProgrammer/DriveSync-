/// OAuth client identifiers for DriveSync.
///
/// Create these in the Google Cloud console (APIs & Services -> Credentials)
/// for a project with the **Google Drive API** enabled, then either edit the
/// defaults below or pass them at build time:
///
///   flutter build web    --dart-define=DV_WEB_CLIENT_ID=...
///   flutter build windows --dart-define=DV_DESKTOP_CLIENT_ID=... \
///                         --dart-define=DV_DESKTOP_CLIENT_SECRET=...
///
/// Android needs no id here: it is matched by package name + SHA-1 in the
/// console, so only `android/app/google-services`-style registration applies.
class DriveConfig {
  /// OAuth 2.0 client of type "Web application". Authorised JavaScript origin
  /// must include the origin you serve the dashboard from.
  ///
  /// No default is baked in here on purpose — OAuth client ids/secrets must
  /// never be committed to source control. Always pass them at build time.
  static const webClientId = String.fromEnvironment('DV_WEB_CLIENT_ID');

  /// OAuth 2.0 client of type "Desktop app" — used for the loopback flow that
  /// Windows sign-in needs (a Web application client cannot do this: Google
  /// requires an exact pre-registered redirect URI for that type, and the
  /// desktop flow picks a random local port each run).
  static const desktopClientId = String.fromEnvironment('DV_DESKTOP_CLIENT_ID');

  /// Desktop client secret. Not a secret in the usual sense: installed-app
  /// clients are public, which is why the flow also requires the loopback
  /// redirect. Even so, never commit this to source control — always supply
  /// it via --dart-define=DV_DESKTOP_CLIENT_SECRET=... (e.g. from a local,
  /// git-ignored script) rather than editing a default in here.
  static const desktopClientSecret =
      String.fromEnvironment('DV_DESKTOP_CLIENT_SECRET');

  /// `drive.file` is the narrow scope: DriveSync can only see and manage the
  /// files it created itself, which is all an offload tool needs.
  static const scopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
  ];

  static bool get isConfigured =>
      webClientId.isNotEmpty && desktopClientId.isNotEmpty;

  /// Root folder created in the user's Drive; per-device subfolders live here.
  static const rootFolderName = 'DriveSync';
}
