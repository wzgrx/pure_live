import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_media_spool.dart';

void main() {
  test('small body is inaccessible before seal and stays in bounded memory', () async {
    final spool = HlsMediaSpool(createDirectory: () => throw StateError('Unexpected disk allocation'), memoryLimit: 8);
    addTearDown(spool.dispose);
    await spool.add([1, 2, 3]);
    expect(spool.read, throwsStateError);
    expect(spool.memoryBytes, 3);
    await spool.seal(expectedLength: 3);
    expect(await spool.read().expand((chunk) => chunk).toList(), [1, 2, 3]);
    expect(spool.spilled, false);
    await expectLater(spool.add([4]), throwsStateError);
  });

  test('large chunks spill whole bytes and dispose only the owned file/directory', () async {
    final root = await Directory.systemTemp.createTemp('purelive-spool-test-');
    final unrelated = File('${root.path}${Platform.pathSeparator}keep.txt');
    await unrelated.writeAsString('keep');
    final spool = HlsMediaSpool(createDirectory: () => root.createTemp('owned-'), memoryLimit: 4, byteLimit: 100);
    try {
      await spool.add([1, 2, 3]);
      await spool.add([4, 5, 6, 7, 8]);
      expect(spool.spilled, true);
      expect(spool.memoryBytes, 0);
      await spool.seal(expectedLength: 8);
      expect(await spool.read().expand((chunk) => chunk).toList(), [1, 2, 3, 4, 5, 6, 7, 8]);
      await spool.dispose();
      await spool.dispose();
      expect(await root.list().length, 1);
      expect(await unrelated.readAsString(), 'keep');
    } finally {
      await spool.dispose();
      await unrelated.delete();
      await root.delete();
    }
  });

  test('length mismatch never seals or publishes a partial response', () async {
    final spool = HlsMediaSpool(createDirectory: () => throw StateError('Unexpected disk allocation'));
    addTearDown(spool.dispose);
    await spool.add([1, 2]);
    await expectLater(spool.seal(expectedLength: 4), throwsA(isA<HttpException>()));
    expect(spool.read, throwsStateError);
  });

  test('chunked input seals at actual length and the resource limit is enforced', () async {
    final spool = HlsMediaSpool(createDirectory: () => throw StateError('Unexpected disk allocation'), byteLimit: 4);
    addTearDown(spool.dispose);
    await spool.add([1, 2, 3, 4]);
    await expectLater(spool.add([5]), throwsFormatException);
    expect(spool.length, 4);
    await spool.seal(expectedLength: -1);
    expect(await spool.read().expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
  });

  test('dispose during an unsealed download deletes its spill', () async {
    final root = await Directory.systemTemp.createTemp('purelive-spool-test-');
    final spool = HlsMediaSpool(createDirectory: () => root.createTemp('owned-'), memoryLimit: 1);
    try {
      await spool.add([1, 2, 3]);
      await spool.dispose();
      expect(await root.list().isEmpty, true);
      expect(spool.read, throwsStateError);
      await expectLater(spool.seal(expectedLength: 3), throwsStateError);
    } finally {
      await spool.dispose();
      await root.delete();
    }
  });
}
