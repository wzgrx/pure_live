// NiconicoSite over the recorded niconico responses (ReplayHttp) and the
// recorded seat conversation (a fake WebSocket replaying
// fixtures/niconico/seat/S04-seat): the catalog and the natively paged
// directory, search, the watch page at every depth, quality discovery with
// its own seat and the recipe, cancellation and deadlines, the seat
// protocol (3.x's test/niconico_session_test.dart, on a manual clock), links
// and the error mapping (3.x's niconico_site_test.dart,
// niconico_directory_test.dart, niconico_quality_catalog_test.dart and
// niconico_application_test.dart, adapter parts), and the M4.U upgrades:
// broadcaster rooms and 3.x's program ids (17-1), program and broadcaster
// links (17-2), the entered room's seat bootstrap (17-6). The master
// playlist is 3.x's synthetic `officialMaster`: no sample has one.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/niconico';
const _live = 'lv351482868';
const _recent = 'https://live.nicovideo.jp/front/api/pages/recent/v1/programs';
const _search = 'https://live.nicovideo.jp/front/api/pages/search/v1/programs';

/// The recorded seat's master playlist (S04-seat, program lv351482868).
final Uri _master = Uri.parse(
  'https://livedelivery.dlive.nicovideo.jp/hls/playlists/6ab953b4d954bb7b1d847c01/4766dc3f43803356/multivariant/variant.m3u8',
);

/// 3.x's `officialMaster`: observed attributes, synthetic media paths.
const _officialMaster = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-192Kbps",NAME="Main Audio",DEFAULT=YES,URI="audio192.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-96Kbps",NAME="Main Audio",DEFAULT=YES,URI="audio96.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1080800,AVERAGE-BANDWIDTH=1000000,CODECS="avc1.4D401F,mp4a.40.2",RESOLUTION=800x450,FRAME-RATE=30.000,AUDIO="trial-audio-192Kbps"
normal.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=412800,AVERAGE-BANDWIDTH=384000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="trial-audio-96Kbps"
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=201600,AVERAGE-BANDWIDTH=192000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="trial-audio-96Kbps"
super-low.m3u8
''';

ReplaySample _synthetic(String url, Object body, {int status = 200}) => ReplaySample(
  method: 'GET',
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

/// A recorded watch page served as the watch page of [room] (the samples
/// were recorded as `watch/user/<id>` and `watch/ch<id>`, which answer with
/// the same page as the program id).
ReplaySample _watchPage(String sample, String room) {
  final recorded = ReplaySample.load('$_root/$sample');
  return ReplaySample(
    method: 'GET',
    url: Uri.parse('https://live.nicovideo.jp/watch/$room'),
    status: recorded.status,
    headers: recorded.headers,
    bytes: recorded.bytes,
  );
}

/// The broadcaster of [_live] (S03-watch-user-live was recorded as its page).
const _user = 'user/144846457';

/// The embedded data of the live watch page, for synthetic variants.
Map<String, dynamic> _liveProps() {
  final body = Fixture.load('niconico', 'S03-watch-user-live').body;
  final raw = RegExp('data-props="([^"]*)"').firstMatch(body)!.group(1)!;
  return jsonDecode(decodeHtmlEntities(raw)) as Map<String, dynamic>;
}

ReplaySample _syntheticWatch(Map<String, dynamic> props, {String program = _live}) => _synthetic(
  'https://live.nicovideo.jp/watch/$program',
  '<script id="embedded-data" data-props="${const HtmlEscape().convert(jsonEncode(props))}"></script>',
);

/// The server's messages in the recorded seat conversation, in order.
List<String> _serverFrames({bool pings = true}) => [
  for (final line in File('$_root/seat/S04-seat/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty)
      if (jsonDecode(line) case {'dir': 'in', 'text': final String text} when pings || !text.contains('"ping"')) text,
];

String _frame(String type, [Object? data]) => jsonEncode({'type': type, 'data': ?data});

/// A seat's `stream` message with every cookie value replaced by [value],
/// optionally on another master.
String _streamFrame({String value = 'rotated', Uri? uri}) {
  final stream = _serverFrames()
      .map((text) => jsonDecode(text) as Map<String, dynamic>)
      .firstWhere((message) => message['type'] == 'stream');
  final data = stream['data'] as Map<String, dynamic>;
  if (uri != null) data['uri'] = uri.toString();
  for (final cookie in (data['cookies'] as List).cast<Map<String, dynamic>>()) {
    cookie['value'] = value;
  }
  return jsonEncode(stream);
}

/// A fake WebSocket: what the server said is queued before the seat listens.
final class _Channel implements SocketChannel {
  new([List<String> server = const []]) {
    server.forEach(incoming.add);
  }

  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Map<String, dynamic>> sent = [];
  bool closed = false;
  bool failSends = false;
  Completer<void>? closeGate;

  List<String> get types => [for (final message in sent) message['type'] as String];

  void server(String type, [Object? data]) => incoming.add(_frame(type, data));

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed || failSends) throw StateError('send failed');
    sent.add(jsonDecode(data as String) as Map<String, dynamic>);
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
  final List<({Uri endpoint, Map<String, String> headers, ProxyRoute route})> calls = [];
  Completer<void>? gate;

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    calls.add((endpoint: endpoint, headers: headers, route: route));
    final channel = channels.removeAt(0);
    await gate?.future;
    return channel;
  }
}

/// Replays [inner], but holds a media request until it is cancelled
/// (reported through [started]).
final class _HoldMedia implements LiveHttp {
  new(this.inner);

  final ReplayHttp inner;
  final Completer<LiveRequest> started = Completer<LiveRequest>();

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    if (!request.url.path.startsWith('/hls/')) return await inner.send(request);
    inner.requests.add(request);
    started.complete(request);
    await request.cancel!.whenCancelled;
    throw const TransportFailure('niconico', TransportReason.cancelled);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

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
    throw TransportFailure('niconico', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('niconico', reason, 'test');

  @override
  void close() {}
}

/// A manual clock for the seat's timers.
final class _Clock {
  Duration _elapsed = Duration.zero;
  final List<_ManualTimer> _timers = [];

  Timer timer(Duration duration, void Function() callback) => _add(duration, null, (_) => callback());

  Timer periodic(Duration period, void Function(Timer timer) callback) => _add(period, period, callback);

  _ManualTimer _add(Duration duration, Duration? period, void Function(Timer) callback) {
    final timer = _ManualTimer(_elapsed + duration, period, callback);
    _timers.add(timer);
    return timer;
  }

  /// Advances by [duration], firing due timers in order.
  void advance(Duration duration) {
    final end = _elapsed + duration;
    while (true) {
      final due = _timers.where((timer) => timer.isActive && timer.dueAt <= end).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      if (due.isEmpty) break;
      _elapsed = due.first.dueAt;
      due.first.fire();
    }
    _elapsed = end;
  }
}

final class _ManualTimer implements Timer {
  new(this.dueAt, this._period, this._callback);

  Duration dueAt;
  final Duration? _period;
  final void Function(Timer) _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    _tick++;
    final period = _period;
    if (period == null) {
      _active = false;
    } else {
      dueAt += period;
    }
    _callback(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

final Uri _socket = Uri.parse('wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/24876040585822?audience_token=x');

/// When S04-seat was recorded: its session cookie expired at 2026-09-28
/// 18:41 UTC, so the seats read their grants at this time, not now.
final DateTime _seatRecordedAt = Fixture.load('niconico', 'seat/S04-seat').capturedAt;

/// Opens a seat on [channel] with the manual [clock].
Future<NiconicoSeat> _open(
  _Channel channel,
  _Clock clock, {
  CancelToken? cancel,
  _Connector? connector,
  Duration closeTimeout = const Duration(seconds: 2),
}) => NiconicoSeat.open(
  _socket,
  connector: (connector ?? _Connector([channel])).call,
  cancel: cancel,
  closeTimeout: closeTimeout,
  now: () => _seatRecordedAt,
  timer: clock.timer,
  periodicTimer: clock.periodic,
);

typedef _Setup = ({NiconicoSite site, ReplayHttp http, _Connector connector});

_Setup _setup(
  List<ReplaySample> samples, {
  List<_Channel>? channels,
  ProxyPolicy proxy = const FixedProxyPolicy(),
  Duration discoveryDeadline = const Duration(seconds: 30),
  Duration seatStartupTimeout = const Duration(seconds: 20),
  Duration bootstrapLifetime = const Duration(seconds: 60),
  DateTime Function()? clock,
  LiveHttp Function(ReplayHttp http)? wrap,
}) {
  final http = ReplayHttp(samples);
  final connector = _Connector(channels ?? []);
  final site = NiconicoSite(
    wrap == null ? http : wrap(http),
    proxy: proxy,
    connector: connector.call,
    discoveryDeadline: discoveryDeadline,
    seatStartupTimeout: seatStartupTimeout,
    bootstrapLifetime: bootstrapLifetime,
    clock: clock,
  );
  return (site: site, http: http, connector: connector);
}

/// The live program, its master, and one recorded seat per discovery.
_Setup _liveSetup({int seats = 1, List<ReplaySample> extra = const [], ProxyPolicy? proxy}) => _setup(
  [...extra, _watchPage('S03-watch-user-live', _live), _synthetic('$_master', _officialMaster)],
  channels: [for (var i = 0; i < seats; i++) _Channel(_serverFrames(pings: false))],
  proxy: proxy ?? const FixedProxyPolicy(),
);

LiveRoom _room(String roomId, {LiveStatus status = LiveStatus.live}) =>
    LiveRoom(roomId: roomId, platform: 'niconico', liveStatus: status);

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

Matcher _cancelled() => throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled));

void main() {
  test("3.x's capabilities", () {
    final site = NiconicoSite(ReplayHttp(const []));
    expect(site.id, 'niconico');
    expect(site.name, 'niconico');
    expect(site, isA<LiveSiteDirectoryPager>());
    expect(site, isA<LiveDirectoryNotice>());
    expect(site, isA<LiveQualityDiscovery>());
    expect(site, isA<LiveCancellableSearch>());
    expect(site, isA<LiveSiteRoomRefresher>());
    expect(site, isA<LiveSiteRecordRoomResolver>());
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isA<LivePlayUrlCursorResolver>());
    expect(site, isA<LiveSiteLinks>());
    expect(site, isNot(isA<LivePlayLeaseMetadata>()));
    expect(site.directoryNoticeKey, 'niconico_directory_scope');
  });

  group('catalog', () {
    test('one category of seven tabs on page 1 only, without a request', () async {
      final setup = _setup([]);
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.single.children.map((area) => area.areaId), NiconicoApi.tabs);
      expect(categories.single.children.map((area) => area.areaType).toSet(), {'recent'});
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('pages 1–10000 and sizes 1–100, else ArgumentError (3.x refused them before any request)', () async {
      final setup = _setup([]);
      for (final (page, size) in [(0, 30), (-1, 30), (10001, 30), (1, 0), (1, 101)]) {
        await expectLater(setup.site.getCategories(page, size), throwsArgumentError, reason: '$page/$size');
      }
      await expectLater(setup.site.getRecommendRooms(pageSize: 0), throwsArgumentError);
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('directory', () {
    test("recommendations are the general tab's page, with 3.x's request", () async {
      final setup = _setup([ReplaySample.load('$_root/S01-recent-common-p1')]);
      final page = await setup.site.getDirectoryPage();
      expect(page.rooms, hasLength(70));
      expect(page.page, 1);
      expect(page.hasMore, isTrue);
      final request = setup.http.requests.single;
      expect(request.url.toString(), '$_recent?tab=common&offset=0&sortOrder=recentDesc');
      expect(request.site, 'niconico', reason: 'the app routes the platform through its proxy');
      expect(request.headers, {'referer': 'https://live.nicovideo.jp/', 'user-agent': 'Mozilla/5.0'});
      expect(request.followRedirects, isFalse);
      expect(await setup.site.getRecommendRooms(pageSize: 20), hasLength(70), reason: 'the native page of 70');
    });

    test('the page offset is the page number minus one, not a row offset', () async {
      final setup = _setup([
        _synthetic('$_recent?tab=common&offset=1&sortOrder=recentDesc', {
          'meta': {'statusCode': 200, 'errorCode': 'OK', 'totalCount': 200},
          'data': <Object?>[],
        }),
      ]);
      final page = await setup.site.getDirectoryPage(page: 2);
      expect(page.page, 2);
      expect(page.hasMore, isTrue, reason: '200 > 2 × 70: an empty page is no end');
    });

    test('every tab is asked by its key; other areas are refused without a request', () async {
      final empty = {
        'meta': {'statusCode': 200, 'errorCode': 'OK', 'totalCount': 0},
        'data': <Object?>[],
      };
      final setup = _setup([
        for (final tab in NiconicoApi.tabs) _synthetic('$_recent?tab=$tab&offset=0&sortOrder=recentDesc', empty),
      ]);
      final areas = (await setup.site.getCategories(1, 30)).single.children;
      for (final area in areas) {
        expect(await setup.site.getCategoryRooms(area), isEmpty);
      }
      expect([for (final request in setup.http.requests) request.url.queryParameters['tab']], NiconicoApi.tabs);
      for (final area in const [
        LiveArea(platform: 'other', areaType: 'recent', areaId: 'common'),
        LiveArea(platform: 'niconico', areaType: 'rank', areaId: 'common'),
        LiveArea(platform: 'niconico', areaType: 'recent', areaId: 'all'),
        LiveArea(platform: 'niconico', areaType: 'recent', areaId: '../all'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: area.areaId);
      }
      expect(setup.http.requests, hasLength(7));
    });

    test('S01 face through the category call', () async {
      final setup = _setup([ReplaySample.load('$_root/S01-recent-face-p1')]);
      final face = (await setup.site.getCategories(1, 30)).single.children.firstWhere((area) => area.areaId == 'face');
      final rooms = await setup.site.getCategoryRooms(face, pageSize: 20);
      expect(rooms, hasLength(44));
      expect(rooms.every((room) => room.isLiveNow), isTrue);
    });

    test('the cancel token reaches the request; a cancelled one sends nothing', () async {
      final setup = _setup([ReplaySample.load('$_root/S01-recent-common-p1')]);
      final cancel = CancelToken();
      await setup.site.getDirectoryPage(cancel: cancel);
      expect(setup.http.requests.single.cancel, same(cancel));
      await expectLater(setup.site.getDirectoryPage(cancel: CancelToken()..cancel()), _cancelled());
      expect(setup.http.requests, hasLength(1));
    });

    test('HTTP and transport failures are errors, never an empty page', () async {
      final setup = _setup([_synthetic('$_recent?tab=common&offset=0&sortOrder=recentDesc', '', status: 403)]);
      await expectLater(setup.site.getRecommendRooms(), throwsA(isA<RiskControl>()));
      final failing = NiconicoSite(_Failing(TransportReason.timeout));
      await expectLater(failing.getRecommendRooms(), throwsA(isA<NetworkFailure>()));
      final cancelled = NiconicoSite(_Failing(TransportReason.cancelled));
      await expectLater(cancelled.getRecommendRooms(), _cancelled());
    });
  });

  group('search', () {
    test("S02: programs on air, 40 a page, with 3.x's query", () async {
      final setup = _setup([ReplaySample.load('$_root/S02-search')]);
      final rooms = await setup.site.searchRooms('ゲーム', pageSize: 20);
      expect(rooms, hasLength(40), reason: 'the native page, whatever the size asked');
      expect(setup.http.requests.single.url.queryParameters, {
        'keyword': 'ゲーム',
        'column': 'main',
        'status': 'onair',
        'page': '1',
        'disableGrouping': 'true',
      });
    });

    test('the keyword is trimmed and encoded, never injected into the query', () async {
      final setup = _setup([
        _synthetic(
          '$_search?keyword=${Uri.encodeQueryComponent('遊戯 & status=past?#')}&column=main&status=onair&page=2'
          '&disableGrouping=true',
          {
            'meta': {'statusCode': 200, 'errorCode': 'OK'},
            'data': {'programs': <Object?>[], 'totalCount': 0},
          },
        ),
      ]);
      expect(await setup.site.searchRooms('  遊戯 & status=past?#  ', page: 2, pageSize: 20), isEmpty);
      expect(setup.http.requests.single.url.queryParameters['keyword'], '遊戯 & status=past?#');
      expect(setup.http.requests.single.url.queryParameters['status'], 'onair');
    });

    test('a blank keyword finds nothing without a request; bad arguments are refused', () async {
      final setup = _setup([]);
      expect(await setup.site.searchRooms('  '), isEmpty);
      await expectLater(setup.site.searchRooms('x' * 501), throwsArgumentError);
      await expectLater(setup.site.searchRooms('x', page: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('x', pageSize: 101), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });

    test('cancellation: nothing sent when cancelled, the token forwarded, a late answer dropped', () async {
      final setup = _setup([ReplaySample.load('$_root/S02-search')]);
      await expectLater(setup.site.searchRoomsCancellable('ゲーム', cancel: CancelToken()..cancel()), _cancelled());
      expect(setup.http.requests, isEmpty);
      final cancel = CancelToken();
      final slow = _setup([ReplaySample.load('$_root/S02-search')], wrap: (http) => _CancelOnAnswer(http, cancel));
      await expectLater(slow.site.searchRoomsCancellable('ゲーム', cancel: cancel), _cancelled());
      expect(slow.http.requests.single.cancel, same(cancel));
    });
  });

  group('detail', () {
    test('one watch page request at every depth; the broadcaster is the room (17-1)', () async {
      final setup = _setup([_watchPage('S03-watch-user-live', _user)]);
      final room = await setup.site.getRoomDetail(roomId: ' $_user ');
      expect(room.roomId, _user);
      expect(room.isLiveNow, isTrue);
      expect(room.totalViewers, '2292');
      expect(room.link, 'https://live.nicovideo.jp/watch/$_user');
      expect((room.data! as NiconicoRoomData).access, NiconicoAccess.allowed);
      expect((room.data! as NiconicoRoomData).programId, _live);
      expect(
        room.danmakuData,
        const NiconicoDanmakuArgs(roomId: _user, programId: _live),
        reason: '17-3 (M5)',
      );
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 17, 42, 14));
      expect(room.restriction, LiveRestriction.none);
      expect(room.introduction, isNotEmpty, reason: '17-5');
      expect(_paths(setup.http), ['/watch/$_user']);
      final request = setup.http.requests.single;
      expect(request.headers, NiconicoApi.headers);
      expect(request.followRedirects, isFalse);
      await setup.site.getRoomDetailForRefresh(roomId: _user);
      await setup.site.getRoomDetailForRecording(roomId: _user);
      expect(await setup.site.getLiveStatus(roomId: _user), isTrue);
      expect(setup.http.requests, hasLength(4), reason: 'one request each, no seat');
      expect(setup.connector.calls, isEmpty);
    });

    test("a channel's room reads the channel's page", () async {
      final setup = _setup([_watchPage('S03-watch-channel', 'ch2640864')]);
      final room = await setup.site.getRoomDetail(roomId: 'ch2640864');
      expect(room.roomId, 'ch2640864');
      expect(room.isLiveNow, isTrue);
      expect(room.avatar, endsWith('/ch2640864.jpg?1785535320'), reason: "the channel's icon");
      expect(_paths(setup.http), ['/watch/ch2640864']);
    });

    test("3.x's program id on air: one request, the broadcaster's room", () async {
      final setup = _setup([_watchPage('S03-watch-user-live', _live)]);
      final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
      expect(room.roomId, _user);
      expect(room.isLiveNow, isTrue);
      expect(_paths(setup.http), ['/watch/$_live']);
    });

    test("3.x's program id no longer on air: the broadcaster's page too (a second request)", () async {
      final setup = _setup([
        _watchPage('S03-watch-user-ended', 'lv351482791'),
        _watchPage('S03-watch-user-ended', 'user/138383030'),
      ]);
      final room = await setup.site.getRoomDetailForRefresh(roomId: 'lv351482791');
      expect(room.roomId, 'user/138383030');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(_paths(setup.http), ['/watch/lv351482791', '/watch/user/138383030']);
      expect(await setup.site.getLiveStatus(roomId: 'lv351482791'), isFalse);
      expect(setup.http.requests, hasLength(4));
    });

    test('the broadcaster may be on air with another program: the old id shows it', () async {
      final ended = _liveProps();
      final program = ended['program'] as Map<String, dynamic>;
      program['nicoliveProgramId'] = 'lv351482700';
      program['status'] = 'ENDED';
      final setup = _setup([_syntheticWatch(ended, program: 'lv351482700'), _watchPage('S03-watch-user-live', _user)]);
      final room = await setup.site.getRoomDetail(roomId: 'lv351482700');
      expect(room.roomId, _user);
      expect(room.isLiveNow, isTrue);
      expect((room.data! as NiconicoRoomData).programId, _live);
    });

    test('an official program stays its program (one request)', () async {
      final setup = _setup([_watchPage('S03-watch-official', 'lv351173882')]);
      final room = await setup.site.getRoomDetail(roomId: 'lv351173882');
      expect(room.roomId, 'lv351173882');
      expect(room.isLiveNow, isTrue);
      expect(room.notice, NiconicoApi.noticeText['niconico_program_scope']);
      expect(setup.http.requests, hasLength(1));
    });

    test('resolveRoomId: the migration of a 3.x follow (M9)', () async {
      final setup = _setup([
        _watchPage('S03-watch-user-ended', 'lv351482791'),
        _watchPage('S03-watch-channel', 'lv351292489'),
        _watchPage('S03-watch-official', 'lv351173882'),
        ReplaySample.load('$_root/S03-watch-notfound'),
      ]);
      expect(await setup.site.resolveRoomId(_user), _user);
      expect(await setup.site.resolveRoomId(' ch2640864 '), 'ch2640864');
      expect(setup.http.requests, isEmpty, reason: 'a broadcaster needs no request');
      expect(await setup.site.resolveRoomId('lv351482791'), 'user/138383030', reason: 'one request, even when ended');
      expect(await setup.site.resolveRoomId('lv351292489'), 'ch2640864');
      expect(await setup.site.resolveRoomId('lv351173882'), 'lv351173882');
      expect(setup.http.requests, hasLength(3));
      await expectLater(setup.site.resolveRoomId('lv1'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.resolveRoomId('abc'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.resolveRoomId(_live, cancel: CancelToken()..cancel()), _cancelled());
      expect(setup.http.requests, hasLength(4));
    });

    test('a follow refresh merges into the stored room of the same broadcaster', () async {
      final setup = _setup([_watchPage('S03-watch-user-ended', 'user/138383030')]);
      final stored = LiveRoom.fromJson(const {
        'roomId': 'user/138383030',
        'platform': 'niconico',
        'title': 'old',
        'liveStatus': 0,
        'status': true,
        'tagIds': ['t'],
      });
      final merged = stored.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: 'user/138383030'));
      expect(merged.title, 'プログラミング');
      expect(merged.effectiveLiveStatus, LiveStatus.offline);
      expect(merged.tagIds, ['t']);
    });

    test("a 3.x follow is merged only once migrated to its broadcaster (M9's job)", () async {
      final setup = _setup([
        _watchPage('S03-watch-user-ended', 'lv351482791'),
        _watchPage('S03-watch-user-ended', 'user/138383030'),
      ]);
      final json = <String, dynamic>{
        'roomId': 'lv351482791',
        'platform': 'niconico',
        'title': 'old',
        'liveStatus': 0,
        'status': true,
        'tagIds': ['t'],
        'notice': NiconicoApi.noticeText['niconico_program_scope'],
      };
      final fresh = await setup.site.getRoomDetailForRefresh(roomId: 'lv351482791');
      final stored = LiveRoom.fromJson(json);
      expect(identical(stored.mergeFrom(fresh), stored), isTrue, reason: 'another identity is ignored');
      final id = await setup.site.resolveRoomId('lv351482791');
      final migrated = LiveRoom.fromJson({...json, 'roomId': id, 'link': NiconicoApi.watchUrl(id), 'notice': null})
          .mergeFrom(fresh);
      expect(migrated.roomId, 'user/138383030');
      expect(migrated.title, 'プログラミング');
      expect(migrated.tagIds, ['t']);
      expect(migrated.notice ?? '', isEmpty, reason: 'the 3.x sentence is dropped by the migration');
    });

    test('not a room id is NotFound without a request; a missing room is NotFound', () async {
      final setup = _setup([ReplaySample.load('$_root/S03-watch-notfound')]);
      for (final id in ['abc', 'lv0', '351482868', 'user/0', 'user/x', 'user/1/2', 'ch0', 'CH1', 'co1', '../lv100']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: 'lv1'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: 'lv1'), throwsA(isA<NotFound>()));
    });

    test('a failing watch page is an error, never an offline room', () async {
      final setup = _setup([_synthetic('https://live.nicovideo.jp/watch/$_user', '', status: 503)]);
      await expectLater(setup.site.getRoomDetailForRecording(roomId: _user), throwsA(isA<NetworkFailure>()));
      await expectLater(
        NiconicoSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test("a broadcaster's page of someone else is ApiChanged", () async {
      final setup = _setup([_watchPage('S03-watch-user-live', 'user/1')]);
      await expectLater(setup.site.getRoomDetail(roomId: 'user/1'), throwsA(isA<ApiChanged>()));
    });
  });

  group('quality discovery', () {
    test('watch page, own seat, master with the seat cookies of its path; the seat is closed', () async {
      const proxy = FixedProxyPolicy(perSite: {'niconico': HttpProxyRoute('127.0.0.1', 7897)});
      final setup = _liveSetup(proxy: proxy);
      final channel = setup.connector.channels.single;
      final qualities = await setup.site.discoverPlayQualities(detail: _room(_live));
      expect(qualities.map((quality) => quality.selectionId), ['800x450@1080800', '512x288@412800', '512x288@201600']);
      expect(qualities.first.quality, '800×450 · 1080800 bps');
      expect(_paths(setup.http), ['/watch/$_live', _master.path]);
      final call = setup.connector.calls.single;
      expect(call.endpoint.host, 'a.live2.nicovideo.jp');
      expect(call.endpoint.queryParameters['frontend_id'], '9');
      expect(call.headers, {'origin': 'https://live.nicovideo.jp'});
      expect(call.route, const HttpProxyRoute('127.0.0.1', 7897), reason: "the platform's route");
      expect(channel.types.take(2), ['startWatching', 'getAkashic']);
      expect(channel.sent.first['data'], {
        'stream': {'quality': 'abr', 'protocol': 'hls', 'latency': 'high', 'chasePlay': false},
        'room': {'protocol': 'webSocket', 'commentable': false},
        'reconnect': false,
      });
      final master = setup.http.requests.last;
      final expected = (Fixture.load('niconico', 'seat/S04-seat').legacy as Map)['cookieHeaderFor'] as Map;
      expect(master.headers, {'cookie': expected['master']}, reason: "3.x's master read sent only the cookies");
      expect(master.followRedirects, isFalse);
      expect(master.timeout, NiconicoSite.masterTimeout);
      expect(channel.closed, isTrue, reason: 'discovery closes its seat before it returns');
    });

    test('getPlayQualities is the same discovery; two discoveries never share a seat', () async {
      final setup = _liveSetup(seats: 2);
      final channels = [...setup.connector.channels];
      await Future.wait([
        setup.site.getPlayQualities(detail: _room(_live)),
        setup.site.discoverPlayQualities(detail: _room(_live)),
      ]);
      expect(setup.connector.calls, hasLength(2));
      expect(channels.every((channel) => channel.closed), isTrue);
    });

    test('a room the platform said is offline has none, without a request (3.x listed nothing)', () async {
      final setup = _liveSetup();
      await expectLater(
        setup.site.getPlayQualities(detail: _room(_live, status: LiveStatus.offline)),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
    });

    test('an ended program is StreamUnavailable before any seat', () async {
      final setup = _setup([_watchPage('S03-watch-user-ended', 'lv351482791')], channels: [_Channel()]);
      await expectLater(setup.site.getPlayQualities(detail: _room('lv351482791')), throwsA(isA<StreamUnavailable>()));
      expect(setup.connector.calls, isEmpty);
    });

    for (final (name, change, error) in [
      (
        'region',
        (Map<String, dynamic> props) => (props['userProgramWatch'] as Map)['isCountryRestrictionTarget'] = true,
        isA<RegionBlocked>(),
      ),
      (
        'login',
        (Map<String, dynamic> props) => ((props['programWatch'] as Map)['condition'] as Map)['needLogin'] = true,
        isA<NeedsLogin>(),
      ),
      (
        'denied',
        (Map<String, dynamic> props) => (props['userProgramWatch'] as Map)['canWatch'] = false,
        isA<NeedsLogin>(),
      ),
    ]) {
      test('a $name-restricted program is refused before any seat', () async {
        final props = _liveProps();
        change(props);
        final setup = _setup([_syntheticWatch(props)], channels: [_Channel()]);
        await expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(error));
        expect(setup.connector.calls, isEmpty);
      });
    }

    test('a refused master is an error and the seat is still closed', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _live), _synthetic('$_master', '', status: 403)],
        channels: [_Channel(_serverFrames(pings: false))],
      );
      final channel = setup.connector.channels.single;
      await expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(isA<RiskControl>()));
      expect(channel.closed, isTrue);
    });

    test('a seat error before the grant is the typed error', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _live)],
        channels: [
          _Channel([
            _frame('error', {'code': 'TOO_MANY_CONNECTIONS'}),
          ]),
        ],
      );
      await expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(isA<RateLimited>()));
      expect(setup.http.requests, hasLength(1), reason: 'no master without a grant');
    });

    test('a seat that never grants fails after the startup timeout', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _live)],
        channels: [_Channel()],
        seatStartupTimeout: const Duration(milliseconds: 30),
      );
      final channel = setup.connector.channels.single;
      await expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(isA<NetworkFailure>()));
      expect(channel.closed, isTrue);
    });

    test('the deadline cancels the master read and closes the seat', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _live)],
        channels: [_Channel(_serverFrames(pings: false))],
        discoveryDeadline: const Duration(milliseconds: 50),
        wrap: _HoldMedia.new,
      );
      final channel = setup.connector.channels.single;
      await expectLater(
        setup.site.getPlayQualities(detail: _room(_live)),
        throwsA(isA<NetworkFailure>().having((error) => error.detail, 'detail', contains('discovery'))),
      );
      expect(setup.http.requests.last.cancel!.isCancelled, isTrue);
      expect(channel.closed, isTrue);
    });

    test("the caller's cancellation during the master read stops it; the caller's token stays its own", () async {
      late _HoldMedia http;
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _live)],
        channels: [_Channel(_serverFrames(pings: false))],
        wrap: (inner) => http = _HoldMedia(inner),
      );
      final channel = setup.connector.channels.single;
      final cancel = CancelToken();
      final result = expectLater(setup.site.discoverPlayQualities(detail: _room(_live), cancel: cancel), _cancelled());
      final master = await http.started.future;
      expect(master.cancel, isNot(same(cancel)), reason: 'discovery owns its token');
      cancel.cancel();
      await result;
      expect(master.cancel!.isCancelled, isTrue);
      expect(channel.closed, isTrue);
      await expectLater(
        setup.site.discoverPlayQualities(detail: _room(_live), cancel: CancelToken()..cancel()),
        _cancelled(),
      );
      expect(setup.http.requests, hasLength(2), reason: 'nothing sent once cancelled');
    });

    for (final (name, frame, error) in [
      ('ends', _frame('disconnect', {'reason': 'END_PROGRAM'}), isA<StreamUnavailable>()),
      ('moves the stream', _streamFrame(uri: _master.resolve('other.m3u8')), isA<StreamUnavailable>()),
    ]) {
      test('a seat that $name during the master read fails the discovery', () async {
        late _HoldMedia http;
        final channel = _Channel(_serverFrames(pings: false));
        final setup = _setup(
          [_watchPage('S03-watch-user-live', _live)],
          channels: [channel],
          wrap: (inner) => http = _HoldMedia(inner),
        );
        final result = expectLater(setup.site.getPlayQualities(detail: _room(_live)), throwsA(error));
        await http.started.future;
        channel.incoming.add(frame);
        await result;
        expect(channel.closed, isTrue);
      });
    }

    test('openSeat hands the caller an open seat with the current grant', () async {
      final setup = _liveSetup();
      final seat = await setup.site.openSeat(_live);
      expect(seat.current.uri, _master);
      expect(seat.keepIntervalSeconds, 30);
      await pumpEventQueue();
      expect(seat.messageServer?.host, 'mpn.live.nicovideo.jp', reason: 'announced after the grant');
      await seat.close();
      expect(setup.connector.channels, isEmpty);
      expect(await seat.done, isNull);
    });
  });

  group("a broadcaster's streams (17-1)", () {
    test("discovery reads the broadcaster's page and binds the qualities to the room and its program", () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _user), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false))],
      );
      final qualities = await setup.site.getPlayQualities(detail: _room(_user));
      expect(_paths(setup.http), ['/watch/$_user', _master.path]);
      final choice = qualities.last.data! as NiconicoQuality;
      expect(choice.roomId, _user);
      expect(choice.programId, _live);
      expect(qualities.map((quality) => quality.selectionId), ['800x450@1080800', '512x288@412800', '512x288@201600']);
      final resolved = await setup.site.resolvePlayUrls(detail: _room(_user), quality: qualities.last);
      expect(
        (resolved.inputRecipe! as NiconicoInputRecipe).identity,
        'niconico:$_live:512x288:201600',
        reason: 'the recipe is the program on air',
      );
      await expectLater(
        setup.site.resolvePlayUrlsRaw(detail: _room(_live), quality: qualities.last),
        throwsArgumentError,
        reason: "the broadcaster's quality is not the program room's",
      );
      await expectLater(
        setup.site.resolvePlayUrlsRaw(detail: _room('user/1'), quality: qualities.last),
        throwsArgumentError,
      );
    });

    test('openSeat takes a broadcaster: the seat of its program on air', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _user)],
        channels: [_Channel(_serverFrames(pings: false))],
      );
      final seat = await setup.site.openSeat(_user);
      expect(seat.current.uri, _master);
      await pumpEventQueue();
      expect(seat.messageServer?.host, 'mpn.live.nicovideo.jp', reason: 'what the comments need (M5)');
      await seat.close();
      await expectLater(setup.site.openSeat('user/0'), throwsA(isA<NotFound>()));
    });

    for (final (name, change, error) in [
      (
        'paid',
        (Map<String, dynamic> props) {
          (props['userProgramWatch'] as Map)['canWatch'] = false;
          ((props['programWatch'] as Map)['condition'] as Map)['payment'] = 'Ticket';
        },
        isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('paid')),
      ),
      (
        'private',
        (Map<String, dynamic> props) {
          (props['userProgramWatch'] as Map)['canWatch'] = false;
          (props['program'] as Map)['isPrivate'] = true;
        },
        isA<StreamUnavailable>().having((e) => e.detail, 'detail', contains('private')),
      ),
    ]) {
      test('a $name program is live and marked; its stream says why before any seat', () async {
        final props = _liveProps();
        change(props);
        final setup = _setup([_syntheticWatch(props, program: _user)], channels: [_Channel()]);
        final room = await setup.site.getRoomDetail(roomId: _user);
        expect(room.isLiveNow, isTrue);
        expect(room.isRestricted, isTrue);
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(error));
        expect(setup.connector.calls, isEmpty);
      });
    }

    test('a card marked paid is not refused by its mark: the watch page decides (a free part)', () async {
      final setup = _setup(
        [_watchPage('S03-watch-channel', 'ch2640864'), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false))],
      );
      final card = LiveRoom(
        roomId: 'ch2640864',
        platform: 'niconico',
        liveStatus: LiveStatus.live,
        restriction: LiveRestriction.paid,
      );
      expect(await setup.site.getPlayQualities(detail: card), hasLength(3));
    });
  });

  group('the entered room hands its seat bootstrap to the first discovery (17-6)', () {
    test('entering and playing reads the watch page once', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _user), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false)), _Channel(_serverFrames(pings: false))],
      );
      final room = await setup.site.getRoomDetail(roomId: _user);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities, hasLength(3));
      expect(_paths(setup.http), ['/watch/$_user', _master.path], reason: 'no second watch page (v3 read it twice)');
      expect(setup.connector.calls.single.endpoint.queryParameters['frontend_id'], '9');
      await setup.site.getPlayQualities(detail: room);
      expect(_paths(setup.http), [
        '/watch/$_user',
        _master.path,
        '/watch/$_user',
        _master.path,
      ], reason: 'taken once: the next discovery reads the page');
    });

    test('an old id entered is kept under its broadcaster', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _live), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false))],
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      await setup.site.getPlayQualities(detail: room);
      expect(_paths(setup.http), ['/watch/$_live', _master.path]);
    });

    test('a bootstrap older than its lifetime is dropped', () async {
      var now = DateTime.utc(2026, 9, 29);
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _user), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false))],
        clock: () => now,
      );
      final room = await setup.site.getRoomDetail(roomId: _user);
      now = now.add(const Duration(seconds: 61));
      await setup.site.getPlayQualities(detail: room);
      expect(_paths(setup.http), ['/watch/$_user', '/watch/$_user', _master.path]);
    });

    test('refresh, recording and the live state keep nothing; a zero lifetime turns it off', () async {
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _user), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false))],
      );
      await setup.site.getRoomDetailForRefresh(roomId: _user);
      await setup.site.getRoomDetailForRecording(roomId: _user);
      await setup.site.getLiveStatus(roomId: _user);
      await setup.site.getPlayQualities(detail: _room(_user));
      expect(_paths(setup.http).where((path) => path.startsWith('/watch/')), hasLength(4));
      final off = _setup(
        [_watchPage('S03-watch-user-live', _user), _synthetic('$_master', _officialMaster)],
        channels: [_Channel(_serverFrames(pings: false))],
        bootstrapLifetime: Duration.zero,
      );
      await off.site.getRoomDetail(roomId: _user);
      await off.site.getPlayQualities(detail: _room(_user));
      expect(_paths(off.http), ['/watch/$_user', '/watch/$_user', _master.path]);
    });

    test('a refused kept bootstrap is retried once on a fresh page', () async {
      final refused = _Channel([
        _frame('error', {'code': 'CONNECT_ERROR'}),
      ]);
      final setup = _setup(
        [_watchPage('S03-watch-user-live', _user), _synthetic('$_master', _officialMaster)],
        channels: [refused, _Channel(_serverFrames(pings: false))],
      );
      final room = await setup.site.getRoomDetail(roomId: _user);
      expect(await setup.site.getPlayQualities(detail: room), hasLength(3));
      expect(_paths(setup.http), ['/watch/$_user', '/watch/$_user', _master.path]);
      expect(setup.connector.calls, hasLength(2));
      expect(refused.closed, isTrue);
    });

    test('an offline or restricted room keeps no bootstrap; a cancelled discovery is not retried', () async {
      final setup = _setup([_watchPage('S03-watch-user-ended', 'user/138383030')]);
      await setup.site.getRoomDetail(roomId: 'user/138383030');
      await expectLater(
        setup.site.getPlayQualities(detail: _room('user/138383030')),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(2), reason: 'the page read again: nothing was kept');
      final held = _Connector([_Channel()])..gate = Completer<void>();
      final http = ReplayHttp([_watchPage('S03-watch-user-live', _user)]);
      final site = NiconicoSite(http, connector: held.call);
      final room = await site.getRoomDetail(roomId: _user);
      final cancel = CancelToken();
      final result = expectLater(site.discoverPlayQualities(detail: room, cancel: cancel), _cancelled());
      await pumpEventQueue();
      cancel.cancel();
      await result;
      held.gate!.complete();
      expect(held.calls, hasLength(1), reason: 'no second seat after a cancellation');
      expect(http.requests, hasLength(1));
    });
  });

  group('recipe', () {
    Future<(NiconicoSite, List<LivePlayQuality>, ReplayHttp)> discovered() async {
      final setup = _liveSetup();
      return (setup.site, await setup.site.getPlayQualities(detail: _room(_live)), setup.http);
    }

    test('the chosen quality resolves to the owned recipe, for playback, recovery and the recorder', () async {
      final (site, qualities, http) = await discovered();
      final requests = http.requests.length;
      final resolved = await site.resolvePlayUrls(detail: _room(_live), quality: qualities.last);
      final recipe = resolved.inputRecipe! as NiconicoInputRecipe;
      expect(recipe.identity, 'niconico:$_live:512x288:201600');
      expect(resolved.urls, isEmpty);
      expect(resolved.hasSources, isTrue);
      expect(resolved.lineCount, 1);
      expect(resolved.appliedQualityData, '512x288@201600');
      expect(
        (await site.resolvePlayUrlsForRecovery(detail: _room(_live), quality: qualities.last)).inputRecipe,
        recipe,
      );
      expect(await site.getPlayUrls(detail: _room(_live), quality: qualities.last), isEmpty);
      final first = await site.resolvePlayUrlAtRaw(detail: _room(_live), quality: qualities.last, lineIndex: 0);
      expect(first.inputRecipe, recipe);
      final second = await site.resolvePlayUrlAtRaw(detail: _room(_live), quality: qualities.last, lineIndex: 1);
      expect(second.hasSources, isFalse);
      expect(http.requests, hasLength(requests), reason: 'resolving opens nothing');
    });

    test("another program's or a relabelled quality is refused; an offline room has no stream", () async {
      final (site, qualities, _) = await discovered();
      await expectLater(
        site.resolvePlayUrlsRaw(detail: _room('lv351482869'), quality: qualities.first),
        throwsArgumentError,
      );
      await expectLater(
        site.resolvePlayUrlsRaw(
          detail: _room(_live),
          quality: LivePlayQuality(quality: 'forged', id: 'wrong', data: qualities.first.data),
        ),
        throwsArgumentError,
      );
      await expectLater(
        site.resolvePlayUrlsRaw(
          detail: _room(_live),
          quality: const LivePlayQuality(quality: 'x', id: 'x'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        site.resolvePlayUrlsRaw(
          detail: _room(_live, status: LiveStatus.offline),
          quality: qualities.first,
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        site.resolvePlayUrlsRaw(
          detail: LiveRoom(roomId: _live, platform: 'bilibili'),
          quality: qualities.first,
        ),
        throwsArgumentError,
      );
    });
  });

  group('seat protocol', () {
    test('the recorded conversation: grant, keepSeat, ping, close', () async {
      final clock = _Clock();
      final channel = _Channel(_serverFrames(pings: false));
      final seat = await _open(channel, clock);
      expect(channel.types, ['startWatching', 'getAkashic']);
      expect(seat.keepIntervalSeconds, 30);
      expect(seat.current.uri, _master);
      expect(seat.current.cookieCount, 13);
      clock.advance(const Duration(seconds: 60));
      expect(seat.keepSeatsSent, 2);
      channel.server('ping');
      await pumpEventQueue();
      expect(seat.pongsSent, 1);
      expect(seat.keepSeatsSent, 3, reason: 'a ping is answered with pong and one more keepSeat (3.x)');
      expect(channel.types.skip(2), ['keepSeat', 'keepSeat', 'pong', 'keepSeat']);
      final grant = seat.current;
      await seat.close();
      expect(await seat.done, isNull);
      expect(channel.closed, isTrue);
      expect(grant.isActive, isFalse);
      expect(grant.cookieCount, 0);
      expect(() => seat.current, throwsA(isA<StreamUnavailable>()));
      final sent = channel.sent.length;
      clock.advance(const Duration(seconds: 100));
      expect(channel.sent, hasLength(sent), reason: 'nothing after close');
    });

    test('a stream before the seat is kept but does not open it', () async {
      final clock = _Clock();
      final channel = _Channel([_streamFrame(value: 'first')]);
      var opened = false;
      final future = _open(channel, clock).then((seat) {
        opened = true;
        return seat;
      });
      await pumpEventQueue();
      expect(opened, isFalse);
      channel.server('seat', {'keepIntervalSec': 30});
      final seat = await future;
      expect(seat.keepIntervalSeconds, 30);
      await seat.close();
    });

    test('a new seat interval replaces the timer instead of adding one', () async {
      final clock = _Clock();
      final channel = _Channel(_serverFrames(pings: false));
      final seat = await _open(channel, clock);
      channel.server('seat', {'keepIntervalSec': 3});
      await pumpEventQueue();
      clock.advance(const Duration(seconds: 2));
      expect(seat.keepSeatsSent, 0);
      clock.advance(const Duration(seconds: 1));
      expect(seat.keepSeatsSent, 1);
      await seat.close();
    });

    test('a new stream replaces the grant and revokes the old one', () async {
      final clock = _Clock();
      final channel = _Channel(_serverFrames(pings: false));
      final seat = await _open(channel, clock);
      final previous = seat.current;
      final updates = <NiconicoGrant>[];
      final listener = seat.changes.listen(updates.add);
      channel.incoming.add(_streamFrame());
      await pumpEventQueue();
      expect(updates, hasLength(1));
      expect(previous.isActive, isFalse);
      expect(seat.current.cookieHeaderFor(seat.current.uri), contains('rotated'));
      await listener.cancel();
      await seat.close();
    });

    for (final (name, end, error) in [
      ('disconnect', (_Channel c) => c.server('disconnect', {'reason': 'END_PROGRAM'}), isA<StreamUnavailable>()),
      ('error', (_Channel c) => c.server('error', {'code': 'NO_PERMISSION'}), isA<NeedsLogin>()),
      ('malformed', (_Channel c) => c.incoming.add('invalid-json'), isA<ApiChanged>()),
      ('binary', (_Channel c) => c.incoming.add(<int>[1, 2]), isA<ApiChanged>()),
      ('invalid stream', (_Channel c) => c.server('stream', {'protocol': 'dash'}), isA<ApiChanged>()),
      ('socket error', (_Channel c) => c.incoming.addError(StateError('private details')), isA<NetworkFailure>()),
      ('socket done', (_Channel c) => unawaited(c.incoming.close()), isA<NetworkFailure>()),
    ]) {
      test('$name ends the seat without a hidden reconnect', () async {
        final clock = _Clock();
        final channel = _Channel(_serverFrames(pings: false));
        final connector = _Connector([channel]);
        final seat = await _open(channel, clock, connector: connector);
        final grant = seat.current;
        end(channel);
        expect(await seat.done, error);
        expect(seat.isClosed, isTrue);
        expect(grant.isActive, isFalse);
        expect(channel.closed, isTrue);
        clock.advance(const Duration(seconds: 100));
        expect(connector.calls, hasLength(1));
      });
    }

    test('90 s of silence ends a half-open seat', () async {
      final clock = _Clock();
      final channel = _Channel(_serverFrames(pings: false));
      final seat = await _open(channel, clock);
      clock.advance(const Duration(seconds: 89));
      expect(seat.isClosed, isFalse, reason: 'keepSeat is no answer, but nothing timed out yet');
      clock.advance(const Duration(seconds: 1));
      expect(await seat.done, isA<NetworkFailure>());
    });

    for (final interval in [0, -1, 301, '30', null]) {
      test('a seat interval $interval fails the open', () async {
        final channel = _Channel([
          _frame('seat', {'keepIntervalSec': interval}),
        ]);
        await expectLater(_open(channel, _Clock()), throwsA(isA<ApiChanged>()));
        expect(channel.closed, isTrue);
      });
    }

    test('the startup timeout ends a pending handshake; the late socket is closed unused', () async {
      final clock = _Clock();
      final channel = _Channel(_serverFrames(pings: false));
      final connector = _Connector([channel])..gate = Completer<void>();
      final result = expectLater(_open(channel, clock, connector: connector), throwsA(isA<NetworkFailure>()));
      await pumpEventQueue();
      clock.advance(const Duration(seconds: 20));
      await result;
      connector.gate!.complete();
      await pumpEventQueue();
      expect(channel.closed, isTrue);
      expect(channel.sent, isEmpty);
    });

    test('cancelling during the handshake ends the seat at once', () async {
      final channel = _Channel(_serverFrames(pings: false));
      final connector = _Connector([channel])..gate = Completer<void>();
      final cancel = CancelToken();
      final result = expectLater(_open(channel, _Clock(), connector: connector, cancel: cancel), _cancelled());
      await pumpEventQueue();
      cancel.cancel();
      await result;
      connector.gate!.complete();
      await pumpEventQueue();
      expect(channel.closed, isTrue);
      expect(channel.sent, isEmpty);
    });

    test('a failed send ends the seat instead of counting a keepalive', () async {
      final channel = _Channel(_serverFrames(pings: false));
      final seat = await _open(channel, _Clock());
      channel
        ..failSends = true
        ..server('ping');
      expect(await seat.done, isA<NetworkFailure>());
      expect(seat.pongsSent, 0);
    });

    test('closing waits for the socket at most the close timeout', () async {
      final channel = _Channel(_serverFrames(pings: false));
      final seat = await _open(channel, _Clock(), closeTimeout: const Duration(milliseconds: 20));
      channel.closeGate = Completer<void>();
      final closing = seat.close();
      expect(identical(closing, seat.close()), isTrue);
      await closing;
      expect(await seat.done, isNull);
      channel.closeGate!.complete();
    });

    test('a socket that is not the seat endpoint, or a cancelled token, connects nothing', () async {
      final connector = _Connector([_Channel()]);
      await expectLater(
        NiconicoSeat.open(Uri.parse('wss://elsewhere.test/unama/wsapi/v2/watch/1?t=x'), connector: connector.call),
        throwsA(isA<ApiChanged>()),
      );
      await expectLater(
        NiconicoSeat.open(_socket, connector: connector.call, cancel: CancelToken()..cancel()),
        _cancelled(),
      );
      expect(connector.calls, isEmpty);
    });
  });

  group('links', () {
    test('broadcaster links need no request (17-2)', () async {
      final http = ReplayHttp(const []);
      final site = NiconicoSite(http);
      expect(site.roomIdFromUrl('https://live.nicovideo.jp/watch/user/144846457'), _user);
      expect(site.roomIdFromUrl('https://ch.nicovideo.jp/channel/ch2640864'), 'ch2640864');
      expect(site.roomIdFromUrl('https://live.nicovideo.jp/watch/lv100'), isNull, reason: 'a program is resolved');
      expect(site.needsResolving('https://live.nicovideo.jp/watch/user/144846457'), isFalse);
      final parser = LinkParser(SiteRegistry({'niconico': () => site}), http);
      expect(parser.containsSupportedLink('主播 https://www.nicovideo.jp/user/144846457'), isTrue);
      expect(await parser.parse('主播 https://www.nicovideo.jp/user/144846457。快来'), const RoomLink('niconico', _user));
      expect(await parser.parse('https://ch.nicovideo.jp/ch2640864/live'), const RoomLink('niconico', 'ch2640864'));
      expect(await parser.parse('https://live.nicovideo.jp/watch/lv0'), isNull);
      expect(http.requests, isEmpty);
    });

    test("a program link is its broadcaster's room: one request for the program's own watch page", () async {
      final http = ReplayHttp([_watchPage('S03-watch-user-live', _live)]);
      final site = NiconicoSite(http);
      for (final url in [
        'https://live.nicovideo.jp/watch/$_live?ref=share',
        'http://live.nicovideo.jp/watch/$_live',
        'https://sp.live.nicovideo.jp/watch/$_live',
        'https://nico.ms/$_live',
      ]) {
        expect(site.needsResolving(url), isTrue, reason: url);
        final parser = LinkParser(SiteRegistry({'niconico': () => site}), http);
        expect(parser.containsSupportedLink('节目 $url'), isTrue);
        expect(await parser.parse('节目 $url。快来'), const RoomLink('niconico', _user), reason: url);
      }
      expect(http.requests.map((request) => request.url.toString()).toSet(), {
        'https://live.nicovideo.jp/watch/$_live',
      });
      expect(http.requests.first.headers, NiconicoApi.headers);
      expect(http.requests.first.followRedirects, isFalse);
    });

    test('an official program link stays the program; an unreadable page falls back to the program', () async {
      final http = ReplayHttp([
        _watchPage('S03-watch-official', 'lv351173882'),
        ReplaySample.load('$_root/S03-watch-notfound'),
        _synthetic('https://live.nicovideo.jp/watch/lv2', 'not a watch page'),
      ]);
      final parser = LinkParser(SiteRegistry({'niconico': () => NiconicoSite(http)}), http);
      expect(await parser.parse('https://nico.ms/lv351173882'), const RoomLink('niconico', 'lv351173882'));
      expect(
        await parser.parse('https://nico.ms/lv1'),
        const RoomLink('niconico', 'lv1'),
        reason: '404: entering says so',
      );
      expect(await parser.parse('https://nico.ms/lv2'), const RoomLink('niconico', 'lv2'));
      final failing = LinkParser(
        SiteRegistry({'niconico': () => NiconicoSite(_Failing(TransportReason.connect))}),
        _Failing(TransportReason.connect),
      );
      expect(await failing.parse('https://nico.ms/lv3'), const RoomLink('niconico', 'lv3'));
    });
  });
}

/// Answers from [inner] but cancels [cancel] first, as if the caller gave
/// up while the answer was on its way.
final class _CancelOnAnswer implements LiveHttp {
  new(this.inner, this.cancel);

  final ReplayHttp inner;
  final CancelToken cancel;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final response = await inner.send(request);
    cancel.cancel();
    return response;
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}
