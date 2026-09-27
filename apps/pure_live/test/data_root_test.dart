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
}
