import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_text.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A local danmaku or gift in the chat list (U.2k-f, c10): a "本地" chip,
/// the platform badge chip with the level (each following its switch, as
/// sent), then "听众 · Pure Live：" and the words; a gift says
/// "送出 🌶 辣条 ×1" without the name again (L9). The name and the words take
/// the chat list's two roles (A08.10); with [showName] off the name and the
/// badge chip are left out and "本地" stays.
class LocalChatLine extends StatelessWidget {
  /// Creates the line of [message].
  const new({required this.message, this.showName = true, super.key});

  /// The local message.
  final LiveMessage message;

  /// Whether the line names its sender ("显示用户名").
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = ChatText.content(theme);
    final profile = LocalProfile.of(message);
    final gift = LocalGiftData.of(message);
    final chip = ChatChip.styleOf(theme);
    final badge = showName ? profile?.badgeLabel ?? '' : '';
    return Padding(
      key: const ValueKey('live-play-local-line'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ChatChip(
                key: const ValueKey('live-play-local-tag'),
                text: i18n('local_tag'),
                background: scheme.primaryContainer,
                style: chip?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
            if (badge.isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: ChatChip(
                  key: const ValueKey('live-play-local-badge'),
                  text: localEmojiText(badge),
                  background: Color(profile!.accent).withValues(alpha: 0.14),
                  style: localEmojiStyle(chip?.copyWith(color: localAccentInk(profile.accent, theme.brightness))),
                ),
              ),
            if (showName)
              TextSpan(
                text: '${profile?.displayName ?? message.userName}${ChatText.nameEnd}',
                style: ChatText.name(theme),
              ),
            if (gift == null)
              TextSpan(text: message.message, style: body)
            else ...[
              TextSpan(text: '${i18n('local_sent_gift')} ', style: body),
              TextSpan(text: '${localEmojiText(gift.emoji)} ', style: localEmojiStyle(body)),
              TextSpan(
                text: gift.name,
                style: body?.emphasis.copyWith(color: localGiftInk(gift.color, theme.brightness)),
              ),
              TextSpan(text: ' ×1', style: body),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small mark before a name in the chat list: "本地", the local badge,
/// and the PK partner's "对方" (E06.2 c3, the same block as "本地").
class ChatChip extends StatelessWidget {
  /// Creates the mark.
  const new({required this.text, required this.background, required this.style, super.key});

  /// The words.
  final String text;

  /// The block's colour.
  final Color background;

  /// The words' style.
  final TextStyle? style;

  /// The chip text style of [theme]: 12, semibold, 18 high.
  static TextStyle? styleOf(ThemeData theme) =>
      theme.textTheme.labelSmall?.emphasis.copyWith(fontSize: 12, height: 18 / 12);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 5),
    child: DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(9)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(text, style: style),
      ),
    ),
  );
}
