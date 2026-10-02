import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// SHOWROOM's comment broadcast (the archived v4's spec/sites/showroom.md
/// §7, checked against the recording `fixtures/showroom/danmaku/S06-live`
/// and the web client; docs/T06/T06a/T06a.16/record.md), without I/O.
///
/// - One WebSocket of text frames on the broadcast server `bcsvr_host`
///   (`wss://<host>/`, port 443). The client subscribes to a broadcast with
///   `SUB\t<bcsvr_key>`; nothing confirms it.
/// - The server pushes `MSG\t<key>\t<JSON object>`; the object's `t` is the
///   kind (1 comment, 2 gift, 5 support points, 8 caption, 18 system log,
///   101 broadcast ended, 104 broadcast started, …).
/// - `PING\tshowroom` is answered `ACK\tshowroom`.
abstract final class ShowroomDanmakuProtocol {
  /// Ping period (the archived v4, spec §7.2).
  static const Duration heartbeatInterval = Duration(seconds: 60);

  /// The client ping; the server answers [ack].
  static const String ping = 'PING\tshowroom';

  /// The server's answer to [ping].
  static const String ack = 'ACK\tshowroom';

  /// `t` of a comment.
  static const int commentType = 1;

  /// Handshake headers: the site's origin and the adapter's desktop UA
  /// (`ShowroomApi.userAgent`), as the archived v4 sent them.
  static const Map<String, String> socketHeaders = {'origin': ShowroomApi.origin, 'user-agent': ShowroomApi.userAgent};

  /// Largest [DateTime], in seconds.
  static const int _maxEpochSeconds = 8640000000000;

  /// The socket of broadcast server [host].
  static Uri endpoint(String host) => Uri(scheme: 'wss', host: host, path: '/');

  /// The subscription to broadcast [key].
  static String subscribe(String key) => 'SUB\t$key';

  /// [args] if they can be subscribed to: the host and key checks of
  /// `ShowroomApi.danmakuArgs` (a host on `showroom-live.com`, a key of at
  /// most 256 characters without white space or control characters; the
  /// host lower-cased), else null.
  static ShowroomDanmakuArgs? checked(ShowroomDanmakuArgs args) {
    final valid = ShowroomApi.danmakuArgs(roomId: 0, host: args.host, key: args.key);
    return valid == null ? null : ShowroomDanmakuArgs(roomId: args.roomId, host: valid.host, key: valid.key);
  }

  /// The chat of one frame (text, or UTF-8 bytes) of broadcast [key]: a
  /// `MSG` of that key whose object is a comment ([comment]). Frames of
  /// another key, `ACK`, JSON that is not an object and every other kind
  /// give nothing.
  static List<LiveMessage> decode(Object? data, {required String key}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null || !text.startsWith('MSG\t')) return const [];
    final keyEnd = text.indexOf('\t', 4);
    if (keyEnd < 0 || text.substring(4, keyEnd) != key) return const [];
    final Object? event;
    try {
      event = jsonDecode(text.substring(keyEnd + 1));
    } on FormatException {
      return const [];
    }
    return [?comment(event)];
  }

  /// A comment event (`t` 1) as white chat, or null for any other event:
  ///
  /// - the text is `cm` (a string, or an integer as the web shows it),
  ///   trimmed; blank or anything else: null. Counting comments ("1", "2",
  ///   …) are a SHOWROOM custom and stay;
  /// - the name is `ac`, the user id `u`;
  /// - the level is the class level `cl` when above 0 (the web shows
  ///   "Class" and the number only then);
  /// - the time is `created_at` (seconds); not positive or out of
  ///   `DateTime`'s range: none.
  ///
  /// The platform gives no message id. The avatar (`av`), the class badge
  /// (`cifn`, `cbisc`, `cbiec`) and `ua`, `aft`, `at`, `d` are not read.
  static LiveMessage? comment(Object? event) {
    if (event is! Map || !_isComment(event['t'])) return null;
    final text = _text(event['cm']);
    if (text.isEmpty) return null;
    final level = event['cl'];
    final created = event['created_at'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _text(event['ac']),
      userId: _text(event['u']),
      message: text,
      userLevel: level is int && level > 0 ? '$level' : '',
      sentAt: created is int && created > 0 && created <= _maxEpochSeconds
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
      color: LiveMessageColor.white,
    );
  }

  /// `t` is 1, as an integer or (as the archived v4 also read it) a string.
  static bool _isComment(Object? type) => (type is int && type == commentType) || type == '$commentType';

  static String _text(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => '$number',
    _ => '',
  };
}

/// SHOWROOM's comment connection (new in v4: 3.x had none, the 19-3
/// upgrade), on the WebSocket runtime: one socket to the broadcast server
/// of `ShowroomDanmakuArgs.host`, subscribed to its `key`.
///
/// - At every open it sends `SUB\t<key>` and counts as joined: the server
///   confirms nothing, as for the web client.
/// - `PING\tshowroom` every 60 s; its `ACK` keeps a quiet room from looking
///   silent, so a socket without any frame for max(3 × 60 s, 90 s) = 180 s
///   is replaced.
/// - Only comments are reported.
///
/// The app registers it as `SiteIds.showroom: () =>
/// ShowroomDanmakuConnection(proxy: …)`.
final class ShowroomDanmakuConnection extends DanmakuSocketConnection<ShowroomDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake and [policy] the timing (tests).
  new({super.proxy, super.connector, super.policy = socketPolicy}) : super(site: SiteIds.showroom);

  /// Socket timing: the runtime's defaults with the 60 s ping. No join
  /// timer: an open socket counts as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: ShowroomDanmakuProtocol.heartbeatInterval,
  );

  _Subscription? _subscription;

  @override
  @protected
  Future<DanmakuSocketTarget> target(ShowroomDanmakuArgs args, DanmakuRun run) async {
    final checked = ShowroomDanmakuProtocol.checked(args);
    if (checked == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable comment server or key');
    }
    _subscription = _Subscription(run, checked.key);
    return DanmakuSocketTarget(
      endpoints: [ShowroomDanmakuProtocol.endpoint(checked.host)],
      headers: ShowroomDanmakuProtocol.socketHeaders,
    );
  }

  _Subscription? _of(DanmakuSocketSession session) {
    final subscription = _subscription;
    return subscription != null && identical(subscription.run, session.run) ? subscription : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    final subscription = _of(session);
    if (subscription == null) return;
    session
      ..send(ShowroomDanmakuProtocol.subscribe(subscription.key))
      ..ready();
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final subscription = _of(session);
    if (subscription == null) return;
    ShowroomDanmakuProtocol.decode(data, key: subscription.key).forEach(session.message);
  }

  @override
  @protected
  Object? heartbeatFrame(DanmakuSocketSession session) => ShowroomDanmakuProtocol.ping;

  @override
  @protected
  Future<void> stop() async {
    _subscription = null;
    await super.stop();
  }
}

/// The broadcast one run subscribes to.
final class _Subscription {
  const new(this.run, this.key);

  final DanmakuRun run;
  final String key;
}
