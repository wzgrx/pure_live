import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

// What makes a combo of a platform's gifts (D07.1,
// docs/D-弹幕/D07-礼物和付费消息/D07.1-礼物过滤连击合并和限速): shared by the chat list's merging
// (`features/live_play/logic/gift_combiner.dart`) and the flying gifts of
// every picture (A08.12, gift_flights.dart), so a combo is the same combo
// in both.

/// A gift line's gift once more than one message counted on it (D07.1):
/// [count] is the combo's total so far, the rest is [last]'s, the newest
/// message's gift, which keeps the platform's own fields.
@immutable
final class CombinedGift extends LiveGift {
  /// [last] counted as [count] in all, over [sends] messages.
  new(this.last, {required super.count, required this.sends})
    : super(
        name: last.name,
        id: last.id,
        kind: last.kind,
        comboKey: last.comboKey,
        comboTotal: last.comboTotal,
        unitPrice: last.unitPrice,
        totalValue: _value(last, count),
        unit: last.unit,
        free: last.free,
        iconUrl: last.iconUrl,
        receiverName: last.receiverName,
      );

  /// The newest message's gift.
  final LiveGift last;

  /// How many messages counted on the line.
  final int sends;

  /// The value of [count] like [gift]: its unit price times [count], or its
  /// value scaled from its own count; null when it has neither.
  static int? _value(LiveGift gift, int count) {
    if (gift.unitPrice case final price?) return price * count;
    final value = gift.totalValue;
    return value == null ? null : (value * count / gift.count).round();
  }

  @override
  bool operator ==(Object other) =>
      super == other && other is CombinedGift && other.last == last && other.sends == sends;

  @override
  int get hashCode => Object.hash(super.hashCode, last, sends);
}

/// What the gifts of one combo share: the platform's combo key, or the
/// sender (id and name) and the gift (its id, else its name) of that kind.
String giftComboKey(LiveMessage message, LiveGift gift) => gift.comboKey.isNotEmpty
    ? 'combo:${gift.comboKey}'
    : 'sender:${gift.kind.name}:${message.userId}\u0000${message.userName}\u0000'
          '${gift.id.isNotEmpty ? gift.id : gift.name}';

/// The count of a combo that showed [shown] once [gift] counts on it: the
/// platform's running count when it has one ([LiveGift.comboTotal];
/// Douyu's `hits` counts gifts, Huya's `iItemGroup` sends, Bilibili's
/// `COMBO_SEND` is the whole combo so far), else the sum of the counts.
int giftComboTotal(int shown, LiveGift gift) {
  final running = gift.comboTotal;
  if (running == null) return shown + gift.count;
  // The message counts the whole combo (Bilibili's COMBO_SEND).
  if (running == gift.count) return math.max(shown, running);
  return math.max(running, shown + gift.count);
}

/// The count a combo starts with at [gift]: the platform's count so far
/// when it joined during a combo, else the message's.
int giftComboStart(LiveGift gift) => math.max(gift.comboTotal ?? 0, gift.count);

/// Whether a combo whose last gift said [running] (the platform's count)
/// started again at [gift]: its count went back.
bool giftComboRestarted(int? running, LiveGift gift) {
  final next = gift.comboTotal;
  return next != null && running != null && next <= running;
}

/// [message] holding [gift], its text the gift's.
LiveMessage giftMessageWith(LiveMessage message, LiveGift gift, {String? text}) => LiveMessage(
  type: message.type,
  userName: message.userName,
  message: text ?? gift.plainText,
  color: message.color,
  userId: message.userId,
  data: gift,
  userLevel: message.userLevel,
  fansLevel: message.fansLevel,
  fansName: message.fansName,
  isLocal: message.isLocal,
  messageId: message.messageId,
  sentAt: message.sentAt,
  style: message.style,
  replayed: message.replayed,
  emotes: message.emotes,
  sourceRoomId: message.sourceRoomId,
  nameColor: message.nameColor,
  badges: message.badges,
);
