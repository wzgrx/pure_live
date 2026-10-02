import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`), from
/// the reliable list's notice 107/10024.
@immutable
final class BaiduLiveGift {
  /// Creates the gift.
  const new({required this.id, required this.name, required this.count, required this.free, this.icon});

  /// `gift_id`, or empty.
  final String id;

  /// `gift_name` (`拍拍`).
  final String name;

  /// `gift_count`, at least 1.
  final int count;

  /// `is_free` is 1.
  final bool free;

  /// `gift_url` when it is an https URL.
  final Uri? icon;

  @override
  bool operator ==(Object other) =>
      other is BaiduLiveGift &&
      other.id == id &&
      other.name == name &&
      other.count == count &&
      other.free == free &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, name, count, free, icon);

  @override
  String toString() => 'BaiduLiveGift($name ×$count)';
}

/// One answer of a message list ([BaiduLiveDanmakuProtocol.playlist]).
@immutable
final class BaiduLivePlaylist {
  /// Creates the playlist.
  new({required Iterable<Uri> segments, this.mediaSequence}) : segments = List.unmodifiable(segments);

  /// The segments, oldest first, resolved against the list's URL.
  final List<Uri> segments;

  /// `#EXT-X-MEDIA-SEQUENCE`, or null. Always 0 when recorded, so segments
  /// are told apart by [BaiduLiveDanmakuProtocol.segmentKey] instead.
  final int? mediaSequence;
}

/// What one segment says ([BaiduLiveDanmakuProtocol.segment]).
@immutable
final class BaiduLiveSegment {
  /// Creates the segment.
  new({Iterable<LiveMessage> messages = const [], this.ended = false}) : messages = List.unmodifiable(messages);

  /// The messages, in order.
  final List<LiveMessage> messages;

  /// Whether it holds the room's "broadcast stopped" notice (102).
  final bool ended;
}

/// Baidu Live's chat (docs/D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/record.md), without I/O.
///
/// The room command 371 names three message lists (`BaiduLiveDanmakuArgs`):
/// HLS-style playlists on `liveshowstatic.baidu.com` that keep the last few
/// segments, each a JSON batch `{list: [{messages: [...]}]}`, gzipped (with
/// or without `Content-Encoding`). A message whose `type` is 0 holds its
/// payload in `content`, a JSON text whose `text` is JSON again (the web
/// page's `handleMessage`, pchome.live.fcb2dc0e.js). Read are the payload
/// types:
/// - 0, chat: the text by `message_type` as the page's `addChatItem` reads
///   it;
/// - 101, the online count `data.onlineusercnt` (the room command's
///   `online_users`);
/// - 102, the broadcast stopped (the page's `stopLive`);
/// - 107 with `service_type` 10024, a gift.
///
/// Everything else (107's other notices: `mix_room_close` names other
/// rooms of the recommendation mix that closed, likes, level-ups, pinned
/// comments, cards; 103, 104, 108) is not reported.
abstract final class BaiduLiveDanmakuProtocol {
  /// Limit of one request.
  static const Duration requestTimeout = Duration(seconds: 10);

  /// Tries of the first chat list request.
  static const int startAttempts = 3;

  /// Wait between the tries of the first chat list request.
  static const Duration startRetryDelay = Duration(seconds: 2);

  /// Failed chat list requests in a row that are retried; the next one ends
  /// the connection.
  static const int maxFailures = 8;

  /// Polls a reliable or host list skips at most after failing.
  static const int maxSkippedPolls = 12;

  /// Tries of a segment that fails without an answer (or with 5xx).
  static const int segmentAttempts = 3;

  /// Segment keys remembered per list (a list shows three).
  static const int rememberedSegments = 256;

  /// The close detail of a broadcast that stopped (102).
  static const String endedDetail = 'Broadcast ended';

  /// Request headers of room [roomId]: the website's (UA, Origin, the room
  /// page as Referer). The lists need none; the page sends them.
  static Map<String, String> headers(String roomId) => {
    'user-agent': BaiduLiveApi.userAgent,
    'accept': 'application/json, text/plain, */*',
    'origin': BaiduLiveApi.webOrigin,
    'referer': BaiduLiveApi.roomUrl(roomId),
  };

  /// Wait after the [failures]-th failed chat list request in a row: 1, 2,
  /// 4, then 8 s.
  static Duration backoff(int failures) => Duration(seconds: 1 << (failures - 1).clamp(0, 3));

  /// Polls a reliable or host list skips after its [failures]-th failure in
  /// a row: 1, 2, 4, 8, then 12.
  static int skippedPolls(int failures) => (1 << (failures - 1).clamp(0, 4)).clamp(1, maxSkippedPolls);

  /// The key a segment is told apart by: its path (the name holds the
  /// list's id and a nanosecond time; the query is its signature).
  static String segmentKey(Uri segment) => segment.path;

  /// A playlist answered from [list]: `#EXTM3U` first, then every line that
  /// is neither empty nor a tag is a segment, resolved against [list]; one
  /// on another host or scheme is skipped. Throws [FormatException] when the
  /// text is not a playlist.
  static BaiduLivePlaylist playlist(String text, Uri list) {
    final lines = const LineSplitter().convert(text).map((line) => line.trim()).where((line) => line.isNotEmpty);
    if (lines.firstOrNull != '#EXTM3U') throw const FormatException('Baidu Live message list is not a playlist');
    int? sequence;
    final segments = <Uri>[];
    for (final line in lines) {
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = _int(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length));
      }
      if (line.startsWith('#')) continue;
      final Uri segment;
      try {
        segment = list.resolve(line);
      } on FormatException {
        continue;
      }
      if (segment.scheme == list.scheme && segment.host == list.host && segment.userInfo.isEmpty) {
        segments.add(segment);
      }
    }
    return BaiduLivePlaylist(segments: segments, mediaSequence: sequence);
  }

  /// [bytes] inflated while they start with the gzip magic (at most twice):
  /// segments are gzipped, sometimes without `Content-Encoding` (then the
  /// transport leaves them as they are). Throws [FormatException] on a
  /// broken gzip stream.
  static List<int> inflate(List<int> bytes) {
    var body = bytes;
    for (var depth = 0; depth < 2 && body.length >= 2 && body[0] == 0x1f && body[1] == 0x8b; depth++) {
      body = gzip.decode(body);
    }
    return body;
  }

  /// The messages of one segment (its body as served) for room [roomId],
  /// in order. Throws [FormatException] when it is not a JSON object; a
  /// message that cannot be read is skipped.
  static BaiduLiveSegment segment(List<int> bytes, {required String roomId}) {
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(inflate(bytes)));
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Baidu Live segment: $error');
    }
    if (root is! Map<String, Object?>) throw const FormatException('Baidu Live segment is not an object');
    final messages = <LiveMessage>[];
    var ended = false;
    for (final item in _list(root['list'])) {
      for (final message in _list(_map(item)['messages'])) {
        switch (_payload(message)) {
          case (final Map<String, Object?> outer, final Map<String, Object?> inner):
            switch (_int(inner['type'])) {
              case 0:
                if (_chat(outer, inner, roomId) case final chat?) messages.add(chat);
              case 101:
                if (_online(inner, roomId) case final online?) messages.add(online);
              case 102:
                if (_forRoom(inner['room_id'] ?? _map(inner['data'])['room_id'], roomId)) ended = true;
              case 107:
                if (_gift(outer, inner, roomId) case final gift?) messages.add(gift);
            }
          case null:
            break;
        }
      }
    }
    return BaiduLiveSegment(messages: messages, ended: ended);
  }

  /// The online count as a message.
  static LiveMessage audience(int viewers) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
    color: LiveMessageColor.white,
  );

  /// A message and its payload: the page reads only `type` 0, whose
  /// `content` (JSON text or an object) holds `text` (JSON text or an
  /// object).
  static (Map<String, Object?>, Map<String, Object?>)? _payload(Object? message) {
    final outer = _map(message);
    if (_int(outer['type']) != 0) return null;
    final text = _map(_decoded(outer['content']))['text'];
    final inner = _decoded(text);
    return inner is Map<String, Object?> ? (outer, inner) : null;
  }

  static Object? _decoded(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  /// A chat line (the page's `addChatItem`): the text by `message_type`
  /// ("0" `content`, else `message_body.txt.word`; "3" the link's title;
  /// "1", "2", "4" images and cards and "5" voice have none; others
  /// `content`), a reply's own words (`message_body.txt.word` when
  /// `at_name` and the quoted words are given); trimmed, empty is dropped.
  static LiveMessage? _chat(Map<String, Object?> outer, Map<String, Object?> inner, String roomId) {
    if (!_forRoom(inner['room_id'], roomId)) return null;
    final body = _map(inner['message_body']);
    final words = _string(_map(body['txt'])['word']);
    final content = _string(inner['content']);
    var text = switch (_id(inner['message_type'])) {
      '0' => content.isNotEmpty ? content : words,
      '1' || '2' || '4' || '5' => '',
      '3' => _string(_map(body['link'])['title']),
      _ => content,
    };
    final quoted = _string(_map(_map(inner['at_message_body'])['txt'])['word']);
    if (_string(inner['at_name']).isNotEmpty && _int(inner['at_message_type']) == 0 && quoted.isNotEmpty) {
      if (words.isNotEmpty) text = words;
    }
    text = text.trim();
    if (text.isEmpty) return null;
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _string(inner['name']).trim(),
      userId: _id(inner['uid']),
      message: text,
      messageId: _id(outer['msgid']),
      sentAt: _time(outer['create_time']),
      color: LiveMessageColor.white,
    );
  }

  /// The online count of a 101 (`data.onlineusercnt`, a whole number of
  /// zero or more).
  static LiveMessage? _online(Map<String, Object?> inner, String roomId) {
    if (!_forRoom(inner['room_id'], roomId)) return null;
    final count = _int(_map(inner['data'])['onlineusercnt']);
    return count != null && count >= 0 ? audience(count) : null;
  }

  /// A gift of a 107/10024: `service_info` names the sender (`user_name`,
  /// `user_id`) and holds the gift in `content` (JSON text or an object:
  /// `gift_name`, `gift_count`, `gift_id`, `is_free`, `gift_url`). The text
  /// is `<name> ×<count>`; without a name there is no gift.
  static LiveMessage? _gift(Map<String, Object?> outer, Map<String, Object?> inner, String roomId) {
    final data = _map(inner['data']);
    if (_id(data['service_type']) != '10024') return null;
    final service = _map(data['service_info']);
    if (!_forRoom(service['room_id'], roomId)) return null;
    final content = _map(_decoded(service['content']));
    final name = _string(content['gift_name']).trim();
    if (name.isEmpty) return null;
    final count = _int(content['gift_count']);
    final icon = Uri.tryParse(_string(content['gift_url']).trim());
    final gift = BaiduLiveGift(
      id: _id(content['gift_id']),
      name: name,
      count: count != null && count > 0 ? count : 1,
      free: _int(content['is_free']) == 1,
      icon: icon != null && icon.scheme == 'https' && icon.host.isNotEmpty ? icon : null,
    );
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: _string(service['user_name']).trim(),
      userId: _id(service['user_id']),
      message: '${gift.name} ×${gift.count}',
      messageId: _id(outer['msgid']),
      sentAt: _time(outer['create_time']),
      data: gift,
      color: LiveMessageColor.white,
    );
  }

  /// Whether a message's room id (missing, or naming [roomId]) is this
  /// room's.
  static bool _forRoom(Object? value, String roomId) {
    final id = _id(value);
    return id.isEmpty || id == roomId;
  }

  /// The largest time `DateTime` holds, in seconds either side of the epoch.
  static const int _maxSeconds = 8640000000000;

  /// `create_time` (Unix seconds, positive) in local time.
  static DateTime? _time(Object? value) {
    final seconds = _int(value);
    if (seconds == null || seconds <= 0 || seconds > _maxSeconds) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  /// A whole number: an integer, a whole finite double, or decimal digits
  /// (with a sign) as text; null otherwise (and beyond 64 bits).
  static int? _int(Object? value) => switch (value) {
    final int number => number,
    final double number when number.isFinite && number == number.truncateToDouble() && number.abs() < 9.2e18 =>
      number.toInt(),
    final String text when _digits.hasMatch(text.trim()) => int.tryParse(text.trim()),
    _ => null,
  };

  static final RegExp _digits = RegExp(r'^[+-]?\d+$');

  /// An id: text as it is (trimmed), a whole number as digits; empty
  /// otherwise.
  static String _id(Object? value) => switch (value) {
    final String text => text.trim(),
    final num number => '${_int(number) ?? ''}',
    _ => '',
  };

  static String _string(Object? value) => value is String ? value : '';

  static Map<String, Object?> _map(Object? value) => value is Map<String, Object?> ? value : const {};

  static List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];
}

/// Baidu Live's danmaku connection: the room's message lists
/// (`BaiduLiveDanmakuArgs`), polled over [LiveHttp]; no socket, no
/// heartbeat.
///
/// - `connect` joins with the first chat list answer, whose segments (the
///   last few, however old) are history and not fetched; a 404 is a list
///   without messages yet. A failed request is tried again 2 s later; the
///   third failure ends the run with [DanmakuCloseReason.connectionFailed].
///   Arguments whose signature ran out (by the clock `now`) end it with
///   [DanmakuCloseReason.credentialsUnavailable] without a request, as does
///   a chat list refused (403) after it ran out: the room detail brings new
///   ones.
/// - Every `pullInterval` after the previous poll (5 s), the chat list is
///   asked again, then the reliable and host lists; each segment not seen
///   before is fetched once, in order, and its messages reported. The
///   first answer of the reliable and host lists is history too.
/// - A failed chat list request (no answer, a status that is not 2xx or
///   404, not a playlist) is tried again after 1, 2, 4, 8, 8… s; the first
///   failure in a row reports [DanmakuReconnecting], the ninth ends with
///   [DanmakuCloseReason.reconnectsExhausted], and an answer after failures
///   reports [DanmakuReady] again. A failing reliable or host list (the
///   host list answered 404 whenever recorded) only skips 1, 2, 4, 8, then
///   12 polls. A segment answered with 4xx, or not a JSON object, is
///   skipped; one without an answer (or with 5xx) is tried in the next
///   polls, three times in all.
/// - The room's "broadcast stopped" notice (102) ends the run with
///   [DanmakuCloseReason.connectionFailed] and the detail
///   [BaiduLiveDanmakuProtocol.endedDetail]: a room is one broadcast, and
///   its replay has no new chat.
///
/// The app registers it as `SiteIds.baiduLive: () =>
/// BaiduLiveDanmakuConnection(http: …)`, with the `LiveHttp` it gives
/// `BaiduLiveSite` (the `baidulive` proxy route and throttle).
final class BaiduLiveDanmakuConnection extends DanmakuConnectionBase<BaiduLiveDanmakuArgs> {
  /// Creates the connection; `http` sends the requests, [now] is the clock
  /// the signature's expiry is compared with.
  new({required this._http, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final LiveHttp _http;
  final DateTime Function() _now;

  @override
  @protected
  Future<void> start(BaiduLiveDanmakuArgs args, DanmakuRun run) async {
    if (args.isExpiredAt(_now())) {
      throw DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable, detail: _expired(args));
    }
    final chat = _BaiduLiveChat(_http, args, run, _now);
    for (var failures = 0; ;) {
      try {
        await chat.join();
        break;
      } on Object catch (error) {
        if (!run.isActive) return;
        if (++failures >= BaiduLiveDanmakuProtocol.startAttempts) {
          throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: '$error');
        }
        if (!await run.delay(BaiduLiveDanmakuProtocol.startRetryDelay)) return;
      }
    }
    if (!run.isActive) return;
    run.ready();
    unawaited(chat.follow());
  }
}

String _expired(BaiduLiveDanmakuArgs args) =>
    'Chat list signature expired at ${args.expiresAt?.toUtc().toIso8601String()}';

/// One message list of a run: the segments seen, the failures.
final class _BaiduLiveList {
  new(this.url);

  final Uri url;

  /// Whether its history was set aside (its first answer after joining,
  /// or a 404: a list that does not exist yet has none).
  bool primed = false;

  /// Keys of the segments fetched or given up, oldest first.
  final LinkedHashSet<String> seen = LinkedHashSet();

  /// Failed tries of segments not answered yet.
  final Map<String, int> attempts = {};

  /// Failed requests in a row (reliable and host lists).
  int failures = 0;

  /// Polls to skip before asking again (reliable and host lists).
  int skip = 0;

  void remember(String key) {
    attempts.remove(key);
    seen.add(key);
    while (seen.length > BaiduLiveDanmakuProtocol.rememberedSegments) {
      seen.remove(seen.first);
    }
  }
}

/// The chat of one run: its lists and requests, cancelled when the run
/// ends.
final class _BaiduLiveChat {
  new(this._http, this._args, this._run, this._now)
    : _roomId = _args.roomId,
      _interval = _args.pullInterval,
      _headers = BaiduLiveDanmakuProtocol.headers(_args.roomId),
      _chat = _BaiduLiveList(_args.chatList),
      _others = [
        if (_args.reliableList case final reliable?) _BaiduLiveList(reliable),
        if (_args.hostList case final host?) _BaiduLiveList(host),
      ] {
    unawaited(_run.ended.then((_) => _cancel.cancel()));
  }

  final LiveHttp _http;
  final BaiduLiveDanmakuArgs _args;
  final DanmakuRun _run;
  final DateTime Function() _now;
  final String _roomId;
  final Duration _interval;
  final Map<String, String> _headers;
  final _BaiduLiveList _chat;
  final List<_BaiduLiveList> _others;
  final CancelToken _cancel = CancelToken();

  /// The first chat list answer: its segments are history.
  Future<void> join() async {
    final playlist = await _playlist(_chat);
    _prime(_chat, playlist);
  }

  /// Polls until the broadcast stops, the failures run out or the run ends.
  Future<void> follow() async {
    var wait = _interval;
    var failures = 0;
    while (await _run.delay(wait)) {
      final BaiduLivePlaylist? playlist;
      try {
        playlist = await _playlist(_chat);
      } on Object catch (error) {
        if (!_run.isActive) return;
        // A refused list whose signature ran out stays refused: the room
        // detail brings new lists.
        if (error is HttpStatusFailure && error.status == 403 && _args.isExpiredAt(_now())) {
          _run.closed(DanmakuCloseReason.credentialsUnavailable, detail: _expired(_args));
          return;
        }
        if (++failures > BaiduLiveDanmakuProtocol.maxFailures) {
          _run.closed(DanmakuCloseReason.reconnectsExhausted, detail: '$error');
          return;
        }
        if (failures == 1) _run.reconnecting(DanmakuInterruption.disconnected, detail: '$error');
        wait = BaiduLiveDanmakuProtocol.backoff(failures);
        continue;
      }
      if (!_run.isActive) return;
      if (failures > 0) {
        failures = 0;
        _run.ready();
      }
      if (!await _drain(_chat, playlist)) return;
      for (final list in _others) {
        if (!await _poll(list)) return;
      }
      wait = _interval;
    }
  }

  /// One poll of a reliable or host list; false when the run is over.
  Future<bool> _poll(_BaiduLiveList list) async {
    if (list.skip > 0) {
      list.skip--;
      return true;
    }
    final BaiduLivePlaylist? playlist;
    try {
      playlist = await _playlist(list);
    } on Object {
      if (!_run.isActive) return false;
      list.skip = BaiduLiveDanmakuProtocol.skippedPolls(++list.failures);
      return true;
    }
    if (!_run.isActive) return false;
    if (playlist == null) {
      // A list that does not exist (404) has no history, and is asked less
      // often too.
      list
        ..primed = true
        ..skip = BaiduLiveDanmakuProtocol.skippedPolls(++list.failures);
      return true;
    }
    list.failures = 0;
    if (!list.primed) {
      _prime(list, playlist);
      return true;
    }
    return await _drain(list, playlist);
  }

  void _prime(_BaiduLiveList list, BaiduLivePlaylist? playlist) {
    list.primed = true;
    for (final segment in playlist?.segments ?? const <Uri>[]) {
      list.remember(BaiduLiveDanmakuProtocol.segmentKey(segment));
    }
  }

  /// Fetches and reports the segments of [playlist] not seen before;
  /// false when the run is over (closed, or the broadcast stopped).
  Future<bool> _drain(_BaiduLiveList list, BaiduLivePlaylist? playlist) async {
    for (final segment in playlist?.segments ?? const <Uri>[]) {
      final key = BaiduLiveDanmakuProtocol.segmentKey(segment);
      if (list.seen.contains(key)) continue;
      final List<int> bytes;
      try {
        bytes = await _get(segment);
      } on HttpStatusFailure catch (failure) {
        if (!_run.isActive) return false;
        if (failure.status < 500 || _failed(list, key)) list.remember(key);
        continue;
      } on Object {
        if (!_run.isActive) return false;
        if (_failed(list, key)) list.remember(key);
        continue;
      }
      if (!_run.isActive) return false;
      list.remember(key);
      final BaiduLiveSegment decoded;
      try {
        decoded = BaiduLiveDanmakuProtocol.segment(bytes, roomId: _roomId);
      } on FormatException {
        continue;
      }
      decoded.messages.forEach(_run.message);
      if (decoded.ended) {
        _run.closed(DanmakuCloseReason.connectionFailed, detail: BaiduLiveDanmakuProtocol.endedDetail);
        return false;
      }
    }
    return _run.isActive;
  }

  /// Counts a failed try of segment [key]; true when it is given up.
  bool _failed(_BaiduLiveList list, String key) {
    final tries = (list.attempts[key] ?? 0) + 1;
    list.attempts[key] = tries;
    return tries >= BaiduLiveDanmakuProtocol.segmentAttempts;
  }

  /// The playlist of [list], or null when the list does not exist (404).
  /// Throws `TransportFailure`, `HttpStatusFailure` or [FormatException].
  Future<BaiduLivePlaylist?> _playlist(_BaiduLiveList list) async {
    final response = await _send(list.url);
    if (response.status == 404) return null;
    if (!response.isSuccess) throw HttpStatusFailure.of(SiteIds.baiduLive, response);
    return BaiduLiveDanmakuProtocol.playlist(response.text, list.url);
  }

  /// The body of [segment]; throws `TransportFailure` or
  /// `HttpStatusFailure`.
  Future<List<int>> _get(Uri segment) async {
    final response = await _send(segment);
    if (!response.isSuccess) throw HttpStatusFailure.of(SiteIds.baiduLive, response);
    return response.bytes;
  }

  Future<LiveResponse> _send(Uri url) => _http.send(
    LiveRequest(
      site: SiteIds.baiduLive,
      url: url,
      headers: _headers,
      timeout: BaiduLiveDanmakuProtocol.requestTimeout,
      cancel: _cancel,
    ),
  );
}
