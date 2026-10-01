import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A local danmaku or gift in the chat list (U.2k-f, c10): a "本地" chip,
/// the platform badge chip with the level (each following its switch, as
/// sent), then "听众 · Pure Live：" and the words; a gift says
/// "送出 🌶 辣条 ×1" without the name again (L9).
class LocalChatLine extends StatelessWidget {
  /// Creates the line of [message].
  const new({required this.message, super.key});

  /// The local message.
  final LiveMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge?.regular;
    final profile = LocalProfile.of(message);
    final gift = LocalGiftData.of(message);
    final chip = theme.textTheme.labelSmall?.emphasis.copyWith(fontSize: 11, height: 18 / 11);
    final badge = profile?.badgeLabel ?? '';
    return Padding(
      key: const ValueKey('live-play-local-line'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _Chip(
                key: const ValueKey('live-play-local-tag'),
                text: i18n('local_tag'),
                background: scheme.primaryContainer,
                style: chip?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
            if (badge.isNotEmpty)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _Chip(
                  key: const ValueKey('live-play-local-badge'),
                  text: localEmojiText(badge),
                  background: Color(profile!.accent).withValues(alpha: 0.14),
                  style: localEmojiStyle(chip?.copyWith(color: localAccentInk(profile.accent, theme.brightness))),
                ),
              ),
            TextSpan(
              text: '${profile?.displayName ?? message.userName}：',
              style: body?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (gift == null)
              TextSpan(
                text: message.message,
                style: body?.copyWith(color: scheme.onSurface),
              )
            else ...[
              TextSpan(
                text: '${i18n('local_sent_gift')} ',
                style: body?.copyWith(color: scheme.onSurface),
              ),
              TextSpan(text: '${localEmojiText(gift.emoji)} ', style: localEmojiStyle(body)),
              TextSpan(
                text: gift.name,
                style: body?.emphasis.copyWith(color: localGiftInk(gift.color, theme.brightness)),
              ),
              TextSpan(
                text: ' ×1',
                style: body?.copyWith(color: scheme.onSurface),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const new({required this.text, required this.background, required this.style, super.key});

  final String text;
  final Color background;
  final TextStyle? style;

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
