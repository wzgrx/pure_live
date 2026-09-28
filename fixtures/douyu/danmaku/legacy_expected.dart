// Writes expected.json for the Douyu danmaku samples: 3.x's decoder runs over
// the recorded frames of S13-live and the synthetic frames of S14-synthetic
// (docs/modules/M5.2-douyu.md, "与 v3 的对照").
//
// The code in the "3.x" section is DouyuDanmaku's codec copied from
// legacy/lib/core/danmaku/douyu_danmaku.dart (archive/v4): decodeMessage,
// _parseCommonSuperChat, _parseVoiceSuperChat, _superChatMessage,
// serializeDouyu, deserializeDouyuPackets, sttToJObject, unscapeSlashAt and
// getColor, with the room id and the suspected-automated preference it reads.
// Only CoreLog is replaced (it prints to stderr), `onMessage` is a list, and
// 3.x's LiveMessage, LiveSuperChatMessage and LiveMessageColor are reduced to
// their fields (from legacy/lib/common/models/live_message.dart). 3.x's
// BinaryWriter (legacy/lib/core/common/binary_writer.dart) is copied for
// serializeDouyu, without the parts it does not use.
//
// S13-live: every incoming frame of frames.jsonl is decoded in order with the
// room id of meta.json (`danmakuKeys.rid`), once with the filter off (3.x's
// default) and once with it on. The client frames 3.x sends (join and
// heartbeat) are recorded too.
//
// S14-synthetic: every case of cases.json is one frame, framed as the server
// does (type 690, UTF-8 length); see the note in cases.json.
//
// Run from the repository root: dart run fixtures/douyu/danmaku/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _root = 'fixtures/douyu/danmaku';

void main() {
  _recorded();
  _synthetic();
}

void _recorded() {
  final meta = jsonDecode(File('$_root/S13-live/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final roomId = (meta['danmakuKeys'] as Map)['rid'] as String;
  final frames = [
    for (final line in File('$_root/S13-live/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  List<Map<String, Object?>> run(bool filter) {
    final danmaku = DouyuDanmaku(filterSuspectedAutomatedMessages: () => filter)..debugSetRoomId(roomId);
    final out = <Map<String, Object?>>[];
    for (var index = 0; index < frames.length; index++) {
      final frame = frames[index];
      if (frame['dir'] != 'in') continue;
      danmaku.received.clear();
      danmaku.decodeMessage(base64Decode(frame['b64'] as String));
      for (final message in danmaku.received) {
        out.add({'frame': index, ..._project(message)});
      }
    }
    return out;
  }

  final danmaku = DouyuDanmaku();
  final messages = run(false);
  final filtered = run(true);
  _write('$_root/S13-live/expected.json', {
    'generator':
        'fixtures/douyu/danmaku/legacy_expected.dart: 3.x DouyuDanmaku.decodeMessage over every incoming frame '
        '(room id from meta.json danmakuKeys.rid; suspected-automated filter off, then on) and serializeDouyu for '
        'the join and heartbeat frames',
    'value': {
      'roomId': roomId,
      'joinFrames': [
        base64Encode(danmaku.serializeDouyu('type@=loginreq/roomid@=$roomId/')),
        base64Encode(danmaku.serializeDouyu('type@=joingroup/rid@=$roomId/gid@=-9999/')),
      ],
      'heartbeatFrame': base64Encode(danmaku.serializeDouyu('type@=mrkl/')),
      'messages': messages,
      'keptWithFilter': [for (final message in filtered) message['messageId']],
    },
  });
}

void _synthetic() {
  final doc = jsonDecode(File('$_root/S14-synthetic/cases.json').readAsStringSync()) as Map<String, dynamic>;
  final results = <Map<String, Object?>>[];
  for (final item in doc['cases'] as List) {
    final testCase = item as Map<String, dynamic>;
    final filter = testCase['filter'] == true;
    final danmaku = DouyuDanmaku(filterSuspectedAutomatedMessages: () => filter)
      ..debugSetRoomId(testCase['roomId'] as String);
    danmaku.decodeMessage(serverFrame(testCase));
    results.add({
      'name': testCase['name'],
      'messages': [for (final message in danmaku.received) _project(message)],
    });
  }
  _write('$_root/S14-synthetic/expected.json', {
    'generator':
        'fixtures/douyu/danmaku/legacy_expected.dart: 3.x DouyuDanmaku.decodeMessage over each case of cases.json '
        '(one server frame per case)',
    'value': results,
  });
}

/// One case of cases.json as the server frames it.
List<int> serverFrame(Map<String, dynamic> testCase) {
  final bytes = <int>[];
  for (final packet in testCase['packets'] as List) {
    if (packet is Map) {
      final header = ByteData(12)
        ..setUint32(0, packet['headerLength'] as int, Endian.little)
        ..setUint32(4, packet['headerLength'] as int, Endian.little)
        ..setUint16(8, 690, Endian.little);
      bytes.addAll(header.buffer.asUint8List());
      continue;
    }
    final body = utf8.encode(packet as String);
    final header = ByteData(12)
      ..setUint32(0, 8 + body.length + 1, Endian.little)
      ..setUint32(4, 8 + body.length + 1, Endian.little)
      ..setUint16(8, 690, Endian.little);
    bytes
      ..addAll(header.buffer.asUint8List())
      ..addAll(body)
      ..add(0);
  }
  final cut = testCase['cut'] as int? ?? 0;
  return bytes.sublist(0, bytes.length - cut);
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
    'data': data is LiveSuperChatMessage
        ? {
            'messageId': data.messageId,
            'userName': data.userName,
            'face': data.face,
            'message': data.message,
            'price': data.price,
            'startTime': data.startTime.millisecondsSinceEpoch,
            'endTime': data.endTime.millisecondsSinceEpoch,
            'backgroundColor': data.backgroundColor,
            'backgroundBottomColor': data.backgroundBottomColor,
          }
        : data,
  };
}

void _write(String path, Object value) {
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  stdout.writeln('wrote $path');
}

// ---------------------------------------------------------------------------
// Stubs for what 3.x's DouyuDanmaku imports.

abstract final class CoreLog {
  static void error(Object? message) => stderr.writeln('CoreLog.error: $message');
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

enum LiveMessageType { chat, gift, online, superChat }

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

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/danmaku/douyu_danmaku.dart, the codec of DouyuDanmaku
// (connection code left out; `onMessage` collects into [received]).

class DouyuDanmaku {
  DouyuDanmaku({bool Function()? filterSuspectedAutomatedMessages})
    : _filterSuspectedAutomatedMessages = filterSuspectedAutomatedMessages ?? (() => false);

  final bool Function() _filterSuspectedAutomatedMessages;

  final List<LiveMessage> received = [];
  void Function(LiveMessage msg)? get onMessage => received.add;

  String _roomId = '';

  void debugSetRoomId(String roomId) => _roomId = roomId;

  void decodeMessage(List<int> data) {
    for (final result in deserializeDouyuPackets(data)) {
      try {
        final jsonData = sttToJObject(result);
        if (jsonData is! Map) continue;

        final type = jsonData["type"]?.toString();
        LiveMessage? liveMsg;
        if (type == "chatmsg") {
          final packetRoomId = jsonData['rid']?.toString() ?? '';
          if (packetRoomId.isNotEmpty && _roomId.isNotEmpty && packetRoomId != _roomId) continue;
          final text = jsonData["txt"]?.toString() ?? '';
          if (text.isEmpty) continue;
          final isSuspectedAutomated = jsonData['dms'] == null && jsonData['if']?.toString() != '1';
          if (isSuspectedAutomated && _filterSuspectedAutomatedMessages()) continue;
          final col = int.tryParse(jsonData["col"]?.toString() ?? '') ?? 0;
          final rawTimestamp = int.tryParse(jsonData['cst']?.toString() ?? '');
          final sentAt = rawTimestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(rawTimestamp > 100000000000 ? rawTimestamp : rawTimestamp * 1000);
          final messageId = jsonData['cid']?.toString() ?? '';
          liveMsg = LiveMessage(
            type: LiveMessageType.chat,
            userName: jsonData["nn"]?.toString() ?? '',
            userId: jsonData['uid']?.toString() ?? '',
            message: text,
            color: getColor(col),
            messageId: messageId.isEmpty ? '' : 'douyu:$messageId',
            sentAt: sentAt,
          );
        } else if (type == "comm_chatmsg") {
          liveMsg = _parseCommonSuperChat(jsonData);
        } else if (type == "voice_trlt") {
          liveMsg = _parseVoiceSuperChat(jsonData);
        }
        if (liveMsg != null) onMessage?.call(liveMsg);
      } catch (e) {
        // One malformed packet must not discard the valid packets coalesced
        // after it in the same WebSocket frame.
        CoreLog.error("Douyu packet parse failed: $e");
      }
    }
  }

  LiveMessage? _parseCommonSuperChat(Map jsonData) {
    final chat = jsonData["chatmsg"];
    final now = int.tryParse(jsonData["now"]?.toString() ?? '');
    final duration = int.tryParse(jsonData["cet"]?.toString() ?? '');
    final rawPrice = int.tryParse(jsonData["cprice"]?.toString() ?? '');
    if (chat is! Map || now == null || duration == null || rawPrice == null) return null;
    final face = chat["ic"]?.toString() ?? '';
    final startTime = DateTime.fromMillisecondsSinceEpoch(now);
    final superChat = LiveSuperChatMessage(
      backgroundBottomColor: "#292a60",
      backgroundColor: "#c1c1ff",
      endTime: startTime.add(Duration(seconds: duration)),
      face: face.isEmpty ? '' : "https://apic.douyucdn.cn/upload/${face}_small.jpg",
      message: chat["txt"]?.toString() ?? '',
      price: rawPrice ~/ 100,
      startTime: startTime,
      userName: chat["nn"]?.toString() ?? '',
    );
    return _superChatMessage(superChat);
  }

  LiveMessage? _parseVoiceSuperChat(Map jsonData) {
    final list = jsonData["list"];
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    final scData = list.first as Map;
    final endSeconds = int.tryParse(scData["etime"]?.toString() ?? '');
    final startSeconds = int.tryParse(scData["acptime"]?.toString() ?? '');
    final rawPrice = int.tryParse(scData["realPrice"]?.toString() ?? '');
    if (endSeconds == null || startSeconds == null || rawPrice == null) return null;
    final avatars = scData["uat"];
    final avatar = avatars is List && avatars.length > 1 ? avatars[1].toString() : '';
    final superChat = LiveSuperChatMessage(
      backgroundBottomColor: "#246488",
      backgroundColor: "#ffffff",
      endTime: DateTime.fromMillisecondsSinceEpoch(endSeconds * 1000),
      face: avatar.isEmpty ? '' : "https://$avatar",
      message: scData["content"]?.toString() ?? '',
      price: rawPrice ~/ 100,
      startTime: DateTime.fromMillisecondsSinceEpoch(startSeconds * 1000),
      userName: scData["un"]?.toString() ?? '',
    );
    return _superChatMessage(superChat);
  }

  LiveMessage _superChatMessage(LiveSuperChatMessage data) {
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: "SUPER_CHAT_MESSAGE",
      message: "SUPER_CHAT_MESSAGE",
      color: LiveMessageColor.white,
      data: data,
    );
  }

  List<int> serializeDouyu(String body) {
    try {
      const int clientSendToServer = 689;
      const int encrypted = 0;
      const int reserved = 0;

      List<int> buffer = utf8.encode(body);

      var writer = BinaryWriter([]);
      writer.writeInt(4 + 4 + body.length + 1, 4, endian: Endian.little);
      writer.writeInt(4 + 4 + body.length + 1, 4, endian: Endian.little);
      writer.writeInt(clientSendToServer, 2, endian: Endian.little);
      writer.writeInt(encrypted, 1, endian: Endian.little);
      writer.writeInt(reserved, 1, endian: Endian.little);
      writer.writeBytes(buffer);
      writer.writeInt(0, 1, endian: Endian.little);
      return writer.buffer;
    } catch (e) {
      CoreLog.error(e);
      return [];
    }
  }

  /// One WebSocket frame commonly carries several complete Douyu packets.
  /// Iterate by each packet's own length instead of silently dropping every
  /// packet after the first.
  List<String> deserializeDouyuPackets(List<int> buffer) {
    final packets = <String>[];
    try {
      final bytes = Uint8List.fromList(buffer);
      var offset = 0;
      while (offset + 12 <= bytes.length) {
        final header = ByteData.sublistView(bytes, offset, offset + 4);
        final fullMsgLength = header.getUint32(0, Endian.little);
        final frameLength = fullMsgLength + 4;
        final bodyLength = fullMsgLength - 9;
        if (fullMsgLength < 9 || bodyLength < 0 || offset + frameLength > bytes.length) break;
        final bodyStart = offset + 12;
        final bodyEnd = bodyStart + bodyLength;
        packets.add(utf8.decode(bytes.sublist(bodyStart, bodyEnd), allowMalformed: true));
        offset += frameLength;
      }
    } catch (e) {
      CoreLog.error(e);
    }
    return packets;
  }

  //辣鸡STT
  dynamic sttToJObject(String str) {
    if (str.contains("//")) {
      var result = [];
      for (var field in str.split("//")) {
        if (field.isEmpty) {
          continue;
        }
        result.add(sttToJObject(field));
      }
      return result;
    }
    if (str.contains("@=")) {
      var result = {};
      for (var field in str.split('/')) {
        if (field.isEmpty) {
          continue;
        }
        final separator = field.indexOf("@=");
        if (separator <= 0) continue;
        var k = field.substring(0, separator);
        var v = unscapeSlashAt(field.substring(separator + 2));
        result[k] = sttToJObject(v);
      }
      return result;
    } else if (str.contains("@A=")) {
      return sttToJObject(unscapeSlashAt(str));
    } else {
      return unscapeSlashAt(str);
    }
  }

  String unscapeSlashAt(String str) {
    return str.replaceAll("@S", "/").replaceAll("@A", "@");
  }

  LiveMessageColor getColor(int type) {
    switch (type) {
      case 1:
        return LiveMessageColor(255, 0, 0);
      case 2:
        return LiveMessageColor(30, 135, 240);
      case 3:
        return LiveMessageColor(122, 200, 75);
      case 4:
        return LiveMessageColor(255, 127, 0);
      case 5:
        return LiveMessageColor(155, 57, 244);
      case 6:
        return LiveMessageColor(255, 105, 180);
      default:
        return LiveMessageColor.white;
    }
  }
}
