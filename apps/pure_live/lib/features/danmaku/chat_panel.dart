import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart' show LiveIcon, LiveIcons, MessageView, Radii, Space;
import 'package:pure_live_app/features/danmaku/danmaku_text.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The chat panel of a room (spec/modules/danmaku.md §6): status and audience
/// line, pinned super chats, and the chat list that follows the newest line
/// until the user scrolls up.
class ChatPanel extends StatelessWidget {
  const new({
    required this.danmaku,
    required this.enabled,
    required this.onLine,
    this.live = true,
    this.onEnable,
    this.onOpenSettings,
    super.key,
  });

  /// The room's chat; null before the room is loaded.
  final RoomDanmaku? danmaku;

  /// "显示弹幕" is on (F-DM-01).
  final bool enabled;

  /// Whether the room is broadcasting; offline rooms have no chat.
  final bool live;

  /// Opens the actions of a line (copy, block).
  final ValueChanged<DanmakuEvent> onLine;

  /// Turns danmaku back on.
  final VoidCallback? onEnable;

  /// Opens the danmaku settings panel.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final danmaku = this.danmaku;
    if (!enabled) {
      return MessageView(
        icon: LiveIcons.danmaku,
        title: t.danmaku.off,
        message: t.danmaku.offHint,
        actionLabel: t.danmaku.turnOn,
        onAction: onEnable,
      );
    }
    if (!live || danmaku == null) {
      return MessageView(icon: LiveIcons.danmaku, title: t.danmaku.offlineNoDanmaku);
    }
    return Column(
      children: [
        _StatusBar(danmaku: danmaku, onOpenSettings: onOpenSettings),
        SuperChatStrip(superChats: danmaku.superChats),
        Expanded(
          child: ChatList(key: ObjectKey(danmaku), log: danmaku.chat, onLine: onLine),
        ),
        LocalChatInput(danmaku: danmaku),
      ],
    );
  }
}

/// F-LI-01: a line only this device shows, in the list and on the video.
/// Nothing reaches the platform or its account.
class LocalChatInput extends StatefulWidget {
  const new({required this.danmaku, super.key});

  final RoomDanmaku danmaku;

  @override
  State<LocalChatInput> createState() => _LocalChatInputState();
}

class _LocalChatInputState extends State<LocalChatInput> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.danmaku.sendLocal(_text.text)) _text.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s3, Space.s1, Space.s1, Space.s2),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('local-chat-input'),
            controller: _text,
            maxLength: RoomDanmaku.localMaxLength,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: t.danmaku.localHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        // The field's hint stays short enough for a 320 dp chat column; what
        // "local" means is on the button.
        IconButton(tooltip: t.danmaku.localSend, icon: const LiveIcon(LiveIcons.send), onPressed: _send),
      ],
    ),
  );
}

class _StatusBar extends StatelessWidget {
  const new({required this.danmaku, this.onOpenSettings});

  final RoomDanmaku danmaku;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(left: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AudienceText(audience: danmaku.audience, style: small),
              const SizedBox(width: Space.s2),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: danmaku.connection,
                  builder: (context, connection, _) {
                    final text = connectionText(connection);
                    return Row(
                      children: [
                        if (text != null)
                          Flexible(
                            child: Text(text, style: small, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        if (connection == ChatConnection.closed)
                          TextButton(onPressed: danmaku.reconnect, child: Text(t.danmaku.reconnect)),
                      ],
                    );
                  },
                ),
              ),
              if (onOpenSettings != null)
                IconButton(
                  tooltip: t.danmaku.settings,
                  icon: const LiveIcon(LiveIcons.tune, size: 20),
                  onPressed: onOpenSettings,
                ),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: danmaku.notice,
            builder: (context, notice, _) {
              final text = notice == null ? null : noticeText(notice);
              if (text == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: Space.s1, right: Space.s3),
                child: Text(text, style: small),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The room's audience figure (LST-6), rebuilt alone when it changes;
/// [fallback] is shown until the chat reports one.
class AudienceText extends StatelessWidget {
  const new({required this.audience, this.fallback, this.style, super.key});

  final ValueListenable<Map<AudienceKind, int>> audience;
  final (AudienceKind, int)? fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: audience,
    builder: (context, figures, _) {
      final shown = headlineAudience(figures) ?? fallback;
      if (shown == null) return const SizedBox.shrink();
      return Text(
        audienceText(shown.$1, shown.$2),
        style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      );
    },
  );
}

/// Pinned super chats above the list (LST-5), earliest end first.
class SuperChatStrip extends StatelessWidget {
  const new({required this.superChats, super.key});

  final ValueListenable<List<DanmakuSuperChat>> superChats;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: superChats,
    builder: (context, items, _) {
      if (items.isEmpty) return const SizedBox.shrink();
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 148),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.s3, 0, Space.s3, Space.s2),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.s1),
          itemBuilder: (context, index) => SuperChatCard(chat: items[index]),
        ),
      );
    },
  );
}

/// One super chat.
class SuperChatCard extends StatelessWidget {
  const new({required this.chat, super.key});

  final DanmakuSuperChat chat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = chat.backgroundColor == null ? scheme.tertiaryContainer : Color(0xFF000000 | chat.backgroundColor!);
    final ink = ThemeData.estimateBrightnessForColor(body) == Brightness.dark ? Colors.white : Colors.black;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: body, borderRadius: BorderRadius.circular(Radii.r2)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(priceText(chat.price), style: text.labelLarge!.copyWith(color: ink)),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(
                    chat.userName,
                    style: text.labelMedium!.copyWith(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(chat.text, style: text.bodyMedium!.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}

/// The chat list (LST-2): follows the newest line; when the user scrolls it
/// freezes on a snapshot and counts new lines (at most 9999) in a pill;
/// back at the bottom or on the pill it follows again. Updates are
/// throttled to one rebuild per 80 ms; a block while frozen removes only the
/// matching lines and keeps the position (LST-3).
class ChatList extends StatefulWidget {
  const new({required this.log, required this.onLine, super.key});

  final ChatLog log;
  final ValueChanged<DanmakuEvent> onLine;

  @override
  State<ChatList> createState() => ChatListState();
}

/// State of a [ChatList]; public for tests.
class ChatListState extends State<ChatList> {
  static const _throttle = Duration(milliseconds: 80);
  static const _bottomSlack = 8.0;

  final ScrollController _scroll = ScrollController();
  List<DanmakuEvent>? _frozen;
  int _unseen = 0;
  Timer? _timer;
  bool _pending = false;

  /// Whether the list follows the newest line.
  bool get following => _frozen == null;

  /// New lines since the list froze.
  int get unseen => _unseen;

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_onChange);
  }

  @override
  void didUpdateWidget(ChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.log, widget.log)) {
      oldWidget.log.removeListener(_onChange);
      widget.log.addListener(_onChange);
      _frozen = null;
      _unseen = 0;
    }
  }

  @override
  void dispose() {
    widget.log.removeListener(_onChange);
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange(ChatLogChange change) {
    if (change.local) {
      // LST-2: the user's own line shows at once and the list follows it.
      if (mounted) follow();
      return;
    }
    if (change.cleared) {
      _frozen = null;
      _unseen = 0;
      _rebuild();
      return;
    }
    final frozen = _frozen;
    if (frozen == null) {
      _rebuildSoon();
      return;
    }
    final removed = change.removed;
    if (removed != null) {
      frozen.removeWhere(removed);
      _rebuild();
    }
    if (change.appended > 0) {
      _unseen = math.min(9999, _unseen + change.appended);
      _rebuildSoon();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _rebuildSoon() {
    if (_timer != null) {
      _pending = true;
      return;
    }
    _rebuild();
    _timer = Timer(_throttle, () {
      _timer = null;
      if (_pending) {
        _pending = false;
        _rebuildSoon();
      }
    });
  }

  void _freeze() {
    if (_frozen != null) return;
    setState(() {
      _frozen = widget.log.lines.toList();
      _unseen = 0;
    });
  }

  /// Follows the newest line again.
  void follow() {
    setState(() {
      _frozen = null;
      _unseen = 0;
    });
    if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      // A user gesture starts: stop following so nothing moves under the finger.
      case ScrollStartNotification(dragDetails: _?):
        _freeze();
      case UserScrollNotification(:final direction) when direction != ScrollDirection.idle:
        _freeze();
      case ScrollEndNotification(:final metrics) when _frozen != null && metrics.pixels <= _bottomSlack:
        follow();
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _frozen;
    final count = frozen?.length ?? widget.log.length;
    DanmakuEvent lineAt(int index) => frozen != null ? frozen[count - 1 - index] : widget.log[count - 1 - index];
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _scroll,
            // Newest at the bottom, offset 0: new lines never move a
            // following list, and a frozen one shows a fixed snapshot.
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: Space.s1),
            itemCount: count,
            itemBuilder: (context, index) {
              final line = lineAt(index);
              return ChatLineTile(line: line, onTap: () => widget.onLine(line));
            },
          ),
        ),
        if (frozen != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.s2,
            child: Center(
              child: FilledButton.tonalIcon(
                icon: const LiveIcon(LiveIcons.scrollToLatest),
                label: Text(_unseen > 0 ? t.danmaku.newMessages(n: _unseen) : t.danmaku.jumpToLatest),
                onPressed: follow,
              ),
            ),
          ),
      ],
    );
  }
}

/// One line of the chat list: a chat ("name：text") or a gift.
class ChatLineTile extends StatelessWidget {
  const new({required this.line, required this.onTap, super.key});

  final DanmakuEvent line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.primary);
    final span = switch (line) {
      final DanmakuChat chat => TextSpan(
        children: [
          if (chat.medalName case final medal? when medal.isNotEmpty)
            TextSpan(
              text: '$medal${chat.medalLevel == null ? '' : ' ${chat.medalLevel}'}  ',
              style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.tertiary),
            ),
          TextSpan(
            text: t.danmaku.chatName(name: chat.userName),
            style: nameStyle,
          ),
          TextSpan(text: chat.text),
        ],
      ),
      final DanmakuGift gift => TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: LiveIcon(LiveIcons.gift, size: 16, color: theme.colorScheme.tertiary),
          ),
          const TextSpan(text: ' '),
          TextSpan(text: '${gift.userName} ', style: nameStyle),
          TextSpan(
            text: giftText(gift),
            style: TextStyle(color: theme.colorScheme.tertiary),
          ),
        ],
      ),
      _ => const TextSpan(),
    };
    return InkWell(
      onTap: onTap,
      onLongPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 3),
        child: Text.rich(span, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}
