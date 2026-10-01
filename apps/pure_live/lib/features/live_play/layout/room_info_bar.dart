import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/buttons/stream_menu.dart';
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
/// line buttons on its right ([StreamPickers]). Grey placeholders while the
/// room loads (E2).
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
