# live_danmaku

v4 的弹幕包（纯 Dart，不依赖 Flutter）：5 个首批平台的弹幕连接、统一消息、过滤链、抽样、按批送到界面线程的后台 isolate。行为规格见 [spec/modules/danmaku.md](../../spec/modules/danmaku.md) §1–§4、§6 的数据部分，各平台协议见 `spec/sites/<平台>.md` 第 7 节。设计决定见 [docs/adr/draft-danmaku.md](../../docs/adr/draft-danmaku.md)。

依赖方向：`live_danmaku → live_core → live_net`（`tools/gate/check_deps.py` 检查）。画面弹幕渲染（§5）和列表界面在应用里做，不在这个包里。

## 用法（应用）

```dart
final worker = await DanmakuWorker.spawn(
  proxy: proxyPolicy,                       // 纯数据（FixedProxyPolicy），会复制进后台 isolate
  credentials: SiteDanmakuCredentials(      // 留在界面 isolate：B 站 token、抖音会话 Cookie、用户 Cookie
    bilibiliSite: bilibili,
    douyinSite: douyin,
    cookies: cookieVault,
  ),
);
final session = worker.open(roomDetail, settings: filterSettings, budget: DanmakuScreenBudget.room);
session.batches.listen((batch) {
  history.addAll(batch.list);               // DanmakuHistory：500 条环形缓冲，返回增量
  board.addAll(batch.superChats, now);      // SuperChatBoard：去重、按结束时间移除
  renderer.enqueue(batch.screen);           // 已按画面预算抽样
  audience.update(batch.online);            // 每种指标只有最新值
});
session.update(settings: newSettings);      // FLT-6：立即生效，不重连
session.update(budget: DanmakuScreenBudget.pip);  // SMP-3：画中画预算
await session.close();                      // 5 s 内返回
```

平台没有弹幕连接时，会话只发一条 `DanmakuStatus.unsupported`。

## 公开接口

| 类型 | 作用 |
|---|---|
| `DanmakuEvent`（`DanmakuChat`、`DanmakuGift`、`DanmakuSuperChat`、`DanmakuOnline`、`DanmakuSystem`） | §1 统一消息。都带房间键、会话令牌、带平台前缀的消息 ID、平台时间、单调接收时间（`Timeline.now`，各 isolate 共用）、是否本地 |
| `DanmakuConnector`、`danmakuConnectorFor(room, transport:, credentials:)` | 一个房间的连接：`events`、`connect()`（加入后返回 true，终态失败返回 false）、`close()`（5 s 内） |
| `DouyuConnector`、`HuyaConnector`、`BilibiliConnector`、`DouyinConnector`、`KuaishouConnector` | 各平台连接；前四个共用 `SocketConnector` 的重连循环，快手是 HTTP 串行轮询 |
| `DouyuProtocol`、`HuyaProtocol`、`HuyaHeadlines`、`BilibiliProtocol`、`DouyinProtocol`、`KuaishouProtocol` | 纯函数：封包、心跳、签名、解码；测试直接用录制帧调用 |
| `DanmakuCredentials`、`SiteDanmakuCredentials` | 连接需要的凭据，由界面 isolate 上的站点适配器提供 |
| `DanmakuTransport`、`IoDanmakuTransport` | WebSocket（`dart:io`，按平台走代理）和 `LiveHttp` |
| `DanmakuPipeline`、`DanmakuBatch` | §2–§4：过滤链、抽样、64 ms 批次 |
| `DanmakuGate`、`DanmakuBlockList`、`RepeatFilter`、`SimilarityFilter`、`partialRatio`、`DensitySampler` | FLT-1～FLT-4、SMP；`DanmakuBlockList.matches` 也给应用移除已显示的条目 |
| `DanmakuWorker`、`DanmakuSession` | CONN-1 后台 isolate；CONN-4 令牌和房间键校验 |
| `DanmakuHistory`、`SuperChatBoard`、`NoticeThrottle` | LST-1、LST-5、LST-7 的数据部分 |
| `ProtoMessage`/`ProtoWriter`、`TarsStruct`/`TarsWriter`、`Stt` | 手写的 protobuf、Tars、STT 编解码 |

## 连接规则（CONN-3）

- 单次握手 10 s；启动 20 s 内没有加入就发 `timeout` 并关闭（`DanmakuWorker.spawn(startTimeout:)`）。
- 无消息超时 max(3 × 心跳, 90 s)；抖音按规格用 45 s。
- 重连：第 n 次失败后等 `1 s × (min(n ÷ 地址数, 5) + 1)` 并换下一个地址；收到任何消息清零；连续 8 次重试后进入终态（`closed`，参数 `maxRetries`），不再占用连接。
- B 站：凭据失败重试 3 次（间隔 500、1000 ms）；8 s 内没有认证回复就换地址；认证被拒重新取 token，最多 3 次。
- 快手：启动试 3 次（0.6 s、1.4 s）；轮询间隔用服务端的 `pullCycleSeconds`（1–10 s）；失败退避 1、2、4、8 s，第 9 次连续失败进入终态。

## 各平台状态（2026-09-27 实网）

| 平台 | 实网连接 | 录制样本 | 解码内容 |
|---|---|---|---|
| 斗鱼 | 通过 | `fixtures/douyu/danmaku/S13-live`（185 帧，147 条聊天、125 个礼物） | 聊天、`comm_chatmsg`/`voice_trlt` 醒目留言、`dgb` 礼物、疑似机器人标记 |
| 虎牙 | 通过 | `fixtures/huya/danmaku/S11-live`（265 帧，110 条聊天，含一次头条留言板响应） | 1400 聊天、8006 热度、2001314 通知后拉头条留言板（WUP） |
| B 站 | 通过（游客） | `fixtures/bilibili/danmaku/S13-live`（166 帧，44 条聊天，昵称被平台打码） | 聊天、人气（op 3）、累计观看、醒目留言、礼物、ACK、醒目留言快照 |
| 抖音 | 通过（匿名） | `fixtures/douyin/danmaku/S13-live`（163 帧，215 条聊天） | 聊天、在线人数、礼物、ACK |
| 快手 | 通过（匿名） | `fixtures/kuaishou/danmaku/S16-live`（10 次轮询，42 条评论） | 评论、在线人数 |
| Steam 直播 | 通过（匿名，HTTP 轮询聊天日志） | `fixtures/steambroadcast/danmaku/S07-live`（146 帧：历史 50 条 + 约 140 个时间窗，录制期间无新消息） | 聊天（历史只用于对时，不发出） |

## 录制样本

```bash
dart run tools/live_cli/bin/live_cli.dart danmaku douyu --recommended --seconds 30 --record S13-live
dart run tools/live_cli/bin/live_cli.dart danmaku bilibili 5050 --pipeline    # 走后台 isolate，打印批次
```

- 样本格式（ADR 0009 第 3 条）：`frames.jsonl` 每行一帧 `{dir, t, b64}`（HTTP 响应是 `{dir, t, url, text}` 或 `b64`），`meta.json` 记房间、弹幕参数、握手地址和请求头（Cookie 换成 `<redacted>`）、原始帧的 SHA-256、脱敏记录。
- 脱敏在帧解码后进行，再重新编码，样本仍能被真实解码器读取：观众昵称换成“观众 N”（平台打码的保持打码形态），用户 ID、头像、哈希换成同形的合成值，斗鱼 `loginres` 的客户端 IP、B 站认证包的 token 和 buvid、抖音签名和访客 ID、快手 `liveStreamId` 和评论文本（按快手规格）都替换。没有解码的消息类型（虎牙除 1400、8006 外的 uri，抖音除聊天和在线人数外的 method）只保留类型、清空负载。写入前检查所有被替换的原值（6 个字符以上）都已消失，否则拒绝写入。
- 样本里的平台时间是录制时的真实时间。去重闸门按“当前时间”丢弃 45 s 前的消息，所以回放测试直接调解码器，不经过带真实时钟的管线。

## 已知缺口

- 只有虎牙头条留言板的空响应是真实录制的；有条目时的字段位置（用户 tag0、内容 tag1、价格 tag2、总时长 tag4、倒计时 tag5、ID tag9、iCostPay tag12）来自旧版，没有真实样本。
- 斗鱼醒目留言（`comm_chatmsg` 付费、`voice_trlt`）、B 站醒目留言和礼物、抖音礼物都没有录到，只有按规格构造的单元测试。
- 虎牙礼物（6501）只有礼物 ID 没有名称，未解码；斗鱼礼物没有价格。
- 抖音主播重新开播后 room_id 会变，连接不会自己重新取详情（规格 §7 的待确认项）；应用应在终态后重新取详情再开会话。
- B 站只在游客会话实测；登录态的 uid 和完整昵称未实测。
- 表情图片（规格 §8 第 6 条）未处理，文本里保留平台的表情代码。
