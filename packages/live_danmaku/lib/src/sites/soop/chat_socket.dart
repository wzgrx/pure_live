import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_net/live_net.dart';

/// [SocketConnector] for SOOP's chat edges (3.x
/// `connectCaseSensitiveWebSocket`, docs/modules/M5.7-soop.md): the opening
/// handshake is written by hand, so the caller's header names and the RFC
/// 6455 upgrade fields keep their spelling. The chat edges answer that
/// handshake and leave `dart:io`'s lower-cased one pending until the
/// connect timeout.
///
/// Private to SOOP until the shared case-sensitive connector of M5.6 (YY)
/// replaces it. [route] is ignored: 3.x opened this socket directly whatever
/// the proxy setting, and so does this one.
Future<SocketChannel> connectSoopChatSocket(
  Uri endpoint, {
  required Map<String, String> headers,
  required Iterable<String>? protocols,
  required ProxyRoute route,
  required Duration connectTimeout,
}) => SoopChatSocket.connect(endpoint, headers: headers, protocols: protocols, connectTimeout: connectTimeout);

/// A WebSocket client (RFC 6455) whose opening handshake is sent exactly as
/// [handshake] writes it (3.x `YyWebSocketChannel`): `ws` over TCP, `wss`
/// over TLS offering only `http/1.1`. Text frames arrive as `String`,
/// binary frames as `List<int>`; pings are answered, fragments joined.
final class SoopChatSocket implements SocketChannel {
  new _(this._socket, this._nonce, this._protocols, this._random) {
    _subscription = _socket.listen(_receive, onError: _fail, onDone: _remoteDone, cancelOnError: true);
    _socket.done.ignore();
  }

  /// Largest response head accepted (3.x: 32 KiB).
  static const int maxHandshakeBytes = 32 * 1024;

  /// Largest message accepted, fragments joined (3.x: 16 MiB).
  static const int maxMessageBytes = 16 * 1024 * 1024;

  /// How long [close] waits for the peer's close frame (3.x: 1 s).
  static const Duration closeWait = Duration(seconds: 1);

  static const String _acceptGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// Header names the handshake writes itself; the caller's are dropped.
  static const Set<String> _controlled = {
    'host',
    'connection',
    'upgrade',
    'cache-control',
    'sec-websocket-key',
    'sec-websocket-version',
    'sec-websocket-protocol',
  };

  /// Opens [endpoint] (`ws` or `wss`) with [headers] as spelled and offers
  /// [protocols]. The whole handshake (TCP, TLS, upgrade) must finish within
  /// [connectTimeout]; the socket is destroyed when it does not.
  static Future<SoopChatSocket> connect(
    Uri endpoint, {
    Map<String, String> headers = const {},
    Iterable<String>? protocols,
    Duration connectTimeout = const Duration(seconds: 10),
  }) async {
    if (endpoint.scheme != 'ws' && endpoint.scheme != 'wss') {
      throw ArgumentError.value(endpoint, 'endpoint', 'Not a ws or wss URL');
    }
    final generator = Random.secure();
    final offered = List<String>.unmodifiable(protocols ?? const <String>[]);
    final nonce = base64Encode([for (var index = 0; index < 16; index++) generator.nextInt(256)]);
    final request = utf8.encode(handshake(endpoint, nonce: nonce, headers: headers, protocols: offered));
    final secure = endpoint.scheme == 'wss';
    final port = endpoint.hasPort ? endpoint.port : (secure ? 443 : 80);
    var abandoned = false;
    SoopChatSocket? channel;
    Future<SoopChatSocket> open() async {
      final socket = secure
          ? await SecureSocket.connect(
              endpoint.host,
              port,
              supportedProtocols: const ['http/1.1'],
              timeout: connectTimeout,
            )
          : await Socket.connect(endpoint.host, port, timeout: connectTimeout);
      if (abandoned) {
        socket.destroy();
        throw const WebSocketException('Handshake abandoned');
      }
      final opened = channel = SoopChatSocket._(socket, nonce, offered, generator);
      socket.add(request);
      await opened._upgraded.future;
      return opened;
    }

    try {
      return await open().timeout(connectTimeout);
    } on Object {
      abandoned = true;
      channel?._finish();
      rethrow;
    }
  }

  /// The opening handshake for [endpoint] (3.x `buildYyWebSocketHandshake`):
  /// the request line and `Host`, the caller's [headers] in order and as
  /// spelled (those the handshake controls left out), then `Connection`,
  /// `Upgrade`, `Cache-Control`, the key, the version and the offered
  /// [protocols]. A header holding a line break is refused.
  static String handshake(
    Uri endpoint, {
    required String nonce,
    Map<String, String> headers = const {},
    List<String> protocols = const [],
  }) {
    final secure = endpoint.scheme == 'wss';
    final port = endpoint.hasPort ? endpoint.port : (secure ? 443 : 80);
    final host = port == (secure ? 443 : 80) ? endpoint.host : '${endpoint.host}:$port';
    final path = endpoint.hasQuery ? '${endpoint.path}?${endpoint.query}' : endpoint.path;
    return [
      'GET ${path.isEmpty ? '/' : path} HTTP/1.1',
      'Host: $host',
      for (final MapEntry(:key, :value) in headers.entries)
        if (!_controlled.contains(key.toLowerCase())) _headerLine(key, value),
      'Connection: Upgrade',
      'Upgrade: websocket',
      'Cache-Control: no-cache',
      'Sec-WebSocket-Key: $nonce',
      'Sec-WebSocket-Version: 13',
      if (protocols.isNotEmpty) 'Sec-WebSocket-Protocol: ${protocols.join(', ')}',
      '',
      '',
    ].join('\r\n');
  }

  static String _headerLine(String name, String value) {
    if ('$name$value'.contains(RegExp('[\r\n]'))) {
      throw ArgumentError.value(name, 'headers', 'Holds a line break');
    }
    return '$name: $value';
  }

  /// The `Sec-WebSocket-Accept` a server owes [nonce].
  static String acceptKey(String nonce) => base64Encode(sha1.convert(ascii.encode('$nonce$_acceptGuid')).bytes);

  /// Checks the response [head] to a handshake with [nonce] (3.x
  /// `validateYyWebSocketHandshake`): status 101, `Connection` holding
  /// `upgrade`, `Upgrade: websocket` (case ignored), the right accept key,
  /// and no subprotocol that was not offered. Returns the selected
  /// subprotocol; throws [WebSocketException] otherwise, also when a checked
  /// field is repeated.
  static String? verify(String head, {required String nonce, List<String> protocols = const []}) {
    final lines = head.split('\r\n');
    if (!RegExp(r'^HTTP/1\.[01] 101(?:\s|$)').hasMatch(lines.first)) {
      throw WebSocketException('Not upgraded: ${lines.first}');
    }
    final fields = <String, List<String>>{};
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      fields
          .putIfAbsent(line.substring(0, separator).trim().toLowerCase(), () => [])
          .add(line.substring(separator + 1).trim());
    }
    String? single(String name) {
      final values = fields[name];
      if (values == null || values.isEmpty) return null;
      if (values.length != 1) throw WebSocketException('Repeated $name');
      return values.single;
    }

    final connection = {
      for (final value in fields['connection'] ?? const <String>[])
        for (final token in value.split(',')) token.trim().toLowerCase(),
    };
    if (!connection.contains('upgrade') || single('upgrade')?.toLowerCase() != 'websocket') {
      throw const WebSocketException('Missing upgrade headers');
    }
    if (single('sec-websocket-accept') != acceptKey(nonce)) {
      throw const WebSocketException('Wrong Sec-WebSocket-Accept');
    }
    final selected = single('sec-websocket-protocol');
    if (selected != null && !protocols.contains(selected)) {
      throw WebSocketException('Unrequested subprotocol $selected');
    }
    return selected;
  }

  final Socket _socket;
  final String _nonce;
  final List<String> _protocols;
  final Random _random;
  late final StreamSubscription<Uint8List> _subscription;
  final Completer<void> _upgraded = Completer();
  final Completer<void> _finished = Completer();
  final StreamController<Object?> _incoming = StreamController();
  Uint8List _buffer = Uint8List(0);
  BytesBuilder? _fragments;
  int _fragmentOpcode = 0;
  bool _open = false;
  bool _done = false;
  bool _closeSent = false;
  Timer? _closeTimer;

  /// The subprotocol the server selected, once open.
  String? get protocol => _protocol;
  String? _protocol;

  @override
  int? get closeCode => _closeCode;
  int? _closeCode;

  @override
  String? get closeReason => _closeReason;
  String? _closeReason;

  @override
  Stream<Object?> get stream => _incoming.stream;

  /// Sends a text (`String`) or binary (`List<int>`) message; throws
  /// [StateError] once the socket is closed.
  @override
  void add(Object data) {
    if (!_open || _done) throw StateError('SOOP chat socket is not open');
    switch (data) {
      case final String text:
        _sendFrame(1, utf8.encode(text));
      case final List<int> bytes:
        _sendFrame(2, bytes);
      default:
        throw ArgumentError.value(data, 'data', 'Neither String nor List<int>');
    }
  }

  /// Sends a close frame ([code] and [reason] when given) and waits at most
  /// [closeWait] for the peer's before dropping the connection.
  @override
  Future<void> close([int? code, String? reason]) {
    if (_done) return _finished.future;
    if (!_open) {
      _fail(const WebSocketException('Closed before the handshake completed'));
      return _finished.future;
    }
    _sendClose(code, reason);
    _closeTimer ??= Timer(closeWait, _finish);
    return _finished.future;
  }

  void _receive(Uint8List data) {
    if (_done || data.isEmpty) return;
    _buffer = _buffer.isEmpty
        ? data
        : (BytesBuilder(copy: false)
                ..add(_buffer)
                ..add(data))
              .takeBytes();
    if (!_open) {
      final end = _headEnd(_buffer);
      if (end < 0) {
        if (_buffer.length > maxHandshakeBytes) _fail(const WebSocketException('Response head too large'));
        return;
      }
      try {
        _protocol = verify(latin1.decode(Uint8List.sublistView(_buffer, 0, end)), nonce: _nonce, protocols: _protocols);
      } on WebSocketException catch (error) {
        _fail(error);
        return;
      }
      _buffer = Uint8List.sublistView(_buffer, end + 4);
      _open = true;
      _upgraded.complete();
    }
    _consumeFrames();
  }

  static int _headEnd(Uint8List bytes) {
    for (var index = 0; index + 3 < bytes.length; index++) {
      if (bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }

  void _consumeFrames() {
    while (!_done && _buffer.length >= 2) {
      final first = _buffer[0];
      final second = _buffer[1];
      final fin = first & 0x80 != 0;
      final opcode = first & 0x0f;
      if (first & 0x70 != 0) return _protocolError('Unsupported RSV bits');
      var offset = 2;
      var length = second & 0x7f;
      if (length == 126) {
        if (_buffer.length < 4) return;
        length = (_buffer[2] << 8) | _buffer[3];
        offset = 4;
      } else if (length == 127) {
        if (_buffer.length < 10) return;
        length = 0;
        for (var index = 2; index < 10; index++) {
          length = length * 256 + _buffer[index];
          if (length > maxMessageBytes) return _protocolError('Frame exceeds $maxMessageBytes bytes');
        }
        offset = 10;
      }
      final masked = second & 0x80 != 0;
      final maskOffset = offset;
      if (masked) offset += 4;
      if (length > maxMessageBytes) return _protocolError('Frame exceeds $maxMessageBytes bytes');
      if (_buffer.length < offset + length) return;
      final payload = Uint8List.fromList(Uint8List.sublistView(_buffer, offset, offset + length));
      if (masked) {
        for (var index = 0; index < payload.length; index++) {
          payload[index] ^= _buffer[maskOffset + (index & 3)];
        }
      }
      _buffer = Uint8List.sublistView(_buffer, offset + length);
      if (opcode >= 8 && (!fin || length > 125)) return _protocolError('Invalid control frame');
      switch (opcode) {
        case 0:
          final fragments = _fragments;
          if (fragments == null) return _protocolError('Unexpected continuation frame');
          fragments.add(payload);
          if (fragments.length > maxMessageBytes) return _protocolError('Fragmented message too large');
          if (fin) {
            _fragments = null;
            _deliver(_fragmentOpcode, fragments.takeBytes());
          }
        case 1 || 2:
          if (_fragments != null) return _protocolError('New message before the previous one ended');
          if (fin) {
            _deliver(opcode, payload);
          } else {
            _fragmentOpcode = opcode;
            _fragments = BytesBuilder(copy: false)..add(payload);
          }
        case 8:
          return _peerClosed(payload);
        case 9:
          _sendFrame(10, payload);
        case 10:
          break;
        default:
          return _protocolError('Unknown opcode $opcode');
      }
    }
  }

  void _deliver(int opcode, Uint8List payload) {
    if (opcode == 2) {
      _incoming.add(payload);
      return;
    }
    try {
      _incoming.add(utf8.decode(payload));
    } on FormatException catch (error) {
      _sendClose(1007, 'Invalid UTF-8');
      _fail(error);
    }
  }

  void _peerClosed(Uint8List payload) {
    if (payload.length == 1) return _protocolError('One-byte close payload');
    if (payload.length >= 2) {
      _closeCode = (payload[0] << 8) | payload[1];
      try {
        _closeReason = utf8.decode(Uint8List.sublistView(payload, 2));
      } on FormatException {
        _closeReason = '';
      }
    }
    if (!_closeSent) {
      _closeSent = true;
      _sendFrame(8, payload);
    }
    _finish();
  }

  void _protocolError(String message) {
    _sendClose(1002, message);
    _fail(WebSocketException(message));
  }

  void _sendClose(int? code, [String? reason]) {
    if (_closeSent || _done) return;
    _closeSent = true;
    _sendFrame(8, [
      if (code != null) ...[(code >> 8) & 0xff, code & 0xff],
      if (code != null && reason != null) ...utf8.encode(reason),
    ]);
  }

  /// One masked client frame (RFC 6455 §5.2).
  void _sendFrame(int opcode, List<int> payload) {
    if (_done) return;
    final length = payload.length;
    final mask = [for (var index = 0; index < 4; index++) _random.nextInt(256)];
    final frame = BytesBuilder(copy: false)..addByte(0x80 | opcode);
    if (length <= 125) {
      frame.addByte(0x80 | length);
    } else if (length <= 0xffff) {
      frame.add([0x80 | 126, (length >> 8) & 0xff, length & 0xff]);
    } else {
      frame.addByte(0x80 | 127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        frame.addByte((length >> shift) & 0xff);
      }
    }
    frame.add(mask);
    final masked = Uint8List(length);
    for (var index = 0; index < length; index++) {
      masked[index] = payload[index] ^ mask[index & 3];
    }
    frame.add(masked);
    _socket.add(frame.takeBytes());
  }

  void _remoteDone() {
    if (_open) {
      _finish();
    } else {
      _fail(const WebSocketException('Connection closed during the handshake'));
    }
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_done) return;
    if (!_upgraded.isCompleted) {
      _upgraded.completeError(error, stackTrace);
    } else if (!_incoming.isClosed) {
      _incoming.addError(error, stackTrace);
    }
    _finish();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _closeTimer?.cancel();
    unawaited(_subscription.cancel());
    _socket.destroy();
    if (!_upgraded.isCompleted) _upgraded.completeError(const WebSocketException('Connection closed'));
    if (!_incoming.isClosed) unawaited(_incoming.close());
    if (!_finished.isCompleted) _finished.complete();
  }
}
