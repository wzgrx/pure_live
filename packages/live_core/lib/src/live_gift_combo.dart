import 'dart:math' as math;

import 'package:live_core/src/live_gift.dart';
import 'package:live_core/src/live_message.dart';

// What makes a combo of a platform's gifts (D07.1,
// docs/D-弹幕/D07-礼物和付费消息/D07.1-礼物过滤连击合并和限速): the chat list's
// merging, the flying gifts (A08.12) and the recorded chat (H01.8) count a
// combo the same way. Moved here from the app's
// `shared/danmaku/gift_combo.dart` (which re-exports them) so the
// recorder, a pure Dart package, uses the same rules.

/// What the gifts of one combo share: the platform's combo key, or the
/// sender (id and name) and the gift (its id, else its name) of that kind.
String giftComboKey(LiveMessage message, LiveGift gift) => gift.comboKey.isNotEmpty
    ? 'combo:${gift.comboKey}'
    : 'sender:${gift.kind.name}:${message.userId}\u0000${message.userName}\u0000'
          '${gift.id.isNotEmpty ? gift.id : gift.name}'
          // A gift to someone else is another combo (D07.7: Kugou's streamer
          // sends 亲亲 to ten viewers in turn); no receiver keeps the old key.
          '${gift.receiverName.isEmpty ? '' : '\u0000→${gift.receiverName}'}';

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

/// Whether [gift] is a platform's summary of a combo: a combo key and a
/// running count equal to its own count (Bilibili's `COMBO_SEND`, which
/// comes about 5 s after the combo's last send, D07.4).
bool giftIsComboSummary(LiveGift gift) => gift.comboKey.isNotEmpty && gift.comboTotal == gift.count;

/// The value of [count] gifts like [gift], in its unit: its unit price
/// times [count], or its value scaled from its own count; null when it has
/// neither.
int? giftValueOfCount(LiveGift gift, int count) {
  if (gift.unitPrice case final price?) return price * count;
  final value = gift.totalValue;
  return value == null ? null : (value * count / gift.count).round();
}
