import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The menu of a follow card (3.x `RoomCard.onLongPress`): the streamer,
/// the title and room id, then tags, copy link and unfollow.
Future<void> showFollowMenu(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  final theme = Theme.of(context);
  final styles = context.textStyles;
  final link = room.link?.trim() ?? '';
  final action = await showDialog<_MenuAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          PlatformLogo(room.platform),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              room.nick,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.t16.copyWith(fontWeight: FontWeight.w700),
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
            if (room.title.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(room.title, style: styles.t14.copyWith(height: 1.45)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                i18n('room_id_label', args: {'id': room.roomId}),
                style: styles.t11.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              key: const ValueKey('follow-menu-tags'),
              leading: const Icon(Remix.price_tag_3_line),
              title: Text(i18n('set_room_tags')),
              onTap: () => Navigator.pop(dialogContext, _MenuAction.tags),
            ),
            if (link.isNotEmpty)
              ListTile(
                key: const ValueKey('follow-menu-copy'),
                leading: const Icon(Remix.link),
                title: Text(i18n('copy_link')),
                onTap: () => Navigator.pop(dialogContext, _MenuAction.copyLink),
              ),
            ListTile(
              key: const ValueKey('follow-menu-unfollow'),
              leading: Icon(Remix.heart_3_line, color: theme.colorScheme.error),
              title: Text(i18n('unfollow'), style: TextStyle(color: theme.colorScheme.error)),
              onTap: () => Navigator.pop(dialogContext, _MenuAction.unfollow),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(i18n('close')))],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case _MenuAction.tags:
      await showTagPicker(context, store: store, room: room);
    case _MenuAction.copyLink:
      await Clipboard.setData(ClipboardData(text: link));
      AppNavigator.toast(i18n('copied_to_clipboard'));
    case _MenuAction.unfollow:
      await unfollow(context, store: store, room: room);
    case null:
      break;
  }
}

enum _MenuAction { tags, copyLink, unfollow }

/// Unfollows [room] after asking (3.x `FollowButton`); the snack bar can
/// put it back in its place.
Future<void> unfollow(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(i18n('unfollow')),
      content: Text(i18n('unfollow_message', args: {'name': room.nick})),
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
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final before = await store.follows.all();
    final index = before.indexWhere(room.hasSameIdentity);
    final stored = index < 0 ? room : before[index];
    if (!await store.follows.remove(room)) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(i18n('favorite_unfollowed', args: {'name': room.nick})),
          action: SnackBarAction(
            label: i18n('favorite_undo'),
            onPressed: () => unawaited(_restore(store, stored, index)),
          ),
        ),
      );
  } on Object catch (error) {
    log('Unfollow failed', name: 'FavoritePage', error: error);
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
  }
}

Future<void> _restore(LiveStore store, LiveRoom room, int index) async {
  try {
    await store.follows.mutate((rooms) {
      if (rooms.any(room.hasSameIdentity)) return rooms;
      return rooms..insert(index.clamp(0, rooms.length), room);
    });
  } on Object catch (error) {
    log('Undo unfollow failed', name: 'FavoritePage', error: error);
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
  }
}

/// Chooses the tags of [room], creating new ones on the way (3.x
/// `_showTagSelectionGridModal`).
Future<void> showTagPicker(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  final List<StoreTag> tags;
  final Set<String> selected;
  try {
    tags = await store.tags.all();
    selected = (await store.tags.tagsOf(room)).toSet();
  } on Object catch (error) {
    log('Reading tags failed', name: 'FavoritePage', error: error);
    AppNavigator.toast(i18n('tag_changes_save_failed'));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _TagPicker(store: store, room: room, tags: tags, selected: selected),
  );
}

class _TagPicker extends StatefulWidget {
  const new({required this.store, required this.room, required this.tags, required this.selected});

  final LiveStore store;
  final LiveRoom room;
  final List<StoreTag> tags;
  final Set<String> selected;

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final List<StoreTag> _tags = List.of(widget.tags);
  late final Set<String> _selected = Set.of(widget.selected);
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    final validation = await widget.store.tags.validateName(name);
    if (!mounted) return;
    if (validation != TagNameValidation.valid) {
      setState(
        () => _error = validation == TagNameValidation.empty
            ? i18n('tag_name_empty_error')
            : i18n('tag_name_duplicate_error'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final tag = await widget.store.tags.add(name);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (tag == null) {
          _error = i18n('tag_invalid_or_duplicate');
          return;
        }
        _error = null;
        _tags.add(tag);
        _selected.add(tag.id);
        _name.clear();
      });
    } on Object catch (error) {
      log('Adding a tag failed', name: 'FavoritePage', error: error);
      if (mounted) setState(() => _busy = false);
      AppNavigator.toast(i18n('tag_changes_save_failed'));
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.store.tags.setTagsOf(widget.room, [
        for (final tag in _tags)
          if (_selected.contains(tag.id)) tag.id,
      ]);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      log('Saving room tags failed', name: 'FavoritePage', error: error);
      if (mounted) setState(() => _busy = false);
      AppNavigator.toast(i18n('tag_assignment_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    i18n('favorite_tags_empty'),
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
                        selected: _selected.contains(tag.id),
                        onSelected: _busy
                            ? null
                            : (on) => setState(() => on ? _selected.add(tag.id) : _selected.remove(tag.id)),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('tag-new-name'),
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_add()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: i18n('tag_input_hint'),
                  errorText: _error,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: i18n('add_tag'),
                    icon: const Icon(Remix.add_line),
                    onPressed: _busy ? null : () => unawaited(_add()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(i18n('cancel'))),
        FilledButton(
          key: const ValueKey('tag-save'),
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(i18n('confirm')),
        ),
      ],
    );
  }
}
