import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

RoomDetail _room(String platform, String id, [Map<String, String> keys = const {}]) => RoomDetail(
  card: RoomCard(ref: RoomRef(platform, id), title: 't', anchorName: 'a', state: LiveState.live),
  link: Uri.parse('https://example.test/$id'),
  danmakuKeys: keys,
);

Uint8List _biliNotice(Map<String, Object?> json) {
  final inner = BilibiliProtocol.packet(BilibiliProtocol.opNotice, utf8.encode(jsonEncode(json)));
  final body = zlib.encode(inner);
  final packet = Uint8List(16 + body.length);
  ByteData.sublistView(packet)
    ..setUint32(0, packet.length)
    ..setUint16(4, 16)
    ..setUint16(6, 2)
    ..setUint32(8, BilibiliProtocol.opNotice)
    ..setUint32(12, 1);
  packet.setRange(16, packet.length, body);
  return packet;
}

void main() {
  test('bilibili: names, ids, hashes and nested JSON strings are replaced; the frame still decodes', () {
    final scrubber = FrameScrubber.forPlatform('bilibili', _room('bilibili', '5050'), seed: 1);
    final notice = {
      'cmd': 'DANMU_MSG',
      'dm_v2': 'c2VjcmV0',
      'info': [
        [
          0,
          1,
          25,
          16777215,
          1790519728614,
          1790504102,
          0,
          'abcdef12',
          0,
          0,
          0,
          '',
          1,
          '{}',
          '{}',
          {
            'extra': jsonEncode({'user_hash': '2997851981', 'reply_uname': 'SomeoneElse'}),
            'user': {
              'uid': 473644038,
              'base': {
                'name': '真实昵称',
                'face': 'https://i0.hdslb.com/bfs/face/abc.jpg',
                'origin_info': {'name': '真实昵称', 'face': 'https://i0.hdslb.com/bfs/face/abc.jpg'},
              },
            },
          },
        ],
        '流口水',
        [473644038, '真实昵称', 0, 0, 0, 10000, 1, ''],
      ],
    };
    final frame = CapturedFrame(direction: 'in', millis: 0, bytes: _biliNotice(notice));
    final result = scrubber.scrub([frame], const []);
    expect(scrubber.findLeak(result.frames, ''), isNull);
    final text = utf8.decode(scrubber.plain(result.frames.single), allowMalformed: true);
    expect(text, isNot(contains('2997851981')));
    expect(text, isNot(contains('SomeoneElse')));
    expect(text, isNot(contains('c2VjcmV0')));
    final context = DecodeContext(room: 'bilibili:5050', session: 0, receivedAt: 0, now: DateTime(2026));
    final decoded = BilibiliProtocol.decode(result.frames.single.bytes, context: context);
    final chat = decoded.events.single as DanmakuChat;
    expect(chat.text, '流口水');
    expect(chat.userName, startsWith('观众'));
    expect(chat.userId, isNot('473644038'));
  });

  test('a masked name keeps its mask', () {
    final names = Pseudonyms(seed: 2);
    expect(names.person('尘***'), endsWith('***'));
    expect(BilibiliProtocol.isMasked(names.person('T***')), isTrue);
  });
}
