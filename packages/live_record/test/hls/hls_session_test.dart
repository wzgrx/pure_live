import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';
import '../support/fake_live.dart';

/// Routes HLS requests to a fake server per CDN host (`hw.cdn.test`…).
final class _Hosts implements HlsClient {
  new(this.servers);

  final Map<String, FakeHlsServer> servers;
  bool closed = false;

  @override
  Future<HlsResponse> get(HlsRequest request) {
    final host = request.url.host;
    final server = servers[host.split('.').first] ?? servers.values.first;
    return server.get(request);
  }

  @override
  void close() => closed = true;
}

final class _Rig {
  new({
    FakeRooms? rooms,
    FakeCdn? cdn,
    Map<String, FakeHlsServer>? servers,
    RecordSettings settings = const RecordSettings(),
  }) : rooms = rooms ?? (FakeRooms(lines: const ['hw'])..formats['hw'] = StreamFormat.hls),
       cdn = cdn ?? FakeCdn(),
       hls = _Hosts(servers ?? {'hw': FakeHlsServer()}) {
    layout = SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', clock.now());
    session = RecordSession(
      room: RoomRef('douyu', '9999'),
      rooms: this.rooms,
      layout: layout,
      files: files,
      settings: settings,
      opener: this.cdn.open,
      hls: hls,
      onPhase: phases.add,
      onRetry: (failure, delay) => retries.add((failure.kind, delay)),
    );
    unawaited(session.run().then((value) => result = value));
  }

  final FakeRooms rooms;
  final FakeCdn cdn;
  final _Hosts hls;
  final files = MemoryRecordFiles();
  late final SessionLayout layout;
  late final RecordSession session;
  SessionResult? result;
  final phases = <SessionPhase>[];
  final retries = <(RecordErrorKind, Duration)>[];

  FakeHlsServer get server => hls.servers.values.first;

  List<Map<String, Object?>> get gaps =>
      ((jsonDecode(utf8.decode(files.bytesOf(layout.gaps)!)) as Map<String, Object?>)['gaps']! as List<Object?>)
          .cast<Map<String, Object?>>();

  void stop(FakeAsync async) {
    unawaited(session.stop());
    async.elapse(const Duration(seconds: 3));
  }
}

void main() {
  test('an HLS-only room is recorded into one .ts: whole segments in order, no gaps (§7, §8)', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.elapse(const Duration(seconds: 20));
      expect(rig.phases, [SessionPhase.resolving, SessionPhase.recording]);
      final progress = rig.session.progress;
      expect(progress.bytes, greaterThan(0));
      expect(progress.media, greaterThanOrEqualTo(const Duration(seconds: 18)));
      expect(progress.line, 'hw');
      rig.stop(async);
      final result = rig.result!;
      expect(result.end, SessionEnd.stopped);
      final path = rig.layout.segment(1, extension: 'ts');
      expect(result.segments.single.path, path);
      final sequences = [for (var seq = 102; seq < 102 + result.segments.single.durationMs ~/ 2000; seq++) seq];
      expect(rig.files.bytesOf(path), [for (final seq in sequences) ...rig.server.segmentBytes(seq)]);
      expect(rig.gaps, isEmpty);
      expect(rig.files.paths.where((p) => p.endsWith('.part')), isEmpty);
    });
  });

  test('FLV lines come first; HLS lines are used when the FLV ones fail before media (§4.3)', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..formats['ws'] = StreamFormat.hls;
      final cdn = FakeCdn()..statusAll = 404;
      final rig = _Rig(rooms: rooms, cdn: cdn, servers: {'ws': FakeHlsServer()});
      async.elapse(const Duration(seconds: 10));
      expect(cdn.opened, isNotEmpty, reason: 'the FLV line was tried first');
      expect(rig.phases.last, SessionPhase.recording);
      rig.stop(async);
      expect(rig.result!.segments.single.name, endsWith('_001.ts'));
    });
  });

  test('a switch from an FLV line to an HLS line closes the FLV file; numbering continues', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..formats['ws'] = StreamFormat.hls;
      final cdn = FakeCdn();
      final rig = _Rig(rooms: rooms, cdn: cdn, servers: {'ws': FakeHlsServer()});
      async.elapse(const Duration(seconds: 20));
      expect(rig.session.segments.single.name, endsWith('_001.flv'));
      // The FLV CDN refuses every new connection from now on.
      cdn
        ..statusAll = 403
        ..cutAll();
      async.elapse(const Duration(seconds: 30));
      rig.stop(async);
      final names = [for (final segment in rig.result!.segments) segment.name.split('_').last];
      expect(names, ['001.flv', '002.ts']);
      expect(rig.result!.segments.every((segment) => segment.closed), isTrue);
    });
  });

  test('a playlist that keeps failing ends the connection; the reconnection continues the file without a gap', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.elapse(const Duration(seconds: 10));
      rig.server.failures['index.m3u8'] = [503, 503, 503];
      async.elapse(const Duration(seconds: 20));
      expect(rig.session.progress.connections, 2);
      expect(rig.retries.first.$1, RecordErrorKind.upstreamEof, reason: 'media was recorded: fast reconnect');
      rig.stop(async);
      expect(rig.result!.segments, hasLength(1));
      expect(rig.gaps, isEmpty, reason: 'the playlist window still held the next segment');
    });
  });

  test('the playlist ends (EXT-X-ENDLIST) and the strict check says offline: the session ends', () {
    fakeAsync((async) {
      final rig = _Rig();
      async.elapse(const Duration(seconds: 10));
      rig.server.ended = true;
      rig.rooms.live = false;
      async.elapse(const Duration(seconds: 10));
      expect(rig.result?.end, SessionEnd.offline);
      expect(rig.result!.segments.single.closed, isTrue);
    });
  });

  test('a line that cannot be recorded (SAMPLE-AES) moves to the next line; all such lines fail the session', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..formats.addAll({'hw': StreamFormat.hls, 'ws': StreamFormat.hls});
      final encrypted = FakeHlsServer(key: Uint8List(16))..keyMethod = 'SAMPLE-AES';
      final rig = _Rig(rooms: rooms, servers: {'hw': encrypted, 'ws': FakeHlsServer()});
      async.elapse(const Duration(seconds: 10));
      expect(rig.phases.last, SessionPhase.recording);
      expect(rig.session.progress.line, 'ws');
      rig.stop(async);

      final both = FakeRooms()..formats.addAll({'hw': StreamFormat.hls, 'ws': StreamFormat.hls});
      final failing = _Rig(
        rooms: both,
        servers: {
          'hw': FakeHlsServer(key: Uint8List(16))..keyMethod = 'SAMPLE-AES',
          'ws': FakeHlsServer(key: Uint8List(16))..keyMethod = 'SAMPLE-AES',
        },
      );
      async.elapse(const Duration(seconds: 10));
      expect(failing.result?.end, SessionEnd.failed);
      expect(failing.result?.failure?.kind, RecordErrorKind.unsupportedProtocol);
    });
  });

  test('without an HLS client HLS lines are not recordable (unsupportedProtocol)', () {
    fakeAsync((async) {
      final rooms = FakeRooms()..formats.addAll({'hw': StreamFormat.hls, 'ws': StreamFormat.hls});
      SessionResult? result;
      unawaited(
        RecordSession(
          room: RoomRef('douyu', '9999'),
          rooms: rooms,
          layout: SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播', clock.now()),
          files: MemoryRecordFiles(),
          settings: const RecordSettings(),
          opener: FakeCdn().open,
        ).run().then((value) => result = value),
      );
      async.elapse(const Duration(seconds: 1));
      expect(result?.failure?.kind, RecordErrorKind.unsupportedProtocol);
    });
  });

  test('AES-128 segments land decrypted on disk; the key never does (§13)', () {
    fakeAsync((async) {
      final key = Uint8List.fromList(List.generate(16, (i) => 0xC0 + i));
      final server = FakeHlsServer(key: key);
      final rig = _Rig(servers: {'hw': server});
      async.elapse(const Duration(seconds: 10));
      rig.stop(async);
      final file = rig.files.bytesOf(rig.result!.segments.single.path)!;
      expect(file.sublist(0, server.segmentBytes(102).length), server.segmentBytes(102));
      for (final path in rig.files.paths) {
        final bytes = rig.files.bytesOf(path)!;
        for (var i = 0; i + 16 <= bytes.length; i++) {
          var same = true;
          for (var j = 0; j < 16 && same; j++) {
            same = bytes[i + j] == key[j];
          }
          expect(same, isFalse, reason: 'the key is not in $path');
        }
      }
    });
  });

  test('the recorded .ts remuxes to MP4 (§10)', () async {
    final files = MemoryRecordFiles();
    final ts = [for (var seq = 102; seq < 110; seq++) ...FakeHlsServer().segmentBytes(seq)];
    files.put('/rec/a_001.ts', ts);
    final result = await remuxRecording(files: files, input: '/rec/a_001.ts', output: '/rec/a_001.mp4');
    expect(result.videoSamples, 8 * 3);
    expect(result.audioSamples, 8 * 2);
    expect(result.duration.inMilliseconds, closeTo(16000, 100));
  });
}
