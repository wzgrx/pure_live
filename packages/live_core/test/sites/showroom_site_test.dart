// ShowroomSite over the recorded SHOWROOM responses (ReplayHttp) and a few
// synthetic ones: the request headers, the shared snapshot and its 30 s
// reuse (page 1 of the directory and the search asks anew, later pages reuse
// it: 19-1), the directory pages and 3.x's slices, the search, room details
// by id and by key for entry, refresh and recording (with the comment
// arguments, 19-3), qualities, lines and recovery, cancellation, links and
// the error mapping. Requests are compared with the ones 3.x sent
// (expected.json records them).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/showroom';
const _api = 'https://www.showroom-live.com/api';

/// The live room of S02–S05 and its key.
const _live = '577362';
const _key = '0c1c310117354';

/// The offline room of S03/S04.
const _offline = '61576';

const _liveSamples = ['S03-profile-live', 'S04-live-info-live', 'S05-streaming-live'];
const _offlineSamples = ['S03-profile-offline', 'S04-live-info-offline', 'S05-streaming-offline'];

const _mediaHeaders = {
  'referer': 'https://www.showroom-live.com/',
  'user-agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
};

ReplaySample _synthetic(String url, Object body, {int status = 200}) => ReplaySample(
  method: 'GET',
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

/// The 404 SHOWROOM answers for any unknown room (samples S02/S03-*-notfound).
ReplaySample _missing(String url) =>
    _synthetic(url, Fixture.load('showroom', 'S03-profile-notfound').body, status: 404);

typedef _Setup = ({ShowroomSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: ShowroomSite(http, now: now), http: http);
}

List<String> _sent(Iterable<LiveRequest> requests) => [for (final request in requests) '${request.url}'];

/// 3.x's requests of a traced legacy call, without the empty `?` 3.x left
/// on `onlives`.
List<String> _legacyRequests(Object? traced) => [
  for (final url in ((traced! as Map<String, dynamic>)['requests'] as List).cast<String>())
    url.replaceFirst(RegExp(r'\?$'), ''),
];

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

Map<String, dynamic> _legacy(String sample) => Fixture.load('showroom', sample).legacy as Map<String, dynamic>;

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

const _genreMusic = LiveArea(
  platform: 'showroom',
  areaType: 'genre',
  typeName: 'SHOWROOM',
  areaId: '112',
  areaName: 'Music',
);

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
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('showroom', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('showroom', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

void main() {
  group('requests', () {
    test("3.x's headers on every request, redirects not followed, sent as showroom", () async {
      final setup = _setup(['S02-status-key', 'S01-onlives', ..._liveSamples]);
      await setup.site.getCategories(1, 30);
      final room = await setup.site.getRoomDetail(roomId: _key);
      await setup.site.resolvePlayUrls(
        detail: room,
        quality: (await setup.site.getPlayQualities(detail: room)).first,
      );
      expect(setup.http.requests.map((request) => request.url.path), [
        '/api/live/onlives',
        '/api/room/status',
        '/api/room/profile',
        '/api/live/live_info',
        '/api/live/streaming_url',
      ]);
      for (final request in setup.http.requests) {
        expect(request.headers, {
          'user-agent': _mediaHeaders['user-agent'],
          'accept': 'application/json, text/plain, */*',
          'referer': 'https://www.showroom-live.com/',
        });
        expect(request.followRedirects, isFalse);
        expect(request.site, 'showroom');
        expect(request.url.host, 'www.showroom-live.com');
      }
      expect((setup.site.id, setup.site.name), ('showroom', 'SHOWROOM'));
      expect(setup.site.directoryNoticeKey, 'showroom_directory_scope');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        ShowroomSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(ShowroomSite(_Failing(TransportReason.cancelled)).getCategories(1, 30), _cancelled);
      for (final (status, type) in [
        (403, isA<RiskControl>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (301, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(ShowroomSite(http).getRoomDetail(roomId: _live), throwsA(type), reason: '$status');
        await expectLater(ShowroomSite(http).getCategories(1, 30), throwsA(type), reason: '$status');
      }
      final html = _Scripted((request) => _response(request, '<html></html>'));
      await expectLater(ShowroomSite(html).searchRooms('king'), throwsA(isA<ApiChanged>()));
    });
  });

  group('the snapshot', () {
    test('categories, recommendations, genre rooms and search share one snapshot for 30 s (3.x)', () async {
      var now = DateTime.utc(2026, 9, 28);
      final setup = _setup(['S01-onlives'], now: () => now);
      final legacy = _legacy('S01-onlives');
      await setup.site.getCategories(1, 30);
      await setup.site.getRecommendRooms();
      await setup.site.getCategoryRooms(_genreMusic);
      await setup.site.searchRooms('king');
      await setup.site.searchRooms('king', page: 2);
      await setup.site.getDirectoryPage(page: 2);
      await setup.site.searchRoomsCancellable('king', page: 2, cancel: CancelToken());
      expect(setup.http.requests, hasLength(1));
      now = now.add(const Duration(seconds: 29));
      await setup.site.getRecommendRooms(page: 2);
      expect(setup.http.requests, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(2), reason: 'a snapshot 30 s old is fetched again');
      // 3.x: getCategores, getRecommendRooms and searchRooms without a token
      // shared one request; the directory page 1 with a token asked again.
      // Same now: page 1 of the directory is the pull to refresh (19-1).
      final cache = _setup(['S01-onlives']);
      await cache.site.getCategories(1, 30);
      await cache.site.getRecommendRooms();
      await cache.site.searchRooms('king');
      await cache.site.getDirectoryPage(cancel: CancelToken());
      expect(_sent(cache.http.requests), _legacyRequests(legacy['cache']));
    });

    test('19-1: page 1 of the directory and the search asks anew; later pages reuse it for 30 s', () async {
      var now = DateTime.utc(2026, 9, 28);
      final setup = _setup(['S01-onlives'], now: () => now);
      final token = CancelToken();
      final first = await setup.site.getDirectoryPage(cancel: token);
      expect(setup.http.requests.single.cancel, same(token));
      final second = await setup.site.getDirectoryPage(page: 2, cancel: CancelToken());
      final third = await setup.site.getDirectoryPage(page: 3, cancel: CancelToken());
      final music = await setup.site.getDirectoryPage(page: 2, category: _genreMusic, cancel: CancelToken());
      await setup.site.searchRoomsCancellable('a', page: 2, pageSize: 20, cancel: CancelToken());
      await setup.site.getCategories(1, 30);
      await setup.site.getRecommendRooms(page: 2);
      expect(setup.http.requests, hasLength(1), reason: '3.x asked once per page with a token (five requests)');
      final ids = [
        for (final page in [first, second, third]) ...page.rooms.map((room) => room.roomId),
      ];
      expect(ids.toSet(), hasLength(ids.length), reason: 'one snapshot: no room twice');
      expect(ids, hasLength(64), reason: 'and none skipped');
      expect((music.page, third.hasMore), (2, false));
      await setup.site.searchRoomsCancellable('king', cancel: token);
      expect(setup.http.requests, hasLength(2), reason: 'page 1 of the search is a refresh too');
      now = now.add(const Duration(seconds: 29));
      await setup.site.searchRoomsCancellable('king', page: 2, cancel: token);
      expect(setup.http.requests, hasLength(2), reason: 'reused: the search page 1 snapshot is 29 s old');
      now = now.add(const Duration(seconds: 1));
      await setup.site.getDirectoryPage(page: 2, cancel: token);
      expect(setup.http.requests, hasLength(3), reason: 'a snapshot 30 s old is fetched again, with the token');
      expect(setup.http.requests.last.cancel, same(token));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(3), reason: 'which is shared again');
      await setup.site.getDirectoryPage();
      expect(setup.http.requests, hasLength(4), reason: 'page 1 without a token refreshes too');
      now = now.subtract(const Duration(minutes: 1));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(5), reason: 'a snapshot from the future (clock set back) is not reused');
    });

    test('a cancellable later page only reuses an arrived snapshot; a cancelled or failed fetch is not kept', () async {
      final body = Fixture.load('showroom', 'S01-onlives').body;
      final gate = Completer<void>();
      var status = 200;
      final http = _Scripted((request) async {
        if (request.cancel == null) await gate.future;
        return _response(request, status == 200 ? body : '', status: status);
      });
      final site = ShowroomSite(http);
      final shared = site.getRecommendRooms();
      final token = CancelToken();
      expect((await site.getDirectoryPage(page: 2, cancel: token)).rooms, hasLength(30));
      expect(http.requests.map((request) => request.cancel), [isNull, same(token)]);
      gate.complete();
      expect(await shared, hasLength(30));
      await site.getDirectoryPage(page: 3, cancel: token);
      expect(http.requests, hasLength(2));
      token.cancel();
      await expectLater(site.getDirectoryPage(page: 2, cancel: token), _cancelled);
      await expectLater(site.getDirectoryPage(cancel: token), _cancelled);
      expect(http.requests, hasLength(2));
      final lateCancel = CancelToken();
      final dropped = _Scripted((request) {
        lateCancel.cancel();
        return _response(request, body);
      });
      final other = ShowroomSite(dropped);
      await expectLater(other.getDirectoryPage(cancel: lateCancel), _cancelled);
      await other.getRecommendRooms();
      expect(dropped.requests, hasLength(2), reason: 'an answer after cancellation is not kept');
      status = 503;
      await expectLater(site.getDirectoryPage(cancel: CancelToken()), throwsA(isA<NetworkFailure>()));
      status = 200;
      await site.getRecommendRooms();
      expect(http.requests, hasLength(3), reason: 'the snapshot before the failed refresh is still shared');
    });

    test('concurrent callers share the fetch under way; a failed fetch is forgotten', () async {
      final body = Fixture.load('showroom', 'S01-onlives').body;
      final gate = Completer<void>();
      var fail = true;
      final http = _Scripted((request) async {
        await gate.future;
        return fail ? _response(request, '', status: 500) : _response(request, body);
      });
      final site = ShowroomSite(http);
      final first = site.getCategories(1, 30);
      final second = site.getRecommendRooms();
      final third = site.searchRooms('king');
      gate.complete();
      await expectLater(first, throwsA(isA<NetworkFailure>()));
      await expectLater(second, throwsA(isA<NetworkFailure>()));
      await expectLater(third, throwsA(isA<NetworkFailure>()));
      expect(http.requests, hasLength(1), reason: '3.x sent one request per caller until the first answer');
      fail = false;
      expect(await site.getRecommendRooms(), hasLength(30));
      expect(http.requests, hasLength(2));
    });
  });

  group('catalog and directory', () {
    test('the category and its genres; page 2 and a size below 1 are empty without a request (3.x)', () async {
      final setup = _setup(['S01-onlives']);
      final legacy = _legacy('S01-onlives');
      final category = (await setup.site.getCategories(1, 30)).single;
      final areas = ((_result(legacy['getCategores'])! as List).single as Map<String, dynamic>)['children'] as List;
      expect(category.children.map((area) => area.areaId), areas.map((area) => (area as Map)['areaId']));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getCategores']));
      final fresh = _setup(['S01-onlives']);
      expect(await fresh.site.getCategories(2, 30), isEmpty);
      expect(await fresh.site.getCategories(1, 0), isEmpty);
      expect(fresh.http.requests, isEmpty);
    });

    test('directory pages: the rooms, pages and requests of 3.x', () async {
      final legacy = _legacy('S01-onlives')['getDirectoryPage'] as Map<String, dynamic>;
      final categories = (await _setup(['S01-onlives']).site.getCategories(1, 30)).single.children;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final [genre, number] = key.split(':');
        final want = _result(value);
        if (want is! Map<String, dynamic> || !want.containsKey('rooms')) continue;
        final setup = _setup(['S01-onlives']);
        final area = genre == 'recommend' ? null : categories.firstWhere((area) => area.areaId == genre);
        final page = await setup.site.getDirectoryPage(page: int.parse(number), category: area, cancel: CancelToken());
        expect(page.rooms.map((room) => room.roomId), (want['rooms'] as List).map((room) => (room as Map)['roomId']));
        expect((page.page, page.hasMore), (want['page'], want['hasMore']), reason: key);
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: key);
      }
    });

    test('caller errors are refused without a request (3.x asked first); an unknown genre is NotFound', () async {
      final setup = _setup(['S01-onlives']);
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsRangeError);
      for (final area in [
        const LiveArea(platform: 'bilibili', areaType: 'genre', areaId: '0'),
        const LiveArea(platform: 'showroom', areaType: 'directory', areaId: '0'),
        const LiveArea(platform: 'showroom', areaType: 'genre', areaId: 'x'),
        const LiveArea(platform: 'showroom', areaType: 'genre', areaId: '-1'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: '$area');
      }
      expect(setup.http.requests, isEmpty);
      final legacy = _legacy('S01-onlives')['getDirectoryPage'] as Map<String, dynamic>;
      expect((_result(legacy['otherPlatform:1'])! as Map)['message'], 'Showroom identity');
      expect((_result(legacy['recommend:0'])! as Map)['message'], 'Showroom schema');
      const gone = LiveArea(platform: 'showroom', areaType: 'genre', areaId: '99999', areaName: 'Gone');
      await expectLater(setup.site.getDirectoryPage(category: gone, cancel: CancelToken()), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getCategoryRooms(gone), throwsA(isA<NotFound>()));
      expect((_result(legacy['99999:1'])! as Map)['message'], 'Showroom missing');
    });

    test("3.x's slices; the ones 3.x served nothing for are empty without a request", () async {
      final legacy = _legacy('S01-onlives');
      for (final MapEntry(:key, :value) in (legacy['getRecommendRooms'] as Map<String, dynamic>).entries) {
        final [_, page, _, size] = key.split(' ');
        final setup = _setup(['S01-onlives']);
        final rooms = await setup.site.getRecommendRooms(page: int.parse(page), pageSize: int.parse(size));
        expect(rooms.map((room) => room.roomId), (_result(value)! as List).map((room) => (room as Map)['roomId']));
        if (ShowroomApi.validSlice(page: int.parse(page), pageSize: int.parse(size))) {
          expect(_sent(setup.http.requests), _legacyRequests(value), reason: key);
        } else {
          expect(setup.http.requests, isEmpty, reason: '$key: 3.x asked, then gave nothing');
        }
      }
      for (final MapEntry(:key, :value) in (legacy['getCategoryRooms'] as Map<String, dynamic>).entries) {
        final [genre, _, page] = key.split(' ');
        if (_result(value) is! List) continue;
        final area = LiveArea(platform: 'showroom', areaType: 'genre', areaId: genre);
        final rooms = await _setup(['S01-onlives']).site.getCategoryRooms(area, page: int.parse(page));
        expect(rooms.map((room) => room.roomId), (_result(value)! as List).map((room) => (room as Map)['roomId']));
      }
    });
  });

  group('search', () {
    test("3.x's results and requests for every keyword", () async {
      final legacy = _legacy('S01-onlives')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in legacy.entries) {
        final setup = _setup(['S01-onlives']);
        final (keyword, page) = switch (key) {
          'blank' => ('  ', 1),
          'link' => ('https://www.showroom-live.com/r/$_key', 1),
          _ => (key.substring(0, key.lastIndexOf(' page ')), int.parse(key.substring(key.lastIndexOf(' ') + 1))),
        };
        final rooms = await setup.site.searchRoomsCancellable(keyword, page: page, pageSize: 20, cancel: CancelToken());
        expect(rooms.map((room) => room.roomId), (_result(value)! as List).map((room) => (room as Map)['roomId']));
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: key);
      }
    });

    test('a page 3.x served nothing for is empty without a request; cancellation reaches the request', () async {
      final setup = _setup(['S01-onlives']);
      for (final (page, size) in [(0, 20), (1, 0), (1, 101)]) {
        expect(await setup.site.searchRooms('king', page: page, pageSize: size), isEmpty);
      }
      expect(setup.http.requests, isEmpty);
      final token = CancelToken();
      expect(await setup.site.searchRoomsCancellable('king', cancel: token), hasLength(1));
      expect(setup.http.requests.single.cancel, same(token));
      token.cancel();
      await expectLater(setup.site.searchRoomsCancellable('king', cancel: token), _cancelled);
      await expectLater(setup.site.getDirectoryPage(cancel: token), _cancelled);
      expect(setup.http.requests, hasLength(1));
    });

    test('an answer after cancellation is dropped', () async {
      final token = CancelToken();
      final body = Fixture.load('showroom', 'S01-onlives').body;
      final http = _Scripted((request) {
        token.cancel();
        return _response(request, body);
      });
      await expectLater(ShowroomSite(http).searchRoomsCancellable('king', cancel: token), _cancelled);
      expect(http.requests, hasLength(1));
    });
  });

  group('rooms', () {
    test('by id: profile and live_info together, then the streams of a live room, as 3.x', () async {
      final legacy = _legacy('S03-profile-live')[_live] as Map<String, dynamic>;
      for (final entry in ['getRoomDetail', 'getRoomDetailForRecording', 'getRoomDetailForRefresh']) {
        final setup = _setup(_liveSamples);
        final room = await switch (entry) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRecording' => setup.site.getRoomDetailForRecording(roomId: _live),
          _ => setup.site.getRoomDetailForRefresh(roomId: _live),
        };
        expect(_sent(setup.http.requests), _legacyRequests(legacy[entry]), reason: entry);
        expect(room.roomId, _live);
        expect(room.isLiveNow, isTrue);
        expect(room.startedAt, DateTime.utc(2026, 9, 27, 13, 49, 2));
        expect(room.restriction, LiveRestriction.none);
        expect(room.totalViewers, '3941');
        if (entry == 'getRoomDetailForRefresh') {
          expect(room.data, isNull, reason: 'refresh keeps 3.x metadata only');
          expect(room.danmakuData, isNull, reason: 'comments connect on room entry');
        } else {
          final data = room.data! as ShowroomRoomData;
          expect(data.roomId, _live);
          expect(data.streams, hasLength(8), reason: 'the rows as answered, WebRTC included');
          // 19-3 (the platform part): the comment arguments, no request.
          final args = room.danmakuData! as ShowroomDanmakuArgs;
          expect((args.roomId, args.host, args.key), (_live, 'online.showroom-live.com', '6e6c686835796846:23483509'));
        }
      }
    });

    test('by key: room/status first, and the room is its numeric id, as 3.x (REG-SHOWROOM-003)', () async {
      final legacy = _legacy('S03-profile-live')[_key] as Map<String, dynamic>;
      for (final entry in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        final setup = _setup(['S02-status-key', ..._liveSamples]);
        final room = entry == 'getRoomDetail'
            ? await setup.site.getRoomDetail(roomId: _key)
            : await setup.site.getRoomDetailForRefresh(roomId: _key);
        expect(room.roomId, _live, reason: '3.x returned the profile room id');
        expect(room.roomId, (_result(legacy[entry])! as Map)['roomId']);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[entry]), reason: entry);
      }
      final setup = _setup(['S02-status-key', 'S04-live-info-live']);
      expect(await setup.site.getLiveStatus(roomId: _key), isTrue);
      expect(setup.http.requests.map((request) => request.url.path), ['/api/room/status', '/api/live/live_info']);
    });

    test('an offline room: two requests at every depth, no data (3.x)', () async {
      final legacy = _legacy('S03-profile-offline')[_offline] as Map<String, dynamic>;
      final setup = _setup(_offlineSamples);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getRoomDetail']));
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.data, isNull);
      expect(room.danmakuData, isNull);
      expect(
        (room.watching, room.totalViewers, room.startedAt, room.restriction),
        ('', '', null, null),
        reason: '19-4',
      );
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(3), reason: 'live_info for the status; qualities ask nothing');
    });

    test('getLiveStatus reads live_info alone (3.x read the refresh detail: two requests)', () async {
      final setup = _setup(_liveSamples);
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect(_sent(setup.http.requests), ['$_api/live/live_info?room_id=$_live']);
      final legacy = _legacy('S03-profile-live')[_live] as Map<String, dynamic>;
      expect(_legacyRequests(legacy['getLiveStatus']), hasLength(2));
    });

    test('unknown rooms and keys are NotFound; what is neither an id nor a key sends nothing', () async {
      final key = _setup(['S02-status-notfound']);
      await expectLater(key.site.getRoomDetail(roomId: 'zxqvnoroomfixture'), throwsA(isA<NotFound>()));
      expect(
        _sent(key.http.requests),
        _legacyRequests((_legacy('S02-status-notfound')['zxqvnoroomfixture'] as Map)['getRoomDetail']),
      );
      final id = _setup(['S03-profile-notfound'], extra: [_missing('$_api/live/live_info?room_id=1')]);
      await expectLater(id.site.getRoomDetailForRefresh(roomId: '1'), throwsA(isA<NotFound>()));
      expect(id.http.requests, hasLength(2));
      await expectLater(id.site.getLiveStatus(roomId: '1'), throwsA(isA<NotFound>()));
      final none = _setup([]);
      for (final reference in ['a b', '../x', '', 'x' * 129]) {
        await expectLater(none.site.getRoomDetail(roomId: reference), throwsA(isA<NotFound>()), reason: reference);
      }
      expect(none.http.requests, isEmpty);
    });

    test('a live room whose streams fail still opens; the qualities ask again (3.x failed the room)', () async {
      final failing = _setup(
        ['S03-profile-live', 'S04-live-info-live'],
        extra: [_synthetic('$_api/live/streaming_url?room_id=$_live&abr_available=1', '', status: 503)],
      );
      final room = await failing.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      expect((room.data! as ShowroomRoomData).streams, isNull);
      await expectLater(failing.site.getPlayQualities(detail: room), throwsA(isA<NetworkFailure>()));
      expect(failing.http.requests.map((request) => request.url.path).last, '/api/live/streaming_url');
      expect(failing.http.requests, hasLength(4));
      final empty = _setup(
        ['S03-profile-live', 'S04-live-info-live'],
        extra: [
          _synthetic('$_api/live/streaming_url?room_id=$_live&abr_available=1', {'streaming_url_list': <Object?>[]}),
        ],
      );
      final open = await empty.site.getRoomDetail(roomId: _live);
      expect(open.isLiveNow, isTrue, reason: 'a live room without HLS (paid, WebRTC only) opens');
      await expectLater(empty.site.getPlayQualities(detail: open), throwsA(isA<StreamUnavailable>()));
      expect(empty.http.requests, hasLength(3), reason: 'the empty rows are kept: no second request');
      final broken = _setup(
        ['S03-profile-live', 'S04-live-info-live'],
        extra: [
          _synthetic('$_api/live/streaming_url?room_id=$_live&abr_available=1', {
            'streaming_url_list': [
              {'type': 'hls', 'url': 'http://x.showroom-txlive.com/a.m3u8'},
            ],
          }),
        ],
      );
      final shown = await broken.site.getRoomDetailForRecording(roomId: _live);
      await expectLater(broken.site.getPlayQualities(detail: shown), throwsA(isA<ApiChanged>()));
    });

    test("an answer for another room is ApiChanged (3.x's identity check)", () async {
      final setup = _setup(
        ['S04-live-info-offline'],
        extra: [_synthetic('$_api/room/profile?room_id=$_offline', Fixture.load('showroom', 'S03-profile-live').body)],
      );
      final other = _setup(
        ['S03-profile-offline'],
        extra: [
          _synthetic('$_api/live/live_info?room_id=$_offline', Fixture.load('showroom', 'S04-live-info-live').body),
        ],
      );
      await expectLater(other.site.getRoomDetail(roomId: _offline), throwsA(isA<ApiChanged>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: _offline), throwsA(isA<ApiChanged>()));
    });

    test('a refreshed room merges into a stored follow without changing its identity', () async {
      final setup = _setup(_liveSamples);
      final stored = LiveRoom.fromJson(const {
        'roomId': _live,
        'platform': 'showroom',
        'title': 'old',
        'liveStatus': 1,
        'httpHeaders': _mediaHeaders,
      });
      final fresh = await setup.site.getRoomDetailForRefresh(roomId: stored.roomId);
      final merged = stored.mergeFrom(fresh);
      expect(merged.identityKey, stored.identityKey);
      expect((merged.isLiveNow, merged.title), (true, fresh.title));
      expect((merged.startedAt, merged.restriction), (fresh.startedAt, LiveRestriction.none));
      // The same room after it went offline (S04-live-info-offline's answer).
      final offline = await _setup(
        ['S03-profile-live'],
        extra: [
          _synthetic('$_api/live/live_info?room_id=$_live', {
            ...jsonDecode(Fixture.load('showroom', 'S04-live-info-offline').body) as Map<String, dynamic>,
            'room_id': 577362,
          }),
        ],
      ).site.getRoomDetailForRefresh(roomId: _live);
      expect((offline.watching, offline.totalViewers), ('', ''), reason: '19-4');
      final ended = merged.mergeFrom(offline);
      expect(ended.effectiveLiveStatus, LiveStatus.offline);
      expect((ended.startedAt, ended.restriction), (null, null), reason: 'M2.1: the broadcast ended');
      expect(ended.totalViewers, '3941', reason: 'mergeFrom keeps a stored audience: M13 hides it offline (19-4)');
    });
  });

  group('streams', () {
    test('qualities from the rows room entry kept: no request; the lines match 3.x', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final before = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: room);
      // 19-2: 原画 first (the default), 自动 last; 3.x: 自动, 原画, 中画质, 低画质.
      expect(qualities.map((quality) => quality.quality), ['原画', '中画质', '低画质', '自动']);
      expect(qualities.map((quality) => quality.id), ['hls:2:1000', 'hls:6:200', 'hls:4:100', 'hls_all:100:0']);
      final urls = (_legacy('S03-profile-live')[_live] as Map<String, dynamic>)['getPlayUrls'] as Map<String, dynamic>;
      for (final quality in qualities) {
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.urls, _result(urls['${quality.id}']));
        expect(resolution.lines.single.headers, _mediaHeaders);
        expect(resolution.lines.single.format, StreamFormat.hls);
        expect(resolution.appliedQualityData, quality.id);
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), _result(urls['${quality.id}']));
      }
      expect(setup.http.requests, hasLength(before), reason: '3.x used the qualities of room entry too');
    });

    test('a room without rows (a card, a refreshed room) asks streaming_url; 3.x could not play it', () async {
      final setup = _setup(['S01-onlives', ..._liveSamples]);
      final card = (await setup.site.getRecommendRooms()).first;
      expect(card.roomId, _live);
      final qualities = await setup.site.getPlayQualities(detail: card);
      expect(qualities, hasLength(4));
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final lines = await setup.site.resolvePlayUrls(detail: refreshed, quality: qualities.first);
      expect(lines.urls.single, endsWith('_main_ss.m3u8'));
      expect(setup.http.requests.map((request) => request.url.path), [
        '/api/live/onlives',
        '/api/live/streaming_url',
        '/api/room/profile',
        '/api/live/live_info',
        '/api/live/streaming_url',
      ]);
      final foreign = card.copyWith(
        data: const ShowroomRoomData(roomId: '1', streams: []),
      );
      expect(
        await setup.site.getPlayQualities(detail: foreign),
        hasLength(4),
        reason: "another room's data is not used",
      );
    });

    test('a quality the room does not offer, and a room of another platform, are refused', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      const gone = LivePlayQuality(quality: '原画', id: 'hls:9:1000');
      await expectLater(setup.site.resolvePlayUrls(detail: room, quality: gone), throwsA(isA<StreamUnavailable>()));
      final other = LiveRoom(roomId: _live, platform: 'bilibili', liveStatus: LiveStatus.live);
      await expectLater(setup.site.getPlayQualities(detail: other), throwsArgumentError);
      await expectLater(setup.site.resolvePlayUrlsForRecovery(detail: other, quality: gone), throwsArgumentError);
    });

    test('recovery asks streaming_url alone (3.x read the whole room: three requests) and keeps the quality', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final auto = (await setup.site.getPlayQualities(detail: room)).last;
      expect(auto.id, 'hls_all:100:0');
      final before = setup.http.requests.length;
      final recovered = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: auto);
      final legacy =
          _result(
                (_legacy('S03-profile-live')[_live]
                    as Map<String, dynamic>)['resolvePlayUrlsForRecoveryRaw(hls_all:100:0)'],
              )!
              as Map<String, dynamic>;
      expect(recovered.urls, legacy['urls']);
      expect(recovered.appliedQualityData, legacy['appliedQualityData']);
      expect(_sent(setup.http.requests.skip(before)), ['$_api/live/streaming_url?room_id=$_live&abr_available=1']);
      const gone = LivePlayQuality(quality: '原画', id: 'hls:9:1000');
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(detail: room, quality: gone),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('recovery of a room that went offline is StreamUnavailable (3.x: mediaUnavailable)', () async {
      final setup = _setup(_offlineSamples);
      final card = LiveRoom(roomId: _offline, platform: 'showroom', liveStatus: LiveStatus.live);
      const quality = LivePlayQuality(quality: '原画', id: 'hls:2:1000');
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(detail: card, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests.single.url.path, '/api/live/streaming_url');
      final legacy = _legacy('S03-profile-offline')[_offline] as Map<String, dynamic>;
      expect(
        (_result(legacy['resolvePlayUrlsForRecoveryRaw(hls:2:1000)'])! as Map)['message'],
        'Showroom mediaUnavailable',
      );
    });
  });

  group('links', () {
    test('room keys and ids without a request (3.x); site pages are not rooms', () async {
      final http = ReplayHttp(const []);
      final site = ShowroomSite(http);
      final parser = LinkParser(SiteRegistry({'showroom': () => site}), http);
      expect(
        await parser.parse('来看 https://www.showroom-live.com/r/$_key?t=1790532886。'),
        const RoomLink('showroom', _key),
      );
      expect(
        await parser.parse('https://www.showroom-live.com/48_Seina_Fukuoka'),
        const RoomLink('showroom', '48_Seina_Fukuoka'),
      );
      expect(
        await parser.parse('https://www.showroom-live.com/room/profile?room_id=$_offline'),
        const RoomLink('showroom', _offline),
      );
      for (final url in [
        'https://www.showroom-live.com/onlive',
        'https://www.showroom-live.com/event/x',
        'https://www.showroom-live.com/r/a/b',
        'https://evilshowroom-live.com/r/abc',
        'https://www.showroom-live.com/room/profile?room_id=0061576',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
        expect(site.needsResolving(url), isFalse, reason: url);
        expect(parser.containsSupportedLink(url), isFalse, reason: url);
      }
      expect(parser.containsSupportedLink('https://www.showroom-live.com/r/$_key'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('an all-digit key is looked up with room/status; 3.x read it as a room id and opened nothing', () async {
      // Room 386593's key is 7779344804 (sample S01); 3.x asked room/profile
      // for room 7779344804.
      final http = ReplayHttp([
        _synthetic('$_api/room/status?room_url_key=7779344804', {'room_id': 386593, 'room_url_key': '7779344804'}),
        _missing('$_api/room/status?room_url_key=1234567'),
      ]);
      final site = ShowroomSite(http);
      final parser = LinkParser(SiteRegistry({'showroom': () => site}), http);
      const url = 'https://www.showroom-live.com/r/7779344804';
      expect(site.roomIdFromUrl(url), isNull);
      expect(site.needsResolving(url), isTrue);
      expect(parser.containsSupportedLink(url), isTrue);
      expect(await parser.parse('看 $url 吧'), const RoomLink('showroom', '386593'));
      expect(http.requests.single.headers['referer'], 'https://www.showroom-live.com/');
      expect(await parser.parse('https://www.showroom-live.com/1234567'), isNull, reason: 'an unknown key');
      final legacy = _legacy('S02-status-key')['ShowroomLink.parse'] as Map<String, dynamic>;
      expect(legacy['http://www.showroom-live.com/r/7779344804'], '7779344804');
    });
  });
}
