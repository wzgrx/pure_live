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

/// One tag in the list: drag handle, name, description and room count,
/// then pin, edit and delete (3.x tag card).
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final styles = context.textStyles;
    final isTop = index == 0;
    final name = {'name': tag.name};
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ReorderableDelayedDragStartListener(
        index: index,
        enabled: enabled,
        child: Material(
          color: colors.secondary.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.secondary.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('tag-open-${tag.id}'),
            onTap: enabled ? onOpen : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
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
                          width: 44,
                          height: 48,
                          child: Icon(Icons.drag_indicator_rounded, color: colors.onSurfaceVariant),
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
                            style: styles.t14.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tag.description.isNotEmpty ? tag.description : i18n('no_description_placeholder'),
                            style: styles.t11.copyWith(
                              color: tag.description.isNotEmpty
                                  ? colors.onSurfaceVariant
                                  : colors.onSurfaceVariant.withValues(alpha: 0.5),
                              fontStyle: tag.description.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.live_tv_rounded, size: 13, color: colors.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  i18n('tags_room_count', args: {'count': '$rooms'}),
                                  key: ValueKey('tag-rooms-${tag.id}'),
                                  style: styles.t11.copyWith(color: colors.primary),
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
                    icon: Icon(isTop ? Icons.push_pin : Icons.push_pin_outlined, size: 20),
                    color: colors.primary,
                    onPressed: enabled && !isTop ? onPin : null,
                  ),
                  IconButton(
                    key: ValueKey('tag-edit-${tag.id}'),
                    tooltip: i18n('edit_tag_named', args: name),
                    icon: Icon(Icons.edit_outlined, size: 20, color: colors.onSurfaceVariant),
                    onPressed: enabled ? onEdit : null,
                  ),
                  IconButton(
                    key: ValueKey('tag-delete-${tag.id}'),
                    tooltip: i18n('delete_tag_named', args: name),
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.error.withValues(alpha: 0.8)),
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

/// Shows [tag]'s name, description and room count (3.x `_showTagDetails`),
/// with a button that opens the editor.
Future<TagDetailsAction?> showTagDetails(BuildContext context, {required StoreTag tag, required int rooms}) =>
    showDialog<TagDetailsAction>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        final styles = dialogContext.textStyles;
        Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(text, style: styles.t12Bold.copyWith(color: colors.primary)),
        );
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(i18n('tag_detail'), style: styles.t16Bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n('tag_name_label'), style: styles.t12Bold.copyWith(color: colors.primary)),
                const SizedBox(height: 6),
                Text(tag.name, style: styles.t16.copyWith(fontWeight: FontWeight.w600)),
                if (tag.description.isNotEmpty) ...[
                  label(i18n('tag_desc_label')),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(tag.description, style: styles.t14.copyWith(height: 1.4)),
                  ),
                ],
                label(i18n('tags_rooms_label')),
                Text(i18n('tags_room_count', args: {'count': '$rooms'}), style: styles.t14),
              ],
            ),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              key: const ValueKey('tag-details-edit'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(dialogContext, TagDetailsAction.edit),
              child: Text(i18n('edit_tag')),
            ),
            FilledButton(
              key: const ValueKey('tag-details-close'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(i18n('confirm')),
            ),
          ],
        );
      },
    );
