import 'package:live_core/src/live_message.dart';
import 'package:meta/meta.dart';

/// What a [LiveGift] is (E05.5; design in docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md §6.1).
enum LiveGiftKind {
  /// A gift sent to the broadcaster (or a guest).
  gift,

  /// A paid membership bought or renewed: Bilibili's guard (`GUARD_BUY`:
  /// 舰长, 提督, 总督), YouTube or Twitch memberships. [LiveGift.count] is
  /// the number of months.
  membership,

  /// Subscriptions gifted to other viewers (Twitch `subgift`, Kick's gifted
  /// subscriptions). [LiveGift.count] is how many were given.
  subscription,

  /// Money given without a gift item (Twitch Bits, SOOP's balloons, FC2
  /// tips). [LiveGift.name] names the currency.
  tip,
}

/// How much a [LiveGift] is worth ([giftTierOf]), as a hint for the gift
/// line and effects to come (V03.5 §6.3).
enum LiveGiftTier {
  /// Free, cheap, or of a value this app cannot place.
  normal,

  /// Worth a mark of its own.
  valuable,

  /// Worth the strongest mark.
  precious,
}

/// The unit of [LiveGift.unitPrice] and [LiveGift.totalValue]: each
/// platform's own currency, kept as the platform counts it. How many make a
/// yuan is only in [giftUnitsPerYuan].
enum LiveGiftUnit {
  /// Fen, a hundredth of a yuan (Douyu's gift table prices).
  fen,

  /// Whole yuan: the super chats of Bilibili (`SUPER_CHAT_MESSAGE.price`),
  /// Douyu (`cprice` in fen, read as yuan) and Huya (D07.2), and a
  /// Bilibili guard's card (198 yuan a month of 舰长).
  yuan,

  /// Bilibili gold seeds (金瓜子).
  goldSeed,

  /// Bilibili silver seeds (银瓜子), which free gifts cost.
  silverSeed,

  /// Missevan diamonds (钻石).
  diamond,

  /// KilaKila red beans (红豆).
  redBean,

  /// Points: niconico, 17LIVE, FC2.
  point,

  /// Twitch Bits.
  bits,

  /// Kick's Kicks.
  kicks,

  /// CHZZK cheese (치즈).
  cheese,

  /// SOOP star balloons (별풍선).
  starBalloon,

  /// Douyin coins (抖币).
  douyinCoin,

  /// Six Rooms coins (六币): a fly-screen costs 1000 (D07.2, the room
  /// page's `data-sug`). Its rate in yuan is not checked, so it is not
  /// ranked.
  sixCoin,

  /// AcFun's AC coins (AC币), ten to a yuan (D07.6).
  acCoin,

  /// AcFun's bananas (香蕉), the platform's free currency: a gift paid in
  /// them is free (D07.6).
  banana,

  /// Kugou Live's star coins (星币), a hundred to a yuan (the gift panel
  /// prices gifts in them, D07.7).
  starCoin,

  /// PandaTV's hearts (하트), about 110 won each like a SOOP star balloon
  /// (D07.7).
  heart,

  /// A unit the platform does not document (Huya's `lPayTotal`), or no
  /// value at all.
  other,
}

/// How many of each unit make about one yuan, for [giftTierOf] (V03.5
/// §6.1, §6.5). The domestic rates are fixed by the platforms; the overseas
/// ones are rough (100 Bits or 100 Kicks about a US dollar, cheese one won,
/// a star balloon or a PandaTV heart about 110 won, a niconico point about a
/// yen) and only
/// rank gifts, never convert a value shown. A unit missing here (red beans,
/// six coins, silver seeds, bananas, [LiveGiftUnit.other]) is never ranked
/// above [LiveGiftTier.normal].
///
/// The table and the [giftValuableYuan], [giftPreciousYuan] thresholds were
/// settled by A08.11 (D-003, the table and the reasons in
/// docs/A-界面设计/A08-弹幕界面/A08.11-礼物行的样子/README.md G1); a change here
/// applies everywhere.
const Map<LiveGiftUnit, double> giftUnitsPerYuan = {
  LiveGiftUnit.fen: 100,
  LiveGiftUnit.yuan: 1,
  LiveGiftUnit.goldSeed: 1000,
  LiveGiftUnit.diamond: 10,
  LiveGiftUnit.douyinCoin: 10,
  LiveGiftUnit.acCoin: 10,
  LiveGiftUnit.starCoin: 100,
  LiveGiftUnit.bits: 14,
  LiveGiftUnit.kicks: 14,
  LiveGiftUnit.cheese: 190,
  LiveGiftUnit.starBalloon: 1.7,
  LiveGiftUnit.heart: 1.7,
  LiveGiftUnit.point: 21,
};

/// From this many yuan a gift is [LiveGiftTier.valuable] (V03.5 §6.1).
const int giftValuableYuan = 10;

/// From this many yuan a gift is [LiveGiftTier.precious] (V03.5 §6.1).
const int giftPreciousYuan = 100;

/// The tier of a gift worth [totalValue] in [unit]: [LiveGiftTier.normal]
/// when [free], without a value or in a unit [giftUnitsPerYuan] does not
/// rate; else by yuan, below [giftValuableYuan] normal, below
/// [giftPreciousYuan] valuable, from it precious.
LiveGiftTier giftTierOf(LiveGiftUnit unit, int? totalValue, {bool free = false}) {
  final rate = giftUnitsPerYuan[unit];
  if (free || rate == null || totalValue == null || totalValue <= 0) return LiveGiftTier.normal;
  final yuan = totalValue / rate;
  if (yuan >= giftPreciousYuan) return LiveGiftTier.precious;
  if (yuan >= giftValuableYuan) return LiveGiftTier.valuable;
  return LiveGiftTier.normal;
}

/// A gift, membership, gifted subscription or tip a viewer sent: the
/// [LiveMessage.data] of every [LiveMessageType.gift] message the platform
/// adapters report, filled the same way on every platform (V03.5 §6.1,
/// E05.5). Each platform's class (`BilibiliGift`, `DouyuGift`…) extends it
/// with the fields only that platform has.
///
/// The sender is the message's: [LiveMessage.userName], [LiveMessage.userId]
/// and the level, fan badge and badges drawn as on a chat line, so blocking
/// and the name style act on gifts and chat alike. The message's text is
/// [plainText].
@immutable
base class LiveGift {
  /// Creates a gift; a [count] below 1 counts as 1.
  const new({
    required this.name,
    this.id = '',
    int count = 1,
    this.kind = LiveGiftKind.gift,
    this.comboKey = '',
    this.comboTotal,
    this.unitPrice,
    this.totalValue,
    this.unit = LiveGiftUnit.other,
    this.free = false,
    this.iconUrl,
    this.receiverName = '',
  }) : count = count < 1 ? 1 : count;

  /// The platform's id for the gift item; empty when it gives none.
  final String id;

  /// The gift's name as the platform writes it (`小心心`, `舰长`, `Donut`);
  /// see [displayName] for one that is never empty.
  final String name;

  /// How many this message gave, at least 1 (the months of a
  /// [LiveGiftKind.membership]).
  final int count;

  /// What it is.
  final LiveGiftKind kind;

  /// What every message of one combo shares: the platform's combo id
  /// (Bilibili `batch_combo_id`), or for Douyu, which has none, the sender
  /// and the gift while `hits` counts; empty otherwise. Combining by
  /// sender and gift when it is empty is D07.1's.
  final String comboKey;

  /// The combo's running count including this message, as the platform
  /// counts it (Douyu `hits`, Huya `iItemGroup`); null when it says nothing.
  final int? comboTotal;

  /// The price of one, in [unit]; null when unknown.
  final int? unitPrice;

  /// What this message's gifts are worth together, in [unit]; null when
  /// unknown.
  final int? totalValue;

  /// The unit of [unitPrice] and [totalValue].
  final LiveGiftUnit unit;

  /// The platform marks it free (Bilibili silver gifts, Baidu's 拍拍,
  /// KilaKila's 克拉之星, a niconico gift of no points).
  final bool free;

  /// The gift's picture (https), when the platform gives one.
  final Uri? iconUrl;

  /// Who received it when the platform names them (a guest on the
  /// microphone rather than the broadcaster); empty otherwise.
  final String receiverName;

  /// [name], or [id] when the platform gave no name.
  String get displayName => name.isNotEmpty ? name : id;

  /// [giftTierOf] this gift.
  LiveGiftTier get tier => giftTierOf(unit, totalValue, free: free);

  /// The text of the gift's message on every platform, `小心心 ×3`: the
  /// name and the count, without the sender (the chat line shows the name)
  /// and without a platform's sentence.
  String get plainText => '$displayName ×$count';

  /// Same class and same shared fields; a platform's class adds its own.
  @override
  bool operator ==(Object other) =>
      other is LiveGift &&
      other.runtimeType == runtimeType &&
      other.id == id &&
      other.name == name &&
      other.count == count &&
      other.kind == kind &&
      other.comboKey == comboKey &&
      other.comboTotal == comboTotal &&
      other.unitPrice == unitPrice &&
      other.totalValue == totalValue &&
      other.unit == unit &&
      other.free == free &&
      other.iconUrl == iconUrl &&
      other.receiverName == receiverName;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    count,
    kind,
    comboKey,
    comboTotal,
    unitPrice,
    totalValue,
    unit,
    free,
    iconUrl,
    receiverName,
  );

  @override
  String toString() =>
      'LiveGift(${kind.name} $plainText${totalValue == null ? '' : ', $totalValue ${unit.name}'}'
      '${free ? ', free' : ''})';
}
