# D01.15 niconico 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 17-3“评论（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有 niconico 评论，这是新增功能
- 旧编号：M5.14、T06a.15
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；座位 `NiconicoSeat`、观看页、弹幕参数 [E03.5 记录](../../../E-直播平台/E03-海外平台/E03.5-niconico/record.md)；B-11 的运营评论、评论限制、节目结束通知在直播间聊天里显示为通知行（C01.1）；详细记录 [record.md](record.md)

## 目标

niconico 生放送的评论实时显示（延迟不到 1 s），观众数按平台的口径（累计来场数）更新；比归档 v4 修掉了评论晚 16～40 s、把累计当在线、一条坏时间丢掉整个窗口、第一次开座位失败就放弃等问题。后来（B-11）运营评论、评论限制、节目结束显示为通知，礼物上报。

## 协议要点

| 项 | 内容 |
|---|---|
| 结构 | 不用 WebSocket 运行时，直接继承 `DanmakuConnectionBase`：先用 `NiconicoSite.openSeat(roomId)` 开一个座位（E03.5，读观看页、开座位 WebSocket、等 `seat` 和 `stream`），座位给出 `messageServer.viewUri`（每 100 ms 查一次，最多 10 s），之后评论走 HTTP |
| 评论服务器 | 流式读（`LiveHttp.open`）“varint 长度 + protobuf”的序列：`view?at=now` 立刻给 `next`；`view?at=<next>` 给 `segment`（进行中的 16 s 窗口，提前约 6 s）、`previous`、`backward` 和下一个 `next`，一个回答约 30 s；每个 `segment` 开一个窗口请求（同时最多 8 个，按地址去重） |
| 地址检查 | `view` 和窗口地址只认 https 的 `nicovideo.jp` 及子域；请求头 `origin: https://live.nicovideo.jp`、`referer`、UA；不跟随跳转；诊断不写地址（路径带令牌） |
| 就绪 | 第一个 `view` 条目（实测从详情到就绪 3.6～3.8 s） |
| 消息 | 窗口的 `ChunkedMessage`：`chat` 和 `overflowed_chat` → 聊天（`content`、`name`、`hashed_user_id` 为空时 `raw_user_id`、id `meta.id`、时间 `meta.at`、颜色按 `modifier` 的 20 色表或完整颜色）；`state.statistics.viewers` → `totalViewers`（累计来场，只在变化时报） |
| B-11 | 运营评论（`state.marquee`）、评论限制变化（`comment_lock`，文字照网页的日文）、节目结束（`program_status` Ended → “この番組は終了しました”）→ 系统通知；`gift` → 礼物（`NiconicoGift`，文字照网页那一行）；广告、来场、排名通知不报 |
| 失败 | 窗口失败只丢这个窗口；`view` 4xx 换座位，其他在同一座位重问同一个 `at`；座位结束（节目结束、断开、90 s 无消息）换座位并重读观看页，主播开了下一场就跟过去，不在播就 `connectionFailed`；连续失败 1、2、4、8、8… s 退避，第 9 次 `reconnectsExhausted` |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 评论 | `NiconicoSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/niconico/niconico_site.dart:52`），公告写着“弹幕暂未接入” | `NiconicoDanmakuConnection`（`packages/live_danmaku/lib/src/sites/niconico.dart:718`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:221`（传 `NiconicoSite`）；公告去掉了“；弹幕暂未接入” | 实时评论（已做） |
| 协议 | 无 | `NiconicoDanmakuProtocol`（:337）：时限 :472～492、单条 1 MiB（:505）、退避（:515）、流式切分 `delimited`（:543）；`NiconicoDelimitedReader`（:258）、`NiconicoMessageReader`（:181，记住评论限制）；节目结束文字（:340） | 与归档 v4 对照，有意差异 18 条 |
| 观众数 | 观看页的 `watchCount`（累计，`audience_niconico_detail` 的说明） | 评论服务器的 `statistics.viewers` 是同一个累计数，报 `totalViewers` | 口径不变，实时更新 |

## 结果

- **提交**：67dba6d24（2026-09-29，M5.14），6c5ded04c（2026-10-01，B-11）。
- **和归档 v4 的对照**：`fixtures/niconico/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序。S07-live（节目 lv351482215，75 s）3 个 `view` 回答、4 个窗口的 15 条聊天和 30 个观众数一致（v4 标成在线、新代码是累计并去重成 17 个）；请求地址与录制逐字相同；录下的回答按 1～1000 字节切片都解出同样的消息。
- **实测**（2026-09-28 匿名经本机代理；直连 TLS 在本机失败）：本实现进 user/52553742 详情后 3.8 s 就绪，90 s 112 条聊天、38 个观众数；180 s 193 条聊天，第 20 条以后每条延迟都不到 1 s。2026-09-30 补录 S08-marquee（4 条运营评论）、S09-ended（节目结束前后）、S10-gift（16 分钟才录到 1 条礼物）。
- **公告**：`NiconicoApi.noticeText['niconico_program_scope']` 去掉“；弹幕暂未接入”（`live_core` 测试同步）。
- **测试**：`packages/live_danmaku/test/sites/niconico_test.dart` 做完时 34 个（另做过 16 种变异），B-11 后 49 个；`live_core` 的 `niconico_api_test.dart` +1（`isProgramEnd`）。

## 验证

- 自动测试：`niconico_test.dart`（用 S04 座位和 S07 回答回放；经 `IoLiveHttp` 从本地服务器流式读取窗口）。
- 真实接口：见上面的实测。没实测到的：评论限制（120 个在播节目都没开）、礼物的附言和名次、运营评论的名字颜色链接。
- 真机：没有；海外平台要代理。

## 留下的问题

- 每个直播间多占一个座位（播放一个、评论一个）；匿名座位的连接数上限没测，`TOO_MANY_CONNECTIONS` 按普通失败退避。共用座位是候选 5，归 G 组。
- 刚连上时当前窗口已有的评论（最多 16 s）一起到。
- 评论的位置（顶部、底部）、大小、字体不支持（`LiveMessage` 没有这些字段，候选 1，归 A 组）；合作直播转发的评论（`forwarded_chat`）不显示（候选 4）。
- 进房前已有的评论限制不提示（不读状态快照），只报之后的变化。
- 网页在评论锁定期间不显示聊天，这里照报。
