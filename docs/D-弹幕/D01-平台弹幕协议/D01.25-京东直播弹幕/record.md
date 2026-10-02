# D01.25 弹幕（新增）：京东直播

- 日期：2026-09-30
- 目标：`packages/live_danmaku/lib/src/sites/jdlive.dart`
  - `JdLiveDanmakuConnection`：连接；
  - `JdLiveDanmakuProtocol`：`liveauth` 的内容、加密、请求和回答的解析、名义地址、令牌的去除、帧的解码，不做 I/O；
  - `JdLiveChatAuth`（一次 `liveauth` 给的 socket 地址和掩码）、`JdLiveDanmakuFrame`（一帧解出的消息和“直播结束”）。
- 参数：`live_core` 新增的 `JdLiveDanmakuArgs(liveId)`（`packages/live_core/lib/src/sites/jdlive/jdlive_api.dart`，只加）。
  - 进房（`getRoomDetail`）和录制详情里，直播中、不是仅限 App 的场次把它放进 `LiveRoom.danmakuData`（`JdLiveApi.room` 的 `withData`）；不多发请求：聊天只要场次号，进房本来就有。
  - 关注刷新、列表卡片、未开播、已结束、回放、暂停、仅限 App 的都没有参数。仅限 App 的场次能不能连聊天没有样本核实（E02.9 也没见过 `secret` 为 1 的回答），不给。
  - 同时按协调要求改了房间公告：`JdLiveApi.chatNotice` 去掉“这里暂时看不到京东直播的聊天。”，只留人数说明。合并后协调者又把它改成“列表里的人数是累计观看；直播中连上弹幕后，显示的是正在观看的人数。”，因为弹幕报的是正在观看人数。3.x 原文没有测试或迁移用到（E06 平台层升级 改公告时就只在注释里留了原文），所以不加 `legacyChatNotice`。
  - `audience.dart` 的京东直播一项改为 `roomRealtime`（见“在线人数”）。
- 升级条目：28-6“聊天（弹幕）”。v3 没有京东直播聊天（`EmptyDanmaku`），这是新增功能，没有 v3 行为可对照。
- 样本（都是本模块录制，`fixtures/jdlive/danmaku/`）：
  - `S06-live`：场次 48399381，2026-09-28 22:57 UTC 起录 45 分钟（1898 帧），留下开头、商品卡片和一位观众进房、自动回复、发言、主播回答的一段，共 44 帧，见“样本”；
  - `S07-ended`：场次 48431089，2026-09-30 12:07 UTC 起录，第 380 s 直播结束（`stop_live_broadcast`），180 s 后服务端断开，留下 22 帧和断开；
  - 两个 `expected.json` 由 `danmaku/web_expected.mjs` 生成（网页脚本的逻辑，见“与网页脚本的对照”）。
- 参考（规格来源）：
  - 归档 v4：京东直播没有弹幕（`spec/sites/jdlive.md` §7“不做（旧版未接入；评论走京东私有长连接，[待确认]）”），`packages/live_danmaku/lib/src/sites/` 下没有 jdlive；
  - pure_live_TV `e1cca224`：`lib/platforms/jdlive/jd_live_site.dart:41` 仍是 `EmptyDanmaku`；
  - 所以规格来自官网直播页的脚本（2026-09-29 下载的 `storage.360buyimg.com/live-common/prod/jd-live/js/app-c714bc7b.340fdd69.js`、`app-748942c6.4db2bcd3.js`、`live-f71cff67.44dc43c4.js`，见“网页脚本”）和录下的真实帧，两者矛盾时以帧为准；
  - E02.9 留下的线索（`liveauth` 不要 h5st、内容用脚本里固定的 appId、密钥和 IV 加密、`liveUrl?token=` 是 socket 地址）全部核实；
  - 2026-09-28 22:53～23:42 UTC 和 2026-09-30 12:03～12:50 UTC 的只读实测（匿名、直连、不登录、不发言、socket 上什么都不发），见“实测”。

## 做法

- **建在 D01.1 的 WebSocket 运行时上**（`DanmakuSocketConnection`），平台代码只写：
  - `target`：检查参数，给出名义地址和握手请求头；
  - `onOpen`：打开即加入（`session.ready()`），不发加入帧；
  - `onData`：解一帧；遇到 `stop_live_broadcast` 以 `DanmakuClosed(connectionFailed, 'Broadcast ended')` 结束；
  - 不发心跳帧（`heartbeatFrame` 用默认的 null）。
  - 换地址、退避、最多 8 次、无消息检测、停止后不再有事件，都由框架和 `LiveSocket` 负责。框架没有改。
- **每次握手前都先 POST `liveauth` 取新令牌**（同 D01.12 TwitCasting 的做法：`connector` 参数本来就允许替换握手）：
  - 令牌只能开一个 socket（实测：同一个令牌第二次握手回 HTTP 200、不升级），`LiveSocket` 重连时却总用同一个地址；
  - 所以交给 `LiveSocket` 的是名义地址 `https://api.m.jd.com/api?functionId=liveauth&groupId=<场次号>`，本平台的握手函数先 POST 取 `liveUrl` 和 `token`，再用 `<liveUrl>?token=<token>` 握手，和网页出错后重新调用 `liveauth` 一样；
  - 请求失败（网络错误、状态码不是 2xx、回答看不懂、`code` 不是 0、没有地址或令牌）当作这次握手失败，走框架的退避和 8 次上限；
  - 一次 `connect` 里的请求绑定一个 `CancelToken`，`close` 或换房间时取消；超时同握手（10 s）。
- **开始时不另发请求**：第一次握手的那次 POST 就是开始的请求（网页也是进房后调用一次），进房详情已经给了场次号。
- **socket 上什么都不发**。网页打开后会发一个 `join_live_broadcast`（随机的“用户”加 7 位数字作昵称），它只是让房间里出现“xx来了”，不发也照样收到整个房间的推送（实测 45 分钟），而且不发时本客户端不算进 `current_viewer`（见“在线人数”）。所以不发，这也是只读的做法。
- **上报**：
  - 聊天：`viewer_send_message`（观众）和 `anchor_send_message`（主播，名字写成网页显示的“主播”），就是网页聊天区显示的两种；
  - 在线人数：`get_statistics_result` 的 `current_viewer`（正在观看）和 `total_viwer`（累计观看，等于列表的 `pv`）；
  - 其余（点赞、进房提示、主播对单个观众的回复、购买和加购提示、商品卡片、购物袋刷新、优惠券、关注）都不报；平台没有醒目留言和付费留言。
- **失败详情不带令牌**：`dart:io` 握手失败的文字里有整个地址，本平台把 `token` 的值换成 `…`。

## 协议

`liveauth`：

| 项目 | 内容 |
|---|---|
| 请求 | `POST https://api.m.jd.com/api`，表单（按网页的顺序）`loginType=2`、`appid=h5-live`、`functionId=liveauth`、`body=<JSON>`、`t=<毫秒>`；请求头是平台层的 `JdLiveApi.apiHeaders`（iOS Safari UA、`Accept`、`Origin`、`Referer: https://lives.jd.com/`）加 `Content-Type: application/x-www-form-urlencoded`（网页的 axios 不带 charset），以 `jdlive` 的名义发出（走本平台的代理设置），不跟随跳转。不要 h5st 签名 |
| `body` | `{"appId":"jd.mall","content":"<Base64>"}` |
| `content` 明文 | 按网页的键顺序：`{"appId":"jd.mall","secretKey":"RYm2dMPMWD9AxYFk","groupId":"<场次号>","clientType":"m","timestamp":<毫秒>,"origin":-100,"encryptPin":true,"random":"<6 位数字>"}`。网页另有 `pin`（登录用户，匿名时为 undefined，`JSON.stringify` 会去掉）和 `eid`（风控指纹，要另一个脚本给，拿不到时同样去掉）；`origin` 取链接里的 `origin`，没有时 -100 |
| 加密 | AES-128-CBC，密钥是 `secretKey` 的 UTF-8，IV 是 `0102030405060708` 的 UTF-8，PKCS#7 填充，Base64（网页用 aes-js，本实现用 `live_core` 的 `AesCbc`） |
| 回答 | `{"code":0,"msg":"鉴权成功","data":{"liveUrl":"wss://live-ws4.jd.com","quicUrl":false,"secretPin":"<Base64>","token":"<令牌>"}}`。令牌是 `jd.mall_游客_<游客编号>_<毫秒时刻和随机数>` 的 Base64（URL 安全字母表），每次不同；`secretPin` 是这个游客加密后的 pin，网页用它过滤自己发的话。游客的回答里没有 `msgMaskKey` |
| 本实现接受的回答 | `code` 是数字 0；`liveUrl` 是 `wss`、主机是 `jd.com` 或它的子域名、没有查询、片段和用户信息；`token` 是不含空白、`&`、`#` 的非空文字。socket 地址照网页直接拼成 `<liveUrl>?token=<token>`（不重新编码，令牌末尾的 `=` 原样保留）。`msgMaskKey` 是非空文字时记下 |
| 拒绝 | 内容解不开：`{"code":1,"msg":"鉴权失败","data":{"error":"解密失败!"}}`；没有内容：`"error":"参数解析错误"`（都是 HTTP 200，实测） |
| 场次号 | 服务端不检查：`0`、`abc`、`99999999999`、已结束的场次都给令牌（实测） |

socket：

| 项目 | 内容 |
|---|---|
| 握手 | `wss://live-ws4.jd.com?token=<令牌>`，请求头 `Origin: https://lives.jd.com` 和平台层的 UA（`dart:io` 会把自己的 UA 拼在前面，实测照样接受）。不带这两个请求头也能连（实测）；不需要保留大小写，用默认的 `dart:io` 握手，不用 `connectExactWebSocket` |
| 令牌 | 只能用一次：同一个令牌第二次握手、37 小时前的令牌握手，都回 HTTP 200、不升级（`dart:io`：`was not upgraded to websocket, HTTP status code: 200`） |
| 加入 | 打开即收到房间的推送，客户端不发任何消息 |
| 下行 | 文本帧，每帧一个 JSON 对象。网页也处理二进制帧：先用 `msgMaskKey` 的每个字符（取低 8 位，循环）异或，再按 UTF-8 解（`decodeURIComponent`）；游客没有掩码，录制和实测里也没有二进制帧。本实现照网页处理，掩码按这次握手的 `liveauth` 回答 |
| 在播时 | 多数房间服务端约每 3.5 s 推一次 `get_statistics_result`，紧跟一个 `thumbs_up`（约 32 个房间·小时里，统计最长间隔 6.8 s）；也有房间一直不推统计（48362752：30 分钟里只有商品、购物袋、自动回复等 266 帧，最长间隔 119 s）。直播中服务端从没断开 |
| 结束后 | 推 `stop_live_broadcast`，之后几秒里可能还有几帧商品消息，然后什么都不推；4 次结束里 3 次在最后一帧 180 s 后被服务端直接断开（1006，没有关闭帧），1 次在结束帧 19 s 后断开（1005）。已结束的场次也能拿到令牌、握手，但一帧都没有，180 s 后同样被断开 |
| 空闲断开 | 服务端对 180 s 没有推送的 socket 直接断开（上面 3 次在最后一帧 180 s 后，一帧都没有的那个 socket 在打开 180 s 后）；在播的房间里推送间隔都在这以内 |

消息（顶层 `type`，`chat_group_message` 再看 `body.type`）：

| 类型 | 字段 | 本实现 | 网页 |
|---|---|---|---|
| `get_statistics_result` | `body`：`current_viewer`、`total_viwer`（原文如此）、`pv`、`max_viewer`、`message_num`、`thumbs_up_num`、`cart_num`，都是数字文字 | 两条在线人数：`current_viewer` 是 `onlineViewers`，`total_viwer` 是 `totalViewers`；数字或它的文字、不小于 0，否则那一条不报 | 只用 `total_viwer`，显示成观看数 |
| `viewer_send_message` | `datetime`（毫秒）、`id`（uuid）、`from {app, pinmd5, secretPin, clientType}`、`body {nickName, content, groupid, plus, userMemberLevel, loveLevel, extraTag, ext, msgStrategy, …}` | 白色聊天（见下） | 聊天区：`昵称: 内容` |
| `anchor_send_message` | 同上，`body` 只有 `content`、`groupid`、`needAck`（主播手打的话，和自动的“正在讲解 N 号宝贝”） | 白色聊天，名字“主播” | 聊天区：`主播: 内容` |
| `stop_live_broadcast` | `body {close_mode, groupid, needAck}` | 结束连接（`connectionFailed`，`Broadcast ended`） | 页面转成已结束 |
| `thumbs_up`、`join_live_broadcast_summary`（“xx来了”）、`viewer_buy_product_summary`、`viewer_get_coupon`、`viewer_add_product_to_cart` | — | 不报 | 屏幕上方的飘条，不进聊天区 |
| `anchor_public_reply`、`live_common_reply` | 主播（多是自动）对某一位观众的回复，`broadcast: false`，带被回复的昵称和账号 | 不报 | 不显示 |
| `new_anchor_cart_number`、`anchor_new_popup_product`、`jdlive_refresh_cart`、`anchor_new_explain_product_over`、`server_add_product_type`、`anchor_send_exclusive_coupon`、`user_places_order`、`pay_attention_to_anchor`、`anchor_send_notice`、`clean_chat_view`、`suspend_live_broadcast`、`resume_live_broadcast` 和未知类型 | 购物袋、商品卡片、讲解、下单、优惠券、关注、公告、清屏、暂停和恢复 | 不报 | 更新购物袋、公告、清屏等 |

聊天解成白色聊天：

- 文字是 `body.content` 去首尾空白，空白或不是文字时不报；
- 名字：观众是 `body.nickName`（去首尾空白，不是文字时留空），主播是 `JdLiveDanmakuProtocol.anchorName`（“主播”，网页的写法，主播消息本身不带名字）；
- 用户 id 是 `from.pinmd5`（账号的摘要；网页从不显示账号）；消息 id 是 `id`；时间是 `datetime`（毫秒），不大于 0、不是整数或超出 `DateTime` 范围时为空；
- `plus`（PLUS 会员）、`userMemberLevel`、`loveLevel`、`extraTag`、`ext`、`msgStrategy` 不读。

帧的解法：不是 JSON 对象（数组、`null`、坏 JSON）丢掉；`body` 不是对象丢掉；`body.groupid`（数字或文字）不是本场次的丢掉，没有 `groupid` 的算本场次（这个 socket 只有一个群组）；二进制帧按上面的掩码规则解，不是 UTF-8 就丢掉。

## 在线人数

- `current_viewer` 随观众进出变化：`S06-live` 里一直是 0（本客户端连着也是 0：不发加入帧就不算），一位观众从 Android App 进房（`join_live_broadcast_summary`）后变成 1，他离开后回到 0；`max_viewer` 是本场的最高值。所以它是“正在观看”的人数，按 `onlineViewers` 上报。京东直播的在线人数很少：两次录制的约 3.1 万个统计里，`current_viewer` 是 0（1.05 万）、1（1.95 万）、2（1246）、3（33），没有更大的。
- `total_viwer` 与列表卡片的 `pv` 相同（例如 48399465：列表 1876，统计 1876），就是平台层的累计观看，按 `totalViewers` 上报。统计里另一个 `pv` 比它小，含义没有查明，不读。
- 统计不是每个直播间都有（见“实测”），没有统计的房间就没有人数更新。
- 所以接入后，在线人数的来源从“没有”变为“直播间里的实时消息”：`audience.dart` 的 `jdlive` 改为 `onlineAvailability: roomRealtime`（`hasTotalViewers` 仍为 true，`hasPopularity` 仍为 false），注释写明来源。列表和进房的人数仍只有累计观看。

## 连接和时序

| 项目 | 本实现 | 网页脚本 | 依据 |
|---|---|---|---|
| 取令牌的时机 | 每次握手前（第一次和每次重连） | 进房时一次；socket 出错时重新调用 | 令牌只能用一次（实测） |
| 取令牌的请求 | 表单同网页；`content` 没有 `pin`、`eid` | 同；登录时有 `pin`，拿到风控指纹时有 `eid` | 不带也给令牌（实测） |
| 取令牌失败 | 当作一次握手失败，按退避重试 | 2 s 后再调用，不限次数 | 框架的统一做法；差异 2 |
| 握手请求头 | `Origin`、平台层的 UA | 浏览器 | 实测不带也能连 |
| 加入 | 打开即就绪，不发任何帧（每次重连都报一次 `DanmakuReady`） | 打开后发 `join_live_broadcast`（随机昵称） | 差异 1 |
| 心跳 | 不发。`heartbeatInterval` 20 s 只是无消息检测的节拍，手动 `heartbeat()` 什么也不发 | 不发 | 客户端发不发都不影响推送 |
| 无消息超时 | 200 s（20 s 检查一次，所以 200～220 s 内发现），比服务端的空闲断开（180 s）长：正常的连接空闲 180 s 就被服务端断开、按普通断线重连，这个检测只抓服务端的断开没有送到的半开连接 | 没有 | 差异 3 |
| 加入超时 | 无 | 无 | 打开即加入 |
| 断线重连 | 框架默认：只有一个名义地址，间隔 2、3、4、5、6、6、6、6 s，最多 8 次，收到任何帧清零，一轮只提示一次；每次都重新取令牌 | 出错（`onerror`）时关掉、重新取令牌再连；正常关闭（`onclose`）时什么也不做 | 框架的统一做法 |
| 直播结束 | 收到 `stop_live_broadcast` 就以 `connectionFailed`（`Broadcast ended`）结束，之后的帧不报 | 页面转成已结束，socket 留着直到服务端断开 | 差异 4 |
| 重连后的补漏 | 不补；靠消息 id 去重（D01.1 的闸门，10 分钟） | 不补 | 平台没有补拉的接口 |
| 参数不对 | 场次号不是 5～18 位、不以 0 开头的数字（平台层的 `JdLiveApi.isLiveId`，先去首尾空白）：`DanmakuClosed(connectionFailed, 'No broadcast')`，不发请求 | — | — |

## 网页脚本

与聊天有关的部分（2026-09-29 的版本，压缩后的名字不固定，按作用描述）：

- 配置（`app-c714bc7b` 的模块 `cf45` 引用的常量）：`{appId:"jd.mall",secretKey:"RYm2dMPMWD9AxYFk",pyl:"0102030405060708"}`；加密函数用 aes-js 的 CBC，密钥默认是 `secretKey`，IV 是 `pyl`，PKCS#7，结果转成 Base64。
- 连接（模块 `b2eb`）：先取风控指纹（`window.getJdEid()`，取不到时为空），拼出 `content` 的明文，调用 `liveauth`（`app-748942c6` 里的请求函数：POST、`appid: h5-live`、`body: JSON.stringify({appId, content})`、`t`；公共请求函数把 `loginType`（浏览器里是 2）放在最前面，表单编码）。回答 `code === 0` 且有 `data` 时记下 `msgMaskKey` 和 `secretPin`，打开 `new WebSocket(liveUrl + "?token=" + token)`；否则 2 s 后重来。
- 打开后发 `{"aid":"dongdong","ver":"1.0.0","from":{"app":"jd.live","pin":…,"clientType":"m","dvc":<__jda Cookie 的第二段>},"groupid":<场次号>,"type":"chat_group_message","id":<毫秒>,"body":{"type":"join_live_broadcast","nickName":<昵称或“用户”加 7 位随机数字>,…}}`。
- 收到消息：`Blob` 先按掩码异或、`decodeURIComponent`，再 `JSON.parse`，交给页面的状态（`pushMessage`）：`get_statistics_result` 更新观看数（`total_viwer`），`anchor_send_notice` 更新公告，`clean_chat_view` 清屏，`stop_live_broadcast` 把直播状态改为已结束，`anchor_cart_number` 更新购物袋数。
- 聊天区（`live-f71cff67`）只收 `viewer_send_message`、`anchor_send_message`，跳过 `from.secretPin` 等于自己的那条（自己发的话本地先显示了），主播的名字写“主播”；飘条收进房、购买、领券、加购的提示。
- 出错时关掉 socket 重新走一遍 `liveauth`；关闭时什么也不做；没有心跳和无消息检测。

## 登记方式

应用（I01.1）建平台表时：

```dart
DanmakuRegistry({
  SiteIds.jdLive: () => JdLiveDanmakuConnection(http: jdLiveHttp, proxy: proxyPolicy),
  // …
});
```

- `http`：应用给 `JdLiveSite` 的同一个 `LiveHttp`。`liveauth` 以 `jdlive` 的名义发出，代理和限流按平台 id。
- `proxy`：应用的 `ProxyPolicy`（`live_net`），按平台 `jdlive` 选 socket 的路由，和接口请求用同一份设置。
- 不需要 Cookie 和账号：全程是游客，v3 也没有京东直播的登录。
- `connector`、`policy`、`now`、`random` 只给测试用，应用不传。默认握手是 `dart:io`，不需要 `connectExactWebSocket`。
- 参数来自 `getRoomDetail`（和录制详情）；其余情况没有参数，按 D01.1 不连接。

## 与网页脚本的对照

- 没有 v3、归档 v4 或上游的实现，期望值由网页脚本本身的逻辑生成：`fixtures/jdlive/danmaku/web_expected.mjs` 把网页里的加密函数、`liveauth` 回答的处理、socket 的消息处理（含掩码）、状态里的 `pushMessage` 和聊天区的筛选逐个改写成 Node 函数（每个上面引了压缩后的原文，只把 aes-js 换成 Node 自带的 `crypto`，同样是 AES-128-CBC 和 PKCS#7），读录下的 `liveauth` 请求、回答和每个收到的帧，写下 `content` 的密文、socket 地址、掩码，以及每帧聊天区新增的行（种类、名字、内容）、页面记下的观看数、是否结束。运行：在仓库根目录 `node fixtures/jdlive/danmaku/web_expected.mjs`（Node 18 以上，不用装包），结果在两个样本的 `expected.json`，`generator` 字段写明来源。
- 测试用同一份录制跑新代码：

| 对照 | 结果 |
|---|---|
| `S06-live` 的 `liveauth` 请求 | 用录下明文里的时刻和随机数，本实现拼出的表单与录制逐项相同；`content` 的密文与网页的加密相同 |
| `S06-live` 的 `liveauth` 回答 | 读出的 socket 地址与网页相同，也等于 `meta.json` 记下的握手地址；没有掩码 |
| `S06-live` 的 44 帧、`S07-ended` 的 22 帧 | 逐帧一致：聊天区的 2 行（观众“多重”、主播的回答，名字和内容）、15 + 6 个观看数（`total_viwer`）、`S07-ended` 第 21 行的结束；其余帧两边都没有东西 |
| 网页不看的部分（手工核对） | 观众消息的用户 id 是 `from.pinmd5`、消息 id、时间；`current_viewer` 在每个统计帧上报一次，`S06-live` 里是 0 和 1 |
| 用连接重放 `S06-live` | 1 次 POST、1 个 socket、就绪 1 次，消息按顺序上报（与逐帧解码相同），客户端没有发过任何帧 |
| 用连接重放 `S07-ended` | 结束帧之前的消息照报，结束帧上以 `connectionFailed`（`Broadcast ended`）结束、关掉 socket，之后的 3 帧和服务端的断开都不再上报，也不重连 |

## 与网页的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 不发 `join_live_broadcast` | 只读：它只让房间里出现一个假的“用户xxxxxxx来了”，并把本客户端算进 `current_viewer`；不发也收到全部推送（实测 45 分钟、8 个房间） |
| 2 | `liveauth` 失败按框架退避重试，最多 8 次 | 框架的统一做法；网页每 2 s 无限重试。拒绝（`code` 不是 0）也重试：内容解不开这种一直失败的情况 8 次后结束，详情里有拒绝的原因（`liveauth refused: 1 鉴权失败 (解密失败!)`），偶发的失败能恢复 |
| 3 | 200 s 没有任何帧就换 socket | 网页发现不了半开的连接。不能再短：有的直播间不推统计，推送间隔到过 119 s，短了会在正常的安静房间里反复重连；服务端自己在 180 s 没有推送时断开，所以正常的连接到不了 200 s |
| 4 | `stop_live_broadcast` 结束连接 | 这一场不会再有聊天（新开播是新的场次号，要重新进房）；不结束的话，服务端 19～180 s 后断开，之后每次重连都拿到令牌、打开、180 s 后又被断开，要 8 轮（约半小时）才以“重连超过最大次数”结束 |
| 5 | 不过滤自己的消息 | 本客户端不发言，`secretPin` 用不到 |
| 6 | 聊天文字、名字去首尾空白，空白的不报 | 与其他平台一致；网页原样显示 |
| 7 | `content` 不带 `pin`、`eid` | 没有账号；`eid` 要执行京东的风控脚本才有，服务端不要求（实测） |
| 8 | 检查 `groupid` | 防止串到别的场次（网页不查）；录制和实测里都与场次号相同 |
| 9 | 在线人数多报 `current_viewer` | 网页只显示累计观看；`current_viewer` 是正在观看的人数，按 `audience.dart` 的约定上报 |

## 实测

2026-09-28 22:53～23:42 UTC（北京时间 29 日 06:53～07:42）和 2026-09-30 12:03～12:50 UTC（北京时间 20:03～20:50），只读、匿名、直连，没有登录，没有发言，socket 上什么都没发。

- **`liveauth`**：游客直接给令牌（“鉴权成功”），`liveUrl` 都是 `wss://live-ws4.jd.com`，没有 `msgMaskKey`；场次号 `0`、`abc`、`99999999999` 和已结束的场次也给；内容用错的密钥加密回“解密失败!”，没有内容回“参数解析错误”。
- **令牌**：用过一次再握手、37 小时前的令牌握手，都回 HTTP 200、不升级；新令牌不带 `Origin` 和 UA 也能握手。
- **推送**：第一次早上 8 个房间各连 45 分钟、晚上推荐里累计观看最多的 40 个房间各连 40 分钟，共约 7.3 万帧，全是文本 JSON：统计和点赞约每 3.5 s 各一个，其余是商品、购物袋、进房、自动回复等。服务端从没在直播中断开。观众发言非常少：早上 8 个房间 45 分钟里只有 1 条（`S06-live` 里那条），晚上 40 个房间 40 分钟里 3 条（“有优惠券吗”“幼儿园小班推荐哪个”“可以送优惠卷嘛”），主播消息 53 条（多是自动的“正在讲解 N 号宝贝”，也有带观众昵称开头的回答）。
- **结束**：晚上 40 个房间里有 4 场在录制中结束。48431089 在第 380 s 推了 `stop_live_broadcast`，之后 5 s 里还有 3 帧商品消息，然后没有任何推送，最后一帧 180 s 后服务端断开（1006）；另外两场同样是 180 s 后 1006，一场在结束帧 19 s 后 1005。一个已经结束、仍在推荐里的场次，握手成功后一帧都没有，180 s 后同样被断开。
- **不推统计的直播间**：48362752 直播中 30 分钟里没有一个统计和点赞，只有 266 帧商品、购物袋、下单、自动回复和主播消息，最长间隔 119 s；socket 一直没断，直到直播结束。所以无消息检测不能按统计的间隔定（差异 3）。
- **本实现**：`JdLiveSite.getRecommendRooms` 取推荐，进累计观看最多的房间（48435909，`getRoomDetail` 给出参数），用默认的 `dart:io` 握手和默认时序连接：434 ms 就绪（POST 加握手），120 s 里收到 34 次统计（每次两条人数：正在观看 1、累计 738），没有重连；这段时间没有人发言。

## 样本

- `S06-live`（`frames.jsonl` 46 行）：`liveauth` 的请求（明文 `content` 和发出的表单）、回答，44 个收到的帧（录制的第 0～11、46～59、1183～1200 帧）：15 个统计、15 个点赞、2 个购物袋数、4 个商品卡片、3 个购物袋刷新、1 个进房、1 对自动回复、1 条观众发言、1 条主播回答。`meta.json` 记下请求头、回答的状态和响应头、握手、保留的帧、原始录制的 SHA-256 和长度、脱敏记录。
- `S07-ended`（25 行）：`liveauth` 的请求和回答，22 个帧（第 0～3、240～257 帧：开头的统计，结束前的统计、商品消息、结束帧和其后的 3 帧），以及第 258 行服务端的断开（1006）。
- 脱敏（按字段逐个检查了两份录制的每一种消息，`scrub.py` 另外检查替换后的文件里找不到任何原值）：
  - `from.pinmd5`（账号摘要，包括平台系统账号）、`from.secretPin`、`body.joinUser`（加密的 pin）换成同形同长度的合成值（十六进制换十六进制，Base64 换同样长度的 Base64），同一个原值总是换成同一个合成值，所以“同一个人”的关系还在（例如进房提示的 `joinUser` 等于这位观众发言的 `secretPin`）；
  - `body.nickName`、`reNickName`、`pin`、`rePin`（昵称和账号名，店铺子账号的名字里有手机号），以及进房提示文字里的昵称，按字符类别换成同长度的合成值；
  - 自动回复里的 `anchorAvatarUrl`（回复图标的路径）换成同形的合成路径；
  - `liveauth` 回答的 `secretPin`、令牌里的游客编号（令牌里的时刻和随机部分保留，所以长度和编码不变）、握手地址里的令牌、响应头 `x-rp-sdtoken` 换成合成值；
  - 保留：消息 id、时间、聊天文字、商品卡片（商品图、价格、京东云视频地址，都是店铺公开内容）、统计、`x-api-request-id`（单次请求的追踪号，同 E02.9）；`liveauth` 的明文 `content` 只有场次号、时刻和随机数。
  - 请求没有 Cookie，回答没有 Set-Cookie；没有 IPv4 地址。门禁的 `fixture privacy` 通过。
- 录制和脱敏用的 `record.dart`、`scrub.py` 没有放进仓库（同 D01.17），`meta.json` 的 `tool` 写明。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 登记到 `DanmakuRegistry` | I01.1（见“登记方式”） |
| 关闭、重连原因的界面文字；`connectionFailed` 的说明 `No broadcast`、`Broadcast ended` | M13（D01.1 的原因表） |
| 房间公告 `jdlive_chat_notice` 的翻译 | 公告已在平台层改好（只说明人数），翻译在 M13。弹幕报来的正在观看人数和公告说的累计观看不是一回事：M13 显示弹幕的人数时，公告要么只在显示累计观看时出现，要么改写成两者都说明 |
| 直播结束后的界面 | M13：弹幕连接以 `Broadcast ended` 结束时可以提示直播已结束，或刷新房间详情 |
| 仅限 App 的场次的聊天 | 以后见到 `secret` 为 1 的场次时再核实能不能连，能连就在 `JdLiveApi.room` 里放开 |
| 显示进房、购买提示（网页的飘条）或主播公告 | M13 决定是否要；要用时在协议层加事件（`join_live_broadcast_summary` 等，`anchor_send_notice`） |
| 发言 | 不做：要登录（`pin`），本应用没有京东账号 |
| `live_core` 的 `LiveDanmaku`、`JdLiveSite` 的 `EmptyDanmaku` | D01 各平台完成后删除 |

## 受阻

没有。`liveauth` 不要 h5st 签名，也不要登录：游客令牌是网页自己用的匿名入口，内容的加密常量就写在网页脚本里。

## 测试

- `packages/live_danmaku/test/sites/jdlive_test.dart` 33 个用例，`live_danmaku` 共 996 个，连续跑 3 次全部通过：
  - 协议 12 个：`content` 的明文和加密（用 `Aes128Cbc` 解回）；随机数；请求（方法、地址、表单的顺序和字段、请求头、不跟随跳转、超时、取消、以平台名义）；回答（地址、掩码、主机大小写）；不能用的回答（状态码、非 JSON、数组、拒绝、`code` 是文字、缺 `data`，`liveUrl` 的 `ws`/`https`/冒充主机/查询/片段/用户信息，令牌缺失、空白、带空格、`&`、`#`）；名义地址和场次号的往返；令牌的去除；观众消息的各字段；主播消息；聊天的边界（空白和非文字、名字、用户、id、时间的 0、负数、上限和越界）；人数（数字和文字、负数、小数、非数字）；帧（其他 14 种消息、别的群组、数字和文字的群组、坏 JSON、数组、字节、掩码、错误的掩码、非 UTF-8、结束帧）。
  - 录制 6 个：`S06-live` 的请求和回答与网页一致；两份录制逐帧与网页的读法一致；`S06-live` 手工核对的字段和在线人数；用连接重放 `S06-live`；用连接重放 `S07-ended`（结束后不再上报、不重连；录制里服务端 180 s 后断开）。
  - 连接 15 个：默认时序和平台表登记；握手（先 POST、注入的时刻和随机数、令牌地址、请求头、代理路由、打开即就绪、聊天和人数）；不论节拍还是手动心跳都不发任何帧；断线后重新取令牌再连；`liveauth` 失败（网络、403、拒绝）按握手失败重试后加入；socket 握手失败（用过的令牌）也重新取令牌；连续失败用尽后 `reconnectsExhausted` 且详情里没有令牌；连续拒绝同样结束、详情有原因；无消息的检测（按比例缩短：有统计时不换，没有时换新令牌）；结束帧结束连接、别的群组的结束帧不算；掩码按每个 socket 自己的回答；参数不对直接结束、不发请求；POST 进行中关闭会取消请求；关闭后没有事件、再次 `connect` 换场次；真实的本地服务器（`IoLiveHttp` 的表单 POST、默认的 `dart:io` 握手、令牌、`Origin` 和 UA、统计和聊天）。
- `live_core`：`jdlive_api_test.dart` 加 2 个（进房的参数：直播中有，刷新、仅限 App、已结束、回放、暂停、预告没有，没有地址的直播中也有；公告和 `audience.dart`），`jdlive_site_test.dart` 在三种深度的对照里断言参数（进房和录制有、刷新没有，请求数不变）。本平台共 59 个，`live_core` 共 3523 个。
- 门禁 `--all` 通过；`tools/timeshift/run.sh 30 1825` 全部 ok（测试里的时间都来自样本或固定值，本实现不拿样本时间和当前时间比较）。
- 整包并发跑 `live_danmaku` 时，YouTube 的“本地 HTTP 服务器”用例偶尔超时失败（4 次里 1 次，单独跑都通过），与本模块无关。
