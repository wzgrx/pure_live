# D01.6 快手 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `60e8e0278`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 5 个平台）：把 3.x 的 `lib/core/danmaku/kuaishou_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一，也是其中唯一用 HTTP 轮询的
- 旧编号：M5.5、T06a.6
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（为本平台留了 `run.delay`、`run.ended`）；平台本身 [E01.5](../../../E-直播平台/E01-国内五大平台/E01.5-快手/README.md)（弹幕参数、表情表，见 [E01.5 记录](../../../E-直播平台/E01-国内五大平台/E01.5-快手/record.md)）；评论表情 [S02.1 记录](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md)第 8 项；飞行弹幕里的表情图 [D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)；直播间的启动超时 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；巡检 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 C-15、C-16（不做）
- 记录：[record.md](record.md)

## 目标

快手直播间的评论和在线人数照 3.x 用移动端网页的评论 feed 轮询拿到（桌面端 WebSocket 要浏览器签名，匿名拿不到）：请求、解析、重试、退避都和 3.x 一样；修掉 3.x 一条评论时间超出范围就让整个回答失败、cursor 不前进、约 47 s 后弹幕彻底断开的潜在问题。快手房间页不给在线人数，直播间的人数靠这里的 `currentWatchingCount` 补上。

## 协议要点

| 项 | 内容 |
|---|---|
| 传输 | HTTP 轮询，不用 WebSocket 运行时，直接继承 `DanmakuConnectionBase`；请求走应用注入的 `LiveHttp`（平台 id `kuaishou` 的代理和限流），每次请求超时用它的默认值 20 s（`packages/live_net/lib/src/request.dart:25`） |
| 参数 | `KuaishouDanmakuArgs`（`packages/live_core/lib/src/sites/kuaishou/kuaishou_api.dart:21`）：本场直播的 `liveStreamId`（每次开播都换，空的直接抛 `FormatException`、不发请求）、取房间时生效的 Cookie（用户的，否则游客会话的），S02.1 起另带 `emotes`（房间页的表情表，`emojiTable`，`kuaishou_api.dart:294`；从卡片进房时为空）；未开播的房间没有弹幕参数 |
| 地址 | `GET https://livev.m.chenzhongtech.com/wap/live/feed?liveStreamId=…[&cursor=…]`；主地址没回答、非 2xx、正文不是 JSON 时换 `https://m.gifshow.com/wap/live/feed`，参数相同（`endpoints`，`kuaishou.dart:60-62`）；每次请求都先试主地址；被拒（`result` 不是 1）不换备用地址 |
| 请求头 | Android 16 上 Chrome 139 的移动端 UA、`Accept: application/json, text/plain, */*`、`Referer: https://livev.m.chenzhongtech.com/`（`headers`，`kuaishou.dart:84-88`）；Cookie 去首尾空白后非空才带 |
| cursor | 第一次不带，之后带上一次回答的；回答里为空时沿用旧的，失败的请求不改它 |
| 解析 | `parse`（`kuaishou.dart:123`）：正文最多解 3 层 JSON（feed 发的是“装着 JSON 的 JSON 字符串”），外面有对象 `data` 取里面；`result` 不是 1（数字、文字“1”、1.0 都算 1）是 `KuaishouFeedRejected`（`:15`）；`pullCycleSeconds` 取整限制在 1～10 s，缺省 3 s（`:137`）；`currentWatchingCount`（`5.6w`、`1.2万`、`1,234`）按 `parseAudienceNumber` 报 `onlineViewers`，先于评论报；`liveStreamFeeds` 里 `type` 为 `comment`（不分大小写）且 `content` 非空的是聊天 |
| 聊天 | `_comment`（`kuaishou.dart:153`）：昵称 `author.userName`，空的写“快手用户”（`anonymousUserName`，`:81`）；用户 id `author.userId`；时间 `time`（毫秒，超出 `DateTime` 范围或无穷大的条目只跳过这一条）；id `kuaishou:<id>`，没有 id 时 `sha1(time \0 userId \0 content)`；白色；礼物等其他类型不显示 |
| 表情（S02.1 加） | 评论里 1～16 字的 `[...]` 码在 `emotes` 表里有的，作为 `LiveMessage.emotes`（`codeEmotes`，`kuaishou.dart:181`，正则 `:190`）；表里没有的由应用的本地表情包（`assets/emo/` 的快手表 207 个）补 |
| 节奏 | 开始时拉取最多 3 次（间隔 0.6、1.4 s，`startRetryDelays`，`:71`，用 `run.delay`，`close` 立即结束），都失败把最后一次的错误抛给调用方；拿到回答就就绪、报出消息；之后按服务端间隔轮询，同一时间只有一个请求；失败后等 1、2、4、8、8、8、8、8 s（`backoff`，`:100`），第 1 次失败报重连，第 9 次失败以 `reconnectsExhausted` 结束（`maxFailures` 8，`:75`），任何一次成功清零并再报一次就绪；没有心跳 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/kuaishou_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/kuaishou.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `KuaishouDanmaku`（:45），`KuaishowSite.getDanmaku()`（`core/site/kuaishou/kuaishou_site.dart:50`） | `KuaishouDanmakuConnection`（:213）继承 `DanmakuConnectionBase`；应用登记在 `apps/pure_live/lib/app/platforms.dart:211`，传应用的 `LiveHttp` | 一致；请求走注入的 `LiveHttp` |
| 地址和请求头 | :50-51、:219-223 | `KuaishouDanmakuProtocol`（:57），地址 :60-62，请求头 :84-88 | 一致；录制的 10 次请求地址逐字相同 |
| 开始重试 | :113 的 600、1400 ms，`Future.delayed` 停不下来 | `startRetryDelays`（:71），`start`（:220）用 `run.delay`，`close` 立即结束 | 一致；关闭更快 |
| 退避和放弃 | `_maxReconnectAttempts = 8`（:53），判断在 :179 | `maxFailures`（:75）、`backoff`（:100），轮询 `follow`（:277） | 一致 |
| 解析 | `parseFeedPayload`（:248），间隔 :261，sha1 id :277，“快手用户” :281 | `parse`（:123），`_comment`（:153），`anonymousUserName`（:81） | 一致 |
| 坏时间 | 一条评论的时间超出范围让整个回答失败、cursor 不前进（:275、:285、:301、:138） | 只跳过这一条（`_maxMilliseconds`，:148） | 修好（3.x 问题 1） |
| 开始失败的错误 | 一律 `CoreError` 等，直播间只记日志不提示 | 有类型：`TransportFailure`、`HttpStatusFailure`、`FormatException`、`KuaishouFeedRejected`（:15）；直播间 `room_controller.dart:839-844` 记日志，并在聊天区提示“弹幕服务器连接失败” | 错误有类型（Q01.1）；提示是 4.x 直播间统一的做法 |
| 主地址超时 | 每次请求最多 20 s，3.x 直播间启动超时也是 20 s，备用地址来不及起作用（3.x 问题 2） | 每次请求仍 20 s；直播间启动超时改成 30 s（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:100`，注释 :142-143 写明是为快手），多画面同样 30 s（`multiview_controller.dart:157`） | 主地址超时后备用地址还有 10 s |
| 表情 | 3.x 打包了 `assets/emo/json/kuaishou.json` 但没读 | 房间页表情表（`KuaishouDanmakuArgs.emotes`）+ 本地表情包（S02.1） | 列表里显示表情图；飞行弹幕的表情图在 D03.2 |

## 结果

- **提交**：`60e8e0278`（2026-09-29，`feat(live_danmaku): Kuaishou danmaku refactored from v3 (M5.5)`）；之后 `fffd28b31`（2026-10-01，S02.1 的评论表情，`feat(danmaku): messages name their emote pictures (M13.16)`）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/kuaishou/danmaku/legacy_expected.dart` 把 3.x 整个类搬成独立程序，在记录计时器的 zone 里跑。S16-live（主播 `Kslala666`，约 29 s，10 次回答）42 条评论、10 次人数逐字段一致，整段会话的 11 次请求、10 次 3 s 等待、1 次就绪、52 条消息顺序一致；S17-synthetic 38 个回答（2 个按坏时间的差异变换）和 15 段会话一致（2 段抛出的错误类型按对照表换算）。
- **有意差异**（record.md 8 条）：事件代替回调、坏条目只跳过、错误有类型、2xx 但不是 JSON 一律换备用地址、关闭原因统一为 `reconnectsExhausted` 并带详情、不写日志、去掉 3.x 测试用的 `fetcher` 和 `minimumPollDelay`、开始阶段的等待可取消。
- **没采用归档 v4 的做法**：被拒也换备用地址、开始失败以“失败”结束而不抛、每次请求 10 s、时间不大于 0 当作没有时间。
- **依赖**：`packages/live_danmaku/pubspec.yaml` 加 `crypto: ^3.0.7`（和 `live_core` 同一版本，`pubspec.lock` 没变）。
- **样本**：`fixtures/kuaishou/danmaku/` 下 S16-live（`frames.jsonl` 10 次请求和回答，作者和文字已由归档录制工具换成合成值）、S17-synthetic（`cases.json`：38 个回答、15 段会话）。
- **测试**：`packages/live_danmaku/test/kuaishou_test.dart` 现在 70 个，和当时相同（协议 5、录制对照 2、合成回答 39、合成会话 16、连接 8）。其中 38 + 15 = 53 个由 `cases.json` 循环生成（`kuaishou_test.dart:389`、`:416`），所以 `grep -c "test("` 只数到 19。S02.1 的表情用例在 `packages/live_danmaku/test/emotes_test.dart:78`（快手表情码），没有加在本文件。

## 验证

- 自动测试：`kuaishou_test.dart`——地址、请求头、参数、重试和退避常数；S16 10 个回答和整段会话对照 3.x；S17 38 个回答、15 段会话对照 3.x；连接（开始失败抛出的类型且回到空闲、第 9 次失败以 `reconnectsExhausted` 结束共 19 次请求、开始时的请求被 `close` 取消、等待中 `close`、换房间丢掉晚到的回答且不带旧 cursor、本地 HTTP 服务器端到端含 503 后换备用地址）。表情在 `emotes_test.dart`。
- 真实接口：E01.5 的“国内平台完善”匿名跑了两个直播间各 2 分钟：就绪 0.2 s，聊天 14 和 37 条、人数 40 和 39 次（656→650、4977→5046），没有重连；feed 只有 `comment` 一种条目，没有礼物、醒目留言、通知或撤回（E01.5 记录“真实环境检查”）。S02.1 另读过一次房间页的表情表（2026-10-01 共 207 个）。
- 真机：没有单独的真机记录。[S02.1](../../../S-质量和验证/S02-真机验证/S02.1-真机问题修复/record.md) 修了 K90 上用户报的快手标题 U+FFFC 和 `[笑哭]` 显示成文字，但修完没有在 K90 上复看；对应 [真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（快手热门直播间有弹幕、断网后重连）和第 7 条（快手带表情的弹幕在列表里是图片），结果一列还是空的。登记表状态是“完成”。

## 留下的问题

- 主地址超时（而不是拒绝）时每次请求最多等 20 s（3.x 问题 2）：record.md 原来留给直播间定启动超时，现在直播间和多画面的启动超时都是 30 s（`room_controller.dart:100`、`multiview_controller.dart:157`），备用地址有机会接上，已解决，不另开任务；如果真机上仍见快手弹幕“弹幕服务器连接超时”，再看是否把每次请求的超时降到 10 s。
- 礼物、醒目留言：移动端 feed 没有，桌面端 WebSocket 要签名，不做（附录 C-16，E01.5 候选 K-3）。
- 进房的合规公告不显示（附录 C-15，E01.5 候选 K-2，不做：内容固定）。
- 没有名字的评论者叫“快手用户”（`kuaishou.dart:81`），写死的中文，英文界面也是中文（pure_live_TV 用 `danmaku_anonymous_user`）：归 [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md) 的 C 类（弹幕层的中文文字）。
- 时间为 0 或负数的评论仍按 1970 年，会被去重闸门当作过期丢掉（保持 3.x，录制里没有这种值）：没有任务。
- 真机结果还没有：等 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 统一验证或下一次 K90 验证时补第 2 节第 1、7 条。
