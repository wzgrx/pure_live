# D01.21 弹幕（新增）：BIGO LIVE

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/bigo.dart`
  - `BigoDanmakuConnection`：连接；
  - `BigoDanmakuProtocol`：地址、握手请求头、各帧的写法、取游客账号的请求和回答的解析、参数检查、帧的解码，不做 I/O；
  - `BigoDanmakuFrame`（一帧解出的内容）、`BigoChatVisitor`（游客账号）。
- 参数：`live_core` 新加的 `BigoDanmakuArgs(siteId, ownerId, roomId)`（`bigo_api.dart`，只加不改）：
  - 进房（`getRoomDetail`）和录制详情（`getRoomDetailForRecording`）用的就是直播间回答（`getInternalStudioInfo`），网页会开聊天的直播间在 `LiveRoom.danmakuData` 里带上参数，不多发请求；关注刷新、开播状态、按号搜索不带；
  - `siteId` 是 `clientBigoId`，`ownerId` 是 `uid`（主播账号），`roomId` 是 `roomId`（主播的 64 位房间号，原样的数字串，E03.11 已读进 `BigoRoomData.broadcastId`）；
  - 什么时候给：照网页播放器的 `startLive`、`startWs`、`handleNeedLogin`（`14.37bf41.js`）：在播（`alive` 为 1）、不要求登录、不是密码房（聊天要密码）、`roomType` 不是 "1"（网页把它当作结束）、有房间号。付费秀照网页也开聊天。`BigoApi.danmakuArgs` 做这个判断，`BigoApi.room(studio, danmaku: true)` 放进房间。
- 升级条目：24-3“聊天（弹幕）”。v3、归档 v4、pure_live_TV 都没有 BIGO 的聊天（v3 和 TV 是 `EmptyDanmaku`，归档规格 §7 只写了“需要另行抓包”），这是新增功能，没有可对照的实现。
- 规格来源：官网 `https://www.bigo.tv/<号>` 在 2026-09-30 加载的脚本（下称“网页”），和同日只读、匿名的实测（见“实测”）：
  - `14.37bf41.js` 模块 931：聊天 socket 的类（`init`、`getWebSocketLink`、`setProdUrl`、`connect`/`onmessage`、`generateChallengeKey`、`doLogin`、`doPing`、`enterRoom`、`pullChatRoomUser`、`handleMessage`、`destroy`），事件号表 `R`、聊天类型表 `CHAT_EVENT`；同一文件的播放器组件（`getInfo`、`startLive`、`startWs`、`handleNeedLogin`、`subWs`）；模块 890 的 `toUri`（"a|b" → `a << 8 | b`）；
  - `97.929aaf.js`：直播间页的 `subWs`（`NUMS`、`11032`、`3608`、`NORMAL_TEXT` 的读法）和聊天列表组件（哪些类型显示、`comments` 是类型 1 和 2）；
  - `app.2a1a24.js`：接口 `getWebSocketLink`（`POST https://ta.bigo.tv/official_website/studio/getWebSocketLink`，表单 `deviceId=…`）、设备号的生成（`web_` + 指纹哈希 + 6 位随机 + 毫秒）、axios 的公共设置。
  - 这些脚本的文件名带版本号，网站更新后会变；上面的函数名是找到对应位置的依据。
- 样本：新录 3 个（`fixtures/bigo/danmaku/`，见“样本”）：`S05-live`（一场在播的直播，前 63 s）、`S06-idle`（进入已下播的房间）、`S07-unsigned`（未回应质询就登录被拒）。`expected.json` 由 `web_expected.py` 按网页的读法生成。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），和 D01.22 PandaTV 一样在握手前插一个请求（框架没有改：`connector` 参数本来就允许替换握手）。平台代码只写这几样：
  - `target`：检查参数，给出聊天地址和握手请求头，为这次连接生成一个设备号；
  - `onOpen`：什么都不发（服务端先说话），只重置这个 socket 的状态；
  - `onData`：解一帧；回答质询、一秒后登录、登录成功后进房、进房成功才就绪（`session.ready()`）并请求观众数；
  - `heartbeatFrame`：登录发出以后才给 ping。
  - 换地址、退避、最多 8 次、无消息检测、加入超时、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **游客账号只在需要时取**：一次 `connect` 的第一次握手前 POST `getWebSocketLink` 取一个游客账号（`userId`、`uidToken`），之后的握手（断线重连）接着用，和网页一样（网页每个播放器取一次，`reconnect` 用同一个 `wsConfig`）。登录或进房被拒、加入超时时丢掉账号，下一次握手再取。请求失败（网络、状态码、回答看不懂）当作这次握手失败，走框架的退避和 8 次上限。
- **加入的判定照网页**：登录回答 `res` 为 "200" 才进房，进房回答 `resCode` 为 "200" 才算加入。服务端对不存在和已下播的房间也回答 "200"，只是 `sid` 为 "0"（实测），这时以 `DanmakuClosed(connectionFailed, 'No broadcast in room <号>')` 结束，不空等。
- **被拒就换账号重连，连续第 4 次结束**：登录被拒（`res` 不是 "200"）、进房被拒（`resCode` 不是 "200"）、`unsigned` 错误、10 s 内没进房（错误的令牌服务端不回答，实测）都算一次，重连前丢掉账号；连续第 4 次以 `DanmakuClosed(connectionFailed, 'Chat refused: …')` 结束，加入成功一次就重新计数（和 D01.22 的次数一致）。收到质询就算收到消息，框架的 8 次上限管不到这种循环，所以要自己计数。
- **不需要保留请求头大小写**：实测带或不带 `Origin`、UA 用 `Mozilla/5.0` 都能握手，用默认的 `dart:io` 握手，不用 `connectExactWebSocket`。请求头照平台层（`BigoApi.headers`）带 `Origin: https://www.bigo.tv` 和 `User-Agent: Mozilla/5.0`。
- **上报聊天和在线人数**：评论（类型 1）和付费弹幕（类型 2，网页在聊天列表里和评论一样显示）当作白色聊天；`NUMS` 的 `totalUserCount` 和观众列表回答的 `total` 报在线人数（`LiveAudienceUpdate(onlineViewers)`）。礼物、点亮爱心、关注、分享、入场、贴图、热度、点赞数、房间状态都不报（和 D01.2～D01.22 的范围一致，见差异）。聊天里没有带金额的醒目留言。
- **在线人数的来源**：列表本来就有在线人数（`user_count`，`audience.dart` 里 BIGO 是 `roomList`），直播间回答没有；聊天里的两个数和列表是同一个口径（一间 socket 上 2472～2513，列表 2557；另一间 socket 上 467～481，列表 557；都是正在观看的人），网页直播间显示的也是它（`nums`）。能力不变，只在 `audience.dart` 本平台那一项的注释里补了这个来源。

## 协议

帧都是文本：一个十进制的事件号，接一个 JSON 对象。客户端直接相连（`791{…}`），服务端中间加一个制表符（`791\t{…}`）；读的时候照网页取第一个 `{` 之前的部分当事件号（`+e.data.slice(0, l).trim()`）。事件号是网页的 `toUri("a|b")` = `a << 8 | b`。

| 步骤 | 内容 | 出处 |
|---|---|---|
| 游客账号 | `POST https://ta.bigo.tv/official_website/studio/getWebSocketLink`，表单 `deviceId=<设备号>`，内容类型 `application/x-www-form-urlencoded; charset=UTF-8`。回答 `{"code":0,"data":{"pro_time":null,"uidToken":<160 字>,"userId":<10 位>,"userName":"0","seqId":…,"deviceId":<原样>,"wssLinkd":[],"realUser":null},"msg":"success"}` | `app.2a1a24.js` 的 `getWebSocketLink`；模块 931 的 `getWebSocketLink` 把 `data` 当作 `wsConfig`；S05 第 1、2 行 |
| 设备号 | `web_<32 位十六进制>_<6 位字母数字>_<毫秒>`；网页用浏览器指纹的哈希，本实现用随机数（同形） | `app.2a1a24.js` 的设备号函数（`/^web_[a-f0-9]{32}_[A-Za-z0-9]{6}_\d+$/`） |
| 地址 | `wss://wss.bigolive.tv/live/official/web`（`setProdUrl`：`www.bigo.tv` 用 `S.prod`；`bigoapp.tv`、`www.bigovideo.ru` 用另两个） | 模块 931 的 `S`、`C`、`B`、`setProdUrl` |
| 质询 | 打开后服务端先发 `256\t{"challenge":<24 字 Base64>}`（10～120 ms 内） | `onmessage` 的 `Challenge_KEY`；S05 第 3 行 |
| 回答 | `79108{"appId":"60","osType":"4","clientVersion":"5","timeStamp":<秒>,"nonce":"1","reservedForSecurity":"1","appSign":"1","redundancy":"1","sign":<MD5("60#4#5#<秒>#1#1#1#1#" + 质询的后 8 字)>}` | `generateChallengeKey`；S05 第 4 行 |
| 登录 | 回答后 1 s：`512279`（`2001|23`）`{"uid","cookie":uidToken 去掉 "###VER2","secret":"0","userName","deviceId", …,"clientType":"7", …,"netConf":{"clientIp":"0", …,"countryCode":"CN"}}` | `doLogin`、`setTimeout(…, 1e3)`；S05 第 5 行 |
| 登录回答 | `512535`（`2002|23`）`{"uid","res":"200","clientIp":<调用方地址，小端 uint32 的十进制>,"timestamp","version"}`；`res` 不是 "200" 是失败 | `handleMessage` 的 `LOGIN`；S05 第 6 行 |
| 进房 | `1304`（`5|24`）`{"secretKey":"0"（密码房是密码）,"seqId":<毫秒>,"roomId","reserver":"1","clientVersion":"0","clientType":"7","version":"15","deviceid","other":[]}` | `enterRoom`；S05 第 7 行 |
| 进房回答 | `1560`（`6|24`）`{"seqId","resCode":"200","roomId","sid","bownerInRoom", …,"admins":[…],"other":[…]}`。在播：`sid` 是这一场的编号（和列表、直播间回答的 `sid` 相同），`other` 里有开播时间 `lst` 等；没有这场直播：`sid` "0"、`bownerInRoom` "0"、`other` 只有 4 项 | `onmessage` 和 `handleMessage` 的 `ENTER_ROOM_RES`；S05 第 8 行、S06 第 8 行 |
| 观众数请求 | 进房成功后 `10776`（`42|24`）`{"uid":<主播>,"seqId":<毫秒>,"roomid", …,"others":[]}`；回答 `11032`（`43|24`）`{"uid","seqId","room_id","users":[…],"isEnd","opRes","total"}` | `pullChatRoomUser`；`97.929aaf.js` 的 `t.sub(11032, …)`；S05 第 9、10 行 |
| ping | 登录后每 10 s `791`（`3|23`）`{"status":"0","seqid":<毫秒>,"flag":"0","roomId":"0","ownerStatus":"0","micUid":"0"}`；服务端一般 0.2 s 内回 `791\t{"status":"0","seqid":<服务端序号>}`（慢时几秒） | `doPing`、`setInterval(…, 1e4)`；S05 第 14、15 行 |
| 登录前没回答质询 | 服务端回 `0\u0000        {"errUri":"512279","info":"unsigned"}`（事件号是 "0"、NUL 和空格），之后不再回答任何帧（ping 也不回） | `onmessage` 的 `"unsigned" === c.info || c.errUri`；S07 第 6 行 |
| 离开 | 网页关页面时发文本 `close`，下播时发 `7|24`；本实现直接关闭 socket | `destroy`、`subWs` 的 3608 |

下行消息（本房间的，`room_id`/`gid` 要等于 `roomId`）：

| 事件号 | 内容 | 本实现 | 网页 |
|---|---|---|---|
| 2584（`10|24`，`NORMAL_TEXT`） | 房间广播：`{"from_uid","seqId","room_id","oriUri","payload":{…}}`。聊天列表的消息（`oriUri` 2060425）的 `payload` 是 `seqId`、`uid`（发送者）、`grade`（等级）、`contribution`、`timestamp`（录到的都是 "0"）、`tag`（类型）、`content`（UTF-8 JSON 的 Base64）、`others`（标志）、`owner` | 类型 1、2 报聊天（见下），其他不报 | 解出 `content` 放进聊天列表；只显示 `CHAT_EVENT` 里的类型 |
| 同上，`tag` 1（`NORMAL_TEXT`） | 评论：`content` 是 `{"n":名字,"m":文字,"a","b","sticker"}` | 聊天 | 列表和画面弹幕 |
| 同上，`tag` 2（`DAMMARKU_TEXT`） | 付费弹幕，网页用同样的 `n`、`m` 画成醒目的横幅（`appendPayDanMu(n, m)`）；录制和实测里没有出现 | 聊天（和网页的聊天列表一样按评论显示） | 列表和横幅 |
| 同上，`tag` 3、6、8、10、11 | 点亮爱心、礼物、关注、分享、公告 | 不报 | 列表里的提示行 |
| 同上，`tag` 34、37、134、12、20、21、76、79 等 | 贴图（`m` 是图片地址）、入场（`{"level","n"}`）、服务端通知（`{"n":"server","m":…}`）、排名等 | 不报 | 不显示（不在 `CHAT_EVENT` 里） |
| 2584，`oriUri` 2396297、2062217、760969、517868 | 热度 `hot_value`、点赞数 `total`、礼物动画、主播的豆子总数 | 不报 | 热度和礼物动画另有显示 |
| 10264（`40|24`，`NUMS`） | 观众进出：`{"gid","addUser":[…],"delUser":[…],"totalUserCount", …}`，几秒一条 | 在线人数 | `nums = totalUserCount` |
| 11032 | 观众数请求的回答：`total` | 在线人数 | `nums = total` |
| 3608 | 房间状态 `roomStatus`：1、2、5 结束，3 主播暂离，4 回来（网页的代码；实测没有遇到） | 不报 | 结束时停播放并发 `7|24`，暂离时显示提示 |
| 10520 | 连麦座位的变化 | 不报 | 另有处理 |

聊天的解法：

- `payload.tag` 是 1 或 2（文字或数字）；`payload.content` 按 Base64 解码（缺少补齐的 `=` 也接受）、按 UTF-8 严格解码、再解 JSON 对象；任何一步失败就丢掉这条（网页的 `JSON.parse(decodeURIComponent(escape(atob(…))))` 失败时同样不显示）；
- 文字是 `m` 去首尾空白（数字照写成数字），为空不报；用户名是 `n` 去首尾空白；
- 用户 id 是 `payload.uid`，不是数字串时用 `from_uid`；等级是 `payload.grade`；
- 消息 id 是 `<用户 id>:<seqId>`（帧的 `seqId`）：服务端录到过把同一条消息原样再发一次（同一个 `seqId`），这个 id 让 D01.1 的去重闸门挡掉重发，又不会把两条相同文字的评论合成一条；
- 没有时间：录到的评论 `timestamp` 都是 "0"。

在线人数的解法：`NUMS` 看 `gid`、`11032` 看 `room_id`，要等于本房间；人数是 1～20 位的数字串或整数，其他丢掉。下播房间的 `11032` 是 `room_id` "0"、`total` "0"，不报。

## 连接和时序

没有归档 v4 和上游可对照，右边一列是网页的做法。

| 项目 | 本实现 | 网页 | 依据 |
|---|---|---|---|
| 地址 | `wss://wss.bigolive.tv/live/official/web`，一个 | 同（`www.bigo.tv` 上） | `setProdUrl` |
| 握手请求头 | `Origin: https://www.bigo.tv`、`User-Agent: Mozilla/5.0`（`BigoApi.headers`），`dart:io` 握手 | 浏览器 | 实测带或不带 `Origin`、UA 为 `Mozilla/5.0` 都能握手 |
| 游客账号 | 一次 `connect` 的第一次握手前 POST 一次；重连接着用；被拒、加入超时后丢掉，下次握手再取 | 每个播放器 `init` 时取一次，`reconnect` 用同一个 | 实测同一个账号能连第二个 socket、能同时连两个、62 分钟后还能登录 |
| 请求头（账号） | `BigoApi.headers` 加内容类型，不跟随跳转，以 `bigo` 的名义发出（走本平台的代理），超时同握手（10 s），一次 `connect` 的请求绑定一个 `CancelToken` | 浏览器，`withCredentials` | 实测不带 `Origin`、`Referer`、甚至不带 `deviceId` 也给账号（不带时服务端自己生成设备号） |
| 登录 | 回答质询后 1 s | 同（`setTimeout(…, 1e3)`） | 实测回答后立即登录也能成功，仍照网页等 1 s |
| 进房 | 登录回答 "200" 后（且登录确实已发出）；不带密码 | 同；密码房带密码 | 密码房、要求登录的房间不给参数，所以不连 |
| 就绪 | 进房回答 `resCode` "200" 且 `sid` 不是 "0"；每次重连加入都再报一次 `DanmakuReady` | 进房回答 "200" 即成功 | 实测不存在和下播的房间也回 "200"、`sid` "0" |
| 没有这场直播 | `connectionFailed`，不再重连 | 不会发生（只在在播时连） | 差异 3 |
| 加入超时 | 10 s；算一次被拒，换账号重连 | 没有 | 实测加入在打开后 1.4～2.5 s 完成（含 1 s 等待）；错误的令牌服务端不回答 |
| 被拒 | 登录、进房被拒和 `unsigned`：换账号重连；连续第 4 次 `connectionFailed`，加入成功就重新计数 | 登录失败重试到 3 次后登出（真实账号）；进房失败只记日志 | 差异 4 |
| 心跳 | 登录发出后才发；每 10 s 一次（框架的计时器从打开时算起，手动 `heartbeat()` 立即发一次） | 登录时开始每 10 s 一次 | `doPing`；服务端回答每个 ping |
| 无消息超时 | max(3 × 10 s, 90 s) = 90 s | 没有 | 框架默认；在播的房间几秒就有一条 `NUMS` |
| 断线重连 | 框架默认：只有一个地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，收到任何帧清零，一轮只提示一次 | `onerror` 时重连，最多 3 次，不等待 | 框架的统一做法 |
| 参数不对 | 号、主播账号或房间号不合规：`connectionFailed`，不请求、不握手 | — | — |
| 下播 | 不处理 3608；下一次重连时进房回答 `sid` "0" 就结束 | 停播放、发 `7|24` | 放到 M13 |

## 实测

2026-09-30 11:50～14:35 UTC（北京时间 19:50～22:35）只读、匿名，经本机代理（出口在境外），没有登录，没有发言、送礼、关注。用只依赖 `dart:io` 和 `crypto` 的小程序，按网页的顺序做（取游客账号、质询、回答、登录、进房、请求观众数、每 10 s ping）；另做了下面的几种变化。在播房间取自公开列表（`vedioList/72` 和网页推荐的 `vedioList/5`）。输出里只看事件号、字段名、长度和计数，账号、令牌和地址不打印。

- **游客账号**：匿名 POST 就给，`code` 0；带或不带 `Origin`、`Referer`、UA 为 `Mozilla/5.0` 都一样；不带 `deviceId` 时服务端自己生成一个；`GET` 回答 `500006`“Request method 'GET' not supported”。回答里没有调用方地址。
- **握手**：带或不带 `Origin`、UA `Mozilla/5.0` 或 Chrome 都能打开。
- **质询和登录**：质询在打开后 10～120 ms 到；照网页等 1 s 再登录，0.2～0.7 s 内回答 "200"；回答后立刻登录也行；故意写错签名也能登录（服务端看来不校验签名，但要先有回答：登录抢在回答之前时回 `unsigned`，样本 S07）。
- **登录回答里有调用方地址**：`clientIp` 是一个十进制数，按小端解成 IPv4 正是本机代理的出口地址（和 `api.ipify.org` 经同一代理看到的一致；不是家里的地址）。样本里换成了 198.51.100.200 的同一写法（见“样本”）。
- **错误的令牌**：同形的随机令牌登录，服务端不回答（没有 `512535`），socket 也不关。
- **进房**：在播的房间回答 "200"、`sid` 非零；编造的房间号和已下播的房间（`qashia305`）也回 "200"，`sid` "0"、`bownerInRoom` "0"（样本 S06），之后的 `11032` 是 `room_id` "0"、`total` "0"，但 ping 照常有回答。
- **账号复用**：同一个游客账号连第二个 socket、同时连两个 socket（都不被踢）、取到 34 分钟和 62 分钟后再登录，都成功。
- **下行**：两个美国推荐房间（列表 85、96 人）各 5 分钟没有一条评论，只有入场、热度、点赞；一间菲律宾房间（2500 人左右）3 分钟 11 条评论、4 分钟 4 条；样本 S05 的印尼房间（列表 557 人）4 分钟 28 条评论。评论的 `oriUri` 都是 2060425、`timestamp` 都是 "0"。服务端把一条点亮爱心原样重发过一次（同一个 `seqId`）。没有遇到付费弹幕（类型 2）和房间状态（3608）。
- **人数**：`NUMS` 在热门房间几秒一条，`totalUserCount` 在 2472～2513 之间，列表同时是 2557（之后一次是 597，列表的人数刷新较慢）；样本 S05 的 `11032` 是 481、`NUMS` 467～468，列表 557。
- **长时间连接**：三次长连接（每 10 s ping，服务端都回，没有下播、踢出或要求刷新账号的消息）：一个在 1592 s 断开；同时打开的两个在同一秒（1432 s）断开；都是关闭码 1006、没有关闭帧。另有同时打开的两个连到 1532 s 时被本机终止，没有断开。断开的时长不同、两个 socket 同时断，更像是经过的代理线路断开，不像服务端的固定时限；本实现按普通断线处理（同一个账号重连，提示一次重连）。直连（不经代理）时是否也会断，没有条件核实，留待 M13 真机观察：若确有固定时限，可以照 D01.22 在到期前悄悄换 socket。
- **本实现**：没有接到真实服务器上跑（测试用本地服务器和假连接）；帧的写法与实测时服务端接受的逐字节相同（样本的客户端帧就是实测程序发出的）。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.bigo: () => BigoDanmakuConnection(http: bigoHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `BigoSite` 的同一个 `LiveHttp`。取游客账号的请求以 `bigo` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `bigo` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie：全程匿名，v3 也没有 BIGO 的登录和 Cookie 设置。
- `connector`、`policy`、`loginDelay`、`now`、`random` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail` 和 `getRoomDetailForRecording`；未开播、要求登录、密码房、刷新和搜索得到的房间没有参数，按 D01.1 不连接。

## 期望值和对照

- 没有归档 v4 或上游的解码可用，期望值来自网页：`fixtures/bigo/danmaku/web_expected.py` 按上面列出的函数，一步步重写网页对每一帧的读法（`onmessage` 取事件号和 JSON、`handleMessage`、直播间页的 `subWs`、聊天列表的 `comments`）和网页会发出的帧（`generateChallengeKey`、`doLogin`、`enterRoom`、`pullChatRoomUser`、`doPing`），没有照抄网页的代码。它从样本读出游客账号、质询、时间和序号，写下网页发出的每一帧，以及每个收到的帧网页做了什么（回答、登录结果、进房结果、`nums`、放进聊天列表的条目），再把网页的评论和人数写成本应用的消息投影（规则见“聊天的解法”）。运行：在仓库根目录 `python3 fixtures/bigo/danmaku/web_expected.py`，结果在各样本的 `expected.json`，`generator` 字段写明来源。
- 测试用同一份样本跑新代码：

| 对照 | 结果 |
|---|---|
| 客户端帧（S05 的 10 帧、S06 的 5 帧、S07 的 3 帧） | 录下的帧等于网页的写法；新代码用同样的输入（质询、时间、序号、账号）写出的帧逐字节相同 |
| 收到的帧（S05 的 58 帧、S06 的 5 帧、S07 的 2 帧） | 逐帧一致：质询、登录、进房、下播房间、`unsigned` 的判定与网页相同；6 条评论（用户 id、名字、文字、等级、消息 id）、4 个人数与网页的投影相同；入场、贴图、礼物、热度、点赞、ping 回答都没有消息 |
| 用连接重放 S05 | 1 个游客账号请求（设备号是本实现生成的同形值）、1 个 socket、就绪 1 次，发出的帧与录制完全相同（回答、登录、进房、观众数请求，手动心跳时 6 个 ping），6 条评论、4 个人数按顺序上报 |
| 用连接重放 S06、S07 | S06：进房回答 `sid` "0" 后以 `connectionFailed` 结束，只发了回答、登录、进房；S07：`unsigned` 后丢掉账号、取新账号、换 socket，再次加入 |
| 进房给的参数 | 平台层用 `S03-studio-live`（`qashia305`）进房和录制详情得到的 `BigoDanmakuArgs` 是 `qashia305`、409742853、6812312308570332324，正是 S06 用的房间；S05 的参数是实测时用 `BigoSite.getRoomDetail` 取到的（`tikaa12`，列表里的 23382904） |

## 与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 设备号用随机数生成（同形），每次 `connect` 一个 | 网页用浏览器指纹的哈希，并存在浏览器里长期使用；应用不做指纹，也不需要跨会话的设备标识 |
| 2 | 不带密码进房，密码房不连 | 应用没有输入房间密码的界面（v3 起密码房就播不了，E06 平台层升级 24-2） |
| 3 | 进房回答 `sid` 为 "0" 时结束连接 | 网页只在在播时连接，不会遇到；应用重连时直播可能已经结束，空连着没有意义 |
| 4 | 被拒时换游客账号重连，连续第 4 次结束；加入 10 s 超时 | 网页登录失败重试 3 次后登出、进房失败只记日志、没有超时；错误的令牌服务端不回答（实测），不设超时会一直停在“连接中” |
| 5 | 重连按框架的退避（最多 8 次） | 网页出错立刻重连，最多 3 次；统一用框架的做法 |
| 6 | 只报评论、付费弹幕和人数 | 礼物、爱心、关注、分享、入场、公告和房间状态不报，和 D01.2～D01.22 的范围一致（v3 所有平台都不显示礼物，`LiveMessageType.gift` 注明“not shown yet”） |
| 7 | 付费弹幕按普通聊天显示 | 网页也在聊天列表里按评论显示；它的横幅没有金额，做成醒目留言没有价格可填（见“放到其他模块的部分”） |
| 8 | 不处理下播、暂离（3608） | 同 D01.22，放到 M13 |
| 9 | 关闭时不发 `close` 文本、下播时不发 `7|24` | 直接关闭 socket 效果相同；`7|24` 只在网页收到下播时发 |

和 E03.11 规格的出入：归档规格 §7 说网页聊天是“私有的二进制 WebSocket”。实际是文本帧（事件号加 JSON，服务端名字里的 `json2yy` 说明它在服务端转成 YY 协议），不需要抓包，也没有私有签名：回答质询用的是网页里公开的 MD5 写法，而且服务端不校验。

## 样本

2026-09-30 12:33～12:39 UTC 经本机代理录制，请求头同本实现（账号请求：`Origin`、`Referer`、`User-Agent: Mozilla/5.0`、表单内容类型、不跟随跳转；握手：`Origin`、`User-Agent: Mozilla/5.0`），录制程序只发网页会发的帧（S07 例外：故意在回答质询前登录）。

| 样本 | 内容 |
|---|---|
| `S05-live` | `tikaa12`（列表 23382904，在播，列表 557 人）：录了 240 s、218 行，保留前 71 行（约 63 s）：账号请求和回答、质询、回答、登录和回答、进房和回答、观众数请求和回答、6 个 ping 和回答、6 条评论、3 个 `NUMS`、礼物（类型 6 和动画、豆子总数）、贴图、入场、热度、点赞；之后是更多同类的帧。`meta.json` 的 `kept` 记着原行号 |
| `S06-idle` | 已下播的 `qashia305`（S03 的主播，房间号 6812312308570332324）：完整流程，进房回答 `sid` "0"，`11032` 为 0，ping 有回答 |
| `S07-unsigned` | `tikaa12`：打开后立刻登录（抢在质询之前），服务端回 `unsigned`，之后的 ping 没有回答 |

脱敏（逐个字段检查过，`meta.json` 的 `scrubbed` 和 `reduced` 有记录；`raw` 是原始录制的 SHA-256 和长度）：

- 游客账号：`userId` 换成 `1000000001`，`uidToken` 换成同形（大写换大写、小写换小写、数字换数字，`+`、`/` 保留）的随机值，`seqId` 换成 `100000001`，设备号换成 `web_0123456789abcdef0123456789abcdef_Sample_<原毫秒>`；登录帧、登录回答、进房帧、进房回答的 `fromUid`、观众数回答的 `uid` 里的同一个值一起换；
- 质询换成 `c3ludGhldGljLWNoYWxsIQ==`（"synthetic-chall!"），回答的 `sign` 按新质询重新算过，所以样本仍然前后一致；
- **登录回答的 `clientIp`（调用方地址）** 换成 `3362010054`，按网站的小端写法是文档地址 198.51.100.200。门禁的 `fixture privacy` 只查点分写法和 Base64，看不到这种十进制写法，所以另由测试守着（样本里的 `clientIp` 只能是 0 或这个值）；
- 其他观众：`from_uid`、`payload.uid`、礼物动画的 `from_uid`、管理员列表换成同位数的合成号码，同一个人同一个值；名字（`content.n`，包括 `ID:<号>` 形式）换成“观众 1”～“观众 11”，`content` 按原来的 JSON 写法重新 Base64；
- 进房回答里主播的设备型号（`from_client_model`）和 `owner_uuid` 换成同形值；
- 缩减：观众列表（`11032.users`、`NUMS` 的 `addUser`/`delUser`，里面有头像地址和令牌）清空；评论的 `others` 只留数字标志，其他消息的 `others` 清空；礼物动画只留礼物字段（去掉名字、头像和带令牌的图片地址）；
- 评论文字、礼物名、贴图的公开图片地址（`static-comm.bigolive.tv`）保留；主播的公开信息（主播账号、房间号、`sid`、Bigo 号、昵称、开播时间）按 E03.11 的口径保留；
- 找不到 IP 地址、头像路径、Cookie；门禁的 `fixture privacy` 通过。

## 受阻

没有。协议全部来自网页公开的脚本和匿名连接时平台自己给的值（游客账号），没有用到登录、私有签名、第三方密钥或绕过访问限制。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（D01.1 的原因表）。没有直播的详情是 `No broadcast in room <号>`，被拒是 `Chat refused: login: res …`、`enter: resCode …`、`unsigned: …`，加入超时是 `login or entry unanswered` 或 `no challenge or login` |
| 房间公告 `bigo_chat_notice` 的文字 | 已在平台层改好：`BigoApi.chatNotice` 去掉“这里暂时看不到 Bigo Live 直播间的聊天。”，只说明人数（“列表里的人数是正在观看的人数；进入直播间后，人数随弹幕更新。”）；对照测试把公告列为有意差异（注明 D01.21）；翻译在 M13 |
| 直播间里的在线人数 | 弹幕连着时由 `NUMS` 更新；关闭弹幕时进房后没有人数（直播间回答没有），界面是否沿用列表卡片的人数由 M13 决定（E03.11 已列） |
| 下播、暂离提示 | M13 决定是否要：聊天流有 3608（`roomStatus` 1、2、5 结束，3 暂离，4 回来），本实现不报；要用时在协议层加一个事件 |
| 显示礼物、点亮爱心、关注、分享（若以后要做） | M13 统一决定；本平台是 `tag` 3、6、8、10，礼物名要查网页的礼物表（`getOnlineGifts`） |
| 付费弹幕显示为醒目留言 | M13 统一决定（同 D01.17、D01.20 的候选）；网页的横幅只有名字和文字，没有金额 |
| 密码房的聊天 | 要先有输入密码的界面（M13）；进房帧的 `secretKey` 填密码即可 |
| 录制时是否带弹幕 | H01.1（录制详情也带参数） |
| 长连接 24～27 分钟后被断开（经代理实测，原因不明） | M13 真机直连观察；若是服务端的固定时限，照 D01.22 在到期前悄悄换 socket，避免定时出现重连提示 |
| `live_core` 的 `LiveDanmaku`、`BigoSite.getDanmaku()` | D01 各平台完成后删除 |

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖（MD5 用 `live_danmaku` 已有的 `crypto`）。`live_danmaku.dart` 按字母顺序加了一行导出。`live_core` 只做了添加：`bigo_api.dart` 加 `BigoDanmakuArgs`、`BigoApi.danmakuArgs`，`BigoApi.room` 加可选参数 `danmaku`（默认不带，行为不变）；`bigo_site.dart` 的进房和录制详情传 `danmaku: true`；改了公告 `chatNotice` 的文字；`audience.dart` 本平台那一项只补了注释。

## 测试

`live_danmaku` 的 `test/sites/bigo_test.dart` 27 个用例，`live_danmaku` 共 990 个；`live_core` 的 BIGO 测试新增 2 个（本平台共 101 个，`live_core` 共 3523 个）。连续跑 3 次全部通过；三个测试文件在时钟 +30 天、+1 年、+5 年下直接运行（`tools/timeshift` 的方式）也都通过，进程正常退出。所有写时间的帧都用注入的 `now`（样本的录制时间），测试里没有依赖真实时钟的期望值。

- 协议 9 个：地址、请求头、时序常量和事件号（等于 `toUri`）、与 `meta.json` 的握手一致；账号请求与录制的逐项相同、设备号的形式；账号回答（录下的、`###VER2`、空名字和设备号的替代、16 种看不懂的回答）；参数检查（合规、去空白、10 种不合规）；五种客户端帧的逐字节写法（含不足 8 字的质询）；控制帧（质询、登录、进房、`sid` 为 "0" 或缺失、各种被拒、`unsigned` 的几种写法、12 种不是控制帧的帧、字节帧）；一条评论的各字段；评论的边界（类型、房间、Base64 和 UTF-8、文字、名字、用户 id、消息 id、等级）；人数（两种帧、各种坏值、别的房间、下播房间的回答）。
- 录制 6 个：三个样本的客户端帧等于网页的写法，新代码写出的逐字节相同；收到的每一帧与网页的读法一致（共 6 条评论、4 个人数）；登录回答里的调用方地址只能是脱敏后的文档地址（门禁看不到这种十进制写法）；用连接重放 S05、S06、S07。
- 连接 12 个：默认时序和平台表登记；握手（先请求账号再握手、地址、请求头、代理路由、服务端先说话、登录前不 ping、登录等 1 s、登录发出前的登录回答不进房、每个 socket 只回答一次质询、进房后就绪并请求人数、别的房间和非评论不报、手动 ping）；定时 ping 只在登录后发、关闭后不再发；断线后用同一个账号重连并再次就绪；登录被拒、进房被拒、`unsigned` 各换一个新账号，加入成功后重新计数，连续第 4 次结束（7 个 socket、7 个账号）；加入超时换账号重连；没有直播的房间结束；账号请求失败（超时、502、业务码）按握手失败重试，一直失败时 `reconnectsExhausted`；socket 握手失败时账号留给下一次；参数不对直接结束、不请求也不握手，参数类型不对抛 `ArgumentError`；关闭时取消进行中的账号请求，关闭后没有事件，再次 `connect` 换房间（旧的登录计时器不再触发、新房间取新账号）；真实的本地服务器（握手的路径、`Origin`、UA，回答、登录、进房、人数请求、ping 的顺序，人数和评论生效，结束时关掉服务端所有升级后的 WebSocket 和服务器）。
- `live_core`：`bigo_api_test.dart` 1 个（参数的几种情况：在播、付费秀、令牌之后的使用给参数；下播、登录门、在播而要求登录、密码房、`roomType` "1"、没有房间号不给；`room` 默认不带、`danmaku: true` 才带、不写进 JSON）；`bigo_site_test.dart` 1 个（进房和录制详情带参数、刷新和按号搜索不带，都只有原来的三个请求；登录门后的进房不带）。原有用例的公告差异注释改为注明 D01.21。
