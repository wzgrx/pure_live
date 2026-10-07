# D01.19 TikTok 弹幕：任务书

> 状态“受阻”。**解除条件满足之前不要开工**；本任务书写清阻塞的原因、怎么判断已经解除、解除后怎么做。

## 背景

- 来源：已批准升级 22-7“TikTok 评论弹幕”（`docs/specs/UPGRADES.md` 第 167 行，状态“受阻”）。3.x 的 TikTok 没有弹幕（`EmptyDanmaku`），这是新增功能。
- 现象：进 TikTok 直播间（要代理），聊天区只出现一次“该平台暂不支持弹幕”，公告写着“TikTok 直播的评论暂时不能在这里显示”。
- 已经做过的：2026-09-29 的调查（提交 d1db5734e，记录 `record.md`）：读了官网直播间页面、`main.bdcac0d4.js`、IM SDK 块 `40231.7dba9d62.js`、`webmssdk/2.0.0.561/webmssdk.js`，用仓库的抖音签名实测，结论是签名对不上，没写代码。平台层（E03.9）已有直播间号 `TikTokRoomData.liveRoomId`。

## 阻塞和解除条件

**阻塞的原因**（record.md“受阻的原因”）：

1. 评论只有 IM 一条路，入口要签名：先签名拉取 `webcast/im/fetch/`，成功后才连 WebSocket；不签名时拉取 403 或空正文，WebSocket 握手报 `illegal secret key`。
2. 仓库的抖音签名对不上：`DouyinSigner.xBogus` 用的是 `X-MS-STUB` 入口和抖音那一版的常数，`aBogus` 是另一个参数、写死抖音 aid 6383；TikTok 的入口是 `X-MS-PAYLOAD`，还有 `registerWsSigner`（`X-Gnarly`）。实测加上和不签名结果一样。
3. 有效签名只能靠在无头浏览器或 JS 引擎里跑 TikTok 的 `webmssdk`（字节码虚拟机），或用第三方签名服务（要 API 密钥）。

**项目规则**：不冒充浏览器运行平台的混淆 SDK 来绕过访问限制，不用第三方 SDK 密钥，不逆向虚拟机字节码写新的签名算法。

**解除条件（满足任一条，并经用户同意，才能开工）**：

| # | 条件 | 怎么判断 | 谁来定 |
|---|---|---|---|
| A | TikTok 有了不需要 SDK 现场签名的评论入口 | 平台巡检（E07.1）或定期复查时：不签名的 `im/fetch`（带 `ttwid`、`msToken`）返回非空的 protobuf，或 WebSocket 握手不再要求签名 | 维护者实测，用户同意接入 |
| B | 出现能合规复用的签名：公开的纯算法实现（不运行 TikTok 的 SDK、不需要第三方密钥），许可证允许随 AGPL-3.0 发布 | 用它签名后 `im/fetch` 返回非空的 protobuf，并能连上 WebSocket 收到评论 | 维护者核对许可证和实测，用户同意 |

解除后：维护者把登记表的状态改成“已确认”、写档位，并在本任务书顶部注明按哪一条解除。

## 目标和验收（解除后）

1. 开着代理进一个在播的 TikTok 直播间，聊天区显示“已连接”，有人发言时几秒内出现评论（名字、文字）。
2. 在线人数随 `WebcastRoomUserSeqMessage` 更新（口径和 E03.9 的 `liveRoomStats.userCount` 一致）。
3. 断网再恢复：一次“正在重连”，恢复后重新拉取、重新连 WebSocket、再次“已连接”。
4. 签名失效（服务端又改了）时：以 `credentialsUnavailable` 一类的原因结束，不无限重连；直播间照常播放。
5. 测试覆盖拉取回答、帧、`im_enter_room`、心跳、ACK 的编解码（对照录制样本）和连接时序；门禁通过。
6. 公告 `tiktok_chat_notice` 去掉第一句（E03.9“留给其他模块”的约定）。

## 现状（读代码得出）

- 平台表：`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 TikTok 受阻、不登记；`DanmakuRegistry.connectionFor('tiktok')` 返回 `EmptyDanmakuConnection`。
- 直播间：`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～821`，不支持弹幕的平台提示一次 `live_play_danmaku_unsupported`。
- 平台层：`packages/live_core/lib/src/sites/tiktok/tiktok_api.dart:267` 的公告 `chatNotice`；没有 `ttwid`（E03.9 不带 Cookie），没有弹幕参数类。
- 可复用：`packages/live_danmaku/lib/src/sites/douyin.dart`（帧、ACK、消息分发的写法；`PushFrame`、`Response`、`Message` 字段号相同）、`packages/live_danmaku/lib/src/codec/protobuf.dart`（读写器）；签名 `packages/live_core/lib/src/sites/douyin/douyin_sign.dart` 对 TikTok 无效。

## 3.x 基线

- `~/ref/v3ref/lib/core/site/tiktok/tiktok_site.dart:38`：`getDanmaku() => EmptyDanmaku()`。
- `~/ref/v3ref/lib/modules/live_play/controllers/danmaku_controller.dart:150`：提示一次 `remote_danmaku_not_integrated`。
- 3.x 没有 TikTok 登录和 Cookie 设置。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 7 节交给其他 AI、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 5 节上游和许可证）。
3. 本文件夹的 `README.md`、`record.md`（“查明的协议”“与抖音签名的核对”“实测”）。
4. `docs/D-弹幕/D01-平台弹幕协议/D01.5-抖音弹幕/record.md` 和 `packages/live_danmaku/lib/src/sites/douyin.dart`。
5. `docs/E-直播平台/E03-海外平台/E03.9-TikTok/record.md`（进房接口、人数口径、公告）。

## 范围

- 可以改：`packages/live_danmaku/lib/src/sites/tiktok.dart`（新建）、`packages/live_danmaku/lib/live_danmaku.dart`（导出）、`packages/live_danmaku/test/sites/tiktok_test.dart`（新建）、`packages/live_core/lib/src/sites/tiktok/`（只加 `TikTokDanmakuArgs`、`ttwid` 的获取和公告文字）、`fixtures/tiktok/danmaku/`（新样本）、`apps/pure_live/lib/app/platforms.dart`（登记一行、改注释）。
- 不能改：框架文件（`connection.dart`、`connection_base.dart`、`socket_connection.dart`）；抖音的签名和弹幕（`douyin_sign.dart`、`sites/douyin.dart`，要共用时先问维护者）；直播间界面和提示文字；版本号、`assets/version.json`、`assets/releases.json`；签名配置；不得加入任何运行 JS 的依赖、无头浏览器或第三方签名服务。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 0 | 确认解除条件：按 A 或 B 实测拉取和握手成功，重新核对 record.md 的协议（官网的模块号、参数、`version_code` 会变） | `record-2.md`（新建） | 维护者确认，登记表改“已确认” |
| 1 | 录样本：只读、匿名进一个在播直播间 3～5 分钟，录拉取回答和 WebSocket 帧；脱敏 `ttwid`、`msToken`、签名、观众名字和 id | `fixtures/tiktok/danmaku/S01-live/` | 门禁 `fixture privacy` 通过 |
| 2 | 平台层：进房时取 `ttwid`（页面的 `Set-Cookie`），`TikTokDanmakuArgs(roomId, ttwid, …)` 放进 `danmakuData`；签名按解除条件的方式实现 | `packages/live_core/lib/src/sites/tiktok/` | `live_core` 的 TikTok 测试通过 |
| 3 | 协议和连接：拉取（失败每 1 s 重试，有上限）→ 按回答建 WebSocket → `im_enter_room` → 带负载的 `hb` → ACK；聊天、人数按 `method` 解码，`room_id` 过滤 | `packages/live_danmaku/lib/src/sites/tiktok.dart` | `tiktok_test.dart`：样本回放逐条对上、连接时序、签名被拒时结束 |
| 4 | 登记和公告：平台表加 TikTok；公告去掉第一句 | `apps/pure_live/lib/app/platforms.dart`、`tiktok_api.dart` | 应用的 `test/platforms_test.dart` 通过；门禁通过 |

## 测试

- `packages/live_danmaku/test/sites/tiktok_test.dart`：拉取回答（`Response` 的 `push_server`、`route_params`、`cursor`）的解码；`im_enter_room`、`hb`、ACK 的编码与样本逐字节相同；样本回放的聊天和人数逐条对上；连接：拉取失败重试、握手被拒（`illegal secret key`）以 `credentialsUnavailable` 结束、断线重连重新拉取、关闭后没有事件、详情不带 `ttwid` 和签名；本地 HTTP + WebSocket 服务器端到端。
- `live_core`：`ttwid` 的读取、`TikTokDanmakuArgs` 只在在播时给出。
- 测试里的定时器至少 1 秒；不访问真实平台；用到样本时间的固定“现在”（D-017）。

## 真机验证（维护者在 K90 上做，开着代理）

| 步骤 | 期望 |
|---|---|
| 1. 进一个在播的 TikTok 直播间 | 聊天区“已连接”，有人发言时出现评论；在线人数随之更新 |
| 2. 关 Wi-Fi 30 s 再开 | 一次“正在重连”，恢复后“已连接” |
| 3. 看直播间公告 | 不再写“评论暂时不能在这里显示” |

## 风险和注意

- 签名是平台对抗的重点，随时会变；要有“签名失效就结束、不无限重连”的退路，播放不受影响。
- 许可证：任何借来的签名代码先核对许可证（`docs/specs/ENGINEERING.md` 第 5 节），GPL-2.0-only 这类不能随 AGPL-3.0 发布的不要用（同 D01.1 对 fuzzywuzzy 的处理）。
- 只能经代理访问；测试和样本不能带出口 IP。
- 和 E03.9（平台层）的文件可能冲突。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/D01.19` 或本机工作区；提交信息以 `[D01.19]` 开头（英文）；不推 master。
- 提交前：`packages/live_danmaku`、`packages/live_core` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑 `flutter test test/platforms_test.dart`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record-2.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。阶段 0 不通过时不要往下做，在 `record-2.md` 写明实测结果，状态保持“受阻”。

## 报告（中文，简洁）

按哪一条解除、签名从哪来、许可证；每条验收做到没有；协议和 record.md 不同的地方；样本和脱敏；测试数量；改了哪些文件；要在真机上看的；需要维护者决定的。
