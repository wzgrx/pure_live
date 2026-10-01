import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The width a stream menu never goes below (docs/ui/compare/U.2f).
const double streamMenuMinWidth = 128;

/// The quality and line buttons, "原画 ⌄" "线路1 ⌄" (3.x `ResolutionSelector`
/// and `LineSelector`), in the room strip and in the fullscreen bar alike
/// (U.2f: every client has the same two buttons and the same small menu).
/// [onVideo] draws them white on the picture; there the menus open above the
/// buttons when they fit ([preferAbove]).
class StreamPickers extends StatelessWidget {
  /// Creates the pickers.
  const new({
    required this.controller,
    this.onVideo = false,
    this.preferAbove = false,
    this.onReopen,
    this.onMenu,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// White on the picture.
  final bool onVideo;

  /// Open the menus above the buttons when there is room (the fullscreen
  /// bar along the bottom).
  final bool preferAbove;

  /// Called before the user asks for another quality or line.
  final VoidCallback? onReopen;

  /// Told when a menu opens (true) and closes (false): the player keeps its
  /// controls up meanwhile.
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context) => ListenableSelector<(RoomStage, int, int, bool, bool, String)>(
    listenable: controller,
    selector: () => (
      controller.stage,
      controller.qualities.length,
      controller.qualityIndex,
      controller.switching,
      controller.switchingLine,
      controller.qualities.map((quality) => '${quality.quality}${quality.isPlaybackUnconfirmed ? '?' : ''}').join('|'),
    ),
    builder: (context, value, _) {
      final (stage, count, _, switchingQuality, switchingLine, _) = value;
      if (stage != RoomStage.playing || count == 0) return const SizedBox.shrink();
      final qualities = controller.qualities;
      final index = controller.qualityIndex.clamp(0, qualities.length - 1);
      final current = qualities[index];
      final switching = switchingQuality || switchingLine;
      return StreamBuilder<PlaybackState>(
        stream: controller.session.states,
        initialData: controller.session.state,
        builder: (context, snapshot) {
          final playback = snapshot.data ?? controller.session.state;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamMenuButton(
                key: const ValueKey('live-play-quality'),
                entryKey: 'live-play-quality-item',
                tooltip: i18n('select_quality'),
                label: current.isPlaybackUnconfirmed ? '${current.quality}?' : current.quality,
                entries: [for (final quality in qualities) quality.quality],
                current: index,
                busy: switchingQuality,
                enabled: !switching,
                onVideo: onVideo,
                preferAbove: preferAbove,
                onMenu: onMenu,
                onSelected: (selected) {
                  if (selected == index) return;
                  onReopen?.call();
                  unawaited(controller.selectQuality(selected));
                },
              ),
              // 3.x showed the line button whenever there was a source.
              if (playback.lineCount > 0)
                StreamMenuButton(
                  key: const ValueKey('live-play-line'),
                  entryKey: 'live-play-line-item',
                  tooltip: i18n('select_play_line'),
                  label: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                  entries: [
                    for (var line = 0; line < playback.lineCount; line++)
                      i18n('toolbox_line', args: {'index': '${line + 1}'}),
                  ],
                  current: playback.lineIndex,
                  busy: switchingLine,
                  enabled: !switching,
                  onVideo: onVideo,
                  preferAbove: preferAbove,
                  onMenu: onMenu,
                  onSelected: (selected) {
                    if (selected == playback.lineIndex) return;
                    onReopen?.call();
                    unawaited(controller.selectLine(selected));
                  },
                ),
            ],
          );
        },
      );
    },
  );
}

/// A button with the current choice and a drop-down mark that opens a small
/// menu of [entries] next to itself (3.x's `PopupMenuButton` of the room
/// strip, docs/ui/compare/U.2f): 14-point text on 48-high rows, at least
/// [streamMenuMinWidth] wide and otherwise as wide as its text, on
/// `surfaceContainerHighest` with 8-point corners; the current entry in the
/// primary colour, bold, with a tick. A choice applies at once and closes
/// the menu; Esc, a tap outside and Back close it too; arrows and Enter
/// work as in every Material menu. The mark points up while the menu is
/// open; [busy] spins in the button while a switch resolves.
class StreamMenuButton extends StatefulWidget {
  /// Creates the button.
  const new({
    required this.label,
    required this.entries,
    required this.current,
    required this.onSelected,
    required this.tooltip,
    this.entryKey = 'stream-menu-item',
    this.busy = false,
    this.enabled = true,
    this.onVideo = false,
    this.preferAbove = false,
    this.onMenu,
    super.key,
  });

  /// The current choice.
  final String label;

  /// The choices, in the platform's order.
  final List<String> entries;

  /// The index of the current choice.
  final int current;

  /// Receives the chosen index.
  final ValueChanged<int> onSelected;

  /// What the button does.
  final String tooltip;

  /// The key prefix of the menu rows (`<prefix>-<index>`).
  final String entryKey;

  /// A switch resolves: a spinner, no taps.
  final bool busy;

  /// Whether the button takes taps.
  final bool enabled;

  /// White on the picture.
  final bool onVideo;

  /// Open above the button when the menu fits there.
  final bool preferAbove;

  /// Told when the menu opens and closes.
  final ValueChanged<bool>? onMenu;

  @override
  State<StreamMenuButton> createState() => _StreamMenuButtonState();
}

class _StreamMenuButtonState extends State<StreamMenuButton> {
  bool _open = false;

  /// Below the button unless only the space above takes the menu (or the
  /// button prefers above and the menu fits there).
  RelativeRect _position(int count) {
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final padding = MediaQuery.paddingOf(context);
    // Rows of 48 and the menu's own 8 above and below (Material's menu).
    final height = count * kMinInteractiveDimension + 16;
    const gap = 4.0;
    final below = overlay.size.height - padding.bottom - rect.bottom - gap;
    final above = rect.top - padding.top - gap;
    final up = widget.preferAbove ? height <= above || above > below : height > below && above > below;
    final top = up ? rect.top - gap - height : rect.bottom + gap;
    return RelativeRect.fromLTRB(rect.left, top, overlay.size.width - rect.right, overlay.size.height - top);
  }

  Future<void> _show() async {
    if (_open || widget.entries.isEmpty) return;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme.bodyMedium?.copyWith(fontSize: 14);
    setState(() => _open = true);
    widget.onMenu?.call(true);
    final chosen = await showMenu<int>(
      context: context,
      position: _position(widget.entries.length),
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      constraints: const BoxConstraints(minWidth: streamMenuMinWidth, maxWidth: 280),
      items: [
        for (final (index, entry) in widget.entries.indexed)
          PopupMenuItem<int>(
            key: ValueKey('${widget.entryKey}-$index'),
            value: index,
            child: Row(
              children: [
                Text(
                  entry,
                  style: index == widget.current
                      ? text?.emphasis.copyWith(color: scheme.primary)
                      : text?.regular.copyWith(color: scheme.onSurface),
                ),
                if (index == widget.current) ...[
                  const SizedBox(width: 16),
                  const Spacer(),
                  Icon(AppIcons.selected, size: 18, color: scheme.primary),
                ],
              ],
            ),
          ),
      ],
    );
    if (mounted) setState(() => _open = false);
    widget.onMenu?.call(false);
    if (chosen != null) widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onVideo = widget.onVideo;
    final ink = onVideo ? OnVideoColors.foreground : scheme.onSurface;
    final style = theme.textTheme.bodyMedium?.regular.copyWith(
      color: ink,
      shadows: onVideo ? OnVideoColors.shadows : null,
    );
    final enabled = widget.enabled && !widget.busy;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => unawaited(_show()) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension, minWidth: kMinInteractiveDimension),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Center(
              child: SizedBox(
                height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: onVideo ? OnVideoColors.chip : null,
                    border: Border.all(
                      color: _open && !onVideo
                          ? scheme.primary
                          : (onVideo ? OnVideoColors.chipOutline : scheme.outlineVariant),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, right: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.busy) ...[
                          SizedBox.square(
                            key: const ValueKey('stream-menu-busy'),
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.8, color: ink),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(widget.label, style: style, maxLines: 1),
                        const SizedBox(width: 2),
                        Icon(_open ? AppIcons.foldUp : AppIcons.dropDown, size: 18, color: ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
