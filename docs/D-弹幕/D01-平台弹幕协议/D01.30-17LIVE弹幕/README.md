# D01.30 17LIVE 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 33-4“17LIVE 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 17LIVE 没有聊天，这是新增功能
- 旧编号：M5.29、T06a.30
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`replayed` 和去重闸门的 135 s 规则是本平台 B-26 时加的）；平台本身和 `SeventeenLiveDanmakuArgs` [E03.15 记录](../../../E-直播平台/E03-海外平台/E03.15-17LIVE/record.md)；名字颜色和徽章的弹幕层 [E06.1 第二份记录](../../../E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md)，聊天行显示在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；详细记录 [record.md](record.md)

## 目标

17LIVE（日本、台湾秀场直播）直播间能看到评论和在线人数。聊天走 Ably（网站用 ably-js 2.21.0），照 ably-js 的做法匿名接入：令牌、`CONNECTED` 后挂频道、令牌错误换令牌、`AUTH` 原地换令牌、`DETACHED` 原地重新挂。后来（B-14）付费弹幕另报醒目留言、断线续接补回消息、下播结束连接、主播暂停直播报通知；（B-25）暂停期间的 0 人不上报；（B-26）补回的消息标 `replayed`；（E06.1）评论带名字颜色和徽章。

## 协议要点

| 项 | 内容 |
|---|---|
| 令牌 | 第一次握手前 `POST https://api-dsa.17app.co/api/v1/messenger/auth`（正文 `{}`），取 `provider` 1（Ably）的 `token`（同一时间段所有人拿到同一个）；之后沿用，令牌错误（40140～40149）或服务端 `AUTH`（17）时再取；`provider` 不是 1 以 `connectionFailed` 结束 |
| 地址 | `wss://17media.realtime.ably.net/?access_token=<令牌>&format=json&heartbeats=true&v=3`，失败依次换 `17-media-{a,b,c}-fallback.ably-realtime.com`；请求头 `Origin: https://17.live` 和桌面 UA；默认 `dart:io` 握手；诊断文字里的令牌换成 `<token>` |
| 加入 | 收到 `CONNECTED`（4）后发 `{"action":10,"channel":"<房间号>"}`，`ATTACHED`（11）就绪；加入超时 10 s |
| 心跳 | 服务端每 15 s 发 `{"action":0}`，客户端不发；25 s 没有任何消息换连接（`maxIdleInterval` + 10 s） |
| 续接 | 重连握手加 `resume=<connectionKey>`，重新挂频道带最后的 `channelSerial` 和标志 32；距最后一帧超过 `connectionStateTtl + maxIdleInterval`（通常 135 s）不再续接；同一次运行里 Ably 消息 id 只报一次（最多记 4096 个）；`ATTACHED` 带 `HAS_BACKLOG` 后、发布时间早于挂上时刻的消息标 `replayed` |
| 消息 | `MESSAGE`（15）的 `data` 是 gzip + base64 的 JSON：`type` 3 评论 → 聊天（网页隐藏的 `isDirty*` 不报；文字先取 `content`；颜色 `comment.textColor`；等级；名字颜色和徽章）；`barrageStyle` 且 `barrage.point` 大于 0 → 另报醒目留言（`priceText` `<point> coins`，20 s）；`type` 38 的 `liveViewerCount` → 在线人数（暂停期间的 0 不报）；`liveinfo.mute` 变化 → 通知“主播暂停了直播（画面静止、没有声音）”/“主播恢复了直播”；`type` 5 下播 → `connectionFailed`（`Broadcast ended`）；礼物、福袋、入场等不报 |
| 拒绝 | 令牌错误和服务端 `DETACHED` 连续第 4 次结束；其他连接或本房间频道的 `ERROR` 结束；不带令牌错误的 `DISCONNECTED` 沿用令牌重连 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `SeventeenLiveSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/seventeenlive/seventeenlive_site.dart:38`），提示一次“尚未接入” | `SeventeenLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/seventeenlive.dart:878`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:237`；平台 id 是 `17live`，类名不能以数字开头所以叫 `SeventeenLive` | 有评论和在线人数（已做） |
| 协议 | 无 | `SeventeenLiveDanmakuProtocol`（:234）：主机和备用主机（:242～245）、心跳 15 s、无消息 25 s、加入超时 10 s、拒绝上限 3（:268～279）、消息类型（:285～292）、续接常量（:297～307）、醒目留言 20 s（:313）、暂停通知（:319～322）、徽章字段（:774） | 与归档 v4 对照，有意差异 15 条 |
| 人数 | 详情有 `liveViewerCount`（`audience.dart` 是 `roomRealtime`） | 进房后弹幕的 `LIVE` 实时更新同一口径 | — |

## 结果

- **提交**：447e34074（2026-09-30，M5.29），82035a2aa（2026-10-01，B-14），f7f0922d3（2026-10-01，B-25、B-26），7f8ee2553（2026-10-02，名字颜色和徽章，E06.1 的 B-14 余项）。
- **和归档 v4 的对照**：`fixtures/17live/danmaku/v4_expected.dart`（与归档逐字相同）。S05-live 8 条聊天、S06-live（房间 27484154，225 s）26 条聊天、9 个在线人数在不报礼物之后逐帧一致；S07-synthetic 12 组里 7 组一致、5 组有意差异。
- **实测**（匿名直连）：令牌至少 92 分钟有效，两天前的令牌回 40142；不存在的房间号照样能挂上；三个备用主机都可用；续接实测（S08-resume）证明 `resume` 和 `channelSerial` 在 `v=3` 下可用、145 s 后频道回 90003；扫描 250 个房间：481 条飞行弹幕只有 1 条 `point` 大于 0，95 次下播，`mute` 为真时观众照常发言、流是静止画面没有声音（所以写成“暂停”而不是“禁言”）。本实现没有直接连真实服务器，用本地服务器和按录制时刻重放测试。
- **样本**：`fixtures/17live/danmaku/` 的 S05-live、S06-live、S07-synthetic、S08-resume、S09-resume-bad-key、S10-events。
- **测试**：`packages/live_danmaku/test/sites/seventeenlive_test.dart` 做完时 54 个（另做过 19 种变异），B-14 后 77 个（29 种变异），B-25、B-26 后 84 个，名字颜色和徽章又加了用例。

## 验证

- 自动测试：`seventeenlive_test.dart`（S08 按录制时刻重放 5 个 socket 的续接；本地服务器端到端）。
- 真实接口：见上面的实测。没实测到的：服务端发 `AUTH`、令牌到期的通知方式、积压里没有时间的消息。
- 真机：没有；海外平台要代理。

## 留下的问题

- 名字颜色和徽章已经在 `LiveMessage.nameColor`、`badges` 里，聊天行还没显示（E06.2 第 2 阶段，暂停中）。
- 下播后主播重新开播（实测 `Close by low memory recycle` 后约 5 分钟重开）：这里第一次下播就结束，要直播间刷新发现重新开播后再连（C01.1 的 B-24）。
- 只读：不登录，不能发言，不订阅登录用户的个人频道。
- 积压判断拿本机时间和 Ably 时间比，本机时钟偏差会让边界附近的几条标记不准（只影响去重闸门的年龄上限）。
