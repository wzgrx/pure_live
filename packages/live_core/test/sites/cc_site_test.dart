// CcSite over the recorded CC responses (ReplayHttp) and a few synthetic
// ones: the Dashen catalog, area pages and the directory pager, the
// recommendation list, search, the three-step detail, per-quality streams
// with their CDNs, links and the error mapping.
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
const _play = '/video_play_url';

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

typedef _Setup = ({CcSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: CcSite(http, now: () => _issued), http: http);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

LiveRoom _room(String ccid) => LiveRoom(roomId: ccid, platform: 'cc');

const _area = LiveArea(platform: 'cc', areaId: '9141', areaType: '1');

void main() {
  group('catalog', () {
    test('the Dashen registry and live configuration, together, with their headers (REG-CC-001)', () async {
      final setup = _setup(['S01-dashen-games', 'S01-dashen-config']);
      final categories = await setup.site.getCategories(1, 1000);
      expect(categories.map((category) => (category.id, category.name, category.children.length)), [
        ('1', '直播分类', 20),
        ('official', '官方房间/专题', 4),
      ]);
      final [games, config] = setup.http.requests;
      expect(games.method, 'GET');
      expect(games.url.queryParameters, {'gameType': 'NETEASE'});
      expect(config.method, 'POST');
      expect(jsonDecode(utf8.decode(config.body!)), {'id': CcApi.catalogConfigurationId});
      for (final request in setup.http.requests) {
        expect(request.headers['origin'], 'https://ds.163.com');
        expect(request.headers['referer'], 'https://ds.163.com/glive/');
        expect(request.headers['user-agent'], CcApi.userAgent);
        expect(request.url.host, isNot('cc.163.com'), reason: 'the old category page moved to Dashen HTML');
      }
    });

    test('a failing request fails the catalog instead of emptying it', () async {
      final setup = _setup(
        ['S01-dashen-games'],
        extra: [
          _synthetic('https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig', '', status: 503, method: 'POST'),
        ],
      );
      await expectLater(setup.site.getCategories(1, 1000), throwsA(isA<NetworkFailure>()));
      await expectLater(
        CcSite(_Failing(TransportReason.connect)).getCategories(1, 1000),
        throwsA(isA<NetworkFailure>()),
      );
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

    test('a followed area keeps its numeric identity whatever its parent', () async {
      final setup = _setup(['S02-area-page1']);
      final old = LiveArea.fromJson(const {'platform': 'cc', 'areaId': '9141', 'areaType': '2', 'areaName': 'Old'});
      expect(await setup.site.getCategoryRooms(old), hasLength(13));
    });

    test('official entries, foreign areas and bad pages are caller errors, without a request (3.x)', () async {
      final setup = _setup([]);
      for (final id in ['', '0', '../3', '3?x=y', 'official:249133']) {
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
    test('every live room, a page at a time; the popular page asks for 100', () async {
      final setup = _setup(
        ['S03-live-page1', 'S03-live-last', 'S03-live-beyond'],
        extra: [_recorded('S03-live-page1', 'https://cc.163.com/api/category/live/?format=json&start=100&size=100')],
      );
      expect(await setup.site.getRecommendRooms(), hasLength(30));
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
      expect(anchors.where((anchor) => anchor.liveStatus), hasLength(4));
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
      expect(await setup.site.getLiveStatus(roomId: '341438909'), isTrue, reason: '3.x always answered true');
    });

    test('a rebroadcast channel is live, as 3.x showed it', () async {
      final setup = _setup(['S05-lives-replay', 'S05-channel-replay']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: '732923115');
      expect(room.title, startsWith('【重播】'));
      expect(room.effectiveLiveStatus, LiveStatus.live);
    });

    test('an offline anchor: refresh and recording mark it offline with one request (REG-CC-003)', () async {
      final setup = _setup(['S05-lives-offline']);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: '376267758');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      expect(refreshed.nick, isEmpty, reason: 'the stored card keeps the rest');
      expect((await setup.site.getRoomDetailForRecording(roomId: '376267758')).isExplicitlyOfflineNow, isTrue);
      expect(await setup.site.getLiveStatus(roomId: '376267758'), isFalse);
      expect(_paths(setup.http), [_lives, _lives, _lives], reason: '3.x sent two requests and failed');
    });

    test('an offline anchor on room entry: the room page fills the room', () async {
      final setup = _setup(['S05-lives-offline', 'S05-page-offline']);
      final room = await setup.site.getRoomDetail(roomId: '376267758');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.nick, '路人7758');
      expect(_paths(setup.http), [_lives, '/376267758/']);
      expect(setup.http.requests.last.url.queryParameters, {'open': 'blizzardtv', 'from': '8382', 'platform': 'ds'});
    });

    test('a channel that ended between the two requests is offline', () async {
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

  group('streams', () {
    test("a live room plays 3.x's qualities and URLs, without a request (REG-CC-004 kept)", () async {
      final setup = _setup(['S05-lives-live', 'S05-channel-live']);
      final detail = await setup.site.getRoomDetail(roomId: '341438909');
      final before = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: detail);
      expect(qualities.map((quality) => quality.quality), ['原画', '高清', '标准', '低清']);
      final resolution = await setup.site.resolvePlayUrls(detail: detail, quality: qualities[1]);
      expect(resolution.urls, qualities[1].data);
      expect(resolution.appliedQualityData, 'high');
      expect(resolution.lines.first.headers['referer'], 'https://cc.163.com/341438909/');
      expect(await setup.site.getPlayUrls(detail: detail, quality: qualities.last), qualities.last.data);
      expect(setup.http.requests, hasLength(before));
    });

    test('a room without a tier list falls back to video_play_url; offline is StreamUnavailable', () async {
      final setup = _setup(['S06-play-default', 'S06-play-offline']);
      final qualities = await setup.site.getPlayQualities(detail: _room('341438909'));
      expect(qualities.map((quality) => quality.id), ['original', 'ultra', 'high', 'standard']);
      expect(setup.http.requests.single.url.queryParameters, {
        'src': 'webcc_h5',
        'vbrmode': '1',
        'use_new_vbrmap': '1',
        'secure': '1',
      });
      await expectLater(
        setup.site.getPlayQualities(detail: _room('376267758').copyWith(data: const CcRoomData())),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('fallback lines of a tier: asked for by vbrname, both CDNs of one answer, headers and leases', () async {
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

    test('fallback high: the tier the server confirms, on the one CDN it offers', () async {
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

    test('fallback renewal and recovery get fresh URLs: every resolution asks again (REG-CC-005)', () async {
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
