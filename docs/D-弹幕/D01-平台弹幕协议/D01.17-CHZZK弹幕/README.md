# D01.17 CHZZK 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 00da1b768）
- 类型：平台
- 来源：已批准升级 20-2“CHZZK 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有 CHZZK 这个平台但没有弹幕，这是新增功能。后续的 B-12（捐赠、撤回、通知、换频道）是同一升级表附录 B 的条目
- 旧编号：M5.16、T06a.17
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数（`chatChannelId`、`channelId`）[E03.7 记录](../../../E-直播平台/E03-海外平台/E03.7-CHZZK/record.md)；表情图片在聊天行（[C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)、[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md)）和飞行弹幕（[D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)）；握手的 User-Agent [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)；决定 D-017；详细记录 [record.md](record.md)

## 目标

CHZZK（韩国 NAVER 直播）直播间能看到聊天。照网站的 NAVER 聊天 SDK 4.11.0 选服务器、加入、心跳、重连，修掉归档 v4 用公式算出路由不列出的服务器、把聊天连接数当在线人数、被拒后换令牌无用重试、超出范围的时间丢整行等问题。后来（B-12）捐赠显示为醒目留言（按金额分五档时长），事后屏蔽撤回那一行，置顶公告、订阅赠送、系统行显示为通知；聊天安静 3 分钟后读一次直播状态，主播重新开播换了聊天频道就跟过去。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/chzzk.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 参数 | `ChzzkDanmakuArgs(chatChannelId, channelId)`（E03.7，进房给出）；`chatChannelId` 去空白后不合格式（`isChatChannelId` :177）时以 `connectionFailed` 结束、不发请求 |
| 开始的请求 | 同时发（`target` :690，平台层请求头 `ChzzkApi.headers`，不跟随跳转，`connect` 结束时都取消）：访问令牌 `comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=<chatChannelId>&chatType=STREAMING`（`tokenUrl` :180、`accessToken` :187、`_token` :714；最多 3 次 `tokenAttempts` :661，间隔 0.5、1 s，每次 5 s `tokenTimeout` :664；拿不到以 `credentialsUnavailable` 结束）和服务器列表 `routing.chat.naver.com/routing/getRouting?serviceId=game`（1 次，1.5 s `routingTimeout` :667；`servers` :195 只收 `*.chat.naver.com`、去重、最多 16 个 `maxServers` :154；失败用 SDK 内置的 `kr-ss1`～`kr-ss5` `defaultServers` :145）。令牌和列表整个 `connect` 期间沿用（实测只读加入不检查令牌） |
| 地址 | `wss://<服务器>/chat`（`endpoints` :207），从随机一台开始（网站对直播聊天用 `RANDOM`），失败按列表轮换；请求头 `origin: https://chzzk.naver.com` 和平台层桌面 UA（`handshakeHeaders` :161）；默认 `dart:io` 握手；按平台 `chzzk` 走代理（`apps/pure_live/lib/app/platforms.dart:223`） |
| 加入 | 打开后发只读加入 `cmd 100`（文本，`auth: READ`、`devType 2001`，`join` :214、`onOpen` :777）；`cmd 10100` 的 `retCode 0` 就绪，并用 `bdy.sid` 请求最近 50 条（`cmd 5101`，`recent` :224，`recentCount` :94）；加入超时 5 s（`joinTimeout` :91）；`retCode` 302、303、304（`retryCodes` :142）按退避重连，其他以 `connectionFailed` 结束并写明码和原因（实测不存在的聊天频道回 105 后服务端关连接）；服务端 `cmd 90102`（结束会话）也以 `connectionFailed` 结束（`decode` :296） |
| 心跳 | 20 s（`heartbeatInterval` :82）发 `{"ver":"3","cmd":0}`（`ping` :164），服务端回 `cmd 10000`；服务端发 ping 时立刻回 pong（`pong` :167）；无消息 30 s 换连接（`inactivityTimeout` :87，SDK 的 `pingInterval` + `pingTimeout`）；策略 `socketPolicy` :654～658 |
| 重连 | 框架默认退避，六台服务器轮换，间隔 1、1、1、1、1、2、2、2 s，连续 8 次失败以 `reconnectsExhausted` 结束；收到任何消息清零 |
| 聊天 | `cmd 93101`、`93102` 和最近聊天 `15101`（`retCode 0`）的行（`decode` :277～325、`line` :361）：种类 1 文本、11 订阅留言（没有种类当 1），状态 `NORMAL` 或没有；文字 `msg`/`content` 去首尾空白，表情留作 `{:名字:}` 并从 `extras.emojis` 填表情图片（`emojis` :401，S02.1）；名字 `profile.nickname`；用户 id `uid`/`userId`；时间 `msgTime`/`messageTime`（越界为空）；id `<用户>:<时间>`（`_id` :416，网站按用户和时间区分消息，没有时间就没有 id）；白色；`BLIND`、`CBOTBLIND` 的行不报 |
| 人数 | 行里的 `mbrCnt`、最近聊天的 `userCount` 是聊天连接数（和平台的 `concurrentUserCount` 相差 4%～75%），不报；人数仍来自列表和详情 |
| B-12 捐赠 | 种类 10、状态 `NORMAL`，`CHAT`、`VIDEO`、`MISSION`、`MISSION_PARTICIPATION`、`PARTY` 都算 → 醒目留言（`_donation` :426）：外壳写 `SUPER_CHAT_MESSAGE`；`price` 是 `extras.payAmount`（치즈）；`priceText` 如 `1,000 치즈`（`cheeseText` :137，金额为 0 时为空）；时长按金额 1 万、10 万、50 万、100 万分 1、2、5、30、60 分钟（`superChatDuration` :127，取哔哩哔哩前五档）；匿名名字是网站原文 `익명의 후원자`（`anonymousDonor` :115），id `anonymous:<时间>`；头像只收 NAVER 图片；没有时间用收到的时间（`clock`） |
| B-12 撤回 | `cmd 94008`（`blind` :555）：`blindType` 不是 `CANCEL` 时报 `LiveRetraction.message('<userId>:<messageTime>')`，正好是那一行的 id；按条撤回，不按用户撤回 |
| B-12 通知 | 置顶公告（`cmd 94010` 和最近聊天的 `bdy.notice`，`pinned` :523）：`<作者> 置顶了消息：<内容>` 等三种句子，id `notice:<用户>:<时间>`，`messageTime` 不大于 0 不报；订阅赠送（种类 12，`_subscriptionGift` :464）：`<赠送者> 向频道赠送了 5 张「<档次>」订阅券` 或 `<赠送者> 向 <接收者> 赠送了「<档次>」订阅券`；系统行（种类 30，`_system` :497）：`<标题>：<说明>`，`extras.visibleRoles` 不空（只给管理员看）的不报 |
| 同一连接去重 | 每次加入都拉最近 50 条：聊天由去重闸门按 id 去掉；醒目留言和通知不经过闸门，连接自己记住报过的 id（最多 512 个，`maxRemembered` :680） |
| B-12 安静检查 | 加入后或最后一次推送的行（93101、93102）起 3 分钟（`quietPeriod` :674）没有新行，读一次 `api.chzzk.naver.com/polling/v3.1/channels/<channelId>/live-status`（`liveStatusUrl` :237、`liveChatChannel` :243、`_checkLive` :823，5 s 超时 `liveStatusTimeout` :677）：`OPEN` 且 `chatChannelId` 变了就取新令牌、`reopen` 到新频道（不提示），新频道接受加入后再报就绪；相同、下播、失败、拿不到令牌就再等 3 分钟；`channelId` 不是 32 位十六进制时不检查 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有 CHZZK 这个平台但没有弹幕：`ChzzkSite.getDanmaku() => EmptyDanmaku()`（`core/site/chzzk/chzzk_site.dart:58`），直播间只提示一次 `remote_danmaku_not_integrated`（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `ChzzkDanmakuConnection`（`chzzk.dart:635`）继承 `DanmakuSocketConnection`；协议 `ChzzkDanmakuProtocol`（:80）；应用登记在 `apps/pure_live/lib/app/platforms.dart:223` | 有聊天（已做） |
| 人数 | 列表和详情的 `concurrentUserCount`；主播用 `cvExposure` 隐藏时不显示（REG-CHZZK-002） | `packages/live_core/lib/src/audience.dart:146～150` 仍是 `roomList`，弹幕不报聊天连接数 | 不显示聊天连接数（已做） |
| 醒目留言、撤回、通知 | 无 | 直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:893～906`：醒目留言栏、`chat.retract` 去掉那一行、通知行 | 已做 |
| 表情 | 无 | 聊天行图文混排（C01.2、S02.1 的 `LiveMessage.emotes`），飞行弹幕表情图（D03.2） | 已做 |

## 结果

- **提交**：00da1b768（2026-09-29，首次实现：令牌、路由、只读加入、心跳、聊天）；e1c4a3fa3（2026-10-01，B-12：捐赠、撤回、置顶、订阅赠送、系统行、安静检查）；fffd28b31（2026-10-01，[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 第 8 条：消息带表情图片）。
- **和归档 v4 的对照**：`fixtures/chzzk/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序。加入、最近聊天请求、ping 与录制逐字节相同（v4 发二进制，这里发文本）；S09-live 125 条聊天一致；S10-live 106 条聊天一致（B-12 后另有系统行和屏蔽通知，共 108 条消息；v4 另报人数）；S11-recent 123 条一致，另多 1 条订阅留言（B-12 后捐赠改为醒目留言）；S12-synthetic 15 组里 9 组一致、6 组有意差异。
- **有意差异**（record.md“与归档 v4 的差异”16 条和 B-12 的 3 条）：id 不加 `chzzk:` 前缀；不报人数；显示订阅留言；匿名名字用网站原文；只认种类 10 为捐赠；文本只收文字和数字；时间越界只让这一行没有时间、时间不大于 0 不生成 id；服务器按路由随机选；加入发文本、没有 `sid` 也算加入；令牌请求重试、被拒不换令牌；90102 结束；加入超时 5 s、无消息 30 s；结束原因用 D01.1 的类型。B-12：撤回按条不按用户；视频捐赠也显示为醒目留言；置顶公告和订阅赠送的句子是中文。
- **样本**：`fixtures/chzzk/S08-chat-token`；`fixtures/chzzk/danmaku/` 下 S09-live（归档）、S10-live（2026-09-28 录，已脱敏）、S11-recent、S12-synthetic（15 组）、S13-recent、S14-live、S15-live、S16-synthetic（6 组 42 帧）、S17-live-status-closed（2026-09-30 录）。
- **测试**：`packages/live_danmaku/test/chzzk_test.dart` 现在运行 74 个用例（源码里 58 个 `test(`，其中 3 个在循环里：S09/S10 对照 v4 各一个、S12 每组一个共 15 个、回放 S09/S10 各一个）；首次实现时 56 个（做过 25 种变异），B-12 后 74 个（+18，做过 21 种变异）。`packages/live_danmaku/test/emotes_test.dart` 里另有 CHZZK 表情的用例（S02.1）。

## 验证

- 自动测试：`chzzk_test.dart`——协议 11 个（令牌和路由回答、服务器列表、请求头、加入和 ping 与录制逐字节相同、聊天字段、不报人数）、录制对照 v4 5 个、S12 合成帧 17 个、连接 23 个（令牌和路由同时发、随机起点、就绪后请求最近聊天、回放 S09/S10、时序、拿不到令牌的 5 种情形、加入超时换下一台、被拒 105 结束、303 重连、90102 结束、退避轮换六台后放弃、换频道、本地 WebSocket 服务器端到端：路径、Origin、UA、加入、S10 的帧、服务端 ping 和 pong），B-12 18 个（醒目留言五档边界、S13～S16 录制和合成帧、安静 3 分钟读直播状态和换频道、各种失败时不动）。在 +30 天、+1 年、+5 年下运行都通过。
- 真实接口：2026-09-28（UTC 21:46～22:01）匿名直连：有效、编造、`null`、别的频道的令牌都能只读加入；不存在的聊天频道回 `retCode 105` 后服务端关连接；每场直播换一个聊天频道；约 300 ms 加入，ping 约 300 ms 得到 pong，两场各约 300 s 没有断线。2026-09-30（UTC 15:15～15:50）录 150 场的最近聊天、16 场各 900 s，得到 S13～S17。没实测到的：直播中换置顶（94010）、送给频道的订阅赠送、真正的换聊天频道（直播状态的开播、下播回答是真实的，换频道流程用本地假连接）。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节没有 CHZZK（第 7 条的表情只看快手、哔哩哔哩），海外平台要用户开代理；[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 第 8 条“CHZZK 表情显示成文字”来自直播间代码审查的记录，不是 K90 上看到的，修好后也没有上机看过。登记表是“完成”，按 D-029 这个平台的弹幕还算“没验证”。

## 留下的问题

- 主播重新开播后最多约 3 分钟才跟到新聊天频道（只在安静 3 分钟时读直播状态；网站每 30 s 读一次）：为少发请求有意这样定，没有任务。直播间的 60 s 详情刷新（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`）只在连接已经结束时重连，不比较 `chatChannelId`。
- 只读：不登录，不能发言，收不到只给管理员看的系统行：没有任务（发弹幕不在 4.x 的范围）。
- `익명의 후원자` 是网站原文，置顶和订阅赠送的句子是协议层拼的中文，都没走翻译文件：没有任务；按 D-005 用户看得到的文字应该进翻译文件，要改时在 C01 统一处理平台给的通知文字。
- 视频捐赠网站聊天列表不显示，这里显示为醒目留言（文字是视频标题）：有意差异，不改。
- 醒目留言的五档时长取自哔哩哔哩（网站没有时长）：自定，不改。
- 握手的 User-Agent：`dart:io` 会把 UA 接在 `Dart/<版本> (dart:io)` 后面，服务端接受；要发纯浏览器 UA 见 [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)。
- 真机上没看过（要用户开代理：聊天和表情、捐赠醒目留言、屏蔽撤回、置顶通知）：没有单独的任务，建议加进真机清单第 2 节，归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类的补验。
