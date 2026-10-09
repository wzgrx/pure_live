import 'dart:collection';

import 'package:live_core/live_core.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/shared/danmaku/gift_combo.dart';

// Moved to shared/ for the flying gifts (A08.12); the room and the tests
// still read it from here.
export 'package:pure_live/shared/danmaku/gift_combo.dart' show CombinedGift;

/// What [GiftCombiner.add] did with a gift.
enum GiftOutcome {
  /// A new gift line.
  added,

  /// Counted on the line of its combo.
  merged,

  /// Not shown: over the line limit with no line to count it on, or free
  /// (counted in [GiftCombiner.dropped]).
  dropped,

  /// Not shown yet: its combo is below [GiftCombiner.minTier] ("只显示值钱的
  /// 礼物", A08.12); it is counted, and the combo gets its line once its
  /// total reaches the tier.
  belowTier,
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
///   line. A combo's summary (a message with the platform's combo key that
///   counts the whole combo: Bilibili's `COMBO_SEND`, which comes after the
///   combo's last send) counts on its line within [summaryWindow], wherever
///   the line is (D07.4).
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
/// - **Tier** (A08.12, "只显示值钱的礼物"): with [minTier] above
///   [LiveGiftTier.normal] a combo gets a line only once its total is
///   worth that tier; until then its gifts are counted out of sight
///   ([GiftOutcome.belowTier]), and the line it gets shows the whole total.
///
/// The controller hands it only gifts that passed the filter, and none
/// while the gift switch is off.
final class GiftCombiner {
  /// Puts gifts into [feed]; `clock` times the window and the limit.
  new({required this.feed, required this._clock});

  /// How long after a combo's last gift the next one still counts on its
  /// line (V03.5 §6.4).
  static const Duration comboWindow = Duration(seconds: 5);

  /// How long after a combo's last gift its summary still counts on its
  /// line: Bilibili's `COMBO_SEND` comes when the combo has ended, 5.15 s
  /// after the last send in fixtures/bilibili/danmaku/S13-guest-gifts (its
  /// `combo_stay_time` is 10 s), so within [comboWindow] it made a second
  /// line (D07.4).
  static const Duration summaryWindow = Duration(seconds: 15);

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
  final LinkedHashMap<String, _Unseen> _unseen = LinkedHashMap();
  LiveGiftTier _minTier = LiveGiftTier.normal;
  final ListQueue<DateTime> _newLines = ListQueue();
  int _dropped = 0;

  /// Gifts not shown so far (over the limit).
  int get dropped => _dropped;

  /// The least a combo must be worth for a line (A08.12): normal shows
  /// every gift; a change forgets the combos counted out of sight.
  LiveGiftTier get minTier => _minTier;
  set minTier(LiveGiftTier tier) {
    if (tier == _minTier) return;
    _minTier = tier;
    _unseen.clear();
  }

  /// What the gifts of one combo share: the platform's combo key, or the
  /// sender (id and name) and the gift (its id, else its name) of that kind.
  static String comboKeyOf(LiveMessage message, LiveGift gift) => giftComboKey(message, gift);

  /// Whether [gift] sums up its combo: it has the platform's combo key and
  /// its running count is its own count (Bilibili's `COMBO_SEND`).
  static bool isSummary(LiveGift gift) => gift.comboKey.isNotEmpty && gift.comboTotal == gift.count;

  /// The count of a line that showed [shown] once [gift] counts on it: the
  /// platform's running count when it has one ([LiveGift.comboTotal];
  /// Douyu's `hits` counts gifts, Huya's `iItemGroup` sends, Bilibili's
  /// `COMBO_SEND` is the whole combo so far), else the sum of the counts.
  static int totalOf(int shown, LiveGift gift) => giftComboTotal(shown, gift);

  /// Puts [message], a platform gift, into the feed.
  GiftOutcome add(LiveMessage message) {
    final now = _clock();
    final gift = message.gift;
    final key = gift == null ? null : comboKeyOf(message, gift);
    var combo = key == null ? null : _combos.remove(key);
    if (combo != null && feed.linesAfter(combo.line) < 0) combo = null;
    if (key != null && gift != null && combo != null) {
      final near = isSummary(gift)
          ? now.difference(combo.at) <= summaryWindow
          : feed.linesAfter(combo.line) < comboLines && now.difference(combo.at) <= comboWindow;
      if (near && !combo.restartedBy(gift)) return _merge(key, combo, message, gift, now);
    }
    if (_minTier != LiveGiftTier.normal) return _addAboveTier(key, message, gift, now);
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
    _unseen.clear();
    _newLines.clear();
  }

  /// A gift that needs a new line while [minTier] holds: the line comes
  /// when its combo's total is worth the tier (it is, so the limit lets it
  /// in, as any valuable gift), else the gift is counted out of sight.
  GiftOutcome _addAboveTier(String? key, LiveMessage message, LiveGift? gift, DateTime now) {
    if (key == null || gift == null) return GiftOutcome.belowTier;
    final before = _unseen.remove(key);
    final going =
        before != null && now.difference(before.at) <= comboWindow && !giftComboRestarted(before.running, gift);
    final total = going ? giftComboTotal(before.total, gift) : giftComboStart(gift);
    final sends = going ? before.sends + 1 : 1;
    if (CombinedGift(gift, count: total, sends: sends).tier.index >= _minTier.index) {
      return _addLine(key, message, gift, now, total: total, sends: sends);
    }
    _unseen[key] = _Unseen(at: now, total: total, running: gift.comboTotal ?? before?.running, sends: sends);
    if (_unseen.length > _maxCombos) _unseen.remove(_unseen.keys.first);
    return GiftOutcome.belowTier;
  }

  bool _mayAddLine(DateTime now) {
    while (_newLines.isNotEmpty && now.difference(_newLines.first) >= _second) {
      _newLines.removeFirst();
    }
    return _newLines.length < linesPerSecond;
  }

  GiftOutcome _addLine(String? key, LiveMessage message, LiveGift? gift, DateTime now, {int? total, int sends = 1}) {
    _newLines.addLast(now);
    if (key == null || gift == null) {
      feed.add(ChatLine.gift(message));
      return GiftOutcome.added;
    }
    // Joined during a combo: the platform's count so far (or the count of
    // the gifts seen below the tier).
    final count = total ?? giftComboStart(gift);
    final line = ChatLine.gift(
      count == gift.count && sends == 1
          ? message
          : giftMessageWith(message, CombinedGift(gift, count: count, sends: sends)),
    );
    feed.add(line);
    _remember(key, _Combo(line, at: now, total: count, running: gift.comboTotal, sends: sends));
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
      giftMessageWith(message, CombinedGift(gift, count: total, sends: sends)),
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
  bool restartedBy(LiveGift gift) => giftComboRestarted(running, gift);
}

/// A combo counted out of sight below [GiftCombiner.minTier]: when its last
/// gift came, its count, the platform's running count, how many messages.
final class _Unseen {
  new({required this.at, required this.total, required this.running, required this.sends});

  final DateTime at;
  final int total;
  final int? running;
  final int sends;
}
