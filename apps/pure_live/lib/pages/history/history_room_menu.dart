import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/history/history_cards.dart';
import 'package:pure_live/pages/history/history_sections.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The menu of a history card (3.x `RoomCard.onLongPress`, also on right
/// click): the room's title, id and watch time, follow or unfollow, copy
/// the link, open, and remove from the history ([onRemove], which asks
/// first).
///
/// 3.x's share (share command) and room tags are left out until the card
/// menu shared by every card page exists (docs/modules/M13.6-history.md).
Future<void> showHistoryRoomMenu(
  BuildContext context, {
  required LiveRoom room,
  required FollowStore follows,
  required DateTime now,
  required VoidCallback onOpen,
  required VoidCallback onRemove,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    final theme = Theme.of(dialogContext);
    final styles = dialogContext.textStyles;
    final link = room.link?.trim() ?? '';
    void close() => Navigator.pop(dialogContext);
    return AlertDialog(
      scrollable: true,
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: PlatformLogo(room.platform),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              room.displayNick(historyPlatformName(room.platform)),
              style: styles.t16.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (link.isNotEmpty)
            IconButton(
              tooltip: i18n('copy_link'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.link_rounded, size: 20, color: theme.colorScheme.primary),
              onPressed: () async {
                close();
                await Clipboard.setData(ClipboardData(text: link));
                AppNavigator.toast(i18n('copied_to_clipboard'));
              },
            ),
          IconButton(
            key: const ValueKey('history-menu-remove'),
            tooltip: i18n('remove_history_entry_named', args: {'title': historyRoomLabel(room)}),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: theme.colorScheme.error),
            onPressed: () {
              close();
              onRemove();
            },
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                historyRoomLabel(room),
                style: styles.t14.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                [
                  historyPlatformName(room.platform),
                  i18n('room_id_label', args: {'id': room.roomId}),
                  historyWatchedLabel(room.lastWatchedAt, now),
                ].join(' · '),
                style: styles.t11.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        _FollowButton(room: room, follows: follows),
        FilledButton(
          onPressed: () {
            close();
            onOpen();
          },
          child: Text(i18n('history_open_room')),
        ),
        TextButton(onPressed: close, child: Text(i18n('close'))),
      ],
    );
  },
);

/// Follow or unfollow (3.x `FollowButton`); unfollowing asks first. The
/// menu closes once the change is stored.
class _FollowButton extends StatefulWidget {
  const new({required this.room, required this.follows});

  final LiveRoom room;
  final FollowStore follows;

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  late final Stream<bool> _followed = widget.follows.watchContains(widget.room);
  bool _busy = false;

  Future<void> _toggle({required bool followed}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (followed) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: Text(i18n('unfollow')),
            content: Text(
              i18n(
                'unfollow_message',
                args: {'name': widget.room.displayNick(historyPlatformName(widget.room.platform))},
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
              TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('confirm'))),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await widget.follows.remove(widget.room);
        if (mounted) Navigator.pop(context);
        AppNavigator.toast(i18n('history_unfollowed'));
      } else {
        if (!await widget.follows.add(widget.room)) {
          AppNavigator.toast(i18n('get_room_info_failed_retry'));
          return;
        }
        if (mounted) Navigator.pop(context);
        AppNavigator.toast(i18n('history_followed'));
      }
    } on Object catch (error, stack) {
      log('Changing the follow failed', name: 'HistoryPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('favorite_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _followed,
    builder: (context, snapshot) {
      final followed = snapshot.data;
      return FilledButton.tonal(
        key: const ValueKey('history-menu-follow'),
        onPressed: _busy || followed == null ? null : () => unawaited(_toggle(followed: followed)),
        child: Text(followed ?? false ? i18n('unfollow') : i18n('follow')),
      );
    },
  );
}
