import 'package:meta/meta.dart';

/// mpv log prefixes whose error-level lines may describe a playback failure (EVT-7).
const _actionablePrefixes = {'file', 'vd', 'ad', 'ffmpeg/video', 'ffmpeg/audio', 'cplayer', 'stream'};

/// Whether an error-level mpv log line enters classification (EVT-7): the
/// prefixes above, or `ffmpeg` lines that start with `tcp:`.
bool isActionableDiagnostic(String prefix, String text) {
  final normalized = prefix.trim().toLowerCase();
  if (normalized == 'ffmpeg') return text.trimLeft().toLowerCase().startsWith('tcp:');
  return _actionablePrefixes.contains(normalized);
}

/// The class of an engine diagnostic (EVT-12).
enum DiagnosticKind {
  /// The engine or its surface was released or cancelled.
  lifecycle(terminal: true),

  /// The video output (surface, texture, GPU context) failed.
  videoOutput(terminal: true),

  /// No decoder for the stream.
  decoderInit(terminal: true),

  /// The connection failed: DNS, TCP, TLS, 5xx, I/O.
  transport(terminal: true),

  /// The source could not be opened: 4xx, unknown format, no streams.
  sourceOpen(terminal: true),

  /// A decoder reported a broken packet or frame while running.
  decoderRuntime(terminal: false),

  /// The demuxer or stream reported a problem while running.
  sourceRuntime(terminal: false),

  /// Anything else.
  other(terminal: false);

  new({required this.terminal});

  /// Immediately final for the current source; otherwise the session watches
  /// 1.2 s for recovery before acting (EVT-7).
  final bool terminal;
}

/// Which part of the media a diagnostic is about.
enum DiagnosticComponent {
  /// Video decoding or output.
  video,

  /// Audio decoding or output.
  audio,

  /// Not specific.
  either,
}

/// A classified diagnostic.
@immutable
final class Diagnosis {
  /// Creates a diagnosis.
  const new(this.kind, this.component);

  /// Class.
  final DiagnosticKind kind;

  /// Affected component.
  final DiagnosticComponent component;

  /// A stable code for logs and deduplication (`video_decoderRuntime`).
  String get code => component == DiagnosticComponent.either ? kind.name : '${component.name}_${kind.name}';

  @override
  bool operator ==(Object other) => other is Diagnosis && other.kind == kind && other.component == component;

  @override
  int get hashCode => Object.hash(kind, component);

  @override
  String toString() => 'Diagnosis($code)';
}

const _lifecycle = [
  'player has been disposed',
  'player has been released',
  'operation was cancelled',
  'operation was canceled',
];

const _videoOutput = [
  'surface has been released',
  'failed to create surface',
  'failed to create texture',
  'texture is unavailable',
  'egl_bad',
  'vulkan error',
  'gpu context failed',
  'failed to initialize a video output',
  'error initializing vo',
];

const _decoderInit = ['no decoder found', 'unsupported codec', 'codec is not supported', 'could not open codec'];

const _transport = [
  'connection timed out',
  'network timeout',
  'network is down',
  'network is unreachable',
  'host is unreachable',
  'connection refused',
  'connection reset',
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

const _sourceOpen = [
  'server returned 4',
  'http error 4',
  'protocol not found',
  'unknown protocol',
  'no protocol handler',
  'failed to open input',
  'error opening input',
  'unable to open input',
  'failed to recognize file format',
  'invalid data found when processing input',
  'could not find codec parameters',
  'no streams found',
];

const _decoderRuntime = [
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

const _sourceRuntime = ['demuxer', 'error opening', 'unable to open', 'end of file', 'unexpected eof'];

final _serverError = RegExp(r'(?:server returned|http error)\s+5\d\d(?:\D|$)');

/// mpv's own "Failed to open `path`." from the player core: the open failed (EVT-17).
final _coreOpenFailure = RegExp(r'^failed to open .+\.$');

/// Classifies one engine diagnostic (EVT-12); [prefix] is the mpv log prefix.
Diagnosis classifyDiagnostic(String message, {String? prefix}) {
  final text = message.trim().toLowerCase();
  final source = prefix?.trim().toLowerCase();
  final component = switch (source) {
    'ad' || 'ffmpeg/audio' => DiagnosticComponent.audio,
    'vd' || 'ffmpeg/video' => DiagnosticComponent.video,
    _ => DiagnosticComponent.either,
  };
  bool any(List<String> markers) => markers.any(text.contains);

  if (any(_lifecycle)) return const Diagnosis(DiagnosticKind.lifecycle, DiagnosticComponent.either);
  if (any(_videoOutput)) return Diagnosis(DiagnosticKind.videoOutput, component);
  if (any(_decoderInit)) return Diagnosis(DiagnosticKind.decoderInit, component);
  if (any(_transport) || _serverError.hasMatch(text)) {
    return const Diagnosis(DiagnosticKind.transport, DiagnosticComponent.either);
  }
  if (any(_sourceOpen) || ((source == null || source == 'cplayer') && _coreOpenFailure.hasMatch(text))) {
    return const Diagnosis(DiagnosticKind.sourceOpen, DiagnosticComponent.either);
  }
  if (any(_decoderRuntime)) return Diagnosis(DiagnosticKind.decoderRuntime, component);
  if (any(_sourceRuntime) || text.startsWith('failed to open')) {
    return const Diagnosis(DiagnosticKind.sourceRuntime, DiagnosticComponent.either);
  }
  return Diagnosis(DiagnosticKind.other, component);
}
