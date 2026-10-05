/// The last word on whether DriveSync may delete a local file after it has
/// been uploaded. Deliberately strict: anything that looks like part of
/// Windows, an installed program, a game, developer tooling or app data is
/// never deleted, on any drive, whatever the settings say.
///
/// [siblingNames] are the other file names in the same folder, when known:
/// a folder that holds programs (.exe/.dll) is treated as software.
bool isSafeToDelete(String path, {Iterable<String> siblingNames = const []}) {
  final parts = path
      .split(RegExp(r'[\\/]+'))
      .where((s) => s.isNotEmpty && !RegExp(r'^[A-Za-z]:$').hasMatch(s))
      .map((s) => s.toLowerCase())
      .toList();
  if (parts.isEmpty) return false;
  final name = parts.removeLast();

  // Hidden/system files and anything at a drive root (pagefile.sys, ...).
  if (parts.isEmpty) return false;
  if (name.startsWith('.') || name.startsWith(r'$')) return false;
  if (_protectedNames.contains(name)) return false;

  final dot = name.lastIndexOf('.');
  final ext = dot <= 0 ? '' : name.substring(dot + 1);
  if (_programExtensions.contains(ext)) return false;

  for (final folder in parts) {
    if (_protectedFolders.contains(folder)) return false;
    if (folder.startsWith('.') || folder.startsWith(r'$')) return false;
    if (folder.startsWith('program files')) return false;
  }

  // Unix system locations (desktop builds on macOS/Linux).
  if (path.startsWith('/') &&
      !(parts.isNotEmpty &&
          (parts.first == 'home' || parts.first == 'users'))) {
    return false;
  }

  for (final sibling in siblingNames) {
    final s = sibling.toLowerCase();
    if (s.endsWith('.exe') || s.endsWith('.dll')) return false;
  }
  return true;
}

const _protectedFolders = <String>{
  'windows', 'windows.old', 'programdata', 'appdata', 'recovery', 'boot',
  'efi', 'perflogs', 'msocache', 'system volume information', 'config.msi',
  'drivers', 'system32', 'syswow64', 'winsxs',
  // Games and launchers keep big data files that must stay put.
  'steamapps', 'steamlibrary', 'steam', 'epic games', 'riot games',
  'origin games', 'ea games', 'ubisoft', 'xboxgames', 'windowsapps',
  // Developer tooling.
  'node_modules', 'venv', '.venv', 'site-packages', 'build', '.gradle',
  // Other OSes.
  'library', 'system', 'applications', 'usr', 'bin', 'sbin', 'etc', 'var',
  'opt', 'proc', 'sys', 'dev', 'lib', 'lib64', 'snap',
};

const _protectedNames = <String>{
  'pagefile.sys',
  'hiberfil.sys',
  'swapfile.sys',
  'ntuser.dat',
  'ntuser.dat.log',
  'desktop.ini',
  'thumbs.db',
  'bootmgr',
  'iconcache.db',
};

const _programExtensions = <String>{
  'exe',
  'dll',
  'sys',
  'msi',
  'msix',
  'appx',
  'bat',
  'cmd',
  'ps1',
  'vbs',
  'com',
  'scr',
  'cpl',
  'ocx',
  'drv',
  'inf',
  'cab',
  'reg',
  'lnk',
  'ini',
  'jar',
  'so',
  'dylib',
  'app',
  'dat',
  'db',
  'log',
  'tmp',
  'efi',
  'mui',
};
