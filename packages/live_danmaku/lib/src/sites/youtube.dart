import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// One parsed `get_live_chat` answer.
@immutable
final class YouTubeChatPoll {
  /// Creates a poll result.
  const new({required this.events, this.continuation, this.delay});

  /// Chat lines in order.
  final List<DanmakuEvent> events;

  /// The next continuation; null when the chat ended.
  final String? continuation;

  /// How long the server asks to wait (`timeoutMs`).
  final Duration? delay;
}

/// YouTube live chat (spec/sites/youtube.md §7), without I/O: the watch
/// page's `next` answer names the chat's first continuation, and
/// `live_chat/get_live_chat` is polled with the continuation of the
/// previous answer.
abstract final class YouTubeChatProtocol {
  /// Request headers (as for the adapter's InnerTube calls).
  static const headers = {
    'content-type': 'application/json',
    'origin': 'https://www.youtube.com',
    'cookie': 'SOCS=CAI',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  };

  /// An InnerTube endpoint.
  static Uri endpoint(String name) => Uri.parse('https://www.youtube.com/youtubei/v1/$name?prettyPrint=false');

  /// The `next` request body for [videoId].
  static List<int> nextBody(String videoId) =>
      utf8.encode(jsonEncode({'context': YouTubeParse.webContext, 'videoId': videoId}));

  /// The `get_live_chat` request body.
  static List<int> chatBody(String continuation) =>
      utf8.encode(jsonEncode({'context': YouTubeParse.webContext, 'continuation': continuation}));

  static Object? _decode(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw FormatException('$what: not JSON');
    }
  }

  static Iterable<Object?> _find(Object? node, String key) sync* {
    if (node is Map) {
      if (node.containsKey(key)) yield node[key];
      for (final value in node.values) {
        yield* _find(value, key);
      }
    } else if (node is List) {
      for (final value in node) {
        yield* _find(value, key);
      }
    }
  }

  static String? _continuation(Object? continuations) {
    if (continuations is! List || continuations.isEmpty) return null;
    final first = continuations.first;
    if (first is! Map) return null;
    for (final data in first.values) {
      if (data is Map && data['continuation'] is String) return data['continuation'] as String;
    }
    return null;
  }

  /// The chat's first continuation from a `next` answer, or null when the
  /// video has no live chat (not live, or chat turned off).
  static String? initialContinuation(String body) {
    for (final chat in _find(_decode(body, 'next'), 'liveChatRenderer')) {
      if (chat is Map) return _continuation(chat['continuations']);
    }
    return null;
  }

  static String _text(Object? message) {
    final runs = message is Map ? message['runs'] : null;
    if (runs is! List) return '';
    final out = StringBuffer();
    for (final run in runs.whereType<Map<Object?, Object?>>()) {
      final text = run['text'];
      if (text is String) {
        out.write(text);
        continue;
      }
      final emoji = run['emoji'];
      if (emoji is Map) {
        final shortcuts = emoji['shortcuts'];
        out.write(shortcuts is List && shortcuts.isNotEmpty ? '${shortcuts.first}' : '${emoji['emojiId'] ?? ''}');
      }
    }
    return out.toString().trim();
  }

  static String _simple(Object? node) =>
      node is Map && node['simpleText'] is String ? node['simpleText'] as String : '';

  /// Parses one `get_live_chat` answer: text messages, and paid messages
  /// as chat lines prefixed with their amount (§7).
  static YouTubeChatPoll parse(String body, {required DecodeContext context}) {
    final root = _decode(body, 'get_live_chat');
    final chat = root is Map && root['continuationContents'] is Map
        ? (root['continuationContents'] as Map)['liveChatContinuation']
        : null;
    if (chat is! Map) return const YouTubeChatPoll(events: []);
    final events = <DanmakuEvent>[];
    final actions = chat['actions'];
    for (final action in actions is List ? actions : const <Object?>[]) {
      final add = action is Map ? action['addChatItemAction'] : null;
      final item = add is Map ? add['item'] : null;
      if (item is! Map) continue;
      final Map<Object?, Object?> renderer;
      var text = '';
      if (item['liveChatTextMessageRenderer'] case final Map<Object?, Object?> message) {
        renderer = message;
        text = _text(message['message']);
      } else if (item['liveChatPaidMessageRenderer'] case final Map<Object?, Object?> paid) {
        renderer = paid;
        text = '${_simple(paid['purchaseAmountText'])} ${_text(paid['message'])}'.trim();
      } else {
        continue;
      }
      if (text.isEmpty) continue;
      final id = renderer['id'];
      final micros = int.tryParse('${renderer['timestampUsec'] ?? ''}');
      events.add(
        DanmakuChat(
          room: context.room,
          session: context.session,
          receivedAt: context.receivedAt,
          id: id is String && id.isNotEmpty ? 'youtube:$id' : null,
          sentAt: micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
          userId: '${renderer['authorExternalChannelId'] ?? ''}',
          userName: _simple(renderer['authorName']),
          text: text,
        ),
      );
    }
    final continuations = chat['continuations'];
    Duration? delay;
    if (continuations is List && continuations.isNotEmpty && continuations.first is Map) {
      for (final data in (continuations.first as Map).values) {
        final ms = data is Map ? data['timeoutMs'] : null;
        if (ms is int && ms >= 0) delay = Duration(milliseconds: ms);
      }
    }
    return YouTubeChatPoll(events: events, continuation: _continuation(continuations), delay: delay);
  }
}

/// YouTube live chat by polling: the first answer is the recent history
/// (not emitted); later answers are emitted. The wait follows the server's
/// `timeoutMs`, capped at [maximumDelay] (the web client is pushed new
/// messages; polling sooner keeps the delay close to it). After
/// [maxFailures] consecutive failures it gives up; an answer without a
/// continuation means the chat ended.
final class YouTubeChatConnector extends ConnectorBase {
  /// Creates the connector; [detail]'s `danmakuKeys['videoId']` is the broadcast.
  new({required super.detail, required super.transport, super.session, super.clock});

  /// Consecutive failures before the terminal state.
  static const maxFailures = 8;

  /// Longest wait between two polls.
  static const maximumDelay = Duration(seconds: 5);

  /// Shortest wait between two polls.
  static const minimumDelay = Duration(seconds: 1);

  /// Wait after a failed request.
  static const retryDelay = Duration(seconds: 2);

  @override
  Future<void> run(int generation) async {
    final video = detail.danmakuKeys['videoId'] ?? '';
    if (video.isEmpty) {
      terminal(generation, 'offline', 'no live video');
      return;
    }
    status(generation, DanmakuStatus.connecting);
    String? continuation;
    try {
      continuation = YouTubeChatProtocol.initialContinuation(await _post('next', YouTubeChatProtocol.nextBody(video)));
    } on Object catch (error) {
      if (!isStale(generation)) terminal(generation, 'failed', '$error');
      return;
    }
    if (continuation == null) {
      terminal(generation, 'offline', 'no live chat');
      return;
    }
    var failures = 0;
    var joinedOnce = false;
    var delay = Duration.zero;
    while (await pause(generation, delay)) {
      try {
        final poll = YouTubeChatProtocol.parse(
          await _post('live_chat/get_live_chat', YouTubeChatProtocol.chatBody(continuation!)),
          context: context(),
        );
        if (isStale(generation)) return;
        if (failures > 0 && joinedOnce) status(generation, DanmakuStatus.connected);
        failures = 0;
        if (!joinedOnce) {
          // The first answer is the recent history.
          joinedOnce = true;
          status(generation, DanmakuStatus.connected);
          joined(generation);
        } else {
          for (final event in poll.events) {
            emit(generation, event);
          }
        }
        final next = poll.continuation;
        if (next == null) {
          terminal(generation, 'offline', 'chat ended');
          return;
        }
        continuation = next;
        final wait = poll.delay ?? maximumDelay;
        delay = wait > maximumDelay ? maximumDelay : (wait < minimumDelay ? minimumDelay : wait);
      } on Object catch (error) {
        if (isStale(generation)) return;
        failures++;
        if (!joinedOnce && failures > 2) {
          terminal(generation, 'failed', '$error');
          return;
        }
        if (failures == 1) status(generation, DanmakuStatus.reconnecting);
        if (failures >= maxFailures) {
          terminal(generation, 'maxRetries');
          return;
        }
        delay = retryDelay;
      }
    }
  }

  Future<String> _post(String endpoint, List<int> body) async {
    final cancel = CancelToken();
    final removeStop = onStop(cancel.cancel);
    try {
      final response = await transport.http.send(
        LiveRequest(
          site: 'youtube',
          method: 'POST',
          url: YouTubeChatProtocol.endpoint(endpoint),
          headers: YouTubeChatProtocol.headers,
          body: body,
          cancel: cancel,
        ),
      );
      if (!response.isSuccess) throw FormatException('HTTP ${response.status} $endpoint');
      return response.text;
    } finally {
      removeStop();
    }
  }
}
