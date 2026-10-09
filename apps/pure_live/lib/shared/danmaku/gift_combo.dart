import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

// The combo rules themselves live in live_core (live_gift_combo.dart) so the
// recorder counts a combo the same way (H01.8); exported here for the room's
// files that read them from this library.
export 'package:live_core/live_core.dart'
    show giftComboKey, giftComboRestarted, giftComboStart, giftComboTotal, giftIsComboSummary, giftValueOfCount;

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
        totalValue: giftValueOfCount(last, count),
        unit: last.unit,
        free: last.free,
        iconUrl: last.iconUrl,
        receiverName: last.receiverName,
      );

  /// The newest message's gift.
  final LiveGift last;

  /// How many messages counted on the line.
  final int sends;

  @override
  bool operator ==(Object other) =>
      super == other && other is CombinedGift && other.last == last && other.sends == sends;

  @override
  int get hashCode => Object.hash(super.hashCode, last, sends);
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
