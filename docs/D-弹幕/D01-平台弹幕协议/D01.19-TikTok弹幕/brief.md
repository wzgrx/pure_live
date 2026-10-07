# D01.19 TikTok 弹幕：任务书

> 状态“受阻”。**解除条件满足并经用户同意之前不要开工。** 本任务书写清阻塞的原因、怎么判断已经解除、解除后怎么做；解除后维护者把登记表改成“已确认”、写档位，并在本页顶部注明按哪一条解除、签名从哪来。

## 背景

- 来源：已批准升级 22-7“TikTok 评论弹幕”（`docs/specs/UPGRADES.md` 第 167 行，状态“受阻”）。3.x 有 TikTok 这个平台但没有弹幕（`~/ref/v3ref/lib/core/site/tiktok/tiktok_site.dart:38`，`EmptyDanmaku`），这是新增功能，没有 3.x 行为可对照。
- 现象：开着代理进 TikTok 直播间，聊天区显示“TikTok LIVE的直播间没有弹幕 / 醒目留言、弹幕设置、屏蔽管理照常可用”，没有任何评论；房间公告写着“TikTok 直播的评论暂时不能在这里显示。……”
- 为什么受阻：2026-09-29 调查（提交 d1db5734e，记录 [record.md](record.md)）读了官网直播间页面、`main.bdcac0d4.js`、IM SDK 块 `40231.7dba9d62.js`、`webmssdk/2.0.0.561/webmssdk.js`，用仓库的抖音签名实测，结论是签名对不上、也拿不到合规的签名（见下节）。登记表说明“要签名才能连弹幕，调查完成”。
- 已经做过的：调查和文档（d1db5734e，没有代码）；平台层 [E03.9](../../../E-直播平台/E03-海外平台/E03.9-TikTok/record.md) 已有直播间号 `TikTokRoomData.liveRoomId`（就是 IM 的 `room_id`）和公告 `TikTokApi.chatNotice`。

## 阻塞原因和解除条件

**阻塞的原因**（record.md“受阻的原因”“实测”）：

1. 评论只有 IM 一条路，入口要签名：网页端先签名拉取 `webcast/im/fetch/`，成功后才连 WebSocket（`fetchBeforeWsSuccess`）。不签名时拉取 403（`webcast.us.tiktok.com`）或 200 空正文（`webcast.tiktok.com`），WebSocket 握手不带 Cookie 回 417“named cookie not present”，带 `ttwid` 回“illegal secret key”。
2. 仓库的抖音签名对不上：`DouyinSigner.xBogus`（`packages/live_core/lib/src/sites/douyin/douyin_sign.dart:173`）用的是 `X-MS-STUB` 入口和抖音那一版的常数，`aBogus`（:79）是另一个参数、写死抖音 aid 6383（:57）；TikTok 的入口是 `X-MS-PAYLOAD`，还有 `registerWsSigner`（`X-Gnarly`）。实测加上它们和不签名的结果完全一样。
3. 有效签名只能靠在无头浏览器或 JS 引擎里跑 TikTok 的 `webmssdk`（签名在字节码虚拟机里，脚本里看不到算法），或用第三方签名服务（Euler Stream 等，要 API 密钥）。

**项目规则**（D01 平台弹幕任务的统一规则）：需要签名、登录、抓包或第三方 SDK 密钥才能连的不硬做，不绕过平台的访问限制——不冒充浏览器运行平台的混淆 SDK，不用第三方 SDK 密钥，不逆向虚拟机字节码写新的签名算法。

**解除条件（满足任一条，并经用户同意，才能开工）**：

| # | 条件 | 怎么判断（逐条可检查） | 谁来定 |
|---|---|---|---|
| A | TikTok 有了不需要 SDK 现场签名的评论入口 | 经代理只读请求：不签名的 `im/fetch`（带 `ttwid`、服务端下发的 `msToken`）返回非空的 protobuf `Response`，或 WebSocket 握手只带 `ttwid` 就能升级并收到帧；结果写进 `record-2.md`。由平台巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md) 或维护者定期复查 | 维护者实测，用户同意接入 |
| B | 出现能合规复用的签名 | 公开的纯算法实现（不运行 TikTok 的 SDK、不需要第三方密钥），许可证允许随 AGPL-3.0 发布（对照 `docs/specs/ENGINEERING.md` 第 5 节的许可证表；GPL-2.0-only 这类不行，同 D01.1 对 fuzzywuzzy 的处理）；用它签名后 `im/fetch` 返回非空的 protobuf，并能连上 WebSocket 收到评论 | 维护者核对许可证和实测，用户同意 |

现在两条都不满足：E07.1 还没开始，2026-09-29 之后没有复查。

## 目标和验收（解除后）

1. 开着代理进一个在播的 TikTok 直播间：聊天区从“连接中”变成已连接，有人发言时几秒内出现评论（名字、文字），列表和画面上都有。
2. 在线人数随 `WebcastRoomUserSeqMessage` 更新，口径和 E03.9 的 `liveRoomStats.userCount`（在线）一致，累计人数不被覆盖。
3. 断网 30 s 再恢复：出现一次“正在重连”，恢复后重新拉取、重新连 WebSocket，评论继续。
4. 签名失效（服务端又改了，拉取 403 或握手“illegal secret key”）：以 `credentialsUnavailable` 结束，只提示一次，不无限重连；直播间照常播放。
5. `ttwid`、`msToken`、签名参数不出现在任何事件的 `detail`、日志、测试和样本里；测试和样本不带出口 IP。
6. 公告 `TikTokApi.chatNotice`（`tiktok_api.dart:267`）去掉“TikTok 直播的评论暂时不能在这里显示。”这一句，只留人数口径。
7. `packages/live_danmaku/test/sites/tiktok_test.dart` 覆盖拉取回答、帧、`im_enter_room`、心跳、ACK 的编解码（对照录制样本）和连接时序；`apps/pure_live/test/platforms_test.dart:47～67` 的“没有弹幕的平台”集合去掉 `SiteIds.tiktok`；门禁通过。

## 现状（读代码得出，写文件:行）

- 平台表：`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 LiveMe、TikTok 受阻、不登记；`buildDanmakuRegistry`（:196～239）里没有 `SiteIds.tiktok`。
- 登记表：`packages/live_danmaku/lib/src/registry.dart`：`supports`（:75）为假，`connectionFor`（:79）给 `EmptyDanmakuConnection`（:13）。
- 直播间：`apps/pure_live/lib/features/live_play/live_play_page.dart:279` 传 `danmaku.supports(site.id)`；`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～822`：不支持时设 `ChatConnection.unsupported`，只加一次系统行“该平台暂不支持弹幕”；聊天列表只有系统行时显示空状态（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:414～419`），`unsupported` 是“{platform}的直播间没有弹幕”（:287～295）。
- 平台层：`packages/live_core/lib/src/sites/tiktok/tiktok_api.dart`：`TikTokRoomData`（:80）的 `liveRoomId`（:108），公告 `chatNotice`（:267，:425 放进每个房间）；没有 `ttwid`（E03.9 不带 Cookie），没有弹幕参数类。人数 `packages/live_core/lib/src/audience.dart:177～181`（`roomRealtime`，有累计）。
- 可复用：`packages/live_danmaku/lib/src/sites/douyin.dart`（`PushFrame`、`Response`、`Message`、ACK 的写法，字段号相同）、`packages/live_danmaku/lib/src/codec/protobuf.dart`（`ProtoMessage` :27、`ProtoWriter` :162）；签名 `douyin_sign.dart` 对 TikTok 无效，不要改它。
- 样本：`fixtures/tiktok/` 只有 E03.9 的 S01、S02 接口样本，没有弹幕样本。

## 3.x 基线

- `~/ref/v3ref/lib/core/site/tiktok/tiktok_site.dart:38`：`getDanmaku() => EmptyDanmaku()`；:76 公告 `tiktok_chat_notice`（`assets/translations/zh.json:1874`：“TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。”）。
- `~/ref/v3ref/lib/modules/live_play/controllers/danmaku_controller.dart:146～150`：没有弹幕的平台不连接，只提示一次 `remote_danmaku_not_integrated`。
- 3.x 的抖音签名在 `core/danmaku/xbogus.dart`，没有 TikTok 的签名；3.x 没有 TikTok 登录和 Cookie 设置。要保留的：没有弹幕时不连接、只提示一次。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 7 节交给其他 AI、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 5 节参考仓库和许可证）。
3. 本文件夹的 `README.md`、`record.md`（“查明的协议”“与抖音签名的核对”“实测”）。
4. `docs/D-弹幕/D01-平台弹幕协议/D01.5-抖音弹幕/record.md` 和 `packages/live_danmaku/lib/src/sites/douyin.dart`；框架 `docs/D-弹幕/D01-平台弹幕协议/D01.1-弹幕框架和过滤/record.md`。
5. `docs/E-直播平台/E03-海外平台/E03.9-TikTok/record.md`（进房接口、人数口径、公告）。

## 范围

- 可以改：`packages/live_danmaku/lib/src/sites/tiktok.dart`（新建）、`packages/live_danmaku/lib/live_danmaku.dart`（导出一行）、`packages/live_danmaku/test/sites/tiktok_test.dart`（新建）、`packages/live_core/lib/src/sites/tiktok/`（只加 `TikTokDanmakuArgs`、`ttwid` 的获取、签名（按解除条件的来源）和公告文字，以及对应测试）、`fixtures/tiktok/danmaku/`（新样本）、`apps/pure_live/lib/app/platforms.dart`（登记一行、改注释）、`apps/pure_live/test/platforms_test.dart`、本文件夹。
- 不能改：框架文件（`connection.dart`、`connection_base.dart`、`socket_connection.dart`、`registry.dart`）；抖音的签名和弹幕（`douyin_sign.dart`、`sites/douyin.dart`，要共用时先问维护者）；直播间界面和提示文字（A08、C01）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；不得加入任何运行 JS 的依赖、无头浏览器或第三方签名服务。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 0 | 确认解除条件：按 A 或 B 实测拉取和握手成功；重新下载官网脚本，核对 record.md 的协议（模块号、`version_code`、参数、`EnterRoom` 字段会变） | `record-2.md`（新建） | 维护者确认、用户同意，登记表改“已确认” |
| 1 | 录样本：经代理只读、匿名进一个在播直播间 3～5 分钟，录拉取回答和 WebSocket 帧；脱敏 `ttwid`、`msToken`、签名、观众名字和 id | `fixtures/tiktok/danmaku/S03-live/`（`frames.jsonl`、`meta.json`） | 门禁 `fixture privacy` 通过 |
| 2 | 平台层：进房时取 `ttwid`（页面的 `Set-Cookie`），`TikTokDanmakuArgs(roomId, ttwid, …)` 在播时放进 `danmakuData`；签名按解除条件的方式实现 | `packages/live_core/lib/src/sites/tiktok/` | `live_core` 的 TikTok 测试通过，原有断言不变 |
| 3 | 协议和连接：拉取（失败每 1 s 重试，有上限）→ 按回答建 WebSocket → `im_enter_room` → 带负载的 `hb`（`heartbeat_duration`，最少 10 s）→ ACK；聊天、人数按 `method` 解码，`room_id` 过滤，`room_id + msg_id` 去重 | `packages/live_danmaku/lib/src/sites/tiktok.dart`、`live_danmaku.dart` | `tiktok_test.dart` 通过（见“测试”） |
| 4 | 登记和公告：平台表加 TikTok；公告去掉第一句 | `apps/pure_live/lib/app/platforms.dart`、`apps/pure_live/test/platforms_test.dart`、`tiktok_api.dart` | 应用全部测试通过；门禁通过 |

每个阶段都要能单独合并（门禁通过、不留半截功能）；阶段 2 合并后还没有连接，界面不变。

## 测试

- `packages/live_danmaku/test/sites/tiktok_test.dart`：拉取回答（`Response` 的 `push_server`、`route_params`、`cursor`、`heartbeat_duration`）的解码；`im_enter_room`、`hb`、ACK 的编码与样本逐字节相同；样本回放的聊天和人数逐条对上；连接：拉取失败重试、握手被拒（`illegal secret key`）以 `credentialsUnavailable` 结束、断线重连重新拉取、关闭后没有事件、详情不带 `ttwid` 和签名；本地 HTTP + WebSocket 服务器端到端。
- `live_core`：`ttwid` 的读取、`TikTokDanmakuArgs` 只在在播时给出、公告文字。
- 应用：`apps/pure_live/test/platforms_test.dart` 的集合去掉 `SiteIds.tiktok`，`connectionFor(SiteIds.tiktok)`（现在 :64 断言是空连接）改成 `TikTokDanmakuConnection`。
- 测试里的定时器至少 1 秒；不访问真实平台；用到样本时间的固定“现在”（D-017）。

## 真机验证（维护者在 K90 上做，开着代理）

| 步骤 | 期望 |
|---|---|
| 1. 首页 → 搜索 TikTok 账号或粘贴直播间链接，进一个在播的直播间 | 聊天区先“连接中”，随后已连接，有人发言时出现评论，画面上有飞行弹幕；在线人数随之更新 |
| 2. 关 Wi-Fi 30 s 再开 | 一次“正在重连”，恢复后评论继续 |
| 3. 看直播间信息里的公告 | 不再写“评论暂时不能在这里显示” |

## 风险和注意

- 签名是平台对抗的重点，随时会变（all-chat 记录 2026-09-15 加 `X-Gnarly` 后反而 403）；必须有“签名失效就结束、不无限重连”的退路，播放不受影响。
- 许可证：任何借来的签名代码先核对许可证，不能随 AGPL-3.0 发布的不要用。
- 只能经代理访问；测试和样本不能带出口 IP；美区和欧区的 WebSocket 主机不同，按拉取回答的 `push_server` 走。
- 和 E03.9（平台层）改同一批文件：同一时间只开一个。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/D01.19` 或本机工作区；提交信息以 `[D01.19]` 开头（英文）；不推 master。
- 提交前：`packages/live_danmaku`、`packages/live_core` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record-2.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。阶段 0 不通过时不要往下做，在 `record-2.md` 写明实测结果，状态保持“受阻”。

## 报告（中文，简洁）

按哪一条解除、签名从哪来、许可证；每条验收做到没有；协议和 record.md 不同的地方；样本和脱敏；测试数量；改了哪些文件；新设置和翻译键（应该没有）；要在真机上看的；需要维护者决定的；可能冲突的文件。
