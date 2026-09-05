import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/acfun/acfun_api.dart';
import 'package:pure_live/core/site/acfun/acfun_directory.dart';
import 'package:pure_live/core/site/acfun/acfun_search.dart';
import 'package:pure_live/core/site/acfun/acfun_site.dart';

Map<String, dynamic> directoryResponse(String cursor, {int id = 42, bool categories = true}) => {
  'channelListData': {
    'result': 0,
    'pcursor': cursor,
    'liveList': [
      {
        'authorId': id,
        'user': {'id': id, 'name': 'Fixture $id'},
        'liveId': 'live-$id',
        'streamName': 'stream-$id',
        'onlineCount': 99,
      },
    ],
  },
  if (categories)
    'channelFilters': {
      'liveChannelDisplayFilters': [
        {
          'displayFilters': [
            {'filterType': 1, 'filterId': 0, 'name': '全部'},
            {'filterType': '1', 'filterId': '4', 'name': '虚拟偶像', 'cover': '//img.example/virtual.jpg'},
          ],
        },
      ],
    },
};

String searchCard(
  int id, {
  Object? flag = '',
  String? href,
  String name = 'Fixture &amp; live',
  String avatar = '//img.example/a.jpg',
}) =>
    '''
<div class="search-up" data-up-exposure-log='${jsonEncode({'up_id': id, 'is_on_live': ?flag})}'>
<img class="up__avatar live-avatar" src="$avatar">
<div class="up__main__name"><a href="${href ?? '/u/$id'}">$name</a></div>
<div class="info__danmaku-count">2.4万&ensp;粉丝</div>
<div class="up__main__intro">Fixture &lt;stream&gt;</div>
</div>''';

String searchResponse(List<String> cards, {required int total, bool blankZero = false, bool emptyMarker = true}) =>
    '${jsonEncode({
      'html': '<span class="total-num" data-total="${blankZero ? '' : total}">共$total条结果</span>'
          '${cards.join()}${cards.isEmpty && emptyMarker ? '<div class="empty-page"></div>' : ''}',
      'scripts': ['throw new Error("never execute")'],
    })}/*<!-- fetch-stream -->*/';

String searchServerPage(int page, {int total = 75}) => searchResponse([
  for (var id = (page - 1) * 30 + 1; id <= page * 30 && id <= total; id++) searchCard(id),
], total: total);

void main() {
  test('official category filters retain names, IDs, order and encoded requests', () {
    final page = AcfunApi.parseDirectory(directoryResponse('opaque'));
    expect(page.categories.map((c) => c.name), ['全部', '虚拟偶像']);
    expect(page.categories.last.cover, 'https://img.example/virtual.jpg');
    expect(jsonDecode(page.categories.last.query), [
      {'filterType': 1, 'filterId': 4},
    ]);
    expect(() => page.categories.clear(), throwsUnsupportedError);
    expect(AcfunApi.parseDirectory(directoryResponse('no_more', categories: false)).categories, isEmpty);
  });

  test('invalid category envelopes do not turn into a successful empty category page', () {
    for (final raw in <Object?>[
      null,
      {},
      {'liveChannelDisplayFilters': {}},
      {
        'liveChannelDisplayFilters': [
          {
            'displayFilters': [
              {'filterType': 1, 'filterId': -2, 'name': 'Invalid'},
            ],
          },
        ],
      },
    ]) {
      expect(() => AcfunApi.parseCategories(raw), throwsA(isA<AcfunApiException>()));
    }
  });

  test('directory items use the outer result envelope and category metadata does not reset cursors', () async {
    final cursors = <String>[];
    final counts = <int>[];
    final api = AcfunApi(
      request: (method, url, {query, body, headers}) async {
        cursors.add(query!['pcursor'] as String);
        counts.add(query['count'] as int);
        return directoryResponse(cursors.last.isEmpty ? 'next-opaque' : 'no_more');
      },
    );
    final site = AcfunSite(api: api);
    final first = await site.getRecommendRooms(pageSize: 20);
    expect(first.single.roomId, '42');
    expect(first.single.liveStatus, LiveStatus.live);
    expect(first.single.onlineViewers, '99');
    final category = (await site.getCategores(1, 30)).single.children.last;
    expect(category.platform, 'acfun');
    expect(category.areaId, '4');
    await site.getRecommendRooms(page: 2, pageSize: 20);
    expect(cursors, ['', '', 'next-opaque']);
    expect(counts, [20, 1, 20]);
    expect(await site.getRecommendRooms(page: 3, pageSize: 20), isEmpty);
    expect(cursors.length, 3);
  });

  test('directory filter and page-size cursors are independent; no guessed cursors on a missing page', () async {
    final requests = <Map<String, dynamic>>[];
    final api = AcfunApi(
      request: (method, url, {query, body, headers}) async {
        requests.add(query!);
        return directoryResponse('next-${requests.length}');
      },
    );
    final directory = AcfunDirectory(api: api);
    await directory.page(filters: 'a', count: 20);
    await directory.page(filters: 'b', count: 20);
    await directory.page(filters: 'a', count: 30);
    await directory.page(page: 2, filters: 'a', count: 20);
    expect(requests.last['pcursor'], 'next-1');
    await expectLater(directory.page(page: 2, filters: 'missing'), throwsA(isA<AcfunApiException>()));
    await expectLater(directory.page(page: 6, filters: 'a', count: 20), throwsA(isA<AcfunApiException>()));
    expect(requests.length, 4);
  });

  test('same-page in-flight directory consumers share one request', () async {
    final barrier = Completer<Object?>();
    var requests = 0;
    final directory = AcfunDirectory(
      api: AcfunApi(
        request: (method, url, {query, body, headers}) {
          requests++;
          return barrier.future;
        },
      ),
    );
    final one = directory.page();
    final two = directory.page();
    expect(identical(one, two), isTrue);
    barrier.complete(directoryResponse('no_more'));
    await Future.wait([one, two]);
    expect(requests, 1);
  });

  test('old page completion after page-one refresh does not overwrite the new cursor generation', () async {
    final oldPage = Completer<Object?>();
    final cursors = <String>[];
    var firstReads = 0;
    final directory = AcfunDirectory(
      api: AcfunApi(
        request: (method, url, {query, body, headers}) async {
          final cursor = query!['pcursor'] as String;
          cursors.add(cursor);
          if (cursor == 'old-next') return oldPage.future;
          if (cursor.isEmpty) return directoryResponse(++firstReads == 1 ? 'old-next' : 'new-next');
          return directoryResponse('no_more');
        },
      ),
    );
    await directory.page();
    final old = directory.page(page: 2);
    await directory.page();
    oldPage.complete(directoryResponse('stale-page-three'));
    await old;
    await expectLater(directory.page(page: 3), throwsA(isA<AcfunApiException>()));
    await directory.page(page: 2);
    expect(cursors, ['', 'old-next', '', 'new-next']);
  });

  test('duplicate cursors are rejected instead of causing infinite duplicate pages', () async {
    final directory = AcfunDirectory(
      api: AcfunApi(request: (method, url, {query, body, headers}) async => directoryResponse('same')),
    );
    await directory.page();
    await expectLater(directory.page(page: 2), throwsA(isA<AcfunApiException>()));
    await expectLater(directory.page(page: 3), throwsA(isA<AcfunApiException>()));
  });

  test('directory query/cursor retention is bounded and evicted contexts require refresh', () async {
    var calls = 0;
    final directory = AcfunDirectory(
      maxQueries: 2,
      maxCursors: 2,
      api: AcfunApi(request: (method, url, {query, body, headers}) async => directoryResponse('next-${++calls}')),
    );
    for (final filter in ['a', 'b', 'c']) {
      await directory.page(filters: filter);
    }
    await expectLater(directory.page(page: 2, filters: 'a'), throwsA(isA<AcfunApiException>()));
    for (var page = 2; page <= 5; page++) {
      await directory.page(page: page, filters: 'c');
    }
    await expectLater(directory.page(page: 2, filters: 'c'), throwsA(isA<AcfunApiException>()));
    await directory.page(page: 6, filters: 'c');
    expect(calls, 8);
  });

  test('category directory emits exact filter IDs and rejects forged category identity', () async {
    Map<String, dynamic>? requestQuery;
    final site = AcfunSite(
      api: AcfunApi(
        request: (method, url, {query, body, headers}) async {
          requestQuery = query;
          return directoryResponse('no_more');
        },
      ),
    );
    final category = (await site.getCategores(1, 30)).single.children.last;
    await site.getCategoryRooms(category);
    expect(jsonDecode(requestQuery!['filters'] as String), [
      {'filterType': 1, 'filterId': 4},
    ]);
    category.platform = 'huya';
    await expectLater(site.getCategoryRooms(category), throwsA(isA<AcfunApiException>()));
  });

  test('author search handles liveId strings, explicit offline and unknown separately', () {
    final data = AcfunSearchClient.parsePage(
      searchResponse([searchCard(1, flag: 'live-opaque'), searchCard(2), searchCard(3, flag: null)], total: 3),
      page: 1,
    );
    expect(data.rooms.map((r) => r.liveStatus), [LiveStatus.live, LiveStatus.offline, LiveStatus.unknown]);
    expect(data.rooms.map((r) => r.status), [true, false, null]);
    expect(data.rooms.first.nick, 'Fixture & live');
    expect(data.rooms.first.introduction, 'Fixture <stream>');
    expect(data.rooms.first.followers, '2.4万');
    expect(data.rooms.first.avatar, 'https://img.example/a.jpg');
    expect(data.rooms.first.onlineViewers, isEmpty);
    expect(data.rooms.first.watching, isEmpty);
    expect(data.rooms.first.link, 'https://live.acfun.cn/live/1');
  });

  test('official blank total plus explicit empty page is authoritative no matches', () {
    expect(AcfunSearchClient.parsePage(searchResponse([], total: 0, blankZero: true), page: 1).rooms, isEmpty);
    expect(AcfunSearchClient.parsePage(searchResponse([], total: 100), page: 99).rooms, isEmpty);
    expect(
      () => AcfunSearchClient.parsePage(searchResponse([], total: 0, emptyMarker: false), page: 1),
      throwsA(isA<AcfunApiException>()),
    );
  });

  test('blocked/truncated/error envelopes and identity mismatches stay errors rather than offline/empty', () {
    for (final body in [
      '<html>access denied</html>',
      jsonEncode({'html': '<div class="empty-page"></div>'}),
      searchResponse([], total: 50, emptyMarker: false),
      searchResponse([searchCard(1), searchCard(2)], total: 1),
      searchResponse([searchCard(1, href: '/u/2')], total: 1),
      searchResponse([searchCard(1, href: 'https://wrong.example/u/1')], total: 1),
      searchResponse([searchCard(1, href: 'javascript:/u/1')], total: 1),
      searchResponse([searchCard(1), searchCard(1)], total: 2),
    ]) {
      expect(() => AcfunSearchClient.parsePage(body, page: 1), throwsA(isA<AcfunApiException>()));
    }
    final room = AcfunSearchClient.parsePage(
      searchResponse([searchCard(1, avatar: 'data:payload')], total: 1),
      page: 1,
    ).rooms.single;
    expect(room.avatar, isEmpty);
  });

  test('20-result application pages map onto 30-result server pages without omissions', () async {
    final requests = <Uri>[];
    final tokens = <CancelToken>[];
    final search = AcfunSearchClient(
      request: (uri, token) async {
        requests.add(uri);
        tokens.add(token);
        return searchServerPage(int.parse(uri.queryParameters['pCursor']!));
      },
    );
    final ids = <String?>[];
    for (var page = 1; page <= 4; page++) {
      ids.addAll((await search.search(' 游戏 &?=+ ', page: page, pageSize: 20)).map((r) => r.roomId));
    }
    expect(ids, [for (var i = 1; i <= 75; i++) '$i']);
    expect(requests.map((u) => u.queryParameters['pCursor']), ['1', '2', '3']);
    for (final uri in requests) {
      expect(uri.queryParameters['keyword'], '游戏 &?=+');
      expect(uri.queryParameters['quickViewId'], 'up-list');
      expect(uri.queryParameters['ajaxpipe'], '1');
    }
    expect(tokens.every((t) => t.isCancelled), isTrue);
  });

  test('cross-page search sizes and final partial page retain exact offsets', () async {
    final search = AcfunSearchClient(
      request: (uri, _) async => searchServerPage(int.parse(uri.queryParameters['pCursor']!)),
    );
    await search.search('fixture', pageSize: 40);
    expect((await search.search('fixture', page: 2, pageSize: 40)).map((r) => r.roomId), [
      for (var i = 41; i <= 75; i++) '$i',
    ]);
    expect(await search.search('fixture', page: 4, pageSize: 40), isEmpty);
  });

  test('search timeout cancels the underlying request and prevents late next-page work', () async {
    final barrier = Completer<String>();
    CancelToken? captured;
    var requests = 0;
    final search = AcfunSearchClient(
      timeout: const Duration(milliseconds: 10),
      request: (uri, token) {
        captured = token;
        requests++;
        return barrier.future;
      },
    );
    await expectLater(search.search('fixture', pageSize: 40), throwsA(isA<AcfunApiException>()));
    expect(captured!.isCancelled, isTrue);
    barrier.complete(searchServerPage(1));
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
  });

  test('search network exceptions are safe and blank/invalid input does not issue requests', () async {
    var requests = 0;
    final search = AcfunSearchClient(
      request: (_, _) async {
        requests++;
        throw StateError('secret-cookie');
      },
    );
    expect(await search.search('  '), isEmpty);
    await expectLater(search.search('fixture', page: 0), throwsA(isA<AcfunApiException>()));
    expect(requests, 0);
    await expectLater(
      search.search('fixture'),
      throwsA(isA<AcfunApiException>().having((e) => e.toString(), 'safe error', isNot(contains('secret-cookie')))),
    );
  });

  test('sparse website pages do not skip authors or prematurely end application pagination', () async {
    final requests = <int>[];
    final search = AcfunSearchClient(
      request: (uri, _) async {
        final page = int.parse(uri.queryParameters['pCursor']!);
        requests.add(page);
        return searchResponse([
          for (var id = (page - 1) * 30 + 1; id <= page * 30 && id <= 100; id++)
            if (id != 60 && id != 100) searchCard(id),
        ], total: 100);
      },
    );
    final actual = <String?>[];
    final sizes = <int>[];
    for (var page = 1; page <= 6; page++) {
      final rows = await search.search('fixture', page: page, pageSize: 20);
      actual.addAll(rows.map((r) => r.roomId));
      sizes.add(rows.length);
    }
    expect(actual, [
      for (var id = 1; id <= 100; id++)
        if (id != 60 && id != 100) '$id',
    ]);
    expect(sizes, [20, 20, 20, 20, 18, 0]);
    expect(requests, [1, 2, 3, 4]);
  });

  test('failed search page retries without dropping the previously buffered authors', () async {
    var failPage = true;
    final requests = <int>[];
    final search = AcfunSearchClient(
      request: (uri, _) async {
        final page = int.parse(uri.queryParameters['pCursor']!);
        requests.add(page);
        if (page == 2 && failPage) {
          failPage = false;
          throw StateError('fixture failure');
        }
        return searchServerPage(page);
      },
    );
    await search.search('fixture', pageSize: 20);
    await expectLater(search.search('fixture', page: 2, pageSize: 20), throwsA(isA<AcfunApiException>()));
    final retry = await search.search('fixture', page: 2, pageSize: 20);
    expect(retry.map((r) => r.roomId), [for (var id = 21; id <= 40; id++) '$id']);
    expect(requests, [1, 2, 2]);
  });

  test('same-page search requests coalesce but a different page never gets the previous result', () async {
    final barrier = Completer<String>();
    var calls = 0;
    final search = AcfunSearchClient(
      request: (_, _) {
        calls++;
        return barrier.future;
      },
    );
    final first = search.search('fixture', pageSize: 10);
    final same = search.search('fixture', pageSize: 10);
    expect(identical(first, same), isTrue);
    await expectLater(search.search('fixture', page: 2, pageSize: 10), throwsA(isA<AcfunApiException>()));
    barrier.complete(searchServerPage(1));
    await first;
    final second = search.search('fixture', page: 2, pageSize: 10);
    await expectLater(search.search('fixture', page: 3, pageSize: 10), throwsA(isA<AcfunApiException>()));
    expect((await second).map((r) => r.roomId), [for (var id = 11; id <= 20; id++) '$id']);
    expect(calls, 1);
  });

  test('search refresh cancels the old generation and ignores its late completion', () async {
    final oldPage = Completer<String>();
    CancelToken? oldCancel;
    var secondCalls = 0;
    final search = AcfunSearchClient(
      request: (uri, cancel) async {
        final page = int.parse(uri.queryParameters['pCursor']!);
        if (page == 2 && ++secondCalls == 1) {
          oldCancel = cancel;
          return oldPage.future;
        }
        return searchServerPage(page);
      },
    );
    await search.search('fixture', pageSize: 20);
    final old = search.search('fixture', page: 2, pageSize: 20);
    final rejected = expectLater(old, throwsA(isA<AcfunApiException>()));
    await search.search('fixture', pageSize: 20);
    expect(oldCancel!.isCancelled, isTrue);
    oldPage.complete(searchServerPage(2));
    await rejected;
    final fresh = await search.search('fixture', page: 2, pageSize: 20);
    expect(fresh.map((r) => r.roomId), [for (var id = 21; id <= 40; id++) '$id']);
    expect(secondCalls, 2);
  });

  test('search retains bounded remaining rows and requires refresh after query eviction', () async {
    var calls = 0;
    final search = AcfunSearchClient(
      maxQueries: 2,
      request: (uri, _) async {
        calls++;
        return searchServerPage(int.parse(uri.queryParameters['pCursor']!));
      },
    );
    for (final query in ['a', 'b', 'c']) {
      await search.search(query, pageSize: 20);
    }
    await expectLater(search.search('a', page: 2, pageSize: 20), throwsA(isA<AcfunApiException>()));
    expect((await search.search('c', page: 2, pageSize: 20)), hasLength(20));
    expect(calls, 4);
  });

  test('explicitly filtered-out server pages advance with a bounded request budget', () async {
    var calls = 0;
    final search = AcfunSearchClient(
      request: (uri, _) async {
        calls++;
        final page = int.parse(uri.queryParameters['pCursor']!);
        return page == 2 ? searchResponse([], total: 75) : searchServerPage(page);
      },
    );
    await search.search('fixture', pageSize: 20);
    final second = await search.search('fixture', page: 2, pageSize: 20);
    expect(second.map((r) => r.roomId), [
      for (var id = 21; id <= 30; id++) '$id',
      for (var id = 61; id <= 70; id++) '$id',
    ]);
    expect(calls, 3);
    calls = 0;
    final allEmpty = AcfunSearchClient(
      request: (_, _) async {
        calls++;
        return searchResponse([], total: 3000);
      },
    );
    await expectLater(allEmpty.search('fixture'), throwsA(isA<AcfunApiException>()));
    expect(calls, 4);
  });

  test('an absent or structured directory cursor is not an authoritative end', () {
    for (final cursor in <Object?>[null, {}, []]) {
      expect(
        () => AcfunApi.parseDirectory({'result': 0, 'liveList': [], 'pcursor': cursor}),
        throwsA(isA<AcfunApiException>()),
      );
    }
  });
}
