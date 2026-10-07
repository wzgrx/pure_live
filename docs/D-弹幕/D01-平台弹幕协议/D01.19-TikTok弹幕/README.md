# D01.19 TikTok 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（受阻，2026-09-29，提交 d1db5734e；登记表说明“要签名才能连弹幕，调查完成”）
- 类型：平台
- 来源：已批准升级 22-7“TikTok 评论弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md) 第 167 行，状态“受阻”）；3.x 有 TikTok 这个平台但没有弹幕
- 旧编号：M5.18、T06a.19
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；抖音的签名和协议 [D01.5](../D01.5-抖音弹幕/README.md)（帧的字段号相同，签名对不上）；平台本身 [E03.9 记录](../../../E-直播平台/E03-海外平台/E03.9-TikTok/record.md)（直播间号 `TikTokRoomData.liveRoomId`、公告 `chatNotice`）；平台巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)；同样受阻的 [D01.18 LiveMe](../D01.18-LiveMe弹幕/README.md)；参考仓库和许可证见 `docs/specs/ENGINEERING.md` 第 5 节；调查记录 [record.md](record.md)；任务书 [brief.md](brief.md)

## 目标

让 TikTok 直播间能看到评论。调查后的结论是**受阻**：评论只能从平台的 IM 拿，先签名请求 `webcast/im/fetch/`、成功后再连 WebSocket，两步都要网页安全 SDK（`webmssdk` 2.0.0.561）现场生成的签名；仓库里抖音的纯 Dart 签名对不上（实测加了和不签名一样被拒），有效签名只能靠运行 TikTok 的混淆 SDK 或用第三方签名服务。D01 平台弹幕任务的统一规则不允许绕过平台的访问限制，也不用第三方 SDK 密钥，所以没有写连接代码；直播间照 3.x 不连接，只说明这个平台没有弹幕。

## 协议要点（调查所得，没有实测成功，没有样本）

出处是 2026-09-29 经代理下载的官网脚本：直播间路由块 `async/main___live-container/(anchorName).live/page.5f08d010.js`、IM SDK 块 `async/40231.7dba9d62.js`、`live_new/static/js/main.bdcac0d4.js`、`webmssdk/2.0.0.561/webmssdk.js`；模块号和函数名是打包后的名字，会变。详见 [record.md](record.md)“查明的协议”。

| 项 | 官网网页端的做法 |
|---|---|
| 顺序 | IM 配置 `fetchBeforeWsSuccess: "1"`、`wsDirect: "1"`：先 HTTP 拉取一次，成功后按回答里的 `push_server`、`route_params`、`heartbeat_duration` 建 WebSocket；拉取失败每 1 s 重试 |
| 拉取 | `GET <webcast 主机>/webcast/im/fetch/`（预览 `/fetch/preview/`、历史 `/fetch/history/`），参数 `aid=1988`、`app_name=tiktok_web`、`room_id`、`cursor=0`、`internal_ext=0`、`last_rtt=-1`、`version_code`、`resp_content_type=protobuf`、浏览器信息等；超时 10 s；回答是 protobuf `webcast.im.Response`；签名不在 IM 块里，由 `webmssdk` 拦截 XHR（`acrawler` 配置 `intercept: true`，`enablePathList` 含 `/webcast.*`）时加 `msToken` 和签名参数 |
| WebSocket | `wss://webcast-ws.us.tiktok.com/webcast/im/ws_proxy/ws_reuse_supplement/?…`（欧区 `.eu.`，或不带区），查询同拉取加 `route_params`、`cursor`、`internal_ext`、`compress=gzip`、`heartbeat_duration`；地址末尾加 `X-Bogus = frontierSign({"X-MS-PAYLOAD": ""})`，SDK 另有 `registerWsSigner`（第三方说明是 `X-Gnarly`）；握手带访客 Cookie `ttwid` |
| 帧 | `webcast.im.PushFrame`：`SeqID 1`、`LogID 2`、`service 3`、`method 4`、`headers 5`、`payload_encoding 6`、`payload_type 7`、`payload 8`，字段号与抖音（D01.5）相同；`Response` 的 1～10 号字段、`Message` 的前 3 个字段与抖音相同（11 号以后不同） |
| 加入 | 发 `payload_type = "im_enter_room"` 的帧，负载 `EnterRoom{room_id 1, room_tag 2, live_region 3, live_id 4, identity 5, cursor 6, account_type 7, …, filter_welcome_msg 9 = "0"}`（抖音只发空的 `hb`） |
| 心跳和 ACK | `hb` 帧带 `HeartBeat{room_id 1}`，间隔取 `heartbeat_duration`（最少 10 s）；`need_ack` 时回 `ack`，负载是 `internal_ext`，`LogID` 同原帧（同抖音）；关闭码 4001 服务端断开、4003 出错 |
| 消息 | 按 `method` 分发（`WebcastChatMessage`、`WebcastRoomUserSeqMessage` 等），`common.room_id` 不是本场的丢，同一个 `room_id + msg_id` 只处理一次；聊天和人数的具体字段没有核对 |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/...`） | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | 3.x 有 TikTok 这个平台但没有弹幕：`TikTokSite.getDanmaku() => EmptyDanmaku()`（`core/site/tiktok/tiktok_site.dart:38`）；直播间只提示一次 `remote_danmaku_not_integrated`（`modules/live_play/controllers/danmaku_controller.dart:146～150`） | 不在弹幕平台表里（`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 TikTok 因签名受阻），`DanmakuRegistry.supports('tiktok')` 为假（`packages/live_danmaku/lib/src/registry.dart:75`），`connectionFor` 给 `EmptyDanmakuConnection`（:79、:13）；直播间不连接（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～822`），聊天区显示“TikTok LIVE的直播间没有弹幕 / 醒目留言、弹幕设置、屏蔽管理照常可用”（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:287～295`，平台名取 `platformName`），列表里另有一行“该平台暂不支持弹幕” | 受阻：解除条件见“留下的问题” |
| 公告 | `tiktok_chat_notice`“TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。”（`assets/translations/zh.json:1874`，`core/site/tiktok/tiktok_site.dart:76`） | E03.9 改成“TikTok 直播的评论暂时不能在这里显示。在线人数是正在看的人数，累计是进过直播间的人数。”（`packages/live_core/lib/src/sites/tiktok/tiktok_api.dart:267`，:425 放进每个房间） | 仍然符合实际，不改 |
| 签名 | 3.x 只有抖音的签名（`core/danmaku/xbogus.dart`） | `packages/live_core/lib/src/sites/douyin/douyin_sign.dart` 的 `DouyinSigner`（:21）：`aBogus`（:79，数据里写死抖音 aid 6383，:57）、`danmakuSignature`（:150）、`xBogus`（:173，`X-MS-STUB` 入口），对 TikTok 无效 | — |
| 参数和 Cookie | 无 | 平台层有直播间号 `TikTokRoomData.liveRoomId`（`tiktok_api.dart:80`、:108），就是 IM 的 `room_id`；没有 `TikTokDanmakuArgs`；平台层不拿访客 Cookie `ttwid`（E03.9 全程不带 Cookie）；账号页没有 TikTok（`apps/pure_live/lib/features/account/account_platforms.dart:82～141`） | 解除后再加 |
| 代码 | 无 | `packages/live_danmaku/lib/src/sites/tiktok.dart` 没有创建，`live_danmaku.dart` 没有导出；`fixtures/tiktok/` 只有 E03.9 的接口样本（S01、S02），没有弹幕样本 | — |
| 人数 | 3.x 分别显示当前观看和累计进房 | `packages/live_core/lib/src/audience.dart:177～181`：`roomRealtime`，有累计；人数来自进房和刷新的 `liveRoomStats.userCount`、`enterCount`，本任务没有改 | 不变 |

## 结果

- **提交**：d1db5734e（2026-09-29，调查结论和文档，没有代码）。
- **实测**（2026-09-29 北京时间 06:01～06:15，经本机代理、美国出口、只读、不登录；record.md“实测”8 条）：
  - 不签名拉取：`webcast.us.tiktok.com` 回 HTTP 403 空正文（带 `x-ms-token` 响应头），`webcast.tiktok.com` 回 200 空正文；预览拉取 403；
  - 加上服务端下发的 `msToken`、`ttwid` 和仓库算的 `X-Bogus`、`a_bogus`：结果和不签名完全一样；
  - WebSocket 握手：不带 Cookie 回 `Handshake-Status: 417`、`named cookie not present`；带 `ttwid`、再加仓库的 `X-Bogus` 都回 `illegal secret key`；
  - 进房接口 `api-live/user/room`、`webcast/room/info` 不要签名，但只有房间信息和人数（E03.9 已用），没有评论。
- **与抖音签名的核对**：入口不同（抖音 `X-MS-STUB` 对 TikTok `X-MS-PAYLOAD`），SDK 版本和常数不同，TikTok 还要先有一次签名成功的 `im/fetch`；`msToken` 不是卡点（被拒的请求也会下发）。
- **没做的**：没有在浏览器或 JS 引擎里运行 `webmssdk`，没有用第三方签名服务（Euler Stream 要 API 密钥），没有逆向字节码虚拟机写新签名，没有登录，没有收到任何评论数据；没有移动 `douyin_sign.dart`（没有可共用的部分）。
- **测试**：没有代码，没有新测试；当时门禁通过。

## 验证

- 自动测试：没有本平台的连接代码。“不登记、给空连接”由应用测试覆盖：`apps/pure_live/test/platforms_test.dart:47～67`（弹幕平台表里没有 `SiteIds.tiktok`，`connectionFor(SiteIds.tiktok)` 是 `EmptyDanmakuConnection`，:64）；没有弹幕的平台不连接、只提示一次由 `apps/pure_live/test/features/live_play/live_play_controller_test.dart:240` 和 `live_play_tabs_test.dart:187` 覆盖。
- 真实接口：见上面的实测，8 次只读请求和握手全部被拒。
- 真机：没有单独的真机记录；状态是“受阻”，不需要真机结果。要看的只有一条：开着代理进一个在播的 TikTok 直播间，聊天区是“……的直播间没有弹幕”，不出现“连接中”。[真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有这一条。

## 留下的问题

- **解除条件**（满足任一条并经用户同意才开工，详见 [brief.md](brief.md)）：
  - A：TikTok 有了不需要 SDK 现场签名的评论入口——不签名的 `im/fetch`（带 `ttwid`、`msToken`）返回非空的 protobuf，或 WebSocket 握手不再要求签名。由平台巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)（未开始）或维护者定期复查。
  - B：出现能合规复用的签名：公开的纯算法实现，不运行 TikTok 的 SDK、不需要第三方密钥，许可证允许随 AGPL-3.0 发布；用它签名后 `im/fetch` 返回非空的 protobuf，并能连上 WebSocket 收到评论。
  - 现在两条都不满足。
- 平台还在改签名（第三方 all-chat 记录 2026-09-15 加 `X-Gnarly` 后反而 403），即使解除，维护成本也高；接入前要和用户确认，并留好“签名失效就结束、不无限重连”的退路。
- 4.x 的“没有弹幕”提示和 3.x 不同（3.x 还提示可以开本地互动），列表里的“该平台暂不支持弹幕”被空状态盖住：属于直播间界面（A08、C01），没有任务，见 [D01.18](../D01.18-LiveMe弹幕/README.md) 的同一条。
