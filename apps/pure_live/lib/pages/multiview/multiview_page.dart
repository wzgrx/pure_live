import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/chat_panel.dart';
import 'package:pure_live/pages/live_play/danmaku_overlay.dart';
import 'package:pure_live/pages/live_play/player_view.dart';
import 'package:pure_live/pages/live_play/room_texts.dart';
import 'package:pure_live/pages/multiview/multiview_cell_view.dart';
import 'package:pure_live/pages/multiview/multiview_controller.dart';
import 'package:pure_live/pages/multiview/multiview_picker.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// Multi-view (3.x `lib/modules/multiview`): several rooms at once, one of
/// them audible, in a 1×1, 1×2, 2×2 or one-large grid.
///
/// Routes: `RoutePath.kMultiview`.
class MultiviewPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<MultiviewPage> createState() => _MultiviewPageState();
}

/// The page's chrome: everything, the grid with a restore button, or the
/// grid alone with the system bars hidden (3.x `_DisplayMode`).
enum _DisplayMode { normal, immersive, fullscreen }

bool get _mobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Wider than this (on desktop) the picker stays open beside the grid (3.x).
const double _wideBreakpoint = 680;

class _MultiviewPageState extends ConsumerState<MultiviewPage> {
  late final MultiviewController _controller;
  final Map<int, GlobalKey> _cellKeys = {};
  _DisplayMode _mode = _DisplayMode.normal;
  bool _exiting = false;
  bool _largeControls = false;
  int _target = 0;

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
      toast: (message) => AppNavigator.toast(message),
    )..addListener(_onControllerChanged);
    unawaited(_controller.start());
    HardwareKeyboard.instance.addHandler(_onKey);
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
    // A smaller layout may drop the cell the picker targets.
    final cells = _controller.cells;
    if (_target >= cells.length) _target = cells.length - 1;
    _cellKeys.removeWhere((id, _) => !cells.any((cell) => cell.id == id));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (_mode == _DisplayMode.fullscreen && _mobile) unawaited(_restoreSystemUi());
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  // ---- display modes and leaving ----

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || _mode == _DisplayMode.normal || ModalRoute.of(context)?.isCurrent != true) return false;
    unawaited(_setMode(_DisplayMode.normal));
    return true;
  }

  Future<void> _setMode(_DisplayMode mode) async {
    if (!mounted || mode == _mode) return;
    final previous = _mode;
    setState(() {
      _mode = mode;
      _largeControls = false;
    });
    if (!_mobile) return;
    try {
      if (mode == _DisplayMode.fullscreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
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
    if (didPop) return;
    if (_mode != _DisplayMode.normal) {
      unawaited(_setMode(_DisplayMode.normal));
      return;
    }
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

  // ---- picking ----

  bool _isWide(double width) => !_mobile && width > _wideBreakpoint && _mode == _DisplayMode.normal;

  int? _shownIn(LiveRoom room) {
    final index = _controller.indexOfRoom(room);
    return index < 0 ? null : index + 1;
  }

  void _pick(LiveRoom room, {int? cell}) {
    final cells = _controller.cells;
    final shown = _controller.indexOfRoom(room);
    if (shown >= 0) {
      // The same stream twice only costs a decoder: show the cell instead.
      AppNavigator.toast(i18n('multiview_already_shown', args: {'index': '${shown + 1}'}));
      unawaited(_select(shown));
      return;
    }
    final target = (cell ?? _target).clamp(0, cells.length - 1);
    unawaited(_controller.assign(target, room));
    // The next empty cell becomes the target, so rooms can be picked in a row.
    for (var step = 1; step < cells.length; step++) {
      final next = (target + step) % cells.length;
      if (cells[next].assignable && cells[next].stage == CellStage.empty) {
        setState(() => _target = next);
        return;
      }
    }
    setState(() {});
  }

  Future<void> _select(int index) async {
    if (_controller.layout == MultiviewLayout.focus) {
      await _controller.promote(index);
    } else {
      await _controller.setAudioFocus(index);
    }
  }

  Future<void> _openPicker(int index) async {
    setState(() => _target = index);
    if (_isWide(MediaQuery.sizeOf(context).width)) return;
    final room = await showRoomPickerSheet(context, shownIn: _shownIn);
    if (room != null && mounted) _pick(room, cell: index);
  }

  void _onCellTap(int index) {
    final cell = _controller.cells[index];
    switch (cell.stage) {
      case CellStage.playing:
        if (_controller.layout == MultiviewLayout.focus) {
          if (_controller.focusedIndex != index) {
            setState(() => _largeControls = false);
            unawaited(_controller.promote(index));
          } else {
            setState(() => _largeControls = !_largeControls);
          }
          return;
        }
        unawaited(_controller.setAudioFocus(index));
      case CellStage.empty || CellStage.offline || CellStage.failed:
        unawaited(_openPicker(index));
      case CellStage.resolving:
        break;
    }
  }

  Future<void> _openLiveRoom(LiveRoom room) async {
    final paused = await _controller.pauseAll();
    try {
      await AppNavigator.toNamed<void>(RoutePath.kLivePlay, arguments: room);
    } finally {
      if (mounted) unawaited(_controller.resumeCells(paused));
    }
  }

  // ---- sheets ----

  Future<void> _showActions(int index) async {
    final cell = _controller.cells[index];
    final room = cell.room;
    if (room == null) return;
    final playing = cell.playing;
    final lines = cell.playback.lineCount;
    final focusLayout = _controller.layout == MultiviewLayout.focus;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        Widget tile(String value, IconData icon, String label, {bool enabled = true, Color? color}) => ListTile(
          key: ValueKey('multiview-action-$value'),
          leading: Icon(icon, color: color),
          title: Text(label, style: color == null ? null : TextStyle(color: color)),
          enabled: enabled,
          onTap: () => Navigator.of(sheetContext).pop(value),
        );
        final paused = cell.playback.status == PlaybackStatus.paused;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(room.displayNick(platformName(room.platform))),
                  subtitle: Text(
                    i18n('multiview_cell_number', args: {'index': '${index + 1}'}),
                    style: context.textStyles.t12Muted,
                  ),
                ),
                const Divider(height: 1),
                if (playing) ...[
                  tile(
                    'play',
                    paused ? Remix.play_line : Remix.pause_line,
                    i18n(paused ? 'multiview_play' : 'multiview_pause'),
                  ),
                  if (!focusLayout && _controller.audioIndex != index)
                    tile('sound', Remix.volume_up_line, i18n('multiview_make_audible')),
                  tile('quality', Remix.hd_line, i18n('select_quality'), enabled: cell.qualities.length > 1),
                  if (lines > 1) tile('line', Remix.route_line, i18n('multiview_line_selector')),
                  tile('volume', Remix.volume_down_line, i18n('multiview_volume')),
                ],
                tile('refresh', Remix.refresh_line, i18n('multiview_refresh')),
                tile('room', Remix.external_link_line, i18n('multiview_open_room')),
                tile('change', Remix.tv_2_line, i18n('multiview_change_room')),
                tile(
                  'close',
                  Remix.close_circle_line,
                  i18n('multiview_close_cell'),
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'play':
        unawaited(_controller.togglePlay(index));
      case 'sound':
        unawaited(_controller.setAudioFocus(index));
      case 'quality':
        unawaited(_showQualities(index));
      case 'line':
        unawaited(_showLines(index));
      case 'volume':
        unawaited(_showVolume(index));
      case 'refresh':
        unawaited(_controller.retry(index, reload: true));
      case 'room':
        unawaited(_openLiveRoom(room));
      case 'change':
        unawaited(_openPicker(index));
      case 'close':
        unawaited(_controller.remove(index));
    }
  }

  Future<void> _showQualities(int index) async {
    final cell = _controller.cells[index];
    final qualities = cell.qualities;
    if (qualities.isEmpty) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < qualities.length; i++)
                ListTile(
                  title: Text(qualityLabel(qualities[i])),
                  trailing: i == cell.qualityIndex ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(sheetContext).pop(i),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) unawaited(_controller.selectQuality(index, chosen));
  }

  Future<void> _showLines(int index) async {
    final cell = _controller.cells[index];
    final state = cell.playback;
    if (state.lineCount < 2) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < state.lineCount; i++)
                ListTile(
                  title: Text(i18n('multiview_line', args: {'index': '${i + 1}'})),
                  trailing: i == state.lineIndex ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(sheetContext).pop(i),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) unawaited(_controller.selectLine(index, chosen));
  }

  Future<void> _showVolume(int index) async {
    final cell = _controller.cells[index];
    final room = cell.room;
    var value = cell.volume;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        room == null ? i18n('multiview_volume') : room.displayNick(platformName(room.platform)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                    Text('${(value * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Remix.volume_down_line),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('multiview-volume-slider'),
                        value: value,
                        onChanged: (next) {
                          setSheetState(() => value = next);
                          unawaited(_controller.setVolume(index, next));
                        },
                        onChangeEnd: (next) => unawaited(_controller.setVolume(index, next, save: true)),
                      ),
                    ),
                    const Icon(Remix.volume_up_line),
                  ],
                ),
                Text(
                  _controller.audioIndex == index ? i18n('room_volume') : i18n('multiview_volume_silent_hint'),
                  style: Theme.of(sheetContext).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDanmakuSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) =>
        SizedBox(height: MediaQuery.sizeOf(sheetContext).height * 0.72, child: const DanmakuSettingsPanel()),
  );

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _exiting,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => switch (_mode) {
          _DisplayMode.normal => Scaffold(
            appBar: AppBar(
              title: Text(i18n('multiview_title')),
              actions: [
                IconButton(
                  key: const ValueKey('multiview-immersive'),
                  tooltip: i18n('multiview_immersive'),
                  icon: const Icon(Remix.expand_diagonal_line),
                  onPressed: () => unawaited(_setMode(_DisplayMode.immersive)),
                ),
                IconButton(
                  key: const ValueKey('multiview-fullscreen'),
                  tooltip: i18n('multiview_fullscreen'),
                  icon: const Icon(Remix.fullscreen_line),
                  onPressed: () => unawaited(_setMode(_DisplayMode.fullscreen)),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = _isWide(constraints.maxWidth);
                  final content = Column(
                    children: [
                      _toolbar(constraints.maxWidth),
                      if (_controller.savedRooms.isNotEmpty) _restoreBar(),
                      Expanded(child: _grid()),
                    ],
                  );
                  if (!wide) return content;
                  return Row(
                    children: [
                      Expanded(child: content),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 320, child: _sidePanel()),
                    ],
                  );
                },
              ),
            ),
          ),
          _DisplayMode.immersive => Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(child: _grid()),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _FloatingExit(
                    key: const ValueKey('multiview-immersive-exit'),
                    icon: Remix.collapse_diagonal_line,
                    tooltip: i18n('multiview_immersive_exit'),
                    onTap: () => unawaited(_setMode(_DisplayMode.normal)),
                  ),
                ),
              ],
            ),
          ),
          _DisplayMode.fullscreen => Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                MediaQuery.removePadding(context: context, removeTop: true, removeBottom: true, child: _grid()),
                Positioned(
                  left: 0,
                  top: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _FloatingExit(
                        key: const ValueKey('multiview-fullscreen-exit'),
                        icon: Remix.fullscreen_exit_line,
                        tooltip: i18n('multiview_fullscreen_exit'),
                        onTap: () => unawaited(_setMode(_DisplayMode.normal)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        },
      ),
    );
  }

  Widget _toolbar(double width) {
    final theme = Theme.of(context);
    final layout = _controller.layout;
    final selector = SegmentedButton<MultiviewLayout>(
      key: const ValueKey('multiview-layouts'),
      showSelectedIcon: false,
      selected: {layout},
      onSelectionChanged: (selection) {
        setState(() => _largeControls = false);
        unawaited(_controller.setLayout(selection.first));
      },
      segments: const [
        ButtonSegment(value: MultiviewLayout.single, icon: Icon(Remix.aspect_ratio_line), label: Text('1×1')),
        ButtonSegment(value: MultiviewLayout.dual, icon: Icon(Remix.layout_column_line), label: Text('1×2')),
        ButtonSegment(value: MultiviewLayout.quad, icon: Icon(Remix.layout_grid_line), label: Text('2×2')),
        ButtonSegment(value: MultiviewLayout.focus, icon: Icon(Remix.focus_3_line), label: Text('1+3')),
      ],
    );
    Color tint({required bool on}) => on ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final selected = _controller.selectedIndex;
    final cells = _controller.cells;
    final canAdjust = selected < cells.length && cells[selected].playing;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('multiview-danmaku'),
          tooltip: i18n('danmaku'),
          isSelected: _controller.danmakuEnabled,
          icon: Icon(CustomIcons.danmaku_open, size: 22, color: tint(on: _controller.danmakuEnabled)),
          onPressed: () => _controller.setDanmakuEnabled(enabled: !_controller.danmakuEnabled),
        ),
        IconButton(
          key: const ValueKey('multiview-mute-all'),
          tooltip: i18n(_controller.allMuted ? 'multiview_unmute_all' : 'multiview_mute_all'),
          icon: Icon(
            _controller.allMuted ? Remix.volume_mute_line : Remix.volume_vibrate_line,
            size: 22,
            color: tint(on: _controller.allMuted),
          ),
          onPressed: _controller.toggleMuteAll,
        ),
        IconButton(
          key: const ValueKey('multiview-volume'),
          tooltip: i18n('multiview_volume'),
          icon: const Icon(Remix.volume_up_line, size: 22),
          onPressed: canAdjust ? () => unawaited(_showVolume(selected)) : null,
        ),
        IconButton(
          key: const ValueKey('multiview-saver'),
          tooltip: i18n('multiview_small_low_quality'),
          icon: Icon(Remix.speed_mini_line, size: 22, color: tint(on: _controller.smallCellsLowQuality)),
          onPressed: layout == MultiviewLayout.focus
              ? () => unawaited(_controller.setSmallCellsLowQuality(enabled: !_controller.smallCellsLowQuality))
              : null,
        ),
      ],
    );
    if (width < 680) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Column(
          children: [
            Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: selector),
            ),
            const SizedBox(height: 2),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(child: Center(child: selector)),
          const SizedBox(width: 8),
          actions,
        ],
      ),
    );
  }

  Widget _restoreBar() {
    final count = _controller.savedRooms.whereType<LiveRoom>().length;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(
            children: [
              Icon(Remix.history_line, size: 18, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  i18n('multiview_restore_hint', args: {'count': '$count'}),
                  style: context.textStyles.t13.copyWith(color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              TextButton(onPressed: _controller.dismissSaved, child: Text(i18n('multiview_restore_dismiss'))),
              FilledButton.tonal(
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

  Widget _sidePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            i18n('multiview_pick_for_cell', args: {'index': '${_target + 1}'}),
            style: context.textStyles.t15Bold,
          ),
        ),
        Expanded(
          child: MultiviewRoomPicker(shownIn: _shownIn, onPicked: _pick),
        ),
      ],
    );
  }

  Widget _grid() {
    final layout = _controller.layout;
    final cells = _controller.cells;
    final Widget content;
    if (layout == MultiviewLayout.focus) {
      content = _focusLayout(cells);
    } else {
      content = Column(
        children: [
          for (var row = 0; row < layout.rows; row++)
            Expanded(
              child: Row(
                children: [
                  for (var column = 0; column < layout.columns; column++)
                    if (row * layout.columns + column < cells.length)
                      Expanded(
                        child: Padding(padding: const EdgeInsets.all(3), child: _cell(row * layout.columns + column)),
                      ),
                ],
              ),
            ),
        ],
      );
    }
    return Padding(padding: const EdgeInsets.all(6), child: content);
  }

  /// The large cell and a column (landscape) or row (portrait) of small
  /// ones; three small cells fill it, more scroll (3.x).
  Widget _focusLayout(List<MultiviewCell> cells) {
    final big = _controller.focusedIndex.clamp(0, cells.length - 1);
    final others = [
      for (var i = 0; i < cells.length; i++)
        if (i != big) i,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxWidth < constraints.maxHeight;
        final large = Padding(padding: const EdgeInsets.all(3), child: _cell(big, large: true));
        final rail = LayoutBuilder(
          builder: (context, box) {
            final extent = (portrait ? box.maxWidth : box.maxHeight) / 3;
            Widget sized(Widget child) => SizedBox(
              width: portrait ? extent : null,
              height: portrait ? null : extent,
              child: Padding(padding: const EdgeInsets.all(3), child: child),
            );
            final children = [
              for (final index in others) sized(_cell(index)),
              if (_controller.canAddCell) sized(AddCellSlot(onTap: _controller.addCell)),
            ];
            return SingleChildScrollView(
              scrollDirection: portrait ? Axis.horizontal : Axis.vertical,
              child: portrait
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
                  : Column(children: children),
            );
          },
        );
        return portrait
            ? Column(
                children: [
                  Expanded(flex: 3, child: large),
                  Expanded(child: rail),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: large),
                  Expanded(child: rail),
                ],
              );
      },
    );
  }

  Widget _cell(int index, {bool large = false}) {
    final cells = _controller.cells;
    final cell = cells[index];
    final wide = _isWide(MediaQuery.sizeOf(context).width);
    final showDanmaku = _controller.danmakuEnabled && index == _controller.selectedIndex && cell.playing;
    return MultiviewCellView(
      key: _cellKeys.putIfAbsent(cell.id, () => GlobalKey(debugLabel: 'multiview_cell_${cell.id}')),
      cell: cell,
      position: index + 1,
      audible: cell.playing && index == _controller.audioIndex && !_controller.allMuted,
      pickTarget: wide && index == _target && cell.assignable,
      showVideo: !_exiting,
      onTap: () => _onCellTap(index),
      onActions: cell.stage == CellStage.empty ? null : () => unawaited(_showActions(index)),
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
      footer: large && cell.playing ? (_largeControls ? _controlBar(index) : _qualityChip(index)) : null,
    );
  }

  /// The quality of the large cell, tap to change (3.x's corner chip).
  Widget _qualityChip(int index) {
    final cell = _controller.cells[index];
    if (cell.qualities.isEmpty) return const SizedBox.shrink();
    final name = qualityLabel(cell.qualities[cell.qualityIndex.clamp(0, cell.qualities.length - 1)]);
    return Align(
      alignment: Alignment.bottomLeft,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const ValueKey('multiview-quality-chip'),
          borderRadius: BorderRadius.circular(10),
          onTap: cell.qualities.length > 1 ? () => unawaited(_showQualities(index)) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Remix.equalizer_line, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: context.textStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The large cell's controls (3.x: as the live room's bar).
  Widget _controlBar(int index) {
    final cell = _controller.cells[index];
    final session = cell.session;
    final color = Colors.white.withValues(alpha: 0.92);
    Widget button(String key, IconData icon, String tooltip, VoidCallback onTap, {Color? tint}) => IconButton(
      key: ValueKey('multiview-bar-$key'),
      tooltip: tooltip,
      icon: Icon(icon, size: 20, color: tint ?? color),
      onPressed: onTap,
    );
    return Container(
      key: const ValueKey('multiview-control-bar'),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session != null)
              StreamBuilder<PlaybackState>(
                stream: session.states,
                initialData: session.state,
                builder: (context, snapshot) {
                  final paused = snapshot.data?.status == PlaybackStatus.paused;
                  return button(
                    'play',
                    paused ? Remix.play_line : Remix.pause_line,
                    i18n(paused ? 'multiview_play' : 'multiview_pause'),
                    () => unawaited(_controller.togglePlay(index)),
                  );
                },
              ),
            button(
              'refresh',
              Remix.refresh_line,
              i18n('multiview_refresh'),
              () => unawaited(_controller.retry(index, reload: true)),
            ),
            button(
              'danmaku',
              CustomIcons.danmaku_open,
              i18n('danmaku'),
              () => _controller.setDanmakuEnabled(enabled: !_controller.danmakuEnabled),
              tint: _controller.danmakuEnabled ? Theme.of(context).colorScheme.primary : null,
            ),
            button(
              'danmaku-settings',
              Remix.settings_3_line,
              i18n('multiview_danmaku_settings'),
              () => unawaited(_showDanmakuSettings()),
            ),
            if (cell.qualities.length > 1)
              button('quality', Remix.hd_line, i18n('select_quality'), () => unawaited(_showQualities(index))),
            if (cell.playback.lineCount > 1)
              button('line', Remix.route_line, i18n('multiview_line_selector'), () => unawaited(_showLines(index))),
            button('volume', Remix.volume_down_line, i18n('multiview_volume'), () => unawaited(_showVolume(index))),
            button(
              'fullscreen',
              _mode == _DisplayMode.fullscreen ? Remix.fullscreen_exit_line : Remix.fullscreen_line,
              i18n(_mode == _DisplayMode.fullscreen ? 'multiview_fullscreen_exit' : 'multiview_fullscreen'),
              () =>
                  unawaited(_setMode(_mode == _DisplayMode.fullscreen ? _DisplayMode.normal : _DisplayMode.fullscreen)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quality's label; "?" marks one the platform has not confirmed (as the
/// live room).
String qualityLabel(LivePlayQuality quality) => quality.isPlaybackUnconfirmed ? '${quality.quality}?' : quality.quality;

/// A round button that leaves immersive or fullscreen mode.
class _FloatingExit extends StatelessWidget {
  const new({required this.icon, required this.tooltip, required this.onTap, super.key});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black.withValues(alpha: 0.68),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Icon(icon, size: 22, color: Colors.white),
        ),
      ),
    ),
  );
}
