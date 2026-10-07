# D01.24 Steam 直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 27-6“聊天（只读）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 Steam 直播没有聊天，这是新增功能
- 旧编号：M5.23、T06a.24
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`getbroadcastmpd` 和弹幕参数 [E03.14 记录](../../../E-直播平台/E03-海外平台/E03.14-Steam直播/record.md)；详细记录 [record.md](record.md)

## 目标

Steam 直播间能看到聊天（Steam 直播的聊天本来就很少）。照 Steam 网页 `broadcast_chat.js` 的 `RequestLoop` 按“聊天日志的时钟”读，修掉归档 v4 固定间隔请求越读越落后、约 70 s 后读到过期窗口 404、一次几秒的网络抖动就放弃的问题。

## 协议要点

| 项 | 内容 |
|---|---|
| 传输 | HTTP 轮询 CDN 上的“聊天日志”，直接继承 `DanmakuConnectionBase`；请求以 `steambroadcast` 的名义走 `LiveHttp`，不跟随跳转，单个请求 10 s |
| 当前这一场 | 用进房给的 `SteamBroadcastDanmakuArgs.broadcastId`；为空或被 `getchatinfo` 拒绝时请求 `getbroadcastmpd`（`SteamBroadcastApi.mpdUrl`，顺便报 `num_viewers` 为在线人数） |
| 日志地址 | `GET https://steamcommunity.com/broadcast/getchatinfo/?steamid=<id>&broadcastid=<这一场>&viewertoken=0&sessionid` → `view_url_template`（`https://steambroadcastchat.akamaized.net/chat/<chat_id>/messages/{0}?chat_origin=…`）；`broadcastid` 不对时 HTTP 500 `{"success":2}`；地址只认 https 和 Steam 的主机 |
| 窗口 | 模板的 `{0}` 换成窗口时刻；窗口 0 是最近 50 行历史（不报），回来即就绪；回答的 `next_request` 是下一个窗口、`initial_delay` 是对时；只有 `next_request` 给出的时刻有窗口，别的时刻都是 404 |
| 时钟 | `SteamBroadcastChatClock`：窗口 N 在 T + `initial_delay` + (N − N0) + 推后量 到期（单调时钟），落后就立即请求；每次失败推后 10 ms（上限 1 s）；等待上限 60 s |
| 失败 | 500 ms 后重试同一窗口；连续第 4 次报重连并回到窗口 0 对时；第 8 次起重新找这场直播（`getbroadcastmpd` → `getchatinfo` → 窗口 0），等待 1、2、4、8 s；第 16 次 `reconnectsExhausted`（约 50 s） |
| 下播 | `getbroadcastmpd` 说下播、账号受限、仅订阅者：`connectionFailed`（`Offline` 等），不发 `getchatinfo`；等待开播按失败重试 |
| 消息 | 聊天行 `msg`（`ː名字ː` 表情原样）、`persona_name`、`steamid`，白色，没有消息 id 和时间；`joined`、`left`、`muted`、`remove_msgs` 不报 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `SteamBroadcastSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/steambroadcast/steam_broadcast_site.dart:40`），公告“Steam 直播的聊天暂时不能在这里显示。……” | `SteamBroadcastDanmakuConnection`（`packages/live_danmaku/lib/src/sites/steambroadcast.dart:360`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:231`（只传 `LiveHttp`） | 有聊天（已做） |
| 协议 | 无 | `SteamBroadcastDanmakuProtocol`（:133）：请求 10 s、重试 500 ms、第 4 次对时、第 8 次重找、上限 15 次后放弃、推后 10 ms 和上限 1 s、等待上限 60 s（:135～161）、`chatInfoUrl`（:183）；时钟 `SteamBroadcastChatClock`（:65） | 与归档 v4 对照，有意差异 15 条 |
| 公告 | 说看不到聊天 | `SteamBroadcastApi.chatNotice` 只留“人数是正在观看的人数。”，3.x 原文留成 `legacyChatNotice` | — |

## 结果

- **提交**：3a9914ad8（2026-09-30，M5.23）。之后没有改动。
- **和归档 v4 的对照**：`fixtures/steambroadcast/danmaku/v4_expected.dart` 把 v4 的读法搬成独立程序。S07-live（主播 76561199799018508，80 s）的 `getbroadcastmpd`、`getchatinfo` 地址与 v4、录制逐字相同；144 个聊天日志回答逐个一致（窗口 0 的 50 行历史，之后都没有新聊天）；用连接重放时每次等待正是日志的步长（约 548 ms）。
- **实测**：2026-09-28 确认只有 `next_request` 的时刻有窗口、日志时钟就是真实时间、`broadcastid` 不对回 500；2026-09-30 用本实现同时连热门第一页 10 位主播各 200 s：0.5～6 s 加入，2,801 次日志请求没有一次 404，1 行聊天；一个连接连续 4 次超时报了一次重连后从窗口 0 重新加入。
- **样本**：只用归档的 `fixtures/steambroadcast/danmaku/S07-live`，新加冻结输出 `expected.json`。
- **测试**：`packages/live_danmaku/test/sites/steambroadcast_test.dart` 24 个（协议 7、录制 3、连接 14，含本地 HTTP 服务器）；`live_core` 的 Steam 测试 +1（公告）。

## 验证

- 自动测试：`steambroadcast_test.dart`（等待在 zone 里立即触发、假时钟同步前进，时钟断言精确到毫秒）。
- 真实接口：见上面的实测。
- 真机：没有单独的真机记录；Steam 在国内可能要代理。真机上要看：进一个在播的 Steam 直播间，聊天区“已连接”，有人发言时出现聊天，连续看几分钟不出现反复的重连提示。

## 留下的问题

- 旧日志一直正常回答空窗口时，连接不会自己发现主播换了一场；要直播间刷新给出新的 `broadcastId` 后重新连接（C01.1 的 B-24 只在连接结束后重连）。
- 直播间里的实时人数只在连接自己请求 `getbroadcastmpd` 时报（网页每 60 s 请求 `getbroadcastinfo`）。
- Steam 表情 `ː名字ː` 显示成文字，图片（`community.fastly.steamstatic.com/economy/emoticon/<名字>`）没做，表情模型不含 Steam。
- 主播本人的消息、`flair`、`in_game` 不显示（`LiveMessage` 没有对应字段）。
