// A08.12 (docs/A-界面设计/A08-弹幕界面/A08.12-礼物开关和飞行弹幕里的礼物): which gifts fly over the
// picture. Only the valuable ones; a combo flies when it first is worth it
// and once more with its total when it ends; at most 3 a second. A fake
// clock in seconds (D-017).
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/shared/danmaku/gift_combo.dart';
import 'package:pure_live/shared/danmaku/gift_flights.dart';

import '../support.dart';

/// The gate, what it flew and the clock it reads.
final class _Picture {
  new({String streamer = ''}) {
    flights = GiftFlights(clock: () => now, emit: flown.add, streamer: () => streamer);
    addTearDown(flights.dispose);
  }

  late final GiftFlights flights;
  final List<LiveMessage> flown = [];
  DateTime now = DateTime(2026, 10, 9, 20);

  void wait(num seconds) => now = now.add(Duration(milliseconds: (seconds * 1000).round()));

  List<String> get words => [for (final message in flown) message.message];
}

/// [count] of a gift worth [value] gold seeds in all (1000 a yuan).
LiveMessage _gift(
  String user,
  String name, {
  int count = 1,
  int value = 0,
  String comboKey = '',
  int? comboTotal,
  bool free = false,
  int? unitPrice,
  String receiver = '',
}) {
  final gift = LiveGift(
    name: name,
    id: name,
    count: count,
    comboKey: comboKey,
    comboTotal: comboTotal,
    unitPrice: unitPrice,
    totalValue: value == 0 ? null : value,
    unit: LiveGiftUnit.goldSeed,
    free: free,
    receiverName: receiver,
  );
  return LiveMessage(
    type: LiveMessageType.gift,
    userName: user,
    userId: user,
    message: gift.plainText,
    color: LiveMessageColor.white,
    data: gift,
  );
}

void main() {
  setUpAll(loadStrings);

  test('only gifts worth a mark fly; free, cheap, local and unknown ones do not', () {
    final picture = _Picture();
    picture.flights
      ..add(_gift('甲', '小心心', count: 3, value: 3000)) // 3 yuan
      ..add(_gift('乙', '辣条', count: 5, free: true))
      ..add(_gift('丙', '礼物')) // no value
      ..add(
        const LiveMessage(
          type: LiveMessageType.gift,
          userName: '本机',
          message: '火箭 ×1',
          color: LiveMessageColor.white,
          isLocal: true,
          data: LiveGift(name: '火箭', totalValue: 500000, unit: LiveGiftUnit.goldSeed),
        ),
      )
      ..add(_gift('丁', '告白气球', value: 52000)); // 52 yuan
    expect(picture.words, ['丁 送出 告白气球 ×1']);
    final flown = picture.flown.single;
    expect((flown.type, flown.userName, flown.gift!.tier), (LiveMessageType.gift, '丁', LiveGiftTier.valuable));
  });

  test("the words: the name and the gift line's sentence; the streamer is not named as receiver", () {
    final picture = _Picture(streamer: '主播');
    picture.flights
      ..add(_gift('甲', '飞机', value: 100000, receiver: '主播'))
      ..add(_gift('乙', '飞机', value: 100000, receiver: '嘉宾'));
    expect(picture.words, ['甲 送出 飞机 ×1', '乙 送给 嘉宾 飞机 ×1']);
    expect(flyingGiftWords(_gift('', '飞机', value: 100000)), '送出 飞机 ×1', reason: 'no name: the sentence');
  });

  test('no flood under a combo: 30 hits fly once at the start and once with the total at the end', () {
    final picture = _Picture();
    for (var i = 0; i < 30; i++) {
      picture.flights.add(_gift('甲', '告白气球', value: 52000, comboKey: 'c1'));
      picture.wait(0.3);
    }
    expect(picture.words, ['甲 送出 告白气球 ×1'], reason: 'the first hit, nothing while it goes on');
    expect(picture.flights.pending, 1);
    picture.wait(6);
    // Any later gift ends the combos it finds over.
    picture.flights.add(_gift('乙', '小心心', value: 1000));
    expect(picture.words, ['甲 送出 告白气球 ×1', '甲 送出 告白气球 ×30']);
    final total = picture.flown.last.gift!;
    expect(total, isA<CombinedGift>());
    expect((total.count, total.totalValue, total.tier), (30, 52000 * 30, LiveGiftTier.precious));
  });

  test("D07.4: Bilibili's COMBO_SEND after the combo ended does not fly the same total again", () {
    final picture = _Picture();
    for (var i = 0; i < 5; i++) {
      picture.flights.add(_gift('甲', '告白气球', value: 52000, comboKey: 'b1'));
      picture.wait(0.3);
    }
    picture.wait(5.5);
    picture.flights.add(_gift('乙', '小心心', value: 1000));
    expect(picture.words, ['甲 送出 告白气球 ×1', '甲 送出 告白气球 ×5']);
    // The summary comes about 5 s after the last send (field combo_stay_time).
    picture.flights.add(_gift('甲', '告白气球', count: 5, value: 260000, comboKey: 'b1', comboTotal: 5));
    picture.wait(6);
    picture.flights.add(_gift('乙', '小心心', value: 1000));
    expect(picture.words, ['甲 送出 告白气球 ×1', '甲 送出 告白气球 ×5'], reason: 'no third flight');
    // A summary that is bigger than what flew (sends the room missed) flies.
    picture.flights.add(_gift('甲', '告白气球', count: 8, value: 416000, comboKey: 'b1', comboTotal: 8));
    expect(picture.words.last, '甲 送出 告白气球 ×8');
  });

  test("a single gift flies once; the platform's running count is the total", () {
    final picture = _Picture();
    picture.flights.add(_gift('甲', '飞机', value: 100000));
    picture.wait(6);
    picture.flights.add(_gift('乙', '小心心', value: 1000));
    expect(picture.words, ['甲 送出 飞机 ×1'], reason: 'nothing grew: no second flight');

    // Joined during a combo the platform counts (Douyu hits): its count.
    final joined = _Picture();
    joined.flights.add(_gift('甲', '荧光棒', unitPrice: 2000, value: 2000, comboTotal: 37));
    expect(joined.words, ['甲 送出 荧光棒 ×37']);
  });

  test('a cheap combo flies when its total gets worth it, and with its total at the end', () {
    final picture = _Picture();
    for (var i = 0; i < 12; i++) {
      picture.flights.add(_gift('甲', '牛哇', value: 1000, comboKey: 'c2')); // 1 yuan each
      picture.wait(1);
    }
    expect(picture.words, ['甲 送出 牛哇 ×10'], reason: '10 yuan: valuable from the tenth');
    picture.wait(6);
    picture.flights.add(_gift('乙', '小心心', value: 1000));
    expect(picture.words, ['甲 送出 牛哇 ×10', '甲 送出 牛哇 ×12']);
  });

  test('a combo whose platform count went back is a new combo', () {
    final picture = _Picture();
    picture.flights
      ..add(_gift('甲', '飞机', value: 100000, comboKey: 'k', comboTotal: 1))
      ..add(_gift('甲', '飞机', value: 100000, comboKey: 'k', comboTotal: 2))
      ..add(_gift('甲', '飞机', value: 100000, comboKey: 'k', comboTotal: 1));
    expect(picture.words, ['甲 送出 飞机 ×1', '甲 送出 飞机 ×2', '甲 送出 飞机 ×1']);
  });

  test('at most 3 a second; the fourth does not fly, the next second takes 3 again', () {
    final picture = _Picture();
    for (var i = 0; i < 5; i++) {
      picture.flights.add(_gift('观众$i', '飞机', value: 100000));
    }
    expect(picture.flown, hasLength(GiftFlights.perSecond));
    expect(picture.flights.dropped, 2);
    picture.wait(1);
    for (var i = 5; i < 10; i++) {
      picture.flights.add(_gift('观众$i', '飞机', value: 100000));
    }
    expect(picture.flown, hasLength(6));
    expect(picture.flights.flights, 6);
  });

  test('clear forgets the combos: their ends do not fly', () {
    final picture = _Picture();
    picture.flights
      ..add(_gift('甲', '告白气球', value: 52000, comboKey: 'c'))
      ..add(_gift('甲', '告白气球', value: 52000, comboKey: 'c'))
      ..clear();
    picture.wait(6);
    picture.flights.add(_gift('乙', '小心心', value: 1000));
    expect(picture.words, ['甲 送出 告白气球 ×1']);
    picture.flights.dispose();
  });

  testWidgets('a combo ends by itself: the sweep flies its total about 5 s after its last gift', (tester) async {
    final picture = _Picture();
    picture.flights
      ..add(_gift('甲', '告白气球', value: 52000, comboKey: 'c'))
      ..add(_gift('甲', '告白气球', value: 52000, comboKey: 'c', count: 4));
    expect(picture.words, ['甲 送出 告白气球 ×1']);
    for (var i = 0; i < 5; i++) {
      picture.wait(1);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(picture.flown, hasLength(1), reason: '5 s: it may still go on');
    picture.wait(1);
    await tester.pump(const Duration(seconds: 1));
    expect(picture.words, ['甲 送出 告白气球 ×1', '甲 送出 告白气球 ×5']);
    expect(picture.flights.pending, 0, reason: 'the sweep stops with no combo left');
    picture.flights.dispose();
  });
}
