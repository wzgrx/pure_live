# D01.31 Kick 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：恢复（已批准升级 X-1“恢复 Kick”，[specs/UPGRADES.md](../../../specs/UPGRADES.md)）：v3.2.11 的代码里没有 Kick 平台，但 v3.2.11 的文档 `docs/KICK_PUBLIC_CHAT_AUDIT_2026_09_23.md` 记录过 3.2.0 时一版走 Pusher 的只读聊天；4.x 恢复 Kick 平台（[E03.16](../../../E-直播平台/E03-海外平台/E03.16-Kick/record.md)，仅 Android）时一起恢复聊天。协议照 pure_live_TV 的 `kick_danmaku.dart`（e1cca224）和那份审计，以本次录到的帧为准
- 旧编号：M5.34、T06a.31
- 相关：决定 D-001、D-004（现在只做 Android；Windows 上没有 Kick）、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和 `KickDanmakuArgs` [E03.16 记录](../../../E-直播平台/E03-海外平台/E03.16-Kick/record.md)；礼物在聊天列表的显示 [C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)（B-21）；表情图片的显示 [D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)；真机验证归 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)（Twitch 和 Kick，要代理）；Windows 恢复归 [X01.2](../../../X-多端客户端/X01-Windows/X01.2-Windows专属功能/README.md)（X-1 的余项）；详细记录 [record.md](record.md)

## 目标

Kick（海外直播）直播间能看到公开聊天、撤回、订阅和突袭通知、Kicks 醒目留言，主播下播时有通知。审核、通知类事件没有录到，按公开客户端库（kick-wss 等）的形状实现，用合成帧测试。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://ws-us2.pusher.com/app/32cbd69e4b950bf97679?protocol=7&client=js&version=8.4.0&flash=false`（Kick 网页的 Pusher 应用，不在 Kick 的 Cloudflare 后面，`dart:io` 正常）；请求头 `origin: https://kick.com`、桌面 Chrome 140 UA；按平台 `kick` 走代理 |
| 会话和订阅 | 服务端先发 `pusher:connection_established`（`socket_id`、`activity_timeout: 120`），之后发 `{"event":"pusher:subscribe","data":{"auth":"","channel":…}}` 订阅 `chatrooms.<chatroomId>.v2`（聊天、审核、通知）和 `channel.<channelId>`（直播本身的事件，比上游多）；聊天频道的 `pusher_internal:subscription_succeeded` 才就绪、才上报消息；加入超时 10 s；每次重连都重新等会话建立、重新订阅 |
| 心跳 | 客户端每 30 s 发 `pusher:ping`；服务端的 `pusher:ping` 回 `pusher:pong`；无消息 90 s 换连接（框架默认） |
| 错误 | `pusher:error`、`pusher_internal:subscription_error` → 带 `protocolError` 提示重连；参数不对（没有聊天房间 id）：`connectionFailed`（`No chatroom to subscribe to`） |
| 消息 | `data` 是 JSON 字符串，事件名取 `App\Events\…` 最后一段。`ChatMessageEvent`（旧形状 `ChatMessageSentEvent` 也认；`type` 为 `message`、`reply` 或空）→ 聊天：`[emote:<id>:<名字>]` 显示为名字，`sender.username`、`sender.id`，颜色 `identity.color`，等级是 `badges_v2` 的 `level`，消息 id，时间 `created_at`；别的聊天房间、空文字、其他类型不报。`MessageDeletedEvent`（按消息 id）、`UserBannedEvent`（按用户，临时和永久都撤）、`ChatroomClearEvent`（全部）→ 撤回；`SubscriptionEvent`、`GiftedSubscriptionsEvent`、`StreamHostEvent`（突袭）、`PinnedMessageCreatedEvent` → 通知；`KicksGifted` 有留言是醒目留言（`priceText` “500 Kicks”，显示 `pinned_time` 秒，没有就按金额 1、2、5、30 分钟），没留言是礼物行；`channel.<id>` 的 `StopStreamBroadcast` → 系统通知“直播已结束”；`PollUpdateEvent`、`PinnedMessageDeletedEvent` 等不报 |
| 人数 | Pusher 不推观看人数，人数仍来自详情（`audience.dart:154`，`roomList`） |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/...`） | 现在 | 要做到 |
|---|---|---|---|
| 平台和聊天 | v3.2.11 没有 Kick 的适配器：`kick` 在下线平台表里（`lib/core/sites.dart:131`，`isRetired` :134；关注的平台版本表 `lib/common/services/settings/favorite_room_controller.dart:73` 写明 3.2.11 下线），分享链接只回答“已下线”。审计文档 `docs/KICK_PUBLIC_CHAT_AUDIT_2026_09_23.md` 记录的 3.2.0 实现在连接时再请求一次 `api/v2/channels/<slug>` 取聊天房间 id，只订 `chatrooms.<id>.v2` | `KickDanmakuConnection`（`packages/live_danmaku/lib/src/sites/kick.dart:361`）：时序 `socketPolicy`（:368）、`target`（:377）检查参数、`onData`（:397）建立后订阅两个频道、回 pong、错误重连、确认后才上报、心跳帧（:418）；弹幕登记在 `apps/pure_live/lib/app/platforms.dart:225`（各平台都登记）；平台本身只在有原生 HTTP 通道时登记（`platforms.dart:172`，Windows 没有，进不了房间） | 有聊天（已做） |
| 协议 | 无 | `KickDanmakuProtocol`（:21）：地址（:23～25）、请求头（:28）、心跳 30 s（:32）、加入超时 10 s（:36）、ping 和 pong（:39、:42）、两个频道名（:45、:48）、订阅帧（:51）、`read`（:65）、`chatEvent`（:98）、`broadcastEvent`（:114）、`message`（:128）、`kicks`（:160）、醒目留言时长（:208）；`KickFrame`（:327） | 与上游读法对照，多了撤回、通知、Kicks、下播、等级 |
| 聊天房间 id | 连接时再请求 | 进房详情给出 `KickDanmakuArgs(chatroomId, channelId, slug)`（`packages/live_core/lib/src/sites/kick/kick_api.dart:22`，进房时才带，`kick_site.dart:205`），不多发请求 | — |

## 结果

- **提交**：96e032864（2026-10-01，本任务的代码）；登记表原来记的 6c68f0010 是同日的文档提交（`docs: M4.34 Kick, M5.34 Kick chat, the Twitch WebView transport, X-1 status`），2026-10-07 已改成代码提交。之后 `kick.dart` 没有改动。
- **期望值**：`fixtures/kick/danmaku/expected.py` 按上游 `parseFrame` 独立读一遍每个收到的帧（加上等级和下播），写进 `expected.json`。S07-chat（lonche，聊天房间 3852600，频道 3862536）75 s 录制的前 160 帧：会话建立、三个订阅确认、141 条聊天（含回复）、投票更新、置顶删除、pong；S08-stream-end（xqc，聊天房间和频道都是 668）16 条聊天和 `StopStreamBroadcast`。
- **样本**：`fixtures/kick/danmaku/` 的 S07-chat、S08-stream-end（发送者和被回复者的 id、用户名、slug 换成同形同长度的合成值，`socket_id` 换掉；记在 `meta.json` 的 `scrubbed`）。
- **测试**：`packages/live_danmaku/test/sites/kick_test.dart` 现在运行时 18 个（和做完时一样；文件里 17 处 `test(`，第 74 行的“逐帧对照”在 S07、S08 两段录制上各跑一次）：录制逐帧对照、下播通知；聊天各字段、回复和其他类型、别的房间、旧形状、坏帧；撤回三种、订阅和赠送和突袭、置顶和投票、Kicks 两种、Pusher 错误；连接时序（会话后才订阅、确认后才就绪和上报、回 pong、代理和握手头）、错误后重连再订阅、加入超时、心跳、参数不对时结束、拒绝别的参数类型。

## 验证

- 自动测试：`kick_test.dart`（见上）。
- 真实接口：录制时匿名只读连过（2026-10-01，S07、S08）；审核、订阅、突袭、置顶、Kicks 都没录到，用合成帧。本实现没有直接连真实服务器。
- 真机：没有。Kick 要代理，[S02.3](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 记为“没测”，归 S02.4。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 5 节第 7 条（有代理时进 Twitch、Kick 直播间）只写“能播”，第 2 节第 1 条没有 Kick，清单里没有 Kick 聊天的条目。真机上要看：聊天和颜色、撤回、Kicks 醒目留言的形状、下播通知、长时间连接。

## 留下的问题

- `KicksGifted` 的形状来自公开客户端库，没有录到，要真机核对：S02.4 第 4 阶段（5.7 Twitch 和 Kick）时顺带看；那一条现在只写“能播”，上机时要把聊天加进去。
- 投票（`PollUpdateEvent`）没有界面；置顶现在是一行通知，不是置顶条：没有任务。
- 表情显示成名字，图片地址 `files.kick.com/emotes/<id>/fullsize` 没接：没有任务。`LiveMessage.emotes`（`packages/live_core/lib/src/live_message.dart:352`）现在只有哔哩哔哩、快手、CHZZK、YouTube 填，显示 D03.2 已做；要做时在本平台的 `message` 里填 `emotes`。
- Windows 上没有 Kick（要 WinHTTP 通道）：X01.2（X-1 的余项，未开始）。
- 登记表 D01.31 的 `commit` 原来记的是文档提交 6c68f0010，2026-10-07 已改成代码提交 96e032864。
