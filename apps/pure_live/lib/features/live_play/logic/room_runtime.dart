import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// Everything a playing room owns: its logic, its one player, the stream's
/// drops, the background policy and the orientation choice. The room page
/// creates it; the in-app floating window ([FloatingRoom]) takes it over when
/// the page closes and gives it back when the same room opens again, so the
/// player and the danmaku are never built twice (UI_PLAN §9.3, U.2j).
final class RoomRuntime {
  /// Bundles the parts of one room.
  new({
    required this.controller,
    required this.session,
    required this.reconnect,
    required this.background,
    required this.orientation,
    this.playerConfig,
  });

  /// The room's logic.
  final LiveRoomController controller;

  /// The player.
  final PlaybackSession session;

  /// The stream's drops.
  final ReconnectWatch reconnect;

  /// Pausing in the background, the locks and the media notification.
  final RoomBackgroundPolicy background;

  /// The room's orientation choice.
  final RoomOrientationChoice orientation;

  /// How [session]'s player was configured (compared with `==`): a player
  /// kept for the next room fits only a room configured the same way
  /// (`PlayerStandby`, F.1d).
  final Object? playerConfig;

  bool _disposed = false;

  /// Whether [dispose] ran.
  bool get disposed => _disposed;

  /// Whether this plays [room].
  bool holds(LiveRoom room) =>
      controller.room.platform.trim().toLowerCase() == room.platform.trim().toLowerCase() &&
      controller.room.roomId == room.roomId;

  /// Stops the room and releases the player; with [keep] the player is only
  /// stopped and handed to it for the next room (3.x "播放器强制销毁" off,
  /// F.1d).
  Future<void> dispose({void Function(PlaybackSession session)? keep}) async {
    if (_disposed) return;
    _disposed = true;
    background.dispose();
    reconnect.dispose();
    orientation.dispose();
    controller.dispose();
    if (keep == null) {
      await session.dispose();
      return;
    }
    // Handed over only once stopped: a stop still running would stop what
    // the next room opens.
    await session.stop();
    keep(session);
  }
}

/// The room playing in the in-app floating window (3.x
/// `PlayerManager.showAppFloating` and the floating session hand-off of
/// `AppNavigator.toLiveRoomDetail`). One at a time; the app's
/// `FloatingRoomLayer` shows it.
///
/// - The room page hands its [RoomRuntime] over when it closes ([show]).
/// - Opening a room claims it: the same room plays on, any other closes it
///   ([claim]); opening multi-view closes it.
/// - Its ✕ stops it ([close]).
final class FloatingRoom extends ChangeNotifier {
  new _();

  /// The app's floating window.
  static final FloatingRoom instance = FloatingRoom._();

  RoomRuntime? _runtime;
  int _layers = 0;
  bool _routesAttached = false;

  /// The room in the floating window, or null.
  RoomRuntime? get runtime => _runtime;

  /// Whether a layer can show a floating window (the app's; tests and the
  /// TV interface have none, and a runtime nobody shows is closed at once).
  bool get canShow => _layers > 0;

  /// A layer that shows the floating window appeared or went away.
  void attachLayer() {
    _layers++;
    _attachRoutes();
  }

  /// See [attachLayer].
  void detachLayer() {
    _layers = (_layers - 1).clamp(0, 1 << 20);
    if (_layers == 0) unawaited(close());
  }

  void _attachRoutes() {
    if (_routesAttached) return;
    _routesAttached = true;
    liveRouteObserver.addListener((event) {
      // 3.x closed the floating window when multi-view opened
      // (`multiview_controller.dart:281-282`).
      if (event.kind == RouteEventKind.push && event.name == RoutePath.kMultiview) unawaited(close());
    });
  }

  /// Plays [runtime] in the floating window (the room page closed); a room
  /// already floating stops. Without a layer it stops at once.
  void show(RoomRuntime runtime) {
    if (identical(runtime, _runtime)) return;
    if (!canShow) {
      unawaited(_release(runtime));
      return;
    }
    final previous = _runtime;
    _runtime = runtime;
    notifyListeners();
    if (previous != null) unawaited(_release(previous));
  }

  /// The floating runtime when it plays [room] (it leaves the floating
  /// window for the room page); any other floating room stops. Null when
  /// nothing of [room] floats.
  RoomRuntime? claim(LiveRoom room) {
    final runtime = _runtime;
    if (runtime == null) return null;
    _runtime = null;
    notifyListeners();
    if (runtime.holds(room) && !runtime.disposed) return runtime;
    unawaited(_release(runtime));
    return null;
  }

  /// Stops the floating room (its ✕, multi-view).
  Future<void> close() async {
    final runtime = _runtime;
    if (runtime == null) return;
    _runtime = null;
    notifyListeners();
    await _release(runtime);
  }

  /// Releases [runtime] once the floating window's picture is gone: the
  /// layer rebuilds on the next frame (or after a second when no frame comes,
  /// such as in the background), then the player closes.
  Future<void> _release(RoomRuntime runtime) async {
    final frame = Completer<void>();
    final timer = Timer(const Duration(seconds: 1), () {
      if (!frame.isCompleted) frame.complete();
    });
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!frame.isCompleted) frame.complete();
      })
      ..scheduleFrame();
    await frame.future;
    timer.cancel();
    await runtime.dispose();
  }

  /// Forgets everything (tests).
  @visibleForTesting
  Future<void> reset() async {
    await close();
    _layers = 0;
  }
}
