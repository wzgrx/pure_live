# T06a.28 弹幕（新增）：六间房

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/sixroom.dart`
  - `SixRoomDanmakuConnection`：连接；
  - `SixRoomDanmakuProtocol`：取服务器列表的请求和回答的解析、登录和心跳帧、帧的解码、网页给游客看的过滤，不做 I/O；
  - `SixRoomDanmakuFrame`：一帧解出的内容。
- 参数：`live_core` 的 `SixRoomDanmakuArgs(roomId, userId)`，T02b.12 已给出：进房（`getRoomDetail`）时放进 `LiveRoom.danmakuData`，不多发请求。`userId`（主播的用户 id，网页的 `page.rid`）决定聊天服务器、也是登录的 `roomid`；`roomId`（房间号）只用作取服务器列表时的 Referer。`live_core` 只改了房间公告（见“放到其他模块的部分”）和这个类的文档注释。
- 升级条目：31-6“聊天”。v3 没有六间房聊天（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本：`fixtures/sixroom/danmaku/S07-live`（本模块新录，2026-09-30 12:31 UTC，房间 80518，180 s，211 行），期望值 `expected.json` 由 `fixtures/sixroom/danmaku/page_expected.py`（网页脚本逻辑的 Python 移植）生成，见“样本”。
- 参考：
  - 归档 v4（`archive/v4`，6ba709135）：没有六间房弹幕。`spec/sites/sixroom.md` 第 7 节只有一句“不做。旧版未接入；房间页的聊天走 6.cn 私有 WebSocket（需要 `encpass` 等会话参数），匿名接入方式 [待确认]”。本模块确认了：游客的 `encpass` 是空的，不需要任何会话参数；
  - pure_live_TV `e1cca224`：`lib/platforms/sixroom/` 与 v3 相同，`getDanmaku()` 是 `EmptyDanmaku`，没有可参考的实现；
  - 规格只能来自平台自己：公开房间页 `https://v.6.cn/<房间号>` 加载的脚本（2026-09-30 下载，见“规格来源”）和 2026-09-30 的只读匿名实测（见“实测”）。

## 做法

- **建在 T06a.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`）。平台代码只写这几样：
  - `target`：检查参数，为这次 `connect` 生成一个游客号，给出名义地址和握手请求头；
  - `onOpen`：发登录帧；
  - `onData`：解一帧；`login.success` 到了才就绪（`session.ready()`），就绪时立即发一次心跳；
  - `heartbeatFrame`：网页的 `noop` 心跳。
  - 换地址、退避、最多 8 次、无消息检测、登录时限、停止后不再有事件，都由框架和 `LiveSocket` 负责。
- **服务器列表的请求放在握手里**（同 T06a.12 TwitCasting、T06a.22 PandaTV 的做法，框架没有改：`connector` 参数本来就允许替换握手）：
  - 交给 `LiveSocket` 的是名义地址 `https://v.6.cn/room/getChat.php?rid=<用户 id>`；本平台的握手函数每次握手取列表里的下一个服务器，列表还没有或者每个服务器都用过一次时，先 GET 这个地址取新列表（回答里的顺序服务端每次都打乱）；
  - 请求就是网页进房时 jQuery 发的那个（同样的地址和查询、请求头见“协议”，不跟随跳转，以 `sixroom` 的名义发出，走本平台的代理设置），超时同握手（10 s），一次 `connect` 里的请求绑定一个 `CancelToken`，`close` 或换房间时取消；
  - 请求失败（网络错误、状态码、回答里没有 `*.6rooms.com` 的服务器）当作这次握手失败，走框架的退避和 8 次上限。
- **以游客登录**：打开后发 `command=login`，`uid` 是游客号（1800000000～1899999999 的随机数，网页没有 `_LiveGuestUser` Cookie 时的做法），`encpass` 为空，`roomid` 是主播的用户 id。游客号每次 `connect` 生成一个，同一次连接里的重连沿用（网页每次打开页面生成一个，重新登录沿用）。
- **不发 `priv_info`**：网页登录成功后会用 `sendmessage` 发一个 `priv_info`（取自己的信息），服务端回 408（带 `authKey` 等）。实测发不发收到的消息完全一样（见“实测”），本实现只读，不发；代价是服务端对每个心跳多回一个 flag 205（“不是用户”），本实现忽略它（网页收到 205 会重新登录，但网页从不会收到，见差异 1）。
- **登录被拒就重连**：`login.failed` 时重连（换下一个服务器），连续第 4 次以 `DanmakuClosed(connectionFailed, 'Chat refused: login.failed')` 结束，登录成功一次就重新计数（次数同 T06a.22）。收到拒绝也算收到消息，框架的 8 次上限管不到这种循环，所以要自己计数。实测没有遇到过 `login.failed`。
- **网页会停掉 socket 的 flag 直接结束**：101 被踢、102 人满、103 付费房、104 密码房、109～114 被禁或移出、204 房间关闭、305 等级不够、306 要重新登录，以 `DanmakuClosed(connectionFailed, 'Chat refused: flag <代码>[: 服务端的文字]')` 结束，不再重连（网页停掉 socket 并弹框，重连没有意义）。其他 flag（发言太快、禁言、205 等）只影响发言，忽略。
- **不需要保留请求头大小写**：实测不带 `Origin` 也能握手，用默认的 `dart:io` 握手，不用 `connectExactWebSocket`。请求头照网页带 `Origin: https://v.6.cn` 和平台层的 Chrome 140 UA。
- **只上报聊天**：公聊（101，单独来，或在 110、1413 的列表里）和飞屏（108）。醒目留言、付费留言的情况见下；礼物、进场、榜单、PK、麦位、系统公告都不报（和 T06a.2～T06a.22 的范围一致）。
  - 飞屏是付费的（1000 六币，“跟风飞屏”2000），网页把它从视频上方飘过，写成“<名字>说：<内容>”。本实现当作普通聊天行（名字、内容），不带价格、不做成醒目留言（同 T06a.17 CHZZK 把捐赠当聊天行），做成醒目留言列为候选。实测没有录到飞屏，字段取自网页脚本（`from`、`content`，另读可能有的 `fid`、`tm`）。
- **在线人数的来源不变**：聊天流里没有人数。网页的观众人数来自 413 信号触发的 HTTP 请求 `/room/getRoomList.php?id=<用户 id>&tm=<时间>`，它的 `num` 就是 inroom 的 `roomlist.content.num`（T02b.12 发现它与首页卡片的 `count` 相近，是热度口径），本模块不拉；`audience.dart` 里六间房一项（热度，没有在线人数）不用改。

## 协议

服务器列表：

| 项目 | 内容 |
|---|---|
| 请求 | `GET https://v.6.cn/room/getChat.php?rid=<主播用户 id>`；请求头照网页的 jQuery：`User-Agent`（Chrome 140）、`Accept: application/json, text/javascript, */*; q=0.01`、`Accept-Language`、`Referer: https://v.6.cn/<房间号>`、`X-Requested-With: XMLHttpRequest`（实测什么都不带也行） |
| 回答 | `{"a":[],"b":[],"websock":["snbjh2.6rooms.com:5390","snbjg1.6rooms.com:5390","snbjh1.6rooms.com:5390","snbjg2.6rooms.com:5390"]}`（`content-type: text/html`）。四台主机 `snbj{g,h}{1,2}.6rooms.com`，端口是房间的分片，每次顺序不同。只接受 `6rooms.com` 或它的子域名、端口 1～65535 的 `主机:端口`，重复的只留一个，其余都算没有 |
| 分片 | 实测 14 个用户 id 的端口都等于 5190 + 100 ×（用户 id mod 6），与房间页 CSP 里的 `wss://*.6rooms.com:5190`～`:5690` 对得上。本实现不用这个规律，照网页用回答 |
| 没有的房间 | `rid` 为 `0`、不是数字：回答 `[]`（算没有服务器）。不存在但像 id 的数字照样给列表 |
| 备用 | 网页取列表失败时改取 `/room/getIpList.php?rid=`，实测回答为空（200，0 字节），本实现不用 |

socket：

| 项目 | 内容 |
|---|---|
| 地址 | `wss://<主机>:<端口>`（网页：`"wss://" + ip + ":" + port`，路径为空） |
| 握手 | 请求头 `Origin`、`User-Agent`（见上）；不带 `Origin` 也能连（实测） |
| 帧 | 都是文本帧。服务端的帧第一行是后面内容的 UTF-8 字节数（实测 1322 帧都对得上），之后是 `key=value` 行，`\r\n` 分隔，每帧一条命令；客户端的帧没有长度行（网页的 `implode`）。本实现按第一个 `=` 拆行，跳过没有 `=` 的行 |
| 登录 | `command=login\r\nuid=<游客号>\r\nencpass=\r\nroomid=<主播用户 id>\r\n` → `47\r\nenc=no\r\ncommand=result\r\ncontent=login.success\r\n`（实测 35 ms 内）；失败是 `content=login.failed` |
| 心跳 | `command=sendmessage\r\ncontent=y8vPLwAA\r\n`（`y8vPLwAA` 是 `noop` 压缩编码后的样子）→ `content=send.success` 的结果；没发过 `priv_info` 的游客另收到 flag 205（`"bbbbb"`） |
| 下行 | `enc=yes|no\r\ncommand=receivemessage\r\ncontent=<Base64>`。`enc=yes`：原始 DEFLATE（服务端的字节与 zlib 等级 6 完全相同，实测 281 帧），Base64 里 `+`、`/`、`=` 写成 `(`、`)`、`@`；`enc=no`：标准 Base64（实测只有全站的信号 415、416）。解出的是 JSON：`{"flag":"001","content":{"typeID":…}}`，flag 不是 `001` 是错误（`content` 是说明文字） |

消息（`content.typeID`）：

| typeID | 内容 | 本实现 | 网页 |
|---|---|---|---|
| 101 | 公聊：`from` 名字、`fid` 用户 id、`frid` 用户的房间号、`to`/`toid`/`torid` 对谁说、`content` 文字、`tm` 时间（秒）、`picEmoji`、`supremeMystery`，另有徽章、等级、头像等几十个字段 | 白色聊天（见下） | `chatList.parsePub` |
| 110 | 101 的列表（`content`） | 每一条按 101 读 | 每一条 `parsePub` |
| 1413 | 任意消息的列表（`content`），实测多是进场（123）和主播的欢迎语（101） | 每一条按自己的类型读，最多 4 层 | 每一条 `Msg.get` |
| 108 | 飞屏 | 白色聊天：名字 `from`、文字 `content`、`fid`、`tm`（没录到） | 视频上方飘过“<from>说：<content>” |
| 153 | 系统飞屏（只有 `content`） | 不报 | 视频上方飘过 |
| 102 | 系统公告（HTML，带链接） | 不报 | 聊天列表里的系统行 |
| 107、111 | 给自己的私聊 | 不报（游客收不到） | 私聊列表 |
| 123 | 进场 | 不报 | 聊天列表里的“来了” |
| 201 | 礼物 | 不报 | 礼物列表 |
| 413、414、415、416 | 只带一个时间戳的信号 | 不报 | 分别去拉观众列表（`getRoomList.php`）、粉丝榜（`getRoomFans.php`）、房间公告（`getRoomNotice.php`）、系统消息（`getRoomMsgSys.php`） |
| 1570、865、5100、4185、1112、1113、2033、4245、320 等 | PK、麦位、连线、活动等状态 | 不报 | 各自的面板 |

公聊解成白色聊天（照 `parsePub`）：

- 名字 `from` 为空（或没有）时不显示，除非是“神秘人”（`supremeMystery` 为 1）；
- 文字是 `content` 先把 `&amp;` 换成 `&`、再解字符引用（网页把它当 HTML 写进页面，浏览器会解引用），去首尾空白；表情代码（`/狂笑`）原样保留（网页换成图片）；没有文字不报；
- 图片消息（`picEmoji.pic` 不为空）：网页不显示文字，只显示图片（替代文字“AI表情”），本实现写成 `[AI表情]`；
- 用户 id `fid`（字符串或整数），时间 `tm`（秒；不大于 0、不是整数或超出 `DateTime` 范围时为空）；
- 没有消息 id（平台不给）；对谁说（`to`）不显示。

网页给游客看之前的过滤（`Room.Msg.get`，对每条消息、包括 1413 里的每一条都做）：

- `cli`（客户端掩码）有值（按 JavaScript 的真假）而且没有 PC 位（1）的不显示；
- 要求财富等级（`newLimitLevel` 存在且不是 -1）或明星等级（`starLimitLevel` 是 -1 以外的数字）的不显示：游客没有等级。实测的公聊都带 `"-1"`；
- 房间类型（`rtype`）和 `screenSocket` 过滤没有照做：参数里没有房间的类型，inroom 的 `screenSocket` 实测为空，公聊也不带 `rtype`。

## 连接和时序

| 项目 | 本实现 | 网页 | 依据 |
|---|---|---|---|
| 服务器列表 | 第一次握手前 GET；每次握手用下一个服务器，每个用过一次后再取新列表 | 进房取一次，打乱后每次登录用下一个（`index++ % length`），不再取 | 差异 3 |
| 取列表失败 | 当作握手失败，按退避重试 | 改取 `getIpList.php`（实测为空） | 差异 3 |
| 握手请求头 | `Origin`、Chrome 140 UA | 浏览器 | 实测不带 `Origin` 也能连 |
| 登录 | 打开后发（游客号、空 `encpass`、`roomid` 为主播用户 id） | 同 | — |
| 游客号 | 每次 `connect` 随机一个，重连沿用 | 每次打开页面随机一个（有 `_LiveGuestUser` Cookie 时用它） | — |
| 就绪 | `login.success`；每次重新登录都报一次 `DanmakuReady` | `login.success` | — |
| 登录时限 | 6 s（从 socket 打开算），超时换下一个服务器重连 | 6 s（从开始连接算），超时 2 s 后换下一个服务器 | 网页的 `timeout` |
| 心跳 | `login.success` 时立即一次，之后每 16 s（从打开算）；手动 `heartbeat()` 立即发一次 | `login.success` 后 1 s 一次，之后每 16 s | 差异 2；不发心跳 20 s 后服务端断开（实测） |
| 无消息超时 | 90 s（框架默认）；服务端回答每个心跳，不会误判 | 无 | 框架默认 |
| `priv_info` | 不发 | 登录后发，没收到 408 时每 30 s 再发 | 差异 1 |
| flag 205 | 忽略 | 2～5 s 后重新登录 | 差异 1 |
| `login.failed` | 重连；连续第 4 次结束（`connectionFailed`），登录成功就重新计数 | 2 s 后重新登录（下一个服务器），最多 100 次后提示“网络繁忙” | 差异 4 |
| 断线重连 | 框架默认：一个名义地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，收到任何帧清零，一轮只提示一次；每次换下一个服务器 | 2 s 后换下一个服务器，最多 100 次 | 框架的统一做法 |
| 网页停掉 socket 的 flag | 以 `connectionFailed` 结束 | 停掉 socket、弹框 | — |
| 参数不对 | 房间号不是 2～12 位数字或用户 id 不合规（`SixRoomApi.isUserId`）：`connectionFailed`（`No usable room or broadcaster`），不请求、不握手 | — | 用户 id 要写进登录帧 |
| 下播 | 不处理；未开播的房间照样能登录，只收到全站的信号 | 页面按其他消息更新 | 放到 M13 |

## 规格来源

房间页 `https://v.6.cn/80518` 等（2026-09-30 下载）用 rspack 的模块联邦按需加载脚本，入口是 `https://vr0.6rooms.com/hao/vintage/bootstrap_d5c3f72e430ad8a1x.js`（构建时间 26/9/27）：它的 `__webpack_require__.u` 表给出每个块的文件名，公共路径 `//vr0.6rooms.com/hao/vintage/`。下面每条结论出自的块（文件名带内容哈希；模块号是块里的键）：

| 结论 | 出处 |
|---|---|
| 登录帧、6 s 登录时限、`login.success` 后 1 s 开始心跳、之后每 16 s、心跳帧 `y8vPLwAA`、`implode`（`\r\n` 连接、末尾空行）、`explode`（按 `=` 拆行）、`enc=yes` 用 `D4` 解、否则 `atob` | `chunkimport-pcwebsocket_b65c7291518068d7x.js`（26/8/6），模块 85534 的 `PCWebSocket`：`login`、`onMessage`、`_heartbeat`、`_onLoginSuccess`、`convey` |
| 编码：Base64 的 `+ / =` 写成 `( ) @`，`lF` 用 pako 以等级 6 原始 DEFLATE 压缩，`D4` 解压 | `chunk6236_09189e40d009daf6x.js`（26/8/6）和 `chunk6235_cd65a36569fd2b6dx.js`，模块 54418 |
| 服务器列表 `/room/getChat.php?rid=` + `page.rid`，失败改 `/room/getIpList.php`；`websock` 打乱（`chunk609_*` 的 `shuffleArray`）；`IP.getIp` 轮换并按 `:` 拆开；`proxy.login("wss://" + ip + ":" + port, uid 或 guest_id, encpass 或 "", page.rid, …)` | `chunk8104_637d0de24aec0ea9x.js`（26/9/18），`L.Socket` 的 `login`、`ipBack`、`IP` |
| `login.success` 后发 `priv_info`（每 30 s 直到收到 408）；`login.failed` 和 `close`/`error`/`timeout` 都 2 s 后重新登录（`tryLogin`，最多 100 次）；flag `001` 进 `Msg.get`，其他进 `parseErr` | 同上，`callback`、`parback`、`tryLogin`、`pMessage` |
| 错误 flag 的表（101 `onKickout`、102 `onFull`、103 `onRepay`、104 `onPwd`、109～114、204 `onClosed`、205 `onNotUser`（2～5 s 后重新登录）、213 `onbad`、305、306……）和哪些会 `room_stop` | 同上，`B.err` 和各处理函数 |
| `Msg.get` 对每条消息的过滤（`cli`、`rtype`、`screenSocket`、`newLimitLevel`、`starLimitLevel`）；1413 逐条 `Msg.get`；413～416 去拉 HTTP 接口 | 同上，`L.Msg.get`、`_getback` |
| 游客的 `_puser`：没有 `uid`，`guest_id` 取 Cookie `_LiveGuestUser`，没有就是 `Math.floor(1e8 * Math.random() + 18e8)`；`encpass` 只在登录后从 Cookie `ticket_v` 来 | `chunk3124_6e8af233098f1ef3x.js`（26/9/21） |
| 101、110 进 `chatList.parsePub`，107 私聊；`parsePub` 的显示规则（`from` 为空不显示，除非 `supremeMystery`；`picEmoji.pic` 时只显示图片、替代文字 AI表情；`&amp;` 换成 `&` 后写进 HTML；`to` 不为空时写“对 … 说”） | `chunkimport-room_2016_59f3e19f42e15dcfx.js`（26/9/22），`Room.chatList` 的处理表和 `parsePub` |
| 108、153 是飞屏（`Room.GiftFly.add`：`t.from + "说：" + t.content`）；413 → `/room/getRoomList.php`（观众列表的 `num`），414 → `getRoomFans.php`，415 → `getRoomNotice.php` | 同上，`Room.GiftFly`、`Room.userList` 和各处理表 |
| 飞屏的价格 | 房间页 HTML 的按钮提示（`data-sug`：“飞屏，价格：1000个六币”“跟风飞屏，价格：2000个六币”） |
| 聊天端口的范围 | 房间页响应头的 CSP：`connect-src … wss://*.6rooms.com:5190 … :5690` |

实测确认的（见“实测”）：服务器列表的样子和分片、游客登录不需要 `encpass`、不发心跳 20 s 断开、`priv_info` 不影响收到的消息、205、帧的长度行、DEFLATE 等级。

## 与归档 v4、上游的差异

归档 v4 和 pure_live_TV 都没有六间房弹幕（v4 规格 §7 写“不做”，TV 是 `EmptyDanmaku`），没有可对照的实现和解码输出。v4 规格“需要 `encpass` 等会话参数，匿名接入方式待确认”一句，本模块实测后更正：游客登录的 `encpass` 为空，游客号是客户端自己随机生成的，不需要任何会话参数、签名或 Cookie。

## 与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 不发 `priv_info`，忽略服务端对心跳多回的 flag 205 | 只读：`priv_info` 是取自己的资料（回答带 `authKey`），对收到的房间消息没有影响（实测 3 分钟两个连接逐类型计数相同）。网页一定发 `priv_info`，所以它收到 205 就重新登录；不发时每个心跳都有 205，照网页重新登录会每 16 s 断一次，所以忽略。实测忽略 3 分钟，服务端没有断开 |
| 2 | 心跳在 `login.success` 时立即发一次（网页 1 s 后），之后的周期从 socket 打开算（网页从登录成功算） | 框架的心跳计时从打开开始；两者都在服务端 20 s 的限期内 |
| 3 | 服务器列表里的每个服务器用过一次后再取新列表；取不到时按握手失败重试，不改取 `getIpList.php` | 长时间连接时列表可能变；`getIpList.php` 实测回答为空 |
| 4 | 重连按框架（8 次、退避）；`login.failed` 连续第 4 次结束 | 各平台统一；网页 2 s 一次、100 次。收到拒绝也会清零框架的计数，要自己计数防止死循环 |
| 5 | 213（`onbad`）不处理 | 网页收到 213 时把 `encpass` 换成脚本里写死的一个值再登录；那是给登录用户的补救，游客没见过 213，本实现不用这个值 |
| 6 | 名字为空或没有 `from` 的公聊不显示 | 网页只排除空字符串，没有这个字段时会显示成“undefined” |
| 7 | 文字去首尾空白，字符引用只解常见的（`decodeHtmlEntities`：`&lt;` 等、数字引用） | 浏览器会解全部 HTML 实体；实测的聊天里没有实体 |
| 8 | 图片消息写成 `[AI表情]`；表情代码不换成图片 | 弹幕只有文字；表情图片见候选 2 |
| 9 | 不做 `rtype`、`screenSocket` 过滤 | 见“协议” |
| 10 | 1413 里有一条读不出时只跳过这一条 | 网页处理整帧时一条出错会中止后面的（`pMessage` 的 `try`） |
| 11 | 不显示“对 … 说”的对象 | 和其他平台一样只显示发言人和内容 |
| 12 | 飞屏当普通聊天行，不带价格 | 见“做法”，醒目留言列为候选 1 |
| 13 | 解压后超过 4 MB 的消息丢掉，列表嵌套超过 4 层不读 | 防止压缩炸弹；实测最大的消息 31 KB，1413 只有一层 |

## 登记方式

应用（T07a.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.sixRoom: () => SixRoomDanmakuConnection(http: sixRoomHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `SixRoomSite` 的同一个 `LiveHttp`。服务器列表的请求以 `sixroom` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `sixroom` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie：全程匿名，v3 也没有六间房的登录。
- `connector`、`policy`、`random` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（直播中和未开播都有）；刷新、录制详情没有参数，按 T06a.1 不连接。

## 实测

2026-09-30 12:03～12:35 UTC（北京时间 20:03～20:35，晚高峰）只读、匿名、直连，没有登录，没有发言，没有送礼。用只依赖 `dart:io` 的小程序，按移动端推荐列表（`special`）选在播的人气房间；除了登录和心跳，只在一次对照里发过网页自己会发的 `priv_info`（见下），输出里只看类型、字段名和数量；探测的原始帧没有存成样本（样本只有下面“样本”一节的那一次录制）。

- **服务器列表**：约 24 次请求（14 个用户 id），都回四台主机；端口随用户 id 固定（5190～5690，六个都见到了，见“协议”），顺序每次不同；不带任何请求头也回答；`rid=0`、`rid=abc`、不带 `rid` 回 `[]`。
- **握手**：带 `Origin` 和 UA、只带 UA 都能打开。
- **登录**：随机游客号、空 `encpass`：35 ms 内 `login.success`。`uid=0`、`roomid=abc`：服务端立即断开，没有回答。不存在的房间（`roomid=1`）：`login.success`，只收到全站的信号。连错分片（5490 的房间连 5190）：`login.success`，只收到全站的 415、416，没有房间消息。
- **心跳**：登录后不发任何东西，20 s 后服务端断开（1006）；只打开不登录，10 s 后断开。每 16 s 发 `noop`，3 分钟都在；每个心跳回 `send.success`，没发 `priv_info` 的连接另回 flag 205 `"bbbbb"`。
- **`priv_info`**：同一房间同时开两个连接各 3 分钟，一个照网页发 `priv_info`、一个不发：前者收到 408（带 `authKey`、`priv` 等自己的资料），此后心跳不再有 205；两者收到的房间消息按类型计数完全相同（1570 141 条、1413 119 条、415 5 条、102 2 条……）。
- **帧**：探测时收到的 1322 帧，每帧一条命令，第一行都等于后面内容的 UTF-8 字节数；`receivemessage` 里 `enc=no` 的只有 415、416（413、414 是压缩的）；一个 3 分钟连接的 281 个 `enc=yes` 帧解压后用 zlib 等级 6 重新压缩，与服务端的字节完全相同。
- **消息**：五个人气房间各 3 分钟：公聊很少，单独来的 101 每间 2～9 条，1413 里的 101（多是主播的自动欢迎语）0～3 条；1413 的其余都是进场（123）；没有 110、108、图片消息、神秘人；没有 IPv4 地址和 `ip` 之类的字段；解压后最大的消息 31 KB。
- **本实现**：没有接到真实服务器上跑（测试用本地服务器和假连接）；协议和上面逐项对照过，与实测一致；录制程序发出的帧与本实现相同（见“样本”）。

## 样本

`fixtures/sixroom/danmaku/S07-live`（新录）：

- 2026-09-30 12:31:42 UTC，直连，房间 80518（主播用户 id 57401078），当时推荐列表前列的房间，180 s。录制程序只做本实现会做的事：GET `getChat.php`（请求头与 `serverRequest` 相同）、连回答里的第一个服务器（`Origin`、UA）、以随机游客号和空 `encpass` 登录、`login.success` 时和此后每 16 s 发 `noop`。211 行：`getChat.php` 的回答、13 个发出的帧（登录和 12 个心跳）、197 个收到的帧；结束时我们自己的关闭没有保留。
- 内容：12 条公聊（9 条单独的 101、3 条在 1413 里的主播欢迎语），有表情代码（`/窃笑`）、带对象的回复；另有进场、礼物、榜单、PK 状态、信号、结果和 205。
- 脱敏（记在 `meta.json` 的 `scrubbed`、`note`）：
  - 登录帧里的游客号换成 1855555555（同形同长度）；
  - 公聊里观众的用户 id（`fid`、`toid`）、观众的房间号（`frid`、`torid`）换成同长度的合成数字（10000001…、200001…，数字仍是数字、字符串仍是字符串），名字（`from`、`to`，以及主播欢迎语里出现的名字）换成观众1～观众6；主播的用户 id、房间号和名字是公开信息，保留（同 T02b.12）；
  - 公聊只留 `parsePub` 和 `Msg.get` 读的字段（`typeID`、`tm`、`fid`、`frid`、`from`、`to`、`toid`、`torid`、`content`、`supremeMystery`、`picEmoji`、`at`、`danmaku`、`anonym`、`vest`、`fpriv`、`tpriv`、等级限制），去掉徽章、头像、军团名等（`reduced`）；其他类型的消息只留 `typeID` 和 `tm`（`dropped`）；只带时间戳的 413～416、结果帧和 205 没有改；
  - 改过的消息按服务端的写法编回（PHP `json_encode` 的 `\u` 转义和 `\/`、原始 DEFLATE 等级 6、站点的 Base64、新的长度行）；没改的消息编回后与录制逐字节相同（184 条都核对过），所以没有脱敏的部分就是原始录制。`raw` 是原始录制文件的 SHA-256 和长度；
  - 逐帧解码检查过：没有 IPv4 地址、Cookie、令牌、头像路径、设备号，找不到原来的观众 id、房间号、名字和游客号。门禁的 `fixture privacy` 通过（弹幕帧是压缩的，门禁看不到里面，所以另外逐帧检查了）。
- 录制和脱敏用的是自写的小程序（`dart:io` 的录制程序；Python 的脱敏脚本），没有放进仓库，`meta.json` 的 `tool` 和 `note` 写明了做法。
- `expected.json`：由 `fixtures/sixroom/danmaku/page_expected.py` 生成（在仓库根目录 `python3 fixtures/sixroom/danmaku/page_expected.py`），`generator` 字段写明来源。它把网页脚本里的 `PCWebSocket`（`explode`、`onMessage`、`login`、`_heartbeat`）、模块 54418 的 `D4`、`Room.Socket` 的服务器列表和回调、游客的 `Msg.get` 过滤、101/110/1413/108 的处理、`parsePub` 和 `parseErr` 逐行移植成 Python，与 Dart 实现互不依赖；输出服务器地址、登录帧、心跳帧、时间常量和每个收到的帧的结果（加入、拒绝、聊天行的名字、用户 id、文字、时间）。

## 受阻

没有。没能验证的：

- **飞屏（108）、公聊列表（110）、图片消息、神秘人、`login.failed`、会结束连接的 flag**：实测都没有遇到，只按网页脚本的字段和处理，用合成帧测试。
- **私密房、黑屏的房间**：没有样本（T02b.12 也没有），聊天照常连接；密码房实际会回 104 时以 `connectionFailed` 结束。
- **长时间连接**：实测最长 3 分钟；游客号、服务器列表都没有时效，心跳照网页。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | T07a.1（见“登记方式”） |
| 关闭、重连原因的界面文字 | M13（T06a.1 的原因表）。本平台的详情：`Chat refused: flag <代码>[: 服务端的文字]`、`Chat refused: login.failed`、`No usable room or broadcaster` |
| 房间公告 `sixroom_chat_notice` 的文字 | 已在平台层改好：`SixRoomApi.chatNotice` 去掉“这里暂时看不到六间房的聊天。”，只留“人数是平台的热度，不是正在观看的人数。”；私密房、黑屏的公告不变。3.x 的原文（“六间房远端聊天尚待接入；……”）在 T02b.12 已经换掉，平台层的对照测试把公告列为有意差异（测试里的 `_notice` 注明了 T02b.12 和 T06a.28，另断言了新文字），迁移也不用它，所以没有留 `legacyChatNotice`。翻译在 M13 |
| 未开播的房间要不要连接 | M13：进房详情总带参数；未开播的房间也能登录，只是没有房间消息 |
| 显示礼物（若以后要做） | M13 统一决定；本平台要解 201 |
| 录制时是否带弹幕 | T08a.1（录制详情现在不带参数） |
| `live_core` 的 `LiveDanmaku`、`getDanmaku()` | T06a 各平台完成后删除 |

后续候选（由用户决定）：

| # | 候选 | 现在 | 说明 |
|---|---|---|---|
| 1 | 飞屏显示为醒目留言（带价格） | 普通聊天行 | 价格按网页是 1000 或 2000 六币，回答里有没有价格要先录到样本；醒目留言要定显示时长和价格单位，需要 M13 定 |
| 2 | 表情代码显示成图片 | 显示成文字（`/狂笑`） | 网页的表情表 `FaceSymbols` 有 63 个代码，图片在 `//vr1.xiu123.cn/images/face/face_v5/`；v3 没有打包六间房的表情，要加资源（T01a.1） |

## 新增的通用能力、依赖

没有。框架没有改，没有新依赖（原始 DEFLATE 用 `dart:io` 的 `ZLibDecoder(raw: true)`）；`live_core` 只改了公告和参数类的文档注释。

## 测试

`test/sites/sixroom_test.dart` 27 个用例，`live_danmaku` 共 990 个，连续跑 3 次全部通过；本文件在时钟 +30 天、+1 年、+5 年下直接运行（`tools/timeshift` 的方式）也都通过，进程正常退出。本平台的代码不拿任何时间和“现在”比较（`tm` 只是换成 `DateTime`，游客号和服务器列表没有时效），不需要 `now:` 参数。`live_core` 的六间房测试（54 个，公告的用例多断言了新文字）照常通过。

- 协议 10 个：地址、请求头、帧、时间常量、`noop` 的解码、游客号的范围（最小、最大、1000 次随机）、会结束的 flag；取服务器列表的请求；列表回答（顺序、去重、大小写、主机和端口的各种不合规、状态码、不是 JSON、`[]`、没有 `websock`）；参数检查；帧的行（长度行、第一个 `=`、后值覆盖）；载荷（压缩和不压缩、有无填充、`@` 填充、坏的 Base64、坏的 DEFLATE、超过 4 MB、坏的 UTF-8）；帧（登录成功和失败、字节帧、其他结果、没有 `content`、205 等其他 flag、坏帧；13 个会结束的 flag 和带不带文字；不压缩的聊天帧）；一条公聊的各字段；公聊的边界（名字、神秘人、图片、字符引用、各种类型的文字、用户 id、时间的 0、负数、上限、越界、字符串）；消息（101、110、1413 的嵌套和 4 层上限、108、各种不报的类型、`cli` 的 14 种值、等级限制的 11 种值、整个列表被过滤）。
- 录制 3 个：服务器地址、登录帧、心跳帧、时间常量与网页脚本的移植（`expected.json`）和 `meta.json` 一致，录制发出的帧就是登录和心跳；197 个收到的帧逐帧与网页脚本的结果一致（加入 1 次、聊天 12 条）；用连接重放整份录制（1 个请求、1 个 socket、就绪 1 次、发出登录和心跳、12 条聊天按顺序）。
- 连接 14 个：
  - 默认时序和平台表登记；握手（请求、第一个服务器、请求头、代理路由、登录帧、`login.success` 前不就绪、就绪后发心跳、205 和信号不上报）；定时心跳和手动心跳；
  - 断线后换下一个服务器、游客号不变，四个都用过后再取列表；登录超时换服务器重连，就绪后不再超时；
  - `login.failed` 重连、成功后重新计数、连续第 4 次结束；会结束的 flag 立即结束、不再重连；
  - 列表请求失败（网络错误、503、`[]`）按握手失败重试后加入；一直失败以 `reconnectsExhausted` 结束；socket 握手失败换下一个服务器、不重取列表；
  - 参数不对直接结束、不请求也不握手，参数类型不对抛 `ArgumentError`；关闭时取消进行中的列表请求；关闭后没有事件，再次 `connect` 换房间和游客号；
  - 真实的本地服务器：列表请求（查询、Referer、`X-Requested-With`）、默认的 `dart:io` 握手（`Origin`、UA）、服务端收到登录和心跳、单独的公聊和 1413 里的公聊都上报；结束时关掉服务端所有升级后的 WebSocket 和服务器，直接运行测试文件时进程能退出。
