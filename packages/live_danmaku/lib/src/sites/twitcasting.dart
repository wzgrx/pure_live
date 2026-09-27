import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// TwitCasting's comment stream (spec/sites/twitcasting.md §7): a signed
/// socket URL per broadcast, then JSON arrays the server pushes (an empty
/// array keeps the socket alive). Without I/O.
abstract final class TwitcastingProtocol {
  /// The socket URL request.
  static final Uri pubsubUrl = Uri.parse('https://twitcasting.tv/eventpubsuburl.php');

  /// Silence watchdog base: the server sends at least an empty array every
  /// few tens of seconds, so 3 × 30 s without anything is a dead socket.
  static const watchInterval = Duration(seconds: 30);

  /// Request headers.
  static const Map<String, String> headers = {'origin': 'https://twitcasting.tv', 'user-agent': _userAgent};

  /// §7.1 the form body for broadcast [movieId].
  static List<int> form(String movieId) => utf8.encode('movie_id=${Uri.encodeQueryComponent(movieId)}');

  /// §7.1 the socket URL of a `eventpubsuburl.php` answer, or null.
  static Uri? socket(String body) {
    try {
      final root = jsonDecode(body);
      final url = root is Map ? Uri.tryParse('${root['url'] ?? ''}') : null;
      return url != null && url.scheme == 'wss' && url.host.endsWith('twitcasting.tv') ? url : null;
    } on FormatException {
      return null;
    }
  }

  /// §7.2 decodes one pushed array.
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
    final items = root is List ? root : [root];
    final events = <DanmakuEvent>[];
    for (final item in items) {
      if (item is! Map) continue;
      final author = item['author'] is Map ? item['author'] as Map : const <Object?, Object?>{};
      final created = item['createdAt'];
      final sentAt = created is int && created > 0 ? DateTime.fromMillisecondsSinceEpoch(created) : null;
      switch (item['type']) {
        case 'comment':
          final message = '${item['message'] ?? ''}'.trim();
          if (message.isEmpty) continue;
          events.add(
            DanmakuChat(
              room: context.room,
              session: context.session,
              receivedAt: context.receivedAt,
              id: item['id'] == null ? null : 'twitcasting:${item['id']}',
              sentAt: sentAt,
              userId: '${author['id'] ?? ''}',
              userName: '${author['name'] ?? ''}',
              text: message,
            ),
          );
        case 'gift':
          final item0 = item['item'] is Map ? item['item'] as Map : const <Object?, Object?>{};
          final sender = item['sender'] is Map ? item['sender'] as Map : author;
          final name = '${item0['name'] ?? ''}';
          if (name.isEmpty) continue;
          events.add(
            DanmakuGift(
              room: context.room,
              session: context.session,
              receivedAt: context.receivedAt,
              id: item['id'] == null ? null : 'twitcasting:${item['id']}',
              sentAt: sentAt,
              userId: '${sender['id'] ?? ''}',
              userName: '${sender['name'] ?? ''}',
              giftId: '${item0['id'] ?? ''}',
              giftName: name,
            ),
          );
      }
    }
    return events;
  }
}

/// TwitCasting's comment connection for the current broadcast
/// (`danmakuKeys['movieId']`): a signed URL per start, no client frames.
final class TwitcastingConnector extends SocketConnector {
  /// Creates the connector.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _movie => detail.danmakuKeys['movieId'] ?? '';

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    if (_movie.isEmpty) throw const DanmakuStartFailure('credentials', 'no current broadcast');
    final LiveResponse response;
    try {
      response = await transport.http.send(
        LiveRequest(
          site: 'twitcasting',
          url: TwitcastingProtocol.pubsubUrl,
          method: 'POST',
          headers: const {
            ...TwitcastingProtocol.headers,
            'content-type': 'application/x-www-form-urlencoded',
            'referer': 'https://twitcasting.tv/',
          },
          body: TwitcastingProtocol.form(_movie),
        ),
      );
    } on Object catch (error) {
      throw DanmakuStartFailure('credentials', '$error');
    }
    final url = response.isSuccess ? TwitcastingProtocol.socket(response.text) : null;
    if (url == null) throw DanmakuStartFailure('credentials', 'eventpubsuburl HTTP ${response.status}');
    return SocketPlan(endpoints: [url], headers: TwitcastingProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => const [];

  @override
  Duration get heartbeatInterval => TwitcastingProtocol.watchInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int>? heartbeat() => null;

  @override
  FrameResult decode(Object? data, DecodeContext context) =>
      FrameResult(events: TwitcastingProtocol.decode(data, context: context));
}
