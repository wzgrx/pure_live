import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// H01.8: gifts and super chats in the recorded chat XML
/// (docs/H-录制/H01-录制核心/H01.8-弹幕XML带礼物/README.md).

final _start = DateTime.utc(2026, 10, 1, 12);

LiveMessage _chat(String text, {String user = 'u'}) =>
    LiveMessage(type: LiveMessageType.chat, userName: user, message: text, color: LiveMessageColor.white);

LiveMessage _gift(LiveGift gift, {String user = 'fan', String userId = '7'}) => LiveMessage(
  type: LiveMessageType.gift,
  userName: user,
  userId: userId,
  message: gift.plainText,
  color: LiveMessageColor.white,
  data: gift,
);

LiveMessage _superChat({
  required int price,
  String user = '甲',
  String text = '加油',
  String priceText = '',
  String id = '',
  bool replayed = false,
}) => LiveMessage(
  type: LiveMessageType.superChat,
  userName: 'SUPER_CHAT_MESSAGE',
  message: 'SUPER_CHAT_MESSAGE',
  color: LiveMessageColor.white,
  replayed: replayed,
  data: LiveSuperChatMessage(
    messageId: id,
    userName: user,
    face: '',
    message: text,
    price: price,
    priceText: priceText,
    startTime: _start,
    endTime: _start.add(const Duration(seconds: 60)),
    backgroundColor: '',
    backgroundBottomColor: '',
  ),
);

DateTime _at(int ms) => _start.add(Duration(milliseconds: ms));

/// The entries of [text] (the lines between the header and `</i>`).
List<String> _entries(String text) => text
    .split('\n')
    .where((line) => line.startsWith('<d ') || line.startsWith('<gift ') || line.startsWith('<sc '))
    .toList();

double _ts(String entry) {
  final match = RegExp('^<d p="([0-9.]+),|ts="([0-9.]+)"').firstMatch(entry)!;
  return double.parse(match.group(1) ?? match.group(2)!);
}

void main() {
  late Directory folder;
  var now = _start;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('live_record_gifts_');
    now = _start;
  });
  tearDown(() => folder.delete(recursive: true));

  /// Runs [body] with `clock.now()` reading [now].
  Future<T> timed<T>(Future<T> Function() body) => withClock(Clock(() => now), body);

  Future<RecordChatWriter> open({String platform = 'bilibili', String name = 'a.xml'}) =>
      RecordChatWriter.open(File(p.join(folder.path, name)), startedAt: _start, platform: platform);

  test('without gifts the file is byte for byte what it was before H01.8', () async {
    // Written by the writer of master e562e5233 (before H01.8) from the
    // same messages.
    const before =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<i>\n'
        '<chatserver>pure_live</chatserver>\n'
        '<d p="0.007,1,25,16777215,1790856000,0,33caace8,0" user="甲">你好 &lt;b&gt;</d>\n'
        '<d p="1.507,1,25,16711680,1790856003,0,1ad37950,0" user="B &quot;q&quot;">x &amp; y</d>\n'
        '<d p="4.507,1,25,16777215,1790856004,0,2d131f5b,0" user="d">emoji 😀</d>\n'
        '</i>\n';
    final writer = await open();
    final messages = [
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: '甲',
        userId: '42',
        message: '你好 <b>',
        color: LiveMessageColor.white,
      ),
      LiveMessage(
        type: LiveMessageType.chat,
        userName: 'B "q"',
        message: 'x & y',
        color: const LiveMessageColor(255, 0, 0),
        sentAt: DateTime.utc(2026, 10, 1, 12, 0, 3),
      ),
      const LiveMessage(type: LiveMessageType.chat, userName: 'c', message: '   ', color: LiveMessageColor.white),
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'd',
        userId: 'abc',
        message: 'emoji 😀\u0001',
        color: LiveMessageColor.white,
      ),
    ];
    await timed(() async {
      for (final (i, message) in messages.indexed) {
        writer.add(message, receivedAt: _at(1500 * i + 7));
        if (i == 1) {
          await writer.flush();
          // Already written: nothing is held back without gifts.
          expect(_entries(await writer.file.readAsString()), hasLength(2));
        }
      }
      await writer.close();
    });
    expect(await writer.file.readAsString(), before);
    expect(writer.paidCount, 0);
  });

  test("a gift: BililiveRecorder's <gift>, price in thousandths of a yuan, the platform's value and unit", () async {
    final writer = await open();
    await timed(() async {
      writer
        ..add(
          _gift(const LiveGift(name: '小心心', unitPrice: 100, totalValue: 300, count: 3, unit: LiveGiftUnit.goldSeed)),
          receivedAt: _at(2500),
        )
        ..add(
          _gift(
            const LiveGift(name: '辣条', totalValue: 100, unit: LiveGiftUnit.silverSeed, free: true),
            user: 'b',
          ),
          receivedAt: _at(2600),
        )
        ..add(
          _gift(const LiveGift(name: '虎粮', totalValue: 10), user: 'c'),
          receivedAt: _at(2700),
        )
        ..add(
          _gift(
            const LiveGift(name: 'Bits', count: 100, totalValue: 100, unit: LiveGiftUnit.bits),
            user: 'e',
          ),
          receivedAt: _at(2800),
        )
        ..add(
          _gift(
            const LiveGift(name: '鱼丸', unitPrice: 10, unit: LiveGiftUnit.fen),
            user: 'f',
          ),
          receivedAt: _at(2900),
        )
        ..add(_gift(const LiveGift(name: '无名')), receivedAt: _at(3000))
        // Not a platform's gift: nothing.
        ..add(
          const LiveMessage(type: LiveMessageType.gift, userName: 'x', message: '辣条 ×1', color: LiveMessageColor.white),
          receivedAt: _at(3100),
        );
      await writer.flush();
      expect(_entries(await writer.file.readAsString()), isEmpty, reason: 'a combo is written once it is over');
      now = _at(3000 + 5000);
      await writer.flush();
    });
    final entries = _entries(await writer.file.readAsString());
    expect(entries, [
      '<gift ts="2.500" user="fan" giftname="小心心" giftcount="3" price="300" value="300" unit="goldSeed" />',
      '<gift ts="2.600" user="b" giftname="辣条" giftcount="1" price="0" value="100" unit="silverSeed" />',
      '<gift ts="2.700" user="c" giftname="虎粮" giftcount="1" value="10" unit="other" />',
      '<gift ts="2.800" user="e" giftname="Bits" giftcount="100" value="100" unit="bits" />',
      '<gift ts="2.900" user="f" giftname="鱼丸" giftcount="1" price="100" value="10" unit="fen" />',
      '<gift ts="3.000" user="fan" giftname="无名" giftcount="1" />',
    ]);
    expect(writer.paidCount, 6);
    expect(writer.count, 0, reason: 'the room\'s "弹幕 N 条" counts chat only');
    await writer.close();
  });

  test('escaping: names and gift names; a blank in a gift name is a no-break space (DanmakuFactory)', () async {
    final writer = await open();
    await timed(() async {
      writer
        ..add(
          _gift(const LiveGift(name: 'A&B <x> "q"'), user: "<O'Neil & \"co\">\u0001"),
          receivedAt: _at(1000),
        )
        ..add(
          _gift(const LiveGift(name: 'Super  Sticker\t1'), user: 'y'),
          receivedAt: _at(1100),
        );
      await writer.close();
    });
    final entries = _entries(await writer.file.readAsString());
    const user = '&lt;O&apos;Neil &amp; &quot;co&quot;&gt;';
    expect(entries, [
      '<gift ts="1.000" user="$user" giftname="A&amp;B\u00A0&lt;x&gt;\u00A0&quot;q&quot;" giftcount="1" />',
      '<gift ts="1.100" user="y" giftname="Super\u00A0\u00A0Sticker\u00A01" giftcount="1" />',
    ]);
  });

  test('a combo is one entry at its first gift with its count; a restart is a new one', () async {
    final writer = await open(platform: 'douyu');
    // Douyu: `hits` is the running count, the key is the sender and gift.
    LiveGift hits(int total) => LiveGift(
      name: '荧光棒',
      id: '824',
      count: 10,
      comboTotal: total,
      comboKey: '7:824',
      unitPrice: 10,
      unit: LiveGiftUnit.fen,
    );
    await timed(() async {
      for (var i = 1; i <= 6; i++) {
        now = _at(1000 * i);
        writer.add(_gift(hits(10 * i)), receivedAt: now);
        if (i == 3) await writer.flush();
      }
      // The count went back: a new combo.
      now = _at(7000);
      writer
        ..add(_gift(hits(10)), receivedAt: now)
        // Another sender's gifts without a platform key are their own combo.
        ..add(
          _gift(
            const LiveGift(name: '鱼丸'),
            user: 'b',
            userId: '8',
          ),
          receivedAt: now,
        )
        ..add(
          _gift(
            const LiveGift(name: '鱼丸'),
            user: 'b',
            userId: '8',
          ),
          receivedAt: _at(7500),
        );
      now = _at(13000);
      await writer.flush();
    });
    expect(_entries(await writer.file.readAsString()), [
      '<gift ts="1.000" user="fan" giftname="荧光棒" giftcount="60" price="6000" value="600" unit="fen" />',
      '<gift ts="7.000" user="fan" giftname="荧光棒" giftcount="10" price="1000" value="100" unit="fen" />',
      '<gift ts="7.000" user="b" giftname="鱼丸" giftcount="2" />',
    ]);
    await writer.close();
  });

  test('a combo summary after the combo was written adds only what it had not counted (D07.4)', () async {
    final writer = await open();
    LiveGift send() => const LiveGift(name: '粉丝团灯牌', comboKey: 'batch-1', unitPrice: 1000, unit: LiveGiftUnit.goldSeed);
    LiveGift summary(int total) => LiveGift(
      name: '粉丝团灯牌',
      count: total,
      comboTotal: total,
      comboKey: 'batch-1',
      unitPrice: 1000,
      unit: LiveGiftUnit.goldSeed,
    );
    await timed(() async {
      for (var i = 0; i < 4; i++) {
        now = _at(1000 + 200 * i);
        writer.add(_gift(send()), receivedAt: now);
      }
      now = _at(1600 + 5100);
      await writer.flush(); // The combo is over: ×4.
      now = _at(1600 + 5150);
      writer.add(_gift(summary(4)), receivedAt: now); // COMBO_SEND: nothing new.
      now = _at(1600 + 5200);
      writer.add(_gift(summary(5)), receivedAt: now); // One send was missed.
      now = _at(20000);
      await writer.flush();
      // Long after: a new combo of the same key.
      writer.add(_gift(send()), receivedAt: now);
      await writer.close();
    });
    expect(_entries(await writer.file.readAsString()), [
      '<gift ts="1.000" user="fan" giftname="粉丝团灯牌" giftcount="4" price="4000" value="4000" unit="goldSeed" />',
      '<gift ts="6.800" user="fan" giftname="粉丝团灯牌" giftcount="1" price="1000" value="1000" unit="goldSeed" />',
      '<gift ts="20.000" user="fan" giftname="粉丝团灯牌" giftcount="1" price="1000" value="1000" unit="goldSeed" />',
    ]);
  });

  test('chat during an open combo waits behind it: the file stays in time order and complete', () async {
    final writer = await open();
    await timed(() async {
      writer.add(_chat('before'), receivedAt: _at(500));
      now = _at(1000);
      writer.add(_gift(const LiveGift(name: '花')), receivedAt: now);
      for (var i = 1; i <= 5; i++) {
        now = _at(1000 + 1000 * i);
        writer.add(_chat('during $i'), receivedAt: now);
        if (i == 2) writer.add(_gift(const LiveGift(name: '花')), receivedAt: now);
        await writer.flush();
        final text = await writer.file.readAsString();
        expect(text, endsWith('</i>\n'));
        expect(_entries(text), [
          '<d p="0.500,1,25,16777215,1790856000,0,${'u'.hashCode.toUnsigned(32).toRadixString(16)},0" user="u">before</d>',
        ]);
      }
      now = _at(3000 + 5000);
      await writer.flush();
    });
    final entries = _entries(await writer.file.readAsString());
    expect(entries.map(_ts), [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
    expect(entries[1], '<gift ts="1.000" user="fan" giftname="花" giftcount="2" />');
    expect(entries.last, contains('>during 5</d>'));
    expect(writer.count, 6);
    await writer.close();
  });

  test('a combo going on for longer than maxComboSpan is written in parts', () async {
    final writer = await open();
    await timed(() async {
      for (var second = 0; second < 45; second++) {
        now = _at(1000 * second);
        writer
          ..add(_gift(const LiveGift(name: '小花花')), receivedAt: now)
          ..add(_chat('c$second'), receivedAt: now);
        if (second.isEven) await writer.flush();
      }
      final written = _entries(await writer.file.readAsString());
      expect(written.where((entry) => entry.startsWith('<gift ')), [
        '<gift ts="0.000" user="fan" giftname="小花花" giftcount="31" />',
      ]);
      expect(written.where((entry) => entry.startsWith('<d ')).length, greaterThanOrEqualTo(30));
      await writer.close();
    });
    final entries = _entries(await writer.file.readAsString());
    expect(entries.where((entry) => entry.startsWith('<gift ')), [
      '<gift ts="0.000" user="fan" giftname="小花花" giftcount="31" />',
      '<gift ts="31.000" user="fan" giftname="小花花" giftcount="14" />',
    ]);
    final times = entries.map(_ts).toList();
    expect(times, orderedEquals([...times]..sort()));
    expect(entries.where((entry) => entry.startsWith('<d ')), hasLength(45));
  });

  test("super chats: <sc> with price in thousandths of a yuan where it is yuan, else the platform's number", () async {
    final bilibili = await open();
    final huya = await open(platform: 'huya', name: 'b.xml');
    await timed(() async {
      bilibili
        ..add(
          _superChat(price: 30, text: '主播 <加油> & "好"', id: '1'),
          receivedAt: _at(4200),
        )
        ..add(
          _superChat(price: 30, text: '主播 <加油> & "好"', id: '1'),
          receivedAt: _at(4300),
        )
        ..add(_superChat(price: 50, id: '2', replayed: true), receivedAt: _at(4400));
      huya
        ..add(_superChat(price: 1000, priceText: '1,000 虎粮'), receivedAt: _at(100))
        ..add(
          _superChat(price: 0, user: '乙', text: ''),
          receivedAt: _at(200),
        );
      await bilibili.close();
      await huya.close();
    });
    expect(_entries(await bilibili.file.readAsString()), [
      '<sc ts="4.200" user="甲" price="30000" time="60">主播 &lt;加油&gt; &amp; &quot;好&quot;</sc>',
    ]);
    expect(bilibili.paidCount, 1);
    expect(_entries(await huya.file.readAsString()), [
      '<sc ts="0.100" user="甲" time="60" value="1000" pricetext="1,000 虎粮">加油</sc>',
      '<sc ts="0.200" user="乙" time="60"></sc>',
    ]);
  });

  test('the recorder writes the gifts and super chats the connector delivers, and nothing else', () async {
    void Function(LiveMessage message)? deliver;
    final chat = RecordChatRecorder(
      enabled: () => true,
      connect: (task, {required onMessage, required onEnded}) async {
        deliver = onMessage;
        return RecordChatConnection(stop: () async {});
      },
    );
    addTearDown(chat.dispose);
    final task = RecordTask(
      taskId: 'bilibili_1',
      roomId: '1',
      platform: 'bilibili',
      title: 't',
      nick: 'n',
      avatar: '',
      cover: '',
      createTime: _start,
      status: RecordStatus.running,
    )..outputDir = folder.path;
    chat.sync([task]);
    for (var i = 0; i < 500 && (chat.fileOf(task.taskId) == null || deliver == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final file = chat.fileOf(task.taskId)!;
    deliver!(_chat('hi'));
    deliver!(_gift(const LiveGift(name: '小心心')));
    deliver!(_superChat(price: 30, id: '9'));
    deliver!(
      const LiveMessage(type: LiveMessageType.online, userName: '', message: '42', color: LiveMessageColor.white),
    );
    deliver!(
      const LiveMessage(type: LiveMessageType.notice, userName: '', message: '公告', color: LiveMessageColor.white),
    );
    await chat.dispose();
    final entries = _entries(await file.readAsString());
    expect(entries, hasLength(3));
    expect(entries.where((entry) => entry.startsWith('<d ')), hasLength(1));
    expect(entries.where((entry) => entry.startsWith('<gift ')), hasLength(1));
    expect(entries.where((entry) => entry.startsWith('<sc ')).single, contains('price="30000"'));
    expect(chat.countOf(task), 1, reason: '"弹幕 N 条" counts the chat');
  });

  test('a long busy recording: every gift counted, the held entries bounded, the cost per message small', () async {
    // 20 minutes of a busy room: 100 chat lines and 20 gifts a second (half
    // of them five fans' continuous combos, half one-off gifts), flushed
    // every 2 s like the recorder.
    final plain = await open(name: 'plain.xml');
    final gifts = await open(name: 'gifts.xml');
    const seconds = 20 * 60;
    final stopwatch = Stopwatch();
    var chatOnly = Duration.zero;
    await timed(() async {
      for (final (writer, withGifts) in [(plain, false), (gifts, true)]) {
        now = _start;
        stopwatch
          ..reset()
          ..start();
        for (var s = 0; s < seconds; s++) {
          for (var i = 0; i < 100; i++) {
            now = _at(s * 1000 + i * 10);
            writer.add(_chat('第 $s 秒的第 $i 条', user: 'viewer${i % 37}'), receivedAt: now);
            if (withGifts && i % 5 == 0) {
              final fan = i % 10 == 0;
              writer.add(
                _gift(
                  LiveGift(name: fan ? '荧光棒' : '礼物$i', unitPrice: 100, unit: LiveGiftUnit.goldSeed),
                  user: fan ? 'fan${i % 50}' : 'once$s-$i',
                  userId: fan ? 'f${i % 50}' : 'o$s-$i',
                ),
                receivedAt: now,
              );
            }
          }
          if (s.isOdd) await writer.flush();
          if (withGifts && s % 300 == 299) {
            // What is held back behind the open combos stays within
            // maxComboSpan and a flush of now.
            final written = _entries(await writer.file.readAsString());
            expect(_ts(written.last), greaterThan(s - 36), reason: 'second $s');
          }
        }
        await writer.close();
        stopwatch.stop();
        if (!withGifts) chatOnly = stopwatch.elapsed;
      }
    });
    final withGifts = stopwatch.elapsed;
    final text = await gifts.file.readAsString();
    final entries = _entries(text);
    final giftEntries = entries.where((entry) => entry.startsWith('<gift ')).toList();
    final counted = giftEntries.fold<int>(
      0,
      (sum, entry) => sum + int.parse(RegExp('giftcount="([0-9]+)"').firstMatch(entry)!.group(1)!),
    );
    expect(counted, seconds * 20, reason: 'every gift is in the file once');
    // Five continuous combos cut every 30 s, plus the one-off gifts.
    expect(giftEntries.length, lessThan(seconds * 10 + 5 * (seconds ~/ 30 + 2)));
    expect(entries.where((entry) => entry.startsWith('<d ')), hasLength(seconds * 100));
    final times = entries.map(_ts).toList();
    for (var i = 1; i < times.length; i++) {
      expect(times[i], greaterThanOrEqualTo(times[i - 1]), reason: 'entry $i is out of order');
    }
    expect(await plain.file.readAsString(), isNot(contains('<gift ')));
    // 120 000 chat lines and 24 000 gifts: a few microseconds a message
    // (generous for a loaded machine; printed for the record).
    final perMessage = withGifts.inMicroseconds / (seconds * 120);
    // The numbers go into the record (record.md), as the D02.2 benchmark's.
    // ignore: avoid_print
    print(
      'chat only ${chatOnly.inMilliseconds} ms, with gifts ${withGifts.inMilliseconds} ms, '
      '${perMessage.toStringAsFixed(1)} µs a message, ${giftEntries.length} gift entries',
    );
    expect(perMessage, lessThan(200));
  });
}
