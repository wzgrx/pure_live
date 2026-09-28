// Writes fixtures/douyin/danmaku/*/expected.json: what 3.x's Douyin danmaku
// decoder did with every received frame (docs/modules/M5.4-douyin.md,
// "v3 的冻结输出"), and S13-vectors/frames.jsonl.
//
// The code between the "3.x" markers is 3.x's DouyinDanmaku copied from
// legacy/lib/core/danmaku/douyin_danmaku.dart (archive/v4): decodeMessage,
// unPackWebcastChatMessage, unPackWebcastRoomUserSeqMessage, sendAck,
// heartbeat, joinRoom, buildServerUrls, buildHandshakeHeaders and the query
// of `start`, with DouyinDanmakuArgs, DouyinRequestParams
// (core/utils/douyin/douyin_request_params.dart), LiveRoom.parseAudienceNumber
// (common/models/live_room.dart) and the parts of LiveMessage,
// LiveMessageColor and LiveAudienceUpdate it uses
// (common/models/live_message.dart). Its protobuf classes are 3.x's generated
// ones (legacy/lib/core/danmaku/proto/douyin.pb.dart) on 3.x's runtime
// (protobuf 6.1.0, fixnum 1.1.x). Only these are replaced:
//
// - `WebScoketUtils` by a stub whose `sendMessage` records the frame;
// - `CoreLog` by the harness's log (the error's type is recorded);
// - `start`, `stop` and `getSignature` (the socket's lifecycle and the random
//   X-Bogus, which M4.4 checked against 3.x) are left out; the `onMessage`
//   callback of `start` (decode inside try/catch) is copied as [_receive].
//
// One 3.x instance replays one sample (S13-live) or one vector (S13-vectors),
// like one connection, with `danmakuArgs` set to the room's arguments. For
// every received frame, in order, the harness records the effects: frames
// sent (Base64), messages (projected) and logged errors (their type).
//
// S13-vectors is synthetic: this file writes its frames.jsonl as well, built
// with 3.x's generated classes (raw bytes where a vector needs a malformed or
// unusual encoding).
//
// The protobuf runtime is not a workspace dependency, so this file runs in a
// throwaway package that legacy_expected.sh builds from the pub cache and
// archive/v4. Run from the repository root:
//
//   bash fixtures/douyin/danmaku/legacy_expected.sh
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';

import 'proto/douyin.pb.dart';

late final String _root;
const _generator =
    '3.x DouyinDanmaku.decodeMessage, one instance per sample or vector '
    '(fixtures/douyin/danmaku/legacy_expected.dart, run by legacy_expected.sh)';

void main(List<String> arguments) {
  _root = '${arguments.isEmpty ? '.' : arguments.single}/fixtures/douyin/danmaku';
  _live();
  _vectors();
}

// Harness --------------------------------------------------------------------

final List<Map<String, Object?>> _effects = [];

DouyinDanmaku _instance(DouyinDanmakuArgs args) {
  final danmaku = DouyinDanmaku()
    ..danmakuArgs = args
    ..webScoketUtils = WebScoketUtils((frame) => _effects.add({'send': base64.encode(frame)}));
  danmaku.onMessage = (message) => _effects.add({'message': _project(message)});
  return danmaku;
}

/// The `onMessage` callback 3.x's `start` gives WebScoketUtils.
List<Map<String, Object?>> _receive(DouyinDanmaku danmaku, List<int> frame) {
  _effects.clear();
  try {
    danmaku.decodeMessage(frame);
  } catch (e) {
    CoreLog.error(e);
  }
  return List.of(_effects);
}

Map<String, Object?> _args(DouyinDanmakuArgs args) => {
  'webRid': args.webRid,
  'roomId': args.roomId,
  'userId': args.userId,
  'cookie': args.cookie,
};

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
    final other => '$other',
  },
};

void _write(String sample, Object? value) {
  File('$_root/$sample/expected.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': _generator, 'value': value})}\n',
  );
  stdout.writeln('wrote $_root/$sample/expected.json');
}

// S13-live ---------------------------------------------------------------------

void _live() {
  final meta = jsonDecode(File('$_root/S13-live/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final keys = meta['danmakuKeys'] as Map<String, dynamic>;
  final args = DouyinDanmakuArgs(
    webRid: keys['webRid'] as String,
    roomId: keys['roomId'] as String,
    userId: keys['userUniqueId'] as String,
    cookie: '',
  );
  final recorded = Uri.parse((meta['handshakes'] as List).first['url'] as String);
  final cursor = recorded.queryParameters['cursor']!;
  final ts = int.parse(RegExp(r'_t-(\d+)_').firstMatch(cursor)!.group(1)!);
  final signature = recorded.queryParameters['signature']!;

  final danmaku = _instance(args);
  final lines = File('$_root/S13-live/frames.jsonl').readAsLinesSync();
  final frames = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    final line = jsonDecode(lines[index]) as Map<String, dynamic>;
    if (line['dir'] != 'in') continue;
    frames.add({'line': index + 1, 'effects': _receive(danmaku, base64.decode(line['b64'] as String))});
  }

  _effects.clear();
  danmaku.heartbeat();
  final heartbeat = _effects.single['send'];
  _effects.clear();
  danmaku.joinRoom(args);
  final join = _effects.single['send'];

  _write('S13-live', {
    'args': _args(args),
    'heartbeat': heartbeat,
    'join': join,
    // The query of `start` at the recorded cursor time, signed with the
    // recorded signature.
    'cursorTime': ts,
    'signature': signature,
    'endpoints': DouyinDanmaku.buildServerUrls(danmaku.baseUri(ts), signature: signature),
    'headers': DouyinDanmaku.buildHandshakeHeaders(args),
    'headersWithCookie': DouyinDanmaku.buildHandshakeHeaders(
      DouyinDanmakuArgs(webRid: args.webRid, roomId: args.roomId, userId: args.userId, cookie: 'ttwid=1%7Csynthetic'),
    ),
    'headersWithBlankCookie': DouyinDanmaku.buildHandshakeHeaders(
      DouyinDanmakuArgs(webRid: args.webRid, roomId: args.roomId, userId: args.userId, cookie: '  '),
    ),
    'frames': frames,
  });
}

// S13-vectors ------------------------------------------------------------------

const _room = '7690000000000000001';
const _webRid = '100000000001';
const _visitor = '7300000000000000001';
final _defaultArgs = DouyinDanmakuArgs(webRid: _webRid, roomId: _room, userId: _visitor, cookie: '');

/// A uint64 from its decimal text (values above 2^63 wrap, as on the wire).
Int64 _u64(String decimal) => Int64(BigInt.parse(decimal).toSigned(64).toInt());

const _ext = 'internal_src:pushserver|first_req_ms:1790519971025|wss_msg_type:r|wrds_v:7690224713984906537';

List<HeadersList> _headers() => [
  HeadersList(key: 'compress_type', value: 'gzip'),
  HeadersList(key: 'im-internal_ext', value: _ext),
];

/// A `msg` frame: [response] as the payload, gzipped unless [encoding] says
/// otherwise (`pb` is plain, as in S13-live).
List<int> _frame(
  List<int> response, {
  String encoding = 'pb',
  bool gzipped = false,
  int? logId = 4901453207607389421,
  String type = 'msg',
}) => PushFrame(
  seqId: Int64(1),
  logId: logId == null ? null : Int64(logId),
  service: Int64(8888),
  method: Int64(8),
  headersList: _headers(),
  payloadEncoding: encoding,
  payloadType: type,
  payload: gzipped ? gzip.encode(response) : response,
).writeToBuffer();

List<int> _response(List<Message> messages, {bool needAck = true, String internalExt = _ext}) => Response(
  messagesList: messages,
  cursor: 't-1790519971068_r-7690224709690737126_d-1_u-1',
  now: Int64(1790519971068),
  internalExt: internalExt,
  heartbeatDuration: Int64(15),
  needAck: needAck,
).writeToBuffer();

Message _envelope(String method, List<int> payload, {int msgId = 7690224709082037814}) =>
    Message(method: method, payload: payload, msgId: Int64(msgId));

Common _common({Int64? msgId, Int64? roomId, Int64? createTime}) => Common(
  method: 'WebcastChatMessage',
  msgId: msgId ?? Int64(7690224691106976802),
  roomId: roomId ?? _u64(_room),
  createTime: createTime,
  isShowMsg: true,
  priorityScore: Int64(31029),
);

List<int> _chat(
  String content, {
  Common? common,
  bool withCommon = true,
  User? user,
  bool withUser = true,
  int eventTime = 1790519968,
}) => ChatMessage(
  common: withCommon ? (common ?? _common()) : null,
  user: withUser ? (user ?? User(id: Int64(579432622234547), nickName: '观众1')) : null,
  content: content,
  eventTime: Int64(eventTime),
).writeToBuffer();

List<int> _seq(String? online, {int total = 305503}) => RoomUserSeqMessage(
  common: Common(method: 'WebcastRoomUserSeqMessage', msgId: Int64(7690224703739085327), roomId: _u64(_room)),
  total: Int64(total),
  totalUser: Int64(7227121),
  totalUserStr: '10万+',
  totalStr: '10万+',
  onlineUserForAnchor: online,
  totalPvForAnchor: '722.7万',
).writeToBuffer();

/// Raw protobuf pieces, for encodings the generated classes never write.
List<int> _varint(int value) {
  final out = <int>[];
  var rest = value;
  while (true) {
    final byte = rest & 0x7f;
    rest = rest >>> 7;
    if (rest == 0) {
      out.add(byte);
      return out;
    }
    out.add(byte | 0x80);
  }
}

List<int> _field(int number, int wireType) => _varint(number << 3 | wireType);
List<int> _rawInt(int number, int value) => [..._field(number, 0), ..._varint(value)];
List<int> _rawBytes(int number, List<int> value) => [..._field(number, 2), ..._varint(value.length), ...value];
List<int> _rawString(int number, String value) => _rawBytes(number, utf8.encode(value));

typedef _Vector = ({String name, DouyinDanmakuArgs args, List<List<int>> frames});

List<_Vector> _vectorList() {
  final big = DouyinDanmakuArgs(webRid: _webRid, roomId: '9300000000000000001', userId: _visitor, cookie: '');
  final chat = _envelope('WebcastChatMessage', _chat('第一条'));
  return [
    (
      name: 'plain-payload-with-ack',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            chat,
            _envelope('WebcastChatMessage', _chat('第二条', user: User(id: Int64(8727542766180611), nickName: 'k!'))),
          ]),
        ),
      ],
    ),
    (name: 'gzip-by-encoding', args: _defaultArgs, frames: [_frame(_response([chat]), encoding: 'gzip', gzipped: true)]),
    (name: 'gzip-encoding-upper-case', args: _defaultArgs, frames: [_frame(_response([chat]), encoding: 'GZIP', gzipped: true)]),
    (name: 'gzip-encoding-upper-case-on-plain-payload', args: _defaultArgs, frames: [_frame(_response([chat]), encoding: 'GZIP')]),
    (name: 'gzip-by-magic-bytes', args: _defaultArgs, frames: [_frame(_response([chat]), encoding: '', gzipped: true)]),
    (name: 'gzip-encoding-on-plain-payload', args: _defaultArgs, frames: [_frame(_response([chat]), encoding: 'gzip')]),
    (name: 'no-ack-requested', args: _defaultArgs, frames: [_frame(_response([chat], needAck: false))]),
    (
      name: 'ack-without-log-id-or-internal-ext',
      args: _defaultArgs,
      frames: [_frame(_response([chat], internalExt: ''), logId: null)],
    ),
    (
      name: 'ack-log-id-above-2^63',
      args: _defaultArgs,
      frames: [
        PushFrame(
          logId: _u64('18446744073709551615'),
          payloadEncoding: 'pb',
          payloadType: 'msg',
          payload: _response([]),
        ).writeToBuffer(),
      ],
    ),
    (
      name: 'need-ack-varint-with-high-bits-only',
      args: _defaultArgs,
      frames: [
        _frame([..._rawBytes(1, chat.writeToBuffer()), ..._rawString(5, _ext), ..._rawInt(9, 1 << 32)]),
        _frame([..._rawBytes(1, chat.writeToBuffer()), ..._rawString(5, _ext), ..._rawInt(9, (1 << 32) | 1)]),
      ],
    ),
    (
      name: 'chat-times',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', _chat('毫秒', common: _common(createTime: Int64(1790519968123)))),
            _envelope('WebcastChatMessage', _chat('秒', common: _common(createTime: Int64(1790519968)))),
            _envelope('WebcastChatMessage', _chat('零', common: _common(createTime: Int64(0)))),
            _envelope('WebcastChatMessage', _chat('只有 eventTime')),
            _envelope('WebcastChatMessage', _chat('1e11 整', common: _common(createTime: Int64(100000000000)))),
          ]),
        ),
      ],
    ),
    (
      name: 'chat-message-ids',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', _chat('common id')),
            _envelope('WebcastChatMessage', _chat('envelope id', common: _common(msgId: Int64(0))), msgId: 42),
            _envelope('WebcastChatMessage', _chat('no id', common: _common(msgId: Int64(0))), msgId: 0),
            _envelope('WebcastChatMessage', _chat('no common', withCommon: false), msgId: 43),
            _envelope('WebcastChatMessage', _chat('negative envelope', common: _common(msgId: Int64(0))), msgId: -5),
          ]),
        ),
      ],
    ),
    (
      name: 'chat-rooms',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', _chat('this room')),
            _envelope('WebcastChatMessage', _chat('other room', common: _common(roomId: Int64(7690000000000000002)))),
            _envelope('WebcastChatMessage', _chat('room 0', common: _common(roomId: Int64(0)))),
            _envelope('WebcastChatMessage', _chat('no common', withCommon: false)),
          ]),
        ),
      ],
    ),
    (
      name: 'chat-without-user-or-content',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', _chat('no user', withUser: false)),
            _envelope('WebcastChatMessage', _chat('')),
            _envelope('WebcastChatMessage', _chat('user without name', user: User(id: Int64(12)))),
          ]),
        ),
      ],
    ),
    (
      name: 'chat-with-full-user-and-extras',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope(
              'WebcastChatMessage',
              ChatMessage(
                common: _common(createTime: Int64(1790519968000)),
                user: User(
                  id: Int64(29022464958),
                  shortId: Int64(123456),
                  nickName: '观众3',
                  level: 12,
                  avatarThumb: Image(urlListList: ['https://p3.douyinpic.com/aweme/100x100/synthetic.jpeg'], uri: 'synthetic'),
                  badgeImageList: [Image(urlListList: ['https://p3.douyinpic.com/badge/synthetic.png'])],
                  followInfo: FollowInfo(followerCount: Int64(10)),
                  displayId: 'synthetic_display',
                  secUid: 'MS4wLjABAAAAsynthetic',
                ),
                content: '左上角有苹果18手机',
                fullScreenTextColor: '#FFFFFF',
                priorityLevel: 3,
                eventTime: Int64(1790519968),
                rtfContent: Text(key: 'synthetic', defaultPatter: '{0}'),
              ).writeToBuffer(),
            ),
          ]),
        ),
      ],
    ),
    (
      name: 'chat-common-split-in-two',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', [
              ..._rawBytes(1, Common(roomId: _u64(_room), createTime: Int64(1790519968)).writeToBuffer()),
              ..._rawBytes(2, User(id: Int64(1), nickName: 'first').writeToBuffer()),
              ..._rawString(3, 'merged'),
              ..._rawBytes(1, Common(msgId: Int64(99)).writeToBuffer()),
              ..._rawBytes(2, User(nickName: 'second').writeToBuffer()),
            ]),
          ]),
        ),
      ],
    ),
    (
      name: 'chat-fields-with-other-wire-types',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', [
              ..._rawBytes(1, Common(roomId: _u64(_room), msgId: Int64(7)).writeToBuffer()),
              ..._rawString(3, 'kept'),
              ..._rawInt(3, 5),
              ..._rawBytes(2, [..._rawInt(1, 31), ..._rawString(3, 'name'), ..._rawInt(3, 9)]),
            ]),
            _envelope('WebcastChatMessage', [..._rawInt(1, 5), ..._rawString(3, 'common as varint')]),
          ]),
        ),
      ],
    ),
    (
      name: 'online-counts',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastRoomUserSeqMessage', _seq('30.6万')),
            _envelope('WebcastRoomUserSeqMessage', _seq('1,234')),
            _envelope('WebcastRoomUserSeqMessage', _seq('1.2w')),
            _envelope('WebcastRoomUserSeqMessage', _seq('2000+')),
            _envelope('WebcastRoomUserSeqMessage', _seq('暂无')),
            _envelope('WebcastRoomUserSeqMessage', _seq('')),
            _envelope('WebcastRoomUserSeqMessage', _seq(null, total: 42)),
            _envelope('WebcastRoomUserSeqMessage', _seq('0')),
          ]),
        ),
      ],
    ),
    (
      name: 'other-methods-ignored',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastMemberMessage', []),
            _envelope('WebcastGiftMessage', GiftMessage(giftId: Int64(1), repeatCount: Int64(1)).writeToBuffer()),
            _envelope('WebcastLikeMessage', LikeMessage(count: Int64(3)).writeToBuffer()),
            _envelope('WebcastSocialMessage', []),
            _envelope('webcastchatmessage', _chat('method is case-sensitive')),
          ]),
        ),
      ],
    ),
    (
      name: 'server-heartbeat-reply',
      args: _defaultArgs,
      frames: [
        PushFrame(
          seqId: Int64(5),
          service: Int64(8888),
          method: Int64(8),
          headersList: [HeadersList(key: 'server_time', value: '1790519971087')],
          payloadType: 'hb',
          payload: gzip.encode(const []),
        ).writeToBuffer(),
        PushFrame(payloadType: 'hb').writeToBuffer(),
      ],
    ),
    (
      name: 'malformed-frames',
      args: _defaultArgs,
      frames: [
        _frame(_response([chat])).sublist(0, 20),
        _frame(_response([chat]).sublist(0, 40)),
        _frame([..._rawString(5, _ext), ..._rawInt(9, 1), ..._rawBytes(1, chat.writeToBuffer().sublist(0, 12))]),
        _frame([..._rawString(5, _ext), ..._rawInt(9, 1), ..._rawBytes(7, [0x0a, 0x05, 0x6b])]),
        [..._rawString(7, 'msg'), ..._rawBytes(5, [0x0a, 0x09, 0x61])],
        _frame([0x00]),
        [0x3a, 0x02, 0x68],
        [],
        PushFrame(
          logId: Int64(1),
          payloadEncoding: 'gzip',
          payloadType: 'msg',
          payload: gzip.encode(_response([chat])).sublist(0, 60),
        ).writeToBuffer(),
        PushFrame(
          logId: Int64(1),
          payloadEncoding: 'gzip',
          payloadType: 'msg',
          payload: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xde, 0xad, 0xbe, 0xef],
        ).writeToBuffer(),
      ],
    ),
    (
      name: 'malformed-chat-before-good-chat',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', _chat('lost').sublist(0, 30)),
            _envelope('WebcastChatMessage', _chat('after the bad one')),
            _envelope('WebcastRoomUserSeqMessage', _seq('30.6万')),
          ]),
        ),
      ],
    ),
    (
      name: 'malformed-online-before-good-chat',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastRoomUserSeqMessage', [..._rawString(10, '30.6万'), 0x08]),
            _envelope('WebcastChatMessage', _chat('after the bad one')),
          ]),
        ),
      ],
    ),
    (
      name: 'create-time-out-of-range',
      args: _defaultArgs,
      frames: [
        _frame(
          _response([
            _envelope('WebcastChatMessage', _chat('far future', common: _common(createTime: Int64(9000000000000000)))),
            _envelope('WebcastChatMessage', _chat('after it')),
          ]),
        ),
      ],
    ),
    (
      name: 'uint64-ids-above-2^63',
      args: big,
      frames: [
        _frame(
          _response([
            _envelope(
              'WebcastChatMessage',
              _chat(
                'room id past 2^63',
                common: _common(roomId: _u64(big.roomId), msgId: _u64('9300000000000000002')),
                user: User(id: _u64('18446744073709551615'), nickName: 'max'),
              ),
            ),
          ]),
        ),
      ],
    ),
  ];
}

void _vectors() {
  final lines = <String>[];
  final vectors = <Map<String, Object?>>[];
  for (final vector in _vectorList()) {
    final danmaku = _instance(vector.args);
    final frames = <Map<String, Object?>>[];
    for (final frame in vector.frames) {
      lines.add(jsonEncode({'vector': vector.name, 'dir': 'in', 't': 0, 'b64': base64.encode(frame)}));
      frames.add({'line': lines.length, 'effects': _receive(danmaku, frame)});
    }
    vectors.add({'vector': vector.name, 'args': _args(vector.args), 'frames': frames});
  }
  File('$_root/S13-vectors/frames.jsonl').writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln('wrote $_root/S13-vectors/frames.jsonl');
  _write('S13-vectors', {'vectors': vectors});
}

// Stubs for what 3.x's DouyinDanmaku imports ----------------------------------

abstract final class CoreLog {
  static void error(Object? message) {
    stderr.writeln('CoreLog.error: $message');
    _effects.add({'error': message is String ? 'String' : '${message.runtimeType}'});
  }
}

class WebScoketUtils {
  WebScoketUtils(this._send);

  final void Function(List<int> frame) _send;

  void sendMessage(dynamic message) => _send(message as List<int>);
}

const visibleForTesting = Object();

enum LiveMessageType { chat, gift, online, superChat }

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

  @override
  String toString() {
    return "#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}";
  }
}

abstract final class LiveRoom {
  static int parseAudienceNumber(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return 0;
    final normalized = text.replaceAll(',', '').replaceAll('，', '');
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(亿|万|千|[kwm])?').firstMatch(normalized);
    final number = double.tryParse(match?.group(1) ?? '') ?? 0;
    final multiplier = switch (match?.group(2)) {
      '亿' => 100000000,
      '万' || 'w' => 10000,
      '千' || 'k' => 1000,
      'm' => 1000000,
      _ => 1,
    };
    return (number * multiplier).round();
  }
}

mixin DouyinRequestParams {
  static const String browserVersion =
      "5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";
  static const String kDefaultUserAgent = "Mozilla/$browserVersion";
  static const aidValue = "6383";
  static const versionCodeValue = "180800";
  static const sdkVersion = "1.0.15";
}

// 3.x ------------------------------------------------------------------------
// legacy/lib/core/danmaku/douyin_danmaku.dart (archive/v4).

class DouyinDanmakuArgs {
  final String webRid;
  final String roomId;
  final String userId;
  final String cookie;

  DouyinDanmakuArgs({required this.webRid, required this.roomId, required this.userId, required this.cookie});
}

class DouyinDanmaku {
  Function(LiveMessage msg)? onMessage;
  static const String _webSocketPath = "/webcast/im/push/v2/";
  static const List<String> _webSocketHosts = <String>[
    // Current web rooms are distributed between the low- and high-latency
    // webcast100 pools. A single hard-coded pool made otherwise healthy rooms
    // appear to have no danmaku whenever that edge rejected the handshake.
    "webcast100-ws-web-lq.douyin.com",
    "webcast100-ws-web-hl.douyin.com",
  ];
  String serverUrl = "wss://${_webSocketHosts.first}$_webSocketPath";
  late DouyinDanmakuArgs danmakuArgs;
  WebScoketUtils? webScoketUtils;

  /// The URI `start` builds before signing, at cursor time [ts] (3.x read
  /// `DateTime.now()` there).
  Uri baseUri(int ts) {
    var uri = Uri.parse(serverUrl).replace(
      scheme: "wss",
      queryParameters: {
        "app_name": "douyin_web",
        "version_code": DouyinRequestParams.versionCodeValue,
        "webcast_sdk_version": DouyinRequestParams.sdkVersion,
        "update_version_code": DouyinRequestParams.sdkVersion,
        "compress": "gzip",
        "cursor": "h-1_t-${ts}_r-1_d-1_u-1",
        "host": "https://live.douyin.com",
        "aid": "6383",
        "live_id": "1",
        "did_rule": "3",
        "debug": "false",
        "maxCacheMessageNumber": "20",
        "endpoint": "live_pc",
        "support_wrds": "1",
        "im_path": "/webcast/im/fetch/",
        "user_unique_id": danmakuArgs.userId,
        "device_platform": "web",
        "cookie_enabled": "true",
        "screen_width": "1920",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Mozilla",
        "browser_version": DouyinRequestParams.browserVersion,
        "browser_online": "true",
        "tz_name": "Asia/Shanghai",
        "identity": "audience",
        "room_id": danmakuArgs.roomId,
        "need_persist_msg_count": "15",
        "heartbeatDuration": "0",
        //"signature": "00000000"
      },
    );
    return uri;
  }

  /// Builds equivalent signed URLs for every current web IM edge.
  ///
  /// The signature alphabet contains `+` and `/`. Appending it as a raw string
  /// changed `+` into a query-space on some HTTP stacks, so failures depended
  /// on the random signature generated for that particular room attempt.
  @visibleForTesting
  static List<String> buildServerUrls(Uri baseUri, {required String signature}) {
    final signed = baseUri.replace(
      path: _webSocketPath,
      queryParameters: <String, String>{...baseUri.queryParameters, "signature": signature},
    );
    return List<String>.unmodifiable(
      _webSocketHosts.map((host) => signed.replace(scheme: "wss", host: host).toString()),
    );
  }

  @visibleForTesting
  static Map<String, dynamic> buildHandshakeHeaders(DouyinDanmakuArgs args) {
    return <String, dynamic>{
      "User-Agent": DouyinRequestParams.kDefaultUserAgent,
      if (args.cookie.trim().isNotEmpty) "Cookie": args.cookie,
      "Origin": "https://live.douyin.com",
      "Referer": "https://live.douyin.com/${args.webRid}",
    };
  }

  void heartbeat() {
    var obj = PushFrame();
    obj.payloadType = 'hb';
    webScoketUtils?.sendMessage(obj.writeToBuffer());
  }

  void decodeMessage(List<int> args) {
    // CoreLog.i(args.toString());

    var wssPackage = PushFrame.fromBuffer(args);

    var logId = wssPackage.logId;
    final encodedPayload = wssPackage.payload;
    final isGzip =
        wssPackage.payloadEncoding.toLowerCase() == 'gzip' ||
        (encodedPayload.length >= 2 && encodedPayload[0] == 0x1f && encodedPayload[1] == 0x8b);
    var decompressed = isGzip ? gzip.decode(encodedPayload) : encodedPayload;
    var payloadPackage = Response.fromBuffer(decompressed);
    if (payloadPackage.needAck) {
      sendAck(logId, payloadPackage.internalExt);
      //return;
    }
    for (var msg in payloadPackage.messagesList) {
      if (msg.method == 'WebcastChatMessage') {
        unPackWebcastChatMessage(msg.payload, envelopeMessageId: msg.msgId.toString());
      } else if (msg.method == 'WebcastRoomUserSeqMessage') {
        unPackWebcastRoomUserSeqMessage(msg.payload);
      }
    }
  }

  void unPackWebcastChatMessage(List<int> payload, {String envelopeMessageId = ''}) {
    var chatMessage = ChatMessage.fromBuffer(payload);
    final commonRoomId = chatMessage.hasCommon() ? chatMessage.common.roomId.toString() : '';
    if (commonRoomId.isNotEmpty && commonRoomId != '0' && commonRoomId != danmakuArgs.roomId) return;
    final commonMessageId = chatMessage.hasCommon() ? chatMessage.common.msgId.toString() : '';
    final resolvedMessageId = commonMessageId.isNotEmpty && commonMessageId != '0'
        ? commonMessageId
        : (envelopeMessageId == '0' ? '' : envelopeMessageId);
    final rawCreateTime = chatMessage.hasCommon() ? chatMessage.common.createTime.toInt() : 0;
    final sentAt = rawCreateTime <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(rawCreateTime > 100000000000 ? rawCreateTime : rawCreateTime * 1000);
    onMessage?.call(
      LiveMessage(
        type: LiveMessageType.chat,
        color: LiveMessageColor.white,
        //暂不知道具体怎么转换颜色
        // color: chatMessage.common.fullScreenTextColor.
        //     ? LiveMessageColor.white
        //     : LiveMessageColor.numberToColor(color),
        message: chatMessage.content,
        userName: chatMessage.user.nickName,
        userId: chatMessage.user.id.toString(),
        messageId: resolvedMessageId.isEmpty ? '' : 'douyin:$resolvedMessageId',
        sentAt: sentAt,
      ),
    );
  }

  void unPackWebcastRoomUserSeqMessage(List<int> payload) {
    var roomUserSeqMessage = RoomUserSeqMessage.fromBuffer(payload);
    final onlineText = roomUserSeqMessage.onlineUserForAnchor;
    if (!RegExp(r'[0-9]').hasMatch(onlineText)) return;
    final online = LiveRoom.parseAudienceNumber(onlineText);

    onMessage?.call(
      LiveMessage(
        type: LiveMessageType.online,
        // totalUser is cumulative. onlineUserForAnchor is the concurrent
        // audience field shown to the anchor and must be kept separate.
        data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: online),
        color: LiveMessageColor.white,
        message: "",
        userName: "",
      ),
    );
  }

  void sendAck(dynamic logId, String internalExt) {
    var obj = PushFrame();
    obj.payloadType = 'ack';
    obj.logId = logId;
    obj.payload = utf8.encode(internalExt);
    webScoketUtils?.sendMessage(obj.writeToBuffer());
  }

  void joinRoom(dynamic args) {
    var obj = PushFrame();
    obj.payloadType = 'hb';
    webScoketUtils?.sendMessage(obj.writeToBuffer());
  }
}
// 3.x end --------------------------------------------------------------------
