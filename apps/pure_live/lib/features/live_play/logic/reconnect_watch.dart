import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_player/live_player.dart';

/// Whether a stream that failed is being brought back, and which attempt
/// (the "正在重连（第 N 次）" message, U.2a E3).
///
/// The playback session says so itself ([PlaybackState.recovery]): only its
/// recovery (a refreshed address, the next line, a new engine, a retry
/// round) is a reconnection, and so is a live stream that stopped moving
/// for `SessionTimings.stallNotice` (G02.3: the session judges it by its
/// position, not by the engine's flags). A stream that buffers without
/// having failed (a slow start, a short stall, a resume after a pause) and
/// the user's own reopenings (another quality or line, a refresh) are not;
/// the picture shows a spinner for those (B02: guessing from "playing, then
/// buffering" called each of them a drop).
final class ReconnectWatch extends ChangeNotifier {
  /// Watches [states] (the session's).
  new(Stream<PlaybackState> states) {
    _subscription = states.listen(update);
  }

  late final StreamSubscription<PlaybackState> _subscription;
  bool _reconnecting = false;
  int _attempts = 0;

  /// A failed stream is being brought back.
  bool get reconnecting => _reconnecting;

  /// The attempt, counting from 1, while [reconnecting]; 0 otherwise.
  int get attempts => _attempts;

  /// Takes the session's [state].
  @visibleForTesting
  void update(PlaybackState state) {
    final reconnecting =
        state.recovering && (state.status == PlaybackStatus.buffering || state.status == PlaybackStatus.opening);
    final attempts = reconnecting ? state.recovery : 0;
    if (reconnecting == _reconnecting && attempts == _attempts) return;
    _reconnecting = reconnecting;
    _attempts = attempts;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
