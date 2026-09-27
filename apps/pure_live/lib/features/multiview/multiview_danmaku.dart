import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart' show DanmakuFilterSettings;
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';

/// The chat of the multiview page (spec/modules/multiview.md §9): at most one
/// connection, to the selected cell's room (DM-2). It reuses the room's
/// [RoomDanmaku], so the filter chain is the single-room one (DM-4,
/// INV-MULTI-10); a failed connection only shows in [RoomDanmaku.connection]
/// and never touches playback (DM-5).
final class MultiviewDanmaku {
  /// Opens connections through the source function, read when a connection
  /// starts.
  new({required this._source});

  final DanmakuSource Function() _source;
  RoomDanmaku? _current;
  PlaybackSession? _session;
  StreamSubscription<PlaybackState>? _states;
  OnVideoDanmaku? _overlay;
  var _disposed = false;

  /// The open chat, if any.
  RoomDanmaku? get current => _current;

  /// Follows the target cell: its [room] and [session], or nothing. The same
  /// room keeps its connection; another room closes the old one first and
  /// then connects (DM-2). [filters] is read only for a new connection.
  void follow({
    required RoomDetail? room,
    required PlaybackSession? session,
    required DanmakuFilterSettings Function() filters,
  }) {
    if (_disposed) return;
    if (room == null || session == null) {
      _stop();
      return;
    }
    if (_current?.room.ref != room.ref) {
      _stop();
      _current = RoomDanmaku(source: _source(), room: room, filters: filters(), enabled: true, overlay: _overlay);
    }
    _bind(session);
  }

  /// REN-7: the layer runs only while the target cell plays.
  void _bind(PlaybackSession session) {
    if (identical(session, _session)) return;
    unawaited(_states?.cancel());
    _session = session;
    final danmaku = _current!..setPlaying(playing: session.state.phase == PlaybackPhase.playing);
    _states = session.states.listen((state) => danmaku.setPlaying(playing: state.phase == PlaybackPhase.playing));
  }

  /// Keeps the connection while the target cell reopens the same room: the
  /// layer freezes until the new session plays.
  void hold() {
    unawaited(_states?.cancel());
    _states = null;
    _session = null;
    _current?.setPlaying(playing: false);
  }

  void _stop() {
    hold();
    final old = _current;
    _current = null;
    if (old != null) {
      old.overlay = null;
      unawaited(old.dispose());
    }
  }

  /// The on-video layer of the page (null detaches it).
  OnVideoDanmaku? get overlay => _overlay;

  set overlay(OnVideoDanmaku? value) {
    _overlay = value;
    _current?.overlay = value;
  }

  /// New filters for the open connection (FLT-6).
  void setFilters(DanmakuFilterSettings filters) => _current?.setFilters(filters);

  /// Disconnects; nothing connects afterwards.
  void dispose() {
    _stop();
    _overlay = null;
    _disposed = true;
  }
}
