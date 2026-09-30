// Writes fixtures/bilibili/danmaku/*/expected.json: what 3.x's Bilibili
// danmaku decoder did with every received WebSocket message
// (docs/modules/M5.1-bilibili.md, "v3 的冻结输出").
//
// The code between the "3.x" markers is 3.x's BiliBiliDanmaku copied from
// legacy/lib/core/danmaku/bilibili_danmaku.dart (archive/v4), with the helpers
// it calls: BinaryWriter (core/common/binary_writer.dart), asT
// (core/common/convert_helper.dart) and the parts of LiveMessage,
// LiveMessageColor, LiveAudienceUpdate and LiveSuperChatMessage it uses
// (common/models/live_message.dart). Only these are replaced:
//
// - `WebScoketUtils` by a stub that records `close`: the decoder reaches the
//   socket only through `_sendPacket` (taken over by the injected
//   `packetSender`, as 3.x's own tests did) and through the credential refresh;
// - `package:brotli` (0.6.0, SDK constraint <3.0.0, so it does not resolve on
//   Dart 3) by live_net's `brotliDecode`, the RFC 7932 decoder of M1.1, behind
//   the same chunked sink: the packet is buffered and decoded at `close`, the
//   output handed on in 16 KiB pieces (M5.F, B-3). Both decoders give the same
//   bytes for every valid stream; for corrupt ones the verdict here is M1.1's
//   (docs/modules/M5.1-bilibili.md, "后续升级");
// - `CoreLog` by the harness's log; `@visibleForTesting` by a local constant;
// - `start`, `_connect` and `stop` (the socket's lifecycle) by a `_connect`
//   stub that records the call.
//
// One 3.x instance replays one recording (S13-live, S13-protover3,
// S13-protover2-paired) or one vector (S13-vectors, S13-brotli-vectors), like
// one connection, with `danmakuArgs` set to the room's arguments and a
// `refresh` that records the call and never completes (so a later rejection
// finds the refresh still running, and no frame's effects depend on how it
// ends). For every received binary message, in order, the harness records
// the effects: messages (projected), packets sent (Base64), `onReady`,
// refreshes and logged errors (their type).
//
// S13-vectors and S13-brotli-vectors are synthetic: this file writes their
// frames.jsonl as well. The brotli vectors use uncompressed meta-blocks
// (`_brotliStream`), the smallest valid encoder; the recordings hold the
// server's compressed ones.
//
// Run from the repository root:
//
//   dart run fixtures/bilibili/danmaku/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_net/live_net.dart' show brotliDecode;

const _root = 'fixtures/bilibili/danmaku';
const _generator =
    '3.x BiliBiliDanmaku.decodeMessage, one instance per sample or vector (fixtures/bilibili/danmaku/legacy_expected.dart)';

Future<void> main() async {
  for (final sample in ['S13-live', 'S13-protover3', 'S13-protover2-paired']) {
    await _live(sample);
  }
  await _vectors('S13-vectors', _vectorList());
  await _vectors('S13-brotli-vectors', _brotliVectorList());
}

// Harness --------------------------------------------------------------------

final List<Map<String, Object?>> _effects = [];

BiliBiliDanmaku _instance() {
  final danmaku = BiliBiliDanmaku(packetSender: (packet) => _effects.add({'send': base64.encode(packet)}));
  danmaku.onMessage = (message) => _effects.add({'message': _project(message)});
  danmaku.onReady = () => _effects.add({'ready': true});
  danmaku.danmakuArgs = BiliBiliDanmakuArgs(
      roomId: 5050,
      token: 'token',
      serverUrls: const [],
      buvid: 'buvid',
      uid: 0,
      cookie: '',
      refresh: () {
        _effects.add({'refresh': true});
        return Completer<BiliBiliDanmakuArgs?>().future;
      },
    );
  return danmaku;
}

/// Decodes [message] and returns the effects.
Future<List<Map<String, Object?>>> _replay(BiliBiliDanmaku danmaku, List<int> message) async {
  _effects.clear();
  danmaku.decodeMessage(message);
  await Future<void>.delayed(Duration.zero);
  return List.of(_effects);
}

Map<String, Object?> _project(LiveMessage message) => {
  'type': message.type.name,
  'userName': message.userName,
  'userId': message.userId,
  'message': message.message,
  'color': message.color.toString(),
  'userLevel': message.userLevel,
  'fansLevel': message.fansLevel,
  'fansName': message.fansName,
  'isLocal': message.isLocal,
  'messageId': message.messageId,
  'sentAt': message.sentAt?.millisecondsSinceEpoch,
  'data': switch (message.data) {
    null => null,
    LiveAudienceUpdate update => {'kind': update.kind.name, 'value': update.value},
    LiveSuperChatMessage chat => {
      'messageId': chat.messageId,
      'userName': chat.userName,
      'face': chat.face,
      'message': chat.message,
      'price': chat.price,
      'startTime': chat.startTime.millisecondsSinceEpoch,
      'endTime': chat.endTime.millisecondsSinceEpoch,
      'backgroundColor': chat.backgroundColor,
      'backgroundBottomColor': chat.backgroundBottomColor,
    },
    final other => '$other',
  },
};

void _write(String sample, Object? value) {
  File('$_root/$sample/expected.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n',
  );
}

Future<void> _live(String sample) async {
  final danmaku = _instance();
  final frames = <Map<String, Object?>>[];
  final lines = File('$_root/$sample/frames.jsonl').readAsLinesSync();
  for (var index = 0; index < lines.length; index++) {
    final frame = jsonDecode(lines[index]) as Map<String, dynamic>;
    if (frame['dir'] != 'in' || frame['b64'] == null) continue;
    frames.add({'line': index + 1, 'effects': await _replay(danmaku, base64.decode(frame['b64'] as String))});
  }
  _write(sample, {'frames': frames});
}

Future<void> _vectors(String sample, List<(String, List<Uint8List>)> list) async {
  final lines = <String>[];
  final vectors = <Map<String, Object?>>[];
  for (final (name, messages) in list) {
    final danmaku = _instance();
    final frames = <Map<String, Object?>>[];
    for (final message in messages) {
      lines.add(jsonEncode({'vector': name, 'dir': 'in', 't': 0, 'b64': base64.encode(message)}));
      frames.add({'line': lines.length, 'effects': await _replay(danmaku, message)});
    }
    vectors.add({'vector': name, 'frames': frames});
  }
  File('$_root/$sample/frames.jsonl').writeAsStringSync('${lines.join('\n')}\n');
  _write(sample, {'vectors': vectors});
}

// Vectors --------------------------------------------------------------------

/// One Bilibili packet (3.x test/bilibili_danmaku_protocol_test.dart `_packet`).
Uint8List _packet(List<int> body, {required int operation, int protocolVersion = 0}) {
  final bytes = Uint8List(16 + body.length);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, bytes.length, Endian.big);
  header.setUint16(4, 16, Endian.big);
  header.setUint16(6, protocolVersion, Endian.big);
  header.setUint32(8, operation, Endian.big);
  header.setUint32(12, 1, Endian.big);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

Uint8List _notice(Object? json, {int protocolVersion = 0}) =>
    _packet(utf8.encode(jsonEncode(json)), operation: 5, protocolVersion: protocolVersion);

Uint8List _zlib(List<int> inner) => _packet(zlib.encode(inner), operation: 5, protocolVersion: 2);

Uint8List _join(List<List<int>> packets) => Uint8List.fromList([for (final packet in packets) ...packet]);

/// A brotli stream of [data] in uncompressed meta-blocks of at most [block]
/// bytes (RFC 7932 section 9.2): window bits 16, then per block ISLAST 0,
/// MNIBBLES 4, MLEN - 1, ISUNCOMPRESSED 1, padding and the bytes, then an
/// empty last meta-block.
Uint8List _brotliStream(List<int> data, {int block = 65536}) {
  final out = BytesBuilder();
  var bits = 0;
  var count = 0;
  void put(int value, int width) {
    bits |= value << count;
    count += width;
    while (count >= 8) {
      out.addByte(bits & 0xff);
      bits >>= 8;
      count -= 8;
    }
  }

  void align() {
    if (count > 0) put(0, 8 - count);
  }

  put(0, 1);
  for (var offset = 0; offset < data.length; offset += block) {
    final end = offset + block < data.length ? offset + block : data.length;
    put(0, 1);
    put(0, 2);
    put(end - offset - 1, 16);
    put(1, 1);
    align();
    out.add(data.sublist(offset, end));
  }
  put(1, 1);
  put(1, 1);
  align();
  return out.takeBytes();
}

Uint8List _brotli(List<int> inner, {int block = 65536}) =>
    _packet(_brotliStream(inner, block: block), operation: 5, protocolVersion: 3);

Uint8List _auth(String body) => _packet(utf8.encode(body), operation: 8);

Uint8List _online(int value, {int length = 4}) {
  final body = ByteData(length);
  if (length >= 4) body.setUint32(0, value, Endian.big);
  return _packet(body.buffer.asUint8List(), operation: 3, protocolVersion: 1);
}

/// A `DANMU_MSG` in the shape of S13-live's: [meta] replaces `info[0]`, [user]
/// `info[2]`; `info[3]` and `info[4]` are the medal and level lists.
Map<String, Object?> _danmu(String text, {List<Object?>? meta, Object? user = const [1000, 'viewer'], String cmd = 'DANMU_MSG'}) => {
  'cmd': cmd,
  'info': [
    meta ?? [0, 1, 25, 16777215, 1790519893202, 1790519804, 0, '8z3o13gj', 0, 0, 0, '', 0, '{}', '{}'],
    text,
    user,
    [27, '大母鹅', 'EdmundDZhang', 5050, 398668, '', 0, 398668, 398668, 6850801, 0, 1, 433351],
    [20, 0, 6406234, '>50000', 0],
  ],
};

List<Object?> _meta({int color = 16777215, Object? time = 1790519893202, Object? nonce = 1790519804, Object? rich}) => [
  0, 1, 25, color, time, nonce, 0, '8z3o13gj', 0, 0, 0, '', 0, '{}', '{}', ?rich,
];

Map<String, Object?> _user(String name, {String? origin}) => {
  'user': {
    'base': {
      'name': name,
      if (origin != null) 'origin_info': {'name': origin},
    },
  },
};

/// The shape of S06-live's `super_chat_info.message_list[0]`, with a
/// synthetic user.
Map<String, Object?> _superChat({Object? face = 'https://i0.hdslb.com/bfs/face/member/noface.jpg', Object? end = 1790504255}) => {
  'id': 19298954,
  'uid': 1000,
  'price': 50,
  'rate': 1000,
  'background_image': '',
  'background_color': '#DBFFFD',
  'background_icon': '',
  'background_price_color': '#7DA4BD',
  'background_bottom_color': '#427D9E',
  'font_color': '',
  'time': 75,
  'start_time': 1790504135,
  'end_time': ?end,
  'message': '现在在巴塞看上海冠军赛，还好西班牙还好',
  'trans_mark': 0,
  'is_ranked': 0,
  'message_trans': '',
  'token': '00000000',
  'ts': 1790504180,
  'user_info': {
    'face': face,
    'face_frame': '',
    'uname': '醒目留言观众',
    'user_level': 12,
    'guard_level': 0,
    'is_vip': 0,
    'is_svip': 0,
    'is_main_vip': 0,
  },
};

List<(String, List<Uint8List>)> _vectorList() => [
  // Framing.
  ('zlib-nested-packets', [
    _zlib(_join([_notice(_danmu('first', user: [1000, 'alice'])), _notice(_danmu('second', user: [1001, 'bob']))])),
  ]),
  ('concatenated-packets', [
    _join([_online(12345), _notice(_danmu('visible')), _auth('{"code":0}')]),
  ]),
  ('zero-length-frame', [
    _join([_notice(_danmu('before malformed frame')), (ByteData(16)..setUint16(4, 16)).buffer.asUint8List()]),
    _notice(_danmu('next websocket message')),
  ]),
  ('truncated-tail', [
    _join([_notice(_danmu('before the tail')), [0, 0, 0, 40, 0, 16]]),
  ]),
  ('packet-past-the-end', [
    _join([_notice(_danmu('before the cut')), _notice(_danmu('cut off')).sublist(0, 30)]),
  ]),
  ('header-length-too-small', [
    _join([_notice(_danmu('before the bad header')), (ByteData(20)..setUint32(0, 20)..setUint16(4, 8)).buffer.asUint8List()]),
  ]),
  ('nesting-too-deep', [
    () {
      List<int> nested = _notice(_danmu('too deep'));
      for (var index = 0; index < 4; index++) {
        nested = _zlib(nested);
      }
      return Uint8List.fromList(nested);
    }(),
    _notice(_danmu('connection survives')),
  ]),
  ('nesting-at-the-limit', [
    _zlib(_zlib(_notice(_danmu('two levels')))),
  ]),
  ('corrupt-zlib', [
    _join([_notice(_danmu('before corrupt zlib')), _packet([1, 2, 3, 4, 5], operation: 5, protocolVersion: 2)]),
  ]),
  ('notice-versions', [
    _join([
      _notice(_danmu('protover 0')),
      _notice(_danmu('protover 1'), protocolVersion: 1),
      _notice(_danmu('protover 4'), protocolVersion: 4),
    ]),
  ]),
  ('unknown-operations', [
    _join([_packet(utf8.encode('{"cmd":"DANMU_MSG"}'), operation: 6), _packet(const [], operation: 2), _notice(_danmu('after'))]),
  ]),
  // Heartbeat reply.
  ('heartbeat-replies', [
    _online(1),
    _online(0),
    _online(4294967295),
    _online(7, length: 3),
    _online(9, length: 8),
  ]),
  // Auth replies.
  ('auth-accepted-once', [
    _auth('{"code":0}'),
    _auth('{"code":0}'),
    _auth(''),
  ]),
  ('auth-empty-body', [
    _auth('   '),
  ]),
  ('auth-code-as-text', [
    _auth('{"code":"0"}'),
  ]),
  ('auth-rejected', [
    _join([_auth('{"code":-101}'), _notice(_danmu('after the rejection'))]),
    _auth('{"code":-101}'),
  ]),
  ('auth-without-code', [
    _auth('{"msg":"ok"}'),
  ]),
  ('auth-not-an-object', [
    _auth('[0]'),
  ]),
  ('auth-invalid-json', [
    _join([_auth('not json'), _notice(_danmu('dropped with the rest'))]),
    _notice(_danmu('next message')),
  ]),
  ('auth-after-rejection', [
    _auth('{"code":-101}'),
    _auth('{"code":0}'),
  ]),
  // Chat.
  ('chat-colors', [
    _join([
      _notice(_danmu('zero', meta: _meta(color: 0))),
      _notice(_danmu('six digits', meta: _meta(color: 0xE33FFF))),
      _notice(_danmu('four digits', meta: _meta(color: 0xFFFC))),
      _notice(_danmu('blue', meta: _meta(color: 0x0000FF))),
      _notice(_danmu('five digits', meta: _meta(color: 0x0A0A0A))),
      _notice(_danmu('eight digits', meta: _meta(color: 0x80FF8800))),
      _notice(_danmu('text colour', meta: _meta(color: 0).toList()..[3] = '16777215')),
    ]),
  ]),
  ('chat-times-and-ids', [
    _join([
      _notice(_danmu('milliseconds', meta: _meta(time: 1790519893202, nonce: -1942957414))),
      _notice(_danmu('seconds', meta: _meta(time: 1790519893, nonce: 'abc'))),
      _notice(_danmu('time as text', meta: _meta(time: '1790519893202', nonce: ''))),
      _notice(_danmu('no time', meta: [0, 1, 25, 16777215])),
      _notice(_danmu('fraction', meta: _meta(time: 1790519893202.5, nonce: null))),
      _notice(_danmu('zero time', meta: _meta(time: 0, nonce: 1.5))),
    ]),
  ]),
  ('chat-shapes', [
    _join([
      _notice(_danmu('variant cmd', cmd: 'DANMU_MSG:4:0:2:2:2:0')),
      _notice(_danmu('no user list', user: null)),
      _notice(_danmu('empty user list', user: const [])),
      _notice(_danmu('short user list', user: const [1000])),
      _notice(_danmu('null user fields', user: const [null, null])),
      _notice(_danmu('short meta', meta: const [0, 1, 25])),
      _notice({'cmd': 'DANMU_MSG', 'info': const []}),
      _notice({'cmd': 'DANMU_MSG'}),
      _notice({
        'cmd': 'DANMU_MSG',
        'info': [_meta(), null, const [1000, 'viewer']],
      }),
      _notice({
        'cmd': 'DANMU_MSG',
        'info': [_meta(), 'two entries'],
      }),
      _notice(_danmu('last')),
    ]),
  ]),
  ('chat-names', [
    _join([
      _notice(_danmu('rich beats masked legacy', meta: _meta(rich: _user('完整用户名')), user: const [1000, '旧***'])),
      _notice(_danmu('legacy beats masked rich', meta: _meta(rich: _user('新***')), user: const [1000, '完整旧用户名'])),
      _notice(_danmu('rich as json text', meta: _meta(rich: jsonEncode(_user(''))), user: const [1000, '观***'])),
      _notice(_danmu('origin name', meta: _meta(rich: jsonEncode(_user('', origin: '原始名'))), user: const [1000, '观***'])),
      _notice(_danmu('rich without user key', meta: _meta(rich: {'base': {'name': ' 直接 '}}), user: const [1000, '观***'])),
      _notice(_danmu('broken json text', meta: _meta(rich: '{not json'), user: const [1000, '观***'])),
      _notice(_danmu('all masked', meta: _meta(rich: _user('观***')), user: const [1000, 'V***'])),
      _notice(_danmu('full-width mask', meta: _meta(rich: _user('用＊＊')), user: const [1000, '用户'])),
      _notice(_danmu('single star', meta: _meta(rich: _user('a*b')), user: const [1000, 'legacy'])),
      _notice({
        ..._danmu('top-level uinfo', user: const [1000, '观***']),
        'uinfo': {'base': {'name': '顶层名'}},
      }),
      _notice({
        ..._danmu('data uinfo', user: const [1000, '观***']),
        'data': {'uinfo': {'base': {'name': '数据名'}}},
      }),
      _notice(_danmu('empty legacy, masked rich', meta: _meta(rich: _user('观***')), user: const [1000, ''])),
      _notice(_danmu('untrimmed legacy', user: const [1000, ' 空格 '])),
    ]),
  ]),
  // Audience.
  ('watched-change', [
    _join([
      _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': 18342, 'text_small': '1.8万'}}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': '42'}}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': '6.2万'}}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': -1}}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': 0}}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': null}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': const [1]}),
      _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': 12.0}}),
    ]),
  ]),
  // Super chat.
  ('super-chat', [
    _join([
      _notice({'cmd': 'SUPER_CHAT_MESSAGE', 'data': _superChat(), 'roomid': 5050}),
      _notice({'cmd': 'SUPER_CHAT_MESSAGE', 'data': _superChat(face: '//i0.hdslb.com/bfs/face/member/noface.jpg')}),
      _notice({'cmd': 'SUPER_CHAT_MESSAGE', 'data': _superChat(end: null)}),
      _notice({'cmd': 'SUPER_CHAT_MESSAGE', 'data': null}),
      _notice({'cmd': 'SUPER_CHAT_MESSAGE_JPN', 'data': _superChat()}),
    ]),
  ]),
  // Acknowledgements.
  ('acknowledgements', [
    _join([
      _notice({..._danmu('ack me'), 'msg_id': 'fixture-message-id', 'p_is_ack': true, 'p_msg_type': 1}),
      _notice({..._danmu('ack with text type'), 'msg_id': ' id-2 ', 'p_is_ack': true, 'p_msg_type': '2'}),
      _notice({..._danmu('no msg_id'), 'p_is_ack': true, 'p_msg_type': 1}),
      _notice({..._danmu('no p_msg_type'), 'msg_id': 'id-3', 'p_is_ack': true}),
      _notice({..._danmu('null p_msg_type'), 'msg_id': 'id-4', 'p_is_ack': true, 'p_msg_type': null}),
      _notice({..._danmu('ack flag as text'), 'msg_id': 'id-5', 'p_is_ack': 'true', 'p_msg_type': 1}),
      _notice({'cmd': 'ONLINE_RANK_COUNT', 'msg_id': 'id-6', 'p_is_ack': true, 'p_msg_type': 3, 'data': {'count': 1}}),
    ]),
  ]),
  // Notices that are not handled.
  ('ignored-notices', [
    _join([
      _notice({'cmd': 'INTERACT_WORD_V2', 'data': {'dmscore': 4, 'pb': ''}}),
      _notice(const [1, 2, 3]),
      _notice('text'),
      _packet(utf8.encode('{not json'), operation: 5),
      _packet(utf8.encode('   '), operation: 5),
      _notice({'info': const []}),
      _notice(_danmu('still decoded')),
    ]),
  ]),
];

/// Protover 3 (brotli) vectors, M5.F B-3: the framing around brotli packets
/// and the faults of the stream itself.
List<(String, List<Uint8List>)> _brotliVectorList() => [
  ('brotli-nested-packets', [
    _brotli(_join([_notice(_danmu('first', user: [1000, 'alice'])), _notice(_danmu('second', user: [1001, 'bob']))])),
  ]),
  ('brotli-meta-blocks', [
    // Seven-byte meta-blocks: packet headers and JSON cross the borders.
    _brotli(_join([_notice(_danmu('split')), _notice({'cmd': 'WATCHED_CHANGE', 'data': {'num': 18342}})]), block: 7),
  ]),
  ('brotli-and-plain-packets', [
    _join([_online(1), _brotli(_notice(_danmu('compressed'))), _notice(_danmu('plain')), _auth('{"code":0}')]),
  ]),
  ('brotli-acknowledgement', [
    _brotli(_notice({..._danmu('ack me'), 'msg_id': 'fixture-message-id', 'p_is_ack': true, 'p_msg_type': 1})),
  ]),
  ('brotli-empty-stream', [
    _join([_brotli(const []), _notice(_danmu('after the empty stream'))]),
  ]),
  ('brotli-corrupt', [
    _join([
      _notice(_danmu('before corrupt brotli')),
      _packet([1, 2, 3, 4, 5], operation: 5, protocolVersion: 3),
      _notice(_danmu('dropped with the rest')),
    ]),
    _notice(_danmu('next websocket message')),
  ]),
  ('brotli-truncated', [
    () {
      final stream = _brotliStream(_notice(_danmu('cut off')));
      return _join([
        _notice(_danmu('before the truncated stream')),
        _packet(stream.sublist(0, stream.length - 2), operation: 5, protocolVersion: 3),
      ]);
    }(),
    _notice(_danmu('next websocket message')),
  ]),
  ('brotli-not-a-packet-stream', [
    _join([_brotli(utf8.encode('{"cmd":"DANMU_MSG"}')), _notice(_danmu('dropped with the rest'))]),
  ]),
  ('brotli-nesting-at-the-limit', [
    _brotli(_zlib(_notice(_danmu('brotli around zlib')))),
    _zlib(_brotli(_notice(_danmu('zlib around brotli')))),
    _brotli(_brotli(_notice(_danmu('brotli around brotli')))),
  ]),
  ('brotli-nesting-too-deep', [
    _brotli(_brotli(_brotli(_notice(_danmu('too deep'))))),
    _notice(_danmu('connection survives')),
  ]),
];

// 3.x ------------------------------------------------------------------------

const visibleForTesting = Object();

abstract final class CoreLog {
  static void error(Object? error) => _effects.add({'log': error.runtimeType.toString()});
}

/// The socket is never opened here; `_refreshCredentialsAndReconnect` closes it.
final class WebScoketUtils {
  Future<void> close() async => _effects.add({'close': true});

  void sendMessage(List<int> message) => throw StateError('packetSender takes the packets');
}

/// `package:brotli` does not resolve on Dart 3: its decoder, answered by
/// live_net's `brotliDecode` behind the same chunked sink (input buffered,
/// decoded at `close`, output in 16 KiB pieces).
abstract final class brotli {
  static Converter<List<int>, List<int>> get decoder => const _BrotliDecoder();
}

final class _BrotliDecoder extends Converter<List<int>, List<int>> {
  const _BrotliDecoder();

  @override
  List<int> convert(List<int> input) => brotliDecode(input);

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) => _BrotliSink(sink);
}

final class _BrotliSink implements Sink<List<int>> {
  _BrotliSink(this.sink);

  final Sink<List<int>> sink;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  void add(List<int> data) => _buffer.add(data);

  @override
  void close() {
    final output = brotliDecode(_buffer.takeBytes());
    for (var offset = 0; offset < output.length || offset == 0; offset += 16384) {
      sink.add(output.sublist(offset, offset + 16384 < output.length ? offset + 16384 : output.length));
    }
    sink.close();
  }
}

T? asT<T>(dynamic value) {
  if (value is T) {
    return value;
  }
  return null;
}

class BinaryWriter {
  List<int> buffer;
  int position = 0;
  BinaryWriter(this.buffer);
  int get length => buffer.length;

  void writeBytes(List<int> list) {
    buffer.addAll(list);
    position += list.length;
  }

  void writeInt(int value, int len, {Endian endian = Endian.big}) {
    var b = Uint8List(len).buffer;
    var bytes = ByteData.view(b);
    if (len == 1) {
      //写入byte
      bytes.setUint8(0, value.toUnsigned(8));
    }
    if (len == 2) {
      bytes.setInt16(0, value, endian);
    }
    if (len == 4) {
      bytes.setInt32(0, value, endian);
    }
    if (len == 8) {
      bytes.setInt64(0, value, endian);
    }

    buffer.addAll(bytes.buffer.asUint8List());
    position += len;
  }
}

enum LiveMessageType {
  /// 聊天
  chat,

  /// 礼物,暂时不支持
  gift,

  /// 在线人数
  online,

  /// 醒目留言
  superChat,
}

enum LiveAudienceMetricKind { popularity, onlineViewers, totalViewers }

class LiveAudienceUpdate {
  const LiveAudienceUpdate({required this.kind, required this.value});

  final LiveAudienceMetricKind kind;
  final int value;
}

class LiveMessage {
  final LiveMessageType type;
  final String userName;
  final String userId;
  final String message;
  final dynamic data;
  final LiveMessageColor color;
  final String userLevel;
  final String fansLevel;
  final String fansName;
  final bool isLocal;
  final String messageId;
  final DateTime? sentAt;

  LiveMessage({
    required this.type,
    required this.userName,
    this.userId = "",
    required this.message,
    this.data,
    required this.color,
    this.userLevel = "",
    this.fansLevel = "",
    this.fansName = "",
    this.isLocal = false,
    this.messageId = "",
    this.sentAt,
  });
}

class LiveMessageColor {
  final int r, g, b;
  const LiveMessageColor(this.r, this.g, this.b);
  static LiveMessageColor get white => LiveMessageColor(255, 255, 255);
  static LiveMessageColor numberToColor(int intColor) {
    var obj = intColor.toRadixString(16);

    LiveMessageColor color = LiveMessageColor.white;
    if (obj.length == 4) {
      obj = "00$obj";
    }
    if (obj.length == 6) {
      var R = int.parse(obj.substring(0, 2), radix: 16);
      var G = int.parse(obj.substring(2, 4), radix: 16);
      var B = int.parse(obj.substring(4, 6), radix: 16);

      color = LiveMessageColor(R, G, B);
    }
    if (obj.length == 8) {
      var R = int.parse(obj.substring(2, 4), radix: 16);
      var G = int.parse(obj.substring(4, 6), radix: 16);
      var B = int.parse(obj.substring(6, 8), radix: 16);
      //var A = int.parse(obj.substring(0, 2), radix: 16);
      color = LiveMessageColor(R, G, B);
    }

    return color;
  }

  @override
  String toString() {
    return "#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}";
  }
}

class LiveSuperChatMessage {
  final String messageId;
  final String userName;
  final String face;
  final String message;
  final int price;
  final DateTime startTime;
  final DateTime endTime;
  final String backgroundColor;
  final String backgroundBottomColor;

  LiveSuperChatMessage({
    this.messageId = '',
    required this.backgroundBottomColor,
    required this.backgroundColor,
    required this.endTime,
    required this.face,
    required this.message,
    required this.price,
    required this.startTime,
    required this.userName,
  });
}

class BiliBiliDanmakuArgs {
  final int roomId;
  final String token;
  final String buvid;
  final List<String> serverUrls;
  final int uid;
  final String cookie;
  final Map<String, dynamic> headers;
  final Future<BiliBiliDanmakuArgs?> Function()? refresh;
  BiliBiliDanmakuArgs({
    required this.roomId,
    required this.token,
    required this.serverUrls,
    required this.buvid,
    required this.uid,
    required this.cookie,
    this.headers = const {},
    this.refresh,
  });
}

class BiliBiliDanmaku {
  factory BiliBiliDanmaku({void Function(List<int> packet)? packetSender}) => BiliBiliDanmaku._(packetSender);

  BiliBiliDanmaku._(this._packetSender);

  final void Function(List<int> packet)? _packetSender;
  static const int _packetHeaderLength = 16;
  static const int _maxTransportMessageBytes = 8 * 1024 * 1024;
  static const int _maxDecompressedMessageBytes = 16 * 1024 * 1024;
  static const int _maxPacketsPerMessage = 4096;
  static const int _maxCompressedNestingDepth = 2;

  int heartbeatTime = 30 * 1000;
  bool _connected = false;

  bool get isConnected => _connected;

  void markConnected() {
    _connected = true;
  }

  void markDisconnected() {
    _connected = false;
  }

  Function(LiveMessage msg)? onMessage;
  Function(String msg)? onReconnect;
  Function(String msg)? onClose;
  Function()? onReady;

  WebScoketUtils? webScoketUtils;
  late BiliBiliDanmakuArgs danmakuArgs;
  bool _refreshingCredentials = false;
  bool _stopped = false;
  int _credentialRefreshCount = 0;
  Timer? _authTimer;

  /// Harness stub for 3.x's socket setup.
  Future<void> _connect(BiliBiliDanmakuArgs args) async => _effects.add({'connect': true});

  Future<void> _refreshCredentialsAndReconnect() async {
    if (_stopped || _refreshingCredentials || _credentialRefreshCount >= 3) return;
    _refreshingCredentials = true;
    _credentialRefreshCount++;
    try {
      final refreshed = await danmakuArgs.refresh?.call();
      if (_stopped || refreshed == null || refreshed.token.isEmpty) return;
      danmakuArgs = refreshed;
      await webScoketUtils?.close();
      if (_stopped) return;
      await _connect(refreshed);
    } catch (error) {
      CoreLog.error(error);
    } finally {
      _refreshingCredentials = false;
    }
  }

  void joinRoom(BiliBiliDanmakuArgs args) {
    _sendPacket(encodeData(json.encode(buildJoinPayload(args)), 7));
  }

  @visibleForTesting
  Map<String, dynamic> buildJoinPayload(BiliBiliDanmakuArgs args, {String? queueUuid}) {
    return {
      "uid": args.uid,
      "roomid": args.roomId,
      "protover": 3,
      "buvid": args.buvid,
      "support_ack": true,
      "queue_uuid": queueUuid ?? _newQueueUuid(),
      "scene": "room",
      "platform": "web",
      "type": 2,
      "key": args.token,
    };
  }

  String _newQueueUuid() {
    final random = Random.secure();
    return List<String>.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  void _sendPacket(List<int> packet) {
    final sender = _packetSender;
    if (sender != null) {
      sender(packet);
      return;
    }
    webScoketUtils?.sendMessage(packet);
  }

  void heartbeat() {
    _sendPacket(encodeData("", 2));
  }

  List<int> encodeData(String msg, int action) {
    var data = utf8.encode(msg);
    //头部长度固定16
    var length = data.length + 16;
    var buffer = Uint8List(length);

    var writer = BinaryWriter([]);

    //数据包长度
    writer.writeInt(buffer.length, 4);
    //数据包头部长度,固定16
    writer.writeInt(16, 2);

    //协议版本，0=JSON,1=Int32,2=Buffer
    writer.writeInt(0, 2);

    //操作类型
    writer.writeInt(action, 4);

    //数据包头部长度,固定1

    writer.writeInt(1, 4);

    writer.writeBytes(data);

    return writer.buffer;
  }

  void decodeMessage(List<int> data) {
    try {
      if (data.length > _maxTransportMessageBytes) {
        throw FormatException('Bilibili danmaku message is too large: ${data.length} bytes');
      }
      _decodePacketStream(data, depth: 0);
    } catch (e) {
      CoreLog.error(e);
    }
  }

  void _decodePacketStream(List<int> data, {required int depth}) {
    if (depth > _maxCompressedNestingDepth) {
      throw const FormatException('Bilibili danmaku packet nesting is too deep');
    }

    var offset = 0;
    var packetCount = 0;
    while (offset + _packetHeaderLength <= data.length) {
      packetCount++;
      if (packetCount > _maxPacketsPerMessage) {
        throw const FormatException('Bilibili danmaku message contains too many packets');
      }
      final packetLength = readInt(data, offset, 4);
      final headerLength = readInt(data, offset + 4, 2);
      final protocolVersion = readInt(data, offset + 6, 2);
      final operation = readInt(data, offset + 8, 4);

      if (headerLength < _packetHeaderLength ||
          packetLength < headerLength ||
          packetLength > _maxTransportMessageBytes ||
          offset + packetLength > data.length) {
        throw FormatException(
          'Invalid Bilibili danmaku frame: offset=$offset, packet=$packetLength, header=$headerLength, total=${data.length}',
        );
      }

      final body = data.sublist(offset + headerLength, offset + packetLength);
      _decodePacket(protocolVersion, operation, body, depth: depth);
      offset += packetLength;
    }

    if (offset != data.length) {
      throw FormatException('Incomplete Bilibili danmaku frame: parsed=$offset, total=${data.length}');
    }
  }

  void _decodePacket(int protocolVersion, int operation, List<int> body, {required int depth}) {
    if (operation == 3) {
      if (body.length < 4) return;
      final online = readInt(body, 0, 4);
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.online,
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.popularity, value: online),
          color: LiveMessageColor.white,
          message: "",
          userName: "",
        ),
      );
      return;
    }

    if (operation == 5) {
      if (protocolVersion == 2 || protocolVersion == 3) {
        final decoded = _decodeCompressedBody(body, protocolVersion);
        _decodePacketStream(decoded, depth: depth + 1);
      } else {
        final text = utf8.decode(body, allowMalformed: true).trim();
        if (text.isNotEmpty) parseMessage(text);
      }
      return;
    }

    if (operation == 8) {
      // The transport is usable only after Bilibili acknowledges auth.
      final text = utf8.decode(body, allowMalformed: true).trim();
      final dynamic decoded = text.isEmpty ? const <String, dynamic>{'code': 0} : json.decode(text);
      final auth = decoded is Map ? decoded : const <String, dynamic>{};
      final code = int.tryParse(auth['code']?.toString() ?? '') ?? -1;
      if (code == 0 && !isConnected) {
        _authTimer?.cancel();
        markConnected();
        heartbeat();
        onReady?.call();
      } else if (code != 0) {
        _authTimer?.cancel();
        markDisconnected();
        unawaited(_refreshCredentialsAndReconnect());
      }
    }
  }

  List<int> _decodeCompressedBody(List<int> body, int protocolVersion) {
    final sink = _BoundedBytesSink(_maxDecompressedMessageBytes);
    final decoder = protocolVersion == 2 ? zlib.decoder : brotli.decoder;
    final conversion = decoder.startChunkedConversion(sink);
    conversion.add(body);
    conversion.close();
    return sink.takeBytes();
  }

  void parseMessage(String jsonMessage) {
    try {
      var obj = json.decode(jsonMessage);
      _acknowledgeIfRequired(obj);
      var cmd = obj["cmd"].toString();
      if (cmd.contains("DANMU_MSG")) {
        if (obj["info"] != null && obj["info"].length != 0) {
          var message = obj["info"][1].toString();
          var color = asT<int?>(obj["info"][0][3]) ?? 0;
          if (obj["info"][2] != null && obj["info"][2].length != 0) {
            final metadata = obj["info"][0] is List ? obj["info"][0] as List : const <dynamic>[];
            final username = _preferredBilibiliUserName(obj, metadata, obj["info"][2][1]?.toString() ?? '');
            final rawTimestamp = metadata.length > 4 ? int.tryParse(metadata[4]?.toString() ?? '') : null;
            final rawNonce = metadata.length > 5 ? metadata[5]?.toString() ?? '' : '';
            final sentAt = rawTimestamp == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(rawTimestamp > 100000000000 ? rawTimestamp : rawTimestamp * 1000);
            var liveMsg = LiveMessage(
              type: LiveMessageType.chat,
              userName: username,
              userId: obj["info"][2][0]?.toString() ?? '',
              message: message,
              color: color == 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
              messageId: rawNonce.isEmpty ? '' : 'bilibili:$rawNonce',
              sentAt: sentAt,
            );
            onMessage?.call(liveMsg);
          }
        }
      } else if (cmd == "WATCHED_CHANGE") {
        final value = int.tryParse(obj["data"]?["num"]?.toString() ?? '');
        if (value != null && value >= 0) {
          onMessage?.call(
            LiveMessage(
              type: LiveMessageType.online,
              data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.totalViewers, value: value),
              color: LiveMessageColor.white,
              message: "",
              userName: "",
            ),
          );
        }
      } else if (cmd == "SUPER_CHAT_MESSAGE") {
        if (obj["data"] == null) {
          return;
        }
        LiveSuperChatMessage sc = LiveSuperChatMessage(
          backgroundBottomColor: obj["data"]["background_bottom_color"].toString(),
          backgroundColor: obj["data"]["background_color"].toString(),
          endTime: DateTime.fromMillisecondsSinceEpoch(obj["data"]["end_time"] * 1000),
          face: "${obj["data"]["user_info"]["face"]}@200w.jpg",
          message: obj["data"]["message"].toString(),
          price: obj["data"]["price"],
          startTime: DateTime.fromMillisecondsSinceEpoch(obj["data"]["start_time"] * 1000),
          userName: obj["data"]["user_info"]["uname"].toString(),
        );
        var liveMsg = LiveMessage(
          type: LiveMessageType.superChat,
          userName: "SUPER_CHAT_MESSAGE",
          message: "SUPER_CHAT_MESSAGE",
          color: LiveMessageColor.white,
          data: sc,
        );
        onMessage?.call(liveMsg);
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  void _acknowledgeIfRequired(dynamic packet) {
    if (packet is! Map || packet['p_is_ack'] != true) return;
    final msgId = packet['msg_id']?.toString().trim() ?? '';
    final cmd = packet['cmd']?.toString().trim() ?? '';
    if (!packet.containsKey('p_msg_type')) return;
    final msgType = int.tryParse(packet['p_msg_type']?.toString() ?? '');
    if (msgId.isEmpty || cmd.isEmpty || msgType == null) return;
    _sendPacket(encodeData(json.encode({'msg_id': msgId, 'cmd': cmd, 'p_msg_type': msgType}), 24));
  }

  String _preferredBilibiliUserName(dynamic packet, List<dynamic> metadata, String legacyName) {
    dynamic richInfo;
    if (metadata.length > 15) richInfo = metadata[15];
    if (richInfo is String && richInfo.trimLeft().startsWith('{')) {
      try {
        richInfo = json.decode(richInfo);
      } catch (_) {
        richInfo = null;
      }
    }

    String readName(dynamic root) {
      if (root is! Map) return '';
      final user = root['user'] is Map ? root['user'] : root;
      if (user is! Map) return '';
      final base = user['base'];
      if (base is! Map) return '';
      final name = base['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
      final origin = base['origin_info'];
      return origin is Map ? origin['name']?.toString().trim() ?? '' : '';
    }

    dynamic packetUserInfo;
    dynamic packetDataUserInfo;
    if (packet is Map) {
      packetUserInfo = packet['uinfo'];
      final data = packet['data'];
      if (data is Map) packetDataUserInfo = data['uinfo'];
    }
    final candidates = <String>[];
    for (final candidate in [richInfo, packetUserInfo, packetDataUserInfo]) {
      final name = readName(candidate);
      if (name.isNotEmpty) candidates.add(name);
    }
    final masked = RegExp(r'\*{2,}|＊{2,}');
    for (final candidate in [...candidates, legacyName]) {
      if (candidate.isNotEmpty && !masked.hasMatch(candidate)) return candidate;
    }
    return candidates.isNotEmpty ? candidates.first : legacyName;
  }

  int readInt(List<int> buffer, int start, int len) {
    var bytes = Uint8List.fromList(buffer.getRange(start, start + len).toList());
    var byteBuffer = bytes.buffer;
    var data = ByteData.view(byteBuffer);
    var result = 0;

    if (len == 1) {
      result = data.getUint8(0);
    }
    if (len == 2) {
      result = data.getUint16(0, Endian.big);
    }
    if (len == 4) {
      result = data.getUint32(0, Endian.big);
    }
    if (len == 8) {
      result = data.getInt64(0, Endian.big);
    }

    return result;
  }
}

class _BoundedBytesSink implements Sink<List<int>> {
  _BoundedBytesSink(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _length = 0;
  bool _closed = false;

  @override
  void add(List<int> data) {
    if (_closed) throw StateError('Bilibili decompression sink is closed');
    if (data.length > limit - _length) {
      throw FormatException('Bilibili decompressed message exceeds $limit bytes');
    }
    _length += data.length;
    _builder.add(data);
  }

  @override
  void close() {
    _closed = true;
  }

  Uint8List takeBytes() => _builder.takeBytes();
}
