import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/buttons/stream_menu.dart';
import 'package:pure_live/features/live_play/layout/room_header.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The icon of an audience figure (3.x `AudienceInfo`).
IconData audienceIcon(AudienceMetricType type) => switch (type) {
  AudienceMetricType.onlineViewers => AppIcons.audienceOnline,
  AudienceMetricType.totalViewers => AppIcons.audienceTotal,
  AudienceMetricType.followers => AppIcons.audienceFollowers,
  _ => AppIcons.audienceHeat,
};

/// The strip under the video (docs/A-界面设计/A07-直播间界面/A07.1-竖屏普通布局, changes 6–8): the
/// replay or restriction mark, the title and "详情 ⌄" on the first line
/// (a tap anywhere on it opens or closes the room details); the platform's
/// audience figures and the time on air on the second, in one line of a
/// fixed height (A07.17 c1), with the quality and line buttons on its right
/// ([StreamPickers]). Grey placeholders while the room loads (E2).
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
        // U.2g: a room that is not on air (or could not be read) keeps only
        // its title line; a restricted one keeps its figures, without the
        // quality and line it cannot play.
        ListenableSelector<RoomStage>(
          listenable: controller,
          selector: () => controller.stage,
          builder: (context, stage, _) => switch (stage) {
            RoomStage.offline || RoomStage.failed => const SizedBox.shrink(),
            // A07.17 c1: one line of a fixed height in every room, the
            // figures centred on the quality and line buttons.
            RoomStage.unplayable || RoomStage.loading || RoomStage.playing => SizedBox(
              key: const ValueKey('live-play-audience-row'),
              height: roomFiguresRowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AudienceStrip(controller: controller),
                    ),
                  ),
                  if (stage != RoomStage.unplayable) StreamPickers(controller: controller, onReopen: onReopen),
                ],
              ),
            ),
          },
        ),
      ],
    ),
  );
}

/// The mark before the title of a room that is not on air (U.2g c7, c10):
/// "未开播", "已封禁", "轮播"; null otherwise.
String? offlineMark(RoomStage stage, LiveRoom room) {
  if (stage != RoomStage.offline) return null;
  return switch (room.effectiveLiveStatus) {
    LiveStatus.banned => i18n('room_mark_banned'),
    LiveStatus.carousel => i18n('room_mark_carousel'),
    LiveStatus.unknown => null,
    _ => i18n('live_play_tag_offline'),
  };
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
              child: ListenableSelector<(String, String?, bool, bool, String?)>(
                listenable: controller,
                selector: () {
                  final room = controller.room;
                  return (
                    room.title.trim(),
                    room.isRestricted && room.isLiveNow ? restrictionLabel(room.effectiveRestriction) : null,
                    room.isRecord,
                    controller.stage == RoomStage.loading,
                    offlineMark(controller.stage, room),
                  );
                },
                builder: (context, value, _) {
                  final (title, restriction, replay, loading, offline) = value;
                  if (title.isEmpty && loading) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: SkeletonBar(key: ValueKey('live-play-info-placeholder'), width: 168, height: 16),
                    );
                  }
                  return Row(
                    children: [
                      if (replay) ...[_Tag(text: i18n('replay'), color: scheme.tertiary), const SizedBox(width: 6)],
                      if (offline != null) ...[
                        _Tag(
                          key: const ValueKey('live-play-offline-tag'),
                          text: offline,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                      ],
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
  const new({required this.text, required this.color, super.key});

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

/// The height of the strip's second line, the figures and the quality and
/// line buttons (their 48 touch height): the same in every room, loading or
/// playing (A07.17 c1).
const double roomFiguresRowHeight = 48;

/// What of the strip's figures fits one line ([fitAudience]): the indexes of
/// the figures shown, the time on air short (`6:45`), the smaller text.
typedef AudienceFit = ({List<int> shown, bool shortClock, bool small});

/// Picks what of the figures [types] and the time on air fits [width] in one
/// line, never wrapping (A07.17 c1): everything; without "看过" when there
/// are more than two figures; with the short time; in the smaller text; then
/// without the last figures but the first. [figure] and [clock] (null
/// without a time on air) measure a part, [spacing] goes between two. As a
/// last resort the parts cut their text short.
AudienceFit fitAudience({
  required List<AudienceMetricType> types,
  required double Function(int index, {required bool small}) figure,
  required double Function({required bool short, required bool small})? clock,
  required double spacing,
  required double width,
}) {
  bool fits(List<int> shown, {required bool short, required bool small}) {
    final parts = [for (final index in shown) figure(index, small: small), ?clock?.call(short: short, small: small)];
    if (parts.isEmpty) return true;
    return parts.fold<double>(0, (sum, part) => sum + part) + spacing * (parts.length - 1) <= width;
  }

  var shown = [for (var index = 0; index < types.length; index++) index];
  if (fits(shown, short: false, small: false)) return (shown: shown, shortClock: false, small: false);
  if (types.length > 2) {
    final total = types.indexOf(AudienceMetricType.totalViewers);
    if (total >= 0) {
      shown = [
        for (final index in shown)
          if (index != total) index,
      ];
      if (fits(shown, short: false, small: false)) return (shown: shown, shortClock: false, small: false);
    }
  }
  final short = clock != null;
  if (short && fits(shown, short: true, small: false)) return (shown: shown, shortClock: true, small: false);
  if (fits(shown, short: short, small: true)) return (shown: shown, shortClock: short, small: true);
  while (shown.length > 1) {
    shown = shown.sublist(0, shown.length - 1);
    if (fits(shown, short: short, small: true)) break;
  }
  return (shown: shown, shortClock: short, small: true);
}

/// The platform's audience figures, each an icon and a number of equal-width
/// digits (online, heat, cumulative: as many as the platform gives, U.2a
/// change 7), and the time on air, in one line whatever the width
/// ([fitAudience], A07.17 c1). Rebuilt only when a figure changes; the time
/// on air keeps its own minute clock. [onVideo] draws it small and light on
/// the picture (the title of a phone held sideways, c2).
class AudienceStrip extends StatelessWidget {
  /// Creates the strip.
  const new({required this.controller, this.onVideo = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Under the title on the picture.
  final bool onVideo;

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
      if (loading) {
        return const Row(
          key: ValueKey('live-play-audience-placeholder'),
          children: [SkeletonBar(width: 52, height: 12), SizedBox(width: 12), SkeletonBar(width: 52, height: 12)],
        );
      }
      final figures = _figures();
      Widget line(BuildContext context) =>
          LayoutBuilder(builder: (context, constraints) => _line(context, figures, startedAt, constraints.maxWidth));
      // The time on air changes the fit as it grows: measured again with it.
      return startedAt == null ? Builder(builder: line) : _MinuteTicker(builder: line);
    },
  );

  Widget _line(BuildContext context, List<AudienceFigure> figures, DateTime? startedAt, double width) {
    final theme = Theme.of(context);
    final color = onVideo ? OnVideoColors.secondary : theme.colorScheme.onSurfaceVariant;
    final shadows = onVideo ? OnVideoColors.shadows : null;
    TextStyle? styleOf({required bool small}) =>
        (small || onVideo ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.regular.tabular.copyWith(
          color: color,
          shadows: shadows,
        );
    double iconOf({required bool small}) => small || onVideo ? 14 : 16;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String text, {required bool small}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: styleOf(small: small),
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.width;
      painter.dispose();
      return iconOf(small: small) + 4 + size;
    }

    String figureText(AudienceFigure figure) =>
        figure.value.isEmpty ? i18n('audience_waiting') : readableAudience(figure.value);
    final elapsed = startedAt == null ? null : controller.now().difference(startedAt);
    String clockText({required bool short}) =>
        short ? shortElapsedText(elapsed ?? Duration.zero) : elapsedText(elapsed ?? Duration.zero);
    const spacing = 14.0;
    final fit = fitAudience(
      types: [for (final figure in figures) figure.type],
      figure: (index, {required small}) => measure(figureText(figures[index]), small: small),
      clock: elapsed == null
          ? null
          : ({required short, required small}) => measure(clockText(short: short), small: small),
      spacing: spacing,
      width: width,
    );
    final style = styleOf(small: fit.small);
    final icon = iconOf(small: fit.small);
    final parts = [
      for (final index in fit.shown)
        _Figure(
          icon: audienceIcon(figures[index].type),
          label: audienceLabel(figures[index].type),
          text: figureText(figures[index]),
          style: style,
          color: color,
          size: icon,
          shadows: shadows,
        ),
      if (elapsed != null)
        _Figure(
          key: const ValueKey('live-play-on-air'),
          icon: AppIcons.liveDuration,
          label: i18n('live_play_on_air'),
          text: clockText(short: fit.shortClock),
          style: style,
          color: color,
          size: icon,
          shadows: shadows,
        ),
    ];
    // Each part flexes by its own measured width: equal flex would cap every
    // part at an equal share, so a long time on air ("2 小时 5 分") was cut
    // short beside two short figures although the whole line fitted.
    final widths = [
      for (final index in fit.shown) measure(figureText(figures[index]), small: fit.small),
      if (elapsed != null) measure(clockText(short: fit.shortClock), small: fit.small),
    ];
    return Row(
      key: const ValueKey('live-play-audience'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0) const SizedBox(width: spacing),
          Flexible(flex: math.max(1, widths[index].round()), child: part),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.text,
    required this.style,
    required this.color,
    required this.size,
    this.shadows,
    super.key,
  });

  final IconData icon;
  final String label;
  final String text;
  final TextStyle? style;
  final Color color;
  final double size;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: color, shadows: shadows),
        const SizedBox(width: 4),
        // The last resort of a narrow strip with large text cuts the figure
        // short instead of overflowing (B09 c3).
        Flexible(
          child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

/// Builds [builder] again every 20 seconds (the time on air's minutes).
class _MinuteTicker extends StatefulWidget {
  const new({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_MinuteTicker> createState() => _MinuteTickerState();
}

class _MinuteTickerState extends State<_MinuteTicker> {
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
  Widget build(BuildContext context) => widget.builder(context);
}

/// The time on air as `2 小时 18 分` ([elapsedText], the cards' words; B09
/// c5, audit B-16: `2:18` read like a recording's minutes and seconds),
/// redrawn by itself each minute. Given [fitWidth] it turns short (`2:18`,
/// [shortElapsedText]) where the long words do not fit that width (the
/// details' cells, A07.17 c6).
class OnAirClock extends StatelessWidget {
  /// Creates the clock.
  const new({required this.startedAt, required this.now, this.style, this.fitWidth, super.key});

  /// When the broadcast started.
  final DateTime startedAt;

  /// The clock.
  final DateTime Function() now;

  /// The text style.
  final TextStyle? style;

  /// The width the long words must fit; null: always the long words.
  final double? fitWidth;

  @override
  Widget build(BuildContext context) => _MinuteTicker(
    builder: (context) {
      final elapsed = now().difference(startedAt);
      var text = elapsedText(elapsed);
      if (fitWidth case final width?) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        if (painter.width > width) text = shortElapsedText(elapsed);
        painter.dispose();
      }
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    },
  );
}
