import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// What one KilaKila chat frame held ([KilakilaDanmakuProtocol.decode]).
@immutable
final class KilakilaDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.joined = false, this.refusal, this.dropped = false});

  /// Nothing to act on.
  static const KilakilaDanmakuFrame empty = KilakilaDanmakuFrame();

  /// Chat and audience updates, in order.
  final List<LiveMessage> messages;

  /// The server confirmed the guest namespace (its `40` packet, or the
  /// `connect_error` event with `code 0`, which is how it says "join
  /// success").
  final bool joined;

  /// The server refused the join: the `connect_error` event with another
  /// code, or a Socket.IO error packet on the namespace. The text is its
  /// message, or the code.
  final String? refusal;

  /// The server left the namespace (Socket.IO `41`) or is closing the
  /// transport (Engine.IO `1`).
  final bool dropped;
}

/// KilaKila's guest chat room (docs/modules/M5.13-kilakila.md), without I/O:
/// Socket.IO 2 over Engine.IO 3 on a WebSocket, the namespace
/// `/live_chat_room_guest` (the archived v4's spec/sites/kilakila.md §7 and
/// the live page's own client, `/static/pclive/js/chunk-82396490.*.js`).
///
/// - The socket's query names the broadcast (`roomId`, the current
///   broadcast's `roomIdStr`); the server subscribes the socket by it.
/// - The client joins the namespace with a text frame, and sends the
///   Engine.IO ping `2` every 25 s (the server's `pingInterval`); the server
///   answers `3` and drops a socket that has not pinged for 85 s.
/// - Chat and room state come as `text_message` events whose payload is a
///   JSON string; its `body.response.content` is another JSON string with
///   short field names.
abstract final class KilakilaDanmakuProtocol {
  /// The chat server.
  static const String host = 'wim.hongrenshuo.com.cn';

  /// The guest namespace (the live page's `ROOM_URI` path).
  static const String namespace = '/live_chat_room_guest';

  /// Engine.IO ping period: the server announces `pingInterval: 25000`.
  static const Duration heartbeatInterval = Duration(seconds: 25);

  /// The Engine.IO ping; the server answers `3`.
  static const String ping = '2';

  /// Handshake headers: the site's origin and the adapter's user agent
  /// (`KilakilaApi.userAgent`). No cookie: guests are anonymous.
  static const Map<String, String> handshakeHeaders = {
    'origin': KilakilaApi.origin,
    'user-agent': KilakilaApi.userAgent,
  };

  /// `content.t` of a chat line.
  static const int chatType = 200;

  /// `content.t` of the room state pushed about every 5 s, whose
  /// URL-encoded `c` holds `watchNumber`, the listeners now.
  static const int roomStateType = 637;

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  static String _query(String roomId) => 'roomId=$roomId&appId=111&clientType=1';

  /// The socket of broadcast [roomId] (Socket.IO's default path with the
  /// live page's query; the page's `wss://…/live_chat_room_guest?…` is
  /// Socket.IO's "URL and namespace" form).
  static Uri endpoint(String roomId) => Uri.parse('wss://$host/socket.io/?${_query(roomId)}&EIO=3&transport=websocket');

  /// The namespace connect packet for [roomId], sent as text as soon as the
  /// socket opens (socket.io-client 2's form: namespace, query, comma).
  static String join(String roomId) => '40$namespace?${_query(roomId)},';

  /// Reads one frame of [roomId]'s socket.
  ///
  /// - Engine.IO: `0` (open), `3` (pong) and `6` (noop) hold nothing; `1`
  ///   means the server is closing ([KilakilaDanmakuFrame.dropped]).
  /// - Socket.IO on the guest namespace: `40` joined, `41` dropped, `44` a
  ///   refusal, `42` an event: `connect_error` (joined when its `code` is
  ///   0, a refusal otherwise) or `text_message` ([textMessage]).
  ///
  /// Other namespaces, other events, binary frames and anything malformed
  /// give nothing.
  static KilakilaDanmakuFrame decode(Object? data, {required String roomId}) {
    if (data is! String || data.isEmpty) return KilakilaDanmakuFrame.empty;
    switch (data[0]) {
      case '1':
        return const KilakilaDanmakuFrame(dropped: true);
      case '4':
        return _packet(data.substring(1), roomId: roomId);
      default:
        return KilakilaDanmakuFrame.empty;
    }
  }

  static KilakilaDanmakuFrame _packet(String packet, {required String roomId}) {
    if (packet.isEmpty) return KilakilaDanmakuFrame.empty;
    final rest = packet.substring(1);
    if (!rest.startsWith(namespace)) return KilakilaDanmakuFrame.empty;
    final after = rest.substring(namespace.length);
    // The namespace ends at the comma before the data, or at the end.
    if (after.isNotEmpty && after[0] != ',') return KilakilaDanmakuFrame.empty;
    final body = after.isEmpty ? '' : after.substring(1);
    switch (packet[0]) {
      case '0':
        return const KilakilaDanmakuFrame(joined: true);
      case '1':
        return const KilakilaDanmakuFrame(dropped: true);
      case '2':
        return _event(body, roomId: roomId);
      case '4':
        return KilakilaDanmakuFrame(refusal: _errorText(body));
      default:
        return KilakilaDanmakuFrame.empty;
    }
  }

  static KilakilaDanmakuFrame _event(String body, {required String roomId}) {
    final Object? event;
    try {
      event = jsonDecode(body);
    } on FormatException {
      return KilakilaDanmakuFrame.empty;
    }
    // The payload is a JSON string, as the live page parses it.
    if (event case [final String name, final String json, ...]) {
      final payload = _object(json);
      if (payload == null) return KilakilaDanmakuFrame.empty;
      switch (name) {
        case 'connect_error':
          final code = payload['code'];
          if (code == 0) return const KilakilaDanmakuFrame(joined: true);
          final message = payload['message'];
          return KilakilaDanmakuFrame(refusal: message is String && message.isNotEmpty ? message : 'code $code');
        case 'text_message':
          return KilakilaDanmakuFrame(messages: [?textMessage(payload, roomId: roomId)]);
      }
    }
    return KilakilaDanmakuFrame.empty;
  }

  static String _errorText(String body) {
    try {
      switch (jsonDecode(body)) {
        case final String error when error.isNotEmpty:
          return error;
        case {'message': final String message} when message.isNotEmpty:
          return message;
      }
    } on FormatException {
      // Not JSON: the text itself.
    }
    return body.isEmpty ? 'error' : body;
  }

  /// The message of one `text_message` [payload] of [roomId], or null.
  ///
  /// `body.response` holds `room_id` (a message of another broadcast is
  /// skipped), `mid` (the message id), `created_at` (milliseconds) and
  /// `content`, a JSON string whose `t` is the kind:
  ///
  /// - [chatType]: a chat line ([chat]);
  /// - [roomStateType]: the room state, whose `watchNumber` is the listeners
  ///   now ([audience]).
  ///
  /// Everything else holds nothing to show here: gifts (220 and the gift
  /// line 10004), entries (101, 603), leaves (102), likes (210, 211), rank
  /// and activity updates (635, 636, 654, 663…), the broadcast's end (103,
  /// or `msg_type` 11).
  static LiveMessage? textMessage(Map<Object?, Object?> payload, {required String roomId}) {
    if (payload case {'body': {'response': final Map<Object?, Object?> response}}) {
      final room = response['room_id'];
      if (room != null && '$room' != roomId) return null;
      final content = _object(response['content']);
      return switch (content?['t']) {
        chatType => chat(content!, response),
        roomStateType => audience(content!),
        _ => null,
      };
    }
    return null;
  }

  /// A chat line (`t` 200) as white chat, or null when its text (`c`) is
  /// not text or blank:
  ///
  /// - the text is `c`, trimmed; the name `n` (as it is); the user id `u`
  ///   (a number or text); the level `l`, as the archived v4 read it;
  /// - the message id is the response's `mid`, the time its `created_at`
  ///   (left out when not a positive whole number within `DateTime`'s
  ///   range).
  ///
  /// The avatar `a`, badges (`ui`, `uc`), `vip`, `m` (manager) and `g`
  /// (gender) are not read.
  static LiveMessage? chat(Map<Object?, Object?> content, Map<Object?, Object?> response) {
    final text = content['c'];
    if (text is! String || text.trim().isEmpty) return null;
    final name = content['n'];
    final created = response['created_at'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name is String ? name : '',
      userId: _id(content['u']),
      message: text.trim(),
      color: LiveMessageColor.white,
      userLevel: _level(content['l']),
      messageId: _id(response['mid']),
      sentAt: created is int && created > 0 && created <= _maxMillis
          ? DateTime.fromMillisecondsSinceEpoch(created)
          : null,
    );
  }

  /// The listeners now of a room state (`t` 637): its `c` is URL-encoded
  /// JSON (the live page runs `decodeURIComponent` and `JSON.parse`) whose
  /// `watchNumber`, a whole number not below 0, is what the page shows as
  /// “收听” while the broadcast is live. Null for anything else.
  static LiveMessage? audience(Map<Object?, Object?> content) {
    final encoded = content['c'];
    final state = _object(encoded is String ? _decodeUriComponent(encoded) : null);
    final watching = state?['watchNumber'];
    if (watching is! int || watching < 0) return null;
    return LiveMessage(
      type: LiveMessageType.online,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: watching),
    );
  }

  static final RegExp _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  /// JavaScript's `decodeURIComponent`, or null where it throws (a `%`
  /// without two hex digits, bytes that are not UTF-8).
  static String? _decodeUriComponent(String text) {
    if (_badEscape.hasMatch(text)) return null;
    try {
      return Uri.decodeComponent(text);
    } on FormatException {
      return null;
    }
  }

  static Map<Object?, Object?>? _object(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<Object?, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _id(Object? value) => switch (value) {
    final int number => '$number',
    final String text => text.trim(),
    _ => '',
  };

  static String _level(Object? value) => switch (value) {
    final int number => '$number',
    final String text => int.tryParse(text)?.toString() ?? '',
    _ => '',
  };
}

/// KilaKila's guest chat connection (new in v4: 3.x had none, the 15-8
/// upgrade), on the WebSocket runtime: one socket per broadcast
/// (`KilakilaDanmakuArgs.roomId`).
///
/// - The namespace join goes out as soon as the socket opens; the room is
///   joined when the server confirms it, within 8 s, or the socket is
///   replaced.
/// - The Engine.IO ping goes out every 25 s from the open; the server
///   answers every one, so a socket silent for max(3 × 25 s, 90 s) = 90 s is
///   replaced.
/// - A refused join reconnects with a [DanmakuInterruption.protocolError]
///   notice, [maxRefusals] times in a row; the next refusal ends the run
///   with [DanmakuCloseReason.connectionFailed]. A confirmed join clears
///   the count. A server that leaves the namespace or closes the transport
///   is reconnected.
///
/// The app registers it as `SiteIds.kilakila: () =>
/// KilakilaDanmakuConnection(proxy: …)`.
final class KilakilaDanmakuConnection extends DanmakuSocketConnection<KilakilaDanmakuArgs> {
  /// Creates the connection; [proxy] routes the socket. `connector` replaces
  /// `dart:io`'s handshake and `policy` the timing (tests).
  new({super.proxy, super.connector, super.policy = defaultPolicy}) : super(site: SiteIds.kilakila);

  /// The platform's timing: the 25 s Engine.IO ping and an 8 s join timer
  /// (the archived v4's), the runtime's defaults otherwise.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: KilakilaDanmakuProtocol.heartbeatInterval,
    joinTimeout: Duration(seconds: 8),
  );

  /// Refused joins in a row that are retried (the archived v4's
  /// `maxRejections`); the next one ends the run.
  static const int maxRefusals = 3;

  _Room? _room;

  @override
  @protected
  Future<DanmakuSocketTarget> target(KilakilaDanmakuArgs args, DanmakuRun run) async {
    final roomId = args.roomId.trim();
    if (!KilakilaApi.isId(roomId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No broadcast');
    }
    _room = _Room(run, roomId);
    return DanmakuSocketTarget(
      endpoints: [KilakilaDanmakuProtocol.endpoint(roomId)],
      headers: KilakilaDanmakuProtocol.handshakeHeaders,
    );
  }

  _Room? _of(DanmakuSocketSession session) {
    final room = _room;
    return room != null && identical(room.run, session.run) ? room : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final room = _of(session);
    if (room == null) return;
    room.socket = _Socket.joining;
    session
      ..markDisconnected()
      ..send(KilakilaDanmakuProtocol.join(room.roomId));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final room = _of(session);
    // A socket given up (refused, dropped) may still deliver frames until
    // the reconnect replaces it; they are not this room's any more.
    if (room == null || room.socket == _Socket.abandoned) return;
    final frame = KilakilaDanmakuProtocol.decode(data, roomId: room.roomId);
    for (final message in frame.messages) {
      if (!session.isActive) return;
      session.message(message);
    }
    final refusal = frame.refusal;
    if (refusal != null) {
      _refused(session, room, refusal);
    } else if (frame.dropped) {
      room.socket = _Socket.abandoned;
      session
        ..markDisconnected()
        ..reconnect();
    } else if (frame.joined && room.socket == _Socket.joining) {
      room
        ..socket = _Socket.joined
        ..refusals = 0;
      session.ready();
    }
  }

  void _refused(DanmakuSocketSession session, _Room room, String refusal) {
    room
      ..socket = _Socket.abandoned
      ..refusals += 1;
    session.markDisconnected();
    if (room.refusals > maxRefusals) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Join refused: $refusal');
      return;
    }
    session.reconnect(notice: DanmakuInterruption.protocolError, detail: refusal);
  }

  /// The join was not confirmed in time: this socket is given up and
  /// replaced, without a notice of its own.
  @override
  @protected
  void onJoinTimeout(DanmakuSocketSession session) {
    _of(session)?.socket = _Socket.abandoned;
    session.reconnect();
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => KilakilaDanmakuProtocol.ping;

  @override
  @protected
  Future<void> stop() async {
    _room = null;
    await super.stop();
  }
}

/// Where the current socket of a [_Room] stands.
enum _Socket {
  /// Opened, the join sent, not confirmed yet.
  joining,

  /// The join was confirmed.
  joined,

  /// Refused, dropped or not confirmed in time: a reconnect replaces it.
  abandoned,
}

/// The broadcast of one run and its join state.
final class _Room {
  new(this.run, this.roomId);

  final DanmakuRun run;
  final String roomId;

  /// The current socket's state.
  _Socket socket = _Socket.joining;

  /// Refused joins since the last confirmed one.
  int refusals = 0;
}
