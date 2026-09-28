// CcSite over the recorded CC responses (ReplayHttp) and a few synthetic
// ones: the mobile catalog with the official entries, area pages and the
// directory pager, the recommendation list, search, the detail steps with
// the follow refresh's existence check, video_play_url's qualities and
// lines with the 3.x fallback, links and the error mapping.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/cc';

const _lives = '/v1/activitylives/anchor/lives';
const _channel = '/live/channel/';
const _exists = '/v1/wapcc/recommendbyccid';
const _play = '/video_play_url';
const _catalog = '/v1/wapcc/gamecategory';

final DateTime _issued = Fixture.load('cc', 'S06-play-default').capturedAt;

ReplaySample _synthetic(String url, Object body, {int status = 200, String method = 'GET'}) => ReplaySample(
  method: method,
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

/// [sample]'s recorded body under another [url].
ReplaySample _recorded(String sample, String url, {Map<String, dynamic> Function(Map<String, dynamic>)? edit}) {
  final body = Fixture.load('cc', sample).body;
  return _synthetic(url, edit == null ? body : edit(jsonDecode(body) as Map<String, dynamic>));
}

String _playUrl(String ccid, [String query = '']) =>
    'https://vapi.cc.163.com/video_play_url/$ccid?src=webcc_h5&vbrmode=1&use_new_vbrmap=1&secure=1$query';

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    throw TransportFailure('cc', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('cc', reason, 'test');

  @override
  void close() {}
}

/// [replay], except that requests to [path] fail with [reason].
final class _FailingPath implements LiveHttp {
  new(this.replay, this.path, this.reason);

  final ReplayHttp replay;
  final String path;
  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    if (request.url.path != path) return await replay.send(request);
    replay.requests.add(request);
    throw TransportFailure('cc', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => replay.open(request);

  @override
  void close() {}
}

typedef _Setup = ({CcSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: CcSite(http, now: now ?? () => _issued), http: http);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

LiveRoom _room(String ccid) => LiveRoom(roomId: ccid, platform: 'cc');

const _area = LiveArea(platform: 'cc', areaId: '9141', areaType: '2');

const _catalogSamples = [
  'S01-cate-all',
  'S01-cate-online',
  'S01-cate-mobile',
  'S01-cate-esports',
  'S01-cate-show',
  'S01-dashen-games',
  'S01-dashen-config',
];

void main() {
  group('catalog (9-4)', () {
    test('the mobile categories, then 3.x official entries from Dashen, with their headers', () async {
      final setup = _setup(_catalogSamples);
      final categories = await setup.site.getCategories(1, 1000);
      expect(categories.map((category) => (category.id, category.name, category.children.length)), [
        ('1', '网游', 33),
        ('2', '手游', 63),
        ('4', '竞技', 8),
        ('5', '综艺', 2),
        ('official', '官方房间/专题', 4),
      ]);
      expect(categories.last.children.map((area) => area.areaId).first, 'official:249133');
      final requests = setup.http.requests;
      expect(requests, hasLength(7), reason: '1 + 4 categories + 2 Dashen (3.x: 2)');
      final mobile = [
        for (final request in requests)
          if (request.url.path == _catalog) request,
      ];
      expect(mobile.map((request) => request.url.queryParameters['catetype']), ['0', '1', '2', '4', '5']);
      for (final request in mobile) {
        expect(request.url.host, 'api.cc.163.com');
        expect(request.headers, {'user-agent': CcApi.userAgent, 'referer': 'https://cc.163.com/'});
      }
      final [games, config] = [
        for (final request in requests)
          if (request.url.host.endsWith('ds.163.com')) request,
      ];
      expect(games.method, 'GET');
      expect(games.url.queryParameters, {'gameType': 'NETEASE'});
      expect(config.method, 'POST');
      expect(jsonDecode(utf8.decode(config.body!)), {'id': CcApi.catalogConfigurationId});
      for (final request in [games, config]) {
        expect(request.headers['origin'], 'https://ds.163.com');
        expect(request.headers['referer'], 'https://ds.163.com/glive/');
        expect(request.headers['user-agent'], CcApi.userAgent);
      }
    });

    test('failing Dashen requests only leave the official entries out', () async {
      for (final extra in [
        _synthetic('https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig', '', status: 503, method: 'POST'),
        _synthetic('https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig', '<html>', method: 'POST'),
      ]) {
        final setup = _setup(_catalogSamples.where((name) => name != 'S01-dashen-config').toList(), extra: [extra]);
        final categories = await setup.site.getCategories(1, 1000);
        expect(categories.map((category) => category.id), ['1', '2', '4', '5']);
      }
    });

    test('a failing mobile request fails the catalog instead of emptying it (3.x)', () async {
      final setup = _setup(
        _catalogSamples.where((name) => name != 'S01-cate-show').toList(),
        extra: [_synthetic('https://api.cc.163.com$_catalog?catetype=5', '', status: 503)],
      );
      await expectLater(setup.site.getCategories(1, 1000), throwsA(isA<NetworkFailure>()));
      final broken = _setup(
        _catalogSamples.where((name) => name != 'S01-cate-all').toList(),
        extra: [_synthetic('https://api.cc.163.com$_catalog?catetype=0', '{"code":1}')],
      );
      await expectLater(broken.site.getCategories(1, 1000), throwsA(isA<ApiChanged>()));
      await expectLater(
        CcSite(_Failing(TransportReason.connect)).getCategories(1, 1000),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('categories without areas are left out', () async {
      final setup = _setup(
        _catalogSamples.where((name) => name != 'S01-cate-show').toList(),
        extra: [
          _synthetic('https://api.cc.163.com$_catalog?catetype=5', {
            'code': 0,
            'data': {
              'category_info': {'game_list': <Object?>[]},
            },
          }),
        ],
      );
      final categories = await setup.site.getCategories(1, 1000);
      expect(categories.map((category) => category.id), ['1', '2', '4', 'official']);
    });
  });

  group('area rooms', () {
    test('offsets from the page and size; tag 0; an empty page after the last', () async {
      final setup = _setup(['S02-area-page1', 'S02-area-beyond']);
      final first = await setup.site.getCategoryRooms(_area);
      expect(first, hasLength(13));
      expect(await setup.site.getCategoryRooms(_area, page: 2), isEmpty);
      expect(setup.http.requests.first.url.path, '/api/category/9141/');
      expect(
        [for (final request in setup.http.requests) request.url.queryParameters],
        [
          {'format': 'json', 'tag_id': '0', 'start': '0', 'size': '30'},
          {'format': 'json', 'tag_id': '0', 'start': '30', 'size': '30'},
        ],
      );
      expect(setup.http.requests.first.headers['user-agent'], CcApi.userAgent);
    });

    test('a followed area keeps its numeric identity whatever its parent (3.x areas, 9-4)', () async {
      final setup = _setup(['S02-area-page1']);
      final old = LiveArea.fromJson(const {
        'platform': 'cc',
        'areaId': '9141',
        'areaType': '1',
        'typeName': '直播分类',
        'areaName': 'Old',
      });
      expect(await setup.site.getCategoryRooms(old), hasLength(13));
    });

    test('game type 0 (其他游戏 of the mobile catalog) lists its rooms', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://cc.163.com/api/category/0/?format=json&tag_id=0&start=0&size=30', {
            'gametype': 0,
            'name': '其他游戏',
            'lives': [
              {'cuteid': 7, 'status': 1},
            ],
          }),
        ],
      );
      final rooms = await setup.site.getCategoryRooms(const LiveArea(platform: 'cc', areaId: '0', areaType: '1'));
      expect(rooms.single.roomId, '7');
    });

    test('official entries, foreign areas and bad pages are caller errors, without a request (3.x)', () async {
      final setup = _setup([]);
      for (final id in ['', '00', '../3', '3?x=y', 'official:249133']) {
        await expectLater(
          setup.site.getCategoryRooms(LiveArea(platform: 'cc', areaId: id)),
          throwsArgumentError,
          reason: id,
        );
      }
      await expectLater(
        setup.site.getCategoryRooms(const LiveArea(platform: 'huya', areaId: '3')),
        throwsArgumentError,
      );
      for (final (page, size) in [(0, 30), (1, 0), (-1, 30), (1, 1001), (100001, 30)]) {
        await expectLater(
          setup.site.getCategoryRooms(_area, page: page, pageSize: size),
          throwsArgumentError,
          reason: '$page×$size',
        );
      }
      expect(setup.http.requests, isEmpty);
    });

    test('the directory: 30 a page, a full page has more (3.x), cancellation reaches the request', () async {
      final full = {
        'gametype': 9141,
        'lives': [
          for (var id = 1; id <= 30; id++) {'cuteid': id, 'status': 1, 'hot_score': id},
        ],
      };
      final setup = _setup(
        ['S02-area-page1'],
        extra: [_synthetic('https://cc.163.com/api/category/9141/?format=json&tag_id=0&start=30&size=30', full)],
      );
      final directory = setup.site.categoryDirectory;
      final cancel = CancelToken();
      final first = await directory.getDirectoryPage(category: _area, cancel: cancel);
      expect((first.rooms.length, first.page, first.hasMore), (13, 1, false));
      expect(setup.http.requests.single.cancel, same(cancel));
      final second = await directory.getDirectoryPage(page: 2, category: _area);
      expect((second.rooms.length, second.hasMore), (30, true));
      await expectLater(directory.getDirectoryPage(), throwsArgumentError);
    });

    test('more rooms than asked for is ApiChanged; a cancelled request stays cancelled', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://cc.163.com/api/category/9141/?format=json&tag_id=0&start=0&size=30', {
            'gametype': '9141',
            'lives': [
              for (var id = 1; id <= 31; id++) {'cuteid': id, 'status': 1},
            ],
          }),
        ],
      );
      await expectLater(setup.site.categoryDirectory.getDirectoryPage(category: _area), throwsA(isA<ApiChanged>()));
      await expectLater(
        CcSite(_Failing(TransportReason.cancelled)).categoryDirectory.getDirectoryPage(category: _area),
        throwsA(isA<TransportFailure>()),
      );
    });
  });

  group('recommend and search', () {
    test('every room on air, a page at a time; the popular page asks for 100', () async {
      final setup = _setup(
        ['S03-live-page1', 'S03-live-last', 'S03-live-beyond'],
        extra: [_recorded('S03-live-page1', 'https://cc.163.com/api/category/live/?format=json&start=100&size=100')],
      );
      final rooms = await setup.site.getRecommendRooms();
      expect(rooms, hasLength(30));
      expect(rooms.every((room) => room.area!.isNotEmpty), isTrue, reason: '9-2');
      expect(await setup.site.getRecommendRooms(page: 4), hasLength(16));
      expect(await setup.site.getRecommendRooms(page: 11), isEmpty);
      expect(await setup.site.getRecommendRooms(page: 2, pageSize: 100), hasLength(30));
      expect(setup.http.requests.last.url.queryParameters, {'format': 'json', 'start': '100', 'size': '100'});
    });

    test('search asks for /search/anchor/ with the slash (REG-CC-007), 1–50 a page', () async {
      final setup = _setup(
        ['S04-search-page1', 'S04-search-empty'],
        extra: [_recorded('S04-search-empty', 'https://cc.163.com/search/anchor/?query=x&size=50&page=1')],
      );
      final rooms = await setup.site.searchRooms(' 梦幻 ', pageSize: 20);
      expect(rooms, hasLength(20));
      expect(setup.http.requests.single.url.path, '/search/anchor/');
      expect(setup.http.requests.single.url.queryParameters, {'query': '梦幻', 'size': '20', 'page': '1'});
      expect(await setup.site.searchRooms('zzqqxxkkyyww', pageSize: 20), isEmpty);
      expect(await setup.site.searchRooms('x', pageSize: 500), isEmpty);
      final anchors = await setup.site.searchAnchors('梦幻', pageSize: 20);
      expect(anchors.map((anchor) => anchor.roomId), rooms.map((room) => room.roomId));
      expect(anchors.where((anchor) => anchor.liveStatus).map((anchor) => anchor.roomId), [
        '1234567',
      ], reason: 'the three rebroadcasting official accounts are not live (9-3)');
      final before = setup.http.requests.length;
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(setup.http.requests, hasLength(before), reason: 'a blank keyword sends nothing');
    });
  });

  group('detail', () {
    test('a live anchor: activitylives, then its channel (3.x); the same room for every depth', () async {
      final setup = _setup(['S05-lives-live', 'S05-channel-live']);
      final room = await setup.site.getRoomDetail(roomId: ' 341438909 ');
      expect(_paths(setup.http), [_lives, _channel]);
      expect(setup.http.requests.first.url.queryParameters, {'anchor_ccid': '341438909'});
      expect(setup.http.requests.last.url.queryParameters, {'channelids': '5728999'});
      expect(setup.http.requests.first.headers, {'user-agent': CcApi.userAgent, 'referer': 'https://cc.163.com/'});
      expect(room.roomId, '341438909');
      expect(room.isLiveNow, isTrue);
      expect(room.followers, '303', reason: '9-6');
      expect(room.startedAt, DateTime.utc(2026, 9, 14, 6, 53, 45));
      expect(room.restriction, LiveRestriction.none);
      expect(room.data, isA<CcRoomData>());
      expect(room.danmakuData, isNull, reason: 'CC has no danmaku, as in 3.x');
      for (final other in [
        await setup.site.getRoomDetailForRefresh(roomId: '341438909'),
        await setup.site.getRoomDetailForRecording(roomId: '341438909'),
      ]) {
        expect(other.toJson(), room.toJson());
        expect(other.data, isA<CcRoomData>());
      }
      expect(setup.http.requests, hasLength(6), reason: 'two requests each, as 3.x');
      expect(await setup.site.getLiveStatus(roomId: '341438909'), isTrue);
    });

    test('a rebroadcast channel is a replay that plays; not live for the status check (9-3)', () async {
      final setup = _setup(['S05-lives-replay', 'S05-channel-replay']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: '732923115');
      expect(room.title, startsWith('【重播】'));
      expect(room.effectiveLiveStatus, LiveStatus.replay);
      expect((room.isPlayableNow, room.followGroup), (true, FollowGroup.replay));
      expect(await setup.site.getLiveStatus(roomId: '732923115'), isFalse);
      expect(_paths(setup.http), [_lives, _channel, _lives, _channel]);
    });

    test('an offline anchor: the follow refresh checks the id exists (9-7); recording and status do not', () async {
      final setup = _setup(['S05-lives-offline', 'S09-exists-offline']);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: '376267758');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      expect(refreshed.nick, isEmpty, reason: 'the stored card keeps the rest');
      expect(_paths(setup.http), [_lives, _exists], reason: '3.x sent two requests and failed');
      final check = setup.http.requests.last;
      expect(check.url.queryParameters, {'ccid': '376267758'});
      expect(check.headers, {'user-agent': CcApi.userAgent, 'referer': 'https://cc.163.com/'});
      expect(check.timeout, CcSite.existenceTimeout);
      expect((await setup.site.getRoomDetailForRecording(roomId: '376267758')).isExplicitlyOfflineNow, isTrue);
      expect(await setup.site.getLiveStatus(roomId: '376267758'), isFalse);
      expect(_paths(setup.http).skip(2), [_lives, _lives]);
    });

    test('an unknown id: the follow refresh says NotFound (9-7)', () async {
      final setup = _setup(['S05-lives-missing', 'S09-exists-missing']);
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: '88888888888'), throwsA(isA<NotFound>()));
      expect(_paths(setup.http), [_lives, _exists]);
      expect(
        (await setup.site.getRoomDetailForRecording(roomId: '88888888888')).isExplicitlyOfflineNow,
        isTrue,
        reason: 'recording keeps its single request',
      );
    });

    test('a failing, slow or odd existence check leaves the refresh offline; a cancellation propagates', () async {
      for (final answer in [
        _synthetic('https://api.cc.163.com$_exists?ccid=376267758', '', status: 502),
        _synthetic('https://api.cc.163.com$_exists?ccid=376267758', '{"code":2,"msg":"x"}'),
        _synthetic('https://api.cc.163.com$_exists?ccid=376267758', '<html>'),
      ]) {
        final setup = _setup(['S05-lives-offline'], extra: [answer]);
        expect((await setup.site.getRoomDetailForRefresh(roomId: '376267758')).isExplicitlyOfflineNow, isTrue);
      }
      final replay = ReplayHttp([ReplaySample.load('$_root/S05-lives-offline')]);
      final slow = CcSite(_FailingPath(replay, _exists, TransportReason.timeout));
      expect((await slow.getRoomDetailForRefresh(roomId: '376267758')).isExplicitlyOfflineNow, isTrue);
      final cancelled = CcSite(_FailingPath(replay, _exists, TransportReason.cancelled));
      await expectLater(cancelled.getRoomDetailForRefresh(roomId: '376267758'), throwsA(isA<TransportFailure>()));
    });

    test('an offline anchor on room entry: the room page fills the room', () async {
      final setup = _setup(['S05-lives-offline', 'S05-page-offline']);
      final room = await setup.site.getRoomDetail(roomId: '376267758');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.nick, '路人7758');
      expect(room.followers, '39802', reason: '9-6');
      expect(_paths(setup.http), [_lives, '/376267758/']);
      expect(setup.http.requests.last.url.queryParameters, {'open': 'blizzardtv', 'from': '8382', 'platform': 'ds'});
    });

    test('a channel that ended between the two requests is offline, without the existence check', () async {
      final setup = _setup(
        ['S05-page-offline'],
        extra: [
          _recorded(
            'S05-lives-offline',
            'https://api.cc.163.com$_lives?anchor_ccid=376267758',
            edit: (root) => root
              ..['data'] = {
                '376267758': {'is_black': 0, 'channel_id': 6734256},
              },
          ),
          _recorded('S05-channel-null', 'https://cc.163.com$_channel?channelids=6734256'),
        ],
      );
      expect((await setup.site.getRoomDetailForRefresh(roomId: '376267758')).isExplicitlyOfflineNow, isTrue);
      expect(_paths(setup.http), [_lives, _channel]);
      final room = await setup.site.getRoomDetail(roomId: '376267758');
      expect(room.nick, '路人7758');
      expect(_paths(setup.http).skip(2), [_lives, _channel, '/376267758/']);
    });

    test('failures are failures, never an offline-looking room (REG-CC-008)', () async {
      final missing = _setup(['S05-lives-missing', 'S05-page-missing']);
      await expectLater(missing.site.getRoomDetail(roomId: '88888888888'), throwsA(isA<NotFound>()));
      final none = _setup([]);
      await expectLater(none.site.getRoomDetail(roomId: 'abc'), throwsA(isA<NotFound>()));
      await expectLater(none.site.getRoomDetailForRefresh(roomId: ''), throwsA(isA<NotFound>()));
      expect(none.http.requests, isEmpty, reason: 'not a ccid: nothing is sent');
      final down = _Failing(TransportReason.connect);
      await expectLater(CcSite(down).getRoomDetail(roomId: '1'), throwsA(isA<NetworkFailure>()));
      await expectLater(
        CcSite(_Failing(TransportReason.cancelled)).getRoomDetailForRefresh(roomId: '1'),
        throwsA(isA<TransportFailure>()),
      );
      final broken = _setup([], extra: [_synthetic('https://api.cc.163.com$_lives?anchor_ccid=1', '{"code":"ERROR"}')]);
      await expectLater(broken.site.getRoomDetailForRecording(roomId: '1'), throwsA(isA<ApiChanged>()));
    });
  });

  group('streams (9-1)', () {
    test("a live room plays video_play_url's real tiers; the qualities answer serves the first play", () async {
      final setup = _setup(
        ['S05-lives-live', 'S05-channel-live', 'S06-play-default', 'S06-play-high'],
        extra: [_recorded('S06-play-default', _playUrl('341438909', '&vbrname=original'))],
      );
      final detail = await setup.site.getRoomDetail(roomId: '341438909');
      final before = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: detail);
      expect(
        [for (final quality in qualities) (quality.quality, quality.id)],
        [('原画', 'original'), ('超清', 'ultra'), ('高清', 'high'), ('标清', 'standard')],
      );
      expect(_paths(setup.http).skip(before), ['$_play/341438909']);
      expect(setup.http.requests.last.url.queryParameters, {
        'src': 'webcc_h5',
        'vbrmode': '1',
        'use_new_vbrmap': '1',
        'secure': '1',
      });
      final first = await setup.site.resolvePlayUrls(detail: detail, quality: qualities.first);
      expect(setup.http.requests, hasLength(before + 1), reason: 'the answer already holds the selected tier');
      expect(first.appliedQualityData, 'original');
      expect(first.lines.map((line) => (line.lineId, line.format)), [
        ('hs', StreamFormat.flv),
        ('ali', StreamFormat.flv),
      ]);
      expect(first.lines.first.headers['referer'], 'https://cc.163.com/341438909/');
      expect(first.lines.first.lease!.expiresAt!.difference(_issued).inSeconds, inInclusiveRange(290, 300));
      final again = await setup.site.resolvePlayUrls(detail: detail, quality: qualities.first);
      expect(again.appliedQualityData, 'original');
      expect(setup.http.requests.last.url.queryParameters['vbrname'], 'original', reason: 'used once');
      final high = await setup.site.resolvePlayUrls(detail: detail, quality: qualities[2]);
      expect((high.appliedQualityData, high.lines.single.lineId), ('high', 'ali'));
      expect(Uri.parse(high.urls.single).path, endsWith('tc2.flv'));
      expect(setup.http.requests, hasLength(before + 3));
    });

    test('the qualities answer serves only its own tier, and only while fresh', () async {
      var now = _issued;
      final setup = _setup(
        ['S06-play-default', 'S06-play-high'],
        extra: [
          _recorded('S06-play-default', _playUrl('341438909', '&vbrname=original')),
          _recorded('S06-play-default', _playUrl('1', '&vbrname=original')),
        ],
        now: () => now,
      );
      const original = LivePlayQuality(quality: '原画', id: 'original', data: 'original');
      await setup.site.getPlayQualities(detail: _room('341438909'));
      await setup.site.resolvePlayUrls(
        detail: _room('341438909'),
        quality: const LivePlayQuality(quality: '高清', id: 'high', data: 'high'),
      );
      await setup.site.resolvePlayUrls(detail: _room('341438909'), quality: original);
      expect(
        [for (final request in setup.http.requests) request.url.queryParameters['vbrname']],
        [null, 'high', 'original'],
        reason: 'another tier drops the answer',
      );
      await setup.site.getPlayQualities(detail: _room('341438909'));
      now = _issued.add(CcSite.qualityAnswerReuse + const Duration(seconds: 1));
      await setup.site.resolvePlayUrls(detail: _room('341438909'), quality: original);
      expect(setup.http.requests, hasLength(5), reason: 'too old: asked again');
      await setup.site.getPlayQualities(detail: _room('341438909'));
      await setup.site.resolvePlayUrls(detail: _room('1'), quality: original);
      expect(setup.http.requests, hasLength(7));
      await setup.site.resolvePlayUrls(detail: _room('341438909'), quality: original);
      expect(setup.http.requests, hasLength(7), reason: 'kept per room');
    });

    test('a rebroadcast plays like a live room, with its 蓝光 tiers', () async {
      final setup = _setup(['S05-lives-replay', 'S05-channel-replay', 'S06-play-replay']);
      final detail = await setup.site.getRoomDetail(roomId: '732923115');
      final qualities = await setup.site.getPlayQualities(detail: detail);
      expect(qualities.map((quality) => quality.quality), ['原画', '蓝光5M', '蓝光3M', '超清', '高清', '标清']);
      final resolution = await setup.site.resolvePlayUrls(detail: detail, quality: qualities.first);
      expect(resolution.lines.map((line) => line.lineId), ['hs', 'ali']);
      expect(setup.http.requests, hasLength(3));
    });

    test("when video_play_url fails otherwise, a room with its tier list falls back to 3.x's", () async {
      for (final answer in [
        _synthetic(_playUrl('341438909'), '', status: 502),
        _synthetic(_playUrl('341438909'), '<html>'),
        _synthetic(_playUrl('341438909'), '{"code":"x"}'),
      ]) {
        final setup = _setup(['S05-lives-live', 'S05-channel-live'], extra: [answer]);
        final detail = await setup.site.getRoomDetail(roomId: '341438909');
        final qualities = await setup.site.getPlayQualities(detail: detail);
        expect(qualities.map((quality) => quality.quality), ['原画', '高清', '标准', '低清']);
        final before = setup.http.requests.length;
        final resolution = await setup.site.resolvePlayUrls(detail: detail, quality: qualities[1]);
        expect(resolution.urls, qualities[1].data);
        expect(resolution.appliedQualityData, 'high');
        expect(resolution.lines.first.headers['referer'], 'https://cc.163.com/341438909/');
        expect(await setup.site.getPlayUrls(detail: detail, quality: qualities.last), qualities.last.data);
        expect(setup.http.requests, hasLength(before), reason: "3.x's URLs need no request");
      }
    });

    test('an anchor not broadcasting is StreamUnavailable, without the fallback', () async {
      final setup = _setup(
        ['S05-lives-live', 'S05-channel-live'],
        extra: [_synthetic(_playUrl('341438909'), Fixture.load('cc', 'S06-play-offline').body, status: 410)],
      );
      final detail = await setup.site.getRoomDetail(roomId: '341438909');
      await expectLater(setup.site.getPlayQualities(detail: detail), throwsA(isA<StreamUnavailable>()));
      final offline = _setup(['S06-play-offline']);
      await expectLater(
        offline.site.getPlayQualities(detail: _room('376267758').copyWith(data: const CcRoomData())),
        throwsA(isA<StreamUnavailable>()),
      );
      final down = _setup([], extra: [_synthetic(_playUrl('341438909'), '', status: 502)]);
      await expectLater(down.site.getPlayQualities(detail: _room('341438909')), throwsA(isA<NetworkFailure>()));
    });

    test('a card without a detail asks video_play_url too', () async {
      final setup = _setup(['S06-play-default']);
      final qualities = await setup.site.getPlayQualities(detail: _room('341438909'));
      expect(qualities.map((quality) => quality.id), ['original', 'ultra', 'high', 'standard']);
      expect(setup.http.requests.single.url.path, '$_play/341438909');
    });

    test('lines of a tier: asked for by vbrname, both CDNs of one answer, headers and leases', () async {
      final setup = _setup([], extra: [_recorded('S06-play-default', _playUrl('341438909', '&vbrname=original'))]);
      final resolution = await setup.site.resolvePlayUrls(
        detail: _room('341438909'),
        quality: const LivePlayQuality(quality: '原画', id: 'original', data: 'original'),
      );
      expect(setup.http.requests, hasLength(1), reason: 'the answer covers every CDN of cdn_list');
      expect(resolution.lines.map((line) => line.lineId), ['hs', 'ali']);
      expect(resolution.appliedQualityData, 'original');
      expect(resolution.lines.first.headers['referer'], 'https://cc.163.com/341438909/');
      expect(resolution.lines.first.lease!.expiresAt!.difference(_issued).inSeconds, inInclusiveRange(290, 300));
    });

    test('high: the tier the server confirms, on the one CDN it offers', () async {
      final setup = _setup(['S06-play-high']);
      final urls = await setup.site.getPlayUrls(
        detail: _room('341438909'),
        quality: const LivePlayQuality(quality: '高清', id: 'high', data: 'high'),
      );
      expect(urls, hasLength(1));
      expect(Uri.parse(urls.single).host, startsWith('ali'));
      expect(setup.http.requests.single.url.queryParameters['vbrname'], 'high');
    });

    test('a CDN of cdn_list the answer left out is asked for once; a failing one leaves the rest', () async {
      ReplaySample hsOnly() => _recorded(
        'S06-play-default',
        _playUrl('341438909', '&vbrname=original'),
        edit: (root) => root..remove('bakvideourl'),
      );
      final setup = _setup(['S06-play-ali'], extra: [hsOnly()]);
      const original = LivePlayQuality(quality: '原画', id: 'original', data: 'original');
      final resolution = await setup.site.resolvePlayUrlsRaw(detail: _room('341438909'), quality: original);
      expect(resolution.lines.map((line) => line.lineId), ['hs', 'ali']);
      expect(setup.http.requests.last.url.queryParameters['cdn'], 'ali');
      final failing = _setup(
        [],
        extra: [hsOnly(), _synthetic(_playUrl('341438909', '&vbrname=original&cdn=ali'), '', status: 502)],
      );
      final rest = await failing.site.resolvePlayUrlsRaw(detail: _room('341438909'), quality: original);
      expect(rest.lines.map((line) => line.lineId), ['hs']);
    });

    test('renewal and recovery get fresh URLs: every resolution asks again (REG-CC-005)', () async {
      final setup = _setup(['S06-play-high']);
      const high = LivePlayQuality(quality: '高清', id: 'high', data: 'high');
      await setup.site.resolvePlayUrls(detail: _room('341438909'), quality: high);
      await setup.site.resolvePlayUrlsForRecovery(detail: _room('341438909'), quality: high);
      expect(_paths(setup.http), ['$_play/341438909', '$_play/341438909']);
    });

    test('a 3.x quality without URLs is StreamUnavailable', () async {
      final setup = _setup([]);
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: _room('1'),
          quality: const LivePlayQuality(quality: '原画', id: 'original', data: <String>[]),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
    });
  });

  group('links', () {
    final site = _setup([]).site;

    test('cc.163.com rooms (3.x), the mobile page and the Dashen player; only numeric ids', () {
      // 3.x test/live_url_tool_parser_test.dart.
      expect(site.roomIdFromUrl('https://cc.163.com/123?source=share'), '123');
      expect(site.roomIdFromUrl('HTTPS://CC.163.COM/732923115/'), '732923115');
      expect(site.roomIdFromUrl('https://h5.cc.163.com/cc/732923115?rid=1'), '732923115');
      expect(site.roomIdFromUrl('https://ds.163.com/glive/?ccid=732923115'), '732923115');
      for (final url in [
        // 3.x's manual-link rule took any word here.
        'https://cc.163.com/channel123/',
        'https://cc.163.com/n/ds_category/3/',
        'https://cc.163.com/search/all/?query=x',
        'https://cc.163.com/0/',
        'https://cc.163.com/',
        'https://h5.cc.163.com/cc/',
        'https://ds.163.com/glive/',
        'https://ds.163.com/?ccid=1',
        'https://cc.163.com.evil.test/123',
        'ftp://cc.163.com/123',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(site.roomIdFromUrl('https://cc.163.com/000123/'), '123');
      expect(site.needsResolving('https://cc.163.com/123'), isFalse);
    });

    test('share texts resolve without a request', () async {
      final http = ReplayHttp(const []);
      final parser = LinkParser(SiteRegistry({'cc': () => CcSite(http)}), http);
      expect(await parser.parse('看这里 https://cc.163.com/732923115/?from=search 了'), const RoomLink('cc', '732923115'));
      expect(parser.containsSupportedLink('https://ds.163.com/glive/?ccid=732923115'), isTrue);
      expect(parser.containsSupportedLink('https://cc.163.com/n/ds_category/3/'), isFalse);
      expect(http.requests, isEmpty);
    });
  });
}
