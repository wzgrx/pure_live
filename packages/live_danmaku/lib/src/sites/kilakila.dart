import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`): a gift
/// line (10004), or a gift animation (220) that is not a combo hit
/// ([KilakilaDanmakuProtocol.gift]).
@immutable
final class KilakilaGift {
  /// Creates the gift.
  const new({
    required this.id,
    required this.name,
    required this.count,
    required this.price,
    this.receiverName = '',
    this.icon,
  });

  /// `c.id`, or empty.
  final String id;

  /// `c.name` (`念念相守`).
  final String name;

  /// `c.doubleCount`, at least 1.
  final int count;

  /// Red beans (红豆) for all [count] gifts.
  final int price;

  /// `c.giftReceiverName`: the broadcaster, or a guest on the microphone;
  /// empty when missing.
  final String receiverName;

  /// `c.pic` when it is an https URL.
  final Uri? icon;

  /// A gift that costs nothing (price 0: 克拉之星, 守护灯牌…).
  bool get free => price == 0;

  @override
  bool operator ==(Object other) =>
      other is KilakilaGift &&
      other.id == id &&
      other.name == name &&
      other.count == count &&
      other.price == price &&
      other.receiverName == receiverName &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, name, count, price, receiverName, icon);

  @override
  String toString() => 'KilakilaGift($name ×$count, $price)';
}

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

/// KilaKila's guest chat room (docs/D-弹幕/D01-平台弹幕协议/D01.14-克拉克拉弹幕/record.md), without I/O:
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

  /// `content.t` of a gift animation (the page's gift bar). A combo sends
  /// one per hit with the count so far; see [gift].
  static const int giftType = 220;

  /// `content.t` of a gift line (the page's chat list: “我送了…”), sent
  /// when a combo ends, with its total.
  static const int giftLineType = 10004;

  /// `content.t` of a paid question being asked (the asker and the price,
  /// not the text). The page ignores it; not reported.
  static const int questionAskedType = 241;

  /// `content.t` of the messages that change the broadcast's board (room
  /// image, question card, microphone list): the page's `dealData` reads
  /// `uc.uiType` and `uc.question` of all of them.
  static const Set<int> boardTypes = {240, 300, 301, 532, 534, 706};

  /// `uc.uiType` values with which the page shows `uc.question` on the
  /// board (`updateQuestion(t.uc.question)`); 8, 12 and 13 clear it.
  static const Set<int> questionUiTypes = {2, 3, 6, 7, 10, 11, 14, 15};

  /// How long a paid question stays a super chat. The page shows the card
  /// until the broadcaster takes it off the board; in 40 minutes of the 30
  /// busiest broadcasts (2026-09-30) paid questions stayed on the board
  /// 11–865 s, half of them under 4.5 minutes.
  static const Duration questionDisplay = Duration(minutes: 5);

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
  /// give nothing. [now] stands for the time of reception where a message
  /// has none of its own (tests).
  static KilakilaDanmakuFrame decode(Object? data, {required String roomId, DateTime? now}) {
    if (data is! String || data.isEmpty) return KilakilaDanmakuFrame.empty;
    switch (data[0]) {
      case '1':
        return const KilakilaDanmakuFrame(dropped: true);
      case '4':
        return _packet(data.substring(1), roomId: roomId, now: now);
      default:
        return KilakilaDanmakuFrame.empty;
    }
  }

  static KilakilaDanmakuFrame _packet(String packet, {required String roomId, DateTime? now}) {
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
        return _event(body, roomId: roomId, now: now);
      case '4':
        return KilakilaDanmakuFrame(refusal: _errorText(body));
      default:
        return KilakilaDanmakuFrame.empty;
    }
  }

  static KilakilaDanmakuFrame _event(String body, {required String roomId, DateTime? now}) {
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
          return KilakilaDanmakuFrame(
            messages: [?textMessage(payload, roomId: roomId, now: now)],
          );
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
  ///   now ([audience]);
  /// - [giftType], [giftLineType]: a gift ([gift], M5.F B-10; not shown
  ///   yet);
  /// - [boardTypes]: a paid question put on the board, as a super chat
  ///   ([question], M5.F B-10).
  ///
  /// Everything else holds nothing to show here: a question being asked
  /// (241), entries (101, 603), leaves (102), likes (210) and the first
  /// light-up (211) (M5.F: not shown, as on every platform), rank and
  /// activity updates (635, 636, 654, 663…), the broadcast's end (103, or
  /// `msg_type` 11).
  static LiveMessage? textMessage(Map<Object?, Object?> payload, {required String roomId, DateTime? now}) {
    if (payload case {'body': {'response': final Map<Object?, Object?> response}}) {
      final room = response['room_id'];
      if (room != null && '$room' != roomId) return null;
      final content = _object(response['content']);
      return switch (content?['t']) {
        chatType => chat(content!, response),
        roomStateType => audience(content!),
        giftType || giftLineType => gift(content!, response),
        final int type when boardTypes.contains(type) => question(content!, response, now: now),
        _ => null,
      };
    }
    return null;
  }

  /// A gift (M5.F B-10), reported once per gift sent:
  ///
  /// - a gift line (10004): the page's chat line for a combo that ended,
  ///   with its total count (`c.doubleCount`) and the price of one gift
  ///   (`c.price`);
  /// - a gift animation (220) that is not a combo hit (`c.isDoubleHit` not
  ///   true): a gift sent at once, `c.price` for all of it; nothing else
  ///   follows it.
  ///
  /// Combo hits (220 with `isDoubleHit` true) are not reported: their
  /// counts run up (1, 2, 3…) and some are skipped when hits come fast; the
  /// line that ends the combo has the total (2026-09-30: all 1,932 lines of
  /// 30 broadcasts ended a combo, none followed a gift sent at once).
  ///
  /// The text is the page's line (`SEND_TEXT`):
  /// `我送了{receiver}{count}个{gift}`, with “豆咖” for a missing receiver;
  /// the sender is `n` and `u`, the level `l`, the id and time the
  /// response's `mid` and `created_at`. Null without a `c` object or a gift
  /// name.
  static LiveMessage? gift(Map<Object?, Object?> content, Map<Object?, Object?> response) {
    final item = content['c'];
    if (item is! Map<Object?, Object?>) return null;
    final line = content['t'] == giftLineType;
    if (!line && item['isDoubleHit'] == true) return null;
    final name = item['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final count = switch (jsonInt(item['doubleCount'])) {
      final int value when value > 0 => value,
      _ => 1,
    };
    final price = switch (jsonInt(item['price'])) {
      final int value when value > 0 => value,
      _ => 0,
    };
    final receiver = item['giftReceiverName'];
    final receiverName = receiver is String ? receiver.trim() : '';
    final icon = jsonUrl(item['pic']);
    final present = KilakilaGift(
      id: _id(item['id']),
      name: name.trim(),
      count: count,
      price: line ? price * count : price,
      receiverName: receiverName,
      icon: icon != null && icon.scheme == 'https' ? icon : null,
    );
    final sender = content['n'];
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: sender is String ? sender : '',
      userId: _id(content['u']),
      message: '我送了${receiverName.isEmpty ? '豆咖' : receiverName}$count个${present.name}',
      color: LiveMessageColor.white,
      userLevel: _level(content['l']),
      messageId: _id(response['mid']),
      sentAt: _time(response['created_at']),
      data: present,
    );
  }

  /// A paid question the broadcaster put on the board, as a super chat
  /// (M5.F B-10): a [boardTypes] message whose `uc.uiType` shows
  /// `uc.question` ([questionUiTypes]) and whose `goldPrice` is above 0.
  /// Free questions (`goldPrice` 0) and boards without a question give
  /// nothing.
  ///
  /// The page URL-decodes every text field of the question first (and loses
  /// the message when one does not decode) and trims `content`. The super
  /// chat is the asker (`questionNickname`, `questionHeadUrl` when https,
  /// `questionUid`), the text `content`, the price `goldPrice` in red beans
  /// with the page's writing of it (“1,000红豆”), the id `questionId` (the
  /// same question shown again is the same super chat), from `created_at`
  /// (else [now], else the time of reading) for [questionDisplay]; no
  /// colours. Null without a text.
  static LiveMessage? question(Map<Object?, Object?> content, Map<Object?, Object?> response, {DateTime? now}) {
    final board = content['uc'];
    if (board is! Map<Object?, Object?> || !questionUiTypes.contains(jsonInt(board['uiType']))) return null;
    final raw = board['question'];
    if (raw is! Map<Object?, Object?>) return null;
    final fields = <Object?, Object?>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (value is String) {
        final decoded = _decodeUriComponent(value);
        if (decoded == null) return null;
        fields[key] = decoded;
      } else {
        fields[key] = value;
      }
    }
    final price = jsonInt(fields['goldPrice']);
    if (price == null || price <= 0) return null;
    final body = fields['content'];
    final text = body is String ? body.trim() : '';
    if (text.isEmpty) return null;
    final asker = fields['questionNickname'];
    final name = asker is String ? asker : '';
    final face = jsonUrl(fields['questionHeadUrl']);
    final id = _id(fields['questionId']);
    final sentAt = _time(response['created_at']);
    final start = sentAt ?? now ?? DateTime.now();
    final superChat = LiveSuperChatMessage(
      messageId: id,
      userName: name,
      face: face != null && face.scheme == 'https' ? '$face' : '',
      message: text,
      price: price,
      priceText: '${amount(price)}红豆',
      startTime: start,
      endTime: start.add(questionDisplay),
      backgroundColor: '',
      backgroundBottomColor: '',
    );
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: name,
      userId: _id(fields['questionUid']),
      message: text,
      color: LiveMessageColor.white,
      messageId: id,
      sentAt: sentAt,
      data: superChat,
    );
  }

  /// [value] as the page writes an amount (`amountRule`): thousands
  /// separated by commas (6000 → `6,000`).
  static String amount(int value) {
    final digits = value.abs().toString();
    final text = StringBuffer(value < 0 ? '-' : '');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) text.write(',');
      text.write(digits[index]);
    }
    return text.toString();
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
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name is String ? name : '',
      userId: _id(content['u']),
      message: text.trim(),
      color: LiveMessageColor.white,
      userLevel: _level(content['l']),
      messageId: _id(response['mid']),
      sentAt: _time(response['created_at']),
    );
  }

  /// `created_at`: a positive whole number of milliseconds within
  /// `DateTime`'s range, else null.
  static DateTime? _time(Object? created) =>
      created is int && created > 0 && created <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(created) : null;

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
  /// without two hex digits, bytes that are not UTF-8). Characters that are
  /// not escapes stay as they are, whatever they are: `Uri.decodeComponent`
  /// throws an `ArgumentError` on any character above U+007F (question
  /// texts are plain Chinese and emoji).
  static String? _decodeUriComponent(String text) {
    if (!text.contains('%')) return text;
    if (_badEscape.hasMatch(text)) return null;
    final decoded = StringBuffer();
    var index = 0;
    while (index < text.length) {
      if (text.codeUnitAt(index) != 0x25) {
        decoded.writeCharCode(text.codeUnitAt(index++));
        continue;
      }
      final bytes = <int>[];
      while (index < text.length && text.codeUnitAt(index) == 0x25) {
        bytes.add(int.parse(text.substring(index + 1, index + 3), radix: 16));
        index += 3;
      }
      try {
        decoded.write(utf8.decode(bytes));
      } on FormatException {
        return null;
      }
    }
    return decoded.toString();
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
