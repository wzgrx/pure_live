import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:meta/meta.dart';

/// How the session reacts to an error kind (spec §21).
enum RetryClass {
  /// The room went offline: end the session normally.
  end,

  /// Not retryable: the task fails.
  none,

  /// Regular backoff (§11.5), bounded by `maxRetries`.
  regular,

  /// Fast reconnect (§11.4): 2 s doubling to 15 s, unbounded, each attempt
  /// after a strict room check.
  fast,

  /// Re-resolve at once (§11.7); regular backoff after 3 in a row.
  reResolve,

  /// Retry the same URL after 1, 2 and 4 s, then regular backoff.
  sameUrl,
}

/// Where a failure happened (spec §21).
enum RecordStage {
  /// Strict room check.
  room,

  /// Quality selection.
  quality,

  /// Stream resolution and lines.
  stream,

  /// Upstream connection.
  network,

  /// File writing.
  writer,

  /// MP4 remux.
  remux,

  /// Concurrency scheduling.
  scheduler,

  /// Background service.
  background,

  /// Waiting-for-live checks.
  status,
}

/// Typed error kinds (spec §21). Never derived from log text.
enum RecordErrorKind {
  /// The strict room check says the room is not live.
  roomOffline(RetryClass.end),

  /// The room is banned.
  roomBanned(RetryClass.none),

  /// The room does not exist.
  roomNotFound(RetryClass.none),

  /// No adapter or recording support for the platform.
  platformUnsupported(RetryClass.none),

  /// The stream needs a signed-in account.
  loginRequired(RetryClass.none),

  /// The stream is not available in this region.
  regionBlocked(RetryClass.none),

  /// The room state could not be determined (parse failure, unexpected answer).
  roomStateUnknown(RetryClass.regular),

  /// A request failed before the platform answered.
  network(RetryClass.regular),

  /// The room is live but offers no stream.
  noQuality(RetryClass.regular),

  /// Every line of every quality failed.
  allLinesFailed(RetryClass.regular),

  /// No line of any quality uses a protocol the recorder can write (HLS,
  /// RTMP…); single unsupported lines are skipped while resolving.
  unsupportedProtocol(RetryClass.none),

  /// The upstream connection ended after media was recorded.
  upstreamEof(RetryClass.fast),

  /// No upstream data within `record.readTimeout`.
  readTimeout(RetryClass.fast),

  /// A session input lost its platform session.
  sessionLeaseLost(RetryClass.fast),

  /// The CDN answered 4xx.
  http4xx(RetryClass.reResolve),

  /// The CDN answered 5xx.
  http5xx(RetryClass.sameUrl),

  /// The disk is full.
  diskFull(RetryClass.none),

  /// Writing is not permitted.
  permissionDenied(RetryClass.none),

  /// The file system is read-only.
  readOnly(RetryClass.none),

  /// The recording path does not exist or is not valid.
  pathInvalid(RetryClass.none),

  /// A disk write did not finish within 30 s (§6.8).
  diskStalled(RetryClass.none),

  /// The system stopped the background service (§16.1).
  backgroundInterrupted(RetryClass.none),

  /// MP4 remux failed; the source files are kept.
  remuxFailed(RetryClass.none),

  /// The recorded input is damaged.
  inputDamaged(RetryClass.none),

  /// Regular retries reached `record.maxRetries` with polling off (REG-RECORD-033).
  retriesExhausted(RetryClass.none);

  new(this.retry);

  /// How the session reacts.
  final RetryClass retry;

  /// Whether this kind ends the session as a failure.
  bool get fatal => retry == RetryClass.none;
}

/// A classified recording error.
@immutable
final class RecordFailure {
  /// Creates a failure; [message] is sanitised with [sanitizeErrorText].
  new(this.kind, this.stage, [String? message]) : message = message == null ? null : sanitizeErrorText(message);

  /// Restores a persisted failure.
  factory fromJson(Map<String, Object?> json) {
    final kind = RecordErrorKind.values.asNameMap()[json['kind']] ?? RecordErrorKind.roomStateUnknown;
    final stage = RecordStage.values.asNameMap()[json['stage']] ?? RecordStage.status;
    return RecordFailure(kind, stage, json['message'] as String?);
  }

  /// Error kind.
  final RecordErrorKind kind;

  /// Where it happened.
  final RecordStage stage;

  /// Sanitised diagnostic text; never contains query strings, cookies or tokens.
  final String? message;

  /// JSON form for persistence.
  Map<String, Object?> toJson() => {'kind': kind.name, 'stage': stage.name, 'message': ?message};

  @override
  bool operator ==(Object other) =>
      other is RecordFailure && other.kind == kind && other.stage == stage && other.message == message;

  @override
  int get hashCode => Object.hash(kind, stage, message);

  @override
  String toString() => 'RecordFailure(${kind.name} at ${stage.name}${message == null ? '' : ': $message'})';
}

/// An error the recorder raises itself.
final class RecordException implements Exception {
  /// Creates the exception.
  new(this.kind, this.stage, [this.detail]);

  /// Error kind.
  final RecordErrorKind kind;

  /// Where it happened.
  final RecordStage stage;

  /// Diagnostic detail.
  final String? detail;

  /// As a [RecordFailure].
  RecordFailure get failure => RecordFailure(kind, stage, detail);

  @override
  String toString() => 'RecordException(${kind.name}${detail == null ? '' : ': ${sanitizeErrorText(detail!)}'})';
}

final _query = RegExp(r'(https?://[^\s?#]+)\?[^\s#]*');
final _secrets = RegExp(
  r'((?:cookie|set-cookie|authorization|token|access_token|wsSecret|sign|auth|did|uid|acf_[a-z]+)\s*[=:]\s*)[^\s,;&]+',
  caseSensitive: false,
);

/// Removes URL query strings, cookies, tokens and signatures from [text]
/// before it is stored or logged (spec §13, REG-RECORD-013).
String sanitizeErrorText(String text) {
  final withoutQueries = text.replaceAllMapped(_query, (match) => '${match[1]}?…');
  final masked = withoutQueries.replaceAllMapped(_secrets, (match) => '${match[1]}…');
  return masked.length > 500 ? '${masked.substring(0, 500)}…' : masked;
}

/// Classifies an adapter error from the strict room check or stream resolution (spec §4.1, §21).
RecordFailure classifySiteError(SiteError error, RecordStage stage) => switch (error) {
  NotFound() => RecordFailure(RecordErrorKind.roomNotFound, stage, error.toString()),
  NeedsLogin() => RecordFailure(RecordErrorKind.loginRequired, stage, error.toString()),
  RegionBlocked() => RecordFailure(RecordErrorKind.regionBlocked, stage, error.toString()),
  UnsupportedLink() => RecordFailure(RecordErrorKind.platformUnsupported, stage, error.toString()),
  StreamUnavailable() => RecordFailure(
    stage == RecordStage.room ? RecordErrorKind.roomOffline : RecordErrorKind.noQuality,
    stage,
    error.toString(),
  ),
  NetworkFailure() || RateLimited() => RecordFailure(RecordErrorKind.network, stage, error.toString()),
  RiskControl() || ApiChanged() => RecordFailure(RecordErrorKind.roomStateUnknown, stage, error.toString()),
};

/// Classifies any error thrown by a room check, a resolve or an upstream
/// connection attempt.
RecordFailure classifyError(Object error, RecordStage stage) => switch (error) {
  RecordException() => error.failure,
  SiteError() => classifySiteError(error, stage),
  UpstreamStatusException(:final status) when status >= 500 => RecordFailure(
    RecordErrorKind.http5xx,
    RecordStage.network,
    'HTTP $status',
  ),
  UpstreamStatusException(:final status) => RecordFailure(RecordErrorKind.http4xx, RecordStage.network, 'HTTP $status'),
  TimeoutException() => RecordFailure(RecordErrorKind.network, stage, 'timed out'),
  FileSystemException() => classifyFileError(error),
  SocketException() ||
  HttpException() ||
  HandshakeException() ||
  TlsException() => RecordFailure(RecordErrorKind.network, stage, error.toString()),
  FormatException() => RecordFailure(RecordErrorKind.network, stage, 'bad upstream data: ${error.message}'),
  _ => RecordFailure(RecordErrorKind.network, stage, error.toString()),
};

/// Maps a file-system error to a fatal disk kind (spec §21): POSIX errno and
/// Windows error codes.
RecordFailure classifyFileError(FileSystemException error) {
  final code = error.osError?.errorCode;
  final kind = switch (code) {
    28 || 112 || 39 => RecordErrorKind.diskFull, // ENOSPC, ERROR_DISK_FULL, ERROR_HANDLE_DISK_FULL
    13 || 1 || 5 => RecordErrorKind.permissionDenied, // EACCES, EPERM, ERROR_ACCESS_DENIED
    30 || 19 => RecordErrorKind.readOnly, // EROFS, ERROR_WRITE_PROTECT
    _ => RecordErrorKind.pathInvalid,
  };
  return RecordFailure(kind, RecordStage.writer, '${error.message} (${error.osError?.message ?? 'no OS error'})');
}
