import 'package:flutter/material.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_theme.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/avatar.dart';
import 'package:live_ui/src/widgets/network_image.dart';
import 'package:live_ui/src/widgets/room_card_appearance.dart';
import 'package:live_ui/src/widgets/status_view.dart';
import 'package:remixicon/remixicon.dart';

/// What an audience figure counts (3.x `AudienceMetricType`).
enum RoomAudienceKind {
  /// Popularity or heat.
  popularity,

  /// Viewers online now.
  onlineViewers,

  /// Total views.
  totalViewers,

  /// Followers.
  followers,

  /// Not known.
  unknown,
}

/// The audience a card shows: its kind and the figure already formatted by
/// the app (`1.2万`); an empty [value] shows "pending" (3.x
/// `audience_waiting`).
@immutable
final class RoomAudience {
  /// Creates the figure.
  const new({required this.kind, required this.value});

  /// What it counts.
  final RoomAudienceKind kind;

  /// The formatted figure.
  final String value;

  @override
  bool operator ==(Object other) => other is RoomAudience && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// What a room card shows, mapped by the app from its room model.
@immutable
final class RoomCardData {
  /// Creates the data.
  const new({
    required this.platformId,
    required this.title,
    required this.anchorName,
    this.avatarUrl,
    this.coverUrl,
    this.isLive = false,
    this.isReplay = false,
    this.audience,
    this.restrictionLabel,
    this.platformName,
    this.isOffline = false,
  });

  /// Platform id; the badge shows it in capitals (3.x).
  final String platformId;

  /// Broadcast title.
  final String title;

  /// Streamer's name.
  final String anchorName;

  /// Avatar address (normalised by the app).
  final String? avatarUrl;

  /// Cover address (normalised by the app); empty or null shows the fallback.
  final String? coverUrl;

  /// Live now: the audience shows only then.
  final bool isLive;

  /// A replay (3.x `isRecord`).
  final bool isReplay;

  /// The audience figure.
  final RoomAudience? audience;

  /// Why the room cannot simply be played (paid, password, app only, region
  /// …), as the words to show; null shows nothing (docs/UPGRADES.md: "卡片
  /// 标出受限类型").
  final String? restrictionLabel;

  /// The platform's name to show beside its logo (`LiveRoomCard`'s platform
  /// chip, U.4a c2); null shows the id in capitals.
  final String? platformName;

  /// The platform says the streamer is off (offline, banned, carousel): the
  /// cover is dimmed and marked (`LiveRoomCard`, U.4a c4).
  final bool isOffline;

  @override
  bool operator ==(Object other) =>
      other is RoomCardData &&
      other.platformId == platformId &&
      other.title == title &&
      other.anchorName == anchorName &&
      other.avatarUrl == avatarUrl &&
      other.coverUrl == coverUrl &&
      other.isLive == isLive &&
      other.isReplay == isReplay &&
      other.audience == audience &&
      other.restrictionLabel == restrictionLabel &&
      other.platformName == platformName &&
      other.isOffline == isOffline;

  @override
  int get hashCode => Object.hash(
    platformId,
    title,
    anchorName,
    avatarUrl,
    coverUrl,
    isLive,
    isReplay,
    audience,
    restrictionLabel,
    platformName,
    isOffline,
  );
}

/// A live room card (3.x `RoomCard`): a 16:9 cover with platform, replay,
/// audience and delete badges above the avatar, title and streamer, or the
/// compact one-row layout, as [appearance] says.
///
/// The card only draws: opening the room ([onTap]) and the card menu
/// ([onLongPress], also on right click) are the page's (3.x opened the room
/// and its follow/tag/share menu from inside the card).
class RoomCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.data,
    this.appearance = RoomCardAppearance.standard,
    this.dense = false,
    this.statusPending = false,
    this.statusPendingLabel,
    this.showDelete = false,
    this.onDelete,
    this.deleteTooltip,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// What to show.
  final RoomCardData data;

  /// How to show it (the card settings for the current screen size).
  final RoomCardAppearance appearance;

  /// The smaller form (multi-column grids).
  final bool dense;

  /// The live status is being checked: a "verifying" badge replaces the
  /// audience.
  final bool statusPending;

  /// Words of the [statusPending] badge; null shows "verifying".
  final String? statusPendingLabel;

  /// Shows a delete button.
  final bool showDelete;

  /// The delete button's action.
  final VoidCallback? onDelete;

  /// The delete button's tooltip; null shows "delete".
  final String? deleteTooltip;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card menu (long press and right click).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = appearance.cornerRadius;
    final words = LiveUiScope.of(context).strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final showAutomaticPlatformBadge =
            appearance.automaticPlatformBadge && !dense && constraints.maxWidth >= 280 && textScale < 1.8;
        final parts = _CardParts(card: this, theme: theme, words: words);
        return Card(
          key: const ValueKey('room-card-surface'),
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          color: isDark ? Colors.grey[900] : Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onLongPress,
            child: appearance.layout == RoomCardLayout.compact
                ? parts.compact(
                    context,
                    showAutomaticPlatformBadge: showAutomaticPlatformBadge,
                    availableWidth: constraints.maxWidth,
                    textScale: textScale,
                  )
                : parts.cover(context, showAutomaticPlatformBadge: showAutomaticPlatformBadge),
          ),
        );
      },
    );
  }
}

final class _CardParts {
  new({required this.card, required this.theme, required this.words})
    : styles = AppTextStyles(theme),
      isDark = theme.brightness == Brightness.dark;

  final RoomCard card;
  final ThemeData theme;
  final LiveUiStrings words;
  final AppTextStyles styles;
  final bool isDark;

  RoomCardData get data => card.data;
  RoomCardAppearance get appearance => card.appearance;
  bool get dense => card.dense;
  String get platformText => data.platformId.toUpperCase();
  String get pendingText => card.statusPendingLabel ?? words.verifying;
  bool get showAudience => appearance.showAudience && data.isLive;
  bool get showReplay => appearance.showReplayBadge && data.isReplay;

  Color get titleColor => isDark ? Colors.white : Colors.black87;
  Color? get anchorColor => isDark ? Colors.grey[400] : Colors.grey[700];

  Widget coverImage(BuildContext context) {
    final url = data.coverUrl?.trim() ?? '';
    if (url.isEmpty) return coverFallback();
    // A stable image element with an encoded disk entry: 3.x found that
    // rebuilding every cover at once (a global epoch) caused flashes and CPU
    // spikes on refresh.
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width / 2;
        final cacheWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(240, 720);
        return LiveNetworkImage(
          url: url,
          memCacheWidth: cacheWidth,
          placeholder: (_) => coverPlaceholder(),
          error: (_) => coverFallback(),
        );
      },
    );
  }

  // One static icon per loading card: an animation per card repainted the
  // whole grid at the display rate in 3.x's early versions.
  Widget coverPlaceholder() => ColoredBox(
    color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
    child: Center(child: Icon(Icons.live_tv_rounded, size: 24, color: isDark ? Colors.white24 : Colors.black12)),
  );

  Widget coverFallback() => ColoredBox(
    key: const ValueKey('room-card-cover-fallback'),
    color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
    child: const AppStatusView(type: AppStatusType.error, title: '', subtitle: '', isMini: true),
  );

  Widget audienceBadge({required bool dense}) {
    final audience = data.audience ?? const RoomAudience(kind: RoomAudienceKind.unknown, value: '');
    final label = switch (audience.kind) {
      RoomAudienceKind.popularity => words.audiencePopularity,
      RoomAudienceKind.onlineViewers => words.audienceOnline,
      RoomAudienceKind.totalViewers => words.audienceTotal,
      RoomAudienceKind.followers => words.audienceFollowers,
      RoomAudienceKind.unknown => words.audienceCount,
    };
    final value = audience.value.isEmpty ? words.audienceWaiting : audience.value;
    return CoverMetricBadge(
      key: const ValueKey('cover-audience-metric'),
      icon: switch (audience.kind) {
        RoomAudienceKind.onlineViewers => Icons.people_alt_rounded,
        RoomAudienceKind.followers => Icons.favorite_rounded,
        RoomAudienceKind.totalViewers => Icons.visibility_rounded,
        _ => Icons.whatshot_rounded,
      },
      value: value,
      semanticLabel: '$label $value',
      dense: dense,
    );
  }

  Widget pendingBadge({required bool dense}) =>
      CoverMetricBadge(icon: Icons.sync_rounded, value: pendingText, semanticLabel: pendingText, dense: dense);

  Widget restrictionBadge(String label, {required bool dense}) => CoverMetricBadge(
    key: const ValueKey('room-card-restriction'),
    icon: Icons.lock_rounded,
    value: label,
    semanticLabel: label,
    dense: dense,
  );

  Widget replayChip({required bool dense}) => CountChip(
    key: const ValueKey('room-card-replay-badge'),
    icon: Icons.videocam_rounded,
    count: words.replay,
    dense: dense,
    color: theme.primaryColor,
  );

  Widget avatar() => KeyedSubtree(
    key: const ValueKey('room-card-avatar'),
    child: CommonAvatar(avatarUrl: data.avatarUrl, fallbackName: data.anchorName, dense: dense),
  );

  Widget title({double? height}) => Text(
    data.title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (dense ? styles.t13 : styles.t15).copyWith(height: height, fontWeight: FontWeight.w600, color: titleColor),
  );

  Widget anchorName({double? height}) => Text(
    data.anchorName,
    key: const ValueKey('room-card-anchor-name'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (dense ? styles.t12 : styles.t13).copyWith(height: height, fontWeight: FontWeight.w500, color: anchorColor),
  );

  Widget tonalPlatformBadge({required bool compactRow}) => Container(
    key: const ValueKey('room-card-platform-badge'),
    padding: compactRow
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: isDark ? Colors.grey[800] : Colors.grey[100],
      borderRadius: BorderRadius.circular(compactRow ? 7 : 8),
    ),
    child: Text(
      platformText,
      maxLines: compactRow ? 1 : null,
      overflow: compactRow ? TextOverflow.fade : null,
      softWrap: compactRow ? false : null,
      style: styles.t11.copyWith(
        fontSize: compactRow ? 10 : null,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey[300] : Colors.grey[800],
      ),
    ),
  );

  Widget deleteButton({required bool onCover}) => IconButton(
    key: const ValueKey('room-card-delete'),
    tooltip: card.deleteTooltip ?? words.delete,
    onPressed: card.onDelete,
    padding: onCover ? const EdgeInsets.all(10) : EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: onCover
        ? Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
            child: Icon(RemixIcons.delete_bin_line, color: Colors.white, size: dense ? 16 : 18),
          )
        : Icon(RemixIcons.delete_bin_line, size: dense ? 17 : 19),
  );

  Widget cover(BuildContext context, {required bool showAutomaticPlatformBadge}) {
    final radius = appearance.cornerRadius;
    final restriction = data.restrictionLabel;
    return Column(
      key: const ValueKey('room-card-cover-layout'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: ColoredBox(color: isDark ? Colors.grey[850]! : Colors.grey.shade100, child: coverImage(context)),
              ),
            ),
            if (appearance.showPlatformBadge)
              Positioned(
                key: const ValueKey('room-card-platform-badge'),
                left: 8,
                top: 8,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 3 : 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    platformText,
                    style: styles.t11.copyWith(
                      fontSize: dense ? 10 : null,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (showReplay)
              Positioned(
                right: card.showDelete ? (dense ? 44 : 48) : 8,
                top: 8,
                child: replayChip(dense: dense),
              ),
            if (restriction != null && restriction.isNotEmpty)
              Positioned(left: 8, bottom: 8, child: restrictionBadge(restriction, dense: dense)),
            if (card.statusPending)
              Positioned(right: 8, bottom: 8, child: pendingBadge(dense: dense))
            else if (showAudience)
              Positioned(right: 8, bottom: 8, child: audienceBadge(dense: dense)),
            if (card.showDelete) Positioned(right: 0, top: 0, child: deleteButton(onCover: true)),
          ],
        ),
        ListTile(
          dense: dense,
          minLeadingWidth: dense ? 34 : 40,
          contentPadding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 4 : 6),
          horizontalTitleGap: dense ? 8 : 12,
          leading: appearance.showAvatar ? avatar() : null,
          title: title(),
          subtitle: appearance.showAnchorName ? anchorName() : null,
          trailing: showAutomaticPlatformBadge ? tonalPlatformBadge(compactRow: false) : null,
        ),
      ],
    );
  }

  Widget? compactTrailing({
    required bool showAutomaticPlatformBadge,
    required double availableWidth,
    required double textScale,
  }) {
    final minimumMetricWidth = card.showDelete ? 360.0 : (dense ? 260.0 : 300.0);
    final canShowMetrics = availableWidth >= minimumMetricWidth && textScale < 1.8;
    final restriction = data.restrictionLabel;
    final children = <Widget>[
      if (canShowMetrics) ...[
        if (appearance.showPlatformBadge || showAutomaticPlatformBadge) tonalPlatformBadge(compactRow: true),
        if (restriction != null && restriction.isNotEmpty) restrictionBadge(restriction, dense: true),
        if (card.statusPending)
          pendingBadge(dense: true)
        else if (showAudience)
          audienceBadge(dense: true)
        else if (showReplay)
          replayChip(dense: true),
      ] else if (card.statusPending)
        Tooltip(message: pendingText, child: const Icon(Icons.sync_rounded, size: 18)),
      if (card.showDelete) deleteButton(onCover: false),
    ];
    if (children.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: children),
    );
  }

  Widget compact(
    BuildContext context, {
    required bool showAutomaticPlatformBadge,
    required double availableWidth,
    required double textScale,
  }) {
    final height = RoomCardLayoutMetrics.compactHeight(
      appearance: appearance,
      dense: dense,
      hasAction: card.showDelete,
      textScaler: MediaQuery.textScalerOf(context),
      fontSizes: LiveFontSizes.of(theme.textTheme),
    );
    final trailing = compactTrailing(
      showAutomaticPlatformBadge: showAutomaticPlatformBadge,
      availableWidth: availableWidth,
      textScale: textScale,
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
                  title(height: 1.2),
                  if (appearance.showAnchorName) ...[SizedBox(height: dense ? 2 : 3), anchorName(height: 1.2)],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A capsule with an icon and a short text on a colour (3.x `CountChip`,
/// the replay badge).
class CountChip extends StatelessWidget {
  /// Creates the chip.
  const new({required this.icon, required this.count, required this.color, this.dense = false, super.key});

  /// Icon.
  final IconData icon;

  /// Text.
  final String count;

  /// The smaller form.
  final bool dense;

  /// Background colour.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    return Card(
      shape: const StadiumBorder(),
      color: color,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 4 : 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: dense ? 16 : 18),
            const SizedBox(width: 4),
            Text(
              count,
              style: (dense ? styles.t12 : styles.t13).copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact figure on a cover (3.x `CoverMetricBadge`): neutral dark
/// background so it reads on bright and dark pictures; the full meaning is
/// the tooltip and the semantics label.
class CoverMetricBadge extends StatelessWidget {
  /// Creates the badge.
  const new({required this.icon, required this.value, required this.semanticLabel, this.dense = false, super.key});

  /// Icon.
  final IconData icon;

  /// Text.
  final String value;

  /// Tooltip and accessibility label.
  final String semanticLabel;

  /// The smaller form.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.58)
        : Colors.black.withValues(alpha: 0.48);
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        label: semanticLabel,
        container: true,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 4 : 5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(dense ? 10 : 12),
            border: Border.all(color: theme.primaryColor.withValues(alpha: 0.12), width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: dense ? 14 : 16),
              SizedBox(width: dense ? 4 : 5),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: dense ? 11 : 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
