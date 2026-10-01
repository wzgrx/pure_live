import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';
import 'package:pure_live/pages/live_play/room_texts.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The app bar title: avatar, streamer and platform / area (3.x
/// `LivePlayHeader._buildTitle`).
class RoomTitle extends StatelessWidget {
  /// Creates the title.
  const new({required this.room, super.key});

  /// The room.
  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = platformName(room.platform);
    final area = room.area?.trim() ?? '';
    return Row(
      children: [
        CommonAvatar(avatarUrl: room.avatar, radius: 16, fallbackName: room.nick),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.displayNick(platform),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                area.isEmpty ? platform : '$platform / $area',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Follow and unfollow (3.x `FavoriteFloatingButton`): unfollowing asks
/// first; the state follows the store, so a change elsewhere shows here.
class FollowButton extends ConsumerStatefulWidget {
  /// Creates the button.
  const new({required this.room, this.compact = false, super.key});

  /// The room.
  final LiveRoom room;

  /// An icon instead of a labelled button.
  final bool compact;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _pending = false;
  late Stream<bool> _followed;

  @override
  void initState() {
    super.initState();
    _followed = ref.read(storeProvider).follows.watchContains(widget.room);
  }

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.room.hasSameIdentity(widget.room)) {
      _followed = ref.read(storeProvider).follows.watchContains(widget.room);
    }
  }

  Future<void> _toggle(bool followed) async {
    if (_pending) return;
    final room = widget.room;
    final follows = ref.read(storeProvider).follows;
    setState(() => _pending = true);
    try {
      if (!followed) {
        if (await follows.add(room)) AppNavigator.toast(i18n('live_play_followed_toast'));
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(i18n('unfollow')),
          content: Text(i18n('unfollow_message', args: {'name': room.displayNick(platformName(room.platform))})),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(i18n('confirm'))),
          ],
        ),
      );
      if (confirmed ?? false) await follows.remove(room);
    } on Object {
      AppNavigator.toast(i18n('favorite_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _followed,
    builder: (context, snapshot) {
      final followed = snapshot.data ?? false;
      final known = snapshot.hasData;
      final label = i18n(followed ? 'followed' : 'follow');
      final onPressed = _pending || !known ? null : () => unawaited(_toggle(followed));
      if (widget.compact) {
        return IconButton(
          key: const ValueKey('live-play-follow'),
          tooltip: label,
          isSelected: followed,
          onPressed: onPressed,
          icon: Icon(followed ? Icons.favorite_rounded : Icons.favorite_border_rounded),
        );
      }
      final button = followed
          ? FilledButton.tonalIcon(
              key: const ValueKey('live-play-follow'),
              onPressed: onPressed,
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: Text(label),
            )
          : FilledButton.icon(
              key: const ValueKey('live-play-follow'),
              onPressed: onPressed,
              icon: const Icon(Icons.favorite_border_rounded, size: 18),
              label: Text(label),
            );
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: button);
    },
  );
}

/// The room's audience, every figure with its own label (online, heat,
/// cumulative), and the time on air.
class AudienceRow extends StatelessWidget {
  /// Creates the row.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = controller.room;
    final style = theme.textTheme.bodySmall;
    final figures = room.isLiveNow || room.isRecord ? audienceFigures(room) : const <AudienceFigure>[];
    final startedAt = room.startedAt;
    final chips = <Widget>[
      for (final figure in figures)
        _Figure(
          icon: switch (figure.type) {
            AudienceMetricType.onlineViewers => Icons.people_alt_rounded,
            AudienceMetricType.totalViewers => Icons.visibility_rounded,
            _ => Icons.whatshot_rounded,
          },
          text:
              '${audienceLabel(figure.type)} '
              '${figure.value.isEmpty ? i18n('audience_waiting') : readableAudience(figure.value)}',
          style: style,
        ),
      if (startedAt != null && room.isLiveNow)
        _Figure(icon: Icons.schedule_rounded, text: startedAgo(startedAt, controller.now()), style: style),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 2, children: chips);
  }
}

class _Figure extends StatelessWidget {
  const new({required this.icon, required this.text, required this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: style?.color),
      const SizedBox(width: 3),
      Text(text, style: style),
    ],
  );
}

/// Quality and line pickers (3.x `ResolutionSelector`, `LineSelector`).
class StreamPickers extends StatelessWidget {
  /// Creates the pickers.
  const new({required this.controller, this.onDark = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// White text over the video.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (controller.stage != RoomStage.playing || controller.qualities.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = onDark ? Colors.white : theme.colorScheme.primary;
    final qualities = controller.qualities;
    final current = qualities[controller.qualityIndex.clamp(0, qualities.length - 1)];
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
              enabled: !controller.switching && qualities.length > 1,
              tooltip: i18n('select_quality'),
              position: PopupMenuPosition.under,
              onSelected: (index) => unawaited(controller.selectQuality(index)),
              itemBuilder: (context) => [
                for (final (index, quality) in qualities.indexed)
                  CheckedPopupMenuItem(
                    value: index,
                    checked: index == controller.qualityIndex,
                    child: Text(quality.quality),
                  ),
              ],
              child: _PickerLabel(
                text: current.isPlaybackUnconfirmed ? '${current.quality}?' : current.quality,
                color: color,
                busy: controller.switching,
              ),
            ),
            if (playback.lineCount > 1)
              PopupMenuButton<int>(
                key: const ValueKey('live-play-line'),
                tooltip: i18n('select_play_line'),
                position: PopupMenuPosition.under,
                onSelected: (index) => unawaited(controller.selectLine(index)),
                itemBuilder: (context) => [
                  for (var index = 0; index < playback.lineCount; index++)
                    CheckedPopupMenuItem(
                      value: index,
                      checked: index == playback.lineIndex,
                      child: Text(i18n('toolbox_line', args: {'index': '${index + 1}'})),
                    ),
                ],
                child: _PickerLabel(
                  text: i18n('toolbox_line', args: {'index': '${playback.lineIndex + 1}'}),
                  color: color,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PickerLabel extends StatelessWidget {
  const new({required this.text, required this.color, this.busy = false});

  final String text;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension, minWidth: kMinInteractiveDimension),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: color)),
            const SizedBox(width: 5),
          ],
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
        ],
      ),
    ),
  );
}

/// The strip under the video: title, restriction mark, audience, time on
/// air, the room-info button and the stream pickers.
class RoomInfoBar extends StatelessWidget {
  /// Creates the strip.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = controller.room;
    final title = room.title.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const ValueKey('live-play-info'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => showRoomInfo(context, controller),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (room.isRestricted && room.isLiveNow) ...[
                        _Tag(text: restrictionLabel(room.effectiveRestriction), color: theme.colorScheme.error),
                        const SizedBox(width: 6),
                      ],
                      if (room.isRecord) ...[
                        _Tag(text: i18n('replay'), color: theme.colorScheme.tertiary),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          title.isEmpty ? i18n('untitled_room') : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    child: AudienceRow(controller: controller),
                  ),
                ],
              ),
            ),
          ),
          StreamPickers(controller: controller),
        ],
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
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    ),
  );
}

/// The room's details in a sheet: title, start time, restriction,
/// announcement, introduction and link (3.x showed only the name and area;
/// the announcement and start time came with M2.1/M4.U).
Future<void> showRoomInfo(BuildContext context, LiveRoomController controller) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => RoomInfoSheet(room: controller.room),
  ),
);

/// The details of [room].
class RoomInfoSheet extends StatelessWidget {
  /// Creates the sheet.
  const new({required this.room, super.key});

  /// The room.
  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startedAt = room.startedAt;
    final notice = room.notice?.trim() ?? '';
    final introduction = room.introduction?.trim() ?? '';
    final link = room.link?.trim() ?? '';
    Widget section(String title, String body, {bool copyable = false}) => ListTile(
      dense: true,
      title: Text(title, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
      subtitle: SelectableText(body, style: theme.textTheme.bodyMedium),
      trailing: copyable
          ? IconButton(
              tooltip: i18n('copy'),
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: body));
                AppNavigator.toast(i18n('copied_to_clipboard'));
              },
            )
          : null,
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            ListTile(
              leading: CommonAvatar(avatarUrl: room.avatar, radius: 20, fallbackName: room.nick),
              title: Text(room.displayNick(platformName(room.platform))),
              subtitle: Text(
                [platformName(room.platform), if (room.area?.trim() case final a? when a.isNotEmpty) a].join(' / '),
              ),
            ),
            section(i18n('live_play_info_title'), room.title.trim().isEmpty ? i18n('untitled_room') : room.title),
            section(i18n('live_play_info_state'), switch (room.effectiveLiveStatus) {
              LiveStatus.live => i18n('live_play_state_live'),
              LiveStatus.replay => i18n('replay'),
              _ => offlineText(room),
            }),
            if (startedAt != null)
              section(
                i18n('live_play_info_started'),
                room.isLiveNow
                    ? '${formatStartTime(startedAt)}（${startedAgo(startedAt, DateTime.now())}）'
                    : formatStartTime(startedAt),
              ),
            if (room.isRestricted)
              section(restrictionLabel(room.effectiveRestriction), restrictionReason(room.effectiveRestriction)),
            if (notice.isNotEmpty) section(i18n('live_play_info_notice'), notice),
            if (introduction.isNotEmpty && introduction != notice)
              section(i18n('live_play_info_introduction'), introduction),
            section(i18n('live_play_info_room_id'), room.roomId, copyable: true),
            if (link.isNotEmpty) section(i18n('live_play_info_link'), link, copyable: true),
          ],
        ),
      ),
    );
  }
}
