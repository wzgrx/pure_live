# D01.31 Kick 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：恢复：v3.2.11 的代码里没有 Kick 平台（`lib/core/site/` 下没有 kick），但 v3.2.11 的文档 `docs/KICK_PUBLIC_CHAT_AUDIT_2026_09_23.md` 记录过一版走 Pusher 的只读聊天；4.x 恢复 Kick 平台（[E03.16](../../../E-直播平台/E03-海外平台/E03.16-Kick/record.md)，仅 Android，附录 X-1）时一起恢复聊天
- 旧编号：M5.34、T06a.31
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和 `KickDanmakuArgs` [E03.16 记录](../../../E-直播平台/E03-海外平台/E03.16-Kick/record.md)；验证归 S02.4（Twitch 和 Kick）；详细记录 [record.md](record.md)

## 目标

Kick（海外直播）直播间能看到公开聊天、撤回、订阅和突袭通知，主播下播时有通知。协议照 pure_live_TV 的 `kick_danmaku.dart`（e1cca224）和 v3 文档的审计，以本次录到的帧为准；审核、通知类事件按公开客户端库（kick-wss 等）的形状实现。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://ws-us2.pusher.com/app/32cbd69e4b950bf97679?protocol=7&client=js&version=8.4.0&flash=false`（Kick 网页的 Pusher 应用，不在 Kick 的 Cloudflare 后面，`dart:io` 正常）；请求头 `origin: https://kick.com`、桌面 Chrome 140 UA；按平台 `kick` 走代理 |
| 会话和订阅 | 服务端先发 `pusher:connection_established`（`activity_timeout: 120`），之后订阅 `chatrooms.<chatroomId>.v2`（聊天、审核、通知）和 `channel.<channelId>`（直播本身的事件，比上游多）；聊天频道的 `pusher_internal:subscription_succeeded` 才就绪、才上报消息；加入超时 10 s |
| 心跳 | 客户端每 30 s 发 `pusher:ping`；服务端的 `pusher:ping` 回 `pusher:pong`；无消息 90 s 换连接 |
| 错误 | `pusher:error`、`pusher_internal:subscription_error` → 带 `protocolError` 提示重连 |
| 消息 | `data` 是 JSON 字符串，事件名取 `App\Events\…` 最后一段：`ChatMessageEvent` → 聊天（`[emote:<id>:<名字>]` 显示为名字，`identity.color` 颜色，`badges_v2` 的等级）；`MessageDeletedEvent`、`UserBannedEvent`、`ChatroomClearEvent` → 撤回；`SubscriptionEvent`、`GiftedSubscriptionsEvent`、`StreamHostEvent`、`PinnedMessageCreatedEvent` → 通知；`KicksGifted` 有留言是醒目留言（`priceText` “500 Kicks”），没留言是礼物；`channel.<id>` 的 `StopStreamBroadcast` → “直播已结束”通知 |
| 人数 | Pusher 不推观看人数，人数仍来自详情 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 平台和聊天 | v3.2.11 代码里没有 Kick；文档记录的旧实现在连接时再请求一次 `api/v2/channels/<slug>` 取聊天房间 id，只订 `chatrooms.<id>.v2` | `KickDanmakuConnection`（`packages/live_danmaku/lib/src/sites/kick.dart:361`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:225`（各平台都登记，Windows 没有 Kick 的平台适配器，进不了房间） | 有聊天（已做） |
| 协议 | 无 | `KickDanmakuProtocol`（:21）：地址（:24）、请求头（:28）、心跳 30 s（:32）、加入超时 10 s（:36）；`KickFrame`（:327） | 与上游读法对照，多了撤回、通知、Kicks、下播、等级 |
| 聊天房间 id | 连接时再请求 | 进房详情给出 `KickDanmakuArgs(chatroomId, channelId, slug)`，不多发请求 | — |

## 结果

- **提交**：96e032864（2026-10-01，M5.34 的代码）；登记表记的 6c68f0010 是同日的文档提交（M4.34 Kick、M5.34 Kick chat 的记录）。
- **期望值**：`fixtures/kick/danmaku/expected.py` 按上游 `parseFrame` 独立读一遍每个收到的帧（加上等级和下播）。S07-chat（lonche，聊天房间 3852600）前 160 帧：会话建立、三个订阅确认、141 条聊天（含回复）；S08-stream-end（xqc，668）16 条聊天和 `StopStreamBroadcast`。
- **测试**：`packages/live_danmaku/test/sites/kick_test.dart` 18 个（两段录制逐帧对照、聊天各字段、撤回三种、通知四种、Kicks 两种、Pusher 错误、连接时序、加入超时、心跳、参数不对）。

## 验证

- 自动测试：`kick_test.dart`。
- 真实接口：录制时匿名只读连过（S07、S08）；审核、订阅、突袭、置顶、Kicks 都没录到，用合成帧。
- 真机：没有。Kick 要代理，[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 记为“没测”，归 S02.4。真机上要看：聊天和颜色、Kicks 醒目留言的形状、长时间连接。

## 留下的问题

- `KicksGifted` 的形状来自公开客户端库，没有录到，要真机核对。
- 投票（`PollUpdateEvent`）没有界面；置顶现在是一行通知，不是置顶条。
- 表情显示成名字，图片地址 `files.kick.com/emotes/<id>/fullsize` 没接（归 A 组的表情）。
