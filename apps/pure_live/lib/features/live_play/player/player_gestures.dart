import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';

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
/// the room's. A level bar shows while it changes.
class PlayerGestureLayer extends StatefulWidget {
  /// Wraps [child].
  const new({required this.controller, required this.child, this.enabled = true, this.onSwipeUp, super.key});

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

  bool get _systemVolume => DeviceControls.available;

  @override
  void dispose() {
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
    if (widget.onSwipeUp != null && details.localPosition.dy >= size.height - portraitRestoreZone) {
      _restoring = 0;
      return;
    }
    if (!DeviceControls.available) return;
    final kind = details.localPosition.dx < size.width / 2 ? GestureLevel.brightness : GestureLevel.volume;
    _dragging = kind;
    unawaited(_current(kind).then((value) => _level = value));
  }

  void _onDragEnd(DragEndDetails details) {
    final restoring = _restoring;
    _restoring = null;
    _dragging = null;
    if (restoring != null && swipeRestoresPanel(upward: restoring, velocity: details.primaryVelocity ?? 0)) {
      widget.onSwipeUp?.call();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_restoring case final upward?) {
      _restoring = (upward - details.delta.dy).clamp(0.0, double.infinity);
      return;
    }
    final kind = _dragging;
    final height = context.size?.height ?? 0;
    if (kind == null || height <= 0) return;
    // A full-height drag moves the level by 1.2 (3.x).
    _level = (_level - details.delta.dy / height * 1.2).clamp(0.0, 1.0);
    unawaited(_apply(kind, _level));
  }

  @override
  Widget build(BuildContext context) {
    final mobile = DeviceControls.available;
    var content = widget.child;
    if (widget.enabled && (mobile || widget.onSwipeUp != null)) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () {
          _dragging = null;
          _restoring = null;
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
