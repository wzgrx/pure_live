# D01.20 YouTube 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 23-3“聊天当作弹幕，付费留言按普通聊天显示”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 YouTube 没有聊天，这是新增功能
- 旧编号：M5.19、T06a.20
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`replayed` 和去重闸门的醒目留言规则是本平台 B-22 时加的）；平台本身、InnerTube 请求和弹幕参数 [E03.10 记录](../../../E-直播平台/E03-海外平台/E03.10-YouTube/record.md)；设置“YouTube 显示全部聊天”（`apps/pure_live/lib/features/settings/danmaku_page.dart:102`）；详细记录 [record.md](record.md)

## 目标

YouTube 直播间能看到实时聊天（延迟中位数 3.4 s）；后来（B-13）Super Chat 显示为醒目留言（原币种金额、网页的颜色和置顶时长），Super Sticker、会员、赠送会员显示为通知，删除的消息撤下，在线人数每 30 s 更新，新增设置“显示全部聊天”；（B-22）进房时补上置顶栏里还在显示的 Super Chat；（B-23）读新礼物 `giftMessageViewModel`。

## 协议要点

| 项 | 内容 |
|---|---|
| 传输 | InnerTube HTTP 轮询，不接推送（GCM 主题，未公开）；直接继承 `DanmakuConnectionBase`；请求 `POST https://www.youtube.com/youtubei/v1/<端点>?prettyPrint=false`，正文是 `YouTubeApi.webContext` 加 `videoId` 或 `continuation`，请求头 `YouTubeApi.apiHeaders`（含 `SOCS=CAI`、`accept-language: en-US`），走注入的 `LiveHttp`（平台 `youtube` 的代理） |
| 加入 | `next`（约 0.3～0.6 MB）取聊天的第一个续页（默认“精选聊天”）和在线人数 → 第一次 `get_live_chat`（历史，不报）→ 报就绪、在线人数、B-22 补报的置顶 Super Chat（标 `replayed`） |
| 轮询 | 上一次结束后等 `timeoutMs`（限制 1～5 s，没有时 5 s；网页靠推送是 10 s），用上一次的续页；失败 2 s 后重试同一续页，第 1 次报重连，第 8 次 `reconnectsExhausted`；请求 15 s 超时 |
| 消息 | `liveChatTextMessageRenderer` → 白色聊天（emoji 写字符本身，频道表情写 `:名字:`，id 是 `id`，时间 `timestampUsec`）；`liveChatPaidMessageRenderer` → 醒目留言（`priceText` 原币种原文，`price` 0，颜色 header/body，`endTime` 优先同一回答里 ticker 的 `fullDurationSec`，否则按颜色档 60～3600 s）；会员、Super Sticker、赠送会员 → 通知；四种删除动作 → 撤回；`giftMessageViewModel` → 礼物（`YouTubeGift`） |
| 在线人数 | 加入时报 `next` 的 `videoViewCountRenderer`，之后每 30 s 请求 `updated_metadata`（失败不影响聊天） |
| 全部聊天 | 设置打开时改写续页 protobuf（字段 119693434 → 16 → 1：4 精选、1 全部），只改“重新开始”的续页；改写被拒（4xx 或没有聊天）马上退回精选 |
| 结束 | `next` 没有聊天：`connectionFailed`（`No live chat`）；回放：`Chat replay only`；回答没有续页：`Chat ended: <说明>`；`videoId` 不是 11 位：`No broadcast` |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `YouTubeSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/youtube/youtube_site.dart:39`），公告“远端聊天尚待接入” | `YouTubeDanmakuConnection`（`packages/live_danmaku/lib/src/sites/youtube.dart:857`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:227`，连接时读设置 `youtubeShowAllChat`；公告 `YouTubeApi.chatNotice` 去掉“尚待接入” | 有聊天（已做） |
| 协议 | 无 | `YouTubeDanmakuProtocol`（:124）：时限 :140～170（请求 15 s、间隔 1～5 s、重试 2 s、人数 30 s、不置顶档 60 s）、`allChatContinuation`（:250）、`chat`（:410）；`YouTubeGift`（:38） | 与归档 v4 对照，有意差异 14 条 |
| 在线人数 | 卡片和详情的“N watching” | 进房后 `next` 一次、`updated_metadata` 每 30 s；`audience.dart` 仍是 `roomRealtime` | 随直播更新 |

## 结果

- **提交**：da62d0146（2026-09-29，M5.19），476f578eb（2026-10-01，B-13），f7f0922d3（2026-10-01，B-22、B-23，和 17LIVE 的 B-25、B-26 同一次提交），fffd28b31（S02.1：频道表情图片）。
- **和归档 v4 的对照**：`fixtures/youtube/danmaku/v4_expected.dart` 把 v4 的协议和轮询循环搬成独立程序（计时器换成记录器）。S06-live 94 行、S07-live-paid 255 行聊天按差异 1～4 一致；S06 接 S08-ended 的会话（请求、续页、等待、聊天结束）一致；S09-synthetic 的 36 个回答、14 个 `next`、15 段会话逐个对照。
- **实测**（经本机代理，匿名只读）：本实现进 `e3n116VqcrE`（约 4 万人）2.8 s 就绪，120 s 113 行聊天、6 条 Super Chat；已结束和普通视频只发一个 `next` 就结束。2026-09-30 录 S10（Korone 生日直播，全部聊天 1200 行对精选 778 行，第一次回答带 50 条置顶 Super Chat）、S11（结束后的人数）、S12（新礼物）。
- **样本**：`fixtures/youtube/danmaku/` 的 S06-live、S07-live-paid、S08-ended、S09-synthetic、S10-live-all-chat、S11-metadata-ended、S12-gifts（观众名字、频道号、续页里的频道号都脱敏）。
- **测试**：`packages/live_danmaku/test/sites/youtube_test.dart` 做完时 93 个，B-13 后 124 个，B-22、B-23 后 132 个（另做过 8 种变异）。

## 验证

- 自动测试：`youtube_test.dart`（本地 HTTP 服务器端到端：线上的请求头和正文、S07 的回答、中途 503 后重连；400 时退回精选）。
- 真实接口：见上面的实测。没实测到的：`timedContinuationData`、蓝色一档、两种 `markChat…AsDeleted`、服务器拒绝改写的续页、进房补报的 Super Chat 之后又作为聊天收到、B-22 和 B-23 没有用本实现接真实服务器跑。
- 真机：没有；海外平台要代理。

## 留下的问题

- 不接推送，轮询最多 5 s 一次，延迟中位数 3.4 s、最多 7.7 s（网页靠推送更快）。
- 醒目留言的 `price` 一律 0（聊天条目里没有数字金额），醒目留言栏不能按金额排序。
- 频道自定义表情的图片：聊天行和飞行弹幕已经显示（S02.1、D03.2）。
- 聊天结束后跟到频道的下一场要靠直播间刷新拿到新 `videoId`（C01.1 的 B-24：弹幕连接结束后重连）。
- 长时间轮询是否被限流没有测到（最长 150 s，没有 429）。
