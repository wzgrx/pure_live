// Writes expected.json for the SOOP danmaku samples: 3.x's decoder runs over
// the recorded frames of S07-live and the synthetic frames of S08-synthetic
// (docs/modules/M5.7-soop.md, "与 v3 的对照").
//
// The code in the "3.x" section is SoopDanmaku copied from
// legacy/lib/core/danmaku/soop_danmaku.dart (archive/v4) without `start` and
// `stop` (the socket is tested apart): the packet strings, joinRoom,
// _calculateByteSize, heartbeat, decodeMessageStr, decodeMessage and
// _decodeChatPacket, with ListUtil from legacy/lib/core/common/utils/
// list_util.dart. Only CoreLog is replaced (warnings go to stderr, debug
// output is dropped), `onMessage` is a list, WebScoketUtils is a stub that
// records what `sendMessage` gets, and 3.x's LiveMessage and
// LiveMessageColor are reduced to their fields (from
// legacy/lib/common/models/live_message.dart).
//
// S07-live: every incoming frame of frames.jsonl is decoded in order. The
// client packets 3.x sends are recorded too: joinRoom with the recorded
// CHATNO (meta.json `danmakuKeys.chatNo`) and a few others, and heartbeat.
//
// S08-synthetic: every case of cases.json is one frame, framed as described
// in its note.
//
// Run from the repository root: dart run fixtures/soop/danmaku/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _root = 'fixtures/soop/danmaku';

Future<void> main() async {
  await _recorded();
  _synthetic();
}

Future<void> _recorded() async {
  final meta = jsonDecode(File('$_root/S07-live/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final chatNo = (meta['danmakuKeys'] as Map)['chatNo'] as String;
  final frames = [
    for (final line in File('$_root/S07-live/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final danmaku = SoopDanmaku();
  final messages = <Map<String, Object?>>[];
  for (var index = 0; index < frames.length; index++) {
    final frame = frames[index];
    if (frame['dir'] != 'in') continue;
    danmaku.received.clear();
    danmaku.decodeMessage(base64Decode(frame['b64'] as String));
    for (final message in danmaku.received) {
      messages.add({'frame': index, ..._project(message)});
    }
  }

  Future<List<String>> join(String chatNo) async {
    final sender = SoopDanmaku();
    sender.webScoketUtils = WebScoketUtils();
    await sender.joinRoom(SoopDanmakuArgs(url: '', chatNo: chatNo));
    return [for (final packet in sender.webScoketUtils!.sent) base64Encode(utf8.encode(packet as String))];
  }

  final heartbeat = SoopDanmaku()..webScoketUtils = WebScoketUtils();
  heartbeat.heartbeat();
  _write('$_root/S07-live/expected.json', {
    'generator':
        'fixtures/soop/danmaku/legacy_expected.dart: 3.x SoopDanmaku.decodeMessage over every incoming frame, '
        'joinRoom (the login and join packets it sends, CHATNO from meta.json danmakuKeys.chatNo and others) and '
        'heartbeat',
    'value': {
      'chatNo': chatNo,
      'joinPackets': {
        for (final number in [chatNo, '1', '123456789', '채팅']) number: await join(number),
      },
      'heartbeatPacket': base64Encode(utf8.encode(heartbeat.webScoketUtils!.sent.single as String)),
      'messages': messages,
    },
  });
}

void _synthetic() {
  final doc = jsonDecode(File('$_root/S08-synthetic/cases.json').readAsStringSync()) as Map<String, dynamic>;
  final results = <Map<String, Object?>>[];
  for (final item in doc['cases'] as List) {
    final testCase = item as Map<String, dynamic>;
    final danmaku = SoopDanmaku();
    danmaku.decodeMessage(serverFrame(testCase));
    results.add({
      'name': testCase['name'],
      'messages': [for (final message in danmaku.received) _project(message)],
    });
  }
  _write('$_root/S08-synthetic/expected.json', {
    'generator':
        'fixtures/soop/danmaku/legacy_expected.dart: 3.x SoopDanmaku.decodeMessage over each case of cases.json '
        '(one server frame per case)',
    'value': results,
  });
}

/// One case of cases.json as the server frames it.
List<int> serverFrame(Map<String, dynamic> testCase) {
  List<int> hex(String text) => [
    for (var index = 0; index < text.length; index += 2) int.parse(text.substring(index, index + 2), radix: 16),
  ];
  final bytes = <int>[];
  for (final item in testCase['packets'] as List) {
    final packet = item as Map<String, dynamic>;
    if (packet['hex'] case final String raw) {
      bytes.addAll(hex(raw));
      continue;
    }
    final body = packet['bodyHex'] is String
        ? hex(packet['bodyHex'] as String)
        : utf8.encode((packet['fields'] as List).cast<String>().join('\x0c'));
    bytes
      ..addAll(hex(packet['prefix'] as String? ?? '1b09'))
      ..addAll(ascii.encode(packet['serviceText'] as String? ?? (packet['service'] as int).toString().padLeft(4, '0')))
      ..addAll(ascii.encode(packet['lengthText'] as String? ?? body.length.toString().padLeft(6, '0')))
      ..addAll(ascii.encode(packet['reserved'] as String? ?? '00'))
      ..addAll(body);
  }
  final cut = testCase['cut'] as int? ?? 0;
  return bytes.sublist(0, bytes.length - cut);
}

Map<String, Object?> _project(LiveMessage message) => {
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
  'data': message.data,
};

void _write(String path, Object value) {
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  stdout.writeln('wrote $path');
}

// ---------------------------------------------------------------------------
// Stubs for what 3.x's SoopDanmaku imports.

abstract final class CoreLog {
  static void d(Object? message) {}

  static void w(Object? message) => stderr.writeln('CoreLog.w: $message');

  static void error(Object? message) => stderr.writeln('CoreLog.error: $message');
}

/// Records what 3.x sends; always connected.
class WebScoketUtils {
  final List<dynamic> sent = [];

  void sendMessage(dynamic message) => sent.add(message);
}

abstract interface class LiveDanmaku {}

enum LiveMessageType { chat, gift, online, superChat }

class LiveMessageColor {
  final int r, g, b;
  const LiveMessageColor(this.r, this.g, this.b);
  static LiveMessageColor get white => LiveMessageColor(255, 255, 255);

  @override
  String toString() {
    return "#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}";
  }
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
    required this.message,
    this.data,
    required this.color,
    this.userLevel = '',
    this.fansLevel = '',
    this.fansName = '',
    this.userId = '',
    this.isLocal = false,
    this.messageId = '',
    this.sentAt,
  });
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/common/utils/list_util.dart (splitList).

final class ListUtil {
  /// 切分list
  static List<List<T>> splitList<T>(List<T> list, T value) {
    if (list.isEmpty) {
      return List.empty();
    }
    List<List<T>> rs = [];
    var start = 0;
    var i = 0;
    for (; i < list.length; i++) {
      var cur = list[i];
      if (cur == value) {
        var end = i;
        var subList = list.sublist(start, end);
        rs.add(subList);
        start = i + 1;
      }
    }
    var end = min(i, list.length);
    var subList = list.sublist(start, end);
    rs.add(subList);
    return rs;
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/danmaku/soop_danmaku.dart (SoopDanmakuArgs without
// JSON; SoopDanmaku without start, stop and the connection state).

class SoopDanmakuArgs {
  String url;
  String chatNo;

  SoopDanmakuArgs({required this.url, required this.chatNo});
}

class SoopDanmaku implements LiveDanmaku {
  /// The stub's `onMessage`.
  final List<LiveMessage> received = [];

  Function(LiveMessage msg)? get onMessage => received.add;

  int heartbeatTime = 20 * 1000;

  final String f = "\x0c";
  final String esc = "\x1b\x09";

  WebScoketUtils? webScoketUtils;
  late SoopDanmakuArgs danmakuArgs;

  Future<void> joinRoom(SoopDanmakuArgs joinData) async {
    danmakuArgs = joinData;
    final connectPacket = '${esc}000100000600${f * 3}16$f';
    webScoketUtils?.sendMessage(connectPacket);

    await Future.delayed(const Duration(milliseconds: 200));
    final joinPacket =
        '${esc}0002${_calculateByteSize(danmakuArgs.chatNo).toString().padLeft(6, '0')}00$f${danmakuArgs.chatNo}${f * 5}';
    webScoketUtils?.sendMessage(joinPacket);
  }

  int _calculateByteSize(String string) {
    return utf8.encode(string).length + 6;
  }

  void heartbeat() {
    final pingPacket = '${esc}000000000100$f';
    webScoketUtils?.sendMessage(pingPacket);
  }

  void decodeMessageStr(String data) {
    CoreLog.w("SoopDanmaku decodeMessageStr: $data");
  }

  void decodeMessage(List<int> data) {
    const headerLength = 14;
    var offset = 0;
    while (offset + headerLength <= data.length) {
      if (data[offset] != 0x1b || data[offset + 1] != 0x09) {
        CoreLog.w('SOOP chat packet has an invalid prefix at offset $offset');
        return;
      }
      final service = int.tryParse(ascii.decode(data.sublist(offset + 2, offset + 6), allowInvalid: true));
      final bodyLength = int.tryParse(ascii.decode(data.sublist(offset + 6, offset + 12), allowInvalid: true));
      if (service == null || bodyLength == null || bodyLength < 0) {
        CoreLog.w('SOOP chat packet has an invalid header at offset $offset');
        return;
      }
      final packetEnd = offset + headerLength + bodyLength;
      if (packetEnd > data.length) {
        CoreLog.w('SOOP chat packet is truncated at offset $offset');
        return;
      }
      if (service == 5) {
        _decodeChatPacket(data.sublist(offset + headerLength, packetEnd));
      }
      offset = packetEnd;
    }
    if (offset != data.length) {
      CoreLog.w('SOOP chat payload ended with ${data.length - offset} trailing bytes');
    }
  }

  void _decodeChatPacket(List<int> body) {
    const separatorByte = 0x0c;
    final parts = ListUtil.splitList(body, separatorByte);
    final fields = parts.map((part) => utf8.decode(part, allowMalformed: true)).toList(growable: false);
    CoreLog.d("SOOP chat fields: $fields");

    if (fields.length <= 6) return;
    final comment = fields[1].trim();
    final userName = fields[6].trim();
    if (comment.isEmpty || userName.isEmpty || ['-1', '1'].contains(comment) || comment.contains('|')) return;
    onMessage?.call(
      LiveMessage(type: LiveMessageType.chat, color: LiveMessageColor.white, message: comment, userName: userName),
    );
  }
}
