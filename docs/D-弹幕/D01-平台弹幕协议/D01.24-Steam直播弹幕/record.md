# D01.24 弹幕（新增）：Steam 直播

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/steambroadcast.dart`
  - `SteamBroadcastDanmakuConnection`：连接（HTTP 轮询，直接继承 `DanmakuConnectionBase`）；
  - `SteamBroadcastDanmakuProtocol`：地址、请求头、`getchatinfo` 和聊天日志回答的解析、失败后的等待，不做 I/O；
  - `SteamBroadcastChat`（一场直播的聊天日志地址模板）、`SteamBroadcastChatWindow`（聊天日志的一次回答）、`SteamBroadcastChatClock`（按聊天日志的时钟算下一次请求的时刻）。
- 参数：`live_core` 的 `SteamBroadcastDanmakuArgs(steamId, broadcastId:)`，E03.14 / E03.14（27-6）已给出：
  - `steamId` 是主播的 64 位 Steam id（房间身份）；`broadcastId` 是进房时 `getbroadcastmpd` 的 `broadcastid`（当前这一场），未开播时进房为空；
  - 只在进房（`getRoomDetail`）时放进 `LiveRoom.danmakuData`，不多发请求；刷新、录制详情、卡片没有；
  - `broadcastId` 为空，或者 Steam 不认它（换场了），连接自己再请求一次 `getbroadcastmpd`（见“连接和时序”）。
- 升级条目：27-6“聊天（只读）”。v3 的 Steam 是 `EmptyDanmaku`，这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/steambroadcast/danmaku/S07-live`（归档 v4 的真实录制，2026-09-27 17:44 UTC，主播 76561199799018508，约 80 s，146 个回答：`getbroadcastmpd`、`getchatinfo`、窗口 0（50 行历史）和之后的 143 个窗口，录制期间没有新消息）。帧没有改，本模块加上 v4 读法的冻结输出 `expected.json` 和生成它的 `danmaku/v4_expected.dart`，没有新录样本。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/steambroadcast.dart`（`SteamBroadcastProtocol`、`SteamBroadcastConnector`）和它的测试；规格 `spec/sites/steambroadcast.md` 第 7 节、第 10 节“聊天越读越落后”；
  - Steam 直播页自己的脚本（2026-09-28 22:46 UTC 下载）：`community.fastly.steamstatic.com/public/javascript/broadcast_chat.js?v=7jUeAoOlKcEN`（聊天，`CBroadcastChat`）和 `broadcast_watch.js?v=90PM3UjdPfln`（直播页，`CBroadcastWatch`），见“网页客户端”；
  - pure_live_TV `e1cca224`：`lib/platforms/steambroadcast/steam_broadcast_site.dart:40` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - `live_core` 的 `SteamBroadcastApi`（E03.14、E03.14）：`mpdUrl`、`roomHeaders`、`broadcast`（`getbroadcastmpd` 的解析）、`isSteamId`、`userAgent`、`link`；
  - 两次只读实测：匿名、直连（本机默认出口），不登录、不发言，见“实测”。

## 做法

- **HTTP 轮询，不用 WebSocket**：Steam 直播的聊天是一份“聊天日志”，按时间窗分段，用普通的 GET 一段一段读（CDN 上的 JSON）。所以和快手（D01.6）、YouTube（D01.20）一样直接继承 `DanmakuConnectionBase`：等待用 `run.delay`，取消挂在 `run.ended` 上。框架没有改。
- **读法照 Steam 网页**：`getchatinfo` 给出聊天日志的地址模板，先读窗口 0（最近的历史，同时给出下一个窗口的时刻和 `initial_delay`），之后每个窗口在“聊天日志的时钟”走到它时才请求（下一节）。这是归档规格 §10 踩过的坑：按固定间隔请求会越读越落后，约 70 s 后旧窗口过期、返回 404。
- **请求照适配器**：`getbroadcastmpd`、`getchatinfo` 用适配器的 JSON 请求头（`SteamBroadcastApi.roomHeaders(json: true)`：3.x 的 Chrome 140 UA、`accept`、`accept-language`、直播页作 `referer`、`x-requested-with`）；聊天日志在另一个主机（`steambroadcastchat.akamaized.net`），用网页跨域请求带的请求头（jQuery 的 JSON `accept`、`origin`、`referer`，没有 `x-requested-with`）。都以 `steambroadcast` 的名义发出（代理路线和限流由应用决定），不跟随跳转，单个请求 10 s（归档 v4）。
- **加入**：窗口 0 回来就算加入，报 `DanmakuReady`。它的 50 行历史不报（同归档 v4：没有时间，放到屏幕上会误导；换回窗口 0 重新对时的时候也不会重复报）。
- **只上报聊天和在线人数**：
  - 聊天行（`msg`）是白色聊天：文字去首尾空白（Steam 表情写作 `ː名字ː`，原样保留），名字 `persona_name`，用户 id `steamid`；平台不给消息 id 和时间，两者都留空；
  - 在线人数：连接自己请求 `getbroadcastmpd` 时（进房没给 `broadcastId`、换场），把它的 `num_viewers` 报成 `onlineViewers`；
  - 聊天日志里没有醒目留言、付费留言、礼物，也没有人数；`joined`、`left`、`muted`、`remove_msgs`（进出、禁言、删除某人的消息）不报。
- **在线人数的来源不变**：列表卡片、`getbroadcastinfo`、`getbroadcastmpd` 本来就给同时观看人数（`audience.dart` 里 Steam 是 `roomList`），接入后没有变，`audience.dart` 不用改。
- **房间公告**：聊天接上了，`live_core` 的 `SteamBroadcastApi.chatNotice` 去掉第一句“Steam 直播的聊天暂时不能在这里显示。”，只留“人数是正在观看的人数。”；3.x 的原文留作 `SteamBroadcastApi.legacyChatNotice`（对照测试断言 3.x 的冻结输出里都是它，也给 J02.1 迁移用）。对照测试里公告本来就列为有意差异，注释补上 D01.24。

## 协议

**请求**：

| 请求 | 地址 | 回答 |
|---|---|---|
| 当前这一场 | `GET https://steamcommunity.com/broadcast/getbroadcastmpd/?broadcastid=0&steamid=<id>&viewertoken=0&sessionid`（`SteamBroadcastApi.mpdUrl`，和进房、录制时的请求逐字相同） | `success`（`ready` 在播）、`broadcastid`、`num_viewers`（读法用平台层的 `SteamBroadcastApi.broadcast`） |
| 聊天日志的地址 | `GET https://steamcommunity.com/broadcast/getchatinfo/?steamid=<id>&broadcastid=<这一场>&viewertoken=0&sessionid`（与录制、归档 v4 相同） | `{"success":1,"chat_id":"…","view_url_template":"https://steambroadcastchat.akamaized.net/chat/<chat_id>/messages/{0}?chat_origin=<聊天服务器>:8071","blocked":false,"moderators_steamid":[]}`。`broadcastid` 不是这位主播当前那一场（0、旧的一场、别人的一场）时回 HTTP 500 `{"success":2}`（实测） |
| 聊天日志的一个窗口 | 模板里第一个 `{0}` 换成窗口的时刻（毫秒，聊天开始以来的时间）；0 是最近的历史 | 见下表 |

**聊天日志的回答**：

| 字段 | 含义 | 本实现 |
|---|---|---|
| `messages` | 这个窗口的聊天行，每行 `steamid`、`instance_id`、`persona_name`、`flair`、`in_game`、`msg` | 聊天（见上）；窗口 0 的是历史，不报。不是对象、`msg` 不是文字或为空白的行跳过；`persona_name` 不是文字时名字为空，`steamid` 是文字或整数 |
| `next_request` | 下一个窗口的时刻 | 必须是正整数（或数字文字），窗口 0 以外必须比这个窗口晚，否则这次回答算失败 |
| `initial_delay` | 到下一个窗口还要等多久（毫秒）；窗口 0 总带着，别的窗口带着时表示重新对时 | 窗口 0：按它对时（没有时当 0）；别的窗口：大于 0 时按它重新对时，这个窗口的聊天照常报 |
| `joined`、`left`、`muted`、`remove_msgs` | 进出聊天、被禁言、删除某人的消息（网页显示成通知或删掉已显示的行） | 不报（已飞出的弹幕收不回来） |

- 只有 `next_request` 给出的那些时刻有窗口：同一日志里别的时刻（下一个窗口 +1 ms、+5 s、+120 s、−30 s……）都是 HTTP 404 的 HTML 页（实测）。请求来早了（窗口还没写出来）也是 404，网页因此每次失败把以后的请求推后 10 ms。
- 状态码：200 以外按适配器的口径变成 `SiteError`（404 `NotFound`、401/403 `RiskControl`、429 `RateLimited`、其他 `NetworkFailure`），短的 JSON 正文写进说明（`getchatinfo: HTTP 500 {"success":2}`）；不是 JSON、不是对象、缺字段是 `ApiChanged`。
- 聊天日志的地址只接受 https、没有用户信息和片段、端口只能是 443，主机是 `steambroadcast*.akamaized.net` 或 Steam 的域名（`steamcommunity.com`、`steamcontent.com`、`steamserver.net`、`steamstatic.com` 及其子域名）；别的是 `ApiChanged`。

**聊天日志的时钟**（`SteamBroadcastChatClock`，照 `broadcast_chat.js` 的 `RequestLoop`）：

- 对时：窗口 0（或带 `initial_delay` 的回答）回来的时刻记为 T，`next_request` 记为 N0；窗口 N0 在 T + `initial_delay` 到期。
- 之后窗口 N 在 T + `initial_delay` + (N − N0) + 推后量 到期；到期前等，已经过了就立即请求（读者落后时一个接一个地补上，直到追上）。每次成功回答的 `next_request` 都比上一个窗口晚，所以不会空转。
- 推后量：每失败一次加 10 ms（网页的 `s_MessageNudgeDelayMS`），整个连接里不清零（同网页），最多 1 s。
- 等待限制在 0～60 s（窗口大约 70 s 后过期）。
- 时间用连接自己的单调时钟（默认一个 `Stopwatch`；测试注入假时钟），与墙上时钟无关。

录制的 143 个窗口：步长 501～637 ms（平均约 548 ms），`next_request` 走过 77.8 s 的同时，回答到达的时刻也走过了 77.8 s（相差 8 ms），即聊天日志的时钟就是真实时间。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网页（`broadcast_chat.js`） | 依据 |
|---|---|---|---|---|
| 当前这一场 | 用进房给的 `broadcastId`；为空时先请求 `getbroadcastmpd` | 每次开始都请求 `getbroadcastmpd` | 直播页的 `getbroadcastmpd`（播放器用的同一个回答）给出 | 27-6：进房已经请求过，不多发（差异 1） |
| 开始 | `getchatinfo`、窗口 0 | 同 | 同 | — |
| 加入（就绪） | 窗口 0 回来时报 `DanmakuReady`；之后每次重新对时成功（窗口 0）再报一次 | 窗口 0 回来时 | — | D01.1 |
| 历史 | 不报 | 不报 | 显示 | 没有时间；弹幕会误导（差异 3） |
| 下一个窗口 | 按聊天日志的时钟（上一节） | 同，但两次请求之间至少 200 ms | 同 | 差异 5 |
| 心跳 | 无（`heartbeatInterval` 为 0，手动 `heartbeat()` 什么也不发） | 无 | 聊天无；直播页另有观看心跳（`POST /broadcast/heartbeat/`，30 s，给视频计数用） | 聊天日志是只读的 CDN 文件 |
| 单个请求 | 10 s | 10 s | 无超时 | — |
| 一次失败 | 500 ms 后重试同一个窗口，推后量 +10 ms，不提示 | 500 ms，推后量 +10 ms；第 1 次失败就把状态改成“重连中” | 500 ms，推后量 +10 ms | 偶尔来早一点的 404 很常见，不该让界面提示断开（差异 6） |
| 连续第 4 次失败 | 报 `DanmakuReconnecting`（一轮只报一次），回到窗口 0 重新对时；它回来时再报 `DanmakuReady` | 回到窗口 0 | 回到窗口 0，显示“Reconnected to chat”；加入前连续 4 次失败则显示“Unable to join chat”并停止 | 网页的 `s_MessageRetryMax` |
| 连续第 8 次失败起 | 重新找这场直播的聊天：`getbroadcastmpd`（主播换了一场就拿到新的 id，已下播就结束）、`getchatinfo`、窗口 0；等待改为 1、2、4、8、8… s | —（第 12 次就结束） | 不会（一直 500 ms 重试、每 4 次对一次时）；换场靠播放器失败后重新请求 `getbroadcastmpd` | 差异 7 |
| 放弃 | 连续第 16 次失败：`DanmakuClosed(reconnectsExhausted)`（约 50 s） | 连续第 12 次失败（约 6 s）；加入前第 3 次失败 | 加入后不放弃 | 与 D01.6、D01.15、D01.20 的量级一致 |
| `getchatinfo` 失败 | 忘掉这个 `broadcastId`，下一次先请求 `getbroadcastmpd`（Steam 对旧的一场回 500） | 终态 | 只记日志 | 差异 2 |
| `getbroadcastmpd` 说不在播 | `unavailable`、`offline`、`not_live`、`no_broadcast`：`DanmakuClosed(connectionFailed, 'Offline')`；`user_restricted`：同，`The account may not broadcast`；`missing_subscription` 且没有 id：同，`Subscribers only`；不发 `getchatinfo` | 除 `ready` 外一律终态 `offline` | — | 重试没有用 |
| `getbroadcastmpd` 没有 id（等待开播 `waiting*` 等） | 算一次失败，按上面的节奏重试 | 终态 `offline` | 播放器按回答的 `retry` 再请求 | 主播可能马上开播 |
| 参数不对 | Steam id 不合规：`DanmakuClosed(connectionFailed, 'Not a Steam id')`，不发请求；`broadcastId` 不是数字或为 0：当作没有 | — | — | — |
| 关闭、换房间 | 取消进行中的请求；之后不发请求、不报事件 | 同 | — | D01.1 |

`connect` 在加入、第一次报 `DanmakuReconnecting` 或结束时完成。

## 网页客户端

`broadcast_chat.js`（`CBroadcastChat`）和 `broadcast_watch.js`（`CBroadcastWatch`）里与聊天有关的部分：

- 直播页先请求 `getbroadcastmpd`（`steamid`、当前的 `broadcastid`、`viewertoken`、`sessionid`、`watchlocation`）；`ready` 时记下 `broadcastid`，调用 `RequestChatInfo(broadcastid)`，同时每 `update_interval`（60 s）请求一次 `getbroadcastinfo` 更新页面上的观看人数，每 `heartbeat_interval`（30 s）发一次观看心跳。播放器下载失败时重新请求 `getbroadcastmpd`，拿到新的 `broadcastid` 就重新 `RequestChatInfo`。
- `RequestChatInfo`：`GET /broadcast/getchatinfo/`（`steamid`、`broadcastid`、`sessionid`），记下 `view_url_template` 和 `chat_id`（后者只用于观众列表和管理），`blocked` 只影响发言框，然后开始 `RequestLoop`。
- `RequestLoop`：
  - 地址是模板里的 `{0}` 换成 `m_nNextChatTS`（模板没有 `{0}` 时改用查询参数 `t`）；
  - 成功：错误计数清零；显示 `messages`（跳过自己发的）、`joined`/`left`/`muted` 通知、按 `remove_msgs` 删掉某人的消息；第一次、`m_nNextChatTS` 为 0 或回答带 `initial_delay`（非 0）时对时：`m_tsFirstRequest = now + initial_delay`，等 `initial_delay`；否则 `next_request` 比当前的小就记日志“Next request in past”并**停止**，不然等 `m_tsFirstRequest + 累计步长 − now + 推后量`（小于 0 按 0）；
  - 失败：计数 +1，推后量 +10 ms；计数到 4 时，还没加入就显示“Unable to join chat”并停止，否则计数清零、标记重连、清空对时；500 ms 后再试。
- 发言、禁言、管理走 WebAPI（要登录），本实现不涉及。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.steamBroadcast: () => SteamBroadcastDanmakuConnection(http: steamHttp),
  // …
});
```

- `http`：应用给 `SteamBroadcastSite` 的同一个 `LiveHttp`。请求以 `steambroadcast` 的名义发出，代理路线和限流按平台 id（`getbroadcastmpd`、`getchatinfo` 在 `steamcommunity.com`，聊天日志在 `steambroadcastchat.akamaized.net`，同一条路线）。
- 不需要 Cookie、账号：全程匿名只读，v3 也没有 Steam 的 Cookie 设置。
- `elapsed` 只给测试用，应用不传。没有 WebSocket，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`；没有参数（刷新、录制详情、卡片）的房间按 D01.1 不连接。

## 与归档 v4 的对照

- 读法的对照：`fixtures/steambroadcast/danmaku/v4_expected.dart` 把归档 v4 的 `SteamChatPoll` 和 `SteamBroadcastProtocol`（除了用不到的 `headers`）原样搬进一个独立程序，只替换它从别处引用的 `DanmakuEvent`、`DanmakuChat` 和 `DecodeContext`。它用 `broadcastId` 读录下的 `getbroadcastmpd`，用 `chatTemplate` 读 `getchatinfo`，用 `parse` 读每个聊天日志的回答（窗口时刻取自回答的地址），写下 v4 的两个请求地址、直播 id、模板，以及每个窗口的地址、下一个窗口、`initial_delay` 和解出的聊天行（投影）。运行：在仓库根目录 `dart run fixtures/steambroadcast/danmaku/v4_expected.dart`，结果在 `S07-live/expected.json`，`generator` 字段写明来源。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| `getbroadcastmpd`、`getchatinfo` 的地址 | 新代码的地址（`SteamBroadcastApi.mpdUrl`、`chatInfoUrl`）与 v4 的、录下的逐字相同 |
| `getbroadcastmpd` 的回答 | 平台层解出的直播 id 与 v4 相同，另有 `num_viewers` 2519 |
| `getchatinfo` 的回答 | 模板与 v4 相同；模板代入窗口时刻得到的就是录下的 144 个地址 |
| 144 个聊天日志的回答 | 逐个一致：下一个窗口、`initial_delay`（只有窗口 0 有，491 ms）、聊天行（窗口 0 的 50 行历史：用户 id、名字、文字；之后的窗口都没有聊天）。v4 的消息 id 是 `steambroadcast:<窗口>:<序号>`，新代码没有 id（差异 8）；录制里没有空名字，所以 v4 的 `Steam` 占位没有出现 |
| 用连接重放录制（参数不带 `broadcastId`） | 请求与录制逐个相同（`getbroadcastmpd`、`getchatinfo`、146 个中的 144 个窗口），最后请求的是最后一个回答给的下一个窗口；报出 2519 人和一次 `DanmakuReady`，历史不报；假时钟下窗口 0 之后等 491 ms，之后每次等的正是聊天日志的步长 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 用进房给的 `broadcastId`，不再先请求 `getbroadcastmpd` | 27-6 的平台层就是为此把 `broadcastId` 放进参数；少一个请求（实测加入 0.5～6 s） |
| 2 | `getchatinfo` 失败时忘掉 id，下一次先请求 `getbroadcastmpd`；连续第 8 次失败起每次都重新找聊天 | 换场后旧 id 会被 `getchatinfo` 拒绝（500），旧的聊天日志 404；这样能跟上主播的下一场，已下播时以 `connectionFailed` 结束。v4 直接进终态 |
| 3 | 历史不报：同 v4 | — |
| 4 | 失败的节奏：前 3 次不提示，第 4 次提示并对时，第 8 次起重新找聊天并退避 1、2、4、8 s，第 16 次放弃（约 50 s） | v4 第 1 次失败就标成“重连中”，第 12 次（约 6 s）就放弃，一次几秒的网络抖动就会让整场直播没有聊天；网页的 404 很常见（它专门为此推后请求），不该每次都提示 |
| 5 | 落后时立即请求，不设 200 ms 的最小间隔；`next_request` 不比当前窗口晚的回答算失败 | 与网页相同：一次请求的往返可能接近甚至超过一个窗口的步长（约 0.55 s；录制时约 0.24 s，实测不复用连接时约 0.75 s），加上最小间隔，读者可能一直追不上，最后读到过期的窗口。v4 用最小间隔防空转；这里改为要求 `next_request` 前进（网页遇到后退会停止整个循环，这里当作失败，交给重试和对时） |
| 6 | 推后量在重新对时后不清零，最多 1 s | 网页不清零（它说明推后是因为这条路径到聊天服务器慢）；v4 在对时时清零。网页没有上限，长时间观看累积的推后会让聊天越来越晚，所以加了上限 |
| 7 | 只有正的 `initial_delay` 才重新对时，这样的回答里的聊天照常报 | 网页的判断是 `rgResponse.initial_delay` 为真（0 不算），并且照常显示这次的消息；v4 对任何带 `initial_delay` 的回答都当作历史，不报其中的聊天 |
| 8 | 消息 id 留空 | 平台不给 id。和 D01.16 一样交给 D01.1 闸门的无 id 规则（同一用户同一文字 2.5 s 内只收一次）；本实现不会重复读同一个窗口，拼出来的 id 没有用处，反而让闸门跳过这条规则 |
| 9 | 名字为空时留空，不写 `Steam` | 占位信息留空的统一原则（E06 平台层升级 的 X-2）；界面名字为空时显示平台名 |
| 10 | 文字只接受字符串，用户 id 接受字符串和整数 | v4 把任何值转成文字（数字、对象也会成为聊天） |
| 11 | 聊天日志地址要求 https 和 Steam 的主机（见“协议”） | v4 只检查 `{0}`；平台回答的地址会被原样请求，带着直播页的 `referer` |
| 12 | 报 `getbroadcastmpd` 的 `num_viewers` | 连接自己请求它时顺便报；v4 不报人数 |
| 13 | 只有下播、账号受限、仅订阅者（且没有 id）才结束；等待开播等没有 id 的状态按失败重试 | v4 对 `ready` 以外的回答一律终态 `offline` |
| 14 | 聊天日志用网页跨域请求的请求头 | v4 所有请求都带 `X-Requested-With`（浏览器跨域时不带）。录制用的是 v4 的请求头，实测用本实现的，两种都能读 |
| 15 | 状态码按适配器的口径变成 `SiteError` | 失败说明与平台层一致；v4 是 `FormatException('HTTP …')` |

没有改的：两个请求的地址、窗口地址的拼法（只换第一个 `{0}`）、500 ms 的重试、10 ms 的推后、第 4 次失败对时、10 s 的请求时限、历史不报、聊天行取的字段，都与 v4 相同。

## 与网页客户端的差异

- 不显示历史（网页显示最近 50 行）。
- 加入前连续失败不会“Unable to join chat”后就停下，加入后也不会无限重试：统一按“连接和时序”的节奏，第 16 次放弃。
- `next_request` 后退时不停止，按失败处理。
- 推后量有 1 s 的上限，等待有 60 s 的上限。
- 不请求 `getbroadcastinfo` 更新人数（网页每 60 s 一次）：见“放到其他模块的部分”。
- 换场：网页靠播放器失败后重新请求 `getbroadcastmpd`；这里靠聊天日志连续失败后重新找聊天（第 8 次失败起）。旧的聊天日志如果一直正常回答空窗口，这里不会自己发现换场（网页的聊天也不会），由 M13 的房间刷新重新 `connect`。

## 实测

只读、匿名、直连（本机默认出口），没有登录，没有发言；输出里只看数量、字段和状态，不记用户的值，结果没有存成样本。

- **2026-09-28 22:40～22:56 UTC**（北京时间 29 日 06:40～06:56），用小脚本和 curl：
  - 录制过的三位主播（S07 的 76561199799018508、S09 的 76561198843011284、S05 的 76561199485215572）一两天后仍在播，`getbroadcastmpd` 给的 `broadcastid` 与录制时相同（全天直播，一场可以持续几天）；S07 那场的 `getchatinfo` 仍给同一个 `chat_id`；
  - `getchatinfo`：正确的 id 回模板；`broadcastid=0`、错一位的 id、别人的一场、未开播账号配某个 id，都是 HTTP 500 `{"success":2}`；
  - 聊天日志：窗口 0 回 50 行历史、`next_request`、`initial_delay`（354、500 ms）；`next_request` 是聊天开始以来的毫秒数（S07 的日志 29.07 小时走了 104,652,955 ms，与真实时间一致）；只有 `next_request` 给出的时刻有回答（`{"messages":[],"next_request":…}`），+1 ms、+5 s、+120 s、−30 s、−65 s、−90 s、−600 s 和随意的时刻都是 404 的 HTML 页；不存在的 `chat_id` 窗口 0 也是 404；回答带 `access-control-allow-origin: *`、`cache-control: no-cache`，浏览器跨域的请求头（`origin`、`referer`）照常回答；
  - 下载了 `broadcast_chat.js`、`broadcast_watch.js`（见“网页客户端”）。
- **2026-09-30 12:23～12:27 UTC**，用本实现（`IoLiveHttp`、默认时序）：`SteamBroadcastSite` 取热门第一页 10 位主播，逐个 `getRoomDetail` 拿参数（都带 `broadcastId`），同时各连 200 s：
  - 都在 0.5～6 s 内加入，没有请求 `getbroadcastmpd`；聊天日志共 2,801 次请求，没有一次 404；
  - 收到 1 行聊天（有用户 id 和名字）——Steam 直播的聊天确实很少（归档规格：前 10 个直播各看 60 s，只有一个出现 3 条）；
  - 一位主播的连接出现连续 4 次请求超时（10 s），报了一次 `DanmakuReconnecting`，随后从窗口 0 重新加入；其余没有重连；关闭后状态都是 `idle`。
  - 此前另一轮（4 位主播各 150 s）：865 次聊天日志请求，没有 404、没有重连、没有聊天。

## 样本

- 没有新录样本，`frames.jsonl` 和 `meta.json` 没有改动。新加的只有 `S07-live/expected.json`（归档 v4 的读法输出）和生成它的 `v4_expected.dart`，里面只有已脱敏的值。
- 逐个字段检查了 `S07-live` 的 146 行（都是 JSON 文本，没有二进制帧）：
  - `getbroadcastmpd` 的 `viewertoken`（本次观看的令牌）录制时已换成合成值（`meta.json` 的 `scrubbed`）；请求地址里的 `viewertoken=0`、空的 `sessionid` 是请求本身的写法；
  - 聊天行（`$.messages[*]`，`scrubbed` 的 `person`）：观众的 `steamid` 不是 `7656119` 开头（合成的 17 位数），名字是随机串，`instance_id` 是随机数；聊天文字是公开的直播间内容，保留；
  - `broadcastid`、`chat_id`、聊天服务器 `broadcastchat7.discovery.steamserver.net:8071`、CDN 主机是服务端的公开信息，主播的 Steam id 是公开信息（同 E03.14 的口径），保留；`moderators_steamid` 为空；
  - 找不到 IP 地址、头像路径、Cookie、会话值。门禁的 `fixture privacy` 通过。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字；`connectionFailed` 的几种说明（`Offline`、`The account may not broadcast`、`Subscribers only`、`Not a Steam id`） | M13（D01.1 的原因表） |
| 主播换了一场：进房详情（或直播间的定时刷新）给出新的 `broadcastId` 时重新 `connect`。本连接在旧日志连续失败时会自己跟上，旧日志一直正常回答时不会 | M13 |
| 直播间里的实时在线人数：网页每 `update_interval`（60 s）请求一次 `getbroadcastinfo` 的 `viewer_count`。本连接只在自己请求 `getbroadcastmpd` 时报人数，不另外轮询；要随时更新时由直播间定时刷新房间（关注刷新就是这两个请求） | M13 |
| Steam 表情 `ː名字ː` 的图片（网页用 `community.fastly.steamstatic.com/economy/emoticon/<名字>`） | A01.1（表情模型现在不含 Steam） |
| 主播本人的消息（网页标成 `Broadcaster`）、`flair`、`in_game` 的显示 | 以后的升级候选（`LiveMessage` 没有对应字段） |
| 房间公告 `steambroadcast_chat_notice` 的翻译 | M13（文字已在平台层改好，见“做法”） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除 |

## 受阻

没有。

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖。`live_core` 只改了本平台的 `steambroadcast_api.dart`（`chatNotice` 的文字、新增 `legacyChatNotice`）和它的两份测试（公告的注释、一条新断言）。

## 测试

`test/sites/steambroadcast_test.dart` 24 个用例，`live_danmaku` 共 987 个，连续跑 3 次全部通过；`live_core` 的 Steam 用例 66 个（E03.14 是 65 个，新增公告一条），`live_core` 共 3522 个全部通过；`bash tools/gate/gate.sh --all` 通过。本文件和 `live_core` 的两份 Steam 测试在时钟 +30 天、+5 年下直接运行（`tools/timeshift` 的方式）都通过，进程正常退出；聊天日志的时刻是它自己的时钟，测试不拿它和墙上时钟比。

连接的等待在一个区域（zone）里立即触发，同时把注入的假时钟往前拨同样的时长，所以时钟相关的断言精确到毫秒，不依赖真实时间。

- 协议 7 个：请求（地址与 v4、录制相同，两组请求头，平台名、不跟随跳转、10 s、取消）；`getchatinfo`（录制的模板和窗口地址，500 `success: 2`、403、404、429、非 JSON、数组、`success` 不是 1、没有模板或 `{0}`，8 种不接受的地址和 7 种接受的地址，只换第一个 `{0}`，`success` 为 `"1"`）；直播 id 的形状；窗口（聊天行的各字段和跳过的行、没有 id 和时间、`next_request` 和 `initial_delay` 的各种形状、404 和其他状态码）；人数消息和 `audience.dart` 仍是 `roomList`；时钟（对时、到期、落后时立即、推后量和上限、60 s 上限、负数、重新对时后推后量保留）；失败后的等待序列。
- 录制 3 个：`getbroadcastmpd` 和 `getchatinfo` 的读法与 v4 一致；144 个聊天日志回答与 v4 的冻结输出逐个一致，窗口首尾相接，日志时钟与到达时间相符；用连接重放整份录制（请求逐个相同、只报人数和一次加入、每次等待等于日志的步长）。
- 连接 14 个：
  - 平台表登记、没有心跳；带进房的 `broadcastId`：只发 `getchatinfo` 和窗口，历史不报，各窗口的聊天按顺序，每次请求往返 100 ms 时的等待（300、400、400、200、400 ms），带 `initial_delay` 的窗口重新对时；落后时立即请求直到追上；
  - 连续 3 次 404 不提示、重试间隔 500 ms、之后的等待多 30 ms；连续第 4 次失败提示重连、回到窗口 0、再次加入；连续第 8 次失败起重新请求 `getbroadcastmpd`，跟上新的一场（新的直播 id 和聊天日志）并报它的人数；
  - 进房给的 id 已过时：`getchatinfo` 500 后请求 `getbroadcastmpd` 再加入；没有 id 或 id 不合规时先请求 `getbroadcastmpd`；下播（两种）、账号受限、仅订阅者以 `connectionFailed` 结束且不发 `getchatinfo`；等待开播和请求超时一直失败：第 4 次提示（此时 `connect` 完成），第 16 次以 `reconnectsExhausted` 结束，等待序列 500 ms × 7、1、2、4、8 × 5 s；成功的回答让计数清零；
  - Steam id 不合规直接结束、不发请求，参数类型不对抛 `ArgumentError`；换房间时取消旧请求，旧房间迟到的回答不会再发请求或报事件，关闭后迟到的回答也不报；
  - 真实的本地服务器：`IoLiveHttp` 发出的请求头（`getchatinfo` 带 `x-requested-with`，聊天日志带 `origin` 和跨域的 `accept`、不带 `x-requested-with`）、一行聊天；结束时关闭服务器（普通 HTTP，没有升级的 WebSocket），直接运行测试文件时进程能退出。
