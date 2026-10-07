# D01.18 LiveMe 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（受阻，2026-09-29，提交 2d1994160；登记表说明“要登录才能连弹幕，调查完成”）
- 类型：平台
- 来源：已批准升级 21-9“LiveMe 弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md) 第 160 行，状态“受阻”）；3.x 有 LiveMe 这个平台但没有弹幕
- 旧编号：M5.17、T06a.18
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；平台本身 [E03.8 记录](../../../E-直播平台/E03-海外平台/E03.8-LiveMe/record.md)（本场直播 id `LiveMeRoomData.videoId`、公告 `chatNotice`）；账号和登录在 [K01.1](../../../K-账号和登录/K01-账号和登录方式/K01.1-账号与登录/record.md)（现在没有 LiveMe 登录）；新功能流程 D-026 和 [V01](../../../V-需求和反馈/V01-新功能提议/README.md)；平台巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)；同样受阻的 [D01.19 TikTok](../D01.19-TikTok弹幕/README.md)；调查记录 [record.md](record.md)；任务书 [brief.md](brief.md)

## 目标

让 LiveMe（海外秀场直播）直播间能看到聊天。调查后的结论是**受阻**：LiveMe 的聊天室要先用登录账号的 uid 和登录令牌登录平台自己的 IM 才能进，官网网页端没有游客通道。本项目不支持 LiveMe 登录，D01 平台弹幕任务的统一规则也不允许绕过平台的访问限制（不用空的 uid、令牌去试 IM 服务器，不抓 App 的包），所以没有写连接代码；直播间照 3.x 不连接，只说明这个平台没有弹幕。

## 协议要点（调查所得，没有实测，没有样本）

出处是官网网页脚本 `www.liveme.com/static/CLaEtC7T.js`（入口）和 `CYslo3Yc.js`（直播间），2026-09-29 下载；函数名是压缩后的名字，官网更新后会变。详见 [record.md](record.md)“查明的协议”。

| 项 | 官网网页端的做法 |
|---|---|
| 服务器 | `webim1.fusionv.com`、`webim2.fusionv.com`（配置写端口 80，https 页面用 443），一个连不上换下一个（`IMKit.createConnection`、`reconnectConnection`） |
| 传输 | socket.io-client 2（Socket.IO 协议 4、Engine.IO 3），只用 WebSocket：`wss://webim1.fusionv.com/live.me/?cmcm=3&EIO=3&transport=websocket`；最多重连 5 次，间隔 3 s，都失败后换服务器 |
| 事件 | 客户端发 `LOGIN`、`LIVE`、`PULL`、`LOGOUT`；服务端发 `SESSIONID`、`LOGIN`、`LIVE`、`CHAT`、`GATEWAY`、`PULL`；除 `SESSIONID`、`LOGOUT` 外载荷是二进制 protobuf（Socket.IO 二进制事件），服务端发 `{cmd, body}` |
| 登录（卡在这里） | 连上后发 `LOGIN`（protobuf `User`）：`userid` 是登录用户的 uid、`token` 是账号的登录令牌、`appid` `liveme`、`devicetype` 1（WEB）、`deviceid` 是 `eb000001-<设备号>`；服务端回 `LOGIN {cmd: 2}`，`Ack.type` 1 且 `statecode` 0 才算登录成功 |
| 进聊天室 | 登录成功后才发 `LIVE`（`IMMessage` 的 `type` 20 ROOM、`subtype` 61 ROOM_LOGIN，`to` 是本场直播 id `vid`，等于直播信息的 `TCRoomId`）；客户端在登录前自己不发（日志“sendRoomEvent: 未登录，无法进行房间操作”）；`Ack.type` 6 是进了聊天室 |
| 消息 | `LIVE {cmd: 20}`（一条 `IMMessage`）、`{cmd: 50}`（`MessageList`）、`GATEWAY {cmd: 60}`；`subtype` 80（ROOM_DIY）的 `content` 是 JSON 文字，`extend1` 是消息名（`app:whitelvmsgcontent`、`app:lowlvmsgcontent`、`app:livestatmsgcontent`、`app:livevideostopmsgcontent` 等，含义没有样本核对）；`deviceid` 等于会话号 `SESSIONID` 的是自己发的 |
| 保活 | 服务端发 `PULL {cmd: -100}`，客户端回 `PULL`；另有 Engine.IO 的 ping |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有 LiveMe 这个平台但没有弹幕：`LiveMeSite.getDanmaku() => EmptyDanmaku()`（`core/site/liveme/liveme_site.dart:38`）；直播间见到 `EmptyDanmaku` 只提示一次 `remote_danmaku_not_integrated`“此平台的远端弹幕尚未接入；可在设置中开启本地互动，仅在本机显示。”（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | 不在弹幕平台表里（`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 LiveMe 因登录受阻），`DanmakuRegistry.supports('liveme')` 为假（`packages/live_danmaku/lib/src/registry.dart:75`），`connectionFor` 给 `EmptyDanmakuConnection`（:79、:13）；直播间不连接（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～822`），聊天区显示“LiveMe的直播间没有弹幕 / 醒目留言、弹幕设置、屏蔽管理照常可用”（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:287～295`），列表里另有一行“该平台暂不支持弹幕” | 受阻：解除条件见“留下的问题” |
| 公告 | `liveme_chat_notice`“LiveMe 远端聊天尚待接入；热度、当前观看和累计观看分别展示。”（`assets/translations/zh.json:1868`，`core/site/liveme/liveme_site.dart:82`） | E03.8 改成“这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。”（`packages/live_core/lib/src/sites/liveme/liveme_api.dart:422`，:840 放进每个房间） | 仍然符合实际，不改 |
| 参数 | 无 | 平台层有本场直播 id `LiveMeRoomData.videoId`（等于聊天室 id `TCRoomId`）；没有加 `LiveMeDanmakuArgs`（只有直播 id 进不了聊天室，还缺 uid、令牌、设备号） | 解除后再加 |
| 账号 | 3.x 没有 LiveMe 登录和 Cookie 设置 | 账号页只有哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、CC、Twitch、SOOP（`apps/pure_live/lib/features/account/account_platforms.dart:82～141`），没有 LiveMe | 条件 A 时由 K 组加 |
| 代码 | 无 | `packages/live_danmaku/lib/src/sites/liveme.dart` 没有创建，`live_danmaku.dart` 没有导出；`fixtures/liveme/` 只有 E03.8 的接口样本，没有弹幕样本 | — |

## 结果

- **提交**：2d1994160（2026-09-29，调查结论和文档，没有代码）。
- **受阻的原因**（record.md“受阻的原因”）：
  1. 官网只在登录后建 IM 连接：`app-im-kit` 状态监听登录状态，没登录就销毁 IM；`createIM` 还要求用户信息里有设备号；
  2. 直播间只在登录分支里调用 `joinRoom(vid)`，游客走 `anonymous-user` 路径只放流；
  3. IM 的 `LOGIN` 要账号的 uid（`userInfo.user.uid`）和登录令牌（`userInfo.token`），网页端没有给游客发 IM 令牌的接口。
- **查过的其他路子都不通**：直播信息里的 `msgfile`（`sz.esxscloud.com/message/…/<vid>.json`）在播时 404（回放用）；`imapi.liveme.com` 只有私信接口且要 `cmimToken` 加签名；分享页和手机版是同一个单页应用；旧版 SDK `/app/spa/js/im.js` 仍要令牌、当前页面不调用；在播直播的 `chatSystem` 全是 `"3"`（自有 IM），精选第 1 页 20 场的 `TCRoomId` 都等于 `vid`；App 端要抓包和签名，不做。
- **没做的**：没有用空的 uid 和令牌去试 IM 服务器，没有注册账号，没有连过 IM 服务器（只做了 DNS 解析，两台都还在）。
- **测试**：没有代码，没有新测试；当时门禁通过。

## 验证

- 自动测试：没有本平台的连接代码。“不登记、给空连接”由应用测试覆盖：`apps/pure_live/test/platforms_test.dart:47～67`（弹幕平台表里没有 `SiteIds.liveMe`）；没有弹幕的平台不连接、只提示一次由 `apps/pure_live/test/features/live_play/live_play_controller_test.dart:240`（“a platform without danmaku says so once”）和 `live_play_tabs_test.dart:187`（聊天区显示“……的直播间没有弹幕”）覆盖；`packages/live_danmaku/test/connection_test.dart:256` 起覆盖 `EmptyDanmakuConnection`。
- 真实接口：只读了公开的网页脚本、请求了一次精选目录和一个在播直播的 `msgfile`（404），没有连过 IM。
- 真机：没有单独的真机记录；状态是“受阻”，不需要真机结果。要看的只有一条：进一个 LiveMe 直播间，聊天区显示“LiveMe的直播间没有弹幕”，不出现“连接中”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有这一条。

## 留下的问题

- **解除条件**（满足任一条才开工，详见 [brief.md](brief.md)）：
  - A：本项目决定支持 LiveMe 账号登录。这是 3.x 没有的新功能，按 D-026 先在 [V01](../../../V-需求和反馈/V01-新功能提议/README.md) 登记提议、写方案、用户确认，再在 K 组登记“LiveMe 登录”任务并完成（`CookieVault` 能存、平台层能读出 uid、登录令牌和设备号）。现在 V01 和 K 组都没有这个任务。
  - B：LiveMe 开放了游客聊天：官网脚本里出现未登录也调用 `createIM`、`joinRoom` 的路径，或有给游客发 IM 令牌的接口。复查由平台巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)（未开始）或维护者定期重读 `CLaEtC7T.js`、`CYslo3Yc.js` 做。
- 4.x 的“没有弹幕”提示和 3.x 不同：3.x 还提示可以开本地互动，4.x 的空状态说“醒目留言、弹幕设置、屏蔽管理照常可用”。属于直播间的提示文字（A08、C01），不在本任务里，没有任务。
- 列表里的一行“该平台暂不支持弹幕”被空状态盖住（`chat_list.dart:414～419` 只有状态行时显示空状态），只在有本地弹幕时才看得到，和空状态的说法重复：没有任务，属于直播间界面。
