import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';

/// Lowers the quality of a room whose playback keeps stalling (F-NEW-10).
///
/// A stall is playing → stalled or recovering with a picture already shown
/// (a rebuffer, not the first load). [threshold] stalls within [window] ask
/// for the next lower quality than the one playing; then the count starts
/// over. It stops for the room once the user picked a quality ([picked]).
final class StallWatch {
  /// Watches with [threshold] stalls per [window].
  new({this.window = const Duration(seconds: 60), this.threshold = 3, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The time the stalls are counted in.
  final Duration window;

  /// Stalls within [window] that lower the quality.
  final int threshold;

  final DateTime Function() _now;
  final _stalls = <DateTime>[];
  bool _manual = false;

  /// Starts over for a new room.
  void reset() {
    _stalls.clear();
    _manual = false;
  }

  /// The user picked a quality: no more automatic changes in this room.
  void picked() => _manual = true;

  /// Takes the state change [previous] → [next]; returns the quality to
  /// switch to, or null.
  Quality? observe(PlaybackState previous, PlaybackState next) {
    if (_manual) return null;
    const stalling = {PlaybackPhase.stalled, PlaybackPhase.recovering};
    final stalled = previous.phase == PlaybackPhase.playing && stalling.contains(next.phase) && next.hasPicture;
    if (!stalled) return null;
    final now = _now();
    _stalls
      ..add(now)
      ..removeWhere((at) => now.difference(at) > window);
    if (_stalls.length < threshold) return null;
    _stalls.clear();
    final current = next.quality;
    final offered = next.qualities;
    final index = current == null ? -1 : offered.indexOf(current);
    if (index < 0 || index + 1 >= offered.length) return null;
    return offered[index + 1];
  }
}
