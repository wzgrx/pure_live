# D01.19 TikTok 弹幕

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（现在是“受阻”）
- 类型：平台
- 来源：已批准升级 22-7“TikTok 评论弹幕”（[specs/UPGRADES.md](../../../specs/UPGRADES.md)，状态“受阻”）；3.x 没有 TikTok 弹幕
- 旧编号：M5.18、T06a.19
- 相关：框架 [D01.1](../D01.1-弹幕框架和过滤/README.md)；抖音的签名和协议 [D01.5](../D01.5-抖音弹幕/README.md)（帧的字段号相同，签名对不上）；平台本身 [E03.9 记录](../../../E-直播平台/E03-海外平台/E03.9-TikTok/record.md)（直播间号 `TikTokRoomData.liveRoomId`、公告 `tiktok_chat_notice`）；调查记录 [record.md](record.md)；任务书 [brief.md](brief.md)

## 目标

让 TikTok 直播间能看到评论。调查后的结论是**受阻**：评论只能从平台的 IM 拿，先签名请求 `webcast/im/fetch/`、成功后再连 WebSocket，两步都要网页安全 SDK（`webmssdk` 2.0.0.561）现场生成的签名；仓库里抖音的纯 Dart 签名对不上（实测加了和不签名一样被拒），有效签名只能靠运行 TikTok 的混淆 SDK 或第三方签名服务，都属于绕过平台限制，不做。

## 协议要点（调查所得，没有实测成功，没有样本）

| 项 | 官网网页端的做法 |
|---|---|
| 顺序 | IM 配置 `fetchBeforeWsSuccess: "1"`：先 HTTP 拉取一次，成功后按回答里的 `push_server`、`route_params`、`heartbeat_duration` 建 WebSocket；拉取失败每 1 s 重试 |
| 拉取 | `GET <webcast 主机>/webcast/im/fetch/`，参数 `aid=1988`、`app_name=tiktok_web`、`room_id`、`cursor=0`、`internal_ext=0`、浏览器信息等；回答是 protobuf `webcast.im.Response`；由 `webmssdk` 拦截 XHR 加 `msToken` 和签名 |
| WebSocket | `wss://webcast-ws.us.tiktok.com/webcast/im/ws_proxy/ws_reuse_supplement/?…`（欧区 `.eu.`，或不带区），地址末尾加 `X-Bogus = frontierSign({"X-MS-PAYLOAD": ""})`，SDK 另有 `registerWsSigner`（`X-Gnarly`）；握手带访客 Cookie `ttwid` |
| 帧 | `webcast.im.PushFrame`，字段号与抖音相同；`Response` 的 1～10 号字段、`Message` 的前 3 个字段与抖音相同 |
| 加入 | 发 `payload_type = "im_enter_room"` 的帧，负载 `EnterRoom{room_id, …, filter_welcome_msg = "0"}`（抖音只发空的 `hb`） |
| 心跳和 ACK | `hb` 帧带 `HeartBeat{room_id}`，间隔取 `heartbeat_duration`（最少 10 s）；`need_ack` 时回 `ack`（同抖音） |
| 消息 | 按 `method` 分发（`WebcastChatMessage`、`WebcastRoomUserSeqMessage` 等），`common.room_id` 不是本场的丢；具体字段没有核对 |

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 弹幕 | `TikTokSite.getDanmaku() => EmptyDanmaku()`（`~/ref/v3ref/lib/core/site/tiktok/tiktok_site.dart:38`），提示一次 `remote_danmaku_not_integrated` | 不在弹幕平台表里（`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 TikTok 受阻），直播间提示一次“该平台暂不支持弹幕”（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～821`） | 受阻：解除条件见下 |
| 公告 | 3.x 的 `tiktok_chat_notice` | E03.9 改成“TikTok 直播的评论暂时不能在这里显示。……”（`packages/live_core/lib/src/sites/tiktok/tiktok_api.dart:267`） | 仍然符合实际 |
| 签名 | 3.x 只有抖音的签名（`core/danmaku/xbogus.dart`） | `packages/live_core/lib/src/sites/douyin/douyin_sign.dart` 的 `DouyinSigner`（`xBogus` 用 `X-MS-STUB` 入口、`aBogus` 写死抖音 aid 6383），对 TikTok 无效 | — |
| 代码 | 无 | `packages/live_danmaku/lib/src/sites/tiktok.dart` 没有创建；没有 `TikTokDanmakuArgs`；平台层不拿 `ttwid` | — |

## 结果

- **提交**：d1db5734e（2026-09-29，调查结论和文档，没有代码）。
- **实测**（2026-09-29 经本机代理、美国出口、只读、不登录）：
  - 不签名拉取：`webcast.us.tiktok.com` 回 HTTP 403 空正文，`webcast.tiktok.com` 回 200 空正文；
  - 加上服务端下发的 `msToken`、`ttwid` 和仓库算的 `X-Bogus`、`a_bogus`：结果和不签名完全一样；
  - WebSocket 握手：不带 Cookie 回 `Handshake-Status: 417 named cookie not present`，带 `ttwid` 和仓库的 `X-Bogus` 都回 `illegal secret key`；
  - 预览拉取、另一个主机、直接连 WebSocket、进房接口都不通或没有评论。
- **没做的**：没有在浏览器或 JS 引擎里运行 `webmssdk`，没有用第三方签名服务（Euler Stream 要 API 密钥），没有逆向字节码虚拟机写新签名，没有登录，没有收到任何评论数据。
- **测试**：没有代码，没有测试；当时门禁通过。

## 验证

- 自动测试：无。平台表不登记 TikTok，`DanmakuRegistry` 返回 `EmptyDanmakuConnection`（`packages/live_danmaku/test/connection_test.dart` 覆盖未登记的平台）。
- 真机：要看的只有一条：开着代理进一个在播的 TikTok 直播间，聊天区只出现一次“该平台暂不支持弹幕”。

## 留下的问题

- 解除条件：TikTok 开放了不需要 SDK 现场签名的评论入口，或者出现可以合规复用的纯算法签名（不运行 TikTok 的 SDK、不用第三方服务的 API 密钥），并且用户同意接入。详见 [brief.md](brief.md)。
- 平台还在改签名（第三方记录 2026-09-15 加 `X-Gnarly` 后反而 403），即使解除，维护成本也高；接入前要和用户确认。
