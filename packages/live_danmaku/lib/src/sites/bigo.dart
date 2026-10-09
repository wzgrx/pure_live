import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// The anonymous visitor a Bigo chat socket logs in as: what the website's
/// `studio/getWebSocketLink` hands every visitor ([BigoDanmakuProtocol
/// .visitor]).
@immutable
final class BigoChatVisitor {
  /// Creates the visitor.
  const new({required this.userId, required this.token, required this.deviceId, this.userName = '0'});

  /// `userId`: the visitor's account, digits.
  final String userId;

  /// `uidToken` without the `###VER2` marker the page strips: the login's
  /// `cookie`. Never logged.
  final String token;

  /// `userName` (`0` for a visitor).
  final String userName;

  /// `deviceId`: the device the visitor was issued for (the page's own
  /// `web_…` value, echoed).
  final String deviceId;

  @override
  String toString() => 'BigoChatVisitor($userId)';
}

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`), from a
/// gift animation (`10|24` with `oriUri` 760969;
/// [BigoDanmakuProtocol.gift], D07.6), as a [LiveGift]: the id, the name,
/// the count and the combo; no price (the gift table `getOnlineGifts` is not
/// asked for).
@immutable
final class BigoGift extends LiveGift {
  /// Creates the gift.
  ///
  /// [id] is `vgift_typeid`, [name] `vgift_name` (`Flower`), [count]
  /// `vgift_count`; [comboTotal] `vgift_count × send_times`, the gifts of
  /// the combo so far; [beans] `ticket_num`, the streamer's bean total after
  /// it (kept for checking; null when not given).
  const new({required super.id, required super.name, required super.count, super.comboTotal, this.beans});

  /// `ticket_num`; null when not given.
  final int? beans;

  @override
  bool operator ==(Object other) => super == other && other is BigoGift && other.beans == beans;

  @override
  int get hashCode => Object.hash(super.hashCode, beans);

  @override
  String toString() => 'BigoGift($name ×$count)';
}

/// The sender of a gift as the chat list's gift line (`payload.tag` 6)
/// names them: the account, the name and the level (D07.6).
typedef BigoGiftSender = ({String userId, String name, String level});

/// What one Bigo chat frame held ([BigoDanmakuProtocol.decode]).
@immutable
final class BigoDanmakuFrame {
  /// Creates the result.
  const new({
    this.messages = const [],
    this.challenge,
    this.loggedIn = false,
    this.entered = false,
    this.idle = false,
    this.refusal,
    this.giftSender,
  });

  /// Chat and audience updates, in order.
  final List<LiveMessage> messages;

  /// The server's challenge (uri 256), which the client answers before it
  /// logs in; null otherwise.
  final String? challenge;

  /// The login was accepted (uri 512535, `res` "200").
  final bool loggedIn;

  /// The room was entered and has a broadcast (uri 1560, `resCode` "200").
  final bool entered;

  /// The room was entered but has no broadcast (uri 1560, `resCode` "200"
  /// with `sid` "0": an offline or unknown room, samples S06-idle and a
  /// made-up room id of 2026-09-30).
  final bool idle;

  /// Why the server refused the login or the room: `login: res …`, `enter:
  /// resCode …`, or `unsigned: …` with the refused uri (a login sent before the challenge
  /// was answered, sample S07-unsigned); null otherwise.
  final String? refusal;

  /// The sender a gift line (`payload.tag` 6) names; it follows the gift's
  /// animation, which names nobody ([BigoDanmakuProtocol.giftLine]).
  final BigoGiftSender? giftSender;
}

/// Bigo Live's web chat, as the website's scripts of 2026-09-30 speak it
/// (docs/D-弹幕/D01-平台弹幕协议/D01.21-BIGOLIVE弹幕/record.md; samples `fixtures/bigo/danmaku/S05-live`,
/// `S06-idle`, `S07-unsigned`), without I/O.
///
/// - Every frame is text: a decimal uri, then a JSON object. The client
///   writes them back to back (`791{…}`); the server puts a tab between
///   them (`791\t{…}`). A uri is the page's `toUri("a|b")`, `a << 8 | b`
///   ([uri]).
/// - A visitor account comes from `studio/getWebSocketLink` ([linkRequest],
///   [visitor]). On the socket ([endpoint]) the server first sends a
///   challenge (256); the client answers it (79108, [answer]), logs in a
///   second later (`2001|23`, [login]) and pings every 10 s from then on
///   (`3|23`, [ping]). An accepted login (`2002|23`) is followed by entering
///   the room (`5|24`, [enter]); an accepted entry (`6|24`) by asking the
///   room's audience (`42|24`, [users]).
/// - Chat arrives as `10|24` (`NORMAL_TEXT`): `payload.tag` 1 is a comment,
///   2 a paid bullet comment, whose `payload.content` is Base64 of UTF-8
///   JSON with the name `n` and the text `m`. The audience arrives as
///   `40|24` (`NUMS`, `totalUserCount`) and in the `43|24` answer
///   (`total`).
abstract final class BigoDanmakuProtocol {
  /// The chat socket of `www.bigo.tv` (the page's `S.prod`; `wss.bigoapp.tv`
  /// and `wss.bigoapp.ru` serve the site's other domains).
  static final Uri endpoint = Uri.parse('wss://wss.bigolive.tv/live/official/web');

  /// Where the page gets its visitor account.
  static final Uri linkUrl = Uri.https('ta.bigo.tv', '/official_website/studio/getWebSocketLink');

  /// Handshake headers: the website's origin and the adapter's browser user
  /// agent (`BigoApi.userAgent`, E03.19). The server also accepts a handshake without an
  /// origin (checked 2026-09-30).
  static const Map<String, String> socketHeaders = {'origin': BigoApi.webOrigin, 'user-agent': BigoApi.userAgent};

  /// Ping period (the page's `setInterval(doPing, 1e4)`).
  static const Duration heartbeatInterval = Duration(seconds: 10);

  /// How long after the socket opened the room must be entered: the
  /// challenge, the page's one-second wait, the login and the entry took 1.4
  /// to 2.5 s in every session of 2026-09-30.
  static const Duration joinTimeout = Duration(seconds: 10);

  /// Wait between answering the challenge and logging in (the page's
  /// `setTimeout(…, 1e3)`).
  static const Duration loginDelay = Duration(seconds: 1);

  /// Refused or unanswered joins in a row after which the connection gives
  /// up.
  static const int maxRefusals = 3;

  /// The page's `toUri("high|low")`.
  static int uri(int high, int low) => high << 8 | low;

  /// The server's challenge (`Challenge_KEY`).
  static const int challengeUri = 256;

  /// The client's answer (`Challenge`).
  static const int answerUri = 79108;

  /// Login, `2001|23`.
  static const int loginUri = 512279;

  /// Login answer, `2002|23` (`LOGIN`).
  static const int loginReplyUri = 512535;

  /// Enter the room, `5|24`.
  static const int enterUri = 1304;

  /// Entry answer, `6|24` (`ENTER_ROOM_RES`).
  static const int enterReplyUri = 1560;

  /// Ask the room's audience, `42|24` (`pullChatRoomUser`).
  static const int usersUri = 10776;

  /// Its answer, `43|24`.
  static const int usersReplyUri = 11032;

  /// Room broadcasts, chat among them, `10|24` (`NORMAL_TEXT`).
  static const int textUri = 2584;

  /// Audience changes, `40|24` (`NUMS`).
  static const int audienceUri = 10264;

  /// Ping and its answer, `3|23`.
  static const int pingUri = 791;

  /// `payload.tag` values that are chat: the page's `comments`
  /// (`NORMAL_TEXT` 1, `DAMMARKU_TEXT` 2).
  static const Set<int> chatTags = {1, 2};

  /// The `oriUri` of a gift's animation in a `10|24` frame (D07.6).
  static const String giftOriUri = '760969';

  /// The `payload.tag` of the chat list's line for a gift (D07.6): it names
  /// the sender ([giftLine]).
  static const int giftLineTag = 6;

  /// How long a gift waits for its line's sender name (D07.6): the line
  /// came 75 ms after the animation in S05-live.
  static const Duration giftSenderWait = Duration(seconds: 1);

  /// A 64-bit room id as written.
  static final RegExp _roomId = RegExp(r'^[1-9][0-9]{0,19}$');

  static final RegExp _digits = RegExp(r'^[0-9]{1,20}$');

  /// Printable ASCII without spaces: the token goes into a JSON frame.
  static final RegExp _token = RegExp(r'^[!-~]{1,4096}$');

  /// A device id as the page makes one for a new browser: `web_`, 32 hex
  /// digits (its fingerprint hash), 6 letters or digits, the time in
  /// milliseconds.
  static String deviceId(Random random, DateTime now) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final hash = [for (var i = 0; i < 32; i++) random.nextInt(16).toRadixString(16)].join();
    final tag = [for (var i = 0; i < 6; i++) alphabet[random.nextInt(alphabet.length)]].join();
    return 'web_${hash}_${tag}_${now.millisecondsSinceEpoch}';
  }

  /// The page's `getWebSocketLink({deviceId})`: a form POST with its
  /// content type, and the adapter's headers (`BigoApi.headers`), no
  /// redirect followed; sent as `bigo` (its proxy route).
  static LiveRequest linkRequest(String deviceId, {Duration timeout = defaultRequestTimeout, CancelToken? cancel}) =>
      LiveRequest(
        site: SiteIds.bigo,
        url: linkUrl,
        method: 'POST',
        headers: const {...BigoApi.headers, 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8'},
        body: utf8.encode('deviceId=${Uri.encodeQueryComponent(deviceId)}'),
        followRedirects: false,
        timeout: timeout,
        cancel: cancel,
      );

  /// The visitor of a `getWebSocketLink` [response]: HTTP 200, `code` 0, a
  /// `userId` of digits and a usable `uidToken`; a [FormatException]
  /// otherwise. [deviceId] stands in when the answer names none.
  static BigoChatVisitor visitor(LiveResponse response, {required String deviceId}) {
    if (response.status != 200) throw FormatException('getWebSocketLink: HTTP ${response.status}');
    final Object? root;
    try {
      root = response.json;
    } on FormatException {
      throw const FormatException('getWebSocketLink: not JSON');
    }
    if (root is! Map || root['code'] != 0) {
      throw FormatException('getWebSocketLink: code ${root is Map ? root['code'] : null}');
    }
    final data = root['data'];
    final userId = data is Map ? data['userId'] : null;
    final rawToken = data is Map ? data['uidToken'] : null;
    final token = rawToken is String ? rawToken.replaceAll('###VER2', '') : null;
    if (data is! Map || userId is! String || !_digits.hasMatch(userId) || token == null || !_token.hasMatch(token)) {
      throw const FormatException('getWebSocketLink: no visitor');
    }
    final name = data['userName'];
    final device = data['deviceId'];
    return BigoChatVisitor(
      userId: userId,
      token: token,
      userName: name is String && _token.hasMatch(name) ? name : '0',
      deviceId: device is String && _token.hasMatch(device) ? device : deviceId,
    );
  }

  /// [args] if they name a room: a Bigo id, an owner account (1 … 2⁵³ − 1)
  /// and a room id of up to 20 digits; null otherwise.
  static BigoDanmakuArgs? checked(BigoDanmakuArgs args) {
    final siteId = args.siteId.trim();
    final roomId = args.roomId.trim();
    if (!BigoApi.isSiteId(siteId) || args.ownerId < 1 || args.ownerId > 9007199254740991) return null;
    if (!_roomId.hasMatch(roomId)) return null;
    return BigoDanmakuArgs(siteId: siteId, ownerId: args.ownerId, roomId: roomId);
  }

  /// The answer to [challenge] at [now] (the page's `generateChallengeKey`):
  /// fixed fields, the time in seconds, and `sign`, the MD5 of
  /// `60#4#5#<time>#1#1#1#1#<the challenge's last 8 characters>`.
  static String answer(String challenge, DateTime now) {
    final time = '${now.millisecondsSinceEpoch ~/ 1000}';
    final tail = challenge.length > 8 ? challenge.substring(challenge.length - 8) : challenge;
    final sign = md5.convert(utf8.encode('60#4#5#$time#1#1#1#1#$tail')).toString();
    return '$answerUri${jsonEncode({'appId': '60', 'osType': '4', 'clientVersion': '5', 'timeStamp': time, 'nonce': '1', 'reservedForSecurity': '1', 'appSign': '1', 'redundancy': '1', 'sign': sign})}';
  }

  /// The login of [visitor] (the page's `doLogin` for a visitor: client
  /// type 7, no client address).
  static String login(BigoChatVisitor visitor) =>
      '$loginUri${jsonEncode({
        'uid': visitor.userId,
        'cookie': visitor.token,
        'secret': '0',
        'userName': visitor.userName,
        'deviceId': visitor.deviceId,
        'userFlag': '0',
        'status': '0',
        'password': '0',
        'sdkVersion': '0',
        'displayType': '0',
        'pbVersion': '0',
        'lang': 'cn',
        'loginLevel': '0',
        'clientVersionCode': '0',
        'clientType': '7',
        'clientOsVer': '0',
        'netConf': {'clientIp': '0', 'proxySwitch': '0', 'proxyTimestamp': '0', 'mcc': '0', 'mnc': '0', 'countryCode': 'CN'},
      })}';

  /// Entering room [roomId] at [now] (the page's `enterRoom` without a
  /// password: `secretKey` "0").
  static String enter(String roomId, BigoChatVisitor visitor, DateTime now) =>
      '$enterUri${jsonEncode({'secretKey': '0', 'seqId': '${now.millisecondsSinceEpoch}', 'roomId': roomId, 'reserver': '1', 'clientVersion': '0', 'clientType': '7', 'version': '15', 'deviceid': visitor.deviceId, 'other': <Object>[]})}';

  /// Asking the audience of [args]'s room at [now] (the page's
  /// `pullChatRoomUser`).
  static String users(BigoDanmakuArgs args, DateTime now) =>
      '$usersUri${jsonEncode({'uid': '${args.ownerId}', 'seqId': '${now.millisecondsSinceEpoch}', 'roomid': args.roomId, 'contribution': '0', 'enterTimestamp': '0', 'number': '0', 'ident': '0', 'userGrade': '0', 'version': '0', 'lastUserBeanGrade': '0', 'lastUserId': '0', 'others': <Object>[]})}';

  /// The ping at [now] (the page's `doPing`).
  static String ping(DateTime now) =>
      '$pingUri${jsonEncode({'status': '0', 'seqid': '${now.millisecondsSinceEpoch}', 'flag': '0', 'roomId': '0', 'ownerStatus': '0', 'micUid': '0'})}';

  /// One frame (text, or UTF-8 bytes) of room [roomId], read as the page's
  /// `onmessage` and the room page's subscriptions read it:
  ///
  /// - everything up to the first `{` is the uri (white space and NUL
  ///   ignored), the rest one JSON object; anything else gives nothing;
  /// - an object with `info` "unsigned" or an `errUri` is a refusal, whatever
  ///   its uri (the page's login failure);
  /// - 256 is the challenge; 512535 the login answer (`res` "200" logs in,
  ///   anything else is a refusal); 1560 the entry answer (`resCode` "200"
  ///   enters, or finds the room [BigoDanmakuFrame.idle] when `sid` is "0";
  ///   anything else is a refusal);
  /// - 2584 of this room is chat when [chat] reads it, a gift when its
  ///   `oriUri` is [giftOriUri] ([gift]), a gift's sender when it is the
  ///   gift line ([giftLine]); 10264 and 11032 of this room are the
  ///   audience ([audience]);
  /// - every other frame (pings, likes, entrance notices, the room's heat,
  ///   seats) gives nothing.
  static BigoDanmakuFrame decode(Object? data, {required String roomId}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    final brace = text?.indexOf('{') ?? -1;
    if (text == null || brace < 0) return const BigoDanmakuFrame();
    final Object? body;
    try {
      body = jsonDecode(text.substring(brace));
    } on FormatException {
      return const BigoDanmakuFrame();
    }
    if (body is! Map) return const BigoDanmakuFrame();
    final errUri = body['errUri'];
    if (body['info'] == 'unsigned' || (errUri != null && errUri != '' && errUri != 0 && errUri != false)) {
      return BigoDanmakuFrame(refusal: 'unsigned: ${_scalar(errUri)}');
    }
    final uri = int.tryParse(text.substring(0, brace).replaceAll(RegExp(r'[\s\x00]'), ''));
    switch (uri) {
      case challengeUri:
        final challenge = body['challenge'];
        return challenge is String && challenge.isNotEmpty
            ? BigoDanmakuFrame(challenge: challenge)
            : const BigoDanmakuFrame();
      case loginReplyUri:
        final res = body['res'];
        return res == '200'
            ? const BigoDanmakuFrame(loggedIn: true)
            : BigoDanmakuFrame(refusal: 'login: res ${_scalar(res)}');
      case enterReplyUri:
        final code = body['resCode'];
        if (code != '200') return BigoDanmakuFrame(refusal: 'enter: resCode ${_scalar(code)}');
        final sid = _scalar(body['sid']);
        return sid.isEmpty || sid == '0' ? const BigoDanmakuFrame(idle: true) : const BigoDanmakuFrame(entered: true);
      case textUri:
        if (_scalar(body['oriUri']) == giftOriUri) {
          final present = gift(body, roomId: roomId);
          return present == null ? const BigoDanmakuFrame() : BigoDanmakuFrame(messages: [present]);
        }
        if (giftLine(body, roomId: roomId) case final sender?) return BigoDanmakuFrame(giftSender: sender);
        final message = chat(body, roomId: roomId);
        return message == null ? const BigoDanmakuFrame() : BigoDanmakuFrame(messages: [message]);
      case audienceUri || usersReplyUri:
        final message = audience(body, uri: uri!, roomId: roomId);
        return message == null ? const BigoDanmakuFrame() : BigoDanmakuFrame(messages: [message]);
      default:
        return const BigoDanmakuFrame();
    }
  }

  /// A `10|24` broadcast of room [roomId] as white chat, or null (the room
  /// page's `NORMAL_TEXT` subscription):
  ///
  /// - `room_id` is the room; `payload.tag` is 1 (comment) or 2 (paid bullet
  ///   comment, shown as a comment as the page's chat list does);
  /// - `payload.content` is Base64 of UTF-8 JSON (the page's
  ///   `JSON.parse(decodeURIComponent(escape(atob(…))))`); one that does not
  ///   decode is dropped, as the page drops it;
  /// - the text is `m` trimmed (null when empty), the name `n` trimmed;
  /// - the user id is `payload.uid` (else `from_uid`), the level
  ///   `payload.grade`;
  /// - the message id is `<user id>:<seqId>` (the server resent a message
  ///   unchanged, same `seqId`, on 2026-09-30);
  /// - no time: `payload.timestamp` is "0" in every comment recorded.
  static LiveMessage? chat(Map<Object?, Object?> frame, {required String roomId}) {
    if (_scalar(frame['room_id']) != roomId) return null;
    final payload = frame['payload'];
    if (payload is! Map) return null;
    final tag = int.tryParse(_scalar(payload['tag']));
    final content = payload['content'];
    if (tag == null || !chatTags.contains(tag) || content is! String) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64.decode(base64.normalize(content.trim()))));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final text = _scalar(decoded['m']).trim();
    if (text.isEmpty) return null;
    var userId = _scalar(payload['uid']);
    if (!_digits.hasMatch(userId)) userId = _scalar(frame['from_uid']);
    if (!_digits.hasMatch(userId)) userId = '';
    final level = _scalar(payload['grade']);
    final seq = _scalar(frame['seqId']);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _scalar(decoded['n']).trim(),
      userId: userId,
      message: text,
      userLevel: _digits.hasMatch(level) ? level : '',
      messageId: userId.isNotEmpty && _digits.hasMatch(seq) ? '$userId:$seq' : '',
      color: LiveMessageColor.white,
    );
  }

  /// A gift's animation in a `10|24` frame of room [roomId] (`oriUri`
  /// [giftOriUri], D07.6): `payload.vgift_typeid` (the id),
  /// `vgift_name`, `vgift_count`, `send_times` (the sends of the combo so
  /// far: the combo's gifts are `vgift_count × send_times`) and
  /// `ticket_num`; the sender's account `from_uid`, no name (the gift line
  /// that follows names them, [giftLine]). The message id is `<account>:<seqId>`.
  /// Null for another room, or without a gift name.
  static LiveMessage? gift(Map<Object?, Object?> frame, {required String roomId}) {
    final payload = frame['payload'];
    if (payload is! Map) return null;
    final room = _scalar(payload['room_id']);
    if ((room.isEmpty ? _scalar(frame['room_id']) : room) != roomId) return null;
    final name = _scalar(payload['vgift_name']).trim();
    if (name.isEmpty) return null;
    final count = _count(payload['vgift_count']) ?? 1;
    final sends = _count(payload['send_times']);
    final present = BigoGift(
      id: _scalar(payload['vgift_typeid']).trim(),
      name: name,
      count: count,
      comboTotal: sends == null ? null : count * sends,
      beans: _count(payload['ticket_num']),
    );
    var userId = _scalar(payload['from_uid']);
    if (!_digits.hasMatch(userId)) userId = _scalar(frame['from_uid']);
    if (!_digits.hasMatch(userId)) userId = '';
    final seq = _scalar(frame['seqId']);
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: '',
      userId: userId,
      message: present.plainText,
      messageId: userId.isNotEmpty && _digits.hasMatch(seq) ? '$userId:$seq' : '',
      color: LiveMessageColor.white,
      data: present,
    );
  }

  /// The sender of the chat list's gift line (`payload.tag` [giftLineTag]
  /// of a `10|24` frame of room [roomId], D07.6): the account `payload.uid`
  /// (else `from_uid`), the name `n` of the Base64 JSON `content` and the
  /// level `payload.grade`. Null for anything else, or without an account.
  static BigoGiftSender? giftLine(Map<Object?, Object?> frame, {required String roomId}) {
    if (_scalar(frame['room_id']) != roomId) return null;
    final payload = frame['payload'];
    if (payload is! Map || int.tryParse(_scalar(payload['tag'])) != giftLineTag) return null;
    var userId = _scalar(payload['uid']);
    if (!_digits.hasMatch(userId)) userId = _scalar(frame['from_uid']);
    if (!_digits.hasMatch(userId)) return null;
    final content = payload['content'];
    var name = '';
    if (content is String) {
      try {
        final decoded = jsonDecode(utf8.decode(base64.decode(base64.normalize(content.trim()))));
        if (decoded is Map) name = _scalar(decoded['n']).trim();
      } on FormatException {
        // A line without a name that reads.
      }
    }
    final level = _scalar(payload['grade']);
    return (userId: userId, name: name, level: _digits.hasMatch(level) ? level : '');
  }

  /// A whole number of at least 1 written as digits, or null.
  static int? _count(Object? value) {
    final text = _scalar(value);
    final count = _digits.hasMatch(text) ? int.tryParse(text) : null;
    return count != null && count > 0 ? count : null;
  }

  /// The concurrent audience of room [roomId] in a `40|24` frame
  /// (`totalUserCount`, when `gid` is the room) or the `43|24` answer
  /// (`total`, when `room_id` is the room), as the room page shows them
  /// (`nums`); null otherwise. Both are the same count as the list's
  /// `user_count` (2472–2513 on the socket against 2557 in the list,
  /// 2026-09-30).
  static LiveMessage? audience(Map<Object?, Object?> frame, {required int uri, required String roomId}) {
    final (room, count) = uri == audienceUri
        ? (frame['gid'], frame['totalUserCount'])
        : (frame['room_id'], frame['total']);
    if (_scalar(room) != roomId) return null;
    final value = int.tryParse(_scalar(count));
    if (value == null || value < 0 || !_digits.hasMatch(_scalar(count))) return null;
    return LiveMessage(
      type: LiveMessageType.online,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: value),
    );
  }

  static String _scalar(Object? value) => switch (value) {
    final String text => text,
    final int number => '$number',
    _ => '',
  };
}

/// Bigo Live's chat connection (new in v4: 3.x had none, the 24-3 upgrade),
/// on the WebSocket runtime: one socket to [BigoDanmakuProtocol.endpoint] as
/// an anonymous visitor, the way the website's player joins a room.
///
/// - The first handshake of a [connect] asks `getWebSocketLink` for a
///   visitor account (one request, as the page does once per player); later
///   handshakes reuse it, as the page's reconnect does. A refused or
///   unanswered join drops it, so the next handshake asks for a new one. A
///   request that fails counts as a failed handshake (the runtime's backoff
///   and its eight attempts).
/// - On every socket: the challenge is answered, the login follows a second
///   later, then the room is entered; the entry's answer joins
///   ([DanmakuReady]) and the audience is asked for. A room without a
///   broadcast ends the connection with [DanmakuCloseReason.connectionFailed].
///   A refused login or entry, or no entry within 10 s, reconnects; the
///   fourth in a row ends the connection.
/// - Pings every 10 s once logged in; the server answers each.
/// - Chat (comments and paid bullet comments) and the concurrent audience
///   are reported, and gifts (D07.6): a gift waits up to
///   [BigoDanmakuProtocol.giftSenderWait] for the gift line that names its
///   sender, and is reported with the name and level then, or without
///   them once the wait is over.
///
/// The app registers it as `SiteIds.bigo: () => BigoDanmakuConnection(http:
/// …, proxy: …)`, with the `LiveHttp` it gives `BigoSite` and its proxy
/// policy for the socket.
final class BigoDanmakuConnection extends DanmakuSocketConnection<BigoDanmakuArgs> {
  /// Creates the connection. [http] asks for the visitor account; [proxy]
  /// routes the socket; [connector] replaces `dart:io`'s handshake,
  /// [policy] the timing, [loginDelay] the wait before the login, [now] the
  /// clock of the frames' times and [random] the device id (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    Duration loginDelay = BigoDanmakuProtocol.loginDelay,
    DateTime Function()? now,
    Random? random,
  }) => BigoDanmakuConnection._(
    _Handshake(http, connector ?? connectIoSocket),
    proxy: proxy,
    policy: policy,
    loginDelay: loginDelay,
    now: now ?? DateTime.now,
    random: random ?? Random.secure(),
  );

  new _(
    this._handshake, {
    required super.proxy,
    required super.policy,
    required this._loginDelay,
    required this._now,
    required this._random,
  }) : super(site: SiteIds.bigo, connector: _handshake.call);

  /// The platform's timing: the page's 10 s ping and a 10 s join limit; the
  /// runtime's defaults otherwise (the silence watchdog at 90 s).
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: BigoDanmakuProtocol.heartbeatInterval,
    joinTimeout: BigoDanmakuProtocol.joinTimeout,
  );

  static final DanmakuSocketTarget _target = DanmakuSocketTarget(
    endpoints: [BigoDanmakuProtocol.endpoint],
    headers: BigoDanmakuProtocol.socketHeaders,
  );

  final _Handshake _handshake;
  final Duration _loginDelay;
  final DateTime Function() _now;
  final Random _random;

  @override
  @protected
  Future<DanmakuSocketTarget> target(BigoDanmakuArgs args, DanmakuRun run) async {
    final checked = BigoDanmakuProtocol.checked(args);
    if (checked == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable room');
    }
    _handshake.chat = _Chat(run, checked, BigoDanmakuProtocol.deviceId(_random, _now()));
    return _target;
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _handshake.chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    _of(session)
      ?..socketReset()
      ..socket += 1;
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = BigoDanmakuProtocol.decode(data, roomId: chat.args.roomId);
    if (frame.refusal case final refusal?) {
      _refused(session, chat, refusal);
      return;
    }
    if (frame.challenge case final challenge? when !chat.answered) {
      chat.answered = true;
      session.send(BigoDanmakuProtocol.answer(challenge, _now()));
      final socket = chat.socket;
      chat.loginTimer = Timer(_loginDelay, () {
        chat.loginTimer = null;
        final visitor = chat.visitor;
        if (!session.isActive || chat.socket != socket || visitor == null) return;
        chat.loginSent = true;
        session.send(BigoDanmakuProtocol.login(visitor));
      });
    }
    if (frame.loggedIn && chat.loginSent && !chat.entering) {
      final visitor = chat.visitor;
      if (visitor == null) return;
      chat.entering = true;
      session.send(BigoDanmakuProtocol.enter(chat.args.roomId, visitor, _now()));
    }
    if (frame.idle) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'No broadcast in room ${chat.args.roomId}');
      return;
    }
    if (frame.entered && !chat.joined) {
      chat
        ..joined = true
        ..refusals = 0;
      if (session.isConnected) {
        session.cancelJoinTimeout();
      } else {
        session.ready();
      }
      session.send(BigoDanmakuProtocol.users(chat.args, _now()));
    }
    if (frame.giftSender case final sender?) chat.named(sender);
    for (final message in frame.messages) {
      if (!session.isActive) return;
      if (message.type == LiveMessageType.gift && message.userId.isNotEmpty) {
        chat.waitForSender(message, session.message);
      } else {
        session.message(message);
      }
    }
  }

  /// A refused or unanswered join: the visitor is dropped (the next
  /// handshake asks for a new one) and the socket replaced; the fourth in a
  /// row ends the connection.
  void _refused(DanmakuSocketSession session, _Chat chat, String refusal) {
    chat
      ..visitor = null
      ..socketReset();
    if (++chat.refusals > BigoDanmakuProtocol.maxRefusals) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: $refusal');
      return;
    }
    session.reconnect();
  }

  @override
  @protected
  void onJoinTimeout(DanmakuSocketSession session) {
    final chat = _of(session);
    if (chat == null) {
      session.reconnect();
      return;
    }
    _refused(session, chat, chat.loginSent ? 'login or entry unanswered' : 'no challenge or login');
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) {
    final chat = _of(session);
    return chat != null && chat.loginSent ? BigoDanmakuProtocol.ping(_now()) : null;
  }

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.dispose();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [BigoDanmakuConnection]: asks `getWebSocketLink` for a
/// visitor first when the run has none, then connects.
final class _Handshake {
  new(this._http, this._connect);

  final LiveHttp _http;
  final SocketConnector _connect;

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
    if (chat.visitor == null) {
      final response = await _http.send(
        BigoDanmakuProtocol.linkRequest(chat.deviceId, timeout: connectTimeout, cancel: chat.cancel),
      );
      final visitor = BigoDanmakuProtocol.visitor(response, deviceId: chat.deviceId);
      if (!chat.run.isActive) throw StateError('The chat was closed');
      chat.visitor = visitor;
    }
    return await _connect(
      endpoint,
      headers: headers,
      protocols: protocols,
      route: route,
      connectTimeout: connectTimeout,
    );
  }
}

/// One run's chat: the room, the visitor and the state of the current
/// socket.
final class _Chat {
  new(this.run, this.args, this.deviceId) {
    unawaited(run.ended.then((_) => dispose()));
  }

  final DanmakuRun run;
  final BigoDanmakuArgs args;

  /// The device id the visitor is asked for.
  final String deviceId;
  final CancelToken cancel = CancelToken();

  /// The visitor of the next login; null until asked for, and after a
  /// refused join.
  BigoChatVisitor? visitor;

  /// Joins refused or unanswered in a row.
  int refusals = 0;

  /// Sockets opened so far.
  int socket = 0;

  /// Whether the current socket's challenge was answered.
  bool answered = false;

  /// Whether the current socket's login was sent.
  bool loginSent = false;

  /// Whether the current socket asked to enter the room.
  bool entering = false;

  /// Whether the current socket entered the room.
  bool joined = false;

  /// Sends the login a second after the answer.
  Timer? loginTimer;

  /// Gifts waiting for their line's sender name (D07.6), oldest first.
  final List<({LiveMessage gift, Timer timer, void Function(LiveMessage) report})> _gifts = [];

  /// Reports [gift] through [report] when its line names the sender, or
  /// without the name after [BigoDanmakuProtocol.giftSenderWait].
  void waitForSender(LiveMessage gift, void Function(LiveMessage) report) {
    late final ({LiveMessage gift, Timer timer, void Function(LiveMessage) report}) entry;
    entry = (
      gift: gift,
      report: report,
      timer: Timer(BigoDanmakuProtocol.giftSenderWait, () {
        if (_gifts.remove(entry) && run.isActive) report(gift);
      }),
    );
    _gifts.add(entry);
  }

  /// The oldest gift waiting from [sender]'s account, reported with the
  /// name and level the gift line gives.
  void named(BigoGiftSender sender) {
    final index = _gifts.indexWhere((entry) => entry.gift.userId == sender.userId);
    if (index < 0) return;
    final entry = _gifts.removeAt(index);
    entry.timer.cancel();
    if (!run.isActive) return;
    final gift = entry.gift;
    entry.report(
      LiveMessage(
        type: gift.type,
        userName: sender.name,
        userId: gift.userId,
        message: gift.message,
        color: gift.color,
        userLevel: sender.level,
        messageId: gift.messageId,
        data: gift.data,
      ),
    );
  }

  /// A new socket: nothing sent, nothing joined.
  void socketReset() {
    answered = false;
    loginSent = false;
    entering = false;
    joined = false;
    loginTimer?.cancel();
    loginTimer = null;
  }

  void dispose() {
    socketReset();
    cancel.cancel();
    for (final entry in _gifts) {
      entry.timer.cancel();
    }
    _gifts.clear();
  }
}
