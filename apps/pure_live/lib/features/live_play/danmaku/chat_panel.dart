import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_settings_panel.dart';
import 'package:pure_live/features/live_play/danmaku/super_chats.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/block_manager.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

export 'package:pure_live/features/live_play/danmaku/chat_list.dart' show superChatPrice;
export 'package:pure_live/features/live_play/danmaku/super_chats.dart' show SuperChatCard, SuperChatList;

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
            // Rebuilt only when the super chats change; one clock inside
            // moves the times on (U.2e c6).
            ListenableSelector<List<LiveSuperChatMessage>>(
              listenable: widget.controller,
              selector: () => widget.controller.superChats,
              builder: (context, messages, _) => SuperChatList(
                messages: messages,
                now: widget.controller.now,
                platformName: platformName(widget.controller.site.id, fallback: widget.controller.site.name),
                platformHasSuperChats: widget.controller.site.hasSuperChats,
              ),
            ),
            // U.2e c8: the U.2f component, "改动立即生效" by the first title.
            RoomDanmakuSettings(controller: widget.controller, inTab: true),
            // U.2e c11-c16; the same component as the settings page's (E4).
            DanmakuBlockManager(addKeyword: widget.controller.blockKeyword),
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
