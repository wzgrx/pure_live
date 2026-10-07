# D01.4 虎牙 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：模块重构（M5 的第 3 个平台）：把 3.x 的 `lib/core/danmaku/huya_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一
- 旧编号：M5.3、T06a.4
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、Tars 编解码、头条留言板接口和后来的礼物、头条面板、下播通知 [E01.3 记录](../../../E-直播平台/E01-国内五大平台/E01.3-虎牙/record.md)；详细记录 [record.md](record.md)

## 目标

虎牙直播间的弹幕照 3.x 连上和显示：聊天（带颜色）、热度、头条留言（醒目留言）；同时修掉 3.x 一条坏消息丢掉整帧、颜色解析靠两个错误抵消、坏 UTF-8 丢整帧等问题。后来按网页的做法用平台消息 id 去重（B-4），收到下播通知就结束连接（C-10）。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | 只有 `wss://wsapi.huya.com`，匿名，握手不带 `Origin`（3.x 也不带） |
| 编码 | Tars（`live_core/src/tars.dart` 的 `TarsWriter`、`TarsStruct`，E01.3 放在公共位置）；帧 tag 0 命令号、tag 1 负载 |
| 加入 | 打开即就绪，发命令 16 注册 `live:<主播UID>`、`chat:<主播UID>` 两个分组，紧接着发一次心跳；每次重连重新注册 |
| 心跳 | 命令 20、空负载，60 s；无消息 180 s 换连接；单地址，重连间隔 2～6 s，8 次后放弃；没有加入计时器 |
| 推送 | 命令 7（单条：tag 1 uri、tag 2 消息体、tag 5 `lMsgId`）和命令 22（分组：条目 tag 0 uri、tag 1 消息体、tag 2 事件 id），其他命令忽略 |
| 消息 | uri 1400 聊天（发送者 tag 0、内容 tag 3、颜色在 tag 6 的 tag 0，不大于 0 为白色）；uri 8006 热度（`popularity`，不是在线人数）；后来加了 uri 6501 礼物（聊天列表里单独一行，B-21）、uri 8001 下播通知 |
| 消息 id | `huya:<lMsgId>`（单条推送 tag 5，B-4）或 `huya:<事件id>`（分组推送 tag 2）；去重闸门按 id 10 分钟内只收一次 |
| 头条留言 | uri 2001314：C-9 起先按留言板面板解析消息体直接上报；消息体解不开时照 3.x 在后台调用 `HuyaDanmakuArgs.superChats` 补拉留言板，间隔 0、0.6、1.8、4 s，每次 3 s 超时，每次连接同一条只报一次（最多记 512 条） |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/huya_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/huya.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `HuyaDanmaku`（:29），`HuyaSite.getDanmaku()`（`core/site/huya/huya_site.dart:42`） | `HuyaDanmakuConnection`（:314）；应用登记在 `apps/pure_live/lib/app/platforms.dart:208` | 一致 |
| 地址、心跳 | `serverUrl`（:73），`heartbeatTime = 60 * 1000`（:49） | `endpoint`（:68），`heartbeatInterval`（:71），`socketPolicy`（:325） | 一致 |
| 注册包 | `getJoinData`（:135） | `HuyaDanmakuProtocol`（:66 起） | 与 3.x、录制逐字节相同 |
| 聊天、热度 | uri 1400（:193）、8006（:207） | `chatUri`（:86）、`popularityUri`（:90），读法 :234、:281 | 一致；颜色按修正后的 `numberToColor` |
| 坏消息 | 整帧一个 `try`，一条坏的丢掉后面全部 | 每个条目单独解码 | 修好 |
| 留言板 | 弹幕里直接调全局的 `getHuyaSuperChatMessageList`（:31） | 由 `HuyaDanmakuArgs.superChats` 读（适配器自己的 HTTP 客户端），重试间隔 :115～117，补拉 `_HuyaSuperChats`（:380） | 请求和解析相同（E01.3 逐字段核对） |
| 消息 id | 单条推送没有 id，按“用户 + 文字 2.5 s”去重 | tag 5 `lMsgId`（:228） | 同一条送两次只显示一次；同一观众 2.5 s 内重复说的每条都显示（同网页） |
| 下播 | 不处理，下播后一直空等 | uri 8001 报 `ended`，本房间主播的下播以 `connectionFailed`（`Broadcast ended`，:102、:367）结束 | 不再空等重连 |

## 结果

- **提交**：5051893e3（2026-09-29，M5.3），8613f92bd（2026-10-01，B-4 单条推送带 `lMsgId`）。之后同一文件的改动属于 E01.3：ce7de2d01（礼物上报）、5a9fa6a5e（头条通知直接解析面板 C-9、下播结束连接 C-10）。
- **和 3.x 的对照**：`fixtures/huya/danmaku/legacy_expected.dart` 把 3.x 的解码和 Tars 编解码搬成独立程序。S11-live（房间 998，262 帧）112 条消息逐条一致（B-4 之后期望改为“3.x 的输出 + 单条推送带 id”）；S16-synthetic 22 组除 4 处有意差异（坏条目只丢自己、颜色、坏 UTF-8 和 int8 符号、留言板读法）外一致。
- **没采用归档 v4 的两处改动**：把聊天 tag 1 当主播 UID 过滤（tag 1 其实是频道号，不等时会丢光聊天）、只收注册分组的命令 22。
- **样本**：`fixtures/huya/danmaku/` 的 S11-live、S16-synthetic、S17-reconnect（两条连接同时录，证明 tag 5 跨连接稳定、重连不补发）、后来的 S18-gift、S19、S20。
- **测试**：`packages/live_danmaku/test/huya_test.dart` 做完时 47 个，B-4 后 52 个，E01.3 的礼物 +2、C-9/C-10 +3，现在 57 个。

## 验证

- 自动测试：`huya_test.dart`（S11 回放、S17 跨连接去重、头条补拉的时序、本地 WebSocket 服务器端到端）。
- 真实接口：2026-09-30 匿名直连 998、60066 各 120 s，聊天 58 和 290 条、热度 6 次、礼物 19 和 27 个、1 次头条通知（E01.3 记录）。
- 真机：没有单独的真机记录；[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（虎牙热门直播间）还没逐条填结果。

## 留下的问题

- 同一观众 2.5 s 内重复的弹幕现在每条都显示（和网页一致），想合并的用户要打开“折叠重复弹幕”；这是 B-4 的有意变化。
- 主播 UID 为 0 时照样注册 `live:0`（3.x 如此）；E01.3 只给直播中的房间弹幕参数，实际不会发生。
- 进场、贵宾席不显示（3.x 也不显示）；礼物按 B-21 在聊天列表里单独一行显示（C01.2，弹幕设置“在聊天列表显示礼物”可关），不上飞行弹幕。
- 电视端要不要把虎牙弹幕统一成白色（pure_live_TV 的做法）留给 X 组决定。
- 附录 C-11（贵族开通、续费 uri 1001 显示为通知）：8 分钟 55 个房间没录到样本，没做，[specs/UPGRADES.md](../../../specs/UPGRADES.md) 里记为“未排”。
