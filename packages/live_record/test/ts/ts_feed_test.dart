import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_live.dart';
import '../support/ts_check.dart';
import '../support/ts_live.dart';

final _line = StreamLine(
  url: Uri.parse('http://192.168.1.1:4022/udp/239.3.1.1:8000'),
  format: StreamFormat.other,
  lineId: 'line1',
  requested: quality,
);

final class _Rig {
  new({TsLive? live, int startMs = 10013, Duration? split, int? splitBytes, this.timings = const TsTimings()})
    : cdn = FakeTsCdn(live: live, startMs: startMs) {
    layout = SessionLayout.at('/rec', RoomRef('iptv', 'CCTV-1'), 'CCTV-1', clock.now());
    gaps = GapLedger(files: files, path: layout.gaps, room: 'iptv:CCTV-1', session: layout.prefix);
    writer = HlsSessionWriter(
      files: files,
      layout: layout,
      gaps: gaps,
      splitDuration: split,
      splitBytes: splitBytes,
      onSegment: events.add,
    );
  }

  final FakeTsCdn cdn;
  final TsTimings timings;
  final files = MemoryRecordFiles();
  final events = <SegmentEvent>[];
  final state = TsStreamState();
  late final SessionLayout layout;
  late final GapLedger gaps;
  late final HlsSessionWriter writer;
  final feeds = <TsFeed>[];
  final results = <Object?>[];

  TsFeed get feed => feeds.last;

  /// Opens a connection and runs a feed on it; [results] gets `done` or the error.
  void connect(FakeAsync async, {DateTime? lostAt, GapReason reason = GapReason.eof}) {
    unawaited(
      cdn.open(_line).then((source) async {
        final sniff = await sniffStream(source);
        expect(sniff.content, StreamContent.ts);
        final feed = TsFeed(
          source: source,
          sink: writer,
          state: state,
          head: sniff.head,
          lostAt: lostAt,
          reason: reason,
          timings: timings,
        );
        feeds.add(feed);
        try {
          await feed.run();
          results.add('done');
        } on Object catch (error) {
          results.add(error);
        }
      }),
    );
    async.flushMicrotasks();
  }

  /// Records [seconds], then the connection ends; returns when it ended.
  DateTime record(FakeAsync async, int seconds, {DateTime? lostAt, GapReason reason = GapReason.eof}) {
    final count = results.length;
    connect(async, lostAt: lostAt, reason: reason);
    async.elapse(Duration(seconds: seconds));
    cdn.cutAll();
    async.elapse(const Duration(milliseconds: 100));
    expect(results.length, count + 1);
    return clock.now();
  }

  void close(FakeAsync async) {
    unawaited(writer.close());
    async.flushMicrotasks();
  }

  Uint8List bytes(int index) => files.bytesOf(layout.segment(index, extension: 'ts'))!;

  List<Map<String, Object?>> get gapsJson {
    final bytes = files.bytesOf(layout.gaps);
    if (bytes == null) return const [];
    return ((jsonDecode(utf8.decode(bytes)) as Map<String, Object?>)['gaps']! as List<Object?>)
        .cast<Map<String, Object?>>();
  }

  /// The remux of segment [index] (it throws on any damage).
  RemuxResult remux(FakeAsync async, int index) {
    RemuxResult? result;
    Object? error;
    final path = layout.segment(index, extension: 'ts');
    unawaited(
      remuxRecording(
        files: files,
        input: path,
        output: '$path.mp4',
      ).then((value) => result = value, onError: (Object e) => error = e),
    );
    async.flushMicrotasks();
    if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
    return result!;
  }
}

/// The packets of [file] from [from] on, in the order of [source]: each
/// one is found in [source] after the previous one.
bool _subsequence(Uint8List file, int from, List<TsLivePacket> source) {
  var at = 0;
  for (var offset = from * 188; offset + 188 <= file.length; offset += 188) {
    final packet = Uint8List.sublistView(file, offset, offset + 188);
    while (at < source.length && !_equal(source[at].bytes, packet)) {
      at++;
    }
    if (at == source.length) return false;
    at++;
  }
  return true;
}

bool _equal(Uint8List a, Uint8List b) {
  for (var i = 0; i < 188; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Every video PES of [file] has as many packets as in [live] (none was cut).
void _expectWholeFrames(Uint8List file, TsLive live) {
  final source = TsCheck.of(live.bytes(0, live.packets.length));
  final check = TsCheck.of(file);
  for (final MapEntry(key: pts, value: packets) in check.videoPesPackets.entries) {
    expect(packets, source.videoPesPackets[pts], reason: 'video PES at PTS $pts');
  }
}

void main() {
  test('a live stream joined mid-frame starts at the next keyframe after PAT and PMT; packets as sent (§8.2)', () {
    fakeAsync((async) {
      final rig = _Rig()..record(async, 6);
      expect(rig.results, ['done']);
      rig.close(async);
      final bytes = rig.bytes(1);
      expect(bytes.length % 188, 0);
      final check = TsCheck.of(bytes);
      expect(check.problems, isEmpty);
      expect(check.firstPids, [0, TsLivePids.pmt, TsLivePids.video], reason: 'PAT, PMT, then the keyframe');
      expect(check.keyStarts.first, 2);
      final live = rig.cdn.live;
      // Joined at 10.013 s: the first keyframe is the one at 11 s.
      expect(check.videoPts.first, live.base + 11000 * 90);
      final key = live.packets.indexWhere((p) => p.key && p.us >= 11000000);
      expect(_subsequence(bytes, 2, live.packets.sublist(key)), isTrue, reason: 'the packets as they came');
      _expectWholeFrames(bytes, live);
      final result = rig.remux(async, 1);
      expect(result.videoSamples, check.videoStarts.length);
      expect(result.videoSamples, greaterThan(4 * 25));
      expect(result.audioSamples, greaterThan(4 * 45));
      final segment = rig.writer.segments.single;
      expect(segment.durationMs, (check.videoStarts.length - 1) * 40);
      expect(rig.writer.mediaTags, check.videoStarts.length);
      expect(rig.feed.units, check.videoStarts.length);
      expect(rig.feed.damagedUnits, 0);
      expect(rig.gapsJson, isEmpty);
    });
  });

  test('a misaligned start and arbitrary chunk sizes give the same file (§8.1)', () {
    Uint8List run({List<int> prefix = const [], int chunkBytes = 0}) {
      late Uint8List bytes;
      fakeAsync((async) {
        final rig = _Rig();
        rig.cdn
          ..prefix = prefix
          ..chunkBytes = chunkBytes;
        rig
          ..record(async, 5)
          ..close(async);
        bytes = rig.bytes(1);
      });
      return bytes;
    }

    final plain = run();
    expect(run(prefix: List.filled(101, 0x47)), plain, reason: 'junk before the first packet');
    expect(run(chunkBytes: 1000), plain);
    expect(run(prefix: [1, 2, 3], chunkBytes: 333), plain);
  });

  test('a connection that ends mid-frame leaves only whole units (§8.2)', () {
    fakeAsync((async) {
      final rig = _Rig()..connect(async);
      // Stop between two packets of a keyframe (the keyframe at 14 s spans 14.000–14.040 s).
      async.elapse(const Duration(milliseconds: 14000 - 10013 + 20));
      rig.cdn.cutAll();
      async.elapse(const Duration(milliseconds: 100));
      rig.close(async);
      final bytes = rig.bytes(1);
      final check = TsCheck.of(bytes);
      expect(check.problems, isEmpty);
      _expectWholeFrames(bytes, rig.cdn.live);
      expect(check.videoPts.last, lessThan(rig.cdn.live.base + 14000 * 90), reason: 'the cut keyframe is not written');
      expect(rig.remux(async, 1).videoSamples, check.videoStarts.length);
    });
  });

  test('a reconnection continues the file at the next keyframe with a gap; the remux keeps the hole (§8.3)', () {
    fakeAsync((async) {
      final rig = _Rig();
      final lostAt = rig.record(async, 5);
      async.elapse(const Duration(seconds: 3));
      rig
        ..record(async, 5, lostAt: lostAt)
        ..close(async);
      expect(rig.writer.segments, hasLength(1));
      final bytes = rig.bytes(1);
      final check = TsCheck.of(bytes);
      expect(check.problems, isEmpty, reason: 'continuity breaks only where a unit starts');
      _expectWholeFrames(bytes, rig.cdn.live);
      // The PTS jump: the last frame before, the resumed keyframe after.
      final pts = check.videoPts;
      final jump = [
        for (var i = 1; i < pts.length; i++)
          if (pts[i] - pts[i - 1] != 3600) i,
      ].single;
      expect(check.keyStarts, contains(check.videoStarts[jump]));
      final resumed = check.videoStarts[jump];
      final before = TsCheck.of(Uint8List.sublistView(bytes, (resumed - 2) * 188, resumed * 188));
      expect(before.pats, [0], reason: 'PAT and PMT right before the resumed keyframe');
      final gap = rig.gapsJson.single;
      expect(gap['reason'], 'eof');
      expect(gap['source'], 'ts');
      expect(gap['part'], '${rig.layout.prefix}_001.ts');
      final missing = (pts[jump] - pts[jump - 1]) ~/ 90 - 40;
      expect(gap['missingMs'], missing);
      expect(missing, greaterThan(3000));
      expect(gap['atMs'], (pts[jump] - pts.first) ~/ 90, reason: 'where the resumed media is, as for FLV');
      final segment = rig.writer.segments.single;
      expect(segment.durationMs, (pts.last - pts.first) ~/ 90, reason: 'the file time keeps the hole, like the remux');
      final result = rig.remux(async, 1);
      expect(result.videoSamples, pts.length);
      expect(result.duration.inMilliseconds, closeTo((pts.last - pts.first) ~/ 90 + 40, 50));
    });
  });

  test('a restarted source (timestamps from another base) is joined by the remux; the gap uses wall time', () {
    fakeAsync((async) {
      final rig = _Rig();
      final lostAt = rig.record(async, 5);
      rig.cdn.restart(TsLive(base: 5000));
      async.elapse(const Duration(seconds: 2));
      rig
        ..record(async, 5, lostAt: lostAt, reason: GapReason.network)
        ..close(async);
      final bytes = rig.bytes(1);
      final check = TsCheck.of(bytes);
      expect(check.problems, isEmpty);
      final gap = rig.gapsJson.single;
      expect(gap['reason'], 'network');
      // Reconnected 2 s after the loss; the restarted stream has a keyframe at once.
      expect(gap['missingMs'], closeTo(2000, 100));
      final result = rig.remux(async, 1);
      expect(result.videoSamples, check.videoStarts.length);
      // The second stretch follows the first one frame later: no backward step, no 90 000 s hole.
      final media = (check.videoStarts.length - 1) * 40;
      expect(result.duration.inMilliseconds, closeTo(media, 200));
    });
  });

  test('lost video packets drop to the next keyframe with a damaged gap; lost audio drops one PES', () {
    fakeAsync((async) {
      final live = TsLive();
      final rig = _Rig(live: live);
      // A packet in the middle of the frame at 12.2 s, and one of the audio PES at 13.056 s.
      final frame = live.packets.indexWhere((p) => p.videoStart && p.us == 12200000);
      final audio = live.packets.indexWhere((p) => p.pid == TsLivePids.audio && p.us == 13056000);
      int second(int from, int pid) => [
        for (var i = from + 1; i < live.packets.length; i++)
          if (live.packets[i].pid == pid) i,
      ].first;
      rig.cdn.lost.addAll({second(frame, TsLivePids.video), second(audio, TsLivePids.audio)});
      rig
        ..record(async, 6)
        ..close(async);
      final bytes = rig.bytes(1);
      final check = TsCheck.of(bytes);
      expect(check.problems, isEmpty);
      final times = [for (final pts in check.videoPts) (pts - live.base) ~/ 90];
      expect(times, isNot(contains(12200)));
      expect(times.where((ms) => ms > 12160 && ms < 13000), isEmpty, reason: 'waits for the keyframe at 13 s');
      expect(times, containsAll([12160, 13000, 13040]));
      final gap = rig.gapsJson.single;
      expect(gap['reason'], 'damaged');
      expect(gap['missingMs'], 13000 - 12160 - 40);
      expect(rig.feed.damagedUnits, 2);
      expect(rig.feed.cuts, 1);
      final result = rig.remux(async, 1);
      expect(result.videoSamples, check.videoStarts.length);
    });
  });

  test('lost sync is found again; what was complete stays (§8.2)', () {
    fakeAsync((async) {
      final live = TsLive();
      final rig = _Rig(live: live);
      final frame = live.packets.indexWhere((p) => p.videoStart && p.us == 12200000);
      rig.cdn.garbage[frame + 2] = [0x47, 1, 2, 3, 0x47];
      rig
        ..record(async, 6)
        ..close(async);
      final bytes = rig.bytes(1);
      final check = TsCheck.of(bytes);
      expect(check.problems, isEmpty);
      expect(rig.gapsJson.single['reason'], 'damaged');
      _expectWholeFrames(bytes, live);
      expect(rig.remux(async, 1).videoSamples, check.videoStarts.length);
    });
  });

  test('record.splitMinutes splits at a keyframe; PES begun before it end in the old file (§6.5)', () {
    fakeAsync((async) {
      // Audio PES of 8 packets over 64 ms: they straddle the keyframes.
      final live = TsLive(audioFrameSize: 450);
      final rig = _Rig(live: live, split: const Duration(seconds: 2))
        ..record(async, 7)
        ..close(async);
      final segments = rig.writer.segments;
      expect(segments.length, greaterThanOrEqualTo(3));
      var frames = 0;
      for (final segment in segments) {
        final bytes = rig.bytes(segment.index);
        final check = TsCheck.of(bytes);
        expect(check.problems, isEmpty, reason: segment.name);
        expect(check.firstPids, [0, TsLivePids.pmt, TsLivePids.video], reason: segment.name);
        expect(check.keyStarts.first, 2);
        expect(check.orphans, 0, reason: '${segment.name}: every PES starts in the file it is in');
        frames += check.videoStarts.length;
        final result = rig.remux(async, segment.index);
        expect(result.videoSamples, check.videoStarts.length);
      }
      expect([for (final s in segments.take(2)) s.durationMs], everyElement(2000));
      expect(frames, rig.feed.units);
    });
  });

  test('a new SPS starts a new file at its keyframe; another AAC setup at the next keyframe', () {
    for (final live in [TsLive(otherSpsFromMs: 13000), TsLive(audioRateIndexFromMs: 12500)]) {
      fakeAsync((async) {
        final rig = _Rig(live: live)
          ..record(async, 6)
          ..close(async);
        final segments = rig.writer.segments;
        expect(segments, hasLength(2));
        final first = TsCheck.of(rig.bytes(1));
        final second = TsCheck.of(rig.bytes(2));
        expect(first.problems, isEmpty);
        expect(second.problems, isEmpty);
        expect((second.videoPts.first - live.base) ~/ 90, 13000);
        expect(rig.gapsJson, isEmpty);
        expect(rig.remux(async, 1).videoSamples, first.videoStarts.length);
        expect(rig.remux(async, 2).videoSamples, second.videoStarts.length);
      });
    }
  });

  test('a new PMT (the audio moved to another PID) cuts to the next keyframe; same streams, same file', () {
    fakeAsync((async) {
      final live = TsLive(audioPidFromMs: 12500);
      final rig = _Rig(live: live)
        ..record(async, 6)
        ..close(async);
      expect(rig.writer.segments, hasLength(1));
      expect(rig.feed.cuts, 1);
      final check = TsCheck.of(rig.bytes(1));
      expect(check.problems, isEmpty);
      final times = [for (final pts in check.videoPts) (pts - live.base) ~/ 90];
      expect(times.where((ms) => ms > 12500 && ms < 13000), isEmpty);
      expect(check.pids, containsAll([TsLivePids.audio, TsLivePids.audio + 0x10]));
      final result = rig.remux(async, 1);
      expect(result.videoSamples, check.videoStarts.length);
      expect(result.audioSamples, check.audioStarts.length * 3, reason: 'the remux follows the audio to its new PID');
    });
  });

  test('AAC frames split across PES: files cut at a reconnection and a split still remux (§8.2, §10)', () {
    fakeAsync((async) {
      final live = TsLive(splitAudio: true, audioFrameSize: 450);
      final rig = _Rig(live: live, split: const Duration(seconds: 3));
      final lostAt = rig.record(async, 5);
      async.elapse(const Duration(seconds: 2));
      rig
        ..record(async, 5, lostAt: lostAt)
        ..close(async);
      expect(rig.writer.segments.length, greaterThanOrEqualTo(3));
      for (final segment in rig.writer.segments) {
        final check = TsCheck.of(rig.bytes(segment.index));
        expect(check.problems, isEmpty, reason: segment.name);
        final result = rig.remux(async, segment.index);
        expect(result.videoSamples, check.videoStarts.length);
        expect(result.audioSamples, greaterThan(0));
      }
    });
  });

  test('a video PID that goes silent does not hold everything back: the last frame is taken as it is', () {
    fakeAsync((async) {
      final live = TsLive(videoUntilMs: 13000);
      final rig = _Rig(live: live, timings: const TsTimings(maxPending: 100))
        ..record(async, 8)
        ..close(async);
      final check = TsCheck.of(rig.bytes(1));
      expect(check.problems, isEmpty);
      expect((check.videoPts.last - live.base) ~/ 90, 12960, reason: 'the last frame is written');
      final audio = check.audioStarts.length;
      expect(audio, greaterThan((18000 - 11000) ~/ 64 - 40), reason: 'audio after the video stopped is written');
      expect(rig.remux(async, 1).audioSamples, audio * 3);
    });
  });

  test('stop waits for the frame being received, then ends with whole units and no gap', () {
    fakeAsync((async) {
      final rig = _Rig()..connect(async);
      async.elapse(const Duration(milliseconds: 14000 - 10013 + 10));
      unawaited(rig.feed.stop(const Duration(seconds: 3)));
      async.elapse(const Duration(milliseconds: 200));
      expect(rig.results, ['done']);
      rig.close(async);
      final check = TsCheck.of(rig.bytes(1));
      expect(check.problems, isEmpty);
      final last = (check.videoPts.last - rig.cdn.live.base) ~/ 90;
      expect(last, 14000, reason: 'the keyframe that was arriving at the stop');
      expect(rig.gapsJson, isEmpty);
    });
  });

  test('a stream without a keyframe in keyframeWait is not recordable (unsupportedProtocol)', () {
    fakeAsync((async) {
      final rig = _Rig(
        live: TsLive(gop: 100000),
        timings: const TsTimings(keyframeWait: Duration(seconds: 5)),
      )..connect(async);
      async.elapse(const Duration(seconds: 7));
      final error = rig.results.single;
      expect(error, isA<RecordException>().having((e) => e.kind, 'kind', RecordErrorKind.unsupportedProtocol));
      expect(rig.writer.segments, isEmpty);
    });
  });

  test('33-bit timestamps wrap: the file time goes on (§8.2)', () {
    fakeAsync((async) {
      // Wraps 2 s after the join.
      final live = TsLive(base: (1 << 33) - 12000 * 90);
      final rig = _Rig(live: live)
        ..record(async, 6)
        ..close(async);
      final check = TsCheck.of(rig.bytes(1));
      expect(check.problems, isEmpty);
      expect(rig.writer.segments.single.durationMs, (check.videoStarts.length - 1) * 40);
      final result = rig.remux(async, 1);
      expect(result.duration.inMilliseconds, closeTo(check.videoStarts.length * 40, 50));
    });
  });

  test('a radio program (audio only) starts at an audio PES; the file time follows PTS', () {
    fakeAsync((async) {
      final rig = _Rig(live: TsLive(video: false))
        ..record(async, 5)
        ..close(async);
      final check = TsCheck.of(rig.bytes(1));
      expect(check.problems, isEmpty);
      expect(check.firstPids, [0, TsLivePids.pmt, TsLivePids.audio]);
      expect(check.videoStarts, isEmpty);
      final segment = rig.writer.segments.single;
      expect(segment.durationMs, (check.audioStarts.length - 1) * 64);
      expect(rig.remux(async, 1).audioSamples, check.audioStarts.length * 3);
    });
  });

  test('MPEG-2 video: keyframes are the frames with a sequence header; other PIDs pass through', () {
    fakeAsync((async) {
      final rig = _Rig(live: TsLive(videoType: 0x02, subtitles: true))
        ..record(async, 5)
        ..close(async);
      final check = TsCheck.of(rig.bytes(1));
      expect(check.problems, isEmpty);
      expect(check.firstPids, [0, TsLivePids.pmt, TsLivePids.video]);
      expect(check.pids, contains(TsLivePids.subtitles));
      expect(rig.feed.units, check.videoStarts.length);
    });
  });
}
