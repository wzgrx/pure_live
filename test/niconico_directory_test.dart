import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_directory.dart';
import 'package:pure_live/core/site/niconico/niconico_site.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';

Matcher failure(NiconicoFailure kind) => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', kind));
Map<String, dynamic> row({bool search = false, int id = 100}) => {
  search ? 'nicoliveProgramId' : 'id': 'lv$id',
  search ? 'status' : 'liveCycle': 'ON_AIR',
  'title': '公開ライブ & game',
  'providerType': 'community',
  'watchPageUrl': 'https://live.nicovideo.jp/watch/lv$id?ref=fixture',
  'listingThumbnail': 'https://listing-thumbnail.live.nicovideo.jp?image=fixture',
  'flippedListingThumbnail': 'https://asset2.dlive.nicovideo.jp/screenshot.jpg',
  if (search)
    'supplier': {
      'name': 'Broadcaster',
      'icons': {'uri150x150': 'https://secure-dcdn.cdn.nimg.jp/icon.jpg'},
    },
  if (!search)
    'programProvider': {'id': '1', 'name': 'Broadcaster', 'icon': 'https://secure-dcdn.cdn.nimg.jp/icon.jpg'},
  'statistics': {'watchCount': 12, 'commentCount': 99},
};
Map<String, dynamic> envelope({bool search = false, List<dynamic>? rows, Object? total = 1}) => {
  'meta': {'statusCode': 200, 'errorCode': 'OK', if (!search) 'totalCount': total},
  'data': search
      ? {
          'programs': rows ?? [row(search: true)],
          'totalCount': total,
        }
      : rows ?? [row()],
};

void main() {
  for (final search in [false, true]) {
    test('${search ? 'search' : 'recent'} keeps public identities, artwork and cumulative audience only', () {
      final result = NiconicoDirectory.parse(jsonEncode(envelope(search: search)), page: 1, search: search);
      final room = result.rooms.single;
      expect(room.roomId, 'lv100');
      expect(room.liveStatus, LiveStatus.live);
      expect(room.totalViewers, '12');
      expect(room.onlineViewers, isEmpty);
      expect(room.audienceMetricType, AudienceMetricType.totalViewers);
      expect(room.cover, 'https://asset2.dlive.nicovideo.jp/screenshot.jpg');
      expect(room.avatar, 'https://secure-dcdn.cdn.nimg.jp/icon.jpg');
      expect(room.link, 'https://live.nicovideo.jp/watch/lv100');
      expect(room.data, isNull);
      expect(result.hasMore, isFalse);
      expect(() => result.rooms.clear(), throwsUnsupportedError);
      expect(jsonEncode(room.toJson()), isNot(contains('commentCount')));
    });
  }
  test('native recent page uses zero-based page offset, not a row offset', () async {
    final calls = <Uri>[];
    final api = NiconicoApi(
      request: (uri, token) async {
        calls.add(uri);
        return (status: 200, body: jsonEncode(envelope(total: 200)));
      },
    );
    final site = NiconicoSite(api: api);
    final result = await site.getDirectoryPage(page: 2);
    expect(result.page, 2);
    expect(result.hasMore, isTrue);
    expect(calls.single.path, '/front/api/pages/recent/v1/programs');
    expect(calls.single.queryParameters, {'tab': 'common', 'offset': '1', 'sortOrder': 'recentDesc'});
  });
  test('keyword search encodes Unicode and query punctuation without parameter injection', () async {
    late Uri target;
    final api = NiconicoApi(
      request: (uri, token) async {
        target = uri;
        return (status: 200, body: jsonEncode(envelope(search: true)));
      },
    );
    await NiconicoSite(api: api).searchRooms('  遊戯 & status=past?#  ', page: 2, pageSize: 20);
    expect(target.path, '/front/api/pages/search/v1/programs');
    expect(target.queryParameters, {
      'keyword': '遊戯 & status=past?#',
      'column': 'main',
      'status': 'onair',
      'page': '2',
      'disableGrouping': 'true',
    });
  });
  test('categories use the seven observed tabs and reject foreign taxonomy', () async {
    final calls = <Uri>[];
    final site = NiconicoSite(
      api: NiconicoApi(
        request: (uri, token) async {
          calls.add(uri);
          return (status: 200, body: jsonEncode(envelope(rows: [], total: 0)));
        },
      ),
    );
    final categories = (await site.getCategores(1, 30)).single.children;
    expect(categories.map((e) => e.areaId), NiconicoDirectory.categories);
    expect(await site.getCategores(2, 30), isEmpty);
    for (final area in categories) {
      await site.getCategoryRooms(area);
    }
    expect(calls.map((u) => u.queryParameters['tab']), NiconicoDirectory.categories);
    for (final area in [
      LiveArea(platform: 'other', areaType: 'recent', areaId: 'common'),
      LiveArea(platform: 'niconico', areaType: 'rank', areaId: 'common'),
      LiveArea(platform: 'niconico', areaType: 'recent', areaId: 'all'),
    ]) {
      expect(() => site.getDirectoryPage(category: area), failure(NiconicoFailure.schema));
    }
    expect(calls, hasLength(7));
    expect(site.directoryNoticeKey, 'niconico_directory_scope');
  });
  test('legacy recommendation and search retain full native pages rather than silently skipping rows', () async {
    final api = NiconicoApi(
      request: (uri, token) async {
        final search = uri.path.contains('/search/');
        final size = search ? 40 : 70;
        return (
          status: 200,
          body: jsonEncode(
            envelope(
              search: search,
              total: size,
              rows: List.generate(size, (i) => row(search: search, id: 100 + i)),
            ),
          ),
        );
      },
    );
    final site = NiconicoSite(api: api);
    expect(await site.getRecommendRooms(pageSize: 20), hasLength(70));
    expect(await site.searchRooms('game', pageSize: 20), hasLength(40));
  });
  test('short and empty native pages retain explicit total-count pagination evidence', () {
    expect(NiconicoDirectory.parse(jsonEncode(envelope(rows: [], total: 71)), page: 1, search: false).hasMore, isTrue);
    expect(NiconicoDirectory.parse(jsonEncode(envelope(total: 140)), page: 2, search: false).hasMore, isFalse);
    expect(
      NiconicoDirectory.parse(jsonEncode(envelope(search: true, total: 81)), page: 2, search: true).hasMore,
      isTrue,
    );
  });
  test('empty keyword is empty, not a pretend all-site directory request', () async {
    var calls = 0;
    final directory = NiconicoDirectory(
      api: NiconicoApi(
        request: (uri, token) async {
          calls++;
          throw StateError('unexpected request');
        },
      ),
    );
    expect((await directory.search('  ')).rooms, isEmpty);
    expect(calls, 0);
  });
  test('invalid input fails before I/O', () async {
    var calls = 0;
    final api = NiconicoApi(
      request: (uri, token) async {
        calls++;
        throw StateError('unexpected');
      },
    );
    final directory = NiconicoDirectory(api: api);
    for (final p in [0, -1, 10001]) {
      await expectLater(directory.recent(page: p), failure(NiconicoFailure.schema));
      await expectLater(directory.search('x', page: p), failure(NiconicoFailure.schema));
    }
    await expectLater(directory.search('x' * 501), failure(NiconicoFailure.schema));
    await expectLater(directory.recent(tab: '../all'), failure(NiconicoFailure.schema));
    await expectLater(api.listing(path: '/watch/lv100', query: {}), failure(NiconicoFailure.schema));
    await expectLater(NiconicoSite(api: api).getRecommendRooms(pageSize: 0), failure(NiconicoFailure.schema));
    expect(calls, 0);
  });
  test('pre-cancel allocates no request and caller cancellation stays local', () async {
    var calls = 0;
    final api = NiconicoApi(
      request: (uri, token) async {
        calls++;
        return (status: 200, body: jsonEncode(envelope()));
      },
    );
    final cancel = CancelToken()..cancel();
    await expectLater(NiconicoDirectory(api: api).recent(cancel: cancel), failure(NiconicoFailure.cancelled));
    expect(calls, 0);
    final caller = CancelToken();
    await NiconicoDirectory(api: api).recent(cancel: caller);
    expect(caller.isCancelled, isFalse);
  });
  test('pending directory cancellation discards late response and cancels child transport', () async {
    final started = Completer<CancelToken>();
    final response = Completer<({int status, String body})>();
    final directory = NiconicoDirectory(
      api: NiconicoApi(
        request: (uri, token) {
          started.complete(token);
          return response.future;
        },
      ),
    );
    final caller = CancelToken();
    final pending = directory.recent(cancel: caller);
    final assertion = expectLater(pending, failure(NiconicoFailure.cancelled));
    final child = await started.future;
    caller.cancel();
    await assertion;
    expect(child.isCancelled, isTrue);
    response.complete((status: 200, body: jsonEncode(envelope())));
    await Future<void>.delayed(Duration.zero);
  });
  test('deadline cancels an unfinished listing transport', () async {
    final started = Completer<CancelToken>();
    final response = Completer<({int status, String body})>();
    final api = NiconicoApi(
      deadline: const Duration(milliseconds: 20),
      request: (uri, token) {
        started.complete(token);
        return response.future;
      },
    );
    await expectLater(NiconicoDirectory(api: api).recent(), failure(NiconicoFailure.transport));
    expect((await started.future).isCancelled, isTrue);
    response.completeError(StateError('late network failure'));
    await Future<void>.delayed(Duration.zero);
  });
  for (final spec in [
    (403, NiconicoFailure.access),
    (429, NiconicoFailure.rateLimited),
    (503, NiconicoFailure.service),
    (400, NiconicoFailure.transport),
  ]) {
    test('listing HTTP ${spec.$1} preserves failure rather than empty EOF', () async {
      final api = NiconicoApi(request: (uri, token) async => (status: spec.$1, body: ''));
      await expectLater(NiconicoDirectory(api: api).recent(), failure(spec.$2));
    });
  }
  test('optional artwork and unknown audience do not discard valid live cards', () {
    final value = row();
    value['statistics'] = {'watchCount': null};
    value['flippedListingThumbnail'] = 'https://evil.invalid/a';
    final result = NiconicoDirectory.parse(jsonEncode(envelope(rows: [value])), page: 1, search: false).rooms.single;
    expect(result.cover, startsWith('https://listing-thumbnail.live.nicovideo.jp'));
    expect(result.totalViewers, isNull);
  });
  test('search official/channel fallback uses social-group attribution when supplier is absent', () {
    final value = row(search: true)..remove('supplier');
    value['providerType'] = 'official';
    value['socialGroup'] = {'name': 'Channel', 'thumbnailUrl': 'https://secure-dcdn.cdn.nimg.jp/channel.jpg'};
    final result = NiconicoDirectory.parse(
      jsonEncode(envelope(search: true, rows: [value])),
      page: 1,
      search: true,
    ).rooms.single;
    expect(result.nick, 'Channel');
    expect(result.avatar, endsWith('/channel.jpg'));
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing envelope': (d) => d.remove('meta'),
    'bad total': (d) => d['meta']['totalCount'] = '1',
    'missing total': (d) => d['meta'].remove('totalCount'),
    'negative count': (d) => d['data'][0]['statistics']['watchCount'] = -1,
    'wrong status': (d) => d['data'][0]['liveCycle'] = 'ENDED',
    'wrong provider': (d) => d['data'][0]['providerType'] = 'unknown',
    'missing title': (d) => d['data'][0].remove('title'),
    'missing attribution': (d) => d['data'][0].remove('programProvider'),
    'too many rows': (d) {
      d['meta']['totalCount'] = 71;
      d['data'] = List.generate(71, (i) => row(id: i + 1));
    },
    'total smaller than rows': (d) => d['meta']['totalCount'] = 0,
  };
  for (final spec in mutations.entries) {
    test('malformed ${spec.key} stays a schema failure', () {
      final data = envelope();
      spec.value(data);
      expect(() => NiconicoDirectory.parse(jsonEncode(data), page: 1, search: false), failure(NiconicoFailure.schema));
    });
  }
  for (final watchUrl in [
    'https://live.nicovideo.jp/watch/lv101',
    'https://live.nicovideo.jp.evil.invalid/watch/lv100',
  ]) {
    test('directory identity mismatch $watchUrl is rejected', () {
      final value = row()..['watchPageUrl'] = watchUrl;
      expect(
        () => NiconicoDirectory.parse(jsonEncode(envelope(rows: [value])), page: 1, search: false),
        failure(NiconicoFailure.identity),
      );
    });
  }
  test('duplicate IDs are not silently collapsed into a premature EOF', () {
    expect(
      () => NiconicoDirectory.parse(jsonEncode(envelope(rows: [row(), row()], total: 2)), page: 1, search: false),
      failure(NiconicoFailure.identity),
    );
  });
  test('API error envelope is not an empty directory', () {
    final data = envelope();
    data['meta']['errorCode'] = 'FAILED';
    expect(() => NiconicoDirectory.parse(jsonEncode(data), page: 1, search: false), failure(NiconicoFailure.service));
  });
  for (final body in ['not-json', '[]', ' ' * (NiconicoWatch.responseLimit + 1)]) {
    test('invalid bounded JSON body ${body.length}', () {
      expect(() => NiconicoDirectory.parse(body, page: 1, search: false), failure(NiconicoFailure.schema));
    });
  }
}
