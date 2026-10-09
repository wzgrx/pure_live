import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';

/// What [GiftCombiner.add] did with a gift.
enum GiftOutcome {
  /// A new gift line.
  added,

  /// Counted on the line of its combo.
  merged,

  /// Not shown: over the line limit with no line to count it on, or free
  /// (counted in [GiftCombiner.dropped]).
  dropped,
}

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

/// Puts a room's platform gifts into its [ChatFeed] (D07.1; V03.5 §6.4,
/// §6.8): a combo is one line whose count goes up, and a busy room's gifts
/// neither flood the list nor push the chat out.
///
/// - **Combo**: a gift with the key ([comboKeyOf]) of a line still among
///   the last [comboLines] lines, within [comboWindow] of that line's last
///   gift, is counted on it: the line is replaced by one with the new count
///   ([ChatFeed.replace]: it comes to the bottom of a following list, and
///   stays where it is in a held one). A platform count that went back
///   ([LiveGift.comboTotal] not above the line's) is a new combo, so a new
///   line.
/// - **Count** ([totalOf]): the platform's running count
///   ([LiveGift.comboTotal]) when it says more than adding up the messages
///   would, else the sum of their counts.
/// - **Limit**: at most [linesPerSecond] new gift lines a second. Beyond
///   it a gift that needs a new line is dropped (and counted, [dropped]),
///   except that a paid one is counted on its combo's line wherever it is,
///   and a valuable one ([LiveGiftTier.valuable] and up) gets its line all
///   the same.
/// - The feed keeps at most [maxGiftLines] gift lines
///   ([ChatFeed.giftCapacity]), dropping the oldest gift line first.
///
/// The controller hands it only gifts that passed the filter, and none
/// while the gift switch is off.
final class GiftCombiner {
  /// Puts gifts into [feed]; `clock` times the window and the limit.
  new({required this.feed, required this._clock});

  /// How long after a combo's last gift the next one still counts on its
  /// line (V03.5 §6.4).
  static const Duration comboWindow = Duration(seconds: 5);

  /// How near the bottom a combo's line must still be to count on it.
  static const int comboLines = 20;

  /// New gift lines a second (V03.5 §6.8).
  static const int linesPerSecond = 10;

  /// Gift lines among the feed's 500 (V03.5 §6.8): the feed's
  /// [ChatFeed.giftCapacity].
  static const int maxGiftLines = 150;

  /// Combos remembered; the least recent goes first.
  static const int _maxCombos = 256;

  static const Duration _second = Duration(seconds: 1);

  /// The room's chat.
  final ChatFeed feed;

  final DateTime Function() _clock;
  final LinkedHashMap<String, _Combo> _combos = LinkedHashMap();
  final ListQueue<DateTime> _newLines = ListQueue();
  int _dropped = 0;

  /// Gifts not shown so far (over the limit).
  int get dropped => _dropped;

  /// What the gifts of one combo share: the platform's combo key, or the
  /// sender (id and name) and the gift (its id, else its name) of that kind.
  static String comboKeyOf(LiveMessage message, LiveGift gift) => gift.comboKey.isNotEmpty
      ? 'combo:${gift.comboKey}'
      : 'sender:${gift.kind.name}:${message.userId}\u0000${message.userName}\u0000'
            '${gift.id.isNotEmpty ? gift.id : gift.name}';

  /// The count of a line that showed [shown] once [gift] counts on it: the
  /// platform's running count when it has one ([LiveGift.comboTotal];
  /// Douyu's `hits` counts gifts, Huya's `iItemGroup` sends, Bilibili's
  /// `COMBO_SEND` is the whole combo so far), else the sum of the counts.
  static int totalOf(int shown, LiveGift gift) {
    final running = gift.comboTotal;
    if (running == null) return shown + gift.count;
    // The message counts the whole combo (Bilibili's COMBO_SEND).
    if (running == gift.count) return math.max(shown, running);
    return math.max(running, shown + gift.count);
  }

  /// Puts [message], a platform gift, into the feed.
  GiftOutcome add(LiveMessage message) {
    final now = _clock();
    final gift = message.gift;
    final key = gift == null ? null : comboKeyOf(message, gift);
    var combo = key == null ? null : _combos.remove(key);
    if (combo != null && feed.linesAfter(combo.line) < 0) combo = null;
    if (key != null && gift != null && combo != null) {
      final near = feed.linesAfter(combo.line) < comboLines && now.difference(combo.at) <= comboWindow;
      if (near && !combo.restartedBy(gift)) return _merge(key, combo, message, gift, now);
    }
    if (_mayAddLine(now) || (gift != null && gift.tier != LiveGiftTier.normal)) {
      return _addLine(key, message, gift, now);
    }
    // Over the limit: a paid gift still counts on its combo's line.
    if (key != null && gift != null && combo != null) {
      if (!gift.free) return _merge(key, combo, message, gift, now, restarted: combo.restartedBy(gift));
      _remember(key, combo);
    }
    _dropped++;
    return GiftOutcome.dropped;
  }

  /// Forgets the combos and the limit (the gift lines went).
  void clear() {
    _combos.clear();
    _newLines.clear();
  }

  bool _mayAddLine(DateTime now) {
    while (_newLines.isNotEmpty && now.difference(_newLines.first) >= _second) {
      _newLines.removeFirst();
    }
    return _newLines.length < linesPerSecond;
  }

  GiftOutcome _addLine(String? key, LiveMessage message, LiveGift? gift, DateTime now) {
    _newLines.addLast(now);
    if (key == null || gift == null) {
      feed.add(ChatLine.gift(message));
      return GiftOutcome.added;
    }
    // Joined during a combo: the platform's count so far.
    final total = math.max(gift.comboTotal ?? 0, gift.count);
    final line = ChatLine.gift(
      total == gift.count ? message : _withGift(message, CombinedGift(gift, count: total, sends: 1)),
    );
    feed.add(line);
    _remember(key, _Combo(line, at: now, total: total, running: gift.comboTotal, sends: 1));
    return GiftOutcome.added;
  }

  GiftOutcome _merge(
    String key,
    _Combo combo,
    LiveMessage message,
    LiveGift gift,
    DateTime now, {
    bool restarted = false,
  }) {
    final total = restarted ? combo.total + gift.count : totalOf(combo.total, gift);
    final running = gift.comboTotal ?? combo.running;
    if (total == combo.total) {
      // Nothing new to show (a combo's summary that adds nothing).
      _remember(key, _Combo(combo.line, at: now, total: total, running: running, sends: combo.sends));
      return GiftOutcome.merged;
    }
    final sends = combo.sends + 1;
    final line = ChatLine.gift(
      _withGift(message, CombinedGift(gift, count: total, sends: sends)),
      revision: combo.line.revision + 1,
    );
    feed.replace(combo.line, line);
    _remember(key, _Combo(line, at: now, total: total, running: running, sends: sends));
    return GiftOutcome.merged;
  }

  void _remember(String key, _Combo combo) {
    _combos[key] = combo;
    if (_combos.length > _maxCombos) _combos.remove(_combos.keys.first);
  }

  /// [message] holding [gift], its text the gift's.
  static LiveMessage _withGift(LiveMessage message, LiveGift gift) => LiveMessage(
    type: message.type,
    userName: message.userName,
    message: gift.plainText,
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
}

/// One combo's line, when its last gift came, the count it shows, the
/// platform's running count of its last gift and how many messages counted.
final class _Combo {
  new(this.line, {required this.at, required this.total, required this.running, required this.sends});

  final ChatLine line;
  final DateTime at;
  final int total;
  final int? running;
  final int sends;

  /// Whether [gift]'s platform count went back: a new combo of the same key.
  bool restartedBy(LiveGift gift) {
    final next = gift.comboTotal;
    final last = running;
    return next != null && last != null && next <= last;
  }
}
