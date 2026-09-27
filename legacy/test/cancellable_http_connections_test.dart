import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/cancellable_http_connections.dart';

SecurityContext _serverContext({bool wrongHost = false}) => SecurityContext()
  ..useCertificateChain('test/fixtures/tls/${wrongHost ? 'wrong-host' : 'localhost'}-cert.pem')
  ..usePrivateKey('test/fixtures/tls/localhost-key.pem');

SecurityContext _trustedContext({bool wrongHost = false}) =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/tls/${wrongHost ? 'wrong-host' : 'localhost'}-cert.pem');

Future<void> _until(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 3)) fail('Connection cleanup did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  for (final proxy in [false, true]) {
    test('stalled TLS ${proxy ? 'through CONNECT' : 'direct'} retires peer and request together', () async {
      final origin = await _Blackhole.start();
      final tunnel = proxy ? await _Proxy.start(origin.port) : null;
      final owner = CancellableHttpConnections();
      final client = HttpClient()
        ..connectionFactory = owner.connect
        ..findProxy = (_) => tunnel == null ? 'DIRECT' : 'PROXY 127.0.0.1:${tunnel.port}';
      final pending = client.getUrl(Uri.parse('https://localhost:${origin.port}/media'));
      final failure = expectLater(pending, throwsA(proxy ? isA<HandshakeException>() : isA<SocketException>()));
      try {
        await origin.hello.future.timeout(const Duration(seconds: 3));
        owner.cancel();
        client.close(force: true);
        await failure.timeout(const Duration(seconds: 3));
        await origin.gone.future.timeout(const Duration(seconds: 3));
        await owner.settled.timeout(const Duration(seconds: 3));
        expect(owner.activeConnectionCount, 0);
        if (tunnel != null) expect(tunnel.authorities, ['localhost:${origin.port}']);
        await expectLater(owner.connect(Uri.parse('http://localhost/'), null, null), throwsA(isA<SocketException>()));
      } finally {
        owner.cancel();
        client.close(force: true);
        await tunnel?.close();
        await origin.close();
      }
    });
  }

  for (final proxy in [false, true]) {
    test('trusted TLS ${proxy ? 'through CONNECT' : 'direct'} preserves large bytes and headers', () async {
      final payload = Uint8List.fromList(List.generate(3 * 1024 * 1024 + 17, (i) => i % 251));
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, _serverContext());
      var requests = 0;
      final sub = server.listen((request) async {
        requests++;
        expect(request.headers.value('x-recording-fixture'), 'preserved');
        request.response.headers.set('x-fixture-result', 'complete');
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      final tunnel = proxy ? await _Proxy.start(server.port) : null;
      final context = _trustedContext();
      final owner = CancellableHttpConnections(securityContext: context);
      final client = HttpClient(context: context)
        ..connectionFactory = owner.connect
        ..maxConnectionsPerHost = 1
        ..findProxy = (_) => tunnel == null ? 'DIRECT' : 'PROXY 127.0.0.1:${tunnel.port}';
      try {
        for (var i = 0; i < 2; i++) {
          final request = await client.getUrl(Uri.parse('https://localhost:${server.port}/media'));
          request.headers.set('x-recording-fixture', 'preserved');
          final response = await request.close();
          expect(response.statusCode, 200);
          expect(response.headers.value('x-fixture-result'), 'complete');
          final bytes = await response.fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) => b..add(chunk));
          expect(bytes.takeBytes(), payload);
          expect(
            owner.activeConnectionCount,
            proxy ? i + 1 : 1,
            reason: 'direct pooling is bounded; CONNECT ownership matches the pinned SDK baseline below',
          );
        }
        expect(requests, 2);
        if (tunnel != null) expect(tunnel.authorities, List.filled(2, 'localhost:${server.port}'));
      } finally {
        client.close(force: true);
        owner.cancel();
        await owner.settled.timeout(const Duration(seconds: 3));
        expect(owner.activeConnectionCount, 0);
        await tunnel?.close();
        await server.close(force: true);
        await sub.cancel();
      }
    });
  }

  for (final proxy in [false, true]) {
    for (final trust in [false, true]) {
      test(
        'rejects ${trust ? 'hostname mismatch' : 'untrusted certificate'} ${proxy ? 'through CONNECT' : 'direct'}',
        () async {
          final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, _serverContext(wrongHost: trust));
          var requests = 0;
          final sub = server.listen((request) {
            requests++;
            request.response.close();
          }, onError: (Object _) {});
          final tunnel = proxy ? await _Proxy.start(server.port) : null;
          final context = trust ? _trustedContext(wrongHost: true) : null;
          final owner = CancellableHttpConnections(securityContext: context);
          final client = HttpClient(context: context)
            ..connectionFactory = owner.connect
            ..findProxy = (_) => tunnel == null ? 'DIRECT' : 'PROXY 127.0.0.1:${tunnel.port}';
          var badCertificateObserved = false;
          if (proxy) {
            client.badCertificateCallback = (_, host, port) {
              badCertificateObserved = true;
              return false;
            };
          }
          try {
            // A trusted chain for wrong-host.invalid still must reject localhost.
            // Keep CONNECT authority identical in positive and negative fixtures.
            const host = 'localhost';
            await expectLater(
              client.getUrl(Uri.parse('https://$host:${server.port}/media')),
              throwsA(isA<HandshakeException>()),
            );
            expect(requests, 0, reason: 'no HTTP content before successful certificate verification');
            if (proxy) expect(badCertificateObserved, true);
          } finally {
            client.close(force: true);
            owner.cancel();
            await owner.settled.timeout(const Duration(seconds: 3));
            expect(owner.activeConnectionCount, 0);
            await tunnel?.close();
            await server.close(force: true);
            await sub.cancel();
          }
        },
      );
    }
  }

  test('default HttpClient CONNECT pooling baseline also opens two tunnels for sequential responses', () async {
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, _serverContext());
    final sub = server.listen((request) {
      request.response.write('baseline');
      request.response.close();
    });
    final proxy = await _Proxy.start(server.port);
    final client = HttpClient(context: _trustedContext())
      ..maxConnectionsPerHost = 1
      ..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.port}';
    try {
      for (var i = 0; i < 2; i++) {
        final response = await (await client.getUrl(Uri.parse('https://localhost:${server.port}/media'))).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      }
      expect(proxy.authorities, List.filled(2, 'localhost:${server.port}'));
    } finally {
      client.close(force: true);
      await proxy.close();
      await server.close(force: true);
      await sub.cancel();
    }
  });

  test('HttpClient connect timeout cancels the owned TLS network without session close', () async {
    final origin = await _Blackhole.start();
    final owner = CancellableHttpConnections();
    final client = HttpClient()
      ..connectionFactory = owner.connect
      ..connectionTimeout = const Duration(seconds: 1);
    try {
      final failure = expectLater(
        client.getUrl(Uri.parse('https://localhost:${origin.port}/media')),
        throwsA(isA<SocketException>()),
      );
      await origin.hello.future.timeout(const Duration(seconds: 3));
      await failure.timeout(const Duration(seconds: 3));
      await origin.gone.future.timeout(const Duration(seconds: 3));
      await _until(() => owner.activeConnectionCount == 0);
    } finally {
      client.close(force: true);
      owner.cancel();
      await owner.settled;
      await origin.close();
    }
  });

  test('immediate cancellation retires late TCP/local allocations', () async {
    final origin = await _Blackhole.start();
    try {
      for (var i = 0; i < 10; i++) {
        final owner = CancellableHttpConnections();
        final task = await owner.connect(Uri.parse('https://localhost:${origin.port}/media'), null, null);
        final failure = expectLater(task.socket, throwsA(isA<SocketException>()));
        owner.cancel();
        await failure;
        await owner.settled.timeout(const Duration(seconds: 3));
        expect(owner.activeConnectionCount, 0);
      }
    } finally {
      await origin.close();
    }
  });

  test('plain HTTP keeps normal response streaming and session isolation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((r) {
      r.response.write('healthy');
      r.response.close();
    });
    final first = CancellableHttpConnections(), second = CancellableHttpConnections();
    final a = HttpClient()..connectionFactory = first.connect;
    final b = HttpClient()..connectionFactory = second.connect;
    final uri = Uri.parse('http://127.0.0.1:${server.port}/media');
    Future<String> get(HttpClient c) async =>
        String.fromCharCodes(await (await (await c.getUrl(uri)).close()).fold<List<int>>([], (a, b) => a..addAll(b)));
    try {
      expect(await get(a), 'healthy');
      expect(await get(b), 'healthy');
      first.cancel();
      a.close(force: true);
      await first.settled;
      expect(await get(b), 'healthy');
      expect(second.activeConnectionCount, 1);
    } finally {
      first.cancel();
      second.cancel();
      a.close(force: true);
      b.close(force: true);
      await first.settled;
      await second.settled;
      await server.close(force: true);
      await sub.cancel();
    }
  });
}

class _Blackhole {
  _Blackhole(this.server);
  final ServerSocket server;
  final hello = Completer<void>(), gone = Completer<void>();
  final sockets = <Socket>[];
  late StreamSubscription<Socket> sub;
  int get port => server.port;
  static Future<_Blackhole> start() async {
    final result = _Blackhole(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    result.sub = result.server.listen((s) {
      result.sockets.add(s);
      s.listen(
        (b) {
          if (b.isNotEmpty && !result.hello.isCompleted) result.hello.complete();
        },
        onError: (Object _) {},
        onDone: () {
          if (!result.gone.isCompleted) result.gone.complete();
        },
      );
    });
    return result;
  }

  Future<void> close() async {
    for (final s in sockets) {
      s.destroy();
    }
    await server.close();
    await sub.cancel();
  }
}

class _Proxy {
  _Proxy(this.server);
  final HttpServer server;
  final sockets = <Socket>[];
  final authorities = <String>[];
  final errors = <Object>[];
  late StreamSubscription<HttpRequest> sub;
  int get port => server.port;
  static Future<_Proxy> start(int targetPort) async {
    final proxy = _Proxy(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    proxy.sub = proxy.server.listen((request) async {
      try {
        expect(request.method, 'CONNECT');
        proxy.authorities.add(request.uri.toString());
        request.response.statusCode = 200;
        final downstream = await request.response.detachSocket(writeHeaders: true);
        proxy.sockets.add(downstream);
        final upstream = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
        proxy.sockets.add(upstream);
        void forward(Socket from, Socket to) {
          unawaited(() async {
            try {
              await to.addStream(from);
              await to.flush();
              await to.close();
            } on Object {
              from.destroy();
              to.destroy();
            }
          }());
        }

        forward(downstream, upstream);
        forward(upstream, downstream);
      } on Object catch (error) {
        proxy.errors.add(error);
        request.response.close();
      }
    });
    return proxy;
  }

  Future<void> close() async {
    for (final s in sockets) {
      s.destroy();
    }
    await server.close(force: true);
    await sub.cancel();
    expect(errors, isEmpty, reason: 'proxy fixture failed before reaching TLS');
  }
}
