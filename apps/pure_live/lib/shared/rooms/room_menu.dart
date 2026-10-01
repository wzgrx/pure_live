import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/tags/tag_editor_dialog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

/// A page's own entry in the room menu (the history page's "remove").
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

  /// Runs after the menu has closed.
  final VoidCallback onSelected;

  /// Drawn in the error colour (removing something).
  final bool danger;
}

enum _Choice { open, follow, unfollow, tags, share, copyLink }

/// The menu of a room card, the same on every card page (3.x
/// `RoomCard.onLongPress`, also on right click): the streamer, the title,
/// the introduction (UPGRADES 11-5), platform, room id, area, [detail] (the
/// history page's watch time) and the room's mark; then open, set tags,
/// share, copy the link, the page's own [actions], and follow or unfollow.
///
/// Open uses [onOpen], else opens the room. Unfollowing asks first and can
/// be undone from the snack bar; setting tags of a room not followed offers
/// to follow it first (tags belong to follows, 3.x).
Future<void> showRoomMenu(
  BuildContext context, {
  required LiveStore store,
  required LiveRoom room,
  VoidCallback? onOpen,
  String? detail,
  List<RoomMenuAction> actions = const [],
}) async {
  final picked = await showDialog<Object>(
    context: context,
    builder: (dialogContext) => _RoomMenu(follows: store.follows, room: room, detail: detail, actions: actions),
  );
  if (!context.mounted) return;
  switch (picked) {
    case _Choice.open:
      if (onOpen != null) {
        onOpen();
      } else {
        unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room));
      }
    case _Choice.follow:
      await followRoom(store, room);
    case _Choice.unfollow:
      await unfollowRoom(context, store: store, room: room);
    case _Choice.tags:
      await editRoomTags(context, store: store, room: room);
    case _Choice.share:
      await shareRoom(room);
    case _Choice.copyLink:
      await Clipboard.setData(ClipboardData(text: room.link?.trim() ?? ''));
      AppNavigator.toast(i18n('copied_to_clipboard'));
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final styles = context.textStyles;
    final name = room.displayNick(platformName(room.platform));
    final title = room.title.trim();
    final intro = room.introduction?.trim() ?? '';
    final link = room.link?.trim() ?? '';
    final mark = roomMark(room);
    final muted = styles.t12.copyWith(color: colors.onSurfaceVariant);
    void pick(Object choice) => Navigator.pop(context, choice);
    Widget entry(Key key, IconData icon, String label, Object choice, {bool danger = false}) => ListTile(
      key: key,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, size: 20, color: danger ? colors.error : colors.primary),
      title: Text(label, style: danger ? TextStyle(color: colors.error) : null),
      onTap: () => pick(choice),
    );
    return AlertDialog(
      key: const ValueKey('room-menu'),
      scrollable: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: PlatformLogo(room.platform),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: styles.t16.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? name : title,
                      style: styles.t14.copyWith(color: colors.onSurface, fontWeight: FontWeight.w500, height: 1.45),
                    ),
                    if (intro.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        intro,
                        key: const ValueKey('room-menu-intro'),
                        style: muted,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(platformName(room.platform), style: muted),
                  SelectableText(i18n('room_id_label', args: {'id': room.roomId}), style: muted),
                  if (room.area case final area? when area.trim().isNotEmpty) Text(area.trim(), style: muted),
                  if (detail case final text? when text.isNotEmpty) Text(text, style: muted),
                  if (mark != null)
                    Text(
                      mark,
                      key: const ValueKey('room-menu-mark'),
                      style: muted.copyWith(color: colors.error),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            entry(const ValueKey('room-menu-open'), Icons.play_circle_outline_rounded, i18n('room_open'), _Choice.open),
            entry(const ValueKey('room-menu-tags'), Remix.price_tag_3_line, i18n('set_room_tags'), _Choice.tags),
            entry(const ValueKey('room-menu-share'), Remix.share_forward_line, i18n('share'), _Choice.share),
            if (link.isNotEmpty)
              entry(const ValueKey('room-menu-copy'), Icons.link_rounded, i18n('copy_link'), _Choice.copyLink),
            for (final action in actions) entry(action.key, action.icon, action.label, action, danger: action.danger),
          ],
        ),
      ),
      actions: [
        StreamBuilder<bool>(
          stream: follows.watchContains(room),
          builder: (context, snapshot) {
            final followed = snapshot.data;
            return FilledButton.tonal(
              key: const ValueKey('room-menu-follow'),
              onPressed: followed == null ? null : () => pick(followed ? _Choice.unfollow : _Choice.follow),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: Text(followed ?? false ? i18n('unfollow') : i18n('follow')),
            );
          },
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('close'))),
      ],
    );
  }
}

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

/// Unfollows [room] after asking (3.x `FollowButton`); the snack bar can put
/// it back in its place. Completes with whether it was unfollowed.
Future<bool> unfollowRoom(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  final name = room.displayNick(platformName(room.platform));
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(i18n('unfollow')),
      content: Text(i18n('unfollow_message', args: {'name': name})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
        FilledButton(
          key: const ValueKey('unfollow-confirm'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(i18n('confirm')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final before = await store.follows.all();
    final index = before.indexWhere(room.hasSameIdentity);
    final stored = index < 0 ? room : before[index];
    if (!await store.follows.remove(room)) return false;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(i18n('room_unfollowed', args: {'name': name})),
          action: SnackBarAction(label: i18n('room_undo'), onPressed: () => unawaited(_restore(store, stored, index))),
        ),
      );
    if (messenger == null) AppNavigator.toast(i18n('room_unfollowed', args: {'name': name}));
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

/// Chooses the tags of [room] (3.x `_showTagSelectionGridModal`); new tags
/// are made with the tag page's editor. A room not followed is offered to
/// be followed first (tags belong to follows).
Future<void> editRoomTags(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  if (!await store.follows.contains(room)) {
    if (!context.mounted) return;
    final name = room.displayNick(platformName(room.platform));
    final follow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(i18n('tags_need_follow_tip')),
        content: Text(i18n('dialog_follow_anchor_ask', args: {'name': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('room-tags-follow'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(i18n('follow')),
          ),
        ],
      ),
    );
    if (follow != true || !await followRoom(store, room)) return;
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
  await showDialog<void>(
    context: context,
    builder: (_) => RoomTagPicker(store: store, room: room, tags: tags, selected: selected),
  );
}

/// Picks the tags of a followed room; "new tag" opens the tag editor and
/// selects what it made.
class RoomTagPicker extends StatefulWidget {
  /// Creates the picker.
  const new({required this.store, required this.room, required this.tags, required this.selected, super.key});

  /// Storage.
  final LiveStore store;

  /// The room.
  final LiveRoom room;

  /// Every tag, in the user's order.
  final List<StoreTag> tags;

  /// The room's tag ids.
  final Set<String> selected;

  @override
  State<RoomTagPicker> createState() => _RoomTagPickerState();
}

class _RoomTagPickerState extends State<RoomTagPicker> {
  late final List<StoreTag> _tags = List.of(widget.tags);
  late final Set<String> _selected = Set.of(widget.selected);
  bool _busy = false;

  Future<void> _create() async {
    final tag = await showTagEditor(context, tags: widget.store.tags);
    if (tag == null || !mounted) return;
    setState(() {
      _tags.add(tag);
      _selected.add(tag.id);
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.store.tags.setTagsOf(widget.room, [
        for (final tag in _tags)
          if (_selected.contains(tag.id)) tag.id,
      ]);
      if (mounted) Navigator.pop(context);
    } on Object catch (error, stack) {
      log('Saving room tags failed', name: 'RoomMenu', error: error, stackTrace: stack);
      if (mounted) setState(() => _busy = false);
      AppNavigator.toast(i18n('tag_assignment_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('room-tags'),
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Expanded(child: Text(i18n('set_room_tags'))),
          IconButton(
            tooltip: i18n('tag_management'),
            icon: const Icon(Remix.settings_3_line),
            onPressed: () {
              Navigator.pop(context);
              unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsTags));
            },
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  i18n('room_tags_empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _tags)
                    FilterChip(
                      key: ValueKey('tag-choice-${tag.id}'),
                      label: Text(tag.name),
                      tooltip: tag.description.trim().isEmpty ? null : tag.description,
                      selected: _selected.contains(tag.id),
                      onSelected: _busy
                          ? null
                          : (on) => setState(() => on ? _selected.add(tag.id) : _selected.remove(tag.id)),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('room-tags-new'),
                onPressed: _busy ? null : () => unawaited(_create()),
                icon: const Icon(Remix.add_line),
                label: Text(i18n('room_tags_new')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(i18n('cancel'))),
        FilledButton(
          key: const ValueKey('room-tags-save'),
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(i18n('confirm')),
        ),
      ],
    );
  }
}
