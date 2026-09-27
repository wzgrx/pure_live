import 'dart:convert';
import 'dart:typed_data';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';

/// One packet of SOOP's chat protocol (spec/sites/soop.md §7.2).
final class SoopPacket {
  /// Creates a packet.
  const new(this.service, this.fields);

  /// Service number (1 login, 2 join, 5 chat, …).
  final int service;

  /// Body fields: the body split at form feeds (the first is usually empty).
  final List<String> fields;
}

/// SOOP's chat protocol (spec/sites/soop.md §7), without I/O.
abstract final class SoopProtocol {
  static const _escape = [0x1b, 0x09];
  static const _separator = 0x0c;

  /// §7.1 handshake headers, sent exactly as written.
  static const Map<String, String> headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    'Origin': 'https://play.sooplive.co.kr',
  };

  /// §7.1 the subprotocol the chat server requires.
  static const protocols = ['chat'];

  /// §7.5 heartbeat period.
  static const heartbeatInterval = Duration(seconds: 20);

  /// §7.1 the chat endpoints of a room: TLS on the port after `CHPT` (what
  /// the HTTPS player uses), then the plain port.
  static List<Uri> endpoints({required String host, required int port, required String bj}) => [
    Uri(scheme: 'wss', host: host, port: port + 1, path: '/Websocket/$bj'),
    Uri(scheme: 'ws', host: host, port: port, path: '/Websocket/$bj'),
  ];

  /// §7.2 `ESC TAB`, 4-digit service, 6-digit body length, `00`, body.
  static Uint8List packet(int service, List<String> fields) {
    final body = <int>[];
    for (final (index, field) in fields.indexed) {
      if (index > 0) body.add(_separator);
      body.addAll(utf8.encode(field));
    }
    return Uint8List.fromList([
      ..._escape,
      ...ascii.encode(service.toString().padLeft(4, '0')),
      ...ascii.encode(body.length.toString().padLeft(6, '0')),
      ...ascii.encode('00'),
      ...body,
    ]);
  }

  /// §7.3 the login packet (service 1).
  static Uint8List login() => packet(1, const ['', '', '', '16', '']);

  /// §7.3 joining chat room [chatNo] (service 2).
  static Uint8List join(String chatNo) => packet(2, ['', chatNo, '', '', '', '', '']);

  /// §7.5 keep-alive (service 0).
  static Uint8List ping() => packet(0, const ['', '']);

  /// §7.2 every packet of one frame; stops at a malformed header.
  static List<SoopPacket> packets(List<int> frame) {
    final bytes = frame is Uint8List ? frame : Uint8List.fromList(frame);
    final result = <SoopPacket>[];
    var offset = 0;
    while (offset + 14 <= bytes.length) {
      if (bytes[offset] != _escape[0] || bytes[offset + 1] != _escape[1]) break;
      final service = int.tryParse(ascii.decode(bytes.sublist(offset + 2, offset + 6), allowInvalid: true));
      final length = int.tryParse(ascii.decode(bytes.sublist(offset + 6, offset + 12), allowInvalid: true));
      if (service == null || length == null || length < 0 || offset + 14 + length > bytes.length) break;
      final body = Uint8List.sublistView(bytes, offset + 14, offset + 14 + length);
      final fields = <String>[];
      var start = 0;
      for (var i = 0; i <= body.length; i++) {
        if (i == body.length || body[i] == _separator) {
          fields.add(utf8.decode(Uint8List.sublistView(body, start, i), allowMalformed: true));
          start = i + 1;
        }
      }
      result.add(SoopPacket(service, fields));
      offset += 14 + length;
    }
    return result;
  }

  /// §7.4 a chat line (service 5): text in field 1, sender id in 2 (a
  /// `(n)` suffix counts the sender's sessions), nick in 6.
  static DanmakuChat? chat(SoopPacket packet, DecodeContext context) {
    if (packet.service != 5 || packet.fields.length < 7) return null;
    final text = packet.fields[1].trim();
    if (text.isEmpty) return null;
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      userId: packet.fields[2].replaceFirst(RegExp(r'\(\d+\)$'), ''),
      userName: packet.fields[6],
      text: text,
    );
  }
}

/// SOOP's chat connection (spec/sites/soop.md §7): exact-case handshake
/// with the `chat` subprotocol, login, then the room join once the login
/// is answered.
final class SoopConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys` name the chat server
  /// (`chatHost`, `chatPort`), the room (`chatNo`) and the broadcaster (`bj`).
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _chatNo => detail.danmakuKeys['chatNo'] ?? '';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final keys = detail.danmakuKeys;
    final host = keys['chatHost'];
    final port = int.tryParse(keys['chatPort'] ?? '');
    if (host == null || port == null || _chatNo.isEmpty) {
      throw const DanmakuStartFailure('credentials', 'no chat server in the room detail');
    }
    return SocketPlan(
      endpoints: SoopProtocol.endpoints(host: host, port: port, bj: keys['bj'] ?? room.roomId),
      headers: SoopProtocol.headers,
      protocols: SoopProtocol.protocols,
      exactHeaders: true,
    );
  }

  @override
  List<List<int>> openFrames() => [SoopProtocol.login()];

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => SoopProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => SoopProtocol.ping();

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    final bytes = switch (data) {
      final List<int> frame => frame,
      final String text => utf8.encode(text),
      _ => null,
    };
    if (bytes == null) return FrameResult.empty;
    final replies = <List<int>>[];
    final events = <DanmakuEvent>[];
    var joined = false;
    for (final packet in SoopProtocol.packets(bytes)) {
      switch (packet.service) {
        case 1:
          replies.add(SoopProtocol.join(_chatNo));
        case 2:
          joined = packet.fields.length > 1 && packet.fields[1] == _chatNo;
        case 5:
          if (SoopProtocol.chat(packet, context) case final chat?) events.add(chat);
      }
    }
    return FrameResult(events: events, replies: replies, joined: joined);
  }
}
