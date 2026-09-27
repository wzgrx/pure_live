// BilibiliSite end to end over the recorded Bilibili responses (ReplayHttp):
// the anonymous session (finger/spi, nav, /lol), WBI signing and its -352
// renewal, catalog, search, detail, streams, danmaku info, links and the
// account helpers. Signature and session parameters are scrubbed in the
// samples, so they are left out of request matching; a fixed clock makes
// `wts` deterministic. Flows without a sample use small synthetic answers.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/bilibili';
const _ignored = {'wts', 'w_rid', 'w_webid'};

/// The guest session samples every flow may need: finger/spi, nav, /lol.
const _sessionSamples = ['S10-guest', 'S11-guest', 'S12-guest'];

/// Fixed clock: wts 1790504183.
final _now = DateTime.utc(2026, 9, 27, 10, 16, 23);

const _imgKey = '7cd084941338484aae1ad9425b84077c';
const _subKey = '4932caff0ff746eab6f01bf08b70ac45';

const _spi = '/x/frontend/finger/spi';
const _nav = '/x/web-interface/nav';
const _lol = '/lol';
const _roomInfo = '/xlive/web-room/v1/index/getInfoByRoom';
const _play = '/xlive/web-room/v2/index/getRoomPlayInfo';
const _danmu = '/xlive/web-room/v1/index/getDanmuInfo';
const _areaList = '/xlive/web-interface/v1/second/getList';
const _ranked = '/room/v1/Area/getListByAreaID';
const _feed = '/xlive/web-interface/v1/webMain/getMoreRecList';

Fixture _fixture(String name) => Fixture.load('bilibili', name);

ReplaySample _synthetic(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      headers: headers,
    );

typedef _Setup = ({BilibiliSite site, ReplayHttp http, List<Duration> sleeps});

/// A site over [samples] plus the session samples; [extra] samples match
/// first.
_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  CookieVault? cookies,
  bool hevc = false,
  DateTime Function()? now,
  Set<String> ignored = _ignored,
}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in [...samples, ..._sessionSamples]) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: ignored);
  final sleeps = <Duration>[];
  final site = BilibiliSite(
    http,
    cookies: cookies,
    hevc: hevc,
    now: now ?? () => _now,
    sleep: (duration) async => sleeps.add(duration),
  );
  return (site: site, http: http, sleeps: sleeps);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

int _count(ReplayHttp http, String path) => _paths(http).where((p) => p == path).length;

/// The guest cookie built from S10.
String _guestCookie() {
  final pair = BilibiliSession.buvid(_fixture('S10-guest').body);
  return 'buvid3=${pair.buvid3};buvid4=${pair.buvid4};';
}

RoomDetail _room(String id, {LiveState state = LiveState.live}) => RoomDetail(
  card: RoomCard(ref: RoomRef('bilibili', id), title: '', anchorName: '', state: state),
  link: Uri.parse('https://live.bilibili.com/$id'),
  danmakuKeys: {'roomId': id},
);

/// Serves [script] answers for a URL path in order, then falls back to [inner].
final class _Sequenced implements LiveHttp {
  new(this.inner, this.script);

  final ReplayHttp inner;
  final Map<String, List<ReplaySample>> script;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final queue = script[request.url.path];
    if (queue == null || queue.isEmpty) return await inner.send(request);
    inner.requests.add(request);
    final sample = queue.removeAt(0);
    return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
  }

  @override
  void close() {}
}

/// Fails every request at the transport level.
final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('bilibili', reason, 'test');

  @override
  void close() {}
}

void main() {
  group('§6.4 WBI signing', () {
    test('the public test vector', () {
      expect(
        BilibiliSite.wbiSign(
          {'foo': '114', 'bar': '514', 'zab': '1919810'},
          imgKey: _imgKey,
          subKey: _subKey,
          wts: 1702204169,
        ),
        'bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4',
      );
    });

    test("the legacy getWbiSign output (S11 keys, wts 1790506842): same w_rid, !'()* filtered, UTF-8 escaped", () {
      // Recorded from BiliBiliSite.getWbiSign with the S11 nav keys.
      const vectors = [
        ({'room_id': '42062'}, '5fc384617ce9612a4edf45b5d0090193'),
        ({'id': '7734200', 'type': '0'}, 'e6d5e5549e5c6168e67a25679c255bfb'),
        (
          {
            'platform': 'web',
            'parent_area_id': '2',
            'area_id': '86',
            'sort_type': 'online',
            'page': '1',
            'w_webid': 'ab.CD-ef_gh~ij',
          },
          '9ed2fee7e2284bb1963e483ecf18b879',
        ),
        ({'k': "中文/(x)!*'v", 'a': '1'}, '4a79430abb8e9b7e027f58c0cf16118d'),
      ];
      for (final (params, rid) in vectors) {
        final signed = BilibiliSite.wbiSign(params, imgKey: _imgKey, subKey: _subKey, wts: 1790506842);
        expect(Uri.splitQueryString(signed)['w_rid'], rid, reason: '$params');
      }
      expect(
        BilibiliSite.wbiSign({'k': "中文/(x)!*'v", 'a': '1'}, imgKey: _imgKey, subKey: _subKey, wts: 1790506842),
        'a=1&k=%E4%B8%AD%E6%96%87%2Fxv&wts=1790506842&w_rid=4a79430abb8e9b7e027f58c0cf16118d',
      );
    });
  });

  group('anonymous session', () {
    test('one finger/spi for concurrent callers; its buvid pair is the cookie of every API request', () async {
      final (:site, :http, sleeps: _) = _setup(['S01-guest']);
      final results = await Future.wait([site.categories(), site.categories()]);
      expect(results.first.first.name, '网游');
      expect(_count(http, _spi), 1);
      final legacyHeaders = (_fixture('S10-guest').legacy as Map<String, dynamic>)['getHeader'];
      final lists = http.requests.where((r) => r.url.path == '/room/v1/Area/getList').toList();
      expect(lists, hasLength(2));
      for (final request in lists) {
        expect(request.headers, legacyHeaders);
        expect(request.headers['cookie'], _guestCookie());
      }
      expect(http.requests.first.headers, {
        'user-agent': BilibiliParse.userAgent,
        'referer': 'https://live.bilibili.com/',
      }, reason: 'finger/spi carries the stored cookie only, and there is none');
    });

    test('a login cookie with its own buvid3 is sent as is, without finger/spi', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=s; buvid3=mine; buvid4=four');
      final (:site, :http, sleeps: _) = _setup(['S01-guest'], cookies: vault);
      await site.categories();
      expect(_paths(http), ['/room/v1/Area/getList']);
      expect(http.requests.single.headers['cookie'], 'SESSDATA=s; buvid3=mine; buvid4=four');
      await site.dispose();
      await vault.dispose();
    });

    test('a failed finger/spi leaves no buvid: the request goes without a cookie, the next one asks again', () async {
      // S05-no-buvid3: search still answers without a buvid cookie.
      final (:site, :http, sleeps: _) = _setup(
        ['S05-no-buvid3'],
        extra: [_synthetic('https://api.bilibili.com$_spi', 'busy', status: 503)],
      );
      final page = await site.search('哔哩哔哩直播');
      expect(page.items, isNotEmpty);
      expect(http.requests.last.headers.containsKey('cookie'), isFalse);
      await site.search('哔哩哔哩直播');
      expect(_count(http, _spi), 2);
    });

    test('WBI keys are fetched once and reused for 6 hours', () async {
      var clock = _now;
      final (:site, :http, sleeps: _) = _setup(['S06-live'], now: () => clock);
      await site.detail(RoomRef('bilibili', '42062'));
      await site.detail(RoomRef('bilibili', '42062'));
      expect(_count(http, _nav), 1);
      clock = clock.add(const Duration(hours: 6, seconds: 1));
      await site.detail(RoomRef('bilibili', '42062'));
      expect(_count(http, _nav), 2);
      expect(_count(http, _spi), 1, reason: 'the guest buvid does not expire with the keys');
    });

    test('a cookie change drops the session (buvid, keys); other platforms do not', () async {
      final vault = MemoryCookieVault();
      final (:site, :http, sleeps: _) = _setup(['S06-live'], cookies: vault);
      final room = RoomRef('bilibili', '42062');
      await site.detail(room);
      expect((_count(http, _spi), _count(http, _nav)), (1, 1));

      vault.set('douyu', 'dy_did=x');
      await Future<void>.delayed(Duration.zero);
      await site.detail(room);
      expect((_count(http, _spi), _count(http, _nav)), (1, 1));

      vault.set('bilibili', 'SESSDATA=s; DedeUserID=42');
      await Future<void>.delayed(Duration.zero);
      await site.detail(room);
      expect((_count(http, _spi), _count(http, _nav)), (2, 2));
      expect(http.requests.last.headers['cookie'], 'SESSDATA=s; DedeUserID=42;${_guestCookie()}');
      expect(http.requests[http.requests.length - 3].headers['cookie'], 'SESSDATA=s; DedeUserID=42');

      // Before the (asynchronous) notification arrives, the new cookie is
      // already used.
      vault.set('bilibili', 'SESSDATA=t; buvid3=own');
      await site.detail(room);
      expect(_count(http, _nav), 3);
      expect(_count(http, _spi), 2, reason: 'the new cookie has its own buvid3');
      expect(http.requests.last.headers['cookie'], 'SESSDATA=t; buvid3=own');
      // The late notification does not throw that session away again.
      await Future<void>.delayed(Duration.zero);
      await site.detail(room);
      expect(_count(http, _nav), 3);

      await site.dispose();
      vault.set('bilibili', null);
      await vault.dispose();
    });
  });

  group('§4 detail', () {
    test('live: signed request, parsed by BilibiliParse.detail', () async {
      final (:site, :http, sleeps: _) = _setup(['S06-live']);
      final detail = await site.detail(RoomRef('bilibili', '42062'));
      expect(_paths(http), [_spi, _nav, _roomInfo]);
      // wts from the fixed clock; w_rid = md5(query + S11 mixin key).
      expect(http.requests.last.url.query, 'room_id=42062&wts=1790504183&w_rid=5c18f6fe9d9c8f0148e44c3966964e41');
      expect(http.requests.last.headers['cookie'], _guestCookie());
      final parsed = BilibiliParse.detail(_fixture('S06-live').body);
      expect(detail.ref, RoomRef('bilibili', '42062'));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, parsed.card.title);
      expect(detail.card.audience.popularity, parsed.card.audience.popularity);
    });

    test('offline and replay are states, not failures', () async {
      final (:site, http: _, sleeps: _) = _setup(['S06-offline', 'S06-replay']);
      expect((await site.detail(RoomRef('bilibili', '22647871'))).state, LiveState.offline);
      expect((await site.detail(RoomRef('bilibili', '5440'))).state, LiveState.replay);
    });

    test(
      'short id 6: the detail is the canonical long room 7734200, and the link resolves without a request',
      () async {
        final (:site, :http, sleeps: _) = _setup(['S06-short-id']);
        final detail = await site.detail(RoomRef('bilibili', '6'));
        expect(http.requests.last.url.queryParameters['room_id'], '6');
        expect(detail.ref, RoomRef('bilibili', '7734200'));
        expect(detail.link.toString(), 'https://live.bilibili.com/7734200');
        final before = http.requests.length;
        expect(await site.resolve('https://live.bilibili.com/6'), RoomRef('bilibili', '7734200'));
        expect(await site.resolve('7734200'), RoomRef('bilibili', '7734200'));
        expect(http.requests, hasLength(before));
      },
    );

    test('a room that does not exist is NotFound; a non-numeric id is NotFound without a request', () async {
      final (:site, :http, sleeps: _) = _setup(['S06-not-found']);
      await expectLater(site.detail(RoomRef('bilibili', '999999999')), throwsA(isA<NotFound>()));
      final before = http.requests.length;
      await expectLater(site.detail(RoomRef('bilibili', 'abc')), throwsA(isA<NotFound>()));
      expect(http.requests, hasLength(before));
    });

    test('§9 -352 twice: one renewal (keys and guest buvid) 180 ms later, then RiskControl', () async {
      final (:site, :http, :sleeps) = _setup(['S06-risk352']);
      await expectLater(site.detail(RoomRef('bilibili', '42062')), throwsA(isA<RiskControl>()));
      expect(_paths(http), [_spi, _nav, _roomInfo, _spi, _nav, _roomInfo]);
      expect(sleeps, [const Duration(milliseconds: 180)]);
      // Legacy also asked twice after one forced WBI refresh (it kept the buvid).
      final legacy = (_fixture('S06-risk352').legacy as Map<String, dynamic>)['requests'] as Map<String, dynamic>;
      expect(legacy[_roomInfo], _count(http, _roomInfo));
      expect(legacy[_nav], _count(http, _nav));
    });

    test('§9 -352 then success: the renewed request answers', () async {
      final replay = ReplayHttp([
        for (final name in ['S06-live', ..._sessionSamples]) ReplaySample.load('$_root/$name'),
      ], ignoredQuery: _ignored);
      final http = _Sequenced(replay, {
        _roomInfo: [ReplaySample.load('$_root/S06-risk352')],
      });
      final site = BilibiliSite(http, now: () => _now, sleep: (_) async {});
      final detail = await site.detail(RoomRef('bilibili', '42062'));
      expect(detail.state, LiveState.live);
      expect(_count(replay, _nav), 2);
      expect(_count(replay, _roomInfo), 2);
    });

    test('§9 HTTP 412 is RateLimited at once: no renewal, no retry', () async {
      final (:site, :http, :sleeps) = _setup(
        [],
        extra: [_synthetic('https://$_liveApiHost$_roomInfo?room_id=42062', '', status: 412)],
      );
      await expectLater(site.detail(RoomRef('bilibili', '42062')), throwsA(isA<RateLimited>()));
      expect(_count(http, _roomInfo), 1);
      expect(_count(http, _nav), 1);
      expect(sleeps, isEmpty);
    });
  });

  group('§2 catalog', () {
    const area = Area(id: '86', name: '英雄联盟', categoryId: '2');

    test(
      'area rooms: signed with w_webid; the guest -352 (S02-signed-risk352) renews once, then RiskControl',
      () async {
        final (:site, :http, :sleeps) = _setup(['S02-signed-risk352']);
        await expectLater(site.areaRooms(area), throwsA(isA<RiskControl>()));
        expect(_paths(http), [_spi, _nav, _lol, _areaList, _spi, _nav, _lol, _areaList]);
        expect(sleeps, [const Duration(milliseconds: 180)]);
        final accessId = (_fixture('S12-guest').legacy as Map<String, dynamic>)['getAccessId'];
        final query = http.requests.last.url.queryParameters;
        expect(query, {
          'area_id': '86',
          'page': '1',
          'parent_area_id': '2',
          'platform': 'web',
          'sort_type': 'online',
          'w_webid': accessId,
          'wts': '1790504183',
          'w_rid': query['w_rid'],
        });
        expect(query['w_rid'], matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(http.requests.last.headers['cookie'], _guestCookie());
      },
    );

    test('area rooms: the cursor is the page; has_more gives the next one', () async {
      final (:site, :http, sleeps: _) = _setup(
        [],
        extra: [
          _synthetic(
            'https://$_liveApiHost$_areaList?platform=web&parent_area_id=2&area_id=86&sort_type=online&page=3',
            {
              'code': 0,
              'data': {
                'list': [
                  {'roomid': 1, 'title': 'a', 'uname': 'u', 'online': 5},
                  {'roomid': 2, 'title': 'b', 'uname': 'v', 'online': 9},
                ],
                'has_more': 1,
              },
            },
          ),
        ],
      );
      final page = await site.areaRooms(area, cursor: const PageCursor('3'));
      expect(page.items.map((room) => room.ref.roomId), ['2', '1']);
      expect(page.next, const PageCursor('4'));
      expect(http.requests.last.url.queryParameters['page'], '3');
    });

    test('recommend: the ranked list; an out-of-range page is the last', () async {
      final (:site, :http, sleeps: _) = _setup(['S03-page1', 'S03-out-of-range']);
      final page = await site.recommended();
      final parsed = BilibiliParse.recommendPage(_fixture('S03-page1').body, page: 1);
      expect(page.items.map((room) => room.ref), parsed.items.map((room) => room.ref));
      expect(page.next, const PageCursor('2'));
      final last = await site.recommended(cursor: const PageCursor('10000'));
      expect(last.items, isEmpty);
      expect(last.isLast, isTrue);
      expect(http.requests.every((r) => r.url.path != _feed), isTrue);
    });

    test('recommend: the ranked list fails twice (180 ms apart), the feed answers', () async {
      final (:site, :http, :sleeps) = _setup(
        ['S04-page1'],
        extra: [
          _synthetic(
            'https://$_liveApiHost$_ranked?areaId=0&parent_area_id=0&sort=online&pageSize=30&page=1',
            'x',
            status: 502,
          ),
        ],
      );
      final page = await site.recommended();
      final parsed = BilibiliParse.recommendPage(_fixture('S04-page1').body, page: 1);
      expect(page.items.map((room) => room.ref), parsed.items.map((room) => room.ref));
      expect(_count(http, _ranked), 2);
      expect(_count(http, _feed), 1);
      expect(sleeps, [const Duration(milliseconds: 180)]);
    });

    test('recommend: RateLimited is not retried; when both endpoints fail the ranked error is reported', () async {
      final limited = _setup(
        [],
        extra: [
          _synthetic(
            'https://$_liveApiHost$_ranked?areaId=0&parent_area_id=0&sort=online&pageSize=30&page=1',
            '',
            status: 412,
          ),
        ],
      );
      await expectLater(limited.site.recommended(), throwsA(isA<RateLimited>()));
      expect(_count(limited.http, _ranked), 1);
      expect(_count(limited.http, _feed), 0);

      final broken = _setup(
        [],
        extra: [
          _synthetic('https://$_liveApiHost$_ranked?areaId=0&parent_area_id=0&sort=online&pageSize=30&page=1', {
            'code': -400,
            'message': 'bad',
          }),
          _synthetic('https://$_liveApiHost$_feed?platform=web&page=1', 'x', status: 500),
        ],
      );
      await expectLater(broken.site.recommended(), throwsA(isA<ApiChanged>()));
      expect(_count(broken.http, _feed), 1);
    });
  });

  group('§3 search', () {
    test('pages follow the parser; a blank keyword sends nothing', () async {
      final (:site, :http, sleeps: _) = _setup(['S05-live-results', 'S05-out-of-range', 'S05-no-results']);
      final keyword = _fixture('S05-live-results').url.queryParameters['keyword']!;
      final page = await site.search(' $keyword ');
      final parsed = BilibiliParse.searchPage(_fixture('S05-live-results').body, page: 1);
      expect(page.items.map((room) => room.ref), parsed.items.map((room) => room.ref));
      expect(page.next, parsed.next);
      expect(http.requests.last.url.queryParameters['page_size'], '20');
      final second = await site.search(keyword, cursor: const PageCursor('2'));
      expect(second.items, isEmpty);
      expect(second.isLast, isTrue);
      final none = await site.search(_fixture('S05-no-results').url.queryParameters['keyword']!);
      expect(none.items, isEmpty);
      final before = http.requests.length;
      expect((await site.search('  ')).isLast, isTrue);
      expect(http.requests, hasLength(before));
    });
  });

  group('§5/§6 streams', () {
    test('best quality by default: qn=0 lists 10000/400/250, 10000 is requested, the guest is served 250', () async {
      final (:site, :http, sleeps: _) = _setup(['S07-guest-qn0', 'S07-guest-qn10000']);
      final set = await site.streams(_room('42062'));
      final plays = http.requests.where((r) => r.url.path == _play).toList();
      expect(plays.map((r) => r.url.queryParameters['qn']), ['0', '10000']);
      expect(
        plays.every((r) => r.url.queryParameters['codec'] == '0' && r.url.queryParameters['room_id'] == '42062'),
        isTrue,
      );
      expect(set.qualities.map((q) => q.id), ['10000', '400', '250']);
      expect(set.selected.id, '10000');
      expect(set.lines.every((line) => line.requested.id == '10000' && line.confirmed?.id == '250'), isTrue);
      expect(set.lines.first.effective.label, '超清');
      expect(set.lines.first.format, StreamFormat.flv);
      final parsed = BilibiliParse.streams(
        BilibiliParse.playData(_fixture('S07-guest-qn10000').body),
        roomId: '42062',
        issuedAt: _now,
        requested: set.selected,
        cookie: _guestCookie(),
      );
      expect(set.lines.map((line) => line.url), parsed.lines.map((line) => line.url));
      expect(set.lines.map((line) => line.lineId), parsed.lines.map((line) => line.lineId));
      for (final line in set.lines) {
        expect(line.headers, BilibiliParse.mediaHeaders('42062', cookie: _guestCookie()));
        expect(line.lease?.expiresAt, isNotNull);
        expect(line.lease!.cutsConnection, isFalse);
      }
    });

    test('a chosen quality is one request at its qn', () async {
      final (:site, :http, sleeps: _) = _setup(['S07-guest-qn10000']);
      final set = await site.streams(
        _room('42062'),
        quality: const Quality(id: '10000', label: '原画', rank: 10000),
      );
      expect(_count(http, _play), 1);
      expect(set.lines.first.confirmed?.id, '250');
    });

    test('hevc: codec=0,1 is requested and the set still holds one codec', () async {
      final (:site, :http, sleeps: _) = _setup(['S07-hevc-qn10000'], hevc: true);
      const original = Quality(id: '10000', label: '原画', rank: 10000);
      final set = await site.streams(_room('42062'), quality: original);
      expect(http.requests.last.url.queryParameters['codec'], '0,1');
      expect(set.lines.map((line) => line.codec).toSet(), {'avc'});
      final body = _fixture('S07-hevc-qn10000').body;
      expect(body, contains('"hevc"'));
      final parsed = BilibiliParse.streams(
        BilibiliParse.playData(body),
        roomId: '42062',
        issuedAt: _now,
        requested: original,
        cookie: _guestCookie(),
      );
      expect(set.lines.map((line) => line.url), parsed.lines.map((line) => line.url));
    });

    test('when the server default already is the best quality, qn=0 is the only request', () async {
      final (:site, :http, sleeps: _) = _setup(
        [],
        extra: [
          _synthetic(
            'https://$_liveApiHost$_play?room_id=42062&protocol=0,1&format=0,1,2&codec=0&qn=0&platform=web&ptype=8&dolby=5&panorama=1&mask=0&no_playurl=0',
            {
              'code': 0,
              'data': {
                'room_id': 42062,
                'live_status': 1,
                'playurl_info': {
                  'playurl': {
                    'g_qn_desc': <Object>[],
                    'stream': [
                      {
                        'protocol_name': 'http_stream',
                        'format': [
                          {
                            'format_name': 'flv',
                            'codec': [
                              {
                                'codec_name': 'avc',
                                'current_qn': 10000,
                                'accept_qn': [10000, 250],
                                'base_url': '/live/x.flv?',
                                'url_info': [
                                  {'host': 'https://cn-a.bilivideo.com', 'extra': 'expires=1790507783&qn=10000'},
                                ],
                              },
                            ],
                          },
                        ],
                      },
                    ],
                  },
                },
              },
            },
          ),
        ],
      );
      final set = await site.streams(_room('42062'));
      expect(_count(http, _play), 1);
      expect(set.selected.id, '10000');
      expect(set.lines.single.confirmed?.id, '10000');
      expect(set.lines.single.lease!.expiresAt, DateTime.fromMillisecondsSinceEpoch(1790507783 * 1000, isUtc: true));
    });

    test('short id: the detail gives the long id, streams and the media Referer use it', () async {
      // One play sample answers both the qn=0 and the qn=10000 request.
      final (:site, :http, sleeps: _) = _setup(['S06-short-id', 'S07-short-id-long'], ignored: {..._ignored, 'qn'});
      final detail = await site.detail(RoomRef('bilibili', '6'));
      final set = await site.streams(detail);
      final plays = http.requests.where((r) => r.url.path == _play);
      expect(plays.map((r) => r.url.queryParameters['room_id']), ['7734200', '7734200']);
      expect(set.lines.first.headers['referer'], 'https://live.bilibili.com/7734200');
    });

    test('offline and replay rooms have no stream: StreamUnavailable', () async {
      final (:site, http: _, sleeps: _) = _setup(['S07-offline', 'S07-replay']);
      await expectLater(site.streams(_room('22647871', state: LiveState.offline)), throwsA(isA<StreamUnavailable>()));
      await expectLater(site.streams(_room('5440', state: LiveState.replay)), throwsA(isA<StreamUnavailable>()));
    });
  });

  group('§7.1 danmaku info', () {
    test('guest: signed getDanmuInfo for the long id; matches what legacy gave the connector', () async {
      final (:site, :http, sleeps: _) = _setup(['S06-live', 'S09-guest']);
      final detail = await site.detail(RoomRef('bilibili', '42062'));
      final info = await site.danmakuInfo(detail);
      final request = http.requests.last;
      expect(request.url.path, _danmu);
      expect(request.url.queryParameters, {
        'id': '42062',
        'type': '0',
        'wts': '1790504183',
        'w_rid': request.url.queryParameters['w_rid'],
      });
      final legacy = (_fixture('S09-guest').legacy as Map<String, dynamic>)['danmakuArgs'] as Map<String, dynamic>;
      expect(info.roomId, legacy['roomId']);
      expect(info.uid, legacy['uid']);
      expect(info.token, legacy['token']);
      expect(info.servers.map((server) => server.toString()), legacy['serverUrls']);
      expect(info.buvid, legacy['buvid']);
      expect(info.headers, legacy['headers']);
    });

    test('signed in: uid from DedeUserID, or from a verified account; buvid from the cookie', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=s; DedeUserID=42; buvid3=own');
      final signedIn = _setup(['S09-guest'], cookies: vault);
      final info = await signedIn.site.danmakuInfo(_room('42062'));
      expect(info.uid, 42);
      expect(info.buvid, 'own');
      expect(info.headers['cookie'], 'SESSDATA=s; DedeUserID=42; buvid3=own');
      expect(_count(signedIn.http, _spi), 0);

      final other = MemoryCookieVault()..set('bilibili', 'SESSDATA=s');
      final verified = _setup(
        ['S09-guest'],
        cookies: other,
        extra: [
          _synthetic('https://api.bilibili.com/x/member/web/account', {
            'code': 0,
            'data': {'mid': 7, 'uname': 'n'},
          }),
        ],
      );
      expect((await verified.site.danmakuInfo(_room('42062'))).uid, 0);
      expect(await verified.site.account(), (uid: 7, name: 'n'));
      expect((await verified.site.danmakuInfo(_room('42062'))).uid, 7);
      await signedIn.site.dispose();
      await verified.site.dispose();
    });
  });

  group('§1.2 links', () {
    test('not a Bilibili room: null without a request', () async {
      final (:site, :http, sleeps: _) = _setup([]);
      for (final input in [
        '',
        'hello',
        '0',
        'https://notbilibili.com/123',
        'https://user@live.bilibili.com/123',
        'ftp://live.bilibili.com/123',
        'https://live.bilibili.com/',
        'https://live.bilibili.com/%FF',
        'https://live.bilibili.com/123%2F456',
        'https://live.bilibili.com/p/eden/area-tags',
        'https://live.bilibili.com/0',
        'https://www.bilibili.com/video/BV1xx411c7mD',
        'https://space.bilibili.com/42062',
        'https://www.douyu.com/42062',
      ]) {
        expect(await site.resolve(input), isNull, reason: input);
      }
      expect(http.requests, isEmpty);
    });

    test('numbers, room pages, h5/blanc pages, the www alias and share text; canonical ids', () async {
      final (:site, :http, sleeps: _) = _setup([
        'S06-live',
        'S06-offline',
        'S06-replay',
        'S06-short-id',
        'S06-not-found',
      ]);
      expect(await site.resolve(' 42062 '), RoomRef('bilibili', '42062'));
      final before = _count(http, _roomInfo);
      expect(await site.resolve('https://LIVE.bilibili.com/42062?visit_id=x#frag'), RoomRef('bilibili', '42062'));
      expect(_count(http, _roomInfo), before, reason: 'a room seen by detail needs no request');
      expect(
        await site.resolve('【直播】快来看 https://live.bilibili.com/h5/22647871?broadcast_type=0，好看'),
        RoomRef('bilibili', '22647871'),
      );
      expect(await site.resolve('www.bilibili.com/5440'), RoomRef('bilibili', '5440'));
      expect(await site.resolve('https://live.bilibili.com/blanc/6'), RoomRef('bilibili', '7734200'));
      await expectLater(site.resolve('https://live.bilibili.com/999999999'), throwsA(isA<NotFound>()));
    });

    test('b23.tv: redirects are followed by hand, the target page is never fetched', () async {
      ReplaySample hop(String from, int status, List<String> locations) =>
          _synthetic('https://b23.tv/$from', '', status: status, headers: {'location': locations});
      final (:site, :http, sleeps: _) = _setup(
        ['S06-short-id', 'S06-live'],
        extra: [
          hop('abc', 302, ['https://live.bilibili.com/6?share_source=copy_link']),
          hop('rel', 301, ['/hop']),
          hop('hop', 307, ['https://live.bilibili.com/42062']),
          hop('loop', 302, ['https://b23.tv/loop#again']),
          hop('two', 302, ['https://live.bilibili.com/6', 'https://live.bilibili.com/42062']),
          hop('video', 302, ['https://www.bilibili.com/video/BV1xx411c7mD']),
          hop('page', 200, []),
          for (var i = 0; i < 9; i++) hop('h$i', 302, ['https://b23.tv/h${i + 1}']),
        ],
      );
      expect(await site.resolve('【哔哩哔哩】 https://b23.tv/abc'), RoomRef('bilibili', '7734200'));
      final shortRequests = http.requests.where((r) => r.url.host == 'b23.tv').toList();
      expect(shortRequests.single.followRedirects, isFalse);
      expect(http.requests.where((r) => r.url.host == 'live.bilibili.com'), isEmpty);

      expect(await site.resolve('https://b23.tv/rel'), RoomRef('bilibili', '42062'));
      for (final dead in ['loop', 'two', 'video', 'page']) {
        expect(await site.resolve('https://b23.tv/$dead'), isNull, reason: dead);
      }
      expect(http.requests.where((r) => r.url.host == 'www.bilibili.com'), isEmpty);
      final before = http.requests.length;
      expect(await site.resolve('https://b23.tv/h0'), isNull);
      expect(http.requests.length - before, 8, reason: 'at most 8 requests per resolution');

      expect(
        await site.resolve('视频 https://b23.tv/video 直播 https://live.bilibili.com/42062'),
        RoomRef('bilibili', '42062'),
        reason: 'the first link that is a room',
      );
    });
  });

  group('§8 account', () {
    test('QR code and polls', () async {
      final generate = _setup(['S15-generate']);
      final code = await generate.site.qrCode();
      final expected = BilibiliSession.qrCode(_fixture('S15-generate').body);
      expect(code.key, expected.key);
      expect(code.url, expected.url);

      for (final (name, state) in [
        ('S15-poll-86101', BilibiliQrState.waiting),
        ('S15-poll-86038', BilibiliQrState.expired),
      ]) {
        final poll = _setup([name], ignored: {'qrcode_key'});
        expect(await poll.site.qrPoll('key'), (state: state, cookie: null), reason: name);
      }

      final confirmed = _setup(
        [],
        extra: [
          _synthetic(
            'https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=k',
            {
              'code': 0,
              'data': {'code': 0, 'message': '0', 'url': 'https://passport.biligame.com/x', 'refresh_token': 'r'},
            },
            headers: {
              'set-cookie': [
                'SESSDATA=abc%2C1; Path=/; Domain=bilibili.com; HttpOnly',
                'DedeUserID=42; Path=/; Domain=bilibili.com',
                'bili_jct=j; Path=/',
                'not-a-pair',
              ],
            },
          ),
        ],
      );
      expect(await confirmed.site.qrPoll('k'), (
        state: BilibiliQrState.confirmed,
        cookie: 'SESSDATA=abc%2C1; DedeUserID=42; bili_jct=j',
      ));
    });

    test('account: -101 (S16) is NeedsLogin; only the cookie is sent; no cookie sends nothing', () async {
      final (:site, :http, sleeps: _) = _setup(['S16-no-cookie']);
      await expectLater(site.account(cookie: 'SESSDATA=old'), throwsA(isA<NeedsLogin>()));
      expect(http.requests.single.headers, {'cookie': 'SESSDATA=old'});
      await expectLater(site.account(), throwsA(isA<NeedsLogin>()));
      expect(http.requests, hasLength(1));
    });
  });

  test('transport failures are NetworkFailure; cancellation is passed through', () async {
    final down = BilibiliSite(_Failing(TransportReason.connect), now: () => _now);
    await expectLater(down.categories(), throwsA(isA<NetworkFailure>()));
    final cancelled = BilibiliSite(_Failing(TransportReason.cancelled), now: () => _now);
    await expectLater(cancelled.categories(), throwsA(isA<TransportFailure>()));
  });
}

const _liveApiHost = 'api.live.bilibili.com';
