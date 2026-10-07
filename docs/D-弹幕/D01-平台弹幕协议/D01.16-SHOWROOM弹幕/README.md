# D01.16 SHOWROOM 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（完成，2026-09-29，提交 a30d7aedd）
- 类型：平台
- 来源：已批准升级 19-3“评论（弹幕）”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x 有 SHOWROOM 这个平台但没有评论，这是新增功能。附录 B 没有 SHOWROOM 的后续条目
- 旧编号：M5.15、T06a.16
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（和 Twitch [D01.9](../D01.9-Twitch弹幕/README.md) 同一类：文本帧、打开即加入、按间隔发心跳）；平台本身和弹幕参数（`bcsvr_host`、`bcsvr_key`）[E03.6 记录](../../../E-直播平台/E03-海外平台/E03.6-SHOWROOM/record.md)；下播后重连 B-24 在 [C01.1](../../../C-直播间/C01-进房和房间逻辑/C01.1-直播间主要流程/README.md)；握手的 User-Agent [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md)（本平台用默认的 `dart:io` 握手）；决定 D-017；详细记录 [record.md](record.md)

## 目标

SHOWROOM（日本偶像直播）直播间能看到观众评论，带网页上的“Class”等级。比归档 v4 多做了参数检查（防止带制表符的键在订阅帧里拼出别的命令），不再自己拼消息 id（交给去重闸门的无 id 规则），文字和名字只收字符串和整数，时间越界不再丢整帧。

## 协议要点

代码都在 `packages/live_danmaku/lib/src/sites/showroom.dart`（下面只写行号）。

| 项 | 内容 |
|---|---|
| 参数 | `ShowroomDanmakuArgs(roomId, host, key)`：`host`、`key` 就是 `live/live_info` 的 `bcsvr_host`、`bcsvr_key`，进房和录制详情在直播中时给出（E03.6），刷新和未开播没有。连接再用平台层的 `ShowroomApi.danmakuArgs` 检查一次（`checked` :50～53）：主机是 `showroom-live.com` 或子域（转小写，不带端口、路径），键不超过 256 字、不含空白和控制字符；不合格以 `connectionFailed`（`No usable comment server or key`）结束，不握手（`target` :147～151） |
| 地址 | `wss://<bcsvr_host>/`（443 端口，`endpoint` :41）；`live_info` 给的 `bcsvr_port` 8080 实测握手 10 s 超时，不用 |
| 握手 | 请求头 `origin: https://www.showroom-live.com` 和平台层的 Chrome 140 UA（`socketHeaders` :35，取 `ShowroomApi`；服务端其实不看，不带也能连）；默认 `dart:io` 握手；按平台 `showroom` 走代理（`apps/pure_live/lib/app/platforms.dart:222`） |
| 订阅 | 打开后发文本 `SUB\t<bcsvr_key>`（`subscribe` :44），随即就绪（`onOpen` :166～172）；键形如 `<16 位十六进制>:<live_id>`，每场直播一个、所有观众相同、不需要令牌；服务端不确认，键不对只是收不到消息；每次重连重新订阅、再报一次就绪；没有加入超时（`socketPolicy` :139～141 只写心跳） |
| 心跳 | 每 60 s 发 `PING\tshowroom`（`heartbeatInterval` :22、`ping` :25、`heartbeatFrame` :184），打开后第一次在 60 s 时；服务端约 0.3 s 回 `ACK\tshowroom`（`ack` :28），不上报。网页不发心跳，但没人说话的房间 90 s 里只有 `ACK`，靠它喂无消息检测：max(3 × 60 s, 90 s) = 180 s |
| 重连 | 框架默认（`DanmakuSocketPolicy`，`packages/live_danmaku/lib/src/socket_connection.dart:15～25`）：一个地址，间隔 2、3、4、5、6、6、6、6 s，连续 8 次失败以 `reconnectsExhausted` 结束，收到任何帧清零 |
| 下行 | 文本帧 `MSG\t<key>\t<JSON 对象>`（字节帧按 UTF-8 解）；第一、二个制表符之间的键必须等于本次订阅的键，第二个制表符之后整段按 JSON 读（`decode` :59～75）；`ACK`、别的键、不是 JSON、不是对象都丢掉 |
| 评论 | `t` 是整数 1 或字符串 `"1"`（`_isComment` :110）时是评论（`comment` :90～107）：文字 `cm` 去首尾空白，整数照写成数字（观众常数数“1”“2”），空白和其他类型不报；名字 `ac`、用户 id `u`（字符串或整数）；等级 `cl` 是大于 0 的整数时填 `userLevel`（网页显示“Class <cl>”）；时间 `created_at`（秒），不大于 0、不是整数或超出 `DateTime` 范围时为空；白色；平台不给消息 id，`messageId` 留空 |
| 不报的 | `t` 2、11、17 礼物，5 应援点数（不是人数），8、9 字幕，18 系统通知，101 下播、104 开播，100（只有时间），投票、联动对战、卡拉 OK 等；评论流里没有观看人数 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 评论 | 3.x 有 SHOWROOM 这个平台但没有评论：`ShowroomSite.getDanmaku() => EmptyDanmaku()`（`core/site/showroom/showroom_site.dart:46`），直播间只提示一次 `remote_danmaku_not_integrated`（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `ShowroomDanmakuConnection`（`showroom.dart:132`）继承 `DanmakuSocketConnection`；协议 `ShowroomDanmakuProtocol`（:20）；应用登记在 `apps/pure_live/lib/app/platforms.dart:222` | 有评论（已做） |
| 人数 | 列表人数是本场累计观看 | `packages/live_core/lib/src/audience.dart:139～143`：累计观看、没有在线（`unsupported`），本任务没有改（评论流里没有人数） | 不变 |
| 等级 | 3.x 长按面板在 `userLevel` 不为空时显示 `Lv.N`（`modules/live_play/widgets/danmaku/danmaku_message_actions.dart:19`） | 评论带 `cl`，但 4.x 的长按面板 `RoomMessagePanel`（`apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:112～150`）不显示等级 | 见“留下的问题” |

## 结果

- **提交**：a30d7aedd（2026-09-29，首次实现）。之后 `showroom.dart` 只有文档路径的注释随文档改名改过（c613b73f9、9dfbb424d），协议没有改动。
- **和归档 v4 的对照**：`fixtures/showroom/danmaku/v4_expected.dart` 把 v4 的 `ShowroomProtocol` 搬成独立程序，写下冻结输出 `S06-live/expected.json`。地址、请求头、订阅帧、心跳帧和间隔与 v4、录制相同；平台层从 `fixtures/showroom/S04-live-info-live` 解出的参数正是录制的主机和键；S06-live（房间 577362，2026-09-27 录制约 71 s）23 个收到的帧逐帧一致，18 条聊天，字幕、系统通知、`t` 100、`ACK` 都不报。差别只有消息 id：v4 自拼 `showroom:<u>:<created_at>:<哈希>`，现在留空（录制里没有 `cl`，两边等级都为空）。
- **有意差异**（record.md“与归档 v4 的差异”5 条）：不报礼物（v4 报，但礼物名只有编号 `#<g>`）；消息 id 留空；读等级 `cl`；文字和名字只收字符串和整数、时间越界只让这一条没有时间；参数用平台层的规则再检查，不合格是 `connectionFailed`。
- **样本**：只用归档的 `fixtures/showroom/danmaku/S06-live`，帧没有改，新加冻结输出 `expected.json`；没有新录样本（实测没有存成样本）。
- **测试**：`packages/live_danmaku/test/sites/showroom_test.dart` 现在 17 个用例（没有循环生成的，做完时同样 17 个）：协议 5、录制 4、连接 8。

## 验证

- 自动测试：`showroom_test.dart`——协议 5 个（地址、订阅、心跳、`ACK`、请求头；参数检查 12 种；评论各字段和边界；帧的各种形状）、录制 4 个（和 v4 及录制发出的帧一致、参数来自 S04、23 帧逐帧一致、用连接重放整份录制）、连接 8 个（默认时序和登记；握手、订阅、就绪；按间隔发 `PING`、没有回答时换连接并重新订阅；断线重连；参数不对不握手；关闭和换房间；本地服务器端到端：路径、`Origin`、UA、`SUB`、`PING` 和 `ACK`，字幕不报、聊天上报）。在 +30 天、+1 年、+5 年下运行都通过。
- 真实接口：2026-09-28（UTC 21:40～22:00）用自写的 `dart:io` 小程序匿名直连探测（不是本实现）：握手约 1.3 s；错键和不订阅都只收到 `ACK`；6 个人最多的房间 90 s 收到 47 条评论，字段一致、`cl` 都大于 0；一个房间 90 s 里只有 `ACK`；没有观看人数类的消息。**本实现没有接真实服务器跑过**，只用录制回放和本地服务器验证，协议和探测结果逐项对照过。
- 真机：没有单独的真机记录。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节没有 SHOWROOM，海外平台要用户开代理；E03.6 的记录里也没有 K90 结果。登记表是“完成”，但本实现既没有连过真实服务器也没有真机结果，按 D-029 还算“没验证”。

## 留下的问题

- 本实现没有在真实服务器上跑过，是 D01 里只靠录制回放和本地服务器验证的平台：没有单独的任务，建议下一次开代理做真机补验时（[S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 一类）进一个在播的 SHOWROOM 直播间看评论和等级是否出现。
- 主播重新开播后键 `bcsvr_key` 会变，旧连接不会自己结束（只剩 `ACK`）。B-24 的“下播后重连”只在弹幕连接已经结束时重连（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`），所以人留在直播间时评论不会换到新的一场，要重新进房：没有任务（和克拉克拉 [D01.14](../D01.14-克拉克拉弹幕/README.md) 同一个问题）。
- 下播（`t` 101）、开播（`t` 104）不报，网页据此标记下播或刷新整页；要用时在协议层加事件：没有任务。
- 礼物不显示：要解 `t` 2、11、17，礼物名要另查礼物表（规格 §12 待确认 2）；B-21 只显示已上报 `gift` 的平台：没有任务。
- 评论带等级 `cl`，4.x 长按面板不显示 `Lv.N`（3.x 显示）：所有带等级的平台都一样，没有任务，见 [D01.13](../D01.13-猫耳FM弹幕/README.md) 的同一条。
- 握手的 User-Agent 去掉 `Dart/<版本>` 前缀：本平台请求头里自带 UA，是否受影响见 [Q03.1](../../../Q-网络和代理/Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md) 的逐平台验证。
