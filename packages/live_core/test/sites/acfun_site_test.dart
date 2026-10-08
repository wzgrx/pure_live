// AcfunSite over the recorded responses (ReplayHttp) and scripted answers:
// the requests 3.x made, the cursor paging of lists and search, the visitor
// session (one login for concurrent callers, five minutes, a refused session
// replaced once), room depths, streams and recovery, danmaku arguments,
// links and error mapping.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/acfun';

/// The visitor values the startPlay samples were recorded with are scrubbed.
const _session = {'userId', 'did', 'acfun.api.visitor_st'};

const _live = [
  'S05-info-live',
  'S05-info-offline',
  'S05-info-missing',
  'S06-visitor',
  'S06-startplay-live',
  'S06-startplay-offline',
];

Map<String, dynamic> _legacy(String name) => Fixture.load('acfun', name).legacy as Map<String, dynamic>;

/// 3.x's recommendation request (S01-list-all: 30 rooms, no filter).
Uri _recommendationUrl() => Uri.parse(((_legacy('S01-list-all')['requests'] as List).single as Map)['url'] as String);

/// 3.x's headers of a request it made, names in lower case (Dio's own
/// content type left out).
Map<String, String> _headers(Map<String, dynamic> request) => {
  for (final MapEntry(:key, :value) in (request['headers'] as Map<String, dynamic>).entries)
    if (key.toLowerCase() != 'content-type') key.toLowerCase(): '$value',
};

Map<String, String> _without(Map<String, String> headers, String name) => {
  for (final MapEntry(:key, :value) in headers.entries)
    if (key != name) key: value,
};

typedef _Setup = ({AcfunSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in samples) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: _session);
  return (site: AcfunSite(http, now: now, random: Random(7)), http: http);
}

/// Answers every request with [answer]: a `(status, body)` record, a body
/// (status 200), or a [TransportReason] to fail with.
final class _Scripted implements LiveHttp {
  new(this.answer);

  final FutureOr<Object> Function(LiveRequest request) answer;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final result = await answer(request);
    if (result is TransportReason) throw TransportFailure('acfun', result, 'scripted');
    final (status, body) = result is (int, String) ? result : (200, result is String ? result : jsonEncode(result));
    return LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}

  List<String> get paths => [for (final request in requests) request.url.path];
}

/// A `channel/list` answer with one room of [id] (or the rooms of [ids])
/// and cursor [next].
Map<String, Object?> _list(String next, {int id = 42, List<int>? ids}) => {
  'channelListData': {
    'result': 0,
    'pcursor': next,
    'liveList': [
      for (final id in ids ?? [id])
        {
          'authorId': id,
          'user': {'id': '$id', 'name': 'Fixture $id'},
          'liveId': 'live-$id',
          'onlineCount': 99,
        },
    ],
  },
  'channelFilters': {
    'liveChannelDisplayFilters': [
      {
        'displayFilters': [
          {'filterType': 1, 'filterId': 0, 'name': '全部'},
          {'filterType': 1, 'filterId': 4, 'name': '虚拟偶像'},
        ],
      },
    ],
  },
};

String _searchCard(int id) => [
  '<div class="search-up" data-up-exposure-log=\'{"up_id":$id,"is_on_live":""}\'>',
  '<div class="up__main__name"><a href="/u/$id">Fixture $id</a></div></div>',
].join();

/// A search answer holding [ids] of [total].
String _searchAnswer(Iterable<int> ids, {required int total}) =>
    '${jsonEncode({'html': '<span class="total-num" data-total="$total">共$total条结果</span>'
        '${ids.map(_searchCard).join()}${ids.isEmpty ? '<div class="empty-page"></div>' : ''}'})}/*<!-- fetch-stream -->*/';

/// Server page [page] of a search with authors 1…[total], 30 a page.
String _serverPage(int page, {int total = 75, Set<int> missing = const {}}) => _searchAnswer([
  for (var id = (page - 1) * 30 + 1; id <= page * 30 && id <= total; id++)
    if (!missing.contains(id)) id,
], total: total);

int _pCursor(LiveRequest request) => int.parse(request.url.queryParameters['pCursor']!);

/// A `live/info` answer for author 42.
Map<String, Object?> _info({bool live = true}) => {
  'result': 0,
  'authorId': 42,
  'user': {'id': '42', 'name': 'Fixture'},
  if (live) 'liveId': 'live-a',
};

/// A startPlay answer whose URLs carry [tag].
Map<String, Object?> _play(String tag, {bool high = true}) => {
  'result': 1,
  'data': {
    'liveId': 'live-$tag',
    'availableTickets': ['ticket-$tag'],
    'enterRoomAttach': 'attach-$tag',
    'videoPlayRes': jsonEncode({
      'liveAdaptiveManifest': [
        {
          'adaptationSet': {
            'representation': [
              {'qualityType': 'STANDARD', 'level': 30, 'url': 'https://cdn.example/$tag-low.flv', 'name': '高清'},
              if (high) {'qualityType': 'HIGH', 'level': 50, 'url': 'https://cdn.example/$tag-high.flv', 'name': '超清'},
            ],
          },
        },
      ],
    }),
  },
};

const Map<String, Object> _visitorAnswer = {
  'result': 0,
  'userId': 12345,
  'acfun.api.visitor_st': 'fixture-visitor-token',
};

void main() {
  group('catalog and lists', () {
    test("the catalog reads one room for the filters, with 3.x's request", () async {
      final setup = _setup(['S01-list-filters']);
      final categories = await setup.site.getCategories(1, 20);
      final legacy = _legacy('S01-list-filters');
      final category = categories.single;
      expect((category.id, category.name), ('acfun', 'AcFun 直播'));
      // changed: 10-2 leaves out 全部 (filter 0).
      expect(category.children.map((area) => area.areaId), [
        for (final area in ((legacy['getCategores'] as List).single as Map)['children'] as List)
          if ((area as Map)['areaId'] != '0') area['areaId'],
      ]);
      expect(category.children.map((area) => area.areaName), isNot(contains('全部')));
      final request = (legacy['requests'] as List).single as Map<String, dynamic>;
      expect(setup.http.requests.single.url, Uri.parse(request['url'] as String));
      expect(setup.http.requests.single.headers, _headers(request));
      expect(await setup.site.getCategories(2, 20), isEmpty);
      expect(setup.http.requests, hasLength(1));
    });

    test("recommendations: 3.x's request and rooms; the page after no_more is empty without a request", () async {
      final setup = _setup(['S01-list-all']);
      final rooms = await setup.site.getRecommendRooms();
      final legacy = _legacy('S01-list-all');
      expect(rooms.map((room) => room.roomId), [
        for (final room in legacy['getRecommendRooms'] as List) (room as Map)['roomId'],
      ]);
      final request = (legacy['requests'] as List).single as Map<String, dynamic>;
      expect(setup.http.requests.single.url, Uri.parse(request['url'] as String));
      expect(setup.http.requests.single.headers, _headers(request));
      expect(await setup.site.getRecommendRooms(page: 2), isEmpty);
      expect(legacy['page2'], isEmpty);
      expect(setup.http.requests, hasLength(1), reason: 'no more requests than 3.x');
    });

    test("area rooms: 3.x's filter request; other platforms' areas are NotFound without a request", () async {
      final setup = _setup(['S02-list-game']);
      const area = LiveArea(platform: 'acfun', areaType: '1', typeName: 'AcFun 直播', areaId: '1', areaName: '游戏');
      final rooms = await setup.site.getCategoryRooms(area);
      final legacy = _legacy('S02-list-game');
      expect(rooms, hasLength(8));
      final request = (legacy['requests'] as List).single as Map<String, dynamic>;
      expect(setup.http.requests.single.url, Uri.parse(request['url'] as String));
      for (final forged in const [
        LiveArea(platform: 'huya', areaType: '1', areaId: '1'),
        LiveArea(platform: 'acfun', areaType: '1', areaId: 'x'),
        LiveArea(platform: 'acfun', areaType: '-1', areaId: '1'),
      ]) {
        await expectLater(setup.site.getCategoryRooms(forged), throwsA(isA<NotFound>()), reason: '$forged');
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('the cursor chain: page 2 by the opaque cursor, the catalog does not reset it, page sizes are sent', () async {
      final http = _Scripted((request) {
        final cursor = request.url.queryParameters['pcursor']!;
        return _list(cursor.isEmpty ? 'next-opaque' : 'no_more');
      });
      final site = AcfunSite(http);
      expect((await site.getRecommendRooms(pageSize: 20)).single.onlineViewers, '99');
      final area = (await site.getCategories(1, 30)).single.children.last;
      expect((area.platform, area.areaId), ('acfun', '4'));
      await site.getRecommendRooms(page: 2, pageSize: 20);
      expect(await site.getRecommendRooms(page: 3, pageSize: 20), isEmpty);
      expect([for (final request in http.requests) request.url.queryParameters['pcursor']], ['', '', 'next-opaque']);
      expect([for (final request in http.requests) request.url.queryParameters['count']], ['20', '1', '20']);
      await site.getRecommendRooms(pageSize: 999);
      expect(http.requests.last.url.queryParameters['count'], '60');
      await site.getCategoryRooms(area);
      expect(jsonDecode(http.requests.last.url.queryParameters['filters']!), [
        {'filterType': 1, 'filterId': 4},
      ]);
    });

    test('concurrent readers of one page share one request', () async {
      final gate = Completer<Object>();
      final http = _Scripted((_) => gate.future);
      final site = AcfunSite(http);
      final one = site.getRecommendRooms();
      final two = site.getRecommendRooms();
      gate.complete(_list('no_more'));
      await Future.wait([one, two]);
      expect(http.requests, hasLength(1));
    });

    test('a page whose cursor was lost to a refresh reads the pages before it (REG-ACFUN-004)', () async {
      var firstReads = 0;
      final http = _Scripted((request) {
        final cursor = request.url.queryParameters['pcursor']!;
        if (cursor.isEmpty) return _list(++firstReads == 1 ? 'old-2' : 'new-2', id: 1);
        final page = int.parse(cursor.substring(4));
        return _list(cursor.startsWith('new-') ? 'new-${page + 1}' : 'old-3', id: page);
      });
      final site = AcfunSite(http);
      await site.getRecommendRooms();
      await site.getRecommendRooms(page: 2);
      await site.getRecommendRooms(); // another list refreshes the chain
      // 3.x: "pagination expired". Now pages 2 and 3 of the new chain are read.
      expect(await site.getRecommendRooms(page: 3), hasLength(1));
      expect(
        [for (final request in http.requests) request.url.queryParameters['pcursor']],
        ['', 'old-2', '', 'new-2', 'new-3'],
      );
    });

    test('a repeated cursor is ApiChanged instead of an endless list (3.x)', () async {
      final site = AcfunSite(_Scripted((_) => _list('same')));
      await site.getRecommendRooms();
      await expectLater(site.getRecommendRooms(page: 2), throwsA(isA<ApiChanged>()));
    });

    test('a stored 全部 area is the recommendations: no filter, the same listing (10-2)', () async {
      final http = _Scripted((_) => _list('no_more'));
      final site = AcfunSite(http);
      const all = LiveArea(platform: 'acfun', areaType: '1', typeName: 'AcFun 直播', areaId: '0', areaName: '全部');
      expect((await site.getCategoryRooms(all)).single.roomId, '42');
      expect(http.requests.single.url.queryParameters.containsKey('filters'), isFalse);
      expect(http.requests.single.url, _recommendationUrl());
      expect(await site.getRecommendRooms(page: 2), isEmpty, reason: 'the listing 全部 read');
      expect(http.requests, hasLength(1));
    });

    test('pages after the first leave out rooms listed since page 1 was read; a re-read page is the same', () async {
      final http = _Scripted((request) {
        final cursor = request.url.queryParameters['pcursor']!;
        return switch (cursor) {
          '' => _list('p2', ids: [1, 2, 3]),
          'p2' => _list('p3', ids: [3, 4, 4, 1, 5]),
          _ => _list('no_more', ids: [5, 6]),
        };
      });
      final site = AcfunSite(http);
      Future<List<String>> ids(int page) async => [
        for (final room in await site.getRecommendRooms(page: page, pageSize: 3)) room.roomId,
      ];
      expect(await ids(1), ['1', '2', '3']);
      expect(await ids(2), ['4', '5']);
      expect(await ids(3), ['6']);
      expect(await ids(2), ['4', '5'], reason: 'the same answer read again');
      expect(await ids(1), ['1', '2', '3'], reason: 'page 1 starts over');
      expect(http.requests, hasLength(5), reason: 'no more requests than before');
    });
  });

  group('cursor directory (10-5)', () {
    test('page 1 without a cursor, the next by the opaque cursor, 30 rooms a page, one request each', () async {
      final http = _Scripted((request) {
        final cursor = request.url.queryParameters['pcursor']!;
        return cursor.isEmpty ? _list('opaque-2', id: 1) : _list('no_more', id: 2);
      });
      final site = AcfunSite(http);
      final first = await site.getDirectoryPageAtCursor(page: 1);
      expect((first.rooms.single.roomId, first.page, first.hasMore, first.nextCursor), ('1', 1, true, 'opaque-2'));
      final second = await site.getDirectoryPageAtCursor(page: 2, cursor: first.nextCursor);
      expect((second.rooms.single.roomId, second.page, second.hasMore, second.nextCursor), ('2', 2, false, null));
      expect([for (final request in http.requests) request.url.queryParameters['pcursor']], ['', 'opaque-2']);
      expect([for (final request in http.requests) request.url.queryParameters['count']], ['30', '30']);
      expect(http.requests.first.url, _recommendationUrl());
      expect(http.requests.first.headers, AcfunApi.apiHeaders);
    });

    test("an area sends its filter, 全部 none; another platform's area is NotFound; the token is forwarded", () async {
      final http = _Scripted((_) => _list('no_more'));
      final site = AcfunSite(http);
      final cancel = CancelToken();
      const game = LiveArea(platform: 'acfun', areaType: '1', areaId: '1', areaName: '游戏');
      await site.getDirectoryPageAtCursor(page: 1, category: game, cancel: cancel);
      expect(jsonDecode(http.requests.last.url.queryParameters['filters']!), [
        {'filterType': 1, 'filterId': 1},
      ]);
      expect(http.requests.last.cancel, same(cancel));
      await site.getDirectoryPageAtCursor(
        page: 1,
        category: const LiveArea(platform: 'acfun', areaType: '1', areaId: '0'),
      );
      expect(http.requests.last.url.queryParameters.containsKey('filters'), isFalse);
      await expectLater(
        site.getDirectoryPageAtCursor(
          page: 1,
          category: const LiveArea(platform: 'huya', areaType: '1', areaId: '1'),
        ),
        throwsA(isA<NotFound>()),
      );
      expect(http.requests, hasLength(2));
    });

    test('a page and its cursor must agree; a cursor that leads to itself is ApiChanged', () async {
      final http = _Scripted((_) => _list('same'));
      final site = AcfunSite(http);
      expect(() => site.getDirectoryPageAtCursor(page: 1, cursor: 'x'), throwsArgumentError);
      expect(() => site.getDirectoryPageAtCursor(page: 2), throwsArgumentError);
      expect(() => site.getDirectoryPageAtCursor(page: 0), throwsRangeError);
      expect(http.requests, isEmpty);
      await expectLater(site.getDirectoryPageAtCursor(page: 2, cursor: 'same'), throwsA(isA<ApiChanged>()));
    });

    test('by page number: the listing chain, with whether more follow and the next cursor', () async {
      final http = _Scripted((request) {
        final cursor = request.url.queryParameters['pcursor']!;
        return cursor.isEmpty ? _list('opaque-2', id: 1) : _list('no_more', id: 2);
      });
      final site = AcfunSite(http);
      final first = await site.getDirectoryPage();
      expect((first.rooms.single.roomId, first.hasMore, first.nextCursor), ('1', true, 'opaque-2'));
      final second = await site.getDirectoryPage(page: 2);
      expect((second.rooms.single.roomId, second.hasMore, second.nextCursor), ('2', false, null));
      final after = await site.getDirectoryPage(page: 3);
      expect(after.rooms, isEmpty);
      expect(after.hasMore, isFalse);
      expect(http.requests, hasLength(2));
      // The recommendations at the same page size share the chain: page 2
      // is read again by its cursor, page 1 is not.
      expect((await site.getRecommendRooms(page: 2)).single.roomId, '2');
      expect(
        [for (final request in http.requests) request.url.queryParameters['pcursor']],
        ['', 'opaque-2', 'opaque-2'],
      );
    });

    test('by page number, a cancelled wait fails; the shared read goes on', () async {
      final gate = Completer<Object>();
      final http = _Scripted((_) => gate.future);
      final site = AcfunSite(http);
      final cancel = CancelToken();
      final waiting = site.getDirectoryPage(cancel: cancel);
      final other = site.getRecommendRooms();
      cancel.cancel();
      await expectLater(
        waiting,
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      gate.complete(_list('no_more'));
      expect((await other).single.roomId, '42');
      expect(http.requests, hasLength(1));
      await expectLater(
        site.getDirectoryPage(cancel: cancel),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      expect(http.requests, hasLength(1));
    });
  });

  group('search', () {
    test("S04 page 1 at 3.x's page size: 3.x's request, authors and streamers", () async {
      final setup = _setup(['S04-search-p1']);
      final rooms = await setup.site.searchRooms(' 游戏 ', pageSize: 20);
      final legacy = _legacy('S04-search-p1');
      expect(rooms.map((room) => room.roomId), [
        for (final room in legacy['searchRooms'] as List) (room as Map)['roomId'],
      ]);
      final request = (legacy['requests'] as List).first as Map<String, dynamic>;
      expect(setup.http.requests.single.url, Uri.parse(request['url'] as String));
      expect(setup.http.requests.single.headers, _headers(request));
      final anchors = await _setup(['S04-search-p1']).site.searchAnchors('游戏', pageSize: 20);
      expect([
        for (final anchor in anchors)
          {
            'roomId': anchor.roomId,
            'avatar': anchor.avatar,
            'userName': anchor.userName,
            'liveStatus': anchor.liveStatus,
          },
      ], legacy['searchAnchors']);
    });

    test('a short result ends at its total; no results is empty; a blank keyword sends nothing', () async {
      final setup = _setup(['S04-search-fuzzy', 'S04-search-none']);
      expect(await setup.site.searchRooms('zzqqxxkkyyww', pageSize: 20), hasLength(8));
      expect(await setup.site.searchRooms('zzqqxxkkyyww', page: 2, pageSize: 20), isEmpty);
      expect(setup.http.requests, hasLength(1));
      expect(await setup.site.searchRooms('豈翀竡龘皓齃'), isEmpty);
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });

    test('20-row pages over 30-row server pages without omissions (3.x navigation test)', () async {
      final http = _Scripted((request) => _serverPage(_pCursor(request)));
      final site = AcfunSite(http);
      final ids = <String>[];
      for (var page = 1; page <= 4; page++) {
        ids.addAll((await site.searchRooms(' 游戏 &?=+ ', page: page, pageSize: 20)).map((room) => room.roomId));
      }
      expect(ids, [for (var id = 1; id <= 75; id++) '$id']);
      expect(http.requests.map(_pCursor), [1, 2, 3]);
      for (final request in http.requests) {
        expect(request.url.queryParameters['keyword'], '游戏 &?=+');
        expect(request.cancel!.isCancelled, isTrue, reason: 'nothing left running');
      }
    });

    test('short server pages neither skip authors nor end the results early (REG-ACFUN-002)', () async {
      final http = _Scripted((request) => _serverPage(_pCursor(request), total: 100, missing: {60, 100}));
      final site = AcfunSite(http);
      final ids = <String>[];
      final sizes = <int>[];
      for (var page = 1; page <= 6; page++) {
        final rooms = await site.searchRooms('fixture', page: page, pageSize: 20);
        ids.addAll(rooms.map((room) => room.roomId));
        sizes.add(rooms.length);
      }
      expect(ids, [
        for (var id = 1; id <= 100; id++)
          if (id != 60 && id != 100) '$id',
      ]);
      expect(sizes, [20, 20, 20, 20, 18, 0]);
      expect(http.requests.map(_pCursor), [1, 2, 3, 4]);
    });

    test('a failed page can be asked again without losing the rows already read (3.x)', () async {
      var fail = true;
      final http = _Scripted((request) {
        if (_pCursor(request) == 2 && fail) {
          fail = false;
          return TransportReason.connect;
        }
        return _serverPage(_pCursor(request));
      });
      final site = AcfunSite(http);
      await site.searchRooms('fixture', pageSize: 20);
      await expectLater(site.searchRooms('fixture', page: 2, pageSize: 20), throwsA(isA<NetworkFailure>()));
      final retry = await site.searchRooms('fixture', page: 2, pageSize: 20);
      expect(retry.map((room) => room.roomId), [for (var id = 21; id <= 40; id++) '$id']);
      expect(http.requests.map(_pCursor), [1, 2, 2]);
    });

    test('the same page shares one read; another page waits for it (3.x failed it)', () async {
      final gate = Completer<Object>();
      final http = _Scripted((request) => _pCursor(request) == 1 ? gate.future : _serverPage(_pCursor(request)));
      final site = AcfunSite(http);
      final first = site.searchRooms('fixture', pageSize: 10);
      final same = site.searchRooms('fixture', pageSize: 10);
      final second = site.searchRooms('fixture', page: 2, pageSize: 10);
      gate.complete(_serverPage(1));
      expect((await first).map((room) => room.roomId), [for (var id = 1; id <= 10; id++) '$id']);
      expect((await same).map((room) => room.roomId), [for (var id = 1; id <= 10; id++) '$id']);
      expect((await second).map((room) => room.roomId), [for (var id = 11; id <= 20; id++) '$id']);
      expect(http.requests, hasLength(1));
    });

    test("a new first page cancels the previous search's request and ignores its answer (3.x)", () async {
      final old = Completer<Object>();
      var secondPageReads = 0;
      final http = _Scripted((request) {
        if (_pCursor(request) == 2 && ++secondPageReads == 1) return old.future;
        return _serverPage(_pCursor(request));
      });
      final site = AcfunSite(http);
      await site.searchRooms('fixture', pageSize: 20);
      final stale = site.searchRooms('fixture', page: 2, pageSize: 20);
      final rejected = expectLater(
        stale,
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      await Future<void>.delayed(Duration.zero);
      final staleCancel = http.requests.last.cancel!;
      await site.searchRooms('fixture', pageSize: 20);
      expect(staleCancel.isCancelled, isTrue);
      old.complete(_serverPage(2));
      await rejected;
      final fresh = await site.searchRooms('fixture', page: 2, pageSize: 20);
      expect(fresh.map((room) => room.roomId), [for (var id = 21; id <= 40; id++) '$id']);
      expect(secondPageReads, 2);
    });

    test('a page asked for out of order starts at its position (3.x: "pagination expired")', () async {
      final http = _Scripted((request) => _serverPage(_pCursor(request)));
      final site = AcfunSite(http);
      final rooms = await site.searchRooms('fixture', page: 3, pageSize: 20);
      expect(rooms.map((room) => room.roomId), [for (var id = 41; id <= 60; id++) '$id']);
      expect(http.requests.map(_pCursor), [2]);
      expect((await site.searchRooms('fixture', page: 4, pageSize: 20)).map((room) => room.roomId), [
        for (var id = 61; id <= 75; id++) '$id',
      ]);
      // Evicted searches (8 are kept) also start again at their position.
      for (var index = 0; index < 8; index++) {
        await site.searchRooms('other $index', pageSize: 20);
      }
      expect(await site.searchRooms('fixture', page: 2, pageSize: 20), hasLength(20));
    });

    test('a page gives up after the timeout and cancels its request', () async {
      final gate = Completer<Object>();
      final http = _Scripted((_) => gate.future);
      final site = AcfunSite(http, searchTimeout: const Duration(milliseconds: 20));
      await expectLater(site.searchRooms('fixture', pageSize: 40), throwsA(isA<NetworkFailure>()));
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      gate.complete(_serverPage(1));
      await Future<void>.delayed(Duration.zero);
      expect(http.requests, hasLength(1), reason: 'no late next-page work');
    });

    test('empty server pages before the total are skipped, at most four a page (3.x)', () async {
      final http = _Scripted(
        (request) => _pCursor(request) == 2 ? _searchAnswer(const [], total: 75) : _serverPage(_pCursor(request)),
      );
      final site = AcfunSite(http);
      await site.searchRooms('fixture', pageSize: 20);
      expect((await site.searchRooms('fixture', page: 2, pageSize: 20)).map((room) => room.roomId), [
        for (var id = 21; id <= 30; id++) '$id',
        for (var id = 61; id <= 70; id++) '$id',
      ]);
      expect(http.requests, hasLength(3));
      final empty = _Scripted((_) => _searchAnswer(const [], total: 3000));
      await expectLater(AcfunSite(empty).searchRooms('fixture'), throwsA(isA<ApiChanged>()));
      expect(empty.requests, hasLength(4));
    });
  });

  group('rooms', () {
    test('refresh and live status read live/info only, never a visitor session (3.x)', () async {
      final setup = _setup(_live);
      final room = await setup.site.getRoomDetailForRefresh(roomId: ' 40740702 ');
      expect(room.roomId, '40740702');
      expect(room.isLiveNow, isTrue);
      expect(room.data, isNull);
      expect(await setup.site.getLiveStatus(roomId: '40740702'), isTrue);
      expect(await setup.site.getLiveStatus(roomId: '1'), isFalse);
      final legacy = (_legacy('S05-info-live')['refreshRequests'] as List).single as Map<String, dynamic>;
      expect(setup.http.requests.first.url, Uri.parse(legacy['url'] as String));
      expect(setup.http.requests.first.headers, _headers(legacy));
      expect(setup.http.requests.map((request) => request.url.path).toSet(), {'/api/live/info'});
    });

    test('room entry: live/info, the visitor login and startPlay, as 3.x asked them', () async {
      final setup = _setup(_live);
      final room = await setup.site.getRoomDetail(roomId: '40740702');
      final legacy = _legacy('S05-info-live');
      final made = (legacy['detailRequests'] as List).cast<Map<String, dynamic>>();
      expect(setup.http.requests.map((request) => request.url.path), [
        for (final r in made) Uri.parse(r['url'] as String).path,
      ]);
      final [info, login, play] = setup.http.requests;
      expect(info.headers, _headers(made[0]));
      expect(_without(login.headers, 'content-type'), {..._headers(made[1]), 'cookie': login.headers['cookie']!});
      expect(login.headers['cookie'], matches(RegExp(r'^_did=web_[A-Za-z0-9]{16};$')));
      expect(Uri.splitQueryString(utf8.decode(login.body!)), made[1]['form']);
      expect(_without(play.headers, 'content-type'), _headers(made[2]));
      expect(Uri.splitQueryString(utf8.decode(play.body!)), made[2]['form']);
      expect(play.url.queryParameters.keys, Uri.parse(made[2]['url'] as String).queryParameters.keys);
      final data = room.data! as AcfunRoomData;
      final playback = (legacy['getRoomDetail'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      expect(data.liveId, playback['liveId']);
      expect(data.qualities.map((quality) => quality.id), [
        for (final quality in playback['qualities'] as List) (quality as Map)['id'],
      ]);
      final args = room.danmakuData! as AcfunDanmakuArgs;
      expect((args.authorId, args.liveId, args.tickets.length), ('40740702', '29RchpoKMpA', 4));
      expect(args.visitor.userId, (_legacy('S06-visitor')['startPlayQuery'] as Map)['userId']);
      expect(args.visitor.security, isNotNull);
      expect(args.enterRoomAttach, isNotEmpty);
    });

    test('recording reads the broadcast too, with the danmaku arguments of the same answers (E05.4)', () async {
      final setup = _setup(_live);
      final room = await setup.site.getRoomDetailForRecording(roomId: '40740702');
      expect(room.data, isA<AcfunRoomData>());
      final args = room.danmakuData! as AcfunDanmakuArgs;
      expect((args.authorId, args.liveId, args.tickets.length), ('40740702', '29RchpoKMpA', 4));
      expect(setup.http.requests, hasLength(3), reason: 'no request for them');
    });

    test('an offline room: one request, no broadcast, and no stream without a request', () async {
      final setup = _setup(_live);
      final room = await setup.site.getRoomDetail(roomId: '1');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.data, isNull);
      expect(setup.http.requests, hasLength(1));
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(1), reason: '3.x listed no qualities without asking');
    });

    test('an unknown author is NotFound; a malformed id is NotFound without a request', () async {
      final setup = _setup(_live);
      await expectLater(setup.site.getRoomDetail(roomId: '99999999999'), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(1));
      for (final id in ['0', '-1', '42&authorId=99', 'https://example.com/42', '0042']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('a broadcast that ends between live/info and startPlay fails room entry as StreamUnavailable', () async {
      final http = _Scripted((request) {
        if (request.url.path == '/api/live/info') return _info();
        if (request.url.path.endsWith('/visitor/login')) return _visitorAnswer;
        return {'result': 129004, 'error_msg': '直播已关播'};
      });
      await expectLater(AcfunSite(http).getRoomDetail(roomId: '42'), throwsA(isA<StreamUnavailable>()));
    });

    test('S05: refresh and entry start at createTime (10-3) without another request; neither is restricted', () async {
      final setup = _setup(_live);
      final start = DateTime.utc(2026, 9, 27, 14, 37, 35, 941);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: '40740702');
      expect((refreshed.startedAt, refreshed.restriction), (start, LiveRestriction.none));
      expect(setup.http.requests, hasLength(1));
      final entered = await setup.site.getRoomDetail(roomId: '40740702');
      expect((entered.startedAt, entered.restriction), (start, LiveRestriction.none));
      final offline = await setup.site.getRoomDetailForRefresh(roomId: '1');
      expect((offline.startedAt, offline.restriction), (null, null));
      expect(setup.http.requests, hasLength(5), reason: '3.x: one, then three, then one');
    });

    test("entry takes startPlay's liveStartTime when live/info has no createTime", () async {
      final http = _Scripted((request) {
        if (request.url.path == '/api/live/info') return _info();
        if (request.url.path.endsWith('/visitor/login')) return _visitorAnswer;
        return {
          ..._play('a'),
          'data': {...(_play('a')['data']! as Map<String, Object?>), 'liveStartTime': 1790519855941},
        };
      });
      final room = await AcfunSite(http).getRoomDetail(roomId: '42');
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 37, 35, 941));
    });
  });

  group('paid shows (M2.1 restrictions)', () {
    /// A live paid show: live/info with [uuid], startPlay 380205.
    _Scripted paidShow({String? uuid = 'show-a'}) => _Scripted((request) {
      if (request.url.path == '/api/live/info') {
        return {..._info(), 'paidShowUuid': ?uuid, 'paidShowUserBuyStatus': false};
      }
      if (request.url.path.endsWith('/visitor/login')) return _visitorAnswer;
      return {'result': AcfunApi.paidShowResult, 'error_msg': 'not paid'};
    });

    final notPlayable = throwsA(
      isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('restricted room (paid)')),
    );

    test('entry: live and paid, no broadcast or danmaku; streams fail naming it without a request', () async {
      final http = paidShow();
      final site = AcfunSite(http);
      final room = await site.getRoomDetail(roomId: '42');
      expect((room.isLiveNow, room.restriction, room.data, room.danmakuData), (true, LiveRestriction.paid, null, null));
      expect(room.followGroup, FollowGroup.live);
      expect(http.paths.map((path) => path.split('/').last), ['info', 'login', 'startPlay'], reason: 'no new session');
      await expectLater(site.getPlayQualities(detail: room), notPlayable);
      await expectLater(
        site.resolvePlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: '超清', id: 'HIGH'),
        ),
        notPlayable,
      );
      expect(http.requests, hasLength(3));
      final recording = await site.getRoomDetailForRecording(roomId: '42');
      expect((recording.isLiveNow, recording.restriction), (true, LiveRestriction.paid));
      expect(recording.danmakuData, isNull, reason: 'a paid show has no danmaku arguments');
    });

    test('refresh marks the paid show from live/info alone (3.x: live, unmarked)', () async {
      final http = paidShow();
      final room = await AcfunSite(http).getRoomDetailForRefresh(roomId: '42');
      expect((room.isLiveNow, room.restriction), (true, LiveRestriction.paid));
      expect(http.requests, hasLength(1));
    });

    test('startPlay decides: 380205 without paidShowUuid is paid too; a playing show is not restricted', () async {
      final room = await AcfunSite(paidShow(uuid: null)).getRoomDetail(roomId: '42');
      expect(room.restriction, LiveRestriction.paid);
      final playing = _Scripted((request) {
        if (request.url.path == '/api/live/info') return {..._info(), 'paidShowUuid': 'show-a'};
        if (request.url.path.endsWith('/visitor/login')) return _visitorAnswer;
        return _play('a');
      });
      final bought = await AcfunSite(playing).getRoomDetail(roomId: '42');
      expect(bought.restriction, LiveRestriction.none);
      expect(bought.data, isA<AcfunRoomData>());
    });

    test('a paid card fails without a request; an unmarked card, recovery and danmaku fail after startPlay', () async {
      final http = paidShow();
      final site = AcfunSite(http);
      final paidCard = LiveRoom(
        platform: 'acfun',
        roomId: '42',
        liveStatus: LiveStatus.live,
        restriction: LiveRestriction.paid,
      );
      await expectLater(site.getPlayQualities(detail: paidCard), notPlayable);
      expect(http.requests, isEmpty);
      final card = LiveRoom(platform: 'acfun', roomId: '42', liveStatus: LiveStatus.live);
      await expectLater(site.getPlayQualities(detail: card), notPlayable);
      await expectLater(
        site.resolvePlayUrlsForRecovery(
          detail: paidCard,
          quality: const LivePlayQuality(quality: '超清', id: 'HIGH'),
        ),
        notPlayable,
      );
      await expectLater(site.danmakuArgs('42'), notPlayable);
      expect(http.paths.where((path) => path.endsWith('/startPlay')), hasLength(3));
    });
  });

  group('visitor session', () {
    _Scripted session({
      Completer<void>? loginGate,
      Object Function(int attempt)? playAnswer,
      Object loginAnswer = _visitorAnswer,
    }) {
      var plays = 0;
      return _Scripted((request) async {
        if (request.url.path.endsWith('/visitor/login')) {
          await loginGate?.future;
          return loginAnswer;
        }
        if (request.url.path == '/api/live/info') return _info();
        plays++;
        return playAnswer?.call(plays) ?? _play('$plays');
      });
    }

    List<String> paths(_Scripted http) => [for (final path in http.paths) path.split('/').last];

    test('concurrent streams share one login and are asked with its identity (3.x)', () async {
      final gate = Completer<void>();
      final http = session(loginGate: gate);
      final site = AcfunSite(http);
      final first = site.getPlayQualities(
        detail: LiveRoom(platform: 'acfun', roomId: '42', liveStatus: LiveStatus.live),
      );
      final second = site.getPlayQualities(
        detail: LiveRoom(platform: 'acfun', roomId: '43'),
      );
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([first, second]);
      expect(paths(http), ['login', 'startPlay', 'startPlay']);
      final did = RegExp('_did=(web_[A-Za-z0-9]{16});').firstMatch(http.requests.first.headers['cookie']!)!.group(1);
      for (final play in http.requests.skip(1)) {
        expect(play.url.queryParameters['did'], did);
        expect(play.url.queryParameters['userId'], '12345');
        expect(play.url.queryParameters['acfun.api.visitor_st'], 'fixture-visitor-token');
        expect(play.headers['referer'], 'https://live.acfun.cn/');
        expect(Uri.splitQueryString(utf8.decode(play.body!))['pullStreamType'], 'FLV');
      }
    });

    test('the session is reused for five minutes, then renewed (3.x)', () async {
      var now = DateTime.utc(2026, 9, 5);
      final http = session();
      final site = AcfunSite(http, now: () => now);
      final card = LiveRoom(platform: 'acfun', roomId: '42', liveStatus: LiveStatus.live);
      await site.getPlayQualities(detail: card);
      await site.getPlayQualities(detail: card);
      now = now.add(const Duration(minutes: 6));
      await site.getPlayQualities(detail: card);
      expect(paths(http), ['login', 'startPlay', 'startPlay', 'login', 'startPlay']);
    });

    test('a refused session is replaced and asked once more at once (REG-ACFUN-003)', () async {
      final http = session(playAnswer: (attempt) => attempt == 1 ? {'result': 401} : _play('$attempt'));
      final site = AcfunSite(http);
      final qualities = await site.getPlayQualities(
        detail: LiveRoom(platform: 'acfun', roomId: '42', liveStatus: LiveStatus.live),
      );
      expect(qualities.map((quality) => quality.id), ['HIGH', 'STANDARD']);
      expect(paths(http), ['login', 'startPlay', 'login', 'startPlay']);
      final twice = session(playAnswer: (_) => {'result': 401});
      await expectLater(
        AcfunSite(twice).getPlayQualities(
          detail: LiveRoom(platform: 'acfun', roomId: '42'),
        ),
        throwsA(isA<RiskControl>()),
      );
      expect(paths(twice), ['login', 'startPlay', 'login', 'startPlay'], reason: 'one retry only');
    });

    test('an ended broadcast keeps the session', () async {
      final http = session(playAnswer: (attempt) => attempt == 1 ? {'result': 129004} : _play('2'));
      final site = AcfunSite(http);
      final card = LiveRoom(platform: 'acfun', roomId: '42');
      await expectLater(site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      await site.getPlayQualities(detail: card);
      expect(paths(http), ['login', 'startPlay', 'startPlay']);
    });

    test('a session without acSecurity still plays (only danmaku needs it)', () async {
      final http = session();
      final room = await AcfunSite(http).getRoomDetail(roomId: '42');
      expect((room.danmakuData! as AcfunDanmakuArgs).visitor.security, isNull);
      expect((room.data! as AcfunRoomData).qualities, hasLength(2));
    });

    test('a refused login is RiskControl and is not kept', () async {
      var logins = 0;
      final http = _Scripted((request) {
        if (request.url.path.endsWith('/visitor/login')) return ++logins == 1 ? {'result': 500} : _visitorAnswer;
        return _play('x');
      });
      final site = AcfunSite(http);
      final card = LiveRoom(platform: 'acfun', roomId: '42');
      await expectLater(site.getPlayQualities(detail: card), throwsA(isA<RiskControl>()));
      await site.getPlayQualities(detail: card);
      expect(logins, 2);
    });
  });

  group('streams', () {
    test("the room's broadcast: qualities and lines without another request", () async {
      final setup = _setup(_live, now: () => Fixture.load('acfun', 'S06-startplay-live').capturedAt);
      final room = await setup.site.getRoomDetail(roomId: '40740702');
      final before = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.quality), ['蓝光 8M', '蓝光 4M', '超清', '高清']);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.first);
      final legacy = (_legacy('S05-info-live')['getPlayUrls'] as Map<String, dynamic>)['BLUE_RAY'];
      expect(resolution.urls, legacy);
      expect(resolution.appliedQualityData, 'BLUE_RAY');
      expect(resolution.lines.single.headers['origin'], 'https://live.acfun.cn');
      expect(resolution.lines.single.lease, isNotNull);
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.last), hasLength(1));
      expect(setup.http.requests, hasLength(before));
    });

    test('a live card without a broadcast asks startPlay first', () async {
      final setup = _setup(_live);
      final card = LiveRoom(platform: 'acfun', roomId: '40740702', liveStatus: LiveStatus.live);
      final qualities = await setup.site.getPlayQualities(detail: card);
      expect(qualities, hasLength(4));
      expect(setup.http.requests.map((request) => request.url.path.split('/').last), ['login', 'startPlay']);
    });

    test('recovery asks startPlay again; a quality no longer offered is StreamUnavailable (3.x)', () async {
      var plays = 0;
      var high = true;
      final http = _Scripted((request) {
        if (request.url.path == '/api/live/info') return _info();
        if (request.url.path.endsWith('/visitor/login')) return _visitorAnswer;
        return _play('${++plays}', high: high);
      });
      final site = AcfunSite(http);
      final room = await site.getRoomDetail(roomId: '42');
      final selected = (await site.getPlayQualities(detail: room)).first;
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: selected);
      expect(recovered.appliedQualityData, 'HIGH');
      expect(recovered.urls.single, 'https://cdn.example/2-high.flv');
      expect((await site.getPlayUrls(detail: room, quality: selected)).single, 'https://cdn.example/1-high.flv');
      high = false;
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: selected),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('recovery of an ended broadcast is StreamUnavailable', () async {
      final setup = _setup(_live);
      final room = await setup.site.getRoomDetail(roomId: '1');
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(
          detail: room,
          quality: const LivePlayQuality(quality: '超清', id: 'HIGH'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests.map((request) => request.url.path).last, '/rest/zt/live/web/startPlay');
    });
  });

  test('danmaku arguments refresh with a new visitor session and broadcast', () async {
    var plays = 0;
    final http = _Scripted((request) {
      if (request.url.path == '/api/live/info') return _info();
      if (request.url.path.endsWith('/visitor/login')) return _visitorAnswer;
      return _play('${++plays}');
    });
    final room = await AcfunSite(http).getRoomDetail(roomId: '42');
    final args = room.danmakuData! as AcfunDanmakuArgs;
    expect((args.liveId, args.enterRoomAttach), ('live-1', 'attach-1'));
    expect(args.tickets, ['ticket-1']);
    final fresh = await args.refresh!();
    expect(fresh.liveId, 'live-2');
    expect(fresh.tickets, ['ticket-2']);
    final cookies = [
      for (final request in http.requests)
        if (request.url.path.endsWith('/visitor/login')) request.headers['cookie'],
    ];
    expect(cookies, hasLength(2));
    expect(cookies.toSet(), hasLength(2), reason: 'a new device id');
  });

  group('links', () {
    test("3.x's room links (legacy web_search_room_parser and live_url_tool tests)", () {
      final site = AcfunSite(ReplayHttp([]));
      expect(site.roomIdFromUrl('https://live.acfun.cn/live/42?from=search'), '42');
      expect(site.roomIdFromUrl('http://live.acfun.cn/live/40740702'), '40740702');
      expect(site.roomIdFromUrl('https://m.acfun.cn/live/detail/40740702'), '40740702');
      for (final url in [
        'https://www.acfun.cn/v/ac42',
        'https://live.acfun.cn/live/0',
        'https://live.acfun.cn/live/042',
        'https://live.acfun.cn/live/42/extra',
        'https://live.acfun.cn.evil.example/live/42',
        'https://secret@live.acfun.cn/live/42',
        'https://live.acfun.cn/search?keyword=huya.com',
        'https://live.acfun.cn/live/search',
        'https://m.acfun.cn/live/42',
        'ftp://live.acfun.cn/live/42',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(site.needsResolving('https://live.acfun.cn/live/42'), isFalse);
    });

    test("profile pages are the author's room (10-1; 3.x did not take them)", () async {
      final site = AcfunSite(ReplayHttp([]));
      for (final url in [
        'https://www.acfun.cn/u/40740702',
        'https://acfun.cn/u/40740702?tab=video',
        'http://www.acfun.cn/u/40740702.aspx',
        'https://m.acfun.cn/upPage/40740702?shareUid=1',
        'https://WWW.ACFUN.CN/u/40740702/',
      ]) {
        expect(site.roomIdFromUrl(url), '40740702', reason: url);
      }
      for (final url in [
        'https://www.acfun.cn/u/0',
        'https://www.acfun.cn/u/042',
        'https://www.acfun.cn/u/42/extra',
        'https://www.acfun.cn/u/.aspx',
        'https://www.acfun.cn/u/42.html',
        'https://m.acfun.cn/u/42',
        'https://live.acfun.cn/u/42',
        'https://www.acfun.cn.evil.example/u/42',
        'https://m.acfun.cn/upPage/abc',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      final http = ReplayHttp([]);
      final parser = LinkParser(SiteRegistry({'acfun': () => AcfunSite(http)}), http);
      expect(await parser.parse('关注这个UP主 https://www.acfun.cn/u/40740702'), const RoomLink('acfun', '40740702'));
      expect(http.requests, isEmpty);
    });

    test('a share text is parsed without a request (3.x)', () async {
      final http = ReplayHttp([]);
      final registry = SiteRegistry({'acfun': () => AcfunSite(http)});
      final parser = LinkParser(registry, http);
      expect(await parser.parse('看看这个直播 https://live.acfun.cn/live/42?source=share'), const RoomLink('acfun', '42'));
      expect(
        await parser.parse('See https://example.org/article then https://live.acfun.cn/live/42'),
        const RoomLink('acfun', '42'),
      );
      expect(await parser.parse('https://live.acfun.cn/search?keyword=huya.com'), isNull);
      expect(http.requests, isEmpty);
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    await expectLater(
      AcfunSite(_Scripted((_) => TransportReason.timeout)).getRoomDetail(roomId: '42'),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      AcfunSite(_Scripted((_) => TransportReason.cancelled)).getRoomDetail(roomId: '42'),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
    await expectLater(
      AcfunSite(_Scripted((_) => (502, 'bad gateway'))).getRecommendRooms(),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      AcfunSite(_Scripted((_) => (403, 'forbidden'))).searchRooms('fixture'),
      throwsA(isA<RiskControl>()),
    );
  });
}
