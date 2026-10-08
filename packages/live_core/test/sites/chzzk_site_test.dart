// ChzzkSite over the recorded CHZZK responses (ReplayHttp) and a few
// synthetic ones: the requests (URL, headers, redirects) and their counts,
// compared with the requests 3.x made (expected.json) where the upgrades
// (docs/specs/UPGRADES.md 20-x) leave them, the catalog of the platform's areas,
// the cursor directory with its page-number replay and deadline, channel
// search, room details for entry, refresh and recording, qualities read
// from the masters with their lines, reuse and recovery, cancellation, links
// through the link parser and the error mapping.
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

/// The four recorded `categories/live` pages.
const _categorySamples = ['S01-categories-p1', 'S01-categories-p2', 'S01-categories-p3', 'S01-categories-p4'];

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

/// When the recorded masters were issued.
DateTime get _issued => Fixture.load('chzzk', 'S07-master-hls').capturedAt;

/// A site over [samples] (and [extra]); the scrubbed signatures of the
/// masters and the page size are left out of matching (the recorded search
/// asked for another size than 3.x's default; the tests check the sizes
/// sent).
_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp(
    [...extra, for (final sample in samples) ReplaySample.load('$_root/$sample')],
    ignoredQuery: const {'size', 'hdnts', 'vp'},
  );
  return (site: ChzzkSite(http, now: () => _issued), http: http);
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
  'openDate': '2026-09-28 20:31:48',
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

/// A master of [heights]; with [expiresAt] the variants carry an Akamai
/// `hdntl` token of that expiry in their path, else they take the master's.
String _master(List<String> heights, {DateTime? expiresAt}) => [
  '#EXTM3U',
  for (final height in heights) ...[
    '#EXT-X-STREAM-INF:BANDWIDTH=1000,CODECS="avc1.64002A",RESOLUTION=1x$height,FRAME-RATE=30.00',
    if (expiresAt == null)
      '${height}p/chunklist.m3u8'
    else
      '${height}p/hdntl=exp=${expiresAt.millisecondsSinceEpoch ~/ 1000}~acl=*~hmac=x/chunklist.m3u8',
  ],
].join('\n');

bool _isMaster(LiveRequest request) => request.url.host == 'livecloud.akamaized.net';

/// A live channel whose answers can be replaced one by one.
_Scripted _world({
  String Function()? channel,
  String Function()? live,
  FutureOr<LiveResponse> Function(LiveRequest request)? master,
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
  if (_isMaster(request)) {
    return master?.call(request) ?? _response(request, _master(['1080', '720']));
  }
  throw StateError('unexpected ${request.url}');
});

/// A `categories/live` page of [ids] (GAME areas) with [next].
String _categories(List<String> ids, {Map<String, Object?>? next}) => _api({
  'size': ids.length,
  'page': next == null ? null : {'next': next, 'prev': null},
  'data': [
    for (final id in ids) {'categoryType': 'GAME', 'categoryId': id, 'categoryValue': id},
  ],
});

/// A lives page of [channels] (one live each, [liveIds] in order) with a
/// next cursor after the last.
String _lives(List<String> channels, List<int> liveIds) => _api({
  'size': channels.length,
  'page': {
    'next': {'concurrentUserCount': 1, 'liveId': liveIds.last},
    'prev': null,
  },
  'data': [
    for (final (index, channel) in channels.indexed)
      {
        'liveId': liveIds[index],
        'liveTitle': 'Live',
        'concurrentUserCount': 10 - index,
        'cvExposure': true,
        'channel': {'channelId': channel, 'channelName': 'Name'},
      },
  ],
});

String _hex(int index) => index.toRadixString(16).padLeft(32, '0');

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
    expect(site, isA<LiveQualityDiscovery>(), reason: '20-9: the qualities make requests');
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isNot(isA<LiveSearchPaginationPolicy>()));
  });

  group('catalog and directory', () {
    test("20-1: the platform's areas from four categories/live pages in turn (3.x: one area, no request)", () async {
      final setup = _setup(_categorySamples);
      final catalog = await setup.site.getCategories(1, 30);
      expect(setup.http.requests.map((request) => request.url.queryParameters), [
        for (final sample in _categorySamples) Fixture.load('chzzk', sample).url.queryParameters,
      ]);
      expect(setup.http.requests.map((request) => request.url.path), everyElement('/service/v1/categories/live'));
      expect(setup.http.requests.map((request) => request.headers), everyElement(ChzzkApi.headers));
      expect(setup.http.requests.map((request) => request.followRedirects), everyElement(isFalse));
      expect(catalog.map((category) => category.name), ['游戏', '娱乐', '其他']);
      expect(catalog.expand((category) => category.children), hasLength(194));
      expect(_legacyRequests('S03-lives-p1', 'getCategores(1)'), 0, reason: '3.x: no request');
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(await setup.site.getCategories(0, 30), isEmpty);
      expect(setup.http.requests, hasLength(4));
    });

    test('the catalog ends at a page without next; a later failing page ends it, the first fails it', () async {
      final short = _Scripted((request) => _response(request, _categories(['a', 'b'])));
      expect((await ChzzkSite(short).getCategories(1, 30)).single.children, hasLength(2));
      expect(short.requests, hasLength(1));
      final later = _Scripted(
        (request) => request.url.queryParameters.containsKey('categoryId')
            ? _response(request, '', status: 503)
            : _response(
                request,
                _categories(['a'], next: {'concurrentUserCount': 1, 'openLiveCount': 1, 'categoryId': 'a'}),
              ),
      );
      expect((await ChzzkSite(later).getCategories(1, 30)).single.children.single.areaId, 'a');
      expect(later.requests.last.url.queryParameters, {
        'size': '50',
        'concurrentUserCount': '1',
        'openLiveCount': '1',
        'categoryId': 'a',
      });
      final first = _Scripted((request) => _response(request, '', status: 503));
      await expectLater(ChzzkSite(first).getCategories(1, 30), throwsA(isA<NetworkFailure>()));
      final looping = _Scripted(
        (request) => _response(
          request,
          _categories(['a'], next: {'concurrentUserCount': 1, 'openLiveCount': 1, 'categoryId': 'a'}),
        ),
      );
      expect((await ChzzkSite(looping).getCategories(1, 30)).single.children, hasLength(1));
      expect(looping.requests, hasLength(ChzzkApi.maxCategoryPages));
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

    test("page 2 by cursor: one request of 30 after the cursor's live (20-6; 3.x asked 31)", () async {
      final setup = _setup(['S03-lives-p2']);
      final cursor = _legacy('S03-lives-p2')['cursor'] as String;
      final page = await setup.site.getDirectoryPageAtCursor(page: 2, cursor: cursor);
      expect(setup.http.requests.single.url.queryParameters, {
        'size': '30',
        'concurrentUserCount': '2187',
        'liveId': '21334270',
      });
      expect(setup.http.requests.single.url.queryParameters, Fixture.load('chzzk', 'S03-lives-p2').url.queryParameters);
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

    test("recommendations and 3.x's popular area are the site-wide list (pageSize not sent)", () async {
      final setup = _setup(['S03-lives-p1']);
      final recommended = await setup.site.getRecommendRooms(pageSize: 10);
      final rooms = await setup.site.getCategoryRooms(ChzzkApi.popularArea);
      expect(recommended, hasLength(30));
      expect(rooms.map((room) => room.roomId), recommended.map((room) => room.roomId));
      expect(setup.http.requests.map((request) => request.url.query), ['size=30', 'size=30']);
      expect(_legacyRequests('S03-lives-p1', 'getRecommendRooms(1)'), 1);
      expect(_legacyRequests('S03-lives-p1', 'getCategoryRooms(1)'), 1);
    });

    test("20-1: an area's lives by cursor and by number (S02)", () async {
      final setup = _setup(['S02-category-lives-p1', 'S02-category-lives-p2']);
      final lol = (await ChzzkSite(
        _setup(_categorySamples).http,
      ).getCategories(1, 30)).first.children.firstWhere((area) => area.areaId == 'League_of_Legends');
      final first = await setup.site.getDirectoryPageAtCursor(page: 1, category: lol);
      expect(setup.http.requests.single.url, Fixture.load('chzzk', 'S02-category-lives-p1').url);
      expect(setup.http.requests.single.headers, ChzzkApi.headers);
      expect(first.rooms, hasLength(30));
      expect(first.rooms.first.area, '리그 오브 레전드');
      final second = await setup.site.getDirectoryPageAtCursor(page: 2, cursor: first.nextCursor, category: lol);
      expect(
        setup.http.requests.last.url.queryParameters,
        Fixture.load('chzzk', 'S02-category-lives-p2').url.queryParameters,
      );
      expect(second.rooms, hasLength(30));
      final replayed = await setup.site.getCategoryRooms(lol, page: 2);
      expect(replayed.map((room) => room.roomId), second.rooms.map((room) => room.roomId));
      expect(setup.http.requests, hasLength(4));
    });

    test('20-1: an unknown area is an empty last page (S02-category-lives-empty)', () async {
      final setup = _setup(['S02-category-lives-empty']);
      const area = LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: 'No_Such_Category_Fixture');
      final page = await setup.site.getDirectoryPage(category: area);
      expect(page.rooms, isEmpty);
      expect(page.hasMore, isFalse);
      expect(await setup.site.getCategoryRooms(area, page: 3), isEmpty);
      expect(setup.http.requests, hasLength(2), reason: 'the replay stops at the empty page');
    });

    test('the page-number replay leaves out channels of its earlier pages', () async {
      final http = _Scripted(
        (request) => request.url.queryParameters.containsKey('liveId')
            ? _response(request, _lives([_hex(2), _hex(3)], [7, 6]))
            : _response(request, _lives([_hex(1), _hex(2)], [9, 8])),
      );
      final page = await ChzzkSite(http).getDirectoryPage(page: 2);
      expect(page.rooms.map((room) => room.roomId), [_hex(3)]);
      expect(page.hasMore, isTrue);
      expect(http.requests, hasLength(2));
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
      const foreign = LiveArea(platform: 'soop', areaType: 'GAME', areaId: 'League_of_Legends');
      const unsafe = LiveArea(platform: 'chzzk', areaType: 'GAME', areaId: '../lives');
      const directory = LiveArea(platform: 'chzzk', areaType: 'directory', areaId: 'public');
      await expectLater(site.getDirectoryPage(page: 0), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPage(page: 21), throwsA(isA<RangeError>()));
      for (final area in [foreign, unsafe, directory]) {
        await expectLater(site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
        await expectLater(site.getCategoryRooms(area), throwsArgumentError, reason: '$area');
        await expectLater(site.getDirectoryPageAtCursor(page: 1, category: area), throwsArgumentError);
      }
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
      expect(request.url.queryParameters, Fixture.load('chzzk', 'S04-search-channels').url.queryParameters);
      expect(request.headers, ChzzkApi.headers);
      expect(rooms, hasLength((_legacyValue('S04-search-channels', 'searchRooms')! as List).length));
      expect(setup.http.requests, hasLength(_legacyRequests('S04-search-channels', 'searchRooms')));
      final none = _setup(['S04-search-empty']);
      expect(await none.site.searchRooms('zxqvfixturenoresult', pageSize: 20), isEmpty);
    });

    test("20-5: pages of 20 whatever the page size asked (3.x: the caller's, 30 by default)", () async {
      final http = _Scripted((request) => _response(request, _api({'page': null, 'data': <Object?>[]})));
      final site = ChzzkSite(http);
      await site.searchRooms('a');
      await site.searchRooms('a', page: 3, pageSize: 10);
      await site.searchRooms('a', page: 2, pageSize: 31);
      await site.searchRooms('a', pageSize: 0);
      expect(http.requests.map((request) => request.url.queryParameters), [
        {'keyword': 'a', 'offset': '0', 'size': '20'},
        {'keyword': 'a', 'offset': '40', 'size': '20'},
        {'keyword': 'a', 'offset': '20', 'size': '20'},
        {'keyword': 'a', 'offset': '0', 'size': '20'},
      ]);
    });

    test('20-5: a keyword over 100 characters is cut there (3.x refused it)', () async {
      final http = _Scripted((request) => _response(request, _api({'data': <Object?>[]})));
      await ChzzkSite(http).searchRooms('${'a' * 100}bcd');
      await ChzzkSite(http).searchRooms('a' * 100);
      expect(http.requests.map((request) => request.url.queryParameters['keyword']), ['a' * 100, 'a' * 100]);
    });

    test("3.x's bounds: nothing, or a caller error, without a request", () async {
      final setup = _setup(const []);
      final site = setup.site;
      expect(await site.searchRooms('a', page: 0), isEmpty);
      expect(await site.searchRooms('   '), isEmpty);
      await expectLater(site.searchRooms('a', page: 50002), throwsA(isA<RangeError>()));
      expect(setup.http.requests, isEmpty);
      final http = _Scripted((request) => _response(request, _api({'data': <Object?>[]})));
      await ChzzkSite(http).searchRooms('a', page: 50001);
      expect(http.requests.single.url.queryParameters['offset'], '1000000');
    });

    test('a cancelled search sends nothing', () async {
      final setup = _setup(const []);
      await expectLater(setup.site.searchRoomsCancellable('a', cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('rooms', () {
    test(
      '20-9: room entry reads the channel and v3.1 live-detail only (two requests; 3.x also both masters)',
      () async {
        final setup = _setup(_liveSamples);
        final room = await setup.site.getRoomDetail(roomId: _live);
        expect(_paths(setup.http.requests), [
          '/service/v1/channels/$_live',
          '/service/v3.1/channels/$_live/live-detail',
        ]);
        expect(setup.http.requests.map((request) => request.headers), everyElement(ChzzkApi.headers));
        expect(setup.http.requests.map((request) => request.followRedirects), everyElement(isFalse));
        expect(_legacyRequests('S06-live-detail-live', 'getRoomDetail'), 4);
        final legacy = _legacyValue('S06-live-detail-live', 'getRoomDetail')! as Map<String, dynamic>;
        expect(room.roomId, legacy['roomId']);
        expect(room.title, legacy['title']);
        expect(room.notice, ChzzkApi.timeMachineNotice, reason: '20-10');
        expect(room.startedAt, DateTime.utc(2026, 9, 27, 8, 52, 4));
        expect(room.restriction, LiveRestriction.none);
        final data = room.data! as ChzzkRoomData;
        expect(data.channelId, _live);
        expect(data.media.map((media) => media.id), ['HLS', 'LLHLS']);
        expect(data.media.map((media) => media.url.path), [
          Fixture.load('chzzk', 'S07-master-hls').url.path,
          Fixture.load('chzzk', 'S07-master-llhls').url.path,
        ]);
        expect(data.unavailable, isNull);
        expect(
          room.danmakuData,
          isA<ChzzkDanmakuArgs>()
              .having((args) => args.chatChannelId, 'chat', 'N2lpu9')
              .having((args) => args.channelId, 'channel', _live),
        );
      },
    );

    test('REG-CHZZK-001: v3.1 only, never the v2 live-detail', () async {
      final setup = _setup(['S06-live-detail-region'], extra: [_channelFromLive('S06-live-detail-region', _region)]);
      final room = await setup.site.getRoomDetail(roomId: _region);
      expect(_paths(setup.http.requests), [
        '/service/v1/channels/$_region',
        '/service/v3.1/channels/$_region/live-detail',
      ]);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, ChzzkApi.regionNotice);
      expect(room.restriction, LiveRestriction.regionBlocked);
      expect(room.danmakuData, isNull, reason: 'no chatChannelId');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<RegionBlocked>()));
      expect(setup.http.requests, hasLength(2));
    });

    test('follow refresh and live state: two requests, no stream data; the start and restriction', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-live', 'getRoomDetailForRefresh')));
      expect(room.data, isNull);
      expect(room.danmakuData, isNull);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.none);
      expect(room.startedAt, isNotNull);
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect(setup.http.requests, hasLength(4));
      expect(_legacyRequests('S06-live-detail-live', 'getLiveStatus'), 2);
    });

    test('recording detail: two requests; with its qualities the four 3.x made', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetailForRecording(roomId: _live);
      expect(setup.http.requests, hasLength(2));
      expect((room.data! as ChzzkRoomData).media, hasLength(2));
      expect(room.danmakuData, isA<ChzzkDanmakuArgs>());
      expect(await setup.site.getPlayQualities(detail: room), hasLength(5));
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-live', 'getRoomDetailForRecording')));
      // E05.4: the live's chat, as room entry has it (multi-view).
      final entered = await setup.site.getRoomDetail(roomId: _live);
      expect(room.danmakuData.toString(), entered.danmakuData.toString());
    });

    test('an offline channel: two requests, and no stream without a request', () async {
      final setup = _setup(['S05-channel-offline', 'S06-live-detail-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      expect(setup.http.requests, hasLength(_legacyRequests('S06-live-detail-offline', 'getRoomDetail')));
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.restriction, isNull);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayQualities(detail: await setup.site.getRoomDetailForRefresh(roomId: _offline)),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(4));
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
    });

    test('20-7: a closed live is offline though the channel still says live; no stream, no master', () async {
      final http = _world(live: () => _liveDetail(changes: {'status': 'CLOSE', 'livePlaybackJson': null}));
      final site = ChzzkSite(http);
      final refreshed = await site.getRoomDetailForRefresh(roomId: _live);
      expect(refreshed.effectiveLiveStatus, LiveStatus.offline, reason: '3.x: live by openLive');
      expect(refreshed.startedAt, isNull);
      expect(await site.getLiveStatus(roomId: _live), isFalse);
      final room = await site.getRoomDetail(roomId: _live);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.danmakuData, isNull);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(http.requests.where(_isMaster), isEmpty);
    });

    test('an adult live opens; its stream needs a login', () async {
      final setup = _setup(['S06-live-detail-adult'], extra: [_channelFromLive('S06-live-detail-adult', _adult)]);
      final room = await setup.site.getRoomDetail(roomId: _adult);
      expect(room.isLiveNow, isTrue);
      expect(room.notice, ChzzkApi.adultNotice);
      expect(room.restriction, LiveRestriction.adult);
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
      expect(merged.startedAt, fresh.startedAt);
      expect(merged.restriction, LiveRestriction.none);
    });

    test('20-9: a failing master no longer fails room entry; the other master still gives its lines', () async {
      final forbidden = _world(
        master: (request) => request.url.path.endsWith('a_hls_playlist.m3u8')
            ? _response(request, '', status: 403)
            : _response(request, _master(['720'])),
      );
      final site = ChzzkSite(forbidden);
      final room = await site.getRoomDetail(roomId: _live);
      expect(forbidden.requests, hasLength(2));
      final qualities = await site.getPlayQualities(detail: room);
      expect(forbidden.requests.where(_isMaster), hasLength(2), reason: 'both masters are asked together');
      expect((qualities.single.data! as List<LivePlayLine>).map((line) => line.lineId), ['LLHLS']);
      final gone = _world(
        master: (request) => request.url.path.endsWith('a_playlist.m3u8')
            ? _response(request, '', status: 404)
            : _response(request, _master(['720'])),
      );
      final goneSite = ChzzkSite(gone);
      final lines = await goneSite.resolvePlayUrls(
        detail: await goneSite.getRoomDetailForRecording(roomId: _live),
        quality: const LivePlayQuality(quality: '720p · HLS', id: '720p'),
      );
      expect(lines.lines.map((line) => line.lineId), ['HLS']);
    });

    test('both masters failing is the first failure; the room and its refresh stand', () async {
      final forbidden = _world(master: (request) => _response(request, '', status: 403));
      final site = ChzzkSite(forbidden);
      final room = await site.getRoomDetail(roomId: _live);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<RiskControl>()));
      final gone = _world(master: (request) => _response(request, '', status: 404));
      await expectLater(
        ChzzkSite(gone).getPlayQualities(detail: await ChzzkSite(gone).getRoomDetail(roomId: _live)),
        throwsA(isA<StreamUnavailable>()),
      );
      final unreadable = _world(master: (request) => _response(request, '<html>'));
      final unreadableSite = ChzzkSite(unreadable);
      await expectLater(
        unreadableSite.getPlayQualities(detail: await unreadableSite.getRoomDetail(roomId: _live)),
        throwsA(isA<ApiChanged>()),
      );
      expect((await unreadableSite.getRoomDetailForRefresh(roomId: _live)).isLiveNow, isTrue);
    });

    test('an unusable livePlaybackJson: the room opens, its stream is ApiChanged; recording refuses it', () async {
      final http = _world(live: () => _liveDetail(playback: '{'));
      final site = ChzzkSite(http);
      expect((await site.getRoomDetailForRefresh(roomId: _live)).isLiveNow, isTrue);
      final room = await site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue, reason: '3.x failed room entry');
      expect(room.restriction, isNull);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));
      await expectLater(site.getRoomDetailForRecording(roomId: _live), throwsA(isA<ApiChanged>()));
      expect(http.requests.where(_isMaster), isEmpty, reason: 'no master was asked');
    });
  });

  group('streams', () {
    test("the qualities read both masters; their lines give 3.x's URLs without another request", () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(_paths(setup.http.requests.skip(2).toList()), [
        Fixture.load('chzzk', 'S07-master-hls').url.path,
        Fixture.load('chzzk', 'S07-master-llhls').url.path,
      ]);
      expect(setup.http.requests.map((request) => request.headers), everyElement(ChzzkApi.headers));
      expect(
        setup.http.requests,
        hasLength(
          _legacyRequests('S06-live-detail-live', 'getRoomDetail') +
              _legacyRequests('S06-live-detail-live', 'getPlayQualites'),
        ),
        reason: '20-9 moves the masters from entry to the qualities',
      );
      final legacy = (_legacyValue('S06-live-detail-live', 'getPlayQualites')! as List).cast<Map<String, dynamic>>();
      expect(qualities.map((quality) => quality.quality), legacy.map((quality) => quality['quality']));
      expect(qualities.map((quality) => quality.id), legacy.map((quality) => quality['id']));
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
      expect(await setup.site.getPlayQualities(detail: room), same(qualities));
      expect(setup.http.requests, hasLength(4));
    });

    test('URLs asked before the qualities read the masters once', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final urls = (_legacy('S06-live-detail-live')['getPlayUrls'] as Map).cast<String, dynamic>();
      expect(
        await setup.site.getPlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: '480p · HLS', id: '480p'),
        ),
        urls['480p'],
      );
      expect(await setup.site.getPlayQualities(detail: room), hasLength(5));
      expect(setup.http.requests, hasLength(4));
    });

    test('the qualities serve until a line is due, then the masters again; past their token, the room', () async {
      final start = DateTime.utc(2026, 9, 29);
      var now = start;
      final http = _world(
        master: (request) => _response(request, _master(['720'], expiresAt: start.add(const Duration(hours: 1)))),
      );
      final site = ChzzkSite(http, now: () => now);
      final room = await site.getRoomDetail(roomId: _live);
      final first = await site.getPlayQualities(detail: room);
      expect(http.requests, hasLength(4));
      expect(await site.getPlayQualities(detail: room), same(first));
      now = start.add(const Duration(minutes: 49));
      await site.getPlayUrls(detail: room, quality: first.single);
      expect(http.requests, hasLength(4));
      now = start.add(const Duration(minutes: 50));
      await site.getPlayUrls(detail: room, quality: first.single);
      expect(_paths(http.requests.skip(4).toList()), everyElement(endsWith('.m3u8')), reason: 'the masters only');
      expect(http.requests, hasLength(6));
      now = DateTime.fromMillisecondsSinceEpoch(1900000000 * 1000, isUtc: true).subtract(const Duration(minutes: 5));
      await site.getPlayQualities(detail: room);
      expect(_paths(http.requests.skip(6).take(2).toList()), [
        '/service/v1/channels/$_live',
        '/service/v3.1/channels/$_live/live-detail',
      ]);
      expect(http.requests, hasLength(10), reason: "the masters' token expires: room entry again");
    });

    test('the cancellation of a quality discovery reaches the master requests', () async {
      final http = _world(
        master: (request) async {
          await request.cancel!.whenCancelled;
          throw const TransportFailure('chzzk', TransportReason.cancelled);
        },
      );
      final site = ChzzkSite(http, now: () => DateTime.utc(2026, 9, 29));
      final room = await site.getRoomDetail(roomId: _live);
      final cancel = CancelToken();
      final future = site.discoverPlayQualities(detail: room, cancel: cancel);
      await Future<void>.delayed(Duration.zero);
      expect(http.requests.where(_isMaster), hasLength(2));
      cancel.cancel();
      await expectLater(future, _cancelled);
      expect(http.requests.where(_isMaster).map((request) => request.cancel!.isCancelled), everyElement(isTrue));
      await expectLater(site.discoverPlayQualities(detail: room, cancel: cancel), _cancelled);
      expect(http.requests, hasLength(4));
    });

    test('a card without playback data (a list card, a refreshed follow) is entered first', () async {
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

    test('recovery enters the room again (four requests, as 3.x), keeps the quality and serves later URLs', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final quality = (await setup.site.getPlayQualities(detail: room))[1];
      final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(setup.http.requests, hasLength(8));
      final legacy =
          ((_legacy('S06-live-detail-live')['resolvePlayUrlsForRecoveryRaw'] as Map)[quality.id] as Map)
              as Map<String, dynamic>;
      expect(legacy['requests'], 4);
      expect(resolution.urls, (legacy['value'] as Map)['urls']);
      expect(resolution.appliedQualityData, (legacy['value'] as Map)['appliedQualityData']);
      final later = await setup.site.resolvePlayUrls(detail: room, quality: quality);
      expect(later.urls, resolution.urls);
      expect(setup.http.requests, hasLength(8));
    });

    test("the recovered lines replace the room's earlier ones", () async {
      var issue = 0;
      final http = _world(
        master: (request) {
          issue++;
          return _response(request, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x720\nv$issue/720p.m3u8');
        },
      );
      final site = ChzzkSite(http, now: () => DateTime.utc(2026, 9, 29));
      final room = await site.getRoomDetail(roomId: _live);
      final quality = (await site.getPlayQualities(detail: room)).single;
      expect(
        (await site.getPlayUrls(detail: room, quality: quality)).map(Uri.parse).map((url) => url.pathSegments[2]),
        ['v1', 'v2'],
      );
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(recovered.urls.map(Uri.parse).map((url) => url.pathSegments[2]), ['v3', 'v4']);
      expect(await site.getPlayUrls(detail: room, quality: quality), recovered.urls);
      expect(http.requests, hasLength(8));
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
      expect(http.requests, hasLength(2));
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

    test('20-4: the channel page is the channel, without a request; other hosts are not rooms', () async {
      final http = ReplayHttp(const []);
      expect(await parser(http).parse('https://chzzk.naver.com/$_live'), const RoomLink('chzzk', _live));
      expect(
        await parser(http).parse('주인공 채널 https://chzzk.naver.com/$_live/videos 구독'),
        const RoomLink('chzzk', _live),
      );
      expect(parser(http).containsSupportedLink('https://chzzk.naver.com/$_live'), isTrue);
      expect(await parser(http).parse('https://m.chzzk.naver.com/live/$_live'), isNull);
      expect(await parser(http).parse('https://chzzk.naver.com/video/123'), isNull);
      final site = ChzzkSite(http);
      expect(site.needsResolving('https://chzzk.naver.com/$_live'), isFalse);
      expect(site.roomIdsInShareText('https://chzzk.naver.com/$_live'), isEmpty);
      expect(http.requests, isEmpty);
    });
  });
}
