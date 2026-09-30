import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What an Ably protocol message of a 17LIVE chat socket asks of the
/// connection ([SeventeenLiveDanmakuFrame.signal]).
enum SeventeenLiveSignal {
  /// Nothing: a heartbeat (`action 0`), a presence sync, another channel's
  /// message, a frame that cannot be read.
  none,

  /// `CONNECTED` (4): the socket may attach the channel now.
  connected,

  /// `ATTACHED` (11) for the room's channel: joined.
  attached,

  /// `DETACHED` (13) for the room's channel, sent by the server: the
  /// channel has to be attached again.
  detached,

  /// `DISCONNECTED` (6): the server drops the socket; a new one follows.
  disconnected,

  /// `ERROR` (9) of the connection: fatal unless it is a token error.
  connectionError,

  /// `ERROR` (9) of the room's channel: the channel failed.
  channelError,

  /// `AUTH` (17): the server asks for a new token on this socket.
  reauthorize,
}

/// An Ably error (`{"code":40142,"statusCode":401,"message":…}`).
@immutable
final class SeventeenLiveAblyError {
  /// Creates the error.
  const new({required this.code, this.statusCode, this.message = ''});

  /// Ably's error code; 0 when the frame gave none.
  final int code;

  /// Its HTTP status, when given.
  final int? statusCode;

  /// Its message, when given.
  final String message;

  /// A token error (40140 to 40149: token expired, revoked, unrecognised…):
  /// a new token fixes it (ably-js's `isTokenErr`).
  bool get isTokenError => code >= 40140 && code < 40150;

  @override
  bool operator ==(Object other) =>
      other is SeventeenLiveAblyError &&
      other.code == code &&
      other.statusCode == statusCode &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, statusCode, message);

  @override
  String toString() => '$code $message'.trim();
}

/// What one 17LIVE chat frame held ([SeventeenLiveDanmakuProtocol.decode]).
@immutable
final class SeventeenLiveDanmakuFrame {
  /// Creates the result.
  const new({this.signal = SeventeenLiveSignal.none, this.error, this.messages = const []});

  /// What the frame asks of the connection.
  final SeventeenLiveSignal signal;

  /// The error a `DISCONNECTED`, `DETACHED` or `ERROR` carried, or null.
  final SeventeenLiveAblyError? error;

  /// Chat and audience figures of a `MESSAGE`, in order.
  final List<LiveMessage> messages;
}

/// `messenger/auth` answered with another push service than Ably: the chat
/// cannot be joined.
final class SeventeenLiveChatRefusal implements Exception {
  /// Creates the refusal for `provider` [provider].
  const new(this.provider);

  /// The answer's `provider` (the website's enum: 1 Ably, 2 PubNub), as
  /// text; empty when the answer named none.
  final String provider;

  @override
  String toString() => 'messenger/auth: provider ${provider.isEmpty ? 'missing' : provider}';
}

/// 17LIVE's chat (the archived v4's spec/sites/17live.md §7, checked
/// against the recordings `fixtures/17live/danmaku/S05-live`, `S06-live`,
/// the website's scripts and read-only sessions of 2026-09-28 to 09-30;
/// docs/modules/M5.29-17live.md), without I/O.
///
/// - The website's push service is Ably (ably-js with `environment:
///   "17media"`). An anonymous token comes from `POST messenger/auth`
///   ([authRequest], [grant]); the socket is Ably's JSON realtime protocol
///   ([endpoints], [withToken]).
/// - After `CONNECTED` the client attaches the room's channel, named by the
///   room id ([attach]); `ATTACHED` joins it. The server sends a heartbeat
///   every 15 s; the client sends none.
/// - A `MESSAGE` (15) holds messages whose `data` is JSON, gzipped and
///   base64-encoded (the website's `gzip_base64`); its `type` is the
///   website's message enum: 3 a comment, 38 the live figures ([message]).
abstract final class SeventeenLiveDanmakuProtocol {
  /// The token source; the website's ably-js asks it in its `authCallback`.
  static final Uri authUrl = Uri.https(SeventeenLiveApi.apiHost, '/api/v1/messenger/auth');

  /// `messenger/auth`'s `provider` for Ably; the website's `PUBNUB` is 2.
  static const int ablyProvider = 1;

  /// The realtime host of ably-js's `environment: "17media"`.
  static const String primaryHost = '17media.realtime.ably.net';

  /// The website's `fallbackHosts`, tried after the primary host fails.
  static const List<String> fallbackHosts = [
    '17-media-a-fallback.ably-realtime.com',
    '17-media-b-fallback.ably-realtime.com',
    '17-media-c-fallback.ably-realtime.com',
  ];

  /// The sockets, primary host first, without their token ([withToken]):
  /// the JSON protocol, version 3, with server heartbeats.
  static final List<Uri> endpoints = List.unmodifiable([
    for (final host in [primaryHost, ...fallbackHosts])
      Uri(scheme: 'wss', host: host, path: '/', queryParameters: {'format': 'json', 'heartbeats': 'true', 'v': '3'}),
  ]);

  /// Handshake headers: the website's origin and the platform's desktop UA,
  /// as the recordings sent them.
  static const Map<String, String> handshakeHeaders = {
    'origin': SeventeenLiveApi.origin,
    'user-agent': SeventeenLiveApi.userAgent,
  };

  /// The server's heartbeat period (`CONNECTED`'s `maxIdleInterval`, 15 000
  /// ms in every recording). The client sends no heartbeat; this is the tick
  /// of the silence watchdog.
  static const Duration heartbeatInterval = Duration(seconds: 15);

  /// Silence after which the socket is replaced: ably-js's idle limit,
  /// `maxIdleInterval` plus its `realtimeRequestTimeout` (10 s).
  static const Duration inactivityTimeout = Duration(seconds: 25);

  /// How long the attach may take: ably-js's `realtimeRequestTimeout`.
  static const Duration joinTimeout = Duration(seconds: 10);

  /// Refusals in a row (token errors and server-sent detaches) after which
  /// the chat gives up; an attached channel starts the count again.
  static const int maxRefusals = 3;

  /// The largest token taken from `messenger/auth`.
  static const int maxTokenLength = 4096;

  /// The comment type (`COMMENT`).
  static const int commentType = 3;

  /// The live figures' type (`LIVE`): `liveinfo.liveViewerCount`.
  static const int liveType = 38;

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  static final RegExp _token = RegExp('^[\\x21-\\x7e]{1,$maxTokenLength}\$');
  static final RegExp _hexColor = RegExp(r'^(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

  /// The token request's headers: the platform's catalog headers (desktop
  /// UA, `Origin`, `Referer: https://17.live/`) and a JSON content type.
  static const Map<String, String> authHeaders = {
    ...SeventeenLiveApi.catalogHeaders,
    'content-type': 'application/json',
  };

  /// The token request: a POST of `{}` with [authHeaders], not following
  /// redirects.
  static LiveRequest authRequest({Duration timeout = defaultRequestTimeout, CancelToken? cancel}) => LiveRequest(
    site: SiteIds.seventeenLive,
    url: authUrl,
    method: 'POST',
    headers: authHeaders,
    body: utf8.encode('{}'),
    followRedirects: false,
    timeout: timeout,
    cancel: cancel,
  );

  /// The Ably token of a `messenger/auth` [response]
  /// (`{"provider":1,"token":…,"permissions":["*"]}`). Another provider
  /// throws [SeventeenLiveChatRefusal]; an answer that is not a 200 or not
  /// JSON throws its `SiteError`, one without a usable token (printable
  /// ASCII, at most [maxTokenLength]) [FormatException].
  static String grant(LiveResponse response) {
    final data = SeventeenLiveApi.decode(response.text, what: 'messenger/auth', status: response.status);
    if (data is! Map) throw const FormatException('messenger/auth: not an object');
    final provider = data['provider'];
    if (provider != ablyProvider) {
      throw SeventeenLiveChatRefusal(provider is String || provider is num ? '$provider' : '');
    }
    final token = data['token'];
    if (token is! String || !_token.hasMatch(token)) throw const FormatException('messenger/auth: no token');
    return token;
  }

  /// [endpoint] with the `access_token` [token] first, as ably-js orders it.
  static Uri withToken(Uri endpoint, String token) =>
      endpoint.replace(queryParameters: {'access_token': token, ...endpoint.queryParameters});

  /// The `ATTACH` (10) of the channel [roomId], as the recordings sent it.
  static String attach(String roomId) => jsonEncode({'action': 10, 'channel': roomId});

  /// The `AUTH` (17) answering a server's request with [token] (ably-js's
  /// in-place reauthorisation).
  static String reauthorize(String token) => jsonEncode({
    'action': 17,
    'auth': {'accessToken': token},
  });

  /// Reads one frame of a chat socket for the room [roomId]: text, or
  /// UTF-8 bytes (malformed bytes become U+FFFD). The frame is one Ably
  /// protocol message, named by `action`:
  ///
  /// - 4 `CONNECTED`, 6 `DISCONNECTED`, 17 `AUTH`: [SeventeenLiveSignal]'s
  ///   `connected`, `disconnected` (with its `error`), `reauthorize`;
  /// - 9 `ERROR`: of the room's channel when it names it
  ///   ([SeventeenLiveSignal.channelError]), of the connection when it names
  ///   none ([SeventeenLiveSignal.connectionError]);
  /// - 11 `ATTACHED`, 13 `DETACHED` of the room's channel;
  /// - 15 `MESSAGE` of the room's channel: its `messages` ([message]); a
  ///   message's id is its `id`, or the frame's `id` and its index (Ably's
  ///   rule for messages without one).
  ///
  /// Anything else (the heartbeat 0, a presence `SYNC` 16, another
  /// channel, a frame that is not a JSON object) holds nothing. A field of
  /// the wrong type costs only that field or that message.
  static SeventeenLiveDanmakuFrame decode(Object? data, {required String roomId}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const SeventeenLiveDanmakuFrame();
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const SeventeenLiveDanmakuFrame();
    }
    if (root is! Map) return const SeventeenLiveDanmakuFrame();
    final channel = root['channel'];
    final ours = channel == roomId;
    final error = _error(root['error']);
    return switch (root['action']) {
      4 => const SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.connected),
      6 => SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.disconnected, error: error),
      9 when channel == null => SeventeenLiveDanmakuFrame(
        signal: SeventeenLiveSignal.connectionError,
        error: error ?? const SeventeenLiveAblyError(code: 0),
      ),
      9 when ours => SeventeenLiveDanmakuFrame(
        signal: SeventeenLiveSignal.channelError,
        error: error ?? const SeventeenLiveAblyError(code: 0),
      ),
      11 when ours => const SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.attached),
      13 when ours => SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.detached, error: error),
      15 when ours => SeventeenLiveDanmakuFrame(messages: _messages(root)),
      17 => const SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.reauthorize),
      _ => const SeventeenLiveDanmakuFrame(),
    };
  }

  static SeventeenLiveAblyError? _error(Object? value) {
    if (value is! Map) return null;
    final code = value['code'];
    final status = value['statusCode'];
    final message = value['message'];
    return SeventeenLiveAblyError(
      code: code is int ? code : 0,
      statusCode: status is int ? status : null,
      message: message is String ? message.trim() : '',
    );
  }

  static List<LiveMessage> _messages(Map<Object?, Object?> root) {
    final messages = root['messages'];
    if (messages is! List) return const [];
    final frameId = root['id'];
    return [
      for (final (index, item) in messages.indexed)
        if (item is Map)
          if (payload(item['data']) case final decoded?)
            ?message(
              decoded,
              id: switch (item['id']) {
                final String id when id.isNotEmpty => id,
                _ => frameId is String && frameId.isNotEmpty ? '$frameId:$index' : '',
              },
            ),
    ];
  }

  /// A message's `data`: base64 of gzipped UTF-8 JSON, as the website reads
  /// it (`gzip_base64`); null when it is not that or not a JSON object.
  static Map<Object?, Object?>? payload(Object? data) {
    if (data is! String || data.isEmpty) return null;
    try {
      final value = jsonDecode(utf8.decode(gzip.decode(base64.decode(data))));
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// The message a decoded [payload] shows, with the Ably message [id]; null
  /// for every other type (gifts, reactions, entries, rankings, missions…).
  ///
  /// - A comment ([commentType], `commentMsg`) is chat, unless the website
  ///   hides it: `isDirty`, `isDirtyWord` or `isDirtyUser` is true. The text
  ///   is `content` (what the website shows; `comment.text` when it has
  ///   none), trimmed; a blank one shows nothing. The name is
  ///   `displayUser.displayName` (its `openID` without one), the user id
  ///   `displayUser.userID`, the level `displayUser.level` (`commentMsg`'s
  ///   without one), the colour `comment.textColor` ([color]) and the time
  ///   `sendTime` (milliseconds; not above zero or beyond [DateTime]: none).
  ///   A barrage (a paid comment that also flies over the video on the
  ///   website) is chat as well.
  /// - The live figures ([liveType]) carry `liveinfo.liveViewerCount`, the
  ///   viewers now, which the website shows: an audience update.
  static LiveMessage? message(Map<Object?, Object?> payload, {String id = ''}) {
    switch (payload['type']) {
      case commentType:
        final comment = payload['commentMsg'];
        if (comment is! Map) return null;
        if (comment['isDirty'] == true || comment['isDirtyWord'] == true || comment['isDirtyUser'] == true) {
          return null;
        }
        final body = comment['comment'];
        var text = _string(comment['content']).trim();
        if (text.isEmpty && body is Map) text = _string(body['text']).trim();
        if (text.isEmpty) return null;
        final user = comment['displayUser'];
        final name = user is Map ? _string(user['displayName']) : '';
        final level = _level(user is Map ? user['level'] : null) ?? _level(comment['level']);
        final time = comment['sendTime'];
        return LiveMessage(
          type: LiveMessageType.chat,
          userName: name.isNotEmpty || user is! Map ? name : _string(user['openID']),
          userId: user is Map ? _string(user['userID']) : '',
          message: text,
          color: color(body is Map ? body['textColor'] : null),
          userLevel: level == null ? '' : '$level',
          messageId: id,
          sentAt: time is int && time > 0 && time <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null,
        );
      case liveType:
        final info = payload['liveinfo'];
        final viewers = info is Map ? info['liveViewerCount'] : null;
        if (viewers is! int || viewers < 0) return null;
        return LiveMessage(
          type: LiveMessageType.online,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
        );
      default:
        return null;
    }
  }

  /// A comment colour: `#AARRGGBB` (the alpha first, as the website reads
  /// it) or `#RRGGBB`, the `#` optional; anything else is white, the
  /// website's default.
  static LiveMessageColor color(Object? value) {
    if (value is! String) return LiveMessageColor.white;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!_hexColor.hasMatch(hex)) return LiveMessageColor.white;
    return LiveMessageColor.numberToColor(int.parse(hex.substring(hex.length - 6), radix: 16));
  }

  static int? _level(Object? value) => value is int && value > 0 ? value : null;

  static String _string(Object? value) => value is String ? value : '';
}

/// 17LIVE's danmaku connection: an anonymous Ably token over [LiveHttp],
/// then Ably's JSON realtime protocol over the shared WebSocket runtime.
///
/// - The token is asked in the handshake (as M5.11 and M5.21 do): the first
///   handshake of a [connect] asks `messenger/auth`, later ones reuse the
///   token until the server refuses it. A failed request fails that
///   handshake (the runtime's backoff and eight attempts); another
///   provider than Ably ends the run with [DanmakuCloseReason.connectionFailed].
/// - The sockets are the primary host and the website's three fallback
///   hosts, rotated on failure. At `CONNECTED` the room's channel is
///   attached; `ATTACHED` joins it, and an attach unanswered for 10 s drops
///   the socket.
/// - The server sends heartbeats every 15 s and the client none; a socket
///   silent for 25 s is replaced.
/// - A token error (`ERROR` or `DISCONNECTED`, 40140 to 40149) drops the
///   token and the socket; the next handshake asks a new one. The fourth in
///   a row without an attach between ends the run with
///   [DanmakuCloseReason.connectionFailed]. Any other connection `ERROR` or
///   a channel `ERROR` ends it as well (ably-js fails the connection or the
///   channel); another `DISCONNECTED` reconnects.
/// - A server-sent `DETACHED` attaches the channel again on the same
///   socket; a second one before it is attached, or no answer within 10 s,
///   drops the socket. It counts as a refusal like a token error. A
///   server-sent `AUTH` asks a new token and sends it on the same socket.
///
/// [SeventeenLiveDanmakuArgs.roomId] is the channel. The app registers it
/// as `SiteIds.seventeenLive: () => SeventeenLiveDanmakuConnection(http: …,
/// proxy: …)`, with the `LiveHttp` it gives `SeventeenLiveSite` and its
/// proxy policy.
final class SeventeenLiveDanmakuConnection extends DanmakuSocketConnection<SeventeenLiveDanmakuArgs> {
  /// Creates the connection. [http] asks `messenger/auth` for tokens;
  /// [proxy] routes the socket; [connector] replaces `dart:io`'s handshake
  /// and [policy] the timing (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
  }) => SeventeenLiveDanmakuConnection._(_Handshake(http, connector ?? connectIoSocket), proxy: proxy, policy: policy);

  new _(this._handshake, {required super.proxy, required super.policy})
    : super(site: SiteIds.seventeenLive, connector: _handshake.call);

  /// The platform's timing: the server's 15 s heartbeat as the watchdog's
  /// tick, 25 s of silence and 10 s for the attach; the runtime's defaults
  /// otherwise.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: SeventeenLiveDanmakuProtocol.heartbeatInterval,
    inactivityTimeout: SeventeenLiveDanmakuProtocol.inactivityTimeout,
    joinTimeout: SeventeenLiveDanmakuProtocol.joinTimeout,
  );

  static final DanmakuSocketTarget _target = DanmakuSocketTarget(
    endpoints: SeventeenLiveDanmakuProtocol.endpoints,
    headers: SeventeenLiveDanmakuProtocol.handshakeHeaders,
  );

  final _Handshake _handshake;

  @override
  @protected
  Future<DanmakuSocketTarget> target(SeventeenLiveDanmakuArgs args, DanmakuRun run) async {
    final roomId = SeventeenLiveApi.normalizeRoomId(args.roomId);
    if (roomId == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable room id');
    }
    _handshake.chat = _Chat(run, roomId);
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
      ..sockets += 1;
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = SeventeenLiveDanmakuProtocol.decode(data, roomId: chat.roomId);
    switch (frame.signal) {
      case SeventeenLiveSignal.none:
        break;
      case SeventeenLiveSignal.connected:
        session.send(SeventeenLiveDanmakuProtocol.attach(chat.roomId));
      case SeventeenLiveSignal.attached:
        chat
          ..refusals = 0
          ..reattaching = false
          ..reattachWatch?.cancel();
        if (session.isConnected) {
          session.cancelJoinTimeout();
        } else {
          session.ready();
        }
      case SeventeenLiveSignal.detached:
        _detached(session, chat, frame.error);
      case SeventeenLiveSignal.disconnected:
        if (frame.error case final error? when error.isTokenError) {
          _tokenRefused(session, chat, error);
        } else {
          session.reconnect();
        }
      case SeventeenLiveSignal.connectionError:
        final error = frame.error!;
        if (error.isTokenError) {
          _tokenRefused(session, chat, error);
        } else {
          session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Ably error $error');
        }
      case SeventeenLiveSignal.channelError:
        session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Channel refused: ${frame.error}');
      case SeventeenLiveSignal.reauthorize:
        unawaited(_reauthorize(session, chat));
    }
    for (final message in frame.messages) {
      if (!session.isActive) return;
      session.message(message);
    }
  }

  /// The server detached the channel: attach it again on this socket, as
  /// ably-js does; a detach while that attach is pending, or no answer
  /// within the join limit, drops the socket. A detach is a refusal: one
  /// too many ends the run.
  void _detached(DanmakuSocketSession session, _Chat chat, SeventeenLiveAblyError? error) {
    if (++chat.refusals > SeventeenLiveDanmakuProtocol.maxRefusals) {
      session.run.closed(
        DanmakuCloseReason.connectionFailed,
        detail: error == null ? 'Channel detached' : 'Channel detached: $error',
      );
      return;
    }
    if (chat.reattaching) {
      session.reconnect();
      return;
    }
    chat.reattaching = true;
    final sockets = chat.sockets;
    chat.reattachWatch = Timer(policy.joinTimeout ?? SeventeenLiveDanmakuProtocol.joinTimeout, () {
      if (session.isActive && chat.reattaching && chat.sockets == sockets) session.reconnect();
    });
    session.send(SeventeenLiveDanmakuProtocol.attach(chat.roomId));
  }

  /// The server refused the token: drop it (the next handshake asks a new
  /// one) and the socket, unless this is one refusal too many.
  void _tokenRefused(DanmakuSocketSession session, _Chat chat, SeventeenLiveAblyError error) {
    chat.token = null;
    if (++chat.refusals > SeventeenLiveDanmakuProtocol.maxRefusals) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Token refused: $error');
      return;
    }
    session.reconnect();
  }

  /// The server asked for a new token: ask `messenger/auth` and send it on
  /// the same socket. A failure is left to the server, which drops the
  /// socket with a token error when the old token lapses.
  Future<void> _reauthorize(DanmakuSocketSession session, _Chat chat) async {
    final sockets = chat.sockets;
    final String token;
    try {
      token = await _handshake.renew(chat, timeout: policy.connectTimeout);
    } on Object {
      return;
    }
    if (session.isActive && chat.sockets == sockets) session.send(SeventeenLiveDanmakuProtocol.reauthorize(token));
  }

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.dispose();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [SeventeenLiveDanmakuConnection]: asks
/// `messenger/auth` for a token first when the run has none, then connects
/// with it. A failed handshake's message has the token blanked out.
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
    final token = chat.token ?? await renew(chat, timeout: connectTimeout);
    try {
      return await _connect(
        SeventeenLiveDanmakuProtocol.withToken(endpoint, token),
        headers: headers,
        protocols: protocols,
        route: route,
        connectTimeout: connectTimeout,
      );
    } on Object catch (error) {
      throw _HandshakeFailure(
        '$error'.replaceAll(Uri.encodeQueryComponent(token), '<token>').replaceAll(token, '<token>'),
      );
    }
  }

  /// Asks `messenger/auth` for a token of [chat] and keeps it. Another
  /// provider ends the run; every failure is thrown.
  Future<String> renew(_Chat chat, {required Duration timeout}) async {
    final response = await _http.send(SeventeenLiveDanmakuProtocol.authRequest(timeout: timeout, cancel: chat.cancel));
    final String token;
    try {
      token = SeventeenLiveDanmakuProtocol.grant(response);
    } on SeventeenLiveChatRefusal catch (refusal) {
      chat.run.closed(DanmakuCloseReason.connectionFailed, detail: '$refusal');
      rethrow;
    }
    if (!chat.run.isActive) throw StateError('The chat was closed');
    return chat.token = token;
  }
}

/// A failed handshake, its message without the token.
final class _HandshakeFailure implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One run's chat: the room, its token and the state of the current socket.
final class _Chat {
  new(this.run, this.roomId) {
    unawaited(run.ended.then((_) => dispose()));
  }

  final DanmakuRun run;

  /// The room id, the channel's name.
  final String roomId;
  final CancelToken cancel = CancelToken();

  /// The token of the next handshake; null asks a new one.
  String? token;

  /// Token refusals and detaches since the channel was last attached.
  int refusals = 0;

  /// Sockets opened so far.
  int sockets = 0;

  /// Whether a server-sent detach is being answered with an attach.
  bool reattaching = false;

  /// The limit of that attach.
  Timer? reattachWatch;

  /// A new socket: nothing attached, no attach pending.
  void socketReset() {
    reattaching = false;
    reattachWatch?.cancel();
    reattachWatch = null;
  }

  void dispose() {
    socketReset();
    cancel.cancel();
  }
}
