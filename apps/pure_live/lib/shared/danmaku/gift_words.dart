import 'dart:math' as math;

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// The words and numbers of a platform's gift (A08.11,
// docs/A-界面设计/A08-弹幕界面/A08.11-礼物行的样子), shared by the chat list's gift line and the
// flying gifts of every picture (A08.12): one sentence for a gift wherever
// it shows. The chat list's widgets re-export them
// (`features/live_play/danmaku/gift_line.dart`).

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

/// The units whose rate in yuan the platform fixes (A08.12, V03.5 §6.5):
/// "礼物价值换算成元" writes these as yuan; the overseas ones (their rates in
/// [giftUnitsPerYuan] only rank gifts) and the unchecked ones stay as they
/// are.
const Set<LiveGiftUnit> giftYuanUnits = {
  LiveGiftUnit.fen,
  LiveGiftUnit.yuan,
  LiveGiftUnit.goldSeed,
  LiveGiftUnit.diamond,
  LiveGiftUnit.douyinCoin,
  LiveGiftUnit.acCoin,
};

/// The value as the line writes it ("100 元", "2000 金瓜子", "79 Kicks"),
/// in the platform's own unit (V03.5 §6.5), or with [inYuan] ("礼物价值换算成元",
/// A08.12) in yuan for the [giftYuanUnits] ("2 元" for 2000 gold seeds);
/// null when it has none to show: free, unknown, zero, or a unit nobody
/// has checked ([LiveGiftUnit.other], Huya's `lPayTotal`; silver seeds are
/// free).
String? giftValueText(LiveGift gift, {bool inYuan = false}) {
  final value = giftShownValue(gift);
  if (value == null || value <= 0) return null;
  if (inYuan && giftYuanUnits.contains(gift.unit)) {
    final rate = giftUnitsPerYuan[gift.unit]!;
    // At least a fen: a paid gift is never "0 元".
    final fen = math.max(1, (value * 100 / rate).round());
    return i18n('gift_value_yuan', args: {'value': _yuan(fen)});
  }
  return giftUnitText(gift.unit, value);
}

/// [value] in [unit] as the app writes it ("100 元" for 10000 fen or 100
/// yuan, "2000 金瓜子", "79 Kicks", "1000 六币"): the gift line's value and a
/// super chat's price (D07.2, `superChatPriceLabel`); null for a unit
/// nobody has checked ([LiveGiftUnit.other], Huya's `lPayTotal`) and for
/// silver seeds (free).
String? giftUnitText(LiveGiftUnit unit, int value) {
  final key = switch (unit) {
    LiveGiftUnit.fen || LiveGiftUnit.yuan => 'gift_value_yuan',
    LiveGiftUnit.goldSeed => 'gift_value_gold_seed',
    LiveGiftUnit.diamond => 'gift_value_diamond',
    LiveGiftUnit.redBean => 'gift_value_red_bean',
    LiveGiftUnit.point => 'gift_value_point',
    LiveGiftUnit.bits => 'gift_value_bits',
    LiveGiftUnit.kicks => 'gift_value_kicks',
    LiveGiftUnit.cheese => 'gift_value_cheese',
    LiveGiftUnit.starBalloon => 'gift_value_star_balloon',
    LiveGiftUnit.douyinCoin => 'gift_value_douyin_coin',
    LiveGiftUnit.sixCoin => 'gift_value_six_coin',
    LiveGiftUnit.acCoin => 'gift_value_ac_coin',
    LiveGiftUnit.silverSeed || LiveGiftUnit.banana || LiveGiftUnit.other => null,
  };
  if (key == null) return null;
  final amount = unit == LiveGiftUnit.fen ? _yuan(value) : _amount(value);
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

/// The gift's name, never empty: "礼物 {编号}" when the platform gave only
/// the id (D07.6: 17LIVE, and AcFun before its gift table came), "礼物"
/// without either.
String giftName(LiveGift gift) {
  final name = gift.name.trim();
  if (name.isNotEmpty) return name;
  final id = gift.id.trim();
  return id.isEmpty ? i18n('gift_line_unnamed') : i18n('gift_line_numbered', args: {'id': id});
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
