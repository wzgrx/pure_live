// BilibiliSite over the recorded responses (ReplayHttp): the anonymous
// session, WBI signing and its -352 renewal, catalog, search, detail with
// danmaku credentials, streams for short ids, links and the account helpers.
// Signature parameters are scrubbed in the samples and left out of matching.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/bilibili';
const _ignored = {'wts', 'w_rid', 'w_webid'};
const _sessionSamples = ['S10-guest', 'S11-guest', 'S12-guest'];
final DateTime _now = DateTime.utc(2026, 9, 27, 10, 16, 23);

const _spi = '/x/frontend/finger/spi';
const _nav = '/x/web-interface/nav';
const _lol = '/lol';
const _roomInfo = '/xlive/web-room/v1/index/getInfoByRoom';
const _danmu = '/xlive/web-room/v1/index/getDanmuInfo';
const _ranked = '/room/v1/Area/getListByAreaID';
const _feed = '/xlive/web-interface/v1/webMain/getMoreRecList';
const _playInfo = '/xlive/web-room/v2/index/getRoomPlayInfo';
const _areaRooms = '/room/v1/area/getRoomList';

ReplaySample _synthetic(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      headers: headers,
    );

/// Answers scripted responses for a path in order, then replays [inner].
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
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('bilibili', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('bilibili', reason, 'test');

  @override
  void close() {}
}

typedef _Setup = ({BilibiliSite site, ReplayHttp http, List<Duration> sleeps});

_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  CookieVault? cookies,
  Map<String, List<ReplaySample>> script = const {},
  int Function()? storedUid,
}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in [...samples, ..._sessionSamples]) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: _ignored);
  final sleeps = <Duration>[];
  final site = BilibiliSite(
    script.isEmpty
        ? http
        : _Sequenced(http, {
            for (final MapEntry(:key, :value) in script.entries) key: [...value],
          }),
    cookies: cookies,
    storedUid: storedUid,
    now: () => _now,
    sleep: (duration) async => sleeps.add(duration),
  );
  return (site: site, http: http, sleeps: sleeps);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

int _count(ReplayHttp http, String path) => _paths(http).where((p) => p == path).length;

String _guestCookie() {
  final pair = BilibiliApi.buvid(Fixture.load('bilibili', 'S10-guest').body);
  return 'buvid3=${pair.buvid3};buvid4=${pair.buvid4};';
}

ReplaySample _risk(String url) => _synthetic(url, {'code': -352, 'message': '-352'});

void main() {
  group('anonymous session', () {
    test(
      'one finger/spi and one nav for concurrent callers; the guest pair is the cookie (REG-BILIBILI-021)',
      () async {
        final setup = _setup(['S06-live', 'S06-offline']);
        await Future.wait([
          setup.site.getRoomDetailForRefresh(roomId: '42062'),
          setup.site.getRoomDetailForRefresh(roomId: '22647871'),
        ]);
        expect(_count(setup.http, _spi), 1);
        expect(_count(setup.http, _nav), 1);
        final info = setup.http.requests.where((request) => request.url.path == _roomInfo);
        expect(info.map((request) => request.headers['cookie']).toSet(), {_guestCookie()});
      },
    );

    test('a login cookie with its own buvid3 is sent as is, without finger/spi', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'buvid3=own; SESSDATA=s');
      addTearDown(vault.dispose);
      final setup = _setup(['S06-live'], cookies: vault);
      await setup.site.getRoomDetailForRefresh(roomId: '42062');
      expect(_count(setup.http, _spi), 0);
      expect(setup.http.requests.last.headers['cookie'], 'buvid3=own; SESSDATA=s');
    });

    test('WBI keys are reused; a cookie change starts a new session', () async {
      final vault = MemoryCookieVault();
      addTearDown(vault.dispose);
      final setup = _setup(['S06-live'], cookies: vault);
      await setup.site.getRoomDetailForRefresh(roomId: '42062');
      await setup.site.getRoomDetailForRefresh(roomId: '42062');
      expect(_count(setup.http, _nav), 1);
      vault.set('bilibili', 'SESSDATA=new');
      await setup.site.getRoomDetailForRefresh(roomId: '42062');
      expect(_count(setup.http, _nav), 2);
      expect(_count(setup.http, _spi), 2);
    });
  });

  group('detail', () {
    test('signed getInfoByRoom; the requested id stays the identity, the long id goes into data', () async {
      final setup = _setup(['S06-short-id']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: '6');
      expect(room.roomId, '6');
      expect((room.data! as BilibiliRoomData).longId, '7734200');
      expect(room.danmakuData, isNull, reason: 'refresh never fetches danmaku credentials (REG-BILIBILI-020)');
      expect(_paths(setup.http), [_spi, _nav, _roomInfo]);
    });

    test('missing rooms are NotFound; a non-numeric id is NotFound without a request', () async {
      final setup = _setup(['S06-not-found']);
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: '999999999'), throwsA(isA<NotFound>()));
      final before = setup.http.requests.length;
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: 'abc'), throwsA(isA<NotFound>()));
      expect(setup.http.requests.length, before);
    });

    test('-352 twice: one renewal (keys, guest buvid) 180 ms later, then RiskControl', () async {
      const url = 'https://api.live.bilibili.com$_roomInfo?room_id=42062';
      final setup = _setup(
        [],
        script: {
          _roomInfo: [_risk(url), _risk(url)],
        },
      );
      await expectLater(setup.site.getRoomDetailForRecording(roomId: '42062'), throwsA(isA<RiskControl>()));
      expect(setup.sleeps, [const Duration(milliseconds: 180)]);
      expect(_count(setup.http, _nav), 2, reason: 'the keys are renewed');
      expect(_count(setup.http, _spi), 2, reason: 'so is the guest buvid');
    });

    test('-352 then success: the renewed request answers', () async {
      const url = 'https://api.live.bilibili.com$_roomInfo?room_id=42062';
      final setup = _setup(
        ['S06-live'],
        script: {
          _roomInfo: [_risk(url)],
        },
      );
      final room = await setup.site.getRoomDetailForRecording(roomId: '42062');
      expect(room.isLiveNow, isTrue);
    });

    test('HTTP 412 is RateLimited at once, without a retry', () async {
      const url = 'https://api.live.bilibili.com$_roomInfo?room_id=42062';
      final setup = _setup(
        [],
        script: {
          _roomInfo: [_synthetic(url, 'blocked', status: 412)],
        },
      );
      await expectLater(setup.site.getRoomDetailForRecording(roomId: '42062'), throwsA(isA<RateLimited>()));
      expect(setup.sleeps, isEmpty);
    });
  });

  group('room entry with danmaku', () {
    test('the guest credentials 3.x gave the connector: token, endpoints, uid 0, buvid, headers', () async {
      final setup = _setup(['S06-live', 'S09-guest']);
      final room = await setup.site.getRoomDetail(roomId: '42062');
      final args = room.danmakuData! as BilibiliDanmakuArgs;
      final legacy = jsonDecode(
        ((Fixture.load('bilibili', 'S09-guest').legacy as Map)['room'] as Map)['danmakuData'] as String,
      ) as Map;
      expect(args.roomId, legacy['roomId']);
      expect(args.token, isNotEmpty);
      expect(args.servers.map((uri) => uri.toString()), legacy['serverUrls']);
      expect(args.uid, 0);
      expect(args.buvid, BilibiliApi.buvid(Fixture.load('bilibili', 'S10-guest').body).buvid3);
      expect(args.headers['referer'], 'https://live.bilibili.com/42062');
      expect(args.headers['cookie'], _guestCookie());
      expect(args.refresh, isNotNull);
      expect(args.giftCatalog, isNotNull, reason: 'D07.4: the gift table for the connection');
    });

    test('when discovery fails the room still opens: empty token, gateway only, refresh for later', () async {
      const danmu = 'https://api.live.bilibili.com$_danmu?id=42062&type=0';
      final setup = _setup(
        ['S06-live'],
        script: {
          _danmu: [
            _synthetic(danmu, {'code': 1, 'message': 'x'}),
          ],
        },
      );
      final room = await setup.site.getRoomDetail(roomId: '42062');
      final args = room.danmakuData! as BilibiliDanmakuArgs;
      expect(args.token, isEmpty);
      expect(args.servers.map((uri) => uri.toString()), [BilibiliApi.danmakuGateway]);
      expect(args.refresh, isNotNull);
      expect(_count(setup.http, _danmu), 1, reason: 'one quick attempt on entry (REG-BILIBILI-010)');
    });

    test('signed in: the uid is DedeUserID of the cookie, else the verified or stored uid', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=s; DedeUserID=123');
      addTearDown(vault.dispose);
      final setup = _setup(['S06-live', 'S09-guest'], cookies: vault, storedUid: () => 9);
      expect((await setup.site.danmakuArgs('42062')).uid, 123);
      vault.set('bilibili', 'SESSDATA=s');
      expect((await setup.site.danmakuArgs('42062')).uid, 9);
    });
  });

  group('catalog and search', () {
    test('categories', () async {
      final setup = _setup(['S01-guest']);
      expect(await setup.site.getCategories(1, 20), isNotEmpty);
    });

    test('M4.D area rooms: the unsigned getRoomList answers, nothing is signed', () async {
      final setup = _setup(['S17-area-page1']);
      final rooms = await setup.site.getCategoryRooms(
        const LiveArea(platform: 'bilibili', areaType: '2', areaId: '86'),
        pageSize: 99,
      );
      expect(rooms, hasLength(30));
      expect(_paths(setup.http), [_spi, _areaRooms], reason: 'the guest buvid, then no nav, lol or signed list');
      expect(setup.http.requests.last.url.queryParameters['page_size'], '30');
    });

    test('area rooms fall back to the signed list with w_webid; both failing report the first error', () async {
      const url =
          'https://api.live.bilibili.com$_areaRooms?platform=web&parent_area_id=2&area_id=86&sort_type=online&page=1&page_size=30';
      final setup = _setup(
        ['S02-signed-risk352'],
        script: {
          _areaRooms: [
            _synthetic(url, {'code': 1, 'message': 'gone'}),
          ],
        },
      );
      await expectLater(
        setup.site.getCategoryRooms(const LiveArea(platform: 'bilibili', areaType: '2', areaId: '86')),
        throwsA(isA<ApiChanged>()),
      );
      expect(_count(setup.http, _lol), 2, reason: 'the signed list renewed its access id after -352');
      expect(
        setup.http.requests.firstWhere((r) => r.url.path.endsWith('second/getList')).url.queryParameters,
        contains('w_webid'),
      );
    });

    test('recommend: the ranked list by popularity', () async {
      final setup = _setup(['S03-page1']);
      final rooms = await setup.site.getRecommendRooms();
      expect(rooms, hasLength(30));
      expect(_paths(setup.http).where((path) => path == _feed), isEmpty);
    });

    test('recommend: the ranked list fails twice 180 ms apart, the feed answers', () async {
      const ranked = 'https://api.live.bilibili.com$_ranked?areaId=0&parent_area_id=0&sort=online&pageSize=30&page=1';
      final setup = _setup(
        ['S04-page1'],
        script: {
          _ranked: [
            _synthetic(ranked, {'code': 1}),
            _synthetic(ranked, {'code': 1}),
          ],
        },
      );
      final rooms = await setup.site.getRecommendRooms();
      expect(rooms, hasLength(12));
      expect(setup.sleeps, [const Duration(milliseconds: 180)]);
    });

    test('recommend: RateLimited is not retried', () async {
      const ranked = 'https://api.live.bilibili.com$_ranked?areaId=0&parent_area_id=0&sort=online&pageSize=30&page=1';
      final setup = _setup(
        [],
        script: {
          _ranked: [_synthetic(ranked, 'x', status: 412)],
        },
      );
      await expectLater(setup.site.getRecommendRooms(), throwsA(isA<RateLimited>()));
      expect(setup.sleeps, isEmpty);
    });

    test('search sends page_size (1–50); a blank keyword sends nothing', () async {
      final setup = _setup(['S05-live-results']);
      expect(await setup.site.searchRooms('哔哩哔哩直播', pageSize: 20), isNotEmpty);
      final before = setup.http.requests.length;
      expect(await setup.site.searchRooms('   '), isEmpty);
      expect(setup.http.requests.length, before);
      final clamped = _setup(
        [],
        extra: [
          _synthetic(
            'https://api.bilibili.com/x/web-interface/search/type?context=&search_type=live&cover_type=user_cover&order=&keyword=x&category_id=&__refresh__=&_extra=&highlight=0&single_column=0&page=1&page_size=50',
            {
              'code': 0,
              'data': {'result': <String, Object?>{}},
            },
          ),
        ],
      );
      expect(await clamped.site.searchRooms('x', pageSize: 999), isEmpty);
    });
  });

  group('streams', () {
    test('qualities from qn=0; a request at 10000 is served 250 and says so', () async {
      final setup = _setup(['S07-guest-qn0', 'S07-guest-qn10000']);
      final room = LiveRoom(platform: 'bilibili', roomId: '42062');
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.id), [10000, 400, 250]);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.first);
      expect(resolution.appliedQualityData, 250);
      expect(resolution.lines.first.headers['referer'], 'https://live.bilibili.com/42062');
    });

    test('a room opened by its short id plays by its long id', () async {
      final setup = _setup(['S06-short-id', 'S07-short-id-long']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: '6');
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities, isNotEmpty);
      expect(setup.http.requests.last.url.queryParameters['room_id'], '7734200');
    });

    test('1-1: a carousel room is its own state and its stream is still asked for', () async {
      final setup = _setup(['S06-replay', 'S07-replay']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: '5440');
      expect(room.effectiveLiveStatus, LiveStatus.carousel);
      // F.5a: a guest gets no stream for the carousel (S07-replay), so the
      // one quality is the carousel's video (M4.01 refused it).
      expect(await setup.site.getPlayQualities(detail: room), [BilibiliApi.carouselQuality]);
      expect(_count(setup.http, _playInfo), 1, reason: 'the carousel is not refused before asking');
    });

    test("1-1 (F.5a): a guest plays the carousel's video from where the carousel is", () async {
      final video = Fixture.load('live_vod', 'V09-playurl-mp4');
      final round = _synthetic('https://api.live.bilibili.com/live/getRoundPlayVideo?room_id=5440', {
        'code': 0,
        'message': '0',
        'data': {
          'cid': 29153362694,
          'play_time': 754,
          'sequence': 3,
          'bvid': 'BV1zKZrYAEi8',
          'title': 'fixture',
          'play_url': 'https://interface.bilibili.com/v2/playurl?dead',
        },
      });
      final setup = _setup(
        ['S06-replay', 'S07-replay'],
        extra: [round, ReplaySample.load('../../fixtures/live_vod/V09-playurl-mp4')],
      );
      final room = await setup.site.getRoomDetailForRefresh(roomId: '5440');
      final qualities = await setup.site.getPlayQualities(detail: room);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.single);
      expect(resolution.start, const Duration(seconds: 754), reason: 'play_time');
      expect(resolution.appliedQualityData, BilibiliApi.carouselQualityId);
      final line = resolution.lines.single;
      expect(line.url, startsWith('https://upos-sz-mirrorhwo1.bilivideo.com/upgcxcode/'));
      expect(line.format, StreamFormat.other, reason: 'one whole MP4');
      expect(line.headers['referer'], 'https://www.bilibili.com/video/BV1zKZrYAEi8/');
      expect(line.headers['cookie'], _guestCookie());
      expect(_paths(setup.http).where((path) => path == '/live/getRoundPlayVideo' || path == '/x/player/playurl'), [
        '/live/getRoundPlayVideo',
        '/x/player/playurl',
      ]);
      expect(video.url.queryParameters['platform'], 'html5');
      // A live quality asked of a carousel without a stream (a stored
      // preference) plays the video too; the room page is asked first.
      final again = await setup.site.resolvePlayUrls(
        detail: room,
        quality: const LivePlayQuality(quality: '自动', id: 0, data: 0),
      );
      expect(again.start, const Duration(seconds: 754));
      expect(_count(setup.http, _playInfo), 2);
    });

    test('1-1: signed in, a carousel that comes with a stream plays', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'buvid3=own; SESSDATA=s');
      addTearDown(vault.dispose);
      final played = jsonDecode(Fixture.load('bilibili', 'S07-guest-qn0').body) as Map<String, dynamic>;
      (played['data'] as Map<String, dynamic>)['live_status'] = 2;
      final setup = _setup(
        ['S06-replay'],
        cookies: vault,
        script: {
          _playInfo: [_synthetic('https://api.live.bilibili.com$_playInfo', played)],
        },
      );
      final room = await setup.site.getRoomDetailForRefresh(roomId: '5440');
      expect(room.liveStatus, LiveStatus.carousel);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities, isNotEmpty);
      expect(setup.http.requests.last.url.queryParameters['room_id'], '5440');
      expect(setup.http.requests.last.headers['cookie'], 'buvid3=own; SESSDATA=s');
    });

    test('offline rooms have no stream: StreamUnavailable', () async {
      final setup = _setup(['S07-offline']);
      final id = Fixture.load('bilibili', 'S07-offline').url.queryParameters['room_id']!;
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'bilibili', roomId: id),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    test('room pages, h5 and blanc pages and the www alias; other pages are not rooms', () {
      final site = _setup([]).site;
      expect(site.roomIdFromUrl('https://live.bilibili.com/42062'), '42062');
      expect(site.roomIdFromUrl('https://live.bilibili.com/h5/42062?x=1'), '42062');
      expect(site.roomIdFromUrl('https://live.bilibili.com/blanc/42062'), '42062');
      expect(site.roomIdFromUrl('https://www.bilibili.com/42062'), '42062');
      expect(site.roomIdFromUrl('https://space.bilibili.com/42062'), isNull);
      expect(site.roomIdFromUrl('https://live.bilibili.com/p/eden/area-tags'), isNull);
      expect(site.roomIdFromUrl('https://live.bilibili.com/0'), isNull);
      expect(site.needsResolving('https://b23.tv/abc'), isTrue);
      expect(site.needsResolving('https://live.bilibili.com/1'), isFalse);
    });

    test('b23.tv is followed by hand through the parser; the room page is never fetched', () async {
      final http = ReplayHttp([
        _synthetic(
          'https://b23.tv/first',
          '',
          status: 302,
          headers: {
            'location': ['https://b23.tv/second'],
          },
        ),
        _synthetic(
          'https://b23.tv/second',
          '',
          status: 301,
          headers: {
            'location': ['https://live.bilibili.com/42062?from=share'],
          },
        ),
      ]);
      final registry = SiteRegistry({'bilibili': () => BilibiliSite(http)});
      final link = await LinkParser(registry, http).parse('快来看 https://b23.tv/first');
      expect(link, const RoomLink('bilibili', '42062'));
      expect(http.requests.map((request) => request.url.path), ['/first', '/second']);
      expect(http.requests.every((request) => !request.followRedirects), isTrue);
    });
  });

  group('account', () {
    test('QR code, waiting and confirmed polls; the cookie comes from Set-Cookie', () async {
      final setup = _setup(
        ['S15-generate', 'S15-poll-86101'],
        extra: [
          _synthetic(
            'https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=done',
            {
              'code': 0,
              'data': {'code': 0, 'message': ''},
            },
            headers: {
              'set-cookie': ['SESSDATA=abc; Path=/; HttpOnly', 'DedeUserID=123; Path=/', 'bad'],
            },
          ),
        ],
      );
      final code = await setup.site.qrCode();
      expect(code.url.scheme, 'https');
      final waiting = Fixture.load('bilibili', 'S15-poll-86101').url.queryParameters['qrcode_key']!;
      expect((await setup.site.qrPoll(waiting)).state, BilibiliQrState.waiting);
      final done = await setup.site.qrPoll('done');
      expect(done.state, BilibiliQrState.confirmed);
      expect(done.cookie, 'SESSDATA=abc; DedeUserID=123');
    });

    test('an expired cookie is NeedsLogin; no cookie sends nothing', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=old');
      addTearDown(vault.dispose);
      final setup = _setup(['S16-no-cookie'], cookies: vault);
      await expectLater(setup.site.account(), throwsA(isA<NeedsLogin>()));
      expect(setup.http.requests.single.headers, {'cookie': 'SESSDATA=old'});
      await expectLater(_setup([]).site.account(), throwsA(isA<NeedsLogin>()));
    });

    test('a verified account uid is the danmaku uid when the cookie has none', () async {
      final vault = MemoryCookieVault()..set('bilibili', 'SESSDATA=s');
      addTearDown(vault.dispose);
      final setup = _setup(
        ['S06-live', 'S09-guest'],
        cookies: vault,
        extra: [
          _synthetic('https://api.bilibili.com/x/member/web/account', {
            'code': 0,
            'data': {'mid': 55, 'uname': 'me'},
          }),
        ],
      );
      expect(await setup.site.account(), (uid: 55, name: 'me'));
      expect((await setup.site.danmakuArgs('42062')).uid, 55);
    });
  });

  group('D07.4 gift table', () {
    const config = '/xlive/web-room/v1/giftPanel/giftConfig';

    test('asked for once without a cookie for concurrent callers, kept 6 hours for every room', () async {
      var now = _now;
      final http = ReplayHttp([ReplaySample.load('$_root/S18-gift-config')], ignoredQuery: _ignored);
      final site = BilibiliSite(
        http,
        cookies: MemoryCookieVault()..set('bilibili', 'buvid3=own; SESSDATA=s'),
        now: () => now,
      );
      final (first, second) = await (site.giftCatalog(), site.giftCatalog()).wait;
      expect(identical(first, second), isTrue);
      expect(first.gifts, hasLength(8));
      expect(http.requests.single.url.toString(), 'https://api.live.bilibili.com$config?platform=pc');
      expect(http.requests.single.headers['cookie'], anyOf(isNull, isEmpty), reason: 'public: no login cookie');
      now = now.add(const Duration(hours: 5, minutes: 59));
      expect(identical(await site.giftCatalog(), first), isTrue);
      expect(http.requests, hasLength(1));
      now = now.add(const Duration(minutes: 2));
      await site.giftCatalog();
      expect(http.requests, hasLength(2), reason: 'after 6 hours it is asked for again');
    });

    test('a failure gives the empty table and is not kept: the next room asks again', () async {
      final setup = _setup(
        const [],
        extra: [ReplaySample.load('$_root/S18-gift-config')],
        script: {
          config: [
            _synthetic('https://api.live.bilibili.com$config?platform=pc', 'bad gateway', status: 502),
            _synthetic('https://api.live.bilibili.com$config?platform=pc', {'code': -400, 'message': 'x'}),
          ],
        },
      );
      expect(await setup.site.giftCatalog(), same(BilibiliGiftCatalog.empty));
      expect(await setup.site.giftCatalog(), same(BilibiliGiftCatalog.empty));
      expect((await setup.site.giftCatalog()).gifts, hasLength(8));
      expect(_count(setup.http, config), 3);
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    final failing = BilibiliSite(_Failing(TransportReason.timeout), now: () => _now);
    await expectLater(failing.getLiveStatus(roomId: '1'), throwsA(isA<NetworkFailure>()));
    final cancelled = BilibiliSite(_Failing(TransportReason.cancelled), now: () => _now);
    await expectLater(
      cancelled.getLiveStatus(roomId: '1'),
      throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled)),
    );
  });
}
