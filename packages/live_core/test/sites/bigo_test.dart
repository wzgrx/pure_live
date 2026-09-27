// Bigo Live: parsing, the web token request and the adapter over the
// recorded samples (spec/sites/bigo.md). No legacy expected values (ADR 0016).
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _room = '414439909';
const _ignored = {'callback', 'data', 'token'};

BigoSite _site(List<String> samples) =>
    BigoSite(ReplayHttp.fixtures('../../fixtures/bigo', samples, ignoredQuery: _ignored));

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

void main() {
  group('§2 public list', () {
    test('S01 cards: bigo ids, owners, topics, viewers', () {
      final page = BigoParse.list(Fixture.load('bigo', 'S01-list').body);
      expect(page.items, hasLength(20));
      expect(page.isLast, isTrue);
      final first = page.items.first;
      expect(first.ref, RoomRef('bigo', '858683693'));
      expect(first.anchorName, 'agt🕸️MrWeb🕷️');
      expect(first.title, 'Pk challenge');
      expect(first.state, LiveState.live);
      expect(first.audience.online, 71);
      expect(page.items.map((c) => c.ref.roomId), contains(_room));
    });

    test('locked rooms are skipped; a failed answer is ApiChanged', () {
      final body = Fixture.load('bigo', 'S01-list').body.replaceFirst('"is_locked": 0', '"is_locked": 1');
      expect(BigoParse.list(body).items, hasLength(19));
      expect(() => BigoParse.list('{"code":1,"msg":"x"}'), throwsA(isA<ApiChanged>()));
    });
  });

  group('§6.1 web token', () {
    test('S02 JSONP time and token, whatever the callback name', () {
      expect(BigoParse.serverTime(Fixture.load('bigo', 'S02-time-live').body), '1672503768');
      expect(BigoParse.token(Fixture.load('bigo', 'S02-status-live').body), hasLength(54));
      expect(BigoParse.serverTime('cb_1({"code":0,"time":"12"});'), '12');
      expect(() => BigoParse.token('cb({"code":1})'), throwsA(isA<ApiChanged>()));
      expect(() => BigoParse.token('<html>'), throwsA(isA<ApiChanged>()));
    });

    test('the request data is OpenSSL "Salted__" AES-256-CBC with EVP md5 keys (openssl vector)', () {
      final data = BigoParse.tokenData(
        '1790000000',
        salt: const [1, 2, 3, 4, 5, 6, 7, 8],
        nonce: '0123456789abcdef0123456789abcdef',
      );
      expect(
        data,
        'U2FsdGVkX18BAgMEBQYHCGgtZH+SaDTmSqohBVEeTYk6fpwByYwRdHxnrSXQf/8ob1PLazm7i6YgNgYug8sTpgkPNvEUPrAQA3CNH2PIUzWLpz2m'
        'VWYajBRwlxIPM1Cn0yJTTOZnEBSSwXkuBmsFVabucMah0XDuO/y7/t8qOnCzJmjBnJ1eqBRdnb4YAEd1',
      );
      final random = BigoParse.tokenData('1');
      expect(base64Decode(random).sublist(0, 8), ascii.encode('Salted__'));
    });
  });

  group('§4 studio', () {
    test('S03 live with a token: details and the HLS source', () {
      final studio = BigoParse.studio(Fixture.load('bigo', 'S03-studio-live').body, roomId: _room);
      expect(studio.detail.state, LiveState.live);
      expect(studio.detail.ref, RoomRef('bigo', _room));
      expect(studio.detail.card.anchorName, isNotEmpty);
      expect(studio.detail.danmakuKeys['uid'], '409742853');
      expect(studio.hls!.path, endsWith('.m3u8'));
      final line = BigoParse.line(studio.hls!, headers: const {});
      expect(line.format, StreamFormat.hls);
      expect(line.lease, isNull);
    });

    test('S03 without a token: needLogin → NeedsLogin', () {
      expect(
        () => BigoParse.studio(Fixture.load('bigo', 'S03-studio-notoken').body, roomId: _room),
        throwsA(isA<NeedsLogin>()),
      );
    });

    test('offline, password and paid rooms have no HLS', () {
      final live = Fixture.load('bigo', 'S03-studio-live').body;
      final offline = BigoParse.studio(live.replaceFirst('"alive": 1', '"alive": 0'), roomId: _room);
      expect(offline.detail.state, LiveState.offline);
      expect(offline.hls, isNull);
      expect(BigoParse.studio(live.replaceFirst('"passRoom": false', '"passRoom": true'), roomId: _room).hls, isNull);
      expect(
        () => BigoParse.studio(live.replaceFirst('"alive": 1', '"alive": 7'), roomId: _room),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('§6.3 HLS protection', () {
    test('S04 the playlist seed', () {
      expect(BigoProtection.seed(Fixture.load('bigo', 'S04-playlist').body), 807018584);
      expect(BigoProtection.seed('#EXTM3U\n#EXT-X-VERSION:3\n'), isNull);
      expect(BigoProtection.seed('#EXT-X-BIGO-WEB-PROTECTION:SEED=12\n'), 12);
    });

    test('a recorded scrambled packet turns back into the PAT; applying twice is the identity', () {
      final scrambled = Uint8List(188)..setAll(0, _hex('3853197ab543cc34d1eb3b1446042e58'));
      final plain = BigoProtection.transform(scrambled, 2020359253);
      expect(plain.sublist(0, 16), _hex('474000100000b00d0001c100000001f0'));
      final segment = Uint8List.fromList(List.generate(188 * 3, (i) => i & 0xff));
      expect(BigoProtection.transform(BigoProtection.transform(segment, 807018584), 807018584), segment);
      expect(BigoProtection.transform(segment, 807018584).sublist(376), segment.sublist(376));
    });

    test('§6.3 the relay restorer: by the playlist seed, none for an unprotected playlist', () {
      final segment = Uint8List.fromList(List.generate(188 * 2, (i) => i & 0xff));
      final restore = BigoProtection.restorer(Fixture.load('bigo', 'S04-playlist').body)!;
      expect(restore(BigoProtection.transform(segment, 807018584)), segment);
      expect(BigoProtection.restorer('#EXTM3U\n#EXT-X-VERSION:3\n'), isNull);
    });
  });

  group('adapter', () {
    test('detail and streams through the token flow', () async {
      final site = _site(['S02-time-live', 'S02-status-live', 'S03-studio-live']);
      final detail = await site.detail(RoomRef('bigo', _room));
      expect(detail.state, LiveState.live);
      final set = await site.streams(detail);
      expect(set.lines.single.headers['referer'], 'https://www.bigo.tv/');
      expect(set.lines.single.hlsRelay?.restore, isNotNull, reason: 'segments go through the relay');
      expect(set.selected, BigoParse.auto);
    });

    test('catalog: one public list, no categories', () async {
      final site = _site(['S01-list']);
      expect(await site.categories(), isEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.recommended(cursor: const PageCursor('2'))).items, isEmpty);
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve('https://www.bigo.tv/$_room'), RoomRef('bigo', _room));
      expect(await site.resolve('看 https://www.bigo.tv/en/qashia305?from=share 吧'), RoomRef('bigo', 'qashia305'));
      expect(await site.resolve(_room), RoomRef('bigo', _room));
      expect(await site.resolve('https://www.bigo.tv/download'), isNull);
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });
  });
}
