import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/tars.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/socket_connector.dart';
import 'package:live_net/live_net.dart';

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

/// Huya's headline board (§7.5): super chats fetched over WUP, without I/O.
abstract final class HuyaHeadlines {
  /// The WUP endpoint.
  static final Uri endpoint = Uri.https('wup.huya.com', '/');

  /// Request headers (§7.5): Origin, Referer and the HYSDK UA.
  static const Map<String, String> headers = {
    'Origin': 'https://www.huya.com',
    'Referer': 'https://www.huya.com',
    'User-Agent': HuyaParse.mediaUserAgent,
  };

  /// §7.5 retry schedule after a 2001314 notification.
  static const List<Duration> retries = [
    Duration.zero,
    Duration(milliseconds: 600),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 4000),
  ];

  /// §7.5 `wupui.getHeadLineMessageBoard` for channel [topSid]: a TUP3
  /// packet whose `tReq` is {lPid, sOffset "", tId {sHuYaUA}, scope 0,
  /// page size 10}.
  static Uint8List request(int topSid) {
    final request = TarsWriter()
      ..struct(0, (writer) {
        writer
          ..integer(0, topSid)
          ..string(1, '')
          ..struct(2, (user) {
            user
              ..integer(0, 0)
              ..string(1, '')
              ..string(2, '')
              ..string(3, HuyaParse.mediaUserAgent)
              ..string(4, '')
              ..integer(5, 0)
              ..string(6, '')
              ..string(7, '');
          })
          ..integer(3, 0)
          ..integer(4, 10);
      });
    final buffer = TarsWriter()..value(0, <Object?, Object?>{'tReq': request.toBytes()});
    final body = TarsWriter()
      ..integer(1, 3)
      ..integer(2, 0)
      ..integer(3, 0)
      ..integer(4, 0)
      ..string(5, 'wupui')
      ..string(6, 'getHeadLineMessageBoard')
      ..bytes(7, buffer.toBytes())
      ..integer(8, 0)
      ..value(9, <Object?, Object?>{})
      ..value(10, <Object?, Object?>{});
    final bytes = body.toBytes();
    return (BytesBuilder(copy: false)
          ..add((ByteData(4)..setInt32(0, bytes.length + 4)).buffer.asUint8List())
          ..add(bytes))
        .toBytes();
  }

  /// §7.5 the super chats of a response received at [context]'s `now`:
  /// empty content or no time left is dropped; price `iCost`, else
  /// max(1, round(iCostPay / 100)); end = now + remaining, start = end −
  /// total; id `huya:{lMessageId}`.
  static List<DanmakuSuperChat> parse(List<int> response, {required DecodeContext context}) {
    if (response.length < 4) throw const FormatException('WUP: shorter than its length prefix');
    final packet = TarsStruct.decode(response.sublist(4));
    final buffer = packet.bytes(7);
    if (buffer == null) throw const FormatException('WUP: no sBuffer');
    final params = TarsStruct.decode(buffer).fields[0];
    final raw = params is Map ? params['tRsp'] : null;
    if (raw is! Uint8List) throw const FormatException('WUP: no tRsp');
    final panel = TarsStruct.decode(raw).struct(0)?.struct(1);
    final now = context.now;
    return [
      for (final item in panel?.list(1).whereType<TarsStruct>() ?? const <TarsStruct>[])
        if (_item(item, now, context) case final DanmakuSuperChat chat) chat,
    ];
  }

  static DanmakuSuperChat? _item(TarsStruct item, DateTime now, DecodeContext context) {
    final text = (item.string(1) ?? '').trim();
    final countdown = item.integer(5) ?? 0;
    final total = item.integer(4) ?? 0;
    final remaining = countdown > 0 ? countdown : total;
    if (text.isEmpty || remaining <= 0) return null;
    var price = item.integer(2) ?? 0;
    final paid = item.integer(12) ?? 0;
    if (price <= 0 && paid > 0) price = max(1, (paid / 100).round());
    final end = now.add(Duration(seconds: remaining));
    final user = item.struct(0);
    final id = item.integer(9) ?? 0;
    final avatar = user?.string(2) ?? '';
    return DanmakuSuperChat(
      room: context.room,
      session: context.session,
      receivedAt: context.receivedAt,
      id: id > 0 ? 'huya:$id' : null,
      userName: (user?.string(1) ?? '').trim(),
      avatar: avatar.isEmpty ? null : Uri.tryParse(avatar),
      text: text,
      price: price,
      startAt: end.subtract(Duration(seconds: total > 0 ? total : remaining)),
      endAt: end,
      backgroundColor: 0xFFFFFF,
      bottomColor: 0x246488,
    );
  }
}

/// Huya's chat connection: registers the streamer's groups, 60 s heartbeat,
/// the headline board once joined and after every 2001314 notification.
final class HuyaConnector extends SocketConnector {
  /// Creates the connector; [detail]'s `danmakuKeys['uid']` is the streamer
  /// and `topSid` the channel of the headline board.
  new({required super.detail, required super.transport, super.session, super.clock, super.policy});

  int get _uid => int.tryParse(detail.danmakuKeys['uid'] ?? '') ?? 0;

  int get _topSid => int.tryParse(detail.danmakuKeys['topSid'] ?? '') ?? 0;

  final Set<String> _seen = {};
  Future<void>? _refreshing;
  var _queued = false;
  var _generation = 0;

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
  void onJoined(int generation) {
    // §7.5: the whole board once on entry.
    _generation = generation;
    _refresh(generation, once: true);
  }

  @override
  FrameResult decode(Object? data, DecodeContext context) {
    if (data is! List<int>) return FrameResult.empty;
    final frame = HuyaProtocol.decode(data, uid: _uid, context: context);
    if (frame.headline) _refresh(_generation, once: false);
    return FrameResult(events: frame.events);
  }

  /// §7.5 fetches the board in the background (never inside decoding); a
  /// notification during a fetch queues one more.
  void _refresh(int generation, {required bool once}) {
    if (_topSid <= 0 || isStale(generation)) return;
    if (_refreshing != null) {
      _queued = true;
      return;
    }
    final run = _fetch(generation, once: once);
    _refreshing = run;
    unawaited(
      run.whenComplete(() {
        _refreshing = null;
        if (_queued && !isStale(generation)) {
          _queued = false;
          _refresh(generation, once: false);
        }
      }),
    );
  }

  Future<void> _fetch(int generation, {required bool once}) async {
    for (final delay in once ? const [Duration.zero] : HuyaHeadlines.retries) {
      if (!await pause(generation, delay)) return;
      final baseline = _seen.isNotEmpty;
      try {
        final response = await transport.http.send(
          LiveRequest(
            site: 'huya',
            url: HuyaHeadlines.endpoint,
            method: 'POST',
            headers: HuyaHeadlines.headers,
            body: HuyaHeadlines.request(_topSid),
            timeout: const Duration(seconds: 3),
          ),
        );
        if (isStale(generation) || !response.isSuccess) continue;
        var fresh = false;
        for (final chat in HuyaHeadlines.parse(response.bytes, context: context())) {
          // Same content under another id is another message (§7.5).
          final key = chat.id ?? '${chat.userName}\u0000${chat.text}\u0000${chat.price}';
          if (!_seen.add(key)) continue;
          if (_seen.length > 512) _seen.remove(_seen.first);
          fresh = true;
          emit(generation, chat);
        }
        // With a baseline, a new entry means the board caught up.
        if (baseline && fresh) return;
      } on Object {
        // Best effort: the next notification tries again.
      }
    }
  }
}
