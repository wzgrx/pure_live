# D01.17 CHZZK 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 20-2“CHZZK 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 CHZZK 弹幕，这是新增功能
- 旧编号：M5.16、T06a.17
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数（`chatChannelId`、`channelId`）[E03.7 记录](../../../E-直播平台/E03-海外平台/E03.7-CHZZK/record.md)；表情图片在聊天行（C01.2、S02.1）和飞行弹幕（D03.2）；详细记录 [record.md](record.md)

## 目标

CHZZK（韩国 NAVER 直播）直播间能看到聊天；照网站的 NAVER 聊天 SDK 4.11.0 选服务器、加入、心跳、重连，修掉归档 v4 算出路由不列出的服务器、把聊天连接数当在线人数、被拒后换令牌无用重试等问题。后来（B-12）捐赠显示为醒目留言（按金额分五档时长），事后屏蔽撤回，置顶公告、订阅赠送、系统行显示为通知，聊天安静 3 分钟后读一次直播状态、主播重新开播换了聊天频道就跟过去。

## 协议要点

| 项 | 内容 |
|---|---|
| 开始的请求 | 同时发：访问令牌 `comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=<chatChannelId>&chatType=STREAMING`（3 次，间隔 0.5、1 s，每次 5 s）和服务器列表 `routing.chat.naver.com/routing/getRouting?serviceId=game`（1 次，1.5 s，失败用 SDK 内置的 `kr-ss1`～`kr-ss5`）；整个连接沿用 |
| 地址 | `wss://<服务器>/chat`，从随机一台开始，失败按列表轮换；请求头 `origin: https://chzzk.naver.com` 和桌面 UA；默认 `dart:io` 握手；按平台 `chzzk` 走代理 |
| 加入 | 发只读加入 `cmd 100`（文本帧，`auth: READ`）；`cmd 10100` 的 `retCode 0` 就绪并用 `sid` 请求最近 50 条（`cmd 5101`）；加入超时 5 s；`retCode` 302～304 重连，其他以 `connectionFailed` 结束（实测只读加入不检查令牌）；`cmd 90102`（结束会话）也结束 |
| 心跳 | 20 s 发 `{"ver":"3","cmd":0}`，服务端回 `cmd 10000`；服务端 ping 立刻回 pong；无消息 30 s 换连接（SDK 的 `pingInterval` + `pingTimeout`）；六台服务器轮换，间隔 1、1、1、1、1、2、2、2 s |
| 聊天 | `cmd 93101`、`93102` 和最近聊天的行：种类 1、11（订阅留言）且状态 `NORMAL` 的是聊天；名字 `profile.nickname`，id `<用户>:<时间>`（网站按用户和时间区分消息），白色；`BLIND`、`CBOTBLIND` 的行不报 |
| B-12 | 种类 10 捐赠 → 醒目留言（`priceText` 如 `1,000 치즈`，时长按金额 1 万、10 万、50 万、100 万分 1、2、5、30、60 分钟，匿名是 `익명의 후원자`）；94008 → `LiveRetraction.message('<userId>:<messageTime>')`；94010 和最近聊天的 `notice` → 置顶公告通知；种类 12 → 订阅赠送通知；种类 30 → 系统行通知（只给管理员看的不报）；同一次连接里醒目留言和通知按 id 只报一次（最多 512 个） |
| 安静检查 | 3 分钟没有推送的行就读 `api.chzzk.naver.com/polling/v3.1/channels/<channelId>/live-status`，`OPEN` 且 `chatChannelId` 变了就取新令牌、`reopen` 到新频道（不提示） |
| 人数 | 行里的 `mbrCnt` 是聊天连接数（和平台的 `concurrentUserCount` 相差 4%～75%），不报；人数仍来自列表和详情 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `ChzzkSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/chzzk/chzzk_site.dart:58`），提示一次“尚未接入” | `ChzzkDanmakuConnection`（`packages/live_danmaku/lib/src/sites/chzzk.dart:635`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:223` | 有聊天（已做） |
| 协议 | 无 | `ChzzkDanmakuProtocol`（:80）：心跳 20 s、无消息 30 s、加入超时 5 s（:82～91）、匿名名（:115）、路由（:157）、令牌（:180）、直播状态（:236～238）；`quietPeriod` 3 分钟（:674） | 与归档 v4 对照，有意差异 16 条 |
| 人数 | `audience.dart` 里 CHZZK 是 `roomList` | 不变 | 不显示聊天连接数（REG-CHZZK-002：主播隐藏人数时不显示） |

## 结果

- **提交**：00da1b768（2026-09-29，M5.16），e1c4a3fa3（2026-10-01，B-12）；fffd28b31（S02.1：消息带表情图片 `{:名字:}`）。
- **和归档 v4 的对照**：`fixtures/chzzk/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序。加入、最近聊天请求、ping 与录制逐字节相同；S09-live 125 条、S10-live 106 条聊天一致（v4 另报人数）；S11-recent 123 条一致，另多 1 条订阅留言；S12-synthetic 15 组里 9 组在统一换算后一致、6 组有意差异。
- **实测**（2026-09-28 匿名直连）：有效、编造、`null`、别的频道的令牌都能只读加入；不存在的聊天频道回 `retCode 105` 后服务端关连接；每场直播换一个聊天频道；约 300 ms 加入。2026-09-30 录 150 场的最近聊天、16 场各 900 s，得到 S13～S17（置顶、任务捐赠、清洁机器人屏蔽、临时限制的 26 个 `HIDDEN`、匿名订阅赠送）。
- **样本**：`fixtures/chzzk/S08-chat-token`，`fixtures/chzzk/danmaku/` 的 S09-live、S10-live、S11-recent、S12-synthetic、S13-recent、S14-live、S15-live、S16-synthetic、S17-live-status-closed。
- **测试**：`packages/live_danmaku/test/chzzk_test.dart` 做完时 56 个（另做过 25 种变异），B-12 后 74 个（另做过 21 种变异）；S02.1 另加表情用例。

## 验证

- 自动测试：`chzzk_test.dart`（本地 WebSocket 服务器端到端：路径、Origin、UA、加入、S10 的帧、服务端 ping 和 pong）。
- 真实接口：见上面的实测。没实测到的：直播中换置顶（94010）、送给频道的订阅赠送、真正的换聊天频道（直播状态的开播、下播回答是真实的，换频道流程用本地假连接）。
- 真机：没有；海外平台要代理。

## 留下的问题

- 主播重新开播后最多约 3 分钟才跟到新聊天频道（只在安静 3 分钟时读直播状态；网站每 30 s 读一次）。
- 只读：不登录，不能发言，收不到只给管理员看的系统行。
- `익명의 후원자` 是网站原文，置顶和订阅赠送的句子是本应用拼的中文，都没走翻译文件。
- 视频捐赠网站聊天列表不显示，这里显示为醒目留言（文字是视频标题），是有意差异。
- 醒目留言的五档时长取自哔哩哔哩（网站没有时长）。
