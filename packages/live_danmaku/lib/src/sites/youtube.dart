import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What a watch page's `next` answer says about the broadcast's chat
/// ([YouTubeDanmakuProtocol.watch]).
@immutable
final class YouTubeChatEntry {
  /// Creates the entry.
  const new({this.continuation, this.replay = false, this.viewers});

  /// The first continuation of the chat (its default "Top chat" view), or
  /// null when the answer names no chat.
  final String? continuation;

  /// Whether the chat is a replay (`isReplay`): the broadcast is over.
  final bool replay;

  /// Concurrent viewers ("1,250 watching now"), or null when the answer
  /// has no live count.
  final int? viewers;

  /// Whether the broadcast has a live chat to poll.
  bool get live => continuation != null && !replay;
}

/// One `live_chat/get_live_chat` answer ([YouTubeDanmakuProtocol.chat]).
@immutable
final class YouTubeChatPoll {
  /// Creates the answer.
  const new({this.messages = const [], this.continuation, this.reload = false, this.timeout, this.notice = ''});

  /// Chat lines, in order.
  final List<LiveMessage> messages;

  /// The continuation of the next request; null when the chat is over.
  final String? continuation;

  /// Whether [continuation] is a `reloadContinuationData`: its answer starts
  /// the chat over with the recent history, as the first answer does.
  final bool reload;

  /// The wait the server asks for (`timeoutMs`), or null.
  final Duration? timeout;

  /// When the chat is over: the site's message, such as "Chat is disabled
  /// for this live stream.", or empty.
  final String notice;

  /// Whether the chat is over: no continuation follows.
  bool get ended => continuation == null;
}

/// YouTube's live chat (docs/modules/M5.19-youtube.md), without I/O: the
/// archived v4's spec/sites/youtube.md §7. The web client's InnerTube calls,
/// anonymous, as the adapter makes them (`YouTubeApi.webContext`,
/// `YouTubeApi.apiHeaders`):
///
/// 1. `next` for the broadcast names the chat's first continuation (a
///    `reloadContinuationData`) and the live viewer count;
/// 2. `live_chat/get_live_chat` is polled with the continuation of the
///    previous answer. The first answer is the recent history; later answers
///    carry what was said since. Each answer names the next continuation
///    and the wait (`timeoutMs`); an answer without one ends the chat.
///
/// Text messages and paid messages (Super Chat, as a chat line prefixed with
/// the amount) are read; everything else (stickers, memberships, removals,
/// placeholders, polls, tickers) is not.
abstract final class YouTubeDanmakuProtocol {
  /// The watch page's `next`.
  static final Uri nextEndpoint = YouTubeApi.apiUrl('next');

  /// The chat's `live_chat/get_live_chat`.
  static final Uri chatEndpoint = YouTubeApi.apiUrl('live_chat/get_live_chat');

  /// Request headers: the adapter's for the web client's InnerTube calls (UA,
  /// JSON, English, `SOCS=CAI`, the site as Referer and Origin); the JSON
  /// content type comes with the request.
  static Map<String, String> get headers => YouTubeApi.apiHeaders;

  /// Longest wait for one answer (v4's request default).
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Shortest wait between two polls.
  static const Duration minimumDelay = Duration(seconds: 1);

  /// Longest wait between two polls, also when the server names none: the
  /// web client waits for pushed invalidations (`timeoutMs` 10 s) that a
  /// poller does not get, so polling sooner keeps the delay near the page's.
  static const Duration maximumDelay = Duration(seconds: 5);

  /// Wait after a failed request.
  static const Duration retryDelay = Duration(seconds: 2);

  /// Failed requests while joining (`next` and the first poll together)
  /// before the connection ends.
  static const int startAttempts = 3;

  /// Failed polls in a row, once joined, before the connection ends.
  static const int maxFailures = 8;

  /// The largest time `DateTime` holds, in microseconds from the epoch.
  static const int _maxMicros = 8640000000000000000;

  static final RegExp _digits = RegExp(r'^\d+$');

  /// The `next` request body for [videoId].
  static Map<String, Object?> nextBody(String videoId) => {'context': YouTubeApi.webContext, 'videoId': videoId};

  /// The `get_live_chat` request body for [continuation].
  static Map<String, Object?> chatBody(String continuation) => {
    'context': YouTubeApi.webContext,
    'continuation': continuation,
  };

  /// The wait before the next poll: [timeout] within [minimumDelay] and
  /// [maximumDelay], and [maximumDelay] when there is none.
  static Duration pollDelay(Duration? timeout) => switch (timeout) {
    null => maximumDelay,
    final wait when wait > maximumDelay => maximumDelay,
    final wait when wait < minimumDelay => minimumDelay,
    final wait => wait,
  };

  /// The concurrent viewers as a message.
  static LiveMessage audience(int viewers) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
    color: LiveMessageColor.white,
  );

  /// Reads a decoded `next` answer: the first `liveChatRenderer` in it (its
  /// `isReplay` and its first continuation) and the first live
  /// `videoViewCountRenderer` (the digits of "1,250 watching now", as the
  /// adapter reads them). Throws [FormatException] when [answer] is not a
  /// JSON object.
  static YouTubeChatEntry watch(Object? answer) {
    if (answer is! Map<String, Object?>) throw const FormatException('YouTube next: not a JSON object');
    Map<Object?, Object?>? chat;
    int? viewers;
    void walk(Object? node) {
      if (chat != null && viewers != null) return;
      if (node is Map) {
        if (node['liveChatRenderer'] case final Map<Object?, Object?> renderer when chat == null) chat = renderer;
        if (node['videoViewCountRenderer'] case final Map<Object?, Object?> count
            when viewers == null && count['isLive'] == true) {
          viewers = _viewers(count['viewCount']);
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(answer);
    final renderer = chat;
    return YouTubeChatEntry(
      continuation: renderer == null ? null : _continuation(renderer['continuations'])?.token,
      replay: renderer?['isReplay'] == true,
      viewers: viewers,
    );
  }

  static int? _viewers(Object? text) {
    final digits = _plain(text).replaceAll(RegExp('[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  /// Reads a decoded `get_live_chat` answer. Without
  /// `continuationContents.liveChatContinuation` the chat is over (the
  /// `contents` message, when there is one, is the notice). Throws
  /// [FormatException] when [answer] is not a JSON object.
  static YouTubeChatPoll chat(Object? answer) {
    if (answer is! Map<String, Object?>) throw const FormatException('YouTube get_live_chat: not a JSON object');
    final contents = answer['continuationContents'];
    final chat = contents is Map ? contents['liveChatContinuation'] : null;
    if (chat is! Map) {
      final message = answer['contents'];
      return YouTubeChatPoll(notice: message is Map ? _plain(_map(message['messageRenderer'])['text']) : '');
    }
    final actions = chat['actions'];
    final next = _continuation(chat['continuations']);
    return YouTubeChatPoll(
      messages: List.unmodifiable([
        if (actions is List)
          for (final action in actions) ?_message(action),
      ]),
      continuation: next?.token,
      reload: next?.kind == 'reloadContinuationData',
      timeout: next?.timeout,
    );
  }

  /// The first continuation of `continuations[0]`: its kind, token and
  /// `timeoutMs` (a whole number of zero or more).
  static ({String kind, String token, Duration? timeout})? _continuation(Object? continuations) {
    if (continuations is! List || continuations.isEmpty) return null;
    final first = continuations.first;
    if (first is! Map) return null;
    for (final MapEntry(:key, :value) in first.entries) {
      if (value case {'continuation': final String token}) {
        final timeout = value['timeoutMs'];
        return (
          kind: '$key',
          token: token,
          timeout: timeout is int && timeout >= 0 ? Duration(milliseconds: timeout) : null,
        );
      }
    }
    return null;
  }

  /// One action as a chat line: an added text message, or an added paid
  /// message with its amount before its text; null for anything else and
  /// for lines without text.
  static LiveMessage? _message(Object? action) {
    final add = action is Map ? action['addChatItemAction'] : null;
    final item = add is Map ? add['item'] : null;
    if (item is! Map) return null;
    final Map<Object?, Object?> renderer;
    final String text;
    if (item['liveChatTextMessageRenderer'] case final Map<Object?, Object?> message) {
      renderer = message;
      text = _runs(message['message']);
    } else if (item['liveChatPaidMessageRenderer'] case final Map<Object?, Object?> paid) {
      renderer = paid;
      text = '${_plain(paid['purchaseAmountText'])} ${_runs(paid['message'])}'.trim();
    } else {
      return null;
    }
    if (text.isEmpty) return null;
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _plain(renderer['authorName']),
      userId: _string(renderer['authorExternalChannelId']),
      message: text,
      messageId: _string(renderer['id']),
      sentAt: _time(renderer['timestampUsec']),
      color: LiveMessageColor.white,
    );
  }

  /// The text of a message's runs, trimmed: text runs as written; an emoji
  /// as the character it is (`emojiId`), a channel's custom emoji as its
  /// shortcut (`:name:`), which is what the page shows as its text.
  static String _runs(Object? message) {
    final runs = message is Map ? message['runs'] : null;
    if (runs is! List) return '';
    final out = StringBuffer();
    for (final run in runs) {
      if (run is! Map) continue;
      if (run['text'] case final String text) {
        out.write(text);
      } else if (run['emoji'] case final Map<Object?, Object?> emoji) {
        out.write(_emoji(emoji));
      }
    }
    return out.toString().trim();
  }

  static String _emoji(Map<Object?, Object?> emoji) {
    final shortcuts = emoji['shortcuts'];
    final shortcut = shortcuts is List && shortcuts.isNotEmpty ? _string(shortcuts.first) : '';
    if (emoji['isCustomEmoji'] == true) return shortcut;
    final id = _string(emoji['emojiId']);
    return id.isNotEmpty ? id : shortcut;
  }

  /// `{simpleText}` as written, or `{runs}` joined.
  static String _plain(Object? node) {
    if (node is! Map) return '';
    if (node['simpleText'] case final String text) return text;
    final runs = node['runs'];
    if (runs is! List) return '';
    return [
      for (final run in runs)
        if (run is Map && run['text'] is String) run['text']! as String,
    ].join();
  }

  static String _string(Object? value) => value is String ? value : '';

  static Map<Object?, Object?> _map(Object? value) => value is Map<Object?, Object?> ? value : const {};

  /// `timestampUsec` (decimal text or a whole number) as a time; null when
  /// it is not positive or out of `DateTime`'s range.
  static DateTime? _time(Object? value) {
    final micros = switch (value) {
      final int number => number,
      final String text when _digits.hasMatch(text.trim()) => int.tryParse(text.trim()),
      _ => null,
    };
    if (micros == null || micros <= 0 || micros > _maxMicros) return null;
    return DateTime.fromMicrosecondsSinceEpoch(micros);
  }
}

/// YouTube's danmaku connection: the live chat of the broadcast on air
/// (`YouTubeDanmakuArgs.videoId`), polled over [LiveHttp]; no socket, no
/// heartbeat.
///
/// - `connect` joins: `next` for the first continuation and the viewer count,
///   then the first poll, whose answer (the recent history) is not reported.
///   A failed request is tried again 2 s later; the third failure while
///   joining ends the run with [DanmakuCloseReason.connectionFailed], as
///   does a broadcast without a live chat (not live, chat off, a replay) or
///   an argument that is not a video id. Joined, it reports [DanmakuReady]
///   and then the viewers of `next`.
/// - Each poll waits for the previous one, then the wait the answer asked
///   for (`timeoutMs`, within 1–5 s, 5 s when none). An answer to a reload
///   continuation is history again and is not reported.
/// - A failed poll is tried again 2 s later with the same continuation; the
///   first failure in a row reports [DanmakuReconnecting], the eighth ends
///   with [DanmakuCloseReason.reconnectsExhausted], and an answer after
///   failures reports [DanmakuReady] again.
/// - An answer without a continuation ends with
///   [DanmakuCloseReason.connectionFailed] (the chat is over: the broadcast
///   ended); the room detail names the channel's next broadcast.
///
/// The app registers it as `SiteIds.youtube: () =>
/// YouTubeDanmakuConnection(http: …)`, with the `LiveHttp` it gives
/// `YouTubeSite` (the `youtube` proxy route and throttle).
final class YouTubeDanmakuConnection extends DanmakuConnectionBase<YouTubeDanmakuArgs> {
  /// Creates the connection; `http` sends the chat requests.
  new({required this._http});

  final LiveHttp _http;

  @override
  @protected
  Future<void> start(YouTubeDanmakuArgs args, DanmakuRun run) async {
    final videoId = args.videoId.trim();
    if (!YouTubeApi.isVideoId(videoId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No broadcast');
    }
    final chat = _YouTubeChat(_http, run);
    YouTubeChatEntry? entry;
    YouTubeChatPoll? history;
    for (var failures = 0; history == null;) {
      try {
        final watch = entry ??= YouTubeDanmakuProtocol.watch(
          await chat.post(YouTubeDanmakuProtocol.nextEndpoint, YouTubeDanmakuProtocol.nextBody(videoId)),
        );
        if (!run.isActive) return;
        if (!watch.live) {
          throw DanmakuStartFailure(
            DanmakuCloseReason.connectionFailed,
            detail: watch.replay ? 'Chat replay only' : 'No live chat',
          );
        }
        history = YouTubeDanmakuProtocol.chat(
          await chat.post(YouTubeDanmakuProtocol.chatEndpoint, YouTubeDanmakuProtocol.chatBody(watch.continuation!)),
        );
      } on DanmakuStartFailure {
        rethrow;
      } on Object catch (error) {
        if (!run.isActive) return;
        if (++failures >= YouTubeDanmakuProtocol.startAttempts) {
          throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: '$error');
        }
        if (!await run.delay(YouTubeDanmakuProtocol.retryDelay)) return;
      }
    }
    if (!run.isActive) return;
    if (history.ended) throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: _ended(history));
    run.ready();
    if (entry?.viewers case final viewers?) run.message(YouTubeDanmakuProtocol.audience(viewers));
    unawaited(chat.follow(history));
  }

  static String _ended(YouTubeChatPoll poll) => poll.notice.isEmpty ? 'Chat ended' : 'Chat ended: ${poll.notice}';
}

/// The chat of one run: its requests, cancelled when the run ends.
final class _YouTubeChat {
  new(this._http, this._run) {
    unawaited(_run.ended.then((_) => _cancel.cancel()));
  }

  final LiveHttp _http;
  final DanmakuRun _run;
  final CancelToken _cancel = CancelToken();

  /// Sends [body] to [url] and returns the answer decoded; throws
  /// `HttpStatusFailure`, `TransportFailure` or [FormatException].
  Future<Object?> post(Uri url, Map<String, Object?> body) => _http.postJson(
    SiteIds.youtube,
    url,
    json: body,
    headers: YouTubeDanmakuProtocol.headers,
    timeout: YouTubeDanmakuProtocol.requestTimeout,
    cancel: _cancel,
  );

  /// Polls after [previous] until the chat is over, the failures run out or
  /// the run ends.
  Future<void> follow(YouTubeChatPoll previous) async {
    var last = previous;
    var wait = YouTubeDanmakuProtocol.pollDelay(last.timeout);
    var failures = 0;
    while (await _run.delay(wait)) {
      final YouTubeChatPoll poll;
      try {
        poll = YouTubeDanmakuProtocol.chat(
          await post(YouTubeDanmakuProtocol.chatEndpoint, YouTubeDanmakuProtocol.chatBody(last.continuation!)),
        );
      } on Object catch (error) {
        if (!_run.isActive) return;
        if (++failures >= YouTubeDanmakuProtocol.maxFailures) {
          _run.closed(DanmakuCloseReason.reconnectsExhausted, detail: '$error');
          return;
        }
        if (failures == 1) _run.reconnecting(DanmakuInterruption.disconnected, detail: '$error');
        wait = YouTubeDanmakuProtocol.retryDelay;
        continue;
      }
      if (!_run.isActive) return;
      if (failures > 0) {
        failures = 0;
        _run.ready();
      }
      // The answer to a reload continuation starts over with the history.
      if (!last.reload) poll.messages.forEach(_run.message);
      if (poll.ended) {
        _run.closed(DanmakuCloseReason.connectionFailed, detail: YouTubeDanmakuConnection._ended(poll));
        return;
      }
      last = poll;
      wait = YouTubeDanmakuProtocol.pollDelay(poll.timeout);
    }
  }
}
