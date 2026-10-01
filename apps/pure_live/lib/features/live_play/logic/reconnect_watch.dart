import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_player/live_player.dart';

/// Whether a stream that was playing has dropped and is being brought back,
/// and how many times in a row (the "正在重连（第 N 次）" message, U.2a E3).
///
/// The playback session recovers by itself (refreshed address, next line,
/// bounded retry rounds) but keeps its attempt count private: its state only
/// says "buffering". So this counts the drops it sees: a playing stream
/// that turns to buffering or opening without the user having asked for a
/// new stream ([expectReopen]). The count starts again once the stream has
/// played for [settle] (the session's own budget reset).
final class ReconnectWatch extends ChangeNotifier {
  /// Watches [states] (the session's).
  new(Stream<PlaybackState> states, {DateTime Function()? now, this.settle = const Duration(seconds: 30)})
    : _now = now ?? DateTime.now {
    _subscription = states.listen(update);
  }

  /// Sustained playback after which a new drop counts as the first again.
  final Duration settle;

  final DateTime Function() _now;
  late final StreamSubscription<PlaybackState> _subscription;
  DateTime? _playingSince;
  bool _expected = false;
  bool _reconnecting = false;
  int _attempts = 0;

  /// A dropped stream is being brought back.
  bool get reconnecting => _reconnecting;

  /// Drops in a row, counting the current one.
  int get attempts => _attempts;

  /// The next reopening is the user's doing (another quality or line, a
  /// refresh), not a drop.
  void expectReopen() => _expected = true;

  /// Takes the session's [state].
  @visibleForTesting
  void update(PlaybackState state) {
    final wasReconnecting = _reconnecting;
    switch (state.status) {
      case PlaybackStatus.playing:
        final now = _now();
        if (_reconnecting || _playingSince == null) _playingSince = now;
        _reconnecting = false;
        _expected = false;
      case PlaybackStatus.buffering || PlaybackStatus.opening:
        final since = _playingSince;
        if (since != null && !_reconnecting && !_expected) {
          if (_now().difference(since) >= settle) _attempts = 0;
          _attempts++;
          _reconnecting = true;
        }
        if (_expected) _playingSince = null;
      case PlaybackStatus.paused || PlaybackStatus.completed:
        _reconnecting = false;
      case PlaybackStatus.idle || PlaybackStatus.stopped || PlaybackStatus.error:
        _reconnecting = false;
        _playingSince = null;
        _expected = false;
        _attempts = 0;
    }
    if (wasReconnecting != _reconnecting) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
