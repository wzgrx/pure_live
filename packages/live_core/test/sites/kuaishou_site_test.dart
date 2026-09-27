// KuaishouSite end to end over the recorded Kuaishou responses (ReplayHttp),
// plus unit tests of the session cookies, the request identity and links.
// Parsing details are covered by kuaishou_parse_test.dart; these tests check
// what the adapter adds: requests, paging, cookies, retries and errors.
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/kuaishou';

Fixture _fixture(String sample) => Fixture.load('kuaishou', sample);

ReplaySample _sample(String sample) => ReplaySample.load('$_root/$sample');

/// A response that was not recorded (the recording stopped, or a shape the
/// spec describes without a sample); every use says why.
ReplaySample _synthetic(
  String url,
  String body, {
  int status = 200,
  String method = 'GET',
  Map<String, List<String>> headers = const {},
}) => ReplaySample(method: method, url: Uri.parse(url), status: status, bytes: utf8.encode(body), headers: headers);

/// A recorded sample's body served at another URL.
ReplaySample _moved(String sample, String url) {
  final recorded = _sample(sample);
  return ReplaySample(method: 'GET', url: Uri.parse(url), status: recorded.status, bytes: recorded.bytes);
}

const _endPage = '{"data":{"list":[],"hasMore":false}}';

final DateTime _capturedAt = _fixture('S09-room-live').capturedAt;

({KuaishouSite site, ReplayHttp http}) _replay(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  CookieVault? cookies,
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
}) {
  final http = ReplayHttp([for (final sample in samples) _sample(sample), ...extra]);
  final site = KuaishouSite(
    http,
    cookies: cookies,
    now: now ?? () => _capturedAt,
    random: Random(1),
    sleep: sleep ?? (_) async {},
  );
  return (site: site, http: http);
}

/// Answers requests in order from a script, recording them.
final class _Scripted implements LiveHttp {
  new(this.script);

  final List<LiveResponse Function(LiveRequest request)> script;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    if (requests.length > script.length) throw StateError('unexpected request ${request.url}');
    return script[requests.length - 1](request);
  }

  @override
  void close() {}
}

LiveResponse Function(LiveRequest) _answer(String body, {int status = 200, List<String> setCookie = const []}) =>
    (request) => LiveResponse(
      status: status,
      bytes: utf8.encode(body),
      url: request.url,
      headers: {if (setCookie.isNotEmpty) 'set-cookie': setCookie},
    );

LiveResponse Function(LiveRequest) _recorded(String sample) {
  final recorded = _sample(sample);
  return (request) =>
      LiveResponse(status: recorded.status, bytes: recorded.bytes, url: request.url, headers: recorded.headers);
}

LiveResponse Function(LiveRequest) _fail(TransportReason reason) =>
    (request) => throw TransportFailure('kuaishou', reason, 'scripted');

const _captcha = '<html><body><div id="captcha">请完成安全验证</div></body></html>';

String _roomPage(Map<String, dynamic> room) =>
    '<html><script>window.__INITIAL_STATE__=${jsonEncode({
      'liveroom': {
        'playList': [room],
      },
    })};(function(){})();</script></html>';

RoomDetail _room(String roomId, {LiveState state = LiveState.live}) => RoomDetail(
  card: RoomCard(ref: RoomRef('kuaishou', roomId), title: '', anchorName: '', state: state),
  link: Uri.parse('https://live.kuaishou.com/u/$roomId'),
);

List<String> _ids(String sample) => [
  for (final item in ((jsonDecode(_fixture(sample).body) as Map)['data'] as Map)['list'] as List)
    (item as Map)['id'] as String,
];

void main() {
  group('catalog', () {
    test('categories walk all eight types, following hasMore page by page', () async {
      // The recording stopped while types 1–4 still said hasMore: their end
      // pages are synthetic; types 5–8 end on recorded pages.
      final replay = _replay(
        [
          for (var type = 1; type <= 8; type++) 'S01-category-type$type-p1',
          'S01-category-type1-p2',
          'S01-category-type5-p2',
        ],
        extra: [
          _synthetic('https://live.kuaishou.com/live_api/category/data?type=1&page=3&size=30', _endPage),
          for (final type in [2, 3, 4])
            _synthetic('https://live.kuaishou.com/live_api/category/data?type=$type&page=2&size=30', _endPage),
        ],
      );
      final categories = await replay.site.categories();
      expect(categories.map((c) => '${c.id} ${c.name}'), [
        '1 热门',
        '2 网游',
        '3 单机',
        '4 手游',
        '5 棋牌',
        '6 娱乐',
        '7 综合',
        '8 文化',
      ]);
      expect(replay.http.requests.map((r) => '${r.url.queryParameters['type']}/${r.url.queryParameters['page']}'), [
        '1/1',
        '1/2',
        '1/3',
        '2/1',
        '2/2',
        '3/1',
        '3/2',
        '4/1',
        '4/2',
        '5/1',
        '5/2',
        '6/1',
        '7/1',
        '8/1',
      ]);
      final byType = {for (final category in categories) category.id: category.areas};
      expect(byType['1']!.map((a) => a.id), [..._ids('S01-category-type1-p1'), ..._ids('S01-category-type1-p2')]);
      for (final type in [2, 3, 4]) {
        expect(byType['$type']!.map((a) => a.id), _ids('S01-category-type$type-p1'));
      }
      // Complete walks on recorded pages: the same areas legacy collected.
      for (final (type, sample) in [
        (5, 'S01-category-type5-p2'),
        (6, 'S01-category-type6-p1'),
        (7, 'S01-category-type7-p1'),
        (8, 'S01-category-type8-p1'),
      ]) {
        final legacy = (_fixture(sample).legacy as Map<String, dynamic>)['getAllSubCategores'] as Map<String, dynamic>;
        expect(byType['$type']!.map((a) => a.id), legacy['areaIds'], reason: 'type $type');
      }
      for (final category in categories) {
        expect(category.areas.every((a) => a.categoryId == category.id), isTrue);
      }
      expect(replay.http.requests.every((r) => !r.headers.containsKey('cookie')), isTrue);
    });

    test('a failing page fails the catalog instead of returning part of it', () async {
      final limited = _replay(
        ['S01-category-type1-p1'],
        extra: [
          _synthetic(
            'https://live.kuaishou.com/live_api/category/data?type=1&page=2&size=30',
            '{"data":{"result":2,"error_msg":"操作太快了，请稍微休息一下"}}',
          ),
        ],
      );
      await expectLater(limited.site.categories(), throwsA(isA<RateLimited>()));
      final broken = _replay(
        const [],
        extra: [_synthetic('https://live.kuaishou.com/live_api/category/data?type=1&page=1&size=30', '', status: 502)],
      );
      await expectLater(broken.site.categories(), throwsA(isA<NetworkFailure>()));
    });

    test('a page with nothing new ends the walk (a server repeating page 1 cannot loop it)', () async {
      final replay = _replay(
        const [],
        extra: [
          _moved('S01-category-type1-p1', 'https://live.kuaishou.com/live_api/category/data?type=1&page=1&size=30'),
          _moved('S01-category-type1-p1', 'https://live.kuaishou.com/live_api/category/data?type=1&page=2&size=30'),
          for (var type = 2; type <= 8; type++)
            _synthetic('https://live.kuaishou.com/live_api/category/data?type=$type&page=1&size=30', _endPage),
        ],
      );
      final categories = await replay.site.categories();
      expect(categories.first.areas.map((a) => a.id), _ids('S01-category-type1-p1'));
      expect(replay.http.requests.where((r) => r.url.queryParameters['type'] == '1'), hasLength(2));
    });

    test('gameboard areas page by number; the recorded page 1 cursor requests the recorded page 2', () async {
      final replay = _replay(['S02-gameboard-p1', 'S02-gameboard-p2']);
      const area = Area(id: '1001', name: '王者荣耀', categoryId: '1');
      final page1 = await replay.site.areaRooms(area);
      expect(page1.items, hasLength(20));
      expect(page1.next, const PageCursor('2'));
      final loops = page1.items.where((r) => r.state == LiveState.replay);
      expect(loops.map((r) => r.ref.roomId), ['KPL704668133']);
      final page2 = await replay.site.areaRooms(area, cursor: page1.next);
      expect(page2.items, hasLength(20));
      expect(replay.http.requests.map((r) => r.url), [
        _fixture('S02-gameboard-p1').url,
        _fixture('S02-gameboard-p2').url,
      ]);
    });

    test('non-gameboard page 2 carries data.cursor and is the real page 2 (REG-KUAISHOU-022)', () async {
      // Both recorded page 2 requests are offered; only the one with the
      // cursor matches what the adapter sends.
      final replay = _replay(['S03-non-gameboard-p1', 'S03-non-gameboard-p2', 'S03-non-gameboard-p2-cursor']);
      const area = Area(id: '1000004', name: '才艺', categoryId: '6');
      final page1 = await replay.site.areaRooms(area);
      final page2 = await replay.site.areaRooms(area, cursor: page1.next);
      expect(replay.http.requests.last.url, _fixture('S03-non-gameboard-p2-cursor').url);
      expect(page2.items.map((r) => r.ref).toSet().intersection(page1.items.map((r) => r.ref).toSet()), isEmpty);
      expect(page2.next, const PageCursor('3:257_1252287100'));
      expect(replay.http.requests.every((r) => !r.headers.containsKey('cookie')), isTrue);
    });

    test('home list is one page of deduplicated cards; a cursor is not ours', () async {
      final replay = _replay(['S04-home-list']);
      final page = await replay.site.recommended();
      expect(page.items, hasLength(47));
      expect(page.isLast, isTrue);
      expect(page.items.map((r) => r.ref).toSet(), hasLength(47));
      await expectLater(replay.site.recommended(cursor: const PageCursor('2')), throwsArgumentError);
    });
  });

  group('search', () {
    test('result 2 is RateLimited, not an empty result (REG-KUAISHOU-015)', () async {
      final vault = MemoryCookieVault()..set('kuaishou', 'did=user');
      final replay = _replay(['S06-search-author-ratelimited'], cookies: vault);
      final keyword = _fixture('S06-search-author-ratelimited').url.queryParameters['keyword']!;
      await expectLater(
        replay.site.search(' $keyword '),
        throwsA(isA<RateLimited>().having((e) => e.detail, 'detail', contains('操作太快'))),
      );
      final request = replay.http.requests.single;
      expect(request.url, _fixture('S06-search-author-ratelimited').url);
      expect(
        request.headers['referer'],
        'https://live.kuaishou.com/search?keyword=%E7%8E%8B%E8%80%85%E8%8D%A3%E8%80%80',
      );
      expect(request.headers.containsKey('cookie'), isFalse, reason: 'search never carries a cookie (§8)');
    });

    test('result 10 (the anonymous busy gate) is RiskControl on search/author too (§9)', () async {
      // The busy answer was recorded on search/liveStream, which v4 does not
      // call; §9 maps result 10 on every live_api endpoint.
      final url = _fixture('S06-search-author-ratelimited').url.toString();
      final replay = _replay(const [], extra: [_moved('S08-search-livestream-busy', url)]);
      await expectLater(
        replay.site.search('王者荣耀'),
        throwsA(isA<RiskControl>().having((e) => e.cookieSuspect, 'cookieSuspect', isFalse)),
      );
    });

    test('the next page sends the ussid as lssid; a blank keyword sends nothing', () async {
      const base = 'https://live.kuaishou.com/live_api/search/author?keyword=%E7%8E%8B%E8%80%85';
      final replay = _replay(
        const [],
        extra: [
          _synthetic(
            '$base&page=1&lssid=',
            '{"data":{"result":1,"ussid":"dXNzaWQ=","list":[{"id":"tianci666","name":"A","living":true}]}}',
          ),
          _synthetic('$base&page=2&lssid=dXNzaWQ%3D', '{"data":{"result":1,"list":[]}}'),
        ],
      );
      final page1 = await replay.site.search('王者');
      expect(page1.items.single.ref, RoomRef('kuaishou', 'tianci666'));
      final page2 = await replay.site.search('王者', cursor: page1.next);
      expect(page2.isLast, isTrue);
      expect(await replay.site.search('  '), isA<Page<RoomCard>>().having((p) => p.items, 'items', isEmpty));
      expect(replay.http.requests, hasLength(2));
    });

    test('search requests start at least minRequestInterval apart; other requests are not held', () async {
      expect(KuaishouSite.minRequestInterval, {'search': const Duration(seconds: 6)});
      final waits = <Duration>[];
      final replay = _replay([
        'S06-search-author-ratelimited',
        'S04-home-list',
      ], sleep: (duration) async => waits.add(duration));
      await expectLater(replay.site.search('王者荣耀'), throwsA(isA<RateLimited>()));
      await replay.site.recommended();
      expect(waits, isEmpty);
      await expectLater(replay.site.search('王者荣耀'), throwsA(isA<RateLimited>()));
      expect(waits, [const Duration(seconds: 6)]);
    });
  });

  group('room', () {
    test('S09 live room: detail from the room page, anonymous, with the danmaku key', () async {
      final replay = _replay(['S09-room-live']);
      final detail = await replay.site.detail(RoomRef('kuaishou', 'baixi9999999999'));
      expect(detail.state, LiveState.live);
      expect(detail.ref, RoomRef('kuaishou', 'baixi9999999999'));
      expect(detail.link, Uri.parse('https://live.kuaishou.com/u/baixi9999999999'));
      expect(detail.danmakuKeys, {'liveStreamId': 'XT8F1KPOf0c'});
      expect(detail.card.audience.isEmpty, isTrue, reason: 'the page has no room audience (REG-KUAISHOU-016)');
      final request = replay.http.requests.single;
      expect(request.url, _fixture('S09-room-live').url);
      expect(request.headers.containsKey('cookie'), isFalse, reason: 'no session yet: the first page goes bare');
      expect(request.headers['accept'], endsWith(';q=0.9'));
    });

    test('S09 loop room: live on the page, replay when opened from its 【回放】 card', () async {
      final replay = _replay(['S02-gameboard-p1', 'S09-room-live-replay']);
      final cards = await replay.site.areaRooms(const Area(id: '1001', name: '王者荣耀', categoryId: '1'));
      final card = cards.items.firstWhere((r) => r.ref.roomId == 'KPL704668133');
      final ref = card.ref;
      final fromCard = await replay.site.detail(ref, from: card);
      expect(fromCard.state, LiveState.replay);
      expect(fromCard.card.title, card.title);
      final plain = await replay.site.detail(ref);
      expect(plain.state, LiveState.live, reason: 'without the card the page alone says live');
      final other = cards.items.firstWhere((r) => r.ref != ref);
      expect(
        (await replay.site.detail(ref, from: other)).state,
        LiveState.live,
        reason: 'another room’s card is ignored',
      );
      // A search card's title is the streamer's name: the bio stays the title.
      final searchCard = RoomCard(ref: ref, title: card.anchorName, anchorName: card.anchorName, state: LiveState.live);
      expect((await replay.site.detail(ref, from: searchCard)).card.title, plain.card.title);
    });

    test('S11 offline room is offline; S12 errorType 22 is NotFound', () async {
      final replay = _replay(['S11-room-offline', 'S12-room-notfound']);
      final offline = await replay.site.detail(RoomRef('kuaishou', 'tianci666'));
      expect(offline.state, LiveState.offline);
      expect(offline.danmakuKeys, isEmpty);
      await expectLater(replay.site.detail(RoomRef('kuaishou', 'purelive_fixture_404')), throwsA(isA<NotFound>()));
    });
  });

  group('streams', () {
    test('S09 live room: qualities best first, CDN lines, play headers, prefetch-only leases', () async {
      final replay = _replay(['S09-room-live']);
      final set = await replay.site.streams(_room('baixi9999999999'));
      expect(set.qualities, isNotEmpty);
      expect(set.selected, set.qualities.first);
      final ranks = set.qualities.map((q) => q.rank).toList();
      expect(ranks, [...ranks]..sort((a, b) => b.compareTo(a)));
      expect(set.lines, isNotEmpty);
      for (final line in set.lines) {
        expect(line.requested, set.selected);
        expect(line.format, StreamFormat.flv);
        expect(line.lineId, startsWith(line.url.host));
        expect(line.headers, KuaishouParse.playHeaders('baixi9999999999'));
        expect(line.headers.containsKey('cookie'), isFalse);
        final lease = line.lease!;
        expect(lease.cutsConnection, isFalse);
        expect(lease.expiresAt!.difference(_capturedAt).inSeconds, closeTo(86400, 5), reason: 'issued at receipt');
        expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
      }
      final lowest = await replay.site.streams(_room('baixi9999999999'), quality: set.qualities.last);
      expect(lowest.selected, set.qualities.last);
      expect(replay.http.requests, hasLength(2), reason: 'every call fetches a fresh room page (§6)');
    });

    test('the loop room plays; offline is StreamUnavailable; a missing streamer is NotFound', () async {
      final replay = _replay(['S09-room-live-replay', 'S11-room-offline', 'S12-room-notfound']);
      expect((await replay.site.streams(_room('KPL704668133', state: LiveState.replay))).lines, isNotEmpty);
      await expectLater(replay.site.streams(_room('tianci666')), throwsA(isA<StreamUnavailable>()));
      await expectLater(replay.site.streams(_room('purelive_fixture_404')), throwsA(isA<NotFound>()));
    });
  });

  group('cookies', () {
    const session =
        'kuaishou.live.bfb1s=092bf5827afad90f04b7f1694477c8a5; clientid=3; '
        'did=bjh_227k205y2093qn7d7389m2u2tqfv3ni9; client_key=26550b54; kpn=PQSH_HVMK';

    test('the anonymous session comes from room pages, goes to room pages only, never to the CDN', () async {
      final replay = _replay(['S09-room-live', 'S04-home-list', 'S06-search-author-ratelimited']);
      await replay.site.detail(RoomRef('kuaishou', 'baixi9999999999'));
      final set = await replay.site.streams(_room('baixi9999999999'));
      await replay.site.recommended();
      await expectLater(replay.site.search('王者荣耀'), throwsA(isA<RateLimited>()));
      final cookies = [for (final request in replay.http.requests) request.headers['cookie']];
      expect(cookies, [null, session, null, null]);
      expect(set.lines.every((line) => !line.headers.containsKey('cookie')), isTrue);
    });

    test('the session is used for 30 minutes, then the next page starts a new one', () async {
      var clock = _capturedAt;
      final replay = _replay(['S09-room-live'], now: () => clock);
      final ref = RoomRef('kuaishou', 'baixi9999999999');
      await replay.site.detail(ref);
      clock = clock.add(const Duration(minutes: 29));
      await replay.site.detail(ref);
      clock = clock.add(const Duration(minutes: 2));
      await replay.site.detail(ref);
      await replay.site.detail(ref);
      expect([for (final request in replay.http.requests) request.headers['cookie']], [null, session, null, session]);
    });

    test('a user cookie goes to room pages and the CDN only, and replaces the anonymous session', () async {
      final vault = MemoryCookieVault()..set('kuaishou', 'Cookie: did=web_user; kuaishou.live.bfb1s=u1\r\n');
      final replay = _replay(['S09-room-live', 'S04-home-list'], cookies: vault);
      await replay.site.detail(RoomRef('kuaishou', 'baixi9999999999'));
      final set = await replay.site.streams(_room('baixi9999999999'));
      await replay.site.recommended();
      expect(set.lines.every((line) => line.headers['cookie'] == 'did=web_user; kuaishou.live.bfb1s=u1'), isTrue);
      // Signed out: the pages answered to the user's cookie did not seed an
      // anonymous session.
      vault.set('kuaishou', null);
      await replay.site.detail(RoomRef('kuaishou', 'baixi9999999999'));
      expect(
        [for (final request in replay.http.requests) request.headers['cookie']],
        ['did=web_user; kuaishou.live.bfb1s=u1', 'did=web_user; kuaishou.live.bfb1s=u1', null, null],
      );
    });

    test('a refused page with a user cookie is RiskControl(cookieSuspect), not retried (REG-KUAISHOU-008)', () async {
      final vault = MemoryCookieVault()..set('kuaishou', 'did=stale');
      final refused = _roomPage({
        'isLiving': false,
        'errorType': {'type': 31, 'title': '错误代码31'},
      });
      final http = _Scripted([
        _answer(refused, setCookie: const ['did=web_new; path=/']),
      ]);
      final site = KuaishouSite(http, cookies: vault, now: () => _capturedAt);
      await expectLater(
        site.detail(RoomRef('kuaishou', 'abc')),
        throwsA(isA<RiskControl>().having((e) => e.cookieSuspect, 'cookieSuspect', isTrue)),
      );
      expect(http.requests, hasLength(1));
    });

    test('an anonymous refusal starts a session from its cookies, reports the did and retries once', () async {
      final http = _Scripted([
        _answer(_captcha, setCookie: const ['did=web_0123abcd; path=/; httponly', 'clientid=3; path=/']),
        _answer('{"result":1}'),
        _recorded('S09-room-live'),
      ]);
      final site = KuaishouSite(http, now: () => _capturedAt, random: Random(1));
      final detail = await site.detail(RoomRef('kuaishou', 'baixi9999999999'));
      expect(detail.state, LiveState.live);
      expect(http.requests.map((r) => '${r.method} ${r.url.host}'), [
        'GET live.kuaishou.com',
        'POST log-sdk.ksapisrv.com',
        'GET live.kuaishou.com',
      ]);
      expect(http.requests.first.headers.containsKey('cookie'), isFalse);
      final report = http.requests[1];
      expect(report.headers.containsKey('cookie'), isFalse, reason: 'the session stays with live.kuaishou.com');
      final body = jsonDecode(utf8.decode(report.body!)) as Map<String, dynamic>;
      expect(((body['common'] as Map)['identity_package'] as Map)['device_id'], 'web_0123abcd');
      expect(http.requests.last.headers['cookie'], 'did=web_0123abcd; clientid=3');
    });

    test('a failed device report does not stop the retry', () async {
      final http = _Scripted([
        _answer(_captcha, setCookie: const ['did=web_1']),
        _fail(TransportReason.connect),
        _recorded('S09-room-live'),
      ]);
      final site = KuaishouSite(http, now: () => _capturedAt);
      expect((await site.detail(RoomRef('kuaishou', 'baixi9999999999'))).state, LiveState.live);
      expect(http.requests, hasLength(3));
    });

    test('a refusal that sets no cookie is RiskControl at once; a refused session is dropped', () async {
      final bare = _Scripted([_answer(_captcha)]);
      await expectLater(
        KuaishouSite(bare, now: () => _capturedAt).detail(RoomRef('kuaishou', 'abc')),
        throwsA(isA<RiskControl>().having((e) => e.cookieSuspect, 'cookieSuspect', isFalse)),
      );
      expect(bare.requests, hasLength(1));

      final http = _Scripted([_recorded('S09-room-live'), _answer(_captcha), _recorded('S09-room-live')]);
      final site = KuaishouSite(http, now: () => _capturedAt);
      final ref = RoomRef('kuaishou', 'baixi9999999999');
      await site.detail(ref);
      await expectLater(site.detail(ref), throwsA(isA<RiskControl>()));
      await site.detail(ref);
      expect([for (final request in http.requests) request.headers['cookie']], [null, session, null]);
    });
  });

  group('transport', () {
    test('transport failures are NetworkFailure; cancellation is passed through', () async {
      final down = KuaishouSite(_Scripted([_fail(TransportReason.timeout)]), now: () => _capturedAt);
      await expectLater(down.recommended(), throwsA(isA<NetworkFailure>()));
      final cancelled = KuaishouSite(_Scripted([_fail(TransportReason.cancelled)]), now: () => _capturedAt);
      await expectLater(
        cancelled.detail(RoomRef('kuaishou', 'abc')),
        throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
      );
    });

    test('one valid browser identity: a current Chrome UA with matching client hints (REG-KUAISHOU-019)', () async {
      final replay = _replay(['S04-home-list', 'S09-room-live', 'S06-search-author-ratelimited']);
      await replay.site.recommended();
      await replay.site.detail(RoomRef('kuaishou', 'baixi9999999999'));
      await expectLater(replay.site.search('王者荣耀'), throwsA(isA<RateLimited>()));
      final ua = RegExp(
        r'^Mozilla/5\.0 \(Macintosh; Intel Mac OS X \d+_\d+(?:_\d+)?\) AppleWebKit/537\.36 '
        r'\(KHTML, like Gecko\) Chrome/(\d+)\.0\.0\.0 Safari/537\.36$',
      );
      final hint = RegExp(r'^"([^"]+)";v="(\d+)"$');
      for (final request in replay.http.requests) {
        final headers = request.headers;
        expect(headers.keys.every((name) => name == name.toLowerCase()), isTrue);
        expect(headers.values.every((value) => !value.contains('\n') && !value.contains('\r')), isTrue);
        final agent = headers['user-agent']!;
        final major = ua.firstMatch(agent)?.group(1);
        expect(major, isNotNull, reason: agent);
        expect(int.parse(major!), greaterThanOrEqualTo(140));
        expect(agent, KuaishouParse.playHeaders(null)['user-agent'], reason: 'the same browser as the play headers');
        final brands = {
          for (final item in headers['sec-ch-ua']!.split(', '))
            if (hint.firstMatch(item) case final match?) match.group(1)!: match.group(2)!,
        };
        expect(brands, hasLength(3), reason: 'every brand is a quoted string with a quoted version');
        expect(brands['Google Chrome'], major);
        expect(brands['Chromium'], major);
        expect(headers['sec-ch-ua-platform'], '"macOS"');
        expect(headers['sec-ch-ua-mobile'], '?0');
      }
    });
  });

  group('links', () {
    test('room pages on live.kuaishou.com and .cn; navigation pages and look-alikes are not rooms', () async {
      final site = KuaishouSite(ReplayHttp(const []));
      Future<String?> room(String input) async => (await site.resolve(input))?.roomId;
      expect(await room('https://live.kuaishou.com/u/tianci666'), 'tianci666');
      expect(await room('http://live.kuaishou.com/u/ATM-Heros/?from=share#top'), 'ATM-Heros');
      expect(await room('https://live.kuaishou.cn/u/3xgw4a6r5eiu4nu/'), '3xgw4a6r5eiu4nu');
      expect(await room('https://LIVE.kuaishou.com/U/abc_def'), 'abc_def');
      expect(await room('快来看我直播 https://live.kuaishou.com/u/tianci666。'), 'tianci666');
      expect(await room('(https://live.kuaishou.com/u/tianci666).'), 'tianci666');
      expect(
        await room(
          '先看 https://live.bilibili.com/6 再看 https://live.kuaishou.com/search?keyword=x 和 https://live.kuaishou.com/u/abc',
        ),
        'abc',
        reason: 'unrelated links do not block a later room link',
      );
      for (final input in [
        'https://live.kuaishou.com/u/',
        'https://live.kuaishou.com/search?keyword=%E7%8E%8B',
        'https://live.kuaishou.com/u/search',
        'https://live.kuaishou.com/u/undefined',
        'https://live.kuaishou.com/cate/1001',
        'https://live.kuaishou.com.evil.test/u/tianci666',
        'https://evil.test/live.kuaishou.com/u/tianci666',
        'ftp://live.kuaishou.com/u/tianci666',
        'tianci666',
        'https://www.douyu.com/9999',
      ]) {
        expect(await site.resolve(input), isNull, reason: input);
      }
    });

    test('share links: a redirect to a room page resolves; everything else is UnsupportedLink', () async {
      final http = ReplayHttp([
        _synthetic(
          'https://v.kuaishou.com/AbCd12',
          '',
          status: 302,
          headers: {
            'location': ['https://live.kuaishou.com/u/tianci666?cc=share_copylink'],
          },
        ),
        _synthetic(
          'https://v.kuaishou.com/Mobile1',
          '',
          status: 302,
          headers: {
            'location': ['https://v.m.chenzhongtech.com/fw/live/3xgw4a6r5eiu4nu'],
          },
        ),
        _synthetic('https://v.kuaishou.com/Page1', '<html></html>'),
      ]);
      final site = KuaishouSite(http);
      expect(await site.resolve('【快手】看直播 https://v.kuaishou.com/AbCd12 复制打开'), RoomRef('kuaishou', 'tianci666'));
      expect(http.requests.single.followRedirects, isFalse);
      expect(http.requests.single.headers.containsKey('cookie'), isFalse);
      for (final input in [
        'https://v.kuaishou.com/Mobile1',
        'https://v.kuaishou.com/Page1',
        'https://m.gifshow.com/fw/live/3xgw4a6r5eiu4nu',
        'https://v.m.chenzhongtech.com/fw/live/3xgw4a6r5eiu4nu',
        'https://www.kuaishou.com/profile/3xgw4a6r5eiu4nu',
      ]) {
        await expectLater(site.resolve(input), throwsA(isA<UnsupportedLink>()), reason: input);
      }
      // A room link anywhere in the text wins without a request.
      final before = http.requests.length;
      expect(
        await site.resolve('https://v.kuaishou.com/Page1 https://live.kuaishou.com/u/abc'),
        RoomRef('kuaishou', 'abc'),
      );
      expect(http.requests, hasLength(before));
    });
  });
}
