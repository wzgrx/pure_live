# D01.15 niconico 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 67dba6d24）
- 类型：平台
- 来源：已批准升级 17-3“评论（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有 niconico 这个平台但没有评论，这是新增功能。后续的 B-11（运营评论、评论限制、节目结束、礼物）是同一升级表附录 B 的条目
- 旧编号：M5.14、T06a.15
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（本平台不用 WebSocket 运行时，直接继承 `DanmakuConnectionBase`，同快手 [D01.6](../D01.6-快手弹幕/README.md)）；座位 `NiconicoSeat`、观看页、弹幕参数 [E03.5](../../../E-直播平台/E03-海外平台/E03.5-niconico/README.md)；通知行和礼物行的显示 [C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)（B-21）；决定 D-017（测试不访问真实平台、样本时间固定）；详细记录 [record.md](record.md)

## 目标

niconico 生放送的评论实时显示（延迟不到 1 s），观众数按平台的口径（累计来场数）随评论实时更新。比归档 v4 修掉了评论晚 16～40 s、把累计来场数当在线、一条坏时间丢掉整个窗口、任何带 scheme 的地址都去请求、第一次开座位失败就放弃 5 个问题。后来（B-11）运营评论、评论限制变化、节目结束显示为系统通知，礼物进聊天列表。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/niconico.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 结构 | `NiconicoDanmakuConnection`（:718）直接继承 `DanmakuConnectionBase`，每次 `start` 建一个 `_NiconicoComments`（:779）。座位的 WebSocket 由 `live_core` 的 `NiconicoSeat`（E03.5）负责，评论服务器是 HTTP，框架的 `LiveSocket` 用不上；没有心跳，座位自己保活 |
| 座位 | `NiconicoSite.openSeat(roomId)`（:822）读观看页、按平台代理开座位，等 `seat` 和 `stream`（启动最多 20 s，`NiconicoSite.seatStartupTimeout`）；然后每 100 ms（`messageServerPoll` :475）看一次座位给的 `messageServer.viewUri`，最多 10 s（`messageServerTimeout` :472，`_messageServer` :946） |
| 地址检查 | `view` 和窗口地址只认 https 的 `nicovideo.jp` 及子域，没有凭据、端口、片段（`isCommentServer` :519）；座位给的 `view` 地址不合格时换座位（:910～912），窗口地址不合格的条目跳过；请求以 `niconico` 的名义经 `LiveHttp` 发出，带 `NiconicoApi.headers`（`referer`、UA `Mozilla/5.0`）和 `origin: https://live.nicovideo.jp`（`headers` :468、`request` :531），不跟随跳转；地址路径带令牌，诊断文字里不写地址 |
| 流式读取 | `LiveHttp.open` 边收边切“varint 长度 + protobuf”（`delimited` :543、`NiconicoDelimitedReader` :258）：长度前缀最多 10 字节，单条最多 1 MiB（`maxMessageBytes` :505），超过或在消息中间结束算这个回答失败（已报的不收回），单条解不开只跳过这一条 |
| `view` | 从 `view?at=now` 开始（:925，超时 20 s `firstViewTimeout` :478），立刻给 `next`；`view?at=<next>` 先给 `backward`、`previous`、进行中的 `segment`，之后每个新窗口在开始前约 6 s 给出，最后给 `next`，一个回答约 30 s（超时 60 s 按间隔计，`viewTimeout` :483）；条目是 oneof，以最后一个字段为准（`viewEntry` :564）；只读 `segment`，`previous`、`backward` 不读 |
| 窗口 | 每个 `segment` 开一个窗口请求（`_open` :993、`_window` :1005），同一座位按地址去重，记住最近 64 个（`rememberedWindows` :511），同时最多 8 个（`maxOpenWindows` :508，通常 2～3 个）；超时是“剩余时间（0～60 s）+ 20 s”，按间隔计（`windowTimeout` :496、`windowGrace` :487、`maxWindowLeft` :492）；窗口先给出已有的消息和 `Flushed`，之后每条一发出就到 |
| 就绪 | 第一个 `view` 条目（`_joined` :892，同时清零失败次数）；实测从详情到就绪 3.6～3.8 s；每次恢复后再报一次 |
| 聊天 | 窗口的 `ChunkedMessage`：`message.1 chat` 和 `message.20 overflowed_chat` 都是聊天（`_chat` :628）：文字 `content` 去首尾空白，空的不报；名字 `name`（匿名评论为空）；用户 id `hashed_user_id`，为空时用 `raw_user_id`；消息 id `meta.id`（不加前缀）；时间 `meta.at`（秒 + 纳秒，`time` :601，越界只让这一条没有时间）；颜色按 `modifier` 的 `named_color`（20 色表 `namedColors` :647）或 `full_color`（`color` :673），没有时白色；位置、大小、字体、透明度不读 |
| 观众数 | `state.statistics.viewers` 是累计来场数（和观看页的 `watchCount`、座位的 `statistics.viewers` 同一个数），报 `totalViewers`，只在数值变化时报（`_lastViewers` :793、:1041～1042） |
| B-11 运营评论 | `state.marquee.display.operator_comment` → 系统通知（`_operatorComment` :420）：文字 `content`，名字 `name`，颜色按 `modifier`；撤下、文字为空的不报；链接不带 |
| B-11 评论限制 | `state.comment_lock` 只在变化时报系统通知（`commentLockOf` :399、`NiconicoCommentLock` :120，由 `NiconicoMessageReader` :181 按连接记住，初始“不限”）：仅关注者照网页日文原文（关注时长 `followDuration` :360 写成 `2日`、`1時間30分` 等），锁定“現在コメントできません”（:344），解除锁定“评论锁定已解除”（:348，网页没有这句，是拼的），解除关注限制“フォロワー限定コメントが解除されました”（:351） |
| B-11 节目结束 | `state.program_status` 为 Ended → 系统通知“この番組は終了しました”（`programEndedNotice` :340、`programEnded` :384）；座位的 `END_PROGRAM` 和窗口的结束谁先到都算，通知只报一次（`_endsProgram` :856～864）；随后不报重连、不计失败，立刻重读观看页开新座位：主播已开下一场就跟过去，不在播（或受限、不存在）以 `connectionFailed` 结束 |
| B-11 礼物 | `message.8 gift` → 礼物（`_gift` :440、`NiconicoGift` :80：`itemId`、`name`、`point`、`message`、`contributionRank`），文字照网页那一行 `【ギフト貢献N位】<赠送者>さんがギフト「<礼物>（<点数>pt）」を贈りました`（没有名次时没有前缀）；点数为负、`item_id` 和 `item_name` 都空的不报 |
| 不报的 | ニコニ広告（`message.9`）、来场和排名通知（`message.7`、`message.23`）、合作直播转发的评论（`forwarded_chat`）、标签、主持人、NG 设置、游戏、信号等 |
| 失败 | 窗口失败只丢这个窗口；`view` 回 4xx（`_Refused`）换座位，其他失败（传输、5xx、没有 `next`）在同一座位重问同一个 `at`（`_read` :902～942）；座位结束（断开、90 s 无消息、`error`）换座位；打不开、不能看（`StreamUnavailable`、`NeedsLogin`、`RegionBlocked`、`NotFound`，`_unwatchable` :868）以 `connectionFailed` 结束；连续失败按 1、2、4、8、8… s 退避（`backoff` :515），第一次报 `DanmakuReconnecting`，超过 8 次（`maxFailures` :502）以 `reconnectsExhausted` 结束（`_failed` :874～889） |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/...`） | 现在 | 要做到 |
|---|---|---|---|
| 评论 | 3.x 有 niconico 这个平台但没有评论：`NiconicoSite.getDanmaku() => EmptyDanmaku()`（`lib/core/site/niconico/niconico_site.dart:52`），直播间只提示一次 `remote_danmaku_not_integrated`（`lib/modules/live_play/controllers/danmaku_controller.dart:146～150`）；官方节目的公告 `niconico_program_scope` 写着“……；弹幕暂未接入。”（`assets/translations/zh.json:674`，`niconico_site.dart:154`） | `NiconicoDanmakuConnection`（`niconico.dart:718`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:221`（传应用的 `NiconicoSite`）；公告改由 `NiconicoApi.noticeText`（`packages/live_core/lib/src/sites/niconico/niconico_api.dart:423～429`）给出，去掉了“；弹幕暂未接入” | 实时评论（已做） |
| 观众数 | 观看页的 `watchCount`（累计），人数设置页说明“watchCount 是节目累计观看，与并发在线人数分开显示”（`assets/translations/zh.json:1600`） | 评论服务器的 `statistics.viewers` 是同一个累计数，报 `totalViewers`，直播间实时更新；`audience.dart` 没有改 | 口径不变，实时更新（已做） |
| 通知、礼物 | 无 | 直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:904～910`：通知行、礼物行（受“在聊天列表显示礼物”开关控制） | 已做 |

## 结果

- **提交**：67dba6d24（2026-09-29，首次实现：座位、流式读评论服务器、聊天、观众数、公告）；6c5ded04c（2026-10-01，B-11：运营评论、评论限制、节目结束、礼物，`live_core` 加 `NiconicoApi.isProgramEnd`）。
- **和归档 v4 的对照**：`fixtures/niconico/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序，对 S07 写下冻结输出 `expected.json`。S07-live（节目 lv351482215，75 s）3 个 `view` 回答的窗口、已结束窗口和 `next` 一致；4 个窗口的 15 条聊天和 30 个观众数一致（v4 标成在线，新代码是累计，去重后 17 个）；新代码的 `view` 请求与录下的 3 个地址逐字相同；录下的 7 个回答按 1、2、3、5、7、64、1000 字节切开都解出同样的消息。
- **有意差异**（record.md“与归档 v4 的差异”18 条）：id 不加 `niconico:` 前缀；观众数报累计、只在变化时报；流式读取；`overflowed_chat` 也是聊天；评论带颜色；没有时间的消息照报、时间越界只让这一条没有时间；`hashed_user_id` 空串时用 `raw_user_id`；地址只认 https 的 `nicovideo.jp`；长度前缀和单条上限；退避 1、2、4、8 s、第 9 次结束、第一次开座位失败也重试；4xx 立刻换座位；节目结束后跟到下一场；结束原因用 D01.1 的类型；窗口超时按间隔计；同时最多 8 个窗口；座位用 E03.5 的 `NiconicoSeat`。
- **公告**：`NiconicoApi.noticeText['niconico_program_scope']` 去掉“；弹幕暂未接入”，`live_core` 的测试同步（与 v3 冻结输出比较的改用常量 `_v3ProgramScope`）。
- **样本**：`fixtures/niconico/danmaku/` 下 S07-live（归档录制）、S08-marquee（lv351501141 约 285 s，4 条运营评论）、S09-ended（lv351501491 结束前后约 127 s，座位 `disconnect` 和窗口的 `program_status`）、S10-gift（连录约 16 分钟才出现的 1 条礼物）；连接测试回放 `fixtures/niconico/seat/S04-seat` 的座位。
- **测试**：`packages/live_danmaku/test/sites/niconico_test.dart` 现在 49 个用例（没有循环生成的）；首次实现时 34 个（做过 16 种变异），B-11 后 49 个（+15）；`live_core` 的 `niconico_api_test.dart` 为 `isProgramEnd` 加 1 个。

## 验证

- 自动测试：`niconico_test.dart`——协议 6 个（请求头、时限、退避、地址检查、录下的回答切片、长度前缀的边界）、录制对照 v4 4 个、合成条目和消息 6 个（`view` 条目、聊天各字段、20 种颜色、观众数、时间越界）、连接 18 个（用 S04 座位和 S07 回答回放：`at` 序列、4 个窗口各读一次、15 条聊天和 17 个观众数；窗口失败只丢窗口；`view` 503 和超时同座位重试、403 换座位；不能看的房间开始即结束；失败 9 次结束；关闭和换房间；经 `IoLiveHttp` 从本地服务器流式读一个窗口），B-11 15 个（S08、S09、S10 录制，运营评论、评论限制 15 步序列、关注时长写法、节目结束和字段顺序、座位结束后跟到下一场或结束）。窗口超时用的“现在”固定成 S07 的录制时间。
- 真实接口：2026-09-28（UTC 21:19～21:35）匿名、经本机代理（本机直连 TLS 失败）：user/52553742 90 s，详情后 3.8 s 就绪，112 条聊天（8 条有名字）、38 个观众数，没有重连；同一房间 180 s，3.6 s 就绪，193 条聊天，第 20 条以后每条延迟都不到 1 s。2026-09-30（UTC 15:22～15:56）补录 S08、S09、S10。没实测到的：评论限制（评论最多的 120 个在播节目都没开）、礼物的附言和名次、运营评论的名字、颜色和链接，用合成用例。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节没有 niconico，第 4 节第 10 条（F-FAV-08）只看旧关注的迁移，不看评论；[E03.5](../../../E-直播平台/E03-海外平台/E03.5-niconico/README.md) 写着“没有在 K90 上专门看过；要用户开着代理”。登记表是“完成”，按 D-029 这个平台的弹幕还算“没验证”。

## 留下的问题

- 每个直播间多占一个座位（播放一个、评论一个，record.md 候选 5）；匿名座位的连接数上限没测，`TOO_MANY_CONNECTIONS` 按普通失败退避：没有任务，要做时归 G 组播放（共用座位）。
- 刚连上时当前窗口已有的评论（最多 16 s）一起到，之后才是实时的：平台的窗口机制，没有任务。
- 评论的位置（`ue` 顶部、`shita` 底部）、大小、字体不支持（record.md 候选 1）：`LiveMessage` 没有这些字段，要先在 `live_core` 加字段再改飞行弹幕，没有任务。
- 合作直播转发的评论（`forwarded_chat`，候选 4）不显示：要来源标记，没有任务。
- 进房前已有的评论限制不提示（不读状态快照），只报之后的变化：多一个请求换一行，B-11 时决定不做。
- 网页在评论锁定期间不显示聊天，这里照报：没有任务，要不要照做由直播间（C01）决定。
- 运营评论在网页上置顶显示 `duration` 秒、可带链接，这里只是一行通知：`LiveMessage` 没有这些字段，没有任务。
- 应用翻译文件里还留着 3.x 的 `niconico_program_scope`（`apps/pure_live/assets/translations/zh.json:1121`、`en.json:1122`，带“；弹幕暂未接入”），应用代码没有用到这个键（公告由 `NiconicoApi.noticeText` 给出），界面不会显示：按 D-024 这次不清理翻译键，没有任务。
- 真机上没看过（要用户开代理：评论实时、颜色、观众数、节目结束通知）：没有单独的任务，建议加进真机清单第 2 节，归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类的补验。
