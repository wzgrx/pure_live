import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one PandaTV chat frame held ([PandaLiveDanmakuProtocol.decode]).
@immutable
final class PandaLiveDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.joined = false, this.refusal, this.expiresIn});

  /// Chat, in order.
  final List<LiveMessage> messages;

  /// The server accepted the subscription (the reply to command 2).
  final bool joined;

  /// The server answered the connect or the subscription with an error
  /// (`connect: 109 token expired`), or null.
  final String? refusal;

  /// When the connection's token lapses, from the connect reply
  /// (`expires`, `ttl`); null when it does not say.
  final Duration? expiresIn;
}

/// `live/play` refused the broadcast (ended, adult, password, fans only, not
/// live): its chat cannot be joined.
final class PandaLiveChatRefusal implements Exception {
  /// Creates the refusal with `errorData.code` [code] (empty without one).
  const new(this.code);

  /// `errorData.code` (`castEnd`, `needAdult`, `needLogin`, …), `not live`
  /// for an accepted answer whose broadcast is not live, or empty.
  final String code;

  @override
  String toString() => 'live/play: ${code.isEmpty ? 'refused' : code}';
}

/// PandaTV's chat (the archived v4's spec/sites/pandalive.md §7, checked
/// against the recording `fixtures/pandalive/danmaku/S07-live` and a
/// read-only session of 2026-09-29; docs/T06/T06a/T06a.22/record.md),
/// without I/O.
///
/// - A Centrifugo 3 server ([endpoint]) speaking its JSON protocol: every
///   command carries an `id` its reply echoes, and one frame may hold
///   several newline-separated replies and pushes.
/// - The client connects with the guest token of the broadcast's
///   `live/play` (a JWT of 30 minutes) and subscribes to its channel (the
///   broadcaster's number). The server closes a socket whose token is not
///   valid (close code 3002, `invalid token`).
/// - It pings with command 7 every 25 s; the server answers every ping.
/// - A publication on the channel is a push without an id, `{"result":
///   {"channel": …, "data": {"data": …, "offset": …}}}`; the inner `data` is
///   the message, whose `type` says what it is (`chatter`, `bj`, `manager`
///   and `support` are chat).
abstract final class PandaLiveDanmakuProtocol {
  /// The chat socket (`PandaLiveApi.chatServer`, the website's
  /// `newChat.node`).
  static Uri get endpoint => PandaLiveApi.chatServer;

  /// Where a chat token is issued: the broadcast's `live/play`.
  static final Uri playUrl = Uri.https(PandaLiveApi.apiHost, '/v1/live/play');

  /// Ping period (centrifuge-js's default, the archived v4 and the
  /// recording).
  static const Duration heartbeatInterval = Duration(seconds: 25);

  /// How long the connect and subscribe replies may take (the archived v4's
  /// 8 s; they came within 0.4 s).
  static const Duration joinTimeout = Duration(seconds: 8);

  /// How long before a token lapses it is replaced: a handshake does not use
  /// a token that lapses sooner, and a joined socket is renewed this long
  /// before the server's `ttl` runs out.
  static const Duration renewalLead = Duration(seconds: 60);

  /// Refused joins in a row after which the connection gives up (the
  /// archived v4's `maxRejections`).
  static const int maxRefusals = 3;

  /// Handshake headers: the site's origin and the adapter's desktop UA, as
  /// the website and the archived v4 sent them (the server also accepts a
  /// handshake without them).
  static const Map<String, String> socketHeaders = {
    'origin': PandaLiveApi.origin,
    'user-agent': PandaLiveApi.userAgent,
  };

  /// The id of the connect command.
  static const int connectId = 1;

  /// The id of the subscribe command; pings count on from it.
  static const int subscribeId = 2;

  /// Message types that are chat (the website's `isNormalChatMessage`).
  static const Set<String> chatTypes = {'bj', 'chatter', 'manager', 'support'};

  /// Largest [DateTime], in seconds.
  static const int _maxEpochSeconds = 8640000000000;

  static final RegExp _channel = RegExp(r'^[0-9]{1,19}$');

  /// Printable ASCII without spaces: a token goes into a JSON command.
  static final RegExp _token = RegExp(r'^[!-~]{1,4096}$');

  /// The connect command with [token].
  static String connect(String token) => jsonEncode({
    'params': {'token': token, 'name': 'js'},
    'id': connectId,
  });

  /// The subscribe command for [channel].
  static String subscribe(String channel) => jsonEncode({
    'method': 1,
    'params': {'channel': channel},
    'id': subscribeId,
  });

  /// The ping command with id [id].
  static String ping(int id) => jsonEncode({'method': 7, 'id': id});

  /// The `live/play` request of broadcaster [userId] as room entry sends it
  /// (`PandaLiveSite`): the form of `PandaLiveApi.playForm`, the adapter's
  /// headers with the live page as Referer, the content type without a
  /// charset, no redirect followed; sent as `pandalive` (its proxy route).
  static LiveRequest playRequest(String userId, {Duration timeout = defaultRequestTimeout, CancelToken? cancel}) =>
      LiveRequest(
        site: SiteIds.pandaLive,
        url: playUrl,
        method: 'POST',
        headers: {
          ...PandaLiveApi.headers(PandaLiveApi.roomUrl(userId)),
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: LiveRequest.form(site: SiteIds.pandaLive, url: playUrl, fields: PandaLiveApi.playForm(userId)).body,
        followRedirects: false,
        timeout: timeout,
        cancel: cancel,
      );

  /// The chat channel and token of a `live/play` [response]. A refusal (HTTP
  /// 400 with `result: false`, or an accepted broadcast that is not live)
  /// throws [PandaLiveChatRefusal]; an answer that cannot be read throws its
  /// `SiteError` (`PandaLiveApi.answer`) or [FormatException] (no numeric
  /// channel or no token).
  static ({String channel, String token}) grant(LiveResponse response) {
    final data = PandaLiveApi.answer(response.text, what: 'live/play', status: response.status);
    if (data['result'] != true) throw PandaLiveChatRefusal(PandaLiveApi.refusalCode(data));
    final media = data['media'];
    if (media is Map && PandaLiveApi.flag(media['isLive']) == false) throw const PandaLiveChatRefusal('not live');
    final channel = jsonString(data['channel']);
    final token = data['token'];
    if (channel == null || !_channel.hasMatch(channel) || token is! String || !_token.hasMatch(token)) {
      throw const FormatException('live/play: no chat channel or token');
    }
    return (channel: channel, token: token);
  }

  /// When JWT [token] lapses (its payload's `exp`), or null when it does not
  /// say.
  static DateTime? tokenExpiry(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      return exp is int && exp > 0 && exp <= _maxEpochSeconds
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
          : null;
    } on FormatException {
      return null;
    }
  }

  /// When a joined socket whose token lapses in [ttl] is renewed:
  /// [renewalLead] before, or halfway for a token shorter than twice that.
  static Duration renewalDelay(Duration ttl) => ttl > renewalLead * 2 ? ttl - renewalLead : ttl ~/ 2;

  /// [args] if they name a chat: a broadcaster id (`PandaLiveApi
  /// .normalizeUserId`) and a numeric channel, trimmed; a token that is not
  /// printable ASCII without spaces is dropped (a new one is asked for).
  /// Null otherwise.
  static PandaLiveDanmakuArgs? checked(PandaLiveDanmakuArgs args) {
    final userId = PandaLiveApi.normalizeUserId(args.userId);
    final channel = args.channel.trim();
    if (userId == null || !_channel.hasMatch(channel)) return null;
    final token = args.token?.trim();
    return PandaLiveDanmakuArgs(
      userId: userId,
      channel: channel,
      token: token != null && _token.hasMatch(token) ? token : null,
    );
  }

  /// One frame (text, or UTF-8 bytes) on [channel]: each line one JSON
  /// reply or push.
  ///
  /// - The reply to the subscription joins; an error reply to the connect or
  ///   the subscription is a [PandaLiveDanmakuFrame.refusal]; the connect
  ///   reply says when the token lapses. Ping replies say nothing.
  /// - A publication on [channel] (a push without `type`) whose message is
  ///   chat ([chat]) is reported; other channels, other pushes (join, leave,
  ///   unsubscribe) and other messages give nothing.
  /// - A line that is not a JSON object is skipped.
  static PandaLiveDanmakuFrame decode(Object? data, {required String channel}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const PandaLiveDanmakuFrame();
    final messages = <LiveMessage>[];
    var joined = false;
    String? refusal;
    Duration? expiresIn;
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      final Object? reply;
      try {
        reply = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (reply is! Map) continue;
      final id = reply['id'];
      if (id != null) {
        if (id != connectId && id != subscribeId) continue;
        final error = reply['error'];
        if (error != null) {
          refusal ??= '${id == connectId ? 'connect' : 'subscribe'}: ${_error(error)}';
        } else if (id == subscribeId) {
          joined = true;
        } else if (reply['result'] case {'expires': true, 'ttl': final int ttl} when ttl > 0) {
          expiresIn = Duration(seconds: ttl);
        }
        continue;
      }
      final result = reply['result'];
      if (result is! Map || result['type'] != null || jsonString(result['channel']) != channel) continue;
      if (chat(result['data'], channel: channel) case final LiveMessage message) messages.add(message);
    }
    return PandaLiveDanmakuFrame(messages: messages, joined: joined, refusal: refusal, expiresIn: expiresIn);
  }

  static String _error(Object? error) => error is Map ? '${error['code']} ${error['message']}'.trim() : '$error';

  /// A publication (`{"data": <message>, "offset"}`) on [channel] as white
  /// chat, or null when its message is not chat:
  ///
  /// - the type is one of [chatTypes];
  /// - the text is `message` trimmed; without text, an emoticon's name in
  ///   brackets (`[pandaS하트다발png]`, as the archived v4 showed an
  ///   emoticon-only message); neither: null;
  /// - the name is `nk`, the user id `id` (the login id);
  /// - the message id is `<channel>:<offset>`, the publication's place in
  ///   the channel;
  /// - the time is `created_at` (seconds); not positive or out of
  ///   `DateTime`'s range: none.
  ///
  /// `idx`, `ip`, `sex`, `lang`, the translation fields and `filtered` are
  /// not read.
  static LiveMessage? chat(Object? publication, {required String channel}) {
    if (publication is! Map) return null;
    final message = publication['data'];
    if (message is! Map || !chatTypes.contains(message['type'])) return null;
    var text = _text(message['message']);
    if (text.isEmpty) text = _emoticon(message['emoticon']);
    if (text.isEmpty) return null;
    final offset = publication['offset'];
    final created = message['created_at'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _text(message['nk']),
      userId: _text(message['id']),
      message: text,
      messageId: offset is int && offset >= 0 ? '$channel:$offset' : '',
      sentAt: created is int && created > 0 && created <= _maxEpochSeconds
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
      color: LiveMessageColor.white,
    );
  }

  /// The first named emoticon of `emoticon` (`{"block": {name, img, …},
  /// "inline": […]}`) in brackets, or empty.
  static String _emoticon(Object? emoticon) {
    if (emoticon is! Map) return '';
    for (final value in emoticon.values) {
      final name = value is Map ? _text(value['name']) : '';
      if (name.isNotEmpty) return '[$name]';
    }
    return '';
  }

  static String _text(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => '$number',
    _ => '',
  };
}

/// PandaTV's chat connection (new in v4: 3.x had none, the 25-2 upgrade),
/// on the WebSocket runtime: one socket to [PandaLiveDanmakuProtocol
/// .endpoint], joined with a `live/play` guest token.
///
/// - The first handshake uses the token room entry brought
///   (`PandaLiveDanmakuArgs.token`) unless it lapses within a minute; every
///   other handshake first asks `live/play` again for a new token and
///   channel, as the website does on every visit. A request that fails
///   counts as a failed handshake (the runtime's backoff and its eight
///   attempts); a refusal (the broadcast ended, adult, password, fans only)
///   ends the connection with [DanmakuCloseReason.connectionFailed].
/// - At every open it sends connect and subscribe; the subscription's reply
///   joins. A refused connect or subscription reconnects with a new token,
///   more than three in a row end the connection.
/// - A joined socket is renewed quietly a minute before its token lapses (the
///   connect reply's `ttl`, 30 minutes): a new token, then a new socket, with
///   no notice and no second [DanmakuReady].
/// - Command 7 pings every 25 s; the server answers each.
/// - Only chat is reported.
///
/// The app registers it as `SiteIds.pandaLive: () =>
/// PandaLiveDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `PandaLiveSite` (proxy route by the platform id) and its proxy
/// policy for the socket.
final class PandaLiveDanmakuConnection extends DanmakuSocketConnection<PandaLiveDanmakuArgs> {
  /// Creates the connection. [http] asks `live/play` for tokens; [proxy]
  /// routes the socket; [connector] replaces `dart:io`'s handshake,
  /// [policy] the timing and [now] the clock the token's expiry is read
  /// against (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    DateTime Function()? now,
  }) => PandaLiveDanmakuConnection._(
    _Handshake(http, connector ?? connectIoSocket, now ?? DateTime.now),
    proxy: proxy,
    policy: policy,
  );

  new _(this._handshake, {required super.proxy, required super.policy})
    : super(site: SiteIds.pandaLive, connector: _handshake.call);

  /// The platform's timing: the 25 s ping and the 8 s join limit; the
  /// runtime's defaults otherwise (the silence watchdog at 90 s).
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: PandaLiveDanmakuProtocol.heartbeatInterval,
    joinTimeout: PandaLiveDanmakuProtocol.joinTimeout,
  );

  static final DanmakuSocketTarget _target = DanmakuSocketTarget(
    endpoints: [PandaLiveDanmakuProtocol.endpoint],
    headers: PandaLiveDanmakuProtocol.socketHeaders,
  );

  final _Handshake _handshake;

  @override
  @protected
  Future<DanmakuSocketTarget> target(PandaLiveDanmakuArgs args, DanmakuRun run) async {
    final checked = PandaLiveDanmakuProtocol.checked(args);
    if (checked == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable broadcaster or channel');
    }
    _handshake.chat = _Chat(run, checked.userId, checked.channel, checked.token);
    return _target;
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _handshake.chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final chat = _of(session);
    if (chat == null) return;
    chat
      ..socketReset()
      ..sockets += 1
      ..fresh = false;
    // A renewal keeps the room joined, so the runtime's join timer does not
    // run; this one does its work.
    if (session.isConnected) {
      final limit = policy.joinTimeout ?? PandaLiveDanmakuProtocol.joinTimeout;
      chat.joinWatch = Timer(limit, () {
        if (session.isActive && !chat.joined) session.reconnect();
      });
    }
    // The handshake made sure of a token; without one the join times out.
    final token = chat.token;
    if (token == null) return;
    session
      ..send(PandaLiveDanmakuProtocol.connect(token))
      ..send(PandaLiveDanmakuProtocol.subscribe(chat.channel));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = PandaLiveDanmakuProtocol.decode(data, channel: chat.channel);
    if (frame.refusal case final refusal?) {
      _refused(session, chat, refusal);
      return;
    }
    if (frame.expiresIn case final ttl?) {
      chat.renewal?.cancel();
      chat.renewal = Timer(PandaLiveDanmakuProtocol.renewalDelay(ttl), () => unawaited(_renew(session, chat)));
    }
    if (frame.joined && !chat.joined) {
      chat
        ..joined = true
        ..refusals = 0
        ..joinWatch?.cancel();
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
  }

  void _refused(DanmakuSocketSession session, _Chat chat, String refusal) {
    chat.socketReset();
    if (++chat.refusals > PandaLiveDanmakuProtocol.maxRefusals) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: $refusal');
      return;
    }
    session.reconnect();
  }

  /// The token of the joined socket lapses soon: a new token, then a new
  /// socket. A refusal has ended the connection; another failure leaves the
  /// socket to the server, which closes it when the token lapses, and the
  /// reconnect asks again. A socket that opened meanwhile (the old one
  /// dropped) is kept; the new token waits for the next handshake.
  Future<void> _renew(DanmakuSocketSession session, _Chat chat) async {
    chat.renewal = null;
    if (!session.isActive) return;
    final sockets = chat.sockets;
    try {
      await _handshake.renew(chat, timeout: policy.connectTimeout);
    } on Object {
      return;
    }
    if (session.isActive && chat.sockets == sockets) await session.reopen(_target);
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) {
    final chat = _of(session);
    return chat == null ? null : PandaLiveDanmakuProtocol.ping(++chat.commandId);
  }

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.dispose();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [PandaLiveDanmakuConnection]: asks `live/play` for a
/// token first when the run's token is spent or lapsing, then connects.
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
    return await _connect(
      endpoint,
      headers: headers,
      protocols: protocols,
      route: route,
      connectTimeout: connectTimeout,
    );
  }

  /// Whether [chat]'s token has not been sent yet and does not lapse within
  /// [PandaLiveDanmakuProtocol.renewalLead].
  bool _usable(_Chat chat) {
    final token = chat.token;
    if (token == null || !chat.fresh) return false;
    final expiry = PandaLiveDanmakuProtocol.tokenExpiry(token);
    return expiry == null || expiry.difference(_now()) > PandaLiveDanmakuProtocol.renewalLead;
  }

  /// Asks `live/play` for a new token and channel of [chat]'s broadcaster. A
  /// refusal ends the run; every failure is thrown.
  Future<void> renew(_Chat chat, {required Duration timeout}) async {
    final response = await _http.send(
      PandaLiveDanmakuProtocol.playRequest(chat.userId, timeout: timeout, cancel: chat.cancel),
    );
    final ({String channel, String token}) grant;
    try {
      grant = PandaLiveDanmakuProtocol.grant(response);
    } on PandaLiveChatRefusal catch (refusal) {
      chat.run.closed(DanmakuCloseReason.connectionFailed, detail: '$refusal');
      rethrow;
    }
    if (!chat.run.isActive) throw StateError('The chat was closed');
    chat
      ..channel = grant.channel
      ..token = grant.token
      ..fresh = true;
  }
}

/// One run's chat: the broadcaster, its channel and token, and the state of
/// the current socket.
final class _Chat {
  new(this.run, this.userId, this.channel, this.token) : fresh = token != null {
    unawaited(run.ended.then((_) => dispose()));
  }

  final DanmakuRun run;
  final String userId;
  final CancelToken cancel = CancelToken();

  /// The channel subscribed to.
  String channel;

  /// The token of the next connect.
  String? token;

  /// Whether [token] has not been sent on a socket yet.
  bool fresh;

  /// Joins refused in a row.
  int refusals = 0;

  /// Sockets opened so far.
  int sockets = 0;

  /// The last command id of the current socket.
  int commandId = PandaLiveDanmakuProtocol.subscribeId;

  /// Whether the current socket's subscription was accepted.
  bool joined = false;

  /// Renews the current socket before its token lapses.
  Timer? renewal;

  /// The join limit of a renewed socket.
  Timer? joinWatch;

  /// A new socket: nothing sent, nothing joined, no timers.
  void socketReset() {
    commandId = PandaLiveDanmakuProtocol.subscribeId;
    joined = false;
    renewal?.cancel();
    renewal = null;
    joinWatch?.cancel();
    joinWatch = null;
  }

  void dispose() {
    socketReset();
    cancel.cancel();
  }
}
