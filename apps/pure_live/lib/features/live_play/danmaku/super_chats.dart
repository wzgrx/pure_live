import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// A super chat's remaining time as `mm:ss` (3.x `SuperChatCard`: whole
/// seconds rounded up, at most two hours).
String superChatRemaining(LiveSuperChatMessage superChat, DateTime now) {
  final left = superChat.endTime.difference(now).inMilliseconds;
  final seconds = left <= 0 ? 0 : (left / 1000).ceil().clamp(0, 7200);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
}

/// The super chats on display (3.x `SuperChatPage`, docs/ui/compare/U.2e
/// c5–c7): newest first; one clock for the whole list redraws only the
/// times (3.x ran a timer per card); a platform without super chats says so
/// instead of "会显示在这里".
class SuperChatList extends StatefulWidget {
  /// Creates the list.
  const new({
    required this.messages,
    required this.now,
    this.platformName = '',
    this.platformHasSuperChats = true,
    super.key,
  });

  /// Messages, oldest first (as they arrived).
  final List<LiveSuperChatMessage> messages;

  /// The clock.
  final DateTime Function() now;

  /// The platform's name (the "none on this platform" line).
  final String platformName;

  /// Whether the platform has super chats at all (`LiveSite.hasSuperChats`).
  final bool platformHasSuperChats;

  @override
  State<SuperChatList> createState() => _SuperChatListState();
}

class _SuperChatListState extends State<SuperChatList> {
  late final ValueNotifier<DateTime> _clock = ValueNotifier(widget.now());
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SuperChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// One clock while there is something to count down (c6).
  void _sync() {
    if (widget.messages.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _clock.value = widget.now();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _clock.value = widget.now());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    if (messages.isEmpty) {
      return _SuperChatEmpty(
        subtitle: widget.platformHasSuperChats
            ? i18n('super_chat_empty_subtitle')
            : i18n('super_chat_unsupported', args: {'platform': widget.platformName}),
      );
    }
    return ListView.builder(
      key: const ValueKey('live-play-super-chats'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      // c5 (E2): the newest on top.
      itemBuilder: (context, index) {
        final superChat = messages[messages.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: SuperChatCard(key: ValueKey('super-chat-$index'), superChat: superChat, clock: _clock),
        );
      },
    );
  }
}

class _SuperChatEmpty extends StatelessWidget {
  const new({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      key: const ValueKey('live-play-super-chat-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.chatEmpty, size: 42, color: scheme.primary),
            const SizedBox(height: 16),
            Text(i18n('super_chat_empty_title'), style: theme.textTheme.titleLarge?.emphasis.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// One super chat (3.x `SuperChatCard`, U.2e c6): the head in the platform's
/// colour with the picture, name, price, "SC" and the time left; the
/// message in the second colour, selectable, a double tap copies it. Ink is
/// chosen by contrast, no shadow, a thin edge. Narrow (under 280) or with
/// larger system text the head stacks (3.x).
class SuperChatCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.superChat, required this.clock, super.key});

  /// The message.
  final LiveSuperChatMessage superChat;

  /// The list's clock.
  final ValueListenable<DateTime> clock;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: superChat.message));
    AppNavigator.toast(i18n('copied_to_clipboard'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = parsePlatformColor(superChat.backgroundColor) ?? scheme.primaryContainer;
    final bottom = parsePlatformColor(superChat.backgroundBottomColor) ?? scheme.surfaceContainerHighest;
    final ink = InkOnColor.contrastOn(top);
    final muted = InkOnColor.contrastMutedOn(top);
    final bodyInk = InkOnColor.contrastOn(bottom);
    const radius = Radius.circular(12);
    final price = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.superChatPrice, size: 16, color: LiveSemanticColors.superChatGold),
        const SizedBox(width: 3),
        Text(
          superChatPrice(superChat),
          key: const ValueKey('super-chat-price'),
          style: theme.textTheme.titleSmall?.emphasis.tabular.copyWith(fontSize: 15, color: ink),
        ),
      ],
    );
    final mark = DecoratedBox(
      decoration: BoxDecoration(color: ink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.superChatMark, size: 11, color: LiveSemanticColors.superChatGold),
            const SizedBox(width: 3),
            Text('SC', style: theme.textTheme.labelMedium?.emphasis.copyWith(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
    final time = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.superChatTime, size: 13, color: muted),
        const SizedBox(width: 3),
        ValueListenableBuilder<DateTime>(
          valueListenable: clock,
          builder: (context, now, _) => Text(
            superChatRemaining(superChat, now),
            key: const ValueKey('super-chat-time'),
            style: theme.textTheme.labelMedium?.regular.tabular.copyWith(fontSize: 12, color: ink),
          ),
        ),
      ],
    );
    final avatar = Container(
      padding: const EdgeInsets.all(1.8),
      decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
      child: CommonAvatar(avatarUrl: superChat.face, radius: 20.2, fallbackName: superChat.userName),
    );
    final name = Text(
      superChat.userName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyLarge?.emphasis.copyWith(color: ink, height: 1.2),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(14) > 14;
        final head = stacked
            ? Column(
                key: const ValueKey('super-chat-head-stacked'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      avatar,
                      const SizedBox(width: 10),
                      Expanded(child: name),
                    ],
                  ),
                  const SizedBox(height: 10),
                  price,
                  const SizedBox(height: 8),
                  mark,
                  const SizedBox(height: 6),
                  time,
                ],
              )
            : Row(
                children: [
                  avatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, const SizedBox(height: 5), price],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [mark, const SizedBox(height: 6), time]),
                ],
              );
        return DecoratedBox(
          key: const ValueKey('super-chat-card'),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(radius),
            border: Border.all(color: scheme.outlineVariant, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                key: const ValueKey('super-chat-head'),
                decoration: BoxDecoration(
                  color: top,
                  borderRadius: const BorderRadius.vertical(top: radius),
                ),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: head),
              ),
              DecoratedBox(
                key: const ValueKey('super-chat-body'),
                decoration: BoxDecoration(
                  color: bottom,
                  borderRadius: const BorderRadius.vertical(bottom: radius),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
                  child: GestureDetector(
                    onDoubleTap: () => unawaited(_copy()),
                    child: SelectableText(
                      superChat.message,
                      style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 14, height: 1.5, color: bodyInk),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
