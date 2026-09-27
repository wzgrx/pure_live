import 'package:flutter/material.dart';
import 'package:live_ui/src/badges.dart';
import 'package:live_ui/src/metrics.dart';

/// Card density (principles §4.3).
enum CardDensity {
  /// Streamer name and title on two lines.
  standard,

  /// "Streamer · title" on one line.
  compact,
}

/// A live room card: 16:9 cover with platform logo, live badge and audience,
/// then the streamer and title (principles §4.3).
///
/// The cover is an [ImageProvider] so the app decides caching and decode size.
class RoomCardView extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.platformId,
    required this.anchorName,
    required this.title,
    required this.isLive,
    this.cover,
    this.audience,
    this.liveFor,
    this.density = CardDensity.standard,
    this.onTap,
    this.onMenu,
    super.key,
  });

  /// Platform id for the logo (`douyu`).
  final String platformId;

  /// Streamer's name.
  final String anchorName;

  /// Broadcast title.
  final String title;

  /// Whether the room is live now.
  final bool isLive;

  /// Cover image; a neutral placeholder when null or failing.
  final ImageProvider? cover;

  /// Formatted audience figure (`355.1万`), shown bottom right.
  final String? audience;

  /// Formatted live duration (`01:24`), shown next to the live badge.
  final String? liveFor;

  /// Text density.
  final CardDensity density;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card menu: long press on touch, right click on desktop.
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final label = isLive ? '$anchorName，直播中，$title' : '$anchorName，未开播，$title';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onSecondaryTap: onMenu,
        child: InkWell(
          onTap: onTap,
          onLongPress: onMenu,
          borderRadius: BorderRadius.circular(Radii.r2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.r2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: scheme.surfaceContainerHighest),
                      if (cover != null)
                        Image(
                          image: cover!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      Positioned(
                        left: Space.s1 + 2,
                        top: Space.s1 + 2,
                        child: PlatformLogo(platformId: platformId),
                      ),
                      if (isLive)
                        Positioned(
                          left: Space.s1 + 2,
                          bottom: Space.s1 + 2,
                          child: LiveBadge(duration: liveFor),
                        ),
                      if (audience != null)
                        Positioned(right: Space.s1 + 2, bottom: Space.s1 + 2, child: CoverLabel(audience!)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, Space.s1),
                child: density == CardDensity.standard
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(anchorName, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            title,
                            style: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: anchorName, style: text.titleSmall),
                            TextSpan(
                              text: ' · $title',
                              style: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row for an offline followed streamer: avatar, name, last live time; no
/// cover is loaded (principles §4.1).
class OfflineRoomRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.platformId,
    required this.anchorName,
    this.avatar,
    this.subtitle,
    this.onTap,
    this.onMenu,
    super.key,
  });

  /// Platform id for the logo.
  final String platformId;

  /// Streamer's name.
  final String anchorName;

  /// Avatar image.
  final ImageProvider? avatar;

  /// Secondary line (`上次开播 3 小时前`).
  final String? subtitle;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card menu.
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTap: onMenu,
      child: ListTile(
        onTap: onTap,
        onLongPress: onMenu,
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundImage: avatar,
          child: Text(anchorName.isEmpty ? '?' : anchorName.characters.first),
        ),
        title: Text(anchorName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1),
        trailing: PlatformLogo(platformId: platformId, size: Sizes.iconDense),
      ),
    );
  }
}
