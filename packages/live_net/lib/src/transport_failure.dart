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

/// A transport-level failure (ADR 0011, rule 2); adapters map it to
/// `NetworkFailure`, except [TransportReason.cancelled].
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
