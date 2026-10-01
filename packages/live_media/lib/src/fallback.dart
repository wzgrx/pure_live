import 'package:live_core/live_core.dart';
import 'package:live_media/src/errors.dart';

/// The identity of [line] for fallback bookkeeping: its CDN code when the
/// platform gives one (stable across renewals), else its URL.
String lineKey(LivePlayLine line) => line.lineId ?? line.url;

/// Walks the lines of one quality after failures (3.x's
/// `LineFallbackManager`).
///
/// 3.x keyed failures by URL and kept a cursor into the list it was last
/// given: a renewed URL of a failed line counted as untried, and a shorter
/// list after a refresh left the cursor past its end (`RangeError`). Here
/// failures are keyed by [lineKey] and the cursor is the last line handed
/// out, looked up again in each list.
final class LineFallback {
  final Set<String> _failed = {};
  String? _last;

  /// The next line after the last one handed out that has not failed,
  /// wrapping around; null when every line failed or [lines] is empty.
  LivePlayLine? next(List<LivePlayLine> lines) {
    if (lines.isEmpty) return null;
    final last = _last;
    final at = last == null ? -1 : lines.indexWhere((line) => lineKey(line) == last);
    for (var step = 1; step <= lines.length; step++) {
      final line = lines[(at + step) % lines.length];
      if (!_failed.contains(lineKey(line))) {
        _last = lineKey(line);
        return line;
      }
    }
    return null;
  }

  /// Records [line] as the one playing (the cursor) without changing its
  /// failure state.
  void select(LivePlayLine line) => _last = lineKey(line);

  /// Records a failure of [line].
  void markFailed(LivePlayLine line) => _failed.add(lineKey(line));

  /// Records that [line] played.
  void markSuccess(LivePlayLine line) => _failed.remove(lineKey(line));

  /// Whether any of [lines] has not failed.
  bool hasAvailable(List<LivePlayLine> lines) => lines.any((line) => !_failed.contains(lineKey(line)));

  /// Forgets failures and the cursor (a new room or quality).
  void reset() {
    _failed.clear();
    _last = null;
  }
}

/// The decoding modes recovery can switch between. v4 plays everything with
/// mpv, so 3.x's engine ladder (media_kit → fijk/exo → fvp) becomes a
/// decoder ladder inside the one engine.
enum DecoderMode {
  /// Hardware decoding (mpv `hwdec=auto-safe`).
  hardware,

  /// Software decoding (mpv `hwdec=no`).
  software,
}

/// Picks the decoder after a failure (3.x's `EngineFallbackManager`).
///
/// Same rules as 3.x: only codec, native, texture, initialization and
/// source failures fall back; a mode is given up after [maxRetryCount]
/// failures (default 1: adapters report confirmed terminal failures once);
/// when every mode has failed the error is rethrown and the ladder resets.
final class DecoderFallback {
  /// Creates the ladder starting at [preferred]; [supported] lists the
  /// modes this device may use, in order of preference.
  new({this.preferred = DecoderMode.hardware, this.supported = DecoderMode.values, this.maxRetryCount = 1});

  /// The first mode.
  final DecoderMode preferred;

  /// Usable modes.
  final List<DecoderMode> supported;

  /// Failures of one mode before it is given up.
  final int maxRetryCount;

  final Map<DecoderMode, int> _retries = {};
  final Set<DecoderMode> _failed = {};

  late final List<DecoderMode> _priority = {preferred, ...DecoderMode.values}.where(supported.contains).toList();

  /// Whether [error] is worth another decoder (3.x's `shouldFallback`).
  bool shouldFallback(PlayerException error) => switch (error.type) {
    PlayerErrorType.codec ||
    PlayerErrorType.native ||
    PlayerErrorType.texture ||
    PlayerErrorType.initialization ||
    PlayerErrorType.source => true,
    _ => false,
  };

  /// The mode to retry with after [current] failed with [error]: [current]
  /// again while it has retries left, else the next untried mode. Throws
  /// [error] (and resets) when none is left; with one supported mode that
  /// mode is returned, as 3.x did with one engine.
  DecoderMode fallback(DecoderMode current, PlayerException error) {
    if (_priority.length <= 1) return _priority.isEmpty ? preferred : _priority.single;
    final retries = (_retries[current] ?? 0) + 1;
    _retries[current] = retries;
    if (retries < maxRetryCount.clamp(1, 100)) return current;
    _failed.add(current);
    for (final mode in _priority) {
      if (!_failed.contains(mode)) {
        _retries[mode] = 0;
        return mode;
      }
    }
    resetAll();
    throw error;
  }

  /// Forgets the failures of [mode] (it played).
  void reset(DecoderMode mode) {
    _retries[mode] = 0;
    _failed.remove(mode);
  }

  /// Forgets everything (a new room).
  void resetAll() {
    _retries.clear();
    _failed.clear();
  }
}
