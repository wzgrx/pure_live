// KugouLiveSite over the recorded Kugou Live responses (ReplayHttp) and a few
// synthetic ones: the requests (URL, headers, redirects) and their counts,
// compared with the requests 3.x made (expected.json), the catalog and its
// cache, the directory, the keyword and room searches (with the search
// snapshot, UPGRADES "翻页"), room details for entry, refresh and recording,
// streams with their lines, restrictions and recovery, the lease queries,
// "优先 H.264", cancellation, links through the link parser and the error
// mapping. Ports the orchestration parts of 3.x's kugou_live_site_test.dart;
// the M4.U items are named by their docs/specs/UPGRADES.md numbers.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/kugoulive';

/// The live room's entry.
const _liveSamples = ['S04-room-live', 'S05-stream-live'];

/// The chat-limited room's entry (M4.U.29).
const _chatLimitSamples = ['S04-room-chatlimit', 'S05-stream-chatlimit'];

/// 1 µs after the epoch: the search callback is `pureLive1`, as recorded;
/// the stream request's `_` (milliseconds) is 0, left out of matching.
final DateTime _clock = DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true);

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

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

typedef _Setup = ({KugouLiveSite site, ReplayHttp http});

/// A site over [samples] (and [extra]); the stream request's clock value
/// `_` is left out of matching.
_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], bool Function()? preferH264}) {
  final http = ReplayHttp(
    [...extra, for (final sample in samples) ReplaySample.load('$_root/$sample')],
    ignoredQuery: const {'_'},
  );
  return (site: KugouLiveSite(http, preferH264: preferH264, now: () => _clock), http: http);
}

/// [sample]'s recorded request answered with [body] instead.
ReplaySample _answer(String sample, String body) {
  final recorded = ReplaySample.load('$_root/$sample');
  return ReplaySample(method: 'GET', url: recorded.url, status: 200, bytes: utf8.encode(body));
}

Map<String, dynamic> _legacy(String sample) => Fixture.load('kugoulive', sample).legacy as Map<String, dynamic>;

Map<String, dynamic> _outcome(String sample, String key) => _legacy(sample)[key] as Map<String, dynamic>;

Object? _legacyValue(String sample, String key) => _outcome(sample, key)['value'];

/// A request as the legacy harness recorded it: the clock values replaced,
/// header names in lower case.
Map<String, Object?> _described(LiveRequest request) => {
  'url': '${request.url}'
      .replaceFirstMapped(RegExp(r'([?&])_=\d+'), (match) => '${match[1]}_=<ms>')
      .replaceFirstMapped(RegExp(r'([?&])callback=pureLive\d+'), (match) => '${match[1]}callback=<callback>'),
  'headers': {for (final MapEntry(:key, :value) in request.headers.entries) key.toLowerCase(): value},
};

Map<String, Object?> _legacyRequest(Object? request) {
  final map = request! as Map<String, dynamic>;
  return {
    'url': map['url'],
    'headers': {
      for (final MapEntry(:key, :value) in (map['headers'] as Map<String, dynamic>).entries) key.toLowerCase(): value,
    },
  };
}

/// Asserts that [requests] are the ones 3.x made for [outcome], in order,
/// sent as `kugoulive` without following redirects.
void _expectLegacyRequests(List<LiveRequest> requests, Map<String, dynamic> outcome) {
  expect(requests.map(_described), [for (final request in outcome['requests'] as List) _legacyRequest(request)]);
  for (final request in requests) {
    expect(request.site, 'kugoulive');
    expect(request.followRedirects, isFalse);
    expect(request.method, 'GET');
  }
}

/// What every room changes against 3.x: `httpHeaders` (3.x's media headers
/// on the room, now on the lines, M4.29) and `notice` (29-6; 29-2 for the
/// room info's announcements; M5.25: the chat is shown, so the notice no
/// longer says it cannot be seen). The new keys (`startedAt`,
/// `restriction`) are not in 3.x's output; kugoulive_api_test.dart checks
/// them.
const _roomChanged = {'httpHeaders', 'notice'};

/// A room from the room info also leaves its title empty (29-2).
const Set<String> _infoChanged = {..._roomChanged, 'title'};

/// A phone broadcast's card is live (29-1; 3.x: unknown, `liveStatus` 3).
const Set<String> _phoneChanged = {..._roomChanged, 'liveStatus', 'status'};

/// A search card has no audience unless live and above 0 (29-3).
const Set<String> _searchChanged = {..._roomChanged, 'watching', 'onlineViewers', 'audienceMetricType'};

/// A list card's changes: a phone broadcast's ([_phoneChanged]) or
/// [_roomChanged].
Set<String> _cardChanged(Map<String, dynamic> legacy) => legacy['liveStatus'] == 3 ? _phoneChanged : _roomChanged;

/// [actual] equals 3.x's [legacy] on every key but [changed]; null reads as
/// ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = _roomChanged,
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

void _expectRooms(
  List<LiveRoom> rooms,
  Object? legacy, {
  Set<String> Function(Map<String, dynamic> legacy) changed = _cardChanged,
  String? reason,
}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(
      _projection(room),
      expected[index],
      changed: changed(expected[index]),
      reason: '${reason ?? ''}[$index]',
    );
  }
}

Set<String> _info(Map<String, dynamic> legacy) => _infoChanged;

Set<String> _search(Map<String, dynamic> legacy) => _searchChanged;

Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

List<String> _paths(List<LiveRequest> requests) => [for (final request in requests) request.url.path];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// A room info answer (3.x's test `_roomJson`) with [info] and [data] changed.
String _roomInfo({Map<String, Object?> info = const {}, Map<String, Object?> data = const {}}) => jsonEncode({
  'code': 0,
  'data': {
    'liveSessionId': '6ab93a1bh6b263401',
    'liveType': 0,
    'normalRoomInfo': {
      'fansCount': 9083,
      'imgPath': '/v2/fxroomcover/cover.jpg',
      'kugouId': 1797665793,
      'limitType': 0,
      'nickName': 'Q梦星冉',
      'publicMesg': '如果做人必须得有抱负',
      'userId': 1797665793,
      'userLogo': '/v2/fxuserlogo/avatar.jpg',
      ...info,
    },
    ...data,
  },
});

/// A signed media URL of room 5085706.
String _signed(String path) =>
    'https://tx2.liveplay.live.kugou.com/live/$path?cn=fx&txSecret=0123456789abcdef0123456789abcdef'
    '&txTime=6AB1DA15&token=0-5085706-0-1010-7-1000-fixture-2';

/// A stream answer of room 5085706 with an H.264 tier 4 and an HEVC tier 5.
final String _twoCodecs = jsonEncode({
  'code': 0,
  'data': {
    'status': 1,
    'roomId': 5085706,
    'lines': [
      {
        'sid': 40,
        'streamProfiles': [
          {
            'rate': 5,
            'codec': 2,
            'layout': 1,
            'httpsFlv': [_signed('hevc.flv')],
          },
          {
            'rate': 4,
            'codec': 1,
            'layout': 1,
            'httpsFlv': [_signed('avc.flv')],
          },
        ],
      },
    ],
  },
});

/// The room info of 5085706 and then [stream] for its stream answer.
_Scripted _roomThenStream(String stream, {int status = 200}) => _Scripted(
  (request) => request.url.host == KugouLiveApi.roomHost
      ? _response(request, _roomInfo())
      : _response(request, stream, status: status),
);

const _area7024 = LiveArea(platform: 'kugoulive', areaType: 'official', areaId: '7024', areaName: '舞蹈');

void main() {
  group('adapter', () {
    test('identity, capabilities, notice key; no danmaku and no short links', () {
      final site = KugouLiveSite(ReplayHttp(const []));
      expect(site.id, _legacy('S01-home')['id']);
      expect(site.name, _legacy('S01-home')['name']);
      expect(site.directoryNoticeKey, _legacy('S01-home')['directoryNoticeKey']);
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveDirectoryNotice>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isA<LivePlayLeaseMetadata>());
      expect(site, isNot(isA<LivePlayUrlCursorResolver>()));
      expect(site.getDanmaku(), isA<EmptyDanmaku>());
      expect(site.needsResolving('https://fanxing.kugou.com/3197156'), isFalse);
      expect(SiteIds.supported, contains(site.id));
    });
  });

  group('catalog', () {
    test('the home page once: request, areas and cache as in 3.x', () async {
      final (:site, :http) = _setup(['S01-home']);
      expect(await site.getCategories(2, 1000), isEmpty);
      expect(await site.getCategories(1, 0), isEmpty);
      expect(http.requests, isEmpty);
      final categories = await site.getCategories(1, 1000);
      _expectLegacyRequests(http.requests, _outcome('S01-home', 'getCategores(1, 1000)'));
      final legacy = (_legacyValue('S01-home', 'getCategores(1, 1000)')! as List).single as Map<String, dynamic>;
      expect((categories.single.id, categories.single.name), (legacy['id'], legacy['name']));
      final areas = (legacy['children'] as List).cast<Map<String, dynamic>>();
      expect(categories.single.children, hasLength(areas.length));
      for (final (index, area) in categories.single.children.indexed) {
        _expectParity(area.toJson(), areas[index], changed: const {}, reason: '[$index]');
      }
      expect((await site.getCategories(1, 3)).single.children.map((area) => area.areaName), ['推荐', '一起玩', '音乐']);
      await site.getCategories(1, 1000);
      expect(http.requests, hasLength(1), reason: '3.x kept the areas for the adapter lifetime');
      expect(_outcome('S01-home', 'getCategores(1, 1000) again')['requests'], isEmpty);
    });

    test('a failed read is asked again', () async {
      final html = Fixture.load('kugoulive', 'S01-home').body;
      var calls = 0;
      final http = _Scripted((request) => _response(request, html, status: calls++ == 0 ? 503 : 200));
      final site = KugouLiveSite(http);
      await expectLater(site.getCategories(1, 100), throwsA(isA<NetworkFailure>()));
      expect((await site.getCategories(1, 100)).single.children, hasLength(14));
      expect(http.requests, hasLength(2));
    });
  });

  group('directory', () {
    for (final (sample, page) in [('S02-recommend-p1', 1), ('S02-recommend-p2', 2)]) {
      test('$sample: 推荐 by every entry, one request each as in 3.x', () async {
        final (:site, :http) = _setup([sample]);
        final result = await site.getDirectoryPage(page: page);
        _expectLegacyRequests(http.requests, _outcome(sample, 'getDirectoryPage($page)'));
        final legacy = _legacyValue(sample, 'getDirectoryPage($page)')! as Map<String, dynamic>;
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        _expectRooms(result.rooms, legacy['rooms'], reason: sample);
        expect(result.rooms.every((room) => room.liveStatus == LiveStatus.live), isTrue, reason: '29-1');
        http.requests.clear();
        _expectRooms(
          await site.getRecommendRooms(page: page),
          _legacyValue(sample, 'getRecommendRooms($page, 30)'),
          reason: 'recommend',
        );
        _expectLegacyRequests(http.requests, _outcome(sample, 'getRecommendRooms($page, 30)'));
        http.requests.clear();
        const recommendArea = LiveArea(platform: 'kugoulive', areaType: 'official', areaId: '8000');
        _expectRooms(
          await site.getCategoryRooms(recommendArea, page: page, pageSize: 100),
          _legacyValue(sample, 'getCategoryRooms(8000, $page)'),
          reason: '推荐 area',
        );
        _expectLegacyRequests(http.requests, _outcome(sample, 'getCategoryRooms(8000, $page)'));
      });
    }

    test('S03 an area: `list_v4` with its `cid`, as in 3.x', () async {
      final (:site, :http) = _setup(['S03-area-7024-p1']);
      final result = await site.getDirectoryPage(category: _area7024);
      final outcome = _outcome('S03-area-7024-p1', 'getDirectoryPage(1, 7024)');
      _expectLegacyRequests(http.requests, outcome);
      final legacy = outcome['value'] as Map<String, dynamic>;
      expect(result.hasMore, legacy['hasMore']);
      _expectRooms(result.rooms, legacy['rooms']);
      _expectRooms(
        await site.getCategoryRooms(_area7024, pageSize: 3),
        _legacyValue('S03-area-7024-p1', 'getCategoryRooms(7024, 1, 3)'),
      );
    });

    test('calls answered without a request: page 0, sizes below 1; caller errors', () async {
      final (:site, :http) = _setup(const []);
      final empty = await site.getDirectoryPage(page: 0);
      final legacy = _legacyValue('S02-recommend-p1', 'getDirectoryPage(0)')! as Map<String, dynamic>;
      expect((empty.page, empty.hasMore, empty.rooms.length), (legacy['page'], legacy['hasMore'], 0));
      expect(await site.getRecommendRooms(page: 0), isEmpty);
      expect(await site.getRecommendRooms(pageSize: 0), isEmpty);
      expect(await site.getCategoryRooms(_area7024, page: 0), isEmpty);
      for (final area in const [
        LiveArea(platform: 'huya', areaType: 'official', areaId: '7024'),
        LiveArea(platform: 'kugoulive', areaType: 'custom', areaId: '7024'),
        LiveArea(platform: 'kugoulive', areaType: 'official', areaId: 'dance'),
      ]) {
        await expectLater(site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
      }
      expect(
        (_legacyValue('S03-area-7024-p1', 'getDirectoryPage(1, other platform)')! as Map)['message'],
        'Kugou Live identity',
      );
      await expectLater(site.getDirectoryPage(page: KugouLiveApi.maxPage + 1), throwsRangeError);
      expect(http.requests, isEmpty);
    });

    test('an area outside the loaded catalog is asked for (3.x refused it)', () async {
      expect(
        (_legacyValue('S03-area-7024-p1', 'getDirectoryPage(1, 100003 after the catalog)')! as Map)['message'],
        'Kugou Live identity',
      );
      final http = _Scripted(
        (request) => _response(
          request,
          jsonEncode({
            'code': 0,
            'data': {'hasNextPage': 0, 'list': <Object?>[]},
          }),
        ),
      );
      final page = await KugouLiveSite(http).getDirectoryPage(
        category: const LiveArea(platform: 'kugoulive', areaType: 'official', areaId: '100003'),
      );
      expect(page.rooms, isEmpty);
      expect(http.requests.single.url.queryParameters['cid'], '100003');
    });
  });

  group('search', () {
    test('a keyword: pages match 3.x; page 1 asks as 3.x, later pages cut its answer (snapshot)', () async {
      final (:site, :http) = _setup(['S06-search']);
      for (final (page, pageSize) in [(1, 30), (2, 30), (4, 30), (5, 30), (1, 100)]) {
        http.requests.clear();
        final key = 'searchRooms($page, $pageSize)';
        final rooms = await site.searchRoomsCancellable('唱歌', page: page, pageSize: pageSize, cancel: CancelToken());
        _expectRooms(rooms, _legacyValue('S06-search', key), changed: _search, reason: key);
        if (page == 1) {
          _expectLegacyRequests(http.requests, _outcome('S06-search', key));
        } else {
          expect(_outcome('S06-search', key)['requests'], hasLength(1), reason: '3.x asked again');
          expect(http.requests, isEmpty, reason: 'the answer of page 1, under 30 s old');
        }
      }
      expect((await site.searchRooms(' 唱歌 ', pageSize: 100)).length, 98);
    });

    test('the snapshot lives 30 s, per keyword; page 1 and a failure keep nothing old', () async {
      final body = Fixture.load('kugoulive', 'S06-search').body.trim();
      var failing = false;
      final http = _Scripted((request) {
        if (failing) return _response(request, '', status: 500);
        // The platform echoes the callback it is given.
        final callback = request.url.queryParameters['callback']!;
        return _response(request, body.replaceFirst('pureLive1(', '$callback('));
      });
      var now = DateTime.utc(2026, 9, 27, 17, 52, 27);
      final site = KugouLiveSite(http, now: () => now);
      Future<List<LiveRoom>> search(String keyword, int page) => site.searchRooms(keyword, page: page);
      expect(await search('唱歌', 2), hasLength(30), reason: 'nothing kept: asks');
      expect(http.requests, hasLength(1));
      now = now.add(const Duration(seconds: 29));
      expect(await search('唱歌', 3), hasLength(30));
      expect(http.requests, hasLength(1), reason: 'under 30 s');
      expect(await search('歌', 2), hasLength(30));
      expect(http.requests, hasLength(2), reason: 'another keyword');
      expect(await search('唱歌', 1), hasLength(30));
      expect(http.requests, hasLength(3), reason: 'page 1 always asks');
      now = now.add(const Duration(seconds: 30));
      expect(await search('唱歌', 4), hasLength(8));
      expect(http.requests, hasLength(4), reason: '30 s old: asks again');
      now = now.subtract(const Duration(minutes: 1));
      expect(await search('唱歌', 2), hasLength(30));
      expect(http.requests, hasLength(5), reason: 'a clock turned back asks again');
      failing = true;
      now = now.add(const Duration(minutes: 5));
      await expectLater(search('唱歌', 2), throwsA(isA<NetworkFailure>()));
      expect(http.requests, hasLength(6));
      for (final keyword in ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9']) {
        failing = false;
        await search(keyword, 1);
      }
      http.requests.clear();
      await search('a9', 2);
      await search('a2', 2);
      expect(http.requests, isEmpty, reason: 'the last eight keywords are kept');
      await search('a1', 2);
      expect(http.requests, hasLength(1), reason: 'the oldest is dropped');
    });

    test('searches answered without a request, as in 3.x', () async {
      final (:site, :http) = _setup(['S06-search']);
      for (final (key, search) in [
        ('searchRooms(1, 101)', () => site.searchRooms('唱歌', pageSize: 101)),
        ('searchRooms(0, 30)', () => site.searchRooms('唱歌', page: 0)),
        ('searchRooms(1, 0)', () => site.searchRooms('唱歌', pageSize: 0)),
        ('searchRooms(blank)', () => site.searchRooms('  ')),
      ]) {
        expect(await search(), isEmpty, reason: key);
        expect(_outcome('S06-search', key)['requests'], isEmpty, reason: key);
      }
      await expectLater(site.searchRooms('歌' * 101), throwsArgumentError);
      expect((_legacyValue('S06-search', 'searchRooms(101 characters)')! as Map)['message'], 'Kugou Live identity');
      expect(http.requests, isEmpty);
    });

    test('no result', () async {
      final (:site, :http) = _setup(['S06-search-empty']);
      expect(await site.searchRooms('qzxqzxpurelivezz'), isEmpty);
      _expectLegacyRequests(http.requests, _outcome('S06-search-empty', 'searchRooms(qzxqzxpurelivezz)'));
    });

    test('a room number or link: the refresh detail, one request, page 1 only', () async {
      final (:site, :http) = _setup(_liveSamples);
      final searches = _legacy('S04-room-live')['searchRooms'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in searches.entries) {
        http.requests.clear();
        final rooms = await site.searchRoomsCancellable(key, cancel: CancelToken());
        final outcome = value as Map<String, dynamic>;
        _expectRooms(rooms, outcome['value'], changed: _info, reason: key);
        _expectLegacyRequests(http.requests, outcome);
        expect(rooms.single.data, isNull, reason: 'refresh depth');
        expect(rooms.single.startedAt, isNotNull);
      }
      http.requests.clear();
      expect(await site.searchRooms('3197156', page: 2), isEmpty);
      expect(
        await site.searchRooms(
          'http://mfanxing.kugou.com/staticPub/rmobile/sharePage/normalRoom/views/index.html?roomId=3197156',
          page: 2,
        ),
        isEmpty,
      );
      expect(http.requests, isEmpty);
      final shared = await site.searchRooms(
        'http://mfanxing.kugou.com/staticPub/rmobile/sharePage/normalRoom/views/index.html?roomId=3197156',
      );
      expect(shared.single.roomId, '3197156', reason: '29-4');
      expect(_paths(http.requests), ['/roomcen/room/web/cdn/getEnterRoomInfo']);
    });

    test('a room that does not exist finds nothing (3.x showed a room named "Kugou Live")', () async {
      final (:site, :http) = _setup(['S04-room-notfound']);
      final legacy = _legacy('S04-room-notfound')['searchRooms'] as Map<String, dynamic>;
      for (final keyword in legacy.keys) {
        expect(((legacy[keyword] as Map)['value'] as List).single, containsPair('nick', 'Kugou Live'));
        expect(await site.searchRooms(keyword), isEmpty, reason: keyword);
      }
      expect(http.requests, hasLength(2));
    });

    test('other failures of a room search are not "no result"', () async {
      final site = KugouLiveSite(_Scripted((request) => _response(request, '', status: 500)));
      await expectLater(site.searchRooms('3197156'), throwsA(isA<NetworkFailure>()));
      await expectLater(site.searchRooms('唱歌'), throwsA(isA<NetworkFailure>()));
    });

    test('cancellation before and during the request, and with a kept answer', () async {
      final (:site, :http) = _setup(['S06-search']);
      final before = CancelToken()..cancel();
      await expectLater(site.searchRoomsCancellable('唱歌', cancel: before), _cancelled);
      await expectLater(site.searchRoomsCancellable('3197156', cancel: before), _cancelled);
      expect(http.requests, isEmpty);
      await site.searchRooms('唱歌');
      await expectLater(site.searchRoomsCancellable('唱歌', page: 2, cancel: before), _cancelled);
      expect(http.requests, hasLength(1));
      final during = CancelToken();
      final scripted = _Scripted((request) {
        during.cancel();
        return _response(request, Fixture.load('kugoulive', 'S06-search').body);
      });
      await expectLater(
        KugouLiveSite(scripted, now: () => _clock).searchRoomsCancellable('唱歌', cancel: during),
        _cancelled,
      );
      expect(scripted.requests.single.cancel, same(during));
    });
  });

  group('rooms', () {
    test('live: entry and recording two requests, refresh and state one, as in 3.x', () async {
      final (:site, :http) = _setup(_liveSamples);
      for (final (key, call) in [
        ('getRoomDetail', () => site.getRoomDetail(roomId: '3197156')),
        ('getRoomDetailForRecording', () => site.getRoomDetailForRecording(roomId: '3197156')),
        ('getRoomDetailForRefresh', () => site.getRoomDetailForRefresh(roomId: '3197156')),
      ]) {
        http.requests.clear();
        final room = await call();
        _expectLegacyRequests(http.requests, _outcome('S04-room-live', key));
        _expectParity(
          _projection(room),
          _legacyValue('S04-room-live', key)! as Map<String, dynamic>,
          changed: _infoChanged,
          reason: key,
        );
        expect(room.httpHeaders, isEmpty, reason: key);
        expect(room.startedAt, DateTime.utc(2026, 9, 27, 15, 45, 31), reason: key);
        final data = room.data;
        if (key == 'getRoomDetailForRefresh') {
          expect(data, isNull);
          expect(room.restriction, isNull, reason: 'the refresh cannot tell');
        } else {
          expect(room.restriction, LiveRestriction.none, reason: 'the stream answer gave a stream');
          expect(data, isA<KugouLiveRoomData>().having((data) => data.roomId, 'roomId', '3197156'));
          final variants = (data! as KugouLiveRoomData).variants;
          final legacy = (_legacy('S04-room-live')['data.variants'] as List).cast<Map<String, dynamic>>();
          expect(variants.map((variant) => variant.id), legacy.map((variant) => variant['id']));
          expect(variants.single.lines.map((line) => line.url), legacy.single['urls']);
        }
      }
      http.requests.clear();
      expect(await site.getLiveStatus(roomId: '3197156'), _legacyValue('S04-room-live', 'getLiveStatus'));
      _expectLegacyRequests(http.requests, _outcome('S04-room-live', 'getLiveStatus'));
    });

    test('a room link names its number (3.x identity), the share page too (29-4)', () async {
      final (:site, :http) = _setup(_liveSamples);
      final room = await site.getRoomDetail(roomId: 'https://fanxing.kugou.com/3197156');
      expect(room.roomId, '3197156');
      _expectParity(
        _projection(room),
        _legacyValue('S04-room-live', 'getRoomDetail(link)')! as Map<String, dynamic>,
        changed: _infoChanged,
      );
      _expectLegacyRequests(http.requests, _outcome('S04-room-live', 'getRoomDetail(link)'));
      expect(room.hasIdentity(platform: 'kugoulive', roomId: '3197156'), isTrue);
      final shared = await site.getRoomDetailForRefresh(
        roomId: 'https://mfanxing.kugou.com/staticPub/rmobile/sharePage/normalRoom/views/index.html?roomId=3197156',
      );
      expect(shared.roomId, '3197156');
    });

    test('offline: one request at every depth; no stream, no start, no restriction', () async {
      final (:site, :http) = _setup(['S04-room-offline']);
      for (final key in ['getRoomDetail', 'getRoomDetailForRecording', 'getRoomDetailForRefresh']) {
        http.requests.clear();
        final room = switch (key) {
          'getRoomDetail' => await site.getRoomDetail(roomId: '1014306'),
          'getRoomDetailForRecording' => await site.getRoomDetailForRecording(roomId: '1014306'),
          _ => await site.getRoomDetailForRefresh(roomId: '1014306'),
        };
        _expectLegacyRequests(http.requests, _outcome('S04-room-offline', key));
        _expectParity(
          _projection(room),
          _legacyValue('S04-room-offline', key)! as Map<String, dynamic>,
          changed: _infoChanged,
          reason: key,
        );
        expect(room.liveStatus, LiveStatus.offline);
        expect((room.startedAt, room.restriction), (null, null), reason: key);
      }
      expect(await site.getLiveStatus(roomId: '1014306'), isFalse);
      final entered = await site.getRoomDetail(roomId: '1014306');
      http.requests.clear();
      expect(_legacyValue('S04-room-offline', 'getPlayQualites'), isEmpty);
      await expectLater(site.getPlayQualities(detail: entered), throwsA(isA<StreamUnavailable>()));
      final kept = entered.copyWith(liveStatus: LiveStatus.unknown);
      await expectLater(site.getPlayQualities(detail: kept), throwsA(isA<StreamUnavailable>()), reason: 'the data');
      expect(http.requests, isEmpty);
    });

    test('a phone broadcast is live at refresh depth, as in 3.x', () async {
      final (:site, :http) = _setup(['S04-room-mobile']);
      final room = await site.getRoomDetailForRefresh(roomId: '50595748');
      _expectParity(
        _projection(room),
        _legacyValue('S04-room-mobile', 'getRoomDetailForRefresh')! as Map<String, dynamic>,
        changed: _infoChanged,
      );
      expect(room.startedAt, DateTime.fromMillisecondsSinceEpoch(0x6ab8d6ec * 1000, isUtc: true));
      expect(await site.getLiveStatus(roomId: '50595748'), isTrue);
      expect(http.requests, hasLength(2));
    });

    test('a room that does not exist is NotFound everywhere (3.x: a "Kugou Live" room)', () async {
      final (:site, :http) = _setup(['S04-room-notfound']);
      expect((_legacyValue('S04-room-notfound', 'getRoomDetail')! as Map)['liveStatus'], 3);
      expect((_legacyValue('S04-room-notfound', 'getLiveStatus')! as Map)['message'], 'Kugou Live access');
      await expectLater(site.getRoomDetail(roomId: '999'), throwsA(isA<NotFound>()));
      await expectLater(site.getRoomDetailForRefresh(roomId: '999'), throwsA(isA<NotFound>()));
      await expectLater(site.getRoomDetailForRecording(roomId: '999'), throwsA(isA<NotFound>()));
      await expectLater(site.getLiveStatus(roomId: '999'), throwsA(isA<NotFound>()));
      expect(http.requests, hasLength(4));
    });

    test('something that is not a room number is NotFound without a request (3.x: identity)', () async {
      final (:site, :http) = _setup(const []);
      for (final id in ['12', 'abc', '012345', 'https://fanxing.kugou.com/pcindex/category/7024']) {
        await expectLater(site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(site.getLiveStatus(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(http.requests, isEmpty);
      expect((_legacyValue('S04-room-live', 'getRoomDetail(bad id)')! as Map)['message'], 'Kugou Live identity');
    });

    test('a chat limit (limitType 2) is live and plays: two requests, restriction none (3.x: unknown)', () async {
      final (:site, :http) = _setup(_chatLimitSamples);
      final room = await site.getRoomDetail(roomId: '5171815');
      expect(_paths(http.requests), [
        '/roomcen/room/web/cdn/getEnterRoomInfo',
        '/video/pc/live/pull/mutiline/streamaddr',
      ]);
      expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.none));
      expect(room.notice, isNot(contains(KugouLiveApi.restrictedNotice)));
      expect(room.startedAt, isNotNull);
      http.requests.clear();
      final quality = (await site.getPlayQualities(detail: room)).single;
      expect(quality.quality, 'FLV 码率档 5');
      expect((await site.resolvePlayUrlsRaw(detail: room, quality: quality)).lines, hasLength(2));
      expect(http.requests, isEmpty);
      expect(await site.getLiveStatus(roomId: '5171815'), isTrue, reason: '3.x: access');
      final refreshed = await site.getRoomDetailForRefresh(roomId: '5171815');
      expect((refreshed.liveStatus, refreshed.restriction), (LiveStatus.live, null));
    });

    test('a stream answer asking for a login: live, needsLogin with its notice; NeedsLogin to play', () async {
      final http = _roomThenStream(jsonEncode({'code': KugouLiveApi.loginRequiredCode, 'msg': '', 'data': null}));
      final site = KugouLiveSite(http);
      final room = await site.getRoomDetail(roomId: '5085706');
      expect(http.requests, hasLength(2));
      expect(
        (room.liveStatus, room.restriction, room.isRestricted),
        (LiveStatus.live, LiveRestriction.needsLogin, true),
      );
      expect(room.notice!.split('\n').first, KugouLiveApi.restrictedNotice);
      expect(room.followGroup, FollowGroup.live);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<NeedsLogin>()));
      expect(http.requests, hasLength(2), reason: 'the entry kept why');
      await expectLater(site.getPlayQualities(detail: room.copyWith(data: 'x')), throwsA(isA<NeedsLogin>()));
      expect(http.requests, hasLength(4), reason: 'without the data: entered again');
      expect(await site.getLiveStatus(roomId: '5085706'), isTrue);
    });

    test('no live session: unknown; the stream is unavailable and the state has no answer', () async {
      final http = _Scripted((request) => _response(request, _roomInfo(data: {'liveSessionId': ''})));
      final site = KugouLiveSite(http);
      final room = await site.getRoomDetail(roomId: '5085706');
      expect(room.liveStatus, LiveStatus.unknown);
      expect(room.restriction, isNull);
      expect(http.requests, hasLength(1));
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(site.getLiveStatus(roomId: '5085706'), throwsA(isA<ApiChanged>()));
    });

    test('a live room whose stream answer has no stream is entered, unplayable (3.x failed the entry)', () async {
      final offline = jsonEncode({
        'code': 0,
        'data': {'status': 0, 'roomId': 3197156, 'lines': <Object?>[]},
      });
      final (:site, :http) = _setup(['S04-room-live'], extra: [_answer('S05-stream-live', offline)]);
      final room = await site.getRoomDetail(roomId: '3197156');
      expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.unplayable));
      expect(room.isLiveNow, isTrue, reason: 'M2.1: still live');
      expect(http.requests, hasLength(2));
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(http.requests, hasLength(2));
    });

    test('chat arguments (29-5, M5.25): live entry and recording carry the room, nothing else', () async {
      final (:site, :http) = _setup(_liveSamples);
      for (final room in [
        await site.getRoomDetail(roomId: 'https://fanxing.kugou.com/3197156'),
        await site.getRoomDetailForRecording(roomId: '3197156'),
      ]) {
        expect(room.danmakuData, isA<KugouLiveDanmakuArgs>().having((args) => args.roomId, 'roomId', '3197156'));
      }
      expect((await site.getRoomDetailForRefresh(roomId: '3197156')).danmakuData, isNull, reason: 'not an entry');
      expect(http.requests, hasLength(5), reason: 'no request for the chat');
      expect(const KugouLiveDanmakuArgs(roomId: '3197156').toString(), 'KugouLiveDanmakuArgs(3197156)');
      // Offline and without a live session: none; live without a stream or
      // asking for a login: the chat works all the same.
      expect((await _setup(['S04-room-offline']).site.getRoomDetail(roomId: '1014306')).danmakuData, isNull);
      final unknown = KugouLiveSite(_Scripted((request) => _response(request, _roomInfo(data: {'liveSessionId': ''}))));
      expect((await unknown.getRoomDetail(roomId: '5085706')).danmakuData, isNull);
      final login = KugouLiveSite(
        _roomThenStream(jsonEncode({'code': KugouLiveApi.loginRequiredCode, 'msg': '', 'data': null})),
      );
      expect(
        (await login.getRoomDetail(roomId: '5085706')).danmakuData,
        isA<KugouLiveDanmakuArgs>().having((args) => args.roomId, 'roomId', '5085706'),
      );
      final noStream = _setup(
        ['S04-room-live'],
        extra: [
          _answer(
            'S05-stream-live',
            jsonEncode({
              'code': 0,
              'data': {'status': 0, 'roomId': 3197156, 'lines': <Object?>[]},
            }),
          ),
        ],
      );
      expect((await noStream.site.getRoomDetail(roomId: '3197156')).danmakuData, isA<KugouLiveDanmakuArgs>());
      // The chat's audience brings the broadcast's cumulative viewers.
      expect(AudiencePlatformCapability.of('kugoulive').hasTotalViewers, isTrue);
      expect(KugouLiveApi.chatNotice, isNot(contains('聊天')), reason: 'M5.25: the chat is shown');
    });

    test('a stream answer that fails otherwise fails the entry, as in 3.x', () async {
      for (final (status, body, matcher) in [
        (500, '', isA<NetworkFailure>()),
        (200, 'not json', isA<ApiChanged>()),
        (
          200,
          jsonEncode({
            'code': 0,
            'data': {'status': 1, 'roomId': 1, 'lines': <Object?>[]},
          }),
          isA<ApiChanged>(),
        ),
        (200, jsonEncode({'code': 2, 'msg': 'busy'}), isA<ApiChanged>()),
      ]) {
        await expectLater(
          KugouLiveSite(_roomThenStream(body, status: status)).getRoomDetail(roomId: '5085706'),
          throwsA(matcher),
          reason: body,
        );
      }
    });

    test('a refresh merged into a stored 3.x follow keeps its identity, title and data', () async {
      final (:site, :http) = _setup(_liveSamples);
      final entered = await site.getRoomDetail(roomId: '3197156');
      final stored = LiveRoom.fromJson({
        ...entered.toJson(),
        'title': '通宵主播！！！！王者女侠，峡谷相约！！！！打王者的可以预约！',
        'watching': '10',
        'onlineViewers': '10',
        'audienceMetricType': 'onlineViewers',
        'httpHeaders': KugouLiveApi.mediaHeaders('3197156'),
      }).copyWith(data: entered.data);
      final refreshed = await site.getRoomDetailForRefresh(roomId: '3197156');
      final merged = stored.mergeFrom(refreshed);
      expect(merged.roomId, '3197156');
      expect(merged.title, stored.title, reason: '29-2: an empty title keeps the stored one');
      expect(merged.onlineViewers, '10', reason: 'the refresh has no audience');
      expect(merged.data, same(entered.data));
      expect(merged.httpHeaders, isNotEmpty, reason: '3.x stored value kept');
      expect(merged.startedAt, refreshed.startedAt);
      expect(merged.restriction, LiveRestriction.none, reason: 'same broadcast: the entry value stays');
    });
  });

  group('streams', () {
    test('qualities and URLs of an entered room: no request, as in 3.x', () async {
      final (:site, :http) = _setup(_liveSamples);
      final room = await site.getRoomDetail(roomId: '3197156');
      http.requests.clear();
      final qualities = await site.getPlayQualities(detail: room);
      final legacy = (_legacyValue('S04-room-live', 'getPlayQualites')! as List).cast<Map<String, dynamic>>();
      expect(
        [for (final quality in qualities) (quality.quality, quality.id, quality.sort)],
        [for (final quality in legacy) (quality['quality'], quality['id'], quality['sort'])],
      );
      final quality = qualities.single;
      final urls = (_legacy('S04-room-live')['getPlayUrls'] as Map)['flv:4:1:2'] as Map;
      expect(await site.getPlayUrls(detail: room, quality: quality), urls['value']);
      final resolution = await site.resolvePlayUrlsRaw(detail: room, quality: quality);
      final resolved = ((_legacy('S04-room-live')['resolvePlayUrlsRaw'] as Map)['flv:4:1:2'] as Map)['value'] as Map;
      expect(resolution.urls, resolved['urls']);
      expect(resolution.appliedQualityData, resolved['appliedQualityData']);
      expect(resolution.lines.map((line) => line.lineId), ['sid5', 'sid40']);
      expect(resolution.lines.first.headers, KugouLiveApi.mediaHeaders('3197156'));
      expect(resolution.lines.first.lease?.expiresAt?.toIso8601String(), (resolved['invalidAt'] as List).first);
      final normalized = await site.resolvePlayUrls(detail: room, quality: quality);
      expect(normalized.urls, resolved['urls']);
      expect(http.requests, isEmpty);
      await expectLater(
        site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: 'HLS 码率档 4', id: 'hls:4:1:2'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect((_legacyValue('S04-room-live', 'resolvePlayUrlsRaw(hls:4:1:2)')! as Map)['message'], contains('media'));
    });

    test('"优先 H.264": read at each call; on (default) H.264 first, off HEVC first; lines say hevc (29-8)', () async {
      var prefer = true;
      final http = _roomThenStream(_twoCodecs);
      final site = KugouLiveSite(http, preferH264: () => prefer);
      final room = await site.getRoomDetail(roomId: '5085706');
      expect((await site.getPlayQualities(detail: room)).map((quality) => quality.id), ['flv:4:1:1', 'flv:5:2:1']);
      prefer = false;
      final qualities = await site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.id), ['flv:5:2:1', 'flv:4:1:1']);
      final hevc = await site.resolvePlayUrlsRaw(detail: room, quality: qualities.first);
      expect(hevc.lines.single.codec, 'hevc');
      expect(
        (await KugouLiveSite(_roomThenStream(_twoCodecs)).getPlayQualities(detail: room)).first.id,
        'flv:4:1:1',
        reason: 'on by default',
      );
    });

    test('a room without data is entered first (3.x: identity); an offline card needs no request', () async {
      expect((_legacyValue('S02-recommend-p1', 'getPlayQualites(card)')! as Map)['message'], 'Kugou Live identity');
      expect(
        (_legacyValue('S04-room-live', 'getPlayQualites(refreshed room)')! as Map)['message'],
        'Kugou Live identity',
      );
      final (:site, :http) = _setup(_liveSamples);
      for (final card in [
        LiveRoom(platform: 'kugoulive', roomId: '3197156', liveStatus: LiveStatus.live),
        await site.getRoomDetailForRefresh(roomId: '3197156'),
        LiveRoom(
          platform: 'kugoulive',
          roomId: '3197156',
          liveStatus: LiveStatus.live,
          data: KugouLiveRoomData(roomId: '1014306', unavailable: const StreamUnavailable('kugoulive')),
        ),
      ]) {
        http.requests.clear();
        final qualities = await site.getPlayQualities(detail: card);
        expect(qualities.single.id, 'flv:4:1:2');
        expect(_paths(http.requests), [
          '/roomcen/room/web/cdn/getEnterRoomInfo',
          '/video/pc/live/pull/mutiline/streamaddr',
        ]);
      }
      http.requests.clear();
      final offline = LiveRoom(platform: 'kugoulive', roomId: '3197156', liveStatus: LiveStatus.offline);
      expect(_legacyValue('S04-room-live', 'getPlayQualites(offline card)'), isEmpty);
      await expectLater(site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
      expect(http.requests, isEmpty);
      await expectLater(
        site.getPlayQualities(
          detail: LiveRoom(platform: 'huya', roomId: '3197156'),
        ),
        throwsArgumentError,
      );
    });

    test('recovery enters the room again: two requests and the URLs of 3.x', () async {
      final (:site, :http) = _setup(_liveSamples);
      final room = await site.getRoomDetail(roomId: '3197156');
      final quality = (await site.getPlayQualities(detail: room)).single;
      http.requests.clear();
      final resolution = await site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: quality);
      final outcome = _outcome('S04-room-live', 'resolvePlayUrlsForRecoveryRaw(flv:4:1:2)');
      _expectLegacyRequests(http.requests, outcome);
      expect(resolution.urls, (outcome['value'] as Map)['urls']);
      expect(resolution.appliedQualityData, (outcome['value'] as Map)['appliedQualityData']);
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(recovered.urls, resolution.urls);
    });

    test('recovery of a room that went offline or lost the quality is an error', () async {
      final (:site, :http) = _setup(['S04-room-offline']);
      const quality = LivePlayQuality(quality: 'FLV 码率档 4', id: 'flv:4:1:2');
      final stale = LiveRoom(platform: 'kugoulive', roomId: '1014306', liveStatus: LiveStatus.live);
      await expectLater(
        site.resolvePlayUrlsForRecoveryRaw(detail: stale, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(http.requests, hasLength(1));
      final (site: live, http: _) = _setup(_liveSamples);
      final entered = await live.getRoomDetail(roomId: '3197156');
      await expectLater(
        live.resolvePlayUrlsForRecoveryRaw(
          detail: entered,
          quality: const LivePlayQuality(quality: 'FLV 码率档 5', id: 'flv:5:1:2'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('lease queries match 3.x', () {
      final site = KugouLiveSite(ReplayHttp(const []));
      final now = DateTime.utc(2026, 9, 27, 18);
      final legacy = _legacy('S04-room-live')['lease'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final times = value as Map<String, dynamic>;
        expect(site.getPlayUrlInvalidAt(key)?.toIso8601String(), times['invalidAt'], reason: key);
        expect(site.getPlayUrlRefreshAt(key, now: now)?.toIso8601String(), times['refreshAt'], reason: key);
      }
      final resolved = ((_legacy('S04-room-live')['resolvePlayUrlsRaw'] as Map)['flv:4:1:2'] as Map)['value'] as Map;
      final url = (resolved['urls'] as List).first as String;
      expect(site.getPlayUrlRefreshAt(url, now: now)?.toIso8601String(), (resolved['refreshAt'] as List).first);
      final later = KugouLiveSite(ReplayHttp(const []), now: () => DateTime.utc(2027));
      expect(later.getPlayUrlRefreshAt(url), DateTime.utc(2027), reason: 'past: now');
    });
  });

  group('errors', () {
    test('transport failures, statuses and codes', () async {
      final failing = KugouLiveSite(
        _Scripted((request) => throw const TransportFailure('kugoulive', TransportReason.timeout)),
      );
      await expectLater(failing.getRecommendRooms(), throwsA(isA<NetworkFailure>()));
      final cancelled = KugouLiveSite(
        _Scripted((request) => throw const TransportFailure('kugoulive', TransportReason.cancelled)),
      );
      await expectLater(cancelled.getRoomDetail(roomId: '3197156'), _cancelled);
      for (final (status, matcher) in [
        (302, isA<NetworkFailure>()),
        (400, isA<ApiChanged>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (451, isA<RegionBlocked>()),
        (500, isA<NetworkFailure>()),
      ]) {
        final site = KugouLiveSite(_Scripted((request) => _response(request, '', status: status)));
        await expectLater(site.getRecommendRooms(), throwsA(matcher), reason: '$status');
        await expectLater(site.getRoomDetailForRefresh(roomId: '3197156'), throwsA(matcher), reason: '$status');
      }
      final busy = KugouLiveSite(
        _Scripted(
          (request) => _response(request, jsonEncode({'code': 110, 'msg': '系统繁忙', 'data': <String, Object?>{}})),
        ),
      );
      await expectLater(busy.getRecommendRooms(), throwsA(isA<ApiChanged>()));
      await expectLater(busy.getRoomDetail(roomId: '3197156'), throwsA(isA<ApiChanged>()));
    });
  });

  group('links', () {
    LinkParser parser(LiveHttp http) => LinkParser(SiteRegistry({'kugoulive': () => KugouLiveSite(http)}), http);

    test('room links in a share text, without a request', () async {
      final http = ReplayHttp(const []);
      for (final (text, id) in [
        ('酷狗直播 https://fanxing.kugou.com/3197156。快来', '3197156'),
        ('https://fanxing.kugou.com/5085706?refer=2177', '5085706'),
        ('看 https://mfanxing.kugou.com/?roomId=5085706 吧', '5085706'),
        ('http://mfanxing.kugou.com/3197156', '3197156'),
        // 29-4: the phone share page (recorded from the room page, 2026-09-28).
        (
          '快来看 http://mfanxing.kugou.com/staticPub/rmobile/sharePage/normalRoom/views/index.html?roomId=3197156 ',
          '3197156',
        ),
        ('https://mfanxing.kugou.com/share?roomId=5085706', '5085706'),
      ]) {
        expect(await parser(http).parse(text), RoomLink('kugoulive', id), reason: text);
      }
      expect(parser(http).containsSupportedLink('酷狗 https://fanxing.kugou.com/5085706'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('other pages and hosts are not rooms (3.x rules; fanxing2 blocked, 29-4)', () async {
      final http = ReplayHttp(const []);
      for (final text in [
        'https://fanxing.kugou.com/channel/5085706',
        'https://fanxing.kugou.com/pcindex/category/7024',
        'https://fanxing.kugou.com.evil.test/5085706',
        'https://user@fanxing.kugou.com/5085706',
        'https://fanxing.kugou.com:8443/5085706',
        'https://fanxing.kugou.com/12',
        'https://fanxing2.kugou.com/5085706',
        'https://mfanxing.kugou.com/staticPub/rmobile/sharePage/normalRoom/views/index.html',
      ]) {
        expect(await parser(http).parse(text), isNull, reason: text);
      }
      expect(http.requests, isEmpty);
    });
  });
}
