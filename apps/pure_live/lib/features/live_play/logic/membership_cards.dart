import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/gift_words.dart';

/// The start of a [membershipCard]'s [LiveSuperChatMessage.messageId]: the
/// cards the room made itself, which "上舰和开会员进醒目留言" turned off takes
/// away again.
const String membershipCardIdPrefix = 'membership:';

/// Whether [superChat] is a card [membershipCard] made.
bool isMembershipCard(LiveSuperChatMessage superChat) => superChat.messageId.startsWith(membershipCardIdPrefix);

/// The card among the super chats for a membership or subscription the
/// platform reported (D07.2, "上舰和开会员进醒目留言"; V03.5 §6.6), or null
/// for any other message:
///
/// - a gift ([LiveMessageType.gift]) of kind [LiveGiftKind.membership] or
///   [LiveGiftKind.subscription]: Bilibili's `GUARD_BUY` (舰长, 提督, 总督),
///   and any platform whose subscriptions are gifts. The price is what it
///   cost: gold seeds become yuan (198 yuan a month of 舰长, times the
///   months), another unit stays the platform's; without one the card
///   names what was bought ("舰长"); the text is the gift's sentence
///   ("开通 舰长 ×1 个月");
/// - a [LiveNoticeKind.subscription] notice: YouTube's memberships and
///   gifted memberships, Twitch's subscriptions and gifts, CHZZK's, Kick's
///   and Picarto's subscriptions. It has no price, so the card names what
///   it is ("会员" on YouTube, else "订阅"); the text is the notice's
///   without the name before it. One viewer's share of a gift
///   ([LiveNoticeKind.giftedSubscription]) has none: the giver's notice
///   counts the gift.
///
/// The card shows from the platform's time (else [now]) for as long as a
/// Bilibili super chat of its price in yuan would ([membershipCardDuration]);
/// it has no colours of its own (the card's theme colours) and no avatar.
/// Its id is [membershipCardIdPrefix] and the message's id, or what tells
/// the message apart without one, so a message the platform sends again
/// is the same card.
LiveSuperChatMessage? membershipCard(LiveMessage message, {required String platform, required DateTime now}) {
  final name = message.userName.trim();
  final int price;
  final LiveGiftUnit unit;
  final String priceText;
  final String text;
  switch (message) {
    case LiveMessage(type: LiveMessageType.gift, :final gift?)
        when gift.kind == LiveGiftKind.membership || gift.kind == LiveGiftKind.subscription:
      final value = gift.totalValue ?? 0;
      if (gift.unit == LiveGiftUnit.goldSeed) {
        price = (value / giftUnitsPerYuan[LiveGiftUnit.goldSeed]!).round();
        unit = LiveGiftUnit.yuan;
      } else {
        price = gift.free ? 0 : value;
        unit = gift.unit;
      }
      // Without a price in words, the card names what was bought (舰长).
      priceText = price > 0 && giftUnitText(unit, price) != null
          ? ''
          : gift.kind == LiveGiftKind.membership
          ? giftName(gift)
          : i18n('super_chat_card_subscription');
      text = giftSentence(gift);
    case LiveMessage(type: LiveMessageType.notice, data: LiveNoticeKind.subscription):
      final said = message.message.trim();
      if (said.isEmpty) return null;
      price = 0;
      unit = LiveGiftUnit.other;
      priceText = _noticeWord(platform);
      text = name.isNotEmpty && said.startsWith('$name ') ? said.substring(name.length + 1).trim() : said;
    default:
      return null;
  }
  final start = message.sentAt ?? now;
  final key = message.messageId.isNotEmpty
      ? message.messageId
      : '${message.userId}|$name|${message.sentAt?.millisecondsSinceEpoch ?? ''}|${message.message}';
  return LiveSuperChatMessage(
    messageId: '$membershipCardIdPrefix$platform:$key',
    userName: name,
    face: '',
    message: text,
    price: price,
    priceText: priceText,
    unit: unit,
    startTime: start,
    endTime: start.add(membershipCardDuration(price, unit)),
    backgroundColor: '',
    backgroundBottomColor: '',
  );
}

/// How long a membership card stays: the steps of Bilibili's super chats by
/// the price in yuan (30 yuan a minute, 50 two, 100 five, 500 thirty, 1000
/// an hour, 2000 two hours; a month of 舰长 at 198 yuan five minutes), at
/// least a minute; a minute when the price is unknown or in a unit with no
/// rate in yuan.
Duration membershipCardDuration(int price, LiveGiftUnit unit) {
  final rate = giftUnitsPerYuan[unit];
  final yuan = rate == null || price <= 0 ? 0 : price / rate;
  return switch (yuan) {
    >= 2000 => const Duration(hours: 2),
    >= 1000 => const Duration(hours: 1),
    >= 500 => const Duration(minutes: 30),
    >= 100 => const Duration(minutes: 5),
    >= 50 => const Duration(minutes: 2),
    _ => const Duration(minutes: 1),
  };
}

/// What a notice's card says it is in place of a price: "会员" for
/// YouTube's memberships, "订阅" for the subscriptions of the others.
String _noticeWord(String platform) =>
    i18n(platform == SiteIds.youtube ? 'super_chat_card_membership' : 'super_chat_card_subscription');
