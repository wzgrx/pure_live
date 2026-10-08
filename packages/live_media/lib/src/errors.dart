import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What kind of failure a player reported (3.x's `PlayerErrorType`).
enum PlayerErrorType {
  /// The connection to the media failed (timeout, refused, DNS, TLS, 5xx).
  network,

  /// An unclassified native diagnostic.
  native,

  /// The decoder could not handle the stream.
  codec,

  /// The source could not be opened or read (401/403/404, bad data).
  source,

  /// The engine or its source open did not start.
  initialization,

  /// The player was disposed or the operation cancelled.
  lifecycle,

  /// The video output (surface, texture, GPU) failed.
  texture,

  /// Anything else.
  unknown,
}

/// A player failure with a stable machine-readable [code] for recovery
/// policy (3.x's `PlayerException`). The interface shows its own text and
/// never parses [message].
final class PlayerException implements Exception {
  /// Creates the exception.
  const new({required this.message, required this.type, this.code, this.error, this.stackTrace});

  /// Diagnostic text (English, not shown as is).
  final String message;

  /// The failure kind.
  final PlayerErrorType type;

  /// Stable diagnostic code (`transport`, `source_open`, `video_decoder_init`).
  final String? code;

  /// The underlying error, when there was one.
  final Object? error;

  /// Where [error] was thrown.
  final StackTrace? stackTrace;

  @override
  String toString() => '[${type.name}] $message';
}

/// Which decoder a native diagnostic is about.
enum NativeDiagnosticComponent {
  /// The video decoder (`vd`, `ffmpeg/video`).
  video,

  /// The audio decoder (`ad`, `ffmpeg/audio`).
  audio,

  /// Not known.
  either,
}

/// The meaning of one native player diagnostic line (3.x's
/// `NativePlayerErrorClassification`).
///
/// mpv forwards selected log lines as errors, but not every one ends
/// playback: a hardware decoder may reject a profile before mpv falls back,
/// and a corrupt live packet may be followed by a good keyframe.
/// [immediatelyTerminal] is reserved for failures that cannot recover
/// without changing the source or the player.
@immutable
final class NativeDiagnostic {
  /// Creates a classification.
  const new({
    required this.type,
    required this.code,
    required this.immediatelyTerminal,
    this.component = NativeDiagnosticComponent.either,
  });

  /// Classifies [message]; [nativePrefix] is mpv's log prefix (`vd`, `ad`,
  /// `ffmpeg/video`...). The order of checks is 3.x's: lifecycle, video
  /// output, decoder init, transport, source open, decoder runtime, source
  /// runtime, else an unclassified native diagnostic. URLs in [message] are
  /// ignored: their hosts, paths and queries carry arbitrary words (Huya's
  /// `codec=264`), and a line naming the stream it failed to open was taken
  /// for a decoder failure (G02.3).
  factory classify(String message, {String? nativePrefix}) {
    final value = message.trim().toLowerCase().replaceAll(_url, ' ');
    final prefix = nativePrefix?.trim().toLowerCase();
    final component = switch (prefix) {
      'ad' || 'ffmpeg/audio' => NativeDiagnosticComponent.audio,
      'vd' || 'ffmpeg/video' => NativeDiagnosticComponent.video,
      _ => NativeDiagnosticComponent.either,
    };
    if (_any(value, _lifecycle)) {
      return const NativeDiagnostic(type: PlayerErrorType.lifecycle, code: 'lifecycle', immediatelyTerminal: true);
    }
    if (_any(value, _videoOutput)) {
      return NativeDiagnostic._withComponent(PlayerErrorType.texture, 'video_output', component, terminal: true);
    }
    if (_any(value, _decoderInit)) {
      return NativeDiagnostic._withComponent(PlayerErrorType.codec, 'decoder_init', component, terminal: true);
    }
    if (_any(value, _transport) || _httpServerFailure.hasMatch(value)) {
      return const NativeDiagnostic(type: PlayerErrorType.network, code: 'transport', immediatelyTerminal: true);
    }
    if (_any(value, _sourceOpen)) {
      return const NativeDiagnostic(type: PlayerErrorType.source, code: 'source_open', immediatelyTerminal: true);
    }
    if (_any(value, _decoderRuntime)) {
      return NativeDiagnostic._withComponent(PlayerErrorType.codec, 'decoder_runtime', component, terminal: false);
    }
    if (_any(value, _sourceRuntime)) {
      return const NativeDiagnostic(type: PlayerErrorType.source, code: 'source_runtime', immediatelyTerminal: false);
    }
    return const NativeDiagnostic(type: PlayerErrorType.native, code: 'native_diagnostic', immediatelyTerminal: false);
  }

  new _withComponent(this.type, String code, this.component, {required bool terminal})
    : code = switch (component) {
        NativeDiagnosticComponent.audio => 'audio_$code',
        NativeDiagnosticComponent.video => 'video_$code',
        NativeDiagnosticComponent.either => code,
      },
      immediatelyTerminal = terminal;

  /// The failure kind.
  final PlayerErrorType type;

  /// Stable code; decoder codes are prefixed `audio_`/`video_` when the
  /// component is known.
  final String code;

  /// Whether the failure ends the current source at once.
  final bool immediatelyTerminal;

  /// The decoder the line is about.
  final NativeDiagnosticComponent component;

  static bool _any(String value, List<String> markers) => markers.any(value.contains);

  static final RegExp _url = RegExp(r'[a-z][a-z0-9+.-]*://\S*');

  static final RegExp _httpServerFailure = RegExp(r'(?:server returned|http error)\s+5\d\d(?:\D|$)');

  static const _lifecycle = [
    'player has been disposed',
    'player has been released',
    'operation was cancelled',
    'operation was canceled',
  ];

  static const _videoOutput = [
    'surface has been released',
    'failed to create surface',
    'failed to create texture',
    'texture is unavailable',
    'egl_bad',
    'vulkan error',
    'gpu context failed',
  ];

  static const _decoderInit = ['no decoder found', 'unsupported codec', 'codec is not supported'];

  static const _transport = [
    'connection timed out',
    'network timeout',
    'network is down',
    'network is unreachable',
    'host is unreachable',
    'connection refused',
    'connection reset',
    // The system tore the connection down (Android destroys the sockets of
    // an app whose network was taken away).
    'connection aborted',
    'software caused connection abort',
    'broken pipe',
    'no route to host',
    'failed to resolve',
    'could not resolve host',
    'unable to resolve host',
    'no address associated with hostname',
    'getaddrinfo failed',
    'nodename nor servname',
    'no such host is known',
    'temporary failure in name resolution',
    'name or service not known',
    'tls handshake',
    'ssl handshake',
    'certificate verify failed',
    'input/output error',
    'i/o error',
  ];

  static const _sourceOpen = [
    'server returned 401',
    'server returned 403',
    'server returned 404',
    'http error 401',
    'http error 403',
    'http error 404',
    'protocol not found',
    'unknown protocol',
    'no protocol handler',
    'failed to open input',
    'error opening input',
    'unable to open input',
    'invalid data found when processing input',
    'could not find codec parameters',
    'no streams found',
  ];

  static const _decoderRuntime = [
    'mediacodec',
    'decoder',
    'decode',
    'codec',
    'invalid nal',
    'non-existing pps',
    'missing reference picture',
    'corrupt decoded frame',
    'error while decoding',
  ];

  static const _sourceRuntime = [
    'demuxer',
    'failed to open',
    'error opening',
    'unable to open',
    'end of file',
    'unexpected eof',
  ];

  @override
  String toString() => 'NativeDiagnostic(${type.name}, $code${immediatelyTerminal ? ', terminal' : ''})';
}

/// What a failure to resolve or open a source means for recovery.
enum SourceFailureKind {
  /// Worth retrying on the same or the next line: transport trouble, a
  /// relay or upstream hiccup, an expired grant.
  transient,

  /// The platform said the stream cannot be played now (offline, login,
  /// region, removed): stop and explain, do not walk the lines.
  terminal,

  /// The open was cancelled by a newer request or by closing.
  cancelled,
}

/// Classifies a failure of resolving or opening a source (3.x mixed Dio,
/// platform and native failures in its recovery checks).
///
/// live_core's `SiteError`s that describe the stream or the account
/// (`StreamUnavailable`, `NeedsLogin`, `RegionBlocked`, `NotFound`) are
/// terminal; rate limits, risk control, network and API failures are
/// transient. live_net's cancelled `TransportFailure` is [SourceFailureKind.cancelled].
SourceFailureKind classifySourceFailure(Object error) => switch (error) {
  TransportFailure(reason: TransportReason.cancelled) ||
  PlayerException(type: PlayerErrorType.lifecycle) => SourceFailureKind.cancelled,
  StreamUnavailable() ||
  NeedsLogin() ||
  RegionBlocked() ||
  NotFound() ||
  UnsupportedLink() => SourceFailureKind.terminal,
  _ => SourceFailureKind.transient,
};

/// The [PlayerException.code] of the failure a session publishes when the
/// network is gone (G02.3): the interface says so and that playback comes
/// back by itself, which the session does once the network answers again.
const String networkLostCode = 'network_lost';

/// Whether [error] says nothing answered at all (G02.3): no connection,
/// TLS, a timeout, or a player failure of the network kind. A cancelled
/// request, a malformed answer and every refusal of the platform are
/// answers, not a missing network.
bool isNetworkFailure(Object error) => switch (error) {
  TransportFailure(reason: TransportReason.cancelled || TransportReason.protocol) => false,
  TransportFailure() || NetworkFailure() || TimeoutException() || SocketException() || TlsException() => true,
  PlayerException(type: PlayerErrorType.network) => true,
  _ => false,
};
