import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// The chat log of one broadcast, as `getchatinfo` names it.
@immutable
final class SteamBroadcastChat {
  /// Creates the chat; [template] holds `{0}` where a window's time goes.
  const new({required this.broadcastId, required this.template});

  /// The broadcast whose chat this is (`getbroadcastmpd`'s `broadcastid`).
  final String broadcastId;

  /// `view_url_template`: `https://steambroadcastchat.akamaized.net/chat/<chat id>/messages/{0}?chat_origin=…`.
  final String template;

  /// The address of the window at [time] (the chat log's clock, in
  /// milliseconds; 0 asks for the latest history). Like Steam's web client,
  /// only the first `{0}` is replaced.
  Uri window(int time) => Uri.parse(template.replaceFirst('{0}', '$time'));

  @override
  bool operator ==(Object other) =>
      other is SteamBroadcastChat && other.broadcastId == broadcastId && other.template == template;

  @override
  int get hashCode => Object.hash(broadcastId, template);

  @override
  String toString() => 'SteamBroadcastChat($broadcastId, $template)';
}

/// One answer of the chat log: a window's chat lines and the next window.
@immutable
final class SteamBroadcastChatWindow {
  /// Creates the answer.
  new({required this.next, required Iterable<LiveMessage> messages, this.initialDelay})
    : messages = List.unmodifiable(messages);

  /// `next_request`: the time of the next window.
  final int next;

  /// `initial_delay`: how long to wait before asking for [next], given with
  /// window 0 (and whenever Steam wants the reader to set its clock again);
  /// null when absent.
  final Duration? initialDelay;

  /// The chat lines (`messages`), in order.
  final List<LiveMessage> messages;
}

/// When to ask for the next window of the chat log, as Steam's web client
/// (`broadcast_chat.js`) times it: an answer that sets the clock (window 0,
/// or one with `initial_delay`) makes its `next_request` due `initial_delay`
/// from now; every later window is due as much later as its time is past
/// that window's, plus a nudge that grows by 10 ms with every failed window
/// (up to 1 s). A reader that fell behind asks at once until it caught up.
///
/// Times are the connection's monotonic clock; waits are clamped to 0–60 s.
final class SteamBroadcastChatClock {
  /// Creates a clock that is not set: the next window asked is 0.
  new();

  int? _firstAt;
  int _first = 0;
  int _next = 0;
  int _nudge = 0;

  /// Whether an answer set the clock (since the last [resync]).
  bool get isSynced => _firstAt != null;

  /// The time of the window to ask for next: 0 until the clock is set.
  int get window => _firstAt == null ? 0 : _next;

  /// What is added to every wait: 10 ms per failed window so far.
  Duration get nudge => Duration(milliseconds: _nudge);

  /// Sets the clock from an answer: window [next] is due [initialDelay]
  /// from [now]. Returns the wait.
  Duration sync(int next, Duration initialDelay, Duration now) {
    final delay = _clamp(initialDelay.inMilliseconds);
    _firstAt = now.inMilliseconds + delay;
    _first = next;
    _next = next;
    return Duration(milliseconds: delay);
  }

  /// The next window is [next]: returns the wait until it is due at [now].
  Duration advance(int next, Duration now) {
    final firstAt = _firstAt;
    if (firstAt == null) return sync(next, Duration.zero, now);
    _next = next;
    return Duration(milliseconds: _clamp(firstAt + (next - _first) + _nudge - now.inMilliseconds));
  }

  /// A window request failed: later windows are asked 10 ms later.
  void miss() {
    final step = SteamBroadcastDanmakuProtocol.nudgeStep.inMilliseconds;
    final most = SteamBroadcastDanmakuProtocol.maxNudge.inMilliseconds;
    _nudge = _nudge + step > most ? most : _nudge + step;
  }

  /// Starts over from window 0 (the nudge stays, as in the web client).
  void resync() {
    _firstAt = null;
    _first = 0;
    _next = 0;
  }

  static int _clamp(int milliseconds) => milliseconds.clamp(0, SteamBroadcastDanmakuProtocol.maxWait.inMilliseconds);
}

/// Steam broadcast chat (docs/T06/T06a/T06a.24/record.md), without I/O:
/// read-only and anonymous, as the watch page reads it (`broadcast_chat.js`).
///
/// - `getbroadcastmpd` names the current broadcast (`broadcastid`); room
///   entry already asked it, so the arguments usually carry the id;
/// - `getchatinfo` of that broadcast gives the chat log's address template
///   ([chat]); Steam answers HTTP 500 (`success: 2`) for any other id;
/// - the chat log is read window by window along its own clock
///   ([SteamBroadcastChatClock]): window 0 is the latest history (not
///   reported), each answer names the next window.
///
/// Chat lines (`msg`, `persona_name`, `steamid`) become white chat
/// messages; `getbroadcastmpd`'s `num_viewers` an audience update. The
/// chat log has no ids, times, paid messages or viewer counts; `joined`,
/// `left`, `muted` and `remove_msgs` are not reported.
abstract final class SteamBroadcastDanmakuProtocol {
  /// Longest wait for one answer (the archived v4's).
  static const Duration requestTimeout = Duration(seconds: 10);

  /// Wait after a failure (the web client's `s_MessageRetryDelay`).
  static const Duration retryDelay = Duration(milliseconds: 500);

  /// Failures in a row after which the chat log is read from window 0 again
  /// (the web client's `s_MessageRetryMax`); the connection reports
  /// [DanmakuReconnecting] then.
  static const int resyncAfter = 4;

  /// Failures in a row after which the chat is looked up again:
  /// `getbroadcastmpd` (a new broadcast gets a new id), `getchatinfo`, window
  /// 0. From then on the waits grow 1, 2, 4, 8 s.
  static const int lookUpAfter = 8;

  /// Failures in a row that are retried; the next one ends the connection.
  static const int maxFailures = 15;

  /// What every failed window adds to later waits (the web client's
  /// `s_MessageNudgeDelayMS`).
  static const Duration nudgeStep = Duration(milliseconds: 10);

  /// The most the nudge grows to (the web client has no bound).
  static const Duration maxNudge = Duration(seconds: 1);

  /// The longest wait for a window: a window is served for about 70 s.
  static const Duration maxWait = Duration(seconds: 60);

  /// The wait after the [failures]-th failure in a row: 500 ms, then from
  /// [lookUpAfter] on 1, 2, 4, 8, 8… s.
  static Duration wait(int failures) =>
      failures < lookUpAfter ? retryDelay : Duration(seconds: 1 << (failures - lookUpAfter).clamp(0, 3));

  /// The request headers of `getbroadcastmpd` and `getchatinfo`: the
  /// adapter's (3.x's JSON headers with the watch page as referer).
  static Map<String, String> headers(String steamId) => SteamBroadcastApi.roomHeaders(steamId, json: true);

  /// The request headers of the chat log: what the watch page's cross-origin
  /// request carries (jQuery's JSON `accept`, the page's origin and referer).
  static Map<String, String> chatHeaders(String steamId) => {
    'user-agent': SteamBroadcastApi.userAgent,
    'accept': 'application/json, text/javascript, */*; q=0.01',
    'accept-language': 'en-US,en;q=0.9',
    'origin': SteamBroadcastApi.origin,
    'referer': SteamBroadcastApi.link(steamId),
  };

  /// `getchatinfo` of [broadcastId], the broadcast of [steamId].
  static Uri chatInfoUrl(String steamId, String broadcastId) => Uri.https(
    'steamcommunity.com',
    '/broadcast/getchatinfo/',
    {'steamid': steamId, 'broadcastid': broadcastId, 'viewertoken': '0', 'sessionid': ''},
  );

  /// A request for [url] with [headers], sent as `steambroadcast` (its proxy
  /// route), without following redirects.
  static LiveRequest request(Uri url, Map<String, String> headers, {CancelToken? cancel}) => LiveRequest(
    site: SiteIds.steamBroadcast,
    url: url,
    headers: headers,
    followRedirects: false,
    timeout: requestTimeout,
    cancel: cancel,
  );

  static final RegExp _broadcastId = RegExp(r'^[1-9][0-9]{0,19}$');

  /// [value] trimmed when it is a broadcast id (digits, not 0), else null.
  static String? broadcastIdOf(String? value) {
    final id = value?.trim() ?? '';
    return _broadcastId.hasMatch(id) ? id : null;
  }

  static final RegExp _chatCdn = RegExp(r'^steambroadcast[a-z0-9-]*\.akamaized\.net$');

  static const List<String> _steamDomains = [
    'steamcommunity.com',
    'steamcontent.com',
    'steamserver.net',
    'steamstatic.com',
  ];

  /// Whether [uri] may be read as a chat log: https, no user info, fragment
  /// or port other than 443, on Steam's chat CDN
  /// (`steambroadcastchat.akamaized.net`) or a Steam domain.
  static bool isChatLog(Uri uri) {
    if (!uri.isScheme('https') || uri.userInfo.isNotEmpty || uri.hasFragment) return false;
    if (uri.hasPort && uri.port != 443) return false;
    final host = uri.host.toLowerCase();
    return _chatCdn.hasMatch(host) || _steamDomains.any((domain) => host == domain || host.endsWith('.$domain'));
  }

  /// `getchatinfo` of [broadcastId]: `success: 1` and a `view_url_template`
  /// holding `{0}` whose address is a chat log ([isChatLog]). Throws a
  /// `SiteError`: for the status (Steam answers 500 for an id that is not
  /// the current broadcast), [ApiChanged] for the shape.
  static SteamBroadcastChat chat(String body, {required String broadcastId, int status = 200}) {
    const what = 'getchatinfo';
    final json = _object(body, status, what);
    final success = json['success'];
    if (success != 1 && success != '1') throw ApiChanged(SiteIds.steamBroadcast, '$what: success $success');
    final template = json['view_url_template'];
    if (template is! String || !template.contains('{0}')) {
      throw const ApiChanged(SiteIds.steamBroadcast, '$what: no view_url_template with {0}');
    }
    final first = Uri.tryParse(template.replaceFirst('{0}', '0'));
    if (first == null || !isChatLog(first)) {
      throw ApiChanged(SiteIds.steamBroadcast, '$what: unexpected chat log ${first?.origin ?? template}');
    }
    return SteamBroadcastChat(broadcastId: broadcastId, template: template);
  }

  /// The answer for the window at [time]: `next_request` (a positive
  /// integer, past [time] after window 0), `initial_delay` (null when
  /// absent or negative) and the chat lines of `messages` ([message]).
  /// Throws a `SiteError`: for the status (a window not served, too early or
  /// too late, is 404), [ApiChanged] for the shape.
  static SteamBroadcastChatWindow window(String body, {required int time, int status = 200}) {
    final what = 'chat window $time';
    final json = _object(body, status, what);
    final next = _integer(json['next_request']);
    if (next == null || next <= 0 || (time > 0 && next <= time)) {
      throw ApiChanged(SiteIds.steamBroadcast, '$what: next_request ${json['next_request']}');
    }
    final delay = _integer(json['initial_delay']);
    final messages = json['messages'];
    return SteamBroadcastChatWindow(
      next: next,
      initialDelay: delay == null || delay < 0 ? null : Duration(milliseconds: delay),
      messages: [
        if (messages is List<Object?>)
          for (final entry in messages) ?message(entry),
      ],
    );
  }

  /// One entry of `messages` as a white chat message: the text is `msg`
  /// trimmed (Steam emoticons stay as written, `ːnameː`), the name
  /// `persona_name` trimmed ('' when absent), the user id `steamid`. Null
  /// when it is not an object or has no text. Steam gives no id and no
  /// time.
  static LiveMessage? message(Object? entry) {
    if (entry is! Map<Object?, Object?>) return null;
    final text = entry['msg'];
    if (text is! String || text.trim().isEmpty) return null;
    final name = entry['persona_name'];
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: name is String ? name.trim() : '',
      userId: switch (entry['steamid']) {
        final String id => id.trim(),
        final int id => '$id',
        _ => '',
      },
      message: text.trim(),
      color: LiveMessageColor.white,
    );
  }

  /// `getbroadcastmpd`'s concurrent viewers as a message.
  static LiveMessage audience(int viewers) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
    color: LiveMessageColor.white,
  );

  static final RegExp _digits = RegExp(r'^[0-9]{1,15}$');

  static int? _integer(Object? value) => switch (value) {
    final int number => number,
    final String text when _digits.hasMatch(text) => int.parse(text),
    _ => null,
  };

  static Map<Object?, Object?> _object(String body, int status, String what) {
    if (status != 200) {
      final trimmed = body.trim();
      final shown = trimmed.startsWith('{') && trimmed.length <= 64 ? ' $trimmed' : '';
      final detail = '$what: HTTP $status$shown';
      throw switch (status) {
        401 || 403 => RiskControl(SiteIds.steamBroadcast, detail: detail),
        404 => NotFound(SiteIds.steamBroadcast, detail),
        429 => RateLimited(SiteIds.steamBroadcast, detail: detail),
        _ => NetworkFailure(SiteIds.steamBroadcast, detail),
      };
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(SiteIds.steamBroadcast, '$what: not JSON');
    }
    if (decoded is! Map<Object?, Object?>) throw ApiChanged(SiteIds.steamBroadcast, '$what: not an object');
    return decoded;
  }
}

/// Steam broadcast chat (new in v4; 3.x had `EmptyDanmaku`, upgrade 27-6):
/// HTTP polling of the chat log ([SteamBroadcastDanmakuProtocol]), read
/// only and anonymously, no socket and no heartbeat.
///
/// - Start: the arguments' broadcast id (room entry's `getbroadcastmpd`),
///   else `getbroadcastmpd` now; then `getchatinfo` and window 0. Window 0
///   joins ([DanmakuReady]); its history is not reported. An offline
///   broadcaster, one whose account may not broadcast, or a broadcast for
///   subscribers only ends with [DanmakuCloseReason.connectionFailed].
/// - Then each window when the chat log's clock says it is due
///   ([SteamBroadcastChatClock]), its chat lines reported in order.
/// - A failure is retried after 500 ms; the 4th in a row reports
///   [DanmakuReconnecting] and reads from window 0 again, joining again when
///   it answers; from the 8th the chat is looked up again (a new
///   `getbroadcastmpd`, so a broadcaster's next broadcast is followed, and
///   an offline one ends the connection) after 1, 2, 4, 8… s; the 16th ends
///   with [DanmakuCloseReason.reconnectsExhausted]. Any answer resets the
///   count.
/// - A `getchatinfo` failure forgets the broadcast id, so the next attempt
///   asks `getbroadcastmpd` (Steam refuses an id that is no longer the
///   broadcaster's current one).
/// - `getbroadcastmpd`'s `num_viewers` is reported whenever it is asked.
///
/// The app registers it as `SiteIds.steamBroadcast: () =>
/// SteamBroadcastDanmakuConnection(http: …)`, with the `LiveHttp` it gives
/// `SteamBroadcastSite` (the `steambroadcast` proxy route and throttle).
final class SteamBroadcastDanmakuConnection extends DanmakuConnectionBase<SteamBroadcastDanmakuArgs> {
  /// Creates the connection; `http` sends the requests. [elapsed] is the
  /// monotonic clock the chat log is followed by (a stopwatch started now;
  /// tests pass their own).
  new({required this._http, Duration Function()? elapsed}) : _elapsed = elapsed ?? _stopwatch();

  final LiveHttp _http;
  final Duration Function() _elapsed;
  _SteamChat? _chat;

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  @override
  @protected
  Future<void> start(SteamBroadcastDanmakuArgs args, DanmakuRun run) async {
    final steamId = args.steamId.trim();
    if (!SteamBroadcastApi.isSteamId(steamId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'Not a Steam id');
    }
    final chat = _chat = _SteamChat(
      this,
      run,
      steamId: steamId,
      broadcastId: SteamBroadcastDanmakuProtocol.broadcastIdOf(args.broadcastId),
    );
    await chat.start();
  }

  @override
  @protected
  Future<void> stop() async {
    final chat = _chat;
    _chat = null;
    chat?.close();
  }
}

/// The broadcaster cannot be watched now; retrying does not help.
final class _Unwatchable implements Exception {
  const new(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The chat of one run: its broadcast, chat log and clock, and the
/// requests, cancelled when the run ends.
final class _SteamChat {
  new(this._owner, this._run, {required this._steamId, required this._broadcastId}) {
    unawaited(_run.ended.then((_) => _cancel.cancel()));
  }

  final SteamBroadcastDanmakuConnection _owner;
  final DanmakuRun _run;
  final String _steamId;
  final SteamBroadcastChatClock _clock = SteamBroadcastChatClock();
  final CancelToken _cancel = CancelToken();
  final Completer<void> _firstAttempt = Completer();
  String? _broadcastId;
  SteamBroadcastChat? _chat;
  int _failures = 0;

  /// Starts following; completes once the first attempt joined, reported
  /// trouble or ended.
  Future<void> start() {
    unawaited(_follow());
    return _firstAttempt.future;
  }

  /// Cancels the requests.
  void close() => _cancel.cancel();

  void _settle() {
    if (!_firstAttempt.isCompleted) _firstAttempt.complete();
  }

  /// One step after another until the run ends.
  Future<void> _follow() async {
    try {
      var wait = Duration.zero;
      while (await _run.delay(wait)) {
        try {
          wait = await _step();
        } on _Unwatchable catch (error) {
          _run.closed(DanmakuCloseReason.connectionFailed, detail: error.reason);
          return;
        } on Object catch (error) {
          if (!_run.isActive) return;
          final next = _failed(error);
          if (next == null) return;
          wait = next;
        }
      }
    } finally {
      _settle();
    }
  }

  /// Reads the window that is due (looking the chat up first when there is
  /// none) and returns the wait before the next one.
  Future<Duration> _step() async {
    final chat = _chat ??= await _lookUp();
    final time = _clock.window;
    final SteamBroadcastChatWindow answer;
    try {
      final response = await _get(chat.window(time), SteamBroadcastDanmakuProtocol.chatHeaders(_steamId));
      answer = SteamBroadcastDanmakuProtocol.window(response.text, time: time, status: response.status);
    } on Object {
      _clock.miss();
      rethrow;
    }
    if (!_run.isActive) return Duration.zero;
    _failures = 0;
    if (!_run.isConnected) _run.ready();
    _settle();
    final now = _owner._elapsed();
    // Window 0 is the latest history: it only sets the clock.
    if (time == 0) return _clock.sync(answer.next, answer.initialDelay ?? Duration.zero, now);
    answer.messages.forEach(_run.message);
    return switch (answer.initialDelay) {
      final delay? when delay > Duration.zero => _clock.sync(answer.next, delay, now),
      _ => _clock.advance(answer.next, now),
    };
  }

  /// The chat log of the current broadcast: `getchatinfo` of the known
  /// broadcast id, else of the one `getbroadcastmpd` names now.
  Future<SteamBroadcastChat> _lookUp() async {
    final broadcastId = _broadcastId ?? await _currentBroadcast();
    try {
      final response = await _get(
        SteamBroadcastDanmakuProtocol.chatInfoUrl(_steamId, broadcastId),
        SteamBroadcastDanmakuProtocol.headers(_steamId),
      );
      final chat = SteamBroadcastDanmakuProtocol.chat(response.text, broadcastId: broadcastId, status: response.status);
      _clock.resync();
      return chat;
    } on Object {
      // Steam refuses an id that is not the current broadcast: the next
      // look-up asks getbroadcastmpd.
      _broadcastId = null;
      rethrow;
    }
  }

  /// The id of the broadcaster's current broadcast (`getbroadcastmpd`),
  /// reporting its viewers. Offline, a restricted account or a broadcast
  /// for subscribers only is [_Unwatchable]; no id otherwise is a failure
  /// (waiting for the broadcast, say).
  Future<String> _currentBroadcast() async {
    final response = await _get(SteamBroadcastApi.mpdUrl(_steamId), SteamBroadcastDanmakuProtocol.headers(_steamId));
    final broadcast = SteamBroadcastApi.broadcast(response.text, steamId: _steamId, status: response.status);
    if (broadcast.viewers case final viewers?) _run.message(SteamBroadcastDanmakuProtocol.audience(viewers));
    if (broadcast.state == SteamBroadcastState.offline) throw const _Unwatchable('Offline');
    if (broadcast.state == SteamBroadcastState.accountRestricted) {
      throw const _Unwatchable('The account may not broadcast');
    }
    final id = broadcast.broadcastId;
    if (id == null) {
      if (broadcast.restriction == LiveRestriction.subscribersOnly) throw const _Unwatchable('Subscribers only');
      throw StreamUnavailable(SiteIds.steamBroadcast, 'getbroadcastmpd: no broadcast id (${broadcast.state.name})');
    }
    return _broadcastId = id;
  }

  /// Counts a failure: ends the run after too many in a row, reports the
  /// 4th and reads from window 0 again, looks the chat up again from the
  /// 8th. Returns the wait, or null when the run ended.
  Duration? _failed(Object error) {
    final detail = '$error';
    _failures++;
    if (_failures > SteamBroadcastDanmakuProtocol.maxFailures) {
      _run.closed(DanmakuCloseReason.reconnectsExhausted, detail: detail);
      return null;
    }
    if (_failures == SteamBroadcastDanmakuProtocol.resyncAfter) {
      _clock.resync();
      _run.reconnecting(DanmakuInterruption.disconnected, detail: detail);
      _settle();
    }
    if (_failures >= SteamBroadcastDanmakuProtocol.lookUpAfter) {
      _chat = null;
      _broadcastId = null;
    }
    return SteamBroadcastDanmakuProtocol.wait(_failures);
  }

  /// Sends a GET; nothing is sent once the run ended.
  Future<LiveResponse> _get(Uri url, Map<String, String> headers) async {
    if (_cancel.isCancelled) throw const TransportFailure(SiteIds.steamBroadcast, TransportReason.cancelled);
    return await _owner._http.send(SteamBroadcastDanmakuProtocol.request(url, headers, cancel: _cancel));
  }
}
