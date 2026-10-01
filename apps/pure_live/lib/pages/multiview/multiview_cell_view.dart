import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/room_texts.dart';
import 'package:pure_live/pages/multiview/multiview_controller.dart';

/// One cell on screen (3.x `_MultiviewCellView`): the video with its name
/// chip, sound mark and playback state, or the empty, loading, offline and
/// failed placeholders.
class MultiviewCellView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.cell,
    required this.position,
    required this.audible,
    required this.pickTarget,
    required this.onTap,
    required this.onActions,
    required this.onRetry,
    this.showVideo = true,
    this.danmaku,
    this.footer,
    super.key,
  });

  /// The cell.
  final MultiviewCell cell;

  /// 1-based number of the cell (shown on empty cells).
  final int position;

  /// The cell's sound plays.
  final bool audible;

  /// The picker fills this cell next.
  final bool pickTarget;

  /// Tap on the cell.
  final VoidCallback onTap;

  /// The cell's menu (long press, right click, the more button).
  final VoidCallback? onActions;

  /// Retry or check the room again.
  final VoidCallback onRetry;

  /// False while the page closes (the video leaves the tree first).
  final bool showVideo;

  /// The flying danmaku over the video.
  final Widget? danmaku;

  /// Shown at the bottom of a playing cell (the large cell's controls).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final session = cell.session;
    final video = cell.playing && session != null && showVideo;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: video || dark ? Colors.black : theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: pickTarget ? theme.colorScheme.primary : Colors.transparent, width: 2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('multiview-cell-$position'),
          onTap: onTap,
          onLongPress: onActions,
          onSecondaryTap: onActions,
          child: video ? _playing(context, session) : _placeholder(context),
        ),
      ),
    );
  }

  Widget _playing(BuildContext context, PlaybackSession session) {
    return Stack(
      fit: StackFit.expand,
      children: [
        LiveVideoView(session: session, outputSize: defaultTargetPlatform == TargetPlatform.windows),
        if (danmaku case final layer?) Positioned.fill(child: IgnorePointer(child: layer)),
        StreamBuilder<PlaybackState>(
          stream: session.states,
          initialData: session.state,
          builder: (context, snapshot) =>
              _PlaybackLayer(state: snapshot.data ?? session.state, switching: cell.switching, onRetry: onRetry),
        ),
        Positioned(
          top: 6,
          left: 6,
          right: 6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Small cells keep the name and drop the badge's words.
              final compact = constraints.maxWidth < 260;
              return Row(
                children: [
                  if (constraints.maxWidth >= 120) Flexible(child: _RoomChip(room: cell.room)),
                  if (audible) ...[const SizedBox(width: 6), _AudioBadge(compact: compact)],
                  const Spacer(),
                  if (onActions != null)
                    _OverlayButton(
                      key: ValueKey('multiview-cell-more-$position'),
                      icon: Remix.more_2_fill,
                      tooltip: i18n('multiview_more'),
                      onTap: onActions!,
                    ),
                ],
              );
            },
          ),
        ),
        if (footer case final bar?) Positioned(left: 6, right: 6, bottom: 6, child: bar),
      ],
    );
  }

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    final styles = context.textStyles;
    final room = cell.room;
    final label = room == null ? '' : room.displayNick(platformName(room.platform));
    Widget column(List<Widget> children) => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    return switch (cell.stage) {
      CellStage.empty => column([
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
          child: Icon(Remix.add_circle_line, size: 24, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Text(i18n('multiview_empty_cell_hint'), style: styles.t14Medium, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(i18n('multiview_cell_number', args: {'index': '$position'}), style: styles.t12Muted),
      ]),
      CellStage.resolving || CellStage.playing => column([
        const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: styles.t12Muted),
        ],
      ]),
      CellStage.offline => column([
        Icon(Remix.live_line, size: 28, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(
          room == null ? i18n('multiview_room_offline') : offlineText(room),
          style: styles.t14Bold,
          textAlign: TextAlign.center,
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: styles.t12Muted),
        ],
        const SizedBox(height: 4),
        Text(i18n('multiview_room_offline_hint'), style: styles.t12Muted, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: ValueKey('multiview-recheck-$position'),
          onPressed: onRetry,
          icon: const Icon(Remix.refresh_line, size: 16),
          label: Text(i18n('multiview_recheck')),
        ),
      ]),
      CellStage.failed => column([
        Icon(Remix.error_warning_line, size: 28, color: theme.colorScheme.error),
        const SizedBox(height: 8),
        Text(i18n('multiview_play_failed'), style: styles.t14Bold, textAlign: TextAlign.center),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: styles.t12Muted),
        ],
        const SizedBox(height: 4),
        Text(
          cellFailureText(cell.failure),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: styles.t12Muted,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: ValueKey('multiview-retry-$position'),
          onPressed: onRetry,
          icon: const Icon(Remix.refresh_line, size: 16),
          label: Text(i18n('retry')),
        ),
      ]),
    };
  }
}

/// Why a cell failed, in words (never the platform's raw text; 3.x showed
/// the exception's `toString`).
String cellFailureText(Object? failure) => switch (failure) {
  UnsupportedPlatform() => i18n('platform_retired'),
  _ => failureText(failure),
};

/// The session's state over the video: loading, paused, failed.
class _PlaybackLayer extends StatelessWidget {
  const new({required this.state, required this.switching, required this.onRetry});

  final PlaybackState state;
  final bool switching;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final styles = context.textStyles;
    const white = Colors.white;
    if (state.status == PlaybackStatus.error) {
      return ColoredBox(
        color: Colors.black54,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Remix.error_warning_line, size: 26, color: white),
                const SizedBox(height: 6),
                Text(
                  failureText(state.error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: styles.t12.copyWith(color: white),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Remix.refresh_line, size: 16),
                  label: Text(i18n('retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final loading = switching || state.status == PlaybackStatus.opening || state.status == PlaybackStatus.buffering;
    if (loading) {
      return const IgnorePointer(
        child: Center(
          child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: white)),
        ),
      );
    }
    if (state.status == PlaybackStatus.paused) {
      return IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(Remix.pause_line, size: 24, color: white, semanticLabel: i18n('multiview_paused')),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Platform logo and streamer name on the video.
class _RoomChip extends StatelessWidget {
  const new({required this.room});

  final LiveRoom? room;

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (room == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlatformLogo(room.platform, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              room.displayNick(platformName(room.platform)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sound" mark of the audible cell (3.x `_AudioFocusBadge`).
class _AudioBadge extends StatelessWidget {
  const new({required this.compact});

  /// Only the icon.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: i18n('multiview_audio_focus_badge'),
      child: Container(
        key: const ValueKey('multiview-audio-badge'),
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Remix.volume_up_line, size: 13, color: Colors.white),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                i18n('multiview_audio_focus_badge'),
                style: context.textStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round button on the video.
class _OverlayButton extends StatelessWidget {
  const new({required this.icon, required this.tooltip, required this.onTap, super.key});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    ),
  );
}

/// The "add a view" slot at the end of the focus column (3.x `_AddCellSlot`).
class AddCellSlot extends StatelessWidget {
  /// Creates the slot.
  const new({required this.onTap, super.key});

  /// Adds a cell.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('multiview-add-cell'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35), width: 1.5),
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Remix.add_circle_line, size: 22, color: theme.colorScheme.primary),
                const SizedBox(height: 6),
                Text(i18n('multiview_add_cell'), style: context.textStyles.t12Primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
