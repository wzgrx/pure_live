// 6.cn (六间房): parsing and the adapter over the recorded samples
// (spec/sites/sixroom.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

SixRoomSite _site(List<String> samples) => SixRoomSite(ReplayHttp.fixtures('../../fixtures/sixroom', samples));

List<Map<String, dynamic>> _rows(String sample, String type) =>
    ((((jsonDecode(Fixture.load('sixroom', sample).body) as Map)['content'] as Map)[type]) as List)
        .cast<Map<String, dynamic>>();

void main() {
  group('§2 lists', () {
    test('S01 u0 pages: 20 rows, cursor until roomListCount, empty beyond', () {
      final rows = _rows('S01-list-u0-p1', 'u0');
      final p1 = SixRoomParse.list(Fixture.load('sixroom', 'S01-list-u0-p1').body, type: 'u0', page: 1);
      expect(p1.items.map((c) => c.ref.roomId), rows.map((r) => r['rid']));
      expect(p1.items.first.anchorName, rows.first['username']);
      expect(p1.items.first.audience.online, rows.first['count']);
      expect(p1.items.first.area, '歌区');
      expect(p1.next, const PageCursor('2'));
      final p3 = SixRoomParse.list(Fixture.load('sixroom', 'S01-list-u0-p3').body, type: 'u0', page: 3);
      expect(p3.items, hasLength(19));
      expect(p3.isLast, isTrue, reason: '3 × 20 ≥ 59');
      final p4 = SixRoomParse.list(Fixture.load('sixroom', 'S01-list-u0-p4').body, type: 'u0', page: 4);
      expect(p4.items, isEmpty);
      expect(p4.isLast, isTrue);
    });

    test('S01 recommendation (special) mixes areas; party list', () {
      final special = SixRoomParse.list(Fixture.load('sixroom', 'S01-list-special-p1').body, type: 'special', page: 1);
      expect(special.items.map((c) => c.area).toSet().length, greaterThan(1));
      final party = SixRoomParse.list(Fixture.load('sixroom', 'S01-list-u8-p1').body, type: 'u8', page: 1);
      expect(party.items, isNotEmpty);
      expect(party.isLast, isTrue);
    });

    test('an empty type answers content: []', () {
      expect(SixRoomParse.list('{"flag":"001","content":[]}', type: 'u10', page: 1).items, isEmpty);
      expect(() => SixRoomParse.list('{"flag":"402"}', type: 'u0', page: 1), throwsA(isA<ApiChanged>()));
    });
  });

  group('§3 search', () {
    test('S02 streamers with live marks; no results', () {
      final html = Fixture.load('sixroom', 'S02-search').body;
      final page = SixRoomParse.search(html);
      expect(page.items, hasLength('<li data-uid="'.allMatches(html).length));
      expect(page.items.first.state, LiveState.live, reason: 'the first result wears the live mark');
      expect(page.items.map((c) => c.state).toSet(), {LiveState.live, LiveState.offline});
      expect(SixRoomParse.search(Fixture.load('sixroom', 'S02-search-empty').body).items, isEmpty);
    });
  });

  group('§4 room page', () {
    test('S03 live: user id, stream name, codec, title from the mood', () {
      final page = SixRoomParse.page(Fixture.load('sixroom', 'S03-room-live').body, expectedId: '16066');
      expect(page.detail.state, LiveState.live);
      expect(page.userId, '53007895');
      expect(page.flvTitle, matches(RegExp(r'^v53007895-\d+$')));
      expect(page.detail.card.anchorName, '莹儿～晚上见');
      expect(page.detail.card.title, isNot(contains('<a')), reason: 'HTML in privNotic is stripped');
      expect(page.detail.card.area, '歌区');
      final line = SixRoomParse.line(page, headers: const {});
      expect(line.url.toString(), 'https://wlive.6rooms.com/httpflv/${page.flvTitle}.flv');
      expect(line.codec, 'avc');
    });

    test('S03 offline and missing rooms', () {
      final offline = SixRoomParse.page(Fixture.load('sixroom', 'S03-room-offline').body, expectedId: '191111');
      expect(offline.detail.state, LiveState.offline);
      expect(offline.detail.card.anchorName, '依诺♔休息');
      expect(() => SixRoomParse.line(offline, headers: const {}), throwsA(isA<StreamUnavailable>()));
      final missing = Fixture.load('sixroom', 'S03-room-notfound');
      expect(
        () => SixRoomParse.page(missing.body, expectedId: '99999999999', status: missing.status),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('adapter', () {
    test('catalog, search, detail and streams', () async {
      final site = _site(['S01-list-u0-p1', 'S01-list-special-p1', 'S02-search', 'S03-room-live']);
      final area = (await site.categories()).single.areas.first;
      expect((await site.areaRooms(area)).items, hasLength(20));
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.search('诺')).items, isNotEmpty);
      final detail = await site.detail(RoomRef('sixroom', '16066'));
      final set = await site.streams(detail);
      expect(set.lines.single.headers['referer'], 'https://v.6.cn/16066');
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve('16066'), RoomRef('sixroom', '16066'));
      expect(await site.resolve('https://v.6.cn/16066?src=x'), RoomRef('sixroom', '16066'));
      expect(await site.resolve('看 https://v.6.cn/profile/191111 吧'), RoomRef('sixroom', '191111'));
      expect(await site.resolve('https://m.6.cn/16066'), RoomRef('sixroom', '16066'));
      expect(await site.resolve('https://v.6.cn/search.php?key=x'), isNull);
    });
  });
}
