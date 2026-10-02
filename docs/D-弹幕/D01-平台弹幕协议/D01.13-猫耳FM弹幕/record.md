# D01.13 弹幕（新增）：猫耳 FM

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/missevan.dart`
  - `MissevanDanmakuConnection`：连接；
  - `MissevanDanmakuProtocol`：游客会话的读取、地址、握手请求头、加入、心跳、解帧、解码，不做 I/O；
  - `MissevanDanmakuFrame`：一帧的解码结果（消息、加入是否被接受、被拒的原因）。
- 参数：`live_core` 的 `MissevanDanmakuArgs`（E02.4 已给出）：房间号 `roomId`、详情里的弹幕地址 `url`、API 请求头 `headers`。进房（`getRoomDetail`）时由详情给出，在播和未开播都给，不多发请求；关注刷新和录制详情不给。本模块没有改 `live_core` 的参数类。
- 升级条目：13-2“猫耳弹幕（归档 v4 已实现）”。v3 没有猫耳弹幕（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 解压：Q01.2 的 `brotliDecode(帧[4:], maxOutput: 帧头的长度)`（[Q01.2](../../../Q-网络和代理/Q01-请求和编码/Q01.2-Brotli解码/record.md)）。
- 样本（都在 `fixtures/missevan/`）：
  - `S05-user-info`：E 从归档复制的游客会话接口录制（`Set-Cookie: FM_SESS`），本模块用它回放会话请求；
  - `danmaku/S06-live`：归档 v4 的真实录制（2026-09-27，房间 246709466，约 45 s，14 行）。帧没有改，本模块加上 v4 解码的冻结输出 `expected.json`。这批帧全是未压缩元块；
  - `danmaku/S07-brotli`：本模块补录（2026-09-28 20:35 UTC，直连，房间 180370487，130 s，25 行），服务端现在发的是真正压缩过的 Brotli 帧，见“样本”；
  - `danmaku/S08-synthetic`：合成帧（`cases.json`，15 组 72 帧），由 `danmaku/synthetic_cases.py` 用参考编码器生成，见“测试”；
  - 三个目录的 `expected.json` 都由 `danmaku/v4_expected.dart` 生成（见“与归档 v4 的对照”）。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/missevan.dart`（`MissevanProtocol`、`MissevanConnector`）、`runtime/socket_connector.dart`、`test/missevan_test.dart`；规格 `spec/sites/missevan.md` 第 7 节；
  - 网站自己的 IM 客户端（2026-09-29 下载的 `s1.hdslb.com/bfs/static/maoer-static/assets/fm/js/bundle.42fe79ce.js`）：加入、应答按 `uuid` 对应、5 s 请求超时、30 s 心跳、帧格式、按房间过滤、重连（见“协议”“连接和时序”）；
  - pure_live_TV `e1cca224`：`lib/platforms/missevan/missevan_site.dart:33` 仍是 `EmptyDanmaku`（注释“Remote danmaku remains absent until its contract is verified”），没有可参考的实现；
  - 2026-09-28 20:20～20:55 UTC（北京时间 29 日凌晨）的只读实测（匿名游客、直连、不登录、不发言），见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），平台只写 `target`、`onOpen`、`onData`、`heartbeatFrame`。换地址、退避、最多 8 次、无消息超时、加入计时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **开始时请求一次游客会话**：
  - 弹幕服务器要 `FM_SESS` Cookie，没有或编造的都在握手时返回 HTTP 403（实测）。用注入的 `LiveHttp` GET `MissevanApi.guestSession`（`fm.missevan.com/api/user/info`），读回答的 `Set-Cookie: FM_SESS`；
  - 请求头是参数里的 API 请求头（`MissevanApi.headers`），不跟随跳转（和平台层的请求一样；跳转会丢掉 Cookie）；
  - 最多 3 次，间隔 0.5 s、1 s，每次最多等 5 s（和 Picarto 取令牌一样）；都拿不到就以 `credentialsUnavailable` 结束，不开连接；三次加间隔最多 16.5 s，短于直播间 20 s 的启动超时（M13）；
  - 本次 `connect` 结束（关闭、换房间）时取消进行中的请求。
- **会话有效 3 天，重连沿用它**，不再请求。每次 `connect` 取一个新的，所以一次观看用不到过期的会话（中途过期的处理见“受阻和限制”）。
- **加入照网站**：连上后发 `{"action":"join","uuid":…,"type":"room","room_id":<数字>}`（文本帧）。服务端按 `uuid` 回答：`code` 为 0 时报 `DanmakuReady`，不是 0 就是被拒。5 s 内没有回答就换连接（框架的加入计时器）。这次 `connect` 加入过之后，重新加入带 `"reconnect":1`（网站这样做）。
- **被拒时换会话**：标为未加入，重新请求游客会话，用 `session.reopen` 换新连接，不提示；每次 `connect` 最多 3 次，第 4 次被拒以 `connectionFailed` 结束，详情写明被拒的码和原因（例如 `Join refused: 500030004 无法找到该聊天室`）。
- **心跳照网站**：每 30 s 发文本 `❤️`，服务端约 50 ms 内回同样的文本。所以无消息超时取框架默认的 max(3 × 30 s, 90 s) = 90 s。服务端在客户端约 120 s 什么也不发时断开（实测），30 s 心跳足够。
- **上报聊天和两种人数**：
  - 聊天（`message`/`new`）和付费弹幕（`message`/`danmaku`，网站把它当作带气泡的飞行弹幕，不是置顶的留言，所以也是聊天）；
  - `room`/`statistics` 的 `score`（热度）报 `popularity`，`online`（此刻在房间里的听众）报 `onlineViewers`。
  - 平台没有醒目留言；礼物、进场、榜单、PK、全站通知都不报（和 D01.2～D01.11 的范围一致，见差异 2）。
- **在线人数的来源改为 `roomRealtime`**：列表和详情只有热度 `score`，`online` 恒为 0（REG-MISSEVAN-002）；真实在线人数只在弹幕的 `room/statistics` 里，约每 2 分钟一条。所以 `audience.dart` 里猫耳一项从 `unsupported` 改成 `roomRealtime`（只改了这一项，并补了注释）。效果：列表卡片在“优先真实在线”时显示待定，进房后由弹幕的在线人数填上；不开这个设置时照旧显示热度。

## 协议

**游客会话**：`GET https://fm.missevan.com/api/user/info`，回答 `{"code":0,"info":{"user":null,"guest":{"user_id":0,"username":""},"websocket":["wss://im.missevan.com/ws"]}}`，响应头 `Set-Cookie: FM_SESS=<值>; max-age=259200`（另有 `FM_SESS.sig`，不需要）。只取 `Set-Cookie` 开头的 `FM_SESS=`，值只收 RFC 6265 的 cookie-octet（它要放进握手的 `cookie` 头）。

**地址**：`args.url`，也就是详情的 `info.websocket[]`（`wss://im.missevan.com/ws?room_id=<房间号>`，T02.U 已检查过）。连接这边再检查一次，因为会话 Cookie 要发给这个主机：

- 必须是 `wss`、主机是 `missevan.com` 或其子域、没有用户信息，否则换成 `wss://im.missevan.com/ws?room_id=<房间号>`；
- 没有 `room_id` 的补上：服务端对没有 `room_id` 的握手回 HTTP 400（实测；游客会话回答里列的正是这种地址）；
- `room_id` 是别的房间的也换掉：服务端拒绝加入地址以外的房间（实测，回 500030004）。

**握手请求头**：API 请求头（`referer`、`origin: https://fm.missevan.com`、UA `Mozilla/5.0`）加 `cookie: FM_SESS=<值>`（请求头里原有的 Cookie 去掉）。服务端只要求 Cookie：不带 Origin 和 Referer 现在也能连（实测），照网站仍然带上；不在乎请求头大小写和 UA，用默认的 `dart:io` 握手，不需要 `connectExactWebSocket`。

**帧**：

- 服务端的消息是二进制帧：第 1 字节 1 表示 Brotli，第 2～4 字节是解压后 UTF-8 的字节数（小端 24 位），第 5 字节起是 Brotli 流。解压后是一个 JSON 对象或对象数组。
- 解压时把帧头的长度作 `maxOutput`：超过就停，结果比它短也丢掉。长度不大于 4、第 1 字节不是 1、流解不开的帧都丢掉（网站同样：`size <= 4` 返回、`t[0] === 1` 才解、长度不等为 null）。UTF-8 坏字节换成 U+FFFD，不丢帧（网站的 `TextDecoder` 默认如此）。
- 文本帧：`❤️` 是心跳回显；其他文本按 JSON 读（网站也这样）。

| `type`/`event` | 含义 | 本实现 | 归档 v4 |
|---|---|---|---|
| `user`/`connect` | 连上后服务端先发，`user_id` 0 表示游客 | 不报 | 不报 |
| `room`/`join`，`uuid` 是这次加入的 | 加入应答：`code` 0 加入（`info.room.status.open` 是否在播），非 0 被拒（`info` 是原因） | 就绪 / 换会话重开 | 不看 `uuid`，任何 `room/join` 都算（差异 3） |
| `message`/`new` | 聊天 | 聊天 | 同 |
| `message`/`danmaku` | 付费弹幕（`price` 钻石），网站作为带气泡的飞行弹幕 | 聊天 | 同 |
| `room`/`statistics` | `score` 热度、`online` 在线听众、`vip` 贵族数；约每 2 分钟 | 热度和在线人数 | 同 |
| `gift`/`send` | 礼物 | 不报（差异 2） | 礼物 |
| `gift`/`cross_send` | 团播里送给另一个房间的礼物 | 不报 | 不报 |
| `member`/`join_queue`、`creator`/`new_rank`、`global_pk`/*、`question`/*、`notify`/*（全站通知，常是别的房间）等 | 进场、榜单、PK、付费提问、通知 | 不报 | 不报 |
| 文本 `❤️` | 心跳回显 | 不报 | 不报 |

对象带 `room_id` 且不是本房间的跳过（网站同样跳过，v4 也是）；没有 `room_id` 的算本房间。

聊天的字段：

| `LiveMessage` | 取值 | 与归档 v4 |
|---|---|---|
| 类型 | 聊天 | 同 |
| 文本 | `message` 去首尾空白；文字或数字，空的不报 | v4 把任何值转成文字（列表显示成 `[x]`，差异 4） |
| 用户名、用户 id | `user.username`、`user.user_id`，文字或数字照写，其他为空 | v4 把任何值转成文字 |
| 消息 id | `msg_id`，不加前缀 | v4 加 `missevan:`（差异 1） |
| 时间 | `time`（毫秒，网站读的字段）；不是正整数或超出 `DateTime` 范围时为空。录到的聊天都没有 `time` | v4 另读 `create_time`，超出范围时整行丢失（差异 5） |
| 颜色 | 白色（平台没有文字颜色；`bubble.text_color` 是贵族气泡上的字色） | 同 |
| 等级 | `titles` 里 `type` 为 `level` 的 `level` | 同 |
| 粉丝牌 | `titles` 里 `type` 为 `medal` 的 `name`、`level` | 名字不是文字时 v4 整行丢失（差异 4） |

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网站 | 依据 |
|---|---|---|---|---|
| 开始前的请求 | 游客会话 1 个，失败时共 3 次（间隔 0.5 s、1 s，每次 5 s 超时，不跟随跳转） | 1 个，失败即结束 | 页面自带 Cookie | 差异 14 |
| 地址 | 详情的 `websocket`，检查主机、补 `room_id` | 详情的，任何 `wss` 都用 | 详情的 `room.websocket`，有多个时随机选 | 实测 400、500030004；差异 7 |
| 握手请求头 | API 请求头加 Cookie；默认握手 | Cookie、Origin、Chrome UA | 浏览器 | 实测；差异 8 |
| 加入 | 打开后发 join（文本）；`uuid` 相同且 `code` 0 就绪，已就绪时不再报；重新加入带 `reconnect: 1` | 发二进制；任何 `room/join` 的 `code` 0 都算 | 文本；按 `uuid` 对应；重新加入带 `reconnect: 1` | 网站脚本；录制；差异 9、10 |
| 加入超时 | 5 s，超时直接换连接（框架默认，不单独提示；框架自己的重连提示照常） | 8 s | 5 s（510010002“IM 请求超时”），然后关掉重连 | 网站脚本；差异 11 |
| 心跳 | 30 s，文本 `❤️`，连上就按间隔发；手动 `heartbeat()` 同样 | 30 s，二进制，加入后才开始 | 30 s（`IMHeartbeat`），已连接时 | 录制；实测回显约 50 ms；差异 9、12 |
| 无消息超时 | 90 s（max(3 × 30 s, 90 s)，策略里不单独写） | 90 s | 没有（靠 `onclose`） | 实测：客户端不发心跳约 120 s 被断开 |
| 断线重连 | 框架默认：只有一个地址，间隔 2、3、4、5、6、6、6、6 s，第 9 次失败结束；收到任何消息清零（每次连上服务端先发 `user/connect`）；一轮只提示一次；沿用会话 | 退避相同，沿用会话 | 每次 1 s，最多 5 次（主播端不限） | D01.1 |
| 被拒 | 标为未加入、换会话、`reopen`，不提示；每次 `connect` 最多 3 次，第 4 次 `connectionFailed` | 换会话后按退避重连并提示，超过 3 次以 `rejected` 结束 | 关掉，1 s 后用同一 Cookie 重连 | 差异 13 |
| 结束原因 | 拿不到会话、被拒后拿不到新会话：`credentialsUnavailable`；房间号不对：`connectionFailed`（不发请求）；第 4 次被拒：`connectionFailed`；重连用尽：`reconnectsExhausted` | `credentials`、`rejected`、`maxRetries` | — | D01.1 的类型；差异 15 |
| 帧解不开 | 丢掉这一帧，不影响连接 | 同 | 同 | — |
| 诊断文字 | 握手失败时是 `dart:io` 的错误（地址不含会话值）；Cookie 不进任何事件 | — | — | — |
| 代理 | 按平台 `missevan` 取路由（构造参数 `proxy`） | 同 | — | — |

`room/statistics` 的时刻：一次 300 s 的实测在加入后 39 s、159 s、279 s（间隔 120 s）；其他几次连接的第一条分别在 15 s、65 s、115 s；S06 在 42 s，S07 在 46 s。所以进房后最迟约 2 分钟才有第一个真实在线人数，在此之前界面只有列表或详情的热度（见“放到其他模块的部分”）。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.missevan: () => MissevanDanmakuConnection(http: http, proxy: proxyPolicy),
  // …
});
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `http` | 是 | 请求游客会话用的 `LiveHttp`，就用给 `MissevanSite` 的那个（按平台 id `missevan` 取代理路由和限流） |
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `missevan` 取路由 |
| `connector` | 否 | 只给测试替换握手；默认 `dart:io` |
| `sessionRetryDelay` | 否 | 只给测试缩短会话重试的间隔 |
| `random` | 否 | 只给测试固定加入的 `uuid` |

不需要 Cookie 或设置：v3 的猫耳全程匿名（E02.4 没有它的 Cookie），弹幕用每次现取的游客会话，不存进 CookieVault。

## 与归档 v4 的对照

对照方式：

- `fixtures/missevan/danmaku/v4_expected.dart` 把归档 v4 的 `MissevanProtocol`（`session`、`headers`、`join`、`heartbeat`、`endpoint`、`text`、`decode`）原样搬进一个独立程序，另记下 `MissevanConnector` 的会话请求头。只替换了它从别处引用的东西：
  - 事件类型（`DanmakuChat`、`DanmakuGift`、`DanmakuOnline`、`AudienceKind`）和 `DecodeContext`、`FrameResult`，删到只剩解码会填的字段；
  - `package:brotli`（0.6.0 在 Dart 3.13 上解析不了依赖）换成 live_net 的 `brotliDecode`。Q01.2 已用参考解码器核对过它（包括 S06 的 10 个帧），合法的流两者解出同样的字节。
- 它对 S06、S07 写下房间、加入的 `uuid`、S05 的游客会话值、会话请求头、地址、握手请求头、加入和心跳，以及每个收到的帧：二进制帧能否读出文字、是否加入或被拒、解出的事件；对 S08 写下每组每帧的同样内容。运行：在仓库根目录 `dart run fixtures/missevan/danmaku/v4_expected.dart`，`generator` 字段写明来源。
- 测试把新代码的 `LiveMessage` 投影成 v4 的形状（消息 id 补回 `missevan:` 前缀，等级和粉丝牌换回数字），逐帧比较；有意的差异在测试里逐组写明：先断言 v4 的输出，再断言新代码的。

| 对照 | 结果 |
|---|---|
| 游客会话 | S05 的 `Set-Cookie` 读出同一个值；`FM_SESS.sig` 在前也一样 |
| 地址 | S04 详情、S06 和 S07 录下的握手地址与 v4 相同 |
| 加入、心跳 | 与 S06（二进制）、S07（文本）录下的逐字节相同，与 v4 相同 |
| S06 的 11 个收到的帧 | 一致：加入 1 次、3 条聊天（名字、用户 id、文本、等级、粉丝牌；id 只差前缀）、热度 105019 和在线 22；别的房间的全站礼物通知不报 |
| S07 的 19 个收到的帧 | 一致：加入 1 次、9 条聊天、热度 6374 和在线 9；进场、榜单、4 次心跳回显不报 |
| S08 的 15 组 72 帧 | 10 组一致；5 组是有意差异（差异 2～5），见下 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 消息 id 不加 `missevan:` 前缀 | 与 D01.2～D01.11 一致：去重闸门按房间内的 id 比较 |
| 2 | 不上报礼物（`gift`/`send`） | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），D01.2～D01.11 也都不报。v4 报，价格单位是钻石 |
| 3 | 只认这次加入的 `uuid` 的应答 | 网站按 `uuid` 把应答对应到请求；v4 任何 `room/join` 都算。录制里的应答都带 `uuid`，看不出区别 |
| 4 | 文本是列表或对象时不报；粉丝牌名不是文字时只丢名字 | v4 把列表显示成 `[x]`；粉丝牌名用 `as String?` 强制转换，出错时整行丢失 |
| 5 | 时间超出 `DateTime` 范围只让这一行没有时间；不读 `create_time` | v4 抛 `RangeError`，整行丢失（统一原则“一行坏数据只跳过这一行”）。网站只读 `time`，`create_time` 没有出处 |
| 6 | 解压以帧头的长度为上限 | 问题 1 |
| 7 | 地址只认 `missevan.com` 的主机，没有 `room_id` 的补上，别的房间的换掉 | 问题 2；实测 400、500030004 |
| 8 | 会话请求和握手都带 API 请求头（Referer、Origin、UA `Mozilla/5.0`） | 和平台层的请求一致（E02.4 照 v3 用 `Mozilla/5.0`）；实测服务端接受。v4 会话请求是 Chrome UA + Referer，握手是 Cookie、Origin、Chrome UA |
| 9 | 加入和心跳用文本帧 | 网站这样发；v4 发二进制，内容相同，服务端两种都收（v4 规格 7.2，本次实测文本） |
| 10 | 重新加入带 `reconnect: 1` | 网站这样做 |
| 11 | 加入超时 5 s | 网站的 IM 请求超时；v4 是运行时默认的 8 s。实测加入应答在 60～90 ms 内到 |
| 12 | 心跳从连上起按间隔发 | 框架的做法（D01.1）；服务端在加入前也回显。v4 加入后才开始 |
| 13 | 被拒后换会话立刻重开，不提示；第 4 次被拒以 `connectionFailed` 结束 | 和哔哩哔哩、Picarto 换凭据一样；v4 换会话后还要按退避等待并提示重连 |
| 14 | 会话请求失败时再试两次（0.5 s、1 s），每次 5 s 超时，不跟随跳转 | 一次网络抖动就让这个房间没有弹幕，直到重新进房；间隔照 Picarto。跳转会丢 `Set-Cookie` |
| 15 | 结束原因用 D01.1 的类型 | v4 的 `credentials`、`rejected`、`maxRetries`；界面文字由 M13 给出 |

没有改的地方：

- 会话接口、会话 Cookie 的读法（只取 `FM_SESS`）、地址的形式、加入的内容、30 s 心跳与 v4 相同，服务端接受过（两次录制）。
- 帧格式的检查（标志 1、长度相符）、别的房间跳过、没有 `room_id` 算本房间、人数的读法（整数或数字文字，不小于 0）、等级和粉丝牌的读法与 v4 相同。
- 时间用本地时区的 `DateTime`（同一时刻），和其他平台一样。

## 审查发现的归档 v4 问题

| # | 问题 | 位置（归档 v4） | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 一帧的帧头写着几百字节，Brotli 流却能解出很大的数据（“解压炸弹”）时，v4 先全部解完再比长度，内存跟着涨 | `MissevanProtocol.text` | `brotli.decode` 没有上限；长度检查在解完之后 | 按帧头的长度设 `maxOutput`，超过就停（差异 6；Q01.2 的接口正为此设计） |
| 2 | 详情里任何 `wss` 地址都会收到会话 Cookie；没有 `room_id` 的地址握手必然 400 | `MissevanConnector.plan` | 只检查了 scheme | 只认猫耳的主机、补 `room_id`（差异 7；T02.U 的参数已先检查一次） |
| 3 | 一行的时间超出范围或粉丝牌名不是文字时整行丢失 | `_chat` | 没有逐字段容错 | 差异 4、5 |
| 4 | 被拒后要等退避并提示“正在重连”，其实马上就能用新会话重开 | `runtime/socket_connector.dart` 的 `rejected` 分支 | 被拒和断线走同一条重连路径 | 差异 13 |

## 实测

2026-09-28 20:20～20:55 UTC，只读、匿名游客、直连，没有登录，没有发言。

- 探测（自写的小程序，`dart:io` 的 WebSocket 加 Q01.2 的解码器）：
  - 不带 Cookie、带编造的 `FM_SESS`：握手 HTTP 403；带会话但不带 Origin 和 Referer：能连上、能加入；
  - 地址没有 `room_id`：握手 HTTP 400；
  - 加入不存在的房间（1）、加入地址以外的房间：都回 `{"type":"room","event":"join","uuid":…,"code":500030004,"info":"无法找到该聊天室"}`，连接不断；
  - `room_id` 用文字也能加入；未开播的房间（S04-offline 的 507069668）也能加入，应答 `open: 0`；
  - 连上后服务端先发 `user/connect`，加入应答在 60～90 ms 内到；
  - 每 30 s 发 `❤️`，服务端约 50 ms 内回 `❤️`（文本帧）；客户端不发心跳时约 120 s 被断开（1006）；
  - 在播房间 300 s：`room/statistics` 在 39 s、159 s、279 s，间隔 120 s；
  - 服务端现在的帧都真正压缩过（例如 143 字节的加入应答压到 117、101 字节），S06（09-27）录到的全是未压缩元块。
- 用本实现（`MissevanSite` 进房取参数，`IoLiveHttp` + 默认握手）连了两个房间：
  - 推荐里热度最高的 869222422，150 s：383 ms 就绪，一直没有重连，115 s 收到热度 21514、在线 10，没有人发言；
  - 180370487，130 s：369 ms 就绪，11 条聊天（等级、粉丝牌都有），65 s 收到热度 414、在线 6；关闭后状态为 `idle`。
- 网站脚本（见“参考”）：连接前 `createWebSocket` 随机选一个地址；`joinRoom` 发 `{action:"join",uuid,type:"room",room_id}`，重连时加 `reconnect:1`；请求 5 s 没有应答就以 510010002 失败，关掉重连；`onMessage` 跳过 `❤️`、长度不大于 4 的帧、标志不是 1 或长度不符的帧；带 `room_id` 且不是当前房间的消息丢掉（全站通知和团播 PK 的例外，这两类本实现本来就不报）；重连间隔 1 s，观众端最多 5 次。

## 样本

- **S07-brotli**（房间 180370487，130 s，25 行：会话接口的回答、加入、19 个收到的帧、4 次心跳）：
  - 录制用自写的 `dart:io` 小程序：游客会话、加入、每 30 s 心跳，别的什么也不发；加入的 `uuid` 由录制程序指定为 `00000000-0000-4000-8000-000000000001`，不是随机值；
  - 握手的 Cookie 记为 `<redacted>`，`Set-Cookie` 没有录进帧；
  - 服务端自己的 4 个帧（`user/connect`、加入应答、`creator/new_rank`、`room/statistics`）里没有个人信息，原样保留；
  - 11 个帧提到了用户（聊天和进场）：解开后把 `user_id` 换成同样位数的其他数字、`username` 换成 `观众N`、头像路径 `iconurl` 逐字换成同形的字母和数字（同一个人换成同一组值），再用参考编码器按服务端声明的窗口重新压缩，帧头的长度随之更新；这些帧的序号记在 `meta.json` 的 `reencoded`；
  - 逐帧解开检查过：没有 IPv4 地址、Cookie、会话值；原值都不在输出里（脚本自查）；门禁的 `fixture privacy` 通过。消息 id、聊天文字、主播的粉丝牌名、公开的装扮图片地址保留，和 S06 的口径相同；
  - `meta.json` 记了原始录制的 SHA-256 和长度、脱敏位置、`reencoded`、说明（`note`）。录制和脱敏脚本没有放进仓库，`tool` 写明了。
- **S06-live**：帧没有改，只加了 `expected.json`。它的 `uuid`、用户、头像路径是归档录制时换过的合成值。
- **S08-synthetic**：名字、id、时间都是编造的；`plain` 字段给出每个 Brotli 帧的内容，便于阅读。

## 回归条目的覆盖

- REG-MISSEVAN-002（热度不是在线人数）：弹幕的 `score` 报热度、`online` 报在线，分开上报，有测试；`audience.dart` 改成 `roomRealtime`，有测试。
- 其余 001、003～005 属于平台层（E02.4）。归档规格第 7 节没有弹幕的回归条目。

## 受阻和限制

没有受阻的部分。

限制：会话在一次连接中途失效（握手变成 403，例如连续挂着超过 3 天）时，框架没有“握手被拒”的钩子，只能按普通断线重连，8 次后以 `reconnectsExhausted` 结束；重新进房会取新会话。每次 `connect` 都取新会话，正常观看遇不到。要处理需要框架在握手失败时把原因交给平台（见候选 4）。

## 后续升级候选（由用户决定）

| # | 内容 | 现状 | 依据 |
|---|---|---|---|
| 1 | 付费提问（`question`/`ask`，带钻石价格）显示为醒目留言 | 已做（D01 后续升级（原 M5.F），B-9） | 网站放在单独的提问面板里；醒目留言要显示时长和价格单位，需要 M13 定 |
| 2 | 管理员清屏（`admin`/`message_clear`，带 `msg_ids`）从弹幕列表撤下 | 已做（D01 后续升级（原 M5.F），B-9） | 网站脚本；和 Twitch、Picarto 的撤回候选一起由 M13 支持 |
| 3 | 显示礼物、贵族开通、PK 等 | 已做（D01 后续升级（原 M5.F），B-9）：贵族开通、PK 显示为通知，礼物上报；礼物的显示归 B-21（M13） | 与其他平台一起由 M13 决定 |
| 4 | 握手被拒（会话失效）时换会话重连 | 已做（D01 后续升级（原 M5.F），B-1） | 需要框架（D01.1）加钩子，见“受阻和限制” |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表） |
| 用 `onlineViewers` 更新房间的在线人数；进房后最迟约 2 分钟才有第一个值，之前按 `AudienceRankKey` 的“待定”处理；人数设置页（v3 `audience_metric_settings_page.dart:20` 写着猫耳只有热度）现在可以选“真实在线” | M13 |
| 弹幕操作菜单：v3 在 `userLevel` 非空时显示 `Lv.x`（`danmaku_message_actions.dart:19`），猫耳的消息现在带等级，会显示出来 | M13（v3 的这段界面原样保留即可） |
| 多画面弹幕（v3 不支持猫耳）是否接入 | 已完成（N01.1：多画面按弹幕登记接入所有有弹幕的平台，[记录](../../../N-多画面和投屏/N01-多画面/N01.1-多画面/record.md)） |
| 上面的候选 | M13、D01.1 |
| `live_core` 的 `LiveDanmaku`、`MissevanSite.getDanmaku()`（仍是 `EmptyDanmaku`） | D01 各平台完成后删除 |

## 新增的通用能力、依赖

没有。框架文件没有改；`live_danmaku.dart` 按字母顺序加了一行导出；没有新依赖（Brotli 用 Q01.2 的 `brotliDecode`）。

`live_core` 只改了 `audience.dart` 里猫耳一项，以及钉着旧值的一条断言：`test/sites/missevan_api_test.dart` 的 REG-MISSEVAN-002 用例原来断言列表卡片“不支持真实在线”、偏好真实在线时仍显示热度 88900；现在是支持、偏好真实在线时显示待定（空，等弹幕的在线人数），不偏好时仍是热度 88900，和同为 `roomRealtime` 的 KilaKila 一样。

## 测试

`test/missevan_test.dart` 54 个用例，`live_danmaku` 共 666 个，连续跑 3 次全部通过；`live_core` 3398 个全部通过。另做了变异检查，下面每一种改动都会让对应的用例失败：不看应答的 `uuid`（v4）、心跳改成 60 s、加入超时改成 8 s（v4）、不补 `room_id`、不检查主机（v4）、重新加入不带 `reconnect`、会话请求跟随跳转、被拒后只重连不换会话、不检查解压后的长度、不按房间过滤、人数可以为负、会话只请求一次（v4）、被拒不限次数、不替换请求头里的 Cookie、不报付费弹幕、文本不去空白、不填等级、关闭时不取消会话请求、把 `FM_SESS.sig` 当成会话、心跳发二进制（v4）、重复的应答再报一次就绪。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 9 | S05 的游客会话与 v4 相同、各种不合格的 `Set-Cookie`；地址与 S04 详情、S06/S07 的握手和 v4 相同；补 `room_id`、换掉别的主机、scheme、房间、用户信息、坏的查询；握手请求头与 S07 录下的相同、替换原有 Cookie；加入与 S06（二进制）、S07（文本）逐字节相同、`reconnect`、`uuid` 的形式；心跳与录制和 v4 相同、回显不报；聊天和人数填满消息模型；`audience.dart` 是 `roomRealtime`、详情的 `online` 为 0；帧的标志、长度、截断、多余字节 |
| 录制帧对照 v4 | 4 | S06、S07 逐帧与 v4 一致；S06 的加入、3 条聊天、热度和在线、别的房间的通知；S07 服务端自己的帧确实压缩过且能完整解开，9 条聊天、热度和在线 |
| 合成帧（S08）对照 v4 | 17 | 15 组各一个用例（5 组按差异 2～5 变换）；另有一个检查每组都有 v4 输出、每条差异都对应一组；一个检查被拒的码和原因 |
| 连接 | 24 | 用 S05 回放取会话：请求的地址、请求头、不跟随跳转、超时；握手地址和带 Cookie 的请求头、直连；加入的内容；应答前不就绪、应答后就绪、重复应答不再报；回放 S06、S07 得到 v4 的 5 条和 11 条（录下的应答不是这个连接的）；只报本房间、别人的应答不算；时序（30 s、90 s、5 s、8 次）；30 s 定时和手动心跳、关闭后不发；代理路由；参数的地址检查和房间号去空白；房间号不对时 `connectionFailed` 且不发请求；会话 3 次（0.5 s、1 s）后成功；4 种拿不到会话的情形（没有 Cookie、302、403、传输失败）都是 `credentialsUnavailable` 且不开连接；取会话时关闭会取消请求、没有事件；加入 5 s 没有应答换连接、新的 `uuid`；断线 2 s 后用同一会话重连、带 `reconnect: 1`、就绪两次；被拒后换会话立刻重开、不提示；第 4 次被拒结束并写明原因；被拒后拿不到新会话结束；被拒次数按 `connect` 计；退避 2、3、4、5、6、6、6、6 s 后放弃、详情不带会话值；关闭后没有事件和心跳；换房间取新会话、旧连接的消息和拒绝都不起作用；参数类型；平台表登记；本地 WebSocket 服务器端到端（查询参数、Cookie、Origin、加入、S07 的真实压缩帧、心跳回显） |

没有用到样本时间与“现在”比较的逻辑（会话的过期时间不读，聊天的 `time` 只换算不比较），`tools/timeshift/run.sh 30 1825` 全部 ok。

## 后续升级（D01 后续升级（原 M5.F），附录 B-1、B-9）

- 日期：2026-09-30～10-01
- 条目：B-1（握手被拒时换会话，本记录候选 4；框架的钩子见 [D01.1](../D01.1-弹幕框架和过滤/record.md) 末节）、B-9（候选 1～3）。
- 依据：网站脚本（“参考”里 2026-09-29 下载的 `bundle.42fe79ce.js`，下面引用的是其中的函数名）和新录的样本 `danmaku/S09-events`（见“样本”）。

### B-1：握手被拒时换会话

- 连接实现框架新加的 `onHandshakeFailure`：握手回 HTTP 403（实测：会话无效或没有会话时服务端的回答）或 401（同样处理）时，重新请求游客会话（和开始时一样：最多 3 次，间隔 0.5 s、1 s，每次最多 5 s，不跟随跳转），把新的 `FM_SESS` 交给下一次握手。
- 重连仍走框架的退避：这一轮第一次失败时照常报一次 `DanmakuReconnecting`，2 s 后重连；下一次握手等会话请求结束再发，所以一定带新 Cookie。
- 每轮连续失败只换一次会话，连接打开过才重新计：新会话仍被拒说明不是会话的问题（例如整个地址被封），照常退避，8 次后 `reconnectsExhausted`，不再反复请求。
- 拿不到新会话：以 `credentialsUnavailable` 结束，和加入被拒后拿不到会话一样。
- 其他握手失败（连不上、超时、400、404、5xx、升级头不对）不换会话，行为和以前相同。
- 用户看到的变化：连续挂着超过 3 天、会话过期时，弹幕断一次（一条“正在重连”），约 2 s 后用新会话接上；以前要重试 8 次（约 40 s）后结束，只能重新进房。

### B-9：付费提问、清屏、通知、礼物

| 服务端消息 | 现在 | 以前 |
|---|---|---|
| `question`/`ask` | 醒目留言 | 不报 |
| `admin`/`message_clear` | 撤回 | 不报 |
| `noble`/`registration`、`renewal`、`cross_registration`、`cross_renewal` | 通知（`system`） | 不报 |
| `pk`/*、`global_pk`/*（幻影 PK）、`team_pk`/*，以及其中的花神赐福（`raid`） | 通知（`system`） | 不报 |
| `gift`/`send` | 礼物（`MissevanGift`，界面暂不显示） | 不报 |
| `question`/`answer`、`gift`/`cross_send`、`super_fan`/*、`notify`/*、进场、榜单等 | 不报 | 不报 |

**付费提问 → 醒目留言。**录到的形式（S09 第 2 帧）：外层 `user` 是提问的人，`question` 是 `question_id`、文字 `question`、`price`（钻石）、`created_time`（毫秒）、`status` 和提问人的副本（`user_id`、`username`、`iconurl`）。S08 里那一组合成的提问用的是网站 store 里的形状（`content`），和服务端发的不同，所以那一组仍然不报。

| `LiveSuperChatMessage` | 取值 |
|---|---|
| `messageId` | `question_id`（外层 `LiveMessage.messageId` 同样填） |
| 用户名、头像 | `user.username`、`user.iconurl`，没有时用 `question` 里的；头像只收 https（`//` 开头的补 `https:`） |
| 文字 | `question.question` 去首尾空白，空的不报 |
| `price` | `question.price`（整数或数字文字，不小于 0；没有、负数、小数不报） |
| `priceText` | `50 钻`：网站的提问面板（“出价 50 钻”“当前最高价为 50 钻”）和收益记录（“×50 钻”）都这样写 |
| `startTime` | `created_time`；没有时用收到的时间（`now` 可注入）。外层 `sentAt` 只在有 `created_time` 时填 |
| `endTime` | 开始后 60 s |
| 颜色 | 平台不给，留空字符串 |

- 显示时长：网页没有。提问进房间的“提问”面板排队（`eO`、`IL`），直到主播回答或取消（`question`/`answer` 的 `answer_type` 是 `join`、`finish`、`cancel`）。选 60 s：哔哩哔哩醒目留言最低一档的时长；录到的提问是 50、52、100 钻（5～10 元），都低于哔哩哔哩的最低档（30 元），所以不按金额分档。
- 外层 `LiveMessage` 的用户名和文字照 3.x 醒目留言的写法填 `SUPER_CHAT_MESSAGE`（和哔哩哔哩、斗鱼一致），用户 id 是提问人的。
- 回答、取消不报：模型没有“提前结束醒目留言”，网站也只是把问题在面板里挪动。

**管理员清屏 → 撤回（未实测）。**网站的转换（`admin` 只取 `message_clear` 的 `opt`、`msg_ids`）和聊天列表（`opt` 为 `All`=1 时去掉所有 `type` 为 `message` 的行，为 `Specific`=2 时去掉 `id` 在 `msg_ids` 里的行；聊天行的 `id` 就是 `msg_id`）：

- `opt` 1：一条 `LiveRetraction.all()`；
- `opt` 2：`msg_ids` 里每个 id 一条 `LiveRetraction.message(id)`，重复的只报一次，空的跳过，数字照写成文字；`msg_ids` 不是列表时不报；
- 其他 `opt`（包括没有）不报；`opt` 是数字文字也认；
- 撤回消息本身没有平台给的 id，`messageId`、文字、用户都为空（不会和原消息在去重闸门里撞键）；
- 聊天本来就带 `msg_id`（D01.13），不用补字段。
- 两批录制的 60 个房间会话里都没有出现，用合成帧测。

**贵族开通 → 通知。**网站聊天行（`Kue`）以开通者口吻写“我开通了神话贵族”，团播里给另一位主播开通（`cross_*`）写“我开通了主播乙的神话贵族”。通知改成第三人称：`观众甲 开通了神话贵族`、`观众甲 续费了主播乙的神话贵族`（主播名取 `room.creator_username`，没有就省略；没有用户名时是 `开通了神话贵族`）。`noble.name` 为空或不是对象时不报。通知带开通者的用户名、用户 id 和 `time`。录到一条本房间的续费（S09 第 25 帧，`观众9 续费了大咖贵族`）；开通和团播的用合成帧。

**PK → 通知。**猫耳在聊天里显示三种 PK 的行：

| 消息 | 网站的行 | 本实现 |
|---|---|---|
| `pk`（随机、邀请 PK） | 观众看到的本地系统消息（`lAe`）：`match_start` “主播正在匹配 PK 对手，请耐心等候”；`match_success` “PK 已开始，快送礼支持主播吧”；`finish`、`close` 按 `pk.result`（1 “恭喜主播获得 PK 胜利，继续支持主播吧”、0 “主播 PK 失败，再接再厉哦”、2 “主播 PK 平局，再接再厉哦”）；`invite_refuse` “对方未接受邀请”；`invite_timeout` 只在发出邀请的房间（`pk.from_room_id`）显示同一句 | 相同。没有 `result` 的 `close`（录到的都没有）、`match_fail`（观众看不到文字）、`punish_finish`、`update` 等不报 |
| `global_pk`（幻影 PK，平台每半小时自动匹配） | “PK 小助手”行（`YR`、`sfe`）：有 `pk.message_tip` 显示它，否则按事件的固定文字（`match_ready` “幻影 PK 即将开启，准备迎战！”等，`finish` 按 `result`）；`update` 只有带提示时才有行 | 相同。网站对没有文字的事件（`close`、`punish_finish`、`mute` 等）显示一句空洞的“PK 小助手提示”，不报。录到的 `match_ready`、`match_start`、`match_success`、`match_skip`、`finish` 都带提示 |
| `team_pk`（团播 PK） | 有 `pk.message_tip` 时一行（`KR`） | 相同（未实测） |
| 花神赐福（上面两种消息里的 `raid.progress.message_tip`） | `match_success`、`update`、`finish`、`close` 带它时另起一行（`UR`） | 相同；`pk` 先赐福行后 PK 行，`global_pk` 先 PK 行后赐福行，和网站添加的先后一致 |

- 提示是 HTML（`<img>`、`<font color>`）：去掉灰色（`#BDBDBD`）的“详情”“结算详情”“对局详情”“去祈福”（网站上是可点的链接提示，应用里点不了），去掉图片和其他标签（`<br>` 换成空格），解码实体，连续空白合成一个空格。例：`恭喜胜利！你在幻影PK中击败 观众7 实力出众！`。
- 幻影 PK 的提示是主播口吻（“你在幻影PK中击败……”），网站给观众看的也是这句，照原文。
- 数量：两批录制里，每个房间每半小时大约 3～4 行（开启、匹配中、匹配成功、结果），随机 PK 另有开始、结果和赐福各一行。

**礼物 → gift（界面暂不显示）。**`gift`/`send` 报成 `LiveMessageType.gift`，`data` 是 `MissevanGift`（照 `BaiduLiveGift` 的写法）：

- `id`（`gift_id`）、`name`、`count`（`num`，至少 1）、`price`（单价，钻石，不小于 0；免费礼物是 0）、`icon`（`icon_url`，只收 https）；
- 幸运礼物：网站写“送给主播 悠闲假日 ×1，抽出 书写星辰 ×1”，`lucky` 是送出的那件、`gift` 是抽出的那件，所以 `gift` 填本身、`lucky` 填 `luckyGift`；
- 文字 `书写星辰 ×1`，用户是送礼人，时间是 `time`（毫秒）；
- `messageId` 是 `oid`；连击的后几次 `oid` 全是 0（网站同样只在有非 0 字符时用它），这时不填；
- `gift`/`cross_send`（团播里送给另一个房间）仍不报。
- 与归档 v4 的差异 2（不报礼物）随之取消：S08 里两组带礼物的合成帧现在和 v4 的输出相同。

### 与决定的差异

- B-1：决定只写了“换会话重连”。另外定了每轮失败只换一次、拿不到会话即结束（理由见上），并且只认 401、403。
- B-9：
  - 醒目留言的时长网页没有，选 60 s（理由见上）；
  - 清屏“全部”用 `LiveRetraction.all()`，按模型是撤回所有已显示的消息，比网站多清了通知这类非聊天行（界面实现时可以只清聊天，见“放到其他模块”）；
  - PK 的空洞行“PK 小助手提示”不报；
  - 除了 PK 结果，还显示了网站在 PK 期间写进聊天的花神赐福行和团播 PK 行，都是同一类通知；
  - 提问的回答、取消不影响已经显示的醒目留言。

### 样本

- **S09-events**（新，26 帧）：2026-09-30 北京时间 23:14 和 23:26 两批只读录制（匿名游客、直连、不登录、不发言），`record_many.dart` 连推荐列表的前 30 个房间，分别 900 s、840 s，只发加入和心跳。从其中 10 个房间会话（7 个房间）挑出：提问和回答、一场随机 PK 从匹配到结束（含两条赐福）、幻影 PK 从开启到结果（含胜、负逃跑、跳过）、礼物（普通、连击、幸运礼物、团播送给别的房间）、一条贵族续费、一条超粉续费，以及前后的聊天。每行多了 `batch` 和 `room`（这个文件跨房间），`t` 是那条连接打开后的毫秒数。
- 两批录到的数量（60 个房间会话）：聊天 4886 条，`gift`/`send` 1147，`question`/`ask` 7、`answer` 8，`pk`/* 159（多为 `update`），`global_pk`/* 1000 左右（多为 `update`），`noble`/`renewal` 1，`admin`/`message_clear` 0。用本实现逐帧解了全部录制：聊天 4886、礼物 1147、醒目留言 7、通知 134、人数 730，没有异常。
- 脱敏：每帧解开后，`user_id`、`creator_id` 换成同位数的其他数字，`username`、`creator_username`、`creator_name` 换成 `观众N`（提示和聊天文字里出现的同名一起换），头像 `iconurl`、`creator_iconurl` 保留协议、主机和第一级目录，其余逐字换成同形的字母和数字；平台账号“PK小助手”、房间号、房间标题、粉丝牌名、消息和礼物的 id、礼物和装扮图片地址保留（和 S07 的口径相同）；握手的 Cookie 没有录进帧。然后用参考编码器按服务端声明的窗口重新压缩，26 帧都在 `reencoded` 里。脚本自查原值都不在输出里；门禁的 `fixture privacy` 通过。`meta.json` 记了原始帧的 SHA-256 和长度、两批的时间、脱敏位置；录制和脱敏脚本没有进仓库，`tool` 写明了。
- 未实测（只用合成帧）：清屏、贵族开通（`registration`）和团播的 `cross_*`、`team_pk`、随机 PK 的邀请被拒或超时和负、平的结果、不带提示的幻影 PK 事件。

### 测试

`test/missevan_test.dart` 71 个（原 54 个，新增 17 个：B-9 11 个，B-1 6 个）；框架 `test/socket_connection_test.dart` 新增 8 个（见 D01.1 末节）；`live_danmaku` 共 1334 个，连续跑 3 次全部通过。

| 分组 | 用例 | 内容 |
|---|---|---|
| B-9 | 11 | S09 的 26 帧逐帧与网站显示的一致，放到别的房间都不报；醒目留言的每个字段（id、用户、头像、文字、价格和价格文字、开始和结束、颜色）；提问的边界（提问人两处来源、没有时间用收到的时间、数字文字的价格、免费、非 https 头像、时间越界、空文字、价格缺失或为负或为小数、不是对象，回答等事件不报）；清屏（聊天带着被清的 id、按 id 撤回并去重、全部、`opt` 是文字、各种坏数据、别的房间）；贵族（录到的续费每个字段，开通、团播、没有主播名、没有用户名、坏数据）；随机 PK（负、平、文字的结果、未知结果、邀请被拒、超时只在邀请方、不显示的事件、赐福行的先后和事件范围）；幻影 PK（各事件的固定文字、按结果、提示优先、空洞事件不报、不认识的事件、赐福行在后）；团播 PK；提示转文字（链接提示、标签、`<br>`、实体、空白、非文字）；礼物（录到的普通、连击、幸运礼物的每个字段，坏数据）；连接按顺序报出一个房间的提问、清屏、通知、礼物，没有时间的提问用注入的时钟 |
| B-1 | 6 | 403 立即换会话，退避 2 s 后的握手带新 Cookie、只提示一次；401 也换，同一轮第二次不再换，连接打开过之后再被拒会再换；连不上、400、404、500、升级头不对都不换；换不到会话以 `credentialsUnavailable` 结束、不再握手；换会话途中关闭会取消请求、没有事件；本地服务器对旧 Cookie 回 403（`dart:io` 的状态码），换会话后加入成功 |

改了原有测试的期望（都在测试里注明）：S08 两组礼物不再按差异 2 去掉礼物（B-9）；“退避 2、3、4、5、6、6、6、6 s”那一个用例的 403 改成像 `dart:io` 一样带状态码，并断言第一次 403 换了一次会话、这一轮不再换（B-1）。

变异检查（每种改动都有用例失败）：握手不用换过的请求头、下一次握手不等会话请求、连接关闭后仍调用钩子（框架测试）、每次被拒都换会话、连接打开后不重新计、400 也换会话、拿不到会话不结束、提示的标签换成空格、保留链接提示、赐福行放在 PK 行后、邀请超时不看邀请方、醒目留言时长改成 30 s、不填价格文字、开始时间用收到的时间、清屏不去重、忽略清屏全部、连击的全 0 `oid` 当 id、不填幸运礼物、团播贵族不写主播名、不报礼物。

测试里的时间都固定（提问用录制时的 `created_time`，没有时间时注入 `now`），不和真实时钟比较；两个测试文件在 +30 天、+1 年、+5 年下直接运行都通过，进程正常退出（本地服务器的连接在结束时都关闭）。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 醒目留言栏显示付费提问（价格文字 `50 钻`，60 s） | M13 |
| 撤回：从聊天列表去掉对应的行；清屏“全部”只清聊天行更接近网站 | M13 |
| 通知行的样式（贵族、PK、赐福） | M13 |
| 显示礼物 | B-21（M13） |

没有新设置。
