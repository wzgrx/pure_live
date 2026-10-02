import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one LOOK chat frame held ([LookLiveDanmakuProtocol.decode]).
@immutable
final class LookLiveDanmakuFrame {
  /// Creates the result.
  const new({
    this.messages = const [],
    this.replies = const [],
    this.opened = false,
    this.joined = false,
    this.refusal,
    this.kicked,
    this.dropped = false,
  });

  /// Chat, in order.
  final List<LiveMessage> messages;

  /// What to send back at once, in order: the echo of a socket.io heartbeat
  /// (`2::`) and the ack of a message that asked for one (`6:::<id>`).
  final List<String> replies;

  /// socket.io's connect packet (`1::`): the session is open, the client
  /// logs in to the chatroom now.
  final bool opened;

  /// The chatroom accepted the login (command 13-2 with `code` 200).
  final bool joined;

  /// The chatroom refused the login: its `code`; null otherwise.
  final int? refusal;

  /// The chatroom put this client out (command 13-3): the reason
  /// ([LookLiveDanmakuProtocol.kickReasons]); null otherwise.
  final int? kicked;

  /// The server ended the socket.io session (`0::`) or reported an error
  /// (`7:::`): the socket is to be replaced.
  final bool dropped;
}

/// The anonymous identity one connection logs in with, as the NIM SDK
/// makes it for a guest (`nimanon_` and 32 hex digits, a device id and an
/// SDK session of 32 hex digits each).
@immutable
final class LookLiveGuest {
  /// Creates the identity.
  const new({required this.account, required this.deviceId, required this.session});

  /// A new identity from [random] (the SDK's `guid()`: 32 lower-case hex
  /// digits).
  factory random(Random random) {
    String guid() => [for (var i = 0; i < 8; i++) random.nextInt(0x10000).toRadixString(16).padLeft(4, '0')].join();
    return LookLiveGuest(account: 'nimanon_${guid()}', deviceId: guid(), session: guid());
  }

  /// The chatroom account (`nimanon_…`).
  final String account;

  /// The device id.
  final String deviceId;

  /// The SDK session.
  final String session;
}

/// LOOK's chat, without I/O (docs/D-弹幕/D01-平台弹幕协议/D01.29-LOOK直播弹幕/record.md): a NetEase
/// Yunxin (网易云信) chatroom, joined anonymously the way LOOK's website does
/// it with the Yunxin web SDK 5.0.1 (`look.163.com`'s `Chatroom` chunk).
///
/// - The room's chat servers come from [LookLiveApi.chatAddressPath]
///   (`host:port` each); the website sends no token for a guest.
/// - Every socket is socket.io 0.9: a GET of `/socket.io/1/?t=<ms>` answers
///   `<sid>:<heartbeat>:<close>:<transports>`, then the WebSocket opens at
///   `/socket.io/1/websocket/<sid>`. The server sends `1::` when the session
///   is open and `2::` every 25 s, which the client echoes; data travels in
///   message packets (`3:::<data>`).
/// - The data is the SDK's JSON: commands `{"SID", "CID", "SER", "Q"}`
///   (service, command, serial, typed parameters), answers `{"sid", "cid",
///   "ser", "code", "r"}`. Properties go by number (the SDK's
///   `serializeMap`).
/// - The client logs in anonymously to the chatroom (13-2) and sends the
///   link heartbeat (1-2) every 3 minutes. Chatroom messages come as
///   notifications (4-10) wrapping 13-7.
/// - A chat line is a text message (type 0) whose `custom` JSON has
///   `bizName` `iplay` and the sender in `content.user` (LOOK's
///   `ignoreMsgs` and the Live chunk's `getMsgElement`).
abstract final class LookLiveDanmakuProtocol {
  /// LOOK's Yunxin app key: the website's public `online.appKey` (app
  /// chunk, module `d4h+`).
  static const String appKey = '3a6a3e48f6854dfa4e4464f3bdaec3b4';

  /// The SDK's `info.sdkVersion` (web SDK 5.0.1).
  static const String sdkVersion = '47';

  /// The SDK's `info.protocolVersion`.
  static const int protocolVersion = 1;

  /// What the SDK reports as the system and browser (`platform.js`) on the
  /// desktop Chrome the handshake's user agent names; the server does not
  /// check them.
  static const String os = 'Windows 10 64-bit';

  /// See [os].
  static const String browser = 'Chrome 140.0.0.0';

  /// The chatroom name of a guest on LOOK's room page (`chatroomNick`).
  static const String guestNick = '匿名用户';

  /// The chatroom avatar of a guest (the SDK's default, one space).
  static const String guestAvatar = ' ';

  /// The watchdog's tick: the socket is replaced after three silent ticks
  /// (90 s, the handshake's heartbeat timeout; the server sends `2::` every
  /// 25 s).
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// Ticks per link heartbeat: 6 × 30 s, the SDK's `heartbeatInterval` of
  /// 180 s.
  static const int ticksPerHeartbeat = 6;

  /// How long the login may take after the socket opened (the SDK waits
  /// 42 s; the answer came within 0.2 s).
  static const Duration joinTimeout = Duration(seconds: 10);

  /// Chat server requests per connection: the website asks again once,
  /// 2 s after a failure.
  static const int addressAttempts = 2;

  /// See [addressAttempts].
  static const Duration addressRetryDelay = Duration(seconds: 2);

  /// Refused logins in a row that are retried (codes the SDK names as
  /// passing: [retriedRefusals]); the next one ends the connection.
  static const int maxRefusals = 3;

  /// Login refusals worth another socket: 408 timeout, 415 no chatroom
  /// server available, 500 server error, 503 busy (the SDK's error table).
  /// Any other code (403, 404 chatroom not found, 13002 chatroom closed, …)
  /// ends the connection.
  static const Set<int> retriedRefusals = {408, 415, 500, 503};

  /// The SDK's kick reasons (`kickedReasons`): 1 the chatroom closed, 2 put
  /// out by the host or a manager, 3 the same account elsewhere, 4 silently
  /// (reconnect), 5 blacklisted.
  static const List<String> kickReasons = [
    '',
    'chatroomClosed',
    'managerKick',
    'samePlatformKick',
    'silentlyKick',
    'blacked',
  ];

  /// The kick the SDK answers by reconnecting (`silentlyKick`).
  static const int silentKick = 4;

  /// Handshake headers of the socket: the website's origin and the
  /// platform's user agent (LOOK's requests use 3.x's `Mozilla/5.0`).
  static const Map<String, String> socketHeaders = {'origin': LookLiveApi.origin, 'user-agent': LookLiveApi.userAgent};

  /// socket.io's heartbeat packet, echoed as it arrives.
  static const String socketHeartbeat = '2::';

  /// The link heartbeat (service 1, command 2; serial 0 as the SDK sends
  /// it).
  static const String heartbeat = '3:::{"SID":1,"CID":2,"SER":0}';

  /// The largest chatroom id that stays exact as a JSON number in the
  /// website (2^53 − 1).
  static const int _maxChatroomId = 9007199254740991;

  /// Largest [DateTime], in milliseconds.
  static const int _maxEpochMillis = 8640000000000000;

  static final RegExp _chatroomId = RegExp(r'^[1-9][0-9]{0,15}$');
  static final RegExp _sessionId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final RegExp _packet = RegExp(r'^([^:]+):([0-9]+)?(\+)?:([^:]+)?:?([\s\S]*)$');

  /// [args] trimmed if they name a chat: a room number
  /// ([LookLiveApi.isRoomNumber]) and a chatroom id that the login can
  /// carry as a number; null otherwise.
  static LookLiveDanmakuArgs? checked(LookLiveDanmakuArgs args) {
    final roomId = args.roomId.trim();
    final chatroomId = args.chatroomId.trim();
    if (!LookLiveApi.isRoomNumber(roomId) ||
        !_chatroomId.hasMatch(chatroomId) ||
        int.parse(chatroomId) > _maxChatroomId) {
      return null;
    }
    return LookLiveDanmakuArgs(roomId: roomId, chatroomId: chatroomId, anonymousMode: args.anonymousMode);
  }

  /// The chat server request of [roomId], as the adapter sends every LOOK
  /// request (`LookLiveSite`): a form POST of the `weapi` envelope of
  /// [LookLiveApi.chatAddressPayload] to [LookLiveApi.chatAddressPath], 3.x's
  /// headers, no redirect followed, sent as `looklive` (its proxy route).
  static LiveRequest addressRequest(String roomId, {Duration timeout = defaultRequestTimeout, CancelToken? cancel}) =>
      LiveRequest(
        site: SiteIds.lookLive,
        url: Uri.parse('${LookLiveApi.apiOrigin}${LookLiveApi.chatAddressPath}'),
        method: 'POST',
        headers: LookLiveApi.requestHeaders,
        body: utf8.encode(LookLiveApi.formBody(LookLiveApi.chatAddressPayload(roomId))),
        followRedirects: false,
        timeout: timeout,
        cancel: cancel,
      );

  /// The socket of each chat server (`host:port`):
  /// `wss://<host>:<port>/socket.io/1/websocket/`, to which the handshake
  /// appends the session id. The SDK makes every address `https://` (its
  /// `secure` default) and tries them in order.
  static List<Uri> endpoints(List<String> addresses) => [
    for (final address in addresses) Uri.parse('wss://$address/socket.io/1/websocket/'),
  ];

  /// The socket.io handshake of [endpoint] at [now]: a GET of
  /// `https://<host>:<port>/socket.io/1/?t=<ms>` (`http` for a `ws`
  /// endpoint) with the website's origin, room [roomId]'s page as referer
  /// and the platform's user agent, as the website's XHR sends it.
  static LiveRequest handshakeRequest(
    Uri endpoint, {
    required String roomId,
    required DateTime now,
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => LiveRequest(
    site: SiteIds.lookLive,
    url: endpoint.replace(
      scheme: endpoint.isScheme('ws') ? 'http' : 'https',
      path: '/socket.io/1/',
      query: 't=${now.millisecondsSinceEpoch}',
    ),
    headers: {'origin': LookLiveApi.origin, 'referer': LookLiveApi.link(roomId), 'user-agent': LookLiveApi.userAgent},
    followRedirects: false,
    timeout: timeout,
    cancel: cancel,
  );

  /// The session id of a handshake [response]
  /// (`<sid>:<heartbeat>:<close>:<transports>`). A status other than 200,
  /// an id that does not fit a URL path segment, or transports without
  /// `websocket` throw [FormatException].
  static String sessionOf(LiveResponse response) {
    if (response.status != 200) throw FormatException('socket.io handshake: HTTP ${response.status}');
    final parts = response.text.trim().split(':');
    if (parts.length < 4 || !_sessionId.hasMatch(parts.first)) {
      throw FormatException('socket.io handshake: ${_snippet(response.text)}');
    }
    if (!parts[3].split(',').contains('websocket')) {
      throw FormatException('socket.io handshake: no websocket in ${_snippet(parts[3])}');
    }
    return parts.first;
  }

  /// The socket of [endpoint] for session [sessionId].
  static Uri socketUrl(Uri endpoint, String sessionId) => endpoint.replace(path: '${endpoint.path}$sessionId');

  /// The anonymous chatroom login (service 13, command 2) with serial
  /// [serial] for [chatroomId] as [guest], as the SDK assembles it
  /// (`assembleLogin`, `assembleIMLogin`): type 1, the chatroom login
  /// (app key, account, device, chatroom, `appLogin`, the guest's name and
  /// avatar, session, `isAnonymous` 1) and the IM login (system, SDK
  /// version, `appLogin`, protocol version, device, app key, account,
  /// browser, session, an empty token). [again] is a login after a
  /// reconnect: the chatroom `appLogin` is 1 and the IM one 0 (0 and 1 the
  /// first time).
  static String login({
    required String chatroomId,
    required LookLiveGuest guest,
    required int serial,
    bool again = false,
  }) {
    final chatroom = <String, Object>{
      '1': appKey,
      '2': guest.account,
      '3': guest.deviceId,
      '5': int.parse(chatroomId),
      '8': again ? 1 : 0,
      '20': guestNick,
      '21': guestAvatar,
      '26': guest.session,
      '38': 1,
    };
    final im = <String, Object>{
      '4': os,
      '6': sdkVersion,
      '8': again ? 0 : 1,
      '9': protocolVersion,
      '13': guest.deviceId,
      '18': appKey,
      '19': guest.account,
      '24': browser,
      '26': guest.session,
      '1000': '',
    };
    final command = {
      'SID': 13,
      'CID': 2,
      'SER': serial,
      'Q': [
        {'t': 'byte', 'v': 1},
        {'t': 'Property', 'v': chatroom},
        {'t': 'Property', 'v': im},
      ],
    };
    return '3:::${jsonEncode(command)}';
  }

  /// One frame (text, or UTF-8 bytes): one socket.io packet, or several
  /// framed as `\ufffd<length>\ufffd<packet>…` (socket.io 0.9's
  /// `decodePayload`).
  ///
  /// - `1::` opens the session; `2::` is echoed; `0::` and `7:::…` drop the
  ///   socket; a message packet with an id and no `+` is acked (`6:::<id>`).
  /// - A message's data is an SDK answer: the login's (13-2: joined, or its
  ///   refusal code), a kick (13-3), a chatroom message (13-7), or a
  ///   notification (4-10, 4-11) wrapping one in `r[1]` (`headerPacket`,
  ///   `body`). Chat lines ([chat]) are reported; with [anonymousMode] the
  ///   names are masked as the room page does.
  /// - Anything unreadable is skipped.
  static LookLiveDanmakuFrame decode(Object? data, {bool anonymousMode = false}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const LookLiveDanmakuFrame();
    final messages = <LiveMessage>[];
    final replies = <String>[];
    var opened = false;
    var joined = false;
    var dropped = false;
    int? refusal;
    int? kicked;
    for (final packet in _payload(text)) {
      final match = _packet.firstMatch(packet);
      if (match == null || (match.group(4) ?? '').isNotEmpty) continue;
      switch (match.group(1)) {
        case '0' || '7':
          dropped = true;
        case '1':
          opened = true;
        case '2':
          replies.add(socketHeartbeat);
        case '3':
          if (match.group(2) case final id? when match.group(3) == null) replies.add('6:::$id');
          final answer = _answer(match.group(5) ?? '');
          if (answer == null) continue;
          switch ((answer.sid, answer.cid)) {
            case (13, 2):
              if (answer.code == 200) {
                joined = true;
              } else {
                refusal ??= answer.code ?? 0;
              }
            case (13, 3) when answer.code == 200:
              kicked ??= _int(answer.body.firstOrNull) ?? 0;
            case (13, 7) when answer.code == 200:
              if (chat(answer.body.firstOrNull, anonymousMode: anonymousMode) case final message?) {
                messages.add(message);
              }
          }
      }
    }
    return LookLiveDanmakuFrame(
      messages: messages,
      replies: replies,
      opened: opened,
      joined: joined,
      refusal: refusal,
      kicked: kicked,
      dropped: dropped,
    );
  }

  /// The packets of a frame: one, or those of a `\ufffd`-framed payload
  /// (lengths in UTF-16 units, as in JavaScript).
  static List<String> _payload(String text) {
    if (!text.startsWith('\ufffd')) return [text];
    final packets = <String>[];
    var index = 1;
    while (index < text.length) {
      final end = text.indexOf('\ufffd', index);
      if (end < 0) break;
      final length = int.tryParse(text.substring(index, end));
      if (length == null || length < 0 || end + 1 + length > text.length) break;
      packets.add(text.substring(end + 1, end + 1 + length));
      index = end + 1 + length + 1;
    }
    return packets;
  }

  /// An SDK answer as its service, command, code and response list; a
  /// notification (4-10, 4-11) as the command it wraps
  /// (`r[1].headerPacket`) with its `body` (the SDK's `parseResponse`).
  static ({int sid, int cid, int? code, List<Object?> body})? _answer(String data) {
    final Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final sid = _int(json['sid']);
    final cid = _int(json['cid']);
    final r = json['r'];
    if (sid == null || cid == null) return null;
    final code = _int(json['code']);
    if (sid == 4 && (cid == 10 || cid == 11)) {
      final wrapped = r is List && r.length > 1 ? r[1] : null;
      if (wrapped is! Map) return null;
      final header = wrapped['headerPacket'];
      final body = wrapped['body'];
      if (header is! Map || body is! List) return null;
      final innerSid = _int(header['sid']);
      final innerCid = _int(header['cid']);
      if (innerSid == null || innerCid == null) return null;
      return (sid: innerSid, cid: innerCid, code: code, body: body);
    }
    return (sid: sid, cid: cid, code: code, body: r is List ? r : const []);
  }

  /// A chatroom message (its numbered properties) as white chat, or null
  /// when it is not a chat line the website shows:
  ///
  /// - a text message (`2` is 0) with text (`3`, the SDK's `attach`;
  ///   trimmed) and a `custom` (`4`) JSON object whose `bizName` is `iplay`
  ///   (LOOK's `ignoreMsgs`; a short-keyed custom, `sp` 1, is expanded as
  ///   its `parseIM` does), not held back for a risk level
  ///   (`content.commonCtrl.riskLevelKey`, never granted to a guest) and
  ///   with a sender (`content.user`): the text;
  /// - or LOOK's emoji message (a custom message, `2` is 100, from
  ///   `musiclive_server`, `custom.type` 2601): the emoji's name in
  ///   brackets (`content.emoji`, a JSON text with `name`), as the room page
  ///   writes it next to the image.
  ///
  /// The sender is `content.user`: the name `nickname` (else `nickName`),
  /// masked to its first character and `***` with [anonymousMode], the id
  /// `userId` (else the message's `from`, `21`), the level `liveLevel` and
  /// the fan club's `fanClubLevel` and `fanClubName` (else those of
  /// `fanClubInfo`). The message id is `idClient` (`1`), the time `time`
  /// (`20`, milliseconds).
  static LiveMessage? chat(Object? message, {bool anonymousMode = false}) {
    if (message is! Map) return null;
    final type = _int(message['2']);
    final custom = _custom(message['4']);
    if (custom == null) return null;
    final String text;
    switch (type) {
      case 0:
        text = _text(message['3']);
        if (text.isEmpty || custom['bizName'] != 'iplay') return null;
      case 100 when message['21'] == 'musiclive_server' && _int(custom['type']) == 2601:
        final content = custom['content'];
        final emoji = content is Map ? _custom(content['emoji']) : null;
        final name = emoji == null ? '' : _text(emoji['name']);
        if (name.isEmpty) return null;
        text = '[$name]';
      default:
        return null;
    }
    final content = custom['content'];
    if (content is! Map) return null;
    final control = content['commonCtrl'];
    if (control is Map && _held(control['riskLevelKey'])) return null;
    final user = content['user'];
    if (user is! Map) return null;
    var name = _text(user['nickname']);
    if (name.isEmpty) name = _text(user['nickName']);
    if (anonymousMode && name.isNotEmpty) name = '${String.fromCharCode(name.runes.first)}***';
    var userId = _text(user['userId']);
    if (userId.isEmpty) userId = _text(message['21']);
    final fanClub = switch (user['fanClubInfo']) {
      final Map<Object?, Object?> info => info,
      _ => const <Object?, Object?>{},
    };
    final level = _level(user['liveLevel']);
    var fansLevel = _level(user['fanClubLevel']);
    if (fansLevel.isEmpty) fansLevel = _level(fanClub['fanClubLevel']);
    var fansName = _text(user['fanClubName']);
    if (fansName.isEmpty) fansName = _text(fanClub['fanClubName']);
    final time = _int(message['20']);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name,
      userId: userId,
      message: text,
      color: LiveMessageColor.white,
      userLevel: level,
      fansLevel: fansLevel,
      fansName: fansName,
      messageId: _text(message['1']),
      sentAt: time != null && time > 0 && time <= _maxEpochMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null,
    );
  }

  /// Whether a message is held back for a risk level the viewer lacks
  /// (LOOK's `onmsgs`: a truthy `riskLevelKey` not in the viewer's
  /// `riskLevel`, which is empty for a guest).
  static bool _held(Object? key) => switch (key) {
    null || false || '' => false,
    final num number => number != 0,
    _ => true,
  };

  /// A `custom` JSON text as an object, expanded when short-keyed (`sp`
  /// 1); null when it is not an object.
  static Map<Object?, Object?>? _custom(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final Object? json;
    try {
      json = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    return json['sp'] == 1 ? _expandMap(json, _shortKeys) : json;
  }

  /// LOOK's short keys (`encodeIM`'s table, app chunk module `NomM`):
  /// each short key to its name and, for an object, its own table. The URL
  /// fields' host completion is left out: no image is read.
  static const Map<String, (String, Map<String, Object>?)> _shortKeys = {
    'c': (
      'content',
      {
        'ir': ('isRoomManager', null),
        'md': ('msgDisplayInfo', {'f': ('fontInfoId', null), 'b': ('bubbleInfoId', null)}),
        'u': (
          'user',
          {
            'a': ('avatarUrl', null),
            'fa': ('fanClubAnchorId', null),
            'fcl': ('fanClubLevel', null),
            'fcn': ('fanClubName', null),
            'fcp': ('fanClubPrivilege', null),
            'fct': ('fanClubType', null),
            'fcnp': (
              'fanClubNameplate',
              {
                'fa': ('fanClubAnchorId', null),
                'fcl': ('fanClubLevel', null),
                'fcp': ('fanClubPrivilege', null),
                'fct': ('fanClubType', null),
              },
            ),
            'g': ('gender', null),
            'l': ('liveLevel', null),
            'n': ('nickname', null),
            'i': ('userId', null),
            'ni': ('nobleInfo', {'l': ('nobleLevel', null)}),
            'nu': ('numen', {'i': ('numenId', null), 's': ('status', null)}),
            'h': (
              'headFrameInfo',
              {'b': ('bigImgUrl', null), 'c': ('configId', null), 'e': ('endTime', null), 's': ('smallImgUrl', null)},
            ),
            'ut': (
              'userTitle',
              {
                'o': ('isOn', null),
                'c': ('configId', null),
                'e': ('endTime', null),
                'r': ('resourceUrl', null),
                'v': ('visibleType', null),
              },
            ),
            'uut': (
              'unionUserTitle',
              {'t': ('titleType', null), 'e': ('expireTime', null), 's': ('styleText', null), 'u': ('unionId', null)},
            ),
          },
        ),
        'uhc': (
          'userHonorsConfig',
          {
            'i': ('id', null),
            'a': ('appearanceType', null),
            'b': ('backgroundUrl', null),
            'bm': ('bigMedalUrl', null),
            'm': ('medalUrl', null),
            'n': ('name', null),
          },
        ),
        'a': ('attachments', null),
      },
    ),
  };

  /// [value] with its keys renamed by [table] (LOOK's `parseIM`): a key not
  /// in the table keeps its name, and so do the keys below it.
  static Object? _expand(Object? value, Map<String, Object>? table) => switch (value) {
    final List<Object?> list => [for (final item in list) _expand(item, table)],
    final Map<Object?, Object?> map => _expandMap(map, table),
    _ => value,
  };

  static Map<Object?, Object?> _expandMap(Map<Object?, Object?> value, Map<String, Object>? table) =>
      <Object?, Object?>{
        for (final MapEntry(:key, value: item) in value.entries)
          if (table?[key] case (final String name, final Map<String, Object>? below))
            name: _expand(item, below)
          else
            key: _expand(item, null),
      };

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text.trim()),
    _ => null,
  };

  static String _text(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => '$number',
    _ => '',
  };

  /// A positive level as text, else ''.
  static String _level(Object? value) => switch (_int(value)) {
    final int level when level > 0 => '$level',
    _ => '',
  };

  static String _snippet(String text) {
    final trimmed = text.trim();
    return trimmed.length <= 80 ? trimmed : '${trimmed.substring(0, 80)}…';
  }
}

/// LOOK's chat connection (new in v4: 3.x had none, the 32-7 upgrade), on
/// the WebSocket runtime: an anonymous guest in the room's Yunxin chatroom,
/// as LOOK's website joins it.
///
/// - At every [connect] the room's chat servers are asked once
///   ([LookLiveApi.chatAddressPath]), and once more 2 s later when that
///   fails, as the website does. A room that is not live (`code` 404
///   "无资源") ends the run with [DanmakuCloseReason.connectionFailed] at
///   once; so does a second failure.
/// - Every handshake first asks the server for a socket.io session (a GET,
///   through the given [LiveHttp]), then opens its WebSocket; a failed GET
///   counts as a failed handshake (the runtime's backoff and its eight
///   attempts). The servers are tried in the answer's order.
/// - When the session opens (`1::`) the guest logs in; the login's answer
///   joins (a [DanmakuReady] for every join after a drop). A refused login
///   reconnects when the code may pass, three times in a row at most, else
///   ends the run; a kick ends it too, unless silent.
/// - The server's `2::` every 25 s is echoed, the link heartbeat goes out
///   every 3 minutes, and a socket silent for 90 s is replaced.
/// - Only chat is reported: text lines and emoji. The chat has no audience
///   figure LOOK shows (see the module record).
///
/// The app registers it as `SiteIds.lookLive: () =>
/// LookLiveDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `LookLiveSite` and its proxy policy for the socket.
final class LookLiveDanmakuConnection extends DanmakuSocketConnection<LookLiveDanmakuArgs> {
  /// Creates the connection. [http] asks for the chat servers and the
  /// socket.io sessions; [proxy] routes the socket; [connector] replaces
  /// `dart:io`'s handshake, [policy] the timing, [now] the clock of the
  /// handshake's `t`, [random] the source of the guest identity and
  /// [addressRetryDelay] the wait before the second chat server request
  /// (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    DateTime Function()? now,
    Random? random,
    Duration addressRetryDelay = LookLiveDanmakuProtocol.addressRetryDelay,
  }) => LookLiveDanmakuConnection._(
    _Handshake(http, connector ?? connectIoSocket, now ?? DateTime.now),
    random ?? Random.secure(),
    addressRetryDelay,
    proxy: proxy,
    policy: policy,
  );

  new _(this._handshake, this._random, this._addressRetryDelay, {required super.proxy, required super.policy})
    : super(site: SiteIds.lookLive, connector: _handshake.call);

  /// The platform's timing: a 30 s tick (the link heartbeat every sixth),
  /// so 90 s of silence replaces the socket, and 10 s for the login.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: LookLiveDanmakuProtocol.heartbeatInterval,
    joinTimeout: LookLiveDanmakuProtocol.joinTimeout,
  );

  final _Handshake _handshake;
  final Random _random;
  final Duration _addressRetryDelay;
  bool _forced = false;

  @override
  @protected
  Future<DanmakuSocketTarget> target(LookLiveDanmakuArgs args, DanmakuRun run) async {
    final checked = LookLiveDanmakuProtocol.checked(args);
    if (checked == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable room or chatroom');
    }
    final chat = _handshake.chat = _Chat(run, checked, LookLiveGuest.random(_random));
    final addresses = await _addresses(chat);
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    return DanmakuSocketTarget(
      endpoints: LookLiveDanmakuProtocol.endpoints(addresses),
      headers: LookLiveDanmakuProtocol.socketHeaders,
    );
  }

  /// The chat servers of [chat]'s room: at most
  /// [LookLiveDanmakuProtocol.addressAttempts] requests; an ended run gives
  /// none.
  Future<List<String>> _addresses(_Chat chat) async {
    var failure = '';
    for (var attempt = 0; attempt < LookLiveDanmakuProtocol.addressAttempts; attempt++) {
      if (attempt > 0 && !await chat.run.delay(_addressRetryDelay)) return const [];
      try {
        final response = await _handshake.http.send(
          LookLiveDanmakuProtocol.addressRequest(chat.args.roomId, cancel: chat.cancel),
        );
        if (!chat.run.isActive) return const [];
        return LookLiveApi.chatAddresses(response.text, status: response.status);
      } on NotFound catch (error) {
        throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No chat: ${error.detail}');
      } on Object catch (error) {
        if (!chat.run.isActive) return const [];
        failure = '$error';
      }
    }
    throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'Chat servers: $failure');
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _handshake.chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    _of(session)?.socketReset();
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = LookLiveDanmakuProtocol.decode(data, anonymousMode: chat.args.anonymousMode);
    frame.replies.forEach(session.send);
    if (frame.opened && !chat.loggedIn) {
      chat.loggedIn = true;
      session.send(
        LookLiveDanmakuProtocol.login(
          chatroomId: chat.args.chatroomId,
          guest: chat.guest,
          serial: ++chat.serial,
          again: chat.joins > 0,
        ),
      );
    }
    if (frame.refusal case final code?) {
      _refused(session, chat, code);
      return;
    }
    if (frame.joined && !chat.joined) {
      chat
        ..joined = true
        ..joins += 1
        ..refusals = 0;
      if (session.isConnected) {
        session.cancelJoinTimeout();
      } else {
        session.ready();
      }
    }
    for (final message in frame.messages) {
      if (!session.isActive) return;
      session.message(message);
    }
    if (frame.kicked case final reason?) {
      _kicked(session, chat, reason);
      return;
    }
    if (frame.dropped) session.reconnect();
  }

  void _refused(DanmakuSocketSession session, _Chat chat, int code) {
    session
      ..cancelJoinTimeout()
      ..markDisconnected();
    if (LookLiveDanmakuProtocol.retriedRefusals.contains(code) &&
        ++chat.refusals <= LookLiveDanmakuProtocol.maxRefusals) {
      session.reconnect();
      return;
    }
    session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Login refused: $code');
  }

  void _kicked(DanmakuSocketSession session, _Chat chat, int reason) {
    if (reason == LookLiveDanmakuProtocol.silentKick) {
      session.reconnect();
      return;
    }
    const reasons = LookLiveDanmakuProtocol.kickReasons;
    final name = reason > 0 && reason < reasons.length ? reasons[reason] : '$reason';
    session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Kicked: $name');
  }

  /// The link heartbeat every [LookLiveDanmakuProtocol.ticksPerHeartbeat]
  /// ticks after the login, and at once on [heartbeat]; nothing before the
  /// login.
  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) {
    final chat = _of(session);
    if (chat == null || !chat.joined) return null;
    if (!_forced && ++chat.ticks < LookLiveDanmakuProtocol.ticksPerHeartbeat) return null;
    chat.ticks = 0;
    return LookLiveDanmakuProtocol.heartbeat;
  }

  /// Sends the link heartbeat now (when logged in).
  @override
  void heartbeat() {
    _forced = true;
    try {
      super.heartbeat();
    } finally {
      _forced = false;
    }
  }

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.cancel.cancel();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [LookLiveDanmakuConnection]: a socket.io session
/// first, then the WebSocket of that session.
final class _Handshake {
  new(this.http, this._connect, this._now);

  final LiveHttp http;
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
    final response = await http.send(
      LookLiveDanmakuProtocol.handshakeRequest(
        endpoint,
        roomId: chat.args.roomId,
        now: _now(),
        timeout: connectTimeout,
        cancel: chat.cancel,
      ),
    );
    if (!chat.run.isActive) throw StateError('The chat was closed');
    return await _connect(
      LookLiveDanmakuProtocol.socketUrl(endpoint, LookLiveDanmakuProtocol.sessionOf(response)),
      headers: headers,
      protocols: protocols,
      route: route,
      connectTimeout: connectTimeout,
    );
  }
}

/// One run's chat: the room, the guest, and the state of the current
/// socket.
final class _Chat {
  new(this.run, this.args, this.guest) {
    unawaited(run.ended.then((_) => cancel.cancel()));
  }

  final DanmakuRun run;
  final LookLiveDanmakuArgs args;
  final LookLiveGuest guest;
  final CancelToken cancel = CancelToken();

  /// The last command serial (the SDK counts from 1 across sockets).
  int serial = 0;

  /// Joins so far: a later login is a reconnect's.
  int joins = 0;

  /// Retried refusals in a row.
  int refusals = 0;

  /// Whether the current socket sent its login.
  bool loggedIn = false;

  /// Whether the current socket's login was accepted.
  bool joined = false;

  /// Watchdog ticks since the last link heartbeat.
  int ticks = 0;

  /// A new socket: nothing sent, nothing joined.
  void socketReset() {
    loggedIn = false;
    joined = false;
    ticks = 0;
  }
}
