// SteamBroadcastSite over the recorded Steam responses (ReplayHttp) and a few
// synthetic ones: the request headers, the directory pages and 3.x's slices,
// the search's lookups and filter, rooms at every depth with the remembered
// cards, the checked master and the streams, media problems that no longer
// fail the room, cancellation, the deadline, links and the error mapping.
// Requests are compared with the ones 3.x sent (expected.json records them
// with their headers).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/steambroadcast';

const _live = '76561199485215572';
const _offline = '76561197960287930';

const _directory = ['S01-directory-p1', 'S01-directory-p2'];
const _liveRoom = ['S05-watch-live', 'S05-mpd-live', 'S05-master-live'];
const _offlineRoom = ['S05-watch-offline', 'S04-mpd-offline'];

const LivePlayQuality _auto = SteamBroadcastApi.quality;

Map<String, dynamic> _legacy(String sample) => Fixture.load('steambroadcast', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

/// The requests of a traced legacy call: `[url, headers]` (names
/// lower-cased).
List<List<Object>> _legacyRequests(Object? traced) => [
  for (final request in ((traced! as Map<String, dynamic>)['requests'] as List).cast<Map<String, dynamic>>())
    [
      request['url'] as String,
      {
        for (final MapEntry(:key, :value) in (request['headers'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value as String,
      },
    ],
];

List<List<Object>> _sent(Iterable<LiveRequest> requests) => [
  for (final request in requests) ['${request.url}', request.headers],
];

typedef _Setup = ({SteamBroadcastSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: SteamBroadcastSite(http), http: http);
}

ReplaySample _answer(Uri url, String body, {int status = 200}) =>
    ReplaySample(method: 'GET', url: url, status: status, bytes: utf8.encode(body));

String _mpd(Map<String, Object?> changes) {
  final root = jsonDecode(Fixture.load('steambroadcast', 'S05-mpd-live').body) as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in changes.entries) {
    root[key] = value;
  }
  return jsonEncode(root);
}

/// The recorded live mpd answer with [changes], for [_live].
ReplaySample _mpdAnswer(Map<String, Object?> changes) => _answer(SteamBroadcastApi.mpdUrl(_live), _mpd(changes));

Uri get _masterUrl => Uri.parse(
  (jsonDecode(Fixture.load('steambroadcast', 'S05-mpd-live').body) as Map<String, dynamic>)['hls_url'] as String,
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
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('steambroadcast', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async =>
      throw TransportFailure('steambroadcast', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// Asserts [room] equals 3.x's [legacy] projection on every key 3.x wrote,
/// except [changed] and `data` (3.x's `SteamBroadcastRoom`).
void _expectParity(LiveRoom room, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.contains(key) || key == 'data') continue;
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], reason: '$reason[$index]');
  }
}

/// A watch page of [steamId] naming [name].
String _watchPage(String steamId, String name) => [
  '<html><head><meta property="og:title" content="Steam Community :: $name :: Broadcast"></head><body>',
  '<div id="application_config" data-broadcastsinfo="{&quot;steamid&quot;:&quot;$steamId&quot;}"></div>',
  '</body></html>',
].join();

void main() {
  group('requests', () {
    test("3.x's URLs and headers, no redirects, as steambroadcast", () async {
      final setup = _setup([..._directory, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      await setup.site.getRoomDetail(roomId: _live);
      final legacyDirectory = (_legacy('S01-directory-p1')['getDirectoryPage'] as Map)['recommend:1'];
      final legacyRoom = _legacy('S05-watch-live')['getRoomDetail'];
      expect(_sent(setup.http.requests), [..._legacyRequests(legacyDirectory), ..._legacyRequests(legacyRoom)]);
      expect(setup.http.requests, hasLength(4));
      for (final request in setup.http.requests) {
        expect(request.followRedirects, isFalse);
        expect(request.site, 'steambroadcast');
        expect(request.method, 'GET');
      }
      expect((setup.site.id, setup.site.name), ('steambroadcast', 'Steam Broadcasts'));
      expect(setup.site.directoryNoticeKey, 'steambroadcast_directory_scope');
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Steam chat');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        SteamBroadcastSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(SteamBroadcastSite(_Failing(TransportReason.cancelled)).getRecommendRooms(), _cancelled);
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (400, isA<ApiChanged>()),
        (502, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(
          SteamBroadcastSite(http).getRoomDetailForRefresh(roomId: _live),
          throwsA(matcher),
          reason: '$status',
        );
        expect(http.requests, hasLength(1), reason: 'the watch page failed first');
      }
    });

    test(
      "one 25 s deadline per call (3.x's _scope): the deadline is NetworkFailure, a caller's cancel is cancelled",
      () async {
        final pending = Completer<LiveResponse>();
        final http = _Scripted((request) => pending.future);
        final site = SteamBroadcastSite(http, deadline: const Duration(milliseconds: 50));
        await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()));
        expect(http.requests.single.cancel?.isCancelled, isTrue, reason: 'the request is cancelled too');
        expect(SteamBroadcastSite(http).deadline, const Duration(seconds: 25));
        final cancel = CancelToken();
        final search = SteamBroadcastSite(http).searchRoomsCancellable('pwm', cancel: cancel);
        cancel.cancel();
        await expectLater(search, _cancelled);
        await expectLater(
          SteamBroadcastSite(http).searchRoomsCancellable('pwm', cancel: CancelToken()..cancel()),
          _cancelled,
        );
      },
    );
  });

  group('catalog and directory', () {
    test('the one category without a request, on page 1 with a size of at least 1 (3.x)', () async {
      final setup = _setup(const []);
      final legacy = _legacy('S01-directory-p1');
      expect((await setup.site.getCategories(1, 30)).single.children.single, SteamBroadcastApi.area);
      expect(await setup.site.getCategories(2, 30), hasLength(_result(legacy['getCategores(page: 2)'])! as int));
      expect(await setup.site.getCategories(1, 0), hasLength(_result(legacy['getCategores(pageSize: 0)'])! as int));
      expect(setup.http.requests, isEmpty);
    });

    test('directory pages match 3.x, for the recommendations and the one area', () async {
      final legacy = _legacy('S01-directory-p1')['getDirectoryPage'] as Map<String, dynamic>;
      for (final (key, category) in [('recommend:1', null), ('trending:1', SteamBroadcastApi.area)]) {
        final setup = _setup(_directory);
        final page = await setup.site.getDirectoryPage(category: category, cancel: CancelToken());
        final expected = _result(legacy[key])! as Map<String, dynamic>;
        _expectRooms(page.rooms, expected['rooms'], reason: key);
        expect((page.page, page.hasMore), (expected['page'], expected['hasMore']));
        expect(_sent(setup.http.requests), _legacyRequests(legacy[key]));
      }
      final setup = _setup(_directory);
      final second = await setup.site.getDirectoryPage(page: 2);
      final expected = _result(_legacy('S01-directory-p2')['getDirectoryPage'])! as Map<String, dynamic>;
      _expectRooms(second.rooms, expected['rooms']);
      expect(second.hasMore, expected['hasMore']);
    });

    test('a page below 1 is empty and another area an error, without a request; past 10000 too', () async {
      final setup = _setup(_directory);
      final legacy = _legacy('S01-directory-p1')['getDirectoryPage'] as Map<String, dynamic>;
      final empty = await setup.site.getDirectoryPage(page: 0);
      expect(_result(legacy['recommend:0']), {'rooms': <Object?>[], 'page': 0, 'hasMore': false});
      expect(empty.rooms, isEmpty);
      expect((empty.page, empty.hasMore), (0, false));
      // 3.x: identity and schema failures before any request.
      expect(_result(legacy['otherArea:1']), containsPair('throws', 'SteamBroadcastException.identity'));
      await expectLater(
        setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'steambroadcast', areaType: 'community', areaId: 'other'),
        ),
        throwsArgumentError,
      );
      expect(_result(legacy['recommend:10001']), containsPair('throws', 'SteamBroadcastException.schema'));
      await expectLater(setup.site.getDirectoryPage(page: 10001), throwsA(isA<RangeError>()));
      await expectLater(setup.site.getRecommendRooms(page: 10001), throwsA(isA<RangeError>()));
      expect(setup.http.requests, isEmpty);
    });

    test("3.x's recommendation slices and the area's rooms, with 3.x's requests", () async {
      final legacy = _legacy('S01-directory-p1');
      final slices = legacy['getRecommendRooms'] as Map<String, dynamic>;
      for (final (page, size) in [(1, 30), (1, 10), (1, 3), (1, 0), (0, 30), (1, 100)]) {
        final setup = _setup(_directory);
        final traced = slices['page $page size $size'];
        _expectRooms(
          await setup.site.getRecommendRooms(page: page, pageSize: size),
          _result(traced),
          reason: '$page/$size',
        );
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: '$page/$size');
      }
      final area = legacy['getCategoryRooms'] as Map<String, dynamic>;
      final setup = _setup(_directory);
      _expectRooms(await setup.site.getCategoryRooms(SteamBroadcastApi.area), _result(area['trending page 1']));
      _expectRooms(
        await setup.site.getCategoryRooms(SteamBroadcastApi.area, pageSize: 3),
        _result(area['trending page 1 size 3']),
      );
      await expectLater(
        setup.site.getCategoryRooms(const LiveArea(platform: 'bilibili', areaType: 'community', areaId: 'trending')),
        throwsArgumentError,
      );
      expect(setup.http.requests, hasLength(2));
      _expectRooms(
        await setup.site.getRecommendRooms(page: 2),
        _result(_legacy('S01-directory-p2')['getRecommendRooms']),
      );
    });
  });

  group('search', () {
    test("every keyword gives 3.x's rooms with 3.x's requests", () async {
      final legacy = _legacy('S01-directory-p1')['searchRooms'] as Map<String, dynamic>;
      for (final keyword in [
        'NTE',
        'neverness',
        'pwm game',
        'ARTDOCK',
        '7656119948521',
        'zzqxnomatch',
        _live,
        ' $_live ',
        'https://steamcommunity.com/broadcast/watch/$_live',
        'https://steamcommunity.com/broadcast/watch/$_live?l=english',
        _offline,
        'https://steamcommunity.com/profiles/$_live',
        '   ',
      ]) {
        final setup = _setup([..._directory, ..._liveRoom, ..._offlineRoom]);
        final traced = legacy['$keyword page 1'];
        _expectRooms(
          await setup.site.searchRoomsCancellable(keyword, cancel: CancelToken()),
          _result(traced),
          reason: keyword,
        );
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: keyword);
      }
    });

    test('bad sizes and pages give nothing without a request; an id on page 2 too; page 2 filters page 2', () async {
      final legacy = _legacy('S01-directory-p1')['searchRooms'] as Map<String, dynamic>;
      final setup = _setup([..._directory, ..._liveRoom]);
      for (final (keyword, page, size, key) in [
        ('pwm', 1, 101, 'pwm page 1 size 101'),
        ('pwm', 0, 30, 'pwm page 0'),
        ('NTE', 1, 0, 'NTE page 1 size 0'),
        (_live, 2, 30, '$_live page 2'),
      ]) {
        expect(_result(legacy[key]), isEmpty);
        expect(
          await setup.site.searchRooms(keyword, page: page, pageSize: size),
          isEmpty,
          reason: key,
        );
      }
      expect(setup.http.requests, isEmpty);
      final second = _legacy('S01-directory-p2')['searchRooms'] as Map<String, dynamic>;
      for (final keyword in ['a', 'zzqxnomatch']) {
        _expectRooms(
          await setup.site.searchRoomsCancellable(keyword, page: 2, cancel: CancelToken()),
          _result(second[keyword]),
          reason: keyword,
        );
      }
    });

    test('an account without a watch page is no result; other failures are thrown', () async {
      final missing = _setup(const [], extra: [_answer(SteamBroadcastApi.watchUrl(_live), '<html></html>')]);
      expect(await missing.site.searchRooms(_live), isEmpty);
      final gone = _setup(const [], extra: [_answer(SteamBroadcastApi.watchUrl(_live), '', status: 404)]);
      expect(await gone.site.searchRooms(_live), isEmpty);
      final refused = _setup(const [], extra: [_answer(SteamBroadcastApi.watchUrl(_live), '', status: 403)]);
      await expectLater(refused.site.searchRooms(_live), throwsA(isA<RiskControl>()));
    });
  });

  group('rooms', () {
    test("live: 3.x's room and requests at every depth; the danmaku arguments on entry only", () async {
      final legacy = _legacy('S05-watch-live');
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _setup(_liveRoom);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          _ => setup.site.getRoomDetailForRecording(roomId: _live),
        };
        _expectParity(room, _result(legacy[depth]), reason: depth);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: depth);
        final data = room.data! as SteamBroadcastRoomData;
        expect(data.state, SteamBroadcastState.live);
        final legacyData = (_result(legacy[depth])! as Map<String, dynamic>)['data'] as Map<String, dynamic>?;
        expect(data.master?.toString(), legacyData?['master'], reason: '$depth: only with the checked master (3.x)');
        expect(room.danmakuData, depth == 'getRoomDetail' ? isA<SteamBroadcastDanmakuArgs>() : isNull);
      }
      expect(_legacyRequests(legacy['getRoomDetail']), hasLength(3), reason: 'watch page, mpd, master (3.x)');
    });

    test("offline: 3.x's room and requests at every depth; no master is asked for", () async {
      final legacy = _legacy('S05-watch-offline');
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _setup(_offlineRoom);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _offline),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _offline),
          _ => setup.site.getRoomDetailForRecording(roomId: _offline),
        };
        _expectParity(room, _result(legacy[depth]), reason: depth);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: depth);
        expect(room.effectiveLiveStatus, LiveStatus.offline);
      }
    });

    test('a watch link is the same room; anything else is NotFound without a request', () async {
      final legacy = _legacy('S05-watch-live');
      final setup = _setup(_liveRoom);
      final room = await setup.site.getRoomDetail(roomId: 'https://steamcommunity.com/broadcast/watch/$_live');
      _expectParity(room, _result(legacy['getRoomDetail(watch link)']));
      expect(room.roomId, _live);
      setup.http.requests.clear();
      expect(_result(legacy['getRoomDetail(not an id)']), containsPair('throws', 'SteamBroadcastException.identity'));
      await expectLater(setup.site.getRoomDetail(roomId: '123'), throwsA(isA<NotFound>()));
      await expectLater(
        setup.site.getLiveStatus(roomId: 'https://steamcommunity.com/profiles/$_live'),
        throwsA(isA<NotFound>()),
      );
      expect(setup.http.requests, isEmpty);
    });

    test("the live status as 3.x's: two requests; restricted or unknown is an error, never offline", () async {
      final live = _setup(_liveRoom);
      expect(await live.site.getLiveStatus(roomId: _live), _result(_legacy('S05-watch-live')['getLiveStatus']));
      expect(live.http.requests, hasLength(2));
      final offline = _setup(_offlineRoom);
      expect(
        await offline.site.getLiveStatus(roomId: _offline),
        _result(_legacy('S05-watch-offline')['getLiveStatus']),
      );
      for (final success in ['user_restricted', 'waiting_for_start', 'something_new']) {
        final setup = _setup(
          _liveRoom,
          extra: [
            _mpdAnswer({'success': success}),
          ],
        );
        await expectLater(setup.site.getLiveStatus(roomId: _live), throwsA(isA<StreamUnavailable>()), reason: success);
        final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
        expect(room.effectiveLiveStatus, LiveStatus.unknown, reason: success);
        expect(
          room.notice,
          success == 'user_restricted' ? SteamBroadcastApi.restrictedNotice : SteamBroadcastApi.chatNotice,
        );
      }
    });

    test("rooms after the directory are filled from its cards, as 3.x's were", () async {
      final setup = _setup([..._directory, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      final detail = await setup.site.getRoomDetail(roomId: _live);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final traced = _legacy('S05-watch-live')['after the directory'];
      _expectRooms([detail, refreshed], _result(traced));
      expect(_sent(setup.http.requests), _legacyRequests(traced));
      expect(detail.title, 'NTE: Neverness to Everness');
      expect(detail.avatar, detail.cover, reason: 'what 3.x showed');
    });

    test('the site remembers the last 1000 broadcasters (3.x: every one)', () async {
      String id(int index) => '7656119${index.toString().padLeft(10, '0')}';
      final http = _Scripted((request) {
        final url = request.url;
        if (url.path == '/apps/allcontenthome') {
          final page = int.parse(url.queryParameters['p']!);
          String card(int index) => [
            '<div class="Broadcast_Card"><a href="https://steamcommunity.com/broadcast/watch/${id(index)}">',
            '<div class="apphub_CardContentType">Game $index: Broadcast</div></a></div>',
          ].join();
          final cards = [for (var index = (page - 1) * 10; index < page * 10; index++) card(index)];
          return _response(request, cards.join());
        }
        if (url.path.startsWith('/broadcast/watch/')) return _response(request, _watchPage(url.pathSegments.last, 'N'));
        return _response(request, '{"success":"unavailable"}');
      });
      final site = SteamBroadcastSite(http);
      for (var page = 1; page <= 101; page++) {
        await site.getRecommendRooms(page: page);
      }
      expect((await site.getRoomDetailForRefresh(roomId: id(10))).title, 'Game 10');
      expect((await site.getRoomDetailForRefresh(roomId: id(1009))).title, 'Game 1009');
      expect((await site.getRoomDetailForRefresh(roomId: id(9))).title, 'Steam Broadcast', reason: 'forgotten');
    });
  });

  group('streams', () {
    test("an entered live room: 3.x's quality and URL, now a line; recovery asks the room again", () async {
      final legacy = _legacy('S05-watch-live')['getRoomDetail → streams'] as Map<String, dynamic>;
      final setup = _setup(_liveRoom);
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      final expected = (_result(legacy['getPlayQualites'])! as List).single as Map<String, dynamic>;
      expect((qualities.single.quality, qualities.single.id), (expected['quality'], expected['id']));
      final resolution = await setup.site.resolvePlayUrlsRaw(detail: room, quality: _auto);
      final urls = _result(legacy['resolvePlayUrlsRaw'])! as Map<String, dynamic>;
      expect(resolution.urls, urls['urls']);
      expect(resolution.appliedQualityData, urls['appliedQualityData']);
      final line = resolution.lines.single;
      expect((line.format, line.codec, line.lineId), (StreamFormat.hls, 'avc', 'steamcontent'));
      expect(line.lease, isNull, reason: 'no expiry in the address; Steam needs no heartbeat');
      expect(line.headers, isEmpty, reason: "3.x's player and recorder sent no Steam headers");
      expect(await setup.site.getPlayUrls(detail: room, quality: _auto), _result(legacy['getPlayUrls']));
      expect(setup.http.requests, isEmpty, reason: 'no request (3.x)');
      final recovered = await setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _auto);
      expect(recovered.urls, (_result(legacy['resolvePlayUrlsForRecoveryRaw'])! as Map)['urls']);
      expect(_sent(setup.http.requests), _legacyRequests(legacy['resolvePlayUrlsForRecoveryRaw']));
      expect(setup.http.requests, hasLength(3), reason: 'a fresh room with its master (REG-LEASE-005)');
      expect(_result(legacy['otherQuality']), containsPair('throws', 'SteamBroadcastException.schema'));
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: 'x', id: 'source'),
        ),
        throwsArgumentError,
      );
    });

    test('rooms that cannot be played say why, without a request', () async {
      final setup = _setup([..._liveRoom, ..._offlineRoom, ..._directory]);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      final card = (await setup.site.getRecommendRooms()).first;
      setup.http.requests.clear();
      final refreshLegacy = _legacy('S05-watch-live')['getRoomDetailForRefresh → streams'] as Map<String, dynamic>;
      final offlineLegacy = _legacy('S05-watch-offline')['getRoomDetail → streams'] as Map<String, dynamic>;
      // 3.x: mediaUnavailable, and no qualities for an offline room.
      expect(
        _result(refreshLegacy['getPlayQualites']),
        containsPair('throws', 'SteamBroadcastException.mediaUnavailable'),
      );
      expect(_result(offlineLegacy['getPlayQualites']), isEmpty);
      expect(
        _result(offlineLegacy['resolvePlayUrlsRaw']),
        containsPair('throws', 'SteamBroadcastException.mediaUnavailable'),
      );
      for (final (name, room) in [('refreshed', refreshed), ('offline', offline), ('card', card)]) {
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()), reason: name);
        await expectLater(
          setup.site.resolvePlayUrlsRaw(detail: room, quality: _auto),
          throwsA(isA<StreamUnavailable>()),
          reason: name,
        );
        await expectLater(
          setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _auto),
          throwsA(isA<StreamUnavailable>()),
          reason: name,
        );
      }
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(roomId: _live, platform: 'bilibili'),
        ),
        throwsArgumentError,
      );
      expect(setup.http.requests, isEmpty);
    });

    test('a media problem no longer fails the room (3.x failed it, refresh included); the stream says why', () async {
      final china = _masterUrl.toString().replaceAll(_masterUrl.host, 'broadcast.st.dl.eccdnx.com');
      final otherHost = _setup(
        _liveRoom,
        extra: [
          _mpdAnswer({'hls_url': china}),
        ],
      );
      final refreshed = await otherHost.site.getRoomDetailForRefresh(roomId: _live);
      expect(refreshed.effectiveLiveStatus, LiveStatus.live);
      final entered = await otherHost.site.getRoomDetail(roomId: _live);
      expect(entered.effectiveLiveStatus, LiveStatus.live);
      expect(otherHost.http.requests, hasLength(4), reason: 'no master to ask for');
      await expectLater(otherHost.site.getPlayQualities(detail: entered), throwsA(isA<ApiChanged>()));

      final gone = _setup(_liveRoom, extra: [_answer(_masterUrl, '', status: 404)]);
      final room = await gone.site.getRoomDetailForRecording(roomId: _live);
      expect(room.effectiveLiveStatus, LiveStatus.live);
      await expectLater(gone.site.resolvePlayUrlsRaw(detail: room, quality: _auto), throwsA(isA<NotFound>()));

      final master = Fixture.load('steambroadcast', 'S05-master-live').body;
      final foreign = _setup(_liveRoom, extra: [_answer(_masterUrl, master.replaceAll(_live, _offline))]);
      final checked = await foreign.site.getRoomDetail(roomId: _live);
      expect(checked.isLiveNow, isTrue);
      await expectLater(foreign.site.getPlayQualities(detail: checked), throwsA(isA<ApiChanged>()));

      final failing = _Scripted((request) {
        if (request.url.host.endsWith('steamcontent.com')) {
          throw const TransportFailure('steambroadcast', TransportReason.connect, 'test');
        }
        return _response(
          request,
          request.url.path.startsWith('/broadcast/watch/')
              ? Fixture.load('steambroadcast', 'S05-watch-live').body
              : Fixture.load('steambroadcast', 'S05-mpd-live').body,
        );
      });
      final unreachable = await SteamBroadcastSite(failing).getRoomDetail(roomId: _live);
      expect(unreachable.isLiveNow, isTrue);
      await expectLater(
        SteamBroadcastSite(failing).getPlayQualities(detail: unreachable),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('recovery of a room that went offline says so', () async {
      final setup = _setup(_liveRoom);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final ended = _setup(
        _liveRoom,
        extra: [
          _mpdAnswer({'success': 'unavailable'}),
        ],
      );
      await expectLater(
        ended.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _auto),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(ended.http.requests, hasLength(2));
    });
  });

  group('links', () {
    test('watch links through the parser, without a request; profile and other pages are not rooms', () async {
      final http = ReplayHttp(const []);
      final registry = SiteRegistry({'steambroadcast': () => SteamBroadcastSite(http)});
      final parser = LinkParser(registry, http);
      expect(
        await parser.parse('Steam https://steamcommunity.com/broadcast/watch/76561198373527746?l=english'),
        const RoomLink('steambroadcast', '76561198373527746'),
      );
      expect(
        await parser.parse('看 https://steamcommunity.com/broadcast/watch/$_live。'),
        const RoomLink('steambroadcast', _live),
      );
      expect(await parser.parse('https://steamcommunity.com/app/730/broadcasts'), isNull);
      expect(await parser.parse('https://steamcommunity.com/profiles/$_live'), isNull);
      expect(await parser.parse('https://steam.tv/example'), isNull);
      expect(http.requests, isEmpty);
      final site = registry.of('steambroadcast') as SteamBroadcastSite;
      expect(site.needsResolving('https://steamcommunity.com/id/probrawlhallastream/'), isFalse);
      expect(
        parser.containsSupportedLink('Steam https://steamcommunity.com/broadcast/watch/76561198373527746'),
        isTrue,
      );
    });
  });
}
