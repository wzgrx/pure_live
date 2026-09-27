import 'dart:convert';
import 'dart:io';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:live_net/live_net.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// 17LIVE's chat (spec/sites/17live.md §7): an anonymous Ably token from
/// `messenger/auth`, then Ably's JSON realtime protocol on the room's
/// channel; message payloads are gzip + base64 JSON. Without I/O.
abstract final class SeventeenliveProtocol {
  /// §7.1 the token source.
  static final Uri auth = Uri.parse('https://api-dsa.17app.co/api/v1/messenger/auth');

  /// §7.2 the server's heartbeat period (`maxIdleInterval`); the client
  /// sends none.
  static const heartbeatInterval = Duration(seconds: 15);

  /// Request and handshake headers.
  static const Map<String, String> headers = {'origin': 'https://17.live', 'user-agent': _userAgent};

  /// §7.1 the Ably token of an auth answer; null unless the provider is
  /// Ably (1).
  static String? token(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map || root['provider'] != 1) return null;
      final token = root['token'];
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.1 the realtime socket for [token].
  static Uri endpoint(String token) => Uri(
    scheme: 'wss',
    host: '17media.realtime.ably.net',
    path: '/',
    queryParameters: {'access_token': token, 'format': 'json', 'heartbeats': 'true', 'v': '3'},
  );

  /// §7.1 the ATTACH message for room [roomId].
  static TextFrame attach(String roomId) => TextFrame(jsonEncode({'action': 10, 'channel': roomId}));

  /// §7.3 a message payload: base64 of gzip of JSON (or plain JSON).
  static Map<String, dynamic>? payload(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is! String || data.isEmpty) return null;
    try {
      final text = data.startsWith('H4sI') ? utf8.decode(gzip.decode(base64.decode(data))) : data;
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.3 decodes one frame of room [roomId].
  static FrameResult decode(Object? data, {required String roomId, required DecodeContext context}) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return FrameResult.empty;
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return FrameResult.empty;
    }
    if (root is! Map) return FrameResult.empty;
    switch (root['action']) {
      case 11 when '${root['channel']}' == roomId:
        return const FrameResult(joined: true);
      case 6 || 9 || 13 when root['error'] != null:
        return const FrameResult(rejected: true);
      case 15 when '${root['channel']}' == roomId:
        final messages = root['messages'];
        return FrameResult(
          events: [
            for (final message in messages is List ? messages : const <Object?>[])
              if (message is Map)
                ...?_event(
                  payload(message['data']),
                  id: message['id'] is String ? message['id'] as String : null,
                  context: context,
                ),
          ],
        );
      default:
        return FrameResult.empty;
    }
  }

  static DateTime? _time(Object? millis) =>
      millis is int && millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null;

  static List<DanmakuEvent>? _event(
    Map<String, dynamic>? message, {
    required String? id,
    required DecodeContext context,
  }) {
    if (message == null) return null;
    switch (message['type']) {
      case 3:
        final comment = message['commentMsg'];
        if (comment is! Map) return null;
        final body = comment['comment'];
        final text = '${(body is Map ? body['text'] : null) ?? comment['content'] ?? ''}'.trim();
        if (text.isEmpty) return null;
        final user = comment['displayUser'] is Map ? comment['displayUser'] as Map : const <String, Object?>{};
        return [
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null ? null : '17live:$id',
            sentAt: _time(comment['sendTime']),
            userId: '${user['userID'] ?? ''}',
            userName: '${user['displayName'] ?? user['openID'] ?? ''}',
            text: text,
          ),
        ];
      case 13:
        final gift = message['giftMsg'];
        if (gift is! Map || gift['giftID'] is! String) return null;
        final user = gift['displayUser'] is Map ? gift['displayUser'] as Map : const <String, Object?>{};
        return [
          DanmakuGift(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null ? null : '17live:$id',
            userId: '${user['userID'] ?? ''}',
            userName: '${user['displayName'] ?? user['openID'] ?? ''}',
            giftId: gift['giftID'] as String,
            giftName: gift['giftID'] as String,
          ),
        ];
      case 38:
        final info = message['liveinfo'];
        final viewers = info is Map ? info['liveViewerCount'] : null;
        if (viewers is! int || viewers < 0) return null;
        return [
          DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: AudienceKind.online,
            value: viewers,
          ),
        ];
      default:
        return null;
    }
  }
}

/// 17LIVE's chat connection: a fresh anonymous Ably token per connection,
/// ATTACH to the room's channel, joined on ATTACHED; the server sends the
/// heartbeats.
final class SeventeenliveConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['roomId']` names the
  /// channel.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _roomId => detail.danmakuKeys['roomId'] ?? room.roomId;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    final LiveResponse response;
    try {
      response = await transport.http.send(
        LiveRequest(
          site: '17live',
          url: SeventeenliveProtocol.auth,
          method: 'POST',
          headers: const {
            ...SeventeenliveProtocol.headers,
            'accept': 'application/json',
            'content-type': 'application/json',
            'referer': 'https://17.live/',
          },
          body: utf8.encode('{}'),
        ),
      );
    } on Object catch (error) {
      throw DanmakuStartFailure('credentials', '$error');
    }
    final token = response.isSuccess ? SeventeenliveProtocol.token(response.text) : null;
    if (token == null) throw DanmakuStartFailure('credentials', 'messenger/auth HTTP ${response.status}');
    return SocketPlan(endpoints: [SeventeenliveProtocol.endpoint(token)], headers: SeventeenliveProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => [SeventeenliveProtocol.attach(_roomId)];

  @override
  bool get joinedOnOpen => false;

  @override
  Duration get heartbeatInterval => SeventeenliveProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int>? heartbeat() => null;

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      SeventeenliveProtocol.decode(data, roomId: _roomId, context: context);
}
