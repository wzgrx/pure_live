import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/local_interaction/local_chat_line.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The look of the chat list (the `danmakuListStyle` setting, U.2a choice
/// A): compact lines by default, 3.x's cards on request.
enum ChatListStyle {
  /// One line per message: "用户名：" in a secondary colour (or the message's
  /// own colour), then the message.
  compact,

  /// 3.x `DanmakuItem`: a card per message with a coloured dot.
  card;

  /// The style stored as [name], compact for anything else.
  static ChatListStyle of(String name) => name == card.name ? card : compact;
}

/// The colour a viewer gave their message, made readable on the theme's
/// surface (3.x lifted the lightness the same way for its dots); null for
/// plain white or black messages, which take the theme's colours.
Color? chatNameColor(LiveMessageColor color, Brightness brightness) {
  if (color == LiveMessageColor.white || (color.r == 0 && color.g == 0 && color.b == 0)) return null;
  final hsl = HSLColor.fromColor(Color.fromARGB(255, color.r, color.g, color.b));
  return hsl.withLightness(brightness == Brightness.dark ? 0.72 : 0.42).toColor();
}

/// The text a double tap copies (3.x: "用户名: 内容").
String chatCopyText(LiveMessage message) {
  final name = message.userName.trim();
  return name.isEmpty ? message.message : '$name: ${message.message}';
}

/// The chat list (3.x `DanmakuListView`): follows new lines while at the
/// bottom; scrolled up it stays put and offers "N 条新弹幕" (3.x's button).
/// A long press or right click on a message opens copy and block; a double
/// tap copies it.
class ChatList extends ConsumerStatefulWidget {
  /// Creates the list.
  const new({required this.controller, this.onTouched, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Called when the user touches the list (clears the tab's count).
  final VoidCallback? onTouched;

  @override
  ConsumerState<ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<ChatList> {
  final ScrollController _scroll = ScrollController();
  bool _following = true;
  int _seen = 0;
  EmoteTable _emotes = EmoteTable.empty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.controller.addListener(_onChange);
    _seen = widget.controller.chat.added;
    // The platform's bundled emoticons (M13.16), read once per platform.
    final library = ref.read(emoteLibraryProvider);
    final platform = widget.controller.site.id;
    _emotes = library.tableOf(platform);
    if (_emotes.codes.isEmpty) {
      unawaited(
        library.load(platform).then((table) {
          if (mounted && table.codes.isNotEmpty) setState(() => _emotes = table);
        }),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _scroll.dispose();
    super.dispose();
  }

  /// What the list says before its first message, or null for the list.
  Widget? _emptyState(List<ChatLine> lines) {
    final controller = widget.controller;
    if (controller.stage == RoomStage.offline) return RoomNoticeState(room: controller.room);
    final last = lines.isEmpty ? null : lines.last.text;
    return switch (controller.chatConnection) {
      ChatConnection.idle => null,
      ChatConnection.connecting => ChatListState(
        key: const ValueKey('live-play-chat-connecting'),
        busy: true,
        title: last ?? i18n('connect_danmaku_server'),
      ),
      ChatConnection.connected => ChatListState(
        key: const ValueKey('live-play-chat-quiet'),
        icon: AppIcons.chatEmpty,
        title: i18n('live_play_chat_empty'),
        subtitle: i18n('live_play_chat_empty_desc'),
      ),
      ChatConnection.timedOut => ChatListState(
        key: const ValueKey('live-play-chat-timeout'),
        icon: AppIcons.danmakuTimeout,
        title: i18n('live_play_chat_timeout'),
        subtitle: i18n('live_play_chat_timeout_desc'),
        action: i18n('live_play_chat_reconnect'),
        actionIcon: AppIcons.refresh,
        onAction: () => unawaited(controller.reconnectDanmaku()),
      ),
      ChatConnection.failed => ChatListState(
        key: const ValueKey('live-play-chat-failed'),
        icon: AppIcons.danmakuTimeout,
        title: last ?? i18n('live_play_danmaku_connect_failed'),
        action: i18n('live_play_chat_reconnect'),
        actionIcon: AppIcons.refresh,
        onAction: () => unawaited(controller.reconnectDanmaku()),
      ),
      ChatConnection.unsupported => ChatListState(
        key: const ValueKey('live-play-chat-unsupported'),
        icon: AppIcons.danmakuUnavailable,
        title: i18n(
          'live_play_chat_unsupported',
          args: {'platform': platformName(controller.site.id, fallback: controller.site.name)},
        ),
        subtitle: i18n('live_play_chat_unsupported_desc'),
      ),
    };
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _following) setState(() => _following = atBottom);
    if (atBottom) _seen = widget.controller.chat.added;
  }

  void _onChange() {
    if (!mounted) return;
    if (_following) {
      _seen = widget.controller.chat.added;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _following) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    setState(() {});
  }

  void _toBottom() {
    setState(() => _following = true);
    _seen = widget.controller.chat.added;
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _copy(LiveMessage message) async {
    await Clipboard.setData(ClipboardData(text: chatCopyText(message)));
    AppNavigator.toast(i18n('copied_to_clipboard'));
  }

  Future<void> _actions(ChatLine line) async {
    final message = line.message;
    if (message == null) return;
    await showRoomMessageActions(context, widget.controller, message);
  }

  /// B06 c1: Bilibili's names for a guest, or for an expired login, with
  /// the way to log in; null when there is nothing to say.
  Widget? _nameHint() => switch (widget.controller.nameHint) {
    ChatNameHint.none => null,
    ChatNameHint.guest => ChatNameHintBar(
      text: i18n('bilibili_guest_names_hidden'),
      action: i18n('live_play_go_login'),
      onAction: () => unawaited(AppNavigator.toBiliBiliLogin()),
    ),
    ChatNameHint.loginExpired => ChatNameHintBar(
      text: i18n('bilibili_login_expired_short'),
      action: i18n('bilibili_login_again'),
      onAction: () => unawaited(AppNavigator.toBiliBiliLogin()),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final display = watchSetting(ref, Settings.enableDanmakuDisplay);
    if (!display) {
      // U.2e c3: 3.x only said where else to go; the switch is here now.
      return ChatListState(
        key: const ValueKey('live-play-chat-display-off'),
        icon: AppIcons.danmakuUnavailable,
        title: i18n('danmaku_display_disabled_title'),
        subtitle: i18n('danmaku_display_disabled_desc'),
        action: i18n('danmaku_display_enable'),
        onAction: () => unawaited(ref.read(storeProvider).settings.set(Settings.enableDanmakuDisplay, true)),
      );
    }
    final style = ChatListStyle.of(watchSetting(ref, Settings.danmakuListStyle));
    final hint = _nameHint();
    // B06 c1: the hint stays above the lines (and the empty states); the
    // list keeps its place in the tree, so its scroll position, when the
    // hint comes or goes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?hint,
        Expanded(key: const ValueKey('live-play-chat-body'), child: _content(style)),
      ],
    );
  }

  Widget _content(ChatListStyle style) {
    final lines = widget.controller.chat.lines;
    if (!lines.any((line) => line.kind != ChatLineKind.system)) {
      // U.2e c2, U.2g c7: until the first message the list says where the
      // danmaku is (3.x: blank, or a few "系统消息" cards).
      final empty = _emptyState(lines);
      if (empty != null) return empty;
    }
    final unseen = widget.controller.chat.added - _seen;
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => widget.onTouched?.call(),
      child: Stack(
        children: [
          ListView.builder(
            key: const ValueKey('live-play-chat'),
            controller: _scroll,
            padding: EdgeInsets.symmetric(horizontal: style == ChatListStyle.card ? 6 : 16, vertical: 6),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final message = line.kind == ChatLineKind.chat ? line.message : null;
              return ChatLineView(
                key: ValueKey(line.id),
                line: line,
                style: style,
                emotes: _emotes,
                onActions: message == null ? null : () => unawaited(_actions(line)),
                onCopy: message == null ? null : () => unawaited(_copy(message)),
              );
            },
          ),
          if (!_following)
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.icon(
                key: const ValueKey('live-play-new-messages'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(AppIcons.newMessages, size: 18),
                label: Text(
                  unseen > 0 ? i18n('danmaku_new_messages', args: {'count': '$unseen'}) : i18n('scroll_to_bottom'),
                ),
                onPressed: _toBottom,
              ),
            ),
        ],
      ),
    );
  }
}

/// The line above the chat list about Bilibili's names (B06 c1): an info
/// mark, [text] and a [action] button that logs in.
class ChatNameHintBar extends StatelessWidget {
  /// Creates the line.
  const new({required this.text, required this.action, required this.onAction, super.key});

  /// What happens to the names.
  final String text;

  /// The button's label.
  final String action;

  /// Opens the login.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('live-play-name-hint'),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Icon(AppIcons.info, size: 16, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(key: const ValueKey('live-play-name-hint-login'), onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

/// One line of the chat list.
class ChatLineView extends StatelessWidget {
  /// Creates the line.
  const new({
    required this.line,
    this.style = ChatListStyle.compact,
    this.emotes = EmoteTable.empty,
    this.onActions,
    this.onCopy,
    this.tag,
    super.key,
  });

  /// The line.
  final ChatLine line;

  /// A mark before the name (the local interaction's "本地", U.2k).
  final Widget? tag;

  /// Compact line or card.
  final ChatListStyle style;

  /// The platform's emoticons.
  final EmoteTable emotes;

  /// Opens copy and block (long press, right click).
  final VoidCallback? onActions;

  /// Copies the message (double tap).
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge?.regular;
    // U.2k c10: a local danmaku or gift has its own line; a local danmaku
    // keeps the long press, right click and double tap (3.x).
    if (line.message case final message? when message.isLocal) {
      final local = LocalChatLine(message: message);
      if (line.kind != ChatLineKind.chat) return local;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onActions,
        onSecondaryTap: onActions,
        onDoubleTap: onCopy,
        child: local,
      );
    }
    switch (line.kind) {
      case ChatLineKind.system:
        // U.2a change 10: a small grey label in the middle.
        return Padding(
          key: const ValueKey('live-play-system-line'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.regular.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        );
      case ChatLineKind.notice:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              Icon(AppIcons.chatNotice, size: 16, color: scheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(line.text, style: body?.copyWith(color: scheme.onSecondaryContainer)),
              ),
            ],
          ),
        );
      case ChatLineKind.gift:
        final message = line.message!;
        final name = message.userName.trim();
        return Padding(
          key: const ValueKey('live-play-gift-line'),
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 6),
                child: Icon(AppIcons.chatGift, size: 15, color: scheme.tertiary),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (name.isNotEmpty)
                        TextSpan(
                          text: '$name ',
                          style: body?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      TextSpan(
                        text: line.text,
                        style: body?.copyWith(color: scheme.tertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case ChatLineKind.superChat:
        final superChat = line.superChat!;
        final background = parsePlatformColor(superChat.backgroundColor) ?? scheme.tertiaryContainer;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
          child: Text(
            '${superChat.userName} · ${superChatPrice(superChat)}：${superChat.message}',
            style: body?.copyWith(color: InkOnColor.on(background)),
          ),
        );
      case ChatLineKind.chat:
        final message = line.message!;
        final text = style == ChatListStyle.card ? _card(context, message, body) : _compact(context, message, body);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onActions,
          onSecondaryTap: onActions,
          onDoubleTap: onCopy,
          child: text,
        );
    }
  }

  List<InlineSpan> _tag() => [
    if (tag case final mark?) ...[
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: mark),
      const TextSpan(text: ' '),
    ],
  ];

  List<InlineSpan> _fans(ThemeData theme, LiveMessage message) {
    if (message.fansName.trim().isEmpty) return const [];
    final scheme = theme.colorScheme;
    return [
      TextSpan(
        text: ' ${message.fansName}${message.fansLevel.isEmpty ? '' : ' ${message.fansLevel}'} ',
        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimary, backgroundColor: scheme.primary),
      ),
      const TextSpan(text: ' '),
    ];
  }

  /// U.2a change 11: "用户名：" in the secondary colour (or the message's own
  /// colour), the message in the normal colour.
  Widget _compact(BuildContext context, LiveMessage message, TextStyle? body) {
    final theme = Theme.of(context);
    final name = message.userName.trim();
    final nameColor = chatNameColor(message.color, theme.brightness) ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      key: const ValueKey('live-play-chat-line'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            ..._tag(),
            ..._fans(theme, message),
            if (name.isNotEmpty)
              TextSpan(
                text: '$name：',
                style: body?.copyWith(color: nameColor),
              ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: EmoteText(
                chatSegments(message, emotes),
                style: body?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3.x `DanmakuItem`, on the theme's surfaces instead of fixed white.
  /// With the sender's avatar (B06 c2: Bilibili's `user.base.face`) the
  /// avatar takes the dot's place and the name takes its colour.
  Widget _card(BuildContext context, LiveMessage message, TextStyle? body) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colour = chatNameColor(message.color, theme.brightness);
    final dot = colour ?? scheme.onSurface;
    final name = message.userName.trim();
    final avatar = switch (message.data) {
      DanmakuSender(:final avatar) when avatar.isNotEmpty => avatar,
      _ => '',
    };
    return Padding(
      key: const ValueKey('live-play-chat-card'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (avatar.isEmpty)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                )
              else
                Padding(
                  key: const ValueKey('live-play-chat-avatar'),
                  padding: const EdgeInsets.only(right: 8),
                  child: CommonAvatar(avatarUrl: avatar, radius: 12, fallbackName: name),
                ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      ..._tag(),
                      ..._fans(theme, message),
                      if (name.isNotEmpty)
                        TextSpan(
                          text: '$name: ',
                          style: body?.emphasis.copyWith(
                            color: avatar.isEmpty ? scheme.onSurface : colour ?? scheme.onSurface,
                          ),
                        ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: EmoteText(chatSegments(message, emotes), style: body?.copyWith(color: scheme.onSurface)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The room's actions on [message]: the chat list's long press and a tap or
/// long press on a flying danmaku (F.2b) open the same sheet. Blocking a
/// viewer or a keyword goes to [controller]; the keyword box opens over
/// [context] after the sheet closes.
Future<void> showRoomMessageActions(BuildContext context, LiveRoomController controller, LiveMessage message) =>
    showChatMessageActions(
      context,
      message,
      onBlockUser: (name) async {
        await controller.blockUser(name);
        AppNavigator.toast(i18n('live_play_user_blocked', args: {'name': name}));
      },
      onBlockKeyword: (text) => unawaited(_blockKeyword(context, controller, text)),
    );

Future<void> _blockKeyword(BuildContext context, LiveRoomController controller, String text) async {
  if (!context.mounted) return;
  final keyword = await showDialog<String>(
    context: context,
    builder: (_) => _KeywordDialog(initialText: text),
  );
  if (keyword == null || keyword.trim().isEmpty) return;
  await controller.blockKeyword(keyword);
  AppNavigator.toast(i18n('danmaku_keyword_blocked'));
}

/// The sheet of a long-pressed message (3.x `DanmakuMessageActions`,
/// docs/ui/compare/U.2f 长按弹幕): "弹幕" and ✕, the message in a card (the
/// name in its colour), then copy, block the viewer and block a keyword,
/// each saying what it does. "屏蔽关键词…" opens the keyword box filled with
/// the message, to cut down to the word. A masked name (a Bilibili guest's
/// `观***`, [isMaskedViewerName]) has no "屏蔽此用户" (B01 c1).
Future<void> showChatMessageActions(
  BuildContext context,
  LiveMessage message, {
  required Future<void> Function(String name) onBlockUser,
  required void Function(String text) onBlockKeyword,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // U.2f: "弹幕" and ✕ head the sheet instead of a handle.
  showDragHandle: false,
  builder: (sheetContext) {
    final theme = Theme.of(sheetContext);
    final scheme = theme.colorScheme;
    final name = message.userName.trim();
    final body = theme.textTheme.bodyLarge?.regular;
    final hint = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    void close() => Navigator.of(sheetContext).pop();
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('live-play-message-sheet'),
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(child: Text(i18n('danmaku'), style: theme.textTheme.titleMedium?.emphasis)),
                  IconButton(
                    key: const ValueKey('live-play-message-close'),
                    tooltip: i18n('close'),
                    onPressed: close,
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: DecoratedBox(
                key: const ValueKey('live-play-message-card'),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (name.isNotEmpty)
                          TextSpan(
                            text: '$name：',
                            style: body?.copyWith(
                              color: chatNameColor(message.color, theme.brightness) ?? scheme.onSurfaceVariant,
                            ),
                          ),
                        TextSpan(
                          text: message.message,
                          style: body?.copyWith(color: scheme.onSurface),
                        ),
                      ],
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            ListTile(
              key: const ValueKey('live-play-copy-message'),
              leading: const Icon(AppIcons.copy),
              title: Text(i18n('copy')),
              onTap: () async {
                close();
                // 3.x copied "用户名: 内容".
                await Clipboard.setData(ClipboardData(text: chatCopyText(message)));
                AppNavigator.toast(i18n('copied_to_clipboard'));
              },
            ),
            // 3.x: a local danmaku cannot block its sender. B-1: nor can a
            // masked name, which stands for many viewers.
            if (name.isNotEmpty && !message.isLocal && !isMaskedViewerName(name))
              ListTile(
                key: const ValueKey('live-play-block-user'),
                leading: const Icon(AppIcons.blockUser),
                title: Text(i18n('live_play_block_viewer')),
                subtitle: Text(i18n('live_play_block_viewer_desc', args: {'name': name}), style: hint),
                onTap: () {
                  close();
                  unawaited(onBlockUser(name));
                },
              ),
            ListTile(
              key: const ValueKey('live-play-block-keyword'),
              leading: const Icon(AppIcons.blockKeyword),
              title: Text(i18n('live_play_block_word')),
              subtitle: Text(i18n('live_play_block_word_desc'), style: hint),
              onTap: () {
                close();
                onBlockKeyword(message.message);
              },
            ),
          ],
        ),
      ),
    );
  },
);

/// A colour the platform sent as `#RRGGBB` or `AARRGGBB`, or null.
Color? parsePlatformColor(String text) {
  final hex = text.trim().replaceFirst('#', '');
  final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return value == null ? null : Color(value);
}

/// The price as shown: the platform's text, else the number (3.x showed
/// `￥price`, though only Bilibili and Douyu use yuan).
String superChatPrice(LiveSuperChatMessage superChat) =>
    superChat.priceText.trim().isNotEmpty ? superChat.priceText.trim() : '￥${superChat.price}';

class _KeywordDialog extends StatefulWidget {
  const new({required this.initialText});

  final String initialText;

  @override
  State<_KeywordDialog> createState() => _KeywordDialogState();
}

class _KeywordDialogState extends State<_KeywordDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(i18n('block_danmaku_keyword')),
    content: TextField(
      key: const ValueKey('live-play-keyword-input'),
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(hintText: i18n('please_enter_keyword')),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('live-play-keyword-confirm'),
        onPressed: () => Navigator.of(context).pop(_text.text.trim()),
        child: Text(i18n('confirm')),
      ),
    ],
  );
}

/// The chat list's state before its first message, and with the danmaku
/// display off (docs/ui/compare/U.2e c2, c3): an icon or a spinner, a line,
/// a reason and at most one button.
class ChatListState extends StatelessWidget {
  /// Creates the state.
  const new({
    required this.title,
    this.subtitle,
    this.icon,
    this.busy = false,
    this.action,
    this.actionIcon,
    this.onAction,
    super.key,
  });

  /// The line.
  final String title;

  /// The reason, or what still works.
  final String? subtitle;

  /// The icon.
  final IconData? icon;

  /// A spinner instead of the icon.
  final bool busy;

  /// The button's words.
  final String? action;

  /// The button's icon.
  final IconData? actionIcon;

  /// The button.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 3))
            else if (icon != null)
              Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              key: const ValueKey('live-play-chat-state-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.emphasis.copyWith(fontSize: 15, color: scheme.onSurface),
            ),
            if (subtitle case final text?) ...[
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
            ],
            if (action != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                key: const ValueKey('live-play-chat-state-action'),
                onPressed: onAction,
                icon: actionIcon == null ? null : Icon(actionIcon, size: 18),
                label: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The chat area of a room that is not on air (docs/ui/compare/U.2g c7): the
/// streamer's announcement when the platform gave one (folded to three
/// lines, "展开" shows it all), and "开播后这里显示弹幕".
class RoomNoticeState extends StatefulWidget {
  /// Creates the area for [room].
  const new({required this.room, super.key});

  /// The room.
  final LiveRoom room;

  @override
  State<RoomNoticeState> createState() => _RoomNoticeStateState();
}

class _RoomNoticeStateState extends State<RoomNoticeState> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notice = (widget.room.notice ?? widget.room.introduction ?? '').trim();
    return ListView(
      key: const ValueKey('live-play-chat-offline'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        if (notice.isNotEmpty) ...[
          DecoratedBox(
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n('live_play_info_notice'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notice,
                    key: const ValueKey('live-play-offline-notice'),
                    maxLines: _open ? null : 3,
                    overflow: _open ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 14, height: 1.5),
                  ),
                  if (!_open)
                    TextButton(
                      key: const ValueKey('live-play-offline-notice-more'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 40)),
                      onPressed: () => setState(() => _open = true),
                      child: Text(i18n('live_play_details_expand')),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Text(
                i18n('live_play_chat_after_live'),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
