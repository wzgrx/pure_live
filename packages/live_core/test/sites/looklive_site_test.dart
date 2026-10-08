// LookLiveSite over the recorded LOOK Live answers (ReplayHttp) and a few
// synthetic ones: the weapi request, the merged and per-area lists, the
// search's look-ups and filter, rooms at every depth completed from the
// lists, the streams and their recovery, cancellation, the deadline, links
// and the error mapping. Requests are compared with the ones 3.x sent
// (expected.json records each as `POST <url> <plaintext payload>`); rooms
// with 3.x's projection but for the keys listed as `changed:` with the
// upgrade item (docs/specs/UPGRADES.md 32-x).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/looklive';

const _video = '21623631';
const _audio = '181408025';
const _offline = '325808387';
const _appOnly = '645235480';

/// Room numbers answered with S03-room-notfound's body (the sample itself
/// asked for room 1, which is not a room number).
const _unknown = ['2162', '99999999'];

const _samples = [
  'S01-video-p1',
  'S02-audio-p1',
  'S02-audio-p2',
  'S04-video-p2',
  'S03-room-video',
  'S03-room-audio',
  'S04-room-offline',
  'S04-room-apponly',
];

Map<String, dynamic> _legacy(String sample) => Fixture.load('looklive', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<String> _legacyRequests(Object? traced) => ((traced! as Map<String, dynamic>)['requests'] as List).cast<String>();

String _decrypt(String data, String key) =>
    utf8.decode(Aes128Cbc.decrypt(base64Decode(data), key: utf8.encode(key), iv: utf8.encode('0102030405060708')));

/// The plaintext payload of a request: the weapi form's two AES layers
/// undone.
String _payload(LiveRequest request) {
  final form = Uri.splitQueryString(utf8.decode(request.body!));
  return _decrypt(_decrypt(form['params']!, '0123456789abcdef'), '0CoJUm6Qyw8W8jud');
}

/// A request as the legacy harness wrote it.
String _line(LiveRequest request) => '${request.method} ${request.url} ${_payload(request)}';

List<String> _sent(Iterable<LiveRequest> requests) => [for (final request in requests) _line(request)];

/// An answer to the POST of [payload] to [path].
ReplaySample _answer(String path, Object? payload, String body, {int status = 200}) => ReplaySample(
  method: 'POST',
  url: Uri.parse('${LookLiveApi.apiOrigin}$path'),
  status: status,
  bytes: utf8.encode(body),
  form: LookLiveApi.envelope(payload),
);

ReplaySample _room(String roomId, String body, {int status = 200}) =>
    _answer(LookLiveApi.roomPath, LookLiveApi.roomPayload(roomId), body, status: status);

ReplaySample _list(LookLiveKind kind, int page, String body, {int status = 200}) =>
    _answer(LookLiveApi.listPath(kind), LookLiveApi.listPayload(page), body, status: status);

String _body(String sample) => Fixture.load('looklive', sample).body;

typedef _Setup = ({LookLiveSite site, ReplayHttp http});

/// The recorded samples and the not-found look-ups; [extra] answers first.
_Setup _setup({List<ReplaySample> extra = const []}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in _samples) ReplaySample.load('$_root/$name'),
    for (final id in _unknown) _room(id, _body('S03-room-notfound')),
  ]);
  return (site: LookLiveSite(http), http: http);
}

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
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('looklive', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('looklive', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// Changed on every room: the notices are in words for users (M4.U, the
/// unified rule on notices), and M5.28 shows LOOK chat, so the chat notice
/// no longer says it is missing.
const _notice = {'notice'};

/// Changed for an ended room after a list card of the same broadcast: the
/// card's heat and viewers are no longer taken (32-5).
const _audience = {'watching', 'audienceMetricType', 'popularity', 'onlineViewers'};

/// Asserts [room] equals 3.x's [legacy] projection on every key 3.x wrote,
/// except [changed]. 3.x wrote null where the immutable model writes ''.
void _expectParity(LiveRoom room, Object? legacy, {Set<String> changed = _notice, String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

void _expectRooms(List<LiveRoom> rooms, Object? legacy, {String reason = ''}) {
  final expected = legacy! as List;
  if (expected.isEmpty || expected.first is String) {
    expect(rooms.map((room) => room.roomId), expected, reason: reason);
    return;
  }
  expect(rooms.map((room) => room.roomId), [for (final room in expected) (room as Map)['roomId']], reason: reason);
  for (final (index, room) in rooms.indexed) {
    _expectParity(room, expected[index], reason: '$reason[$index]');
  }
}

void _expectPage(LiveDirectoryPage page, Object? legacy, {String reason = ''}) {
  final expected = legacy! as Map<String, dynamic>;
  _expectRooms(page.rooms, expected['rooms'] ?? expected['roomIds'], reason: reason);
  expect((page.page, page.hasMore), (expected['page'], expected['hasMore']), reason: reason);
}

String? _failure(Object? legacy) {
  if (legacy is! Map || legacy['throws'] != 'LookLiveException') return null;
  return (legacy['message']! as String).replaceFirst('LOOK Live ', '');
}

/// The `SiteError` of a 3.x failure kind at the site (JSON codes and shapes;
/// the HTTP statuses have their own test).
Matcher _typed(String kind) => throwsA(switch (kind) {
  'schema' || 'identity' || 'service' => isA<ApiChanged>(),
  'missing' => isA<NotFound>(),
  'access' => isA<RiskControl>(),
  'rateLimited' => isA<RateLimited>(),
  'transport' => isA<NetworkFailure>(),
  'mediaUnavailable' => isA<StreamUnavailable>(),
  _ => throw ArgumentError(kind),
});

/// Runs [call] against 3.x's traced [legacy]: the requests it sent (or
/// [requests]) and the value ([check]) or the typed failure ([failed]).
Future<void> _expectTraced<T>(
  ReplayHttp http,
  Future<T> Function() call,
  Object? legacy, {
  void Function(T value, Object? expected)? check,
  Matcher? failed,
  List<String>? requests,
  String reason = '',
}) async {
  final before = http.requests.length;
  final expected = _result(legacy);
  final kind = _failure(expected);
  if (failed != null) {
    await expectLater(call(), failed, reason: reason);
  } else if (kind != null) {
    await expectLater(call(), _typed(kind), reason: reason);
  } else {
    final value = await call();
    check == null ? expect(value, expected, reason: reason) : check(value, expected);
  }
  expect(_sent(http.requests.skip(before)), requests ?? _legacyRequests(legacy), reason: '$reason requests');
}

List<(Object?, Object?, Object?)> _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities) (quality.quality, quality.id, quality.sort),
];

List<(Object?, Object?, Object?)> _legacyQualities(Object? legacy) => [
  for (final quality in (legacy! as List).cast<Map<String, dynamic>>())
    (quality['quality'], quality['id'], quality['sort']),
];

LivePlayQuality _quality(String id) => LivePlayQuality(id: id, quality: id);

/// A list page of [ids] (live cards of [liveType], video by default, with
/// heat and viewers).
String _listBody(Iterable<String> ids, {bool hasMore = false, int liveType = 1}) => jsonEncode({
  'code': 200,
  'data': {
    'hasMore': hasMore,
    'itemList': [
      for (final id in ids)
        {
          'type': '1',
          'liveData': {
            'liveType': liveType,
            'liveId': int.parse(id) + 1,
            'liveTitle': 'title $id',
            'popularity': 7,
            'onlineNumber': 3,
            'userInfo': {'liveRoomNo': int.parse(id), 'userId': 1, 'nickname': 'nick $id'},
          },
        },
    ],
  },
});

/// A live room answer of [id] in the broadcast of [_listBody].
String _roomBody(String id) => jsonEncode({
  'code': 200,
  'data': {
    'liveStatus': 1,
    'roomInfo': {'id': int.parse(id) + 1, 'liveType': 1, 'title': 'title $id', 'liveUrl': null},
    'anchor': {'liveRoomNo': id, 'userId': 1, 'nickName': 'nick $id'},
  },
});

void main() {
  group('requests', () {
    test("3.x's weapi POST: headers, form, no redirects, 20 s, as looklive; the platform's names", () async {
      final setup = _setup();
      await setup.site.getDirectoryPage(category: LookLiveApi.videoArea);
      await setup.site.getRoomDetailForRefresh(roomId: _video);
      final [list, room] = setup.http.requests;
      for (final request in setup.http.requests) {
        expect(request.headers, LookLiveApi.requestHeaders);
        expect(request.followRedirects, isFalse);
        expect((request.site, request.method, request.timeout), ('looklive', 'POST', const Duration(seconds: 20)));
      }
      final meta = Fixture.load('looklive', 'S03-room-video').meta['request'] as Map<String, dynamic>;
      expect(utf8.decode(room.body!), meta['body'], reason: "the recorded form, byte for byte (3.x's encoding)");
      expect({
        for (final MapEntry(:key, :value) in (meta['headers'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value,
      }, room.headers);
      expect(_line(list), 'POST https://api.look.163.com/weapi/livestream/homepage/recommend {"offset":0,"limit":20}');
      expect(_line(room), 'POST https://api.look.163.com/weapi/livestream/room/get/v3 {"liveRoomNo":"21623631"}');
      expect((setup.site.id, setup.site.name), ('looklive', 'LOOK 直播'));
      expect(setup.site.directoryNoticeKey, 'looklive_directory_scope');
      expect(setup.site.deadline, const Duration(seconds: 20));
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        LookLiveSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: _video),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(LookLiveSite(_Failing(TransportReason.cancelled)).getRecommendRooms(), _cancelled);
      for (final (status, type) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (400, isA<NetworkFailure>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(LookLiveSite(http).getRoomDetail(roomId: _video), throwsA(type), reason: '$status');
        await expectLater(LookLiveSite(http).getDirectoryPage(), throwsA(type), reason: '$status');
      }
      final html = _Scripted((request) => _response(request, '<html></html>'));
      await expectLater(LookLiveSite(html).getRecommendRooms(), throwsA(isA<ApiChanged>()));
      await expectLater(LookLiveSite(html).getRoomDetailForRefresh(roomId: _video), throwsA(isA<ApiChanged>()));
    });

    test("3.x's statuses and bodies on the room and list requests (S03-room-notfound's cases)", () async {
      final legacy = _legacy('S03-room-notfound');
      for (final status in [401, 403, 404, 429, 500, 502, 503, 302, 400, 204]) {
        final setup = _setup(extra: [_room(_video, '', status: status)]);
        final calls = legacy['room status $status'] as Map<String, dynamic>;
        final kind = _failure(_result(calls['getRoomDetail']))!;
        final type = switch (kind) {
          'access' => isA<RiskControl>(),
          'missing' => isA<NotFound>(),
          'rateLimited' => isA<RateLimited>(),
          'service' || 'transport' => isA<NetworkFailure>(),
          _ => throw StateError(kind),
        };
        await _expectTraced(
          setup.http,
          () => setup.site.getRoomDetail(roomId: _video),
          calls['getRoomDetail'],
          failed: throwsA(type),
        );
        await _expectTraced(
          setup.http,
          () => setup.site.getRoomDetailForRefresh(roomId: _video),
          calls['getRoomDetailForRefresh'],
          failed: throwsA(type),
        );
        await _expectTraced(
          setup.http,
          () => setup.site.getLiveStatus(roomId: _video),
          calls['getLiveStatus'],
          failed: throwsA(type),
        );
        await _expectTraced(
          setup.http,
          () => setup.site.searchRooms(_video),
          calls['searchRooms'],
          failed: status == 404 ? null : throwsA(type),
          check: (rooms, expected) => expect(rooms, isEmpty, reason: 'a room the site does not know is no result'),
        );
      }
      for (final name in ['empty 200', 'not JSON', 'over 2 MiB', 'at 2 MiB']) {
        final body = switch (name) {
          'empty 200' => '',
          'not JSON' => '<html></html>',
          'over 2 MiB' => '{"code":200,"data":{}}${' ' * (2 * 1024 * 1024)}',
          _ => '${_body('S03-room-video')}${' ' * (2 * 1024 * 1024 - utf8.encode(_body('S03-room-video')).length)}',
        };
        final setup = _setup(extra: [_room(_video, body)]);
        await _expectTraced(
          setup.http,
          () => setup.site.getRoomDetailForRefresh(roomId: _video),
          legacy['room $name'],
          check: _expectParity,
          reason: name,
        );
      }
      for (final (name, status, body) in [('status 404', 404, ''), ('status 503', 503, ''), ('not JSON', 200, 'x')]) {
        final calls = legacy['video list $name'] as Map<String, dynamic>;
        final setup = _setup(extra: [_list(LookLiveKind.video, 1, body, status: status)]);
        final type = switch (status) {
          404 => isA<NotFound>(),
          503 => isA<NetworkFailure>(),
          _ => isA<ApiChanged>(),
        };
        await _expectTraced(setup.http, setup.site.getDirectoryPage, calls['getDirectoryPage'], failed: throwsA(type));
        await _expectTraced(
          setup.http,
          () => setup.site.getCategoryRooms(LookLiveApi.audioArea),
          calls['getCategoryRooms(audio)'],
          check: _expectRooms,
        );
        await _expectTraced(
          setup.http,
          () => setup.site.searchRooms('电台'),
          calls['searchRooms'],
          failed: throwsA(type),
        );
      }
    });

    test("one 20 s deadline per request (3.x's _post); the request is cancelled", () async {
      final http = _Scripted((request) => Completer<LiveResponse>().future);
      final site = LookLiveSite(http, deadline: const Duration(milliseconds: 30));
      await expectLater(site.getRoomDetail(roomId: _video), throwsA(isA<NetworkFailure>()));
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      expect(http.requests.single.timeout, const Duration(milliseconds: 30));
      await expectLater(site.getDirectoryPage(), throwsA(isA<NetworkFailure>()));
      expect(http.requests, hasLength(3), reason: 'both lists were asked');
      expect(http.requests.every((request) => request.cancel!.isCancelled), isTrue);
    });

    test("the caller's cancellation reaches the request and is reported as such", () async {
      final http = _Scripted((request) => Completer<LiveResponse>().future);
      final site = LookLiveSite(http);
      final token = CancelToken();
      final search = site.searchRoomsCancellable(_video, cancel: token);
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectLater(search, _cancelled);
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      await expectLater(site.searchRoomsCancellable('电台', cancel: token), _cancelled);
      await expectLater(site.getDirectoryPage(cancel: token), _cancelled);
      expect(http.requests, hasLength(1), reason: 'nothing is sent once cancelled');
      final token2 = CancelToken();
      final answered = _Scripted((request) {
        token2.cancel();
        return _response(request, _body('S01-video-p1'));
      });
      await expectLater(
        LookLiveSite(answered).getDirectoryPage(category: LookLiveApi.videoArea, cancel: token2),
        _cancelled,
        reason: 'an answer that arrives after the cancellation is dropped',
      );
    });
  });

  group('lists', () {
    test("the merged directory, page 1: 3.x's rooms and requests (video, then voice)", () async {
      final setup = _setup();
      final legacy = _legacy('S01-video-p1')['getDirectoryPage'] as Map<String, dynamic>;
      await _expectTraced(setup.http, setup.site.getDirectoryPage, legacy['page 1'], check: _expectPage);
      final page = await setup.site.getDirectoryPage();
      expect(page.rooms, hasLength(22));
      expect(page.rooms.take(3).map((room) => room.area), everyElement('视频直播'));
      expect(page.rooms.skip(3).map((room) => room.area), everyElement('语音直播'));
    });

    test('page 2: the ended video list is empty, the voice list goes on (3.x failed, difference 1)', () async {
      final setup = _setup();
      final legacy = _legacy('S01-video-p1')['getDirectoryPage'] as Map<String, dynamic>;
      expect(_failure(_result(legacy['page 2'])), 'schema', reason: 'S04-video-p2 answers itemList null');
      await _expectTraced(
        setup.http,
        () => setup.site.getDirectoryPage(page: 2),
        legacy['page 2 with an empty video page'],
        check: _expectPage,
        requests: _legacyRequests(legacy['page 2']),
      );
      expect((await setup.site.getDirectoryPage(page: 2)).hasMore, isTrue);
      final video2 = _legacy('S04-video-p2');
      expect(_failure(_result(video2['getDirectoryPage(page: 2)'])), 'schema');
      expect(_failure(_result(video2['getRecommendRooms(page: 2)'])), 'schema');
      expect(
        (await setup.site.getRecommendRooms(page: 2)).map((room) => room.roomId),
        (_result(legacy['page 2 with an empty video page'])! as Map)['roomIds'],
      );
      final videoPage2 = await setup.site.getDirectoryPage(page: 2, category: LookLiveApi.videoArea);
      expect(videoPage2.rooms, isEmpty);
      expect(videoPage2.hasMore, isFalse);
      expect(_failure(_result(legacy['video page 2'])), 'schema');
    });

    test('32-1: the merged pages no longer ask the ended video list; page 1 asks both again', () async {
      final setup = _setup();
      final legacy = _legacy('S01-video-p1')['getDirectoryPage'] as Map<String, dynamic>;
      await _expectTraced(setup.http, setup.site.getDirectoryPage, legacy['page 1'], check: _expectPage);
      // S01: the video list answered hasMore false on page 1.
      const audio2 =
          'POST https://api.look.163.com/weapi/livestream/listen/homepage/recommend/list '
          '{"offset":20,"limit":20}';
      await _expectTraced(
        setup.http,
        () => setup.site.getDirectoryPage(page: 2),
        legacy['page 2 with an empty video page'],
        check: _expectPage,
        requests: const [audio2],
      );
      expect(_legacyRequests(legacy['page 2']), hasLength(2), reason: '3.x asked both lists on every page');
      var sent = setup.http.requests.length;
      final recommended = await setup.site.getRecommendRooms(page: 2, pageSize: 5);
      expect(recommended, hasLength(5));
      expect(_sent(setup.http.requests.skip(sent)), [audio2], reason: 'the recommendations are the merged pages');
      sent = setup.http.requests.length;
      await setup.site.getDirectoryPage(page: 2, category: LookLiveApi.videoArea);
      expect(setup.http.requests, hasLength(sent + 1), reason: 'an area asks its own list, as in 3.x');
      sent = setup.http.requests.length;
      await setup.site.getDirectoryPage();
      expect(setup.http.requests, hasLength(sent + 2), reason: 'page 1 (pulling to refresh) asks both again');
    });

    test('32-1: both lists ended is an empty last page without a request; a list that grows again is asked', () async {
      final ended = <String, int>{'video': 1, 'audio': 2};
      final http = _Scripted((request) {
        final payload = jsonDecode(_payload(request)) as Map<String, dynamic>;
        final page = (payload['offset'] as int) ~/ LookLiveApi.pageSize + 1;
        final list = request.url.path == LookLiveApi.audioListPath ? 'audio' : 'video';
        final base = list == 'audio' ? 30000000 : 20000000;
        return _response(
          request,
          _listBody(['${base + page}'], hasMore: page < ended[list]!, liveType: list == 'audio' ? 2 : 1),
        );
      });
      final site = LookLiveSite(http);
      String sentList(LiveRequest request) => request.url.path == LookLiveApi.audioListPath ? 'audio' : 'video';
      final page1 = await site.getDirectoryPage();
      expect(page1.rooms.map((room) => room.roomId), ['20000001', '30000001']);
      expect(page1.hasMore, isTrue);
      final page2 = await site.getDirectoryPage(page: 2);
      expect(http.requests.skip(2).map(sentList), ['audio']);
      expect(page2.rooms.map((room) => room.roomId), ['30000002']);
      expect(page2.hasMore, isFalse);
      final page3 = await site.getDirectoryPage(page: 3);
      expect((page3.rooms.length, page3.hasMore), (0, false));
      expect(http.requests, hasLength(3), reason: 'both lists have ended');
      // The video list grows to two pages; pulling to refresh sees it.
      ended['video'] = 2;
      final again = await site.getDirectoryPage();
      expect(again.hasMore, isTrue);
      await site.getDirectoryPage(page: 2);
      expect(http.requests.skip(3).map(sentList), ['video', 'audio', 'video', 'audio']);
      await site.getDirectoryPage(page: 3);
      expect(http.requests, hasLength(7), reason: 'both ended on page 2');
    });

    test("the areas: 3.x's pages and requests; other areas, page 0 and a page past 10000 send nothing", () async {
      final setup = _setup();
      final legacy = _legacy('S01-video-p1')['getDirectoryPage'] as Map<String, dynamic>;
      for (final (name, area, page) in [
        ('video page 1', LookLiveApi.videoArea, 1),
        ('audio page 1', LookLiveApi.audioArea, 1),
        ('audio page 2', LookLiveApi.audioArea, 2),
      ]) {
        await _expectTraced(
          setup.http,
          () => setup.site.getDirectoryPage(page: page, category: area),
          legacy[name],
          check: _expectPage,
          reason: name,
        );
      }
      for (final (name, area) in [
        ('otherArea', const LiveArea(platform: 'looklive', areaType: 'official', areaId: 'other')),
        ('otherType', const LiveArea(platform: 'looklive', areaType: 'hot', areaId: 'video')),
        ('otherPlatform', const LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'video')),
      ]) {
        expect(_failure(_result(legacy[name])), 'identity');
        await _expectTraced(
          setup.http,
          () => setup.site.getDirectoryPage(category: area),
          legacy[name],
          failed: throwsArgumentError,
          reason: name,
        );
      }
      await _expectTraced(setup.http, () => setup.site.getDirectoryPage(page: 0), legacy['page 0'], check: _expectPage);
      await _expectTraced(
        setup.http,
        () => setup.site.getDirectoryPage(page: 10001),
        legacy['page 10001'],
        failed: throwsA(isA<RangeError>()),
      );
    });

    test('recommendations and area rooms: slices, sizes and pages below 1 give nothing (3.x)', () async {
      final legacy = _legacy('S01-video-p1');
      final recommend = legacy['getRecommendRooms'] as Map<String, dynamic>;
      for (final (page, size) in [(1, 30), (1, 1), (1, 10), (1, 100), (0, 30), (1, 0)]) {
        final setup = _setup();
        await _expectTraced(
          setup.http,
          () => setup.site.getRecommendRooms(page: page, pageSize: size),
          recommend['page $page size $size'],
          check: _expectRooms,
          reason: '$page $size',
        );
      }
      final areas = legacy['getCategoryRooms'] as Map<String, dynamic>;
      for (final (name, area, page, size) in [
        ('video page 1', LookLiveApi.videoArea, 1, 30),
        ('audio page 1', LookLiveApi.audioArea, 1, 30),
        ('audio page 2', LookLiveApi.audioArea, 2, 30),
        ('audio page 1 size 5', LookLiveApi.audioArea, 1, 5),
        ('audio page 0', LookLiveApi.audioArea, 0, 30),
      ]) {
        final setup = _setup();
        await _expectTraced(
          setup.http,
          () => setup.site.getCategoryRooms(area, page: page, pageSize: size),
          areas[name],
          check: _expectRooms,
          reason: name,
        );
      }
      final setup = _setup();
      await _expectTraced(
        setup.http,
        () => setup.site.getCategoryRooms(const LiveArea(platform: 'looklive', areaType: 'official', areaId: 'other')),
        areas['otherArea'],
        failed: throwsArgumentError,
      );
      expect(await setup.site.getCategoryRooms(const LiveArea(platform: 'x'), page: 0), isEmpty, reason: '3.x order');
    });

    test('the one category and its two areas, on page 1 with a size of at least 1; no request (3.x)', () async {
      final setup = _setup();
      final legacy = _legacy('S01-video-p1');
      final category = (await setup.site.getCategories(1, 30)).single;
      final expected = (_result(legacy['getCategores'])! as List).single as Map<String, dynamic>;
      expect((category.id, category.name), (expected['id'], expected['name']));
      expect([for (final area in category.children) area.areaName], ['视频直播', '语音直播']);
      expect([
        for (final area in (await setup.site.getCategories(1, 1)).single.children) area.areaId,
      ], _result(legacy['getCategores(pageSize: 1)']));
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(await setup.site.getCategories(1, 0), isEmpty);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('search', () {
    test("keywords: 3.x's results and requests; another site's link sends nothing (problem 9)", () async {
      final legacy = _legacy('S01-video-p1')['searchRoomsCancellable'] as Map<String, dynamic>;
      for (final MapEntry(key: keyword, value: traced) in legacy.entries) {
        final setup = _setup();
        final call = switch (keyword) {
          'Armin page 2' => () => setup.site.searchRooms('Armin', page: 2),
          '$_video page 2' => () => setup.site.searchRooms(_video, page: 2),
          '电台 size 1' => () => setup.site.searchRooms('电台', pageSize: 1),
          '电台 size 100' => () => setup.site.searchRooms('电台', pageSize: 100),
          '电台 size 101' => () => setup.site.searchRooms('电台', pageSize: 101),
          '电台 size 0' => () => setup.site.searchRooms('电台', pageSize: 0),
          'Armin without a token' => () => setup.site.searchRooms('Armin'),
          _ => () => setup.site.searchRoomsCancellable(keyword, cancel: CancelToken()),
        };
        final otherSite = keyword.startsWith('https://example.com');
        await _expectTraced(
          setup.http,
          call,
          traced,
          check: (rooms, expected) => _expectRooms(rooms, expected, reason: keyword),
          requests: otherSite ? const [] : null,
          reason: keyword,
        );
        if (otherSite) expect(_result(traced), isEmpty, reason: '3.x filtered the lists with it, never matching');
      }
    });

    test('a look-up error other than not-found is reported (3.x)', () async {
      final setup = _setup(extra: [_room(_video, '', status: 403)]);
      await expectLater(setup.site.searchRooms(_video), throwsA(isA<RiskControl>()));
      await expectLater(setup.site.searchRooms('https://look.163.com/live?id=$_video'), throwsA(isA<RiskControl>()));
    });
  });

  group('rooms', () {
    for (final (sample, roomId) in [
      ('S03-room-video', _video),
      ('S03-room-audio', _audio),
      ('S04-room-offline', _offline),
      ('S04-room-apponly', _appOnly),
      ('S03-room-notfound', '99999999'),
    ]) {
      test('$sample: every depth, the live status, qualities, lines and recovery against 3.x', () async {
        final legacy = _legacy(sample)['recorded'] as Map<String, dynamic>;
        var setup = _setup();
        for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          await _expectTraced(
            setup.http,
            () => switch (depth) {
              'getRoomDetail' => setup.site.getRoomDetail(roomId: roomId),
              'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: roomId),
              _ => setup.site.getRoomDetailForRecording(roomId: roomId),
            },
            legacy[depth],
            check: _expectParity,
            reason: depth,
          );
        }
        await _expectTraced(setup.http, () => setup.site.getLiveStatus(roomId: roomId), legacy['getLiveStatus']);
        await _expectTraced(
          setup.http,
          () => setup.site.getRoomDetailForRefresh(roomId: 'https://look.163.com/live?id=$roomId'),
          legacy['room link as id'],
          check: _expectParity,
        );
        for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          setup = _setup();
          final LiveRoom detail;
          try {
            detail = await switch (depth) {
              'getRoomDetail' => setup.site.getRoomDetail(roomId: roomId),
              'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: roomId),
              _ => setup.site.getRoomDetailForRecording(roomId: roomId),
            };
          } on SiteError {
            expect(legacy.keys.where((key) => key.startsWith('$depth →')), isEmpty);
            continue;
          }
          final data = detail.data;
          final error = data is LookLiveRoom ? data.streamError : null;
          // Changed: a refreshed room (no data), an offline one (3.x: no
          // qualities) or one without streams is StreamUnavailable before
          // any request; another quality is a caller error, also before the
          // recovery's request (3.x: identity, [] or mediaUnavailable).
          final playable = data is LookLiveRoom && error == null && !detail.isExplicitlyOfflineNow;
          final unavailable = throwsA(isA<StreamUnavailable>());
          await _expectTraced(
            setup.http,
            () => setup.site.getPlayQualities(detail: detail),
            legacy['$depth → getPlayQualites'],
            check: (qualities, expected) => expect(_qualities(qualities), _legacyQualities(expected)),
            failed: playable ? null : unavailable,
            reason: '$depth qualities',
          );
          for (final id in [LookLiveApi.hlsId, LookLiveApi.flvId, 'auto']) {
            await _expectTraced(
              setup.http,
              () => setup.site.resolvePlayUrlsRaw(detail: detail, quality: _quality(id)),
              legacy['$depth → resolvePlayUrlsRaw($id)'],
              check: (resolution, expected) {
                final map = expected! as Map<String, dynamic>;
                expect(resolution.urls, map['urls']);
                expect(resolution.appliedQualityData, map['appliedQualityData']);
                // Changed (32-3): the web's media headers (3.x sent none).
                expect(resolution.lines.single.headers, LookLiveApi.mediaHeaders(roomId));
              },
              failed: !playable ? unavailable : (id == 'auto' ? throwsArgumentError : null),
              reason: '$depth $id',
            );
          }
          for (final id in [LookLiveApi.flvId, 'auto']) {
            final traced = legacy['$depth → resolvePlayUrlsForRecoveryRaw($id)'];
            await _expectTraced(
              setup.http,
              () => setup.site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: _quality(id)),
              traced,
              check: (resolution, expected) {
                final map = expected! as Map<String, dynamic>;
                expect(resolution.urls, map['urls']);
                expect(resolution.appliedQualityData, map['appliedQualityData']);
              },
              failed: !playable ? unavailable : (id == 'auto' ? throwsArgumentError : null),
              requests: playable && id != 'auto' ? null : const [],
              reason: '$depth recovery $id',
            );
          }
          await _expectTraced(
            setup.http,
            () => setup.site.getPlayUrls(detail: detail, quality: _quality(LookLiveApi.hlsId)),
            legacy['$depth → getPlayUrls(hls:source)'],
            failed: playable ? null : unavailable,
            reason: '$depth getPlayUrls',
          );
        }
      });
    }

    test('the video room: lines with format, host and media headers, no lease; one request per recovery', () async {
      final setup = _setup();
      final detail = await setup.site.getRoomDetail(roomId: _video);
      expect(detail.data, isA<LookLiveRoom>());
      expect(await setup.site.getPlayQualities(detail: detail), [LookLiveApi.hlsQuality, LookLiveApi.flvQuality]);
      final hls = await setup.site.resolvePlayUrls(detail: detail, quality: LookLiveApi.hlsQuality);
      final line = hls.lines.single;
      expect(
        (line.format, line.lineId, line.lease, line.codec),
        (StreamFormat.hls, 'pull0583d674.live.126.net', null, null),
      );
      // Changed (32-3): 3.x's player had no LOOK branch and sent none.
      expect(line.headers, LookLiveApi.mediaHeaders(_video));
      expect(detail.httpHeaders, LookLiveApi.mediaHeaders(_video), reason: "kept in the room's JSON as in 3.x");
      final flv = await setup.site.resolvePlayUrls(detail: detail, quality: LookLiveApi.flvQuality);
      expect(flv.lines.single.format, StreamFormat.flv);
      expect(setup.http.requests, hasLength(1), reason: 'the lines come from the room entry');
      await setup.site.resolvePlayUrlsForRecovery(detail: detail, quality: LookLiveApi.hlsQuality);
      expect(setup.http.requests, hasLength(2), reason: 'recovery asks the room again (REG-LEASE-005)');
    });

    test('invalid room ids are NotFound without a request (3.x: identity)', () async {
      final legacy = _legacy('S03-room-video')['invalid ids'] as Map<String, dynamic>;
      final setup = _setup();
      for (final MapEntry(key: id, value: traced) in legacy.entries) {
        expect(_failure(_result(traced)), 'identity', reason: id);
        await _expectTraced(
          setup.http,
          () => setup.site.getRoomDetail(roomId: id),
          traced,
          failed: throwsA(isA<NotFound>()),
          reason: id,
        );
      }
    });

    test('the live status: banned is false (32-2), an unknown state ApiChanged (3.x: access)', () async {
      String edited(Object? status) => _body('S03-room-video').replaceFirst('"liveStatus": 1', '"liveStatus": $status');
      for (final (status, live, liveStatus) in <(Object?, bool?, LiveStatus)>[
        (-10, false, LiveStatus.banned),
        (-4, false, LiveStatus.banned),
        (-2, false, LiveStatus.offline),
        (2, null, LiveStatus.unknown),
        ('null', null, LiveStatus.unknown),
      ]) {
        final setup = _setup(extra: [_room(_video, edited(status))]);
        if (live == null) {
          await expectLater(setup.site.getLiveStatus(roomId: _video), throwsA(isA<ApiChanged>()), reason: '$status');
        } else {
          expect(await setup.site.getLiveStatus(roomId: _video), live, reason: '$status');
        }
        final room = await setup.site.getRoomDetail(roomId: _video);
        expect(room.liveStatus, liveStatus, reason: '$status');
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
        expect(setup.http.requests, hasLength(2), reason: 'playing asks nothing');
      }
      final ended = _setup();
      expect(await ended.site.getLiveStatus(roomId: _offline), isFalse);
      expect(await ended.site.getLiveStatus(roomId: _appOnly), isTrue, reason: 'live, only not on the web');
    });

    test('the room says its start and restriction at every depth (M2.1); app-only is live, grouped live', () async {
      final setup = _setup();
      for (final call in [
        () => setup.site.getRoomDetail(roomId: _appOnly),
        () => setup.site.getRoomDetailForRefresh(roomId: _appOnly),
        () => setup.site.getRoomDetailForRecording(roomId: _appOnly),
      ]) {
        final room = await call();
        expect(
          (room.liveStatus, room.restriction, room.followGroup),
          (LiveStatus.live, LiveRestriction.appOnly, FollowGroup.live),
        );
        expect(room.startedAt, DateTime.utc(2026, 8, 18, 18, 4, 34, 614));
      }
      final entry = await setup.site.getRoomDetail(roomId: _appOnly);
      await expectLater(
        setup.site.getPlayQualities(detail: entry),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('LOOK app only'))),
      );
      final video = await setup.site.getRoomDetailForRefresh(roomId: _video);
      expect((video.restriction, video.startedAt), (LiveRestriction.none, DateTime.utc(2026, 8, 26, 8, 33, 20, 612)));
      final ended = await setup.site.getRoomDetailForRefresh(roomId: _offline);
      expect((ended.restriction, ended.startedAt), (LiveRestriction.none, null));
      final card = (await setup.site.getCategoryRooms(LookLiveApi.audioArea, page: 2)).first;
      expect((card.restriction, card.startedAt), (null, null), reason: 'a card does not tell tickets or the start');
    });

    test('the lists complete rooms of the same broadcast: heat and viewers (3.x)', () async {
      final legacy = _legacy('S01-video-p1')['known'] as Map<String, dynamic>;
      var setup = _setup();
      await _expectTraced(
        setup.http,
        () => setup.site.getRoomDetailForRefresh(roomId: _video),
        legacy['getRoomDetailForRefresh before the list'],
        check: _expectParity,
      );
      await _expectTraced(
        setup.http,
        setup.site.getDirectoryPage,
        legacy['getDirectoryPage 1'],
        check: (page, expected) => expect(page.rooms, hasLength(expected! as int)),
      );
      for (final (name, call) in [
        ('getRoomDetailForRefresh after the list', () => setup.site.getRoomDetailForRefresh(roomId: _video)),
        ('getRoomDetail after the list', () => setup.site.getRoomDetail(roomId: _video)),
      ]) {
        await _expectTraced(setup.http, call, legacy[name], check: _expectParity, reason: name);
      }
      final after = await setup.site.getRoomDetailForRefresh(roomId: _video);
      expect((after.effectiveOnlineViewers, after.effectivePopularity), ('1', '440'));
      await _expectTraced(
        setup.http,
        () => setup.site.searchRooms(_video),
        legacy['searchRooms after the list'],
        check: _expectRooms,
      );
      setup = _setup();
      await setup.site.getRoomDetail(roomId: _video);
      await _expectTraced(
        setup.http,
        setup.site.getDirectoryPage,
        legacy['getDirectoryPage 1 after the room'],
        check: (page, expected) => _expectParity(page.rooms.first, expected),
      );
      setup = _setup();
      await setup.site.searchRooms('Armin');
      await _expectTraced(
        setup.http,
        () => setup.site.getRoomDetailForRefresh(roomId: _video),
        legacy['getRoomDetailForRefresh after a search'],
        check: _expectParity,
      );
      final room = _legacy('S03-room-video')['after the list'] as Map<String, dynamic>;
      setup = _setup();
      await setup.site.getDirectoryPage();
      await _expectTraced(
        setup.http,
        () => setup.site.getRoomDetail(roomId: _video),
        room['getRoomDetail'],
        check: _expectParity,
      );
      await _expectTraced(setup.http, () => setup.site.getLiveStatus(roomId: _video), room['getLiveStatus']);
    });

    test('voice page 2 completes the voice room; the ended room no longer shows its last heat (32-5)', () async {
      for (final (sample, roomId, names) in [
        ('S03-room-audio', _audio, ['getRoomDetail', 'getRoomDetailForRefresh']),
        ('S04-room-offline', _offline, ['getRoomDetailForRefresh', 'getRoomDetail', 'getLiveStatus']),
      ]) {
        final legacy = _legacy(sample)['after audio page 2'] as Map<String, dynamic>;
        final setup = _setup();
        await setup.site.getCategoryRooms(LookLiveApi.audioArea, page: 2);
        // Changed (32-5): the ended room no longer takes the card's heat
        // and viewers.
        final changed = {..._notice, if (sample == 'S04-room-offline') ..._audience};
        for (final name in names) {
          await _expectTraced<Object?>(
            setup.http,
            () => switch (name) {
              'getRoomDetail' => setup.site.getRoomDetail(roomId: roomId),
              'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: roomId),
              _ => setup.site.getLiveStatus(roomId: roomId),
            },
            legacy[name],
            check: (value, expected) =>
                value is LiveRoom ? _expectParity(value, expected, changed: changed) : expect(value, expected),
            reason: '$sample $name',
          );
        }
      }
      final legacy = _legacy('S04-room-offline')['after audio page 2'] as Map<String, dynamic>;
      final v3 = _result(legacy['getRoomDetailForRefresh'])! as Map<String, dynamic>;
      expect((v3['popularity'], v3['onlineViewers']), ('824', '8'), reason: "3.x showed the last broadcast's heat");
      final setup = _setup();
      await setup.site.getCategoryRooms(LookLiveApi.audioArea, page: 2);
      final ended = await setup.site.getRoomDetailForRefresh(roomId: _offline);
      expect(
        (ended.liveStatus, ended.effectivePopularity, ended.effectiveOnlineViewers, ended.watching),
        (LiveStatus.offline, '', '', ''),
      );
      final live = await setup.site.getRoomDetailForRefresh(roomId: _audio);
      expect(live.liveStatus, LiveStatus.live);
      expect(live.effectiveOnlineViewers, isNotEmpty, reason: 'the live room still takes its card');
    });

    test('a live answer without streams plays the list card of the same broadcast (3.x); type 50 does not', () async {
      String edited(String streamType) =>
          _body('S03-room-video')
              .replaceFirst(RegExp(r'"liveUrl": \{[^}]*\}'), '"liveUrl": null')
              .replaceFirst('"liveStreamType": 1', '"liveStreamType": $streamType');
      final legacy = _legacy('S03-room-video')['variants'] as Map<String, dynamic>;
      for (final (streamType, name) in [
        ('1', 'liveUrl null'),
        ('null', 'liveStreamType missing without liveUrl'),
        ('50', 'liveStreamType 50 without liveUrl'),
      ]) {
        final setup = _setup(extra: [_room(_video, edited(streamType))]);
        final before = await setup.site.getRoomDetail(roomId: _video);
        await expectLater(setup.site.getPlayQualities(detail: before), throwsA(isA<StreamUnavailable>()));
        await setup.site.getDirectoryPage();
        final after = await setup.site.getRoomDetail(roomId: _video);
        final expected = (legacy[name] as Map<String, dynamic>)['after the list'] as Map<String, dynamic>;
        _expectParity(after, expected['getRoomDetail'], reason: name);
        final qualities = expected['getRoomDetail → getPlayQualites'];
        if (qualities is List) {
          expect(_qualities(await setup.site.getPlayQualities(detail: after)), _legacyQualities(qualities));
          expect(
            (await setup.site.resolvePlayUrlsRaw(detail: after, quality: LookLiveApi.hlsQuality)).urls,
            (expected['getRoomDetail → resolvePlayUrlsRaw(hls:source)'] as Map)['urls'],
          );
        } else {
          expect(_failure(qualities), 'mediaUnavailable');
          await expectLater(setup.site.getPlayQualities(detail: after), throwsA(isA<StreamUnavailable>()));
        }
      }
    });

    test('rooms that cannot play: a card, a refresh or search room, offline, app-only, another platform', () async {
      final setup = _setup();
      final card = (await setup.site.getDirectoryPage(category: LookLiveApi.videoArea)).rooms.first;
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: _video);
      final found = (await setup.site.searchRooms(_video)).single;
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      final appOnly = await setup.site.getRoomDetail(roomId: _appOnly);
      final sent = setup.http.requests.length;
      for (final room in [card, refresh, found, offline, appOnly]) {
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
        await expectLater(
          setup.site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: LookLiveApi.hlsQuality),
          throwsA(isA<StreamUnavailable>()),
        );
      }
      final entry = await setup.site.getRoomDetail(roomId: _video);
      final other = LiveRoom(roomId: _video, platform: 'bilibili', data: entry.data);
      await expectLater(setup.site.getPlayQualities(detail: other), throwsArgumentError);
      final moved = LiveRoom(roomId: _audio, platform: 'looklive', liveStatus: LiveStatus.live, data: entry.data);
      await expectLater(setup.site.getPlayQualities(detail: moved), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(sent + 1), reason: 'only the room entry asked');
    });

    test('recovery after the room ended says why; the lines of a room entry still work until then', () async {
      final setup = _setup();
      final detail = await setup.site.getRoomDetail(roomId: _video);
      final ended = _body('S03-room-video').replaceFirst('"liveStatus": 1', '"liveStatus": -1');
      final later = LookLiveSite(ReplayHttp([_room(_video, ended)]));
      await expectLater(
        later.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: LookLiveApi.hlsQuality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect((await setup.site.resolvePlayUrlsRaw(detail: detail, quality: LookLiveApi.hlsQuality)).urls, hasLength(1));
    });

    test('room entry and recording carry the chat (M5.28) from the one room request; a refresh does not', () async {
      final setup = _setup();
      const chat = LookLiveDanmakuArgs(roomId: _video, chatroomId: '462192286');
      expect((await setup.site.getRoomDetail(roomId: _video)).danmakuData, chat);
      expect((await setup.site.getRoomDetailForRecording(roomId: _video)).danmakuData, chat);
      expect((await setup.site.getRoomDetailForRefresh(roomId: _video)).danmakuData, isNull);
      expect(_sent(setup.http.requests), [
        for (var i = 0; i < 3; i++)
          'POST https://api.look.163.com/weapi/livestream/room/get/v3 {"liveRoomNo":"21623631"}',
      ]);
      expect(
        (await setup.site.getRoomDetail(roomId: _audio)).danmakuData,
        const LookLiveDanmakuArgs(roomId: _audio, chatroomId: '16272838887'),
      );
      expect((await setup.site.getRoomDetail(roomId: _offline)).danmakuData, isNull, reason: 'not live');
      final rooms = await setup.site.getRecommendRooms();
      expect(rooms.map((room) => room.danmakuData), everyElement(isNull), reason: 'list cards');
    });

    test('the rooms kept are bounded: the oldest of more than 2000 is forgotten', () async {
      final http = _Scripted((request) {
        final payload = jsonDecode(_payload(request)) as Map<String, dynamic>;
        if (request.url.path == LookLiveApi.roomPath) {
          return _response(request, _roomBody(payload['liveRoomNo'] as String));
        }
        final offset = payload['offset'] as int;
        return _response(request, _listBody([for (var i = 0; i < 100; i++) '${10000000 + offset * 5 + i}']));
      });
      final site = LookLiveSite(http);
      for (var page = 1; page <= 21; page++) {
        await site.getDirectoryPage(page: page, category: LookLiveApi.videoArea);
      }
      final first = await site.getRoomDetailForRefresh(roomId: '10000000');
      expect(first.effectiveOnlineViewers, isEmpty, reason: 'its card was dropped');
      final last = await site.getRoomDetailForRefresh(roomId: '${10000000 + 400 * 5 + 99}');
      expect(last.effectiveOnlineViewers, '3');
    });
  });

  group('links', () {
    test('look.163.com room links and share texts, through the link parser; no request', () async {
      final http = _Scripted((request) => throw StateError('no request'));
      final registry = SiteRegistry({'looklive': () => LookLiveSite(http)});
      final parser = LinkParser(registry, http);
      expect(await parser.parse('LOOK https://look.163.com/live?id=$_video'), const RoomLink('looklive', _video));
      expect(
        await parser.parse('来看直播 https://look.163.com/live?id=$_video&position=3。快来'),
        const RoomLink('looklive', _video),
      );
      expect(await parser.parse('https://look.163.com/hot?id=$_video'), isNull);
      expect(await parser.parse('https://look.163.com/live?id=$_video&id=2'), isNull);
      expect(await parser.parse('https://look.163.com.evil.test/live?id=$_video'), isNull);
      expect(await parser.parse(_video), isNull, reason: 'a bare number is not a link');
      expect(parser.containsSupportedLink('LOOK https://look.163.com/live?id=$_video'), isTrue);
      final site = registry.of('looklive') as LookLiveSite;
      expect(site.roomIdFromUrl('https://look.163.com:8443/live?id=$_video'), isNull);
      expect(site.roomIdFromUrl(_video), isNull);
      expect(site.needsResolving('https://look.163.com/live?id=$_video'), isFalse);
      expect(http.requests, isEmpty);
    });
  });
}
