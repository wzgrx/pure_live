// KilaKila parsing and the adapter over the recorded samples
// (spec/sites/kilakila.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _anchor = '3674092253247';
const _broadcast = '2268450556051718173';

Map<String, dynamic> _json(String sample) => jsonDecode(Fixture.load('kilakila', sample).body) as Map<String, dynamic>;

KilakilaSite _site(List<String> samples) => KilakilaSite(
  ReplayHttp.fixtures('../../fixtures/kilakila', samples),
  now: () => Fixture.load('kilakila', 'S05-room-live').capturedAt,
);

void main() {
  group('§2 timelines', () {
    test('hot: dataType 8 rows, live, cumulative listeners; next page until isLastPage', () {
      final page = KilakilaParse.timelinePage(Fixture.load('kilakila', 'S01-timeline-hot-p1').body, page: 1, type: '0');
      final rows = ((((_json('S01-timeline-hot-p1')['data'] as Map)['body'] as Map)['b'] as Map)['data'] as List)
          .cast<Map<String, dynamic>>();
      expect(page.items.map((r) => r.ref.roomId), rows.map((r) => '${(r['roomResq'] as Map)['uid']}'));
      expect(page.items.every((r) => r.state == LiveState.live), isTrue);
      final first = rows.first['roomResq'] as Map<String, dynamic>;
      expect(page.items.first.title, first['title']);
      expect(page.items.first.anchorName, (rows.first['userResp'] as Map)['nickname']);
      expect(page.items.first.audience.cumulative, first['watchNumber']);
      expect(page.items.first.audience.online, isNull);
      expect(page.next, const PageCursor('2'));
      expect(
        KilakilaParse.timelinePage(Fixture.load('kilakila', 'S01-timeline-hot-p2').body, page: 2, type: '0').next,
        const PageCursor('3'),
      );
      expect(
        KilakilaParse.timelinePage(Fixture.load('kilakila', 'S01-timeline-hot-last').body, page: 55, type: '0').isLast,
        isTrue,
      );
    });

    test('newcomers use dataType 2; the other dataType is skipped', () {
      final body = Fixture.load('kilakila', 'S01-timeline-new-p1').body;
      expect(KilakilaParse.timelinePage(body, page: 1, type: '107').items, hasLength(10));
      expect(KilakilaParse.timelinePage(body, page: 1, type: '0').items, isEmpty);
      expect(KilakilaParse.timelinePage(body, page: KilakilaParse.maxPages, type: '107').isLast, isTrue);
    });
  });

  group('§4 anchors', () {
    test('a live anchor: the current broadcast card, online and cumulative figures', () {
      final anchor = KilakilaParse.anchor(Fixture.load('kilakila', 'S04-owner-live').body, uid: _anchor);
      final detail = KilakilaParse.detail(anchor);
      expect(detail.ref, RoomRef('kilakila', _anchor));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, '欢迎来到克拉农场');
      expect(detail.card.anchorName, startsWith('程也'));
      expect(detail.card.audience.online, 193);
      expect(detail.card.audience.cumulative, 1136);
      expect(detail.card.liveSince, DateTime.fromMillisecondsSinceEpoch(1790518002790, isUtc: true));
      expect(detail.introduction, startsWith('个播'));
      expect(detail.danmakuKeys, {'roomId': _broadcast});
      expect(detail.link, Uri.parse('https://live.hongrenshuo.com.cn/index/roomuser/uid/$_anchor'));
    });

    test('an anchor without a broadcast is offline; an unknown one is NotFound', () {
      final offline = KilakilaParse.detail(
        KilakilaParse.anchor(Fixture.load('kilakila', 'S04-owner-offline').body, uid: '1775178981381'),
      );
      expect(offline.state, LiveState.offline);
      expect(offline.card.title, '回忆专用小马甲');
      expect(offline.danmakuKeys, isEmpty);
      expect(
        () => KilakilaParse.anchor(Fixture.load('kilakila', 'S04-owner-notfound').body, uid: '1'),
        throwsA(isA<NotFound>()),
      );
    });

    test('broadcast status: 4 live, 10 replay, others unknown', () {
      expect(KilakilaParse.state(4), LiveState.live);
      expect(KilakilaParse.state('10'), LiveState.replay);
      expect(() => KilakilaParse.state(7), throwsA(isA<ApiChanged>()));
    });
  });

  group('§5 streams', () {
    test('FLV then HLS under one quality, leases from the auth_key expiry', () {
      final fixture = Fixture.load('kilakila', 'S05-room-live');
      final room = KilakilaParse.roomInfo(fixture.body);
      expect(KilakilaParse.anchorOf(room), _anchor);
      final set = KilakilaParse.streams(room, issuedAt: fixture.capturedAt, headers: KilakilaSite.headers);
      expect(set.lines.map((l) => l.lineId), ['flv', 'hls']);
      expect(set.lines.first.url.path, '/hrs/$_broadcast.flv');
      final expiry = int.parse(set.lines.first.url.queryParameters['auth_key']!.split('-').first);
      final lease = set.lines.first.lease!;
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(fixture.capturedAt).inHours, inInclusiveRange(719, 720));
      expect(lease.cutsConnection, isFalse);
      expect(set.lines.last.lease!.cutsConnection, isTrue);
      expect(set.lines.first.headers['referer'], 'https://live.kilakila.cn/');
    });

    test('an ended broadcast has no stream; a paid one needs an account; a missing one is NotFound', () {
      final ended = Fixture.load('kilakila', 'S05-room-replay');
      final room = KilakilaParse.roomInfo(ended.body);
      expect(KilakilaParse.state(room['status']), LiveState.replay);
      expect(
        () => KilakilaParse.streams(room, issuedAt: ended.capturedAt, headers: const {}),
        throwsA(isA<StreamUnavailable>()),
      );
      final live = KilakilaParse.roomInfo(Fixture.load('kilakila', 'S05-room-live').body)..['goldPrice'] = 100;
      expect(
        () => KilakilaParse.streams(live, issuedAt: ended.capturedAt, headers: const {}),
        throwsA(isA<NeedsLogin>()),
      );
      expect(
        () => KilakilaParse.roomInfo(Fixture.load('kilakila', 'S05-room-notfound').body),
        throwsA(isA<NotFound>()),
      );
    });
  });

  test('§3 search page: anchors with names and avatars; a next page link', () {
    final first = KilakilaParse.searchPage(Fixture.load('kilakila', 'S03-search').body, page: 1);
    expect(first.anchors, hasLength(10));
    expect(first.anchors.first.uid, '1775178981381');
    expect(first.anchors.first.name, '回忆专用小马甲');
    expect(first.anchors.first.avatar, Uri.parse('https://img.hongrenshuo.com.cn/1775178981381.png'));
    expect(first.more, isTrue);
    expect(KilakilaParse.searchPage(Fixture.load('kilakila', 'S03-search-p2').body, page: 2).more, isTrue);
    final empty = KilakilaParse.searchPage(Fixture.load('kilakila', 'S03-search-empty').body, page: 1);
    expect(empty.anchors, isEmpty);
    expect(empty.more, isFalse);
  });

  group('adapter over ReplayHttp', () {
    test('catalog and timelines', () async {
      final site = _site(['S01-timeline-hot-p1', 'S01-timeline-new-p1']);
      final categories = await site.categories();
      expect(categories.single.areas.map((a) => a.id), ['0', '107']);
      expect((await site.areaRooms(categories.single.areas.last)).items, hasLength(10));
      expect((await site.recommended()).items, hasLength(10));
    });

    test('detail and streams for a live anchor', () async {
      final site = _site(['S04-owner-live', 'S05-room-live']);
      final detail = await site.detail(RoomRef('kilakila', _anchor));
      expect(detail.state, LiveState.live);
      final set = await site.streams(detail);
      expect(set.lines, hasLength(2));
    });

    test('links: uids, anchor pages, and broadcast links through the room lookup', () async {
      final site = _site(['S05-room-live']);
      expect(await site.resolve(_anchor), RoomRef('kilakila', _anchor));
      expect(await site.resolve('https://live.kilakila.cn/zhubo/$_anchor'), RoomRef('kilakila', _anchor));
      final redirect = Fixture.load('kilakila', 'S06-room-redirect');
      final location = ((redirect.meta['response'] as Map)['headers'] as Map)['location'] as String;
      expect(await site.resolve(location), RoomRef('kilakila', _anchor), reason: 'encrypted share link');
      expect(await site.resolve('https://live.kilakila.cn/room/$_broadcast'), RoomRef('kilakila', _anchor));
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });

    test('search looks each anchor up for its state', () async {
      final site = _site(['S03-search', 'S04-owner-offline', 'S04-owner-live']);
      // Only two profiles are recorded: the page's other anchors fail the
      // replay, so check the request plan on the first one.
      await expectLater(site.search('小'), throwsA(isA<StateError>()));
      final http = site.http as ReplayHttp;
      expect(Uri.decodeFull(http.requests.first.url.path), '/aboutus/serach/kw/小');
      expect(http.requests[1].url.path, '/Tg/personalH5');
      expect(http.requests[1].url.queryParameters['uid'], '1775178981381');
    });

    test('a uid search returns that anchor; an unknown one no result', () async {
      final site = _site(['S04-owner-live', 'S04-owner-notfound']);
      expect((await site.search(_anchor)).items.single.state, LiveState.live);
      expect((await site.search('1')).items, isEmpty);
    });
  });
}
