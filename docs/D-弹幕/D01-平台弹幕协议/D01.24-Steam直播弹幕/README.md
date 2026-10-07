# D01.24 Steam 直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 27-6“聊天（只读）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 Steam 直播没有聊天（`EmptyDanmaku`），这是新增功能，规格来自归档 v4 的实现和录制、Steam 网页的 `broadcast_chat.js`
- 旧编号：M5.23、T06a.24
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`getbroadcastmpd` 和弹幕参数 [E03.14 记录](../../../E-直播平台/E03-海外平台/E03.14-Steam直播/record.md)；下播后重连 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)（B-24）；表情图片的显示 [D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉；详细记录 [record.md](record.md)

## 目标

Steam 直播间能看到聊天（Steam 直播的聊天本来就很少）。照 Steam 网页 `broadcast_chat.js` 的 `RequestLoop` 按“聊天日志的时钟”读，修掉归档 v4 固定间隔请求越读越落后、约 70 s 后读到过期窗口 404、一次几秒的网络抖动就放弃的问题。

## 协议要点

| 项 | 内容 |
|---|---|
| 传输 | HTTP 轮询 CDN 上的“聊天日志”，直接继承 `DanmakuConnectionBase`，没有 socket、没有心跳；请求以 `steambroadcast` 的名义走 `LiveHttp`（代理和限流按平台），不跟随跳转，单个请求 10 s |
| 当前这一场 | 用进房给的 `SteamBroadcastDanmakuArgs.broadcastId`；为空或被 `getchatinfo` 拒绝时（忘掉这个 id）请求 `getbroadcastmpd`（`SteamBroadcastApi.mpdUrl`，顺便把 `num_viewers` 报为在线人数） |
| 日志地址 | `GET https://steamcommunity.com/broadcast/getchatinfo/?steamid=<id>&broadcastid=<这一场>&viewertoken=0&sessionid` → `view_url_template`（`https://steambroadcastchat.akamaized.net/chat/<chat_id>/messages/{0}?chat_origin=…`）；`broadcastid` 不对时 HTTP 500 `{"success":2}`；模板只认 https 和 Steam 的主机（`isChatLog`） |
| 窗口 | 模板的第一个 `{0}` 换成窗口时刻；窗口 0 是最近 50 行历史（不报），回来即就绪；回答的 `next_request` 是下一个窗口、`initial_delay` 是对时；只有 `next_request` 给出的时刻有窗口，别的时刻都是 404 |
| 时钟 | `SteamBroadcastChatClock`：窗口 N 在 T + `initial_delay` + (N − N0) + 推后量 到期（单调时钟），落后就立即请求；每次失败推后 10 ms（上限 1 s）；等待上限 60 s；之后的回答带正的 `initial_delay` 时重新对时 |
| 失败 | 500 ms 后重试同一窗口；连续第 4 次报重连（`DanmakuReconnecting`）并回到窗口 0 对时；第 8 次起重新找这场直播（`getbroadcastmpd` → `getchatinfo` → 窗口 0），等待 1、2、4、8 s；第 16 次以 `reconnectsExhausted` 结束（约 50 s）；任何一次成功回答清零 |
| 下播 | `getbroadcastmpd` 说下播（`Offline`）、账号受限（`The account may not broadcast`）、仅订阅者（`Subscribers only`）：`connectionFailed`，不发 `getchatinfo`；没有直播 id（等待开播等）按失败重试；Steam id 不合规：`connectionFailed`（`Not a Steam id`），不发请求 |
| 消息 | 聊天行 `msg`（`ː名字ː` 表情原样）、`persona_name`、`steamid`，白色，没有消息 id 和时间；`joined`、`left`、`muted`、`remove_msgs` 不报 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `SteamBroadcastSite.getDanmaku() => EmptyDanmaku()`（`core/site/steambroadcast/steam_broadcast_site.dart:40`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `SteamBroadcastDanmakuConnection`（`packages/live_danmaku/lib/src/sites/steambroadcast.dart:360`）：`start`（:377）；一次运行的 `_SteamChat`（:412）：`_step`（:465）读到期的窗口，`_lookUp`（:492）取日志地址，`_currentBroadcast`（:514）读 `getbroadcastmpd`，`_failed`（:533）计数和退避；应用登记在 `apps/pure_live/lib/app/platforms.dart:231`（只传 `LiveHttp`） | 有聊天（已做） |
| 协议 | 无 | `SteamBroadcastDanmakuProtocol`（:133）：请求 10 s、重试 500 ms、第 4 次对时、第 8 次重找、上限 15 次、推后 10 ms 和上限 1 s、等待上限 60 s（:135～161）、`wait`（:165）、`chatInfoUrl`（:183）、`isChatLog`（:220）、`chat`（:231）、`window`（:252）、`message`（:276）；时钟 `SteamBroadcastChatClock`（:65，`sync` :85、`advance` :94、`miss` :102、`resync` :109） | 与归档 v4 对照，有意差异 15 条（record.md） |
| 公告 | 普通房间显示 `steambroadcast_chat_notice`“Steam 远端聊天尚待接入；界面人数来自平台明确返回的当前并发观看数。”（`steam_broadcast_site.dart:97`，`assets/translations/zh.json:1924`） | `SteamBroadcastApi.chatNotice`（`packages/live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart:423`）只留“人数是正在观看的人数。”，3.x 原文留成 `legacyChatNotice`（:427） | 3.x 存下的旧公告导入时清掉（J02.1） |
| 参数和人数 | 无 | `SteamBroadcastDanmakuArgs`（`steambroadcast_api.dart:354`），进房和录制详情给出（`steambroadcast_site.dart:370`）；`audience.dart:218` 仍是 `roomList`，没有累计 | — |

## 结果

- **提交**：3a9914ad8（2026-09-30，本任务的代码）。之后只有 docs v1 改编号时动过注释（c613b73f9、9dfbb424d），行为没有变。
- **和归档 v4 的对照**：`fixtures/steambroadcast/danmaku/v4_expected.dart` 把 v4 的读法搬成独立程序，输出 `S07-live/expected.json`。S07-live（主播 76561199799018508，80 s）的 `getbroadcastmpd`、`getchatinfo` 地址与 v4、录制逐字相同；144 个聊天日志回答逐个一致（窗口 0 的 50 行历史，之后都没有新聊天）；用连接重放时每次等待正是日志的步长（约 548 ms）。
- **实测**：2026-09-28 确认只有 `next_request` 的时刻有窗口、日志时钟就是真实时间、`broadcastid` 不对回 500；2026-09-30 用本实现同时连热门第一页 10 位主播各 200 s：0.5～6 s 加入，2,801 次日志请求没有一次 404，1 行聊天；一个连接连续 4 次超时报了一次重连后从窗口 0 重新加入。
- **样本**：只用归档的 `fixtures/steambroadcast/danmaku/S07-live`，新加冻结输出 `expected.json`。
- **测试**：`packages/live_danmaku/test/sites/steambroadcast_test.dart` 现在 24 个（和做完时一样，没有循环生成的用例）：协议 7、录制 3、连接 14（含本地 HTTP 服务器）；`live_core` 的 Steam 测试 +1（公告，66 个）。

## 验证

- 自动测试：`steambroadcast_test.dart`。请求和请求头、`getchatinfo` 的各种回答和 15 种地址、窗口的各种 `next_request`/`initial_delay`、时钟（对时、到期、落后、推后量和上限、60 s 上限）、失败后的等待序列；录制对照 v4 冻结输出、用连接重放（每次等待等于日志步长）；连接的下播、受限、仅订阅者、第 4 次对时、第 8 次重找、第 16 次结束、关闭时取消请求。等待在 zone 里立即触发、假时钟同步前进，时钟断言精确到毫秒。
- 真实接口：2026-09-28、09-30 跑过（见上面的实测）。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有 Steam。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有 Steam 弹幕的条目；Steam 在国内可能要代理。真机上要看：进一个在播的 Steam 直播间，聊天区“已连接”，有人发言时出现聊天，连续看几分钟不出现反复的重连提示。

## 留下的问题

- 旧日志一直正常回答空窗口时，连接不会自己发现主播换了一场：没有任务。连接在旧日志连续失败第 8 次时会重新找当前这一场；C01.1 的 B-24 只在弹幕连接结束后重连，不会因为详情换了 `broadcastId` 主动重连。实测少见，先不做。
- 直播间里的实时人数只在连接自己请求 `getbroadcastmpd` 时报（开始、重找时）：没有任务。网页每 60 s 请求 `getbroadcastinfo` 的 `viewer_count`，本连接不另外轮询。
- Steam 表情 `ː名字ː` 显示成文字：没有任务。`LiveMessage.emotes`（`packages/live_core/lib/src/live_message.dart:352`）现在只有哔哩哔哩、快手、CHZZK、YouTube 填，飞行弹幕和聊天列表的表情显示 D03.2 已做；要做时在本平台协议层按 `community.fastly.steamstatic.com/economy/emoticon/<名字>` 填 `emotes`。
- 主播本人的消息（网页标成 `Broadcaster`）、`flair`、`in_game` 不显示：没有任务（`LiveMessage` 没有对应字段）。
- 3.x 存下的旧公告：已由 J02.1 处理，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
