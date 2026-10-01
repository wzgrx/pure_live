import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';

/// The player a closed room leaves for the next one (3.x `PlayerManager`
/// with "播放器强制销毁" off: `softStop` and the idle release, F.1d).
///
/// The room page hands its stopped session over when it closes without the
/// in-app floating window ([keep]); the next room page takes it ([take])
/// when its player would be configured the same way, so the engine is not
/// built again. The session releases its engine by itself after
/// `SessionTimings.idleRelease` (45 s); this only keeps the session object.
/// One at a time: keeping another releases the one kept before.
final class PlayerStandby {
  PlaybackSession? _session;
  Object? _config;
  bool _disposed = false;

  /// Whether a session waits for the next room.
  bool get holding => _session != null;

  /// Keeps [session] (stopped) for the next room whose player is configured
  /// as [config] (compared with `==`).
  void keep(PlaybackSession session, {required Object? config}) {
    if (_disposed) {
      unawaited(session.dispose());
      return;
    }
    final previous = _session;
    _session = session;
    _config = config;
    if (previous != null && !identical(previous, session)) unawaited(previous.dispose());
  }

  /// The kept session when its player was configured as [config]; it leaves
  /// the standby. A session configured otherwise is released. Null when
  /// none fits.
  PlaybackSession? take({required Object? config}) {
    final session = _session;
    if (session == null) return null;
    _session = null;
    if (_config == config) return session;
    unawaited(session.dispose());
    return null;
  }

  /// Releases the kept session; later ones are released at once.
  Future<void> dispose() async {
    _disposed = true;
    final session = _session;
    _session = null;
    await session?.dispose();
  }
}

/// The app's [PlayerStandby] (one per provider scope, so tests never share
/// one).
final Provider<PlayerStandby> playerStandbyProvider = Provider((ref) {
  final standby = PlayerStandby();
  ref.onDispose(() => unawaited(standby.dispose()));
  return standby;
});
