import 'dart:async';
import 'dart:io';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/proxy.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';
import 'package:live_net/src/transport_failure.dart';

/// [LiveHttp] on `dart:io` (ADR 0011, rule 1): one pooled client per proxy
/// route, gzip/deflate decoding, per-request timeout and cancellation.
final class IoLiveHttp implements LiveHttp {
  /// Creates the transport.
  new({this.proxy = const FixedProxyPolicy(), this.connectTimeout = const Duration(seconds: 10)});

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
    if (request.cancel?.isCancelled ?? false) {
      throw TransportFailure(request.site, TransportReason.cancelled);
    }
    final client = _client(proxy.routeFor(request.site, request.url));
    HttpClientRequest? outgoing;
    var finished = false;

    Future<LiveResponse> exchange() async {
      outgoing = await client.openUrl(request.method, request.url);
      final open = outgoing!
        ..followRedirects = request.followRedirects
        ..maxRedirects = 5;
      request.headers.forEach((name, value) => open.headers.set(name, value, preserveHeaderCase: true));
      final body = request.body;
      if (body != null) {
        open
          ..contentLength = body.length
          ..add(body);
      }
      final response = await open.close();
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      final headers = <String, List<String>>{};
      response.headers.forEach((name, values) => headers[name.toLowerCase()] = [...values]);
      final redirects = response.redirects;
      return LiveResponse(
        status: response.statusCode,
        headers: headers,
        bytes: bytes,
        url: redirects.isEmpty ? request.url : request.url.resolveUri(redirects.last.location),
      );
    }

    final cancelled = request.cancel?.whenCancelled.then<LiveResponse>(
      (_) => throw TransportFailure(request.site, TransportReason.cancelled),
    );
    try {
      final result = await Future.any([exchange().timeout(request.timeout), ?cancelled]);
      finished = true;
      return result;
    } on TransportFailure {
      rethrow;
    } on TimeoutException {
      throw TransportFailure(request.site, TransportReason.timeout, 'after ${request.timeout.inMilliseconds} ms');
    } on HandshakeException catch (error) {
      throw TransportFailure(request.site, TransportReason.tls, error.message);
    } on TlsException catch (error) {
      throw TransportFailure(request.site, TransportReason.tls, error.message);
    } on SocketException catch (error) {
      throw TransportFailure(request.site, TransportReason.connect, error.message);
    } on RedirectException catch (error) {
      throw TransportFailure(request.site, TransportReason.protocol, error.message);
    } on HttpException catch (error) {
      throw TransportFailure(request.site, TransportReason.protocol, error.message);
    } finally {
      if (!finished) outgoing?.abort();
    }
  }

  @override
  void close() {
    for (final client in _clients.values) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
