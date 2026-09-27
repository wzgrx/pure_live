import 'dart:async';
import 'dart:io';

import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import '../support/flv_build.dart';
import '../support/mp4_reader.dart';

/// Reports progress 10, 20 … 50 and succeeds.
final class _Reports implements Remuxer {
  const new();

  @override
  Future<void> remux(RemuxJob job) async {
    for (var i = 1; i <= 5; i++) {
      job.onProgress(i * 10);
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Waits for cancellation, then fails.
final class _WaitsForCancel implements Remuxer {
  const new();

  @override
  Future<void> remux(RemuxJob job) async {
    await job.cancelled;
    throw const RemuxException('stopped');
  }
}

/// Fails with an error that is not a RemuxException.
final class _Crashes implements Remuxer {
  const new();

  @override
  Future<void> remux(RemuxJob job) async => throw StateError('boom');
}

RemuxJob _job({String input = 'in', String output = 'out', void Function(int)? onProgress, Future<void>? cancelled}) =>
    RemuxJob(
      input: input,
      output: output,
      inputBytes: 100,
      onProgress: onProgress ?? (_) {},
      cancelled: cancelled ?? Completer<void>().future,
    );

void main() {
  test('progress crosses the isolate boundary in order', () async {
    final progress = <int>[];
    await const IsolateRemuxer(_Reports()).remux(_job(onProgress: progress.add));
    // Progress sent just before the isolate finished may still be in flight.
    expect(progress, [10, 20, 30, 40, 50].sublist(0, progress.length));
  });

  test('cancellation reaches the remuxer in the isolate', () async {
    final cancel = Completer<void>();
    final run = const IsolateRemuxer(_WaitsForCancel()).remux(_job(cancelled: cancel.future));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cancel.complete();
    await expectLater(run, throwsA(isA<RemuxException>().having((e) => e.message, 'message', 'stopped')));
  });

  test('any error in the isolate arrives as a RemuxException', () async {
    await expectLater(
      const IsolateRemuxer(_Crashes()).remux(_job()),
      throwsA(isA<RemuxException>().having((e) => e.message, 'message', contains('boom'))),
    );
  });

  group('with FlvToMp4Remuxer on disk', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('live_record_remux'));
    tearDown(() => dir.delete(recursive: true));

    test('converts a file', () async {
      final input = '${dir.path}/a.flv';
      File(input).writeAsBytesSync(remuxFixture('avc_aac.flv'));
      await const IsolateRemuxer(FlvToMp4Remuxer()).remux(_job(input: input, output: '${dir.path}/a.mp4.partial'));
      final mp4 = File('${dir.path}/a.mp4.partial').readAsBytesSync();
      final boxes = parseBoxes(mp4);
      expect(boxes.map((box) => box.type), ['ftyp', 'moov', 'mdat']);
      expect(readTrack(mp4, boxes[1].all('trak').first).sizes, hasLength(60));
    });

    test('a damaged file fails and leaves no output', () async {
      final input = '${dir.path}/a.flv';
      final bytes = remuxFixture('avc_aac.flv');
      File(input).writeAsBytesSync(bytes.sublist(0, bytes.length - 5));
      await expectLater(
        const IsolateRemuxer(FlvToMp4Remuxer()).remux(_job(input: input, output: '${dir.path}/a.mp4.partial')),
        throwsA(isA<RemuxException>().having((e) => e.message, 'message', contains('truncated'))),
      );
      expect(File('${dir.path}/a.mp4.partial').existsSync(), isFalse);
    });
  });
}
