# D01.21 BIGO LIVE 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-30，提交 51ca7deda）
- 类型：平台
- 来源：已批准升级 24-3“聊天（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有 BIGO 这个平台但没有聊天，归档 v4、pure_live_TV 也都没有，这是新增功能，没有可对照的实现。附录 B 没有 BIGO 的后续条目
- 旧编号：M5.20、T06a.21
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；同样在握手前插请求的 [D01.22 PandaTV](../D01.22-PandaTV弹幕/README.md)；平台本身、`BigoDanmakuArgs` 和公告 [E03.11 记录](../../../E-直播平台/E03-海外平台/E03.11-BIGOLIVE/record.md)；下播后重连 B-24 在 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；握手的 User-Agent [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（本平台默认用 `dart:io` 握手）；决定 D-017；详细记录 [record.md](record.md)

## 目标

BIGO LIVE（海外秀场直播）直播间能看到评论和实时在线人数。协议照官网 `www.bigo.tv` 在 2026-09-30 加载的网页脚本（`14.37bf41.js` 模块 931、`97.929aaf.js`、`app.2a1a24.js`）从零写：文本帧（事件号 + JSON），游客账号由平台匿名发放，没有私有签名（回答质询的 MD5 写法是网页公开的，服务端也不校验）。归档规格 §7 说“私有的二进制 WebSocket、需要抓包”，实际不需要。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/bigo.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 参数 | `live_core` 新加的 `BigoDanmakuArgs(siteId, ownerId, roomId)`（`packages/live_core/lib/src/sites/bigo/bigo_api.dart:257`）：照网页播放器的 `startLive`、`startWs`、`handleNeedLogin`，在播、不要求登录、不是密码房、`roomType` 不是 "1"、有房间号时由 `BigoApi.danmakuArgs`（:713）给出，进房和录制详情带上，不多发请求；连接再检查一次（`checked` :231），不合规以 `connectionFailed`（`No usable room`）结束，不请求、不握手（`target` :496） |
| 游客账号 | 一次 `connect` 的第一次握手前（`_Handshake` :610 包住握手）`POST https://ta.bigo.tv/official_website/studio/getWebSocketLink`（`linkUrl` :102、`linkRequest` :186），表单 `deviceId=web_<32 位十六进制>_<6 位>_<毫秒>`（`deviceId` :176，用随机数生成，网页用浏览器指纹），回答的 `userId`、`uidToken`（`visitor` :201、`BigoChatVisitor` :17）；重连接着用，被拒或加入超时后丢掉，下一次握手再取；请求失败当作这次握手失败，走框架的退避 |
| 地址 | `wss://wss.bigolive.tv/live/official/web`（`endpoint` :99）；请求头 `origin: https://www.bigo.tv`、`user-agent: Mozilla/5.0`（`socketHeaders` :107）；默认 `dart:io` 握手；按平台 `bigo` 走代理（`apps/pure_live/lib/app/platforms.dart:228`） |
| 帧 | 文本：十进制事件号 + JSON 对象；事件号是网页的 `toUri("a|b") = a << 8 | b`（`uri` :126）；客户端直接相连，服务端在中间加制表符，读时取第一个 `{` 之前的部分（`decode` :301） |
| 握手顺序 | 打开后什么都不发（`onOpen` :512），服务端先发质询 `256`（:129）→ 回答 `79108`（:132，`answer` :242：`sign = MD5("60#4#5#<秒>#1#1#1#1#" + 质询的后 8 字)`）→ 1 s 后（`loginDelay` :119）登录 `512279`（:135，`login` :251）→ 登录回答 `512535`（:138）的 `res` 为 "200" → 进房 `1304`（:141，`enter` :274，不带密码）→ 进房回答 `1560`（:144）的 `resCode` "200" 且 `sid` 不是 "0" 才就绪 → 请求观众数 `10776`（:147，`users` :279），回答 `11032`（:150） |
| 心跳 | 登录发出以后才给 ping（`heartbeatFrame` :594）：每 10 s（`heartbeatInterval` :110）发 `791`（:159，`ping` :283），服务端一般 0.2 s 内回答；无消息 90 s 换连接；加入超时 10 s（`joinTimeout` :115，`onJoinTimeout` :583）；策略 `defaultPolicy` :479～482 |
| 被拒 | 登录被拒（`res` 不是 "200"）、进房被拒（`resCode` 不是 "200"）、抢在回答质询前登录的 `unsigned`、10 s 内没进房（错误的令牌服务端不回答）：丢掉账号、换账号重连（`_refused` :570）；连续第 4 次（`maxRefusals` :123）以 `connectionFailed`（`Chat refused: …`）结束；加入成功清零 |
| 没有这场直播 | 进房回答 `sid` 为 "0"（下播或不存在的房间，服务端也回 "200"）：`connectionFailed`（`No broadcast in room <号>`），不再重连 |
| 重连 | 框架默认：一个地址，间隔 2、3、4、5、6、6、6、6 s，连续 8 次失败以 `reconnectsExhausted` 结束，收到任何帧清零，一轮只提示一次 |
| 评论 | `2584`（`NORMAL_TEXT`，`textUri` :153），`room_id` 等于本房间、`oriUri` 2060425 的 `payload.tag` 是 1（评论）或 2（付费弹幕）（`chatTags` :163）→ 白色聊天（`chat` :362）：`payload.content` 按 Base64（缺补齐也接受）、UTF-8 严格解码、JSON 对象，任何一步失败就丢；文字 `m`、名字 `n` 去首尾空白；用户 id `payload.uid`（不是数字串时用 `from_uid`）；等级 `payload.grade`；消息 id `<用户 id>:<seqId>`（挡掉服务端原样重发的同一条）；没有时间（录到的 `timestamp` 都是 "0"） |
| 在线人数 | `10264`（`NUMS`，`audienceUri` :156）的 `totalUserCount`（看 `gid`）、`11032` 的 `total`（看 `room_id`）→ `onlineViewers`（`audience` :400）；1～20 位数字；下播房间的 `total` "0"、`room_id` "0" 不报 |
| 不报的 | `tag` 3、6、8、10、11（爱心、礼物、关注、分享、公告）和贴图、入场、服务端通知、排名；`oriUri` 2396297 热度、2062217 点赞数、礼物动画、豆子总数；`3608` 房间状态（结束、暂离、回来）；`10520` 连麦座位 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | 3.x 有 BIGO 这个平台但没有聊天：`BigoSite.getDanmaku() => EmptyDanmaku()`（`lib/core/site/bigo/bigo_site.dart:42`），直播间只提示一次 `remote_danmaku_not_integrated`（`lib/modules/live_play/controllers/danmaku_controller.dart:146～150`） | `BigoDanmakuConnection`（`bigo.dart:446`）继承 `DanmakuSocketConnection`；协议 `BigoDanmakuProtocol`（:96）；应用登记在 `apps/pure_live/lib/app/platforms.dart:228` | 有评论和人数（已做） |
| 公告 | `bigo_chat_notice`“Bigo Live 远端聊天尚待接入；目录 user_count 仅作为当前直播在线人数，房间详情缺值时保持未知。”（`assets/translations/zh.json:1891`） | `BigoApi.chatNotice`（`bigo_api.dart:342`）改成“列表里的人数是正在观看的人数；进入直播间后，人数随弹幕更新。”，去掉“看不到聊天” | 已做 |
| 人数 | 列表的 `user_count`；直播间回答没有人数 | `packages/live_core/lib/src/audience.dart:196～200` 仍是 `roomList`（只补了注释）；弹幕连着时人数随 `NUMS` 更新（和列表同口径） | 已做 |
| 参数 | 无 | `BigoDanmakuArgs`、`BigoApi.danmakuArgs`，`BigoApi.room(studio, danmaku: true)` 只在进房和录制详情带 | 已做 |

## 结果

- **提交**：51ca7deda（2026-09-30，首次实现）。之后 `bigo.dart` 只有文档路径的注释随文档改名改过（c613b73f9、9dfbb424d），协议没有改动。
- **期望值**：没有可对照的实现，`fixtures/bigo/danmaku/web_expected.py` 按网页的读法一步步重写（不照抄网页代码），生成各样本的 `expected.json`。S05-live（`tikaa12`，前 63 s）客户端 10 帧逐字节相同、收到的 58 帧逐帧一致：6 条评论、4 个人数；S06-idle（已下播的 `qashia305`）进房回答 `sid` "0" 后以 `connectionFailed` 结束；S07-unsigned 抢在质询前登录被拒，换账号、换 socket 后再次加入。平台层用 `S03-studio-live` 得到的参数正是 S06 用的房间。
- **与网页的差异**（record.md 9 条）：设备号用随机数；不带密码进房、密码房不连；`sid` "0" 时结束；被拒换账号、连续第 4 次结束、加入 10 s 超时；重连按框架退避；只报评论、付费弹幕和人数；付费弹幕按普通聊天；不处理 3608；关闭时不发 `close`、`7|24`。
- **样本**：`fixtures/bigo/danmaku/` 下 S05-live、S06-idle、S07-unsigned（2026-09-30 经代理录制）。登录回答的 `clientIp` 是调用方地址的小端十进制写法，门禁的 `fixture privacy` 看不到，换成文档地址 198.51.100.200 的同一写法（`3362010054`），另由测试守着。
- **测试**：`packages/live_danmaku/test/sites/bigo_test.dart` 现在 27 个用例（没有循环生成的，做完时同样 27 个）：协议 9、录制 6、连接 12；`live_core` 的 `bigo_api_test.dart`、`bigo_site_test.dart` 各 +1。

## 验证

- 自动测试：`bigo_test.dart`——协议 9 个（地址、请求头、时序和事件号、账号请求和回答、参数检查、五种客户端帧逐字节、控制帧、评论和人数的边界）、录制 6 个（三个样本的客户端帧和收到的帧、`clientIp` 只能是脱敏值、用连接重放 S05/S06/S07）、连接 12 个（先取账号再握手、登录等 1 s、登录后才 ping、进房后就绪并请求人数、断线用同一账号重连、三种被拒各换账号且第 4 次结束、加入超时、没有直播结束、账号请求失败按握手失败重试、关闭和换房间、本地服务器端到端：路径、`Origin`、UA，回答、登录、进房、人数请求、ping 的顺序）。所有写时间的帧用注入的 `now`，在 +30 天、+1 年、+5 年下运行都通过。
- 真实接口：2026-09-30（UTC 11:50～14:35）用只依赖 `dart:io` 和 `crypto` 的探测程序匿名经代理：质询 10～120 ms 到，登录 0.2～0.7 s 回答；故意写错签名也能登录；错误的令牌服务端不回答；同一游客账号能同时连两个 socket、62 分钟后还能登录；菲律宾房间 3 分钟 11 条评论，S05 的印尼房间 4 分钟 28 条；`NUMS` 2472～2513 对列表 2557；三次长连接分别在 1592 s、1432 s（两个同时）被 1006 断开。**本实现没有接真实服务器跑过**，帧的写法与实测时服务端接受的逐字节相同。没遇到：付费弹幕（`tag` 2）、房间状态 `3608`。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节没有 BIGO，海外平台要用户开代理；E03.11 的记录里也没有 K90 结果。登记表是“完成”，但本实现既没有连过真实服务器也没有真机结果，按 D-029 还算“没验证”。

## 留下的问题

- 本实现没有在真实服务器上跑过（只用录制回放和本地服务器）：没有单独的任务，建议下一次开代理做真机补验时（[S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类）进一个人多的在播直播间看评论和人数。
- 长连接在 24～27 分钟被 1006 断开（经代理实测，两个 socket 同一秒断开，更像代理线路），本实现按普通断线处理（同一账号重连，提示一次）。真机直连时要留意是否也会发生；若是服务端的固定时限，可以照 [D01.22](../D01.22-PandaTV弹幕/README.md) 在到期前悄悄换 socket：没有任务。
- 下播、暂离（`3608`）不报，下播要等下一次重连时进房回答 `sid` "0" 才结束；直播间的 60 s 详情刷新（C01.1，B-24）在弹幕结束后才重连：没有任务。
- 关闭弹幕时进房后没有人数（直播间回答没有人数），界面沿用不沿用列表卡片的人数归直播间（E03.11 已列）：没有任务。
- 付费弹幕按普通聊天显示（网页的横幅也没有金额，做不成醒目留言）；礼物、爱心、关注、分享不显示（礼物名要查网页的 `getOnlineGifts`），B-21 只显示已上报 `gift` 的平台：没有任务。
- 密码房不连（应用没有输入房间密码的界面，进房帧的 `secretKey` 填密码即可）：没有任务。
- 评论带等级 `grade`，4.x 长按面板不显示 `Lv.N`（3.x 显示）：所有带等级的平台都一样，没有任务，见 [D01.13](../D01.13-猫耳FM弹幕/README.md) 的同一条。
