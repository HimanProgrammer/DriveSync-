import 'dart:io';

import 'package:drivesync/services/delete_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;

  setUp(() {
    // A fake user folder under /home so the Unix rule treats it as personal.
    home = Directory(p.join(Directory.systemTemp.path, 'home', 'me'))
      ..createSync(recursive: true);
  });

  tearDown(() => home.parent.deleteSync(recursive: true));

  bool check(File f) => isSafeToDelete(
        // Present it like a /home path, as on a real Linux desktop.
        '/home/me/${p.relative(f.path, from: home.path)}',
        siblingNames: f.parent.listSync().map((e) => p.basename(e.path)),
      );

  test('a video next to a program is kept', () {
    final dir = Directory(p.join(home.path, 'Tools', 'MyApp'))..createSync(recursive: true);
    File(p.join(dir.path, 'MyApp.exe')).writeAsStringSync('x');
    final video = File(p.join(dir.path, 'intro.mp4'))..writeAsStringSync('x');
    expect(check(video), isFalse);
  });

  test('a video in a normal folder may be deleted after upload', () {
    final dir = Directory(p.join(home.path, 'Videos'))..createSync(recursive: true);
    final video = File(p.join(dir.path, 'holiday.mp4'))..writeAsStringSync('x');
    expect(check(video), isTrue);
  });
}
