import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/features/live_play/mini/mini_player.dart';
import 'package:pure_live/features/live_play/mini/room_mini_window.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

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
    PictureInPicture.active.addListener(_changed);
  }

  @override
  void dispose() {
    _room
      ..removeListener(_changed)
      ..detachLayer();
    liveRouteObserver.openPopups.removeListener(_changed);
    liveRouteObserver.currentRoute.removeListener(_changed);
    PictureInPicture.active.removeListener(_changed);
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
    final hidden = liveRouteObserver.openPopups.value > 0 && !PictureInPicture.active.value;
    return Offstage(
      offstage: hidden,
      child: _FloatingWindow(
        key: ObjectKey(runtime),
        runtime: runtime,
        route: liveRouteObserver.currentRoute.value,
        room: _room,
        onBackToRoom: () => unawaited(AppNavigator.toLiveRoomDetail(liveRoom: runtime.controller.room)),
        onClose: () => unawaited(_room.close()),
      ),
    );
  }
}

class _FloatingWindow extends ConsumerStatefulWidget {
  const new({
    required this.runtime,
    required this.route,
    required this.room,
    required this.onBackToRoom,
    required this.onClose,
    super.key,
  });

  final RoomRuntime runtime;
  final String route;

  /// Where the last window settled ([FloatingRoom.placement]).
  final FloatingRoom room;
  final VoidCallback onBackToRoom;
  final VoidCallback onClose;

  @override
  ConsumerState<_FloatingWindow> createState() => _FloatingWindowState();
}

/// What the window is laid out by, from the last build: the area, the
/// clearances, the picture's ratio and the size settings.
final class _Layout {
  const new({
    required this.screen,
    required this.area,
    required this.ratio,
    required this.topClearance,
    required this.bottomClearance,
    required this.sizeName,
    required this.stored,
    required this.portraitWindow,
  });

  final Size screen;
  final Size area;
  final double ratio;
  final double topClearance;
  final double bottomClearance;
  final String sizeName;

  /// The kept resize of this picture's kind (A07.22).
  final double stored;
  final bool portraitWindow;

  Size get room => inAppMiniRoom(area: area, topClearance: topClearance, bottomClearance: bottomClearance);

  double bounded(double wanted) =>
      inAppMiniScale(screen: screen, aspectRatio: ratio, scale: wanted, size: sizeName, room: room);

  Size sized(double scale) =>
      inAppMiniWindowSize(screen: screen, aspectRatio: ratio, size: sizeName, scale: scale, room: room);
}

class _FloatingWindowState extends ConsumerState<_FloatingWindow> with SingleTickerProviderStateMixin {
  /// Where the user left it (top-left), or null for the corner; and the
  /// side it is tucked into (A07.24).
  Offset? _dragged;
  MiniDock? _dock;

  /// A finger is moving it: it may go past the sides then.
  bool _dragging = false;

  /// A resize (A07.22): the window when it began, its scale then, which
  /// corner stays, and whether it is a portrait picture's window.
  Rect? _resizeFrom;
  double _resizeFromScale = 1;
  MiniResizeAnchor _anchor = MiniResizeAnchor.centre;
  bool _resizePortrait = false;

  /// The scale shown while resizing, and after it until the stored one
  /// arrives (the store writes in the background).
  double? _scale;

  /// A07.24: a drag, a resize or the settling slide changes only the
  /// window's place and size; the picture under it is not rebuilt.
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final ValueNotifier<MiniGripCorner?> _grip = ValueNotifier(null);

  /// The clock of the settling slide; [_slideRun] says where it is.
  late final AnimationController _settle = AnimationController.unbounded(vsync: this)..addListener(_moved);
  _SlideSimulation? _slideRun;
  _Layout? _layout;

  /// Android's picture-in-picture is on this device (the window's button,
  /// and leaving the app turns the window into it; A07.24).
  bool _pipSupported = false;
  StreamSubscription<PlaybackState>? _states;
  bool? _armed;
  (int, int)? _armedSize;
  Rect? _armedRect;

  /// The picture's width × height for picture-in-picture.
  (int, int) _pictureSize = (16, 9);

  @override
  void initState() {
    super.initState();
    final placement = widget.room.placement;
    _dragged = placement?.offset;
    _dock = placement?.dock;
    unawaited(
      PictureInPicture.supported().then((supported) {
        if (mounted && supported != _pipSupported) setState(() => _pipSupported = supported);
      }),
    );
    _states = widget.runtime.session.states.listen((_) => _syncAutoPip());
  }

  @override
  void didUpdateWidget(_FloatingWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) _syncAutoPipLater();
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    if (_armed ?? false) unawaited(PictureInPicture.setAutoEnter(enabled: false, owner: this));
    _settle.dispose();
    _frame.dispose();
    _grip.dispose();
    super.dispose();
  }

  void _syncAutoPipLater() => SchedulerBinding.instance.addPostFrameCallback((_) => _syncAutoPip());

  /// Leaving the app turns the window into Android's picture-in-picture
  /// (A07.24; before, the picture went away with the app): with
  /// "离开应用时自动画中画" on, while it plays and no room page is on top
  /// (a room page arms its own); it grows out of the window.
  void _syncAutoPip() {
    if (!mounted || !_pipSupported) return;
    final runtime = widget.runtime;
    final status = runtime.session.state.status;
    final armed = shouldAutoEnterPip(
      enabled: runtime.controller.store.settings.get(Settings.autoPipOnLeave),
      onTop: widget.route != RoutePath.kLivePlay,
      stage: runtime.controller.stage,
      status: status,
      audioOnly: runtime.controller.audioOnly,
    );
    final layout = _layout;
    final rect = armed && layout != null && !PictureInPicture.active.value ? _rect(layout) : null;
    if (armed == _armed && (!armed || (_armedSize == _pictureSize && _armedRect == rect))) return;
    final titled = armed && !(_armed ?? false);
    _armed = armed;
    _armedSize = _pictureSize;
    _armedRect = rect;
    if (titled) {
      unawaited(PictureInPicture.update(title: _title, subtitle: runtime.controller.room.title));
    }
    unawaited(
      PictureInPicture.setAutoEnter(
        enabled: armed,
        width: _pictureSize.$1,
        height: _pictureSize.$2,
        picture: rect,
        pixelRatio: View.maybeOf(context)?.devicePixelRatio ?? 1,
        owner: this,
      ),
    );
  }

  String get _title {
    final room = widget.runtime.controller.room;
    return room.nick.isNotEmpty ? room.nick : room.title;
  }

  /// The window's picture-in-picture button (A07.24).
  Future<void> _enterPip() async {
    final layout = _layout;
    final availability = await PictureInPicture.availability();
    if (!mounted) return;
    if (availability == PipAvailability.disabled) {
      showPipDisabledToast();
      return;
    }
    final entry = await PictureInPicture.enter(
      width: _pictureSize.$1,
      height: _pictureSize.$2,
      picture: layout == null ? null : _rect(layout),
      pixelRatio: View.maybeOf(context)?.devicePixelRatio ?? 1,
      title: _title,
      subtitle: widget.runtime.controller.room.title,
    );
    if (!mounted) return;
    switch (entry) {
      case PipEntry.entered:
        break;
      case PipEntry.disabled:
        showPipDisabledToast();
      case PipEntry.failed:
        AppNavigator.toast(i18n('pip_enter_failed'));
    }
  }

  void _moved() => _frame.value++;

  /// The window's size now.
  Size _size(_Layout layout) {
    final scale = _resizePortrait == layout.portraitWindow ? _scale ?? layout.stored : layout.stored;
    return layout.sized(scale);
  }

  /// The window's place and size now.
  Rect _rect(_Layout layout) {
    final size = _size(layout);
    final Offset offset;
    final run = _slideRun;
    if (_settle.isAnimating && run != null) {
      offset = run.at(_settle.value);
    } else if (_dragging) {
      offset = inAppMiniDragOffset(
        area: layout.area,
        window: size,
        wanted: _dragged ?? Offset.zero,
        topClearance: layout.topClearance,
        bottomClearance: layout.bottomClearance,
      );
    } else {
      offset = inAppMiniOffset(
        area: layout.area,
        window: size,
        dragged: _dragged,
        dock: _dock,
        topClearance: layout.topClearance,
        bottomClearance: layout.bottomClearance,
      );
    }
    return offset & size;
  }

  /// Puts the grip on the corner towards the middle (after the frame: it
  /// sits inside the surface).
  void _placeGrip() {
    final layout = _layout;
    if (layout == null) return;
    _grip.value = _dock != null ? null : inAppMiniGripCorner(window: _rect(layout), area: layout.area);
  }

  void _dragStart() {
    final layout = _layout;
    if (layout == null) return;
    final from = _rect(layout).topLeft;
    _settle.stop();
    _dragging = true;
    _dock = null;
    _dragged = from;
    _grip.value = null;
    _moved();
  }

  void _dragUpdate(Offset delta) {
    final layout = _layout;
    if (layout == null || !_dragging) return;
    // From where it shows: a drag past the limit does not pile up.
    _dragged = _rect(layout).topLeft + delta;
    _moved();
  }

  void _dragEnd(Offset velocity) {
    final layout = _layout;
    if (layout == null || !_dragging) return;
    final window = _rect(layout);
    _dragging = false;
    final settled = inAppMiniSettle(
      area: layout.area,
      window: window,
      velocity: velocity,
      topClearance: layout.topClearance,
      bottomClearance: layout.bottomClearance,
    );
    _slide(from: window.topLeft, to: settled.offset, dock: settled.dock, velocity: velocity);
  }

  /// Slides from [from] to [to] on a spring that leaves at [velocity] (no
  /// slide when the system asks for less motion), tucked into [dock] or
  /// not, and remembers it.
  void _slide({required Offset from, required Offset to, required MiniDock? dock, Offset velocity = Offset.zero}) {
    _dock = dock;
    _dragged = to;
    widget.room.placement = (offset: to, dock: dock);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still || (from - to).distance < 0.5) {
      _settle.stop();
      _moved();
    } else {
      final tolerance = AppMotion.tolerance(MediaQuery.devicePixelRatioOf(context));
      ReleaseSpringSimulation axis(double start, double end, double speed) => ReleaseSpringSimulation(
        spring: AppMotion.floatingSpring,
        start: start,
        end: end,
        velocity: speed,
        tolerance: tolerance,
      );
      final run = _slideRun = _SlideSimulation(axis(from.dx, to.dx, velocity.dx), axis(from.dy, to.dy, velocity.dy));
      _settle.animateRelease(run, refreshRate: View.of(context).display.refreshRate);
    }
    _placeGrip();
    _syncAutoPipLater();
  }

  /// A tap on a tucked-away window brings it back to its side.
  void _undock() {
    final layout = _layout;
    if (layout == null || _dock == null) return;
    final window = _rect(layout);
    final inside = inAppMiniOffset(
      area: layout.area,
      window: window.size,
      dragged: window.topLeft,
      topClearance: layout.topClearance,
      bottomClearance: layout.bottomClearance,
    );
    _slide(from: window.topLeft, to: inside, dock: null);
  }

  void _resizeStart({required bool pinch}) {
    final layout = _layout;
    if (layout == null) return;
    final window = _rect(layout);
    _settle.stop();
    _resizeFrom = window;
    _resizeFromScale = layout.bounded(_scale ?? layout.stored);
    _resizePortrait = layout.portraitWindow;
    _scale = _resizeFromScale;
    _dragged = window.topLeft;
    _dock = null;
    final grip = _grip.value;
    _anchor = pinch
        ? MiniResizeAnchor.centre
        : grip == MiniGripCorner.bottomLeft
        ? MiniResizeAnchor.topRight
        : MiniResizeAnchor.topLeft;
  }

  void _resizeTo(double wanted) {
    final layout = _layout;
    final from = _resizeFrom;
    if (layout == null || from == null) return;
    final next = layout.bounded(wanted);
    _scale = next;
    _dragged = inAppMiniResizedOffset(from: from, size: layout.sized(next), anchor: _anchor);
    _moved();
  }

  void _gripMove(Offset moved) {
    final from = _resizeFrom;
    if (from == null) return;
    final corner = _anchor == MiniResizeAnchor.topRight ? MiniGripCorner.bottomLeft : MiniGripCorner.bottomRight;
    final long = from.width < from.height ? from.height : from.width;
    final extent = inAppMiniGripExtent(from: from.size, corner: corner, moved: moved);
    _resizeTo(_resizeFromScale * extent / long);
  }

  void _resizeEnd() {
    final layout = _layout;
    if (layout == null || _resizeFrom == null) return;
    final window = _rect(layout);
    final setting = _resizePortrait ? Settings.floatWindowPortraitScale : Settings.floatWindowLandscapeScale;
    final kept = setting.normalize(_scale ?? layout.stored);
    // Still in the corner (a grip pulled towards the middle grows it from
    // there): it stays the corner one, following a turn or another page's
    // bottom bar as before; elsewhere it stays where it is.
    final corner = inAppMiniOffset(
      area: layout.area,
      window: window.size,
      topClearance: layout.topClearance,
      bottomClearance: layout.bottomClearance,
    );
    _scale = kept;
    _resizeFrom = null;
    _dragged = (window.topLeft - corner).distance < 0.5 ? null : window.topLeft;
    widget.room.placement = _dragged == null ? null : (offset: _dragged!, dock: null);
    _moved();
    _placeGrip();
    _syncAutoPipLater();
    // Remembered for the next time (A07.22 c2).
    unawaited(ref.read(storeProvider).settings.set(setting, kept));
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final media = MediaQuery.of(context);
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final follow = watchSetting(ref, Settings.portraitPipFollowSource);
    final sizeName = watchSetting(ref, Settings.floatWindowSize);
    final landscapeScale = watchSetting(ref, Settings.floatWindowLandscapeScale);
    final portraitScale = watchSetting(ref, Settings.floatWindowPortraitScale);
    final keepOn = watchSetting(ref, Settings.enableScreenKeepOn);
    watchSetting(ref, Settings.autoPipOnLeave);
    _syncAutoPipLater();
    // A07.24: in Android's picture-in-picture the window is the whole
    // screen, the picture alone (the system draws the buttons).
    final pip = PictureInPicture.active.value;
    // Built once per change of the room or the settings; a drag does not
    // come here (A07.24).
    final surface = MiniPlayerSurface(
      controller: runtime.controller,
      reconnect: runtime.reconnect,
      kind: pip ? MiniKind.systemPip : MiniKind.inApp,
      onPip: _pipSupported ? () => unawaited(_enterPip()) : null,
      // F.1a: kept on while it plays only with "屏幕常亮" on.
      video: LiveVideoView(session: runtime.session, fit: fit, keepScreenOn: keepOn),
      onBackToRoom: widget.onBackToRoom,
      onClose: widget.onClose,
      onDragStart: (_) => _dragStart(),
      onDragUpdate: (details) => _dragUpdate(details.delta),
      onDragEnd: (details) => _dragEnd(details.velocity.pixelsPerSecond),
      // A07.22: the grip on the bottom corner towards the middle, and two
      // fingers anywhere. Only the window's size changes: the player is not
      // rebuilt.
      resizeGrip: _grip,
      onResizeStart: _resizeStart,
      onGripMove: _gripMove,
      onPinch: (factor) => _resizeTo(_resizeFromScale * factor),
      onResizeEnd: _resizeEnd,
    );
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
              _pictureSize = miniPictureSize(
                width: picture.width,
                height: picture.height,
                portrait: portrait,
                followPortrait: follow,
              );
              // A07.22: a portrait picture's window keeps a resize of its own.
              final portraitWindow = inAppMiniPortrait(ratio);
              final stored = portraitWindow ? portraitScale : landscapeScale;
              if (_resizeFrom == null && _scale != null && (_scale! - stored).abs() < 1e-9) _scale = null;
              _layout = _Layout(
                screen: media.size,
                area: area,
                ratio: ratio,
                topClearance: media.viewPadding.top + inAppMiniMargin,
                bottomClearance: inAppMiniBottomClearance(
                  route: widget.route,
                  width: area.width,
                  safeBottom: media.viewPadding.bottom,
                ),
                sizeName: sizeName,
                stored: stored,
                portraitWindow: portraitWindow,
              );
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_dragging && _resizeFrom == null) _placeGrip();
              });
              return ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, picture) {
                  final window = pip ? Offset.zero & area : _rect(_layout!);
                  return Stack(
                    children: [
                      Positioned(
                        key: const ValueKey('floating-window'),
                        left: window.left,
                        top: window.top,
                        width: window.width,
                        height: window.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            picture!,
                            // A tucked-away window: a tap brings it back,
                            // a drag pulls it out.
                            if (_dock != null && !_settle.isAnimating && !pip)
                              GestureDetector(
                                key: const ValueKey('floating-window-tucked'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _undock,
                                onPanStart: (_) => _dragStart(),
                                onPanUpdate: (details) => _dragUpdate(details.delta),
                                onPanEnd: (details) => _dragEnd(details.velocity.pixelsPerSecond),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
                // 3.x showed it at 80 % while dragged; the video stays opaque
                // now (P05): a see-through video is drawn offscreen
                // (saveLayer) every frame of the drag.
                child: RepaintBoundary(
                  child: DecoratedBox(
                    // c10: square corners and a floating shadow; the video
                    // is not clipped.
                    decoration: const BoxDecoration(
                      color: OnVideoColors.ground,
                      boxShadow: OnVideoColors.floatingShadow,
                    ),
                    child: surface,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The floating window's settling slide (A07.24): a spring on each axis,
/// each leaving at the finger's speed along it. Its value is the time, so
/// one controller runs both.
class _SlideSimulation extends Simulation {
  new(this._x, this._y) : super(tolerance: _x.tolerance);

  final Simulation _x;
  final Simulation _y;

  /// Where the window is [time] seconds in.
  Offset at(double time) => Offset(_x.x(time), _y.x(time));

  @override
  double x(double time) => time;

  @override
  double dx(double time) => 1;

  @override
  bool isDone(double time) => _x.isDone(time) && _y.isDone(time);
}
