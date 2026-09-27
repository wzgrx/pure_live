// v4 YY parsing against the recorded samples (spec/sites/yy.md §11); the
// legacy parser no longer runs (ADR 0016), expected values are written here.
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('yy', sample);

void main() {
  group('S01/S02 catalog', () {
    test('header: three categories, areas with their page URLs', () {
      final header = YyParse.header(_load('S01-header').body);
      expect(header.map((e) => e.category.name), ['娱乐', '游戏', '其他']);
      final ent = header.first;
      expect(ent.category.areas.first.id, '7');
      expect(ent.category.areas.first.name, '音乐');
      expect(ent.pages['4'], Uri.parse('https://www.yy.com/dancing'), reason: 'http is served over https');
    });

    test('getCategory: area covers by id', () {
      final icons = YyParse.areaIcons(_load('S01-category-ent').body);
      expect(icons['7'], Uri.parse('https://image.yy.com/contimage/6Z-z5LmQMTY0MDc3NDY0NjE2NQ.jpg'));
    });

    test('area pages: pageInfo module, or none (server-rendered)', () {
      expect(YyParse.module(_load('S02-area-page-dance').body), (moduleId: '313', biz: 'dance', subBiz: 'idx'));
      expect(YyParse.module(_load('S02-area-page-lol').body), isNull);
    });

    test('page.action: 30 live rooms, heat, start time; ends at totalCount', () {
      final page = YyParse.roomListPage(_load('S02-dance-p1').body, page: 1, area: '舞蹈');
      expect(page.items, hasLength(30));
      final first = page.items.first;
      expect(first.ref, RoomRef('yy', '22490906'));
      expect(first.title, '星耀营 S6・曼妙一夏特别返场');
      expect(first.anchorName, '燃舞蹈-福星');
      expect(first.audience, const Audience(popularity: 1459270));
      expect(first.liveSince, DateTime.fromMillisecondsSinceEpoch(1790527818000, isUtc: true));
      expect(first.area, '舞蹈');
      expect(first.cover?.scheme, 'https');
      expect(page.next, const PageCursor('2'));
      final last = YyParse.roomListPage(_load('S02-dance-p5').body, page: 5);
      expect(last.items, hasLength(16));
      expect(last.isLast, isTrue, reason: '5 × 30 ≥ 136');
      expect(YyParse.roomListPage(_load('S02-dance-p6').body, page: 6).items, isEmpty);
    });

    test('recommendations: 38 rooms over two pages', () {
      final first = YyParse.roomListPage(_load('S03-recommend-p1').body, page: 1);
      expect(first.items, hasLength(30));
      expect(first.next, const PageCursor('2'));
      final second = YyParse.roomListPage(_load('S03-recommend-p2').body, page: 2);
      expect(second.items, hasLength(8));
      expect(second.isLast, isTrue);
      expect(YyParse.roomListPage(_load('S03-recommend-p3').body, page: 3).items, isEmpty);
    });
  });

  group('S04 search', () {
    test('live rooms; the " 正在直播" suffix is not part of the title; ends at totalPage', () {
      final page = YyParse.searchPage(_load('S04-search-p1').body, page: 1);
      expect(page.items, hasLength(16));
      expect(page.items.first.ref, RoomRef('yy', '93379291'));
      expect(page.items.first.title, '创艺灵珊');
      expect(page.items.first.state, LiveState.live);
      expect(page.items.first.audience, const Audience(popularity: 21542));
      expect(page.next, const PageCursor('2'));
      expect(YyParse.searchPage(_load('S04-search-p50').body, page: 50).isLast, isTrue);
      expect(YyParse.searchPage(_load('S04-search-empty').body, page: 1).items, isEmpty);
    });
  });

  group('S05 detail', () {
    test('a live channel', () {
      final detail = YyParse.liveDetail(_load('S05-detail-live').body, sid: '22490906')!;
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, '燃舞蹈-福星');
      expect(detail.danmakuKeys, {'sid': '22490906', 'ssid': '22490906'});
      expect(detail.link, Uri.parse('https://www.yy.com/22490906'));
    });

    test('offline and unknown channels both answer data: null', () {
      expect(YyParse.liveDetail(_load('S05-detail-offline').body, sid: '85520900'), isNull);
      expect(YyParse.liveDetail(_load('S05-detail-missing').body, sid: '999999999999'), isNull);
    });

    test('the room page: offline anchor, 404, and a short channel number', () {
      final offline = YyParse.offlineDetail(_load('S05-page-offline').body);
      expect(offline.ref, RoomRef('yy', '85520900'));
      expect(offline.state, LiveState.offline);
      expect(offline.card.anchorName, '小洲- 00000o0000');
      expect(offline.card.title, startsWith('卓越988'));
      expect(offline.card.area, '段子手');
      expect(() => YyParse.roomPage(_load('S05-page-missing').body), throwsA(isA<NotFound>()));
      expect(YyParse.roomPage(_load('S05-page-asid').body).sid, '35340121');
    });
  });

  group('S06/S07 streams', () {
    test('only web-playable gears; the answer names the delivered gear and line', () {
      final streams = YyParse.streams(_load('S06-streams-g1').body);
      expect(streams.qualities.map((q) => (q.id, q.label)), [('2', '高清'), ('1', '流畅')]);
      expect(streams.gear, '1');
      expect(streams.line, 14);
      expect(streams.lines, [10, 14]);
      expect(streams.url!.host, 'ks-flv-web.yy.com');
    });

    test('gear 3 has no web stream: the server delivers gear 2', () {
      expect(YyParse.streams(_load('S06-streams-g3').body).gear, '2');
    });

    test('line_seq picks the CDN', () {
      expect(YyParse.streams(_load('S06-streams-g2-l10').body).url!.host, 'tx-flv-web.yy.com');
      expect(YyParse.streams(_load('S06-streams-g2-l14').body).url!.host, 'ks-flv-web.yy.com');
    });

    test('lease: t is the expiry, ten minutes out; connection kept', () {
      final fixture = _load('S06-streams-g2');
      final url = YyParse.streams(fixture.body).url!;
      final lease = YyParse.lease(url, fixture.capturedAt)!;
      expect(lease.expiresAt!.difference(fixture.capturedAt).inSeconds, inInclusiveRange(590, 601));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 1));
      expect(lease.cutsConnection, isFalse);
    });

    test('an offline channel has no gears and no line; mobile HLS has no URL', () {
      final streams = YyParse.streams(_load('S06-streams-offline').body);
      expect(streams.qualities, isEmpty);
      expect(streams.url, isNull);
      expect(YyParse.mobileHls(_load('S07-mobile-hls-offline').body), isNull);
      expect(YyParse.mobileHls(_load('S07-mobile-hls').body)!.path, endsWith('.m3u8'));
    });
  });
}
