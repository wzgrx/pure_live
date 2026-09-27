import 'dart:typed_data';

import 'package:live_danmaku/src/codec/tars.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';

/// What one Huya frame held besides events.
typedef HuyaFrame = ({List<DanmakuEvent> events, bool headline});

/// Huya's chat protocol (spec/sites/huya.md §7), without I/O.
abstract final class HuyaProtocol {
  /// The endpoint (§7.1).
  static final Uri endpoint = Uri.parse('wss://wsapi.huya.com');

  /// Handshake headers (§7.1, as the probe sends them).
  static const headers = {'Origin': 'https://www.huya.com'};

  /// Heartbeat period (§7.3).
  static const heartbeatInterval = Duration(seconds: 60);

  /// Chat message uri.
  static const chatUri = 1400;

  /// Popularity uri (8006, not an online count: REG-HUYA-014).
  static const popularityUri = 8006;

  /// Headline (super chat) notification uri.
  static const headlineUri = 2001314;

  /// The groups one connection registers for streamer [uid].
  static List<String> groups(int uid) => ['live:$uid', 'chat:$uid'];

  /// §7.2 command 16: register [groups].
  static Uint8List register(int uid) {
    final group = TarsWriter()
      ..list<String>(0, groups(uid), (writer, item) => writer.string(0, item))
      ..string(1, '');
    return (TarsWriter()
          ..integer(0, 16)
          ..bytes(1, group.toBytes()))
        .toBytes();
  }

  /// §7.3 command 20 with an empty payload.
  static Uint8List heartbeat() =>
      (TarsWriter()
            ..integer(0, 20)
            ..bytes(1, const []))
          .toBytes();

  /// §7.2 decodes one frame for streamer [uid]: commands 7 and 22, uris
  /// 1400 and 8006; `headline` reports a 2001314 notification. Items of
  /// command 22 addressed to another group are dropped (§7.6).
  static HuyaFrame decode(List<int> frame, {required int uid, required DecodeContext context}) {
    final outer = TarsStruct.decode(frame);
    final payload = outer.bytes(1);
    if (payload == null) return (events: const [], headline: false);
    final events = <DanmakuEvent>[];
    var headline = false;
    void item(int? uri, Uint8List? body, int? messageId) {
      if (uri == headlineUri) {
        headline = true;
        return;
      }
      if (uri == null || body == null) return;
      try {
        final event = switch (uri) {
          chatUri => _chat(body, messageId, uid, context),
          popularityUri => _popularity(body, context),
          _ => null,
        };
        if (event != null) events.add(event);
      } on FormatException {
        // One malformed item must not drop the others of the frame.
      }
    }

    switch (outer.integer(0)) {
      case 7:
        final push = TarsStruct.decode(payload);
        item(push.integer(1), push.bytes(2), null);
      case 22:
        final push = TarsStruct.decode(payload);
        final group = push.string(0) ?? '';
        if (!groups(uid).contains(group)) break;
        for (final entry in push.list(1).whereType<TarsStruct>()) {
          item(entry.integer(0), entry.bytes(1), entry.integer(2));
        }
    }
    return (events: events, headline: headline);
  }

  /// uri 1400: sender tag0 (uid tag0, nick tag2), presenter uid tag1, text
  /// tag3, bullet format tag6 (colour tag0; 0 or less is white), message id
  /// tag20 (a decimal string; the command 22 item id otherwise). A message
  /// naming another presenter is dropped (CONN-5).
  static DanmakuChat? _chat(Uint8List body, int? itemId, int uid, DecodeContext context) {
    final message = TarsStruct.decode(body);
    final text = message.string(3) ?? '';
    if (text.isEmpty) return null;
    final presenter = message.integer(1) ?? 0;
    if (presenter > 0 && uid > 0 && presenter != uid) return null;
    final sender = message.struct(0);
    final color = message.struct(6)?.integer(0) ?? 0;
    final messageId = message.string(20) ?? '';
    final id = messageId.isNotEmpty ? messageId : (itemId == null || itemId <= 0 ? null : '$itemId');
    return DanmakuChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id == null ? null : 'huya:$id',
      userId: '${sender?.integer(0) ?? ''}',
      userName: sender?.string(2) ?? '',
      text: text,
      color: color <= 0 ? DanmakuColors.white : DanmakuColors.fromNumber(color),
    );
  }

  /// uri 8006: tag0 `iAttendeeCount`, a popularity figure.
  static DanmakuOnline? _popularity(Uint8List body, DecodeContext context) {
    final value = TarsStruct.decode(body).integer(0);
    if (value == null || value < 0) return null;
    return DanmakuOnline(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      audience: AudienceKind.popularity,
      value: value,
    );
  }
}

/// Huya's chat connection: registers the streamer's groups, 60 s heartbeat.
final class HuyaConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['uid']` is the streamer.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy, this.onHeadline});

  /// Called when a headline (super chat) notification arrives.
  final void Function()? onHeadline;

  int get _uid => int.tryParse(detail.danmakuKeys['uid'] ?? '') ?? 0;

  @override
  Future<SocketPlan> plan({required bool refresh}) async {
    // §7.1: no connection for a streamer uid of 0 or less.
    if (_uid <= 0) throw const DanmakuStartFailure('noRoom', 'huya uid missing');
    return SocketPlan(endpoints: [HuyaProtocol.endpoint], headers: HuyaProtocol.headers);
  }

  @override
  List<List<int>> openFrames() => [HuyaProtocol.register(_uid)];

  @override
  Duration get heartbeatInterval => HuyaProtocol.heartbeatInterval;

  @override
  List<int> heartbeat() => HuyaProtocol.heartbeat();

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    if (data is! List<int>) return FrameResult.empty;
    final frame = HuyaProtocol.decode(data, uid: _uid, context: context);
    if (frame.headline) onHeadline?.call();
    return FrameResult(events: frame.events);
  }
}
