# D01.14 克拉克拉 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 15-8“克拉克拉弹幕（归档 v4 已实现）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 没有克拉克拉弹幕，这是新增功能
- 旧编号：M5.13、T06a.14
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数 [E02.6 记录](../../../E-直播平台/E02-其他国内平台/E02.6-克拉克拉/record.md)；详细记录 [record.md](record.md)

## 目标

克拉克拉（语音直播）直播间能看到聊天和直播间显示的“收听”人数；比归档 v4 多认出服务端的拒绝和踢出、不再把数字当聊天。后来（B-10）礼物每次送礼报一次、付费提问上板时显示为醒目留言。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | `wss://wim.hongrenshuo.com.cn/socket.io/?roomId=<roomIdStr>&appId=111&clientType=1&EIO=3&transport=websocket`（官网脚本的 `live_chat_room_guest` 是 socket.io-client 的命名空间写法）；请求头 `origin: https://live.kilakila.cn`、`user-agent: Mozilla/5.0`；默认 `dart:io` 握手 |
| Socket.IO | 只实现用到的部分，不加依赖：打开后发命名空间加入包 `40/live_chat_room_guest?roomId=<id>&appId=111&clientType=1,`；每 25 s 发 Engine.IO ping `2`，服务端回 `3`；服务端 85 s 没收到 ping 会断开 |
| 加入 | 收到 `connect_error`（`code` 0 就是“join success”）或命名空间 `40` 就算加入，每个 socket 只报一次就绪；加入超时 8 s 换 socket |
| 拒绝和踢出 | `connect_error` 的 `code` 非 0 或 `44` 错误包：带 `protocolError` 提示重连，连续第 4 次被拒以 `connectionFailed` 结束；`41`（离开命名空间）或 Engine.IO `1`：马上重连 |
| 消息 | `42/live_chat_room_guest,["text_message","<JSON>"]`，`body.response` 里 `room_id` 不是本场的丢；`content.t` 200 → 聊天（`c` 文字、`n` 名字、`u` 用户 id、`l` 等级、消息 id `mid`、时间 `created_at`）；637 房间状态的 `watchNumber`（URL 编码 JSON，约每 5 s）→ 在线人数（就是直播间显示的“收听”，不是列表的累计） |
| B-10 礼物 | 10004 礼物条报一次（价格 = 单价 × 数量）；220 非连击报一次；连击中的 220 不报；文字照网页 `我送了<收礼人><数量>个<礼物>` |
| B-10 提问 | 240、300、301、534、532、706 带 `uc.question` 且 `uiType` 是显示问题的 8 种之一、`goldPrice` 大于 0 时报醒目留言：`messageId` 是 `questionId`，`priceText` 如 `1,000红豆`，显示 5 分钟 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `KilakilaSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/kilakila/kilakila_site.dart:35`），提示一次“尚未接入” | `KilakilaDanmakuConnection`（`packages/live_danmaku/lib/src/sites/kilakila.dart:549`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:220` | 有聊天和收听人数（已做） |
| 协议 | 无 | `KilakilaDanmakuProtocol`（:103）：主机 :105、心跳 25 s（:111）、`decode`（:182）、`gift`（:310）、`question`（:364）、提问显示 5 分钟（:155）；`defaultPolicy`（:556～558）加入超时 8 s | 与归档 v4 对照，有意差异 11 条 |
| 在线人数 | 列表和 `getRoomInfo` 的 `watchNumber` 是累计（REG-KILAKILA-003） | 弹幕 637 的 `watchNumber` 是此刻收听；`audience.dart` 仍是 `roomRealtime` | 和官网直播间一致 |

## 结果

- **提交**：644d18e6b（2026-09-29，M5.13），a9f412940（2026-10-01，B-10）。
- **和归档 v4 的对照**：`fixtures/kilakila/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序。地址、加入包、心跳帧、时序设置与 v4 和录制相同；S07-live 5 条聊天一致；S08-live-full（补录 150 s，内容完整）7 条聊天一致，另有 30 次在线人数（v4 的录制把 637 的内容丢了，所以它以为没有人数）；S09-synthetic 24 组里 16 组一致、8 组有意差异。
- **实测**（2026-09-28 匿名直连）：本实现 258～264 ms 就绪；累计 911 人的直播 120 s 收到 11 条聊天、25 次在线人数（98～102），没有重连；不发 ping 的连接 85.3 s 被断开。2026-09-30 匿名录 30 场各 40 分钟：聊天 15,181、礼物 220 共 3,241、礼物条 1,933、提问上板 48；本实现解出礼物 2,634 条（= 1,933 + 699 + 2）、醒目留言 32 条。
- **顺手修的**：`_decodeUriComponent`（:372、:464）原来用 `Uri.decodeComponent`，遇到明文中文会抛 `ArgumentError`，改成照 JavaScript 的 `decodeURIComponent` 只解 `%XX`。
- **样本**：`fixtures/kilakila/danmaku/` 的 S07-live（补做 `sid`、`uxid` 脱敏）、S08-live-full、S09-synthetic、S10-live-gifts-questions、S11-live-question-board。
- **测试**：`packages/live_danmaku/test/sites/kilakila_test.dart` 做完时 44 个（另做过 17 种变异），B-10 后 51 个。

## 验证

- 自动测试：`kilakila_test.dart`（本地 WebSocket 服务器端到端：路径和查询、Origin、UA、ping 和 pong、聊天和人数）。
- 真实接口：见上面的实测。没验证到的：服务端拒绝加入（找不到让它拒绝的写法，只用合成帧）、直播结束时的消息（`msg_type` 11 或 103）、`uiType` 3、6、7 等少见的提问版面。
- 真机：没有单独的真机记录；克拉克拉不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。

## 留下的问题

- 进房时详情给的是主页卡片的 `onlineNumber`，几秒后弹幕给的是直播间的 `watchNumber`，两者差几个到十几个人，后到的覆盖详情值。
- 主播重新开播后直播号会变，旧连接不会自己结束（只剩 ping、pong），和 TwitCasting 一样没被 B-24 的“结束后重连”覆盖。
- 进场、第一次点亮不显示（B-10 决定不做）。
- 提问 5 分钟是按录到的板上停留时间（中位数约 4.5 分钟）自定的；清板不会提前撤下醒目留言。
- 被拒时会连着出现两条提示（`protocolError` 一条，连接自己的“断开”一条）。
