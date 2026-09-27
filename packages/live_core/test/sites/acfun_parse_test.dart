// v4 AcFun parsing against the recorded samples (spec/sites/acfun.md §11);
// the legacy parser no longer runs (ADR 0016), expected values are here.
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('acfun', sample);

void main() {
  group('S01/S02 directory', () {
    test('areas are the list filters without 全部', () {
      final areas = AcfunParse.areas(_load('S01-list-all').body);
      expect(areas.map((a) => (a.categoryId, a.id, a.name)), [
        ('1', '4', '虚拟偶像'),
        ('1', '1', '游戏'),
        ('1', '3', '娱乐'),
        ('1', '2', '其他'),
      ]);
      expect(areas.first.icon?.host, 'imgs.aixifan.com');
      expect(AcfunParse.filterQuery(areas[1]), '[{"filterType":1,"filterId":1}]');
    });

    test('the whole live list fits one page; no_more ends it', () {
      final page = AcfunParse.listPage(_load('S01-list-all').body);
      expect(page.items, hasLength(19));
      expect(page.isLast, isTrue);
      final first = page.items.first;
      expect(first.ref, RoomRef('acfun', '40740702'));
      expect(first.state, LiveState.live);
      expect(first.audience.online, isNotNull);
      expect(first.area, '游戏');
      expect(first.cover?.host, isNotEmpty);
      expect(AcfunParse.listPage(_load('S02-list-game').body).items, hasLength(8));
    });
  });

  group('S04 search', () {
    test('authors from the page fragment, live or not; 100 results in pages of 30', () {
      final page = AcfunParse.searchPage(_load('S04-search-p1').body, page: 1);
      expect(page.items, hasLength(30));
      expect(page.items.every((room) => room.anchorName.isNotEmpty && room.avatar != null), isTrue);
      expect(page.next, const PageCursor('2'));
      final last = AcfunParse.searchPage(_load('S04-search-p4').body, page: 4);
      expect(last.items, hasLength(lessThanOrEqualTo(10)));
      expect(last.isLast, isTrue);
      // A nonsense keyword still finds eight authors by fuzzy match; a
      // keyword of rare characters finds none (the page shows empty-page).
      final fuzzy = AcfunParse.searchPage(_load('S04-search-fuzzy').body, page: 1);
      expect(fuzzy.items, hasLength(8));
      expect(fuzzy.isLast, isTrue);
      expect(AcfunParse.searchPage(_load('S04-search-none').body, page: 1).items, isEmpty);
    });
  });

  group('S05 detail', () {
    test('a live room', () {
      final detail = AcfunParse.detail(_load('S05-info-live').body, author: '40740702');
      expect(detail.state, LiveState.live);
      expect(detail.card.title, '西八！');
      expect(detail.card.anchorName, 'Evelonda-飒旦');
      expect(detail.card.area, '游戏');
      expect(detail.card.liveSince, DateTime.fromMillisecondsSinceEpoch(1790519855941, isUtc: true));
      expect(detail.danmakuKeys, {'author': '40740702', 'liveId': '29RchpoKMpA'});
      expect(detail.link, Uri.parse('https://live.acfun.cn/live/40740702'));
    });

    test('an author without liveId is offline; user id 0 is unknown', () {
      final offline = AcfunParse.detail(_load('S05-info-offline').body, author: '1');
      expect(offline.state, LiveState.offline);
      expect(offline.card.anchorName, 'admin');
      expect(offline.introduction, isNotNull);
      expect(() => AcfunParse.detail(_load('S05-info-missing').body, author: '99999999999'), throwsA(isA<NotFound>()));
      expect(() => AcfunParse.detail('{"user":{}}', author: '1'), throwsA(isA<NotFound>()));
    });
  });

  group('S06 streams', () {
    test('the visitor session', () {
      final visitor = AcfunParse.visitor(_load('S06-visitor').body);
      expect(visitor.userId, isNotEmpty);
      expect(visitor.token, isNotEmpty);
      expect(visitor.security, endsWith('=='));
    });

    test('startPlay: qualities by level, URLs per quality, chat admission', () {
      final play = AcfunParse.play(_load('S06-startplay-live').body);
      expect(play.qualities.map((q) => q.id), ['BLUE_RAY', 'SUPER', 'HIGH', 'STANDARD']);
      expect(play.qualities.first.label, '蓝光 8M');
      expect(play.urls['HIGH']!.single.path, endsWith('.flv'));
      expect(play.tickets, isNotEmpty);
      expect(play.attach, isNotNull);
    });

    test('lease: auth_key time, thirty days out', () {
      final fixture = _load('S06-startplay-live');
      final url = AcfunParse.play(fixture.body).urls['HIGH']!.single;
      final lease = AcfunParse.lease(url, fixture.capturedAt)!;
      expect(lease.expiresAt!.difference(fixture.capturedAt).inDays, inInclusiveRange(29, 30));
      expect(lease.cutsConnection, isFalse);
    });

    test('a closed broadcast (129004) is StreamUnavailable', () {
      expect(() => AcfunParse.play(_load('S06-startplay-offline').body), throwsA(isA<StreamUnavailable>()));
    });
  });
}
