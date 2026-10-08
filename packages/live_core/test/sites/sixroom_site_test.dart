// SixRoomSite over the recorded 6.cn responses (ReplayHttp) and a few
// synthetic ones: the request headers and forms, the directory (all rooms
// still the homepage with 3.x's local pages and 90 s snapshot; the areas and
// recommendations the app's mobile lists and 星颜 the web's subarea list
// since M4.U.31), the search and its room lookups, rooms cold (the room
// page's user id, which 3.x no longer found) and after the directory or
// search (3.x's remembered user ids and cards), the streams, cancellation,
// the deadline, links and the error mapping. Requests are compared with the
// ones 3.x sent (expected.json records them with their headers and forms);
// intended differences are listed with `changed:` and the upgrade's number.
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

/// The live broadcast's start (inroom `liveinfo.starttime`).
final _liveStart = DateTime.utc(2026, 9, 28, 11, 25, 29);

const _home = ['S04-home'];
const _liveRoom = ['S05-page-live', 'S05-inroom-live'];
const _offlineRoom = ['S05-page-offline', 'S05-inroom-offline'];
const _search = ['S02-search', 'S02-search-empty', 'S05-search-long'];

/// The mobile lists at 30 a page and the web's 星颜 list (S06, 2026-09-28
/// 21:02 UTC).
const _lists = [
  'S06-list-special-p1',
  'S06-list-special-p2',
  'S06-list-u0-p1',
  'S06-list-u0-p2',
  'S06-list-u1-p1',
  'S06-list-u2-p1',
  'S06-list-u8-p1',
  'S06-list-u10-p1',
  'S06-subarea-face',
];

const LivePlayQuality _source = LivePlayQuality(quality: 'FLV 原始线路', id: 'flv:source');

/// Room keys every room changed: the notice is in words for users now
/// (unified rule "说明文字"), and since M5.27 (chat is shown) it only says
/// what the audience number is.
const _notice = {'notice'};

/// Room keys of a room read from inroom with no card seen: the title is the
/// broadcaster's signature (31-2), the avatar the broadcaster's own (31-1;
/// 3.x showed the cover), and the notice.
const _inroomRoom = {'title', 'avatar', 'notice'};

/// Room keys of a room read from inroom after a card with the broadcaster's
/// avatar: only the title (31-2) and the notice (the avatar is the same
/// image).
const _inroomAfterCard = {'title', 'notice'};

/// Room keys of a search card: its state (31-3), no area stand-in (unified
/// rule "占位信息"), and the notice.
const _searchCard = {'liveStatus', 'status', 'area', 'notice'};

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

/// The request of page [page] of the mobile list [type] at [size].
List<Object?> _listRequest(String type, int page, {int size = 30}) => [
  'GET',
  '${SixRoomApi.listUrl(type, page: page, size: size)}',
  SixRoomApi.listHeaders,
  null,
];

/// The request of the web's 星颜 list.
final List<Object?> _faceRequest = ['GET', '${SixRoomApi.subareaUrl(10)}', SixRoomApi.webHeaders, null];

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

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
  final expected = (legacy! as List).cast<Map<String, dynamic>>();
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], changed: changed, reason: '$reason[$index]');
  }
}

/// Asserts the homepage cards [rooms] equal 3.x's [legacy] ones: the
/// notice is new, and the one room without an area has none (3.x wrote the
/// platform's name; unified rule "占位信息").
void _expectHomeCards(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  _expectRooms(rooms, legacy, changed: {..._notice, 'area'}, reason: reason);
  for (final (index, room) in rooms.indexed) {
    final area = ((legacy! as List)[index] as Map<String, dynamic>)['area'];
    expect(room.area, area == SixRoomApi.siteName ? '' : area, reason: '$reason[$index]');
  }
}

List<String> _ids(Iterable<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

LiveArea _area(String id, String name) =>
    LiveArea(platform: 'sixroom', areaType: 'official', areaId: id, areaName: name, typeName: '六间房直播');

final LiveArea _all = _area('all', '全部');

const _areaNames = {'all': '全部', 'song': '歌区', 'dance': '舞区', 'talk': '脱口秀', 'face': '星颜', 'party': '派对'};

/// The rooms of the mobile list sample [name].
List<String> _listIds(String name, String type) {
  final url = Fixture.load('sixroom', name).url;
  return [
    for (final room in SixRoomApi.list(
      Fixture.load('sixroom', name).body,
      type: type,
      page: int.parse(url.queryParameters['p']!),
      size: int.parse(url.queryParameters['size']!),
    ).rooms)
      room.roomId,
  ];
}

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

/// A mobile list row of room [roomId].
Map<String, Object?> _row(String roomId) => {
  'rid': roomId,
  'uid': '${10000000 + int.parse(roomId)}',
  'username': 'N$roomId',
  'liveid': '2224${roomId.padLeft(5, '0')}',
  'count': 100,
  'anchor_area': '歌区',
};

void main() {
  group('requests', () {
    test("3.x's URLs, headers and forms, no redirects, 15 s, as sixroom; the app's and the web's lists", () async {
      final setup = _setup([..._home, ..._liveRoom, ..._lists]);
      await setup.site.getDirectoryPage(category: _all, cancel: CancelToken());
      await setup.site.getRoomDetail(roomId: _live);
      final legacyDirectory = (_legacy('S04-home')['getDirectoryPage(all)'] as Map<String, dynamic>)['1'];
      final legacyRoom = (_legacy('S05-inroom-live')['after the directory'] as Map<String, dynamic>)['getRoomDetail'];
      expect(_sent(setup.http.requests), [..._legacyRequests(legacyDirectory), ..._legacyRequests(legacyRoom)]);
      expect(setup.http.requests.map((request) => request.method), ['GET', 'POST']);
      // 31-4: the recommendations and areas are the app's lists (its
      // headers, without a body), 星颜 the web's subarea list.
      setup.http.requests.clear();
      await setup.site.getDirectoryPage(cancel: CancelToken());
      await setup.site.getCategoryRooms(_area('song', '歌区'));
      await setup.site.getCategoryRooms(_area('face', '星颜'));
      expect(_sent(setup.http.requests), [_listRequest('special', 1), _listRequest('u0', 1), _faceRequest]);
      expect(SixRoomApi.listHeaders, {
        'user-agent': SixRoomApi.mobileUserAgent,
        'accept': 'application/json,text/plain,*/*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
        'referer': 'https://ios.6.cn/?ver=8.0.3&build=4',
      });
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
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Six Rooms chat (31-6 is M5)');
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
        await expectLater(SixRoomSite(http).getRecommendRooms(), throwsA(matcher), reason: 'list $status');
        await expectLater(
          SixRoomSite(http).getCategoryRooms(_area('face', '星颜')),
          throwsA(matcher),
          reason: 'subarea $status',
        );
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
        await expectLater(site.getRecommendRooms(), throwsA(isA<NetworkFailure>()));
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
      expect(categories.single.children.map((area) => area.areaName), _areaNames.values);
      expect(
        (await setup.site.getCategories(1, 3)).single.children.map((area) => area.areaId),
        _result(legacy['getCategores(pageSize: 3)']),
      );
      expect(await setup.site.getCategories(2, 30), hasLength(_result(legacy['getCategores(page: 2)'])! as int));
      expect(await setup.site.getCategories(1, 0), hasLength(_result(legacy['getCategores(pageSize: 0)'])! as int));
      expect(setup.http.requests, isEmpty);
    });

    test("every page of all rooms is 3.x's, with 3.x's requests (the homepage, 90 s)", () async {
      final legacy = _legacy('S04-home');
      final setup = _setup(_home, clock: () => DateTime.utc(2026, 9, 28, 13, 50));
      final all = legacy['getDirectoryPage(all)'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in all.entries) {
        setup.http.requests.clear();
        final page = await setup.site.getDirectoryPage(page: int.parse(key), category: _all, cancel: CancelToken());
        final expected = _result(value)! as Map<String, dynamic>;
        _expectHomeCards(page.rooms, expected['rooms'], reason: 'all $key');
        expect((page.page, page.hasMore), (expected['page'], expected['hasMore']), reason: 'all $key');
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: 'all $key');
      }
      final pages = (legacy['getDirectoryPage(category)'] as Map<String, dynamic>)['all'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in pages.entries) {
        setup.http.requests.clear();
        final page = await setup.site.getDirectoryPage(page: int.parse(key), category: _all);
        final expected = _result(value)! as Map<String, dynamic>;
        expect(_ids(page.rooms), expected['rooms'], reason: 'all area $key');
        expect(page.hasMore, expected['hasMore'], reason: 'all area $key');
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: 'all area $key');
      }
      // The cards carry the broadcast's start (M2.1).
      final first = (await setup.site.getDirectoryPage(category: _all)).rooms;
      expect(first.every((room) => room.startedAt != null), isTrue);
      expect(first.every((room) => room.restriction == null), isTrue, reason: 'a card says nothing about it');
    });

    test("the areas are the app's lists, a request a page; 3.x filtered the homepage (31-4)", () async {
      final setup = _setup([..._home, ..._lists]);
      // 3.x's pages of these areas were the homepage filtered (13:51 UTC);
      // the app's lists are a later recording (21:02 UTC), so the rooms are
      // not compared with 3.x's.
      for (final (id, type, pages) in [('song', 'u0', 2), ('dance', 'u1', 1), ('talk', 'u2', 1), ('party', 'u8', 1)]) {
        for (var page = 1; page <= pages; page++) {
          setup.http.requests.clear();
          final result = await setup.site.getDirectoryPage(page: page, category: _area(id, _areaNames[id]!));
          expect(_ids(result.rooms), _listIds('S06-list-$type-p$page', type), reason: '$id $page');
          expect(result.hasMore, page < pages, reason: '$id $page');
          expect(_sent(setup.http.requests), [_listRequest(type, page)], reason: '$id $page');
          for (final room in result.rooms) {
            expect(room.area, _areaNames[id], reason: '$id ${room.roomId}');
            expect(room.isLiveNow, isTrue);
            expect(room.startedAt, isNotNull);
          }
        }
      }
      // The same through the category rooms, at any page size (the list
      // takes it).
      setup.http.requests.clear();
      final song = await setup.site.getCategoryRooms(_area('song', '歌区'), page: 2);
      expect(_ids(song), _listIds('S06-list-u0-p2', 'u0'));
      expect(_sent(setup.http.requests), [_listRequest('u0', 2)]);
      final small = _setup(['S01-list-u8-p1']);
      expect(
        _ids(await small.site.getCategoryRooms(_area('party', '派对'), pageSize: 20)),
        _listIds('S01-list-u8-p1', 'u8'),
      );
      expect(_sent(small.http.requests), [_listRequest('u8', 1, size: 20)]);
    });

    test("星颜 is the web's subarea list (the app's is empty), read whole and paged locally for 90 s", () async {
      var now = DateTime.utc(2026, 9, 28, 21, 3);
      final setup = _setup(_lists, clock: () => now);
      final face = _area('face', '星颜');
      final all = [
        for (final room in SixRoomApi.subarea(Fixture.load('sixroom', 'S06-subarea-face').body)) room.roomId,
      ];
      expect(all, hasLength(9));
      Future<void> step(int page, List<String> ids, {required bool request}) async {
        setup.http.requests.clear();
        expect(_ids(await setup.site.getCategoryRooms(face, page: page, pageSize: 4)), ids, reason: '$now $page');
        expect(_sent(setup.http.requests), [if (request) _faceRequest], reason: '$now $page');
      }

      // Page 2 with no snapshot loads it; pages 3 and 4 reuse it.
      await step(2, [...all.skip(4).take(4)], request: true);
      await step(3, [all.last], request: false);
      await step(4, [], request: false);
      // Page 1 reloads; the snapshot serves for 90 s.
      await step(1, [...all.take(4)], request: true);
      now = now.add(const Duration(seconds: 89));
      await step(2, [...all.skip(4).take(4)], request: false);
      now = now.add(const Duration(seconds: 1));
      await step(2, [...all.skip(4).take(4)], request: true);
      final page = await setup.site.getDirectoryPage(category: face);
      expect(_ids(page.rooms), all);
      expect(page.hasMore, isFalse);
      expect(page.rooms.every((room) => room.avatar.isNotEmpty && room.area == '星颜'), isTrue);
      expect(page.rooms.first.startedAt, isNull, reason: 'the featured rows have no realstarttime');
      expect(page.rooms[3].startedAt, isNotNull);
    });

    test("the recommendations are the app's `special` list (31-4; 3.x: all rooms)", () async {
      final setup = _setup([..._lists, 'S01-list-special-p1']);
      final first = await setup.site.getDirectoryPage(cancel: CancelToken());
      expect(_ids(first.rooms), _listIds('S06-list-special-p1', 'special'));
      expect(first.hasMore, isTrue);
      final second = await setup.site.getDirectoryPage(page: 2);
      expect(_ids(second.rooms), _listIds('S06-list-special-p2', 'special'));
      expect(second.hasMore, isFalse);
      expect(_sent(setup.http.requests), [_listRequest('special', 1), _listRequest('special', 2)]);
      expect(first.rooms.map((room) => room.area).toSet(), containsAll(['歌区', '舞区', '脱口秀', '星颜']));
      setup.http.requests.clear();
      expect(await setup.site.getRecommendRooms(), hasLength(30));
      expect(_ids(await setup.site.getRecommendRooms(pageSize: 20)), _listIds('S01-list-special-p1', 'special'));
      expect(_sent(setup.http.requests), [_listRequest('special', 1), _listRequest('special', 1, size: 20)]);
      // 3.x's slices that send nothing.
      final slices = _legacy('S04-home')['getRecommendRooms'] as Map<String, dynamic>;
      setup.http.requests.clear();
      for (final (page, size) in [(1, 0), (0, 30)]) {
        expect(await setup.site.getRecommendRooms(page: page, pageSize: size), isEmpty);
        expect(_result(slices['page $page size $size']), isEmpty);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('a list leaves out the rooms its earlier pages gave since page 1 (the list moves between pages)', () async {
      final pages = <int, List<String>>{
        1: ['101', '102', '103'],
        2: ['103', '104', '101', '105'],
        3: ['103', '101'],
      };
      final http = _Scripted((request) {
        final page = int.parse(request.url.queryParameters['p']!);
        final size = int.parse(request.url.queryParameters['size']!);
        return _response(
          request,
          jsonEncode({
            'flag': '001',
            'content': {
              'u0': [for (final id in pages[page] ?? const <String>[]) _row(id)],
              'roomListCount': {'u0': size * 3 + 1},
            },
          }),
        );
      });
      final site = SixRoomSite(http);
      final song = _area('song', '歌区');
      expect(_ids(await site.getCategoryRooms(song)), ['101', '102', '103']);
      expect(_ids(await site.getCategoryRooms(song, page: 2)), ['104', '105']);
      final all = await site.getDirectoryPage(page: 3, category: song);
      expect((all.rooms.length, all.hasMore), (0, true), reason: 'nothing new, and the list goes on');
      // A page asked again is measured against the pages before it only.
      expect(_ids(await site.getCategoryRooms(song, page: 2)), ['104', '105']);
      // Page 1 starts again; another page size is its own sequence.
      expect(_ids(await site.getCategoryRooms(song)), ['101', '102', '103']);
      expect(_ids(await site.getCategoryRooms(song, page: 2, pageSize: 20)), ['103', '104', '101', '105']);
      expect(http.requests, hasLength(6));
    });

    test("the homepage's 90 s snapshot (3.x) is for all rooms only; page 1 reloads it", () async {
      var now = DateTime.utc(2026, 9, 28, 13, 50);
      final setup = _setup([..._home, ..._lists], clock: () => now);
      final legacy = _legacy('S04-home')['cache'] as Map<String, dynamic>;
      final homeRequest = _legacyRequests((_legacy('S04-home')['getDirectoryPage(all)'] as Map)['1']);
      Future<void> step(String name, Future<List<LiveRoom>> Function() call, {required bool home}) async {
        setup.http.requests.clear();
        final rooms = await call();
        if (name == 'all page 2' || name == 'all page 1') expect(_ids(rooms), _result(legacy[name]), reason: name);
        expect(_sent(setup.http.requests).where((request) => request[1] == '${SixRoomApi.homeUrl}'), [
          if (home) ...homeRequest,
        ], reason: name);
      }

      final site = setup.site;
      // The areas no longer load the homepage (3.x's first step did).
      await step('song page 1', () => site.getCategoryRooms(_area('song', '歌区')), home: false);
      await step('all page 2', () async => (await site.getDirectoryPage(page: 2, category: _all)).rooms, home: true);
      await step('all page 3', () async => (await site.getDirectoryPage(page: 3, category: _all)).rooms, home: false);
      await step('all page 1', () async => (await site.getDirectoryPage(category: _all)).rooms, home: true);
      now = now.add(const Duration(seconds: 89));
      await step('+89 s all page 2', () => site.getCategoryRooms(_all, page: 2), home: false);
      now = now.add(const Duration(seconds: 1));
      await step('+90 s all page 2', () => site.getCategoryRooms(_all, page: 2), home: true);
      await step('recommend page 1', site.getRecommendRooms, home: false);
      now = now.subtract(const Duration(seconds: 1));
      await step('clock back 1 s: all page 2', () => site.getCategoryRooms(_all, page: 2), home: true);
      expect(_result(legacy['all page 2']), isNotEmpty);
    });

    test('a page below 1 is empty and another area an error, without a request; past 10000 too', () async {
      final setup = _setup([..._home, ..._lists]);
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
      await expectLater(setup.site.getCategoryRooms(_all, page: 10001), throwsA(isA<RangeError>()));
      expect(setup.http.requests, isEmpty);
      final last = await setup.site.getDirectoryPage(page: 10000, category: _all);
      expect((last.rooms.length, last.hasMore), (0, false));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['page 10000']));
      // 3.x trimmed the area id.
      setup.http.requests.clear();
      final spaced = await setup.site.getDirectoryPage(category: _area(' song ', '歌区'));
      expect(_ids(spaced.rooms), _listIds('S06-list-u0-p1', 'u0'));
      expect(_sent(setup.http.requests), [_listRequest('u0', 1)]);
    });

    test("all rooms by any page size are 3.x's recommendations (3.x's recommendations were all rooms)", () async {
      final legacy = _legacy('S04-home');
      final slices = legacy['getRecommendRooms'] as Map<String, dynamic>;
      for (final (page, size) in [(1, 30), (1, 3), (2, 20), (1, 101), (15, 30), (16, 30)]) {
        final setup = _setup(_home);
        final traced = slices['page $page size $size'];
        expect(_ids(await setup.site.getCategoryRooms(_all, page: page, pageSize: size)), _result(traced));
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: '$page/$size');
      }
      _expectHomeCards(
        await _setup(_home).site.getCategoryRooms(_all, pageSize: 3),
        _result(legacy['getRecommendRooms(page 1 size 3)']),
      );
      final face = _setup(_lists);
      expect(await face.site.getCategoryRooms(_area('face', '星颜'), page: 0), isEmpty);
      expect(await face.site.getCategoryRooms(_area('face', '星颜'), pageSize: 0), isEmpty);
      expect(face.http.requests, isEmpty);
    });
  });

  group('search', () {
    test("keywords give 3.x's rooms with 3.x's requests; cards say whether they are live (31-3)", () async {
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
        final rooms = await setup.site.searchRoomsCancellable(
          keyword,
          page: page,
          pageSize: size,
          cancel: CancelToken(),
        );
        _expectRooms(rooms, _result(traced), changed: _searchCard, reason: '$keyword/$page/$size');
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: '$keyword/$page/$size');
        for (final room in rooms) {
          expect(
            room.liveStatus,
            room.roomId == '277288' || room.roomId == '68160' ? LiveStatus.live : LiveStatus.offline,
          );
        }
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
        _expectParity(rooms.single, _result(known), changed: _inroomRoom, reason: keyword);
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
      _expectParity(detail, _result(legacy['getRoomDetail']), changed: _inroomAfterCard);
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getRoomDetail']));
      expect(setup.http.requests.single.method, 'POST', reason: 'the second card was remembered too');
      final again = await setup.site.searchRooms('诺', pageSize: 2);
      expect(again.last.effectiveLiveStatus, LiveStatus.offline);
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
        _expectParity(room, _result(known['includeMedia $media']), changed: _inroomRoom, reason: depth);
        expect(_sent(setup.http.requests), [
          ..._legacyRequests(cold[depth]),
          ..._legacyRequests(warm[depth]),
        ], reason: depth);
        final data = room.data! as SixRoomRoomData;
        expect((data.userId, data.state, data.restriction), (_liveUid, SixRoomState.live, LiveRestriction.none));
        expect(data.stream != null, media, reason: '$depth: the stream only with the media (3.x)');
        // E05.4 c5: the recording detail (multi-view) has them too.
        expect(room.danmakuData, media ? isA<SixRoomDanmakuArgs>() : isNull, reason: depth);
        expect((room.startedAt, room.restriction), (_liveStart, LiveRestriction.none), reason: 'M2.1');
        expect(room.title, '但行好事，莫问前程', reason: '31-2');
        expect(room.avatar, isNot(room.cover), reason: '31-1');
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
        await setup.site.getDirectoryPage(category: _all, cancel: CancelToken());
        setup.http.requests.clear();
        final result = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          'getRoomDetailForRecording' => setup.site.getRoomDetailForRecording(roomId: _live),
          _ => setup.site.getLiveStatus(roomId: _live),
        };
        if (result is LiveRoom) {
          _expectParity(result, _result(legacy[depth]), changed: _inroomAfterCard, reason: depth);
          expect(result.avatar, isNot(result.cover), reason: "the broadcaster's avatar");
          expect(result.popularity, '23444', reason: "the card's, the same broadcast still live (31-5)");
        } else {
          expect(result, _result(legacy[depth]));
        }
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: depth);
      }
      final setup = _setup([..._home, ..._liveRoom]);
      await setup.site.getDirectoryPage(category: _all, cancel: CancelToken());
      final link = await setup.site.getRoomDetail(roomId: 'https://v.6.cn/$_live?from=home');
      _expectParity(link, _result(_legacy('S05-inroom-live')['getRoomDetail(link)']), changed: _inroomAfterCard);
      expect(link.roomId, _live);
      await setup.site.getRoomDetail(roomId: _live);
      final card = (await setup.site.getDirectoryPage(category: _all, cancel: CancelToken())).rooms.first;
      _expectRooms([card], _result(_legacy('S05-inroom-live')['directory card after the room']), changed: _notice);
      expect(card.followers, '425628', reason: "the room's followers stay on the card (3.x)");
    });

    test("a room seen on a mobile list is read with one request; once ended, without the card's numbers", () async {
      final http = _Scripted((request) {
        if (request.method == 'GET') return _response(request, Fixture.load('sixroom', 'S06-list-u0-p1').body);
        final userId = Uri.splitQueryString(utf8.decode(request.body!))['ruid']!;
        return _response(request, _inroomAnswer('828957', userId));
      });
      final site = SixRoomSite(http);
      // 828957 is on the 歌区 list; its broadcaster is known from the card.
      final card = (await site.getCategoryRooms(_area('song', '歌区'))).firstWhere((room) => room.roomId == '828957');
      expect((card.popularity, card.startedAt != null), ('4012', true));
      http.requests.clear();
      final detail = await site.getRoomDetailForRefresh(roomId: '828957');
      expect(http.requests.map((request) => request.method), ['POST']);
      expect(Uri.splitQueryString(utf8.decode(http.requests.single.body!))['ruid'], card.userId);
      expect((detail.liveStatus, detail.popularity, detail.startedAt), (LiveStatus.offline, '', null), reason: '31-5');
      expect(detail.area, '歌区', reason: "the card's area where the answer has none");
    });

    test("offline: 3.x's room cold and after the search", () async {
      final legacy = _legacy('S05-inroom-offline');
      final cold = legacy['cold'] as Map<String, dynamic>;
      final warm = legacy['after the search'] as Map<String, dynamic>;
      final setup = _setup(_offlineRoom);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      expect(_result(cold['getRoomDetail']), containsPair('throws', 'SixRoomException.schema'));
      _expectParity(room, _result(legacy['knownUserId']), changed: _inroomRoom);
      expect(_sent(setup.http.requests), [
        ..._legacyRequests(cold['getRoomDetail']),
        ..._legacyRequests(warm['getRoomDetail']),
      ]);
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect((room.startedAt, room.restriction), (null, LiveRestriction.none));
      expect(await _setup(_offlineRoom).site.getLiveStatus(roomId: _offline), isFalse);
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final searched = _setup([..._offlineRoom, 'S02-search']);
        await searched.site.searchRooms('诺');
        final detail = await switch (depth) {
          'getRoomDetail' => searched.site.getRoomDetail(roomId: _offline),
          'getRoomDetailForRefresh' => searched.site.getRoomDetailForRefresh(roomId: _offline),
          _ => searched.site.getRoomDetailForRecording(roomId: _offline),
        };
        _expectParity(detail, _result(warm[depth]), changed: _inroomAfterCard, reason: depth);
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

    test(
      'a private or black-screen broadcast is live and restricted (M2.1; 3.x: unknown); it cannot be played',
      () async {
        for (final (edit, restriction, reason) in <(void Function(Map<String, dynamic>), LiveRestriction, String)>[
          ((root) => _content(root)['isPriveRoom'] = 1, LiveRestriction.private, 'private'),
          ((root) => _content(root)['blackScreenInfo'] = {'msg': '黑屏', 'endtm': 1}, LiveRestriction.unplayable, '黑屏'),
        ]) {
          final setup = _setup(_liveRoom, extra: [_inroom(edit)]);
          final room = await setup.site.getRoomDetail(roomId: _live);
          expect(
            (room.effectiveLiveStatus, room.restriction, room.followGroup),
            (LiveStatus.live, restriction, FollowGroup.live),
          );
          expect(room.notice, '${SixRoomApi.restrictedNotice}\n${SixRoomApi.chatNotice}');
          expect(await setup.site.getLiveStatus(roomId: _live), isTrue, reason: '3.x: access');
          await expectLater(
            setup.site.getPlayQualities(detail: room),
            throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains(reason))),
          );
          await expectLater(
            setup.site.resolvePlayUrlsRaw(detail: room, quality: _source),
            throwsA(isA<StreamUnavailable>()),
          );
        }
      },
    );

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
        await site.getCategoryRooms(_all, page: page, pageSize: 100);
      }
      http.requests.clear();
      await site.getRoomDetailForRefresh(roomId: '${1000 + count - 1}');
      expect(http.requests.map((request) => request.method), ['POST'], reason: 'remembered');
      http.requests.clear();
      await site.getRoomDetailForRefresh(roomId: '1000');
      expect(http.requests.map((request) => request.method), ['GET', 'POST'], reason: 'forgotten: the room page');
    });

    test("a refresh after the broadcast ended keeps no card's popularity or start (31-5)", () async {
      final ended = _setup(
        _home,
        extra: [_inroom((root) => (_content(root)['liveinfo'] as Map<String, dynamic>).remove('id'))],
      );
      final card = (await ended.site.getDirectoryPage(category: _all)).rooms.firstWhere((room) => room.roomId == _live);
      expect((card.popularity, card.startedAt), ('23444', _liveStart));
      final room = await ended.site.getRoomDetailForRefresh(roomId: _live);
      expect((room.liveStatus, room.popularity, room.watching, room.startedAt), (LiveStatus.offline, '', '', null));
      expect(room.audienceMetricType, AudienceMetricType.unknown);
      expect((room.followers, room.avatar, room.cover.isNotEmpty), ('425628', card.avatar, true));
      // The card listed next keeps its own numbers.
      final again = (await ended.site.getDirectoryPage(page: 2, category: _all)).rooms;
      expect(again.every((room) => room.popularity.isNotEmpty), isTrue);
    });
  });

  group('streams', () {
    test("an entered live room: 3.x's quality and URL, now a line; recovery asks the room again", () async {
      final legacy =
          (_legacy('S05-inroom-live')['after the directory'] as Map<String, dynamic>)['getRoomDetail → streams']
              as Map<String, dynamic>;
      final setup = _setup([..._home, ..._liveRoom]);
      await setup.site.getDirectoryPage(category: _all, cancel: CancelToken());
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
      final setup = _setup([..._liveRoom, ..._offlineRoom, ..._lists]);
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
