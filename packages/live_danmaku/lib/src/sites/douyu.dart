import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/binary.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:meta/meta.dart';

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`), from a
/// `dgb` packet ([DouyuDanmakuProtocol.gift]). Reported, not shown yet
/// (M5 appendix B-21).
@immutable
final class DouyuGift {
  /// Creates the gift.
  const new({required this.id, required this.name, required this.count, this.combo = 0, this.receiverName = ''});

  /// `gfid`; empty when missing or 0 (a backpack prop such as 陪伴印章, whose
  /// id is `pid`).
  final String id;

  /// `gfn` (`粉丝荧光棒`).
  final String name;

  /// `gfcnt`, at least 1.
  final int count;

  /// `hits`, the combo so far including this send; 0 when missing.
  final int combo;

  /// `receive_nn`: the broadcaster, or a guest; empty when missing.
  final String receiverName;

  @override
  bool operator ==(Object other) =>
      other is DouyuGift &&
      other.id == id &&
      other.name == name &&
      other.count == count &&
      other.combo == combo &&
      other.receiverName == receiverName;

  @override
  int get hashCode => Object.hash(id, name, count, combo, receiverName);

  @override
  String toString() => 'DouyuGift($name ×$count, combo $combo)';
}

/// Douyu's STT text format (3.x `sttToJObject`, docs/T06/T06a/T06a.3/record.md):
/// `key@=value/` pairs; a list is its items, each followed by `/`; inside a
/// value `@` is written `@A` and `/` is written `@S`, once per nesting level.
///
/// Decoding is shallow: every value is unescaped exactly once and stays text.
/// Only the fields Douyu nests (a super chat's `chatmsg`, a voice super
/// chat's `list` and `uat`) are decoded again, by the protocol. 3.x decoded
/// every value recursively and guessed its shape from its text, so chat
/// holding `@A`, `@S`, `@=` or `//` came out changed.
abstract final class DouyuStt {
  /// Escapes [value] for one nesting level.
  static String escape(String value) => value.replaceAll('@', '@A').replaceAll('/', '@S');

  /// Reverses [escape] (3.x `unscapeSlashAt`).
  static String unescape(String value) => value.replaceAll('@S', '/').replaceAll('@A', '@');

  /// The pairs of [text] with their values unescaped once. Parts without a
  /// key (`@=` missing or first) are skipped, a later duplicate wins, and
  /// keys stay as written, as in 3.x.
  static Map<String, String> map(String text) {
    final pairs = <String, String>{};
    for (final part in text.split('/')) {
      final separator = part.indexOf('@=');
      if (separator <= 0) continue;
      pairs[part.substring(0, separator)] = unescape(part.substring(separator + 2));
    }
    return pairs;
  }

  /// The items of a list value (as [map] returns it), each unescaped once;
  /// empty items are skipped. An item that is itself a map goes through
  /// [map].
  static List<String> list(String value) => [
    for (final item in value.split('/'))
      if (item.isNotEmpty) unescape(item),
  ];
}

/// Douyu's danmaku protocol (the codec of 3.x `DouyuDanmaku`), without I/O.
///
/// A packet is `length(4) length(4) type(2) encrypted(1) reserved(1) body
/// \0`, little endian, where length counts itself out: 8 + body + 1. Client
/// packets have type 689; one server frame usually carries several packets.
abstract final class DouyuDanmakuProtocol {
  /// The only endpoint (`DouyuApi.danmakuServer`).
  static final Uri endpoint = Uri.parse(DouyuApi.danmakuServer);

  /// Heartbeat period (3.x `heartbeatTime`, 45 000 ms).
  static const Duration heartbeatInterval = Duration(seconds: 45);

  /// Packet type of client packets.
  static const int clientPacketType = 689;

  /// Packet type the server uses (3.x never checked it, neither does
  /// [bodies]).
  static const int serverPacketType = 690;

  /// One packet of [body] (3.x `serializeDouyu`). The length counts UTF-8
  /// bytes; 3.x counted UTF-16 units, which only agrees for ASCII bodies (the
  /// only ones it sent).
  static Uint8List packet(String body, {int type = clientPacketType}) {
    final text = utf8.encode(body);
    final length = 4 + 4 + text.length + 1;
    final writer = BinaryWriter()
      ..writeInt(length, 4, endian: Endian.little)
      ..writeInt(length, 4, endian: Endian.little)
      ..writeInt(type, 2, endian: Endian.little)
      // Encrypted, reserved.
      ..writeInt(0, 1)
      ..writeInt(0, 1)
      ..writeBytes(text)
      ..writeInt(0, 1);
    return Uint8List.fromList(writer.buffer);
  }

  /// What joins room [roomId] once the socket is open (3.x `joinRoom`):
  /// `loginreq`, then `joingroup` with group −9999.
  static List<Uint8List> joinPackets(String roomId) => [
    packet('type@=loginreq/roomid@=$roomId/'),
    packet('type@=joingroup/rid@=$roomId/gid@=-9999/'),
  ];

  /// The heartbeat packet (`type@=mrkl/`).
  static Uint8List heartbeat() => packet('type@=mrkl/');

  /// The bodies of the packets in [frame], in order (3.x
  /// `deserializeDouyuPackets`). The last byte of each packet (its `\0`) is
  /// left out; a length below 9 or past the end of the frame stops the split,
  /// and the rest of the frame is dropped.
  static List<String> bodies(List<int> frame) {
    final bytes = frame is Uint8List ? frame : Uint8List.fromList(frame);
    final view = ByteData.sublistView(bytes);
    final bodies = <String>[];
    var offset = 0;
    while (offset + 12 <= bytes.length) {
      final length = view.getUint32(offset, Endian.little);
      if (length < 9 || offset + 4 + length > bytes.length) break;
      bodies.add(utf8.decode(Uint8List.sublistView(bytes, offset + 12, offset + 3 + length), allowMalformed: true));
      offset += 4 + length;
    }
    return bodies;
  }

  /// The messages of one server [frame] for room [roomId] (3.x
  /// `decodeMessage`): chat (`chatmsg`), super chats (`comm_chatmsg`,
  /// `voice_trlt`) and gifts (`dgb`, M4.D; 3.x ignored them); other packets
  /// are ignored. A packet that fails to decode
  /// is skipped without losing the others. [filterSuspectedAutomated] is read
  /// for each suspected chat, so a changed setting applies at once.
  static List<LiveMessage> decode(
    List<int> frame, {
    required String roomId,
    bool Function()? filterSuspectedAutomated,
  }) => read(frame, roomId: roomId, filterSuspectedAutomated: filterSuspectedAutomated).messages;

  /// [decode], and whether the frame says room [roomId]'s broadcast ended
  /// ([endsBroadcast]); the packets after that one are not read.
  static ({List<LiveMessage> messages, bool ended}) read(
    List<int> frame, {
    required String roomId,
    bool Function()? filterSuspectedAutomated,
  }) {
    final messages = <LiveMessage>[];
    for (final body in bodies(frame)) {
      try {
        final fields = DouyuStt.map(body);
        if (endsBroadcast(fields, roomId)) return (messages: messages, ended: true);
        final message = switch (fields['type']) {
          'chatmsg' => _chat(fields, roomId, filterSuspectedAutomated),
          'comm_chatmsg' => _superChat(fields),
          'voice_trlt' => _voiceSuperChat(fields),
          'dgb' => gift(fields, roomId),
          _ => null,
        };
        if (message != null) messages.add(message);
      } on Object {
        // 3.x: one malformed packet (a timestamp out of range) must not lose
        // the packets after it in the same frame.
      }
    }
    return (messages: messages, ended: false);
  }

  /// Whether [fields] is room [roomId]'s `rss` packet saying the broadcast
  /// ended (`ss@=0`). A start (`ss@=1`) gives nothing, nor does another
  /// room's packet.
  static bool endsBroadcast(Map<String, String> fields, String roomId) {
    if (fields['type'] != 'rss' || fields['ss'] != '0') return false;
    final packetRoomId = fields['rid'] ?? '';
    return packetRoomId.isEmpty || roomId.isEmpty || packetRoomId == roomId;
  }

  /// The colour of `col` (3.x `getColor`); unknown values are white.
  static LiveMessageColor color(int col) => switch (col) {
    1 => const LiveMessageColor(255, 0, 0),
    2 => const LiveMessageColor(30, 135, 240),
    3 => const LiveMessageColor(122, 200, 75),
    4 => const LiveMessageColor(255, 127, 0),
    5 => const LiveMessageColor(155, 57, 244),
    6 => const LiveMessageColor(255, 105, 180),
    _ => LiveMessageColor.white,
  };

  /// A chat without `dms` whose `if` is not `1` (3.x's "suspected automated"
  /// rule; the filter is off unless the user turns it on).
  static bool isSuspectedAutomated(Map<String, String> fields) => fields['dms'] == null && fields['if'] != '1';

  /// `chatmsg`: another room's packet and empty text are dropped; `cst` above
  /// 10^11 is milliseconds, otherwise seconds.
  static LiveMessage? _chat(Map<String, String> fields, String roomId, bool Function()? filterSuspectedAutomated) {
    final packetRoomId = fields['rid'] ?? '';
    if (packetRoomId.isNotEmpty && roomId.isNotEmpty && packetRoomId != roomId) return null;
    final text = fields['txt'] ?? '';
    if (text.isEmpty) return null;
    if (isSuspectedAutomated(fields) && (filterSuspectedAutomated?.call() ?? false)) return null;
    final timestamp = int.tryParse(fields['cst'] ?? '');
    final messageId = fields['cid'] ?? '';
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: fields['nn'] ?? '',
      userId: fields['uid'] ?? '',
      message: text,
      color: color(int.tryParse(fields['col'] ?? '') ?? 0),
      messageId: messageId.isEmpty ? '' : 'douyu:$messageId',
      sentAt: timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp > 100000000000 ? timestamp : timestamp * 1000),
    );
  }

  /// `comm_chatmsg`: start `now` (ms), `cet` seconds, `cprice` cents and the
  /// nested `chatmsg` map (`nn`, `txt`, `ic`). A notice without price or
  /// duration (a pandora box opening shares the type) is not a super chat.
  static LiveMessage? _superChat(Map<String, String> fields) {
    final nested = fields['chatmsg'];
    final now = int.tryParse(fields['now'] ?? '');
    final seconds = int.tryParse(fields['cet'] ?? '');
    final cents = int.tryParse(fields['cprice'] ?? '');
    if (nested == null || !nested.contains('@=') || now == null || seconds == null || cents == null) return null;
    if (cents <= 0 || seconds <= 0) return null;
    final chat = DouyuStt.map(nested);
    final face = chat['ic'] ?? '';
    final start = DateTime.fromMillisecondsSinceEpoch(now);
    return _superChatMessage(
      LiveSuperChatMessage(
        userName: chat['nn'] ?? '',
        face: face.isEmpty ? '' : 'https://apic.douyucdn.cn/upload/${face}_small.jpg',
        message: chat['txt'] ?? '',
        price: cents ~/ 100,
        startTime: start,
        endTime: start.add(Duration(seconds: seconds)),
        backgroundColor: '#c1c1ff',
        backgroundBottomColor: '#292a60',
      ),
    );
  }

  /// `voice_trlt`: the first map of `list`, with `acptime` and `etime`
  /// (seconds), `realPrice` (cents), `content`, `un`, and the avatar
  /// `https://` + the second item of `uat`.
  static LiveMessage? _voiceSuperChat(Map<String, String> fields) {
    final items = DouyuStt.list(fields['list'] ?? '');
    if (items.isEmpty || !items.first.contains('@=')) return null;
    final item = DouyuStt.map(items.first);
    final end = int.tryParse(item['etime'] ?? '');
    final start = int.tryParse(item['acptime'] ?? '');
    final cents = int.tryParse(item['realPrice'] ?? '');
    if (end == null || start == null || cents == null) return null;
    final avatars = DouyuStt.list(item['uat'] ?? '');
    final avatar = avatars.length > 1 ? avatars[1] : '';
    return _superChatMessage(
      LiveSuperChatMessage(
        userName: item['un'] ?? '',
        face: avatar.isEmpty ? '' : 'https://$avatar',
        message: item['content'] ?? '',
        price: cents ~/ 100,
        startTime: DateTime.fromMillisecondsSinceEpoch(start * 1000),
        endTime: DateTime.fromMillisecondsSinceEpoch(end * 1000),
        backgroundColor: '#ffffff',
        backgroundBottomColor: '#246488',
      ),
    );
  }

  /// `dgb`: a gift sent in this room, reported as a [LiveMessageType.gift]
  /// holding a [DouyuGift] (not shown yet, M5 appendix B-21; the archived v4
  /// read the same fields). The sender is `nn`/`uid`, the text
  /// `<gfn> ×<gfcnt>`. Another room's packet and a gift without a name give
  /// nothing. The packet has no id and no time.
  static LiveMessage? gift(Map<String, String> fields, String roomId) {
    final packetRoomId = fields['rid'] ?? '';
    if (packetRoomId.isNotEmpty && roomId.isNotEmpty && packetRoomId != roomId) return null;
    final name = (fields['gfn'] ?? '').trim();
    if (name.isEmpty) return null;
    final id = fields['gfid'] ?? '';
    final count = int.tryParse(fields['gfcnt'] ?? '') ?? 0;
    final combo = int.tryParse(fields['hits'] ?? '') ?? 0;
    final present = DouyuGift(
      id: id == '0' ? '' : id,
      name: name,
      count: count > 0 ? count : 1,
      combo: combo > 0 ? combo : 0,
      receiverName: fields['receive_nn'] ?? '',
    );
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: fields['nn'] ?? '',
      userId: fields['uid'] ?? '',
      message: '${present.name} ×${present.count}',
      color: LiveMessageColor.white,
      data: present,
    );
  }

  static LiveMessage _superChatMessage(LiveSuperChatMessage data) => LiveMessage(
    type: LiveMessageType.superChat,
    userName: 'SUPER_CHAT_MESSAGE',
    message: 'SUPER_CHAT_MESSAGE',
    color: LiveMessageColor.white,
    data: data,
  );
}

/// Douyu's danmaku connection (3.x `DouyuDanmaku`): one anonymous WebSocket
/// to [DouyuDanmakuProtocol.endpoint] without extra headers. An open socket
/// counts as joined; the join packets follow, a `type@=mrkl/` heartbeat goes
/// out every 45 s, and a socket silent for 135 s is replaced. The room's
/// broadcast-end packet ([DouyuDanmakuProtocol.endsBroadcast]) ends the run
/// with [DanmakuCloseReason.connectionFailed] ([broadcastEnded]), as 17LIVE
/// does (C-6, B-14); a start is not reported.
///
/// The app registers it as `SiteIds.douyu: () => DouyuDanmakuConnection(proxy:
/// …, filterSuspectedAutomatedMessages: () => …)`, reading 3.x's
/// `filterDouyuSuspectedAutomatedMessages` setting (default off) on every
/// call, so a change applies to the next message without reconnecting.
final class DouyuDanmakuConnection extends DanmakuSocketConnection<DouyuDanmakuArgs> {
  /// Creates the connection. [proxy] routes the handshake;
  /// `filterSuspectedAutomatedMessages` drops chat 3.x deems automated when
  /// it returns true (null: never); `connector` replaces `dart:io`'s
  /// handshake (tests).
  new({super.proxy, this._filterSuspectedAutomatedMessages, super.connector})
    : super(site: SiteIds.douyu, policy: socketPolicy);

  /// Socket timing: 3.x's `WebScoketUtils` defaults with a 45 s heartbeat,
  /// so a socket silent for max(3 × 45 s, 90 s) = 135 s is replaced. No join
  /// timer: 3.x counted an open socket as joined.
  static const DanmakuSocketPolicy socketPolicy = DanmakuSocketPolicy(
    heartbeatInterval: DouyuDanmakuProtocol.heartbeatInterval,
  );

  /// The detail of the run's end when the broadcast ends.
  static const String broadcastEnded = 'Broadcast ended';

  final bool Function()? _filterSuspectedAutomatedMessages;
  String _roomId = '';

  @override
  Future<DanmakuSocketTarget> target(DouyuDanmakuArgs args, DanmakuRun run) async {
    _roomId = args.roomId;
    return DanmakuSocketTarget(endpoints: [DouyuDanmakuProtocol.endpoint]);
  }

  @override
  void onOpen(DanmakuSocketSession session) {
    // 3.x: ready as soon as the socket opens, then the join packets.
    session.ready();
    DouyuDanmakuProtocol.joinPackets(_roomId).forEach(session.send);
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) {
    // Douyu only sends binary frames.
    if (data is! List<int>) return;
    final (:messages, :ended) = DouyuDanmakuProtocol.read(
      data,
      roomId: _roomId,
      filterSuspectedAutomated: _filterSuspectedAutomatedMessages,
    );
    messages.forEach(session.message);
    if (ended) session.run.closed(DanmakuCloseReason.connectionFailed, detail: broadcastEnded);
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => DouyuDanmakuProtocol.heartbeat();
}
