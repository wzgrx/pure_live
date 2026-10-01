import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/search/search_cards.dart';

/// The menu of a result card (long press or right click): the room's
/// details with its introduction (Picarto's channel bio, UPGRADES 11-5),
/// open, follow or unfollow, copy the link.
///
/// 3.x's card menu also had sharing and follow tags; those belong to the
/// shared card menu (M13) and are not repeated here.
Future<void> showSearchRoomSheet(
  BuildContext context, {
  required LiveRoom room,
  required String platformName,
  required FollowStore follows,
  required void Function(LiveRoom room) onOpen,
  required void Function(String message) toast,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      _RoomSheet(room: room, platformName: platformName, follows: follows, onOpen: onOpen, toast: toast),
);

class _RoomSheet extends StatelessWidget {
  const new({
    required this.room,
    required this.platformName,
    required this.follows,
    required this.onOpen,
    required this.toast,
  });

  final LiveRoom room;
  final String platformName;
  final FollowStore follows;
  final void Function(LiveRoom room) onOpen;
  final void Function(String message) toast;

  Future<void> _toggleFollow(BuildContext context, {required bool followed}) async {
    try {
      if (followed) {
        await follows.remove(room);
      } else {
        await follows.add(room);
      }
      toast(i18n(followed ? 'search_unfollowed' : 'search_followed'));
    } on Object {
      toast(i18n('favorite_changes_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final intro = room.introduction?.trim() ?? '';
    final restriction = room.isRestricted ? restrictionLabel(room.effectiveRestriction) : null;
    final link = room.link?.trim() ?? '';
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('search-room-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PlatformLogo(room.platform),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    room.displayNick(platformName),
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (restriction != null) Chip(visualDensity: VisualDensity.compact, label: Text(restriction)),
              ],
            ),
            if (room.title.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(room.title.trim(), style: theme.textTheme.bodyMedium),
            ],
            if (intro.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(intro, style: muted, maxLines: 6, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Text('$platformName · ${i18n('room_id_label', args: {'id': room.roomId})}', style: muted),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('search-room-open'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpen(room);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(i18n('search_room_enter')),
                ),
                StreamBuilder<bool>(
                  stream: follows.watchContains(room),
                  builder: (context, snapshot) {
                    final followed = snapshot.data ?? false;
                    return OutlinedButton.icon(
                      key: const ValueKey('search-room-follow'),
                      onPressed: snapshot.hasData ? () => unawaited(_toggleFollow(context, followed: followed)) : null,
                      icon: Icon(followed ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                      label: Text(i18n(followed ? 'unfollow' : 'follow')),
                    );
                  },
                ),
                if (link.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      toast(i18n('copied_to_clipboard'));
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: Text(i18n('copy_link')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
