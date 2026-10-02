import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/binary.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/exact_websocket.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';

/// One packet of SOOP's chat protocol ([SoopDanmakuProtocol.packets]): its
/// service number (1 login, 2 join, 5 chat, …) and body.
typedef SoopPacket = ({int service, Uint8List body});

/// SOOP's chat protocol (the codec of 3.x `SoopDanmaku`,
/// docs/D-弹幕/D01-平台弹幕协议/D01.8-SOOP弹幕/record.md), without I/O.
///
/// A packet is `ESC TAB`, a 4-digit decimal service, a 6-digit decimal body
/// length in bytes, `00` and the body, whose fields are separated by form
/// feeds; one frame may carry several packets. The client sends its packets
/// as text frames, the server answers in binary frames.
abstract final class SoopDanmakuProtocol {
  /// Subprotocol the chat edges require.
  static const List<String> protocols = ['chat'];

  /// Heartbeat period (3.x `heartbeatTime`, 20 000 ms).
  static const Duration heartbeatInterval = Duration(seconds: 20);

  /// Pause between the login and the join packet (3.x `joinRoom`).
  static const Duration joinDelay = Duration(milliseconds: 200);

  /// Service number of a chat line.
  static const int chatService = 5;

  /// Header bytes before a packet's body.
  static const int headerLength = 14;

  static const String _escape = '\x1b\t';
  static const String _separator = '\f';

  /// The login packet (service 1), sent as soon as the socket opens.
  static const String login = '${_escape}000100000600$_separator$_separator${_separator}16$_separator';

  /// The keep-alive packet (service 0).
  static const String heartbeat = '${_escape}000000000100$_separator';

  /// The packet joining chat room [chatNo] (service 2); the length counts
  /// UTF-8 bytes, as 3.x did.
  static String join(String chatNo) =>
      '${_escape}0002${(utf8.encode(chatNo).length + 6).toString().padLeft(6, '0')}00'
      '$_separator$chatNo${_separator * 5}';

  /// Endpoints of a room, in order: 3.x's TLS port (`CHPT + 1`), then the
  /// plain port (`CHPT`), which answers where the TLS port drops the
  /// connection after the ClientHello (REG-SOOP-002).
  static List<Uri> endpoints(SoopDanmakuArgs args) => [args.url, args.plainUrl];

  /// [headers] with every name spelled as 3.x wrote it (`user-agent` →
  /// `User-Agent`, `sec-fetch-dest` → `Sec-Fetch-Dest`): the chat edges see
  /// the handshake as written.
  static Map<String, String> handshakeHeaders(Map<String, String> headers) => {
    for (final MapEntry(:key, :value) in headers.entries) headerName(key): value,
  };

  /// [name] with each word capitalised and the rest in lower case.
  static String headerName(String name) => name
      .split('-')
      .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join('-');

  /// What may go over the plain port: [headers] without `Cookie`. The user's
  /// cookie only travels over TLS; the chat never needed it (the archived
  /// v4 joined anonymously).
  static Map<String, String> plainHeaders(Map<String, String> headers) => {
    for (final MapEntry(:key, :value) in headers.entries)
      if (key.toLowerCase() != 'cookie') key: value,
  };

  /// The packets of [frame], in order (3.x `decodeMessage`). The split stops
  /// at a packet without the `ESC TAB` prefix, with a service or length that
  /// is not a number, with a negative length, or running past the end of the
  /// frame; the rest of the frame is dropped. Fewer than 14 bytes left over
  /// are ignored, and so are the two bytes after the length.
  static List<SoopPacket> packets(List<int> frame) {
    final bytes = frame is Uint8List ? frame : Uint8List.fromList(frame);
    final packets = <SoopPacket>[];
    var offset = 0;
    while (offset + headerLength <= bytes.length) {
      if (bytes[offset] != 0x1b || bytes[offset + 1] != 0x09) break;
      final service = int.tryParse(ascii.decode(bytes.sublist(offset + 2, offset + 6), allowInvalid: true));
      final length = int.tryParse(ascii.decode(bytes.sublist(offset + 6, offset + 12), allowInvalid: true));
      if (service == null || length == null || length < 0) break;
      final end = offset + headerLength + length;
      if (end > bytes.length) break;
      packets.add((service: service, body: Uint8List.sublistView(bytes, offset + headerLength, end)));
      offset = end;
    }
    return packets;
  }

  /// The chat lines of one server [frame] (3.x `decodeMessage`); other
  /// services (viewer lists, flags, balloons, …) are ignored.
  static List<LiveMessage> decode(List<int> frame) => [
    for (final packet in packets(frame))
      if (packet.service == chatService) ?chat(packet.body),
  ];

  /// A chat line (3.x `_decodeChatPacket`): text in field 1, nick in field
  /// 6, both trimmed, in white, and the sender's id from field 2 ([userId]).
  /// Null with fewer than seven fields or an empty text or nick.
  ///
  /// 3.x also dropped the texts `1` and `-1` and every text holding `|`;
  /// the web player shows them (`SVC_CHATMESG` in LivePlayer.js takes the
  /// text field whole; `|` only separates the two flags of field 7), and so
  /// does this since M5.F B-6.
  static LiveMessage? chat(List<int> body) {
    final fields = [for (final part in ListUtil.splitList(body, 0x0c)) utf8.decode(part, allowMalformed: true)];
    if (fields.length <= 6) return null;
    final text = fields[1].trim();
    final name = fields[6].trim();
    if (text.isEmpty || name.isEmpty) return null;
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name,
      userId: userId(fields[2]),
      message: text,
      color: LiveMessageColor.white,
    );
  }

  /// The sender's id of a chat line's field 2, without the `(n)` a second
  /// session of the same account gets (`loo3672(2)` → `loo3672`), as the
  /// web player's `realID` reads it: the run of word characters followed
  /// only by digits and parentheses up to the end; the trimmed field itself
  /// when there is no such run.
  static String userId(String field) {
    final id = field.trim();
    return _realId.firstMatch(id)?.group(1) ?? id;
  }

  static final RegExp _realId = RegExp(r'(\w+)[()0-9]*$');
}

/// SOOP's danmaku connection (3.x `SoopDanmaku`): a WebSocket with the
/// `chat` subprotocol and the room's handshake headers, opened by a
/// connector that keeps the header spelling
/// ([connectExactWebSocketViaRoute]). An open socket counts as joined; the
/// login packet follows at once, the join packet 200 ms later, a keep-alive
/// every 20 s, and a socket silent for 90 s is replaced. The TLS port comes
/// first, the plain port second.
///
/// The app registers it as `SiteIds.soop: () =>
/// SoopDanmakuConnection(proxy: …)`: the cookie and the headers come with
/// [SoopDanmakuArgs]. The socket takes the platform's proxy route (M5.F
/// B-6; 3.x always dialled the edge directly).
final class SoopDanmakuConnection extends DanmakuSocketConnection<SoopDanmakuArgs> {
  /// Creates the connection; [proxy] routes the socket (an HTTP proxy is
  /// asked for a `CONNECT` tunnel), `connector` replaces the case-sensitive
  /// handshake (tests). Either way the cookie never goes to the plain port.
  new({super.proxy, SocketConnector? connector})
    : super(
        site: SiteIds.soop,
        policy: socketPolicy,
        connector: _withoutPlainCookie(connector ?? connectExactWebSocketViaRoute),
      );

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 20 s heartbeat,
  /// so a socket silent for max(3 × 20 s, 90 s) = 90 s is replaced. No join
  /// timer: 3.x counted an open socket as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: SoopDanmakuProtocol.heartbeatInterval,
  );

  /// Stands for a room without chat data (null arguments).
  static final SoopDanmakuArgs _noChatData = SoopDanmakuArgs(
    url: Uri(),
    plainUrl: Uri(),
    chatNo: '',
    headers: const {},
  );

  static SocketConnector _withoutPlainCookie(SocketConnector connector) =>
      (endpoint, {required headers, required protocols, required route, required connectTimeout}) => connector(
        endpoint,
        headers: endpoint.scheme == 'wss' ? headers : SoopDanmakuProtocol.plainHeaders(headers),
        protocols: protocols,
        route: route,
        connectTimeout: connectTimeout,
      );

  String _chatNo = '';
  int _opens = 0;

  /// Joins the room of [args]. Null arguments (a room whose details carry no
  /// chat server) end with [DanmakuCloseReason.connectionFailed], as 3.x
  /// reported "服务器连接失败"; other types throw [ArgumentError].
  @override
  Future<void> connect(Object? args) => super.connect(args ?? _noChatData);

  @override
  Future<DanmakuSocketTarget> target(SoopDanmakuArgs args, DanmakuRun run) async {
    if (identical(args, _noChatData)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No chat server');
    }
    _chatNo = args.chatNo;
    return DanmakuSocketTarget(
      endpoints: SoopDanmakuProtocol.endpoints(args),
      headers: SoopDanmakuProtocol.handshakeHeaders(args.headers),
      protocols: SoopDanmakuProtocol.protocols,
    );
  }

  @override
  void onOpen(DanmakuSocketSession session) {
    // 3.x: ready as soon as the socket opens, then the login and, 200 ms
    // later, the join.
    session
      ..ready()
      ..send(SoopDanmakuProtocol.login);
    unawaited(_join(session, ++_opens));
  }

  /// Sends the join packet unless the run ended or another socket opened
  /// meanwhile (that one sends its own).
  Future<void> _join(DanmakuSocketSession session, int open) async {
    if (!await session.run.delay(SoopDanmakuProtocol.joinDelay) || open != _opens) return;
    session.send(SoopDanmakuProtocol.join(_chatNo));
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) {
    // Chat comes in binary frames; 3.x only logged text frames.
    if (data is! List<int>) return;
    SoopDanmakuProtocol.decode(data).forEach(session.message);
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => SoopDanmakuProtocol.heartbeat;
}
