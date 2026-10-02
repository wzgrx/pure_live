# T06a.26 弹幕（新增）：酷狗直播

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/kugoulive.dart`
  - `KugouLiveDanmakuConnection`：连接（T06a.1 的 WebSocket 运行时）；
  - `KugouLiveDanmakuProtocol`：调度接口的地址、签名和回答的解析，登录帧、心跳帧，帧的解码，不做 I/O；
  - `KugouLiveDanmakuFrame`（一帧解出的内容）、`KugouLiveChatGrant`（调度给的地址和令牌）、`KugouLiveChatRefusal`（登录被拒）、`KugouLiveDispatchRefusal`（调度拒绝）。
- 参数：`live_core` 的 `KugouLiveDanmakuArgs(roomId)`，本模块在平台层补上（见“平台层的改动”）：进房（`getRoomDetail`）和录制详情在房间直播中时放进 `LiveRoom.danmakuData`，不多发请求；未开播、没有场次、关注刷新都没有参数。聊天只要房间号：地址和令牌由连接自己向网站的调度接口要，和网页一样。
- 升级条目：29-5“酷狗弹幕”。v3 的酷狗是 `EmptyDanmaku`，这是新增功能，没有 v3 行为可对照。
- 样本（都在 `fixtures/kugoulive/danmaku/`，本模块新录，2026-09-30，直连、匿名、只读）：
  - `S07-live`：房间 51049168（推荐列表里人最多的，约 98 人），300 s：调度回答、登录、两个状态帧、双向心跳、37 条聊天、5 个人数帧和不含个人信息的系统帧；
  - `S08-refused`：房间 1073619，故意用调度回答里的备用令牌 `backsoctoken` 登录，录下 622 拒绝；
  - `S09-pk-chat`：房间 1073619 PK 时，对方房间的一条聊天（400305）；
  - 三个目录的 `expected.json` 由 `web_expected.py` 生成（见“规格来源和期望值”）。
- 参考：
  - 归档 v4：没有酷狗弹幕。`spec/sites/kugoulive.md` 第 7 节只写了“不做。繁星的聊天是私有二进制 WebSocket 协议，旧版没有实现可参考，匿名接入方式 [待确认]”，第 12 节“待确认”的第 4 条是“聊天协议”；
  - pure_live_TV `e1cca224`：`lib/platforms/kugoulive/` 的 `getDanmaku()` 是 `EmptyDanmaku`，没有可参考的实现；
  - 所以规格只来自网站自己的房间页脚本和匿名连接时的真实帧，见“规格来源和期望值”“实测”。

## 做法

- **照网站房间页的做法匿名接入**：先调用网站的调度接口（`socket_scheduler`）拿到聊天服务器地址和登录令牌，再连 WebSocket、发匿名登录包，状态帧说登录成功就算加入。调度接口的签名是页面脚本里的 MD5 加固定盐（`$_fan_xing_$`），不是混淆的签名 SDK，也不要登录态和别的密钥；登录包里页面在网页端（非酷狗客户端）不加安全签名（`FxAjaxSafeGate` 只在酷狗客户端里可用）。全程不登录、不发言、不送礼，只发登录包、心跳和网页也会发的礼物确认。
- **建在 T06a.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码写这几样：
  - `target`：检查参数，调用调度接口（开始时最多 3 次），给出它的主机列表和握手请求头；
  - `onOpen`：发登录包（第一次 201；房间加入过之后的新 socket 发 2201，带上次的会话号 `socsid`，同网页）；
  - `onData`：解一帧；登录被接受（901，`type` 1、`status` 1）才就绪；被拒就换 socket（令牌被拒时先换令牌）；
  - `heartbeatFrame`：4 字节的二进制心跳 `64 00 01 00`。
  - 换地址、退避、最多 8 次、无消息检测、加入超时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **令牌在握手里按需更新**（同 T06a.22 PandaTV 的做法，框架没有改：`connector` 参数本来就允许替换握手）：调度给的令牌留给以后的 socket 用，和网页一样；以下情况下一次握手前先重新调用调度接口：
  - 令牌比调度回答的 `age`（5 分钟，网页在 `localStorage` 里缓存调度回答的时长）旧，或时钟倒退；
  - 服务端以 622 拒绝了令牌（网页的 `dispatchError622`）；
  - 令牌发出去的那个 socket 在服务端回答登录之前就断了或超时（服务端对不认识的令牌直接关闭连接，不回 901，实测）。
  - 重新调度的请求失败（网络、状态码、看不懂的回答）算这次握手失败，走框架的退避和 8 次上限；调度拒绝（`code` 不为 0，如签名不对 1100014、要人机验证 1100007）说明进不去了，以 `DanmakuClosed(connectionFailed, 'dispatch: code …')` 结束。
  - 调度给每个房间的都是同样 3 个主机（实测 4 个房间，只是顺序不同），所以 socket 仍按第一次调度的地址表轮换；新的调度回答里没有当前要连的主机时，改连新表的第一个。
- **开始时的调度**：最多 3 次，间隔 1.5 s、4.5 s（网页的退避 `1500 × (2^n − 1)` ms），每次 10 s 超时（同握手；网页是 3 s）；都失败以 `DanmakuClosed(connectionFailed, 'dispatch: …')` 结束，调度拒绝则第一次就结束。
- **登录被拒**：连接换 socket 重连；连续第 4 次被拒以 `DanmakuClosed(connectionFailed, 'Chat refused: 901 errorno …')` 结束，加入成功一次就重新计数（次数同 PandaTV）。被拒的 socket 收到了 901，框架的 8 次上限管不到这种循环，所以要自己计数。
- **只说二进制**：调度回答的 `protocoltype` 是 1（二进制 protobuf），网页据此用二进制编码；实测服务端按客户端用的格式回答（同一个主机，发 JSON 文本登录就回 JSON 文本），本实现总是发二进制、只解二进制，不读 `protocoltype`，文本帧不解。
- **不需要保留请求头大小写**：`dart:io` 的握手就能连（实测），不用 `connectExactWebSocket`。请求头带网站的 `Origin` 和平台层的 Chrome 140 UA，同浏览器。
- **上报本房间的公聊和人数**（见“消息”）。礼物、进场、PK、对方房间的聊天、系统公告都不报（和 T06a.2～T06a.22 的范围一致）。礼物虽然不报，信封要求确认（`ack` 1）的礼物照网页回 211 确认：不确认的话服务端每个礼物再发两次（实测）。

## 协议

### 调度

| 项目 | 内容 | 依据 |
|---|---|---|
| 地址 | `GET https://fx1.service.kugou.com/socket_scheduler/pc/binary/v2/address.jsonp`（`ServiceHost.backup1ServiceUrl`，与平台层的 `KugouLiveApi.apiHost` 相同） | `index_5e7bbee.js` 的 `dispatchSocket.getDispatchSocketAddress` |
| 参数 | 按页面对象的顺序：`_p=0`、`_v=7.0.0`（`liveInitData.version`，房间页把它设成 `window.staticVersion`）、`pv=20240801`（`RoomSocket.socketPv`）、`rid=<房间号>`、`clienttime=<毫秒>`、`cid=100`、`at=102`（普通房间；`liveInitData.kugouLive` 房间是 122），最后 `sign` | 同上；房间页内联脚本 `liveInitData = extend(liveInitData, {version: window.staticVersion})` |
| 签名 | 把除 `sign` 外的参数按键名排序，拼成 `k=v` 用 `&` 连起来，接上 `$_fan_xing_$`，取 MD5 十六进制的第 8～23 位。服务端不算 `_`（网页的防缓存参数）和 `sign` | 同上；实测：签名对的回答 `code 0`，`_v` 值不一致时回 `1100014 sign verify fail`；两份样本记下的地址逐字节重算得出 |
| 请求头 | 平台层的请求头（UA、`Accept`、`Origin`），`Referer` 是房间页；不跟随跳转，以 `kugoulive` 的名义发出 | 浏览器从房间页发出 |
| 回答 | `{"code":0,"data":{"addrs":[{"host":"chatwss146107.kugou.com/acksocket","timeout":10000},…],"age":300000,"backsoctoken":…,"protocol":"wss://","protocoltype":1,"pv":20240801,"socketype":1,"soctoken":…},"msg":"success","time":…}` | 样本 S07、S08 |
| 用法 | socket 地址是 `protocol + host`（没有 `protocol` 时 `ws://`）；登录用 `soctoken`（`backsoctoken` 是网页备用主机 `chat1wss.kugou.com` 的令牌，本实现不用）；`age` 毫秒；`addrs[].timeout` 是网页等一个主机的时长 | `initDispatchSocketOption`、`initSocket`、`RoomSocket.login` |
| 失败 | `code` 1100007：网页弹滑块验证（`_showSliderCheck`）；1100005：网页不再退回备用主机；其他：网页退回备用主机 | `getDispatchSocketAddress` 的回调 |

### 帧

| 项目 | 内容 | 依据 |
|---|---|---|
| 客户端帧头 | 18 字节：`100`、版本 `3`（2 字节）、类型 `1`、`12`（2 字节，其后可变部分的长度）、命令（4 字节）、内容长度（4 字节）、4 个 0；然后是内容。多字节都是大端 | 模块 1374 `toDataView`，模块 39296 的 `PROTOCOL_BYTES [1,2,1,2,4,4,1,2,1]` |
| 服务端帧头 | 26 字节：`100`、版本 `3`、类型、可变部分长度 `20`、命令、内容长度、`8`、8 字节毫秒时间；内容从第 `6 + 可变部分长度` 字节开始 | 模块 1374 `getPayloadBuffer`（只读类型、可变部分长度和命令）；样本 |
| 心跳 | 客户端 `64 00 01 00`（`encodeSocketBeat`：100、版本 1、类型 0），每 10 s；服务端回 `64 00 03 00`。类型 0 就是心跳 | `isSocketBeat`、`Fx.socket` 的 `BEAT_FREQUENCY 1e4`；样本 S07 29 次往返 |
| 内容 | protobuf `SocketProtocol.Message{offset 1, ack 2, rpt 3, msgId 4, compression 5, codec 6, content 7}`：`compression` 1 gzip、2 snappy；`codec` 1 时 `content` 是 protobuf，0 时是 JSON | 模块 55585 的 schema，模块 1374 `decodePb`、`unCompress`；样本里 gzip 的 JSON 帧（100、300622 等） |
| 客户端内容 | `Message{content}`：页面写的 `{MCodec:0, MCompression:1, content}` 只有 `content` 是字段 | `encodePb` |

### 命令

| 命令 | 方向 | 内容 | 本实现 |
|---|---|---|---|
| 201 登录 / 2201 重新登录 | 发 | `Login.LoginRequest`：`cmd`、`roomid`、`kugouid` 0、`token` 空、`appid` 1010、`platid` 7（网页；嵌入页 8）、`deviceNo`（页面存的设备号）、`v` 20240801、`referer` 0、`clientid` 100、`soctoken`、`sid`（页面的会话号）、`socsid`（上次登录的会话，第一次为空）、`screen` 0、`dfid` `-`，按字段号顺序写（protobufjs 的做法）。重连时网页发 2201（`LOGIN_AGAIN`） | 同网页；`sid`、`deviceNo` 每次 `connect` 随机生成（网页格式的 uuid），不持久保存 |
| 901 状态 | 收 | `ErrorResponse{cmd, type, seq, status, errorno, msg, socsid}`，`codec` 1。登录后先来 `type 4, status 1`，再来 `type 1`：`status 1` 带 `socsid` 是成功；令牌不对时 `status` 空、`errorno 622` | `type 1, status 1` 就绪并记下 `socsid`；`type 1` 其他状态是拒绝；其他类型不处理 |
| 501 聊天 | 收 | `Content.ContentMessage{cmd 1, content 2, roomid 3, receiverid 4, senderid 6, senderkugouid 7, appId 8, time 11 秒, ext 14, sinfo 15, codec 16}`，`codec` 1 时 `content` 是 `Chat.ChatResponse{chatmsg 1, senderid 2, senderkugouid 3, sendername 4, senderrichlevel 5, receiverid 6, receivername 8, seq 13, senderLogo 24, senderrichlevelV2 25, …}`，`ext` 是 `Ext.Extension`（粉丝团 `intimacyVo` 39 等），`sinfo` 里 `ck` 1 是神秘嘉宾、`ckid` 是其化名编号 | 见“消息” |
| 301005 人数（`HEAT_NUM`） | 收 | JSON：`{"cmd":301005,"content":{"data":{"robot","count","visited","vertical","hot","login","landscape"},"actionId":"roomAuNumber"},"roomid":…,"time":<毫秒>}`，约每 62 s 一次 | 见“人数” |
| 400305 对方房间的聊天（`OTHERMESSAGE`） | 收 | 同 501，`source{roomid, tags}` 是说话的房间（样本 S09：`roomid` 是本房间，`source.roomid` 5138284） | 不报（差异 5） |
| 601 礼物 | 收 | 信封带 `ack` 1、`offset`、`msgId`；网页回 211 确认：`Ack.AckRequest{cmd 211, roomId, kugouId 0（没登录）, offset, msgId, rpt}`，每个字段都写 | 不报；`ack` 1 时照网页回确认 |
| 其他 | 收 | 201 进场、602 全站礼物、400002/400004 头条、400303 全站公告、100 系统消息、616/315 歌曲、300361、304303、PK（613）等 | 不报 |

### 消息

聊天照网页 `socket_51738e4.js` 的 `RoomSocket.callback`（`case cmd.MESSAGE`）和 `PublicChat` 处理：

- 只报公聊：`ContentMessage.receiverid` 不为 0 是私聊，`senderid` 小于 0、`privateType` 为 1 的不显示（同网页）；`roomid` 不为 0 又不是本房间的丢掉（网页不查，本实现防串房）；
- 文字 `chatmsg`、用户名 `sendername`，去掉 U+2027～U+202E（行分隔、段分隔、文字方向控制符，网页 `replaceUnicode` 去掉的那些），再去首尾空白；没有文字不报。对某人公开说的话（`ChatResponse.receiverid` 不为 0，网页显示“A 对 B 说”）只报文字；
- 用户 id：`ContentMessage.senderid`（没有时用 `ChatResponse.senderid`）；神秘嘉宾（`sinfo.ck` 1）用化名编号 `sinfo.ckid`，同网页操作菜单用的 id，不暴露真实 id；
- 等级：财富等级 `senderrichlevelV2`，没有时 `senderrichlevel`（网页同）；
- 粉丝牌：`ext.intimacyVo` 的 `nameplate` 和 `level`，只在网页会显示时（`level` 大于 0、`type` 1～4、`lightUp` 1，`roomBase` 的 `dealWithNickName`）；
- 消息 id：信封的 `msgId`，没有时 `<发送者>:<seq>`（`seq` 是发送端自己的计数或时间，两个人可能相同，所以带上发送者）；
- 时间：`ContentMessage.time`（服务端的秒；大于 10^11 当毫秒）；
- 颜色白色。网页对粉丝团等级高于 7、守护的用户把文字染成橙色，那是网页聊天列表的样式，不是弹幕颜色，不照搬。

JSON 编码（信封 `codec` 0）的聊天按同样的规则读，`ext` 是 URL 编码的 JSON。

### 人数

`301005`、`actionId` 为 `roomAuNumber` 的帧（网页 `ViewerHeat` 模块）：

- `count` 报在线人数（`onlineViewers`）：它就是列表的 `viewerNum`（实测 100 对列表录制前的 98、87 对录制后的 85；网页观众列表在 `count` 大于 80 时把它当观众总数）；
- `visited` 报本场累计（`totalViewers`）：网页显示成“看过：本场累计 N 人”（`viewerList` 模块）；
- `hot` 不报：网页叫它“热度”（“热度即直播间观众的活跃度情况，不同于直播间人数”），但它和列表的 `hot`（平台层当作热度的那个数）不是一回事（同一时刻 1389 对 3126），报了会把两种热度混在一起；
- `roomid` 不是本房间的丢掉。

所以 `audience.dart` 里酷狗一项的 `hasTotalViewers` 改为 true（只改这一项），在线人数的来源仍是列表（`roomList`），弹幕来的是同一个数的实时更新。

## 连接和时序

| 项目 | 本实现 | 网页（房间页脚本） | 依据 |
|---|---|---|---|
| 地址 | 调度给的 3 个主机（`wss://chatwss…kugou.com/acksocket`），按回答的顺序 | 同；3 个都连不上时退回 `wss://chat1wss.kugou.com/acksocket`（文本协议，`backsoctoken`），再不行重新调度 | `initSocket`、`switchSocket`、`liveInitData.sokt` |
| 握手请求头 | `Origin`、Chrome 140 UA | 浏览器 | 实测 `dart:io` 握手可连 |
| 开始 | 调度最多 3 次（1.5 s、4.5 s），每次 10 s 超时 | 调度失败按 `1500 × (2^n − 1)` ms（最多 10 s）一直重试，超时 3 s | 差异 2 |
| 登录 | 打开后发 201；房间加入过后发 2201 带上次的 `socsid` | 同（`connected` 里 `isReconnect` 时用 `LOGIN_AGAIN`） | 实测 2201 带旧 `socsid` 回来同一个 `socsid` |
| 就绪 | 901 `type 1, status 1`；每次重新加入都报一次 `DanmakuReady` | 901 `status 1` 就算进房（`type 4` 那一帧也算，差异 3） | 样本 S07、S08 |
| 加入超时 | 10 s，超时换主机重连（下次握手先重新调度） | 10 s（`addrs[].timeout`）没有正常的第一帧就换主机 | `startConnectTime`、`reConnectionSocket` |
| 心跳 | 每 10 s 发 `64 00 01 00`，打开后 10 s 第一次；手动 `heartbeat()` 立即发一次 | 收到第一帧后开始，每 10 s | `socketBeat` |
| 无消息超时 | max(3 × 10 s, 90 s) = 90 s；服务端回答每个心跳 | 不检测（`BEAT_MAX_COUNT` 没有用到） | 框架默认 |
| 令牌 | 留给之后的 socket；超过 `age`、被拒（622）、或发出后没等到回答就断了，下次握手前重新调度 | 调度回答在 `localStorage` 缓存 `age`；页面内重连一直用同一个令牌，622 时重新调度 | 实测：令牌 6 分钟后仍可用，20 分钟后 622 |
| 登录被拒 | 换 socket；622 先换令牌；连续第 4 次 `connectionFailed`，加入成功就重新计数 | 622 重新调度一次（`retryDispatch622` 1）；其他拒绝等 10 s 换主机 | 差异 4 |
| 调度拒绝 | `connectionFailed` | 1100007 弹验证；其他退回备用主机 | — |
| 断线重连 | 框架默认：间隔 1、2、2、3、3… s，最多 8 次，收到任何帧清零，一轮只提示一次 | 每个主机试一次，再退回备用主机、重新调度 | 框架的统一做法 |
| 参数不对 | 房间号不是 3～11 位数字：`connectionFailed`，不请求、不握手 | — | — |
| 礼物确认 | 信封 `ack` 1 的礼物（601）回 211 | 同 | 实测不确认时同一礼物再来两次 |
| 停止 | 取消进行中的调度请求，关 socket | 退出时发 202（`QUIT`） | 差异 6 |

## 登记方式

应用（T07a.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.kugouLive: () => KugouLiveDanmakuConnection(http: kugouLiveHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `KugouLiveSite` 的同一个 `LiveHttp`。调度请求以 `kugoulive` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `kugoulive` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie：全程匿名，v3 也没有酷狗的登录和 Cookie 设置。
- `connector`、`policy`、`retryDelays`、`now`、`random` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（和录制详情）；未开播、没有场次、刷新得到的房间没有参数，按 T06a.1 不连接。

## 规格来源和期望值

归档 v4 和上游都没有实现，协议全部来自 2026-09-30 从 `https://fanxing.kugou.com/<房间号>` 下载的页面脚本（匿名、只读）和实测的帧：

| 脚本 | 读了什么 |
|---|---|
| 房间页 HTML | `liveInitData`（房间号、`version`）、`FxAjax` 的参数序列化、`FxAjaxSafeGate`（只在酷狗客户端里可用：`window.external.clientInfo.supportLurkingDog`）、`ServiceHost`（`backup1ServiceUrl` 等） |
| `/pub2/vroom/main/index_5e7bbee.js` | `Fx.socket`（`FxWebSocket` 的连接、超时、换主机、心跳）、`dispatchSocket`（调度、签名、缓存、622、备用主机）、`initSocket`、`connectSocket`、`RoomSocket`（`login`、`callback` 的拆信封、命令表 `cmd`）、`String.prototype.replaceUnicode`；webpack 模块 1374（编解码）、39296/40564（帧头布局）、80965（命令和 schema 的对照）、55585/73190/59301/38678/47985/40788/83339/46384（protobuf schema）、99512（snappy）、60991（pako gzip） |
| `/pub2/room/js/socket_51738e4.js` | 房间页实际用的 `RoomSocket.callback`：礼物确认（211）、`MESSAGE`/`OTHERMESSAGE` 的显示规则、公聊和私聊的分支 |
| `/pub2/room/js/roomBase_a2fb4ce.js`、`roomFunction_15fbd30.js` | `dealWithNickName` 的粉丝牌、`dealWithChatContentColor`、`sendChatMessage.chatSet.judgeShowChatMes`（公聊限制） |
| `/pub2/room/modules/PublicChat/index_d44b8e9.js`、`mysticViewer/index_3e596d3.js` | 公聊的模板（“对 … 说”）、神秘嘉宾的名字和 id |
| `/pub2/room/modules/ViewerHeat/index_fe0bfcb.js`、`viewerList/index_36b2784.js` | `HEAT_NUM` 的 `hot`、`visited`，观众总数的 `count` |

期望值：`fixtures/kugoulive/danmaku/web_expected.py` 用 Python 标准库把上面这些脚本的读法独立重写一遍（调度签名、`decodePb` 和拆信封、`replaceUnicode`、`MESSAGE`/`OTHERMESSAGE` 的显示规则、粉丝牌、`ViewerHeat`、`setSSID`/`sendSocketEnterRoom`/622，以及 `encodePb` 写登录包和礼物确认），读每个样本的每一帧，写下网页会怎么处理（状态、显示的聊天和它的各字段、人数、心跳、要回的确认）。在仓库根目录运行 `python3 fixtures/kugoulive/danmaku/web_expected.py`，结果在各样本的 `expected.json`，`generator` 字段写明来源。Dart 测试把本实现的结果逐帧和它对照：

| 对照 | 结果 |
|---|---|
| 调度地址 | S07、S08 记下的地址（含 `sign`）由本实现逐字节重算得出；生成脚本重算的签名也等于记下的（服务端接受了它们） |
| 调度回答 | 3 个主机（顺序同回答）、令牌、`age` 与脚本一致 |
| 登录包 | 本实现用记下的 `sid`、`deviceNo`、令牌写出的登录包与录下的发出帧逐字节相同，也等于脚本按页面对象编码的结果 |
| S07 的 195 个收到的帧 | 逐帧一致：29 个心跳回答；两个状态帧（`type 4` 不就绪，`type 1` 就绪并给出 `socsid`）；37 条聊天的用户名、文字、用户 id、等级、粉丝牌（样本里都不点亮）、时间，消息 id 按本实现的规则由脚本的 `senderid` 和 `seq` 算出；5 个人数帧的 `count`、`visited`；其余 122 帧没有消息 |
| S08 | `type 4` 不就绪，`errorno 622` 是令牌被拒（脚本：`askSchedulerAgain`） |
| S09 | 脚本：网页会显示并标成对方房间的；本实现不报（差异 5） |
| 用连接重放 S07 | 发出的帧（登录、之后的心跳）与录制相同，就绪 1 次，37 条聊天和 10 个人数按顺序上报 |

## 与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 文字和用户名只去掉 U+2027～U+202E，保留普通空格 | 网页的 `replaceUnicode` 先把这些字符换成空格，再删掉字符串里所有的半角空格（`replace(/ /g,"")`），连正常的空格也删了（“hello world”显示成“helloworld”），像是写错了；样本里的文字没有空格，结果相同 |
| 2 | 开始时调度最多 3 次（1.5 s、4.5 s），然后 `connectionFailed`；调度拒绝直接结束；每次超时 10 s | 网页一直重试，失败时还会退回备用主机（要备用令牌，也来自调度）。一直重试会让界面停在“连接中”；3 次和间隔取自网页的退避。超时同握手，网页 3 s 在移动网络上偏紧 |
| 3 | 就绪要等 901 的 `type 1, status 1` | 网页把第一个 `status 1` 的 901 当作进房，而 `type 4, status 1` 在令牌被拒时也会先到（样本 S08），网页随后才因 622 重新调度 |
| 4 | 登录被拒一律换 socket 重连，连续 4 次结束；令牌只在 622 时换 | 网页 622 只重新调度一次，其他拒绝等 10 s 换主机，没有上限。被拒的 socket 收到了帧，框架的 8 次上限管不到 |
| 5 | 不报 PK 对方房间的聊天（400305） | 网页在 PK 时把对方房间的公聊（`source.tags & 1` 且 PK 模块同意时）混进本房间的聊天，加“对方”标记；`LiveMessage` 没有来源标记，混进弹幕会让人以为是本房间的 |
| 6 | 关闭时不发退出（202） | 直接关 socket，服务端照常清理；T06a 所有平台都这样 |
| 7 | 不按房间的公聊限制隐藏聊天 | 网页对匿名观众用 `judgeShowChatMes` 隐藏公聊限制下“不该能说话”的人的公聊（限制类型 1 要房间的管理员名单，限制类型 2 看财富等级）。它要另外的房间数据（`limitType`、`limitValue`、管理员名单），而服务端推来的就是已经发出去的公聊；本实现照推来的显示 |
| 8 | `sid`、`deviceNo` 每次连接随机生成，不持久保存 | 网页把设备号存在 `localStorage` 里长期使用；本应用不需要让平台认出同一台设备 |
| 9 | 只说二进制，不接文本协议和备用主机 | 调度要求二进制（`protocoltype 1`，接口路径就叫 `binary`）；服务端按客户端的格式回答，二进制在所有调度主机上都可用 |

## 实测

2026-09-30 12:03～13:38 UTC（北京时间 20:03～21:38）只读、匿名、直连，没有登录，没有发言。用只依赖 `dart:io` 和 `crypto` 的小程序按房间页的做法调度、连接、登录、发心跳，记下所有帧；分析时只看数量、字段号、类型和时间，个人信息只在脱敏脚本里经手、没有另存。房间取自推荐列表（平台层同一个接口）里在播、人数最多的几个。

- **调度**：签名按页面算（`_v` 取 `7.0.0`）回 `code 0`；把签名里的 `_v` 写成 `undefined` 而参数里是空值，回 `1100014 sign verify fail`；不带 `_v` 时签名和参数一致也可以。4 个房间的主机都是 `chatwss140045`、`chatwss140058`、`chatwss146107`（顺序不同），`age` 300000，`protocoltype 1`、`socketype 1`，`soctoken` 51 字、`backsoctoken` 43 字。
- **登录**：匿名登录包（`kugouid` 0、空 `token`）被接受：`901 type 4 status 1`，随即 `901 type 1 status 1` 带 `socsid`（31 位十六进制）。空令牌、乱写的令牌：服务端立即以关闭码 1000、原因 `Bye` 关闭，不回 901。备用令牌 `backsoctoken` 在二进制主机上：`type 4` 之后 `type 1` 带 `errorno 622`，socket 不关，之后只收到全站头条（样本 S08）。
- **令牌寿命**：同一个 `soctoken` 在 3 分钟、5 分 52 秒后再登录都成功，20 分钟后 622。
- **重新登录**：2201 带上一次的 `socsid`，服务端回来同一个 `socsid`。
- **文本协议**：在调度主机上发 JSON 文本登录，服务端回 JSON 文本（`{"rpt":0,"ack":0,"cmd":901,"content":{…}}`）；备用主机 `chat1wss.kugou.com/acksocket` 用 `backsoctoken` 的 JSON 登录也被接受，空令牌 `Bye`。
- **下行**：人最多的房间（约 98 人）5 分钟 37 条聊天（大多是房间的迎宾账号自动发的欢迎语，3 条来自两位观众），另有进场 37、全站头条 114、全站礼物 16、全站公告 42 等；聊天都是 protobuf（`codec 1`），较大的 JSON 帧 gzip 压缩，没有见到 snappy。人数帧约 62 s 一次（13.8 s、76.5 s、138.3 s、201.3 s、262.0 s），`count` 100、100、95、95、87，推荐列表在录制前后给这个房间的 `viewerNum` 是 98 和 85；`hot` 1389 左右，列表的 `hot` 是 3126 和 3830。
- **长连接**：同一房间（51049168）连着 26 分钟没有断，155 次心跳服务端都回；帧之间最长间隔 6.9 s；人数帧 24 个，约 62～67 s 一个。
- **礼物确认**：这 26 分钟里 29 个礼物帧（601）的信封都带 `ack 1`、`offset`、`msgId`，`rpt` 0。没有确认时，同一个礼物（同一 `msgId`、`offset`）一共来 3 次，间隔约 2～2.5 s（10 个礼物，最后一个录制结束时只来了 2 次），`rpt` 仍是 0。回确认的效果没能实测：之后三次照网页回确认的录制（51049168 的 7 分钟和 15 分钟、2739259 的 5 分钟）里都没有人送礼。确认帧照网页脚本写（`socket_51738e4.js` 里的对象，`encodePb` 编码，每个字段都写），测试里与生成脚本按页面对象编码的结果一致。
- **PK**：房间 1073619 PK 时收到对方房间（5138284）的聊天 400305（样本 S09）。
- **本实现**：没有接到真实服务器上跑（测试用本地服务器和假连接）；协议和上面逐项对照过，登录包与实测发出的逐字节相同。

## 样本

三个新样本，格式照 `fixtures/README.md`（`frames.jsonl` 第一行是调度回答，其余是 socket 帧，二进制帧放在 `b64`），`meta.json` 记下调度请求、握手、原始录制的 SHA-256 和长度、脱敏和删减。

- **删减**：S07 只留调度回答、登录、状态帧、心跳、聊天、人数和不含个人信息的系统帧（300361、616、315、304303、300622、1901 和一个 gzip 的 100），删掉了讲别人的帧（进场 37、全站礼物 16、全站头条 114、全站公告 42、别人升级的系统消息 2、关注 2、才艺卡 1、别的房间的消息 1），数目记在 `meta.json` 的 `dropped`。S08 删掉了 3 个全站头条；S09 只留那一帧。
- **脱敏**（按协议逐层解开 protobuf 逐个字段替换，再按原来的字段顺序和线型重新编码、改正帧头的长度，没替换的部分与录制逐字节相同）：
  - 调度回答的 `soctoken`、`backsoctoken`，登录包的 `soctoken`：同长度的随机十六进制；
  - 登录包的 `deviceNo`、`sid`：同格式的随机 uuid；状态帧的 `socsid`：同长度的随机十六进制；
  - 聊天的 `ContentMessage.senderid`、`senderkugouid` 和 `ChatResponse.senderid`、`senderkugouid`、`receiverid`、`receiverkugouid`：同位数的合成数字；`sendername`、`receivername` 和文字里『』中的名字：同长度的“观众N”；头像 `senderLogo` 的图片编号：同长度的随机值（酷狗的默认头像 `/v2/kugouicon/` 保留）；`mac`、`kidSign`（设备摘要）：同长度的随机十六进制；
  - 一个人在所有帧里用同一套合成值；主播（51049168：2454242816、“姜拾七er”；1073619：692619617、143254319）是公开信息，保留；
  - `ext`（粉丝团名、铭牌、座驾、勋章图片地址）和 `sinfo`（等级、会员）里没有 id、令牌，保留；逐个检查过 `ext` 没有 `token`（20）、`kugouId`（21），`sinfo` 没有神秘嘉宾的化名和头像；
  - 脱敏脚本最后检查：所有被替换的原值（字符串，和 4 字节以上的 id 的 varint 编码）在输出里都找不到；
  - 调度回答和帧里没有 IP 地址（主机名是服务端的），响应头只有 CDN 节点和请求编号。门禁的 `fixture privacy` 通过。
- 录制和脱敏用的小程序没有放进仓库（`meta.json` 的 `tool` 写明了做法）。

## 受阻

没有。协议、匿名接入和样本都拿到了。只在“与网页的差异”里列了有意不做的部分。

## 后续升级候选（由用户决定）

| # | 内容 | 现状 | 依据 |
|---|---|---|---|
| 1 | PK 时显示对方房间的聊天，标出“对方” | 不报（差异 5） | 网页的做法；要 `LiveMessage` 或界面有来源标记（M13） |
| 2 | 按房间的公聊限制隐藏聊天 | 不隐藏（差异 7） | 网页的 `judgeShowChatMes`；要房间的限制和管理员名单 |
| 3 | 聊天文字按网页染色（粉丝团 7 级以上、守护）。**已做（T06a.F）** | 白色 | 网页 `dealWithChatContentColor`，是否算弹幕颜色由 T01a.1/M13 决定 |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | T07a.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（T06a.1 的原因表）。调度失败的详情是 `dispatch: <原因>` 或 `dispatch: code <code> <msg>`，登录被拒是 `Chat refused: 901 errorno <n> <msg>` |
| 房间公告 `kugoulive_chat_notice` 的文字 | 已在平台层改好：`KugouLiveApi.chatNotice` 去掉“这里暂时看不到酷狗直播间的聊天。”，只说明人数（“人数是正在观看的人数，没有时显示热度；粉丝数单独显示。”）；翻译在 M13 |
| 进房详情的人数和弹幕报的人数不同时显示哪个；本场累计的显示 | M13（其他平台也是后到的覆盖先到的） |
| 显示礼物、进场（若以后要做） | M13 统一决定；礼物已按网页确认，要显示时在协议层解 `GiftEffectSocketMsg.Content` |
| 表情 `[/抱抱]` 这类文字表情换成图片 | T01a.1（v3 没有酷狗的表情表；网页的 `emotion` 模块有对照） |
| 录制时是否带弹幕 | T08a.1（录制详情也带参数） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | T06a 各平台完成后删除 |

## 平台层的改动

- `kugoulive_api.dart`：新增 `KugouLiveDanmakuArgs(roomId)`；`chatNotice` 去掉“这里暂时看不到酷狗直播间的聊天。”（3.x 原文没有对照测试或迁移要用，不另留 `legacyChatNotice`：对照测试比的是冻结输出里的 3.x 公告，T02.U 已说明 3.x 存下的公告刷新时覆盖、不用迁移）。
- `kugoulive_site.dart`：进房和录制详情在直播中时带 `danmakuData: KugouLiveDanmakuArgs(roomId)`，不论取流回答是否能播（要登录、没有流的房间聊天照常）；未开播、没有场次、关注刷新不带。没有多发请求。
- `audience.dart`：酷狗一项 `hasTotalViewers` 改为 true，注释写明弹幕的 `count`、`visited`（只改这一项）。
- 对照测试：公告本来就在有意差异里（29-6），注释补上 T06a.26；新增一个用例查参数。

## 新增的通用能力、依赖

没有。框架没有改；没有新依赖（MD5 用本包已有的 `crypto`，gzip 用 `dart:io`，protobuf 用本包的 `src/codec/protobuf.dart`，snappy 按网页的 snappyjs 自己解，四十行）。只在 `live_danmaku.dart` 里按字母顺序加了一行导出。

## 测试

`test/sites/kugoulive_test.dart` 30 个用例；`live_core` 的酷狗测试加 1 个（共 85 个）。`live_danmaku` 共 993 个，连续跑 3 次全部通过；本文件在时钟 +30 天、+1 年、+5 年下直接运行（`tools/timeshift` 的方式）也都通过，进程正常退出。用到时间的地方（调度的 `clienttime`、令牌的 `age`）都把“现在”固定成录制时间（`now:`）。

- 协议 15 个：
  - 常量、心跳、房间号、uuid 格式；
  - 调度地址：S07、S08 记下的地址逐字节重算，签名与生成脚本和服务端一致，排序规则的两个向量；
  - 调度请求与房间页相同（地址、请求头、不跟随跳转、超时、取消）；
  - 调度回答：两份样本；1100014 等拒绝；403、502、不是 JSON、各种缺字段和坏地址、令牌的各种坏形状；没有 `protocol` 用 `ws://`、重复主机、`age` 的兜底；
  - 登录包：两份样本逐字节相同，也等于生成脚本的编码；2201 的帧头和字段顺序；
  - S07 逐帧与网页的读法一致（心跳 29、状态 2、聊天 37、人数 5）；S07 的迎宾账号、观众、对主播公开说的话、信封与聊天 id 不同的用户；
  - S08 的 622、S09 的对方房间聊天；
  - 状态帧的各种类型、没有会话号、JSON 编码的状态；
  - 聊天的各条规则：私聊、负的发送者、别的房间、空文字、`codec 0`、400305、没有房间号；对某人说；方向控制符和空格；两种等级；粉丝牌点亮的各种条件；神秘嘉宾；消息 id 的三种；时间的秒、毫秒、0 和越界；
  - JSON 编码的聊天：URL 编码的 `ext`、坏的转义、坏的 UTF-8、`privateType`、私聊、化名；
  - 人数：两种人数、字符串数字、负数、没有房间号、别的房间、别的 `actionId`、坏形状；
  - 什么也不给的帧：文本、过短、可变部分长度过小、为负、越界、坏 protobuf、未知命令、坏 JSON、坏 UTF-8、坏 gzip、坏 snappy；心跳；未知压缩照原样读；gzip、snappy 的人数帧；超过 4 MiB 的 gzip；录下的 gzip 系统消息；
  - 礼物：不报；信封要确认时回 211（帧头、字段和顺序、重发次数、JSON 编码的礼物），`ack` 不是 1、不是礼物、读不出的帧不回；
  - snappy：字面量、三种复制（含重叠）、长字面量，十种坏块。
- 连接 15 个：
  - 默认时序和平台表登记；
  - 开始：调度请求、第一个主机、握手请求头、代理路由、登录包；`type 4` 不就绪，`type 1` 就绪；聊天、人数、心跳回答、礼物的确认；手动心跳；
  - 用连接重放 S07：登录包和心跳与录制相同，就绪 1 次，37 条聊天和 10 个人数；
  - 断线后发 2201 带上次的会话号，同一个令牌，再次就绪；
  - 令牌超过 `age` 先重新调度（签名用当时的时间），时钟倒退也重新调度；
  - 622 换令牌重连、加入后重新计数、其他拒绝保留令牌、连续第 4 次结束；
  - 登录没回答就断、加入超时：下次握手先重新调度；
  - 握手失败保留令牌、换下一个主机；重新调度失败算握手失败，之后成功；
  - 开始时调度的 3 次和失败、调度拒绝直接结束；网页的等待间隔；
  - 重连时调度拒绝结束连接；
  - 新的调度回答没有当前主机时改连它的第一个；
  - 参数不对直接结束、不请求不握手，参数类型不对抛 `ArgumentError`；
  - 关闭时取消进行中的调度请求、关闭后没有事件、再次 `connect` 换房间；
  - 真实的本地服务器：`dart:io` 握手（路径、`Origin`、UA），服务端收到登录和心跳，回录下的状态帧和聊天；结束时关掉服务端所有升级后的 WebSocket 和服务器，直接运行测试文件时进程能退出。

## 后续升级（T06a.F，附录 B-15）

- 日期：2026-09-30～10-01
- 条目：B-15（本记录候选 3）：聊天文字按网页染色，填进 `LiveMessage.color`。
- 依据：房间页脚本（2026-09-30 匿名重新下载，文件名和本记录用的相同）：
  - `/pub2/room/js/roomBase_a2fb4ce.js` 的 `Fx.dealWithChatContentColor(a, c)`：`fxRequire("fandomClubConfig").getCurSwitch()` 为真时，`a.intimacyVo.level > 7`、`a.littleGuard.l`、`a.userGuard.g` 任一成立，文字用 `#ff9900`；为假时 `littleGuard.l` 用 `#ff9900`、`userGuard.g` 用 `#9955ee`；然后 `a.starvip.mysticUser` 为真时一律 `#CC9900`；都不是就是默认的 `user-msg` 样式；
  - 调用处是 `/pub2/room/modules/PublicChat/index_d44b8e9.js`（公聊的 `h()` 把 `ext` 和文字交给它），`ext` 来自 `/pub2/room/js/socket_51738e4.js` 的 `RoomSocket.callback`：`L = JSON.parse(decodeURIComponent(k.ext))`，有 `k.sinfo` 时写 `L.starvip`，`MESSAGE` 里 `L.starvip.mysticUser = (sinfo.ck === 1)`；
  - `/pub2/vroom/main/index_5e7bbee.js`：开关 `getCurSwitch()` 在频道房间、`liveInitData.isLiveRoom` 的房间为假，否则看 `ApolloConfig.new_fandom_club_switch`（房间页里是 `"1,1"`）的第一项，所以本连接连的普通房间（`at` 102）都是“开”；`decodePb` 对 protobuf 聊天总会把 `ext` 解成 `Ext.Extension`（没有这个字段时是空消息）再 URL 编码成 JSON，所以 protobuf 聊天总有 `L`；schema：`Extension` 的 `userGuard` 8（`UserGuardVo{g string 1, i string 2}`）、`littleGuard` 9（`LittleGuardVo{l int32 1, g int32 2}`）、`intimacyVo` 39（`level` 1）。

### 做法

- `KugouLiveDanmakuProtocol.textColor(ext, mystery:)`，按“开”的那一支：
  - 神秘嘉宾（`sinfo.ck` 为 1）：`#CC9900`（`mysteryColor`），盖过其他；
  - 否则粉丝团等级大于 7、小守护（`littleGuard.l`）、守护（`userGuard.g`）任一：`#ff9900`（`highlightColor`）；
  - 否则白色（网页的默认样式，和以前一样）。
  - 按 JavaScript 的写法读：`l`、`g` 用 JS 的真假（`g` 是字符串，`"0"` 也算有；数字 0、空字符串、`false`、`null` 算没有），`level > 7` 按 JS 的比较（数字、数字文字、布尔值当 0/1，其他不成立）。
- protobuf 聊天：`_content` 另外读出 `ext` 的 `userGuard`、`littleGuard`，并且总有 `ext`（没有这个字段时是空的），和网页的 `decodePb` 一致；所以神秘嘉宾没有 `ext` 也是金色。
- JSON 聊天（信封 `codec` 0）：`ext` 是 URL 编码的 JSON；没有、解不开（坏的转义、坏的 UTF-8、不是 JSON、不是对象）时白色——网页这时没有 `L`，神秘嘉宾也不染色。
- 只作用于本房间的公聊（501）。PK 对方房间的聊天（400305）仍不报（差异 5；网页会染色，S09 那一条是橙色）。
- “关”的那一支（频道房间、`isLiveRoom` 的房间，或平台把开关改成 0）没有实现：这些房间的参数里没有房间类型，本连接连的也不是这类房间。
- 网页的聊天气泡（`BUBBLES_SHOW` 时按气泡配置换一套样式）不照搬：那是聊天列表的装饰，不是文字颜色。

### 用户看到的变化

弹幕和聊天列表里，粉丝团 8 级以上、小守护、守护发的聊天是橙色（`#ff9900`），神秘嘉宾的是金色（`#cc9900`），其他仍是白色。T06a.26 的记录原来说这是网页聊天列表的样式、不照搬（“消息”一节最后一条）；按 B-15 的决定改为照搬，写进 `LiveMessage.color`：画面弹幕和聊天列表都按这个字段着色，和斗鱼、哔哩哔哩的弹幕颜色一样（界面在 T01a.1、M13）。

### 样本和实测

2026-09-30 15:20～15:50 UTC（北京时间 23:20～23:50）匿名、只读、直连，推荐列表人数最多的 15 个房间各 30 分钟（按房间页调度、匿名登录、心跳，照网页回礼物确认，不发言），留下所有聊天帧：1,744 条聊天里 854 条橙色、49 条金色、841 条白色；本实现逐条读出的颜色与录制脚本按网页规则算的一致。

- **S10-chat-colours**（新，房间 1570369，6 条）：粉丝团 33 级且是小守护、8 级（最低的橙色）、守护（`g` 为 `"1"`，没有粉丝团）、守护且 30 级、房主（守护、小守护都是空的，没有粉丝团）、3 级。
- **S11-mystery-colour**（新，房间 1528949，2 条）：22 级的神秘嘉宾（金色，不是橙色）、7 级（刚好不染色）。
- 脱敏（同 T06a.26 的做法：逐层解开 protobuf，按原来的字段顺序和线型编回，改正帧头的长度，没替换的部分与录制逐字节相同）：发送者、接收者的 id（`ContentMessage` 6、7，`ChatResponse` 2、3、6、7）换成同位数的合成数字，一个人一套；昵称（`ChatResponse` 4）换成同长度的 `观众N`；`mac`、`kidSign`（19、23）换成同长度的随机十六进制；用户头像地址里的图片编号换成随机十六进制（默认头像保留）；`Ext.defaultPlate.kid`（10.1，铭牌所属的酷狗 id）、`Ext.fancyNumInfo` 的靓号（52.1）换成同位数的合成数字；神秘嘉宾的化名（`sinfo.ckname` 6）换掉数字、化名编号（`ckid` 8）换成同形的字母和数字。聊天文字逐条看过，不提到任何人，也都不是对某人说的。门禁的 `fixture privacy` 通过。
- `web_expected.py` 按上面的脚本补了 `content_color`（`contentColor`，`null` 是网页的默认样式），并读出 `ext` 的 8、9；五个样本的 `expected.json` 都重新生成：S07、S08、S09 只多了这个字段（S07 的 37 条都是 `null`，S09 那条 400305 是 `#ff9900`）和 `generator` 的说明。
- 录制和脱敏的脚本没有进仓库（`meta.json` 的 `tool` 写明了做法）。

### 与决定的差异

没有。没能实测的：JSON 编码的聊天（录到的聊天都是 protobuf）、“关”的那一支（见上）只按脚本实现或不实现；`g`、`l` 取别的值、JS 真假的边界只用合成帧测。

### 测试

`test/sites/kugoulive_test.dart` 36 个（原 30 个，新增 6 个）；`live_danmaku` 共 1337 个，连续跑 3 次全部通过；本文件在时钟 +30 天、+1 年、+5 年下直接运行都通过。

| 用例 | 内容 |
|---|---|
| 颜色常量 | `#ff9900`、`#cc9900` |
| 录制对照（S10、S11） | 8 条聊天逐条与网页的读法（`web_expected.py`）一致，颜色依次是橙、橙、橙、橙、白、白、金、白 |
| 录制里的依据 | 两个样本的粉丝团等级；S07 的 37 条在网页都是默认样式 |
| 合成的 protobuf | 7、8、0、负数级；没有粉丝团、空 `ext`；守护的空条目、`g` 为 `""`、`"0"`、`"6"`；小守护的 `l` 为 0、1、-1，只有 `g`；3 级加守护；神秘嘉宾盖过橙色、没有 `ext` 也是金色，`ck` 为 2 或没有时不算 |
| 合成的 JSON | 数字、数字文字、7.5、`"7"`、`"abc"`、`true` 的等级；`l` 为 `"0"`、0、`false`；`g` 为 0、`{}`、`null`；不是对象；坏的转义、不是 JSON、`null`、空字符串；神秘嘉宾只在有 `ext` 时金色 |
| PK 对方房间 | 网页会染色，本实现仍不报 |

改了原有测试的期望（测试里注明了 B-15）：对照网页的聊天字段时，颜色由原来一律白色改为网页的 `contentColor`（S07 的 37 条仍是白色）。

### 放到其他模块的部分

没有新增：颜色在 `LiveMessage.color` 里，画面弹幕和聊天列表照这个字段着色本来就是 T01a.1、M13 的内容（和其他平台的弹幕颜色一样）。
