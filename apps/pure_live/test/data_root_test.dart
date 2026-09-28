import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/core/data_root.dart';

void main() {
  test('F-WIN-06: a writable folder is used, a blocked one is not', () async {
    final temp = await Directory.systemTemp.createTemp('data-root-');
    addTearDown(() => temp.delete(recursive: true));
    expect(await isWritableDirectory(Directory('${temp.path}/data')), isTrue);
    expect(Directory('${temp.path}/data').existsSync(), isTrue);
    // A file where the folder should be: not writable as a folder.
    final blocker = File('${temp.path}/blocked')..writeAsStringSync('x');
    expect(await isWritableDirectory(Directory('${blocker.path}/data')), isFalse);
  });

  test("F-WIN-06: portable data sits in UserData beside the exe, never in Flutter's data folder", () {
    expect(portableDataDir(r'C:\PureLive\pure_live_app.exe'), r'C:\PureLive\UserData');
    expect(portableDataDir('D:/Apps/PureLive/pure_live_app.exe'), r'D:/Apps/PureLive\UserData');
    expect(portableDataDir(r'C:\PureLive\pure_live_app.exe'), isNot(endsWith(r'\data')));
  });
}
