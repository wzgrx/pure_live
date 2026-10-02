import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/logic/multiview_geometry.dart';
import 'package:pure_live/features/multiview/widgets/cell_controls.dart';
import 'package:pure_live/features/multiview/widgets/cell_view.dart';
import 'package:pure_live/features/multiview/widgets/focus_bar.dart';
import 'package:pure_live/features/multiview/widgets/room_picker.dart';
import 'package:pure_live/features/multiview/widgets/toolbar.dart';
import 'package:pure_live/features/multiview/widgets/wall.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/screen_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/panels/side_panel.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Multi-view (3.x `lib/modules/multiview`, docs/ui/compare/U.8): several
/// rooms at once, one of them audible, in a 1×1, 1×2, 2×2 or 1+3 wall of
/// 16:9 cells. Laid out as the live room: the picture area above (portrait)
/// or on the left (landscape, wide), the selected cell's controls and the
/// room picker below it or in a right column that folds away.
///
/// Routes: `RoutePath.kMultiview`.
class MultiviewPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  /// The processors of this device (the cells it may decode, UI_PLAN §9.3).
  @visibleForTesting
  static int Function() processors = () => Platform.numberOfProcessors;

  @override
  ConsumerState<MultiviewPage> createState() => _MultiviewPageState();
}

/// The page's chrome: everything, the cells alone with the status bar, or
/// the cells alone with the system bars hidden (3.x `_DisplayMode`).
enum _DisplayMode { normal, immersive, fullscreen }

/// Where the page puts the cells and their controls (by the page's own
/// size, never the screen's: c15).
enum _Arrangement {
  /// The cells above, the selected cell's controls and the picker below.
  portrait,

  /// A landscape phone: the toolbar in the app bar, the cells on the left,
  /// the controls or the picker in the right column.
  landscape,

  /// Tablets and desktops: the cells on the left, the controls and the
  /// picker in a 360-point right column.
  wide,
}

/// The panel open over the page.
enum _Overlay {
  none,

  /// The danmaku settings (U.2f's panel).
  danmaku,

  /// The cell's controls (immersive and fullscreen: long press).
  cell,

  /// The room picker (immersive and fullscreen: tap on an empty cell).
  picker,
}

bool get _mobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// The right column of wide screens (U.2f's panel width).
const double _columnWidth = roomSidePanelWidth;

/// The landscape phone's right column is at least this wide: the selected
/// cell's five 48-point buttons on one row with 8 at each side.
const double _minColumnWidth = 256;

class _MultiviewPageState extends ConsumerState<MultiviewPage> {
  late final MultiviewController _controller;
  final Map<int, GlobalKey> _cellKeys = {};
  _DisplayMode _mode = _DisplayMode.normal;
  _Arrangement _arrangement = _Arrangement.portrait;
  _Overlay _overlay = _Overlay.none;
  bool _exiting = false;
  bool _barVisible = false;
  bool _folded = false;
  bool _columnPicker = false;
  int? _selectedId;
  int? _targetId;
  Set<int> _railOffscreen = const {};
  bool _appHidden = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final services = ref.read(appServicesProvider);
    final store = services.store;
    final sites = ref.read(sitesProvider);
    final danmaku = ref.read(danmakuProvider);
    final sessions = ref.read(playbackSessionFactoryProvider);
    final config = _engineConfig(store.settings);
    _controller = MultiviewController(
      siteOf: sites.maybeOf,
      newSession: () => sessions(config: config),
      danmakuFor: danmaku.connectionFor,
      danmakuSupports: danmaku.supports,
      store: store,
      mobile: _mobile,
      maxCells: multiviewMaxCells(mobile: _mobile, processors: MultiviewPage.processors()),
      toast: (message) => AppNavigator.toast(message),
    )..addListener(_onControllerChanged);
    unawaited(_controller.start());
    HardwareKeyboard.instance.addHandler(_onKey);
    // No video is decoded while the app is out of sight (UI_PLAN §9.3).
    _lifecycle = AppLifecycleListener(onHide: () => _setAppHidden(true), onShow: () => _setAppHidden(false));
  }

  /// The player settings (M9) as the engine's configuration (as the live
  /// room).
  static MpvEngineConfig _engineConfig(SettingsStore settings) => MpvEngineConfig(
    platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux,
    hardwareDecoding: settings.get(Settings.enableCodec),
    customOutput: settings.get(Settings.customPlayerOutput),
    videoOutputDriver: settings.get(Settings.videoOutputDriver),
    hardwareDecoder: settings.get(Settings.videoHardwareDecoder),
    audioOutputDriver: settings.get(Settings.audioOutputDriver),
    androidCompatibility: settings.get(Settings.playerCompatMode),
    rtxVideoSuperResolution: settings.get(Settings.enableRtxVsr),
  );

  void _onControllerChanged() {
    final cells = _controller.cells;
    bool exists(int? id) => cells.any((cell) => cell.id == id);
    _cellKeys.removeWhere((id, _) => !exists(id));
    if (!exists(_selectedId)) _selectedId = null;
    if (!exists(_targetId)) _targetId = null;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (_mode == _DisplayMode.fullscreen && _mobile) unawaited(_restoreSystemUi());
    if (_mode == _DisplayMode.fullscreen && !_mobile) unawaited(DesktopWindow.setFullScreen(on: false));
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  // ---- selection and the picker's target ----

  /// The cell whose controls show: the one tapped or long-pressed last,
  /// else the controller's (the large cell in 1+3, else the audible one).
  int get _selectedIndex {
    final cells = _controller.cells;
    final index = cells.indexWhere((cell) => cell.id == _selectedId && cell.stage != CellStage.empty);
    return index >= 0 ? index : _controller.selectedIndex;
  }

  bool get _hasSelection {
    final cells = _controller.cells;
    final index = _selectedIndex;
    return index < cells.length && cells[index].stage != CellStage.empty;
  }

  /// The cell the picker fills: the one the user chose, else the first
  /// empty one, else one that failed or is offline, else the selected one
  /// (its room is replaced, "第 1 格换台").
  int get _targetIndex {
    final cells = _controller.cells;
    final chosen = cells.indexWhere((cell) => cell.id == _targetId);
    if (chosen >= 0) return chosen;
    final empty = cells.indexWhere((cell) => cell.stage == CellStage.empty);
    if (empty >= 0) return empty;
    final assignable = cells.indexWhere((cell) => cell.assignable);
    if (assignable >= 0) return assignable;
    return _selectedIndex;
  }

  /// The picker is on screen (its target cell gets the dashed frame).
  bool get _pickerVisible => switch (_mode) {
    _DisplayMode.normal => switch (_arrangement) {
      _Arrangement.portrait => true,
      _Arrangement.wide => !_folded && _overlay != _Overlay.danmaku,
      _Arrangement.landscape => !_folded && _overlay != _Overlay.danmaku && (_columnPicker || !_hasSelection),
    },
    _ => _overlay == _Overlay.picker,
  };

  int? _shownIn(LiveRoom room) {
    final index = _controller.indexOfRoom(room);
    return index < 0 ? null : index + 1;
  }

  void _pick(LiveRoom room) {
    final cells = _controller.cells;
    final shown = _controller.indexOfRoom(room);
    if (shown >= 0) {
      // W4: the same stream twice only costs a decoder; select its cell.
      AppNavigator.toast(i18n('multiview_already_shown', args: {'index': '${shown + 1}'}));
      _select(shown);
      return;
    }
    final target = _targetIndex.clamp(0, cells.length - 1);
    final cell = cells[target];
    final smallCell = _controller.layout == MultiviewLayout.focus && target != _controller.focusedIndex;
    unawaited(_controller.assign(target, room));
    setState(() {
      // The next empty cell becomes the target, so rooms can be picked in a row.
      _targetId = null;
      if (!smallCell) _selectedId = cell.id;
      // A landscape phone keeps picking while cells are empty, then shows
      // the controls.
      _columnPicker = _controller.cells.any((other) => other.stage == CellStage.empty);
      if (_overlay == _Overlay.picker) _overlay = _Overlay.none;
    });
  }

  void _select(int index) {
    final cell = _controller.cells[index];
    setState(() {
      _selectedId = cell.id;
      _columnPicker = false;
      if (_overlay == _Overlay.picker) _overlay = _Overlay.none;
    });
    if (!cell.playing) return;
    if (_controller.layout == MultiviewLayout.focus) {
      unawaited(_controller.promote(index));
    } else {
      unawaited(_controller.setAudioFocus(index));
    }
  }

  /// Makes cell [index] the picker's target and shows the picker.
  void _openPicker(int index) {
    setState(() {
      _targetId = _controller.cells[index].id;
      if (_mode == _DisplayMode.normal) {
        _folded = false;
        _columnPicker = true;
        if (_overlay == _Overlay.danmaku) _overlay = _Overlay.none;
      } else {
        _overlay = _Overlay.picker;
      }
    });
  }

  void _onCellTap(int index) {
    final cell = _controller.cells[index];
    switch (cell.stage) {
      case CellStage.playing:
        if (_controller.layout == MultiviewLayout.focus) {
          if (_controller.focusedIndex != index) {
            setState(() {
              _barVisible = false;
              _selectedId = cell.id;
              _columnPicker = false;
            });
            unawaited(_controller.promote(index));
          } else {
            setState(() {
              _selectedId = cell.id;
              _columnPicker = false;
              // c14: the large cell's bar only where the controls are hidden.
              if (_mode != _DisplayMode.normal) _barVisible = !_barVisible;
            });
          }
          return;
        }
        _show(cell);
        unawaited(_controller.setAudioFocus(index));
      case CellStage.resolving:
        _show(cell);
      case CellStage.empty || CellStage.offline || CellStage.failed:
        _openPicker(index);
    }
  }

  /// Shows [cell]'s controls (the landscape column leaves the picker).
  void _show(MultiviewCell cell) => setState(() {
    _selectedId = cell.id;
    _columnPicker = false;
  });

  /// Long press and right click (3.x's cell menu): the cell's controls, in
  /// place on the page, in a panel in the immersive and fullscreen modes.
  void _onCellLongPress(int index) {
    setState(() {
      _selectedId = _controller.cells[index].id;
      if (_mode == _DisplayMode.normal) {
        _columnPicker = false;
        _folded = false;
        if (_overlay == _Overlay.danmaku) _overlay = _Overlay.none;
      } else {
        _overlay = _Overlay.cell;
      }
    });
  }

  void _toggleDanmakuSettings() => setState(() {
    _overlay = _overlay == _Overlay.danmaku ? _Overlay.none : _Overlay.danmaku;
    _folded = false;
  });

  Future<void> _openLiveRoom(LiveRoom room) async {
    final paused = await _controller.pauseAll();
    try {
      await AppNavigator.toNamed<void>(RoutePath.kLivePlay, arguments: room);
    } finally {
      if (mounted) unawaited(_controller.resumeCells(paused));
    }
  }

  void _setLayout(MultiviewLayout layout) {
    setState(() => _barVisible = false);
    unawaited(_controller.setLayout(layout));
  }

  /// The rail's cells out of sight ([indexes]); every cell while the app
  /// is hidden. They decode no video (UI_PLAN §9.3).
  void _setOffscreen(Set<int> indexes) {
    _railOffscreen = indexes;
    final cells = _controller.cells;
    _controller.setOffscreen({
      for (final (index, cell) in cells.indexed)
        if (_appHidden || indexes.contains(index)) cell.id,
    });
  }

  void _setAppHidden(bool hidden) {
    if (hidden == _appHidden) return;
    _appHidden = hidden;
    _setOffscreen(_railOffscreen);
  }

  // ---- display modes and leaving ----

  /// Closes what is open, one step at a time (7. 返回链): a panel, the
  /// landscape column's picker, the immersive or fullscreen mode. False when
  /// nothing was open.
  bool _stepBack() {
    if (_overlay != _Overlay.none) {
      setState(() => _overlay = _Overlay.none);
      return true;
    }
    if (_mode == _DisplayMode.normal && _arrangement == _Arrangement.landscape && _columnPicker && _hasSelection) {
      setState(() => _columnPicker = false);
      return true;
    }
    if (_mode != _DisplayMode.normal) {
      unawaited(_setMode(_DisplayMode.normal));
      return true;
    }
    return false;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    return _stepBack();
  }

  Future<void> _setMode(_DisplayMode mode) async {
    if (!mounted || mode == _mode) return;
    final previous = _mode;
    setState(() {
      _mode = mode;
      _overlay = _Overlay.none;
      _barVisible = false;
    });
    if (!_mobile) {
      // The whole window on desktops (window_manager).
      if (mode == _DisplayMode.fullscreen || previous == _DisplayMode.fullscreen) {
        await DesktopWindow.setFullScreen(on: mode == _DisplayMode.fullscreen);
      }
      return;
    }
    try {
      if (mode == _DisplayMode.fullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await ScreenOrientation.landscape();
      } else if (previous == _DisplayMode.fullscreen) {
        await _restoreSystemUi();
      }
    } on Object {
      // The page keeps working without the system bars change.
    }
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  void _onBack(bool didPop) {
    if (didPop || _stepBack()) return;
    unawaited(_exitSafely());
  }

  /// Takes every video off the screen, lets two frames pass, then closes
  /// (3.x: the compositor must not draw a texture the engine is releasing).
  Future<void> _exitSafely() async {
    if (_exiting) return;
    setState(() => _exiting = true);
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final popped = await Navigator.of(context).maybePop();
    // Nothing to go back to (the first page): show the videos again.
    if (!popped && mounted) setState(() => _exiting = false);
  }

  // ---- build ----

  static _Arrangement _arrangementOf(Size size) {
    // A short and wide page is a landscape phone, whatever its width (5.1).
    if (size.height < 480 && size.width > size.height) return _Arrangement.landscape;
    if (size.width >= 840) return _Arrangement.wide;
    return _Arrangement.portrait;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _exiting,
    onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
    child: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          _arrangement = _arrangementOf(constraints.biggest);
          return _mode == _DisplayMode.normal ? _normal(context) : _bare(context, constraints.biggest);
        },
      ),
    ),
  );

  Widget _normal(BuildContext context) {
    final landscape = _arrangement == _Arrangement.landscape;
    return Scaffold(
      appBar: AppBar(
        centerTitle: !landscape,
        titleSpacing: landscape ? 0 : null,
        title: landscape
            ? Row(
                children: [
                  Text(i18n('multiview_title')),
                  const SizedBox(width: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          LayoutSegments(controller: _controller, onChanged: _setLayout),
                          const SizedBox(width: 8 - toolbarToggleInset),
                          ToolbarToggles(controller: _controller, onDanmakuSettings: _toggleDanmakuSettings),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Text(i18n('multiview_title')),
        actions: [
          IconButton(
            key: const ValueKey('multiview-immersive'),
            tooltip: i18n('multiview_immersive'),
            icon: const Icon(AppIcons.immersive),
            onPressed: () => unawaited(_setMode(_DisplayMode.immersive)),
          ),
          IconButton(
            key: const ValueKey('multiview-fullscreen'),
            tooltip: i18n('multiview_fullscreen'),
            icon: const Icon(AppIcons.gridFullscreen),
            onPressed: () => unawaited(_setMode(_DisplayMode.fullscreen)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) => switch (_arrangement) {
            _Arrangement.portrait => _portraitBody(box),
            _Arrangement.landscape => _landscapeBody(box),
            _Arrangement.wide => _wideBody(),
          },
        ),
      ),
    );
  }

  /// The layouts and the switches on a row of their own (portrait, wide).
  /// The switches' 48-point targets fill the row's height and reach into
  /// the padding beside them: the circles stay where they were.
  Widget _toolbar({required bool icons}) => Padding(
    key: const ValueKey('multiview-toolbar'),
    padding: EdgeInsets.fromLTRB(icons ? 16 : 12, 4, (icons ? 16 : 8) - toolbarToggleInset, 4),
    child: Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: LayoutSegments(
                  controller: _controller,
                  icons: icons,
                  // Narrow phones and 1+3's fourth switch: narrower segments
                  // before smaller words.
                  dense: !icons && box.maxWidth < LayoutSegments.width,
                  onChanged: _setLayout,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8 - toolbarToggleInset),
        ToolbarToggles(controller: _controller, onDanmakuSettings: _toggleDanmakuSettings),
      ],
    ),
  );

  /// c2: the 16:9 cells above, as tall as the width wants (at most half the
  /// page), the selected cell's controls and the picker below.
  Widget _portraitBody(BoxConstraints box) {
    final natural = WallGeometry.of(_controller.layout, width: box.maxWidth).size.height;
    final height = math.min(natural, box.maxHeight * 0.5);
    return Column(
      children: [
        _toolbar(icons: false),
        if (_controller.savedRooms.isNotEmpty) _restoreBar(),
        SizedBox(height: height, child: _wall()),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _controlsAndPicker()),
              if (_overlay == _Overlay.danmaku)
                Positioned.fill(
                  child: _danmakuPanel(
                    dragToClose: true,
                    radius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// c3: a landscape phone: the cells as tall as the page, the rest of the
  /// width for the column (the controls, or the picker while picking).
  Widget _landscapeBody(BoxConstraints box) {
    final restore = _controller.savedRooms.isNotEmpty;
    var wallWidth = box.maxWidth;
    if (!_folded) {
      final geometry = WallGeometry.of(
        _controller.layout,
        width: box.maxWidth - _minColumnWidth,
        height: box.maxHeight - (restore ? 52 : 0),
      );
      final column = (box.maxWidth - geometry.contentWidth - 6).clamp(_minColumnWidth, _columnWidth);
      wallWidth = box.maxWidth - column;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: wallWidth,
          child: Column(
            children: [
              if (restore) _restoreBar(),
              Expanded(child: _wallWithHandle()),
            ],
          ),
        ),
        if (!_folded) Expanded(child: _column(wide: false)),
      ],
    );
  }

  /// c3: tablets and desktops alike: the toolbar, the cells, and a 360-point
  /// column with the controls above the picker.
  Widget _wideBody() => Column(
    children: [
      _toolbar(icons: true),
      if (_controller.savedRooms.isNotEmpty) _restoreBar(),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _wallWithHandle(gap: 4)),
            if (!_folded) SizedBox(width: _columnWidth, child: _column(wide: true)),
          ],
        ),
      ),
    ],
  );

  Widget _wall({double gap = 3, Rect? avoid}) => MultiviewWall(
    layout: _controller.layout,
    count: _controller.cells.length,
    focused: _controller.focusedIndex,
    gap: gap,
    padding: gap,
    avoid: avoid,
    onAddCell: _controller.canAddCell ? _controller.addCell : null,
    onOffscreen: _setOffscreen,
    cellBuilder: _cell,
  );

  /// The wall with the column's fold handle on its right edge (22).
  Widget _wallWithHandle({double gap = 3}) => Stack(
    children: [
      Positioned.fill(child: _wall(gap: gap)),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: _FoldHandle(folded: _folded, onTap: () => setState(() => _folded = !_folded)),
      ),
    ],
  );

  /// The right column: the danmaku settings while open; else the controls
  /// and the picker (wide), or one of them (a landscape phone).
  Widget _column({required bool wide}) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (_overlay == _Overlay.danmaku) {
      child = _danmakuPanel();
    } else if (wide) {
      child = _controlsAndPicker(compact: true);
    } else if (_columnPicker || !_hasSelection) {
      child = MultiviewRoomPicker(
        shownIn: _shownIn,
        onPicked: _pick,
        header: _pickerHeader(onClose: _hasSelection ? () => setState(() => _columnPicker = false) : null),
      );
    } else {
      child = SingleChildScrollView(child: _controls(compact: true));
    }
    return DecoratedBox(
      key: const ValueKey('multiview-column'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: BorderDirectional(start: BorderSide(color: scheme.outlineVariant)),
      ),
      child: child,
    );
  }

  Widget _controlsAndPicker({bool compact = false}) {
    final selection = _hasSelection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selection) ...[_controls(compact: compact), const Divider(height: 1)],
        Expanded(
          child: MultiviewRoomPicker(shownIn: _shownIn, onPicked: _pick, header: _pickerHeader()),
        ),
      ],
    );
  }

  Widget _controls({required bool compact}) {
    final index = _selectedIndex;
    return MultiviewCellControls(
      key: ValueKey('multiview-controls-${_controller.cells[index].id}'),
      controller: _controller,
      index: index,
      compact: compact,
      onChangeRoom: () => _openPicker(index),
      onEnterRoom: (room) => unawaited(_openLiveRoom(room)),
    );
  }

  (String, String?) _pickerTitle() {
    final cells = _controller.cells;
    final target = _targetIndex.clamp(0, cells.length - 1);
    final room = cells[target].room;
    if (cells[target].stage == CellStage.empty || room == null) {
      return (i18n('multiview_pick_title', args: {'index': '${target + 1}'}), i18n('multiview_pick_hint'));
    }
    return (
      i18n('multiview_replace_title', args: {'index': '${target + 1}'}),
      i18n('multiview_replace_hint', args: {'name': room.displayNick(platformName(room.platform))}),
    );
  }

  Widget _pickerHeader({VoidCallback? onClose}) {
    final (title, hint) = _pickerTitle();
    return PickerHeader(title: title, hint: onClose == null ? hint : null, onClose: onClose);
  }

  Widget _danmakuPanel({bool dragToClose = false, BorderRadius? radius}) {
    final theme = Theme.of(context);
    return RoomSidePanel(
      key: const ValueKey('multiview-danmaku-panel'),
      title: i18n('danmaku_settings'),
      dragToClose: dragToClose,
      borderRadius: radius,
      onClose: () => setState(() => _overlay = _Overlay.none),
      actions: [
        Flexible(
          flex: 3,
          child: Text(
            i18n('multiview_danmaku_panel_hint'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.regular.copyWith(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
      child: const DanmakuSettingsContent(),
    );
  }

  Widget _restoreBar() {
    final count = _controller.savedRooms.whereType<LiveRoom>().length;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
          child: Row(
            children: [
              Icon(AppIcons.restoreLast, size: 18, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i18n('multiview_restore_hint', args: {'count': '$count'}),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, color: scheme.onSecondaryContainer),
                ),
              ),
              TextButton(onPressed: _controller.dismissSaved, child: Text(i18n('multiview_restore_dismiss'))),
              TextButton(
                key: const ValueKey('multiview-restore'),
                onPressed: () => unawaited(_controller.restoreLast()),
                child: Text(i18n('multiview_restore')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Immersive (the status bar stays) and fullscreen (no system bars): the
  /// cells alone on black, the same exit button in the top-left corner
  /// (c12), and a panel on the right (landscape) or at the bottom (portrait)
  /// for a long-pressed cell, the picker or the danmaku settings (c13).
  Widget _bare(BuildContext context, Size size) {
    final fullscreen = _mode == _DisplayMode.fullscreen;
    final padding = MediaQuery.paddingOf(context);
    // The exit button; the cells' marks keep clear of it (c12, 拿不准 2).
    final exit = Rect.fromLTWH(padding.left + 12, padding.top + 12, kMinInteractiveDimension, kMinInteractiveDimension);
    final wall = fullscreen
        ? MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: _wall(avoid: exit),
          )
        : SafeArea(child: _wall(avoid: exit.shift(Offset(-padding.left, -padding.top))));
    return Scaffold(
      backgroundColor: OnVideoColors.ground,
      body: Stack(
        children: [
          Positioned.fill(child: wall),
          Positioned.fromRect(
            rect: exit,
            child: _ExitButton(
              key: ValueKey(fullscreen ? 'multiview-fullscreen-exit' : 'multiview-immersive-exit'),
              icon: fullscreen ? AppIcons.gridExitFullscreen : AppIcons.exitImmersive,
              tooltip: i18n(fullscreen ? 'multiview_fullscreen_exit' : 'multiview_immersive_exit'),
              onTap: () => unawaited(_setMode(_DisplayMode.normal)),
            ),
          ),
          if (_overlay != _Overlay.none) _overlayPanel(size),
        ],
      ),
    );
  }

  Widget _overlayPanel(Size size) {
    final side = size.width > size.height;
    void close() => setState(() => _overlay = _Overlay.none);
    final panel = switch (_overlay) {
      _Overlay.danmaku => _danmakuPanel(
        dragToClose: !side,
        radius: _panelRadius(side: side),
      ),
      _Overlay.cell => RoomSidePanel(
        key: const ValueKey('multiview-cell-panel'),
        title: i18n('multiview_cell_number', args: {'index': '${_selectedIndex + 1}'}),
        dragToClose: !side,
        borderRadius: _panelRadius(side: side),
        onClose: close,
        child: SingleChildScrollView(child: _controls(compact: true)),
      ),
      _Overlay.picker || _Overlay.none => RoomSidePanel(
        key: const ValueKey('multiview-picker-panel'),
        title: _pickerTitle().$1,
        dragToClose: !side,
        borderRadius: _panelRadius(side: side),
        onClose: close,
        child: MultiviewRoomPicker(shownIn: _shownIn, onPicked: _pick),
      ),
    };
    if (side) {
      return Positioned(top: 0, bottom: 0, right: 0, width: math.min(_columnWidth, size.width / 2), child: panel);
    }
    final height = _overlay == _Overlay.cell ? math.min<double>(320, size.height * 0.6) : size.height * 0.55;
    return Positioned(left: 0, right: 0, bottom: 0, height: height, child: panel);
  }

  static BorderRadius _panelRadius({required bool side}) => side
      ? const BorderRadius.horizontal(left: Radius.circular(16))
      : const BorderRadius.vertical(top: Radius.circular(16));

  Widget _cell(int index, {required bool large, required double nameInset}) {
    final cells = _controller.cells;
    final cell = cells[index];
    final focusLayout = _controller.layout == MultiviewLayout.focus;
    final showDanmaku = _controller.danmakuEnabled && index == _controller.selectedIndex && cell.playing;
    final bar = large && focusLayout && _mode != _DisplayMode.normal && _barVisible;
    return MultiviewCellView(
      key: _cellKeys.putIfAbsent(cell.id, () => GlobalKey(debugLabel: 'multiview_cell_${cell.id}')),
      cell: cell,
      position: index + 1,
      audible: cell.playing && index == _controller.audioIndex && !_controller.allMuted,
      pickTarget: _pickerVisible && index == _targetIndex && cell.assignable,
      saver: focusLayout && _controller.smallCellsLowQuality && !large,
      showVideo: !_exiting,
      nameInset: nameInset,
      onTap: () => _onCellTap(index),
      onLongPress: cell.stage == CellStage.empty ? null : () => _onCellLongPress(index),
      onRetry: () => unawaited(_controller.retry(index)),
      danmaku: showDanmaku
          ? Consumer(
              builder: (context, ref, _) => DanmakuOverlay(
                messages: _controller.flying,
                retractions: _controller.retractions,
                look: danmakuLookOf(ref),
              ),
            )
          : null,
      footer: bar
          ? FocusControlBar(
              controller: _controller,
              index: index,
              fullscreen: _mode == _DisplayMode.fullscreen,
              onDanmakuSettings: () => setState(() => _overlay = _Overlay.danmaku),
              onVolume: () => setState(() {
                _selectedId = cell.id;
                _overlay = _Overlay.cell;
              }),
              onFullscreen: () =>
                  unawaited(_setMode(_mode == _DisplayMode.fullscreen ? _DisplayMode.normal : _DisplayMode.fullscreen)),
            )
          : null,
    );
  }
}

/// The handle on the column's edge that folds it away and back (22, as
/// U.2d's chat column).
class _FoldHandle extends StatelessWidget {
  const new({required this.folded, required this.onTap});

  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: i18n(folded ? 'multiview_unfold_column' : 'multiview_fold_column'),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(8))
            .resolve(Directionality.of(context)),
        child: InkWell(
          key: const ValueKey('multiview-fold'),
          onTap: onTap,
          child: SizedBox(
            width: 22,
            height: 56,
            child: Icon(folded ? AppIcons.unfoldLeft : AppIcons.foldRight, size: 20, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The round button that leaves the immersive and fullscreen modes: the same
/// place and look in both (c12).
class _ExitButton extends StatelessWidget {
  const new({required this.icon, required this.tooltip, required this.onTap, super.key});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: OnVideoColors.scrim,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Icon(icon, size: 22, color: OnVideoColors.foreground),
        ),
      ),
    ),
  );
}
