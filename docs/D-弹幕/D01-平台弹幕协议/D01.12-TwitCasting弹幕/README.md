# D01.12 TwitCasting 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 12-3“评论（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 TwitCasting 评论，这是新增功能
- 旧编号：M5.11、T06a.12
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数 [E03.4 记录](../../../E-直播平台/E03-海外平台/E03.4-TwitCasting/record.md)；详细记录 [record.md](record.md)

## 目标

TwitCasting（日本个人直播）直播间能看到评论；修掉归档 v4 实现开播一小时后断线就再也连不上的问题（签名地址约一小时过期，v4 重连沿用旧地址）。

## 协议要点

| 项 | 内容 |
|---|---|
| 取地址 | 每次握手前 `POST https://twitcasting.tv/eventpubsuburl.php`，表单 `movie_id=<直播号>`，请求头用适配器的 `TwitcastingApi.headers`（UA `Mozilla/5.0`）；回答 `{"url":"wss://<节点>.twitcasting.tv/event.pubsub/v1/streams/<直播号>/events?token=<签名>&n=<随机>"}`，只接受 `wss` 且主机是 `twitcasting.tv` 或子域名 |
| 签名 | `token` 中间的数字是签发时刻 + 3601 s，到时握手回 HTTP 400（实测 3540 s 能连、3640 s 不能）；所以名义地址交给 `LiveSocket`，本平台的握手函数每次先 POST 拿新地址 |
| socket | 握手请求头 `Origin: https://twitcasting.tv`、UA；打开即就绪，客户端什么也不发；按平台 `twitcasting` 走代理 |
| 保活 | 服务端 10 s 没有事件就发一个 `[]`；客户端不发心跳；无消息 30 s（每 10 s 检查一次）换连接，是网页的阈值 |
| 事件 | 每帧一个 JSON 数组；`comment` → 白色聊天（`message` 文字、`author.name` 为空时用 `screenName`、`author.id`、消息 id `id`、时间 `createdAt`）；`gift`（要地址带 `gift=1` 才推送）、置顶、投票、突袭等不报 |
| 失败 | 取地址失败当作一次握手失败，走框架的退避和 8 次上限；直播号不大于 0 以 `connectionFailed`（`No broadcast`）结束；诊断文字里 `token`、`n` 换成 `…` |
| 人数 | 评论流里没有，人数仍来自列表的 `current_viewer_count` |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 评论 | `TwitcastingSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/twitcasting/twitcasting_site.dart:22`），提示一次“尚未接入” | `TwitcastingDanmakuConnection`（`packages/live_danmaku/lib/src/sites/twitcasting.dart:174`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:218` | 有评论（已做） |
| 协议 | 无 | `TwitcastingDanmakuProtocol`（:24）：取地址 `request`（:45）、`socketUrl`（:58）、`redact`（:92）、`decode`（:98）；每次握手前取地址的 `_Resolver`（:234） | 与归档 v4 解码一致 |
| 时序 | 无 | `defaultPolicy`（:191～193）：检测节拍 `keepAliveInterval` 10 s（:30），`silenceTimeout` 30 s（:34） | 比 v4 的 90 s 更快发现断线 |

## 结果

- **提交**：a4cb9a72e（2026-09-29，M5.11）。之后没有改动。
- **和归档 v4 的对照**：`fixtures/twitcasting/danmaku/v4_expected.dart` 把 v4 的地址解析和解码搬成独立程序。S08-live（频道 c:abzou_sub，13 个推送帧）12 条聊天逐帧一致（只差 v4 的 `twitcasting:` 前缀），取地址的回答与 `meta.json` 记下的握手地址相同。
- **和归档 v4 的差异**（record.md 11 条）：每次握手前重取签名地址；开始取地址失败按握手失败重试；无消息 30 s；不要礼物；id 不加前缀；名字为空用 `screenName`；文字必须是字符串；主机校验更严；诊断不带签名。
- **和网页播放器的差异**：不补拉断线期间的评论（网页用 `eventpolling.php`，要页面令牌），不在 3 次失败后改用 HTTP 轮询，不加 `gift=1`。
- **实测**（2026-09-29 匿名直连）：本实现 1449 ms 就绪（POST 加握手），120 s 收到 52 条聊天；空房间 130 s 收到 13 个 `[]` 保活。
- **样本**：没有新录，用归档的 `fixtures/twitcasting/S07-pubsub` 和 `fixtures/twitcasting/danmaku/S08-live`，新加冻结输出 `expected.json`。
- **测试**：`packages/live_danmaku/test/sites/twitcasting_test.dart` 24 个（协议 8、录制 3、连接 13，含本地 HTTP + WebSocket 服务器端到端）。

## 验证

- 自动测试：`twitcasting_test.dart`。
- 真实接口：见上面的实测。已经连着的 socket 到一小时会不会被断开没有验证（两种情况本实现都能处理）。
- 真机：没有；海外平台要代理。

## 留下的问题

- 主播重新开播后直播号会变，旧连接不会自己结束（只剩保活）；要直播间的定时刷新拿到新 `movieId` 后重新连接。附录 B-24 已由 C01.1 做了“开播后重连弹幕”，但直播间刷新时只在弹幕连接已结束（`DanmakuStatus.closed`）时重连（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`），TwitCasting 的旧连接不会结束，换场次没有覆盖；没有登记任务。
- 断线期间的评论不补拉。
- 口令直播能否匿名取地址没有验证（口令直播现在本来就不能播放）。
- 礼物（含带留言的付费礼物 `isPaidGift`）不显示：要地址加 `gift=1` 并解码 `gift` 事件，B-21 没覆盖本平台。
