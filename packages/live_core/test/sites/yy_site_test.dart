// YySite over the recorded responses (ReplayHttp): the catalog, area modules
// (stored, read on opening, module-less), recommendations, search, room
// detail (entry and refresh: live, offline, unknown, short numbers), mobile
// HLS first and stream-manager standing in, FLV first (6-1), the second CDN
// line (6-4), cookies, links and error mapping; the M4.U upgrades are named
// by their number in docs/specs/UPGRADES.md. The stream-manager body carries clock
// values (seq, send_time, the URL's sequence) and the recording's browser
// (osversion, width, height), left out of matching.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/yy';
const _ignored = {'seq', 'send_time', 'sequence', 'osversion', 'width', 'height'};
final DateTime _now = Fixture.load('yy', 'S06-streams-g2').capturedAt;

const _streams = '/v3/channel/streams';
const _live = '22490906';
const _offline = '85520900';
const _missing = '999999999999';

ReplaySample _synthetic(String url, Object body, {int status = 200, String method = 'GET'}) => ReplaySample(
  method: method,
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

/// A recorded sample's body served at [url].
ReplaySample _moved(String sample, String url, {String Function(String body)? edit}) {
  final recorded = ReplaySample.load('$_root/$sample');
  final text = utf8.decode(recorded.bytes);
  return ReplaySample(
    method: 'GET',
    url: Uri.parse(url),
    status: recorded.status,
    bytes: utf8.encode(edit == null ? text : edit(text)),
  );
}

String _detailUrl(String sid) => 'https://www.yy.com/api/liveInfoDetail/$sid/$sid/0';

String _mobileUrl(String sid, String rate) =>
    'https://interface.yy.com/hls/new/get/$sid/$sid/$rate?source=wapyy&callback=';

/// The 4000 answer the recordings lack: the 高清 stream of 22490906.
ReplaySample _mobile4000(String sid) => _synthetic(
  _mobileUrl(sid, '4000'),
  '({"code":0,"width":720,"audio":"xa_${sid}_${sid}_0_0_0","video":"xv_${sid}_${sid}_0_0_0",'
  '"hls":"https://sslproxy.yy.com:4443/livesystem/15013_xv_${sid}_${sid}_0_0_0.m3u8?org=yyweb&t=1&tk=x","height":1280})',
);

final ReplaySample _serverTimeout = _synthetic(
  'https://stream-manager.yy.com$_streams',
  r'{"res_code":500,"msg":"{\"id\":\"gfy.client\",\"code\":100001,\"detail\":\"call timeout\"}"}',
  status: 500,
  method: 'POST',
);

/// Both mobile HLS rates of [sid] failing.
Map<String, List<Object>> _mobileDown(String sid) => {
  '/hls/new/get/$sid/$sid/1200': [TransportReason.timeout],
  '/hls/new/get/$sid/$sid/4000': [TransportReason.timeout],
};

/// The 4000 answer of a channel without a stream (the recording has 1200).
ReplaySample _noStream4000(String sid) =>
    _synthetic(_mobileUrl(sid, '4000'), '({"code":0,"width":0,"audio":"","video":"","height":0})');

/// Answers scripted responses for a path in order (a [TransportReason]
/// throws), then replays [inner].
final class _Scripted implements LiveHttp {
  new(this.inner, this.script);

  final ReplayHttp inner;
  final Map<String, List<Object>> script;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final queue = script[request.url.path];
    if (queue == null || queue.isEmpty) return await inner.send(request);
    inner.requests.add(request);
    final next = queue.removeAt(0);
    if (next is TransportReason) throw TransportFailure('yy', next, 'scripted');
    final sample = next as ReplaySample;
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
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('yy', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('yy', reason, 'test');

  @override
  void close() {}
}

typedef _Setup = ({YySite site, ReplayHttp http});

_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  Map<String, List<Object>> script = const {},
  CookieVault? cookies,
}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in samples) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: _ignored);
  final site = YySite(
    script.isEmpty
        ? http
        : _Scripted(http, {
            for (final MapEntry(:key, :value) in script.entries) key: [...value],
          }),
    cookies: cookies,
    now: () => _now,
  );
  return (site: site, http: http);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

LiveRoom _room(String sid) => LiveRoom(platform: 'yy', roomId: sid);

const _dance = LiveArea(platform: 'yy', areaType: '1', typeName: '娱乐', areaId: '4', areaName: '舞蹈');
const _categorySamples = ['S01-category-ent', 'S01-category-game', 'S01-category-other'];

void main() {
  group('catalog', () {
    test('6-5: header and getCategory only (4 requests, 3.x: 22); the areas of 3.x without shortName', () async {
      final setup = _setup(['S01-header', ..._categorySamples]);
      final categories = await setup.site.getCategories(1, 20);
      expect(categories.map((category) => (category.id, category.name)), [('1', '娱乐'), ('2', '游戏'), ('3', '其他')]);
      var stored = 0;
      for (final (index, name) in _categorySamples.indexed) {
        final all = ((Fixture.load('yy', name).legacy as Map)['areas'] as List).cast<Map<String, dynamic>>();
        // C-19: 小视频 (a short-video page, areaId 34) is left out.
        final legacy = [
          for (final area in all)
            if (area['areaName'] != '小视频') area,
        ];
        expect(all.length - legacy.length, name == 'S01-category-other' ? 1 : 0, reason: name);
        final areas = categories[index].children;
        expect(areas.map((area) => area.areaId), legacy.map((area) => area['areaId']), reason: name);
        for (final (position, area) in areas.indexed) {
          final json = area.toJson();
          for (final key in ['platform', 'areaType', 'typeName', 'areaId', 'areaName']) {
            expect(json[key] ?? '', legacy[position][key] ?? '', reason: '$name[$position] $key');
          }
          // shortName: 6-5 (3.x read every area page to fill it; the area's
          // page is read when it is opened).
          expect(area.shortName, isEmpty);
          if ((legacy[position]['shortName'] as String? ?? '').isNotEmpty) stored++;
        }
      }
      expect(stored, 2, reason: '3.x filled it from the two recorded area pages');
      expect(_paths(setup.http), [
        '/yyweb/module/data/header',
        for (var i = 0; i < 3; i++) '/c/yycom/category/getCategory.action',
      ]);
    });

    test('6-5: after the catalog, opening an area reads its page once; one that fails fails only there', () async {
      final setup = _setup(
        ['S01-header', ..._categorySamples, 'S02-area-page-dance', 'S02-dance-p1', 'S02-dance-p5'],
        script: {
          '/chicken/lol': [TransportReason.timeout],
        },
      );
      final categories = await setup.site.getCategories(1, 20);
      final dance = categories.first.children.firstWhere((area) => area.areaId == '4');
      expect(await setup.site.getCategoryRooms(dance), hasLength(30));
      expect(await setup.site.getCategoryRooms(dance, page: 5), hasLength(16));
      expect(_paths(setup.http).skip(4), ['/dancing', '/more/page.action', '/more/page.action']);
      final lol = categories[1].children.firstWhere((area) => area.areaId == '23');
      await expectLater(setup.site.getCategoryRooms(lol), throwsA(isA<NetworkFailure>()));
    });

    test('a failing getCategory fails the catalog', () async {
      final failing = _synthetic('https://www.yy.com/c/yycom/category/getCategory.action', 'x', status: 502);
      final broken = _setup(
        ['S01-header'],
        script: {
          '/c/yycom/category/getCategory.action': [failing, failing, failing],
        },
      );
      await expectLater(broken.site.getCategories(1, 20), throwsA(isA<NetworkFailure>()));
    });
  });

  group('area rooms', () {
    test('a stored shortName (3.x areas and follows) asks page.action straight away, with 3.x’s query', () async {
      final setup = _setup(['S02-dance-p1']);
      final shortName = (Fixture.load('yy', 'S02-area-page-dance').legacy as Map)['shortName'] as String;
      final area = LiveArea(
        platform: 'yy',
        areaType: '1',
        typeName: '娱乐',
        areaId: '4',
        areaName: '舞蹈',
        shortName: shortName,
      );
      final rooms = await setup.site.getCategoryRooms(area);
      expect(rooms, hasLength(30));
      expect(rooms.every((room) => room.area == '舞蹈' && room.isLiveNow), isTrue);
      final request = setup.http.requests.single;
      expect(
        request.url.queryParameters,
        ((Fixture.load('yy', 'S02-dance-p1').legacy as Map)['query'] as Map).cast<String, String>(),
      );
      expect(request.headers, YyApi.apiHeaders());
    });

    test('without shortName the area page is read once, found through getCategory', () async {
      final setup = _setup(['S01-category-ent', 'S02-area-page-dance', 'S02-dance-p1', 'S02-dance-p5']);
      expect(await setup.site.getCategoryRooms(_dance), hasLength(30));
      expect(_paths(setup.http), ['/c/yycom/category/getCategory.action', '/dancing', '/more/page.action']);
      expect(await setup.site.getCategoryRooms(_dance, page: 5), hasLength(16));
      expect(_paths(setup.http).skip(3), ['/more/page.action'], reason: 'the module is kept');
    });

    test('a module-less area (moduleId 0) lists the cards of its page, without asking page.action (M4.D)', () async {
      final shortName = (Fixture.load('yy', 'S02-area-page-lol').legacy as Map)['shortName'] as String;
      final stored = _setup(['S01-category-game', 'S02-area-page-lol']);
      final area = LiveArea(platform: 'yy', areaType: '2', areaId: '23', areaName: '英雄联盟', shortName: shortName);
      expect(await stored.site.getCategoryRooms(area), isEmpty, reason: 'the page renders no card');
      expect(_paths(stored.http), ['/c/yycom/category/getCategory.action', '/chicken/lol']);
      final read = _setup(['S01-category-other', 'S02-area-page-mobilelive']);
      const mobile = LiveArea(platform: 'yy', areaType: '3', typeName: '其他', areaId: '27', areaName: '手机直播');
      final rooms = await read.site.getCategoryRooms(mobile);
      expect(rooms, hasLength(18), reason: '3.x and M4.6 listed nothing; the site shows these');
      expect(rooms.every((room) => room.area == '手机直播' && room.isLiveNow), isTrue);
      expect(_paths(read.http), [
        '/c/yycom/category/getCategory.action',
        '/others/mobilelive/',
      ], reason: 'one page read');
      expect(await read.site.getCategoryRooms(mobile, page: 2), isEmpty);
      expect(await read.site.getCategoryRooms(mobile), hasLength(18));
      expect(_paths(read.http).skip(2), ['/others/mobilelive/'], reason: 'page 1 again reads the page again');
    });

    test('an area missing from its category is NotFound; a page without pageInfo (小视频) is empty', () async {
      final setup = _setup(['S01-category-ent', 'S01-category-other', 'S02-area-page-sv']);
      await expectLater(
        setup.site.getCategoryRooms(const LiveArea(platform: 'yy', areaType: '1', areaId: '999')),
        throwsA(isA<NotFound>()),
      );
      expect(
        await setup.site.getCategoryRooms(const LiveArea(platform: 'yy', areaType: '3', areaId: '34', areaName: '小视频')),
        isEmpty,
        reason: 'a short-video page; 3.x sent page.action without a module and got HTTP 400, M4.6 said ApiChanged',
      );
    });
  });

  group('recommend and search', () {
    test('recommendations: 3.x’s query; no area until an area page names the biz (6-3)', () async {
      final setup = _setup(
        ['S03-recommend-p1', 'S01-category-ent', 'S02-area-page-dance', 'S02-dance-p1'],
        extra: [
          _moved(
            'S02-dance-p1',
            'https://www.yy.com/more/page.action?page=2&pageSize=30&biz=other&subBiz=idx&moduleId=-1',
          ),
        ],
      );
      final rooms = await setup.site.getRecommendRooms();
      expect(rooms, hasLength(30));
      expect(rooms.map((room) => room.area).toSet(), {''}, reason: '3.x: `other` on every card');
      expect(rooms.every((room) => room.startedAt != null), isTrue);
      expect(
        setup.http.requests.single.url.queryParameters,
        ((Fixture.load('yy', 'S03-recommend-p1').legacy as Map)['query'] as Map).cast<String, String>(),
      );
      // Cards whose biz is `dance`: named by the preset before any area page
      // was read (C-21; 3.x: `dance`, 6-3: empty), and after.
      expect((await setup.site.getRecommendRooms(page: 2)).first.area, '舞蹈');
      await setup.site.getCategoryRooms(_dance);
      expect((await setup.site.getRecommendRooms(page: 2)).first.area, '舞蹈');
    });

    test('6-3/6-5: a followed area’s stored shortName names its biz too, without reading the page', () async {
      final setup = _setup(
        ['S02-dance-p1'],
        extra: [
          _moved(
            'S02-dance-p1',
            'https://www.yy.com/more/page.action?page=2&pageSize=30&biz=other&subBiz=idx&moduleId=-1',
          ),
        ],
      );
      final shortName = (Fixture.load('yy', 'S02-area-page-dance').legacy as Map)['shortName'] as String;
      await setup.site.getCategoryRooms(
        LiveArea(platform: 'yy', areaType: '1', areaId: '4', areaName: '热舞', shortName: shortName),
      );
      expect((await setup.site.getRecommendRooms(page: 2)).first.area, '热舞', reason: 'learnt before the preset');
      expect(_paths(setup.http), ['/more/page.action', '/more/page.action']);
    });

    test('search: rooms and streamers with 3.x’s query and one request each; a blank keyword sends nothing', () async {
      final setup = _setup(['S04-search-p1', 'S04-search-anchors']);
      final rooms = await setup.site.searchRooms('舞蹈');
      expect(rooms, hasLength(16));
      expect(rooms.first.title, '创艺灵珊', reason: '6-2');
      expect(
        setup.http.requests.single.url.queryParameters,
        ((Fixture.load('yy', 'S04-search-p1').legacy as Map)['query'] as Map).cast<String, String>(),
      );
      expect(await setup.site.searchAnchors('舞蹈'), hasLength(15));
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(await setup.site.searchAnchors(''), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });
  });

  group('detail', () {
    test('a live channel: one request; danmaku arguments, channel data and the start', () async {
      final setup = _setup(['S05-detail-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      expect(room.danmakuData, const YyDanmakuArgs(topSid: 22490906, subSid: 22490906));
      expect((room.data! as YyRoomData).sid, _live);
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 16, 50, 18));
      expect(room.area, isEmpty, reason: '6-3: the raw biz `other`');
      expect(_paths(setup.http), ['/api/liveInfoDetail/$_live/$_live/0']);
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect((await setup.site.getRoomDetailForRefresh(roomId: _live)).startedAt, room.startedAt);
      expect(setup.http.requests, hasLength(3), reason: 'a live room never needs its page');
    });

    test('offline on entry: the room page names the streamer and gives the danmaku arguments (6-7)', () async {
      final setup = _setup(['S05-detail-offline', 'S05-page-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.roomId, _offline);
      expect(room.nick, '小洲- 00000o0000');
      expect(room.area, '段子手');
      expect(room.danmakuData, const YyDanmakuArgs(topSid: 85520900, subSid: 85520900), reason: '3.x: none');
      expect(_paths(setup.http), ['/api/liveInfoDetail/$_offline/$_offline/0', '/$_offline']);
      await setup.site.getRoomDetail(roomId: _offline);
      expect(_paths(setup.http).skip(2), ['/api/liveInfoDetail/$_offline/$_offline/0', '/$_offline'], reason: 'always');
    });

    test('6-8: refresh, recording and live status read an offline room’s page once, then 3.x’s one request', () async {
      final setup = _setup(['S05-detail-offline', 'S05-page-offline']);
      final legacy = (Fixture.load('yy', 'S05-detail-offline').legacy as Map)['room'] as Map<String, dynamic>;
      final first = await setup.site.getRoomDetailForRefresh(roomId: _offline);
      // title, nick, avatar: the page read once (6-8) names the streamer as
      // room entry does; the state and the rest are 3.x's.
      for (final MapEntry(:key, :value) in legacy.entries) {
        if (key == 'danmakuData' || key == 'title' || key == 'nick' || key == 'avatar') continue;
        expect(first.toJson()[key] ?? '', value ?? '', reason: key);
      }
      expect(first.nick, '小洲- 00000o0000');
      expect(_paths(setup.http), ['/api/liveInfoDetail/$_offline/$_offline/0', '/$_offline']);
      final again = await setup.site.getRoomDetailForRefresh(roomId: _offline);
      for (final MapEntry(:key, :value) in legacy.entries) {
        expect(again.toJson()[key] ?? '', value ?? '', reason: 'afterwards 3.x’s room: $key');
      }
      expect((await setup.site.getRoomDetailForRecording(roomId: _offline)).effectiveLiveStatus, LiveStatus.offline);
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
      expect(_paths(setup.http).skip(2), everyElement('/api/liveInfoDetail/$_offline/$_offline/0'));
      expect(setup.http.requests, hasLength(5));
      final merged = LiveRoom(platform: 'yy', roomId: _offline, nick: '小洲', avatar: 'https://a/b.png').mergeFrom(again);
      expect((merged.nick, merged.avatar), ('小洲', 'https://a/b.png'), reason: 'the follow keeps its name');
      expect(merged.effectiveLiveStatus, LiveStatus.offline);
    });

    test('6-8: an unknown channel is NotFound on refresh, recording and state checks too (3.x: offline)', () async {
      final setup = _setup(['S05-detail-missing', 'S05-page-missing']);
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRecording(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: _missing), throwsA(isA<NotFound>()));
      expect(_paths(setup.http), [
        for (var i = 0; i < 3; i++) ...['/api/liveInfoDetail/$_missing/$_missing/0', '/$_missing'],
      ], reason: 'an unknown channel is not remembered: it may be created');
    });

    test('6-8: a followed short number is followed to its canonical channel on refresh', () async {
      final setup = _setup(
        ['S05-page-asid'],
        extra: [
          _synthetic(_detailUrl('2149'), {'resultCode': 0, 'data': null}),
          _moved('S05-detail-live', _detailUrl('35340121'), edit: (body) => body.replaceAll(_live, '35340121')),
        ],
      );
      final room = await setup.site.getRoomDetailForRefresh(roomId: '2149');
      expect((room.roomId, room.isLiveNow), ('2149', true), reason: '3.x: offline for ever');
      expect(_paths(setup.http), [
        '/api/liveInfoDetail/2149/2149/0',
        '/2149',
        '/api/liveInfoDetail/35340121/35340121/0',
      ]);
      expect(await setup.site.getLiveStatus(roomId: '2149'), isTrue);
      expect(_paths(setup.http).skip(3), ['/api/liveInfoDetail/35340121/35340121/0'], reason: 'remembered');
    });

    test('an unknown channel is NotFound on entry, not offline (REG-YY-007); a non-number asks nothing', () async {
      final setup = _setup(['S05-detail-missing', 'S05-page-missing']);
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      final before = setup.http.requests.length;
      await expectLater(setup.site.getRoomDetail(roomId: 'music'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: '0123'), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(before));
    });

    test('a short number keeps its identity and plays its canonical channel (REG-YY-008)', () async {
      final setup = _setup(
        ['S05-page-asid'],
        extra: [
          _synthetic(_detailUrl('2149'), {'resultCode': 0, 'data': null}),
          _moved('S05-detail-live', _detailUrl('35340121'), edit: (body) => body.replaceAll(_live, '35340121')),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: '2149');
      expect(room.roomId, '2149', reason: 'a follow keeps the id it was made with');
      expect(room.isLiveNow, isTrue);
      expect(room.link, 'https://www.yy.com/2149');
      expect((room.data! as YyRoomData).sid, '35340121');
      expect(room.danmakuData, const YyDanmakuArgs(topSid: 35340121, subSid: 35340121));
      expect(_paths(setup.http), [
        '/api/liveInfoDetail/2149/2149/0',
        '/2149',
        '/api/liveInfoDetail/35340121/35340121/0',
      ]);
      await setup.site.getRoomDetailForRefresh(roomId: '2149');
      expect(_paths(setup.http).skip(3), ['/api/liveInfoDetail/35340121/35340121/0'], reason: 'remembered');
    });

    test('a short number of an offline channel is offline under its own number', () async {
      final setup = _setup(
        ['S05-page-asid'],
        extra: [
          _synthetic(_detailUrl('2149'), {'resultCode': 0, 'data': null}),
          _synthetic(_detailUrl('35340121'), {'resultCode': 0, 'data': null}),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: '2149');
      expect((room.roomId, room.effectiveLiveStatus), ('2149', LiveStatus.offline));
      expect((room.data! as YyRoomData).sid, '35340121');
      expect(room.danmakuData, const YyDanmakuArgs(topSid: 35340121, subSid: 35340121), reason: '6-7');
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: '2149');
      expect((refreshed.data! as YyRoomData).sid, '35340121');
      expect(_paths(setup.http).skip(3), ['/api/liveInfoDetail/35340121/35340121/0'], reason: 'no page again (6-8)');
    });

    test('another resultCode is ApiChanged (3.x showed an error room)', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic(_detailUrl(_live), {'resultCode': -1}),
        ],
      );
      await expectLater(setup.site.getRoomDetail(roomId: _live), throwsA(isA<ApiChanged>()));
    });
  });

  group('streams', () {
    test('qualities: mobile HLS first, with the names 3.x users saw; stream-manager is not asked', () async {
      final setup = _setup(['S07-mobile-hls'], extra: [_mobile4000(_live)]);
      final qualities = await setup.site.getPlayQualities(detail: _room(_live));
      expect(qualities.map((quality) => (quality.quality, quality.data)), [
        ('高清 · 720p', 'mobile-hls:4000'),
        ('流畅 · 360p', 'mobile-hls:1200'),
      ]);
      expect(setup.http.requests.every((request) => request.url.host == 'interface.yy.com'), isTrue);
      final mobile = setup.http.requests.first;
      expect(mobile.headers['user-agent'], YyApi.mobileUserAgent);
      expect(mobile.headers['referer'], 'https://wap.yy.com/mobileweb/$_live/$_live');
      final resolution = await setup.site.resolvePlayUrls(detail: _room(_live), quality: qualities.last);
      expect(resolution.lines.single.format, StreamFormat.hls);
      expect(resolution.lines.single.headers, YyApi.mediaHeaders());
      expect(resolution.lines.single.lease, isNull, reason: 'the HLS t is the issue time');
      expect(resolution.appliedQualityData, 'mobile-hls:1200');
      expect(setup.http.requests.where((request) => request.url.host == 'stream-manager.yy.com'), isEmpty);
    });

    test('mobile HLS has nothing: stream-manager at gear 1, a JSON body sent as text/plain (REG-YY-003)', () async {
      final setup = _setup(['S06-streams-g1'], script: _mobileDown(_live));
      final qualities = await setup.site.getPlayQualities(detail: _room(_live));
      expect(qualities.map((quality) => (quality.id, quality.quality)), [('2', '高清'), ('1', '流畅')]);
      final request = setup.http.requests.last;
      expect(request.method, 'POST');
      expect(request.headers['content-type'], 'text/plain;charset=UTF-8');
      expect(request.headers['referer'], 'https://www.yy.com/$_live/$_live');
      expect(request.headers['origin'], 'https://www.yy.com');
      // 3.x handed Dio the map with this content type, and Dio form-encoded
      // it (`head%5Bseq%5D=…`), which stream-manager answers with HTTP 500.
      final body = jsonDecode(utf8.decode(request.body!)) as Map<String, dynamic>;
      expect((body['avp_parameter'] as Map)['gear'], 1);
      expect((body['head'] as Map)['seq'], _now.millisecondsSinceEpoch);
      expect(request.url.queryParameters, {
        'uid': '0',
        'cid': _live,
        'sid': _live,
        'appid': '0',
        'sequence': '${_now.millisecondsSinceEpoch}',
        'encode': 'json',
      });
    });

    test('lines at gear 2: both CDN lines (6-4), FLV, media headers, line_seq and leases; gear 2 confirmed', () async {
      final setup = _setup(['S06-streams-g2', 'S06-streams-g2-l10']);
      final resolution = await setup.site.resolvePlayUrls(
        detail: _room(_live),
        quality: const LivePlayQuality(quality: '高清', id: '2', data: '2', sort: 2300),
      );
      expect(resolution.lines.map((line) => (line.lineId, Uri.parse(line.url).host)), [
        ('14', 'ks-flv-web.yy.com'),
        ('10', 'tx-flv-web.yy.com'),
      ], reason: '3.x: line 14 only');
      for (final line in resolution.lines) {
        expect(line.format, StreamFormat.flv);
        expect(line.headers, YyApi.mediaHeaders());
        expect(line.lease!.expiresAt!.difference(_now).inSeconds, inInclusiveRange(599, 604));
      }
      expect(resolution.appliedQualityData, '2');
      final bodies = [
        for (final request in setup.http.requests) (jsonDecode(utf8.decode(request.body!)) as Map)['avp_parameter'],
      ];
      expect(bodies.map((body) => ((body as Map)['gear'], body['line_seq'])), [(2, -1), (2, 10)]);
    });

    test('6-4: another line that fails or serves another gear is left out', () async {
      final failing = _setup(
        ['S06-streams-g2'],
        script: {
          _streams: [ReplaySample.load('$_root/S06-streams-g2'), _serverTimeout],
        },
      );
      const quality = LivePlayQuality(quality: '高清', id: '2', data: '2', sort: 2300);
      final one = await failing.site.resolvePlayUrls(detail: _room(_live), quality: quality);
      expect(one.lines.single.lineId, '14');
      expect(failing.http.requests, hasLength(2));
      final otherGear = _setup(
        [],
        script: {
          _streams: [ReplaySample.load('$_root/S06-streams-g2'), ReplaySample.load('$_root/S06-streams-g1')],
        },
      );
      expect((await otherGear.site.resolvePlayUrls(detail: _room(_live), quality: quality)).lines, hasLength(1));
      final cancelled = _setup(
        [],
        script: {
          _streams: [ReplaySample.load('$_root/S06-streams-g2'), TransportReason.cancelled],
        },
      );
      await expectLater(
        cancelled.site.resolvePlayUrls(detail: _room(_live), quality: quality),
        throwsA(isA<TransportFailure>()),
        reason: 'a cancelled request is not a missing line',
      );
    });

    test('gear 3 has no web stream: served gear 2, and the lines say so (REG-YY-004)', () async {
      final setup = _setup(['S06-streams-g1', 'S06-streams-g3', 'S06-streams-g2-l10'], script: _mobileDown(_live));
      final qualities = await setup.site.getPlayQualities(detail: _room(_live));
      expect(qualities.map((quality) => quality.id), isNot(contains('3')), reason: '3.x listed 超清');
      const requested = LivePlayQuality(quality: '超清', id: '3', data: '3', sort: 2100);
      final resolution = await setup.site.resolvePlayUrls(detail: _room(_live), quality: requested);
      expect(resolution.appliedQualityData, '2');
      expect(
        resolveAppliedPlayQuality(qualities: qualities, requested: requested, resolution: resolution).quality,
        '高清',
      );
    });

    test('a mobile quality whose HLS fails plays the same tier as FLV on both lines, with leases', () async {
      final setup = _setup(
        ['S06-streams-g2', 'S06-streams-g2-l10'],
        script: {
          '/hls/new/get/$_live/$_live/4000': [TransportReason.timeout],
        },
      );
      const quality = LivePlayQuality(quality: '高清 · 720p', id: 'mobile-hls:4000', data: 'mobile-hls:4000', sort: 4000);
      final resolution = await setup.site.resolvePlayUrls(detail: _room(_live), quality: quality);
      expect(resolution.lines.map((line) => line.lineId), ['14', '10'], reason: '6-4');
      final line = resolution.lines.first;
      expect(line.format, StreamFormat.flv);
      expect(line.headers, YyApi.mediaHeaders());
      final lease = line.lease!;
      expect(lease.expiresAt!.difference(_now).inSeconds, inInclusiveRange(599, 601));
      expect(lease.expiresAt!.difference(lease.refreshAt), YyApi.leaseLead);
      expect(lease.cutsConnection, isFalse);
      expect(resolution.appliedQualityData, isNull, reason: 'standing in confirms no quality');
      final body = jsonDecode(utf8.decode(setup.http.requests[1].body!)) as Map<String, dynamic>;
      expect((body['avp_parameter'] as Map)['gear'], 2, reason: '4000 is the 高清 tier (gear 2)');
      expect(
        resolveAppliedPlayQuality(qualities: const [quality], requested: quality, resolution: resolution).quality,
        '高清 · 720p',
      );
    });

    test('a mobile quality with no stream anywhere is StreamUnavailable', () async {
      final setup = _setup(['S07-mobile-hls-offline', 'S06-streams-offline']);
      await expectLater(
        setup.site.resolvePlayUrls(
          detail: _room(_offline),
          quality: const LivePlayQuality(quality: '流畅 · 360p', id: 'mobile-hls:1200', data: 'mobile-hls:1200'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a stream-manager quality that fails plays mobile HLS at 4000 (rate ≥ 2000) or 1200', () async {
      final setup = _setup(
        ['S07-mobile-hls'],
        extra: [_mobile4000(_live)],
        script: {
          _streams: [_serverTimeout, _serverTimeout],
        },
      );
      final high = await setup.site.resolvePlayUrls(
        detail: _room(_live),
        quality: const LivePlayQuality(quality: '高清', id: '2', data: '2', sort: 2300),
      );
      expect(high.urls.single, contains('_0_0_0.m3u8'));
      expect(high.appliedQualityData, isNull, reason: 'a fallback confirms nothing');
      final low = await setup.site.resolvePlayUrls(
        detail: _room(_live),
        quality: const LivePlayQuality(quality: '流畅', id: '1', data: '1', sort: 600),
      );
      expect(low.urls.single, contains('_0_1_0'));
    });

    test('an offline channel: no mobile stream, no gear → StreamUnavailable', () async {
      final setup = _setup(['S06-streams-offline', 'S07-mobile-hls-offline'], extra: [_noStream4000(_offline)]);
      await expectLater(setup.site.getPlayQualities(detail: _room(_offline)), throwsA(isA<StreamUnavailable>()));
      expect(_paths(setup.http), [
        '/hls/new/get/$_offline/$_offline/1200',
        '/hls/new/get/$_offline/$_offline/4000',
        _streams,
      ]);
    });

    test('when every route fails, the first failure is reported', () async {
      final setup = _setup(
        [],
        script: {
          ..._mobileDown(_live),
          _streams: [_serverTimeout],
        },
      );
      await expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(isA<NetworkFailure>()));
      expect(setup.http.requests.last.url.path, _streams);
    });

    test('a room read by its short number plays its canonical channel', () async {
      final setup = _setup(
        ['S07-mobile-hls-offline'],
        extra: [_noStream4000(_offline)],
        script: {
          _streams: [_serverTimeout],
        },
      );
      final room = LiveRoom(
        platform: 'yy',
        roomId: '2149',
        data: const YyRoomData(sid: _offline, ssid: _offline),
      );
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests.first.url.path, '/hls/new/get/$_offline/$_offline/1200');
      expect(setup.http.requests.last.url.queryParameters['cid'], _offline);
      final legacy = LiveRoom(
        platform: 'yy',
        roomId: '2149',
        danmakuData: const YyDanmakuArgs(topSid: 85520900, subSid: 85520900),
      );
      final again = _setup(
        ['S07-mobile-hls-offline'],
        extra: [_noStream4000(_offline)],
        script: {
          _streams: [_serverTimeout],
        },
      );
      await expectLater(again.site.getPlayQualities(detail: legacy), throwsA(isA<StreamUnavailable>()));
      expect(again.http.requests.first.url.path, '/hls/new/get/$_offline/$_offline/1200', reason: "3.x's arguments");
    });

    test('the user cookie goes with API requests and media lines', () async {
      final vault = MemoryCookieVault()..set('yy', 'yyuid=1; udb_oar=x');
      addTearDown(vault.dispose);
      final setup = _setup(['S05-detail-live', 'S06-streams-g2', 'S06-streams-g2-l10'], cookies: vault);
      await setup.site.getRoomDetail(roomId: _live);
      final resolution = await setup.site.resolvePlayUrls(
        detail: _room(_live),
        quality: const LivePlayQuality(quality: '高清', id: '2', data: '2', sort: 2300),
      );
      expect(setup.http.requests, hasLength(3));
      expect(setup.http.requests.map((request) => request.headers['cookie']).toSet(), {'yyuid=1; udb_oar=x'});
      expect(resolution.lines.map((line) => line.headers['cookie']), ['yyuid=1; udb_oar=x', 'yyuid=1; udb_oar=x']);
    });
  });

  group('FLV first (6-1)', () {
    _Setup flvFirst(
      List<String> samples, {
      List<ReplaySample> extra = const [],
      Map<String, List<Object>> script = const {},
    }) {
      final http = ReplayHttp([
        ...extra,
        for (final name in samples) ReplaySample.load('$_root/$name'),
      ], ignoredQuery: _ignored);
      final transport = script.isEmpty
          ? http
          : _Scripted(http, {
              for (final MapEntry(:key, :value) in script.entries) key: [...value],
            });
      return (site: YySite(transport, flvFirst: true, now: () => _now), http: http);
    }

    test('off by default: 3.x’s mobile HLS qualities come first', () {
      expect(YySite(ReplayHttp(const [])).flvFirst, isFalse);
    });

    test('qualities from stream-manager in one request, the platform’s names; mobile HLS is not asked', () async {
      final setup = flvFirst(['S06-streams-g1', 'S06-streams-g2', 'S06-streams-g2-l10']);
      final qualities = await setup.site.getPlayQualities(detail: _room(_live));
      expect(qualities.map((quality) => (quality.id, quality.quality)), [('2', '高清'), ('1', '流畅')]);
      expect(_paths(setup.http), [_streams]);
      final resolution = await setup.site.resolvePlayUrls(detail: _room(_live), quality: qualities.first);
      expect(resolution.lines.map((line) => (line.format, line.lineId)), [
        (StreamFormat.flv, '14'),
        (StreamFormat.flv, '10'),
      ]);
      expect(resolution.lines.every((line) => line.lease != null), isTrue, reason: 'renewed by M7');
      expect(resolution.appliedQualityData, '2');
      expect(setup.http.requests.where((request) => request.url.host == 'interface.yy.com'), isEmpty);
      expect(YyApi.flvQualityId('mobile-hls:4000', qualities), '2', reason: 'M9: 高清 · 720p becomes 高清');
    });

    test('stream-manager failing or without a stream: mobile HLS stands in', () async {
      final failing = flvFirst(
        ['S07-mobile-hls'],
        extra: [_mobile4000(_live)],
        script: {
          _streams: [_serverTimeout],
        },
      );
      final qualities = await failing.site.getPlayQualities(detail: _room(_live));
      expect(qualities.map((quality) => quality.quality), ['高清 · 720p', '流畅 · 360p']);
      expect(_paths(failing.http).first, _streams);
      final offline = flvFirst(['S06-streams-offline', 'S07-mobile-hls-offline'], extra: [_noStream4000(_offline)]);
      await expectLater(offline.site.getPlayQualities(detail: _room(_offline)), throwsA(isA<StreamUnavailable>()));
      expect(_paths(offline.http), [
        _streams,
        '/hls/new/get/$_offline/$_offline/1200',
        '/hls/new/get/$_offline/$_offline/4000',
      ]);
    });

    test('a quality whose stream-manager request fails plays mobile HLS (3.x’s fallback)', () async {
      final setup = flvFirst(
        ['S07-mobile-hls'],
        script: {
          _streams: [_serverTimeout],
        },
      );
      final low = await setup.site.resolvePlayUrls(
        detail: _room(_live),
        quality: const LivePlayQuality(quality: '流畅', id: '1', data: '1', sort: 600),
      );
      expect(low.lines.single.format, StreamFormat.hls);
      expect(low.appliedQualityData, isNull);
    });

    test('every route failing reports the first failure', () async {
      final setup = flvFirst(
        [],
        script: {
          ..._mobileDown(_live),
          _streams: [_serverTimeout],
        },
      );
      await expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(isA<NetworkFailure>()));
      expect(setup.http.requests.first.url.path, _streams);
    });
  });

  group('links', () {
    test('channel pages of yy.com and the mobile page; other pages are not rooms (3.x cases)', () {
      final site = _setup([]).site;
      expect(site.roomIdFromUrl('https://www.yy.com/123/456?tempId=789'), '123');
      expect(site.roomIdFromUrl('https://www.yy.com/1382731151'), '1382731151');
      expect(site.roomIdFromUrl('https://www.yy.com/22490906/22490906?tempId=16777217'), _live);
      expect(site.roomIdFromUrl('https://wap.yy.com/mobileweb/54880976/54880976'), '54880976');
      expect(site.roomIdFromUrl('https://yy.com/123'), '123');
      expect(site.roomIdFromUrl('https://www.yy.com/'), isNull);
      expect(site.roomIdFromUrl('https://www.yy.com/music/'), isNull);
      expect(site.roomIdFromUrl('https://www.yy.com/search-test'), isNull);
      expect(site.roomIdFromUrl('https://www.yy.com/0'), isNull);
      expect(site.roomIdFromUrl('https://notyy.com/123'), isNull);
      expect(site.roomIdFromUrl('ftp://www.yy.com/123'), isNull);
      expect(site.needsResolving('https://www.yy.com/123'), isFalse);
    });

    test('a share text is parsed without requests', () async {
      final http = ReplayHttp(const []);
      final registry = SiteRegistry({'yy': () => YySite(http)});
      final parser = LinkParser(registry, http);
      expect(
        await parser.parse('来看 https://www.yy.com/22490906/22490906?tempId=16777217 。'),
        const RoomLink('yy', _live),
      );
      expect(parser.containsSupportedLink('https://www.yy.com/123'), isTrue);
      expect(http.requests, isEmpty);
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    await expectLater(
      YySite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: _live),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      YySite(_Failing(TransportReason.cancelled)).searchRooms('x'),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
    await expectLater(
      YySite(_Failing(TransportReason.cancelled)).getPlayQualities(detail: _room(_live)),
      throwsA(isA<TransportFailure>()),
      reason: 'a cancelled request does not go on to the other route',
    );
  });
}
