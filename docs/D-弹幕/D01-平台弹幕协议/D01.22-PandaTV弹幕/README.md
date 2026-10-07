# D01.22 PandaTV 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 25-2“PandaTV 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 PandaTV 聊天，这是新增功能
- 旧编号：M5.21、T06a.22
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`live/play` 和 `PandaLiveDanmakuArgs` [E03.12 记录](../../../E-直播平台/E03-海外平台/E03.12-PandaTV/record.md)；详细记录 [record.md](record.md)

## 目标

PandaTV（韩国秀场直播）直播间能看到聊天；修掉归档 v4 实现的令牌问题：令牌 30 分钟到期后 v4 先用旧令牌被拒再重取，而且被拒次数从不清零，约 2 小时后整场直播没有弹幕。本实现在令牌到期前 60 s 悄悄换 socket，界面不出现重连提示。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `PandaLiveApi.chatServer`（`wss://chat-ws.neolive.kr/connection/websocket`，Centrifugo 3.1.1 JSON 协议）；请求头 `Origin: https://www.pandalive.co.kr` 和 Chrome 140 UA；默认 `dart:io` 握手；按平台 `pandalive` 走代理 |
| 令牌 | `live/play` 回答的 `token`（HS256 JWT，`exp` = 签发 + 1800 s）和 `channel`（主播编号）；第一次握手用进房带来的，其余每次握手前 POST `live/play` 取新的（就是进房的那个请求） |
| 加入 | 打开后发 connect `{"params":{"token":…,"name":"js"},"id":1}` 和 subscribe `{"method":1,"params":{"channel":…},"id":2}`；subscribe 的回复到了才就绪；加入超时 8 s |
| 心跳 | 每 25 s 发 `{"method":7,"id":<从 3 往上数>}`；无消息 90 s |
| 到期换 socket | connect 回复的 `ttl`（约 1798 s）前 60 s 取新令牌、`reopen` 新 socket，不报重连、不再报就绪；服务端在 `ttl` 后约 25 s 以 3005 `expired` 断开 |
| 被拒 | connect/subscribe 回复带 `error`（如 109 `token expired`）或服务端 3002 `invalid token`：换令牌重连，连续第 4 次以 `connectionFailed`（`Chat refused: …`）结束；`live/play` 拒绝（`castEnd`、`needAdult` 或不在播）：`connectionFailed`（`live/play: <代码>`） |
| 消息 | 频道推送 `data.data.type` 为 `bj`、`chatter`、`manager`、`support` 的是白色聊天：`message`（没有文字时显示第一个表情名 `[名字]`）、`nk` 昵称、`id` 登录 id、id `<channel>:<offset>`、`created_at`；礼物、推荐、入场、房间状态不报；聊天流里没有人数 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `PandaLiveSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/pandalive/pandalive_site.dart:39`），提示一次“尚未接入” | `PandaLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/pandalive.dart:333`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:229` | 有聊天（已做） |
| 协议 | 无 | `PandaLiveDanmakuProtocol`（:63）：心跳 25 s、加入超时 8 s、提前 60 s 换令牌（:73～82）、`maxRefusals = 3`（:86）、聊天类型（:103）；`PandaLiveChatRefusal`（:34） | 与归档 v4 对照，有意差异 11 条 |
| 人数 | 列表和进房有在线人数（`audience.dart` 是 `roomList`） | 不变（网页另拉 `cache-api` 的 `channel_user_count`，本实现不拉） | — |
| 公告 | 说看不到聊天 | `PandaLiveApi.chatNotice` 去掉“看不到聊天”，只说明人数 | — |

## 结果

- **提交**：2a6b552b2（2026-09-29，M5.21）。之后没有改动。
- **和归档 v4 的对照**：`fixtures/pandalive/danmaku/v4_expected.dart`（与归档逐字相同）。S07-live（`daisy00`，152 s）27 个收到的帧逐帧一致，18 条聊天（含一条只有表情的 `[pandaS하트다발png]`），客户端发的 8 帧与录制相同；进房发的 `live/play` 和本实现取令牌的请求逐项相同。
- **实测**（2026-09-28 匿名直连）：错误令牌服务端立即 3002 关闭；connect、subscribe 回复 0.3 s 内到；连着的连接在加入后 1821 s 被 3005 `expired` 关闭（证明要提前换 socket）；过期令牌再连回 109 后 3003 关闭。本实现没有接真实服务器跑，用本地服务器测试。
- **样本**：只用归档的 `fixtures/pandalive/danmaku/S07-live`，新加冻结输出 `expected.json`（令牌、游客频道、观众都是合成值）。
- **测试**：`packages/live_danmaku/test/sites/pandalive_test.dart` 29 个（协议 8、录制 3、连接 18，含到期前换 socket 的各种情形和本地服务器端到端）。

## 验证

- 自动测试：`pandalive_test.dart`。
- 真实接口：只有探测程序的实测，本实现没有直接连真实服务器。
- 真机：没有；海外平台要代理。真机上要看：在一个直播间连续看 35 分钟以上，30 分钟左右不出现“正在重连”。

## 留下的问题

- 网页在同一个连接上用 `v1/chat/refresh_token` 刷新令牌，接口没有记录，本实现改用 `live/play` 加换 socket，换的零点几秒里可能漏几条。
- 直播间的实时在线人数不拉（要 `cache-api` 的 `channel_user_count`）。
- 下播、暂停（`RoomEnd`、`CastPause`）不报；下一次重连时 `live/play` 的 `castEnd` 会结束连接。
- 礼物（`SponCoin`、`ItemCoin`）不显示。
