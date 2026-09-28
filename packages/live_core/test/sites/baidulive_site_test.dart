// BaiduLiveSite over the recorded Baidu Live responses (ReplayHttp) and a
// few synthetic ones: the requests (URL, form, signature, headers,
// redirects) and their counts, compared with the requests 3.x made
// (expected.json), the catalog and the feed sessions of the directory, the
// room-id search, room details for entry, refresh and recording, what
// earlier cards fill in, streams with their lines and recovery,
// cancellation, links through the link parser and the error mapping. Ports
// the orchestration parts of 3.x's baidu_live_site_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/baidulive';

/// The device id the samples were recorded with.
const _device = 'pc-purelivefixturedevice01';

const _liveRoom = '11560887291';
const _endedRoom = '11583715413';
const _missingRoom = '99999999999';

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

typedef _Setup = ({BaiduLiveSite site, ReplayHttp http});

/// A site over [samples] with the recorded device id and a clock at
/// [now]. The clock values (`timestamp`, `_`) and the signature are left
/// out of matching; the tests check what is sent.
_Setup _setup(List<String> samples, {DateTime Function()? now}) {
  final http = ReplayHttp(
    [for (final sample in samples) ReplaySample.load('$_root/$sample')],
    ignoredQuery: const {'timestamp', 'sign', '_'},
  );
  return (site: BaiduLiveSite(http, deviceId: _device, now: now ?? () => _captured('S02-room-live')), http: http);
}

DateTime _captured(String sample) => Fixture.load('baidulive', sample).capturedAt;

Map<String, dynamic> _meta(String sample) => Fixture.load('baidulive', sample).meta;

/// The recorded request of [sample].
Map<String, dynamic> _recorded(String sample) => _meta(sample)['request'] as Map<String, dynamic>;

/// The clock of a recorded feed request.
DateTime _feedClock(String sample) {
  final form = Uri.splitQueryString(_recorded(sample)['body'] as String);
  return DateTime.fromMillisecondsSinceEpoch(int.parse(form['timestamp']!) * 1000);
}

/// The clock of a recorded room request.
DateTime _roomClock(String sample) =>
    DateTime.fromMillisecondsSinceEpoch(int.parse(Uri.parse(_recorded(sample)['url'] as String).queryParameters['_']!));

/// [recorded] (a form or URL) with its empty fields written bare, as 3.x's
/// Dart `Uri` encoding wrote them (`sid&`; the recorder wrote `sid=&`).
String _bare(String recorded) {
  final query = recorded.indexOf('?');
  final head = query < 0 ? '' : recorded.substring(0, query + 1);
  final fields = (query < 0 ? recorded : recorded.substring(query + 1)).split('&');
  return head + fields.map((field) => field.endsWith('=') ? field.substring(0, field.length - 1) : field).join('&');
}

Map<String, dynamic> _legacy(String sample) => Fixture.load('baidulive', sample).legacy as Map<String, dynamic>;

Map<String, dynamic> _outcome(String sample, String key) => _legacy(sample)[key] as Map<String, dynamic>;

Object? _legacyValue(String sample, String key) => _outcome(sample, key)['value'];

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

/// A request as the legacy harness recorded it: the device id, clocks and
/// signature as placeholders, header names as 3.x wrote them (compared
/// without case).
Map<String, Object?> _described(LiveRequest request) {
  final url = request.url;
  String data(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    (decoded['data'] as Map<String, dynamic>)['device_id'] = '<device>';
    return jsonEncode(decoded);
  }

  final form = request.method == 'POST' ? Uri.splitQueryString(utf8.decode(request.body!)) : null;
  return {
    'method': request.method,
    'url': '${url.scheme}://${url.host}${url.path}',
    if (url.queryParameters.isNotEmpty)
      'query': {
        for (final MapEntry(:key, :value) in url.queryParameters.entries)
          key: switch (key) {
            'uid' => '<device>',
            '_' => '<time>',
            'data' => data(value),
            _ => value,
          },
      },
    if (form != null)
      'form': {
        for (final MapEntry(:key, :value) in form.entries)
          key: switch (key) {
            'uid' => '<device>',
            'timestamp' => '<time>',
            'sign' => '<sign>',
            _ => value,
          },
      },
  };
}

/// Asserts that [requests] are the ones 3.x made for [outcome], in order:
/// method, URL, query and form (with the fields in 3.x's order) and 3.x's
/// API headers (names without case; a feed POST adds its content type).
void _expectLegacyRequests(List<LiveRequest> requests, Map<String, dynamic> outcome) {
  final legacy = (outcome['requests'] as List).cast<Map<String, dynamic>>();
  expect(requests.map(_described), [
    for (final request in legacy) {...request}..remove('headers'),
  ]);
  for (final (index, request) in requests.indexed) {
    final headers = (legacy[index]['headers'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    );
    expect({...request.headers}..remove('content-type'), headers, reason: 'headers of request $index');
    expect(request.followRedirects, isFalse);
    if (request.method == 'POST') {
      expect(request.headers['content-type'], 'application/x-www-form-urlencoded');
      final sent = utf8.decode(request.body!).split('&').map((field) => field.split('=').first);
      expect(sent, (legacy[index]['form'] as Map).keys, reason: 'field order');
    }
  }
}

void _expectParity(Map<String, Object?> actual, Map<String, dynamic> legacy, {String? reason}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (key == 'httpHeaders') continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String? reason}) {
  final expected = _maps(legacy);
  expect(rooms.map((room) => room.roomId), expected.map((room) => room['roomId']), reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(_projection(room), expected[index], reason: '${reason ?? ''}[$index]');
  }
}

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// A feed page of [ids] (live cards) in session [session] at [index].
String _feedAnswer(List<int> ids, {String session = '1790000000000', int index = 1, Object? tab}) => jsonEncode({
  'errno': 0,
  'data': {
    'feed': {
      'inner_errno': 0,
      'session_id': session,
      'refresh_index': index,
      'items': [
        for (final id in ids)
          {
            'room_id': id,
            'title': 'Room $id',
            'live_status': 1,
            'audience_count': 7,
            'host': {'uk': 'u$id', 'name': 'Anchor $id'},
          },
      ],
    },
    'tab': ?tab,
  },
});

List<int> _ids(int from, [int count = 10]) => [for (var index = 0; index < count; index++) 11500000000 + from + index];

/// The live sample's command with [changes] applied (and [video] to its
/// `video`).
String _liveAnswer({Map<String, Object?> changes = const {}, Map<String, Object?> video = const {}}) {
  final root = jsonDecode(Fixture.load('baidulive', 'S02-room-live').body) as Map<String, dynamic>;
  final command = (root['data'] as Map<String, dynamic>)['371'] as Map<String, dynamic>..addAll(changes);
  command['video'] = {...command['video'] as Map<String, dynamic>, ...video};
  return jsonEncode(root);
}

/// The room id a room command asks for.
String _askedRoom(LiveRequest request) {
  final data = jsonDecode(request.url.queryParameters['data']!) as Map<String, dynamic>;
  return (data['data'] as Map<String, dynamic>)['room_id'] as String;
}

void main() {
  group('the site', () {
    test('name, notice, capabilities and no danmaku (3.x)', () {
      final site = BaiduLiveSite(ReplayHttp(const []));
      expect(site.id, 'baidulive');
      expect(site.name, '百度直播');
      expect(site.directoryNoticeKey, 'baidulive_directory_scope');
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveDirectoryNotice>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isNot(isA<LiveSiteCursorDirectoryPager>()));
      expect(site, isNot(isA<LivePlayLeaseMetadata>()));
      expect(site.getDanmaku(), isA<EmptyDanmaku>());
    });

    test("3.x's device ids: one for the feed per adapter, a new one for every room command", () async {
      var clock = DateTime.utc(2026, 9, 28, 12);
      final http = _Scripted((request) {
        clock = clock.add(const Duration(seconds: 1));
        return _response(request, request.method == 'POST' ? _feedAnswer(_ids(0)) : _liveAnswer());
      });
      final site = BaiduLiveSite(http, now: () => clock);
      await site.getDirectoryPage();
      await site.getDirectoryPage(
        category: const LiveArea(platform: 'baidulive', areaType: 'official', areaId: 'news'),
      );
      await site.getRoomDetail(roomId: _liveRoom);
      await site.getRoomDetail(roomId: _liveRoom);
      final feeds = [
        for (final request in http.requests.where((request) => request.method == 'POST'))
          Uri.splitQueryString(utf8.decode(request.body!))['uid'],
      ];
      expect(feeds.toSet(), hasLength(1));
      expect(feeds.first, matches(RegExp(r'^pc-[0-9a-z]+purelivedev$')));
      final rooms = [
        for (final request in http.requests.where((request) => request.method == 'GET'))
          (
            request.url.queryParameters['uid'],
            ((jsonDecode(request.url.queryParameters['data']!) as Map<String, dynamic>)['data'] as Map)['device_id'],
          ),
      ];
      expect(rooms.map((room) => room.$1).toSet(), hasLength(2));
      for (final (uid, device) in rooms) {
        expect(uid, matches(RegExp(r'^pc-[0-9a-z]+baidulive$')));
        expect(device, uid, reason: 'data.device_id is the uid');
      }
    });
  });

  group('catalog', () {
    test("3.x's fixed channels without a request; the first feed page's tab list after it", () async {
      final (:site, :http) = _setup(['S01-feed-rec-p1'], now: () => _feedClock('S01-feed-rec-p1'));
      final before = await site.getCategories(1, 30);
      expect(before.single.children.map((area) => area.areaId), [
        'rec',
        'shopping',
        'finance',
        'health',
        'education',
        'news',
        'leisure',
      ]);
      expect(await site.getCategories(2, 30), isEmpty);
      expect(await site.getCategories(1, 0), isEmpty);
      expect(http.requests, isEmpty);
      await site.getDirectoryPage();
      final after = await site.getCategories(1, 30);
      final legacy = _maps(_legacyValue('S01-feed-rec-p1', 'getCategores(1) after the feed'));
      expect(after.single.children.map((area) => area.toJson()['areaName']), [
        for (final area in _maps(legacy.single['children'])) area['areaName'],
      ]);
    });

    test('a channel the platform adds is listed and requested; the list of the next first page replaces it', () async {
      var tabs = [
        {'type': 'rec', 'name': '推荐', 'channel_id': 570},
        {'type': 'auto', 'name': '汽车', 'channel_id': 700},
      ];
      final http = _Scripted(
        (request) => _response(request, _feedAnswer(_ids(0), tab: {'inner_errno': 0, 'items': tabs})),
      );
      final site = BaiduLiveSite(http);
      const auto = LiveArea(platform: 'baidulive', areaType: 'official', areaId: 'auto');
      expect(() => site.getDirectoryPage(category: auto), throwsArgumentError, reason: 'not in the fixed list');
      await site.getDirectoryPage();
      expect((await site.getCategories(1, 30)).single.children.map((area) => area.areaName), ['推荐', '汽车']);
      await site.getDirectoryPage(category: auto);
      final form = Uri.splitQueryString(utf8.decode(http.requests.last.body!));
      expect([form['tab'], form['channel_id']], ['auto', '700']);
      tabs = [
        {'type': 'rec', 'name': '推荐', 'channel_id': 570},
      ];
      await site.getDirectoryPage();
      expect((await site.getCategories(1, 30)).single.children.map((area) => area.areaId), ['rec']);
    });
  });

  group('directory', () {
    test("page 1: 3.x's signed POST (the recording's own signature) and 3.x's rooms", () async {
      final (:site, :http) = _setup(['S01-feed-rec-p1'], now: () => _feedClock('S01-feed-rec-p1'));
      final page = await site.getDirectoryPage();
      _expectLegacyRequests(http.requests, _outcome('S01-feed-rec-p1', 'getDirectoryPage(1)'));
      final request = http.requests.single;
      expect(request.url.toString(), _recorded('S01-feed-rec-p1')['url']);
      expect(
        utf8.decode(request.body!),
        _bare(_recorded('S01-feed-rec-p1')['body'] as String),
        reason: 'sign included',
      );
      expect(utf8.decode(request.body!), contains('&sid&'), reason: "3.x's encoding of an empty field");
      final legacy = _legacyValue('S01-feed-rec-p1', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      _expectRooms(page.rooms, legacy['rooms'], reason: 'p1');
      expect(page.rooms, hasLength(10));
      expect(page.hasMore, legacy['hasMore']);
      expect(page.page, 1);
      expect(page.rooms.every((room) => room.data == null && room.httpHeaders.isEmpty), isTrue);
    });

    test('page 2 continues the session: its session id and index, signed as recorded', () async {
      var clock = _feedClock('S01-feed-rec-p1');
      final (:site, :http) = _setup(['S01-feed-rec-p1', 'S01-feed-rec-p2'], now: () => clock);
      await site.getDirectoryPage();
      clock = _feedClock('S01-feed-rec-p2');
      final page = await site.getDirectoryPage(page: 2);
      final request = http.requests.last;
      _expectLegacyRequests([request], _outcome('S01-feed-rec-p2', 'getDirectoryPage(2)'));
      expect(
        utf8.decode(request.body!),
        _bare(_recorded('S01-feed-rec-p2')['body'] as String),
        reason: 'sign included',
      );
      final legacy = _legacyValue('S01-feed-rec-p2', 'getDirectoryPage(2)')! as Map<String, dynamic>;
      _expectRooms(page.rooms, legacy['rooms'], reason: 'p2');
      expect(page.hasMore, legacy['hasMore']);
      // 3.x: only the next page of the session; any other page is empty.
      final again = await site.getDirectoryPage(page: 2);
      expect(again.rooms, isEmpty);
      expect(again.hasMore, isFalse);
      expect(_legacyValue('S01-feed-rec-p2', 'getDirectoryPage(2) again'), {
        'page': 2,
        'hasMore': false,
        'rooms': <Object?>[],
      });
      expect(await site.getDirectoryPage(page: 5), isA<LiveDirectoryPage>().having((p) => p.rooms, 'rooms', isEmpty));
      expect(http.requests, hasLength(2));
    });

    test('pages 3.x answered without a request: below 1, not the next of the session', () async {
      final (:site, :http) = _setup(['S01-feed-rec-p1'], now: () => _feedClock('S01-feed-rec-p1'));
      final zero = await site.getDirectoryPage(page: 0);
      expect([zero.rooms, zero.hasMore], [isEmpty, isFalse]);
      final early = await site.getDirectoryPage(page: 2);
      expect([early.rooms, early.hasMore], [isEmpty, isFalse], reason: 'no session yet');
      await site.getDirectoryPage();
      final skipped = await site.getDirectoryPage(page: 3);
      expect(skipped.rooms, isEmpty);
      expect(_legacyValue('S01-feed-rec-p1', 'getDirectoryPage(3) after page 1'), {
        'page': 3,
        'hasMore': false,
        'rooms': <Object?>[],
      });
      expect(await site.getRecommendRooms(page: 0), isEmpty);
      expect(await site.getRecommendRooms(pageSize: 0), isEmpty);
      expect(http.requests, hasLength(1));
    });

    test('another platform or channel is a caller error without a request (3.x: identity)', () async {
      final (:site, :http) = _setup(const []);
      for (final area in [
        const LiveArea(platform: 'douyu', areaType: 'official', areaId: 'rec'),
        const LiveArea(platform: 'baidulive', areaType: 'category', areaId: 'rec'),
        const LiveArea(platform: 'baidulive', areaType: 'official', areaId: 'auto'),
      ]) {
        expect(() => site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
      }
      expect(
        _legacyValue('S01-feed-rec-p1', 'getDirectoryPage(1, another platform)'),
        containsPair('message', 'Baidu Live identity'),
      );
      expect(
        _legacyValue('S01-feed-rec-p1', 'getDirectoryPage(1, unknown area)'),
        containsPair('message', 'Baidu Live identity'),
      );
      expect(http.requests, isEmpty);
    });

    test('recommendations and channel rooms: the first pageSize rooms of the page (3.x)', () async {
      final (:site, :http) = _setup(['S01-feed-rec-p1'], now: () => _feedClock('S01-feed-rec-p1'));
      _expectRooms(await site.getRecommendRooms(), _legacyValue('S01-feed-rec-p1', 'getRecommendRooms(1)'));
      _expectRooms(
        await site.getRecommendRooms(pageSize: 4),
        _legacyValue('S01-feed-rec-p1', 'getRecommendRooms(1, pageSize 4)'),
      );
      final rec = (await site.getCategories(1, 30)).single.children.first;
      _expectRooms(await site.getCategoryRooms(rec), _legacyValue('S01-feed-rec-p1', 'getCategoryRooms(rec, 1)'));
      expect(http.requests, hasLength(3), reason: 'each page 1 starts a session');
    });

    test('page 2 of the recommendations, five rooms (3.x)', () async {
      var clock = _feedClock('S01-feed-rec-p1');
      final (:site, :http) = _setup(['S01-feed-rec-p1', 'S01-feed-rec-p2'], now: () => clock);
      await site.getRecommendRooms();
      clock = _feedClock('S01-feed-rec-p2');
      _expectRooms(
        await site.getRecommendRooms(page: 2, pageSize: 5),
        _legacyValue('S01-feed-rec-p2', 'getRecommendRooms(2, pageSize 5)'),
      );
      expect(http.requests, hasLength(2));
    });

    test('the shopping channel: its tab and channel id (S01-feed-shopping-p1)', () async {
      final (:site, :http) = _setup(['S01-feed-shopping-p1'], now: () => _feedClock('S01-feed-shopping-p1'));
      final shopping = (await site.getCategories(
        1,
        30,
      )).single.children.firstWhere((area) => area.areaId == 'shopping');
      final page = await site.getDirectoryPage(category: shopping);
      _expectLegacyRequests(http.requests, _outcome('S01-feed-shopping-p1', 'getDirectoryPage(1, shopping)'));
      expect(utf8.decode(http.requests.single.body!), _bare(_recorded('S01-feed-shopping-p1')['body'] as String));
      final legacy = _legacyValue('S01-feed-shopping-p1', 'getDirectoryPage(1, shopping)')! as Map<String, dynamic>;
      _expectRooms(page.rooms, legacy['rooms']);
      _expectRooms(
        await site.getCategoryRooms(shopping),
        _legacyValue('S01-feed-shopping-p1', 'getCategoryRooms(shopping, 1)'),
      );
    });

    test('a session shows a room once; it ends on a short page, a page of repeats or an index that stays', () async {
      final pages = <String>[];
      final http = _Scripted((request) => _response(request, pages.removeAt(0)));
      final site = BaiduLiveSite(http);
      pages.addAll([
        _feedAnswer(_ids(0)),
        _feedAnswer([..._ids(5, 5), ..._ids(20, 5)], index: 2),
      ]);
      await site.getDirectoryPage();
      final second = await site.getDirectoryPage(page: 2);
      expect(second.rooms.map((room) => room.roomId), [for (final id in _ids(20, 5)) '$id'], reason: 'repeats dropped');
      expect(second.hasMore, isTrue);
      final sent = Uri.splitQueryString(utf8.decode(http.requests.last.body!));
      expect(
        [sent['session_id'], sent['refresh_index'], sent['refresh_type'], sent['resource']],
        ['1790000000000', '2', '1', 'feed'],
      );
      for (final (answer, reason) in [
        (_feedAnswer(_ids(0), index: 2), 'nothing new'),
        (_feedAnswer(_ids(40)), 'the index stayed'),
        (_feedAnswer(_ids(40, 9), index: 2), 'nine items'),
      ]) {
        pages.addAll([_feedAnswer(_ids(0)), answer]);
        await site.getDirectoryPage();
        final page = await site.getDirectoryPage(page: 2);
        expect(page.hasMore, isFalse, reason: reason);
        final after = await site.getDirectoryPage(page: 3);
        expect(after.rooms, isEmpty, reason: '$reason: the session ended');
      }
    });

    test('each channel keeps its own session; the recommendations are the first channel', () async {
      final http = _Scripted((request) {
        final form = Uri.splitQueryString(utf8.decode(request.body!));
        final base = form['tab'] == 'rec' ? 0 : 100;
        return _response(
          request,
          _feedAnswer(_ids(base + int.parse(form['refresh_index']!) * 10), index: int.parse(form['refresh_index']!)),
        );
      });
      final site = BaiduLiveSite(http);
      const news = LiveArea(platform: 'baidulive', areaType: 'official', areaId: 'news');
      await site.getDirectoryPage();
      await site.getDirectoryPage(category: news);
      final rec = await site.getDirectoryPage(page: 2);
      final newsTwo = await site.getDirectoryPage(page: 2, category: news);
      expect(rec.rooms.first.roomId, '${_ids(20).first}');
      expect(newsTwo.rooms.first.roomId, '${_ids(120).first}');
    });

    test('a failed page keeps the session: the same page can be asked again', () async {
      var fail = false;
      final http = _Scripted((request) {
        if (fail) return _response(request, '', status: 502);
        final index = int.parse(Uri.splitQueryString(utf8.decode(request.body!))['refresh_index']!);
        return _response(request, _feedAnswer(_ids(index * 10), index: index));
      });
      final site = BaiduLiveSite(http);
      await site.getDirectoryPage();
      fail = true;
      await expectLater(site.getDirectoryPage(page: 2), throwsA(isA<NetworkFailure>()));
      fail = false;
      final retried = await site.getDirectoryPage(page: 2);
      expect(retried.rooms, hasLength(10));
      expect(Uri.splitQueryString(utf8.decode(http.requests.last.body!))['refresh_index'], '2');
    });

    test('cancellation: before the request, or while it runs', () async {
      final (:site, :http) = _setup(['S01-feed-rec-p1'], now: () => _feedClock('S01-feed-rec-p1'));
      final cancel = CancelToken()..cancel();
      await expectLater(site.getDirectoryPage(cancel: cancel), _cancelled);
      expect(http.requests, isEmpty);
      final running = CancelToken();
      final slow = _Scripted((request) async {
        running.cancel();
        return _response(request, _feedAnswer(_ids(0)));
      });
      await expectLater(BaiduLiveSite(slow).getDirectoryPage(cancel: running), _cancelled);
      expect(slow.requests.single.cancel, same(running));
    });
  });

  group('search', () {
    test("a room id or link finds the room (one command, 3.x's request); nothing else is searched", () async {
      final (:site, :http) = _setup(['S02-room-live']);
      final searches = _legacy('S02-room-live')['searchRooms'] as Map<String, dynamic>;
      expect(searches, hasLength(5));
      for (final MapEntry(:key, :value) in searches.entries) {
        http.requests.clear();
        final rooms = await site.searchRooms(key);
        _expectLegacyRequests(http.requests, value as Map<String, dynamic>);
        _expectRooms(rooms, value['value'], reason: key);
        expect(rooms.single.data, isNull, reason: 'no playback data');
      }
      http.requests.clear();
      expect(await site.searchRooms(_liveRoom, page: 2), isEmpty);
      expect(await site.searchRooms(_liveRoom, pageSize: 0), isEmpty);
      expect(await site.searchRooms('锦尚书画'), isEmpty);
      expect(_legacyValue('S01-feed-rec-p1', 'searchRooms(nickname)'), isEmpty);
      expect(await site.searchRooms('http://live.baidu.com/m/room/$_liveRoom'), isEmpty);
      expect(await site.searchRooms('https://live.baidu.com/search?room_id=$_liveRoom'), isEmpty);
      expect(http.requests, isEmpty);
    });

    test('an ended room is found, offline; a room that does not exist finds nothing', () async {
      final (:site, :http) = _setup(['S02-room-ended', 'S02-room-notfound']);
      for (final (sample, id) in [('S02-room-ended', _endedRoom), ('S02-room-notfound', _missingRoom)]) {
        final searches = _legacy(sample)['searchRooms'] as Map<String, dynamic>;
        for (final MapEntry(:key, :value) in searches.entries) {
          _expectRooms(await site.searchRooms(key), (value as Map<String, dynamic>)['value'], reason: key);
        }
        expect(searches.keys, contains(id));
      }
    });

    test('other failures are thrown; cancellation too', () async {
      final http = _Scripted((request) => _response(request, '', status: 503));
      await expectLater(BaiduLiveSite(http).searchRooms(_liveRoom), throwsA(isA<NetworkFailure>()));
      final cancel = CancelToken()..cancel();
      await expectLater(BaiduLiveSite(http).searchRoomsCancellable(_liveRoom, cancel: cancel), _cancelled);
      expect(http.requests, hasLength(1));
    });
  });

  group('rooms', () {
    test("entry, refresh and recording: one command each, 3.x's request and room", () async {
      final (:site, :http) = _setup(['S02-room-live'], now: () => _roomClock('S02-room-live'));
      for (final (key, call) in [
        ('getRoomDetail', () => site.getRoomDetail(roomId: _liveRoom)),
        ('getRoomDetailForRefresh', () => site.getRoomDetailForRefresh(roomId: _liveRoom)),
        ('getRoomDetailForRecording', () => site.getRoomDetailForRecording(roomId: _liveRoom)),
      ]) {
        http.requests.clear();
        final room = await call();
        _expectLegacyRequests(http.requests, _outcome('S02-room-live', key));
        expect(http.requests.single.url.toString(), _bare(_recorded('S02-room-live')['url'] as String));
        expect(http.requests.single.url.query, contains('&bd_vid&'), reason: "3.x's encoding of an empty field");
        _expectParity(_projection(room), _legacyValue('S02-room-live', key)! as Map<String, dynamic>, reason: key);
        expect(room.data, key == 'getRoomDetailForRefresh' ? isNull : isA<BaiduLiveRoom>(), reason: key);
        expect(room.httpHeaders, isEmpty);
      }
      expect(await site.getLiveStatus(roomId: _liveRoom), _legacyValue('S02-room-live', 'getLiveStatus'));
    });

    test('ended: offline and not live; a room that does not exist is NotFound (3.x: missing)', () async {
      final (:site, :http) = _setup(['S02-room-ended', 'S02-room-notfound']);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final room = await switch (key) {
          'getRoomDetail' => site.getRoomDetail(roomId: _endedRoom),
          'getRoomDetailForRefresh' => site.getRoomDetailForRefresh(roomId: _endedRoom),
          _ => site.getRoomDetailForRecording(roomId: _endedRoom),
        };
        _expectParity(_projection(room), _legacyValue('S02-room-ended', key)! as Map<String, dynamic>, reason: key);
        expect(room.liveStatus, LiveStatus.offline);
      }
      expect(await site.getLiveStatus(roomId: _endedRoom), isFalse);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording', 'getLiveStatus']) {
        expect(_legacyValue('S02-room-notfound', key), containsPair('message', 'Baidu Live missing'), reason: key);
      }
      await expectLater(site.getRoomDetail(roomId: _missingRoom), throwsA(isA<NotFound>()));
      await expectLater(site.getRoomDetailForRefresh(roomId: _missingRoom), throwsA(isA<NotFound>()));
      await expectLater(site.getLiveStatus(roomId: _missingRoom), throwsA(isA<NotFound>()));
    });

    test('a room link is a room id (3.x); anything else is NotFound without a request', () async {
      final (:site, :http) = _setup(['S02-room-live']);
      final room = await site.getRoomDetail(roomId: 'https://live.baidu.com/m/room/$_liveRoom');
      expect(room.roomId, _liveRoom);
      expect(_askedRoom(http.requests.single), _liveRoom);
      http.requests.clear();
      for (final id in ['12345', '012345678', 'abc', 'http://live.baidu.com/m/room/$_liveRoom']) {
        await expectLater(site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(http.requests, isEmpty);
    });

    test(
      'the live state: paid NeedsLogin, forbidden or banned StreamUnavailable, unknown ApiChanged (3.x: access)',
      () async {
        for (final (changes, matcher) in [
          ({'has_pay_service': '1'}, throwsA(isA<NeedsLogin>())),
          ({'ban_status': 1}, throwsA(isA<StreamUnavailable>())),
          ({'is_forbidden_url': 1, 'has_pay_service': 1}, throwsA(isA<StreamUnavailable>())),
          ({'status': '9'}, throwsA(isA<ApiChanged>())),
        ]) {
          final http = _Scripted((request) => _response(request, _liveAnswer(changes: changes)));
          await expectLater(BaiduLiveSite(http).getLiveStatus(roomId: _liveRoom), matcher, reason: '$changes');
        }
        for (final (status, live) in [('0', true), ('1', false), ('20', false), ('3', false)]) {
          final http = _Scripted((request) => _response(request, _liveAnswer(changes: {'status': status})));
          expect(await BaiduLiveSite(http).getLiveStatus(roomId: _liveRoom), live, reason: status);
        }
      },
    );

    test('a card seen before fills what the command leaves out; an ended room drops the card viewers', () async {
      final (:site, :http) = _setup(['S01-feed-rec-p1', 'S02-room-live'], now: () => _feedClock('S01-feed-rec-p1'));
      await site.getDirectoryPage();
      _expectParity(
        _projection(await site.getRoomDetail(roomId: _liveRoom)),
        _legacyValue('S02-room-live', 'getRoomDetail after the directory')! as Map<String, dynamic>,
      );
      final cards = _Scripted((request) {
        if (request.method == 'POST') return _response(request, _feedAnswer([11560887291, 11583715413]));
        return _askedRoom(request) == _liveRoom
            ? _response(
                request,
                _liveAnswer(
                  changes: {
                    'host': {'uk': ''},
                    'online_users': null,
                  },
                  video: {'title': ''},
                ),
              )
            : _response(request, Fixture.load('baidulive', 'S02-room-ended').body);
      });
      final listed = BaiduLiveSite(cards);
      await listed.getDirectoryPage();
      final live = await listed.getRoomDetailForRefresh(roomId: _liveRoom);
      expect(
        [live.userId, live.nick, live.title, live.onlineViewers],
        ['u11560887291', 'Anchor 11560887291', 'Room 11560887291', '7'],
      );
      final ended = await listed.getRoomDetailForRefresh(roomId: _endedRoom);
      expect(ended.onlineViewers, '', reason: '3.x showed the card viewers on the ended room');
      expect(ended.audienceMetricType, AudienceMetricType.unknown);
      expect(ended.nick, '霞浦贵人笑');
    });
  });

  group('streams', () {
    test("room entry brings 3.x's qualities and URLs: no further request; lines with the media headers", () async {
      final (:site, :http) = _setup(['S02-room-live']);
      final detail = await site.getRoomDetail(roomId: _liveRoom);
      http.requests.clear();
      final qualities = await site.getPlayQualities(detail: detail);
      expect([
        for (final quality in qualities) {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort},
      ], _legacyValue('S02-room-live', 'getPlayQualites'));
      final urls = _legacy('S02-room-live')['getPlayUrls'] as Map<String, dynamic>;
      final raw = _legacy('S02-room-live')['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in qualities) {
        expect(await site.getPlayUrls(detail: detail, quality: quality), (urls['${quality.id}'] as Map)['value']);
        final resolution = await site.resolvePlayUrls(detail: detail, quality: quality);
        final legacy = (raw['${quality.id}'] as Map<String, dynamic>)['value'] as Map<String, dynamic>;
        expect(resolution.urls, legacy['urls']);
        expect(resolution.appliedQualityData, legacy['appliedQualityData']);
        expect(
          resolution.lines.every((line) => line.headers['referer'] == 'https://live.baidu.com/m/room/$_liveRoom'),
          isTrue,
        );
      }
      expect(http.requests, isEmpty, reason: '3.x: the room entry snapshot');
    });

    test('recovery asks the room again and plays the same quality; a quality gone is StreamUnavailable', () async {
      final (:site, :http) = _setup(['S02-room-live']);
      final detail = await site.getRoomDetail(roomId: _liveRoom);
      final recovery = _legacy('S02-room-live')['resolvePlayUrlsForRecoveryRaw'] as Map<String, dynamic>;
      for (final quality in await site.getPlayQualities(detail: detail)) {
        http.requests.clear();
        final resolution = await site.resolvePlayUrlsForRecovery(detail: detail, quality: quality);
        final outcome = recovery['${quality.id}'] as Map<String, dynamic>;
        _expectLegacyRequests(http.requests, outcome);
        expect(resolution.urls, (outcome['value'] as Map<String, dynamic>)['urls']);
        expect(resolution.appliedQualityData, quality.id);
      }
      final changed = _Scripted(
        (request) => _response(request, _liveAnswer(video: {'live_hls_url': '', 'url_clarity_list': <Object?>[]})),
      );
      final other = BaiduLiveSite(changed);
      final entered = await other.getRoomDetail(roomId: _liveRoom);
      await expectLater(
        other.resolvePlayUrlsForRecovery(
          detail: entered,
          quality: const LivePlayQuality(quality: 'HLS 720P · AVC', id: 'hls:720:avc'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test(
      'a room without playback data (a card, a refreshed follow) asks once; offline says so without asking',
      () async {
        final (:site, :http) = _setup(['S02-room-live', 'S01-feed-rec-p1'], now: () => _feedClock('S01-feed-rec-p1'));
        final card = (await site.getDirectoryPage()).rooms.firstWhere((room) => room.roomId == _liveRoom);
        http.requests.clear();
        // 3.x refused a room without its snapshot (`identity`).
        expect(
          _legacyValue('S01-feed-rec-p1', 'getPlayQualites(card)'),
          containsPair('message', 'Baidu Live identity'),
        );
        expect(
          _legacyValue('S02-room-live', 'getPlayQualites(refreshed)'),
          containsPair('message', 'Baidu Live identity'),
        );
        final qualities = await site.getPlayQualities(detail: card);
        expect(qualities.map((quality) => quality.id), ['hls:720:avc', 'flv:0:avc']);
        expect(http.requests, hasLength(1));
        http.requests.clear();
        final offline = LiveRoom(platform: 'baidulive', roomId: _endedRoom, liveStatus: LiveStatus.offline);
        await expectLater(site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
        await expectLater(
          site.resolvePlayUrlsRaw(detail: offline, quality: qualities.first),
          throwsA(isA<StreamUnavailable>()),
        );
        expect(http.requests, isEmpty);
        expect(
          () => site.getPlayQualities(
            detail: LiveRoom(platform: 'douyu', roomId: _liveRoom),
          ),
          throwsArgumentError,
        );
      },
    );

    test('rooms that cannot be played are entered and say why when streamed', () async {
      final (:site, :http) = _setup(['S02-room-ended']);
      final ended = await site.getRoomDetail(roomId: _endedRoom);
      expect(_legacyValue('S02-room-ended', 'getPlayQualites'), isEmpty, reason: '3.x: an empty list');
      await expectLater(site.getPlayQualities(detail: ended), throwsA(isA<StreamUnavailable>()));
      for (final (changes, matcher) in [
        ({'has_pay_service': 1}, throwsA(isA<NeedsLogin>())),
        ({'is_forbidden_url': 1}, throwsA(isA<StreamUnavailable>())),
        ({'status': '9'}, throwsA(isA<StreamUnavailable>())),
      ]) {
        final http = _Scripted((request) => _response(request, _liveAnswer(changes: changes)));
        final restricted = BaiduLiveSite(http);
        final room = await restricted.getRoomDetail(roomId: _liveRoom);
        expect(room.liveStatus, LiveStatus.unknown, reason: '$changes');
        await expectLater(restricted.getPlayQualities(detail: room), matcher, reason: '$changes');
        expect(http.requests, hasLength(1), reason: 'the snapshot says why');
      }
      final noStream = _Scripted(
        (request) => _response(
          request,
          _liveAnswer(
            video: {
              'live_hls_url': '',
              'live_flv_url': '',
              'live_flv_url_origin': '',
              'live_hls_url_origin': '',
              'url_list': <Object?>[],
              'avc_url': '',
              'play_url': '',
            },
          ),
        ),
      );
      final live = await BaiduLiveSite(noStream).getRoomDetail(roomId: _liveRoom);
      expect(live.liveStatus, LiveStatus.live, reason: '3.x failed the entry');
      await expectLater(BaiduLiveSite(noStream).getPlayQualities(detail: live), throwsA(isA<StreamUnavailable>()));
    });

    test("the platform's current CDN plays when 3.x's hosts give nothing", () async {
      final http = _Scripted(
        (request) =>
            _response(request, _liveAnswer(video: {'live_hls_url': '', 'live_flv_url': '', 'live_flv_url_origin': ''})),
      );
      final site = BaiduLiveSite(http);
      final detail = await site.getRoomDetail(roomId: _liveRoom);
      final qualities = await site.getPlayQualities(detail: detail);
      expect(qualities.map((quality) => quality.quality), [
        'FLV 720P · AVC',
        'HLS 720P · AVC',
        'FLV 480P · AVC',
        'HLS 480P · AVC',
        'FLV 原始线路 · AVC',
        'HLS 原始线路 · AVC',
      ]);
      final lines = (await site.resolvePlayUrls(detail: detail, quality: qualities.first)).lines;
      expect(lines.map((line) => line.url), everyElement(startsWith('http://flv')));
      expect(lines.map((line) => line.format), everyElement(StreamFormat.flv));
    });
  });

  group('errors', () {
    test('transport failures are NetworkFailure; statuses are typed', () async {
      final failing = _Scripted((request) => throw const TransportFailure('baidulive', TransportReason.timeout));
      await expectLater(BaiduLiveSite(failing).getRoomDetail(roomId: _liveRoom), throwsA(isA<NetworkFailure>()));
      await expectLater(BaiduLiveSite(failing).getDirectoryPage(), throwsA(isA<NetworkFailure>()));
      final cancelled = _Scripted((request) => throw const TransportFailure('baidulive', TransportReason.cancelled));
      await expectLater(BaiduLiveSite(cancelled).getRoomDetail(roomId: _liveRoom), _cancelled);
      for (final (status, type) in [
        (400, isA<ApiChanged>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (451, isA<RegionBlocked>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '{}', status: status));
        await expectLater(BaiduLiveSite(http).getRoomDetail(roomId: _liveRoom), throwsA(type), reason: '$status');
        await expectLater(BaiduLiveSite(http).getDirectoryPage(), throwsA(type), reason: '$status');
      }
    });
  });

  group('links', () {
    LinkParser parser(LiveHttp http) => LinkParser(SiteRegistry({'baidulive': () => BaiduLiveSite(http)}), http);

    test('room pages, the PC player and share pages in a share text, without a request', () async {
      final http = ReplayHttp(const []);
      for (final (text, id) in [
        ('百度直播 https://live.baidu.com/m/room/11560887291。快来', '11560887291'),
        ('https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=11572411040&source=h5pre', '11572411040'),
        (
          '【百度直播】奇门排盘分析讲堂 https://live.baidu.com/m/media/multipage/liveshow/index/wpdwl?room_id=11560887291',
          '11560887291',
        ),
      ]) {
        expect(await parser(http).parse(text), RoomLink('baidulive', id), reason: text);
      }
      expect(parser(http).containsSupportedLink('百度 https://live.baidu.com/m/room/11572411040'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('other pages, hosts and http are not rooms (3.x); there are no short links', () async {
      final http = ReplayHttp(const []);
      for (final text in [
        'https://live.baidu.com/search?room_id=11572411040',
        'https://live.baidu.com.evil.test/m/room/11572411040',
        'http://live.baidu.com/m/room/11572411040',
        'https://live.baidu.com/',
      ]) {
        expect(await parser(http).parse(text), isNull, reason: text);
      }
      final site = BaiduLiveSite(http);
      expect(site.needsResolving('https://live.baidu.com/m/room/11572411040'), isFalse);
      expect(site.roomIdsInShareText('https://live.baidu.com/m/room/11572411040'), isEmpty);
      expect(http.requests, isEmpty);
    });
  });
}
