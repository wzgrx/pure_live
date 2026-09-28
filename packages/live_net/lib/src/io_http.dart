import 'dart:async';
import 'dart:io';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/proxy.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';
import 'package:live_net/src/streamed_response.dart';
import 'package:live_net/src/transport_failure.dart';

/// [LiveHttp] on `dart:io`: one pooled client per proxy route, gzip and
/// deflate decoding, per-request timeout and cancellation.
///
/// Replaces 3.x's dio singleton, which read the proxy from the settings
/// service on every connection and had to be rebuilt when it changed; here
/// the [proxy] policy decides the route per platform and request.
final class IoLiveHttp implements LiveHttp {
  /// Creates the transport.
  new({this.proxy = const FixedProxyPolicy(), this.connectTimeout = defaultRequestTimeout});

  /// Route per platform.
  final ProxyPolicy proxy;

  /// Limit for opening a connection.
  final Duration connectTimeout;

  final Map<ProxyRoute, HttpClient> _clients = {};

  HttpClient _client(ProxyRoute route) => _clients.putIfAbsent(
    route,
    () => HttpClient()
      ..connectionTimeout = connectTimeout
      ..idleTimeout = const Duration(seconds: 30)
      ..autoUncompress = true
      ..userAgent = null
      ..findProxy = (_) => route.directive,
  );

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final exchange = _Exchange(request, _client(proxy.routeFor(request.site, request.url)));
    try {
      return await exchange.race(() async {
        final response = await exchange.start();
        final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
        exchange.done = true;
        return LiveResponse(
          status: response.statusCode,
          headers: _headers(response),
          bytes: bytes,
          url: _finalUrl(request, response),
        );
      });
    } finally {
      exchange.finish();
    }
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final exchange = _Exchange(request, _client(proxy.routeFor(request.site, request.url)));
    final HttpClientResponse response;
    try {
      response = await exchange.race(exchange.start);
    } on Object {
      exchange.finish();
      rethrow;
    }
    final controller = StreamController<List<int>>();
    StreamSubscription<List<int>>? subscription;
    StreamSubscription<void>? cancelWatch;
    void fail(Object error) {
      if (controller.isClosed) return;
      controller.addError(failureOf(request.site, error, request.timeout));
      unawaited(controller.close());
      unawaited(subscription?.cancel());
      unawaited(cancelWatch?.cancel());
      exchange.finish();
    }

    controller
      ..onListen = () {
        cancelWatch = request.cancel?.whenCancelled.asStream().listen(
          (_) => fail(TransportFailure(request.site, TransportReason.cancelled)),
        );
        subscription = response
            .timeout(request.timeout)
            .listen(
              controller.add,
              onError: (Object error, StackTrace _) => fail(error),
              onDone: () {
                exchange.done = true;
                unawaited(cancelWatch?.cancel());
                unawaited(controller.close());
              },
              cancelOnError: true,
            );
      }
      ..onPause = () {
        subscription?.pause();
      }
      ..onResume = () {
        subscription?.resume();
      }
      ..onCancel = () async {
        await cancelWatch?.cancel();
        await subscription?.cancel();
        exchange.finish();
      };
    final length = response.contentLength;
    return LiveStreamedResponse(
      status: response.statusCode,
      headers: _headers(response),
      body: controller.stream,
      url: _finalUrl(request, response),
      contentLength: length < 0 ? null : length,
    );
  }

  static Map<String, List<String>> _headers(HttpClientResponse response) {
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) => headers[name.toLowerCase()] = [...values]);
    return headers;
  }

  static Uri _finalUrl(LiveRequest request, HttpClientResponse response) {
    final redirects = response.redirects;
    return redirects.isEmpty ? request.url : request.url.resolveUri(redirects.last.location);
  }

  @override
  void close() {
    for (final client in _clients.values) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

/// The [TransportFailure] for a `dart:io` [error] of [site]'s request.
/// Errors that are not transport errors become [TransportReason.protocol].
TransportFailure failureOf(String site, Object error, Duration timeout) => switch (error) {
  TransportFailure() => error,
  TimeoutException() => TransportFailure(site, TransportReason.timeout, 'after ${timeout.inMilliseconds} ms'),
  TlsException(:final message) => TransportFailure(site, TransportReason.tls, message),
  SocketException(:final message) => TransportFailure(site, TransportReason.connect, message),
  RedirectException(:final message) => TransportFailure(site, TransportReason.protocol, message),
  HttpException(:final message) => TransportFailure(site, TransportReason.protocol, message),
  _ => TransportFailure(site, TransportReason.protocol, error.runtimeType.toString()),
};

/// One request on a pooled client: races it against its timeout and
/// cancellation, and aborts the connection when it is abandoned.
final class _Exchange {
  new(this.request, this.client);

  final LiveRequest request;
  final HttpClient client;
  HttpClientRequest? _outgoing;
  bool _abandoned = false;

  /// Set once the whole body was read; the connection may then be reused.
  bool done = false;

  /// Sends the request and waits for the response headers.
  Future<HttpClientResponse> start() async {
    final outgoing = _outgoing = await client.openUrl(request.method, request.url);
    // Timed out or cancelled while the connection (or its TLS handshake) was
    // still being made: drop it instead of sending a request nobody waits for.
    if (_abandoned) {
      outgoing.abort();
      throw TransportFailure(request.site, TransportReason.cancelled);
    }
    outgoing
      ..followRedirects = request.followRedirects
      ..maxRedirects = 5;
    request.headers.forEach((name, value) => outgoing.headers.set(name, value, preserveHeaderCase: true));
    final body = request.body;
    if (body != null) {
      outgoing
        ..contentLength = body.length
        ..add(body);
    }
    return await outgoing.close();
  }

  /// Runs [work] within the timeout, unless cancelled first.
  Future<T> race<T>(Future<T> Function() work) async {
    if (request.cancel?.isCancelled ?? false) throw TransportFailure(request.site, TransportReason.cancelled);
    final cancelled = request.cancel?.whenCancelled.then<T>(
      (_) => throw TransportFailure(request.site, TransportReason.cancelled),
    );
    try {
      final result = await Future.any([work().timeout(request.timeout), ?cancelled]);
      return result;
    } on Object catch (error) {
      throw failureOf(request.site, error, request.timeout);
    }
  }

  /// Aborts the connection unless the body was read completely.
  void finish() {
    if (done) return;
    done = true;
    _abandoned = true;
    _outgoing?.abort();
  }
}
