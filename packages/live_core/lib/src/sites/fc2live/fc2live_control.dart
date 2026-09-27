import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/fc2live/fc2live_parse.dart';
import 'package:live_core/src/text_socket.dart';

const _site = 'fc2live';

/// One FC2 control socket (spec/sites/fc2live.md §6.2): the WebSocket whose
/// session authorises the channel's HLS playlists. The media server refuses
/// a playlist whose control socket closed before its first request, so the
/// socket stays open while anything plays the grant.
final class Fc2Control {
  new _(this._socket);

  /// Opens the control socket of [grant] and waits (up to [timeout]) for
  /// the `get_hls_information` answer.
  static Future<Fc2Control> open(
    Fc2Grant grant, {
    required TextSocketConnect connect,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final TextSocket raw;
    try {
      raw = await connect(Fc2LiveParse.controlUrl(grant), {
        'Origin': 'https://live.fc2.com',
        'Cookie': 'l_ortkn=${grant.orz}',
      });
    } on SiteError {
      rethrow;
    } on Object catch (error) {
      throw NetworkFailure(_site, 'control: $error');
    }
    final control = Fc2Control._(raw).._listen();
    try {
      await control._ready.future.timeout(timeout);
      return control;
    } on TimeoutException {
      await control.close();
      throw const NetworkFailure(_site, 'control: no HLS information within the timeout');
    } on Object {
      await control.close();
      rethrow;
    }
  }

  final TextSocket _socket;
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _done = Completer<void>();
  StreamSubscription<String>? _subscription;
  late Map<int, Uri> _playlists;
  var _requested = false;
  var _closed = false;

  /// Playlist URL by mode (§6.2).
  Map<int, Uri> get playlists => _playlists;

  /// Viewers (PC + mobile) from the last `user_count` messages.
  int? get viewers => _pc == null && _mobile == null ? null : (_pc ?? 0) + (_mobile ?? 0);
  int? _pc;
  int? _mobile;

  /// Why the socket ended.
  String? endReason;

  /// Whether the socket is still open.
  bool get isOpen => !_closed;

  /// Completes when the socket has ended.
  Future<void> get done => _done.future;

  void _listen() {
    _subscription = _socket.messages.listen(
      _receive,
      onError: (Object error) => _end('error: $error'),
      onDone: () => _end(endReason ?? 'closed'),
      cancelOnError: true,
    );
  }

  void _receive(String text) {
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (message is! Map) return;
    final arguments = message['arguments'];
    switch (message['name']) {
      case 'connect_complete':
        if (!_requested) {
          _requested = true;
          _socket.send('{"name":"get_hls_information","arguments":{},"id":1}');
        }
      case '_response_' when message['id'] == 1 && arguments is Map<String, dynamic>:
        try {
          _playlists = Fc2LiveParse.playlists(arguments);
          if (!_ready.isCompleted) _ready.complete();
        } on SiteError catch (error) {
          if (!_ready.isCompleted) _ready.completeError(error);
          unawaited(close());
        }
      case 'user_count' when arguments is Map:
        if (arguments['pc_user_count'] case final int pc) _pc = pc;
        if (arguments['mobile_user_count'] case final int mobile) _mobile = mobile;
      case 'control_disconnection':
        endReason = 'control_disconnection ${arguments is Map ? arguments['code'] ?? '' : ''}'.trim();
        if (!_ready.isCompleted) _ready.completeError(StreamUnavailable(_site, 'control: $endReason'));
        unawaited(close());
    }
  }

  void _end(String reason) {
    endReason ??= reason;
    if (!_ready.isCompleted) _ready.completeError(NetworkFailure(_site, 'control: $reason'));
    unawaited(close());
  }

  /// Closes the socket (idempotent).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    endReason ??= 'closed';
    unawaited(_subscription?.cancel());
    try {
      await _socket.close();
    } on Object {
      // Already gone.
    }
    if (!_done.isCompleted) _done.complete();
  }
}
