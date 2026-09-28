// KilakilaSite over the recorded KilaKila responses (ReplayHttp) and a few
// synthetic ones: the request headers and counts (compared with the requests
// 3.x sent, from expected.json), the catalog and timelines, keyword and exact
// search, room details for entry, refresh and recording, streams with their
// leases and recovery onto a new broadcast, cancellation, links through the
// link parser and the error mapping. The synthetic worlds port 3.x's
// kilakila_application_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/kilakila';
const _liveOwner = '3674092253247';
const _liveBroadcast = '2268450556051718173';
const _offlineOwner = '1775178981381';
const _first = '9007199254740993123';
const _second = '9007199254740993456';

/// Answers every request with [answer].
final class _Scripted implements LiveHttp {
  new(this.answer);

  final LiveResponse Function(LiveRequest request) answer;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return answer(request);
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

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('kilakila', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('kilakila', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

typedef _Setup = ({KilakilaSite site, ReplayHttp http});

_Setup _setup(List<String> samples) {
  final http = ReplayHttp.fixtures(_root, samples);
  return (site: KilakilaSite(http, now: () => DateTime.utc(2026, 9, 27, 17, 10)), http: http);
}

List<String> _urls(List<LiveRequest> requests) => [for (final request in requests) request.url.toString()];

List<String> _paths(List<LiveRequest> requests) => [for (final request in requests) request.url.path];

Map<String, dynamic> _legacy(String sample) => Fixture.load('kilakila', sample).legacy as Map<String, dynamic>;

/// The requests 3.x sent for [key] of [sample].
List<String> _legacyRequests(String sample, String key) =>
    ((_legacy(sample)[key] as Map<String, dynamic>)['requests'] as List).cast<String>();

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

// 3.x's application-test world: the anchor 100, whose current broadcast
// `getRoomInfo` answers for any broadcast id.

String _media(String room, [String extension = 'flv']) =>
    'https://pull.live.hongrenshuo.com.cn/hrs/$room.$extension?auth_key=1900000000-0-0-fixture';

Map<String, dynamic> _card([String room = _first]) => {
  'roomIdStr': room,
  'uid': '100',
  'title': 'Fixture live',
  'goldPrice': 0,
  'status': 4,
  'watchNumber': 1234,
};

String _profile(Object card) => jsonEncode({
  'code': 200,
  'data': {
    'userResp': {
      'nickname': 'Fixture',
      'introduction': 'hello',
      'statisticInfo': {'followerNumber': 12},
    },
    'liveCard': card,
  },
});

String _info(String room, {Map<String, dynamic> changes = const {}}) => jsonEncode({
  'h': {'code': 200, 'success': true},
  'b': {
    ..._card(room),
    'userInfo': {'id': '100', 'nickname': 'Fixture'},
    'flvPlayUrl': _media(room),
    'hlsPlayUrl': _media(room, 'm3u8'),
    ...changes,
  },
});

_Scripted _world({
  String Function()? current,
  Object Function()? card,
  Map<String, dynamic> changes = const {},
  String Function(String broadcastId)? info,
}) => _Scripted((request) {
  switch (request.url.path) {
    case '/Tg/personalH5':
      expect(request.url.queryParameters, {'uid': '100'});
      return _response(request, _profile(card?.call() ?? _card(current?.call() ?? _first)));
    case '/LiveRoom/getRoomInfo':
      final id = request.url.queryParameters['roomId']!;
      return _response(request, info?.call(id) ?? _info(id, changes: changes));
  }
  throw StateError('unexpected ${request.url}');
});

String _timeline(Uri url, List<Map<String, dynamic>> cards, {bool more = false}) => jsonEncode({
  'code': 200,
  'data': {
    'body': {
      'h': {'code': 200, 'success': true},
      'b': {
        'pageNo': int.parse(url.queryParameters['pageNo']!),
        'pageSize': int.parse(url.queryParameters['pageSize']!),
        'isLastPage': !more,
        'data': [
          for (final card in cards)
            {
              'dataType': 8,
              'roomResq': card,
              'userResp': {'id': card['uid'], 'nickname': 'Fixture'},
            },
        ],
      },
    },
  },
});

List<Map<String, dynamic>> _vectors() =>
    (jsonDecode(File('$_root/S09-share-vectors/vectors.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

void main() {
  group('requests', () {
    test("3.x's headers on every request, redirects not followed", () async {
      final setup = _setup(['S01-timeline-hot-p1', 'S03-search', 'S04-owner-live', 'S05-room-live']);
      await setup.site.getDirectoryPage();
      await setup.site.searchRooms('小', pageSize: 20);
      await setup.site.getRoomDetail(roomId: _liveOwner);
      expect(setup.http.requests, hasLength(4));
      for (final request in setup.http.requests) {
        expect(request.headers, {'referer': 'https://live.kilakila.cn/', 'user-agent': 'Mozilla/5.0'});
        expect(request.followRedirects, isFalse);
        expect(request.site, 'kilakila');
      }
      expect((setup.site.id, setup.site.name), ('kilakila', '克拉克拉'));
      expect(setup.site.directoryNoticeKey, 'kilakila_directory_scope');
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no KilaKila danmaku');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled', () async {
      await expectLater(
        KilakilaSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: '100'),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(KilakilaSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: '100'), _cancelled);
      final unavailable = _Scripted((request) => _response(request, '', status: 503));
      await expectLater(KilakilaSite(unavailable).getDirectoryPage(), throwsA(isA<NetworkFailure>()));
      final denied = _Scripted((request) => _response(request, '', status: 403));
      await expectLater(KilakilaSite(denied).getRoomDetailForRefresh(roomId: '100'), throwsA(isA<RiskControl>()));
      final redirected = _Scripted((request) => _response(request, '', status: 302));
      await expectLater(KilakilaSite(redirected).getRoomDetail(roomId: '100'), throwsA(isA<NetworkFailure>()));
    });

    test('the cancellation goes with the request, and wins before and after the answer (3.x)', () async {
      final token = CancelToken();
      final setup = _setup(['S01-timeline-hot-p1']);
      await setup.site.getDirectoryPage(cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      await expectLater(setup.site.getDirectoryPage(cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, hasLength(1), reason: 'nothing sent once cancelled');
      final afterAnswer = CancelToken();
      final late = _Scripted((request) {
        afterAnswer.cancel();
        return _response(request, _profile(_card()));
      });
      await expectLater(KilakilaSite(late).searchRoomsWithCancellation('100', cancel: afterAnswer), _cancelled);
      final afterFailure = CancelToken();
      final broken = _Scripted((request) {
        afterFailure.cancel();
        throw const TransportFailure('kilakila', TransportReason.connect);
      });
      await expectLater(KilakilaSite(broken).searchRoomsCancellable('音乐', cancel: afterFailure), _cancelled);
    });
  });

  group('catalog and directory', () {
    test('the two timelines, without a request; page 2 is empty (3.x)', () async {
      final setup = _setup([]);
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.single.children.map((area) => (area.areaId, area.areaName)), [('0', '热门直播'), ('107', '萌星推荐')]);
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test("native pages of ten, ending at isLastPage; 3.x's requests", () async {
      final setup = _setup([
        'S01-timeline-hot-p1',
        'S01-timeline-hot-p2',
        'S01-timeline-hot-last',
        'S01-timeline-new-p1',
      ]);
      final areas = (await setup.site.getCategories(1, 30)).single.children;
      final first = await setup.site.getDirectoryPage();
      final hot = await setup.site.getDirectoryPage(category: areas.first);
      final second = await setup.site.getDirectoryPage(page: 2);
      final last = await setup.site.getDirectoryPage(page: 55);
      final stars = await setup.site.getDirectoryPage(category: LiveArea.fromJson(areas.last.toJson()));
      expect((first.rooms.length, first.hasMore), (10, true));
      expect(hot.rooms, first.rooms);
      expect((second.page, second.hasMore), (2, true));
      expect((last.page, last.hasMore), (55, false));
      expect((stars.rooms.length, stars.hasMore), (10, true));
      expect(_urls(setup.http.requests), [
        ..._legacyRequests('S01-timeline-hot-p1', 'getDirectoryPage(null)'),
        ..._legacyRequests('S01-timeline-hot-p1', 'getDirectoryPage'),
        ..._legacyRequests('S01-timeline-hot-p2', 'getDirectoryPage'),
        ..._legacyRequests('S01-timeline-hot-last', 'getDirectoryPage'),
        ..._legacyRequests('S01-timeline-new-p1', 'getDirectoryPage'),
      ]);
      expect(await setup.site.getRecommendRooms(pageSize: 10), first.rooms);
      expect(await setup.site.getCategoryRooms(areas.last, pageSize: 10), stars.rooms);
    });

    test('recommendations and areas send their page size; the rooms are anchors, each once (3.x)', () async {
      final http = _Scripted(
        (request) =>
            _response(request, _timeline(request.url, [_card(), _card(_second), _card('200')..['uid'] = '101'])),
      );
      final site = KilakilaSite(http);
      final rooms = await site.getCategoryRooms(
        const LiveArea(platform: 'kilakila', areaType: 'timeline', areaId: '107'),
        page: 2,
        pageSize: 7,
      );
      expect(rooms.map((room) => room.roomId), ['100', '101']);
      expect(http.requests.single.url.queryParameters, {
        'tag': '0',
        'type': '107',
        'genderType': '0',
        'pageNo': '2',
        'pageSize': '7',
      });
      await site.getRecommendRooms();
      expect(http.requests.last.url.queryParameters['pageSize'], '30');
      expect(http.requests.last.url.queryParameters['type'], '0');
    });

    test('bad pages, page sizes and areas are caller errors, without a request (3.x)', () async {
      final setup = _setup([]);
      for (final page in [0, 100001]) {
        await expectLater(setup.site.getDirectoryPage(page: page), throwsArgumentError, reason: '$page');
      }
      for (final size in [0, 101]) {
        await expectLater(setup.site.getRecommendRooms(pageSize: size), throwsArgumentError, reason: '$size');
      }
      for (final area in [
        const LiveArea(platform: 'other', areaType: 'timeline', areaId: '0'),
        const LiveArea(platform: 'kilakila', areaId: '0'),
        const LiveArea(platform: 'kilakila', areaType: 'timeline', areaId: '99'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
      }
      expect(setup.http.requests, isEmpty);
    });
  });

  group('search', () {
    test('keywords: one request a page, no lookup per anchor; the state stays unknown (3.x)', () async {
      final setup = _setup(['S03-search', 'S03-search-p2', 'S03-search-empty']);
      final first = await setup.site.searchRooms('小', pageSize: 20);
      final second = await setup.site.searchRooms(' 小 ', page: 2, pageSize: 20);
      final none = await setup.site.searchRooms('zxqvnoresultfixture', pageSize: 20);
      expect((first.length, second.length, none.length), (10, 10, 0));
      expect(first.every((room) => room.isLiveStatusPending && room.data == null), isTrue);
      expect(_urls(setup.http.requests), [
        ..._legacyRequests('S03-search', 'searchRooms'),
        ..._legacyRequests('S03-search-p2', 'searchRooms'),
        ..._legacyRequests('S03-search-empty', 'searchRooms'),
      ]);
      expect(Uri.decodeFull(setup.http.requests.first.url.path), '/aboutus/serach/kw/小');
      expect(setup.site.supportsSearchPaginationFor('小'), isTrue);
    });

    test('a uid or anchor link: one profile request, on page 1 only (3.x)', () async {
      final setup = _setup(['S04-owner-live', 'S04-owner-offline', 'S04-owner-notfound']);
      final live = (await setup.site.searchRooms(_liveOwner)).single;
      expect((live.roomId, live.isLiveNow, live.data), (_liveOwner, true, null));
      final linked = await setup.site.searchRooms(KilakilaApi.ownerUrl(_liveOwner));
      expect(linked.single.roomId, _liveOwner);
      final zhubo = await setup.site.searchRooms('https://live.kilakila.cn/zhubo/$_offlineOwner');
      expect(zhubo.single.title, zhubo.single.nick, reason: "an anchor without a broadcast is 3.x's profile card");
      expect(zhubo.single.isLiveStatusPending, isTrue);
      expect(await setup.site.searchRooms('1'), isEmpty, reason: 'an unknown anchor is no result');
      expect(await setup.site.searchRooms(_liveOwner, page: 2), isEmpty);
      expect(_urls(setup.http.requests), [
        ..._legacyRequests('S04-owner-live', 'searchRooms(uid)'),
        ..._legacyRequests('S04-owner-live', 'searchRooms(ownerUrl)'),
        ..._legacyRequests('S04-owner-offline', 'searchRooms(uid)'),
        ..._legacyRequests('S04-owner-notfound', 'searchRooms(uid)'),
      ]);
      for (final input in [_liveOwner, KilakilaApi.ownerUrl(_liveOwner)]) {
        expect(setup.site.supportsSearchPaginationFor(input), isFalse, reason: input);
      }
    });

    test('broadcast links, other links, padded numbers and blanks find nothing without a request (3.x)', () async {
      final setup = _setup([]);
      for (final input in [
        '00100',
        'https://live.kilakila.cn/room/$_first',
        'https://evil.test/index/roomuser/uid/100',
        'https://evil.test/zhubo/123',
        '   ',
      ]) {
        expect(await setup.site.searchRooms(input), isEmpty, reason: input);
        expect(setup.site.supportsSearchPaginationFor(input), isFalse, reason: input);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('a keyword with a colon is a keyword (3.x took `Re:Zero` for a link and found nothing)', () async {
      final http = _Scripted(
        (request) => _response(
          request,
          '<div class="userList"><a href="/zhubo/100"><div class="anchor-name">Re:Zero</div></a></div>',
        ),
      );
      final site = KilakilaSite(http);
      expect((await site.searchRooms('Re:Zero')).single.roomId, '100');
      expect(http.requests.single.url.pathSegments, ['aboutus', 'serach', 'kw', 'Re:Zero']);
      expect(site.supportsSearchPaginationFor('Re:Zero'), isTrue);
    });

    test('keywords, pages and sizes the site does not take are refused without a request (3.x)', () async {
      final setup = _setup([]);
      await expectLater(setup.site.searchRooms('x' * 101), throwsArgumentError);
      await expectLater(setup.site.searchRooms('音乐', page: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('音乐', page: 10001), throwsArgumentError);
      await expectLater(setup.site.searchRooms('音乐', pageSize: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('音乐', pageSize: 101), throwsArgumentError);
      await expectLater(setup.site.searchRooms('', pageSize: 0), throwsArgumentError, reason: 'checked first');
      expect(setup.http.requests, isEmpty);
    });

    test('only an unknown anchor is an empty result; other failures are errors (3.x)', () async {
      final service = _Scripted((request) => _response(request, jsonEncode({'code': 1, 'data': null})));
      await expectLater(KilakilaSite(service).searchRooms('100'), throwsA(isA<ApiChanged>()));
      final malformed = _Scripted(
        (request) => _response(request, jsonEncode({'code': 200, 'data': <String, Object?>{}})),
      );
      await expectLater(KilakilaSite(malformed).searchRooms('100'), throwsA(isA<ApiChanged>()));
      final token = CancelToken();
      final keyword = _Scripted((request) => _response(request, '<div class="userList"></div>'));
      await KilakilaSite(keyword).searchRoomsCancellable('音乐', pageSize: 20, cancel: token);
      expect(identical(keyword.requests.single.cancel, token), isTrue);
      expect(keyword.requests.single.url.queryParameters, isEmpty, reason: 'the page size is not sent');
    });
  });

  group('rooms', () {
    test("refresh: the profile only; entry and recording: profile and getRoomInfo (3.x's requests)", () async {
      final setup = _setup(['S04-owner-live', 'S05-room-live']);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: ' $_liveOwner ');
      expect(_urls(setup.http.requests), _legacyRequests('S04-owner-live', 'getRoomDetailForRefresh'));
      expect((refreshed.roomId, refreshed.isLiveNow, refreshed.data), (_liveOwner, true, null));
      setup.http.requests.clear();
      final entered = await setup.site.getRoomDetail(roomId: _liveOwner);
      expect(_urls(setup.http.requests), _legacyRequests('S04-owner-live', 'getRoomDetail'));
      expect(entered.roomId, _liveOwner);
      expect((entered.data! as KilakilaRoomData).broadcast!.broadcastId, _liveBroadcast);
      expect(entered.danmakuData.toString(), 'KilakilaDanmakuArgs($_liveBroadcast)');
      setup.http.requests.clear();
      final recorded = await setup.site.getRoomDetailForRecording(roomId: _liveOwner);
      expect(_urls(setup.http.requests), _legacyRequests('S04-owner-live', 'getRoomDetailForRecording'));
      expect(recorded.data, isA<KilakilaRoomData>());
      expect(recorded.danmakuData, isNull, reason: 'recording needs no danmaku');
      setup.http.requests.clear();
      expect(await setup.site.getLiveStatus(roomId: _liveOwner), isTrue);
      expect(_urls(setup.http.requests), _legacyRequests('S04-owner-live', 'getLiveStatus'));
    });

    test('an anchor without a broadcast: one request, unknown state, no stream (3.x)', () async {
      final setup = _setup(['S04-owner-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offlineOwner);
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect(await setup.site.getLiveStatus(roomId: _offlineOwner), isFalse);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(_urls(setup.http.requests), [
        ..._legacyRequests('S04-owner-offline', 'getRoomDetail'),
        ..._legacyRequests('S04-owner-offline', 'getLiveStatus'),
      ]);
    });

    test('an unknown anchor is NotFound; an id that is no uid asks nothing', () async {
      final setup = _setup(['S04-owner-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: '1'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: '1'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: '1'), throwsA(isA<NotFound>()));
      for (final id in ['0123', 'abc', '', '../100', _first.padLeft(33, '1')]) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(3));
    });

    test('a follow is the anchor across broadcasts; nothing short-lived is stored (REG-KILAKILA-001)', () async {
      var current = _first;
      final site = KilakilaSite(_world(current: () => current));
      final entered = await site.getRoomDetail(roomId: '100');
      final saved = entered.toJson();
      expect(jsonEncode(saved), allOf(isNot(contains(_first)), isNot(contains('auth_key'))));
      final stored = LiveRoom.fromJson({...saved, 'area': 'kept'});
      current = _second;
      final refreshed = await site.getRoomDetailForRefresh(roomId: stored.roomId);
      expect(refreshed.hasSameIdentity(stored), isTrue);
      final merged = stored.mergeFrom(refreshed);
      expect((merged.roomId, merged.area, merged.isLiveNow), ('100', 'kept', true));
      expect((merged.introduction, merged.followers), ('hello', '12'));
      final again = await site.getRoomDetail(roomId: '100');
      expect((again.data! as KilakilaRoomData).broadcast!.broadcastId, _second);
    });

    test('an unknown advertised status stays unknown on refresh (3.x)', () async {
      final site = KilakilaSite(_world(card: () => {..._card(), 'status': 77}));
      expect((await site.getRoomDetailForRefresh(roomId: '100')).effectiveLiveStatus, LiveStatus.unknown);
    });

    test('a broadcast that ended between the two requests cannot be played (3.x failed here too)', () async {
      for (final code in [5201, 5966]) {
        final site = KilakilaSite(
          _world(
            info: (_) => jsonEncode({
              'h': {'code': code, 'success': false},
            }),
          ),
        );
        await expectLater(site.getRoomDetail(roomId: '100'), throwsA(isA<StreamUnavailable>()), reason: '$code');
      }
      final foreign = KilakilaSite(_world(changes: {'uid': '101'}));
      await expectLater(foreign.getRoomDetail(roomId: '100'), throwsA(isA<ApiChanged>()));
      await expectLater(foreign.getRoomDetailForRecording(roomId: '100'), throwsA(isA<ApiChanged>()));
      final replaced = KilakilaSite(_world(info: (_) => _info(_second)));
      await expectLater(replaced.getRoomDetail(roomId: '100'), throwsA(isA<ApiChanged>()));
    });

    test('paid, not live or URL-less broadcasts open; their stream says why (3.x failed at entry)', () async {
      for (final (changes, matcher) in [
        (<String, dynamic>{'goldPrice': 1}, isA<NeedsLogin>()),
        (<String, dynamic>{'status': 77}, isA<StreamUnavailable>()),
        (<String, dynamic>{'flvPlayUrl': '', 'hlsPlayUrl': ''}, isA<StreamUnavailable>()),
      ]) {
        final http = _world(changes: changes);
        final site = KilakilaSite(http);
        for (final entered in [
          await site.getRoomDetail(roomId: '100'),
          await site.getRoomDetailForRecording(roomId: '100'),
        ]) {
          await expectLater(site.getPlayQualities(detail: entered), throwsA(matcher), reason: '$changes');
        }
        expect(http.requests, hasLength(4), reason: 'the stream needs no further request');
      }
    });
  });

  group('streams', () {
    test('qualities and lines from room entry: no request, headers and lease on the line', () async {
      final setup = _setup(['S04-owner-live', 'S05-room-live']);
      final room = await setup.site.getRoomDetail(roomId: _liveOwner);
      final qualities = await setup.site.getPlayQualities(detail: room);
      final legacy = _legacy('S04-owner-live')['getPlayQualites'] as List;
      expect(qualities.map((quality) => quality.id), [for (final quality in legacy) (quality as Map)['id']]);
      for (final (index, quality) in qualities.indexed) {
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.urls, (legacy[index] as Map)['getPlayUrls']);
        final line = resolution.lines.single;
        expect(line.headers, KilakilaApi.headers);
        expect(line.lease!.expiresAt, DateTime.fromMillisecondsSinceEpoch(1793120972 * 1000, isUtc: true));
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), resolution.urls);
      }
      expect(setup.http.requests, hasLength(2));
    });

    test('a list card is entered first; a room called offline asks nothing', () async {
      final setup = _setup(['S01-timeline-hot-p1', 'S04-owner-live', 'S05-room-live']);
      final card = (await setup.site.getDirectoryPage()).rooms.firstWhere((room) => room.roomId == _liveOwner);
      expect(await setup.site.getPlayQualities(detail: card), hasLength(2));
      expect(_paths(setup.http.requests), ['/pcLive/timeline', '/Tg/personalH5', '/LiveRoom/getRoomInfo']);
      final offline = LiveRoom(roomId: _liveOwner, platform: 'kilakila', liveStatus: LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(3));
    });

    test('recovery follows the anchor to a new broadcast with the same quality ids (3.x)', () async {
      var current = _first;
      final http = _world(current: () => current);
      final site = KilakilaSite(http);
      final room = await site.getRoomDetail(roomId: '100');
      final quality = (await site.getPlayQualities(detail: room)).first;
      expect(quality.selectionId, 'flv');
      expect(await site.getPlayUrls(detail: room, quality: quality), [_media(_first)]);
      current = _second;
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(recovered.urls, [_media(_second)]);
      expect(recovered.appliedQualityData, 'flv');
      expect(recovered.lines.single.lease!.cutsConnection, isFalse);
      expect(http.requests, hasLength(4));
    });

    test('recovery never reuses the old signed URLs (3.x)', () async {
      var current = _first;
      final site = KilakilaSite(_world(current: () => current, changes: {'hlsPlayUrl': ''}));
      final room = await site.getRoomDetail(roomId: '100');
      current = _second;
      await expectLater(
        site.resolvePlayUrlsForRecovery(
          detail: room,
          quality: LivePlayQuality(quality: 'HLS', id: 'hls', data: [_media(_first, 'm3u8')]),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      final ended = KilakilaSite(_world(card: () => {'roomSourceType': 0, 'recommendSource': 0}));
      await expectLater(
        ended.resolvePlayUrlsForRecovery(
          detail: room,
          quality: const LivePlayQuality(quality: 'FLV', id: 'flv'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    test('anchor links are rooms without a request; broadcast links need one (3.x)', () {
      final site = KilakilaSite(ReplayHttp(const []));
      final owner = _vectors().firstWhere((vector) => vector['name'] == 'new-owner');
      for (final (url, uid) in [
        ('https://live.hongrenshuo.com.cn/index/roomuser/uid/100', '100'),
        ('https://live.kilakila.cn/zhubo/100', '100'),
        (owner['url'] as String, owner['id']),
      ]) {
        expect(site.roomIdFromUrl(url), uid, reason: url);
        expect(site.needsResolving(url), isFalse, reason: url);
      }
      final location =
          ((Fixture.load('kilakila', 'S06-room-redirect').meta['response'] as Map)['headers'] as Map)['location']
              as String;
      for (final url in [
        'https://live.kilakila.cn/room/$_first',
        'https://www.hongdoufm.com/PcLive/index/detail?id=$_first',
        location,
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
        expect(site.needsResolving(url), isTrue, reason: url);
      }
      for (final url in ['https://live.kilakila.cn/%72oom/1', 'https://evil.test/zhubo/1', 'https://douyu.com/1']) {
        expect((site.roomIdFromUrl(url), site.needsResolving(url)), (null, false), reason: url);
      }
    });

    test('the share link of S06: one getRoomInfo finds the anchor (3.x also asked for the profile)', () async {
      final http = ReplayHttp.fixtures(_root, ['S05-room-live']);
      final parser = LinkParser(SiteRegistry({'kilakila': () => KilakilaSite(http)}), http);
      final redirect = Fixture.load('kilakila', 'S06-room-redirect');
      final location = ((redirect.meta['response'] as Map)['headers'] as Map)['location'] as String;
      final legacy = _legacy('S06-room-redirect')['shareImport(location)'] as Map<String, dynamic>;
      expect(legacy['value'], [_liveOwner, 'kilakila']);
      expect(await parser.parse('快来听 $location 呀'), const RoomLink('kilakila', _liveOwner));
      expect(_urls(http.requests), [(legacy['requests'] as List).first]);
      expect(http.requests.single.headers, KilakilaApi.headers);
      expect(http.requests.single.followRedirects, isFalse);
      expect(await parser.parse(redirect.url.toString()), const RoomLink('kilakila', _liveOwner));
      expect(parser.containsSupportedLink('看 $location'), isTrue);
    });

    test('share vectors through the link parser: owners ask nothing, broadcasts their room (3.x)', () async {
      for (final vector in _vectors()) {
        final http = _world();
        final parser = LinkParser(SiteRegistry({'kilakila': () => KilakilaSite(http)}), http);
        final result = await parser.parse(vector['url'] as String);
        if (vector['valid'] != true) {
          expect(result, isNull, reason: vector['name'] as String);
          expect(http.requests, isEmpty);
        } else if (vector['kind'] == 'owner') {
          expect(result, RoomLink('kilakila', vector['id'] as String));
          expect(http.requests, isEmpty);
        } else {
          expect(result, const RoomLink('kilakila', '100'), reason: vector['name'] as String);
          expect(http.requests.single.url.queryParameters, {'roomId': vector['id']});
        }
      }
    });

    test('a broadcast whose anchor cannot be found is no room (3.x reported a failure)', () async {
      final notFound = ReplayHttp.fixtures(_root, ['S05-room-notfound']);
      final parser = LinkParser(SiteRegistry({'kilakila': () => KilakilaSite(notFound)}), notFound);
      expect(await parser.parse('https://live.kilakila.cn/room/1'), isNull);
      expect(_legacy('S05-room-notfound')['shareImport'], {
        'value': {'throws': 'KilakilaException', 'message': 'Kilakila service'},
        'requests': ['https://live.kilakila.cn/LiveRoom/getRoomInfo?roomId=1'],
      });
      for (final (body, status) in [
        ('', 503),
        (
          jsonEncode({
            'h': {'code': 5966, 'success': false},
          }),
          200,
        ),
      ]) {
        final http = _Scripted((request) => _response(request, body, status: status));
        final parser = LinkParser(SiteRegistry({'kilakila': () => KilakilaSite(http)}), http);
        expect(await parser.parse('https://live.kilakila.cn/room/$_first'), isNull);
        expect(http.requests, hasLength(1));
      }
    });
  });
}
