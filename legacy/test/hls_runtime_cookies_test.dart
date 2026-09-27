import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_session_cookies.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/hls_body_reader.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';
import 'package:pure_live/recorder/services/hls_upstream_client.dart';

void main() {
  for (final foreign in [false, true]) {
    test('runtime cookie resolves each redirect and never revives stale cookies; foreign=$foreign', () async {
      final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${first.port}/root.m3u8');
      final seen = <String?>[];
      final calls = <Uri>[];
      var generation = 1;
      Future<void> respond(HttpRequest request) async {
        seen.add(request.headers.value('cookie'));
        if (request.uri.path == '/root.m3u8') {
          generation = 2;
          request.response.statusCode = 302;
          request.response.headers.set('Set-Cookie', 'grant=stale-response; Path=/');
          request.response.headers.set('Location', foreign ? 'http://127.0.0.1:${second.port}/keys/key' : '/keys/key');
        } else {
          request.response.write('body');
        }
        await request.response.close();
      }

      final s1 = first.listen(respond);
      final s2 = second.listen(respond);
      final client = HttpClient();
      final jar = HlsSessionCookies()..receive(base, ['grant=stale-jar; Path=/']);
      final upstream = HlsUpstreamClient(
        client: client,
        source: base,
        cookies: jar,
        headers: {'Cookie': 'grant=stale-argument'},
        requestCookies: (uri) {
          calls.add(uri);
          if (uri.origin != base.origin || uri.path == '/no-cookie') return null;
          return 'grant=g$generation; path=${uri.path == '/keys/key' ? 'key' : 'playlist'}';
        },
      );
      try {
        final (response, _) = await upstream.open('GET', base);
        await response.drain<void>();
        expect(calls.length, 2);
        expect(calls.last.path, '/keys/key');
        expect(seen, ['grant=g1; path=playlist', foreign ? null : 'grant=g2; path=key']);
        final (empty, _) = await upstream.open('GET', base.resolve('/no-cookie'));
        await empty.drain<void>();
        expect(seen.last, isNull);
        expect(jar.headerFor(base), 'grant=stale-jar', reason: 'runtime mode never stores response grants');
      } finally {
        upstream.clear();
        client.close(force: true);
        await first.close(force: true);
        await second.close(force: true);
        await s1.cancel();
        await s2.cancel();
      }
    });
  }

  for (final stop in [false, true]) {
    test('late open checks ${stop ? 'stop' : 'revocation'} before sending credentials', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var received = 0;
      final sub = server.listen((request) async {
        received++;
        await request.response.close();
      });
      final client = HttpClient();
      final delayed = _DelayedOpen(client);
      var active = true;
      var calls = 0;
      final upstream = HlsUpstreamClient(
        client: delayed,
        source: Uri.parse('http://127.0.0.1:${server.port}/root.m3u8'),
        headers: {},
        cookies: HlsSessionCookies(),
        requestCookies: (_) {
          calls++;
          if (!active) throw StateError('grant revoked');
          return 'grant=current';
        },
      );
      try {
        final pending = upstream.open('GET', Uri.parse('http://127.0.0.1:${server.port}/root.m3u8'));
        final failure = expectLater(pending, throwsA(stop ? isA<HlsUpstreamStopped>() : isA<StateError>()));
        await delayed.opened.future;
        active = false;
        if (stop) upstream.clear();
        delayed.release.complete();
        await failure;
        expect(received, 0);
        expect(calls, stop ? 0 : 1);
      } finally {
        if (!delayed.release.isCompleted) delayed.release.complete();
        upstream.clear();
        client.close(force: true);
        await server.close(force: true);
        await sub.cancel();
      }
    });
  }

  test('prefetch snapshots and media share runtime grant; revoked downloads fail without transmission', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${server.port}/root.m3u8');
    final seen = <String?>[];
    final sub = server.listen((request) async {
      seen.add(request.headers.value('cookie'));
      request.response.write(
        request.uri.path.endsWith('.m3u8')
            ? '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:1,\nmedia.ts\n'
            : 'media',
      );
      await request.response.close();
    });
    final client = HttpClient();
    var active = true;
    var generation = 1;
    final upstream = HlsUpstreamClient(
      client: client,
      source: base,
      headers: {},
      cookies: HlsSessionCookies(),
      requestCookies: (uri) {
        if (!active) throw StateError('revoked');
        return 'grant=g$generation; kind=${uri.path.endsWith('.ts') ? 'media' : 'playlist'}';
      },
    );
    const idle = Duration(seconds: 2);
    final pool = HlsPrefetchPool(createDirectory: () => throw StateError('unexpected disk'), bodyIdleTimeout: idle);
    try {
      await upstream.loadSnapshot(base, HlsPrefetchCancellation(), budget: HlsResponseBudget(idle));
      generation = 2;
      final ticket = pool.prefetch(
        'media',
        (cancel) => upstream.loadMedia(base.resolve('media.ts'), cancel, budget: HlsResponseBudget(idle)),
      )!;
      expect(await ticket.ready, true);
      expect(seen, ['grant=g1; kind=playlist', 'grant=g2; kind=media']);
      active = false;
      final revoked = pool.prefetch(
        'revoked',
        (cancel) => upstream.loadMedia(base.resolve('later.ts'), cancel, budget: HlsResponseBudget(idle)),
      )!;
      expect(await revoked.ready, false);
      expect(seen.length, 2);
      expect(revoked.failure, HlsPrefetchFailure.download);
    } finally {
      upstream.stop();
      client.close(force: true);
      await pool.close();
      upstream.clear();
      await server.close(force: true);
      await sub.cancel();
    }
  });

  test('runtime cookies require valid HLS input instead of silently falling through to native', () async {
    for (final args in <List<String>>[
      [],
      ['-i'],
      ['-i', 'https://example.test/live.flv'],
    ]) {
      await expectLater(
        FFmpegHlsInputRelay.startForArguments(args, requestCookies: (_) => null),
        throwsFormatException,
      );
    }
  });

  test('relay activates on desktop, rewrites key/media and reads refreshed per-path grants', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = Uri.parse('http://127.0.0.1:${origin.port}/root.m3u8');
    final seen = <String, String?>{};
    var generation = 1;
    final sub = origin.listen((request) async {
      seen[request.uri.path] = request.headers.value('cookie');
      request.response.write(
        request.uri.path.endsWith('.m3u8')
            ? '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-KEY:METHOD=AES-128,URI="keys/key"\n#EXTINF:1,\nsegments/media.ts\n'
            : 'fixture-bytes',
      );
      await request.response.close();
    });
    final relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-headers', 'Cookie: stale=argument\r\n', '-i', base.toString()],
      requestCookies: (uri) => uri.origin == base.origin ? 'grant=g$generation; path=${uri.path.split('/')[1]}' : null,
      findProxy: (_) => 'DIRECT',
    ))!;
    final client = HttpClient();
    Future<String> read(Uri uri) async {
      final response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, 200);
      return response.transform(utf8.decoder).join();
    }

    try {
      final playlist = await read(relay.inputUri);
      expect(playlist, isNot(contains(base.origin)));
      expect(playlist, isNot(contains('grant=')));
      generation = 2;
      final key = RegExp(r'URI="([^"]+)"').firstMatch(playlist)!.group(1)!;
      final media = const LineSplitter()
          .convert(playlist)
          .firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));
      expect(await read(Uri.parse(key)), 'fixture-bytes');
      expect(await read(Uri.parse(media)), 'fixture-bytes');
      expect(seen, {
        '/root.m3u8': 'grant=g1; path=root.m3u8',
        '/keys/key': 'grant=g2; path=keys',
        '/segments/media.ts': 'grant=g2; path=segments',
      });
      expect(relay.sessionCookieCount, 0);
    } finally {
      client.close(force: true);
      await relay.close();
      await origin.close(force: true);
      await sub.cancel();
    }
    expect(relay.resourceCount, 0);
  });
}

final class _DelayedOpen implements HttpClient {
  _DelayedOpen(this.inner);
  final HttpClient inner;
  final opened = Completer<void>();
  final release = Completer<void>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    final request = await inner.openUrl(method, uri);
    opened.complete();
    await release.future;
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
