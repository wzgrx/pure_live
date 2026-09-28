// SixRoomSite over the recorded 6.cn responses (ReplayHttp) and a few
// synthetic ones: the request headers and forms, the homepage directory with
// 3.x's local pages and 90 s snapshot, the search and its room lookups, rooms
// cold (the room page's user id, which 3.x no longer found) and after the
// directory or search (3.x's remembered user ids and cards), the streams,
// cancellation, the deadline, links and the error mapping. Requests are
// compared with the ones 3.x sent (expected.json records them with their
// headers and forms).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/sixroom';

const _live = '8838';
const _liveUid = '56182128';
const _offline = '191111';
const _missing = '99999999999';
const _longKeyword = 'qzxqzxqzxqzxqzxqzxqz';

const _home = ['S04-home'];
const _liveRoom = ['S05-page-live', 'S05-inroom-live'];
const _offlineRoom = ['S05-page-offline', 'S05-inroom-offline'];
const _search = ['S02-search', 'S02-search-empty', 'S05-search-long'];

const LivePlayQuality _source = LivePlayQuality(quality: 'FLV 原始线路', id: 'flv:source');

Map<String, dynamic> _legacy(String sample) => Fixture.load('sixroom', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

/// The requests of a traced legacy call: `[method, url, headers, form]`
/// (names lower-cased; Dio added the form's content type).
List<List<Object?>> _legacyRequests(Object? traced) => [
  for (final request in ((traced! as Map<String, dynamic>)['requests'] as List).cast<Map<String, dynamic>>())
    [
      request['method'],
      request['url'],
      {
        for (final MapEntry(:key, :value) in (request['headers'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value as String,
        if (request['form'] != null) 'content-type': 'application/x-www-form-urlencoded',
      },
      request['form'],
    ],
];

List<List<Object?>> _sent(Iterable<LiveRequest> requests) => [
  for (final request in requests)
    [
      request.method,
      '${request.url}',
      request.headers,
      if (request.body case final body?) Uri.splitQueryString(utf8.decode(body)) else null,
    ],
];

typedef _Setup = ({SixRoomSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? clock}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: SixRoomSite(http, clock: clock), http: http);
}

/// The live inroom answer with [edit] applied, answered to [userId]'s form.
ReplaySample _inroom(void Function(Map<String, dynamic> root) edit, {String userId = _liveUid}) {
  final root = jsonDecode(Fixture.load('sixroom', 'S05-inroom-live').body) as Map<String, dynamic>;
  edit(root);
  return ReplaySample(
    method: 'POST',
    url: SixRoomApi.inroomUrl,
    status: 200,
    bytes: utf8.encode(jsonEncode(root)),
    form: SixRoomApi.inroomForm(userId),
  );
}

Map<String, dynamic> _content(Map<String, dynamic> root) => root['content'] as Map<String, dynamic>;

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
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('sixroom', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('sixroom', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// Asserts [room] equals 3.x's [legacy] projection on every key 3.x wrote,
/// except [changed] and `data` (3.x's `SixRoomRoom`).
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

List<String> _ids(Iterable<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

LiveArea _area(String id, String name) =>
    LiveArea(platform: 'sixroom', areaType: 'official', areaId: id, areaName: name, typeName: '六间房直播');

/// A room page of [roomId] naming [userId] (as 6.cn writes it now).
String _roomPage(String roomId, String userId) => [
  '<html><head><link rel="canonical" href="https://v.6.cn/$roomId"/></head><body><script>',
  "Object.assign(page, {\n  rid: '$userId',\n  roomid: $roomId,\n});",
  '</script></body></html>',
].join();

/// An inroom answer for [roomId] and [userId], offline.
String _inroomAnswer(String roomId, String userId) => jsonEncode({
  'flag': '001',
  'content': {
    'roominfo': {'id': userId, 'rid': roomId, 'alias': 'A$roomId'},
    'liveinfo': {'title': '', 'flvtitle': ''},
    'roomParamInfo': {'uid': userId, 'fans_num': 1},
  },
});

void main() {
  group('requests', () {
    test("3.x's URLs, headers and forms, no redirects, 15 s, as sixroom", () async {
      final setup = _setup([..._home, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      await setup.site.getRoomDetail(roomId: _live);
      final legacyDirectory = (_legacy('S04-home')['getDirectoryPage(all)'] as Map<String, dynamic>)['1'];
      final legacyRoom = (_legacy('S05-inroom-live')['after the directory'] as Map<String, dynamic>)['getRoomDetail'];
      expect(_sent(setup.http.requests), [..._legacyRequests(legacyDirectory), ..._legacyRequests(legacyRoom)]);
      expect(setup.http.requests.map((request) => request.method), ['GET', 'POST']);
      // Cold, the room page first: 3.x sent it too, then failed on it.
      final cold = _setup(_liveRoom);
      await cold.site.getRoomDetail(roomId: _live);
      final legacyCold = (_legacy('S05-inroom-live')['cold'] as Map<String, dynamic>)['getRoomDetail'];
      expect(_sent(cold.http.requests), [..._legacyRequests(legacyCold), ..._legacyRequests(legacyRoom)]);
      for (final request in [...setup.http.requests, ...cold.http.requests]) {
        expect(request.followRedirects, isFalse);
        expect(request.site, 'sixroom');
        expect(request.timeout, const Duration(seconds: 15));
      }
      expect((setup.site.id, setup.site.name), ('sixroom', '六间房直播'));
      expect(setup.site.directoryNoticeKey, _legacy('S04-home')['directoryNoticeKey']);
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Six Rooms chat');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        SixRoomSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(SixRoomSite(_Failing(TransportReason.cancelled)).getRecommendRooms(), _cancelled);
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (401, isA<RiskControl>()),
        (302, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (410, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (400, isA<NetworkFailure>()),
        (502, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(
          SixRoomSite(http).getRoomDetailForRefresh(roomId: _live),
          throwsA(matcher),
          reason: '$status',
        );
        expect(http.requests, hasLength(1), reason: 'the room page failed first');
      }
    });

    test(
      "one 20 s deadline per call (3.x's _scope): the deadline is NetworkFailure, a caller's cancel is cancelled",
      () async {
        final pending = Completer<LiveResponse>();
        final http = _Scripted((request) => pending.future);
        final site = SixRoomSite(http, deadline: const Duration(milliseconds: 50));
        await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()));
        expect(http.requests.single.cancel?.isCancelled, isTrue, reason: 'the request is cancelled too');
        expect(SixRoomSite(http).deadline, const Duration(seconds: 20));
        final cancel = CancelToken();
        final search = SixRoomSite(http).searchRoomsCancellable('诺', cancel: cancel);
        cancel.cancel();
        await expectLater(search, _cancelled);
        final directory = CancelToken();
        final page = SixRoomSite(http).getDirectoryPage(cancel: directory);
        directory.cancel();
        await expectLater(page, _cancelled);
        final before = http.requests.length;
        await expectLater(SixRoomSite(http).searchRoomsCancellable('诺', cancel: CancelToken()..cancel()), _cancelled);
        expect(http.requests, hasLength(before), reason: 'no request once cancelled');
      },
    );
  });

  group('directory', () {
    test('the one category without a request, on page 1 with a size of at least 1 (3.x)', () async {
      final setup = _setup(const []);
      final legacy = _legacy('S04-home');
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.single.children.map((area) => area.areaId), ['all', 'song', 'dance', 'talk', 'face', 'party']);
      expect(
        (await setup.site.getCategories(1, 3)).single.children.map((area) => area.areaId),
        _result(legacy['getCategores(pageSize: 3)']),
      );
      expect(await setup.site.getCategories(2, 30), hasLength(_result(legacy['getCategores(page: 2)'])! as int));
      expect(await setup.site.getCategories(1, 0), hasLength(_result(legacy['getCategores(pageSize: 0)'])! as int));
      expect(setup.http.requests, isEmpty);
    });

    test("every page of all rooms and of every area is 3.x's, with 3.x's requests", () async {
      final legacy = _legacy('S04-home');
      final setup = _setup(_home, clock: () => DateTime.utc(2026, 9, 28, 13, 50));
      final all = legacy['getDirectoryPage(all)'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in all.entries) {
        setup.http.requests.clear();
        final page = await setup.site.getDirectoryPage(page: int.parse(key), cancel: CancelToken());
        final expected = _result(value)! as Map<String, dynamic>;
        _expectRooms(page.rooms, expected['rooms'], reason: 'all $key');
        expect((page.page, page.hasMore), (expected['page'], expected['hasMore']), reason: 'all $key');
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: 'all $key');
      }
      final areas = legacy['getDirectoryPage(category)'] as Map<String, dynamic>;
      for (final MapEntry(key: areaId, value: pages) in areas.entries) {
        final name = {'all': '全部', 'song': '歌区', 'dance': '舞区', 'talk': '脱口秀', 'face': '星颜', 'party': '派对'}[areaId]!;
        for (final MapEntry(:key, :value) in (pages as Map<String, dynamic>).entries) {
          setup.http.requests.clear();
          final page = await setup.site.getDirectoryPage(page: int.parse(key), category: _area(areaId, name));
          final expected = _result(value)! as Map<String, dynamic>;
          expect(_ids(page.rooms), expected['rooms'], reason: '$areaId $key');
          expect(page.hasMore, expected['hasMore'], reason: '$areaId $key');
          expect(_sent(setup.http.requests), _legacyRequests(value), reason: '$areaId $key');
        }
      }
      _expectRooms(
        (await setup.site.getDirectoryPage(category: _area('song', '歌区'))).rooms,
        (_result(legacy['getDirectoryPage(song page 1)'])! as Map<String, dynamic>)['rooms'],
      );
    });

    test("3.x's 90 s homepage snapshot: page 1 of all rooms refreshes it, other pages and areas reuse it", () async {
      var now = DateTime.utc(2026, 9, 28, 13, 50);
      final setup = _setup(_home, clock: () => now);
      final legacy = _legacy('S04-home')['cache'] as Map<String, dynamic>;
      Future<void> step(String name, Future<List<LiveRoom>> Function() call) async {
        setup.http.requests.clear();
        expect(_ids(await call()), _result(legacy[name]), reason: name);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[name]), reason: name);
      }

      final site = setup.site;
      await step('song page 1 (empty cache)', () => site.getCategoryRooms(_area('song', '歌区')));
      await step('dance page 1', () => site.getCategoryRooms(_area('dance', '舞区')));
      await step('all page 2', () async => (await site.getDirectoryPage(page: 2)).rooms);
      await step('all page 1', () async => (await site.getDirectoryPage()).rooms);
      now = now.add(const Duration(seconds: 89));
      await step('+89 s talk page 1', () => site.getCategoryRooms(_area('talk', '脱口秀')));
      now = now.add(const Duration(seconds: 1));
      await step('+90 s talk page 1', () => site.getCategoryRooms(_area('talk', '脱口秀')));
      await step('recommend page 2', () => site.getRecommendRooms(page: 2));
      await step('recommend page 1', site.getRecommendRooms);
      now = now.subtract(const Duration(seconds: 1));
      await step('clock back 1 s: party page 1', () => site.getCategoryRooms(_area('party', '派对')));
    });

    test('a page below 1 is empty and another area an error, without a request; past 10000 too', () async {
      final setup = _setup(_home);
      final legacy = _legacy('S04-home')['getDirectoryPage(edge)'] as Map<String, dynamic>;
      for (final key in ['page 0', 'page 0 other platform']) {
        expect(_result(legacy[key]), {'rooms': <Object?>[], 'page': 0, 'hasMore': false}, reason: key);
      }
      final empty = await setup.site.getDirectoryPage(page: 0);
      expect((empty.rooms.length, empty.page, empty.hasMore), (0, 0, false));
      expect(
        (await setup.site.getDirectoryPage(
          page: 0,
          category: const LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'song'),
        )).rooms,
        isEmpty,
      );
      // 3.x: identity and schema failures before any request.
      for (final (key, area) in [
        ('other platform', const LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'song')),
        ('other areaType', const LiveArea(platform: 'sixroom', areaType: 'u0', areaId: 'song')),
        ('unknown area', _area('u10', '星颜')),
      ]) {
        expect(_result(legacy[key]), containsPair('throws', 'SixRoomException.identity'), reason: key);
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: key);
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: key);
      }
      expect(_result(legacy['page 10001']), containsPair('throws', 'SixRoomException.schema'));
      await expectLater(setup.site.getDirectoryPage(page: 10001), throwsA(isA<RangeError>()));
      await expectLater(setup.site.getRecommendRooms(page: 10001), throwsA(isA<RangeError>()));
      expect(setup.http.requests, isEmpty);
      final last = await setup.site.getDirectoryPage(page: 10000);
      expect((last.rooms.length, last.hasMore), (0, false));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['page 10000']));
      final spaced = await setup.site.getDirectoryPage(category: _area(' song ', '歌区'));
      expect(_ids(spaced.rooms), (_result(legacy['area id with spaces'])! as Map<String, dynamic>)['rooms']);
    });

    test("3.x's recommendation slices and area rooms, with 3.x's requests", () async {
      final legacy = _legacy('S04-home');
      final slices = legacy['getRecommendRooms'] as Map<String, dynamic>;
      for (final (page, size) in [(1, 30), (1, 3), (2, 20), (1, 0), (0, 30), (1, 101), (15, 30), (16, 30)]) {
        final setup = _setup(_home);
        final traced = slices['page $page size $size'];
        expect(_ids(await setup.site.getRecommendRooms(page: page, pageSize: size)), _result(traced));
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: '$page/$size');
      }
      _expectRooms(
        await _setup(_home).site.getRecommendRooms(pageSize: 3),
        _result(legacy['getRecommendRooms(page 1 size 3)']),
      );
      final areas = legacy['getCategoryRooms'] as Map<String, dynamic>;
      for (final (id, name) in [('song', '歌区'), ('face', '星颜'), ('party', '派对')]) {
        final setup = _setup(_home);
        final traced = areas['$id page 1 size 5'];
        _expectRooms(await setup.site.getCategoryRooms(_area(id, name), pageSize: 5), _result(traced), reason: id);
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: id);
      }
      final party = _setup(_home);
      expect(
        _ids(await party.site.getCategoryRooms(_area('party', '派对'), page: 2, pageSize: 20)),
        _result(areas['party page 2 size 20']),
      );
      expect(await party.site.getCategoryRooms(_area('party', '派对'), page: 0), isEmpty);
      expect(await party.site.getCategoryRooms(_area('party', '派对'), pageSize: 0), isEmpty);
      expect(party.http.requests, hasLength(1));
    });
  });

  group('search', () {
    test("keywords give 3.x's rooms with 3.x's requests", () async {
      final legacy = _legacy('S02-search')['searchRooms'] as Map<String, dynamic>;
      for (final (keyword, page, size) in [
        ('诺', 1, 30),
        (' 诺 ', 1, 30),
        ('诺', 1, 3),
        ('诺', 2, 30),
        ('诺', 0, 30),
        ('诺', 1, 0),
        ('诺', 1, 100),
        ('诺', 1, 101),
        ('', 1, 30),
        ('   ', 1, 30),
        ('qzxqzx', 1, 30),
        (_live, 2, 30),
        (_missing, 1, 30),
      ]) {
        final setup = _setup([..._search, ..._liveRoom, 'S03-room-notfound']);
        final traced = legacy['"$keyword" page $page size $size'];
        _expectRooms(
          await setup.site.searchRoomsCancellable(keyword, page: page, pageSize: size, cancel: CancelToken()),
          _result(traced),
          reason: '$keyword/$page/$size',
        );
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: '$keyword/$page/$size');
      }
    });

    test('keywords 6.cn calls too long are no result (3.x: access, or schema past 80 without a request)', () async {
      final legacy = _legacy('S02-search')['searchRooms'] as Map<String, dynamic>;
      final long = legacy['"$_longKeyword" page 1 size 30'];
      expect(_result(long), containsPair('throws', 'SixRoomException.access'));
      final setup = _setup(_search);
      expect(await setup.site.searchRooms(_longKeyword), isEmpty);
      expect(_sent(setup.http.requests), _legacyRequests(long));
      setup.http.requests.clear();
      final past = legacy['"${'x' * 81}" page 1 size 30'];
      expect(_result(past), containsPair('throws', 'SixRoomException.schema'));
      expect(await setup.site.searchRooms('x' * 81), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('a room number or link is that room, without its stream (3.x failed on the room page)', () async {
      final legacy = _legacy('S02-search')['searchRooms'] as Map<String, dynamic>;
      final known = (_legacy('S05-inroom-live')['knownUserId'] as Map<String, dynamic>)['includeMedia false'];
      for (final keyword in [_live, ' $_live ', 'https://v.6.cn/$_live', 'https://m.6.cn/profile/$_live']) {
        final traced = legacy['"$keyword" page 1 size 30'];
        expect(_result(traced), containsPair('throws', 'SixRoomException.schema'), reason: keyword);
        final setup = _setup(_liveRoom);
        final rooms = await setup.site.searchRooms(keyword);
        _expectParity(rooms.single, _result(known), reason: keyword);
        final data = rooms.single.data! as SixRoomRoomData;
        expect(data.stream, isNull);
        expect(_sent(setup.http.requests), [
          ..._legacyRequests(traced),
          ..._legacyRequests((_legacy('S05-inroom-live')['after the directory'] as Map)['getRoomDetailForRefresh']),
        ], reason: keyword);
      }
    });

    test('rooms after the search are filled from its cards; results are remembered (3.x)', () async {
      final setup = _setup([..._search, ..._offlineRoom]);
      final rooms = await setup.site.searchRooms('诺', pageSize: 1);
      expect(_ids(rooms), ['277288']);
      setup.http.requests.clear();
      final legacy = _legacy('S05-inroom-offline')['after the search'] as Map<String, dynamic>;
      final detail = await setup.site.getRoomDetail(roomId: _offline);
      _expectParity(detail, _result(legacy['getRoomDetail']));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getRoomDetail']));
      expect(setup.http.requests.single.method, 'POST', reason: 'the second card was remembered too');
      final again = await setup.site.searchRooms('诺', pageSize: 2);
      expect(again.last.effectiveLiveStatus, LiveStatus.offline, reason: 'the card takes the known state (3.x)');
    });

    test('a prompt page other than "too long" is RiskControl (3.x: access)', () async {
      final prompt = Fixture.load('sixroom', 'S05-search-long').body.replaceFirst('输入内容过长', '操作过于频繁');
      final setup = _setup(
        const [],
        extra: [ReplaySample(method: 'GET', url: SixRoomApi.searchUrl('诺'), status: 200, bytes: utf8.encode(prompt))],
      );
      await expectLater(setup.site.searchRooms('诺'), throwsA(isA<RiskControl>()));
    });
  });

  group('rooms', () {
    test("cold: the room page's user id, then 3.x's inroom room (3.x failed on the page)", () async {
      final legacy = _legacy('S05-inroom-live');
      final cold = legacy['cold'] as Map<String, dynamic>;
      final known = legacy['knownUserId'] as Map<String, dynamic>;
      final warm = legacy['after the directory'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        expect(_result(cold[depth]), containsPair('throws', 'SixRoomException.schema'), reason: depth);
        final setup = _setup(_liveRoom);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          _ => setup.site.getRoomDetailForRecording(roomId: _live),
        };
        final media = depth != 'getRoomDetailForRefresh';
        _expectParity(room, _result(known['includeMedia $media']), reason: depth);
        expect(_sent(setup.http.requests), [
          ..._legacyRequests(cold[depth]),
          ..._legacyRequests(warm[depth]),
        ], reason: depth);
        final data = room.data! as SixRoomRoomData;
        expect((data.userId, data.state), (_liveUid, SixRoomState.live));
        expect(data.stream != null, media, reason: '$depth: the stream only with the media (3.x)');
        expect(room.danmakuData, depth == 'getRoomDetail' ? isA<SixRoomDanmakuArgs>() : isNull);
      }
      expect(_result(cold['getLiveStatus']), containsPair('throws', 'SixRoomException.schema'));
      expect(await _setup(_liveRoom).site.getLiveStatus(roomId: _live), isTrue);
      final args = (await _setup(_liveRoom).site.getRoomDetail(roomId: _live)).danmakuData! as SixRoomDanmakuArgs;
      expect((args.roomId, args.userId), (_live, _liveUid));
    });

    test("after the directory: 3.x's rooms and requests (the remembered user id and card)", () async {
      final legacy = _legacy('S05-inroom-live')['after the directory'] as Map<String, dynamic>;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording', 'getLiveStatus']) {
        final setup = _setup([..._home, ..._liveRoom]);
        await setup.site.getDirectoryPage(cancel: CancelToken());
        setup.http.requests.clear();
        final result = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          'getRoomDetailForRecording' => setup.site.getRoomDetailForRecording(roomId: _live),
          _ => setup.site.getLiveStatus(roomId: _live),
        };
        if (result is LiveRoom) {
          _expectParity(result, _result(legacy[depth]), reason: depth);
          expect(result.avatar, isNot(result.cover), reason: "the card's avatar (3.x)");
        } else {
          expect(result, _result(legacy[depth]));
        }
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: depth);
      }
      final setup = _setup([..._home, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      final link = await setup.site.getRoomDetail(roomId: 'https://v.6.cn/$_live?from=home');
      _expectParity(link, _result(_legacy('S05-inroom-live')['getRoomDetail(link)']));
      expect(link.roomId, _live);
      await setup.site.getRoomDetail(roomId: _live);
      final card = (await setup.site.getDirectoryPage(cancel: CancelToken())).rooms.first;
      _expectRooms([card], _result(_legacy('S05-inroom-live')['directory card after the room']));
      expect(card.followers, '425628', reason: "the room's followers stay on the card (3.x)");
    });

    test("offline: 3.x's room cold and after the search", () async {
      final legacy = _legacy('S05-inroom-offline');
      final cold = legacy['cold'] as Map<String, dynamic>;
      final warm = legacy['after the search'] as Map<String, dynamic>;
      final setup = _setup(_offlineRoom);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      expect(_result(cold['getRoomDetail']), containsPair('throws', 'SixRoomException.schema'));
      _expectParity(room, _result(legacy['knownUserId']));
      expect(_sent(setup.http.requests), [
        ..._legacyRequests(cold['getRoomDetail']),
        ..._legacyRequests(warm['getRoomDetail']),
      ]);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(await _setup(_offlineRoom).site.getLiveStatus(roomId: _offline), isFalse);
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final searched = _setup([..._offlineRoom, 'S02-search']);
        await searched.site.searchRooms('诺');
        final detail = await switch (depth) {
          'getRoomDetail' => searched.site.getRoomDetail(roomId: _offline),
          'getRoomDetailForRefresh' => searched.site.getRoomDetailForRefresh(roomId: _offline),
          _ => searched.site.getRoomDetailForRecording(roomId: _offline),
        };
        _expectParity(detail, _result(warm[depth]), reason: depth);
      }
    });

    test('a room that does not exist is NotFound; an id that is none too, without a request', () async {
      final legacy = _legacy('S03-room-notfound');
      final setup = _setup(['S03-room-notfound']);
      expect(_result(legacy['getRoomDetail']), containsPair('throws', 'SixRoomException.missing'));
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: _missing), throwsA(isA<NotFound>()));
      expect(await setup.site.searchRooms(_missing), _result(legacy['searchRooms']));
      expect(_sent(setup.http.requests.take(1)), _legacyRequests(legacy['getRoomDetail']));
      expect(setup.http.requests, hasLength(3));
      // 6.cn's "暂不能进入此房间" for a user without a room (3.x: access).
      final missing = _legacy('S05-inroom-missing')['room'];
      expect(_result(missing), containsPair('throws', 'SixRoomException.access'));
      final refused = _setup(
        const [],
        extra: [
          ReplaySample(
            method: 'GET',
            url: SixRoomApi.roomUrl('88381'),
            status: 200,
            bytes: utf8.encode(_roomPage('88381', _missing)),
          ),
          ReplaySample.load('$_root/S05-inroom-missing'),
        ],
      );
      await expectLater(refused.site.getRoomDetail(roomId: '88381'), throwsA(isA<NotFound>()));
      expect(_sent(refused.http.requests.skip(1)), _legacyRequests(missing));
      final none = _setup(const []);
      for (final id in ['abc', '1', 'https://v.6.cn/search.php']) {
        await expectLater(none.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(_result(_legacy('S05-inroom-live')['getRoomDetail(not an id)']), containsPair('throws', anything));
      expect(none.http.requests, isEmpty);
    });

    test('a private or black-screen room is unknown with its notice; its status and streams are unavailable', () async {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (root) => _content(root)['isPriveRoom'] = 1,
        (root) => _content(root)['blackScreenInfo'] = {'msg': '黑屏', 'endtm': 1},
      ]) {
        final setup = _setup(_liveRoom, extra: [_inroom(edit)]);
        final room = await setup.site.getRoomDetail(roomId: _live);
        expect(room.effectiveLiveStatus, LiveStatus.unknown);
        expect(room.notice, '${SixRoomApi.restrictedNotice}\n${SixRoomApi.chatNotice}');
        await expectLater(setup.site.getLiveStatus(roomId: _live), throwsA(isA<StreamUnavailable>()));
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      }
    });

    test('the site remembers the last 2000 rooms (3.x: every one)', () async {
      const count = 2001;
      final http = _Scripted((request) {
        final url = request.url;
        if (url.path == '/') {
          final rows = [
            for (var index = 0; index < count; index++)
              {'rid': '${1000 + index}', 'uid': '${10000000 + index}', 'username': 'N$index'},
          ];
          return _response(
            request,
            '<script>window.__SMARTY_ALL_VARIABLES__ = ${jsonEncode({'typeList': rows})};</script>',
          );
        }
        if (request.method == 'POST') {
          final userId = Uri.splitQueryString(utf8.decode(request.body!))['ruid']!;
          return _response(request, _inroomAnswer('${int.parse(userId) - 10000000 + 1000}', userId));
        }
        final roomId = url.pathSegments.single;
        return _response(request, _roomPage(roomId, '${int.parse(roomId) - 1000 + 10000000}'));
      });
      final site = SixRoomSite(http);
      for (var page = 1; page <= 21; page++) {
        await site.getRecommendRooms(page: page, pageSize: 100);
      }
      http.requests.clear();
      await site.getRoomDetailForRefresh(roomId: '${1000 + count - 1}');
      expect(http.requests.map((request) => request.method), ['POST'], reason: 'remembered');
      http.requests.clear();
      await site.getRoomDetailForRefresh(roomId: '1000');
      expect(http.requests.map((request) => request.method), ['GET', 'POST'], reason: 'forgotten: the room page');
    });
  });

  group('streams', () {
    test("an entered live room: 3.x's quality and URL, now a line; recovery asks the room again", () async {
      final legacy =
          (_legacy('S05-inroom-live')['after the directory'] as Map<String, dynamic>)['getRoomDetail → streams']
              as Map<String, dynamic>;
      final setup = _setup([..._home, ..._liveRoom]);
      await setup.site.getDirectoryPage(cancel: CancelToken());
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      final expected = (_result(legacy['getPlayQualites'])! as List).single as Map<String, dynamic>;
      expect(
        (qualities.single.quality, qualities.single.id, qualities.single.sort),
        (expected['quality'], expected['id'], expected['sort']),
      );
      final resolution = await setup.site.resolvePlayUrlsRaw(detail: room, quality: qualities.single);
      final urls = _result(legacy['resolvePlayUrlsRaw'])! as Map<String, dynamic>;
      expect(resolution.urls, urls['urls']);
      expect(resolution.appliedQualityData, urls['appliedQualityData']);
      final line = resolution.lines.single;
      expect((line.format, line.codec, line.lineId), (StreamFormat.flv, 'avc', 'wlive'));
      expect(line.lease, isNull, reason: 'no expiry in the address');
      expect(line.headers, isEmpty, reason: "3.x's player and recorder sent no Six Rooms headers");
      expect(await setup.site.getPlayUrls(detail: room, quality: _source), _result(legacy['getPlayUrls']));
      expect(setup.http.requests, isEmpty, reason: 'no request (3.x)');
      final recovered = await setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _source);
      expect(recovered.urls, (_result(legacy['resolvePlayUrlsForRecoveryRaw'])! as Map)['urls']);
      expect(_sent(setup.http.requests), _legacyRequests(legacy['resolvePlayUrlsForRecoveryRaw']));
      expect(setup.http.requests, hasLength(1), reason: 'a fresh room (REG-LEASE-005)');
      expect(_result(legacy['otherQuality']), containsPair('throws', 'SixRoomException.mediaUnavailable'));
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: 'x', id: 'source'),
        ),
        throwsArgumentError,
      );
      // Cold, entered through the room page, the same stream.
      final cold = _setup(_liveRoom);
      final entered = await cold.site.getRoomDetailForRecording(roomId: _live);
      expect((await cold.site.resolvePlayUrlsRaw(detail: entered, quality: _source)).urls, urls['urls']);
    });

    test('rooms that cannot be played say why, without a request', () async {
      final setup = _setup([..._liveRoom, ..._offlineRoom, ..._home]);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      final card = (await setup.site.getRecommendRooms()).first;
      setup.http.requests.clear();
      final refreshLegacy =
          (_legacy('S05-inroom-live')['after the directory']
                  as Map<String, dynamic>)['getRoomDetailForRefresh → streams']
              as Map<String, dynamic>;
      final offlineLegacy =
          (_legacy('S05-inroom-offline')['after the search'] as Map<String, dynamic>)['getRoomDetail → streams']
              as Map<String, dynamic>;
      // 3.x: identity for a refreshed room; no qualities and
      // mediaUnavailable for an offline one.
      expect(_result(refreshLegacy['getPlayQualites']), containsPair('throws', 'SixRoomException.identity'));
      expect(_result(offlineLegacy['getPlayQualites']), isEmpty);
      expect(_result(offlineLegacy['resolvePlayUrlsRaw']), containsPair('throws', 'SixRoomException.mediaUnavailable'));
      for (final (name, room) in [('refreshed', refreshed), ('offline', offline), ('card', card)]) {
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()), reason: name);
        await expectLater(
          setup.site.resolvePlayUrlsRaw(detail: room, quality: _source),
          throwsA(isA<StreamUnavailable>()),
          reason: name,
        );
        await expectLater(
          setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _source),
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

    test('a live room with an unusable stream name keeps its state; the stream says why', () async {
      final setup = _setup(
        _liveRoom,
        extra: [_inroom((root) => (_content(root)['liveinfo'] as Map<String, dynamic>)['flvtitle'] = 'v1-2')],
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));
    });

    test('recovery of a room that went offline says so', () async {
      final room = await _setup(_liveRoom).site.getRoomDetail(roomId: _live);
      final ended = _setup(
        _liveRoom,
        extra: [_inroom((root) => (_content(root)['liveinfo'] as Map<String, dynamic>).remove('id'))],
      );
      await expectLater(
        ended.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _source),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(ended.http.requests, hasLength(2));
    });
  });

  group('links', () {
    test('room links through the parser, without a request; other pages are not rooms', () async {
      final http = ReplayHttp(const []);
      final registry = SiteRegistry({'sixroom': () => SixRoomSite(http)});
      final parser = LinkParser(registry, http);
      expect(await parser.parse('直播 https://v.6.cn/8838?from=home'), const RoomLink('sixroom', '8838'));
      expect(await parser.parse('看 https://m.6.cn/profile/243126861。'), const RoomLink('sixroom', '243126861'));
      expect(await parser.parse('http://m.6.cn/8838'), const RoomLink('sixroom', '8838'));
      for (final text in [
        'https://v.6.cn/search.php?key=8838',
        'https://m.v.6.cn/redian/8838',
        'https://v.6.cn.evil.test/8838',
        'https://www.6.cn/8838',
        'https://v.6.cn/8838#chat',
      ]) {
        expect(await parser.parse(text), isNull, reason: text);
      }
      expect(http.requests, isEmpty);
      expect(parser.containsSupportedLink('直播 https://v.6.cn/8838'), isTrue);
      final site = registry.of('sixroom') as SixRoomSite;
      expect(site.roomIdFromUrl('https://v.6.cn/profile/8838'), '8838');
      expect(site.needsResolving('https://v.6.cn/8838'), isFalse);
    });
  });
}
