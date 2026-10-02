# D01.17 弹幕（新增）：CHZZK

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/chzzk.dart`
  - `ChzzkDanmakuConnection`：连接；
  - `ChzzkDanmakuProtocol`：令牌和服务器列表的读取、地址、握手请求头、加入、最近聊天请求、心跳、解码，不做 I/O；
  - `ChzzkDanmakuFrame`：一帧的解码结果（消息、加入是否被接受、会话号、被拒的原因、是否该重连、服务端 ping、服务端结束会话）。
- 参数：`live_core` 的 `ChzzkDanmakuArgs`（E03.7 给出 `chatChannelId`，E03.7 加了 `channelId`）。进房（`getRoomDetail`）在播且 `live-detail` 有 `chatChannelId` 时给出，不多发请求；地区受限、成人、未开播的没有；关注刷新和录制详情不给。本模块没有改 `live_core`。
- 升级条目：20-2“CHZZK 弹幕”。v3 没有 CHZZK 弹幕（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本（都在 `fixtures/chzzk/`）：
  - `S08-chat-token`：E03.7 从归档复制的令牌接口录制，本模块用它回答令牌请求；
  - `danmaku/S09-live`：归档 v4 的真实录制（2026-09-27，聊天频道 `N2lpu9`，约 33 s，42 行）。帧没有改，本模块加上 v4 解码的冻结输出 `expected.json`；
  - `danmaku/S10-live`：本模块补录（2026-09-28 21:51 UTC，直连，聊天频道 `N2l_uf`），有路由回答、服务端 pong、聊天模式事件、系统行和屏蔽通知，见“样本”；
  - `danmaku/S11-recent`：本模块补录的三个最近聊天回答（2026-09-28 22:00 UTC，三场直播），有捐赠（具名、匿名、视频）、订阅和清洁机器人屏蔽的行，见“样本”；
  - `danmaku/S12-synthetic`：合成帧（`cases.json`，15 组 65 帧），由 `danmaku/synthetic_cases.py` 生成，见“测试”；
  - 四个目录的 `expected.json` 都由 `danmaku/v4_expected.dart` 生成（见“与归档 v4 的对照”）。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：`packages/live_danmaku/lib/src/sites/chzzk.dart`（`ChzzkProtocol`、`ChzzkConnector`）、`runtime/socket_connector.dart`、`test/chzzk_test.dart`；规格 `spec/sites/chzzk.md` 第 7 节；
  - 网站自己的聊天客户端（2026-09-29 下载的 `ssl.pstatic.net/static/nng/glive/resource/p/static/js/vendor-DQYi7KBW.js` 里的 NAVER 聊天 SDK 4.11.0，和驱动它的 `index-BBIPHoDO.js`）：路由、选服务器、加入、请求超时、心跳和 ping 超时、重连、要重连的拒绝码、结束会话、消息种类和状态、匿名捐赠、按用户和时间区分消息（见“协议”“连接和时序”）；
  - pure_live_TV `e1cca224`：`lib/platforms/chzzk/chzzk_site.dart:56` 仍是 `EmptyDanmaku`，没有可参考的实现；
  - 2026-09-28 21:46～22:01 UTC（韩国时间 29 日清晨）的只读实测（匿名、直连、不登录、不发言），见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），平台只写 `target`、`onOpen`、`onData`、`heartbeatFrame`。换地址、退避、最多 8 次、无消息超时、加入计时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **开始时同时发两个请求**（都用注入的 `LiveHttp`，平台 id `chzzk`，平台层的请求头 `ChzzkApi.headers`，不跟随跳转）：
  - 访问令牌：`comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=<chatChannelId>&chatType=STREAMING`，读 `code 200` 的 `content.accessToken`。最多 3 次，间隔 0.5 s、1 s，每次最多等 5 s（和 Picarto、猫耳一样）；都拿不到就以 `credentialsUnavailable` 结束，不开连接；
  - 服务器列表：`routing.chat.naver.com/routing/getRouting?serviceId=game`，只请求一次、最多等 1.5 s（网站的 SDK 就是 1 次、1500 ms），读 `code 200` 的 `result.sessionServerList`；失败或没有可用的主机时用 SDK 内置的 `kr-ss1`～`kr-ss5`；
  - 两个同时发，令牌等待期间路由也在进行，不增加等待；本次 `connect` 结束（关闭、换房间）时两个都取消。
- **令牌和服务器列表整个 `connect` 期间沿用**，重连不再请求（网站的客户端也一直用同一个令牌）。实测匿名只读加入并不检查令牌（见“实测”），所以没有“令牌过期”要处理。
- **连接从随机的一台服务器开始**（网站对直播聊天用 `RANDOM`，只有 `MEMBER` 类频道才按频道号取模），失败时按列表顺序轮换其他服务器。
- **加入照 v4 和录制**：连上后发只读加入（文本帧）。服务端回 `cmd 10100`：`retCode 0` 就报 `DanmakuReady`，并用回答里的 `sid` 请求最近 50 条聊天（网站每次连上都这样做）；5 s 内没有回答就换连接（框架的加入计时器）。
- **被拒就结束**：`retCode` 不是 0 时，302、303、304 按网站 SDK 重连（换下一台服务器，走框架的退避），其他以 `connectionFailed` 结束，详情写明码和原因（例如 `Join refused: 105 Incorrect parameter`）。实测不存在的聊天频道回 105 后服务端就关掉连接；只读加入不检查令牌，换令牌没有用。服务端发 `cmd 90102`（结束会话，SDK 不重连）也以 `connectionFailed` 结束。
- **心跳照网站**：每 20 s 发 `{"ver":"3","cmd":0}`，服务端约 300 ms 内回 `{"ver":"2","cmd":10000}`；服务端发 ping 时立刻回 pong。无消息超时 30 s（SDK 在 20 s 没有消息时发 ping、再等 10 s 没有回答就关掉）。
- **只上报聊天**：
  - 文本（种类 1）、捐赠（10）的留言或视频标题、订阅（11）的留言，状态是 `NORMAL`（或没有状态）且文字不空的行；
  - 管理员或清洁机器人屏蔽的行（`BLIND`、`CBOTBLIND`）仍带着原文，网站不显示，这里也不报；
  - 图片、贴纸、订阅赠送、派对、商店购买、系统行不报；
  - 捐赠按网站的做法当作聊天行显示（网站把它放在聊天列表里，没有置顶的留言栏），金额不报；显示为醒目留言列为候选；
  - 不报人数，见下条。
- **在线人数的来源不变**：每行的 `mbrCnt`（最近聊天是 `memberCount`、`userCount`）是聊天连接数，不是观众数：和同一时刻平台给的 `concurrentUserCount` 相差 4%～75%，有高有低（见“实测”），也不管主播是否用 `cvExposure` 隐藏了人数；网站也不显示它。所以不报，`audience.dart` 里 CHZZK 仍是 `roomList`（列表和详情就有真实在线人数），没有改。v4 把它报成在线人数（差异 2）。

## 协议

**令牌**：`GET https://comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=<chatChannelId>&chatType=STREAMING`，回答 `{"code":200,"content":{"accessToken":…,"extraToken":…,"temporaryRestrict":{…},"realNameAuth":false,…}}`（S08）。不存在的聊天频道回 HTTP 500、`code 50001`（实测）。只取 `accessToken`，它只放进加入包，不出现在地址和任何事件里。

**服务器**：`GET https://routing.chat.naver.com/routing/getRouting?serviceId=game`，回答 `{"result":{"sessionServerList":["kr-ss1.chat.naver.com",…,"kr-ss6.chat.naver.com"],"proxyServerList":[…],"expireTime":86400},"code":200}`（S10 第 0 行）。只收 `*.chat.naver.com` 的主机名（小写字母、数字、连字符），去重，最多 16 个。地址是 `wss://<主机>/chat`。

**握手请求头**：`origin: https://chzzk.naver.com` 和平台层的桌面 UA（`ChzzkApi.userAgent`），和两次录制、v4 相同。服务端不在乎请求头大小写，用默认的 `dart:io` 握手，不需要 `connectExactWebSocket`。（`dart:io` 会把 UA 接在它自己的 `Dart/3.13 (dart:io)` 后面，所有用默认握手的平台都这样，服务端接受。）

**消息**：每条都是 JSON 文本帧（客户端发文本，和网站一样；v4 发的是二进制，服务端也收）。

| 方向 | `cmd` | 内容 | 本实现 | 归档 v4 |
|---|---|---|---|---|
| 发 | 100 | 加入：`{"ver":"3","cmd":100,"svcid":"game","cid":<聊天频道>,"bdy":{"uid":null,"devType":2001,"accTkn":<令牌>,"auth":"READ"},"tid":1}` | 与 S09、S10 逐字节相同 | 同，二进制 |
| 收 | 10100 | 加入应答：`retCode 0` 加入（`bdy.sid` 会话号），否则被拒（`retMsg` 原因） | 就绪并请求最近聊天；302～304 重连，其他结束 | 没有 `sid` 也算被拒；被拒换令牌重连 |
| 发 | 5101 | 最近聊天：`{"ver":"3","cmd":5101,"svcid":"game","cid":…,"sid":…,"bdy":{"recentMessageCount":50},"tid":2}` | 每次加入后发 | 同 |
| 收 | 15101 | 最近聊天：`bdy.messageList`（另有 `userCount`、置顶公告 `notice`） | `retCode 0` 时读 | 不看 `retCode` |
| 收 | 93101 | 聊天，`bdy` 是行的数组 | 读 | 读，另报人数 |
| 收 | 93102 | 服务端主动发的行：捐赠、订阅、系统行 | 读 | 读，捐赠另报礼物 |
| 发/收 | 0 | ping：`{"ver":"3","cmd":0}`；服务端也会发 | 20 s 一次；收到就回 pong | 同 |
| 发/收 | 10000 | pong：服务端回 `{"ver":"2","cmd":10000}`，客户端回 `{"ver":"3","cmd":10000}` | 不报 | 不报 |
| 收 | 90102 | 服务端结束会话 | 以 `connectionFailed` 结束 | 忽略（差异 14） |
| 收 | 93006 | 事件（聊天模式、捐赠设置、直播被封、预测……） | 不报 | 不报 |
| 收 | 94008 | 事后屏蔽某条（按用户和时间） | 不报（撤回列为候选） | 不报 |
| 收 | 94010、94005、94015 等 | 置顶公告、踢人、处罚 | 不报 | 不报 |

行的字段（直播推送的 / 最近聊天的）：

| `LiveMessage` | 取值 | 与归档 v4 |
|---|---|---|
| 类型 | 聊天 | 同 |
| 显示哪些行 | 种类 `msgTypeCode` / `messageTypeCode` 为 1、10、11（没有种类当作 1），状态 `msgStatusType` / `messageStatusType` 为 `NORMAL` 或没有 | v4 不报 11（差异 5）；`extras` 带 `payAmount` 的任何种类都当捐赠（差异 6） |
| 文本 | `msg` / `content` 去首尾空白；文字或数字，空的不报。表情留作 `{:名字:}` | v4 把列表、对象也转成文字（差异 10） |
| 用户名 | `profile`（JSON 文本或对象）的 `nickname` | 同 |
| 用户 id | `uid` / `userId` | 同 |
| 匿名捐赠 | 种类 10 且 `extras.isAnonymous` 为真或用户是 `anonymous`：名字是网站的 `익명의 후원자`，没有用户 id | v4 叫“匿名”（差异 4） |
| 时间 | `msgTime` / `messageTime`（毫秒，整数或它的文字）；不大于 0 或超出 `DateTime` 范围时为空 | 超出范围时 v4 整行丢失（差异 8） |
| 消息 id | `<用户>:<时间>`（匿名捐赠是 `anonymous:<时间>`），没有时间就没有 id。网站就是按用户和时间区分消息的（`isSameMessage`） | v4 加 `chzzk:` 前缀（差异 1）；时间不大于 0 也生成 id（差异 8） |
| 颜色 | 白色（`nicknameColor.colorCode` 是昵称的调色板代码，不是文字颜色） | 同 |
| 等级、粉丝牌 | 空（平台只有订阅月数和徽章） | 同 |

## 连接和时序

| 项目 | 本实现 | 归档 v4 | 网站（SDK 4.11.0） | 依据 |
|---|---|---|---|---|
| 开始前的请求 | 令牌（3 次，间隔 0.5 s、1 s，每次 5 s 超时）和路由（1 次，1.5 s）同时发；平台层请求头；不跟随跳转 | 只有令牌，1 次，请求头只有 Origin 和 UA | 令牌和路由（路由结果在本地存一天） | 差异 13 |
| 地址 | 路由给的服务器（失败时 SDK 内置的 5 台），从随机一台开始，失败后轮换 | 按聊天频道号的字符和 % 9 + 1 算出一台 `kr-ss<n>` | 路由给的列表里随机一台 | 差异 11 |
| 握手请求头 | Origin、桌面 UA；默认握手 | 同 | 浏览器 | 录制 |
| 加入 | 打开后发加入（文本）；`retCode 0` 就绪，已就绪时不再报；每次加入都请求最近 50 条 | 二进制；`retCode 0` 且有 `sid` 才算加入 | 文本；`retCode 0` 算加入；连上就请求最近 50 条 | 差异 9、12 |
| 加入超时 | 5 s，超时直接换连接（框架默认，不单独提示；框架自己的重连提示照常） | 8 s | 每个请求 5 s（`callbackTimeout`） | 差异 15 |
| 心跳 | 20 s，文本 ping，连上就按间隔发；手动 `heartbeat()` 同样；服务端 ping 立刻回 pong | 20 s，二进制，加入后开始 | 最后一条消息 20 s 后发 ping（`pingInterval`） | 录制；实测 pong 约 300 ms |
| 无消息超时 | 30 s | 90 s | ping 后 10 s 没有消息就关掉（`pingTimeout`） | 差异 15 |
| 断线重连 | 框架默认：六台服务器轮换，间隔 1、1、1、1、1、2、2、2 s，第 9 次失败结束；收到任何消息清零；一轮只提示一次；沿用令牌 | 退避相同，一台服务器，沿用令牌 | 连上后断开立刻重连；连接失败重试 1 次（约 1 s） | D01.1 |
| 被拒 | 302～304 重连（走退避）；其他以 `connectionFailed` 结束，写明码和原因 | 换令牌后按退避重连并提示，超过 3 次以 `rejected` 结束 | 302～304 重连；其他报错，不重试 | 差异 13；实测 105 后服务端关连接 |
| 服务端结束会话（90102） | `connectionFailed` | 忽略 | 关掉，不重连 | 差异 14 |
| 结束原因 | 没有令牌：`credentialsUnavailable`；聊天频道号不对：`connectionFailed`（不发请求）；被拒、90102：`connectionFailed`；重连用尽：`reconnectsExhausted` | `credentials`、`rejected`、`maxRetries` | — | D01.1 的类型；差异 16 |
| 帧解不开 | 丢掉这一帧，不影响连接 | 同 | 同 | — |
| 诊断文字 | 握手失败时是 `dart:io` 的错误（地址不含令牌）；令牌不进任何事件 | — | — | — |
| 代理 | 按平台 `chzzk` 取路由（构造参数 `proxy`）；两个 HTTP 请求由 `LiveHttp` 按平台取路由 | 同 | — | — |

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.chzzk: () => ChzzkDanmakuConnection(http: http, proxy: proxyPolicy),
  // …
});
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `http` | 是 | 请求令牌和服务器列表用的 `LiveHttp`，就用给 `ChzzkSite` 的那个（按平台 id `chzzk` 取代理路由和限流） |
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `chzzk` 取路由 |
| `connector` | 否 | 只给测试替换握手；默认 `dart:io` |
| `tokenRetryDelay` | 否 | 只给测试缩短令牌重试的间隔 |
| `random` | 否 | 只给测试固定第一台服务器 |

不需要 Cookie 或设置：v3 的 CHZZK 全程匿名（E03.7 没有它的 Cookie），弹幕用每次现取的令牌，只读加入。`ChzzkDanmakuArgs.channelId` 连接用不到（聊天就是 `chatChannelId`）。

## 与归档 v4 的对照

对照方式：

- `fixtures/chzzk/danmaku/v4_expected.dart` 把归档 v4 的 `ChzzkProtocol`（`tokenUrl`、`accessToken`、`endpoint`、`headers`、`join`、`recent`、`ping`、`pong`、`decode`）原样搬进一个独立程序（测试核对过与归档逐字相同），另记下 `ChzzkConnector` 发的令牌请求和握手。只替换了它从别处引用的东西：事件类型（`DanmakuChat`、`DanmakuGift`、`DanmakuOnline`、`AudienceKind`）和 `DecodeContext`、`FrameResult`，删到只剩解码会填的字段。
- 它对 S09、S10 写下聊天频道、令牌、令牌请求、服务器、握手请求头、加入和 ping，以及每个收到的聊天帧：是否加入或被拒、回复（pong、最近聊天请求）、解出的事件；对 S11 写下每个回答的同样内容；对 S12 写下每组每帧的同样内容。运行：在仓库根目录 `dart run fixtures/chzzk/danmaku/v4_expected.dart`，`generator` 字段写明来源。
- 测试把新代码的结果投影成 v4 的形状（消息 id 补回 `chzzk:` 前缀；连接会发的 pong 和最近聊天请求算作回复），逐帧比较。所有帧共有的差异（不报人数、不报礼物、匿名捐赠的名字和 id）统一换算；其余有意的差异在测试里逐组写明：先断言 v4 的输出，再断言新代码的。

| 对照 | 结果 |
|---|---|
| 令牌 | S08 和两次录制的令牌回答读出同一个令牌 |
| 加入、最近聊天请求、ping | 与 S09（二进制）、S10（文本）录下的逐字节相同，与 v4 相同 |
| 握手请求头 | 与三份录制、v4 相同 |
| 服务器 | 不同（差异 11）：v4 为 S09 算出 `kr-ss1`、为 S10 算出 `kr-ss2`；录制实际用了 `kr-ss1`、`kr-ss5`，都在路由列表里 |
| S09 的 38 个收到的帧 | 一致：加入 1 次、125 条聊天（最近 50 条、直播推送 75 条）；v4 另报 35 个人数 |
| S10 的 39 个收到的帧 | 一致：加入 1 次、106 条聊天；聊天模式事件、系统行、屏蔽通知、pong 不报；v4 另报 33 个人数 |
| S11 的 3 个回答 | 一致：123 条聊天，其中 6 条匿名捐赠（2 条是视频捐赠）、2 条具名捐赠，2 条 `CBOTBLIND` 不报；新代码另多 1 条订阅留言（差异 5），共 124 条；v4 另报 8 个礼物 |
| S12 的 15 组 65 帧 | 9 组在统一换算（不报人数、礼物，匿名捐赠的名字和 id）后一致；6 组是有意差异（差异 5～10），见下 |

## 与归档 v4 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 消息 id 不加 `chzzk:` 前缀 | 与 D01.2～D01.13 一致：去重闸门按房间内的 id 比较 |
| 2 | 不报人数（v4 把每帧最后一行的 `mbrCnt` 报成在线人数） | 那是聊天连接数：和 `concurrentUserCount` 相差 4%～75%，有高有低，也不管主播隐藏人数（`cvExposure`）；网站不显示它（见“做法”“实测”） |
| 3 | 捐赠不报礼物（v4 报“치즈”× 金额） | v3 所有平台都不显示礼物（`LiveMessageType.gift` 注明“not shown yet”），D01.2～D01.13 也都不报 |
| 4 | 匿名捐赠的名字是网站的 `익명의 후원자`，id 是 `anonymous:<时间>` | 网站就这样显示（`index-*.js` 的匿名资料）；v4 写死中文“匿名”，id 里还可能带着被标为匿名的用户号 |
| 5 | 订阅（种类 11）的留言当作聊天 | 网站在聊天列表里显示订阅者的留言（S11 有一条）；v4 丢掉 |
| 6 | 显示哪些行只看种类；`extras` 带 `payAmount` 的贴纸之类不再当捐赠 | v4 把任何带 `payAmount` 的行当捐赠；网站按种类渲染 |
| 7 | 最近聊天的回答 `retCode` 不是 0 时不读 | 网站的 SDK 这时把请求当失败；v4 照样读 `messageList` |
| 8 | 时间超出 `DateTime` 范围只让这一行没有时间；时间不大于 0 时没有 id | v4 抛 `RangeError`，整行丢失（统一原则“一行坏数据只跳过这一行”）；v4 用 0 或负数也生成 id，同一用户这样的行会被去重闸门合并 |
| 9 | 加入应答 `retCode 0` 但没有 `sid` 也算加入（只是不请求最近聊天） | 网站的 SDK 只看 `retCode`；v4 当作被拒 |
| 10 | 文本是列表或对象时不报 | v4 显示成 `[x]`、`{a: 1}` |
| 11 | 服务器来自路由，随机选一台，失败时轮换 | v4 按聊天频道号算出一台（`% 9 + 1`，会算出路由不列出的 `kr-ss7`～`kr-ss9`），只有这一个地址。网站对直播聊天就是随机选 |
| 12 | 发文本帧 | 网站这样发；v4 发二进制，内容相同，服务端两种都收（S09 二进制、S10 文本） |
| 13 | 令牌请求 3 次、每次 5 s、平台层请求头、不跟随跳转，和路由一起发；被拒时不换令牌：302～304 重连，其他结束 | 一次网络抖动就让这个房间没有弹幕，直到重新进房（间隔照 Picarto、猫耳）；只读加入不检查令牌（实测），换令牌没有用；实测唯一见到的拒绝（105）后服务端就关连接，重试只会一直被拒 |
| 14 | `cmd 90102` 结束 | 网站的 SDK 收到后关掉、不重连；v4 忽略它，之后连接会被当作断线一直重连 |
| 15 | 加入超时 5 s、无消息超时 30 s | 网站的 `callbackTimeout`、`pingInterval` + `pingTimeout`；v4 用运行时默认的 8 s、90 s |
| 16 | 结束原因用 D01.1 的类型 | v4 的 `credentials`、`rejected`、`maxRetries`；界面文字由 M13 给出 |

没有改的地方：

- 令牌接口和读法、加入和最近聊天请求的内容、20 s ping、服务端 ping 回 pong、握手请求头与 v4 相同，服务端接受过（两次录制）。
- 两种行的字段名、`profile` 和 `extras` 是 JSON 文本、屏蔽状态不报、文本去空白、名字取 `nickname`、时间是毫秒（整数或它的文字）、表情留在文本里、颜色一律白色与 v4 相同。
- 时间用本地时区的 `DateTime`（同一时刻），和其他平台一样。

## 审查发现的归档 v4 问题

| # | 问题 | 位置（归档 v4） | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 约三分之一的聊天频道算出 `kr-ss7`～`kr-ss9`，路由并不列出它们（现在 DNS 仍能解析，实测也能连，但不是平台给的服务器）；只有一个地址，它不可用时一直重连同一台 | `ChzzkProtocol.endpoint` | 规格 §7.2 把 SDK 对 `MEMBER` 频道的取模（按列表长度）记成了 `% 9 + 1` | 用路由的列表，随机起点，失败轮换（差异 11） |
| 2 | 把聊天连接数当成在线人数，还会显示主播隐藏了的人数 | `_messages` | 没有和平台的 `concurrentUserCount` 对照 | 不报（差异 2） |
| 3 | 被拒后换令牌、按退避重连并提示，最多 4 轮；实际被拒的原因（聊天频道不对）换令牌解决不了 | `runtime/socket_connector.dart` 的 `rejected` 分支 | 没有实测拒绝 | 差异 13 |
| 4 | 一行的时间超出范围时整行丢失；没有 `sid` 的成功应答当作被拒 | `_message`、`decode` | 没有逐字段容错；比 SDK 多一个条件 | 差异 8、9 |

## 实测

2026-09-28 21:46～22:01 UTC，只读、匿名、直连，没有登录，没有发言。

- 网站脚本（见“参考”）：SDK 4.11.0 的常量和逻辑如上表；CHZZK 的 `getChatClientOptions` 是 `svcid game`、`channelType LIVE`、未登录时 `auth READ`，路由 `numTries 1`、`callTimeoutMillis 1500`；连上后 `getLiveMessageListRecentAsync({recentMessageCount:50})`；93101 和 93102 走同一个处理；消息种类 `TEXT 1`、`DONATION 10`、`SUBSCRIPTION 11`、`SUBSCRIPTION_GIFT 12`、`PARTY 13`、`STREAMER_SHOP_PURCHASE 15`、`SYSTEM 30`，状态 `NORMAL`、`BLIND`、`CBOTBLIND`；匿名捐赠显示 `익명의 후원자`；按用户和时间区分消息；94008 按用户和时间把已显示的行改成屏蔽。
- 路由回答 6 台服务器（`kr-ss1`～`kr-ss6`），`expireTime` 86400；SDK 内置的是 5 台。
- 加入探测（`N2lxhQ`，一场约 1400 人的直播）：
  - 有效令牌、编造的令牌、`null`、另一个聊天频道的令牌：都回 `retCode 0`，照常收到聊天（只读加入不检查令牌）；
  - `kr-ss1`、`kr-ss6`、`kr-ss9` 都能加入；
  - 不存在的聊天频道（`zzzzzz`）：回 `{"cmd":10100,"retCode":105,"retMsg":"Incorrect parameter","tid":"1"}`，随后服务端以 1000 `Bye` 关连接；它的令牌请求回 HTTP 500、`code 50001`；
  - 上一场已结束的聊天频道（`N2lpu9`，S09 的）：仍能拿到令牌、加入成功，但没有消息。同一频道 09-28 的直播已是 `N2lxdt`，也就是每场直播换一个聊天频道。
- 人数：`userCount`、`mbrCnt` 和平台同时给的 `concurrentUserCount`：
  - S10 开始时 4228 对 4724；另一场录了 280 s，聊天是 1049～1315，平台是 1337～1396；
  - 30 场热门直播的最近聊天回答（22:00 UTC）：856 对 937、322 对 367、214 对 188、168 对 175、143 对 120、205 对 117……有高有低。
- 用录制程序连了两场各约 300 s（S10 是其中之一）：约 300 ms 加入，ping 约 300 ms 得到 pong，没有断线。清晨是韩国的冷门时段，两场都没有捐赠；S11 取自 30 场的最近聊天回答。

## 样本

- **S10-live**（频道 `ac6a03808bffbe58b3bfb0e25271836e`，聊天 `N2l_uf`，服务器 `kr-ss5`）：
  - 录制用自写的 `dart:io` 小程序：路由、令牌、只读加入、最近聊天、每 20 s 一次 ping、回服务端 ping，别的什么也不发；共 300 s、154 行，保留第 0～39 行（前 25 s：路由、令牌、加入、最近聊天、聊天、第一次 ping 和 pong）和第 114～118 行（119～125 s：聊天模式改为只能发表情的事件、93102 的系统行、94008 屏蔽通知、ping 和 pong），其余是同样的聊天和 pong，`meta.json` 的 `kept` 写明；
  - 直播约 35 s 时似乎下播了（直播状态接口开始给累计人数，聊天连接数从 4228 降到 1900 左右），聊天照常继续；
  - 脱敏：用户号（`uid`、`userId`、`userIdHash`，32 位十六进制）换成同样位数的其他十六进制，昵称换成“观众N”，令牌（`accessToken`、`extraToken`、加入包的 `accTkn`）、会话号 `sid`、`uuid` 换成同形同长度的值，同一个人始终是同一组值；聊天里提到的观众昵称（三个字以上）一并替换。嵌套的 `profile`、`extras` 按原来的转义（有的客户端转义 `/`）写回，其余字节与服务端的相同。聊天文字、徽章、表情地址、主播的公开频道号保留，和 S09 的口径相同；
- **S11-recent**（三场直播 `N2l-x_`、`N2lyvo`、`N2m13O` 的最近聊天回答，各 50 行）：同样的规则，另把 `weeklyRankList` 里的用户号和昵称、`extras.nickname`、`donationId` 换掉；主播的频道号和名字、金额保留。
- 两份都逐帧检查过：原值都不在输出里（脚本自查），没有 IPv4 地址；门禁的 `fixture privacy` 通过。`meta.json` 记了原始录制的 SHA-256 和长度、脱敏位置、说明（`note`）。录制和脱敏脚本没有放进仓库，`tool` 写明了。
- **S09-live**：帧没有改，只加了 `expected.json`。它的用户、令牌是归档录制时换过的合成值。
- **S12-synthetic**：名字、id、令牌、时间都是编造的，字段名和形状照录制和网站脚本。

## 回归条目的覆盖

归档规格第 7 节没有弹幕的回归条目；REG-CHZZK-001～004 属于平台层（E03.7）。REG-CHZZK-002（`cvExposure` 为假时不显示在线人数）在这里的体现是不报聊天连接数，有测试。

## 受阻和限制

没有受阻的部分。

限制：

- 聊天频道每场直播换一个。主播下播再开播后，旧的聊天频道仍能加入但不再有消息，连接看起来正常；网站靠每隔一段时间读直播状态发现新的频道。本模块不轮询（T02.U 为此留下的 `channelId` 暂时没用上），要靠重新进房拿到新参数，见“放到其他模块的部分”和候选 5。
- 只读：不登录，不能发言，也收不到只给管理员看的系统行。

## 后续升级候选（由用户决定）

| # | 内容 | 现状 | 依据 |
|---|---|---|---|
| 1 | 捐赠（치즈，1 치즈 = 1 韩元）显示为醒目留言，带金额 | 已做（D01 后续升级（原 M5.F）），见“后续升级（D01 后续升级（原 M5.F），附录 B-12）” | 网站在聊天列表里高亮显示，没有置顶栏；醒目留言要定显示时长和金额单位，需要 M13 定 |
| 2 | 渲染表情（`{:名字:}` 和 `extras.emojis` 里的图片地址） | 文本里显示占位 | 需要 A01.1 的表情渲染支持远程图片 |
| 3 | 事后屏蔽（94008，按用户和时间）从弹幕列表撤下 | 已做（D01 后续升级（原 M5.F）），撤回的界面在 M13 | 与 Twitch、Picarto、猫耳的撤回候选一起由 M13 支持 |
| 4 | 置顶公告（94010、最近聊天的 `notice`）显示为房间公告 | 已做（D01 后续升级（原 M5.F）），显示为通知 | 网站显示在聊天上方 |
| 5 | 聊天没有消息一段时间后，用 `channelId` 读一次直播状态，聊天频道换了就换过去 | 已做（D01 后续升级（原 M5.F）），安静 3 分钟后读一次 | 网站轮询直播状态；需要决定间隔（多一个请求） |
| 6 | 订阅赠送、系统行（聊天模式变化等） | 已做（D01 后续升级（原 M5.F）），显示为通知 | 与其他平台一起由 M13 决定 |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表） |
| 重新进房拿到的 `ChzzkDanmakuArgs.chatChannelId` 与正在用的不同时（主播重新开播），重建弹幕连接；D01.1 的“同房间且已就绪时不重连”只比较房间，要把弹幕参数也算进去 | M13 |
| 匿名捐赠的名字 `익명의 후원자` 是网站的原文，是否翻译 | M13 |
| 多画面弹幕（v3 不支持 CHZZK）是否接入 | 已完成（N01.1：多画面按弹幕登记接入所有有弹幕的平台，[记录](../../../N-多画面和投屏/N01-多画面/N01.1-多画面/record.md)） |
| 上面的候选 | A01.1、M13 |
| `live_core` 的 `LiveDanmaku`、`ChzzkSite.getDanmaku()`（仍是 `EmptyDanmaku`） | D01 各平台完成后删除 |

## 新增的通用能力、依赖

没有。框架文件没有改；`live_danmaku.dart` 按字母顺序加了一行导出；没有新依赖；`live_core` 没有改（人数来源不变，`audience.dart` 不动）。

发现但没有改（不属于本模块）：`live_net` 的 `connectIoSocket` 经 `dart:io` 发出的 UA 是 `Dart/3.13 (dart:io), <给定的 UA>`（`dart:io` 是追加而不是替换），所有用默认握手的平台都这样。CHZZK 和已接入的平台服务端都接受；要发纯浏览器 UA 需要在 `live_net` 里处理。

## 测试

`test/chzzk_test.dart` 56 个用例，`live_danmaku` 共 746 个，连续跑 3 次全部通过；直接作为 Dart 程序运行也能正常退出（本地服务器在结束时关闭升级后的服务端连接）。另做了变异检查，下面每一种改动都会让对应的用例失败：ping 改成 30 s、去掉 30 s 无消息超时、加入超时改成 8 s（v4）、显示被屏蔽的行、不显示订阅、匿名名字改成“匿名”（v4）、只按用户名判断匿名、不回 pong、不请求最近聊天、不重连 302～304、忽略 90102、不用路由、总从第一台开始、不看最近聊天的 `retCode`、令牌跟随跳转、id 加前缀（v4）、时间为 0 也生成 id（v4）、文本不去空白、不检查聊天频道号、令牌只请求一次（v4）、关闭时不取消请求、加入发二进制（v4）、没有 `sid` 当作被拒（v4）、重复的应答再报一次就绪、超出范围的时间照用。

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 11 | S08 和两次录制的令牌、坏的令牌回答；S10 的路由回答、坏主机、去重、上限、SDK 的列表、轮换；v4 的服务器公式与录制和路由的对照；握手请求头与三份录制和 v4 相同；加入、最近聊天请求、ping 与 S09（二进制）、S10（文本）逐字节相同；聊天频道号的检查；S09 的参数就是 S06 进房给的；聊天填满消息模型；不报人数、`audience.dart` 仍是 `roomList`；S11 的具名、匿名、视频捐赠和订阅，屏蔽的行；应答、ping、结束会话的读法 |
| 录制帧对照 v4 | 5 | S09、S10 逐帧与 v4 一致；S09 的加入和 125 条聊天；S10 的事件、系统行、屏蔽通知、pong 不报；S11 逐个回答与 v4 一致，另多订阅留言 |
| 合成帧（S12）对照 v4 | 17 | 15 组各一个用例（6 组按差异 5～10 变换）；另有一个检查每组都有 v4 输出、每条差异都对应一组；一个检查 90102 和要重连的拒绝码 |
| 连接 | 23 | 令牌和路由的请求（地址、请求头、不跟随跳转、超时）、两个同时发；随机起点的服务器、握手请求头、直连；加入的内容；应答前不就绪、应答后就绪并请求最近聊天、重复应答不再报；回放 S09、S10 得到 v4 的 125 条和 106 条；时序（20 s、30 s、5 s、8 次）；20 s 定时和手动 ping、回服务端 ping、关闭后不发；代理路由；四种拿不到路由时用 SDK 的 5 台；聊天频道号去空白和检查（不对时 `connectionFailed` 且不发请求）；令牌 3 次（0.5 s、1 s）后成功；5 种拿不到令牌的情形都是 `credentialsUnavailable` 且不开连接；取令牌时关闭会取消两个请求、没有事件；加入 5 s 没有应答换下一台、沿用令牌；断线 1 s 后换下一台、重新加入并再请求最近聊天；被拒（105）结束并写明原因、不重连；303 重连；90102 结束；退避 1、1、1、1、1、2、2、2 s 轮换六台后放弃、详情不带令牌；关闭后没有事件和 ping；换聊天频道取新令牌、旧连接的消息和拒绝都不起作用；参数类型；平台表登记；本地 WebSocket 服务器端到端（路径、Origin、UA、加入、S10 的帧、服务端 ping 和 pong、手动 ping） |

没有用到样本时间与“现在”比较的逻辑（令牌没有过期时间，路由的 `expireTime` 不读，聊天的时间只换算不比较），`tools/timeshift/run.sh 30 1825` 全部 ok。

## 后续升级（D01 后续升级（原 M5.F），附录 B-12）

- 日期：2026-10-01。条目：上面“后续升级候选”的 1、3、4、5、6（用户 2026-09-30 答复“按建议全部处理”）；候选 2（表情图片）放 A01.1，这次不做。
- 目标：`packages/live_danmaku/lib/src/sites/chzzk.dart`。`live_core` 和框架没有改，没有新依赖。本节取代前文“做法”里“只上报聊天”一条、“协议”表里 93102、94008、94010 三行的“本实现”一栏、差异 3（捐赠不报）和“登记方式”里“`ChzzkDanmakuArgs.channelId` 连接用不到”一句（现在用它读直播状态）；其余不变。登记方式不变，构造参数只多了给测试用的 `clock`。
- 依据：
  - 网站脚本（D01.17 下载的 `index-BBIPHoDO.js`、`vendor-DQYi7KBW.js`）：聊天列表按种类渲染（`case Ly.DONATION` 按 `extras.donationType` 分 `CHAT`、`MISSION`、`MISSION_PARTICIPATION`、`PARTY`；`Ly.SUBSCRIPTION_GIFT` 按 `giftType` 分 `zC`、`LC`；`Ly.SYSTEM` 标题加说明）；捐赠行 `yC` 按金额分五档样式（`level0`～`level4`，界线 1 万、10 万、50 万、100 万），金额用 `Tl`（三位一逗号）；`makeMessage` 的匿名规则；`messageFilter` 对带 `visibleRoles` 的系统行，没有资料（未登录）时不显示；`notiBlindListener`（94008 按 `messageTime` 和 `userId` 找到那一行改成屏蔽，`CANCEL` 恢复）；`notiNoticeListener`（94010，`messageTime` 不大于 0 表示没有置顶）和 `connectedListener`（最近聊天的 `notice`）；聊天页在直播开着时每 30 s 调 `sp(channelId)`（`polling/v3.1/channels/<id>/live-status`，失败 20 次后停），`connect` 用 `isSameConfig` 比较 `chatChannelId`，变了就重连；
  - 界面文字（2026-09-30 下载的 `ssl.pstatic.net/static/nng/glive/locales/pc/strings-ko_kr.json`）：`live_chatting_message.donation_cheese_with_amount`（`{{payAmount}} 치즈를 후원했습니다.`）、`live_chatting_subscription_channel_gift.channel_gift_line`（`<em>{{giftTierName}} 구독권 {{quantity}}개</em>를 채널에 선물하였습니다.`）、`live_chatting_subscription_viewer_gift.gift_subscription_line`（`님에게 <em>{{giftTierName}} 구독권</em>을 선물하였습니다.`）、`live_chatting_fixed.message_of_pinned`（`<name/>님의 메시지를 고정함`）和 `pinned_by_suffix`（`<name/>님이 고정함`）；
  - 新样本 S13～S17（见下）。

### 做法

| 条目 | 读法 | `LiveMessage` |
|---|---|---|
| 捐赠（候选 1） | 种类 10、状态 `NORMAL`，文字和金额至少有一样；`CHAT`、`VIDEO`、`MISSION`、`MISSION_PARTICIPATION`、`PARTY` 都算 | `superChat`，外壳照 3.x 和哔哩哔哩、斗鱼、虎牙写 `SUPER_CHAT_MESSAGE`，另带 `userId`、`messageId`（`<用户>:<时间>`，匿名 `anonymous:<时间>`，和聊天行同一套）、`sentAt`；`data` 见下表 |
| 事后屏蔽（候选 3） | 94008 的 `userId` 和 `messageTime`；`blindType` 为 `CANCEL` 时不报，其余（`BLIND`、`CBOTBLIND`、`HIDDEN`，缺少也算）都撤回；缺用户或时间不报 | `retraction`，`data` 是 `LiveRetraction.message('<userId>:<messageTime>')`，正好是那一行的 `messageId`（D01.17 起就按用户和时间给 id，不用补字段）；撤回本身没有 `messageId`、`sentAt`、`userId` |
| 置顶公告（候选 4） | 每次加入后最近聊天回答的 `bdy.notice`（放在最近的行之后），直播中换置顶的 94010；`messageTime` 不大于 0（网页的“没有置顶”）或内容为空不报 | `notice`（`system`）：作者自己置顶是 `<作者> 置顶了消息：<内容>`，别人置顶是 `<置顶者> 置顶了 <作者> 的消息：<内容>`（`extras.registerProfile` 是置顶者），没有作者是 `置顶消息：<内容>`；`userName`、`userId` 是作者；`messageId` 是 `notice:<用户>:<时间>`，不和被置顶的那行撞 id；没有 `sentAt`（`messageTime` 是那行写下的时间，不是置顶的时间） |
| 订阅赠送（候选 6） | 种类 12、状态 `NORMAL`；`giftType` 为 `SUBSCRIPTION_GIFT` 是送给频道，其余（`SUBSCRIPTION_GIFT_RECEIVER`）是送给某位观众，和网页一样 | `notice`（`subscription`）：`<赠送者> 向频道赠送了 5 张「<档次>」订阅券`（`quantity`、`giftTierName`），`<赠送者> 向 <接收者> 赠送了「<档次>」订阅券`（`receiverNickname`）；缺数量或档次时省掉那部分。送给频道且带 `anonymousToken`、送给观众且 `profile` 为空，或用户是 `anonymous`，赠送者是 `익명의 후원자`，没有用户 id，`messageId` 是 `anonymous:<时间>` |
| 系统行（候选 6） | 种类 30、状态 `NORMAL`；`extras.visibleRoles` 不空的（临时限制等，只给主播和管理员看）不报；标题（`msg`）和说明（`extras.description`）都空不报 | `notice`（`system`）：`<标题>：<说明>`（网页标题一行、说明一行），只有一样就只写那一样；`messageId` 是 `SYSTEM_MESSAGE:<时间>` |
| 直播状态（候选 5） | 见下 | 换频道后新频道接受加入时再报一次 `DanmakuReady` |

醒目留言的 `data`（`LiveSuperChatMessage`）：

| 字段 | 取值 |
|---|---|
| `messageId` | 同外壳 |
| `userName` | `profile.nickname`；匿名是 `익명의 후원자` |
| `face` | `profile.profileImageUrl`，只收 NAVER 的图片（`ChzzkApi.image`，和列表、详情一样）；匿名为空 |
| `message` | 留言；视频捐赠是视频标题，任务捐赠是任务内容；只有金额时为空 |
| `price` | `extras.payAmount`（치즈，整数或它的文字；负数、缺少、坏数据为 0） |
| `priceText` | 网页的写法：三位一逗号加 ` 치즈`，如 `1,000 치즈`、`1,234,567 치즈`；金额为 0 时为空 |
| `startTime` | 行的时间；没有时间用收到的时间（连接的 `clock`，默认现在） |
| `endTime` | 开始时间加上按金额的时长：网页按金额分五档（`yC` 的 `level0`～`level4`），但网页没有显示时长（捐赠留在聊天列表里滚走），所以时长取哔哩哔哩醒目留言的前五档，也就是 v3 醒目留言栏已经在用的时长：1 万以下 1 分钟，10 万以下 2 分钟，50 万以下 5 分钟，100 万以下 30 分钟，100 万及以上 60 分钟 |
| `backgroundColor`、`backgroundBottomColor` | 空：网页按档次在样式表里上色，行里没有颜色 |

**最近聊天的重复**：每次加入都请求最近 50 行（D01.17），其中的聊天行由去重闸门按 id 去掉（过滤链只管聊天）；醒目留言和通知不经过闸门，所以连接在本次 `connect` 里记住报过的醒目留言和通知的 id（最多 512 个），重连后最近聊天里的同一条不再报。置顶公告也因此每次加入只报一次（同一条置顶）。

**安静时读直播状态**（候选 5）：

- 从加入被接受或最后一帧推送的行（93101、93102，显示与否都算）起 3 分钟（`ChzzkDanmakuConnection.quietPeriod`）没有新的行，就读一次 `api.chzzk.naver.com/polling/v3.1/channels/<channelId>/live-status`（网页聊天页用的同一个请求；平台层请求头，不跟随跳转，最多等 5 s，关闭、换房间时取消）。pong、事件（93006）、屏蔽通知不算“有行”。
- 回答 `code 200`、`status` 为 `OPEN`、`chatChannelId` 是合法的聊天频道号且和正在用的不同：照进房的做法取新频道的令牌（3 次），再把连接换到同一组服务器（随机起点，`reopen`，不提示重连），新频道接受加入后报 `DanmakuReady` 并请求它的最近聊天；旧连接之后的帧不再起作用。
- 相同、下播（`CLOSE`，`chatChannelId` 为空，S17）、请求失败、拿不到新令牌：什么也不做，再等 3 分钟。
- `ChzzkDanmakuArgs.channelId` 为空或不是 32 位十六进制时不检查（E03.7 起进房都会给）。
- 间隔的理由：换聊天频道只发生在主播重新开播，旧频道随即完全没有新行（D01.17 实测）；网站每 30 s 读一次。只在 3 分钟没有任何行时读：热门直播几乎不会多出请求，冷门直播每安静 3 分钟多 1 个请求（网站同样时间 6 个），也不会因为冷门直播正常的一两分钟空白就去读。代价是主播重新开播后最多约 3 分钟才换过去。
- 没有新增设置（决定一列没有要求）。

### 与决定、与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 事后屏蔽按条撤回（`LiveRetraction.message`），没有用任务说明里的“按用户撤回”（`LiveRetraction.user`） | 94008 用用户和时间指定一行，网页也只把那一行改成屏蔽。平台要撤下某位观众的全部发言时，会对他的每一行各发一个 94008：S14 里临时限制一位观众后，平台对他的 20 行（其中 4 行本连接已显示）各发了一个 `HIDDEN`，逐条撤回的效果就是撤下他的全部发言，和网页相同；按用户撤回会让一次清洁机器人屏蔽撤下这位观众的所有发言，比网页多 |
| 2 | 视频捐赠（`donationType` `VIDEO`）也显示为醒目留言，文字是视频标题 | 网页的聊天列表不显示它（视频在直播画面里播放，`case Ly.DONATION` 的 `default` 返回空）；但它是带金额的捐赠（S11 录到两条，1,000 和 1,820 치즈），D01.17 起也已显示它的标题 |
| 3 | 置顶公告和订阅赠送的句子是中文 | 网页用自己的界面文字拼这两种句子（韩文），这里按规则用中文照网页的意思拼，平台给的名字、内容、档次名不翻译 |

### 新样本和脱敏

2026-09-30 15:15～15:50 UTC（韩国时间 10 月 1 日零点前后），匿名、只读、直连，不登录，不发言。录制程序（`scan.dart`：150 场热门直播各读一次直播状态、取令牌、只读加入、请求一次最近聊天后关闭；`listen.dart`：16 场同时录 900 s，只发加入、最近聊天请求、20 s 的 ping 和回服务端的 pong）和脱敏脚本没有放进仓库，`meta.json` 的 `tool`、`note`、`kept`、原始录制的 SHA-256 写明了来源。

- `danmaku/S13-recent`：三场直播的最近聊天回答（从 138 个回答里挑的）：主播自己置顶、主播置顶观众的一行、聊天管理员置顶；一条只给管理员看的限制系统行；匿名的 `CHAT`、`MISSION_PARTICIPATION`（40,000 치즈）、`MISSION`（20,000 치즈）捐赠。138 个回答里没有订阅赠送。
- `danmaku/S14-live`：一场约 7 500 人的直播录 900 s 中的 60 行：直播状态、路由、令牌回答，加入，最近聊天（带置顶），一条推送的匿名捐赠，一次清洁机器人屏蔽（94008 `CBOTBLIND` 和那行），两次临时限制（93006 `TEMPORARY_RESTRICT` 之后各有一串 94008 `HIDDEN`，共 26 个，和一条只给管理员看的系统行），以及后来被限制的观众在此前显示过的 3 行（最近聊天里另有 1 行）。
- `danmaku/S15-live`：另一场约 2 800 人的直播录 900 s 中的 18 行：同样的开头，一次匿名赠送 2 张订阅券给指定观众（93006 `SUBSCRIPTION_GIFT` 事件，和每位接收者一条种类 12 的 `SUBSCRIPTION_GIFT_RECEIVER` 行、一个 93006 事件），一条推送的捐赠。
- `danmaku/S16-synthetic`：合成帧（6 组 42 帧），由 `danmaku/synthetic_cases.py` 生成（和 S12 同一个脚本），形状照 S13～S15 和网页脚本：金额五档的边界、字段类型不对的捐赠、各种订阅赠送、系统行、置顶公告、94008 的各种情形和坏数据。
- `danmaku/S17-live-status-closed`：已下播频道（S05 的频道）的直播状态回答（`CLOSE`，`chatChannelId` 为空）。开播的直播状态回答是 S14、S15 的第 0 行。
- S12 的两组改了名字（写明 B-12 后的新行为），帧不变；`v4_expected.dart` 重新运行，`expected.json` 只有这两个组名变了。
- 脱敏照 D01.17 的规则：用户号、昵称（`extras`、`weeklyRankList`、`registerProfile` 里的也算）、令牌、会话号、`uuid`、捐赠号换成同形同长度的值，同一个人始终是同一组值；本次另外换掉 `anonymousToken`、`giftId`、`missionDonationId`、`relatedMissionDonationId`、直播状态的 `liveTokenList`、接收者的 `receiverNickname` 和 `receiverUserIdHash`、限制记录里的 `registerNickname`、`targetNickname` 和嵌套的 `registerChatProfileJson`、`targetChatProfileJson`，以及限制说明文字里的观众昵称。主播的公开频道号和名字、聊天文字、金额保留。嵌套的 JSON 按原来的转义写回（有的客户端把 `=` 写成 `=`），直播状态回答里的 emoji 保留代理对转义，其余字节与服务端的相同。脚本自查原值都不在输出里、没有 IPv4 地址；门禁的 `fixture privacy` 通过。

### 没能实测的部分

- 直播中换置顶（94010）：16 场录了 900 s 都没有遇到。它的内容和最近聊天的 `notice` 同形（网页用同一个 `makeMessage` 读），S13～S15 的 `notice` 是真实的；94010 本身和“没有置顶”（时间为 0）用合成帧（S16）。
- 送给频道的订阅赠送行（`giftType` `SUBSCRIPTION_GIFT`）：S15 那次送给指定观众，只有每位接收者的行；送给频道的行照网页脚本（`zC` 读 `giftTierName`、`quantity`，匿名看 `anonymousToken`）用合成帧。
- 慢速模式（`styleType` 5）等网页另有专门文字的系统行没有录到：网页用自己的文字（`<秒数> 저속 모드 ON`），这里按通用规则显示标题和说明。
- 派对捐赠（`PARTY`）录到了两条（另一场直播，匿名，1,000 和 10,000 치즈，一条没有文字），没有放进样本；它和其他捐赠走同一条路径。
- 真正的换聊天频道：没有等到主播重新开播。直播状态的开播、下播回答是真实的，换频道的流程用本地假连接测试。

### 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 表情图片（候选 2） | A01.1 |
| 醒目留言栏显示 `priceText`、按 `endTime` 收起；通知在聊天列表里单独一行；撤回从聊天列表去掉对应的行 | M13（D01.1 的模型追加） |
| 过滤链只对聊天做 45 s 年龄检查；醒目留言有 `endTime`，最近聊天里较早的通知（系统行、订阅赠送带 `sentAt`）是否隐藏由界面决定 | M13 |
| `익명의 후원자` 和中文句子的多语言文字 | M13 |
| 重新进房拿到新的 `chatChannelId` 时重建连接（原“放到其他模块的部分”一条）仍保留；连接自己换频道只在它开着时起作用 | M13 |

### 测试

`test/chzzk_test.dart` 74 个用例（原 56 个，新增 18 个），`live_danmaku` 共 1327 个，全包连续 10 次全部通过（更早的一次全包运行有用例失败，没有留下输出；之后本文件单独 10 次、全包 10 次都没有复现）；直接作为 Dart 程序在 `SHIFT_SECONDS` 为 0、+30 天、+1 年、+5 年下运行都通过并正常退出。

原有用例因条目改变的期望（都在测试里注明 B-12）：投影把醒目留言还原成 v4 的“礼物 + 聊天”，`_shared` 不再丢掉 v4 的礼物；S10 的系统行和屏蔽通知分别多出通知和撤回（逐帧对照、回放、本地服务器的条数 106 → 108）；S11 的捐赠改为醒目留言；人数一项改为“不出现人数和礼物”；S12 的系统行、订阅赠送、94008、94010 四帧的差异；最近聊天一组的 v4 礼物留在读法里。

| 新增用例 | 内容 |
|---|---|
| 醒目留言 | S11 的具名捐赠逐字段；五档边界的时长和金额写法；字段异常（金额是文字、负数、缺少，没有文字也没有金额，没有时间用收到的时间，NAVER 和别处的头像，`extras` 坏了） |
| 录制帧 | S13：任务、任务参与捐赠，只给管理员看的系统行不报，三种置顶的句子和字段；S14：两次限制的 27 个撤回覆盖已显示的 4 行、撤回本身的字段、限制系统行不报；S15：匿名赠送给两位观众是两条订阅通知，赠送事件不报 |
| 合成帧（S16） | 订阅赠送 9 帧、系统行 7 帧、置顶公告 8 帧、94008 9 帧逐帧对照；直播状态：S14、S15 的开播回答、S17 的下播回答和 8 种坏回答 |
| 连接 | 醒目留言、通知、撤回的上报，重连后最近聊天不重报醒目留言和通知（聊天照报）；没有时间的捐赠用连接的 `clock`；安静 3 分钟读一次（请求的地址、请求头、超时、不跟随跳转），同一频道再等；换频道（新令牌、同一组服务器、旧连接失效、再报就绪、请求新频道最近聊天）；推送的行重新计时、pong 和事件不算，没有 `channelId` 不计时；状态失败、下播、异常、拿不到新令牌时不动并再等；读状态时关闭会取消请求、不再有动作 |

另做了变异检查，下面每一种改动都会让用例失败：按用户撤回、撤回 `CANCEL`、显示只给管理员看的系统行、安静时间改成 2 分钟、去掉本次连接内的去重、金额不加逗号、换频道前不标为未连接、置顶公告用那行的 id、置顶公告带时间、档次边界改动、外壳写成留言文字、推送的行不重新计时、任何帧都重新计时、下播的回答也换频道、没有 `channelId` 也计时、直播状态跟随跳转、匿名赠送只看资料、系统行用空格连接、总当作作者自己置顶、丢掉视频捐赠、不读最近聊天的置顶。
