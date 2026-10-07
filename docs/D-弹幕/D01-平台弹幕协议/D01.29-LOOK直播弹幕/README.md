# D01.29 LOOK 直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 32-7“聊天（网易云信）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 的 LOOK 直播没有聊天，这是新增功能
- 旧编号：M5.28、T06a.29
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、新加的 `LookLiveDanmakuArgs` 和公告 [E02.13 记录](../../../E-直播平台/E02-其他国内平台/E02.13-LOOK直播/record.md)；详细记录 [record.md](record.md)

## 目标

LOOK 直播（网易云音乐旗下）直播间能看到聊天。聊天走网易云信（NIM）聊天室，照官网脚本（打包了云信 Web SDK 5.0.1 和 socket.io 0.9.11）用网页公开的 appKey 匿名游客登录，不需要登录态、签名或额外密钥。

## 协议要点

| 项 | 内容 |
|---|---|
| 参数 | 进房时 `room/get/v3` 已有房间号、云信聊天室 id（`roomInfo.roomId`）、`anonymousMode`，放进 `LookLiveDanmakuArgs`，不多发请求 |
| 聊天服务器 | 每次连接 `POST https://api.look.163.com/weapi/livestream/chat/address`（`weapi` 信封，`{"liveRoomNo":…,"os":0}`）取 4 个 `chatwlXX.yunxinfw.com:443`；失败 2 s 后再取一次；`code` 404（不在播）直接结束 |
| socket.io 0.9 | 每次握手先 `GET https://<服务器>/socket.io/1/?t=<毫秒>` 取会话号，再开 `wss://<服务器>/socket.io/1/websocket/<会话号>`；包格式 `类型:id:端点:数据`，支持 `�` 拼包；服务端每 25 s 发 `2::`，客户端原样回 |
| 登录 | 收到 `1::` 发云信聊天室登录 13-2（appKey `3a6a3e48f6854dfa4e4464f3bdaec3b4`、账号 `nimanon_` + 32 位十六进制、空令牌、昵称“匿名用户”，游客身份每次连接随机生成）；回答 `code` 200 就绪；加入超时 10 s |
| 心跳 | 云信链路心跳 1-2 登录后每 180 s（框架计时每 30 s 一跳，第 6 跳发）；无消息 90 s |
| 拒绝和被踢 | 登录码 408、415、500、503 重连，连续第 4 次结束；其他码以 `connectionFailed`（`Login refused: <code>`）结束；被踢 13-3 原因 4 重连，其他（聊天室关闭、被踢、拉黑）结束 |
| 消息 | 4-10 通知里的 13-7：文字消息（`bizName` 为 `iplay`、有 `content.user`、通过风险等级过滤）→ 聊天，正文在属性 `3`；名字 `nickname`（`anonymousMode` 时打码成首字 + `***`）、`userId`、`liveLevel`、粉丝团；表情 2601 → `[表情名]`；礼物、进场、点歌、PK、公告不报；聊天流里没有页面显示的在线人数 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `LookLiveSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/looklive/look_live_site.dart:40`），提示一次“尚未接入” | `LookLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/looklive.dart:667`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:236` | 有聊天（已做） |
| 协议 | 无 | `LookLiveDanmakuProtocol`（:98）：appKey、SDK 版本、系统和浏览器（:101～115）、游客昵称（:118）、心跳节拍 30 s 和 6 跳（:126～130）、加入超时 10 s（:134）、取地址 2 次（:138～141）、可重连的拒绝码（:151）；`LookLiveGuest`（:56） | 与网页代码逐帧一致 |
| 人数 | 列表的 `onlineNumber`（`roomList`） | 不变（登录回答的 `onlineMemberNum` 是聊天室连接数，和列表对不上，不报） | — |
| 公告 | 说看不到聊天 | `LookLiveApi.chatNotice` 只说明人数 | — |

## 结果

- **提交**：3da78f071（2026-09-30，M5.28）。之后没有改动。
- **和网页代码的对照**：`fixtures/looklive/danmaku/web_expected.js`（Node）把网页读的那一半原样搬进来（socket.io 的 `parser`、SDK 的 `createCmd`、`parseResponse`、属性表、消息模型，LOOK 的 `ignoreMsgs`、`parseIM`、`getMsgElement`）。S05-live（房间 447365581，320 s）123 个收到的帧逐帧一致：47 条聊天（35 条房间助手欢迎语、12 条观众聊天），61 条其他自定义消息不报；登录包与录制、SDK 组装逐字节相同。
- **实测**（2026-09-30 匿名直连）：已下播和不存在的房间回 404；会话回答 `…:90:30:websocket,xhr-polling`；服务端 `2::` 间隔 25.06 s；本实现连 60 s 就绪 1 次、3 条聊天。
- **样本**：`fixtures/looklive/danmaku/S05-live`（游客身份、会话号、观众 id、昵称、头像、`@` 到的名字都脱敏）。
- **测试**：`packages/live_danmaku/test/sites/looklive_test.dart` 29 个（协议 12、录制 3、连接 14，含本地服务器端到端）；`live_core` 的 LOOK 测试 +7。

## 验证

- 自动测试：`looklive_test.dart`。
- 真实接口：见上面的实测。没遇到的：表情 2601、短键 `sp`、人数 200。
- 真机：没有单独的真机记录；LOOK 不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。

## 留下的问题

- 下播（203，可能带轮播的下一个房间）、违规（302）、管理员消息（301）不报；连接只在聊天室关闭被踢出时结束。
- 礼物、进场、点歌不显示。
- 不请求历史消息（网页连上后取最近 1 分钟的 5 条）。
- 网页名字为空写“匿名用户”，这里留空。
