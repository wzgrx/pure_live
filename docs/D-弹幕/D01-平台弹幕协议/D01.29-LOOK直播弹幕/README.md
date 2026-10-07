# D01.29 LOOK 直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 32-7“聊天（网易云信）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 LOOK 直播没有聊天（`EmptyDanmaku`），这是新增功能，规格来自官网脚本（打包了云信 Web SDK 5.0.1 和 socket.io 0.9.11）和录下的真实帧
- 旧编号：M5.28、T06a.29
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、新加的 `LookLiveDanmakuArgs` 和公告 [E02.13](../../../E-直播平台/E02-其他国内平台/E02.13-LOOK直播/README.md)（弹幕参数见它的 [record.md](../../../E-直播平台/E02-其他国内平台/E02.13-LOOK直播/record.md)）；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉；详细记录 [record.md](record.md)

## 目标

LOOK 直播（网易云音乐旗下）直播间能看到聊天。聊天走网易云信（NIM）聊天室，照官网脚本用网页公开的 appKey 匿名游客登录，不需要登录态、签名或额外密钥。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | 进房时 `room/get/v3` 已有房间号、云信聊天室 id（`roomInfo.roomId`）、`anonymousMode`，放进 `LookLiveDanmakuArgs`，不多发请求；房间号或聊天室 id 不合规：`connectionFailed`（`No usable room or chatroom`） |
| 聊天服务器 | 每次开始连接（`connect`）时 `POST https://api.look.163.com/weapi/livestream/chat/address`（`weapi` 信封，`{"liveRoomNo":…,"os":0}`）取 4 个 `chatwlXX.yunxinfw.com:443`，作为 `LiveSocket` 依次尝试的地址；失败 2 s 后再取一次，第二次也失败以 `connectionFailed`（`Chat servers: …`）结束；`code` 404（“无资源”，不在播）直接以 `connectionFailed`（`No chat: …`）结束 |
| socket.io 0.9 | 每次握手先 `GET https://<服务器>/socket.io/1/?t=<毫秒>` 取会话号（回答 `<会话>:90:30:websocket,xhr-polling`），再开 `wss://<服务器>/socket.io/1/websocket/<会话号>`；会话请求失败算握手失败（框架退避，最多 8 次）；包格式 `类型:id:端点:数据`，支持 `�` 拼包；服务端每 25 s 发 `2::`，客户端原样回；`0::`、`7:::` 换 socket；请求头是网页的 `Origin` 和 UA |
| 登录 | 收到 `1::` 发云信聊天室登录 13-2（appKey `3a6a3e48f6854dfa4e4464f3bdaec3b4`、SDK 版本 47、系统 Windows 10、浏览器 Chrome 140、账号 `nimanon_` + 32 位十六进制、空令牌、昵称“匿名用户”；游客身份每次开始连接随机生成，重连沿用，重连的登录带 appLogin 和递增序号）；每个 socket 只登录一次；回答 `code` 200 就绪；加入超时 10 s |
| 心跳 | 云信链路心跳 1-2（`3:::{"SID":1,"CID":2,"SER":0}`）登录后每 180 s（框架节拍每 30 s 一跳，第 6 跳发，登录前不发）；无消息 90 s 换 socket |
| 拒绝和被踢 | 登录码 408、415、500、503 重连，连续第 4 次结束，加入一次清零；其他码以 `connectionFailed`（`Login refused: <code>`）结束；被踢 13-3 原因 4 重连，其他（聊天室关闭、被踢、拉黑等）以 `connectionFailed`（`Kicked: <原因>`）结束 |
| 消息 | 4-10 通知里的 13-7（也读直接的 13-7）：文字消息（类型 0、`bizName` 为 `iplay`、有 `content.user`、没有被风险等级 `riskLevelKey` 挡住）→ 聊天，正文在属性 `3`；表情（类型 100、来自 `musiclive_server`、`custom.type` 2601）→ `[表情名]`；短键（`sp` 1）照网页展开；名字 `nickname`（没有时 `nickName`，`anonymousMode` 时打码成首字 + `***`）、用户 id `userId`（没有时消息的 `21`）、等级 `liveLevel`、粉丝团等级和名字、消息 id 属性 `1`、时间属性 `20`；白色；礼物、进场、点歌、PK、公告不报；聊天流里没有页面显示的在线人数 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `LookLiveSite.getDanmaku() => EmptyDanmaku()`（`core/site/looklive/look_live_site.dart:40`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `LookLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/looklive.dart:667`）：时序（:695）、`target`（:707）、取聊天服务器 `_addresses`（:724）、`onOpen`（:751）、`onData`（:757）回 `2::`、登录、就绪和上报、`_refused`（:799）、`_kicked`（:811）、链路心跳 `heartbeatFrame`（:826）；握手 `_Handshake`（:856，先取 socket.io 会话）；一次运行的 `_Chat`（:897）；应用登记在 `apps/pure_live/lib/app/platforms.dart:236` | 有聊天（已做） |
| 协议 | 无 | `LookLiveDanmakuProtocol`（:98）：appKey（:101）、SDK 版本（:104）、系统和浏览器（:112、:115）、游客昵称（:118）、心跳节拍 30 s 和 6 跳（:126、:130）、加入超时 10 s（:134）、取地址 2 次和间隔 2 s（:138、:141）、拒绝上限 3（:145）、可重连的拒绝码（:151）、被踢原因（:156）、无提示的被踢（:166）、心跳帧（:173、:177）、`addressRequest`（:208）、`handshakeRequest`（:232）、`sessionOf`（:255）、`login`（:279）、`decode`（:333）、`chat`（:455）；游客身份 `LookLiveGuest`（:56） | 与网页代码逐帧一致 |
| 参数 | 无 | `live_core` 新加 `LookLiveDanmakuArgs`（`packages/live_core/lib/src/sites/looklive/looklive_api.dart:73`），进房和录制详情给出，刷新、不在播、卡片不给 | — |
| 人数 | 列表的 `onlineNumber` | `audience.dart:263` 仍是 `roomList`；登录回答的 `onlineMemberNum` 是聊天室连接数，和列表对不上，不报 | — |
| 公告 | `looklive_chat_notice`“LOOK 远端聊天尚待接入；官网 popularity 按平台热度展示……”（`look_live_site.dart:95`，`assets/translations/zh.json:1956`） | `LookLiveApi.chatNotice`（`looklive_api.dart:378`）只说明人数：“人数是正在观看的人数，热度另外显示。”；没有留 `legacyChatNotice` | 3.x 存下的旧公告导入时清掉（J02.1） |

## 结果

- **提交**：3da78f071（2026-09-30，本任务的代码）。之后只有 docs v1 改编号时动过注释（c613b73f9、9dfbb424d），行为没有变。
- **和网页代码的对照**：`fixtures/looklive/danmaku/web_expected.js`（Node）把网页读的那一半原样搬进来（socket.io 的 `parser`、SDK 的 `createCmd`、`parseResponse`、属性表、消息模型，LOOK 的 `ignoreMsgs`、`parseIM`、`getMsgElement`）。S05-live（房间 447365581，320 s）123 个收到的帧逐帧一致：47 条聊天（35 条房间助手欢迎语、12 条观众聊天），61 条其他自定义消息不报；登录包与录制、SDK 组装逐字节相同。
- **实测**（2026-09-30 匿名直连）：已下播和不存在的房间回 404；会话回答 `…:90:30:websocket,xhr-polling`；服务端 `2::` 间隔 25.06 s；本实现连 60 s 就绪 1 次、3 条聊天。
- **样本**：`fixtures/looklive/danmaku/S05-live`（游客身份、会话号、观众 id、昵称、头像、`@` 到的名字都脱敏）。
- **测试**：`packages/live_danmaku/test/sites/looklive_test.dart` 现在 29 个（和做完时一样，没有循环生成的用例）：协议 12、录制 3、连接 14（含本地服务器端到端）；`live_core` 的 LOOK 测试 +7。

## 验证

- 自动测试：`looklive_test.dart` 覆盖常量和时序、聊天服务器请求和载荷、socket.io 握手请求和坏回答、登录包与 SDK 组装逐字节相同、重连后的 appLogin 和序号、socket.io 各种包和拼包、SDK 的登录、被踢和通知、聊天的过滤和各字段、表情和短键、打码；录制逐帧对照网页代码、用连接重放；连接的不在播直接结束、取地址重试一次、会话失败换服务器、掉线后新会话和新登录、可恢复的拒绝第 4 次结束、被踢、登录超时、心跳（`2::` 回应、第 6 跳才发）、关闭时取消请求、本地服务器端到端。
- 真实接口：2026-09-30 跑过（见上面的实测）。没遇到的：表情 2601、短键 `sp`、人数 200。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有 LOOK，E02.13 也写“没有在 K90 上专门看过”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有 LOOK 弹幕的条目。真机上要看：进一个在播的 LOOK 直播间，房间助手的欢迎语和观众聊天出现，看 5 分钟以上（跨过一次 180 s 链路心跳）不掉线。

## 留下的问题

- 下播（203，可能带轮播的下一个房间）、违规（302）、管理员消息（301）不报，连接只在聊天室关闭被踢出时结束：没有任务（要用时在协议层加一个事件，下播后的重连由 C01.1 的 B-24 按房间刷新处理）。
- 礼物、进场、点歌不显示：没有任务。B-21 的礼物显示（C01.2）只显示已上报礼物的平台，本平台要先解自定义消息 102、114 等。
- 不请求历史消息（网页连上后取最近 1 分钟的 5 条）：没有任务。
- 网页名字为空写“匿名用户”，这里留空：没有任务。
- 3.x 存下的旧公告：已由 J02.1 处理，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
