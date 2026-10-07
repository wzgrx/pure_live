# D01.2 哔哩哔哩 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 1 个平台）：把 3.x 的 `lib/core/danmaku/bilibili_danmaku.dart` 逐行移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.1、T06a.2
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和后来的弹幕升级 [E01.1 记录](../../../E-直播平台/E01-国内五大平台/E01.1-哔哩哔哩/record.md)（“国内平台完善”“附录 C 落地”两节）；访客昵称提示、粉丝牌和头像 [D01.32](../D01.32-哔哩哔哩访客昵称和粉丝牌/README.md)；打码昵称不能屏蔽 [D02.1](../../D02-过滤和屏蔽/D02.1-打码昵称不能屏蔽/README.md)；决定 D-013；详细记录 [record.md](record.md)

## 目标

哔哩哔哩直播间的弹幕在 4.x 照 3.x 的行为连上、解码、重连：聊天、醒目留言、热度和累计观看都和 3.x 一样显示；同时修掉审查发现的 3 个 3.x 问题（认证被拒后无限重连、旧会话的凭据刷新串到新会话、文本帧抛错）。后来又改回网页用的 protover 3（Brotli），省约 13% 流量。

## 协议要点

| 项 | 内容 |
|---|---|
| 传输 | WebSocket 二进制；16 字节大端包头（包长、头长、protover、操作码、seq）；一条消息里可以有多个包，压缩包里是整段包序列，递归拆开 |
| 地址 | 房间参数 `BilibiliDanmakuArgs` 的 `servers`（E01.1 把通用网关排在最前，再接 `host_list` 的节点）；为空时 `wss://broadcastlv.chat.bilibili.com/sub` |
| 请求头 | 参数里的 UA、Origin、Referer 和同一份 Cookie（登录时带登录 Cookie，uid 取 Cookie 的 `DedeUserID`） |
| 加入 | 每次打开都发认证包（操作码 7），字段顺序同 3.x：`uid`、`roomid`、`protover`（3）、`buvid`、`support_ack`、`queue_uuid`（每次新生成 8 位十六进制）、`scene`、`platform`、`type`、`key`；收到操作码 8 且 `code == 0`、当前未加入时，先发一次心跳再报就绪 |
| 心跳 | 30 s，操作码 2、空包体；打开就开始发，认证完成前也发（3.x 如此）；无消息超时 90 s；加入超时 8 s，超时直接重连不提示 |
| 解码 | 操作码 3：4 字节热度 → `popularity`；操作码 5：protover 3 用 `live_net` 的 `brotliDecode`、protover 2 用 zlib 解压后递归，其他按 JSON；上限：单条消息 8 MiB、解压后 16 MiB、4096 个包、压缩嵌套 2 层 |
| 消息 | `DANMU_MSG`（文本 `info[1]`、颜色 `info[0][3]`、时间 `info[0][4]`、id `bilibili:` + `info[0][5]`）；`SUPER_CHAT_MESSAGE`（醒目留言，带 `data.id`）；`WATCHED_CHANGE`（累计观看）；后来加了 `ONLINE_RANK_COUNT`（在线人数）、`SEND_GIFT`/`COMBO_SEND`/`GUARD_BUY`（礼物，聊天列表里单独一行，B-21）、`RECALL_DANMU_MSG`、`SUPER_CHAT_MESSAGE_DELETE`（撤回）、`WARNING`/`CUT_OFF`（系统通知） |
| 昵称 | 依次取 `info[0][15]` 的 `user.base.name` 或 `origin_info.name`、顶层 `uinfo`、`data.uinfo`、`info[2][1]`，取第一个没有打码（`**` 或 `＊＊`）的；访客看到的基本都是打码昵称（D-013） |
| ACK | `p_is_ack` 为真且 `msg_id`、`cmd`、`p_msg_type` 齐全时，先回操作码 24 的 ACK 再上报 |
| 凭据 | 开始时没有 token：刷新凭据最多 3 次（间隔 500 ms、1000 ms），仍没有就 `DanmakuClosed(credentialsUnavailable)`；认证被拒：刷新后用新凭据 `reopen`，每次连接最多刷新 3 次，拿不到就结束 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/bilibili_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/bilibili.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `BiliBiliDanmaku`（:50），`BiliBiliSite.getDanmaku()`（`core/site/bilibili/bilibili_site.dart:26`） | `BilibiliDanmakuConnection`（:75）继承 `DanmakuSocketConnection`；应用在 `apps/pure_live/lib/app/platforms.dart:202` 登记 | 一致（已做） |
| 心跳和超时 | `heartbeatTime = 30 * 1000`（:63） | `defaultPolicy`（:91～93）：30 s、加入超时 8 s | 一致 |
| 认证包 | `joinRoom`（:179），`protover: 3`（:188），用 `package:brotli` | 认证包写法在 `BilibiliDanmakuProtocol`（:302 起），`protocolVersion = 3`（:327）；Brotli 用 `live_net` 的解码器（:452） | 和网页一致；先做过 protover 2，B-3 改回 3 |
| 解码 | `decodeMessage`（:260），`DANMU_MSG`（:374）、`WATCHED_CHANGE`（:398）、`SUPER_CHAT_MESSAGE`（:411） | `decode`（:403），按 `cmd` 分发（:484～495） | 3.x 的三种全部一致，另加撤回、通知、在线人数、礼物 |
| 认证被拒 | `_refreshCredentialsAndReconnect`（:161）：刷新失败就返回，被拒的连接用旧 token 无限重连、反复提示 | `onData` 里刷新后 `reopen`，拿不到就 `credentialsUnavailable`（:210、:225） | 修好（3.x 问题 1） |
| 凭据状态 | 属于实例，同房间重建时旧会话的刷新串进新会话 | 属于一次连接（`DanmakuRun`），被取代后丢掉 | 修好（3.x 问题 2） |
| 文本帧 | 当字节数组处理，抛类型错误 | 忽略 | 修好（3.x 问题 3） |
| 醒目留言 id | 没有 | 外层消息和 `LiveSuperChatMessage` 都带 `data.id`，与进房拉的醒目留言板按 id 合并 | 不重复显示 |
| 打码判断 | 直播间控制器里的正则 | `isMaskedName`（:115、:344），直播间用它提示（D01.32）和禁止屏蔽（D02.1） | 已做 |
| 粉丝牌和头像 | 不显示 | `_medal`（:615）读 `user.medal`；头像 `user.base.face` 放进 `DanmakuSender`（:595～607）（D01.32） | 已做，待真机（D01.32） |

## 结果

- **提交**：95adcea10（2026-09-29，M5.1 从 3.x 移植），95cf8473e（2026-10-01，B-3 改回 protover 3）。之后同一文件的改动属于其他任务：81733c1e6（醒目留言 id、撤回、警告和切断通知，E01.1 的“国内平台完善”）、e8a00e0d4（在线人数和礼物，E01.1 的“附录 C 落地”）、fffd28b31（消息带表情图片，[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 的真机问题修复）、2eea8022a（粉丝牌和头像，D01.32）。
- **和 3.x 的对照**：用 3.x 解码器的冻结输出逐条比较。S13-live（161 条真实消息）全部一致；S13-vectors（28 个合成向量）只有 5 处有意差异（颜色按修正后的 `numberToColor`、醒目留言的 `messageId` 和头像地址）。protover 3 和 protover 2 同时录的两份样本（240 s）解出的 2570 条通知逐条相同。
- **有意差异**（record.md 第“与 v3 的有意差异”节）：认证被拒拿不到新凭据时结束；醒目留言字段按 E01.1 快照的读法；`info` 形状不对整条丢；文本帧忽略；解码错误作为返回值不写日志。
- **样本**：`fixtures/bilibili/danmaku/` 下 S13-live、S13-vectors、S13-protover3、S13-protover2-paired、S13-brotli-vectors，都附 3.x 的冻结输出 `expected.json`（`legacy_expected.dart` 生成）。
- **测试**：`packages/live_danmaku/test/sites/bilibili_test.dart` 现在 38 个用例（M5.1 时 23 个，B-3 后 28 个，之后撤回和通知 +3、在线人数和礼物 +3、粉丝牌和头像等 +4）。

## 验证

- 自动测试：`bilibili_test.dart`（协议、冻结输出对照、连接的 15 个时序用例、本地 WebSocket 服务器）；M5.1 时做过 11 个变异、B-3 做过 5 个变异，都能被测试发现。
- 真实接口：2026-09-30、10-01 游客直连跑过（E01.1 记录：545068 房间 120 s 收到 157 条聊天、27 次人数；两次共约 9 分钟收到 562 次在线人数、2 次上舰）。
- 真机：没有单独的真机记录。[S02.2 冒烟](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（2026-10-02）在 K90 进直播间看到聊天和带表情图的飞行弹幕；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1、7 条（断网重连、醒目留言、表情）还没逐条填结果。访客昵称提示、粉丝牌和头像在 D01.32 待真机。

## 留下的问题

- 访客收到的礼物是 `SEND_GIFT_V2`（Base64 的 protobuf），现在不解析，访客只能收到上舰：候选，记在 E01.1 记录“附录 C 落地”的候选表，归 [E06.1](../../../E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/README.md) 一类的平台升级。礼物的显示已按 B-21 做好（C01.2：聊天列表里单独一行，可在弹幕设置里关）。
- 禁言通知（`ROOM_BLOCK_MSG`、`ROOM_SILENT_ON/OFF`，附录 C-3）没录到样本，没做。
- 心跳回复的热度访客恒为 1，照 3.x 上报，由直播间合并时丢掉（`LiveRoom.withAudienceFallbackFrom`）。
- 坏的 Brotli 包丢掉这条消息剩下的部分（网页逐包跳过）；服务端每条消息只放一个包，实际没有区别，不改。
