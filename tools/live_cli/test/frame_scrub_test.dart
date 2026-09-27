import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

  test('soop: chat senders get pseudonyms, viewer lists lose their bodies', () {
    final scrubber = FrameScrubber.forPlatform('soop', _room('soop', 'khm11903', {'chatNo': '4172'}), seed: 4);
    final chat = SoopProtocol.packet(5, ['', '와 대박', 'realviewer77(2)', '0', '0', '3', '진짜닉네임', '1769504']);
    final list = SoopProtocol.packet(4, ['', '1', 'someviewer99', '다른시청자', '65536']);
    final result = scrubber.scrub([
      CapturedFrame(direction: 'in', millis: 0, bytes: [...chat, ...list]),
    ], const []);
    expect(scrubber.findLeak(result.frames, ''), isNull);
    final packets = SoopProtocol.packets(result.frames.single.bytes);
    expect(packets.map((p) => p.service), [5, 4]);
    expect(packets.first.fields[1], '와 대박', reason: 'chat text is public');
    expect(packets.first.fields[2], endsWith('(2)'));
    expect(packets.first.fields[2], isNot(startsWith('realviewer77')));
    expect(packets.first.fields[6], startsWith('观众'));
    expect(packets.last.fields, ['']);
  });

  test('acfun: the visitor session, tickets and senders are replaced; frames are sealed again and still decode', () {
    final scrubber = FrameScrubber.forPlatform('acfun', _room('acfun', '41254970', {'author': '41254970'}), seed: 5);
    final security = Uint8List.fromList(List.generate(16, (i) => i + 1));
    final sessionKey = Uint8List.fromList(List.generate(16, (i) => 90 + i));
    final session = AcfunChatSession(
      userId: 1700000000000001,
      token: 'visitorTokenABC123',
      security: security,
      deviceId: 'web_realdevice00001',
      liveId: 'LIVE1',
      tickets: const ['realTicket+AAA=='],
      attach: 'realAttach/BBB==',
    );
    Uint8List down(String command, List<int> data, List<int> key, int mode) {
      final plain =
          (ProtoWriter()
                ..string(1, command)
                ..integer(2, 1)
                ..bytes(4, data))
              .toBytes();
      final header =
          (ProtoWriter()
                ..integer(1, 13)
                ..integer(2, 1700000000000001)
                ..integer(7, plain.length)
                ..integer(8, mode)
                ..integer(10, 5))
              .toBytes();
      return AcfunProtocol.frame(header, AcfunProtocol.seal(plain, key, Random(1)));
    }

    final link = AcfunLink(session);
    final register = link.register();
    final answer = down(
      AcfunProtocol.register,
      (ProtoWriter()
            ..bytes(2, sessionKey)
            ..integer(3, 77))
          .toBytes(),
      security,
      1,
    );
    link.read(answer);
    final comment =
        (ProtoWriter()
              ..string(1, '好活')
              ..integer(2, 1790000000000)
              ..bytes(
                3,
                (ProtoWriter()
                      ..integer(1, 123456789)
                      ..string(2, '真名字')
                      ..bytes(3, utf8.encode('https://avatar.example/real.png')))
                    .toBytes(),
              ))
            .toBytes();
    final signals =
        (ProtoWriter()
              ..bytes(
                1,
                (ProtoWriter()
                      ..string(1, 'CommonActionSignalComment')
                      ..bytes(2, comment))
                    .toBytes(),
              )
              ..bytes(
                1,
                (ProtoWriter()
                      ..string(1, 'CommonActionSignalRichText')
                      ..bytes(2, [1, 2, 3]))
                    .toBytes(),
              ))
            .toBytes();
    final push =
        (ProtoWriter()
              ..string(1, 'ZtLiveScActionSignal')
              ..integer(2, 2)
              ..bytes(3, gzip.encode(signals))
              ..string(5, 'realTicket+AAA=='))
            .toBytes();
    final query = {
      'subBiz': 'mainApp',
      'userId': '1700000000000001',
      'did': 'web_realdevice00001',
      'acfun.api.visitor_st': 'visitorTokenABC123',
    };
    final frames = [
      CapturedFrame(
        direction: 'in',
        millis: 0,
        text: true,
        url: Uri.https('id.app.acfun.cn', '/rest/app/visitor/login'),
        bytes: utf8.encode(
          jsonEncode({
            'result': 0,
            'userId': 1700000000000001,
            'acfun.api.visitor_st': 'visitorTokenABC123',
            'acSecurity': base64.encode(security),
          }),
        ),
      ),
      CapturedFrame(
        direction: 'in',
        millis: 1,
        text: true,
        url: Uri.https('api.kuaishouzt.com', '/rest/zt/live/web/startPlay', query),
        bytes: utf8.encode(
          jsonEncode({
            'result': 1,
            'data': {
              'liveId': 'LIVE1',
              'availableTickets': ['realTicket+AAA=='],
              'enterRoomAttach': 'realAttach/BBB==',
              'videoPlayRes': '{"url":"https://cdn.example/x.flv?auth_key=1-2-3"}',
            },
            'host': 'real-host-name-01',
          }),
        ),
      ),
      CapturedFrame(direction: 'out', millis: 2, bytes: register),
      CapturedFrame(direction: 'in', millis: 3, bytes: answer),
      CapturedFrame(direction: 'out', millis: 4, bytes: link.enterRoom()),
      CapturedFrame(direction: 'in', millis: 5, bytes: down(AcfunProtocol.message, push, sessionKey, 2)),
    ];
    final result = scrubber.scrub(frames, [(url: AcfunProtocol.endpoint, headers: const <String, String>{})]);
    expect(scrubber.findLeak(result.frames, result.handshakes.toString()), isNull);
    final text = result.frames.take(2).map((frame) => utf8.decode(frame.bytes)).join();
    for (final secret in [
      'visitorTokenABC123',
      'realTicket',
      'realAttach',
      'real-host',
      'auth_key',
      '1700000000000001',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(result.frames[1].url!.queryParameters['did'], isNot('web_realdevice00001'));
    final visitor = AcfunProtocol.visitor(utf8.decode(result.frames[0].bytes));
    expect(visitor.security, isNot(security));
    final play = AcfunProtocol.startPlay(utf8.decode(result.frames[1].bytes))!;
    final fake = AcfunChatSession(
      userId: visitor.userId,
      token: visitor.token,
      security: visitor.security,
      deviceId: '',
      liveId: play.liveId,
      tickets: play.tickets,
      attach: play.attach,
    );
    final reader = AcfunLink(fake);
    final (:header, :payload) = AcfunProtocol.unframe(result.frames[2].bytes);
    expect(header.message(9)!.string(2), visitor.token, reason: 'the header token is the replaced one');
    expect(ProtoMessage.decode(AcfunProtocol.open(payload, visitor.security)).string(1), 'Basic.Register');
    expect(reader.read(result.frames[3].bytes).command, 'Basic.Register');
    expect(reader.registered, isTrue);
    final message = reader.read(result.frames[5].bytes);
    final context = DecodeContext(room: 'acfun:41254970', session: 0, receivedAt: 0, now: DateTime.utc(2026));
    final chat = AcfunProtocol.push(message.payload, context).events.single as DanmakuChat;
    expect(chat.text, '好活', reason: 'chat text is public');
    expect(chat.userName, startsWith('观众'));
    expect(chat.userId, isNot('123456789'));
    expect(chat.userId, hasLength(9));
  });

  test("twitch: senders and their mentions get pseudonyms; other viewers' notices are dropped", () {
    final scrubber = FrameScrubber.forPlatform('twitch', _room('twitch', 'zarbex', {'login': 'zarbex'}), seed: 6);
    List<int> text(String value) => utf8.encode(value);
    final frames = [
      CapturedFrame(direction: 'out', millis: 0, text: true, bytes: text('NICK justinfan12345')),
      CapturedFrame(
        direction: 'in',
        millis: 1,
        text: true,
        bytes: text(
          '@display-name=AlanBowgen;id=m-1;user-id=1246260645;client-nonce=413E0BAE;color=#8A2BE2 '
          ':alanbowgen!alanbowgen@alanbowgen.tmi.twitch.tv PRIVMSG #zarbex :@Schmalooten wie gross?\r\n',
        ),
      ),
      CapturedFrame(
        direction: 'in',
        millis: 2,
        text: true,
        bytes: text(
          '@display-name=Schmalooten;id=m-2;user-id=555666777 '
          ':schmalooten!schmalooten@schmalooten.tmi.twitch.tv PRIVMSG #zarbex :@alanbowgen 191\r\n'
          '@login=someone;display-name=Someone;msg-id=sub :tmi.twitch.tv USERNOTICE #zarbex :hi\r\n'
          'PING :tmi.twitch.tv\r\n',
        ),
      ),
    ];
    final result = scrubber.scrub(frames, const []);
    expect(scrubber.findLeak(result.frames, ''), isNull);
    final all = result.frames.map((frame) => utf8.decode(frame.bytes)).join('\n');
    for (final original in ['AlanBowgen', 'alanbowgen', 'Schmalooten', 'schmalooten', '1246260645', '413E0BAE']) {
      expect(all, isNot(contains(original)));
    }
    expect(all, isNot(contains('USERNOTICE')));
    expect(all, contains('PING :tmi.twitch.tv'));
    expect(utf8.decode(result.frames.first.bytes), 'NICK justinfan12345');
    final context = DecodeContext(room: 'twitch:zarbex', session: 0, receivedAt: 0, now: DateTime.utc(2026));
    final chats = [
      for (final frame in result.frames.skip(1))
        for (final message in TwitchProtocol.messages(utf8.decode(frame.bytes)))
          ?TwitchProtocol.chat(message, channel: 'zarbex', context: context),
    ];
    expect(chats, hasLength(2));
    expect(chats.first.userName, hasLength('AlanBowgen'.length));
    expect(chats.first.text, '@${chats.last.userName} wie gross?', reason: 'a mention before the sender speaks');
    expect(chats.last.text, endsWith(' 191'));
    expect(chats.last.text, isNot(contains('alanbowgen')));
    expect(chats.first.id, 'twitch:m-1');
    expect(chats.first.color, 0x8A2BE2);
  });

  test('a masked name keeps its mask', () {
    final names = Pseudonyms(seed: 2);
    expect(names.person('尘***'), endsWith('***'));
    expect(BilibiliProtocol.isMasked(names.person('T***')), isTrue);
  });
}
