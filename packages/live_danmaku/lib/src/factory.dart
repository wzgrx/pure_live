import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/sites/bilibili.dart';
import 'package:live_danmaku/src/sites/chzzk.dart';
import 'package:live_danmaku/src/sites/douyin.dart';
import 'package:live_danmaku/src/sites/douyu.dart';
import 'package:live_danmaku/src/sites/huya.dart';
import 'package:live_danmaku/src/sites/kilakila.dart';
import 'package:live_danmaku/src/sites/kuaishou.dart';
import 'package:live_danmaku/src/sites/missevan.dart';
import 'package:live_danmaku/src/transport.dart';

/// Platforms with a chat connector.
const danmakuPlatforms = {'bilibili', 'chzzk', 'douyin', 'douyu', 'huya', 'kilakila', 'kuaishou', 'missevan'};

/// The chat connector for [room]'s platform, or null when the platform has
/// none (the UI shows [DanmakuStatus.unsupported] once, REG-DANMAKU-021).
///
/// [credentials] supplies Bilibili tokens and cookies; [session] is stamped
/// on every event.
DanmakuConnector? danmakuConnectorFor(
  RoomDetail room, {
  required DanmakuTransport transport,
  DanmakuCredentials? credentials,
  int session = 0,
  DanmakuClock? clock,
}) => switch (room.ref.platform) {
  'douyu' => DouyuConnector(detail: room, transport: transport, session: session, clock: clock),
  'huya' => HuyaConnector(detail: room, transport: transport, session: session, clock: clock),
  'bilibili' => BilibiliConnector(
    detail: room,
    transport: transport,
    credentials: credentials,
    session: session,
    clock: clock,
  ),
  'douyin' => DouyinConnector(
    detail: room,
    transport: transport,
    credentials: credentials,
    session: session,
    clock: clock,
  ),
  'kuaishou' => KuaishouConnector(
    detail: room,
    transport: transport,
    credentials: credentials,
    session: session,
    clock: clock,
  ),
  'chzzk' => ChzzkConnector(detail: room, transport: transport, session: session, clock: clock),
  'kilakila' => KilakilaConnector(detail: room, transport: transport, session: session, clock: clock),
  'missevan' => MissevanConnector(
    detail: room,
    transport: transport,
    credentials: credentials,
    session: session,
    clock: clock,
  ),
  _ => null,
};
