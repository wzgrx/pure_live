import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// One cell on screen (3.x `_MultiviewCellView`, docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面 c6–c8):
/// black in every theme with white words; its number, platform and name in
/// the top-left corner; the audible cell outlined with a "声音来源" mark; the
/// cell the picker fills framed with a dashed line; and the empty, opening,
/// playing, paused, offline and failed states.
class MultiviewCellView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.cell,
    required this.position,
    required this.audible,
    required this.pickTarget,
    required this.onTap,
    required this.onLongPress,
    required this.onRetry,
    this.saver = false,
    this.showVideo = true,
    this.keepScreenOn = true,
    this.nameInset = 0,
    this.danmaku,
    this.footer,
    super.key,
  });

  /// The cell.
  final MultiviewCell cell;

  /// 1-based number of the cell.
  final int position;

  /// The cell's sound plays: a 2-point outline and the "声音来源" mark.
  final bool audible;

  /// The picker fills this cell: a dashed frame (and "正在为这一格选台" when
  /// it is empty).
  final bool pickTarget;

  /// A small cell that plays the lowest quality ("省流").
  final bool saver;

  /// Tap on the cell.
  final VoidCallback onTap;

  /// Long press and right click (null on an empty cell).
  final VoidCallback? onLongPress;

  /// Plays the cell again after a failure.
  final VoidCallback onRetry;

  /// False while the page closes (the video leaves the tree first).
  final bool showVideo;

  /// The screen stays on while the cell plays ("屏幕常亮", N01.2 c4).
  final bool keepScreenOn;

  /// Moves the corner marks right, past a button over the cell's corner
  /// (the fullscreen exit on a screen without black sides).
  final double nameInset;

  /// The flying danmaku over the video.
  final Widget? danmaku;

  /// Along the bottom of a playing cell (the large cell's controls).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final session = cell.session;
    final video = cell.playing && session != null && showVideo;
    final accent = OnVideoColors.accent(Theme.of(context).colorScheme);
    return ColoredBox(
      color: OnVideoColors.ground,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('multiview-cell-$position'),
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final small = constraints.maxHeight < 90 || constraints.maxWidth < 160;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (video) ...[
                    LiveVideoView(
                      session: session,
                      outputSize: defaultTargetPlatform == TargetPlatform.windows,
                      keepScreenOn: keepScreenOn,
                    ),
                    if (danmaku case final layer?) Positioned.fill(child: IgnorePointer(child: layer)),
                    StreamBuilder<PlaybackState>(
                      stream: session.states,
                      initialData: session.state,
                      builder: (context, snapshot) => _PlaybackLayer(
                        state: snapshot.data ?? session.state,
                        switching: cell.switching,
                        small: small,
                        onRetry: onRetry,
                      ),
                    ),
                  ] else
                    _Placeholder(cell: cell, pickTarget: pickTarget, small: small, accent: accent, onRetry: onRetry),
                  Positioned(
                    top: 6,
                    left: 6 + nameInset,
                    right: 6,
                    child: _CornerMarks(
                      position: position,
                      room: cell.stage == CellStage.empty ? null : cell.room,
                      audible: audible,
                      compact: constraints.maxWidth < 160,
                    ),
                  ),
                  if (saver && video)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _Mark(
                        key: const ValueKey('multiview-saver-mark'),
                        child: Text(i18n('multiview_saver_mark'), style: _markStyle(context)),
                      ),
                    ),
                  if (footer case final bar? when video) Positioned(left: 8, right: 8, bottom: 8, child: bar),
                  if (audible)
                    IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('multiview-audio-outline'),
                        decoration: BoxDecoration(border: Border.all(color: accent, width: 2)),
                      ),
                    ),
                  if (pickTarget)
                    IgnorePointer(
                      child: CustomPaint(key: const ValueKey('multiview-pick-frame'), painter: _DashedFrame(accent)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A mark's text: the small size, or the body size with [body] (12 and 13
/// by default, A01.2), semi-bold unless [weight] says otherwise.
TextStyle _markStyle(BuildContext context, {bool body = false, FontWeight weight = FontWeight.w600}) {
  final text = Theme.of(context).textTheme;
  return text.bodySmall!.copyWith(
    fontSize: body ? text.bodyMedium?.fontSize : null,
    height: 1.2,
    fontWeight: weight,
    color: OnVideoColors.foreground,
  );
}

/// A dark rounded mark on the picture (number, name, "省流").
class _Mark extends StatelessWidget {
  const new({required this.child, this.color = OnVideoColors.scrim, this.padding, super.key});

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 6),
        // Centred in the 20-point minimum, as small as the words otherwise.
        child: Align(widthFactor: 1, heightFactor: 1, child: child),
      ),
    ),
  );
}

/// The number, the room and the "声音来源" mark in the top-left corner.
class _CornerMarks extends StatelessWidget {
  const new({required this.position, required this.room, required this.audible, required this.compact});

  final int position;
  final LiveRoom? room;
  final bool audible;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _Mark(
          key: ValueKey('multiview-cell-number-$position'),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text('$position', style: _markStyle(context).tabular),
        ),
        if (room != null) ...[
          const SizedBox(width: 4),
          Flexible(
            child: _Mark(
              padding: const EdgeInsets.only(left: 5, right: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlatformLogo(room.platform, size: 12),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      room.displayNick(platformName(room.platform)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _markStyle(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (audible) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: i18n('multiview_audio_focus_badge'),
            child: _Mark(
              key: const ValueKey('multiview-audio-badge'),
              color: scheme.primary,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.audioFocus, size: 12, color: scheme.onPrimary),
                  if (!compact) ...[
                    const SizedBox(width: 3),
                    Text(
                      i18n('multiview_audio_focus_badge'),
                      style: _markStyle(context).copyWith(color: scheme.onPrimary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The cell without a picture: empty, opening, offline, failed.
class _Placeholder extends StatelessWidget {
  const new({
    required this.cell,
    required this.pickTarget,
    required this.small,
    required this.accent,
    required this.onRetry,
  });

  final MultiviewCell cell;
  final bool pickTarget;
  final bool small;
  final Color accent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = _markStyle(context, body: true);
    final muted = _markStyle(context, weight: FontWeight.w400).copyWith(color: OnVideoColors.secondary);
    final room = cell.room;
    if (small && cell.stage == CellStage.empty) {
      // A small empty cell puts the + beside its words, so both keep their
      // size (12 and 20) instead of shrinking to fit (A01.4 c5: the column
      // scaled "点击选台" down to about 7).
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 26, 8, 6),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pickTarget ? accent.withValues(alpha: 0.25) : OnVideoColors.chip,
                  ),
                  child: const Icon(AppIcons.addCell, size: 20, color: OnVideoColors.foreground),
                ),
                Text(
                  i18n(pickTarget ? 'multiview_pick_target_short' : 'multiview_empty_cell_hint'),
                  key: const ValueKey('multiview-cell-hint'),
                  style: _markStyle(context),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final children = switch (cell.stage) {
      CellStage.empty => [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pickTarget ? accent.withValues(alpha: 0.25) : OnVideoColors.chip,
          ),
          child: const Icon(AppIcons.addCell, size: 22, color: OnVideoColors.foreground),
        ),
        Text(
          i18n(pickTarget ? 'multiview_pick_target' : 'multiview_empty_cell_hint'),
          textAlign: TextAlign.center,
          style: title,
        ),
      ],
      CellStage.resolving || CellStage.playing => [
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: OnVideoColors.foreground),
        ),
        if (!small) Text(i18n('multiview_opening'), style: muted),
      ],
      CellStage.offline => [
        const Icon(AppIcons.roomOffline, size: 26, color: OnVideoColors.secondary),
        Text(
          switch (room?.effectiveLiveStatus) {
            // v4 tells a ban, a rerun loop and an unknown state apart.
            LiveStatus.banned || LiveStatus.carousel || LiveStatus.unknown => offlineText(room!),
            _ => i18n('multiview_room_offline'),
          },
          textAlign: TextAlign.center,
          style: title,
        ),
        if (!small) Text(i18n('multiview_room_offline_hint'), textAlign: TextAlign.center, style: muted),
      ],
      CellStage.failed => [
        const Icon(AppIcons.cellFailed, size: 26, color: OnVideoColors.error),
        Text(i18n('multiview_play_failed'), textAlign: TextAlign.center, style: title),
        if (!small) ...[
          Text(
            cellFailureText(cell.failure),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: muted,
          ),
          _RetryButton(key: ValueKey('multiview-retry-${cell.id}'), onPressed: onRetry),
        ],
      ],
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 26, 12, 8),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: children),
          ),
        ),
      ),
    );
  }
}

/// "重试" on a failed cell.
class _RetryButton extends StatelessWidget {
  const new({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.only(left: 10, right: 14),
        textStyle: Theme.of(context).textTheme.bodyMedium?.emphasis,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      onPressed: onPressed,
      icon: const Icon(AppIcons.cellRefresh, size: 16),
      label: Text(i18n('retry')),
    ),
  );
}

/// Why a cell failed, in words (never the platform's raw text; 3.x showed
/// the exception's `toString`).
String cellFailureText(Object? failure) => switch (failure) {
  UnsupportedPlatform() => i18n('platform_retired'),
  _ => failureText(failure),
};

/// The session's state over the video: loading, paused ("已暂停"), failed.
class _PlaybackLayer extends StatelessWidget {
  const new({required this.state, required this.switching, required this.small, required this.onRetry});

  final PlaybackState state;
  final bool switching;
  final bool small;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.status == PlaybackStatus.error) {
      return ColoredBox(
        color: OnVideoColors.dim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 26, 12, 8),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    const Icon(AppIcons.cellFailed, size: 26, color: OnVideoColors.error),
                    Text(
                      failureText(state.error),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _markStyle(context, weight: FontWeight.w400),
                    ),
                    if (!small) _RetryButton(onPressed: onRetry),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final loading = switching || state.status == PlaybackStatus.opening || state.status == PlaybackStatus.buffering;
    if (loading) {
      return const IgnorePointer(
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: OnVideoColors.foreground),
          ),
        ),
      );
    }
    if (state.status == PlaybackStatus.paused) {
      // c8: the picture dims and says so.
      return IgnorePointer(
        child: ColoredBox(
          color: OnVideoColors.scrimMid,
          child: Center(
            child: Container(
              key: const ValueKey('multiview-paused'),
              height: 32,
              padding: const EdgeInsets.only(left: 8, right: 12),
              decoration: BoxDecoration(color: OnVideoColors.scrim, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  const Icon(AppIcons.cellPause, size: 18, color: OnVideoColors.foreground),
                  Text(i18n('multiview_paused'), style: _markStyle(context, body: true)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// The dashed frame of the cell the picker fills (3 points in, 2 wide).
class _DashedFrame extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = (Offset.zero & size).deflate(4);
    if (rect.isEmpty) return;
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += dash + gap) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame oldDelegate) => oldDelegate.color != color;
}

/// The "添加画面" slot at the end of the focus rail (3.x `_AddCellSlot`).
class AddCellSlot extends StatelessWidget {
  /// Creates the slot.
  const new({required this.onTap, super.key});

  /// Adds a cell.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = OnVideoColors.accent(Theme.of(context).colorScheme);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('multiview-add-cell'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Icon(AppIcons.addCell, size: 22, color: accent),
                    Text(i18n('multiview_add_cell'), style: _markStyle(context).copyWith(color: accent)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
