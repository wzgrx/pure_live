# D01.22 PandaTV 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 2a6b552b2）
- 类型：平台
- 来源：已批准升级 25-2“PandaTV 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有 PandaTV 这个平台但没有聊天，这是新增功能。附录 B 没有 PandaTV 的后续条目
- 旧编号：M5.21、T06a.22
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；同样在握手前插请求的 [D01.12 TwitCasting](../D01.12-TwitCasting弹幕/README.md)、[D01.21 BIGO LIVE](../D01.21-BIGOLIVE弹幕/README.md)；平台本身、`live/play` 和 `PandaLiveDanmakuArgs` [E03.12 记录](../../../E-直播平台/E03-海外平台/E03.12-PandaTV/record.md)；下播后重连 B-24 在 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；握手的 User-Agent [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（本平台默认用 `dart:io` 握手）；决定 D-017；详细记录 [record.md](record.md)

## 目标

PandaTV（韩国秀场直播）直播间能看到聊天。修掉归档 v4 实现的令牌问题：令牌 30 分钟到期后 v4 先用旧令牌被拒再重取（多一个 socket、多一轮提示），被拒次数在一次连接里从不清零，第 4 次到期（约 2 小时）后整场直播没有弹幕。本实现在令牌到期前 60 s 悄悄换 socket，界面不出现重连提示。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/pandalive.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 参数 | `PandaLiveDanmakuArgs(userId, channel, token)`（`packages/live_core/lib/src/sites/pandalive/pandalive_api.dart:82`，E03.12）：进房和录制详情在 `live/play` 接受且在播时带上；`channel` 是回答的 `channel`（主播编号），`token` 是聊天令牌（约 30 分钟），`userId` 用来重新调用 `live/play`。连接再检查一次（`checked` :190）：主播 id 按平台层规则，频道 1～19 位数字，令牌 1～4096 个不含空白的可打印 ASCII（不合规的令牌丢掉、第一次握手就取新的）；主播 id 或频道不合规以 `connectionFailed` 结束，不请求、不握手（`target` :369） |
| 地址 | `PandaLiveApi.chatServer`（`pandalive_api.dart:242`：`wss://chat-ws.neolive.kr/connection/websocket`，Centrifugo 3.1.1 JSON 协议）；`live/play` 回答里的 `chatServer.url` 是空的，不用 |
| 握手 | 请求头 `origin: https://www.pandalive.co.kr` 和平台层的 Chrome 140 UA（`socketHeaders` :91；实测不带也能连）；默认 `dart:io` 握手；按平台 `pandalive` 走代理（`apps/pure_live/lib/app/platforms.dart:229`） |
| 令牌 | `live/play` 的 `token`：HS256 JWT，`exp` = 签发 + 1800 s（`tokenExpiry` :168）。第一次握手用进房带来的，一分钟内到期时先取新的；其余每次握手（重连、换 socket）前由 `_Handshake`（:483）POST `live/play`（`playRequest` :133，就是进房的那个请求：同样的地址、表单、请求头、不跟随跳转，超时同握手 10 s）取新的令牌和频道；取到没用掉的令牌留给下次。请求失败当作这次握手失败走退避；`live/play` 拒绝（`result: false`，如 `castEnd`、`needAdult`，或 `media.isLive` 为假，`PandaLiveChatRefusal` :34）以 `connectionFailed`（`live/play: <代码>`）结束 |
| 加入 | 打开后发 connect `{"params":{"token":…,"name":"js"},"id":1}`（`connect` :114）和 subscribe `{"method":1,"params":{"channel":…},"id":2}`（`subscribe` :120）（`onOpen` :385～406）；connect 回复带 `expires`、`ttl`，subscribe 的无错回复到了才就绪；加入超时 8 s（`joinTimeout` :77） |
| 心跳 | 每 25 s（`heartbeatInterval` :73）发 `{"method":7,"id":<从 3 往上数>}`（`ping` :127、`heartbeatFrame` :467），每个 socket 重新数；服务端回答每个 ping；无消息 90 s 换连接；策略 `defaultPolicy` :355 |
| 到期换 socket | connect 回复的 `ttl`（约 1798 s）前 60 s（`renewalLead` :82、`renewalDelay` :184）取新令牌、`session.reopen` 新 socket（`_renew` :453）：不报重连、不再报就绪；新 socket 8 s 内没加入按普通断线重连；取不到令牌就不换，等服务端在 `ttl` 后约 25 s 以 3005 `expired` 断开后重连 |
| 被拒 | connect/subscribe 回复带 `error`（如 109 `token expired`，`_error` :252）或服务端以 3002 `invalid token` 关闭：换令牌重连（`_refused` :439）；连续第 4 次（`maxRefusals` :86）以 `connectionFailed`（`Chat refused: …`）结束；加入成功清零 |
| 重连 | 框架默认：一个地址，间隔 2、3、4、5、6、6、6、6 s，连续 8 次失败以 `reconnectsExhausted` 结束，收到任何帧清零 |
| 帧 | 文本，一帧可有多行，每行一个 JSON（`decode` :212）：带 `id` 的是回复（1 connect、2 subscribe，`connectId` :97、`subscribeId` :100；其他是 ping 的回复），不带的是推送；频道推送 `{"result":{"channel":…,"data":{"data":<消息>,"offset":<序号>}}}`，频道必须等于当前频道；带 `result.type` 的推送（加入、离开）不处理 |
| 聊天 | `data.data.type` 是 `bj`、`chatter`、`manager`、`support`（`chatTypes` :103）→ 白色聊天（`chat` :269）：文字 `message` 去首尾空白，没有文字时取第一个有名字的表情写成 `[名字]`（`_emoticon` :293，如 `[pandaS하트다발png]`）；用户名 `nk`（没有时留空）、用户 id `id`（登录 id）；消息 id `<channel>:<offset>`；时间 `created_at`（秒，越界为空）；`idx`、`ip`、`sex`、翻译字段不读 |
| 不报的 | `SponCoin`、`ItemCoin`（礼物）、`MediaUpdate`、`Recommend`、`Info`、`FanUp`、入场、`RoomEnd`、`CastPause`、`ModifyRoom` 等；聊天流里没有人数 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | 3.x 有 PandaTV 这个平台但没有聊天：`PandaLiveSite.getDanmaku() => EmptyDanmaku()`（`lib/core/site/pandalive/pandalive_site.dart:39`），直播间只提示一次 `remote_danmaku_not_integrated`（`lib/modules/live_play/controllers/danmaku_controller.dart:146～150`） | `PandaLiveDanmakuConnection`（`pandalive.dart:333`）继承 `DanmakuSocketConnection`；协议 `PandaLiveDanmakuProtocol`（:63）；应用登记在 `apps/pure_live/lib/app/platforms.dart:229` | 有聊天（已做） |
| 公告 | `pandalive_chat_notice`“PandaTV 远端聊天尚待接入；user 字段按平台当前在线人数展示，playCnt 不作为并发人数。”（`assets/translations/zh.json:1898`） | `PandaLiveApi.chatNotice`（`pandalive_api.dart:198`）改成“人数分别是正在观看和本场累计观看。”，去掉“看不到聊天” | 已做 |
| 人数 | 列表和进房有在线人数 | `packages/live_core/lib/src/audience.dart:204～208` 是 `roomList`、有累计，本任务没改；网页另拉 `cache-api` 的 `channel_user_count`，本实现不拉 | 不变 |

## 结果

- **提交**：2a6b552b2（2026-09-29，首次实现）。之后 `pandalive.dart` 只有文档路径的注释随文档改名改过（c613b73f9、9dfbb424d），协议没有改动。
- **和归档 v4 的对照**：`fixtures/pandalive/danmaku/v4_expected.dart`（与归档的 `PandaliveProtocol` 逐字相同，只替换外部类型）写下冻结输出 `S07-live/expected.json`。地址、请求头、ping 间隔、`live/play` 的地址和表单与 v4 和录制相同；S07-live（`daisy00`，2026-09-27 录制约 152 s）客户端 8 帧与录制相同，27 个收到的 socket 帧逐帧一致，18 条聊天（含一条只有表情的 `[pandaS하트다발png]`），唯一差别是 v4 的 id 带 `pandalive:` 前缀；平台层用 `S04-member-live`、`S05-play-live`、`S06-master` 进房得到的参数和录制一致，进房发的 `live/play` 和本实现取令牌的请求逐项相同。
- **有意差异**（record.md“与归档 v4 的差异”11 条）：开始时用进房带来的令牌；每次重连先取新令牌、加入成功后被拒次数清零；到期前悄悄换 socket；`live/play` 拒绝以 `connectionFailed` 结束；`live/play` 失败按握手失败重试；`live/play` 的请求与进房相同；不报礼物；id 不加前缀；用户名只取 `nk`；文字、名字、id 只收字符串和整数，时间越界为空；参数和令牌要检查。
- **样本**：只用归档的 `fixtures/pandalive/danmaku/S07-live`，帧没有改（令牌、游客频道、观众都是合成值），新加冻结输出 `expected.json`；没有新录样本。
- **测试**：`packages/live_danmaku/test/sites/pandalive_test.dart` 现在 29 个用例（没有循环生成的，做完时同样 29 个）：协议 8、录制 3、连接 18。

## 验证

- 自动测试：`pandalive_test.dart`——协议 8 个（地址、请求头、命令、`live/play` 请求和回答、令牌到期时间、参数检查、帧和聊天的边界）、录制 3 个（与 v4 和录制一致、进房参数、用连接重放 S07）、连接 18 个（第一次握手用进房的令牌、到期前 60 s 换 socket 不提示、新 socket 加入超时、取不到令牌时等服务端断开、加入被拒换令牌和第 4 次结束、过期令牌照实测只换一次 socket、`live/play` 拒绝结束、`live/play` 失败按退避重试、关闭和换房间、本地服务器端到端）。
- 真实接口：2026-09-28（UTC 22:12～22:50）用探测程序匿名直连：错误令牌服务端立即以 3002 关闭；connect、subscribe 回复 0.3 s 内到；两个人气房间 4 分钟 1 条、30 分钟 4 条聊天；连着的连接在加入后 1821 s（`ttl` 1796 s 之后约 25 s）被 3005 `expired` 关闭，证明要提前换 socket；过期令牌再连回 109 后 3003 关闭。**本实现没有接真实服务器跑过**，用录制回放和本地服务器测试，协议和实测逐项对照过。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节没有 PandaTV，海外平台要用户开代理；E03.12 的记录里也没有 K90 结果。登记表是“完成”，但本实现既没有连过真实服务器也没有真机结果，按 D-029 还算“没验证”。

## 留下的问题

- 本实现没有在真实服务器上跑过，最要紧的“30 分钟左右不出现‘正在重连’”只用本地服务器测过：没有单独的任务，建议加进真机清单第 2 节（开代理，在一个 PandaTV 直播间连续看 35 分钟以上，看聊天不断、30 分钟左右没有重连提示），归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类的补验。
- 网页在同一个连接上用 `v1/chat/refresh_token` 刷新令牌，那个接口没有记录，本实现改用 `live/play` 加换 socket，换的零点几秒里可能漏几条；每次换 socket 多一次 `live/play`（平台可能算一次观看）：没有任务。
- 直播间的实时在线人数不拉（网页定时拉 `cache-api` 的 `/v1/chat/channel_user_count`，要聊天的频道和令牌）；列表和进房本来就有在线人数：没有任务。
- 下播、暂停（`RoomEnd`、`CastPause`）不报；下一次重连或换 socket 时 `live/play` 回 `castEnd` 才结束连接，之后由直播间的 60 s 详情刷新（C01.1，B-24）处理：没有任务。
- 礼物（`SponCoin`、`ItemCoin`）不上报，B-21 只显示已上报 `gift` 的平台：没有任务。
