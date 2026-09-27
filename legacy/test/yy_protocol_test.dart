import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/utils/yy/yy_protocol.dart';

const _topSid = 22490906;
const _subSid = 22490906;
final _uid = BigInt.parse('4294967301');

void main() {
  group('YY current H5 protocol', () {
    test('uses the current official single-channel endpoint identity', () {
      const uuid = '00000000-0000-4000-8000-000000000001';
      expect(yyH5ServiceProtocolVersion, '3.2.10');
      expect(yyH5ServiceWebSocketBaseUrl, 'wss://h5-sinchl.yy.com/websocket');
      final endpoint = Uri.parse(buildYyH5ServiceWebSocketUrl(uuid));
      expect(endpoint.queryParameters, <String, String>{'appid': 'yymwebh5', 'version': '3.2.10', 'uuid': uuid});
    });

    test('packet writer emits the official 10-byte little-endian header', () {
      final bytes = (YyProtocolWriter(uri: 778244)..writeUint32(7)).takeBytes();
      final reader = YyProtocolReader(bytes, hasHeader: true);

      expect(reader.packetLength, bytes.length);
      expect(reader.uri, 778244);
      expect(reader.responseCode, 200);
      expect(reader.readUint32(), 7);
      expect(reader.bytesAvailable, 0);
    });

    test('runs anonymous login, AP login and channel join in order', () {
      final session = _newSession();
      final firstPacket = session.beginHandshake();
      expect(session.phase, YyProtocolPhase.waitingUdb);
      expect(_uri(firstPacket), 778244);

      final udbBatch = session.consume(_anonymousLoginResponse());
      expect(udbBatch.failure, isNull);
      expect(session.phase, YyProtocolPhase.waitingAp);
      expect(udbBatch.outbound.map(_uri), <int>[775684]);

      final apBatch = session.consume(_apLoginResponse());
      expect(apBatch.failure, isNull);
      expect(session.phase, YyProtocolPhase.waitingJoin);
      expect(apBatch.outbound.map(_uri), <int>[513035, 538456]);
      _expectJoinRouter(apBatch.outbound.first);

      final joinBatch = session.consume(_joinResponse());
      expect(joinBatch.failure, isNull);
      expect(joinBatch.becameReady, isTrue);
      expect(session.phase, YyProtocolPhase.joined);
      expect(joinBatch.outbound.map(_uri), <int>[537944, 537944]);
      expect(_groupCount(joinBatch.outbound[0]), 6);
      expect(_groupCount(joinBatch.outbound[1]), 2);
      expect(_uri(session.buildHeartbeat()!), 794116);
    });

    test('does not become ready when the router joins another room', () {
      final session = _newSession()..beginHandshake();
      session.consume(_anonymousLoginResponse());
      session.consume(_apLoginResponse());

      final batch = session.consume(_joinResponse(topSid: _topSid + 1));
      expect(batch.becameReady, isFalse);
      expect(batch.failure, contains('加入频道失败'));
      expect(session.phase, YyProtocolPhase.failed);
      expect(session.buildHeartbeat(), isNull);
    });

    test('decodes live chat only after joining the requested room', () {
      final session = _joinedSession();

      final batch = session.consume(_userGroupChat(topSid: _topSid, subSid: _subSid, nick: '测试用户', message: '晚上好'));
      expect(batch.warnings, isEmpty);
      expect(batch.chats, hasLength(1));
      expect(batch.chats.single.userName, '测试用户');
      expect(batch.chats.single.message, '晚上好');

      final wrongRoom = session.consume(
        _userGroupChat(topSid: _topSid + 1, subSid: _subSid + 1, nick: '其他房间', message: '忽略'),
      );
      expect(wrongRoom.chats, isEmpty);
    });

    test('parses every packet in one WebSocket binary message', () {
      final session = _joinedSession();
      final first = _userGroupChat(topSid: _topSid, subSid: _subSid, nick: '甲', message: '第一条');
      final second = _bySidChat(topSid: _topSid, subSid: _subSid, nick: '乙', message: '第二条');

      final batch = session.consume(Uint8List.fromList(<int>[...first, ...second]));
      expect(batch.chats.map((chat) => chat.message), <String>['第一条', '第二条']);
    });

    test('rejects truncated frames without throwing from the socket callback', () {
      final session = _newSession()..beginHandshake();
      final malformed = Uint8List.fromList(<int>[20, 0, 0, 0, 12, 0, 0, 0, 200, 0]);

      final batch = session.consume(malformed);
      expect(batch.warnings, isNotEmpty);
      expect(session.phase, YyProtocolPhase.waitingUdb);
    });
  });
}

YyProtocolSession _newSession() =>
    YyProtocolSession(topSid: _topSid, subSid: _subSid, uuid: '00000000-0000-4000-8000-000000000001');

YyProtocolSession _joinedSession() {
  final session = _newSession()..beginHandshake();
  session.consume(_anonymousLoginResponse());
  session.consume(_apLoginResponse());
  session.consume(_joinResponse());
  expect(session.phase, YyProtocolPhase.joined);
  return session;
}

int _uri(Uint8List packet) => YyProtocolReader(packet, hasHeader: true).uri!;

Uint8List _anonymousLoginResponse() {
  final payload = YyProtocolWriter()
    ..writeString('')
    ..writeUint32(0)
    ..writeUint32(5)
    ..writeUint32(12345)
    ..writeString('anonymous')
    ..writeString('secret')
    ..writeByteArray(Uint8List.fromList(<int>[1, 2, 3]))
    ..writeByteArray(Uint8List.fromList(<int>[4, 5]))
    ..writeString('')
    ..writeString('')
    ..writeUint64(_uid);
  final packet = YyProtocolWriter(uri: 778500)
    ..writeString('')
    ..writeUint32(0)
    ..writeUint32(20078)
    ..writeByteArray32(payload.takeBytes());
  return packet.takeBytes();
}

Uint8List _apLoginResponse() {
  final packet = YyProtocolWriter(uri: 775940)
    ..writeUint32(259)
    ..writeUint32(200)
    ..writeString('259:0')
    ..writeUint32(0x0100007f)
    ..writeUint16(1234)
    ..writeUint32(0);
  return packet.takeBytes();
}

Uint8List _joinResponse({int topSid = _topSid, int subSid = _subSid}) {
  final payload = YyProtocolWriter()
    ..writeUint32(topSid)
    ..writeUint32(5)
    ..writeUint32(subSid)
    ..writeUint32(_topSid)
    ..writeUint32(123)
    ..writeUint8(4)
    ..writeUtf8String('')
    ..writeUint32(0)
    ..writeUint32(0)
    ..writeUint64(_uid);
  final headers = YyProtocolWriter()..writeUint32(0xff000004);
  final packet = YyProtocolWriter(uri: 512011)
    ..writeString('')
    ..writeUint32(2048514)
    ..writeUint16(0)
    ..writeByteArray32(payload.takeBytes())
    ..writeByteArray32(headers.takeBytes());
  return packet.takeBytes();
}

void _expectJoinRouter(Uint8List packet) {
  final reader = YyProtocolReader(packet, hasHeader: true);
  expect(reader.uri, 513035);
  expect(reader.readString(), '');
  expect(reader.readUint32(), 2048258);
  expect(reader.readUint16(), 0);
  final payload = YyProtocolReader(reader.readByteArray32());
  expect(payload.readUint32(), 5);
  expect(payload.readUint32(), _topSid);
  expect(payload.readUint32(), _subSid);
  expect(payload.readUint32(), 2);
  expect(payload.readUint32(), 2);
  expect(payload.readString(), '0');
  expect(payload.readUint32(), 3);
  expect(payload.readString(), '1');
  expect(payload.readUint64(), _uid);
  final headers = YyProtocolReader(reader.readByteArray32());
  expect(headers.readUint32(), 0x01000008);
  expect(headers.readUint32(), 2048258);
  expect(headers.readUint32(), 0x02000010);
  expect(headers.readUint32(), 259);
  expect(headers.readUint64(), _uid);
  expect(headers.readUint32(), 0x0400000c);
  expect(headers.readUint32(), 0);
  expect(headers.readUint32(), 0);
  expect(headers.readUint32(), 0x05000008);
  expect(headers.readUint32(), 0);
  expect(headers.readUint32(), 0x06000023);
  expect(headers.readUint32(), 0);
  expect(headers.readUint16(), 0);
  expect(headers.readUint32(), 0);
  expect(headers.readString(), 'channelAuther');
  expect(headers.readUint32(), 0);
  expect(headers.readString(), '');
  while (headers.bytesAvailable > 4) {
    headers.readUint8();
  }
  expect(headers.readUint32(), 0xff787878);
}

int _groupCount(Uint8List packet) {
  final reader = YyProtocolReader(packet, hasHeader: true);
  reader.readUint64();
  return reader.readUint32();
}

Uint8List _userGroupChat({required int topSid, required int subSid, required String nick, required String message}) {
  final packet = YyProtocolWriter(uri: 533080)
    ..writeUint64(BigInt.one)
    ..writeUint64(BigInt.from(subSid))
    ..writeUint32(31)
    ..writeByteArray32(_chatPacket(topSid: topSid, subSid: subSid, nick: nick, message: message));
  return packet.takeBytes();
}

Uint8List _bySidChat({required int topSid, required int subSid, required String nick, required String message}) {
  final packet = YyProtocolWriter(uri: 28760)
    ..writeUint16(31)
    ..writeUint32(topSid)
    ..writeByteArray(_chatPacket(topSid: topSid, subSid: subSid, nick: nick, message: message));
  return packet.takeBytes();
}

Uint8List _chatPacket({required int topSid, required int subSid, required String nick, required String message}) {
  final chat = YyProtocolWriter()
    ..writeUint32(0)
    ..writeUcs2String32('')
    ..writeUint32(0xffffff)
    ..writeUint32(16)
    ..writeUcs2String32(message)
    ..writeUint32(0);
  final packet = YyProtocolWriter(uri: 3104600)
    ..writeUint32(5)
    ..writeUint32(topSid)
    ..writeUint32(subSid)
    ..writeByteArray(chat.takeBytes())
    ..writeString('')
    ..writeString('')
    ..writeUtf8String(nick)
    ..writeUint32(0)
    ..writeUint32(0)
    ..writeUint64(_uid);
  return packet.takeBytes();
}
