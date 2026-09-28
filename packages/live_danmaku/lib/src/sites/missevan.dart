import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one Missevan chat frame held ([MissevanDanmakuProtocol.decode]).
@immutable
final class MissevanDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.joined, this.refusal = ''});

  /// Chat and audience updates, in order.
  final List<LiveMessage> messages;

  /// The answer to this socket's join: true when the room was joined
  /// (`code 0`), false when the join was refused, null when the frame held
  /// no answer to it.
  final bool? joined;

  /// The refused join's code and text (`500030004 无法找到该聊天室`), for
  /// diagnostics.
  final String refusal;
}

/// Missevan's (猫耳 FM) chat (docs/modules/M5.12-missevan.md), without I/O.
///
/// 3.x had no Missevan danmaku; this follows the archived v4 connector and
/// the site's own IM client (`maoer-static/assets/fm/js/bundle.*.js`):
///
/// - the socket needs a guest session: `api/user/info` sets the `FM_SESS`
///   cookie ([session]), without which the handshake is refused (HTTP 403);
/// - the client joins its room with a JSON text frame ([join]) and the
///   server answers it by the join's `uuid`;
/// - every server message is a binary frame, flag 1 and the UTF-8 length
///   (24 bits, little-endian) before a Brotli stream ([text]), holding a
///   JSON object or an array of them; the heartbeat `❤️` goes out every 30 s
///   as text and comes back as text.
abstract final class MissevanDanmakuProtocol {
  /// Heartbeat period: the site's `IMHeartbeat` (30 000 ms). The server
  /// drops a client that sends nothing for about two minutes.
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// The heartbeat, sent as a text frame; the server echoes it.
  static const String heartbeat = '❤️';

  /// How long the join's answer may take: the site gives up on any IM
  /// request after 5 s (510010002 "IM 请求超时") and reconnects.
  static const Duration joinTimeout = Duration(seconds: 5);

  /// The first byte of a binary frame whose payload is Brotli.
  static const int brotliFlag = 1;

  /// Bytes before a frame's Brotli stream: the flag and the length.
  static const int headerLength = 4;

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  /// A cookie value: RFC 6265 cookie-octets (no space, quote, comma,
  /// semicolon or backslash); it goes into the handshake's `cookie` header.
  static final RegExp _cookieValue = RegExp(r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]+$');

  static final RegExp _sessionCookie = RegExp(r'^\s*FM_SESS=([^;]*)');

  /// The chat socket of room [roomId] at [url] (`MissevanDanmakuArgs.url`):
  /// [url] when it is a `wss` URL on `missevan.com` or a subdomain without
  /// user info (the session cookie goes there), for this room. A URL
  /// without `room_id` gets it (the server answers such a handshake with
  /// HTTP 400, and refuses a join of any room but the URL's); anything else
  /// is replaced by `wss://im.missevan.com/ws?room_id={roomId}`, the form
  /// the site uses.
  static Uri endpoint(Uri url, {required String roomId}) {
    final fallback = Uri(scheme: 'wss', host: 'im.missevan.com', path: '/ws', queryParameters: {'room_id': roomId});
    if (url.scheme != 'wss' ||
        url.userInfo.isNotEmpty ||
        (url.host != 'missevan.com' && !url.host.endsWith('.missevan.com'))) {
      return fallback;
    }
    final Map<String, List<String>> query;
    try {
      query = url.queryParametersAll;
    } on FormatException {
      return fallback;
    }
    final named = query['room_id'];
    if (named == null) return url.replace(queryParameters: {...query, 'room_id': roomId});
    return named.length == 1 && named.single == roomId ? url : fallback;
  }

  /// The `FM_SESS` value that [setCookie] (the `Set-Cookie` headers of the
  /// guest session answer) sets, or null. `FM_SESS.sig` is not needed.
  static String? session(Iterable<String> setCookie) {
    for (final header in setCookie) {
      final value = _sessionCookie.firstMatch(header)?.group(1)?.trim();
      if (value != null && _cookieValue.hasMatch(value)) return value;
    }
    return null;
  }

  /// Handshake headers: [headers] (the API's, with the site's `Origin`, as
  /// the site's page sends them) with the session cookie in place of any
  /// cookie they carry. The cookie is what the server requires.
  static Map<String, String> handshakeHeaders(Map<String, String> headers, String session) => {
    for (final entry in headers.entries)
      if (entry.key.toLowerCase() != 'cookie') entry.key: entry.value,
    'cookie': 'FM_SESS=$session',
  };

  /// The join of [roomId] (sent as a number) with [uuid], as the site
  /// writes it; after the room was joined once, the site's rejoins carry
  /// `reconnect: 1` ([reconnect]).
  static String join(String roomId, {required String uuid, bool reconnect = false}) => jsonEncode({
    'action': 'join',
    'uuid': uuid,
    'type': 'room',
    'room_id': int.parse(roomId),
    if (reconnect) 'reconnect': 1,
  });

  /// A random version 4 UUID, the join's `uuid`.
  static String uuid(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// The text of a received frame, as the site's client reads it: a text
  /// frame as it is; a binary one longer than its header with flag 1,
  /// Brotli-decoded, when the result has exactly the length the header
  /// declares (decoding stops once it would exceed it). Anything else is
  /// null: another flag, a short frame, a stream that does not decode.
  static String? text(Object? data) {
    if (data is String) return data;
    if (data is! List<int> || data.length <= headerLength || data[0] != brotliFlag) return null;
    final length = data[1] | data[2] << 8 | data[3] << 16;
    final Uint8List plain;
    try {
      plain = brotliDecode(data.sublist(headerLength), maxOutput: length);
    } on FormatException {
      return null;
    }
    if (plain.length != length) return null;
    return utf8.decode(plain, allowMalformed: true);
  }

  /// Reads one frame of room [roomId]'s socket, whose join was sent with
  /// [uuid].
  ///
  /// The frame's JSON is an object or an array of objects, each named by
  /// `type` and `event`:
  ///
  /// - `room`/`join` with this [uuid]: the answer to the join
  ///   ([MissevanDanmakuFrame.joined]);
  /// - `message`/`new`, and `message`/`danmaku` (a paid danmaku, a chat
  ///   line the site flies in a bubble): chat ([chat]);
  /// - `room`/`statistics`: heat and the listeners in the room now
  ///   ([audience]).
  ///
  /// An object naming another room (`room_id`) is skipped, as the site's
  /// client skips it; so is everything else (gifts, entries, ranks, global
  /// notices, the heartbeat's echo), a frame that is not JSON, and an item
  /// that is not an object. A field of the wrong type costs only that field
  /// or that line, never the frame.
  static MissevanDanmakuFrame decode(Object? data, {required String roomId, required String uuid}) {
    final text = MissevanDanmakuProtocol.text(data);
    if (text == null || text == heartbeat) return const MissevanDanmakuFrame();
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const MissevanDanmakuFrame();
    }
    final messages = <LiveMessage>[];
    bool? joined;
    var refusal = '';
    for (final item in root is List ? root : [root]) {
      if (item is! Map) continue;
      final type = item['type'];
      final event = item['event'];
      if (type == 'room' && event == 'join') {
        if (item['uuid'] != uuid) continue;
        final code = item['code'];
        joined = code == 0;
        if (!joined) refusal = [_scalar(code), if (item['info'] case final String info) info].join(' ').trim();
        continue;
      }
      final room = item['room_id'];
      if (room != null && '$room' != roomId) continue;
      switch ((type, event)) {
        case ('message', 'new' || 'danmaku'):
          if (chat(item) case final message?) messages.add(message);
        case ('room', 'statistics'):
          messages.addAll(audience(item['statistics']));
        default:
          break;
      }
    }
    return MissevanDanmakuFrame(messages: messages, joined: joined, refusal: refusal);
  }

  /// One chat line, or null when its `message` is blank or neither text nor
  /// a number.
  ///
  /// Fields: `message` the text (trimmed), `user.username` and
  /// `user.user_id`, `msg_id` the message id, `time` the time in
  /// milliseconds (the site's; recorded lines have none). The user's
  /// `titles` carry the level (`type` `level`) and the fan medal (`medal`:
  /// its `name` and `level`). The site gives no text colour: white.
  static LiveMessage? chat(Map<Object?, Object?> item) {
    final text = _scalar(item['message']).trim();
    if (text.isEmpty) return null;
    final user = item['user'];
    final titles = user is Map && user['titles'] is List ? user['titles'] as List<Object?> : const <Object?>[];
    Map<Object?, Object?>? title(String type) =>
        titles.whereType<Map<Object?, Object?>>().where((entry) => entry['type'] == type).firstOrNull;
    final level = _int(title('level')?['level']);
    final medal = title('medal');
    final medalLevel = _int(medal?['level']);
    final medalName = medal?['name'];
    final time = item['time'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: user is Map ? _scalar(user['username']) : '',
      userId: user is Map ? _scalar(user['user_id']) : '',
      message: text,
      color: LiveMessageColor.white,
      userLevel: level == null ? '' : '$level',
      fansName: medalName is String ? medalName : '',
      fansLevel: medalLevel == null ? '' : '$medalLevel',
      messageId: _scalar(item['msg_id']),
      sentAt: time is int && time > 0 && time <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(time) : null,
    );
  }

  /// The figures of a `room`/`statistics` message's [statistics]: `score`,
  /// the heat the site shows, and `online`, the listeners in the room now
  /// (the room lists and the detail carry an `online` that is always 0).
  /// Each is a whole number, not negative, or left out.
  static List<LiveMessage> audience(Object? statistics) {
    if (statistics is! Map) return const [];
    return [
      for (final (key, kind) in const [
        ('score', LiveAudienceMetricKind.popularity),
        ('online', LiveAudienceMetricKind.onlineViewers),
      ])
        if (_int(statistics[key]) case final value? when value >= 0)
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: LiveAudienceUpdate(kind: kind, value: value),
          ),
    ];
  }

  /// A whole number: a JSON integer or its text.
  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };

  static String _scalar(Object? value) => value is String || value is num ? '$value' : '';
}

/// Missevan's danmaku connection: a guest session over [LiveHttp], then the
/// room's chat socket over the shared WebSocket runtime.
///
/// - A guest session is asked at every [connect], up to three times (0.5 s
///   and 1 s apart); without one the run ends with
///   [DanmakuCloseReason.credentialsUnavailable]. Reconnects reuse it (it
///   lasts three days).
/// - At every open the socket sends the join; the room counts as joined
///   when the server accepts it, and a join not answered within 5 s drops
///   the socket, as the site's client does.
/// - A refused join asks a new guest session and reopens the socket without
///   a notice, at most three times per [connect]; the next refusal ends the
///   run with [DanmakuCloseReason.connectionFailed].
/// - The heartbeat goes out every 30 s and the server echoes it, so a
///   socket silent for max(3 × 30 s, 90 s) = 90 s is replaced.
///
/// The app registers it as `SiteIds.missevan: () =>
/// MissevanDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `MissevanSite` and its proxy policy.
final class MissevanDanmakuConnection extends DanmakuSocketConnection<MissevanDanmakuArgs> {
  /// Creates the connection; `http` asks for the guest sessions and [proxy]
  /// routes the socket. `connector` replaces `dart:io`'s handshake,
  /// `sessionRetryDelay` the step between session attempts and `random`
  /// the source of the join's `uuid` (tests).
  new({
    required this._http,
    super.proxy,
    super.connector,
    this._sessionRetryDelay = const Duration(milliseconds: 500),
    Random? random,
  }) : _random = random ?? Random.secure(),
       super(site: SiteIds.missevan, policy: socketPolicy);

  /// Socket timing: the site's 30 s heartbeat and 5 s for the join's answer;
  /// the rest are the shared runtime's defaults.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: MissevanDanmakuProtocol.heartbeatInterval,
    joinTimeout: MissevanDanmakuProtocol.joinTimeout,
  );

  /// Requests per attempt to get a guest session.
  static const int sessionAttempts = 3;

  /// Longest wait for one guest session answer.
  static const Duration sessionTimeout = Duration(seconds: 5);

  /// Refused joins answered with a new session and socket, per [connect].
  static const int maxRejoins = 3;

  final LiveHttp _http;
  final Duration _sessionRetryDelay;
  final Random _random;
  _Room? _room;

  @override
  @protected
  Future<DanmakuSocketTarget> target(MissevanDanmakuArgs args, DanmakuRun run) async {
    final roomId = args.roomId.trim();
    if (!MissevanApi.idPattern.hasMatch(roomId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No room');
    }
    final room = _room = _Room(run, roomId, MissevanDanmakuProtocol.endpoint(args.url, roomId: roomId), args.headers);
    final session = await _session(room);
    if (!run.isActive) return const DanmakuSocketTarget(endpoints: []);
    if (session == null) throw DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: room.lastFailure);
    return room.target(session);
  }

  /// A guest session for [room]: up to [sessionAttempts] requests, or null
  /// when none set one or the run ended. Redirects are not followed (they
  /// would lose the cookie; the API requests do not follow them either).
  Future<String?> _session(_Room room) async {
    for (var attempt = 0; attempt < sessionAttempts; attempt++) {
      if (attempt > 0 && !await room.run.delay(_sessionRetryDelay * attempt)) return null;
      try {
        final response = await _http.send(
          LiveRequest(
            site: SiteIds.missevan,
            url: MissevanApi.guestSession,
            headers: room.headers,
            followRedirects: false,
            timeout: sessionTimeout,
            cancel: room.cancel,
          ),
        );
        if (!room.run.isActive) return null;
        final session = response.isSuccess
            ? MissevanDanmakuProtocol.session(response.headers['set-cookie'] ?? const [])
            : null;
        if (session != null) return session;
        room.lastFailure = response.isSuccess ? 'No guest session' : 'Guest session: HTTP ${response.status}';
      } on Object catch (error) {
        if (!room.run.isActive) return null;
        room.lastFailure = '$error';
      }
    }
    return null;
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
    final uuid = room.uuid = MissevanDanmakuProtocol.uuid(_random);
    session.send(MissevanDanmakuProtocol.join(room.roomId, uuid: uuid, reconnect: room.joinedBefore));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final room = _of(session);
    if (room == null) return;
    final frame = MissevanDanmakuProtocol.decode(data, roomId: room.roomId, uuid: room.uuid);
    frame.messages.forEach(session.message);
    switch (frame.joined) {
      case true when !session.isConnected:
        room.joinedBefore = true;
        session.ready();
      case false:
        session
          ..cancelJoinTimeout()
          ..markDisconnected();
        unawaited(_refused(session, room, frame.refusal));
      default:
        break;
    }
  }

  /// Answers a refused join with a new guest session and socket, without a
  /// notice (the archived v4 asked a new session too; the site reconnects).
  Future<void> _refused(DanmakuSocketSession session, _Room room, String refusal) async {
    if (room.refreshing) return;
    if (room.rejoins >= maxRejoins) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Join refused: $refusal');
      return;
    }
    room
      ..refreshing = true
      ..rejoins += 1;
    final String? fresh;
    try {
      fresh = await _session(room);
    } finally {
      // The new socket may be refused too; that refusal starts the next
      // round.
      room.refreshing = false;
    }
    if (!session.isActive) return;
    if (fresh == null) {
      session.run.closed(DanmakuCloseReason.credentialsUnavailable, detail: room.lastFailure);
      return;
    }
    await session.reopen(room.target(fresh));
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => MissevanDanmakuProtocol.heartbeat;

  @override
  @protected
  Future<void> stop() async {
    _room = null;
    await super.stop();
  }
}

/// The chat of one run: its room, socket and session requests.
final class _Room {
  new(this.run, this.roomId, this.endpoint, this.headers) {
    unawaited(run.ended.then((_) => cancel.cancel()));
  }

  final DanmakuRun run;
  final String roomId;
  final Uri endpoint;

  /// The API headers, sent with the session request and the handshake.
  final Map<String, String> headers;
  final CancelToken cancel = CancelToken();

  /// The `uuid` of the current socket's join.
  String uuid = '';

  /// Whether this run joined the room before (rejoins carry `reconnect`).
  bool joinedBefore = false;
  String lastFailure = '';
  int rejoins = 0;
  bool refreshing = false;

  DanmakuSocketTarget target(String session) =>
      DanmakuSocketTarget(endpoints: [endpoint], headers: MissevanDanmakuProtocol.handshakeHeaders(headers, session));
}
