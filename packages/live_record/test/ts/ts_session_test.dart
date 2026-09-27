import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';
import '../support/fake_live.dart';
import '../support/ts_check.dart';
import '../support/ts_live.dart';

/// An FLV connection of [FakeCdn] as bytes: a single HTTP stream that is FLV.
final class _FlvBytes implements ByteSource {
  new(this._inner);

  final FlvPacketSource _inner;

  @override
  Future<Uint8List?> next() => _inner.next();

  @override
  Future<void> cancel() => _inner.cancel();
}

/// Serves the playlist of [server] for any address (an IPTV list URL without `.m3u8`).
final class _AnyPlaylist implements HlsClient {
  new(this.server);

  final FakeHlsServer server;

  @override
  Future<HlsResponse> get(HlsRequest request) {
    final url = request.url;
    final mapped = url.path.endsWith('.m3u8') || url.path.contains('/seg/')
        ? url
        : url.replace(path: '/live/index.m3u8');
    return server.get(
      HlsRequest(
        url: mapped,
        headers: request.headers,
        range: request.range,
        maxBytes: request.maxBytes,
        cancel: request.cancel,
      ),
    );
  }

  @override
  void close() {}
}

final class _Rig {
  new({
    required this.rooms,
    Map<String, ByteSourceOpener>? streams,
    FakeCdn? flv,
    HlsClient? hls,
    bool noStream = false,
    RecordSettings settings = const RecordSettings(),
  }) : flv = flv ?? FakeCdn(),
       streams = streams ?? {} {
    layout = SessionLayout.at('/rec', RoomRef('iptv', 'CCTV-1'), 'CCTV-1', clock.now());
    session = RecordSession(
      room: RoomRef('iptv', 'CCTV-1'),
      rooms: rooms,
      layout: layout,
      files: files,
      settings: settings,
      opener: this.flv.open,
      hls: hls,
      stream: noStream ? null : _open,
      onPhase: phases.add,
      onRetry: (failure, delay) => retries.add((failure.kind, delay)),
    );
    unawaited(session.run().then((value) => result = value));
  }

  final FakeRooms rooms;
  final FakeCdn flv;
  final Map<String, ByteSourceOpener> streams;
  final files = MemoryRecordFiles();
  late final SessionLayout layout;
  late final RecordSession session;
  SessionResult? result;
  final phases = <SessionPhase>[];
  final retries = <(RecordErrorKind, Duration)>[];
  final opened = <String>[];

  Future<ByteSource> _open(StreamLine line) {
    final host = line.url.host.split('.').first;
    opened.add(host);
    return streams[host]!(line);
  }

  List<Map<String, Object?>> get gaps =>
      ((jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>)['gaps']! as List<Object?>)
          .cast<Map<String, Object?>>();

  void stop(FakeAsync async) {
    unawaited(session.stop());
    async.elapse(const Duration(seconds: 3));
  }

  RemuxResult remux(FakeAsync async, String path) {
    RemuxResult? value;
    Object? error;
    unawaited(
      remuxRecording(
        files: files,
        input: path,
        output: '$path.mp4',
      ).then((r) => value = r, onError: (Object e) => error = e),
    );
    async.flushMicrotasks();
    if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
    return value!;
  }
}

FakeRooms _rooms(Map<String, StreamFormat> lines) => FakeRooms(lines: lines.keys.toList())..formats.addAll(lines);

void main() {
  test('an IPTV line of continuous MPEG-TS is recorded into one .ts (§8)', () {
    fakeAsync((async) {
      final cdn = FakeTsCdn();
      final rig = _Rig(rooms: _rooms({'udpxy': StreamFormat.other}), streams: {'udpxy': cdn.open});
      async.elapse(const Duration(seconds: 20));
      expect(rig.phases, [SessionPhase.resolving, SessionPhase.recording]);
      final progress = rig.session.progress;
      expect(progress.media, greaterThanOrEqualTo(const Duration(seconds: 18)));
      expect(progress.line, 'udpxy');
      rig.stop(async);
      final result = rig.result!;
      expect(result.end, SessionEnd.stopped);
      final segment = result.segments.single;
      expect(segment.name, endsWith('_001.ts'));
      final check = TsCheck.of(rig.files.bytesOf(segment.path)!);
      expect(check.problems, isEmpty);
      expect(check.firstPids, [0, TsLivePids.pmt, TsLivePids.video]);
      expect(rig.gaps, isEmpty);
      expect(rig.files.paths.where((path) => path.endsWith('.part')), isEmpty);
      expect(rig.remux(async, segment.path).videoSamples, check.videoStarts.length);
    });
  });

  test('a lost connection reconnects into the same file with an eof gap (§3, §8.3)', () {
    fakeAsync((async) {
      final cdn = FakeTsCdn();
      final rig = _Rig(rooms: _rooms({'udpxy': StreamFormat.other}), streams: {'udpxy': cdn.open});
      async.elapse(const Duration(seconds: 10));
      cdn.cutAll();
      async.elapse(const Duration(seconds: 10));
      expect(rig.phases, [
        SessionPhase.resolving,
        SessionPhase.recording,
        SessionPhase.reconnecting,
        SessionPhase.recording,
      ]);
      expect(rig.retries.single.$1, RecordErrorKind.upstreamEof);
      rig.stop(async);
      final segment = rig.result!.segments.single;
      expect(rig.session.progress.connections, 2);
      final check = TsCheck.of(rig.files.bytesOf(segment.path)!);
      expect(check.problems, isEmpty);
      final gap = rig.gaps.single;
      expect((gap['reason'], gap['source'], gap['part']), ('eof', 'ts', segment.name));
      expect(gap['missingMs']! as int, greaterThan(2000));
      expect(rig.remux(async, segment.path).videoSamples, check.videoStarts.length);
    });
  });

  test('a single HTTP stream that is FLV is recorded as FLV, reconnections sniff again (§8.1)', () {
    fakeAsync((async) {
      final cdn = FakeCdn();
      final rig = _Rig(
        rooms: _rooms({'flvline': StreamFormat.other}),
        streams: {'flvline': (line) async => _FlvBytes(await cdn.open(line))},
      );
      async.elapse(const Duration(seconds: 10));
      cdn.cutAll();
      async.elapse(const Duration(seconds: 5));
      rig.stop(async);
      final segment = rig.result!.segments.single;
      expect(segment.name, endsWith('_001.flv'));
      expect(cdn.connections.length, 2, reason: 'the splicer reconnected through the sniff');
      final file = FlvFile(rig.files.bytesOf(segment.path)!);
      expect(file.video, isNotEmpty);
      expect(rig.opened, ['flvline', 'flvline']);
    });
  });

  test('a single HTTP stream that is an HLS playlist is recorded as HLS (§8.1)', () {
    fakeAsync((async) {
      final server = FakeHlsServer();
      final rig = _Rig(
        rooms: _rooms({'list': StreamFormat.other}),
        streams: {
          'list': (line) async => ListByteSource([Uint8List.fromList(utf8.encode('#EXTM3U\n#EXT-X-VERSION:3\n'))]),
        },
        hls: _AnyPlaylist(server),
      );
      async.elapse(const Duration(seconds: 20));
      rig.stop(async);
      final segment = rig.result!.segments.single;
      expect(segment.name, endsWith('_001.ts'));
      expect(rig.files.bytesOf(segment.path), [
        for (var seq = 102; seq < 102 + segment.durationMs ~/ 2000; seq++) ...server.segmentBytes(seq),
      ]);
    });
  });

  test('content that is not FLV, TS or HLS moves to the next line; only such lines fail the session (§21)', () {
    fakeAsync((async) {
      final cdn = FakeTsCdn();
      final page = Uint8List.fromList(utf8.encode('<html>${'x' * 2000}</html>'));
      final rig = _Rig(
        rooms: _rooms({'web': StreamFormat.other, 'udpxy': StreamFormat.other}),
        streams: {
          'web': (line) async => ListByteSource([page]),
          'udpxy': cdn.open,
        },
      );
      async.elapse(const Duration(seconds: 10));
      expect(rig.opened.take(2), ['web', 'udpxy']);
      expect(rig.phases.last, SessionPhase.recording);
      rig.stop(async);
      expect(rig.result!.segments.single.name, endsWith('_001.ts'));
    });
    fakeAsync((async) {
      final page = Uint8List.fromList(utf8.encode('<html>${'x' * 2000}</html>'));
      final rig = _Rig(
        rooms: _rooms({'a': StreamFormat.other, 'b': StreamFormat.other}),
        streams: {
          'a': (line) async => ListByteSource([page]),
          'b': (line) async => ListByteSource([page]),
        },
      );
      async.elapse(const Duration(seconds: 30));
      final result = rig.result!;
      expect(result.end, SessionEnd.failed);
      expect(result.failure!.kind, RecordErrorKind.unsupportedProtocol);
      expect(result.segments, isEmpty);
    });
  });

  test('HTTP 404 on a single stream re-resolves at once like FLV (§11.7)', () {
    fakeAsync((async) {
      final cdn = FakeTsCdn()..statusFor[0] = 404;
      final rig = _Rig(rooms: _rooms({'udpxy': StreamFormat.other}), streams: {'udpxy': cdn.open});
      async.elapse(const Duration(seconds: 10));
      expect(cdn.opened.length, 2);
      expect(rig.phases.last, SessionPhase.recording);
      rig.stop(async);
      expect(rig.result!.segments, hasLength(1));
    });
  });

  test(
    'FLV and single-stream lines come before HLS, in their order; without a stream opener other lines are skipped',
    () {
      fakeAsync((async) {
        final cdn = FakeTsCdn();
        final rig = _Rig(
          rooms: _rooms({'hls': StreamFormat.hls, 'udpxy': StreamFormat.other, 'flv': StreamFormat.flv}),
          streams: {'udpxy': cdn.open},
          hls: FakeHlsServer(),
        );
        async.elapse(const Duration(seconds: 5));
        expect(rig.opened, ['udpxy'], reason: 'the first of the FLV and single-stream lines');
        expect(rig.flv.opened, isEmpty);
        rig.stop(async);
      });
      fakeAsync((async) {
        final rig = _Rig(rooms: _rooms({'udpxy': StreamFormat.other}), noStream: true);
        async.elapse(const Duration(seconds: 5));
        expect(rig.result!.failure!.kind, RecordErrorKind.unsupportedProtocol);
      });
    },
  );
}
