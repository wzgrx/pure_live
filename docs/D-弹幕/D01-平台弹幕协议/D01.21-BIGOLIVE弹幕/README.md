# D01.21 BIGO LIVE 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 24-3“聊天（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有 BIGO 的聊天，这是新增功能，没有可对照的实现
- 旧编号：M5.20、T06a.21
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；同样在握手前插请求的 [D01.22 PandaTV](../D01.22-PandaTV弹幕/README.md)；平台本身、`BigoDanmakuArgs` 和公告 [E03.11 记录](../../../E-直播平台/E03-海外平台/E03.11-BIGOLIVE/record.md)；详细记录 [record.md](record.md)

## 目标

BIGO LIVE（海外秀场直播）直播间能看到评论和实时在线人数。协议照官网 `www.bigo.tv` 的网页脚本（`14.37bf41.js` 模块 931 等）从零写：文本帧（事件号 + JSON），游客账号由平台匿名发放，没有私有签名（质询的 MD5 写法是网页公开的，服务端也不校验）。

## 协议要点

| 项 | 内容 |
|---|---|
| 游客账号 | 一次连接的第一次握手前 `POST https://ta.bigo.tv/official_website/studio/getWebSocketLink`（表单 `deviceId=web_<32 位十六进制>_<6 位>_<毫秒>`，设备号用随机数生成），得到 `userId`、`uidToken`；重连接着用，被拒或加入超时后丢掉重取 |
| 地址 | `wss://wss.bigolive.tv/live/official/web`；请求头 `Origin: https://www.bigo.tv`、`User-Agent: Mozilla/5.0`；默认 `dart:io` 握手；按平台 `bigo` 走代理 |
| 帧 | 文本：十进制事件号（`toUri("a|b") = a << 8 | b`）+ JSON；服务端在中间加制表符 |
| 握手顺序 | 服务端先发质询 `256` → 回答 `79108`（`sign = MD5("60#4#5#<秒>#1#1#1#1#" + 质询后 8 字)`）→ 1 s 后登录 `512279` → 登录回答 `512535` 的 `res` 为 "200" → 进房 `1304` → 进房回答 `1560` 的 `resCode` "200" 且 `sid` 不是 "0" 才就绪 → 请求观众数 `10776` |
| 心跳 | 登录发出后每 10 s 发 `791` ping；无消息 90 s 换连接；加入超时 10 s |
| 被拒 | 登录、进房被拒、`unsigned`、加入超时：换账号重连，连续第 4 次以 `connectionFailed`（`Chat refused: …`）结束；进房回答 `sid` "0"（下播或不存在）：`connectionFailed`（`No broadcast in room <号>`） |
| 消息 | `2584`（`oriUri` 2060425）的 `payload.tag` 1 评论、2 付费弹幕 → 白色聊天（`content` 是 Base64 的 JSON：`n` 名字、`m` 文字；`payload.uid`、`grade` 等级；id `<用户 id>:<seqId>`，挡掉服务端的原样重发）；`10264`（`NUMS`）的 `totalUserCount`、`11032` 的 `total` → 在线人数；礼物、爱心、关注、入场、热度、房间状态 `3608` 不报 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `BigoSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/bigo/bigo_site.dart:42`），提示一次“尚未接入” | `BigoDanmakuConnection`（`packages/live_danmaku/lib/src/sites/bigo.dart:446`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:228` | 有评论和人数（已做） |
| 协议 | 无 | `BigoDanmakuProtocol`（:96）：地址（:99）、账号接口（:102）、心跳和超时（:110～119）、`maxRefusals = 3`（:123）、事件号表（:129～159）；`BigoChatVisitor`（:17） | 客户端帧与网页写法逐字节相同 |
| 参数 | 无 | `live_core` 新加 `BigoDanmakuArgs(siteId, ownerId, roomId)`：进房和录制详情在播、不要求登录、不是密码房、`roomType` 不是 "1" 时带上，不多发请求 | — |
| 公告和人数 | 公告说看不到聊天；直播间回答没有人数 | 公告 `BigoApi.chatNotice` 去掉“看不到聊天”；弹幕连着时人数随 `NUMS` 更新（和列表同口径） | — |

## 结果

- **提交**：51ca7deda（2026-09-30，M5.20）。之后没有改动。
- **期望值**：没有可对照的实现，`fixtures/bigo/danmaku/web_expected.py` 按网页的读法一步步重写（不照抄网页代码），生成各样本的 `expected.json`。S05-live（`tikaa12`，63 s）收到的 58 帧逐帧一致：6 条评论、4 个人数；客户端帧逐字节相同。S06-idle（已下播的 `qashia305`）进房回答 `sid` "0" 后结束；S07-unsigned 抢在质询前登录被拒后换账号再次加入。
- **实测**（2026-09-30 经本机代理，匿名）：质询 10～120 ms 到，登录 0.2～0.7 s 回答；故意写错签名也能登录；错误的令牌服务端不回答；同一游客账号能同时连两个 socket、62 分钟后还能登录；长连接在 24～27 分钟被 1006 断开（更像代理线路，原因不明）。本实现没有接真实服务器跑，帧写法与实测接受的逐字节相同。
- **样本隐私**：登录回答的 `clientIp` 是调用方地址的小端十进制写法，门禁看不到，换成文档地址 198.51.100.200 的同一写法（`3362010054`），另由测试守着。
- **测试**：`packages/live_danmaku/test/sites/bigo_test.dart` 27 个（协议 9、录制 6、连接 12）；`live_core` 的 BIGO 测试 +2。

## 验证

- 自动测试：`bigo_test.dart`（本地服务器端到端：握手路径、Origin、UA，回答、登录、进房、人数请求、ping 的顺序）。
- 真实接口：只有探测程序的实测，本实现没有直接连真实服务器。
- 真机：没有；海外平台要代理。真机上要留意长连接 24～27 分钟被断开是不是直连也会发生。

## 留下的问题

- 长连接定时断开的原因不明；若是服务端的固定时限，可以照 D01.22 在到期前悄悄换 socket，避免定时出现重连提示。
- 下播、暂离（`3608`）不报；关闭弹幕时进房后没有人数（直播间回答没有）。
- 付费弹幕按普通聊天显示（网页的横幅也没有金额）；礼物、爱心等不显示（礼物名要查 `getOnlineGifts`）。
- 密码房不连（应用没有输入房间密码的界面）。
