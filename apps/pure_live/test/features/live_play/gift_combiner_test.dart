// D07.1 c2, c3: a combo is one gift line whose count goes up, at most ten new
// gift lines a second, at most 150 gift lines among the feed's 500. A fake
// clock in seconds (D-017); the platforms' gifts from their recorded
// samples where there are some.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/gift_combiner.dart';

/// A scheduler run by hand: the flushes wait in [due].
final class _Frames {
  final List<VoidCallback> due = [];

  void schedule(VoidCallback flush) => due.add(flush);

  void frame() {
    final now = [...due];
    due.clear();
    for (final flush in now) {
      flush();
    }
  }
}

/// A feed, a combiner on it and the clock they share.
final class _Room {
  new() {
    feed = ChatFeed(giftCapacity: GiftCombiner.maxGiftLines, schedule: frames.schedule);
    gifts = GiftCombiner(feed: feed, clock: () => now);
  }

  final _Frames frames = _Frames();
  late final ChatFeed feed;
  late final GiftCombiner gifts;
  DateTime now = DateTime(2026, 10, 9, 20);

  void wait(int seconds) => now = now.add(Duration(seconds: seconds));

  void chat(int count) {
    for (var i = 0; i < count; i++) {
      feed.add(ChatLine.chat(_chat('聊天 $i')));
    }
  }

  List<ChatLine> get giftLines => [
    for (final line in feed.lines)
      if (line.kind == ChatLineKind.gift) line,
  ];
}

LiveMessage _chat(String text) =>
    LiveMessage(type: LiveMessageType.chat, userName: '观众', message: text, color: LiveMessageColor.white);

LiveMessage _gift(
  String user,
  String name, {
  String id = '',
  int count = 1,
  String comboKey = '',
  int? comboTotal,
  bool free = false,
  int? totalValue,
  LiveGiftUnit unit = LiveGiftUnit.other,
}) {
  final gift = LiveGift(
    name: name,
    id: id,
    count: count,
    comboKey: comboKey,
    comboTotal: comboTotal,
    free: free,
    totalValue: totalValue,
    unit: unit,
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

const String _fixtures = '../../fixtures';

/// The recorded frames of [sample] coming in, with their time in ms.
List<({int t, Uint8List bytes})> _frames(String sample) => [
  for (final line in File('$_fixtures/$sample/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': 'in', 't': final int t, 'b64': final String b64})
      (t: t, bytes: base64Decode(b64)),
];

/// A protobuf message of [fields] (SEND_GIFT_V2's): an `int` is a varint, a
/// `String` UTF-8 and a `List<int>` a nested message.
List<int> _pb(Map<int, Object> fields) {
  final out = <int>[];
  void varint(int value) {
    var rest = value;
    while (rest >= 0x80) {
      out.add(rest & 0x7f | 0x80);
      rest >>= 7;
    }
    out.add(rest);
  }

  for (final MapEntry(:key, :value) in fields.entries) {
    if (value is int) {
      varint(key << 3);
      varint(value);
      continue;
    }
    final bytes = value is String ? utf8.encode(value) : value as List<int>;
    varint(key << 3 | 2);
    varint(bytes.length);
    out.addAll(bytes);
  }
  return out;
}

/// A Bilibili notice packet (operation 5, uncompressed).
Uint8List _bilibili(Map<String, Object?> notice) {
  final body = utf8.encode(jsonEncode(notice));
  final bytes = Uint8List(16 + body.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, bytes.length)
    ..setUint16(4, 16)
    ..setUint16(6, 0)
    ..setUint32(8, 5)
    ..setUint32(12, 1);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

List<LiveMessage> _bilibiliMessages(Map<String, Object?> notice) => [
  for (final item in BilibiliDanmakuProtocol.decode(_bilibili(notice)).items)
    if (item case BilibiliDanmakuMessage(:final message)) message,
];

void main() {
  group('combos (c2)', () {
    test('the same key within 5 s counts on its line; at 6 s it is a new line', () {
      final room = _Room();
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.added);
      room.wait(4);
      expect(room.gifts.add(_gift('甲', '小心心', id: '1', count: 2)), GiftOutcome.merged);
      expect(room.giftLines.single.text, '小心心 ×3');
      room.wait(5);
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.merged, reason: '5 s after the last one');
      expect(room.giftLines.single.text, '小心心 ×4');
      room.wait(6);
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.added);
      expect(room.giftLines.map((line) => line.text), ['小心心 ×4', '小心心 ×1']);
    });

    test('without a combo key: by sender and gift; another sender or gift is a line of its own', () {
      final room = _Room();
      room.gifts
        ..add(_gift('甲', '小心心', id: '1'))
        ..add(_gift('乙', '小心心', id: '1'))
        ..add(_gift('甲', '辣条', id: '2'))
        ..add(_gift('甲', '小心心', id: '1'));
      expect(room.giftLines.map((line) => '${line.message!.userName} ${line.text}'), [
        '乙 小心心 ×1',
        '甲 辣条 ×1',
        '甲 小心心 ×2',
      ]);
      // No id: by name.
      room.gifts
        ..add(_gift('丙', '陪伴印章'))
        ..add(_gift('丙', '陪伴印章'));
      expect(room.giftLines.last.text, '陪伴印章 ×2');
    });

    test('the combo key beats the sender: two keys are two lines, one key across names is one', () {
      final room = _Room();
      room.gifts
        ..add(_gift('甲', '小心心', id: '1', comboKey: 'a'))
        ..add(_gift('甲', '小心心', id: '1', comboKey: 'b'))
        ..add(_gift('甲*', '小心心', id: '1', comboKey: 'a'));
      expect(room.giftLines.map((line) => line.text), ['小心心 ×1', '小心心 ×2']);
    });

    test('only within the last 20 lines', () {
      final room = _Room();
      room.gifts.add(_gift('甲', '小心心', id: '1'));
      room.chat(19);
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.merged, reason: '19 lines after it');
      room.chat(20);
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.added, reason: '20 lines after it');
      expect(room.giftLines.map((line) => line.text), ['小心心 ×2', '小心心 ×1']);
    });

    test("the platform's running count beats adding up; a count that went back is a new combo", () {
      final room = _Room();
      LiveMessage hit(int total) => _gift('甲', '粉丝荧光棒', id: '824', count: 10, comboKey: '甲:824', comboTotal: total);
      room.gifts
        ..add(hit(10))
        ..add(hit(20))
        ..add(hit(40));
      expect(room.giftLines.single.text, '粉丝荧光棒 ×40', reason: 'the hit of 30 was missed');
      room.gifts.add(hit(10));
      expect(room.giftLines.map((line) => line.text), ['粉丝荧光棒 ×40', '粉丝荧光棒 ×10']);
      // Joined during a combo: the count so far.
      room.gifts.add(_gift('乙', '粉丝荧光棒', id: '824', count: 10, comboKey: '乙:824', comboTotal: 350));
      expect(room.giftLines.last.text, '粉丝荧光棒 ×350');
      expect(room.giftLines.last.message!.gift!.count, 350);
    });

    test('totalOf: running counts of gifts (Douyu), of sends (Huya), of the whole combo (Bilibili)', () {
      LiveGift gift(int count, int? total) => LiveGift(name: 'g', count: count, comboTotal: total);
      expect(GiftCombiner.totalOf(10, gift(10, 20)), 20, reason: 'Douyu hits: gifts');
      expect(GiftCombiner.totalOf(20, gift(10, 40)), 40, reason: 'Douyu: a missed hit');
      expect(GiftCombiner.totalOf(4, gift(1, 5)), 5, reason: 'Huya iItemGroup: sends of one');
      expect(GiftCombiner.totalOf(10, gift(10, 2)), 20, reason: 'Huya: sends of ten');
      expect(GiftCombiner.totalOf(3, gift(1, null)), 4, reason: 'Bilibili SEND_GIFT: no running count');
      expect(GiftCombiner.totalOf(4, gift(5, 5)), 5, reason: 'Bilibili COMBO_SEND: the whole combo');
      expect(GiftCombiner.totalOf(6, gift(5, 5)), 6, reason: 'a summary behind the sends adds nothing');
    });

    test('a merge replaces the line: new id at the end, not added, revision up, the old one links to it', () {
      final room = _Room();
      var heard = 0;
      room.feed.addListener(() => heard++);
      room.gifts.add(_gift('甲', '小心心', id: '1'));
      room.chat(3);
      final first = room.giftLines.single;
      final added = room.feed.added;
      room.gifts
        ..add(_gift('甲', '小心心', id: '1'))
        ..add(_gift('甲', '小心心', id: '1'));
      final merged = room.giftLines.single;
      expect(room.feed.lines.last, same(merged), reason: 'at the bottom');
      expect(merged.text, '小心心 ×3');
      expect(merged.revision, 2);
      expect(first.revision, 0);
      expect(first.latest, same(merged));
      expect(first.replacement, isNotNull);
      expect(merged.replacement, isNull);
      expect(merged.id, greaterThan(room.feed.lines[room.feed.length - 2].id));
      expect(room.feed.added, added, reason: 'a merge is not a new message');
      expect(room.feed.replacements, 2);
      expect(room.feed.linesAfter(first), -1);
      expect(room.feed.linesAfter(merged), 0);
      expect(room.frames.due, hasLength(1));
      room.frames.frame();
      expect(heard, 1, reason: 'still once a frame');
      // The gift the line holds: the total, the latest message's sender.
      final gift = merged.message!.gift! as CombinedGift;
      expect((gift.count, gift.sends, gift.plainText, gift.last.count), (3, 3, '小心心 ×3', 1));
    });

    test('the value grows with the count, and so does the tier', () {
      final room = _Room();
      for (var i = 0; i < 20; i++) {
        room.gifts.add(_gift('甲', '小心心', id: '1', totalValue: 1000, unit: LiveGiftUnit.goldSeed));
      }
      final gift = room.giftLines.single.message!.gift!;
      expect((gift.count, gift.totalValue, gift.tier), (20, 20000, LiveGiftTier.valuable));
    });

    test('a gift without a LiveGift is a line of its own', () {
      final room = _Room();
      const bare = LiveMessage(
        type: LiveMessageType.gift,
        userName: '甲',
        message: '辣条 ×1',
        color: LiveMessageColor.white,
      );
      room.gifts
        ..add(bare)
        ..add(bare);
      expect(room.giftLines, hasLength(2));
    });
  });

  group('limits (c3)', () {
    test('15 different gifts in one second: 10 lines, 5 dropped; the next second there is room again', () {
      final room = _Room();
      for (var i = 0; i < 15; i++) {
        room.gifts.add(_gift('观众$i', '礼物$i', id: '$i'));
      }
      expect(room.giftLines, hasLength(GiftCombiner.linesPerSecond));
      expect(room.gifts.dropped, 5);
      room.wait(1);
      expect(room.gifts.add(_gift('观众x', '礼物x', id: 'x')), GiftOutcome.added);
    });

    test('over the limit a paid gift counts on its line wherever it is; a free one is dropped', () {
      final room = _Room();
      room.gifts
        ..add(_gift('甲', '小心心', id: '1'))
        ..add(_gift('乙', '辣条', id: '2', free: true));
      room
        ..chat(30)
        ..wait(1);
      for (var i = 0; i < 10; i++) {
        room.gifts.add(_gift('观众$i', '礼物$i', id: '$i'));
      }
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.merged, reason: '30 lines up, still counted');
      expect(room.gifts.add(_gift('乙', '辣条', id: '2', free: true)), GiftOutcome.dropped);
      expect(room.gifts.add(_gift('丙', '辣条', id: '2', free: true)), GiftOutcome.dropped);
      expect(room.gifts.add(_gift('丁', '礼物x', id: 'x')), GiftOutcome.dropped, reason: 'paid, but no line');
      expect(room.gifts.dropped, 3);
      expect(room.giftLines.last.text, '小心心 ×2');
    });

    test('over the limit a valuable gift still gets its line', () {
      final room = _Room();
      for (var i = 0; i < 10; i++) {
        room.gifts.add(_gift('观众$i', '礼物$i', id: '$i'));
      }
      final guard = _gift('甲', '舰长', id: '10003', totalValue: 198000, unit: LiveGiftUnit.goldSeed);
      expect(guard.gift!.tier, LiveGiftTier.precious);
      expect(room.gifts.add(guard), GiftOutcome.added);
    });

    test('at most 150 gift lines: the oldest gift line goes, not a chat line', () {
      final room = _Room()..chat(100);
      for (var i = 0; i < 151; i++) {
        if (i % 10 == 0) room.wait(1);
        room.gifts.add(_gift('观众$i', '礼物$i', id: '$i'));
      }
      expect(room.feed.giftLines, GiftCombiner.maxGiftLines);
      expect(room.giftLines, hasLength(150));
      expect(room.giftLines.first.text, '礼物1 ×1', reason: 'the first gift went');
      expect(room.feed.lines.where((line) => line.kind == ChatLineKind.chat), hasLength(100));
      expect(room.feed.length, 250);
      // Beyond the 500: the oldest of any kind, as before.
      room.chat(300);
      expect(room.feed.length, 500);
      expect(room.feed.giftLines, room.giftLines.length);
    });

    test('a removal keeps the gift count; a gift line removed is not merged into', () {
      final room = _Room();
      room.gifts.add(_gift('甲', '小心心', id: '1'));
      room.feed.removeWhere((line) => line.kind == ChatLineKind.gift);
      expect(room.feed.giftLines, 0);
      expect(room.gifts.add(_gift('甲', '小心心', id: '1')), GiftOutcome.added);
      expect(room.giftLines.single.text, '小心心 ×1');
    });
  });

  group('platforms (recorded samples)', () {
    test('Douyu S13-live at its recorded times: the combos are a few lines, each at its last hits', () {
      final room = _Room();
      final start = room.now;
      var gifts = 0;
      final lastHits = <String, int>{};
      for (final frame in _frames('douyu/danmaku/S13-live')) {
        room.now = start.add(Duration(milliseconds: frame.t));
        for (final message in DouyuDanmakuProtocol.decode(frame.bytes, roomId: '9999')) {
          if (message.type == LiveMessageType.chat) {
            room.feed.add(ChatLine.chat(message));
          } else if (message.type == LiveMessageType.gift) {
            gifts++;
            room.gifts.add(message);
            if (message.data case DouyuGift(:final combo) when combo > 0) lastHits[message.userId] = combo;
          }
        }
      }
      expect(gifts, 125);
      final lines = room.giftLines;
      // The numbers go to the record (D07.1 record.md).
      // ignore: avoid_print
      print('Douyu S13-live: $gifts gifts, ${lines.length} lines, ${room.gifts.dropped} dropped');
      expect(lines, hasLength(26), reason: 'was a line each');
      expect(room.gifts.dropped, 0);
      // The longest combo (61721176, 31 hits of 10) ends at its last hits.
      final longest = lines.lastWhere((line) => line.message!.userId == '61721176');
      expect(longest.message!.gift!.count, lastHits['61721176']);
    });

    test("Huya S18-gift: one viewer's 虎粮 combo is one line at 19; separate sends of 10 and 5 stay apart", () {
      final room = _Room();
      final start = room.now;
      for (final frame in _frames('huya/danmaku/S18-gift')) {
        room.now = start.add(Duration(milliseconds: frame.t));
        HuyaDanmakuProtocol.decode(frame.bytes).messages.forEach(room.gifts.add);
      }
      final lines = room.giftLines.map((line) => '${line.message!.userId} ${line.text}').toList();
      expect(lines, contains('7482778489185 虎粮 ×19'), reason: 'iItemGroup 1…17, 19 (18 missed)');
      expect(lines.where((line) => line.startsWith('7482778489185 ')), hasLength(1));
      expect(lines, containsAllInOrder(['9396536651700 虎粮 ×10', '9396536651700 虎粮 ×5']));
      expect(room.giftLines, hasLength(27 - 18 + 1), reason: '27 gifts, 18 of them one combo');
    });

    test(
      'Bilibili guests S13-guest-gifts (D07.4) at its recorded times: SEND_GIFT_V2 sends and COMBO_SEND are one line',
      () {
        final room = _Room();
        final start = room.now;
        var gifts = 0;
        for (final frame in _frames('bilibili/danmaku/S13-guest-gifts')) {
          room.now = start.add(Duration(milliseconds: frame.t));
          for (final item in BilibiliDanmakuProtocol.decode(frame.bytes).items) {
            if (item case BilibiliDanmakuMessage(:final message) when message.type == LiveMessageType.gift) {
              gifts++;
              room.gifts.add(message);
            }
          }
        }
        expect(gifts, 51, reason: '50 SEND_GIFT_V2 and one COMBO_SEND');
        final lines = room.giftLines;
        expect(lines, hasLength(49), reason: 'two sends of one combo and its COMBO_SEND are one line');
        expect(room.gifts.dropped, 0);
        final fries = lines.where((line) => line.message!.gift!.name == '薯条').toList();
        expect(fries.map((line) => line.text), [
          '薯条 ×2',
          '薯条 ×1',
        ], reason: 'two sends, then COMBO_SEND (total_num 2) 5.15 s later on the same line; a later send apart');
        expect(fries.first.message!.gift, isA<CombinedGift>().having((gift) => gift.sends, 'sends', 2));
        expect(
          (fries.first.message!.gift!.totalValue, fries.first.message!.gift!.iconUrl.toString()),
          (200, 'https://s1.hdslb.com/bfs/live/931e985f8637e5f190e54a832fca7889b4585b87.png'),
        );
        expect(lines.every((line) => BilibiliDanmakuProtocol.isMaskedName(line.message!.userName)), isTrue);
      },
    );

    test(
      "D07.4: Bilibili's COMBO_SEND, which comes after the combo ended, counts on its line for 15 s, wherever it is",
      () {
        Map<String, Object?> send(String combo) => {
          'cmd': 'SEND_GIFT_V2',
          'data': {
            'pb': base64Encode(
              _pb({
                2: '观***',
                10: _pb({1: 35969, 2: '薯条', 3: 1, 5: 100, 7: 100, 8: 'gold', 12: combo}),
              }),
            ),
          },
        };
        Map<String, Object?> summary(String combo, int total) => {
          'cmd': 'COMBO_SEND',
          'data': {
            'gift_name': '薯条',
            'gift_id': 35969,
            'total_num': total,
            'combo_total_coin': total * 100,
            'uname': '观***',
            'uid': 0,
            'batch_combo_id': combo,
          },
        };
        final room = _Room();
        _bilibiliMessages(send('a')).forEach(room.gifts.add);
        room.wait(4);
        _bilibiliMessages(send('a')).forEach(room.gifts.add);
        room
          ..wait(6)
          ..chat(30);
        _bilibiliMessages(summary('a', 2)).forEach(room.gifts.add);
        expect(room.giftLines.single.text, '薯条 ×2', reason: '6 s later and 30 lines up: still its line');
        room.wait(9);
        _bilibiliMessages(summary('a', 3)).forEach(room.gifts.add);
        expect(room.giftLines.single.text, '薯条 ×3', reason: 'a send it missed');
        room.wait(16);
        _bilibiliMessages(summary('a', 3)).forEach(room.gifts.add);
        expect(room.giftLines, hasLength(2), reason: 'after 15 s a line of its own');
        // A send (not a summary) 6 s later is a new combo as before.
        _bilibiliMessages(send('b')).forEach(room.gifts.add);
        room.wait(6);
        _bilibiliMessages(send('b')).forEach(room.gifts.add);
        expect(room.giftLines, hasLength(4));
      },
    );

    test('Bilibili: every SEND_GIFT of a combo counts, COMBO_SEND sets the total', () {
      final room = _Room();
      Map<String, Object?> send(int num) => {
        'cmd': 'SEND_GIFT',
        'data': {
          'giftName': '小心心',
          'giftId': 30607,
          'num': num,
          'uname': '观众',
          'uid': 1,
          'coin_type': 'gold',
          'total_coin': 1000 * num,
          'batch_combo_id': 'batch:gift:combo_id:1',
        },
      };
      for (var i = 0; i < 4; i++) {
        _bilibiliMessages(send(1)).forEach(room.gifts.add);
      }
      expect(room.giftLines.single.text, '小心心 ×4');
      _bilibiliMessages({
        'cmd': 'COMBO_SEND',
        'data': {
          'gift_name': '小心心',
          'gift_id': 30607,
          'total_num': 5,
          'combo_total_coin': 5000,
          'uname': '观众',
          'uid': 1,
          'batch_combo_id': 'batch:gift:combo_id:1',
        },
      }).forEach(room.gifts.add);
      final line = room.giftLines.single;
      expect(line.text, '小心心 ×5', reason: 'the send it missed');
      expect((line.message!.gift!.totalValue, line.message!.gift!.unit), (5000, LiveGiftUnit.goldSeed));
      _bilibiliMessages(send(1)).forEach(room.gifts.add);
      expect(room.giftLines.single.text, '小心心 ×6');
    });
  });
}
