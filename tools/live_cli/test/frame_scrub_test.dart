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

  test('yy: the anonymous session is replaced everywhere; the frames still decode', () {
    final room = _room('yy', '54880976', {'sid': '54880976', 'ssid': '54880976'});
    final scrubber = FrameScrubber.forPlatform('yy', room, seed: 3);
    final payload =
        (YyWriter()
              ..latin('')
              ..u32(0)
              ..u32(2104501648)
              ..u32(0)
              ..latin('anonUser1234')
              ..latin('anonPass5678')
              ..bytes16([9, 8, 7, 6, 5, 4, 3, 2])
              ..bytes16(const [])
              ..latin('')
              ..latin('')
              ..u64(2104501648))
            .take();
    final loginReply =
        (YyWriter(778500)
              ..latin('')
              ..u32(0)
              ..u32(20078)
              ..bytes32(payload))
            .take();
    final apReply =
        (YyWriter(775940)
              ..u32(259)
              ..u32(200)
              ..latin('259:0')
              ..latin('KEY_YY_UID')
              ..latin('2104501648'))
            .take();
    const login = YyAnonymousLogin(
      ok: true,
      uid: 2104501648,
      username: 'anonUser1234',
      password: 'anonPass5678',
      cookie: [9, 8, 7, 6, 5, 4, 3, 2],
    );
    final frames = [
      CapturedFrame(direction: 'in', millis: 0, bytes: loginReply),
      CapturedFrame(
        direction: 'out',
        millis: 1,
        bytes: YyProtocol.apLogin(login, uuid: 'c0ffee00-1234-4abc-9def-001122334455'),
      ),
      CapturedFrame(direction: 'in', millis: 2, bytes: apReply),
      CapturedFrame(
        direction: 'out',
        millis: 3,
        bytes: YyProtocol.join(
          uid: 2104501648,
          topSid: 54880976,
          subSid: 54880976,
          trace: 'F2104501648_yymwebh5_0',
        ).first,
      ),
    ];
    final result = scrubber.scrub(frames, [
      (
        url: Uri.parse('wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&uuid=c0ffee00-1234-4abc-9def-001122334455'),
        headers: const <String, String>{},
      ),
    ]);
    expect(scrubber.findLeak(result.frames, result.handshakes.toString()), isNull);
    final decoded = [for (final frame in result.frames) ...YyProtocol.decode(frame.bytes)];
    final scrubbed = decoded.whereType<YyAnonymousLogin>().single;
    expect(scrubbed.ok, isTrue);
    expect(scrubbed.uid, isNot(2104501648));
    expect(scrubbed.username, hasLength('anonUser1234'.length));
    expect(decoded.whereType<YyApLogin>().single.code, 200);
    final all = [for (final frame in result.frames) ...frame.bytes];
    expect(latin1.decode(all), isNot(contains('2104501648')));
    expect(result.handshakes.single['url'], isNot(contains('c0ffee00')));
  });

  test('a masked name keeps its mask', () {
    final names = Pseudonyms(seed: 2);
    expect(names.person('尘***'), endsWith('***'));
    expect(BilibiliProtocol.isMasked(names.person('T***')), isTrue);
  });
}
