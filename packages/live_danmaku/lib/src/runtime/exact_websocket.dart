import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:live_net/live_net.dart';

/// A WebSocket client (RFC 6455) that sends its opening handshake exactly as
/// written: `Connection: Upgrade`, `Upgrade: websocket` and the caller's
/// headers keep their case and order.
///
/// `dart:io` lower-cases the upgrade headers, and the chat edges of YY and
/// SOOP leave such a handshake pending forever (spec/sites/yy.md §7,
/// spec/sites/soop.md §7). This client goes through the platform's proxy
/// route with `CONNECT` like `HttpClient` does, speaks TLS for `wss`, and
/// delivers text frames as `String` and binary frames as `List<int>`.
final class ExactWebSocket implements DanmakuSocket {
  new _(this._channel, this.protocol) {
    _channel.onBytes = _receive;
    _channel.onDone = _remoteDone;
  }

  /// Opens [url] within [timeout] through [route].
  static Future<ExactWebSocket> connect(
    Uri url, {
    ProxyRoute route = const DirectRoute(),
    Map<String, String> headers = const {},
    List<String> protocols = const [],
    Duration timeout = const Duration(seconds: 10),
    Random? random,
  }) async {
    if (url.scheme != 'ws' && url.scheme != 'wss') throw ArgumentError.value(url, 'url', 'not a ws or wss URL');
    final secure = url.scheme == 'wss';
    final port = url.hasPort ? url.port : (secure ? 443 : 80);
    final nonce = base64.encode(List<int>.generate(16, (_) => (random ?? Random.secure()).nextInt(256)));
    _RawChannel? channel;
    try {
      return await () async {
        final proxy = route is HttpProxyRoute ? route : null;
        channel = await _RawChannel.open(proxy?.host ?? url.host, proxy?.port ?? port, timeout);
        if (proxy != null) {
          channel!.write(ascii.encode('CONNECT ${url.host}:$port HTTP/1.1\r\nHost: ${url.host}:$port\r\n\r\n'));
          final reply = await channel!.readHead();
          if (!RegExp(r'^HTTP/1\.[01] 200').hasMatch(reply.head)) {
            throw WebSocketException('Proxy refused CONNECT: ${reply.head.split('\r\n').first}');
          }
        }
        if (secure) await channel!.secure(url.host);
        channel!.write(utf8.encode(handshake(url, nonce: nonce, headers: headers, protocols: protocols)));
        final reply = await channel!.readHead();
        final selected = verifyHandshake(reply.head, nonce: nonce, protocols: protocols);
        final socket = ExactWebSocket._(channel!, selected);
        if (reply.rest.isNotEmpty) socket._receive(reply.rest);
        return socket;
      }().timeout(timeout);
    } on Object {
      channel?.destroy();
      rethrow;
    }
  }

  /// The opening handshake request for [url] (RFC 6455 §4.1): the caller's
  /// [headers] in order and as spelled, then the upgrade headers.
  static String handshake(
    Uri url, {
    required String nonce,
    Map<String, String> headers = const {},
    List<String> protocols = const [],
  }) {
    final secure = url.scheme == 'wss';
    final port = url.hasPort ? url.port : (secure ? 443 : 80);
    final host = port == (secure ? 443 : 80) ? url.host : '${url.host}:$port';
    final target = '${url.path.isEmpty ? '/' : url.path}${url.hasQuery ? '?${url.query}' : ''}';
    const controlled = {
      'host',
      'connection',
      'upgrade',
      'sec-websocket-key',
      'sec-websocket-version',
      'sec-websocket-protocol',
      'sec-websocket-extensions',
    };
    return [
      'GET $target HTTP/1.1',
      'Host: $host',
      for (final MapEntry(:key, :value) in headers.entries)
        if (!controlled.contains(key.toLowerCase())) '$key: $value',
      'Connection: Upgrade',
      'Upgrade: websocket',
      'Sec-WebSocket-Key: $nonce',
      'Sec-WebSocket-Version: 13',
      if (protocols.isNotEmpty) 'Sec-WebSocket-Protocol: ${protocols.join(', ')}',
      '',
      '',
    ].join('\r\n');
  }

  /// Checks the server's answer to [handshake]; returns the selected
  /// subprotocol. Throws [WebSocketException] when it is not an upgrade.
  static String? verifyHandshake(String head, {required String nonce, List<String> protocols = const []}) {
    final lines = head.split('\r\n');
    if (!RegExp(r'^HTTP/1\.[01] 101').hasMatch(lines.first)) {
      throw WebSocketException('Not upgraded: ${lines.first}');
    }
    final fields = <String, String>{};
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      fields[line.substring(0, separator).trim().toLowerCase()] = line.substring(separator + 1).trim();
    }
    if (fields['upgrade']?.toLowerCase() != 'websocket') throw const WebSocketException('Missing Upgrade: websocket');
    final expected = base64.encode(sha1.convert(ascii.encode('${nonce}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')).bytes);
    if (fields['sec-websocket-accept'] != expected) throw const WebSocketException('Bad Sec-WebSocket-Accept');
    final selected = fields['sec-websocket-protocol'];
    if (selected != null && !protocols.contains(selected)) {
      throw WebSocketException('Unrequested subprotocol $selected');
    }
    return selected;
  }

  final _RawChannel _channel;
  final StreamController<Object?> _messages = StreamController<Object?>();
  final Random _mask = Random.secure();
  Uint8List _buffer = Uint8List(0);
  BytesBuilder? _fragments;
  int _fragmentOpcode = 0;
  var _closeSent = false;
  var _done = false;
  int? _closeCode;
  Timer? _closeTimer;

  /// The subprotocol the server selected, if any.
  final String? protocol;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void send(List<int> frame) => _sendFrame(2, frame);

  @override
  void sendText(String text) => _sendFrame(1, utf8.encode(text));

  @override
  Future<void> close() async {
    if (_done) return;
    _sendClose(1000);
    _closeTimer ??= Timer(const Duration(seconds: 1), _finish);
    await _messages.done.timeout(const Duration(seconds: 2), onTimeout: () {});
    _finish();
  }

  void _sendFrame(int opcode, List<int> payload) {
    if (_done || _closeSent) return;
    final header = BytesBuilder(copy: false)..addByte(0x80 | opcode);
    final length = payload.length;
    if (length < 126) {
      header.addByte(0x80 | length);
    } else if (length < 65536) {
      header.add([0x80 | 126, length >> 8, length & 0xff]);
    } else {
      header.addByte(0x80 | 127);
      for (var shift = 56; shift >= 0; shift -= 8) {
        header.addByte((length >> shift) & 0xff);
      }
    }
    final mask = [for (var i = 0; i < 4; i++) _mask.nextInt(256)];
    header.add(mask);
    final masked = Uint8List(length);
    for (var i = 0; i < length; i++) {
      masked[i] = payload[i] ^ mask[i & 3];
    }
    _channel
      ..write(header.takeBytes())
      ..write(masked);
  }

  void _sendClose(int code) {
    if (_closeSent || _done) return;
    _sendFrame(8, [code >> 8, code & 0xff]);
    _closeSent = true;
  }

  void _receive(List<int> bytes) {
    if (_done) return;
    _buffer = _buffer.isEmpty
        ? Uint8List.fromList(bytes)
        : (BytesBuilder(copy: false)
                ..add(_buffer)
                ..add(bytes))
              .toBytes();
    while (!_done) {
      final frame = _nextFrame();
      if (frame == null) return;
      _handle(frame.fin, frame.opcode, frame.payload);
    }
  }

  ({bool fin, int opcode, Uint8List payload})? _nextFrame() {
    if (_buffer.length < 2) return null;
    final fin = _buffer[0] & 0x80 != 0;
    final opcode = _buffer[0] & 0x0f;
    final masked = _buffer[1] & 0x80 != 0;
    var length = _buffer[1] & 0x7f;
    var offset = 2;
    if (length == 126) {
      if (_buffer.length < 4) return null;
      length = (_buffer[2] << 8) | _buffer[3];
      offset = 4;
    } else if (length == 127) {
      if (_buffer.length < 10) return null;
      length = 0;
      for (var i = 2; i < 10; i++) {
        length = (length << 8) | _buffer[i];
      }
      offset = 10;
    }
    final maskOffset = offset;
    if (masked) offset += 4;
    if (_buffer.length < offset + length) return null;
    final payload = Uint8List.fromList(Uint8List.sublistView(_buffer, offset, offset + length));
    if (masked) {
      for (var i = 0; i < payload.length; i++) {
        payload[i] ^= _buffer[maskOffset + (i & 3)];
      }
    }
    _buffer = Uint8List.sublistView(_buffer, offset + length);
    return (fin: fin, opcode: opcode, payload: payload);
  }

  void _handle(bool fin, int opcode, Uint8List payload) {
    switch (opcode) {
      case 0:
        final fragments = _fragments;
        if (fragments == null) return _fail('Unexpected continuation frame');
        fragments.add(payload);
        if (fin) {
          _fragments = null;
          _deliver(_fragmentOpcode, fragments.takeBytes());
        }
      case 1 || 2:
        if (fin) {
          _deliver(opcode, payload);
        } else {
          _fragmentOpcode = opcode;
          _fragments = BytesBuilder(copy: false)..add(payload);
        }
      case 8:
        _closeCode = payload.length >= 2 ? (payload[0] << 8) | payload[1] : 1005;
        _sendClose(_closeCode == 1005 ? 1000 : _closeCode!);
        _finish();
      case 9:
        _sendFrame(10, payload);
      case 10:
        break;
      default:
        _fail('Unknown opcode $opcode');
    }
  }

  void _deliver(int opcode, Uint8List payload) {
    if (_messages.isClosed) return;
    if (opcode == 1) {
      _messages.add(utf8.decode(payload, allowMalformed: true));
    } else {
      _messages.add(payload);
    }
  }

  void _fail(String reason) {
    if (!_messages.isClosed) _messages.addError(WebSocketException(reason));
    _sendClose(1002);
    _finish();
  }

  void _remoteDone() => _finish();

  void _finish() {
    if (_done) return;
    _done = true;
    _closeTimer?.cancel();
    _channel.destroy();
    if (!_messages.isClosed) unawaited(_messages.close());
  }
}

/// A raw TCP (or TLS) connection with a write queue and a byte callback.
final class _RawChannel {
  new _(this._socket) {
    _subscription = _socket.listen(_event, onError: (Object _) => _closed(), onDone: _closed);
  }

  static Future<_RawChannel> open(String host, int port, Duration timeout) async =>
      _RawChannel._(await RawSocket.connect(host, port, timeout: timeout));

  RawSocket _socket;
  late StreamSubscription<RawSocketEvent> _subscription;
  final List<Uint8List> _pending = [];
  var _pendingOffset = 0;
  var _destroyed = false;

  /// Receives bytes once the handshake is over.
  void Function(List<int>)? onBytes;

  /// Called when the peer closes or the connection fails.
  void Function()? onDone;

  final BytesBuilder _head = BytesBuilder(copy: false);
  Completer<({String head, List<int> rest})>? _headWaiter;

  /// Upgrades the connection to TLS for [host] (after a proxy CONNECT).
  Future<void> secure(String host) async {
    // RawSecureSocket takes the (unpaused) subscription over.
    final secured = await RawSecureSocket.secure(
      _socket,
      subscription: _subscription,
      host: host,
      supportedProtocols: const ['http/1.1'],
    );
    _socket = secured;
    _subscription = secured.listen(_event, onError: (Object _) => _closed(), onDone: _closed);
  }

  /// Reads an HTTP response head (up to `\r\n\r\n`) and what followed it.
  Future<({String head, List<int> rest})> readHead() {
    final waiter = Completer<({String head, List<int> rest})>();
    _headWaiter = waiter;
    _takeHead();
    return waiter.future;
  }

  void _takeHead() {
    final waiter = _headWaiter;
    if (waiter == null) return;
    final bytes = _head.toBytes();
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        _headWaiter = null;
        _head.clear();
        waiter.complete((head: latin1.decode(bytes.sublist(0, i)), rest: bytes.sublist(i + 4)));
        return;
      }
    }
    if (bytes.length > 32 * 1024) {
      _headWaiter = null;
      waiter.completeError(const WebSocketException('Response head too large'));
    }
  }

  void _event(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        final data = _socket.read();
        if (data == null || data.isEmpty) return;
        if (_headWaiter != null || onBytes == null) {
          _head.add(data);
          _takeHead();
        } else {
          onBytes!(data);
        }
      case RawSocketEvent.write:
        _flush();
      case RawSocketEvent.readClosed:
        _closed();
      case RawSocketEvent.closed:
        _closed();
    }
  }

  void write(List<int> bytes) {
    if (_destroyed || bytes.isEmpty) return;
    _pending.add(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    _flush();
  }

  void _flush() {
    while (_pending.isNotEmpty && !_destroyed) {
      final chunk = _pending.first;
      final written = _socket.write(chunk, _pendingOffset);
      _pendingOffset += written;
      if (_pendingOffset < chunk.length) {
        _socket.writeEventsEnabled = true;
        return;
      }
      _pending.removeAt(0);
      _pendingOffset = 0;
    }
  }

  void _closed() {
    final waiter = _headWaiter;
    if (waiter != null && !waiter.isCompleted) {
      _headWaiter = null;
      waiter.completeError(const WebSocketException('Connection closed during the handshake'));
    }
    destroy();
    onDone?.call();
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    unawaited(_subscription.cancel());
    _socket.close().ignore();
  }
}
