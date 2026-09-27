import 'dart:convert';

import 'package:brotli/brotli.dart';
import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

RoomDetail _room(String platform, String id, [Map<String, String> keys = const {}]) => RoomDetail(
  card: RoomCard(ref: RoomRef(platform, id), title: 't', anchorName: 'a', state: LiveState.live),
  link: Uri.parse('https://example.test/$id'),
  danmakuKeys: keys,
);

CapturedFrame _in(List<int> bytes, {bool text = false}) =>
    CapturedFrame(direction: 'in', millis: 0, bytes: bytes, text: text);

void main() {
  test('stored Brotli round-trips through the real decoder, across meta-blocks', () {
    for (final length in [1, 100, 65536, 65537, 140000]) {
      final data = List<int>.generate(length, (index) => index * 7 % 251);
      expect(brotli.decode(brotliStored(data)), data, reason: '$length bytes');
    }
  });

  test('chzzk: viewers in nested profile JSON, tokens and session ids are replaced', () {
    final scrubber = FrameScrubber.forPlatform('chzzk', _room('chzzk', 'a' * 32), seed: 1);
    final frame = jsonEncode({
      'cmd': 93101,
      'bdy': [
        {
          'uid': 'f7a6281ca24b25a345b9d3383f1f6f24',
          'profile': jsonEncode({'userIdHash': 'f7a6281ca24b25a345b9d3383f1f6f24', 'nickname': '시청자닉네임'}),
          'msg': 'hello',
          'extras': jsonEncode({'extraToken': 'TOKENtoken123456', 'streamingChannelId': 'b' * 32}),
          'mbrCnt': 10,
        },
      ],
    });
    final out = utf8.decode(scrubber.scrubFrame(_in(utf8.encode(frame), text: true))!);
    expect(out, isNot(contains('f7a6281ca24b25a345b9d3383f1f6f24')));
    expect(out, isNot(contains('시청자닉네임')));
    expect(out, isNot(contains('TOKENtoken123456')));
    expect(out, contains('b' * 32), reason: 'the streamer channel id is public');
    final decoded = ChzzkProtocol.decode(
      out,
      chatChannelId: 'c',
      context: DecodeContext(room: 'chzzk:x', session: 0, receivedAt: 0, now: DateTime.utc(2026)),
    );
    expect(decoded.events.whereType<DanmakuChat>().single.text, 'hello');
  });

  test('missevan: the Brotli frame is decoded, scrubbed and stored again with its new length', () {
    final scrubber = FrameScrubber.forPlatform('missevan', _room('missevan', '1', const {'roomId': '1'}), seed: 2);
    final plain = utf8.encode(
      jsonEncode({
        'type': 'message',
        'event': 'new',
        'room_id': 1,
        'msg_id': 'm',
        'message': '晚上好',
        'user': {'user_id': 38112623, 'username': '花间_梵梵', 'iconurl': 'https://static.example.test/a.png'},
      }),
    );
    final frame = [1, plain.length & 0xff, (plain.length >> 8) & 0xff, 0, ...brotliStored(plain)];
    final out = scrubber.scrubFrame(_in(frame))!;
    final text = MissevanProtocol.text(out)!;
    expect(text, isNot(contains('38112623')));
    expect(text, isNot(contains('花间_梵梵')));
    expect(text, isNot(contains('static.example.test')));
    expect(text, contains('晚上好'));
    expect(scrubber.findLeak([_in(out)], ''), isNull);
    expect(utf8.decode(scrubber.scrubFrame(_in(utf8.encode('❤️'), text: true))!), '❤️');
  });
}
