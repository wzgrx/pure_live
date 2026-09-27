import 'dart:convert';
import 'dart:typed_data';

import 'package:live_danmaku/src/codec/stt.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';

/// Douyu's chat protocol (spec/sites/douyu.md §7), without I/O.
abstract final class DouyuProtocol {
  /// The only endpoint (§7.1).
  static final Uri endpoint = Uri.parse('wss://danmuproxy.douyu.com:8506');

  /// Heartbeat period (§7.1).
  static const heartbeatInterval = Duration(seconds: 45);

  /// Packet type of client packets (§7.2).
  static const clientType = 689;

  /// §7.2 one packet: `len len type encrypt reserved body \0`, little endian,
  /// `len` counting UTF-8 bytes.
  static Uint8List packet(String body, {int type = clientType}) {
    final text = utf8.encode(body);
    final length = 8 + text.length + 1;
    final out = ByteData(4 + length)
      ..setUint32(0, length, Endian.little)
      ..setUint32(4, length, Endian.little)
      ..setUint16(8, type, Endian.little);
    final bytes = out.buffer.asUint8List()..setRange(12, 12 + text.length, text);
    return bytes;
  }

  /// §7.1 the join packets for room [rid].
  static List<Uint8List> join(String rid) => [
    packet('type@=loginreq/roomid@=$rid/'),
    packet('type@=joingroup/rid@=$rid/gid@=-9999/'),
  ];

  /// §7.1 the heartbeat packet.
  static Uint8List heartbeat() => packet('type@=mrkl/');

  /// §7.2 the bodies of every packet in one frame; stops at a length below 9
  /// or past the end (REG-DOUYU-017).
  static List<String> bodies(List<int> frame) {
    final bytes = frame is Uint8List ? frame : Uint8List.fromList(frame);
    final view = ByteData.sublistView(bytes);
    final bodies = <String>[];
    var offset = 0;
    while (offset + 12 <= bytes.length) {
      final length = view.getUint32(offset, Endian.little);
      if (length < 9 || offset + 4 + length > bytes.length) break;
      var end = offset + 4 + length;
      if (bytes[end - 1] == 0) end--;
      bodies.add(utf8.decode(Uint8List.sublistView(bytes, offset + 12, end), allowMalformed: true));
      offset += 4 + length;
    }
    return bodies;
  }

  /// §7.4 decodes one frame for room [rid]; a malformed packet is skipped
  /// without losing the others (REG-DOUYU-021).
  static List<DanmakuEvent> decode(List<int> frame, {required String rid, required DecodeContext context}) => [
    for (final body in bodies(frame)) ?_packet(body, rid, context),
  ];

  static DanmakuEvent? _packet(String body, String rid, DecodeContext context) {
    try {
      final fields = Stt.map(body);
      return switch (fields['type']) {
        'chatmsg' => _chat(fields, rid, context),
        'comm_chatmsg' => _superChat(fields, context),
        'voice_trlt' => _voiceSuperChat(fields, context),
        'dgb' => _gift(fields, rid, context),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  /// §7.4 `chatmsg`; CONN-5 drops another room's packet.
  static DanmakuChat? _chat(Map<String, String> fields, String rid, DecodeContext context) {
    final packetRoom = fields['rid'] ?? '';
    if (packetRoom.isNotEmpty && rid.isNotEmpty && packetRoom != rid) return null;
    final text = fields['txt'] ?? '';
    if (text.isEmpty) return null;
    final cid = fields['cid'] ?? '';
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: cid.isEmpty ? null : 'douyu:$cid',
      sentAt: _time(fields['cst']),
      userId: fields['uid'] ?? '',
      userName: fields['nn'] ?? '',
      text: text,
      color: color(int.tryParse(fields['col'] ?? '') ?? 0),
      userLevel: int.tryParse(fields['level'] ?? ''),
      medalLevel: _positive(fields['bl']),
      medalName: _nonEmpty(fields['bnn']),
      suspectedBot: fields['dms'] == null && fields['if'] != '1',
    );
  }

  /// `dgb` gift: `gfn` name, `gfid` id, `gfcnt` count, sender `nn`/`uid`;
  /// another room's gift and a gift without a name are dropped. The packet
  /// carries no price.
  static DanmakuGift? _gift(Map<String, String> fields, String rid, DecodeContext context) {
    final packetRoom = fields['rid'] ?? '';
    if (packetRoom.isNotEmpty && rid.isNotEmpty && packetRoom != rid) return null;
    final name = fields['gfn'] ?? '';
    if (name.isEmpty) return null;
    return DanmakuGift(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      userId: fields['uid'] ?? '',
      userName: fields['nn'] ?? '',
      giftId: fields['gfid'] ?? '',
      giftName: name,
      count: _positive(fields['gfcnt']) ?? 1,
    );
  }

  /// §7.4 `comm_chatmsg`: start `now` (ms), `cet` seconds, `cprice` cents,
  /// nested `chatmsg{nn, txt, ic}`; incomplete ones are ignored.
  static DanmakuSuperChat? _superChat(Map<String, String> fields, DecodeContext context) {
    final nested = fields['chatmsg'];
    final now = int.tryParse(fields['now'] ?? '');
    final seconds = int.tryParse(fields['cet'] ?? '');
    final cents = int.tryParse(fields['cprice'] ?? '');
    if (nested == null || now == null || seconds == null || cents == null) return null;
    // Other notices share the type (`btype@=pandora` box openings, price 0,
    // duration 0); only a paid, timed one is a super chat.
    if (cents <= 0 || seconds <= 0) return null;
    final chat = Stt.map(nested);
    final face = chat['ic'] ?? '';
    final start = DateTime.fromMillisecondsSinceEpoch(now);
    return DanmakuSuperChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      userName: chat['nn'] ?? '',
      avatar: face.isEmpty ? null : Uri.tryParse('https://apic.douyucdn.cn/upload/${face}_small.jpg'),
      text: chat['txt'] ?? '',
      price: cents ~/ 100,
      startAt: start,
      endAt: start.add(Duration(seconds: seconds)),
      backgroundColor: 0xC1C1FF,
      bottomColor: 0x292A60,
    );
  }

  /// §7.4 `voice_trlt`: `list[0]` with `acptime`, `etime` (seconds),
  /// `realPrice` (cents), `content`, `un`; avatar `https://` + `uat[1]`.
  static DanmakuSuperChat? _voiceSuperChat(Map<String, String> fields, DecodeContext context) {
    final items = Stt.list(fields['list'] ?? '');
    if (items.isEmpty) return null;
    final item = Stt.map(items.first);
    final start = int.tryParse(item['acptime'] ?? '');
    final end = int.tryParse(item['etime'] ?? '');
    final cents = int.tryParse(item['realPrice'] ?? '');
    if (start == null || end == null || cents == null) return null;
    final avatars = Stt.list(item['uat'] ?? '');
    return DanmakuSuperChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      userName: item['un'] ?? '',
      avatar: avatars.length > 1 ? Uri.tryParse('https://${avatars[1]}') : null,
      text: item['content'] ?? '',
      price: cents ~/ 100,
      startAt: DateTime.fromMillisecondsSinceEpoch(start * 1000),
      endAt: DateTime.fromMillisecondsSinceEpoch(end * 1000),
      backgroundColor: 0xFFFFFF,
      bottomColor: 0x246488,
    );
  }

  /// §7.4 colour table of `col`.
  static int color(int col) => switch (col) {
    1 => 0xFF0000,
    2 => 0x1E87F0,
    3 => 0x7AC84B,
    4 => 0xFF7F00,
    5 => 0x9B39F4,
    6 => 0xFF69B4,
    _ => DanmakuColors.white,
  };

  /// `cst` above 1e11 is milliseconds, else seconds.
  static DateTime? _time(String? raw) {
    final value = int.tryParse(raw ?? '');
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value > 100000000000 ? value : value * 1000);
  }

  static int? _positive(String? raw) {
    final value = int.tryParse(raw ?? '');
    return value == null || value <= 0 ? null : value;
  }

  static String? _nonEmpty(String? raw) => raw == null || raw.isEmpty ? null : raw;
}

/// Douyu's chat connection: anonymous, one endpoint, 45 s heartbeat.
final class DouyuConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['rid']` is the room.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  String get _rid => detail.danmakuKeys['rid'] ?? room.roomId;

  @override
  Future<SocketPlan> plan({required bool refresh}) async => SocketPlan(endpoints: [DouyuProtocol.endpoint]);

  @override
  List<List<int>> openFrames() => DouyuProtocol.join(_rid);

  @override
  Duration get heartbeatInterval => DouyuProtocol.heartbeatInterval;

  @override
  bool get heartbeatOnJoin => false;

  @override
  List<int> heartbeat() => DouyuProtocol.heartbeat();

  @override
  FrameResult decode(Object? data, DecodeContext context) => switch (data) {
    final List<int> frame => FrameResult(
      events: DouyuProtocol.decode(frame, rid: _rid, context: context),
    ),
    _ => FrameResult.empty,
  };
}
