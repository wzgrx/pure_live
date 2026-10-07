# D01.4 虎牙 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-09-29，提交 `5051893e3`）
- 类型：平台
- 来源：模块重构（弹幕协议的第 3 个平台）：把 3.x 的 `lib/core/danmaku/huya_danmaku.dart` 移到 `packages/live_danmaku`；3.x 已有弹幕的 8 个平台之一；2026-10-01 又做了已批准升级 B-4（平台消息 id 去重）
- 旧编号：M5.3、T06a.4
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)（去重闸门、折叠重复弹幕）；平台本身 [E01.3](../../../E-直播平台/E01-国内五大平台/E01.3-虎牙/README.md)（Tars 编解码、头条留言板接口，后来的礼物、头条面板 C-9、下播通知 C-10 在 [E01.3 记录](../../../E-直播平台/E01-国内五大平台/E01.3-虎牙/record.md)“国内平台完善”“附录 C 落地”两节）；巡检 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md)；升级条目 [specs/UPGRADES.md](../../../specs/UPGRADES.md) 的 B-4、C-9、C-10、C-11
- 记录：[record.md](record.md)

## 目标

虎牙直播间的弹幕照 3.x 连上和显示：聊天（带颜色）、热度、头条留言（醒目留言）；同时修掉 3.x 审查出的问题（一条坏消息丢掉整帧、颜色靠两个错误抵消才对、坏 UTF-8 丢整帧、文本帧抛错）。后来按网页的做法用平台消息 id 去重（B-4），头条通知直接解析面板（C-9），收到下播通知就结束连接（C-10）。

## 协议要点

| 项 | 内容 |
|---|---|
| 地址 | 只有 `wss://wsapi.huya.com`（`huya.dart:68`），匿名，握手不带 `Origin`、不带子协议（3.x 也不带；录制工具带了 `Origin` 也一样能收） |
| 参数 | `HuyaDanmakuArgs`（`packages/live_core/lib/src/sites/huya/huya_api.dart:71`）：主播 `uid`、`topSid`、`subSid`，另带 `superChats`（读头条留言板，`HuyaSite` 用自己的 HTTP 客户端，`huya_site.dart:342`；topSid 为 0 时为空）；回放和下播的房间没有弹幕参数 |
| 编码 | Tars（`packages/live_core/lib/src/tars.dart` 的 `TarsWriter`、`TarsStruct`，E01.3 放在公共位置；int8 按有符号读，坏 UTF-8 换成 `U+FFFD`）；外层帧 tag 0 命令号、tag 1 负载字节 |
| 加入 | 打开即就绪，发命令 16 注册（负载 tag 0 分组列表 `live:<主播UID>`、`chat:<主播UID>`，tag 1 空字符串，`register`，`huya.dart:132`），紧接着发一次心跳；每次重连都重新注册；主播 UID 为 0 时照样注册 `live:0`（同 3.x） |
| 心跳 | 命令 20、空负载，60 s（`heartbeatInterval`，`huya.dart:71`）；服务端心跳回应（命令 21）和注册回应（命令 17）不看；无消息 180 s（max(3 × 60 s, 90 s)）换连接；单地址，重连间隔 2、3、4、5、6、6、6、6 s，8 次后放弃；没有加入计时器 |
| 推送 | 命令 7（单条：tag 1 uri、tag 2 消息体、tag 5 `lMsgId`）和命令 22（分组：tag 1 条目列表，每条 tag 0 uri、tag 1 消息体、tag 2 事件 id），其他命令忽略；不检查分组和频道 |
| 聊天 | uri 1400（`MessageNotice`）：发送者 tag 0（其中 tag 0 uid、tag 2 昵称），文字 tag 3，弹幕格式 tag 6（其中 tag 0 颜色）；颜色不大于 0（默认 −1）为白色，否则走 E05.1 修正后的 `LiveMessageColor.numberToColor`（`color`，`huya.dart:216`）；缺字段按 3.x 的默认值（uid 0、空字符串）；空文字照样报出 |
| 热度 | uri 8006（`AttendeeCountNotice`）tag 0，报成 `LiveAudienceUpdate` 的 `popularity`（不是在线人数，REG-HUYA-014），缺失为 0 |
| 礼物（E01.3 加） | uri 6501（`SendItemSubBroadcastPacket`）：tag 0 礼物类型、2 数量、4 送礼人 uid、6 昵称、9 连击、20 礼物名、41 支付总额，报成 `LiveMessageType.gift`，数据 `HuyaGift`（`huya.dart:13`），文字 `<礼物名> ×<数量>`；没有名字的不报 |
| 消息 id | `huya:<lMsgId>`（单条推送 tag 5，B-4）或 `huya:<事件id>`（分组条目 tag 2），不大于 0 没有 id（`_messageId`，`huya.dart:232`）；D01.1 的去重闸门（`filters/message_gate.dart:24`）按 id 10 分钟内只收一次，有 id 的不再按“用户 + 文字 2.5 s”去重 |
| 头条留言 | uri 2001314：先用 `HuyaApi.headlineNotice`（`huya_api.dart:1118`）把消息体当留言板面板解析，每条留言直接作为醒目留言上报（C-9）；消息体缺失、为空、不是 Tars 时照 3.x 在后台调用 `superChats` 补拉，间隔 0、0.6、1.8、4 s（`superChatRetryDelays`，`huya.dart:113-118`），每次 3 s 超时（`:121`）；每次连接同一条只报一次，最多记 512 条（`:125`）；同一时间只有一轮补拉，期间再来通知只排一轮；醒目留言的用户名和文字都是 `SUPER_CHAT_MESSAGE`，配色 `#ffffff`/`#246488`，id `huya:<lMessageId>` |
| 下播（E01.3 加） | uri 8001（`EndLiveNotice`，tag 0 主播 uid）：本房间主播或 uid 不大于 0 的通知，先报完同一帧里的其他消息，再以 `connectionFailed`（`Broadcast ended`，`huya.dart:102`）结束，不重连；别的主播的不理 |
| 出错 | 分组里一个条目解不开只丢这一条；整帧不是 Tars 时什么也不报；文本帧忽略 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/danmaku/huya_danmaku.dart`） | 现在（`packages/live_danmaku/lib/src/sites/huya.dart`） | 要做到 |
|---|---|---|---|
| 入口 | `HuyaDanmaku`（:29），`HuyaSite.getDanmaku()`（`core/site/huya/huya_site.dart:42`） | `HuyaDanmakuConnection`（:314）继承 `DanmakuSocketConnection`；应用登记在 `apps/pure_live/lib/app/platforms.dart:208` | 一致（已做） |
| 地址、心跳 | `serverUrl`（:73），`heartbeatTime = 60 * 1000`（:49） | `endpoint`（:68），`heartbeatInterval`（:71），`socketPolicy`（:325） | 一致 |
| 注册包、心跳包 | `getJoinData`（:135），加入在 :131 | `HuyaDanmakuProtocol`（:66）的 `register`（:132）、`heartbeat`（:143）；`onOpen`（:341）就绪、注册、心跳 | 和 3.x、录制逐字节相同 |
| 聊天、热度 | uri 1400（:193）、8006（:207） | `chatUri`（:86）、`popularityUri`（:90），读法 `_chat`（:237）、`_popularity`（:283） | 一致；颜色按修正后的 `numberToColor` |
| 坏消息 | `decodeMessage`（:171）整帧一个 `try`，一条坏的丢掉后面全部 | `decode`（:158）每个条目单独 `try` | 修好（3.x 问题 1） |
| 颜色 | int8 按无符号读，−1 变 255，再靠 `numberToColor` 只认 4、6、8 位十六进制退回白色（`pkg/tars/codec/tars_input_stream.dart:48-50`、`common/models/live_message.dart:128-151`） | 不大于 0 为白色，其余走修正后的 `numberToColor` | 修好（3.x 问题 3）；录制里的颜色都是 6 位或 −1，结果不变 |
| 留言板 | 弹幕里直接调全局的 `getHuyaSuperChatMessageList`（:31），重试间隔 :34-38，3 s 超时 :259 | 由 `HuyaDanmakuArgs.superChats` 读；补拉 `_HuyaSuperChats`（:380），重试间隔 :113-118 | 请求和解析相同（E01.3 逐字段核对） |
| 头条通知的消息体 | 不读，每次通知都补拉（:221） | 先按面板解析（C-9），解不开才补拉 | 醒目留言随通知出现，少 1～4 个请求 |
| 消息 id | 单条推送没有 id，按“用户 + 文字 2.5 s”去重 | 单条推送 tag 5 `lMsgId`（`decode` 里 :200） | 同一条送两次只显示一次；同一观众 2.5 s 内重复说的每条都显示（同网页，B-4） |
| 下播 | 不处理，下播后一直空等 | uri 8001（`endUri`，:98）报 `ended`，`onData`（:351）里本房间的以 `connectionFailed` 结束（:367-368） | 不再空等重连（C-10） |
| 文本帧 | 回调把文本帧交给 `decodeMessage(List<int>)` 抛类型错误（:102-104） | `onData` 只收二进制（:353） | 修好（3.x 问题 2） |

## 结果

- **提交**：`5051893e3`（2026-09-29，`feat(live_danmaku): Huya danmaku refactored from v3 (M5.3)`），`8613f92bd`（2026-10-01，B-4 单条推送带 `lMsgId`）。之后同一文件的改动属于 E01.3：`ce7de2d01`（2026-10-01，礼物上报）、`5a9fa6a5e`（2026-10-01，头条通知直接解析面板 C-9、下播结束连接 C-10）。2026-10-03 的两次文档提交（`c613b73f9`、`9dfbb424d`）只改了代码和测试注释里的文档路径。
- **和 3.x 的对照**：`fixtures/huya/danmaku/legacy_expected.dart` 把 3.x 的解码和 Tars 编解码搬成独立程序。S11-live（房间 998，262 帧收到）112 条消息（110 条聊天、2 条热度）逐条一致（B-4 之后期望改为“3.x 的输出 + 单条推送带 id”）；S16-synthetic 22 组的帧由 `TarsWriter` 写出、和 3.x 的 `TarsOutputStream` 逐字节相同，除 4 处有意差异（坏条目只丢自己、颜色、坏 UTF-8 和 int8 符号、留言板读法）外一致。
- **有意差异**（record.md“与 v3 的有意差异”8 条）；保持 3.x 的地方：打开即就绪、握手不带 `Origin`、主播 UID 为 0 照样连、不检查分组和频道、空文字照样报、进场和贵宾席不显示、进房时的留言板由直播间读。
- **没采用归档 v4 的两处改动**：把聊天 tag 1 当主播 UID 过滤（tag 1 其实是频道号 `lTid`，不等时会丢光聊天）、只收注册分组的命令 22。
- **样本**：`fixtures/huya/danmaku/` 下 S11-live、S16-synthetic（`cases.json` 22 组）、S17-reconnect（两条连接同时录，证明 tag 5 跨连接稳定、重连不补发），后来 E01.3 加了 S18-gift（60066 的 27 个礼物）、S19-headline（一次头条通知，空面板）、S20-end（3 条下播通知）。
- **测试**：`packages/live_danmaku/test/huya_test.dart` 现在 57 个（当时 47 个：协议 4、录制对照 1、合成对照 23、连接 19；B-4 后 52 个；E01.3 礼物 +2、C-9/C-10 +3）。其中 22 个由 S16 的 `cases.json` 循环生成（`huya_test.dart:594-597`），所以 `grep -c "test("` 只数到 36。

## 验证

- 自动测试：`huya_test.dart`——注册包和心跳逐字节；S11 回放对照 3.x；S16 22 组合成帧对照 3.x；S17 跨连接同 id、去重闸门只放 189 条、同一观众 2.5 s 内重复每条显示；S18 礼物；S19 面板解析、非面板仍补拉；S20 本房间的下播结束连接、别的主播不理；头条补拉的时序（不阻塞解码、0.6/1.8/4 s、只报一次、排队只补一轮、失败和 3 s 超时后继续、换房间和关闭后丢弃、没有 topSid）；重连退避；本地 WebSocket 服务器端到端。
- 真实接口：2026-09-30 匿名直连 998、60066 各 120 s，聊天 58 和 290 条、热度各 6 次（444 万、362 万左右，与列表热度一致）、礼物 19 和 27 个、60066 有 1 次头条通知（空面板）；2026-10-01 08:14～08:22 同时连 55 个在播房间 8 分钟，3 个房间下播各收到一条 8001，服务端之后不关连接（E01.3 记录“真实环境检查”“附录 C 落地”）。
- 真机：没有单独的真机记录。对应 [真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条（虎牙热门直播间有弹幕、断网后重连），结果一列还是空的。登记表状态是“完成”。

## 留下的问题

- 附录 C-11（贵族开通、续费 uri 1001 显示为通知）：8 分钟 55 个房间没录到样本，没做；[specs/UPGRADES.md](../../../specs/UPGRADES.md) 记为“受阻，未排”。没有任务，录到样本后再开；巡检 [E01.6](../../../E-直播平台/E01-国内五大平台/E01.6-国内五大平台巡检和修复/README.md) 录弹幕时可以顺带留意 1001。
- 同一观众 2.5 s 内重复的弹幕现在每条都显示（和网页一致），想合并的用户打开“折叠重复弹幕”（D01.1 的 `RepeatedDanmakuFilter`，默认关）；这是 B-4 的有意变化，没有任务。
- 主播 UID 为 0 时照样注册 `live:0`（3.x 如此）；E01.3 只给直播中的房间弹幕参数，实际不会发生，没有任务。
- 进场、贵宾席不显示（3.x 也不显示），没有任务；礼物按 B-21 在聊天列表里单独一行显示（C01.2，弹幕设置“在聊天列表显示礼物”可关），不上飞行弹幕。
- 电视端要不要把虎牙弹幕统一成白色（pure_live_TV 的做法）：留给电视端设计 [A17.4](../../../A-界面设计/A17-电视界面/A17.4-电视直播间/README.md)（电视直播间）时决定。
- 真机结果还没有：等 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md) 统一验证或下一次 K90 验证时补第 2 节第 1 条。
