import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';

/// Blocked words and users (F-DM-04: 3.x's shield page and the room tab
/// merged into one page). Matching ignores case and surrounding spaces
/// (FLT-2); changes apply to open rooms at once.
class BlockListPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('屏蔽词和屏蔽用户'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '关键词'),
            Tab(text: '用户'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _RuleList(kind: BlockKind.keyword),
          _RuleList(kind: BlockKind.user),
        ],
      ),
    ),
  );
}

class _RuleList extends ConsumerStatefulWidget {
  const new({required this.kind});

  final BlockKind kind;

  @override
  ConsumerState<_RuleList> createState() => _RuleListState();
}

class _RuleListState extends ConsumerState<_RuleList> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _keyword => widget.kind == BlockKind.keyword;

  Future<void> _add() async {
    final value = _input.text.trim();
    if (value.isEmpty) return;
    _input.clear();
    final added = await ref.read(blockRuleWriterProvider).add(widget.kind, value);
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('“$value”已经在列表里')));
    }
  }

  void _remove(BlockRule rule) {
    unawaited(ref.read(blockRuleWriterProvider).remove(rule.kind, rule.value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已移除“${rule.value}”'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => unawaited(ref.read(blockRuleWriterProvider).add(rule.kind, rule.value)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(blockRulesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 64,
                  decoration: InputDecoration(
                    hintText: _keyword ? '输入要屏蔽的词' : '输入要屏蔽的用户名',
                    helperText: _keyword ? '包含这个词的弹幕不显示' : '按用户名完全匹配',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: Space.s2),
              FilledButton(onPressed: _add, child: const Text('添加')),
            ],
          ),
        ),
        Expanded(
          child: rules.when(
            loading: () => const LoadingView(),
            error: (error, _) => MessageView.error(title: '读取屏蔽列表失败', message: '$error'),
            data: (all) {
              final shown = [
                for (final rule in all.reversed)
                  if (rule.kind == widget.kind) rule,
              ];
              if (shown.isEmpty) {
                return MessageView(
                  icon: _keyword ? Icons.block : Icons.person_off_outlined,
                  title: _keyword ? '还没有屏蔽词' : '还没有屏蔽用户',
                  message: '也可以在直播间里点一条弹幕来屏蔽',
                );
              }
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final rule = shown[index];
                  return ListTile(
                    title: Text(rule.value),
                    trailing: IconButton(tooltip: '移除', icon: const Icon(Icons.close), onPressed: () => _remove(rule)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
