import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/follow_button.dart';
import 'package:pure_live/features/live_play/buttons/record_button.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/record/record_state.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The least width kept for the avatar and the names: the buttons turn into
/// their round forms before the names go below it.
const double roomHeaderTitleMinWidth = 100;

/// The live room's app bar row (3.x `LivePlayHeader`): avatar, streamer and
/// "平台 · 分区" (a tap opens the room details, E1), then follow, record and
/// the menu (docs/A-界面设计/A07-直播间界面/A07.1-竖屏普通布局, changes 1, 12, 13 and choice B).
class RoomHeader extends ConsumerStatefulWidget {
  /// Creates the row.
  const new({required this.controller, required this.onDetails, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Opens or closes the room details.
  final VoidCallback onDetails;

  @override
  ConsumerState<RoomHeader> createState() => _RoomHeaderState();
}

class _RoomHeaderState extends ConsumerState<RoomHeader> {
  StreamSubscription<List<RecordTask>>? _tasks;

  @override
  void initState() {
    super.initState();
    // The record button's width depends on its task ("自动录" is wider).
    _tasks = ref.read(recordingProvider)?.recorder?.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_tasks?.cancel());
    super.dispose();
  }

  double _pillWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge?.emphasis),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    // Padding 14 + mark 18 + gap 8 + text + padding 14, and 4 on each side.
    return width + 62;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final iptv = controller.site.id == SiteIds.iptv;
    final recording = ref.watch(recordingProvider);
    final task = iptv || recording == null || !recording.available ? null : recording.taskFor(controller.room);
    final recordable = !iptv && (recording?.available ?? false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final follow = _pillWidth(context, i18n('followed'));
        final record = !recordable
            ? 0.0
            : autoRecordOn(task) && !task!.status.isActive
            ? _pillWidth(context, i18n('live_play_auto_record'))
            : kMinInteractiveDimension;
        final compact = constraints.maxWidth - follow - record - kMinInteractiveDimension - 4 < roomHeaderTitleMinWidth;
        return Row(
          children: [
            Expanded(
              child: RoomTitle(controller: controller, onTap: widget.onDetails),
            ),
            // Rebuilt when the room changes identity, not for every chat
            // message; a tap reads the room as it is then.
            ListenableSelector<String>(
              listenable: controller,
              selector: () => controller.room.identityKey,
              builder: (context, _, _) =>
                  FollowButton(room: controller.room, latest: () => controller.room, compact: compact),
            ),
            if (!iptv)
              ListenableSelector<String>(
                listenable: controller,
                selector: () => controller.room.identityKey,
                builder: (context, _, _) =>
                    RecordButton(room: controller.room, latest: () => controller.room, compact: compact),
              ),
            RoomMenuButton(controller: controller),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}

/// The avatar, the streamer's name (15, semi-bold) and "平台 · 分区" (12, the
/// secondary colour) of the room bar (U.2a change 1; 3.x showed both lines
/// at the same small size). Grey placeholders stand in while the room loads
/// without a name (E2).
class RoomTitle extends StatelessWidget {
  /// Creates the title.
  const new({required this.controller, this.onTap, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Opens the room details.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListenableSelector<(String, String, String, String, bool)>(
    listenable: controller,
    selector: () {
      final room = controller.room;
      return (
        room.nick.trim(),
        room.avatar,
        room.platform,
        roomAreaShown(room.platform, room.area),
        controller.stage == RoomStage.loading,
      );
    },
    builder: (context, value, _) {
      final (nick, avatar, platform, area, loading) = value;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final platformLabel = platformName(platform);
      final placeholder = nick.isEmpty && loading;
      // One stop for a screen reader (A05.1): the names and what a tap
      // opens; the avatar inside (32, the keyboard's stop) does the same.
      return Semantics(
        container: true,
        tooltip: onTap == null ? null : i18n('live_play_room_details'),
        child: InkWell(
          key: const ValueKey('live-play-title'),
          onTap: onTap,
          // The avatar is the keyboard's stop for the details (B09 c9); the
          // names around it are more room for a finger.
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(12),
          // At least 48 to tap (A05.1): the two lines and the padding make 47.
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                // B09 c9 (U.1c c9): the tappable avatar darkens under the
                // pointer and when pressed, and draws the keyboard frame.
                ExcludeSemantics(
                  child: CommonAvatar(
                    key: const ValueKey('live-play-avatar'),
                    avatarUrl: avatar,
                    radius: 16,
                    fallbackName: nick.isEmpty ? platformLabel : nick,
                    onTap: onTap,
                    tooltip: onTap == null ? null : i18n('live_play_room_details'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: placeholder
                      ? const Column(
                          key: ValueKey('live-play-title-placeholder'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBar(width: 72, height: 14),
                            SizedBox(height: 6),
                            SkeletonBar(width: 112, height: 10),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nick.isEmpty ? platformLabel : nick,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.emphasis,
                            ),
                            Text(
                              area.isEmpty ? platformLabel : '$platformLabel · ${platformAreaName(platform, area)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.regular.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A still grey bar standing in for text that is loading (no shimmer,
/// UI_PLAN §7.4 rule 8).
class SkeletonBar extends StatelessWidget {
  /// Creates the bar.
  const new({required this.width, required this.height, super.key});

  /// The width.
  final double width;

  /// The height.
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    ),
  );
}
