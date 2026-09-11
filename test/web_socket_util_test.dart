import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('a silent half-open socket is closed and reconnected on the next endpoint', () async {
    final endpoints = <String>[];
    final channels = <_FakeWebSocketChannel>[];
    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      serverUrls: const ['wss://primary.example/ws', 'wss://backup.example/ws'],
      heartBeatTime: 10,
      inactivityTimeout: const Duration(milliseconds: 25),
      reconnectBaseDelay: const Duration(milliseconds: 5),
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        endpoints.add(endpoint);
        final channel = _FakeWebSocketChannel();
        channels.add(channel);
        return channel;
      },
    );

    await socket.connect();
    expect(socket.status, SocketStatus.connected);

    await Future<void>.delayed(const Duration(milliseconds: 55));

    expect(endpoints.length, greaterThanOrEqualTo(2));
    expect(endpoints.take(2), ['wss://primary.example/ws', 'wss://backup.example/ws']);
    expect(channels.first.outgoing.closed, isTrue);

    await socket.close();
    final connectionCount = endpoints.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(endpoints.length, connectionCount, reason: 'manual close must cancel watchdog reconnects');
  });

  test('incoming heartbeat traffic keeps one connection alive', () async {
    late _FakeWebSocketChannel channel;
    var connectionCount = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 10,
      inactivityTimeout: const Duration(milliseconds: 40),
      reconnectBaseDelay: const Duration(milliseconds: 5),
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        connectionCount++;
        channel = _FakeWebSocketChannel();
        return channel;
      },
    );

    await socket.connect();
    for (var index = 0; index < 4; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      channel.incoming.add('heartbeat-$index');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(connectionCount, 1);
    expect(socket.status, SocketStatus.connected);
    await socket.close();
  });

  test('configured proxy routing is applied to the WebSocket handshake client', () async {
    HttpClient? capturedClient;
    configureWebSocketProxyRouting((uri) => 'PROXY localhost:7897');
    addTearDown(() => configureWebSocketProxyRouting(null));

    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 0,
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        capturedClient = customClient;
        return _FakeWebSocketChannel();
      },
    );

    await socket.connect();
    expect(capturedClient, isNotNull);
    expect(resolveWebSocketProxyDirective(Uri.parse('wss://primary.example/ws')), 'PROXY localhost:7897');
    await socket.close();
  });

  test('DIRECT routing keeps the dart:io default WebSocket client', () async {
    HttpClient? capturedClient;
    configureWebSocketProxyRouting((uri) => 'DIRECT');
    addTearDown(() => configureWebSocketProxyRouting(null));

    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 0,
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        capturedClient = customClient;
        return _FakeWebSocketChannel();
      },
    );

    await socket.connect();
    expect(capturedClient, isNull);
    await socket.close();
  });

  test('remote close diagnostics include the close code and reason', () async {
    final failures = <String>[];
    late _FakeWebSocketChannel channel;
    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 0,
      reconnectBaseDelay: const Duration(seconds: 1),
      onFailure: failures.add,
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        channel = _FakeWebSocketChannel(closeCode: 1008, closeReason: 'policy');
        return channel;
      },
    );

    await socket.connect();
    await channel.incoming.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(failures, ['WebSocket closed (code=1008): policy']);
    await socket.close();
  });

  test('manual close aborts a stalled handshake and permits a clean connection attempt', () async {
    final stalledReady = Completer<void>();
    final endpoints = <String>[];
    final channels = <_FakeWebSocketChannel>[];
    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 0,
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        endpoints.add(endpoint);
        final channel = _FakeWebSocketChannel(ready: channels.isEmpty ? stalledReady.future : null);
        channels.add(channel);
        return channel;
      },
    );
    addTearDown(() async {
      if (!stalledReady.isCompleted) stalledReady.complete();
      await socket.close();
    });

    final stalledConnection = socket.connect();
    await Future<void>.delayed(Duration.zero);
    await socket.close().timeout(const Duration(milliseconds: 100));
    await stalledConnection.timeout(const Duration(milliseconds: 100));

    await socket.connect().timeout(const Duration(milliseconds: 100));
    expect(endpoints, ['wss://primary.example/ws', 'wss://primary.example/ws']);
    expect(channels.first.outgoing.closed, isTrue);
    expect(channels.first.outgoing.closeCalls, 1);
    expect(socket.status, SocketStatus.connected);
  });

  test('duplicate connect callers join the active handshake until it is closed', () async {
    final stalledReady = Completer<void>();
    var connectorCalls = 0;
    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 0,
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        connectorCalls++;
        return _FakeWebSocketChannel(ready: stalledReady.future);
      },
    );
    addTearDown(() {
      if (!stalledReady.isCompleted) stalledReady.complete();
    });

    final first = socket.connect();
    final duplicate = socket.connect();
    var duplicateCompleted = false;
    unawaited(duplicate.whenComplete(() => duplicateCompleted = true));
    await Future<void>.delayed(Duration.zero);

    expect(connectorCalls, 1);
    expect(duplicateCompleted, isFalse);

    await socket.close();
    await Future.wait([first, duplicate]);
    expect(duplicateCompleted, isTrue);
  });

  test('real IO handshake can be abandoned before the peer upgrades the connection', () async {
    final accepted = Completer<Socket>();
    Socket? peer;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverSubscription = server.listen((client) {
      peer = client;
      if (!accepted.isCompleted) accepted.complete(client);
    });
    final socket = WebScoketUtils(
      url: 'ws://${InternetAddress.loopbackIPv4.address}:${server.port}/stall',
      heartBeatTime: 0,
    );
    addTearDown(() async {
      await socket.close();
      peer?.destroy();
      await serverSubscription.cancel();
      await server.close();
    });

    final connection = socket.connect();
    await accepted.future.timeout(const Duration(seconds: 2));
    await socket.close().timeout(const Duration(seconds: 2));
    await connection.timeout(const Duration(seconds: 2));

    expect(socket.status, SocketStatus.closed);
  });

  test('an established socket with a stalled close acknowledgement has bounded teardown', () async {
    final closeGate = Completer<void>();
    late _FakeWebSocketChannel channel;
    final socket = WebScoketUtils(
      url: 'wss://primary.example/ws',
      heartBeatTime: 0,
      shutdownTimeout: const Duration(milliseconds: 20),
      connector: (endpoint, {connectTimeout, protocols, headers, customClient}) {
        channel = _FakeWebSocketChannel(closeGate: closeGate);
        return channel;
      },
    );
    addTearDown(() {
      if (!closeGate.isCompleted) closeGate.complete();
    });

    await socket.connect();
    await socket.close().timeout(const Duration(milliseconds: 100));

    expect(channel.outgoing.closed, isTrue);
    expect(socket.status, SocketStatus.closed);
  });
}

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel({this.closeCode, this.closeReason, Future<void>? ready, Completer<void>? closeGate})
    : _ready = ready ?? Future<void>.value(),
      outgoing = _FakeWebSocketSink(closeGate: closeGate);

  final StreamController<dynamic> incoming = StreamController<dynamic>();
  final _FakeWebSocketSink outgoing;
  final Future<void> _ready;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => outgoing;

  @override
  Future<void> get ready => _ready;

  @override
  String? get protocol => null;

  @override
  final int? closeCode;

  @override
  final String? closeReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink({this.closeGate});

  final Completer<void>? closeGate;
  final List<dynamic> sent = <dynamic>[];
  final Completer<void> _done = Completer<void>();
  bool closed = false;
  int closeCalls = 0;

  @override
  void add(dynamic data) {
    if (closed) throw StateError('socket is closed');
    sent.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closeCalls++;
    closed = true;
    if (closeGate != null) {
      await closeGate!.future;
      return;
    }
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
