import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

/// Cancels an in-flight request; one token can cancel several.
final class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels every request using this token.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// How long a request may take unless it says otherwise: 3.x used 20 seconds
/// for connecting, sending and receiving (`HttpClient` in v3's
/// `core/common/http_client.dart`).
const Duration defaultRequestTimeout = Duration(seconds: 20);

/// One HTTP request.
@immutable
final class LiveRequest {
  /// Creates a request; header names are matched case-insensitively.
  const new({
    required this.site,
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.body,
    this.followRedirects = true,
    this.timeout = defaultRequestTimeout,
    this.cancel,
  });

  /// A GET for [url] with [query] added to its query string. Null values are
  /// left out, iterables become repeated parameters and anything else is sent
  /// as its `toString()`. The URL's own query is kept as written when [query]
  /// is empty, so signed URLs are never re-encoded.
  factory get({
    required String site,
    required Uri url,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => LiveRequest(site: site, url: withQuery(url, query), headers: headers, timeout: timeout, cancel: cancel);

  /// A POST with an `application/x-www-form-urlencoded` body; values are
  /// percent-encoded (Douyu enc_data may hold `+`, `/`, `=`).
  factory form({
    required String site,
    required Uri url,
    required Map<String, String> fields,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => LiveRequest(
    site: site,
    url: withQuery(url, query),
    method: 'POST',
    headers: {...headers, 'content-type': 'application/x-www-form-urlencoded; charset=utf-8'},
    body: utf8.encode(
      fields.entries
          .map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
          .join('&'),
    ),
    timeout: timeout,
    cancel: cancel,
  );

  /// A request whose body is [json] encoded as UTF-8 JSON.
  factory json({
    required String site,
    required Uri url,
    required Object? json,
    String method = 'POST',
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => LiveRequest(
    site: site,
    url: withQuery(url, query),
    method: method,
    headers: {...headers, 'content-type': 'application/json; charset=utf-8'},
    body: utf8.encode(jsonEncode(json)),
    timeout: timeout,
    cancel: cancel,
  );

  /// Platform id; selects the proxy route and the throttle.
  final String site;

  /// Absolute URL.
  final Uri url;

  /// HTTP method.
  final String method;

  /// Request headers.
  final Map<String, String> headers;

  /// Body bytes, or null.
  final List<int>? body;

  /// Whether to follow redirects (at most 5); when false a 3xx is returned.
  final bool followRedirects;

  /// Limit for the whole exchange of `LiveHttp.send`. For `LiveHttp.open` it
  /// limits the wait for the response headers and every gap between body
  /// chunks, like 3.x's receive timeout.
  final Duration timeout;

  /// Cancellation.
  final CancelToken? cancel;

  /// [url] with [query] appended (see [LiveRequest.get]). Like dio in 3.x,
  /// the new parameters are appended to the existing query string, which is
  /// kept byte for byte: signed parameters must not be re-encoded.
  static Uri withQuery(Uri url, Map<String, Object?> query) {
    final pairs = <String>[
      for (final MapEntry(:key, :value) in query.entries)
        if (value != null)
          for (final item in value is Iterable ? value : [value])
            '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent('$item')}',
    ];
    if (pairs.isEmpty) return url;
    final added = pairs.join('&');
    return url.replace(query: url.query.isEmpty ? added : '${url.query}&$added');
  }
}
