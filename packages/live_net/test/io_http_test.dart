import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late IoLiveHttp http;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    http = IoLiveHttp();
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/text':
          response
            ..headers.add('set-cookie', 'a=1; Path=/')
            ..headers.add('set-cookie', 'b=2; Path=/')
            ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
            ..write('斗鱼 ${request.headers.value('x-probe')}');
        case '/form':
          response.write(await utf8.decoder.bind(request).join());
        case '/redirect':
          response
            ..statusCode = HttpStatus.found
            ..headers.set('location', '/text');
        case '/missing':
          response
            ..statusCode = HttpStatus.notFound
            ..write('gone');
        case '/gzip':
          response
            ..headers.set('content-encoding', 'gzip')
            ..add(gzip.encode(utf8.encode('compressed body')));
        case '/slow':
          await Future<void>.delayed(const Duration(seconds: 2));
          response.write('late');
        case '/chunks':
          response.contentLength = 6;
          for (final part in ['ab', 'cd', 'ef']) {
            response.add(utf8.encode(part));
            await response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
      }
      await response.close();
    });
  });

  tearDown(() async {
    http.close();
    await server.close(force: true);
  });

  LiveRequest get(
    String path, {
    bool follow = true,
    Duration timeout = const Duration(seconds: 5),
    CancelToken? cancel,
  }) => LiveRequest(site: 'douyu', url: base.resolve(path), followRedirects: follow, timeout: timeout, cancel: cancel);

  test('returns text, headers with every value, and sends request headers', () async {
    final response = await http.send(
      LiveRequest(site: 'douyu', url: base.resolve('/text'), headers: const {'X-Probe': 'ok'}),
    );
    expect(response.status, 200);
    expect(response.text, '斗鱼 ok');
    expect(response.headers['set-cookie'], ['a=1; Path=/', 'b=2; Path=/']);
    expect(response.header('Content-Type'), startsWith('text/plain'));
  });

  test('form bodies are percent-encoded', () async {
    final response = await http.send(
      LiveRequest.form(site: 'douyu', url: base.resolve('/form'), fields: const {'enc_data': 'a+b/c=', 'rate': '-1'}),
    );
    expect(response.text, 'enc_data=a%2Bb%2Fc%3D&rate=-1');
  });

  test('redirects are followed or returned as asked', () async {
    final followed = await http.send(get('/redirect'));
    expect(followed.status, 200);
    expect(followed.url.path, '/text');
    final kept = await http.send(get('/redirect', follow: false));
    expect(kept.status, 302);
    expect(kept.header('location'), '/text');
  });

  test('HTTP errors are responses, not exceptions', () async {
    final response = await http.send(get('/missing'));
    expect(response.status, 404);
    expect(response.isSuccess, isFalse);
    expect(response.text, 'gone');
  });

  test('gzip bodies are decoded', () async {
    expect((await http.send(get('/gzip'))).text, 'compressed body');
  });

  test('timeout, cancellation and refused connections are transport failures', () async {
    await expectLater(
      http.send(get('/slow', timeout: const Duration(milliseconds: 200))),
      throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.timeout)),
    );
    final token = CancelToken();
    final pending = http.send(get('/slow', cancel: token));
    token.cancel();
    await expectLater(
      pending,
      throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled)),
    );
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await expectLater(
      http.send(LiveRequest(site: 'huya', url: Uri.parse('http://127.0.0.1:$port/'))),
      throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.connect)),
    );
  });

  test('a per-platform proxy route carries the request', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    proxy.listen((request) async {
      request.response.write('via proxy for ${request.uri.host}');
      await request.response.close();
    });
    final routed = IoLiveHttp(proxy: FixedProxyPolicy(perSite: {'twitch': HttpProxyRoute('127.0.0.1', proxy.port)}));
    addTearDown(routed.close);
    final response = await routed.send(LiveRequest(site: 'twitch', url: Uri.parse('http://example.test/x')));
    expect(response.text, 'via proxy for example.test');
    // Other platforms stay direct.
    expect((await routed.send(get('/text'))).status, 200);
  });

  /// A server that sends headers and `first`, then stalls for two seconds:
  /// written by hand because `HttpServer` holds back small flushed writes.
  Future<Uri> stallingServer() async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    addTearDown(() async {
      for (final peer in peers) {
        peer.destroy();
      }
      await raw.close();
    });
    raw.listen((peer) {
      peers.add(peer);
      peer.listen((_) async {
        peer.add(utf8.encode('HTTP/1.1 200 OK\r\ncontent-length: 100\r\n\r\nfirst'));
        await peer.flush();
      });
    });
    return Uri.parse('http://127.0.0.1:${raw.port}/stall');
  }

  group('open', () {
    test('streams the body chunk by chunk with the declared length', () async {
      final response = await http.open(get('/chunks'));
      expect(response.status, 200);
      expect(response.contentLength, 6);
      final chunks = await response.body.map(utf8.decode).toList();
      expect(chunks.join(), 'abcdef');
    });

    test('a gap between chunks longer than the timeout fails the body stream', () async {
      final url = await stallingServer();
      final response = await http.open(
        LiveRequest(site: 'douyu', url: url, timeout: const Duration(milliseconds: 300)),
      );
      final received = <String>[];
      await expectLater(
        response.body.map(utf8.decode).forEach(received.add),
        throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.timeout)),
      );
      expect(received, ['first']);
    });

    test('cancelling during the body ends the stream with a cancelled failure', () async {
      final url = await stallingServer();
      final token = CancelToken();
      final response = await http.open(LiveRequest(site: 'douyu', url: url, cancel: token));
      final done = response.body.drain<void>();
      token.cancel();
      await expectLater(
        done,
        throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled)),
      );
    });

    test('waiting for headers is limited by the timeout', () async {
      await expectLater(
        http.open(get('/slow', timeout: const Duration(milliseconds: 200))),
        throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.timeout)),
      );
    });

    test('collect reads the rest; discard closes without reading', () async {
      expect((await (await http.open(get('/text'))).collect()).text, startsWith('斗鱼'));
      final stalled = await http.open(LiveRequest(site: 'douyu', url: await stallingServer()));
      await stalled.discard().timeout(const Duration(seconds: 1));
    });
  });
}
