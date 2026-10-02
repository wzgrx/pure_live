# D01.29 弹幕（新增）：LOOK 直播

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/looklive.dart`
  - `LookLiveDanmakuConnection`：连接（D01.1 的 WebSocket 运行时，握手前先取 socket.io 会话）；
  - `LookLiveDanmakuProtocol`：聊天服务器请求、socket.io 握手、云信（网易云信 NIM）聊天室的登录和心跳、帧的解码，不做 I/O；
  - `LookLiveDanmakuFrame`（一帧解出的内容）、`LookLiveGuest`（匿名游客身份）。
- 参数：本模块在 `live_core` 本平台补了 `LookLiveDanmakuArgs(roomId, chatroomId, anonymousMode)`（只加，不改已有行为）：
  - 进房（`getRoomDetail`）和录制详情在房间回答是直播中时放进 `LiveRoom.danmakuData`：`roomId` 是房间号（`liveRoomNo`），`chatroomId` 是云信聊天室（房间回答的 `roomInfo.roomId`，不是房间号），`anonymousMode` 是房间回答的 `anonymousMode`（房间把观众名字打码，见“解码”）；
  - 都来自进房本来就发的那个 `room/get/v3`，不多发请求；未开播、封禁、状态未知、没有聊天室 id 的回答，关注刷新和列表卡片都没有参数，按 D01.1 不连接；
  - 聊天服务器地址不在参数里：网页每次进聊天都现取（见“协议”），本实现在连接时取，不放进进房。
- 升级条目：32-7“聊天（网易云信）”。v3 的 LOOK 直播是 `EmptyDanmaku`，这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/looklive/danmaku/S05-live`，本模块只读匿名补录（2026-09-30 12:19 UTC，直连，声音推荐里在线最多的房间 447365581，320 s，140 行），见“样本”。`expected.json` 由 `fixtures/looklive/danmaku/web_expected.js` 生成（网页自己的解码代码，见“与网页代码的对照”）。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：**没有** LOOK 的弹幕实现；规格 `spec/sites/looklive.md` 第 7 节只写了“直播间聊天走网易云信 IM（需要云信的 appKey 和匿名登录流程），匿名接入待确认”；
  - pure_live_TV `e1cca224`：`lib/platforms/looklive/` 的 `getDanmaku()` 是 `EmptyDanmaku`，没有可参考的实现；
  - E02.13 文档“留给其他模块”里 T02.U 记下的线索（`online.appKey`、`roomInfo.roomId`、`chat/address`、`nimanon_`），本模块逐条核实；
  - LOOK 官网公开页面加载的脚本（2026-09-30 取 `https://look.163.com/live?id=21623631`，静态目录 `s7.music.126.net/static_public/672de53804e2cd654a6450c0_672de53804e2cd654a6450c1/`）：`app.437aa9a876c6e88708b1.js`（下称 app）、按需加载的 `Live.f58eedd602695ad4f195.js`（Live）和 `Chatroom.e3d6b7d6edc11115bba6.js`（Chatroom，打包了云信 Web SDK 5.0.1 和 socket.io 0.9.11）；脚本约 1.8 MB，只作依据，不进仓库；
  - 2026-09-30 12:10～12:35 UTC 的只读实测：匿名、直连，不登录、不发言、不送礼，见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码只写这几样：
  - `target`：检查参数，取房间的聊天服务器，给出每个服务器的 socket 地址；
  - 握手（`connector`）：每次先 GET 一个 socket.io 会话，再用会话号打开 WebSocket（同 D01.12 TwitCasting、D01.22 PandaTV 把请求放进握手的做法，框架没有改）；
  - `onOpen`：新 socket 的状态清零；
  - `onData`：解一帧，回心跳、会话打开时登录、登录回答到了才就绪、上报聊天；
  - `heartbeatFrame`：云信的链路心跳。
  - 换地址、退避、最多 8 次、无消息检测、加入超时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **聊天服务器每次 `connect` 取一次**：`POST https://api.look.163.com/weapi/livestream/chat/address`，载荷 `{"liveRoomNo":"<房间号>","os":0}`，和适配器的其他请求一样是 `weapi` 信封、3.x 的请求头、不跟随跳转、以 `looklive` 的名义发出（代理路由按平台）。失败时 2 s 后再取一次（网页的 `catchError(timer(2e3))`），还失败以 `DanmakuClosed(connectionFailed, 'Chat servers: …')` 结束；回答 `code` 404“无资源”（房间不在播）直接以 `connectionFailed`（`No chat: …`）结束，不再取。重连时照网页 SDK 沿用同一组服务器，按回答的顺序轮换。
- **socket.io 0.9 的会话在握手里取**：每次握手先 GET `https://<服务器>/socket.io/1/?t=<毫秒>`，回答 `<会话号>:<心跳超时>:<关闭超时>:<传输方式>`（实测 `…:90:30:websocket,xhr-polling`），再打开 `wss://<服务器>/socket.io/1/websocket/<会话号>`。GET 走注入的 `LiveHttp`（平台 `looklive`），时限用框架的握手时限（10 s，也是 socket.io 客户端的 `u.timeout = 1e4`）；GET 失败、状态不是 200、回答读不出会话号或不支持 websocket，都当作这次握手失败，走框架的退避。
- **匿名游客登录**：服务器发来 `1::`（会话打开）时发一次云信聊天室登录，登录回答 `code` 200 才就绪。身份是每次 `connect` 随机生成的游客（`nimanon_` 加 32 位十六进制、设备号、SDK 会话号，照 SDK 的 `guid()`），同一次连接的重连沿用；网页把匿名账号存在 `localStorage` 里下次再用，本实现不存。没有令牌、没有 Cookie，网页对游客也是如此（`token: ""`）。
- **登录被拒、被踢**：登录回答的 `code` 是 408、415、500、503（SDK 错误表：超时、没有聊天室服务器可分配、服务器内部错误、繁忙）时重连，连续 3 次后第 4 次结束，加入成功一次就重新计数；其他 `code`（403、404、13002 聊天室状态异常、13003 黑名单等）直接以 `DanmakuClosed(connectionFailed, 'Login refused: <code>')` 结束（SDK 这时同样不再重连）。被踢（13-3）的原因是 4（`silentlyKick`）时重连，其他原因（1 聊天室关闭、2 被管理员踢出、3 同账号另处登录、5 拉黑）以 `connectionFailed`（`Kicked: <原因>`）结束，同 SDK 的 `onKicked`。
- **心跳**：socket.io 服务端每 25 s 发 `2::`，客户端原样回 `2::`（socket.io 0.9 客户端只回、不主动发）；云信的链路心跳（1-2）在登录后每 180 s 发一次（SDK `heartbeatInterval: 18e4`）。框架的心跳计时器每 30 s 一跳：第 6 跳发链路心跳（正好 180 s），其余几跳什么都不发，只用来检查无消息（3 跳 = 90 s，正是握手回答的心跳超时，服务端每 25 s 都有 `2::`）。手动 `heartbeat()` 在已登录时立即发一次链路心跳。
- **只上报聊天**：文字聊天和表情消息（见“解码”）。醒目留言、付费留言平台没有；礼物、进场、公告、点歌、PK 等都不报（和 D01.2～D01.22 的范围一致）。
- **在线人数的来源不变**：聊天流里没有 LOOK 页面显示的在线人数（见“在线人数”），`audience.dart` 本平台一项（列表的 `onlineNumber`，`roomList`）不改。

## 协议

### 连接

| 项目 | 内容 | 出处 |
|---|---|---|
| appKey | `3a6a3e48f6854dfa4e4464f3bdaec3b4`，网页配置里公开的 `online.appKey` | app，模块 `d4h+`（约 52% 处） |
| 聊天服务器 | `POST /api/livestream/chat/address`，`{liveRoomNo, os: 0}`；网页的请求封装把 `/api/` 换成 `/weapi/` 并加密（没有 `__csrf` Cookie 时不带 `csrf_token`）；回答 `data.address` 是 `host:port` 列表（实测 `chatwl01.yunxinfw.com:443` 等 4 个）；不在播的房间回答 `code` 404“无资源” | Live，模块 `qKXv`（约 87% 处，游客分支只发这一个请求，登录用户另取 `/api/livestream/im/imto` 等）；app，模块 `0CZ9`（`/api/`→`/weapi/`）；实测 |
| 聊天室 id | 房间数据的 `roomId`（房间回答 `roomInfo.roomId`），传给 SDK 的 `chatroomId` | Live，模块 `qKXv`（`d.default.init({roomId: l, …})`）；实测登录回答的聊天室 `1` 等于它 |
| 游客身份 | 没有账号时 `{chatroomNick: "匿名用户", isAnonymous: true}`；SDK 给匿名账号 `"nimanon_" + guid()`，`chatroomAvatar` 默认一个空格；`token: ""` | app，模块 `RoOs`（`getUserInfo`，约 41% 处）、`Ph1m`（`init`，约 37% 处）；Chatroom，约 44% 处（`e.isAnonymous && (e.account = e.account \|\| "nimanon_" + u.guid())`） |
| 地址格式 | SDK 把每个地址补成 `https://`（`secure` 默认为真），按顺序试，用完一轮从头再来（`refreshSocketUrl`） | Chatroom，`formatSocketUrl`（约 5% 处）、`ChatroomProtocol.reset` |
| socket.io 握手 | `GET https://<host>:<port>/socket.io/1/?t=<Date.now()>`，200 时回答 `sid:heartbeat:close:transports`，XHR 超时 10 s；WebSocket 地址 `wss://<host>:<port>/socket.io/1/websocket/<sid>` | Chatroom，socket.io 0.9.11 的 `handshake`、`prepareUrl`（约 25%～30% 处）；实测 `…:90:30:websocket,xhr-polling` |
| 包格式 | `类型:id:端点:数据`；0 断开、1 连接、2 心跳、3 消息、7 错误、8 空操作；多个包可以用 `\ufffd<长度>\ufffd<包>` 拼在一帧里；带 id（不带 `+`）的消息要回 ack `6:::<id>` | Chatroom，socket.io 的 `parser`、`SocketNamespace.onPacket` |
| 心跳 | 服务端每 25 s 发 `2::`，客户端回 `2::`（`Transport.onHeartbeat`）；超过握手给的心跳超时（90 s）没有任何包就关掉 | Chatroom，`Transport.onPacket`、`setHeartbeatTimeout`；实测 12 次，间隔 25.06 s |

### 云信聊天室

数据是 SDK 的 JSON：命令 `{"SID":服务,"CID":命令,"SER":序号,"Q":[{"t":类型,"v":值}…]}`，回答 `{"sid","cid","ser","code","r":[…]}`，属性按编号（SDK 的 `serializeMap`/`unserializeMap`），`code` 200 是成功。出处都在 Chatroom 里（SDK 的 `cmdConfig`、`packetConfig` 和属性表，约 95%～99% 处）。

| 命令 | 内容 | 本实现 |
|---|---|---|
| 登录 13-2 | `Q`：`byte` 1；`login` 属性 `1` appKey、`2` 账号、`3` 设备、`5` 聊天室（数字）、`8` appLogin、`20` 昵称 `匿名用户`、`21` 头像 `" "`、`26` SDK 会话、`38` isAnonymous 1；`imLogin` 属性 `4` 系统、`6` SDK 版本 `"47"`、`8` appLogin、`9` 协议版本 1、`13` 设备、`18` appKey、`19` 账号、`24` 浏览器、`26` 会话、`1000` 令牌 `""`（`assembleLogin`、`assembleIMLogin`）。第一次登录 `login.8` 为 0、`imLogin.8` 为 1，重连后是 1 和 0；序号从 1 往上数（`createCmd`） | 照发，同一次连接里序号递增；系统和浏览器写 SDK 在桌面 Chrome 上报的 `Windows 10 64-bit`、`Chrome 140.0.0.0`（服务端不检查） |
| 登录回答 | `r[0]` 聊天室（`1` id、`3` 名字、`100` 创建者即主播、`101` 在线成员数 `onlineMemberNum`…），`r[1]` 自己的成员信息（类型 4 游客） | `code` 200 就绪；其他见“登录被拒” |
| 链路心跳 1-2 | `{"SID":1,"CID":2,"SER":0}`，登录后每 180 s（`startHeartbeat`，`heartbeatInterval: 18e4`），回答 `{"sid":1,"cid":2,"ser":0,"code":200,"r":[]}` | 同（见“做法”） |
| 消息 13-7 | 包在通知 4-10 里：`r[1].headerPacket` 是 `{sid:13,cid:7}`，`r[1].body[0]` 是消息（`parseResponse` 对 4-10、4-11 的处理）；消息属性 `1` idClient、`2` 类型（0 文字、100 自定义、5 通知…）、`3` attach（文字消息的正文就在这里，`TextMessage.reverse`：`t.text = e.attach`）、`4` custom、`13` body、`20` 时间（毫秒）、`21` 发送者账号、`23` 客户端类型 | 通知和直接的 13-7 都读 |
| 被踢 13-3 | `r[0]` 原因、`r[1]` 附加文字；原因表 `["", "chatroomClosed", "managerKick", "samePlatformKick", "silentlyKick", "blacked"]` | 见“做法” |

### 解码

LOOK 对消息的取舍在 app 的模块 `Ph1m`（`ignoreMsgs` 和 `onmsgs`）和 Live 的模块 `COdP`（`getMsgElement`，约 15% 处）：

- **文字消息**（类型 0）：正文为空丢掉；`custom` 是 JSON，`sp` 为 1 时先按短键表展开（app 模块 `NomM` 的 `parseIM`：`c`→`content`、`u`→`user`、`n`→`nickname`、`i`→`userId`、`l`→`liveLevel`、`fcl`/`fcn` 粉丝团…）；`bizName` 不是 `iplay`、没有 `custom` 或读不出来的都丢掉（`shouldIntercept` 在回调里取不到应用设置，按默认的真处理）；`custom.content.commonCtrl.riskLevelKey` 有值、而观众的 `riskLevel` 里没有它的丢掉（游客的 `riskLevel` 是空的）；没有 `content.user` 的不显示。
- **表情消息**（自定义消息，类型 100，发送者必须是 `musiclive_server`，`custom.type` 2601）：页面显示用户、表情图片和表情名（`content.emoji` 是 JSON 文字，`name`、`previewUrl`）。本实现报成 `[表情名]`（同 D01.22 只有表情的聊天）。录制里没有遇到，按网页脚本和合成用例测试。
- 其他自定义消息（102 礼物和点歌、114 进场、140 粉团升级、104 关注、105 分享、303 全站公告、55000 只给某个观众看的欢迎语、200067、300042、702～715 PK、952、956 抽奖、7778 奖励包、10000 图片、12008 演唱得分、120 播放状态等）和通知消息都不报。

一条聊天：

- 文字是 `3`（去首尾空白；数字照写）；表情是 `[名字]`；
- 用户名是 `content.user.nickname`，没有时 `nickName`（页面 `l || o`）；房间 `anonymousMode` 为真时照房间页打码成“第一个字 + `***`”（页面是 `substring(0, 1)`，本实现取第一个完整字符，不会切开表情的代理对）；页面在名字为空时写“匿名用户”，本实现留空（统一原则“占位信息”）；
- 用户 id 是 `content.user.userId`，没有时用消息的发送者账号 `21`（两者在录制里相同）；
- 等级 `liveLevel`、粉丝团等级 `fanClubLevel`、粉丝团名 `fanClubName`（没有时读 `fanClubInfo` 里的，页面同样如此），等级只取正整数；
- 消息 id 是 `idClient`（SDK 按它去重，框架的去重闸门同样用它），时间是 `20`（毫秒），超出 `DateTime` 范围为空；
- 颜色白色（文字消息没有颜色字段，`msgDisplayInfo` 只有字体和气泡的配置号）。

帧的解法：先按 socket.io 0.9 拆包（支持 `\ufffd` 拼包，长度按 UTF-16 单位，同 JavaScript），端点不是默认端点的包跳过；消息包的数据按 SDK 回答读，读不出的跳过；二进制帧按 UTF-8 解码（服务端没发过）。

## 连接和时序

| 项目 | 本实现 | 网页（SDK 5.0.1、socket.io 0.9.11） | 依据 |
|---|---|---|---|
| 聊天服务器 | 每次 `connect` 取一次，失败 2 s 后再取一次，404 直接结束 | 进房时取一次，失败 2 s 后重试一次 | 同网页 |
| 地址 | 回答的顺序；失败换下一个，一轮后从头 | 同（`getNextSocketUrl`、`refreshSocketUrl`） | 同 |
| 握手 | 每次先 GET socket.io 会话，再开 WebSocket；请求头 `Origin: https://look.163.com`、3.x 的 UA `Mozilla/5.0`（GET 另带房间页作 `Referer`） | 浏览器的 XHR 和 WebSocket | 实测 `Mozilla/5.0` 可以握手（`dart:io` 会在前面加自己的名字） |
| 加入 | 收到 `1::` 发登录，登录回答 200 就绪；每次重连加入都再报一次 `DanmakuReady` | 同（`onConnect` → `login` → `notifyLogin`） | 实测登录回答在 0.05～0.12 s 内到 |
| 加入超时 | 10 s，超时直接重连 | 命令超时 42 s（`cmdTimeout`） | 42 s 太长，界面会一直“连接中”；实测不到 0.2 s |
| socket.io 心跳 | 收到 `2::` 立刻回 `2::` | 同 | 实测服务端每 25 s 一次 |
| 链路心跳 | 登录后每 180 s（6 × 30 s 的计时跳）；手动 `heartbeat()` 立即发 | 登录后 180 s，之后每次回答后再等 180 s | 同间隔；框架的计时器在 socket 打开时起算，和登录相差不到 1 s |
| 无消息超时 | 90 s（框架默认 max(3 × 30 s, 90 s)，每 30 s 检查一次） | 90 s（握手回答的心跳超时） | 同 |
| 断线重连 | 框架默认：换下一个服务器，4 个服务器时间隔 1、1、1、2、2、2、2、3 s，最多 8 次，收到任何帧清零，一轮只提示一次；每次都重新取会话、重新登录（序号递增，appLogin 按重连） | SDK 自己的退避（656 ms 起，最多 42 s，不限次数） | 框架的统一做法 |
| `0::`、`7:::` | 换 socket 重连 | SDK 在 socket.io 断开、出错时重连 | 同 |
| 登录被拒 | 408、415、500、503 重连，连续 3 次后第 4 次结束；其他结束 | 一律不再重连（`onAuthError`） | 服务端暂时不可用时不该让整场没有弹幕；其他码重试也没用 |
| 被踢 | `silentlyKick` 重连，其他结束 | 同（`onKicked`） | — |
| 下播 | 不处理 203（`END_STREAM`）等下播消息；聊天室关闭时服务端踢出（原因 1）就结束 | 收到 203 断开聊天、提示 | 放到 M13 |
| 停止 | 关掉 socket，取消进行中的请求 | 断开前发 `0::` | 服务端按连接关闭处理，效果相同 |
| 参数不对 | 房间号不是 2～18 位、聊天室 id 不是能作 JSON 数字的正整数：`connectionFailed`，不请求、不握手 | — | 聊天室 id 要作为数字写进登录 |

## 规格来源

归档 v4 和上游都没有本平台的弹幕，协议结论全部来自官网脚本和实测帧（互相印证，没有矛盾）：

| 结论 | 脚本（文件、模块、大致位置） | 实测帧（S05-live 的行） |
|---|---|---|
| appKey | app `d4h+`（52%） | 第 4 行的登录用它，第 5 行登录成功 |
| 聊天服务器接口和载荷、`/weapi/` | Live `qKXv`（87%）；app `0CZ9` | 第 1 行；`meta.json` 的 `requests[0]` |
| 聊天室 id 是 `roomInfo.roomId` | Live `qKXv`（`init({roomId})`） | 第 5 行的聊天室 `1` 是 9902460973 |
| 游客（`nimanon_`、`匿名用户`、空令牌） | Chatroom（44%）；app `RoOs`、`Ph1m` | 第 4、5 行（成员类型 4） |
| socket.io 0.9 握手和包格式 | Chatroom，socket.io 0.9.11（25%～30%） | 第 2、3 行，`meta.json` 的 `handshakes` |
| 登录的组装 | Chatroom `assembleLogin`、`assembleIMLogin`、`createCmd` | 第 4 行与 `web_expected.js` 用 SDK 代码组装的结果逐字节相同 |
| 心跳 | Chatroom `heartbeatInterval: 18e4`、`Transport.onHeartbeat` | `2::` 12 次；第 83 行链路心跳的回答 |
| 消息在 4-10 里、文字在 `attach` | Chatroom `parseResponse`、`TextMessage.reverse` | 第 6 行起；观众的消息只有 `3` 没有 `13` |
| 聊天的取舍、用户字段 | app `Ph1m`、`NomM`；Live `COdP` | 47 条聊天，见“与网页代码的对照” |
| 消息类型常量 | Live `DhJI`（`ONLINE_NUMBER: 200`、`END_STREAM: 203`、`EMOJI: 2601`…） | — |

## 在线人数

聊天流里没有 LOOK 显示的在线人数，所以不上报人数，`audience.dart` 不改：

- 登录回答的聊天室 `onlineMemberNum` 是连着这个云信聊天室的连接数，不是列表卡片的 `onlineNumber`：同一房间实测 26、51、55，而几分钟内声音推荐给的 `onlineNumber` 是 79～99。把它当在线人数会和列表、进房补上的人数对不上；
- 消息类型表里有 `ONLINE_NUMBER: 200`，但网页代码没有用它，320 s 的录制和另外约 9 分钟的实测里也没有出现；
- 网页直播间的热度另外每 60 s 拉 `/api/livestream/room/sync/v1`（Live `ROY9`），不走聊天。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.lookLive: () => LookLiveDanmakuConnection(http: lookLiveHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `LookLiveSite` 的同一个 `LiveHttp`。聊天服务器请求和 socket.io 的会话请求都以 `looklive` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `looklive` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie、账号：全程匿名，3.x 的 LOOK 也没有账号。
- `connector`、`policy`、`now`、`random`、`addressRetryDelay` 只给测试用，应用不传。默认握手是 `dart:io`，不需要保留请求头大小写（不用 `connectExactWebSocket`）。
- 参数来自 `getRoomDetail`（和录制详情）；未开播、刷新得到的房间没有参数，按 D01.1 不连接。

## 与网页代码的对照

- 生成器：`fixtures/looklive/danmaku/web_expected.js`（Node）把网页脚本里读的那一半原样搬进来（用 `@babel/generator` 还原格式，其余不改，改动处都有注释）：socket.io 0.9.11 的 `parser`；SDK 的 `createCmd`、`parseResponse`、`serialize`/`unserialize` 和聊天室的命令、数据包、属性表；消息模型（`Message`、`TextMessage`、`CustomMessage` 的 `reverse`）；LOOK 的 `ignoreMsgs`、`parseIM` 和 `onmsgs` 里的风险等级过滤；Live `getMsgElement` 里决定哪些消息成为聊天行的分支。它读 `S05-live/frames.jsonl`，对每个收到的 socket 帧写下包类型、要回的包、是否登录成功、链路心跳回答和聊天行（idClient、时间、发送者、用户 id、名字、正文、等级、粉丝团），并用 SDK 的 `createCmd` 按录下的游客身份组装登录包。运行：在仓库根目录 `node fixtures/looklive/danmaku/web_expected.js`，结果在 `S05-live/expected.json`，`generator` 写明来源。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| 登录包 | 本实现的 `login()`（录下的游客身份、序号 1）与录制第 4 行、与 SDK 组装的结果逐字节相同 |
| 123 个收到的 socket 帧 | 逐帧一致：`1::` 1 个、`2::` 12 个（都回 `2::`）、第 5 行登录成功、第 83 行心跳回答，47 条聊天（35 条房间助手账号的欢迎语、12 条两位观众的聊天）的消息 id、时间、用户 id、名字、正文、等级、粉丝团逐条相同；61 条其他自定义消息都不报。名字和正文的去空白、等级的“只取正整数”是本实现的规则，比较时照此换算网页的值 |
| 请求和握手 | 聊天服务器请求的载荷、请求头与录制的 `meta.json` 相同，也与 `LookLiveSite` 发出的请求（站点、方法、请求头、不跟随跳转、20 s 时限）相同；socket.io 会话地址、WebSocket 地址与录制相同（`Uri` 会省去 https 的默认端口 443，比较时按 `Uri` 比较） |
| 用连接重放录制 | 1 个聊天服务器请求、1 次会话、1 个 socket，就绪 1 次，发出的帧与录制相同（登录、12 次 `2::`、手动心跳时的链路心跳；录制程序离开时发的 `0::` 本实现不发），47 条聊天按顺序上报 |

## 与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 加入超时 10 s | SDK 等 42 s；实测不到 0.2 s。超时后按框架重连 |
| 2 | 退避按框架（最多 8 次），SDK 不限次数 | 各平台统一；8 次失败后界面提示，由用户决定是否刷新 |
| 3 | 可以恢复的登录拒绝码（408、415、500、503）重连 | SDK 一律停止；这些码是服务端暂时的问题 |
| 4 | 不处理下播（203）、违规（302）、管理员消息（301）等房间状态消息 | 放到 M13；连接本身在聊天室关闭被踢出时结束 |
| 5 | 不报礼物、进场、点歌、公告 | v3 所有平台都不显示礼物，D01.2～D01.22 也都不报 |
| 6 | 游客身份每次连接新生成，不存 | 网页存在 `localStorage`；应用没有必要让服务端认出同一个游客 |
| 7 | 名字为空时留空，不写“匿名用户”；打码时不切开代理对 | 统一原则“占位信息”；页面的 `substring(0, 1)` 会把表情切成半个 |
| 8 | 停止时不发 `0::` | 直接关闭 socket，服务端同样结束会话 |
| 9 | 不请求历史消息 | 网页连上后取最近 1 分钟的 5 条文字（`getHistoryMsgs`）；和其他平台一样只报连上之后的 |

## 实测

2026-09-30 12:10～12:35 UTC 只读、匿名、直连，没有登录，没有发言，没有送礼。先用小脚本（Python：`weapi` 请求、socket.io 握手、手写的 WebSocket 客户端，只发 SDK 对游客会发的登录、`2::` 回应和一次链路心跳），再用本实现连了一次：

- **聊天服务器**：在播的房间回答 4 个 `chatwlXX(-bgp).yunxinfw.com:443`；已下播的房间（325808387）和不存在的房间号 `1` 回答 `code` 404“无资源”；仅限 App 的房间（645235480）照样给地址。
- **会话**：两个服务器的握手都回答 `<uuid>:90:30:websocket,xhr-polling`。
- **登录**：带 appKey、`nimanon_` 账号、空令牌的匿名登录成功，`r[1]` 是游客（类型 4），聊天室名字 `online_liveChatRoom_110013407_<主播 id>`、创建者是主播。
- **下行**：房间 447365581 录了 20 s、240 s、320 s 三段，房间 610786917 录了 200 s（没有人聊天，只有演唱得分 12008、播放状态 120、进场 114 和 200067）。聊天都是 4-10 通知里的 13-7：房间助手账号（网页客户端发的，`13` 和 `3` 都有正文）和观众（手机端发的，只有 `3`，另有统计字段 `39`）；`custom` 都是 `bizName` `iplay` 的 JSON，观众的带 `type` 0、`roomId`、`text`、`isRoomManager`、`msgDisplayInfo` 和完整的用户信息，`fromCustom`（`9`）另有一份用户信息。没有见到 `sp` 为 1 的短键、表情 2601、人数 200。
- **心跳**：服务端 `2::` 的间隔 25.06 s；登录后 180 s 的链路心跳 0.06 s 内回答。
- **本实现**：用临时脚本（没有提交）经 `LookLiveSite.getRoomDetail` 取参数（`LookLiveDanmakuArgs(447365581, chatroom 9902460973)`），再用 `LookLiveDanmakuConnection` 连 60 s：就绪 1 次，收到 3 条聊天，名字、用户 id、等级、粉丝团、时间、消息 id 都有；`Mozilla/5.0` 的 UA 可以握手。

## 样本

`fixtures/looklive/danmaku/S05-live`：

- `frames.jsonl`（140 行）：第 1 行聊天服务器的回答，第 2 行 socket.io 会话的回答（带请求地址），之后是 socket 的全部文字帧（方向、相对毫秒、文字）；`meta.json` 记下请求、握手、`danmakuKeys`、录制时间、原始 SHA-256 和脱敏记录；`expected.json` 见上。
- 脱敏（逐帧、逐字段检查过，`meta.json` 的 `scrubbed` 有记录）：
  - 游客账号、设备号、SDK 会话号（登录包和登录回答里）、socket.io 会话号（握手回答和 WebSocket 地址里）换成同形同长度的合成值；
  - 聊天发送者的用户 id（`21` 和 `custom`、`fromCustom` 里的 `userId`）、昵称、头像路径、观众自己的房间号换成合成值，一个人在所有帧里用同一组；房间助手欢迎语里 `@` 到的 30 个观众名字换成 `观众4`～`观众32`；
  - 其他自定义消息（114 进场 43 条、303 全站公告 4 条、55000 私人欢迎语 6 条、200067 8 条）的 `custom` 只留 `id` 和 `type`，里面的用户信息、名字、头像都去掉了；
  - 主播 id（564597113）、房间号、聊天室 id、appKey、聊天服务器地址、头像框和勋章等公共资源图片、粉丝团名是公开信息，保留；
  - 帧都能按服务端的写法（紧凑、不转义中文）原样重新编码，嵌套的 JSON 文字就地替换，其余内容逐字节是录制。样本里没有调用方地址，门禁的 `fixture privacy` 通过。
- 录制原始数据和脱敏脚本在本机临时目录，没有提交。

## 受阻

没有。云信聊天室的匿名登录用网页公开的 appKey 即可，不需要登录态、签名或额外密钥。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表）。详情是 `No chat: …`（房间不在播）、`Chat servers: …`、`Login refused: <code>`、`Kicked: <原因>` |
| 房间公告 `looklive_chat_notice` 的文字 | 已在平台层改好：`LookLiveApi.chatNotice` 去掉“这里暂时看不到 LOOK 直播的聊天。”，只说明人数（“人数是正在观看的人数，热度另外显示。”）；3.x 的原文 T02.U 时已经不在代码里（对照测试把公告列为有意差异，不需要原文），没有加 `legacyChatNotice`；翻译在 M13 |
| 下播、违规、管理员消息 | M13 决定是否要：聊天流有 203（下播，内容里可能带轮播的下一个房间）、302（违规整改）、301（管理员私信）等，本实现不报；要用时在协议层加一个事件 |
| 显示礼物、进场（若以后要做） | M13 统一决定；本平台要解自定义消息 102、114 等 |
| 录制时是否带弹幕 | H01.1（录制详情也带参数） |
| E02.13 文档“留给其他模块”里 32-7 的线索和“平台层没有弹幕参数类” | 已由本模块落实；E02.13 文档本身没有改（本任务只改列出的文件） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | D01 各平台完成后删除（`LookLiveSite.getDanmaku()` 仍是 `EmptyDanmaku`，测试的说明改为弹幕在 `live_danmaku`） |

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖。`live_core` 只在本平台加了：`LookLiveDanmakuArgs`；`LookLiveRoom` 的 `chatroomId`、`anonymousMode`、`danmakuArgs`（`room()` 读出，`enrich` 保留本次回答的）；`LookLiveApi.liveRoom(withData: true)` 给出 `danmakuData`；`LookLiveApi.chatAddressPath`、`chatAddressPayload`、`chatAddresses`（沿用本平台已有的回答信封和状态映射）；公告文字。已有的解析、请求和输出不变（对照测试照旧通过）。

## 测试

`live_danmaku` 的 `test/sites/looklive_test.dart` 29 个用例，`live_danmaku` 共 992 个，连续跑 3 次全部通过；本文件在时钟 +30 天、+5 年下直接运行（`tools/timeshift` 的方式）也都通过，进程正常退出。握手的 `t` 用注入的时钟（录制时间），代码不拿任何时间和当前时间比较。

- 协议 12 个：常量和时序；聊天服务器请求与适配器的请求相同、载荷与录制相同；地址、socket.io 握手请求（含 `ws`→`http`）、录下的会话回答、坏回答（状态、太短、没有 websocket、非法会话号）、WebSocket 地址；参数检查（房间号、聊天室 id 的范围）；登录包与 SDK 的组装和录制逐字节相同、重连后的 appLogin 和序号；游客身份的格式；socket.io 包（连接、心跳、断开、错误、空操作、ack、别的端点、`\ufffd` 拼包、字节帧、坏的 UTF-8）；SDK 回答（登录成功和拒绝、被踢、直接的 13-7 和 4-10、4-11 通知、读不出的回答）；一条聊天的各字段；聊天的边界（类型、正文、`iplay`、风险等级的各种值、没有用户、名字和 id 的回退、等级、粉丝团回退、时间的范围）；表情消息和短键展开；打码。
- 录制 3 个：请求、握手与录制一致；123 个收到的帧与网页代码的冻结输出逐帧一致；用连接重放整份录制。
- 连接 14 个：时序和平台表登记；握手顺序（聊天服务器、会话、socket、代理路由、请求头）、`1::` 才登录且每个 socket 只登录一次、登录回答后就绪；不在播直接结束、失败重试一次、两次失败结束；会话失败换下一个服务器、一直失败 8 次后结束；掉线后新会话、新登录（序号 2、按重连）、再次就绪；`0::`、`7:::` 换 socket；可恢复的拒绝重连、第 4 次结束、加入后重新计数、其他码立即结束；被踢；登录超时重连；心跳（`2::` 回应、登录前不发、登录后第 6 跳才发、手动立即发）；参数不对直接结束、参数类型不对抛 `ArgumentError`；关闭时取消进行中的聊天服务器和会话请求、关闭后没有事件、换房间；打码的房间；真实的本地服务器（会话请求的地址和 `Referer`、WebSocket 路径、`Origin`、UA，登录、`2::` 回应、拼包里的聊天、手动心跳；结束时关掉服务端所有升级后的 WebSocket 和服务器，直接运行测试文件时进程能退出）。

`live_core` 本平台的测试：`looklive_api_test.dart` 新增 6 个（进房和录制给出参数、刷新不给；不在播、卡片、没有聊天室 id 时没有参数；`anonymousMode` 只认 `true`；`enrich` 保留本次回答的聊天；聊天服务器的请求载荷和录下的回答；地址的筛选、去重、404 和其他错误），公告测试改为新文字；`looklive_site_test.dart` 新增 1 个（进房、录制带参数且只有 1 个请求，刷新、不在播、列表没有参数），`getDanmaku()` 的说明改写。对照 3.x 的测试里公告仍列为有意差异（`_notice`，注释写明 T02.U 和 D01.29）。
