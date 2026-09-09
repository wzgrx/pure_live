import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/recorder/services/hls_body_reader.dart';
import 'package:pure_live/recorder/services/hls_http_body_metadata.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';
import 'package:pure_live/recorder/services/hls_session_cookies.dart';
import 'package:pure_live/recorder/services/hls_upstream_client.dart';

const idle = Duration(seconds: 2);
HlsPrefetchPool pool() =>
    HlsPrefetchPool(createDirectory: () => throw StateError('Unexpected disk'), bodyIdleTimeout: idle);
Future<List<int>> bytes(HlsPrefetchLease lease) async {
  final controller = StreamController<List<int>>();
  final result = controller.stream.fold<List<int>>([], (all, part) => all..addAll(part));
  try {
    await lease.writeTo(controller.sink);
  } finally {
    await controller.close();
    await lease.release();
  }
  return result;
}

void main() {
  test('actual HTTP gzip is decoded once and seals against decoded rather than wire length', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()..autoUncompress = true;
    final uri = Uri.parse('http://127.0.0.1:${server.port}/media.m4s');
    final wire = gzip.encode([1, 2, 3]);
    final subscription = server.listen((request) async {
      request.response.headers.set('Content-Encoding', 'gzip');
      request.response.contentLength = wire.length;
      request.response.add(wire);
      await request.response.close();
    });
    final upstream = HlsUpstreamClient(client: client, source: uri, headers: {}, cookies: HlsSessionCookies());
    final cache = pool();
    try {
      final ticket = cache.prefetch(
        'gzip',
        (cancel) => upstream.loadMedia(uri, cancel, budget: HlsResponseBudget(idle)),
      )!;
      expect(await ticket.ready, true);
      final lease = cache.acquire(ticket.key)!;
      expect(lease.metadata!.expectedLength, -1);
      expect(lease.length, 3);
      expect(wire.length, isNot(3));
      expect(await bytes(lease), [1, 2, 3]);
    } finally {
      upstream.stop();
      client.close(force: true);
      await cache.close();
      upstream.clear();
      await server.close(force: true);
      await subscription.cancel();
    }
  });
  for (final foreign in [false, true]) {
    test('prefetch shares redirect cookie/query/header policy; foreign=$foreign', () async {
      final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient()..connectionTimeout = idle;
      final base = Uri.parse('http://127.0.0.1:${first.port}/live/root.m3u8?token=a%2Fb');
      final seen = <Map<String, String?>>[];
      void observe(HttpRequest request) => seen.add({
        'query': request.uri.query,
        'authorization': request.headers.value('authorization'),
        'cookie': request.headers.value('cookie'),
        'agent': request.headers.value('user-agent'),
        'range': request.headers.value('range'),
      });
      Future<void> media(HttpRequest request) async {
        observe(request);
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', 'bytes 10-12/100');
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.contentLength = 3;
        request.response.add([1, 2, 3]);
        await request.response.close();
      }

      final sub1 = first.listen((request) async {
        if (request.uri.path.endsWith('/redirect.m4s')) {
          observe(request);
          request.response.statusCode = 302;
          request.response.headers.set('Set-Cookie', 'session=fixture; Path=/live');
          request.response.headers.set(
            'Location',
            foreign ? 'http://127.0.0.1:${second.port}/live/media.m4s?x=1' : '/live/media.m4s?x=1',
          );
          await request.response.close();
        } else {
          await media(request);
        }
      });
      final sub2 = second.listen(media);
      final cookies = HlsSessionCookies();
      final upstream = HlsUpstreamClient(
        client: client,
        source: base,
        cookies: cookies,
        headers: {'Authorization': 'Bearer fixture', 'Cookie': 'caller=fixture', 'User-Agent': 'fixture-agent'},
        queryPolicy: HlsSourceQueryPolicy.fromSource(base),
      );
      final cache = pool();
      try {
        final ticket = cache.prefetch(
          'selected-range',
          (cancel) => upstream.loadMedia(
            base.resolve('redirect.m4s'),
            cancel,
            range: const HlsSegmentRange(10, 3),
            budget: HlsResponseBudget(idle),
          ),
        )!;
        expect(await ticket.ready, true);
        final lease = cache.acquire(ticket.key)!;
        expect(lease.metadata!.statusCode, 206);
        expect(lease.metadata!.contentRange, 'bytes 10-12/100');
        expect(lease.metadata!.contentType, startsWith('video/mp4'));
        expect(await bytes(lease), [1, 2, 3]);
        expect(seen.length, 2);
        expect(seen.first['query'], 'token=a%2Fb');
        expect(seen.last['query'], foreign ? 'x=1' : 'x=1&token=a%2Fb');
        expect(seen.last['authorization'], foreign ? isNull : 'Bearer fixture');
        expect(seen.last['cookie'], foreign ? isNull : allOf(contains('caller=fixture'), contains('session=fixture')));
        expect(seen.last['agent'], 'fixture-agent');
        expect(seen.map((e) => e['range']), everyElement('bytes=10-12'));
      } finally {
        upstream.stop();
        client.close(force: true);
        await cache.close();
        upstream.clear();
        cookies.clear();
        await first.close(force: true);
        await second.close(force: true);
        await sub1.cancel();
        await sub2.cancel();
      }
    });
  }
  for (final phase in ['headers', 'redirect-body', 'media-body', 'bad-range', 'snapshot-body']) {
    test('retiring $phase closes its real TCP but preserves another download and shared client', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final subscription = server.listen((socket) {
        sockets.add(socket);
        var input = '';
        var replied = false;
        var hanging = false;
        void ended() {
          if (hanging && !cancelled.isCompleted) cancelled.complete();
        }

        socket.listen(
          (data) {
            input += ascii.decode(data);
            if (replied || !input.contains('\r\n\r\n')) return;
            replied = true;
            hanging = input.startsWith('GET /hang ');
            if (!hanging) {
              socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc'));
              unawaited(socket.flush().then((_) => socket.close()));
            } else {
              if (phase == 'redirect-body') {
                socket.add(ascii.encode('HTTP/1.1 302 Found\r\nLocation: /next\r\nContent-Length: 100\r\n\r\nx'));
              } else if (phase != 'headers') {
                socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nx'));
              }
              unawaited(
                socket.flush().then((_) {
                  if (!started.isCompleted) started.complete();
                }),
              );
            }
          },
          onDone: ended,
          onError: (Object _) => ended(),
        );
      });
      final client = HttpClient()..connectionTimeout = idle;
      final base = Uri.parse('http://127.0.0.1:${server.port}/root.m3u8');
      final redirectReading = Completer<void>();
      final upstream = HlsUpstreamClient(
        client: phase == 'redirect-body' ? _ObserveRedirectClient(client, redirectReading) : client,
        source: base,
        headers: {},
        cookies: HlsSessionCookies(),
      );
      final cache = pool();
      try {
        final bad = cache.prefetch('hang', (cancel) async {
          if (phase == 'snapshot-body') {
            await upstream.loadSnapshot(base.resolve('/hang'), cancel, budget: HlsResponseBudget(idle));
            throw StateError('Cancelled snapshot unexpectedly completed');
          }
          return upstream.loadMedia(
            base.resolve('/hang'),
            cancel,
            budget: HlsResponseBudget(idle),
            range: phase == 'bad-range' ? const HlsSegmentRange(10, 3) : null,
          );
        })!;
        final good = cache.prefetch(
          'good',
          (cancel) => upstream.loadMedia(base.resolve('/good'), cancel, budget: HlsResponseBudget(idle)),
        )!;
        await started.future.timeout(idle);
        expect(await good.ready, true);
        expect(await bytes(cache.acquire('good')!), ascii.encode('abc'));
        // Observe actual subscription rather than relying on a scheduling delay
        // or cancelling while response headers are still in flight.
        if (phase == 'redirect-body') await redirectReading.future.timeout(idle);
        if (phase == 'bad-range') {
          expect(await bad.ready, false);
          expect(bad.failure, HlsPrefetchFailure.download);
        } else {
          await cache.evict('hang').timeout(idle);
        }
        await cancelled.future.timeout(idle);
        expect(cache.acquire('hang'), isNull);
        final (later, _) = await upstream.open('GET', base.resolve('/later'), budget: HlsResponseBudget(idle));
        expect(await later.transform(ascii.decoder).join(), 'abc');
        expect(await bytes(cache.acquire('good')!), ascii.encode('abc'));
      } finally {
        upstream.stop();
        client.close(force: true);
        await cache.close();
        upstream.clear();
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      }
      expect(cache.ownedEntries, 0);
      expect(cache.retainedBytes, 0);
    });
  }
  test('pool rejects mismatched body/metadata contracts and cancels unread response', () async {
    final cache = pool();
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    try {
      final ticket = cache.prefetch(
        'mismatch',
        (_) async => HlsPrefetchResponse(
          stream.stream,
          expectedLength: 2,
          metadata: HlsHttpBodyMetadata.validate(statusCode: 200, contentLength: 3),
        ),
      )!;
      expect(await ticket.ready, false);
      await cache.close();
      expect(cancelled, true);
      expect(cache.acquire('mismatch'), isNull);
    } finally {
      await cache.close();
      await stream.close();
    }
  });
}

final class _ObserveRedirectClient implements HttpClient {
  _ObserveRedirectClient(this.inner, this.reading);
  final HttpClient inner;
  final Completer<void> reading;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async =>
      _ObserveRedirectRequest(await inner.openUrl(method, uri), reading);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ObserveRedirectRequest implements HttpClientRequest {
  _ObserveRedirectRequest(this.inner, this.reading);
  final HttpClientRequest inner;
  final Completer<void> reading;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  set followRedirects(bool value) => inner.followRedirects = value;
  @override
  Future<HttpClientResponse> get done => inner.done;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) => inner.abort(exception, stackTrace);
  @override
  Future<HttpClientResponse> close() async {
    final response = await inner.close();
    return response.statusCode == 302 ? _ObserveRedirectResponse(response, reading) : response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ObserveRedirectResponse extends Stream<List<int>> implements HttpClientResponse {
  _ObserveRedirectResponse(this.inner, this.reading);
  final HttpClientResponse inner;
  final Completer<void> reading;
  @override
  int get statusCode => inner.statusCode;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = inner.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    if (!reading.isCompleted) reading.complete();
    return subscription;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
