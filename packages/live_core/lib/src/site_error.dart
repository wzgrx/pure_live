import 'package:meta/meta.dart';

/// Every failure an adapter reports (ADR 0010, rule 6).
///
/// Sealed so the UI and the recovery policy handle each kind by type, never
/// by message text.
@immutable
sealed class SiteError implements Exception {
  const new(this.site, [this.detail]);

  /// Platform id, for example `douyu`.
  final String site;

  /// Diagnostic detail for logs; never shown as UI copy.
  final String? detail;

  /// Whether retrying the same request later can succeed.
  bool get isTransient => false;

  /// Stable name of the kind, for logs and diagnostics.
  String get kind;

  @override
  String toString() => '$kind($site${detail == null ? '' : ': $detail'})';
}

/// The room or streamer does not exist.
final class NotFound extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'NotFound';
}

/// The content needs a signed-in account.
final class NeedsLogin extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'NeedsLogin';
}

/// The platform throttled the client.
final class RateLimited extends SiteError {
  /// Creates the error.
  const new(String site, {this.retryAfter, String? detail}) : super(site, detail);

  /// Suggested wait, when the platform gives one.
  final Duration? retryAfter;

  @override
  bool get isTransient => true;

  @override
  String get kind => 'RateLimited';
}

/// The platform refused the request as suspicious: a rejected signature, a
/// captcha, a stale cookie.
final class RiskControl extends SiteError {
  /// Creates the error.
  const new(String site, {this.cookieSuspect = false, String? detail}) : super(site, detail);

  /// Whether the user's stored cookie is the likely cause (ask to renew it).
  final bool cookieSuspect;

  @override
  String get kind => 'RiskControl';
}

/// The content is not available in the user's region.
final class RegionBlocked extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'RegionBlocked';
}

/// No playable stream right now: offline, a loop or replay without a stream,
/// or live without video (ADR 0010, revision).
final class StreamUnavailable extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'StreamUnavailable';
}

/// A link that no adapter recognises.
final class UnsupportedLink extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'UnsupportedLink';
}

/// The response does not match the platform spec.
final class ApiChanged extends SiteError {
  /// Creates the error; [detail] should summarise the unexpected shape.
  const new(super.site, [super.detail]);

  @override
  String get kind => 'ApiChanged';
}

/// The network failed before the platform answered.
final class NetworkFailure extends SiteError {
  /// Creates the error.
  const new(super.site, [super.detail]);

  @override
  bool get isTransient => true;

  @override
  String get kind => 'NetworkFailure';
}
