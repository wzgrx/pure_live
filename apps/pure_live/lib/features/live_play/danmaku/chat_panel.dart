import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_settings_panel.dart';
import 'package:pure_live/features/live_play/danmaku/super_chats.dart';
import 'package:pure_live/features/live_play/layout/room_view_memory.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
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
  const new({
    required this.controller,
    this.detailsOpen = false,
    this.memory,
    this.composerCollapsed = false,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The local composer is a star on the list instead of a bar under it
  /// (the portrait room's panel, A07.17 c3).
  final bool composerCollapsed;

  /// Whether the room details cover the panel.
  final bool detailsOpen;

  /// The tab and the chat list's place, kept while the page builds the
  /// panel anew (leaving the fullscreen, B09 c4).
  final RoomViewMemory? memory;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: (widget.memory?.chatTab ?? 0).clamp(0, 3),
    animationDuration: pureLiveTabTransitionDuration,
  )..addListener(_keepTab);

  void _keepTab() => widget.memory?.chatTab = _tabs.index;

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
        // B09 c9: the app's tab labels (U.1c c12: the badge, the keyboard
        // frame; a narrow column shrinks the tab instead of cutting it).
        tabs: [
          ListenableSelector<int>(
            // The feed tells of new lines at most once a frame (B08).
            listenable: widget.controller.chat,
            selector: () {
              final from = _unreadFrom;
              return from == null ? 0 : widget.controller.chat.added - from;
            },
            builder: (context, count, _) => _counted(
              label: i18n('danmaku_list'),
              count: count,
              key: const ValueKey('live-play-unread-count'),
              semantics: i18n('live_play_unread_count', args: {'count': '$count'}),
            ),
          ),
          ListenableSelector<int>(
            listenable: widget.controller,
            selector: () => widget.controller.superChats.length,
            builder: (context, count, _) =>
                _counted(label: i18n('super_chat'), count: count, key: const ValueKey('live-play-super-chat-count')),
          ),
          TabLabel(label: i18n('danmaku_settings')),
          TabLabel(label: i18n('block_list')),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          physics: const PureLivePageScrollPhysics(),
          children: [
            // U.2k-a: the local danmaku composer under the list (while the
            // local interaction is on).
            LocalComposerBelow(
              collapsed: widget.composerCollapsed,
              child: ChatList(
                controller: widget.controller,
                onTouched: _seen,
                memory: widget.memory,
                buttonInset: widget.composerCollapsed ? LocalComposerBelow.starInset : 0,
              ),
            ),
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
            DanmakuBlockManager(addKeyword: widget.controller.blockKeyword, blockedCount: widget.controller.blocked),
          ],
        ),
      ),
    ],
  );
}

/// A tab with [count] as its badge (U.2a change 9), keyed by [key] while
/// there is one.
Widget _counted({required String label, required int count, required Key key, String? semantics}) {
  if (count <= 0) return TabLabel(label: label);
  final tab = TabLabel(key: key, label: label, badge: count > 99 ? '99+' : '$count');
  return semantics == null ? tab : Semantics(label: semantics, child: tab);
}
