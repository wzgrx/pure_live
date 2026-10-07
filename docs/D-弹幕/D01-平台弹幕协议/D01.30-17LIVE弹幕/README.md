# D01.30 17LIVE 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 33-4“17LIVE 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 17LIVE 没有聊天（`EmptyDanmaku`），这是新增功能，规格来自归档 v4 的实现和录制、网站用的 ably-js 2.21.0；后来的附录 B-14（付费弹幕、续接、下播、暂停通知）、B-25（暂停期间的 0 人）、B-26（补回的消息标 `replayed`）和 E06.1 的名字颜色、徽章也在这里
- 旧编号：M5.29、T06a.30
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`LiveMessage.replayed` 和去重闸门对补回消息放宽到 135 s 是本平台 B-26 时加的）；平台本身和 `SeventeenLiveDanmakuArgs` [E03.15 记录](../../../E-直播平台/E03-海外平台/E03.15-17LIVE/record.md)；名字颜色和徽章的弹幕层 [E06.1 第二份记录](../../../E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md)，聊天行显示在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 2 阶段“名字颜色和徽章”；下播后重新开播时重连 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)（B-24）；详细记录 [record.md](record.md)

## 目标

17LIVE（日本、台湾秀场直播）直播间能看到评论和在线人数。聊天走 Ably，照 ably-js 的做法匿名接入：令牌、`CONNECTED` 后挂频道、令牌错误换令牌、`AUTH` 原地换令牌、`DETACHED` 原地重新挂。后来（B-14）付费弹幕另报醒目留言、断线续接补回消息、下播结束连接、主播暂停直播报通知；（B-25）暂停期间的 0 人不上报；（B-26）补回的消息标 `replayed`；（E06.1）评论带名字颜色和徽章。

## 协议要点

| 项 | 内容 |
|---|---|
| 令牌 | 第一次握手前 `POST https://api-dsa.17app.co/api/v1/messenger/auth`（正文 `{}`，不跟随跳转），取 `provider` 1（Ably）的 `token`（同一时间段所有人拿到同一个，至少 92 分钟有效）；之后沿用，令牌错误（40140～40149）或服务端 `AUTH`（17）时再取；`provider` 不是 1 以 `connectionFailed`（`messenger/auth: provider <n>`）结束；令牌请求失败算握手失败 |
| 地址 | `wss://17media.realtime.ably.net/?access_token=<令牌>&format=json&heartbeats=true&v=3`，失败依次换 `17-media-{a,b,c}-fallback.ably-realtime.com`；请求头 `Origin: https://17.live` 和桌面 UA；默认 `dart:io` 握手；按平台 `17live` 走代理；诊断文字里的令牌换成 `<token>` |
| 加入 | 收到 `CONNECTED`（4）后发 `{"action":10,"channel":"<房间号>"}`（`ATTACH`），`ATTACHED`（11）就绪；加入超时 10 s |
| 心跳 | 服务端每 15 s 发 `{"action":0}`，客户端不发；25 s 没有任何消息换连接（`maxIdleInterval` + 10 s） |
| 续接 | 重连握手加 `resume=<connectionKey>`，重新挂频道带最后的 `channelSerial` 和标志 32；距最后一帧超过 `connectionStateTtl + maxIdleInterval`（通常 120 + 15 = 135 s）不再续接；同一次运行里 Ably 消息 id 只报一次（最多记 4096 个）；`ATTACHED` 带 `HAS_BACKLOG`（2）后、发布时间早于挂上时刻的消息标 `replayed`，第一条不早于它的消息结束积压 |
| 消息 | `MESSAGE`（15）的 `data` 是 gzip + base64 的 JSON。`type` 3 评论 → 聊天：网页隐藏的（`isDirty`、`isDirtyWord`、`isDirtyUser`）不报；文字先取 `content`，没有时 `comment.text`；名字 `displayUser.displayName`（没有时 `openID`）、用户 id `userID`、等级、颜色 `comment.textColor`（`#AARRGGBB` 或 `#RRGGBB`）、时间 `sendTime`；名字颜色 `name.textColor` → `nameColor`，名字旁的徽章（`prefixBadges`、`prefixBadge` 和 5 个位置，最多 16 个前缀徽章，只收平台主机的图）→ `badges`。`barrageStyle` 且 `barrage.point` 大于 0 → 另报醒目留言（`priceText` `<point> coins`，20 s，背景色是评论的 `backgroundColor`）。`type` 38 的 `liveinfo.liveViewerCount` → 在线人数（暂停期间和结束暂停那一条的 0 不报，B-25）；`liveinfo.mute` 变化 → 系统通知“主播暂停了直播（画面静止、没有声音）”/“主播恢复了直播”；`type` 5 下播 → `connectionFailed`（`Broadcast ended`）；礼物、福袋、入场等不报 |
| 拒绝 | 令牌错误和服务端 `DETACHED` 连续第 4 次结束，加入一次清零；`DETACHED` 先原地重新挂，两次就换连接；其他连接错误或本房间频道的 `ERROR` 以 `connectionFailed` 结束，别的频道的错误不管；不带令牌错误的 `DISCONNECTED` 沿用令牌重连；四个主机轮换用尽后 `reconnectsExhausted`，详情不带令牌 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `SeventeenLiveSite.getDanmaku() => EmptyDanmaku()`（`core/site/seventeenlive/seventeenlive_site.dart:38`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`）；3.x 的房间公告只有年龄提示 `seventeen_age_notice`（`seventeenlive_site.dart:101`），没有聊天公告 | `SeventeenLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/seventeenlive.dart:878`）：时序（:900）、下播说明（:907）、`target`（:918）、`onOpen`（:934）、`onData`（:942）、`_attach`（:1023）、`onJoinTimeout`（:1035）、`_detached`（:1045）、`_tokenRefused`（:1071）、`_reauthorize`（:1083）；握手 `_Handshake`（:1107，`renew` :1149）；一次运行的 `_Chat`（:1175：记 4096 个 id :1181、续接键 `resumeKey` :1232、`firstSight` :1245）；应用登记在 `apps/pure_live/lib/app/platforms.dart:237`；平台 id 是 `17live`，类名不能以数字开头所以叫 `SeventeenLive` | 有评论和在线人数（已做） |
| 协议 | 无 | `SeventeenLiveDanmakuProtocol`（:234）：`provider` 1（:239）、主机和备用主机（:242～245）、握手请求头（:260）、心跳 15 s、无消息 25 s、加入超时 10 s、拒绝上限 3（:268～279）、消息类型（:285～292）、续接常量（:297～307）、醒目留言 20 s（:313）、暂停通知（:319～322）、`grant`（:358）、`withToken`（:372）、`attach`（:379）、`reauthorize`（:388）、`decode`（:420）、`entry`（:561）、`superChat`（:617）、`payload`（:675）、`message`（:704）、`color`（:752）、`nameColor`（:763）、徽章字段（:774）、`badges`（:788） | 与归档 v4 对照，有意差异 15 条（record.md） |
| 人数 | 详情有 `liveViewerCount` | `audience.dart:163` 仍是 `roomRealtime`（有累计）；进房后弹幕的 `LIVE`（38）实时更新同一口径 | — |
| 参数 | 无 | `SeventeenLiveDanmakuArgs`（`packages/live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart:46`），E03.15 给出 | — |

## 结果

- **提交**：447e34074（2026-09-30，本任务的代码），82035a2aa（2026-10-01，B-14），f7f0922d3（2026-10-01，B-25、B-26），7f8ee2553（2026-10-02，名字颜色和徽章，E06.1 的 B-14 余项）。另外 docs v1 改编号时动过注释（c613b73f9、9dfbb424d）。
- **和归档 v4 的对照**：`fixtures/17live/danmaku/v4_expected.dart`（与归档逐字相同）。S05-live 8 条聊天、S06-live（房间 27484154，225 s）26 条聊天、9 个在线人数在不报礼物之后逐帧一致；S07-synthetic 12 组里 7 组一致、5 组有意差异。
- **实测**（匿名直连）：令牌至少 92 分钟有效，两天前的令牌回 40142；不存在的房间号照样能挂上；三个备用主机都可用；续接实测（S08-resume）证明 `resume` 和 `channelSerial` 在 `v=3` 下可用、145 s 后频道回 90003；扫描 250 个房间：481 条飞行弹幕只有 1 条 `point` 大于 0，95 次下播，`mute` 为真时观众照常发言、流是静止画面没有声音（所以写成“暂停”而不是“禁言”）。本实现没有直接连真实服务器，用本地服务器和按录制时刻重放测试。
- **样本**：`fixtures/17live/danmaku/` 的 S05-live、S06-live、S07-synthetic、S08-resume、S09-resume-bad-key、S10-events。
- **测试**：`packages/live_danmaku/test/sites/seventeenlive_test.dart` 现在运行时 86 个：文件里 73 处 `test(`，其中第 764、931 行各在 S05、S06 两份录制上跑一次，第 842 行在 S07 的 12 组合成帧上各跑一次。历次：做完时 54 个（另做过 19 种变异），B-14 后 77 个（29 种变异），B-25、B-26 后 84 个，名字颜色和徽章加 2 个。

## 验证

- 自动测试：`seventeenlive_test.dart` 覆盖令牌请求和回答、四个地址、握手请求头、`ATTACH`、`AUTH`、帧的信号和错误、载荷解码、评论各字段（隐藏标记、文字取法、颜色、时间）、付费弹幕、在线人数、名字颜色和徽章；录制和合成帧对照 v4；S08 按录制时刻重放 5 个 socket 的续接（补发的 9 条上报消息标 `replayed`、闸门放过全部 8 条聊天）；S10 的暂停和下播；连接的令牌复用和更换、主机轮换、`DETACHED`、拒绝上限、加入超时、关闭时取消、本地服务器端到端。
- 真实接口：2026-09-28～30 跑过（见上面的实测）。没实测到的：服务端发 `AUTH`、令牌到期的通知方式、积压里没有时间的消息。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有 17LIVE。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有 17LIVE 弹幕的条目；海外平台要代理，清单“准备”一行写明只在用户开着代理时做；E06.1 第二份记录“要在 K90 上看的”一节列了名字颜色和徽章，要等 E06.2 接到界面。真机上要看：评论和颜色、在线人数随弹幕变化；断网 30 s 再恢复后补回的评论出现；主播暂停时出现暂停通知、人数不变成 0。

## 留下的问题

- 名字颜色和徽章已经在 `LiveMessage.nameColor`、`badges` 里，聊天行还没显示：E06.2 第 2 阶段“名字颜色和徽章”（暂停中；颜色要过 D04.1 的对比度处理，见 E06.2 的 brief）。
- 下播后主播重新开播（实测 `Close by low memory recycle` 后约 5 分钟重开）：这里第一次下播就结束连接；直播间每 60 秒刷新详情，弹幕连接结束后重连，已由 C01.1 的 B-24 做完（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`；17LIVE 的参数只有房间号，刷新后照旧可用），没有真机结果。
- 只读：不登录，不能发言，不订阅登录用户的个人频道（`streams:<房间>:users:<用户>`）：没有任务，本应用没有 17LIVE 账号。
- 积压判断拿本机时间和 Ably 时间比，本机时钟偏差会让边界附近的几条标记不准（只影响去重闸门的年龄上限）：没有任务，去重闸门本身也是同一个前提。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
