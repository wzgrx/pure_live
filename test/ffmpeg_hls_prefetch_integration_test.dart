import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

Future<(int, List<int>, HttpHeaders)> get(HttpClient client, Uri uri, {String? range, String method = 'GET'}) async {
  final request = await client.openUrl(method, uri);
  if (range != null) request.headers.set('Range', range);
  final response = await request.close();
  final bytes = await response.fold<List<int>>([], (all, part) => all..addAll(part));
  return (response.statusCode, bytes, response.headers);
}

List<Uri> mediaUris(String text) => const LineSplitter()
    .convert(text)
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .map(Uri.parse)
    .toList();

void main() {
  for (final interstitial in [false, true]) {
    test('DATERANGE metadata uses selected cache only; interstitial=$interstitial', () async {
      const tag = '#EXT-X-DATERANGE:ID="event",START-DATE="2026-09-09T00:00:00Z",X-NOTE="one,two"';
      var bodies = 0;
      final paths = <String>[];
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final jobs = <Future<void>>{};
      final sub = origin.listen((request) {
        late Future<void> job;
        job = () async {
          paths.add(request.uri.path);
          if (request.uri.path == '/root.m3u8') {
            request.response.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:1\n'
              '#EXT-X-PROGRAM-DATE-TIME:2026-09-09T00:00:00Z\n'
              '$tag${interstitial ? ',CLASS="com.apple.hls.interstitial",X-ASSET-URI="asset.m3u8"' : ''}\n'
              '#EXTINF:1,\nbody.ts\n#EXT-X-DATERANGE:ID="event",DURATION=1\n#EXT-X-ENDLIST\n',
            );
          } else if (request.uri.path == '/body.ts') {
            bodies++;
            request.response.add([1, 2, 3]);
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        }().whenComplete(() => jobs.remove(job));
        jobs.add(job);
      });
      final relay = (await FFmpegHlsInputRelay.startForArguments(
        ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
        drainOnStop: true,
        enablePrefetch: true,
      ))!;
      final client = HttpClient();
      try {
        final root = await get(client, relay.inputUri);
        expect(root.$1, 200);
        final text = utf8.decode(root.$2);
        expect(relay.prefetchFeedCount, interstitial ? 0 : 1);
        expect(text, contains(tag));
        if (!interstitial) {
          expect(RegExp(r'^#EXT-X-DATERANGE:', multiLine: true).allMatches(text), hasLength(1));
          expect(text, contains('DURATION=1'));
          final uri = mediaUris(text).single;
          expect((await get(client, uri)).$2, [1, 2, 3]);
          await relay.finish();
          expect(utf8.decode((await get(client, relay.inputUri)).$2), text);
          expect((await get(client, uri)).$2, [1, 2, 3]);
          expect(bodies, 1);
        } else {
          expect(bodies, 0);
        }
        expect(paths, isNot(contains('/asset.m3u8')));
      } finally {
        client.close(force: true);
        await relay.close();
        await origin.close(force: true);
        await sub.cancel();
        await Future.wait(jobs.toList());
      }
      expect(relay.prefetchBodyCount, 0);
    });
  }
  for (final delayedHeaders in [false, true]) {
    test('stop preserves published media completing beyond target duration; headers=$delayedHeaders', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final jobs = <Future<void>>{};
      final sub = origin.listen((request) {
        late Future<void> job;
        job = () async {
          try {
            if (request.uri.path.endsWith('.m3u8')) {
              request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nbody.ts\n#EXT-X-ENDLIST\n');
            } else {
              request.response.contentLength = 2;
              if (!delayedHeaders) {
                request.response.add([1]);
                await request.response.flush();
              }
              entered.complete();
              await release.future;
              request.response.add(delayedHeaders ? [1, 2] : [2]);
            }
            await request.response.close();
          } on Object {
            /* Only this fixture's held request may end during teardown. */
          }
        }().whenComplete(() => jobs.remove(job));
        jobs.add(job);
      });
      final relay = (await FFmpegHlsInputRelay.startForArguments(
        ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
        drainOnStop: true,
        enablePrefetch: true,
      ))!;
      final client = HttpClient();
      try {
        final manifest = utf8.decode((await get(client, relay.inputUri)).$2);
        final body = get(client, mediaUris(manifest).single);
        await entered.future.timeout(const Duration(seconds: 3));
        await relay.finish();
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        release.complete();
        final response = await body.timeout(const Duration(seconds: 3));
        expect(response.$1, 200);
        expect(response.$2, [1, 2]);
        expect(relay.inputTailDiscarded, false);
      } finally {
        if (!release.isCompleted) release.complete();
        client.close(force: true);
        await relay.close();
        await origin.close(force: true);
        await sub.cancel();
        await Future.wait(jobs.toList());
      }
      expect(relay.prefetchBodyCount, 0);
      expect(relay.prefetchBytes, 0);
    });
  }
  test('late concurrent root response cannot replace an already selected master generation', () async {
    const master = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nvideo.m3u8\n';
    final firstEntered = Completer<void>();
    final bothEntered = Completer<void>();
    final releaseSecond = Completer<void>();
    var roots = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final jobs = <Future<void>>{};
    final sub = origin.listen((request) {
      late Future<void> job;
      job = () async {
        try {
          if (request.uri.path == '/root.m3u8') {
            final number = ++roots;
            if (number == 1) {
              firstEntered.complete();
              await bothEntered.future;
              request.response.write(master);
            } else {
              bothEntered.complete();
              await releaseSecond.future;
              request.response.write(master.replaceFirst('video.m3u8', 'other.m3u8'));
            }
          } else if (request.uri.path.endsWith('.m3u8')) {
            request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nbody.ts\n#EXT-X-ENDLIST\n');
          } else {
            request.response.write('body');
          }
          await request.response.close();
        } on Object {
          /* Teardown ends only this fixture request. */
        }
      }().whenComplete(() => jobs.remove(job));
      jobs.add(job);
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
      drainOnStop: true,
      enablePrefetch: true,
    ))!;
    final client = HttpClient();
    try {
      final first = get(client, relay.inputUri);
      await firstEntered.future.timeout(const Duration(seconds: 3));
      final second = get(client, relay.inputUri);
      final selected = await first.timeout(const Duration(seconds: 3));
      releaseSecond.complete();
      expect((await second.timeout(const Duration(seconds: 3))).$2, selected.$2);
      expect(relay.prefetchFeedCount, 1);
    } finally {
      if (!bothEntered.isCompleted) bothEntered.complete();
      if (!releaseSecond.isCompleted) releaseSecond.complete();
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await sub.cancel();
      await Future.wait(jobs.toList());
    }
  });
  for (final range in [false, true]) {
    test('production cache keeps byte identity, repeat reads and origin status; ranged=$range', () async {
      var mediaRequests = 0;
      final seenRanges = <String?>[];
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = origin.listen((request) async {
        if (request.uri.path == '/root.m3u8') {
          request.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n'
            '${range ? '#EXT-X-BYTERANGE:3@10\n' : ''}body.bin\n#EXT-X-ENDLIST\n',
          );
        } else {
          mediaRequests++;
          seenRanges.add(request.headers.value('Range'));
          if (range) {
            request.response.statusCode = 206;
            request.response.headers.set('Content-Range', 'bytes 10-12/20');
          }
          request.response.contentLength = 3;
          request.response.add([10, 11, 12]);
        }
        await request.response.close();
      });
      final relay = (await FFmpegHlsInputRelay.startForArguments(
        ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
        drainOnStop: true,
        enablePrefetch: true,
      ))!;
      final client = HttpClient();
      try {
        final manifest = utf8.decode((await get(client, relay.inputUri)).$2);
        expect(relay.prefetchFeedCount, 1);
        final uri = mediaUris(manifest).single;
        for (var i = 0; i < 2; i++) {
          final response = await get(client, uri, range: range ? 'bytes=10-12' : 'bytes=0-');
          expect(response.$1, range ? 206 : 200);
          expect(response.$2, [10, 11, 12]);
          expect(response.$3.value('Content-Range'), range ? 'bytes 10-12/20' : null);
        }
        expect(mediaRequests, 1);
        expect(seenRanges, [range ? 'bytes=10-12' : null]);
        if (range) {
          expect((await get(client, uri, range: 'bytes=0-2')).$1, 416);
        }
        for (final headRange in [null, 'bytes=10-12', 'bytes=0-2']) {
          final head = await get(client, uri, method: 'HEAD', range: headRange);
          expect(head.$1, 200);
          expect(head.$2, isEmpty);
          expect(head.$3.value('Content-Length'), range ? '20' : '3');
          expect(head.$3.value('Content-Range'), isNull);
        }
      } finally {
        client.close(force: true);
        await relay.close();
        await origin.close(force: true);
        await subscription.cancel();
      }
      expect(relay.prefetchBodyCount, 0);
      expect(relay.prefetchBytes, 0);
    });
  }
  test('oversized initial finite playlist keeps every segment in the original path', () async {
    var bodies = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = origin.listen((request) async {
      if (request.uri.path == '/root.m3u8') {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n');
        for (var i = 0; i < 65; i++) {
          request.response.write('#EXTINF:1,\nbody$i.ts\n');
        }
        request.response.write('#EXT-X-ENDLIST\n');
      } else {
        bodies++;
        request.response.write('body');
      }
      await request.response.close();
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
      drainOnStop: true,
      enablePrefetch: true,
    ))!;
    final client = HttpClient();
    try {
      final root = await get(client, relay.inputUri);
      expect(root.$1, 200);
      expect(mediaUris(utf8.decode(root.$2)), hasLength(65));
      expect(relay.prefetchFeedCount, 0);
      expect(relay.prefetchBodyCount, 0);
      expect(bodies, 0);
      expect(utf8.decode((await get(client, mediaUris(utf8.decode(root.$2)).first)).$2), 'body');
    } finally {
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await sub.cancel();
    }
  });
  test('unsupported second rendition leaves both in original relay path before any media download', () async {
    var bodies = 0;
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = origin.listen((request) async {
      if (request.uri.path == '/root.m3u8') {
        request.response.write(
          '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="a",URI="audio.m3u8"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a"\nvideo.m3u8\n',
        );
      } else if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(
          '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nbody.ts\n'
          '${request.uri.path == '/audio.m3u8' ? '#EXT-X-PART:DURATION=0.1,URI="part.ts"\n' : ''}',
        );
      } else {
        bodies++;
        request.response.write('body');
      }
      await request.response.close();
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
      drainOnStop: true,
      enablePrefetch: true,
    ))!;
    final client = HttpClient();
    try {
      final root = await get(client, relay.inputUri);
      expect(root.$1, 200);
      expect(utf8.decode(root.$2), contains('#EXT-X-STREAM-INF'));
      expect(relay.prefetchFeedCount, 0);
      expect(relay.prefetchBodyCount, 0);
      expect(bodies, 0);
      final child = await get(client, mediaUris(utf8.decode(root.$2)).single);
      final body = await get(client, mediaUris(utf8.decode(child.$2)).single);
      expect(utf8.decode(body.$2), 'body');
    } finally {
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await sub.cancel();
    }
  });
  test('ready initialization remains readable after production transport stops', () async {
    var initRequests = 0;
    final release = Completer<void>();
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final jobs = <Future<void>>{};
    final sub = origin.listen((request) {
      late Future<void> job;
      job = () async {
        try {
          if (request.uri.path == '/root.m3u8') {
            request.response.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MAP:URI="init.mp4"\n'
              '#EXTINF:1,\nbody.m4s\n#EXT-X-ENDLIST\n',
            );
          } else if (request.uri.path == '/init.mp4') {
            initRequests++;
            request.response.write('init');
          } else {
            await release.future;
            request.response.write('media');
          }
          await request.response.close();
        } on Object {
          /* The held media is cancelled at stop. */
        }
      }().whenComplete(() => jobs.remove(job));
      jobs.add(job);
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
      drainOnStop: true,
      enablePrefetch: true,
    ))!;
    final client = HttpClient();
    try {
      final text = utf8.decode((await get(client, relay.inputUri)).$2);
      final init = Uri.parse(RegExp('URI="([^"]+)"').firstMatch(text)!.group(1)!);
      expect(utf8.decode((await get(client, init)).$2), 'init');
      await relay.finish();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(utf8.decode((await get(client, init)).$2), 'init');
      expect(initRequests, 1);
    } finally {
      release.complete();
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await sub.cancel();
      await Future.wait(jobs.toList());
    }
    expect(relay.prefetchBodyCount, 0);
  });
  test('failed cached media preserves upstream 403 instead of converting it to generic 503', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = origin.listen((request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nbody.ts\n#EXT-X-ENDLIST\n');
      } else {
        request.response.statusCode = 403;
      }
      await request.response.close();
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
      drainOnStop: true,
      enablePrefetch: true,
    ))!;
    var gaps = 0;
    relay.onCoverageIncomplete = () => gaps++;
    final client = HttpClient();
    try {
      final text = utf8.decode((await get(client, relay.inputUri)).$2);
      expect((await get(client, mediaUris(text).single)).$1, 403);
      expect(gaps, 1);
    } finally {
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await sub.cancel();
    }
  });
}
