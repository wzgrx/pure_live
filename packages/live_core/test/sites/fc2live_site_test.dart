// Fc2LiveSite over the recorded FC2 Live responses (ReplayHttp), a few
// synthetic ones and the recorded control socket (a fake WebSocket replaying
// fixtures/fc2live/control/S04-control): the form POSTs and their headers,
// the shared snapshot (page 1 refreshes it, later pages reuse it for 20 s,
// 26-1), the directory pages and 3.x's slices, the search (keywords and
// exact channels), room details at every depth (restrictions, start times,
// comment arguments), the qualities and their recipes (26-2), the control
// grant and the control socket, cancellation, links and the error mapping.
// Requests are compared with the ones 3.x sent (expected.json records them).
// Ports the site part of 3.x's test/fc2live_site_test.dart. The clock is the
// recording time wherever a sample's times are read.
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
const _points = '5185474';
const _missing = '99999999';

const _members = [
  'S02-member-live',
  'S02-member-offline',
  'S02-member-restricted',
  'S02-member-points',
  'S02-member-missing',
];

/// When the member answers were recorded: the clock of every setup, so no
/// test compares a recorded time with the real one.
final DateTime _recorded = Fixture.load('fc2live', 'S02-member-live').capturedAt;

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
    site: Fc2LiveSite(
      http,
      now: now ?? () => _recorded,
      connector: connector,
      proxy: proxy,
      controlStartupTimeout: controlStartupTimeout,
    ),
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
List<String> _serverFrames([String sample = 'S04-control']) => [
  for (final line in File('$_root/control/$sample/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty)
      if (jsonDecode(line) case {'dir': 'in', 'text': final String text}) text,
];

/// The channel of control/S07-control-hd, a 1080p broadcast whose answer
/// offers the tiers 50 and 40 too.
const _hd = '10200498';

/// Synthetic answers for [_hd]: S02-member-live's member answer about it and
/// S03-control's grant for its control socket (only the channel differs).
List<ReplaySample> _hdAnswers() {
  final member = jsonDecode(Fixture.load('fc2live', 'S02-member-live').body) as Map<String, dynamic>;
  ((member['data'] as Map<String, dynamic>)['channel_data'] as Map<String, dynamic>)['channelid'] = _hd;
  final grant = jsonDecode(Fixture.load('fc2live', 'S03-control').body) as Map<String, dynamic>;
  grant['url'] = (grant['url'] as String).replaceFirst('/channels/$_live', '/channels/$_hd');
  return [
    _synthetic('/api/memberApi.php', _memberForm(_hd), member),
    ReplaySample(
      method: 'POST',
      url: Uri.parse('https://live.fc2.com/api/getControlServer.php'),
      status: 200,
      bytes: utf8.encode(jsonEncode(grant)),
    ),
  ];
}

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

    test("the platform: 3.x's id, name and directory note; no account or cookie; comments are M5's", () {
      final site = _setup(const []).site;
      expect((site.id, site.name, site.directoryNoticeKey), ('fc2live', 'FC2 Live', 'fc2live_directory_scope'));
      expect(site.getDanmaku(), isA<EmptyDanmaku>(), reason: 'the connection is M5 (DanmakuRegistry)');
      expect(Fc2LiveSite.snapshotLifetime, const Duration(seconds: 20), reason: "3.x's 20 s (26-1)");
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isNot(isA<LivePlayUrlCursorResolver>()));
      expect(site, isA<LiveQualityDiscovery>(), reason: 'the qualities come from a control answer (26-2)');
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

    test('26-1: page 1 refreshes the snapshot; later directory pages reuse it, no room twice or missing', () async {
      var now = DateTime.utc(2026, 9, 28, 12);
      final setup = _setup(['S01-directory'], now: () => now);
      final token = CancelToken();
      final pages = [
        for (final page in [1, 2, 3, 4]) await setup.site.getDirectoryPage(page: page, cancel: token),
      ];
      expect(setup.http.requests, hasLength(1), reason: '3.x: one request a page, each a new snapshot');
      final ids = [for (final page in pages) ..._ids(page.rooms)];
      expect(ids, hasLength(61));
      expect(ids.toSet(), hasLength(61));
      expect(pages.map((page) => page.hasMore), [true, true, true, false]);
      await setup.site.getDirectoryPage(page: 2, category: _area('1'), cancel: token);
      await setup.site.getCategories(1, 30);
      await setup.site.getRecommendRooms(page: 2);
      await setup.site.getCategoryRooms(_area('9'));
      expect(setup.http.requests, hasLength(1), reason: 'every other call reuses it');
      now = now.add(const Duration(seconds: 19));
      await setup.site.getDirectoryPage(page: 3, cancel: token);
      expect(setup.http.requests, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      await setup.site.getDirectoryPage(page: 3, cancel: token);
      expect(setup.http.requests, hasLength(2), reason: 'after 20 s a later page asks anew');
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(2), reason: 'and that one is shared again');
      await setup.site.getDirectoryPage(cancel: token);
      await setup.site.getDirectoryPage();
      expect(setup.http.requests, hasLength(4), reason: 'page 1 always refreshes, with a token or without');
      now = now.subtract(const Duration(minutes: 1));
      await setup.site.getDirectoryPage(page: 2, cancel: token);
      expect(setup.http.requests, hasLength(5), reason: 'a clock that went back does not reuse');
    });

    test('26-1: the keyword search refreshes on page 1 and pages from the same snapshot', () async {
      final setup = _setup(['S01-directory', 'S02-member-live']);
      final token = CancelToken();
      final pages = [
        for (final page in [1, 2, 3, 4])
          await setup.site.searchRoomsCancellable('fc2user', page: page, pageSize: 5, cancel: token),
      ];
      expect(setup.http.requests, hasLength(1));
      final search = _legacy('S01-directory')['searchRooms (pageSize 20)'] as Map<String, dynamic>;
      for (final page in [1, 2, 3]) {
        expect(_ids(pages[page - 1]), _legacyIds(search['fc2user page $page size 5']), reason: 'page $page');
      }
      await setup.site.searchRoomsCancellable('猫', cancel: token);
      expect(setup.http.requests, hasLength(2), reason: 'a new search is a page 1');
      await setup.site.searchRooms('猫');
      await setup.site.getDirectoryPage(page: 2, cancel: token);
      expect(setup.http.requests, hasLength(2), reason: 'the search snapshot serves the directory too');
      await setup.site.searchRoomsCancellable(_live, cancel: token);
      expect(setup.http.requests.last.url.path, '/api/memberApi.php', reason: 'an exact channel is still looked up');
    });

    test(
      '26-1: a later page with a token does not wait for a shared fetch; failures and cancels are not kept',
      () async {
        final body = Fixture.load('fc2live', 'S01-directory').body;
        final gate = Completer<void>();
        var fail = false;
        final http = _Scripted((request) async {
          if (request.cancel == null) await gate.future;
          if (fail) throw const TransportFailure('fc2live', TransportReason.connect, 'down');
          if (request.cancel?.isCancelled ?? false) throw const TransportFailure('fc2live', TransportReason.cancelled);
          return LiveResponse(status: 200, bytes: utf8.encode(body), url: request.url);
        });
        final site = Fc2LiveSite(http, now: () => _recorded);
        final shared = site.getRecommendRooms();
        await pumpEventQueue();
        final page = await site.getDirectoryPage(page: 2, cancel: CancelToken());
        expect(page.rooms, hasLength(20), reason: 'fetched with its own token, not waiting for the shared one');
        expect(http.requests, hasLength(2));
        gate.complete();
        expect(await shared, hasLength(30));
        await site.getDirectoryPage(page: 3, cancel: CancelToken());
        expect(http.requests, hasLength(2), reason: 'the arrived snapshot is reused');

        fail = true;
        await expectLater(site.getDirectoryPage(cancel: CancelToken()), throwsA(isA<NetworkFailure>()));
        fail = false;
        final cancelled = CancelToken()..cancel();
        await expectLater(site.searchRoomsCancellable('猫', page: 2, cancel: cancelled), _cancelled);
        final before = http.requests.length;
        await site.getDirectoryPage(page: 2, cancel: CancelToken());
        expect(http.requests, hasLength(before), reason: 'the snapshot before the failure is still there');
      },
    );

    test("3.x's `cache` scenario still sends 3.x's two requests; the refreshed one is shared after", () async {
      final setup = _setup(['S01-directory']);
      await setup.site.getRecommendRooms();
      await setup.site.getCategoryRooms(_area('1'));
      await setup.site.searchRooms('猫');
      await setup.site.getDirectoryPage(cancel: CancelToken());
      expect(_sent(setup.http.requests), _legacyRequests(_legacy('S01-directory')['cache']));
      await setup.site.getRecommendRooms();
      expect(setup.http.requests, hasLength(2), reason: "the directory's page 1 is the shared snapshot now (26-1)");
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
      // The start time and restriction from the same answer (M2.1).
      for (final room in [entry, refresh, recording, link]) {
        expect(room.startedAt, DateTime.utc(2026, 9, 26, 7, 17, 46, 410), reason: 'start 1790407066410');
        expect(room.restriction, LiveRestriction.none);
      }
      // Comment arguments on entry and recording only (26-3, M5).
      expect(entry.danmakuData, const Fc2LiveDanmakuArgs(_live));
      expect(recording.danmakuData, const Fc2LiveDanmakuArgs(_live));
      expect(refresh.danmakuData, isNull);
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
      expect((offline.watching, offline.onlineViewers, offline.totalViewers), ('', '', ''), reason: '26-8');
      expect((offline.startedAt, offline.restriction), (null, null));
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
      expect((await setup.site.getRoomDetail(roomId: _offline)).danmakuData, const Fc2LiveDanmakuArgs(_offline));
      final restricted = await setup.site.getRoomDetail(roomId: _restricted);
      expect(restricted.liveStatus, LiveStatus.live, reason: '26-9 (3.x: unknown)');
      expect(restricted.restriction, LiveRestriction.needsLogin);
      expect(restricted.followGroup, FollowGroup.live);
      expect(restricted.notice, Fc2LiveApi.noticeText['fc2live_access_restricted']);
      expect(await setup.site.getLiveStatus(roomId: _restricted), isTrue, reason: '26-9 (3.x: access)');
      final points = await setup.site.getRoomDetailForRefresh(roomId: _points);
      expect((points.liveStatus, points.restriction, points.nick), (LiveStatus.live, LiveRestriction.needsLogin, ''));
      expect(await setup.site.getLiveStatus(roomId: _points), isTrue);
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
      expect(merged.area, '其他', reason: "the stored Japanese area gives way to the catalog's name (26-6)");
      expect(merged.startedAt, fresh.startedAt);
      expect(merged.httpHeaders, stored.httpHeaders, reason: 'mergeFrom replaces headers only for IPTV');
    });

    test(
      "3.x's stored restricted follow (unknown) refreshes to live and marked; a nameless one keeps its name",
      () async {
        final setup = _setup(_members);
        final restricted = LiveRoom.fromJson(
          (_result(_legacy('S02-member-restricted')['getRoomDetail'])! as Map<String, dynamic>).cast<String, Object?>(),
        );
        expect(restricted.liveStatus, LiveStatus.unknown);
        final merged = restricted.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: _restricted));
        expect((merged.liveStatus, merged.restriction), (LiveStatus.live, LiveRestriction.needsLogin));
        final named = LiveRoom(platform: 'fc2live', roomId: _points, nick: 'stored name', liveStatus: LiveStatus.live);
        final refreshed = named.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: _points));
        expect(refreshed.nick, 'stored name', reason: 'an empty name does not overwrite (M2.1; 3.x wrote the number)');
      },
    );

    test('a broadcast that ends clears its start time and restriction and shows no viewers', () async {
      final live = await _setup(['S02-member-live']).site.getRoomDetailForRefresh(roomId: _live);
      final ended = _setup(const [], extra: [_editedMember((channel) => channel['is_publish'] = 0)]);
      final merged = live.mergeFrom(await ended.site.getRoomDetailForRefresh(roomId: _live));
      expect((merged.liveStatus, merged.startedAt, merged.restriction), (LiveStatus.offline, null, null));
      expect(merged.watching, live.watching, reason: 'M2.1 keeps a stored count; the interface hides it offline (M13)');
    });
  });

  group('streams', () {
    test("the qualities the channel's control answer offers, from entry, refresh or a card (26-2)", () async {
      final channels = [for (var i = 0; i < 3; i++) _Channel(_serverFrames())];
      final connector = _Connector([...channels]);
      final setup = _setup(['S02-member-live', 'S01-directory', 'S03-control'], connector: connector.call);
      final entry = await setup.site.getRoomDetail(roomId: _live);
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final card = (await setup.site.getRecommendRooms(pageSize: 100)).firstWhere((room) => room.roomId == _live);
      final requests = setup.http.requests.length;
      for (final room in [entry, refresh, card]) {
        final qualities = await setup.site.getPlayQualities(detail: room);
        // S04 has no 50 or 40: they are not listed.
        expect(qualities.map((quality) => quality.selectionId), ['30', '20', '10', 'auto']);
        expect(qualities.map((quality) => quality.quality), ['高清', '标清', '流畅', '自适应 HLS']);
      }
      // A control each (3.x listed auto without a request): member, grant,
      // socket, closed before the list is returned.
      final grant = _legacyRequests(_legacy('S02-member-live')['Fc2Api.controlGrant']);
      expect(_sent(setup.http.requests.skip(requests)), [...grant, ...grant, ...grant]);
      expect(connector.calls, hasLength(3));
      expect(channels.map((channel) => channel.closed), everyElement(isTrue));
      expect(channels.map((channel) => channel.sent), everyElement([Fc2LiveControl.hlsRequest]));
    });

    test('F.5a: the probe hands its control over when asked to; any tier can be played from it', () async {
      final channel = _Channel(_serverFrames('S07-control-hd'));
      final connector = _Connector([channel]);
      final taken = <Fc2LiveControl>[];
      final http = ReplayHttp(_hdAnswers());
      final site = Fc2LiveSite(http, now: () => _recorded, connector: connector.call, probeControl: taken.add);
      final room = LiveRoom(platform: 'fc2live', roomId: _hd, liveStatus: LiveStatus.live);
      final qualities = await site.discoverPlayQualities(detail: room);
      expect(qualities.first.selectionId, '50');
      final control = taken.single;
      expect((control.isClosed, channel.closed), (false, false), reason: 'the taker owns it now');
      expect((control.channelId, control.requestedQuality), (_hd, 'auto'));
      expect(Fc2LiveApi.playlistFor(control.playlists, '50')?.url.path, '/a/stream/$_hd/51/playlist');
      await control.close();
      expect(channel.closed, isTrue);
      expect(connector.calls, hasLength(1));
    });

    test('S07: a channel with the tiers 50 and 40 lists them first; each plays its high-latency variant', () async {
      final connector = _Connector([
        _Channel(_serverFrames('S07-control-hd')),
        _Channel(_serverFrames('S07-control-hd')),
      ]);
      final setup = _setup(const [], extra: _hdAnswers(), connector: connector.call);
      final room = LiveRoom(platform: 'fc2live', roomId: _hd, liveStatus: LiveStatus.live);
      final qualities = await setup.site.discoverPlayQualities(detail: room);
      expect(qualities.map((quality) => (quality.selectionId, quality.quality)), [
        ('50', '超清 3M（β）'),
        ('40', '超清 2M'),
        ('30', '高清'),
        ('20', '标清'),
        ('10', '流畅'),
        ('auto', '自适应 HLS'),
      ]);
      final resolution = await setup.site.resolvePlayUrlsRaw(detail: room, quality: qualities.first);
      expect(resolution.inputRecipe, Fc2LiveInputRecipe(_hd, quality: '50'));
      final control = await setup.site.openControl(_hd, quality: '50');
      expect((control.quality, control.playlist.path), ('50', '/a/stream/$_hd/51/playlist'));
      await control.close();
      expect(connector.calls, hasLength(2));
    });

    test('a discovery honours its cancel token and never leaves a socket open', () async {
      final cancelled = CancelToken()..cancel();
      final early = _controlSetup(_Channel(_serverFrames()));
      final detail = LiveRoom(platform: 'fc2live', roomId: _live, liveStatus: LiveStatus.live);
      await expectLater(early.site.discoverPlayQualities(detail: detail, cancel: cancelled), _cancelled);
      expect(early.http.requests, isEmpty);
      expect(early.connector.calls, isEmpty);

      final channel = _Channel([_message('connect_complete')]);
      final setup = _controlSetup(channel);
      final cancel = CancelToken();
      final discovery = setup.site.discoverPlayQualities(detail: detail, cancel: cancel);
      while (!channel.sent.contains(Fc2LiveControl.hlsRequest)) {
        await pumpEventQueue();
      }
      cancel.cancel();
      await expectLater(discovery, _cancelled);
      expect(channel.closed, isTrue);
      final silent = _Channel([_message('connect_complete')]);
      await expectLater(
        _controlSetup(silent, startup: const Duration(milliseconds: 50)).site.getPlayQualities(detail: detail),
        throwsA(isA<NetworkFailure>()),
      );
      expect(silent.closed, isTrue);
    });

    test("each quality's recipe: no URL, 3.x's identity for auto, the same for recovery; no request", () async {
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
      const qualities = Fc2LiveApi.qualities;
      for (final tier in qualities) {
        final unified = await setup.site.resolvePlayUrls(detail: detail, quality: tier);
        expect(unified.inputRecipe, Fc2LiveInputRecipe(_live, quality: '${tier.id}'));
        expect(unified.inputRecipe?.identity, 'fc2live:$_live:${tier.id}');
        expect(unified.appliedQualityData, tier.id);
        expect(resolveAppliedPlayQuality(qualities: qualities, requested: tier, resolution: unified), same(tier));
        final again = await setup.site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: tier);
        expect(again.inputRecipe, unified.inputRecipe);
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('rooms that cannot be played are refused before any request, restricted ones with the reason', () async {
      final setup = _setup(_members);
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      final restricted = await setup.site.getRoomDetail(roomId: _restricted);
      final points = await setup.site.getRoomDetail(roomId: _points);
      final requests = setup.http.requests.length;
      const quality = Fc2LiveApi.autoQuality;
      await expectLater(setup.site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.resolvePlayUrlsRaw(detail: offline, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      for (final room in [restricted, points]) {
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<NeedsLogin>()), reason: room.roomId);
        await expectLater(
          setup.site.resolvePlayUrlsRaw(detail: room, quality: Fc2LiveApi.tierQualities.first),
          throwsA(isA<NeedsLogin>()),
        );
      }
      // A room read back from storage has no data: its restriction decides.
      for (final (restriction, matcher) in [
        (LiveRestriction.needsLogin, isA<NeedsLogin>()),
        (LiveRestriction.paid, isA<StreamUnavailable>()),
        (LiveRestriction.unplayable, isA<StreamUnavailable>()),
      ]) {
        final stored = LiveRoom.fromJson(
          LiveRoom(platform: 'fc2live', roomId: _live, liveStatus: LiveStatus.live, restriction: restriction).toJson(),
        );
        await expectLater(setup.site.getPlayQualities(detail: stored), throwsA(matcher), reason: restriction.name);
      }
      final stored = LiveRoom.fromJson(
        LiveRoom(
          platform: 'fc2live',
          roomId: _live,
          liveStatus: LiveStatus.live,
          restriction: LiveRestriction.none,
        ).toJson(),
      );
      expect(
        (await setup.site.resolvePlayUrlsRaw(detail: stored, quality: quality)).inputRecipe,
        Fc2LiveInputRecipe(_live),
        reason: 'restriction none plays',
      );
      final pending = LiveRoom(platform: 'fc2live', roomId: _live, liveStatus: LiveStatus.unknown);
      await expectLater(setup.site.getPlayQualities(detail: pending), throwsA(isA<StreamUnavailable>()));
      final other = LiveRoom(platform: 'bilibili', roomId: _live, liveStatus: LiveStatus.live);
      await expectLater(setup.site.getPlayQualities(detail: other), throwsArgumentError);
      final bad = LiveRoom(platform: 'fc2live', roomId: 'abc', liveStatus: LiveStatus.live);
      await expectLater(setup.site.getPlayQualities(detail: bad), throwsA(isA<NotFound>()));
      final live = await _setup(['S02-member-live']).site.getRoomDetail(roomId: _live);
      for (final id in ['original', '60', 'AUTO']) {
        await expectLater(
          setup.site.resolvePlayUrlsRaw(
            detail: live,
            quality: LivePlayQuality(quality: '原画', id: id),
          ),
          throwsArgumentError,
          reason: id,
        );
      }
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

    test('offline is StreamUnavailable, restricted by its kind, missing NotFound: no grant request', () async {
      final setup = _setup(_members);
      await expectLater(setup.site.controlGrant(_offline), throwsA(isA<StreamUnavailable>()));
      await expectLater(setup.site.controlGrant(_restricted), throwsA(isA<NeedsLogin>()));
      await expectLater(setup.site.controlGrant(_points), throwsA(isA<NeedsLogin>()));
      await expectLater(setup.site.controlGrant(_missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.controlGrant('abc'), throwsA(isA<NotFound>()));
      expect(setup.http.requests.map((request) => request.url.path), everyElement('/api/memberApi.php'));
      expect(setup.http.requests, hasLength(4));
      // Paid and FC2-restricted broadcasts are StreamUnavailable with the
      // reason (3.x: `access` for all five flags).
      for (final (flag, reason) in [('fee', 'paid'), ('ticketid', 'paid'), ('is_limited', '配信規制中')]) {
        final paid = _setup(const [], extra: [_editedMember((channel) => channel[flag] = 1)]);
        await expectLater(
          paid.site.openControl(_live),
          throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains(reason))),
          reason: flag,
        );
        expect(paid.http.requests, hasLength(1), reason: flag);
      }
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
      expect('${control.playlist}', _legacy('control/S04-control')[_live], reason: "auto plays 3.x's master");
      expect((control.requestedQuality, control.quality), ('auto', 'auto'));
      expect(control.playlists, hasLength(15));
      expect(control.mediaHeaders, Fc2LiveApi.mediaHeaders(_live));
      expect(control.channelId, _live);
      expect(control.isClosed, isFalse);
      await control.close();
      expect(control.isClosed, isTrue);
      expect(channel.closed, isTrue);
      expect(await control.done, isNull);
      await control.close();
    });

    test('26-2: a tier opens on its high-latency variant; the request and handshake are the same', () async {
      for (final (quality, mode) in [('30', 31), ('20', 21), ('10', 11)]) {
        final channel = _Channel(_serverFrames());
        final setup = _controlSetup(channel);
        final control = await setup.site.openControl(_live, quality: quality);
        expect(control.playlist.path, '/a/stream/$_live/$mode/playlist', reason: quality);
        expect(control.playlist.queryParameters.keys, unorderedEquals(['c', 'd']));
        expect((control.requestedQuality, control.quality), (quality, quality));
        expect(channel.sent, [Fc2LiveControl.hlsRequest]);
        expect(_sent(setup.http.requests), _legacyRequests(_legacy('S02-member-live')['Fc2Api.controlGrant']));
        await control.close();
      }
    });

    test("26-2: a tier the channel lacks plays the next one and says so; none at all can't open", () async {
      String answer(List<int> modes) => jsonEncode({
        'name': '_response_',
        'id': 1,
        'arguments': {
          'status': 0,
          'playlists': [
            for (final mode in modes)
              {
                'mode': mode,
                'status': 0,
                'url': 'https://us-west-1-media.live.fc2.com/a/stream/$_live/$mode/playlist?c=cc&d=dd',
              },
          ],
        },
      });
      final lower = _Channel([
        _message('connect_complete'),
        answer([10, 20]),
      ]);
      final control = await _controlSetup(lower).site.openControl(_live, quality: '30');
      expect((control.requestedQuality, control.quality, control.playlist.pathSegments[3]), ('30', '20', '20'));
      await control.close();
      final sound = _Channel([
        _message('connect_complete'),
        answer([90]),
      ]);
      await expectLater(_controlSetup(sound).site.openControl(_live, quality: '10'), throwsA(isA<ApiChanged>()));
      expect(sound.closed, isTrue);
    });

    test('a quality that is not one of the six is refused without a request or a socket', () async {
      final setup = _controlSetup(_Channel(_serverFrames()));
      for (final quality in ['60', 'original', '']) {
        await expectLater(setup.site.openControl(_live, quality: quality), throwsArgumentError, reason: quality);
      }
      expect(setup.http.requests, isEmpty);
      expect(setup.connector.calls, isEmpty);
      final grant = Fc2LiveApi.grant(Fixture.load('fc2live', 'S03-control').body, channelId: _live);
      await expectLater(
        Fc2LiveControl.open(grant, connector: setup.connector.call, quality: '60'),
        throwsArgumentError,
      );
      expect(setup.connector.calls, isEmpty);
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
      for (final secret in [playback.grant.controlToken, playback.grant.orz, playback.playlist.query]) {
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
