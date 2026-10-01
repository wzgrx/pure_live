import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

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
    final name = message.userName.trim();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(name.isEmpty ? i18n('live_play_anonymous') : name),
                subtitle: Text(message.message, maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
              ListTile(
                key: const ValueKey('live-play-copy-message'),
                leading: const Icon(AppIcons.copy),
                title: Text(i18n('live_play_copy_message')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: message.message));
                  AppNavigator.toast(i18n('copied_to_clipboard'));
                },
              ),
              if (name.isNotEmpty)
                ListTile(
                  key: const ValueKey('live-play-block-user'),
                  leading: const Icon(AppIcons.blockUser),
                  title: Text(i18n('live_play_block_user', args: {'name': name})),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await widget.controller.blockUser(name);
                    AppNavigator.toast(i18n('live_play_user_blocked', args: {'name': name}));
                  },
                ),
              // 3.x had it; v4 lost it until U.2a.
              ListTile(
                key: const ValueKey('live-play-block-keyword'),
                leading: const Icon(AppIcons.blockKeyword),
                title: Text(i18n('block_danmaku_keyword')),
                subtitle: Text(message.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_blockKeyword(message.message));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _blockKeyword(String text) async {
    final keyword = await showDialog<String>(
      context: context,
      builder: (_) => _KeywordDialog(initialText: text),
    );
    if (keyword == null || keyword.trim().isEmpty) return;
    await widget.controller.blockKeyword(keyword);
    AppNavigator.toast(i18n('danmaku_keyword_blocked'));
  }

  @override
  Widget build(BuildContext context) {
    final display = watchSetting(ref, Settings.enableDanmakuDisplay);
    if (!display) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(i18n('danmaku_display_disabled_hint'), textAlign: TextAlign.center),
        ),
      );
    }
    final style = ChatListStyle.of(watchSetting(ref, Settings.danmakuListStyle));
    final lines = widget.controller.chat.lines;
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

/// One line of the chat list.
class ChatLineView extends StatelessWidget {
  /// Creates the line.
  const new({
    required this.line,
    this.style = ChatListStyle.compact,
    this.emotes = EmoteTable.empty,
    this.onActions,
    this.onCopy,
    super.key,
  });

  /// The line.
  final ChatLine line;

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
  Widget _card(BuildContext context, LiveMessage message, TextStyle? body) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = chatNameColor(message.color, theme.brightness) ?? scheme.onSurface;
    final name = message.userName.trim();
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
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 10),
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      ..._fans(theme, message),
                      if (name.isNotEmpty)
                        TextSpan(
                          text: '$name: ',
                          style: body?.emphasis.copyWith(color: scheme.onSurface),
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
