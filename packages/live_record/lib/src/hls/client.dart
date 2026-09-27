import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_media/live_media.dart';
import 'package:live_record/src/hls/playlist.dart';
import 'package:meta/meta.dart';

/// One GET of an HLS resource: a playlist, segment, key or initialisation
/// section.
@immutable
final class HlsRequest {
  /// Creates a request.
  const new({required this.url, this.headers = const {}, this.range, this.maxBytes = 64 << 20, this.cancel});

  /// Absolute URL.
  final Uri url;

  /// Request headers (the line's headers: user agent, referer, cookie…).
  final Map<String, String> headers;

  /// Bytes wanted; null for the whole resource.
  final M3u8ByteRange? range;

  /// A larger body fails the request.
  final int maxBytes;

  /// Completes when the request must be dropped.
  final Future<void>? cancel;
}

/// The body of a successful [HlsRequest].
@immutable
final class HlsResponse {
  /// Creates a response.
  const new({required this.body, required this.url});

  /// Exactly the bytes asked for (the range when one was given).
  final Uint8List body;

  /// Final URL after redirects: the base for relative URIs of a playlist.
  final Uri url;
}

/// A body that did not arrive whole: shorter than its `Content-Length` or
/// range, larger than allowed, or stalled.
final class HlsTransferException implements Exception {
  /// Creates the exception.
  const new(this.message, this.url);

  /// What went wrong.
  final String message;

  /// Requested URL.
  final Uri url;

  @override
  String toString() => 'HLS transfer from ${url.host} failed: $message';
}

/// A request dropped through [HlsRequest.cancel].
final class HlsCancelled implements Exception {
  /// Creates the exception.
  const new();

  @override
  String toString() => 'HLS request cancelled';
}

/// HTTP access of the HLS recorder (spec §7). Answers other than 2xx throw
/// `UpstreamStatusException` (so 4xx and 5xx are classified like FLV
/// connections, §21); a body that does not arrive whole throws
/// [HlsTransferException]. Only whole bodies are returned: a segment is
/// never written half (REG-RECORD-020).
abstract interface class HlsClient {
  /// Fetches [request].
  Future<HlsResponse> get(HlsRequest request);

  /// Drops pooled connections and session cookies.
  void close();
}

/// Session cookies of one recording (spec §7.7): kept in memory only, per
/// origin (scheme, host and port: never shared across hosts, REG-RECORD-030),
/// at most 64 cookies and 16 KiB per origin, 4 KiB per cookie.
final class HlsCookieJar {
  static const int _maxCookies = 64;
  static const int _maxBytes = 16 * 1024;
  static const int _maxCookie = 4 * 1024;

  final _origins = <String, Map<String, String>>{};

  static String _origin(Uri url) => '${url.scheme}://${url.host}:${url.port}';

  /// Takes the `Set-Cookie` values of a response from [url].
  void store(Uri url, List<String> setCookies) {
    if (setCookies.isEmpty) return;
    final jar = _origins.putIfAbsent(_origin(url), () => <String, String>{});
    for (final header in setCookies) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(header);
      } on Object {
        continue;
      }
      final expired =
          (cookie.maxAge != null && cookie.maxAge! <= 0) ||
          (cookie.expires != null && cookie.expires!.isBefore(DateTime.now()));
      if (expired || cookie.value.isEmpty) {
        jar.remove(cookie.name);
        continue;
      }
      if (cookie.name.length + cookie.value.length > _maxCookie) continue;
      jar
        ..remove(cookie.name)
        ..[cookie.name] = cookie.value;
      // Oldest first out when over a limit.
      while (jar.length > _maxCookies || _size(jar) > _maxBytes) {
        jar.remove(jar.keys.first);
      }
    }
  }

  static int _size(Map<String, String> jar) =>
      jar.entries.fold(0, (sum, entry) => sum + entry.key.length + entry.value.length + 2);

  /// The `Cookie` header value for a request to [url], or null.
  String? header(Uri url) {
    final jar = _origins[_origin(url)];
    if (jar == null || jar.isEmpty) return null;
    return jar.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  /// Forgets everything.
  void clear() => _origins.clear();
}

/// [HlsClient] over `dart:io`: TLS verified (REG-RECORD-021), every request
/// through `findProxy` (the app's proxy policy, REG-RECORD-022), pooled
/// keep-alive connections, session cookies per origin (§7.7). A response
/// that sends nothing for [idleTimeout] fails; so does a body shorter than
/// its `Content-Length`.
final class IoHlsClient implements HlsClient {
  /// Creates a client. [findProxy] answers like `HttpClient.findProxy`
  /// (`DIRECT`, `PROXY host:port`) for each request URL.
  new({
    String Function(Uri url)? findProxy,
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 15),
  }) : _client = HttpClient() {
    _client
      ..connectionTimeout = connectTimeout
      ..idleTimeout = const Duration(seconds: 30)
      ..autoUncompress = true
      ..userAgent = null
      ..findProxy = findProxy ?? ((_) => 'DIRECT');
  }

  /// Limit for connecting and for the response head.
  final Duration connectTimeout;

  /// Longest pause while the body arrives.
  final Duration idleTimeout;

  final HttpClient _client;
  final _cookies = HlsCookieJar();

  @override
  Future<HlsResponse> get(HlsRequest request) {
    HttpClientRequest? outgoing;
    StreamSubscription<List<int>>? subscription;
    Timer? idle;
    final result = Completer<HlsResponse>();
    void fail(Object error) {
      idle?.cancel();
      if (!result.isCompleted) result.completeError(error);
    }

    unawaited(
      request.cancel?.then((_) {
        outgoing?.abort(const HlsCancelled());
        unawaited(subscription?.cancel());
        fail(const HlsCancelled());
      }),
    );
    unawaited(() async {
      try {
        final open = outgoing = await _client.getUrl(request.url).timeout(connectTimeout);
        if (result.isCompleted) {
          open.abort(const HlsCancelled());
          return;
        }
        open
          ..followRedirects = true
          ..maxRedirects = 5;
        request.headers.forEach((name, value) => open.headers.set(name, value, preserveHeaderCase: true));
        final session = _cookies.header(request.url);
        if (session != null) {
          final platform = request.headers.entries.where((e) => e.key.toLowerCase() == 'cookie').firstOrNull?.value;
          open.headers.set(
            HttpHeaders.cookieHeader,
            platform == null || platform.isEmpty ? session : '$platform; $session',
          );
        }
        final range = request.range;
        if (range != null) open.headers.set(HttpHeaders.rangeHeader, range.header);
        final response = await open.close().timeout(connectTimeout);
        final redirects = response.redirects;
        final url = redirects.isEmpty ? request.url : request.url.resolveUri(redirects.last.location);
        _cookies.store(url, response.headers[HttpHeaders.setCookieHeader] ?? const []);
        final status = response.statusCode;
        if (result.isCompleted || status < 200 || status > 299) {
          unawaited(response.drain<void>().catchError((Object _) {}));
          fail(UpstreamStatusException(status, request.url));
          return;
        }
        final encoded = (response.headers.value(HttpHeaders.contentEncodingHeader) ?? 'identity') != 'identity';
        final declared = encoded ? -1 : response.contentLength;
        if (declared > request.maxBytes) {
          unawaited(response.drain<void>().catchError((Object _) {}));
          fail(HlsTransferException('$declared bytes is over the ${request.maxBytes} byte limit', request.url));
          return;
        }
        final builder = BytesBuilder(copy: false);
        void arm() {
          idle?.cancel();
          idle = Timer(idleTimeout, () {
            unawaited(subscription?.cancel());
            open.abort();
            fail(HlsTransferException('no data for ${idleTimeout.inSeconds} s', request.url));
          });
        }

        arm();
        subscription = response.listen(
          (chunk) {
            builder.add(chunk);
            if (builder.length > request.maxBytes) {
              unawaited(subscription?.cancel());
              open.abort();
              fail(HlsTransferException('body over the ${request.maxBytes} byte limit', request.url));
              return;
            }
            arm();
          },
          onError: fail,
          onDone: () {
            idle?.cancel();
            if (result.isCompleted) return;
            final body = builder.takeBytes();
            if (declared >= 0 && body.length != declared) {
              fail(HlsTransferException('got ${body.length} of $declared bytes', request.url));
              return;
            }
            try {
              result.complete(HlsResponse(body: _slice(body, range, status, request.url), url: url));
            } on Object catch (error) {
              fail(error);
            }
          },
          cancelOnError: true,
        );
      } on Object catch (error) {
        fail(error);
      }
    }());
    return result.future;
  }

  /// The wanted bytes: a 206 answer is the range itself; a server that
  /// ignores `Range` answers 200 with the whole resource.
  static Uint8List _slice(Uint8List body, M3u8ByteRange? range, int status, Uri url) {
    if (range == null) return body;
    if (status == 206) {
      if (body.length != range.length) {
        throw HlsTransferException('range answer of ${body.length} bytes, asked for ${range.length}', url);
      }
      return body;
    }
    if (body.length < range.end) throw HlsTransferException('resource of ${body.length} bytes ends before $range', url);
    return Uint8List.sublistView(body, range.offset, range.end);
  }

  @override
  void close() {
    _cookies.clear();
    _client.close(force: true);
  }
}
