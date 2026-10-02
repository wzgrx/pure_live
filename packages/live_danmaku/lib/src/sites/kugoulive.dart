import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one Kugou Live chat frame held ([KugouLiveDanmakuProtocol.decode]).
@immutable
final class KugouLiveDanmakuFrame {
  /// Creates the result.
  const new({
    this.messages = const [],
    this.joined = false,
    this.sessionId,
    this.refusal,
    this.heartbeat = false,
    this.ack,
  });

  /// Chat and audience updates, in order.
  final List<LiveMessage> messages;

  /// The acknowledgement to send (command 211), or null: the page answers
  /// every gift (601) whose envelope asks for one (`ack` 1); unanswered, the
  /// server sends it twice more, about 2 s apart.
  final Uint8List? ack;

  /// The server accepted the login (status 901 of type 1 with status 1).
  final bool joined;

  /// The session of an accepted login (`socsid`), sent again when the socket
  /// logs in anew (command 2201); null when the answer had none.
  final String? sessionId;

  /// The server refused the login (status 901 of type 1, another status),
  /// or null.
  final KugouLiveChatRefusal? refusal;

  /// The server's answer to a heartbeat.
  final bool heartbeat;
}

/// A refused login: the status frame's `errorno` and `msg`.
@immutable
final class KugouLiveChatRefusal {
  /// Creates the refusal.
  const new(this.errorNo, [this.message = '']);

  /// `errorno`; [KugouLiveDanmakuProtocol.tokenRejected] (622) when the
  /// login token is not (or no longer) valid.
  final int errorNo;

  /// `msg`, or empty.
  final String message;

  /// Whether the token was refused: a new one is asked for.
  bool get tokenRejected => errorNo == KugouLiveDanmakuProtocol.tokenRejected;

  @override
  String toString() => '901 errorno $errorNo${message.isEmpty ? '' : ' $message'}';
}

/// The scheduler answered with a `code` other than 0 (a signature it does
/// not accept, a client it wants verified by a slider, …): the chat cannot
/// be joined.
final class KugouLiveDispatchRefusal implements Exception {
  /// Creates the refusal.
  const new(this.code, [this.message = '']);

  /// The answer's `code`.
  final int code;

  /// The answer's `msg`, or empty.
  final String message;

  @override
  String toString() => 'dispatch: code $code${message.isEmpty ? '' : ' $message'}';
}

/// What the scheduler granted a room: its chat sockets and a login token.
@immutable
final class KugouLiveChatGrant {
  /// Creates the grant.
  new({required List<Uri> endpoints, required this.token, required this.age})
    : endpoints = List.unmodifiable(endpoints);

  /// The sockets (`protocol` + `addrs[].host`), in the answer's order.
  final List<Uri> endpoints;

  /// `soctoken`, the login's token.
  final String token;

  /// `age`: how long the website keeps the answer for a new visit (5
  /// minutes); a token this old is not used for a new socket.
  final Duration age;
}

/// Kugou Live's (繁星, fanxing.kugou.com) room chat, as the website's room
/// page speaks it (`/pub2/vroom/main/index_*.js`: the scheduler call
/// `dispatchSocket.getDispatchSocketAddress`, the socket wrapper `Fx.socket`,
/// `RoomSocket.login`, the protobuf codec of webpack module 1374 with the
/// schemas of module 80965; the handling of messages in
/// `/pub2/room/js/socket_*.js`; docs/T06/T06a/T06a.26/record.md), without
/// I/O.
///
/// - The scheduler (`socket_scheduler/pc/binary/v2/address.jsonp`, signed
///   with the page's MD5 salt) gives three chat hosts and a token.
/// - Frames are binary: an 18-byte header (100, version 3, type 1, 12, the
///   command, the length, then zeros) and a protobuf `SocketProtocol.Message`
///   whose `content` is the command's message. The server's header is 26
///   bytes (the variable part is 20: command, length, 8 and a millisecond
///   time).
/// - Login is command 201 (`Login.LoginRequest`), 2201 on a reconnect; the
///   server answers with status frames (901, `ErrorResponse`): type 4, then
///   type 1 with status 1 and the session (`socsid`), or another status and
///   `errorno` (622: the token is refused).
/// - The heartbeat is the 4-byte frame `64 00 01 00` every 10 s; the server
///   answers `64 00 03 00`.
/// - A message is a `Content.ContentMessage` (`codec` 1) whose `content` is
///   the command's own protobuf (501 chat: `Chat.ChatResponse`), or JSON
///   (`codec` 0; 301005 the audience), gzipped (`compression` 1) or snappy
///   (2) when the envelope says so.
abstract final class KugouLiveDanmakuProtocol {
  /// The scheduler's path on `KugouLiveApi.apiHost` (the website's
  /// `ServiceHost.backup1ServiceUrl`, `https://fx1.service.kugou.com`).
  static const String dispatchPath = '/socket_scheduler/pc/binary/v2/address.jsonp';

  /// The salt of the scheduler's signature (`$_fan_xing_$`).
  static const String signSalt = r'$_fan_xing_$';

  /// The page's `staticVersion` (`liveInitData.version`), sent as `_v`.
  static const String pageVersion = '7.0.0';

  /// `RoomSocket.socketPv`: the scheduler's `pv` and the login's `v`.
  static const int socketVersion = 20240801;

  /// `cid` of the scheduler and `clientid` of the login.
  static const int clientId = 100;

  /// `at` of a normal room (122 is the page's for a `kugouLive` room).
  static const int roomType = 102;

  /// The login's `appid` (the page's fallback without a login cookie).
  static const int appId = 1010;

  /// The login's `platid`: the web page (8 when it is embedded).
  static const int platformId = 7;

  /// The login command.
  static const int loginCommand = 201;

  /// The login command of a socket that replaces a joined one (`LOGIN_AGAIN`).
  static const int reloginCommand = 2201;

  /// Status frames.
  static const int statusCommand = 901;

  /// Chat of the room.
  static const int chatCommand = 501;

  /// A gift in the room (`SENDGIFT`): not reported, but acknowledged.
  static const int giftCommand = 601;

  /// The acknowledgement of a message (`ACKCMD`, `Ack.AckRequest`).
  static const int ackCommand = 211;

  /// Chat of the other room of a PK (`OTHERMESSAGE`): reported as chat
  /// marked with that room (B-16, [chat]).
  static const int otherRoomChatCommand = 400305;

  /// The audience (`HEAT_NUM`, `actionId` `roomAuNumber`).
  static const int audienceCommand = 301005;

  /// The `errorno` of a refused token.
  static const int tokenRejected = 622;

  /// Heartbeat period (`BEAT_FREQUENCY`).
  static const Duration heartbeatInterval = Duration(seconds: 10);

  /// How long the login may take before the next host is tried (the
  /// scheduler's `addrs[].timeout`, 10 000 ms).
  static const Duration joinTimeout = Duration(seconds: 10);

  /// How long the website keeps a scheduler answer when the answer has no
  /// `age`.
  static const Duration defaultAge = Duration(minutes: 5);

  /// Refused logins in a row after which the connection gives up.
  static const int maxRefusals = 3;

  /// Largest decompressed message.
  static const int maxContentBytes = 4 * 1024 * 1024;

  /// The website's origin and the adapter's desktop UA, as a browser sends
  /// them in the handshake.
  static const Map<String, String> socketHeaders = {
    'origin': KugouLiveApi.webOrigin,
    'user-agent': KugouLiveApi.userAgent,
  };

  static const int _magic = 100;
  static const int _version = 3;
  static const int _dataType = 1;
  static const int _heartbeatType = 0;
  static const int _maxEpochMilliseconds = 8640000000000000;
  static final RegExp _roomId = RegExp(r'^[1-9][0-9]{2,10}$');
  static final RegExp _token = RegExp(r'^[!-~]{1,1024}$');

  /// [roomId] trimmed when it is a room number, else null.
  static String? checkedRoom(String roomId) {
    final room = roomId.trim();
    return _roomId.hasMatch(room) ? room : null;
  }

  /// The scheduler's signature of [query] (`getDispatchSocketAddress`): the
  /// MD5 of the keys in order with their values, `k=v` joined by `&`, and
  /// [signSalt]; its hex characters 8 to 23.
  static String sign(Map<String, String> query) {
    final keys = query.keys.toList()..sort();
    final text = '${keys.map((key) => '$key=${query[key]}').join('&')}$signSalt';
    return md5.convert(utf8.encode(text)).toString().substring(8, 24);
  }

  /// The scheduler's address for room [roomId] at [now] (the page's
  /// parameters in its order, then `sign`).
  static Uri dispatchUrl(String roomId, {required DateTime now}) {
    final query = {
      '_p': '0',
      '_v': pageVersion,
      'pv': '$socketVersion',
      'rid': roomId,
      'clienttime': '${now.millisecondsSinceEpoch}',
      'cid': '$clientId',
      'at': '$roomType',
    };
    return Uri.https(KugouLiveApi.apiHost, dispatchPath, {...query, 'sign': sign(query)});
  }

  /// The scheduler's request for [roomId], as the room page sends it: the
  /// adapter's headers with the room page as Referer, no redirect followed,
  /// sent as `kugoulive` (its proxy route).
  static LiveRequest dispatchRequest(
    String roomId, {
    required DateTime now,
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => LiveRequest(
    site: SiteIds.kugouLive,
    url: dispatchUrl(roomId, now: now),
    headers: {...KugouLiveApi.apiHeaders, 'referer': KugouLiveApi.roomUrl(roomId)},
    followRedirects: false,
    timeout: timeout,
    cancel: cancel,
  );

  /// The grant of a scheduler [response]. A `code` other than 0 throws
  /// [KugouLiveDispatchRefusal]; a failed status or an answer that cannot
  /// be read throws its `SiteError`.
  ///
  /// Each `addrs[].host` becomes `protocol` + host (`ws://` without a
  /// protocol, as the page does); hosts that do not make a `ws`/`wss` URL
  /// are skipped. A token is printable ASCII without spaces.
  static KugouLiveChatGrant grant(LiveResponse response) {
    if (KugouLiveApi.statusError(response.status, 'dispatch') case final error?) throw error;
    final Object? root;
    try {
      root = jsonDecode(response.text);
    } on FormatException {
      throw const ApiChanged(SiteIds.kugouLive, 'dispatch: not JSON');
    }
    if (root is! Map) throw const ApiChanged(SiteIds.kugouLive, 'dispatch: not an object');
    final code = jsonInt(root['code']);
    if (code != 0) throw KugouLiveDispatchRefusal(code ?? -1, _text(root['msg']));
    final data = root['data'];
    if (data is! Map) throw const ApiChanged(SiteIds.kugouLive, 'dispatch: no data');
    final protocol = _text(data['protocol']).isEmpty ? 'ws://' : _text(data['protocol']);
    final endpoints = <Uri>[];
    for (final address in data['addrs'] is List ? data['addrs'] as List : const []) {
      final host = address is Map && address['host'] is String ? address['host'] as String : '';
      final uri = host.isEmpty ? null : Uri.tryParse('$protocol$host');
      if (uri != null &&
          (uri.scheme == 'wss' || uri.scheme == 'ws') &&
          uri.host.isNotEmpty &&
          !endpoints.contains(uri)) {
        endpoints.add(uri);
      }
    }
    final token = _text(data['soctoken']);
    if (endpoints.isEmpty || !_token.hasMatch(token)) {
      throw const ApiChanged(SiteIds.kugouLive, 'dispatch: no chat address or token');
    }
    final age = jsonInt(data['age']);
    return KugouLiveChatGrant(
      endpoints: endpoints,
      token: token,
      age: age != null && age > 0 ? Duration(milliseconds: age) : defaultAge,
    );
  }

  /// A frame of [command] carrying [content] as the page writes it
  /// (`toDataView`, `encodePb`): the 18-byte header, then the envelope
  /// `SocketProtocol.Message{content}`.
  static Uint8List frame(int command, List<int> content) {
    final message = (ProtoWriter()..bytes(7, content)).toBytes();
    final header = ByteData(18)
      ..setUint8(0, _magic)
      ..setInt16(1, _version)
      ..setUint8(3, _dataType)
      ..setInt16(4, 12)
      ..setInt32(6, command)
      ..setInt32(10, message.length);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(message))
        .toBytes();
  }

  /// The anonymous login of room [roomId] (`RoomSocket.login` without a
  /// login cookie): `Login.LoginRequest` with the fields the page sets, in
  /// field order: command, room, `kugouid` 0, an empty `token`, [appId],
  /// [platformId], the device, [socketVersion], `referer` 0, [clientId], the
  /// scheduler's [token], the page's session [sid], the last session
  /// [sessionId] (empty before the first join), `screen` 0 and `dfid` `-`.
  /// [again] is the login of a socket that replaces a joined one (2201).
  static Uint8List login({
    required String roomId,
    required String token,
    required String sid,
    required String deviceNo,
    String sessionId = '',
    bool again = false,
  }) {
    final command = again ? reloginCommand : loginCommand;
    final request = ProtoWriter()
      ..integer(1, command)
      ..integer(2, int.parse(roomId))
      ..integer(3, 0)
      ..string(4, '')
      ..integer(6, appId)
      ..integer(7, platformId)
      ..string(10, deviceNo)
      ..integer(12, socketVersion)
      ..integer(13, 0)
      ..integer(14, clientId)
      ..string(15, token)
      ..string(18, sid)
      ..string(23, sessionId)
      ..integer(29, 0)
      ..string(38, '-');
    return frame(command, request.toBytes());
  }

  /// The heartbeat (`encodeSocketBeat`): 100, version 1, type 0.
  static Uint8List heartbeat() => Uint8List.fromList(const [_magic, 0, 1, _heartbeatType]);

  /// The acknowledgement of a message of room [roomId] (`socket_*.js`, for
  /// a gift whose envelope has `ack` 1): `Ack.AckRequest` with the command
  /// 211, the room, `kugouId` 0 (no login), the envelope's `offset` and
  /// `msgId` and its `rpt`, every field written.
  static Uint8List ack({required String roomId, required String offset, required String msgId, int repeat = 0}) =>
      frame(
        ackCommand,
        (ProtoWriter()
              ..integer(1, ackCommand)
              ..integer(2, int.parse(roomId))
              ..integer(3, 0)
              ..string(4, offset)
              ..string(5, msgId)
              ..integer(6, repeat))
            .toBytes(),
      );

  /// A uuid as the page's `generateUUID` writes it (version 4 form), for the
  /// login's session and device.
  static String uuid(Random random) {
    const hex = '0123456789abcdef';
    final text = StringBuffer();
    for (final char in 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.split('')) {
      text.write(switch (char) {
        'x' => hex[random.nextInt(16)],
        'y' => hex[(random.nextInt(16) & 3) | 8],
        _ => char,
      });
    }
    return text.toString();
  }

  /// One server frame for room [roomId].
  ///
  /// - A frame of type 0 is the heartbeat's answer.
  /// - Status (901): type 1 with status 1 joins (with its `socsid`); type 1
  ///   with another status is a [KugouLiveDanmakuFrame.refusal]; other types
  ///   (4 comes first) say nothing.
  /// - Chat (501) and the PK partner room's chat (400305) as [chat]; the
  ///   audience (301005) as [audience].
  /// - A gift (601) whose envelope asks for it is acknowledged
  ///   ([KugouLiveDanmakuFrame.ack]); gifts are not reported.
  /// - Anything else, text frames, frames that cannot be read (a short
  ///   header, bad protobuf, JSON or compression) give nothing.
  static KugouLiveDanmakuFrame decode(Object? data, {required String roomId}) {
    if (data is! List<int>) return const KugouLiveDanmakuFrame();
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (bytes.length >= 4 && bytes[3] == _heartbeatType) return const KugouLiveDanmakuFrame(heartbeat: true);
    final (int, Map<String, Object?>?) read;
    try {
      read = _packet(bytes);
    } on FormatException {
      return const KugouLiveDanmakuFrame();
    }
    final (command, packet) = read;
    if (packet == null) return const KugouLiveDanmakuFrame();
    switch (command) {
      case statusCommand:
        if (jsonInt(packet['type']) != 1) return const KugouLiveDanmakuFrame();
        if (jsonInt(packet['status']) == 1) {
          final session = _text(packet['socsid']);
          return KugouLiveDanmakuFrame(joined: true, sessionId: session.isEmpty ? null : session);
        }
        return KugouLiveDanmakuFrame(
          refusal: KugouLiveChatRefusal(jsonInt(packet['errorno']) ?? 0, _text(packet['msg'])),
        );
      case chatCommand || otherRoomChatCommand:
        final message = chat(packet, roomId: roomId, otherRoom: command == otherRoomChatCommand);
        return KugouLiveDanmakuFrame(messages: [?message]);
      case audienceCommand:
        return KugouLiveDanmakuFrame(messages: audience(packet, roomId: roomId));
      case giftCommand when jsonInt(packet['ack']) == 1:
        return KugouLiveDanmakuFrame(
          ack: ack(
            roomId: roomId,
            offset: _text(packet['offset']),
            msgId: _text(packet['msgId']),
            repeat: jsonInt(packet['rpt']) ?? 0,
          ),
        );
    }
    return const KugouLiveDanmakuFrame();
  }

  /// The command of [frame] and its message as the page's decoder leaves it
  /// (`decodePb`, then `RoomSocket.callback` takes the envelope's `content`):
  /// a status frame's `ErrorResponse`, a message's `ContentMessage` (with a
  /// chat's `ChatResponse` as `content`, its `ext` and `sinfo`), or the JSON
  /// of a `codec` 0 envelope. Null for what is not read.
  static (int, Map<String, Object?>?) _packet(Uint8List frame) {
    if (frame.length < 10) throw const FormatException('Kugou chat frame too short');
    final view = ByteData.sublistView(frame);
    final start = 6 + view.getInt16(4);
    if (start < 10 || start > frame.length) throw const FormatException('Kugou chat header out of range');
    final command = view.getInt32(6);
    final envelope = ProtoMessage.decode(Uint8List.sublistView(frame, start));
    final content = _uncompress(envelope.bytes(7) ?? Uint8List(0), envelope.integer(5) ?? 0);
    final Map<String, Object?>? packet;
    if ((envelope.integer(6) ?? 0) == 1) {
      packet = command == statusCommand
          ? _status(ProtoMessage.decode(content))
          : _content(ProtoMessage.decode(content), command);
    } else {
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(content));
      } on FormatException {
        return (command, null);
      }
      packet = json is Map ? json.cast<String, Object?>() : null;
    }
    // `RoomSocket.callback` puts the envelope's ack fields on the message.
    return (
      command,
      packet == null
          ? null
          : {
              ...packet,
              'ack': envelope.integer(2) ?? 0,
              'rpt': envelope.integer(3) ?? 0,
              'msgId': envelope.string(4) ?? '',
              'offset': envelope.string(1) ?? '',
            },
    );
  }

  /// `SocketProtocol.ErrorResponse{cmd 1, type 2, seq 3, status 4, errorno
  /// 5, msg 6, socsid 7}`.
  static Map<String, Object?> _status(ProtoMessage status) => {
    'type': status.integer(2) ?? 0,
    'status': status.integer(4) ?? 0,
    'errorno': status.integer(5) ?? 0,
    'msg': status.string(6) ?? '',
    'socsid': status.string(7) ?? '',
  };

  /// `Content.ContentMessage{cmd 1, content 2, roomid 3, receiverid 4,
  /// senderid 6, senderkugouid 7, time 11, ext 14, sinfo 15, codec 16,
  /// source 18 {roomid 1, tags 2}}`; the
  /// `content` of a chat whose `codec` is 1 read as `Chat.ChatResponse`
  /// ([_chatResponse]), its `ext` (`Ext.Extension`) for the fan badge
  /// (`intimacyVo` 39) and the text's colour (`intimacyVo.level`,
  /// `userGuard` 8 `{g 1}`, `littleGuard` 9 `{l 1}`), and its `sinfo` (`ck`
  /// 5, `ckid` 8). Other messages keep only the envelope.
  ///
  /// The page decodes `ext` even when the message has none (an empty
  /// `Extension`), so a chat always has one here; a sub-message it lacks
  /// is left out, as protobufjs leaves it null.
  static Map<String, Object?> _content(ProtoMessage message, int command) {
    final packet = <String, Object?>{
      'roomid': message.integer(3) ?? 0,
      'receiverid': message.integer(4) ?? 0,
      'senderid': message.integer(6) ?? 0,
      'senderkugouid': message.integer(7) ?? 0,
      'time': message.integer(11) ?? 0,
    };
    if ((command != chatCommand && command != otherRoomChatCommand) || (message.integer(16) ?? 0) != 1) {
      return packet;
    }
    final chat = ProtoMessage.decode(message.bytes(2) ?? Uint8List(0));
    final ext = ProtoMessage.decode(message.bytes(14) ?? Uint8List(0));
    final intimacy = ext.message(39);
    final userGuard = ext.message(8);
    final littleGuard = ext.message(9);
    final sinfo = message.message(15);
    final source = message.message(18);
    return {
      ...packet,
      'content': _chatResponse(chat),
      'ext': {
        if (intimacy != null)
          'intimacyVo': {
            'level': intimacy.integer(1) ?? 0,
            'nameplate': intimacy.string(2) ?? '',
            'type': intimacy.integer(3) ?? 0,
            'lightUp': intimacy.integer(5) ?? 0,
          },
        if (userGuard != null) 'userGuard': {'g': userGuard.string(1) ?? ''},
        if (littleGuard != null) 'littleGuard': {'l': littleGuard.integer(1) ?? 0},
      },
      if (sinfo != null) 'sinfo': {'ck': sinfo.integer(5) ?? 0, 'ckid': sinfo.string(8) ?? ''},
      if (source != null) 'source': {'roomid': source.integer(1) ?? 0, 'tags': source.integer(2) ?? 0},
    };
  }

  /// `Chat.ChatResponse{chatmsg 1, senderid 2, senderkugouid 3, sendername
  /// 4, senderrichlevel 5, receiverid 6, receivername 8, seq 13,
  /// senderrichlevelV2 25}`.
  static Map<String, Object?> _chatResponse(ProtoMessage chat) => {
    'chatmsg': chat.string(1) ?? '',
    'senderid': chat.integer(2) ?? 0,
    'senderkugouid': chat.integer(3) ?? 0,
    'sendername': chat.string(4) ?? '',
    'senderrichlevel': chat.integer(5) ?? 0,
    'receiverid': chat.integer(6) ?? 0,
    'receivername': chat.string(8) ?? '',
    'seq': chat.integer(13) ?? 0,
    'senderrichlevelV2': chat.integer(25) ?? 0,
  };

  /// A chat message (`RoomSocket.callback`, case `MESSAGE`, or with
  /// [otherRoom] `OTHERMESSAGE`) of room [roomId] as chat, or null when the
  /// page would not show it in the public chat:
  ///
  /// - the message goes to someone (`receiverid` of the envelope not 0: a
  ///   private message), comes from a negative sender or is marked
  ///   `privateType` 1;
  /// - it names another room (`roomid` not 0 and not [roomId]);
  /// - [otherRoom] (the PK partner's chat, B-16) without `source.tags & 1`
  ///   (the page shows only those) or without the partner's
  ///   `source.roomid`; such a chat carries that room as
  ///   [LiveMessage.sourceRoomId], and the page marks it as the other side.
  ///   Whether the page's PK module also lets it through is not known here
  ///   (it was shown in the one recording, S09);
  /// - it has no text left.
  ///
  /// The text is `chatmsg` and the name `sendername`, without the
  /// separators and direction marks U+2027 to U+202E the page takes out
  /// (`replaceUnicode`), trimmed. A message to someone in public (`receiverid`
  /// of the chat) is shown as its text. The user id is the envelope's
  /// `senderid` (the chat's without one), for a mystery guest (`sinfo.ck` 1)
  /// the alias id `sinfo.ckid`, as the page uses. The level is the wealth
  /// level `senderrichlevelV2`, else `senderrichlevel`; the fan badge is
  /// `ext.intimacyVo`'s `nameplate` and `level` when the page shows it
  /// (level above 0, `type` 1 to 4, `lightUp` 1). The id is the envelope's
  /// `msgId`, else `<sender>:<seq>` (the sender's own counter); the time is
  /// the envelope's `time` (seconds, milliseconds above 10^11). The colour
  /// is the page's for the text ([textColor], M5.F B-15).
  static LiveMessage? chat(Map<String, Object?> packet, {required String roomId, bool otherRoom = false}) {
    if ((jsonInt(packet['receiverid']) ?? 0) != 0 || (jsonInt(packet['senderid']) ?? 0) < 0) return null;
    final content = packet['content'];
    if (content is! Map || jsonInt(content['privateType']) == 1) return null;
    final room = jsonInt(packet['roomid']) ?? 0;
    if (room != 0 && '$room' != roomId) return null;
    var sourceRoom = '';
    if (otherRoom) {
      final source = packet['source'];
      final partner = source is Map ? jsonInt(source['roomid']) ?? 0 : 0;
      final tags = source is Map ? jsonInt(source['tags']) ?? 0 : 0;
      if (tags & 1 == 0 || partner <= 0 || '$partner' == roomId) return null;
      sourceRoom = '$partner';
    }
    final text = _clean(content['chatmsg']);
    if (text.isEmpty) return null;
    final sender = _id(packet['senderid']) ?? _id(content['senderid']);
    final sinfo = packet['sinfo'];
    final mystery = sinfo is Map && jsonInt(sinfo['ck']) == 1;
    final alias = mystery ? _text(sinfo['ckid']) : null;
    final level = _positive(content['senderrichlevelV2']) ?? _positive(content['senderrichlevel']);
    final ext = _extension(packet['ext']);
    final badge = _badge(ext);
    final messageId = _text(packet['msgId']);
    final seq = jsonInt(content['seq']) ?? 0;
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _clean(content['sendername']),
      userId: alias ?? sender ?? '',
      message: text,
      color: textColor(ext, mystery: mystery),
      userLevel: level == null ? '' : '$level',
      fansName: badge?.name ?? '',
      fansLevel: badge == null ? '' : '${badge.level}',
      messageId: messageId.isNotEmpty
          ? messageId
          : sender != null && seq > 0
          ? '$sender:$seq'
          : '',
      sentAt: _time(packet['time']),
      sourceRoomId: sourceRoom,
    );
  }

  /// The audience of room [roomId] (`HEAT_NUM` with `actionId`
  /// `roomAuNumber`, the page's `ViewerHeat`, about every minute): `count`,
  /// the viewers now (the lists' `viewerNum`), and `visited`, the viewers of
  /// this broadcast so far (the page: “看过：本场累计 N 人”). `hot`, the page's
  /// 热度, is not the lists' `hot` and is not reported.
  static List<LiveMessage> audience(Map<String, Object?> packet, {required String roomId}) {
    final content = packet['content'];
    if (content is! Map || content['actionId'] != 'roomAuNumber') return const [];
    final room = jsonInt(packet['roomid']) ?? 0;
    if (room != 0 && '$room' != roomId) return const [];
    final data = content['data'];
    if (data is! Map) return const [];
    return [
      for (final (key, kind) in const [
        ('count', LiveAudienceMetricKind.onlineViewers),
        ('visited', LiveAudienceMetricKind.totalViewers),
      ])
        if (jsonCount(data[key]) case final value?)
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: LiveAudienceUpdate(kind: kind, value: value),
          ),
    ];
  }

  /// The orange of a chat text the page highlights (`#ff9900`).
  static const LiveMessageColor highlightColor = LiveMessageColor(0xff, 0x99, 0x00);

  /// The gold of a mystery guest's chat text (`#CC9900`).
  static const LiveMessageColor mysteryColor = LiveMessageColor(0xcc, 0x99, 0x00);

  /// The colour the page gives a chat text (`Fx.dealWithChatContentColor`
  /// of roomBase_a2fb4ce.js, called by the PublicChat module with the
  /// message's [ext]), with the fan-club switch on, as for every room this
  /// connects (`getCurSwitch()`: the room page's `new_fandom_club_switch` is
  /// `1,1` and the room is neither a channel nor a live room):
  ///
  /// - [highlightColor] when the fan-club level (`intimacyVo.level`) is
  ///   above 7, or the sender is a little guard (`littleGuard.l`) or a
  ///   guard (`userGuard.g`), read with JavaScript's truthiness;
  /// - [mysteryColor], over that, for a mystery guest ([mystery]: the page
  ///   sets `starvip.mysticUser` from `sinfo.ck`);
  /// - white otherwise, and whenever the message has no `ext` (the page
  ///   then has nothing to colour by).
  static LiveMessageColor textColor(Map<Object?, Object?>? ext, {required bool mystery}) {
    if (ext == null) return LiveMessageColor.white;
    if (mystery) return mysteryColor;
    final intimacy = ext['intimacyVo'];
    final littleGuard = ext['littleGuard'];
    final userGuard = ext['userGuard'];
    if ((intimacy is Map && _jsNumber(intimacy['level']) > 7) ||
        (littleGuard is Map && _jsTruthy(littleGuard['l'])) ||
        (userGuard is Map && _jsTruthy(userGuard['g']))) {
      return highlightColor;
    }
    return LiveMessageColor.white;
  }

  /// JavaScript's truthiness of a JSON value.
  static bool _jsTruthy(Object? value) => switch (value) {
    null => false,
    final bool flag => flag,
    final num number => number != 0 && !number.isNaN,
    final String text => text.isNotEmpty,
    _ => true,
  };

  /// A JSON value as JavaScript's `>` compares it with a number: numbers,
  /// numeric text (empty text is 0), booleans as 0 and 1; anything else
  /// never compares true (NaN).
  static double _jsNumber(Object? value) => switch (value) {
    null => 0,
    final num number => number.toDouble(),
    final bool flag => flag ? 1 : 0,
    final String text when text.trim().isEmpty => 0,
    final String text => double.tryParse(text.trim()) ?? double.nan,
    _ => double.nan,
  };

  /// The message's `ext` as the page reads it: a map, or the URL-encoded
  /// JSON of a JSON message. Null when it is missing or cannot be read.
  static Map<Object?, Object?>? _extension(Object? ext) {
    var value = ext;
    if (value is String) {
      if (value.isEmpty) return null;
      // decodeComponent throws an ArgumentError on a bad escape.
      if (_badEscape.hasMatch(value)) return null;
      try {
        value = jsonDecode(Uri.decodeComponent(value));
      } on FormatException {
        return null;
      }
    }
    return value is Map<Object?, Object?> ? value : null;
  }

  /// The fan badge the page shows (`dealWithNickName`): `intimacyVo` of the
  /// message's [ext].
  static ({String name, int level})? _badge(Map<Object?, Object?>? ext) {
    final intimacy = ext?['intimacyVo'];
    if (intimacy is! Map) return null;
    final level = jsonInt(intimacy['level']) ?? 0;
    final type = jsonInt(intimacy['type']) ?? 0;
    final name = _clean(intimacy['nameplate']);
    if (level <= 0 || type < 1 || type > 4 || jsonInt(intimacy['lightUp']) != 1 || name.isEmpty) return null;
    return (name: name, level: level);
  }

  static final RegExp _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  static final RegExp _marks = RegExp(r'[\u2027-\u202E]');

  static String _clean(Object? value) => _text(value).replaceAll(_marks, '').trim();

  static String _text(Object? value) => switch (value) {
    final String text => text,
    final int number => '$number',
    _ => '',
  };

  static String? _id(Object? value) => switch (jsonInt(value)) {
    final int id when id > 0 => '$id',
    _ => null,
  };

  static int? _positive(Object? value) => switch (jsonInt(value)) {
    final int number when number > 0 => number,
    _ => null,
  };

  static DateTime? _time(Object? value) {
    final time = jsonInt(value) ?? 0;
    if (time <= 0) return null;
    final milliseconds = time > 100000000000 ? time : time * 1000;
    return milliseconds > _maxEpochMilliseconds ? null : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  /// [content] as the envelope's `compression` says: 1 gzip, 2 snappy, else
  /// as it is (the page's `unCompress`). At most [maxContentBytes].
  static Uint8List _uncompress(Uint8List content, int compression) {
    switch (compression) {
      case 1:
        final sink = _BoundedSink(maxContentBytes);
        try {
          GZipCodec().decoder.startChunkedConversion(sink)
            ..add(content)
            ..close();
        } on FormatException {
          rethrow;
        } on Object catch (error) {
          throw FormatException('Kugou chat gzip: $error');
        }
        return sink.bytes.takeBytes();
      case 2:
        return snappy(content);
    }
    return content;
  }

  /// A raw snappy block (the page's snappyjs `uncompressToBuffer`): the
  /// length as a varint, then literals and copies. At most
  /// [maxContentBytes]; anything malformed is a [FormatException].
  static Uint8List snappy(Uint8List input) {
    var position = 0;
    var length = 0;
    for (var shift = 0; ; shift += 7) {
      if (shift > 28 || position >= input.length) throw const FormatException('Snappy length');
      final byte = input[position++];
      length |= (byte & 0x7F) << shift;
      if (byte < 0x80) break;
    }
    if (length > maxContentBytes) throw const FormatException('Snappy block too large');
    final output = Uint8List(length);
    var written = 0;
    int take(int count) {
      if (position + count > input.length) throw const FormatException('Snappy block truncated');
      var value = 0;
      for (var i = 0; i < count; i++) {
        value |= input[position + i] << (8 * i);
      }
      position += count;
      return value;
    }

    while (position < input.length) {
      final tag = input[position++];
      final int size;
      if (tag & 3 == 0) {
        final short = (tag >> 2) + 1;
        size = short > 60 ? take(short - 60) + 1 : short;
        if (position + size > input.length || written + size > length) {
          throw const FormatException('Snappy literal out of range');
        }
        output.setRange(written, written + size, input, position);
        position += size;
        written += size;
        continue;
      }
      final int offset;
      switch (tag & 3) {
        case 1:
          size = 4 + ((tag >> 2) & 7);
          offset = ((tag >> 5) << 8) | take(1);
        case 2:
          size = (tag >> 2) + 1;
          offset = take(2);
        default:
          size = (tag >> 2) + 1;
          offset = take(4);
      }
      if (offset == 0 || offset > written || written + size > length) {
        throw const FormatException('Snappy copy out of range');
      }
      for (var i = 0; i < size; i++) {
        output[written] = output[written - offset];
        written++;
      }
    }
    if (written != length) throw const FormatException('Snappy length mismatch');
    return output;
  }
}

final class _BoundedSink implements Sink<List<int>> {
  new(this.limit);

  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (chunk.length > limit - bytes.length) throw FormatException('Kugou chat message exceeds $limit bytes');
    bytes.add(chunk);
  }

  @override
  void close() {}
}

/// Kugou Live's chat connection (new in v4: 3.x had none, the 29-5
/// upgrade), on the WebSocket runtime, as the website's room page joins
/// anonymously:
///
/// - Before the first socket it asks the scheduler for the room's hosts and
///   token (three tries, 1.5 s and 4.5 s apart, the page's backoff); a
///   refusal or three failures end with [DanmakuCloseReason.connectionFailed].
/// - Every socket logs in (201; 2201 with the last session once the room has
///   been joined) and is joined when the status frame accepts it; the next
///   host is tried when that takes 10 s.
/// - The token is kept for the next sockets, as the page keeps it, until it
///   is older than the scheduler's `age` (5 minutes), was refused (622) or
///   went on a socket that closed (or timed out) before the server answered
///   its login: then the handshake asks the scheduler again first. A failed request fails the handshake (the
///   runtime's backoff and its eight attempts); a refusal ends the
///   connection.
/// - Refused logins reconnect; more than three in a row end the connection.
/// - The binary heartbeat goes every 10 s; the server answers each.
/// - Chat of the room and its audience are reported; gifts are not, but
///   acknowledged as the page does.
///
/// The app registers it as `SiteIds.kugouLive: () =>
/// KugouLiveDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `KugouLiveSite` (proxy route by the platform id) and its proxy
/// policy for the socket.
final class KugouLiveDanmakuConnection extends DanmakuSocketConnection<KugouLiveDanmakuArgs> {
  /// Creates the connection. [http] asks the scheduler; [proxy] routes the
  /// socket; [connector] replaces `dart:io`'s handshake, [policy] the
  /// timing, [retryDelays] the waits between a start's scheduler requests,
  /// [now] the clock (the scheduler's `clienttime` and the token's age) and
  /// [random] the login's session and device ids (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    List<Duration> retryDelays = dispatchRetryDelays,
    DateTime Function()? now,
    Random? random,
  }) => KugouLiveDanmakuConnection._(
    _Handshake(http, connector ?? connectIoSocket, now ?? DateTime.now),
    random ?? Random.secure(),
    retryDelays,
    proxy: proxy,
    policy: policy,
  );

  new _(this._handshake, this._random, this._retryDelays, {required super.proxy, required super.policy})
    : super(site: SiteIds.kugouLive, connector: _handshake.call);

  /// The platform's timing: the 10 s heartbeat and the 10 s login limit;
  /// the runtime's defaults otherwise (the silence watchdog at 90 s).
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: KugouLiveDanmakuProtocol.heartbeatInterval,
    joinTimeout: KugouLiveDanmakuProtocol.joinTimeout,
  );

  /// The page's waits before the second and third scheduler request of a
  /// start (`1500 × (2^n − 1)` ms).
  static const List<Duration> dispatchRetryDelays = [Duration(milliseconds: 1500), Duration(milliseconds: 4500)];

  final _Handshake _handshake;
  final Random _random;
  final List<Duration> _retryDelays;

  @override
  @protected
  Future<DanmakuSocketTarget> target(KugouLiveDanmakuArgs args, DanmakuRun run) async {
    final roomId = KugouLiveDanmakuProtocol.checkedRoom(args.roomId);
    if (roomId == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'Not a Kugou Live room');
    }
    final chat = _handshake.chat = _Chat(
      run,
      roomId,
      sid: KugouLiveDanmakuProtocol.uuid(_random),
      deviceNo: KugouLiveDanmakuProtocol.uuid(_random),
    );
    Object? failure;
    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      if (attempt > 0 && !await run.delay(_retryDelays[attempt - 1])) break;
      try {
        await _handshake.renew(chat, timeout: policy.connectTimeout, endOnRefusal: false);
        failure = null;
        break;
      } on KugouLiveDispatchRefusal catch (refusal) {
        throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: '$refusal');
      } on Object catch (error) {
        if (!run.isActive) rethrow;
        failure = error;
      }
    }
    final grant = chat.grant;
    if (failure != null || grant == null) {
      throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'dispatch: ${failure ?? 'stopped'}');
    }
    return DanmakuSocketTarget(endpoints: grant.endpoints, headers: KugouLiveDanmakuProtocol.socketHeaders);
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _handshake.chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final chat = _of(session);
    final grant = chat?.grant;
    if (chat == null || grant == null) return;
    chat
      ..sent = true
      ..answered = false;
    session.send(
      KugouLiveDanmakuProtocol.login(
        roomId: chat.roomId,
        token: grant.token,
        sid: chat.sid,
        deviceNo: chat.deviceNo,
        sessionId: chat.sessionId,
        again: chat.everJoined,
      ),
    );
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = KugouLiveDanmakuProtocol.decode(data, roomId: chat.roomId);
    if (frame.ack case final ack?) session.send(ack);
    if (frame.refusal case final refusal?) {
      _refused(session, chat, refusal);
      return;
    }
    if (frame.joined) {
      chat
        ..answered = true
        ..everJoined = true
        ..refusals = 0
        ..sessionId = frame.sessionId ?? chat.sessionId;
      session.ready();
    }
    for (final message in frame.messages) {
      if (!session.isActive) return;
      session.message(message);
    }
  }

  /// A refused login: the token is dropped when the server refused it, then
  /// a new socket; more than [KugouLiveDanmakuProtocol.maxRefusals] in a row
  /// end the connection.
  void _refused(DanmakuSocketSession session, _Chat chat, KugouLiveChatRefusal refusal) {
    if (refusal.tokenRejected) {
      chat.grant = null;
    } else {
      chat.answered = true;
    }
    if (++chat.refusals > KugouLiveDanmakuProtocol.maxRefusals) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: $refusal');
      return;
    }
    session.reconnect();
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => KugouLiveDanmakuProtocol.heartbeat();

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.dispose();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [KugouLiveDanmakuConnection]: asks the scheduler
/// again first when the run's token is spent, then connects.
final class _Handshake {
  new(this._http, this._connect, this._now);

  final LiveHttp _http;
  final SocketConnector _connect;
  final DateTime Function() _now;

  /// The current run's chat.
  _Chat? chat;

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    final chat = this.chat;
    if (chat == null || !chat.run.isActive) throw StateError('The chat was closed');
    if (!_usable(chat)) await renew(chat, timeout: connectTimeout);
    // The scheduler hands every room the same hosts; a host it no longer
    // lists gives way to its first.
    final endpoints = chat.grant!.endpoints;
    return await _connect(
      endpoints.contains(endpoint) ? endpoint : endpoints.first,
      headers: headers,
      protocols: protocols,
      route: route,
      connectTimeout: connectTimeout,
    );
  }

  /// Whether [chat]'s token may go on a new socket: there is one, it is
  /// younger than its `age`, and the server answered the last login it
  /// went on (a join, or a refusal that was not about the token).
  bool _usable(_Chat chat) {
    final grant = chat.grant;
    if (grant == null || (chat.sent && !chat.answered)) return false;
    final age = _now().difference(chat.grantedAt);
    return age >= Duration.zero && age < grant.age;
  }

  /// Asks the scheduler for [chat]'s room. A refusal ends the run when
  /// [endOnRefusal] (a handshake; the start turns it into its failure);
  /// every failure is thrown.
  Future<void> renew(_Chat chat, {required Duration timeout, bool endOnRefusal = true}) async {
    final response = await _http.send(
      KugouLiveDanmakuProtocol.dispatchRequest(chat.roomId, now: _now(), timeout: timeout, cancel: chat.cancel),
    );
    final KugouLiveChatGrant grant;
    try {
      grant = KugouLiveDanmakuProtocol.grant(response);
    } on KugouLiveDispatchRefusal catch (refusal) {
      if (endOnRefusal) chat.run.closed(DanmakuCloseReason.connectionFailed, detail: '$refusal');
      rethrow;
    }
    if (!chat.run.isActive) throw StateError('The chat was closed');
    chat
      ..grant = grant
      ..grantedAt = _now()
      ..sent = false
      ..answered = false;
  }
}

/// One run's chat: the room, the page's ids, the token and the state of the
/// current socket.
final class _Chat {
  new(this.run, this.roomId, {required this.sid, required this.deviceNo}) {
    unawaited(run.ended.then((_) => dispose()));
  }

  final DanmakuRun run;
  final String roomId;

  /// The page's `mySocket.sid`, one per visit.
  final String sid;

  /// The page's stored `device`.
  final String deviceNo;

  final CancelToken cancel = CancelToken();

  /// The scheduler's grant; null when the token was refused.
  KugouLiveChatGrant? grant;

  /// When [grant] was received.
  DateTime grantedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether [grant]'s token went on a socket.
  bool sent = false;

  /// Whether the server answered the login of the socket it last went on
  /// (a join, or a refusal that was not about the token).
  bool answered = false;

  /// Whether the room was joined in this run: later sockets log in again
  /// (2201) with [sessionId].
  bool everJoined = false;

  /// The last accepted login's `socsid`.
  String sessionId = '';

  /// Logins refused in a row.
  int refusals = 0;

  void dispose() => cancel.cancel();
}
