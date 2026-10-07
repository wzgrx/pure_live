# D01.5 抖音 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `a4959ea90`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 4 个平台）：把 3.x 的 `lib/core/danmaku/douyin_danmaku.dart` 和生成的 protobuf 类移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一；2026-10-01 又做了已批准升级 B-5
- 旧编号：M5.4、T06a.5
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`onReconnectsExhausted` 由本任务加进框架）；平台本身 [E01.4](../../../E-直播平台/E01-国内五大平台/E01.4-抖音/README.md)（签名 `DouyinSigner.danmakuSignature`、弹幕参数和 `refresh`，见 [E01.4 记录](../../../E-直播平台/E01-国内五大平台/E01.4-抖音/record.md)）；protobuf 读取器后来和 AcFun 共用（[D01.10](../D01.10-AcFun弹幕/README.md)）；握手 UA [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（B-2）；巡检 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 B-5
- 记录：[record.md](record.md)

## 目标

抖音直播间的弹幕照 3.x 连上和显示：聊天和在线人数，按要求回 ACK，两个节点轮流重连；不再依赖 `package:protobuf` 和 7500 行生成代码；修掉 3.x 的两个问题：2038 年后开播的房间 room_id 越过 2^63 弹幕全丢、一帧里一条坏消息丢掉后面全部。后来（B-5）在线人数改用精确整数、聊天补上发送时间、主播重新开播时自动换到新场次。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `DouyinDanmakuArgs`（`packages/live_core/lib/src/sites/douyin/douyin_api.dart:20`）：web_rid、本场 room_id、19 位访客号（reflow 的 `user_unique_id`，否则适配器自己的访客号）、会话 Cookie（用户的，否则匿名 ttwid）、握手头 `headers`，B-5 起另带 `refresh`（重新取一次详情） |
| 地址 | `wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/`、`wss://webcast100-ws-web-hl.douyin.com/webcast/im/push/v2/`（`hosts`、`path`，`douyin.dart:37-40`；`endpoints`，`:66`），同一组 31 个查询参数，顺序同 3.x（`app_name=douyin_web`、`version_code=180800`、`webcast_sdk_version=1.0.15`、`compress=gzip`、`cursor=h-1_t-<开始时的毫秒>_r-1_d-1_u-1`、`user_unique_id`、`room_id`、`need_persist_msg_count=15`、`heartbeatDuration=0`、`signature` 等）；`signature` 是本地算的 X-Bogus，每次 `connect` 算一次、重连沿用，作为参数值编码（`+`、`/` 变 `%2B`、`%2F`） |
| 请求头 | `user-agent`（Chrome 134）、`cookie`（去空白后非空才带）、`origin: https://live.douyin.com`、`referer: https://live.douyin.com/<web_rid>`，即 `DouyinDanmakuArgs.headers`；`dart:io` 会在 UA 前面加 `Dart/3.13 (dart:io), `（3.x 也一样，见 Q03.1） |
| 编码 | protobuf `PushFrame`（logId 2、payloadEncoding 6、payloadType 7、payload 8）→ 负载 gzip 解压（`payloadEncoding` 转小写为 `gzip`，或负载以 `1f 8b` 开头）→ `Response`（messages 1、internalExt 5、needAck 9）→ `Message`（method 1、payload 2、msgId 3）列表；手写读取器 `packages/live_danmaku/lib/src/codec/protobuf.dart`（`ProtoMessage`、`ProtoWriter`，197 行） |
| 加入和心跳 | 打开即就绪，随后发一个 `PushFrame{payloadType: "hb"}`（4 字节 `3a 02 68 62`，`heartbeat`，`douyin.dart:105`）当作加入；心跳 10 s（`:43`）；服务端心跳回复和 `heartbeatDuration`（录到 15）不处理；无消息 45 s 换连接（3.x 单独设的，`:46`）；两个节点轮流，等待 1、2、2、3、3、4、4、5 s，8 次后放弃；没有加入计时器 |
| ACK | `Response.needAck` 为真时先回 `PushFrame{logId: 原帧 logId, payloadType: "ack", payload: internalExt}`（`ack`，`:110`，三个字段为空也照写）再上报；帧本身（含 headers、解压、`Response`、每个 `Message` 外壳）读不出来时整帧丢弃、不回 ACK |
| 聊天 | `WebcastChatMessage`（`_chat`，`:172`）：`common.roomId` 不为 0 且不是本场就丢；id 取 `common.msgId`，为 0 取外层 `Message.msgId`，加 `douyin:`；uint64 按无符号打印；时间先 `common.createTime`，B-5 起没有时用 `ChatMessage.eventTime`（字段 15），大于 10¹¹ 按毫秒、否则按秒；昵称 `user.nickName`，用户 id `user.id`（没有 `user` 为 `0`）；颜色一律白色；文字为空照样上报 |
| 在线人数 | `WebcastRoomUserSeqMessage`（`_online`，`:210`）：B-5 起 `total`（字段 3）大于 0 就用它，否则照 3.x 用 `onlineUserForAnchor`（字段 10，如 `30.6万` → 306000）含数字时的文字；报 `onlineViewers`；`totalUser`（字段 7）是累计，不用 |
| 其他 | 进场、礼物、点赞、关注、榜单等方法忽略（匿名网页端也收不到 `WebcastGiftMessage`）；文本帧忽略 |
| 换场次（B-5） | 参数带 `refresh` 时：每分钟看一次有没有收到任何消息（`quietTick`，`:50`），连续 2 分钟没有就查一次详情，同一场就之后在再连续 4、8 分钟后查，以后每 16 分钟（`quietChecks`，`:55`）；重连耗尽时也查一次（`onReconnectsExhausted`，`:320`）；同一时间只查一次，最多等 10 s（`refreshTimeout`，`:58`）；room_id 变了就用新签名、新游标 `reopen`，失败次数从头算，不提示；没变、不在直播、失败或超时：安静检查什么都不做，耗尽时照旧以 `reconnectsExhausted` 结束 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/douyin_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/douyin.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `DouyinDanmaku`（:39），`DouyinSite.getDanmaku()`（`core/site/douyin/douyin_site.dart:28`） | `DouyinDanmakuConnection`（:251）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:210`（注释 :209 说明参数带 `refresh`） | 一致（已做） |
| 节点和超时 | 两个节点 :70-71，`heartbeatTime = 10 * 1000`（:41），`inactivityTimeout` 45 s（:136） | `hosts`（:37）、`heartbeatInterval`（:43）、`inactivityTimeout`（:46）、`socketPolicy`（:263） | 一致；地址和 3.x 的 `buildServerUrls`（:174）、录制的握手地址逐字相同 |
| protobuf | `package:protobuf` 6.1.0 和生成的 `core/danmaku/proto/douyin.pb.dart` | 手写读取器 `src/codec/protobuf.dart`，只读用到的十来个字段 | 正常数据结果相同 |
| 解码 | `decodeMessage`（:201），整帧只有 `start` 里的一个 `try`（:139-140） | `decode`（:124）按方法分发（:147-148），每条消息单独 `try` | 一条坏的只丢自己（修 3.x 问题 2） |
| uint64 编号 | `common.roomId.toString()`（:228）、`msgId`（:230）、`user.id`（:248）按有符号打印，2038 年后开播的房间 room_id 变负数，和参数永远不等，弹幕全丢 | 按无符号打印 | 修好（3.x 问题 1）；现在的编号都小于 2^63，结果不变 |
| 在线人数 | 只取 `onlineUserForAnchor` 文字（:257） | `_online`（:210）`total` 优先（:212-215） | 1 万以上显示精确人数（305503，以前 306000）（B-5） |
| 聊天时间 | 只看 `createTime`（:234），录到的聊天都没有，`sentAt` 为空 | `_chat` 里没有 `createTime` 时用 `eventTime`（:180-190） | 聊天有时间，去重闸门开始做 45 s 检查（B-5） |
| 重新开播 | 沿用旧 room_id，要重新进房 | `refresh` 回调（`DouyinSite` 放进参数）、安静计时 `_watch`（:334，在 `target` :276 启动）、`onReconnectsExhausted`（:320），查询 10 s 超时（:58） | 2～3 分钟内自动接上新场次（B-5，没实测真实的重新开播） |

## 结果

- **提交**：`a4959ea90`（2026-09-29，`feat(live_danmaku): Douyin danmaku refactored from v3 (M5.4)`），`54baa1109`（2026-09-29，protobuf 读取器从 `sites/douyin/` 移到 `src/codec/`，和 AcFun 共用），`03aa04354`（2026-10-01，B-5：精确人数、事件时间、换场次）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/douyin/danmaku/legacy_expected.sh` 在临时目录用 3.x 的 protobuf 运行时跑 3.x 的解码（`legacy_expected.dart`），生成冻结输出，仓库不加依赖。S13-live（房间 148108118778，81 帧收到）78 个 ACK、215 条聊天、16 次在线人数逐条一致，心跳和 ACK 与录制逐字节相同；S13-vectors 25 个向量里 21 个一致、4 个是有意差异（无符号打印、坏消息只丢自己）。B-5 后期望改为“3.x 的输出加上 `eventTime` 和 `total`”。
- **有意差异**（record.md 5 条）：uint64 无符号打印、每条消息单独解码、只检查用到的那一层格式、`connect` 只接受 `DouyinDanmakuArgs`、解码错误作为返回值不写日志。保持 3.x：文字为空的聊天照样上报、room_id 为空照样连接、不处理心跳回复和 `heartbeatDuration`、不显示礼物进场点赞。
- **框架的添加**：`DanmakuSocketConnection.onReconnectsExhausted`（`packages/live_danmaku/lib/src/socket_connection.dart:192`，调用在 `:390`），默认 false，目前只有抖音覆盖。
- **样本**：`fixtures/douyin/danmaku/` 下 S13-live（`frames.jsonl`、`expected.json`）、S13-vectors（25 个合成向量 36 帧，目录里有 README）、S13-audience（B-5，5 个直播间 150 s，在线人数 2～77726，已脱敏）。
- **测试**：`packages/live_danmaku/test/sites/douyin_test.dart` 现在 63 个（当时 50 个：protobuf 读取器 4、发出的帧和握手 4、录制对照 3、合成对照 26、连接 13；B-5 加 13 个）。其中 25 个由 S13-vectors 循环生成（`douyin_test.dart:723-725`），所以 `grep -c "test("` 只数到 39。另做过 15 个变异（B-5 再 2 个），都会让测试失败。B-5 同时给 `socket_connection_test.dart` 加了 2 个（框架接管后 `reopen` 和自己结束）、`live_core` 的 `douyin_site_test.dart` 加了 1 个（`refresh`）。

## 验证

- 自动测试：`douyin_test.dart`——protobuf 读取器（变长整数、wire type、合并、坏 UTF-8）；心跳、地址、握手头、ACK 与 3.x 和录制逐字节相同；S13-live 81 帧对照 3.x；25 个向量对照 3.x；S13-audience 在线人数都等于 `total`、333 条聊天都有 `eventTime`；连接（第一个节点、签名、游标、就绪和加入心跳、10 s 心跳、45 s 静默、退避 1～5 s 节点交替、换房间、本地 WebSocket 服务器端到端）；换场次的 8 个时序用例（安静 2 分钟换场、间隔 2/4/8/16/16 分钟、查询失败超时不影响、耗尽后换场或结束、关闭后丢弃）。
- 真实接口：2026-09-30 录 S13-audience（5 个房间 150 s，`total` 和文字的关系逐条核对）；E01.4 的“国内平台完善”匿名直连 731918444565、653206915660 各 2 分钟，聊天 532 和 22 条（都有发送时间），在线人数 21 和 30 次，两个房间约 2000 条消息里没有 `WebcastGiftMessage`（E01.4 记录“真实环境检查”）。
- 真机：没有单独的真机记录。对应 [真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（抖音热门直播间有弹幕、断网后重连），结果一列还是空的。登记表状态是“完成”。

## 留下的问题

- 主播下播后重新开播的真实过程没录到，换场次只用合成帧测过：没有任务；真机上留意（直播间里等主播重新开播，看 2～3 分钟内弹幕是否接上），巡检 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 遇到时补录样本。
- 本机时钟和抖音相差 45 s 以上时，B-5 之后的聊天会被去重闸门当作过期丢掉：所有带发送时间的平台都一样，没有任务（闸门的规则在 D01.1）。
- 握手的 User-Agent 带 `Dart/3.13 (dart:io)` 前缀：B-2 的开关（`PURE_LIVE_PLAIN_WS_UA`，`apps/pure_live/lib/app/platforms.dart:245` 的 `plainDanmakuUserAgent`）默认关，在 K90 逐平台验证后再改为默认开，去向 [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)。
- 礼物：匿名网页端收不到 `WebcastGiftMessage`（E01.4 和 B-5 录的 7 个房间都没有），没做；没有任务，除非以后登录后能收到再考虑。
- 抖音会把少数聊天约 0.6 s 后用同一个 msgId 再推一次（S13-audience 333 条里 8 条），去重闸门按 id 去掉，行为正确，不用改。
- 真机结果还没有：等 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 统一验证或下一次 K90 验证时补第 2 节第 1 条。
