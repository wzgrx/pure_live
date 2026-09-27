import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import 'support/fake_live.dart';

final class _Rig {
  new({Duration? split, int? splitBytes, this.files}) {
    files ??= MemoryRecordFiles();
    layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', clock.now());
    gaps = GapLedger(files: files!, path: layout.gaps, room: 'douyu:9999', session: layout.prefix);
    writer = FlvSessionWriter(
      files: files!,
      layout: layout,
      gaps: gaps,
      splitDuration: split,
      splitBytes: splitBytes,
      onSegment: events.add,
    );
  }

  MemoryRecordFiles? files;
  late final SessionLayout layout;
  late final GapLedger gaps;
  late final FlvSessionWriter writer;
  final events = <SegmentEvent>[];

  void feed(Iterable<Uint8List> packets) => packets.forEach(writer.add);

  FlvFile file(int index) => FlvFile(files!.bytesOf(layout.segment(index))!);
}

void main() {
  const flv = SyntheticFlv();

  test('a segment starts with header, script, configurations and a keyframe at 0 (§6.1)', () {
    fakeAsync((async) {
      final rig = _Rig()
        // Joined mid-GOP: frames before the first keyframe and audio older than it are dropped.
        ..feed([
          FlvTag.fileHeader(),
          SyntheticFlv.script(0),
          flv.videoConfig(0),
          SyntheticFlv.audioConfig(0),
          SyntheticFlv.video(100920, key: false),
          SyntheticFlv.audio(100950),
          ...flv.tags(101000, 104000),
        ]);
      unawaited(rig.writer.close());
      async.flushMicrotasks();

      final file = rig.file(1);
      expect(file.head, ['script', 'vconf', 'aconf', 'key', 'audio']);
      expect(file.video.first, 0);
      expect(file.keyframes.first, 0);
      expect(file.audio.first, greaterThanOrEqualTo(0));
      expect(file.video.last, 2960);
      expect(file.trailing, 0);
      expect(file.header[4], 5, reason: 'audio and video flags from the first connection');
      expect(rig.files!.paths.where((path) => path.endsWith('.part')), isEmpty);
      expect(rig.writer.mediaDuration, const Duration(milliseconds: 2983), reason: 'last audio at 2983');
    });
  });

  test('the open segment is a .part file, renamed when closed; a taken name gets -1 (§6.9)', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final rig = _Rig(files: files);
      files.put(rig.layout.segment(1), [1, 2, 3]);
      rig.feed(flv.connection(100000, 101000));
      async.flushMicrotasks();
      final taken = rig.layout.segment(1).replaceFirst('_001.flv', '_001-1.flv');
      expect(files.paths, contains('$taken.part'));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect(files.paths, containsAll([taken, rig.layout.segment(1)]));
      expect(files.bytesOf(rig.layout.segment(1)), [1, 2, 3], reason: 'never overwritten');
      expect(rig.writer.segments.single.path, taken);
    });
  });

  test('timestamps stay monotonic: older video and non-increasing audio are dropped (§6.2)', () {
    fakeAsync((async) {
      final rig = _Rig()
        ..feed([
          ...flv.connection(100000, 100200),
          SyntheticFlv.video(100080, key: false),
          SyntheticFlv.video(100160, key: false),
          SyntheticFlv.audio(100161),
          SyntheticFlv.audio(100161),
          SyntheticFlv.audio(100100),
        ]);
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      final file = rig.file(1);
      expect(FlvFile.monotonic(file.video), isTrue);
      expect(FlvFile.monotonic(file.audio, strict: true), isTrue);
      expect(file.video.where((ts) => ts == 160), hasLength(2), reason: 'equal video DTS is allowed');
    });
  });

  test('a reconnect on another timeline is rebased to the end plus one frame, with a gap (§6.3)', () {
    fakeAsync((async) {
      final rig = _Rig()..feed(flv.connection(100000, 110000));
      async.elapse(const Duration(seconds: 3));
      rig.writer.beginConnection(lostAt: clock.now().subtract(const Duration(seconds: 2)));
      rig.feed(flv.connection(5000, 8000));
      unawaited(rig.writer.close());
      async.flushMicrotasks();

      final file = rig.file(1);
      expect(rig.writer.segments, hasLength(1), reason: 'a reconnect continues the same file');
      expect(FlvFile.maxStep(file.video), 40, reason: 'rebased right after the last frame');
      expect(FlvFile.monotonic(file.audio, strict: true), isTrue);
      final gap = rig.gaps.gaps.single;
      expect(gap.reason, GapReason.eof);
      expect(gap.atMs, 9960 + 40);
      expect(gap.missingMs, 2000);
      expect(gap.part, endsWith('_001.flv'));
    });
  });

  test('a reconnect on the same timeline keeps its timestamps and records the skipped time', () {
    fakeAsync((async) {
      final rig = _Rig()..feed(flv.connection(100000, 110000));
      rig.writer.beginConnection(lostAt: clock.now());
      rig.feed(flv.connection(113000, 115000));
      unawaited(rig.writer.close());
      async.flushMicrotasks();

      final file = rig.file(1);
      expect(file.video, contains(13000));
      expect(FlvFile.maxStep(file.video), 13000 - 9960);
      expect(rig.gaps.gaps.single.missingMs, 13000 - 9960 - 40);
      expect(file.videoConfigs, hasLength(1), reason: 'the same configuration is not repeated');
      expect(file.scripts, 1);
    });
  });

  test('splits by duration at the next keyframe; every segment starts at 0 (§6.5)', () {
    fakeAsync((async) {
      final rig = _Rig(split: const Duration(seconds: 3))..feed(flv.connection(100000, 107500));
      unawaited(rig.writer.close());
      async.flushMicrotasks();

      expect(rig.writer.segments, hasLength(3));
      for (var i = 1; i <= 3; i++) {
        final file = rig.file(i);
        expect(file.head.take(4), ['script', 'vconf', 'aconf', 'key'], reason: 'segment $i');
        expect(file.video.first, 0);
        expect(file.audio.first, greaterThanOrEqualTo(0));
      }
      expect(rig.file(1).video.last, 2960);
      expect(rig.events.whereType<SegmentOpened>(), hasLength(3));
      expect(rig.events.whereType<SegmentClosed>(), hasLength(3));
    });
  });

  test('splits by size at the next keyframe', () {
    fakeAsync((async) {
      final rig = _Rig(splitBytes: 2000)..feed(flv.connection(100000, 104000));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      expect(rig.writer.segments.length, greaterThan(1));
      expect(rig.writer.segments.every((segment) => segment.closed), isTrue);
    });
  });

  test('a new video configuration opens a new segment that starts with it (§6.5)', () {
    fakeAsync((async) {
      const other = SyntheticFlv(videoConfigPayload: [9, 9, 9]);
      final rig = _Rig()..feed(flv.connection(100000, 102000));
      rig.writer.beginConnection();
      rig.feed(other.connection(102000, 104000));
      unawaited(rig.writer.close());
      async.flushMicrotasks();

      expect(rig.writer.segments, hasLength(2));
      final second = rig.file(2);
      expect(second.head.take(4), ['script', 'vconf', 'aconf', 'key']);
      expect(second.videoConfigs.single.sublist(FlvTag.headerLength + 10, FlvTag.headerLength + 13), [9, 9, 9]);
      expect(rig.file(1).videoConfigs, hasLength(1));
    });
  });

  test('prefix-only video at the end is dropped; followed by a picture it is kept (§6.7)', () {
    fakeAsync((async) {
      final rig = _Rig()
        ..feed([
          ...flv.connection(100000, 100400),
          SyntheticFlv.sei(100400),
          SyntheticFlv.video(100400, key: false),
          SyntheticFlv.sei(100440),
          SyntheticFlv.audio(100441),
        ]);
      expect(rig.writer.holdsPrefix, isTrue);
      unawaited(rig.writer.close());
      async.flushMicrotasks();

      final file = rig.file(1);
      final last = file.tags.lastWhere((tag) => FlvTag.type(tag) == FlvTag.video);
      expect(FlvCodec.isPrefixOnly(last), isFalse, reason: 'the file never ends with SEI only');
      expect(file.video.where((ts) => ts == 400), hasLength(2), reason: 'SEI before a picture stays');
      expect(file.audio.last, 441, reason: 'audio held behind the SEI is still written');
    });
  });

  test('legacy codec-12 HEVC is rewritten to Enhanced FLV hvc1 (§6.6)', () {
    final config = FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x1C, 0, 0, 0, 0, 1, 2, 3]);
    final frame = FlvTag.build(type: FlvTag.video, timestamp: 40, data: [0x2C, 1, 0, 0, 9, 0, 0, 0, 2, 0x02, 0x01]);
    final end = FlvTag.build(type: FlvTag.video, timestamp: 80, data: [0x1C, 2, 0, 0, 0]);
    final c = FlvCodec.rewriteLegacyHevc(config);
    final f = FlvCodec.rewriteLegacyHevc(frame);
    final e = FlvCodec.rewriteLegacyHevc(end);
    const h = FlvTag.headerLength;
    expect(c.sublist(h, h + 8), [0x90, 0x68, 0x76, 0x63, 0x31, 1, 2, 3]);
    expect(f.sublist(h, h + 13), [0xA1, 0x68, 0x76, 0x63, 0x31, 0, 0, 9, 0, 0, 0, 2, 0x02]);
    expect(e.sublist(h, h + 5), [0x92, 0x68, 0x76, 0x63, 0x31]);
    expect(FlvTag.timestamp(f), 40);
    expect(FlvTag.isVideoConfig(c), isTrue);
    expect(FlvTag.isKeyframe(f), isFalse);
    final avc = SyntheticFlv.video(0, key: true);
    expect(identical(FlvCodec.rewriteLegacyHevc(avc), avc), isTrue, reason: 'other tags are untouched');
    final hevcSei = FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x2C, 1, 0, 0, 0, 0, 0, 0, 2, 0x4E, 0x01]);
    expect(FlvCodec.isPrefixOnly(FlvCodec.rewriteLegacyHevc(hevcSei)), isTrue, reason: 'HEVC prefix SEI (39)');
    expect(FlvCodec.isPrefixOnly(f), isFalse, reason: 'HEVC TRAIL_R slice (1)');
  });

  test('timestamps beyond 24 bits use the extension byte', () {
    fakeAsync((async) {
      const far = 0x1000000 + 5000;
      final rig = _Rig()
        ..feed([
          ...flv.connection(100000, 100100),
          SyntheticFlv.video(100000 + far, key: true),
          SyntheticFlv.audio(100000 + far + 1),
        ]);
      unawaited(rig.writer.close());
      async.flushMicrotasks();
      final file = rig.file(1);
      expect(file.video.last, far);
      expect(file.audio.last, far + 1);
      final last = file.tags.last;
      expect(last[7], 0x01, reason: 'bits 24-31 go to the extension byte');
    });
  });

  test('backpressure: a stalled disk holds the reader, 30 s of stall is fatal (§6.8)', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final rig = _Rig(files: files)..feed(flv.connection(100000, 101000));
      async.flushMicrotasks();
      final stall = Completer<void>();
      files.stall = stall.future;
      // Queue well over 8 MiB.
      final big = FlvTag.build(type: FlvTag.audio, timestamp: 0, data: List.filled(1 << 20, 0xAF));
      for (var i = 0; i < 10; i++) {
        rig.writer.add(FlvTag.withTimestamp(big, 101000 + i * 23));
      }
      var ready = false;
      unawaited(rig.writer.ready.then((_) => ready = true));
      async.elapse(const Duration(seconds: 29));
      expect(ready, isFalse);
      expect(rig.writer.failed, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(rig.writer.failed?.kind, RecordErrorKind.diskStalled);
      expect(ready, isTrue, reason: 'a failed writer releases the reader');
      unawaited(rig.writer.close(giveUpAfter: const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 2));
    });
  });

  test('a full disk is a typed fatal error', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final rig = _Rig(files: files);
      RecordFailure? failure;
      unawaited(rig.writer.failure.then((value) => failure = value));
      rig.feed(flv.connection(100000, 100500));
      async.flushMicrotasks();
      files.writeError = const FileSystemException('write failed', '/rec', OSError('No space left on device', 28));
      rig.feed(flv.tags(100500, 101000));
      async.flushMicrotasks();
      expect(failure?.kind, RecordErrorKind.diskFull);
      expect(failure?.stage, RecordStage.writer);
      files.writeError = null;
      unawaited(rig.writer.close());
      async.elapse(const Duration(seconds: 1));
      expect(rig.writer.segments.single.closed, isTrue, reason: 'what reached the file is kept');
    });
  });

  test('flushes at least every second while open', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final rig = _Rig(files: files)..feed(flv.connection(100000, 100100));
      async.elapse(const Duration(milliseconds: 1500));
      expect(files.flushes, greaterThanOrEqualTo(1));
      unawaited(rig.writer.close());
      async.flushMicrotasks();
    });
  });

  test('chat time follows the file time anchors (§17)', () {
    fakeAsync((async) {
      final rig = _Rig()..feed(flv.connection(100000, 100100));
      final start = clock.now();
      async.elapse(const Duration(seconds: 2));
      rig.feed(flv.tags(100100, 102000));
      expect(rig.writer.fileTimeAt(start.add(const Duration(milliseconds: 500))), 500);
      expect(
        rig.writer.fileTimeAt(start.add(const Duration(seconds: 10))),
        1982,
        reason: 'clamped to what was written',
      );
      expect(rig.writer.fileTimeAt(start.subtract(const Duration(seconds: 1))), 0);
      unawaited(rig.writer.close());
      async.flushMicrotasks();
    });
  });

  test('gaps.json is written atomically and lists every gap', () {
    fakeAsync((async) {
      final files = MemoryRecordFiles();
      final rig = _Rig(files: files);
      unawaited(rig.gaps.write());
      async.flushMicrotasks();
      final empty = jsonDecode(utf8.decode(files.bytesOf(rig.layout.gaps)!)) as Map<String, Object?>;
      expect(empty['gaps'], isEmpty, reason: 'no gaps still writes an empty list');
      expect(empty['room'], 'douyu:9999');
      unawaited(rig.gaps.add(const RecordGap(part: 'a_001.flv', atMs: 5, reason: GapReason.http4xx, missingMs: 1200)));
      async.flushMicrotasks();
      final json = jsonDecode(utf8.decode(files.bytesOf(rig.layout.gaps)!)) as Map<String, Object?>;
      expect((json['gaps']! as List).single, containsPair('reason', 'http4xx'));
      expect(files.paths.where((path) => path.endsWith('.tmp')), isEmpty);
      unawaited(rig.writer.close());
      async.flushMicrotasks();
    });
  });
}
