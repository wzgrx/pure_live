import 'dart:async';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';

/// What one Huya server frame held: its messages in order, and how many
/// headline (super chat) notices (uri 2001314) it carried.
typedef HuyaDanmakuFrame = ({List<LiveMessage> messages, int superChatNotices});

/// Huya's danmaku protocol (the codec of 3.x `HuyaDanmaku`), without I/O.
///
/// Every frame is a Tars structure: tag 0 the command, tag 1 its payload
/// bytes. The client registers the streamer's groups (command 16) and sends
/// heartbeats (command 20); the server pushes single messages (command 7:
/// tag 1 uri, tag 2 body, tag 5 message id) and batches (command 22: tag 0
/// group, tag 1 items of tag 0 uri, tag 1 body, tag 2 message id). Chat is
/// uri 1400, popularity uri 8006, and uri 2001314 announces a new headline
/// on the message board.
abstract final class HuyaDanmakuProtocol {
  /// The only endpoint (3.x `serverUrl`).
  static final Uri endpoint = Uri.parse('wss://wsapi.huya.com');

  /// Heartbeat period (3.x `heartbeatTime`, 60 000 ms).
  static const Duration heartbeatInterval = Duration(seconds: 60);

  /// `EWSCmdC2S_RegisterGroupReq`.
  static const int registerCommand = 16;

  /// `EWSCmdC2S_HeartBeatReq`.
  static const int heartbeatCommand = 20;

  /// A single push (`WSPushMessage`).
  static const int pushCommand = 7;

  /// A batch of pushes for one group (`WSPushMessage_V2`).
  static const int batchCommand = 22;

  /// Chat (`MessageNotice`).
  static const int chatUri = 1400;

  /// Popularity (`AttendeeCountNotice`): a heat figure, not concurrent
  /// viewers (REG-HUYA-014).
  static const int popularityUri = 8006;

  /// A new headline (super chat) on the room's message board; the body is
  /// not read, the board is fetched instead.
  static const int superChatUri = 2001314;

  /// Waits before each board fetch after a headline notice (3.x
  /// `defaultSuperChatRetryDelays`): the notice can arrive before the board
  /// has the entry.
  static const List<Duration> superChatRetryDelays = [
    Duration.zero,
    Duration(milliseconds: 600),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 4000),
  ];

  /// Longest wait for one board fetch (3.x's `timeout` around it).
  static const Duration superChatTimeout = Duration(seconds: 3);

  /// Board entries remembered per connection to report each only once (3.x
  /// `_maxRememberedSuperChats`).
  static const int maxRememberedSuperChats = 512;

  /// The groups a connection registers for streamer [uid].
  static List<String> groups(int uid) => ['live:$uid', 'chat:$uid'];

  /// Command 16 registering [groups] of streamer [uid] (3.x `getJoinData`):
  /// the payload is tag 0 the group list, tag 1 an empty token.
  static Uint8List register(int uid) {
    final payload = TarsWriter()
      ..writeList<String>(0, groups(uid), (writer, group) => writer.writeString(0, group))
      ..writeString(1, '');
    return (TarsWriter()
          ..writeInt(0, registerCommand)
          ..writeBytes(1, payload.toBytes()))
        .toBytes();
  }

  /// Command 20 with an empty payload (3.x `heartbeatData`).
  static Uint8List heartbeat() =>
      (TarsWriter()
            ..writeInt(0, heartbeatCommand)
            ..writeBytes(1, const []))
          .toBytes();

  /// The messages of one server [frame] (3.x `decodeMessage`): chat and
  /// popularity from commands 7 and 22, and the count of headline notices.
  /// Other commands and uris are ignored; a frame that is not Tars gives
  /// nothing, and an item whose body fails to decode is skipped without
  /// losing the others.
  static HuyaDanmakuFrame decode(List<int> frame) {
    final messages = <LiveMessage>[];
    var notices = 0;
    void item(int uri, Uint8List? body, int eventId) {
      if (uri == superChatUri) {
        notices++;
        return;
      }
      try {
        final message = switch (uri) {
          chatUri => _chat(body, eventId),
          popularityUri => _popularity(body, eventId),
          _ => null,
        };
        if (message != null) messages.add(message);
      } on FormatException {
        // 3.x lost the rest of the frame with the malformed item.
      }
    }

    try {
      final outer = TarsStruct.decode(frame);
      final payload = outer.bytes(1);
      switch (outer.integer(0)) {
        case pushCommand:
          final push = TarsStruct.decode(payload ?? const []);
          // M5.F B-4: 3.x left single pushes without an id.
          item(push.integer(1) ?? 0, push.bytes(2), push.integer(5) ?? 0);
        case batchCommand:
          final batch = TarsStruct.decode(payload ?? const []);
          for (final entry in batch.list(1)) {
            if (entry is! TarsStruct) continue;
            item(entry.integer(0) ?? 0, entry.bytes(1), entry.integer(2) ?? 0);
          }
      }
    } on FormatException {
      // A frame that is not Tars: 3.x logged it and dropped the frame.
    }
    return (messages: messages, superChatNotices: notices);
  }

  /// The colour of a chat's `iFontColor`: 0 or less (-1 is the default) is
  /// white, anything else goes through [LiveMessageColor.numberToColor].
  static LiveMessageColor color(int fontColor) =>
      fontColor <= 0 ? LiveMessageColor.white : LiveMessageColor.numberToColor(fontColor);

  /// The message 3.x reported for one board entry.
  static LiveMessage superChatMessage(LiveSuperChatMessage data) => LiveMessage(
    type: LiveMessageType.superChat,
    userName: 'SUPER_CHAT_MESSAGE',
    message: 'SUPER_CHAT_MESSAGE',
    color: LiveMessageColor.white,
    data: data,
  );

  /// The message id of a push (`huya:{id}`): its `lMsgId`, tag 5 of a single
  /// push and tag 2 of a batch item. It is the same on every connection to
  /// the room, and the web client drops a push whose `lMsgId` it has seen
  /// (taf-signal `filterMessage`); 0 or less means none.
  static String _messageId(int eventId) => eventId > 0 ? 'huya:$eventId' : '';

  /// uri 1400 (`MessageNotice`): tag 0 the sender (tag 0 uid, tag 2 nick),
  /// tag 3 the text, tag 6 the bullet format (tag 0 colour). Missing fields
  /// read as 3.x's defaults (uid 0, empty strings, colour 0).
  static LiveMessage _chat(Uint8List? body, int eventId) {
    final notice = TarsStruct.decode(body ?? const []);
    final sender = notice.struct(0);
    return LiveMessage(
      type: LiveMessageType.chat,
      color: color(notice.struct(6)?.integer(0) ?? 0),
      message: notice.string(3) ?? '',
      userName: sender?.string(2) ?? '',
      userId: '${sender?.integer(0) ?? 0}',
      messageId: _messageId(eventId),
    );
  }

  /// uri 8006 (`AttendeeCountNotice`): tag 0 `iAttendeeCount`, 0 when
  /// missing.
  static LiveMessage _popularity(Uint8List? body, int eventId) => LiveMessage(
    type: LiveMessageType.online,
    data: LiveAudienceUpdate(
      kind: LiveAudienceMetricKind.popularity,
      value: TarsStruct.decode(body ?? const []).integer(0) ?? 0,
    ),
    color: LiveMessageColor.white,
    message: '',
    userName: '',
    messageId: _messageId(eventId),
  );
}

/// Huya's danmaku connection (3.x `HuyaDanmaku`): one anonymous WebSocket
/// to [HuyaDanmakuProtocol.endpoint] without extra headers. An open socket
/// counts as joined; the group registration and one heartbeat follow, a
/// heartbeat goes out every 60 s, and a socket silent for 180 s is replaced.
///
/// A headline notice fetches the room's message board in the background
/// through `HuyaDanmakuArgs.superChats` (the `HuyaSite` that built the
/// arguments owns the HTTP client): at once, then after 0.6, 1.8 and 4 more
/// seconds; every entry not seen before on this connection is reported once.
///
/// The app registers it as `SiteIds.huya: () => HuyaDanmakuConnection(proxy:
/// …)`.
final class HuyaDanmakuConnection extends DanmakuSocketConnection<HuyaDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake (tests).
  new({super.proxy, super.connector}) : super(site: SiteIds.huya, policy: socketPolicy);

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 60 s heartbeat,
  /// so a socket silent for max(3 × 60 s, 90 s) = 180 s is replaced. No join
  /// timer: 3.x counted an open socket as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: HuyaDanmakuProtocol.heartbeatInterval,
  );

  int _uid = 0;
  _HuyaSuperChats? _superChats;

  @override
  Future<DanmakuSocketTarget> target(HuyaDanmakuArgs args, DanmakuRun run) async {
    _uid = args.uid;
    _superChats = _HuyaSuperChats(run, args.superChats);
    return DanmakuSocketTarget(endpoints: [HuyaDanmakuProtocol.endpoint]);
  }

  @override
  void onOpen(DanmakuSocketSession session) {
    // 3.x: ready as soon as the socket opens, then the registration and a
    // heartbeat at once (every reconnect registers again).
    session
      ..ready()
      ..send(HuyaDanmakuProtocol.register(_uid))
      ..heartbeat();
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) {
    // Huya only sends binary frames.
    if (data is! List<int>) return;
    final frame = HuyaDanmakuProtocol.decode(data);
    frame.messages.forEach(session.message);
    for (var notice = 0; notice < frame.superChatNotices; notice++) {
      _superChats?.schedule();
    }
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => HuyaDanmakuProtocol.heartbeat();
}

/// The headline board of one run (3.x `_scheduleSuperChatRefresh` and
/// `_refreshSuperChats`): one fetch sequence at a time, a notice during it
/// queues one more, and entries are reported once per run by their event
/// id. Everything stops with the run.
final class _HuyaSuperChats {
  new(this._run, this._fetch);

  final DanmakuRun _run;
  final Future<List<LiveSuperChatMessage>> Function()? _fetch;
  // Insertion ordered, so the oldest entry is forgotten first.
  final Set<LiveSuperChatMessage> _reported = {};
  Future<void>? _refreshing;
  bool _queued = false;

  void schedule() {
    final fetch = _fetch;
    // 3.x: no board without a top channel id (topSid 0).
    if (fetch == null || !_run.isActive) return;
    if (_refreshing != null) {
      _queued = true;
      return;
    }
    _queued = false;
    final refreshing = _refreshing = _refresh(fetch);
    unawaited(
      refreshing.whenComplete(() {
        if (identical(_refreshing, refreshing)) _refreshing = null;
        if (_queued && _run.isActive) schedule();
      }),
    );
  }

  /// Fetches the board after each retry delay. Once this run has reported
  /// an entry, a fetch that brings a new one ends the sequence: the board
  /// caught up. A failed or slow fetch waits for the next attempt.
  Future<void> _refresh(Future<List<LiveSuperChatMessage>> Function() fetch) async {
    for (final delay in HuyaDanmakuProtocol.superChatRetryDelays) {
      if (delay > Duration.zero && !await _run.delay(delay)) return;
      if (!_run.isActive) return;
      try {
        final entries = await fetch().timeout(HuyaDanmakuProtocol.superChatTimeout);
        if (!_run.isActive) return;
        final hadReported = _reported.isNotEmpty;
        var reportedNew = false;
        for (final entry in entries) {
          if (!_remember(entry)) continue;
          reportedNew = true;
          _run.message(HuyaDanmakuProtocol.superChatMessage(entry));
        }
        if (hadReported && reportedNew) return;
      } on Object {
        // 3.x logged the last failure only; the next notice tries again.
      }
    }
  }

  bool _remember(LiveSuperChatMessage entry) {
    if (!_reported.add(entry)) return false;
    while (_reported.length > HuyaDanmakuProtocol.maxRememberedSuperChats) {
      _reported.remove(_reported.first);
    }
    return true;
  }
}
