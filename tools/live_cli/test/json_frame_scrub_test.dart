import 'dart:convert';
import 'dart:io';

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

  test('kilakila: chat senders are replaced, other message types keep only their type', () {
    final scrubber = FrameScrubber.forPlatform('kilakila', _room('kilakila', '1', const {'roomId': '9'}), seed: 3);
    String frame(Map<String, Object?> content) =>
        '42/live_chat_room_guest,${jsonEncode([
          'text_message',
          jsonEncode({
            'body': {
              'response': {
                'room_id': '9',
                'sender_info': {'uid': 3632776065087, 'nickname': 'viewer_nick', 'avatar': 'https://a.example.test/x.png'},
                'content': jsonEncode(content),
              },
            },
          }),
        ])}';
    final chat = utf8.decode(
      scrubber.scrubFrame(
        _in(
          utf8.encode(
            frame({
              't': 200,
              'u': 3632776065087,
              'n': '月月月月月亮',
              'c': '你好',
              'a': 'https://a.example.test/x.png',
              'ui': {'gn': '粉丝团'},
            }),
          ),
          text: true,
        ),
      )!,
    );
    expect(chat, isNot(contains('3632776065087')));
    expect(chat, isNot(contains('月月月月月亮')));
    expect(chat, isNot(contains('粉丝团')));
    expect(chat, contains('你好'));
    final decoded = KilakilaProtocol.decode(
      chat,
      roomId: '9',
      context: DecodeContext(room: 'kilakila:1', session: 0, receivedAt: 0, now: DateTime.utc(2026)),
    );
    expect(decoded.events.whereType<DanmakuChat>().single.text, '你好');
    final other = utf8.decode(
      scrubber.scrubFrame(_in(utf8.encode(frame({'t': 621, 'c': '%7B%22userName%22%3A%22x%22%7D'})), text: true))!,
    );
    expect(other, isNot(contains('userName')));
    expect(scrubber.findLeak([_in(utf8.encode(chat), text: true)], ''), isNull);
  });

  test('pandalive: live/play is reduced, tokens and viewers are replaced, chat still decodes', () {
    final scrubber = FrameScrubber.forPlatform('pandalive', _room('pandalive', 'daisy00'), seed: 4);
    final play = jsonEncode({
      'result': true,
      'message': 'ok',
      'channel': '24133575',
      'token': 'eyJhbGciOi.eyJzdWIiOiJ2X2RhYTE2NjBjLTIi.nImVCxnSz1ZbSkjKNJDj9R6pGA',
      'userIp': '203.0.113.9',
      'loginInfo': {'sessKey': 'daa1660c-289b-4050-b19a-1948de0c0ae8'},
      'fanList': [
        {'userId': 'fanlogin77', 'userNick': '팬닉네임'},
      ],
      'media': {'userId': 'daisy00', 'userIdx': 24133575, 'isLive': true, 'title': 't'},
    });
    final reduced = utf8.decode(
      scrubber.scrubFrame(
        CapturedFrame(direction: 'in', millis: 0, bytes: utf8.encode(play), text: true, url: PandaliveProtocol.play),
      )!,
    );
    for (final gone in ['nImVCxnSz1ZbSkjKNJDj9R6pGA', '203.0.113.9', 'daa1660c', 'fanlogin77', '팬닉네임']) {
      expect(reduced, isNot(contains(gone)));
    }
    final session = PandaliveProtocol.session(reduced)!;
    expect(session.channel, '24133575');
    final chat = [
      '{"id":1,"result":{"client":"1527999c-5cc0-45a9-bb41-3382e4e5c08f","subs":{"_person:#v_fbd920d6-a":{}}}}',
      jsonEncode({
        'result': {
          'channel': '24133575',
          'data': {
            'data': {
              'type': 'chatter',
              'message': 'hello',
              'created_at': 1790533910,
              'id': 'viewer4411',
              'idx': 29069412,
              'nk': '시청자닉',
              'ip': 'kDin96VidKQRZufEdHGRNw==',
              'sex': 'U',
            },
            'offset': 1532,
          },
        },
      }),
    ].join('\n');
    final out = utf8.decode(scrubber.scrubFrame(_in(utf8.encode(chat), text: true))!);
    for (final gone in ['1527999c', 'fbd920d6', 'viewer4411', '29069412', '시청자닉', 'kDin96VidKQRZufEdHGRNw', '"sex"']) {
      expect(out, isNot(contains(gone)));
    }
    final decoded = PandaliveProtocol.decode(
      out,
      channel: '24133575',
      context: DecodeContext(room: 'pandalive:daisy00', session: 0, receivedAt: 0, now: DateTime.utc(2026)),
    );
    expect(decoded.events.whereType<DanmakuChat>().single.text, 'hello');
  });

  test('17live: gzip payloads are reduced and packed again; tokens and connection ids are replaced', () {
    final scrubber = FrameScrubber.forPlatform('17live', _room('17live', '29046769'), seed: 5);
    String pack(Map<String, Object?> payload) => base64.encode(gzip.encode(utf8.encode(jsonEncode(payload))));
    final auth = utf8.decode(
      scrubber.scrubFrame(
        CapturedFrame(
          direction: 'in',
          millis: 0,
          bytes: utf8.encode('{"provider":1,"token":"qvDtFQ.DDC0-eGrme5ctrBQSFzNHT1fQZ4Q8gE2"}'),
          text: true,
          url: SeventeenliveProtocol.auth,
        ),
      )!,
    );
    expect(auth, isNot(contains('DDC0-eGrme5ctrBQSFzNHT1fQZ4Q8gE2')));
    final connected = utf8.decode(
      scrubber.scrubFrame(
        _in(
          utf8.encode(
            jsonEncode({
              'action': 4,
              'connectionId': 'GSKpfkxteF',
              'connectionDetails': {'connectionKey': '4ab-NrJ6QyWxOQ!GSKpfkxteFAWtC0', 'serverId': 'frontdoor.a1eb'},
            }),
          ),
          text: true,
        ),
      )!,
    );
    for (final gone in ['GSKpfkxteF', 'NrJ6QyWxOQ', 'frontdoor.a1eb']) {
      expect(connected, isNot(contains(gone)));
    }
    final message = jsonEncode({
      'action': 15,
      'channel': '29046769',
      'messages': [
        {
          'id': 'm:0',
          'data': pack({
            'type': 3,
            'commentMsg': {
              'comment': {'text': 'hello'},
              'content': 'hello',
              'sendTime': 1790539305272,
              'level': 70,
              'displayUser': {'userID': '42813249-17ed-4d5a-acb7-73e247e648be', 'displayName': 'みかさ'},
            },
          }),
        },
        {
          'id': 'm:1',
          'data': pack({
            'type': 79,
            'laborReceiveRewardMsg': {
              'userInfo': {'displayName': '別の観客'},
            },
          }),
        },
      ],
    });
    final out = utf8.decode(scrubber.scrubFrame(_in(utf8.encode(message), text: true))!);
    final payloads = [
      for (final m in (jsonDecode(out) as Map)['messages'] as List) SeventeenliveProtocol.payload((m as Map)['data']),
    ];
    final text = jsonEncode(payloads);
    for (final gone in ['42813249', 'みかさ', '別の観客', '"level"']) {
      expect(text, isNot(contains(gone)));
    }
    expect(payloads[1], {'type': 79});
    final decoded = SeventeenliveProtocol.decode(
      out,
      roomId: '29046769',
      context: DecodeContext(room: '17live:29046769', session: 0, receivedAt: 0, now: DateTime.utc(2026)),
    );
    expect(decoded.events.whereType<DanmakuChat>().single.text, 'hello');
  });
}
