import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

const _quality = Quality(id: 'abr', label: '自动', rank: 1);

final class _NoUpstream implements HlsUpstream {
  @override
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers) => throw UnimplementedError();

  @override
  void close() {}
}

/// A CDN: a master that redirects, a media playlist, segments, a key; it
/// records the cookie and referer of every request.
final class _Cdn {
  new _(this.server);

  static Future<_Cdn> start() async {
    final cdn = _Cdn._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    cdn.server.listen(cdn._serve);
    return cdn;
  }

  final HttpServer server;
  final Map<String, ({String? cookie, String? referer})> requests = {};
  String mediaSeed = 'SEED=7';

  Uri get master => Uri.parse('http://127.0.0.1:${server.port}/start/master.m3u8');

  static final segment = Uint8List.fromList(List.generate(400, (i) => i & 0xff));

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    requests[path] = (cookie: request.headers.value('cookie'), referer: request.headers.value('referer'));
    final response = request.response;
    switch (path) {
      case '/start/master.m3u8':
        response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/hls/pl/master.m3u8');
      case '/hls/pl/master.m3u8':
        response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nv/media.m3u8?t=1\n');
      case '/hls/pl/v/media.m3u8':
        response.write(
          '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#X-PROTECT:$mediaSeed\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="/hls/keys/1"\n'
          '#EXTINF:2,\n/hls/seg/1.ts\n#EXTINF:2,\n/hls/seg/2.ts\n',
        );
      case '/hls/seg/1.ts':
        response.add(segment);
      case '/hls/seg/2.ts':
        response.statusCode = HttpStatus.forbidden;
      case '/hls/keys/1':
        response.add(List.filled(16, 1));
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }
}

Future<({int status, Uint8List body})> _get(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    final builder = BytesBuilder();
    await response.forEach(builder.add);
    return (status: response.statusCode, body: builder.takeBytes());
  } finally {
    client.close(force: true);
  }
}

Uri _entry(String playlist, bool Function(String line) where) =>
    Uri.parse(const LineSplitter().convert(playlist).firstWhere(where));

/// The [index]th segment of a rewritten media playlist.
Uri _segment(String playlist, int index) =>
    Uri.parse(const LineSplitter().convert(playlist).where((l) => l.endsWith('.ts')).elementAt(index));

void main() {
  group('rewriting', () {
    final route = HlsRoute(
      prefix: '/secret/',
      port: 9,
      line: StreamLine(
        url: Uri.parse('https://cdn.test/a/master.m3u8'),
        format: StreamFormat.hls,
        lineId: 'x',
        requested: _quality,
      ),
      upstream: _NoUpstream(),
    );

    test('a master: variants and renditions become local playlists', () {
      final text = route.rewrite(
        '#EXTM3U\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="x",URI="audio/a.m3u8"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a"\n'
        'video/v.m3u8\n',
        Uri.parse('https://cdn.test/a/master.m3u8'),
      );
      expect(text, contains('URI="http://127.0.0.1:9/secret/p0.m3u8"'));
      expect(text, contains('\nhttp://127.0.0.1:9/secret/p1.m3u8\n'));
      expect(text, contains('#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a"'));
    });

    test('a media playlist: segments, parts, map and key; the same address keeps its name', () {
      const media =
          '#EXTM3U\n'
          '#EXT-X-MAP:URI="init.mp4"\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="https://keys.test/k?id=1",IV=0x1\n'
          '#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://fairplay"\n'
          '#EXT-X-PART:DURATION=0.5,URI="p1.cmfv"\n'
          '#EXTINF:2,\n'
          'https://seg.test/1.cmfv?sig=1\n';
      final base = Uri.parse('https://cdn.test/a/v.m3u8');
      final text = route.rewrite(media, base);
      expect(text, matches(RegExp(r'#EXT-X-MAP:URI="http://127\.0\.0\.1:9/secret/m\d+\.mp4"')));
      expect(text, matches(RegExp(r'URI="http://127\.0\.0\.1:9/secret/k\d+",IV=0x1')));
      expect(text, contains('URI="skd://fairplay"'), reason: 'not a web address: left alone');
      expect(text, matches(RegExp(r'#EXT-X-PART:DURATION=0\.5,URI="http://127\.0\.0\.1:9/secret/s\d+\.cmfv"')));
      expect(text, matches(RegExp(r'\nhttp://127\.0\.0\.1:9/secret/s\d+\.cmfv\n')));
      expect(route.rewrite(media, base), text, reason: 'reloads map the same addresses to the same names');
    });
  });

  group('serving', () {
    late _Cdn cdn;
    late LoopbackRelay relay;

    setUp(() async {
      cdn = await _Cdn.start();
      relay = await LoopbackRelay.start();
    });

    tearDown(() async {
      await relay.close();
      await cdn.server.close(force: true);
    });

    StreamLine line({List<ScopedCookie>? cookies}) => StreamLine(
      url: cdn.master,
      format: StreamFormat.hls,
      lineId: 'cdn',
      requested: _quality,
      headers: const {'referer': 'https://site.test/', 'cookie': 'master=1'},
      hlsRelay: HlsRelayRecipe(
        cookies: cookies == null ? null : () => cookies,
        restore: (playlist) {
          final seed = RegExp(r'SEED=(\d+)').firstMatch(playlist)?.group(1);
          if (seed == null) return null;
          return (segment) => Uint8List.fromList([for (final byte in segment) byte ^ int.parse(seed)]);
        },
      ),
    );

    test('playlists follow redirects, segments are restored, each path gets its own cookies', () async {
      final input = relay.openHls(
        line(
          cookies: const [
            ScopedCookie(name: 'pl', value: 'a', domain: '127.0.0.1', path: '/hls/pl'),
            ScopedCookie(name: 'seg', value: 'b', domain: '127.0.0.1', path: '/hls/seg'),
            ScopedCookie(name: 'key', value: 'c', domain: '127.0.0.1', path: '/hls/keys'),
          ],
        ),
        site: 'test',
      );
      expect(input.uri.host, '127.0.0.1');

      final master = await _get(input.uri);
      expect(master.status, HttpStatus.ok);
      final variant = _entry(utf8.decode(master.body), (l) => l.startsWith('http://127.0.0.1'));
      final media = utf8.decode((await _get(variant)).body);
      expect(media, contains('#X-PROTECT:SEED=7'));
      expect(cdn.requests.keys, contains('/hls/pl/v/media.m3u8'), reason: 'resolved against the redirect target');

      final first = await _get(_segment(media, 0));
      expect(first.body, [for (final byte in _Cdn.segment) byte ^ 7]);
      final key = RegExp('URI="([^"]+)"').firstMatch(media)!.group(1)!;
      expect((await _get(Uri.parse(key))).body, List.filled(16, 1));

      expect(cdn.requests['/start/master.m3u8']!.cookie, isNull, reason: 'no cookie matches that path');
      expect(cdn.requests['/hls/pl/v/media.m3u8']!.cookie, 'pl=a');
      expect(cdn.requests['/hls/seg/1.ts']!.cookie, 'seg=b');
      expect(cdn.requests['/hls/keys/1']!.cookie, 'key=c');
      expect(cdn.requests['/hls/seg/1.ts']!.referer, 'https://site.test/');
    });

    test('without recipe cookies the line keeps its cookie header; unprotected segments pass as they are', () async {
      cdn.mediaSeed = 'none';
      final input = relay.openHls(line(), site: 'test');
      final master = utf8.decode((await _get(input.uri)).body);
      final media = utf8.decode((await _get(_entry(master, (l) => l.startsWith('http')))).body);
      expect((await _get(_segment(media, 0))).body, _Cdn.segment);
      expect(cdn.requests['/hls/seg/1.ts']!.cookie, 'master=1');
    });

    test('upstream errors pass through; unknown and closed routes are 404', () async {
      final input = relay.openHls(line(), site: 'test');
      final master = utf8.decode((await _get(input.uri)).body);
      final media = utf8.decode((await _get(_entry(master, (l) => l.startsWith('http')))).body);
      expect((await _get(_segment(media, 1))).status, HttpStatus.forbidden);
      expect((await _get(input.uri.replace(path: '${input.uri.path}x'))).status, HttpStatus.notFound);
      expect(
        (await _get(input.uri.replace(path: '/other/index.m3u8'))).status,
        HttpStatus.notFound,
        reason: 'only the secret prefix serves',
      );
      await input.close();
      expect((await _get(input.uri)).status, HttpStatus.notFound);
    });
  });

  group('pipeline', () {
    StreamLine hls({HlsRelayRecipe? recipe}) => StreamLine(
      url: Uri.parse('https://cdn.test/a.m3u8'),
      format: StreamFormat.hls,
      lineId: 'x',
      requested: _quality,
      hlsRelay: recipe,
    );

    test('HLS with a recipe goes through the relay, plain HLS plays directly', () async {
      expect(PipelineMode.of(hls(), canRenew: true), PipelineMode.direct);
      expect(PipelineMode.of(hls(recipe: const HlsRelayRecipe()), canRenew: false), PipelineMode.hls);
      final pipeline = SourcePipeline();
      addTearDown(pipeline.close);
      final input = await pipeline.open(hls(recipe: const HlsRelayRecipe()), site: 'test');
      expect(input.mode, PipelineMode.hls);
      expect(input.local, isTrue);
      expect(input.headers, isEmpty, reason: 'the relay sends them');
      expect(input.renewsLease, isFalse, reason: 'the session keeps prefetching');
      expect(input.uri.path, endsWith('/index.m3u8'));
      await input.close();
    });
  });
}
