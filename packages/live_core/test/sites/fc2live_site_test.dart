// Fc2LiveSite over the recorded FC2 Live responses (ReplayHttp), a few
// synthetic ones and the recorded control socket (a fake WebSocket replaying
// fixtures/fc2live/control/S04-control): the form POSTs and their headers,
// the shared snapshot and its 20 s reuse, the directory pages and 3.x's
// slices, the search (keywords and exact channels), room details at every
// depth, qualities and the recipe, the control grant and the control socket,
// cancellation, links and the error mapping. Requests are compared with the
// ones 3.x sent (expected.json records them). Ports the site part of 3.x's
// test/fc2live_site_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/fc2live';
const _live = '62996200';
const _offline = '10608314';
const _restricted = '3024638';
const _missing = '99999999';

const _members = ['S02-member-live', 'S02-member-offline', 'S02-member-restricted', 'S02-member-missing'];

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// 3.x's API headers (`Fc2Api.headers`) with its form content type.
const Map<String, String> _apiHeaders = {
  'user-agent': _userAgent,
  'accept': 'application/json, text/javascript, */*; q=0.01',
  'accept-language': 'ja,en-US;q=0.9,en;q=0.8',
  'origin': 'https://live.fc2.com',
  'referer': 'https://live.fc2.com/',
  'x-requested-with': 'XMLHttpRequest',
  'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
};

typedef _Setup = ({Fc2LiveSite site, ReplayHttp http});

_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  DateTime Function()? now,
  SocketConnector? connector,
  ProxyPolicy proxy = const FixedProxyPolicy(),
  Duration controlStartupTimeout = const Duration(seconds: 20),
}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (
    site: Fc2LiveSite(http, now: now, connector: connector, proxy: proxy, controlStartupTimeout: controlStartupTimeout),
    http: http,
  );
}

/// A synthetic form POST answer to [path] for [form].
ReplaySample _synthetic(String path, Map<String, String> form, Object body, {int status = 200}) => ReplaySample(
  method: 'POST',
  url: Uri.https('live.fc2.com', path),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
  form: form,
);

Map<String, String> _memberForm(String channel) => {'channel': '1', 'profile': '1', 'user': '1', 'streamid': channel};

/// The S02-member-live answer with [edit] applied to its channel_data.
ReplaySample _editedMember(void Function(Map<String, dynamic> channel) edit) {
  final root = jsonDecode(Fixture.load('fc2live', 'S02-member-live').body) as Map<String, dynamic>;
  edit((root['data'] as Map<String, dynamic>)['channel_data'] as Map<String, dynamic>);
  return _synthetic('/api/memberApi.php', _memberForm(_live), root);
}

/// Requests as 3.x's harness wrote them: `POST <path> <form>`.
List<String> _sent(Iterable<LiveRequest> requests) => [
  for (final request in requests)
    () {
      final form = Uri.splitQueryString(utf8.decode(request.body ?? const []));
      final fields = form.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
      return '${request.method} ${request.url.path}${fields.isEmpty ? '' : ' $fields'}';
    }(),
];

Map<String, dynamic> _legacy(String sample) => Fixture.load('fc2live', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<String> _legacyRequests(Object? traced) => ((traced! as Map<String, dynamic>)['requests'] as List).cast<String>();

List<String> _ids(List<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

List<Object?> _legacyIds(Object? traced) => [for (final room in _result(traced)! as List) (room as Map)['roomId']];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

LiveArea _area(String id) => Fc2LiveApi.category().children.singleWhere((area) => area.areaId == id);

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
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    throw TransportFailure('fc2live', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('fc2live', reason, 'test');

  @override
  void close() {}
}

// The control socket ----------------------------------------------------------

/// The server's messages in the recorded control conversation, in order.
List<String> _serverFrames() => [
  for (final line in File('$_root/control/S04-control/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty)
      if (jsonDecode(line) case {'dir': 'in', 'text': final String text}) text,
];

String _message(String name, [Object? arguments]) => jsonEncode({'name': name, 'arguments': arguments ?? {}});

/// A fake WebSocket: what the server said is queued before the control
/// listens.
final class _Channel implements SocketChannel {
  new([List<Object> server = const []]) {
    server.forEach(incoming.add);
  }

  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<String> sent = [];
  bool closed = false;
  Completer<void>? closeGate;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('send failed');
    sent.add(data as String);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    await closeGate?.future;
  }

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

/// Hands out [channels] in order; [gate] holds the handshake.
final class _Connector {
  new(this.channels);

  final List<_Channel> channels;
  final List<({Uri endpoint, Map<String, String> headers, ProxyRoute route, Duration timeout})> calls = [];
  Completer<void>? gate;
  Exception? failure;

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    calls.add((endpoint: endpoint, headers: headers, route: route, timeout: connectTimeout));
    final error = failure;
    if (error != null) throw error;
    final channel = channels.removeAt(0);
    await gate?.future;
    return channel;
  }
}

final class _Proxy implements ProxyPolicy {
  final List<(String, Uri)> asked = [];

  @override
  ProxyRoute routeFor(String site, Uri url) {
    asked.add((site, url));
    return const HttpProxyRoute('127.0.0.1', 7890);
  }
}

/// A site with the live channel's member and grant answers and [channel]
/// behind the connector.
({Fc2LiveSite site, ReplayHttp http, _Connector connector}) _controlSetup(
  _Channel channel, {
  Duration startup = const Duration(seconds: 20),
  ProxyPolicy proxy = const FixedProxyPolicy(),
}) {
  final connector = _Connector([channel]);
  final setup = _setup(
    ['S02-member-live', 'S03-control'],
    connector: connector.call,
    proxy: proxy,
    controlStartupTimeout: startup,
  );
  return (site: setup.site, http: setup.http, connector: connector);
}

void main() {
  group('requests', () {
    test("3.x's form POSTs: its headers, redirects not followed, sent as fc2live", () async {
      final setup = _setup(['S01-directory', 'S02-member-live', 'S03-control']);
      await setup.site.getRecommendRooms();
      await setup.site.getRoomDetail(roomId: _live);
      await setup.site.controlGrant(_live);
      expect(_sent(setup.http.requests), [
        'POST /contents/allchannellist.php',
        'POST /api/memberApi.php channel=1&profile=1&user=1&streamid=62996200',
        ..._legacyRequests(_legacy('S02-member-live')['Fc2Api.controlGrant']),
      ]);
      for (final request in setup.http.requests) {
        expect(request.url.host, 'live.fc2.com');
        expect(request.url.scheme, 'https');
        expect(request.headers, _apiHeaders);
        expect(request.followRedirects, isFalse);
        expect(request.site, 'fc2live');
        expect(request.timeout, defaultRequestTimeout);
      }
    });

    test("the platform: 3.x's id, name and directory note; no danmaku, account or cookie", () {
      final site = _setup(const []).site;
      expect((site.id, site.name, site.directoryNoticeKey), ('fc2live', 'FC2 Live', 'fc2live_directory_scope'));
      expect(site.getDanmaku(), isA<EmptyDanmaku>());
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isNot(isA<LivePlayUrlCursorResolver>()));
      expect(site, isNot(isA<LiveQualityDiscovery>()));
      expect(Fc2LiveControl.pingInterval, const Duration(seconds: 15), reason: "3.x's control ping");
    });

    test('transport failures are NetworkFailure; a cancellation stays a cancellation', () async {
      for (final reason in [TransportReason.timeout, TransportReason.connect, TransportReason.tls]) {
        final site = Fc2LiveSite(_Failing(reason));
        await expectLater(site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()), reason: '$reason');
      }
      await expectLater(Fc2LiveSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: _live), _cancelled);
    });

    test("HTTP statuses map as 3.x's did; redirects are not followed", () async {
      for (final (status, matcher) in [
        (302, isA<NetworkFailure>()),
        (400, isA<ApiChanged>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (502, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => LiveResponse(status: status, bytes: utf8.encode('{}'), url: request.url));
        await expectLater(Fc2LiveSite(http).getRoomDetail(roomId: _live), throwsA(matcher), reason: '$status');
        await expectLater(Fc2LiveSite(http).getRecommendRooms(), throwsA(matcher), reason: '$status');
      }
    });
  });

  group('snapshot', () {
    test('reused for 20 s without a cancel token, as 3.x; fetched anew after', () async {
      var now = DateTime.utc(2026, 9, 28, 12);
      final setup = _setup(['S01-directory'], now: () => now);
      await setup.site.getRecommendRooms();
      await setup.site.getCategoryRooms(_area('1'));
      await setup.site.searchRooms('猫');
      expect(setup.http.requests, hasLength(1));
      now = now.add(const Duration(seconds: 19));
      await setup.site.getRecommendRooms(page: 2);
      expect(setup.http.requests, hasLength(1));
      now = now.add(const Duration(seconds: 2));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(2));
    });

    test("a cancel token always fetches anew and leaves the shared one alone (3.x's `cache`)", () async {
      final setup = _setup(['S01-directory']);
      await setup.site.getRecommendRooms();
      await setup.site.getCategoryRooms(_area('1'));
      await setup.site.searchRooms('猫');
      await setup.site.getDirectoryPage(cancel: CancelToken());
      expect(_sent(setup.http.requests), _legacyRequests(_legacy('S01-directory')['cache']));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(2), reason: 'the shared snapshot is still the first one');
    });

    test('concurrent callers share the fetch under way; a failed fetch is forgotten', () async {
      final gate = Completer<void>();
      var fail = true;
      final body = Fixture.load('fc2live', 'S01-directory').body;
      final http = _Scripted((request) async {
        await gate.future;
        if (fail) throw const TransportFailure('fc2live', TransportReason.connect, 'down');
        return LiveResponse(status: 200, bytes: utf8.encode(body), url: request.url);
      });
      final site = Fc2LiveSite(http);
      final first = site.getRecommendRooms();
      final second = site.getCategoryRooms(_area('9'));
      gate.complete();
      await expectLater(first, throwsA(isA<NetworkFailure>()));
      await expectLater(second, throwsA(isA<NetworkFailure>()));
      expect(http.requests, hasLength(1));
      fail = false;
      expect(await site.getRecommendRooms(), hasLength(30));
      expect(http.requests, hasLength(2));
    });
  });

  group('catalog', () {
    test('the one category and six areas without a request; only page 1 (3.x)', () async {
      final setup = _setup(const []);
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.single.children.map((area) => area.areaId), ['all', '1', '2', '4', '9', '5']);
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(await setup.site.getCategories(1, 0), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('directory pages match 3.x, one request each (every page and area of the legacy run)', () async {
      final pages = _legacy('S01-directory')['getDirectoryPage'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in pages.entries) {
        final want = _result(value);
        if (want is! Map<String, dynamic> || !want.containsKey('rooms')) continue;
        final [area, number] = key.split(':');
        final setup = _setup(['S01-directory']);
        final page = await setup.site.getDirectoryPage(
          page: int.parse(number),
          category: area == 'recommend' ? null : _area(area),
          cancel: CancelToken(),
        );
        expect(_ids(page.rooms), [for (final room in want['rooms'] as List) (room as Map)['roomId']], reason: key);
        expect((page.page, page.hasMore), (want['page'], want['hasMore']), reason: key);
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: key);
      }
      final audio = await _setup(['S01-directory']).site.getDirectoryPage(category: _area('9'));
      expect(_ids(audio.rooms), ['25958804', '75095119'], reason: 'the two audio channels');
    });

    test('caller errors send nothing: a page below 1, an unknown area, another platform', () async {
      final setup = _setup(['S01-directory']);
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsA(isA<RangeError>()));
      const three = LiveArea(platform: 'fc2live', areaType: 'public', areaId: '3', areaName: '3');
      const other = LiveArea(platform: 'bilibili', areaType: 'public', areaId: '1', areaName: 'x');
      const wrongType = LiveArea(platform: 'fc2live', areaType: 'genre', areaId: '1', areaName: 'x');
      for (final area in [three, other, wrongType]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError);
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError);
      }
      expect(setup.http.requests, isEmpty);
    });

    test("3.x's slices; a slice 3.x served nothing for sends nothing now", () async {
      final legacy = _legacy('S01-directory');
      for (final MapEntry(:key, :value) in (legacy['getRecommendRooms'] as Map<String, dynamic>).entries) {
        final [_, page, _, size] = key.split(' ');
        final setup = _setup(['S01-directory']);
        final rooms = await setup.site.getRecommendRooms(page: int.parse(page), pageSize: int.parse(size));
        expect(_ids(rooms), _legacyIds(value), reason: key);
        final valid = Fc2LiveApi.validSlice(page: int.parse(page), pageSize: int.parse(size));
        expect(setup.http.requests, hasLength(valid ? 1 : 0), reason: key);
      }
      for (final MapEntry(:key, :value) in (legacy['getCategoryRooms'] as Map<String, dynamic>).entries) {
        final [id, _, page, _, size] = key.split(' ');
        if (id == '3') continue;
        final rooms = await _setup(['S01-directory']).site
            .getCategoryRooms(_area(id), page: int.parse(page), pageSize: int.parse(size));
        expect(_ids(rooms), _legacyIds(value), reason: key);
      }
    });
  });

  group('search', () {
    test('keywords filter a fresh snapshot, as 3.x (same rooms, same request)', () async {
      final search = _legacy('S01-directory')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      for (final keyword in ['ちゅうや', '猫', 'idle chat', '0200', 'zxqvnoresultfixture']) {
        final setup = _setup(['S01-directory']);
        final rooms = await setup.site.searchRoomsCancellable(keyword, pageSize: 20, cancel: CancelToken());
        expect(_ids(rooms), _legacyIds(search['$keyword page 1']), reason: keyword);
        expect(_sent(setup.http.requests), _legacyRequests(search['$keyword page 1']), reason: keyword);
      }
      for (final page in [1, 2, 3]) {
        final rooms = await _setup(['S01-directory']).site.searchRooms('fc2user', page: page, pageSize: 5);
        expect(_ids(rooms), _legacyIds(search['fc2user page $page size 5']), reason: 'page $page');
      }
    });

    test('a channel number or link is looked up: one member request, offline channels found too', () async {
      final search = _legacy('S01-directory')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      for (final keyword in [_live, 'https://live.fc2.com/ja/62996200/', _restricted]) {
        final setup = _setup(_members);
        final rooms = await setup.site.searchRooms(keyword, pageSize: 20);
        expect(_ids(rooms), _legacyIds(search['exact $keyword']), reason: keyword);
        expect(_sent(setup.http.requests), _legacyRequests(search['exact $keyword']), reason: keyword);
      }
      // 3.x failed on both ('schema'); its search meant to give the offline
      // channel and nothing for a channel that does not exist.
      final offline = await _setup(_members).site.searchRooms(_offline);
      expect(offline.single.liveStatus, LiveStatus.offline);
      final missing = _setup(_members);
      expect(await missing.site.searchRooms(_missing), isEmpty);
      expect(missing.http.requests, hasLength(1));
    });

    test('blank keywords, later pages of an exact channel and bad slices send nothing', () async {
      final setup = _setup(_members);
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(await setup.site.searchRooms(_live, page: 2), isEmpty);
      expect(await setup.site.searchRooms('猫', page: 0), isEmpty);
      expect(await setup.site.searchRooms('猫', pageSize: 101), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('the cancel token reaches the request; a cancelled search sends nothing and drops a late answer', () async {
      final setup = _setup(['S01-directory', ..._members]);
      final token = CancelToken();
      await setup.site.searchRoomsCancellable('猫', cancel: token);
      await setup.site.searchRoomsCancellable(_live, cancel: token);
      expect(setup.http.requests.map((request) => request.cancel), everyElement(same(token)));
      token.cancel();
      await expectLater(setup.site.searchRoomsCancellable('猫', cancel: token), _cancelled);
      await expectLater(setup.site.searchRoomsCancellable(_live, cancel: token), _cancelled);
      expect(setup.http.requests, hasLength(2));

      final late = CancelToken();
      final http = _Scripted((request) {
        late.cancel();
        return LiveResponse(
          status: 200,
          bytes: utf8.encode(Fixture.load('fc2live', 'S01-directory').body),
          url: request.url,
        );
      });
      await expectLater(Fc2LiveSite(http).searchRoomsCancellable('猫', cancel: late), _cancelled);
    });
  });

  group('rooms', () {
    test('one member request at every depth, as 3.x; the room id is the channel number', () async {
      final legacy = _legacy('S02-member-live');
      final setup = _setup(['S02-member-live']);
      final entry = await setup.site.getRoomDetail(roomId: _live);
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final recording = await setup.site.getRoomDetailForRecording(roomId: ' $_live ');
      final link = await setup.site.getRoomDetail(roomId: 'https://live.fc2.com/62996200/');
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect([entry, refresh, recording, link].map((room) => room.roomId), everyElement(_live));
      expect(_sent(setup.http.requests), [
        for (final call in [
          'getRoomDetail',
          'getRoomDetailForRefresh',
          'getRoomDetailForRecording',
          'getRoomDetail(link)',
          'getLiveStatus',
        ])
          ..._legacyRequests(legacy[call]),
      ]);
      expect(entry.title, (_result(legacy['getRoomDetail'])! as Map)['title']);
    });

    test('a room id that is not a channel is NotFound without a request', () async {
      final setup = _setup(const []);
      for (final id in ['', '0', 'abc', 'https://live.fc2.com/rank/', 'https://example.com/62996200/']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getLiveStatus(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
    });

    test("offline, restricted and missing channels (3.x: 'schema', unknown, 'schema')", () async {
      final setup = _setup(_members);
      final offline = await setup.site.getRoomDetailForRefresh(roomId: _offline);
      expect(offline.liveStatus, LiveStatus.offline);
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
      final restricted = await setup.site.getRoomDetail(roomId: _restricted);
      expect(restricted.liveStatus, LiveStatus.unknown);
      expect(restricted.notice, Fc2LiveApi.noticeText['fc2live_access_restricted']);
      await expectLater(setup.site.getLiveStatus(roomId: _restricted), throwsA(isA<NeedsLogin>()));
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: _missing), throwsA(isA<NotFound>()));
    });

    test('a follow 3.x stored merges with the fresh room (same identity; stored headers kept)', () async {
      final stored = LiveRoom.fromJson(
        (_result(_legacy('S02-member-live')['getRoomDetail'])! as Map<String, dynamic>).cast<String, Object?>(),
      );
      final fresh = await _setup(['S02-member-live']).site.getRoomDetailForRefresh(roomId: stored.roomId);
      expect(fresh.hasSameIdentity(stored), isTrue);
      final merged = stored.mergeFrom(fresh);
      expect(merged.identityKey, 'fc2live:62996200');
      expect(merged.onlineViewers, '127');
      expect(merged.httpHeaders, stored.httpHeaders, reason: 'mergeFrom replaces headers only for IPTV');
    });
  });

  group('streams', () {
    test("3.x's one quality for a live room from entry, refresh or a card; no request", () async {
      final setup = _setup(['S02-member-live', 'S01-directory']);
      final entry = await setup.site.getRoomDetail(roomId: _live);
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final card = (await setup.site.getRecommendRooms()).first;
      final requests = setup.http.requests.length;
      for (final room in [entry, refresh, card]) {
        final qualities = await setup.site.getPlayQualities(detail: room);
        expect(qualities.single.selectionId, 'auto');
        expect(qualities.single.quality, '自适应 HLS');
      }
      expect(setup.http.requests, hasLength(requests));
    });

    test("the recipe: no URL, 3.x's identity, the same for recovery; no request", () async {
      final setup = _setup(['S02-member-live']);
      final detail = await setup.site.getRoomDetail(roomId: _live);
      const quality = Fc2LiveApi.autoQuality;
      final resolution = await setup.site.resolvePlayUrlsRaw(detail: detail, quality: quality);
      expect(resolution.urls, isEmpty);
      expect(resolution.lines, isEmpty);
      expect(resolution.inputRecipe, Fc2LiveInputRecipe(_live));
      expect(resolution.inputRecipe?.identity, _legacy('S02-member-live')['Fc2InputRecipe.identity']);
      expect(resolution.appliedQualityData, 'auto');
      expect(resolution.lineCount, 1);
      final recovery = await setup.site.resolvePlayUrlsForRecovery(detail: detail, quality: quality);
      expect(recovery.inputRecipe, resolution.inputRecipe);
      expect(await setup.site.getPlayUrls(detail: detail, quality: quality), isEmpty);
      final unified = await setup.site.resolvePlayUrls(detail: detail, quality: quality);
      expect(
        resolveAppliedPlayQuality(qualities: const [quality], requested: quality, resolution: unified),
        same(quality),
      );
      expect(setup.http.requests, hasLength(1));
    });

    test('rooms that cannot be played are refused before any request', () async {
      final setup = _setup(_members);
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      final restricted = await setup.site.getRoomDetail(roomId: _restricted);
      final requests = setup.http.requests.length;
      const quality = Fc2LiveApi.autoQuality;
      await expectLater(setup.site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.resolvePlayUrlsRaw(detail: offline, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(setup.site.getPlayQualities(detail: restricted), throwsA(isA<NeedsLogin>()));
      await expectLater(
        setup.site.resolvePlayUrlsRaw(detail: restricted, quality: quality),
        throwsA(isA<NeedsLogin>()),
      );
      final pending = LiveRoom(platform: 'fc2live', roomId: _live, liveStatus: LiveStatus.unknown);
      await expectLater(setup.site.getPlayQualities(detail: pending), throwsA(isA<StreamUnavailable>()));
      final other = LiveRoom(platform: 'bilibili', roomId: _live, liveStatus: LiveStatus.live);
      await expectLater(setup.site.getPlayQualities(detail: other), throwsArgumentError);
      final bad = LiveRoom(platform: 'fc2live', roomId: 'abc', liveStatus: LiveStatus.live);
      await expectLater(setup.site.getPlayQualities(detail: bad), throwsA(isA<NotFound>()));
      final live = await _setup(['S02-member-live']).site.getRoomDetail(roomId: _live);
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: live,
          quality: const LivePlayQuality(quality: '原画', id: 'original'),
        ),
        throwsArgumentError,
      );
      expect(setup.http.requests, hasLength(requests));
    });
  });

  group('control grant', () {
    test("member, then getControlServer with the channel's version: 3.x's requests and grant", () async {
      final legacy = _legacy('S02-member-live')['Fc2Api.controlGrant'];
      final setup = _setup(['S02-member-live', 'S03-control']);
      final grant = await setup.site.controlGrant(_live);
      expect(_sent(setup.http.requests), _legacyRequests(legacy));
      expect({
        'channelId': grant.channelId,
        'webSocket': '${grant.socket}',
        'controlToken': grant.controlToken,
        'orz': grant.orz,
      }, _result(legacy));
      expect((await _setup(['S02-member-live', 'S03-control']).site.controlGrant(' $_live ')).channelId, _live);
    });

    test('offline is StreamUnavailable, restricted NeedsLogin, missing NotFound: no grant request', () async {
      final setup = _setup(_members);
      await expectLater(setup.site.controlGrant(_offline), throwsA(isA<StreamUnavailable>()));
      await expectLater(setup.site.controlGrant(_restricted), throwsA(isA<NeedsLogin>()));
      await expectLater(setup.site.controlGrant(_missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.controlGrant('abc'), throwsA(isA<NotFound>()));
      expect(setup.http.requests.map((request) => request.url.path), everyElement('/api/memberApi.php'));
      expect(setup.http.requests, hasLength(3));
    });

    test('a live channel without a version, or a refused grant, fails without a socket', () async {
      final noVersion = _setup(const [], extra: [_editedMember((channel) => channel['version'] = '')]);
      await expectLater(noVersion.site.controlGrant(_live), throwsA(isA<ApiChanged>()));
      expect(noVersion.http.requests, hasLength(1));
      final refused = _setup(
        ['S02-member-live'],
        extra: [
          ReplaySample(
            method: 'POST',
            url: Uri.parse('https://live.fc2.com/api/getControlServer.php'),
            status: 200,
            bytes: utf8.encode(jsonEncode({'status': 2})),
          ),
        ],
      );
      await expectLater(refused.site.openControl(_live), throwsA(isA<StreamUnavailable>()));
    });
  });

  group('control socket', () {
    test("the recorded conversation: 3.x's handshake, one get_hls_information, 3.x's master", () async {
      final channel = _Channel(_serverFrames());
      final proxy = _Proxy();
      final setup = _controlSetup(channel, proxy: proxy);
      final control = await setup.site.openControl(_live);
      addTearDown(control.close);
      final call = setup.connector.calls.single;
      final grant = Fc2LiveApi.grant(Fixture.load('fc2live', 'S03-control').body, channelId: _live);
      expect(call.endpoint, grant.endpoint);
      expect(call.endpoint.queryParameters['control_token'], grant.controlToken);
      expect(call.headers, {
        'origin': 'https://live.fc2.com',
        'user-agent': _userAgent,
        'cookie': 'l_ortkn=${grant.orz}',
      });
      expect(call.route, const HttpProxyRoute('127.0.0.1', 7890));
      expect(proxy.asked.single, ('fc2live', grant.socket));
      expect(call.timeout, const Duration(seconds: 20));
      expect(channel.sent, [Fc2LiveControl.hlsRequest]);
      expect('${control.master}', _legacy('control/S04-control')[_live]);
      expect(control.mediaHeaders, Fc2LiveApi.mediaHeaders(_live));
      expect(control.channelId, _live);
      expect(control.isClosed, isFalse);
      await control.close();
      expect(control.isClosed, isTrue);
      expect(channel.closed, isTrue);
      expect(await control.done, isNull);
      await control.close();
    });

    test('get_hls_information goes out once, only after connect_complete', () async {
      final channel = _Channel([
        _message('initial_connect'),
        _message('connect_complete'),
        _message('connect_complete'),
      ]);
      final setup = _controlSetup(channel);
      final opening = setup.site.openControl(_live);
      await pumpEventQueue();
      expect(channel.sent, [Fc2LiveControl.hlsRequest]);
      channel.incoming.add(jsonEncode(jsonDecode(_serverFrames().firstWhere((text) => text.contains('_response_')))));
      final control = await opening;
      expect(channel.sent, hasLength(1));
      await control.close();
    });

    test('an answer before the request is not taken; the start waits and times out', () async {
      final answer = _serverFrames().firstWhere((text) => text.contains('_response_'));
      final channel = _Channel([answer]);
      final setup = _controlSetup(channel, startup: const Duration(milliseconds: 50));
      await expectLater(setup.site.openControl(_live), throwsA(isA<NetworkFailure>()));
      expect(channel.sent, isEmpty);
      expect(channel.closed, isTrue);
    });

    test('ends after opening: control_disconnection, the server closing, a binary or malformed frame', () async {
      for (final (reason, frame, matcher) in <(String, Object?, Matcher)>[
        ('disconnection', _message('control_disconnection', {'code': 4500}), isA<NetworkFailure>()),
        ('server closed', null, isA<NetworkFailure>()),
        ('binary frame', <int>[1, 2, 3], isA<ApiChanged>()),
        ('not JSON', '{', isA<ApiChanged>()),
        ('not an object', '[1]', isA<ApiChanged>()),
        ('over 2 MiB', 'x' * (Fc2LiveControl.messageLimit + 1), isA<ApiChanged>()),
      ]) {
        final channel = _Channel(_serverFrames());
        final setup = _controlSetup(channel);
        final control = await setup.site.openControl(_live);
        if (frame == null) {
          await channel.incoming.close();
        } else {
          channel.incoming.add(frame);
        }
        expect(await control.done, matcher, reason: reason);
        expect(control.isClosed, isTrue, reason: reason);
        expect(channel.closed, isTrue, reason: reason);
      }
    });

    test('user counts, comments and the rest grant nothing and end nothing', () async {
      final channel = _Channel(_serverFrames());
      final control = await _controlSetup(channel).site.openControl(_live);
      channel.incoming
        ..add(_message('user_count', {'pc_user_count': 1}))
        ..add(_message('ng_comment'))
        ..add(
          jsonEncode({
            'name': '_response_',
            'id': 1,
            'arguments': {'status': 1},
          }),
        );
      await pumpEventQueue();
      expect(control.isClosed, isFalse, reason: 'a later answer is not read again');
      await control.close();
    });

    test('the HLS answer refuses the stream (status) or names no master: the open fails', () async {
      for (final (arguments, matcher) in <(Map<String, Object?>, Matcher)>[
        ({'status': 3}, isA<StreamUnavailable>()),
        ({'status': 0, 'playlists': <Object?>[]}, isA<ApiChanged>()),
      ]) {
        final channel = _Channel([
          _message('connect_complete'),
          jsonEncode({'name': '_response_', 'id': 1, 'arguments': arguments}),
        ]);
        await expectLater(_controlSetup(channel).site.openControl(_live), throwsA(matcher));
        expect(channel.closed, isTrue);
      }
    });

    test('startup: a silent server times out; a failed handshake is a NetworkFailure', () async {
      final silent = _Channel([_message('connect_complete')]);
      final setup = _controlSetup(silent, startup: const Duration(milliseconds: 50));
      await expectLater(setup.site.openControl(_live), throwsA(isA<NetworkFailure>()));
      expect(silent.closed, isTrue);

      final refused = _controlSetup(_Channel());
      refused.connector.failure = const SocketException('refused');
      await expectLater(refused.site.openControl(_live), throwsA(isA<NetworkFailure>()));
    });

    test('cancellation: nothing opens once cancelled; a late handshake is closed at once', () async {
      final token = CancelToken()..cancel();
      final early = _controlSetup(_Channel(_serverFrames()));
      await expectLater(early.site.openControl(_live, cancel: token), _cancelled);
      expect(early.http.requests, isEmpty);
      expect(early.connector.calls, isEmpty);

      final channel = _Channel(_serverFrames());
      final setup = _controlSetup(channel);
      setup.connector.gate = Completer<void>();
      final cancel = CancelToken();
      final opening = setup.site.openControl(_live, cancel: cancel);
      while (setup.connector.calls.isEmpty) {
        await pumpEventQueue();
      }
      cancel.cancel();
      await expectLater(opening, _cancelled);
      setup.connector.gate!.complete();
      await pumpEventQueue();
      expect(channel.closed, isTrue, reason: 'the handshake finished after the control ended');
      expect(channel.sent, isEmpty);

      final opened = _Channel(_serverFrames());
      final owner = CancelToken();
      final control = await _controlSetup(opened).site.openControl(_live, cancel: owner);
      owner.cancel();
      await pumpEventQueue();
      expect((control.isClosed, opened.closed), (false, false), reason: 'once open, the owner closes it (3.x)');
      await control.close();
    });

    test('REG-LEASE-017: every open takes its own grant and socket; nothing private reaches the room', () async {
      final first = _Channel(_serverFrames());
      final second = _Channel(_serverFrames());
      final connector = _Connector([first, second]);
      final setup = _setup(['S02-member-live', 'S03-control'], connector: connector.call);
      final playback = await setup.site.openControl(_live);
      final recording = await setup.site.openControl(_live);
      final grant = _legacyRequests(_legacy('S02-member-live')['Fc2Api.controlGrant']);
      expect(_sent(setup.http.requests), [...grant, ...grant]);
      expect(connector.calls, hasLength(2));
      await playback.close();
      expect((first.closed, second.closed, recording.isClosed), (true, false, false));
      await recording.close();
      final room = jsonEncode((await setup.site.getRoomDetail(roomId: _live)).toJson());
      for (final secret in [playback.grant.controlToken, playback.grant.orz, playback.master.query]) {
        expect(room, isNot(contains(secret)));
      }
      final resolution = await setup.site.resolvePlayUrlsRaw(
        detail: await setup.site.getRoomDetail(roomId: _live),
        quality: Fc2LiveApi.autoQuality,
      );
      expect(resolution.urls, isEmpty);
      expect(resolution.inputRecipe?.identity, 'fc2live:62996200:auto');
    });

    test('closing waits at most the close timeout for a stuck socket', () async {
      final channel = _Channel(_serverFrames())..closeGate = Completer<void>();
      final grant = Fc2LiveApi.grant(Fixture.load('fc2live', 'S03-control').body, channelId: _live);
      final control = await Fc2LiveControl.open(
        grant,
        connector: _Connector([channel]).call,
        closeTimeout: const Duration(milliseconds: 20),
      );
      await control.close().timeout(const Duration(seconds: 1));
      expect(await control.done, isNull);
      channel.closeGate!.complete();
    });
  });

  group('links', () {
    test("channel links and share texts, without a request (3.x's Fc2Link)", () async {
      final http = ReplayHttp(const []);
      final site = Fc2LiveSite(http);
      final parser = LinkParser(SiteRegistry({'fc2live': () => site}), http);
      for (final (text, room) in [
        ('https://live.fc2.com/10608314/', '10608314'),
        ('https://live.fc2.com/ja/10608314/?utm_source=share', '10608314'),
        ('看这个 https://live.fc2.com/en/62996200/ 快来', '62996200'),
        ('http://live.fc2.com/62996200', '62996200'),
      ]) {
        expect(await parser.parse(text), RoomLink('fc2live', room), reason: text);
        expect(parser.containsSupportedLink(text), isTrue, reason: text);
      }
      for (final text in [
        '10608314',
        'https://live.fc2.com/',
        'https://live.fc2.com/rank/',
        'https://live.fc2.com/10608314/archive',
        'https://live.fc2.com.evil.test/10608314/',
        'https://live.fc2.com/10608314/#chat',
      ]) {
        expect(await parser.parse(text), isNull, reason: text);
        expect(site.roomIdFromUrl(text), isNull, reason: text);
      }
      expect(http.requests, isEmpty);
      expect(site.needsResolving('https://live.fc2.com/10608314/'), isFalse);
    });
  });
}
