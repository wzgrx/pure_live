import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

void main() {
  test('unrewritten non-HTTP references never become diagnostic resource IDs', () async {
    const marker = 'privatesecret';
    final fixture = await _Fixture.start((request) async {
      request.response.write(
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
        '#EXT-X-KEY:METHOD=AES-128,URI="ftp://127.0.0.1/path/$marker"\n'
        '#EXTINF:2,\nftp://127.0.0.1/path/$marker\n',
      );
      await request.response.close();
    });
    try {
      // Observation neither rewrites nor attempts to fetch unsupported inputs.
      expect(await fixture.text(fixture.relay.inputUri), contains(marker));
      await fixture.relay.close();
      final snapshot = fixture.diagnostics.snapshot();
      expect(jsonEncode(snapshot), isNot(contains(marker)));
      final window = _requests(snapshot).single['manifest'] as Map;
      expect((window['segments'] as List).single['resourceId'], isNull);
      expect(window['children'], isEmpty);
    } finally {
      await fixture.close();
    }
  });

  test('master roles and media windows correlate only through opaque IDs', () async {
    const secret = 'PRIVATE_signed_cookie_title';
    final fixture = await _Fixture.start((request) async {
      request.response.headers.add('Set-Cookie', 'auth=$secret');
      if (request.uri.path == '/root.m3u8') {
        request.response.write(
          '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="$secret",URI="audio.m3u8?token=$secret"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=100,AUDIO="a"\nvideo.m3u8?token=$secret\n',
        );
      } else {
        final offset = request.uri.path == '/audio.m3u8' ? 0 : 10;
        request.response.write(
          '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:${100 + offset}\n'
          '#EXT-X-DISCONTINUITY-SEQUENCE:9\n#EXT-X-TARGETDURATION:2\n'
          '#EXT-X-MAP:URI="init.mp4?token=$secret"\n'
          '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T15:00:${offset.toString().padLeft(2, '0')}+08:00\n'
          '#EXTINF:2,$secret\ns1.m4s?token=$secret\n#EXTINF:2,\ns2.m4s\n#EXT-X-ENDLIST\n',
        );
      }
      await request.response.close();
    });
    try {
      final master = await fixture.text(fixture.relay.inputUri);
      final audio = Uri.parse(RegExp(r'URI="([^"]+)"').firstMatch(master)!.group(1)!);
      final video = Uri.parse(master.split('\n').firstWhere((line) => line.startsWith('http')));
      await fixture.text(audio);
      await fixture.text(video);
      await fixture.relay.close();
      final snapshot = fixture.diagnostics.snapshot();
      final requests = _requests(snapshot);
      expect(requests.length, 3);
      final children = (requests[0]['manifest'] as Map)['children'] as List;
      expect(children.map((child) => child['role']), ['audio', 'variant']);
      expect(children.map((child) => child['resourceId']), requests.skip(1).map((request) => request['resourceId']));
      for (var i = 1; i <= 2; i++) {
        final window = requests[i]['manifest'] as Map;
        expect(window['mediaSequence'], i == 1 ? 100 : 110);
        expect(window['discontinuitySequence'], 9);
        expect(window['durationSeconds'], 4);
        expect(window['targetDuration'], 2);
        expect(window['endList'], true);
        final segments = window['segments'] as List;
        expect(segments[0]['programDateTime'], i == 1 ? '2026-09-09T07:00:00.000Z' : '2026-09-09T07:00:10.000Z');
        expect(segments[1]['programDateTimeExplicit'], false);
        expect(segments[1]['programDateTime'], i == 1 ? '2026-09-09T07:00:02.000Z' : '2026-09-09T07:00:12.000Z');
      }
      final encoded = jsonEncode(snapshot);
      for (final forbidden in [secret, 'http:', 'token=', '127.0.0.1', 'root.m3u8', 'Set-Cookie']) {
        expect(encoded, isNot(contains(forbidden)));
      }
      expect(fixture.relay.resourceCount, 0);
      // The caller owns detached snapshots, not mutable internal records.
      (requests[1]['manifest'] as Map)['segments'] = [];
      expect(((_requests(fixture.diagnostics.snapshot())[1]['manifest'] as Map)['segments'] as List).length, 2);
    } finally {
      await fixture.close();
    }
  });

  test('staged media separates first byte, complete body, and local delivery', () async {
    final release = Completer<void>();
    final fixture = await _Fixture.start((request) async {
      if (request.uri.path == '/root.m3u8') {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nmedia.m4s\n');
      } else {
        request.response.contentLength = 8;
        request.response.bufferOutput = false;
        request.response.add([1, 2, 3, 4]);
        await request.response.flush();
        await release.future;
        request.response.add([5, 6, 7, 8]);
      }
      await request.response.close();
    });
    try {
      final manifest = await fixture.text(fixture.relay.inputUri);
      final media = Uri.parse(manifest.split('\n').firstWhere((line) => line.startsWith('http')));
      var delivered = false;
      final body = fixture.text(media).then((value) {
        delivered = true;
        return value;
      });
      await _until(() => _requests(fixture.diagnostics.snapshot()).last['receivedBytes'] == 4);
      final pending = _requests(fixture.diagnostics.snapshot()).last;
      expect(pending['bodyCompleteMs'], isNull);
      expect(pending['finishedMs'], isNull);
      expect(pending['deliveredMs'], isNull);
      expect(pending['outcome'], 'active');
      expect(delivered, false);
      release.complete();
      expect((await body).codeUnits, [1, 2, 3, 4, 5, 6, 7, 8]);
      await fixture.relay.close();
      final trace = _requests(fixture.diagnostics.snapshot()).last;
      expect(trace['receivedBytes'], 8);
      expect(trace['upstreamStatus'], 200);
      expect(trace['localStatus'], 200);
      final times = [
        'startedMs',
        'headersMs',
        'firstBodyMs',
        'bodyCompleteMs',
        'deliveredMs',
        'finishedMs',
      ].map((key) => trace[key] as int).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i], greaterThanOrEqualTo(times[i - 1]));
      }
    } finally {
      if (!release.isCompleted) release.complete();
      await fixture.close();
    }
  });

  test('request and manifest storage remain bounded with omissions explicit', () async {
    final fixture = await _Fixture.start((request) async {
      request.response.write(
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n${List.generate(80, (i) => '#EXTINF:2,\ns$i.m4s\n').join()}',
      );
      await request.response.close();
    }, maximumRequests: 2);
    try {
      for (var i = 0; i < 5; i++) {
        await fixture.text(fixture.relay.inputUri);
      }
      await fixture.relay.close();
      final snapshot = fixture.diagnostics.snapshot();
      expect(snapshot['omittedRequests'], 3);
      expect(_requests(snapshot).length, 2);
      final window = _requests(snapshot).first['manifest'] as Map;
      expect((window['segments'] as List).length, 64);
      expect(window['segmentCount'], 80);
      expect(window['omittedSegments'], 16);
      expect(window['durationSeconds'], 160);
      expect(HlsRelayDiagnostics(maximumRequests: 100000).maximumRequests, 1024);
      expect(HlsRelayDiagnostics(maximumRequests: 0).maximumRequests, 1);
    } finally {
      await fixture.close();
    }
  });

  test('discontinuity and absent or malformed PDT do not invent wall time', () async {
    final fixture = await _Fixture.start((request) async {
      request.response.write(
        '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T07:00:00Z\n#EXTINF:2,\na.m4s\n'
        '#EXT-X-DISCONTINUITY\n#EXTINF:2,\nb.m4s\n'
        '#EXT-X-PROGRAM-DATE-TIME:PRIVATE_NOT_A_DATE\n#EXTINF:2,\nc.m4s\n',
      );
      await request.response.close();
    });
    try {
      await fixture.text(fixture.relay.inputUri);
      await fixture.relay.close();
      final segments = (_requests(fixture.diagnostics.snapshot()).first['manifest'] as Map)['segments'] as List;
      expect(segments[0]['programDateTime'], isNotNull);
      expect(segments[1]['programDateTime'], isNull);
      expect(segments[2]['programDateTime'], isNull);
      expect(jsonEncode(fixture.diagnostics.snapshot()), isNot(contains('PRIVATE')));
    } finally {
      await fixture.close();
    }
  });

  test('stop retains partial receive timing without marking a whole body', () async {
    final release = Completer<void>();
    final fixture = await _Fixture.start((request) async {
      if (request.uri.path == '/root.m3u8') {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\na.m4s\n');
      } else {
        request.response.contentLength = 8;
        request.response.bufferOutput = false;
        request.response.add([1, 2, 3, 4]);
        await request.response.flush();
        await release.future;
      }
      await request.response.close();
    });
    try {
      final manifest = await fixture.text(fixture.relay.inputUri);
      final media = Uri.parse(manifest.split('\n').firstWhere((line) => line.startsWith('http')));
      final responseFuture = (await fixture.client.getUrl(media)).close();
      await _until(() => _requests(fixture.diagnostics.snapshot()).last['receivedBytes'] == 4);
      await fixture.relay.finish();
      final response = await responseFuture.timeout(const Duration(seconds: 4));
      await response.drain<void>();
      expect(response.statusCode, 410);
      await fixture.text(fixture.relay.inputUri);
      await fixture.relay.close();
      final traces = _requests(fixture.diagnostics.snapshot());
      expect(traces[1]['bodyCompleteMs'], isNull);
      expect(traces[1]['deliveredMs'], isNull);
      expect(traces[1]['outcome'], 'stopped');
      expect(traces[1]['receivedBytes'], 4);
      expect(traces[2]['manifestSource'], 'cached-stop');
      expect((traces[2]['manifest'] as Map)['endList'], true);
    } finally {
      release.complete();
      await fixture.close();
    }
  });
}

List<Map<String, Object?>> _requests(Map<String, Object?> snapshot) =>
    (snapshot['requests'] as List).cast<Map<String, Object?>>();

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 3)) throw StateError('Expected diagnostic phase not observed');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Fixture {
  _Fixture(this.origin, this.subscription, this.relay, this.diagnostics);
  final HttpServer origin;
  final StreamSubscription<HttpRequest> subscription;
  final FFmpegHlsInputRelay relay;
  final HlsRelayDiagnostics diagnostics;
  final HttpClient client = HttpClient()..findProxy = (_) => 'DIRECT';

  static Future<_Fixture> start(Future<void> Function(HttpRequest) handle, {int maximumRequests = 512}) async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = origin.listen((request) async {
      try {
        await handle(request);
      } on Object {
        /* Owned fixture can be closed during stop. */
      }
    });
    final diagnostics = HlsRelayDiagnostics(maximumRequests: maximumRequests);
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
      drainOnStop: true,
      diagnostics: diagnostics,
      findProxy: (_) => 'DIRECT',
    ))!;
    return _Fixture(origin, subscription, relay, diagnostics);
  }

  Future<String> text(Uri uri) async => utf8.decode(
    await (await (await client.getUrl(uri)).close()).fold<List<int>>([], (out, bytes) => out..addAll(bytes)),
  );

  Future<void> close() async {
    client.close(force: true);
    await relay.close();
    await origin.close(force: true);
    await subscription.cancel();
  }
}
