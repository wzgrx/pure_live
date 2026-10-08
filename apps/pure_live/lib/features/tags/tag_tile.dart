import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// How many followed rooms carry each tag: tag id → count. Assignments of
/// rooms no longer followed are not counted (the follow page, where tags
/// filter rooms, does not show them).
Map<String, int> followedTagCounts(Map<String, List<String>> assignments, Iterable<LiveRoom> follows) {
  final counts = <String, int>{};
  for (final room in follows) {
    for (final id in assignments[room.identityKey] ?? const <String>[]) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
}

/// One tag in the list (docs/A-界面设计/A09-浏览界面/A09.10-标签管理 c2–c4): drag handle, name
/// (15/600), description (12 px, secondary colour) and the followed rooms,
/// then pin, edit and delete as 48 px buttons with 3.x's icons. The first
/// tag shows a filled pin that does nothing. A long press anywhere on the
/// card drags it too (3.x).
class TagTile extends StatelessWidget {
  /// Creates the row of [tag] at [index].
  const new({
    required this.tag,
    required this.index,
    required this.rooms,
    required this.enabled,
    required this.onOpen,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  /// The tag.
  final StoreTag tag;

  /// Its position (the first one is "at the top").
  final int index;

  /// Followed rooms with the tag.
  final int rooms;

  /// Whether the actions can be used (not while a change is saved).
  final bool enabled;

  /// Shows the details.
  final VoidCallback onOpen;

  /// Moves the tag to the top.
  final VoidCallback onPin;

  /// Edits the tag.
  final VoidCallback onEdit;

  /// Deletes the tag.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final isTop = index == 0;
    final name = {'name': tag.name};
    final described = tag.description.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ReorderableDelayedDragStartListener(
        index: index,
        enabled: enabled,
        child: Material(
          color: colors.surfaceContainerLow,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('tag-open-${tag.id}'),
            onTap: enabled ? onOpen : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    enabled: enabled,
                    child: Tooltip(
                      message: i18n('tags_drag_handle'),
                      child: MouseRegion(
                        cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
                        child: SizedBox(
                          key: ValueKey('tag-handle-${tag.id}'),
                          width: 44,
                          height: 48,
                          child: Icon(AppIcons.dragHandle, size: 20, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      label: i18n('view_tag_details_named', args: name),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tag.name,
                            key: ValueKey('tag-name-${tag.id}'),
                            style: styles.t15.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            described ? tag.description : i18n('no_description_placeholder'),
                            key: ValueKey('tag-description-${tag.id}'),
                            // G1: 3.x drew it 11 px in 38 % black (about 2.6:1).
                            style: styles.t12.copyWith(
                              color: colors.onSurfaceVariant,
                              fontStyle: described ? FontStyle.normal : FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(AppIcons.tagRooms, size: 14, color: colors.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  i18n('tags_room_count', args: {'count': '$rooms'}),
                                  key: ValueKey('tag-rooms-${tag.id}'),
                                  style: styles.t12.copyWith(color: colors.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('tag-pin-${tag.id}'),
                    tooltip: i18n(isTop ? 'tag_already_at_top_named' : 'move_tag_to_top_named', args: name),
                    icon: Icon(isTop ? AppIcons.pinned : AppIcons.unpinned, size: 22),
                    color: colors.primary,
                    // The first one keeps its filled pin (3.x), not greyed out.
                    disabledColor: isTop ? colors.primary : null,
                    onPressed: enabled && !isTop ? onPin : null,
                  ),
                  IconButton(
                    key: ValueKey('tag-edit-${tag.id}'),
                    tooltip: i18n('edit_tag_named', args: name),
                    icon: const Icon(AppIcons.edit, size: 22),
                    color: colors.onSurfaceVariant,
                    onPressed: enabled ? onEdit : null,
                  ),
                  IconButton(
                    key: ValueKey('tag-delete-${tag.id}'),
                    tooltip: i18n('delete_tag_named', args: name),
                    icon: const Icon(AppIcons.delete, size: 22),
                    color: colors.error,
                    onPressed: enabled ? onDelete : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the details dialog was closed with.
enum TagDetailsAction {
  /// Open the editor.
  edit,
}

/// Shows [tag]'s name, description and followed rooms (3.x
/// `_showTagDetails`; c6): "编辑标签" opens the editor, "关闭" closes (3.x
/// had only "确认").
Future<TagDetailsAction?> showTagDetails(BuildContext context, {required StoreTag tag, required int rooms}) =>
    showAppDialog<TagDetailsAction>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        final styles = dialogContext.textStyles;
        Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(text, style: styles.t12.emphasis.copyWith(color: colors.primary)),
        );
        return AppDialog(
          key: const ValueKey('tag-details'),
          title: i18n('tag_detail'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i18n('tag_name_label'), style: styles.t12.emphasis.copyWith(color: colors.primary)),
              const SizedBox(height: 6),
              Text(tag.name, style: styles.t16.copyWith(fontWeight: FontWeight.w600)),
              if (tag.description.isNotEmpty) ...[
                label(i18n('tag_desc_label')),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(tag.description, style: styles.t14.copyWith(height: 1.4)),
                ),
              ],
              label(i18n('tags_rooms_label')),
              Text(i18n('tags_room_count', args: {'count': '$rooms'}), style: styles.t14),
            ],
          ),
          actions: [
            DialogCancelButton(key: const ValueKey('tag-details-close'), label: i18n('close')),
            DialogActionButton(
              key: const ValueKey('tag-details-edit'),
              label: i18n('edit_tag'),
              onPressed: () => Navigator.pop(dialogContext, TagDetailsAction.edit),
            ),
          ],
        );
      },
    );
