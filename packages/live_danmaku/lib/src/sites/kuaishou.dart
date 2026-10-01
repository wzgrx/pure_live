import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// The comment feed refused the request: its `result` is not 1 (3.x threw a
/// `StateError`). A refused answer is not asked again on the fallback
/// endpoint.
@immutable
final class KuaishouFeedRejected implements Exception {
  /// Creates the failure.
  const new(this.result);

  /// The feed's `result`, or null when it was missing or not a number.
  final int? result;

  @override
  String toString() => 'KuaishouFeedRejected(result: ${result ?? 'unknown'})';
}

/// One answer of the comment feed (3.x `KuaishouFeedBatch`).
@immutable
final class KuaishouFeedBatch {
  /// Creates the batch.
  const new({required this.cursor, required this.pullDelay, required this.messages, this.onlineViewers});

  /// Cursor for the next request; empty keeps the previous one.
  final String cursor;

  /// Wait before the next request: `pullCycleSeconds`, 1–10 s (3 s when
  /// missing).
  final Duration pullDelay;

  /// The comments, in feed order.
  final List<LiveMessage> messages;

  /// `currentWatchingCount` as a number; null when the feed left it empty.
  final int? onlineViewers;

  /// What the connection reports for this answer, in 3.x's order: the
  /// audience figure (when there is one), then the comments.
  List<LiveMessage> get reported => [
    if (onlineViewers case final viewers?) KuaishouDanmakuProtocol.audience(viewers),
    ...messages,
  ];
}

/// Kuaishou's comment feed (the protocol of 3.x `KuaishouDanmaku`), without
/// I/O: the mobile site's incremental feed, polled over HTTP. The desktop
/// WebSocket needs a signed browser bootstrap; the feed carries the same
/// public comments and the concurrent audience anonymously.
abstract final class KuaishouDanmakuProtocol {
  /// The feed endpoints, primary first; every request tries the primary and
  /// falls back to the second when it gets no usable answer.
  static final List<Uri> endpoints = [
    Uri.parse('https://livev.m.chenzhongtech.com/wap/live/feed'),
    Uri.parse('https://m.gifshow.com/wap/live/feed'),
  ];

  /// The mobile Chrome 139 on Android 16 3.x presented to the feed.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/139.0 Mobile Safari/537.36';

  /// Waits before the second and third try of the first request.
  static const List<Duration> startRetryDelays = [Duration(milliseconds: 600), Duration(milliseconds: 1400)];

  /// Failed requests in a row that are retried; the next one ends the
  /// connection.
  static const int maxFailures = 8;

  /// Wait before the next request when the feed gives no pull cycle.
  static const Duration defaultPullDelay = Duration(seconds: 3);

  /// The name of a commenter without one.
  static const String anonymousUserName = '快手用户';

  /// Request headers; the cookie (trimmed) only when there is one.
  static Map<String, String> headers(String cookie) => {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://livev.m.chenzhongtech.com/',
    if (cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// Query of a request for [liveStreamId] after [cursor] (none for the
  /// first request).
  static Map<String, String> query(String liveStreamId, String cursor) => {
    'liveStreamId': liveStreamId,
    if (cursor.isNotEmpty) 'cursor': cursor,
  };

  /// Wait after the [failures]-th failed request in a row: 1, 2, 4, then
  /// 8 s.
  static Duration backoff(int failures) => Duration(seconds: 1 << (failures - 1).clamp(0, 3));

  /// The audience figure as a message.
  static LiveMessage audience(int viewers) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
    color: LiveMessageColor.white,
  );

  /// Parses one answer (3.x `parseFeedPayload`): [body] is the response
  /// decoded once; text is decoded up to three more times (the feed sends a
  /// JSON string holding the JSON object) and an object under `data` is
  /// unwrapped.
  ///
  /// Throws [FormatException] when no object results and
  /// [KuaishouFeedRejected] when `result` is not 1. Only `comment` entries
  /// (any case) with text become messages; an entry that cannot be read (a
  /// time out of range) is skipped without losing the others. A comment's
  /// codes found in [emotes] (the room page's emoji table, `[笑哭]` → its
  /// picture) are its [LiveMessage.emotes] (M13.16; the feed itself has no
  /// pictures).
  static KuaishouFeedBatch parse(Object? body, {Map<String, String> emotes = const {}}) {
    var payload = body;
    for (var depth = 0; depth < 3 && payload is String; depth++) {
      payload = jsonDecode(payload);
    }
    if (payload case {'data': final Map<Object?, Object?> data}) payload = data;
    if (payload is! Map<Object?, Object?>) throw const FormatException('Kuaishou feed has an invalid shape');

    final result = _int(payload['result']);
    if (result != 1) throw KuaishouFeedRejected(result);
    final watching = payload['currentWatchingCount']?.toString().trim() ?? '';
    final feeds = payload['liveStreamFeeds'];
    return KuaishouFeedBatch(
      cursor: payload['cursor']?.toString() ?? '',
      pullDelay: Duration(seconds: (_int(payload['pullCycleSeconds']) ?? defaultPullDelay.inSeconds).clamp(1, 10)),
      messages: List.unmodifiable([
        if (feeds is List<Object?>)
          for (final feed in feeds) ?_comment(feed, emotes),
      ]),
      onlineViewers: watching.isEmpty ? null : parseAudienceNumber(watching),
    );
  }

  /// The largest time `DateTime` holds, in milliseconds either side of the
  /// epoch.
  static const int _maxMilliseconds = 8640000000000000;

  /// One feed entry as a chat message; null when it is not a comment, has no
  /// text, or has a time no `DateTime` can hold (3.x failed the whole answer
  /// on such an entry, and every retry of it, as the cursor stayed put).
  static LiveMessage? _comment(Object? feed, Map<String, String> emotes) {
    if (feed is! Map<Object?, Object?> || feed['type']?.toString().toLowerCase() != 'comment') return null;
    final content = feed['content']?.toString().trim() ?? '';
    if (content.isEmpty) return null;
    final time = feed['time'];
    if (time is double && !time.isFinite) return null;
    final timestamp = _int(time);
    if (timestamp != null && (timestamp < -_maxMilliseconds || timestamp > _maxMilliseconds)) return null;
    final author = feed['author'] is Map<Object?, Object?>
        ? feed['author']! as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final userName = author['userName']?.toString().trim() ?? '';
    final userId = author['userId']?.toString() ?? '';
    final rawId = feed['id']?.toString().trim() ?? '';
    final id = rawId.isNotEmpty ? rawId : sha1.convert(utf8.encode('$timestamp\u0000$userId\u0000$content')).toString();
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: userName.isEmpty ? anonymousUserName : userName,
      userId: userId,
      message: content,
      messageId: 'kuaishou:$id',
      sentAt: timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp),
      color: LiveMessageColor.white,
      emotes: emotes.isEmpty ? const [] : codeEmotes(content, emotes),
    );
  }

  /// The `[…]` codes of [text] that [table] has, each once, in order.
  static List<LiveEmote> codeEmotes(String text, Map<String, String> table) {
    final seen = <String>{};
    return [
      for (final match in _code.allMatches(text))
        if (table[match.group(0)!] case final url? when seen.add(match.group(0)!))
          LiveEmote(code: match.group(0)!, url: url),
    ];
  }

  static final RegExp _code = RegExp(r'\[[^\[\]\n]{1,16}\]');

  /// 3.x `_asInt`: numbers truncated, text parsed, anything else null.
  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// Kuaishou's danmaku connection (3.x `KuaishouDanmaku`): serial polling of
/// the comment feed over [LiveHttp], no socket and no heartbeat.
///
/// `connect` asks for the first answer up to three times (0.6 s and 1.4 s
/// apart) and throws the last failure when all three fail; the first answer
/// joins. Every next request waits for the previous one and then the pull
/// cycle the feed asked for. A failed request is retried after 1, 2, 4, 8, 8…
/// seconds, the first failure in a row reports [DanmakuReconnecting], the
/// ninth ends with [DanmakuClosed]; any answer joins again.
///
/// The app registers it as `SiteIds.kuaishou: () =>
/// KuaishouDanmakuConnection(http: …)`, with the `LiveHttp` it gives
/// `KuaishouSite` (proxy route and throttle by the platform id). The cookie
/// comes with the arguments.
final class KuaishouDanmakuConnection extends DanmakuConnectionBase<KuaishouDanmakuArgs> {
  /// Creates the connection; `http` sends the feed requests.
  new({required this._http});

  final LiveHttp _http;

  @override
  Future<void> start(KuaishouDanmakuArgs args, DanmakuRun run) async {
    if (args.liveStreamId.trim().isEmpty) throw const FormatException('Kuaishou live stream id is missing');
    final feed = _KuaishouFeed(_http, args, run);
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt <= KuaishouDanmakuProtocol.startRetryDelays.length; attempt++) {
      if (attempt > 0 && !await run.delay(KuaishouDanmakuProtocol.startRetryDelays[attempt - 1])) return;
      final KuaishouFeedBatch batch;
      try {
        batch = await feed.pull();
      } on Object catch (error, stackTrace) {
        if (!run.isActive) return;
        lastError = error;
        lastStackTrace = stackTrace;
        continue;
      }
      if (!run.isActive) return;
      feed.report(batch);
      unawaited(feed.follow(batch.pullDelay));
      return;
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }
}

/// The feed of one run: the cursor, and the requests, cancelled when the run
/// ends.
final class _KuaishouFeed {
  new(this._http, KuaishouDanmakuArgs args, this._run)
    : _liveStreamId = args.liveStreamId,
      _emotes = args.emotes,
      _headers = KuaishouDanmakuProtocol.headers(args.cookie) {
    unawaited(_run.ended.then((_) => _cancel.cancel()));
  }

  final LiveHttp _http;
  final DanmakuRun _run;
  final String _liveStreamId;
  final Map<String, String> _emotes;
  final Map<String, String> _headers;
  final CancelToken _cancel = CancelToken();
  String _cursor = '';

  /// Requests and parses the next answer; a new cursor is kept.
  Future<KuaishouFeedBatch> pull() async {
    final batch = KuaishouDanmakuProtocol.parse(await _fetch(), emotes: _emotes);
    if (batch.cursor.isNotEmpty) _cursor = batch.cursor;
    return batch;
  }

  /// Joins when not joined, then reports the answer.
  void report(KuaishouFeedBatch batch) {
    if (!_run.isConnected) _run.ready();
    batch.reported.forEach(_run.message);
  }

  /// Polls until the run ends, after waiting [delay].
  Future<void> follow(Duration delay) async {
    var wait = delay;
    var failures = 0;
    while (await _run.delay(wait)) {
      final KuaishouFeedBatch batch;
      try {
        batch = await pull();
      } on Object catch (error) {
        if (!_run.isActive) return;
        failures++;
        if (failures > KuaishouDanmakuProtocol.maxFailures) {
          _run.closed(DanmakuCloseReason.reconnectsExhausted, detail: '$error');
          return;
        }
        if (failures == 1) _run.reconnecting(DanmakuInterruption.disconnected);
        wait = KuaishouDanmakuProtocol.backoff(failures);
        continue;
      }
      if (!_run.isActive) return;
      failures = 0;
      report(batch);
      wait = batch.pullDelay;
    }
  }

  /// The body of one answer, decoded once: the primary endpoint, then the
  /// fallback when the primary gave no usable answer (no response, a status
  /// that is not 2xx, a body that is not JSON). Throws the fallback's failure.
  Future<Object?> _fetch() async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final endpoint in KuaishouDanmakuProtocol.endpoints) {
      try {
        return await _http.getJson(
          SiteIds.kuaishou,
          endpoint,
          query: KuaishouDanmakuProtocol.query(_liveStreamId, _cursor),
          headers: _headers,
          cancel: _cancel,
        );
      } on Object catch (error, stackTrace) {
        if (_cancel.isCancelled) rethrow;
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }
}
