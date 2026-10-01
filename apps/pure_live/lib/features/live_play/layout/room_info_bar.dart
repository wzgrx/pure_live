import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_header.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// `2:18` (hours and minutes) for a broadcast's time on air.
String formatOnAir(Duration elapsed) {
  final minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// The icon of an audience figure (3.x `AudienceInfo`).
IconData audienceIcon(AudienceMetricType type) => switch (type) {
  AudienceMetricType.onlineViewers => AppIcons.audienceOnline,
  AudienceMetricType.totalViewers => AppIcons.audienceTotal,
  AudienceMetricType.followers => AppIcons.audienceFollowers,
  _ => AppIcons.audienceHeat,
};

/// The strip under the video (docs/ui/compare/U.2a, changes 6–8): the
/// replay or restriction mark, the title and "详情 ⌄" on the first line
/// (a tap anywhere on it opens or closes the room details); the platform's
/// audience figures and the time on air on the second, with the quality and
/// line buttons on its right. Grey placeholders while the room loads (E2).
class RoomInfoBar extends StatelessWidget {
  /// Creates the strip.
  const new({
    required this.controller,
    required this.detailsOpen,
    required this.onToggleDetails,
    this.onReopen,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// Whether the room details are open ("收起 ⌃" then).
  final bool detailsOpen;

  /// Opens or closes the room details.
  final VoidCallback onToggleDetails;

  /// Called before the user asks for another quality or line.
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TitleLine(controller: controller, detailsOpen: detailsOpen, onTap: onToggleDetails),
        Row(
          children: [
            Expanded(child: AudienceStrip(controller: controller)),
            StreamPickers(controller: controller, onReopen: onReopen),
          ],
        ),
      ],
    ),
  );
}

class _TitleLine extends StatelessWidget {
  const new({required this.controller, required this.detailsOpen, required this.onTap});

  final LiveRoomController controller;
  final bool detailsOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final toggle = theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.primary);
    return InkWell(
      key: const ValueKey('live-play-info'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(
              child: ListenableSelector<(String, String?, bool, bool)>(
                listenable: controller,
                selector: () {
                  final room = controller.room;
                  return (
                    room.title.trim(),
                    room.isRestricted && room.isLiveNow ? restrictionLabel(room.effectiveRestriction) : null,
                    room.isRecord,
                    controller.stage == RoomStage.loading,
                  );
                },
                builder: (context, value, _) {
                  final (title, restriction, replay, loading) = value;
                  if (title.isEmpty && loading) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: SkeletonBar(key: ValueKey('live-play-info-placeholder'), width: 168, height: 16),
                    );
                  }
                  return Row(
                    children: [
                      if (replay) ...[_Tag(text: i18n('replay'), color: scheme.tertiary), const SizedBox(width: 6)],
                      if (restriction != null) ...[
                        _Tag(text: restriction, color: scheme.error),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          title.isEmpty ? i18n('untitled_room') : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.emphasis,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(i18n(detailsOpen ? 'live_play_details_fold' : 'live_play_details'), style: toggle),
            Icon(detailsOpen ? AppIcons.foldUp : AppIcons.dropDown, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const new({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.regular.copyWith(color: color)),
    ),
  );
}

/// The platform's audience figures, each an icon and a number of equal-width
/// digits (online, heat, cumulative: as many as the platform gives, U.2a
/// change 7), and the time on air as `H:MM`. Rebuilt only when a figure
/// changes; the time on air keeps its own minute clock.
class AudienceStrip extends StatelessWidget {
  /// Creates the strip.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  List<AudienceFigure> _figures() {
    final room = controller.room;
    final shown = (room.isLiveNow || room.isRecord) && controller.site.id != SiteIds.iptv;
    return shown ? audienceFigures(room) : const [];
  }

  @override
  Widget build(BuildContext context) => ListenableSelector<(String, DateTime?, bool)>(
    listenable: controller,
    selector: () {
      final room = controller.room;
      return (
        [for (final figure in _figures()) '${figure.type.name}=${figure.value}'].join('|'),
        room.isLiveNow ? room.startedAt : null,
        controller.stage == RoomStage.loading && room.title.trim().isEmpty,
      );
    },
    builder: (context, value, _) {
      final (_, startedAt, loading) = value;
      final theme = Theme.of(context);
      final color = theme.colorScheme.onSurfaceVariant;
      final style = theme.textTheme.bodyMedium?.regular.tabular.copyWith(color: color);
      if (loading) {
        return const Row(
          key: ValueKey('live-play-audience-placeholder'),
          children: [SkeletonBar(width: 52, height: 12), SizedBox(width: 12), SkeletonBar(width: 52, height: 12)],
        );
      }
      return Wrap(
        key: const ValueKey('live-play-audience'),
        spacing: 14,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final figure in _figures())
            _Figure(
              icon: audienceIcon(figure.type),
              label: audienceLabel(figure.type),
              text: figure.value.isEmpty ? i18n('audience_waiting') : readableAudience(figure.value),
              style: style,
              color: color,
            ),
          if (startedAt != null)
            _Figure(
              icon: AppIcons.liveDuration,
              label: i18n('live_play_on_air'),
              style: style,
              color: color,
              child: OnAirClock(startedAt: startedAt, now: controller.now, style: style),
            ),
        ],
      );
    },
  );
}

class _Figure extends StatelessWidget {
  const new({required this.icon, required this.label, required this.style, required this.color, this.text, this.child});

  final IconData icon;
  final String label;
  final String? text;
  final Widget? child;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        child ?? Text(text ?? '', style: style),
      ],
    ),
  );
}

/// The time on air as `H:MM`, redrawn by itself each minute.
class OnAirClock extends StatefulWidget {
  /// Creates the clock.
  const new({required this.startedAt, required this.now, this.style, super.key});

  /// When the broadcast started.
  final DateTime startedAt;

  /// The clock.
  final DateTime Function() now;

  /// The text style.
  final TextStyle? style;

  @override
  State<OnAirClock> createState() => _OnAirClockState();
}

class _OnAirClockState extends State<OnAirClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(formatOnAir(widget.now().difference(widget.startedAt)), style: widget.style);
}

/// Quality and line buttons (3.x `ResolutionSelector`, `LineSelector`):
/// the name with a drop-down mark on an outlined 32-high button with a
/// 48-high touch area (U.2a change 8); [onVideo] draws them for the
/// fullscreen bar. The lists they open are unchanged.
class StreamPickers extends StatelessWidget {
  /// Creates the pickers.
  const new({required this.controller, this.onVideo = false, this.onReopen, super.key});

  /// The room.
  final LiveRoomController controller;

  /// White on the picture.
  final bool onVideo;

  /// Called before the user asks for another quality or line.
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) => ListenableSelector<(RoomStage, int, int, bool, String)>(
    listenable: controller,
    selector: () => (
      controller.stage,
      controller.qualities.length,
      controller.qualityIndex,
      controller.switching,
      controller.qualities.map((quality) => '${quality.quality}${quality.isPlaybackUnconfirmed ? '?' : ''}').join('|'),
    ),
    builder: (context, value, _) {
      final (stage, count, _, switching, _) = value;
      if (stage != RoomStage.playing || count == 0) return const SizedBox.shrink();
      final qualities = controller.qualities;
      final index = controller.qualityIndex.clamp(0, qualities.length - 1);
      final current = qualities[index];
      return StreamBuilder<PlaybackState>(
        stream: controller.session.states,
        initialData: controller.session.state,
        builder: (context, snapshot) {
          final playback = snapshot.data ?? controller.session.state;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<int>(
                key: const ValueKey('live-play-quality'),
                enabled: !switching && qualities.length > 1,
                tooltip: i18n('select_quality'),
                position: PopupMenuPosition.under,
                onSelected: (selected) {
                  onReopen?.call();
                  unawaited(controller.selectQuality(selected));
                },
                itemBuilder: (context) => [
                  for (final (option, quality) in qualities.indexed)
                    CheckedPopupMenuItem(value: option, checked: option == index, child: Text(quality.quality)),
                ],
                child: _DropButton(
                  text: current.isPlaybackUnconfirmed ? '${current.quality}?' : current.quality,
                  onVideo: onVideo,
                  busy: switching,
                ),
              ),
              if (playback.lineCount > 1)
                PopupMenuButton<int>(
                  key: const ValueKey('live-play-line'),
                  tooltip: i18n('select_play_line'),
                  position: PopupMenuPosition.under,
                  onSelected: (selected) {
                    onReopen?.call();
                    unawaited(controller.selectLine(selected));
                  },
                  itemBuilder: (context) => [
                    for (var line = 0; line < playback.lineCount; line++)
                      CheckedPopupMenuItem(
                        value: line,
                        checked: line == playback.lineIndex,
                        child: Text(i18n('toolbox_line', args: {'index': '${line + 1}'})),
                      ),
                  ],
                  child: _DropButton(
                    text: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                    onVideo: onVideo,
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

class _DropButton extends StatelessWidget {
  const new({required this.text, required this.onVideo, this.busy = false});

  final String text;
  final bool onVideo;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = onVideo ? OnVideoColors.foreground : scheme.onSurface;
    final style = theme.textTheme.bodyMedium?.regular.copyWith(
      color: ink,
      shadows: onVideo ? OnVideoColors.shadows : null,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension, minWidth: kMinInteractiveDimension),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Center(
          child: SizedBox(
            height: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: onVideo ? OnVideoColors.chip : null,
                border: Border.all(color: onVideo ? OnVideoColors.chipOutline : scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy) ...[
                      SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: ink)),
                      const SizedBox(width: 5),
                    ],
                    Text(text, style: style, maxLines: 1),
                    const SizedBox(width: 2),
                    Icon(AppIcons.dropDown, size: 18, color: ink),
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
