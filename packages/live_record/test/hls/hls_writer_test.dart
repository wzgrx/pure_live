import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';
import '../support/ts_build.dart';

HlsMedia _ts(int sequence, {Uint8List? sps, int durationMs = 2000}) => HlsMedia(
  sequence: sequence,
  durationMs: durationMs,
  data: tsSegment(sequence, sps: sps),
);

HlsMedia _fmp4(int sequence, {Uint8List? init}) =>
    HlsMedia(sequence: sequence, durationMs: 1000, data: fmp4Fragments[sequence % 2], init: init ?? fmp4Init);

final class _Rig {
  new({Duration? split, int? splitBytes, FlvWriterLimits limits = const FlvWriterLimits()}) {
    layout = SessionLayout.at('/rec', RoomRef('soop', 'bj'), '主播', clock.now());
    gaps = GapLedger(files: files, path: layout.gaps, room: 'soop:bj', session: layout.prefix);
    writer = HlsSessionWriter(
      files: files,
      layout: layout,
      gaps: gaps,
      splitDuration: split,
      splitBytes: splitBytes,
      limits: limits,
      onSegment: events.add,
    );
  }

  final files = MemoryRecordFiles();
  final events = <SegmentEvent>[];
  late final SessionLayout layout;
  late final GapLedger gaps;
  late final HlsSessionWriter writer;

  List<Map<String, Object?>> get gapsJson =>
      ((jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>)['gaps']! as List<Object?>)
          .cast<Map<String, Object?>>();
}

void main() {
  test('MPEG-TS segments become one continuous .ts, written as .part and renamed when closed (§8)', () {
    fakeAsync((async) {
      final rig = _Rig();
      final segments = [for (var seq = 10; seq < 14; seq++) _ts(seq)]..forEach(rig.writer.addMedia);
      async.flushMicrotasks();
      expect(rig.files.paths, contains('${rig.layout.segment(1, extension: 'ts')}.part'));
      expect(rig.writer.mediaTags, 4);
      expect(rig.writer.mediaDuration, const Duration(seconds: 8));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      final path = rig.layout.segment(1, extension: 'ts');
      expect(rig.files.bytesOf(path), [for (final segment in segments) ...segment.data]);
      expect(rig.files.paths.where((path) => path.endsWith('.part')), isEmpty);
      final segment = rig.writer.segments.single;
      expect((segment.closed, segment.durationMs, segment.bytes), (true, 8000, rig.files.bytesOf(path)!.length));
      expect(rig.events.map((event) => event.runtimeType), [SegmentOpened, SegmentClosed]);
    });
  });

  test('record.splitMinutes splits at the next segment boundary; each file starts with a keyframe (§6.5)', () {
    fakeAsync((async) {
      final rig = _Rig(split: const Duration(seconds: 5));
      for (var seq = 0; seq < 7; seq++) {
        rig.writer.addMedia(_ts(seq));
      }
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect([for (final segment in rig.writer.segments) segment.durationMs], [6000, 6000, 2000]);
      expect(
        [for (final segment in rig.writer.segments) segment.name],
        ['${rig.layout.prefix}_001.ts', '${rig.layout.prefix}_002.ts', '${rig.layout.prefix}_003.ts'],
      );
    });
  });

  test('record.splitMegabytes splits by size', () {
    fakeAsync((async) {
      final size = _ts(0).data.length;
      final rig = _Rig(splitBytes: size * 2);
      for (var seq = 0; seq < 5; seq++) {
        rig.writer.addMedia(_ts(seq));
      }
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect([for (final segment in rig.writer.segments) segment.bytes ~/ size], [2, 2, 1]);
    });
  });

  group('files start with a keyframe (§6.5, Amazon IVS segments that do not)', () {
    Uint8List midGop(int sequence, {bool key = true}) {
      final base = 90000 + sequence * 180000;
      return buildTs([
        TsUnit.video(pts: base),
        TsUnit.audio(pts: base),
        TsUnit.video(pts: base + 60000),
        TsUnit.audio(pts: base + 60000),
        TsUnit.video(pts: base + 120000, key: key),
        TsUnit.audio(pts: base + 120000),
        TsUnit.video(pts: base + 150000),
      ]);
    }

    Future<RemuxResult> remux(_Rig rig, int index) => remuxRecording(
      files: rig.files,
      input: rig.layout.segment(index, extension: 'ts'),
      output: '/out$index.mp4',
    );

    test('the first segment is cut at its keyframe; the part before is left out', () async {
      final rig = _Rig();
      rig.writer
        ..addMedia(HlsMedia(sequence: 0, durationMs: 2000, data: midGop(0)))
        ..addMedia(HlsMedia(sequence: 1, durationMs: 2000, data: tsSegment(1)));
      await rig.writer.close();
      expect(rig.writer.droppedBytes, greaterThan(0));
      final result = await remux(rig, 1);
      expect(result.droppedTags, 0, reason: 'nothing before the keyframe is in the file');
      expect(result.videoSamples, 2 + 3);
    });

    test('a first segment without a keyframe is left out entirely', () async {
      final rig = _Rig();
      rig.writer
        ..addMedia(HlsMedia(sequence: 0, durationMs: 2000, data: midGop(0, key: false)))
        ..addMedia(HlsMedia(sequence: 1, durationMs: 2000, data: tsSegment(1)));
      await rig.writer.close();
      expect(rig.writer.skippedSegments, 1);
      expect(rig.writer.segments.single.durationMs, 2000);
      expect((await remux(rig, 1)).videoSamples, 3);
    });

    test('a split falls on the keyframe inside the segment: before it to the old file, from it the new one', () async {
      final rig = _Rig(split: const Duration(seconds: 3));
      rig.writer
        ..addMedia(HlsMedia(sequence: 0, durationMs: 2000, data: tsSegment(0)))
        ..addMedia(HlsMedia(sequence: 1, durationMs: 2000, data: tsSegment(1)))
        ..addMedia(HlsMedia(sequence: 2, durationMs: 2000, data: midGop(2)));
      await rig.writer.close();
      expect(rig.writer.segments, hasLength(2));
      final first = await remux(rig, 1);
      final second = await remux(rig, 2);
      expect(first.videoSamples, 3 + 3 + 2, reason: 'the two frames before the keyframe stay in the first file');
      expect((second.videoSamples, second.droppedTags), (2, 0));
    });
  });

  test('a changed codec setup (another SPS) starts a new file (§6.5); the same setup does not', () {
    fakeAsync((async) {
      final rig = _Rig()
        ..writer.addMedia(_ts(0))
        ..writer.addMedia(_ts(1))
        ..writer.addMedia(_ts(2, sps: TsBuild.otherSps))
        ..writer.addMedia(_ts(3, sps: TsBuild.otherSps));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect([for (final segment in rig.writer.segments) segment.durationMs], [4000, 4000]);
    });
  });

  test('fMP4: the initialisation section starts the file once; a new one starts a new .m4s', () {
    fakeAsync((async) {
      final rig = _Rig();
      final otherInit = Uint8List.fromList(fmp4Init)..[fmp4Init.length - 1] ^= 1;
      rig.writer
        ..addMedia(_fmp4(0))
        ..addMedia(_fmp4(1, init: Uint8List.fromList(fmp4Init)))
        ..addMedia(_fmp4(2, init: otherInit));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      final first = rig.files.bytesOf(rig.layout.segment(1, extension: 'm4s'))!;
      expect(first, [...fmp4Init, ...fmp4Fragments[0], ...fmp4Fragments[1]], reason: 'equal bytes: same file');
      final second = rig.files.bytesOf(rig.layout.segment(2, extension: 'm4s'))!;
      expect(second, [...otherInit, ...fmp4Fragments[0]]);
    });
  });

  test('switching between MPEG-TS and fMP4 starts a new file of the other kind', () {
    fakeAsync((async) {
      final rig = _Rig()
        ..writer.addMedia(_ts(0))
        ..writer.addMedia(_fmp4(1))
        ..writer.addMedia(_ts(2));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect([for (final segment in rig.writer.segments) segment.name.split('.').last], ['ts', 'm4s', 'ts']);
    });
  });

  test('a segment that does not end on a whole packet loses the rest; packed audio is refused', () {
    fakeAsync((async) {
      final rig = _Rig();
      final data = tsSegment(0);
      rig.writer.addMedia(HlsMedia(sequence: 0, durationMs: 2000, data: Uint8List.fromList([...data, 1, 2, 3])));
      expect(rig.writer.trimmedBytes, 3);
      expect(
        () =>
            rig.writer.addMedia(HlsMedia(sequence: 1, durationMs: 2000, data: Uint8List.fromList(utf8.encode('ID3…')))),
        throwsA(isA<RecordException>().having((e) => e.kind, 'kind', RecordErrorKind.unsupportedProtocol)),
      );
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect(rig.files.bytesOf(rig.layout.segment(1, extension: 'ts')), data);
    });
  });

  test('missing media is a gap at the file time, with its sequence numbers; none before the first media', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.writer.addMissing(const HlsMissing(reason: GapReason.sequenceJump, missingMs: 4000, fromSeq: 1, toSeq: 2));
      rig.writer
        ..addMedia(_ts(3))
        ..addMedia(_ts(4))
        ..addMissing(const HlsMissing(reason: GapReason.sequenceJump, missingMs: 6000, fromSeq: 5, toSeq: 7));
      async.flushMicrotasks();
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      final gap = rig.gapsJson.single;
      expect(gap['part'], '${rig.layout.prefix}_001.ts');
      expect(gap['atMs'], 4000);
      expect(gap['missingMs'], 6000);
      expect(gap['reason'], 'sequenceJump');
      expect(gap['source'], 'hls:video');
      expect((gap['fromSeq'], gap['toSeq']), (5, 7));
    });
  });

  test('chat time follows the file time of the segments written', () {
    fakeAsync((async) {
      final rig = _Rig();
      expect(rig.writer.fileTimeAt(clock.now()), isNull);
      rig.writer.addMedia(_ts(0));
      async.elapse(const Duration(seconds: 2));
      rig.writer.addMedia(_ts(1));
      async.elapse(const Duration(milliseconds: 500));
      expect(rig.writer.fileTimeAt(clock.now()), 2500);
      expect(rig.writer.fileTimeAt(clock.now().add(const Duration(minutes: 1))), 4000, reason: 'clamped');
      unawaited(rig.writer.close());
      async.flushMicrotasks();
    });
  });

  test('backpressure: ready waits while more than the queue limit is unwritten (§6.8)', () {
    fakeAsync((async) {
      final stall = Completer<void>();
      final rig = _Rig(limits: const FlvWriterLimits(queueBytes: 1000));
      rig.files.stall = stall.future;
      rig.writer
        ..addMedia(_ts(0))
        ..addMedia(_ts(1));
      var ready = false;
      unawaited(rig.writer.ready.then((_) => ready = true));
      async.elapse(const Duration(seconds: 1));
      expect(ready, isFalse);
      rig.files.stall = null;
      stall.complete();
      async.elapse(const Duration(seconds: 1));
      expect(ready, isTrue);
      unawaited(rig.writer.close());
      async.flushMicrotasks();
    });
  });

  test('a full disk is fatal (§21)', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.files.writeError = const FileSystemException('No space', '/rec', OSError('No space left on device', 28));
      rig.writer.addMedia(_ts(0));
      async.flushMicrotasks();
      expect(rig.writer.failed?.kind, RecordErrorKind.diskFull);
    });
  });
}
