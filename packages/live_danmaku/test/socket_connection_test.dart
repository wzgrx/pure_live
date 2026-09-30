import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

final class _FakeChannel implements SocketChannel {
  new({this.closeCode, this.closeReason});

  final StreamController<Object?> incoming = StreamController<Object?>();
  final List<Object> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  final int? closeCode;

  @override
  final String? closeReason;
}

/// Hands out fake channels and records every handshake.
final class _Connector {
  new({
    this.fail = false,
    this.stall = false,
    this.failures = const [],
    this.gate,
    this.refuse,
    _FakeChannel Function()? make,
  }) : make = make ?? _FakeChannel.new;

  final bool fail;
  final bool stall;

  /// Every handshake waits for it first.
  final Future<void>? gate;

  /// Thrown by the first handshakes, one each, in order.
  final List<Exception> failures;

  /// Endpoints refused on top of [fail].
  final bool Function(Uri endpoint)? refuse;
  final _FakeChannel Function() make;
  final List<Uri> endpoints = [];
  final List<Map<String, String>> headers = [];
  final List<Iterable<String>?> protocols = [];
  final List<_FakeChannel> channels = [];
  final Completer<void> _never = Completer<void>();

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    endpoints.add(endpoint);
    this.headers.add(headers);
    this.protocols.add(protocols);
    await gate;
    if (fail || (refuse?.call(endpoint) ?? false)) throw const SocketException('refused');
    if (endpoints.length <= failures.length) throw failures[endpoints.length - 1];
    if (stall) await _never.future;
    final channel = make();
    channels.add(channel);
    return channel;
  }
}

/// B-1: what a test platform answers a failed handshake with.
typedef _Renew = FutureOr<Map<String, String>?> Function(DanmakuHandshakeFailure failure);

/// A platform that joins with a text frame and reads text frames:
/// `joined` confirms the join, `fail` is a protocol failure, anything else is
/// a chat line.
final class _Platform extends DanmakuSocketConnection<DanmakuSocketTarget> {
  new({required super.policy, required _Connector connector, this.readyOnOpen = true, this.joinTimeoutNotice})
    : super(site: SiteIds.douyu, connector: connector.call);

  final bool readyOnOpen;
  final DanmakuInterruption? joinTimeoutNotice;
  final List<DanmakuSocketSession> opens = [];
  int joinTimeouts = 0;
  bool showFailureDetail = false;
  Exception? targetFailure;

  @override
  Future<DanmakuSocketTarget> target(DanmakuSocketTarget args, DanmakuRun run) async {
    final failure = targetFailure;
    if (failure != null) throw failure;
    return args;
  }

  @override
  void onOpen(DanmakuSocketSession session) {
    opens.add(session);
    session.send('join');
    if (readyOnOpen) session.ready();
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) {
    switch (data) {
      case 'joined':
        session.ready();
      case 'fail':
        session
          ..markDisconnected()
          ..reconnect(notice: DanmakuInterruption.protocolError, detail: 'bad packet');
      default:
        session.message(
          LiveMessage(type: LiveMessageType.chat, userName: 'u', message: '$data', color: LiveMessageColor.white),
        );
    }
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => 'hb';

  @override
  void onJoinTimeout(DanmakuSocketSession session) {
    joinTimeouts++;
    final notice = joinTimeoutNotice;
    if (notice == null) {
      super.onJoinTimeout(session);
    } else {
      session.reconnect(notice: notice);
    }
  }

  @override
  String reconnectDetail(String lastFailure) => showFailureDetail ? lastFailure : super.reconnectDetail(lastFailure);

  /// B-1: the failed handshakes reported, and what to answer them with
  /// (the default hook when null).
  final List<DanmakuHandshakeFailure> handshakeFailures = [];
  _Renew? renew;

  @override
  FutureOr<Map<String, String>?> onHandshakeFailure(DanmakuSocketSession session, DanmakuHandshakeFailure failure) {
    handshakeFailures.add(failure);
    final answer = renew;
    return answer == null ? super.onHandshakeFailure(session, failure) : answer(failure);
  }

  /// What the platform does when the reconnects run out; null keeps the
  /// runtime's default.
  bool Function(DanmakuSocketSession session, String lastFailure)? exhausted;

  @override
  bool onReconnectsExhausted(DanmakuSocketSession session, String lastFailure) =>
      exhausted?.call(session, lastFailure) ?? super.onReconnectsExhausted(session, lastFailure);
}

final Uri _primary = Uri.parse('wss://primary.example/ws');
final Uri _backup = Uri.parse('wss://backup.example/ws');
final DanmakuSocketTarget _target = DanmakuSocketTarget(
  endpoints: [_primary, _backup],
  headers: const {'Origin': 'https://www.douyu.com'},
  protocols: const ['chat'],
);

List<DanmakuEvent> _record(DanmakuConnection connection) {
  final events = <DanmakuEvent>[];
  connection.events.listen(events.add);
  return events;
}

Iterable<String> _texts(List<DanmakuEvent> events) => events.whereType<DanmakuReceived>().map((e) => e.message.message);

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [condition] holds, at most two seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await _wait(const Duration(milliseconds: 2));
  }
}

void main() {
  test('opens the first endpoint, joins, reports ready and messages, sends heartbeats', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration(milliseconds: 15),
        inactivityTimeout: Duration(seconds: 5),
      ),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    expect(connection.isConnected, isTrue);
    expect(connection.heartbeatInterval, const Duration(milliseconds: 15));
    expect(connector.endpoints, [_primary]);
    expect(connector.headers.single, {'Origin': 'https://www.douyu.com'});
    expect(connector.protocols.single, ['chat']);

    final channel = connector.channels.single;
    channel.incoming
      ..add('hello')
      ..add('world');
    await _until(() => channel.sent.where((frame) => frame == 'hb').length >= 2);
    expect(channel.sent.first, 'join');
    expect(events.first, const DanmakuReady());
    expect(_texts(events), ['hello', 'world']);
    await connection.close();
  });

  test('a join confirmed by the platform reports ready only then', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
      readyOnOpen: false,
    );
    final events = _record(connection);
    await connection.connect(_target);
    expect(connection.status, DanmakuStatus.connecting);
    connector.channels.single.incoming.add('joined');
    await _until(() => events.isNotEmpty);
    expect(connection.isConnected, isTrue);
    expect(events, [const DanmakuReady()]);
    await connection.close();
  });

  test('an unconfirmed join reconnects after the join timeout, without a notice of its own', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration.zero,
        joinTimeout: Duration(milliseconds: 30),
        reconnectBaseDelay: Duration(milliseconds: 5),
      ),
      connector: connector,
      readyOnOpen: false,
    );
    final events = _record(connection);
    await connection.connect(_target);
    await _until(() => connector.channels.length == 2);
    expect(connection.joinTimeouts, 1);
    expect(connector.channels.first.closed, isTrue);
    expect(connector.endpoints, [_primary, _backup]);
    connector.channels.last.incoming.add('joined');
    await _until(() => connection.isConnected);
    expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
    await connection.close();
  });

  test('a confirmed join stops the join timer', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero, joinTimeout: Duration(milliseconds: 20)),
      connector: connector,
      readyOnOpen: false,
    );
    await connection.connect(_target);
    connector.channels.single.incoming.add('joined');
    await _wait(const Duration(milliseconds: 50));
    expect(connection.joinTimeouts, 0);
    expect(connector.channels, hasLength(1));
    await connection.close();
  });

  test('a join timeout with a notice reports it, then the socket reports its own (3.x YY)', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration.zero,
        joinTimeout: Duration(milliseconds: 20),
        reconnectBaseDelay: Duration(milliseconds: 5),
      ),
      connector: connector,
      readyOnOpen: false,
      joinTimeoutNotice: DanmakuInterruption.handshakeTimeout,
    );
    final events = _record(connection);
    await connection.connect(_target);
    await _until(() => connector.channels.length == 2);
    expect(events, [
      const DanmakuReconnecting(DanmakuInterruption.handshakeTimeout),
      const DanmakuReconnecting(DanmakuInterruption.disconnected),
    ]);
    await connection.close();
  });

  test('a protocol failure reports its notice and reconnects', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration.zero,
        reconnectBaseDelay: Duration(milliseconds: 5),
      ),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    connector.channels.single.incoming.add('fail');
    await _until(() => connector.channels.length == 2 && connection.isConnected);
    expect(events, [
      const DanmakuReady(),
      const DanmakuReconnecting(DanmakuInterruption.protocolError, detail: 'bad packet'),
      const DanmakuReconnecting(DanmakuInterruption.disconnected),
      const DanmakuReady(),
    ]);
    await connection.close();
  });

  test('a silent socket is replaced on the next endpoint; one notice per streak', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration(milliseconds: 10),
        inactivityTimeout: Duration(milliseconds: 25),
        reconnectBaseDelay: Duration(milliseconds: 5),
      ),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    await _until(() => connector.channels.length >= 3);
    await connection.close();
    expect(connector.endpoints.take(3), [_primary, _backup, _primary]);
    expect(connector.channels.first.closed, isTrue);
    expect(events.whereType<DanmakuReconnecting>(), hasLength(1), reason: 'no message arrived in between');
    expect(events.whereType<DanmakuReady>().length, greaterThanOrEqualTo(3), reason: '3.x reported every reopen');
  });

  test('the reconnect notice can carry the last failure (3.x YY)', () async {
    final connector = _Connector(make: () => _FakeChannel(closeCode: 1008, closeReason: 'policy'));
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
    )..showFailureDetail = true;
    final events = _record(connection);
    await connection.connect(_target);
    await connector.channels.single.incoming.close();
    await _until(() => events.length == 2);
    expect(
      events.last,
      const DanmakuReconnecting(DanmakuInterruption.disconnected, detail: 'WebSocket closed (code=1008): policy'),
    );
    await connection.close();
  });

  test("reconnects back off as 3.x did and give up after the policy's count", () async {
    final delays = <Duration>[];
    const unit = Duration(seconds: 1000);
    final connector = _Connector(fail: true);
    final events = <DanmakuEvent>[];
    late _Platform connection;
    await runZoned(
      () async {
        connection = _Platform(
          policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero, reconnectBaseDelay: unit),
          connector: connector,
        );
        connection.events.listen(events.add);
        await connection.connect(_target);
        expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)], reason: 'connect returns');
        await _until(() => events.length == 2);
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration < unit) return parent.createTimer(zone, duration, callback);
          // Record the backoff and run it at once.
          delays.add(duration);
          return parent.createTimer(zone, Duration.zero, callback);
        },
      ),
    );
    // Next endpoint at once; one more step after each full round of two.
    expect(delays, [
      for (final step in [1, 2, 2, 3, 3, 4, 4, 5]) unit * step,
    ]);
    expect(connector.endpoints, [
      for (var attempt = 0; attempt < 9; attempt++)
        if (attempt.isEven) _primary else _backup,
    ]);
    expect(
      events.last,
      isA<DanmakuClosed>().having((event) => event.reason, 'reason', DanmakuCloseReason.reconnectsExhausted),
    );
    expect((events.last as DanmakuClosed).detail, contains('refused'));
    expect(connection.status, DanmakuStatus.closed);
  });

  group('onReconnectsExhausted (added for M5.F B-5, Douyin)', () {
    final fresh = DanmakuSocketTarget(endpoints: [Uri.parse('wss://fresh.example/ws')]);

    /// Runs [body] with every backoff wait (a second or more) fired at once.
    Future<void> fast(Future<void> Function() body) => runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) =>
            parent.createTimer(zone, duration < const Duration(seconds: 1) ? duration : Duration.zero, callback),
      ),
    );

    test('a platform that takes over can reopen elsewhere: no close, fresh reconnects', () async {
      final connector = _Connector(refuse: (endpoint) => endpoint != fresh.endpoints.single);
      final connection = _Platform(
        policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
        connector: connector,
      );
      final failures = <String>[];
      connection.exhausted = (session, lastFailure) {
        failures.add(lastFailure);
        unawaited(session.reopen(fresh));
        return true;
      };
      final events = _record(connection);
      await fast(() async {
        await connection.connect(_target);
        await _until(() => connection.isConnected);
      });
      expect(failures, [contains('refused')], reason: 'asked once, after the ninth failure');
      expect(connector.endpoints, hasLength(10));
      expect(connector.endpoints.last, fresh.endpoints.single);
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('a platform that takes over can end the run itself', () async {
      final connector = _Connector(fail: true);
      final connection =
          _Platform(
              policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
              connector: connector,
            )
            ..exhausted = (session, lastFailure) {
              session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'gone');
              return true;
            };
      final events = _record(connection);
      await fast(() async {
        await connection.connect(_target);
        await _until(() => events.whereType<DanmakuClosed>().isNotEmpty);
      });
      expect(events, [
        const DanmakuReconnecting(DanmakuInterruption.disconnected),
        const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'gone'),
      ]);
      expect(connector.endpoints, hasLength(9));
      expect(connection.status, DanmakuStatus.closed);
    });
  });

  test('a message resets the reconnect count', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration.zero,
        reconnectBaseDelay: Duration(milliseconds: 5),
      ),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    await connector.channels.single.incoming.close();
    await _until(() => connector.channels.length == 2);
    connector.channels.last.incoming.add('back');
    await _until(() => _texts(events).isNotEmpty);
    await connector.channels.last.incoming.close();
    await _until(() => connector.channels.length == 3);
    expect(events.whereType<DanmakuReconnecting>(), hasLength(2), reason: 'a new streak after the message');
    await connection.close();
  });

  test('close stops everything: no event, heartbeat or reconnect afterwards', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(
        heartbeatInterval: Duration(milliseconds: 5),
        reconnectBaseDelay: Duration(milliseconds: 5),
      ),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    final channel = connector.channels.single;
    await connection.close();
    await connection.close();
    final sent = channel.sent.length;
    channel.incoming.add('late');
    await _wait(const Duration(milliseconds: 40));
    expect(channel.closed, isTrue);
    expect(channel.sent, hasLength(sent));
    expect(connector.channels, hasLength(1));
    expect(events, [const DanmakuReady()]);
    expect(connection.status, DanmakuStatus.idle);
    connection.heartbeat();
    expect(channel.sent, hasLength(sent));
  });

  test('close aborts a stalled handshake; connect then completes', () async {
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: _Connector(stall: true),
    );
    final events = _record(connection);
    final connecting = connection.connect(_target);
    await _wait(const Duration(milliseconds: 5));
    await connection.close().timeout(const Duration(milliseconds: 200));
    await connecting.timeout(const Duration(milliseconds: 200));
    expect(events, isEmpty);
  });

  test('connecting to another room closes the first socket', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    final other = DanmakuSocketTarget(endpoints: [Uri.parse('wss://other.example/ws')]);
    await connection.connect(other);
    connector.channels.first.incoming.add('from the first room');
    connector.channels.last.incoming.add('from the second room');
    await _until(() => _texts(events).isNotEmpty);
    expect(connector.channels.first.closed, isTrue);
    expect(connector.endpoints.last, other.endpoints.single);
    expect(_texts(events), ['from the second room']);
    await connection.close();
  });

  test('reopen moves to a new target without a notice (3.x Bilibili after new credentials)', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(_target);
    final session = connection.opens.single;
    final refreshed = DanmakuSocketTarget(endpoints: [Uri.parse('wss://refreshed.example/sub')]);
    await session.reopen(refreshed);
    expect(connector.channels.first.closed, isTrue);
    expect(connector.endpoints.last, refreshed.endpoints.single);
    expect(connection.opens, hasLength(2));
    expect(identical(connection.opens.last, session), isTrue, reason: 'one session per run');
    expect(events, [const DanmakuReady(), const DanmakuReady()]);
    await connection.close();
  });

  test('a known start failure closes without opening a socket', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
    )..targetFailure = const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable);
    final events = _record(connection);
    await connection.connect(_target);
    expect(events, [const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable)]);
    expect(connector.endpoints, isEmpty);
  });

  test('a target without endpoints fails instead of staying "connecting"', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
    );
    final events = _record(connection);
    await connection.connect(DanmakuSocketTarget(endpoints: [Uri()]));
    expect(events, [const DanmakuClosed(DanmakuCloseReason.connectionFailed, detail: 'No endpoint')]);
    expect(connection.status, DanmakuStatus.closed);
    expect(connector.endpoints, isEmpty);
  });

  test('heartbeat() sends the frame now while a socket is open', () async {
    final connector = _Connector();
    final connection = _Platform(
      policy: const DanmakuSocketPolicy(heartbeatInterval: Duration.zero),
      connector: connector,
    )..heartbeat();
    await connection.connect(_target);
    connection.heartbeat();
    expect(connector.channels.single.sent, ['join', 'hb']);
    await connection.close();
  });

  group('handshake failures (B-1)', () {
    const policy = DanmakuSocketPolicy(heartbeatInterval: Duration.zero, reconnectBaseDelay: Duration(milliseconds: 5));
    const refused = WebSocketException(
      "Connection to 'https://primary.example:0/ws#' was not upgraded to websocket",
      403,
    );
    const renewed = {'Origin': 'https://www.douyu.com', 'Cookie': 'session=new'};

    test('a refused handshake is reported; renewed headers go with the next one, after the backoff', () async {
      final connector = _Connector(failures: [refused]);
      final connection = _Platform(policy: policy, connector: connector)..renew = (_) async => renewed;
      final events = _record(connection);
      await connection.connect(_target);
      await _until(() => connection.isConnected);
      final failure = connection.handshakeFailures.single;
      expect(failure.endpoint, _primary);
      expect(failure.error, same(refused));
      expect(failure.refused, isTrue);
      expect(failure.statusCode, 403);
      expect(connector.endpoints, [_primary, _backup], reason: 'the backoff moved on as for any failure');
      expect(connector.headers, [_target.headers, renewed]);
      expect(connector.protocols, everyElement(['chat']));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected), const DanmakuReady()]);
      await connection.close();
    });

    test('the next handshake waits for the renewal', () async {
      final renewal = Completer<Map<String, String>?>();
      final connector = _Connector(failures: [refused]);
      final connection = _Platform(policy: policy, connector: connector)..renew = (_) => renewal.future;
      await connection.connect(_target);
      await _wait(const Duration(milliseconds: 60));
      expect(connector.endpoints, hasLength(1), reason: 'the backoff is over; the handshake waits');
      renewal.complete(renewed);
      await _until(() => connection.isConnected);
      expect(connector.headers.last, renewed);
      await connection.close();
    });

    test('headers given at once apply at once; null, the default and a failed renewal keep them', () async {
      for (final (name, renew, expected) in <(String, _Renew?, Map<String, String>)>[
        ('at once', (_) => renewed, renewed),
        ('null', (_) => null, _target.headers),
        ('a future of null', (_) async => null, _target.headers),
        ('the default', null, _target.headers),
        ('a failed future', (_) => Future<Map<String, String>?>.error(StateError('no session')), _target.headers),
        ('a throwing hook', (_) => throw StateError('no session'), _target.headers),
      ]) {
        final connector = _Connector(failures: [refused]);
        final connection = _Platform(policy: policy, connector: connector)..renew = renew;
        await connection.connect(_target);
        await _until(() => connection.isConnected);
        expect(connection.handshakeFailures, hasLength(1), reason: name);
        expect(connector.headers.last, expected, reason: name);
        await connection.close();
      }
    });

    test('failures without an answer are reported too, as no refusal and without a status', () async {
      final timeout = TimeoutException('handshake', const Duration(seconds: 10));
      final connector = _Connector(failures: [const SocketException('refused'), timeout, refused]);
      var renewals = 0;
      final connection = _Platform(policy: policy, connector: connector)
        ..renew = (failure) => failure.refused ? {...renewed, 'Round': '${++renewals}'} : null;
      await connection.connect(_target);
      await _until(() => connection.isConnected);
      expect(
        [for (final failure in connection.handshakeFailures) (failure.refused, failure.statusCode)],
        [(false, null), (false, null), (true, 403)],
      );
      expect(connection.handshakeFailures.map((failure) => failure.endpoint), [_primary, _backup, _primary]);
      expect(connector.headers, [
        _target.headers,
        _target.headers,
        _target.headers,
        {...renewed, 'Round': '1'},
      ]);
      // An upgrade that fails its checks is a refusal without a status.
      expect(
        DanmakuHandshakeFailure(
          endpoint: _primary,
          error: const WebSocketException('WebSocket was not upgraded: HTTP/1.1 403 Forbidden'),
        ),
        isA<DanmakuHandshakeFailure>()
            .having((failure) => failure.refused, 'refused', isTrue)
            .having((failure) => failure.statusCode, 'statusCode', isNull),
      );
      await connection.close();
    });

    test('closed while renewing: no handshake, header change or event afterwards', () async {
      final renewal = Completer<Map<String, String>?>();
      final connector = _Connector(failures: [refused]);
      final connection = _Platform(policy: policy, connector: connector)..renew = (_) => renewal.future;
      final events = _record(connection);
      await connection.connect(_target);
      await _wait(const Duration(milliseconds: 30));
      await connection.close().timeout(const Duration(seconds: 2));
      renewal.complete(renewed);
      await _wait(const Duration(milliseconds: 60));
      expect(connector.endpoints, hasLength(1));
      expect(events, [const DanmakuReconnecting(DanmakuInterruption.disconnected)]);
      expect(connection.status, DanmakuStatus.idle);
    });

    test("renewed headers belong to the socket: reopen and another room start from their own target's", () async {
      final connector = _Connector(failures: [refused]);
      final connection = _Platform(policy: policy, connector: connector)..renew = (_) => renewed;
      await connection.connect(_target);
      await _until(() => connection.isConnected);
      final refreshed = DanmakuSocketTarget(
        endpoints: [Uri.parse('wss://refreshed.example/sub')],
        headers: const {'Origin': 'https://refreshed.example'},
      );
      await connection.opens.last.reopen(refreshed);
      final other = DanmakuSocketTarget(endpoints: [Uri.parse('wss://other.example/ws')]);
      await connection.connect(other);
      expect(connector.headers, [_target.headers, renewed, refreshed.headers, other.headers]);
      await connection.close();
    });

    test('a failure of a socket already closed is not reported', () async {
      final gate = Completer<void>();
      final connector = _Connector(failures: [refused], gate: gate.future);
      final connection = _Platform(policy: policy, connector: connector)..renew = (_) => renewed;
      final connecting = connection.connect(_target);
      await _until(() => connector.endpoints.isNotEmpty);
      await connection.close().timeout(const Duration(seconds: 2));
      await connecting.timeout(const Duration(seconds: 2));
      gate.complete();
      await _wait(const Duration(milliseconds: 30));
      expect(connection.handshakeFailures, isEmpty);
      expect(connector.endpoints, hasLength(1));
    });

    test("a real server's 403: dart:io's status, then the renewed cookie is accepted", () async {
      final cookies = <String?>[];
      final sockets = <WebSocket>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await Future.wait([for (final socket in sockets) socket.close()]);
        await server.close(force: true);
      });
      server.listen((request) async {
        final cookie = request.headers.value('cookie');
        cookies.add(cookie);
        if (cookie != 'session=new') {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((frame) {
          if (frame == 'join') socket.add('弹幕');
        });
      });
      final connection = _RealPlatform(policy: policy)..renew = (_) async => {'Cookie': 'session=new'};
      final events = _record(connection);
      await connection.connect(
        DanmakuSocketTarget(
          endpoints: [Uri.parse('ws://127.0.0.1:${server.port}/')],
          headers: const {'Cookie': 'session=old'},
        ),
      );
      await _until(() => _texts(events).isNotEmpty);
      expect(cookies, ['session=old', 'session=new']);
      expect(connection.handshakeFailures.single.statusCode, 403);
      expect(connection.handshakeFailures.single.refused, isTrue);
      expect(events.first, const DanmakuReconnecting(DanmakuInterruption.disconnected));
      await connection.close();
    });
  });

  test('a real WebSocket server: join, messages and heartbeats', () async {
    final received = <Object?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((frame) {
        received.add(frame);
        if (frame == 'join') socket.add('弹幕');
      });
    });
    addTearDown(() => server.close(force: true));
    final connection = _RealPlatform(policy: const DanmakuSocketPolicy(heartbeatInterval: Duration(milliseconds: 20)));
    final events = _record(connection);
    await connection.connect(DanmakuSocketTarget(endpoints: [Uri.parse('ws://127.0.0.1:${server.port}/')]));
    await _until(() => _texts(events).isNotEmpty && received.where((frame) => frame == 'hb').length >= 2);
    expect(_texts(events), ['弹幕']);
    expect(received.first, 'join');
    await connection.close();
  });
}

/// [_Platform] on `dart:io`'s WebSocket.
final class _RealPlatform extends DanmakuSocketConnection<DanmakuSocketTarget> {
  new({required super.policy}) : super(site: SiteIds.douyu);

  @override
  Future<DanmakuSocketTarget> target(DanmakuSocketTarget args, DanmakuRun run) async => args;

  @override
  void onOpen(DanmakuSocketSession session) {
    session
      ..send('join')
      ..ready();
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) => session.message(
    LiveMessage(type: LiveMessageType.chat, userName: 'u', message: '$data', color: LiveMessageColor.white),
  );

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => 'hb';

  final List<DanmakuHandshakeFailure> handshakeFailures = [];
  _Renew? renew;

  @override
  FutureOr<Map<String, String>?> onHandshakeFailure(DanmakuSocketSession session, DanmakuHandshakeFailure failure) {
    handshakeFailures.add(failure);
    final answer = renew;
    return answer == null ? super.onHandshakeFailure(session, failure) : answer(failure);
  }
}
