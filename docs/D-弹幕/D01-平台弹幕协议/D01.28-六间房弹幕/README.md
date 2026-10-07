# D01.28 六间房 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 31-6“聊天”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有六间房的聊天，这是新增功能，规格只能来自平台自己：房间页 `v.6.cn/<房间号>` 的 rspack 脚本和匿名实测
- 旧编号：M5.27、T06a.28
- 相关：决定 D-001、D-017；框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`SixRoomDanmakuArgs` 和公告 [E02.12](../../../E-直播平台/E02-其他国内平台/E02.12-六间房/README.md)（弹幕参数见它的 [record.md](../../../E-直播平台/E02-其他国内平台/E02.12-六间房/record.md)）；表情图片的显示 [D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)；3.x 存下的旧公告由 [J02.1](../../../J-设置和数据/J02-存储和加密/J02.1-存储和迁移/record.md) 导入时清掉；详细记录 [record.md](record.md)

## 目标

六间房（秀场直播）直播间能看到公聊和飞屏。归档规格说“需要 `encpass` 等会话参数”，实测更正为：游客的 `encpass` 是空的，游客号由客户端随机生成，不要任何会话参数、签名或 Cookie。

## 协议要点

| 项 | 内容 |
|---|---|
| 服务器列表 | 交给 `LiveSocket` 的是名义地址（列表请求本身），每次握手取列表里的下一个服务器（`_Handshake.call`），用完一轮再 `GET https://v.6.cn/room/getChat.php?rid=<主播用户 id>`（回答 `websock` 是四台 `snbj{g,h}{1,2}.6rooms.com:<端口>`，端口按用户 id 分片：5190 + 100 ×（id mod 6），顺序每次打乱）；只接受 `6rooms.com` 的主机；列表请求失败算握手失败（框架退避，最多 8 次后 `reconnectsExhausted`） |
| socket | `wss://<主机>:<端口>`，请求头 `Origin: https://v.6.cn` 和 Chrome 140 UA；默认 `dart:io` 握手；按平台 `sixroom` 走代理 |
| 帧 | 文本：服务端第一行是内容的 UTF-8 字节数，之后 `key=value` 行（`\r\n` 分隔，后值覆盖前值）；客户端不写长度行；`receivemessage` 的 `content` 是 Base64（`enc=yes` 时是原始 DEFLATE，Base64 的 `+ / =` 写成 `( ) @`），解出 JSON `{"flag":"001","content":{"typeID":…}}`；解压后上限 4 MiB |
| 登录 | `command=login\r\nuid=<游客号>\r\nencpass=\r\nroomid=<主播用户 id>\r\n`；游客号在 1800000000～1899999999 里随机，一次连接里不变（换服务器也不变）；`login.success` 才就绪（实测 35 ms 内），就绪时立即发一次心跳；登录时限 6 s，超时换下一个服务器 |
| 心跳 | 每 16 s 发 `command=sendmessage\r\ncontent=y8vPLwAA\r\n`（`noop`）；不发心跳 20 s 后服务端断开；不发 `priv_info`，所以每个心跳另回 flag 205，忽略；无消息 90 s（框架默认） |
| 拒绝 | `login.failed` 换服务器重连，连续第 4 次以 `connectionFailed`（`Chat refused: login.failed`）结束，加入一次清零；网页会停掉 socket 的 flag（101 被踢、102 人满、103 付费房、104 密码房、109～114 封禁、204 房间关闭、305 等级不够、306 要重新登录）以 `connectionFailed`（`Chat refused: flag <代码>[: 文字]`）结束；参数不对：`connectionFailed`（`No usable room or broadcaster`），不请求 |
| 消息 | 101 公聊（单独，或在 110 列表里，或在 1413 批量里，1413 最多嵌套 4 层）和 108 飞屏 → 白色聊天：名字 `from`（为空不显示，除非 `supremeMystery` 1）、`content`（`&amp;` 和字符引用解开，表情代码 `/狂笑` 原样）、图片消息（`picEmoji.pic`）写 `[AI表情]`、用户 id `fid`、时间 `tm`（秒），没有消息 id；照网页 `Room.Msg.get` 过滤游客看不到的（`cli` 设了但没有 PC 位 1、有财富或明星等级限制）；礼物（201）、进场、系统公告、PK 不报；聊天流里没有人数 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `SixRoomSite.getDanmaku() => EmptyDanmaku()`（`core/site/sixroom/sixroom_site.dart:40`）；进房时弹幕区一条状态“此平台的远端弹幕尚未接入……”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | `SixRoomDanmakuConnection`（`packages/live_danmaku/lib/src/sites/sixroom.dart:422`）：时序（:444）、`target`（:454）检查参数和定游客号、`onOpen`（:470）发登录、`onData`（:479）处理拒绝、加入和消息、心跳帧（:512）；握手 `_Handshake`（:526，`call` :535）；一次运行的 `_Chat`（:561）；应用登记在 `apps/pure_live/lib/app/platforms.dart:235` | 有公聊（已做） |
| 协议 | 无 | `SixRoomDanmakuProtocol`（:67）：心跳 16 s、登录时限 6 s、被拒上限 3（:72～80）、请求头（:85）、心跳帧（:89）、会结束的 flag（:96）、消息类型（:113～123）、`[AI表情]`（:128）、解压上限和嵌套上限（:131、:134）、`serverRequest`（:145）、`servers`（:168）、`guestId`（:202）、`login`（:206）、`fields`（:210）、`payload`（:218）、`decode`（:240）、`messages`（:286）、`shownToGuests`（:318）、`chat`（:356）、`fly`（:369） | 与网页脚本的 Python 移植逐帧一致 |
| 参数 | 无 | `SixRoomDanmakuArgs(roomId, userId)`（`packages/live_core/lib/src/sites/sixroom/sixroom_api.dart:250`）：只在进房详情里有（`sixroom_site.dart:407`），刷新（:412）和录制详情（:416）不带 | — |
| 公告 | `sixroom_chat_notice`“六间房远端聊天尚待接入；大厅 count 保留为平台热度……”（`sixroom_site.dart:89`，`assets/translations/zh.json:1948`） | `SixRoomApi.chatNotice`（`sixroom_api.dart:318`）只留“人数是平台的热度，不是正在观看的人数。”；没有留 `legacyChatNotice`（E02.12 已换掉，对照测试列为有意差异） | 3.x 存下的旧公告导入时清掉（J02.1） |
| 人数 | 热度 | `audience.dart:256` 仍是 `unsupported`（只有热度）；网页的人数来自 413 信号触发的 HTTP 请求，本实现不拉 | — |

## 结果

- **提交**：3a6825c91（2026-09-30，本任务的代码）。之后只有 docs v1 改编号时动过注释（c613b73f9、9dfbb424d），行为没有变。
- **期望值**：没有可对照的实现，`fixtures/sixroom/danmaku/page_expected.py` 把网页的 `PCWebSocket`、`D4` 解压、服务器列表、游客过滤、`parsePub` 逐行移植成 Python。S07-live（房间 80518，180 s）197 个收到的帧逐帧一致：加入 1 次、12 条公聊（9 条单独、3 条在 1413 里的主播欢迎语）；录制程序发出的登录和心跳与本实现相同。
- **实测**（2026-09-30 晚高峰匿名直连）：14 个用户 id 的端口都等于 5190 + 100 ×（id mod 6）；`uid=0` 服务端立即断开；同一房间同时开两个连接，发不发 `priv_info` 收到的房间消息逐类型计数相同；281 个 `enc=yes` 帧用 zlib 等级 6 重压后与服务端逐字节相同；五个人气房间各 3 分钟公聊很少。本实现没有直接连真实服务器，用本地服务器测试。
- **样本**：`fixtures/sixroom/danmaku/S07-live`（游客号、观众 id、房间号、名字脱敏；改过的消息按服务端写法重新压缩编码，没改的 184 条与录制逐字节相同）。
- **测试**：`packages/live_danmaku/test/sites/sixroom_test.dart` 现在 27 个（和做完时一样，没有循环生成的用例）：协议 10、录制 3、连接 14（含本地服务器端到端）。`live_core` 的六间房测试 54 个照常通过（公告用例多断言了新文字）。

## 验证

- 自动测试：`sixroom_test.dart` 覆盖地址、请求头、心跳帧和时序常量、游客号范围、服务器列表的各种回答、帧的行和载荷（压缩与否、`@` 填充、坏 Base64、坏 DEFLATE、超过 4 MB）、13 个会结束的 flag、公聊和飞屏各字段、110 和 1413 嵌套、`cli` 的 14 种值和等级限制；录制逐帧对照网页移植、用连接重放；连接的换服务器（游客号不变、四个用完再取列表）、登录超时、`login.failed` 第 4 次结束、会结束的 flag、列表请求失败重试、关闭时取消请求、本地服务器端到端。
- 真实接口：2026-09-30 跑过（见上面的实测）。没遇到的：飞屏（108）、公聊列表（110）、图片消息、神秘人、`login.failed`、会结束连接的 flag，都用合成帧；长时间连接实测最长 3 分钟。
- 真机：没有单独的真机记录；S02.2、S02.3 的记录里没有六间房，E02.12 也写“没有在 K90 上专门看过”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节第 1 条只列国内五大平台，没有六间房弹幕的条目。真机上要看：进一个在播的六间房直播间，聊天区“已连接”，主播欢迎语和观众公聊出现，长时间看不反复重连。

## 留下的问题

- 飞屏（付费，1000 或 2000 六币）当普通聊天行，不带价格：没有任务（record.md 候选 1：做成醒目留言要先录到带价格的样本）。
- 表情代码 `/狂笑` 显示成文字：没有任务（record.md 候选 2）。网页的 `FaceSymbols` 有 63 个代码，图片在 `//vr1.xiu123.cn/images/face/face_v5/`，v3 没有打包六间房的表情；要做时加资源并在本平台协议层填 `LiveMessage.emotes`（显示 D03.2 已做）。
- 未开播的房间也有参数、能登录，只是没有房间消息：没有任务，要不要连由直播间按房间状态决定（现在只在直播中或画面受限时连）。
- 录制详情（`sixroom_site.dart:416`）不带弹幕参数。**影响的是多画面**：多画面用录制详情建格子（`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:486-490`），参数为空就不连（`:865`），所以多画面里的六间房没有弹幕；录制本身不受影响（录制的弹幕走 `getRoomDetail`，`apps/pure_live/lib/app/recording.dart:52`；2026-10-07 H、I 组更正）。→ [E05.4](../../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md) 第 2 阶段（录制详情也带 `SixRoomDanmakuArgs`，AcFun、克拉克拉同样）。
- 礼物（201）不显示：没有任务。B-21 的礼物显示（C01.2）只显示已上报礼物的平台，本平台要先在协议层解 201。
- 3.x 存下的旧公告：已由 J02.1 处理，真机核对在 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)。
- 没有真机结果：没有任务；真机清单没有本平台弹幕的条目（见“验证”）。
