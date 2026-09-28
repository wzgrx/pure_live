// ChzzkSite over the recorded CHZZK responses (ReplayHttp) and a few
// synthetic ones: the requests (URL, headers, redirects) and their counts,
// compared with the requests 3.x made (expected.json), the fixed catalog and
// the cursor directory with its page-number replay and deadline, channel
// search, room details for entry, refresh and recording, streams with their
// lines and recovery, cancellation, links through the link parser and the
// error mapping.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/chzzk';
const _live = 'af3323d30e11ae42c39d7203c7e07fa2';
const _offline = '12bba8d480ba0ffaf85656afd76fa792';
const _region = '75cbf189b3bb8f9f687d2aca0d0a382b';
const _adult = '7ce8032370ac5121dcabce7bad375ced';
const _missing = '00000000000000000000000000000000';

/// Every room sample of the live channel: its channel, live and masters.
const _liveSamples = ['S05-channel-live', 'S06-live-detail-live', 'S07-master-hls', 'S07-master-llhls'];

/// Answers every request with [answer].
final class _Scripted implements LiveHttp {
  new(this.answer);

  final FutureOr<LiveResponse> Function(LiveRequest request) answer;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return await answer(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      headers: response.headers,
      body: Stream.value(response.bytes),
      url: response.url,
      contentLength: response.bytes.length,
    );
  }

  @override
  void close() {}
}

/// Never answers; fails as cancelled once the request's token is cancelled
/// (as live_net does).
_Scripted _hanging() => _Scripted((request) async {
  await request.cancel!.whenCancelled;
  throw const TransportFailure('chzzk', TransportReason.cancelled);
});

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

String _api(Object? content, {int code = 200}) => jsonEncode({'code': code, 'message': null, 'content': content});

typedef _Setup = ({ChzzkSite site, ReplayHttp http});

/// A site over [samples] (and [extra]); the scrubbed signatures of the
/// masters and the page size are left out of matching (the recorded
/// directory page 2 and search asked for other sizes than 3.x did; the tests
/// check the sizes sent).
_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp(
    [...extra, for (final sample in samples) ReplaySample.load('$_root/$sample')],
    ignoredQuery: const {'size', 'hdnts', 'vp'},
  );
  return (site: ChzzkSite(http, now: () => Fixture.load('chzzk', 'S07-master-hls').capturedAt), http: http);
}

/// The channel answer the region and adult samples were recorded without:
/// the live's own `channel` object, as the legacy harness answered.
ReplaySample _channelFromLive(String sample, String id) {
  final live = (jsonDecode(Fixture.load('chzzk', sample).body) as Map<String, dynamic>)['content'] as Map;
  return ReplaySample(
    method: 'GET',
    url: Uri.https(ChzzkApi.apiHost, '/service/v1/channels/$id'),
    status: 200,
    bytes: utf8.encode(_api(live['channel'])),
  );
}

List<String> _paths(List<LiveRequest> requests) => [for (final request in requests) request.url.path];

Map<String, dynamic> _legacy(String sample) => Fixture.load('chzzk', sample).legacy as Map<String, dynamic>;

/// The number of requests 3.x made for [key] of [sample].
int _legacyRequests(String sample, String key) => (_legacy(sample)[key] as Map<String, dynamic>)['requests'] as int;

Object? _legacyValue(String sample, String key) => (_legacy(sample)[key] as Map<String, dynamic>)['value'];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

const _hls = 'https://livecloud.akamaized.net/chzzk/x/a_hls_playlist.m3u8?hdnts=st=1~exp=1900000000~acl=*';
const _llhls = 'https://livecloud.akamaized.net/chzzk/x/a_playlist.m3u8?hdnts=st=1~exp=1900000000~acl=*';

String _liveDetail({String? playback, Map<String, dynamic> changes = const {}}) => _api({
  'liveId': 1,
  'liveTitle': 'Title',
  'status': 'OPEN',
  'concurrentUserCount': 5,
  'cvExposure': true,
  'adult': false,
  'krOnlyViewing': false,
  'timeMachineActive': false,
  'chatChannelId': 'Chat01',
  'liveCategoryValue': 'Talk',
  'livePlaybackJson':
      playback ??
      jsonEncode({
        'media': [
          {'mediaId': 'HLS', 'protocol': 'HLS', 'path': _hls},
          {'mediaId': 'LLHLS', 'protocol': 'HLS', 'path': _llhls},
        ],
      }),
  'channel': {'channelId': _live, 'channelName': 'Name', 'channelImageUrl': 'https://nng-phinf.pstatic.net/a.png'},
  ...changes,
});

String _master(List<String> heights) => [
  '#EXTM3U',
  for (final height in heights) ...[
    '#EXT-X-STREAM-INF:BANDWIDTH=1000,CODECS="avc1.64002A",RESOLUTION=1x$height,FRAME-RATE=30.00',
    '${height}p/chunklist.m3u8',
  ],
].join('\n');

/// A live channel whose answers can be replaced one by one.
_Scripted _world({
  String Function()? channel,
  String Function()? live,
  LiveResponse Function(LiveRequest request)? master,
}) => _Scripted((request) {
  switch (request.url.path) {
    case '/service/v1/channels/$_live':
      return _response(
        request,
        channel?.call() ?? _api({'channelId': _live, 'channelName': 'Name', 'followerCount': 3, 'openLive': true}),
      );
    case '/service/v3.1/channels/$_live/live-detail':
      return _response(request, live?.call() ?? _liveDetail());
  }
  if (request.url.host == 'livecloud.akamaized.net') {
    return master?.call(request) ?? _response(request, _master(['1080', '720']));
  }
  throw StateError('unexpected ${request.url}');
});

void main() {
  test('the adapter: id, name, capabilities, directory notice', () {
    final site = ChzzkSite(ReplayHttp(const []));
    expect(site.id, 'chzzk');
    expect(site.name, 'CHZZK');
    expect(site.directoryNoticeKey, 'chzzk_directory_scope');
    expect(site, isA<LiveSiteLinks>());
    expect(site, isA<LiveSiteRoomRefresher>());
    expect(site, isA<LiveSiteRecordRoomResolver>());
    expect(site, isA<LiveSiteCursorDirectoryPager>());
    expect(site, isA<LiveDirectoryNotice>());
    expect(site, isA<LiveCancellableSearch>());
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isNot(isA<LiveSearchPaginationPolicy>()));
    expect(site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no CHZZK danmaku');
  });

  group('catalog and directory', () {
    test('the fixed catalog needs no request', () async {
      final setup = _setup(const []);
      expect((await setup.site.getCategories(1, 30)).single.children.single.areaId, 'popular');
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test("page 1: one request with 3.x's URL and headers, no redirects", () async {
      final setup = _setup(['S03-lives-p1']);
      final page = await setup.site.getDirectoryPage();
      final request = setup.http.requests.single;
      expect(request.url.toString(), 'https://api.chzzk.naver.com/service/v1/lives?size=30');
      expect(request.headers, ChzzkApi.headers);
      expect(request.followRedirects, isFalse);
      expect(request.site, 'chzzk');
      final legacy = _legacyValue('S03-lives-p1', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      expect(page.page, 1);
      expect(page.rooms.map((room) => room.roomId), (legacy['rooms'] as List).map((room) => (room as Map)['roomId']));
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, isTrue);
      expect(setup.http.requests, hasLength(_legacyRequests('S03-lives-p1', 'getDirectoryPage(1)')));
    });

    test("page 2 by cursor: one request of 31 after the cursor's live (3.x)", () async {
      final setup = _setup(['S03-lives-p2']);
      final cursor = _legacy('S03-lives-p2')['cursor'] as String;
      final page = await setup.site.getDirectoryPageAtCursor(page: 2, cursor: cursor);
      expect(setup.http.requests.single.url.queryParameters, {
        'size': '31',
        'concurrentUserCount': '2187',
        'liveId': '21334270',
      });
      final legacy = _legacyValue('S03-lives-p2', 'getDirectoryPageAtCursor(2)')! as Map<String, dynamic>;
      expect(page.page, 2);
      expect(page.rooms.map((room) => room.roomId), (legacy['rooms'] as List).map((room) => (room as Map)['roomId']));
      expect(page.nextCursor, legacy['nextCursor']);
    });

    test('page 2 by number replays page 1 (two requests, as 3.x)', () async {
      final setup = _setup(['S03-lives-p1', 'S03-lives-p2']);
      final page = await setup.site.getDirectoryPage(page: 2);
      expect(setup.http.requests, hasLength(_legacyRequests('S03-lives-p2', 'getDirectoryPage(2)')));
      expect(setup.http.requests.last.url.queryParameters['liveId'], '21334270');
      final legacy = _legacyValue('S03-lives-p2', 'getDirectoryPage(2)')! as Map<String, dynamic>;
      expect(page.rooms.map((room) => room.roomId), (legacy['rooms'] as List).map((room) => (room as Map)['roomId']));
      expect(page.page, 2);
    });

    test('recommendations and the popular area are the directory (pageSize not sent)', () async {
      final setup = _setup(['S03-lives-p1']);
      final area = ChzzkApi.categories().single.children.single;
      final recommended = await setup.site.getRecommendRooms(pageSize: 10);
      final rooms = await setup.site.getCategoryRooms(area);
      expect(recommended, hasLength(30));
      expect(rooms.map((room) => room.roomId), recommended.map((room) => room.roomId));
      expect(setup.http.requests.map((request) => request.url.query), ['size=30', 'size=30']);
      expect(_legacyRequests('S03-lives-p1', 'getRecommendRooms(1)'), 1);
    });

    test('a directory that ends before the page gives an empty last page', () async {
      final http = _Scripted(
        (request) => _response(
          request,
          _api({
            'page': null,
            'data': [
              {
                'liveId': 1,
                'liveTitle': 'Only',
                'channel': {'channelId': _live, 'channelName': 'Name'},
              },
            ],
          }),
        ),
      );
      final page = await ChzzkSite(http).getDirectoryPage(page: 3);
      expect(page.rooms, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.page, 3);
      expect(http.requests, hasLength(1));
    });

    test('caller errors are refused before any request', () async {
      final setup = _setup(const []);
      final site = setup.site;
      const foreign = LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'League_of_Legends');
      await expectLater(site.getDirectoryPage(page: 0), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPage(page: 21), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPage(category: foreign), throwsArgumentError);
      await expectLater(site.getCategoryRooms(foreign), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 0), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPageAtCursor(page: 1, cursor: '{"v":1,"l":2}'), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 2), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 2, cursor: 'not ours'), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });

    test("the page-number replay has 3.x's deadline; its request is cancelled", () async {
      final http = _hanging();
      final site = ChzzkSite(http, directoryDeadline: const Duration(milliseconds: 50));
      await expectLater(site.getDirectoryPage(), throwsA(isA<NetworkFailure>()));
      expect(http.requests.single.cancel!.isCancelled, isTrue);
    });

    test("the caller's cancellation reaches the replay's requests", () async {
      final http = _hanging();
      final cancel = CancelToken();
      final future = ChzzkSite(http).getDirectoryPage(cancel: cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await expectLater(future, _cancelled);
      final before = CancelToken()..cancel();
      await expectLater(ChzzkSite(http).getDirectoryPage(cancel: before), _cancelled);
      await expectLater(ChzzkSite(http).getDirectoryPageAtCursor(page: 1, cancel: before), _cancelled);
      expect(http.requests, hasLength(1));
    });
  });

  group('search', () {
    test("one request with 3.x's query; the recorded cards", () async {
      final setup = _setup(['S04-search-channels']);
      final rooms = await setup.site.searchRooms(' 배틀 ', pageSize: 20);
      final request = setup.http.requests.single;
      expect(request.url.path, '/service/v1/search/channels');
      expect(request.url.queryParameters, {'keyword': '배틀', 'offset': '0', 'size': '20'});
      expect(request.headers, ChzzkApi.headers);
      expect(rooms, hasLength((_legacyValue('S04-search-channels', 'searchRooms')! as List).length));
      expect(setup.http.requests, hasLength(_legacyRequests('S04-search-channels', 'searchRooms')));
      final none = _setup(['S04-search-empty']);
      expect(await none.site.searchRooms('zxqvfixturenoresult', pageSize: 20), isEmpty);
    });

    test('pages are offsets of the page size (default 30)', () async {
      final http = _Scripted((request) => _response(request, _api({'page': null, 'data': <Object?>[]})));
      final site = ChzzkSite(http);
      await site.searchRooms('a');
      await site.searchRooms('a', page: 3, pageSize: 10);
      expect(http.requests.map((request) => request.url.queryParameters), [
        {'keyword': 'a', 'offset': '0', 'size': '30'},
        {'keyword': 'a', 'offset': '20', 'size': '10'},
      ]);
    });

    test("3.x's bounds: nothing, or a caller error, without a request", () async {
      final setup = _setup(const []);
      final site = setup.site;
      expect(await site.searchRooms('a', page: 0), isEmpty);
      expect(await site.searchRooms('a', pageSize: 0), isEmpty);
      expect(await site.searchRooms('a', pageSize: 31), isEmpty);
      expect(await site.searchRooms('   '), isEmpty);
      await expectLater(site.searchRooms('a' * 101), throwsArgumentError);
      await expectLater(site.searchRooms('a', page: 40000), throwsA(isA<RangeError>()));
      expect(setup.http.requests, isEmpty);
      final http = _Scripted((request) => _response(request, _api({'data': <Object?>[]})));
      await ChzzkSite(http).searchRooms('a' * 100);
      expect(http.requests.single.url.queryParameters['keyword'], hasLength(100));
    });

    test('a cancelled search sends nothing', () async {
      final setup = _setup(const []);
      await expectLater(setup.site.searchRoomsCancellable('a', cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('rooms', () {
    test('room entry: the channel, v3.1 live-detail, then both masters (four requests, as 3.x)', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(_paths(setup.http.requests), [
        '/service/v1/channels/$_live',
        '/service/v3.1/channels/$_live/live-detail',
        Fixture.load('chzzk', 'S07-master-hls').url.path,
        Fixture.load('chzzk', 'S07-master-llhls').url.path,
      ]);
      expect(setup.http.requests.map((request) => request.headers), everyElement(ChzzkApi.headers));
      expect(setup.http.requests.map((request) => request.followRedirects), everyElement(isFalse));
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-live', 'getRoomDetail')));
      final legacy = _legacyValue('S06-live-detail-live', 'getRoomDetail')! as Map<String, dynamic>;
      expect(room.roomId, legacy['roomId']);
      expect(room.title, legacy['title']);
      expect(room.notice, legacy['notice']);
      final data = room.data! as ChzzkRoomData;
      expect(data.channelId, _live);
      expect(data.qualities.map((quality) => quality.id), ['1080p60', '720p60', '480p', '360p', '144p']);
      expect(room.danmakuData, isA<ChzzkDanmakuArgs>().having((args) => args.chatChannelId, 'chat', 'N2lpu9'));
    });

    test('REG-CHZZK-001: v3.1 only, never the v2 live-detail', () async {
      final setup = _setup(['S06-live-detail-region'], extra: [_channelFromLive('S06-live-detail-region', _region)]);
      final room = await setup.site.getRoomDetail(roomId: _region);
      expect(_paths(setup.http.requests), [
        '/service/v1/channels/$_region',
        '/service/v3.1/channels/$_region/live-detail',
      ]);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, ChzzkApi.regionNotice);
      expect(room.danmakuData, isNull, reason: 'no chatChannelId');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<RegionBlocked>()));
      expect(setup.http.requests, hasLength(2));
    });

    test('follow refresh and live state: two requests, no masters, no stream data', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-live', 'getRoomDetailForRefresh')));
      expect(room.data, isNull);
      expect(room.danmakuData, isNull);
      expect(room.isLiveNow, isTrue);
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect(setup.http.requests, hasLength(4));
      expect(_legacyRequests('S06-live-detail-live', 'getLiveStatus'), 2);
    });

    test('recording detail: the qualities as room entry, without the chat', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetailForRecording(roomId: _live);
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-live', 'getRoomDetailForRecording')));
      expect((room.data! as ChzzkRoomData).qualities, hasLength(5));
      expect(room.danmakuData, isNull);
    });

    test('an offline channel: two requests, and no stream without a request', () async {
      final setup = _setup(['S05-channel-offline', 'S06-live-detail-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-offline', 'getRoomDetail')));
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayQualities(detail: await setup.site.getRoomDetailForRefresh(roomId: _offline)),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(4));
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
    });

    test('an adult live opens; its stream needs a login', () async {
      final setup = _setup(['S06-live-detail-adult'], extra: [_channelFromLive('S06-live-detail-adult', _adult)]);
      final room = await setup.site.getRoomDetail(roomId: _adult);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, ChzzkApi.adultNotice);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<NeedsLogin>()));
      expect(setup.http.requests, hasLength(2));
    });

    test('an unknown channel is NotFound after one request; a live-detail 404 too', () async {
      final setup = _setup(['S05-channel-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(1));
      final http = _world(live: () => '');
      final site = ChzzkSite(
        _Scripted((request) {
          if (request.url.path.endsWith('/live-detail')) {
            return _response(request, jsonEncode({'code': 404, 'message': '채널이 존재하지 않습니다.'}), status: 404);
          }
          return http.answer(request);
        }),
      );
      await expectLater(site.getRoomDetailForRefresh(roomId: _live), throwsA(isA<NotFound>()));
    });

    test('an id that is not a channel id is NotFound without a request', () async {
      final setup = _setup(const []);
      for (final id in ['', 'abc', _live.toUpperCase(), '$_live/x', '../$_live']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      final http = _world();
      expect((await ChzzkSite(http).getRoomDetailForRefresh(roomId: ' $_live ')).roomId, _live);
    });

    test('a refresh merges into the room 3.x stored: the identity is the channel id', () async {
      final setup = _setup(_liveSamples);
      final stored = LiveRoom.fromJson({
        ...(_legacyValue('S06-live-detail-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>),
        'tagIds': const ['t1'],
      });
      final fresh = await setup.site.getRoomDetailForRefresh(roomId: stored.roomId);
      final merged = stored.mergeFrom(fresh);
      expect(merged.hasSameIdentity(stored), isTrue);
      expect(merged.identityKey, 'chzzk:$_live');
      expect(merged.tagIds, ['t1']);
      expect(merged.onlineViewers, fresh.onlineViewers);
    });

    test('a master that fails fails the entry, as in 3.x; the refresh is not affected', () async {
      final forbidden = _world(master: (request) => _response(request, '', status: 403));
      await expectLater(ChzzkSite(forbidden).getRoomDetail(roomId: _live), throwsA(isA<RiskControl>()));
      expect(forbidden.requests, hasLength(3), reason: 'LLHLS is not asked after HLS failed');
      final gone = _world(
        master: (request) => request.url.path.endsWith('a_playlist.m3u8')
            ? _response(request, '', status: 404)
            : _response(request, _master(['720'])),
      );
      await expectLater(ChzzkSite(gone).getRoomDetailForRecording(roomId: _live), throwsA(isA<StreamUnavailable>()));
      final unreadable = _world(master: (request) => _response(request, '<html>'));
      await expectLater(ChzzkSite(unreadable).getRoomDetail(roomId: _live), throwsA(isA<ApiChanged>()));
      expect((await ChzzkSite(unreadable).getRoomDetailForRefresh(roomId: _live)).isLiveNow, isTrue);
    });

    test('an unusable livePlaybackJson: the refresh works, the entry is ApiChanged (3.x failed both)', () async {
      final http = _world(live: () => _liveDetail(playback: '{'));
      final site = ChzzkSite(http);
      expect((await site.getRoomDetailForRefresh(roomId: _live)).isLiveNow, isTrue);
      await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<ApiChanged>()));
      expect(http.requests, hasLength(4), reason: 'no master was asked');
    });
  });

  group('streams', () {
    test('qualities and lines come from room entry, without a request', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final count = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: room);
      final legacy = (_legacyValue('S06-live-detail-live', 'getPlayQualites')! as List).cast<Map<String, dynamic>>();
      expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
      final urls = (_legacy('S06-live-detail-live')['getPlayUrls'] as Map).cast<String, dynamic>();
      for (final quality in qualities) {
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), urls[quality.id]);
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.appliedQualityData, quality.id);
        expect(resolution.lines.map((line) => line.lineId), ['HLS', 'LLHLS']);
        expect(resolution.lines.map((line) => line.headers), everyElement(ChzzkApi.mediaHeaders));
        expect(resolution.lines.map((line) => line.format), everyElement(StreamFormat.hls));
        expect(resolution.lines.map((line) => line.lease?.cutsConnection), everyElement(isTrue));
      }
      expect(setup.http.requests, hasLength(count));
    });

    test('a card without stream data (a list card, a refreshed follow) is entered first', () async {
      final setup = _setup(_liveSamples);
      final card = LiveRoom(platform: 'chzzk', roomId: _live, liveStatus: LiveStatus.live);
      expect(await setup.site.getPlayQualities(detail: card), hasLength(5));
      expect(setup.http.requests, hasLength(4));
      final follow = LiveRoom(platform: 'chzzk', roomId: _live);
      expect(await setup.site.getPlayQualities(detail: follow), hasLength(5), reason: 'state unknown');
      expect(setup.http.requests, hasLength(8));
    });

    test('an offline search card has no stream, without a request', () async {
      final setup = _setup(const []);
      final card = LiveRoom(platform: 'chzzk', roomId: _offline, liveStatus: LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayUrls(
          detail: card,
          quality: const LivePlayQuality(quality: '720p · HLS', id: '720p'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
    });

    test('recovery enters the room again (four requests, as 3.x) and keeps the quality', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final quality = (await setup.site.getPlayQualities(detail: room))[1];
      final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(setup.http.requests, hasLength(8));
      final legacy =
          ((_legacy('S06-live-detail-live')['resolvePlayUrlsForRecoveryRaw'] as Map)[quality.id] as Map)['value']
              as Map;
      expect(resolution.urls, legacy['urls']);
      expect(resolution.appliedQualityData, legacy['appliedQualityData']);
    });

    test('recovery onto a live without the quality is StreamUnavailable', () async {
      var heights = ['1080', '720'];
      final http = _world(master: (request) => _response(request, _master(heights)));
      final site = ChzzkSite(http);
      final room = await site.getRoomDetail(roomId: _live);
      final quality = (await site.getPlayQualities(detail: room)).first;
      expect(quality.id, '1080p');
      heights = ['720'];
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("another channel's data is not used; another platform's room is a caller error", () async {
      final http = _world();
      final site = ChzzkSite(http);
      final room = await site.getRoomDetail(roomId: _live);
      final stranger = LiveRoom(platform: 'chzzk', roomId: _offline, liveStatus: LiveStatus.offline, data: room.data);
      await expectLater(site.getPlayQualities(detail: stranger), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        site.getPlayQualities(
          detail: LiveRoom(platform: 'soop', roomId: _live, data: room.data),
        ),
        throwsArgumentError,
      );
      expect(http.requests, hasLength(4));
    });
  });

  group('errors', () {
    test('transport failures are NetworkFailure; a cancellation stays one', () async {
      for (final reason in [TransportReason.connect, TransportReason.timeout, TransportReason.tls]) {
        final site = ChzzkSite(_Scripted((request) => throw TransportFailure('chzzk', reason)));
        await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()), reason: '$reason');
      }
      final cancelled = ChzzkSite(
        _Scripted((request) => throw const TransportFailure('chzzk', TransportReason.cancelled)),
      );
      await expectLater(cancelled.searchRooms('a'), _cancelled);
    });

    test("statuses as 3.x's _read classed them; a code other than 200 is ApiChanged", () async {
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final site = ChzzkSite(_Scripted((request) => _response(request, '', status: status)));
        await expectLater(site.getRecommendRooms(), throwsA(matcher), reason: '$status');
      }
      final code = ChzzkSite(
        _Scripted((request) => _response(request, jsonEncode({'code': 9004, 'message': '해외 시청 불가능한 컨텐츠 입니다.'}))),
      );
      await expectLater(code.getRoomDetailForRefresh(roomId: _live), throwsA(isA<ApiChanged>()));
    });
  });

  group('links', () {
    LinkParser parser(LiveHttp http) => LinkParser(SiteRegistry({'chzzk': () => ChzzkSite(http)}), http);

    test('a live page in a share text, without a request', () async {
      final http = ReplayHttp(const []);
      expect(
        await parser(http).parse('치지직 보러 와 https://chzzk.naver.com/live/${_live.toUpperCase()}。快来'),
        const RoomLink('chzzk', _live),
      );
      expect(parser(http).containsSupportedLink('https://chzzk.naver.com/live/$_live'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('the channel page and other hosts are not rooms (3.x)', () async {
      final http = ReplayHttp(const []);
      expect(await parser(http).parse('https://chzzk.naver.com/$_live'), isNull);
      expect(await parser(http).parse('https://m.chzzk.naver.com/live/$_live'), isNull);
      expect(parser(http).containsSupportedLink('https://chzzk.naver.com/$_live'), isFalse);
      final site = ChzzkSite(http);
      expect(site.needsResolving('https://chzzk.naver.com/live/$_live'), isFalse);
      expect(site.roomIdsInShareText('https://chzzk.naver.com/live/$_live'), isEmpty);
      expect(http.requests, isEmpty);
    });
  });
}
