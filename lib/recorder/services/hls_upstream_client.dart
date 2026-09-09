import 'dart:async';
import 'dart:io';

import 'package:pure_live/core/common/hls_source_query_policy.dart';

import 'hls_body_reader.dart';
import 'hls_http_body_metadata.dart';
import 'hls_prefetch_pool.dart';
import 'hls_retained_window.dart';
import 'hls_session_cookies.dart';

/// Shared production/prefetch HTTP policy. The caller owns HttpClient,
/// connectionFactory, proxy/TLS configuration and the returned response body.
/// Cancelling one ticket never closes the shared client or another request.
final class HlsUpstreamClient {
  HlsUpstreamClient({
    required this.client,
    required Uri source,
    required Map<String, String> headers,
    required this.cookies,
    HlsSourceQueryPolicy? queryPolicy,
  }) : _origin = source.origin,
       _headers = Map.of(headers),
       _policy = queryPolicy {
    if (queryPolicy != null && !queryPolicy.matchesSource(source)) {
      throw const FormatException('HLS query policy does not match upstream source');
    }
  }
  final HttpClient client;
  final HlsSessionCookies cookies;
  final String _origin;
  final Map<String, String> _headers;
  HlsSourceQueryPolicy? _policy;
  final Set<void Function()> _aborters = {};
  bool _stopped = false;

  void stop() {
    _stopped = true;
    for (final abort in _aborters.toList()) {
      abort();
    }
  }

  /// Call after the owning relay/pool has awaited its requests and bodies.
  void clear() {
    stop();
    _headers.clear();
    _policy = null;
  }

  void _check(HlsPrefetchCancellation? cancellation, HlsResponseBudget? budget) {
    if (_stopped) throw const HlsUpstreamStopped();
    cancellation?.throwIfCancelled();
    budget?.check();
  }

  Future<(HttpClientResponse, Uri)> open(
    String method,
    Uri upstream, {
    String? range,
    HlsResponseBudget? budget,
    HlsPrefetchCancellation? cancellation,
  }) async {
    var uri = _policy?.apply(upstream) ?? upstream;
    for (var redirects = 0; ; redirects++) {
      _check(cancellation, budget);
      // A connection that has not yielded its request remains owned by the
      // client's connection timeout. Never abandon a late openUrl Future.
      final HttpClientRequest request;
      try {
        request = await client.openUrl(method, uri);
      } on Object {
        _check(cancellation, budget);
        rethrow;
      }
      // Header construction may throw before request.close installs its await.
      // Observe abort completion in that path as well as closing the socket.
      unawaited(request.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
      void abort() => request.abort(const HlsUpstreamStopped());
      _aborters.add(abort);
      final detach = cancellation?.onCancel(abort);
      try {
        _check(cancellation, budget);
        request.followRedirects = false;
        String? initialCookie;
        for (final entry in _headers.entries) {
          final name = entry.key.toLowerCase();
          if (name == HttpHeaders.cookieHeader) {
            if (uri.origin == _origin) initialCookie = entry.value;
            continue;
          }
          if (name == HttpHeaders.authorizationHeader && uri.origin != _origin) continue;
          request.headers.set(entry.key, entry.value, preserveHeaderCase: true);
        }
        final cookie = cookies.headerFor(uri, initialHeader: initialCookie);
        if (cookie != null) request.headers.set(HttpHeaders.cookieHeader, cookie);
        if (!_isPlaylist(uri) && range != null && range.isNotEmpty) {
          request.headers.set(HttpHeaders.rangeHeader, range);
        }
        final response = budget == null
            ? await request.close().timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  request.abort();
                  throw TimeoutException('HLS upstream headers timed out');
                },
              )
            : await budget.wait(request.close, abort: request.abort);
        _check(cancellation, budget);
        cookies.receive(uri, response.headers[HttpHeaders.setCookieHeader] ?? const []);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (!const {301, 302, 303, 307, 308}.contains(response.statusCode) || location == null) {
          return (response, uri);
        }
        final resolved = uri.resolve(location);
        final next = _policy?.apply(resolved) ?? resolved;
        if (redirects >= 5 ||
            !const {'http', 'https'}.contains(next.scheme) ||
            next.userInfo.isNotEmpty ||
            (uri.scheme == 'https' && next.scheme != 'https')) {
          throw const HttpException('HLS redirect rejected or limit exceeded');
        }
        final reader = HlsBodyReader(response);
        try {
          if (budget == null) {
            Future<void> drain() async {
              while (await reader.moveNext()) {
                _check(cancellation, budget);
              }
            }

            await drain().timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                request.abort();
                throw TimeoutException('HLS redirect body timed out');
              },
            );
          } else {
            while (await budget.wait(reader.moveNext)) {
              _check(cancellation, budget);
            }
          }
        } finally {
          await reader.cancel();
        }
        _check(cancellation, budget);
        uri = next;
      } on Object {
        // Includes header construction, cookie parsing and redirect validation,
        // not just request.close: every allocated request has a failure owner.
        request.abort();
        if (_stopped) throw const HlsUpstreamStopped();
        rethrow;
      } finally {
        detach?.call();
        _aborters.remove(abort);
      }
    }
  }

  /// Body ownership passes directly to the pool, which validates actual size,
  /// deadlines and sealing before making this metadata available to a lease.
  Future<HlsPrefetchResponse> loadMedia(
    Uri uri,
    HlsPrefetchCancellation cancellation, {
    required HlsResponseBudget budget,
    HlsSegmentRange? range,
  }) async {
    HlsHttpBodyMetadata.validateRequestRange(range);
    final (response, _) = await open(
      'GET',
      uri,
      range: range?.requestHeader,
      budget: budget,
      cancellation: cancellation,
    );
    try {
      _check(cancellation, budget);
      final metadata = HlsHttpBodyMetadata.fromResponse(response, requestedRange: range);
      return HlsPrefetchResponse(response, expectedLength: metadata.expectedLength, metadata: metadata);
    } on Object {
      await HlsBodyReader(response).cancel();
      rethrow;
    }
  }

  static bool _isPlaylist(Uri uri) => RegExp(r'\.m3u8$', caseSensitive: false).hasMatch(uri.path);
}

final class HlsUpstreamStopped implements Exception {
  const HlsUpstreamStopped();
}
