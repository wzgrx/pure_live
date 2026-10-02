import 'package:meta/meta.dart';

/// Every failure the cast package reports (docs/N-多画面和投屏/N02-投屏/N02.1-投屏/record.md).
///
/// Sealed so the app words each kind by type, never by message text.
@immutable
sealed class CastFailure implements Exception {
  const new([this.detail]);

  /// Diagnostic detail for logs; never shown as UI copy.
  final String? detail;

  /// Stable name of the kind, for logs and diagnostics.
  String get kind;

  @override
  String toString() => '$kind${detail == null ? '' : '($detail)'}';
}

/// The search could not start: no usable network interface, the sockets were
/// refused, or no M-SEARCH could be sent.
final class CastSearchFailure extends CastFailure {
  /// Creates the failure.
  const new([super.detail]);

  @override
  String get kind => 'CastSearchFailure';
}

/// A device did not answer within [timeout].
final class CastTimeoutFailure extends CastFailure {
  /// Creates the failure.
  const new(this.timeout, [super.detail]);

  /// The limit that passed.
  final Duration timeout;

  @override
  String get kind => 'CastTimeoutFailure';
}

/// The connection to a device failed: refused, reset, unreachable.
final class CastNetworkFailure extends CastFailure {
  /// Creates the failure.
  const new([super.detail]);

  @override
  String get kind => 'CastNetworkFailure';
}

/// A device answered with an HTTP error status and no UPnP error.
final class CastHttpFailure extends CastFailure {
  /// Creates the failure.
  const new(this.statusCode, [super.detail]);

  /// HTTP status.
  final int statusCode;

  @override
  String get kind => 'CastHttpFailure';
}

/// A description or response that cannot be read: not XML, no device, a
/// SOAP fault without a UPnP error, an oversized body.
final class CastProtocolFailure extends CastFailure {
  /// Creates the failure.
  const new([super.detail]);

  @override
  String get kind => 'CastProtocolFailure';
}

/// The device refused a UPnP action with an error code (UPnP Device
/// Architecture 1.1 §3.2.2; AVTransport:1 §2.4).
final class UpnpActionFailure extends CastFailure {
  /// Creates the failure.
  const new(this.action, this.code, [super.detail]);

  /// Action name (`SetAVTransportURI`).
  final String action;

  /// UPnP error code (`716`).
  final int code;

  /// The code as a known error.
  UpnpError get error => UpnpError.of(code);

  @override
  String get kind => 'UpnpActionFailure';

  @override
  String toString() => '$kind($action, $code${detail == null ? '' : ': $detail'})';
}

/// UPnP error codes: the architecture's (4xx, 5xx, 6xx) and AVTransport's
/// (7xx).
enum UpnpError {
  /// 401: the device does not know the action.
  invalidAction(401),

  /// 402: missing or wrong arguments.
  invalidArgs(402),

  /// 501: the action failed for a reason the device does not say.
  actionFailed(501),

  /// 600: an argument value is invalid.
  argumentValueInvalid(600),

  /// 601: an argument value is out of range.
  argumentValueOutOfRange(601),

  /// 602: an optional action the device did not implement.
  optionalActionNotImplemented(602),

  /// 603: the device ran out of memory.
  outOfMemory(603),

  /// 604: someone has to act on the device first.
  humanInterventionRequired(604),

  /// 605: a string argument is too long (long metadata).
  stringArgumentTooLong(605),

  /// 701: the transport cannot make this transition now (loading, busy).
  transitionNotAvailable(701),

  /// 702: nothing is loaded.
  noContents(702),

  /// 703: the media could not be read.
  readError(703),

  /// 704: the media format is not supported.
  formatNotSupported(704),

  /// 705: the transport is locked by another control point.
  transportLocked(705),

  /// 706: the media could not be written.
  writeError(706),

  /// 707: the media is protected.
  mediaProtected(707),

  /// 708: the recording format is not supported.
  recordFormatNotSupported(708),

  /// 709: the media is full.
  mediaFull(709),

  /// 710: the seek mode is not supported.
  seekModeNotSupported(710),

  /// 711: the seek target is invalid.
  illegalSeekTarget(711),

  /// 712: the play mode is not supported.
  playModeNotSupported(712),

  /// 713: the record quality is not supported.
  recordQualityNotSupported(713),

  /// 714: the MIME type in the metadata is not accepted.
  illegalMimeType(714),

  /// 715: the content is in use.
  contentBusy(715),

  /// 716: the URI cannot be reached or found.
  resourceNotFound(716),

  /// 717: the play speed is not supported.
  playSpeedNotSupported(717),

  /// 718: the instance id is invalid.
  invalidInstanceId(718),

  /// 719: a DRM error.
  drmError(719),

  /// 720: the content expired.
  expiredContent(720),

  /// 721: the use is not allowed.
  nonAllowedUse(721),

  /// 722: the allowed uses cannot be determined.
  cantDetermineAllowedUses(722),

  /// 723: the allowed uses are exhausted.
  exhaustedAllowedUse(723),

  /// 724: the device failed authentication.
  deviceAuthenticationFailure(724),

  /// 725: the device was revoked.
  deviceRevocation(725),

  /// Any other code (vendor codes 800–899 and unknown values).
  unknown(0);

  new(this.code);

  /// Numeric code; 0 for [unknown].
  final int code;

  /// The error with [code], or [unknown].
  static UpnpError of(int code) {
    for (final error in values) {
      if (error.code == code && error != unknown) return error;
    }
    return unknown;
  }

  /// The renderer is busy with something else; stopping it and asking again
  /// can succeed.
  bool get busy => this == transitionNotAvailable || this == transportLocked || this == contentBusy;

  /// The renderer cannot play the media itself: format, MIME type, or it
  /// cannot read or reach the URI.
  bool get unplayable => const {
    formatNotSupported,
    illegalMimeType,
    readError,
    noContents,
    resourceNotFound,
    drmError,
    mediaProtected,
  }.contains(this);
}
