import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';

/// Little-endian reader of YY's marshalled packets (spec/sites/yy.md §7.2).
final class YyReader {
  /// Reads [bytes] from [offset].
  factory(List<int> bytes, [int offset = 0]) =>
      YyReader._(bytes is Uint8List ? bytes : Uint8List.fromList(bytes), offset);

  new _(this._bytes, this.offset) : _view = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _view;

  /// Read position.
  int offset;

  /// Bytes left.
  int get remaining => _bytes.length - offset;

  void _need(int count) {
    if (count < 0 || offset + count > _bytes.length) {
      throw FormatException('YY packet truncated at $offset (need $count, have $remaining)');
    }
  }

  /// One byte.
  int u8() {
    _need(1);
    return _bytes[offset++];
  }

  /// A 16-bit number.
  int u16() {
    _need(2);
    final value = _view.getUint16(offset, Endian.little);
    offset += 2;
    return value;
  }

  /// A 32-bit number.
  int u32() {
    _need(4);
    final value = _view.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  /// A 64-bit number (low word first).
  int u64() {
    final low = u32();
    return low + (u32() << 32);
  }

  /// [count] raw bytes.
  Uint8List bytes(int count) {
    _need(count);
    final value = Uint8List.sublistView(_bytes, offset, offset + count);
    offset += count;
    return value;
  }

  /// Bytes behind a 16-bit length.
  Uint8List bytes16() => bytes(u16());

  /// Bytes behind a 32-bit length.
  Uint8List bytes32() => bytes(u32());

  /// A Latin-1 string behind a 16-bit length.
  String latin() => latin1.decode(bytes16());

  /// A UTF-8 string behind a 16-bit length.
  String utf8String() => utf8.decode(bytes16(), allowMalformed: true);

  /// A UTF-16LE string behind a 32-bit byte length.
  String ucs2() {
    final raw = bytes32();
    final view = ByteData.sublistView(raw);
    return String.fromCharCodes([for (var i = 0; i + 1 < raw.length; i += 2) view.getUint16(i, Endian.little)]);
  }
}

/// Little-endian writer of YY packets.
final class YyWriter {
  /// A packet for the given uri (with the 10-byte header) or, without one,
  /// a bare payload.
  new([this._uri]) {
    if (_uri != null) {
      u32(0);
      u32(_uri);
      u16(200);
    }
  }

  final int? _uri;
  final BytesBuilder _out = BytesBuilder(copy: false);

  /// Appends one byte.
  void u8(int value) => _out.addByte(value & 0xff);

  /// Appends a 16-bit number.
  void u16(int value) => _out.add((ByteData(2)..setUint16(0, value & 0xffff, Endian.little)).buffer.asUint8List());

  /// Appends a 32-bit number.
  void u32(int value) => _out.add((ByteData(4)..setUint32(0, value & 0xffffffff, Endian.little)).buffer.asUint8List());

  /// Appends a 64-bit number (low word first).
  void u64(int value) {
    u32(value & 0xffffffff);
    u32(value >> 32);
  }

  /// Appends raw bytes.
  void raw(List<int> bytes) => _out.add(bytes);

  /// Appends bytes behind a 16-bit length.
  void bytes16(List<int> bytes) {
    u16(bytes.length);
    raw(bytes);
  }

  /// Appends bytes behind a 32-bit length.
  void bytes32(List<int> bytes) {
    u32(bytes.length);
    raw(bytes);
  }

  /// Appends a Latin-1 string behind a 16-bit length.
  void latin(String text) => bytes16([for (final unit in text.codeUnits) unit & 0xff]);

  /// The bytes; a packet gets its total length written first.
  Uint8List take() {
    final bytes = _out.takeBytes();
    if (_uri != null) ByteData.sublistView(bytes).setUint32(0, bytes.length, Endian.little);
    return bytes;
  }
}

/// What one received YY frame means for the session.
sealed class YyEvent {
  const new();
}

/// The anonymous UDB login answered (§7.3 step 1).
final class YyAnonymousLogin extends YyEvent {
  /// Creates the event.
  const new({required this.ok, this.uid = 0, this.username = '', this.password = '', this.cookie = const []});

  /// Whether the server accepted it.
  final bool ok;

  /// Anonymous uid.
  final int uid;

  /// Anonymous user name for the AP login.
  final String username;

  /// Anonymous password for the AP login.
  final String password;

  /// Session cookie for the AP login.
  final List<int> cookie;
}

/// The AP login answered (§7.3 step 2).
final class YyApLogin extends YyEvent {
  /// Creates the event.
  const new(this.code);

  /// Result code; 200 is success.
  final int code;
}

/// The channel join answered (§7.3 step 3).
final class YyJoin extends YyEvent {
  /// Creates the event.
  const new({required this.status, required this.topSid, required this.subSid, this.error = ''});

  /// Login status; 4 is joined.
  final int status;

  /// Channel joined.
  final int topSid;

  /// Sub-channel joined.
  final int subSid;

  /// Server's error text.
  final String error;
}

/// A chat line (§7.4).
final class YyChat extends YyEvent {
  /// Creates the event.
  const new({
    required this.uid,
    required this.topSid,
    required this.subSid,
    required this.text,
    required this.userName,
    required this.color,
  });

  /// Sender's uid.
  final int uid;

  /// Channel of the message.
  final int topSid;

  /// Sub-channel of the message.
  final int subSid;

  /// Message text.
  final String text;

  /// Sender's name; empty when the packet has none.
  final String userName;

  /// Font colour as sent.
  final int color;
}

/// YY's H5 service protocol (spec/sites/yy.md §7), without I/O.
abstract final class YyProtocol {
  /// Protocol version of the YY web client.
  static const version = '3.2.10';

  /// §7.1 the single-channel endpoint for a connection id [uuid].
  static Uri endpoint(String uuid) => Uri(
    scheme: 'wss',
    host: 'h5-sinchl.yy.com',
    path: '/websocket',
    queryParameters: {'appid': 'yymwebh5', 'version': version, 'uuid': uuid},
  );

  /// §7.1 handshake headers, sent exactly as written.
  static const Map<String, String> headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
    'Origin': 'https://www.yy.com',
  };

  /// §7.1 the service application id.
  static const appId = 259;

  static const _anonymousLogin = 778244;
  static const _anonymousLoginReply = 778500;
  static const _apLogin = 775684;
  static const _apLoginReply = 775940;
  static const _apPing = 794116;
  static const _router = 513035;
  static const _routerReply = 512011;
  static const _joinChannel = 2048258;
  static const _joinChannelReply = 2048514;
  static const _joinGroups = 537944;
  static const _groupMessage = 533080;
  static const _bySidMessage = 28760;
  static const _textChat = 3104600;
  static const _subscribeApps = 538456;

  /// The device string the web client reports.
  static const _mac = 'B8-97-5A-17-AD-4D';

  /// A random connection id in UUID form.
  static String uuid(Random random) {
    final hex = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// §7.3 step 1: anonymous UDB login.
  static Uint8List anonymousLogin() {
    final payload = YyWriter()
      ..latin('')
      ..u32(0)
      ..latin(_mac)
      ..latin(_mac)
      ..u32(0)
      ..latin('yymwebh5');
    return (YyWriter(_anonymousLogin)
          ..latin('')
          ..u32(19822)
          ..bytes32(payload.take()))
        .take();
  }

  /// §7.3 step 2: AP login with the anonymous credentials.
  static Uint8List apLogin(YyAnonymousLogin login, {required String uuid}) {
    final auth = YyWriter()
      ..latin(login.username)
      ..latin(login.password)
      ..u32(2)
      ..u32(0)
      ..u32(0)
      ..latin('yytianlaitv')
      ..latin(_mac)
      ..latin('yymwebn_yymwebh5')
      ..u32(0)
      ..u32(0)
      ..u32(0)
      ..u32(0)
      ..latin(uuid);
    return (YyWriter(_apLogin)
          ..bytes32(auth.take())
          ..u32(appId)
          ..u64(login.uid)
          ..u8(0)
          ..bytes16(const [])
          ..bytes16(login.cookie)
          ..latin('$appId:0')
          ..latin('')
          ..latin('')
          ..latin('')
          ..u8(0)
          ..u32(0)
          ..u32(0)
          ..u32(0xffffffff)
          ..latin('')
          ..u32(1)
          ..latin('BCIFVer')
          ..latin('V2'))
        .take();
  }

  /// §7.3 step 3: join the channel through the router, and subscribe to
  /// the chat applications.
  static List<Uint8List> join({required int uid, required int topSid, required int subSid, required String trace}) {
    final payload = YyWriter()
      ..u32(uid & 0xffffffff)
      ..u32(topSid)
      ..u32(subSid)
      // Two anonymous channel properties; without them the router drops the
      // join silently (legacy yy_protocol.dart:536-540).
      ..u32(2)
      ..u32(2)
      ..latin('0')
      ..u32(3)
      ..latin('1')
      ..u64(uid);
    const apps = [31, 101, 102, 103, 17];
    final subscribe = YyWriter(_subscribeApps)
      ..u64(uid)
      ..u32(apps.length);
    apps.forEach(subscribe.u32);
    return [
      _routed(_joinChannel, 'channelAuther', payload.take(), uid: uid, topSid: topSid, trace: trace),
      subscribe.take(),
    ];
  }

  static Uint8List _routed(
    int realUri,
    String service,
    Uint8List payload, {
    required int uid,
    required int topSid,
    required String trace,
  }) {
    final top = (YyWriter()..u32(topSid)).take();
    final extensions = <(int, List<int>)>[(1, top), (103, latin1.encode(trace))];
    final headers = YyWriter()
      ..u32(0x01000008)
      ..u32(realUri)
      ..u32(0x02000010)
      ..u32(appId)
      ..u64(uid)
      ..u32(0x0400000c)
      ..u32(0)
      ..u32(0)
      ..u32(0x05000008)
      ..u32(0)
      // Section lengths count their 4-byte tag; the fixed fields and two
      // string lengths are 22 bytes.
      ..u32(0x06000000 | (22 + service.length))
      ..u32(0)
      ..u16(0)
      ..u32(0)
      ..latin(service)
      ..u32(0)
      ..latin('');
    var extensionLength = 8;
    for (final (_, value) in extensions) {
      extensionLength += 4 + 2 + value.length;
    }
    headers
      ..u32(0x07000000 | extensionLength)
      ..u32(extensions.length);
    for (final (key, value) in extensions) {
      headers
        ..u32(key)
        ..bytes16(value);
    }
    headers
      ..u32(0x08000006)
      ..latin('')
      ..u32(0xff787878);
    return (YyWriter(_router)
          ..latin('')
          ..u32(realUri)
          ..u16(0)
          ..bytes32(payload)
          ..bytes32(headers.take()))
        .take();
  }

  /// §7.3 step 4: after joining, subscribe to the channel's user groups.
  static List<Uint8List> groups({required int uid, required int topSid, required int subSid}) {
    Uint8List subscribe(List<List<int>> groups) {
      final writer = YyWriter(_joinGroups)
        ..u64(uid)
        ..u32(groups.length);
      for (final group in groups) {
        group.forEach(writer.u32);
      }
      writer.latin('');
      return writer.take();
    }

    return [
      subscribe([
        [1, 0, topSid, 0],
        [2, 0, subSid, 0],
        [1024, appId, subSid, topSid],
        [768, appId, 0, topSid],
        [256, appId, 0, topSid],
        [256, appId, subSid, topSid],
      ]),
      subscribe([
        [1, 0, topSid, 0],
        [2, 0, subSid, 0],
      ]),
    ];
  }

  /// §7.5 heartbeat: an AP ping.
  static Uint8List ping() => (YyWriter(_apPing)..u32(0)).take();

  /// §7.2 every packet of one frame, decoded; unknown packets are skipped
  /// and a malformed one does not lose the rest.
  static List<YyEvent> decode(List<int> frame) {
    final bytes = frame is Uint8List ? frame : Uint8List.fromList(frame);
    final events = <YyEvent>[];
    var offset = 0;
    while (bytes.length - offset >= 10) {
      final length = ByteData.sublistView(bytes, offset).getUint32(0, Endian.little);
      if (length < 10 || offset + length > bytes.length) break;
      try {
        events.addAll(_packet(Uint8List.sublistView(bytes, offset, offset + length)));
      } on FormatException {
        // One malformed packet.
      }
      offset += length;
    }
    return events;
  }

  static List<YyEvent> _packet(Uint8List packet) {
    final reader = YyReader(packet, 4);
    final uri = reader.u32();
    reader.u16();
    switch (uri) {
      case _anonymousLoginReply:
        reader.latin();
        final envelope = reader.u32();
        final realUri = reader.u32();
        final payload = YyReader(reader.bytes32());
        if (realUri != 20078) return const [YyAnonymousLogin(ok: false)];
        payload.latin();
        final result = payload.u32();
        final uid32 = payload.u32();
        payload.u32();
        final username = payload.latin();
        final password = payload.latin();
        final cookie = payload.bytes16();
        payload
          ..bytes16()
          ..latin()
          ..latin();
        final uid = payload.remaining >= 8 ? payload.u64() : uid32;
        final ok = (envelope == 0 || envelope == 200) && (result == 0 || result == 200) && uid != 0;
        return [YyAnonymousLogin(ok: ok, uid: uid, username: username, password: password, cookie: cookie)];
      case _apLoginReply:
        reader.u32();
        return [YyApLogin(reader.u32())];
      case _routerReply:
        reader.latin();
        final realUri = reader.u32();
        final code = reader.u16();
        final payload = YyReader(reader.bytes32());
        if (realUri == _joinChannelReply) {
          if (code != 0 && code != 200) return [YyJoin(status: -code, topSid: 0, subSid: 0)];
          final topSid = payload.u32();
          payload.u32();
          final subSid = payload.u32();
          payload
            ..u32()
            ..u32();
          final status = payload.u8();
          return [YyJoin(status: status, topSid: topSid, subSid: subSid, error: payload.utf8String())];
        }
        if (realUri == _groupMessage && (code == 0 || code == 200)) return _group(payload);
        return const [];
      case _groupMessage:
        return _group(reader);
      case _bySidMessage:
        final app = reader.u16();
        reader.u32();
        return _service(app, reader.bytes16());
      default:
        return const [];
    }
  }

  static List<YyEvent> _group(YyReader reader) {
    reader
      ..u64()
      ..u64();
    final app = reader.u32();
    return _service(app, reader.bytes32());
  }

  static final _xmlText = RegExp(r'<txt\s+data="([^"]*)"');

  static final _xmlEntity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

  /// §7.4 chat text: a `<?xml …><msg>…<txt data="…"/>…</msg>` wrapper gives
  /// its `txt` attribute (XML entities decoded); other text is used as is.
  /// A wrapper without `txt` has no chat text (empty).
  static String plainText(String raw) {
    final text = raw.trim();
    if (!text.startsWith('<?xml') && !text.startsWith('<msg')) return text;
    final data = _xmlText.firstMatch(text)?.group(1);
    if (data == null) return '';
    return data.replaceAllMapped(_xmlEntity, (match) {
      final entity = match.group(1)!;
      return switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ when entity.startsWith('#x') => String.fromCharCode(int.parse(entity.substring(2), radix: 16)),
        _ => String.fromCharCode(int.parse(entity.substring(1))),
      };
    }).trim();
  }

  /// §7.4 application 31 carries text chat (uri 3104600).
  static List<YyEvent> _service(int app, Uint8List message) {
    if (app != 31 || message.length < 10) return const [];
    final reader = YyReader(message, 4);
    if (reader.u32() != _textChat) return const [];
    reader.u16();
    final uid = reader.u32();
    final topSid = reader.u32();
    final subSid = reader.u32();
    final chatLength = reader.u16();
    final chatEnd = reader.offset + chatLength;
    reader
      ..u32()
      ..ucs2();
    final color = reader.u32();
    reader.u32();
    final text = plainText(reader.ucs2());
    reader
      ..offset = chatEnd
      ..latin()
      ..latin();
    final name = reader.remaining > 0 ? reader.utf8String().trim() : '';
    if (text.isEmpty) return const [];
    return [YyChat(uid: uid, topSid: topSid, subSid: subSid, text: text, userName: name, color: color)];
  }
}

/// YY's chat connection (spec/sites/yy.md §7): anonymous login, AP login,
/// channel join, then group subscriptions; exact-case handshake.
final class YyConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys` `sid` and `ssid` are
  /// the channel.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy, Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  /// Per-socket state: reset by every [openFrames].
  var _uuid = '';
  var _uid = 0;
  var _trace = 0;
  var _joined = false;

  int get _topSid => int.tryParse(detail.danmakuKeys['sid'] ?? room.roomId) ?? 0;

  int get _subSid => int.tryParse(detail.danmakuKeys['ssid'] ?? '') ?? _topSid;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    _uuid = YyProtocol.uuid(_random);
    return SocketPlan(endpoints: [YyProtocol.endpoint(_uuid)], headers: YyProtocol.headers, exactHeaders: true);
  }

  @override
  List<List<int>> openFrames() {
    _uid = 0;
    _joined = false;
    return [YyProtocol.anonymousLogin()];
  }

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get authTimeout => const Duration(seconds: 15);

  @override
  Duration get heartbeatInterval => const Duration(seconds: 5);

  @override
  List<int> heartbeat() => YyProtocol.ping();

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    if (data is! List<int>) return FrameResult.empty;
    final replies = <List<int>>[];
    final events = <DanmakuEvent>[];
    var joinedNow = false;
    var rejected = false;
    for (final event in YyProtocol.decode(data)) {
      switch (event) {
        case YyAnonymousLogin(ok: false):
          rejected = true;
        case final YyAnonymousLogin login:
          _uid = login.uid;
          replies.add(YyProtocol.apLogin(login, uuid: _uuid));
        case YyApLogin(:final code):
          if (code != 200) {
            rejected = true;
          } else {
            replies.addAll(
              YyProtocol.join(uid: _uid, topSid: _topSid, subSid: _subSid, trace: 'F${_uid}_yymwebh5_${_trace++}'),
            );
          }
        case YyJoin(:final status, :final topSid, :final subSid):
          if (status != 4 || topSid != _topSid || subSid != _subSid) {
            rejected = true;
          } else if (!_joined) {
            _joined = joinedNow = true;
            replies.addAll(YyProtocol.groups(uid: _uid, topSid: _topSid, subSid: _subSid));
          }
        case final YyChat chat:
          // CONN-5: another channel's line is not this room's.
          if (!_joined || chat.topSid != _topSid || chat.subSid != _subSid) continue;
          events.add(
            DanmakuChat(
              room: context.room,
              session: context.session,
              receivedAt: context.receivedAt,
              userId: chat.uid == 0 ? '' : '${chat.uid}',
              userName: chat.userName,
              text: chat.text,
            ),
          );
      }
    }
    return FrameResult(events: events, replies: replies, joined: joinedNow, rejected: rejected);
  }
}
