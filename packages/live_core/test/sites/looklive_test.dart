// LOOK Live: the AES/weapi envelope, parsing and the adapter over the
// recorded samples (spec/sites/looklive.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_core/src/crypto/aes.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

LookLiveSite _site(List<String> samples) => LookLiveSite(ReplayHttp.fixtures('../../fixtures/looklive', samples));

void main() {
  group('AES (FIPS-197 and OpenSSL vectors)', () {
    test('AES-128 and AES-256 single blocks', () {
      final plain = _unhex('00112233445566778899aabbccddeeff');
      expect(
        _hex(AesCbc.encryptBlock(_unhex('000102030405060708090a0b0c0d0e0f'), plain)),
        '69c4e0d86a7b0430d8cdb78070b4c55a',
      );
      expect(
        _hex(AesCbc.encryptBlock(_unhex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'), plain)),
        '8ea2b7ca516745bfeafc49904b496089',
      );
    });

    test('CBC with PKCS#7 matches openssl enc', () {
      expect(
        _hex(
          AesCbc.encrypt(
            utf8.encode('hello weapi'),
            key: utf8.encode('0123456789abcdef'),
            iv: utf8.encode('0102030405060708'),
          ),
        ),
        'ef2907dee91ee007f0f329fed23c6595',
      );
      expect(
        _hex(
          AesCbc.encrypt(
            utf8.encode('{"offset":0,"limit":20}'),
            key: _unhex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'),
            iv: _unhex('0f0e0d0c0b0a09080706050403020100'),
          ),
        ),
        '71da8dc70771ffc46a5a92cab7c4fb6759d3736ccbf6d1866d78cdc4f88aabc5',
      );
    });
  });

  test('§6.1 weapi envelope (vector from the Python/OpenSSL capture script)', () {
    final form = LookLiveParse.envelope({'offset': 0, 'limit': 20});
    expect(form['params'], 'oHkLd52ofA3k/zndl36a8U1O4zHnBfKbbKjMR5BPce+0g9PYp5zhE1V3NRH3CjTU');
    expect(
      form['encSecKey'],
      '35701388baf89fed412e11269b9c76625d095ecaf17f03fa018abe19ea2d38b949debf242ee39a71ca1f6cda71b1b86a45aa909ee27f7e78e2'
      '67d34e732f0de948206c3340a788d0003372183e2f753c1f78b66ac23d134ac1fc9b993156520ea826b8aa89a962d4491b4b8d7e08738e1da'
      '9b07aa39bf4a7ef0b1c210728cd52',
    );
  });

  group('§2 lists', () {
    test('S01 video list: live cards with online and heat; the end', () {
      final page = LookLiveParse.list(Fixture.load('looklive', 'S01-video-p1').body, area: 'video', page: 1);
      final data = (jsonDecode(Fixture.load('looklive', 'S01-video-p1').body) as Map)['data'] as Map;
      final first = ((data['itemList'] as List).first as Map)['liveData'] as Map;
      expect(page.items.first.ref.roomId, '${(first['userInfo'] as Map)['liveRoomNo']}');
      expect(page.items.first.audience.popularity, first['popularity']);
      expect(page.items.first.cover!.scheme, 'https');
      expect(page.isLast, isTrue, reason: 'hasMore false');
    });

    test('S02 voice list drops the injected video card and pages on', () {
      final body = Fixture.load('looklive', 'S02-audio-p1').body;
      final rows = ((jsonDecode(body) as Map)['data'] as Map)['itemList'] as List;
      final voice = rows.where((r) => ((r as Map)['liveData'] as Map)['liveType'] == 2).length;
      final page = LookLiveParse.list(body, area: 'audio', page: 1);
      expect(page.items, hasLength(voice));
      expect(voice, lessThan(rows.length));
      expect(page.next, const PageCursor('2'));
    });
  });

  group('§4 room', () {
    test('S03 video and voice rooms; not found', () {
      final video = LookLiveParse.room(Fixture.load('looklive', 'S03-room-video').body, expectedNo: '21623631');
      expect(video.detail.state, LiveState.live);
      expect(video.audio, isFalse);
      final lines = LookLiveParse.lines(video, headers: const {});
      expect(lines.map((l) => l.format), [StreamFormat.flv, StreamFormat.hls]);
      expect(lines.first.codec, 'avc');
      final voice = LookLiveParse.room(Fixture.load('looklive', 'S03-room-audio').body, expectedNo: '181408025');
      expect(voice.audio, isTrue);
      expect(voice.detail.card.area, '声音直播');
      expect(LookLiveParse.lines(voice, headers: const {}).first.codec, isNull, reason: 'audio only');
      expect(
        () => LookLiveParse.room(Fixture.load('looklive', 'S03-room-notfound').body, expectedNo: '1'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('adapter', () {
    test('the envelope reproduces the recorded forms: lists, detail, streams', () async {
      final site = _site(['S01-video-p1', 'S02-audio-p1', 'S03-room-video']);
      final areas = (await site.categories()).single.areas;
      expect((await site.areaRooms(areas.last)).items, isNotEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      final detail = await site.detail(RoomRef('looklive', '21623631'));
      expect((await site.streams(detail)).lines, hasLength(2));
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve('21623631'), RoomRef('looklive', '21623631'));
      expect(await site.resolve('分享 https://look.163.com/live?id=21623631&x=1'), RoomRef('looklive', '21623631'));
      expect(await site.resolve('https://look.163.com/user?id=1'), isNull);
    });
  });
}
