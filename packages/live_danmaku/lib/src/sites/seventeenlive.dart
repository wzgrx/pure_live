import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What an Ably protocol message of a 17LIVE chat socket asks of the
/// connection ([SeventeenLiveDanmakuFrame.signal]).
enum SeventeenLiveSignal {
  /// Nothing: a heartbeat (`action 0`), a presence sync, another channel's
  /// message, a frame that cannot be read.
  none,

  /// `CONNECTED` (4): the socket may attach the channel now.
  connected,

  /// `ATTACHED` (11) for the room's channel: joined.
  attached,

  /// `DETACHED` (13) for the room's channel, sent by the server: the
  /// channel has to be attached again.
  detached,

  /// `DISCONNECTED` (6): the server drops the socket; a new one follows.
  disconnected,

  /// `ERROR` (9) of the connection: fatal unless it is a token error.
  connectionError,

  /// `ERROR` (9) of the room's channel: the channel failed.
  channelError,

  /// `AUTH` (17): the server asks for a new token on this socket.
  reauthorize,
}

/// An Ably error (`{"code":40142,"statusCode":401,"message":…}`).
@immutable
final class SeventeenLiveAblyError {
  /// Creates the error.
  const new({required this.code, this.statusCode, this.message = ''});

  /// Ably's error code; 0 when the frame gave none.
  final int code;

  /// Its HTTP status, when given.
  final int? statusCode;

  /// Its message, when given.
  final String message;

  /// A token error (40140 to 40149: token expired, revoked, unrecognised…):
  /// a new token fixes it (ably-js's `isTokenErr`).
  bool get isTokenError => code >= 40140 && code < 40150;

  @override
  bool operator ==(Object other) =>
      other is SeventeenLiveAblyError &&
      other.code == code &&
      other.statusCode == statusCode &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, statusCode, message);

  @override
  String toString() => '$code $message'.trim();
}

/// The connection a `CONNECTED` names ([SeventeenLiveDanmakuFrame.connection]):
/// what a later socket resumes (Ably's `resume`, docs/T06/T06a/T06a.30/record.md,
/// B-14).
@immutable
final class SeventeenLiveConnectionDetails {
  /// Creates the details.
  const new({
    required this.id,
    required this.key,
    this.stateTtl = SeventeenLiveDanmakuProtocol.defaultConnectionStateTtl,
    this.maxIdleInterval = SeventeenLiveDanmakuProtocol.heartbeatInterval,
  });

  /// `connectionId`: the same one after a resume means the connection went
  /// on.
  final String id;

  /// `connectionDetails.connectionKey`: a socket's `resume` query parameter.
  final String key;

  /// `connectionDetails.connectionStateTtl`: how long the server keeps the
  /// connection after the socket dropped.
  final Duration stateTtl;

  /// `connectionDetails.maxIdleInterval`: the server's heartbeat period.
  final Duration maxIdleInterval;

  @override
  bool operator ==(Object other) =>
      other is SeventeenLiveConnectionDetails &&
      other.id == id &&
      other.key == key &&
      other.stateTtl == stateTtl &&
      other.maxIdleInterval == maxIdleInterval;

  @override
  int get hashCode => Object.hash(id, key, stateTtl, maxIdleInterval);
}

/// One Ably message of a `MESSAGE` frame, read
/// ([SeventeenLiveDanmakuProtocol.entry]).
@immutable
final class SeventeenLiveEntry {
  /// Creates the entry.
  const new({
    this.id = '',
    this.messages = const [],
    this.muted,
    this.ended = false,
    this.publishedAt,
    this.replayed = false,
  });

  /// Ably's message id (or the frame's id and the index): a message the
  /// server sends again after a resume has the same one.
  final String id;

  /// When Ably published it: the message's `timestamp`, else its frame's
  /// (milliseconds, as ably-js fills it in); null when neither is a time.
  final DateTime? publishedAt;

  /// Whether it is part of the backlog an `ATTACHED` announced (B-26): its
  /// [messages] are [LiveMessage.replayed].
  final bool replayed;

  /// What it shows, in order: a comment's chat line, then a paid barrage's
  /// super chat; the viewers now.
  final List<LiveMessage> messages;

  /// The live figures' (38) `liveinfo.mute`, when it is a boolean.
  final bool? muted;

  /// A stream end (`LIVE_STREAM_END`, 5).
  final bool ended;
}

/// What one 17LIVE chat frame held ([SeventeenLiveDanmakuProtocol.decode]).
@immutable
final class SeventeenLiveDanmakuFrame {
  /// Creates the result.
  const new({
    this.signal = SeventeenLiveSignal.none,
    this.error,
    this.entries = const [],
    this.connection,
    this.channelSerial,
    this.resumed = false,
    this.backlog = false,
  });

  /// What the frame asks of the connection.
  final SeventeenLiveSignal signal;

  /// The error a `DISCONNECTED`, `DETACHED` or `ERROR` carried, or that a
  /// `CONNECTED` (a resume that failed: 80018 an invalid key) or an
  /// `ATTACHED` (90003: the channel's messages since the serial expired)
  /// came with; null otherwise.
  final SeventeenLiveAblyError? error;

  /// The Ably messages of a `MESSAGE`, in order.
  final List<SeventeenLiveEntry> entries;

  /// Chat, super chats and audience figures of a `MESSAGE`, in order.
  List<LiveMessage> get messages => [for (final entry in entries) ...entry.messages];

  /// A `CONNECTED`'s connection, when it names its id and key.
  final SeventeenLiveConnectionDetails? connection;

  /// The room channel's `channelSerial` of an `ATTACHED`, `MESSAGE` or
  /// `PRESENCE`: where an attach resumes from.
  final String? channelSerial;

  /// Whether an `ATTACHED` has the `RESUMED` flag: the channel went on from
  /// the serial the attach gave, missing nothing.
  final bool resumed;

  /// Whether an `ATTACHED` has the `HAS_BACKLOG` flag: messages sent before
  /// the attach follow it (what a resume missed, or the recent ones when it
  /// could not resume; B-26).
  final bool backlog;
}

/// `messenger/auth` answered with another push service than Ably: the chat
/// cannot be joined.
final class SeventeenLiveChatRefusal implements Exception {
  /// Creates the refusal for `provider` [provider].
  const new(this.provider);

  /// The answer's `provider` (the website's enum: 1 Ably, 2 PubNub), as
  /// text; empty when the answer named none.
  final String provider;

  @override
  String toString() => 'messenger/auth: provider ${provider.isEmpty ? 'missing' : provider}';
}

/// 17LIVE's chat (the archived v4's spec/sites/17live.md §7, checked
/// against the recordings `fixtures/17live/danmaku/S05-live`, `S06-live`,
/// the website's scripts and read-only sessions of 2026-09-28 to 09-30;
/// docs/T06/T06a/T06a.30/record.md), without I/O.
///
/// - The website's push service is Ably (ably-js with `environment:
///   "17media"`). An anonymous token comes from `POST messenger/auth`
///   ([authRequest], [grant]); the socket is Ably's JSON realtime protocol
///   ([endpoints], [withToken]).
/// - After `CONNECTED` the client attaches the room's channel, named by the
///   room id ([attach]); `ATTACHED` joins it. The server sends a heartbeat
///   every 15 s; the client sends none.
/// - A `MESSAGE` (15) holds messages whose `data` is JSON, gzipped and
///   base64-encoded (the website's `gzip_base64`); its `type` is the
///   website's message enum: 3 a comment, 38 the live figures, 5 the stream
///   end ([entry]).
/// - A later socket resumes as ably-js 2.21.0 does (B-14): `resume` with
///   the last `CONNECTED`'s key ([withToken]), and an `ATTACH` with the
///   last `channelSerial` and the `ATTACH_RESUME` flag ([attach]); the
///   server answers `ATTACHED` with `RESUMED` and sends the messages missed
///   meanwhile. An `ATTACHED` with `HAS_BACKLOG` announces them; the
///   messages published before it are replayed (B-26).
abstract final class SeventeenLiveDanmakuProtocol {
  /// The token source; the website's ably-js asks it in its `authCallback`.
  static final Uri authUrl = Uri.https(SeventeenLiveApi.apiHost, '/api/v1/messenger/auth');

  /// `messenger/auth`'s `provider` for Ably; the website's `PUBNUB` is 2.
  static const int ablyProvider = 1;

  /// The realtime host of ably-js's `environment: "17media"`.
  static const String primaryHost = '17media.realtime.ably.net';

  /// The website's `fallbackHosts`, tried after the primary host fails.
  static const List<String> fallbackHosts = [
    '17-media-a-fallback.ably-realtime.com',
    '17-media-b-fallback.ably-realtime.com',
    '17-media-c-fallback.ably-realtime.com',
  ];

  /// The sockets, primary host first, without their token ([withToken]):
  /// the JSON protocol, version 3, with server heartbeats.
  static final List<Uri> endpoints = List.unmodifiable([
    for (final host in [primaryHost, ...fallbackHosts])
      Uri(scheme: 'wss', host: host, path: '/', queryParameters: {'format': 'json', 'heartbeats': 'true', 'v': '3'}),
  ]);

  /// Handshake headers: the website's origin and the platform's desktop UA,
  /// as the recordings sent them.
  static const Map<String, String> handshakeHeaders = {
    'origin': SeventeenLiveApi.origin,
    'user-agent': SeventeenLiveApi.userAgent,
  };

  /// The server's heartbeat period (`CONNECTED`'s `maxIdleInterval`, 15 000
  /// ms in every recording). The client sends no heartbeat; this is the tick
  /// of the silence watchdog.
  static const Duration heartbeatInterval = Duration(seconds: 15);

  /// Silence after which the socket is replaced: ably-js's idle limit,
  /// `maxIdleInterval` plus its `realtimeRequestTimeout` (10 s).
  static const Duration inactivityTimeout = Duration(seconds: 25);

  /// How long the attach may take: ably-js's `realtimeRequestTimeout`.
  static const Duration joinTimeout = Duration(seconds: 10);

  /// Refusals in a row (token errors and server-sent detaches) after which
  /// the chat gives up; an attached channel starts the count again.
  static const int maxRefusals = 3;

  /// The largest token taken from `messenger/auth`.
  static const int maxTokenLength = 4096;

  /// The comment type (`COMMENT`).
  static const int commentType = 3;

  /// The live figures' type (`LIVE`): `liveinfo.liveViewerCount`.
  static const int liveType = 38;

  /// The stream end's type (`LIVE_STREAM_END`): the website leaves the
  /// channel.
  static const int streamEndType = 5;

  /// How long the server keeps a dropped connection when `CONNECTED` does
  /// not say (`connectionStateTtl`, 120 000 ms in every recording and in
  /// ably-js's defaults).
  static const Duration defaultConnectionStateTtl = Duration(seconds: 120);

  /// `ATTACH`'s `ATTACH_RESUME` flag: the channel was attached before.
  static const int attachResumeFlag = 32;

  /// `ATTACHED`'s `RESUMED` flag.
  static const int resumedFlag = 4;

  /// `ATTACHED`'s `HAS_BACKLOG` flag: a backlog follows (ably-js hands it to
  /// the attached state change as `hasBacklog`; it marks no message).
  static const int hasBacklogFlag = 2;

  /// How long a paid barrage stays a super chat: the website flies it once
  /// over the player, 1 px a frame from the right edge until it leaves the
  /// left one (`7953` chunk, `KV`): (player width + barrage width) / 60 s,
  /// about 20 s for a 900 px player and a 300 px barrage.
  static const Duration superChatDuration = Duration(seconds: 20);

  /// The notice when the live figures' `liveinfo.mute` turns true: the
  /// streamer paused the stream, which then shows a still picture without
  /// sound (measured 2026-09-30; viewers can still write). The website shows
  /// nothing for it.
  static const String mutedNotice = '主播暂停了直播（画面静止、没有声音）';

  /// The notice when it turns false again.
  static const String unmutedNotice = '主播恢复了直播';

  /// Largest time [DateTime] can hold, in milliseconds.
  static const int _maxMillis = 8640000000000000;

  /// Largest `connectionStateTtl` or `maxIdleInterval` taken: a day.
  static const int _maxDetailMillis = 86400000;

  static final RegExp _token = RegExp('^[\\x21-\\x7e]{1,$maxTokenLength}\$');
  static final RegExp _hexColor = RegExp(r'^(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

  /// The token request's headers: the platform's catalog headers (desktop
  /// UA, `Origin`, `Referer: https://17.live/`) and a JSON content type.
  static const Map<String, String> authHeaders = {
    ...SeventeenLiveApi.catalogHeaders,
    'content-type': 'application/json',
  };

  /// The token request: a POST of `{}` with [authHeaders], not following
  /// redirects.
  static LiveRequest authRequest({Duration timeout = defaultRequestTimeout, CancelToken? cancel}) => LiveRequest(
    site: SiteIds.seventeenLive,
    url: authUrl,
    method: 'POST',
    headers: authHeaders,
    body: utf8.encode('{}'),
    followRedirects: false,
    timeout: timeout,
    cancel: cancel,
  );

  /// The Ably token of a `messenger/auth` [response]
  /// (`{"provider":1,"token":…,"permissions":["*"]}`). Another provider
  /// throws [SeventeenLiveChatRefusal]; an answer that is not a 200 or not
  /// JSON throws its `SiteError`, one without a usable token (printable
  /// ASCII, at most [maxTokenLength]) [FormatException].
  static String grant(LiveResponse response) {
    final data = SeventeenLiveApi.decode(response.text, what: 'messenger/auth', status: response.status);
    if (data is! Map) throw const FormatException('messenger/auth: not an object');
    final provider = data['provider'];
    if (provider != ablyProvider) {
      throw SeventeenLiveChatRefusal(provider is String || provider is num ? '$provider' : '');
    }
    final token = data['token'];
    if (token is! String || !_token.hasMatch(token)) throw const FormatException('messenger/auth: no token');
    return token;
  }

  /// [endpoint] with the `access_token` [token] first, as ably-js orders it,
  /// and with a [resume] key the `resume` of the connection it names (B-14).
  static Uri withToken(Uri endpoint, String token, {String? resume}) =>
      endpoint.replace(queryParameters: {'access_token': token, 'resume': ?resume, ...endpoint.queryParameters});

  /// The `ATTACH` (10) of the channel [roomId]: as the recordings sent it,
  /// or, for a channel attached before ([resume]), with ably-js's
  /// `ATTACH_RESUME` flag and the last [channelSerial], from which the
  /// server sends what was missed (B-14).
  static String attach(String roomId, {String? channelSerial, bool resume = false}) => jsonEncode({
    'action': 10,
    'channel': roomId,
    'channelSerial': ?channelSerial,
    if (resume) 'flags': attachResumeFlag,
  });

  /// The `AUTH` (17) answering a server's request with [token] (ably-js's
  /// in-place reauthorisation).
  static String reauthorize(String token) => jsonEncode({
    'action': 17,
    'auth': {'accessToken': token},
  });

  /// Reads one frame of a chat socket for the room [roomId]: text, or
  /// UTF-8 bytes (malformed bytes become U+FFFD). The frame is one Ably
  /// protocol message, named by `action`:
  ///
  /// - 4 `CONNECTED`, 6 `DISCONNECTED`, 17 `AUTH`: [SeventeenLiveSignal]'s
  ///   `connected` (with its connection id, key and times, and the error of
  ///   a resume that failed), `disconnected` (with its `error`),
  ///   `reauthorize`;
  /// - 9 `ERROR`: of the room's channel when it names it
  ///   ([SeventeenLiveSignal.channelError]), of the connection when it names
  ///   none ([SeventeenLiveSignal.connectionError]);
  /// - 11 `ATTACHED` (its `channelSerial`, the `RESUMED` and `HAS_BACKLOG`
  ///   flags and an error), 13 `DETACHED` of the room's channel;
  /// - 15 `MESSAGE` of the room's channel: its `channelSerial` and its
  ///   `messages` ([entry]); a message's id is its `id`, or the frame's `id`
  ///   and its index (Ably's rule for messages without one). A comment
  ///   without its own time gets [now] (default: the current time) as its
  ///   super chat's start. With [backlogBefore] (when the `ATTACHED` that
  ///   announced a backlog came), the messages Ably published before it are
  ///   the backlog, replayed, up to the first that was published at it or
  ///   later (B-26);
  /// - 14 `PRESENCE` of the room's channel: its `channelSerial` only (ably-js
  ///   keeps it as the channel's).
  ///
  /// Anything else (the heartbeat 0, a presence `SYNC` 16, another
  /// channel, a frame that is not a JSON object) holds nothing. A field of
  /// the wrong type costs only that field or that message.
  static SeventeenLiveDanmakuFrame decode(
    Object? data, {
    required String roomId,
    DateTime? now,
    DateTime? backlogBefore,
  }) {
    final text = switch (data) {
      final String text => text,
      final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
      _ => null,
    };
    if (text == null) return const SeventeenLiveDanmakuFrame();
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException {
      return const SeventeenLiveDanmakuFrame();
    }
    if (root is! Map) return const SeventeenLiveDanmakuFrame();
    final channel = root['channel'];
    final ours = channel == roomId;
    final error = _error(root['error']);
    final serial = switch (root['channelSerial']) {
      final String serial when serial.isNotEmpty => serial,
      _ => null,
    };
    return switch (root['action']) {
      4 => SeventeenLiveDanmakuFrame(
        signal: SeventeenLiveSignal.connected,
        error: error,
        connection: _connection(root),
      ),
      6 => SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.disconnected, error: error),
      9 when channel == null => SeventeenLiveDanmakuFrame(
        signal: SeventeenLiveSignal.connectionError,
        error: error ?? const SeventeenLiveAblyError(code: 0),
      ),
      9 when ours => SeventeenLiveDanmakuFrame(
        signal: SeventeenLiveSignal.channelError,
        error: error ?? const SeventeenLiveAblyError(code: 0),
      ),
      11 when ours => SeventeenLiveDanmakuFrame(
        signal: SeventeenLiveSignal.attached,
        error: error,
        channelSerial: serial,
        resumed: switch (root['flags']) {
          final int flags => (flags & resumedFlag) != 0,
          _ => false,
        },
        backlog: switch (root['flags']) {
          final int flags => (flags & hasBacklogFlag) != 0,
          _ => false,
        },
      ),
      13 when ours => SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.detached, error: error),
      14 when ours => SeventeenLiveDanmakuFrame(channelSerial: serial),
      15 when ours => SeventeenLiveDanmakuFrame(
        entries: _entries(root, now ?? DateTime.now(), backlogBefore),
        channelSerial: serial,
      ),
      17 => const SeventeenLiveDanmakuFrame(signal: SeventeenLiveSignal.reauthorize),
      _ => const SeventeenLiveDanmakuFrame(),
    };
  }

  static SeventeenLiveConnectionDetails? _connection(Map<Object?, Object?> root) {
    final id = root['connectionId'];
    final details = root['connectionDetails'];
    if (id is! String || id.isEmpty || details is! Map) return null;
    final key = details['connectionKey'];
    if (key is! String || key.isEmpty) return null;
    Duration? millis(Object? value) =>
        value is int && value > 0 && value <= _maxDetailMillis ? Duration(milliseconds: value) : null;
    return SeventeenLiveConnectionDetails(
      id: id,
      key: key,
      stateTtl: millis(details['connectionStateTtl']) ?? defaultConnectionStateTtl,
      maxIdleInterval: millis(details['maxIdleInterval']) ?? heartbeatInterval,
    );
  }

  static SeventeenLiveAblyError? _error(Object? value) {
    if (value is! Map) return null;
    final code = value['code'];
    final status = value['statusCode'];
    final message = value['message'];
    return SeventeenLiveAblyError(
      code: code is int ? code : 0,
      statusCode: status is int ? status : null,
      message: message is String ? message.trim() : '',
    );
  }

  static List<SeventeenLiveEntry> _entries(Map<Object?, Object?> root, DateTime now, DateTime? backlogBefore) {
    final messages = root['messages'];
    if (messages is! List) return const [];
    final frameId = root['id'];
    final frameTime = _millis(root['timestamp']);
    var backlog = backlogBefore != null;
    final entries = <SeventeenLiveEntry>[];
    for (final (index, item) in messages.indexed) {
      if (item is! Map) continue;
      final decoded = payload(item['data']);
      if (decoded == null) continue;
      final published = _millis(item['timestamp']) ?? frameTime;
      // The backlog ends at the first message published at the attach or
      // later; one without a time cannot tell.
      if (backlog && published != null && !published.isBefore(backlogBefore!)) backlog = false;
      entries.add(
        entry(
          decoded,
          id: switch (item['id']) {
            final String id when id.isNotEmpty => id,
            _ => frameId is String && frameId.isNotEmpty ? '$frameId:$index' : '',
          },
          now: now,
          publishedAt: published,
          replayed: backlog && published != null,
        ),
      );
    }
    return entries;
  }

  /// A time in milliseconds from the epoch, above zero and within
  /// [DateTime]'s range, or null.
  static DateTime? _millis(Object? value) =>
      value is int && value > 0 && value <= _maxMillis ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  /// A decoded [payload] with the Ably message [id] (B-14):
  ///
  /// - a comment: its chat line ([message]), then, for a paid barrage, its
  ///   super chat ([superChat]), which starts at [now] when the comment has
  ///   no time of its own;
  /// - the live figures: the viewers now ([message]) and `liveinfo.mute`
  ///   when it is a boolean;
  /// - the stream end ([streamEndType]): [SeventeenLiveEntry.ended];
  /// - anything else: nothing.
  ///
  /// [publishedAt] is when Ably published it; a [replayed] one (a backlog,
  /// B-26) has its messages marked so.
  static SeventeenLiveEntry entry(
    Map<Object?, Object?> payload, {
    String id = '',
    DateTime? now,
    DateTime? publishedAt,
    bool replayed = false,
  }) {
    final shown = message(payload, id: id, replayed: replayed);
    return switch (payload['type']) {
      commentType => SeventeenLiveEntry(
        id: id,
        publishedAt: publishedAt,
        replayed: replayed,
        messages: [
          ?shown,
          ?superChat(payload, id: id, now: now, replayed: replayed),
        ],
      ),
      liveType => SeventeenLiveEntry(
        id: id,
        publishedAt: publishedAt,
        replayed: replayed,
        messages: [?shown],
        muted: switch (payload['liveinfo']) {
          {'mute': final bool muted} => muted,
          _ => null,
        },
      ),
      streamEndType => SeventeenLiveEntry(id: id, publishedAt: publishedAt, replayed: replayed, ended: true),
      _ => SeventeenLiveEntry(id: id, publishedAt: publishedAt, replayed: replayed),
    };
  }

  /// The super chat of a paid barrage (B-14): a comment the website shows
  /// ([message]) whose `barrageStyle` is true and whose `barrage.point`, the
  /// baby coins it cost, is above zero. The website flies such a comment
  /// over the player besides its chat line; the ones that cost no coins
  /// (`point` 0: the platform's army and welcome lines, type 5, the
  /// streamer assistant's, type 4, and barrages from the sender's stock,
  /// with a `count`) stay chat only. Null for anything else.
  ///
  /// - The text is what the website flies: `comment.text` with line breaks
  ///   as spaces, trimmed (`content` without it); the name, user id and
  ///   message id are the chat line's.
  /// - [LiveSuperChatMessage.price] is the point, [LiveSuperChatMessage.priceText]
  ///   the website's `{point} coins` (`barrage_send_point` in English and
  ///   Japanese).
  /// - It starts at `sendTime` ([now], default the current time, without
  ///   one) and lasts [superChatDuration].
  /// - Both colours are the comment's own `backgroundColor`, the background
  ///   the website paints its chat line with (`#AARRGGBB`, given as
  ///   `#RRGGBB`; empty when it has none that reads, [backgroundColor]).
  /// - The face is the sender's `picture` as the website shows it
  ///   (`https://cdn.17app.co/THUMBNAIL_<file>`, or its own URL on the
  ///   platform's hosts; `SeventeenLiveApi.image`).
  /// - It is [replayed] as its chat line is (B-26).
  static LiveMessage? superChat(Map<Object?, Object?> payload, {String id = '', DateTime? now, bool replayed = false}) {
    if (payload['type'] != commentType) return null;
    final chat = message(payload, id: id);
    final comment = payload['commentMsg'];
    if (chat == null || comment is! Map) return null;
    final barrage = comment['barrage'];
    final point = barrage is Map ? barrage['point'] : null;
    if (comment['barrageStyle'] != true || point is! int || point <= 0) return null;
    final body = comment['comment'];
    var text = (body is Map ? _string(body['text']) : '').replaceAll('\n', ' ').trim();
    if (text.isEmpty) text = chat.message;
    final fill = backgroundColor(comment['backgroundColor']);
    final user = comment['displayUser'];
    final picture = user is Map ? _string(user['picture']) : '';
    final start = chat.sentAt ?? now ?? DateTime.now();
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: chat.userName,
      userId: chat.userId,
      message: text,
      color: LiveMessageColor.white,
      messageId: id,
      sentAt: chat.sentAt,
      replayed: replayed,
      data: LiveSuperChatMessage(
        messageId: id,
        userName: chat.userName,
        face: picture.isEmpty
            ? ''
            : SeventeenLiveApi.image(
                picture.startsWith('http://') || picture.startsWith('https://') ? picture : 'THUMBNAIL_$picture',
              ),
        message: text,
        price: point,
        priceText: '$point coins',
        startTime: start,
        endTime: start.add(superChatDuration),
        backgroundColor: fill,
        backgroundBottomColor: fill,
      ),
    );
  }

  /// The system notice of the live figures' `liveinfo.mute` turning [muted]
  /// (B-14: [mutedNotice], [unmutedNotice]), with the Ably message [id];
  /// [replayed] when that message was (B-26).
  static LiveMessage muteNotice({required bool muted, String id = '', bool replayed = false}) => LiveMessage(
    type: LiveMessageType.notice,
    userName: '',
    message: muted ? mutedNotice : unmutedNotice,
    color: LiveMessageColor.white,
    messageId: id,
    data: LiveNoticeKind.system,
    replayed: replayed,
  );

  /// A message's `data`: base64 of gzipped UTF-8 JSON, as the website reads
  /// it (`gzip_base64`); null when it is not that or not a JSON object.
  static Map<Object?, Object?>? payload(Object? data) {
    if (data is! String || data.isEmpty) return null;
    try {
      final value = jsonDecode(utf8.decode(gzip.decode(base64.decode(data))));
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// The message a decoded [payload] shows, with the Ably message [id]; null
  /// for every other type (gifts, reactions, entries, rankings, missions…).
  ///
  /// - A comment ([commentType], `commentMsg`) is chat, unless the website
  ///   hides it: `isDirty`, `isDirtyWord` or `isDirtyUser` is true. The text
  ///   is `content` (what the website shows; `comment.text` when it has
  ///   none), trimmed; a blank one shows nothing. The name is
  ///   `displayUser.displayName` (its `openID` without one), the user id
  ///   `displayUser.userID`, the level `displayUser.level` (`commentMsg`'s
  ///   without one), the colour `comment.textColor` ([color]) and the time
  ///   `sendTime` (milliseconds; not above zero or beyond [DateTime]: none).
  ///   The name's colour is `name.textColor` ([nameColor]) and the badges
  ///   the website draws by the name are [badges] (B-14).
  ///   A barrage (a comment that also flies over the video on the website)
  ///   is chat as well; a paid one also has a super chat ([superChat]).
  /// - The live figures ([liveType]) carry `liveinfo.liveViewerCount`, the
  ///   viewers now, which the website shows: an audience update.
  ///
  /// [replayed] marks a message of a backlog (B-26).
  static LiveMessage? message(Map<Object?, Object?> payload, {String id = '', bool replayed = false}) {
    switch (payload['type']) {
      case commentType:
        final comment = payload['commentMsg'];
        if (comment is! Map) return null;
        if (comment['isDirty'] == true || comment['isDirtyWord'] == true || comment['isDirtyUser'] == true) {
          return null;
        }
        final body = comment['comment'];
        var text = _string(comment['content']).trim();
        if (text.isEmpty && body is Map) text = _string(body['text']).trim();
        if (text.isEmpty) return null;
        final user = comment['displayUser'];
        final name = user is Map ? _string(user['displayName']) : '';
        final level = _level(user is Map ? user['level'] : null) ?? _level(comment['level']);
        return LiveMessage(
          type: LiveMessageType.chat,
          userName: name.isNotEmpty || user is! Map ? name : _string(user['openID']),
          userId: user is Map ? _string(user['userID']) : '',
          message: text,
          color: color(body is Map ? body['textColor'] : null),
          userLevel: level == null ? '' : '$level',
          messageId: id,
          sentAt: _millis(comment['sendTime']),
          replayed: replayed,
          nameColor: nameColor(comment['name']),
          badges: badges(comment),
        );
      case liveType:
        final info = payload['liveinfo'];
        final viewers = info is Map ? info['liveViewerCount'] : null;
        if (viewers is! int || viewers < 0) return null;
        return LiveMessage(
          type: LiveMessageType.online,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
          replayed: replayed,
        );
      default:
        return null;
    }
  }

  /// A comment colour: `#AARRGGBB` (the alpha first, as the website reads
  /// it) or `#RRGGBB`, the `#` optional; anything else is white, the
  /// website's default.
  static LiveMessageColor color(Object? value) {
    if (value is! String) return LiveMessageColor.white;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!_hexColor.hasMatch(hex)) return LiveMessageColor.white;
    return LiveMessageColor.numberToColor(int.parse(hex.substring(hex.length - 6), radix: 16));
  }

  /// The colour of a comment's sender name (B-14): `name.textColor` read
  /// as [color] reads a text colour; null when the comment has none that
  /// reads (the website then draws its default).
  static LiveMessageColor? nameColor(Object? name) {
    final value = name is Map ? name['textColor'] : null;
    if (value is! String) return null;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    return _hexColor.hasMatch(hex) ? color(hex) : null;
  }

  /// The places of a comment's badges, in the order the comment names them
  /// around the sender's name (`prefixBadges` holds the prefix badges, and
  /// the single `prefixBadge` is one of them when set).
  static const List<String> badgeFields = [
    'prefixBadge',
    'middleBadge',
    'roleBadge',
    'attendanceBadge',
    'mLevelBadge',
    'topRightBadge',
  ];

  /// The badges of a comment (B-14): `{URL, styleID}` objects, the prefix
  /// badges (`prefixBadges`, then `prefixBadge`) first and the others in
  /// [badgeFields] order. A badge without a picture, or with one off the
  /// platform's hosts, is left out (`SeventeenLiveApi.image`, made https);
  /// a picture named twice is shown once.
  static List<LiveBadge> badges(Map<Object?, Object?> comment) {
    final seen = <String>{};
    final result = <LiveBadge>[];
    void add(Object? badge) {
      if (badge is! Map) return;
      final url = SeventeenLiveApi.image(badge['URL']);
      if (url.isEmpty || !seen.add(url)) return;
      result.add(LiveBadge(url: url, id: _string(badge['styleID']).trim()));
    }

    final prefixes = comment['prefixBadges'];
    if (prefixes is List) prefixes.take(badgeLimit).forEach(add);
    for (final field in badgeFields) {
      add(comment[field]);
    }
    return List.unmodifiable(result);
  }

  /// The most prefix badges read from one comment.
  static const int badgeLimit = 16;

  /// A comment's `backgroundColor` as `#RRGGBB` (upper case; the alpha of
  /// `#AARRGGBB` dropped, the `#` optional), or empty for anything else.
  static String backgroundColor(Object? value) {
    if (value is! String) return '';
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!_hexColor.hasMatch(hex)) return '';
    return '#${hex.substring(hex.length - 6).toUpperCase()}';
  }

  static int? _level(Object? value) => value is int && value > 0 ? value : null;

  static String _string(Object? value) => value is String ? value : '';
}

/// 17LIVE's danmaku connection: an anonymous Ably token over [LiveHttp],
/// then Ably's JSON realtime protocol over the shared WebSocket runtime.
///
/// - The token is asked in the handshake (as M5.11 and M5.21 do): the first
///   handshake of a [connect] asks `messenger/auth`, later ones reuse the
///   token until the server refuses it. A failed request fails that
///   handshake (the runtime's backoff and eight attempts); another
///   provider than Ably ends the run with [DanmakuCloseReason.connectionFailed].
/// - The sockets are the primary host and the website's three fallback
///   hosts, rotated on failure. At `CONNECTED` the room's channel is
///   attached; `ATTACHED` joins it, and an attach unanswered for 10 s drops
///   the socket.
/// - A later socket of the run resumes as ably-js does (B-14): its
///   handshake has `resume` with the last `CONNECTED`'s key, and its
///   `ATTACH` the last `channelSerial` and the `ATTACH_RESUME` flag, so the
///   server sends the messages missed meanwhile. A resume that fails (a new
///   connection id, 80018) or a channel that cannot go on from the serial
///   (90003) is attached all the same and shows what the server sends. A
///   message whose Ably id was already reported in the run is not reported
///   again. After more than `connectionStateTtl` + `maxIdleInterval` (135 s)
///   without a frame the key and the serial are forgotten, as ably-js
///   forgets a stale connection, and the next socket starts afresh; an
///   attach unanswered in time forgets the serial (ably-js suspends the
///   channel).
/// - The server sends heartbeats every 15 s and the client none; a socket
///   silent for 25 s is replaced.
/// - A token error (`ERROR` or `DISCONNECTED`, 40140 to 40149) drops the
///   token and the socket; the next handshake asks a new one. The fourth in
///   a row without an attach between ends the run with
///   [DanmakuCloseReason.connectionFailed]. Any other connection `ERROR` or
///   a channel `ERROR` ends it as well (ably-js fails the connection or the
///   channel); another `DISCONNECTED` reconnects.
/// - A server-sent `DETACHED` attaches the channel again on the same
///   socket, from the last serial; a second one before it is attached, or no
///   answer within 10 s, drops the socket. It counts as a refusal like a
///   token error. A server-sent `AUTH` asks a new token and sends it on the
///   same socket.
/// - The stream end (5) ends the run with [DanmakuCloseReason.connectionFailed]
///   (`Broadcast ended`), as the website leaves the channel then (B-14). The
///   live figures' `liveinfo.mute` turning true (the streamer paused the
///   stream), or false again after that, is a system notice
///   ([SeventeenLiveDanmakuProtocol.muteNotice]). While paused, and in the
///   figures that end the pause, a count of 0 viewers is not reported: the
///   last count stays (B-25).
/// - The messages of a backlog an `ATTACHED` announces (`HAS_BACKLOG`: after
///   a resume, what was missed; when it could not resume, the recent ones)
///   are [LiveMessage.replayed], up to the first message Ably published at
///   the attach or later, so the duplicate gate shows them for as long as a
///   resume reaches back (B-26).
///
/// [SeventeenLiveDanmakuArgs.roomId] is the channel. The app registers it
/// as `SiteIds.seventeenLive: () => SeventeenLiveDanmakuConnection(http: …,
/// proxy: …)`, with the `LiveHttp` it gives `SeventeenLiveSite` and its
/// proxy policy.
final class SeventeenLiveDanmakuConnection extends DanmakuSocketConnection<SeventeenLiveDanmakuArgs> {
  /// Creates the connection. [http] asks `messenger/auth` for tokens;
  /// [proxy] routes the socket; [connector] replaces `dart:io`'s handshake,
  /// [policy] the timing and [now] the clock (tests).
  factory({
    required LiveHttp http,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    DanmakuSocketPolicy policy = defaultPolicy,
    DateTime Function()? now,
  }) => SeventeenLiveDanmakuConnection._(
    _Handshake(http, connector ?? connectIoSocket, now ?? DateTime.now),
    proxy: proxy,
    policy: policy,
  );

  new _(this._handshake, {required super.proxy, required super.policy})
    : super(site: SiteIds.seventeenLive, connector: _handshake.call);

  /// The platform's timing: the server's 15 s heartbeat as the watchdog's
  /// tick, 25 s of silence and 10 s for the attach; the runtime's defaults
  /// otherwise.
  static const DanmakuSocketPolicy defaultPolicy = DanmakuSocketPolicy(
    heartbeatInterval: SeventeenLiveDanmakuProtocol.heartbeatInterval,
    inactivityTimeout: SeventeenLiveDanmakuProtocol.inactivityTimeout,
    joinTimeout: SeventeenLiveDanmakuProtocol.joinTimeout,
  );

  /// The detail of the run's end at the stream end.
  static const String broadcastEnded = 'Broadcast ended';

  static final DanmakuSocketTarget _target = DanmakuSocketTarget(
    endpoints: SeventeenLiveDanmakuProtocol.endpoints,
    headers: SeventeenLiveDanmakuProtocol.handshakeHeaders,
  );

  final _Handshake _handshake;

  @override
  @protected
  Future<DanmakuSocketTarget> target(SeventeenLiveDanmakuArgs args, DanmakuRun run) async {
    final roomId = SeventeenLiveApi.normalizeRoomId(args.roomId);
    if (roomId == null) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No usable room id');
    }
    _handshake.chat = _Chat(run, roomId);
    return _target;
  }

  _Chat? _of(DanmakuSocketSession session) {
    final chat = _handshake.chat;
    return chat != null && identical(chat.run, session.run) ? chat : null;
  }

  @override
  @protected
  void onOpen(DanmakuSocketSession session) {
    _of(session)
      ?..socketReset()
      ..sockets += 1;
  }

  @override
  @protected
  void onData(DanmakuSocketSession session, Object? data) {
    final chat = _of(session);
    if (chat == null) return;
    final now = _handshake.now();
    chat.lastActivity = now;
    final frame = SeventeenLiveDanmakuProtocol.decode(
      data,
      roomId: chat.roomId,
      now: now,
      backlogBefore: chat.backlogBefore,
    );
    if (frame.channelSerial case final serial?) chat.channelSerial = serial;
    switch (frame.signal) {
      case SeventeenLiveSignal.none:
        break;
      case SeventeenLiveSignal.connected:
        if (frame.connection case final connection?) chat.connection = connection;
        _attach(session, chat);
      case SeventeenLiveSignal.attached:
        chat
          ..refusals = 0
          ..attachPending = false
          ..attachedBefore = true
          ..reattaching = false
          // A backlog follows: what Ably published before now (B-26).
          ..backlogBefore = frame.backlog ? now : null
          ..reattachWatch?.cancel();
        if (session.isConnected) {
          session.cancelJoinTimeout();
        } else {
          session.ready();
        }
      case SeventeenLiveSignal.detached:
        _detached(session, chat, frame.error);
      case SeventeenLiveSignal.disconnected:
        if (frame.error case final error? when error.isTokenError) {
          _tokenRefused(session, chat, error);
        } else {
          session.reconnect();
        }
      case SeventeenLiveSignal.connectionError:
        final error = frame.error!;
        if (error.isTokenError) {
          _tokenRefused(session, chat, error);
        } else {
          session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Ably error $error');
        }
      case SeventeenLiveSignal.channelError:
        session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Channel refused: ${frame.error}');
      case SeventeenLiveSignal.reauthorize:
        unawaited(_reauthorize(session, chat));
    }
    // The backlog is over once a message published at the attach or later
    // came (B-26).
    if (frame.entries.any((entry) => entry.publishedAt != null && !entry.replayed)) chat.backlogBefore = null;
    for (final entry in frame.entries) {
      if (!session.isActive) return;
      // A message sent again after a resume, or twice: reported once.
      if (entry.id.isNotEmpty && !chat.firstSight(entry.id)) continue;
      // While the stream is paused (and in the figures that end the pause)
      // the viewers are 0; the last count stays (B-25).
      final paused = chat.muted == true || entry.muted == true;
      for (final message in entry.messages) {
        if (!session.isActive) return;
        if (message.data case LiveAudienceUpdate(value: 0) when paused) continue;
        session.message(message);
      }
      if (entry.muted case final muted?) {
        if (chat.muteNotice(muted: muted, id: entry.id, replayed: entry.replayed) case final notice?) {
          session.message(notice);
        }
      }
      if (entry.ended) {
        session.run.closed(DanmakuCloseReason.connectionFailed, detail: broadcastEnded);
        return;
      }
    }
  }

  /// Attaches the room's channel: after an earlier attach of the run, from
  /// the last serial with the `ATTACH_RESUME` flag (ably-js).
  void _attach(DanmakuSocketSession session, _Chat chat) {
    chat.attachPending = true;
    session.send(
      SeventeenLiveDanmakuProtocol.attach(chat.roomId, channelSerial: chat.channelSerial, resume: chat.attachedBefore),
    );
  }

  /// The attach went unanswered (or the socket never said `CONNECTED`):
  /// a new socket. An attach sent and not answered forgets the serial, as
  /// ably-js suspends the channel.
  @override
  @protected
  void onJoinTimeout(DanmakuSocketSession session) {
    final chat = _of(session);
    if (chat != null && chat.attachPending) chat.channelSerial = null;
    super.onJoinTimeout(session);
  }

  /// The server detached the channel: attach it again on this socket, as
  /// ably-js does; a detach while that attach is pending, or no answer
  /// within the join limit, drops the socket and the serial. A detach is a
  /// refusal: one too many ends the run.
  void _detached(DanmakuSocketSession session, _Chat chat, SeventeenLiveAblyError? error) {
    if (++chat.refusals > SeventeenLiveDanmakuProtocol.maxRefusals) {
      session.run.closed(
        DanmakuCloseReason.connectionFailed,
        detail: error == null ? 'Channel detached' : 'Channel detached: $error',
      );
      return;
    }
    if (chat.reattaching) {
      chat.channelSerial = null;
      session.reconnect();
      return;
    }
    chat.reattaching = true;
    final sockets = chat.sockets;
    chat.reattachWatch = Timer(policy.joinTimeout ?? SeventeenLiveDanmakuProtocol.joinTimeout, () {
      if (session.isActive && chat.reattaching && chat.sockets == sockets) {
        chat.channelSerial = null;
        session.reconnect();
      }
    });
    _attach(session, chat);
  }

  /// The server refused the token: drop it (the next handshake asks a new
  /// one) and the socket, unless this is one refusal too many.
  void _tokenRefused(DanmakuSocketSession session, _Chat chat, SeventeenLiveAblyError error) {
    chat.token = null;
    if (++chat.refusals > SeventeenLiveDanmakuProtocol.maxRefusals) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: 'Token refused: $error');
      return;
    }
    session.reconnect();
  }

  /// The server asked for a new token: ask `messenger/auth` and send it on
  /// the same socket. A failure is left to the server, which drops the
  /// socket with a token error when the old token lapses.
  Future<void> _reauthorize(DanmakuSocketSession session, _Chat chat) async {
    final sockets = chat.sockets;
    final String token;
    try {
      token = await _handshake.renew(chat, timeout: policy.connectTimeout);
    } on Object {
      return;
    }
    if (session.isActive && chat.sockets == sockets) session.send(SeventeenLiveDanmakuProtocol.reauthorize(token));
  }

  @override
  @protected
  Future<void> stop() async {
    _handshake.chat?.dispose();
    _handshake.chat = null;
    await super.stop();
  }
}

/// The handshake of a [SeventeenLiveDanmakuConnection]: asks
/// `messenger/auth` for a token first when the run has none, then connects
/// with it, resuming the run's connection while it is fresh (B-14). A
/// failed handshake's message has the token and the key blanked out.
final class _Handshake {
  new(this._http, this._connect, this.now);

  final LiveHttp _http;
  final SocketConnector _connect;

  /// The clock.
  final DateTime Function() now;

  /// The current run's chat.
  _Chat? chat;

  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    final chat = this.chat;
    if (chat == null || !chat.run.isActive) throw StateError('The chat was closed');
    final token = chat.token ?? await renew(chat, timeout: connectTimeout);
    final resume = chat.resumeKey(now());
    try {
      return await _connect(
        SeventeenLiveDanmakuProtocol.withToken(endpoint, token, resume: resume),
        headers: headers,
        protocols: protocols,
        route: route,
        connectTimeout: connectTimeout,
      );
    } on Object catch (error) {
      var message = '$error';
      for (final (secret, mark) in [(token, '<token>'), if (resume != null) (resume, '<key>')]) {
        message = message.replaceAll(Uri.encodeQueryComponent(secret), mark).replaceAll(secret, mark);
      }
      throw _HandshakeFailure(message);
    }
  }

  /// Asks `messenger/auth` for a token of [chat] and keeps it. Another
  /// provider ends the run; every failure is thrown.
  Future<String> renew(_Chat chat, {required Duration timeout}) async {
    final response = await _http.send(SeventeenLiveDanmakuProtocol.authRequest(timeout: timeout, cancel: chat.cancel));
    final String token;
    try {
      token = SeventeenLiveDanmakuProtocol.grant(response);
    } on SeventeenLiveChatRefusal catch (refusal) {
      chat.run.closed(DanmakuCloseReason.connectionFailed, detail: '$refusal');
      rethrow;
    }
    if (!chat.run.isActive) throw StateError('The chat was closed');
    return chat.token = token;
  }
}

/// A failed handshake, its message without the token.
final class _HandshakeFailure implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One run's chat: the room, its token, what a later socket resumes and the
/// state of the current socket.
final class _Chat {
  new(this.run, this.roomId) {
    unawaited(run.ended.then((_) => dispose()));
  }

  /// Ably message ids remembered to report each message once.
  static const int maxSeen = 4096;

  final DanmakuRun run;

  /// The room id, the channel's name.
  final String roomId;
  final CancelToken cancel = CancelToken();

  /// The token of the next handshake; null asks a new one.
  String? token;

  /// The last `CONNECTED`'s connection: what the next socket resumes.
  SeventeenLiveConnectionDetails? connection;

  /// The room channel's last serial: where the next attach resumes from.
  String? channelSerial;

  /// When the last frame came.
  DateTime? lastActivity;

  /// Whether the channel was attached in this run (`ATTACH_RESUME`).
  bool attachedBefore = false;

  /// Whether an attach of the current socket awaits its `ATTACHED`.
  bool attachPending = false;

  /// The live figures' last `liveinfo.mute`, or null before the first.
  bool? muted;

  /// When the `ATTACHED` that announced a backlog came, until a message
  /// published at it or later ends the backlog (B-26); null otherwise.
  DateTime? backlogBefore;

  final LinkedHashSet<String> _seen = LinkedHashSet();

  /// Token refusals and detaches since the channel was last attached.
  int refusals = 0;

  /// Sockets opened so far.
  int sockets = 0;

  /// Whether a server-sent detach is being answered with an attach.
  bool reattaching = false;

  /// The limit of that attach.
  Timer? reattachWatch;

  /// The key the next handshake resumes at [now], or null. A connection
  /// silent for longer than its `connectionStateTtl` + `maxIdleInterval` is
  /// forgotten with the channel's serial, as ably-js discards stale state
  /// and suspends the channel.
  String? resumeKey(DateTime now) {
    final connection = this.connection;
    final last = lastActivity;
    if (connection == null || last == null) return null;
    if (now.difference(last) > connection.stateTtl + connection.maxIdleInterval) {
      this.connection = null;
      channelSerial = null;
      return null;
    }
    return connection.key;
  }

  /// Whether the message [id] is new in this run; remembers it.
  bool firstSight(String id) {
    if (!_seen.add(id)) return false;
    if (_seen.length > maxSeen) _seen.remove(_seen.first);
    return true;
  }

  /// The notice for the live figures' `liveinfo.mute` being [muted], or null
  /// when it did not change (or is false the first time).
  LiveMessage? muteNotice({required bool muted, required String id, bool replayed = false}) {
    final before = this.muted;
    this.muted = muted;
    if (before == muted || (before == null && !muted)) return null;
    return SeventeenLiveDanmakuProtocol.muteNotice(muted: muted, id: id, replayed: replayed);
  }

  /// A new socket: nothing attached, no attach pending, no backlog.
  void socketReset() {
    attachPending = false;
    reattaching = false;
    backlogBefore = null;
    reattachWatch?.cancel();
    reattachWatch = null;
  }

  void dispose() {
    socketReset();
    cancel.cancel();
  }
}
