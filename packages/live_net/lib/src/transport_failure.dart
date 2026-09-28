import 'package:live_net/src/response.dart';
import 'package:meta/meta.dart';

/// Why a request did not produce a response.
enum TransportReason {
  /// DNS, refused or reset connection.
  connect,

  /// TLS handshake or certificate failure.
  tls,

  /// The request's timeout elapsed.
  timeout,

  /// The caller cancelled.
  cancelled,

  /// Malformed HTTP or too many redirects.
  protocol,
}

/// A transport-level failure: no response arrived.
@immutable
final class TransportFailure implements Exception {
  /// Creates the failure.
  const new(this.site, this.reason, [this.detail]);

  /// Platform id of the request.
  final String site;

  /// What went wrong.
  final TransportReason reason;

  /// Diagnostic detail; never contains cookies or tokens.
  final String? detail;

  @override
  String toString() => 'TransportFailure($site, ${reason.name}${detail == null ? '' : ': $detail'})';
}

/// A response whose status is not 2xx, thrown by the `LiveHttpCalls`
/// helpers (3.x's `HttpError` from a bad response). The text shown to the
/// user comes from the status in the interface layer, not from here.
@immutable
final class HttpStatusFailure implements Exception {
  /// Creates the failure.
  const new(this.site, this.status, {this.bodyPreview, this.headers = const {}});

  /// The failure for [response]: its status, the first [previewLength]
  /// characters of its body and its headers.
  ///
  /// A rejected request (Douyu's edge answers 403 with a four-byte body) says
  /// nothing through the status code alone; the body and the request id
  /// header are what make it diagnosable.
  factory of(String site, LiveResponse response, {int previewLength = 256}) {
    final text = response.text;
    return HttpStatusFailure(
      site,
      response.status,
      bodyPreview: text.length <= previewLength ? text : text.substring(0, previewLength),
      headers: {
        for (final MapEntry(:key, :value) in response.headers.entries)
          if (value.isNotEmpty) key: value.join(', '),
      },
    );
  }

  /// Platform id of the request.
  final String site;

  /// Status code.
  final int status;

  /// Start of the response body, for diagnostics only.
  final String? bodyPreview;

  /// Response headers by lower-case name, repeated values joined.
  final Map<String, String> headers;

  @override
  String toString() => 'HttpStatusFailure($site, $status)';
}
