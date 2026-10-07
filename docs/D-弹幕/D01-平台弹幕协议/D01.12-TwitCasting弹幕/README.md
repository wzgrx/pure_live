# D01.12 TwitCasting 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `a4cb9a72e`）
- 类型：平台
- 来源：已批准升级 12-3“评论（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 TwitCasting 评论，这是新增功能（照网页播放器脚本和归档 v4 的实现写）
- 旧编号：M5.11、T06a.12
- 相关：决定 D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（`connector` 参数可以替换握手，本平台用它每次重取地址）；平台本身 [E03.4](../../../E-直播平台/E03-海外平台/E03.4-TwitCasting/README.md)（弹幕参数、`eventpubsuburl.php` 的录制 S07，见 [E03.4 记录](../../../E-直播平台/E03-海外平台/E03.4-TwitCasting/record.md)）；直播间的定时刷新和开播后重连弹幕 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)（B-24）；巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)
- 记录：[record.md](record.md)

## 目标

TwitCasting（日本个人直播）直播间能看到评论（3.x 进房只提示一次“此平台的远端弹幕尚未接入”）；修掉归档 v4 实现开播约一小时后断线就再也连不上的问题（socket 地址里的签名约一小时过期，v4 重连沿用旧地址）。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | `TwitcastingDanmakuArgs(channel, movieId)`（`packages/live_core/lib/src/sites/twitcasting/twitcasting_api.dart:47`）：进房详情只在直播中、`movie.id` 大于 0 时给；录制详情也带，关注刷新不带；直播号不大于 0 以 `connectionFailed`（`No broadcast`）结束，不发请求（`twitcasting.dart:202`） |
| 取地址 | 每次握手前 `POST https://twitcasting.tv/eventpubsuburl.php`（`pubsubUrl`，`twitcasting.dart:26`；`request`，`:45`），表单 `movie_id=<直播号>`，请求头用适配器的 `TwitcastingApi.headers`（`Referer`、`Origin`、UA `Mozilla/5.0`），以平台 `twitcasting` 的名义发出，超时同握手 10 s；回答 `{"url":"wss://<节点>.twitcasting.tv/event.pubsub/v1/streams/<直播号>/events?token=<签名>&n=<随机>"}`，只接受 `wss` 且主机是 `twitcasting.tv` 或子域名（`socketUrl`，`:58`；`_isSiteHost`，`:74`）；一次 `connect` 的请求绑一个 `CancelToken`，关闭或换房间时取消 |
| 签名 | `token` 形如 `<12 位>:::<10 位数字>:<16 位>`，中间的数字是签发时刻 + 3601 s，到时握手回 HTTP 400（实测 3540 s 能连、3640 s 不能）；所以交给 `LiveSocket` 的是名义地址 `https://twitcasting.tv/eventpubsuburl.php?movie_id=<直播号>`（`endpoint`，`:79`），本平台的握手函数 `_Resolver`（`:234`，包在 `connector` 外面）每次先 POST 拿新地址再握手 |
| socket | 握手请求头 `origin: https://twitcasting.tv`、`user-agent: Mozilla/5.0`（`socketHeaders`，`:38`；`dart:io` 会在 UA 前加 `Dart/…`，实测服务端照样接受）；默认 `dart:io` 握手；按平台 `twitcasting` 走代理；打开即就绪（`onOpen`，`:213`），客户端什么也不发 |
| 保活 | 服务端 10 s 没有别的事件就发一个 `[]`；客户端不发心跳（`heartbeatInterval` 10 s 只是无消息检测的节拍，`keepAliveInterval`，`:30`）；无消息 30 s（`silenceTimeout`，`:34`，网页的 `DISCONNECTION_THRESHOLD`）换连接，所以 30～40 s 内发现断线 |
| 事件 | 文本帧，每帧一个 JSON 数组（`decode`，`:98`；单个事件对象按一个元素读，二进制帧按 UTF-8，坏 JSON 丢这一帧）；`comment`（`comment`，`:127`）→ 白色聊天：文字 `message` 去首尾空白（空白或不是字符串不报）、用户名 `author.name`（为空用 `screenName`）、用户 id `author.id`、消息 id `id`（不加前缀）、时间 `createdAt`（不大于 0、不是整数或超范围为空）；`gift`（要地址带 `gift=1` 才推送，本实现不带）、`update_comment`、置顶、投票、突袭、通话、联播等不报 |
| 失败 | 取地址失败（网络错误、非 2xx、没有 wss 地址）当作一次握手失败，走框架的退避（单地址 2、3、4、5、6、6、6、6 s）和 8 次上限；诊断文字里 `token`、`n` 的值换成 `…`（`redact`，`:92`） |
| 人数 | 评论流里没有；人数仍来自列表的 `current_viewer_count`（网页另有要页面令牌的状态接口） |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 评论 | 3.x 有这个平台但没有弹幕：`TwitcastingSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/twitcasting/twitcasting_site.dart:22`；`EmptyDanmaku` 在 `lib/core/danmaku/empty_danmaku.dart:9`），直播间提示一次 `remote_danmaku_not_integrated`（`modules/live_play/controllers/danmaku_controller.dart:146-150`） | `TwitcastingDanmakuConnection`（`packages/live_danmaku/lib/src/sites/twitcasting.dart:174`）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:218`（传 `LiveHttp`、代理、握手 UA 开关的 `connector`） | 有评论（已做） |
| 协议 | 无 | `TwitcastingDanmakuProtocol`（:24）：取地址 `request`（:45）、`socketUrl`（:58）、`redact`（:92）、`decode`（:98）、`comment`（:127）；每次握手前取地址的 `_Resolver`（:234） | 与归档 v4 解码一致 |
| 时序 | 无 | `defaultPolicy`（:191-194）：检测节拍 10 s（:30）、无消息 30 s（:34）、没有加入计时器 | 比归档 v4 的 90 s 更快发现断线 |
| 签名过期 | 无 | 每次握手前重取地址（归档 v4 重连沿用旧地址，一小时后就连不上） | 修好 |

## 结果

- **提交**：`a4cb9a72e`（2026-09-29，`feat(live_danmaku): TwitCasting comments (M5.11)`）。之后代码没有改动；测试有两次稳定性修改：`f40f44f86`（2026-09-29，测试里关掉服务端的 WebSocket）、`f82830808`（2026-09-30，放宽保活用例的超时）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和归档 v4 的对照**（3.x 没有可对照的行为）：`fixtures/twitcasting/danmaku/v4_expected.dart` 把归档 v4 的地址解析和解码搬成独立程序。S08-live（频道 c:abzou_sub，约 45 s，13 个推送帧，其中 2 个保活 `[]`）12 条聊天逐帧一致（只差 v4 的 `twitcasting:` 前缀），取地址的回答与 `meta.json` 记下的握手地址相同。
- **和归档 v4 的差异**（record.md 11 条）：每次握手前重取签名地址；开始取地址失败按握手失败重试；无消息 30 s；不要礼物；id 不加前缀；名字为空用 `screenName`；文字必须是字符串；主机校验更严；诊断不带签名等。
- **和网页播放器的差异**：不补拉断线期间的评论（网页用 `eventpolling.php`，要页面令牌），不在 3 次失败后改用 HTTP 轮询，不加 `gift=1`，退避按框架。
- **实测**（2026-09-29 匿名直连）：本实现进推荐里人最多的房间，1449 ms 就绪（POST 加握手），120 s 收到 52 条聊天，都有消息 id、时间和用户名；空房间 130 s 收到 13 个 `[]` 保活；同房间带 `gift=1` 的 socket 多收到 1 个 `gift`（活动通知）。
- **样本**：没有新录，用归档的 `fixtures/twitcasting/S07-pubsub`（取地址的请求和回答）和 `fixtures/twitcasting/danmaku/S08-live`，新加冻结输出 `S08-live/expected.json`。
- **测试**：`packages/live_danmaku/test/sites/twitcasting_test.dart` 24 个，和当时相同（协议 8、录制 3、连接 13，含本地 HTTP + WebSocket 服务器端到端；没有循环生成的用例）。

## 验证

- 自动测试：`twitcasting_test.dart`——取地址的请求（方法、表单、请求头、超时、取消）和 S07 回放；不能用的回答（状态码、非 JSON、没有地址、`ws`/`https`、冒充的主机）；签名去除；评论各字段和边界；帧（保活、坏 JSON、其他事件、字节帧）；S08 13 帧对照 v4；连接（先 POST 再用签名地址握手、不发任何帧、断线后重新取地址、开始时 POST 失败按握手失败重试、用尽后详情不带签名、无消息 30 s 换新地址、参数不对不发请求、POST 进行中关闭取消请求、本地服务器端到端）。
- 真实接口：见上面的实测（2026-09-29）。已经连着的 socket 到一小时会不会被断开没有验证（要连一个多小时；断不断本实现都能处理）。
- 真机：没有单独的真机记录。TwitCasting 是海外平台，要代理；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有 TwitCasting 的条目。登记表状态是“完成”。

## 留下的问题

- 主播重新开播后直播号会变，旧连接不会自己结束（服务端只剩 `[]` 保活）：直播间每 60 s 刷新详情，但只在弹幕连接已结束（`DanmakuStatus.closed`）时重连（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`，B-24 由 C01.1 做的），而且刷新用的 `getRoomDetailForRefresh` 不带弹幕参数，TwitCasting 的换场次没有覆盖。→ [C01.6](../../../C-直播间/C01-进房和房间逻辑/C01.6-主播换场后弹幕参数变了要重连/README.md)（2026-10-07 登记：刷新发现换场时按进房详情取新参数重连）。
- 断线期间的评论不补拉（网页要页面令牌请求 `eventpolling.php`）：没有任务。
- 口令直播能否匿名取地址没有验证（口令直播即私密直播，现在本来就不能播放，直播间按受限类型说明，见 UPGRADES 12-5）：没有任务。
- 礼物（含带留言的付费礼物 `isPaidGift`）不显示：要地址加 `gift=1` 并解码 `gift` 事件，B-21 的礼物显示（C01.2）只覆盖已上报礼物的平台；没有任务，要做先在 V01 提议（D-026）。
- 真机：建议在真机清单第 5 节第 7 条（有代理时的海外平台）加上 TwitCasting 的评论，由 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 一起看（见报告）。
