// SeventeenLiveSite over the recorded 17LIVE responses (ReplayHttp) and a few
// synthetic ones: the requests (URL, headers, redirects) and their number,
// compared with the requests 3.x made (expected.json), the cursor directory
// and its page-number replay, the regions (33-1), search by room and by
// keyword, room details for entry, refresh and recording, streams with their
// lines, "优先 H.264" and recovery, locked lives, cancellation, links through
// the link parser and the error mapping. Differences from 3.x name their
// docs/specs/UPGRADES.md row (33-x).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/17live';
const _live = '27484154';
const _offline = '28371376';
const _missing = '999999999';
const _army = '376827';

/// 3.x's quality ids → the current ones (33-2).
const _qualityIds = {'enhanced': 'enhanced', 'hd': 'hd', 'h264': 'h264', 'standard': 'source'};

/// A 3.x pull URL as the current code gives it: always https (33-3).
String _https(Object? url) => '$url'.replaceFirst(RegExp('^http://'), 'https://');

/// 3.x's [urls] of quality [id] as the adapter gives them: over https
/// (33-3), without Wansu's H.264 transcode, which is not served (E03.18).
List<String> _served(String id, Object? urls) => [
  for (final url in urls! as List)
    if (id != 'h264' || !'$url'.contains('://wansu-')) _https(url),
];

LiveArea _area(String id) => SeventeenLiveApi.areas.singleWhere((area) => area.areaId == id);

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

typedef _Setup = ({SeventeenLiveSite site, ReplayHttp http});

_Setup _setup(List<String> samples) {
  final http = ReplayHttp.fixtures(_root, samples);
  return (site: SeventeenLiveSite(http), http: http);
}

Map<String, dynamic> _legacy(String sample) => Fixture.load('17live', sample).legacy as Map<String, dynamic>;

/// The requests 3.x made for [key] of [sample].
List<String> _legacyRequests(String sample, String key) =>
    ((_legacy(sample)[key] as Map<String, dynamic>)['requests'] as List).cast<String>();

Object? _legacyValue(String sample, String key) => (_legacy(sample)[key] as Map<String, dynamic>)['value'];

List<String> _urls(List<LiveRequest> requests) => [for (final request in requests) '${request.url}'];

List<String> _ids(Iterable<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

List<Object?> _legacyIds(Object? rooms) => [for (final room in rooms! as List) (room as Map)['roomId']];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// A `lives/<id>` answer for room 123.
String _lives({int status = 2, Object? providers, Map<String, Object?> changes = const {}}) => jsonEncode({
  'liveStreamID': 123,
  'userID': 'uid',
  'status': status,
  'caption': 'Title',
  'liveViewerCount': 4,
  'viewerCount': 9,
  'userInfo': {'roomID': 123, 'userID': 'uid', 'displayName': 'Name', 'followerCount': 1},
  'pullURLsInfo': {
    'rtmpURLs':
        providers ??
        [
          {
            'url': 'http://tencent-global-pull-rtmp.17app.co/live/uid.flv',
            'url264': 'http://tencent-global-pull-rtmp.17app.co/live/uid_h264.flv',
          },
        ],
  },
  ...changes,
});

void main() {
  test('the adapter: id, name, capabilities, directory notice, a catalog without a request, no danmaku', () async {
    final http = ReplayHttp(const []);
    final site = SeventeenLiveSite(http);
    expect(site.id, '17live');
    expect(site.id, SiteIds.seventeenLive);
    expect(site.name, '17LIVE');
    expect(site.name, _legacy('S01-sections-jp')['name']);
    expect(site.directoryNoticeKey, 'seventeen_directory_scope');
    expect(site.directoryNoticeKey, _legacy('S01-sections-jp')['directoryNoticeKey']);
    expect(site, isA<LiveSiteLinks>());
    expect(site, isA<LiveSiteCursorDirectoryPager>());
    expect(site, isA<LiveDirectoryNotice>());
    expect(site, isA<LiveCancellableSearch>());
    expect(site, isA<LiveSiteRoomRefresher>());
    expect(site, isA<LiveSiteRecordRoomResolver>());
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isNot(isA<LiveSearchPaginationPolicy>()));
    expect(site, isNot(isA<LivePlayLeaseMetadata>()));
    // changed: 3.x had no catalog (its LiveSite default); 33-1.
    final categories = await site.getCategories(1, 30);
    expect(categories.single.id, 'region');
    expect(categories.single.children.map((area) => area.areaId), ['JP', 'TW', 'HK']);
    expect(await site.getCategories(2, 30), isEmpty);
    expect(await site.searchAnchors('a'), isEmpty);
    expect(http.requests, isEmpty);
  });

  group('directory', () {
    test("page 1: one request with 3.x's URL and headers, no redirects", () async {
      final setup = _setup(['S01-sections-jp']);
      final page = await setup.site.getDirectoryPageAtCursor(page: 1);
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp', 'getDirectoryPageAtCursor(1)'));
      final request = setup.http.requests.single;
      expect(
        request.url.toString(),
        'https://api-dsa.17app.co/api/v1/sections?count=20&typeTab=2&region=JP&cursor',
        reason: "3.x's Uri writes an empty cursor without '='",
      );
      expect(request.headers, SeventeenLiveApi.catalogHeaders);
      expect(request.followRedirects, isFalse);
      expect(request.site, '17live');
      final legacy = _legacyValue('S01-sections-jp', 'getDirectoryPageAtCursor(1)')! as Map<String, dynamic>;
      expect(page.page, 1);
      expect(_ids(page.rooms), _legacyIds(legacy['rooms']));
      expect(page.nextCursor, legacy['nextCursor']);
      expect(page.hasMore, isTrue);
    });

    test('page 2 by cursor: one request carrying the cursor as 3.x sent it', () async {
      final setup = _setup(['S01-sections-jp-p2']);
      final cursor = _legacy('S01-sections-jp-p2')['cursor'] as String;
      final page = await setup.site.getDirectoryPageAtCursor(page: 2, cursor: cursor);
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp-p2', 'getDirectoryPageAtCursor(2)'));
      expect(setup.http.requests.single.url.queryParameters['cursor'], cursor);
      expect(page.page, 2);
      expect(_ids(page.rooms), ['28571668']);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('by page number: replayed from page 1, as many requests as 3.x', () async {
      final setup = _setup(['S01-sections-jp', 'S01-sections-jp-p2']);
      final second = await setup.site.getDirectoryPage(page: 2);
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp-p2', 'getDirectoryPage(2)'));
      expect(
        _ids(second.rooms),
        _legacyIds((_legacyValue('S01-sections-jp-p2', 'getDirectoryPage(2)')! as Map)['rooms']),
      );
      setup.http.requests.clear();
      final third = await setup.site.getDirectoryPage(page: 3);
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp-p2', 'getDirectoryPage(3)'));
      expect(third.rooms, isEmpty);
      expect(third.page, 3);
      expect(third.hasMore, isFalse);
      setup.http.requests.clear();
      final first = await setup.site.getDirectoryPage();
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp', 'getDirectoryPage(1)'));
      expect(first.rooms, hasLength(30));
    });

    test('recommendations: the first pageSize rooms of the page (3.x)', () async {
      final setup = _setup(['S01-sections-jp']);
      expect(
        _ids(await setup.site.getRecommendRooms()),
        _legacyIds(_legacyValue('S01-sections-jp', 'getRecommendRooms(1)')),
      );
      expect(
        _ids(await setup.site.getRecommendRooms(pageSize: 5)),
        _legacyIds(_legacyValue('S01-sections-jp', 'getRecommendRooms(1, pageSize 5)')),
      );
      expect(setup.http.requests, hasLength(2));
    });

    test('caller errors are refused before any request (3.x: schema)', () async {
      final setup = _setup(const []);
      final site = setup.site;
      await expectLater(site.getDirectoryPageAtCursor(page: 0), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPageAtCursor(page: 1, cursor: 'x'), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 2), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 2, cursor: ''), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 2, cursor: 'x' * 513), throwsArgumentError);
      await expectLater(site.getDirectoryPageAtCursor(page: 2, cursor: 'a\tb'), throwsArgumentError);
      // 3.x refused every area (it had none); now only one that is not a
      // region (33-1).
      for (final area in [
        const LiveArea(platform: '17live', areaId: 'US'),
        const LiveArea(platform: 'showroom', areaId: 'JP'),
      ]) {
        await expectLater(site.getDirectoryPageAtCursor(page: 1, category: area), throwsArgumentError);
        await expectLater(site.getDirectoryPage(category: area), throwsArgumentError);
        await expectLater(site.getCategoryRooms(area), throwsArgumentError);
      }
      await expectLater(site.getDirectoryPage(page: 0), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPage(page: 21), throwsA(isA<RangeError>()));
      await expectLater(site.getDirectoryPage(page: 21, category: _area('TW')), throwsA(isA<RangeError>()));
      await expectLater(site.getRecommendRooms(pageSize: 0), throwsA(isA<RangeError>()));
      await expectLater(site.getCategoryRooms(_area('HK'), pageSize: 0), throwsA(isA<RangeError>()));
      expect(setup.http.requests, isEmpty);
      for (final key in [
        'getDirectoryPageAtCursor(0)',
        'getDirectoryPageAtCursor(1, cursor)',
        'getDirectoryPageAtCursor(2, no cursor)',
        'getDirectoryPageAtCursor(2, blank cursor)',
        'getDirectoryPageAtCursor(1, category)',
        'getDirectoryPage(0)',
        'getDirectoryPage(21)',
        'getRecommendRooms(1, pageSize 0)',
      ]) {
        expect(_legacyRequests('S01-sections-jp', key), isEmpty, reason: key);
      }
    });

    test('33-1: a region is its sections page, one request by cursor, with the headers of the directory', () async {
      final setup = _setup(['S02-sections-tw', 'S02-sections-hk']);
      for (final (id, sample, count) in [('TW', 'S02-sections-tw', 20), ('HK', 'S02-sections-hk', 32)]) {
        setup.http.requests.clear();
        final page = await setup.site.getDirectoryPageAtCursor(page: 1, category: _area(id));
        final request = setup.http.requests.single;
        expect(
          request.url.toString(),
          'https://api-dsa.17app.co/api/v1/sections?count=20&typeTab=2&region=$id&cursor',
          reason: sample,
        );
        expect(request.headers, SeventeenLiveApi.catalogHeaders);
        expect(request.followRedirects, isFalse);
        expect(page.rooms, hasLength(count));
        expect(page.hasMore, isTrue);
        setup.http.requests.clear();
        final rooms = await setup.site.getCategoryRooms(_area(id), pageSize: 5);
        expect(rooms.map((room) => room.roomId), page.rooms.take(5).map((room) => room.roomId));
        expect(setup.http.requests, hasLength(1));
      }
      final tw = _legacyValue('S02-sections-tw', 'getDirectoryPageAtCursor(1)')! as Map<String, dynamic>;
      setup.http.requests.clear();
      final page = await setup.site.getDirectoryPage(category: _area('TW'));
      expect(_ids(page.rooms), _legacyIds(tw['rooms']), reason: "the same rooms 3.x's parser read");
      expect(page.nextCursor, tw['nextCursor']);
      expect(setup.http.requests, hasLength(1));
    });

    test('33-1: Japan by area is the recommendations; page N of a region replays that region', () async {
      final setup = _setup(['S01-sections-jp', 'S01-sections-jp-p2']);
      final byArea = await setup.site.getDirectoryPage(page: 2, category: _area('JP'));
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp-p2', 'getDirectoryPage(2)'));
      expect(_ids(byArea.rooms), ['28571668']);
      setup.http.requests.clear();
      expect(
        _ids(await setup.site.getCategoryRooms(_area('JP'))),
        _legacyIds(_legacyValue('S01-sections-jp', 'getRecommendRooms(1)')),
      );
      expect(_urls(setup.http.requests), _legacyRequests('S01-sections-jp', 'getRecommendRooms(1)'));
      final stored = LiveArea.fromJson(_area('HK').toJson());
      final http = _Scripted((request) {
        final cursor = request.url.queryParameters['cursor']!;
        return _response(request, jsonEncode({'cursor': cursor.isEmpty ? 'hk-2' : '', 'sections': <Object?>[]}));
      });
      final hk = await SeventeenLiveSite(http).getDirectoryPage(page: 3, category: stored);
      expect(hk.rooms, isEmpty);
      expect(http.requests.map((request) => request.url.queryParameters['region']), ['HK', 'HK']);
      expect(http.requests.map((request) => request.url.queryParameters['cursor']), ['', 'hk-2']);
    });

    test('cancellation: before the request, and while it runs', () async {
      final before = CancelToken()..cancel();
      final idle = _Scripted((request) => throw StateError('unexpected'));
      await expectLater(SeventeenLiveSite(idle).getDirectoryPageAtCursor(page: 1, cancel: before), _cancelled);
      expect(idle.requests, isEmpty);
      final during = CancelToken();
      final http = _Scripted((request) {
        during.cancel();
        return _response(request, jsonEncode({'cursor': 'next', 'sections': <Object?>[]}));
      });
      await expectLater(SeventeenLiveSite(http).getDirectoryPage(page: 3, cancel: during), _cancelled);
      expect(http.requests, hasLength(1), reason: 'the replay stops');
      expect(http.requests.single.cancel, same(during));
    });
  });

  group('search', () {
    test("a keyword: one request with 3.x's URL and headers", () async {
      final setup = _setup(['S03-search']);
      final rooms = await setup.site.searchRooms(' 花音 ');
      expect(_urls(setup.http.requests), _legacyRequests('S03-search', 'searchRooms'));
      final request = setup.http.requests.single;
      expect(request.url.path, '/api/v1/liveStreams/search');
      expect(request.url.queryParameters, {'query': '花音'});
      expect(request.headers, SeventeenLiveApi.catalogHeaders);
      expect(request.followRedirects, isFalse);
      expect(_ids(rooms), _legacyIds(_legacyValue('S03-search', 'searchRooms')));
      expect(rooms.single.data, isNull);
      final none = _setup(['S03-search-none']);
      expect(await none.site.searchRooms('zxqvnothingfixture'), isEmpty);
    });

    test('one page only, cut to pageSize (3.x)', () async {
      final setup = _setup(['S03-search']);
      expect(
        _ids(await setup.site.searchRooms('花音', pageSize: 1)),
        _legacyIds(_legacyValue('S03-search', 'searchRooms(pageSize 1)')),
      );
      setup.http.requests.clear();
      expect(await setup.site.searchRooms('花音', page: 2), isEmpty);
      expect(await setup.site.searchRooms('花音', page: 0), isEmpty);
      expect(await setup.site.searchRooms('花音', pageSize: 0), isEmpty);
      expect(setup.http.requests, isEmpty);
      expect(_legacyRequests('S03-search', 'searchRooms(page 2)'), isEmpty);
      final many = _Scripted(
        (request) => _response(
          request,
          jsonEncode([
            for (var id = 1; id <= 5; id++)
              {
                'liveStreamID': id,
                'userID': 'u$id',
                'status': 2,
                'userInfo': {'roomID': id, 'userID': 'u$id', 'displayName': 'n$id'},
              },
          ]),
        ),
      );
      expect(_ids(await SeventeenLiveSite(many).searchRooms('n', pageSize: 3)), ['1', '2', '3']);
    });

    test('nothing to search, no request: blank, or a web address that is not a room (3.x)', () async {
      final setup = _setup(const []);
      for (final keyword in [
        '',
        '   ',
        'https://other.test/live/123',
        'https://m.17.live/ja/live/$_live',
        'https://17.live/ja/live/%FF',
        'https://17.live/ja/profile/$_live',
      ]) {
        expect(await setup.site.searchRooms(keyword), isEmpty, reason: keyword);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('33-5: a keyword with a colon is searched; one over 100 characters is cut (3.x: no request)', () async {
      final http = _Scripted((request) => _response(request, '[]'));
      final site = SeventeenLiveSite(http);
      final long = '${'x' * 99}😀 tail';
      for (final (keyword, sent) in [
        (' Re:Zero ', 'Re:Zero'),
        ('mailto:someone', 'mailto:someone'),
        ('x' * 101, 'x' * 100),
        (long, 'x' * 99),
      ]) {
        http.requests.clear();
        expect(await site.searchRooms(keyword), isEmpty, reason: keyword);
        expect(http.requests.single.url.path, '/api/v1/liveStreams/search');
        expect(http.requests.single.url.queryParameters, {'query': sent}, reason: keyword);
      }
      expect(Uri.tryParse('Re:Zero')?.hasScheme, isTrue, reason: 'why 3.x refused it');
    });

    test('a room id or link: one lives request, live or not, as 3.x', () async {
      for (final (sample, id) in [('S04-live-live', _live), ('S04-live-offline', _offline)]) {
        for (final (key, keyword) in [
          ('searchRooms(id)', id),
          ('searchRooms(live link)', ' https://17.live/ja/live/$id '),
          ('searchRooms(profile link)', 'https://17.live/en/profile/r/$id'),
        ]) {
          final setup = _setup([sample]);
          final rooms = await setup.site.searchRooms(keyword);
          expect(_urls(setup.http.requests), _legacyRequests(sample, key), reason: '$sample $key');
          expect(setup.http.requests.single.headers, SeventeenLiveApi.requestHeaders(id));
          expect(_ids(rooms), _legacyIds(_legacyValue(sample, key)), reason: '$sample $key');
          expect(rooms.single.data, isNull, reason: 'a card, not an entered room');
        }
        final setup = _setup([sample]);
        expect(await setup.site.searchRooms(id, page: 2), isEmpty);
        expect(setup.http.requests, isEmpty);
      }
    });

    test('33-6: a www.17.live link finds its room with one lives request (3.x: nothing)', () async {
      final setup = _setup(['S04-live-live']);
      final rooms = await setup.site.searchRooms('https://www.17.live/ja/live/$_live');
      expect(_urls(setup.http.requests), ['https://api-dsa.17app.co/api/v1/lives/$_live']);
      expect(_ids(rooms), [_live]);
      expect(rooms.single.startedAt, DateTime.utc(2026, 9, 27, 17, 54, 44), reason: '33-7');
    });

    test('a room that does not exist finds nothing (3.x failed on HTTP 520); other failures stay', () async {
      for (final keyword in [_missing, 'https://17.live/ja/live/$_missing']) {
        final setup = _setup(['S04-live-notfound']);
        expect(await setup.site.searchRooms(keyword), isEmpty, reason: keyword);
        expect(setup.http.requests, hasLength(1));
        expect((_legacyValue('S04-live-notfound', 'searchRooms(id)')! as Map)['message'], '17LIVE service');
      }
      final denied = SeventeenLiveSite(_Scripted((request) => _response(request, '', status: 403)));
      await expectLater(denied.searchRooms(_live), throwsA(isA<RiskControl>()));
      await expectLater(denied.searchRooms('花音'), throwsA(isA<RiskControl>()));
    });

    test('cancellation reaches the request', () async {
      final before = CancelToken()..cancel();
      final idle = _Scripted((request) => throw StateError('unexpected'));
      await expectLater(SeventeenLiveSite(idle).searchRoomsWithCancellation('花音', cancel: before), _cancelled);
      await expectLater(SeventeenLiveSite(idle).searchRoomsCancellable(_live, cancel: before), _cancelled);
      expect(idle.requests, isEmpty);
      final token = CancelToken();
      final http = _Scripted((request) {
        token.cancel();
        return _response(request, '[]');
      });
      await expectLater(SeventeenLiveSite(http).searchRoomsCancellable('花音', cancel: token), _cancelled);
      expect(http.requests.single.cancel, same(token));
    });
  });

  group('rooms', () {
    test("entry, refresh, recording, state: one request each, 3.x's URL and headers", () async {
      for (final (sample, id) in [('S04-live-live', _live), ('S04-live-offline', _offline)]) {
        final setup = _setup([sample]);
        final site = setup.site;
        for (final (key, call) in [
          ('getRoomDetail', () => site.getRoomDetail(roomId: id)),
          ('getRoomDetailForRefresh', () => site.getRoomDetailForRefresh(roomId: id)),
          ('getRoomDetailForRecording', () => site.getRoomDetailForRecording(roomId: id)),
        ]) {
          setup.http.requests.clear();
          final room = await call();
          expect(_urls(setup.http.requests), _legacyRequests(sample, key), reason: '$sample $key');
          final request = setup.http.requests.single;
          expect(request.url.toString(), 'https://api-dsa.17app.co/api/v1/lives/$id');
          expect(request.headers, SeventeenLiveApi.requestHeaders(id));
          expect(request.headers['referer'], 'https://17.live/en/live/$id');
          expect(request.followRedirects, isFalse);
          final legacy = _legacyValue(sample, key)! as Map<String, dynamic>;
          expect(room.roomId, legacy['roomId']);
          expect(room.liveStatus!.index, legacy['liveStatus']);
          expect(room.data, key == 'getRoomDetailForRefresh' ? isNull : isA<SeventeenLiveRoomData>());
        }
        setup.http.requests.clear();
        expect(await site.getLiveStatus(roomId: id), _legacyValue(sample, 'getLiveStatus'));
        expect(_urls(setup.http.requests), _legacyRequests(sample, 'getLiveStatus'));
      }
    });

    test('an unknown room is NotFound (REG-17LIVE-004); 3.x said service', () async {
      final setup = _setup(['S04-live-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRecording(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: _missing), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(4));
      expect(_legacyRequests('S04-live-notfound', 'getRoomDetail'), hasLength(1));
    });

    test('an id that is not a room id is NotFound without a request (3.x: identity)', () async {
      final setup = _setup(const []);
      for (final id in ['', 'abc', '0123', '1234567890123', '12/3', '-1']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      expect(_legacyRequests('S04-live-live', 'getRoomDetail(not a room id)'), isEmpty);
    });

    test('a state 3.x did not know: the room shows it, the live state is an error', () async {
      final http = _Scripted((request) => _response(request, _lives(status: 1)));
      final site = SeventeenLiveSite(http);
      expect((await site.getRoomDetailForRefresh(roomId: '123')).liveStatus, LiveStatus.unknown);
      await expectLater(site.getLiveStatus(roomId: '123'), throwsA(isA<ApiChanged>()));
      final room = await site.getRoomDetail(roomId: '123');
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));
    });

    test('pull data that cannot be read: entered (3.x failed the entry), playing it is ApiChanged', () async {
      final http = _Scripted((request) => _response(request, _lives(providers: 'x')));
      final site = SeventeenLiveSite(http);
      final room = await site.getRoomDetail(roomId: '123');
      expect(room.isLiveNow, isTrue);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));
      expect((await site.getRoomDetailForRecording(roomId: '123')).isLiveNow, isTrue);
      expect((await site.getRoomDetailForRefresh(roomId: '123')).isLiveNow, isTrue);
      expect(http.requests, hasLength(3), reason: 'the stream is not asked again');
    });

    test('an army-only live (S04-live-army): live and marked everywhere, not played, one request each', () async {
      final setup = _setup(['S04-live-army']);
      final site = setup.site;
      final entered = await site.getRoomDetail(roomId: _army);
      final refreshed = await site.getRoomDetailForRefresh(roomId: _army);
      final recording = await site.getRoomDetailForRecording(roomId: _army);
      final found = (await site.searchRooms(_army)).single;
      for (final room in [entered, refreshed, recording, found]) {
        expect(room.isLiveNow, isTrue);
        expect(room.restriction, LiveRestriction.subscribersOnly);
        expect(room.startedAt, DateTime.utc(2026, 9, 28, 20, 46, 5));
      }
      expect(await site.getLiveStatus(roomId: _army), isTrue);
      expect(setup.http.requests, hasLength(5));
      setup.http.requests.clear();
      await expectLater(site.getPlayQualities(detail: entered), throwsA(isA<StreamUnavailable>()));
      const quality = LivePlayQuality(quality: 'H.264 · FLV', id: 'h264');
      await expectLater(site.resolvePlayUrls(detail: entered, quality: quality), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: entered, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty, reason: 'room entry already knows');
      await expectLater(site.getPlayQualities(detail: refreshed), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(1), reason: 'a card is entered first');
    });

    test('33-4: room entry and recording carry the chat channel; refreshes and cards do not', () async {
      final setup = _setup(['S04-live-live', 'S01-sections-jp']);
      final site = setup.site;
      const args = SeventeenLiveDanmakuArgs(roomId: _live);
      expect((await site.getRoomDetail(roomId: _live)).danmakuData, args);
      expect((await site.getRoomDetailForRecording(roomId: _live)).danmakuData, args);
      expect((await site.getRoomDetailForRefresh(roomId: _live)).danmakuData, isNull);
      expect((await site.getRecommendRooms()).map((room) => room.danmakuData).toSet(), {null});
      expect(args.toString(), 'SeventeenLiveDanmakuArgs($_live)');
      expect(args.hashCode, const SeventeenLiveDanmakuArgs(roomId: _live).hashCode);
    });

    test('a refresh merges into the room 3.x stored: the identity is the room id', () async {
      final setup = _setup(['S04-live-live']);
      final stored = LiveRoom.fromJson({
        ...(_legacyValue('S04-live-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>),
        'tagIds': const ['t1'],
      });
      expect(stored.httpHeaders, isNotEmpty, reason: '3.x stored the media headers');
      final fresh = await setup.site.getRoomDetailForRefresh(roomId: stored.roomId);
      final merged = stored.mergeFrom(fresh);
      expect(merged.hasSameIdentity(stored), isTrue);
      expect(merged.identityKey, '17live:$_live');
      expect(merged.tagIds, ['t1']);
      expect(merged.onlineViewers, '108');
      expect(merged.httpHeaders, stored.httpHeaders, reason: 'kept as stored');
    });
  });

  group('streams', () {
    test('an entered room: qualities and URLs without a request, as 3.x (33-2 order and names, 33-3 https)', () async {
      final setup = _setup(['S04-live-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      // changed: 3.x's order was enhanced, hd, h264, standard (33-2).
      expect(qualities.map((q) => q.id), ['h264', 'source', 'enhanced', 'hd']);
      expect(qualities.first.quality, 'H.264 · FLV', reason: 'the default with 优先 H.264 on');
      final urls = _legacy('S04-live-live')['getPlayUrls'] as Map<String, dynamic>;
      for (final MapEntry(key: old, value: id) in _qualityIds.entries) {
        final quality = qualities.singleWhere((q) => q.id == id);
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.urls, _served(id, (urls[old] as Map)['value']), reason: old);
        expect(resolution.appliedQualityData, id);
        expect(resolution.lines.first.headers, SeventeenLiveApi.mediaHeaders(_live));
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), resolution.urls);
        final byOldId = await setup.site.resolvePlayUrls(
          detail: room,
          quality: LivePlayQuality(quality: 'x', id: old),
        );
        expect(byOldId.urls, resolution.urls, reason: "3.x's stored id still plays");
      }
      expect(setup.http.requests, isEmpty);
    });

    test('33-2: "优先 H.264" is read each time the qualities are listed; on by default', () async {
      var prefer = false;
      final setup = _setup(['S04-live-live']);
      final site = SeventeenLiveSite(setup.http, preferH264: () => prefer);
      final room = await site.getRoomDetail(roomId: _live);
      expect((await site.getPlayQualities(detail: room)).map((q) => q.id), ['source', 'enhanced', 'hd', 'h264']);
      expect((await site.getPlayQualities(detail: room)).first.quality, '原画 · FLV');
      prefer = true;
      expect((await site.getPlayQualities(detail: room)).map((q) => q.id), ['h264', 'source', 'enhanced', 'hd']);
      expect(setup.http.requests, hasLength(1));
      final byDefault = SeventeenLiveSite(setup.http);
      expect((await byDefault.getPlayQualities(detail: room)).first.id, 'h264');
    });

    test('recovery: room entry again, one request, same URLs as 3.x (over https, 33-3)', () async {
      final setup = _setup(['S04-live-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final recovered = _legacy('S04-live-live')['resolvePlayUrlsForRecoveryRaw'] as Map<String, dynamic>;
      for (final MapEntry(key: old, value: id) in _qualityIds.entries) {
        final quality = (await setup.site.getPlayQualities(detail: room)).singleWhere((q) => q.id == id);
        setup.http.requests.clear();
        final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
        final legacy = recovered[old] as Map<String, dynamic>;
        expect(_urls(setup.http.requests), legacy['requests']);
        expect(resolution.urls, _served(id, (legacy['value'] as Map)['urls']));
        expect((legacy['value'] as Map)['appliedQualityData'], old);
        expect(resolution.appliedQualityData, id, reason: '33-2: the current id');
      }
    });

    test('recovery when the quality is gone, or the room went offline', () async {
      var answer = _lives();
      final http = _Scripted((request) => _response(request, answer));
      final site = SeventeenLiveSite(http);
      final room = await site.getRoomDetail(roomId: '123');
      final hd = (await site.getPlayQualities(detail: room)).firstWhere((q) => q.id == 'hd');
      answer = _lives(
        providers: [
          {'url264': 'http://tencent-global-pull-rtmp.17app.co/live/uid_h264.flv'},
        ],
      );
      await expectLater(site.resolvePlayUrlsForRecovery(detail: room, quality: hd), throwsA(isA<StreamUnavailable>()));
      answer = _lives(status: 0);
      await expectLater(site.resolvePlayUrlsForRecovery(detail: room, quality: hd), throwsA(isA<StreamUnavailable>()));
      expect(http.requests, hasLength(3));
    });

    test('an offline room has no stream, without a request (3.x: an empty list, then mediaUnavailable)', () async {
      final setup = _setup(['S04-live-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      setup.http.requests.clear();
      const quality = LivePlayQuality(quality: 'hd', id: 'hd');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(setup.site.resolvePlayUrls(detail: room, quality: quality), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
      expect(_legacyValue('S04-live-offline', 'getPlayQualites'), isEmpty);
      final recovery = (_legacy('S04-live-offline')['resolvePlayUrlsForRecoveryRaw'] as Map)['hd'] as Map;
      expect(recovery['requests'], isEmpty);
      final card = LiveRoom(platform: '17live', roomId: _offline, liveStatus: LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, isEmpty);
    });

    test('a live room without a pull URL is entered; its stream says why (3.x failed the entry)', () async {
      final http = _Scripted((request) => _response(request, _lives(providers: const [])));
      final site = SeventeenLiveSite(http);
      final room = await site.getRoomDetail(roomId: '123');
      expect(room.isLiveNow, isTrue);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(http.requests, hasLength(1));
    });

    test('a card without playback (list, search, refreshed follow) is entered first (3.x: identity)', () async {
      final setup = _setup(['S01-sections-jp', 'S04-live-live']);
      final card = (await setup.site.getRecommendRooms()).firstWhere((room) => room.roomId == _live);
      expect(card.data, isNull);
      expect((_legacyValue('S01-sections-jp', 'getPlayQualites(list card)')! as Map)['message'], '17LIVE identity');
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: card);
      expect(qualities, hasLength(4));
      expect(_urls(setup.http.requests), ['https://api-dsa.17app.co/api/v1/lives/$_live']);
      final other = LiveRoom(
        platform: '17live',
        roomId: _live,
        userId: 'someone else',
        liveStatus: LiveStatus.live,
        data: (await setup.site.getRoomDetail(roomId: _live)).data,
      );
      setup.http.requests.clear();
      await setup.site.getPlayQualities(detail: other);
      expect(setup.http.requests, hasLength(1), reason: "another broadcaster's data is not used (3.x: identity)");
    });

    test('another platform is a caller error', () async {
      final site = SeventeenLiveSite(ReplayHttp(const []));
      final room = LiveRoom(platform: 'pandalive', roomId: _live, liveStatus: LiveStatus.live);
      await expectLater(site.getPlayQualities(detail: room), throwsArgumentError);
      expect((_legacyValue('S04-live-live', 'getRoomDetail(other platform)')! as Map)['message'], '17LIVE identity');
    });
  });

  group('errors', () {
    test('transport failures are NetworkFailure; a cancellation stays one', () async {
      for (final reason in [TransportReason.connect, TransportReason.timeout, TransportReason.tls]) {
        final site = SeventeenLiveSite(_Scripted((request) => throw TransportFailure('17live', reason)));
        await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()), reason: '$reason');
      }
      final cancelled = SeventeenLiveSite(
        _Scripted((request) => throw const TransportFailure('17live', TransportReason.cancelled)),
      );
      await expectLater(cancelled.searchRooms('a'), _cancelled);
    });

    test("statuses as 3.x's _fetch classed them, except 520 stream not found and 420", () async {
      for (final (status, body, matcher) in [
        (400, '', isA<ApiChanged>()),
        (401, '', isA<RiskControl>()),
        (403, '', isA<RiskControl>()),
        (404, '', isA<NotFound>()),
        (420, '{"errorCode":7,"errorMessage":"invalid channel type"}', isA<ApiChanged>()),
        (429, '', isA<RateLimited>()),
        (500, '', isA<NetworkFailure>()),
        (520, '{"errorCode":0,"errorMessage":"stream not found"}', isA<NotFound>()),
        (302, '', isA<NetworkFailure>()),
      ]) {
        final site = SeventeenLiveSite(_Scripted((request) => _response(request, body, status: status)));
        await expectLater(site.getRecommendRooms(), throwsA(matcher), reason: '$status');
      }
      final html = SeventeenLiveSite(_Scripted((request) => _response(request, '<html>')));
      await expectLater(html.getRoomDetailForRefresh(roomId: _live), throwsA(isA<ApiChanged>()));
    });
  });

  group('links', () {
    LinkParser parser(LiveHttp http) => LinkParser(SiteRegistry({'17live': () => SeventeenLiveSite(http)}), http);

    test('a live or profile page in a share text, without a request', () async {
      final http = ReplayHttp(const []);
      expect(await parser(http).parse('17LIVEで配信中 https://17.live/ja/live/$_live。见'), const RoomLink('17live', _live));
      expect(await parser(http).parse('https://17.live/en/profile/r/$_live'), const RoomLink('17live', _live));
      expect(parser(http).containsSupportedLink('https://17.live/live/$_live'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('33-6: a www.17.live page is a room too (3.x: not a link), without a request', () async {
      final http = ReplayHttp(const []);
      expect(await parser(http).parse('見て https://www.17.live/ja/live/$_live'), const RoomLink('17live', _live));
      expect(await parser(http).parse('https://WWW.17.live/profile/r/$_live'), const RoomLink('17live', _live));
      expect(parser(http).containsSupportedLink('https://www.17.live/live/$_live'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('other hosts and pages are not rooms (3.x); no short links', () async {
      final http = ReplayHttp(const []);
      expect(await parser(http).parse('https://m.17.live/ja/live/$_live'), isNull);
      expect(await parser(http).parse('https://17.live/ja/profile/$_live'), isNull);
      expect(parser(http).containsSupportedLink('https://17.live/'), isFalse);
      final site = SeventeenLiveSite(http);
      expect(site.needsResolving('https://17.live/ja/live/$_live'), isFalse);
      expect(site.roomIdsInShareText('https://17.live/ja/live/$_live'), isEmpty);
      expect(site.roomIdFromUrl('https://17.live/ja/live/%FF'), isNull, reason: '3.x threw FormatException');
      expect(http.requests, isEmpty);
    });
  });
}
