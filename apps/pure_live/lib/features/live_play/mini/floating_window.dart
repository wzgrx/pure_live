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
/// [inAppMiniBase] says. It can be dragged anywhere and stays on screen when
/// the window turns or shrinks; menus, dialogs and sheets hide it (it plays
/// on). The app puts it over its pages; it shows [FloatingRoom.instance].
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
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final media = MediaQuery.of(context);
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
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
              final portrait = isPortraitLayout(runtime.orientation.value, detected: state.isPortrait);
              final size = inAppMiniSize(
                screen: media.size,
                aspectRatio: pictureRatio(width: state.videoWidth, height: state.videoHeight, portrait: portrait),
              );
              final offset = inAppMiniOffset(
                area: area,
                window: size,
                dragged: _dragged,
                topClearance: media.viewPadding.top + inAppMiniMargin,
                bottomClearance: inAppMiniBottomClearance(
                  route: widget.route,
                  width: area.width,
                  safeBottom: media.viewPadding.bottom,
                ),
              );
              // A drag past the edge does not pile up: the next one starts
              // where the window shows.
              if (_dragged != null) _dragged = offset;
              return Stack(
                children: [
                  Positioned(
                    key: const ValueKey('floating-window'),
                    left: offset.dx,
                    top: offset.dy,
                    width: size.width,
                    height: size.height,
                    child: AnimatedOpacity(
                      // 3.x: 80 % while it is dragged.
                      opacity: _dragging ? 0.8 : 1,
                      duration: const Duration(milliseconds: 120),
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
                          video: LiveVideoView(session: runtime.session, fit: fit),
                          onBackToRoom: widget.onBackToRoom,
                          onClose: widget.onClose,
                          onDragStart: (_) => setState(() {
                            _dragging = true;
                            _dragged = offset;
                          }),
                          onDragUpdate: (details) => setState(() => _dragged = (_dragged ?? offset) + details.delta),
                          onDragEnd: (_) => setState(() {
                            _dragging = false;
                            // Kept where it is, within the screen.
                            _dragged = offset;
                          }),
                        ),
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
