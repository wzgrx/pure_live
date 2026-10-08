// SteamBroadcastSite over the recorded Steam responses (ReplayHttp) and a few
// synthetic ones: the request headers, the directory pages and 3.x's slices,
// the search's lookups and filter, rooms at every depth with the remembered
// cards, the detail answers of M4.U (the mini profile and getbroadcastinfo,
// 27-2, with their fallbacks), the checked master and its variants (27-7),
// the streams, media problems that no longer fail the room, cancellation,
// the deadline, links (27-4) and the error mapping. Requests are compared
// with the ones 3.x sent (expected.json records them with their headers)
// where they are still sent; intended differences name their item. No test
// compares a sample's time with the clock.
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
const _scs = '76561198843011284';

const _directory = ['S01-directory-p1', 'S01-directory-p2'];

/// The live broadcaster's detail answers: the mini profile and
/// getbroadcastinfo (recorded 2026-09-27), getbroadcastmpd and the master
/// (2026-09-28).
const _liveRoom = ['S03-profile', 'S05-mpd-live', 'S02-info-live', 'S05-master-live'];
const _offlineRoom = ['S08-profile-offline', 'S04-mpd-offline', 'S02-info-offline'];

/// One broadcaster's four answers recorded in the same minute
/// (2026-09-28T20:00Z), with a four-variant master.
const _scsRoom = ['S09-profile-live', 'S09-mpd-live', 'S09-info-live', 'S09-master-live'];

const LivePlayQuality _auto = SteamBroadcastApi.quality;

/// 3.x's notice ([SteamBroadcastApi.legacyChatNotice]), rewritten for viewers
/// ("说明文字"), without its chat sentence since the chat is shown (M5.23).
const _notice = {'notice'};

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

/// The request of [url] with the JSON headers of [steamId]'s room.
List<Object> _json(Uri url, String steamId) => ['$url', SteamBroadcastApi.roomHeaders(steamId, json: true)];

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

Uri get _scsMasterUrl => Uri.parse(
  (jsonDecode(Fixture.load('steambroadcast', 'S09-mpd-live').body) as Map<String, dynamic>)['hls_url'] as String,
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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], changed: changed, reason: '$reason[$index]');
  }
}

/// What a live room from the directory changed against 3.x: the avatar
/// (27-1).
const Set<String> _cardChanges = {'avatar', ..._notice};

/// What room entry changed against 3.x for the live S05 room: title, area
/// and cover from getbroadcastinfo (27-2), the profile's avatar (27-1), the
/// notice.
const Set<String> _enteredChanges = {'title', 'area', 'cover', 'avatar', ..._notice};

void main() {
  group('requests', () {
    test('changed: the directory as 3.x; a room asks its profile and getbroadcastinfo too (27-2)', () async {
      final setup = _setup([..._directory, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      await setup.site.getRoomDetail(roomId: _live);
      final legacyDirectory = (_legacy('S01-directory-p1')['getDirectoryPage'] as Map)['recommend:1'];
      final legacyRoom = _legacyRequests(_legacy('S05-watch-live')['getRoomDetail']);
      expect(_sent(setup.http.requests), [
        ..._legacyRequests(legacyDirectory),
        _json(SteamBroadcastApi.profileUrl(_live), _live),
        legacyRoom[1], // getbroadcastmpd, as 3.x
        _json(SteamBroadcastApi.infoUrl(_live), _live),
        legacyRoom[2], // the master, as 3.x
      ]);
      expect(legacyRoom.first.first, SteamBroadcastApi.link(_live), reason: "3.x's watch page is the fallback now");
      for (final request in setup.http.requests) {
        expect(request.followRedirects, isFalse);
        expect(request.site, 'steambroadcast');
        expect(request.method, 'GET');
      }
      expect((setup.site.id, setup.site.name), ('steambroadcast', 'Steam Broadcasts'));
      expect(setup.site.directoryNoticeKey, 'steambroadcast_directory_scope');
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: 'the chat is M5');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        SteamBroadcastSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(SteamBroadcastSite(_Failing(TransportReason.cancelled)).getRecommendRooms(), _cancelled);
      await expectLater(
        SteamBroadcastSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: _live),
        _cancelled,
        reason: 'a cancellation is not a failed profile to fall back from',
      );
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
        expect(http.requests.map((request) => request.url.path), [
          '/miniprofile/1524949844/json',
          '/broadcast/watch/$_live',
        ], reason: 'the profile failed, then its fallback, the watch page (27-2)');
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
        final lookup = CancelToken();
        final byId = SteamBroadcastSite(http).searchRoomsCancellable(_live, cancel: lookup);
        lookup.cancel();
        await expectLater(byId, _cancelled);
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

    test('changed: directory pages match 3.x, for the recommendations and the one area, but the avatar', () async {
      final legacy = _legacy('S01-directory-p1')['getDirectoryPage'] as Map<String, dynamic>;
      for (final (key, category) in [('recommend:1', null), ('trending:1', SteamBroadcastApi.area)]) {
        final setup = _setup(_directory);
        final page = await setup.site.getDirectoryPage(category: category, cancel: CancelToken());
        final expected = _result(legacy[key])! as Map<String, dynamic>;
        _expectRooms(page.rooms, expected['rooms'], changed: _cardChanges, reason: key);
        expect((page.page, page.hasMore), (expected['page'], expected['hasMore']));
        expect(_sent(setup.http.requests), _legacyRequests(legacy[key]));
        for (final room in page.rooms) {
          expect(room.avatar, isNot(room.cover), reason: "27-1: the broadcaster's avatar, not the cover");
        }
        expect(
          page.rooms.where((room) => room.avatar.endsWith('_full.jpg')),
          hasLength(8),
          reason: "2 of page 1's broadcasters show Steam's default avatar, which is none",
        );
      }
      final setup = _setup(_directory);
      final second = await setup.site.getDirectoryPage(page: 2);
      final expected = _result(_legacy('S01-directory-p2')['getDirectoryPage'])! as Map<String, dynamic>;
      _expectRooms(second.rooms, expected['rooms'], changed: _cardChanges);
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
          changed: _cardChanges,
          reason: '$page/$size',
        );
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: '$page/$size');
      }
      final area = legacy['getCategoryRooms'] as Map<String, dynamic>;
      final setup = _setup(_directory);
      _expectRooms(
        await setup.site.getCategoryRooms(SteamBroadcastApi.area),
        _result(area['trending page 1']),
        changed: _cardChanges,
      );
      _expectRooms(
        await setup.site.getCategoryRooms(SteamBroadcastApi.area, pageSize: 3),
        _result(area['trending page 1 size 3']),
        changed: _cardChanges,
      );
      await expectLater(
        setup.site.getCategoryRooms(const LiveArea(platform: 'bilibili', areaType: 'community', areaId: 'trending')),
        throwsArgumentError,
      );
      expect(setup.http.requests, hasLength(2));
      _expectRooms(
        await setup.site.getRecommendRooms(page: 2),
        _result(_legacy('S01-directory-p2')['getRecommendRooms']),
        changed: _cardChanges,
      );
    });
  });

  group('search', () {
    test("keywords filter the page as 3.x's did, with 3.x's requests", () async {
      final legacy = _legacy('S01-directory-p1')['searchRooms'] as Map<String, dynamic>;
      for (final keyword in ['NTE', 'neverness', 'pwm game', 'ARTDOCK', '7656119948521', 'zzqxnomatch', '   ']) {
        final setup = _setup(_directory);
        final traced = legacy['$keyword page 1'];
        _expectRooms(
          await setup.site.searchRoomsCancellable(keyword, cancel: CancelToken()),
          _result(traced),
          changed: _cardChanges,
          reason: keyword,
        );
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: keyword);
      }
    });

    test('changed: an id, watch or profile link (27-4) looks the account up with the refresh answers (27-2)', () async {
      final legacy = _legacy('S01-directory-p1')['searchRooms'] as Map<String, dynamic>;
      for (final (keyword, steamId) in [
        (_live, _live),
        (' $_live ', _live),
        ('https://steamcommunity.com/broadcast/watch/$_live', _live),
        ('https://steamcommunity.com/broadcast/watch/$_live?l=english', _live),
        ('https://steamcommunity.com/profiles/$_live', _live),
        (_offline, _offline),
      ]) {
        final setup = _setup([..._liveRoom, ..._offlineRoom]);
        final rooms = await setup.site.searchRoomsCancellable(keyword, cancel: CancelToken());
        final traced = legacy['$keyword page 1'];
        if (keyword.contains('/profiles/')) {
          // 27-4: 3.x filtered the directory page with the link and found
          // nothing.
          expect(_result(traced), isEmpty);
        } else {
          _expectRooms(
            rooms,
            _result(traced),
            // 3.x: the watch page and getbroadcastmpd's viewers; now the
            // refresh answers (27-2): getbroadcastinfo's viewers.
            changed: steamId == _live
                ? {..._enteredChanges, 'watching', 'onlineViewers'}
                : {'avatar', 'title', 'area', ..._notice},
            reason: keyword,
          );
          expect(_legacyRequests(traced), hasLength(2), reason: '3.x: the watch page and getbroadcastmpd');
        }
        expect(rooms.single.roomId, steamId, reason: keyword);
        expect(_sent(setup.http.requests), [
          _json(SteamBroadcastApi.profileUrl(steamId), steamId),
          _json(SteamBroadcastApi.infoUrl(steamId), steamId),
        ], reason: keyword);
        final room = rooms.single;
        if (steamId == _live) {
          expect(
            (room.title, room.nick, room.effectiveOnlineViewers),
            ('NTE: Neverness to Everness', 'PWM Game Manager', '6862'),
          );
          expect(room.effectiveLiveStatus, LiveStatus.live);
        } else {
          expect((room.nick, room.effectiveLiveStatus), ('Rabscuttle', LiveStatus.offline));
        }
      }
    });

    test('a custom address is resolved first (27-4, one request more); an unknown one is no result', () async {
      final setup = _setup([..._offlineRoom, 'S10-vanity', 'S10-vanity-missing']);
      final rooms = await setup.site.searchRooms('https://steamcommunity.com/id/gabelogannewell/');
      expect(rooms.single.roomId, _offline);
      expect(rooms.single.nick, 'Rabscuttle');
      expect(_sent(setup.http.requests), [
        ['https://steamcommunity.com/id/gabelogannewell/?xml=1', SteamBroadcastApi.xmlHeaders],
        _json(SteamBroadcastApi.profileUrl(_offline), _offline),
        _json(SteamBroadcastApi.infoUrl(_offline), _offline),
      ]);
      setup.http.requests.clear();
      expect(await setup.site.searchRooms('https://steamcommunity.com/id/zzqx-no-such-vanity-27'), isEmpty);
      expect(setup.http.requests, hasLength(1));
      setup.http.requests.clear();
      expect(await setup.site.searchRooms('https://steamcommunity.com/id/gabelogannewell', page: 2), isEmpty);
      expect(setup.http.requests, isEmpty);
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
          changed: _cardChanges,
          reason: keyword,
        );
      }
    });

    test('an account without a page is no result; other failures are thrown', () async {
      final profile = SteamBroadcastApi.profileUrl(_live);
      final missing = _setup(
        const [],
        extra: [_answer(profile, '', status: 404), _answer(SteamBroadcastApi.watchUrl(_live), '<html></html>')],
      );
      expect(await missing.site.searchRooms(_live), isEmpty, reason: 'no profile, a watch page without a config');
      final gone = _setup(
        const [],
        extra: [_answer(profile, '', status: 404), _answer(SteamBroadcastApi.watchUrl(_live), '', status: 404)],
      );
      expect(await gone.site.searchRooms(_live), isEmpty);
      final refused = _setup(
        const [],
        extra: [_answer(profile, '', status: 403), _answer(SteamBroadcastApi.watchUrl(_live), '', status: 403)],
      );
      await expectLater(refused.site.searchRooms(_live), throwsA(isA<RiskControl>()));
    });
  });

  group('rooms', () {
    test("changed: live at every depth: 3.x's room with the detail answers; entry asks one request more", () async {
      final legacy = _legacy('S05-watch-live');
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _setup(_liveRoom);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          _ => setup.site.getRoomDetailForRecording(roomId: _live),
        };
        final refresh = depth == 'getRoomDetailForRefresh';
        // A refresh reads getbroadcastinfo's viewers (cached a minute),
        // room entry getbroadcastmpd's (3.x's).
        _expectParity(
          room,
          _result(legacy[depth]),
          changed: {
            ..._enteredChanges,
            if (refresh) ...{'watching', 'onlineViewers'},
          },
          reason: depth,
        );
        final requests = _legacyRequests(legacy[depth]);
        expect(
          _sent(setup.http.requests),
          refresh
              ? [_json(SteamBroadcastApi.profileUrl(_live), _live), _json(SteamBroadcastApi.infoUrl(_live), _live)]
              : [
                  _json(SteamBroadcastApi.profileUrl(_live), _live),
                  requests[1],
                  _json(SteamBroadcastApi.infoUrl(_live), _live),
                  requests[2],
                ],
          reason: depth,
        );
        expect(requests, hasLength(refresh ? 2 : 3), reason: "3.x's count");
        expect((room.title, room.area), ('NTE: Neverness to Everness', 'NTE: Neverness to Everness'), reason: depth);
        expect(room.avatar, endsWith('_full.jpg'));
        expect(room.effectiveOnlineViewers, refresh ? '6862' : '7994');
        expect(room.restriction, refresh ? isNull : LiveRestriction.none, reason: depth);
        final data = room.data! as SteamBroadcastRoomData;
        expect(data.state, SteamBroadcastState.live);
        final legacyData = (_result(legacy[depth])! as Map<String, dynamic>)['data'] as Map<String, dynamic>?;
        expect(data.master?.toString(), legacyData?['master'], reason: '$depth: only with the checked master (3.x)');
        expect(
          room.danmakuData,
          refresh ? isNull : const SteamBroadcastDanmakuArgs(_live, broadcastId: '4005242549293303728'),
          reason: '27-6: the current broadcast, on entry and recording (E05.4, multi-view)',
        );
      }
    });

    test("changed: offline at every depth: 3.x's room with the profile's avatar (27-1), two requests", () async {
      final legacy = _legacy('S05-watch-offline');
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final setup = _setup(_offlineRoom);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _offline),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _offline),
          _ => setup.site.getRoomDetailForRecording(roomId: _offline),
        };
        // X-2: 3.x's placeholder title and area are left empty.
        _expectParity(room, _result(legacy[depth]), changed: {'avatar', 'title', 'area', ..._notice}, reason: depth);
        final refresh = depth == 'getRoomDetailForRefresh';
        final requests = _legacyRequests(legacy[depth]);
        expect(requests, hasLength(2));
        expect(_sent(setup.http.requests), [
          _json(SteamBroadcastApi.profileUrl(_offline), _offline),
          if (refresh) _json(SteamBroadcastApi.infoUrl(_offline), _offline) else requests[1],
        ], reason: depth);
        expect(room.effectiveLiveStatus, LiveStatus.offline);
        expect((room.nick, room.title, room.area), ('Rabscuttle', '', ''));
        expect(room.avatar, endsWith('c5d56249ee5d28a07db4ac9f7f60af961fab5426_full.jpg'));
        expect(room.restriction, isNull);
      }
    });

    test('S09: entry from its own answers, recorded in one minute; the four variants are its qualities', () async {
      final setup = _setup(_scsRoom);
      final room = await setup.site.getRoomDetail(roomId: _scs);
      expect(setup.http.requests.map((request) => request.url.host), [
        'steamcommunity.com',
        'steamcommunity.com',
        'steamcommunity.com',
        _scsMasterUrl.host,
      ]);
      expect((room.nick, room.title, room.effectiveOnlineViewers), ('SCS Software', 'Euro Truck Simulator 2', '2490'));
      expect(room.avatar, endsWith('ea764a9a9aa36897901e5a2cb1fe951fde29462e_full.jpg'));
      expect(room.cover, contains('/broadcast/$_scs/7677968762198629065/thumbnail/'));
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.quality), ['自适应 HLS', '1080p60', '720p', '480p', '360p']);
      expect(setup.http.requests, hasLength(4), reason: 'no request for the qualities');
    });

    test("27-2 fallbacks: a failed profile is the watch page's name; a failed info is 3.x's getbroadcastmpd", () async {
      final profile = _answer(SteamBroadcastApi.profileUrl(_live), '{"error":1}');
      final withoutProfile = _setup(['S05-watch-live', ..._liveRoom], extra: [profile]);
      final room = await withoutProfile.site.getRoomDetailForRefresh(roomId: _live);
      expect(room.nick, 'PWM Game Manager', reason: "the watch page's name");
      expect(room.avatar, '', reason: 'the watch page has none');
      expect(withoutProfile.http.requests.map((request) => request.url.path), [
        '/miniprofile/1524949844/json',
        '/broadcast/watch/$_live',
        '/broadcast/getbroadcastinfo/',
      ]);
      final info = _answer(SteamBroadcastApi.infoUrl(_live), '', status: 503);
      final withoutInfo = _setup(_liveRoom, extra: [info]);
      final refreshed = await withoutInfo.site.getRoomDetailForRefresh(roomId: _live);
      expect(refreshed.effectiveLiveStatus, LiveStatus.live);
      expect((refreshed.title, refreshed.area, refreshed.effectiveOnlineViewers), ('', '', '7994'));
      expect(refreshed.restriction, LiveRestriction.none, reason: "getbroadcastmpd's ready says");
      expect(withoutInfo.http.requests.map((request) => request.url.path), [
        '/miniprofile/1524949844/json',
        '/broadcast/getbroadcastinfo/',
        '/broadcast/getbroadcastmpd/',
      ]);
      withoutInfo.http.requests.clear();
      final entered = await withoutInfo.site.getRoomDetail(roomId: _live);
      expect(entered.isLiveNow, isTrue, reason: 'on entry a failed info is only missing fields');
      expect(entered.title, '');
      expect((entered.data! as SteamBroadcastRoomData).streamError, isNull);
      expect(withoutInfo.http.requests, hasLength(4));
    });

    test('a watch or profile link (27-4) is the same room; anything else is NotFound without a request', () async {
      final legacy = _legacy('S05-watch-live');
      final setup = _setup(_liveRoom);
      final room = await setup.site.getRoomDetail(roomId: 'https://steamcommunity.com/broadcast/watch/$_live');
      _expectParity(room, _result(legacy['getRoomDetail(watch link)']), changed: _enteredChanges);
      expect(room.roomId, _live);
      expect((await setup.site.getRoomDetail(roomId: 'https://steamcommunity.com/profiles/$_live')).roomId, _live);
      setup.http.requests.clear();
      expect(_result(legacy['getRoomDetail(not an id)']), containsPair('throws', 'SteamBroadcastException.identity'));
      await expectLater(setup.site.getRoomDetail(roomId: '123'), throwsA(isA<NotFound>()));
      await expectLater(
        setup.site.getLiveStatus(roomId: 'https://steamcommunity.com/id/gabelogannewell'),
        throwsA(isA<NotFound>()),
      );
      expect(setup.http.requests, isEmpty);
    });

    test(
      "the live status as 3.x's: two requests; offline or a restricted account is not live, unknown an error",
      () async {
        final live = _setup(_liveRoom);
        expect(await live.site.getLiveStatus(roomId: _live), _result(_legacy('S05-watch-live')['getLiveStatus']));
        expect(live.http.requests, hasLength(2));
        final offline = _setup(_offlineRoom);
        expect(
          await offline.site.getLiveStatus(roomId: _offline),
          _result(_legacy('S05-watch-offline')['getLiveStatus']),
        );
        expect(offline.http.requests, hasLength(2));
        // getbroadcastmpd answers a refresh whose getbroadcastinfo failed.
        final info = _answer(SteamBroadcastApi.infoUrl(_live), '', status: 500);
        for (final (success, expected) in [
          ('user_restricted', false),
          ('waiting_for_start', null),
          ('something_new', null),
        ]) {
          final setup = _setup(
            _liveRoom,
            extra: [
              info,
              _mpdAnswer({'success': success}),
            ],
          );
          if (expected == null) {
            await expectLater(
              setup.site.getLiveStatus(roomId: _live),
              throwsA(isA<StreamUnavailable>()),
              reason: success,
            );
          } else {
            expect(await setup.site.getLiveStatus(roomId: _live), expected, reason: success);
          }
          final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
          expect(
            room.effectiveLiveStatus,
            success == 'user_restricted' ? LiveStatus.banned : LiveStatus.unknown,
            reason: success,
          );
          expect(
            room.notice,
            success == 'user_restricted' ? SteamBroadcastApi.restrictedNotice : SteamBroadcastApi.chatNotice,
          );
        }
        final replay = _setup(
          _liveRoom,
          extra: [
            _answer(
              SteamBroadcastApi.infoUrl(_live),
              Fixture.load('steambroadcast', 'S02-info-live').body.replaceFirst('"is_replay": 0', '"is_replay": 1'),
            ),
          ],
        );
        expect(await replay.site.getLiveStatus(roomId: _live), isFalse, reason: 'a replay is not live');
      },
    );

    test('changed: rooms after the directory are filled from its cards, the viewers only while live (27-5)', () async {
      final setup = _setup([..._directory, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      final detail = await setup.site.getRoomDetail(roomId: _live);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final traced = _legacy('S05-watch-live')['after the directory'];
      _expectRooms(
        [detail, refreshed],
        _result(traced),
        changed: {'avatar', 'cover', ..._notice, 'watching', 'onlineViewers'},
      );
      expect(detail.title, 'NTE: Neverness to Everness');
      expect(detail.avatar, isNot(detail.cover), reason: "27-1: 3.x showed the card's cover as avatar");
      // The card's broadcaster ends: its last card's viewers are not kept.
      final ended = _setup(
        [..._directory, ..._offlineRoom, ..._liveRoom],
        extra: [_answer(SteamBroadcastApi.infoUrl(_live), Fixture.load('steambroadcast', 'S02-info-offline').body)],
      );
      final card = (await ended.site.getRecommendRooms()).first;
      expect(card.effectiveOnlineViewers, '6763');
      final after = await ended.site.getRoomDetailForRefresh(roomId: _live);
      expect(after.effectiveLiveStatus, LiveStatus.offline);
      expect(after.effectiveOnlineViewers, '', reason: '27-5: 3.x showed 6763');
      expect((after.title, after.cover), (card.title, card.cover), reason: "the last card's game and thumbnail (3.x)");
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
        if (url.path.startsWith('/miniprofile/')) return _response(request, '{"persona_name":"N"}');
        return _response(request, '{"success":42}');
      });
      final site = SteamBroadcastSite(http);
      for (var page = 1; page <= 101; page++) {
        await site.getRecommendRooms(page: page);
      }
      expect((await site.getRoomDetailForRefresh(roomId: id(10))).title, 'Game 10');
      expect((await site.getRoomDetailForRefresh(roomId: id(1009))).title, 'Game 1009');
      expect((await site.getRoomDetailForRefresh(roomId: id(9))).title, '', reason: 'forgotten');
    });
  });

  group('streams', () {
    test("changed: an entered live room: 3.x's quality and URL, now a line; recovery asks only two answers", () async {
      final legacy = _legacy('S05-watch-live')['getRoomDetail → streams'] as Map<String, dynamic>;
      final setup = _setup(_liveRoom);
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      final expected = (_result(legacy['getPlayQualites'])! as List).single as Map<String, dynamic>;
      expect(qualities.map((quality) => (quality.quality, quality.id)), [
        (expected['quality'], expected['id']),
      ], reason: "S05's master has one variant: the adaptive quality alone");
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
      final legacyRecovery = _legacyRequests(legacy['resolvePlayUrlsForRecoveryRaw']);
      expect(legacyRecovery, hasLength(3), reason: '3.x: the watch page, getbroadcastmpd, the master');
      expect(_sent(setup.http.requests), legacyRecovery.sublist(1), reason: 'a fresh master (REG-LEASE-005)');
      expect(_result(legacy['otherQuality']), containsPair('throws', 'SteamBroadcastException.schema'));
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: 'x', id: 'source'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: '720p', id: '720p'),
        ),
        throwsArgumentError,
        reason: 'a variant this master does not offer',
      );
    });

    test("a variant's quality (27-7): the master restricted to it (M7), applied as asked; recovery keeps it", () async {
      final setup = _setup(_scsRoom);
      final room = await setup.site.getRoomDetail(roomId: _scs);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      final hd = qualities[2];
      final resolution = await setup.site.resolvePlayUrlsRaw(detail: room, quality: hd);
      expect(resolution.urls, ['$_scsMasterUrl']);
      expect(resolution.appliedQualityData, '720p');
      expect(resolution.lines.single.codec, 'avc');
      expect(
        resolveAppliedPlayQuality(qualities: qualities, requested: hd, resolution: resolution).data,
        isA<SteamBroadcastVariant>(),
        reason: 'the player finds the selector in the applied quality',
      );
      final variant = hd.data! as SteamBroadcastVariant;
      final selection = variant.selectIn(Fixture.load('steambroadcast', 'S09-master-live').body, source: _scsMasterUrl);
      expect(selection.video.path, endsWith('/3500000/video.m3u8'));
      expect(
        (await setup.site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: '1080p60', id: '1080p60'),
        )).appliedQualityData,
        '1080p60',
        reason: 'a stored id without its data',
      );
      expect(setup.http.requests, isEmpty);
      final recovered = await setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: hd);
      expect(recovered.urls, ['$_scsMasterUrl']);
      expect(recovered.appliedQualityData, '720p');
      expect(setup.http.requests.map((request) => request.url.host), ['steamcommunity.com', _scsMasterUrl.host]);
      final gone = await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: '1440p60', id: '1440p60'),
      );
      expect(gone.appliedQualityData, 'auto', reason: 'a variant the fresh master lacks plays the adaptive quality');
      await expectLater(
        setup.site.resolvePlayUrlsForRecoveryRaw(
          detail: room,
          quality: const LivePlayQuality(quality: 'x', id: 'x'),
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

    test('a broadcast for subscribers only is live and says why it cannot be played; no master is asked', () async {
      final setup = _setup(
        _liveRoom,
        extra: [
          _mpdAnswer({'success': 'missing_subscription'}),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.subscribersOnly);
      expect(room.title, 'NTE: Neverness to Everness', reason: 'getbroadcastinfo still names it');
      expect(setup.http.requests.map((request) => request.url.path), [
        '/miniprofile/1524949844/json',
        '/broadcast/getbroadcastmpd/',
        '/broadcast/getbroadcastinfo/',
      ]);
      await expectLater(
        setup.site.getPlayQualities(detail: room),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'reason', contains('subscribers only'))),
      );
      final restricted = _setup(
        _liveRoom,
        extra: [
          _mpdAnswer({'success': 'user_restricted'}),
        ],
      );
      final banned = await restricted.site.getRoomDetail(roomId: _live);
      expect(banned.effectiveLiveStatus, LiveStatus.banned);
      expect(restricted.http.requests, hasLength(2), reason: 'nothing to read for an account that may not broadcast');
      await expectLater(restricted.site.getPlayQualities(detail: banned), throwsA(isA<StreamUnavailable>()));
    });

    test('a media problem no longer fails the room (3.x failed it, refresh included); the stream says why', () async {
      final china = _masterUrl.toString().replaceAll(_masterUrl.host, 'broadcast.st.dl.eccdnx.com');
      final otherHost = _setup(
        _liveRoom,
        extra: [
          _mpdAnswer({'hls_url': china}),
        ],
      );
      final entered = await otherHost.site.getRoomDetail(roomId: _live);
      expect(entered.effectiveLiveStatus, LiveStatus.live);
      expect(otherHost.http.requests, hasLength(3), reason: 'no master to ask for');
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
        final path = request.url.path;
        final sample = path.startsWith('/miniprofile/')
            ? 'S03-profile'
            : path.startsWith('/broadcast/getbroadcastinfo')
            ? 'S02-info-live'
            : 'S05-mpd-live';
        return _response(request, Fixture.load('steambroadcast', sample).body);
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
      expect(ended.http.requests, hasLength(1), reason: 'getbroadcastmpd only');
    });
  });

  group('links', () {
    test('watch and profile links (27-4) through the parser without a request; a custom address with one', () async {
      final http = ReplayHttp([ReplaySample.load('$_root/S10-vanity'), ReplaySample.load('$_root/S10-vanity-missing')]);
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
      expect(
        await parser.parse('https://steamcommunity.com/profiles/$_live'),
        const RoomLink('steambroadcast', _live),
        reason: '27-4 (3.x: not a room)',
      );
      expect(await parser.parse('https://steamcommunity.com/app/730/broadcasts'), isNull);
      expect(await parser.parse('https://steam.tv/example'), isNull);
      expect(http.requests, isEmpty);
      final site = registry.of('steambroadcast') as SteamBroadcastSite;
      expect(site.needsResolving('https://steamcommunity.com/id/probrawlhallastream/'), isTrue, reason: '27-4');
      expect(site.needsResolving('https://steamcommunity.com/profiles/$_live'), isFalse);
      expect(
        await parser.parse('主页 https://steamcommunity.com/id/gabelogannewell/'),
        const RoomLink('steambroadcast', _offline),
      );
      expect(http.requests.single.url.toString(), 'https://steamcommunity.com/id/gabelogannewell/?xml=1');
      expect(http.requests.single.headers, SteamBroadcastApi.xmlHeaders);
      expect(await parser.parse('https://steamcommunity.com/id/zzqx-no-such-vanity-27/'), isNull);
      expect(
        parser.containsSupportedLink('Steam https://steamcommunity.com/broadcast/watch/76561198373527746'),
        isTrue,
      );
    });
  });
}
