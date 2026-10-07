# D01.5 抖音 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 4 个平台）：把 3.x 的 `lib/core/danmaku/douyin_danmaku.dart` 和生成的 protobuf 类移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.4、T06a.5
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、签名 `DouyinSigner.danmakuSignature` 和弹幕参数 [E01.4 记录](../../../E-直播平台/E01-国内五大平台/E01.4-抖音/record.md)；protobuf 读取器后来和 AcFun 共用（[D01.10](../D01.10-AcFun弹幕/README.md)）；详细记录 [record.md](record.md)

## 目标

抖音直播间的弹幕照 3.x 连上和显示：聊天和在线人数，回 ACK，两个节点轮流重连；不再依赖 `package:protobuf` 和 7500 行生成代码；修掉 3.x 2038 年后 room_id 越过 2^63 弹幕全丢、一条坏消息丢掉整帧的问题。后来（B-5）在线人数改用精确整数、聊天补上发送时间、主播重新开播时自动换到新场次。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/`、`wss://webcast100-ws-web-hl.douyin.com/webcast/im/push/v2/`，同一组 31 个查询参数（顺序同 3.x，`room_id` 是本场 room_id，`signature` 是本地算的 X-Bogus，按参数值编码 `+`→`%2B`） |
| 请求头 | `user-agent`（Chrome 134）、`cookie`（非空才带）、`origin: https://live.douyin.com`、`referer: https://live.douyin.com/<web_rid>`，来自 `DouyinDanmakuArgs.headers` |
| 编码 | protobuf `PushFrame` → gzip（`payloadEncoding` 为 `gzip` 或负载以 `1f 8b` 开头）→ `Response` → `Message` 列表；手写读取器 `packages/live_danmaku/lib/src/codec/protobuf.dart`（`ProtoMessage`、`ProtoWriter`，约 200 行） |
| 加入和心跳 | 打开即就绪，随后发一个 `PushFrame{payloadType: "hb"}`（4 字节 `3a 02 68 62`）；心跳 10 s；无消息 45 s 换连接；两个节点轮流，等待 1、2、2、3、3、4、4、5 s，8 次后放弃 |
| ACK | `Response.needAck` 为真时先回 `PushFrame{logId, payloadType: "ack", payload: internalExt}` 再上报 |
| 消息 | `WebcastChatMessage`（`common.roomId` 不为 0 且不是本场就丢；id 取 `common.msgId`，为 0 取外层 `Message.msgId`，加 `douyin:`；时间先 `common.createTime`，B-5 起没有时用 `eventTime`；颜色一律白色）；`WebcastRoomUserSeqMessage`（B-5 起优先 `total` 精确整数，没有时用 `onlineUserForAnchor` 文字，报 `onlineViewers`）；其他方法忽略 |
| 换场次 | 参数带 `refresh` 时：连续 2 分钟没有任何消息查一次详情（之后 4、8、16 分钟），重连耗尽时也查一次；room_id 变了就用新签名、新游标 `reopen`，不提示 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/douyin_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/douyin.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `DouyinDanmaku`（:39），`DouyinSite.getDanmaku()`（`core/site/douyin/douyin_site.dart:28`） | `DouyinDanmakuConnection`（:251）；应用登记在 `apps/pure_live/lib/app/platforms.dart:210` | 一致 |
| 节点和超时 | :68～71 两个节点，`heartbeatTime = 10 * 1000`（:41），`inactivityTimeout` 45 s（:136） | `hosts`（:37）、`heartbeatInterval`（:43）、`inactivityTimeout`（:46）、`socketPolicy`（:263） | 一致；地址与 3.x 的 `buildServerUrls`（:174）和录制逐字相同 |
| protobuf | `package:protobuf` 6.1.0 和生成的 `proto/douyin.pb.dart` | 手写读取器（`src/codec/protobuf.dart`），只读用到的十来个字段 | 正常数据结果相同 |
| 解码 | `decodeMessage`（:201），整帧一个 `try` | 按方法分发（:147～148），每条消息单独解码 | 一条坏的只丢自己（修 3.x 问题 2） |
| uint64 编号 | `Int64.toString()` 按有符号打印，2038 年后开播的房间 room_id 变负数，弹幕全丢 | 按无符号打印 | 修好（3.x 问题 1） |
| 在线人数 | 只取 `onlineUserForAnchor` 文字（`30.6万` → 306000） | `total` 优先（:206 起） | 1 万以上显示精确人数（B-5） |
| 聊天时间 | 只看 `createTime`，录到的聊天都没有，`sentAt` 为空 | 没有时用 `eventTime` | 聊天有时间，去重闸门开始做 45 s 检查（B-5） |
| 重新开播 | 沿用旧 room_id，要重新进房 | `refresh` 回调（`DouyinSite` 放进参数）、`_watch`（:276）、`onReconnectsExhausted`（:320），查询 10 s 超时（:58） | 2～3 分钟内自动接上新场次（B-5，未实测真实的重新开播） |

## 结果

- **提交**：a4959ea90（2026-09-29，M5.4），54baa1109（protobuf 读取器移到 `src/codec/`，和 AcFun 共用），03aa04354（2026-10-01，B-5）。
- **和 3.x 的对照**：`fixtures/douyin/danmaku/legacy_expected.sh` 在临时目录用 3.x 的 protobuf 运行时跑 3.x 的解码，生成冻结输出。S13-live（房间 148108118778，81 帧）78 个 ACK、215 条聊天、16 次在线人数逐条一致，心跳和 ACK 与录制逐字节相同；S13-vectors 25 个向量里 21 个一致、4 个是有意差异（无符号打印、坏消息只丢自己）。B-5 后期望改为“3.x 的输出加上 `eventTime` 和 `total`”。
- **有意差异**：record.md 5 条；保持 3.x：文字为空的聊天照样上报、room_id 为空照样连接、不处理心跳回复和 `heartbeatDuration`、不显示礼物进场点赞（匿名网页端也收不到 `WebcastGiftMessage`）。
- **框架的添加**：`DanmakuSocketConnection.onReconnectsExhausted`（`packages/live_danmaku/lib/src/socket_connection.dart`），默认 false，目前只有抖音覆盖。
- **样本**：`fixtures/douyin/danmaku/` 的 S13-live、S13-vectors、S13-audience（5 个直播间 150 s，在线人数 2～77726）。
- **测试**：`packages/live_danmaku/test/sites/douyin_test.dart` 做完时 50 个（另做过 15 个变异），B-5 后 63 个；`socket_connection_test.dart` +2，`live_core` 的 `douyin_site_test.dart` +1。

## 验证

- 自动测试：`douyin_test.dart`（S13 回放、本地 WebSocket 服务器端到端、换场次的 8 个时序用例）。
- 真实接口：2026-09-30 录 S13-audience；E01.4 的“国内平台完善”匿名直连 731918444565、653206915660 各 2 分钟，聊天 532 和 22 条都有发送时间，在线人数 21 和 30 次。
- 真机：没有单独的真机记录；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（抖音热门直播间）还没逐条填结果。

## 留下的问题

- 主播下播后重新开播的真实过程没录到，换场次只用合成帧测过；要在真机上留意（直播间里等主播重新开播，看 2～3 分钟内弹幕是否接上）。
- 本机时钟和抖音相差 45 s 以上时，B-5 之后的聊天会被去重闸门当作过期丢掉（所有带发送时间的平台都一样）。
- 握手的 User-Agent 带 `Dart/3.13 (dart:io)` 前缀：B-2 的开关（`PURE_LIVE_PLAIN_WS_UA`，`apps/pure_live/lib/app/platforms.dart` 的 `plainDanmakuUserAgent`）默认关，要在 Android 真机逐平台验证后再改。
- 礼物：匿名网页端收不到 `WebcastGiftMessage`，没做。
