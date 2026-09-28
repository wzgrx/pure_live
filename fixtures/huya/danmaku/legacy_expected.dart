// Writes expected.json for the Huya danmaku samples: 3.x's decoder runs over
// the recorded frames of S11-live and the synthetic frames of S16-synthetic
// (docs/modules/M5.3-huya.md, "与 v3 的对照").
//
// The "3.x" sections are copied from legacy/lib (archive/v4):
// - HuyaDanmaku's codec from core/danmaku/huya_danmaku.dart: heartbeatData,
//   getJoinData, decodeMessage and _decodePush, and the HYPushMessage,
//   HYPushMessageV2, HYMessageItem, HYSender, HYMessage and HYBulletFormat
//   structures (unchanged);
// - the Tars codec from pkg/tars/codec: tars_struct.dart,
//   tars_input_stream.dart, tars_output_stream.dart,
//   tars_decode_exception.dart, tars_encode_exception.dart and DeepCopyable
//   from tars_deep_copyable.dart (unchanged but for their imports).
// Only logging is replaced (errors print to stderr), `onMessage` is a list, the
// board refresh that uri 2001314 starts is counted instead of run (fetching
// the board is not decoding; the connection tests port 3.x's tests of it),
// and 3.x's LiveMessage, LiveMessageColor (with its numberToColor) and
// LiveAudienceUpdate are reduced to their fields (from
// legacy/lib/common/models/live_message.dart).
//
// S11-live: every incoming WebSocket frame of frames.jsonl is decoded in
// order (the recorded HTTP response of the message board is skipped); the
// client frames 3.x sends once the socket opens (registration, heartbeat) are
// recorded for the streamer uid of meta.json.
//
// S16-synthetic: every case of cases.json is built into one server frame
// with 3.x's TarsOutputStream (see the note in cases.json) and decoded.
//
// Run from the repository root: dart run fixtures/huya/danmaku/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'dart:typed_data';

const _root = 'fixtures/huya/danmaku';

Future<void> main() async {
  await _recorded();
  await _synthetic();
}

Future<void> _recorded() async {
  final meta = jsonDecode(File('$_root/S11-live/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final uid = int.parse((meta['danmakuKeys'] as Map)['uid'] as String);
  final frames = [
    for (final line in File('$_root/S11-live/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final danmaku = HuyaDanmaku();
  final messages = <Map<String, Object?>>[];
  for (var index = 0; index < frames.length; index++) {
    final frame = frames[index];
    // Incoming WebSocket frames only: the recorder also kept one HTTP
    // response of the message board (it has a url).
    if (frame['dir'] != 'in' || frame.containsKey('url')) continue;
    danmaku.received.clear();
    await danmaku.decodeMessage(base64Decode(frame['b64'] as String));
    for (final message in danmaku.received) {
      messages.add({'frame': index, ..._project(message)});
    }
  }
  _write('$_root/S11-live/expected.json', {
    'generator':
        'fixtures/huya/danmaku/legacy_expected.dart: 3.x HuyaDanmaku.decodeMessage over every incoming WebSocket '
        'frame, and getJoinData (uid from meta.json danmakuKeys.uid) and heartbeatData for the frames sent once '
        'the socket opens',
    'value': {
      'uid': uid,
      'registerFrame': base64Encode(danmaku.getJoinData(uid)),
      'heartbeatFrame': base64Encode(danmaku.heartbeatData),
      'messages': messages,
      'superChatNotices': danmaku.superChatNotices,
    },
  });
}

Future<void> _synthetic() async {
  final doc = jsonDecode(File('$_root/S16-synthetic/cases.json').readAsStringSync()) as Map<String, dynamic>;
  final results = <Map<String, Object?>>[];
  for (final item in doc['cases'] as List) {
    final testCase = item as Map<String, dynamic>;
    final frame = serverFrame(testCase['frame'] as Map<String, dynamic>);
    final danmaku = HuyaDanmaku();
    await danmaku.decodeMessage(frame);
    results.add({
      'name': testCase['name'],
      'frame': base64Encode(frame),
      'messages': [for (final message in danmaku.received) _project(message)],
      'superChatNotices': danmaku.superChatNotices,
    });
  }
  _write('$_root/S16-synthetic/expected.json', {
    'generator':
        'fixtures/huya/danmaku/legacy_expected.dart: each case of cases.json built into one server frame with 3.x '
        "TarsOutputStream, then 3.x HuyaDanmaku.decodeMessage over it",
    'value': results,
  });
}

/// One case of cases.json as the server frames it, written with 3.x's
/// TarsOutputStream.
Uint8List serverFrame(Map<String, dynamic> spec) {
  final raw = spec['base64'] as String?;
  if (raw != null) return base64Decode(raw);
  final command = spec['command'] as int;
  var payload = Uint8List(0);
  if (command == 7) {
    payload =
        (TarsOutputStream()
              ..write(5, 0)
              ..write(spec['uri'] as int, 1)
              ..write(_body(spec), 2)
              ..write(2, 3))
            .toUint8List();
  } else if (command == 22) {
    final push = HYPushMessageV2()
      ..groupId = spec['group'] as String
      ..items = [
        for (final item in spec['items'] as List)
          HYMessageItem()
            ..uri = (item as Map)['uri'] as int
            ..msg = _body(item as Map<String, dynamic>)
            ..messageId = item['id'] as int? ?? 0,
      ];
    final out = TarsOutputStream();
    push.writeTo(out);
    payload = out.toUint8List();
  }
  final frame =
      (TarsOutputStream()
            ..write(command, 0)
            ..write(payload, 1))
          .toUint8List();
  final cut = spec['cut'] as int? ?? 0;
  return Uint8List.sublistView(frame, 0, frame.length - cut);
}

/// The body of one push: a chat, a count, raw Base64, or nothing.
Uint8List _body(Map<String, dynamic> spec) {
  final raw = spec['body'] as String?;
  if (raw != null) return base64Decode(raw);
  if (spec.containsKey('count')) return (TarsOutputStream()..write(spec['count'] as int, 0)).toUint8List();
  final chat = spec['chat'] as Map<String, dynamic>?;
  if (chat == null) return Uint8List(0);
  final out = TarsOutputStream();
  if (chat.containsKey('uid') || chat.containsKey('nick')) {
    out.write(
      _Fields((stream) {
        stream
          ..write(chat['uid'] as int? ?? 0, 0)
          ..write(0, 1)
          ..write(chat['nick'] as String? ?? '', 2)
          ..write(0, 3);
      }),
      0,
    );
  }
  out
    ..write(chat['tid'] as int? ?? 0, 1)
    ..write(chat['tid'] as int? ?? 0, 2);
  if (chat.containsKey('content')) out.write(chat['content'] as String, 3);
  if (chat.containsKey('color')) {
    out.write(
      _Fields((stream) {
        stream
          ..write(chat['color'] as int, 0)
          ..write(4, 1)
          ..write(0, 2)
          ..write(1, 3);
      }),
      6,
    );
  }
  final body = out.toUint8List();
  final cut = spec['cutBody'] as int? ?? 0;
  return Uint8List.sublistView(body, 0, body.length - cut);
}

/// A structure written by a callback (frame building only).
class _Fields extends TarsStruct {
  _Fields(this.fields);

  final void Function(TarsOutputStream stream) fields;

  @override
  void writeTo(TarsOutputStream outputStream) => fields(outputStream);

  @override
  void readFrom(TarsInputStream inputStream) {}

  @override
  Object deepCopy() => this;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

Map<String, Object?> _project(LiveMessage message) {
  final data = message.data;
  return {
    'type': message.type.name,
    'userName': message.userName,
    'userId': message.userId,
    'message': message.message,
    'color': message.color.toString(),
    'messageId': message.messageId,
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userLevel': message.userLevel,
    'fansLevel': message.fansLevel,
    'fansName': message.fansName,
    'isLocal': message.isLocal,
    'data': data is LiveAudienceUpdate ? {'kind': data.kind.name, 'value': data.value} : data,
  };
}

void _write(String path, Object value) {
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  stdout.writeln('wrote $path');
}

// ---------------------------------------------------------------------------
// Stubs for what 3.x's HuyaDanmaku and Tars codec import.

abstract final class CoreLog {
  static void error(Object? message) => stderr.writeln('CoreLog.error: $message');
}

/// 3.x's debug log. The Tars reader logs every field it looks for past the
/// end of a structure, so it stays quiet here.
abstract final class Log {
  static void d(String message) {}
}

enum LiveMessageType { chat, gift, online, superChat }

enum LiveAudienceMetricKind { popularity, onlineViewers, totalViewers }

class LiveAudienceUpdate {
  final LiveAudienceMetricKind kind;
  final int value;

  const LiveAudienceUpdate({required this.kind, required this.value});
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

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/danmaku/huya_danmaku.dart, the codec of HuyaDanmaku
// (connection and board code left out; `onMessage` collects into [received],
// and a board refresh is counted in [superChatNotices]).

class HuyaDanmaku {
  final List<LiveMessage> received = [];
  void Function(LiveMessage msg)? get onMessage => received.add;

  int superChatNotices = 0;
  int _generation = 0;

  void _scheduleSuperChatRefresh(int generation) => superChatNotices++;

  /// Current website heartbeat: `EWSCmdC2S_HeartBeatReq` (20).
  List<int> get heartbeatData {
    final command = TarsOutputStream();
    command.write(20, 0);
    command.write(Uint8List(0), 1);
    return command.toUint8List();
  }

  List<int> getJoinData(int uid) {
    try {
      final group = TarsOutputStream();
      group.write(<String>['live:$uid', 'chat:$uid'], 0);
      group.write('', 1);

      final command = TarsOutputStream();
      command.write(16, 0); // EWSCmdC2S_RegisterGroupReq
      command.write(group.toUint8List(), 1);
      return command.toUint8List();
    } catch (e) {
      CoreLog.error(e);
      return [];
    }
  }

  Future<void> decodeMessage(List<int> data) async {
    try {
      var stream = TarsInputStream(Uint8List.fromList(data));
      var type = stream.read(0, 0, false);
      if (type == 7) {
        stream = TarsInputStream(stream.readBytes(1, false));
        HYPushMessage wSPushMessage = HYPushMessage();
        wSPushMessage.readFrom(stream);
        await _decodePush(wSPushMessage.uri, wSPushMessage.msg);
      } else if (type == 22) {
        final push = HYPushMessageV2();
        push.readFrom(TarsInputStream(stream.readBytes(1, false)));
        for (final item in push.items) {
          await _decodePush(item.uri, item.msg, messageId: item.messageId);
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  Future<void> _decodePush(int uri, List<int> payload, {int messageId = 0}) async {
    if (uri == 1400) {
      final messageNotice = HYMessage();
      messageNotice.readFrom(TarsInputStream(Uint8List.fromList(payload)));
      final color = messageNotice.bulletFormat.fontColor;
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.chat,
          color: color <= 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(color),
          message: messageNotice.content,
          userName: messageNotice.userInfo.nickName,
          userId: messageNotice.userInfo.uid.toString(),
          messageId: messageId > 0 ? 'huya:$messageId' : '',
        ),
      );
    } else if (uri == 8006) {
      final attendeeCount = TarsInputStream(Uint8List.fromList(payload)).read(0, 0, false);
      onMessage?.call(
        LiveMessage(
          type: LiveMessageType.online,
          // Current website captures keep iAttendeeCount in the same
          // multi-million popularity range as the list value.
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.popularity, value: attendeeCount),
          color: LiveMessageColor.white,
          message: '',
          userName: '',
          messageId: messageId > 0 ? 'huya:$messageId' : '',
        ),
      );
    } else if (uri == 2001314) {
      // The notification can arrive before the message-board WUP result is
      // updated. Fetching once here loses that SC until a manual room refresh;
      // awaiting the HTTP call also serializes unrelated websocket messages.
      // Reconcile in the background with a small bounded retry window instead.
      _scheduleSuperChatRefresh(_generation);
    }
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/danmaku/huya_danmaku.dart: the push and message structures

class HYPushMessage extends TarsStruct {
  int pushType = 0;
  int uri = 0;
  List<int> msg = <int>[];
  int protocolType = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    pushType = inputStream.read(pushType, 0, false);
    uri = inputStream.read(uri, 1, false);
    msg = inputStream.readBytes(2, false);
    protocolType = inputStream.read(protocolType, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYPushMessage()
      ..pushType = pushType
      ..uri = uri
      ..msg = List<int>.from(msg)
      ..protocolType = protocolType;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYPushMessageV2 extends TarsStruct {
  String groupId = '';
  List<HYMessageItem> items = <HYMessageItem>[];

  @override
  void readFrom(TarsInputStream inputStream) {
    groupId = inputStream.read(groupId, 0, false);
    items = inputStream.readList<HYMessageItem>(<HYMessageItem>[HYMessageItem()], 1, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(groupId, 0);
    outputStream.write(items, 1);
  }

  @override
  Object deepCopy() => HYPushMessageV2()
    ..groupId = groupId
    ..items = items.map((item) => item.deepCopy() as HYMessageItem).toList();

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYMessageItem extends TarsStruct {
  int uri = 0;
  List<int> msg = <int>[];
  int messageId = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    uri = inputStream.read(uri, 0, false);
    msg = inputStream.readBytes(1, false);
    messageId = inputStream.read(messageId, 2, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {
    outputStream.write(uri, 0);
    outputStream.write(Uint8List.fromList(msg), 1);
    outputStream.write(messageId, 2);
  }

  @override
  Object deepCopy() => HYMessageItem()
    ..uri = uri
    ..msg = List<int>.from(msg)
    ..messageId = messageId;

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYSender extends TarsStruct {
  int uid = 0;
  int lMid = 0;
  String nickName = "";
  int gender = 0;

  @override
  void readFrom(TarsInputStream inputStream) {
    uid = inputStream.read(uid, 0, false);
    lMid = inputStream.read(lMid, 0, false);
    nickName = inputStream.read(nickName, 2, false);
    gender = inputStream.read(gender, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYSender()
      ..uid = uid
      ..lMid = lMid
      ..nickName = nickName
      ..gender = gender;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYMessage extends TarsStruct {
  HYSender userInfo = HYSender();
  String content = "";
  HYBulletFormat bulletFormat = HYBulletFormat();

  @override
  void readFrom(TarsInputStream inputStream) {
    userInfo = inputStream.readTarsStruct(userInfo, 0, false) as HYSender;
    content = inputStream.read(content, 3, false);
    bulletFormat = inputStream.readTarsStruct(bulletFormat, 6, false) as HYBulletFormat;
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYMessage()
      ..userInfo = userInfo.deepCopy() as HYSender
      ..content = content
      ..bulletFormat = bulletFormat.deepCopy() as HYBulletFormat;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

class HYBulletFormat extends TarsStruct {
  int fontColor = 0;
  int fontSize = 4;
  int textSpeed = 0;
  int transitionType = 1;

  @override
  void readFrom(TarsInputStream inputStream) {
    fontColor = inputStream.read(fontColor, 0, false);
    fontSize = inputStream.read(fontSize, 1, false);
    textSpeed = inputStream.read(textSpeed, 2, false);
    transitionType = inputStream.read(transitionType, 3, false);
  }

  @override
  void writeTo(TarsOutputStream outputStream) {}

  @override
  Object deepCopy() {
    return HYBulletFormat()
      ..fontColor = fontColor
      ..fontSize = fontSize
      ..textSpeed = textSpeed
      ..transitionType = transitionType;
  }

  @override
  void displayAsString(StringBuffer sb, int level) {}
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/pkg/tars/codec/tars_struct.dart

// ignore_for_file: non_constant_identifier_names, constant_identifier_names, no_leading_underscores_for_local_identifiers

enum TarsStructType {
  BYTE,
  SHORT,
  INT,
  LONG,
  FLOAT,
  DOUBLE,
  STRING1,
  STRING4,
  MAP,
  LIST,
  STRUCT_BEGIN,
  STRUCT_END,
  ZERO_TAG,
  SIMPLE_LIST,
}

abstract class TarsStruct extends DeepCopyable {
  static int TARS_MAX_STRING_LENGTH = 100 * 1024 * 1024;
  void writeTo(TarsOutputStream outputStream);
  void readFrom(TarsInputStream inputStream);
  void displayAsString(StringBuffer sb, int level);

  Uint8List toByteArray() {
    TarsOutputStream os = TarsOutputStream();
    writeTo(os);
    return os.toUint8List();
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/pkg/tars/codec/tars_deep_copyable.dart

abstract class DeepCopyable {
  Object deepCopy();
}

List<T> listDeepCopy<T>(List list) {
  List<T> newList = List<T>.filled(0, list[0], growable: true);
  for (var value in list) {
    newList.add(
      value is Map
          ? mapDeepCopy(value)
          : value is List
          ? listDeepCopy(value)
          : value is Set
          ? setDeepCopy(value)
          : value is DeepCopyable
          ? value.deepCopy() as T
          : value,
    );
  }
  return newList;
}

Set<T> setDeepCopy<T>(Set s) {
  Set<T> newSet = <T>{};
  for (var value in s) {
    newSet.add(
      value is Map
          ? mapDeepCopy(value)
          : value is List
          ? listDeepCopy(value)
          : value is Set
          ? setDeepCopy(value)
          : value is DeepCopyable
          ? value.deepCopy() as T
          : value,
    );
  }
  return newSet;
}

Map<K, V> mapDeepCopy<K, V>(Map<K, V> map) {
  Map<K, V> newMap = <K, V>{};

  map.forEach((key, value) {
    newMap[key] =
        (value is Map
                ? mapDeepCopy(value)
                : value is List
                ? listDeepCopy(value)
                : value is Set
                ? setDeepCopy(value)
                : value is DeepCopyable
                ? value.deepCopy() as V
                : value)
            as V;
  });

  return newMap;
}

Map<K, List<V>> mapListDeepCopy<K, V>(Map<K, List<V>> map) {
  Map<K, List<V>> newMap = <K, List<V>>{};
  map.forEach((key, value) {
    newMap[key] = listDeepCopy<V>(value);
  });
  return newMap;
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/pkg/tars/codec/tars_decode_exception.dart

class TarsDecodeException extends Error {
  String message;
  TarsDecodeException(this.message);
  @override
  String toString() {
    return message;
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/pkg/tars/codec/tars_encode_exception.dart

class TarsEncodeException extends Error {
  String message;
  TarsEncodeException(this.message);

  @override
  String toString() {
    return message;
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/pkg/tars/codec/tars_input_stream.dart

class HeadData {
  int type = 0;
  int tag = 0;

  void clear() {
    type = 0;
    tag = 0;
  }
}

class BinaryReader {
  Uint8List buffer;
  int position = 0;

  BinaryReader(this.buffer);

  int get length => buffer.length;

  /// 从当前流中读取下一个字节，并使流的当前位置提升 1 个字节
  /// 返回下一个字节(0-255)
  int read() {
    var byte = buffer[position];
    position += 1;
    return byte;
  }

  /// 从当前流中读取指定长度的字节整数，并使流的当前位置提升指定长度。
  /// [len] 指定长度
  /// len=1为int8,2为int16,4为int32,8为int64。dart中统一为int类型
  /// 返回整数
  int readInt(int len) {
    var result = 0;
    // if (len == 1) {
    //   result = buffer[position];
    //   position += len;
    //   return result;
    // }
    var bytes = Uint8List.fromList(buffer.getRange(position, position + len).toList());
    var byteBuffer = bytes.buffer;
    var data = ByteData.view(byteBuffer);
    if (len == 1) {
      result = data.getUint8(0);
    }
    if (len == 2) {
      result = data.getInt16(0, Endian.big);
    }
    if (len == 4) {
      result = data.getInt32(0, Endian.big);
    }
    if (len == 8) {
      result = data.getInt64(0, Endian.big);
    }
    position += len;
    return result;
  }

  /// 从当前流中读取指定长度的字节数组，并使流的当前位置提升指定长度。
  /// [len] 指定长度
  /// 返回字节数组
  Uint8List readBytes(int len) {
    var bytes = Uint8List.fromList(buffer.getRange(position, position + len).toList());
    position += len;
    return bytes;
  }

  /// 从当前流中读取指定长度的字节浮点数，并使流的当前位置提升指定长度。
  /// [len] 指定长度
  /// len=4为float,8为double。dart中统一为double类型
  /// 返回浮点数
  double readFloat(int len) {
    var result = 0.0;
    var bytes = Uint8List.fromList(buffer.getRange(position, position + len).toList());
    var byteBuffer = bytes.buffer;
    var data = ByteData.view(byteBuffer);
    if (len == 4) {
      result = data.getFloat32(0, Endian.big);
    }
    if (len == 8) {
      result = data.getFloat64(0, Endian.big);
    }
    position += len;
    return result;
  }
}

class TarsInputStream {
  late BinaryReader br;

  TarsInputStream(Uint8List? bytes, {int pos = 0}) {
    if (bytes != null) {
      br = BinaryReader(bytes);
      br.position = pos;
    }
  }

  void wrap(Uint8List bytes, {int pos = 0}) {
    br = BinaryReader(bytes);
    br.position = pos;
  }

  static int readBinaryReaderHead(HeadData hd, BinaryReader bb) {
    if (bb.position >= bb.length) {
      throw TarsDecodeException('read file to end');
    }
    var b = bb.read();
    hd.type = (b & 15);
    hd.tag = ((b & (15 << 4)) >> 4);
    if (hd.tag == 15) {
      hd.tag = bb.read();
      return 2;
    }
    return 1;
  }

  int readHead(HeadData hd) {
    return readBinaryReaderHead(hd, br);
  }

  int peakHead(HeadData hd) {
    var curPos = br.position;
    var len = readHead(hd);
    br.position = curPos;
    return len;
  }

  void skip(int len) {
    br.position += len;
  }

  bool skipToTag(int tag) {
    try {
      var hd = HeadData();
      while (true) {
        var len = peakHead(hd);
        if (tag <= hd.tag || hd.type == TarsStructType.STRUCT_END.index) {
          return tag == hd.tag;
        }

        skip(len);
        skipFieldWithType(hd.type);
      }
    } catch (e) {
      if (e is TarsDecodeException) {
        Log.d('skipToTag error: $e');
      }
      Log.d(e.toString());
    }
    return false;
  }

  // 跳到当前结构的结束位置
  void skipToStructEnd() {
    var hd = HeadData();
    do {
      readHead(hd);
      skipFieldWithType(hd.type);
    } while (hd.type != TarsStructType.STRUCT_END.index);
  }

  // 跳过一个字段
  void skipField() {
    var hd = HeadData();
    readHead(hd);
    skipFieldWithType(hd.type);
  }

  void skipFieldWithType(int type) {
    var t = TarsStructType.values[type];
    switch (t) {
      case TarsStructType.BYTE:
        skip(1);
        break;
      case TarsStructType.SHORT:
        skip(2);
        break;
      case TarsStructType.INT:
        skip(4);
        break;
      case TarsStructType.LONG:
        skip(8);
        break;
      case TarsStructType.FLOAT:
        skip(4);
        break;
      case TarsStructType.DOUBLE:
        skip(8);
        break;
      case TarsStructType.STRING1:
        {
          var len = br.read();
          if (len < 0) {
            len += 256;
          }
          skip(len);
          break;
        }
      case TarsStructType.STRING4:
        {
          skip(br.readInt(4));
          break;
        }
      case TarsStructType.MAP:
        {
          var size = readInt(0, true);
          for (var i = 0; i < size * 2; ++i) {
            skipField();
          }
          break;
        }
      case TarsStructType.LIST:
        {
          var size = readInt(0, true);
          for (var i = 0; i < size; ++i) {
            skipField();
          }
          break;
        }
      case TarsStructType.SIMPLE_LIST:
        {
          var hd = HeadData();
          readHead(hd);
          if (hd.type != TarsStructType.BYTE.index) {
            throw TarsDecodeException('skipField with invalid type, type value: $type,${hd.type}');
          }
          var size = readInt(0, true);
          skip(size);
          break;
        }
      case TarsStructType.STRUCT_BEGIN:
        skipToStructEnd();
        break;
      case TarsStructType.STRUCT_END:
      case TarsStructType.ZERO_TAG:
        break;
    }
  }

  dynamic read<T>(dynamic data, int tag, bool isRequire) {
    if (data is int || data == int) {
      data = readInt(tag, isRequire);
    } else if (data is double || data == double) {
      data = readFloat(tag, isRequire);
    } else if (data is bool || data == bool) {
      data = readBool(tag, isRequire);
    } else if (data is Uint8List || data == Uint8List) {
      data = readBytes(tag, isRequire);
    } else if (data is String || data == String) {
      data = readString(tag, isRequire);
    } else if (data is List || data == List) {
      data = readList<T>(data, tag, isRequire);
    } else if (data is Map || data == Map) {
      data = readMap(data, tag, isRequire);
    } else if (data is TarsStruct || data == TarsStruct) {
      data = readTarsStruct(data, tag, isRequire);
    } else {
      throw TarsDecodeException('type:${data.runtimeType} not supported.');
    }
    return data;
  }

  /// 读取整数
  /// 对应Tars类型：int1、int2、int4、int8
  int readInt(int tag, bool isRequire) {
    var n = 0;
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      switch (t) {
        case TarsStructType.ZERO_TAG:
          n = 0;
          break;
        case TarsStructType.BYTE:
          n = br.readInt(1);
          break;
        case TarsStructType.SHORT:
          n = br.readInt(2);
          break;
        case TarsStructType.INT:
          n = br.readInt(4);
          break;
        case TarsStructType.LONG:
          n = br.readInt(8);
          break;
        default:
          throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return n;
  }

  /// 读取bool
  /// 对应Tars类型：int1
  bool readBool(int tag, bool isRequire) {
    return readInt(tag, isRequire) != 0;
  }

  /// 读取单字char
  /// 对应Tars类型：int
  String readChar(int tag, bool isRequire) {
    var char = readInt(tag, isRequire);
    return String.fromCharCode(char);
  }

  /// 读取字符串
  /// 对应Tars类型：string1、string4
  String readString(int tag, bool isRequire) {
    var n = '';
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      switch (t) {
        case TarsStructType.STRING1:
          n = _readString1();
          break;
        case TarsStructType.STRING4:
          n = _readString4();
          break;

        default:
          throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return n;
  }

  String _readString1() {
    var len = 0;
    len = br.readInt(1);
    if (len < 0) {
      len += 256;
    }

    var ss = br.readBytes(len);

    return utf8.decode(ss);
  }

  String _readString4() {
    var len = 0;
    len = br.readInt(4);
    if (len > TarsStruct.TARS_MAX_STRING_LENGTH || len < 0) {
      throw TarsDecodeException('string too long: $len');
    }

    var ss = br.readBytes(len);

    return utf8.decode(ss);
  }

  /// 读取浮点数
  /// 对应Tars类型：double、float
  double readFloat(int tag, bool isRequire) {
    var n = 0.0;
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      switch (t) {
        case TarsStructType.ZERO_TAG:
          n = 0;
          break;
        case TarsStructType.FLOAT:
          {
            n = br.readFloat(4);
          }
          break;
        case TarsStructType.DOUBLE:
          {
            n = br.readFloat(8);
          }
          break;
        default:
          throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return n;
  }

  /// 读取byte[]
  /// 对应Tars类型：SimpleList
  Uint8List readBytes(int tag, bool isRequire) {
    var lr = Uint8List(0);
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      switch (t) {
        case TarsStructType.SIMPLE_LIST:
          {
            var hh = HeadData();
            readHead(hh);
            if (hh.type != TarsStructType.BYTE.index) {
              throw TarsDecodeException('type mismatch, tag: $tag,type:${hd.type},${hh.type}');
            }
            var size = readInt(0, true);
            if (size < 0) {
              throw TarsDecodeException('invalid size, tag: $tag, type: ${hd.type}, ${hh.type}  size:$size');
            }

            lr = Uint8List(size);
            try {
              lr = br.readBytes(size);
            } catch (e) {
              Log.d(e.toString());
              return Uint8List(0);
            }
          }
          break;
        case TarsStructType.LIST:
          {
            var size = readInt(0, true);
            if (size < 0) throw TarsDecodeException('size invalid: $size');
            lr = Uint8List(size);
            for (var i = 0; i < size; ++i) {
              lr[i] = readInt(0, true);
            }
          }
          break;
        default:
          throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return lr;
  }

  /// 读取Map
  /// 需要指定键、值的类型
  /// 对应Tars类型：Map
  Map<K, V> readMap<K, V>(Map<K, V> data, int tag, bool isRequire) {
    Iterable<MapEntry<K, V>> it = data.entries;
    MapEntry<K, V> en = it.first;
    K k = en.key;
    V v = en.value;
    Map<K, V> map = <K, V>{};

    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      if (t == TarsStructType.MAP) {
        var size = readInt(0, true);
        if (size < 0) {
          throw TarsDecodeException('size invalid:$size');
        }
        for (var i = 0; i < size; ++i) {
          var mk = read(k, 0, true);
          var mv = read(v, 1, true);
          if (mk != null) {
            if (map.containsKey(mk)) {
              map[mk] = mv;
            } else {
              map.addAll({mk: mv});
            }
          }
        }
      } else {
        throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return map;
  }

  Map<K, List<V>> readMapList<K, V>(Map<K, List<V>> source, int tag, bool isRequire) {
    var map = <K, List<V>>{};
    Iterable<MapEntry<K, List<V>>> it = source.entries;
    MapEntry<K, List<V>> en = it.first;
    K k = en.key;
    List<V> v = en.value;
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      if (t == TarsStructType.MAP) {
        var size = readInt(0, true);
        if (size < 0) {
          throw TarsDecodeException('size invalid:$size');
        }
        for (var i = 0; i < size; ++i) {
          var mk = read<K>(k, 0, true);
          var mv = read<V>(v, 1, true);
          if (mk != null) {
            if (map.containsKey(mk)) {
              map[mk] = mv;
            } else {
              map.addAll({mk: mv});
            }
          }
        }
      } else {
        throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return map;
  }

  Map<K, Map<K2, V2>> readMapMap<K, K2, V2>(Map<K, Map<K2, V2>> source, int tag, bool isRequire) {
    var map = <K, Map<K2, V2>>{};
    Iterable<MapEntry<K, Map<K2, V2>>> it = source.entries;
    MapEntry<K, Map<K2, V2>> en = it.first;
    K k = en.key;
    Map<K2, V2> v = en.value;
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      if (t == TarsStructType.MAP) {
        var size = readInt(0, true);
        if (size < 0) {
          throw TarsDecodeException('size invalid:$size');
        }
        for (var i = 0; i < size; ++i) {
          var mk = read<K>(k, 0, true);
          var mv = readMap<K2, V2>(v, 1, true);
          if (mk != null) {
            if (map.containsKey(mk)) {
              map[mk] = mv;
            } else {
              map.addAll({mk: mv});
            }
          }
        }
      } else {
        throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return map;
  }

  /// 读取列表
  /// 对应Tars类型：List
  List<T> readList<T>(dynamic data, int tag, bool isRequire) {
    var ls = <T>[];
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      switch (t) {
        case TarsStructType.LIST:
          {
            var size = readInt(0, true);
            if (size < 0) throw TarsDecodeException('size invalid: $size');
            ls = <T>[];
            for (var i = 0; i < size; ++i) {
              ls.add(read(data[0], 0, true));
            }
          }
          break;
        default:
          throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return ls;
  }

  /// 读取自定义结构
  /// 对应Tars类型：TarsStruct
  TarsStruct readTarsStruct(TarsStruct ts, int tag, bool isRequire) {
    if (skipToTag(tag)) {
      var hd = HeadData();
      readHead(hd);
      var t = TarsStructType.values[hd.type];
      if (t == TarsStructType.STRUCT_BEGIN) {
        var copyTs = ts.deepCopy() as TarsStruct;
        copyTs.readFrom(this);
        skipToStructEnd();
        return copyTs;
      } else {
        throw TarsDecodeException('type mismatch.');
      }
    } else if (isRequire) {
      throw TarsDecodeException('require field not exist.');
    }
    return ts;
  }

  String sServerEncoding = "UTF-8";

  int setServerEncoding(String se) {
    sServerEncoding = se;
    return 0;
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/pkg/tars/codec/tars_output_stream.dart

class BinaryWriter {
  List<int> buffer;
  int position = 0;

  BinaryWriter(this.buffer);

  int get length => buffer.length;

  void writeBytes(Uint8List list) {
    buffer.addAll(list);
    position += list.length;
  }

  void writeInt(int value, int len) {
    var b = Uint8List(len).buffer;
    var bytes = ByteData.view(b);
    if (len == 1) {
      //写入byte
      bytes.setUint8(0, value.toUnsigned(8));
    }
    if (len == 2) {
      bytes.setInt16(0, value, Endian.big);
    }
    if (len == 4) {
      bytes.setInt32(0, value, Endian.big);
    }
    if (len == 8) {
      bytes.setInt64(0, value, Endian.big);
    }

    buffer.addAll(bytes.buffer.asUint8List());
    position += len;
  }

  void writeDouble(double value, int len) {
    var b = Uint8List(len).buffer;
    var bytes = ByteData.view(b);

    if (len == 4) {
      bytes.setFloat32(0, value, Endian.big);
    }
    if (len == 8) {
      bytes.setFloat64(0, value, Endian.big);
    }

    buffer.addAll(bytes.buffer.asUint8List());
    position += len;
  }
}

class TarsOutputStream {
  late BinaryWriter bw;

  TarsOutputStream({Uint8List? ls}) {
    if (ls != null) {
      bw = BinaryWriter(ls);
    } else {
      bw = BinaryWriter([]);
    }
  }

  void writeHead(int type, int tag) {
    if (tag < 15) {
      var b = ((tag << 4) | type);
      try {
        bw.writeInt(b, 1);
      } catch (e) {
        Log.d(e.toString());
      }
    } else if (tag < 256) {
      try {
        var b = ((15 << 4) | type);
        {
          bw.writeInt(b, 1);
          bw.writeInt(tag, 1);
        }
      } catch (e) {
        Log.d('${toString()} writeHead: $e');
      }
    } else {
      throw TarsEncodeException('tag is too large: $tag');
    }
  }

  void write(dynamic data, int tag) {
    if (data is int || data == int) {
      writeInt(data, tag);
    } else if (data is double || data == double) {
      writeDouble(data, tag);
    } else if (data is bool || data == bool) {
      writeBool(data, tag);
    } else if (data is Uint8List || data == Uint8List) {
      writeUint8List(data, tag);
    } else if (data is String || data == String) {
      writeString(data, tag);
    } else if (data is List || data == List) {
      writeList(data, tag);
    } else if (data is Map || data == Map) {
      writeMap(data, tag);
    } else if (data is TarsStruct || data == TarsStruct) {
      writeTarsStruct(data, tag);
    } else {
      throw TarsEncodeException('type:${data.runtimeType} not supported.');
    }
  }

  /// 写入bool
  /// 对应Tars类型：int1
  void writeBool(bool b, int tag) {
    writeByte(b ? 1 : 0, tag);
  }

  /// 写入字节
  /// 对应Tars类型：int1
  void writeByte(int b, int tag) {
    //紧跟1个字节整型数据
    if (b == 0) {
      writeHead(TarsStructType.ZERO_TAG.index, tag);
    } else {
      writeHead(TarsStructType.BYTE.index, tag);
      try {
        bw.writeInt(b, 1);
      } catch (e) {
        Log.d(e.toString());
      }
    }
  }

  /// 写入整数型
  /// 对应Tars类型：int1、int2、int4、int8
  void writeInt(int n, int tag) {
    //写入byte
    //紧跟1个字节整型数据
    if (n >= -128 && n <= 127) {
      writeByte(n, tag);
      return;
    }
    //int16
    //紧跟2个字节整型数据
    if (n >= -32768 && n <= 32767) {
      writeHead(TarsStructType.SHORT.index, tag);
      bw.writeInt(n, 2);
      return;
    }
    //int32
    //紧跟4个字节整型数据
    if (n >= -2147483648 && n <= 2147483647) {
      writeHead(TarsStructType.INT.index, tag);
      bw.writeInt(n, 4);
      return;
    }
    //int64
    //紧跟8个字节整型数据
    if (n >= -9223372036854775808 && n <= 9223372036854775807) {
      writeHead(TarsStructType.LONG.index, tag);
      bw.writeInt(n, 8);
      return;
    }
  }

  /// 写入浮点数
  /// 对应Tars类型：float
  void writeFloat(double n, int tag) {
    //紧跟4个字节浮点型数据
    writeHead(TarsStructType.FLOAT.index, tag);
    bw.writeDouble(n, 4);
  }

  /// 写入双精度浮点数(Double)
  /// 对应Tars类型：double
  void writeDouble(double n, int tag) {
    //紧跟8个字节浮点型数据
    writeHead(TarsStructType.DOUBLE.index, tag);
    bw.writeDouble(n, 8);
  }

  /// 写入字符串
  /// 对应Tars类型：string1、string4
  void writeString(String s, int tag) {
    //string1:紧跟1个字节长度，再跟内容
    //string4:紧跟4个字节长度，再跟内容
    var bytes = utf8.encode(s);
    if (bytes.isEmpty) {
      writeHead(TarsStructType.STRING1.index, tag);
      bw.writeInt(0, 1);
      return;
    }
    if (bytes.length > 255) {
      writeHead(TarsStructType.STRING4.index, tag);
      bw.writeInt(bytes.length, 4);
      bw.writeBytes(Uint8List.fromList(bytes));
    } else {
      writeHead(TarsStructType.STRING1.index, tag);
      bw.writeInt(bytes.length, 1);
      bw.writeBytes(Uint8List.fromList(bytes));
    }
  }

  /// 写入byte[]
  /// 对应Tars类型：SimpleList
  void writeUint8List(Uint8List ls, int tag) {
    //简单列表（目前用在byte数组），紧跟一个类型字段（目前只支持byte），紧跟一个整型数据表示长度，再跟byte数据
    writeHead(TarsStructType.SIMPLE_LIST.index, tag);
    writeHead(TarsStructType.BYTE.index, 0);
    writeInt(ls.length, 0);
    bw.writeBytes(ls);
  }

  /// 写入Map
  /// 对应Tars类型：Map
  void writeMap<K, V>(Map<K, V> map, int tag) {
    //紧跟一个整型数据表示Map的大小，再跟[key, value]对列表
    writeHead(TarsStructType.MAP.index, tag);
    writeInt(map.length, 0);
    for (var item in map.keys) {
      write(item, 0);
      write(map[item], 1);
    }
  }

  /// 写入列表
  /// 对应Tars类型：List
  void writeList(List ls, int tag) {
    //紧跟一个整型数据表示List的大小，再跟元素列表
    writeHead(TarsStructType.LIST.index, tag);
    write(ls.length, 0);
    for (var item in ls) {
      write(item, 0);
    }
  }

  /// 写入自定义结构
  /// 对应Tars类型：TarsStruct
  void writeTarsStruct(TarsStruct o, int tag) {
    writeHead(TarsStructType.STRUCT_BEGIN.index, tag);
    o.writeTo(this);
    writeHead(TarsStructType.STRUCT_END.index, 0);
  }

  Uint8List toUint8List() {
    return Uint8List.fromList(bw.buffer);
  }

  String sServerEncoding = "UTF-8";

  int setServerEncoding(String se) {
    sServerEncoding = se;
    return 0;
  }
}
