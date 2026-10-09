import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// SHOWROOM's comment broadcast (the archived v4's spec/sites/showroom.md
/// §7, checked against the recording `fixtures/showroom/danmaku/S06-live`
/// and the web client; docs/D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/record.md), without I/O.
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

  /// `t` of a gift ([gift], D07.7).
  static const int giftType = 2;

  /// A gift's picture without the room's table: the address the table
  /// writes (`image`), by gift id.
  static Uri giftImage(String id) => Uri.https('static.showroom-live.com', '/image/gift/${id}_s.png');

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
    return valid == null
        ? null
        : ShowroomDanmakuArgs(roomId: args.roomId, host: valid.host, key: valid.key, gifts: args.gifts);
  }

  /// The chat and gifts of one frame (text, or UTF-8 bytes) of broadcast
  /// [key]: a `MSG` of that key whose object is a comment ([comment]) or a
  /// gift ([gift], named by [gifts], D07.7). Frames of another key, `ACK`,
  /// JSON that is not an object and every other kind give nothing.
  static List<LiveMessage> decode(
    Object? data, {
    required String key,
    ShowroomGiftCatalog gifts = ShowroomGiftCatalog.empty,
  }) {
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
    return [?comment(event), ?gift(event, gifts: gifts)];
  }

  /// A gift event (`t` 2, D07.7) as a [LiveMessageType.gift] message with a
  /// [LiveGift], or null for any other event or one without a gift id:
  ///
  /// - [LiveGift.id] `g`, [LiveGift.count] `n`;
  /// - from the room's table ([gifts], by `g`): [LiveGift.name]
  ///   `gift_name`, [LiveGift.free] `free`, and for a paid gift
  ///   [LiveGift.unitPrice] `point` and [LiveGift.totalValue] `point × n` in
  ///   [LiveGiftUnit.point] (SHOWROOM points, about a yen each); without the
  ///   table the gift has only its id, and `gt` 2 (the free kind of the
  ///   recorded stars) is free;
  /// - [LiveGift.iconUrl] the table's `image`, else [giftImage];
  /// - the sender as a [comment]'s (`ac`, `u`, the class level `cl`), the
  ///   time `created_at`. The platform gives no message id and no combo.
  static LiveMessage? gift(Object? event, {ShowroomGiftCatalog gifts = ShowroomGiftCatalog.empty}) {
    if (event is! Map || !_isType(event['t'], giftType)) return null;
    final id = _text(event['g']);
    if (id.isEmpty || id == '0') return null;
    final count = event['n'];
    final info = gifts[id];
    final free = info?.free ?? _text(event['gt']) == '2';
    final price = free ? null : info?.point;
    final data = LiveGift(
      id: id,
      name: info?.name ?? '',
      count: count is int ? count : 1,
      unitPrice: price,
      totalValue: price == null ? null : price * (count is int && count > 1 ? count : 1),
      unit: LiveGiftUnit.point,
      free: free,
      iconUrl: info?.image ?? giftImage(id),
    );
    final level = event['cl'];
    final created = event['created_at'];
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: _text(event['ac']),
      userId: _text(event['u']),
      message: data.plainText,
      userLevel: level is int && level > 0 ? '$level' : '',
      sentAt: created is int && created > 0 && created <= _maxEpochSeconds
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
      color: LiveMessageColor.white,
      data: data,
    );
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
  static bool _isComment(Object? type) => _isType(type, commentType);

  static bool _isType(Object? type, int expected) => (type is int && type == expected) || type == '$expected';

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
/// - Comments and gifts (D07.7) are reported; the room's gift table
///   (`ShowroomDanmakuArgs.gifts`) is asked for once per run in the
///   background, and gifts before it comes, or without it, have their ids
///   and pictures only.
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
    final subscription = _subscription = _Subscription(run, checked.key);
    if (args.gifts case final gifts?) unawaited(_loadGifts(subscription, gifts));
    return DanmakuSocketTarget(
      endpoints: [ShowroomDanmakuProtocol.endpoint(checked.host)],
      headers: ShowroomDanmakuProtocol.socketHeaders,
    );
  }

  Future<void> _loadGifts(_Subscription subscription, Future<ShowroomGiftCatalog> Function() gifts) async {
    try {
      final catalog = await gifts();
      if (identical(_subscription, subscription)) subscription.gifts = catalog;
    } on Object {
      // No table: gifts keep their ids.
    }
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
    ShowroomDanmakuProtocol.decode(data, key: subscription.key, gifts: subscription.gifts).forEach(session.message);
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

/// The broadcast one run subscribes to, and its gift table once it came.
final class _Subscription {
  new(this.run, this.key);

  final DanmakuRun run;
  final String key;
  ShowroomGiftCatalog gifts = ShowroomGiftCatalog.empty;
}
