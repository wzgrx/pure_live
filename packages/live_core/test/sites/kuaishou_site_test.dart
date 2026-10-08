// KuaishouSite over the recorded responses (ReplayHttp): the anonymous
// session (bootstrap, device report, 30-minute lifetime, one retry after a
// refusal), the browser identity, catalog and area paging, search, room
// depths, streams from the page, links and error mapping.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/kuaishou';
final DateTime _now = Fixture.load('kuaishou', 'S09-room-live').capturedAt;

const _live = 'baixi9999999999';
const _loop = 'KPL704668133';
const _offline = 'tianci666';
const _missing = 'purelive_fixture_404';
const _report = '/rest/wd/common/log/collect/misc2';

/// The anonymous session the recorded room pages set.
const _session =
    'kuaishou.live.bfb1s=092bf5827afad90f04b7f1694477c8a5; clientid=3; '
    'did=bjh_227k205y2093qn7d7389m2u2tqfv3ni9; client_key=26550b54; kpn=PQSH_HVMK';

const _captcha = '<html><body><div id="captcha">请完成安全验证</div></body></html>';

ReplaySample _synthetic(
  String url,
  Object body, {
  int status = 200,
  String method = 'GET',
  Map<String, List<String>> headers = const {},
}) => ReplaySample(
  method: method,
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
  headers: headers,
);

/// A recorded sample's body served at another URL.
ReplaySample _moved(String sample, String url) {
  final recorded = ReplaySample.load('$_root/$sample');
  return ReplaySample(method: 'GET', url: Uri.parse(url), status: recorded.status, bytes: recorded.bytes);
}

final ReplaySample _reportAnswer = _synthetic(
  'https://log-sdk.ksapisrv.com$_report?v=3.9.49&kpn=KS_GAME_LIVE_PC',
  '{"result":1}',
  method: 'POST',
);

String _page(String roomId) => 'https://live.kuaishou.com/u/$roomId';

/// Answers scripted responses for a path in order (a [TransportReason]
/// throws), then replays [inner].
final class _Sequenced implements LiveHttp {
  new(this.inner, this.script);

  final ReplayHttp inner;
  final Map<String, List<Object>> script;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final queue = script[request.url.path];
    if (queue == null || queue.isEmpty) return await inner.send(request);
    inner.requests.add(request);
    var next = queue.removeAt(0);
    if (next is Future<Object>) next = await next;
    if (next is TransportReason) throw TransportFailure('kuaishou', next, 'scripted');
    final sample = next as ReplaySample;
    return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}

typedef _Setup = ({KuaishouSite site, ReplayHttp http});

_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  CookieVault? cookies,
  Map<String, List<Object>> script = const {},
  DateTime Function()? now,
  int seed = 1,
}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name'), _reportAnswer]);
  final site = KuaishouSite(
    script.isEmpty
        ? http
        : _Sequenced(http, {
            for (final MapEntry(:key, :value) in script.entries) key: [...value],
          }),
    cookies: cookies,
    now: now ?? () => _now,
    random: Random(seed),
  );
  return (site: site, http: http);
}

/// `METHOD path cookie` of every request, `-` without a cookie.
List<String> _trace(ReplayHttp http) => [
  for (final request in http.requests) '${request.method} ${request.url.path} ${request.headers['cookie'] ?? '-'}',
];

int _count(ReplayHttp http, String path) => http.requests.where((request) => request.url.path == path).length;

List<String> _ids(String sample) => [
  for (final item in ((jsonDecode(Fixture.load('kuaishou', sample).body) as Map)['data'] as Map)['list'] as List)
    (item as Map)['id'] as String,
];

/// The request names one browser: the client hints match the UA's browser,
/// version and platform (quoted), and Safari sends none.
void _expectOneBrowser(Map<String, String> headers) {
  final agent = headers['user-agent']!;
  if (!agent.contains('Chrome/')) {
    expect(agent, contains('Version/'), reason: agent);
    expect(headers.keys.where((name) => name.startsWith('sec-ch-ua')), isEmpty, reason: 'Safari sends no hints');
    return;
  }
  final edge = RegExp(r'Edg/(\d+)').firstMatch(agent)?.group(1);
  final chrome = RegExp(r'Chrome/(\d+)\.0\.0\.0').firstMatch(agent)!.group(1);
  expect(headers['sec-ch-ua'], contains(edge == null ? '"Google Chrome";v="$chrome"' : '"Microsoft Edge";v="$edge"'));
  expect(headers['sec-ch-ua'], contains('"Chromium";v="${edge ?? chrome}"'));
  final platform = agent.contains('Macintosh')
      ? 'macOS'
      : agent.contains('Windows')
      ? 'Windows'
      : 'Linux';
  expect(headers['sec-ch-ua-platform'], '"$platform"');
  expect(headers['sec-ch-ua-mobile'], '?0');
}

void main() {
  group('catalog', () {
    test('categories walk all eight types page by page while hasMore says so; no cookie', () async {
      // The recording stopped while types 1–4 still said hasMore: their end
      // pages are synthetic; types 5–8 end on recorded pages.
      const end = '{"data":{"list":[],"hasMore":false}}';
      final setup = _setup(
        [
          for (var type = 1; type <= 8; type++) 'S01-category-type$type-p1',
          'S01-category-type1-p2',
          'S01-category-type5-p2',
        ],
        extra: [
          _synthetic('https://live.kuaishou.com/live_api/category/data?type=1&page=3&size=30', end),
          for (final type in [2, 3, 4])
            _synthetic('https://live.kuaishou.com/live_api/category/data?type=$type&page=2&size=30', end),
        ],
      );
      final categories = await setup.site.getCategories(1, 20);
      expect(categories.map((category) => '${category.id} ${category.name}'), [
        '1 热门',
        '2 网游',
        '3 单机',
        '4 手游',
        '5 棋牌',
        '6 娱乐',
        '7 综合',
        '8 文化',
      ]);
      expect(
        [
          for (final request in setup.http.requests)
            '${request.url.queryParameters['type']}/${request.url.queryParameters['page']}',
        ],
        ['1/1', '1/2', '1/3', '2/1', '2/2', '3/1', '3/2', '4/1', '4/2', '5/1', '5/2', '6/1', '7/1', '8/1'],
      );
      final byType = {for (final category in categories) category.id: category.children};
      expect(byType['1']!.map((area) => area.areaId), [
        ..._ids('S01-category-type1-p1'),
        ..._ids('S01-category-type1-p2'),
      ]);
      // Walks that end on recorded pages collect what 3.x collected.
      for (final (type, sample) in [
        (5, 'S01-category-type5-p2'),
        (6, 'S01-category-type6-p1'),
        (7, 'S01-category-type7-p1'),
        (8, 'S01-category-type8-p1'),
      ]) {
        final legacy = (Fixture.load('kuaishou', sample).legacy as Map)['getAllSubCategores'] as Map;
        expect(byType['$type']!.map((area) => area.areaId), legacy['areaIds'], reason: 'type $type');
      }
      for (final category in categories) {
        expect(
          category.children.every((area) => area.areaType == category.id && area.typeName == category.name),
          isTrue,
        );
      }
      expect(setup.http.requests.every((request) => !request.headers.containsKey('cookie')), isTrue);
    });

    test('a failing page fails the catalog instead of returning part of it', () async {
      final limited = _setup(
        ['S01-category-type1-p1'],
        extra: [
          _synthetic('https://live.kuaishou.com/live_api/category/data?type=1&page=2&size=30', {
            'data': {'result': 2, 'error_msg': '操作太快了，请稍微休息一下'},
          }),
        ],
      );
      await expectLater(limited.site.getCategories(1, 20), throwsA(isA<RateLimited>()));
      final broken = _setup(
        [],
        extra: [_synthetic('https://live.kuaishou.com/live_api/category/data?type=1&page=1&size=30', '', status: 502)],
      );
      await expectLater(broken.site.getCategories(1, 20), throwsA(isA<NetworkFailure>()));
    });

    test('a page with nothing new ends a category (a server repeating page 1 cannot loop it)', () async {
      final setup = _setup(
        [],
        extra: [
          _moved('S01-category-type1-p1', 'https://live.kuaishou.com/live_api/category/data?type=1&page=1&size=30'),
          _moved('S01-category-type1-p1', 'https://live.kuaishou.com/live_api/category/data?type=1&page=2&size=30'),
          for (var type = 2; type <= 8; type++)
            _synthetic(
              'https://live.kuaishou.com/live_api/category/data?type=$type&page=1&size=30',
              '{"data":{"list":[],"hasMore":false}}',
            ),
        ],
      );
      final categories = await setup.site.getCategories(1, 20);
      expect(categories.first.children.map((area) => area.areaId), _ids('S01-category-type1-p1'));
      expect(setup.http.requests.where((request) => request.url.queryParameters['type'] == '1'), hasLength(2));
    });
  });

  group('area rooms', () {
    const game = LiveArea(platform: 'kuaishou', areaType: '1', areaId: '1001', areaName: '王者荣耀');
    const show = LiveArea(platform: 'kuaishou', areaType: '6', areaId: '1000004', areaName: '才艺');

    test('game areas (id shorter than 7) page by number on gameboard/list', () async {
      final setup = _setup(['S02-gameboard-p1', 'S02-gameboard-p2']);
      expect(await setup.site.getCategoryRooms(game), hasLength(20));
      // 20 cards, one of them already on page 1 (M4.U.5, see below).
      expect(await setup.site.getCategoryRooms(game, page: 2), hasLength(19));
      expect(setup.http.requests.map((request) => request.url), [
        Fixture.load('kuaishou', 'S02-gameboard-p1').url,
        Fixture.load('kuaishou', 'S02-gameboard-p2').url,
      ]);
      final card = (await setup.site.getCategoryRooms(game)).first;
      expect((card.danmakuData! as KuaishouDanmakuArgs).cookie, isEmpty, reason: 'no session yet');
    });

    test('non-gameboard page 2 sends page 1’s cursor and is the real page 2 (REG-KUAISHOU-022)', () async {
      // Both recorded page 2 requests are offered; only the one with the
      // cursor matches what the adapter sends (3.x sent the other and got
      // page 1 again).
      final setup = _setup(['S03-non-gameboard-p1', 'S03-non-gameboard-p2', 'S03-non-gameboard-p2-cursor']);
      final page1 = await setup.site.getCategoryRooms(show);
      final page2 = await setup.site.getCategoryRooms(show, page: 2);
      expect(setup.http.requests.last.url, Fixture.load('kuaishou', 'S03-non-gameboard-p2-cursor').url);
      expect(page2.map((room) => room.roomId).toSet().intersection(page1.map((room) => room.roomId).toSet()), isEmpty);
    });

    test('a page not reached yet is walked to from page 1; a page past the last is empty without a request', () async {
      final setup = _setup(['S03-non-gameboard-p1', 'S03-non-gameboard-p2-cursor']);
      expect(await setup.site.getCategoryRooms(show, page: 2), hasLength(20));
      expect(setup.http.requests.map((request) => request.url.queryParameters['page']), ['1', '2']);

      final endPage = _setup(
        [],
        extra: [
          _synthetic('https://live.kuaishou.com/live_api/gameboard/list?filterType=0&pageSize=20&gameId=7&page=1', {
            'data': {
              'hasMore': false,
              'list': [
                {
                  'id': 'L',
                  'author': {'id': 'abc'},
                },
              ],
            },
          }),
        ],
      );
      const small = LiveArea(platform: 'kuaishou', areaId: '7');
      expect(await endPage.site.getCategoryRooms(small), hasLength(1));
      expect(await endPage.site.getCategoryRooms(small, page: 2), isEmpty);
      expect(endPage.http.requests, hasLength(1));
    });

    test('M4.U.5 翻页: a room already listed since page 1 is left out of later pages; no extra request', () async {
      // The live ranking moved between the two recorded requests: qingyi223
      // is on both pages.
      final setup = _setup(['S02-gameboard-p1', 'S02-gameboard-p2']);
      final page1 = await setup.site.getCategoryRooms(game);
      expect(page1.map((room) => room.roomId), contains('qingyi223'));
      final raw2 = [
        for (final item
            in ((jsonDecode(Fixture.load('kuaishou', 'S02-gameboard-p2').body) as Map)['data'] as Map)['list'] as List)
          ((item as Map)['author'] as Map)['id'] as String,
      ];
      expect(raw2, contains('qingyi223'));
      final page2 = await setup.site.getCategoryRooms(game, page: 2);
      expect(page2.map((room) => room.roomId), [...raw2.where((id) => id != 'qingyi223')], reason: 'order kept');
      expect(
        (await setup.site.getCategoryRooms(game, page: 2)).map((room) => room.roomId),
        page2.map((room) => room.roomId),
        reason: 'reading a page again gives the same rooms',
      );
      await setup.site.getCategoryRooms(game);
      expect(await setup.site.getCategoryRooms(game, page: 2), hasLength(19), reason: 'page 1 again starts over');
      expect(setup.http.requests, hasLength(5), reason: 'one request per page read, as before');

      final repeated = _setup(
        [],
        extra: [
          _synthetic('https://live.kuaishou.com/live_api/gameboard/list?filterType=0&pageSize=20&gameId=7&page=1', {
            'data': {
              'hasMore': false,
              'list': [
                for (final id in ['a', 'b', 'a'])
                  {
                    'id': 'L$id',
                    'author': {'id': id},
                  },
              ],
            },
          }),
        ],
      );
      expect(
        (await repeated.site.getCategoryRooms(const LiveArea(platform: 'kuaishou', areaId: '7')))
            .map((room) => room.roomId),
        ['a', 'b'],
        reason: 'and once within a page',
      );
    });

    test('M4.U.5 开播时间: a card’s start stays with a follow refreshed while live and goes when it ends', () async {
      final setup = _setup(
        ['S02-gameboard-p1', 'S09-room-live'],
        script: {
          '/u/$_live': [ReplaySample.load('$_root/S09-room-live'), _moved('S11-room-offline', _page(_live))],
        },
      );
      final card = (await setup.site.getCategoryRooms(game)).firstWhere((room) => room.roomId == _live);
      expect(card.startedAt, DateTime.utc(2026, 9, 27, 9, 19, 38, 677), reason: 'statrtTime 1790500778677');
      expect(card.restriction, LiveRestriction.none);
      final live = card.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: _live));
      expect((live.isLiveNow, live.startedAt, live.restriction), (true, card.startedAt, LiveRestriction.none));
      final ended = live.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: _live));
      expect((ended.isLiveNow, ended.startedAt, ended.restriction), (false, null, null));
      expect(_count(setup.http, '/u/$_live'), 2, reason: 'one request per refresh, as before');
    });
  });

  group('recommend and search', () {
    test('the home list: one page of streamers', () async {
      final setup = _setup(['S04-home-list']);
      final rooms = await setup.site.getRecommendRooms();
      expect(rooms, hasLength(47));
      expect(await setup.site.getRecommendRooms(page: 2), isEmpty);
      expect(setup.http.requests, hasLength(1));
      expect(setup.http.requests.single.headers.containsKey('cookie'), isFalse);
    });

    test('result 2 is RateLimited (REG-KUAISHOU-015); the search page is the referer; never a cookie', () async {
      final vault = MemoryCookieVault()..set('kuaishou', 'did=user');
      addTearDown(vault.dispose);
      final setup = _setup(['S06-search-author-ratelimited'], cookies: vault);
      await expectLater(
        setup.site.searchRooms(' 王者荣耀 '),
        throwsA(isA<RateLimited>().having((error) => error.detail, 'detail', contains('操作太快'))),
      );
      final request = setup.http.requests.single;
      expect(request.url, Fixture.load('kuaishou', 'S06-search-author-ratelimited').url);
      expect(
        request.headers['referer'],
        'https://live.kuaishou.com/search?keyword=%E7%8E%8B%E8%80%85%E8%8D%A3%E8%80%80',
      );
      expect(request.headers.containsKey('cookie'), isFalse);
    });

    test('result 10 (the guest gate) is RiskControl on the author search too', () async {
      final url = Fixture.load('kuaishou', 'S06-search-author-ratelimited').url.toString();
      final setup = _setup([], extra: [_moved('S08-search-livestream-busy', url)]);
      await expectLater(setup.site.searchRooms('王者荣耀'), throwsA(isA<RiskControl>()));
    });

    test('at most pageSize results; streamers for searchAnchors; a blank keyword sends nothing', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://live.kuaishou.com/live_api/search/author?keyword=x&page=2&lssid=', {
            'data': {
              'result': 1,
              'list': [
                {'id': 'a', 'name': 'A', 'avatar': 'https://p.test/a.jpg', 'living': true},
                {'id': 'b', 'name': 'B', 'living': false},
              ],
            },
          }),
        ],
      );
      expect((await setup.site.searchRooms('x', page: 2, pageSize: 1)).map((room) => room.roomId), ['a']);
      final anchors = await setup.site.searchAnchors('x', page: 2);
      expect(anchors.map((anchor) => (anchor.roomId, anchor.userName, anchor.avatar, anchor.liveStatus)), [
        ('a', 'A', 'https://p.test/a.jpg', true),
        ('b', 'B', '', false),
      ]);
      final before = setup.http.requests.length;
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(setup.http.requests, hasLength(before));
    });
  });

  group('anonymous session', () {
    test('room entry: a bare visit makes the session and is the room page; its did is reported', () async {
      final setup = _setup(['S09-room-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      // G03.1: the visit is the room page, so no second request for it.
      expect(_trace(setup.http), ['GET /u/$_live -', 'POST $_report -']);
      final report = jsonDecode(utf8.decode(setup.http.requests[1].body!)) as Map<String, dynamic>;
      expect(
        ((report['common'] as Map)['identity_package'] as Map)['device_id'],
        'bjh_227k205y2093qn7d7389m2u2tqfv3ni9',
      );
      expect(setup.http.requests[1].headers['content-type'], startsWith('application/json'));
      expect(room.isLiveNow, isTrue);
      expect(room.roomId, _live);
      final args = room.danmakuData! as KuaishouDanmakuArgs;
      expect((args.liveStreamId, args.cookie), ('XT8F1KPOf0c', _session), reason: '3.x gave the feed the session');
      expect((room.data! as KuaishouRoomData).playUrls, isNotNull);
    });

    test('the session is reused for 30 minutes, then the next room entry makes a new one', () async {
      var clock = _now;
      final setup = _setup(['S09-room-live'], now: () => clock);
      await setup.site.getRoomDetail(roomId: _live);
      clock = clock.add(const Duration(minutes: 29));
      await setup.site.getRoomDetailForRecording(roomId: _live);
      expect(_count(setup.http, _report), 1);
      clock = clock.add(const Duration(minutes: 2));
      await setup.site.getRoomDetail(roomId: _live);
      expect(_trace(setup.http), [
        'GET /u/$_live -',
        'POST $_report -',
        'GET /u/$_live $_session',
        'GET /u/$_live -',
        'POST $_report -',
      ]);
    });

    test('G03.1: the report does not hold up a room its visit has read', () async {
      final report = Completer<Object>();
      final setup = _setup(
        ['S09-room-live'],
        script: {
          _report: [report.future],
        },
      );
      LiveRoom? room;
      unawaited(setup.site.getRoomDetail(roomId: _live).then((value) => room = value));
      await pumpEventQueue();
      expect(room?.isLiveNow, isTrue, reason: 'the report is still out');
      expect(_trace(setup.http), ['GET /u/$_live -', 'POST $_report -']);
      report.complete(_reportAnswer);
      await pumpEventQueue();
    });

    test('G03.1: a visit that is no room page leaves it to the page with the session, after the report', () async {
      final recorded = ReplaySample.load('$_root/S09-room-live');
      final refused = _synthetic(_page(_live), _captcha, headers: recorded.headers);
      final report = Completer<Object>();
      final setup = _setup(
        ['S09-room-live'],
        script: {
          '/u/$_live': [refused],
          _report: [report.future],
        },
      );
      LiveRoom? room;
      unawaited(setup.site.getRoomDetail(roomId: _live).then((value) => room = value));
      await pumpEventQueue();
      expect(_trace(setup.http), ['GET /u/$_live -', 'POST $_report -'], reason: 'the page waits for the report');
      report.complete(_reportAnswer);
      await pumpEventQueue();
      expect(_trace(setup.http), ['GET /u/$_live -', 'POST $_report -', 'GET /u/$_live $_session']);
      expect(room?.isLiveNow, isTrue);
      expect((room!.danmakuData! as KuaishouDanmakuArgs).cookie, _session);
    });

    test('concurrent room entries share one bootstrap', () async {
      final setup = _setup(['S09-room-live', 'S11-room-offline']);
      final rooms = await Future.wait([
        setup.site.getRoomDetail(roomId: _live),
        setup.site.getRoomDetail(roomId: _offline),
      ]);
      expect(rooms.map((room) => room.effectiveLiveStatus), [LiveStatus.live, LiveStatus.offline]);
      expect(_count(setup.http, _report), 1);
      expect(_trace(setup.http).where((line) => line.startsWith('GET') && line.endsWith(' -')), hasLength(1));
    });

    test('a follow refresh goes as it is: no bootstrap, no streams; the live session when there is one', () async {
      final setup = _setup(['S09-room-live', 'S11-room-offline']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
      expect(_trace(setup.http), ['GET /u/$_live -']);
      expect((room.data! as KuaishouRoomData).playUrls, isNull);
      expect((room.danmakuData! as KuaishouDanmakuArgs).cookie, isEmpty);
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
      await setup.site.getRoomDetail(roomId: _live);
      await setup.site.getRoomDetailForRefresh(roomId: _offline);
      expect(_trace(setup.http).last, 'GET /u/$_offline $_session');
    });

    test('a refused page drops the session, makes a new one and is retried once', () async {
      final refused = _synthetic(_page(_live), _captcha);
      final withSession = _synthetic(
        _page(_live),
        _captcha,
        headers: ReplaySample.load('$_root/S09-room-live').headers,
      );
      final setup = _setup(
        ['S09-room-live'],
        script: {
          '/u/$_live': [withSession, refused],
        },
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      // The new session's visit reads as the room: no further request.
      expect(_trace(setup.http), [
        'GET /u/$_live -',
        'POST $_report -',
        'GET /u/$_live $_session',
        'GET /u/$_live -',
        'POST $_report -',
      ]);
    });

    test('a refused refresh is retried once with a new session (3.x did the same)', () async {
      final setup = _setup(
        ['S09-room-live'],
        script: {
          '/u/$_live': [_synthetic(_page(_live), _captcha)],
        },
      );
      expect((await setup.site.getRoomDetailForRefresh(roomId: _live)).isLiveNow, isTrue);
      expect(_trace(setup.http), ['GET /u/$_live -', 'GET /u/$_live -', 'POST $_report -']);
    });

    test('refused twice is RiskControl; missing streamers and offline rooms are answers, not retried', () async {
      final refused = _synthetic(_page(_live), _captcha);
      final twice = _setup(
        [],
        script: {
          '/u/$_live': [refused, refused, refused],
        },
      );
      await expectLater(
        twice.site.getRoomDetailForRefresh(roomId: _live),
        throwsA(isA<RiskControl>().having((error) => error.cookieSuspect, 'cookieSuspect', isFalse)),
      );
      expect(_count(twice.http, '/u/$_live'), 3, reason: 'the page, the new session’s visit, the one retry');

      final setup = _setup(['S11-room-offline', 'S12-room-notfound']);
      expect((await setup.site.getRoomDetailForRefresh(roomId: _offline)).effectiveLiveStatus, LiveStatus.offline);
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: _missing), throwsA(isA<NotFound>()));
      expect(_trace(setup.http), ['GET /u/$_offline -', 'GET /u/$_missing -']);
    });

    test('a failed device report does not hold the room up', () async {
      final setup = _setup(
        ['S09-room-live'],
        script: {
          _report: [TransportReason.connect],
        },
      );
      expect((await setup.site.getRoomDetail(roomId: _live)).isLiveNow, isTrue);
      expect(_trace(setup.http), ['GET /u/$_live -', 'POST $_report -']);
    });
  });

  group('user cookie', () {
    test('room pages carry it alone: no session, no report; the feed and the media get it too', () async {
      final vault = MemoryCookieVault()..set('kuaishou', ' did=web_user;\n kuaishou.live.bfb1s=u1 ');
      addTearDown(vault.dispose);
      const cookie = 'did=web_user; kuaishou.live.bfb1s=u1';
      final setup = _setup(['S09-room-live', 'S04-home-list'], cookies: vault);
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(_trace(setup.http), ['GET /u/$_live $cookie']);
      expect((room.danmakuData! as KuaishouDanmakuArgs).cookie, cookie);
      final qualities = await setup.site.getPlayQualities(detail: room);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.first);
      expect(resolution.lines.every((line) => line.headers['cookie'] == cookie), isTrue);
      final cards = await setup.site.getRecommendRooms();
      expect(setup.http.requests.last.headers.containsKey('cookie'), isFalse, reason: 'lists never carry a cookie');
      expect((cards.first.danmakuData! as KuaishouDanmakuArgs).cookie, cookie);
    });

    test('a refusal with it is RiskControl with the cookie suspect, not retried (REG-KUAISHOU-008)', () async {
      final vault = MemoryCookieVault()..set('kuaishou', 'did=stale');
      addTearDown(vault.dispose);
      final setup = _setup(
        [],
        cookies: vault,
        extra: [
          _synthetic(
            _page('abc'),
            '<html><script>window.__INITIAL_STATE__={"liveroom":{"playList":[{"isLiving":false,'
            '"errorType":{"type":31,"title":"错误代码31"}}]}};</script></html>',
          ),
        ],
      );
      await expectLater(
        setup.site.getRoomDetail(roomId: 'abc'),
        throwsA(isA<RiskControl>().having((error) => error.cookieSuspect, 'cookieSuspect', isTrue)),
      );
      expect(_trace(setup.http), ['GET /u/abc did=stale']);
    });
  });

  group('browser identity', () {
    test('every request names one browser: UA and matching hints (REG-KUAISHOU-019)', () async {
      for (var seed = 0; seed < 12; seed++) {
        final setup = _setup(['S04-home-list', 'S09-room-live', 'S06-search-author-ratelimited'], seed: seed);
        await setup.site.getRecommendRooms();
        await setup.site.getRoomDetail(roomId: _live);
        await expectLater(setup.site.searchRooms('王者荣耀'), throwsA(isA<RateLimited>()));
        for (final request in setup.http.requests) {
          expect(request.headers.keys.every((name) => name == name.toLowerCase()), isTrue);
          _expectOneBrowser(request.headers);
        }
        final pages = [
          for (final request in setup.http.requests)
            if (request.url.path == '/u/$_live' || request.url.path == _report) request.headers['user-agent'],
        ];
        expect(pages.toSet(), hasLength(1), reason: 'one browser for the whole session (seed $seed)');
        expect(setup.http.requests.last.headers['user-agent'], pages.first, reason: 'and for what follows it');
      }
    });

    test('the browsers are current: Chrome and Edge majors and Safari versions from BrowserUserAgent', () async {
      final agents = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        final setup = _setup(['S04-home-list'], seed: seed);
        await setup.site.getRecommendRooms();
        agents.add(setup.http.requests.single.headers['user-agent']!);
      }
      expect(agents.length, greaterThan(3), reason: 'picked at random like 3.x');
      for (final agent in agents) {
        final major = RegExp(r'(?:Chrome|Version)/(\d+)').firstMatch(agent)!.group(1)!;
        expect(
          [
            ...BrowserUserAgent.chromeMajors.map((major) => '$major'),
            ...BrowserUserAgent.edgeMajors.map((major) => '$major'),
            ...BrowserUserAgent.safariVersions.map((version) => version.split('.').first),
          ],
          contains(major),
          reason: agent,
        );
        expect(agent, isNot(contains('-')), reason: '3.x turned the macOS version into hyphens');
      }
    });
  });

  group('streams', () {
    test('qualities and lines come from the page the room was opened with; no request', () async {
      final setup = _setup(['S09-room-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final before = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.sort), [130, 70, 50, 30]);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities[1]);
      expect(resolution.appliedQualityData, qualities[1].id);
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities[1]), resolution.urls);
      expect(resolution.urls, qualities[1].data);
      for (final line in resolution.lines) {
        expect(line.headers, KuaishouApi.mediaHeaders(_live), reason: 'the session never goes to the CDN');
        expect(line.lease!.expiresAt!.difference(_now).inSeconds, closeTo(86400, 5));
      }
      expect(setup.http.requests, hasLength(before));
    });

    test('M4.D “优先 H.264” is read at each call: H.265-only qualities last, or by sort when off', () async {
      final fixture = Fixture.load('kuaishou', 'S10-room-live-hevc');
      final room = KuaishouApi.roomDetail(fixture.body, requestedId: 'KPL704668133', issuedAt: fixture.capturedAt);
      var preferH264 = true;
      final http = ReplayHttp(const []);
      final site = KuaishouSite(http, preferH264: () => preferH264, now: () => fixture.capturedAt);
      expect((await site.getPlayQualities(detail: room)).map((quality) => quality.sort), [70, 50, 30, 490, 130]);
      preferH264 = false;
      expect((await site.getPlayQualities(detail: room)).map((quality) => quality.sort), [490, 130, 70, 50, 30]);
      expect(http.requests, isEmpty);
    });

    test('recovery reads a fresh page; a room without streams (a refreshed follow) reads one too', () async {
      final setup = _setup(['S09-room-live']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities, hasLength(4));
      final pages = _count(setup.http, '/u/$_live');
      final recovered = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: qualities.first);
      expect(recovered.lines, isNotEmpty);
      expect(_count(setup.http, '/u/$_live'), pages + 1);
      final bare = LiveRoom(platform: 'kuaishou', roomId: _live);
      expect(await setup.site.getPlayQualities(detail: bare), hasLength(4));
    });

    test('the loop room plays; offline is StreamUnavailable; a missing streamer is NotFound', () async {
      final setup = _setup(['S09-room-live-replay', 'S11-room-offline', 'S12-room-notfound']);
      final loop = LiveRoom(platform: 'kuaishou', roomId: _loop);
      expect(await setup.site.getPlayQualities(detail: loop), isNotEmpty);
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      await expectLater(setup.site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'kuaishou', roomId: _offline),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'kuaishou', roomId: _missing),
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('M4.U.5 受限: a living page without streams is live and unplayable; playing it asks nothing more', () async {
      // A user cookie keeps the anonymous session out of the trace.
      final vault = MemoryCookieVault()..set('kuaishou', 'did=user');
      addTearDown(vault.dispose);
      final setup = _setup(
        [],
        cookies: vault,
        extra: [
          _synthetic(
            _page('abc'),
            '<html><script>window.__INITIAL_STATE__=${jsonEncode({
              'liveroom': {
                'playList': [
                  {
                    'isLiving': true,
                    'author': {'id': 'abc', 'name': 'A'},
                    'liveStream': {
                      'id': 'L1',
                      'playUrls': {'h264': <String, dynamic>{}, 'hevc': <String, dynamic>{}},
                    },
                  },
                ],
              },
            })};</script></html>',
          ),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: 'abc');
      expect(
        (room.isLiveNow, room.restriction, room.followGroup),
        (true, LiveRestriction.unplayable, FollowGroup.live),
      );
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(_trace(setup.http), ['GET /u/abc did=user'], reason: 'the page it was opened with already said so');
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'abc');
      expect(refreshed.restriction, LiveRestriction.unplayable, reason: 'the refresh reads the same page');
    });

    test('M4.U.5 房间身份: a follow stored in another case takes the refresh of its lower-case id', () async {
      final setup = _setup(['S13-room-id-case']);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'kpl704668133');
      expect(_trace(setup.http), ['GET /u/kpl704668133 -']);
      final follow = LiveRoom(platform: 'kuaishou', roomId: _loop, nick: 'old', tagIds: const ['t']);
      final merged = follow.mergeFrom(refreshed);
      expect((merged.roomId, merged.nick, merged.isLiveNow), (_loop, refreshed.nick, true));
      expect(merged.tagIds, ['t']);
      expect({follow, refreshed}, hasLength(1), reason: 'one room whatever the case');
    });

    test('a card’s streams play without a request', () async {
      final setup = _setup(['S02-gameboard-p1']);
      final cards = await setup.site.getCategoryRooms(const LiveArea(platform: 'kuaishou', areaId: '1001'));
      final qualities = await setup.site.getPlayQualities(detail: cards.first);
      expect(qualities, isNotEmpty);
      final resolution = await setup.site.resolvePlayUrls(detail: cards.first, quality: qualities.last);
      expect(resolution.lines, isNotEmpty);
      expect(setup.http.requests, hasLength(1));
    });
  });

  group('links', () {
    final site = _setup([]).site;

    test('room pages on live.kuaishou.com and .cn; other pages and look-alikes are not rooms', () {
      // 3.x test/live_url_tool_parser_test.dart and web_search_room_parser_test.dart.
      expect(site.roomIdFromUrl('https://live.kuaishou.com/u/profile_name?source=share'), 'profile_name');
      expect(site.roomIdFromUrl('https://live.kuaishou.cn/u/profile-name/'), 'profile-name');
      expect(site.roomIdFromUrl('https://live.kuaishou.com/u/profile_name'), 'profile_name');
      expect(site.roomIdFromUrl('http://LIVE.kuaishou.com/U/3xgw4a6r5eiu4nu/extra#top'), '3xgw4a6r5eiu4nu');
      for (final url in [
        'https://live.kuaishou.com/u/',
        'https://live.kuaishou.com/search?keyword=test',
        'https://live.kuaishou.com/u/search',
        'https://live.kuaishou.com/cate/1001',
        'https://live.kuaishou.com.evil.test/u/abc',
        'https://evil.test/live.kuaishou.com/u/abc',
        'https://live.kuaishou.com/u/a.b',
        'ftp://live.kuaishou.com/u/abc',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(
        site.needsResolving('https://v.kuaishou.com/AbCd12'),
        isFalse,
        reason: 'share links unsupported, as in 3.x',
      );
    });

    test('share texts resolve without a request', () async {
      final http = ReplayHttp(const []);
      final registry = SiteRegistry({'kuaishou': () => KuaishouSite(http)});
      final parser = LinkParser(registry, http);
      expect(
        await parser.parse('快来看我直播 https://live.kuaishou.com/u/tianci666。'),
        const RoomLink('kuaishou', 'tianci666'),
      );
      expect(parser.containsSupportedLink('https://live.kuaishou.cn/u/fixture'), isTrue);
      expect(parser.containsSupportedLink('https://live.kuaishou.com/search'), isFalse);
      expect(http.requests, isEmpty);
    });
  });

  group('transport', () {
    test('transport failures are NetworkFailure; cancellation passes through', () async {
      final down = _setup(
        [],
        script: {
          '/live_api/home/list': [TransportReason.timeout],
        },
      );
      await expectLater(down.site.getRecommendRooms(), throwsA(isA<NetworkFailure>()));
      final cancelled = _setup(
        [],
        script: {
          '/u/abc': [TransportReason.cancelled],
        },
      );
      await expectLater(
        cancelled.site.getRoomDetailForRefresh(roomId: 'abc'),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
    });

    test('an empty room id is NotFound without a request', () async {
      final setup = _setup([]);
      await expectLater(setup.site.getRoomDetail(roomId: '  '), throwsA(isA<NotFound>()));
      expect(setup.http.requests, isEmpty);
    });
  });

  test('a stored room id is sent encoded and keeps its identity', () async {
    final setup = _setup([], extra: [_moved('S09-room-live', 'https://live.kuaishou.com/u/a%20b')]);
    final room = await setup.site.getRoomDetailForRefresh(roomId: 'a b');
    expect(room.roomId, 'a b');
    expect(setup.http.requests.single.url.path, '/u/a%20b');
  });
}
