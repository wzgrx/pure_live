import 'dart:async';

import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';

/// Turns mpv's error-level log lines into confirmed source failures (the
/// diagnostic half of 3.x's `MediaKitAdapter`).
///
/// mpv reports recoverable packet and hardware-decoder trouble on the same
/// stream as fatal failures. So:
/// - only lines from the prefixes 3.x acted on count (`ffmpeg` only for
///   `tcp:` lines);
/// - [NativeDiagnostic.immediatelyTerminal] failures are reported at once;
/// - other failures wait [window]: progress of the same decoder (a frame, or
///   playing without buffering) cancels them;
/// - a line logged while a source opens is held until the open finishes and
///   dropped when the decoder it names already produced output;
/// - the same text is reported once per source within two seconds.
final class NativeDiagnosticGate {
  /// Creates a gate that reports to [onError].
  new({required this.onError, this.window = const Duration(milliseconds: 1200)});

  /// Receives confirmed failures.
  final void Function(PlayerException error) onError;

  /// How long a recoverable diagnostic waits for progress.
  final Duration window;

  static const _prefixes = {'file', 'vd', 'ad', 'ffmpeg/video', 'ffmpeg/audio', 'cplayer', 'stream'};

  bool _opening = false;
  bool _closed = false;
  bool _videoReady = false;
  bool _audioReady = false;
  bool _playing = false;
  bool _buffering = false;
  int _progress = 0;
  ({String text, String? prefix})? _held;
  Timer? _timer;
  PlayerException? _pending;
  NativeDiagnosticComponent _pendingComponent = NativeDiagnosticComponent.either;
  int _pendingProgress = 0;
  String? _lastText;
  DateTime? _lastAt;

  /// Whether mpv's [prefix] and [text] are worth classifying (3.x's
  /// `_isActionableNativeLog`).
  static bool isActionable(String prefix, String text) {
    final normalized = prefix.trim().toLowerCase();
    if (normalized == 'ffmpeg') return text.trimLeft().toLowerCase().startsWith('tcp:');
    return _prefixes.contains(normalized);
  }

  /// A new source starts opening; everything of the previous one is dropped.
  void beginOpen() {
    _cancelPending();
    _opening = true;
    _videoReady = false;
    _audioReady = false;
    _playing = false;
    _buffering = true;
    _progress = 0;
    _held = null;
    _lastText = null;
    _lastAt = null;
  }

  /// The open finished; a held line is processed now unless its decoder
  /// already produced output.
  void finishOpen() {
    _opening = false;
    final held = _held;
    _held = null;
    if (held != null && !_ready(_componentOf(held.prefix))) _process(held.text, held.prefix);
  }

  /// One mpv log line.
  void log(String prefix, String level, String text) {
    if (_closed || level != 'error' || !isActionable(prefix, text)) return;
    if (_opening) {
      _held = (text: text, prefix: prefix);
      return;
    }
    _process(text, prefix);
  }

  /// A decoded video frame (or video parameters).
  void videoFrame() {
    _videoReady = true;
    _progress++;
    _cancelRecovered(NativeDiagnosticComponent.video);
  }

  /// Decoded audio (audio parameters).
  void audioFrame() {
    _audioReady = true;
    _progress++;
    _cancelRecovered(NativeDiagnosticComponent.audio);
  }

  /// mpv's playing and buffering flags; playing without buffering is
  /// progress of whatever is shown.
  void playback({required bool playing, required bool buffering, bool audioOnly = false}) {
    _playing = playing;
    _buffering = buffering;
    if (playing && !buffering) {
      _progress++;
      _cancelRecovered(audioOnly ? NativeDiagnosticComponent.audio : NativeDiagnosticComponent.video);
    }
  }

  /// Stops reporting.
  void close() {
    _closed = true;
    _cancelPending();
  }

  void _process(String text, String? prefix) {
    final classification = NativeDiagnostic.classify(text, nativePrefix: prefix);
    final error = PlayerException(message: text, type: classification.type, code: classification.code);
    if (classification.immediatelyTerminal) {
      _report(error);
      return;
    }
    if (_timer != null) return;
    _pending = error;
    _pendingComponent = classification.component;
    _pendingProgress = _progress;
    _timer = Timer(window, () {
      _timer = null;
      final pending = _pending;
      _pending = null;
      if (pending == null || _closed) return;
      final recovered = _progress > _pendingProgress && _playing && (_ready(_pendingComponent) || !_buffering);
      if (recovered || (_playing && !_buffering)) return;
      _report(pending);
    });
  }

  void _report(PlayerException error) {
    if (_closed) return;
    final now = clock.now();
    final last = _lastAt;
    if (_lastText == error.message && last != null && now.difference(last) < const Duration(seconds: 2)) return;
    _lastText = error.message;
    _lastAt = now;
    onError(error);
  }

  bool _ready(NativeDiagnosticComponent component) => switch (component) {
    NativeDiagnosticComponent.video => _videoReady,
    NativeDiagnosticComponent.audio => _audioReady,
    NativeDiagnosticComponent.either => _videoReady || _audioReady,
  };

  static NativeDiagnosticComponent _componentOf(String? prefix) => switch (prefix?.trim().toLowerCase()) {
    'ad' || 'ffmpeg/audio' => NativeDiagnosticComponent.audio,
    'vd' || 'ffmpeg/video' => NativeDiagnosticComponent.video,
    _ => NativeDiagnosticComponent.either,
  };

  void _cancelRecovered(NativeDiagnosticComponent progressed) {
    if (_timer == null) return;
    if (_pendingComponent != NativeDiagnosticComponent.either && _pendingComponent != progressed) return;
    _cancelPending();
  }

  void _cancelPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _pendingComponent = NativeDiagnosticComponent.either;
  }
}
