import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_danmaku/src/transport.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// SHOWROOM's comment broadcast (spec/sites/showroom.md §7): tab-separated
/// text frames on the `bcsvr` host. Without I/O.
abstract final class ShowroomProtocol {
  /// Ping period (§7.2).
  static const heartbeatInterval = Duration(seconds: 60);

  /// The default broadcast host.
  static const defaultHost = 'online.showroom-live.com';

  /// Handshake headers.
  static const Map<String, String> headers = {'origin': 'https://www.showroom-live.com', 'user-agent': _userAgent};

  /// §7.1 the socket on [host].
  static Uri endpoint(String host) => Uri.parse('wss://$host/');

  /// §7.1 the subscription for live key [key].
  static TextFrame subscribe(String key) => TextFrame('SUB\t$key');

  /// §7.2 the ping.
  static TextFrame ping() => TextFrame('PING\tshowroom');

  /// §7.3 decodes one frame of live [key]: `MSG\t<key>\t<json>`.
  static List<DanmakuEvent> decode(Object? data, {required String key, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null || !text.startsWith('MSG\t')) return const [];
    final parts = text.split('\t');
    if (parts.length < 3 || parts[1] != key) return const [];
    final Object? message;
    try {
      message = jsonDecode(parts.sublist(2).join('\t'));
    } on FormatException {
      return const [];
    }
    if (message is! Map) return const [];
    final created = message['created_at'];
    final sentAt = created is int && created > 0 ? DateTime.fromMillisecondsSinceEpoch(created * 1000) : null;
    final user = '${message['u'] ?? ''}';
    final name = '${message['ac'] ?? ''}';
    switch ('${message['t']}') {
      case '1':
        final comment = '${message['cm'] ?? ''}'.trim();
        if (comment.isEmpty) return const [];
        return [
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: created == null ? null : 'showroom:$user:$created:${comment.hashCode}',
            sentAt: sentAt,
            userId: user,
            userName: name,
            text: comment,
          ),
        ];
      case '2':
        final gift = '${message['g'] ?? ''}';
        if (gift.isEmpty) return const [];
        final count = message['n'];
        return [
          DanmakuGift(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            sentAt: sentAt,
            userId: user,
            userName: name,
            giftId: gift,
            giftName: '#$gift',
            count: count is int && count > 0 ? count : 1,
          ),
        ];
      default:
        return const [];
    }
  }
}

/// SHOWROOM's comment connection: subscribe to the live's key, ping every
/// 60 s.
final class ShowroomConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys` hold `bcsvrKey` and
  /// `bcsvrHost`.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _key => detail.danmakuKeys['bcsvrKey'] ?? '';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    if (_key.isEmpty) throw const DanmakuStartFailure('credentials', 'no bcsvr key');
    final host = detail.danmakuKeys['bcsvrHost'] ?? ShowroomProtocol.defaultHost;
    if (!RegExp(r'^[a-z0-9.-]+\.showroom-live\.com$').hasMatch(host)) {
      throw DanmakuStartFailure('credentials', 'unexpected bcsvr host $host');
    }
    return SocketPlan(endpoints: [ShowroomProtocol.endpoint(host)], headers: ShowroomProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => [ShowroomProtocol.subscribe(_key)];

  @override
  Duration get heartbeatInterval => ShowroomProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => ShowroomProtocol.ping();

  @override
  FrameResult decode(Object? data, DecodeContext context) => FrameResult(
    events: ShowroomProtocol.decode(data, key: _key, context: context),
  );
}
