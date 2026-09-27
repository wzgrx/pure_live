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

/// Asks for a group name; null when cancelled.
Future<String?> askGroupName(BuildContext context, {String initial = '', String title = '新建分组'}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(hintText: '分组名称'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('确定')),
      ],
    ),
  );
  controller.dispose();
  return name == null || name.isEmpty ? null : name;
}

/// Creates or renames a group and reports a duplicate name in place.
Future<Tag?> createGroup(BuildContext context, WidgetRef ref) async {
  final name = await askGroupName(context);
  if (name == null) return null;
  try {
    return await ref.read(storeProvider).tags.create(name);
  } on TagNameException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.duplicate ? '已经有叫“$name”的分组了' : '分组名称不能为空')));
    }
    return null;
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
  if (chosen != null) await store.tags.setTagsOf(room, chosen);
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '改名',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final name = await askGroupName(context, initial: tag.name, title: '分组改名');
                              if (name == null) return;
                              try {
                                await store.tags.rename(tag.id, name);
                              } on TagNameException {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text('已经有叫“$name”的分组了')));
                                }
                              }
                            },
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
