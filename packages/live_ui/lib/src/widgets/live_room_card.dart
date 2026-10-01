import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/icons/platform_logo.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/live_theme.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/avatar.dart';
import 'package:live_ui/src/widgets/network_image.dart';
import 'package:live_ui/src/widgets/room_card.dart';
import 'package:live_ui/src/widgets/room_card_appearance.dart';

/// The room card of the browsing pages (docs/ui/compare/U.4a): popular,
/// follows, area rooms, and later search and history (U.5).
///
/// 3.x's structure is kept (`RoomCard`: a 16:9 cover with its badges above
/// the avatar, a one-line title and the streamer, or the compact row of the
/// "简洁" preset; tap opens, long press and right click open the card
/// dialog); what changed:
///
/// * the platform shows as its logo and name on the cover's top left, when
///   the card settings say "always", or say "automatic" and the list mixes
///   platforms ([mixedPlatforms], c2);
/// * colours come from the theme's roles; the replay badge uses the primary
///   colour in both themes (c3);
/// * a room that is not live has its cover dimmed and marked (c4);
/// * a cover that is loading or failed shows the same placeholder (c5);
/// * every badge is 12 points, the audience in tabular figures (c6);
/// * a restricted room is marked on the cover's bottom left (c7);
/// * a mouse over the card tints it and shows the whole title; keyboard
///   focus draws a primary outline (c9).
///
/// [RoomCardSkeleton] is the static placeholder of the same size (c8).
class LiveRoomCard extends StatefulWidget {
  /// Creates the card.
  const new({
    required this.data,
    this.appearance = RoomCardAppearance.standard,
    this.dense = true,
    this.mixedPlatforms = false,
    this.statusPending = false,
    this.statusPendingLabel,
    this.showDelete = false,
    this.onDelete,
    this.deleteTooltip,
    this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// What to show.
  final RoomCardData data;

  /// How to show it (the card settings of this device).
  final RoomCardAppearance appearance;

  /// The small form of the grids (3.x `dense`); the large one is the follows
  /// page with "compact mode" off.
  final bool dense;

  /// The list mixes platforms (follows' "all", search, history): an
  /// "automatic" platform badge shows.
  final bool mixedPlatforms;

  /// The live status is being checked: the status badge replaces the
  /// audience.
  final bool statusPending;

  /// Words of the [statusPending] badge; null shows "verifying".
  final String? statusPendingLabel;

  /// Shows the delete button (history).
  final bool showDelete;

  /// The delete button's action.
  final VoidCallback? onDelete;

  /// The delete button's tooltip; null shows "delete".
  final String? deleteTooltip;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card dialog (long press and right click).
  final VoidCallback? onLongPress;

  /// The card's focus (grids that move focus by keys).
  final FocusNode? focusNode;

  /// Takes the focus when first shown.
  final bool autofocus;

  /// Whether the platform badge shows with [appearance] in a list that
  /// [mixedPlatforms] or not.
  static bool showsPlatform(RoomCardAppearance appearance, {required bool mixedPlatforms}) =>
      appearance.showPlatformBadge || (appearance.automaticPlatformBadge && mixedPlatforms);

  @override
  State<LiveRoomCard> createState() => _LiveRoomCardState();
}

class _LiveRoomCardState extends State<LiveRoomCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appearance = widget.appearance;
    final radius = BorderRadius.circular(appearance.cornerRadius);
    final keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final parts = _Parts(card: widget, theme: theme, words: LiveUiScope.of(context).strings);
    final cover = appearance.layout == RoomCardLayout.cover;
    final card = Material(
      key: const ValueKey('room-card-surface'),
      color: _hovered ? scheme.surfaceContainerHigh : LiveRoomCardColors.surface(scheme, theme.brightness),
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        borderRadius: radius,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        child: cover ? parts.cover(context) : parts.compact(context),
      ),
    );
    // Always the same wrapper: swapping it in on focus would rebuild the ink
    // well and lose the focus it just got.
    final focusRing = _focused && keyboard;
    final outlined = DecoratedBox(
      key: const ValueKey('room-card-ring'),
      position: DecorationPosition.foreground,
      decoration: focusRing
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: scheme.primary, width: 3, strokeAlign: BorderSide.strokeAlignOutside),
            )
          : const BoxDecoration(),
      child: card,
    );
    if (!cover) return outlined;
    // The whole title on hover (mouse only: a long press opens the dialog).
    return Tooltip(
      message: widget.data.title,
      triggerMode: TooltipTriggerMode.manual,
      waitDuration: const Duration(milliseconds: 500),
      child: outlined,
    );
  }
}

/// The card's surface: white in the light theme (3.x), the container colour
/// in the dark one (3.x used `grey[900]`).
abstract final class LiveRoomCardColors {
  /// The resting surface.
  static Color surface(ColorScheme scheme, Brightness brightness) =>
      brightness == Brightness.dark ? scheme.surfaceContainer : scheme.surfaceContainerLowest;

  /// The dimming over an offline room's cover (a plain layer, no filter).
  static const Color offlineDim = Color(0x61000000);

  /// A badge on a cover: dark enough on bright and dark pictures.
  static const Color chip = Color(0x8C000000);
}

/// Heights of [LiveRoomCard] so fixed-extent grids reserve what a card takes
/// (16:9 cover plus a 64-point caption, 72 for the large card; more when
/// the text is larger).
abstract final class LiveRoomCardMetrics {
  /// The caption under the cover.
  static double captionHeight({
    required bool dense,
    RoomCardAppearance appearance = RoomCardAppearance.standard,
    TextScaler textScaler = TextScaler.noScaling,
    LiveFontSizes fontSizes = const LiveFontSizes(),
  }) {
    final title = textScaler.scale(dense ? fontSizes.bodyMedium : fontSizes.titleMedium) * 1.3;
    final anchor = appearance.showAnchorName
        ? textScaler.scale(dense ? fontSizes.bodySmall : fontSizes.bodyMedium) * 1.3 + 2
        : 0.0;
    return math.max(dense ? 64.0 : 72.0, title + anchor + 16);
  }

  /// A card [itemWidth] wide.
  static double extent({
    required double itemWidth,
    required bool dense,
    RoomCardAppearance appearance = RoomCardAppearance.standard,
    TextScaler textScaler = TextScaler.noScaling,
    LiveFontSizes fontSizes = const LiveFontSizes(),
  }) {
    if (appearance.layout == RoomCardLayout.compact) {
      return RoomCardLayoutMetrics.compactHeight(
        appearance: appearance,
        dense: dense,
        textScaler: textScaler,
        fontSizes: fontSizes,
      );
    }
    return math.max(0, itemWidth) * 9 / 16 +
        captionHeight(dense: dense, appearance: appearance, textScaler: textScaler, fontSizes: fontSizes);
  }
}

final class _Parts {
  new({required this.card, required this.theme, required this.words})
    : styles = AppTextStyles(theme),
      scheme = theme.colorScheme;

  final LiveRoomCard card;
  final ThemeData theme;
  final LiveUiStrings words;
  final AppTextStyles styles;
  final ColorScheme scheme;

  RoomCardData get data => card.data;
  RoomCardAppearance get appearance => card.appearance;
  bool get dense => card.dense;
  bool get showPlatform => LiveRoomCard.showsPlatform(appearance, mixedPlatforms: card.mixedPlatforms);
  String get platformText => data.platformName ?? data.platformId.toUpperCase();
  String get pendingText => card.statusPendingLabel ?? words.verifying;
  bool get showAudience => appearance.showAudience && data.isLive;
  bool get showReplay => appearance.showReplayBadge && data.isReplay;
  String? get restriction => (data.restrictionLabel?.isEmpty ?? true) ? null : data.restrictionLabel;

  Widget coverPlaceholder() => ColoredBox(
    key: const ValueKey('room-card-cover-placeholder'),
    color: scheme.surfaceContainer,
    child: Center(child: Icon(AppIcons.coverPlaceholder, size: 24, color: scheme.outline)),
  );

  Widget coverImage() {
    final url = data.coverUrl?.trim() ?? '';
    if (url.isEmpty) return coverPlaceholder();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
        final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round().clamp(240, 720);
        return LiveNetworkImage(
          url: url,
          memCacheWidth: cacheWidth,
          placeholder: (_) => coverPlaceholder(),
          error: (_) => coverPlaceholder(),
        );
      },
    );
  }

  Widget audienceChip() {
    final audience = data.audience ?? const RoomAudience(kind: RoomAudienceKind.unknown, value: '');
    final label = switch (audience.kind) {
      RoomAudienceKind.popularity => words.audiencePopularity,
      RoomAudienceKind.onlineViewers => words.audienceOnline,
      RoomAudienceKind.totalViewers => words.audienceTotal,
      RoomAudienceKind.followers => words.audienceFollowers,
      RoomAudienceKind.unknown => words.audienceCount,
    };
    final value = audience.value.isEmpty ? words.audienceWaiting : audience.value;
    return CoverChip(
      key: const ValueKey('cover-audience-metric'),
      icon: switch (audience.kind) {
        RoomAudienceKind.onlineViewers => AppIcons.audienceOnline,
        RoomAudienceKind.followers => AppIcons.audienceFollowers,
        RoomAudienceKind.totalViewers => AppIcons.audienceTotal,
        _ => AppIcons.audienceHeat,
      },
      text: value,
      tabular: true,
      tooltip: '$label $value',
    );
  }

  Widget platformChip() => CoverChip(
    key: const ValueKey('room-card-platform-badge'),
    leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: PlatformLogo(data.platformId, size: 16)),
    text: platformText,
  );

  Widget deleteButton({required bool onCover}) => IconButton(
    key: const ValueKey('room-card-delete'),
    tooltip: card.deleteTooltip ?? words.delete,
    onPressed: card.onDelete,
    padding: onCover ? const EdgeInsets.all(10) : EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: onCover
        ? DecoratedBox(
            decoration: const BoxDecoration(color: OnVideoColors.scrim, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(AppIcons.delete, color: OnVideoColors.foreground, size: dense ? 16 : 18),
            ),
          )
        : Icon(AppIcons.delete, size: dense ? 17 : 19),
  );

  Widget avatar() => KeyedSubtree(
    key: const ValueKey('room-card-avatar'),
    child: CommonAvatar(avatarUrl: data.avatarUrl, fallbackName: data.anchorName, dense: dense),
  );

  Widget title() => Text(
    data.title,
    key: const ValueKey('room-card-title'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (dense ? styles.t13 : styles.t15).copyWith(
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
  );

  Widget anchorName() => Text(
    data.anchorName,
    key: const ValueKey('room-card-anchor-name'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (dense ? styles.t12 : styles.t13).copyWith(
      height: 1.3,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
    ),
  );

  Widget cover(BuildContext context) {
    final radius = BorderRadius.circular(appearance.cornerRadius);
    final restricted = restriction;
    final Widget? statusChip;
    if (card.statusPending) {
      statusChip = CoverChip(key: const ValueKey('room-card-pending'), icon: AppIcons.statusPending, text: pendingText);
    } else if (data.isOffline) {
      statusChip = CoverChip(key: const ValueKey('room-card-offline'), text: words.offline);
    } else if (showAudience) {
      statusChip = audienceChip();
    } else {
      statusChip = null;
    }
    final captionHeight = LiveRoomCardMetrics.captionHeight(
      dense: dense,
      appearance: appearance,
      textScaler: MediaQuery.textScalerOf(context),
      fontSizes: LiveFontSizes.of(theme.textTheme),
    );
    return Column(
      key: const ValueKey('room-card-cover-layout'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The only clip of the card (U.4a, performance).
              ClipRRect(borderRadius: radius, child: coverImage()),
              if (data.isOffline && !card.statusPending)
                DecoratedBox(
                  key: const ValueKey('room-card-offline-dim'),
                  decoration: BoxDecoration(color: LiveRoomCardColors.offlineDim, borderRadius: radius),
                ),
              if (showPlatform) Positioned(left: 8, top: 8, child: platformChip()),
              if (showReplay)
                Positioned(
                  right: card.showDelete ? 48 : 8,
                  top: 8,
                  child: CoverChip(
                    key: const ValueKey('room-card-replay-badge'),
                    icon: AppIcons.replay,
                    text: words.replay,
                    background: scheme.primary,
                    foreground: scheme.onPrimary,
                  ),
                ),
              if (restricted != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: CoverChip(
                    key: const ValueKey('room-card-restriction'),
                    icon: AppIcons.restrictedBadge,
                    text: restricted,
                  ),
                ),
              if (statusChip != null) Positioned(right: 8, bottom: 8, child: statusChip),
              if (card.showDelete) Positioned(right: 0, top: 0, child: deleteButton(onCover: true)),
            ],
          ),
        ),
        SizedBox(
          height: captionHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
            child: Row(
              children: [
                if (appearance.showAvatar) ...[avatar(), SizedBox(width: dense ? 8 : 12)],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title(),
                      if (appearance.showAnchorName) ...[const SizedBox(height: 2), anchorName()],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget? compactTrailing(double width, double textScale) {
    final minimumMetricWidth = card.showDelete ? 360.0 : (dense ? 260.0 : 300.0);
    final canShowMetrics = width >= minimumMetricWidth && textScale < 1.8;
    final restricted = restriction;
    final children = <Widget>[
      if (canShowMetrics) ...[
        if (showPlatform) platformChip(),
        if (restricted != null)
          CoverChip(key: const ValueKey('room-card-restriction'), icon: AppIcons.restrictedBadge, text: restricted),
        if (card.statusPending)
          CoverChip(key: const ValueKey('room-card-pending'), icon: AppIcons.statusPending, text: pendingText)
        else if (data.isOffline)
          CoverChip(key: const ValueKey('room-card-offline'), text: words.offline)
        else if (showAudience)
          audienceChip()
        else if (showReplay)
          CoverChip(
            key: const ValueKey('room-card-replay-badge'),
            icon: AppIcons.replay,
            text: words.replay,
            background: scheme.primary,
            foreground: scheme.onPrimary,
          ),
      ] else if (card.statusPending)
        Tooltip(message: pendingText, child: const Icon(AppIcons.statusPending, size: 18)),
      if (card.showDelete) deleteButton(onCover: false),
    ];
    if (children.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: children),
    );
  }

  Widget compact(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScaler = MediaQuery.textScalerOf(context);
      final height = RoomCardLayoutMetrics.compactHeight(
        appearance: appearance,
        dense: dense,
        hasAction: card.showDelete,
        textScaler: textScaler,
        fontSizes: LiveFontSizes.of(theme.textTheme),
      );
      return SizedBox(
        key: const ValueKey('room-card-compact-layout'),
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 8 : 10),
          child: Row(
            children: [
              if (appearance.showAvatar) ...[avatar(), SizedBox(width: dense ? 8 : 10)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title(),
                    if (appearance.showAnchorName) ...[const SizedBox(height: 2), anchorName()],
                  ],
                ),
              ),
              ?compactTrailing(constraints.maxWidth, textScaler.scale(1)),
            ],
          ),
        ),
      );
    },
  );
}

/// A badge on a cover (U.4a): 22 high, a dark translucent capsule with an
/// optional icon or [leading] and 12-point words; [background] and
/// [foreground] for the replay badge's primary colour.
class CoverChip extends StatelessWidget {
  /// Creates the badge.
  const new({
    required this.text,
    this.icon,
    this.leading,
    this.background,
    this.foreground,
    this.tabular = false,
    this.tooltip,
    super.key,
  });

  /// The words.
  final String text;

  /// An icon before the words.
  final IconData? icon;

  /// A picture before the words (the platform logo); replaces [icon].
  final Widget? leading;

  /// The capsule's colour; null is the translucent dark one.
  final Color? background;

  /// The words' colour; null is white.
  final Color? foreground;

  /// Figures in tabular form (audience).
  final bool tabular;

  /// Shown on hover and read by screen readers.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ink = foreground ?? OnVideoColors.foreground;
    var style = (Theme.of(context).textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 12,
      height: 1.2,
      color: ink,
      fontWeight: FontWeight.w600,
    );
    if (tabular) style = style.tabular;
    final chip = Container(
      height: 22,
      padding: EdgeInsets.only(left: leading != null ? 3 : 7, right: 7),
      decoration: BoxDecoration(color: background ?? LiveRoomCardColors.chip, borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (leading case final picture?) picture else if (icon case final glyph?) Icon(glyph, size: 14, color: ink),
          Flexible(
            child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: style),
          ),
        ],
      ),
    );
    final message = tooltip;
    if (message == null) return chip;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(label: message, container: true, excludeSemantics: true, child: chip),
    );
  }
}

/// The static placeholder of a [LiveRoomCard] while the first rooms load
/// (U.4a c8): the same size, no shimmer.
class RoomCardSkeleton extends StatelessWidget {
  /// Creates the placeholder.
  const new({this.appearance = RoomCardAppearance.standard, this.dense = true, super.key});

  /// The card settings (radius, layout, avatar).
  final RoomCardAppearance appearance;

  /// The small form.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final block = scheme.surfaceContainerHigh;
    final radius = BorderRadius.circular(appearance.cornerRadius);
    Widget bar(double factor) => FractionallySizedBox(
      widthFactor: factor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(5)),
      ),
    );
    final avatarSize = dense ? 34.0 : 40.0;
    final caption = Row(
      children: [
        if (appearance.showAvatar) ...[
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(color: block, shape: BoxShape.circle),
          ),
          SizedBox(width: dense ? 8 : 12),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bar(0.86), const SizedBox(height: 8), bar(0.46)],
          ),
        ),
      ],
    );
    final compact = appearance.layout == RoomCardLayout.compact;
    return DecoratedBox(
      key: const ValueKey('room-card-skeleton'),
      decoration: BoxDecoration(color: LiveRoomCardColors.surface(scheme, theme.brightness), borderRadius: radius),
      child: compact
          ? SizedBox(
              height: RoomCardLayoutMetrics.compactHeight(appearance: appearance, dense: dense),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: caption),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: block, borderRadius: radius),
                  ),
                ),
                SizedBox(
                  height: LiveRoomCardMetrics.captionHeight(
                    dense: dense,
                    appearance: appearance,
                    textScaler: MediaQuery.textScalerOf(context),
                    fontSizes: LiveFontSizes.of(theme.textTheme),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
                    child: caption,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A room that is not live as one row (U.4c c5, candidate C-5): the
/// avatar with the platform's logo on its corner, the streamer (15 points)
/// and the last title; 64 high. Tap, long press and right click as on a
/// card.
class RoomRow extends StatefulWidget {
  /// Creates the row.
  const new({required this.data, this.onTap, this.onLongPress, this.trailing, super.key});

  /// What to show ([RoomCardData.anchorName] first, then the title).
  final RoomCardData data;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card dialog (long press and right click).
  final VoidCallback? onLongPress;

  /// Shown at the end of the row (a status).
  final Widget? trailing;

  /// The row's height before text scaling.
  static const double height = 64;

  @override
  State<RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<RoomRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = AppTextStyles(theme);
    final data = widget.data;
    final radius = BorderRadius.circular(12);
    final keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final surface = scheme.surface;
    final row = Material(
      color: _hovered ? scheme.surfaceContainerHigh : LiveRoomCardColors.surface(scheme, theme.brightness),
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onLongPress,
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RoomRow.height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CommonAvatar(avatarUrl: data.avatarUrl, fallbackName: data.anchorName),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          key: const ValueKey('room-row-platform'),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: surface, width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: PlatformLogo(data.platformId, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.anchorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.t15.copyWith(fontWeight: FontWeight.w600, height: 1.4, color: scheme.onSurface),
                      ),
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.t13.copyWith(height: 1.4, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                ?widget.trailing,
              ],
            ),
          ),
        ),
      ),
    );
    // Always the same wrapper, so the ink well keeps its focus.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: _focused && keyboard
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: scheme.primary, width: 3, strokeAlign: BorderSide.strokeAlignOutside),
            )
          : const BoxDecoration(),
      child: row,
    );
  }
}
