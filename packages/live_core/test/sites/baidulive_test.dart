// Baidu Live: parsing and the adapter over the recorded samples
// (spec/sites/baidulive.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _device = 'pc-purelivefixturedevice01';
const _ignored = {'timestamp', 'sign', '_'};

BaiduLiveSite _site(List<String> samples) =>
    BaiduLiveSite(ReplayHttp.fixtures('../../fixtures/baidulive', samples, ignoredQuery: _ignored), deviceId: _device);

Map<String, dynamic> _feed(String sample) =>
    ((jsonDecode(Fixture.load('baidulive', sample).body) as Map)['data'] as Map)['feed'] as Map<String, dynamic>;

void main() {
  test('§2.2 feed signature (vector from the Python capture script)', () {
    final form = {
      'appname': 'pclive',
      'sid': '',
      'ua': '320_480_pc_1.0_0',
      'uid': 'pc-abcdefgh12345678baidulive',
      'timestamp': '1790527918',
      'source': 'pclive',
      'resource': 'banner,tab,feed',
      'scene': 'pc_channel',
      'session_id': '',
      'refresh_type': '0',
      'refresh_index': '1',
      'tab': 'rec',
      'channel_id': '570',
    };
    expect(BaiduLiveParse.feedSign(form), 'efacca3b883a2d3ecc360cee92f78e55');
  });

  group('§2 feed', () {
    test('S01 first page: tabs become areas; ten live cards; cursor session:index', () {
      final body = Fixture.load('baidulive', 'S01-feed-rec-p1').body;
      final areas = BaiduLiveParse.categories(body).single.areas;
      expect(areas.map((a) => a.id), containsAll(['shopping:574', 'finance:611', 'news:575']));
      expect(areas.map((a) => a.id), isNot(contains('rec:570')));
      final page = BaiduLiveParse.feed(body);
      final feed = _feed('S01-feed-rec-p1');
      final items = (feed['items'] as List).cast<Map<String, dynamic>>();
      expect(page.items.map((c) => c.ref.roomId), items.map((i) => '${i['room_id']}'));
      expect(page.items.first.audience.online, items.first['audience_count']);
      expect(page.items.first.anchorName, (items.first['host'] as Map)['name']);
      expect(page.next, PageCursor('${feed['session_id']}:${feed['refresh_index']}'));
    });

    test('S01 page 2 keeps the session and advances the index', () {
      final p2 = _feed('S01-feed-rec-p2');
      expect(p2['session_id'], _feed('S01-feed-rec-p1')['session_id']);
      expect(p2['refresh_index'], 2);
      expect(BaiduLiveParse.feed(Fixture.load('baidulive', 'S01-feed-rec-p2').body).items, hasLength(10));
    });
  });

  group('§4 room', () {
    test('S02 live: qualities origin, 720p, 480p; FLV per CDN then HLS', () {
      final room = BaiduLiveParse.room(Fixture.load('baidulive', 'S02-room-live').body, expectedId: '11560887291');
      expect(room.detail.state, LiveState.live);
      expect(room.detail.card.audience.online, isNotNull);
      expect(BaiduLiveParse.qualities(room.video).map((q) => q.id), ['origin', '720p', '480p']);
      final source = BaiduLiveParse.lines(room, BaiduLiveParse.origin, headers: const {});
      expect(source.single.format, StreamFormat.flv);
      expect(source.single.url.path, endsWith('_11560887291.flv'));
      final hd = BaiduLiveParse.lines(
        room,
        const Quality(id: '720p', label: '720p', rank: 720),
        headers: const {},
      );
      expect(hd.map((l) => l.format), [StreamFormat.flv, StreamFormat.flv, StreamFormat.hls, StreamFormat.hls]);
      expect(hd.map((l) => l.lineId).toSet(), hasLength(4));
      expect(hd.first.url.path, endsWith('-L3.flv'));
    });

    test('S02 ended room (status 3) is offline although stale URLs remain; missing room', () {
      final ended = BaiduLiveParse.room(Fixture.load('baidulive', 'S02-room-ended').body, expectedId: '11583715413');
      expect(ended.detail.state, LiveState.offline);
      expect(ended.detail.card.audience.online, isNull);
      expect(
        () => BaiduLiveParse.lines(ended, BaiduLiveParse.origin, headers: const {}),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(
        () => BaiduLiveParse.room(Fixture.load('baidulive', 'S02-room-notfound').body, expectedId: '99999999999'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('adapter', () {
    test('catalog, detail and streams', () async {
      final site = _site(['S01-feed-rec-p1', 'S01-feed-shopping-p1', 'S02-room-live']);
      final areas = (await site.categories()).single.areas;
      final shopping = areas.firstWhere((a) => a.id == 'shopping:574');
      expect((await site.areaRooms(shopping)).items, hasLength(10));
      final recommended = await site.recommended();
      expect(recommended.items, isNotEmpty);
      final detail = await site.detail(RoomRef('baidulive', '11560887291'));
      final set = await site.streams(detail);
      expect(set.selected, BaiduLiveParse.origin);
    });

    test('the second page sends the session', () async {
      final site = _site(['S01-feed-rec-p1', 'S01-feed-rec-p2']);
      final p1 = await site.recommended();
      final p2 = await site.recommended(cursor: p1.next);
      expect(p2.items, hasLength(10));
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve('11560887291'), RoomRef('baidulive', '11560887291'));
      expect(await site.resolve('https://live.baidu.com/m/room/11560887291'), RoomRef('baidulive', '11560887291'));
      expect(
        await site.resolve('【百度直播】https://live.baidu.com/m/media/multipage/liveshow/index/ixxcsd?room_id=11560887291'),
        RoomRef('baidulive', '11560887291'),
      );
      expect(
        await site.resolve('https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=11560887291'),
        RoomRef('baidulive', '11560887291'),
      );
      expect(await site.resolve('https://live.baidu.com/other?room_id=11560887291'), isNull);
    });
  });
}
