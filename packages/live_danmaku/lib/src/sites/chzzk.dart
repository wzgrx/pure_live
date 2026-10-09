import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one CHZZK chat frame held ([ChzzkDanmakuProtocol.decode]).
@immutable
final class ChzzkDanmakuFrame {
  /// Creates the result.
  const new({
    this.messages = const [],
    this.pushed = false,
    this.joined,
    this.sessionId = '',
    this.refusal = '',
    this.retry = false,
    this.ping = false,
    this.closed = false,
  });

  /// Chat lines, super chats, notices and retractions, in order.
  final List<LiveMessage> messages;

  /// The frame carried lines pushed live (`cmd` 93101 or 93102), shown or
  /// not: the chat channel is in use.
  final bool pushed;

  /// The answer to the join (`cmd 10100`): true when accepted (`retCode 0`),
  /// false when refused, null when the frame held no answer to it.
  final bool? joined;

  /// The session id (`bdy.sid`) of an accepted join, which the recent-chat
  /// request names; empty when the answer had none.
  final String sessionId;

  /// A refused join's code and text (`105 Incorrect parameter`), for
  /// diagnostics.
  final String refusal;

  /// The refusal asks the client to connect again (`retCode` 302, 303 or
  /// 304, on which the site's chat SDK reconnects).
  final bool retry;

  /// The server's ping (`cmd 0`), to be answered with
  /// [ChzzkDanmakuProtocol.pong].
  final bool ping;

  /// The server ended the session (`cmd 90102`); the site's chat SDK then
  /// closes without reconnecting.
  final bool closed;
}

/// CHZZK's chat (docs/D-弹幕/D01-平台弹幕协议/D01.17-CHZZK弹幕/record.md), without I/O.
///
/// 3.x had no CHZZK danmaku; this follows the archived v4 connector, the
/// recordings and the site's own chat client (NAVER's chat SDK 4.11.0 in
/// `chzzk.naver.com`'s `vendor-*.js`, driven by its `index-*.js`):
///
/// - an access token from `comm-api.game.naver.com` names the chat channel
///   ([tokenUrl], [accessToken]);
/// - the session servers come from `routing.chat.naver.com` ([routingUrl],
///   [servers]); a live chat takes one of them at random;
/// - every message is a JSON text frame: the join (`cmd 100`, read-only)
///   is answered by `cmd 10100`, after which the client asks the recent
///   chat (`cmd 5101`, answered by `15101`); chat arrives as `93101` and
///   `93102`; the client pings (`cmd 0`) and the server pongs (`10000`),
///   and a server ping is answered the same way;
/// - the site shows donations as paid messages, subscription gifts, system
///   lines and the pinned notice as lines of their own, and hides a line a
///   manager or the clean bot blinds afterwards (`94008`); these become
///   super chats, notices and retractions (M5.F, B-12);
/// - a live's state, its chat channel included, is read from the channel's
///   `live-status` ([liveStatusUrl], [liveChatChannel]).
abstract final class ChzzkDanmakuProtocol {
  /// Ping period: the SDK's `pingInterval` (20 000 ms).
  static const Duration heartbeatInterval = Duration(seconds: 20);

  /// Silence after which the socket is replaced: the SDK closes a socket
  /// that answers nothing within its `pingTimeout` (10 000 ms) of a ping
  /// sent after 20 s without a message, so 30 s in all.
  static const Duration inactivityTimeout = Duration(seconds: 30);

  /// How long the join's answer may take: the SDK's `callbackTimeout`
  /// (5 000 ms) for every request.
  static const Duration joinTimeout = Duration(seconds: 5);

  /// Recent chat lines asked for after joining, as the site asks.
  static const int recentCount = 50;

  /// Text, the first of the message kinds (`msgTypeCode`,
  /// `messageTypeCode`) read here; the others are the constants below.
  /// Images, stickers, parties and shop purchases are not read.
  static const int textType = 1;

  /// A donation (`치즈 후원`): a super chat whose text is the donor's message,
  /// the title of the video it pays for or the mission it pledges.
  static const int donationType = 10;

  /// A subscription, whose text is the subscriber's message: a notice
  /// ([subscription], D07.6), then the message as chat.
  static const int subscriptionType = 11;

  /// A subscription gift (`구독권 선물`): a notice composed from `extras`.
  static const int subscriptionGiftType = 12;

  /// A system line (chat modes, restrictions): a notice.
  static const int systemType = 30;

  /// The name the site shows for an anonymous donor (its `익명의 후원자`).
  static const String anonymousDonor = '익명의 후원자';

  /// The unit of donations (1 치즈 is one won), as the site names it after
  /// an amount (`{{payAmount}} 치즈를 후원했습니다`).
  static const String cheese = '치즈';

  /// How long a donation stays among the super chats, by the site's five
  /// amount tiers (the `level0`–`level4` styles of its donation line: below
  /// 10 000, 100 000, 500 000 and 1 000 000 치즈, and above). The site keeps
  /// donations in its chat list without a time; these are the first five
  /// steps of Bilibili's super chats (1, 2, 5, 30 and 60 minutes), the
  /// times 3.x's super chat bar already shows.
  static Duration superChatDuration(int amount) => switch (amount) {
    >= 1000000 => const Duration(hours: 1),
    >= 500000 => const Duration(minutes: 30),
    >= 100000 => const Duration(minutes: 5),
    >= 10000 => const Duration(minutes: 2),
    _ => const Duration(minutes: 1),
  };

  /// A donation's amount as the site writes it: digits grouped by commas
  /// (its `Tl`) and the unit, `1,000 치즈`.
  static String cheeseText(int amount) => '${'$amount'.replaceAll(_thousands, ',')} $cheese';

  static final RegExp _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

  /// Join refusals on which the site's chat SDK connects again.
  static const Set<int> retryCodes = {302, 303, 304};

  /// The routing answer's fallback, as the SDK has it built in.
  static const List<String> defaultServers = [
    'kr-ss1.chat.naver.com',
    'kr-ss2.chat.naver.com',
    'kr-ss3.chat.naver.com',
    'kr-ss4.chat.naver.com',
    'kr-ss5.chat.naver.com',
  ];

  /// Most session servers taken from a routing answer.
  static const int maxServers = 16;

  /// The session servers of the chat service `game`.
  static final Uri routingUrl = Uri.https('routing.chat.naver.com', '/routing/getRouting', {'serviceId': 'game'});

  /// Handshake headers: the site's origin and the desktop UA of every CHZZK
  /// request (`ChzzkApi.userAgent`), as the recordings sent them.
  static const Map<String, String> handshakeHeaders = {'origin': ChzzkApi.origin, 'user-agent': ChzzkApi.userAgent};

  /// The client's ping; the server answers `{"ver":"2","cmd":10000}`.
  static const String ping = '{"ver":"3","cmd":0}';

  /// The answer to a server ping.
  static const String pong = '{"ver":"3","cmd":10000}';

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  static final RegExp _chatChannelId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _server = RegExp(r'^[a-z0-9-]{1,63}\.chat\.naver\.com$');

  /// Whether [id] can be a chat channel id: base64url characters (`N2l_uf`,
  /// `N2l-x_`), at most 64.
  static bool isChatChannelId(String id) => _chatChannelId.hasMatch(id);

  /// The access token request of [chatChannelId].
  static Uri tokenUrl(String chatChannelId) => Uri.https('comm-api.game.naver.com', '/nng_main/v1/chats/access-token', {
    'channelId': chatChannelId,
    'chatType': 'STREAMING',
  });

  /// The access token of a decoded token answer (`code 200`,
  /// `content.accessToken`), or null.
  static String? accessToken(Object? answer) {
    if (answer case {'code': 200, 'content': {'accessToken': final String token}} when token.isNotEmpty) return token;
    return null;
  }

  /// The session servers of a decoded routing answer (`code 200`,
  /// `result.sessionServerList`): host names under `chat.naver.com`, in
  /// order, without repeats, at most [maxServers]; null when there is none.
  static List<String>? servers(Object? answer) {
    if (answer case {'code': 200, 'result': {'sessionServerList': final List<Object?> list}}) {
      final hosts = <String>{
        for (final host in list)
          if (host is String && _server.hasMatch(host)) host,
      };
      if (hosts.isNotEmpty) return List.unmodifiable(hosts.take(maxServers));
    }
    return null;
  }

  /// The chat sockets of [servers], starting at [first] and going round.
  static List<Uri> endpoints(List<String> servers, int first) => [
    for (var index = 0; index < servers.length; index++)
      Uri(scheme: 'wss', host: servers[(first + index) % servers.length], path: '/chat'),
  ];

  /// The read-only join of [chatChannelId] with [token], as v4 and the
  /// recordings sent it.
  static String join(String chatChannelId, String token) => jsonEncode({
    'ver': '3',
    'cmd': 100,
    'svcid': 'game',
    'cid': chatChannelId,
    'bdy': {'uid': null, 'devType': 2001, 'accTkn': token, 'auth': 'READ'},
    'tid': 1,
  });

  /// The recent-chat request of the session [sessionId].
  static String recent(String chatChannelId, String sessionId) => jsonEncode({
    'ver': '3',
    'cmd': 5101,
    'svcid': 'game',
    'cid': chatChannelId,
    'sid': sessionId,
    'bdy': {'recentMessageCount': recentCount},
    'tid': 2,
  });

  /// The live state of the channel [channelId], which the site's chat page
  /// polls every 30 s while the live is open (its `polling/v3.1` client,
  /// `/channels/<id>/live-status`).
  static Uri liveStatusUrl(String channelId) =>
      Uri.https(ChzzkApi.apiHost, '/polling/v3.1/channels/$channelId/live-status');

  /// The chat channel of a decoded live-status answer (`code 200`,
  /// `content.chatChannelId`) while the live is open (`status` `OPEN`);
  /// null otherwise (closed, no chat, not a chat channel id).
  static String? liveChatChannel(Object? answer) {
    if (answer case {'code': 200, 'content': {'status': 'OPEN', 'chatChannelId': final String id}}
        when isChatChannelId(id)) {
      return id;
    }
    return null;
  }

  /// Reads one frame of a chat socket: text, or UTF-8 bytes (malformed
  /// bytes become U+FFFD). [receivedAt] (default: now) starts the super
  /// chat of a donation that has no time.
  ///
  /// The frame's JSON object is named by `cmd`:
  ///
  /// - `0`: the server's ping ([ChzzkDanmakuFrame.ping]);
  /// - `10100`: the answer to the join; `retCode 0` accepts it
  ///   ([ChzzkDanmakuFrame.joined], with `bdy.sid`), anything else refuses
  ///   it (`retCode` and `retMsg` in [ChzzkDanmakuFrame.refusal]);
  /// - `93101` (chat) and `93102` (lines the server sends on its own:
  ///   donations, subscriptions, system lines): `bdy` lists the lines
  ///   ([line], [ChzzkDanmakuFrame.pushed]);
  /// - `15101` with `retCode 0`: the recent chat, `bdy.messageList`, in
  ///   the recent form of [line], then the notice pinned now, `bdy.notice`
  ///   ([pinned]);
  /// - `94010`: the notice pinned now ([pinned]);
  /// - `94008`: a line blinded afterwards ([blind]);
  /// - `90102`: the server ended the session ([ChzzkDanmakuFrame.closed]).
  ///
  /// Everything else (the pong `10000`, events `93006`, kicks and
  /// penalties) holds nothing to show; so does a frame that is not a JSON
  /// object. A field of the wrong type costs only that field or that line,
  /// never the frame. The member count of every line (`mbrCnt`,
  /// `memberCount`, and `userCount` of the recent chat) counts the chat's
  /// connections, not the audience, and is not read.
  static ChzzkDanmakuFrame decode(Object? data, {DateTime? receivedAt}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const ChzzkDanmakuFrame();
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const ChzzkDanmakuFrame();
    }
    if (root is! Map) return const ChzzkDanmakuFrame();
    final body = root['bdy'];
    final now = receivedAt ?? DateTime.now();
    switch (root['cmd']) {
      case 0:
        return const ChzzkDanmakuFrame(ping: true);
      case 90102:
        return const ChzzkDanmakuFrame(closed: true);
      case 10100:
        final code = root['retCode'];
        if (code == 0) {
          final sid = body is Map ? body['sid'] : null;
          return ChzzkDanmakuFrame(joined: true, sessionId: sid is String ? sid : '');
        }
        return ChzzkDanmakuFrame(
          joined: false,
          refusal: '${_scalar(code)} ${_scalar(root['retMsg'])}'.trim(),
          retry: retryCodes.contains(code),
        );
      case 93101 || 93102 when body is List:
        return ChzzkDanmakuFrame(messages: _lines(body, recent: false, receivedAt: now), pushed: true);
      case 15101 when root['retCode'] == 0 && body is Map && body['messageList'] is List:
        return ChzzkDanmakuFrame(
          messages: [
            ..._lines(body['messageList'] as List<Object?>, recent: true, receivedAt: now),
            if (_object(body['notice']) case final notice?) ?pinned(notice),
          ],
        );
      case 94010 when body is Map:
        return ChzzkDanmakuFrame(messages: [?pinned(body)]);
      case 94008 when body is Map:
        return ChzzkDanmakuFrame(messages: [?blind(body)]);
      default:
        return const ChzzkDanmakuFrame();
    }
  }

  static List<LiveMessage> _lines(List<Object?> items, {required bool recent, required DateTime receivedAt}) => [
    for (final item in items)
      if (item is Map) ...[?subscription(item, recent: recent), ?line(item, recent: recent, receivedAt: receivedAt)],
  ];

  /// The notice of a subscription line ([subscriptionType], D07.6; it was
  /// only its message as chat): a [LiveNoticeKind.subscription] notice of
  /// the subscriber (`profile.nickname`, else `extras.nickname`) with the
  /// tier's name (`extras.tierName`) and the months (`extras.month`), in
  /// Chinese around the platform's names, as [_subscriptionGift] writes a
  /// gift: `<name> 订阅了「나나양 좋아」，已订阅 32 个月`. Its id is
  /// `subscription:<user>:<time>` (the message's chat line keeps
  /// `<user>:<time>`). Null for any other line, and for one the site does
  /// not show (a status other than `NORMAL`).
  static LiveMessage? subscription(Map<Object?, Object?> item, {bool recent = false}) {
    final type = _int(item[recent ? 'messageTypeCode' : 'msgTypeCode']);
    if (type != subscriptionType) return null;
    final status = item[recent ? 'messageStatusType' : 'msgStatusType'];
    if (status != null && status != 'NORMAL') return null;
    final time = _int(item[recent ? 'messageTime' : 'msgTime']);
    final user = _scalar(item[recent ? 'userId' : 'uid']);
    final extras = _object(item['extras']) ?? const <Object?, Object?>{};
    final profile = _object(item['profile']);
    var name = _scalar(profile?['nickname']).trim();
    if (name.isEmpty) name = _scalar(extras['nickname']).trim();
    final tier = _scalar(extras['tierName']).trim();
    final months = _int(extras['month']);
    final subscribed = tier.isEmpty ? '订阅了频道' : '订阅了「$tier」';
    final text = months != null && months > 0 ? '$subscribed，已订阅 $months 个月' : subscribed;
    final sentAt = time != null && time > 0 && time <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null;
    return LiveMessage(
      type: LiveMessageType.notice,
      userName: name,
      userId: user,
      message: name.isEmpty ? text : '$name $text',
      color: LiveMessageColor.white,
      messageId: sentAt == null || user.isEmpty ? '' : 'subscription:$user:$time',
      sentAt: sentAt,
      data: LiveNoticeKind.subscription,
    );
  }

  /// One line of the chat, or null when the site does not show it.
  ///
  /// A line pushed live names its fields `msg`, `uid`, `msgTime`,
  /// `msgTypeCode` and `msgStatusType`; a [recent] one `content`, `userId`,
  /// `messageTime`, `messageTypeCode` and `messageStatusType`. Both carry
  /// `profile` and `extras` as JSON text (or objects). Only lines whose
  /// status is `NORMAL` (or missing) are read: `BLIND` and `CBOTBLIND` lines
  /// (hidden by a manager or the clean bot) still carry their text, and the
  /// site does not show it.
  ///
  /// - Text and subscriptions ([textType], [subscriptionType]; a line
  ///   without a numeric type is text, as v4 read it) are chat when their
  ///   text is not blank (a subscription's notice is [subscription]'s).
  /// - Donations ([donationType]) are super chats, subscription gifts
  ///   ([subscriptionGiftType]) and system lines ([systemType]) notices
  ///   (B-12; see [_donation], [_subscriptionGift], [_system]).
  /// - The name is `profile.nickname`, the user id `uid`; an anonymous
  ///   donation (`extras.isAnonymous`, or the user `anonymous`) is
  ///   [anonymousDonor] without a user id, as the site shows it.
  /// - The time is the milliseconds the site reads (a whole number or its
  ///   text; one not above zero or beyond [DateTime] leaves the line without
  ///   a time). The site tells lines apart by user and time, and blinds
  ///   them by user and time, so the message id is `<user>:<time>`
  ///   (`anonymous:<time>` for anonymous donors), and a line without a time
  ///   has none.
  /// - Emoji stay as `{:name:}` in the text; the ones the line's
  ///   `extras.emojis` names (`name` → picture) are its
  ///   [LiveMessage.emotes] ([emojis], M13.16). The name colour
  ///   (`nicknameColor` is a palette code) is not the text's: white.
  static LiveMessage? line(Map<Object?, Object?> item, {bool recent = false, DateTime? receivedAt}) {
    final type = _int(item[recent ? 'messageTypeCode' : 'msgTypeCode']) ?? textType;
    final status = item[recent ? 'messageStatusType' : 'msgStatusType'];
    if (status != null && status != 'NORMAL') return null;
    final time = _int(item[recent ? 'messageTime' : 'msgTime']);
    final row = (
      text: _scalar(item[recent ? 'content' : 'msg']).trim(),
      user: _scalar(item[recent ? 'userId' : 'uid']),
      time: time,
      sentAt: time != null && time > 0 && time <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null,
      profile: _object(item['profile']),
      extras: _object(item['extras']) ?? const <Object?, Object?>{},
    );
    switch (type) {
      case textType || subscriptionType:
        if (row.text.isEmpty) return null;
        return LiveMessage(
          type: LiveMessageType.chat,
          userName: _scalar(row.profile?['nickname']),
          userId: row.user,
          message: row.text,
          color: LiveMessageColor.white,
          messageId: _id(row.user, row),
          sentAt: row.sentAt,
          emotes: emojis(row.text, row.extras['emojis']),
        );
      case donationType:
        return _donation(row, receivedAt ?? DateTime.now());
      case subscriptionGiftType:
        return _subscriptionGift(row);
      case systemType:
        return _system(row);
      default:
        return null;
    }
  }

  /// The pictures of the `{:name:}` codes in [text] that [table] (a line's
  /// `extras.emojis`, `name` → address) names with an http(s) address, each
  /// once, in the order of the text.
  static List<LiveEmote> emojis(String text, Object? table) {
    if (table is! Map || table.isEmpty || !text.contains('{:')) return const [];
    final seen = <String>{};
    return [
      for (final match in _emojiCode.allMatches(text))
        if (table[match.group(1)] case final String url
            when (url.startsWith('https://') || url.startsWith('http://')) && seen.add(match.group(0)!))
          LiveEmote(code: match.group(0)!, url: url),
    ];
  }

  static final RegExp _emojiCode = RegExp(r'\{:([^{}:\s]+):\}');

  /// The message id of [row] by [user]: `<user>:<time>`, or empty without
  /// a user or a time.
  static String _id(String user, _Row row) => row.sentAt == null || user.isEmpty ? '' : '$user:${row.time}';

  /// A donation: a super chat of `extras.payAmount` 치즈 ([cheeseText]),
  /// shown for [superChatDuration] from the line's time (or [receivedAt]),
  /// with the donor's avatar (`profile.profileImageUrl`, when it is one of
  /// NAVER's images). Its message is the donor's text, the video title of a
  /// video donation or the pledge of a mission (the site shows each in its
  /// chat list); a donation with neither text nor amount shows nothing. The
  /// site colours donations by amount tier in its style sheet, not in the
  /// line: no colours.
  static LiveMessage? _donation(_Row row, DateTime receivedAt) {
    final anonymous = row.extras['isAnonymous'] == true || row.user == 'anonymous';
    final amount = max(_int(row.extras['payAmount']) ?? 0, 0);
    if (row.text.isEmpty && amount == 0) return null;
    final id = _id(anonymous ? 'anonymous' : row.user, row);
    final start = row.sentAt ?? receivedAt;
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: 'SUPER_CHAT_MESSAGE',
      message: 'SUPER_CHAT_MESSAGE',
      userId: anonymous ? '' : row.user,
      color: LiveMessageColor.white,
      messageId: id,
      sentAt: row.sentAt,
      data: LiveSuperChatMessage(
        messageId: id,
        userName: anonymous ? anonymousDonor : _scalar(row.profile?['nickname']),
        face: anonymous ? '' : ChzzkApi.image(row.profile?['profileImageUrl']),
        message: row.text,
        price: amount,
        priceText: amount > 0 ? cheeseText(amount) : '',
        unit: LiveGiftUnit.cheese,
        startTime: start,
        endTime: start.add(superChatDuration(amount)),
        backgroundColor: '',
        backgroundBottomColor: '',
      ),
    );
  }

  /// A subscription gift: a [LiveNoticeKind.subscription] notice whose text
  /// says what the site's gift line says (`live_chatting_subscription_*`),
  /// in Chinese, around the platform's names:
  /// `<giver> 向频道赠送了 5 张「팬」订阅券` for `giftType`
  /// `SUBSCRIPTION_GIFT` (`quantity`, `giftTierName`),
  /// `<giver> 向 <receiver> 赠送了「팬」订阅券` otherwise (`receiverNickname`).
  /// The giver is [anonymousDonor] when the site shows it so: a channel gift
  /// with an `anonymousToken`, a gift to a viewer without a profile, or the
  /// user `anonymous`.
  static LiveMessage? _subscriptionGift(_Row row) {
    final toChannel = row.extras['giftType'] == 'SUBSCRIPTION_GIFT';
    final anonymous =
        row.user == 'anonymous' || (toChannel ? row.extras.containsKey('anonymousToken') : row.profile == null);
    final giver = anonymous ? anonymousDonor : _scalar(row.profile?['nickname']).trim();
    final tier = _scalar(row.extras['giftTierName']).trim();
    final pass = tier.isEmpty ? '订阅券' : '「$tier」订阅券';
    final String gift;
    if (toChannel) {
      final quantity = _int(row.extras['quantity']);
      gift = quantity != null && quantity > 0 ? '向频道赠送了 $quantity 张$pass' : '向频道赠送了$pass';
    } else {
      final receiver = _scalar(row.extras['receiverNickname']).trim();
      gift = receiver.isEmpty ? '赠送了$pass' : '向 $receiver 赠送了$pass';
    }
    return LiveMessage(
      type: LiveMessageType.notice,
      userName: giver,
      userId: anonymous ? '' : row.user,
      message: giver.isEmpty ? gift : '$giver $gift',
      color: LiveMessageColor.white,
      messageId: _id(anonymous ? 'anonymous' : row.user, row),
      sentAt: row.sentAt,
      data: LiveNoticeKind.subscription,
    );
  }

  /// A system line (`SYSTEM_MESSAGE`: `이모티콘 모드 ON`, restrictions): a
  /// [LiveNoticeKind.system] notice of its text and `extras.description`,
  /// as the site shows them (title and description), joined by `：`. A line
  /// whose `extras.visibleRoles` names roles is for the streamer and the
  /// managers only (a restriction): the site shows it to no one else, and
  /// this client is anonymous.
  static LiveMessage? _system(_Row row) {
    if (row.extras['visibleRoles'] case final List<Object?> roles when roles.isNotEmpty) return null;
    final description = _scalar(row.extras['description']).trim();
    final text = [row.text, description].where((part) => part.isNotEmpty).join('：');
    if (text.isEmpty) return null;
    return LiveMessage(
      type: LiveMessageType.notice,
      userName: '',
      message: text,
      color: LiveMessageColor.white,
      messageId: _id(row.user, row),
      sentAt: row.sentAt,
      data: LiveNoticeKind.system,
    );
  }

  /// The notice pinned above the chat (the recent chat's `notice`, or the
  /// body of a `94010`), in the recent form of a line (`content`, `userId`,
  /// `messageTime`, `profile`; `extras.registerProfile` is who pinned it):
  /// a [LiveNoticeKind.system] notice that says whose line is pinned, as
  /// the site's pinned bar does (`live_chatting_fixed.*`), in Chinese:
  /// `<author> 置顶了消息：<text>` when the author pinned it,
  /// `<pinner> 置顶了 <author> 的消息：<text>` when someone else did. Its id is
  /// `notice:<user>:<time>`, never the id of the line it pins. It has no
  /// time: the line's is when it was written, not when it was pinned. A
  /// notice without a time (the site's "nothing pinned") or text is null.
  static LiveMessage? pinned(Map<Object?, Object?> notice) {
    final time = _int(notice['messageTime']);
    final text = _scalar(notice['content']).trim();
    if (time == null || time <= 0 || time > _maxMillis || text.isEmpty) return null;
    final user = _scalar(notice['userId']);
    final profile = _object(notice['profile']);
    final author = _scalar(profile?['nickname']).trim();
    final register = _object(_object(notice['extras'])?['registerProfile']);
    final pinner = _scalar(register?['nickname']).trim();
    final byAuthor = pinner.isEmpty || _scalar(register?['userIdHash']) == _scalar(profile?['userIdHash']);
    return LiveMessage(
      type: LiveMessageType.notice,
      userName: author,
      userId: user,
      message: author.isEmpty
          ? '置顶消息：$text'
          : byAuthor
          ? '$author 置顶了消息：$text'
          : '$pinner 置顶了 $author 的消息：$text',
      color: LiveMessageColor.white,
      messageId: user.isEmpty ? 'notice:$time' : 'notice:$user:$time',
      data: LiveNoticeKind.system,
    );
  }

  /// A line blinded afterwards (`94008`): `userId` and `messageTime` name
  /// it, as the site's chat finds it, so it is a retraction of the message
  /// `<user>:<time>` ([line]'s id). Every kind the site hides (`BLIND`,
  /// `CBOTBLIND`, `HIDDEN`, …) retracts; `CANCEL` shows the line again on
  /// the site, which cannot be undone here: null, as is a notice without a
  /// user or a time. When the site hides all lines of a viewer (a temporary
  /// restriction), it sends one `94008` per line.
  static LiveMessage? blind(Map<Object?, Object?> body) {
    if (body['blindType'] == 'CANCEL') return null;
    final user = _scalar(body['userId']);
    final time = _int(body['messageTime']);
    if (user.isEmpty || time == null || time <= 0 || time > _maxMillis) return null;
    return LiveMessage(
      type: LiveMessageType.retraction,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: LiveRetraction.message('$user:$time'),
    );
  }

  /// A JSON object, or the object a JSON text holds.
  static Map<Object?, Object?>? _object(Object? value) {
    if (value is Map) return value;
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// A whole number: a JSON integer or its text.
  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };

  static String _scalar(Object? value) => value is String || value is num ? '$value' : '';
}

/// The fields of one chat line that [ChzzkDanmakuProtocol.line] reads.
typedef _Row = ({
  String text,
  String user,
  int? time,
  DateTime? sentAt,
  Map<Object?, Object?>? profile,
  Map<Object?, Object?> extras,
});

/// CHZZK's danmaku connection: an access token and the session servers over
/// [LiveHttp], then the chat socket over the shared WebSocket runtime.
///
/// - At every [connect] the access token is asked up to three times (0.5 s
///   and 1 s apart) while the session servers are asked once (1.5 s at
///   most, as the site asks them); without a token the run ends with
///   [DanmakuCloseReason.credentialsUnavailable], without servers the SDK's
///   built-in list is used. Reconnects reuse both, as the site's client
///   reuses its token.
/// - The socket starts at a random server and goes round the others on
///   failure. At every open it sends the read-only join; the room counts as
///   joined when the server accepts it, and a join not answered within 5 s
///   drops the socket. Every accepted join asks the recent 50 lines.
/// - A refused join ends the run with [DanmakuCloseReason.connectionFailed]
///   (the server closes the socket after it), except the codes on which
///   the site's client connects again (302, 303, 304): those reconnect.
///   `cmd 90102` ends the run the same way.
/// - The ping goes out every 20 s and the server answers it, so a socket
///   silent for 30 s is replaced; a server ping is answered at once.
/// - Donations are super chats; subscription gifts, system lines and the
///   pinned notice are notices; a line blinded afterwards is retracted
///   (B-12). The recent chat of every join repeats lines already seen:
///   chat is left to the duplicate gate, and a super chat or notice already
///   reported in this run is not reported again.
/// - After [quietPeriod] without a line pushed live, the live-status of
///   [ChzzkDanmakuArgs.channelId] is read once; when the open live has
///   another chat channel (the streamer went live again), the connection
///   takes a token for it and moves its socket there, reporting
///   [DanmakuReady] when the new chat accepts the join. The site polls
///   live-status every 30 s; this asks only while the chat is quiet.
///
/// The app registers it as `SiteIds.chzzk: () => ChzzkDanmakuConnection(
/// http: …, proxy: …)`, with the `LiveHttp` it gives `ChzzkSite` and its
/// proxy policy.
final class ChzzkDanmakuConnection extends DanmakuSocketConnection<ChzzkDanmakuArgs> {
  /// Creates the connection; `http` asks for the token, the servers and the
  /// live's state, and [proxy] routes the socket. `connector` replaces
  /// `dart:io`'s handshake, `tokenRetryDelay` the step between token
  /// attempts, `random` the choice of the first server and `clock` the time
  /// a donation without its own is received (tests).
  new({
    required this._http,
    super.proxy,
    super.connector,
    this._tokenRetryDelay = const Duration(milliseconds: 500),
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random(),
       _clock = clock ?? DateTime.now,
       super(site: SiteIds.chzzk, policy: socketPolicy);

  /// Socket timing: the site's 20 s ping, 30 s of silence and 5 s for the
  /// join's answer; the rest are the shared runtime's defaults.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: ChzzkDanmakuProtocol.heartbeatInterval,
    inactivityTimeout: ChzzkDanmakuProtocol.inactivityTimeout,
    joinTimeout: ChzzkDanmakuProtocol.joinTimeout,
  );

  /// Requests per attempt to get an access token.
  static const int tokenAttempts = 3;

  /// Longest wait for one token answer.
  static const Duration tokenTimeout = Duration(seconds: 5);

  /// Longest wait for the routing answer: the SDK's `callTimeoutMillis`.
  static const Duration routingTimeout = Duration(milliseconds: 1500);

  /// How long the chat may go without a line pushed live before the live's
  /// state is read once. A restarted broadcast gets a new chat channel and
  /// the old one falls silent at once, while a small live's chat can be
  /// quiet for a minute or two; three minutes of silence is one request
  /// where the site makes six (it polls every 30 s).
  static const Duration quietPeriod = Duration(minutes: 3);

  /// Longest wait for the live-status answer.
  static const Duration liveStatusTimeout = Duration(seconds: 5);

  /// Most ids of super chats and notices remembered per run.
  static const int maxRemembered = 512;

  final LiveHttp _http;
  final Duration _tokenRetryDelay;
  final Random _random;
  final DateTime Function() _clock;
  _Chat? _chat;

  @override
  @protected
  Future<DanmakuSocketTarget> target(ChzzkDanmakuArgs args, DanmakuRun run) async {
    final channel = args.chatChannelId.trim();
    if (!ChzzkDanmakuProtocol.isChatChannelId(channel)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No chat channel');
    }
    final owner = args.channelId.trim();
    final chat = _chat = _Chat(run, channel, ChzzkApi.isChannelId(owner) ? owner : '');
    final servers = _servers(chat);
    final token = await _token(chat, channel);
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    if (token == null) throw DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: chat.lastFailure);
    chat.token = token;
    final hosts = chat.servers = await servers;
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    return _target(hosts);
  }

  DanmakuSocketTarget _target(List<String> hosts) => DanmakuSocketTarget(
    endpoints: ChzzkDanmakuProtocol.endpoints(hosts, _random.nextInt(hosts.length)),
    headers: ChzzkDanmakuProtocol.handshakeHeaders,
  );

  /// An access token for [channel]: up to [tokenAttempts] requests, or null
  /// when none gave one or the run ended.
  Future<String?> _token(_Chat chat, String channel) async {
    for (var attempt = 0; attempt < tokenAttempts; attempt++) {
      if (attempt > 0 && !await chat.run.delay(_tokenRetryDelay * attempt)) return null;
      try {
        final response = await _http.send(
          LiveRequest(
            site: SiteIds.chzzk,
            url: ChzzkDanmakuProtocol.tokenUrl(channel),
            headers: ChzzkApi.headers,
            followRedirects: false,
            timeout: tokenTimeout,
            cancel: chat.cancel,
          ),
        );
        if (!chat.run.isActive) return null;
        final token = response.isSuccess ? ChzzkDanmakuProtocol.accessToken(_json(response)) : null;
        if (token != null) return token;
        chat.lastFailure = response.isSuccess ? 'No chat token' : 'Chat token: HTTP ${response.status}';
      } on Object catch (error) {
        if (!chat.run.isActive) return null;
        chat.lastFailure = '$error';
      }
    }
    return null;
  }

  /// The session servers: one routing request, else the SDK's list.
  Future<List<String>> _servers(_Chat chat) async {
    try {
      final response = await _http.send(
        LiveRequest(
          site: SiteIds.chzzk,
          url: ChzzkDanmakuProtocol.routingUrl,
          headers: ChzzkApi.headers,
          followRedirects: false,
          timeout: routingTimeout,
          cancel: chat.cancel,
        ),
      );
      if (response.isSuccess) {
        if (ChzzkDanmakuProtocol.servers(_json(response)) case final servers?) return servers;
      }
    } on Object {
      // The SDK falls back to its own list as well.
    }
    return ChzzkDanmakuProtocol.defaultServers;
  }

  static Object? _json(LiveResponse response) {
    try {
      return response.json;
    } on FormatException {
      return null;
    }
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final chat = _of(session);
    if (chat != null) session.send(ChzzkDanmakuProtocol.join(chat.channel, chat.token));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = ChzzkDanmakuProtocol.decode(data, receivedAt: _clock());
    if (frame.ping) session.send(ChzzkDanmakuProtocol.pong);
    for (final message in frame.messages) {
      if (chat.isNew(message)) session.message(message);
    }
    if (frame.pushed) _awaitQuiet(chat, session);
    switch (frame.joined) {
      case true:
        if (!session.isConnected) session.ready();
        if (frame.sessionId.isNotEmpty) session.send(ChzzkDanmakuProtocol.recent(chat.channel, frame.sessionId));
        _awaitQuiet(chat, session);
      case false:
        session
          ..cancelJoinTimeout()
          ..markDisconnected();
        if (frame.retry) {
          session.reconnect();
        } else {
          session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Join refused: ${frame.refusal}'.trim());
        }
      case null:
        break;
    }
    if (frame.closed) session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Closed by the server');
  }

  /// (Re)starts the wait for a quiet chat; nothing without a channel id.
  void _awaitQuiet(_Chat chat, DanmakuSocketSession session) {
    chat.quiet?.cancel();
    chat.quiet = null;
    if (chat.owner.isEmpty || !session.isActive) return;
    chat.quiet = Timer(quietPeriod, () => unawaited(_checkLive(chat, session)));
  }

  /// The chat was quiet for [quietPeriod]: reads the live's state once and
  /// moves to its chat channel when that changed; otherwise waits again.
  Future<void> _checkLive(_Chat chat, DanmakuSocketSession session) async {
    chat.quiet = null;
    if (chat.checking || !session.isActive) return;
    chat.checking = true;
    try {
      String? next;
      try {
        final response = await _http.send(
          LiveRequest(
            site: SiteIds.chzzk,
            url: ChzzkDanmakuProtocol.liveStatusUrl(chat.owner),
            headers: ChzzkApi.headers,
            followRedirects: false,
            timeout: liveStatusTimeout,
            cancel: chat.cancel,
          ),
        );
        if (response.isSuccess) next = ChzzkDanmakuProtocol.liveChatChannel(_json(response));
      } on Object {
        // Asked again after the next quiet period.
      }
      if (!session.isActive) return;
      final token = next == null || next == chat.channel ? null : await _token(chat, next);
      if (!session.isActive) return;
      if (next == null || token == null) {
        if (chat.quiet == null) _awaitQuiet(chat, session);
        return;
      }
      chat
        ..channel = next
        ..token = token;
      session.markDisconnected();
      await session.reopen(_target(chat.servers));
    } finally {
      chat.checking = false;
    }
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => ChzzkDanmakuProtocol.ping;

  @override
  @protected
  Future<void> stop() async {
    _chat?.quiet?.cancel();
    _chat = null;
    await super.stop();
  }
}

/// The chat of one run: its channel, token, servers and requests.
final class _Chat {
  new(this.run, this.channel, this.owner) {
    unawaited(
      run.ended.then((_) {
        cancel.cancel();
        quiet?.cancel();
      }),
    );
  }

  final DanmakuRun run;

  /// The chat channel joined; another one when the live moved.
  String channel;

  /// The room's channel id, whose live-status names the chat; empty when
  /// the arguments had none.
  final String owner;

  final CancelToken cancel = CancelToken();
  String token = '';
  List<String> servers = ChzzkDanmakuProtocol.defaultServers;
  String lastFailure = '';

  /// The wait for a quiet chat ([ChzzkDanmakuConnection.quietPeriod]).
  Timer? quiet;

  /// A live-status check is under way.
  bool checking = false;

  final Set<String> _reported = {};

  /// Whether [message] is to be reported: chat (the duplicate gate sees
  /// it) and messages without an id always; a super chat or notice once
  /// per run, as the recent chat of every join repeats them.
  bool isNew(LiveMessage message) {
    if (message.type == LiveMessageType.chat || message.messageId.isEmpty) return true;
    if (!_reported.add(message.messageId)) return false;
    if (_reported.length > ChzzkDanmakuConnection.maxRemembered) _reported.remove(_reported.first);
    return true;
  }
}
