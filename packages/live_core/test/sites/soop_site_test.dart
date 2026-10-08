// SoopSite over the recorded responses (ReplayHttp): the requests 3.x made
// (queries, forms, headers, the user's cookie on every one), the catalog
// walk, room depths (room entry with the station, M4.U 7-5), restricted
// broadcasts, streams from the room's broadcast and recovery, links and app
// links, and error mapping.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/soop';
final DateTime _now = DateTime.utc(2026, 9, 27, 17, 30, 45);

const _player = '/afreeca/player_live_api.php';
const _assign = '/broad_stream_assign.html';

/// The station path of streamer [id] (7-5).
String _station(String id) => '/api/$id/station';
const _catalog = ['S01-category-p1', 'S01-category-p2', 'S01-category-p3', 'S01-category-p4', 'S01-category-p5'];

ReplaySample _synthetic(String url, Object body, {int status = 200, String method = 'GET'}) => ReplaySample(
  method: method,
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

Map<String, dynamic> _legacy(String name) => Fixture.load('soop', name).legacy as Map<String, dynamic>;

/// 3.x's request of a sample (expected.json → `request`).
Map<String, dynamic> _legacyRequest(String name) => _legacy(name)['request'] as Map<String, dynamic>;

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
    final next = queue.removeAt(0);
    if (next is TransportReason) throw TransportFailure('soop', next, 'scripted');
    final sample = next as ReplaySample;
    return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}

typedef _Setup = ({SoopSite site, ReplayHttp http});

_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  CookieVault? cookies,
  Map<String, List<Object>> script = const {},
}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  final site = SoopSite(
    script.isEmpty
        ? http
        : _Sequenced(http, {
            for (final MapEntry(:key, :value) in script.entries) key: [...value],
          }),
    cookies: cookies,
    now: () => _now,
  );
  return (site: site, http: http);
}

/// `METHOD path type` of every request (`type` of a player API form).
List<String> _trace(ReplayHttp http) => [
  for (final request in http.requests)
    [request.method, request.url.path, if (request.body != null) _form(request)['type']].join(' '),
];

Map<String, String> _form(LiveRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

/// 3.x's headers of a sample's request, names in lower case, its empty
/// cookie left out.
Map<String, String> _legacyHeaders(String name) => {
  for (final MapEntry(:key, :value) in (_legacyRequest(name)['headers'] as Map<String, dynamic>).entries)
    if (key != 'Cookie') key.toLowerCase(): '$value',
};

void main() {
  group('catalog and lists', () {
    test("the catalog walks the five pages 3.x did, with 3.x's requests", () async {
      final setup = _setup(_catalog);
      final categories = await setup.site.getCategories(1, 20);
      final category = categories.single;
      expect((category.id, category.name), ('1', '热门'));
      expect(category.children, hasLength(544));
      expect(category.children.map((area) => area.areaId), [
        for (final name in _catalog)
          for (final area in _legacy(name)['areas'] as List) (area as Map)['areaId'],
      ]);
      expect(setup.http.requests, hasLength(5));
      for (final (index, request) in setup.http.requests.indexed) {
        expect(request.url, Uri.parse(_legacyRequest(_catalog[index])['url'] as String));
        expect(request.headers, _legacyHeaders(_catalog[index]));
        expect(request.site, 'soop');
      }
    });

    test('a failing later page ends the catalog with the areas so far, as in 3.x', () async {
      final setup = _setup(
        _catalog,
        script: {
          '/api.php': [
            ReplaySample.load('$_root/S01-category-p1'),
            ReplaySample.load('$_root/S01-category-p2'),
            TransportReason.timeout,
          ],
        },
      );
      expect((await setup.site.getCategories(1, 20)).single.children, hasLength(240));
      expect(setup.http.requests, hasLength(3), reason: 'no more requests than 3.x');
    });

    test('a failing first page fails the catalog (3.x showed an empty one)', () async {
      final setup = _setup(
        [],
        script: {
          '/api.php': <Object>[TransportReason.timeout],
        },
      );
      await expectLater(setup.site.getCategories(1, 20), throwsA(isA<NetworkFailure>()));
      final cancelled = _setup(
        _catalog,
        script: {
          '/api.php': [ReplaySample.load('$_root/S01-category-p1'), TransportReason.cancelled],
        },
      );
      await expectLater(
        cancelled.site.getCategories(1, 20),
        throwsA(isA<TransportFailure>()),
        reason: 'a cancelled walk is not a partial catalog',
      );
    });

    test('a server that repeats a page cannot loop the catalog', () async {
      final setup = _setup(
        [],
        script: {
          '/api.php': [ReplaySample.load('$_root/S01-category-p1'), ReplaySample.load('$_root/S01-category-p1')],
        },
      );
      expect((await setup.site.getCategories(1, 20)).single.children, hasLength(120));
      expect(setup.http.requests, hasLength(2));
    });

    test("area rooms: 3.x's request, page size limited to 60, the area's name on every card", () async {
      final setup = _setup(['S02-area-p1']);
      const area = LiveArea(platform: 'soop', areaType: '1', typeName: '热门', areaId: '00130000', areaName: '토크/캠방');
      final rooms = await setup.site.getCategoryRooms(area, pageSize: 999);
      expect(rooms, hasLength(60));
      expect(rooms.every((room) => room.area == '토크/캠방'), isTrue);
      expect(setup.http.requests.single.url, Uri.parse(_legacyRequest('S02-area-p1')['url'] as String));
    });

    test('recommendations by page; the list ends with an empty page', () async {
      final setup = _setup(['S03-main-p1', 'S03-main-p36', 'S03-main-p37']);
      expect(await setup.site.getRecommendRooms(), hasLength(60));
      expect(await setup.site.getRecommendRooms(page: 36), hasLength(20));
      expect(await setup.site.getRecommendRooms(page: 37), isEmpty);
      expect(setup.http.requests.first.url, Uri.parse(_legacyRequest('S03-main-p1')['url'] as String));
    });

    test("search: 3.x's request; page size limited to 50; a blank keyword sends nothing", () async {
      final setup = _setup(['S04-search-p1', 'S04-search-empty']);
      expect(await setup.site.searchRooms('게임'), hasLength(30));
      expect(setup.http.requests.single.url, Uri.parse(_legacyRequest('S04-search-p1')['url'] as String));
      expect(await setup.site.searchRooms(' zzqqxxkkyyww '), isEmpty);
      final before = setup.http.requests.length;
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(setup.http.requests, hasLength(before));
      final limited = _setup(
        [],
        extra: [
          _synthetic(
            'https://sch.sooplive.co.kr/api.php?l=DF&m=liveSearch&c=UTF-8&w=webk&isMobile=0&onlyParent=1&szType=json'
            '&szOrder=score&szKeyword=x&nPageNo=2&nListCnt=50&tab=live&location=total_search&isHashSearch=0&v=2.0',
            {'RESULT': '1', 'REAL_BROAD': <Object>[]},
          ),
        ],
      );
      expect(await limited.site.searchRooms('x', page: 2, pageSize: 999), isEmpty);
    });
  });

  group('rooms', () {
    test("room entry: 3.x's form and headers, the requested id, the broadcast and danmaku arguments", () async {
      final setup = _setup(['S05-live-live', 'S05-station-live']);
      final room = await setup.site.getRoomDetail(roomId: ' khm11903 ');
      expect(_trace(setup.http), ['POST $_player live', 'GET ${_station('khm11903')}']);
      final request = setup.http.requests.first;
      final legacy = _legacyRequest('S05-live-live');
      expect(request.method, 'POST');
      expect(request.url, Uri.parse(legacy['url'] as String));
      expect(_form(request), legacy['form']);
      expect({...request.headers}..remove('content-type'), _legacyHeaders('S05-live-live'));
      expect(room.roomId, 'khm11903');
      expect(room.isLiveNow, isTrue);
      expect(room.data, isA<SoopRoomData>());
      expect((room.danmakuData! as SoopDanmakuArgs).chatNo, '4172');
      expect(room.startedAt, DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(room.restriction, LiveRestriction.none);
    });

    test("room entry also reads the station (7-5): 3.x's API headers, the profile and viewers", () async {
      final setup = _setup(['S05-live-live', 'S05-station-live']);
      final room = await setup.site.getRoomDetail(roomId: 'khm11903');
      final station = setup.http.requests.last;
      expect(station.method, 'GET');
      expect(station.url, Uri.parse('https://chapi.sooplive.co.kr/api/khm11903/station'));
      expect(station.headers, SoopApi.apiHeaders());
      expect(station.site, 'soop');
      expect(room.avatar, 'https://profile.img.sooplive.co.kr/LOGO/kh/khm11903/khm11903.jpg');
      expect(room.introduction, '스타1 전프로게이머 김봉준 입니다.');
      expect(room.onlineViewers, '35465');
    });

    test('a failing station leaves the room as the player API says (one request more, at room entry)', () async {
      for (final failure in <Object>[
        TransportReason.timeout,
        TransportReason.cancelled,
        _synthetic('https://chapi.sooplive.co.kr/api/nsh100427/station', 'bad gateway', status: 502),
        _synthetic('https://chapi.sooplive.co.kr/api/nsh100427/station', '<html></html>'),
      ]) {
        final setup = _setup(
          ['S05-live-password'],
          script: {
            _station('nsh100427'): [failure],
          },
        );
        final room = await setup.site.getRoomDetail(roomId: 'nsh100427');
        expect(room.isLiveNow, isTrue, reason: '$failure');
        expect(room.restriction, LiveRestriction.password, reason: '7-8');
        expect(room.avatar, 'https://stimg.sooplive.co.kr/LOGO/ns/nsh100427/nsh100427.jpg', reason: 'the built one');
        expect(room.introduction, '');
        expect(setup.http.requests, hasLength(2));
      }
    });

    test('refresh and recording: the player API alone (one request, as in 3.x); recording has the chat', () async {
      final setup = _setup(['S05-live-live']);
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: 'khm11903');
      final recording = await setup.site.getRoomDetailForRecording(roomId: 'khm11903');
      expect(refresh.danmakuData, isNull);
      // E05.4: the same answer's chat arguments, for multi-view.
      expect(recording.danmakuData, isA<SoopDanmakuArgs>());
      expect(recording.data, isA<SoopRoomData>(), reason: "the recorder's streams need the broadcast");
      expect(_trace(setup.http), ['POST $_player live', 'POST $_player live']);
      expect(refresh.startedAt, DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(refresh.restriction, LiveRestriction.none);
      expect(await setup.site.getLiveStatus(roomId: 'khm11903'), isTrue);
    });

    test('offline (7-4): offline at room entry too, with the profile; refresh and recording as in 3.x', () async {
      final setup = _setup(['S05-live-offline', 'S05-station-offline']);
      expect((await setup.site.getRoomDetailForRefresh(roomId: 'phonics1')).effectiveLiveStatus, LiveStatus.offline);
      expect((await setup.site.getRoomDetailForRecording(roomId: 'phonics1')).effectiveLiveStatus, LiveStatus.offline);
      expect(setup.http.requests, hasLength(2), reason: 'one request each, as in 3.x');
      final room = await setup.site.getRoomDetail(roomId: 'phonics1');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.nick, '김민교.');
      expect(room.introduction, '실력과 재미와 감동을 겸비한 방송');
      expect(_trace(setup.http).sublist(2), ['POST $_player live', 'GET ${_station('phonics1')}']);
      expect(await setup.site.getLiveStatus(roomId: 'phonics1'), isFalse);
    });

    test('an unknown streamer is NotFound at room entry (7-5, REG-SOOP-005); offline on refresh', () async {
      final setup = _setup(['S05-live-missing', 'S05-station-missing']);
      const id = 'zzzqqqxxxnotexist1';
      await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(2));
      // The refresh reads the player API only, which answers an unknown
      // streamer like an offline one (as 3.x did).
      expect((await setup.site.getRoomDetailForRefresh(roomId: id)).effectiveLiveStatus, LiveStatus.offline);
      expect(setup.http.requests, hasLength(3));
      // Without the station's word it stays offline.
      final failing = _setup(
        ['S05-live-missing'],
        script: {
          _station(id): [TransportReason.timeout],
        },
      );
      expect((await failing.site.getRoomDetail(roomId: id)).effectiveLiveStatus, LiveStatus.offline);
    });

    test('banned at room entry (7-4; 3.x: a failed load)', () async {
      final setup = _setup(
        ['S05-station-offline'],
        extra: [
          _synthetic('https://live.sooplive.co.kr$_player?bjid=phonics1', {
            'CHANNEL': {'RESULT': -2},
          }, method: 'POST'),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: 'phonics1');
      expect(room.effectiveLiveStatus, LiveStatus.banned);
      expect(room.nick, '김민교.');
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'soop', roomId: 'phonics1'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test(
      'an age-restricted broadcast is live at every depth, and NeedsLogin for its stream (7-5, REG-SOOP-006)',
      () async {
        final setup = _setup(['S05-live-adult', 'S05-station-adult']);
        final entry = await setup.site.getRoomDetail(roomId: 'bumzi98');
        expect(entry.isLiveNow, isTrue);
        expect(entry.restriction, LiveRestriction.adult);
        expect((entry.nick, entry.onlineViewers), ('하니니', '3209'));
        expect(entry.danmakuData, isNull);
        for (final room in [
          await setup.site.getRoomDetailForRefresh(roomId: 'bumzi98'),
          await setup.site.getRoomDetailForRecording(roomId: 'bumzi98'),
        ]) {
          expect(room.isLiveNow, isTrue);
          expect(room.restriction, LiveRestriction.adult);
          expect(room.title, '다시보기 X 추석 토끼 떡 찧다가 술마시는중');
        }
        expect(await setup.site.getLiveStatus(roomId: 'bumzi98'), isTrue);
        await expectLater(setup.site.getPlayQualities(detail: entry), throwsA(isA<NeedsLogin>()));
      },
    );

    test('password and subscribers-only broadcasts: live, restricted, StreamUnavailable with the reason', () async {
      final setup = _setup(['S05-live-adult-password', 'S05-live-subscribers', 'S05-station-subscribers']);
      final locked = await setup.site.getRoomDetailForRefresh(roomId: 'qazeee');
      expect((locked.isLiveNow, locked.restriction), (true, LiveRestriction.password));
      await expectLater(
        setup.site.getPlayQualities(detail: locked),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('password'))),
      );
      final members = await setup.site.getRoomDetail(roomId: 'kirababy2');
      expect((members.isLiveNow, members.restriction), (true, LiveRestriction.subscribersOnly));
      expect(members.title, '햇비랑 프클하려고 왔음');
      await expectLater(
        setup.site.resolvePlayUrls(
          detail: members,
          quality: const LivePlayQuality(quality: '原画', id: 'original'),
        ),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('subscribers'))),
      );
    });

    test('a room id that is no streamer id is NotFound without a request', () async {
      final setup = _setup([]);
      await expectLater(setup.site.getRoomDetail(roomId: ''), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetail(roomId: 'a/b'), throwsA(isA<NotFound>()));
      expect(setup.http.requests, isEmpty);
    });
  });

  group('streams', () {
    test("from room entry: no new room request, 3.x's assignment then key, 3.x's URL", () async {
      final setup = _setup([
        'S05-live-live',
        'S05-station-live',
        'S06-assign-original',
        'S06-aid-original',
        'S06-assign-hd',
        'S06-aid-hd',
      ]);
      final room = await setup.site.getRoomDetail(roomId: 'khm11903');
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(setup.http.requests, hasLength(2), reason: 'the qualities need no request');
      // 7-1: 720p (hd4k) is “超清” after the source; ids unchanged.
      expect(qualities.map((quality) => quality.id), ['original', 'hd4k', 'hd', 'sd']);
      expect(qualities.map((quality) => quality.quality), ['原画', '超清', '高清', '标清']);
      for (final name in ['original', 'hd']) {
        final before = setup.http.requests.length;
        final resolution = await setup.site.resolvePlayUrls(
          detail: room,
          quality: qualities.firstWhere((quality) => quality.id == name),
        );
        expect(resolution.urls, _legacy('S06-aid-$name')['getPlayUrls']);
        final requests = setup.http.requests.sublist(before);
        expect(_trace(setup.http).sublist(before), ['GET $_assign', 'POST $_player aid']);
        expect(requests.first.url, Uri.parse(_legacyRequest('S06-assign-$name')['url'] as String));
        expect(_form(requests.last), _legacyRequest('S06-aid-$name')['form']);
        expect(resolution.lines.single.headers['referer'], 'https://play.sooplive.co.kr/khm11903');
        expect(resolution.appliedQualityData, name);
      }
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.first), hasLength(1));
    });

    test('a room without its broadcast (a list card) asks the player API first', () async {
      final setup = _setup(['S05-live-live', 'S06-assign-original', 'S06-aid-original']);
      final card = LiveRoom(platform: 'soop', roomId: 'khm11903', liveStatus: LiveStatus.live);
      final qualities = await setup.site.getPlayQualities(detail: card);
      await setup.site.resolvePlayUrls(detail: card, quality: qualities.first);
      expect(_trace(setup.http), ['POST $_player live', 'POST $_player live', 'GET $_assign', 'POST $_player aid']);
    });

    test('recovery always asks the player API again: a new broadcast has a new number', () async {
      final setup = _setup(['S05-live-live', 'S06-assign-original', 'S06-aid-original']);
      final stale = LiveRoom(
        platform: 'soop',
        roomId: 'khm11903',
        data: SoopRoomData(
          bno: '1',
          rmd: 'https://livestream-manager.sooplive.com',
          cdn: 'gcp_cdn',
          presets: const [SoopPreset(name: 'original', bps: 8000)],
        ),
      );
      final resolution = await setup.site.resolvePlayUrlsForRecovery(
        detail: stale,
        quality: const LivePlayQuality(quality: '原画', id: 'original'),
      );
      expect(resolution.urls, _legacy('S06-aid-original')['getPlayUrls']);
      expect(_trace(setup.http), ['POST $_player live', 'GET $_assign', 'POST $_player aid']);
      expect(setup.http.requests[1].url.queryParameters['broad_key'], '297314125-common-original-hls');
    });

    test('offline rooms have no stream: StreamUnavailable; an age-restricted key is NeedsLogin', () async {
      final offline = _setup(['S05-live-offline']);
      await expectLater(
        offline.site.getPlayQualities(
          detail: LiveRoom(platform: 'soop', roomId: 'phonics1'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      final adult = _setup(
        ['S06-aid-adult'],
        extra: [
          _synthetic(
            'https://livestream-manager.sooplive.com$_assign?return_type=gcp_cdn&broad_key=1-common-original-hls',
            {'result': '1', 'view_url': 'https://live-global-cdn-v02.sooplive.com/x/auth_playlist.m3u8'},
          ),
        ],
      );
      final room = LiveRoom(
        platform: 'soop',
        roomId: 'bumzi98',
        data: SoopRoomData(
          bno: '1',
          rmd: 'https://livestream-manager.sooplive.com',
          cdn: 'gcp_cdn',
          presets: const [SoopPreset(name: 'original')],
        ),
      );
      await expectLater(
        adult.site.resolvePlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: '原画', id: 'original'),
        ),
        throwsA(isA<NeedsLogin>()),
      );
      final entry = _setup(['S05-live-adult']);
      await expectLater(
        entry.site.getPlayQualities(
          detail: LiveRoom(platform: 'soop', roomId: 'bumzi98'),
        ),
        throwsA(isA<NeedsLogin>()),
      );
    });

    test('a password broadcast (7-8): 3.x asked for the key anyway; its refusal names the password', () async {
      final setup = _setup(
        ['S05-live-password', 'S06-aid-password'],
        extra: [
          _synthetic(
            'https://livestream-manager.sooplive.com$_assign?return_type=gcp_cdn&broad_key=297451835-common-original-hls',
            {'result': '1', 'view_url': 'https://live-global-cdn-v02.sooplive.com/x/auth_playlist.m3u8'},
          ),
        ],
        script: {
          _station('nsh100427'): [TransportReason.timeout],
        },
      );
      final room = await setup.site.getRoomDetail(roomId: 'nsh100427');
      expect(room.restriction, LiveRestriction.password);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.quality), ['原画', '超清', '高清', '标清']);
      await expectLater(
        setup.site.resolvePlayUrls(detail: room, quality: qualities.first),
        throwsA(
          isA<StreamUnavailable>().having((error) => error.detail, 'detail', 'aid: RESULT 0, password-protected'),
        ),
      );
      expect(_trace(setup.http).sublist(2), ['GET $_assign', 'POST $_player aid']);
    });
  });

  group("the user's cookie", () {
    test('goes with every request, the media lines and the danmaku handshake, as in 3.x', () async {
      final vault = MemoryCookieVault()..set('soop', ' PdboxTicket=t;\n AuthTicket=a ');
      addTearDown(vault.dispose);
      final setup = _setup([
        'S03-main-p1',
        'S05-live-live',
        'S05-station-live',
        'S06-assign-original',
        'S06-aid-original',
      ], cookies: vault);
      const cookie = 'PdboxTicket=t; AuthTicket=a';
      await setup.site.getRecommendRooms();
      final room = await setup.site.getRoomDetail(roomId: 'khm11903');
      final resolution = await setup.site.resolvePlayUrls(
        detail: room,
        quality: const LivePlayQuality(quality: '原画', id: 'original'),
      );
      expect(setup.http.requests.map((request) => request.headers['cookie']).toSet(), {cookie});
      expect(setup.http.requests.where((request) => request.url.host == 'chapi.sooplive.co.kr'), hasLength(1));
      expect(resolution.lines.single.headers['cookie'], cookie);
      expect((room.danmakuData! as SoopDanmakuArgs).headers['cookie'], cookie);
    });

    test('without one no request carries a cookie header', () async {
      final setup = _setup(['S03-main-p1', 'S05-live-live', 'S05-station-live']);
      await setup.site.getRecommendRooms();
      final room = await setup.site.getRoomDetail(roomId: 'khm11903');
      expect(setup.http.requests.every((request) => !request.headers.containsKey('cookie')), isTrue);
      expect((room.danmakuData! as SoopDanmakuArgs).headers.containsKey('cookie'), isFalse);
    });
  });

  group('links', () {
    test("3.x's room links (legacy live_url_tool, web_search_room_parser and soop_platform tests)", () {
      final site = _setup([]).site;
      expect(site.roomIdFromUrl('https://play.sooplive.co.kr/fixture/456'), 'fixture');
      expect(site.roomIdFromUrl('https://play.sooplive.com/fixture?source=share'), 'fixture');
      expect(site.roomIdFromUrl('https://play.sooplive.co.kr/streamer_1/123'), 'streamer_1');
      expect(site.roomIdFromUrl('https://play.sooplive.co.kr/example_channel'), 'example_channel');
      expect(site.roomIdFromUrl('https://www.sooplive.co.kr/example_channel?from=share'), 'example_channel');
      expect(site.roomIdFromUrl('https://www.sooplive.com/example_channel?from=share'), 'example_channel');
      expect(site.roomIdFromUrl('https://ch.sooplive.co.kr/khm11903'), 'khm11903');
    });

    test('station pages and upper case (3.x opened the streamer "station", and the id as typed)', () {
      final site = _setup([]).site;
      expect(site.roomIdFromUrl('https://www.sooplive.co.kr/station/khm11903'), 'khm11903');
      expect(site.roomIdFromUrl('https://play.sooplive.co.kr/KHM11903'), 'khm11903');
    });

    test('pages that are not streamers, and other sites, are not rooms', () {
      final site = _setup([]).site;
      for (final url in [
        'https://www.sooplive.co.kr/',
        'https://www.sooplive.co.kr/station',
        'https://www.sooplive.co.kr/search?keyword=x',
        'https://www.sooplive.co.kr/directory/category',
        'https://vod.sooplive.co.kr/player/123',
        'https://www.sooplive.co.kr/live/all',
        'https://sch.sooplive.co.kr/api.php',
        'https://vod.afreecatv.com/player/123',
        'https://www.afreecatv.com/',
        'https://afreecatv.com.example.com/khm11903',
        'https://example.com/khm11903',
        'https://sooplive.co.kr.example.com/khm11903',
        'ftp://play.sooplive.co.kr/khm11903',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(site.needsResolving('https://play.sooplive.co.kr/khm11903'), isFalse);
    });

    test('the former afreecatv.com links, as SOOP search answers still give them (7-7)', () {
      final site = _setup([]).site;
      final search = SoopApi.searchRooms(Fixture.load('soop', 'S04-search-p1').body);
      final urls = [
        for (final entry in (jsonDecode(Fixture.load('soop', 'S04-search-p1').body) as Map)['REAL_BROAD'] as List)
          '${(entry as Map)['url']}',
      ];
      expect(urls.first, 'http://afreecatv.com/ecvhao');
      expect([for (final url in urls) site.roomIdFromUrl(url)], [for (final room in search) room.roomId]);
      expect(site.roomIdFromUrl('https://play.afreecatv.com/khm11903/297314125'), 'khm11903');
      expect(site.roomIdFromUrl('https://bj.afreecatv.com/KHM11903'), 'khm11903');
      expect(site.roomIdFromUrl('https://www.afreecatv.com/station/khm11903'), 'khm11903');
    });

    test('SOOP app links in a share text (7-9), before web links, without a request', () async {
      final site = _setup([]).site;
      expect(site.roomIdsInShareText('보러 와 sooplive://player/live?broad_no=297314125&user_id=khm11903&channel='), [
        'khm11903',
      ]);
      expect(site.roomIdsInShareText('(sooplive://player/live?user_id=KHM11903)'), ['khm11903']);
      expect(site.roomIdsInShareText('sooplive://player/vod?user_id=a1 https://play.sooplive.co.kr/b2'), isEmpty);
      final http = ReplayHttp([]);
      final registry = SiteRegistry({'soop': () => SoopSite(http)});
      final parser = LinkParser(registry, http);
      expect(
        await parser.parse('봉준 sooplive://player/live?broad_no=1&user_id=khm11903，https://play.sooplive.co.kr/other1'),
        const RoomLink('soop', 'khm11903'),
      );
      expect(parser.containsSupportedLink('sooplive://player/live?user_id=khm11903'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('a share text is parsed without a request', () async {
      final http = ReplayHttp([]);
      final registry = SiteRegistry({'soop': () => SoopSite(http)});
      final link = await LinkParser(
        registry,
        http,
      ).parse('봉준 방송 https://play.sooplive.co.kr/khm11903/297314125 보러 오세요');
      expect(link, const RoomLink('soop', 'khm11903'));
      expect(http.requests, isEmpty);
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    final failing = _setup(
      ['S05-station-live'],
      script: {
        _player: [TransportReason.timeout],
      },
    );
    await expectLater(failing.site.getRoomDetail(roomId: 'khm11903'), throwsA(isA<NetworkFailure>()));
    final cancelled = _setup(
      ['S05-station-live'],
      script: {
        _player: [TransportReason.cancelled],
      },
    );
    await expectLater(
      cancelled.site.getRoomDetail(roomId: 'khm11903'),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
    final server = _setup(
      ['S05-station-live'],
      script: {
        _player: [_synthetic('https://live.sooplive.co.kr$_player', 'bad gateway', status: 502, method: 'POST')],
      },
    );
    await expectLater(server.site.getRoomDetail(roomId: 'khm11903'), throwsA(isA<NetworkFailure>()));
  });
}
