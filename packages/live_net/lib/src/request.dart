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

/// One HTTP request from a platform adapter (ADR 0011, rule 2).
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
    this.timeout = const Duration(seconds: 15),
    this.cancel,
  });

  /// A POST with an `application/x-www-form-urlencoded` body; values are
  /// percent-encoded (Douyu enc_data may hold `+`, `/`, `=`).
  factory form({
    required String site,
    required Uri url,
    required Map<String, String> fields,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
    CancelToken? cancel,
  }) => LiveRequest(
    site: site,
    url: url,
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

  /// Limit for the whole exchange, body included.
  final Duration timeout;

  /// Cancellation.
  final CancelToken? cancel;
}
