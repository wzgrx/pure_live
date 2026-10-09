import 'dart:async';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`), from uri
/// 6501 (`SendItemSubBroadcastPacket`, a gift sent in this room), as a
/// [LiveGift] (E05.5): [combo] is its combo total, [payTotal] its value in
/// [LiveGiftUnit.other] (the unit is not documented), and the combo key the
/// sender and `lComboSeqId` (D07.6).
@immutable
final class HuyaGift extends LiveGift {
  /// Creates the gift.
  ///
  /// [id] is `iItemType`, the gift's id (`4` is 虎粮), empty when 0 (E05.5:
  /// was the number); [name] `sPropsName` (`虎粮`, `粉丝通行证`); [count]
  /// `iItemCount`, at least 1: how many this send gave; [comboKey] the
  /// sender's uid and `lComboSeqId`, `uid:seq` ([HuyaDanmakuProtocol.comboKey]),
  /// empty when the packet has no sequence id.
  const new({
    required super.id,
    required super.name,
    required super.count,
    required this.combo,
    required this.payTotal,
    super.comboKey,
  }) : super(comboTotal: combo, totalValue: payTotal > 0 ? payTotal : null);

  /// `iItemGroup`, at least 1: the combo counter. A combo sends one packet
  /// per hit with the same `lComboSeqId`, counting 1, 2, 3…
  final int combo;

  /// `lPayTotal` as the platform gives it (0 for a free gift such as 虎粮;
  /// the unit is not documented).
  final int payTotal;

  @override
  bool operator ==(Object other) =>
      super == other && other is HuyaGift && other.combo == combo && other.payTotal == payTotal;

  @override
  int get hashCode => Object.hash(super.hashCode, combo, payTotal);

  @override
  String toString() => 'HuyaGift($name ×$count, combo $combo)';
}

/// What one Huya server frame held: its messages in order (with the super
/// chats that headline notices carried), how many headline notices (uri
/// 2001314) had a body that was not a board panel, so the board must be
/// fetched, and the streamer uids of its stream end notices (uri 8001; 0
/// when the notice names none).
typedef HuyaDanmakuFrame = ({List<LiveMessage> messages, int superChatNotices, List<int> ended});

/// Huya's danmaku protocol (the codec of 3.x `HuyaDanmaku`), without I/O.
///
/// Every frame is a Tars structure: tag 0 the command, tag 1 its payload
/// bytes. The client registers the streamer's groups (command 16) and sends
/// heartbeats (command 20); the server pushes single messages (command 7:
/// tag 1 uri, tag 2 body, tag 5 message id) and batches (command 22: tag 0
/// group, tag 1 items of tag 0 uri, tag 1 body, tag 2 message id). Chat is
/// uri 1400, popularity uri 8006, a gift uri 6501, and uri 2001314 carries
/// the headline message board after a change.
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

  /// A gift sent in this room (`SendItemSubBroadcastPacket`); 3.x ignored
  /// it.
  static const int giftUri = 6501;

  /// The stream ended (`EndLiveNotice`: 0 lPresenterUid, 1 iReason, 2
  /// lLiveId, 3 sReason such as `主播结束直播`); 3.x ignored it (C-10).
  static const int endUri = 8001;

  /// The detail of the run's end at the stream end (C-10, as 17LIVE's
  /// B-14).
  static const String broadcastEnded = 'Broadcast ended';

  /// The room's headline (super chat) message board after a change: the
  /// body is the board's panel (`GameEventMessageBoardPanel`, C-9). 3.x did
  /// not read it and fetched the board; that is now the fallback for a body
  /// that is not a panel.
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

  /// The messages of one server [frame] (3.x `decodeMessage`): chat,
  /// popularity and (M4.D) gifts from commands 7 and 22; (C-9) the board
  /// entries of each headline notice whose body is a panel, as
  /// [superChatMessage]s timed from [now] (default the clock), and the
  /// count of the other headline notices; (C-10) the streamer uid of each
  /// stream end notice.
  /// Other commands and uris are ignored; a frame that is not Tars gives
  /// nothing, and an item whose body fails to decode is skipped without
  /// losing the others.
  static HuyaDanmakuFrame decode(List<int> frame, {DateTime? now}) {
    final messages = <LiveMessage>[];
    final ended = <int>[];
    var notices = 0;
    void item(int uri, Uint8List? body, int eventId) {
      if (uri == endUri) {
        try {
          ended.add(TarsStruct.decode(body ?? const []).integer(0) ?? 0);
        } on FormatException {
          // Not an end notice.
        }
        return;
      }
      if (uri == superChatUri) {
        final board = HuyaApi.headlineNotice(body, now: now ?? DateTime.now());
        if (board == null) {
          notices++;
        } else {
          messages.addAll(board.map(superChatMessage));
        }
        return;
      }
      try {
        final message = switch (uri) {
          chatUri => _chat(body, eventId),
          popularityUri => _popularity(body, eventId),
          giftUri => gift(body, eventId),
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
    return (messages: messages, superChatNotices: notices, ended: ended);
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

  /// The combo key of a gift from sender [uid] with `lComboSeqId` [sequence]
  /// (D07.6): every packet of one combo carries the same sequence id (the
  /// time the combo began, in milliseconds), so the sender is part of the
  /// key, as two viewers may start a combo in the same millisecond. Empty
  /// without a sequence id (0: a gift sent at once, some 虎粮 batches).
  static String comboKey(int uid, int sequence) => sequence > 0 ? '$uid:$sequence' : '';

  /// uri 6501 (`SendItemSubBroadcastPacket`, the web client's field names):
  /// tag 0 `iItemType`, 2 `iItemCount`, 4 `lSenderUid`, 6 `sSenderNick`, 9
  /// `iItemGroup` (the combo counter), 20 `sPropsName`, 39 `lComboSeqId`
  /// (the combo's id, D07.6: [comboKey]), 41 `lPayTotal`. A gift without a
  /// name is not reported (the web client names it from a gift table this
  /// client does not load). Reported as a gift holding a [HuyaGift]; the
  /// text is `虎粮 ×1`.
  static LiveMessage? gift(Uint8List? body, int eventId) {
    final packet = TarsStruct.decode(body ?? const []);
    final name = (packet.string(20) ?? '').trim();
    if (name.isEmpty) return null;
    final count = packet.integer(2) ?? 0;
    final combo = packet.integer(9) ?? 0;
    final payTotal = packet.integer(41) ?? 0;
    final id = packet.integer(0) ?? 0;
    final uid = packet.integer(4) ?? 0;
    final data = HuyaGift(
      id: id == 0 ? '' : '$id',
      name: name,
      count: count > 0 ? count : 1,
      combo: combo > 0 ? combo : 1,
      payTotal: payTotal > 0 ? payTotal : 0,
      comboKey: comboKey(uid, packet.integer(39) ?? 0),
    );
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: packet.string(6) ?? '',
      userId: '$uid',
      message: data.plainText,
      color: LiveMessageColor.white,
      messageId: _messageId(eventId),
      data: data,
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
/// A headline notice carries the room's message board (C-9): every entry not
/// seen before on this connection is reported once. A notice whose body is
/// not a board panel fetches the board in the background instead (3.x)
/// through `HuyaDanmakuArgs.superChats` (the `HuyaSite` that built the
/// arguments owns the HTTP client): at once, then after 0.6, 1.8 and 4 more
/// seconds, with the same once-only rule.
///
/// A stream end notice for this streamer (C-10) ends the run with
/// [DanmakuCloseReason.connectionFailed] (`Broadcast ended`), after the
/// other messages of its frame.
///
/// The app registers it as `SiteIds.huya: () => HuyaDanmakuConnection(proxy:
/// …)`.
final class HuyaDanmakuConnection extends DanmakuSocketConnection<HuyaDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake; `connector`
  /// replaces `dart:io`'s handshake and [now] the clock that times board
  /// entries (tests).
  new({super.proxy, super.connector, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(site: SiteIds.huya, policy: socketPolicy);

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 60 s heartbeat,
  /// so a socket silent for max(3 × 60 s, 90 s) = 180 s is replaced. No join
  /// timer: 3.x counted an open socket as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: HuyaDanmakuProtocol.heartbeatInterval,
  );

  final DateTime Function() _now;
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
    final frame = HuyaDanmakuProtocol.decode(data, now: _now());
    for (final message in frame.messages) {
      if (message.data case final LiveSuperChatMessage entry) {
        _superChats?.report(entry);
      } else {
        session.message(message);
      }
    }
    for (var notice = 0; notice < frame.superChatNotices; notice++) {
      _superChats?.schedule();
    }
    // C-10: the web client leaves the room at the stream end; a notice that
    // names another streamer is not this room's.
    if (frame.ended.any((uid) => uid == _uid || uid <= 0)) {
      session.run.closed(DanmakuCloseReason.connectionFailed, detail: HuyaDanmakuProtocol.broadcastEnded);
    }
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => HuyaDanmakuProtocol.heartbeat();
}

/// The headline board of one run (3.x `_scheduleSuperChatRefresh` and
/// `_refreshSuperChats`): one fetch sequence at a time, a notice during it
/// queues one more, and entries, fetched or carried by a notice, are
/// reported once per run by their event id. Everything stops with the run.
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
          if (report(entry)) reportedNew = true;
        }
        if (hadReported && reportedNew) return;
      } on Object {
        // 3.x logged the last failure only; the next notice tries again.
      }
    }
  }

  /// Reports [entry] unless this run already did; whether it did now.
  bool report(LiveSuperChatMessage entry) {
    if (!_run.isActive || !_reported.add(entry)) return false;
    _run.message(HuyaDanmakuProtocol.superChatMessage(entry));
    while (_reported.length > HuyaDanmakuProtocol.maxRememberedSuperChats) {
      _reported.remove(_reported.first);
    }
    return true;
  }
}
