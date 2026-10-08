import 'dart:async';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

final class _FakeChannel implements SocketChannel {
  new({this.closeCode, this.closeReason, this.closeGate});

  final StreamController<Object?> incoming = StreamController<Object?>();
  final Completer<void>? closeGate;
  final List<Object> sent = [];
  bool closed = false;
  int closeCalls = 0;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCalls++;
    closed = true;
    final gate = closeGate;
    if (gate != null) await gate.future;
  }

  @override
  final int? closeCode;

  @override
  final String? closeReason;
}

/// A connector that records endpoints and routes and hands out channels
/// made by [make], after [handshake] completes when given.
final class _Connector {
  new({_FakeChannel Function()? make, this.handshake}) : make = make ?? _FakeChannel.new;

  final _FakeChannel Function() make;
  final Future<void>? Function(int call)? handshake;
  final List<Uri> endpoints = [];
  final List<ProxyRoute> routes = [];
  final List<_FakeChannel> channels = [];

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    final index = endpoints.length;
    endpoints.add(endpoint);
    routes.add(route);
    final channel = make();
    channels.add(channel);
    await handshake?.call(index);
    return channel;
  }
}

final Uri _primary = Uri.parse('wss://primary.example/ws');
final Uri _backup = Uri.parse('wss://backup.example/ws');

void main() {
  test('a silent half-open socket is closed and reconnected on the next endpoint', () async {
    final connector = _Connector();
    final socket = LiveSocket(
      endpoints: [_primary, _backup, _primary],
      site: 'douyu',
      heartbeatInterval: const Duration(milliseconds: 10),
      inactivityTimeout: const Duration(milliseconds: 25),
      reconnectBaseDelay: const Duration(milliseconds: 5),
      connector: connector.call,
    );
    expect(socket.endpoints, [_primary, _backup], reason: 'duplicates are dropped');

    await socket.connect();
    expect(socket.status, SocketStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 55));

    expect(connector.endpoints.length, greaterThanOrEqualTo(2));
    expect(connector.endpoints.take(2), [_primary, _backup]);
    expect(connector.channels.first.closed, isTrue);

    await socket.close();
    final count = connector.endpoints.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connector.endpoints.length, count, reason: 'close cancels watchdog reconnects');
  });

  test('incoming traffic keeps one connection alive and heartbeats tick', () async {
    final connector = _Connector();
    var beats = 0;
    final socket = LiveSocket(
      endpoints: [_primary],
      site: 'douyu',
      heartbeatInterval: const Duration(milliseconds: 10),
      // Traffic every 100 ms for 1.2 s outlives the 1 s timeout only if each
      // message resets it; the wide margin keeps the test stable under load.
      inactivityTimeout: const Duration(seconds: 1),
      reconnectBaseDelay: const Duration(milliseconds: 5),
      onHeartbeat: () => beats++,
      connector: connector.call,
    );
    await socket.connect();
    for (var index = 0; index < 12; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      connector.channels.last.incoming.add('heartbeat-$index');
    }
    expect(connector.endpoints, hasLength(1));
    expect(socket.status, SocketStatus.connected);
    expect(beats, greaterThan(0));
    await socket.close();
  });

  test('the proxy policy is read at every handshake', () async {
    final connector = _Connector();
    var route = const DirectRoute() as ProxyRoute;
    final socket = LiveSocket(
      endpoints: [_primary],
      site: 'twitch',
      proxy: _MutablePolicy(() => route),
      reconnectBaseDelay: const Duration(milliseconds: 5),
      connector: connector.call,
    );
    await socket.connect();
    route = const HttpProxyRoute('127.0.0.1', 7897);
    socket.reconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(connector.routes, [const DirectRoute(), const HttpProxyRoute('127.0.0.1', 7897)]);
    await socket.close();
  });

  test('a proxy route gets its own handshake client; DIRECT keeps the dart:io default', () {
    expect(webSocketClientFor(const DirectRoute()), isNull);
    final client = webSocketClientFor(const HttpProxyRoute('127.0.0.1', 7897));
    expect(client, isNotNull);
    client!.close();
  });

  group('the handshake User-Agent (UPGRADES B-2, Q03.1)', () {
    /// A loopback WebSocket server that records each upgrade's User-Agent.
    Future<(HttpServer, List<String?>)> recordingServer() async {
      final agents = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        agents.add(request.headers.value(HttpHeaders.userAgentHeader));
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close();
      });
      addTearDown(() => server.close(force: true));
      return (server, agents);
    }

    Future<void> connect(HttpServer server, {Map<String, String> headers = const {}, bool plain = false}) async {
      final channel = await connectIoSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/'),
        headers: headers,
        protocols: null,
        route: const DirectRoute(),
        connectTimeout: const Duration(seconds: 5),
        plainUserAgent: plain,
      );
      await channel.close();
    }

    test("the default handshake sends dart:io's User-Agent prefix", () async {
      final (server, agents) = await recordingServer();
      await connect(server, headers: {'user-agent': 'Mozilla/5.0 test'});
      expect(agents.single, startsWith('Dart/'));
    });

    test("plainUserAgent sends only the caller's User-Agent, or none", () async {
      final (server, agents) = await recordingServer();
      await connect(server, headers: {'user-agent': 'Mozilla/5.0 test'}, plain: true);
      await connect(server, plain: true);
      expect(agents, ['Mozilla/5.0 test', null]);
    });
  });

  test('remote close diagnostics include the close code and reason', () async {
    final failures = <String>[];
    final connector = _Connector(make: () => _FakeChannel(closeCode: 1008, closeReason: 'policy'));
    final socket = LiveSocket(endpoints: [_primary], site: 'douyu', onFailure: failures.add, connector: connector.call);
    await socket.connect();
    await connector.channels.single.incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(failures, ['WebSocket closed (code=1008): policy']);
    await socket.close();
  });

  test('after the last reconnect fails it gives up and reports why', () async {
    final closed = <String>[];
    var reconnecting = 0;
    final socket = LiveSocket(
      endpoints: [_primary, _backup],
      site: 'douyu',
      maxReconnects: 3,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      onReconnecting: () => reconnecting++,
      onClosed: closed.add,
      connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) =>
          Future.error(const SocketException('refused')),
    );
    await socket.connect();
    await _eventually(() => closed.isNotEmpty);
    expect(closed, hasLength(1));
    expect(closed.single, contains('refused'));
    expect(reconnecting, 1, reason: 'one notice per streak');
    expect(socket.status, SocketStatus.closed);
  });

  test('close aborts a stalled handshake and a new connection can be made', () async {
    final stalled = Completer<void>();
    final connector = _Connector(handshake: (call) => call == 0 ? stalled.future : null);
    final socket = LiveSocket(endpoints: [_primary], site: 'douyu', connector: connector.call);
    addTearDown(() async {
      if (!stalled.isCompleted) stalled.complete();
      await socket.close();
    });

    final first = socket.connect();
    await Future<void>.delayed(Duration.zero);
    await socket.close().timeout(const Duration(milliseconds: 100));
    await first.timeout(const Duration(milliseconds: 100));

    await socket.connect().timeout(const Duration(milliseconds: 100));
    expect(connector.endpoints, [_primary, _primary]);
    expect(socket.status, SocketStatus.connected);

    // The abandoned handshake completes later: its socket is closed once.
    stalled.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(connector.channels.first.closeCalls, 1);
    expect(connector.channels.last.closed, isFalse);
  });

  test('duplicate connect callers join the pending handshake until it is closed', () async {
    final stalled = Completer<void>();
    final connector = _Connector(handshake: (_) => stalled.future);
    final socket = LiveSocket(endpoints: [_primary], site: 'douyu', connector: connector.call);
    addTearDown(() {
      if (!stalled.isCompleted) stalled.complete();
    });

    final first = socket.connect();
    final duplicate = socket.connect();
    var duplicateDone = false;
    unawaited(duplicate.whenComplete(() => duplicateDone = true));
    await Future<void>.delayed(Duration.zero);
    expect(connector.endpoints, hasLength(1));
    expect(duplicateDone, isFalse);

    await socket.close();
    await Future.wait([first, duplicate]);
    expect(duplicateDone, isTrue);
  });

  test('a real handshake can be abandoned before the peer upgrades the connection', () async {
    final accepted = Completer<Socket>();
    Socket? peer;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((client) {
      peer = client;
      if (!accepted.isCompleted) accepted.complete(client);
    });
    final socket = LiveSocket(
      endpoints: [Uri.parse('ws://${InternetAddress.loopbackIPv4.address}:${server.port}/stall')],
      site: 'douyu',
    );
    addTearDown(() async {
      await socket.close();
      peer?.destroy();
      await subscription.cancel();
      await server.close();
    });

    final connection = socket.connect();
    await accepted.future.timeout(const Duration(seconds: 2));
    await socket.close().timeout(const Duration(seconds: 2));
    await connection.timeout(const Duration(seconds: 2));
    expect(socket.status, SocketStatus.closed);
  });

  test('a real echo server: messages flow both ways', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      ws.listen(ws.add);
    });
    addTearDown(() => server.close(force: true));
    final received = Completer<Object?>();
    final socket = LiveSocket(
      endpoints: [Uri.parse('ws://127.0.0.1:${server.port}/')],
      site: 'douyu',
      onMessage: received.complete,
    );
    addTearDown(socket.close);
    await socket.connect();
    socket.send('弹幕');
    expect(await received.future.timeout(const Duration(seconds: 2)), '弹幕');
  });

  test('an established socket with a stalled closing handshake has bounded teardown', () async {
    final gate = Completer<void>();
    final connector = _Connector(make: () => _FakeChannel(closeGate: gate));
    final socket = LiveSocket(
      endpoints: [_primary],
      site: 'douyu',
      shutdownTimeout: const Duration(milliseconds: 20),
      connector: connector.call,
    );
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await socket.connect();
    await socket.close().timeout(const Duration(milliseconds: 100));
    expect(connector.channels.single.closed, isTrue);
    expect(socket.status, SocketStatus.closed);
  });

  group('connectIoSocket pings', () {
    /// A dart:io WebSocket server behind a TCP relay that records the bytes
    /// the client sends after its upgrade request.
    Future<({int port, List<int> Function() afterHandshake})> relayedServer() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen((_) {});
      });
      final relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final fromClient = <int>[];
      final sockets = <Socket>[];
      relay.listen((client) async {
        final upstream = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
        sockets.addAll([client, upstream]);
        upstream.listen(client.add, onDone: client.destroy, onError: (Object _) {});
        client.listen(
          (bytes) {
            fromClient.addAll(bytes);
            upstream.add(bytes);
          },
          onDone: upstream.destroy,
          onError: (Object _) {},
        );
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await relay.close();
        await server.close(force: true);
      });
      List<int> afterHandshake() {
        final end = String.fromCharCodes(fromClient).indexOf('\r\n\r\n');
        return end < 0 ? const [] : fromClient.sublist(end + 4);
      }

      return (port: relay.port, afterHandshake: afterHandshake);
    }

    Future<SocketChannel> connect(int port, {Duration? pingInterval}) => connectIoSocket(
      Uri.parse('ws://127.0.0.1:$port/'),
      headers: const {},
      protocols: null,
      route: const DirectRoute(),
      connectTimeout: const Duration(seconds: 2),
      pingInterval: pingInterval,
    );

    test('with an interval the client sends ping frames', () async {
      final relay = await relayedServer();
      final channel = await connect(relay.port, pingInterval: const Duration(milliseconds: 40));
      addTearDown(channel.close);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (relay.afterHandshake().isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // FIN + opcode 9 (ping), masked as every client frame.
      expect(relay.afterHandshake().take(2), [0x89, 0x80]);
    });

    test('without one the client stays silent', () async {
      final relay = await relayedServer();
      final channel = await connect(relay.port);
      addTearDown(channel.close);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(relay.afterHandshake(), isEmpty);
    });
  });
}

final class _MutablePolicy implements ProxyPolicy {
  new(this.route);

  final ProxyRoute Function() route;

  @override
  ProxyRoute routeFor(String site, Uri url) => route();
}

/// Waits until [condition] holds, polling every few milliseconds, instead of
/// sleeping a fixed time that a loaded machine can overrun. Fails after
/// [timeout].
Future<void> _eventually(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
