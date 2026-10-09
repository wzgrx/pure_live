import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_text.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/danmaku/message_panel.dart';
import 'package:pure_live/features/live_play/layout/room_view_memory.dart';
import 'package:pure_live/features/live_play/local_interaction/local_chat_line.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';
import 'package:pure_live/shared/images.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The contrast a name in a viewer's colour keeps on its background (WCAG
/// AA for body text).
const double chatNameContrast = 4.5;

/// The WCAG contrast ratio of [a] and [b] (1 to 21), both taken opaque.
double contrastRatio(Color a, Color b) {
  final la = a.withValues(alpha: 1).computeLuminance();
  final lb = b.withValues(alpha: 1).computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final Map<(int, int), Color> _readableNames = {};

/// The colour a viewer gave their message, for their name on [background]
/// (B08, audit B-5): the colour itself when it reads at [chatNameContrast],
/// else darker step by step on a light background (lighter on a dark one)
/// until it does. 3.x set every colour to one lightness, which left yellow
/// at 1.6:1 on white. Null for plain white or black messages, which take
/// the theme's colours.
Color? chatNameColor(LiveMessageColor color, Color background) {
  if (color == LiveMessageColor.white || (color.r == 0 && color.g == 0 && color.b == 0)) return null;
  final ground = background.withValues(alpha: 1);
  final key = ((color.r << 16) | (color.g << 8) | color.b, ground.toARGB32());
  if (_readableNames[key] case final known?) return known;
  if (_readableNames.length >= 512) _readableNames.clear();
  return _readableNames[key] = _readableOn(Color.fromARGB(255, color.r, color.g, color.b), ground);
}

Color _readableOn(Color color, Color background) {
  if (contrastRatio(color, background) >= chatNameContrast) return color;
  // Towards black or white, whichever the background stands further from
  // (one of them always reaches 4.5:1).
  final luminance = background.computeLuminance();
  final darker = (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05);
  final hsl = HSLColor.fromColor(color);
  var lightness = hsl.lightness;
  while (true) {
    lightness = (lightness + (darker ? -0.01 : 0.01)).clamp(0.0, 1.0);
    final next = hsl.withLightness(lightness).toColor();
    if (contrastRatio(next, background) >= chatNameContrast || lightness == 0 || lightness == 1) return next;
  }
}

/// The colour of [message]'s sender name on [background] (A08.10 G3, the
/// same rule on every line that names a sender): the platform's name colour
/// (B-14: 17LIVE), else the message's own colour (a coloured danmaku), each
/// made readable by [chatNameColor]; plain white or black ones take the
/// name role's secondary ink.
Color chatNameInk(LiveMessage message, Color background, ColorScheme scheme) =>
    chatNameColor(message.nameColor ?? message.color, background) ?? scheme.onSurfaceVariant;

/// The text a double tap copies (3.x: "用户名: 内容"). A local gift's words
/// already start with the name ("Pure Live 送出 辣条 ×1", A08.13); a
/// platform's gift is copied as its line says it, "名字: 送出 小心心 ×3"
/// (A08.11 c7).
String chatCopyText(LiveMessage message) {
  final name = chatSenderName(message);
  final words = chatMessageWords(message);
  return name.isEmpty ? words : '$name: $words';
}

/// What [message] says without its sender: a platform's gift in the gift
/// line's words ("送出 小心心 ×3", A08.11), anything else its text.
String chatMessageWords(LiveMessage message) => switch (message.gift) {
  final gift? when !message.isLocal => giftSentence(gift),
  _ => message.message,
};

/// The name shown before [message]'s words in its panel and copied with
/// them: none for a local gift, whose words name the sender (U.2k c10).
String chatSenderName(LiveMessage message) =>
    message.isLocal && message.type == LiveMessageType.gift ? '' : message.userName.trim();

/// Whether [line] has the long press, right click and double tap: a chat
/// line, a local gift's (A08.13; 3.x's local gift was a danmaku card) and a
/// platform's gift (A08.11 c7: copy, block the sender or the gift's name).
bool chatLineActionable(ChatLine line) =>
    line.message != null && (line.kind == ChatLineKind.chat || line.kind == ChatLineKind.gift);

/// The chat list (3.x `DanmakuListView`): follows new lines while at the
/// bottom; scrolled up it stays put and offers "N 条新弹幕" (3.x's button).
/// A long press or right click on a message opens copy and block; a double
/// tap copies it.
///
/// B08: it listens to the room's [ChatFeed] (at most once a frame) rather
/// than to the whole room. The list is reversed, the newest line at the
/// bottom as index 0, so following needs no jump, and a line already built
/// is not built again. From the moment a finger drags it, or it is moved
/// away from the bottom, it holds the lines it shows (3.x's snapshot: they
/// stay where they are, new ones are counted) and follows the feed again
/// when a scroll ends at the bottom or "N 条新弹幕" is pressed.
class ChatList extends ConsumerStatefulWidget {
  /// Creates the list.
  const new({required this.controller, this.onTouched, this.memory, this.buttonInset = 0, super.key});

  /// The room.
  final LiveRoomController controller;

  /// How much further from the right the new-messages button sits: clear of
  /// the composer's star on the list (A07.17 c3).
  final double buttonInset;

  /// Called when the user touches the list (clears the tab's count).
  final VoidCallback? onTouched;

  /// Where the list keeps the lines it held and its place when the page
  /// builds it anew (leaving the fullscreen, B09 c4); null: it starts at
  /// the newest line.
  final RoomViewMemory? memory;

  @override
  ConsumerState<ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<ChatList> {
  /// This close to the newest line the list is at the bottom.
  static const double _bottomSlack = 24;

  late final ScrollController _scroll;

  /// Lines added since the list last showed the newest one.
  final ValueNotifier<int> _unseen = ValueNotifier(0);

  /// Each line's widget, made once for the list's look and emoticons, with
  /// the message it was made for: the same widget is not built again when
  /// the list rebuilds (B08), and a line whose message was replaced (D07.1's
  /// combo count, A08.11 c4) is.
  final Expando<(ChatLineView, LiveMessage?)> _views = Expando('chat line views');

  /// The lines shown, oldest first: the feed's while following, else the
  /// ones that were shown when the list stopped following. A new batch
  /// rebuilds only the list, not the hint above it.
  final ValueNotifier<List<ChatLine>> _shown = ValueNotifier(const []);
  bool _following = true;
  int _seen = 0;
  int _removals = 0;
  EmoteTable _emotes = EmoteTable.empty;

  /// What the list shows of the room besides its lines.
  late _RoomFacts _facts;

  ChatFeed get _feed => widget.controller.chat;

  @override
  void initState() {
    super.initState();
    // B09 c4: back where it was left (the memory is the page's; the offset
    // is not left to the page storage, which keys by place in the tree).
    final held = widget.memory?.chatList;
    final restore = held != null && identical(held.feed, widget.controller.chat);
    _scroll = ScrollController(initialScrollOffset: restore ? held.offset : 0, keepScrollOffset: false)
      ..addListener(_onScroll);
    _attach(widget.controller, held: restore ? held : null);
  }

  @override
  void deactivate() {
    // Leaving the tree (the fullscreen, another layout, another tab): what
    // it held, for the list built in its place.
    final memory = widget.memory;
    if (memory != null) {
      memory.chatList = _following || !_scroll.hasClients
          ? null
          : ChatListMemory(feed: _feed, shown: _shown.value, seen: _seen, removals: _removals, offset: _scroll.offset);
    }
    super.deactivate();
  }

  @override
  void didUpdateWidget(ChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _detach(oldWidget.controller);
    _following = true;
    _attach(widget.controller);
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _scroll.dispose();
    _unseen.dispose();
    _shown.dispose();
    super.dispose();
  }

  void _attach(LiveRoomController controller, {ChatListMemory? held}) {
    controller.addListener(_onRoom);
    controller.chat.addListener(_onLines);
    if (held != null) {
      // Holding the lines it showed: removals since apply, new lines count.
      _following = false;
      _shown.value = held.shown;
      _seen = held.seen;
      _removals = held.removals;
      _onLines();
    } else {
      _shown.value = controller.chat.lines;
      _seen = controller.chat.added;
      _removals = controller.chat.removals;
      _unseen.value = 0;
    }
    _facts = _RoomFacts.of(controller);
    // The platform's bundled emoticons (M13.16), read once per platform.
    final library = ref.read(emoteLibraryProvider);
    final platform = controller.site.id;
    _emotes = library.tableOf(platform);
    if (_emotes.codes.isEmpty) {
      unawaited(
        library.load(platform).then((table) {
          if (mounted && identical(widget.controller, controller) && table.codes.isNotEmpty) {
            setState(() => _emotes = table);
          }
        }),
      );
    }
  }

  void _detach(LiveRoomController controller) {
    controller.removeListener(_onRoom);
    controller.chat.removeListener(_onLines);
  }

  /// The room changed: the list rebuilds only for what it shows of it.
  void _onRoom() {
    if (!mounted) return;
    final facts = _RoomFacts.of(widget.controller);
    if (facts != _facts) setState(() => _facts = facts);
  }

  /// The feed changed (at most once a frame).
  void _onLines() {
    if (!mounted) return;
    final feed = _feed;
    if (_following) {
      _shown.value = feed.lines;
      _seen = feed.added;
      return;
    }
    // Held: a merged gift shows its new count where it is (D07.1); taken-back
    // and blocked lines still go, also those the feed has already let go of
    // (3.x); new ones are counted.
    if (_shown.value.any((line) => line.replacement != null)) {
      _shown.value = [for (final line in _shown.value) line.latest];
    }
    if (feed.removals != _removals) {
      final tests = feed.removalsSince(_removals) ?? const [];
      _removals = feed.removals;
      _shown.value = [
        for (final line in _shown.value)
          if (!line.removed && !tests.any((test) => test(line))) line,
      ];
    }
    _unseen.value = feed.added - _seen;
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

  /// Reversed: 0 is the newest line.
  bool get _atBottom => !_scroll.hasClients || _scroll.position.pixels <= _bottomSlack;

  void _onScroll() {
    if (_following && !_atBottom) _hold();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      // A finger on the list: the lines under it stay where they are.
      _hold();
    } else if (notification is ScrollEndNotification && _atBottom) {
      _follow();
    }
    return false;
  }

  /// Stops following: the lines shown stay, new ones are counted.
  void _hold() {
    if (!_following) return;
    setState(() => _following = false);
    _removals = _feed.removals;
    _unseen.value = _feed.added - _seen;
  }

  /// Follows the feed again, from its newest line.
  void _follow() {
    if (_following) return;
    setState(() => _following = true);
    _shown.value = _feed.lines;
    _seen = _feed.added;
    _unseen.value = 0;
  }

  void _toBottom() {
    _follow();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  ChatLineView _view(ChatLine line, ChatListStyle style, {required bool names, required GiftLineRoom room}) {
    if (_views[line] case (final made, final message)
        when identical(message, line.message) &&
            made.style == style &&
            made.showName == names &&
            made.giftRoom == room &&
            identical(made.emotes, _emotes)) {
      return made;
    }
    final message = chatLineActionable(line) ? line.message : null;
    final view = ChatLineView(
      key: ValueKey(line.id),
      line: line,
      style: style,
      showName: names,
      emotes: _emotes,
      giftRoom: room,
      onActions: message == null ? null : () => unawaited(_actions(line)),
      onCopy: message == null ? null : () => unawaited(_copy(message)),
    );
    _views[line] = (view, line.message);
    return view;
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
  Widget? _nameHint() => switch (_facts.nameHint) {
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
    // A08.10: one switch for every layout's list (portrait, the phone held
    // sideways, the wide chat column are this one component).
    final names = watchSetting(ref, Settings.showChatNames);
    final hint = _nameHint();
    // B06 c1: the hint stays above the lines (and the empty states); the
    // list keeps its place in the tree, so its scroll position, when the
    // hint comes or goes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?hint,
        Expanded(
          key: const ValueKey('live-play-chat-body'),
          child: ValueListenableBuilder<List<ChatLine>>(
            valueListenable: _shown,
            builder: (context, lines, _) => _content(style, lines, names: names),
          ),
        ),
      ],
    );
  }

  Widget _content(ChatListStyle style, List<ChatLine> lines, {required bool names}) {
    if (!lines.any((line) => line.kind != ChatLineKind.system)) {
      // U.2e c2, U.2g c7: until the first message the list says where the
      // danmaku is (3.x: blank, or a few "系统消息" cards).
      final empty = _emptyState(lines);
      if (empty != null) return empty;
    }
    final count = lines.length;
    final scheme = Theme.of(context).colorScheme;
    final controller = widget.controller;
    final room = GiftLineRoom(platform: controller.site.id, streamer: controller.room.nick);
    return Listener(
      onPointerDown: (_) => widget.onTouched?.call(),
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView.builder(
              key: const ValueKey('live-play-chat'),
              controller: _scroll,
              // B08: the newest line is index 0 at the bottom; new lines
              // come in under the others without a jump.
              reverse: true,
              padding: EdgeInsets.symmetric(horizontal: style == ChatListStyle.card ? 6 : 16, vertical: 6),
              itemCount: count,
              // Nothing in a line is worth keeping off screen, and the
              // keep-alive wrappers were built again for every line on
              // every new batch (3.x turned them off too).
              addAutomaticKeepAlives: false,
              // A line keeps its element when lines come in under it.
              findChildIndexCallback: (key) {
                if (key is! ValueKey<int>) return null;
                final at = _indexOfId(lines, key.value);
                return at < 0 ? null : count - 1 - at;
              },
              itemBuilder: (context, index) => _view(lines[count - 1 - index], style, names: names, room: room),
            ),
          ),
          if (!_following)
            Positioned(
              right: 12 + widget.buttonInset,
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
                label: ValueListenableBuilder<int>(
                  valueListenable: _unseen,
                  builder: (context, unseen, _) => Text(
                    unseen > 0 ? i18n('danmaku_new_messages', args: {'count': '$unseen'}) : i18n('scroll_to_bottom'),
                  ),
                ),
                onPressed: _toBottom,
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the line with [id] is in [lines] (in id order), or -1.
int _indexOfId(List<ChatLine> lines, int id) {
  var low = 0;
  var high = lines.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final at = lines[middle].id;
    if (at == id) return middle;
    if (at < id) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return -1;
}

/// What the chat list shows of the room besides its lines: the empty
/// states and the Bilibili names hint. The room's other changes (audience,
/// volume, the player) leave the list alone.
@immutable
final class _RoomFacts {
  const new({required this.stage, required this.connection, required this.nameHint, required this.room});

  factory of(LiveRoomController controller) => _RoomFacts(
    stage: controller.stage,
    connection: controller.chatConnection,
    nameHint: controller.nameHint,
    // The offline state shows the room's notice.
    room: controller.stage == RoomStage.offline ? controller.room : null,
  );

  final RoomStage stage;
  final ChatConnection connection;
  final ChatNameHint nameHint;
  final LiveRoom? room;

  @override
  bool operator ==(Object other) =>
      other is _RoomFacts &&
      other.stage == stage &&
      other.connection == connection &&
      other.nameHint == nameHint &&
      identical(other.room, room);

  @override
  int get hashCode => Object.hash(stage, connection, nameHint, room == null ? null : identityHashCode(room));
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
            TextButton(
              key: const ValueKey('live-play-name-hint-login'),
              // The bar's ink: the primary colour falls under 4.5:1 on the
              // secondary container in the light theme (A05.1).
              style: TextButton.styleFrom(foregroundColor: scheme.onSecondaryContainer),
              onPressed: onAction,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the chat list.
///
/// A08.10: every line that names a sender draws the name and the content in
/// the two [ChatText] roles, in both styles; what comes before the name is
/// always in one order (G5): "本地" or "对方", the platform's badges, the fan
/// medal, the name. With [showName] off ("显示用户名") the sender's name and
/// what belongs to them (badges, fan medal, avatar) are left out and the
/// line starts with what was said; "本地" and "对方" stay, they are about
/// the message.
class ChatLineView extends StatelessWidget {
  /// Creates the line.
  const new({
    required this.line,
    this.style = ChatListStyle.compact,
    this.showName = true,
    this.emotes = EmoteTable.empty,
    this.onActions,
    this.onCopy,
    this.tag,
    this.giftRoom = GiftLineRoom.none,
    super.key,
  });

  /// The line.
  final ChatLine line;

  /// A mark before the name (the local interaction's "本地", U.2k).
  final Widget? tag;

  /// Compact line or card.
  final ChatListStyle style;

  /// Whether the line names its sender (the `showChatNames` setting).
  final bool showName;

  /// The platform's emoticons.
  final EmoteTable emotes;

  /// Opens copy and block (long press, right click).
  final VoidCallback? onActions;

  /// Copies the message (double tap).
  final VoidCallback? onCopy;

  /// The room's platform and streamer, for a gift line (A08.11).
  final GiftLineRoom giftRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge?.regular;
    // U.2k c10: a local danmaku or gift has its own line; both keep the
    // long press, right click and double tap (3.x; the gift's since A08.13).
    if (line.message case final message? when message.isLocal) {
      final local = LocalChatLine(message: message, showName: showName);
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
        // A08.11: one gift line for every platform (gift_line.dart).
        return giftLineOf(
          line,
          style: style,
          showName: showName,
          room: giftRoom,
          lead: _lead(Theme.of(context), line.message!),
          onActions: onActions,
          onCopy: onCopy,
        );
      case ChatLineKind.superChat:
        final superChat = line.superChat!;
        final background = parsePlatformColor(superChat.backgroundColor) ?? scheme.tertiaryContainer;
        final ink = InkOnColor.on(background);
        final name = showName ? superChat.userName.trim() : '';
        return Container(
          key: const ValueKey('live-play-super-chat-line'),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
          child: Text.rich(
            TextSpan(
              children: [
                // The card's own ink: the name role's weight, not its colour.
                if (name.isNotEmpty) TextSpan(text: '$name · ', style: ChatText.name(theme, ink)),
                TextSpan(text: '${superChatPrice(superChat)}${ChatText.nameEnd}', style: ChatText.name(theme, ink)),
                TextSpan(
                  text: superChat.message,
                  style: body?.copyWith(color: ink),
                ),
              ],
            ),
          ),
        );
      case ChatLineKind.chat:
        final message = line.message!;
        final text = style == ChatListStyle.card ? _card(context, message) : _compact(context, message);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onActions,
          onSecondaryTap: onActions,
          onDoubleTap: onCopy,
          child: text,
        );
    }
  }

  /// G5: what comes before the name, in one order on both styles.
  List<InlineSpan> _lead(ThemeData theme, LiveMessage message) => [
    if (tag case final mark?) ...[chatInline(mark), const TextSpan(text: ' ')],
    // B-16 (E06.2 c3): a PK partner room's viewer, in the block of "本地".
    if (message.isFromOtherRoom)
      chatInline(
        ChatChip(
          key: const ValueKey('live-play-chat-other-room'),
          text: i18n('danmaku_other_room'),
          background: theme.colorScheme.tertiaryContainer,
          style: ChatChip.styleOf(theme)?.copyWith(color: theme.colorScheme.onTertiaryContainer),
        ),
      ),
    if (showName) ...[..._badges(message), ..._fans(theme, message)],
  ];

  /// B-14 (E06.2 c2): the platform's badges before the name, in its order.
  List<InlineSpan> _badges(LiveMessage message) => [
    for (final (index, badge) in message.badges.indexed)
      if (badge.url.trim().isNotEmpty)
        chatInline(ChatBadge(key: ValueKey('live-play-chat-badge-$index'), url: badge.url.trim())),
  ];

  /// B06 c2: the fan medal ("粉丝牌 等级"), in the same block as the other
  /// marks (A08.10 G5; it was a highlighted run of text).
  List<InlineSpan> _fans(ThemeData theme, LiveMessage message) {
    final fans = message.fansName.trim();
    if (fans.isEmpty) return const [];
    final level = message.fansLevel.trim();
    final scheme = theme.colorScheme;
    return [
      chatInline(
        ChatChip(
          key: const ValueKey('live-play-chat-fans'),
          text: level.isEmpty ? fans : '$fans $level',
          background: scheme.primary,
          style: ChatChip.styleOf(theme)?.copyWith(color: scheme.onPrimary),
        ),
      ),
    ];
  }

  /// The name ("用户名：") in the name role, or nothing.
  List<InlineSpan> _name(ThemeData theme, LiveMessage message, Color background) {
    final name = message.userName.trim();
    if (!showName || name.isEmpty) return const [];
    return [
      TextSpan(
        text: '$name${ChatText.nameEnd}',
        style: ChatText.name(theme, chatNameInk(message, background, theme.colorScheme)),
      ),
    ];
  }

  /// What was said, with the platform's emoticons, in the content role.
  InlineSpan _words(ThemeData theme) => chatInline(
    EmoteText(line.segments(emotes), style: ChatText.content(theme)),
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
  );

  /// U.2a change 11, A08.10: "用户名：" in the name role (readable on the
  /// panel's surface, B08), then the message in the content role.
  Widget _compact(BuildContext context, LiveMessage message) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('live-play-chat-line'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [..._lead(theme, message), ..._name(theme, message, theme.colorScheme.surface), _words(theme)],
        ),
      ),
    );
  }

  /// 3.x `DanmakuItem`, on the theme's surfaces instead of fixed white.
  /// With the sender's avatar (B06 c2: Bilibili's `user.base.face`) the
  /// avatar takes the dot's place. The dot keeps the message's colour; the
  /// name and the words take the same roles as the compact line (A08.10).
  Widget _card(BuildContext context, LiveMessage message) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ground = scheme.surfaceContainerLowest;
    final dot = chatNameColor(message.color, ground) ?? scheme.onSurface;
    final name = message.userName.trim();
    final avatar = switch (message.data) {
      DanmakuSender(:final avatar) when showName && avatar.isNotEmpty => avatar,
      _ => '',
    };
    return Padding(
      key: const ValueKey('live-play-chat-card'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ground,
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
                  TextSpan(children: [..._lead(theme, message), ..._name(theme, message, ground), _words(theme)]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A badge the platform shows before a sender's name (B-14: 17LIVE's
/// prefix, attendance and level pictures; E06.2 c2): [height] high at its
/// own width, through the app's image cache. Nothing, and no gap, while it
/// loads or when it fails.
class ChatBadge extends StatelessWidget {
  /// Creates the badge of [url].
  const new({required this.url, super.key});

  /// The picture's address.
  final String url;

  /// The badge's height.
  static const double height = 16;

  /// The gap after a badge that loaded.
  static const double gap = 4;

  @override
  Widget build(BuildContext context) {
    final decoded = (height * MediaQuery.devicePixelRatioOf(context)).round();
    return Image(
      image: ResizeImage(chatBadgeImage(url), height: decoded),
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, _) => frame == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(right: gap),
              child: child,
            ),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// The picture of a chat badge at [url]: the app's image cache (its proxy
/// and headers) when it is installed, else a plain request.
ImageProvider chatBadgeImage(String url) => switch (AppImageCache.manager) {
  final manager? => CachedNetworkImageProvider(url, cacheManager: manager, headers: networkImageHeaders(url)),
  null => NetworkImage(url, headers: networkImageHeaders(url)),
};

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

/// The chat list's state before its first message, and with the danmaku
/// display off (docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页 c2, c3): an icon or a spinner, a line,
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

/// The chat area of a room that is not on air (docs/A-界面设计/A07-直播间界面/A07.7-直播间的状态 c7): the
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
                    platformNotice(notice),
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
