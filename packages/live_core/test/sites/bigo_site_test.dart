// BigoSite over the recorded Bigo responses (ReplayHttp) and a few synthetic
// ones: the request headers, the web token before every studio request, the
// shared list and its 30 s reuse (24-5), the directory pages and 3.x's
// slices, the search's lookups and filter, rooms at every depth, the reused
// token of refreshes and the gate asked again (24-4, a scripted site `_Bigo`
// that answers as the site did in the checks), the owned input and its fresh
// studio answer per consumer, cancellation, the deadline, links (24-7), case
// in ids and the error mapping. Requests are compared with the ones 3.x sent
// (expected.json records them); where they differ the test says why. The
// token's random `callback`, `data` and `token` values are left out of
// matching; the callback names are the recorded ones.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/bigo';
const _ignored = {'callback', 'data', 'token'};

/// The live room of the studio samples, as the list names it, and its id as
/// the site writes it.
const _room = '414439909';
const _canonical = 'qashia305';

const _list = ['S01-list'];
const _live = ['S02-time-live', 'S02-status-live', 'S03-studio-live'];

const _studioPath = '/official_website/studio/getInternalStudioInfo';

final DateTime _now = DateTime.utc(2026, 9, 28, 3, 5);

/// The callback names of the recorded token answers, in order.
String Function() _callbacks() {
  var next = 0;
  return () => (next++).isEven ? 'jsonp_purelive_t' : 'jsonp_purelive_s';
}

Map<String, dynamic> _legacy(String sample) => Fixture.load('bigo', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<String> _legacyRequests(Object? traced) => ((traced! as Map<String, dynamic>)['requests'] as List).cast<String>();

/// A request as the legacy harness wrote it: method, URL without the token's
/// random values.
String _line(LiveRequest request) {
  final url = request.url;
  final pairs = [
    for (final MapEntry(:key, :value) in url.queryParameters.entries)
      if (!_ignored.contains(key)) '$key=$value',
  ];
  return '${request.method} ${url.scheme}://${url.host}${url.path}${pairs.isEmpty ? '' : '?${pairs.join('&')}'}';
}

List<String> _sent(Iterable<LiveRequest> requests) => [for (final request in requests) _line(request)];

/// A studio answer for [siteId]'s tokenized request.
ReplaySample _studioAnswer(String siteId, String body, {int status = 200}) => ReplaySample(
  method: 'POST',
  url: Uri.https('ta.bigo.tv', _studioPath, {'siteId': siteId, 'verify': ''}),
  status: status,
  bytes: utf8.encode(body),
);

/// The recorded live studio answer with [data] fields replaced.
String _studio(Map<String, Object?> data) {
  final root = jsonDecode(Fixture.load('bigo', 'S03-studio-live').body) as Map<String, dynamic>;
  (root['data'] as Map<String, dynamic>).addAll(data);
  return jsonEncode(root);
}

String _avatarHttps() =>
    Fixture.load('bigo', 'S03-studio-live').body.replaceFirst('"avatar": "http://', '"avatar": "https://');

typedef _Setup = ({BigoSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now, Random? random}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in samples) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: _ignored);
  return (site: BigoSite(http, now: now ?? () => _now, random: random, callbackName: _callbacks()), http: http);
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

/// A scripted Bigo that behaves as the site did in the checks of 2026-09-28/29
/// (24-4): every `webjs/status` issues a new token `t0k3n<n>`; a token's
/// first studio use answers the recorded live studio (with its playlist and
/// `passRoom`), every later use the same without them (S03-studio-reused).
/// With [gateFirstUse] the first use answers the login gate instead
/// (S03-studio-notoken); with [gateEveryUse] every use does. The first
/// [failTokens] `webjs/t` requests answer 503; with [delay] the first one
/// waits for [release].
final class _Bigo {
  new({this.gateFirstUse = false, this.gateEveryUse = false, this.failTokens = 0, this.delay = false});

  final bool gateFirstUse;
  final bool gateEveryUse;
  final int failTokens;
  final bool delay;
  final Completer<void> _gate = Completer<void>();
  var _issued = 0;
  var _timeRequests = 0;
  final Map<String, int> _uses = {};

  /// The path of every request, in order.
  final List<String> paths = [];

  /// The token of every studio request, in order.
  final List<String> tokens = [];

  late final _Scripted http = _Scripted(_answer);

  void release() => _gate.complete();

  Future<LiveResponse> _answer(LiveRequest request) async {
    paths.add(request.url.path);
    final callback = request.url.queryParameters['callback'];
    switch (request.url.path) {
      case '/v1/webjs/t':
        if (delay && _timeRequests == 0) await _gate.future;
        if (_timeRequests++ < failTokens) return _response(request, '', status: 503);
        return _response(request, '$callback({"code":0,"time":"1672503768"});');
      case '/v1/webjs/status':
        return _response(request, '$callback({"code":0,"token":"t0k3n${++_issued}"});');
    }
    final token = request.url.queryParameters['token']!;
    tokens.add(token);
    final use = _uses[token] = (_uses[token] ?? 0) + 1;
    if (gateEveryUse || (gateFirstUse && use == 1)) {
      return _response(request, Fixture.load('bigo', 'S03-studio-notoken').body);
    }
    return _response(request, use == 1 ? Fixture.load('bigo', 'S03-studio-live').body : _studio(_reused));
  }
}

/// The recorded live studio as a used token answers it (S03-studio-reused).
const Map<String, Object?> _reused = {'passRoom': null, 'hls_src': ''};

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('bigo', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('bigo', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// Asserts [room] equals 3.x's [legacy] projection on every key 3.x wrote,
/// except [changed]. Every room differs in its notice, said for viewers (the
/// unified rule on notices; M5.20 drops "chat pending" from it).
void _expectParity(LiveRoom room, Object? legacy, {Set<String> changed = const {'notice'}, String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

List<Object?> _ids(Object? legacy) => [for (final room in legacy! as List) (room as Map)['roomId']];

void main() {
  group('requests', () {
    test("3.x's headers everywhere, no redirects, as bigo; the token first, then the studio with it", () async {
      final setup = _setup([..._list, ..._live], random: Random(7));
      await setup.site.getRecommendRooms();
      await setup.site.getRoomDetail(roomId: _room);
      expect(_sent(setup.http.requests), [
        'GET https://ta.bigo.tv/official_website/OInterfaceWeb/vedioList/72?tabType=00&fetchNum=10&lang=en&countryCode=US',
        'GET https://sec.bigo.sg/v1/webjs/t',
        'GET https://sec.bigo.sg/v1/webjs/status',
        'POST https://ta.bigo.tv$_studioPath?siteId=$_room&verify=',
      ]);
      for (final request in setup.http.requests) {
        expect(request.headers, {
          'origin': 'https://www.bigo.tv',
          'referer': 'https://www.bigo.tv/',
          'user-agent': 'Mozilla/5.0',
        });
        expect(request.followRedirects, isFalse);
        expect(request.site, 'bigo');
      }
      final [_, time, status, studio] = setup.http.requests;
      expect(time.url.queryParameters['callback'], 'jsonp_purelive_t');
      expect(status.url.queryParameters['callback'], 'jsonp_purelive_s');
      expect(
        status.url.queryParameters['data'],
        BigoApi.tokenData('1672503768', random: Random(7)),
        reason: "3.x's codec over the server time of webjs/t",
      );
      expect(studio.url.queryParameters['token'], 'DOmOJRj8G2MasRYxGhnGwdhhGCcQoWQGUo7TlgKp88ZTniqMFVN03y');
      expect(studio.body, isEmpty, reason: '3.x sent the token in the query, no form (§10: the form request is gated)');
      expect(studio.headers.keys, isNot(contains('content-type')));
      expect((setup.site.id, setup.site.name), ('bigo', 'Bigo Live'));
      expect(setup.site.directoryNoticeKey, 'bigo_directory_scope');
    });

    test("3.x's default callback names: jsonpcallback_<ms>_<µs> of the clock, echoed by the service", () async {
      final clock = DateTime.fromMicrosecondsSinceEpoch(1790000000123456, isUtc: true);
      final body = Fixture.load('bigo', 'S03-studio-live').body;
      final http = _Scripted((request) {
        final callback = request.url.queryParameters['callback'];
        return switch (request.url.path) {
          '/v1/webjs/t' => _response(request, '$callback({"code":0,"time":"1672503768"});'),
          '/v1/webjs/status' => _response(request, '$callback({"code":0,"token":"t0k3n"});'),
          _ => _response(request, body),
        };
      });
      final room = await BigoSite(http, now: () => clock).getRoomDetailForRefresh(roomId: _room);
      expect(room.roomId, _canonical);
      expect(http.requests.take(2).map((request) => request.url.queryParameters['callback']), [
        'jsonpcallback_1790000000123_123456',
        'jsonpcallback_1790000000123_123456',
      ]);
      expect(http.requests.last.url.queryParameters['token'], 't0k3n');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are mapped', () async {
      await expectLater(
        BigoSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: _room),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(BigoSite(_Failing(TransportReason.cancelled)).getRecommendRooms(), _cancelled);
      for (final (status, type) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (400, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(BigoSite(http).getRoomDetail(roomId: _room), throwsA(type), reason: '$status');
        await expectLater(BigoSite(http).getRecommendRooms(), throwsA(type), reason: '$status');
        expect(http.requests.where((request) => request.url.path == '/v1/webjs/status'), isEmpty);
      }
      final html = _Scripted((request) => _response(request, '<html></html>'));
      await expectLater(BigoSite(html).getRecommendRooms(), throwsA(isA<ApiChanged>()));
      await expectLater(BigoSite(html).getRoomDetail(roomId: _room), throwsA(isA<ApiChanged>()));
      final huge = _Scripted((request) => _response(request, '{"x":"${'a' * BigoApi.responseLimit}"}'));
      await expectLater(BigoSite(huge).getRecommendRooms(), throwsA(isA<ApiChanged>()));
    });

    test(
      "one 20 s deadline over the token and the studio (3.x's scope): NetworkFailure, the request cancelled",
      () async {
        final http = _Scripted((request) => Completer<LiveResponse>().future);
        final site = BigoSite(http, deadline: const Duration(milliseconds: 30));
        await expectLater(site.getRoomDetail(roomId: _room), throwsA(isA<NetworkFailure>()));
        expect(http.requests.single.cancel!.isCancelled, isTrue);
        await expectLater(site.getRecommendRooms(), throwsA(isA<NetworkFailure>()));
        expect(BigoSite(http).deadline, const Duration(seconds: 20));
      },
    );

    test("the caller's cancellation reaches the request and is reported as such", () async {
      final http = _Scripted((request) => Completer<LiveResponse>().future);
      final site = BigoSite(http);
      final token = CancelToken();
      final detail = site.searchRoomsCancellable(_room, cancel: token);
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectLater(detail, _cancelled);
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      await expectLater(site.searchRoomsCancellable('Pk', cancel: token), _cancelled);
      await expectLater(site.getDirectoryPage(cancel: token), _cancelled);
      expect(http.requests, hasLength(1), reason: 'nothing is sent once cancelled');
    });
  });

  group('the public list', () {
    test('shared for 30 s by callers without a token (3.x); page 1 of the directory is new (24-5)', () async {
      var now = _now;
      final setup = _setup(_list, now: () => now);
      final legacy = _legacy('S01-list');
      await setup.site.getRecommendRooms();
      await setup.site.getCategoryRooms(BigoApi.area);
      await setup.site.searchRooms('Pk');
      expect(setup.http.requests, hasLength(1));
      await setup.site.getDirectoryPage();
      expect(setup.http.requests, hasLength(2), reason: 'page 1 is the pull to refresh (24-5; 3.x shared it)');
      await setup.site.getDirectoryPage(cancel: CancelToken());
      expect(setup.http.requests, hasLength(3));
      // 3.x sent 2 requests for the same calls: the directory without a
      // token shared the list, the one with a token fetched anew.
      expect(_legacyRequests(legacy['cache']), hasLength(2));
      expect(_sent(setup.http.requests).toSet(), _legacyRequests(legacy['cache']).toSet());
      now = now.add(const Duration(seconds: 29));
      await setup.site.getRecommendRooms(page: 2, pageSize: 8);
      await setup.site.searchRoomsCancellable('Pk', cancel: CancelToken());
      await setup.site.getDirectoryPage(page: 2, cancel: CancelToken());
      expect(setup.http.requests, hasLength(3), reason: 'the list page 1 fetched, for 30 s');
      now = now.add(const Duration(seconds: 1));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(4), reason: 'a list 30 s old is fetched again');
    });

    test('24-5: the search and later pages use the list the directory fetched (3.x fetched anew for each)', () async {
      var now = _now;
      final setup = _setup(_list, now: () => now);
      final page = await setup.site.getDirectoryPage(cancel: CancelToken());
      final search = await setup.site.searchRoomsCancellable('Pk', pageSize: 20, cancel: CancelToken());
      final second = await setup.site.getDirectoryPage(page: 2, cancel: CancelToken());
      final recommended = await setup.site.getRecommendRooms(pageSize: 100);
      expect(setup.http.requests, hasLength(1), reason: '3.x: 3 (page 1, the search, page 2 each with a token)');
      expect(search.single.roomId, '858683693');
      expect(page.rooms.map((room) => room.roomId), recommended.map((room) => room.roomId));
      expect(second.rooms, isEmpty);
      expect(page.hasMore, isFalse);
      now = now.add(const Duration(seconds: 30));
      await setup.site.searchRoomsCancellable('Pk', pageSize: 20, cancel: CancelToken());
      expect(setup.http.requests, hasLength(2), reason: 'a list 30 s old is fetched again');
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(2), reason: "the search's list is shared");
      await setup.site.getDirectoryPage(cancel: CancelToken());
      expect(setup.http.requests, hasLength(3), reason: 'the pull to refresh');
      now = now.subtract(const Duration(minutes: 5));
      await setup.site.searchRoomsCancellable('Pk', pageSize: 20, cancel: CancelToken());
      expect(setup.http.requests, hasLength(4), reason: 'a clock turned back is no reuse');
    });

    test('24-5: a call with a token does not wait on a shared fetch under way; cancelling it fails nobody', () async {
      final body = Fixture.load('bigo', 'S01-list').body;
      final gates = <Completer<void>>[];
      final http = _Scripted((request) async {
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        return _response(request, body);
      });
      final site = BigoSite(http);
      final shared = site.getRecommendRooms();
      final token = CancelToken();
      final search = site.searchRoomsCancellable('Pk', cancel: token);
      await Future<void>.delayed(Duration.zero);
      expect(http.requests, hasLength(2), reason: 'the search fetched its own list');
      token.cancel();
      await expectLater(search, _cancelled);
      gates.first.complete();
      expect(await shared, hasLength(20));
      await site.searchRoomsCancellable('Pk', cancel: CancelToken());
      expect(http.requests, hasLength(2), reason: 'the arrived shared list is reused');
    });

    test('24-5: a failed or cancelled fetch leaves no list; the one before stays usable', () async {
      var now = _now;
      var fail = false;
      final body = Fixture.load('bigo', 'S01-list').body;
      final http = _Scripted((request) => fail ? _response(request, '', status: 503) : _response(request, body));
      final site = BigoSite(http, now: () => now);
      await site.getDirectoryPage(cancel: CancelToken());
      fail = true;
      await expectLater(site.getDirectoryPage(cancel: CancelToken()), throwsA(isA<NetworkFailure>()));
      now = now.add(const Duration(seconds: 10));
      expect((await site.searchRoomsCancellable('Pk', cancel: CancelToken())).single.roomId, '858683693');
      expect(http.requests, hasLength(2), reason: 'the first list, still younger than 30 s');
    });

    test('concurrent callers share the fetch under way; a failed fetch is forgotten', () async {
      final body = Fixture.load('bigo', 'S01-list').body;
      final gate = Completer<void>();
      var fail = true;
      final http = _Scripted((request) async {
        await gate.future;
        return fail ? _response(request, '', status: 500) : _response(request, body);
      });
      final site = BigoSite(http);
      final first = site.getRecommendRooms();
      final second = site.getCategoryRooms(BigoApi.area);
      final third = site.searchRooms('Pk');
      gate.complete();
      await expectLater(first, throwsA(isA<NetworkFailure>()));
      await expectLater(second, throwsA(isA<NetworkFailure>()));
      await expectLater(third, throwsA(isA<NetworkFailure>()));
      expect(http.requests, hasLength(1), reason: '3.x sent one request per caller until the first answer');
      fail = false;
      expect(await site.getRecommendRooms(), hasLength(20));
      expect(http.requests, hasLength(2));
    });

    test('the category and its area; page 2 and a size below 1 are empty; no request (3.x)', () async {
      final setup = _setup(_list);
      final legacy = _legacy('S01-list');
      final category = (await setup.site.getCategories(1, 30)).single;
      final expected = (_result(legacy['getCategores'])! as List).single as Map<String, dynamic>;
      expect((category.id, category.name), (expected['id'], expected['name']));
      expect(category.children.single.toJson()..removeWhere((key, value) => value == ''), {
        for (final MapEntry(:key, :value) in (((expected['children'] as List).single) as Map).entries) key: ?value,
      });
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(await setup.site.getCategories(1, 0), isEmpty);
      expect(setup.http.requests, isEmpty);
      expect(_legacyRequests(legacy['getCategores']), isEmpty);
    });

    test('directory pages of 20: rooms, pages and requests of 3.x, for the recommendations and the area', () async {
      final legacy = _legacy('S01-list')['getDirectoryPage'] as Map<String, dynamic>;
      for (final (key, page, area) in [
        ('recommend:1', 1, null),
        ('recommend:2', 2, null),
        ('recommend:3', 3, null),
        ('public:1', 1, BigoApi.area),
      ]) {
        final setup = _setup(_list);
        final directory = await setup.site.getDirectoryPage(page: page, category: area, cancel: CancelToken());
        final want = _result(legacy[key])! as Map<String, dynamic>;
        final rooms = (want['rooms'] as List).cast<Map<String, dynamic>>();
        expect(directory.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']), reason: key);
        for (final (index, room) in directory.rooms.indexed) {
          _expectParity(room, rooms[index], reason: '$key[$index]');
        }
        expect((directory.page, directory.hasMore), (want['page'], want['hasMore']), reason: key);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[key]), reason: key);
      }
    });

    test('caller errors are refused without a request (3.x: identity and schema failures)', () async {
      final setup = _setup(_list);
      final legacy = _legacy('S01-list');
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsRangeError);
      expect(_result((legacy['getDirectoryPage'] as Map)['recommend:0']), containsPair('message', 'Bigo schema'));
      for (final area in [
        const LiveArea(platform: 'bigo', areaType: 'public', areaId: '73'),
        const LiveArea(platform: 'bilibili', areaType: 'public', areaId: '72'),
        const LiveArea(platform: 'bigo', areaType: 'genre', areaId: '72'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: '$area');
      }
      expect(setup.http.requests, isEmpty);
      expect(_result((legacy['getDirectoryPage'] as Map)['otherArea:1']), containsPair('message', 'Bigo identity'));
      expect(_result((legacy['getCategoryRooms'] as Map)['otherPlatform']), containsPair('message', 'Bigo identity'));
    });

    test("3.x's slices of the recommendations and the area; the ones 3.x served nothing for send nothing", () async {
      final legacy = _legacy('S01-list');
      for (final MapEntry(:key, :value) in (legacy['getRecommendRooms'] as Map<String, dynamic>).entries) {
        final [_, page, _, size] = key.split(' ');
        final setup = _setup(_list);
        final rooms = await setup.site.getRecommendRooms(page: int.parse(page), pageSize: int.parse(size));
        expect(rooms.map((room) => room.roomId), _ids(_result(value)), reason: key);
        if (BigoApi.validSlice(page: int.parse(page), pageSize: int.parse(size))) {
          expect(_sent(setup.http.requests), _legacyRequests(value), reason: key);
        } else {
          expect(setup.http.requests, isEmpty, reason: '$key: 3.x asked, then gave nothing');
        }
      }
      final area = legacy['getCategoryRooms'] as Map<String, dynamic>;
      final setup = _setup(_list);
      expect(
        (await setup.site.getCategoryRooms(BigoApi.area)).map((room) => room.roomId),
        _ids(_result(area['public page 1'])),
      );
      expect(
        (await setup.site.getCategoryRooms(BigoApi.area, page: 2, pageSize: 8)).map((room) => room.roomId),
        _ids(_result(area['public page 2 size 8'])),
      );
    });
  });

  group('search', () {
    test("3.x's results and requests: names and topics filtered, ids and links looked up", () async {
      final legacy = _legacy('S01-list')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      for (final keyword in [
        'Pk',
        'pk CHALLENGE',
        'qashia',
        'MR',
        '赚钱',
        'nickname words',
        'http://example.com/x',
        '  ',
      ]) {
        final traced = legacy['$keyword page 1'];
        final setup = _setup(_list);
        final rooms = await setup.site.searchRoomsCancellable(keyword, pageSize: 20, cancel: CancelToken());
        expect(rooms.map((room) => room.roomId), _ids(_result(traced)), reason: keyword);
        for (final (index, room) in rooms.indexed) {
          _expectParity(room, (_result(traced)! as List)[index], reason: '$keyword[$index]');
        }
        expect(_sent(setup.http.requests), _legacyRequests(traced), reason: keyword);
      }
      for (final (key, keyword, page) in [('Pk page 2', 'Pk', 2), ('long', 'a' * 101, 1)]) {
        final setup = _setup(_list);
        expect(
          await setup.site.searchRoomsCancellable(keyword, page: page, pageSize: 20, cancel: CancelToken()),
          isEmpty,
        );
        expect(_result(legacy[key]), isEmpty);
        expect(setup.http.requests, isEmpty);
      }
      final shared = _setup(_list);
      expect((await shared.site.searchRooms('Pk', pageSize: 20)).single.roomId, '858683693');
      expect(_sent(shared.http.requests), _legacyRequests(legacy['Pk without a token']));
      expect(await shared.site.searchRooms('Pk', pageSize: 0), isEmpty);
    });

    test('an id or a room link is looked up (three requests, 3.x); 3.x failed on the http avatar', () async {
      final legacy = _legacy('S01-list');
      final recorded = legacy['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      final https = legacy['searchRooms avatarHttps'] as Map<String, dynamic>;
      for (final keyword in [_room, 'https://www.bigo.tv/$_room', 'https://www.bigo.tv/en/$_room']) {
        expect(_result(recorded['$keyword page 1']), containsPair('message', 'Bigo schema'), reason: keyword);
        final setup = _setup([..._list, ..._live]);
        final rooms = await setup.site.searchRoomsCancellable(keyword, pageSize: 20, cancel: CancelToken());
        expect(rooms.single.roomId, _canonical, reason: keyword);
        expect(rooms.single.isLiveNow, isTrue);
        final twin = https[keyword] ?? https[_room];
        // avatar: the recorded http avatar (3.x failed on it); cover: the
        // snapshot (24-1); notice: said for viewers (M5.20 drops "chat pending").
        _expectParity(
          rooms.single,
          (_result(twin)! as List).single,
          changed: {'avatar', 'cover', 'notice'},
          reason: keyword,
        );
        expect(rooms.single.restriction, LiveRestriction.none, reason: 'a lookup is a complete answer');
        expect(_sent(setup.http.requests), _legacyRequests(recorded['$keyword page 1']), reason: keyword);
      }
    });

    test('a word matching no card is looked up as an id (3.x); an unknown id is no result', () async {
      final traced = (_legacy('S01-list')['searchRooms (pageSize 20)'] as Map<String, dynamic>)['zzqxnomatch page 1'];
      final setup = _setup([..._list, ..._live], extra: [_studioAnswer('zzqxnomatch', '', status: 404)]);
      expect(await setup.site.searchRoomsCancellable('zzqxnomatch', pageSize: 20, cancel: CancelToken()), isEmpty);
      expect(_sent(setup.http.requests), _legacyRequests(traced));
      final failing = _setup([..._list, ..._live], extra: [_studioAnswer('zzqxnomatch', '{"code":1}')]);
      await expectLater(failing.site.searchRooms('zzqxnomatch'), throwsA(isA<ApiChanged>()));
    });

    test(
      "the site's actual answer for an unknown id (S03-studio-unknown) is no result (3.x failed the search)",
      () async {
        final setup = _setup([..._list, ..._live, 'S03-studio-unknown']);
        expect(await setup.site.searchRoomsCancellable('zzqxnomatch', pageSize: 20, cancel: CancelToken()), isEmpty);
        expect(setup.http.requests, hasLength(4), reason: 'the list, the token and the studio');
        await expectLater(setup.site.getRoomDetail(roomId: 'zzqxnomatch'), throwsA(isA<NotFound>()));
      },
    );

    test('a word that is a listed id is looked up rather than filtered (3.x)', () async {
      final list = jsonDecode(Fixture.load('bigo', 'S01-list').body) as Map<String, dynamic>;
      (((list['data'] as Map)['data'] as List)[4] as Map)['bigo_id'] = _canonical.replaceAll(RegExp('[0-9]'), '');
      final setup = _setup(
        _live.take(2).toList(),
        extra: [
          ReplaySample(
            method: 'GET',
            url: Uri.parse(
              'https://ta.bigo.tv/official_website/OInterfaceWeb/vedioList/72?tabType=00&fetchNum=10&lang=en&countryCode=US',
            ),
            status: 200,
            bytes: utf8.encode(jsonEncode(list)),
          ),
          _studioAnswer('QASHIA', _studio(const {})),
        ],
      );
      final rooms = await setup.site.searchRooms('QASHIA');
      expect(rooms.single.roomId, _canonical);
      expect(setup.http.requests.last.url.queryParameters['siteId'], 'QASHIA', reason: 'asked as typed (3.x)');
    });
  });

  group('rooms', () {
    test("every depth is the token and the studio (3.x's three requests); the id is the site's spelling", () async {
      final calls = (_legacy('S03-studio-live')['avatarHttps'] as Map<String, dynamic>)[_room] as Map<String, dynamic>;
      for (final (depth, detail) in <(String, Future<LiveRoom> Function(BigoSite))>[
        ('getRoomDetail', (site) => site.getRoomDetail(roomId: _room)),
        ('getRoomDetailForRefresh', (site) => site.getRoomDetailForRefresh(roomId: _room)),
        ('getRoomDetailForRecording', (site) => site.getRoomDetailForRecording(roomId: _room)),
      ]) {
        final setup = _setup(_live);
        final room = await detail(setup.site);
        expect(room.roomId, _canonical, reason: depth);
        // avatar: the recorded http avatar (3.x failed the room on it);
        // cover: the snapshot (24-1); notice: said for viewers (M5.20 drops "chat pending").
        _expectParity(room, _result(calls[depth]), changed: {'avatar', 'cover', 'notice'}, reason: depth);
        expect(room.avatar, startsWith('http://esx.bigo.sg/'));
        expect(room.cover, contains('1wgYlS00y4dZTiM2B5Tdq_2.jpg'), reason: 'the snapshot (24-1)');
        expect(room.restriction, LiveRestriction.none, reason: "added: a token's first use");
        expect(_sent(setup.http.requests), _legacyRequests(calls[depth]), reason: depth);
        expect((room.data! as BigoRoomData).hasStream, isTrue);
        final https = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, _avatarHttps())]);
        _expectParity(
          await detail(https.site),
          _result(calls[depth]),
          changed: {'cover', 'notice'},
          reason: '$depth (https avatar)',
        );
      }
      final recorded = (_legacy('S03-studio-live')['recorded'] as Map<String, dynamic>)[_room] as Map<String, dynamic>;
      expect(_result(recorded['getRoomDetail']), containsPair('message', 'Bigo schema'));
    });

    test('M5.20: entries and recording details carry the chat arguments without a request; refreshes and '
        'lookups do not', () async {
      for (final (depth, detail, carries) in <(String, Future<LiveRoom> Function(BigoSite), bool)>[
        ('getRoomDetail', (site) => site.getRoomDetail(roomId: _room), true),
        ('getRoomDetailForRecording', (site) => site.getRoomDetailForRecording(roomId: _room), true),
        ('getRoomDetailForRefresh', (site) => site.getRoomDetailForRefresh(roomId: _room), false),
        (
          'searchRoomsCancellable',
          (site) async => (await site.searchRoomsCancellable(_room, pageSize: 20, cancel: CancelToken())).single,
          false,
        ),
      ]) {
        final setup = _setup([..._list, ..._live]);
        final room = await detail(setup.site);
        expect(setup.http.requests, hasLength(3), reason: '$depth: no request for the chat');
        if (carries) {
          final args = room.danmakuData! as BigoDanmakuArgs;
          expect((args.siteId, args.ownerId, args.roomId), (_canonical, 409742853, '6812312308570332324'));
        } else {
          expect(room.danmakuData, isNull, reason: depth);
        }
      }
      final gated = _Bigo(gateEveryUse: true);
      final entry = await BigoSite(gated.http, now: () => _now).getRoomDetail(roomId: _room);
      expect(entry.danmakuData, isNull, reason: 'the page opens no chat behind the login gate');
    });

    test('asked by the site spelling, the room is the same', () async {
      final setup = _setup(_live.take(2).toList(), extra: [_studioAnswer(_canonical, _studio(const {}))]);
      final room = await setup.site.getRoomDetail(roomId: ' $_canonical ');
      expect(room.roomId, _canonical);
      expect(setup.http.requests.last.url.queryParameters['siteId'], _canonical);
    });

    test("a follow stored by 3.x merges the refresh; a card by the list's id is another identity (3.x)", () async {
      final calls = (_legacy('S03-studio-live')['avatarHttps'] as Map<String, dynamic>)[_room] as Map<String, dynamic>;
      final stored = LiveRoom.fromJson((_result(calls['getRoomDetailForRefresh'])! as Map).cast<String, Object?>());
      final refreshed = await _setup(_live).site
          .getRoomDetailForRefresh(roomId: stored.roomId.replaceAll('qashia305', _room));
      final merged = stored.mergeFrom(refreshed);
      expect(merged.hasSameIdentity(stored), isTrue);
      expect(merged.isLiveNow, isTrue);
      expect(merged.httpHeaders, BigoApi.headers);
      final card = BigoApi.directory(Fixture.load('bigo', 'S01-list').body).firstWhere((card) => card.roomId == _room);
      expect(card.hasSameIdentity(refreshed), isFalse, reason: '3.x bound a refresh to the follow it was asked for');
    });

    test('the live status: true (three requests, then one); a restricted live room is live; a gate that stays is '
        'an error, never offline', () async {
      final live = _setup(_live);
      expect(await live.site.getLiveStatus(roomId: _room), isTrue);
      expect(live.http.requests, hasLength(3));
      expect(await live.site.getLiveStatus(roomId: _room), isTrue);
      expect(live.http.requests, hasLength(4), reason: 'the token is reused (24-4)');
      final offline = _setup(
        _live.take(2).toList(),
        extra: [
          _studioAnswer(_room, _studio({'alive': 0, 'hls_src': ''})),
        ],
      );
      expect(await offline.site.getLiveStatus(roomId: _room), isFalse);
      final notoken = Fixture.load('bigo', 'S03-studio-notoken').body;
      final gated = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, notoken)]);
      await expectLater(gated.site.getLiveStatus(roomId: _room), throwsA(isA<NeedsLogin>()));
      expect(gated.http.requests, hasLength(4), reason: 'asked again with the same token; still gated');
      final calls = (_legacy('S03-studio-notoken')['asTokenAnswer'] as Map<String, dynamic>)[_room] as Map;
      expect(_result(calls['getLiveStatus']), containsPair('message', 'Bigo unknownState'));
      for (final data in <Map<String, Object?>>[
        {'isPaidShow': '1', 'hls_src': ''},
        {'passRoom': true, 'hls_src': ''},
        {'hls_src': ''},
      ]) {
        // 3.x (and M4.24): unknownState / StreamUnavailable; a restricted
        // live room is live now (M2.1).
        final restricted = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, _studio(data))]);
        expect(await restricted.site.getLiveStatus(roomId: _room), isTrue, reason: '$data');
      }
      final locked = _setup(
        _live.take(2).toList(),
        extra: [
          _studioAnswer(_room, _studio({'passRoom': true, 'alive': 0, 'hls_src': ''})),
        ],
      );
      await expectLater(locked.site.getLiveStatus(roomId: _room), throwsA(isA<StreamUnavailable>()));
    });

    test('a gate that stays: the room opens with its state unknown, the login notice and needsLogin (3.x)', () async {
      final notoken = Fixture.load('bigo', 'S03-studio-notoken').body;
      final calls = (_legacy('S03-studio-notoken')['asTokenAnswer'] as Map<String, dynamic>)[_room] as Map;
      final setup = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, notoken)]);
      final room = await setup.site.getRoomDetail(roomId: _room);
      // cover: the snapshot (24-1); notice: said for viewers (M5.20 drops "chat pending").
      _expectParity(room, _result(calls['getRoomDetail']), changed: {'cover', 'notice'});
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect(room.restriction, LiveRestriction.needsLogin);
      expect(setup.http.requests, hasLength(4), reason: '3.x: 3; the same token asked again once');
      final [_, _, first, again] = setup.http.requests;
      expect(again.url.queryParameters['token'], first.url.queryParameters['token']);
    });

    test('an id that is not a Bigo id is NotFound without a request (3.x: identity)', () async {
      final setup = _setup(_live);
      for (final id in ['../x', '', 'a b', 'a' * 65]) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getLiveStatus(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      final recorded = _legacy('S03-studio-live')['recorded'] as Map<String, dynamic>;
      expect(_result(recorded['notASiteId']), containsPair('message', 'Bigo identity'));
    });
  });

  group('streams', () {
    Future<LiveRoom> entry() => _setup(_live).site.getRoomDetail(roomId: _room);

    test("the one quality and the owned input, as 3.x's, without a request", () async {
      final calls = (_legacy('S03-studio-live')['avatarHttps'] as Map<String, dynamic>)[_room] as Map<String, dynamic>;
      final http = _Scripted((request) => throw StateError('no request expected'));
      final site = BigoSite(http);
      for (final depth in ['getRoomDetail', 'getRoomDetailForRecording', 'getRoomDetailForRefresh']) {
        final setup = _setup(_live);
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _room),
          'getRoomDetailForRecording' => setup.site.getRoomDetailForRecording(roomId: _room),
          _ => setup.site.getRoomDetailForRefresh(roomId: _room),
        };
        final qualities = await site.getPlayQualities(detail: room);
        expect(qualities, [BigoApi.quality], reason: depth);
        final resolution = await site.resolvePlayUrls(detail: room, quality: qualities.single);
        final recovery = await site.resolvePlayUrlsForRecovery(detail: room, quality: qualities.single);
        for (final result in [resolution, recovery]) {
          expect(result.urls, isEmpty);
          expect(result.inputRecipe, BigoInputRecipe(_canonical));
          expect(result.inputRecipe!.identity, 'bigo:qashia305:live');
          expect(result.appliedQualityData, 'live');
          expect(result.hasSources, isTrue);
        }
        expect(await site.getPlayUrls(detail: room, quality: qualities.single), isEmpty);
        if (depth != 'getRoomDetailForRefresh') {
          final legacy = _result(calls['$depth → resolvePlayUrlsRaw'])! as Map<String, dynamic>;
          expect(legacy['inputRecipe'], {'siteId': _canonical, 'identity': resolution.inputRecipe!.identity});
          expect(legacy['urls'], isEmpty);
          expect(legacy['appliedQualityData'], 'live');
        } else {
          // 3.x kept no studio answer in a refreshed room and refused it
          // (mediaUnavailable); the room now carries its access, never a
          // media address, and plays like the others.
          expect(_result(calls['$depth → getPlayQualites']), containsPair('message', 'Bigo mediaUnavailable'));
        }
      }
      expect(http.requests, isEmpty);
    });

    test('what cannot be played says why, without a request', () async {
      final site = BigoSite(_Scripted((request) => throw StateError('no request expected')));
      final room = await entry();
      final card = BigoApi.directory(Fixture.load('bigo', 'S01-list').body).first;
      final notoken = BigoApi.room(
        BigoApi.studio(Fixture.load('bigo', 'S03-studio-notoken').body, requestedSiteId: _room),
      );
      final paid = BigoApi.room(BigoApi.studio(_studio({'passRoom': true, 'hls_src': ''}), requestedSiteId: _room));
      final bare = BigoApi.room(BigoApi.studio(_studio({'hls_src': ''}), requestedSiteId: _room));
      final list = jsonDecode(Fixture.load('bigo', 'S01-list').body) as Map<String, dynamic>;
      ((((list['data'] as Map)['data'] as List).first) as Map)['is_locked'] = 1;
      final locked = BigoApi.directory(jsonEncode(list)).first;
      expect(paid.isLiveNow, isTrue, reason: 'a restricted live room is live (24-2)');
      expect(bare.restriction, LiveRestriction.unplayable);
      for (final (name, detail, matcher) in [
        ('a list card (no studio answer)', card, isA<StreamUnavailable>()),
        (
          'a locked list card (24-2)',
          locked,
          isA<StreamUnavailable>().having((error) => '$error', 'reason', contains('password')),
        ),
        ('a live room without a playlist', bare, isA<StreamUnavailable>()),
        ('offline', room.copyWith(liveStatus: LiveStatus.offline), isA<StreamUnavailable>()),
        ('stored state pending', room.copyWith(liveStatus: LiveStatus.unknown), isA<StreamUnavailable>()),
        (
          "another room's answer",
          LiveRoom(platform: 'bigo', roomId: 'other', liveStatus: LiveStatus.live, data: room.data),
          isA<StreamUnavailable>(),
        ),
        ('login gate', notoken, isA<NeedsLogin>()),
        ('paid room', paid, isA<StreamUnavailable>()),
      ]) {
        await expectLater(site.getPlayQualities(detail: detail), throwsA(matcher), reason: name);
        await expectLater(
          site.resolvePlayUrls(detail: detail, quality: BigoApi.quality),
          throwsA(matcher),
          reason: name,
        );
      }
      await expectLater(
        site.getPlayQualities(
          detail: LiveRoom(platform: 'bilibili', roomId: _canonical, data: room.data),
        ),
        throwsArgumentError,
      );
      await expectLater(
        site.resolvePlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: '原画', id: 'auto'),
        ),
        throwsArgumentError,
        reason: '3.x: mediaUnavailable',
      );
    });

    test('every input opens a fresh token and studio answer (REG-LEASE-005, 007): the playlist line', () async {
      final setup = _setup(_live);
      final recipe = BigoInputRecipe(_room);
      final first = await setup.site.resolveInput(recipe);
      final second = await setup.site.resolveInput(recipe);
      expect(setup.http.requests.map((request) => request.url.path), [
        '/v1/webjs/t',
        '/v1/webjs/status',
        _studioPath,
        '/v1/webjs/t',
        '/v1/webjs/status',
        _studioPath,
      ]);
      expect(setup.http.requests[2].url.queryParameters['siteId'], _room);
      expect(setup.http.requests[0].cancel, isNot(same(setup.http.requests[3].cancel)));
      for (final line in [first, second]) {
        expect(line.url, 'https://47a788a9.cubetecn.com:1451/list_3453520891_2472221860_0.m3u8');
        expect(line.headers, BigoApi.headers);
        expect(line.format, StreamFormat.hls);
        expect(line.lineId, '47a788a9.cubetecn.com');
        expect(line.lease, isNull);
      }
    });

    test('an input of a studio that cannot be played says why', () async {
      final notoken = Fixture.load('bigo', 'S03-studio-notoken').body;
      final gated = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, notoken)]);
      await expectLater(gated.site.resolveInput(BigoInputRecipe(_room)), throwsA(isA<NeedsLogin>()));
      final offline = _setup(
        _live.take(2).toList(),
        extra: [
          _studioAnswer(_room, _studio({'alive': 0, 'hls_src': ''})),
        ],
      );
      await expectLater(offline.site.resolveInput(BigoInputRecipe(_room)), throwsA(isA<StreamUnavailable>()));
      final token = CancelToken()..cancel();
      await expectLater(_setup(_live).site.resolveInput(BigoInputRecipe(_room), cancel: token), _cancelled);
    });
  });

  group('24-4 web token reuse', () {
    test('follow refreshes reuse one token for 30 min: one request each (3.x: three every time)', () async {
      var now = _now;
      final server = _Bigo();
      final site = BigoSite(server.http, now: () => now);
      final first = await site.getRoomDetailForRefresh(roomId: _room);
      expect(server.paths, ['/v1/webjs/t', '/v1/webjs/status', _studioPath]);
      expect(first.restriction, LiveRestriction.none, reason: "the token's first use is complete");
      final again = await site.getRoomDetailForRefresh(roomId: _room);
      expect(server.paths.skip(3), [_studioPath]);
      expect(server.tokens, ['t0k3n1', 't0k3n1']);
      expect(again.isLiveNow, isTrue);
      expect(again.restriction, isNull, reason: 'a used token does not say whether the room is locked');
      expect((again.data! as BigoRoomData).complete, isFalse);
      expect(first.mergeFrom(again).restriction, LiveRestriction.none, reason: 'kept while still live (M2.1)');
      now = now.add(const Duration(minutes: 29, seconds: 59));
      await site.getLiveStatus(roomId: _room);
      expect(server.paths, hasLength(5));
      now = now.add(const Duration(seconds: 1));
      await site.getRoomDetailForRefresh(roomId: _room);
      expect(server.paths.skip(5), ['/v1/webjs/t', '/v1/webjs/status', _studioPath], reason: 'after 30 min');
      expect(server.tokens.last, 't0k3n2');
      now = now.subtract(const Duration(hours: 1));
      await site.getRoomDetailForRefresh(roomId: _room);
      expect(server.tokens.last, 't0k3n3', reason: 'a clock turned back is no reuse');
      expect(BigoSite.tokenReuse, const Duration(minutes: 30));
    });

    test('a follow list refreshed together shares one new token: 2 + N requests (3.x: 3N)', () async {
      final server = _Bigo();
      final site = BigoSite(server.http, now: () => _now);
      final rooms = await Future.wait([
        for (var index = 0; index < 5; index++) site.getRoomDetailForRefresh(roomId: 'room_$index'),
      ]);
      expect(server.paths.where((path) => path == '/v1/webjs/status'), hasLength(1));
      expect(server.paths, hasLength(7));
      expect(server.tokens.toSet(), {'t0k3n1'});
      expect(rooms.where((room) => (room.data! as BigoRoomData).complete), hasLength(1), reason: 'one first use');
      expect(rooms.every((room) => room.isLiveNow), isTrue);
    });

    test('entries, recording details, lookups and inputs take a new token; each used one serves refreshes', () async {
      final server = _Bigo();
      final site = BigoSite(server.http, now: () => _now);
      final entry = await site.getRoomDetail(roomId: _room);
      expect(server.paths, hasLength(3));
      expect(entry.restriction, LiveRestriction.none);
      final refreshed = await site.getRoomDetailForRefresh(roomId: _room);
      expect(server.paths, hasLength(4));
      expect(server.tokens, ['t0k3n1', 't0k3n1'], reason: "the entry's token, used again");
      expect(refreshed.isLiveNow, isTrue);
      final line = await site.resolveInput(BigoInputRecipe(_room));
      expect(server.paths, hasLength(7));
      expect(server.tokens.last, 't0k3n2', reason: 'an input never takes a used token (REG-LEASE-007)');
      expect(line.url, contains('.m3u8'));
      await site.getRoomDetailForRecording(roomId: _room);
      await site.searchRoomsCancellable(_room, cancel: CancelToken());
      expect(server.tokens.skip(3), ['t0k3n3', 't0k3n4']);
      await site.getLiveStatus(roomId: _room);
      expect(server.tokens.last, 't0k3n4', reason: 'the last used token');
      expect(server.paths, hasLength(14));
    });

    test('a room refreshed with a used token plays: the input asks the studio again', () async {
      final server = _Bigo();
      final site = BigoSite(server.http, now: () => _now);
      await site.getRoomDetail(roomId: _room);
      final refreshed = await site.getRoomDetailForRefresh(roomId: _room);
      final count = server.paths.length;
      final qualities = await site.getPlayQualities(detail: refreshed);
      final resolution = await site.resolvePlayUrls(detail: refreshed, quality: qualities.single);
      expect(resolution.inputRecipe, BigoInputRecipe(_canonical));
      expect(server.paths, hasLength(count), reason: 'no request before the input');
      final line = await site.resolveInput(resolution.inputRecipe! as BigoInputRecipe);
      expect(line.lineId, '47a788a9.cubetecn.com');
    });

    test("a gated first use: an entry asks again and keeps the gate with the room's state; a refresh uses the "
        'second answer; an input does not ask again', () async {
      final server = _Bigo(gateFirstUse: true);
      final site = BigoSite(server.http, now: () => _now);
      final entry = await site.getRoomDetail(roomId: _room);
      expect(server.paths, ['/v1/webjs/t', '/v1/webjs/status', _studioPath, _studioPath]);
      expect(server.tokens, ['t0k3n1', 't0k3n1']);
      expect(entry.isLiveNow, isTrue, reason: '3.x: unknown');
      expect(entry.restriction, LiveRestriction.needsLogin);
      expect(entry.notice, BigoApi.loginNotice);
      expect(entry.followGroup, FollowGroup.live);
      await expectLater(site.getPlayQualities(detail: entry), throwsA(isA<NeedsLogin>()));
      final refreshed = await site.getRoomDetailForRefresh(roomId: _room);
      expect(server.paths, hasLength(5), reason: 'the used token answers without the gate');
      expect(refreshed.isLiveNow, isTrue);
      expect(refreshed.restriction, isNull);
      final fresh = _Bigo(gateFirstUse: true);
      final refresh = await BigoSite(fresh.http, now: () => _now).getRoomDetailForRefresh(roomId: _room);
      expect(fresh.paths, hasLength(4));
      expect(refresh.isLiveNow, isTrue);
      expect(refresh.restriction, isNull, reason: 'a refresh does not mark a gate it saw once');
      expect(refresh.notice, BigoApi.chatNotice);
      final input = _Bigo(gateFirstUse: true);
      await expectLater(
        BigoSite(input.http, now: () => _now).resolveInput(BigoInputRecipe(_room)),
        throwsA(isA<NeedsLogin>()),
      );
      expect(input.paths, hasLength(3));
    });

    test('a token turned away twice is dropped: the next refresh takes a new one', () async {
      final server = _Bigo(gateFirstUse: true, gateEveryUse: true);
      final site = BigoSite(server.http, now: () => _now);
      final room = await site.getRoomDetailForRefresh(roomId: _room);
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
      expect(room.restriction, LiveRestriction.needsLogin);
      expect(server.paths, hasLength(4));
      await expectLater(site.getLiveStatus(roomId: _room), throwsA(isA<NeedsLogin>()));
      expect(server.paths, hasLength(8));
      expect(server.tokens, ['t0k3n1', 't0k3n1', 't0k3n2', 't0k3n2']);
    });

    test('a failed token fetch is not kept; a slow one is shared', () async {
      final server = _Bigo(failTokens: 1);
      final site = BigoSite(server.http, now: () => _now);
      await expectLater(site.getRoomDetailForRefresh(roomId: _room), throwsA(isA<NetworkFailure>()));
      expect((await site.getRoomDetailForRefresh(roomId: _room)).isLiveNow, isTrue);
      expect(server.tokens, ['t0k3n1']);
      final slow = _Bigo(delay: true);
      final shared = BigoSite(slow.http, now: () => _now);
      final one = shared.getRoomDetailForRefresh(roomId: 'one');
      final two = shared.getRoomDetailForRefresh(roomId: 'two');
      await Future<void>.delayed(Duration.zero);
      slow.release();
      expect(await Future.wait([one, two]), hasLength(2));
      expect(slow.paths.where((path) => path == '/v1/webjs/status'), hasLength(1));
    });
  });

  group('identity', () {
    test('Bigo ids ignore case: a follow typed in another case merges the refresh and plays (M2.1)', () async {
      expect(SiteIds.ignoresRoomIdCase('bigo'), isTrue);
      final stored = LiveRoom(platform: 'bigo', roomId: 'chrispcritter78', nick: 'stored', tagIds: const ['t']);
      final refreshed = BigoApi.room(
        BigoApi.studio(_studio({'clientBigoId': 'ChrisPCritter78'}), requestedSiteId: 'chrispcritter78'),
      );
      expect(refreshed.roomId, 'ChrisPCritter78', reason: "the site's spelling");
      expect(stored.hasSameIdentity(refreshed), isTrue);
      expect(stored.identityKey, 'bigo:chrispcritter78');
      final merged = stored.mergeFrom(refreshed);
      expect(merged.roomId, 'chrispcritter78', reason: 'the stored spelling stays');
      expect(merged.nick, 'qashia');
      expect(merged.tagIds, ['t']);
      final site = BigoSite(_Scripted((request) => throw StateError('no request expected')));
      final resolution = await site.resolvePlayUrls(detail: merged, quality: BigoApi.quality);
      expect(resolution.inputRecipe, BigoInputRecipe('ChrisPCritter78'));
    });
  });

  group('links', () {
    test('room links through the parser, without a request; site pages and other hosts are not rooms', () async {
      final http = ReplayHttp(const []);
      final registry = SiteRegistry({'bigo': () => BigoSite(http)});
      final parser = LinkParser(registry, http);
      expect(
        await parser.parse('看 https://www.bigo.tv/en/qashia305?from=share 吧'),
        const RoomLink('bigo', 'qashia305'),
      );
      expect(await parser.parse('https://bigo.tv/$_room'), const RoomLink('bigo', _room));
      expect(await parser.parse('https://www.bigo.tv/download'), isNull);
      // 24-7: subdomains and fragments (3.x: not links).
      expect(await parser.parse('https://m.bigo.tv/qashia305'), const RoomLink('bigo', 'qashia305'));
      expect(await parser.parse('来看 https://www.bigo.tv/en/qashia305#live 吧'), const RoomLink('bigo', 'qashia305'));
      expect(parser.containsSupportedLink('https://m.bigo.tv/en/qashia305'), isTrue);
      expect(await parser.parse('https://m.bigo.tv/search'), isNull);
      expect(http.requests, isEmpty);
      final site = registry.of('bigo') as BigoSite;
      expect(site.roomIdFromUrl('https://www.bigo.tv/qashia305#x'), 'qashia305', reason: '24-7 (3.x: null)');
      expect(site.needsResolving('https://www.bigo.tv/qashia305'), isFalse);
      expect(parser.containsSupportedLink('https://www.bigo.tv/qashia305'), isTrue);
    });

    test('a subdomain link is looked up in the search like any room link (24-7)', () async {
      final setup = _setup([..._list, ..._live]);
      final rooms = await setup.site.searchRoomsCancellable('https://m.bigo.tv/$_room#top', cancel: CancelToken());
      expect(rooms.single.roomId, _canonical);
      expect(setup.http.requests.last.url.queryParameters['siteId'], _room);
    });
  });
}
