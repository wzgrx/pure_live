# D01.28 六间房 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：已批准升级 31-6“聊天”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）；3.x、归档 v4、pure_live_TV 都没有六间房的聊天，这是新增功能
- 旧编号：M5.27、T06a.28
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身、`SixRoomDanmakuArgs` 和公告 [E02.12 记录](../../../E-直播平台/E02-其他国内平台/E02.12-六间房/record.md)；详细记录 [record.md](record.md)

## 目标

六间房（秀场直播）直播间能看到公聊和飞屏。规格只能来自平台自己：房间页 `v.6.cn/<房间号>` 的 rspack 脚本和匿名实测；归档规格说“需要 `encpass` 等会话参数”，实测更正为游客的 `encpass` 是空的，游客号由客户端随机生成，不要任何会话参数、签名或 Cookie。

## 协议要点

| 项 | 内容 |
|---|---|
| 服务器列表 | 每次握手前取列表里的下一个服务器，用完一轮再 `GET https://v.6.cn/room/getChat.php?rid=<主播用户 id>`（回答 `websock` 是四台 `snbj{g,h}{1,2}.6rooms.com:<端口>`，端口按用户 id 分片 5190～5690，顺序每次打乱）；只接受 `6rooms.com` 的主机 |
| socket | `wss://<主机>:<端口>`，请求头 `Origin: https://v.6.cn` 和 Chrome 140 UA；默认 `dart:io` 握手；按平台 `sixroom` 走代理 |
| 帧 | 文本：服务端第一行是内容的 UTF-8 字节数，之后 `key=value` 行（`\r\n` 分隔）；客户端不写长度行；`receivemessage` 的 `content` 是 Base64（`enc=yes` 时是原始 DEFLATE，Base64 的 `+ / =` 写成 `( ) @`），解出 JSON `{"flag":"001","content":{"typeID":…}}` |
| 登录 | `command=login\r\nuid=<游客号 1800000000～1899999999>\r\nencpass=\r\nroomid=<主播用户 id>\r\n`；`login.success` 才就绪（35 ms 内），就绪时立即发一次心跳；登录时限 6 s |
| 心跳 | 每 16 s 发 `command=sendmessage\r\ncontent=y8vPLwAA\r\n`（`noop`）；不发心跳 20 s 后服务端断开；不发 `priv_info`，所以每个心跳另回 flag 205，忽略 |
| 拒绝 | `login.failed` 换服务器重连，连续第 4 次结束；网页会停掉 socket 的 flag（101 被踢、102 人满、103 付费房、104 密码房、109～114、204 房间关闭、305、306）以 `connectionFailed`（`Chat refused: flag <代码>`）结束 |
| 消息 | 101 公聊（单独或在 110、1413 列表里，1413 最多读 4 层）和 108 飞屏 → 白色聊天：`from` 名字（为空不显示，除非神秘人）、`content`（`&amp;` 和字符引用解开，表情代码 `/狂笑` 原样）、图片消息写 `[AI表情]`、`fid`、`tm`；照网页过滤游客看不到的（`cli` 没有 PC 位、有等级限制）；礼物、进场、系统公告、PK 不报；聊天流里没有人数 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 聊天 | `SixRoomSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/sixroom/sixroom_site.dart:40`），公告“六间房远端聊天尚待接入；……” | `SixRoomDanmakuConnection`（`packages/live_danmaku/lib/src/sites/sixroom.dart:422`）；应用登记在 `apps/pure_live/lib/app/platforms.dart:235` | 有公聊（已做） |
| 协议 | 无 | `SixRoomDanmakuProtocol`（:67）：心跳 16 s、登录时限 6 s、被拒上限 3（:72～80）、心跳帧（:89）、会结束的 flag（:96）、消息类型（:113～123）、`[AI表情]`（:128） | 与网页脚本的 Python 移植逐帧一致 |
| 公告 | 说看不到聊天 | `SixRoomApi.chatNotice` 只留“人数是平台的热度，不是正在观看的人数。” | — |
| 人数 | 热度（`audience.dart` 没有在线人数） | 不变（网页的人数来自 413 信号触发的 HTTP 请求，本实现不拉） | — |

## 结果

- **提交**：3a6825c91（2026-09-30，M5.27）。之后没有改动。
- **期望值**：没有可对照的实现，`fixtures/sixroom/danmaku/page_expected.py` 把网页的 `PCWebSocket`、`D4` 解压、服务器列表、游客过滤、`parsePub` 逐行移植成 Python。S07-live（房间 80518，180 s）197 个收到的帧逐帧一致：加入 1 次、12 条公聊（9 条单独、3 条在 1413 里的主播欢迎语）；录制程序发出的登录和心跳与本实现相同。
- **实测**（2026-09-30 晚高峰匿名直连）：14 个用户 id 的端口都等于 5190 + 100 ×（id mod 6）；`uid=0` 服务端立即断开；同一房间同时开两个连接，发不发 `priv_info` 收到的房间消息逐类型计数相同；281 个 `enc=yes` 帧用 zlib 等级 6 重压后与服务端逐字节相同；五个人气房间各 3 分钟公聊很少。本实现没有直接连真实服务器，用本地服务器测试。
- **样本**：`fixtures/sixroom/danmaku/S07-live`（游客号、观众 id、房间号、名字脱敏；改过的消息按服务端写法重新压缩编码，没改的 184 条与录制逐字节相同）。
- **测试**：`packages/live_danmaku/test/sites/sixroom_test.dart` 27 个（协议 10、录制 3、连接 14，含本地服务器端到端）。

## 验证

- 自动测试：`sixroom_test.dart`。
- 真实接口：见上面的实测。没遇到的：飞屏（108）、公聊列表（110）、图片消息、神秘人、`login.failed`、会结束连接的 flag，都用合成帧。
- 真机：没有单独的真机记录；六间房不在[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 2 节里。

## 留下的问题

- 飞屏（付费，1000 或 2000 六币）当普通聊天行，不带价格；做成醒目留言要先录到样本（候选 1）。
- 表情代码显示成文字，网页的 `FaceSymbols` 有 63 个代码，要加资源（候选 2，归 A 组）。
- 未开播的房间也有参数、能登录，只是没有房间消息；要不要连由直播间决定。
- 录制详情现在不带参数，录制时不带弹幕。
- 礼物（201）不显示。
