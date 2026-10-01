import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/popular/popular_rooms.dart';
import 'package:pure_live/pages/popular/share_command.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// A room card's menu (3.x `RoomCard.onLongPress`): the streamer, share,
/// tags, the title and room id, follow or unfollow.
Future<void> showRoomMenu(BuildContext context, {required LiveStore store, required LiveRoom room}) {
  final theme = Theme.of(context);
  final styles = context.textStyles;
  final name = room.displayNick(platformDisplayName(room.platform));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('room-menu'),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          PlatformLogo(room.platform),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: styles.t16.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: i18n('share'),
            icon: Icon(Icons.share_rounded, size: 20, color: theme.colorScheme.primary),
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(shareRoom(room));
            },
          ),
          IconButton(
            tooltip: i18n('set_room_tags'),
            icon: Icon(Icons.sell_outlined, size: 20, color: theme.colorScheme.primary),
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(_editTags(context, store, room));
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
                room.title.isEmpty ? name : room.title,
                style: styles.t14.copyWith(color: theme.colorScheme.onSurface, height: 1.45),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                SelectableText(
                  i18n('room_id_label', args: {'id': room.roomId}),
                  style: styles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (room.area case final area? when area.trim().isNotEmpty)
                  Text(area, style: styles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                if (restrictionLabel(room) case final label?)
                  Text(label, style: styles.t12.copyWith(color: theme.colorScheme.error)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        _FollowButton(store: store, room: room),
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(i18n('close'))),
      ],
    ),
  );
}

/// Copies [room]'s share code (3.x `onShareRoomPressed`; the phone's share
/// sheet needs the share plugin, see the M13.1 record).
Future<bool> shareRoom(LiveRoom room) async {
  final code = encodeRoomShareCode(room);
  if (code.isEmpty) {
    AppNavigator.toast(i18n('share_failed'));
    return false;
  }
  try {
    await Clipboard.setData(ClipboardData(text: code));
    AppNavigator.toast(i18n('copied_to_clipboard'));
    return true;
  } on Object catch (error) {
    log('Room share failed', name: 'PopularPage', error: error);
    AppNavigator.toast(i18n('share_failed'));
    return false;
  }
}

Future<void> _editTags(BuildContext context, LiveStore store, LiveRoom room) async {
  if (!await store.follows.contains(room)) {
    // 3.x: tags belong to follows; ask to follow first.
    AppNavigator.toast(i18n('tags_need_follow_tip'));
    if (!context.mounted) return;
    final follow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('follow')),
        content: Text(i18n('dialog_follow_anchor_ask', args: {'name': room.nick})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('follow'))),
        ],
      ),
    );
    if (follow != true) return;
    try {
      await store.follows.add(room);
    } on Object catch (error) {
      log('Follow failed', name: 'PopularPage', error: error);
      AppNavigator.toast(i18n('favorite_changes_save_failed'));
      return;
    }
  }
  if (!context.mounted) return;
  final tags = await store.tags.all();
  final selected = await store.tags.tagsOf(room);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => RoomTagsDialog(store: store, room: room, tags: tags, selected: selected),
  );
}

/// Picks the tags of a followed room and creates new ones (3.x's tag grid
/// in `RoomCard`, reduced to the choice and a new name).
class RoomTagsDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.store, required this.room, required this.tags, required this.selected, super.key});

  /// Storage.
  final LiveStore store;

  /// The room.
  final LiveRoom room;

  /// Every tag.
  final List<StoreTag> tags;

  /// The room's tag ids.
  final List<String> selected;

  @override
  State<RoomTagsDialog> createState() => _RoomTagsDialogState();
}

class _RoomTagsDialogState extends State<RoomTagsDialog> {
  late final List<StoreTag> _tags = [...widget.tags];
  late final List<String> _selected = [...widget.selected];
  final TextEditingController _name = TextEditingController();
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    final check = await widget.store.tags.validateName(name);
    if (!mounted) return;
    if (check != TagNameValidation.valid) {
      setState(() {
        _nameError = check == TagNameValidation.empty ? i18n('tag_name_empty_error') : i18n('tag_name_duplicate_error');
      });
      return;
    }
    final tag = await widget.store.tags.add(name);
    if (!mounted || tag == null) return;
    setState(() {
      _tags.add(tag);
      _selected.add(tag.id);
      _nameError = null;
      _name.clear();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.store.tags.setTagsOf(widget.room, _selected);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      log('Tags not saved', name: 'PopularPage', error: error);
      AppNavigator.toast(i18n('tag_assignment_save_failed'));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('room-tags'),
    title: Text(i18n('set_room_tags')),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tags.isEmpty)
            Text(i18n('popular_no_tags'), style: context.textStyles.t13Muted)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tags)
                  FilterChip(
                    label: Text(tag.name),
                    selected: _selected.contains(tag.id),
                    onSelected: (on) => setState(() => on ? _selected.add(tag.id) : _selected.remove(tag.id)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 20,
            decoration: InputDecoration(
              hintText: i18n('tag_input_hint'),
              errorText: _nameError,
              suffixIcon: IconButton(tooltip: i18n('add_tag'), icon: const Icon(Icons.add_rounded), onPressed: _add),
            ),
            onSubmitted: (_) => unawaited(_add()),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(i18n('confirm')),
      ),
    ],
  );
}

class _FollowButton extends StatefulWidget {
  const new({required this.store, required this.room});

  final LiveStore store;
  final LiveRoom room;

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  late final Stream<bool> _followed = widget.store.follows.watchContains(widget.room);
  bool _busy = false;

  Future<void> _toggle(bool followed) async {
    if (_busy) return;
    final name = widget.room.displayNick(platformDisplayName(widget.room.platform));
    if (followed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(i18n('unfollow')),
          content: Text(i18n('unfollow_message', args: {'name': name})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(i18n('confirm'))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (followed) {
        await widget.store.follows.remove(widget.room);
      } else {
        await widget.store.follows.add(widget.room);
      }
      AppNavigator.toast(i18n(followed ? 'popular_unfollowed' : 'popular_followed', args: {'name': name}));
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      log('Follow change failed', name: 'PopularPage', error: error);
      AppNavigator.toast(i18n('favorite_changes_save_failed'));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _followed,
    builder: (context, snapshot) {
      final followed = snapshot.data;
      return FilledButton.tonal(
        key: const ValueKey('room-menu-follow'),
        onPressed: followed == null || _busy ? null : () => _toggle(followed),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: Text(followed ?? false ? i18n('unfollow') : i18n('follow')),
      );
    },
  );
}
