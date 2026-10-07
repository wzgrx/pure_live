# D01.20 YouTube 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 da62d0146）
- 类型：平台
- 来源：已批准升级 23-3“聊天当作弹幕，付费留言按普通聊天显示”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有 YouTube 这个平台但没有聊天，这是新增功能。后续的 B-13（醒目留言、通知、撤回、在线人数、全部聊天）、B-22（进房补报置顶的 Super Chat）、B-23（新礼物）是同一升级表附录 B 的条目
- 旧编号：M5.19、T06a.20
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`LiveMessage.replayed` 和去重闸门对醒目留言的年龄规则是本平台 B-22 时加的；本平台不用 WebSocket 运行时，同快手 [D01.6](../D01.6-快手弹幕/README.md) 直接继承 `DanmakuConnectionBase`）；平台本身、InnerTube 请求和弹幕参数 [E03.10 记录](../../../E-直播平台/E03-海外平台/E03.10-YouTube/record.md)；设置“YouTube 显示全部聊天”（`apps/pure_live/lib/features/settings/danmaku_page.dart:98～104`）；表情图片在聊天行（[C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)、[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md)）和飞行弹幕（[D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)）；下播后重连 B-24 在 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；决定 D-017、D-018（新设置只加不改）；详细记录 [record.md](record.md)

## 目标

YouTube 直播间能看到实时聊天（实测延迟中位数 3.4 s）。比归档 v4 修掉了 emoji 写成短码、时间越界整个回答抛错、开始时一次失败就结束、回放续页请求 400 后还重试、`reload` 后重报历史等问题。后来（B-13）Super Chat 显示为醒目留言（原币种金额、网页的颜色和置顶时长），Super Sticker、会员、赠送会员显示为通知，删除的消息撤下，在线人数每 30 s 更新，新增设置“显示全部聊天”；（B-22）进房时补上置顶栏里还在显示的 Super Chat；（B-23）读新礼物 `giftMessageViewModel`。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/youtube.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 传输 | InnerTube HTTP 轮询，不接推送（续页里的 `invalidationId` 是未公开的 GCM 主题）；`YouTubeDanmakuConnection`（:857）直接继承 `DanmakuConnectionBase`，每次 `start`（:869）建一个 `_YouTubeChat`（:915）；请求 `POST https://www.youtube.com/youtubei/v1/<端点>?prettyPrint=false`，正文是 `YouTubeApi.webContext` 加 `videoId`（`nextBody` :194）或 `continuation`（`chatBody` :197），请求头 `YouTubeApi.apiHeaders`（UA、`accept-language: en-US`、`SOCS=CAI`、`referer`、`origin`）加 JSON 内容类型，走注入的 `LiveHttp`（平台 `youtube` 的代理路线和限流）；每个请求 15 s（`requestTimeout` :140）；没有心跳 |
| 参数 | `YouTubeDanmakuArgs.videoId` 去空白后不是 11 位视频号：`connectionFailed`（`No broadcast`），不发请求 |
| 加入 | `next`（约 0.34～0.56 MB）取 `liveChatRenderer.continuations[0]` 的续页（默认“精选聊天”）和在线人数（`watch` :333、`_liveViewers` :378）→ 第一次 `get_live_chat`（历史，聊天不报）→ 报就绪、`next` 的在线人数（`audience` :221）、B-22 补报的置顶 Super Chat；`next` 和第一次轮询合计失败 3 次（`startAttempts` :155，间隔 2 s）以 `connectionFailed` 结束，开始阶段不报重连 |
| 没有聊天 | `next` 没有 `liveChatRenderer`：`connectionFailed`（`No live chat`）；`isReplay`：`Chat replay only`；都不轮询 |
| 轮询 | 上一次请求结束后等回答的 `timeoutMs`，限制在 1～5 s（`minimumDelay` :143、`maximumDelay` :148、`pollDelay` :213），没有时 5 s（网页靠推送，没有推送时 10 s）；`reloadContinuationData` 之后的回答是重新开始的历史，不报；失败 2 s 后（`retryDelay` :151）用同一续页重试，连续第 1 次报 `DanmakuReconnecting`，第 8 次（`maxFailures` :158）以 `reconnectsExhausted` 结束（`follow` :968） |
| 结束 | 回答没有续页：报完这次的行后 `connectionFailed`（`Chat ended: <messageRenderer 说明>`，`_ended` :911）；频道下一场要由直播间刷新拿到新 `videoId` |
| 聊天 | `liveChatTextMessageRenderer` → 白色聊天（`_chatLine` :570）：文字是 `message.runs` 拼起来去首尾空白（`_runs` :723），标准 emoji 写字符本身（`emojiId`），频道自定义表情写第一个 `shortcuts`（如 `:face-purple-crying:`）并填表情图片（`customEmoji` :742，S02.1）；名字 `authorName`；用户 id `authorExternalChannelId`；消息 id `id`（不加前缀）；时间 `timestampUsec`（微秒，正数且在范围内，`_time` :808） |
| B-13 醒目留言 | `liveChatPaidMessageRenderer` → 醒目留言（`_superChat` :593）：`priceText` 是 `purchaseAmountText` 原文（原币种，不换算），`price` 0（回答里没有数字金额）；颜色 `headerBackgroundColor`/`bodyBackgroundColor` 写成 `#rrggbb`；头像取最大的 https 缩略图；`endTime` 优先同一回答里同 id 的 ticker 条目的 `fullDurationSec`（`_pinned` :504），否则按颜色档（`tierDisplay` :178：绿 2 min、黄 5 min、橙 10 min、品红 30 min、红 1 h），不置顶的两档和不认识的颜色 60 s（`unpinnedDisplay` :170） |
| B-13 通知 | 会员加入和里程碑（`_membership` :650）、Super Sticker（`_sticker` :638，“名字 送出 Super Sticker 金额：贴图说明”）、赠送和领取会员 → `LiveNoticeKind.subscription` 的通知（`_notice` :700），平台原文不翻译 |
| B-13 撤回 | `removeChatItemAction`、`markChatItemAsDeletedAction` → `LiveRetraction.message(targetItemId)`；`removeChatItemByAuthorAction`、`markChatItemsByAuthorAsDeletedAction` → `LiveRetraction.user(externalChannelId)`（`_retraction` :540）；历史里的删除不报；`replaceChatItemAction`、`clearChatWindowAction` 不读 |
| B-13 在线人数 | 加入后每 30 s（`viewerInterval` :163，`viewers` :1006）请求 `updated_metadata`：第一次按视频号（`metadataBody` :204），之后用上一次的续页（`metadataContinuationBody` :208）；失败、坏回答不报、不影响聊天，下一轮改回按视频号；结束后的“N views”不报 |
| B-13 全部聊天 | 设置“显示全部聊天”打开时，改写续页 protobuf（字段 119693434 → 16 → 1：4 精选、1 全部，`allChatContinuation` :250），只改“重新开始”的续页（`next` 的和之后的 `reload`）；改写不了直接用原续页；改写后被拒（4xx 或回答没有聊天）马上退回精选，不算失败 |
| B-22 置顶补报 | 第一次回答里 `liveChatTickerPaidMessageItemRenderer`（`durationSec` 大于 0、嵌着付费留言）解成醒目留言，标 `replayed: true`，按发送时间排序（`_stillPinned` :444）；`endTime` 是收到时间加 `durationSec`（和网页置顶条消失的时刻一致）；只在进房时补，之后的置顶条目和 reload 后的历史不补；同 id 由去重闸门和醒目留言栏去重 |
| B-23 礼物 | `giftMessageViewModel` → 礼物（`_gift` :669，`YouTubeGift` :38）：名字 `authorName.content`，文字 `text.content`（如 `sent Donut`），礼物名去掉开头的 `sent `（:690），图片取最大的 https 地址；没有频道号和时间（有时照读） |
| 不报的 | 欢迎语、占位（精选聊天里被隐藏的行）、替换、投票、面板、横幅、审核状态 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | 3.x 有 YouTube 这个平台但没有聊天：`YouTubeSite.getDanmaku() => EmptyDanmaku()`（`lib/core/site/youtube/youtube_site.dart:39`），直播间只提示一次 `remote_danmaku_not_integrated`（`lib/modules/live_play/controllers/danmaku_controller.dart:146～150`）；公告 `youtube_chat_notice`“YouTube Live 远端聊天尚待接入；……”（`assets/translations/zh.json:1885`） | `YouTubeDanmakuConnection`（`youtube.dart:857`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:227`，建连接时读设置 `Settings.youtubeShowAllChat`；公告 `YouTubeApi.chatNotice`（`packages/live_core/lib/src/sites/youtube/youtube_api.dart:396`）去掉了“远端聊天尚待接入”，3.x 原文留作 `legacyChatNotice`（:399）给对照测试和迁移 | 有聊天（已做） |
| 在线人数 | 卡片和详情的“N watching” | 进房后 `next` 一次、`updated_metadata` 每 30 s；`packages/live_core/lib/src/audience.dart:186～190` 仍是 `roomRealtime` | 随直播更新（已做） |
| 设置 | 无 | `Settings.youtubeShowAllChat`（`packages/live_store/lib/src/settings/settings.dart:626`，默认关），设置 → 弹幕 → 更多（`danmaku_page.dart:98～104`，“YouTube 显示全部聊天 / 默认和网页一样只显示精选聊天；打开后显示所有消息”）；设置目录 `settings_catalog.dart:1731` | 已做 |
| 醒目留言、通知、撤回、礼物 | 无 | 直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:893～910`：醒目留言栏、通知行、`chat.retract`、礼物行（受“在聊天列表显示礼物”开关控制，B-21） | 已做 |

## 结果

- **提交**：da62d0146（2026-09-29，首次实现）；f62fe8317（2026-09-30，本地服务器测试先读完正文再计数）；476f578eb（2026-10-01，B-13）；f7f0922d3（2026-10-01，B-22、B-23，和 17LIVE 的 B-25、B-26 同一次提交）；fffd28b31、8386b679d（2026-10-01，[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 第 8 条：频道表情图片和格式化）。
- **和归档 v4 的对照**：`fixtures/youtube/danmaku/v4_expected.dart` 把 v4 的协议和轮询循环搬成独立程序（计时器换成记录器）。S06-live 94 行、S07-live-paid 255 行聊天按差异 1～4 换算后逐字段一致；S06 接 S08-ended 的会话（请求、续页、等待、21 行、聊天结束）一致；S09-synthetic 的 36 个回答、14 个 `next`、15 段会话逐个对照（有意差异单独断言）。
- **有意差异**（record.md“与归档 v4 的差异”14 条）：id 不加 `youtube:` 前缀；emoji 写字符本身；时间用本地时区、0 和负数不当时间、越界只让这一行没有时间；名字和金额也读 `runs`；回放直接结束；`reload` 后的历史不报；加入时报在线人数；开始阶段失败重试 3 次；第一次回答没有续页时不报就绪；请求头用适配器的；视频号要是 11 位。
- **样本**：`fixtures/youtube/danmaku/` 下 S06-live（归档）、S07-live-paid、S08-ended（2026-09-28 录）、S09-synthetic（`synthetic_cases.py` 生成）、S10-live-all-chat（Korone 生日直播，全部聊天，第一次回答带 50 条置顶 Super Chat）、S11-metadata-ended、S12-gifts（2026-09-30 录）；观众名字、频道号、续页里的频道号都脱敏。
- **测试**：`packages/live_danmaku/test/sites/youtube_test.dart` 现在运行 133 个用例（源码里 69 个 `test(`，其中 4 个在循环里：录制对照 3 个样本、S09 的 36 个回答、14 个 `next`、15 段会话各一个）；首次实现时 93 个，B-13 后 124 个，B-22、B-23 后 132 个（另做过 8 种变异），S02.1 加了 1 个（S07 的频道表情）。

## 验证

- 自动测试：`youtube_test.dart`——协议 7、录制对照 v4 3、S09 合成回答 38、合成 `next` 16、会话 21、连接 8（含本地 HTTP 服务器端到端：线上的请求头和正文、S07 的回答、中途 503 后重连），B-13 32 个（醒目留言档位和 ticker 时长、通知、撤回、在线人数、全部聊天的改写和被拒退回），B-22 5 个、B-23 3 个，S02.1 1 个。在 +30 天、+1 年、+5 年下运行都通过。
- 真实接口：2026-09-28（UTC 22:00～22:40）匿名经本机代理：本实现进 `e3n116VqcrE`（约 4 万人）2.8 s 就绪，120 s 收到 113 行聊天、6 条 Super Chat，没有重复 id；已结束的回放 2.2 s 以 `Chat replay only` 结束，没有回放的和普通视频都是 `No live chat`，只发一个 `next`。2026-09-30 本实现全部聊天实测：Korone 150 s 全部 1200 行对精选 778 行，Lofi Girl 3 次删除两边相同，改写后的续页一次也没被拒。没实测到的：`timedContinuationData`、蓝色一档、两种 `markChat…AsDeleted`、服务器拒绝改写的续页、进房补报的 Super Chat 之后又作为聊天收到；B-22、B-23 没有用本实现接真实服务器跑。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节没有 YouTube（第 4 节第 10 条 F-FAV-08 只看旧关注迁移），海外平台要用户开代理；[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 第 8 条“YouTube 表情显示成文字”来自直播间代码审查的记录，不是 K90 上看到的。登记表是“完成”，按 D-029 这个平台的弹幕还算“没验证”。

## 留下的问题

- 不接推送，轮询最多 5 s 一次，延迟中位数 3.4 s、最长 7.7 s（网页靠推送更快）：推送通道没有公开，没有任务。
- 醒目留言的 `price` 一律 0（聊天条目里没有数字金额），醒目留言栏不能按金额排序：没有任务。
- 改了“YouTube 显示全部聊天”后，已经打开的 YouTube 直播间不会变：连接在进房时建（`apps/pure_live/lib/features/live_play/live_play_page.dart:278`），`allChat` 在建连接时读（`platforms.dart:227`），直播间只在“显示弹幕”“小窗弹幕”两个设置变时同步弹幕（`room_controller.dart:313～315`），要重新进房才生效。record.md 当时留给直播间“改设置时重连”，没有做；没有任务，建议在 C01 登记。
- 聊天结束后跟到频道的下一场要靠直播间刷新拿到新 `videoId`：B-24 已做（C01.1：每 60 s 刷新详情，弹幕连接结束后重连）。
- 长时间轮询是否被限流没有测到（实测最长 150 s、约 26 次请求，没有 429）；遇到时按失败重试，8 次后结束：没有任务。
- 平台层的推荐和搜索卡片在 E03.10（23-2）后也带“N watching”，`audience.dart` 里 YouTube 严格说已经可以是 `roomList`（record.md“在线人数”），本任务没改：没有任务，归 E06 一类的平台层核对。
- 真机上没看过（要用户开代理：聊天和表情、醒目留言和颜色、会员通知、删除撤回、在线人数更新、显示全部聊天）：没有单独的任务，建议加进真机清单第 2 节，归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类的补验。
