import 'dart:async';

import 'package:clock/clock.dart';
import 'package:live_media/src/session/playback_state.dart';

/// Decides the picture orientation from decoded sizes (§8, GEO-1 to GEO-3).
///
/// Size events merge in fixed 120 ms windows (not a trailing debounce, so a
/// steady stream of events cannot starve the decision). A candidate commits
/// after 3 consecutive window samples or 500 ms of stability; the stability
/// timer rounds up to the millisecond and adds 1 ms, since firing early
/// rejects a lone sample. Hysteresis keeps a committed orientation while the
/// ratio stays below 0.96 (portrait) or above 1.04 (landscape).
final class GeometryTracker {
  /// Creates a tracker that reports commits to [_onChanged].
  new(
    this._onChanged, {
    this.window = const Duration(milliseconds: 120),
    this.stableFor = const Duration(milliseconds: 500),
    this.samplesToCommit = 3,
  });

  final void Function(VideoGeometry geometry) _onChanged;

  /// Merge window.
  final Duration window;

  /// Stability that commits a candidate.
  final Duration stableFor;

  /// Consecutive samples that commit a candidate.
  final int samplesToCommit;

  VideoGeometry _committed = VideoGeometry.unknown;
  Timer? _windowTimer;
  Timer? _stableTimer;
  ({int width, int height})? _latest;
  VideoGeometry? _candidate;
  var _candidateSamples = 0;
  DateTime? _candidateSince;

  /// The committed geometry.
  VideoGeometry get geometry => _committed;

  /// Orientation for [ratio] given the [current] one (GEO-3).
  static VideoOrientation classify(double ratio, VideoOrientation current) {
    if (current == VideoOrientation.portrait && ratio < 0.96) return VideoOrientation.portrait;
    if (current == VideoOrientation.landscape && ratio > 1.04) return VideoOrientation.landscape;
    if (ratio <= 0.90) return VideoOrientation.portrait;
    if (ratio >= 1.10) return VideoOrientation.landscape;
    return VideoOrientation.square;
  }

  /// Starts over for a new source generation (GEO-1).
  void reset() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _latest = null;
    _candidate = null;
    _candidateSamples = 0;
    _candidateSince = null;
    if (_committed != VideoGeometry.unknown) {
      _committed = VideoGeometry.unknown;
      _onChanged(_committed);
    }
  }

  /// A decoded size; null or zero sizes are ignored (EVT-8).
  void add(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) return;
    _latest = (width: width, height: height);
    _windowTimer ??= Timer(window, _closeWindow);
  }

  void _closeWindow() {
    _windowTimer = null;
    final sample = _latest;
    if (sample == null) return;
    final orientation = classify(sample.width / sample.height, _committed.orientation);
    final geometry = VideoGeometry(orientation: orientation, width: sample.width, height: sample.height);
    if (orientation == _committed.orientation) {
      _clearCandidate();
      if (geometry != _committed) {
        _committed = geometry;
        _onChanged(geometry);
      }
      return;
    }
    if (_candidate?.orientation == orientation) {
      _candidate = geometry;
      _candidateSamples++;
    } else {
      _candidate = geometry;
      _candidateSamples = 1;
      _candidateSince = clock.now();
      _stableTimer?.cancel();
      final wait = stableFor.inMicroseconds;
      _stableTimer = Timer(Duration(milliseconds: (wait + 999) ~/ 1000 + 1), _commitStable);
    }
    if (_candidateSamples >= samplesToCommit) _commit();
  }

  void _commitStable() {
    _stableTimer = null;
    final since = _candidateSince;
    if (_candidate == null || since == null) return;
    if (clock.now().difference(since) >= stableFor) _commit();
  }

  void _commit() {
    final candidate = _candidate;
    _clearCandidate();
    if (candidate == null) return;
    _committed = candidate;
    _onChanged(candidate);
  }

  void _clearCandidate() {
    _candidate = null;
    _candidateSamples = 0;
    _candidateSince = null;
    _stableTimer?.cancel();
    _stableTimer = null;
  }

  /// Stops the timers.
  void dispose() {
    _windowTimer?.cancel();
    _stableTimer?.cancel();
  }
}
