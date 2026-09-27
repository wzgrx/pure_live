import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/sites/acfun.dart';
import 'package:live_danmaku/src/sites/bilibili.dart';
import 'package:live_danmaku/src/sites/chzzk.dart';
import 'package:live_danmaku/src/sites/douyin.dart';
import 'package:live_danmaku/src/sites/douyu.dart';
import 'package:live_danmaku/src/sites/huya.dart';
import 'package:live_danmaku/src/sites/kilakila.dart';
import 'package:live_danmaku/src/sites/kuaishou.dart';
import 'package:live_danmaku/src/sites/missevan.dart';
import 'package:live_danmaku/src/sites/pandalive.dart';
import 'package:live_danmaku/src/sites/picarto.dart';
import 'package:live_danmaku/src/sites/seventeenlive.dart';
import 'package:live_danmaku/src/sites/showroom.dart';
import 'package:live_danmaku/src/sites/soop.dart';
import 'package:live_danmaku/src/sites/twitcasting.dart';
import 'package:live_danmaku/src/sites/twitch.dart';
import 'package:live_danmaku/src/sites/yy.dart';
import 'package:live_danmaku/src/transport.dart';

/// Platforms with a chat connector.
const danmakuPlatforms = {
  '17live',
  'acfun',
  'bilibili',
  'chzzk',
  'douyin',
  'douyu',
  'huya',
  'kilakila',
  'kuaishou',
  'missevan',
  'pandalive',
  'picarto',
  'showroom',
  'soop',
  'twitcasting',
  'twitch',
  'yy',
};

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
  '17live' => SeventeenliveConnector(detail: room, transport: transport, session: session, clock: clock),
  'acfun' => AcfunConnector(detail: room, transport: transport, session: session, clock: clock),
  'chzzk' => ChzzkConnector(detail: room, transport: transport, session: session, clock: clock),
  'kilakila' => KilakilaConnector(detail: room, transport: transport, session: session, clock: clock),
  'missevan' => MissevanConnector(
    detail: room,
    transport: transport,
    credentials: credentials,
    session: session,
    clock: clock,
  ),
  'pandalive' => PandaliveConnector(detail: room, transport: transport, session: session, clock: clock),
  'picarto' => PicartoConnector(detail: room, transport: transport, session: session, clock: clock),
  'showroom' => ShowroomConnector(detail: room, transport: transport, session: session, clock: clock),
  'soop' => SoopConnector(detail: room, transport: transport, session: session, clock: clock),
  'twitcasting' => TwitcastingConnector(detail: room, transport: transport, session: session, clock: clock),
  'twitch' => TwitchConnector(detail: room, transport: transport, session: session, clock: clock),
  'yy' => YyConnector(detail: room, transport: transport, session: session, clock: clock),
  _ => null,
};
