import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/features/live_play/mini/mini_player.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';

/// The in-app floating window (3.x `showAppFloating`, U.2j-b): the room that
/// played when its page closed ("退出小窗播放" on), over every page, in the
/// bottom-right corner (above the home page's bottom bar), as wide as
/// [inAppMiniBase] and "小窗大小" say. It can be dragged anywhere and stays
/// on screen when the window turns or shrinks; its grip or two fingers
/// resize it, kept for the next time (A07.22); menus, dialogs and sheets
/// hide it (it plays on). The app puts it over its pages; it shows
/// [FloatingRoom.instance].
class FloatingRoomLayer extends StatefulWidget {
  /// Creates the layer.
  const new({this.room, super.key});

  /// The floating room ([FloatingRoom.instance] by default; tests give
  /// their own).
  final FloatingRoom? room;

  @override
  State<FloatingRoomLayer> createState() => _FloatingRoomLayerState();
}

class _FloatingRoomLayerState extends State<FloatingRoomLayer> {
  late final FloatingRoom _room = widget.room ?? FloatingRoom.instance;
  final GlobalKey<OverlayState> _overlay = GlobalKey();
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _room
      ..attachLayer()
      ..addListener(_changed);
    liveRouteObserver.openPopups.addListener(_changed);
    liveRouteObserver.currentRoute.addListener(_changed);
  }

  @override
  void dispose() {
    _room
      ..removeListener(_changed)
      ..detachLayer();
    liveRouteObserver.openPopups.removeListener(_changed);
    liveRouteObserver.currentRoute.removeListener(_changed);
    _entry?.remove();
    _entry?.dispose();
    super.dispose();
  }

  /// The room, a menu or the page on top changed: rebuild, after the frame
  /// when this came in the middle of one (a room page hands over from its
  /// dispose).
  void _changed() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _changed());
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    setState(() {});
    _entry?.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    // Its own overlay, so the buttons' tooltips work above the navigator.
    _entry ??= OverlayEntry(builder: _window);
    return Overlay(key: _overlay, initialEntries: [_entry!]);
  }

  Widget _window(BuildContext context) {
    final runtime = _room.runtime;
    if (runtime == null) return const SizedBox.shrink();
    // Hidden, not stopped, while a menu, dialog or sheet is open (3.x
    // `PopupAwareVisibility`).
    final hidden = liveRouteObserver.openPopups.value > 0;
    return Offstage(
      offstage: hidden,
      child: _FloatingWindow(
        key: ObjectKey(runtime),
        runtime: runtime,
        route: liveRouteObserver.currentRoute.value,
        onBackToRoom: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: runtime.controller.room)),
        onClose: () => unawaited(_room.close()),
      ),
    );
  }
}

class _FloatingWindow extends ConsumerStatefulWidget {
  const new({required this.runtime, required this.route, required this.onBackToRoom, required this.onClose, super.key});

  final RoomRuntime runtime;
  final String route;
  final VoidCallback onBackToRoom;
  final VoidCallback onClose;

  @override
  ConsumerState<_FloatingWindow> createState() => _FloatingWindowState();
}

class _FloatingWindowState extends ConsumerState<_FloatingWindow> {
  /// Where the user dragged it (top-left), or null for the corner.
  Offset? _dragged;

  /// A resize (A07.22): the window when it began, its scale then, which
  /// corner stays, and whether it is a portrait picture's window.
  Rect? _resizeFrom;
  double _resizeFromScale = 1;
  MiniResizeAnchor _anchor = MiniResizeAnchor.centre;
  bool _resizePortrait = false;

  /// The scale shown while resizing, and after it until the stored one
  /// arrives (the store writes in the background).
  double? _scale;

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final media = MediaQuery.of(context);
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final follow = watchSetting(ref, Settings.portraitPipFollowSource);
    final sizeName = watchSetting(ref, Settings.floatWindowSize);
    final landscapeScale = watchSetting(ref, Settings.floatWindowLandscapeScale);
    final portraitScale = watchSetting(ref, Settings.floatWindowPortraitScale);
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        return ListenableBuilder(
          listenable: runtime.orientation,
          builder: (context, _) => StreamBuilder<PlaybackState>(
            stream: runtime.session.states,
            initialData: runtime.session.state,
            builder: (context, snapshot) {
              final state = snapshot.data ?? runtime.session.state;
              final portrait = isPortraitLayout(runtime.orientation.value, detected: state.expectsPortrait);
              final picture = expectedPictureSize(state);
              final ratio = pictureRatio(
                width: picture.width,
                height: picture.height,
                portrait: portrait,
                followPortrait: follow,
              );
              final topClearance = media.viewPadding.top + inAppMiniMargin;
              final bottomClearance = inAppMiniBottomClearance(
                route: widget.route,
                width: area.width,
                safeBottom: media.viewPadding.bottom,
              );
              final room = inAppMiniRoom(area: area, topClearance: topClearance, bottomClearance: bottomClearance);
              // A07.22: a portrait picture's window keeps a resize of its own.
              final portraitWindow = inAppMiniPortrait(ratio);
              final stored = portraitWindow ? portraitScale : landscapeScale;
              if (_resizeFrom == null && _scale != null && (_scale! - stored).abs() < 1e-9) _scale = null;
              final scale = _resizePortrait == portraitWindow ? _scale ?? stored : stored;
              double bounded(double wanted) =>
                  inAppMiniScale(screen: media.size, aspectRatio: ratio, scale: wanted, size: sizeName, room: room);
              Size sized(double scale) =>
                  inAppMiniWindowSize(screen: media.size, aspectRatio: ratio, size: sizeName, scale: scale, room: room);
              final size = sized(scale);
              final offset = inAppMiniOffset(
                area: area,
                window: size,
                dragged: _dragged,
                topClearance: topClearance,
                bottomClearance: bottomClearance,
              );
              // A drag past the edge does not pile up: the next one starts
              // where the window shows.
              if (_dragged != null) _dragged = offset;
              final window = offset & size;
              final grip = inAppMiniGripCorner(window: window, area: area);

              void resizeTo(double wanted) {
                final from = _resizeFrom;
                if (from == null) return;
                final next = bounded(wanted);
                setState(() {
                  _scale = next;
                  _dragged = inAppMiniResizedOffset(from: from, size: sized(next), anchor: _anchor);
                });
              }

              return Stack(
                children: [
                  Positioned(
                    key: const ValueKey('floating-window'),
                    left: offset.dx,
                    top: offset.dy,
                    width: size.width,
                    height: size.height,
                    // 3.x showed it at 80 % while dragged; the video stays
                    // opaque now (P05): a see-through video is drawn
                    // offscreen (saveLayer) every frame of the drag.
                    child: DecoratedBox(
                      // c10: square corners and a floating shadow; the
                      // video is not clipped.
                      decoration: const BoxDecoration(
                        color: OnVideoColors.ground,
                        boxShadow: OnVideoColors.floatingShadow,
                      ),
                      child: MiniPlayerSurface(
                        controller: runtime.controller,
                        reconnect: runtime.reconnect,
                        kind: MiniKind.inApp,
                        // F.1a: kept on while it plays only with "屏幕常亮" on.
                        video: LiveVideoView(
                          session: runtime.session,
                          fit: fit,
                          keepScreenOn: watchSetting(ref, Settings.enableScreenKeepOn),
                        ),
                        onBackToRoom: widget.onBackToRoom,
                        onClose: widget.onClose,
                        onDragStart: (_) => setState(() => _dragged = offset),
                        onDragUpdate: (details) => setState(() => _dragged = (_dragged ?? offset) + details.delta),
                        // Kept where it is, within the screen.
                        onDragEnd: (_) => setState(() => _dragged = offset),
                        // A07.22: the grip on the bottom corner towards the
                        // middle, and two fingers anywhere. Only the
                        // window's size changes: the player is not rebuilt.
                        resizeGrip: grip,
                        onResizeStart: ({required pinch}) => setState(() {
                          _resizeFrom = window;
                          _resizeFromScale = bounded(scale);
                          _resizePortrait = portraitWindow;
                          _scale = _resizeFromScale;
                          _dragged = offset;
                          _anchor = pinch
                              ? MiniResizeAnchor.centre
                              : grip == MiniGripCorner.bottomLeft
                              ? MiniResizeAnchor.topRight
                              : MiniResizeAnchor.topLeft;
                        }),
                        onGripMove: (moved) {
                          final from = _resizeFrom;
                          if (from == null) return;
                          final corner = _anchor == MiniResizeAnchor.topRight
                              ? MiniGripCorner.bottomLeft
                              : MiniGripCorner.bottomRight;
                          final long = from.width < from.height ? from.height : from.width;
                          final extent = inAppMiniGripExtent(from: from.size, corner: corner, moved: moved);
                          resizeTo(_resizeFromScale * extent / long);
                        },
                        onPinch: (factor) => resizeTo(_resizeFromScale * factor),
                        onResizeEnd: () {
                          if (_resizeFrom == null) return;
                          final setting = _resizePortrait
                              ? Settings.floatWindowPortraitScale
                              : Settings.floatWindowLandscapeScale;
                          final kept = setting.normalize(_scale ?? stored);
                          // Still in the corner (a grip pulled towards the
                          // middle grows it from there): it stays the corner
                          // one, following a turn or another page's bottom
                          // bar as before; elsewhere it stays where it is.
                          final corner = inAppMiniOffset(
                            area: area,
                            window: size,
                            topClearance: topClearance,
                            bottomClearance: bottomClearance,
                          );
                          setState(() {
                            _scale = kept;
                            _resizeFrom = null;
                            _dragged = (offset - corner).distance < 0.5 ? null : offset;
                          });
                          // Remembered for the next time (A07.22 c2).
                          unawaited(ref.read(storeProvider).settings.set(setting, kept));
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
