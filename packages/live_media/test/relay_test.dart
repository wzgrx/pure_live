import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

/// A CDN on loopback: TwitCasting-like session cookies, a Bigo-protected
/// playlist, a token master, renewable masters and a legacy-HEVC FLV. It
/// records the query and cookie of every request.
final class _Cdn {
  new _(this.server);

  static Future<_Cdn> start() async {
    final cdn = _Cdn._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    cdn.server.listen(cdn._serve);
    return cdn;
  }

  final HttpServer server;
  final Map<String, ({String query, String? cookie})> requests = {};

  String base(String path) => 'http://127.0.0.1:${server.port}$path';

  static final segment = Uint8List.fromList(List.generate(400, (i) => (i * 7) & 0xff));

  /// The recorded Steam master: an audio group and four video variants
  /// (fixtures/steambroadcast/S09-master-live).
  static final String steamMaster = File('../../fixtures/steambroadcast/S09-master-live/body.m3u8').readAsStringSync();

  static Uint8List legacyHevcFlv() {
    final header = FlvTag.fileHeader();
    final config = FlvTag.build(type: FlvTag.video, timestamp: 0, data: [0x1c, 0, 0, 0, 0, 9, 9, 9]);
    final frame = FlvTag.build(type: FlvTag.video, timestamp: 40, data: [0x1c, 1, 0, 0, 0, 5, 5]);
    return Uint8List.fromList([...header, ...config, ...frame]);
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    requests[path] = (query: request.uri.query, cookie: request.headers.value('cookie'));
    final response = request.response;
    switch (path) {
      case '/tc/hls/media.m3u8':
        response
          ..headers.add(HttpHeaders.setCookieHeader, 'lvhls_ssid_1=abc; Path=/tc/hls/; Max-Age=600')
          ..write('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nseg/1.ts\n');
      case '/tc/hls/seg/1.ts':
        if (request.headers.value('cookie') != 'lvhls_ssid_1=abc') response.statusCode = HttpStatus.forbidden;
        response.add(segment);
      case '/bigo/media.m3u8':
        response.write('#EXTM3U\n#EXT-X-BIGO-WEB-PROTECTION:VERSION=1,SEED=7\n#EXTINF:2,\n1.ts\n');
      case '/bigo/1.ts':
        response.add(BigoHlsProtection.transform(segment, 7));
      case '/token/master.m3u8' || '/renew/1/master.m3u8' || '/renew/2/master.m3u8':
        response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nv/media.m3u8\n');
      case '/token/v/media.m3u8' || '/renew/1/v/media.m3u8' || '/renew/2/v/media.m3u8':
        response.write('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\n1.ts\n');
      case '/steam/master.m3u8':
        response.write(steamMaster);
      case '/steam/other-host/master.m3u8':
        response.write(steamMaster.replaceAll('cache3-lax2.steamcontent.com', 'cache8-lax1.steamcontent.com'));
      case '/steam/no-720p/master.m3u8':
        response.write(steamMaster.replaceAll('RESOLUTION=1280x720,', 'RESOLUTION=1024x576,'));
      case '/live.flv':
        response
          ..headers.contentType = ContentType('video', 'x-flv')
          ..add(legacyHevcFlv());
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

Future<String> _text(Uri url) async => utf8.decode((await _get(url)).body);

Uri _lastUri(String playlist) =>
    Uri.parse(const LineSplitter().convert(playlist).lastWhere((line) => line.startsWith('http')));

void main() {
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

  test('echoes the session cookie a media playlist set (TwitCasting lvhls_ssid)', () async {
    final input = relay.openHls(LivePlayLine(cdn.base('/tc/hls/media.m3u8'), format: StreamFormat.hls), site: 'tc');
    final playlist = await _text(input.uri);
    final segment = await _get(_lastUri(playlist));
    expect(segment.status, HttpStatus.ok);
    expect(segment.body, _Cdn.segment);
    expect(cdn.requests['/tc/hls/seg/1.ts']?.cookie, 'lvhls_ssid_1=abc');
  });

  test('restores the first 376 bytes of every Bigo segment', () async {
    final input = relay.openHls(
      LivePlayLine(cdn.base('/bigo/media.m3u8'), format: StreamFormat.hls),
      site: 'bigo',
      recipe: bigoRelayRecipe(),
    );
    final segment = await _get(_lastUri(await _text(input.uri)));
    expect(segment.body, _Cdn.segment);
  });

  test('propagates the source token to child requests (query policy)', () async {
    final source = Uri.parse(cdn.base('/token/master.m3u8?token=abc'));
    final input = relay.openHls(
      LivePlayLine('$source', format: StreamFormat.hls),
      site: 'cc',
      recipe: HlsRelayRecipe(queryPolicy: HlsSourceQueryPolicy.fromSource(source)),
    );
    final media = await _text(_lastUri(await _text(input.uri)));
    await _get(_lastUri(media));
    expect(cdn.requests['/token/v/media.m3u8']?.query, 'token=abc');
    expect(cdn.requests['/token/v/1.ts']?.query, 'token=abc');
  });

  test('a renewed cutting lease points the playlists the engine knows at the new URLs', () async {
    final lease = PlayLease(refreshAt: DateTime.now().add(const Duration(hours: 1)), cutsConnection: true);
    final input = relay.openHls(
      LivePlayLine(cdn.base('/renew/1/master.m3u8'), format: StreamFormat.hls, lease: lease),
      site: 'chzzk',
      renew: (current) async => LivePlayLine(cdn.base('/renew/2/master.m3u8'), format: StreamFormat.hls, lease: lease),
    );
    final child = _lastUri(await _text(input.uri));
    await _text(child);
    expect(cdn.requests.keys, contains('/renew/1/v/media.m3u8'));
    expect(await input.renewNow(), isTrue);
    await _text(child);
    expect(cdn.requests.keys, contains('/renew/2/v/media.m3u8'));
    expect(input.line.url, endsWith('/renew/2/master.m3u8'));
  });

  test('rewrites codec-12 HEVC FLV to Enhanced FLV', () async {
    final input = relay.openFlv(
      LivePlayLine(cdn.base('/live.flv'), format: StreamFormat.flv),
      site: 'kuaishou',
      rewriteLegacyHevc: true,
    );
    final body = (await _get(input.uri)).body;
    final framer = FlvFramer();
    final packets = framer.add(body);
    expect(packets, hasLength(3));
    expect(packets[1][11] & 0x80, 0x80, reason: 'Enhanced FLV flag');
    expect(ascii.decode(packets[1].sublist(12, 16)), 'hvc1');
    expect(packets[2][11], 0x80 | (1 << 4) | 1, reason: 'keyframe, CodedFrames');
    expect(FlvTag.isKeyframe(packets[2]), isTrue);
  });

  test('a closed input stops serving its path', () async {
    final input = relay.openHls(LivePlayLine(cdn.base('/bigo/media.m3u8'), format: StreamFormat.hls), site: 'bigo');
    await input.close();
    expect(input.isClosed, isTrue);
    expect((await _get(input.uri)).status, HttpStatus.notFound);
  });

  group("a Steam variant's line (G01.4)", () {
    const hd = SteamBroadcastVariant(id: '720p', width: 1280, height: 720, bandwidth: 3660000, codec: 'avc');
    late MediaOpener opener;

    setUp(() => opener = MediaOpener(relay: () async => relay));

    Future<MediaInput> open(String path) => opener.open(
      LineSource(LivePlayLine(cdn.base(path), format: StreamFormat.hls)),
      site: 'steambroadcast',
      variantSelector: hd,
    );

    List<String> streams(String master) =>
        const LineSplitter().convert(master).where((line) => line.startsWith('#EXT-X-STREAM-INF')).toList();

    test('serves the master with that variant only, and its audio', () async {
      final input = await open('/steam/master.m3u8');
      expect(input.route, MediaRoute.hlsRelay);
      final master = await _text(input.uri);
      expect(streams(master), [contains('RESOLUTION=1280x720')]);
      expect(
        const LineSplitter().convert(master).where((line) => line.startsWith('#EXT-X-MEDIA:TYPE=AUDIO')),
        hasLength(1),
      );
      expect(master, isNot(contains('steamcontent.com')), reason: 'the children go through the relay');
    });

    test('a fresh master on another CDN host still plays the same variant', () async {
      final master = await _text((await open('/steam/other-host/master.m3u8')).uri);
      expect(streams(master), [contains('RESOLUTION=1280x720')]);
    });

    test('a master without the variant fails the open instead of playing another', () async {
      final input = await open('/steam/no-720p/master.m3u8');
      expect((await _get(input.uri)).status, HttpStatus.badGateway);
    });

    test('without a selector the master goes to the engine as it is', () async {
      final input = await opener.open(
        LineSource(LivePlayLine(cdn.base('/steam/master.m3u8'), format: StreamFormat.hls)),
        site: 'steambroadcast',
      );
      expect(input.route, MediaRoute.direct);
      expect(input.uri.toString(), cdn.base('/steam/master.m3u8'));
    });
  });

  test('niconico keeps exactly the selected variant of the master', () {
    final recipe = niconicoRelayRecipe(() => throw StateError('no grant needed'), resolution: '1280x720');
    final source = Uri.parse('https://livedelivery.test/lv1/master.m3u8');
    final text = recipe.master!(
      source,
      '#EXTM3U\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720\n720.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360\n360.m3u8\n',
    );
    expect(text, contains('720.m3u8'));
    expect(text, isNot(contains('360.m3u8')));
  });

  test('HlsSessionCookies pins cookies to their origin and path', () {
    final jar = HlsSessionCookies(now: () => DateTime.utc(2026, 10))
      ..receive(Uri.parse('https://a.test/x/list.m3u8'), ['s=1; Path=/x/', 'd=2; Domain=b.test']);
    expect(jar.count, 1, reason: 'a foreign domain is ignored');
    expect(jar.headerFor(Uri.parse('https://a.test/x/1.ts'), initialHeader: 'k=v; s=old'), 's=1; k=v');
    expect(jar.headerFor(Uri.parse('https://a.test/y/1.ts')), isNull);
    expect(jar.headerFor(Uri.parse('https://c.test/x/1.ts')), isNull);
  });
}
