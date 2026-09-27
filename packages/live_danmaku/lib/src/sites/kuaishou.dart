import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/numbers.dart';
import 'package:live_danmaku/src/runtime/base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// One parsed feed response.
@immutable
final class KuaishouFeed {
  /// Creates a feed.
  const new({required this.cursor, required this.pullDelay, required this.events});

  /// Cursor for the next request; empty keeps the previous one.
  final String cursor;

  /// `pullCycleSeconds`, 1–10 s (default 3 s).
  final Duration pullDelay;

  /// Comments and the online figure.
  final List<DanmakuEvent> events;
}

/// Kuaishou's mobile feed (spec/sites/kuaishou.md §7), without I/O.
abstract final class KuaishouProtocol {
  /// Feed endpoints, primary first (§7 request).
  static final List<Uri> endpoints = [
    Uri.parse('https://livev.m.chenzhongtech.com/wap/live/feed'),
    Uri.parse('https://m.gifshow.com/wap/live/feed'),
  ];

  /// §7 request headers; the cookie only when there is one.
  static Map<String, String> headers({String? cookie}) => {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/139.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://livev.m.chenzhongtech.com/',
    if (cookie != null && cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// The feed URL at [endpoint] for [liveStreamId], after [cursor].
  static Uri url(Uri endpoint, String liveStreamId, String cursor) =>
      endpoint.replace(queryParameters: {'liveStreamId': liveStreamId, if (cursor.isNotEmpty) 'cursor': cursor});

  /// §7 response: a body JSON-encoded 1–3 times, maybe inside `data`;
  /// `result != 1` throws [FormatException] (REG-KUAISHOU-012, -013).
  static KuaishouFeed parse(String body, {required DecodeContext context}) {
    Object? payload = body;
    for (var depth = 0; depth < 3 && payload is String; depth++) {
      payload = jsonDecode(payload);
    }
    if (payload is Map && payload['data'] is Map) payload = payload['data'];
    if (payload is! Map) throw const FormatException('Kuaishou feed: not an object');
    final result = _int(payload['result']);
    if (result != 1) throw FormatException('Kuaishou feed: result $result');
    final seconds = (_int(payload['pullCycleSeconds']) ?? 3).clamp(1, 10);
    final events = <DanmakuEvent>[];
    final watching = payload['currentWatchingCount']?.toString().trim() ?? '';
    final online = watching.isEmpty ? null : audienceNumber(watching);
    if (online != null) {
      events.add(
        DanmakuOnline(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          audience: AudienceKind.online,
          value: online,
        ),
      );
    }
    final feeds = payload['liveStreamFeeds'];
    if (feeds is List) {
      for (final feed in feeds) {
        if (feed is! Map || feed['type']?.toString().toLowerCase() != 'comment') continue;
        final text = feed['content']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final author = feed['author'] is Map ? feed['author'] as Map : const <Object?, Object?>{};
        final name = author['userName']?.toString().trim() ?? '';
        final userId = author['userId']?.toString() ?? '';
        final time = _int(feed['time']);
        final rawId = feed['id']?.toString().trim() ?? '';
        final id = rawId.isNotEmpty ? rawId : sha1.convert(utf8.encode('$time\u0000$userId\u0000$text')).toString();
        events.add(
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: 'kuaishou:$id',
            sentAt: time == null || time <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(time),
            userId: userId,
            userName: name.isEmpty ? '快手用户' : name,
            text: text,
          ),
        );
      }
    }
    return KuaishouFeed(
      cursor: payload['cursor']?.toString() ?? '',
      pullDelay: Duration(seconds: seconds),
      events: events,
    );
  }

  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
}

/// Kuaishou's chat: serial polling of the mobile feed (§7 polling):
/// three tries to start, the server's pull interval, back-off 1, 2, 4, 8 s,
/// terminal after the ninth consecutive failure.
final class KuaishouConnector extends ConnectorBase {
  /// Creates the connector; [detail]'s `danmakuKeys['liveStreamId']` is the
  /// broadcast.
  new({required super.detail, required super.transport, this.credentials, super.session, super.clock});

  /// Source of the user's cookie.
  final DanmakuCredentials? credentials;

  /// Waits between start attempts (§7: 0.6 s, 1.4 s).
  static const startRetries = [Duration(milliseconds: 600), Duration(milliseconds: 1400)];

  /// Consecutive failures before the terminal state.
  static const maxFailures = 8;

  String _cursor = '';

  @override
  Future<void> run(int generation) async {
    final stream = detail.danmakuKeys['liveStreamId'] ?? '';
    if (stream.isEmpty) {
      terminal(generation, 'noRoom', 'kuaishou liveStreamId missing');
      return;
    }
    status(generation, DanmakuStatus.connecting);
    String? cookie;
    try {
      cookie = await credentials?.cookie('kuaishou');
    } on Object {
      cookie = null;
    }
    final headers = KuaishouProtocol.headers(cookie: cookie);
    _cursor = '';
    // Start: three tries.
    KuaishouFeed? feed;
    for (var attempt = 0; attempt <= startRetries.length && feed == null; attempt++) {
      if (attempt > 0 && !await pause(generation, startRetries[attempt - 1])) return;
      feed = await _poll(generation, stream, headers);
    }
    if (isStale(generation)) return;
    if (feed == null) {
      terminal(generation, 'failed', 'feed');
      return;
    }
    status(generation, DanmakuStatus.connected);
    joined(generation);
    var failures = 0;
    var delay = feed.pullDelay;
    while (await pause(generation, delay)) {
      final next = await _poll(generation, stream, headers);
      if (isStale(generation)) return;
      if (next != null) {
        if (failures > 0) status(generation, DanmakuStatus.connected);
        failures = 0;
        delay = next.pullDelay;
        continue;
      }
      failures++;
      if (failures == 1) status(generation, DanmakuStatus.reconnecting);
      if (failures > maxFailures) {
        terminal(generation, 'maxRetries');
        return;
      }
      delay = Duration(seconds: 1 << (failures - 1 < 3 ? failures - 1 : 3));
    }
  }

  /// One round over the endpoints (primary first); null when every one
  /// failed. Events are emitted here.
  Future<KuaishouFeed?> _poll(int generation, String stream, Map<String, String> headers) async {
    final cancel = CancelToken();
    unawaited(stopped.then((_) => cancel.cancel()));
    for (final endpoint in KuaishouProtocol.endpoints) {
      if (isStale(generation)) return null;
      try {
        final response = await transport.http.send(
          LiveRequest(
            site: 'kuaishou',
            url: KuaishouProtocol.url(endpoint, stream, _cursor),
            headers: headers,
            timeout: const Duration(seconds: 10),
            cancel: cancel,
          ),
        );
        if (isStale(generation)) return null;
        if (!response.isSuccess) continue;
        final feed = KuaishouProtocol.parse(response.text, context: context());
        if (feed.cursor.isNotEmpty) _cursor = feed.cursor;
        for (final event in feed.events) {
          emit(generation, event);
        }
        return feed;
      } on Object {
        continue;
      }
    }
    return null;
  }
}
