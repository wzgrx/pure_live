import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/chat_text.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/danmaku/gift_words.dart';

// The words and numbers moved to shared/ for the flying gifts (A08.12); the
// list's code and its tests still read them from here.
export 'package:pure_live/shared/danmaku/gift_words.dart';

// A08.11 (docs/A-界面设计/A08-弹幕界面/A08.11-礼物行的样子): one gift line for every
// platform, read from the shared LiveGift (E05.5) and never from a
// platform's sentence.

/// What the gift line needs of the room besides the message: the platform,
/// whose colour marks a precious gift (G3), and the streamer, who is not
/// named as the receiver of every gift (Douyu names them on each).
@immutable
final class GiftLineRoom {
  /// Creates the facts.
  const new({this.platform = '', this.streamer = ''});

  /// No room (a line built alone): tertiary for every tier, every receiver
  /// named.
  static const GiftLineRoom none = GiftLineRoom();

  /// The platform's id ([SiteIds]).
  final String platform;

  /// The streamer's name, as the room has it.
  final String streamer;

  @override
  bool operator ==(Object other) => other is GiftLineRoom && other.platform == platform && other.streamer == streamer;

  @override
  int get hashCode => Object.hash(platform, streamer);
}

/// The colour of a precious gift's name and mark on [ground] (G3): the
/// platform's colour (the local interaction's platform packs, one table for
/// the 34 platforms) made readable at [chatNameContrast]; null for a
/// platform without one (the tertiary ink then).
Color? giftPlatformInk(String platform, Color ground) {
  final pack = LocalCatalog.packFor(platform);
  if (pack.id == LocalCatalog.genericPack.id) return null;
  return chatNameColor(LiveMessageColor.numberToColor(pack.accent), ground);
}

/// The width of the tier mark at the line's left edge: none, 2 for a
/// valuable gift, 4 for a precious one, so the tiers differ without their
/// colour (c3).
double giftTierMarkWidth(LiveGiftTier tier) => switch (tier) {
  LiveGiftTier.normal => 0,
  LiveGiftTier.valuable => 2,
  LiveGiftTier.precious => 4,
};

/// A gift line of the chat list (c1–c6), the same widget on every platform,
/// in both list styles and every layout:
///
/// - the gift's picture ([GiftIcon], 16 square) in the dot's place; then the
///   chat line's marks and the sender's name in the name role (left out
///   with [showName] off), "送出" in the secondary ink, the gift's name
///   semibold in the tertiary ink, "×N" in tabular figures, and the value
///   one size smaller in the secondary ink;
/// - compact: no background (super chats have theirs, notices the secondary
///   container); card: the chat card;
/// - a valuable gift has a 2-wide tertiary mark at its left edge, a precious
///   one a 4-wide mark and its name in the platform's colour (4.5:1);
/// - nothing is cut: the line wraps, and the value moves to the next line
///   as one piece when it does not fit;
/// - when the shown count changes (D07.1's combo), only "×N" grows to 1.2
///   times and back in 200 ms, not with the system's reduced motion.
class GiftLine extends StatefulWidget {
  /// Creates the line of [message].
  const new({
    required this.message,
    this.text = '',
    this.style = ChatListStyle.compact,
    this.showName = true,
    this.room = GiftLineRoom.none,
    this.lead = const [],
    this.merged = false,
    this.valueInYuan = false,
    this.sizing = ChatSizing.standard,
    super.key,
  });

  /// The gift message; its [LiveMessage.gift] is read.
  final LiveMessage message;

  /// The line's text, shown as the gift's name when the message holds no
  /// [LiveGift] (an engine that does not fill one).
  final String text;

  /// Compact line or card.
  final ChatListStyle style;

  /// Whether the line names its sender ("显示用户名", A08.10 G6).
  final bool showName;

  /// The room's platform and streamer.
  final GiftLineRoom room;

  /// The chat line's marks before the name ("对方", and with the names on
  /// the badges and the fan medal; A08.10 G5, G6).
  final List<InlineSpan> lead;

  /// Whether this line is a combo D07.1 just merged into: the merged line is
  /// a new [ChatLine] (a new id, so a new widget), and its ×N pulses once
  /// when it is first built (`ChatLine.revision > 0`).
  final bool merged;

  /// Writes the value in yuan where the platform fixes the rate
  /// ("礼物价值换算成元", A08.12; [giftValueText]).
  final bool valueInYuan;

  /// The list's text size and spacing (A08.15): the words, the value, the
  /// picture and the gaps follow it.
  final ChatSizing sizing;

  /// The picture's size at the theme's text size.
  static const double iconSize = GiftIcon.size;

  /// The combo pulse (c4).
  static const Duration pulse = Duration(milliseconds: 200);

  @override
  State<GiftLine> createState() => _GiftLineState();
}

class _GiftLineState extends State<GiftLine> with SingleTickerProviderStateMixin {
  AnimationController? _pulse;
  Animation<double>? _scale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.merged) _startPulse();
  }

  bool _started = false;

  @override
  void didUpdateWidget(GiftLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.message.gift;
    final now = widget.message.gift;
    if (before == null || now == null || giftShownCount(before) == giftShownCount(now)) return;
    _startPulse();
  }

  void _startPulse() {
    if (widget.message.gift == null || MediaQuery.disableAnimationsOf(context)) return;
    final pulse = _pulse ??= AnimationController(vsync: this, duration: GiftLine.pulse);
    // Up decelerating, back down decelerating (UI.md §8.6: no bounce).
    _scale ??= TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.2).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: 1.2, end: 1).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
    ]).animate(pulse);
    pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final card = widget.style == ChatListStyle.card;
    final ground = card ? scheme.surfaceContainerLowest : scheme.surface;
    final message = widget.message;
    final gift = message.gift;
    final tier = gift == null ? LiveGiftTier.normal : giftShownTier(gift);
    final platformInk = tier == LiveGiftTier.precious ? giftPlatformInk(widget.room.platform, ground) : null;
    final giftInk = platformInk ?? scheme.tertiary;
    final sizing = widget.sizing;
    final body = ChatText.content(theme, sizing: sizing);
    final secondary = body?.copyWith(color: scheme.onSurfaceVariant);
    final named = body?.emphasis.copyWith(color: giftInk);
    final name = widget.showName ? message.userName.trim() : '';
    final notes = gift == null
        ? const <String>[]
        : [?giftValueText(gift, inYuan: widget.valueInYuan), ...giftNotes(gift)];
    final count = gift == null ? '' : giftCountText(gift);
    final text = Text.rich(
      key: const ValueKey('live-play-gift-text'),
      TextSpan(
        children: [
          ...widget.lead,
          if (name.isNotEmpty)
            TextSpan(text: '$name ', style: ChatText.name(theme, chatNameInk(message, ground, scheme), sizing)),
          if (gift == null)
            TextSpan(text: widget.text, style: named)
          else ...[
            TextSpan(
              text: '${giftVerb(gift, streamer: widget.room.streamer)} ',
              style: secondary,
            ),
            TextSpan(text: giftName(gift), style: named),
            if (count.isNotEmpty) ...[
              TextSpan(text: ' ', style: named),
              _piece(Text(count, key: const ValueKey('live-play-gift-count'), style: named?.tabular), pulse: true),
            ],
          ],
          if (notes.isNotEmpty)
            _piece(
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Text(
                  notes.join(' · '),
                  key: const ValueKey('live-play-gift-value'),
                  style: sizing
                      .piece(theme.textTheme.bodyMedium, theme)
                      ?.regular
                      .tabular
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
    // The picture sits on the first line at every text size; it grows with
    // the list's text size (A08.15 c3), not with the system's, as before.
    final first = MediaQuery.textScalerOf(context).scale(body?.fontSize ?? 14) * (body?.height ?? 1.5);
    final iconSize = GiftLine.iconSize * sizing.scaleIn(theme);
    final icon = Padding(
      padding: EdgeInsetsDirectional.only(top: math.max(0, (first - iconSize) / 2), end: card ? 8 : 6),
      child: GiftIcon(url: gift?.iconUrl, color: scheme.tertiary, size: iconSize),
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        Expanded(child: text),
      ],
    );
    final mark = giftTierMarkWidth(tier);
    final markInk = platformInk ?? scheme.tertiary;
    Widget marked(Widget child, {required double inset, required double gap}) => mark == 0
        ? child
        : Stack(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(start: gap),
                child: child,
              ),
              PositionedDirectional(
                start: 0,
                top: inset,
                bottom: inset,
                width: mark,
                child: Semantics(
                  label: i18n(tier == LiveGiftTier.precious ? 'gift_tier_precious' : 'gift_tier_valuable'),
                  child: DecoratedBox(
                    key: ValueKey('live-play-gift-tier-${tier.name}'),
                    decoration: BoxDecoration(color: markInk, borderRadius: BorderRadius.circular(mark / 2)),
                  ),
                ),
              ),
            ],
          );
    if (!card) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: sizing.gap(4)),
        child: marked(row, inset: 0, gap: mark + 6),
      );
    }
    // The chat card (A08.1), the picture in the dot's place.
    final inner = sizing.gap(8);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: sizing.gap(4)),
      child: DecoratedBox(
        key: const ValueKey('live-play-gift-card'),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant, width: 0.5),
        ),
        child: marked(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: inner),
            child: row,
          ),
          inset: inner,
          gap: 0,
        ),
      ),
    );
  }

  /// A piece of the line that moves to the next line whole ([chatInline]).
  WidgetSpan _piece(Widget child, {bool pulse = false}) {
    final scale = _scale;
    return chatInline(
      pulse && scale != null ? ScaleTransition(scale: scale, child: child) : child,
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
    );
  }
}

/// A gift's picture (c1): [size] square, decoded at the size it is drawn
/// through the app's image cache (as [ChatBadge]); the gift icon in
/// [color] while it loads, when it fails and when the platform gives none,
/// so the line never has a gap there.
class GiftIcon extends StatelessWidget {
  /// Creates the picture of [url], [size] square (A08.15: the list's text
  /// size makes it larger or smaller).
  const new({required this.url, required this.color, double size = GiftIcon.size, super.key}) : side = size;

  /// The picture's address, or null.
  final Uri? url;

  /// The fallback icon's colour.
  final Color color;

  /// This picture's size.
  final double side;

  /// The picture's size at the theme's text size.
  static const double size = 16;

  @override
  Widget build(BuildContext context) {
    final size = side;
    final fallback = Icon(AppIcons.chatGift, key: const ValueKey('live-play-gift-icon'), size: size, color: color);
    final address = url?.toString() ?? '';
    if (address.isEmpty) return fallback;
    final decoded = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox.square(
      dimension: size,
      child: Image(
        key: const ValueKey('live-play-gift-image'),
        image: ResizeImage(chatBadgeImage(address), width: decoded, height: decoded, policy: ResizeImagePolicy.fit),
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, loaded) => frame == null && !loaded ? fallback : child,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// The gift line of a chat line with its gestures, as [ChatLineView] builds
/// it; kept here so the list's file does not grow.
Widget giftLineOf(
  ChatLine line, {
  required ChatListStyle style,
  required bool showName,
  required GiftLineRoom room,
  required List<InlineSpan> lead,
  bool valueInYuan = false,
  ChatSizing sizing = ChatSizing.standard,
  VoidCallback? onActions,
  VoidCallback? onCopy,
}) => GestureDetector(
  key: const ValueKey('live-play-gift-line'),
  behavior: HitTestBehavior.opaque,
  onLongPress: onActions,
  onSecondaryTap: onActions,
  onDoubleTap: onCopy,
  child: GiftLine(
    message: line.message!,
    text: line.text,
    style: style,
    showName: showName,
    room: room,
    lead: lead,
    merged: line.revision > 0,
    valueInYuan: valueInYuan,
    sizing: sizing,
  ),
);
