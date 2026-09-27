import 'dart:typed_data';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _uid = 294636272;
final _context = DecodeContext(room: 'huya:998', session: 3, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

Uint8List _chat({int senderUid = 1, String nick = '观众', String text = '你好', int color = -1, int presenter = _uid}) =>
    (TarsWriter()
          ..struct(0, (writer) {
            writer
              ..integer(0, senderUid)
              ..string(2, nick);
          })
          ..integer(1, presenter)
          ..string(3, text)
          ..struct(6, (writer) => writer.integer(0, color))
          ..string(20, '2048896616064357376'))
        .toBytes();

Uint8List _push7(int uri, List<int> body) {
  final push = TarsWriter()
    ..integer(0, 0)
    ..integer(1, uri)
    ..bytes(2, body);
  return (TarsWriter()
        ..integer(0, 7)
        ..bytes(1, push.toBytes()))
      .toBytes();
}

Uint8List _push22(String group, List<(int, List<int>, int)> items) {
  final push = TarsWriter()
    ..string(0, group)
    ..list<(int, List<int>, int)>(1, items, (writer, item) {
      writer.struct(0, (fields) {
        fields
          ..integer(0, item.$1)
          ..bytes(1, item.$2)
          ..integer(2, item.$3);
      });
    });
  return (TarsWriter()
        ..integer(0, 22)
        ..bytes(1, push.toBytes()))
      .toBytes();
}

void main() {
  group('encoding (§7.2, §7.3)', () {
    test('register command 16 lists the live: and chat: groups', () {
      final outer = TarsStruct.decode(HuyaProtocol.register(_uid));
      expect(outer.integer(0), 16);
      final group = TarsStruct.decode(outer.bytes(1)!);
      expect(group.list(0), ['live:$_uid', 'chat:$_uid']);
      expect(group.string(1), '');
    });

    test('heartbeat command 20 with an empty payload, every 60 s', () {
      final outer = TarsStruct.decode(HuyaProtocol.heartbeat());
      expect(outer.integer(0), 20);
      expect(outer.bytes(1), isEmpty);
      expect(HuyaProtocol.heartbeatInterval, const Duration(seconds: 60));
    });

    test('Tars round trip keeps every value type', () {
      final value = TarsStruct({
        0: 0,
        1: -5,
        2: 40000,
        3: 3000000000,
        4: 'text',
        5: Uint8List.fromList([1, 2, 3]),
        6: const ['a', 'b'],
        7: const {'k': 1},
        8: const TarsStruct({0: 'nested'}),
        9: 'x' * 300,
      });
      final decoded = TarsStruct.decode(value.encode());
      expect(decoded.fields[3], 3000000000);
      expect(decoded.string(9), hasLength(300));
      expect(decoded.list(6), ['a', 'b']);
      expect(decoded.fields[7], {'k': 1});
      expect(decoded.struct(8)!.string(0), 'nested');
      expect(decoded.bytes(5), [1, 2, 3]);
      expect(() => TarsStruct.decode(const [0x06, 0x05, 0x61]), throwsFormatException);
    });
  });

  group('messages (§7.4, §7.6)', () {
    test('uri 1400 via command 7: sender, text, colour, tag 20 id', () {
      final frame = HuyaProtocol.decode(_push7(1400, _chat(color: 0xFF706E)), uid: _uid, context: _context);
      final chat = frame.events.single as DanmakuChat;
      expect(chat.userId, '1');
      expect(chat.userName, '观众');
      expect(chat.text, '你好');
      expect(chat.color, 0xFF706E);
      expect(chat.id, 'huya:2048896616064357376');
      expect(chat.session, 3);
      final white = HuyaProtocol.decode(_push7(1400, _chat()), uid: _uid, context: _context).events.single;
      expect((white as DanmakuChat).color, DanmakuColors.white);
    });

    test('uri 8006 is popularity, never online (REG-HUYA-014)', () {
      final body = (TarsWriter()..integer(0, 5391195)).toBytes();
      final online = HuyaProtocol.decode(_push7(8006, body), uid: _uid, context: _context).events.single;
      expect((online as DanmakuOnline).audience, AudienceKind.popularity);
      expect(online.value, 5391195);
    });

    test('uri 2001314 reports a headline without an event', () {
      final frame = HuyaProtocol.decode(_push7(2001314, const []), uid: _uid, context: _context);
      expect(frame.events, isEmpty);
      expect(frame.headline, isTrue);
    });

    test("command 22 accepts only this room's groups; the item id is the fallback id", () {
      final body =
          (TarsWriter()
                ..struct(0, (writer) => writer.string(2, 'x'))
                ..string(3, 'hi'))
              .toBytes();
      final mine = HuyaProtocol.decode(_push22('live:$_uid', [(1400, body, 42)]), uid: _uid, context: _context);
      expect((mine.events.single as DanmakuChat).id, 'huya:42');
      final other = HuyaProtocol.decode(_push22('live:1', [(1400, body, 42)]), uid: _uid, context: _context);
      expect(other.events, isEmpty);
    });

    test('a chat naming another presenter is dropped; a system chat (presenter -1) is kept', () {
      expect(HuyaProtocol.decode(_push7(1400, _chat(presenter: 1)), uid: _uid, context: _context).events, isEmpty);
      expect(
        HuyaProtocol.decode(_push7(1400, _chat(presenter: -1)), uid: _uid, context: _context).events,
        hasLength(1),
      );
    });

    test('a malformed item does not drop the others of the frame', () {
      final good =
          (TarsWriter()
                ..struct(0, (writer) => writer.string(2, 'x'))
                ..string(3, 'ok'))
              .toBytes();
      final frame = HuyaProtocol.decode(
        _push22('chat:$_uid', [
          (1400, [0x06, 0x09], 1),
          (1400, good, 2),
        ]),
        uid: _uid,
        context: _context,
      );
      expect(frame.events.map((event) => (event as DanmakuChat).text), ['ok']);
    });
  });

  group('recorded frames (fixtures/huya/danmaku/S11-live)', () {
    final fixture = DanmakuFixture.load('huya', 'S11-live');
    final uid = int.parse(fixture.keys['uid']!);
    final frames = [
      for (final frame in fixture.incoming) HuyaProtocol.decode(frame.bytes, uid: uid, context: fixture.context(frame)),
    ];
    final events = [for (final frame in frames) ...frame.events];

    test('the client registered the groups and sent a heartbeat', () {
      final commands = [for (final frame in fixture.outgoing) TarsStruct.decode(frame.bytes).integer(0)];
      expect(commands, [16, 20]);
      expect(fixture.outgoing.first.bytes, HuyaProtocol.register(uid));
    });

    test('chat and popularity decode; the server groups are live:<uid>', () {
      final chats = events.whereType<DanmakuChat>().toList();
      expect(chats, hasLength(62));
      expect(chats.every((chat) => chat.id!.startsWith('huya:') && chat.text.isNotEmpty), isTrue);
      expect(chats.first.text, '又是射程，你没有伤害有射程有什么用');
      expect(chats.first.id, 'huya:2048896616064357376');
      expect(chats.where((chat) => chat.color == 0xFF706E), isNotEmpty);
      final popularity = events.whereType<DanmakuOnline>().map((online) => online.value).toList();
      expect(popularity, [5391195, 5392559]);
      final groups = {
        for (final frame in fixture.incoming)
          if (TarsStruct.decode(frame.bytes) case final outer when outer.integer(0) == 22)
            TarsStruct.decode(outer.bytes(1)!).string(0),
      };
      expect(groups, {'live:$uid'});
    });
  });
}
