import 'dart:async';
import 'dart:convert';

import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// One parsed chat poll.
@immutable
final class SteamChatPoll {
  /// Creates a poll result.
  const new({required this.next, required this.events, this.initialDelay});

  /// Chat-log time (ms) of the next window (`next_request`).
  final int next;

  /// Only on a first poll: how long to wait before requesting [next].
  final Duration? initialDelay;

  /// Chat lines in order.
  final List<DanmakuEvent> events;
}

/// Steam broadcast chat (spec/sites/steambroadcast.md §7), without I/O:
/// `getbroadcastmpd` gives the broadcast id, `getchatinfo` a URL template,
/// and the template is read window by window along the chat log's clock.
abstract final class SteamBroadcastProtocol {
  /// Request headers for the community endpoints of [steamId].
  static Map<String, String> headers(String steamId) => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/140.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/javascript, */*; q=0.8',
    'Referer': 'https://steamcommunity.com/broadcast/watch/$steamId',
    'X-Requested-With': 'XMLHttpRequest',
  };

  /// The broadcast manifest request, which names the current broadcast.
  static Uri broadcastUrl(String steamId) => Uri.https('steamcommunity.com', '/broadcast/getbroadcastmpd/', {
    'broadcastid': '0',
    'steamid': steamId,
    'viewertoken': '0',
    'sessionid': '',
  });

  /// The chat info request for [broadcastId].
  static Uri chatInfoUrl(String steamId, String broadcastId) => Uri.https(
    'steamcommunity.com',
    '/broadcast/getchatinfo/',
    {'steamid': steamId, 'broadcastid': broadcastId, 'viewertoken': '0', 'sessionid': ''},
  );

  static Map<String, dynamic> _object(String body, String what) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw FormatException('$what: not an object');
    return decoded;
  }

  /// `getbroadcastmpd` → the broadcast id, or null when not broadcasting.
  static String? broadcastId(String body) {
    final json = _object(body, 'getbroadcastmpd');
    if (json['success'] != 'ready') return null;
    final id = json['broadcastid']?.toString() ?? '';
    return RegExp(r'^[1-9]\d*$').hasMatch(id) ? id : null;
  }

  /// `getchatinfo` → the message URL template (`…/messages/{0}?…`).
  static String chatTemplate(String body) {
    final json = _object(body, 'getchatinfo');
    final template = json['view_url_template'];
    if (json['success'] != 1 || template is! String || !template.contains('{0}')) {
      throw FormatException('getchatinfo: success ${json['success']}');
    }
    return template;
  }

  /// The URL of the chat window at [time]; 0 asks for the latest history.
  static Uri messagesUrl(String template, int time) => Uri.parse(template.replaceFirst('{0}', '$time'));

  /// One window; ids combine the window time and the position in it.
  static SteamChatPoll parse(String body, {required int time, required DecodeContext context}) {
    final json = _object(body, 'messages');
    final next = json['next_request'];
    if (next is! int || next <= 0) throw FormatException('messages: next_request $next');
    final delay = json['initial_delay'];
    final events = <DanmakuEvent>[];
    final messages = json['messages'];
    if (messages is List) {
      for (final (index, message) in messages.indexed) {
        if (message is! Map) continue;
        final text = message['msg']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final name = message['persona_name']?.toString().trim() ?? '';
        events.add(
          DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: 'steambroadcast:$time:$index',
            userId: message['steamid']?.toString() ?? '',
            userName: name.isEmpty ? 'Steam' : name,
            text: text,
          ),
        );
      }
    }
    return SteamChatPoll(
      next: next,
      events: events,
      initialDelay: delay is int && delay >= 0 ? Duration(milliseconds: delay) : null,
    );
  }
}

/// Steam broadcast chat, read like the web client (broadcast_chat.js): the
/// first request (window 0) returns the latest history, the next window's
/// time and `initial_delay`; every later window is requested when the chat
/// log's clock reaches it, about twice a second. The history is not
/// emitted. After [resyncAfter] consecutive failures the reader starts over
/// from window 0; after [maxFailures] it gives up.
final class SteamBroadcastConnector extends ConnectorBase {
  /// Creates the connector; [detail]'s `danmakuKeys['steamid']` is the
  /// broadcaster.
  new({required super.detail, required super.transport, super.session, super.clock});

  /// Consecutive failures that restart from window 0 (web client: 4).
  static const resyncAfter = 4;

  /// Consecutive failures before the terminal state.
  static const maxFailures = 12;

  /// Wait after a failed request (web client: 500 ms).
  static const retryDelay = Duration(milliseconds: 500);

  /// Shortest wait between two windows, so a late reader never spins.
  static const minimumDelay = Duration(milliseconds: 200);

  @override
  Future<void> run(int generation) async {
    final steamId = detail.danmakuKeys['steamid'] ?? '';
    if (steamId.isEmpty) {
      terminal(generation, 'noRoom', 'steamid missing');
      return;
    }
    status(generation, DanmakuStatus.connecting);
    final headers = SteamBroadcastProtocol.headers(steamId);
    final String template;
    try {
      final broadcast = SteamBroadcastProtocol.broadcastId(
        await _get(SteamBroadcastProtocol.broadcastUrl(steamId), headers),
      );
      if (broadcast == null) {
        terminal(generation, 'offline');
        return;
      }
      template = SteamBroadcastProtocol.chatTemplate(
        await _get(SteamBroadcastProtocol.chatInfoUrl(steamId, broadcast), headers),
      );
    } on Object catch (error) {
      if (!isStale(generation)) terminal(generation, 'failed', '$error');
      return;
    }
    // The chat log's clock: window `first` is due at monotonic `firstAt`.
    int? firstAt;
    var first = 0;
    var next = 0;
    var failures = 0;
    var nudge = 0;
    var joinedOnce = false;
    var delay = Duration.zero;
    while (await pause(generation, delay)) {
      final time = firstAt == null ? 0 : next;
      try {
        final poll = SteamBroadcastProtocol.parse(
          await _get(SteamBroadcastProtocol.messagesUrl(template, time), headers),
          time: time,
          context: context(),
        );
        if (isStale(generation)) return;
        if (failures > 0 && joinedOnce) status(generation, DanmakuStatus.connected);
        failures = 0;
        final initial = poll.initialDelay;
        if (firstAt == null || initial != null) {
          // A first read (or a resync): history only, then follow the clock.
          firstAt = clock.micros() ~/ 1000 + (initial?.inMilliseconds ?? 0);
          first = poll.next;
          next = poll.next;
          nudge = 0;
          if (!joinedOnce) {
            joinedOnce = true;
            status(generation, DanmakuStatus.connected);
            joined(generation);
          }
          delay = initial ?? minimumDelay;
          continue;
        }
        for (final event in poll.events) {
          emit(generation, event);
        }
        next = poll.next;
        final due = firstAt + (next - first) + nudge - clock.micros() ~/ 1000;
        delay = Duration(milliseconds: due < minimumDelay.inMilliseconds ? minimumDelay.inMilliseconds : due);
      } on Object catch (error) {
        if (isStale(generation)) return;
        failures++;
        nudge += 10;
        if (!joinedOnce && failures > 2) {
          terminal(generation, 'failed', '$error');
          return;
        }
        if (failures == 1) status(generation, DanmakuStatus.reconnecting);
        if (failures >= maxFailures) {
          terminal(generation, 'maxRetries');
          return;
        }
        if (failures % resyncAfter == 0) firstAt = null;
        delay = retryDelay;
      }
    }
  }

  Future<String> _get(Uri url, Map<String, String> headers) async {
    final cancel = CancelToken();
    final removeStop = onStop(cancel.cancel);
    try {
      final response = await transport.http.send(
        LiveRequest(
          site: 'steambroadcast',
          url: url,
          headers: headers,
          timeout: const Duration(seconds: 10),
          cancel: cancel,
        ),
      );
      if (!response.isSuccess) throw FormatException('HTTP ${response.status} ${url.path}');
      return response.text;
    } finally {
      removeStop();
    }
  }
}
