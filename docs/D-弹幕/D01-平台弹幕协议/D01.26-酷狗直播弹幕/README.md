# D01.26 酷狗直播 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 29-5“酷狗弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有酷狗（繁星）的聊天，这是新增功能
- 旧编号：M5.25、T06a.26
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`KugouLiveDanmakuArgs` 和公告 [E02.10 记录](../../../E-直播平台/E02-其他国内平台/E02.10-酷狗直播/record.md)；PK 对方聊天的弹幕层 [E06.1 第二份记录](../../../E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md)，聊天行的“对方”标签在 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md)；详细记录 [record.md](record.md)

## 目标

酷狗直播间能看到公聊、在线人数和本场累计。照网站房间页（`fanxing.kugou.com/<房间号>`）的做法匿名接入：先调用调度接口拿聊天服务器和令牌（签名是页面脚本里的 MD5 加固定盐，不是混淆的签名 SDK），再连 WebSocket 发匿名登录包。后来（B-15）聊天文字按网页染色，（B-16）PK 时对方房间的聊天也上报并带来源。

## 协议要点

| 项 | 内容 |
|---|---|
| 调度 | `GET https://fx1.service.kugou.com/socket_scheduler/pc/binary/v2/address.jsonp`，参数 `_p=0`、`_v=7.0.0`、`pv=20240801`、`rid`、`clienttime`、`cid=100`、`at=102`，`sign` = 参数按键名排序拼成 `k=v&…` 接 `$_fan_xing_$` 的 MD5 第 8～23 位；回答 3 个主机（`wss://chatwss…kugou.com/acksocket`）、`soctoken`、`age`（5 分钟）；开始最多 3 次（1.5、4.5 s） |
| 帧 | 二进制：客户端 18 字节头（`100`、版本 3、类型 1、命令、长度），服务端 26 字节头；内容是 protobuf `SocketProtocol.Message`（gzip 或 snappy 压缩，`codec` 1 是 protobuf、0 是 JSON） |
| 登录 | 打开后发 201（加入过之后的新 socket 发 2201 带上次的 `socsid`）`LoginRequest`（`kugouid` 0、`soctoken`、随机 `sid` 和 `deviceNo`）；901 状态 `type 1, status 1` 才就绪（`type 4` 不算）；加入超时 10 s |
| 心跳 | 每 10 s 发 4 字节 `64 00 01 00`；无消息 90 s |
| 令牌 | 超过 `age`、被 622 拒绝、发出后没等到回答就断了：下次握手前重新调度；登录被拒连续第 4 次以 `connectionFailed`（`Chat refused: 901 errorno …`）结束；调度拒绝（签名错 1100014、人机验证 1100007）直接结束 |
| 消息 | 501 公聊（私聊、负发送者、别的房间丢；去掉 U+2027～U+202E；神秘嘉宾用化名编号；财富等级；点亮的粉丝牌；id 是信封 `msgId` 或 `<发送者>:<seq>`）；B-15 颜色：粉丝团 8 级以上、小守护、守护橙 `#ff9900`，神秘嘉宾金 `#cc9900`；B-16：400305 且 `source.tags & 1` 的对方房间聊天带 `sourceRoomId` 上报；301005 的 `count` → 在线、`visited` → 本场累计；礼物（601）不报但照网页回 211 确认（不确认服务端会重发两次） |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `KugouLiveSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/kugoulive/kugou_live_site.dart:42`），提示一次“尚未接入” | `KugouLiveDanmakuConnection`（`packages/live_danmaku/lib/src/sites/kugoulive.dart:904`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:233` | 有聊天和人数（已做） |
| 协议 | 无 | `KugouLiveDanmakuProtocol`（:132）：调度路径和盐（:135～138）、命令号（:159～184）、心跳 10 s、加入超时 10 s、令牌 5 分钟、被拒上限 3（:187～198）；snappy 按网页的 snappyjs 自己解 | 与网页读法逐帧一致 |
| 参数和人数 | 无 | `live_core` 新加 `KugouLiveDanmakuArgs(roomId)`（直播中的进房和录制详情）；`audience.dart` 酷狗 `hasTotalViewers` 改为 true | 进房后实时人数 |
| 公告 | 说看不到聊天 | `KugouLiveApi.chatNotice` 只说明人数 | — |

## 结果

- **提交**：8fe5c32bb（2026-09-30，M5.25），5e86cf795（2026-10-01，B-15 文字染色），7f8ee2553（2026-10-02，B-16 对方房间聊天，E06.1）。
- **期望值**：没有可对照的实现，`fixtures/kugoulive/danmaku/web_expected.py` 用 Python 标准库独立重写房间页脚本的读法（调度签名、`decodePb`、显示规则、粉丝牌、人数、颜色）。S07-live（房间 51049168，300 s）195 帧逐帧一致：29 个心跳回答、37 条聊天、5 个人数帧；调度地址（含签名）逐字节重算得出；登录包与录制逐字节相同。
- **实测**（2026-09-30 匿名直连）：空令牌或乱写的令牌服务端立即 `Bye` 关闭；令牌 6 分钟后仍可用、20 分钟后 622；连着 26 分钟没断；不确认的礼物来 3 次；B-15 时 15 个房间各 30 分钟 1,744 条聊天里 854 橙、49 金、841 白，本实现与网页规则一致。
- **样本**：`fixtures/kugoulive/danmaku/` 的 S07-live、S08-refused（622）、S09-pk-chat（对方房间）、S10-chat-colours、S11-mystery-colour。
- **测试**：`packages/live_danmaku/test/sites/kugoulive_test.dart` 做完时 30 个，B-15 后 36 个，B-16 又加了对方房间的用例；`live_core` 的酷狗测试 +1。

## 验证

- 自动测试：`kugoulive_test.dart`（本地服务器端到端：路径、Origin、UA、登录和心跳、录下的状态帧和聊天）。
- 真实接口：见上面的实测。本实现没有直接连真实服务器，登录包与实测发出的逐字节相同。没实测到的：回礼物确认的效果、JSON 编码的聊天、开关“关”的那一支颜色。
- 真机：没有单独的真机记录；酷狗不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。真机上要看：聊天里橙色、金色的名字；PK 时对方房间的聊天有没有“对方”标记（E06.2 做完后）。

## 留下的问题

- PK 对方房间的聊天现在混在本房间聊天里上报，聊天行的“对方”标签还没做（E06.2 第 3 阶段，暂停中）。
- 不按房间的公聊限制隐藏聊天（附录 B-17，决定不做）。
- 文字表情 `[/抱抱]` 显示成文字（网页的 `emotion` 模块有对照表，归 A 组）。
- 礼物、进场不显示；礼物显示要解 `GiftEffectSocketMsg.Content`。
- 网页的 `replaceUnicode` 会删掉所有半角空格（像是写错了），这里保留普通空格，是有意差异。
