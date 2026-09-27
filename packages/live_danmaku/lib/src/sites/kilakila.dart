import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_danmaku/src/transport.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// KilaKila's guest chat (spec/sites/kilakila.md §7): Socket.IO 2 over
/// Engine.IO 3 on a WebSocket, namespace `/live_chat_room_guest`. Without
/// I/O.
abstract final class KilakilaProtocol {
  /// Engine.IO ping period (the server announces `pingInterval: 25000`).
  static const heartbeatInterval = Duration(seconds: 25);

  /// The Socket.IO namespace.
  static const namespace = '/live_chat_room_guest';

  /// Handshake headers.
  static const Map<String, String> headers = {'origin': 'https://live.kilakila.cn', 'user-agent': _userAgent};

  static String _query(String roomId) => 'roomId=$roomId&appId=111&clientType=1';

  /// §7.1 the socket of broadcast [roomId].
  static Uri endpoint(String roomId) =>
      Uri.parse('wss://wim.hongrenshuo.com.cn/socket.io/?${_query(roomId)}&EIO=3&transport=websocket');

  /// §7.1 the namespace connect packet (a text frame).
  static TextFrame join(String roomId) => TextFrame('40$namespace?${_query(roomId)},');

  /// §7.2 the Engine.IO ping (a text frame).
  static TextFrame ping() => TextFrame('2');

  /// §7.1–§7.3 decodes one received message.
  static FrameResult decode(Object? data, {required String roomId, required DecodeContext context}) {
    if (data is! String) return FrameResult.empty;
    if (data == '40$namespace' || data.startsWith('40$namespace,')) return const FrameResult(joined: true);
    const prefix = '42$namespace,';
    if (!data.startsWith(prefix)) return FrameResult.empty;
    final Object? packet;
    try {
      packet = jsonDecode(data.substring(prefix.length));
    } on FormatException {
      return FrameResult.empty;
    }
    if (packet is! List || packet.length < 2 || packet[1] is! String) return FrameResult.empty;
    final payload = _object(packet[1]);
    if (payload == null) return FrameResult.empty;
    switch (packet[0]) {
      case 'connect_error':
        // The join answer arrives under this event name; code 0 is success.
        final code = payload['code'];
        return code == 0 ? const FrameResult(joined: true) : const FrameResult(rejected: true);
      case 'text_message':
        final body = payload['body'];
        final response = body is Map ? body['response'] : null;
        if (response is! Map) return FrameResult.empty;
        if ('${response['room_id'] ?? roomId}' != roomId) return FrameResult.empty;
        final content = _object(response['content']);
        if (content == null) return FrameResult.empty;
        final created = response['created_at'];
        final sentAt = created is int && created > 0 ? DateTime.fromMillisecondsSinceEpoch(created) : null;
        final id = response['mid'] == null ? null : 'kilakila:${response['mid']}';
        return FrameResult(
          events: [?_message(content, context, id: id, sentAt: sentAt)],
        );
      default:
        return FrameResult.empty;
    }
  }

  static DanmakuEvent? _message(Map<dynamic, dynamic> content, DecodeContext context, {String? id, DateTime? sentAt}) {
    final user = '${content['u'] ?? ''}';
    final name = content['n'] is String ? content['n'] as String : '';
    switch (content['t']) {
      case 200:
        final text = '${content['c'] ?? ''}'.trim();
        if (text.isEmpty) return null;
        return DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id,
          sentAt: sentAt,
          userId: user,
          userName: name,
          text: text,
          userLevel: _int(content['l']),
        );
      case 220:
        final gift = content['c'];
        if (gift is! Map || '${gift['name'] ?? ''}'.isEmpty) return null;
        return DanmakuGift(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id,
          sentAt: sentAt,
          userId: user,
          userName: name,
          giftId: '${gift['id'] ?? ''}',
          giftName: '${gift['name']}',
          count: _int(gift['doubleCount']) ?? 1,
          icon: gift['pic'] is String ? Uri.tryParse(gift['pic'] as String) : null,
        );
      default:
        return null;
    }
  }

  static Map<dynamic, dynamic>? _object(Object? value) {
    if (value is Map) return value;
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };
}

/// KilaKila's guest chat connection for the current broadcast
/// (`danmakuKeys['roomId']`).
final class KilakilaConnector extends SocketConnector {
  /// Creates the connector.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _roomId => detail.danmakuKeys['roomId'] ?? '';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    if (_roomId.isEmpty) throw const DanmakuStartFailure('credentials', 'no current broadcast');
    return SocketPlan(endpoints: [KilakilaProtocol.endpoint(_roomId)], headers: KilakilaProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => [KilakilaProtocol.join(_roomId)];

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => KilakilaProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => KilakilaProtocol.ping();

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      KilakilaProtocol.decode(data, roomId: _roomId, context: context);
}
