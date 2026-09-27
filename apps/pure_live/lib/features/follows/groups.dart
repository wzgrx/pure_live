import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';

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
  String title = '新建分组',
}) async {
  final result = await showDialog<GroupFields>(
    context: context,
    builder: (context) => _GroupEditor(title: title, name: name, description: description),
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
          decoration: const InputDecoration(labelText: '分组名称'),
          textInputAction: TextInputAction.next,
        ),
        TextField(
          controller: _description,
          maxLength: 60,
          decoration: const InputDecoration(labelText: '描述（可选）', hintText: '比如：晚上常看的'),
          onSubmitted: (_) => _done(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _done, child: const Text('确定')),
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
    if (context.mounted) _say(context, error.duplicate ? '已经有叫“${fields.name}”的分组了' : '分组名称不能为空');
    return null;
  }
}

/// Edits the name and description of [tag] (F-FAV-05: 改名、描述).
Future<void> editGroup(BuildContext context, WidgetRef ref, Tag tag) async {
  final fields = await askGroupFields(context, name: tag.name, description: tag.description, title: '编辑分组');
  if (fields == null || !context.mounted) return;
  final tags = ref.read(storeProvider).tags;
  try {
    if (fields.name != tag.name) await tags.rename(tag.id, fields.name);
    if (fields.description != tag.description) await tags.describe(tag.id, fields.description);
  } on TagNameException {
    if (context.mounted) _say(context, '已经有叫“${fields.name}”的分组了');
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
    if (context.mounted) _say(context, '分组没有保存，请重试');
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
      title: Text('设置分组 · ${widget.title}'),
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
              title: const Text('新建分组'),
              onTap: () async {
                final tag = await createGroup(context, ref);
                if (tag != null) setState(() => _selected.add(tag.id));
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('保存')),
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
      appBar: AppBar(title: const Text('管理分组')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createGroup(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建分组'),
      ),
      body: tags.isEmpty
          ? const MessageView(icon: Icons.folder_outlined, title: '还没有分组', message: '分组可以把关注的主播归类，在关注页按分组查看。')
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
                            tooltip: '改名和描述',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => editGroup(context, ref, tag),
                          ),
                          IconButton(
                            tooltip: '删除',
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
                                  content: Text('已删除分组“${tag.name}”'),
                                  action: SnackBarAction(
                                    label: '撤销',
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
