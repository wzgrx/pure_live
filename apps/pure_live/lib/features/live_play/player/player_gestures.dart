import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/player/room_swipe.dart';

/// The icon of a gesture's [level] (3.x `BrightnessVolumnDargArea`: none,
/// under half, half and more).
IconData gestureLevelIcon(GestureLevel gesture, double level) => switch (gesture) {
  GestureLevel.volume =>
    level <= 0
        ? AppIcons.volumeMute
        : level < 0.5
        ? AppIcons.volumeDown
        : AppIcons.volumeUp,
  GestureLevel.brightness =>
    level <= 0
        ? AppIcons.brightnessLow
        : level < 0.5
        ? AppIcons.brightnessMedium
        : AppIcons.brightnessHigh,
};

/// What a gesture changes.
enum GestureLevel {
  /// The volume (the phone's media volume, else the player's).
  volume,

  /// The window's brightness (phones).
  brightness,
}

/// Volume and brightness gestures over the picture (3.x `VideoController`
/// drag handling and `volume_control.dart`): on phones a vertical drag on
/// the right half changes the media volume and on the left half the
/// brightness; with a mouse the wheel changes the player's volume, kept as
/// the room's. A level bar shows while it changes. With a [swipe] (the
/// portrait fullscreen opened from a list, U.2b2) the picture is in thirds:
/// brightness on the left, the room on the middle, volume on the right.
class PlayerGestureLayer extends StatefulWidget {
  /// Wraps [child].
  const new({
    required this.controller,
    required this.child,
    this.enabled = true,
    this.onSwipeUp,
    this.swipe,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The picture and its tap handling.
  final Widget child;

  /// Off while the controls are locked.
  final bool enabled;

  /// The portrait fullscreen: an upward swipe from the lowest
  /// [portraitRestoreZone] brings the panel back (3.x
  /// `BrightnessVolumnDargArea._onVerticalDragStart`).
  final VoidCallback? onSwipeUp;

  /// The swipe between rooms; null without one.
  final RoomSwipeController? swipe;

  @override
  State<PlayerGestureLayer> createState() => PlayerGestureLayerState();
}

/// The state of [PlayerGestureLayer]; [nudgeVolume] serves the keyboard.
class PlayerGestureLayerState extends State<PlayerGestureLayer> {
  GestureLevel? _showing;
  double _level = 0;
  Timer? _hide;
  Timer? _save;
  GestureLevel? _dragging;
  double? _restoring;

  /// The level a drag starts from is being read (the system's volume or
  /// brightness): moves wait for it, so the first one never starts from 0.
  bool _reading = false;

  /// A drag in the middle third moves between rooms (U.2b2).
  bool _switching = false;

  /// Where the finger went down, down the screen (A07.15): the drag starts
  /// only after the finger has moved, by then out of the system's edge.
  double? _downY;

  /// The frame callback that tells the system the level a drag set, or
  /// null (research 2026-10-02 S9: a touch screen sampling at 240 or 480 Hz
  /// moves several times a frame; the system hears the latest once).
  int? _sending;

  /// What the drag set and the system has not heard yet.
  GestureLevel? _unsent;

  bool get _systemVolume => DeviceControls.available;

  @override
  void dispose() {
    if (_sending case final id?) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    if (_unsent case final kind?) unawaited(_send(kind, _level));
    _hide?.cancel();
    if (_save?.isActive ?? false) {
      _save!.cancel();
      unawaited(widget.controller.saveVolume());
    }
    super.dispose();
  }

  void _show(GestureLevel kind, double level) {
    _hide?.cancel();
    setState(() {
      _showing = kind;
      _level = level.clamp(0.0, 1.0);
    });
    _hide = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showing = null);
    });
  }

  Future<double> _current(GestureLevel kind) async => switch (kind) {
    GestureLevel.volume when _systemVolume => await DeviceControls.volume() ?? widget.controller.volume,
    GestureLevel.volume => widget.controller.volume,
    GestureLevel.brightness => await DeviceControls.brightness() ?? 0.5,
  };

  Future<void> _apply(GestureLevel kind, double value) async {
    final level = value.clamp(0.0, 1.0);
    _show(kind, level);
    await _send(kind, level);
  }

  /// Shows [kind]'s level at once and tells the system with the next frame.
  void _applySoon(GestureLevel kind) {
    _show(kind, _level);
    _unsent = kind;
    _sending ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _sending = null;
      final unsent = _unsent;
      _unsent = null;
      if (unsent != null && mounted) unawaited(_send(unsent, _level));
    });
  }

  /// Tells the system (or the player) [kind]'s [level].
  Future<void> _send(GestureLevel kind, double level) async {
    switch (kind) {
      case GestureLevel.volume when _systemVolume:
        await DeviceControls.setVolume(level);
      case GestureLevel.volume:
        await widget.controller.setVolume(level);
        // The player's volume is the room's: kept once the wheel rests.
        _save?.cancel();
        _save = Timer(const Duration(milliseconds: 600), () => unawaited(widget.controller.saveVolume()));
      case GestureLevel.brightness:
        await DeviceControls.setBrightness(level);
    }
  }

  /// Changes the volume by [delta] (arrow keys, the mouse wheel).
  Future<void> nudgeVolume(double delta) async {
    final now = _showing == GestureLevel.volume ? _level : await _current(GestureLevel.volume);
    await _apply(GestureLevel.volume, now + delta);
  }

  void _onDragStart(DragStartDetails details) {
    final size = context.size ?? Size.zero;
    _restoring = null;
    _dragging = null;
    _switching = false;
    if (widget.onSwipeUp != null && details.localPosition.dy >= size.height - portraitRestoreZone) {
      _restoring = 0;
      return;
    }
    // A07.15: going home (or pulling down the status bar) from the screen's
    // edge changes nothing. Global, since the picture need not fill the
    // screen; the portrait fullscreen's restore above goes first.
    final edges = MediaQuery.systemGestureInsetsOf(context);
    if (inSystemGestureArea(
      globalY: _downY ?? details.globalPosition.dy,
      screenHeight: MediaQuery.sizeOf(context).height,
      insets: (top: edges.top, bottom: edges.bottom),
      bottomFallback: defaultTargetPlatform == TargetPlatform.android ? androidGestureFallback : 0,
    )) {
      return;
    }
    final swipe = widget.swipe;
    final drag = pictureDragAt(x: details.localPosition.dx, width: size.width, switchRooms: swipe != null);
    if (drag == PictureDrag.switchRoom) {
      _switching = true;
      swipe?.start();
      return;
    }
    if (!DeviceControls.available) return;
    final kind = drag == PictureDrag.brightness ? GestureLevel.brightness : GestureLevel.volume;
    _dragging = kind;
    _reading = true;
    unawaited(
      _current(kind).then((value) {
        _level = value;
        _reading = false;
      }),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (_switching) {
      _switching = false;
      widget.swipe?.end(details.primaryVelocity ?? 0);
      return;
    }
    final restoring = _restoring;
    _restoring = null;
    _dragging = null;
    if (restoring != null && swipeRestoresPanel(upward: restoring, velocity: details.primaryVelocity ?? 0)) {
      widget.onSwipeUp?.call();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_switching) {
      widget.swipe?.update(details.delta.dy);
      return;
    }
    if (_restoring case final upward?) {
      _restoring = (upward - details.delta.dy).clamp(0.0, double.infinity);
      return;
    }
    final kind = _dragging;
    final height = context.size?.height ?? 0;
    if (kind == null || height <= 0 || _reading) return;
    // A full-height drag moves the level by 1.2 (3.x).
    _level = (_level - details.delta.dy / height * 1.2).clamp(0.0, 1.0);
    _applySoon(kind);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = DeviceControls.available;
    var content = widget.child;
    if (widget.enabled && (mobile || widget.onSwipeUp != null || widget.swipe != null)) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragDown: (details) => _downY = details.globalPosition.dy,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () {
          _dragging = null;
          _restoring = null;
          if (_switching) widget.swipe?.cancel();
          _switching = false;
        },
        child: content,
      );
    }
    if (widget.enabled) {
      content = Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
            unawaited(nudgeVolume(event.scrollDelta.dy > 0 ? -0.05 : 0.05));
          }
        },
        child: content,
      );
    }
    final showing = _showing;
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (showing != null)
          IgnorePointer(
            child: Center(
              child: DecoratedBox(
                key: ValueKey('gesture-level-${showing.name}'),
                decoration: BoxDecoration(color: OnVideoColors.panel, borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(gestureLevelIcon(showing, _level), color: OnVideoColors.foreground),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _level,
                            minHeight: 6,
                            backgroundColor: OnVideoColors.track,
                            color: OnVideoColors.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_level * 100).round()}%',
                        style: Theme.of(context).textTheme.bodyMedium?.emphasis.tabular
                            .copyWith(color: OnVideoColors.foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
