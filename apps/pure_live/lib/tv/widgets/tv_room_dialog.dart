import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/tags/tag_editor_dialog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// A page's own action in the card dialog (history: "删除这条记录").
@immutable
final class TvRoomAction {
  /// Creates the action; with [confirmTitle] it asks first (a dangerous
  /// question, the focus on cancel).
  const new({
    required this.key,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.confirmTitle,
    this.confirmMessage,
  });

  /// The button's key (tests find it by this).
  final Key key;

  /// Its icon.
  final IconData icon;

  /// Its words.
  final String label;

  /// Runs after the dialog closed (and the question was answered yes).
  final VoidCallback onSelected;

  /// The question's title; null acts at once.
  final String? confirmTitle;

  /// The question.
  final String? confirmMessage;
}

/// The card dialog of the TV (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c9): a held OK or the
/// menu key on any room card opens it, on every page (pure_live_TV had a
/// follow question, a follows menu and a history menu, P10). It is the
/// phone's card dialog (U.4a) in the TV style:
///
/// - the platform's logo, the streamer, "平台 · 房间号" and the whole title;
/// - "设置标签" (the focus starts here; a room not followed is followed
///   first) and the page's [actions] (history: "删除这条记录", asked first);
/// - "关闭" on the left, "＋ 关注 / ✓ 已关注" on the right: following is
///   immediate, unfollowing asks first with the focus on cancel (c12); the
///   dialog stays and the button flips.
Future<void> showTvRoomDialog(
  BuildContext context, {
  required LiveStore store,
  required LiveRoom room,
  List<TvRoomAction> actions = const [],
}) async {
  final picked = await showTvDialog<Object>(
    context,
    builder: (_) => TvRoomDialog(store: store, room: room, actions: actions),
  );
  if (!context.mounted || picked is! TvRoomAction) return;
  if (picked.confirmTitle case final title?) {
    final confirmed = await showTvConfirm(
      context,
      title: title,
      message: picked.confirmMessage ?? '',
      confirmLabel: picked.label,
      danger: true,
    );
    if (!confirmed) return;
  }
  picked.onSelected();
}

/// The content of [showTvRoomDialog].
class TvRoomDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({required this.store, required this.room, this.actions = const [], super.key});

  /// Storage.
  final LiveStore store;

  /// The room.
  final LiveRoom room;

  /// The page's own actions.
  final List<TvRoomAction> actions;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final name = room.displayNick(platformName(room.platform));
    final title = room.title.trim();
    return TvDialog(
      key: const ValueKey('tv-room-dialog'),
      width: 520,
      header: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(scale.px(8)),
            child: PlatformLogo(room.platform, size: scale.pxText(36)),
          ),
          SizedBox(width: scale.px(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.font(TvTextSize.heading, weight: FontWeight.w600, color: palette.text, height: 1.3),
                ),
                Text(
                  i18n('tv_room_platform_id', args: {'platform': platformName(room.platform), 'id': room.roomId}),
                  key: const ValueKey('tv-room-dialog-id'),
                  style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4).tabular,
                ),
              ],
            ),
          ),
        ],
      ),
      leading: TvButton(
        key: const ValueKey('tv-room-dialog-close'),
        label: i18n('close'),
        onTap: () => Navigator.pop(context),
      ),
      actions: [
        StreamBuilder<bool>(
          stream: store.follows.watchContains(room),
          builder: (context, snapshot) {
            final followed = snapshot.data;
            return TvButton(
              key: const ValueKey('tv-room-dialog-follow'),
              icon: followed ?? false ? AppIcons.followed : AppIcons.follow,
              label: i18n(followed ?? false ? 'followed' : 'follow'),
              kind: followed ?? false ? TvButtonKind.normal : TvButtonKind.primary,
              onTap: followed == null
                  ? null
                  : () => unawaited(
                      followed ? tvUnfollowRoom(context, store: store, room: room) : followRoom(store, room),
                    ),
            );
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: EdgeInsets.only(top: scale.px(16)),
            padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(12)),
            decoration: BoxDecoration(color: palette.low, borderRadius: BorderRadius.circular(scale.px(TvRadius.card))),
            child: Text(
              title.isEmpty ? name : title,
              key: const ValueKey('tv-room-dialog-title'),
              style: scale.font(TvTextSize.body, color: palette.text, height: 1.55),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: scale.px(16)),
            child: Wrap(
              spacing: scale.px(12),
              runSpacing: scale.px(12),
              children: [
                TvButton(
                  key: const ValueKey('tv-room-dialog-tags'),
                  icon: TvIcons.tags,
                  label: i18n('tv_set_tags'),
                  autofocus: true,
                  onTap: () => unawaited(tvEditRoomTags(context, store: store, room: room)),
                ),
                for (final action in actions)
                  TvButton(
                    key: action.key,
                    icon: action.icon,
                    label: action.label,
                    onTap: () => Navigator.pop(context, action),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Unfollows [room] after asking (U.15a c9, c12: the focus on "取消", the
/// main button "取消关注" in the error colour); completes with whether it
/// was unfollowed.
Future<bool> tvUnfollowRoom(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  final name = room.displayNick(platformName(room.platform));
  final confirmed = await showTvConfirm(
    context,
    title: i18n('unfollow'),
    message: i18n('unfollow_message', args: {'name': name}),
    confirmLabel: i18n('unfollow'),
    danger: true,
  );
  if (!confirmed) return false;
  try {
    if (!await store.follows.remove(room)) return false;
    AppNavigator.toast(i18n('room_unfollowed', args: {'name': name}));
    return true;
  } on Object catch (error, stack) {
    log('Unfollow failed', name: 'TvRoomDialog', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('favorite_changes_save_failed'));
    return false;
  }
}

/// Sets the tags of [room] (U.15a c11): a room not followed is followed
/// first (tags belong to follows), then the tag dialog.
Future<void> tvEditRoomTags(BuildContext context, {required LiveStore store, required LiveRoom room}) async {
  if (!await store.follows.contains(room) && !await followRoom(store, room)) return;
  final List<StoreTag> tags;
  final Set<String> selected;
  try {
    tags = await store.tags.all();
    selected = (await store.tags.tagsOf(room)).toSet();
  } on Object catch (error, stack) {
    log('Reading tags failed', name: 'TvRoomDialog', error: error, stackTrace: stack);
    AppNavigator.toast(i18n('tag_changes_save_failed'));
    return;
  }
  if (!context.mounted) return;
  await showTvDialog<void>(
    context,
    builder: (_) => TvRoomTagsDialog(store: store, room: room, tags: tags, selected: selected),
  );
}

/// The tag dialog of the TV (U.15a c11, the phone's tag dialog of U.4a in
/// the TV style): the room under the title, one row per tag with a round
/// tick, "新建标签" at the end (also when there are no tags: pure_live_TV
/// pointed at a "+" the TV did not have, P11), "取消 / 确认". The focus
/// starts on the first row.
class TvRoomTagsDialog extends StatefulWidget {
  /// Creates the dialog.
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
  State<TvRoomTagsDialog> createState() => _TvRoomTagsDialogState();
}

class _TvRoomTagsDialogState extends State<TvRoomTagsDialog> {
  late final List<StoreTag> _tags = List.of(widget.tags);
  late final Set<String> _selected = Set.of(widget.selected);
  bool _busy = false;

  Future<void> _create() async {
    final name = await TvTextInput.prompt(
      context,
      title: i18n('room_tags_new'),
      hint: i18n('tv_tag_name_hint'),
      maxLength: tagNameMaxLength,
    );
    if (name == null || !mounted) return;
    final text = name.trim();
    final tags = widget.store.tags;
    try {
      final validation = await tags.validateName(text);
      if (validation != TagNameValidation.valid) {
        AppNavigator.toast(
          i18n(validation == TagNameValidation.empty ? 'tag_name_empty_error' : 'tag_name_duplicate_error'),
        );
        return;
      }
      final tag = await tags.add(text.length > tagNameMaxLength ? text.substring(0, tagNameMaxLength) : text);
      if (tag == null) {
        AppNavigator.toast(i18n('tag_invalid_or_duplicate'));
        return;
      }
      if (!mounted) return;
      // A new tag is ticked at once (c11).
      setState(() {
        _tags.add(tag);
        _selected.add(tag.id);
      });
    } on Object catch (error, stack) {
      log('Adding a tag failed', name: 'TvRoomDialog', error: error, stackTrace: stack);
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
    } on Object catch (error, stack) {
      log('Saving room tags failed', name: 'TvRoomDialog', error: error, stackTrace: stack);
      if (mounted) setState(() => _busy = false);
      AppNavigator.toast(i18n('tag_assignment_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final name = room.displayNick(platformName(room.platform));
    return TvDialog(
      key: const ValueKey('tv-room-tags'),
      title: i18n('set_room_tags'),
      subtitle: i18n('tv_tags_room', args: {'name': name, 'platform': platformName(room.platform)}),
      actions: [
        TvButton(
          key: const ValueKey('tv-room-tags-cancel'),
          label: i18n('cancel'),
          onTap: _busy ? null : () => Navigator.pop(context),
        ),
        TvButton(
          key: const ValueKey('tv-room-tags-save'),
          label: i18n('confirm'),
          kind: TvButtonKind.primary,
          onTap: _busy ? null : () => unawaited(_save()),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(top: TvScale.of(context).px(12)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, tag) in _tags.indexed)
                TvOptionRow(
                  key: ValueKey('tv-tag-${tag.id}'),
                  label: tag.name,
                  description: tag.description.trim().isEmpty ? null : tag.description,
                  leading: TvTick(ticked: _selected.contains(tag.id)),
                  autofocus: index == 0,
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          if (!_selected.remove(tag.id)) _selected.add(tag.id);
                        }),
                ),
              TvOptionRow(
                key: const ValueKey('tv-tags-new'),
                label: i18n('room_tags_new'),
                icon: AppIcons.add,
                accent: true,
                autofocus: _tags.isEmpty,
                onTap: _busy ? null : () => unawaited(_create()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round tick of a multiple choice (U.15a, tags 31): an outlined circle,
/// filled with the primary colour and a tick when on.
class TvTick extends StatelessWidget {
  /// Creates the tick.
  const new({required this.ticked, super.key});

  /// On or off.
  final bool ticked;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final size = scale.pxText(22);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ticked ? palette.accent : null,
        border: Border.all(color: ticked ? palette.accent : palette.outline, width: scale.px(2)),
      ),
      child: ticked ? Icon(TvIcons.ticked, size: scale.pxText(16), color: palette.onAccent) : null,
    );
  }
}
