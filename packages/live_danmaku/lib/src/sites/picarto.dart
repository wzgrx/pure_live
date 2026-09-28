import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one Picarto chat frame held ([PicartoDanmakuProtocol.decode]).
@immutable
final class PicartoDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.tokenRefused = false});

  /// Chat and audience updates, in order.
  final List<LiveMessage> messages;

  /// The chat server refused the token (`{"success":false,"code":"JWT_TOKEN"}`);
  /// it keeps the socket open but sends nothing else.
  final bool tokenRefused;
}

/// Picarto's chat (docs/modules/M5.10-picarto.md), without I/O: an
/// anonymous JWT from the site's GraphQL API names the channel, and a
/// WebSocket of JSON text frames carries the chat.
///
/// 3.x had no Picarto danmaku; this follows the archived v4 connector and
/// the site's own chat client (`picarto.tv/static/js`), which sends the
/// keep-alive [heartbeat] every 50 s.
abstract final class PicartoDanmakuProtocol {
  /// The GraphQL endpoint that issues chat tokens.
  static final Uri tokenEndpoint = Uri.https(PicartoApi.apiHost, '/ptvapi');

  /// The GraphQL query of a chat token; anonymous callers get one with
  /// `userId 0` and no expiry.
  static const String tokenQuery = r'query ($name: String) { generateJwtToken(channel_name: $name) { key } }';

  /// The JSON body asking a token for [channelName] (the platform's
  /// spelling).
  static Map<String, Object?> tokenBody(String channelName) => {
    'query': tokenQuery,
    'variables': {'name': channelName},
  };

  static final RegExp _jwt = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');

  /// The token of a decoded GraphQL answer, or null: an unknown channel
  /// gives `{"key": null}`. Only a JWT (three base64url parts) is taken, as
  /// it goes into the socket's path.
  static String? token(Object? answer) {
    if (answer case {'data': {'generateJwtToken': {'key': final String key}}} when _jwt.hasMatch(key)) return key;
    return null;
  }

  /// The chat socket of [token] (the token is part of the path).
  static Uri endpoint(String token) => Uri.parse('wss://chat.picarto.tv/chat/token=$token');

  /// Handshake headers: the site's origin and the desktop UA every Picarto
  /// request carries (`PicartoApi.headers`).
  static const Map<String, String> handshakeHeaders = {'origin': PicartoApi.origin, 'user-agent': PicartoApi.userAgent};

  /// Keep-alive period: the site's chat client pings every 50 s
  /// (`REACT_APP_CHAT_TIMEOUT`).
  static const Duration heartbeatInterval = Duration(seconds: 50);

  /// The site's keep-alive frame; the server answers
  /// `{"success":true,"code":"PONG"}`, so even a channel whose chat is
  /// silent (every offline one) never looks dead.
  static const String heartbeat = '{"type":"ping","message":"__ping__"}';

  /// The refusal code of a token the chat server does not accept.
  static const String refusedCode = 'JWT_TOKEN';

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  static final RegExp _hex6 = RegExp(r'^[0-9a-fA-F]{6}$');
  static final RegExp _hex3 = RegExp(r'^[0-9a-fA-F]{3}$');

  /// Reads one text frame of [channelId]'s chat socket.
  ///
  /// Frames are JSON objects named by `type` or `t`, with their payload in
  /// `messages` or `m` (the site's client reads both spellings):
  ///
  /// - `c`: chat, a list of lines ([chat]); a page of history (`paginated`
  ///   or `p` set) is skipped, as the site's client skips it;
  /// - `stream`: the channel's state, whose `viewers` is the concurrent
  ///   audience ([audience]);
  /// - `{"success":false,"code":"JWT_TOKEN"}`: the token was refused.
  ///
  /// Everything else (joins and leaves `un`/`ur`, the user list, whispers,
  /// chip tips, polls, raffles, the answer to [heartbeat]) holds nothing to
  /// show; so does a frame that is not a JSON object. A field of the wrong
  /// type costs only that field (a time out of range, a colour that is not
  /// text) or that line (text that is not text), never the frame.
  static PicartoDanmakuFrame decode(String text, {required int channelId}) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const PicartoDanmakuFrame();
    }
    if (root is! Map) return const PicartoDanmakuFrame();
    if (root['success'] == false && root['code'] == refusedCode) return const PicartoDanmakuFrame(tokenRefused: true);
    final payload = root['messages'] ?? root['m'];
    switch (root['type'] ?? root['t']) {
      case 'stream':
        return PicartoDanmakuFrame(messages: [?audience(payload, channelId: channelId)]);
      case 'c' when !_truthy(root['paginated'] ?? root['p']) && payload is List:
        return PicartoDanmakuFrame(messages: [for (final line in payload) ?chat(line)]);
      default:
        return const PicartoDanmakuFrame();
    }
  }

  /// One chat line, or null when it is not a chat line (`t` other than `c`)
  /// or holds no text.
  ///
  /// Fields: `n` name, `u` user id, `m` text (trimmed), `id` (or `_id`) the
  /// message id, `d` the time in milliseconds, `k` the name colour (hex
  /// without `#`; anything else is white). `c` (the channel the line was
  /// written in) is not checked: channels streaming together share one chat,
  /// and the site shows all of it. Emotes stay as `:name:` in the text.
  static LiveMessage? chat(Object? line) {
    if (line is! Map) return null;
    final type = line['t'];
    if (type != null && type != 'c') return null;
    final text = line['m'];
    if (text is! String || text.trim().isEmpty) return null;
    final id = line['id'] ?? line['_id'];
    final sent = line['d'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _scalar(line['n']),
      userId: _scalar(line['u']),
      message: text.trim(),
      color: color(line['k']),
      messageId: id is String ? id : '',
      sentAt: sent is int && sent.abs() <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(sent) : null,
    );
  }

  /// The concurrent audience of a `stream` frame's [state], or null. A
  /// frame naming another channel (`id`) is skipped; `viewers` must be a
  /// whole number, not negative.
  static LiveMessage? audience(Object? state, {required int channelId}) {
    if (state is! Map) return null;
    final id = state['id'];
    if (id != null && '$id' != '$channelId') return null;
    final viewers = state['viewers'];
    if (viewers is! int || viewers < 0) return null;
    return LiveMessage(
      type: LiveMessageType.online,
      userName: '',
      message: '',
      color: LiveMessageColor.white,
      data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
    );
  }

  /// A name colour: 6 hex digits (`66AFFF`), optionally after `#`, or the
  /// 3-digit CSS short form; anything else is white. The site's client
  /// prefixes `#` and hands it to CSS.
  static LiveMessageColor color(Object? value) {
    if (value is! String) return LiveMessageColor.white;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (_hex3.hasMatch(hex)) hex = hex.split('').map((digit) => '$digit$digit').join();
    if (!_hex6.hasMatch(hex)) return LiveMessageColor.white;
    return LiveMessageColor.numberToColor(int.parse(hex, radix: 16));
  }

  static String _scalar(Object? value) => value is String || value is num ? '$value' : '';

  /// JavaScript truthiness, as the site's client tests `paginated || p`.
  static bool _truthy(Object? value) => switch (value) {
    null => false,
    final bool flag => flag,
    final num number => number != 0 && !number.isNaN,
    final String text => text.isNotEmpty,
    _ => true,
  };
}

/// Picarto's danmaku connection: a chat token from the GraphQL API over
/// [LiveHttp], then the chat socket over the shared WebSocket runtime.
///
/// - A token is asked at every [connect], up to three times (0.5 s and 1 s
///   apart); without one the run ends with
///   [DanmakuCloseReason.credentialsUnavailable]. Tokens do not expire, so
///   reconnects reuse it, as the site's client does.
/// - An open socket counts as joined (the server sends no welcome); the
///   keep-alive goes out every 50 s and the server answers it, so a socket
///   silent for max(3 × 50 s, 90 s) = 150 s is replaced.
/// - A refused token (`JWT_TOKEN`) is replaced by a new one and the socket
///   reopened without a notice, at most three times per [connect]; then the
///   run ends with [DanmakuCloseReason.credentialsUnavailable].
///
/// The app registers it as `SiteIds.picarto: () =>
/// PicartoDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `PicartoSite` and its proxy policy.
final class PicartoDanmakuConnection extends DanmakuSocketConnection<PicartoDanmakuArgs> {
  /// Creates the connection; `http` asks for the chat tokens and [proxy]
  /// routes the socket. `connector` replaces `dart:io`'s handshake and
  /// `tokenRetryDelay` the step between token attempts (tests); handshake
  /// failures are reported without the token.
  new({
    required this._http,
    super.proxy,
    SocketConnector? connector,
    this._tokenRetryDelay = const Duration(milliseconds: 500),
  }) : super(site: SiteIds.picarto, policy: socketPolicy, connector: _withoutToken(connector ?? connectIoSocket));

  /// Socket timing: the defaults of the shared runtime with the site's 50 s
  /// keep-alive. No join timer: an open socket counts as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: PicartoDanmakuProtocol.heartbeatInterval,
  );

  /// Token requests per attempt to get one.
  static const int tokenAttempts = 3;

  /// Longest wait for one token answer.
  static const Duration tokenTimeout = Duration(seconds: 5);

  /// Refused tokens replaced per [connect].
  static const int maxTokenRefreshes = 3;

  final LiveHttp _http;
  final Duration _tokenRetryDelay;
  _Chat? _chat;

  static final RegExp _tokenInText = RegExp('token=[A-Za-z0-9_.-]+');

  /// [connector] whose failures do not repeat the token of the socket's
  /// path (`dart:io` names the URL in its errors, which end up in
  /// [DanmakuClosed.detail]).
  static SocketConnector _withoutToken(SocketConnector connector) =>
      (endpoint, {required headers, required protocols, required route, required connectTimeout}) async {
        try {
          return await connector(
            endpoint,
            headers: headers,
            protocols: protocols,
            route: route,
            connectTimeout: connectTimeout,
          );
        } on Object catch (error) {
          throw _HandshakeFailure('$error'.replaceAll(_tokenInText, 'token=…'));
        }
      };

  static DanmakuSocketTarget _target(String token) => DanmakuSocketTarget(
    endpoints: [PicartoDanmakuProtocol.endpoint(token)],
    headers: PicartoDanmakuProtocol.handshakeHeaders,
  );

  @override
  @protected
  Future<DanmakuSocketTarget> target(PicartoDanmakuArgs args, DanmakuRun run) async {
    final channel = args.channelName.trim();
    if (channel.isEmpty) throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No channel');
    final chat = _chat = _Chat(run, channel, args.channelId);
    final token = await _token(chat);
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    if (token == null) throw DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: chat.lastFailure);
    return _target(token);
  }

  /// A token for [chat]'s channel: up to [tokenAttempts] requests, or null
  /// when none gave one or the run ended.
  Future<String?> _token(_Chat chat) async {
    for (var attempt = 0; attempt < tokenAttempts; attempt++) {
      if (attempt > 0 && !await chat.run.delay(_tokenRetryDelay * attempt)) return null;
      try {
        final answer = await _http.postJson(
          SiteIds.picarto,
          PicartoDanmakuProtocol.tokenEndpoint,
          json: PicartoDanmakuProtocol.tokenBody(chat.channel),
          headers: PicartoApi.headers,
          timeout: tokenTimeout,
          cancel: chat.cancel,
        );
        final token = PicartoDanmakuProtocol.token(answer);
        if (token != null) return token;
        chat.lastFailure = 'No chat token';
      } on Object catch (error) {
        if (!chat.run.isActive) return null;
        chat.lastFailure = '$error';
      }
    }
    return null;
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    if (_of(session) != null) session.ready();
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return;
    final frame = PicartoDanmakuProtocol.decode(text, channelId: chat.channelId);
    frame.messages.forEach(session.message);
    if (frame.tokenRefused) unawaited(_refused(session, chat));
  }

  /// Replaces a refused token and reopens, without a notice.
  Future<void> _refused(DanmakuSocketSession session, _Chat chat) async {
    if (chat.refreshing) return;
    session.markDisconnected();
    if (chat.refreshes >= maxTokenRefreshes) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: 'Chat token refused');
      return;
    }
    chat
      ..refreshing = true
      ..refreshes += 1;
    final String? token;
    try {
      token = await _token(chat);
    } finally {
      // The new socket may be refused too; that refusal starts the next
      // refresh.
      chat.refreshing = false;
    }
    if (!session.isActive) return;
    if (token == null) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: chat.lastFailure);
      return;
    }
    await session.reopen(_target(token));
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => PicartoDanmakuProtocol.heartbeat;

  @override
  @protected
  Future<void> stop() async {
    _chat = null;
    await super.stop();
  }
}

/// The chat of one run: its channel, the token requests and refreshes.
final class _Chat {
  new(this.run, this.channel, this.channelId) {
    unawaited(run.ended.then((_) => cancel.cancel()));
  }

  final DanmakuRun run;
  final String channel;
  final int channelId;
  final CancelToken cancel = CancelToken();
  String lastFailure = '';
  int refreshes = 0;
  bool refreshing = false;
}

/// A failed handshake, described without the token.
final class _HandshakeFailure implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}
