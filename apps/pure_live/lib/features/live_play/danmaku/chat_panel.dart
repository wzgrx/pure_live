import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_settings_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

export 'package:pure_live/features/live_play/danmaku/chat_list.dart' show superChatPrice;

/// The four tabs under the video (3.x `DanmakuTabView`, four equal widths):
/// chat, super chats (with their count, U.2a change 9), danmaku settings and
/// the block list. While the room details cover the tabs, the messages that
/// arrive are counted on "弹幕列表" until the list is looked at again.
class ChatPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, this.detailsOpen = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Whether the room details cover the panel.
  final bool detailsOpen;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    animationDuration: pureLiveTabTransitionDuration,
  );

  /// The chat count when the details opened; null when nothing is pending.
  int? _unreadFrom;

  @override
  void initState() {
    super.initState();
    if (widget.detailsOpen) _unreadFrom = widget.controller.chat.added;
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.detailsOpen && !oldWidget.detailsOpen) _unreadFrom = widget.controller.chat.added;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _seen() {
    if (_unreadFrom != null && !widget.detailsOpen) setState(() => _unreadFrom = null);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TabBar(
        key: const ValueKey('live-play-tabs'),
        controller: _tabs,
        tabAlignment: TabAlignment.fill,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        onTap: (index) {
          if (index == 0) _seen();
        },
        tabs: [
          Tab(
            child: ListenableSelector<int>(
              listenable: widget.controller,
              selector: () {
                final from = _unreadFrom;
                return from == null ? 0 : widget.controller.chat.added - from;
              },
              builder: (context, count, _) => _TabLabel(
                text: i18n('danmaku_list'),
                count: count,
                countKey: const ValueKey('live-play-unread-count'),
                semantics: i18n('live_play_unread_count', args: {'count': '$count'}),
              ),
            ),
          ),
          Tab(
            child: ListenableSelector<int>(
              listenable: widget.controller,
              selector: () => widget.controller.superChats.length,
              builder: (context, count, _) => _TabLabel(
                text: i18n('super_chat'),
                count: count,
                countKey: const ValueKey('live-play-super-chat-count'),
              ),
            ),
          ),
          Tab(text: i18n('danmaku_settings')),
          Tab(text: i18n('block_list')),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          physics: const PureLiveBoundedScrollPhysics(),
          children: [
            ChatList(controller: widget.controller, onTouched: _seen),
            // Rebuilt with the room as before: the remaining times move on
            // with each update (the super chat tab is U.2e's).
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) =>
                  SuperChatList(messages: widget.controller.superChats, now: widget.controller.now),
            ),
            RoomDanmakuSettings(controller: widget.controller),
            const BlockListPanel(),
          ],
        ),
      ),
    ],
  );
}

class _TabLabel extends StatelessWidget {
  const new({required this.text, required this.count, required this.countKey, this.semantics});

  final String text;
  final int count;
  final Key countKey;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = Semantics(
      label: semantics,
      child: Container(
        key: countKey,
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: theme.textTheme.labelSmall?.emphasis.tabular.copyWith(color: scheme.onPrimary, height: 1.1),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: DefaultTextStyle.of(context).style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        if (width + 24 <= constraints.maxWidth) {
          // Room for the count after the word (U.2a change 9).
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [Text(text, maxLines: 1), const SizedBox(width: 4), number],
          );
        }
        // A narrow column (the wide layout's chat): the count sits on the
        // word's corner instead of cutting it short.
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            Positioned(top: -10, right: -18, child: number),
          ],
        );
      },
    );
  }
}

/// Super chats on display with their remaining time (3.x `SuperChatPage`).
class SuperChatList extends StatelessWidget {
  /// Creates the list.
  const new({required this.messages, required this.now, super.key});

  /// Messages, oldest first.
  final List<LiveSuperChatMessage> messages;

  /// The clock.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return AppStatusView(
        type: AppStatusType.empty,
        isMini: true,
        title: i18n('super_chat_empty_title'),
        subtitle: i18n('super_chat_empty_subtitle'),
      );
    }
    final theme = Theme.of(context);
    final current = now();
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final superChat = messages[messages.length - 1 - index];
        final top = parsePlatformColor(superChat.backgroundColor) ?? theme.colorScheme.tertiaryContainer;
        final bottom = parsePlatformColor(superChat.backgroundBottomColor) ?? theme.colorScheme.tertiary;
        final left = superChat.endTime.difference(current);
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: top,
                child: ListTile(
                  dense: true,
                  leading: CommonAvatar(avatarUrl: superChat.face, radius: 16, fallbackName: superChat.userName),
                  title: Text(superChat.userName, style: const TextStyle(color: InkOnColor.dark)),
                  subtitle: Text(superChatPrice(superChat), style: const TextStyle(color: InkOnColor.dark)),
                  trailing: Text(
                    left.isNegative ? '' : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: InkOnColor.darkMuted),
                  ),
                ),
              ),
              ColoredBox(
                color: bottom,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(superChat.message, style: const TextStyle(color: InkOnColor.light)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Blocked words and viewers (3.x `KeywordBlockPage`): add a word, tap a
/// chip to remove it.
class BlockListPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const new({super.key});

  @override
  ConsumerState<BlockListPanel> createState() => _BlockListPanelState();
}

class _BlockListPanelState extends ConsumerState<BlockListPanel> {
  final TextEditingController _input = TextEditingController();
  late final Stream<List<String>> _keywords;
  late final Stream<List<String>> _users;

  @override
  void initState() {
    super.initState();
    final lists = ref.read(storeProvider).blockLists;
    _keywords = lists.watch(BlockKind.keyword);
    _users = lists.watch(BlockKind.user);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final words = _input.text
        .split(RegExp(r'[\n,，]'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      AppNavigator.toast(i18n('please_enter_keyword'));
      return;
    }
    final lists = ref.read(storeProvider).blockLists;
    var added = 0;
    for (final word in words) {
      if (await lists.add(BlockKind.keyword, word)) added++;
    }
    _input.clear();
    AppNavigator.toast(i18n('keyword_added_count', args: {'count': '$added'}));
  }

  Widget _chips(Stream<List<String>> stream, BlockKind kind, String empty) => StreamBuilder<List<String>>(
    stream: stream,
    builder: (context, snapshot) {
      final values = snapshot.data ?? const <String>[];
      if (values.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(empty, style: Theme.of(context).textTheme.bodySmall),
        );
      }
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final value in values)
            InputChip(
              label: Text(value),
              tooltip: i18n('click_to_remove'),
              onDeleted: () => unawaited(ref.read(storeProvider).blockLists.remove(kind, value)),
              onPressed: () => unawaited(ref.read(storeProvider).blockLists.remove(kind, value)),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('live-play-block-list'),
    padding: const EdgeInsets.all(12),
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('live-play-block-input'),
              controller: _input,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: i18n('please_enter_keyword'),
              ),
              onSubmitted: (_) => unawaited(_add()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('live-play-block-add'),
            onPressed: () => unawaited(_add()),
            child: Text(i18n('add')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(i18n('danmaku_keyword_block'), style: Theme.of(context).textTheme.titleSmall),
      _chips(_keywords, BlockKind.keyword, i18n('live_play_no_blocked_words')),
      const SizedBox(height: 12),
      StreamBuilder<List<String>>(
        stream: _users,
        builder: (context, snapshot) => Text(
          i18n('blocked_danmaku_users', args: {'count': '${snapshot.data?.length ?? 0}'}),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      _chips(_users, BlockKind.user, i18n('live_play_no_blocked_users')),
    ],
  );
}
