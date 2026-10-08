import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// A quality's label; "?" marks one the platform has not confirmed (as the
/// live room).
String qualityLabel(LivePlayQuality quality) =>
    '${platformQualityName(quality.quality)}${quality.isPlaybackUnconfirmed ? '?' : ''}';

/// The visible size of a control button (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面, `.sr2 .ib`).
const double _buttonSize = 40;

/// How far a button's 48-point tap target reaches past its circle on each
/// side (UI_PLAN 5.4): the padding next to the buttons is shorter by this
/// much so the circles keep their places.
const double _buttonInset = (kMinInteractiveDimension - _buttonSize) / 2;

/// The five buttons side by side.
const double _buttonsWidth = 5 * kMinInteractiveDimension;

/// The controls' padding at the start: the room, the menus and the volume
/// start 12 in, the first button's circle too.
const double _start = 12 - _buttonInset;

/// The narrowest slider (with its padding) kept after the buttons on the
/// portrait row: a 40-point track, the narrowest the row had with the
/// smaller targets (360 wide). Narrower, the volume takes a row of its own.
const double _minInlineSlider = 64;

/// The selected cell's controls, all in one place and the same in every
/// layout (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面 c4): the room with the cell's number; the
/// quality and line buttons with their small menus (U.2f); pause, refresh,
/// change room, open the live room, close the cell; the room volume.
///
/// Under the picture in portrait ([compact] false: the quality and line on
/// the room's row, the buttons and the volume on one row, the volume on its
/// own row when the phone is too narrow for both); in the right column and
/// the fullscreen panel each on a row of its own ([compact]). The buttons
/// are 40 in 48-point tap targets (UI_PLAN 5.4).
/// Rebuilds only when this cell changes.
class MultiviewCellControls extends StatelessWidget {
  /// Creates the controls of cell [index].
  const new({
    required this.controller,
    required this.index,
    required this.onChangeRoom,
    required this.onEnterRoom,
    this.compact = false,
    this.onMenu,
    super.key,
  });

  /// The page's controller.
  final MultiviewController controller;

  /// The cell.
  final int index;

  /// Each control on a row of its own (a narrow column).
  final bool compact;

  /// "换台": the picker fills this cell next.
  final VoidCallback onChangeRoom;

  /// "进入直播间".
  final ValueChanged<LiveRoom> onEnterRoom;

  /// Told when a quality or line menu opens and closes.
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context) => ListenableSelector<Object>(
    listenable: controller,
    selector: () {
      final cells = controller.cells;
      if (index >= cells.length) return const [];
      final cell = cells[index];
      return Object.hash(
        cell.id,
        cell.stage,
        cell.room?.identityKey,
        cell.room?.nick,
        cell.room?.title,
        cell.room?.avatar,
        cell.qualityIndex,
        cell.switching,
        cell.volume,
        Object.hashAll([for (final quality in cell.qualities) qualityLabel(quality)]),
        cell.session,
      );
    },
    builder: (context, _, _) {
      final cells = controller.cells;
      if (index >= cells.length) return const SizedBox.shrink();
      final cell = cells[index];
      final room = cell.room;
      if (cell.stage == CellStage.empty || room == null) return const SizedBox.shrink();
      final header = _RoomRow(room: room, position: index + 1);
      final streams = _StreamButtons(controller: controller, index: index, cell: cell, onMenu: onMenu);
      final buttons = _Buttons(
        controller: controller,
        index: index,
        cell: cell,
        onChangeRoom: onChangeRoom,
        onEnterRoom: () => onEnterRoom(room),
      );
      _VolumeRow volume({required double lead}) => _VolumeRow(
        key: ValueKey('multiview-volume-${cell.id}'),
        lead: lead,
        value: cell.volume,
        onChanged: (value) => unawaited(controller.setVolume(index, value)),
        onChangeEnd: (value) => unawaited(controller.setVolume(index, value, save: true)),
      );
      // On a row of its own the volume's icon lines up with the room's
      // avatar, as before.
      final volumeRow = volume(lead: 20 - _start);
      const indent = EdgeInsetsDirectional.only(start: _buttonInset);
      return Padding(
        key: ValueKey('multiview-cell-controls-${index + 1}'),
        padding: const EdgeInsetsDirectional.fromSTEB(_start, 6, 8, 6),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(padding: indent, child: header),
                  Padding(
                    padding: indent,
                    child: Align(alignment: AlignmentDirectional.centerStart, child: streams),
                  ),
                  Align(alignment: AlignmentDirectional.centerStart, child: buttons),
                  volumeRow,
                ],
              )
            : LayoutBuilder(
                builder: (context, box) {
                  // The volume after the buttons while its slider keeps a
                  // usable track (8 between the last circle and its icon).
                  final inline =
                      box.maxWidth - _buttonsWidth - _VolumeRow.chrome(lead: 8 - _buttonInset) >= _minInlineSlider;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: indent,
                        child: Row(
                          children: [
                            Expanded(child: header),
                            streams,
                          ],
                        ),
                      ),
                      if (inline)
                        Row(
                          children: [
                            buttons,
                            Expanded(child: volume(lead: 8 - _buttonInset)),
                          ],
                        )
                      else ...[
                        Align(alignment: AlignmentDirectional.centerStart, child: buttons),
                        volumeRow,
                      ],
                    ],
                  );
                },
              ),
      );
    },
  );
}

/// The avatar, the cell's number, the streamer, the platform and title.
class _RoomRow extends StatelessWidget {
  const new({required this.room, required this.position});

  final LiveRoom room;
  final int position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final platform = platformName(room.platform);
    final title = room.title.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        spacing: 10,
        children: [
          CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, radius: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Container(
                      key: const ValueKey('multiview-controls-number'),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$position',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)
                            .tabular,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        room.displayNick(platform),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.emphasis.copyWith(fontSize: 15, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
                Text(
                  title.isEmpty ? platform : '$platform · $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.regular.copyWith(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "原画 ⌄" "线路1 ⌄": the live room's buttons and menus (U.2f).
class _StreamButtons extends StatelessWidget {
  const new({required this.controller, required this.index, required this.cell, required this.onMenu});

  final MultiviewController controller;
  final int index;
  final MultiviewCell cell;
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context) {
    final session = cell.session;
    final qualities = cell.qualities;
    if (!cell.playing || session == null || qualities.isEmpty) return const SizedBox.shrink();
    final current = cell.qualityIndex.clamp(0, qualities.length - 1);
    return StreamBuilder<PlaybackState>(
      stream: session.states,
      initialData: session.state,
      builder: (context, snapshot) {
        final playback = snapshot.data ?? session.state;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamMenuButton(
              key: const ValueKey('multiview-quality'),
              entryKey: 'multiview-quality-item',
              tooltip: i18n('select_quality'),
              label: qualityLabel(qualities[current]),
              entries: [for (final quality in qualities) platformQualityName(quality.quality)],
              current: current,
              busy: cell.switching,
              enabled: !cell.switching,
              onMenu: onMenu,
              onSelected: (selected) => unawaited(controller.selectQuality(index, selected)),
            ),
            if (playback.lineCount > 0)
              StreamMenuButton(
                key: const ValueKey('multiview-line'),
                entryKey: 'multiview-line-item',
                tooltip: i18n('select_play_line'),
                label: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                entries: [
                  for (var line = 0; line < playback.lineCount; line++)
                    i18n('toolbox_line', args: {'index': '${line + 1}'}),
                ],
                current: playback.lineIndex,
                enabled: !cell.switching,
                onMenu: onMenu,
                onSelected: (selected) {
                  if (selected != playback.lineIndex) unawaited(controller.selectLine(index, selected));
                },
              ),
          ],
        );
      },
    );
  }
}

/// Pause, refresh, change room, open the live room, close the cell.
class _Buttons extends StatelessWidget {
  const new({
    required this.controller,
    required this.index,
    required this.cell,
    required this.onChangeRoom,
    required this.onEnterRoom,
  });

  final MultiviewController controller;
  final int index;
  final MultiviewCell cell;
  final VoidCallback onChangeRoom;
  final VoidCallback onEnterRoom;

  /// A 40-point button in a 48-point tap target (UI_PLAN 5.4; it looks the
  /// same), on every platform.
  static final ButtonStyle _target = IconButton.styleFrom(
    fixedSize: const Size.square(_buttonSize),
    minimumSize: const Size.square(_buttonSize),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(String key, IconData icon, String tooltip, VoidCallback? onPressed, {Color? color}) => IconButton(
      key: ValueKey('multiview-control-$key'),
      tooltip: tooltip,
      style: _target,
      color: color ?? scheme.onSurfaceVariant,
      iconSize: 22,
      onPressed: onPressed,
      icon: Icon(icon),
    );
    final session = cell.session;
    final play = session == null || !cell.playing
        ? button('play', AppIcons.cellPause, i18n('multiview_pause'), null)
        : StreamBuilder<PlaybackState>(
            stream: session.states,
            initialData: session.state,
            builder: (context, snapshot) {
              final paused = (snapshot.data ?? session.state).status == PlaybackStatus.paused;
              return button(
                'play',
                paused ? AppIcons.cellPlay : AppIcons.cellPause,
                i18n(paused ? 'multiview_play' : 'multiview_pause'),
                () => unawaited(controller.togglePlay(index)),
              );
            },
          );
    // Side by side: the targets leave 8 between the circles. A column too
    // narrow for five wraps rather than overflows.
    return Wrap(
      children: [
        play,
        button(
          'refresh',
          AppIcons.cellRefresh,
          i18n('multiview_refresh'),
          () => unawaited(controller.retry(index, reload: true)),
        ),
        button('change', AppIcons.changeRoom, i18n('multiview_change_room'), onChangeRoom),
        button('room', AppIcons.enterRoom, i18n('multiview_open_room'), onEnterRoom),
        button(
          'close',
          AppIcons.closeCell,
          i18n('multiview_close_this_cell'),
          () => unawaited(controller.remove(index)),
          color: scheme.error,
        ),
      ],
    );
  }
}

/// The room volume: the slider follows the finger, the room keeps the value
/// when the finger lifts (3.x `_showVolumeSheet`).
class _VolumeRow extends StatefulWidget {
  const new({required this.lead, required this.value, required this.onChanged, required this.onChangeEnd, super.key});

  /// The width of everything but the slider after [lead].
  static double chrome({required double lead}) => lead + _iconSize + _valueWidth;

  static const double _iconSize = 20;
  static const double _valueWidth = 40;

  /// The space before the icon.
  final double lead;

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = (_dragging ?? widget.value).clamp(0.0, 1.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          SizedBox(width: widget.lead),
          Icon(AppIcons.cellVolume, size: _VolumeRow._iconSize, color: scheme.onSurfaceVariant),
          Expanded(
            child: Slider(
              key: const ValueKey('multiview-volume-slider'),
              value: value,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              semanticFormatterCallback: (value) => '${i18n('room_volume')} ${(value * 100).round()}%',
              onChanged: (next) {
                setState(() => _dragging = next);
                widget.onChanged(next);
              },
              onChangeEnd: (next) {
                setState(() => _dragging = null);
                widget.onChangeEnd(next);
              },
            ),
          ),
          SizedBox(
            width: _VolumeRow._valueWidth,
            child: Text(
              '${(value * 100).round()}%',
              key: const ValueKey('multiview-volume-value'),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)
                  .tabular,
            ),
          ),
        ],
      ),
    );
  }
}
