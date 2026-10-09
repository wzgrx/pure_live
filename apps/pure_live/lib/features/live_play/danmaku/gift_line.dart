import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/chat_text.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

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

/// The count a gift line shows after "×": the platform's running combo
/// count when it gives one (Douyu `hits`, Huya `iItemGroup`) and it is
/// more than this message's count, else the count. D07.1's merging hands
/// the line a message with a new count; the line only shows it.
int giftShownCount(LiveGift gift) => math.max(gift.count, gift.comboTotal ?? 0);

/// What the shown count is worth, in the gift's unit: none for a free gift;
/// the unit price times the shown count when a combo count is shown and the
/// price is known; else the message's [LiveGift.totalValue].
int? giftShownValue(LiveGift gift) {
  if (gift.free) return null;
  final shown = giftShownCount(gift);
  final price = gift.unitPrice;
  if (shown != gift.count && price != null && price > 0) return price * shown;
  return gift.totalValue;
}

/// The tier the line marks: [giftTierOf] the shown value (a combo climbs
/// tiers as it grows; for one message it is [LiveGift.tier]).
LiveGiftTier giftShownTier(LiveGift gift) => giftTierOf(gift.unit, giftShownValue(gift), free: gift.free);

/// The value as the line writes it ("100 元", "2000 金瓜子", "79 Kicks"),
/// in the platform's own unit (V03.5 §6.5; converting to yuan is A08.12's
/// switch); null when it has none to show: free, unknown, zero, or a unit
/// nobody has checked ([LiveGiftUnit.other], Huya's `lPayTotal`; silver
/// seeds are free).
String? giftValueText(LiveGift gift) {
  final value = giftShownValue(gift);
  if (value == null || value <= 0) return null;
  final key = switch (gift.unit) {
    LiveGiftUnit.fen => 'gift_value_yuan',
    LiveGiftUnit.goldSeed => 'gift_value_gold_seed',
    LiveGiftUnit.diamond => 'gift_value_diamond',
    LiveGiftUnit.redBean => 'gift_value_red_bean',
    LiveGiftUnit.point => 'gift_value_point',
    LiveGiftUnit.bits => 'gift_value_bits',
    LiveGiftUnit.kicks => 'gift_value_kicks',
    LiveGiftUnit.cheese => 'gift_value_cheese',
    LiveGiftUnit.starBalloon => 'gift_value_star_balloon',
    LiveGiftUnit.douyinCoin => 'gift_value_douyin_coin',
    LiveGiftUnit.silverSeed || LiveGiftUnit.other => null,
  };
  if (key == null) return null;
  final amount = gift.unit == LiveGiftUnit.fen ? _yuan(value) : _amount(value);
  return i18n(key, args: {'value': amount});
}

/// A large amount the way the app writes counts ("19.8万", "2万"; "198k"
/// in English).
String _amount(int value) => readableAudience('$value').replaceFirst(RegExp(r'\.0(?=\D*$)'), '');

/// Fen as yuan: "5", "0.1", "12.5".
String _yuan(int fen) {
  if (fen % 100 == 0) return _amount(fen ~/ 100);
  final text = (fen / 100).toStringAsFixed(2);
  return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
}

/// What a platform's gift adds after the value (E05.5 took it out of the
/// text): niconico's giver rank ("贡献第 3 名").
List<String> giftNotes(LiveGift gift) => [
  if (gift case NiconicoGift(:final contributionRank?) when contributionRank > 0)
    i18n('gift_line_rank', args: {'rank': '$contributionRank'}),
];

/// The verb before the gift's name, by kind: "送出" (or "送给 嘉宾" when the
/// platform names a receiver other than [streamer]), "开通" a membership,
/// "赠送" subscriptions, "打赏" a tip.
String giftVerb(LiveGift gift, {String streamer = ''}) {
  final receiver = gift.receiverName.trim();
  return switch (gift.kind) {
    LiveGiftKind.gift when receiver.isNotEmpty && receiver != streamer.trim() => i18n(
      'gift_line_sent_to',
      args: {'name': receiver},
    ),
    LiveGiftKind.gift => i18n('gift_line_sent'),
    LiveGiftKind.membership => i18n('gift_line_bought'),
    LiveGiftKind.subscription => i18n('gift_line_gifted'),
    LiveGiftKind.tip => i18n('gift_line_tipped'),
  };
}

/// The gift's name, never empty.
String giftName(LiveGift gift) {
  final name = gift.displayName.trim();
  return name.isEmpty ? i18n('gift_line_unnamed') : name;
}

/// "×N" ("×1 个月" for a membership); empty for a tip of one, whose value
/// says it.
String giftCountText(LiveGift gift) {
  final count = giftShownCount(gift);
  return switch (gift.kind) {
    LiveGiftKind.membership => i18n('gift_line_months', args: {'count': '$count'}),
    LiveGiftKind.tip when count == 1 => '',
    _ => i18n('gift_line_count', args: {'count': '$count'}),
  };
}

/// The gift in words, without the sender: "送出 小心心 ×3" (what a double
/// tap copies after "名字: ", c7).
String giftSentence(LiveGift gift, {String streamer = ''}) {
  final count = giftCountText(gift);
  return '${giftVerb(gift, streamer: streamer)} ${giftName(gift)}${count.isEmpty ? '' : ' $count'}';
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

  /// The picture's size.
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
  void didUpdateWidget(GiftLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.message.gift;
    final now = widget.message.gift;
    if (before == null || now == null || giftShownCount(before) == giftShownCount(now)) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
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
    final body = ChatText.content(theme);
    final secondary = body?.copyWith(color: scheme.onSurfaceVariant);
    final named = body?.emphasis.copyWith(color: giftInk);
    final name = widget.showName ? message.userName.trim() : '';
    final notes = gift == null ? const <String>[] : [?giftValueText(gift), ...giftNotes(gift)];
    final count = gift == null ? '' : giftCountText(gift);
    final text = Text.rich(
      key: const ValueKey('live-play-gift-text'),
      TextSpan(
        children: [
          ...widget.lead,
          if (name.isNotEmpty)
            TextSpan(text: '$name ', style: ChatText.name(theme, chatNameInk(message, ground, scheme))),
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
                  style: theme.textTheme.bodyMedium?.regular.tabular.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
    // The picture sits on the first line at every text size.
    final first = MediaQuery.textScalerOf(context).scale(body?.fontSize ?? 14) * (body?.height ?? 1.5);
    final icon = Padding(
      padding: EdgeInsetsDirectional.only(top: math.max(0, (first - GiftLine.iconSize) / 2), end: card ? 8 : 6),
      child: GiftIcon(url: gift?.iconUrl, color: scheme.tertiary),
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: marked(row, inset: 0, gap: mark + 6),
      );
    }
    // The chat card (A08.1), the picture in the dot's place.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: DecoratedBox(
        key: const ValueKey('live-play-gift-card'),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant, width: 0.5),
        ),
        child: marked(
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: row),
          inset: 8,
          gap: 0,
        ),
      ),
    );
  }

  /// A piece of the line that moves to the next line whole: laid out at the
  /// base size, which the text's own scaling then enlarges (a text inside a
  /// [WidgetSpan] would otherwise be scaled twice).
  WidgetSpan _piece(Widget child, {bool pulse = false}) {
    final scale = _scale;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MediaQuery.withNoTextScaling(
        child: pulse && scale != null ? ScaleTransition(scale: scale, child: child) : child,
      ),
    );
  }
}

/// A gift's picture (c1): [size] square, decoded at the size it is drawn
/// through the app's image cache (as [ChatBadge]); the gift icon in
/// [color] while it loads, when it fails and when the platform gives none,
/// so the line never has a gap there.
class GiftIcon extends StatelessWidget {
  /// Creates the picture of [url].
  const new({required this.url, required this.color, super.key});

  /// The picture's address, or null.
  final Uri? url;

  /// The fallback icon's colour.
  final Color color;

  /// The picture's size.
  static const double size = 16;

  @override
  Widget build(BuildContext context) {
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
  VoidCallback? onActions,
  VoidCallback? onCopy,
}) => GestureDetector(
  key: const ValueKey('live-play-gift-line'),
  behavior: HitTestBehavior.opaque,
  onLongPress: onActions,
  onSecondaryTap: onActions,
  onDoubleTap: onCopy,
  child: GiftLine(message: line.message!, text: line.text, style: style, showName: showName, room: room, lead: lead),
);
