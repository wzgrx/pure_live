import 'dart:async';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';
import 'package:live_net/src/streamed_response.dart';
import 'package:live_net/src/transport_failure.dart';

/// Reports every failed request to [onFailure] as a structure-only
/// diagnostic (see [describeHttpFailure]): transport failures other than
/// cancellation, and responses that are not 2xx.
///
/// 3.x's `CustomLogInterceptor` did the same inside dio. A diagnostic sink
/// that throws never replaces the original failure.
final class LoggingHttp implements LiveHttp {
  /// Wraps [inner]; [now] is injectable for tests.
  new(this.inner, {required this.onFailure, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The transport doing the work.
  final LiveHttp inner;

  /// Receives one diagnostic per failed request.
  final void Function(String diagnostic) onFailure;

  final DateTime Function() _now;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final started = _now();
    try {
      final response = await inner.send(request);
      if (!response.isSuccess) {
        _report(
          request,
          started,
          kind: 'badResponse',
          status: response.status,
          responseHeaders: response.headers,
          responseLength: response.bytes.length,
        );
      }
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason != TransportReason.cancelled) _report(request, started, kind: failure.reason.name);
      rethrow;
    }
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final started = _now();
    try {
      final response = await inner.open(request);
      if (!response.isSuccess) {
        _report(
          request,
          started,
          kind: 'badResponse',
          status: response.status,
          responseHeaders: response.headers,
          responseLength: response.contentLength,
        );
      }
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason != TransportReason.cancelled) _report(request, started, kind: failure.reason.name);
      rethrow;
    }
  }

  void _report(
    LiveRequest request,
    DateTime started, {
    required String kind,
    int? status,
    Map<String, List<String>> responseHeaders = const {},
    int? responseLength,
  }) {
    try {
      onFailure(
        describeHttpFailure(
          request,
          kind: kind,
          elapsed: _now().difference(started),
          status: status,
          responseHeaders: responseHeaders,
          responseLength: responseLength,
        ),
      );
    } on Object {
      // Diagnostics are never a second failure source.
    }
  }

  @override
  void close() => inner.close();
}

/// A diagnostic for a failed [request] that shows its structure only.
///
/// Signed CDN paths, query values, bodies, cookies, header values and nested
/// error text may all carry credentials, and a deny-list of token names
/// misses each platform's new fields. So only the origin, the method, the
/// number of path segments, the names of query parameters and headers and
/// the sizes of bodies are written. [kind] is `badResponse` or the transport
/// failure reason; a negative [elapsed] (clock change) prints as unknown.
String describeHttpFailure(
  LiveRequest request, {
  required String kind,
  Duration? elapsed,
  int? status,
  Map<String, List<String>> responseHeaders = const {},
  int? responseLength,
}) {
  final url = request.url;
  final origin = url.hasAuthority
      ? Uri(scheme: url.scheme, host: url.host, port: url.hasPort ? url.port : null).toString()
      : '(relative)';
  final time = elapsed == null || elapsed.isNegative ? 'unknown' : '${elapsed.inMilliseconds}ms';
  final body = request.body;
  return '[HTTP Error] [$kind] [Time:$time]\n'
      'Request Method: ${request.method}\n'
      'Response Code: ${status ?? 'none'}\n'
      'Request Origin: $origin\n'
      'Request Path Segments: ${url.pathSegments.length}\n'
      'Request Query Keys: ${_names(url.queryParametersAll.keys)}\n'
      'Request Data Shape: ${body == null ? 'null' : 'bytes(${body.length})'}\n'
      'Request Header Keys: ${_names(request.headers.keys)}\n'
      'Response Header Keys: ${_names(responseHeaders.keys)}\n'
      'Response Data Shape: ${responseLength == null ? 'null' : 'bytes($responseLength)'}';
}

final RegExp _plainName = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,63}$');

/// At most 24 names; anything that does not look like a field name (a value
/// used as a key) is redacted.
String _names(Iterable<String> keys) {
  final list = keys.toList();
  final names = list.take(24).map((key) => _plainName.hasMatch(key) ? key : '(redacted-key)').join(',');
  return '[$names${list.length > 24 ? ',...' : ''}]';
}
