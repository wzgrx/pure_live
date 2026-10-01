import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/features/live_play/dialogs/room_dialogs.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

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
  const new({required this.controller, required this.child, this.enabled = true, super.key});

  /// The room.
  final LiveRoomController controller;

  /// The picture and its tap handling.
  final Widget child;

  /// Off while the controls are locked.
  final bool enabled;

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
    final width = context.size?.width ?? 0;
    final kind = details.localPosition.dx < width / 2 ? GestureLevel.brightness : GestureLevel.volume;
    _dragging = kind;
    unawaited(_current(kind).then((value) => _level = value));
  }

  void _onDragUpdate(DragUpdateDetails details) {
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
    if (widget.enabled && mobile) {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: (_) => _dragging = null,
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
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showing == GestureLevel.volume
                            ? volumeIcon(_level)
                            : _level < 0.34
                            ? Icons.brightness_low_rounded
                            : _level < 0.67
                            ? Icons.brightness_medium_rounded
                            : Icons.brightness_high_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _level,
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_level * 100).round()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
