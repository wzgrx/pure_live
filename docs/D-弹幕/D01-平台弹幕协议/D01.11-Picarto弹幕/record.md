# D01.11 弹幕（新增）：Picarto

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/picarto.dart`
  - `PicartoDanmakuConnection`：连接；
  - `PicartoDanmakuProtocol`：令牌请求、地址、心跳帧、解码，不做 I/O；
  - `PicartoDanmakuFrame`：一帧的解码结果（消息、令牌是否被拒）。
- 参数：`live_core` 的 `PicartoDanmakuArgs`（E03.3）：平台写法的频道名 `channelName`、频道 id `channelId`。进房（`getRoomDetail`）时由详情给出，未开播也给，不多发请求；录制详情和关注刷新不给。本模块没有改 `live_core`。
- 升级条目：11-7“启用 Picarto 弹幕（归档 v4 已实现）”。v3 没有 Picarto 弹幕（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本（都在 `fixtures/picarto/danmaku/`）：
  - `S07-live`：归档 v4 的真实录制（2026-09-27，频道 allatir，约 100 s，9 帧：令牌应答、1 条进场、6 条频道状态、1 条聊天）。E 从归档复制过来，本模块加上 v4 解码的冻结输出 `expected.json`；
  - `S09-keepalive`：本模块补录（2026-09-28 18:57 UTC，直连，200 s，13 帧）：令牌应答、4 条频道状态（多人同播，每次重复一条）、1 条离开、1 条进场，以及每 50 s 发一次的保活和服务端的 3 次应答；
  - `S10-token-refused`：本模块补录（2026-09-28 19:01 UTC，直连，10 s，3 帧）：用一个编造的、与真令牌同形的令牌连接，服务端的拒绝、保活、再次拒绝；
  - `S11-synthetic`：合成帧（`cases.json`，23 组），见“测试”；
  - 四个目录的 `expected.json` 都由 `v4_expected.dart` 生成（见“与归档 v4 的对照”）。`S06-chat-token`（E03.3 的令牌接口录制）也用于测试。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/picarto.dart`（`PicartoProtocol`、`PicartoConnector`）、`runtime/socket_connector.dart`、`model.dart` 的 `DanmakuColors`、`test/picarto_test.dart`；规格 `spec/sites/picarto.md` 第 7 节；
  - 网站自己的聊天客户端（2026-09-28 下载的 `picarto.tv/static/js/main.d543fe27.js` 和聊天所在的 `6572.9e565331.chunk.js`）：地址、保活、重连、消息类型和字段的含义（见“协议”）；
  - pure_live_TV `e1cca224`：`lib/platforms/picarto/picarto_site.dart:30` 仍是 `EmptyDanmaku`，没有可参考的实现；对照笔记 `~/ref/notes/tvcore/sub_C.md` 的 picarto 一节也是这样记的；
  - 2026-09-28 18:44～19:10 UTC 的只读实测（匿名、直连、不登录、不发言），见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），平台只写 `target`、`onOpen`、`onData`、`heartbeatFrame`。换地址、退避、最多 8 次、无消息超时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **开始时请求一次令牌**：
  - 用注入的 `LiveHttp` 向 GraphQL 接口要匿名 JWT（和归档 v4、网站相同的查询），请求头是 `PicartoApi.headers`；
  - 最多 3 次，间隔 0.5 s、1 s，每次最多等 5 s；都拿不到就以 `credentialsUnavailable` 结束，不开连接；
  - 本次 `connect` 结束（关闭、换房间）时取消进行中的请求。
- **令牌不会过期，重连沿用它**：JWT 里没有 `exp`、`iat`，7 分钟前的令牌照样能连；网站断线后也是 1 s 后用同一个令牌重连。所以断线重连不再请求。
- **打开即就绪**：服务端连上后不发欢迎消息（实测第一条消息最早也在 20 s 之后），网站和 v4 都是打开即算连上。
- **保活照网站**：每 50 s 发一次 `{"type":"ping","message":"__ping__"}`，服务端回 `{"success":true,"code":"PONG"}`，所以无消息超时取框架默认的 max(3 × 50 s, 90 s) = 150 s。未开播和冷清的频道也不会被误判为断线（差异 11）。
- **令牌被拒时换令牌**：服务端不关连接，只回 `{"success":false,"code":"JWT_TOKEN"}`，之后每一帧都这样回。这时标为未加入，重新请求令牌，用 `session.reopen` 换新连接，不提示；每次 `connect` 最多换 3 次，第 4 次被拒或拿不到新令牌就以 `credentialsUnavailable` 结束（和哔哩哔哩刷新凭据一样）。
- **只上报聊天和在线人数**，和归档 v4 相同，也和 D01.2～D01.10 的范围一致。Picarto 的付费消息是“筹码打赏”（chip tip），没有录到过，也没有 3.x 的界面，不上报，列为后续升级候选。

## 协议

**令牌**：`POST https://ptvintern.picarto.tv/ptvapi`，正文 `{"query":"query ($name: String) { generateJwtToken(channel_name: $name) { key } }","variables":{"name":"<频道名>"}}`。

- 回答 `{"data":{"generateJwtToken":{"key":"<JWT>"}}}`。匿名令牌是 HS256，载荷有 `userId 0`、`channelId`、`channelName` 等，没有过期时间；
- 频道不存在时 `key` 为 `null`（实测）；
- 只接受三段 base64url 的值（它要放进地址的路径），不合格的当作没有令牌。

**连接**：`wss://chat.picarto.tv/chat/token=<JWT>`，握手请求头 `origin: https://picarto.tv` 和 Chrome 140 的 UA（与 v4 和两次录制相同）。服务端（Cloudflare + uWebSockets）不在乎请求头大小写，用默认的 `dart:io` 握手，不需要 `connectExactWebSocket`。

**消息**：JSON 文本帧。网站按 `type` 或 `t` 取类型、按 `messages` 或 `m` 取内容，两种写法都读。

| 帧 | 含义 | 本实现 | 归档 v4 |
|---|---|---|---|
| `{"t":"c","m":[行…]}` | 聊天，一帧可有多行 | 每行一条聊天（见下表） | 同 |
| `{"t":"c","paginated":…}` 或带 `p` | 历史记录的一页 | 不报，网站的实时处理也跳过它（差异 8） | 当作聊天 |
| `{"type":"stream","messages":{…}}` | 频道状态：`id`、`online`、`viewers`、`multistream`、同播各路的 `streams` | `viewers` 是同时在线，报 `onlineViewers`；`id` 不是本频道时不报（差异 10） | 报 `viewers`，不看 `id` |
| `{"success":true,"code":"PONG"}` | 保活的应答 | 不报 | v4 不发保活，收不到 |
| `{"success":false,"code":"JWT_TOKEN"}` | 令牌被拒 | 换令牌（见“做法”） | 不识别 |
| `un`、`ur`、`ul` | 观众进入、离开、名单 | 不报 | 不报 |
| `w`、`ct`、`ps`/`pr`、`rs`/`rr`、`system`、`raid`、`ns`、`rm`、`cm` 等 | 私信、筹码打赏、投票、抽奖、系统通知、突袭、订阅、删除消息、清屏 | 不报（候选见后） | 不报 |

聊天行的字段（网站的映射：`t` 类型、`c` 所在频道、`u` 用户、`n` 名字、`m` 文本、`id`/`_id`、`d` 时间、`k` 名字颜色、`i` 头像、`y` 账号类型、`rn` 房间名、`cb` 徽章…）：

| `LiveMessage` | 取值 | 与归档 v4 |
|---|---|---|
| 类型 | 聊天；行的 `t` 不是 `c`（例如 `system`、`w`）时不报 | v4 不看行的类型（差异 7） |
| 文本 | `m` 去首尾空白；不是文字或为空时整行不报 | 同 |
| 用户名、用户 id | `n`、`u`，文字或数字照写，其他类型为空 | v4 把任何值转成文字（差异 6） |
| 消息 id | `id`，没有时用 `_id`，不加前缀 | v4 只读 `id`、加 `picarto:`（差异 1、2） |
| 时间 | `d`（毫秒）；不是整数或超出 `DateTime` 范围时为空 | v4 超出范围时整帧抛错（差异 3） |
| 颜色 | `k`：6 位十六进制（可带 `#`）或 CSS 的 3 位简写；其他都是白色 | v4 按 1～8 位数字读，3 位、8 位与网站不同；不是文字时整帧抛错（差异 4、5） |
| 等级、粉丝牌 | 空 | 同 |

`c`（发言所在频道）不检查：多人同播时同组共用一个聊天室，网站全部显示，v4 也全部显示。表情以 `:名字:` 留在文本里。

在线人数的来源：目录、搜索、详情本来就给 `viewers`（`audience.dart` 里 Picarto 是 `roomList`），弹幕里的 `stream.viewers` 是同一个数（S04 详情 52 对 S07 的 53；S09 录制时目录里 allatir 是 22，弹幕 23、22）。接入后来源没有变，`audience.dart` 不用改。

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 依据 |
|---|---|---|---|
| 开始前的请求 | 令牌 1 个，失败时共 3 次（间隔 0.5 s、1 s，每次 5 s 超时） | 令牌 1 个，失败即结束 | 差异 13 |
| 地址、请求头 | `wss://chat.picarto.tv/chat/token=<JWT>`；`origin`、UA；默认握手 | 同 | 录制、网站脚本 |
| 加入 | 打开即就绪，不发任何加入消息；每次重连后再报一次 `DanmakuReady` | 同 | 网站 `onopen` 即“connected” |
| 加入超时 | 无 | 无 | — |
| 心跳 | 50 s，`{"type":"ping","message":"__ping__"}`，文本帧；手动 `heartbeat()` 同样 | 不发 | 网站 `REACT_APP_CHAT_TIMEOUT: "50000"`；差异 11 |
| 无消息超时 | 150 s（max(3 × 50 s, 90 s)，策略里不单独写）；服务端每次保活都回 | 180 s（3 × 60 s） | 实测未开播频道 240 s 没有一条文本消息 |
| 断线重连 | 框架默认：只有一个地址，间隔 2、3、4、5、6、6、6、6 s，第 9 次失败结束；收到任何消息清零；一轮只提示一次。沿用令牌 | 同样的退避；沿用令牌（只有被拒才重取，而它识别不了被拒） | 网站 1 s 后用同一令牌重连，最多 10 次 |
| 令牌被拒 | 标为未加入、重取令牌、`reopen`，不提示；每次 `connect` 最多 3 次 | 不识别，连接一直沉默，到 180 s 看门狗后用同一令牌重连，循环不止 | S10 录制；差异 12 |
| 结束原因 | 拿不到令牌、第 4 次被拒：`credentialsUnavailable`；频道名为空：`connectionFailed`；重连用尽：`reconnectsExhausted` | `credentials`、`maxRetries` | D01.1 的类型；差异 16 |
| 诊断文字 | 握手失败的文字里把令牌换成 `token=…` | 带着整个地址 | D01.1：详情不带令牌；差异 15 |
| 代理 | 按平台 `picarto` 取路由（构造参数 `proxy`） | 同 | — |

服务端的 WebSocket 协议层 ping：客户端什么也不发时约每 84 s 一次（`dart:io` 自动回应）；每 50 s 发保活时一次也没有。它不是应用消息，不能让框架的无消息检测知道连接还活着，所以要靠应用层的保活。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.picarto: () => PicartoDanmakuConnection(http: http, proxy: proxyPolicy),
  // …
});
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `http` | 是 | 请求令牌用的 `LiveHttp`，就用给 `PicartoSite` 的那个（按平台 id `picarto` 取代理路由和限流） |
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `picarto` 取路由。国内直连和经代理都能用（v4 规格） |
| `connector` | 否 | 只给测试替换握手；默认 `dart:io` |
| `tokenRetryDelay` | 否 | 只给测试缩短令牌重试的间隔 |

不需要 Cookie 或设置：Picarto 没有登录（v3、E03.3 都没有它的 Cookie），弹幕全程匿名。

## 与归档 v4 的对照

对照方式：

- `fixtures/picarto/danmaku/v4_expected.dart` 把归档 v4 的 `PicartoProtocol`（`tokenQuery`、`token`、`endpoint`、`decode`）、`PicartoConnector.plan` 发出的令牌请求和握手请求头、`model.dart` 的 `DanmakuColors` 原样搬进一个独立程序，只把事件类型删到只剩字段；解码抛错时记为 `{"throws": 类型}`。
- 它对 S07、S09、S10 写下令牌、地址、令牌请求、握手请求头、每个收到的帧解出的事件，对 S11 写下每组每帧解出的事件。运行：在仓库根目录 `dart run fixtures/picarto/danmaku/v4_expected.dart`，`generator` 字段写明来源。
- 测试把新代码的 `LiveMessage` 投影成 v4 的形状（消息 id 补回 `picarto:` 前缀），逐帧比较；有意的差异在测试里逐组写明：先断言 v4 的输出，再断言新代码的。

| 对照 | 结果 |
|---|---|
| 令牌请求 | 地址、查询正文与 v4、S06 录制相同；请求头都是 origin、UA、referer 加 JSON 类型 |
| 令牌、地址、握手请求头 | S07、S09 与 v4 和录下的握手完全相同 |
| S07 的 8 个收到的帧 | 一致：1 条聊天（名字、用户 id、文本、时间、颜色；id 只差前缀）、6 次在线人数（53、59）；进场不报 |
| S09 的 9 个收到的帧 | 一致：4 次在线人数（23、22）；离开、进场、3 次保活应答都不报 |
| S10 | v4 什么也读不出；新代码两帧都识别为令牌被拒 |
| S11 的 23 组 | 14 组一致（其中令牌被拒那组 v4 读不出被拒）；9 组是有意差异（差异 2～10），见下 |
| 发出的帧 | v4 什么也不发（S07 没有发出的帧）；新代码只发保活，与 S09 录下的 3 次逐字相同 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 消息 id 不加 `picarto:` 前缀 | 与 D01.2～D01.10 一致：去重闸门按房间内的 id 比较，不需要前缀 |
| 2 | 没有 `id` 时用 `_id` | 网站的映射就是 `id || _id` |
| 3 | 时间超出 `DateTime` 范围只让这一行没有时间 | v4 抛 `RangeError`，整帧丢失（统一原则“一行坏数据只跳过这一行”） |
| 4 | 颜色按网站的 CSS 读：3 位是简写（`f80` 是 `#ff8800`），8 位不是颜色 | 网站把 `k` 加上 `#` 交给 CSS；v4 把 `f80` 读成 `#000f80`、8 位当 ARGB。录到的颜色都是 6 位，没有区别 |
| 5 | 颜色不是文字时为白色 | v4 强制转换抛 `TypeError`，整帧丢失 |
| 6 | 用户名、用户 id 不是文字或数字时为空 | v4 会显示 `{x: 1}`、`true` 这样的文字 |
| 7 | 聊天帧里 `t` 不是 `c` 的行不报 | 网站按行的类型区分系统通知、私信等；v4 当作聊天 |
| 8 | 历史记录的一页（帧上有 `paginated` 或 `p`）不报 | 网站的实时处理跳过它；实测匿名连接不会收到，只是防止旧消息当新弹幕 |
| 9 | `type`/`t`、`messages`/`m` 两种写法都读 | 网站两种都读；v4 只认 `type`+`messages` 的状态和 `t`+`m` 的聊天 |
| 10 | 频道状态的 `id` 不是本频道时不报人数 | 多人同播时防止把别的频道的人数当成本房间的。录制里的状态帧都是本频道的，看不出区别 |
| 11 | 每 50 s 发网站的保活，无消息超时 150 s | 问题 1：v4 不发任何东西、180 s 没有消息就重连，未开播或冷清的频道每 3 分钟提示一次重连 |
| 12 | 识别令牌被拒，换令牌重连，每次 `connect` 最多 3 次 | 问题 2 |
| 13 | 令牌请求失败时再试两次（0.5 s、1 s），每次 5 s 超时 | 一次网络抖动就让这个房间没有弹幕，直到重新进房；间隔照哔哩哔哩取凭据。每次 5 s 超时，三次请求加间隔最多 16.5 s，短于直播间 20 s 的启动超时（M13） |
| 14 | 令牌只接受三段 base64url | 它要放进路径；v4 只要求三段 |
| 15 | 握手失败的诊断文字不带令牌 | D01.1 约定详情不带令牌；`dart:io` 的错误文字带着整个地址 |
| 16 | 结束原因用 D01.1 的类型：拿不到令牌、被拒用尽是 `credentialsUnavailable` | v4 的 `credentials`；界面文字由 M13 给出 |

没有改的地方：

- 令牌请求、地址、握手请求头与 v4 相同，服务端接受过（两次录制）。
- 打开即就绪、沿用令牌重连、代理路由、退避和次数（框架默认）与 v4 相同。
- 聊天和人数的解读（文本去空白、空文本不报、`viewers` 是同时在线）与 v4 相同，时间用本地时区的 `DateTime`（同一时刻），和其他平台一样。
- 多人同播时同组的聊天全部显示。

## 审查发现的归档 v4 问题

| # | 问题 | 位置（归档 v4） | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 未开播或冷清的频道每 3 分钟断一次、提示一次重连 | `sites/picarto.dart`（`watchInterval` 60 s、`heartbeat()` 为 null） | 以为服务端的 `stream` 状态约每 60 s 必来（规格 7.3）。实测未开播频道 240 s 一条文本消息也没有，在播频道也有 153 s 的空档；服务端的协议层 ping 不算消息 | 发网站的保活（差异 11） |
| 2 | 令牌被拒时连接一直沉默，之后用同一个令牌无限重连 | `sites/picarto.dart` 的 `decode` 不返回 `rejected` | 服务端拒绝令牌时不关连接、只回 `JWT_TOKEN`；v4 不识别，框架只有在“被拒”时才重取令牌 | 差异 12 |
| 3 | 一行的时间超出范围或颜色不是文字时整帧丢失 | `decode` | 没有逐字段容错 | 差异 3、5 |
| 4 | 规格写“重连时重新取 JWT”，实现并不重取 | 规格 7.3；`runtime/socket_connector.dart` | 只有 `rejected` 才调用 `plan(refresh: true)` | 令牌不过期，沿用是对的（和网站相同），文档按实际写 |
| 5 | （潜在）多人同播时别的频道的状态会被当成本房间人数 | `decode` | 不看 `id` | 差异 10 |

## 实测

2026-09-28 18:44～19:10 UTC，只读、匿名、直连，没有登录，没有发言。

- 探测（自写的最小 WebSocket 客户端，能看到控制帧）：
  - 3 个频道各连 240 s，客户端什么也不发：在播的 rapapapapapa、allatir 约每 60 s 一条状态（allatir 第一条在 170 s 才来），未开播的 Kaiyote 一条文本消息也没有；服务端在 84 s、168 s 发协议层 ping；
  - 未开播频道每 10 s 发一次保活，5 次都在 0.3 s 内回 `PONG`；
  - 编造的令牌：握手照样成功（101），立刻回 `JWT_TOKEN`，之后每次保活都回同样的拒绝，25 s 内没有关连接（S10 是这样录下的）；
  - 不存在的频道：令牌接口回 `{"key": null}`；
  - 7 分钟前拿到的令牌照样能连、能收到 `PONG`；JWT 解开后没有 `exp`、`iat`。
- 4 个在播频道（JFdeportista 168 人、rapapapapapa 61 人、tetrapod 23 人、allatir 22 人）各录 200 s，照新连接的做法每 50 s 发保活：12 次保活都在 0.4 s 内得到应答，状态约每 60 s 一条，200 s 里没有人发聊天。S09 取自 allatir 那一份（内容最全）。
- 用本实现（`IoLiveHttp` + 默认握手）连 allatir 70 s：2.3 s 就绪，3 s 时手动发一次保活，45 s 收到在线人数 21，关闭后状态为 `idle`。
- 网站脚本（见“参考”）：连接地址同上；`onopen` 即“connected”，然后每 50 s 发保活；它等的应答写成 `"__pong__"`，而服务端实际回 `{"success":true,"code":"PONG"}`，所以网站在整个会话里一直每 50 s 发一次；`onclose` 后 1 s 用同一个令牌重连，最多 10 次。

## 样本

- **S09-keepalive**（allatir，多人同播）：
  - 令牌（令牌应答和握手地址）换成三段长度相同（36、407、43）的合成值；
  - 离开和进场里观众的 `u`（用户 id）、`n`（名字）、`i`（头像路径）、`r`（注册时间）换成同形同长的合成值，两帧里同一个人换成同一组值；
  - 频道状态里是各路主播的公开信息（名字、id、头像、缩略图），按 E03.3 的口径保留；保活和应答没有要换的；
  - `meta.json` 记了脱敏位置、原始录制的 SHA-256 和长度、说明（`note`）。
- **S10-token-refused**：令牌是编造的，不是脱敏的结果（`scrubbed` 为空，`note` 写明）。
- **S11-synthetic**：名字、id、时间都是编造的。
- 逐帧检查过：没有 IPv4 地址、Cookie、会话值；门禁的 `fixture privacy` 通过。
- `S07-live` 的帧没有改，只加了 `expected.json`。
- 录制用的是自写的 Python 小脚本（最小 WebSocket 客户端，只发保活），没有放进仓库；`meta.json` 的 `tool` 写明了。

## 回归条目的覆盖

归档规格里 Picarto 的回归条目 REG-PICARTO-001～003 都属于平台层（E03.3），第 7 节“弹幕”没有回归条目。

## 受阻

没有。

## 后续升级候选（由用户决定）

| # | 内容 | 现状 | 依据 |
|---|---|---|---|
| 1 | 筹码打赏（`ct`）显示为醒目留言 | 已做（D01 后续升级（原 M5.F）） | 网站显示“<名字> tipped <主播> <筹码数>”和附言（字段 `n`、`rn`、`x`、`m`）。没有录到过；醒目留言要显示时长和价格单位，需要 M13 定 |
| 2 | 被管理员删除的消息（`rm`）、清掉某人的消息（`cm`）从弹幕列表撤下 | 已做（D01 后续升级（原 M5.F）） | 网站脚本；和 Twitch 的候选 2 一起由 M13 支持撤回 |
| 3 | 显示系统通知、突袭、订阅（`system`、`raid`、`ns`） | 已做（D01 后续升级（原 M5.F）） | 网站脚本；Twitch 的 `USERNOTICE` 也不显示 |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表） |
| 上面的候选 | M13 |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除 |

## 新增的通用能力、依赖

没有。只在 `live_danmaku.dart` 里按字母顺序加了一行导出，框架文件没有改，`live_core` 没有改。

## 测试

`test/picarto_test.dart` 53 个用例，`live_danmaku` 共 612 个，连续跑 3 次全部通过。另做了变异检查，下面每一种改动都会让对应的用例失败：保活改成 60 s、不发保活（v4）、不理会被拒、被拒后用旧令牌重连、没有换令牌的上限、不看状态帧的频道（v4）、诊断文字带令牌、显示历史记录页（v4）、不认 3 位颜色、令牌只请求一次、收到消息才就绪、不看行的类型（v4）、不读 `_id`、不检查时间范围、关闭时不取消令牌请求。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 5 | 令牌请求与 v4、S06 录制相同；令牌的读法（S06、S07、S09、未知频道和各种形状，只收三段 base64url）；地址和握手请求头与 v4、录下的握手相同；保活与 S09 发出的帧相同、间隔 50 s、v4 不发；聊天和人数填满消息模型 |
| 录制帧对照 v4 | 3 | S07 的 8 帧（1 条聊天、6 次人数）；S09 的 9 帧（4 次人数，进出和保活应答不报）；S10 的两次拒绝 |
| 合成帧（S11）对照 v4 | 24 | 23 组各一个用例（9 组按差异 2～10 变换，每组另查是否识别为令牌被拒），另有一个检查每组都有 v4 输出、每条差异都对应一组 |
| 连接 | 21 | 用 S06 回放取令牌、请求的地址头部正文和超时、握手地址头部、直连、打开即就绪且不发东西；频道名去空白、为空时 `connectionFailed`；代理路由；令牌 3 次（0.5 s、1 s）后成功；3 种拿不到令牌的情形都是 `credentialsUnavailable` 且不开连接；取令牌时关闭会取消请求、没有事件；时序（50 s、150 s、无加入计时器、8 次）；50 s 定时和手动保活、关闭后不发；回放 S07 和 S09（文本帧和二进制帧交替）得到 v4 的 11 条；只报本频道的人数；被拒后换令牌立刻重开、不提示、就绪两次；第 4 次被拒结束；被拒后拿不到新令牌结束；被拒次数按 `connect` 计；断线 2 s 后用同一令牌重连、就绪两次；退避 2、3、4、5、6、6、6、6 s 后放弃且详情不带令牌；关闭后没有事件和保活；换房间取新令牌、旧连接的消息和拒绝都不起作用；参数类型；平台表登记；本地 WebSocket 服务器端到端（路径里的令牌、Origin、录制的帧、保活和应答） |

## 后续升级（D01 后续升级（原 M5.F），附录 B-8）

- 日期：2026-09-30
- 条目：附录 B-8，即上面“后续升级候选”的 1～3，决定“采用”。本节取代“协议”一节消息表里 `ct`、`system`、`raid`、`ns`、`rm`、`cm` 的“不报”，以及“做法”里“只上报聊天和在线人数”。
- 改动：`PicartoDanmakuProtocol` 加了 `line`、`tip`、`avatar`、`system`、`raid`、`subscription`、`deletion`、`clearance` 和常量 `tipDuration`、`imageBase`、`tipUnit`；`decode` 多了可选参数 `channelName`（本房间的频道名）和 `now`（收到的时间）。`PicartoDanmakuConnection` 多了只给测试用的构造参数 `now`（时钟），登记方式不变。没有新设置。
- 依据：
  - 网站脚本（2026-09-30 重新下载，文件名和 D01.11 时相同：`main.d543fe27.js`、聊天所在的 `6572.9e565331.chunk.js`，另加行映射所在的 `/chatworker.min.js`）：
    - 聊天组件的收帧分支（`6572`：`"cm"===e.t0?56:"rm"===e.t0?58:…"c"===e.t0||"ct"===e.t0||…?73:"ns"===e.t0?75:"raid"===e.t0?77:…"system"===e.t0?85`）；帧上 `paginated` 或 `p` 为真时整帧跳过；
    - `rm` 交给消息列表的 `updateDeleteMessage(m)`：把 `id` 相同的那一行的文字换成帧里的 `m`，标为已删除；`cm` 交给 `updateMsgClear(m.u)`：去掉 `userChannelId`（行的 `u`）相同的所有行；
    - 行的映射（`chatworker.min.js` 的 `chatMessageMapper`，`main.js` 里有同样的一份）：`t` 按 `{c: chat, system, ct: chipTip, w: whisper, …}` 定类型，`x` 是 `chips`，`v` 是 `tipping`，`mc`、`mk` 是最大的 chipmote，`rn` 是 `receiverName`，`i` 头像，`l` 链接，`ic` 图标；
    - 每行的显示（`6572` 的消息组件）：类型 `system` 用 NotificationMessage（`main.js` 模块 90370：`{link}`、`{icon}` 占位，按 `\n` 分行），`ns` 用 SubscriberMessage，`raid` 用 RaidMessage，行的 `tipping` 为真用 ChipTipMessage（“<名字> tipped <rn> <x>”，下面是附言，附言里 `kudo100` 这类 chipmote 换成图片），没有类型的行不显示；
    - `system` 帧（`At`）：帧的 `c` 为 `b` 时只给主播和房管看；`z`、`w` 只影响排序和私信窗口；
    - 文字（`main.js`）：`CHIPS_TIPPED "tipped"`、`TIP_BOX_STRING3 "Kudos"`（打赏框写“Tipping {数} Kudos”，贡献榜写“{数} Kudos”）、`SUBSCRIBER_MESSAGE*`、`CHAT_SUB_RECURRING`、`RAID_STRING_2 "Raid"`；头像前缀 `https://images.picarto.tv/`（模块 59735），完整地址照用。
  - 实测：2026-09-30 15:14～17:44 UTC，对目录里在线人数最多的 45 个频道各连 150 分钟（匿名、直连、`dart:io` 的最小客户端，只发保活，不登录、不发言）。共收到 2120 个聊天帧、1591 个频道状态、6145 次保活应答，其中 B-8 相关的只有 3 帧：1 次打赏（S14-tip）、1 次 `rm`（S13-removed）、1 条 `system`（S15-system）；`ct` 帧、`cm`、`raid`、`ns` 没有出现。另见到网站的收帧分支里没有的 `ctt`（打赏榜：`[{n, ct}]`），网站不处理，这里也不报。

### 做法

| 帧 | 网站 | 本实现 |
|---|---|---|
| 带真值 `v` 的聊天行（录到的形状），或 `ct` 行 | 打赏框 | 醒目留言（`superChat`） |
| `rm` | 那一行的文字换成 `m`，标为已删除 | 撤回 `LiveRetraction.message(id)` |
| `cm` | 去掉这个用户的所有行 | 撤回 `LiveRetraction.user(u)` |
| `system` 行 | 居中的通知行 | 通知 `system` |
| `raid` | “RAID!”和服务端的文字；在发起方频道的页面上 10 s 后跳到被突袭的频道 | 通知 `raid`，不跳转 |
| `ns` | 按字段拼的英文句子 | 通知 `subscription`，中文句子 |

**醒目留言（筹码打赏）**

- 录到的打赏（S14）是普通的聊天帧：`{"t":"c","m":[{"t":"c", …, "m":"kudo100 …", "v":true, "mc":100, "mk":"kudo", "x":100}]}`，附言开头是打赏人输入的 chipmote。
- 哪些行算打赏：`c` 行或没有类型的行带真值 `v`（网站的 `tipping`，JavaScript 的真值规则）；`ct` 行（网站映射成 `chipTip`，没有录到）。行按自己的类型读，所以 `c`、`ct`、`system` 帧里的打赏都认。
- 字段：

| `LiveSuperChatMessage` | 取值 |
|---|---|
| `messageId` | 行的 `id`，没有时 `_id`（和聊天行相同） |
| `userName` | `n` |
| `face` | `i`：路径前加 `https://images.picarto.tv/`，已经是完整地址的照用（和网站相同）；没有或不是文字时为空 |
| `message` | `m` 去首尾空白，不是文字时为空；`kudo100` 这类 chipmote 照文字留着（和聊天里的 `:表情:` 一样）。多人同播时 `rn` 不是本房间的频道（不分大小写）就写成 `打赏给 <rn>：<附言>`，没有附言时 `打赏给 <rn>`；没有 `rn` 时不加 |
| `price` | `x`，大于 0 的整数；不是的这一行不报（坏数据只丢这一行） |
| `priceText` | `<x> Kudos`：网站打赏框和贡献榜的写法（聊天里那一行只写数字，没有单位） |
| `startTime` | `d`（毫秒）；没有或不是合法的整数时用收到的时间 |
| `endTime` | `startTime` + 60 s |
| `backgroundColor`、`backgroundBottomColor` | 空字符串：帧里没有颜色，网站用固定的主题色边框 |

- 外层的 `LiveMessage`：类型 `superChat`，用户名和文字都是 `SUPER_CHAT_MESSAGE`、白色，和 D01.2～D01.4 的醒目留言相同；另外带上行的 `id`（`messageId`）、`u`（`userId`）、`d`（`sentAt`），这样 `rm`、`cm` 能像撤回聊天一样撤回它。
- 显示时长 60 s（网站没有）：网站把打赏当作聊天里一个带边框的行，不定时撤下，也没有按金额分档。60 s 是哔哩哔哩醒目留言最短的一档（醒目留言栏是照它做的）；Picarto 的 1 Kudo 给主播 1 美分，打赏普遍是小额（录到的是 100），用最短一档。
- `ct` 行没有 `v` 时网站只显示名字、没有内容；这里照样当作打赏（比网站宽，`ct` 没有录到，防止服务端不带 `v` 时整条丢掉）。聊天行带 `x` 但没有 `v` 的仍是聊天。

**撤回**

- `rm`：`m` 是对象、`m.id` 是非空文字时撤回这条（`LiveRetraction.message(id)`）。聊天行和打赏本来就带同一个平台 id（D01.11 起），不用补字段；S13 录到的 `rm` 的 `id` 就是 4 s 前那行聊天的 `id`。撤回消息自己不带 id（D01.1：用被撤回的 id 会和原消息在去重闸门里撞键），用户名、文字为空。网站保留那一行、文字换成 `m`（S13 是 `Chat Message Removed by <主播>`）；模型的撤回没有替换文字，界面（M13）直接去掉那一行。
- `cm`：`m.u` 是文字或数字、不为空时撤回这个用户的全部（`LiveRetraction.user(u)`），聊天行和打赏的 `userId` 就是行的 `u`。网站严格比较（数字和文字不相等），这里都按文字比较。
- 其他形状（没有 `m`、`m` 是列表或文字、`id` 为空或是数字、只有 `_id`、`u` 为空或是对象、布尔）都不报。

**通知**

- `system`：行的 `t` 为 `system` 时报一条 `system` 通知，文字是服务端原文：有 `l`（列表）时 `{link}` 换成链接的 `text`（没有 `text` 时为空），有 `ic`（列表）时 `{icon}` 去掉，列表不存在（包括 `null`）时占位原样留着（和网站相同）；按 `\n` 分开的各行去空白后用空格连起来；最后为空的不报。S15 录到的是 `{icon} Multistream Chat has been merged: \n<四个频道>`（`ic` 有、`l` 为 `null`），报成 `Multistream Chat has been merged: <四个频道>`。第 k 个 `{link}` 取 `l[2k+1]`，没有就取 `l[0]`：网站按占位切开后的片段序号取链接，只有一个链接时就是 `l[0]`，两个时顺序和字面相反，这里照网站。
  - 帧的 `c` 为 `b`（只给房管看）不报；`system` 帧里没有类型的行不报（网站不显示没有类型的行），其中的聊天行照聊天报；`z`、`w` 不影响。
  - 聊天帧里的 `system` 行也报成通知（网站按行的类型显示）。这改变了 S11 一组的期望（见“测试”）。
- `raid`：`m` 是对象时报一条 `raid` 通知，文字是服务端的 `m`（去空白）；没有文字时拼成 `<n> 突袭了 <rn>`（`n` 发起方、`rn` 被突袭的频道，和网站的 `senderName`、`receiverName` 相同）；两个名字缺一个就不报。网站在发起方频道的页面上 10 s 后把观众带到被突袭的频道，弹幕层不做。
- `ns`：`m` 是对象时按网站的分支拼句子（网站是英文，这里写成中文，意思照网站；月数 `md` 为假值时是 1，和网站的 `months || 1` 相同）：

| 情况 | 网站 | 通知 |
|---|---|---|
| 订阅 | `sn subscribed to n for md month/s` | `sn 订阅了 n，md 个月` |
| 有等级 `slvl` | `sn activated a Level slvl subscription to n` | `sn 开通了 n 的 slvl 级订阅` |
| 赠送（`sg`） | `sn gifted md month/s subscription to gn` | `sn 赠送给 gn md 个月订阅` |
| 赠送给社区（`sg`，`sc` 有 k 人） | `sn gifted k subscriptions to the Picarto Community for n` | `sn 向 Picarto 社区赠送了 k 份 n 的订阅` |
| 匿名赠送（`sg`、`ag`） | `gn received anonymous gift of md month/s subscription for n` | `gn 收到匿名赠送的 md 个月 n 订阅` |
| 匿名赠送给社区（`sg`、`ag`，`sc` 有 k 人） | `An anonymous gift of k subscriptions to the Picarto Community for n` | `有人匿名向 Picarto 社区赠送了 k 份 n 的订阅` |

  句子要用的名字缺了就不报（网站会显示 `undefined`）。“Click here to see the gift recipients”这类可点的部分不报。
- 通知的用户名、用户 id、消息 id 为空，没有时间，白色。

**历史记录页**：`paginated` 或 `p` 为真的帧，打赏、通知、撤回都不报（网站整帧跳过）；`stream` 帧照旧（D01.11 的行为不变）。

### 与决定的差异

决定只写“采用”，按网站做了；与网站的差别：

| # | 差别 | 原因 |
|---|---|---|
| 1 | `rm` 撤下整行，网站留一行“已删除”文字 | 模型的撤回（D01.1）没有替换文字 |
| 2 | 打赏附言里的 chipmote 不换图片，打赏框的边框颜色不传 | 图片要界面支持（表情图片统一放 A01.1）；帧里没有颜色 |
| 3 | 醒目留言 60 s 后离开醒目留言栏 | 网站没有时长，见上 |
| 4 | `ct` 行没有 `v` 也当打赏 | `ct` 没有录到；网站那样只显示一个名字 |
| 5 | 订阅的句子是中文 | 网站在客户端用英文拼，帧里没有文字；规则是拼句子时用中文 |
| 6 | 突袭不跳转 | 跳转是播放页的行为，不在 B-8 里 |
| 7 | `cm` 的用户 id 数字和文字按同一个比较 | `userId` 是文字 |

### 样本

- **S12-b8-synthetic**（`cases.json`，20 组）：合成帧，字段照上面的网站脚本和录到的形状；名字、id、时间都是编造的。`receivedAt` 是测试注入的“现在”。
- **S13-removed**（2026-09-30 15:26 UTC，频道 syugyobeya）：2 帧，主播在自己的聊天里发了一行，约 4 s 后删掉，服务端发来 `rm`。保留频道的公开名字、id、头像路径（和 S09 保留同播各路主播的信息同一口径）；被删掉的那行文字换成同样长度的合成文字（`scrubbed`：`$.m[0].m`，规则 `content`）。
- **S14-tip**（16:11 UTC，频道 Sparkythechu）：1 帧，一位观众打赏 100 Kudos 并留言。打赏人的 `u`、`n`、头像路径 `i`（路径里的用户 id 一起换）和屏蔽名单 `g` 换成同形同长的合成值；频道的公开名字、id 和留言保留。
- **S15-system**（16:21 UTC，频道 LOITER）：1 帧，频道加入多人同播时服务端发的系统通知，只有同播的四个频道名（公开），没有要换的；紧跟着的白名单、封禁名单帧没有保留。
- 三个录制都没有保存令牌（`handshakes` 里只写了形状），`meta.json` 记了原始行的 SHA-256 和长度、脱敏位置、`tool` 和 `note`；逐帧检查过没有 IPv4、Cookie、会话值，门禁的 `fixture privacy` 通过。录制脚本没有放进仓库。
- 没有实测的部分：`ct` 帧和 `ct` 行、`cm`、`raid`、`ns`、带链接的 `system`、房管专用的 `system`（`c` 为 `b`）、历史记录页里的这几种。字段和含义来自网站脚本，用 S12 的合成帧测试。

### 测试

`test/picarto_test.dart` 从 53 个用例增加到 81 个，`live_danmaku` 共 1337 个，连续跑 3 次都通过；本文件在时间前移 30 天、1 年、5 年时直接运行都通过（打赏的“收到时间”由 `now` 注入，样本时间不和真实时钟比较）。

| 分组 | 用例 | 内容 |
|---|---|---|
| B-8（新） | 28 | S12 的 20 组各一个用例（逐帧对照期望，打赏投影出全部字段，通知和撤回的固定字段在投影里断言），另有一个检查每组都有期望；打赏逐字段（含没有时间时用注入的时钟）；撤回和三种通知逐字段；S13：`rm` 撤回的正是前一行聊天的 id、`cm` 按行的 `u` 撤回、闸门都放过；S14：录到的打赏逐字段，D01.11 时它是普通聊天，在同播的另一个频道里加“打赏给”；S15：录到的系统通知；连接按顺序上报打赏、聊天、撤回、通知（文本帧和二进制帧交替，时钟注入）；多人同播时按参数的频道名判断打赏给谁 |
| 合成帧（S11）对照 v4 | 24（数量不变） | 3 组期望因 B-8 改变，测试里注明 `B-8`：“lines of another type…”里的 `system` 行变成通知；“joins, leaves and other notices…”里 `system`、`raid`、`ns` 三帧变成通知；“a chip tip is not shown…”变成醒目留言（组名是 v4 对照文件的键，保留原名） |

另做了变异检查，下面 18 种改动都会让用例失败：房管专用的 `system` 帧也报、时长改成 30 s、新几种不跳过历史页、`ct` 行必须有 `v`、聊天行的 `v` 不看、`system` 帧里没有类型的行也报、链接按字面顺序取、不加“打赏给”、接收方按大小写比较、没有时间时用真实时钟、不写 `Kudos`、头像不加前缀、撤回带上被撤回的 id、月数缺省为 0、突袭没有文字时不拼句子、`cm` 的数字 id 不认、`{icon}` 不去掉、筹码为负也收。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 醒目留言栏显示打赏、撤回时从列表去掉对应的行、通知单独一行显示 | M13（D01.1“模型追加”） |
| chipmote、表情图片 | A01.1 |
| 突袭后跟随跳转 | 不做（不在 B-8 里） |

### 新增的通用能力、依赖

没有。框架文件、`live_net`、`live_core` 都没有改；醒目留言的 `priceText`、撤回和通知两种消息用的是 D01.1 已经加好的模型。
