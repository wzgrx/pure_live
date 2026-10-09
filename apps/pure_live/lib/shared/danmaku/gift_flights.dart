import 'dart:async';
import 'dart:collection';

import 'package:live_core/live_core.dart';
import 'package:pure_live/shared/danmaku/gift_combo.dart';
import 'package:pure_live/shared/danmaku/gift_words.dart';

/// Which of a room's gifts fly over the picture ("飞行弹幕显示礼物", A08.12,
/// docs/A-界面设计/A08-弹幕界面/A08.12-礼物开关和飞行弹幕里的礼物; V03.5 §6.6, §6.8), so a busy room's
/// gifts never flood it:
///
/// - only gifts worth a mark ([LiveGiftTier.valuable] and up, the shown
///   total's tier as the gift line marks it);
/// - a combo (the chat list's combo, [giftComboKey] within [comboWindow])
///   flies twice at most: when it first is worth a mark, and once more when
///   it ends ([comboWindow] without another gift) if its total grew since
///   (a combo that climbs to the tier first flies when it gets there);
/// - at most [perSecond] a second; one over it does not fly (the chat list
///   still has it), and an ending combo waits for no one either.
///
/// What flies is handed to its `emit`: the gift's message holding the shown total
/// (a [CombinedGift] for a combo), its text the words the picture draws,
/// "名字 送出 礼物 ×N" ([giftSentence]). The flying layer draws a gift's
/// message in the gift look (`DanmakuOverlay`) in the same waiting line and
/// lanes as the chat, so "同屏最大弹幕条数" and the display range hold for both.
///
/// The room's controller and the multi-view's hand it the platform's gifts
/// that passed the filters, while the switch is on.
final class GiftFlights {
  /// Flies gifts by `emit`; `clock` times combos and the limit; `streamer`
  /// is the room's, who is not named as every gift's receiver.
  new({required this._clock, required this._emit, String Function()? streamer}) : _streamer = streamer ?? _nobody;

  /// Gifts that fly in one second, at most (V03.5 §6.8).
  static const int perSecond = 3;

  /// How long a combo waits for its next gift before it ends (the chat
  /// list's, D07.1).
  static const Duration comboWindow = Duration(seconds: 5);

  /// How often ended combos are looked for (tests' timers are 1 s or more).
  static const Duration sweep = Duration(seconds: 1);

  /// Combos remembered; the least recent goes first.
  static const int _maxCombos = 256;

  static const Duration _second = Duration(seconds: 1);

  static String _nobody() => '';

  final DateTime Function() _clock;
  final void Function(LiveMessage message) _emit;
  final String Function() _streamer;
  final LinkedHashMap<String, _Flight> _combos = LinkedHashMap();
  final ListQueue<DateTime> _flown = ListQueue();
  Timer? _sweeper;
  int _flights = 0;
  int _dropped = 0;

  /// Gifts that flew so far.
  int get flights => _flights;

  /// Gifts worth flying that did not, over [perSecond].
  int get dropped => _dropped;

  /// Combos waiting for their end.
  int get pending => _combos.length;

  /// Takes [message], a platform's gift.
  void add(LiveMessage message) {
    final gift = message.gift;
    if (gift == null || message.isLocal) return;
    final now = _clock();
    _endBefore(now);
    final key = giftComboKey(message, gift);
    var combo = _combos.remove(key);
    if (combo != null && giftComboRestarted(combo.running, gift)) {
      _end(combo);
      combo = null;
    }
    final total = combo == null ? giftComboStart(gift) : giftComboTotal(combo.total, gift);
    final sends = (combo?.sends ?? 0) + 1;
    final shown = total == gift.count && sends == 1 ? message : _shown(message, gift, total, sends);
    var flown = combo?.flown ?? 0;
    if (flown == 0 && _worthFlying(shown) && _fly(shown, now)) flown = total;
    _combos[key] = _Flight(shown, at: now, total: total, running: gift.comboTotal ?? combo?.running, sends: sends)
      ..flown = flown;
    if (_combos.length > _maxCombos) _combos.remove(_combos.keys.first);
    _sweeper ??= Timer.periodic(sweep, (_) => _endBefore(_clock()));
  }

  /// Forgets the combos without flying their ends (the switch went off,
  /// the danmaku closed).
  void clear() {
    _combos.clear();
    _flown.clear();
    _sweeper?.cancel();
    _sweeper = null;
  }

  /// Stops for good.
  void dispose() => clear();

  /// Ends the combos whose last gift came more than [comboWindow] before
  /// [now].
  void _endBefore(DateTime now) {
    if (_combos.isEmpty) return;
    final ended = [
      for (final MapEntry(:key, :value) in _combos.entries)
        if (now.difference(value.at) > comboWindow) key,
    ];
    for (final key in ended) {
      _end(_combos.remove(key)!, now: now);
    }
    if (_combos.isEmpty) {
      _sweeper?.cancel();
      _sweeper = null;
    }
  }

  /// A combo ended: its total flies when it grew since it flew (or it never
  /// flew and is worth it now).
  void _end(_Flight combo, {DateTime? now}) {
    if (combo.total == combo.flown || !_worthFlying(combo.message)) return;
    _fly(combo.message, now ?? _clock());
  }

  bool _worthFlying(LiveMessage message) {
    final gift = message.gift;
    return gift != null && giftShownTier(gift) != LiveGiftTier.normal;
  }

  bool _fly(LiveMessage message, DateTime now) {
    while (_flown.isNotEmpty && now.difference(_flown.first) >= _second) {
      _flown.removeFirst();
    }
    if (_flown.length >= perSecond) {
      _dropped++;
      return false;
    }
    _flown.addLast(now);
    _flights++;
    _emit(giftMessageWith(message, message.gift!, text: flyingGiftWords(message, streamer: _streamer())));
    return true;
  }

  static LiveMessage _shown(LiveMessage message, LiveGift gift, int total, int sends) =>
      giftMessageWith(message, CombinedGift(gift, count: total, sends: sends));
}

/// What a flying gift says: the sender's name and the gift's sentence,
/// "名字 送出 小心心 ×3" (the chat list's gift line in one run of text).
String flyingGiftWords(LiveMessage message, {String streamer = ''}) {
  final gift = message.gift;
  if (gift == null) return message.message;
  final name = message.userName.trim();
  final sentence = giftSentence(gift, streamer: streamer);
  return name.isEmpty ? sentence : '$name $sentence';
}

/// One combo on its way: its message holding the total so far, when its
/// last gift came, the platform's running count, how many messages, and
/// the total that flew (0 for none).
final class _Flight {
  new(this.message, {required this.at, required this.total, required this.running, required this.sends});

  final LiveMessage message;
  final DateTime at;
  final int total;
  final int? running;
  final int sends;
  int flown = 0;
}
