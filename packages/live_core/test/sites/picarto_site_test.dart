// PicartoSite over the recorded responses (ReplayHttp): the requests 3.x
// made (queries, headers), the catalog and directory pages, room depths and
// their request counts, streams from room entry and recovery, cancellation,
// links and error mapping. Several cases are 3.x's own (legacy
// test/picarto_adapter_test.dart).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/picarto';
const _api = 'https://ptvintern.picarto.tv';
const _detailPath = '/api/channel/detail';

Map<String, dynamic> _legacy(String name) => Fixture.load('picarto', name).legacy as Map<String, dynamic>;

/// 3.x's request of a sample (expected.json → `request`).
Map<String, dynamic> _legacyRequest(String name) => _legacy(name)['request'] as Map<String, dynamic>;

ReplaySample _synthetic(String url, Object body, {int status = 200}) => ReplaySample(
  method: 'GET',
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

typedef _Setup = ({PicartoSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: PicartoSite(http), http: http);
}

/// Answers each request with the next of [answers] (a [TransportReason]
/// throws, a function is called with the request), recording the requests.
/// The public API, which room entry asks for the start of a live broadcast
/// beside the master playlist, is answered with [publicApi] (by default
/// "Channel does not exist") and takes nothing from [answers].
final class _Scripted implements LiveHttp {
  new(this.answers, {this.publicApi});

  final List<Object> answers;
  final Object? publicApi;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    var next = request.url.host == PicartoApi.publicApiHost
        ? publicApi ?? _answer('"Channel does not exist"', status: 404)
        : answers.removeAt(0);
    if (next is Future<Object> Function(LiveRequest)) next = await next(request);
    if (next is TransportReason) throw TransportFailure('picarto', next, 'scripted');
    final sample = next as ReplaySample;
    return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

// 3.x's synthetic answers (legacy test/picarto_adapter_test.dart).

const _masterText =
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=3661056,RESOLUTION=1280x720,FRAME-RATE=60,CODECS="avc1.640020,mp4a.40.2"\n'
    'variant.m3u8\n';

/// The master playlist of [_detail].
final Uri _masterUri = Uri.parse('https://edge1-eu-west.picarto.tv/stream/hls/golive+Artist/index.m3u8');

Map<String, dynamic> _channel({String name = 'Artist', bool online = true}) => {
  'id': 15237,
  'name': name,
  'title': 'Drawing',
  'online': online,
  'private': false,
  'adult': false,
  'viewers': 15,
  'total_views': 95434,
  'categories': [
    {'id': 10, 'name': 'Comic'},
  ],
};

Map<String, dynamic> _detail({String name = 'Artist', bool online = true, String origin = 'edge1-eu-west'}) => {
  'channel': _channel(name: name, online: online),
  'getLoadBalancerUrl': {'origin': origin},
  'getMultiStreams': {
    'streams': [
      {'channelId': 999, 'stream_name': 'golive+Other'},
      {'channelId': 15237, 'stream_name': 'golive+$name'},
    ],
  },
};

ReplaySample _answer(Object body, {int status = 200}) => _synthetic('https://scripted.invalid/', body, status: status);

void main() {
  test("the site has 3.x's abilities, and no danmaku yet (3.x had none; M5)", () {
    final site = _setup([]).site;
    expect(site.id, SiteIds.picarto);
    expect(site.name, 'Picarto');
    expect(site, isA<LiveSiteRecordRoomResolver>());
    expect(site, isA<LiveSiteRoomRefresher>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isA<LiveSiteDirectoryPager>());
    expect(site, isA<LiveCancellableSearch>());
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LiveSiteLinks>());
    expect(site.getDanmaku(), isA<EmptyDanmaku>());
  });

  group('catalog and directory', () {
    test("the catalog: 3.x's request and category, page 1 only", () async {
      final setup = _setup(['S01-categories']);
      final categories = await setup.site.getCategories(1, 30);
      final legacy = ((_legacy('S01-categories')['getCategores'] as List).single as Map).cast<String, dynamic>();
      final category = categories.single;
      expect((category.id, category.name), ('picarto', 'Picarto'));
      expect(category.children.map((area) => area.areaId), [
        for (final area in legacy['children'] as List) (area as Map)['areaId'],
      ]);
      final request = setup.http.requests.single;
      expect(request.url, Uri.parse(_legacyRequest('S01-categories')['url'] as String));
      expect(request.site, 'picarto');
      expect(request.headers, PicartoApi.headers);
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(setup.http.requests, hasLength(1), reason: 'no request for page 2 (3.x)');
    });

    test("recommendations page by page with 3.x's query and headers", () async {
      final setup = _setup(['S02-explore-p1', 'S02-explore-last', 'S02-explore-beyond']);
      for (final (name, page) in [('S02-explore-p1', 1), ('S02-explore-last', 3), ('S02-explore-beyond', 4)]) {
        final before = setup.http.requests.length;
        final result = await setup.site.getDirectoryPage(page: page);
        final legacy = _legacy(name);
        expect(result.rooms.map((room) => room.roomId), [
          for (final room in legacy['rooms'] as List) (room as Map)['roomId'],
        ]);
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        final request = setup.http.requests[before];
        expect(request.url.queryParameters, Uri.parse(_legacyRequest(name)['url'] as String).queryParameters);
        for (final MapEntry(:key, :value) in (_legacyRequest(name)['headers'] as Map<String, dynamic>).entries) {
          expect(request.headers[key.toLowerCase()], value, reason: "3.x's $key");
        }
        expect(request.headers['user-agent'], PicartoApi.userAgent);
      }
    });

    test('the public directory area, getRecommendRooms and getCategoryRooms give the same page (3.x)', () async {
      final setup = _setup(['S02-explore-p1']);
      final legacy = _legacy('S02-explore-p1');
      final viaArea = await setup.site.getDirectoryPage(category: PicartoApi.publicDirectory);
      expect(viaArea.rooms.map((room) => room.roomId), (legacy['publicDirectory'] as Map)['rooms']);
      expect((await setup.site.getRecommendRooms()).map((room) => room.roomId), legacy['getRecommendRooms']);
      expect(
        (await setup.site.getCategoryRooms(PicartoApi.publicDirectory)).map((room) => room.roomId),
        legacy['getCategoryRooms'],
      );
      expect(setup.http.requests.map((request) => request.url.queryParameters['first']).toSet(), {'30'});
    });

    test("a category page: 3.x's filters, the channels of the category", () async {
      final setup = _setup(['S02-explore-category']);
      const furry = LiveArea(
        platform: 'picarto',
        areaType: 'category',
        typeName: 'Picarto',
        areaId: '8',
        areaName: 'Furry',
      );
      final page = await setup.site.getDirectoryPage(category: furry);
      final legacy = _legacy('S02-explore-category');
      expect(page.rooms.map((room) => room.roomId), legacy['getCategoryRooms']);
      expect(page.hasMore, isFalse);
      final query = setup.http.requests.single.url.queryParameters;
      expect(query, Uri.parse(_legacyRequest('S02-explore-category')['url'] as String).queryParameters);
      expect(query['filter_params[categories]'], '8: true');
      expect(query['filter_params[languages]'], '');
      expect((await setup.site.getCategoryRooms(furry)).map((room) => room.roomId), legacy['getCategoryRooms']);
    });

    test('page sizes of the list calls are sent, limited to 1–60', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic(
            '$_api/api/explore?first=60&page=2&filter_params%5Badult%5D=false&order_by%5Bfield%5D=viewers'
            '&order_by%5Border%5D=DESC&type=stream',
            {'current_page': 2, 'last_page': 2, 'per_page': 60, 'total': 0, 'data': <Object>[]},
          ),
          _synthetic(
            '$_api/api/explore?first=1&page=1&filter_params%5Badult%5D=false&order_by%5Bfield%5D=viewers'
            '&order_by%5Border%5D=DESC&type=stream',
            {'current_page': 1, 'last_page': 1, 'per_page': 1, 'total': 0, 'data': <Object>[]},
          ),
        ],
      );
      expect(await setup.site.getRecommendRooms(page: 2, pageSize: 999), isEmpty);
      expect(await setup.site.getRecommendRooms(page: 0, pageSize: 0), isEmpty);
    });

    test('an area that is no Picarto category fails before any request (3.x)', () async {
      final setup = _setup([]);
      for (final area in const [
        LiveArea(platform: 'other', areaType: 'category', areaId: '10'),
        LiveArea(platform: 'picarto', areaType: 'directory', areaId: '10'),
        LiveArea(platform: 'picarto', areaType: 'category', areaId: '010'),
        LiveArea(platform: 'picarto', areaType: 'category', areaId: 'abc'),
        LiveArea(platform: 'other', areaId: 'live'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: '$area');
      }
      expect(setup.http.requests, isEmpty);
    });

    test('a category page listing another category is ApiChanged after one request (3.x)', () async {
      final http = _Scripted([
        _answer({
          'current_page': 1,
          'last_page': 1,
          'per_page': 30,
          'total': 1,
          'data': [_channel()],
        }),
      ]);
      await expectLater(
        PicartoSite(http).getDirectoryPage(
          category: const LiveArea(platform: 'picarto', areaType: 'category', areaId: '33'),
        ),
        throwsA(isA<ApiChanged>()),
      );
      expect(http.requests, hasLength(1));
    });
  });

  group('search', () {
    test("3.x's request (20 a page from the search page); a blank keyword sends nothing", () async {
      final setup = _setup(['S03-search', 'S03-search-empty']);
      final rooms = await setup.site.searchRooms(' art ', pageSize: 20);
      expect(rooms.map((room) => room.roomId), [
        for (final room in _legacy('S03-search')['rooms'] as List) (room as Map)['roomId'],
      ]);
      expect(setup.http.requests.single.url, Uri.parse(_legacyRequest('S03-search')['url'] as String));
      expect(await setup.site.searchRooms('zxqvnoresultfixture', pageSize: 20), isEmpty);
      expect(await setup.site.searchRooms('   '), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });

    test('the page size is limited to 1–60 and the keyword to 100 characters', () async {
      final keyword = 'k' * 150;
      final setup = _setup(
        [],
        extra: [
          _synthetic('$_api/api/search?first=60&page=3&q=${'k' * 100}&type=searchProfiles&tag_search=false', {
            'searchProfiles': {'count': 0, 'data': <Object>[]},
          }),
        ],
      );
      expect(await setup.site.searchRooms(keyword, page: 3, pageSize: 500), isEmpty);
    });

    test('the cancel token reaches the transport, and a cancelled search stays cancelled (3.x)', () async {
      final token = CancelToken();
      final http = _Scripted([
        _answer({
          'searchProfiles': {'count': 0, 'data': <Object>[]},
        }),
        TransportReason.cancelled,
      ]);
      final site = PicartoSite(http);
      expect(await site.searchRoomsCancellable('artist', cancel: token), isEmpty);
      expect(http.requests.single.cancel, same(token));
      token.cancel();
      await expectLater(
        site.searchRoomsWithCancellation('artist', cancel: token),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      await expectLater(
        site.searchRoomsCancellable('artist', cancel: token),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
    });

    test('a directory page forwards its cancel token too', () async {
      final token = CancelToken();
      final http = _Scripted([TransportReason.cancelled]);
      await expectLater(PicartoSite(http).getDirectoryPage(cancel: token), throwsA(isA<TransportFailure>()));
      expect(http.requests.single.cancel, same(token));
    });
  });

  group('rooms', () {
    test('refresh: the detail only, one request, the room 3.x refreshed', () async {
      final setup = _setup(['S04-detail-live']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: ' allatir ');
      final legacy = _legacy('S04-detail-live');
      expect(setup.http.requests.single.url.toString(), _legacyRequest('S04-detail-live')['url']);
      expect(legacy['refreshRequests'], 1);
      expect(room.roomId, 'allatir');
      expect(room.isLiveNow, isTrue);
      expect(room.data, isNull);
      expect(room.danmakuData, isNull);
      expect(room.onlineViewers, (legacy['getRoomDetailForRefresh'] as Map)['onlineViewers']);
      expect(room.restriction, LiveRestriction.none, reason: 'the detail says it is not private');
      expect(room.startedAt, isNull, reason: 'no start time without another request');
      expect(await setup.site.getLiveStatus(roomId: 'allatir'), isTrue);
    });

    test("room entry: 3.x's two requests and the start of the broadcast, the stream, danmaku arguments", () async {
      final setup = _setup(['S04-detail-live', 'S05-master', 'S08-channel-live']);
      final room = await setup.site.getRoomDetail(roomId: 'allatir');
      final urls = [for (final request in setup.http.requests) request.url.toString()];
      final legacy = (_legacy('S04-detail-live')['roomEntryRequests'] as List).cast<String>();
      expect(urls.first, legacy.first, reason: 'the detail first');
      expect(urls.skip(1).toSet(), {legacy.last, 'https://api.picarto.tv/api/v1/channel/name/allatir'});
      expect(setup.http.requests.every((request) => request.headers['referer'] == 'https://picarto.tv/'), isTrue);
      final data = room.data! as PicartoRoomData;
      expect((data.name, data.channelId), ('allatir', 942670));
      expect(data.master.host, 'edge1-eu-west.picarto.tv');
      expect(data.qualities.map((quality) => quality.quality), ['720p 60fps']);
      final args = room.danmakuData! as PicartoDanmakuArgs;
      expect((args.channelName, args.channelId), ('allatir', 942670));
      expect(room.startedAt, DateTime.utc(2026, 9, 28, 16, 12, 10));
      expect(room.restriction, LiveRestriction.none);
    });

    test('room entry stands without the start of the broadcast when the public API fails', () async {
      for (final failure in <Object>[
        TransportReason.timeout,
        TransportReason.cancelled,
        _answer('bad gateway', status: 502),
        _answer('<html>'),
        _answer({'name': 'Artist', 'online': false, 'last_live': '2026-09-28 16:12:10'}),
      ]) {
        final http = _Scripted([_answer(_detail()), _answer(_masterText)], publicApi: failure);
        final room = await PicartoSite(http).getRoomDetail(roomId: 'Artist');
        expect(room.startedAt, isNull, reason: '$failure');
        expect(room.data, isA<PicartoRoomData>(), reason: '$failure');
        expect(http.requests.map((request) => request.url.host), contains(PicartoApi.publicApiHost));
      }
    });

    test('recording: the stream too (3.x used room entry) and the danmaku arguments (E05.4), no start', () async {
      final setup = _setup(['S04-detail-live', 'S05-master']);
      final room = await setup.site.getRoomDetailForRecording(roomId: 'allatir');
      expect(room.data, isA<PicartoRoomData>());
      expect((room.danmakuData! as PicartoDanmakuArgs).channelName, 'allatir');
      expect(room.startedAt, isNull);
      expect(setup.http.requests, hasLength(2));
    });

    test('the follow refresh of a live channel without its stream fields succeeds (11-2)', () async {
      final http = _Scripted([
        _answer({..._detail(), 'getLoadBalancerUrl': null}),
        _answer({..._detail(), 'getLoadBalancerUrl': null}),
      ]);
      final site = PicartoSite(http);
      final room = await site.getRoomDetailForRefresh(roomId: 'Artist');
      expect((room.isLiveNow, room.title, room.onlineViewers), (true, 'Drawing', '15'));
      expect(await site.getLiveStatus(roomId: 'Artist'), isTrue);
      expect(http.requests, hasLength(2), reason: 'one request each');
      // Room entry needs the stream: 3.x's error there.
      final entry = _Scripted([
        _answer({..._detail(), 'getLoadBalancerUrl': null}),
      ]);
      await expectLater(PicartoSite(entry).getRoomDetail(roomId: 'Artist'), throwsA(isA<ApiChanged>()));
    });

    test('a private channel: shown live and marked, no stream requested, playing names the reason (11-9)', () async {
      final private = {
        ..._detail(),
        'channel': {..._channel(), 'private': true},
      };
      final http = _Scripted([_answer(private), _answer(private), _answer(private), _answer(private)]);
      final site = PicartoSite(http);
      final refreshed = await site.getRoomDetailForRefresh(roomId: 'Artist');
      expect((refreshed.isLiveNow, refreshed.restriction), (true, LiveRestriction.private));
      final entered = await site.getRoomDetail(roomId: 'Artist');
      expect((entered.isLiveNow, entered.restriction, entered.data), (true, LiveRestriction.private, null));
      expect(entered.danmakuData, isA<PicartoDanmakuArgs>());
      expect(http.requests.map((request) => request.url.host), [
        'ptvintern.picarto.tv',
        'ptvintern.picarto.tv',
        PicartoApi.publicApiHost,
      ], reason: 'no master playlist');
      await expectLater(
        site.getPlayQualities(detail: entered),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('private'))),
      );
      await expectLater(
        site.resolvePlayUrlsForRecovery(
          detail: entered,
          quality: const LivePlayQuality(quality: '720p 60fps', id: 'x'),
        ),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('private'))),
      );
      expect(http.requests.where((request) => request.url.host != 'ptvintern.picarto.tv'), hasLength(1));
    });

    test('offline: one request at every depth, no stream, no qualities without a request', () async {
      final setup = _setup(['S04-detail-offline']);
      final entered = await setup.site.getRoomDetail(roomId: 'Kaiyote');
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'Kaiyote');
      final recording = await setup.site.getRoomDetailForRecording(roomId: 'Kaiyote');
      for (final room in [entered, refreshed, recording]) {
        expect(room.effectiveLiveStatus, LiveStatus.offline);
        expect(room.data, isNull);
      }
      expect(entered.danmakuData, isA<PicartoDanmakuArgs>(), reason: 'the chat of an offline channel is open');
      expect(setup.http.requests, hasLength(3));
      await expectLater(setup.site.getPlayQualities(detail: entered), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(3), reason: '3.x listed no quality without a request');
      expect(await setup.site.getLiveStatus(roomId: 'Kaiyote'), isFalse);
    });

    test('an unknown channel is NotFound at every depth (3.x: a schema error)', () async {
      final setup = _setup(['S04-detail-notfound']);
      for (final call in [
        setup.site.getRoomDetail,
        setup.site.getRoomDetailForRefresh,
        setup.site.getRoomDetailForRecording,
      ]) {
        await expectLater(call(roomId: 'zxqvnochannelfixture'), throwsA(isA<NotFound>()));
      }
      await expectLater(setup.site.getLiveStatus(roomId: 'zxqvnochannelfixture'), throwsA(isA<NotFound>()));
    });

    test('a room id that is no channel name is NotFound without a request (3.x refused it too)', () async {
      final setup = _setup([]);
      for (final id in ['', 'explore', 'a-b', 'a/b', 'x' * 51]) {
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
    });

    test("a room asked for in another spelling is the platform's, the followed one (3.x)", () async {
      final offline = ReplaySample.load('$_root/S04-detail-offline');
      final setup = _setup(
        [],
        extra: [
          ReplaySample(method: 'GET', url: Uri.parse('$_api$_detailPath/kaiyote'), status: 200, bytes: offline.bytes),
        ],
      );
      // 3.x stored the follow under the platform's spelling.
      final followed = LiveRoom.fromJson(
        _legacy('S04-detail-offline')['getRoomDetailForRefresh'] as Map<String, Object?>,
      );
      expect(followed.roomId, 'Kaiyote');
      for (final call in [
        setup.site.getRoomDetail,
        setup.site.getRoomDetailForRefresh,
        setup.site.getRoomDetailForRecording,
      ]) {
        final room = await call(roomId: 'kaiyote');
        expect(room.roomId, 'Kaiyote');
        expect(room.hasSameIdentity(followed), isTrue, reason: 'the page shows it followed; no second follow');
      }
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'kaiyote');
      final merged = followed.copyWith(title: 'old').mergeFrom(refreshed);
      expect(merged.cover, refreshed.cover, reason: 'the refresh merges into the follow');
      expect(merged.cover, isNotEmpty);
      // X-2: Picarto's default title is a placeholder; it no longer replaces
      // the stored one (3.x: "My Channel Title").
      expect(merged.title, 'old');
      expect(setup.http.requests.map((request) => request.url.path).toSet(), {'$_detailPath/kaiyote'});

      final live = ReplaySample.load('$_root/S04-detail-live');
      final entry = _setup(
        ['S05-master', 'S08-channel-live'],
        extra: [
          ReplaySample(method: 'GET', url: Uri.parse('$_api$_detailPath/ALLATIR'), status: 200, bytes: live.bytes),
        ],
      );
      final room = await entry.site.getRoomDetail(roomId: 'ALLATIR');
      expect(room.roomId, 'allatir');
      final data = room.data! as PicartoRoomData;
      expect((data.name, data.requestedId), ('allatir', 'ALLATIR'));
      expect((room.danmakuData! as PicartoDanmakuArgs).channelName, 'allatir');
      expect(room.startedAt, isNotNull, reason: "the public API is asked with the platform's spelling");
    });

    test('rooms compare ignoring case, before the detail answers too (11-8, M2.1)', () {
      expect(SiteIds.ignoresRoomIdCase(SiteIds.picarto), isTrue);
      final followed = LiveRoom.fromJson(
        _legacy('S04-detail-offline')['getRoomDetailForRefresh'] as Map<String, Object?>,
      );
      // A lower-case link, a history entry: the platform has not answered yet.
      final fromLink = LiveRoom(
        platform: 'picarto',
        roomId: _setup([]).site.roomIdFromUrl('https://picarto.tv/kaiyote'),
      );
      expect(fromLink.roomId, 'kaiyote', reason: 'the link keeps its spelling');
      expect(fromLink.hasSameIdentity(followed), isTrue);
      expect(fromLink, followed);
      expect(fromLink.identityKey, followed.identityKey);
      // A streamer who changed the case of their name still merges.
      final renamed = LiveRoom(platform: 'picarto', roomId: 'KAIYOTE', title: 'new');
      expect(followed.mergeFrom(renamed).title, 'new');
      expect(followed.mergeFrom(renamed).roomId, 'Kaiyote', reason: 'the stored spelling stays');
    });

    test('overlapping room reads share nothing (3.x)', () async {
      final first = Completer<Object>();
      final http = _Scripted([
        (LiveRequest _) => first.future,
        _answer({'channel': _channel(name: 'Second', online: false)}),
      ]);
      final site = PicartoSite(http);
      final old = site.getRoomDetailForRefresh(roomId: 'First');
      final newer = await site.getRoomDetailForRefresh(roomId: 'Second');
      first.complete(_answer({'channel': _channel(name: 'First', online: false)}));
      expect(newer.roomId, 'Second');
      expect((await old).roomId, 'First');
    });
  });

  group('streams', () {
    test('from room entry: no new request, one line with the media headers', () async {
      final setup = _setup(['S04-detail-live', 'S05-master', 'S08-channel-live']);
      final room = await setup.site.getRoomDetail(roomId: 'allatir');
      final qualities = await setup.site.getPlayQualities(detail: room);
      final legacy = _legacy('S04-detail-live');
      expect(qualities.map((quality) => quality.id), [
        for (final quality in legacy['getPlayQualites'] as List) (quality as Map)['id'],
      ]);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.single);
      expect(resolution.urls, (legacy['getPlayUrls'] as Map).values.single);
      expect(resolution.lines.single.headers, PicartoApi.headers);
      expect(resolution.appliedQualityData, qualities.single.selectionId);
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.single), resolution.urls);
      expect(setup.http.requests, hasLength(3), reason: 'the three of room entry');
    });

    test('a room without its stream (a list card) is entered first', () async {
      final setup = _setup(['S02-explore-p1', 'S04-detail-live', 'S05-master']);
      final card = (await setup.site.getRecommendRooms()).first;
      expect(card.roomId, 'allatir');
      final qualities = await setup.site.getPlayQualities(detail: card);
      expect(qualities.single.quality, '720p 60fps');
      expect(setup.http.requests.map((request) => request.url.host), [
        'ptvintern.picarto.tv',
        'ptvintern.picarto.tv',
        'edge1-eu-west.picarto.tv',
      ]);
    });

    test('recovery reads the detail and the master again: the edge moves (REG-PICARTO-003, 3.x)', () async {
      var details = 0;
      var playlists = 0;
      Future<Object> answer(LiveRequest request) async {
        if (request.url.host == 'ptvintern.picarto.tv') return _answer(_detail(origin: 'edge${++details}'));
        playlists++;
        return _answer(_masterText);
      }

      final http = _Scripted([answer, answer, answer, answer, answer, answer]);
      final site = PicartoSite(http);
      final room = await site.getRoomDetail(roomId: 'Artist');
      final quality = (await site.getPlayQualities(detail: room)).single;
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(recovered.urls.single, contains('edge2.picarto.tv'));
      expect(recovered.lines.single.lineId, 'edge2.picarto.tv');
      expect((await site.getPlayUrls(detail: room, quality: quality)).single, contains('edge1.picarto.tv'));
      final recording = await site.getRoomDetailForRecording(roomId: 'Artist');
      final recorded = await site.resolvePlayUrls(
        detail: recording,
        quality: (await site.getPlayQualities(detail: recording)).first,
      );
      expect(recorded.urls.single, contains('edge3.picarto.tv'));
      expect(recorded.appliedQualityData, quality.selectionId, reason: 'the profile id survives the edge');
      expect((details, playlists), (3, 3));
      expect(
        http.requests.where((request) => request.url.host == PicartoApi.publicApiHost),
        hasLength(1),
        reason: 'only room entry asks for the start; recovery and recording do not',
      );
    });

    test('recovery after a profile change plays the best quality and reports it (11-1; 3.x failed)', () async {
      const hd =
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60,CODECS="avc1.64002a,mp4a.40.2"\n'
          'hd.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,FRAME-RATE=30,CODECS="avc1.64001f,mp4a.40.2"\n'
          'sd.m3u8\n';
      final http = _Scripted([_answer(_detail()), _answer(_masterText), _answer(_detail()), _answer(hd)]);
      final site = PicartoSite(http);
      final room = await site.getRoomDetail(roomId: 'Artist');
      final old = (await site.getPlayQualities(detail: room)).single;
      expect(old.quality, '720p 60fps');
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: old);
      expect(recovered.urls.single, endsWith('/hd.m3u8'), reason: 'the best of the new playlist');
      expect(recovered.appliedQualityData, isNot(old.selectionId));
      final renewed = PicartoApi.qualities(hd, master: _masterUri);
      expect(recovered.appliedQualityData, renewed.first.selectionId, reason: 'the quality played, for M7 to show');
      expect(renewed.first.quality, '1080p 60fps');
      // F.5a: the quality played is named, so the player shows "1080p 60fps"
      // instead of the old name marked unconfirmed.
      expect(recovered.appliedQuality?.quality, '1080p 60fps');
      expect(recovered.appliedQuality?.selectionId, recovered.appliedQualityData);
      final shown = resolveAppliedPlayQuality(qualities: [old], requested: old, resolution: recovered);
      expect((shown.quality, shown.isPlaybackUnconfirmed), ('1080p 60fps', false));
      // With the room's own playlist a quality it lacks is still the caller's
      // mistake (3.x: quality unavailable).
      await expectLater(
        site.getPlayUrls(
          detail: room,
          quality: const LivePlayQuality(id: 'missing', quality: 'fake'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a list card whose quality is gone by the time it plays gets the best one too (11-1)', () async {
      final http = _Scripted([_answer(_detail()), _answer(_masterText)]);
      final card = LiveRoom(platform: 'picarto', roomId: 'Artist', liveStatus: LiveStatus.live);
      final resolution = await PicartoSite(http).resolvePlayUrls(
        detail: card,
        quality: const LivePlayQuality(id: 'gone', quality: '1080p 60fps'),
      );
      expect(resolution.urls.single, endsWith('/variant.m3u8'));
      expect(resolution.appliedQualityData, PicartoApi.qualities(_masterText, master: _masterUri).single.selectionId);
      expect(resolution.appliedQuality?.quality, PicartoApi.qualities(_masterText, master: _masterUri).single.quality);
    });

    test('a quality the playlist no longer has is StreamUnavailable (3.x: quality unavailable)', () async {
      final setup = _setup(['S04-detail-live', 'S05-master', 'S08-channel-live']);
      final room = await setup.site.getRoomDetail(roomId: 'allatir');
      await expectLater(
        setup.site.getPlayUrls(
          detail: room,
          quality: const LivePlayQuality(id: 'missing', quality: 'fake'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a channel that went offline or whose master is gone has no stream', () async {
      final offline = _Scripted([
        _answer({'channel': _channel(online: false)}),
      ]);
      await expectLater(
        PicartoSite(offline).getPlayQualities(
          detail: LiveRoom(platform: 'picarto', roomId: 'Artist'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      final gone = _Scripted([_answer(_detail()), _answer('', status: 404)]);
      await expectLater(PicartoSite(gone).getRoomDetail(roomId: 'Artist'), throwsA(isA<StreamUnavailable>()));
      final broken = _Scripted([_answer(_detail()), _answer('<html>error</html>')]);
      await expectLater(PicartoSite(broken).getRoomDetail(roomId: 'Artist'), throwsA(isA<ApiChanged>()));
    });

    test('malformed metadata is ApiChanged, not an offline stop for the recorder (3.x)', () async {
      final http = _Scripted([_answer('{}')]);
      await expectLater(PicartoSite(http).getRoomDetailForRecording(roomId: 'Artist'), throwsA(isA<ApiChanged>()));
    });
  });

  group('links', () {
    test("3.x's room links: exact hosts and one channel segment", () {
      final site = _setup([]).site;
      expect(site.roomIdFromUrl('https://picarto.tv/Artist'), 'Artist');
      expect(site.roomIdFromUrl('http://www.picarto.tv/Artist/?ref=share'), 'Artist');
      expect(site.roomIdFromUrl('https://picarto.tv/search?q=art'), isNull, reason: 'legacy toolbox_link_detection');
      expect(site.roomIdFromUrl('https://picarto.tv/Artist/videos'), isNull);
      expect(site.roomIdFromUrl('https://evil.picarto.tv/Artist'), isNull);
      expect(site.needsResolving('https://picarto.tv/Artist'), isFalse);
    });

    test('a share text is parsed without a request (3.x)', () async {
      final http = ReplayHttp([]);
      final parser = LinkParser(SiteRegistry({'picarto': () => PicartoSite(http)}), http);
      for (final url in ['https://picarto.tv/Artist', 'http://www.picarto.tv/Artist/?ref=share']) {
        expect(await parser.parse('Check $url'), const RoomLink('picarto', 'Artist'), reason: url);
        expect(parser.containsSupportedLink(url), isTrue, reason: url);
      }
      expect(parser.containsSupportedLink('https://picarto.tv/search?q=art'), isFalse);
      expect(http.requests, isEmpty);
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    await expectLater(
      PicartoSite(_Scripted([TransportReason.timeout])).getRoomDetail(roomId: 'Artist'),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      PicartoSite(_Scripted([TransportReason.cancelled])).getRoomDetail(roomId: 'Artist'),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
    await expectLater(
      PicartoSite(_Scripted([_answer('bad gateway', status: 502)])).getRoomDetail(roomId: 'Artist'),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      PicartoSite(_Scripted([_answer('slow down', status: 429)])).getCategories(1, 30),
      throwsA(isA<RateLimited>()),
    );
  });
}
