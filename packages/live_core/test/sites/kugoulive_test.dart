// Kugou Live (Fanxing): parsing and the adapter over the recorded samples
// (spec/sites/kugoulive.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _ignored = {'callback', '_'};

KugouLiveSite _site(List<String> samples) => KugouLiveSite(
  ReplayHttp.fixtures('../../fixtures/kugoulive', samples, ignoredQuery: _ignored),
  now: () => DateTime.utc(2026, 9, 27, 17),
);

Map<String, dynamic> _data(String sample) =>
    (jsonDecode(Fixture.load('kugoulive', sample).body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;

void main() {
  group('§2 catalog', () {
    test('S01 home page: areas in page order without personal routes or the recommendation', () {
      final categories = KugouLiveParse.categories(Fixture.load('kugoulive', 'S01-home').body);
      final areas = categories.single.areas;
      expect(areas.first.name, '一起玩');
      expect(areas.map((a) => a.id), containsAll(['100001', '100002', '7024', '1009', '6007']));
      expect(areas.map((a) => a.id), isNot(contains('8000')));
      expect(areas.map((a) => a.id), isNot(contains('3001')));
      expect(areas.every((a) => a.categoryId == KugouLiveParse.categoryId), isTrue);
    });

    test('S02 recommended pages: live cards with online and heat, hasNextPage', () {
      final rows = (_data('S02-recommend-p1')['list'] as List).cast<Map<String, dynamic>>();
      final page = KugouLiveParse.roomList(Fixture.load('kugoulive', 'S02-recommend-p1').body, page: 1);
      expect(page.items.map((c) => c.ref.roomId), rows.map((r) => '${r['roomId']}'));
      final first = page.items.first;
      expect(first.title, rows.first['label']);
      expect(first.audience.popularity, rows.first['hot']);
      expect(first.cover.toString(), rows.first['imgPath']);
      expect(page.next, const PageCursor('2'));
      final p2 = KugouLiveParse.roomList(Fixture.load('kugoulive', 'S02-recommend-p2').body, page: 2);
      expect(p2.items.every((c) => c.state == LiveState.live), isTrue, reason: 'liveStatus 6 (phone) is live too');
    });

    test('S03 area list: "star" wrappers, liveType as state, last page', () {
      final page = KugouLiveParse.roomList(Fixture.load('kugoulive', 'S03-area-7024-p1').body, page: 1);
      final rows = (_data('S03-area-7024-p1')['list'] as List).cast<Map<String, dynamic>>();
      expect(page.items.map((c) => c.ref.roomId), rows.map((r) => '${(r['data'] as Map)['roomId']}'));
      expect(page.items.every((c) => c.state == LiveState.live), isTrue);
      expect(page.isLast, isTrue);
    });
  });

  group('§3 search', () {
    test('S06 JSONP: anchors live or not, one page; empty result', () {
      final body = Fixture.load('kugoulive', 'S06-search').body;
      final page = KugouLiveParse.search(body);
      expect(page.items, isNotEmpty);
      expect(page.items.map((c) => c.state).toSet(), {LiveState.live, LiveState.offline});
      expect(page.items.every((c) => c.followers != null), isTrue, reason: '`fansCount`');
      expect(page.isLast, isTrue);
      expect(KugouLiveParse.search(Fixture.load('kugoulive', 'S06-search-empty').body).items, isEmpty);
    });
  });

  group('§4 room', () {
    test('S04 live, phone, offline and missing rooms', () {
      final live = KugouLiveParse.detail(Fixture.load('kugoulive', 'S04-room-live').body, expectedId: '3197156');
      final info = _data('S04-room-live')['normalRoomInfo'] as Map<String, dynamic>;
      expect(live.detail.state, LiveState.live);
      expect(live.detail.card.anchorName, info['nickName']);
      expect(live.detail.card.title, info['privateMesg']);
      expect(live.detail.notice, info['publicMesg']);
      expect(live.detail.card.cover.toString(), 'https://p3.fx.kgimg.com${info['imgPath']}');
      expect(live.restricted, isFalse);
      final mobile = KugouLiveParse.detail(Fixture.load('kugoulive', 'S04-room-mobile').body, expectedId: '50595748');
      expect(mobile.detail.state, LiveState.live, reason: 'liveType 2 with a session');
      final offline = KugouLiveParse.detail(Fixture.load('kugoulive', 'S04-room-offline').body, expectedId: '1014306');
      expect(offline.detail.state, LiveState.offline);
      expect(
        () => KugouLiveParse.detail(Fixture.load('kugoulive', 'S04-room-notfound').body, expectedId: '999'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('§5/§6 streams', () {
    test('S05 two lines (sid 5 and 40), one FLV each, Tencent lease', () {
      final set = KugouLiveParse.streams(
        Fixture.load('kugoulive', 'S05-stream-live').body,
        expectedId: '3197156',
        headers: const {},
      );
      expect(set.qualities, [KugouLiveParse.source]);
      expect(set.lines.map((l) => l.lineId), ['sid5-flv', 'sid40-flv']);
      expect(set.lines.every((l) => l.format == StreamFormat.flv && l.codec == 'avc'), isTrue);
      final lease = set.lines.first.lease!;
      final hex = set.lines.first.url.queryParameters['txTime']!;
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(int.parse(hex, radix: 16) * 1000, isUtc: true));
      expect(lease.cutsConnection, isFalse);
    });

    test('S05 an offline room answers status 0', () {
      expect(
        () => KugouLiveParse.streams(
          Fixture.load('kugoulive', 'S05-stream-offline').body,
          expectedId: '1014306',
          headers: const {},
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('adapter', () {
    test('catalog, search, detail and streams', () async {
      final site = _site([
        'S01-home',
        'S02-recommend-p1',
        'S03-area-7024-p1',
        'S06-search',
        'S04-room-live',
        'S05-stream-live',
      ]);
      final categories = await site.categories();
      final dance = categories.single.areas.firstWhere((a) => a.id == '7024');
      expect((await site.areaRooms(dance)).items, isNotEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.search('唱歌')).items, isNotEmpty);
      final detail = await site.detail(RoomRef('kugoulive', '3197156'));
      final set = await site.streams(detail);
      expect(set.lines.first.headers['referer'], 'https://fanxing.kugou.com/3197156');
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve('3197156'), RoomRef('kugoulive', '3197156'));
      expect(await site.resolve('https://fanxing.kugou.com/3197156?refer=1'), RoomRef('kugoulive', '3197156'));
      expect(await site.resolve('分享 https://mfanxing.kugou.com/?roomId=3197156 进来'), RoomRef('kugoulive', '3197156'));
      expect(await site.resolve('https://fanxing.kugou.com/pcindex/category/7024'), isNull);
      expect(await site.resolve('https://www.kugou.com/1234'), isNull);
    });
  });
}
