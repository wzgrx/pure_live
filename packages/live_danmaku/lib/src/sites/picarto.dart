import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// Picarto's chat (spec/sites/picarto.md §7): an anonymous JWT from the
/// GraphQL API, then a JSON WebSocket the server keeps alive. Without I/O.
abstract final class PicartoProtocol {
  /// The GraphQL endpoint.
  static final Uri graphql = Uri.parse('https://ptvintern.picarto.tv/ptvapi');

  /// Silence watchdog base: the server sends `stream` updates every
  /// 25–60 s (S07-live), so 3 × 60 s without anything is a dead connection.
  static const watchInterval = Duration(seconds: 60);

  /// Request headers.
  static const Map<String, String> headers = {'origin': 'https://picarto.tv', 'user-agent': _userAgent};

  /// §7.1 the token request body for [channel].
  static List<int> tokenQuery(String channel) => utf8.encode(
    jsonEncode({
      'query': r'query ($name: String) { generateJwtToken(channel_name: $name) { key } }',
      'variables': {'name': channel},
    }),
  );

  /// §7.1 the JWT of a token response, or null.
  static String? token(String body) {
    try {
      final root = jsonDecode(body);
      final data = root is Map ? root['data'] : null;
      final generated = data is Map ? data['generateJwtToken'] : null;
      final key = generated is Map ? generated['key'] : null;
      return key is String && key.split('.').length == 3 ? key : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.1 the chat socket for [token].
  static Uri endpoint(String token) => Uri.parse('wss://chat.picarto.tv/chat/token=$token');

  /// §7.2 decodes one received message.
  static List<DanmakuEvent> decode(Object? data, {required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const [];
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    if (root is! Map) return const [];
    if (root['type'] == 'stream') {
      final messages = root['messages'];
      final viewers = messages is Map ? messages['viewers'] : null;
      return [
        if (viewers is int && viewers >= 0)
          DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: AudienceKind.online,
            value: viewers,
          ),
      ];
    }
    if (root['t'] != 'c' || root['m'] is! List) return const [];
    return [
      for (final item in root['m'] as List)
        if (item is Map && item['m'] is String && (item['m'] as String).trim().isNotEmpty)
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: item['id'] is String ? 'picarto:${item['id']}' : null,
            sentAt: item['d'] is int ? DateTime.fromMillisecondsSinceEpoch(item['d'] as int) : null,
            userId: '${item['u'] ?? ''}',
            userName: '${item['n'] ?? ''}',
            text: (item['m'] as String).trim(),
            color: DanmakuColors.parse(item['k'] as String?) ?? DanmakuColors.white,
          ),
    ];
  }
}

/// Picarto's chat connection: a JWT per start, no client heartbeat.
final class PicartoConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['channelName']` names
  /// the channel.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _channel => detail.danmakuKeys['channelName'] ?? room.roomId;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final LiveResponse response;
    try {
      response = await transport.http.send(
        LiveRequest(
          site: 'picarto',
          url: PicartoProtocol.graphql,
          method: 'POST',
          headers: const {
            ...PicartoProtocol.headers,
            'content-type': 'application/json',
            'referer': 'https://picarto.tv/',
          },
          body: PicartoProtocol.tokenQuery(_channel),
        ),
      );
    } on Object catch (error) {
      throw DanmakuStartFailure('credentials', '$error');
    }
    final token = response.isSuccess ? PicartoProtocol.token(response.text) : null;
    if (token == null) throw DanmakuStartFailure('credentials', 'generateJwtToken HTTP ${response.status}');
    return SocketPlan(endpoints: [PicartoProtocol.endpoint(token)], headers: PicartoProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => const [];

  @override
  Duration get heartbeatInterval => PicartoProtocol.watchInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int>? heartbeat() => null;

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      FrameResult(events: PicartoProtocol.decode(data, context: context));
}
