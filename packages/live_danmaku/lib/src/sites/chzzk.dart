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
    this.joined,
    this.sessionId = '',
    this.refusal = '',
    this.retry = false,
    this.ping = false,
    this.closed = false,
  });

  /// Chat lines, in order.
  final List<LiveMessage> messages;

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

/// CHZZK's chat (docs/modules/M5.16-chzzk.md), without I/O.
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
///   and a server ping is answered the same way.
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

  /// Message kinds (`msgTypeCode`, `messageTypeCode`) shown as chat: text,
  /// a donation's message and a subscription's message. Images, stickers,
  /// subscription gifts, parties, shop purchases and system lines are not.
  static const int textType = 1;

  /// A donation (`치즈 후원`), whose text is the donor's message or the
  /// title of the video it pays for.
  static const int donationType = 10;

  /// A subscription, whose text is the subscriber's message.
  static const int subscriptionType = 11;

  /// The name the site shows for an anonymous donor (its `익명의 후원자`).
  static const String anonymousDonor = '익명의 후원자';

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

  /// Reads one frame of a chat socket: text, or UTF-8 bytes (malformed
  /// bytes become U+FFFD).
  ///
  /// The frame's JSON object is named by `cmd`:
  ///
  /// - `0`: the server's ping ([ChzzkDanmakuFrame.ping]);
  /// - `10100`: the answer to the join; `retCode 0` accepts it
  ///   ([ChzzkDanmakuFrame.joined], with `bdy.sid`), anything else refuses
  ///   it (`retCode` and `retMsg` in [ChzzkDanmakuFrame.refusal]);
  /// - `93101` (chat) and `93102` (lines the server sends on its own:
  ///   donations, subscriptions, system lines): `bdy` lists the lines
  ///   ([chat]);
  /// - `15101` with `retCode 0`: the recent chat, `bdy.messageList`, in
  ///   the recent form of [chat];
  /// - `90102`: the server ended the session ([ChzzkDanmakuFrame.closed]).
  ///
  /// Everything else (the pong `10000`, events `93006`, blind notices
  /// `94008`, notices `94010`, penalties) holds nothing to show; so does a
  /// frame that is not a JSON object. A field of the wrong type costs only
  /// that field or that line, never the frame. The member count of every
  /// line (`mbrCnt`, `memberCount`, and `userCount` of the recent chat)
  /// counts the chat's connections, not the audience, and is not read.
  static ChzzkDanmakuFrame decode(Object? data) {
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
        return ChzzkDanmakuFrame(messages: _lines(body, recent: false));
      case 15101 when root['retCode'] == 0 && body is Map && body['messageList'] is List:
        return ChzzkDanmakuFrame(messages: _lines(body['messageList'] as List<Object?>, recent: true));
      default:
        return const ChzzkDanmakuFrame();
    }
  }

  static List<LiveMessage> _lines(List<Object?> items, {required bool recent}) => [
    for (final item in items)
      if (item is Map) ?chat(item, recent: recent),
  ];

  /// One chat line, or null when it is not shown.
  ///
  /// A line pushed live names its fields `msg`, `uid`, `msgTime`,
  /// `msgTypeCode` and `msgStatusType`; a [recent] one `content`, `userId`,
  /// `messageTime`, `messageTypeCode` and `messageStatusType`. Both carry
  /// `profile` and `extras` as JSON text (or objects).
  ///
  /// - Shown: text, donations and subscriptions ([textType],
  ///   [donationType], [subscriptionType]; a line without a numeric type
  ///   is text, as v4 read it)
  ///   whose status is `NORMAL` (or missing) and whose text is not blank.
  ///   `BLIND` and `CBOTBLIND` lines (hidden by a manager or the clean bot)
  ///   still carry their text, and the site does not show it.
  /// - The name is `profile.nickname`, the user id `uid`; an anonymous
  ///   donation (`extras.isAnonymous`, or the user `anonymous`) is
  ///   [anonymousDonor] without a user id, as the site shows it.
  /// - The time is the milliseconds the site reads (a whole number or its
  ///   text; one not above zero or beyond [DateTime] leaves the line without
  ///   a time). The site tells lines apart by user and time, so the message
  ///   id is `<user>:<time>` (`anonymous:<time>` for anonymous donors), and
  ///   a line without a time has none.
  /// - Emoji stay as `{:name:}` in the text. The name colour (`nicknameColor`
  ///   is a palette code) is not the text's: white.
  static LiveMessage? chat(Map<Object?, Object?> item, {bool recent = false}) {
    final type = _int(item[recent ? 'messageTypeCode' : 'msgTypeCode']) ?? textType;
    if (type != textType && type != donationType && type != subscriptionType) return null;
    final status = item[recent ? 'messageStatusType' : 'msgStatusType'];
    if (status != null && status != 'NORMAL') return null;
    final text = _scalar(item[recent ? 'content' : 'msg']).trim();
    if (text.isEmpty) return null;
    final user = _scalar(item[recent ? 'userId' : 'uid']);
    final extras = _object(item['extras']);
    final anonymous = type == donationType && (extras?['isAnonymous'] == true || user == 'anonymous');
    final time = _int(item[recent ? 'messageTime' : 'msgTime']);
    final sentAt = time != null && time > 0 && time <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null;
    final id = anonymous ? 'anonymous' : user;
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: anonymous ? anonymousDonor : _scalar(_object(item['profile'])?['nickname']),
      userId: anonymous ? '' : user,
      message: text,
      color: LiveMessageColor.white,
      messageId: sentAt == null || id.isEmpty ? '' : '$id:$time',
      sentAt: sentAt,
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
///
/// [ChzzkDanmakuArgs.channelId] is not needed: a live's chat is its
/// `chatChannelId`. The app registers it as `SiteIds.chzzk: () =>
/// ChzzkDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it gives
/// `ChzzkSite` and its proxy policy.
final class ChzzkDanmakuConnection extends DanmakuSocketConnection<ChzzkDanmakuArgs> {
  /// Creates the connection; `http` asks for the token and the servers, and
  /// [proxy] routes the socket. `connector` replaces `dart:io`'s handshake,
  /// `tokenRetryDelay` the step between token attempts and `random` the
  /// choice of the first server (tests).
  new({
    required this._http,
    super.proxy,
    super.connector,
    this._tokenRetryDelay = const Duration(milliseconds: 500),
    Random? random,
  }) : _random = random ?? Random(),
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

  final LiveHttp _http;
  final Duration _tokenRetryDelay;
  final Random _random;
  _Chat? _chat;

  @override
  @protected
  Future<DanmakuSocketTarget> target(ChzzkDanmakuArgs args, DanmakuRun run) async {
    final channel = args.chatChannelId.trim();
    if (!ChzzkDanmakuProtocol.isChatChannelId(channel)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No chat channel');
    }
    final chat = _chat = _Chat(run, channel);
    final servers = _servers(chat);
    final token = await _token(chat);
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    if (token == null) throw DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: chat.lastFailure);
    chat.token = token;
    final hosts = await servers;
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    return DanmakuSocketTarget(
      endpoints: ChzzkDanmakuProtocol.endpoints(hosts, _random.nextInt(hosts.length)),
      headers: ChzzkDanmakuProtocol.handshakeHeaders,
    );
  }

  /// An access token for [chat]: up to [tokenAttempts] requests, or null
  /// when none gave one or the run ended.
  Future<String?> _token(_Chat chat) async {
    for (var attempt = 0; attempt < tokenAttempts; attempt++) {
      if (attempt > 0 && !await chat.run.delay(_tokenRetryDelay * attempt)) return null;
      try {
        final response = await _http.send(
          LiveRequest(
            site: SiteIds.chzzk,
            url: ChzzkDanmakuProtocol.tokenUrl(chat.channel),
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
    final frame = ChzzkDanmakuProtocol.decode(data);
    if (frame.ping) session.send(ChzzkDanmakuProtocol.pong);
    frame.messages.forEach(session.message);
    switch (frame.joined) {
      case true:
        if (!session.isConnected) session.ready();
        if (frame.sessionId.isNotEmpty) session.send(ChzzkDanmakuProtocol.recent(chat.channel, frame.sessionId));
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

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => ChzzkDanmakuProtocol.ping;

  @override
  @protected
  Future<void> stop() async {
    _chat = null;
    await super.stop();
  }
}

/// The chat of one run: its channel, token and requests.
final class _Chat {
  new(this.run, this.channel) {
    unawaited(run.ended.then((_) => cancel.cancel()));
  }

  final DanmakuRun run;
  final String channel;
  final CancelToken cancel = CancelToken();
  String token = '';
  String lastFailure = '';
}
