# D01.26 酷狗直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 29-5“酷狗弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有酷狗（繁星）的聊天，这是新增功能，规格来自网站房间页（`fanxing.kugou.com/<房间号>`）的脚本和录下的真实帧；后来的附录 B-15（文字染色）、B-16（PK 对方房间的聊天）也在这里
- 旧编号：M5.25、T06a.26
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`KugouLiveDanmakuArgs` 和公告 [E02.10](../../../E-直播平台/E02-其他国内平台/E02.10-酷狗直播/README.md)（弹幕参数见它的 [record.md](../../../E-直播平台/E02-其他国内平台/E02.10-酷狗直播/record.md)）；PK 对方聊天的弹幕层（B-16）[E06.1 第二份记录](../../../E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md)，聊天行的“对方”标签在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/brief.md) 第 3 阶段“酷狗 PK”；礼物显示 [C01.2](../../../C-直播间/C01-进房和房间逻辑/C01.2-直播间第二部分/README.md)（B-21）；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉；详细记录 [record.md](record.md)

## 目标

酷狗直播间能看到公聊、在线人数和本场累计。照网站房间页的做法匿名接入：先调用调度接口拿聊天服务器和令牌（签名是页面脚本里的 MD5 加固定盐，不是混淆的签名 SDK），再连 WebSocket 发匿名登录包。后来（B-15）聊天文字按网页染色，（B-16）PK 时对方房间的聊天也上报并带来源房间。

## 协议要点

| 项 | 内容 |
|---|---|
| 调度 | `GET https://fx1.service.kugou.com/socket_scheduler/pc/binary/v2/address.jsonp`，参数 `_p=0`、`_v=7.0.0`、`pv=20240801`、`rid`、`clienttime`、`cid=100`、`at=102`，`sign` = 参数按键名排序拼成 `k=v&…` 接 `$_fan_xing_$` 的 MD5 第 8～23 位（`sign`、`dispatchUrl`）；回答 3 个主机（`wss://chatwss…kugou.com/acksocket`）、`soctoken`、`age`（5 分钟）；开始时最多 3 次（间隔 1.5、4.5 s，网页的退避），都失败以 `connectionFailed`（`dispatch: …`）结束；调度拒绝（签名错 1100014、人机验证 1100007）直接结束 |
| 帧 | 二进制：客户端 18 字节头（魔数 `100`、版本 3、类型 1、命令、长度），服务端 26 字节头；内容是 protobuf `SocketProtocol.Message`（gzip 或 snappy 压缩，snappy 按网页的 snappyjs 自己解；`codec` 1 是 protobuf、0 是 JSON），解压后上限 4 MiB；文本帧不读 |
| 登录 | 打开后发 201（这次运行加入过之后的新 socket 发 2201 带上次的 `socsid`）`LoginRequest`（`kugouid` 0、`soctoken`、每次运行随机的 `sid` 和 `deviceNo`）；901 状态 `type 1, status 1` 才就绪（`type 4` 先到，不算）；加入超时 10 s，超时换下一个主机 |
| 心跳 | 每 10 s 发 4 字节 `64 00 01 00`，服务端每个都回；无消息 90 s（框架默认） |
| 令牌 | 令牌留给之后的 socket 用，直到超过 `age`、被 622 拒绝、或发出后没等到登录回答 socket 就断了：下次握手前重新调度（`_Handshake._usable`）；重新调度的请求失败算握手失败（框架退避，最多 8 次），被拒直接结束；登录被拒重连，连续第 4 次以 `connectionFailed`（`Chat refused: 901 errorno …`）结束，加入一次清零 |
| 消息 | 501 公聊：私聊（`privateType` 1）、有 `receiverid`、负发送者、别的房间丢；文字和名字去掉 U+2027～U+202E；用户 id 是信封 `senderid`，神秘嘉宾（`sinfo.ck` 1）用化名编号 `ckid`；等级是财富等级 `senderrichlevelV2`（没有时 `senderrichlevel`）；点亮的粉丝牌（`intimacyVo` 的 `nameplate`、`level`）；id 是信封 `msgId` 或 `<发送者>:<seq>`；时间是信封 `time`。B-15 颜色：粉丝团 8 级以上、小守护（`littleGuard.l`）、守护（`userGuard.g`）橙 `#ff9900`，神秘嘉宾金 `#cc9900`，其他和没有 `ext` 的白色（网页开关“开”的那一支）。B-16：400305 且 `source.tags & 1`、来源房间不是本房间的，按公聊读、带 `sourceRoomId` 上报（颜色照样）。301005（`actionId` `roomAuNumber`，约每分钟）的 `count` → 在线、`visited` → 本场累计（`hot` 不报）。礼物（601）不报，但信封要求时照网页回 211 确认（不确认服务端会重发两次） |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `KugouLiveSite.getDanmaku() => EmptyDanmaku()`（`core/site/kugoulive/kugou_live_site.dart:42`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `KugouLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/kugoulive.dart:904`）：时序（:931）、开始时的调度间隔（:938）、`target`（:946）调度、`onOpen`（:985）发登录、`onData`（:1006）回确认和上报、`_refused`（:1032）、心跳帧（:1047）；握手 `_Handshake`（:1060，`_usable` :1095、`renew` :1105）；一次运行的 `_Chat`（:1127）；应用登记在 `apps/pure_live/lib/app/platforms.dart:233` | 有聊天和人数（已做） |
| 协议 | 无 | `KugouLiveDanmakuProtocol`（:132）：调度路径和盐（:135～138）、命令号（:159～184，含 400305 :178、622 :184）、心跳 10 s、加入超时 10 s、令牌 5 分钟、被拒上限 3（:187～198）、解压上限（:201）、`sign`（:227）、`dispatchUrl`（:235）、`grant`（:272）、`decode`（:409）、`chat`（:593）、`audience`（:642）、颜色（:666、:669）、`textColor`（:684） | 与网页读法逐帧一致 |
| 参数和人数 | 无 | `live_core` 新加 `KugouLiveDanmakuArgs(roomId)`（`packages/live_core/lib/src/sites/kugoulive/kugoulive_api.dart:103`，直播中的进房和录制详情）；`audience.dart:239` 酷狗 `hasTotalViewers` 改为 true（仍是 `roomList`） | 进房后实时人数和本场累计 |
| 公告 | `kugoulive_chat_notice`“酷狗远端聊天尚待接入；viewerNum/getViewerNum 按当前观看人数展示……”（`kugou_live_site.dart:93`，`assets/translations/zh.json:1937`） | `KugouLiveApi.chatNotice`（`kugoulive_api.dart:174`）只说明人数：“人数是正在观看的人数，没有时显示热度；粉丝数单独显示。” | 3.x 存下的旧公告导入时清掉（J02.1） |

## 结果

- **提交**：8fe5c32bb（2026-09-30，本任务的代码），5e86cf795（2026-10-01，B-15 文字染色），7f8ee2553（2026-10-02，B-16 对方房间聊天，E06.1 的弹幕层）。另外 docs v1 改编号时动过注释（c613b73f9、9dfbb424d）。
- **期望值**：没有可对照的实现，`fixtures/kugoulive/danmaku/web_expected.py` 用 Python 标准库独立重写房间页脚本的读法（调度签名、`decodePb`、显示规则、粉丝牌、人数，B-15 时补了 `content_color`）。S07-live（房间 51049168，300 s）195 帧逐帧一致：29 个心跳回答、37 条聊天、5 个人数帧；调度地址（含签名）逐字节重算得出；登录包与录制逐字节相同。
- **实测**（2026-09-30 匿名直连）：空令牌或乱写的令牌服务端立即 `Bye` 关闭；令牌 6 分钟后仍可用、20 分钟后 622；连着 26 分钟没断；不确认的礼物来 3 次；B-15 时 15 个房间各 30 分钟 1,744 条聊天里 854 橙、49 金、841 白，本实现与网页规则一致。
- **样本**：`fixtures/kugoulive/danmaku/` 的 S07-live、S08-refused（622）、S09-pk-chat（对方房间）、S10-chat-colours、S11-mystery-colour。
- **测试**：`packages/live_danmaku/test/sites/kugoulive_test.dart` 现在 36 个（没有循环生成的用例）：做完时 30 个，B-15 加 6 个；B-16 没有加用例，只把原来“对方房间的聊天不报”的两个用例改成“标出对方并照网页染色”。`live_core` 的酷狗测试 +1。

## 验证

- 自动测试：`kugoulive_test.dart` 覆盖调度签名和地址、回答的拒绝、帧头和 gzip/snappy、登录包、状态帧、公聊的过滤和各字段、粉丝牌、人数、礼物确认；S07～S11 逐帧对照网页读法（S10、S11 逐条对颜色）；合成帧的颜色边界（等级、守护的各种值、神秘嘉宾、JSON 聊天）；连接的调度重试、令牌复用和重新调度、622、连续拒绝结束、本地服务器端到端（路径、`Origin`、UA、登录和心跳、录下的状态帧和聊天）。
- 真实接口：2026-09-30 跑过（见上面的实测）。本实现没有直接连真实服务器，登录包与实测发出的逐字节相同。没实测到的：回礼物确认的效果、JSON 编码的聊天、开关“关”的那一支颜色。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有酷狗，E02.10 也写“没有在 K90 上专门看过”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有酷狗弹幕的条目。真机上要看：聊天里橙色、金色的文字；人数和本场累计随弹幕变化；PK 时对方房间的聊天有没有“对方”标记（E06.2 做完后）。

## 留下的问题

- PK 对方房间的聊天现在混在本房间聊天里显示，聊天行的“对方”标签还没做：E06.2 第 3 阶段“酷狗 PK”（暂停中，半成品见它的 brief）。
- 按房间的公聊限制隐藏聊天：不做（附录 B-17：要另取房间限制和管理员名单，只会让用户少看到消息）。
- 文字表情 `[/抱抱]` 显示成文字：没有任务。网页的 `emotion` 模块有对照表，v3 没有酷狗的表情资源；要做时在本平台协议层填 `LiveMessage.emotes`（显示 D03.2 已做）。
- 礼物、进场不显示：没有任务。B-21 的礼物显示（C01.2）只显示已上报礼物的平台，本平台要先解 `GiftEffectSocketMsg.Content`。
- 网页开关“关”的那一支颜色（频道房间、`isLiveRoom` 的房间：小守护橙、守护紫 `#9955ee`）没有实现：没有任务，本连接连的普通房间（`at` 102）都是“开”。
- 网页的 `replaceUnicode` 会删掉所有半角空格（像是写错了），这里保留普通空格：有意差异，不改。
- 3.x 存下的旧公告：已由 J02.1 处理，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
