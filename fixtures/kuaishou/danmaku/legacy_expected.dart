// Writes fixtures/kuaishou/danmaku/*/expected.json: what 3.x's Kuaishou
// danmaku did with the recorded feed answers of S16-live and with the
// synthetic answers and sessions of S17-synthetic
// (docs/modules/M5.5-kuaishou.md, "与 v3 的对照").
//
// The code in the "3.x" section is KuaishouDanmaku copied whole from
// legacy/lib/core/danmaku/kuaishou_danmaku.dart (archive/v4), with the parts
// of LiveMessage, LiveMessageColor, LiveAudienceUpdate and
// LiveRoom.parseAudienceNumber it uses (legacy/lib/common/models/). It keeps
// `package:crypto` (sha1), as 3.x. Only these are replaced:
//
// - `HttpClient.instance.getJson` (the request `_fetchFeed` makes) by a stub
//   that records the request (endpoint, query parameters, headers) and answers
//   the next scripted step: `error` and a status that is not 2xx throw, as
//   3.x's client did (dio's error wrapped in a `CoreError`); otherwise the body
//   is decoded once, as dio does for a JSON content type, and a body that is
//   not JSON throws the same way. When the steps run out the request never
//   completes and the session ends;
// - dio's `CancelToken` and `DioException`, `CoreLog` (stderr) and the
//   `LiveDanmaku` interface by stubs with the members the class uses;
// - timers: every session runs in a zone that records each timer's duration
//   (the start's retry waits and every poll's wait) and fires it at once.
//
// One session is one `start` with the callbacks recording, in order: requests,
// timer waits, `onReady`, messages (projected), `onReconnect` and `onClose`
// texts, and how `start` ended. S16-live replays the recorded answers in
// order with the recorded liveStreamId; its per-answer parse results are
// written too.
//
// Run from the repository root:
//
//   dart run fixtures/kuaishou/danmaku/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, stderr, stdout;

import 'package:crypto/crypto.dart';

const _root = 'fixtures/kuaishou/danmaku';

Future<void> main() async {
  await _recorded();
  await _synthetic();
}

Future<void> _recorded() async {
  final meta = jsonDecode(File('$_root/S16-live/meta.json').readAsStringSync()) as Map<String, dynamic>;
  final liveStreamId = (meta['danmakuKeys'] as Map)['liveStreamId'] as String;
  final frames = [
    for (final line in File('$_root/S16-live/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final answers = [
    for (final frame in frames)
      if (frame['dir'] == 'in') frame['text'] as String,
  ];
  _write('$_root/S16-live/expected.json', {
    'generator':
        'fixtures/kuaishou/danmaku/legacy_expected.dart: 3.x KuaishouDanmaku.parseFeedPayload over every recorded '
        'answer (decoded once first, as dio did), and one 3.x session (start with the liveStreamId of meta.json '
        'danmakuKeys, no cookie) answered by the recorded answers in order',
    'value': {
      'liveStreamId': liveStreamId,
      'answers': [for (final text in answers) _parse(jsonDecode(text))],
      'session': await _session(liveStreamId: liveStreamId, cookie: '', steps: [
        for (final text in answers) {'raw': text},
      ]),
    },
  });
}

Future<void> _synthetic() async {
  final doc = jsonDecode(File('$_root/S17-synthetic/cases.json').readAsStringSync()) as Map<String, dynamic>;
  final feeds = [
    for (final item in doc['feeds'] as List)
      {
        'name': (item as Map)['name'],
        ..._decodeOnce(bodyOf(item as Map<String, dynamic>)),
        if (item['skipEntry'] case final int entry) 'v3WithoutEntry': _parse(_without(bodyOf(item), entry)),
      },
  ];
  final sessions = <Map<String, Object?>>[];
  for (final item in doc['sessions'] as List) {
    final testCase = item as Map<String, dynamic>;
    sessions.add({
      'name': testCase['name'],
      'trace': await _session(
        liveStreamId: testCase['liveStreamId'] as String? ?? 'ls-synthetic',
        cookie: testCase['cookie'] as String? ?? '',
        steps: [for (final step in testCase['steps'] as List) step as Map<String, dynamic>],
      ),
    });
  }
  _write('$_root/S17-synthetic/expected.json', {
    'generator':
        'fixtures/kuaishou/danmaku/legacy_expected.dart: 3.x KuaishouDanmaku.parseFeedPayload over each feed of '
        'cases.json (decoded once first, as dio did), and one 3.x session per session of cases.json (liveStreamId '
        '"ls-synthetic" unless the case gives one)',
    'value': {'feeds': feeds, 'sessions': sessions},
  });
}

/// The body text of one answer of cases.json.
String bodyOf(Map<String, dynamic> answer) {
  final raw = answer['raw'];
  if (raw is String) return raw;
  var text = jsonEncode(answer['payload']);
  final layers = answer['layers'] as int? ?? 2;
  for (var layer = 1; layer < layers; layer++) {
    text = jsonEncode(text);
  }
  return text;
}

/// The payload of [body] (decoded until it is not text) without entry
/// [entry] of `liveStreamFeeds`.
Map<String, dynamic> _without(String body, int entry) {
  Object? payload = body;
  while (payload is String) {
    payload = jsonDecode(payload);
  }
  final map = payload as Map<String, dynamic>;
  (map['liveStreamFeeds'] as List).removeAt(entry);
  return map;
}

Map<String, Object?> _decodeOnce(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return {'error': 'CoreError'};
  }
  return _parse(decoded);
}

Map<String, Object?> _parse(Object? raw) {
  try {
    final batch = KuaishouDanmaku.parseFeedPayload(raw);
    return {
      'cursor': batch.cursor,
      'pullDelayMs': batch.pullDelay.inMilliseconds,
      'onlineViewers': batch.onlineViewers,
      'messages': [for (final message in batch.messages) _project(message)],
    };
  } catch (error) {
    return {'error': error.runtimeType.toString()};
  }
}

Future<List<Map<String, Object?>>> _session({
  required String liveStreamId,
  required String cookie,
  required List<Map<String, dynamic>> steps,
}) async {
  final trace = <Map<String, Object?>>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  var next = 0;
  HttpClient.instance.handler = (url, queryParameters, header) async {
    trace.add({
      'request': {'url': url, 'query': {...?queryParameters}, 'headers': {...?header}},
    });
    if (next >= steps.length) {
      finish();
      return Completer<dynamic>().future;
    }
    final step = steps[next++];
    if (step['error'] != null) throw CoreError('scripted ${step['error']}');
    final status = step['status'] as int? ?? 200;
    if (status < 200 || status >= 300) throw CoreError('status $status');
    try {
      return jsonDecode(bodyOf(step));
    } on FormatException {
      throw CoreError('body is not JSON');
    }
  };

  final engine = KuaishouDanmaku();
  engine.onReady = () => trace.add({'event': 'ready'});
  engine.onMessage = (message) => trace.add({'event': 'message', 'message': _project(message)});
  engine.onReconnect = (text) => trace.add({'event': 'reconnect', 'text': text});
  engine.onClose = (text) {
    trace.add({'event': 'close', 'text': text});
    finish();
  };

  await runZoned(
    () async {
      try {
        await engine.start(KuaishouDanmakuArgs(liveStreamId: liveStreamId, cookie: cookie));
        trace.add({'start': 'returned'});
      } catch (error) {
        trace.add({'start': 'threw', 'error': error.runtimeType.toString()});
        finish();
      }
      await done.future;
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        trace.add({'delay': duration.inMilliseconds});
        return parent.createTimer(zone, Duration.zero, callback);
      },
    ),
  );
  await engine.stop();
  return trace;
}

Map<String, Object?> _project(LiveMessage message) {
  final data = message.data;
  return {
    'type': message.type.name,
    'userName': message.userName,
    'userId': message.userId,
    'message': message.message,
    'color': message.color.toString(),
    'messageId': message.messageId,
    'sentAt': message.sentAt?.millisecondsSinceEpoch,
    'userLevel': message.userLevel,
    'fansLevel': message.fansLevel,
    'fansName': message.fansName,
    'isLocal': message.isLocal,
    'data': data is LiveAudienceUpdate ? {'kind': data.kind.name, 'value': data.value} : data,
  };
}

void _write(String path, Object value) {
  File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  stdout.writeln('wrote $path');
}

// ---------------------------------------------------------------------------
// Stubs for what 3.x's KuaishouDanmaku imports.

/// 3.x's `CoreError` (legacy/lib/core/common/core_error.dart), which
/// `HttpClient` threw for every failed request.
class CoreError implements Exception {
  CoreError(this.message);
  final String message;

  @override
  String toString() => message;
}

class HttpClient {
  HttpClient._();
  static final HttpClient instance = HttpClient._();

  late Future<dynamic> Function(String url, Map<String, dynamic>? queryParameters, Map<String, dynamic>? header)
  handler;

  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) => handler(url, queryParameters, header);
}

class CancelToken {
  bool isCancelled = false;

  void cancel([Object? reason]) => isCancelled = true;

  static bool isCancel(DioException error) => false;
}

class DioException implements Exception {}

abstract final class CoreLog {
  static void e(String message, StackTrace stackTrace) => stderr.writeln('CoreLog.e: $message');
}

abstract class LiveDanmaku {
  Function(LiveMessage msg)? onMessage;
  Function(String msg)? onReconnect;
  Function(String msg)? onClose;
  Function()? onReady;
  int heartbeatTime = 0;
  bool get isConnected;
  void markConnected();
  void markDisconnected();
  void heartbeat() {}
  Future start(dynamic args);
  Future stop();
}

enum LiveMessageType { chat, gift, online, superChat }

enum LiveAudienceMetricKind { popularity, onlineViewers, totalViewers }

class LiveAudienceUpdate {
  const LiveAudienceUpdate({required this.kind, required this.value});

  final LiveAudienceMetricKind kind;
  final int value;
}

class LiveMessage {
  final LiveMessageType type;
  final String userName;
  final String userId;
  final String message;
  final dynamic data;
  final LiveMessageColor color;
  final String userLevel;
  final String fansLevel;
  final String fansName;
  final bool isLocal;
  final String messageId;
  final DateTime? sentAt;

  LiveMessage({
    required this.type,
    required this.userName,
    this.userId = "",
    required this.message,
    this.data,
    required this.color,
    this.userLevel = "",
    this.fansLevel = "",
    this.fansName = "",
    this.isLocal = false,
    this.messageId = "",
    this.sentAt,
  });
}

class LiveMessageColor {
  final int r, g, b;
  const LiveMessageColor(this.r, this.g, this.b);
  static LiveMessageColor get white => LiveMessageColor(255, 255, 255);

  @override
  String toString() {
    return "#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}";
  }
}

class LiveRoom {
  static int parseAudienceNumber(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return 0;
    final normalized = text.replaceAll(',', '').replaceAll('，', '');
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(亿|万|千|[kwm])?').firstMatch(normalized);
    final number = double.tryParse(match?.group(1) ?? '') ?? 0;
    final multiplier = switch (match?.group(2)) {
      '亿' => 100000000,
      '万' || 'w' => 10000,
      '千' || 'k' => 1000,
      'm' => 1000000,
      _ => 1,
    };
    return (number * multiplier).round();
  }
}

// ---------------------------------------------------------------------------
// 3.x: legacy/lib/core/danmaku/kuaishou_danmaku.dart, unchanged.

class KuaishouDanmakuArgs {
  const KuaishouDanmakuArgs({required this.liveStreamId, this.cookie = ''});

  final String liveStreamId;
  final String cookie;
}

typedef KuaishouFeedFetcher = Future<dynamic> Function(
  KuaishouDanmakuArgs args,
  String cursor,
  CancelToken cancelToken,
);

class KuaishouFeedBatch {
  const KuaishouFeedBatch({
    required this.cursor,
    required this.pullDelay,
    required this.messages,
    required this.onlineViewers,
  });

  final String cursor;
  final Duration pullDelay;
  final List<LiveMessage> messages;
  final int? onlineViewers;
}

/// Anonymous Kuaishou live-chat transport backed by the platform's mobile
/// incremental feed. The current desktop WebSocket bootstrap is guarded by a
/// signed browser request; the mobile feed exposes the same public comments,
/// cursor and concurrent audience count without keeping a hidden WebView alive.
///
/// Polls are one-shot and scheduled only after the previous request finishes,
/// preventing overlapping timers, duplicate cursors and background CPU growth.
class KuaishouDanmaku implements LiveDanmaku {
  KuaishouDanmaku({KuaishouFeedFetcher? fetcher, this.minimumPollDelay = const Duration(seconds: 1)})
    : _fetcher = fetcher ?? _fetchFeed;

  static const List<String> _feedUrls = <String>[
    'https://livev.m.chenzhongtech.com/wap/live/feed',
    'https://m.gifshow.com/wap/live/feed',
  ];
  static const int _maxReconnectAttempts = 8;

  final KuaishouFeedFetcher _fetcher;
  final Duration minimumPollDelay;

  @override
  int heartbeatTime = 0;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onReconnect;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  bool _connected = false;
  @override
  bool get isConnected => _connected;

  @override
  void markConnected() => _connected = true;

  @override
  void markDisconnected() => _connected = false;

  @override
  void heartbeat() {
    // The incremental HTTP feed is itself the liveness probe.
  }

  Timer? _pollTimer;
  CancelToken? _cancelToken;
  KuaishouDanmakuArgs? _args;
  String _cursor = '';
  int _generation = 0;
  int _reconnectAttempts = 0;

  @override
  Future<void> start(dynamic args) async {
    final typedArgs = args is KuaishouDanmakuArgs ? args : KuaishouDanmakuArgs(liveStreamId: args?.toString() ?? '');
    if (typedArgs.liveStreamId.trim().isEmpty) {
      throw const FormatException('Kuaishou live stream id is missing');
    }

    final generation = ++_generation;
    _pollTimer?.cancel();
    _pollTimer = null;
    _cancelToken?.cancel('Kuaishou room changed');
    _cancelToken = null;
    _args = typedArgs;
    _cursor = '';
    _reconnectAttempts = 0;
    markDisconnected();

    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: attempt == 1 ? 600 : 1400));
      }
      if (generation != _generation) return;
      try {
        await _pollOnce(generation, propagateFailure: true);
        if (generation != _generation) return;
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<void> _pollOnce(int generation, {bool scheduleNext = true, bool propagateFailure = false}) async {
    final args = _args;
    if (args == null || generation != _generation) return;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    try {
      final raw = await _fetcher(args, _cursor, cancelToken);
      if (generation != _generation || cancelToken.isCancelled) return;
      final batch = parseFeedPayload(raw);
      if (batch.cursor.isNotEmpty) _cursor = batch.cursor;
      _reconnectAttempts = 0;

      final wasConnected = isConnected;
      markConnected();
      if (!wasConnected) onReady?.call();

      final viewers = batch.onlineViewers;
      if (viewers != null) {
        onMessage?.call(
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
            color: LiveMessageColor.white,
          ),
        );
      }
      for (final message in batch.messages) {
        if (generation != _generation) return;
        onMessage?.call(message);
      }
      if (scheduleNext) _schedulePoll(generation, batch.pullDelay);
    } on DioException catch (error, stackTrace) {
      if (CancelToken.isCancel(error) || generation != _generation) return;
      if (propagateFailure) rethrow;
      _handlePollFailure(generation, error, stackTrace);
    } catch (error, stackTrace) {
      if (generation != _generation || cancelToken.isCancelled) return;
      if (propagateFailure) rethrow;
      _handlePollFailure(generation, error, stackTrace);
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  void _handlePollFailure(int generation, Object error, StackTrace stackTrace) {
    CoreLog.e(error.toString(), stackTrace);
    markDisconnected();
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      onClose?.call('服务器连接失败：快手弹幕重连超过最大次数');
      return;
    }
    if (_reconnectAttempts == 1) {
      onReconnect?.call('与服务器断开连接，正在尝试重连');
    }
    final seconds = 1 << (_reconnectAttempts - 1).clamp(0, 3);
    _schedulePoll(generation, Duration(seconds: seconds));
  }

  void _schedulePoll(int generation, Duration requestedDelay) {
    if (generation != _generation) return;
    _pollTimer?.cancel();
    final delay = requestedDelay < minimumPollDelay ? minimumPollDelay : requestedDelay;
    _pollTimer = Timer(delay, () {
      _pollTimer = null;
      if (generation == _generation) unawaited(_pollOnce(generation));
    });
  }

  @override
  Future<void> stop() async {
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _cancelToken?.cancel('Kuaishou danmaku stopped');
    _cancelToken = null;
    _args = null;
    _cursor = '';
    _reconnectAttempts = 0;
    markDisconnected();
    onMessage = null;
    onReconnect = null;
    onClose = null;
    onReady = null;
  }

  static Future<dynamic> _fetchFeed(KuaishouDanmakuArgs args, String cursor, CancelToken cancelToken) async {
    final headers = <String, dynamic>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/139.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Referer': 'https://livev.m.chenzhongtech.com/',
    };
    if (args.cookie.trim().isNotEmpty) headers['cookie'] = args.cookie.trim();
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final endpoint in _feedUrls) {
      try {
        return await HttpClient.instance.getJson(
          endpoint,
          queryParameters: <String, dynamic>{
            'liveStreamId': args.liveStreamId,
            if (cursor.isNotEmpty) 'cursor': cursor,
          },
          header: headers,
          cancel: cancelToken,
        );
      } catch (error, stackTrace) {
        if (cancelToken.isCancelled) rethrow;
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  static KuaishouFeedBatch parseFeedPayload(dynamic raw) {
    dynamic payload = raw;
    for (var depth = 0; depth < 3 && payload is String; depth++) {
      payload = jsonDecode(payload);
    }
    if (payload is Map && payload['data'] is Map) payload = payload['data'];
    if (payload is! Map) throw const FormatException('Kuaishou feed has an invalid shape');

    final result = _asInt(payload['result']);
    if (result != 1) {
      throw StateError('Kuaishou feed rejected the request (result: ${result ?? 'unknown'})');
    }
    final cursor = payload['cursor']?.toString() ?? '';
    final pullSeconds = (_asInt(payload['pullCycleSeconds']) ?? 3).clamp(1, 10);
    final watchingText = payload['currentWatchingCount']?.toString().trim() ?? '';
    final onlineViewers = watchingText.isEmpty ? null : LiveRoom.parseAudienceNumber(watchingText);
    final messages = <LiveMessage>[];

    final feeds = payload['liveStreamFeeds'];
    if (feeds is List) {
      for (final feed in feeds) {
        if (feed is! Map || feed['type']?.toString().toLowerCase() != 'comment') continue;
        final content = feed['content']?.toString().trim() ?? '';
        if (content.isEmpty) continue;
        final author = feed['author'] is Map ? feed['author'] as Map : const <dynamic, dynamic>{};
        final userName = author['userName']?.toString().trim() ?? '';
        final userId = author['userId']?.toString() ?? '';
        final timestamp = _asInt(feed['time']);
        final rawId = feed['id']?.toString().trim() ?? '';
        final digest = sha1.convert(utf8.encode('$timestamp\u0000$userId\u0000$content')).toString();
        messages.add(
          LiveMessage(
            type: LiveMessageType.chat,
            userName: userName.isEmpty ? '快手用户' : userName,
            userId: userId,
            message: content,
            messageId: 'kuaishou:${rawId.isEmpty ? digest : rawId}',
            sentAt: timestamp == null ? null : DateTime.fromMillisecondsSinceEpoch(timestamp),
            color: LiveMessageColor.white,
          ),
        );
      }
    }

    return KuaishouFeedBatch(
      cursor: cursor,
      pullDelay: Duration(seconds: pullSeconds),
      messages: List<LiveMessage>.unmodifiable(messages),
      onlineViewers: onlineViewers,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
