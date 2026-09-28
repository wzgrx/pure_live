// BigoSite over the recorded Bigo responses (ReplayHttp) and a few synthetic
// ones: the request headers, the web token before every studio request, the
// shared list and its 30 s reuse, the directory pages and 3.x's slices, the
// search's lookups and filter, rooms at every depth, the owned input and its
// fresh studio answer per consumer, cancellation, the deadline, links and the
// error mapping. Requests are compared with the ones 3.x sent (expected.json
// records them). The token's random `callback`, `data` and `token` values
// are left out of matching; the callback names are the recorded ones.
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
/// except [changed].
void _expectParity(LiveRoom room, Object? legacy, {Set<String> changed = const {}, String reason = ''}) {
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
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Bigo chat');
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
    test('shared for 30 s by callers without a token (3.x); a fetch with a token is new and not shared', () async {
      var now = _now;
      final setup = _setup(_list, now: () => now);
      final legacy = _legacy('S01-list');
      await setup.site.getRecommendRooms();
      await setup.site.getCategoryRooms(BigoApi.area);
      await setup.site.searchRooms('Pk');
      await setup.site.getDirectoryPage();
      expect(setup.http.requests, hasLength(1));
      await setup.site.getDirectoryPage(cancel: CancelToken());
      expect(_sent(setup.http.requests), _legacyRequests(legacy['cache']), reason: "3.x's requests");
      now = now.add(const Duration(seconds: 29));
      await setup.site.getRecommendRooms(page: 2, pageSize: 8);
      expect(setup.http.requests, hasLength(2));
      now = now.add(const Duration(seconds: 1));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(3), reason: 'a list 30 s old is fetched again');
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
        // avatar, cover: the recorded http avatar (3.x failed on it).
        _expectParity(rooms.single, (_result(twin)! as List).single, changed: {'avatar', 'cover'}, reason: keyword);
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
        // avatar, cover: the recorded http avatar (3.x failed the room on it).
        _expectParity(room, _result(calls[depth]), changed: {'avatar', 'cover'}, reason: depth);
        expect(room.avatar, startsWith('http://esx.bigo.sg/'));
        expect(_sent(setup.http.requests), _legacyRequests(calls[depth]), reason: depth);
        expect((room.data! as BigoRoomData).hasStream, isTrue);
        final https = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, _avatarHttps())]);
        _expectParity(await detail(https.site), _result(calls[depth]), reason: '$depth (https avatar)');
      }
      final recorded = (_legacy('S03-studio-live')['recorded'] as Map<String, dynamic>)[_room] as Map<String, dynamic>;
      expect(_result(recorded['getRoomDetail']), containsPair('message', 'Bigo schema'));
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

    test('the live status: true (three requests); a gate is an error, never offline (3.x unknownState)', () async {
      final live = _setup(_live);
      expect(await live.site.getLiveStatus(roomId: _room), isTrue);
      expect(live.http.requests, hasLength(3));
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
      final calls = (_legacy('S03-studio-notoken')['asTokenAnswer'] as Map<String, dynamic>)[_room] as Map;
      expect(_result(calls['getLiveStatus']), containsPair('message', 'Bigo unknownState'));
      final paid = _setup(
        _live.take(2).toList(),
        extra: [
          _studioAnswer(_room, _studio({'isPaidShow': '1', 'hls_src': ''})),
        ],
      );
      await expectLater(paid.site.getLiveStatus(roomId: _room), throwsA(isA<StreamUnavailable>()));
      final bare = _setup(
        _live.take(2).toList(),
        extra: [
          _studioAnswer(_room, _studio({'hls_src': ''})),
        ],
      );
      await expectLater(bare.site.getLiveStatus(roomId: _room), throwsA(isA<StreamUnavailable>()));
    });

    test('a gated studio: the room opens with its state unknown and the login notice (3.x)', () async {
      final notoken = Fixture.load('bigo', 'S03-studio-notoken').body;
      final calls = (_legacy('S03-studio-notoken')['asTokenAnswer'] as Map<String, dynamic>)[_room] as Map;
      final setup = _setup(_live.take(2).toList(), extra: [_studioAnswer(_room, notoken)]);
      final room = await setup.site.getRoomDetail(roomId: _room);
      _expectParity(room, _result(calls['getRoomDetail']));
      expect(room.effectiveLiveStatus, LiveStatus.unknown);
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
      for (final (name, detail, matcher) in [
        ('a list card (no studio answer)', card, isA<StreamUnavailable>()),
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
      expect(await parser.parse('https://m.bigo.tv/qashia305'), isNull);
      expect(http.requests, isEmpty);
      final site = registry.of('bigo') as BigoSite;
      expect(site.roomIdFromUrl('https://www.bigo.tv/qashia305#x'), isNull, reason: '3.x');
      expect(site.needsResolving('https://www.bigo.tv/qashia305'), isFalse);
      expect(parser.containsSupportedLink('https://www.bigo.tv/qashia305'), isTrue);
    });
  });
}
