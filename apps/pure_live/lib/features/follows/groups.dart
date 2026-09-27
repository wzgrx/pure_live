import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Groups (tags) in the user's order (spec/product.md F-FAV-05).
final StreamProvider<List<Tag>> tagsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(storeProvider).tags.watchAll(),
);

/// A group's name and description as entered.
typedef GroupFields = ({String name, String description});

/// Asks for a group's name and description (F-FAV-05); null when cancelled
/// or the name is empty.
Future<GroupFields?> askGroupFields(
  BuildContext context, {
  String name = '',
  String description = '',
  String? title,
}) async {
  final result = await showDialog<GroupFields>(
    context: context,
    builder: (context) => _GroupEditor(title: title ?? t.follows.newGroup, name: name, description: description),
  );
  return result == null || result.name.isEmpty ? null : result;
}

/// The fields of [askGroupFields]; the controllers live as long as the dialog,
/// including its closing animation.
class _GroupEditor extends StatefulWidget {
  const new({required this.title, required this.name, required this.description});

  final String title;
  final String name;
  final String description;

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  late final _name = TextEditingController(text: widget.name);
  late final _description = TextEditingController(text: widget.description);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, (name: _name.text.trim(), description: _description.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(labelText: t.follows.groupName),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: _description,
          maxLength: 60,
          decoration: InputDecoration(labelText: t.follows.groupDescription, hintText: t.follows.groupDescriptionHint),
          onSubmitted: (_) => _done(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
      FilledButton(onPressed: _done, child: Text(t.common.ok)),
    ],
  );
}

void _say(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Creates a group and reports a duplicate name in place.
Future<Tag?> createGroup(BuildContext context, WidgetRef ref) async {
  final fields = await askGroupFields(context);
  if (fields == null || !context.mounted) return null;
  try {
    return await ref.read(storeProvider).tags.create(fields.name, description: fields.description);
  } on TagNameException catch (error) {
    if (context.mounted) {
      _say(context, error.duplicate ? t.follows.groupExists(name: fields.name) : t.follows.groupNameEmpty);
    }
    return null;
  }
}

/// Edits the name and description of [tag] (F-FAV-05: 改名、描述).
Future<void> editGroup(BuildContext context, WidgetRef ref, Tag tag) async {
  final fields = await askGroupFields(
    context,
    name: tag.name,
    description: tag.description,
    title: t.follows.editGroup,
  );
  if (fields == null || !context.mounted) return;
  final tags = ref.read(storeProvider).tags;
  try {
    if (fields.name != tag.name) await tags.rename(tag.id, fields.name);
    if (fields.description != tag.description) await tags.describe(tag.id, fields.description);
  } on TagNameException {
    if (context.mounted) _say(context, t.follows.groupExists(name: fields.name));
  }
}

/// Picks the groups of one followed room.
Future<void> editRoomGroups(BuildContext context, WidgetRef ref, RoomRef room, String title) async {
  final store = ref.read(storeProvider);
  final current = await store.tags.tagsOf(room);
  if (!context.mounted) return;
  final chosen = await showDialog<Set<String>>(
    context: context,
    builder: (context) => _GroupPicker(title: title, initial: current),
  );
  if (chosen == null) return;
  try {
    await store.tags.setTagsOf(room, chosen);
  } on Object {
    // The write is one transaction: the groups stay as they were.
    if (context.mounted) _say(context, t.follows.groupNotSaved);
  }
}

class _GroupPicker extends ConsumerStatefulWidget {
  const new({required this.title, required this.initial});

  final String title;
  final Set<String> initial;

  @override
  ConsumerState<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends ConsumerState<_GroupPicker> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    return AlertDialog(
      title: Text(t.follows.setGroupsFor(title: widget.title)),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final tag in tags)
              CheckboxListTile(
                value: _selected.contains(tag.id),
                title: Text(tag.name),
                onChanged: (on) => setState(() => on! ? _selected.add(tag.id) : _selected.remove(tag.id)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(t.follows.newGroup),
              onTap: () async {
                final tag = await createGroup(context, ref);
                if (tag != null) setState(() => _selected.add(tag.id));
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: Text(t.common.save)),
      ],
    );
  }
}

/// Group management: create, rename, reorder by dragging, delete with undo.
class GroupsPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final store = ref.read(storeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.follows.manageGroups)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createGroup(context, ref),
        icon: const Icon(Icons.add),
        label: Text(t.follows.newGroup),
      ),
      body: tags.isEmpty
          ? MessageView(icon: Icons.folder_outlined, title: t.follows.noGroups, message: t.follows.groupsHint)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
                child: ReorderableListView.builder(
                  itemCount: tags.length,
                  onReorderItem: (from, to) {
                    final ids = [for (final tag in tags) tag.id];
                    final moved = ids.removeAt(from);
                    ids.insert(to, moved);
                    unawaited(store.tags.reorder(ids));
                  },
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    return ListTile(
                      key: ValueKey(tag.id),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(tag.name),
                      subtitle: tag.description.isEmpty ? null : Text(tag.description, maxLines: 2),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: t.follows.renameAndDescribe,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => editGroup(context, ref, tag),
                          ),
                          IconButton(
                            tooltip: t.common.delete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final members = [
                                for (final follow in await store.follows.all())
                                  if (follow.tagIds.contains(tag.id)) follow.ref,
                              ];
                              await store.tags.delete(tag.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(t.follows.groupDeleted(name: tag.name)),
                                  action: SnackBarAction(
                                    label: t.common.undo,
                                    onPressed: () async {
                                      final restored = await store.tags.create(tag.name, description: tag.description);
                                      await store.tags.addRooms(restored.id, members);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// Copies text and says so.
Future<void> copyWithToast(BuildContext context, String text, String toast) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
}
