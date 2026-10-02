import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_switch.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// The rooms of the "切换直播间" panel (docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板): 3.x's small
// card (`play_other.dart` `_RoomSwitchCard`) and the list style's row.

/// "刚刚", "5 分钟前", "2 小时前", "3 天前".
String agoText(DateTime then, DateTime now) {
  final ago = agoOf(then, now);
  return switch (ago.unit) {
    AgoUnit.now => i18n('room_switch_ago_now'),
    AgoUnit.minutes => i18n('room_switch_ago_minutes', args: {'count': '${ago.count}'}),
    AgoUnit.hours => i18n('room_switch_ago_hours', args: {'count': '${ago.count}'}),
    AgoUnit.days => i18n('room_switch_ago_days', args: {'count': '${ago.count}'}),
  };
}

/// Where a room stands, as the panel marks it.
enum RoomSwitchState {
  /// On air: "直播中" in red.
  live,

  /// A replay: "回放".
  replay,

  /// Off air: the cover dimmed, "未开播 · 上次看 X 前".
  offline,

  /// Not known: no mark.
  unknown,
}

/// What a card or row shows of a room.
@immutable
final class RoomSwitchTileData {
  /// Creates the data.
  const new({
    required this.nick,
    required this.title,
    required this.platform,
    required this.area,
    required this.cover,
    required this.state,
    required this.audience,
    this.watched,
  });

  /// The data of [room]; [history] adds when it was last watched.
  factory of(LiveRoom room, {required AudiencePolicy policy, required DateTime now, bool history = false}) {
    final platform = platformName(room.platform);
    final title = room.title.trim();
    final watchedAt = room.lastWatchedAt;
    return RoomSwitchTileData(
      nick: room.displayNick(platform),
      title: title.isEmpty ? i18n('untitled_room') : title,
      platform: platform,
      area: room.area?.trim() ?? '',
      cover: normalizeImageUrl(room.cover),
      state: room.isLiveNow
          ? RoomSwitchState.live
          : room.isRecord
          ? RoomSwitchState.replay
          : room.isExplicitlyOfflineNow
          ? RoomSwitchState.offline
          : RoomSwitchState.unknown,
      audience: policy.audienceOf(room),
      watched: history && watchedAt != null && watchedAt > 0
          ? agoText(DateTime.fromMillisecondsSinceEpoch(watchedAt), now)
          : null,
    );
  }

  /// The streamer (the platform's name when unknown).
  final String nick;

  /// The room's title ("未命名直播间" when empty).
  final String title;

  /// The platform's name.
  final String platform;

  /// The area, or empty.
  final String area;

  /// The cover address, or empty.
  final String cover;

  /// Live, replay, offline or unknown.
  final RoomSwitchState state;

  /// The audience figure.
  final RoomAudience audience;

  /// How long ago it was watched (the history), or null.
  final String? watched;

  /// The mark of an offline room: "未开播 · 上次看 2 小时前" (or "未开播").
  String get offlineLabel =>
      watched == null ? i18n('room_switch_offline') : i18n('room_switch_offline_watched', args: {'ago': watched!});

  /// The list row's last line: "平台 · 分区", or the offline mark.
  String get line =>
      state == RoomSwitchState.offline ? offlineLabel : [platform, if (area.isNotEmpty) area].join(' · ');
}

IconData _audienceIcon(RoomAudienceKind kind) => switch (kind) {
  RoomAudienceKind.popularity => AppIcons.audienceHeat,
  RoomAudienceKind.totalViewers => AppIcons.audienceTotal,
  RoomAudienceKind.followers => AppIcons.audienceFollowers,
  RoomAudienceKind.onlineViewers || RoomAudienceKind.unknown => AppIcons.audienceOnline,
};

/// A mark on a cover: white on red ("直播中") or on dark.
class _Badge extends StatelessWidget {
  const new({required this.text, this.icon, this.live = false, super.key});

  final String text;
  final IconData? icon;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: live ? LiveSemanticColors.onLive : OnVideoColors.foreground,
      fontWeight: FontWeight.w700,
      fontSize: 10.5,
      height: 1,
    );
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: live ? LiveSemanticColors.live : OnVideoColors.dim,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            Icon(icon, size: 11, color: OnVideoColors.foreground),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
        ],
      ),
    );
  }
}

/// The marks at the cover's top left: "直播中" and the audience, "回放",
/// or the offline mark.
class _Marks extends StatelessWidget {
  const new({required this.data, this.short = false});

  final RoomSwitchTileData data;

  /// A small cover (the list): "未开播" without the watch time.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final audience = data.audience.value;
    final children = switch (data.state) {
      RoomSwitchState.live => [
        _Badge(key: const ValueKey('switch-live'), text: i18n('room_switch_live'), live: true),
        if (audience.isNotEmpty) _Badge(text: audience, icon: _audienceIcon(data.audience.kind)),
      ],
      RoomSwitchState.replay => [
        _Badge(text: i18n('room_switch_replay'), icon: AppIcons.replay),
        if (audience.isNotEmpty) _Badge(text: audience, icon: _audienceIcon(data.audience.kind)),
      ],
      RoomSwitchState.offline => [
        _Badge(key: const ValueKey('switch-offline'), text: short ? i18n('room_switch_offline') : data.offlineLabel),
      ],
      RoomSwitchState.unknown => [
        if (data.watched case final watched? when !short)
          _Badge(text: i18n('room_switch_watched', args: {'ago': watched})),
      ],
    };
    return Wrap(spacing: 4, runSpacing: 4, children: children);
  }
}

/// The cover: the picture (or a placeholder), dimmed when off air, the
/// marks at the top left and, with [title], the title along the bottom.
class _Cover extends StatelessWidget {
  const new({required this.data, this.title = false, this.short = false});

  final RoomSwitchTileData data;
  final bool title;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget placeholder(BuildContext context) => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(AppIcons.switchRoomEmpty, size: 28, color: scheme.onSurfaceVariant)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (data.cover.isEmpty)
          placeholder(context)
        else
          LayoutBuilder(
            builder: (context, constraints) => LiveNetworkImage(
              url: data.cover,
              placeholder: placeholder,
              error: placeholder,
              memCacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(160, 720),
            ),
          ),
        if (data.state == RoomSwitchState.offline)
          const ColoredBox(key: ValueKey('switch-dim'), color: OnVideoColors.dim),
        if (title)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [OnVideoColors.clear, OnVideoColors.scrim],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 5),
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: OnVideoColors.foreground, fontSize: 11),
                ),
              ),
            ),
          ),
        Positioned(
          left: short ? 4 : 6,
          top: short ? 4 : 6,
          right: short ? 4 : 6,
          child: Align(
            alignment: Alignment.topLeft,
            child: _Marks(data: data, short: short),
          ),
        ),
      ],
    );
  }
}

/// 3.x's small card (`_RoomSwitchCard`): the cover with the marks and the
/// title, then the streamer on one line ([footer] high), and the platform
/// on its right when the list mixes platforms (U.2m X4).
class RoomSwitchCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.data,
    required this.onTap,
    required this.onLongPress,
    this.footer = roomSwitchCardFooter,
    this.showPlatform = false,
    super.key,
  });

  /// What it shows.
  final RoomSwitchTileData data;

  /// Picks the room.
  final VoidCallback onTap;

  /// The room card's dialog.
  final VoidCallback onLongPress;

  /// The name line's height.
  final double footer;

  /// The platform's name after the streamer.
  final bool showPlatform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = data.state == RoomSwitchState.offline;
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Cover(data: data, title: true)),
            SizedBox(
              height: footer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.nick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.emphasis.copyWith(
                          color: offline ? scheme.onSurfaceVariant : scheme.onSurface,
                        ),
                      ),
                    ),
                    if (showPlatform) ...[
                      const SizedBox(width: 6),
                      Text(
                        data.platform,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list style's row: a 112 × 63 cover with the marks, the streamer, the
/// title and "平台 · 分区" (U.2m c4).
class RoomSwitchRow extends StatelessWidget {
  /// Creates the row.
  const new({required this.data, required this.onTap, required this.onLongPress, super.key});

  /// What it shows.
  final RoomSwitchTileData data;

  /// Picks the room.
  final VoidCallback onTap;

  /// The room card's dialog.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = data.state == RoomSwitchState.offline;
    final main = offline ? scheme.onSurfaceVariant : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              height: 63,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _Cover(data: data, short: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.nick,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.emphasis.copyWith(color: main),
                  ),
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: main),
                  ),
                  Text(
                    data.line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
