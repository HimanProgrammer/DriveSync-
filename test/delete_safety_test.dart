import 'package:flutter_test/flutter_test.dart';
import 'package:drivesync/services/delete_safety.dart';

void main() {
  group('never deletes system or software files', () {
    const protected = [
      r'C:\Windows\System32\drivers\etc\hosts',
      r'C:\Windows\explorer.exe',
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Steam\steam.dll',
      r'F:\Program Files\Some App\data\video.mp4',
      r'C:\ProgramData\Microsoft\Windows\file.dat',
      r'C:\Users\me\AppData\Local\Temp\big.zip',
      r'C:\Users\me\AppData\Roaming\Code\User\settings.json',
      r'D:\Games\SteamLibrary\steamapps\common\Game\movie.mp4',
      r'C:\pagefile.sys',
      r'C:\hiberfil.sys',
      r'C:\$Recycle.Bin\S-1-5\file.mp4',
      r'C:\System Volume Information\x.dat',
      r'C:\Users\me\NTUSER.DAT',
      r'C:\Users\me\Desktop\desktop.ini',
      r'C:\Users\me\Downloads\setup.exe',
      r'C:\Users\me\Downloads\installer.msi',
      r'C:\Users\me\Documents\script.ps1',
      r'C:\Users\me\Documents\run.bat',
      r'C:\Users\me\Documents\shortcut.lnk',
      r'C:\Users\me\project\node_modules\pkg\big.tar.gz',
      r'C:\Users\me\project\.git\objects\pack\pack.pack',
      r'C:\Users\me\.android\avd\image.img',
      r'E:\Windows.old\Users\me\Videos\a.mp4',
      r'C:\Recovery\WindowsRE\Winre.wim',
      r'/usr/lib/libfoo.so',
      r'/System/Library/foo.mov',
    ];
    for (final path in protected) {
      test(path, () => expect(isSafeToDelete(path), isFalse));
    }
  });

  group('allows personal files after upload', () {
    const allowed = [
      r'C:\Users\me\Videos\holiday.mp4',
      r'C:\Users\me\Pictures\2024\IMG_0001.jpg',
      r'C:\Users\me\Downloads\movie.mkv',
      r'C:\Users\me\Documents\report.pdf',
      r'F:\Newfolder\photos\trip.png',
      r'D:\Backups\old-project.zip',
      r'/home/me/Videos/clip.mov',
    ];
    for (final path in allowed) {
      test(path, () => expect(isSafeToDelete(path), isTrue));
    }
  });

  test('a folder holding programs is software, not personal files', () {
    expect(
      isSafeToDelete(r'F:\Tools\MyApp\intro.mp4',
          siblingNames: ['MyApp.exe', 'intro.mp4']),
      isFalse,
    );
    expect(
      isSafeToDelete(r'F:\Videos\intro.mp4',
          siblingNames: ['intro.mp4', 'notes.txt']),
      isTrue,
    );
  });
}

