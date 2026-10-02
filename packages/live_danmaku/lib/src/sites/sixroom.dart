import 'dart:async';
import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What one Six Rooms chat frame held ([SixRoomDanmakuProtocol.decode]).
@immutable
final class SixRoomDanmakuFrame {
  /// Creates the result.
  const new({this.messages = const [], this.joined = false, this.loginFailed = false, this.refusal});

  /// Nothing to act on.
  static const SixRoomDanmakuFrame empty = SixRoomDanmakuFrame();

  /// Chat, in order.
  final List<LiveMessage> messages;

  /// The login was accepted (`command=result`, `content=login.success`).
  final bool joined;

  /// The login was refused (`content=login.failed`); the room page logs in
  /// again.
  final bool loginFailed;

  /// An error flag on which the room page stops its socket for good (kicked,
  /// room full, paid or password room, room closed, banned), as
  /// `flag <code>` and the server's text when it sent one; null otherwise.
  final String? refusal;
}

/// Six Rooms' room chat, as the public room page (`v.6.cn/<room>`) runs it
/// anonymously (docs/D-弹幕/D01-平台弹幕协议/D01.28-六间房弹幕/record.md), without I/O. The page's
/// scripts: `chunkimport-pcwebsocket_*.js` (the socket client), `chunk8104_*`
/// (`Room.Socket`, `Room.Msg`, the error flags), `chunk6236_*` (the codec),
/// `chunkimport-room_2016_*` (the chat list).
///
/// - The chat servers of a room come from `GET /room/getChat.php?rid=<the
///   broadcaster's user id>`: `{"websock": ["<host>:<port>", …]}`, four
///   `*.6rooms.com` hosts on the room's shard port. The page shuffles them
///   and moves to the next one at every new login.
/// - Every frame is text: a line with the byte length of the rest, then
///   `key=value` lines (`\r\n`), each frame one command.
/// - The client logs in with `command=login`, its user id, its `encpass`
///   (empty for a guest) and the broadcaster's user id as `roomid`; a guest's
///   user id is a random number from 1800000000 to 1899999999 (the page's
///   `guest_id`). The server answers `command=result`, `content=
///   login.success` (or `login.failed`).
/// - The client then sends the page's heartbeat, `noop` deflated
///   (`y8vPLwAA`), every 16 s; a socket that sends nothing is closed after
///   20 s (measured). The server answers `send.success`, and a guest that
///   never asked for its own details (`priv_info`, which this client does not
///   send) also gets flag 205.
/// - Everything else comes as `command=receivemessage`, `enc=yes|no`,
///   `content=<Base64>`: with `enc=yes` raw DEFLATE with `+`, `/`, `=`
///   written `(`, `)`, `@`; a JSON object `{"flag": "001", "content": {…}}`
///   whose `typeID` says what it is (101 public chat, 110 a list of them,
///   1413 a list of any messages, 108 a fly-screen message). Another flag is
///   an error.
abstract final class SixRoomDanmakuProtocol {
  /// Where a room's chat servers are asked for.
  static final Uri serversUrl = Uri.parse('${SixRoomApi.origin}/room/getChat.php');

  /// The page's heartbeat period (`_heartbeat`, 16 s).
  static const Duration heartbeatInterval = Duration(seconds: 16);

  /// How long the login may take (the page's `timeout`, 6 s).
  static const Duration joinTimeout = Duration(seconds: 6);

  /// Refused logins in a row after which the connection gives up (the page
  /// logs in again up to 100 times; any frame resets the runtime's count, so
  /// the connection counts refusals itself).
  static const int maxRefusals = 3;

  /// Handshake headers: the site's origin and the adapter's desktop UA, as
  /// the room page sends them (the server also accepts a handshake without
  /// an origin).
  static const Map<String, String> socketHeaders = {'origin': SixRoomApi.origin, 'user-agent': SixRoomApi.userAgent};

  /// The heartbeat frame: `noop`, deflated and encoded (the page's
  /// `y8vPLwAA`).
  static const String heartbeat = 'command=sendmessage\r\ncontent=y8vPLwAA\r\n';

  /// Error flags on which the room page stops its socket (`parseErr`): 101
  /// kicked, 102 full, 103 paid room, 104 password room, 109–114 banned or
  /// removed, 204 room closed, 305 not allowed by rank, 306 log in again.
  /// Other flags only prompt a user who speaks (or, 205, a guest that never
  /// asked for its details) and are ignored.
  static const Set<String> stoppingFlags = {
    '101',
    '102',
    '103',
    '104',
    '109',
    '110',
    '111',
    '112',
    '113',
    '114',
    '204',
    '305',
    '306',
  };

  /// Public chat (the page's `parsePub`).
  static const String publicChat = '101';

  /// A list of public chat messages (`content`), each read like [publicChat].
  static const String publicChatList = '110';

  /// A fly-screen message (飞屏, a paid message flying over the video;
  /// `Room.GiftFly`).
  static const String flyScreen = '108';

  /// A list of any messages (`content`), each dispatched by its own type.
  static const String batch = '1413';

  /// The text of a public chat message that is a picture (`picEmoji.pic`: the
  /// page shows the image instead of the text, with the alternative text
  /// AI表情).
  static const String pictureText = '[AI表情]';

  /// Largest inflated message.
  static const int maxInflatedBytes = 4 * 1024 * 1024;

  /// Deepest nesting of lists ([batch]) that is read.
  static const int maxDepth = 4;

  /// Largest [DateTime], in seconds.
  static const int _maxEpochSeconds = 8640000000000;

  static final RegExp _roomId = RegExp(r'^[1-9]\d{1,11}$');
  static final RegExp _server = RegExp(r'^([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?):(\d{1,5})$');

  /// The request for the chat servers of [args]' room, as the page sends it
  /// (jQuery's JSON request from the room page); sent as `sixroom` (its
  /// proxy route), no redirect followed.
  static LiveRequest serverRequest(
    SixRoomDanmakuArgs args, {
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => LiveRequest(
    site: SiteIds.sixRoom,
    url: serversUrl.replace(queryParameters: {'rid': args.userId}),
    headers: {
      'user-agent': SixRoomApi.userAgent,
      'accept': 'application/json, text/javascript, */*; q=0.01',
      'accept-language': SixRoomApi.webHeaders['accept-language']!,
      'referer': SixRoomApi.link(args.roomId),
      'x-requested-with': 'XMLHttpRequest',
    },
    followRedirects: false,
    timeout: timeout,
    cancel: cancel,
  );

  /// The chat servers of a `getChat.php` [response] (`websock`), as
  /// `wss://<host>:<port>` in the answer's order: hosts on `6rooms.com`,
  /// ports 1–65535, each once. Throws [FormatException] for a status that is
  /// not 2xx or an answer without such a server (a missing room gets `[]`).
  static List<Uri> servers(LiveResponse response) {
    if (!response.isSuccess) throw FormatException('getChat.php answered HTTP ${response.status}');
    final Object? root;
    try {
      root = response.json;
    } on FormatException {
      throw const FormatException('getChat.php answered no JSON');
    }
    final listed = root is Map ? root['websock'] : null;
    final servers = <Uri>[];
    for (final entry in listed is List ? listed : const <Object?>[]) {
      final match = entry is String ? _server.firstMatch(entry.trim()) : null;
      if (match == null) continue;
      final host = match[1]!.toLowerCase();
      final port = int.parse(match[2]!);
      if (port < 1 || port > 65535 || (host != '6rooms.com' && !host.endsWith('.6rooms.com'))) continue;
      final server = Uri(scheme: 'wss', host: host, port: port);
      if (!servers.contains(server)) servers.add(server);
    }
    if (servers.isEmpty) throw const FormatException('getChat.php answered no chat server');
    return servers;
  }

  /// [args] if they name a room: a room number and a broadcaster's user id
  /// (`SixRoomApi.isUserId`), trimmed; null otherwise.
  static SixRoomDanmakuArgs? checked(SixRoomDanmakuArgs args) {
    final roomId = args.roomId.trim();
    final userId = args.userId.trim();
    if (!_roomId.hasMatch(roomId) || !SixRoomApi.isUserId(userId)) return null;
    return SixRoomDanmakuArgs(roomId: roomId, userId: userId);
  }

  /// A guest's user id, as the page makes one without a `_LiveGuestUser`
  /// cookie: `Math.floor(1e8 * Math.random() + 18e8)`.
  static int guestId(Random random) => 1800000000 + random.nextInt(100000000);

  /// The login of guest [guestId] to the room of broadcaster [userId], with
  /// the empty `encpass` of a guest.
  static String login(int guestId, String userId) => 'command=login\r\nuid=$guestId\r\nencpass=\r\nroomid=$userId\r\n';

  /// The `key=value` lines of a frame; a line without `=` (the length line)
  /// is skipped, a key keeps its last value.
  static Map<String, String> fields(String frame) => {
    for (final line in frame.split('\r\n'))
      if (line.indexOf('=') case final at when at > 0) line.substring(0, at): line.substring(at + 1),
  };

  /// The JSON text of a `receivemessage` [content]: Base64 in the site's
  /// alphabet (standard Base64 reads the same), raw DEFLATE when [deflated].
  /// Throws [FormatException] when it is neither.
  static String payload(String content, {required bool deflated}) {
    final encoded = content.trim().replaceAll('(', '+').replaceAll(')', '/').replaceAll('@', '=');
    final bytes = base64.decode(base64.normalize(encoded));
    return utf8.decode(deflated ? _inflate(bytes) : bytes, allowMalformed: true);
  }

  static Uint8List _inflate(List<int> bytes) {
    final sink = _BoundedSink(maxInflatedBytes);
    ZLibDecoder(raw: true).startChunkedConversion(sink)
      ..add(bytes)
      ..close();
    return sink.bytes.takeBytes();
  }

  /// One frame (text, or UTF-8 bytes):
  ///
  /// - a `result` says whether the login was accepted or refused; other
  ///   results (`send.success`) say nothing;
  /// - a `receivemessage` with flag `001` gives its chat ([messages]); one
  ///   of the [stoppingFlags] is a [SixRoomDanmakuFrame.refusal]; other flags
  ///   say nothing;
  /// - anything that cannot be read says nothing.
  static SixRoomDanmakuFrame decode(Object? data) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return SixRoomDanmakuFrame.empty;
    final frame = fields(text);
    final content = frame['content'];
    if (content == null) return SixRoomDanmakuFrame.empty;
    switch (frame['command']) {
      case 'result':
        return switch (content.trim()) {
          'login.success' => const SixRoomDanmakuFrame(joined: true),
          'login.failed' => const SixRoomDanmakuFrame(loginFailed: true),
          _ => SixRoomDanmakuFrame.empty,
        };
      case 'receivemessage':
        final Object? root;
        try {
          root = jsonDecode(payload(content, deflated: frame['enc'] == 'yes'));
        } on FormatException {
          return SixRoomDanmakuFrame.empty;
        }
        if (root is! Map) return SixRoomDanmakuFrame.empty;
        final flag = _text(root['flag']);
        if (flag == '001') return SixRoomDanmakuFrame(messages: messages(root['content']));
        if (!stoppingFlags.contains(flag)) return SixRoomDanmakuFrame.empty;
        final said = _text(root['content']);
        return SixRoomDanmakuFrame(refusal: said.isEmpty ? 'flag $flag' : 'flag $flag: $said');
      default:
        return SixRoomDanmakuFrame.empty;
    }
  }

  /// The chat of one message (`content` of a `001` frame), as the page
  /// shows it to a guest:
  ///
  /// - public chat ([publicChat]) and fly-screen messages ([flyScreen]) are
  ///   read with [chat] and [fly];
  /// - a list of public chat ([publicChatList]) gives each entry's [chat];
  /// - a list of messages ([batch]) gives each entry's messages, at most
  ///   [maxDepth] lists deep;
  /// - a message the page hides from a guest ([shownToGuests]) and every
  ///   other type (entries, gifts, rankings, PK states, room notices) give
  ///   nothing.
  static List<LiveMessage> messages(Object? message) {
    final found = <LiveMessage>[];
    _collect(message, 0, found);
    return found;
  }

  static void _collect(Object? message, int depth, List<LiveMessage> found) {
    if (message is! Map || !shownToGuests(message)) return;
    switch (_text(message['typeID'])) {
      case publicChat:
        if (chat(message) case final LiveMessage line) found.add(line);
      case flyScreen:
        if (fly(message) case final LiveMessage line) found.add(line);
      case publicChatList:
        for (final entry in _list(message['content'])) {
          if (entry is! Map) continue;
          if (chat(entry) case final LiveMessage line) found.add(line);
        }
      case batch when depth < maxDepth:
        for (final entry in _list(message['content'])) {
          _collect(entry, depth + 1, found);
        }
    }
  }

  /// Whether the page shows [message] to a guest (`Room.Msg.get`), with
  /// JavaScript's conversions:
  ///
  /// - not when its client mask `cli` is set (truthy) without the PC bit 1;
  /// - not when it names a wealth level (`newLimitLevel` present and not -1)
  ///   or a star level (`starLimitLevel` a number other than -1): a guest has
  ///   neither.
  static bool shownToGuests(Map<Object?, Object?> message) {
    final cli = message['cli'];
    if (_truthy(cli) && _int32(cli) & 1 == 0) return false;
    if (message.containsKey('newLimitLevel') && jsonInt(message['newLimitLevel']) != -1) return false;
    final star = jsonInt(message['starLimitLevel']);
    return star == null || star == -1;
  }

  static bool _truthy(Object? value) => switch (value) {
    null || false || '' => false,
    final num number => number != 0 && !number.isNaN,
    _ => true,
  };

  static int _int32(Object? value) => switch (value) {
    true => 1,
    final int number => number,
    final double number when number.isFinite => number.truncate(),
    final String text => switch (num.tryParse(text.trim())) {
      final num number when number.isFinite => number.truncate(),
      _ => 0,
    },
    _ => 0,
  };

  /// A public chat message (typeID 101) as white chat, as the page's
  /// `parsePub` shows it, or null:
  ///
  /// - a message without a sender name (`from`) is not shown, unless the
  ///   sender is a "supreme mystery" (`supremeMystery` 1);
  /// - the text is `content` with `&amp;` read as `&` and then its character
  ///   references decoded (the page writes it as HTML), trimmed; a picture
  ///   (`picEmoji.pic`) is [pictureText]; face codes (`/狂笑`) stay as
  ///   written; no text: null;
  /// - the name is `from`, the user id `fid`, the time `tm` (seconds); the
  ///   addressee (`to`) is not shown.
  ///
  /// It has no message id.
  static LiveMessage? chat(Map<Object?, Object?> message) {
    final name = _text(message['from']);
    if (name.isEmpty && jsonInt(message['supremeMystery']) != 1) return null;
    final picture = message['picEmoji'];
    final text = picture is Map && _text(picture['pic']).isNotEmpty ? pictureText : _html(message['content']);
    if (text.isEmpty) return null;
    return _line(name, message, text);
  }

  /// A fly-screen message (typeID 108) as white chat: the name `from`, the
  /// text `content` (read like [chat]'s), the user id `fid` and the time
  /// `tm` when given; null without text. The page flies it over the video
  /// as `<from>说：<content>`.
  static LiveMessage? fly(Map<Object?, Object?> message) {
    final text = _html(message['content']);
    return text.isEmpty ? null : _line(_text(message['from']), message, text);
  }

  static LiveMessage _line(String name, Map<Object?, Object?> message, String text) {
    final time = jsonInt(message['tm']);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name,
      userId: _text(message['fid']),
      message: text,
      sentAt: time != null && time > 0 && time <= _maxEpochSeconds
          ? DateTime.fromMillisecondsSinceEpoch(time * 1000)
          : null,
      color: LiveMessageColor.white,
    );
  }

  static String _html(Object? value) => switch (value) {
    final String text => decodeHtmlEntities(text.replaceAll('&amp;', '&')).trim(),
    final int number => '$number',
    _ => '',
  };

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String _text(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => '$number',
    _ => '',
  };
}

/// Six Rooms' chat connection (new in v4: 3.x had none, the 31-6 upgrade),
/// on the WebSocket runtime: a socket to one of the room's chat servers,
/// logged in as a guest.
///
/// - Every handshake takes the next server of the room's list; the list is
///   asked for (`getChat.php`) at the first handshake and again once each of
///   its servers was used. A request that fails or gives no server counts as
///   a failed handshake: the runtime's backoff and its eight attempts apply.
/// - At every open it logs in with the run's guest id; `login.success` joins
///   and sends a heartbeat at once, as the page does a second later. The
///   login has 6 s; a refused login reconnects, more than three in a row end
///   the connection. A flag on which the page stops its socket ends it too.
/// - The page's `noop` heartbeat every 16 s; the server answers each.
/// - Only chat is reported: public chat and fly-screen messages.
///
/// The app registers it as `SiteIds.sixRoom: () =>
/// SixRoomDanmakuConnection(http: …, proxy: …)`, with the `LiveHttp` it
/// gives `SixRoomSite` (proxy route by the platform id) and its proxy policy
/// for the socket.
final class SixRoomDanmakuConnection extends DanmakuSocketConnection<SixRoomDanmakuArgs> {
  /// Creates the connection. [http] asks for the chat servers; [proxy] routes
  /// the socket; [connector] replaces `dart:io`'s handshake, [policy] the
  /// timing and [random] the source of guest ids (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    Random? random,
  }) => SixRoomDanmakuConnection._(
    _Handshake(http, connector ?? connectIoSocket),
    random ?? Random(),
    proxy: proxy,
    policy: policy,
  );

  new _(this._handshake, this._random, {required super.proxy, required super.policy})
    : super(site: SiteIds.sixRoom, connector: _handshake.call);

  /// The page's timing: the 16 s heartbeat and the 6 s login; the runtime's
  /// defaults otherwise (the silence watchdog at 90 s).
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: SixRoomDanmakuProtocol.heartbeatInterval,
    joinTimeout: SixRoomDanmakuProtocol.joinTimeout,
  );

  final _Handshake _handshake;
  final Random _random;

  @override
  @protected
  Future<DanmakuSocketTarget> target(SixRoomDanmakuArgs args, DanmakuRun run) async {
    final checked = SixRoomDanmakuProtocol.checked(args);
    if (checked == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable room or broadcaster');
    }
    final chat = _handshake.chat = _Chat(run, checked, SixRoomDanmakuProtocol.guestId(_random));
    return DanmakuSocketTarget(endpoints: [chat.endpoint], headers: SixRoomDanmakuProtocol.socketHeaders);
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
    chat.joined = false;
    session.send(SixRoomDanmakuProtocol.login(chat.guestId, chat.args.userId));
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final frame = SixRoomDanmakuProtocol.decode(data);
    if (frame.refusal case final refusal?) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: $refusal');
      return;
    }
    if (frame.loginFailed) {
      chat.joined = false;
      if (++chat.refusals > SixRoomDanmakuProtocol.maxRefusals) {
        session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Chat refused: login.failed');
      } else {
        session.reconnect();
      }
      return;
    }
    if (frame.joined && !chat.joined) {
      chat
        ..joined = true
        ..refusals = 0;
      session
        ..ready()
        ..heartbeat();
    }
    for (final message in frame.messages) {
      if (!session.isActive) return;
      session.message(message);
    }
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) =>
      _of(session) == null ? null : SixRoomDanmakuProtocol.heartbeat;

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.cancel.cancel();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [SixRoomDanmakuConnection]: the next chat server of the
/// run's room, asking for the list first when it is used up.
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
    if (chat.next >= chat.servers.length) {
      final response = await _http.send(
        SixRoomDanmakuProtocol.serverRequest(chat.args, timeout: connectTimeout, cancel: chat.cancel),
      );
      final servers = SixRoomDanmakuProtocol.servers(response);
      if (!chat.run.isActive) throw StateError('The chat was closed');
      chat
        ..servers = servers
        ..next = 0;
    }
    final server = chat.servers[chat.next++];
    return await _connect(server, headers: headers, protocols: protocols, route: route, connectTimeout: connectTimeout);
  }
}

/// One run's chat: the room, the guest, the room's chat servers and the
/// state of the current socket.
final class _Chat {
  new(this.run, this.args, this.guestId) {
    unawaited(run.ended.then((_) => cancel.cancel()));
  }

  final DanmakuRun run;
  final SixRoomDanmakuArgs args;

  /// The guest's user id, the same for every login of the run.
  final int guestId;

  final CancelToken cancel = CancelToken();

  /// The address the runtime is given: the room's server list, which every
  /// handshake turns into its next chat server.
  Uri get endpoint => SixRoomDanmakuProtocol.serversUrl.replace(queryParameters: {'rid': args.userId});

  /// The room's chat servers, in the order of the last answer.
  List<Uri> servers = const [];

  /// The next server to use; the list is asked for again once it passes the
  /// end.
  int next = 0;

  /// Whether the current socket's login was accepted.
  bool joined = false;

  /// Logins refused in a row.
  int refusals = 0;
}

/// Collects inflated bytes and fails once they pass [limit], so a highly
/// compressible message is rejected before it is all in memory.
final class _BoundedSink implements Sink<List<int>> {
  new(this.limit);

  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (chunk.length > limit - bytes.length) {
      throw FormatException('Six Rooms inflated message exceeds $limit bytes');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
