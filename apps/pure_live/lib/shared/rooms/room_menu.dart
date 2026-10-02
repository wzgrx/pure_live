import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_tags_dialog.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

/// A page's own entry in the room dialog (the history page's "remove").
@immutable
final class RoomMenuAction {
  /// Creates the entry.
  const new({
    required this.key,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.danger = false,
  });

  /// The entry's widget key (tests find it by this).
  final Key key;

  /// Its icon.
  final IconData icon;

  /// Its words.
  final String label;

  /// Runs after the dialog has closed.
  final VoidCallback onSelected;

  /// Drawn in the error colour (removing something).
  final bool danger;
}

enum _Choice { follow, unfollow, tags, share }

/// The dialog of a room card, the same on every card page and client
/// (3.x `RoomCard.onLongPress`, also on right click; docs/ui/compare/U.4a,
/// choice A1: a dialog in the middle of the screen, like 3.x).
///
/// The platform's logo, the streamer and "platform · room id" ([detail]
/// under them: the history page's watch time), the whole title, "分享" and
/// "设置标签" with their words (c10), the page's own [actions], then "关闭"
/// and the follow pill of the live room's app bar (c11): following closes
/// the dialog and says so; unfollowing asks first (on top of the dialog)
/// and can be undone from the toast. Setting the tags of a room not
/// followed offers to follow it first (tags belong to follows).
///
/// [onOpen] is kept for callers that open rooms their own way; the dialog
/// has no "open" entry (3.x had none: a tap on the card opens the room).
Future<void> showRoomMenu(
  BuildContext context, {
  required LiveStore store,
  required LiveRoom room,
  VoidCallback? onOpen,
  String? detail,
  List<RoomMenuAction> actions = const [],
}) async {
  final picked = await showAppDialog<Object>(
    context: context,
    builder: (dialogContext) => _RoomMenu(follows: store.follows, room: room, detail: detail, actions: actions),
  );
  if (!context.mounted) return;
  switch (picked) {
    case _Choice.follow:
      await followRoom(store, room);
    case _Choice.unfollow:
      await unfollowRoom(context, store: store, room: room, confirmed: true);
    case _Choice.tags:
      await editRoomTags(context, store: store, room: room);
    case _Choice.share:
      await shareRoom(room);
    case final RoomMenuAction action:
      action.onSelected();
  }
}

class _RoomMenu extends StatelessWidget {
  const new({required this.follows, required this.room, required this.detail, required this.actions});

  final FollowStore follows;
  final LiveRoom room;
  final String? detail;
  final List<RoomMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final name = room.displayNick(platformName(room.platform));
    final title = room.title.trim();
    void pick(Object choice) => Navigator.pop(context, choice);

    Future<void> askUnfollow() async {
      if (await confirmUnfollowRoom(context, name: name) && context.mounted) pick(_Choice.unfollow);
    }

    return CardDialog(
      key: const ValueKey('room-menu'),
      leading: PlatformLogo(room.platform),
      title: name,
      subtitle: i18n('room_menu_subtitle', args: {'platform': platformName(room.platform), 'id': room.roomId}),
      detail: detail,
      body: title.isEmpty ? i18n('untitled_room') : title,
      closeLabel: i18n('close'),
      actions: [
        [
          CardDialogAction(
            key: const ValueKey('room-menu-share'),
            icon: AppIcons.share,
            label: i18n('share'),
            onPressed: () => pick(_Choice.share),
          ),
          CardDialogAction(
            key: const ValueKey('room-menu-tags'),
            icon: AppIcons.tag,
            label: i18n('room_menu_set_tags'),
            onPressed: () => pick(_Choice.tags),
          ),
        ],
        for (final action in actions)
          [
            CardDialogAction(
              key: action.key,
              icon: action.icon,
              label: action.label,
              danger: action.danger,
              onPressed: () => pick(action),
            ),
          ],
      ],
      trailing: StreamBuilder<bool>(
        stream: follows.watchContains(room),
        builder: (context, snapshot) {
          final followed = snapshot.data ?? false;
          return FollowPill(
            key: const ValueKey('room-menu-follow'),
            followed: followed,
            followLabel: i18n('follow'),
            followedLabel: i18n('followed'),
            onPressed: snapshot.hasData ? () => followed ? unawaited(askUnfollow()) : pick(_Choice.follow) : null,
          );
        },
      ),
    );
  }
}

/// Asks whether to unfollow [name] (U.4a c12: one kind of confirmation for
/// follow and unfollow, the main button saying what it does, in red).
Future<bool> confirmUnfollowRoom(BuildContext context, {required String name}) => showAppConfirmDialog(
  context: context,
  key: const ValueKey('unfollow-dialog'),
  title: i18n('unfollow'),
  message: i18n('unfollow_message', args: {'name': name}),
  confirmLabel: i18n('unfollow'),
  danger: true,
  confirmKey: const ValueKey('unfollow-confirm'),
);

/// Follows [room] and says so; false when it could not be stored.
Future<bool> followRoom(LiveStore store, LiveRoom room) async {
  final name = room.displayNick(platformName(room.platform));
  try {
    if (!await store.follows.add(room) && !await store.follows.contains(room)) {
      AppNavigator.toast(i18n('get_room_info_failed_retry'));
      return false;
    }
    AppNavigator.toast(i18n('room_followed', args: {'name': name}));
    return true;
  } on Object catch (error, stack) {
    log('Follow failed', name: 'RoomMenu', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
    return false;
  }
}

/// Unfollows [room] after asking (3.x `FollowButton`; [confirmed] when the
/// caller asked already); the toast's "撤销" can put it back in its place.
/// Completes with whether it was unfollowed.
Future<bool> unfollowRoom(
  BuildContext context, {
  required LiveStore store,
  required LiveRoom room,
  bool confirmed = false,
}) async {
  final name = room.displayNick(platformName(room.platform));
  if (!confirmed && !await confirmUnfollowRoom(context, name: name)) return false;
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final before = await store.follows.all();
    final index = before.indexWhere(room.hasSameIdentity);
    final stored = index < 0 ? room : before[index];
    if (!await store.follows.remove(room)) return false;
    final toast = AppToast(
      i18n('room_unfollowed', args: {'name': name}),
      actionLabel: i18n('room_undo'),
      onAction: () => unawaited(_restore(store, stored, index)),
    );
    if (messenger != null) {
      showAppToastOn(messenger, toast);
    } else {
      AppNavigator.showToast(toast);
    }
    return true;
  } on Object catch (error, stack) {
    log('Unfollow failed', name: 'RoomMenu', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
    return false;
  }
}

Future<void> _restore(LiveStore store, LiveRoom room, int index) async {
  try {
    await store.follows.mutate((rooms) {
      if (rooms.any(room.hasSameIdentity)) return rooms;
      return rooms..insert(index < 0 ? rooms.length : index.clamp(0, rooms.length), room);
    });
  } on Object catch (error, stack) {
    log('Undo unfollow failed', name: 'RoomMenu', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
  }
}

/// Shares [room]'s share code (3.x `ShareCommandHandler.onShareRoomPressed`):
/// the system share sheet on phones once the app has one
/// ([SystemShare.sheet]), else the code is copied.
Future<bool> shareRoom(LiveRoom room) async {
  final code = encodeRoomShareCode(room);
  if (code.isEmpty) {
    AppNavigator.toast(i18n('share_failed'));
    return false;
  }
  // The clipboard check does not offer the user's own code back (3.x
  // `ShareCommandHandler._rememberText`).
  OwnClipboardTexts.remember(code);
  try {
    final sheet = SystemShare.sheet;
    if (sheet != null && (Platform.isAndroid || Platform.isIOS)) return await sheet(code);
    await Clipboard.setData(ClipboardData(text: code));
    AppNavigator.toast(i18n('copied_to_clipboard'));
    return true;
  } on Object catch (error, stack) {
    log('Room share failed', name: 'RoomMenu', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('share_failed'));
    return false;
  }
}

/// Chooses the tags of [room] (3.x `_showTagSelectionGridModal`,
/// U.4a c13). A room not followed is offered to be followed first in one
/// dialog whose button says so ("关注并设置标签", c10, c12).
Future<void> editRoomTags(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  if (!await store.follows.contains(room)) {
    if (!context.mounted) return;
    final name = room.displayNick(platformName(room.platform));
    final follow = await showAppConfirmDialog(
      context: context,
      key: const ValueKey('room-tags-ask'),
      title: i18n('room_tags_follow_title'),
      message: i18n('room_tags_follow_message', args: {'name': name}),
      confirmLabel: i18n('room_tags_follow_confirm'),
      confirmKey: const ValueKey('room-tags-follow'),
    );
    if (!follow || !await followRoom(store, room)) return;
  }
  final List<StoreTag> tags;
  final Set<String> selected;
  try {
    tags = await store.tags.all();
    selected = (await store.tags.tagsOf(room)).toSet();
  } on Object catch (error, stack) {
    log('Reading tags failed', name: 'RoomMenu', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('tag_changes_save_failed'));
    return;
  }
  if (!context.mounted) return;
  await showAppDialog<void>(
    context: context,
    builder: (_) => RoomTagPicker(store: store, room: room, tags: tags, selected: selected),
  );
}
