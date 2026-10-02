// JdLiveSite over the recorded JD Live responses (ReplayHttp) and a few
// synthetic ones: the request headers and query, the page sequences of the
// featured list, the search's lookups and filter, rooms at every depth with
// the playlist check, the list cards completing play answers, the streams
// and their recovery, cancellation, the deadline, links and the error
// mapping. Requests are compared with the ones 3.x sent (expected.json
// records them without the clock: `v`, `t` and the list's `timestamp`).
// Rooms differ from 3.x's only where listed with `changed:` and the reason
// (the M4.U upgrades by item number, docs/specs/UPGRADES.md 28-1 to 28-7).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/jdlive';
const _ignored = {'v', 't'};

/// The archived live room and old id, and the room recorded for M4.28.
const _archivedLive = '48378944';
const _archivedOld = '10000';
const _live = '48395626';

/// The clock values the samples were recorded with.
final DateTime _archivedClock = DateTime.fromMillisecondsSinceEpoch(1790533000000);
final DateTime _recordedClock = DateTime.fromMillisecondsSinceEpoch(1790600000000);
final DateTime _upgradeClock = DateTime.fromMillisecondsSinceEpoch(1790626000000);

const _archived = ['S01-list-p1', 'S01-list-p2', 'S02-play-live', 'S02-play-old'];
const _recorded = ['S04-list', 'S04-play-live', 'S04-playlist'];

/// Room keys every room changed: the notice is in words for users now (the
/// unified rule for developer notes, M4.U), and since M5.24 (chat is shown)
/// it only explains the number.
const _notice = {'notice'};

/// Room keys a play answer without a list card changed: 28-2 (no `JD Live`
/// title or shop name, no broadcast id as the shop account, no cover as the
/// avatar: all empty, so a follow keeps what it stored), 28-3 (the blurred
/// image is not the cover) and the notice.
const _playOnly = {'title', 'nick', 'userId', 'avatar', 'cover', 'notice'};

/// Room keys a play answer completed from a list card changed: 28-3 (the
/// card's cover instead of the blurred image) and the notice.
const _afterCard = {'cover', 'notice'};

/// Room keys of the old id changed besides [_playOnly]: status 3 without a
/// recording is an unplayable replay (the unified replay rule; 3.x:
/// offline).
const Set<String> _oldReplay = {..._playOnly, 'liveStatus', 'isRecord'};

Map<String, dynamic> _legacy(String sample) => Fixture.load('jdlive', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

/// 3.x's requests of a traced call, without the headers it wrote after the
/// URL.
List<String> _legacyRequests(Object? traced) => [
  for (final line in ((traced! as Map<String, dynamic>)['requests'] as List).cast<String>())
    line.split(' headers ').first,
];

String _withoutClock(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return body;
  return jsonEncode({...decoded}..remove('timestamp'));
}

/// A request as the legacy harness wrote it: the URL without the clock.
String _line(LiveRequest request) {
  final url = request.url;
  final pairs = [
    for (final MapEntry(:key, :value) in url.queryParameters.entries)
      if (!_ignored.contains(key)) '$key=${key == 'body' ? _withoutClock(value) : value}',
  ];
  return '${request.method} ${url.scheme}://${url.host}${url.path}${pairs.isEmpty ? '' : '?${pairs.join('&')}'}';
}

List<String> _sent(Iterable<LiveRequest> requests) => [for (final request in requests) _line(request)];

/// The list request's `timestamp`.
int _timestamp(LiveRequest request) =>
    (jsonDecode(request.url.queryParameters['body']!) as Map<String, dynamic>)['timestamp'] as int;

/// The list request's page.
int _page(LiveRequest request) =>
    (jsonDecode(request.url.queryParameters['body']!) as Map<String, dynamic>)['page'] as int;

typedef _Setup = ({JdLiveSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in samples) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: _ignored);
  return (site: JdLiveSite(http, now: now ?? () => _archivedClock), http: http);
}

_Setup _recordedSetup({List<ReplaySample> extra = const []}) =>
    _setup(_recorded, extra: extra, now: () => _recordedClock);

/// An answer to [url] with [body].
ReplaySample _answer(Uri url, String body, {int status = 200}) =>
    ReplaySample(method: 'GET', url: url, status: status, bytes: utf8.encode(body));

/// The playlist of stream [key]: S04-playlist's body under it, unless [body].
ReplaySample _playlist(String key, {String? body, int status = 200}) => _answer(
  Uri.parse('https://zt-pull-ai.jdcloud.com/live/${key}_fhd.m3u8'),
  body ?? Fixture.load('jdlive', 'S04-playlist').body.replaceAll('F366C61365FB1F9B4BC62D90DBE239B1', key),
  status: status,
);

const _archivedKey = '834C6A62B3177AB5FDD83B3EAC6DC6EA';

/// S02-play-live's JSON with `data` fields replaced.
String _editedPlay(Map<String, Object?> data) {
  final json = jsonDecode(Fixture.load('jdlive', 'S02-play-live').body) as Map<String, dynamic>;
  (json['data'] as Map<String, dynamic>).addAll(data);
  return jsonEncode(json);
}

/// A list page of [ids], all live.
String _listBody(Iterable<String> ids, {int count = 30}) => jsonEncode({
  'code': '0',
  'subCode': '0',
  'data': {
    'currentCount': count,
    'list': [
      for (final id in ids)
        {
          'templateType': 1,
          'data': {'id': int.parse(id), 'liveId': id, 'userName': 'shop $id', 'title': 'title $id', 'status': 1},
        },
    ],
  },
});

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
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw UnsupportedError('open');

  @override
  void close() {}
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('jdlive', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('jdlive', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// Asserts [room] equals 3.x's [legacy] projection on every key 3.x wrote,
/// except [changed]. 3.x wrote null where the immutable model writes ''.
void _expectParity(LiveRoom room, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = _notice, String reason = ''}) {
  final expected = legacy! as List;
  if (expected.isNotEmpty && expected.first is String) {
    expect(rooms.map((room) => room.roomId), expected, reason: reason);
    return;
  }
  expect(rooms.map((room) => room.roomId), [for (final room in expected) (room as Map)['roomId']], reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], changed: changed, reason: '$reason[$index]');
  }
}

String? _failure(Object? legacy) {
  if (legacy is! Map || legacy['throws'] != 'JdLiveException') return null;
  return (legacy['message']! as String).replaceFirst('JD Live ', '');
}

void main() {
  group('requests', () {
    test("3.x's headers and query, no redirects, as jdlive; the platform's names", () async {
      var now = _archivedClock;
      final setup = _setup(_archived, now: () => now);
      await setup.site.getDirectoryPage();
      now = now.add(const Duration(seconds: 5));
      await setup.site.getRoomDetailForRefresh(roomId: _archivedLive);
      final [list, play] = setup.http.requests;
      for (final request in setup.http.requests) {
        expect(request.headers, JdLiveApi.apiHeaders);
        expect(request.followRedirects, isFalse);
        expect((request.site, request.method), ('jdlive', 'GET'));
      }
      expect(list.url.queryParameters, {
        'appid': 'h5-live',
        'functionId': 'liveListWithTabToM',
        'v': '1790533000000',
        'body': '{"tabId":1,"currentCount":"0","page":1,"timestamp":1790533000000}',
      });
      expect(play.url.queryParameters, {
        'appid': 'h5-live',
        'functionId': 'getImmediatePlayToM',
        't': '1790533005000',
        'body': '{"liveId":"48378944"}',
      });
      expect(play.url.queryParameters.containsKey('h5st'), isFalse, reason: 'the play answer needs no signature (§10)');
      expect((setup.site.id, setup.site.name), ('jdlive', 'JD Live'));
      expect(setup.site.directoryNoticeKey, 'jdlive_directory_scope');
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no JD chat');
    });

    test("room entry downloads the live playlist with 3.x's media headers", () async {
      final setup = _recordedSetup();
      final legacy = (_legacy('S04-play-live')['recorded'] as Map<String, dynamic>)['getRoomDetail'];
      await setup.site.getRoomDetail(roomId: _live);
      expect(_sent(setup.http.requests), _legacyRequests(legacy));
      final media = setup.http.requests.last;
      expect(media.headers, JdLiveApi.mediaHeaders(_live));
      final legacyHeaders = jsonDecode(((legacy! as Map)['requests'] as List).last.toString().split(' headers ').last);
      expect(media.headers, {
        for (final MapEntry(:key, :value) in (legacyHeaders as Map<String, dynamic>).entries) key.toLowerCase(): value,
      });
      expect(media.followRedirects, isFalse);
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        JdLiveSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(JdLiveSite(_Failing(TransportReason.cancelled)).getRecommendRooms(), _cancelled);
      for (final (status, type) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (400, isA<ApiChanged>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(JdLiveSite(http).getRoomDetail(roomId: _live), throwsA(type), reason: '$status');
        await expectLater(JdLiveSite(http).getDirectoryPage(), throwsA(type), reason: '$status');
      }
      final html = _Scripted((request) => _response(request, '<html></html>'));
      await expectLater(JdLiveSite(html).getRecommendRooms(), throwsA(isA<ApiChanged>()));
      await expectLater(JdLiveSite(html).getRoomDetailForRefresh(roomId: _live), throwsA(isA<ApiChanged>()));
    });

    test("one 20 s deadline over the play answer and its playlist (3.x's scope)", () async {
      final http = _Scripted((request) => Completer<LiveResponse>().future);
      final site = JdLiveSite(http, deadline: const Duration(milliseconds: 30));
      await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()));
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      await expectLater(site.getDirectoryPage(), throwsA(isA<NetworkFailure>()));
      expect(JdLiveSite(http).deadline, const Duration(seconds: 20));
      final body = Fixture.load('jdlive', 'S04-play-live').body;
      final slow = _Scripted(
        (request) => request.url.host == 'api.m.jd.com'
            ? Future.delayed(const Duration(milliseconds: 20), () => _response(request, body))
            : Completer<LiveResponse>().future,
      );
      await expectLater(
        // A deadline the 20 ms answer always beats, even on a loaded machine.
        JdLiveSite(slow, deadline: const Duration(seconds: 1)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
        reason: 'the playlist counts against the same deadline',
      );
      expect(slow.requests, hasLength(2));
    });

    test("the caller's cancellation reaches the request and is reported as such", () async {
      final http = _Scripted((request) => Completer<LiveResponse>().future);
      final site = JdLiveSite(http);
      final token = CancelToken();
      final search = site.searchRoomsCancellable(_live, cancel: token);
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectLater(search, _cancelled);
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      await expectLater(site.searchRoomsCancellable('海信', cancel: token), _cancelled);
      await expectLater(site.getDirectoryPage(cancel: token), _cancelled);
      expect(http.requests, hasLength(1), reason: 'nothing is sent once cancelled');
    });
  });

  group('featured list', () {
    test("the directory: 3.x's rooms and requests, page by page; one timestamp per sequence", () async {
      var now = _archivedClock;
      final page3 = JdLiveApi.listUrl(page: 3, count: 67, timestamp: 1790533000000, now: _archivedClock);
      final setup = _setup(
        _archived,
        extra: [_answer(page3, '{"code":"0","subCode":"0","data":{"currentCount":67,"list":[]}}')],
        now: () => now,
      );
      final legacy = _legacy('S01-list-p1')['getDirectoryPage'] as Map<String, dynamic>;
      for (final page in [1, 2]) {
        final result = await setup.site.getDirectoryPage(page: page);
        final expected = _result(legacy['page $page'])! as Map<String, dynamic>;
        _expectRooms(result.rooms, expected['rooms'], reason: 'page $page');
        expect((result.page, result.hasMore), (expected['page'], expected['hasMore']));
        now = now.add(const Duration(minutes: 1));
      }
      final third = await setup.site.getDirectoryPage(page: 3);
      expect(third.rooms, isEmpty);
      expect(third.hasMore, isFalse);
      expect(_sent(setup.http.requests), [
        ..._legacyRequests(legacy['page 1']),
        ..._legacyRequests(legacy['page 2']),
        ..._legacyRequests(legacy['page 3']),
      ]);
      expect(setup.http.requests.map(_timestamp).toSet(), {1790533000000}, reason: '3.x: ${legacy['timestamps']}');
      expect(setup.http.requests.map((request) => request.url.queryParameters['v']), [
        '1790533000000',
        '1790533060000',
        '1790533120000',
      ]);
      expect((await setup.site.getDirectoryPage(page: 4)).rooms, isEmpty);
      expect(setup.http.requests, hasLength(3), reason: 'page 3 was the last');
      now = now.add(const Duration(minutes: 1));
      await expectLater(setup.site.getDirectoryPage(), throwsA(isA<StateError>()), reason: 'a new sequence, no sample');
      expect(_timestamp(setup.http.requests.last), now.millisecondsSinceEpoch);
    });

    test('the area, another area, page 0 and a page without its previous one (3.x)', () async {
      final setup = _setup(_archived);
      final legacy = _legacy('S01-list-p1')['getDirectoryPage'] as Map<String, dynamic>;
      final featured = await setup.site.getDirectoryPage(category: JdLiveApi.area);
      final expected = _result(legacy['featured page 1'])! as Map<String, dynamic>;
      expect(featured.rooms.map((room) => room.roomId), expected['roomIds']);
      final requests = setup.http.requests.length;
      for (final area in [
        const LiveArea(platform: 'jdlive', areaType: 'official', areaId: 'other'),
        const LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'featured'),
      ]) {
        expect(() => setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '3.x: identity');
      }
      final zero = await JdLiveSite(setup.http).getDirectoryPage(page: 0);
      expect(zero.rooms, isEmpty);
      expect((zero.page, zero.hasMore), (0, false));
      final second = await JdLiveSite(setup.http).getDirectoryPage(page: 2);
      expect((second.rooms.length, second.hasMore), (0, false));
      expect(setup.http.requests, hasLength(requests), reason: 'no request (3.x)');
      expect(_legacyRequests(legacy['page 0']), isEmpty);
      expect(_legacyRequests(legacy['page 2 first']), isEmpty);
    });

    test('28-1: S04 page 1 has 29 broadcasts; 3.x asked for no page 2, now pages go on until an empty one', () async {
      final ids = [
        for (final room in JdLiveApi.directory(Fixture.load('jdlive', 'S04-list').body, page: 1).rooms) room.liveId,
      ];
      final timestamp = _recordedClock.millisecondsSinceEpoch;
      // Page 2 repeats the first broadcast of page 1 and adds two; page 3 is
      // the empty end (S05-list-p8's shape).
      final setup = _recordedSetup(
        extra: [
          _answer(
            JdLiveApi.listUrl(page: 2, count: 36, timestamp: timestamp, now: _recordedClock),
            _listBody([ids.first, '48400001', '48400002'], count: 39),
          ),
          _answer(
            JdLiveApi.listUrl(page: 3, count: 39, timestamp: timestamp, now: _recordedClock),
            Fixture.load('jdlive', 'S05-list-p8').body.replaceFirst('"currentCount":215', '"currentCount":39'),
          ),
        ],
      );
      final legacy = _legacy('S04-list');
      final page = await setup.site.getDirectoryPage();
      final expected = _result((legacy['getDirectoryPage'] as Map<String, dynamic>)['page 1'])! as Map<String, dynamic>;
      _expectRooms(page.rooms, expected['rooms']);
      expect(expected['hasMore'], isFalse, reason: '3.x: fewer than 30 broadcasts');
      expect((page.rooms.length, page.hasMore), (29, true));
      final second = await setup.site.getDirectoryPage(page: 2);
      expect(second.rooms.map((room) => room.roomId), ['48400001', '48400002'], reason: 'page 1 listed the first');
      expect(second.hasMore, isTrue);
      final third = await setup.site.getDirectoryPage(page: 3);
      expect(third.rooms, isEmpty);
      expect(third.hasMore, isFalse);
      expect((await setup.site.getDirectoryPage(page: 4)).rooms, isEmpty);
      expect(setup.http.requests, hasLength(3), reason: 'page 4 is not asked for');
      expect(setup.http.requests.map(_timestamp).toSet(), {timestamp}, reason: 'one sequence');
      expect(
        [
          for (final request in setup.http.requests)
            (jsonDecode(request.url.queryParameters['body']!) as Map<String, dynamic>)['currentCount'],
        ],
        ['0', '36', '39'],
      );
      expect(await setup.site.getRecommendRooms(), hasLength(29));
      expect((await setup.site.getRecommendRooms(page: 2)).map((room) => room.roomId), ['48400001', '48400002']);
      expect(setup.http.requests, hasLength(5), reason: 'the recommendations are their own sequence');
    });

    test('28-1: a page with only broadcasts already listed ends the sequence (no endless paging)', () async {
      final http = _Scripted(
        (request) => _response(request, _listBody(['48000001', '48000002'], count: 2 * _page(request))),
      );
      final site = JdLiveSite(http);
      expect((await site.getDirectoryPage()).hasMore, isTrue);
      final again = await site.getDirectoryPage(page: 2);
      expect(again.rooms, isEmpty);
      expect(again.hasMore, isFalse);
      expect((await site.getDirectoryPage(page: 3)).rooms, isEmpty);
      expect(http.requests, hasLength(2));
      final first = await site.getDirectoryPage();
      expect(first.rooms, hasLength(2), reason: 'a new sequence lists them again');
    });

    test('recommendations and the area: their own sequence, cut to 30, sizes below 1 give nothing (3.x)', () async {
      final legacy = _legacy('S01-list-p1');
      final recommend = legacy['getRecommendRooms'] as Map<String, dynamic>;
      var setup = _setup(_archived);
      for (final page in [1, 2]) {
        final rooms = await setup.site.getRecommendRooms(page: page);
        _expectRooms(rooms, _result(recommend['page $page size 30']), reason: 'page $page');
      }
      expect(_sent(setup.http.requests), [
        ..._legacyRequests(recommend['page 1 size 30']),
        ..._legacyRequests(recommend['page 2 size 30']),
      ]);
      for (final (page, size) in [(1, 10), (1, 31), (1, 1), (0, 30), (1, 0), (2, 30)]) {
        setup = _setup(_archived);
        final rooms = await setup.site.getRecommendRooms(page: page, pageSize: size);
        final expected = recommend['fresh page $page size $size'];
        _expectRooms(rooms, _result(expected), reason: '$page $size');
        expect(_sent(setup.http.requests), _legacyRequests(expected), reason: '$page $size');
      }
      setup = _setup(_archived);
      await setup.site.getDirectoryPage();
      expect(await setup.site.getRecommendRooms(page: 2), isEmpty, reason: 'the directory is another sequence');
      expect(_legacyRequests(recommend['page 2 after directory page 1']), isEmpty);
      final area = legacy['getCategoryRooms'] as Map<String, dynamic>;
      setup = _setup(_archived);
      _expectRooms(await setup.site.getCategoryRooms(JdLiveApi.area), _result(area['featured page 1']));
      _expectRooms(await setup.site.getCategoryRooms(JdLiveApi.area, page: 2), _result(area['featured page 2']));
      _expectRooms(
        await _setup(_archived).site.getCategoryRooms(JdLiveApi.area, pageSize: 5),
        _result(area['featured page 1 size 5']),
      );
      expect(
        () => setup.site.getCategoryRooms(const LiveArea(platform: 'jdlive', areaType: 'official', areaId: 'other')),
        throwsArgumentError,
      );
    });

    test('the one category and its area, on page 1 with a size of at least 1; no request (3.x)', () async {
      final setup = _setup(const []);
      final legacy = _legacy('S01-list-p1');
      final category = (await setup.site.getCategories(1, 30)).single;
      final expected = (_result(legacy['getCategores'])! as List).single as Map<String, dynamic>;
      expect((category.id, category.name), (expected['id'], expected['name']));
      final area = category.children.single;
      final legacyArea = (expected['children'] as List).single as Map<String, dynamic>;
      for (final key in ['platform', 'areaType', 'typeName', 'areaId', 'areaName']) {
        expect(area.toJson()[key], legacyArea[key], reason: key);
      }
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(await setup.site.getCategories(1, 0), isEmpty);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('search', () {
    test("keywords: 3.x's results and requests; a link of another site is no result without a request", () async {
      final legacy = _legacy('S01-list-p1')['searchRoomsCancellable'] as Map<String, dynamic>;
      for (final keyword in [
        '海信',
        'obox',
        'OBOX',
        '0821',
        '旗舰店',
        ' 旗舰店 ',
        'zxqvnomatch',
        _archivedLive,
        _archivedOld,
        'https://lives.jd.com/#/$_archivedLive?origin=0',
        'https://lives.jd.com/#/$_archivedLive/live',
        'https://example.com/x',
        '  ',
      ]) {
        final setup = _setup(_archived);
        final rooms = await setup.site.searchRoomsCancellable(keyword, cancel: CancelToken());
        // An id or room link finds the room by its play answer alone.
        final changed = keyword == _archivedOld
            ? _oldReplay
            : JdLiveApi.liveIdOf(keyword) != null
            ? _playOnly
            : _notice;
        _expectRooms(rooms, _result(legacy[keyword]), changed: changed, reason: keyword);
        if (keyword == 'https://example.com/x') {
          expect(setup.http.requests, isEmpty, reason: '3.x filtered the list with the URL (1 request, no match)');
          expect(_legacyRequests(legacy[keyword]), hasLength(1));
        } else {
          expect(_sent(setup.http.requests), _legacyRequests(legacy[keyword]), reason: keyword);
        }
      }
      final withoutToken = await _setup(_archived).site.searchRooms('海信');
      _expectRooms(withoutToken, _result(legacy['海信 without a token']));
    });

    test("a keyword's pages: its own sequence; the size; page 2 first; a size over 100 (3.x)", () async {
      final legacy = _legacy('S01-list-p1')['searchRoomsCancellable'] as Map<String, dynamic>;
      final flow = legacy['旗舰店 page 1 then 2'] as Map<String, dynamic>;
      var setup = _setup(_archived);
      await setup.site.getDirectoryPage();
      final first = await setup.site.searchRoomsCancellable('旗舰店', cancel: CancelToken());
      final second = await setup.site.searchRoomsCancellable('旗舰店', page: 2, cancel: CancelToken());
      _expectRooms(first, _result(flow['page 1']));
      _expectRooms(second, _result(flow['page 2']));
      expect(_sent(setup.http.requests.skip(1)), [
        ..._legacyRequests(flow['page 1']),
        ..._legacyRequests(flow['page 2']),
      ]);
      for (final (name, page, size) in [
        ('旗舰店 page 2 first', 2, 30),
        ('旗舰店 size 3', 1, 3),
        ('旗舰店 size 100', 1, 100),
        ('旗舰店 size 101', 1, 101),
        ('$_archivedLive page 2', 2, 30),
      ]) {
        setup = _setup(_archived);
        final keyword = name.split(' ').first;
        final rooms = await setup.site.searchRoomsCancellable(keyword, page: page, pageSize: size);
        _expectRooms(rooms, _result(legacy[name]), changed: _playOnly, reason: name);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[name]), reason: name);
      }
      setup = _setup(_archived);
      expect(await setup.site.searchRooms('海信', page: 0), isEmpty);
      expect(await setup.site.searchRooms('海信', pageSize: 0), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test(
      'an exact lookup of a broadcast the site does not know is no result; other failures fail the search',
      () async {
        final notFound = _Scripted((request) => _response(request, '', status: 404));
        expect(await JdLiveSite(notFound).searchRooms(_live), isEmpty);
        final subCode = _Scripted((request) => _response(request, '{"code":"0","subCode":"1"}'));
        expect(await JdLiveSite(subCode).searchRooms('https://lives.jd.com/#/$_live'), isEmpty);
        final legacy = _legacy('S03-detail-403');
        expect(_result((legacy['status 404'] as Map<String, dynamic>)['searchRooms']), isEmpty);
        expect(_failure(_result((legacy['status 403'] as Map<String, dynamic>)['searchRooms'])), 'access');
        final forbidden = _Scripted((request) => _response(request, '', status: 403));
        await expectLater(JdLiveSite(forbidden).searchRooms(_live), throwsA(isA<RiskControl>()));
        expect(notFound.requests.single.url.queryParameters['functionId'], 'getImmediatePlayToM');
      },
    );

    test('search sequences beyond 32 keywords drop the oldest (3.x kept every one)', () async {
      final http = _Scripted(
        (request) => _response(request, _listBody([for (var i = 0; i < 30; i++) '${48000000 + i}'])),
      );
      final site = JdLiveSite(http);
      for (var i = 0; i < 33; i++) {
        await site.searchRooms('word$i');
      }
      expect(http.requests, hasLength(33));
      await site.searchRooms('word0', page: 2);
      expect(http.requests, hasLength(33), reason: 'the oldest search lost its sequence');
      await site.searchRooms('word1', page: 2);
      expect(http.requests, hasLength(34));
      await site.getDirectoryPage();
      await site.getDirectoryPage(page: 2);
      expect(http.requests, hasLength(36), reason: 'the directory is never dropped');
    });
  });

  group('rooms', () {
    test("S04 at every depth and its live status: 3.x's rooms and requests", () async {
      final legacy = _legacy('S04-play-live')['recorded'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _recordedSetup();
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          _ => setup.site.getRoomDetailForRecording(roomId: _live),
        };
        _expectParity(room, _result(legacy[depth]), changed: _playOnly, reason: depth);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: depth);
        expect(room.data, depth == 'getRoomDetailForRefresh' ? isNull : isA<JdLiveRoom>(), reason: depth);
        expect(
          room.danmakuData,
          depth == 'getRoomDetailForRefresh'
              ? isNull
              : isA<JdLiveDanmakuArgs>().having((args) => args.liveId, 'liveId', _live),
          reason: 'M5.24: the chat arguments come with the room, without a request ($depth)',
        );
        expect(room.roomId, _live);
        expect((room.restriction, room.startedAt), (LiveRestriction.none, null), reason: 'JD gives no start time');
      }
      final setup = _recordedSetup();
      expect(await setup.site.getLiveStatus(roomId: _live), _result(legacy['getLiveStatus']));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getLiveStatus']));
    });

    test("S02: refresh, room entry with S04's playlist under its key, and after the list (3.x)", () async {
      final legacy = _legacy('S02-play-live');
      final recorded = legacy['recorded'] as Map<String, dynamic>;
      var setup = _setup(_archived);
      _expectParity(
        await setup.site.getRoomDetailForRefresh(roomId: _archivedLive),
        _result(recorded['getRoomDetailForRefresh']),
        changed: _playOnly,
      );
      expect(_failure(_result(recorded['getRoomDetail'])), 'transport', reason: '3.x: no recorded playlist');
      final withPlaylist = legacy['withS04Playlist'] as Map<String, dynamic>;
      setup = _setup(_archived, extra: [_playlist(_archivedKey)]);
      final room = await setup.site.getRoomDetail(roomId: _archivedLive);
      _expectParity(room, _result(withPlaylist['getRoomDetail']), changed: _playOnly);
      expect(_sent(setup.http.requests), _legacyRequests(withPlaylist['getRoomDetail']));
      setup = _setup(_archived, extra: [_playlist(_archivedKey)]);
      await setup.site.getDirectoryPage();
      final after = (legacy['withS04Playlist after the list'] as Map<String, dynamic>)['getRoomDetail'];
      final entered = await setup.site.getRoomDetail(roomId: _archivedLive);
      _expectParity(entered, _result(after), changed: _afterCard);
      final card = (await _setup(_archived).site.getDirectoryPage()).rooms.first;
      expect(entered.cover, card.cover, reason: "28-3: the card's cover");
      expect((entered.data! as JdLiveRoom).background, (_result(after)! as Map)['cover'], reason: '28-3: background');
    });

    test("the list cards complete play answers, and the answer replaces the card (3.x's _known)", () async {
      final known = _legacy('S01-list-p1')['known'] as Map<String, dynamic>;
      var setup = _setup(_archived);
      final before = await setup.site.getRoomDetailForRefresh(roomId: _archivedLive);
      _expectParity(before, _result(known['getRoomDetailForRefresh before the list']), changed: _playOnly);
      expect((before.title, before.nick, before.userId, before.avatar, before.cover), ('', '', null, '', ''));
      await setup.site.getDirectoryPage();
      final after = await setup.site.getRoomDetailForRefresh(roomId: _archivedLive);
      _expectParity(after, _result(known['getRoomDetailForRefresh after the list']), changed: _afterCard);
      expect((after.title, after.nick, after.userId), ('有爱，科技也动情~~海信', '海信诚一恒专卖店', '24304104'));
      final search = await setup.site.searchRooms(_archivedLive);
      _expectParity(search.single, (_result(known['searchRooms after the list'])! as List).single, changed: _afterCard);
      setup = _setup(_archived);
      await setup.site.searchRooms('海信');
      _expectParity(
        await setup.site.getRoomDetailForRefresh(roomId: _archivedLive),
        _result(known['getRoomDetailForRefresh after a search']),
        changed: _afterCard,
      );
    });

    test('28-2: after a restart a refresh keeps the follow its shop name, title, account, avatar and cover', () async {
      final follow = (await _recordedSetup().site.getDirectoryPage()).rooms.first;
      final restarted = _recordedSetup();
      final refreshed = await restarted.site.getRoomDetailForRefresh(roomId: follow.roomId);
      expect(
        (refreshed.title, refreshed.nick, refreshed.userId, refreshed.avatar, refreshed.cover),
        ('', '', null, '', ''),
      );
      final merged = follow.mergeFrom(refreshed);
      expect((merged.title, merged.nick, merged.userId), ('国民喜糖徐福记优选', '徐福记食品店', '23924087'));
      expect((merged.avatar, merged.cover), (follow.avatar, follow.cover));
      expect((merged.liveStatus, merged.restriction), (LiveStatus.live, LiveRestriction.none));
      expect(restarted.http.requests, hasLength(1), reason: 'one request, as 3.x');
      final unnamed = LiveRoom(roomId: follow.roomId, platform: 'jdlive').mergeFrom(refreshed);
      expect(unnamed.displayNick('京东直播'), '京东直播', reason: 'the interface shows the platform name (M13)');
    });

    test('the cards kept are bounded: the oldest of more than 2000 is forgotten', () async {
      var page = 0;
      final play = Fixture.load('jdlive', 'S02-play-live').body;
      final http = _Scripted((request) {
        if (request.url.queryParameters['functionId'] == 'getImmediatePlayToM') {
          final id = (jsonDecode(request.url.queryParameters['body']!) as Map<String, dynamic>)['liveId'];
          return _response(request, play.replaceFirst('"liveId": $_archivedLive', '"liveId": $id'));
        }
        final start = 48000000 + page++ * 30;
        return _response(request, _listBody([for (var i = 0; i < 30; i++) '${start + i}'], count: page * 30));
      });
      final site = JdLiveSite(http);
      for (var i = 1; i <= 67; i++) {
        await site.getDirectoryPage(page: i);
      }
      expect(page, 67, reason: '2010 cards');
      expect((await site.getRoomDetailForRefresh(roomId: '48000000')).nick, isEmpty, reason: 'forgotten (28-2)');
      expect((await site.getRoomDetailForRefresh(roomId: '48002009')).nick, 'shop 48002009');
    });

    test('ids: a room link is read (3.x); not a broadcast id is NotFound without a request', () async {
      final legacy = _legacy('S04-play-live')['recorded'] as Map<String, dynamic>;
      final setup = _recordedSetup();
      final room = await setup.site.getRoomDetailForRefresh(roomId: 'https://lives.jd.com/#/$_live/live');
      _expectParity(room, _result(legacy['room link as id']), changed: _playOnly);
      expect(room.roomId, _live);
      for (final id in ['', 'abc', '1234', '0123456']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getLiveStatus(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('live status: live (app-only too), ended; paused and unknown are errors, never offline', () async {
      final legacy = _legacy('S02-play-live')['variants'] as Map<String, dynamic>;
      for (final (name, data, error) in [
        ('status text', <String, Object?>{'status': '1'}, null),
        ('status 2', <String, Object?>{'status': 2}, null),
        ('status 0', <String, Object?>{'status': 0}, null),
        ('status 3', <String, Object?>{'status': 3}, null),
        ('status 10', <String, Object?>{'status': 10}, isA<StreamUnavailable>()),
        ('status 11', <String, Object?>{'status': 11}, isA<StreamUnavailable>()),
        ('status 99', <String, Object?>{'status': 99}, isA<ApiChanged>()),
      ]) {
        final expected = (legacy[name] as Map<String, dynamic>)['getLiveStatus'];
        final http = _Scripted((request) => _response(request, _editedPlay(data)));
        final status = JdLiveSite(http).getLiveStatus(roomId: _archivedLive);
        if (error == null) {
          expect(await status, expected, reason: name);
        } else {
          expect(_failure(expected), 'access', reason: '3.x: $name');
          await expectLater(status, throwsA(error), reason: name);
        }
        expect(http.requests, hasLength(1));
      }
      // App-only is live (the unified rule for restricted broadcasts; 3.x:
      // `access`, NeedsLogin since M4.28).
      expect(_failure((legacy['secret 1'] as Map<String, dynamic>)['getLiveStatus']), 'access');
      final restricted = _Scripted((request) => _response(request, _editedPlay({'secret': 1})));
      expect(await JdLiveSite(restricted).getLiveStatus(roomId: _archivedLive), isTrue);
      final ended = _Scripted((request) => _response(request, _editedPlay({'secret': 1, 'status': 2})));
      expect(await JdLiveSite(ended).getLiveStatus(roomId: _archivedLive), isFalse);
      final old = _setup(_archived);
      expect(await old.site.getLiveStatus(roomId: _archivedOld), isFalse);
      final replay = _setup(['S05-play-replay'], now: () => _upgradeClock);
      expect(await replay.site.getLiveStatus(roomId: _live), isFalse, reason: 'a replay is not live');
    });

    test('the old id is an unplayable replay at every depth (status 3; 3.x: offline) and cannot be played', () async {
      final legacy = _legacy('S02-play-old')['recorded'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _setup(_archived);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _archivedOld),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _archivedOld),
          _ => setup.site.getRoomDetailForRecording(roomId: _archivedOld),
        };
        _expectParity(room, _result(legacy[depth]), changed: _oldReplay, reason: depth);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: 'no playlist when not live');
        expect((room.liveStatus, room.restriction), (LiveStatus.replay, LiveRestriction.unplayable));
        expect(room.followGroup, FollowGroup.offline);
        expect(_result(legacy['$depth → getPlayQualites']), anyOf(isEmpty, isA<Map<String, dynamic>>()));
        await expectLater(
          setup.site.getPlayQualities(detail: room),
          throwsA(isA<StreamUnavailable>()),
          reason: '3.x: [] for an offline room',
        );
      }
    });

    test('a replay: one request at every depth, its recording plays as "原画" with the media headers', () async {
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _setup(['S05-play-replay'], now: () => _upgradeClock);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          _ => setup.site.getRoomDetailForRecording(roomId: _live),
        };
        expect(setup.http.requests, hasLength(1), reason: '$depth: the recording is not downloaded');
        expect(
          (room.liveStatus, room.restriction, room.followGroup),
          (LiveStatus.replay, LiveRestriction.none, FollowGroup.replay),
        );
        if (depth == 'getRoomDetailForRefresh') continue;
        final qualities = await setup.site.getPlayQualities(detail: room);
        expect(qualities, [JdLiveApi.replayQuality]);
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.single);
        final line = resolution.lines.single;
        expect(line.url, startsWith('https://discover.300hu.com/m3u8/$_live/'));
        expect(line.format, StreamFormat.hls);
        expect(line.headers, JdLiveApi.mediaHeaders(_live), reason: '28-5');
        expect(resolution.appliedQualityData, JdLiveApi.replayId);
        await expectLater(
          setup.site.resolvePlayUrlsRaw(detail: room, quality: JdLiveApi.hlsQuality),
          throwsA(isA<StreamUnavailable>()),
          reason: 'the live stream ended',
        );
        expect(setup.http.requests, hasLength(1), reason: 'no request to play');
        final recovered = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: qualities.single);
        expect(recovered.urls, [line.url]);
        expect(setup.http.requests, hasLength(2), reason: 'recovery asks the play answer again, one request');
      }
    });

    test("the detail endpoint's empty 403 as the play answer: RiskControl at every depth (3.x: access)", () async {
      final legacy = _legacy('S03-detail-403')['status 403'] as Map<String, dynamic>;
      final url = Fixture.load('jdlive', 'S02-play-live').url;
      final setup = _setup(const [], extra: [_answer(url, Fixture.load('jdlive', 'S03-detail-403').body, status: 403)]);
      for (final call in <String, Future<Object?> Function()>{
        'getRoomDetail': () => setup.site.getRoomDetail(roomId: _archivedLive),
        'getRoomDetailForRefresh': () => setup.site.getRoomDetailForRefresh(roomId: _archivedLive),
        'getLiveStatus': () => setup.site.getLiveStatus(roomId: _archivedLive),
        'searchRooms': () => setup.site.searchRooms(_archivedLive),
      }.entries) {
        expect(_failure(_result(legacy[call.key])), 'access', reason: call.key);
        await expectLater(call.value(), throwsA(isA<RiskControl>()), reason: call.key);
      }
    });

    test('room entry fails with its playlist: 404 StreamUnavailable (3.x: missing), a bad one ApiChanged', () async {
      final legacy = _legacy('S04-play-live');
      final missing = _recordedSetup(extra: [_playlist('F366C61365FB1F9B4BC62D90DBE239B1', body: '', status: 404)]);
      await expectLater(missing.site.getRoomDetail(roomId: _live), throwsA(isA<StreamUnavailable>()));
      await expectLater(missing.site.getRoomDetailForRecording(roomId: _live), throwsA(isA<StreamUnavailable>()));
      final playlist404 = legacy['playlist 404'] as Map<String, dynamic>;
      expect(_failure(_result(playlist404['getRoomDetail'])), 'missing');
      _expectParity(
        await missing.site.getRoomDetailForRefresh(roomId: _live),
        _result(playlist404['getRoomDetailForRefresh']),
        changed: _playOnly,
        reason: 'refresh does not read the playlist',
      );
      final empty = _recordedSetup(extra: [_playlist('F366C61365FB1F9B4BC62D90DBE239B1', body: '#EXTM3U\n')]);
      expect(_failure(_result(legacy['empty playlist'])), 'schema');
      await expectLater(empty.site.getRoomDetail(roomId: _live), throwsA(isA<ApiChanged>()));
    });
  });

  group('streams', () {
    test("room entry and recording: 3.x's qualities and URLs, no request; lines with format and host", () async {
      final legacy = _legacy('S04-play-live')['recorded'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final setup = _recordedSetup();
        final room = depth == 'getRoomDetail'
            ? await setup.site.getRoomDetail(roomId: _live)
            : await setup.site.getRoomDetailForRecording(roomId: _live);
        final sent = setup.http.requests.length;
        final qualities = await setup.site.getPlayQualities(detail: room);
        final expected = (_result(legacy['$depth → getPlayQualites'])! as List).cast<Map<String, dynamic>>();
        expect(qualities.map((quality) => (quality.quality, quality.id, quality.sort)), [
          for (final quality in expected) (quality['quality'], quality['id'], quality['sort']),
        ]);
        for (final quality in qualities) {
          final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
          final legacyResolution =
              _result(legacy['$depth → resolvePlayUrlsRaw(${quality.id})'])! as Map<String, dynamic>;
          expect(resolution.urls, legacyResolution['urls']);
          expect(resolution.appliedQualityData, legacyResolution['appliedQualityData']);
          final line = resolution.lines.single;
          expect(line.format, quality.id == 'hls' ? StreamFormat.hls : StreamFormat.flv);
          expect(line.lineId, 'zt-pull-ai.jdcloud.com');
          expect(line.headers, JdLiveApi.mediaHeaders(_live), reason: "28-5 (3.x's player sent no JD headers)");
          expect(line.lease, isNull);
        }
        expect(
          await setup.site.getPlayUrls(detail: room, quality: JdLiveApi.flvQuality),
          _result(legacy['$depth → getPlayUrls(flv)']),
        );
        expect(setup.http.requests, hasLength(sent), reason: 'no request (3.x)');
        expect(_failure(_result(legacy['$depth → resolvePlayUrlsRaw(auto)'])), 'mediaUnavailable');
        await expectLater(
          setup.site.resolvePlayUrlsRaw(
            detail: room,
            quality: const LivePlayQuality(quality: 'auto', id: 'auto'),
          ),
          throwsArgumentError,
        );
      }
    });

    test('recovery asks the play answer and the playlist again (3.x, REG-LEASE-005)', () async {
      final legacy = _legacy('S04-play-live')['recorded'] as Map<String, dynamic>;
      final setup = _recordedSetup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final recovered = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: JdLiveApi.hlsQuality);
      final expected = legacy['getRoomDetail → resolvePlayUrlsForRecoveryRaw(hls)'];
      expect(recovered.urls, (_result(expected)! as Map<String, dynamic>)['urls']);
      expect(_sent(setup.http.requests), _legacyRequests(expected));
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(
          detail: room,
          quality: const LivePlayQuality(quality: 'x', id: 'x'),
        ),
        throwsArgumentError,
      );
      expect(setup.http.requests, hasLength(2), reason: 'another quality asks nothing');
      var ended = false;
      final http = _Scripted((request) {
        if (request.url.host != 'api.m.jd.com') return _response(request, Fixture.load('jdlive', 'S04-playlist').body);
        final body = Fixture.load('jdlive', 'S04-play-live').body;
        return _response(request, ended ? body.replaceFirst('"status":1,', '"status":2,') : body);
      });
      final site = JdLiveSite(http);
      final live = await site.getRoomDetail(roomId: _live);
      ended = true;
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: live, quality: JdLiveApi.flvQuality),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('cannot play: a card, a refresh or search room, offline or app-only rooms, another platform', () async {
      final setup = _recordedSetup();
      final card = (await setup.site.getDirectoryPage()).rooms.first;
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final search = (await setup.site.searchRooms(_live)).single;
      final legacy = _legacy('S04-play-live')['recorded'] as Map<String, dynamic>;
      expect(_failure(_result(legacy['getRoomDetailForRefresh → getPlayQualites'])), 'mediaUnavailable');
      for (final room in [card, refresh, search]) {
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
        await expectLater(
          setup.site.resolvePlayUrlsRaw(detail: room, quality: JdLiveApi.hlsQuality),
          throwsA(isA<StreamUnavailable>()),
        );
        await expectLater(
          setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: JdLiveApi.hlsQuality),
          throwsA(isA<StreamUnavailable>()),
          reason: '3.x checked the room before asking again',
        );
      }
      final restricted = _Scripted((request) => _response(request, _editedPlay({'secret': 1})));
      final site = JdLiveSite(restricted);
      final room = await site.getRoomDetail(roomId: _archivedLive);
      expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.appOnly), reason: '3.x: unknown');
      expect(room.notice, JdLiveApi.restrictedNotice);
      await expectLater(
        site.getPlayQualities(detail: room),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'reason', contains('app only'))),
        reason: 'M2.1: appOnly is StreamUnavailable with its reason (M4.28: NeedsLogin)',
      );
      expect(restricted.requests, hasLength(1), reason: 'no playlist for an app-only broadcast (3.x: 1 request)');
      final other = LiveRoom(roomId: _live, platform: 'bilibili', liveStatus: LiveStatus.live);
      expect(() => setup.site.getPlayQualities(detail: other), throwsArgumentError);
    });
  });

  group('links', () {
    test('lives.jd.com room links and share texts, through the link parser; no request', () async {
      final http = _Scripted((request) => throw StateError('no request'));
      final registry = SiteRegistry({'jdlive': () => JdLiveSite(http)});
      final parser = LinkParser(registry, http);
      expect(await parser.parse('看直播 https://lives.jd.com/#/$_live?origin=0 快来'), const RoomLink('jdlive', _live));
      expect(await parser.parse('https://lives.jd.com/#/$_live/live'), const RoomLink('jdlive', _live));
      expect(await parser.parse('http://lives.jd.com/#$_live。'), const RoomLink('jdlive', _live));
      expect(await parser.parse('https://lives.jd.com/'), isNull);
      expect(await parser.parse('https://lives.jd.com/#/$_live/other'), isNull);
      expect(await parser.parse('https://m.jd.com/product/$_live.html'), isNull);
      expect(await parser.parse(_live), isNull, reason: 'a bare id is not a link');
      expect(parser.containsSupportedLink('https://lives.jd.com/#/$_live'), isTrue);
      final site = registry.of('jdlive') as JdLiveSite;
      expect(site.roomIdFromUrl('https://lives.jd.com:8443/#/$_live'), isNull);
      expect(site.needsResolving('https://lives.jd.com/#/$_live'), isFalse);
      expect(http.requests, isEmpty);
    });
  });
}
