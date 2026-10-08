import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// The chat group's credentials of one handshake: the socket URL (the
/// `liveauth` answer's `liveUrl` and `token`) and, when the answer has one,
/// the key its binary frames are masked with (`msgMaskKey`).
@immutable
final class JdLiveChatAuth {
  /// Creates the credentials.
  const new({required this.socketUrl, this.maskKey});

  /// `<liveUrl>?token=<token>`: the token is good for one handshake.
  final Uri socketUrl;

  /// `msgMaskKey`, or null when the answer has none (the guest answers
  /// recorded so far: their frames are plain text).
  final String? maskKey;
}

/// What one pushed frame says.
@immutable
final class JdLiveDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.ended = false});

  /// A frame that says nothing this client reports.
  static const JdLiveDanmakuFrame none = JdLiveDanmakuFrame();

  /// Chat or audience, in order.
  final List<LiveMessage> messages;

  /// `stop_live_broadcast`: the broadcast ended (the page then shows its
  /// end; the server stops pushing and closes the socket 19–180 s later).
  final bool ended;
}

/// JD Live's chat: the website's guest `liveauth` and its socket
/// (`lives.jd.com`'s live page script, 2026-09-29; checked against the
/// recording `fixtures/jdlive/danmaku/S06-live`;
/// docs/D-弹幕/D01-平台弹幕协议/D01.25-京东直播弹幕), without I/O.
///
/// - A handshake first POSTs `liveauth` (no h5st signature): the form's
///   `body` holds the website's app id and, as `content`, a JSON object
///   naming the broadcast as the chat group, AES-128-CBC encrypted with the
///   key and IV written in the page script. The answer gives the socket's
///   address and a token that opens one socket.
/// - The client sends nothing on the socket: the website's join frame only
///   announces a visitor ("… 来了") and is not needed to receive the room.
/// - The server pushes JSON text: `get_statistics_result` (the audience,
///   about every 3.5 s while live) and `chat_group_message` events, whose
///   `body.type` says what happened. Chat is `viewer_send_message` and
///   `anchor_send_message`, the two kinds the website's chat list shows.
abstract final class JdLiveDanmakuProtocol {
  /// Where `liveauth` is asked (the page's API host).
  static final Uri authUrl = Uri.parse('https://${JdLiveApi.apiHost}/api');

  /// The page's app id (`appId`), in the form's `body` and the content.
  static const String appId = 'jd.mall';

  /// The page's key (`secretKey`): sent in the content and, as UTF-8, the
  /// AES key that encrypts it.
  static const String secretKey = 'RYm2dMPMWD9AxYFk';

  /// The page's IV (`pyl`), as UTF-8.
  static const String iv = '0102030405060708';

  /// `loginType` of the page in a browser (11 in the mini program).
  static const String loginType = '2';

  /// `origin` of the content: the page's default when its link names none.
  static const int origin = -100;

  /// The name the website's chat list gives the streamer's own messages
  /// (`anchor_send_message` carries no name).
  static const String anchorName = '主播';

  /// How often the server sends the audience while a broadcast is live
  /// (measured 2026-09-29/30: about every 3.5 s, at most 6.8 s apart in
  /// 32 room-hours). Not every live room has it: one pushed no statistics
  /// for 30 minutes, only product events, up to 119 s apart.
  static const Duration statisticsInterval = Duration(milliseconds: 3500);

  /// The server drops a socket that got nothing for this long (measured:
  /// four sockets, each closed 180 s after its last frame, code 1006).
  static const Duration serverIdleTimeout = Duration(seconds: 180);

  /// Silence after which the socket is replaced: longer than
  /// [serverIdleTimeout], so it only catches a socket the server's close
  /// never reached (a quiet room without statistics is normal). The website
  /// has no watchdog.
  static const Duration silenceTimeout = Duration(seconds: 200);

  /// Headers of `liveauth`: the adapter's API headers (3.x's `apiHeaders`)
  /// and the page's form type (axios, without a charset).
  static const Map<String, String> authHeaders = {
    ...JdLiveApi.apiHeaders,
    'content-type': 'application/x-www-form-urlencoded',
  };

  /// Handshake headers: the website's origin and the adapter's user agent.
  static const Map<String, String> socketHeaders = {'origin': JdLiveApi.webOrigin, 'user-agent': JdLiveApi.userAgent};

  static const int _maxEpochMilliseconds = 8640000000000000;
  static final RegExp _token = RegExp(r'''(?<=[?&])token=[^&#\s'"]*''');

  /// The JSON the page encrypts for [liveId] (`groupId`), in the page's key
  /// order; [now] is the `timestamp` (ms) and [nonce] its `random` (six
  /// digits). No `pin` (no account) and no `eid` (the risk fingerprint the
  /// page asks another script for; the server does not need it).
  static String content(String liveId, {required DateTime now, required String nonce}) => jsonEncode({
    'appId': appId,
    'secretKey': secretKey,
    'groupId': liveId,
    'clientType': 'm',
    'timestamp': now.millisecondsSinceEpoch,
    'origin': origin,
    'encryptPin': true,
    'random': nonce,
  });

  /// [content] encrypted as the page does: AES-128-CBC with PKCS#7 padding,
  /// Base64.
  static String encrypt(String content) =>
      base64.encode(AesCbc.encrypt(utf8.encode(content), key: utf8.encode(secretKey), iv: utf8.encode(iv)));

  /// Six random digits, as the page's `Math.random().toString().slice(-6)`.
  static String nonce(Random random) => [for (var i = 0; i < 6; i++) random.nextInt(10)].join();

  /// The `liveauth` request for [liveId]: a form POST like the page's
  /// (`loginType`, `appid`, `functionId`, `body`, `t`), with the adapter's
  /// headers, not following redirects, sent as `jdlive`.
  static LiveRequest request(
    String liveId, {
    required DateTime now,
    required String nonce,
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) {
    final fields = {
      'loginType': loginType,
      'appid': 'h5-live',
      'functionId': 'liveauth',
      'body': jsonEncode({'appId': appId, 'content': encrypt(content(liveId, now: now, nonce: nonce))}),
      't': '${now.millisecondsSinceEpoch}',
    };
    return LiveRequest(
      site: SiteIds.jdLive,
      url: authUrl,
      method: 'POST',
      headers: authHeaders,
      body: utf8.encode(
        fields.entries
            .map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
            .join('&'),
      ),
      followRedirects: false,
      timeout: timeout,
      cancel: cancel,
    );
  }

  /// The credentials of a `liveauth` [response]: `code` 0 and a `data`
  /// with a `wss` `liveUrl` on a `jd.com` host (no query, fragment or user
  /// info) and a `token`. Throws [FormatException] for anything else (a
  /// status that is not 2xx, no JSON, a refusal such as `{"code":1,"msg":
  /// "鉴权失败","data":{"error":"解密失败!"}}`).
  static JdLiveChatAuth auth(LiveResponse response) {
    if (!response.isSuccess) throw FormatException('liveauth answered HTTP ${response.status}');
    final Object? root;
    try {
      root = response.json;
    } on FormatException {
      throw const FormatException('liveauth answered no JSON');
    }
    if (root is! Map) throw const FormatException('liveauth answered no JSON object');
    final data = root['data'];
    if (root['code'] != 0 || data is! Map) {
      final error = data is Map ? data['error'] : null;
      throw FormatException('liveauth refused: ${root['code']} ${root['msg']}${error is String ? ' ($error)' : ''}');
    }
    final address = data['liveUrl'];
    final base = address is String ? Uri.tryParse(address.trim()) : null;
    final token = data['token'];
    if (base == null ||
        !base.isScheme('wss') ||
        !_isJdHost(base.host) ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        token is! String ||
        token.trim().isEmpty ||
        token.contains(RegExp(r'[\s&#]'))) {
      throw const FormatException('liveauth answered no socket');
    }
    final mask = data['msgMaskKey'];
    return JdLiveChatAuth(
      socketUrl: Uri.parse('$base?token=${token.trim()}'),
      maskKey: mask is String && mask.isNotEmpty ? mask : null,
    );
  }

  static bool _isJdHost(String host) {
    final lower = host.toLowerCase();
    return lower == 'jd.com' || lower.endsWith('.jd.com');
  }

  /// The address a [JdLiveDanmakuConnection]'s socket is given for
  /// [liveId]: `liveauth` naming the broadcast. Every handshake turns it
  /// into a fresh socket URL (a token opens one socket).
  static Uri endpoint(String liveId) => authUrl.replace(queryParameters: {'functionId': 'liveauth', 'groupId': liveId});

  /// The broadcast of an [endpoint] address, or null for any other address.
  static String? liveIdOf(Uri address) {
    if (address.scheme != authUrl.scheme || address.host != authUrl.host || address.path != authUrl.path) return null;
    final parameters = address.queryParameters;
    final liveId = parameters['groupId'] ?? '';
    return parameters['functionId'] == 'liveauth' && JdLiveApi.isLiveId(liveId) ? liveId : null;
  }

  /// [text] with the socket URL's token left out: `dart:io` names the whole
  /// URL in a failed handshake.
  static String redact(String text) => text.replaceAll(_token, 'token=…');

  /// One pushed frame of broadcast [liveId]: text, or bytes (XORed with
  /// [maskKey] when the answer gave one, as the page does, then UTF-8). A
  /// frame that is not a JSON object, an event of another group (a
  /// `body.groupid` that is not [liveId]) and every event but the audience,
  /// the two kinds of chat and the end of the broadcast give nothing.
  static JdLiveDanmakuFrame decode(Object? data, {required String liveId, String? maskKey}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => _text(bytes, maskKey),
      _ => null,
    };
    if (text == null) return JdLiveDanmakuFrame.none;
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return JdLiveDanmakuFrame.none;
    }
    if (root is! Map) return JdLiveDanmakuFrame.none;
    final body = root['body'];
    if (body is! Map || !_sameGroup(body['groupid'], liveId)) return JdLiveDanmakuFrame.none;
    return switch (root['type']) {
      'get_statistics_result' => JdLiveDanmakuFrame(messages: audience(body)),
      'chat_group_message' when body['type'] == 'stop_live_broadcast' => const JdLiveDanmakuFrame(ended: true),
      'chat_group_message' => JdLiveDanmakuFrame(messages: [if (chat(root) case final LiveMessage message) message]),
      _ => JdLiveDanmakuFrame.none,
    };
  }

  /// The bytes of a binary frame as text: XORed with [maskKey]'s code units
  /// (their low bytes, repeated) when there is one, then UTF-8; null when
  /// they are not UTF-8 (the page's `decodeURIComponent` throws and the
  /// frame is dropped).
  static String? _text(List<int> bytes, String? maskKey) {
    final key = maskKey == null || maskKey.isEmpty ? null : maskKey.codeUnits;
    final plain = key == null
        ? bytes
        : [for (var i = 0; i < bytes.length; i++) (key[i % key.length] ^ bytes[i]) & 0xFF];
    try {
      return utf8.decode(plain);
    } on FormatException {
      return null;
    }
  }

  /// Whether an event's `groupid` (a number or its text) is [liveId]'s; an
  /// event without one counts as this group's.
  static bool _sameGroup(Object? group, String liveId) => switch (group) {
    null => true,
    final int number => '$number' == liveId,
    final String text => text.trim() == liveId,
    _ => false,
  };

  /// The audience of a `get_statistics_result` [body]: `current_viewer`,
  /// the viewers in the room now (it rises and falls as they join and
  /// leave), and `total_viwer` (sic), the cumulative views the list shows as
  /// `pv`. Each is a whole number (a JSON number or its text), not
  /// negative, or left out. `pv`, `max_viewer`, `message_num`,
  /// `thumbs_up_num` and `cart_num` are not read.
  static List<LiveMessage> audience(Map<Object?, Object?> body) => [
    for (final (key, kind) in const [
      ('current_viewer', LiveAudienceMetricKind.onlineViewers),
      ('total_viwer', LiveAudienceMetricKind.totalViewers),
    ])
      if (_count(body[key]) case final value?)
        LiveMessage(
          type: LiveMessageType.online,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveAudienceUpdate(kind: kind, value: value),
        ),
  ];

  /// A `chat_group_message` [event] as white chat, or null for any other
  /// kind (entries, likes, purchases, products, replies to one viewer, room
  /// state):
  ///
  /// - `viewer_send_message`: the name is `body.nickName`;
  /// - `anchor_send_message`: the name is [anchorName], as the page shows;
  /// - the text is `body.content`, trimmed; blank or not text: null;
  /// - the user id is `from.pinmd5` (a hash of the account; the page never
  ///   shows the account), the message id `id`, the time `datetime` (ms;
  ///   left out when not a positive whole number within `DateTime`'s range).
  ///
  /// `plus`, `userMemberLevel`, `loveLevel`, `extraTag` and `ext` are not
  /// read.
  static LiveMessage? chat(Map<Object?, Object?> event) {
    final body = event['body'];
    if (body is! Map) return null;
    final String name;
    switch (body['type']) {
      case 'viewer_send_message':
        final nick = body['nickName'];
        name = nick is String ? nick.trim() : '';
      case 'anchor_send_message':
        name = anchorName;
      default:
        return null;
    }
    final text = body['content'];
    if (text is! String || text.trim().isEmpty) return null;
    final from = event['from'];
    final user = from is Map ? from['pinmd5'] : null;
    final id = event['id'];
    final time = event['datetime'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name,
      userId: user is String ? user.trim() : '',
      message: text.trim(),
      messageId: id is String ? id.trim() : '',
      sentAt: time is int && time > 0 && time <= _maxEpochMilliseconds
          ? DateTime.fromMillisecondsSinceEpoch(time)
          : null,
      color: LiveMessageColor.white,
    );
  }

  static int? _count(Object? value) {
    final count = switch (value) {
      final int number => number,
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    return count != null && count >= 0 ? count : null;
  }
}

/// JD Live's chat connection (new in v4: 3.x had none, the 28-6 upgrade), on
/// the WebSocket runtime: one socket per broadcast
/// (`JdLiveDanmakuArgs.liveId`), no client frames.
///
/// - Every handshake, the first and each reconnect, first POSTs `liveauth`
///   for a fresh token, as the page does after a socket error: a token opens
///   one socket. A request that fails or is refused counts as a failed
///   handshake: the runtime's backoff and its eight attempts apply.
/// - An open socket counts as joined.
/// - The server sends the audience about every 3.5 s while most broadcasts
///   are live, and drops a socket after 180 s without a frame; 200 s without
///   any frame replaces the socket (a half-open one). Nothing is sent: the
///   20 s heartbeat period only paces that watchdog.
/// - `stop_live_broadcast` ends the connection
///   ([DanmakuCloseReason.connectionFailed], `Broadcast ended`): the server
///   pushes nothing more for that broadcast, and a new one has a new id.
/// - Failures name the socket URL without its token.
///
/// The app registers it as `SiteIds.jdLive: () =>
/// JdLiveDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `JdLiveSite` (proxy route by the platform id) and its proxy policy
/// for the socket.
final class JdLiveDanmakuConnection extends DanmakuSocketConnection<JdLiveDanmakuArgs> {
  /// Creates the connection. [http] asks for the tokens; [proxy] routes the
  /// socket; [connector] replaces `dart:io`'s handshake, [policy] the
  /// timing, [now] the clock and [random] the nonces of `liveauth` (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    DateTime Function()? now,
    Random? random,
  }) => JdLiveDanmakuConnection._(
    _Resolver(http, connector ?? connectIoSocket, now ?? DateTime.now, random ?? Random.secure()),
    proxy: proxy,
    policy: policy,
  );

  new _(this._resolver, {required super.proxy, required super.policy})
    : super(site: SiteIds.jdLive, connector: _resolver.connect);

  /// The platform's timing: a 20 s tick for the silence watchdog (no frame
  /// is sent) and 200 s of silence; the runtime's defaults otherwise. No
  /// join timer: an open socket is joined.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: Duration(seconds: 20),
    inactivityTimeout: JdLiveDanmakuProtocol.silenceTimeout,
  );

  final _Resolver _resolver;
  String _liveId = '';

  @override
  @protected
  Future<DanmakuSocketTarget> target(JdLiveDanmakuArgs args, DanmakuRun run) async {
    final liveId = args.liveId.trim();
    if (!JdLiveApi.isLiveId(liveId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No broadcast');
    }
    _resolver.renew();
    _liveId = liveId;
    return DanmakuSocketTarget(
      endpoints: [JdLiveDanmakuProtocol.endpoint(liveId)],
      headers: JdLiveDanmakuProtocol.socketHeaders,
    );
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) => session.ready();

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final frame = JdLiveDanmakuProtocol.decode(data, liveId: _liveId, maskKey: _resolver.maskKey);
    for (final message in frame.messages) {
      if (!session.isActive) return;
      session.message(message);
    }
    if (frame.ended) session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Broadcast ended');
  }

  @override
  @protected
  Future<void> stop() async {
    _resolver.cancel();
    await super.stop();
  }
}

/// The handshake of a [JdLiveDanmakuConnection]: resolves the `liveauth`
/// address to a socket URL with a fresh token, then connects.
final class _Resolver {
  new(this._http, this._connect, this._now, this._random);

  final LiveHttp _http;
  final SocketConnector _connect;
  final DateTime Function() _now;
  final Random _random;
  CancelToken _cancel = CancelToken();

  /// The mask of the current socket's binary frames, from its `liveauth`.
  String? maskKey;

  /// A new run: the previous run's requests are cancelled.
  void renew() {
    _cancel.cancel();
    _cancel = CancelToken();
    maskKey = null;
  }

  /// Cancels the current run's requests.
  void cancel() => _cancel.cancel();

  Future<SocketChannel> connect(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    final liveId = JdLiveDanmakuProtocol.liveIdOf(endpoint);
    var url = endpoint;
    if (liveId != null) {
      final auth = await _auth(liveId, connectTimeout);
      maskKey = auth.maskKey;
      url = auth.socketUrl;
    }
    try {
      return await _connect(url, headers: headers, protocols: protocols, route: route, connectTimeout: connectTimeout);
    } on Object catch (error) {
      throw _HandshakeFailure(JdLiveDanmakuProtocol.redact('$error'));
    }
  }

  Future<JdLiveChatAuth> _auth(String liveId, Duration timeout) async {
    final request = JdLiveDanmakuProtocol.request(
      liveId,
      now: _now(),
      nonce: JdLiveDanmakuProtocol.nonce(_random),
      timeout: timeout,
      cancel: _cancel,
    );
    return JdLiveDanmakuProtocol.auth(await _http.send(request));
  }
}

/// A failed handshake, described without the URL's token.
final class _HandshakeFailure implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}
