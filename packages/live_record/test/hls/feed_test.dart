import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import '../support/fake_hls.dart';

final class _Rig {
  new(
    this.server, {
    StreamLine? line,
    Future<StreamLine> Function(StreamLine current)? renew,
    HlsFeedState? state,
    Duration readTimeout = const Duration(seconds: 15),
    HlsTimings timings = const HlsTimings(),
  }) : state = state ?? HlsFeedState(),
       started = clock.now() {
    feed = HlsFeed(
      line: line ?? server.line(),
      client: server,
      sink: sink,
      state: this.state,
      renew: renew,
      readTimeout: readTimeout,
      timings: timings,
    );
    unawaited(
      feed.run().then(
        (_) => done = true,
        onError: (Object caught) {
          error = caught;
          done = true;
        },
      ),
    );
  }

  final FakeHlsServer server;
  final sink = RecordingSink();
  final HlsFeedState state;
  final DateTime started;
  late final HlsFeed feed;
  bool done = false;
  Object? error;

  /// Seconds since the rig started of each playlist request.
  List<double> get playlistTimes => [
    for (final request in server.requested('.m3u8')) request.at.difference(started).inMilliseconds / 1000,
  ];
}

void main() {
  group('playlist pace (RFC 8216 §6.3.4, REG-RECORD-026)', () {
    test('first request at once; one target duration after a change, half after none', () {
      fakeAsync((async) {
        final rig = _Rig(FakeHlsServer());
        async.elapse(const Duration(milliseconds: 6100));
        rig.server.frozen = true;
        async.elapse(const Duration(milliseconds: 5000));
        expect(rig.playlistTimes, [0, 2, 4, 6, 8, 9, 10, 11]);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('timed from the request start: a slow answer adds no wait, requests never overlap', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..latency = const Duration(milliseconds: 2700);
        final rig = _Rig(server, readTimeout: const Duration(seconds: 60));
        async.elapse(const Duration(milliseconds: 11000));
        expect(rig.playlistTimes, [0, 2.7, 5.4, 8.1, 10.8]);
        expect(server.maxPlaylistInFlight, 1);
        expect(rig.sink.sequences, isNotEmpty);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });
  });

  group('segments (§7.3, §7.4)', () {
    test('starts three segments from the live edge; each segment once, in order', () {
      fakeAsync((async) {
        final rig = _Rig(FakeHlsServer());
        async.elapse(const Duration(seconds: 20));
        final sequences = rig.sink.sequences;
        expect(sequences.first, 102, reason: 'window 100–104: start at 102');
        expect(sequences, List.generate(sequences.length, (i) => 102 + i));
        expect(rig.server.segmentRequests.toSet().length, rig.server.segmentRequests.length, reason: 'no refetch');
        expect(rig.sink.missing, isEmpty);
        expect(rig.state.lastSequence, sequences.last);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('at most two downloads at once; the writer holding back holds the downloads', () {
      fakeAsync((async) {
        final server = FakeHlsServer(window: 8)..latency = const Duration(milliseconds: 300);
        final gate = Completer<void>();
        final rig = _Rig(server);
        rig.sink.gate = gate.future;
        async.elapse(const Duration(seconds: 3));
        expect(server.maxSegmentInFlight, lessThanOrEqualTo(2));
        expect(server.segmentRequests, hasLength(2), reason: 'the first waits for the writer, one more is ready');
        gate.complete();
        rig.sink.gate = null;
        async.elapse(const Duration(seconds: 3));
        expect(rig.sink.sequences.length, greaterThanOrEqualTo(3));
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a failing segment is retried twice, then recorded as a gap with its sequence', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..missing.add(106);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 14));
        expect(server.segmentRequests.where((seq) => seq == 106), hasLength(3));
        expect(rig.sink.sequences, isNot(contains(106)));
        final gap = rig.sink.missing.single;
        expect((gap.reason, gap.fromSeq, gap.toSeq, gap.missingMs), (GapReason.http4xx, 106, 106, 2000));
        expect(rig.sink.sequences, containsAllInOrder([105, 107]));
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('segments failing three times in a row end the connection', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..statusAll['.ts'] = 403;
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 20));
        expect(rig.done, isTrue);
        expect(rig.error, isA<UpstreamStatusException>());
      });
    });

    test('a jump in the sequence (segments gone while away) is a gap with fromSeq/toSeq (§7.4)', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final state = HlsFeedState();
        final first = _Rig(server, state: state);
        async.elapse(const Duration(seconds: 5));
        first.feed.cancel();
        async.flushMicrotasks();
        final last = state.lastSequence!;
        // Away for 20 s: the 5-segment window moved on by 10 segments.
        async.elapse(const Duration(seconds: 20));
        final second = _Rig(server, state: state);
        async.elapse(const Duration(seconds: 3));
        final gap = second.sink.missing.single;
        expect(gap.reason, GapReason.sequenceJump);
        expect(gap.fromSeq, last + 1);
        final firstListed = second.sink.sequences.first;
        expect(gap.toSeq, firstListed - 1, reason: 'from the oldest segment still listed');
        expect(gap.missingMs, (firstListed - last - 1) * 2000);
        second.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a reconnection within the window continues without a gap or a duplicate', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final state = HlsFeedState();
        final first = _Rig(server, state: state);
        async.elapse(const Duration(seconds: 5));
        first.feed.cancel();
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 4));
        final second = _Rig(server, state: state);
        async.elapse(const Duration(seconds: 3));
        expect(second.sink.missing, isEmpty);
        expect(second.sink.sequences.first, first.sink.sequences.last + 1);
        second.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a restarted numbering is a reset gap; recording goes on from the new live edge', () {
      fakeAsync((async) {
        final server = FakeHlsServer(firstSequence: 5000);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 6));
        server.shift = -4990;
        async.elapse(const Duration(seconds: 12));
        final reset = rig.sink.missing.where((gap) => gap.reason == GapReason.reset).single;
        expect(reset.fromSeq, isNull);
        final sequences = rig.sink.sequences;
        final restart = sequences.indexWhere((seq) => seq < 5000);
        expect(restart, greaterThan(0));
        expect(sequences.sublist(restart), List.generate(sequences.length - restart, (i) => sequences[restart] + i));
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('EXT-X-GAP segments are not requested and are recorded as missing', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..gaps.add(106);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 12));
        expect(server.segmentRequests, isNot(contains(106)));
        expect(rig.sink.missing.single.fromSeq, 106);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('EXT-X-ENDLIST: everything listed is written, then the run ends', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..ended = true;
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 2));
        expect(rig.done, isTrue);
        expect(rig.error, isNull);
        expect(rig.sink.sequences, [102, 103, 104]);
      });
    });

    test('no new segment for four target durations (or record.readTimeout) ends the connection', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 3));
        server.frozen = true;
        async.elapse(const Duration(seconds: 14));
        expect(rig.done, isFalse);
        async.elapse(const Duration(seconds: 3));
        expect(rig.done, isTrue);
        expect(rig.error, isA<TimeoutException>());
      });
    });
  });

  group('content', () {
    test('AES-128 with the sequence number as IV: decrypted, the key fetched once and kept in memory', () {
      fakeAsync((async) {
        final key = Uint8List.fromList(List.generate(16, (i) => i * 3));
        final server = FakeHlsServer(key: key);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 8));
        expect(rig.sink.media, isNotEmpty);
        for (final media in rig.sink.media) {
          expect(media.data, server.segmentBytes(media.sequence));
        }
        expect(server.requests.where((r) => r.url.host == 'keys.test'), hasLength(1));
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('AES-128 with an explicit IV', () {
      fakeAsync((async) {
        final server = FakeHlsServer(key: Uint8List(16)..[5] = 9, explicitIv: true);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 4));
        expect(rig.sink.media.first.data, server.segmentBytes(rig.sink.media.first.sequence));
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('SAMPLE-AES cannot be recorded (unsupportedProtocol)', () {
      fakeAsync((async) {
        final server = FakeHlsServer(key: Uint8List(16))..keyMethod = 'SAMPLE-AES';
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 2));
        expect((rig.error! as RecordException).kind, RecordErrorKind.unsupportedProtocol);
        expect(server.segmentRequests, isEmpty);
      });
    });

    test('byte ranges: each segment is asked for with its absolute range', () {
      fakeAsync((async) {
        final server = FakeHlsServer(byteRange: true);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 8));
        expect(rig.sink.media, isNotEmpty);
        for (final media in rig.sink.media) {
          expect(media.data, server.segmentBytes(media.sequence));
        }
        expect(server.requested('all.ts').every((r) => r.range != null), isTrue);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('fMP4: the initialisation section is fetched once and goes with every segment', () {
      fakeAsync((async) {
        final server = FakeHlsServer(fmp4: true);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 8));
        expect(server.requested('init.mp4'), hasLength(1));
        final inits = rig.sink.media.map((media) => media.init).toSet();
        expect(inits, hasLength(1));
        expect(inits.single, fmp4Init);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('LL-HLS: only whole parent segments, never parts or preload hints', () {
      fakeAsync((async) {
        final server = FakeHlsServer(lowLatency: true);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 8));
        expect(rig.sink.media, isNotEmpty);
        expect(server.requests.where((r) => r.url.path.contains('/part/')), isEmpty);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a master playlist: the best variant is recorded and then polled directly', () {
      fakeAsync((async) {
        final server = FakeHlsServer(master: true);
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 6));
        expect(server.requested('master.m3u8'), hasLength(1));
        expect(server.requested('low.m3u8'), isEmpty);
        expect(server.requested('index.m3u8').length, greaterThan(1));
        expect(rig.sink.media, isNotEmpty);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a master with a separate audio rendition is not recorded yet (unsupportedProtocol)', () {
      fakeAsync((async) {
        final rig = _Rig(FakeHlsServer(master: true, separateAudio: true));
        async.elapse(const Duration(seconds: 1));
        expect((rig.error! as RecordException).kind, RecordErrorKind.unsupportedProtocol);
      });
    });
  });

  group('failures and renewal (§7.2, §7.6)', () {
    test('a refused playlist is renewed once through the adapter; the new address continues the numbering', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        var renewals = 0;
        final rig = _Rig(
          server,
          renew: (current) async {
            renewals++;
            server.failures.remove('index.m3u8');
            return server.line(at: server.url.replace(queryParameters: {'renewed': '$renewals'}));
          },
        );
        async.elapse(const Duration(seconds: 5));
        server.failures['index.m3u8'] = [403];
        async.elapse(const Duration(seconds: 6));
        expect(renewals, 1);
        expect(server.requested('.m3u8').last.url.queryParameters['renewed'], '1');
        expect(rig.sink.missing, isEmpty, reason: 'same numbering: no gap');
        expect(rig.done, isFalse);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a refusal the renewal does not fix ends the connection with the 4xx', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final rig = _Rig(server, renew: (current) async => current);
        async.elapse(const Duration(seconds: 3));
        server.statusAll['index.m3u8'] = 404;
        async.elapse(const Duration(seconds: 4));
        expect(rig.error, isA<UpstreamStatusException>().having((e) => e.status, 'status', 404));
      });
    });

    test('three playlist failures in a row end the connection; fewer do not', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 3));
        server.failures['index.m3u8'] = [const SocketException('reset'), 503];
        async.elapse(const Duration(seconds: 6));
        expect(rig.done, isFalse);
        server.failures['index.m3u8'] = [503, 503, 503];
        async.elapse(const Duration(seconds: 6));
        expect(rig.error, isA<UpstreamStatusException>().having((e) => e.status, 'status', 503));
      });
    });

    test('a delta update (EXT-X-SKIP) counts as a failed request', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final rig = _Rig(server);
        async.elapse(const Duration(seconds: 3));
        server.failures['index.m3u8'] = [const FormatException('LL-HLS delta update (EXT-X-SKIP)')];
        async.elapse(const Duration(seconds: 6));
        expect(rig.done, isFalse);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });

    test('a lease renews the address at refreshAt; the next poll uses it (§7.6)', () {
      fakeAsync((async) {
        final server = FakeHlsServer();
        final start = clock.now();
        final rig = _Rig(
          server,
          line: server.line(lease: Lease(refreshAt: start.add(const Duration(seconds: 7)), cutsConnection: false)),
          renew: (current) async => server.line(at: server.url.replace(queryParameters: {'lease': '2'})),
        );
        async.elapse(const Duration(seconds: 12));
        final times = [
          for (final request in server.requested('.m3u8'))
            if (request.url.queryParameters['lease'] == '2') request.at.difference(start).inSeconds,
        ];
        expect(times.first, 8);
        expect(rig.sink.missing, isEmpty);
        rig.feed.cancel();
        async.flushMicrotasks();
      });
    });
  });

  group('stop (§7.8)', () {
    test('no more requests; a download in flight finishes and is written', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..latency = const Duration(milliseconds: 1500);
        final rig = _Rig(server, readTimeout: const Duration(seconds: 60));
        async.elapse(const Duration(milliseconds: 4200));
        final before = server.requests.length;
        final inFlight = server.inFlight;
        unawaited(rig.feed.stop());
        async.elapse(const Duration(seconds: 3));
        expect(server.requests.length, before, reason: 'frozen');
        expect(inFlight, greaterThan(0));
        expect(server.inFlight, 0);
        expect(rig.done, isTrue);
        expect(rig.sink.missing.where((gap) => gap.reason == GapReason.stop), isEmpty);
      });
    });

    test('downloads not done within one target duration are dropped as a stop gap', () {
      fakeAsync((async) {
        final server = FakeHlsServer()..latency = const Duration(milliseconds: 1500);
        final rig = _Rig(server, readTimeout: const Duration(seconds: 60));
        async.elapse(const Duration(milliseconds: 4200));
        server.latency = const Duration(seconds: 30);
        async.elapse(const Duration(milliseconds: 2000));
        unawaited(rig.feed.stop());
        async.elapse(const Duration(seconds: 3));
        expect(rig.done, isTrue);
        final stop = rig.sink.missing.where((gap) => gap.reason == GapReason.stop).single;
        expect(stop.fromSeq, isNotNull);
        expect(stop.missingMs, greaterThanOrEqualTo(2000));
      });
    });
  });

  group('cookies (§7.7)', () {
    test('kept per origin, never sent to another host; expired ones removed; limits', () {
      final jar = HlsCookieJar();
      final a = Uri.parse('https://cdn-a.test/live/index.m3u8');
      jar.store(a, ['lvhls_ssid_1=abc; Path=/live/; Max-Age=600', 'x=1']);
      expect(jar.header(Uri.parse('https://cdn-a.test/live/seg/1.ts')), 'lvhls_ssid_1=abc; x=1');
      expect(jar.header(Uri.parse('https://cdn-b.test/live/seg/1.ts')), isNull);
      expect(jar.header(Uri.parse('http://cdn-a.test/live/seg/1.ts')), isNull, reason: 'another scheme and port');
      jar.store(a, ['x=; Max-Age=0']);
      expect(jar.header(a), 'lvhls_ssid_1=abc');
      jar.store(a, ['big=${'v' * 5000}']);
      expect(jar.header(a), 'lvhls_ssid_1=abc', reason: 'over 4 KiB');
      jar.store(a, [for (var i = 0; i < 70; i++) 'c$i=$i']);
      expect(jar.header(a)!.split('; '), hasLength(64));
    });
  });
}
