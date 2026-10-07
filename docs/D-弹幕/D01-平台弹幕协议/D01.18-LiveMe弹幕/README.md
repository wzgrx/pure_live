# D01.18 LiveMe 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（现在是“受阻”）
- 类型：平台
- 来源：已批准升级 21-9“LiveMe 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)，状态“受阻”）；3.x 没有 LiveMe 弹幕
- 旧编号：M5.17、T06a.18
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身 [E03.8 记录](../../../E-直播平台/E03-海外平台/E03.8-LiveMe/record.md)（本场直播 id `LiveMeRoomData.videoId`、公告 `liveme_chat_notice`）；账号和登录在 K 组（现在没有 LiveMe 登录）；调查记录 [record.md](record.md)；任务书 [brief.md](brief.md)

## 目标

让 LiveMe（海外秀场直播）直播间能看到聊天。调查后的结论是**受阻**：LiveMe 的聊天室要先用登录账号登录平台自己的 IM 才能进，网页端没有游客通道；本项目不支持 LiveMe 登录、也不绕过平台的限制，所以没有写连接代码，界面照 3.x 只提示一次“不支持弹幕”。

## 协议要点（调查所得，没有实测，没有样本）

| 项 | 官网网页端的做法 |
|---|---|
| 服务器 | `webim1.fusionv.com`、`webim2.fusionv.com`（443），一个连不上换下一个 |
| 传输 | socket.io-client 2（Engine.IO 3），只用 WebSocket：`wss://webim1.fusionv.com/live.me/?cmcm=3&EIO=3&transport=websocket`；最多重连 5 次，间隔 3 s |
| 事件 | 客户端发 `LOGIN`、`LIVE`、`PULL`、`LOGOUT`；服务端发 `SESSIONID`、`LOGIN`、`LIVE`、`CHAT`、`GATEWAY`、`PULL`；载荷是二进制 protobuf |
| 登录（卡在这里） | 连上后发 `LOGIN`（protobuf `User`）：`userid` 是登录用户的 uid、`token` 是账号的登录令牌、`deviceid` 是 `eb000001-<设备号>`；服务端回 `Ack.type` 1 且 `statecode` 0 才算登录成功 |
| 进聊天室 | 登录成功后才发 `LIVE`（`IMMessage` 的 `type` 20、`subtype` 61，`to` 是本场直播 id `vid`，等于直播信息的 `TCRoomId`）；客户端在登录前自己不发（日志“未登录，无法进行房间操作”） |
| 消息 | `LIVE {cmd: 20}`、`{cmd: 50}`、`GATEWAY {cmd: 60}`；`subtype` 80 的消息 `content` 是 JSON 文字，`extend1` 是消息名（`app:whitelvmsgcontent` 等，含义没有样本核对） |
| 保活 | 服务端发 `PULL {cmd: -100}`，客户端回 `PULL` |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `LiveMeSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/liveme/liveme_site.dart:38`），直播间提示一次 `remote_danmaku_not_integrated` | 不在弹幕平台表里（`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 LiveMe 受阻），`DanmakuRegistry.supports('liveme')` 为假；直播间提示一次 `live_play_danmaku_unsupported`“该平台暂不支持弹幕”（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～821`） | 受阻：解除条件见下 |
| 公告 | “LiveMe 远端聊天尚待接入；……” | E03.8 改成“这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。”（`packages/live_core/lib/src/sites/liveme/liveme_api.dart:422`） | 仍然符合实际 |
| 参数 | 无 | 平台层有本场直播 id `LiveMeRoomData.videoId`；没有加 `LiveMeDanmakuArgs`（只有直播 id 进不了聊天室） | 解除后再加 |
| 代码 | 无 | `packages/live_danmaku/lib/src/sites/liveme.dart` 没有创建，`live_danmaku.dart` 没有导出 | — |

## 结果

- **提交**：2d1994160（2026-09-29，调查结论和文档，没有代码）。
- **受阻的原因**（record.md“受阻的原因”）：
  1. 官网的 IM 连接只在登录后建立（`app-im-kit` 监听登录状态，没登录就销毁 IM）；
  2. 直播间只在登录分支里进聊天室，游客走 `anonymous-user` 路径只放流；
  3. IM 登录用的是账号的 uid 和登录令牌，网页端没有给游客发 IM 令牌的接口。
- **查过的其他路子都不通**：直播信息里的 `msgfile` 在播时 404（回放用）；`imapi.liveme.com` 只有私信接口且要签名；分享页和手机版是同一个单页应用；旧版 SDK `im.js` 仍要令牌；在播直播的 `chatSystem` 全是 `"3"`（自有 IM）；App 端要抓包和签名，按规则不做。
- **没做的**：没有用空的 uid 和令牌去试 IM 服务器（那就是绕过平台“登录后才能进聊天室”的限制），没有注册账号，没有连过 IM 服务器（只做了 DNS 解析）。
- **测试**：没有代码，没有测试；当时门禁通过。

## 验证

- 自动测试：无（没有代码）。平台表不登记 LiveMe，`DanmakuRegistry` 的测试覆盖“没登记的平台返回 `EmptyDanmakuConnection`”（`packages/live_danmaku/test/connection_test.dart`）。
- 真机：要看的只有一条：进一个 LiveMe 直播间，聊天区只出现一次“该平台暂不支持弹幕”，不出现“连接中”。

## 留下的问题

- 解除条件：本项目决定支持 LiveMe 账号登录（新功能，按 D-026 先在 V01 提议并经用户确认，再在 K 组开登录任务），或者 LiveMe 开放了游客聊天通道（定期巡检时复查官网脚本，见 E07.1）。详见 [brief.md](brief.md)。
- 4.x 的“不支持弹幕”提示文字和 3.x 不同（3.x 还提示可以开本地互动），属于直播间的提示文字，不在本任务里。
