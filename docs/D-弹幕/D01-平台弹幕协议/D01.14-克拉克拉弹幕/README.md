# D01.14 克拉克拉 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 644d18e6b）
- 类型：平台
- 来源：已批准升级 15-8“克拉克拉弹幕（归档 v4 已实现）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有克拉克拉这个平台但没有弹幕，这是新增功能。后续的 B-10（礼物、付费提问）是同一升级表附录 B 的条目
- 旧编号：M5.13、T06a.14
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身和弹幕参数 [E02.6](../../../E-直播平台/E02-其他国内平台/E02.6-克拉克拉/README.md)；礼物显示 B-21 和下播后重连 B-24 在 [C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)、[C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；握手的 User-Agent [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（本平台用默认的 `dart:io` 握手）；决定 D-017（测试不访问真实平台、样本时间固定）；详细记录 [record.md](record.md)

## 目标

克拉克拉（语音直播）直播间能看到聊天和直播间显示的“收听”人数。比归档 v4 多认出服务端的拒绝（`44`）和踢出（`41`、Engine.IO `1`），不再把数字、布尔值当聊天，一行坏数据只丢这一行。后来（B-10）每次送礼报一次礼物，付费提问上板时显示为醒目留言。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/kilakila.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 地址 | `wss://wim.hongrenshuo.com.cn/socket.io/?roomId=<roomIdStr>&appId=111&clientType=1&EIO=3&transport=websocket`（`host` :105、`endpoint` :165）。官网脚本写的 `wss://…/live_chat_room_guest?…` 是 socket.io-client 的“地址 + 命名空间”写法。订阅哪一场由握手地址的 `roomId` 决定。参数 `KilakilaDanmakuArgs.roomId` 是这一场直播的 `roomIdStr`，去空白后不是直播号（`KilakilaApi.isId`）时以 `connectionFailed`（`No broadcast`）结束、不握手（`target` :569～579） |
| 握手 | 请求头 `origin: https://live.kilakila.cn`、`user-agent: Mozilla/5.0`（`handshakeHeaders` :118，取 `KilakilaApi`）；不要 Cookie；默认 `dart:io` 握手；按平台 `kilakila` 走代理（`apps/pure_live/lib/app/platforms.dart:220`） |
| Socket.IO | 只实现用到的部分，不加依赖：全是文本帧，一帧一个包（`decode` :182、`_packet` :194、`_event` :216）。Engine.IO `0`、`3`、`6` 不报；`1` 是服务端关闭传输 |
| 加入 | 打开就发命名空间加入包 `40/live_chat_room_guest?roomId=<id>&appId=111&clientType=1,`（`join` :169、`onOpen` :588～595）；收到 `connect_error` 且 `code` 为 0（“join success”）或命名空间的 `40` 就算加入，每个 socket 只报一次就绪（`onData` :617～621）；加入超时 8 s（`defaultPolicy` :556～559），超时放弃这个 socket 重连、不单独提示（`onJoinTimeout` :641） |
| 拒绝 | `connect_error` 的 `code` 不是 0（说明取 `message`，没有时写 `code <值>`）或命名空间错误包 `44`（`_errorText` :242）：带 `protocolError` 提示重连；连续被拒 3 次后（`maxRefusals` :563），第 4 次以 `connectionFailed` 结束，详情 `Join refused: <文字>`（`_refused` :625～635）；加入成功清零 |
| 踢出 | 服务端离开命名空间 `41/live_chat_room_guest` 或 Engine.IO `1`：马上重连，不单独提示（`onData` :612～616）；放弃了的 socket 迟到的帧不再算数（:603） |
| 心跳 | 从打开起每 25 s（`heartbeatInterval` :111）发 Engine.IO ping `2`（`ping` :114、`heartbeatFrame` :648），加入前也发；服务端每次回 `3`；服务端 85 s 没收到 ping 就发 `1` 并断开 TCP；无消息超时取框架默认 max(3 × 25 s, 90 s) = 90 s |
| 重连 | 框架默认（`DanmakuSocketPolicy`，`packages/live_danmaku/lib/src/socket_connection.dart:15～25`）：一个地址，间隔 2、3、4、5、6、6、6、6 s，连续 8 次失败以 `reconnectsExhausted` 结束，收到任何帧清零 |
| 消息外层 | `42/live_chat_room_guest,["text_message","<JSON 字符串>"]`；载荷的 `body.response` 有 `room_id`（不是本场的丢，没有的算本场）、`mid`（消息 id）、`created_at`（毫秒）、`content`（又一层 JSON 字符串，短字段名）（`textMessage` :275～289）；`content.t` 必须是整数，写成文字的不认 |
| 聊天 | `t` 200（`chatType` :124，`chat` :437～451）：文字 `c` 去首尾空白，不是文字或为空不报；名字 `n` 原样；用户 id `u`（数字或文字）；等级 `l`（整数或数字文字）；消息 id `mid`（不加前缀）；时间 `created_at`（正整数且在 `DateTime` 范围内，否则为空）；白色；头像、徽章、`vip`、管理员、性别不读 |
| 收听人数 | `t` 637 房间状态（`roomStateType` :128，`audience` :462～474）：`c` 是 URL 编码的 JSON，解开后 `watchNumber`（不小于 0 的整数）报 `onlineViewers`，约每 5 s 一次；这是官网直播间显示的“收听”，不是列表和 `getRoomInfo` 里同名的累计数（REG-KILAKILA-003） |
| B-10 礼物 | `gift`（:310～348）：礼物条 10004（`giftLineType` :136）报一次，数量 `doubleCount`、价格是单价 × 数量；礼物动画 220（`giftType` :132）不是连击（`isDoubleHit` 不是 true）时报一次、价格照写；连击中的 220 不报。文字照网页 `我送了<收礼人><数量>个<礼物>`，没有收礼人时“豆咖”；`data` 是 `KilakilaGift`（:13，`id`、`name`、`count`、`price` 红豆、`receiverName`、`icon` 只收 https，`free` 是价格为 0） |
| B-10 付费提问 | `question`（:364～412）：`t` 是 240、300、301、532、534、706 之一（`boardTypes` :145），`uc.uiType` 是显示问题的 2、3、6、7、10、11、14、15（`questionUiTypes` :149），`uc.question` 各文字字段 `decodeURIComponent` 都成功，`goldPrice` 大于 0，`content` 不为空时报醒目留言：`messageId` 是 `questionId`（同一问题再上板是同一条），名字 `questionNickname`、头像 `questionHeadUrl`（https）、用户 id `questionUid`，价格 `goldPrice`，`priceText` 如 `1,000红豆`（`amount` :416），开始是 `created_at`，没有时用收到的时间，显示 5 分钟（`questionDisplay` :155）；241（只有提问人和价格，`questionAskedType` :140）不报 |
| URL 解码 | `_decodeUriComponent`（:483～505）照 JavaScript 的 `decodeURIComponent` 只解 `%XX`，明文中文原样；坏的转义或坏的 UTF-8 返回 null |
| 不报的 | 进场（101、603）、离开（102）、点赞（210）、第一次点亮（211）、榜单（635、636）、活动、直播结束（103 或 `msg_type` 11）等 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有克拉克拉这个平台但没有弹幕：`KilakilaSite.getDanmaku() => EmptyDanmaku()`（`core/site/kilakila/kilakila_site.dart:35`），直播间只提示一次 `remote_danmaku_not_integrated`（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `KilakilaDanmakuConnection`（`kilakila.dart:549`）继承 `DanmakuSocketConnection`；协议 `KilakilaDanmakuProtocol`（:103）；应用登记在 `apps/pure_live/lib/app/platforms.dart:220` | 有聊天和收听人数（已做） |
| 在线人数 | 人数设置页（`modules/settings/pages/audience_metric_settings_page.dart:22`）说明“watchNumber 尚无已验证的并发人数含义，不参与真实在线排行” | `packages/live_core/lib/src/audience.dart:296～300`：克拉克拉是 `roomRealtime`、有累计；进房后弹幕 637 的 `watchNumber` 覆盖详情给的主页卡片 `onlineNumber`（`room_controller.dart` 的 `_applyAudience`） | 和官网直播间“收听”一致（已做） |
| 礼物、付费提问 | 无 | 礼物进聊天列表单独一行，受“在聊天列表显示礼物”开关控制（B-21，`apps/pure_live/lib/features/live_play/logic/room_controller.dart:907～910`）；付费提问进醒目留言栏（:893～898） | 已做 |
| 等级 | 3.x 长按面板在 `userLevel` 不为空时显示 `Lv.N`（`modules/live_play/widgets/danmaku/danmaku_message_actions.dart:19`） | 聊天和礼物都带 `userLevel`，但 4.x 的长按面板 `RoomMessagePanel`（`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:112～150`）不显示等级 | 见“留下的问题” |

## 结果

- **提交**：644d18e6b（2026-09-29，首次实现：游客聊天、收听人数、拒绝和踢出）；a9f412940（2026-10-01，B-10：礼物、付费提问，顺手修 `_decodeUriComponent`）。
- **和归档 v4 的对照**：`fixtures/kilakila/danmaku/v4_expected.dart` 把 v4 的协议搬成独立程序，对 S07、S08、S09 写下冻结输出 `expected.json`。地址、加入包、心跳帧、`origin` 和时序设置（心跳 25 s、加入超时 8 s、无消息 90 s、被拒上限 3）与 v4 和录制相同；S07-live 57 个收到的帧里加入和 5 条聊天一致；S08-live-full 68 个收到的帧里加入和 7 条聊天一致，另有 30 次收听人数（v4 的录制把 637 的内容丢了，以为没有人数）；S09-synthetic 24 组里 16 组一致、8 组有意差异。B-10 后礼物照 v4 报（连击中的一下除外）。
- **有意差异**（record.md“与归档 v4 的差异”11 条）：消息 id 不加 `kilakila:` 前缀；礼物每次送礼只报一次；637 报收听人数；聊天文字必须是文字、时间越界只让这一行没有时间；用户 id 只收数字和文字；`44` 当被拒；`41` 和 `1` 马上重连；被拒按“连续”计；UA 用适配器的 `Mozilla/5.0`；心跳从打开起算；参数不对以 `connectionFailed` 结束。
- **顺手修的**：`_decodeUriComponent`（:483）原来用 `Uri.decodeComponent`，遇到 U+007F 以上的字符抛 `ArgumentError`（只接了 `FormatException`），带明文中文的问题文字会让 `decode` 抛出；改成照 JavaScript 只解 `%XX`。
- **样本**：`fixtures/kilakila/danmaku/` 下 S07-live（归档录制，补做 `sid`、`uxid` 脱敏）、S08-live-full（2026-09-28 补录 150 s、内容完整）、S09-synthetic（24 组合成帧）、S10-live-gifts-questions（10 帧：一次送出、连击和礼物条、付费提问上板）、S11-live-question-board（6 帧：同一付费问题两次上板）；S10、S11 没有 v4 的冻结输出，期望值写在测试里。
- **测试**：`packages/live_danmaku/test/sites/kilakila_test.dart` 现在运行 51 个用例（源码里 28 个 `test(`，其中 S09 每组一个在循环里，24 组）；首次实现时 44 个（做过 17 种变异），B-10 后 51 个（+7）。

## 验证

- 自动测试：`kilakila_test.dart` 分组——协议 5 个（地址、加入包、心跳帧、请求头和录制相同，637 的人数，被拒的说明）、录制对照 v4 2 个、S09 合成帧对照 v4 25 个、连接 12 个（时序、握手、打开即加入、两种确认只就绪一次、回放 S08、ping 从打开起按 25 s 发、加入超时、被拒提示和第 4 次结束、`41` 和 `1` 马上重连、不合规的直播号、关闭后无事件、本地 WebSocket 服务器端到端：路径和查询、Origin、UA、ping 和 pong、聊天和人数），B-10 7 个（S10 逐帧、S11、合成的礼物和问题、URL 解码、不报的类型、回放 S10）。测试时间都来自样本或注入的 `now`，在 +30 天、+1 年、+5 年下运行都通过。
- 真实接口：2026-09-28（UTC 21:00～21:45）匿名直连：本实现 258～264 ms 就绪；累计 911 人的一场 120 s 收到 11 条聊天、25 次收听人数（98～102），没有重连；不发 ping 的连接 85.3 s 被断开。2026-09-30（UTC 15:18～15:58）匿名录热门 30 场各 40 分钟：聊天 15,181、礼物动画 3,241、礼物条 1,933、提问上板 48；本实现解出礼物 2,634 条（= 1,933 + 699 + 2）、醒目留言 32 条。没验证到的：服务端拒绝加入（找不到让它拒绝的写法，只用合成帧）、直播结束时的消息、`uiType` 3、6、7、11、14、15 的提问版面。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列了哔哩哔哩、斗鱼、虎牙、抖音、快手，没有克拉克拉；[E02.6](../../../E-直播平台/E02-其他国内平台/E02.6-克拉克拉/README.md) 也写着“没有在 K90 上专门看过”。登记表是“完成”，按 D-029 这个平台的弹幕还算“没验证”。

## 留下的问题

- 进房时详情给的是主页卡片的 `onlineNumber`，几秒后弹幕给的是直播间的 `watchNumber`，两者差几个到十几个人，后到的覆盖详情值：照官网直播间的做法，不改，没有任务。
- 主播重新开播后直播号 `roomIdStr` 会变，旧连接不会自己结束（只剩 ping、pong）。B-24 的“下播后重连”只在弹幕连接已经结束时重连（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`，`refreshDetail` 里 `danmaku.status == DanmakuStatus.closed`），所以这种情况人留在直播间时弹幕不会换到新的一场，要重新进房；TwitCasting 一样。→ [C01.6](../../../C-直播间/C01-进房和房间逻辑/C01.6-主播换场后弹幕参数变了要重连/README.md)（2026-10-07 登记）。
- 进场、第一次点亮不显示（B-10 决定不做，和其他平台一致）。
- 付费提问显示 5 分钟是按录到的上板时间（11～865 s，中位数约 4.5 分钟）自定的；主播清板（301）不会提前撤下醒目留言（模型没有“提前结束”）：没有任务。
- 被拒时会连着出现两条提示（`protocolError` 一条，连接自己的“断开”一条），和 YY 的握手超时一样：界面文字的问题，没有任务。
- 聊天带等级，4.x 长按面板不显示 `Lv.N`（3.x 显示）：所有带等级的平台都一样，没有任务，要不要加回由维护者决定（见 [D01.13](../D01.13-猫耳FM弹幕/README.md) 的同一条）。
- 握手的 User-Agent 去掉 `Dart/<版本>` 前缀要先在 K90 上逐平台验证：[Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)。
- 真机上没看过（聊天、收听人数、礼物行、付费提问的醒目留言）：没有单独的任务，建议加进真机清单第 2 节，归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类的补验。
