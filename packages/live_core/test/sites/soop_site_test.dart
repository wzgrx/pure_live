// SoopSite over the recorded responses (ReplayHttp): the requests 3.x made
// (queries, forms, headers, the user's cookie on every one), the catalog
// walk, room depths, streams from the room's broadcast and recovery, links
// and error mapping.
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
      final setup = _setup(['S05-live-live']);
      final room = await setup.site.getRoomDetail(roomId: ' khm11903 ');
      final request = setup.http.requests.single;
      final legacy = _legacyRequest('S05-live-live');
      expect(request.method, 'POST');
      expect(request.url, Uri.parse(legacy['url'] as String));
      expect(_form(request), legacy['form']);
      expect({...request.headers}..remove('content-type'), _legacyHeaders('S05-live-live'));
      expect(room.roomId, 'khm11903');
      expect(room.isLiveNow, isTrue);
      expect(room.data, isA<SoopRoomData>());
      expect((room.danmakuData! as SoopDanmakuArgs).chatNo, '4172');
    });

    test('refresh and recording: the same answer without danmaku arguments', () async {
      final setup = _setup(['S05-live-live']);
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: 'khm11903');
      final recording = await setup.site.getRoomDetailForRecording(roomId: 'khm11903');
      expect(refresh.danmakuData, isNull);
      expect(recording.danmakuData, isNull);
      expect(recording.data, isA<SoopRoomData>(), reason: "the recorder's streams need the broadcast");
      expect(_trace(setup.http), ['POST $_player live', 'POST $_player live']);
      expect(await setup.site.getLiveStatus(roomId: 'khm11903'), isTrue);
    });

    test('offline and unknown streamers: offline on refresh, a failed load at room entry, one request each', () async {
      final setup = _setup(['S05-live-offline', 'S05-live-missing']);
      for (final id in ['phonics1', 'zzzqqqxxxnotexist1']) {
        // REG-SOOP-005 kept as 3.x: an unknown id is offline too.
        expect((await setup.site.getRoomDetailForRefresh(roomId: id)).effectiveLiveStatus, LiveStatus.offline);
        expect((await setup.site.getRoomDetailForRecording(roomId: id)).effectiveLiveStatus, LiveStatus.offline);
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<StreamUnavailable>()));
      }
      expect(setup.http.requests, hasLength(6));
      expect(setup.http.requests.every((request) => request.url.path == _player), isTrue);
      expect(await setup.site.getLiveStatus(roomId: 'phonics1'), isFalse);
    });

    test("an age-restricted broadcast is NeedsLogin at every depth (REG-SOOP-006: 3.x's unknown state)", () async {
      final setup = _setup(['S05-live-adult']);
      await expectLater(setup.site.getRoomDetail(roomId: 'bumzi98'), throwsA(isA<NeedsLogin>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: 'bumzi98'), throwsA(isA<NeedsLogin>()));
      await expectLater(setup.site.getRoomDetailForRecording(roomId: 'bumzi98'), throwsA(isA<NeedsLogin>()));
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
      final setup = _setup(['S05-live-live', 'S06-assign-original', 'S06-aid-original', 'S06-assign-hd', 'S06-aid-hd']);
      final room = await setup.site.getRoomDetail(roomId: 'khm11903');
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.id), ['original', 'hd', 'sd', 'hd4k']);
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
  });

  group("the user's cookie", () {
    test('goes with every request, the media lines and the danmaku handshake, as in 3.x', () async {
      final vault = MemoryCookieVault()..set('soop', ' PdboxTicket=t;\n AuthTicket=a ');
      addTearDown(vault.dispose);
      final setup = _setup(['S03-main-p1', 'S05-live-live', 'S06-assign-original', 'S06-aid-original'], cookies: vault);
      const cookie = 'PdboxTicket=t; AuthTicket=a';
      await setup.site.getRecommendRooms();
      final room = await setup.site.getRoomDetail(roomId: 'khm11903');
      final resolution = await setup.site.resolvePlayUrls(
        detail: room,
        quality: const LivePlayQuality(quality: '原画', id: 'original'),
      );
      expect(setup.http.requests.map((request) => request.headers['cookie']).toSet(), {cookie});
      expect(resolution.lines.single.headers['cookie'], cookie);
      expect((room.danmakuData! as SoopDanmakuArgs).headers['cookie'], cookie);
    });

    test('without one no request carries a cookie header', () async {
      final setup = _setup(['S03-main-p1', 'S05-live-live']);
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
        // The former domain, which SOOP's search answers still link to: 3.x
        // did not recognise it (a later upgrade).
        'http://afreecatv.com/ecvhao',
        'https://example.com/khm11903',
        'https://sooplive.co.kr.example.com/khm11903',
        'ftp://play.sooplive.co.kr/khm11903',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(site.needsResolving('https://play.sooplive.co.kr/khm11903'), isFalse);
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
      [],
      script: {
        _player: [TransportReason.timeout],
      },
    );
    await expectLater(failing.site.getRoomDetail(roomId: 'khm11903'), throwsA(isA<NetworkFailure>()));
    final cancelled = _setup(
      [],
      script: {
        _player: [TransportReason.cancelled],
      },
    );
    await expectLater(
      cancelled.site.getRoomDetail(roomId: 'khm11903'),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
    final server = _setup(
      [],
      script: {
        _player: [_synthetic('https://live.sooplive.co.kr$_player', 'bad gateway', status: 502, method: 'POST')],
      },
    );
    await expectLater(server.site.getRoomDetail(roomId: 'khm11903'), throwsA(isA<NetworkFailure>()));
  });
}
