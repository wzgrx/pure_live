import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// The room's state over the picture: entering, buffering, offline, failed
/// or restricted, with what OK does (pure_live_TV's placeholders).
class TvRoomStatus extends StatelessWidget {
  /// Creates the layer.
  const new({required this.controller, required this.playback, super.key});

  /// The room.
  final LiveRoomController controller;

  /// The session's state.
  final PlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final restricted = room.isRestricted && room.isLiveNow;
    final (busy, icon, title, subtitle, action) = switch (controller.stage) {
      RoomStage.loading => (true, null, i18n('live_play_entering'), null, null),
      RoomStage.failed => (
        false,
        Icons.error_outline_rounded,
        failureText(controller.failure),
        null,
        i18n('tv_ok_retry'),
      ),
      RoomStage.offline => (false, Icons.nightlight_round, offlineText(room), null, i18n('tv_ok_refresh')),
      RoomStage.unplayable => (
        false,
        restricted ? Icons.lock_outline_rounded : Icons.videocam_off_outlined,
        restricted ? restrictionReason(room.effectiveRestriction) : failureText(controller.failure),
        restricted ? failureText(controller.failure) : null,
        i18n('tv_ok_retry'),
      ),
      RoomStage.playing => switch (playback.status) {
        PlaybackStatus.idle || PlaybackStatus.opening || PlaybackStatus.buffering => (true, null, '', null, null),
        PlaybackStatus.error => (
          false,
          Icons.error_outline_rounded,
          i18n('playback_failure_title'),
          failureText(playback.error),
          i18n('tv_ok_retry'),
        ),
        _ => (false, null, null, null, null),
      },
    };
    if (!busy && title == null) return const SizedBox.shrink();
    final scale = TvScale.of(context);
    return IgnorePointer(
      child: ColoredBox(
        color: busy ? Colors.transparent : Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: scale(56),
                  child: CircularProgressIndicator(color: Colors.white70, strokeWidth: scale(5)),
                )
              else if (icon != null)
                Icon(icon, color: Colors.white70, size: scale(72)),
              if (title != null && title.isNotEmpty) ...[
                SizedBox(height: scale(16)),
                Text(
                  title,
                  key: const ValueKey('tv-room-status'),
                  textAlign: TextAlign.center,
                  style: scale.style(28, weight: FontWeight.w600, color: Colors.white),
                ),
              ],
              if (subtitle != null && subtitle.isNotEmpty && subtitle != title) ...[
                SizedBox(height: scale(8)),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: scale.style(20, color: Colors.white70),
                ),
              ],
              if (action != null) ...[
                SizedBox(height: scale(20)),
                Text(
                  action,
                  style: scale.style(20, weight: FontWeight.w600, color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The new room's place and name, shown for a moment after a switch
/// (pure_live_TV's channel banner).
class TvChannelBanner extends StatelessWidget {
  /// Creates the banner.
  const new({required this.room, required this.index, required this.count, super.key});

  /// The room.
  final LiveRoom room;

  /// Its place in the list.
  final int index;

  /// The length of the list.
  final int count;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final title = room.title.trim();
    return Container(
      key: const ValueKey('tv-room-banner'),
      margin: EdgeInsets.all(scale(32)),
      padding: EdgeInsets.symmetric(horizontal: scale.text(24), vertical: scale.text(16)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(scale(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${index + 1}',
            style: scale.style(44, weight: FontWeight.w800, color: Colors.white),
          ),
          SizedBox(width: scale(20)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scale(760)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  room.displayNick(platformName(room.platform)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.style(26, weight: FontWeight.w700, color: Colors.white),
                ),
                Text(
                  '${platformName(room.platform)} · ${title.isEmpty ? i18n('untitled_room') : title} · ${index + 1}/$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.style(19, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The control layer at the bottom (pure_live_TV's control bar, the basic
/// part): the room's title, streamer and audience, then quality, line,
/// danmaku, follow, refresh and the room list. The first button has the
/// focus when the layer opens; Left and Right walk the buttons.
class TvRoomControls extends StatelessWidget {
  /// Creates the layer.
  const new({
    required this.controller,
    required this.followed,
    required this.danmakuOn,
    required this.onQuality,
    required this.onLine,
    required this.onDanmaku,
    required this.onFollow,
    required this.onRefresh,
    required this.onList,
    this.firstButton,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The node of the first button (the page focuses it when the layer
  /// opens: the room's key node holds the focus, so `autofocus` would not).
  final FocusNode? firstButton;

  /// Whether the room is followed.
  final bool followed;

  /// Whether danmaku are shown.
  final bool danmakuOn;

  /// Picks the quality.
  final VoidCallback onQuality;

  /// Picks the line.
  final VoidCallback onLine;

  /// Shows or hides danmaku.
  final VoidCallback onDanmaku;

  /// Follows or unfollows.
  final VoidCallback onFollow;

  /// Loads the room again.
  final VoidCallback onRefresh;

  /// Opens the room list.
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final room = controller.room;
    final qualities = controller.qualities;
    final quality = qualities.isEmpty ? null : qualities[controller.qualityIndex.clamp(0, qualities.length - 1)];
    final playback = controller.session.state;
    final title = room.title.trim();
    final figures = [
      for (final figure in audienceFigures(room)) '${audienceLabel(figure.type)} ${readableAudience(figure.value)}',
    ];
    return Container(
      key: const ValueKey('tv-room-controls'),
      padding: EdgeInsets.fromLTRB(scale(48), scale(80), scale(48), scale(36)),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xDD000000)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, radius: scale.text(28)),
              SizedBox(width: scale(18)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? i18n('untitled_room') : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: scale.style(30, weight: FontWeight.w700, color: Colors.white),
                    ),
                    Text(
                      [
                        room.displayNick(platformName(room.platform)),
                        platformName(room.platform),
                        if ((room.area ?? '').trim() case final area when area.isNotEmpty) area,
                        ...figures,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: scale.style(20, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: scale(24)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _gap(
                  scale,
                  TvButton(
                    key: const ValueKey('tv-room-quality'),
                    focusNode: firstButton,
                    icon: Icons.high_quality_rounded,
                    label: quality == null ? i18n('tv_quality') : '${i18n('tv_quality')} ${quality.quality}',
                    onTap: qualities.length > 1 ? onQuality : null,
                  ),
                ),
                if (playback.lineCount > 1)
                  _gap(
                    scale,
                    TvButton(
                      key: const ValueKey('tv-room-line'),
                      icon: Icons.alt_route_rounded,
                      label: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                      onTap: onLine,
                    ),
                  ),
                _gap(
                  scale,
                  TvButton(
                    key: const ValueKey('tv-room-danmaku'),
                    icon: danmakuOn ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
                    label: i18n(danmakuOn ? 'tv_danmaku_on' : 'tv_danmaku_off'),
                    selected: danmakuOn,
                    onTap: onDanmaku,
                  ),
                ),
                _gap(
                  scale,
                  TvButton(
                    key: const ValueKey('tv-room-follow'),
                    icon: followed ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    label: i18n(followed ? 'followed' : 'follow'),
                    selected: followed,
                    onTap: onFollow,
                  ),
                ),
                _gap(
                  scale,
                  TvButton(
                    key: const ValueKey('tv-room-refresh'),
                    icon: Icons.refresh_rounded,
                    label: i18n('refresh'),
                    onTap: onRefresh,
                  ),
                ),
                TvButton(
                  key: const ValueKey('tv-room-list'),
                  icon: Icons.format_list_bulleted_rounded,
                  label: i18n('tv_room_list'),
                  onTap: onList,
                ),
              ],
            ),
          ),
          SizedBox(height: scale(16)),
          Text(i18n('tv_room_keys_hint'), style: scale.style(17, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _gap(TvScale scale, Widget child) => Padding(
    padding: EdgeInsets.only(right: scale(16)),
    child: child,
  );
}

/// The room list on the right (pure_live_TV's playlist panel): the rooms of
/// the list the room came from, the current one marked and focused; OK
/// switches to a room.
class TvRoomList extends StatefulWidget {
  /// Creates the list.
  const new({required this.rooms, required this.current, required this.onPick, super.key});

  /// The rooms.
  final List<LiveRoom> rooms;

  /// The room shown.
  final int current;

  /// Switches to a room.
  final ValueChanged<int> onPick;

  @override
  State<TvRoomList> createState() => _TvRoomListState();
}

class _TvRoomListState extends State<TvRoomList> {
  ScrollController? _scroll;
  final FocusNode _current = FocusNode(debugLabel: 'tv room list current');

  @override
  void initState() {
    super.initState();
    // The room's key node holds the focus, so `autofocus` would not move it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _current.context != null) _current.requestFocus();
    });
  }

  @override
  void dispose() {
    _scroll?.dispose();
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final rooms = widget.rooms;
    final current = widget.current;
    final extent = scale.text(96);
    // The current room is built (and focused) at once.
    final scroll = _scroll ??= ScrollController(initialScrollOffset: (current - 2).clamp(0, rooms.length) * extent);
    final width = scale.text(560);
    return Container(
      key: const ValueKey('tv-room-panel'),
      width: width,
      color: palette.background.withValues(alpha: 0.92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(scale(28), scale(28), scale(28), scale(12)),
            child: Text(
              '${i18n('tv_room_list')} (${rooms.length})',
              style: scale.style(26, weight: FontWeight.w700, color: palette.text),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: EdgeInsets.symmetric(horizontal: scale(20), vertical: scale(8)),
              itemExtent: extent,
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final title = room.title.trim();
                return Padding(
                  padding: EdgeInsets.only(bottom: scale(8)),
                  child: TvFocusable(
                    key: ValueKey('tv-room-list-$index'),
                    focusNode: index == current ? _current : null,
                    scale: 1.02,
                    onTap: () => widget.onPick(index),
                    builder: (context, focused) {
                      final color = focused ? palette.onFocusedCard : palette.text;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: scale.text(16)),
                        decoration: BoxDecoration(
                          color: focused ? palette.focusedCard : (index == current ? palette.subtleFill : null),
                          borderRadius: BorderRadius.circular(scale(14)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: scale.text(44),
                              child: Text(
                                '${index + 1}',
                                style: scale.style(22, weight: FontWeight.w800, color: color.withValues(alpha: 0.7)),
                              ),
                            ),
                            PlatformLogo(room.platform, size: scale.text(28)),
                            SizedBox(width: scale(12)),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    room.displayNick(platformName(room.platform)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: scale.style(21, weight: FontWeight.w600, color: color),
                                  ),
                                  Text(
                                    title.isEmpty ? i18n('untitled_room') : title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: scale.style(17, color: color.withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            ),
                            if (index == current)
                              Icon(Icons.play_arrow_rounded, color: palette.focus, size: scale.text(28)),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
