// Missevan parsing and the adapter over the recorded samples
// (spec/sites/missevan.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = '453091860';

Map<String, dynamic> _info(String sample) =>
    (jsonDecode(Fixture.load('missevan', sample).body) as Map<String, dynamic>)['info'] as Map<String, dynamic>;

MissevanSite _site(List<String> samples) => MissevanSite(
  ReplayHttp.fixtures('../../fixtures/missevan', samples),
  now: () => Fixture.load('missevan', 'S04-live').capturedAt,
);

void main() {
  test('§2.1 tabs grouped by namespace; the team-live list tab is kept', () {
    final categories = MissevanParse.categories(Fixture.load('missevan', 'S01-meta').body);
    expect(categories.map((c) => c.id), ['catalog', 'list', 'tag']);
    expect(categories.map((c) => c.name), ['分区', '团播', '标签']);
    expect(categories.first.areas.map((a) => a.id), ['105', '104', '116', '115', '122']);
    expect(categories.first.areas.every((a) => a.categoryId == 'catalog'), isTrue);
    expect(categories[1].areas.single.id, '4');
    expect(categories[1].areas.single.name, '团播');
    expect(categories.last.areas.single.categoryId, 'tag');
    final unknown = jsonEncode({
      'code': 0,
      'info': {
        'tabs': [
          {'type': 'future', 'name': 'x'},
          {'type': 'catalog', 'catalog_id': 1, 'name': 'a'},
        ],
      },
    });
    expect(MissevanParse.categories(unknown).single.areas.single.name, 'a', reason: 'unknown tab types are skipped');
  });

  group('§2.2 lists', () {
    test('page 1 keeps every entry beyond pagesize, live only', () {
      final page = MissevanParse.listPage(Fixture.load('missevan', 'S02-list-p1').body, page: 1);
      final rows = (_info('S02-list-p1')['Datas'] as List).cast<Map<String, dynamic>>();
      expect(rows, hasLength(22));
      expect(page.items.map((r) => r.ref.roomId), rows.map((r) => '${r['room_id']}'));
      expect(page.items.every((r) => r.state == LiveState.live), isTrue);
      final first = page.items.first;
      expect(first.title, rows.first['name']);
      expect(first.anchorName, rows.first['creator_username']);
      expect(first.audience.popularity, (rows.first['statistics'] as Map)['score']);
      expect(first.audience.online, isNull);
      expect(first.area, rows.first['catalog_name']);
      expect(page.next, const PageCursor('2'));
    });

    test('the last page is maxpage; beyond it is empty', () {
      expect(MissevanParse.listPage(Fixture.load('missevan', 'S02-list-last').body, page: 29).isLast, isTrue);
      final beyond = MissevanParse.listPage(Fixture.load('missevan', 'S02-list-beyond').body, page: 30);
      expect(beyond.items, isEmpty);
      expect(beyond.isLast, isTrue);
    });

    test('catalog, tag and team-live lists parse', () {
      for (final sample in ['S02-list-catalog', 'S02-list-tag', 'S02-list-team']) {
        final page = MissevanParse.listPage(Fixture.load('missevan', sample).body, page: 1);
        expect(page.items, isNotEmpty, reason: sample);
        expect(page.next, isNotNull, reason: sample);
      }
    });

    test('an unknown open state is ApiChanged', () {
      final body = jsonEncode({
        'code': 0,
        'info': {
          'pagination': {'p': 1, 'maxpage': 1},
          'Datas': [
            {
              'room_id': 1,
              'status': {'open': 2},
            },
          ],
        },
      });
      expect(() => MissevanParse.listPage(body, page: 1), throwsA(isA<ApiChanged>()));
    });
  });

  group('§3 search', () {
    test('live and offline rooms; pages up to maxpage', () {
      final page = MissevanParse.searchPage(Fixture.load('missevan', 'S03-search').body, page: 1);
      final rows = (_info('S03-search')['data'] as List).cast<Map<String, dynamic>>();
      expect(page.items.map((r) => r.ref.roomId), rows.map((r) => '${r['room_id']}'));
      expect(page.items.map((r) => r.state == LiveState.live), rows.map((r) => (r['status'] as Map)['open'] == 1));
      expect(page.items.where((r) => r.state == LiveState.offline), isNotEmpty);
      expect(page.next, const PageCursor('2'));
      final empty = MissevanParse.searchPage(Fixture.load('missevan', 'S03-search-empty').body, page: 1);
      expect(empty.items, isEmpty);
      expect(empty.isLast, isTrue);
    });
  });

  group('§4 detail and §5 streams', () {
    test('a live room', () {
      final detail = MissevanParse.detail(Fixture.load('missevan', 'S04-live').body);
      final room = _info('S04-live')['room'] as Map<String, dynamic>;
      expect(detail.ref, RoomRef('missevan', _live));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, room['name']);
      expect(detail.card.audience.popularity, (room['statistics'] as Map)['score']);
      expect(detail.card.liveSince, DateTime.fromMillisecondsSinceEpoch(1790481150876, isUtc: true));
      expect(detail.notice, room['announcement']);
      expect(detail.introduction, startsWith('这里是花间'));
      expect(detail.danmakuKeys, {'roomId': _live, 'websocket': 'wss://im.missevan.com/ws?room_id=$_live'});
      expect(detail.link, Uri.parse('https://fm.missevan.com/live/$_live'));
    });

    test('streams: one quality, FLV then HLS over https, leases from expires', () {
      final fixture = Fixture.load('missevan', 'S04-live');
      final set = MissevanParse.streams(fixture.body, issuedAt: fixture.capturedAt, headers: MissevanSite.headers);
      expect(set.qualities, [MissevanParse.original]);
      expect(set.lines.map((l) => l.lineId), ['flv', 'hls']);
      expect(set.lines.map((l) => l.format), [StreamFormat.flv, StreamFormat.hls]);
      expect(set.lines.every((l) => l.url.scheme == 'https' && l.url.host.endsWith('.bilivideo.com')), isTrue);
      expect(set.lines.every((l) => l.confirmed == MissevanParse.original), isTrue);
      final expires = int.parse(set.lines.first.url.queryParameters['expires']!);
      final lease = set.lines.first.lease!;
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
      expect(lease.cutsConnection, isFalse);
      expect(set.lines.last.lease!.cutsConnection, isTrue);
      expect(set.lines.first.headers['referer'], 'https://fm.missevan.com/');
    });

    test('offline rooms keep stale addresses that must not play', () {
      final fixture = Fixture.load('missevan', 'S04-offline');
      expect(MissevanParse.detail(fixture.body).state, LiveState.offline);
      expect(
        () => MissevanParse.streams(fixture.body, issuedAt: fixture.capturedAt, headers: const {}),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('not found and other failures', () {
      final missing = Fixture.load('missevan', 'S04-notfound');
      expect(() => MissevanParse.detail(missing.body, status: missing.status), throwsA(isA<NotFound>()));
      expect(() => MissevanParse.info('{"code":1,"info":"x"}', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => MissevanParse.info('', what: 'x', status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => MissevanParse.info('', what: 'x', status: 429), throwsA(isA<RateLimited>()));
      expect(
        () => MissevanParse.mediaUrl('https://evil.example.test/a.flv', format: StreamFormat.flv),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('adapter over ReplayHttp', () {
    test('catalog, area rooms per namespace, recommended, search', () async {
      final site = _site([
        'S01-meta',
        'S02-list-p1',
        'S02-list-catalog',
        'S02-list-tag',
        'S02-list-team',
        'S03-search',
        'S03-search-p2',
      ]);
      final categories = await site.categories();
      final areas = {for (final area in categories.expand((c) => c.areas)) '${area.categoryId}:${area.id}': area};
      expect((await site.areaRooms(areas['catalog:104']!)).items, isNotEmpty);
      expect((await site.areaRooms(areas['tag:1']!)).items, isNotEmpty);
      expect((await site.areaRooms(areas['list:4']!)).items, isNotEmpty);
      final recommended = await site.recommended();
      expect(recommended.items, hasLength(22));
      final first = await site.search('配音');
      final second = await site.search('配音', cursor: first.next);
      expect(second.items, hasLength(20));
    });

    test('searching a room id or link finds that room; a missing room is no result', () async {
      final site = _site(['S04-live', 'S04-offline', 'S04-notfound']);
      expect((await site.search(_live)).items.single.ref.roomId, _live);
      expect((await site.search('https://fm.missevan.com/live/507069668/')).items.single.state, LiveState.offline);
      expect((await site.search('1')).items, isEmpty);
    });

    test('detail and streams re-read the room', () async {
      final site = _site(['S04-live']);
      final detail = await site.detail(RoomRef('missevan', _live));
      final set = await site.streams(detail);
      expect(set.lines, hasLength(2));
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve(_live), RoomRef('missevan', _live));
      expect(await site.resolve('来听 https://fm.missevan.com/live/$_live 吧'), RoomRef('missevan', _live));
      expect(await site.resolve('https://fm.missevan.com/live/0123'), isNull);
      expect(await site.resolve('https://www.missevan.com/live/$_live'), isNull);
      expect(await site.resolve('https://fm.missevan.com/explore'), isNull);
    });
  });
}
