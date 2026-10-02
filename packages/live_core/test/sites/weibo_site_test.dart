// WeiboSite over the recorded Weibo responses (ReplayHttp) and a few
// synthetic ones: the request headers, the catalog, the snapshot and 3.x's
// list calls, nickname and exact search, room details for entry, refresh and
// recording, the live status, streams read again for every playback,
// cancellation, links and the error mapping. The synthetic cases port 3.x's
// weibo_site_test.dart and weibo_application_test.dart. Differences from
// 3.x's frozen output name their upgrade (docs/specs/UPGRADES.md, 18-x).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/weibo';
const _detailUrl = 'https://weibo.com/l/!/2/wblive/room/show_pc_live.json';
const _recommendUrl = 'https://weibo.com/l/!/2/wblive/pc_recommend/list.json?count=100&uid=';

/// 3.x's snapshot request (18-1 asks count=100).
const _legacyRecommendUrl = 'https://weibo.com/l/!/2/wblive/pc_recommend/list.json?count=10&uid=';

/// 3.x's request list [requests] as the adapter sends it now: the snapshot
/// with count=100 (18-1), the rest unchanged.
List<Object?> _now(Object? requests) => [
  for (final url in requests! as List)
    if (url == _legacyRecommendUrl) _recommendUrl else url,
];

/// The samples' broadcasts.
const _live = '1022:2321325347923495092258';
const _watchLimit = '1022:2321325347904448757771';
const _endedReplay = '1022:2321325269875509035102';
const _notFound = '1022:2321320000000000000001';
const _ended = '1022:2320508a306db1bc389510651e77d5feb4f90d';

/// S03-live, the first card of S03-recommend.
const _s03Live = '1022:2321325348206094712906';

/// S04-shortlink-room, where the short link of S04-shortlink leads.
const _shortLinkRoom = '1022:2321325347771573207158';

/// 3.x's test broadcast.
const _id = '1022:2321325000000000000000';

String _detailOf(String id) => '$_detailUrl?live_id=${Uri.encodeQueryComponent(id)}';

Map<String, dynamic> _legacy(String name) => Fixture.load('weibo', name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Object?> _legacyIds(Object? rooms) => [for (final room in rooms! as List) (room as Map)['roomId']];

/// 3.x's test room answer (legacy/test/fixtures/weibo/live-detail.json),
/// with [url] as both media fields.
Map<String, dynamic> _answer({
  String id = _id,
  int owner = 101,
  int status = 1,
  int watchLimit = 0,
  int playSwitch = 1,
  String url = 'https://media.example.test/stream_wb720avc.flv?token=fixture',
}) => {
  'code': 100000,
  'msg': 'success',
  'error_code': 0,
  'data': {
    'liveId': id,
    'status': status,
    'cover': 'https://img.example.test/cover.jpg',
    'width': 1280,
    'height': 720,
    'title': '公开直播样本',
    'watch_limit': watchLimit,
    'user': {'uid': owner, 'screenName': '样本 0', 'profileImageUrl': 'https://img.example.test/avatar.jpg'},
    'live_origin_hls_url': url,
    'live_origin_flv_url': url,
    'replay_origin_url': '',
    'pay_live_status': 1,
    'play_switch': playSwitch,
  },
};

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

  /// As [send]: the short link session reads headers only.
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

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('weibo', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('weibo', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, Object body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body is String ? body : jsonEncode(body)), url: request.url);

typedef _Setup = ({WeiboSite site, ReplayHttp http});

/// The site over [samples]; S03-recommend was recorded with 3.x's
/// `count=10`, so [anyCount] lets it answer the `count=100` request (18-1;
/// S01-recommend was recorded with `count=100`).
_Setup _setup(List<String> samples, {bool anyCount = false}) {
  final http = ReplayHttp.fixtures(_root, samples, ignoredQuery: {if (anyCount) 'count'});
  return (site: WeiboSite(http), http: http);
}

List<String> _urls(Iterable<LiveRequest> requests) => [for (final request in requests) request.url.toString()];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

void main() {
  group('requests', () {
    test("3.x's headers on every request, redirects not followed", () async {
      final setup = _setup(['S03-recommend', 'S03-live'], anyCount: true);
      await setup.site.getDirectoryPage();
      final room = await setup.site.getRoomDetail(roomId: _s03Live);
      await setup.site.resolvePlayUrls(detail: room, quality: WeiboApi.original);
      expect(_urls(setup.http.requests), [_recommendUrl, _detailOf(_s03Live), _detailOf(_s03Live)]);
      for (final request in setup.http.requests) {
        expect(request.headers, {'referer': 'https://weibo.com/l/wblive/', 'user-agent': 'Mozilla/5.0'});
        expect(request.followRedirects, isFalse);
        expect((request.site, request.method), ('weibo', 'GET'));
      }
      expect((setup.site.id, setup.site.name), ('weibo', '微博直播'));
      expect(setup.site.directoryNoticeKey, 'weibo_directory_scope');
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Weibo danmaku');
    });

    test("3.x's capabilities, plus lines and links", () {
      final site = WeiboSite(ReplayHttp(const []));
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveDirectoryNotice>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isA<LiveSiteLinks>());
      expect(site, isNot(isA<LiveSearchPaginationPolicy>()), reason: '3.x never paged Weibo searches');
      expect(site, isNot(isA<LiveSiteCursorDirectoryPager>()));
      expect(site, isNot(isA<LiveQualityDiscovery>()));
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are typed', () async {
      await expectLater(
        WeiboSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: _id),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(WeiboSite(_Failing(TransportReason.cancelled)).getDirectoryPage(), _cancelled);
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, 'private raw body', status: status));
        await expectLater(WeiboSite(http).getDirectoryPage(), throwsA(matcher), reason: '$status');
        await expectLater(WeiboSite(http).getRoomDetailForRefresh(roomId: _id), throwsA(matcher), reason: '$status');
      }
    });
  });

  group('catalog and directory', () {
    final legacy = _legacy('S03-recommend');

    test('one category with the snapshot as its area, without a request; later pages empty (3.x)', () async {
      final setup = _setup([]);
      final categories = await setup.site.getCategories(1, 30);
      final known = (legacy['getCategores'] as List).single as Map<String, dynamic>;
      expect((categories.single.id, categories.single.name), (known['id'], known['name']));
      final area = categories.single.children.single;
      expect((area.areaType, area.areaId, area.areaName, area.typeName), ('recommendation', 'live', '公开推荐', '微博直播'));
      expect(await setup.site.getCategories(2, 30), hasLength(legacy['getCategores(page: 2)'] as int));
      expect(setup.http.requests, isEmpty);
    });

    test('the snapshot: count=100 (18-1), one page; page 2 empty without a request; the area is the same', () async {
      final setup = _setup(['S03-recommend'], anyCount: true);
      final area = (await setup.site.getCategories(1, 30)).single.children.single;
      for (final (key, call) in [
        ('getDirectoryPage', setup.site.getDirectoryPage),
        ('getDirectoryPage(page: 2)', () => setup.site.getDirectoryPage(page: 2)),
        ('getDirectoryPage(category)', () => setup.site.getDirectoryPage(category: LiveArea.fromJson(area.toJson()))),
      ]) {
        setup.http.requests.clear();
        final page = await call();
        final want = legacy[key] as Map<String, dynamic>;
        final result = want['result'] as Map<String, dynamic>;
        expect(page.rooms.map((room) => room.roomId), _legacyIds(result['rooms']), reason: key);
        expect((page.page, page.hasMore), (result['page'], result['hasMore']), reason: key);
        // changed: 18-1, count=100 instead of 3.x's count=10.
        expect(_urls(setup.http.requests), _now(want['requests']), reason: key);
      }
      expect((legacy['getDirectoryPage'] as Map<String, dynamic>)['requests'], [_legacyRecommendUrl]);
    });

    test("3.x's list calls: the whole snapshot whatever the page size; page 2 asks nothing", () async {
      final setup = _setup(['S03-recommend'], anyCount: true);
      final area = (await setup.site.getCategories(1, 30)).single.children.single;
      final recommended = legacy['getRecommendRooms'] as Map<String, dynamic>;
      for (final (page, size) in [(1, 30), (1, 3), (2, 3)]) {
        setup.http.requests.clear();
        final key = 'page $page, pageSize $size';
        final rooms = await setup.site.getRecommendRooms(page: page, pageSize: size);
        final want = recommended[key] as Map<String, dynamic>;
        expect(rooms.map((room) => room.roomId), _legacyIds(want['result']), reason: key);
        expect(_urls(setup.http.requests), _now(want['requests']), reason: key);
      }
      final categoryRooms = legacy['getCategoryRooms'] as Map<String, dynamic>;
      for (final page in [1, 2]) {
        setup.http.requests.clear();
        final key = 'page $page, pageSize 30';
        final rooms = await setup.site.getCategoryRooms(area, page: page);
        final want = categoryRooms[key] as Map<String, dynamic>;
        expect(rooms.map((room) => room.roomId), _legacyIds(want['result']), reason: key);
        expect(_urls(setup.http.requests), _now(want['requests']), reason: key);
      }
    });

    test('S01-recommend (the count=100 request, 18-1): all 51 cards, as 3.x parsed them, live (18-2)', () async {
      final setup = _setup(['S01-recommend']);
      final page = await setup.site.getDirectoryPage();
      expect(_urls(setup.http.requests), [_recommendUrl]);
      final want = _result(_legacy('S01-recommend')['getDirectoryPage'])! as Map<String, dynamic>;
      expect(page.rooms.map((room) => room.roomId), _legacyIds(want['rooms']));
      expect(page.rooms, hasLength(51));
      expect(page.rooms.every((room) => room.liveStatus == LiveStatus.live && !room.hasRealOnlineCount), isTrue);
      expect(page.rooms.every((room) => room.restriction == null && room.startedAt == null), isTrue);
      expect(await setup.site.getRecommendRooms(pageSize: 3), hasLength(51), reason: "3.x's page size not applied");
    });

    test('bad pages, sizes and areas are caller errors, without a request (3.x)', () async {
      final setup = _setup([]);
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsArgumentError);
      await expectLater(setup.site.getRecommendRooms(page: 0), throwsArgumentError);
      await expectLater(setup.site.getRecommendRooms(pageSize: 0), throwsArgumentError);
      await expectLater(setup.site.getRecommendRooms(pageSize: 1001), throwsArgumentError);
      await expectLater(setup.site.getCategories(0, 30), throwsArgumentError);
      await expectLater(setup.site.getCategories(1, 0), throwsArgumentError);
      for (final area in [
        const LiveArea(platform: 'weibo', areaType: 'other', areaId: 'live'),
        const LiveArea(platform: 'weibo', areaType: 'recommendation', areaId: 'hot'),
        const LiveArea(platform: 'other', areaType: 'recommendation', areaId: 'live'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: '$area');
      }
      expect(setup.http.requests, isEmpty);
    });

    test('the cancellation goes with the request, and wins after the answer (3.x)', () async {
      final token = CancelToken();
      final setup = _setup(['S03-recommend'], anyCount: true);
      await setup.site.getDirectoryPage(cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      await expectLater(setup.site.getDirectoryPage(cancel: CancelToken()..cancel()), _cancelled);
      await expectLater(setup.site.getDirectoryPage(page: 2, cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, hasLength(1), reason: 'nothing sent once cancelled');
      final afterAnswer = CancelToken();
      final http = _Scripted((request) {
        afterAnswer.cancel();
        return _response(request, Fixture.load('weibo', 'S03-recommend').body);
      });
      await expectLater(WeiboSite(http).getDirectoryPage(cancel: afterAnswer), _cancelled);
    });
  });

  group('search', () {
    test('keywords filter the snapshot nicknames, as 3.x (one request each)', () async {
      for (final (name, anyCount) in [('S03-recommend', true), ('S01-recommend', false)]) {
        final setup = _setup([name], anyCount: anyCount);
        final searches = _legacy(name)['searchRooms'] as Map<String, dynamic>;
        for (final keyword in ['卫视', '学长', '发布', 'vortex', 'bang', '_', '小', ' 卫视 ', 'zxqvnoresultfixture']) {
          setup.http.requests.clear();
          final rooms = await setup.site.searchRooms(keyword, pageSize: 20);
          final want = searches[keyword] as Map<String, dynamic>;
          expect(rooms.map((room) => room.roomId), _legacyIds(want['result']), reason: '$name $keyword');
          expect(setup.http.requests, hasLength((want['requests'] as List).length), reason: '$name $keyword');
        }
        final three = await setup.site.searchRooms('_', pageSize: 3);
        expect(three.map((room) => room.roomId), _legacyIds(_result(searches['_ pageSize 3'])));
        setup.http.requests.clear();
        expect(await setup.site.searchRooms('小', page: 2), isEmpty);
        expect(await setup.site.searchRooms('  '), isEmpty);
        expect(setup.http.requests, isEmpty, reason: 'page 2 and blank ask nothing (3.x)');
        expect(await setup.site.searchRooms('Re:Zero'), isEmpty, reason: 'a keyword, filtered (3.x)');
        expect(setup.http.requests, hasLength(1));
      }
    });

    test('a broadcast id or room link finds that room with one request, on page 1 only (3.x)', () async {
      final setup = _setup(['S02-live', 'S02-ended-replay']);
      final legacy = _legacy('S02-live');
      for (final (key, input) in [
        ('searchRooms', _live),
        ('searchRooms(link)', 'https://weibo.com/l/wblive/p/show/$_live'),
        ('searchRooms(mobile link)', 'https://weibo.com/l/wblive/m/show/${_live.replaceAll(':', '%3A')}'),
      ]) {
        setup.http.requests.clear();
        final rooms = await setup.site.searchRooms(input);
        final want = legacy[key] as Map<String, dynamic>;
        expect(rooms.map((room) => room.roomId), _legacyIds(want['result']), reason: key);
        expect(_urls(setup.http.requests), want['requests'], reason: key);
        expect(rooms.single.isLiveNow, isTrue);
      }
      final replay = await setup.site.searchRooms('https://live.media.weibo.com/live/show?id=$_endedReplay');
      expect(replay.single.liveStatus, LiveStatus.replay, reason: 'kept as 3.x showed it; the list filters it');
      setup.http.requests.clear();
      expect(await setup.site.searchRooms(_live, page: 2), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('a missing broadcast is an empty result: HTTP 404 (3.x) and error_code 27401 (3.x: an error)', () async {
      final legacy = _legacy('S02-notfound');
      expect(_result(legacy['searchRooms']), {'throws': 'WeiboException', 'message': 'Weibo api'});
      final setup = _setup(['S02-notfound']);
      expect(await setup.site.searchRooms(_notFound), isEmpty);
      final absent = _Scripted((request) => _response(request, '', status: 404));
      expect(await WeiboSite(absent).searchRooms(_id), isEmpty);
      for (final (status, matcher) in [(429, isA<RateLimited>()), (503, isA<NetworkFailure>())]) {
        final failing = _Scripted((request) => _response(request, '', status: status));
        await expectLater(WeiboSite(failing).searchRooms(_id), throwsA(matcher), reason: '$status');
      }
      final broken = _Scripted((request) => _response(request, '{"code":999999,"error_code":20003,"data":[]}'));
      await expectLater(WeiboSite(broken).searchRooms(_id), throwsA(isA<ApiChanged>()));
    });

    test('an older broadcast id 3.x did not recognise is found (3.x filtered nicknames with it)', () async {
      final legacy = _legacy('S02-ended');
      expect(_result(legacy['searchRooms']), isEmpty);
      final setup = _setup(['S02-ended']);
      final rooms = await setup.site.searchRooms(_ended);
      expect((rooms.single.roomId, rooms.single.nick), (_ended, '央视新闻'));
      expect(_urls(setup.http.requests), [_detailOf(_ended)]);
    });

    test('other links and blank input find nothing without a request (3.x asked the snapshot)', () async {
      final legacy = _legacy('S03-recommend')['searchRooms'] as Map<String, dynamic>;
      expect((legacy['https://weibo.com/u/101'] as Map<String, dynamic>)['requests'], hasLength(1));
      final setup = _setup([]);
      for (final input in [
        'https://weibo.com/u/101',
        'https://t.cn/fixture-link',
        'https://weibo.com/l/wblive/p/show/$_id/..',
        '   ',
      ]) {
        expect(await setup.site.searchRooms(input), isEmpty, reason: input);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('pages and sizes 3.x refused are refused without a request', () async {
      final setup = _setup([]);
      await expectLater(setup.site.searchRooms('样本', page: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('样本', pageSize: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms(_id, pageSize: 1001), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });

    test('pre-cancelled searches send nothing; the cancellation reaches the exact lookup (3.x)', () async {
      final setup = _setup(['S03-recommend', 'S02-live'], anyCount: true);
      final cancelled = CancelToken()..cancel();
      await expectLater(setup.site.searchRoomsCancellable(_live, cancel: cancelled), _cancelled);
      await expectLater(setup.site.searchRoomsCancellable('卫视', cancel: cancelled), _cancelled);
      await expectLater(setup.site.searchRoomsCancellable('卫视', page: 2, cancel: cancelled), _cancelled);
      expect(setup.http.requests, isEmpty);
      final token = CancelToken();
      final started = Completer<void>();
      final answer = Completer<LiveResponse>();
      final http = _Scripted((request) {
        started.complete();
        return answer.future;
      });
      final search = WeiboSite(http).searchRoomsWithCancellation(_live, cancel: token);
      final check = expectLater(search, _cancelled);
      await started.future;
      expect(identical(http.requests.single.cancel, token), isTrue);
      token.cancel();
      answer.complete(_response(http.requests.single, Fixture.load('weibo', 'S02-live').body));
      await check;
    });
  });

  group('rooms', () {
    for (final (name, id) in [
      ('S02-live', _live),
      ('S02-watch-limit', _watchLimit),
      ('S02-ended-replay', _endedReplay),
      ('S03-live', _s03Live),
    ]) {
      test('$name: entry, refresh and recording, one request each for the broadcast asked (3.x)', () async {
        final setup = _setup([name]);
        final legacy = _legacy(name);
        final rooms = [
          await setup.site.getRoomDetail(roomId: id),
          await setup.site.getRoomDetailForRefresh(roomId: ' $id '),
          await setup.site.getRoomDetailForRecording(roomId: id),
        ];
        for (final (index, key) in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording'].indexed) {
          final want = legacy[key] as Map<String, dynamic>;
          final result = want['result'] as Map<String, dynamic>;
          expect((rooms[index].roomId, rooms[index].userId), (result['roomId'], result['userId']), reason: key);
          // changed: 18-4, the friends-only broadcast is live (3.x: unknown).
          expect(
            rooms[index].liveStatus!.index,
            name == 'S02-watch-limit' ? LiveStatus.live.index : result['liveStatus'],
            reason: key,
          );
          expect(rooms[index].data, isA<WeiboRoomData>());
          expect(rooms[index].restriction, name == 'S02-watch-limit' ? LiveRestriction.private : LiveRestriction.none);
          expect(rooms[index].startedAt, rooms[index].isLiveNow ? isNotNull : isNull);
        }
        expect(_urls(setup.http.requests), everyElement(_detailOf(id)));
        expect(setup.http.requests, hasLength(3));
      });
    }

    test('a card refreshed by its detail keeps its identity and takes the detail (mergeFrom)', () async {
      final setup = _setup(['S03-recommend', 'S03-live'], anyCount: true);
      final card = (await setup.site.getDirectoryPage()).rooms.first;
      expect((card.roomId, card.liveStatus, card.avatar), (_s03Live, LiveStatus.live, ''));
      final merged = card.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: card.roomId));
      expect(merged.identityKey, 'weibo:$_s03Live');
      expect((merged.title, merged.nick, merged.liveStatus), ('惑星VORTEX四周年吃播', '惑星VORTEX', LiveStatus.live));
      expect(merged.avatar, allOf(startsWith('https://tvax1.sinaimg.cn/'), contains('.1024/')));
      expect(merged.userId, '6596154111');
      expect((merged.restriction, merged.startedAt), (LiveRestriction.none, DateTime.utc(2026, 9, 28, 11, 36, 3)));
      expect(setup.http.requests, hasLength(2));
    });

    test('S02-ended: an older id 3.x refused opens; status 5 is offline (18-3)', () async {
      final setup = _setup(['S02-ended']);
      final room = await setup.site.getRoomDetail(roomId: _ended);
      expect((room.liveStatus, room.title), (LiveStatus.offline, '泸县地震救援现场'));
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(1));
    });

    test('a live follow that ended: the refresh says offline and drops the start and restriction (M2.1)', () async {
      var ended = false;
      final http = _Scripted((request) {
        final answer = _answer(status: ended ? 5 : 1);
        (answer['data'] as Map)['startTime'] = 1790595363000;
        return _response(request, answer);
      });
      final site = WeiboSite(http);
      final live = await site.getRoomDetailForRefresh(roomId: _id);
      expect((live.liveStatus, live.restriction), (LiveStatus.live, LiveRestriction.none));
      expect(live.startedAt, DateTime.utc(2026, 9, 28, 11, 36, 3));
      ended = true;
      final merged = live.mergeFrom(await site.getRoomDetailForRefresh(roomId: _id));
      expect(
        (merged.liveStatus, merged.restriction, merged.startedAt, merged.followGroup),
        (LiveStatus.offline, null, null, FollowGroup.offline),
      );
    });

    test('an id that is no broadcast id is NotFound without a request; so is error_code 27401', () async {
      final setup = _setup(['S02-notfound']);
      for (final id in ['101', '', '1042152:wrong', 'https://weibo.com/l/wblive/p/show/$_id', '$_id/x']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: _notFound), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(1));
    });

    test('the live status: live (restricted too), a replay or ended broadcast not live, others no answer', () async {
      final setup = _setup(['S02-live', 'S02-ended-replay', 'S02-watch-limit', 'S02-ended']);
      expect(await setup.site.getLiveStatus(roomId: _live), _result(_legacy('S02-live')['getLiveStatus']));
      expect(
        await setup.site.getLiveStatus(roomId: _endedReplay),
        _result(_legacy('S02-ended-replay')['getLiveStatus']),
      );
      // changed: 18-4, 3.x's access failure; the broadcast is on air.
      expect(_result(_legacy('S02-watch-limit')['getLiveStatus']), {
        'throws': 'WeiboException',
        'message': 'Weibo access',
      });
      expect(await setup.site.getLiveStatus(roomId: _watchLimit), isTrue);
      // changed: 18-3, 3.x refused the id (M4.18: no answer for status 5).
      expect(await setup.site.getLiveStatus(roomId: _ended), isFalse);
      final disabled = _Scripted((request) => _response(request, _answer(playSwitch: 0)));
      expect(await WeiboSite(disabled).getLiveStatus(roomId: _id), isTrue, reason: 'on air, playback switched off');
      final unknown = _Scripted((request) => _response(request, _answer(status: 99)));
      await expectLater(WeiboSite(unknown).getLiveStatus(roomId: _id), throwsA(isA<StreamUnavailable>()));
      final failing = _Scripted((request) => _response(request, '', status: 503));
      await expectLater(WeiboSite(failing).getLiveStatus(roomId: _id), throwsA(isA<NetworkFailure>()));
    });
  });

  group('streams', () {
    test("entry and play: 3.x's quality without a request, then the detail again for the line", () async {
      final setup = _setup(['S03-live']);
      final legacy = _legacy('S03-live');
      final room = await setup.site.getRoomDetail(roomId: _s03Live);
      final qualities = await setup.site.getPlayQualities(detail: room);
      final want = (legacy['getPlayQualites'] as List).single as Map<String, dynamic>;
      expect(qualities.map((quality) => (quality.quality, quality.id, quality.sort)), [
        (want['quality'], want['id'], want['sort']),
      ]);
      expect(setup.http.requests, hasLength(1));
      for (final (key, call) in [
        ('resolvePlayUrlsRaw', () => setup.site.resolvePlayUrls(detail: room, quality: qualities.single)),
        (
          'resolvePlayUrlsForRecoveryRaw',
          () => setup.site.resolvePlayUrlsForRecovery(detail: room, quality: qualities.single),
        ),
      ]) {
        setup.http.requests.clear();
        final resolution = await call();
        final traced = legacy[key] as Map<String, dynamic>;
        final result = traced['result'] as Map<String, dynamic>;
        expect(resolution.urls, result['urls'], reason: key);
        expect(resolution.appliedQualityData, result['appliedQualityData'], reason: key);
        expect(_urls(setup.http.requests), traced['requests'], reason: key);
        final line = resolution.lines.single;
        expect((line.format, line.codec, line.lineId, line.lease), (StreamFormat.flv, 'avc', 'alicdn', null));
        expect(line.headers, isEmpty);
      }
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.single), _result(legacy['getPlayUrls']));
    });

    test('every playback, recovery and recording reads the broadcast again (3.x)', () async {
      var answers = 0;
      final http = _Scripted(
        (request) => _response(request, _answer(url: 'https://media.example.test/fresh.flv?token=${answers++}')),
      );
      final site = WeiboSite(http);
      final room = await site.getRoomDetail(roomId: _id);
      final quality = (await site.getPlayQualities(detail: room)).single;
      expect(quality.selectionId, 'original');
      expect((await site.resolvePlayUrls(detail: room, quality: quality)).urls, [
        'https://media.example.test/fresh.flv?token=1',
      ]);
      expect((await site.resolvePlayUrlsForRecovery(detail: room, quality: quality)).urls, [
        'https://media.example.test/fresh.flv?token=2',
      ]);
      final recording = await site.getRoomDetailForRecording(roomId: _id);
      expect(await site.getPlayUrls(detail: recording, quality: quality), [
        'https://media.example.test/fresh.flv?token=4',
      ]);
      expect(http.requests, hasLength(5));
      expect(http.requests.map((request) => request.url.queryParameters['live_id']), everyElement(_id));
    });

    test('a fresh answer of another anchor is ApiChanged, never played (3.x)', () async {
      var owner = 101;
      final http = _Scripted((request) => _response(request, _answer(owner: owner)));
      final site = WeiboSite(http);
      final room = await site.getRoomDetail(roomId: _id);
      owner = 999;
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: WeiboApi.original),
        throwsA(isA<ApiChanged>()),
      );
      final stored = LiveRoom(platform: 'weibo', roomId: _id, userId: '101');
      await expectLater(site.resolvePlayUrls(detail: stored, quality: WeiboApi.original), throwsA(isA<ApiChanged>()));
    });

    test('another quality is refused without a request', () async {
      final http = _Scripted((request) => _response(request, _answer()));
      final site = WeiboSite(http);
      final room = await site.getRoomDetail(roomId: _id);
      for (final quality in [
        const LivePlayQuality(quality: 'fake', id: 'fake', data: ['https://evil.test/a.flv']),
        const LivePlayQuality(quality: '原画', id: 'origin'),
        WeiboApi.replay,
      ]) {
        await expectLater(
          site.resolvePlayUrls(detail: room, quality: quality),
          throwsA(isA<StreamUnavailable>()),
          reason: '${quality.id}',
        );
      }
      expect(http.requests, hasLength(1));
    });

    test('a room whose detail does not play is refused before any request, with its reason', () async {
      final setup = _setup(['S02-watch-limit', 'S02-ended']);
      final restricted = await setup.site.getRoomDetail(roomId: _watchLimit);
      final ended = await setup.site.getRoomDetail(roomId: _ended);
      setup.http.requests.clear();
      // changed: 3.x's access failure (M4.18: NeedsLogin) is StreamUnavailable
      // with the kind (18-4, M2.1).
      final friendsOnly = isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('private'));
      await expectLater(setup.site.getPlayQualities(detail: restricted), throwsA(friendsOnly));
      await expectLater(
        setup.site.resolvePlayUrls(detail: restricted, quality: WeiboApi.original),
        throwsA(friendsOnly),
      );
      await expectLater(setup.site.getPlayQualities(detail: ended), throwsA(isA<StreamUnavailable>()));
      final stored = LiveRoom(platform: 'weibo', roomId: _id, liveStatus: LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: stored), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.resolvePlayUrls(detail: stored, quality: WeiboApi.original),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
    });

    test('S04-self-only-replay: a private replay offers nothing, with the platform text', () async {
      final setup = _setup(['S04-self-only-replay']);
      final room = await setup.site.getRoomDetail(roomId: _watchLimit);
      expect((room.liveStatus, room.restriction), (LiveStatus.replay, LiveRestriction.private));
      await expectLater(
        setup.site.getPlayQualities(detail: room),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('主播自己'))),
      );
      await expectLater(
        setup.site.resolvePlayUrls(detail: room, quality: WeiboApi.replay),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(1));
    });

    test('S02-ended-replay (18-5): the replay offers 原画 and plays its recording without another request', () async {
      final setup = _setup(['S02-ended-replay']);
      final room = await setup.site.getRoomDetail(roomId: _endedReplay);
      final legacy = _legacy('S02-ended-replay');
      // changed: 3.x offered no quality and refused the URLs.
      expect(legacy['getPlayQualites'], isEmpty);
      expect(_result(legacy['getPlayUrls']), {'throws': 'WeiboException', 'message': 'Weibo notLive'});
      expect(await setup.site.getPlayQualities(detail: room), [WeiboApi.replay]);
      const recording = 'https://live.video.weibocdn.com/5269875505238409_wb1080avc_index.m3u8';
      for (final resolve in [setup.site.resolvePlayUrls, setup.site.resolvePlayUrlsForRecovery]) {
        final resolution = await resolve(detail: room, quality: WeiboApi.replay);
        expect(resolution.urls, [recording]);
        expect(resolution.appliedQualityData, 'replay');
        final line = resolution.lines.single;
        expect((line.format, line.codec, line.lease), (StreamFormat.hls, 'avc', null));
        expect(line.headers, isEmpty);
      }
      expect(await setup.site.getPlayUrls(detail: room, quality: WeiboApi.replay), [recording]);
      expect(setup.http.requests, hasLength(1), reason: 'the recording came with the detail');
      await expectLater(
        setup.site.resolvePlayUrls(detail: room, quality: WeiboApi.original),
        throwsA(isA<StreamUnavailable>()),
        reason: 'the live quality of an ended broadcast',
      );
      expect(setup.http.requests, hasLength(1));
    });

    test('a stored replay without detail data offers 原画 and reads the detail once to play', () async {
      final setup = _setup(['S02-ended-replay']);
      final stored = LiveRoom(
        platform: 'weibo',
        roomId: _endedReplay,
        userId: '5371906414',
        liveStatus: LiveStatus.replay,
      );
      expect(await setup.site.getPlayQualities(detail: stored), [WeiboApi.replay]);
      expect(setup.http.requests, isEmpty);
      final resolution = await setup.site.resolvePlayUrls(detail: stored, quality: WeiboApi.replay);
      expect(resolution.urls.single, endsWith('_wb1080avc_index.m3u8'));
      expect(_urls(setup.http.requests), [_detailOf(_endedReplay)]);
      await expectLater(
        setup.site.resolvePlayUrls(detail: stored, quality: WeiboApi.original),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a live broadcast that ended while playing: recovery reports it, never switches to the replay', () async {
      var ended = false;
      final http = _Scripted((request) {
        final answer = _answer(status: ended ? 3 : 1);
        if (ended) (answer['data'] as Map)['replay_origin_url'] = 'http://media.example.test/replay_index.m3u8';
        return _response(request, answer);
      });
      final site = WeiboSite(http);
      final room = await site.getRoomDetail(roomId: _id);
      ended = true;
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: WeiboApi.original),
        throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('ended'))),
      );
      final replay = await site.getRoomDetail(roomId: _id);
      expect((await site.resolvePlayUrls(detail: replay, quality: WeiboApi.replay)).urls, [
        'https://media.example.test/replay_index.m3u8',
      ]);
      expect(http.requests, hasLength(3));
    });

    for (final mode in ['restricted', 'disabled', 'unknown', 'replay', 'empty-media']) {
      test('a fresh $mode answer never falls back to the old URL (3.x)', () async {
        var fresh = false;
        final http = _Scripted(
          (request) => _response(
            request,
            !fresh
                ? _answer()
                : switch (mode) {
                    'restricted' => _answer(watchLimit: 8),
                    'disabled' => _answer(playSwitch: 0),
                    'unknown' => _answer(status: 99),
                    'replay' => _answer(status: 3),
                    _ => _answer(url: ''),
                  },
          ),
        );
        final site = WeiboSite(http);
        final room = await site.getRoomDetail(roomId: _id);
        fresh = true;
        await expectLater(
          site.getPlayUrls(detail: room, quality: WeiboApi.original),
          throwsA(isA<StreamUnavailable>()),
        );
        final again = await site.getRoomDetail(roomId: _id);
        // changed: 18-4, restricted and switched-off broadcasts on air are
        // live (3.x: unknown).
        expect(again.liveStatus, switch (mode) {
          'replay' => LiveStatus.replay,
          'unknown' => LiveStatus.unknown,
          _ => LiveStatus.live,
        });
        expect(again.restriction, switch (mode) {
          'restricted' => LiveRestriction.appOnly,
          'unknown' => null,
          _ => LiveRestriction.unplayable,
        });
        expect(http.requests, hasLength(3));
      });
    }

    test('a list card or stored follow without detail data plays after one request', () async {
      final http = _Scripted((request) => _response(request, _answer()));
      final site = WeiboSite(http);
      final card = LiveRoom(platform: 'weibo', roomId: _id, userId: '101', liveStatus: LiveStatus.unknown);
      expect(await site.getPlayQualities(detail: card), [WeiboApi.original]);
      expect(http.requests, isEmpty);
      expect((await site.resolvePlayUrls(detail: card, quality: WeiboApi.original)).urls, [
        'https://media.example.test/stream_wb720avc.flv?token=fixture',
      ]);
      expect(http.requests, hasLength(1));
    });
  });

  group('short links (18-9)', () {
    test('a t.cn link in a share text is followed once, without the target; the room is its broadcast', () async {
      final setup = _setup(['S04-shortlink']);
      final site = setup.site;
      final parser = LinkParser(SiteRegistry({'weibo': () => site}), setup.http);
      const text = '我在#微博直播#开播啦，快来看看吧 http://t.cn/AXWbinBd 候鸟书的微博直播';
      expect(site.needsResolving('http://t.cn/AXWbinBd'), isTrue);
      expect(site.roomIdFromUrl('http://t.cn/AXWbinBd'), isNull);
      expect(parser.containsSupportedLink(text), isTrue);
      expect(await parser.parse(text), const RoomLink('weibo', _shortLinkRoom));
      final request = setup.http.requests.single;
      expect(request.url.toString(), 'https://t.cn/AXWbinBd');
      expect(request.followRedirects, isFalse);
      expect(request.headers, WeiboApi.headers);
    });

    test('an unknown code (weibo.com/sorry) leads nowhere; so does an answer without a redirect', () async {
      final setup = _setup(['S04-shortlink-missing']);
      final parser = LinkParser(SiteRegistry({'weibo': () => setup.site}), setup.http);
      expect(await parser.parse('https://t.cn/zzzzzzzz'), isNull);
      expect(setup.http.requests, hasLength(1));
      final page = _Scripted((request) => _response(request, '<html>t.cn</html>'));
      expect(
        await WeiboSite(page)
            .resolveUrl('https://t.cn/AXWbinBd', ShortLinkSession(page, timeout: const Duration(seconds: 5))),
        isNull,
      );
    });

    test('a t.cn link to another site is handed back to every platform', () async {
      final http = _Scripted(
        (request) => LiveResponse(
          status: 302,
          headers: const {
            'location': ['https://live.bilibili.com/22603245'],
          },
          bytes: const [],
          url: request.url,
        ),
      );
      final resolution = await WeiboSite(http)
          .resolveUrl('http://t.cn/A6bili', ShortLinkSession(http, timeout: const Duration(seconds: 5)));
      expect(
        resolution,
        isA<LinkRedirect>().having((link) => '${link.target}', 'target', 'https://live.bilibili.com/22603245'),
      );
      expect(http.requests.single.url.toString(), 'https://t.cn/A6bili');
    });

    test('search: a t.cn link finds its broadcast with two requests; nothing for other targets', () async {
      final setup = _setup(['S04-shortlink', 'S04-shortlink-room', 'S04-shortlink-missing']);
      final rooms = await setup.site.searchRooms('http://t.cn/AXWbinBd');
      expect(
        (rooms.single.roomId, rooms.single.nick, rooms.single.liveStatus),
        (_shortLinkRoom, '候鸟书', LiveStatus.offline),
      );
      expect(_urls(setup.http.requests), ['https://t.cn/AXWbinBd', _detailOf(_shortLinkRoom)]);
      setup.http.requests.clear();
      expect(await setup.site.searchRooms('https://t.cn/zzzzzzzz'), isEmpty);
      expect(_urls(setup.http.requests), ['https://t.cn/zzzzzzzz']);
      for (final (status, location) in [(302, 'https://live.bilibili.com/1'), (200, null), (404, null)]) {
        final http = _Scripted(
          (request) => LiveResponse(
            status: status,
            headers: {
              'location': [?location],
            },
            bytes: const [],
            url: request.url,
          ),
        );
        expect(await WeiboSite(http).searchRooms('https://t.cn/AXWbinBd'), isEmpty, reason: '$status');
        expect(http.requests, hasLength(1));
      }
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(WeiboSite(http).searchRooms('https://t.cn/AXWbinBd'), throwsA(matcher), reason: '$status');
      }
      await expectLater(
        WeiboSite(_Failing(TransportReason.timeout)).searchRooms('https://t.cn/AXWbinBd'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('search: a t.cn link to a broadcast that does not exist finds nothing', () async {
      final http = _Scripted(
        (request) => request.url.host == 't.cn'
            ? LiveResponse(
                status: 302,
                headers: const {
                  'location': ['https://weibo.com/l/wblive/p/show/$_notFound'],
                },
                bytes: const [],
                url: request.url,
              )
            : _response(request, Fixture.load('weibo', 'S02-notfound').body),
      );
      expect(await WeiboSite(http).searchRooms('https://t.cn/AXWbinBd'), isEmpty);
      expect(_urls(http.requests), ['https://t.cn/AXWbinBd', _detailOf(_notFound)]);
    });
  });

  group('links', () {
    const watch = 'https://weibo.com/l/wblive/p/show/$_id';

    for (final raw in [
      watch,
      '$watch?from=share#live',
      watch.replaceFirst('https://weibo.com', 'http://www.weibo.com:80'),
      watch.replaceFirst('/p/', '/m/').replaceFirst('1022:', '1022%3a'),
      '  $watch  ',
      'https://live.media.weibo.com/live/show?id=$_id',
    ]) {
      test('a watch link in a share text, without a request: $raw (3.x)', () async {
        final http = ReplayHttp(const []);
        final site = WeiboSite(http);
        final parser = LinkParser(SiteRegistry({'weibo': () => site}), http);
        expect(site.roomIdFromUrl(raw), _id);
        expect(site.needsResolving(raw), isFalse);
        expect(parser.containsSupportedLink('直播 $raw'), isTrue);
        expect(await parser.parse('直播 $raw'), const RoomLink('weibo', _id));
        expect(http.requests, isEmpty);
      });
    }

    test('Chinese prose after the link is dropped before the room is read (3.x)', () async {
      final http = ReplayHttp(const []);
      final parser = LinkParser(SiteRegistry({'weibo': () => WeiboSite(http)}), http);
      for (final text in ['分享 $watch。打开应用观看', '直播：$watch，复制本条信息', '分享 $watch)', '分享 $watch.']) {
        expect(await parser.parse(text), const RoomLink('weibo', _id), reason: text);
      }
      expect(http.requests, isEmpty);
    });

    for (final raw in [
      _id,
      'https://weibo.com/u/101',
      'https://weibo.com.evil.test/l/wblive/p/show/$_id',
      'https://user@weibo.com/l/wblive/p/show/$_id',
      'https://weibo.com:444/l/wblive/p/show/$_id',
      'ftp://weibo.com/l/wblive/p/show/$_id',
      '$watch/.',
      '$watch/..',
      '$watch/.。继续观看',
      '$watch/..)',
      '$watch/.?from=share',
      '$watch/..#section',
      '$watch/%2e',
      watch.replaceFirst('/p/show/', '/p/x/../show/'),
      watch.replaceFirst('1022:', '1022%253a'),
      'https://t.cn/fixture-link',
      'https://weibo.com/l/wblive/app/h5_compatible?live_id=$_id',
    ]) {
      test('not salvaged into a room: $raw (3.x)', () async {
        final http = ReplayHttp(const []);
        final site = WeiboSite(http);
        final parser = LinkParser(SiteRegistry({'weibo': () => site}), http);
        expect(site.roomIdFromUrl(raw), isNull);
        expect(parser.containsSupportedLink(raw), isFalse);
        expect(await parser.parse(raw), isNull);
        expect(http.requests, isEmpty);
      });
    }
  });
}
