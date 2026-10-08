import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/buttons/follow_button.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/logic/area_lookup.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// When a broadcast started, said the short way: `今天 19:18 开播`,
/// `昨天 23:05 开播`, else `10-01 19:18 开播` (with the year when it is not
/// this year's).
String startedText(DateTime startedAt, DateTime now) {
  final local = startedAt.toLocal();
  final today = now.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  final day = DateTime(local.year, local.month, local.day);
  final days = DateTime(today.year, today.month, today.day).difference(day).inDays;
  if (days == 0) return i18n('live_play_started_today', args: {'time': time});
  if (days == 1) return i18n('live_play_started_yesterday', args: {'time': time});
  final date = local.year == today.year
      ? '${two(local.month)}-${two(local.day)} $time'
      : '${local.year}-${two(local.month)}-${two(local.day)} $time';
  return i18n('live_play_started_on', args: {'date': date});
}

/// The room details (docs/A-界面设计/A07-直播间界面/A07.1-竖屏普通布局, "直播间详情"): laid over the tabs
/// and the chat, never over the picture, without a screen-wide shade. The
/// streamer with the platform, a tappable area and the follow button; the
/// state (live, replay, offline, restricted with the reason); the full
/// title; the audience figures and time on air; the announcement and the
/// introduction; room number and link to copy; share and open on the
/// platform. It closes with "收起", another tap on the room strip, a pull
/// down or Back.
class RoomDetailsPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  @override
  State<RoomDetailsPanel> createState() => _RoomDetailsPanelState();
}

class _RoomDetailsPanelState extends State<RoomDetailsPanel> {
  /// How far a pull past the top closes the panel.
  static const double _closePull = 64;

  double _pull = 0;
  bool _closing = false;

  LiveRoomController get _controller => widget.controller;

  void _close() {
    if (_closing) return;
    _closing = true;
    widget.onClose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      case ScrollStartNotification():
        _pull = 0;
      case OverscrollNotification(:final overscroll) when overscroll < 0:
        _pull -= overscroll;
        if (_pull >= _closePull) _close();
      case ScrollUpdateNotification(:final metrics) when metrics.pixels < -_closePull:
        _close();
      case ScrollEndNotification():
        _pull = 0;
      default:
        break;
    }
    return false;
  }

  int _signature() {
    final room = _controller.room;
    return Object.hash(
      Object.hash(room.nick, room.avatar, room.area, room.title, room.notice, room.introduction, room.link),
      Object.hash(room.effectiveLiveStatus, room.effectiveRestriction, room.startedAt, room.roomId),
      Object.hashAll(audienceFigures(room)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('live-play-details'),
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          const Divider(height: 1),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              if (details.delta.dy > 0) _pull += details.delta.dy;
              if (_pull >= _closePull) _close();
            },
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 600) _close();
              _pull = 0;
            },
            child: SizedBox(
              height: 20,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListenableSelector<int>(
                listenable: _controller,
                selector: _signature,
                builder: (context, _, _) => _Content(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final theme = Theme.of(context);
    final iptv = room.platform == SiteIds.iptv;
    final title = room.title.trim();
    final notice = room.notice?.trim() ?? '';
    final introduction = room.introduction?.trim() ?? '';
    final link = room.link?.trim() ?? '';
    final external = externalRoomTarget(room);
    return ListView(
      key: const ValueKey('live-play-details-list'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _Streamer(controller: controller),
        const SizedBox(height: 10),
        _State(controller: controller),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            title,
            key: const ValueKey('live-play-details-title'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.emphasis,
          ),
        ],
        _Figures(controller: controller),
        if (notice.isNotEmpty) _Expandable(label: i18n('live_play_info_notice'), text: platformNotice(notice)),
        if (introduction.isNotEmpty && introduction != notice)
          _Expandable(label: i18n('live_play_info_introduction'), text: introduction),
        const SizedBox(height: 4),
        _CopyRow(label: i18n('live_play_info_room_id'), value: room.roomId, keyName: 'room-id'),
        if (link.isNotEmpty)
          _CopyRow(label: i18n('live_play_details_link'), value: link, shown: linkWithoutScheme(link), keyName: 'link'),
        if (!iptv) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('live-play-details-share'),
                onPressed: () => unawaited(shareRoom(room)),
                icon: const Icon(AppIcons.share, size: 18),
                label: Text(i18n('share')),
              ),
              if (external != null)
                OutlinedButton.icon(
                  key: const ValueKey('live-play-details-open'),
                  onPressed: () => unawaited(openRoomExternally(room)),
                  icon: const Icon(AppIcons.openExternal, size: 18),
                  label: Text(i18n('live_play_open_in', args: {'platform': platformName(room.platform)})),
                ),
            ],
          ),
        ],
        SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

/// The avatar, name, platform and area (a tap opens the area's rooms) and
/// the follow button, in step with the bar's.
class _Streamer extends StatefulWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  State<_Streamer> createState() => _StreamerState();
}

class _StreamerState extends State<_Streamer> {
  bool _finding = false;

  Future<void> _openArea(String name) async {
    if (_finding) return;
    final site = widget.controller.site;
    setState(() => _finding = true);
    try {
      // A room carries its area's name only: the platform's list gives the
      // area to open (a route, not the areas page's own code).
      final area = findAreaByName(await site.getCategories(1, 1000), name);
      if (area == null) {
        AppNavigator.toast(i18n('live_play_area_not_found'));
        return;
      }
      await AppNavigator.toCategoryDetail(site: site, category: area);
    } on Object {
      AppNavigator.toast(i18n('live_play_area_not_found'));
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.controller.room;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final platform = platformName(room.platform);
    final area = room.area?.trim() ?? '';
    final secondary = theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant);
    return Row(
      children: [
        CommonAvatar(avatarUrl: room.avatar, radius: 24, fallbackName: room.nick),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.displayNick(platform),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.emphasis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  PlatformLogo(room.platform, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(platform, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                  ),
                  if (area.isNotEmpty) ...[
                    Text(' · ', style: secondary),
                    Flexible(
                      child: InkWell(
                        key: const ValueKey('live-play-details-area'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: room.platform == SiteIds.iptv ? null : () => unawaited(_openArea(area)),
                        // One text with its mark, cut short as a whole in a
                        // narrow column (a phone held sideways, A07.17 c2).
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: platformAreaName(room.platform, area)),
                              if (_finding)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: SizedBox.square(
                                      dimension: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              else if (room.platform != SiteIds.iptv)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(AppIcons.forward, size: 16, color: scheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FollowButton(room: room, latest: () => widget.controller.room, place: FollowButtonPlace.details),
      ],
    );
  }
}

/// "直播" in red with the start and the time on air; replay, offline and
/// restricted rooms say so, a restriction with its reason.
class _State extends StatelessWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant);
    final now = controller.now();
    final startedAt = room.startedAt;
    final (String tag, Color background, Color foreground, String detail) = switch (room.effectiveLiveStatus) {
      LiveStatus.live => (
        i18n('live_play_tag_live'),
        LiveSemanticColors.live,
        LiveSemanticColors.onLive,
        [if (startedAt != null) startedText(startedAt, now), ?liveDuration(room, now)].join(' · '),
      ),
      LiveStatus.replay => (
        i18n('replay'),
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        startedAt == null ? '' : startedText(startedAt, now),
      ),
      _ => (i18n('live_play_tag_offline'), scheme.surfaceContainerHighest, scheme.onSurfaceVariant, offlineText(room)),
    };
    final restriction = room.isRestricted ? restrictionLabel(room.effectiveRestriction) : null;
    return Column(
      key: const ValueKey('live-play-details-state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Mark(text: tag, background: background, foreground: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: secondary),
            ),
          ],
        ),
        if (restriction != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Mark(text: restriction, background: scheme.errorContainer, foreground: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  restrictionReason(room.effectiveRestriction),
                  style: theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const new({required this.text, required this.background, required this.foreground});

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge?.emphasis.copyWith(color: foreground)),
    ),
  );
}

/// The audience figures the platform gives and the time on air, in equal
/// cells.
class _Figures extends StatelessWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = (room.isLiveNow || room.isRecord) && room.platform != SiteIds.iptv;
    final figures = shown ? audienceFigures(room) : const <AudienceFigure>[];
    final startedAt = room.isLiveNow ? room.startedAt : null;
    if (figures.isEmpty && startedAt == null) return const SizedBox(height: 4);
    final value = theme.textTheme.titleLarge?.emphasis.tabular;
    final label = theme.textTheme.bodySmall?.regular.copyWith(color: scheme.onSurfaceVariant);
    Widget cell(Widget number, String name) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            DefaultTextStyle.merge(style: value, maxLines: 1, child: number),
            const SizedBox(height: 2),
            Text(name, style: label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
    final count = figures.length + (startedAt == null ? 0 : 1);
    return Padding(
      key: const ValueKey('live-play-details-figures'),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: LayoutBuilder(
        // The cells' width, for the time on air (the row's intrinsic height
        // cannot ask a layout builder inside it).
        builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth - 2 - (count - 1)) / count;
          final cells = [
            for (final figure in figures)
              cell(Text(figure.value.isEmpty ? '—' : readableAudience(figure.value)), audienceLabel(figure.type)),
            if (startedAt != null)
              // A07.17 c6: `12:13` where `12 小时 13 分` does not fit the cell.
              cell(
                OnAirClock(startedAt: startedAt, now: controller.now, style: value, fitWidth: cellWidth),
                i18n('live_play_on_air'),
              ),
          ];
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (final (index, child) in cells.indexed) ...[
                    if (index > 0) VerticalDivider(width: 1, color: scheme.outlineVariant),
                    child,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A labelled text of two lines with "展开" when it is longer.
class _Expandable extends StatefulWidget {
  const new({required this.label, required this.text});

  final String label;
  final String text;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge?.regular;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: theme.textTheme.bodySmall?.regular.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: widget.text, style: body),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 2,
              )..layout(maxWidth: constraints.maxWidth);
              final long = painter.didExceedMaxLines;
              painter.dispose();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      widget.text,
                      maxLines: _open ? null : 2,
                      overflow: _open ? null : TextOverflow.ellipsis,
                      style: body,
                    ),
                  ),
                  if (long)
                    TextButton(
                      onPressed: () => setState(() => _open = !_open),
                      child: Text(i18n(_open ? 'live_play_details_fold' : 'live_play_details_expand')),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// [link] as the details show it: without `https://` or `http://` (A07.17
/// c6; the copy is still the whole address).
String linkWithoutScheme(String link) => link.replaceFirst(RegExp('^https?://', caseSensitive: false), '');

/// A label, a value (shown as [shown] when given) and a copy button.
class _CopyRow extends StatelessWidget {
  const new({required this.label, required this.value, required this.keyName, this.shown});

  final String label;
  final String value;
  final String? shown;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(
            shown ?? value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.regular,
          ),
        ),
        IconButton(
          key: ValueKey('live-play-details-copy-$keyName'),
          tooltip: i18n('copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            AppNavigator.toast(i18n('copied_to_clipboard'));
          },
          icon: Icon(AppIcons.copy, size: 20, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
