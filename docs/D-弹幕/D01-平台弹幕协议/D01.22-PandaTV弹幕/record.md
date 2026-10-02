# D01.22 弹幕（新增）：PandaTV

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/pandalive.dart`
  - `PandaLiveDanmakuConnection`：连接；
  - `PandaLiveDanmakuProtocol`：地址、握手请求头、命令、取令牌的请求和回答的解析、令牌到期时间、参数检查、帧的解码，不做 I/O；
  - `PandaLiveDanmakuFrame`（一帧解出的内容）、`PandaLiveChatRefusal`（`live/play` 拒绝）。
- 参数：`live_core` 的 `PandaLiveDanmakuArgs(userId, channel, token)`，E03.12（25-2）已给出。
  - 进房（`getRoomDetail`）和录制详情在 `live/play` 接受且在播时放进 `LiveRoom.danmakuData`：`channel` 是回答的 `channel`（不是数字时用主播编号），`token` 是它的聊天令牌（约 30 分钟），`userId` 用来重新调用 `live/play` 取新令牌；不多发请求。被拒绝（成人、密码、粉丝专属、已下播）、未开播、关注刷新都没有参数。
  - 聊天服务器地址 `PandaLiveApi.chatServer`（`wss://chat-ws.neolive.kr/connection/websocket`）、`live/play` 的表单 `PandaLiveApi.playForm`、房间页 `PandaLiveApi.roomUrl` 都用平台层已有的。
  - 本模块没有改 `live_core`。
- 升级条目：25-2“PandaTV 弹幕”。v3 没有 PandaTV 聊天（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/pandalive/danmaku/S07-live`（归档 v4 的真实录制，2026-09-27 19:14 UTC，主播 `daisy00`，约 152 s，36 行：开始时的 `live/play` 回答、客户端发的 connect、subscribe 和 6 个 ping、服务端的 2 个回复和 6 个 ping 回复、18 条聊天、1 个 `MediaUpdate`、1 个 `Recommend`）。帧没有改，本模块加上 v4 的冻结输出 `expected.json` 和生成它的 `danmaku/v4_expected.dart`，没有新录样本。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/pandalive.dart`（`PandaliveProtocol`、`PandaliveConnector`）和它的运行时 `runtime/socket_connector.dart`；规格 `spec/sites/pandalive.md` 第 7 节（来自网页脚本 centrifuge-js 2.x 和 2026-09-27 实测）；
  - pure_live_TV `e1cca224`：`lib/platforms/pandalive/pandalive_site.dart:39` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 2026-09-28 22:12～22:50 UTC（北京时间 29 日 06:12～06:50）的只读实测：匿名、直连、不登录、不发言，见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码只写这几样：
  - `target`：检查参数，给出聊天服务器和握手请求头；
  - `onOpen`：发 connect 和 subscribe；
  - `onData`：解一帧；subscribe 的回复到了才就绪（`session.ready()`）；
  - `heartbeatFrame`：命令 7 的 ping，id 在每个 socket 上从 3 往上数。
  - 换地址、退避、最多 8 次、无消息检测、加入超时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **令牌只在需要时取，取的请求放在握手里**（同 D01.12 TwitCasting 的做法，框架没有改：`connector` 参数本来就允许替换握手）：
  - 第一次握手用进房带来的令牌，不发请求；令牌是 JWT，读得出到期时间（`exp`）且一分钟内就到期时不用；
  - 其余每次握手（重连、换 socket）都先 POST `live/play` 取新的令牌和频道，再握手，和网页每次进房一样；取到的令牌只要还没发出去（握手失败了），下次握手接着用，不再请求；
  - `live/play` 的请求就是进房发的那个（同样的地址、表单、请求头、不跟随跳转，以 `pandalive` 的名义发出，走本平台的代理设置），超时同握手（10 s），一次 `connect` 里的请求绑定一个 `CancelToken`，`close` 或换房间时取消；
  - 请求失败（网络错误、状态码、回答看不懂、没有令牌）当作这次握手失败，走框架的退避和 8 次上限；`live/play` 拒绝（`result: false`，如已下播 `castEnd`、成人 `needAdult`；或接受但 `media.isLive` 为假）说明这场直播的聊天进不去了，以 `DanmakuClosed(connectionFailed, 'live/play: <代码>')` 结束。
- **令牌到期前悄悄换 socket**：connect 的回复带 `expires: true` 和 `ttl`（约 1798 s），服务端在 `ttl` 之后约 25 s 断开这个连接（实测：关闭码 3005 `expired`）。本实现在 `ttl` 前 60 s 先取新令牌，再用框架的 `session.reopen` 换一个新 socket：不报 `DanmakuReconnecting`，也不再报一次 `DanmakuReady`（房间一直算已加入），只有换 socket 的零点几秒里可能漏几条。新 socket 8 s 内没有加入成功就按普通断线重连。取令牌失败就不换，等服务端到时断开，重连时再取；被拒绝就结束。
- **加入被拒就换令牌重连**：connect 或 subscribe 的回复带 `error`（令牌无效、过期、没有权限）时重连，下次握手自然取新令牌；连续第 4 次被拒以 `DanmakuClosed(connectionFailed, 'Chat refused: …')` 结束，加入成功一次就重新计数（次数同归档 v4 的 `maxRejections`；v4 从不清零，见差异 2）。收到拒绝也算收到消息，框架的 8 次上限管不到这种循环，所以要自己计数。
- **不需要保留请求头大小写**：实测不带 `Origin`、UA 也能握手，用默认的 `dart:io` 握手，不用 `connectExactWebSocket`。请求头照归档 v4 和录制带 `Origin: https://www.pandalive.co.kr` 和平台层的 Chrome 140 UA。
- **只上报聊天**（`bj`、`chatter`、`manager`、`support`）。平台的聊天流里没有醒目留言、付费留言，也没有在线人数；礼物（`SponCoin`、`ItemCoin`）、推荐、点赞收藏、入场、房间状态都不报（和 D01.2～D01.16 的范围一致，见差异 7）。
- **在线人数的来源不变**：聊天流里没有观看人数（网页另外轮询 `cache-api` 的 `channel_user_count`，归档规格 §7.3），`audience.dart` 里 PandaTV 一项（列表里有在线人数，另有累计观看，T02.U 25-3）不用改。

## 协议

socket（Centrifugo 3.1.1，JSON 协议）：

| 项目 | 内容 |
|---|---|
| 地址 | `wss://chat-ws.neolive.kr/connection/websocket`（网页配置的 `newChat.node`，`PandaLiveApi.chatServer`）。`live/play` 回答里的 `chatServer` 是 `{url: "", t, token}`，地址为空，不用 |
| 握手 | 请求头 `Origin`、`User-Agent`（见上）；不带也能连（实测） |
| 令牌 | `live/play` 的 `token`：HS256 JWT，载荷是 `sub`（12 字的游客会话）、`exp`（签发 + 1800 s）、`info`（`channel`、`iat`、调用方地址 `ip` 等）、`etc`；同一回答的 `channel` 是主播编号（和 `media.userIdx` 相同，实测） |
| connect | `{"params":{"token":"<令牌>","name":"js"},"id":1}` → `{"id":1,"result":{"client":<uuid>,"version":"3.1.1","expires":true,"ttl":1798,"subs":{"_person:#<游客>":{}}}}`（服务端自动订阅游客的个人频道，不处理） |
| subscribe | `{"method":1,"params":{"channel":"<channel>"},"id":2}` → `{"id":2,"result":{}}`，收到即加入 |
| ping | `{"method":7,"id":<从 3 往上数>}` → `{"id":<同>}` |
| 下行 | 文本帧，一帧可以有多行，每行一个 JSON：带 `id` 的是回复，不带的是推送。频道推送 `{"result":{"channel":"<channel>","data":{"data":<消息>,"offset":<序号>}}}`；带 `result.type` 的是其他推送（加入、离开、取消订阅），不处理 |
| 令牌无效 | 服务端直接关闭：关闭码 3002，原因 `{"reason":"invalid token","reconnect":false}`（实测，没有先回错误） |
| 令牌过期后再连 | connect 回 `{"id":1,"error":{"code":109,"message":"token expired"}}`，随后关闭：3003，`{"reason":"bad request","reconnect":false}`（实测） |
| 连着时令牌到期 | 服务端不发任何消息，在 `ttl` 之后约 25 s 关闭连接：3005，`{"reason":"expired","reconnect":true}`（实测） |

消息（`data.data.type`）：

| type | 内容 | 本实现 | 归档 v4 |
|---|---|---|---|
| `bj`、`chatter`、`manager`、`support` | 普通聊天（网页的 `isNormalChatMessage`）：`message`、`emoticon`（`{block: {name, img, …}, inline: […]}`）、`id` 登录 id、`nk` 昵称、`idx` 编号、`created_at`（秒）；实测另有 `translate`、`autoTranslate`、`filtered`、`adv`、`lang`、`lcl`、`sex`、`dt`、`pf`、`iat`、`ip` | 白色聊天（见下） | 聊天 |
| `SponCoin`、`ItemCoin` | 送心、特别心（`message` 是 JSON 字符串：`nick`、`id`、`coin`） | 不报（差异 7） | 礼物 |
| `MediaUpdate` | 点赞、收藏、积分（归档规格；录制里只留了 `type`、`created_at`） | 不报 | 不报 |
| `Recommend`、`Info`、`FanUp`、`FanIn`、`KingFanIn`、`ManagerIn` 等 | 推荐、等级变化、入场 | 不报 | 不报 |
| `RoomEnd`、`CastPause`、`ModifyRoom` 等 | 房间状态 | 不报（见“放到其他模块的部分”） | 不报 |

聊天解成白色聊天：

- 文字是 `message` 去首尾空白（整数照写成数字）；没有文字时，取表情里第一个有名字的（一般是 `block`），显示成 `[<名字>]`（如 `[pandaS하트다발png]`，同归档 v4）；都没有就不报；
- 用户名 `nk`，用户 id `id`（登录 id，字符串或整数）；
- 消息 id 是 `<channel>:<offset>`：`offset` 是这条推送在频道里的序号，频道内递增；没有或不是非负整数时留空；
- 时间 `created_at`（秒），不大于 0、不是整数或超出 `DateTime` 范围时为空；
- `idx`、`ip`、`sex`、`lang`、翻译字段、`filtered` 不读。

帧的解法：按行拆开（`LineSplitter`），空行、不是 JSON、不是对象的行跳过；`id` 为 1、2 的回复看 `error`（有就是拒绝，文字是 `connect: <code> <message>`）、2 的无错回复是加入、1 的回复读 `expires`/`ttl`；其他 `id`（ping 的回复）不处理；推送的频道（字符串或数字）必须等于当前频道。二进制帧按 UTF-8 解码（服务端没发过）。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网页（归档规格 §7） | 依据 |
|---|---|---|---|---|
| 地址 | `PandaLiveApi.chatServer`，一个 | 同 | 同 | — |
| 握手请求头 | `Origin`、Chrome 140 UA | 同 | 浏览器 | 实测不带也能连 |
| 开始时的令牌 | 进房带来的；没有或一分钟内到期时先 POST `live/play` | 每次开始都 POST `live/play` | 进房的 `live/play` | 差异 1 |
| 重连时的令牌 | 每次握手前 POST `live/play` 取新的（握手失败时没用过的令牌留给下次） | 沿用开始时的，只在回复带 `error` 后重取 | — | 差异 2 |
| 加入 | 打开后发 connect、subscribe；subscribe 的回复到了才就绪；每次重连加入都再报一次 `DanmakuReady` | 同 | 同（centrifuge-js） | — |
| 加入超时 | 8 s，超时直接重连 | 8 s（`authTimeout`） | — | 回复实测 0.3 s 内到 |
| 心跳 | 每 25 s 发命令 7，id 从 3 往上数，每个 socket 重新数；打开后第一次在 25 s 时（不在加入时立刻发）；手动 `heartbeat()` 立即发一次 | 同（`heartbeatOnJoin` 为 false） | centrifuge-js 默认 25 s | 录制里的间隔正是 25 s |
| 无消息超时 | max(3 × 25 s, 90 s) = 90 s；服务端回答每个 ping | 同 | — | 框架默认 |
| 令牌到期 | `ttl` 前 60 s 取新令牌、悄悄换 socket（不提示）；取不到就等服务端断开（`ttl` 后约 25 s，3005）后重连 | 不处理：服务端断开后按普通断线重连，先用旧令牌被拒（109）再重取（差异 2） | 到期前调用 `v1/chat/refresh_token` 刷新（不换 socket） | 差异 3 |
| 加入被拒 | 换令牌重连；连续第 4 次结束（`connectionFailed`），加入成功就重新计数 | 同样的次数，终态 `rejected`，但一次开始里从不清零 | — | 差异 2 |
| `live/play` 拒绝 | `connectionFailed`，不再重连 | 终态 `credentials` | 进不了房间 | 差异 4 |
| `live/play` 失败 | 当作一次握手失败，按退避重试 | 开始时是终态 `credentials` | — | 差异 5 |
| 断线重连 | 框架默认：只有一个地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，收到任何帧清零，一轮只提示一次 | 框架（v4 的运行时） | centrifuge-js 自己的退避 | 框架的统一做法 |
| 参数不对 | 主播 id 或频道不合规：`connectionFailed`，不请求、不握手；令牌不是可打印 ASCII 时丢掉，第一次握手就取新的 | 用 `danmakuKeys['userId']`，不检查 | — | — |
| 下播 | 不处理下播推送；重连时 `live/play` 回 `castEnd` 就结束 | 不处理 | 按 `RoomEnd` 等更新页面 | 放到 M13 |

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.pandaLive: () => PandaLiveDanmakuConnection(http: pandaLiveHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `PandaLiveSite` 的同一个 `LiveHttp`。`live/play` 以 `pandalive` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `pandalive` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie：全程匿名，v3 也没有 PandaTV 的登录和 Cookie 设置。
- `connector`、`policy`、`now` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（和录制详情）；未开播、被拒绝、刷新得到的房间没有参数，按 D01.1 不连接。

## 与归档 v4 的对照

- 解码的对照：`fixtures/pandalive/danmaku/v4_expected.dart` 把归档 v4 的 `PandaliveProtocol` 原样搬进一个独立程序（与归档文件逐字相同，已用脚本比对），只替换它从别处引用的 `TextFrame`、事件类型（`DanmakuChat`、`DanmakuGift`）、`DecodeContext` 和 `FrameResult`。它用 `meta.json` 的 `danmakuKeys` 和录下的 `live/play` 回答写下 socket 地址、握手请求头、ping 间隔、`live/play` 的地址和表单、读出的频道和令牌、connect、subscribe 和 6 个 ping，再用 `decode` 读每个收到的 socket 帧，写下加入、拒绝的标记和解出的事件（投影）。运行：在仓库根目录 `dart run fixtures/pandalive/danmaku/v4_expected.dart`，结果在 `S07-live/expected.json`，`generator` 字段写明来源。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| 地址、请求头、ping 间隔、`live/play` 的地址和表单 | 与 v4 相同，也等于 `meta.json` 记下的握手 |
| 录下的 `live/play` 回答 | 读出的频道和令牌与 v4 相同 |
| 客户端发的 8 帧 | 与 v4 的 connect、subscribe、ping 3～8 相同，也等于录制 |
| 27 个收到的 socket 帧 | 逐帧一致：加入标记（第 5 行）、拒绝标记（没有）、18 条聊天（消息 id、用户 id、用户名、文字、时间，含一条只有表情的 `[pandaS하트다발png]`），connect 回复、ping 回复、`MediaUpdate`、`Recommend` 都没有消息。唯一的差别是 v4 的 id 带 `pandalive:` 前缀（差异 8），比较时给新代码的 id 加上 |
| 用连接重放录制 | 1 个 socket、没有请求（录制的令牌是脱敏后的，读不出到期时间，照用）、就绪 1 次，发出的帧与录制相同（打开时 connect、subscribe，手动心跳时 ping 3～8），18 条聊天按顺序上报 |
| 进房给的参数 | 平台层用 `S04-member-live`、`S05-play-live`、`S06-master` 进房得到的 `PandaLiveDanmakuArgs` 就是 `daisy00`、`24133575` 和 `S05` 的令牌；进房发出的 `live/play` 请求与本实现取令牌的请求逐项相同（方法、地址、请求头、表单、不跟随跳转） |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 开始时用进房带来的令牌，不再请求 `live/play` | 进房刚刚调用过 `live/play`（E03.12 把令牌放进参数就是为此），每次调用都算一次观看；令牌一分钟内到期时仍会先取新的 |
| 2 | 每次重连都先取新令牌；加入成功后被拒次数重新计数 | 令牌 30 分钟后失效。v4 重连时沿用旧令牌，只在回复带 `error` 后重取：令牌到期、服务端断开（3005）后，v4 先用旧令牌连一次，收到 109 `token expired` 才重取令牌再连（多一个 socket、多一轮提示）；而且 v4 的被拒次数在一次开始里从不清零，每次到期记一次，第 4 次到期（约 2 小时）时以 `rejected` 终止，之后整场直播没有弹幕。令牌不是 JWT 格式等无效情况，服务端直接关闭（3002，不先回错误），v4 更是按普通断线用同一个令牌重连到用尽 8 次（均为实测） |
| 3 | 令牌到期前主动换 socket，不提示 | 服务端在 `ttl` 之后约 25 s 断开（实测），不换的话每 30 分钟界面就会出现一次“与服务器断开连接，正在尝试重连”和“已连接”。网页用 `v1/chat/refresh_token` 在同一个连接上刷新，那个接口归档规格没有记录，本实现改用已知的 `live/play` 加换 socket |
| 4 | `live/play` 拒绝时以 `connectionFailed` 结束 | 这场直播的聊天进不去了（已下播、成人、密码、粉丝专属），重试没有用；原因写在详情里。v4 报的是它自己的终态 `credentials`。接受但 `media.isLive` 为假也算拒绝，和平台层 `danmakuArgs` 的判断一致 |
| 5 | `live/play` 失败（网络、状态码、回答看不懂）按握手失败重试 | 和 socket 握手失败一致；一次网络抖动不该让整场直播没有弹幕。v4 开始时失败就终态 |
| 6 | `live/play` 的请求与进房相同 | 平台层的整组请求头（含 `Accept-Language`）、内容类型不带 charset、不跟随跳转；v4 只带 `Origin`、UA、`Accept`、`Referer`，内容类型带 charset |
| 7 | 不上报礼物（`SponCoin`、`ItemCoin`） | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），D01.2～D01.16 也都不报 |
| 8 | 消息 id 不加 `pandalive:` 前缀 | 和 D01.2～D01.16 一致：去重只在一个房间内，前缀没有作用 |
| 9 | 用户名只取 `nk`，没有时留空 | 统一原则的“占位信息”（E03.12 同样把昵称为空时顶替的登录 id 改为留空）；v4 用登录 id 顶替。录制和实测里 `nk` 都不为空，结果与 v4 相同 |
| 10 | 文字、用户名、用户 id 只接受字符串和整数；时间超出 `DateTime` 范围时为空；表情名去首尾空白 | v4 把任何值转成文字（`true`、对象也会成为聊天）；时间超出范围时 `DateTime.fromMillisecondsSinceEpoch` 抛错，整帧丢掉 |
| 11 | 参数和令牌要检查：主播 id 用平台层的规则，频道是 1～19 位数字，令牌是 1～4096 个不含空白的可打印 ASCII；推送的频道可以是数字 | 令牌要写进 JSON 命令；v4 要求令牌由点分成三段，本实现不要求（令牌格式是服务端的事，不合规它会关闭连接），只保证能安全发出 |

没有改的：地址、请求头、connect、subscribe、ping 的格式和间隔、加入的判定、8 s 的加入超时、被拒 3 次后的第 4 次结束、按频道过滤、跳过带 `type` 的推送、聊天类型、只有表情时显示表情名、按行拆帧都与 v4 相同。

## 与网页的差异

- 令牌到期前换 socket，而不是在同一个连接上刷新（见差异 3）。
- 不处理下播、暂停、改房间信息等房间状态推送（`RoomEnd`、`CastPause`、`ModifyRoom`）。
- 退避按框架（最多 8 次）。

## 实测

2026-09-28 22:12～22:50 UTC（北京时间 29 日 06:12～06:50）只读、匿名、直连，没有登录，没有发言。用只依赖 `dart:io` 的小程序，按人气目录选公开、免费、不是重播的在播房间，调用 `live/play` 取令牌后连接；输出里只看数量、字段名、类型和时间，不记用户的值和令牌；结果没有存成样本。

- **令牌**：JWT 的头是 `typ`、`alg`（HS256），载荷是 `sub`（12 字）、`exp`、`info`（`channel`、`type`、`dt`、`pf`、`iat`、`ip`、`lang`、`lcl`）、`etc`；`exp` 比取到时晚 1800～1801 s。`channel` 是数字，等于主播编号。
- **握手**：带 `Origin` 和 UA、什么都不带都能打开。
- **错误的令牌**：服务端立即关闭，关闭码 3002，原因 `{"reason":"invalid token","reconnect":false}`，之前没有回复。
- **加入**：connect 和 subscribe 的回复在 0.3 s 内到，`version` 3.1.1，`expires` 为真，`ttl` 1796～1798。
- **下行**：两个人气房间各连 4 分钟和 30 分钟，聊天很少（4 分钟 1 条；30 分钟 4 条，都是 `manager`，另有 1 个 `MediaUpdate` 和 1 个 `Recommend`，两者都是 `type`、`message`（JSON 字符串）、`created_at`），聊天的字段见“协议”；聊天带发送者的 `ip`（24 字）、`sex` 等，样本里没有保留，本实现不读。没有观看人数类的推送；网页的观看人数另外拉 `cache-api` 的 `/v1/chat/channel_user_count?channel=&token=`（2026-09-28 22:45 UTC 下载的官网脚本里有这个请求）。
- **连着时令牌到期**：一个连接加入后一直开着（每 25 s ping，服务端都回），服务端没有发任何刷新或断开的消息，在加入后 1821 s（`ttl` 1796 s 之后约 25 s）关闭：3005，`{"reason":"expired","reconnect":true}`。
- **过期的令牌再连**：取一个令牌，放到过期 30 s 后再用：connect 回 109 `token expired`，随后连接以 3003 `bad request` 关闭（subscribe 已经紧跟着发出）。
- **官网脚本**：页面配置里的聊天地址有 `chat-ws.neolive.kr`、`chat-ws.pandalive.co.kr`、`chat-ws.pandalive.co.jp`、`chat-ws.bktv.kr`（后几个是开发和别的站点，归档规格 §7.1），与平台层的 `chatServer` 一致。
- **本实现**：没有接到真实服务器上跑（测试用本地服务器和假连接）；协议和上面逐项对照过，与实测一致。

## 样本

- 没有新录样本，`frames.jsonl` 和 `meta.json` 没有改动。新加的只有 `S07-live/expected.json`（归档 v4 的解码输出）和生成它的 `v4_expected.dart`，里面只有已脱敏的值。
- 逐个字段检查了 `S07-live` 的 36 行：
  - `live/play` 回答录制时已缩减（`meta.json` 的 `reduced`），只剩 `result`、`message`、`channel`、`token` 和 `media` 的 `userId`、`userIdx`、`isLive`；令牌（回答和 connect 命令里的同一个）已换成同形的合成值（三段，读不出载荷，所以也没有 JWT 里的调用方地址）；
  - connect 回复的 `client`、`subs` 里的游客频道已换成同形的合成值；
  - 聊天的 `id`、`idx`、`nk` 已换成合成值（`观众1`～`观众3`），只留了 `type`、`message`、`emoticon`、`filtered`、`created_at`、`id`、`idx`、`nk`，实测的 `ip`、`sex` 等字段不在样本里；其他类型的消息只留了 `type`、`created_at`（`dropped`）；表情图片是平台的公开资源（`cdn.pandalive.co.kr/upload/ChatEmoticon/…`），保留；
  - 找不到 IP 地址、头像路径、Cookie。门禁的 `fixture privacy` 通过。
- 主播 id `daisy00` 和频道（主播编号）是公开信息，按 E03.12 的口径保留。

## 受阻

没有。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表）。`live/play` 拒绝的详情是 `live/play: <代码>`，加入被拒是 `Chat refused: <connect|subscribe>: <code> <message>` |
| 房间公告 `pandalive_chat_notice` 的文字 | 已在平台层改好：`PandaLiveApi.chatNotice` 去掉“这里暂时看不到 PandaTV 直播间的聊天。”，只说明人数（“人数分别是正在观看和本场累计观看。”）；翻译在 M13 |
| 直播间里的实时在线人数 | M13 或以后的升级决定：网页定时拉 `cache-api` 的 `/v1/chat/channel_user_count`（要聊天的频道和令牌）；列表和进房本来就有在线人数（`user`），`audience.dart` 是 `roomList`，本模块不拉 |
| 下播提示 | M13 决定是否要：聊天流有 `RoomEnd`、`CastPause` 等推送，本实现不报；要用时在协议层加一个事件。连接本身在下一次重连时由 `live/play` 的 `castEnd` 结束 |
| 显示礼物（若以后要做） | M13 统一决定；本平台要解 `SponCoin`、`ItemCoin`（`message` 是 JSON 字符串） |
| 录制时是否带弹幕 | H01.1（录制详情也带参数，E03.12） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除 |

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖；`live_core` 没有改，请求、地址、表单、回答的读取和主播 id 的规则都用平台层已有的（`PandaLiveApi.chatServer`、`headers`、`roomUrl`、`playForm`、`answer`、`refusalCode`、`flag`、`normalizeUserId`）。

## 测试

`test/sites/pandalive_test.dart` 29 个用例，`live_danmaku` 共 780 个，连续跑 3 次全部通过；本文件在时钟 +30 天、+1 年、+5 年下直接运行（`tools/timeshift` 的方式）也都通过，进程正常退出。所有读令牌到期时间的地方都把“现在”固定成录制时间（`now:`）。

- 协议 8 个：地址、请求头、命令、时序常量和换 socket 的时间；取令牌的请求与平台层进房发的逐项相同，进房给的参数；取令牌的回答（完整的 `S05-play-live`、录下的缩减回答、数字频道、没有 `isLive`；`castEnd`、`needAdult` 两个录下的拒绝和合成的拒绝、没有代码、接受但不在播；403、502、不是 JSON；没有令牌、带空白或非 ASCII、4097 字、没有频道、不是数字的频道、20 位频道、令牌不是字符串）；令牌的到期时间（合成的 JWT、没有 `exp`、0、负数、越界、字符串、数组载荷、不是 JSON、坏的 base64、坏的 UTF-8、录下的脱敏令牌）；参数检查；一条聊天的各字段；聊天的边界（四种聊天类型和 16 种其他类型、文字的各种类型、只有表情、表情的各种坏形状、名字和 id、`offset`、时间的 0、负数、上限和越界）；帧（connect 回复的 `ttl`、加入、两种拒绝和字符串错误、ping 回复、字符串 id、字节帧、坏的 UTF-8、数字频道、一帧多行、别的频道、带 `type` 的推送、不是对象、礼物和其他类型）。
- 录制 3 个：地址、请求头、表单、命令、ping 间隔与 v4 和 `meta.json`、录制发出的帧一致；27 个收到的帧与 v4 的冻结输出逐帧一致；用连接重放整份录制。
- 连接 18 个：
  - 默认时序和平台表登记；握手（进房的令牌、地址、请求头、代理路由、打开时发 connect 和 subscribe、subscribe 回复后才就绪、别的频道和其他消息不上报）；
  - 没有令牌、令牌一分钟内到期或已过期时先取令牌，用回答里的新频道；两分钟后才到期的令牌照用；
  - 断线后取新令牌重连、再次就绪；握手失败时没用过的令牌留给下次；
  - `live/play` 在开始时和重连时拒绝都以 `connectionFailed` 结束；请求失败（超时、502、没有令牌）按握手失败重试后加入，一直失败时 `reconnectsExhausted`；
  - 加入被拒换令牌重连、加入成功后重新计数、连续第 4 次结束；过期令牌照实测的样子（回 109 再关闭）只换一次 socket；加入超时换令牌重连；
  - 到期前换 socket（不提示、不再就绪、聊天不断），新令牌不会马上再换；换 socket 时 `live/play` 拒绝就结束、失败就保留旧 socket（断开后重连再取）；等令牌时旧 socket 断了、重连已经换好，就不再换，取到的令牌留给下次；换好的 socket 不加入就重连；
  - ping 的 id 每个 socket 从 3 数起，定时和手动都发；参数不对直接结束、不请求也不握手，参数类型不对抛 `ArgumentError`；关闭时取消进行中的 `live/play`，关闭后没有事件、不再发帧，再次 `connect` 换房间；
  - 真实的本地服务器：默认的 `dart:io` 握手（路径、`Origin`、UA），服务端收到 connect、subscribe、ping，一帧多行的回复里加入和聊天都生效；结束时关掉服务端所有升级后的 WebSocket 和服务器，直接运行测试文件时进程能退出。
