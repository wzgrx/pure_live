import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/appearance.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/features/multiview/multiview_cell.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/multiview/multiview_sheets.dart';
import 'package:pure_live_app/features/room/presentation.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// How the page shows itself (OPS-5).
enum MultiviewDisplay {
  /// Title bar, toolbar and, on wide windows, the picker panel.
  normal,

  /// Only the grid on black and a restore button; the system UI stays.
  immersive,

  /// The system fullscreen: desktop windows fill the screen, phones hide the
  /// system bars and turn landscape.
  fullscreen,
}

/// Enters or leaves the system fullscreen of the page (OPS-5); [phone] also
/// locks landscape and restores portrait on the way out. Tests replace it.
typedef MultiviewSystemFullscreen = Future<void> Function({required bool enabled, required bool phone});

/// The page's system fullscreen, through the room's presentation effects
/// (desktop window fullscreen; phones' system bars and orientation).
final Provider<MultiviewSystemFullscreen> multiviewSystemFullscreenProvider = Provider<MultiviewSystemFullscreen>(
  (ref) =>
      ({required enabled, required phone}) => applyPresentation(
        PresentationEffects(
          presentation: enabled ? RoomPresentation.fullscreen : RoomPresentation.inline,
          lockLandscape: enabled && phone,
          restorePortrait: !enabled && phone,
        ),
        desktop: !touchPlatform,
      ),
);

/// Width of the resident picker panel (LYT-7).
const double multiviewPanelWidth = 320;

const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const List<LogicalKeyboardKey> _numpadKeys = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// Multiview (spec/modules/multiview.md): several rooms, one with sound.
class MultiviewPage extends ConsumerStatefulWidget {
  const new({this.rooms = const [], super.key});

  /// Rooms to fill in order ("一键多画面" from the follows page).
  final List<RoomRef> rooms;

  @override
  ConsumerState<MultiviewPage> createState() => _MultiviewPageState();
}

class _MultiviewPageState extends ConsumerState<MultiviewPage> {
  bool _leaving = false;
  MultiviewDisplay _display = MultiviewDisplay.normal;
  bool _phoneFullscreen = false;

  /// The big cell's control bar in 1+N (OPS-1, OPS-3).
  bool _controls = false;

  /// An opaque page covers this one (RS-3).
  bool _covered = false;

  /// The picker panel was shown in the last build (LYT-7).
  bool _panel = false;

  /// Remote and keyboard focus of the cells (TV: the D-pad moves between them).
  final TvGridFocus _cells = TvGridFocus(debugLabel: 'multiview-cell');

  /// Holds the keyboard for the page's keys (AUD-5) while no cell has it.
  final FocusNode _keys = FocusNode(debugLabel: 'multiview-keys');

  /// The page's own danmaku renderer and budget (DM-3, danmaku REN-6).
  final DanmakuController _overlay = DanmakuController();

  /// Moves the chat layer between cells without rebuilding it.
  final GlobalKey _danmakuKey = GlobalKey(debugLabel: 'multiview-danmaku');

  /// The small column of 1+N and what the page last laid out in it.
  final ScrollController _rail = ScrollController();
  List<int> _railCells = const [];
  double _railExtent = 0;
  double _railViewport = 0;
  bool _railReport = false;

  late final MultiviewController _controller;
  late final MultiviewSystemFullscreen _systemFullscreen;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Read now: ref is unusable in dispose.
    _controller = ref.read(multiviewProvider.notifier);
    _systemFullscreen = ref.read(multiviewSystemFullscreenProvider);
    final prefs = ref.read(danmakuPrefsProvider);
    _overlay
      ..style = prefs.style
      ..budget = prefs.budget;
    _controller.overlay = ControllerOnVideo(_overlay);
    // DM-3: the global danmaku style applies to the playing cell at once.
    ref.listenManual(danmakuPrefsProvider, (_, next) {
      _overlay
        ..style = next.style
        ..budget = next.budget;
    });
    // EXT-1: Esc works while the picker's search field has the focus, and
    // only while this page is on top (REG-MULTI-019).
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _controller.setAppHidden(
        hidden:
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached,
      ),
    );
    _rail.addListener(_reportRail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final compact = WindowLayout(MediaQuery.sizeOf(context)).width == WidthClass.compact;
      // Default layout by window class (ENT-3): 1×2 on phones, 2×2 elsewhere;
      // TV is always 2×2 (principles §5.3).
      final layout = compact && !TvScope.of(context).enabled ? MultiviewLayout.two : MultiviewLayout.four;
      unawaited(_controller.start(layout: layout, rooms: widget.rooms));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RS-3: the route below an opaque page is built offstage with its
    // tickers off.
    final covered = !TickerMode.valuesOf(context).enabled;
    if (covered != _covered) {
      _covered = covered;
      _controller.setCovered(covered: covered);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _lifecycle.dispose();
    _rail.dispose();
    _controller.overlay = null;
    _overlay.dispose();
    // EXT-3: removed while fullscreen: the system UI and window come back.
    if (_display == MultiviewDisplay.fullscreen) {
      unawaited(_systemFullscreen(enabled: false, phone: _phoneFullscreen).catchError((Object _) {}));
    }
    _cells.dispose();
    _keys.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- back

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    _back();
    return true;
  }

  /// EXT-1: another display mode goes back to normal first; normal leaves.
  void _back() {
    if (_display != MultiviewDisplay.normal) {
      unawaited(_setDisplay(MultiviewDisplay.normal));
    } else {
      unawaited(_leave());
    }
  }

  /// Unmount every video, let two frames go by, then leave (EXT-2).
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _controller.clearForExit();
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) context.pop();
  }

  // ------------------------------------------------------------- display

  /// OPS-5: the system fullscreen follows the fullscreen mode only; a failed
  /// platform call is logged and the page stays usable.
  Future<void> _setDisplay(MultiviewDisplay next) async {
    if (!mounted || next == _display) return;
    final previous = _display;
    final phone = touchPlatform && MediaQuery.sizeOf(context).shortestSide < 600;
    setState(() => _display = next);
    final entering = next == MultiviewDisplay.fullscreen;
    if (entering == (previous == MultiviewDisplay.fullscreen)) return;
    if (entering) _phoneFullscreen = phone;
    try {
      await _systemFullscreen(
        enabled: entering,
        phone: _phoneFullscreen,
      ).timeout(const Duration(seconds: 1), onTimeout: () {});
    } on Object catch (error) {
      debugPrint('multiview fullscreen: $error');
    }
  }

  void _toggleFullscreen() => unawaited(
    _setDisplay(_display == MultiviewDisplay.fullscreen ? MultiviewDisplay.normal : MultiviewDisplay.fullscreen),
  );

  // ------------------------------------------------------------- cells

  /// OPS-1.
  void _tap(int index) {
    final state = ref.read(multiviewProvider);
    if (index >= state.cells.length) return;
    // The page's keys work again after a click in the picker panel.
    if (!TvScope.of(context).enabled && !_keys.hasFocus) _keys.requestFocus();
    switch (state.cells[index].status) {
      case CellStatus.playing:
        if (state.layout != MultiviewLayout.onePlusN) {
          _controller.setFocus(index);
        } else if (index == state.big) {
          setState(() => _controls = !_controls);
        } else {
          // Promotion; the new big cell starts with its bar hidden.
          setState(() => _controls = false);
          _controller.setFocus(index);
        }
      case CellStatus.resolving:
        break;
      case CellStatus.empty || CellStatus.offline || CellStatus.error:
        _controller.setTarget(index);
        // With the panel on screen a free cell only becomes the target (LYT-7).
        if (!_panel) unawaited(pickRoomForCell(context, ref, index));
    }
  }

  /// AUD-5: 1–9 give that playing cell the sound (1+N: promote it).
  void _focusByKey(int index) {
    final state = ref.read(multiviewProvider);
    if (index >= state.cells.length || state.cells[index].status != CellStatus.playing) return;
    if (state.layout == MultiviewLayout.onePlusN && index != state.big) setState(() => _controls = false);
    _controller.setFocus(index);
  }

  void _setLayout(MultiviewLayout layout) {
    setState(() => _controls = false);
    _controller.setLayout(layout);
  }

  Map<ShortcutActivator, VoidCallback> _bindings({required bool tv, required bool danmaku}) => {
    for (final (index, key) in _digitKeys.indexed) SingleActivator(key): () => _focusByKey(index),
    for (final (index, key) in _numpadKeys.indexed) SingleActivator(key): () => _focusByKey(index),
    const SingleActivator(LogicalKeyboardKey.keyM): _controller.toggleMuteAll,
    const SingleActivator(LogicalKeyboardKey.space): _controller.togglePauseSelected,
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): _controller.togglePauseSelected,
    if (danmaku) const SingleActivator(LogicalKeyboardKey.keyD): _controller.toggleDanmaku,
    if (!tv) const SingleActivator(LogicalKeyboardKey.keyF, includeRepeats: false): _toggleFullscreen,
  };

  // ------------------------------------------------------------- 1+N column

  /// The column laid out [cells] at [extent] each in a [viewport] high box;
  /// its visibility is reported after the frame (RS-3).
  void _railLaidOut(List<int> cells, double extent, double viewport) {
    _railCells = cells;
    _railExtent = extent;
    _railViewport = viewport;
    if (_railReport) return;
    _railReport = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _railReport = false;
      _reportRail();
    });
  }

  void _reportRail() {
    if (!mounted || ref.read(multiviewProvider).layout != MultiviewLayout.onePlusN || _railExtent <= 0) return;
    final offset = _rail.positions.length == 1 ? _rail.offset : 0.0;
    _controller.setVisibleSmallCells([
      for (final (slot, index) in _railCells.indexed)
        if ((slot + 1) * _railExtent > offset && slot * _railExtent < offset + _railViewport) index,
    ]);
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiviewProvider);
    final danmakuOn = ref.watch(danmakuPrefsProvider.select((prefs) => prefs.enabled));
    final tv = TvScope.of(context).enabled;
    final window = WindowLayout(MediaQuery.sizeOf(context));
    final capacity = multiviewCapacity();
    _panel = _display == MultiviewDisplay.normal && !tv && window.width.atLeast(WidthClass.expanded);
    final layouts = [
      MultiviewLayout.one,
      MultiviewLayout.two,
      MultiviewLayout.four,
      if (window.width.atLeast(WidthClass.expanded)) MultiviewLayout.onePlusN,
      if (capacity >= 9 && window.width.atLeast(WidthClass.large)) MultiviewLayout.nine,
    ];
    // DM-2: the chat shows on the selected cell only, while it plays.
    final danmakuCell = state.danmaku && danmakuOn && state.selectedCell?.status == CellStatus.playing
        ? state.selected
        : null;
    final fullscreen = _display == MultiviewDisplay.fullscreen;

    Widget cell(int index, {FocusOnKeyEventCallback? onKeyEvent}) {
      final big = state.layout == MultiviewLayout.onePlusN && index == state.big;
      return MultiviewCellView(
        index: index,
        focusNode: _cells.node(index),
        autofocus: tv && index == 0,
        onKeyEvent: onKeyEvent,
        onTap: () => _tap(index),
        onPick: () => unawaited(pickRoomForCell(context, ref, index)),
        covered: _covered,
        big: big,
        danmaku: index == danmakuCell ? DanmakuOverlay(key: _danmakuKey, controller: _overlay, visible: true) : null,
        controls: big && _controls
            ? MultiviewControlBar(index: index, fullscreen: fullscreen, onFullscreen: tv ? null : _toggleFullscreen)
            : null,
      );
    }

    final grid = CallbackShortcuts(
      bindings: _bindings(tv: tv, danmaku: danmakuOn),
      child: Focus(
        focusNode: _keys,
        autofocus: !tv,
        child: _Grid(
          state: state,
          compact: window.width == WidthClass.compact && !tv,
          focus: _cells,
          rail: _rail,
          onRail: _railLaidOut,
          cell: cell,
        ),
      ),
    );

    final Widget page = switch (_display) {
      MultiviewDisplay.normal => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: IconButton(tooltip: t.common.back, icon: const Icon(Icons.arrow_back), onPressed: _back),
          title: Text(t.app.multiview),
          actions: [
            if (!tv) ...[
              IconButton(
                tooltip: t.multiview.immersive,
                icon: const Icon(Icons.open_in_full),
                onPressed: () => unawaited(_setDisplay(MultiviewDisplay.immersive)),
              ),
              IconButton(
                tooltip: t.multiview.fullscreen,
                icon: const Icon(Icons.fullscreen),
                onPressed: _toggleFullscreen,
              ),
            ],
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(Sizes.targetTouch),
            child: _Toolbar(tv: tv, layouts: layouts, onLayout: _setLayout),
          ),
        ),
        body: SafeArea(
          child: _panel
              ? Row(
                  children: [
                    Expanded(child: grid),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: multiviewPanelWidth,
                      child: _PickerPanel(
                        target: state.target,
                        onPicked: (room) => unawaited(_controller.assign(ref.read(multiviewProvider).target, room)),
                      ),
                    ),
                  ],
                )
              : grid,
        ),
      ),
      MultiviewDisplay.immersive => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              grid,
              Positioned(
                right: Space.s4,
                bottom: Space.s4,
                child: IconButton.filledTonal(
                  tooltip: t.multiview.exitImmersive,
                  icon: const Icon(Icons.close_fullscreen),
                  onPressed: () => unawaited(_setDisplay(MultiviewDisplay.normal)),
                ),
              ),
            ],
          ),
        ),
      ),
      MultiviewDisplay.fullscreen => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            grid,
            Positioned(
              left: 0,
              top: 0,
              // The exit stays clear of the notch.
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s2),
                  child: IconButton.filledTonal(
                    tooltip: t.multiview.exitFullscreen,
                    icon: const Icon(Icons.fullscreen_exit),
                    onPressed: () => unawaited(_setDisplay(MultiviewDisplay.normal)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    };

    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      // Video pages are dark in every theme (principles §3); TV already is.
      child: theme.brightness == Brightness.light && !tv ? Theme(data: DarkTheme.of(context), child: page) : page,
    );
  }
}

/// The toolbar (OPS-4): layout, add a cell (1+N), danmaku, mute-all and the
/// selected cell's volume.
class _Toolbar extends ConsumerWidget {
  const new({required this.tv, required this.layouts, required this.onLayout});

  final bool tv;
  final List<MultiviewLayout> layouts;
  final ValueChanged<MultiviewLayout> onLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiviewProvider);
    final controller = ref.read(multiviewProvider.notifier);
    final danmakuOn = ref.watch(danmakuPrefsProvider.select((prefs) => prefs.enabled));
    final scheme = Theme.of(context).colorScheme;
    final capacity = multiviewCapacity();
    final canAdd = controller.canAddCell;
    final selected = state.selectedCell;
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.s2),
        child: Row(
          children: [
            // TV keeps the fixed 2×2 (principles §5.3).
            if (!tv)
              PopupMenuButton<MultiviewLayout>(
                tooltip: t.multiview.layout,
                onSelected: onLayout,
                itemBuilder: (context) => [
                  for (final layout in layouts)
                    CheckedPopupMenuItem(value: layout, checked: layout == state.layout, child: Text(layout.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view),
                      const SizedBox(width: Space.s1),
                      Text(state.layout.label),
                    ],
                  ),
                ),
              ),
            if (state.layout == MultiviewLayout.onePlusN && !tv)
              // LYT-1: full means the decoders, and the reason is shown.
              IconButton(
                tooltip: canAdd ? t.multiview.addCell : t.multiview.capacityReached(n: capacity),
                icon: Icon(Icons.add, color: canAdd ? null : scheme.onSurface.withValues(alpha: 0.38)),
                onPressed: () {
                  if (canAdd) {
                    controller.addCell();
                  } else {
                    ScaffoldMessenger.maybeOf(context)
                      ?..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(t.multiview.capacityHint(n: capacity))));
                  }
                },
              ),
            if (danmakuOn)
              IconButton(
                tooltip: state.danmaku ? t.multiview.danmakuOff : t.multiview.danmakuOn,
                isSelected: state.danmaku,
                icon: const Icon(Icons.subtitles_off_outlined),
                selectedIcon: const Icon(Icons.subtitles),
                onPressed: controller.toggleDanmaku,
              ),
            IconButton(
              tooltip: state.muteAll ? t.multiview.unmuteAll : t.multiview.muteAll,
              isSelected: state.muteAll,
              icon: const Icon(Icons.volume_up),
              selectedIcon: const Icon(Icons.volume_off),
              onPressed: controller.toggleMuteAll,
            ),
            IconButton(
              tooltip: t.multiview.selectedVolume,
              icon: const Icon(Icons.tune),
              onPressed: selected?.status == CellStatus.playing
                  ? () => unawaited(showMultiviewVolumeSheet(context, state.selected))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The resident picker panel (LYT-7): picks go to the target cell.
class _PickerPanel extends StatelessWidget {
  const new({required this.target, required this.onPicked});

  final int target;
  final ValueChanged<RoomRef> onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
            child: Text(t.multiview.pickRoomFor(n: target + 1), style: theme.textTheme.titleSmall),
          ),
          Expanded(child: MultiviewRoomPicker(onPicked: onPicked)),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const new({
    required this.state,
    required this.compact,
    required this.focus,
    required this.rail,
    required this.onRail,
    required this.cell,
  });

  final MultiviewState state;
  final bool compact;
  final TvGridFocus focus;
  final ScrollController rail;
  final void Function(List<int> cells, double extent, double viewport) onRail;
  final Widget Function(int index, {FocusOnKeyEventCallback? onKeyEvent}) cell;

  /// Cells per row for D-pad moves; null where the layout is not a grid (1+N).
  int? get _columns => switch (state.layout) {
    MultiviewLayout.one => 1,
    MultiviewLayout.two => compact ? 1 : 2,
    MultiviewLayout.four => 2,
    MultiviewLayout.nine => 3,
    MultiviewLayout.onePlusN => null,
  };

  @override
  Widget build(BuildContext context) {
    final columns = _columns;
    final count = state.cells.length;
    Widget at(int index) => cell(
      index,
      onKeyEvent: columns == null
          ? null
          : (node, event) => focus.handleKey(index, event, count: count, columns: columns),
    );
    const gap = 2.0;
    switch (state.layout) {
      case MultiviewLayout.one:
        return at(0);
      case MultiviewLayout.two:
        final children = [Expanded(child: at(0)), const SizedBox.square(dimension: gap), Expanded(child: at(1))];
        return compact ? Column(children: children) : Row(children: children);
      case MultiviewLayout.four:
      case MultiviewLayout.nine:
        final side = state.layout == MultiviewLayout.four ? 2 : 3;
        return Column(
          children: [
            for (var row = 0; row < side; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var column = 0; column < side; column++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(gap / 2),
                          child: row * side + column < count ? at(row * side + column) : const SizedBox(),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      case MultiviewLayout.onePlusN:
        // Big cell 3/4 wide; the small column shows three a screen, scrolls
        // and stays mounted (LYT-6).
        final small = [
          for (var i = 0; i < count; i++)
            if (i != state.big) i,
        ];
        return Row(
          children: [
            Expanded(flex: 3, child: at(state.big)),
            const SizedBox(width: gap),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final extent = constraints.maxHeight / 3;
                  onRail(small, extent, constraints.maxHeight);
                  return SingleChildScrollView(
                    controller: rail,
                    child: Column(
                      children: [
                        for (final index in small)
                          SizedBox(
                            height: extent,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: gap),
                              child: at(index),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
    }
  }
}
