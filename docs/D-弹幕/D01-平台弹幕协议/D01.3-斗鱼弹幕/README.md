# D01.3 斗鱼 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `04717fcf9`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 2 个平台）：把 3.x 的 `lib/core/danmaku/douyu_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.2、T06a.3
- 相关：决定 D-001（照 3.x 逐块重构）、D-017（测试不访问真实平台）；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身 [E01.2](../../../E-直播平台/E01-国内五大平台/E01.2-斗鱼/README.md)（真实房间号、后来的礼物和下播通知在 [E01.2 记录](../../../E-直播平台/E01-国内五大平台/E01.2-斗鱼/record.md)“国内平台完善”“附录 C 落地”两节）；“过滤斗鱼疑似机器人弹幕”开关在屏蔽页 [A08.3](../../../A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/README.md)，设置存储在 [J01.1](../../../J-设置和数据/J01-设置/J01.1-设置/record.md)；巡检 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)
- 记录：[record.md](record.md)

## 目标

斗鱼直播间的弹幕照 3.x 连上和显示：聊天、醒目留言、语音醒目留言，“疑似机器人”过滤开关照旧生效、改了不用重连；同时修掉 3.x 审查出的 5 个问题（STT 递归解析把 `@Alice` 显示成 `@lice`、链接变成列表；语音醒目留言没有头像；开箱通知当成 0 元醒目留言；包长按 UTF-16 算；文本帧抛错）。后来（E01.2）又加了礼物上报和下播通知：主播下播后弹幕区显示连接结束，不再一直重连。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | 只有 `wss://danmuproxy.douyu.com:8506`（`DouyuApi.danmakuServer`，`packages/live_core/lib/src/sites/douyu/douyu_api.dart:157`），匿名，不带请求头和子协议；房间号是 `DouyuDanmakuArgs`（`douyu_api.dart:57`）里的真实房间号（E01.2 由 `betard` 的 `room.room_id` 得到，`douyu_site.dart:226`，靓号和别名已换掉） |
| 包 | `长度(4) 长度(4) 类型(2) 加密(1) 保留(1) 包体 \0`，小端，长度 = 8 + 包体 UTF-8 字节数 + 1；客户端类型 689，服务端 690（不检查）；一帧多包，按每个包自己的长度切开（`bodies`，`douyu.dart:140`），长度小于 9 或越界就停，每个包最后一个字节丢掉、不检查是不是 `\0` |
| 加入 | 打开即就绪（`onOpen` 先 `session.ready()`，`douyu.dart:374-376`），随后发 `type@=loginreq/roomid@=<房间号>/` 和 `type@=joingroup/rid@=<房间号>/gid@=-9999/`；每次重连都重新发；没有加入计时器，不等 `loginres` |
| 心跳 | 45 s 发 `type@=mrkl/`（`heartbeatInterval`，`douyu.dart:99`）；服务端的 `pingreq` 不回应；无消息 135 s（max(3 × 45 s, 90 s)）换连接；握手超时 10 s；只有一个地址，重连间隔 2、3、4、5、6、6、6、6 s，连续失败 8 次放弃（`DanmakuSocketPolicy` 默认值，`socket_connection.dart:15-24`；退避算法在 `packages/live_net/lib/src/socket.dart:351`） |
| 文本格式 | STT（`key@=value/`，`@A` 表示 `@`、`@S` 表示 `/`）；4.x 的 `DouyuStt`（`douyu.dart:60`）按层解析，每个值只反转义一次，只有确实嵌套的字段（醒目留言的 `chatmsg`、语音醒目留言的 `list` 和 `uat`）再解析一层 |
| 聊天 | `chatmsg`：`rid` 不为空且和房间不同就丢，`txt` 为空就丢；昵称 `nn`、用户 id `uid`、文字 `txt`；颜色 `col` 走 3.x 的 6 色表（`color`，`douyu.dart:204`，其余白色，不经过 `numberToColor`）；时间 `cst`（大于 10¹¹ 按毫秒，否则按秒）；消息 id `douyu:<cid>` |
| 醒目留言 | `comm_chatmsg`：开始 `now`（毫秒）、时长 `cet`（秒）、价格 `cprice`（分，除以 100），嵌套的 `chatmsg{nn, txt, ic}`，头像 `https://apic.douyucdn.cn/upload/<ic>_small.jpg`，配色 `#c1c1ff`/`#292a60`；价格或时长不大于 0 的（开箱通知）不算 |
| 语音醒目留言 | `voice_trlt`：取 `list` 第一项的 `acptime`、`etime`（秒）、`realPrice`（分）、`content`、`un`，头像 `https://` + `uat` 第二项，配色 `#ffffff`/`#246488` |
| 礼物（E01.2 加） | `dgb`：报成 `LiveMessageType.gift`，数据 `DouyuGift`（`douyu.dart:15`：`gfid`、`gfn`、`gfcnt`、`hits` 连击、`receive_nn` 收礼人），文字 `<礼物名> ×<数量>`；别的房间的、没有名字的不报；`gfid` 为 0 的背包道具编号为空；包里没有消息 id 和时间 |
| 下播（E01.2 加） | 本房间（或包里没有 `rid`）的 `rss` 且 `ss@=0`：`read` 报告下播，同一帧里它之前的消息照常上报、之后的不读，连接以 `connectionFailed`（`Broadcast ended`）结束、不重连；开播（`ss@=1`）和别的房间的不报 |
| 过滤 | 没有 `dms` 且 `if` 不是 `1` 的聊天（`isSuspectedAutomated`，`douyu.dart:216`）只在设置 `filterDouyuSuspectedAutomatedMessages`（`packages/live_store/lib/src/settings/settings.dart:584`，默认关）打开时丢；每条疑似的读一次设置，改了不用重连 |
| 出错 | 一个包解析失败（例如时间戳超出 `DateTime` 范围）只丢这一个包，同帧后面的照常；文本帧忽略 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/douyu_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/douyu.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `DouyuDanmaku`（:14），`DouyuSite.getDanmaku()`（`core/site/douyu/douyu_site.dart:70`）把设置读取函数传进去 | `DouyuDanmakuConnection`（:346）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:203-207`，同样传 `settings.get(Settings.filterDouyuSuspectedAutomatedMessages)` | 一致（已做） |
| 地址和心跳 | `serverUrl`（:45）、`heartbeatTime = 45 * 1000`（:21），`WebScoketUtils` 默认的超时和重连 | `DouyuDanmakuProtocol.endpoint`（:96）、`socketPolicy`（:357）、`heartbeatInterval`（:99） | 一致 |
| 就绪和加入 | `onReady` 里先 `markConnected`、报就绪，再 `joinRoom`（:69-74、:92-94） | `onOpen`（:374）先 `ready`，再发 `joinPackets`（:128-131） | 一致；发出的包和 3.x、录制逐字节相同 |
| 包长 | `serializeDouyu` 按字符串长度（UTF-16 码元，:221-222） | `packet`（:111）按 UTF-8 字节数 | 修好（3.x 问题 4；只发 ASCII，线上没影响） |
| STT 解析 | `sttToJObject`（:118、:267-295）每个值递归猜结构，普通文字被反转义两次 | `DouyuStt`（:60）按层解析 | 修好（3.x 问题 1）：文字和昵称不再被改 |
| 聊天 | `decodeMessage` 的 `chatmsg` 分支（:123-144），过滤在 :129-130 | `_chat`（:220） | 147 条录制聊天逐字段一致 |
| 醒目留言 | `_parseCommonSuperChat`（:159-178）只检查字段在不在，开箱通知变成 0 元醒目留言 | `_superChat`（:244）价格或时长不大于 0 的不算 | 修好（3.x 问题 3） |
| 语音醒目留言头像 | `_parseVoiceSuperChat`（:180），头像永远是空（:188-189，`uat` 被解析成字符串） | `_voiceSuperChat`（:271），`https://` + `uat` 第二项（:279） | 修好（3.x 问题 2） |
| 文本帧 | `decodeMessage(List<int>)` 收到文本帧抛类型错误（:66-67） | `onData`（:381）只收二进制（:383） | 修好（3.x 问题 5） |
| 礼物、下播 | 不处理 | `dgb` 报成礼物（`gift`，:300）；`rss` 下播时 `read`（:168）报告结束，连接以 `connectionFailed`（`broadcastEnded`，:362、:390）结束 | 礼物在聊天列表里单独一行（B-21，C01.2）；下播后不再一直重连 |
| 过滤开关 | `SettingsService.to.danmaku.filterDouyuSuspectedAutomatedMessages`（`douyu_site.dart:71`） | 设置 `settings.dart:584`；屏蔽页开关 `apps/pure_live/lib/shared/danmaku/block_manager.dart:334-335` | 一致，改了不重连 |

## 结果

- **提交**：`04717fcf9`（2026-09-29，`feat(live_danmaku): Douyu danmaku refactored from v3 (M5.2)`）。之后同一文件的改动属于 E01.2：`8eca75a32`（2026-10-01，礼物上报，“国内平台完善”）、`398f68f87`（2026-10-01，下播通知结束连接，附录 C-6）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/douyu/danmaku/legacy_expected.dart` 把 3.x 的解码代码原样搬成独立程序生成冻结输出。S13-live（房间 9999，约 30 s，183 帧收到）的 147 条聊天顺序、所在帧和全部字段一致，发出的 `loginreq`、`joingroup`、心跳和 3.x、录制逐字节相同；S14-synthetic 17 组合成帧除 3 处有意差异（文字不再被改、语音醒目留言有头像、开箱通知不是醒目留言）外一致；打开过滤后录制的 147 条全部保留（都带 `dms` 或 `if=1`），和 3.x 一样。
- **有意差异**（record.md“与 v3 的有意差异”6 条）：按层解析文字、语音醒目留言头像、0 元 `comm_chatmsg` 不算、包长按 UTF-8、文本帧忽略、`connect` 只接受 `DouyuDanmakuArgs`。保持 3.x 的地方：打开即就绪、只检查聊天的 `rid`、`cst=0` 仍是 1970 年（被 D01.1 的去重闸门丢掉）、每个包最后一个字节不检查、不显示进场和榜单。
- **样本**：`fixtures/douyu/danmaku/` 下 S13-live（`frames.jsonl`、`expected.json`）、S14-synthetic（`cases.json` 17 组、`expected.json`），后来 E01.2 加了 S15-gifts（9263298 的 57 个 `dgb` 包体，已脱敏）、S16-broadcast-end（1 个 `rss` 包体）。
- **测试**：`packages/live_danmaku/test/douyu_test.dart` 现在 45 个（当时 40 个：协议 6、录制对照 3、合成对照 18、连接 13；E01.2 礼物 +3、下播 +2）。其中 17 个由 S14 的 `cases.json` 循环生成（`douyu_test.dart:463-466`），所以 `grep -c "test("` 只数到 29（28 个固定的加循环里的 1 处）。

## 验证

- 自动测试：`douyu_test.dart`——协议（加入包和心跳逐字节、UTF-8 包长、切包、STT 转义、颜色表、疑似机器人判定）；S13 录制逐帧对照 3.x；S14 17 组合成帧对照 3.x；礼物（S13 的 125 个、S15 的 57 个、别的房间和没名字的）；下播包（S16）和以 `Broadcast ended` 结束不重连；连接（地址、立即就绪、45 s 心跳、135 s 静默、无加入计时器、重连退避 2～6 s、换房间、设置每条读取不重连、文本帧忽略）；本地 WebSocket 服务器端到端回放录制。
- 真实接口：2026-09-30 匿名直连 266609、9263298 各 120 s，都立即就绪，各收到 1 条聊天都解出，9263298 收到 57 条礼物；2026-10-01 同时加入 200 个直播间 6 分钟，录到 1 个下播包（12850251）和 114 条醒目留言（E01.2 记录“真实环境检查”“附录 C 落地”）。
- 真机：没有单独的真机记录（S02.2、S02.3 进的是哔哩哔哩直播间）。对应 [真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（斗鱼热门直播间有弹幕、断网后重连）和第 4 条（打开机器弹幕过滤），结果一列还是空的。登记表状态是“完成”。

## 留下的问题

- 进房时补上还在显示的醒目留言（附录 C-5）：查了 PC 和手机网页的 100 多个脚本分包都没找到列表接口，醒目留言仍只从弹幕来。[specs/UPGRADES.md](../../../specs/UPGRADES.md) 记为“受阻，未排”；没有任务（E01.2 记录候选 D-1），找到接口前做不了；巡检时顺带留意（[E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)）。
- 加入一个已下播或轮播的房间时服务端会不会立刻发 `ss@=0` 的 `rss` 没验证（录到的都是直播中的房间）；如果会，轮播房间的弹幕会马上结束。去向：真机清单第 2 节第 1 条和 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 的弹幕 120 秒检查，进一个轮播房间（例如 93976）看一次。
- 平台通知 `hpsc`、`blab`、`spbc` 不显示，贵宾数 `oun`/`oni` 不上报（口径不是在线人数）：没有任务，E01.2 记录候选 D-2、D-3 决定不做。
- 礼物现在在聊天列表里单独一行（C01.2 按 B-21 做的，可在弹幕设置里关），不用另开任务。
- 真机结果还没有：等 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 统一验证或下一次 K90 验证时补第 2 节第 1、4 条。
