import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_view.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Blocked words and users (F-DM-04: 3.x's shield page and the room tab
/// merged into one page). Matching ignores case and surrounding spaces
/// (FLT-2); changes apply to open rooms at once.
class BlockListPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: PageAppBar(
        title: Text(t.danmaku.blockListTitle),
        bottom: TabBar(
          tabs: [
            Tab(text: t.danmaku.blockKeywords),
            Tab(text: t.danmaku.blockUsers),
          ],
        ),
      ),
      body: const PageBody(
        child: TabBarView(
          children: [
            _RuleList(kind: BlockKind.keyword),
            _RuleList(kind: BlockKind.user),
          ],
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.danmaku.alreadyBlocked(value: value))));
    }
  }

  void _remove(BlockRule rule) {
    unawaited(ref.read(blockRuleWriterProvider).remove(rule.kind, rule.value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(t.danmaku.unblocked(value: rule.value)),
          action: SnackBarAction(
            label: t.common.undo,
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
                    hintText: _keyword ? t.danmaku.keywordHint : t.danmaku.userHint,
                    helperText: _keyword ? t.danmaku.keywordHelper : t.danmaku.userHelper,
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: Space.s2),
              FilledButton(onPressed: _add, child: Text(t.common.add)),
            ],
          ),
        ),
        Expanded(
          child: rules.when(
            loading: () => const SkeletonList(leading: false),
            error: (error, _) => ErrorView(
              error,
              title: t.danmaku.blockListLoadFailed,
              onRetry: () => ref.invalidate(blockRulesProvider),
            ),
            data: (all) {
              final shown = [
                for (final rule in all.reversed)
                  if (rule.kind == widget.kind) rule,
              ];
              if (shown.isEmpty) {
                return MessageView(
                  icon: _keyword ? LiveIcons.block : LiveIcons.blockUser,
                  title: _keyword ? t.danmaku.noBlockedKeywords : t.danmaku.noBlockedUsers,
                  message: t.danmaku.blockFromRoomHint,
                );
              }
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final rule = shown[index];
                  return ListTile(
                    title: Text(rule.value),
                    trailing: IconButton(
                      tooltip: t.common.remove,
                      icon: const LiveIcon(LiveIcons.close),
                      onPressed: () => _remove(rule),
                    ),
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
