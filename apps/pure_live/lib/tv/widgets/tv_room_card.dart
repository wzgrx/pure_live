import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// A room on the TV: the phone's card (docs/A-界面设计/A09-浏览界面/A09.1-房间卡片) in the TV style
/// of docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 (c5, c7, c8):
///
/// - the cover takes what the info row leaves; on it the platform ("logo +
///   Chinese name", only in lists that mix platforms, [showPlatform]), the
///   followed heart, "录播" or the restriction (lock + reason) top right and
///   the audience (equal-width figures) bottom right while live; a room off
///   air is dimmed with "未开播"; a cover loading or failed is one
///   placeholder (never the "offline" glyph);
/// - below, the avatar (the channel number in an IPTV list), the title (16,
///   600; it scrolls while focused) and the streamer (14, secondary colour);
/// - focus is the shared ring and 5 % growth, the card a step lighter.
///
/// The data is the shared card model (`AudiencePolicy.cardOf`, M12.2), so
/// the audience rule, the room marks and the untitled-room text are the
/// phone's.
class TvRoomCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.data,
    this.onTap,
    this.onLongPress,
    this.onKey,
    this.onFocusChange,
    this.focusNode,
    this.followed = false,
    this.showPlatform = false,
    this.channelNumber,
    this.detail,
    super.key,
  });

  /// What the card shows.
  final RoomCardData data;

  /// OK.
  final VoidCallback? onTap;

  /// A held OK or the menu key: the card dialog.
  final VoidCallback? onLongPress;

  /// Keys before the default handling (the grid's moves).
  final TvKeyHandler? onKey;

  /// Focus gained or lost.
  final ValueChanged<bool>? onFocusChange;

  /// The node (the grid keeps one per card).
  final FocusNode? focusNode;

  /// Shows the followed heart (not on the follows page).
  final bool followed;

  /// Shows the platform chip (lists that mix platforms: all, history,
  /// search across platforms; U.15a c7).
  final bool showPlatform;

  /// The channel number shown instead of the avatar (IPTV lists).
  final int? channelNumber;

  /// A line after the streamer (history: when it was watched).
  final String? detail;

  /// The height of a card [width] wide: a 16:9 cover over the two lines.
  static double heightFor(double width, TvScale scale) =>
      width * 9 / 16 + scale.px(16) + scale.pxText((TvTextSize.body + TvTextSize.small) * 1.4) + 1;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final offAir = !data.isLive && !data.isReplay;
    final audience = data.audience?.value ?? '';
    final mark = data.restrictionLabel ?? '';
    final iptv = data.platformId == 'iptv';
    final radius = Radius.circular(scale.px(TvRadius.card));
    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      onFocusChange: onFocusChange,
      builder: (context, focused) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: focused ? palette.raised : palette.card,
          borderRadius: BorderRadius.all(radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TvCover(url: data.coverUrl, fit: iptv ? BoxFit.contain : BoxFit.cover),
                  if (offAir) ...[
                    const ColoredBox(color: OnVideoColors.scrim),
                    Center(
                      child: Text(
                        i18n('live_play_tag_offline'),
                        key: const ValueKey('tv-card-off-air'),
                        style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: OnVideoColors.foreground),
                      ),
                    ),
                  ],
                  if (showPlatform || followed)
                    Positioned(
                      left: scale.px(8),
                      top: scale.px(8),
                      child: Row(
                        children: [
                          if (showPlatform)
                            TvCoverChip(
                              key: const ValueKey('tv-card-platform'),
                              logo: data.platformId,
                              label: platformName(data.platformId),
                            ),
                          if (showPlatform && followed) SizedBox(width: scale.px(4)),
                          if (followed)
                            const TvCoverChip(
                              key: ValueKey('tv-card-followed'),
                              icon: TvIcons.followedMark,
                              iconColor: TvColors.followed,
                            ),
                        ],
                      ),
                    ),
                  if (data.isReplay || mark.isNotEmpty)
                    Positioned(
                      right: scale.px(8),
                      top: scale.px(8),
                      child: data.isReplay
                          ? TvCoverChip(
                              key: const ValueKey('tv-card-replay'),
                              icon: TvIcons.replay,
                              label: i18n('replay'),
                            )
                          : TvCoverChip(key: const ValueKey('tv-card-mark'), icon: AppIcons.restricted, label: mark),
                    ),
                  if (data.isLive && !data.isReplay && audience.isNotEmpty)
                    Positioned(
                      right: scale.px(8),
                      bottom: scale.px(8),
                      child: TvCoverChip(
                        key: const ValueKey('tv-card-audience'),
                        icon: audienceIcon(data.audience!.kind),
                        label: audience,
                        tabular: true,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: scale.px(12), vertical: scale.px(8)),
              child: Row(
                children: [
                  SizedBox(
                    width: scale.pxText(28),
                    child: Center(
                      child: channelNumber != null
                          ? Text(
                              '$channelNumber',
                              key: const ValueKey('tv-card-channel'),
                              maxLines: 1,
                              style: scale.font(18, weight: FontWeight.w600, color: palette.text).tabular,
                            )
                          : CommonAvatar(
                              avatarUrl: data.avatarUrl,
                              fallbackName: data.anchorName,
                              radius: scale.pxText(14),
                            ),
                    ),
                  ),
                  SizedBox(width: scale.px(8)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TvMarquee(
                          text: data.title,
                          running: focused,
                          style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text, height: 1.4),
                        ),
                        Text(
                          detail == null ? data.anchorName : '${data.anchorName} · $detail',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The icon of an audience figure (the phone card's choice, U.4a).
IconData audienceIcon(RoomAudienceKind kind) => switch (kind) {
  RoomAudienceKind.onlineViewers => AppIcons.audienceOnline,
  RoomAudienceKind.followers => AppIcons.audienceFollowers,
  RoomAudienceKind.totalViewers => AppIcons.audienceTotal,
  RoomAudienceKind.popularity || RoomAudienceKind.unknown => AppIcons.audienceHeat,
};

/// A cover picture with the one placeholder for loading and failed pictures
/// (U.15a c8): the highest-but-one surface and a television, never the
/// "offline" glyph.
class TvCover extends StatelessWidget {
  /// Creates the cover of [url].
  const new({required this.url, this.fit = BoxFit.cover, this.cacheWidth = 640, super.key});

  /// The picture; null or empty shows the placeholder.
  final String? url;

  /// How the picture fills the box.
  final BoxFit fit;

  /// The width it is decoded at (covers 640, UI_PLAN §9.2).
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final address = url ?? '';
    const placeholder = TvCoverPlaceholder();
    if (address.isEmpty) return placeholder;
    return ColoredBox(
      color: TvTheme.of(context).raised,
      child: LiveNetworkImage(
        url: address,
        fit: fit,
        memCacheWidth: cacheWidth,
        placeholder: (_) => placeholder,
        error: (_) => placeholder,
      ),
    );
  }
}

/// The placeholder of a cover that is loading or failed.
class TvCoverPlaceholder extends StatelessWidget {
  /// Creates the placeholder.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    return ColoredBox(
      key: const ValueKey('tv-cover-placeholder'),
      color: palette.raised,
      child: Center(
        child: Icon(TvIcons.coverPlaceholder, size: TvScale.of(context).px(32), color: palette.outline),
      ),
    );
  }
}

/// A chip on a cover (U.15a c7, the phone's U.4a badges): 60 % black, white
/// words at 14 (600), an optional platform logo or icon before them.
class TvCoverChip extends StatelessWidget {
  /// Creates the chip.
  const new({this.icon, this.label, this.logo, this.iconColor, this.tabular = false, super.key});

  /// The icon.
  final IconData? icon;

  /// The words.
  final String? label;

  /// A platform id whose logo leads the chip.
  final String? logo;

  /// The icon's colour (white when null).
  final Color? iconColor;

  /// Figures of equal width (audience counts).
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final text = scale.font(TvTextSize.small, weight: FontWeight.w600, color: OnVideoColors.foreground, height: 1.4);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: scale.px(8), vertical: scale.px(1)),
      decoration: const ShapeDecoration(color: OnVideoColors.scrim, shape: StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null) PlatformLogo(logo!, size: scale.pxText(14)),
          if (icon != null) Icon(icon, size: scale.pxText(15), color: iconColor ?? OnVideoColors.foreground),
          if (label case final label? when label.isNotEmpty) ...[
            if (icon != null || logo != null) SizedBox(width: scale.px(4)),
            Text(label, maxLines: 1, style: tabular ? text.tabular : text),
          ],
        ],
      ),
    );
  }
}

/// One line of text that scrolls to show all of it while [running] (the
/// focused card's title, pure_live_TV `TvMarqueeText`, kept by U.15a c1);
/// otherwise it ends with an ellipsis. Only the running one ticks, and it
/// stops as soon as the focus leaves (UI_PLAN §9.3).
class TvMarquee extends StatefulWidget {
  /// Creates the line.
  const new({required this.text, required this.style, this.running = false, super.key});

  /// The text.
  final String text;

  /// Its style.
  final TextStyle style;

  /// Scrolls when the text does not fit.
  final bool running;

  /// The pause before a pass and between passes.
  static const Duration pause = Duration(seconds: 1);

  /// How fast it scrolls, in logical pixels per second.
  static const double speed = 40;

  @override
  State<TvMarquee> createState() => _TvMarqueeState();
}

class _TvMarqueeState extends State<TvMarquee> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _offset = ValueNotifier(0);
  double _overflow = 0;
  double _gap = 0;

  @override
  void didUpdateWidget(TvMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.running) {
      _ticker.stop();
      _offset.value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final travel = _overflow + _gap;
    final pause = TvMarquee.pause.inMicroseconds / Duration.microsecondsPerSecond;
    final pass = travel / TvMarquee.speed;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond % (pause + pass);
    _offset.value = seconds < pause ? 0 : (seconds - pause) * TvMarquee.speed;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      final height = painter.height;
      painter.dispose();
      final fits = width <= constraints.maxWidth;
      if (!widget.running || fits) {
        if (_ticker.isActive) _ticker.stop();
        return Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
      }
      _gap = (widget.style.fontSize ?? 16) * 3;
      // One pass moves the second copy to where the first one started.
      _overflow = width;
      if (!_ticker.isActive) _ticker.start();
      return SizedBox(
        height: height,
        width: constraints.maxWidth,
        child: ClipRect(
          child: ValueListenableBuilder<double>(
            valueListenable: _offset,
            builder: (context, offset, child) => Transform.translate(offset: Offset(-offset, 0), child: child),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                  SizedBox(width: _gap),
                  Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
