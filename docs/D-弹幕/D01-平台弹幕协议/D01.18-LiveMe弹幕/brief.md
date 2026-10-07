# D01.18 LiveMe 弹幕：任务书

> 状态“受阻”。**解除条件满足之前不要开工。** 本任务书写清阻塞的原因、怎么判断已经解除、解除后怎么做；解除后维护者把登记表改成“已确认”、写档位，并在本页顶部注明按哪一条解除。

## 背景

- 来源：已批准升级 21-9“LiveMe 弹幕”（`docs/specs/UPGRADES.md` 第 160 行，状态“受阻”）。3.x 有 LiveMe 这个平台但没有弹幕（`~/ref/v3ref/lib/core/site/liveme/liveme_site.dart:38`，`EmptyDanmaku`），这是新增功能，没有 3.x 行为可对照。
- 现象：进 LiveMe 直播间，聊天区显示“LiveMe的直播间没有弹幕 / 醒目留言、弹幕设置、屏蔽管理照常可用”，没有任何聊天；房间信息里的公告是“这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。”
- 为什么受阻：2026-09-29 调查（提交 2d1994160，记录 [record.md](record.md)）读了官网网页脚本，查清了聊天协议和进聊天室的条件，结论是要登录账号才能进聊天室，没有游客通道（见下节）。登记表说明“要登录才能连弹幕，调查完成”。
- 已经做过的：调查和文档（2d1994160，没有代码）；平台层 [E03.8](../../../E-直播平台/E03-海外平台/E03.8-LiveMe/record.md) 已有本场直播 id `LiveMeRoomData.videoId`（等于聊天室 id `TCRoomId`）和公告 `LiveMeApi.chatNotice`。

## 阻塞原因和解除条件

**阻塞的原因**（读官网 `www.liveme.com/static/CLaEtC7T.js`、`CYslo3Yc.js` 得出，2026-09-29）：

1. 官网只在登录后建 IM 连接：`app-im-kit` 状态监听登录状态（立即执行一次），登录了才调 `createIM`，没登录就销毁 IM；`createIM` 还要求用户信息里有设备号。
2. 直播间只在登录分支里调用 `joinRoom(vid)`；游客走 `anonymous-user` 播放路径，只放流就返回。即使调用了，没有 IM 实例时 `joinRoom` 只打印“加入房间失败，不存在IM”。
3. IM 的 `LOGIN` 包要账号的 uid（`userInfo.user.uid`）和登录令牌（`userInfo.token`），收到登录成功的应答前客户端不发进聊天室的包；网页端没有给游客发 IM 令牌的接口。
4. 其他路子都不通：`msgfile` 在播时 404（回放用），`imapi.liveme.com` 只有要 `cmimToken` 加签名的私信接口，旧版 SDK `/app/spa/js/im.js` 也要令牌，App 端要抓包和签名。

**项目规则**（D01 平台弹幕任务的统一规则）：需要签名、登录、抓包或第三方 SDK 密钥才能连的不硬做，不绕过平台的访问限制——不用空的 uid、令牌去试 IM 服务器，不抓 App 的包，不注册账号。

**解除条件（满足任一条才能开工）**：

| # | 条件 | 怎么判断（逐条可检查） | 谁来定 |
|---|---|---|---|
| A | 本项目决定支持 LiveMe 账号登录 | ① [V01](../../../V-需求和反馈/V01-新功能提议/README.md) 有“LiveMe 登录”的提议，用户确认，[DECISIONS.md](../../../DECISIONS.md) 记了一条（D-026 的流程）；② K 组登记的“LiveMe 登录”任务完成：账号页（`apps/pure_live/lib/features/account/account_platforms.dart:82～141`）有 LiveMe，`CookieVault` 能存 LiveMe 的 uid、登录令牌和设备号，平台层能读出来 | 用户（新功能）；维护者登记任务 |
| B | LiveMe 开放了游客聊天 | 重读官网脚本，出现未登录也调用 `createIM`、`joinRoom` 的路径，或有给游客发 IM 令牌的公开接口；写进本文件夹的 `record-2.md`，附脚本文件名和下载时间。由平台巡检 [E07.1](../../../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md) 或维护者定期复查 | 维护者 |

现在两条都不满足：V01 和 K 组都没有 LiveMe 登录的任务，E07.1 还没开始。

## 目标和验收（解除后）

1. 进一个在播的 LiveMe 直播间（条件 A 时已登录 LiveMe）：聊天区从“连接中”变成已连接，有人发言时 3 s 内出现聊天，名字和文字正确，列表和画面上都有。
2. 断网 30 s 再恢复：聊天区出现一次“正在重连”，恢复后自动重新登录 IM、重新进聊天室，聊天继续。
3. 条件 A 时，没有登录 LiveMe 的用户进房：不连接、不发任何 IM 请求，聊天区照现在的空状态（或直播间另定的登录引导），不出现“连接中”。
4. IM 登录被拒（`Ack.statecode` 不是 0）：以 `credentialsUnavailable` 结束，只提示一次，不反复重连。
5. 主播下播：连接结束（或交给直播间 60 s 刷新判断），不无限重连。
6. uid、令牌、设备号、会话号不出现在任何事件的 `detail`、日志、测试和样本里。
7. `packages/live_danmaku/test/sites/liveme_test.dart` 覆盖协议编解码（对照录制样本）、连接时序、登录被拒、断线重连；`apps/pure_live/test/platforms_test.dart:47～67` 的“没有弹幕的平台”集合去掉 `SiteIds.liveMe`；门禁通过。

## 现状（读代码得出，写文件:行）

- 平台表：`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 LiveMe、TikTok 受阻、不登记；`buildDanmakuRegistry`（:196～239）里没有 `SiteIds.liveMe`。
- 登记表：`packages/live_danmaku/lib/src/registry.dart`：`supports`（:75）为假，`connectionFor`（:79）给 `EmptyDanmakuConnection`（:13，不连接、不报事件）。
- 直播间：`apps/pure_live/lib/features/live_play/live_play_page.dart:279` 把 `danmaku.supports(site.id)` 传给控制器；`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～822`：`danmakuSupported` 为假时设 `ChatConnection.unsupported`，只加一次系统行 `live_play_danmaku_unsupported`“该平台暂不支持弹幕”；聊天列表在只有系统行时显示空状态（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:414～419`），`unsupported` 的空状态是 `live_play_chat_unsupported`“{platform}的直播间没有弹幕”和说明（:287～295）。
- 平台层：`packages/live_core/lib/src/sites/liveme/liveme_api.dart:422` 的 `chatNotice`（:840 放进每个房间）；`LiveMeRoomData.videoId`；没有弹幕参数类，没有任何 Cookie 读取（E03.8：全程匿名）。
- 弹幕包：`packages/live_danmaku/lib/src/sites/` 下没有 `liveme.dart`。可复用：`src/codec/protobuf.dart`（`ProtoMessage` :27、`ProtoWriter` :162，抖音、AcFun、YouTube 在用）；Socket.IO 的写法参考 `sites/kilakila.dart`（`KilakilaDanmakuProtocol` :103 起，只有文本事件，LiveMe 要二进制事件和占位符）；会话凭据和握手被拒的钩子参考 `sites/missevan.dart`（`onHandshakeFailure` :847）。
- 样本：`fixtures/liveme/` 只有 E03.8 的接口样本（S01～S05），没有弹幕样本。

## 3.x 基线

- `~/ref/v3ref/lib/core/site/liveme/liveme_site.dart:38`：`getDanmaku() => EmptyDanmaku()`；:82 公告 `liveme_chat_notice`（`assets/translations/zh.json:1868`：“LiveMe 远端聊天尚待接入；热度、当前观看和累计观看分别展示。”）。
- `~/ref/v3ref/lib/modules/live_play/controllers/danmaku_controller.dart:146～150`：没有弹幕的平台不连接，只提示一次 `remote_danmaku_not_integrated`（“此平台的远端弹幕尚未接入；可在设置中开启本地互动，仅在本机显示。”）。
- 3.x 没有 LiveMe 登录，也没有它的 Cookie 设置。要保留的：没有弹幕时不连接、只提示一次。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 6 节新功能、第 7 节交给其他 AI、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`、`record.md`（“查明的协议”是全部协议细节）。
4. `docs/D-弹幕/D01-平台弹幕协议/D01.1-弹幕框架和过滤/record.md`（连接接口、`DanmakuSocketConnection` 的 `target`、`onOpen`、`onData`、`heartbeatFrame`，按一次 `connect` 失效）；参考实现 `packages/live_danmaku/lib/src/sites/kilakila.dart`、`missevan.dart`、`acfun.dart`。
5. 条件 A 时：K 组 LiveMe 登录任务的记录（Cookie 怎么存、怎么读）；条件 B 时：`record-2.md` 的游客路径。

## 范围

- 可以改：`packages/live_danmaku/lib/src/sites/liveme.dart`（新建）、`packages/live_danmaku/lib/live_danmaku.dart`（加一行导出）、`packages/live_danmaku/test/sites/liveme_test.dart`（新建）、`packages/live_core/lib/src/sites/liveme/`（只加 `LiveMeDanmakuArgs` 和放进 `danmakuData` 的代码，以及对应测试）、`fixtures/liveme/danmaku/`（新样本）、`apps/pure_live/lib/app/platforms.dart`（登记一行、改注释）、`apps/pure_live/test/platforms_test.dart`（集合去掉 LiveMe）、本文件夹。
- 不能改：框架文件（`connection.dart`、`connection_base.dart`、`socket_connection.dart`、`registry.dart`，需要改时先问维护者）；其他平台；直播间界面和提示文字（A08、C01）；账号页和登录（K 组）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；不能把任何真实的 uid、令牌、设备号、Cookie 写进代码、测试或样本。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 0 | 确认解除条件：A 时 K 组登录任务已完成、能从 `CookieVault` 读出 uid、令牌、设备号；B 时写清游客路径。重新下载官网脚本，逐项核对 record.md“查明的协议”（服务器、路径 `/live.me`、`cmcm=3`、事件名、`User`/`IMMessage`/`Ack` 的字段号） | `record-2.md`（新建） | 维护者确认，登记表改“已确认” |
| 1 | 录样本：维护者用自己的账号（A）或游客（B）只读进一个在播直播间 3～5 分钟，录 IM 的收发帧（含 `SESSIONID`、`LOGIN` 应答、`LIVE` 应答、聊天、`PULL`）；脱敏 uid、令牌、设备号、会话号、观众名字和头像 | `fixtures/liveme/danmaku/S06-live/`（`frames.jsonl`、`meta.json`） | 门禁 `fixture privacy` 通过 |
| 2 | 平台层参数：`LiveMeDanmakuArgs(videoId, uid, token, deviceId)`，进房（`getRoomDetail`）在播且有登录时放进 `danmakuData`；录制详情、关注刷新不给 | `packages/live_core/lib/src/sites/liveme/` | `live_core` 的 LiveMe 测试通过，原有断言不变 |
| 3 | 协议和连接：Socket.IO 二进制事件（文本占位包加二进制帧）、Engine.IO ping、`LOGIN` → 等 `Ack.type` 1 → `LIVE`（ROOM_LOGIN）→ 等 `Ack.type` 6 就绪；收 `LIVE {cmd:20}`、`{cmd:50}`；`PULL {cmd:-100}` 回 `PULL`；两台服务器轮换；聊天解成白色 `LiveMessage`（消息名和字段以样本为准）；自己的会话号发的消息丢掉 | `packages/live_danmaku/lib/src/sites/liveme.dart`、`live_danmaku.dart` | `liveme_test.dart` 通过（见“测试”） |
| 4 | 登记：`SiteIds.liveMe: () => LiveMeDanmakuConnection(proxy: proxy, connector: connector)`，改掉注释里的受阻说明；E03.8 的公告 `chatNotice` 去掉“这里暂时看不到……聊天”半句 | `apps/pure_live/lib/app/platforms.dart`、`apps/pure_live/test/platforms_test.dart`、`liveme_api.dart` | 应用的 `platforms_test.dart` 通过；门禁通过 |

每个阶段都要能单独合并（门禁通过、不留半截功能）；阶段 2 合并后还没有连接，界面不变。

## 测试

- `packages/live_danmaku/test/sites/liveme_test.dart`：
  - 协议：`LOGIN`、`LIVE`（ROOM_LOGIN）、`PULL` 的编码与样本逐字节相同；Socket.IO 二进制事件的拼包和拆包；坏帧丢掉这一帧不影响连接；
  - 录制回放：样本里每条聊天的名字、文字、时间逐条对上；自己会话号的消息不报；
  - 连接：登录应答前不发进聊天室、`Ack.type` 6 后就绪、登录被拒（`statecode` 非 0）以 `credentialsUnavailable` 结束、两台服务器轮换、断线后重新登录并进聊天室、关闭后没有事件、详情不带令牌；本地 WebSocket 服务器端到端。
- `live_core`：`LiveMeDanmakuArgs` 只在在播且有登录时给出。
- 应用：`apps/pure_live/test/platforms_test.dart` 的“没有弹幕的平台”集合去掉 `SiteIds.liveMe`，`connectionFor(SiteIds.liveMe)` 是 `LiveMeDanmakuConnection`。
- 测试里的定时器至少 1 秒；不访问真实平台（只用 `fixtures/`）；用到样本时间的把“现在”固定成录制时间（D-017）。

## 真机验证（维护者在 K90 上做，要开代理）

| 步骤 | 期望 |
|---|---|
| 1. 条件 A：在账号页登录 LiveMe；首页 → LiveMe → 精选里人最多的在播直播间 | 聊天区先“连接中”，随后已连接，1 分钟内出现聊天，画面上有飞行弹幕 |
| 2. 关 Wi-Fi 30 s 再开 | 出现一次“正在重连”，恢复后聊天继续 |
| 3. 退出 LiveMe 登录，再进同一直播间 | 不出现“连接中”，聊天区是“LiveMe的直播间没有弹幕”（或直播间另定的登录引导） |
| 4. 进一个即将下播的直播间，等主播下播 | 连接结束，不反复重连 |

## 风险和注意

- 官网脚本是压缩过的，函数名和字段号会随更新变；阶段 0 必须重新核对协议，不能直接照 record.md 写。
- 账号令牌是敏感信息：只从 `CookieVault` 读，不进日志、事件详情、样本；样本由维护者录制和脱敏，执行者不拿账号。
- 用户账号在 LiveMe 的风控：只读进聊天室、不发言；每个直播间只开一个 IM 连接；不要同时在官网登录同一账号测试（IM 可能互踢）。
- 和 E03.8（平台层）、K 组（登录）改同一批文件：同一时间只开一个。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/D01.18` 或本机工作区；提交信息以 `[D01.18]` 开头（英文）；不推 master。
- 提交前：`packages/live_danmaku`、`packages/live_core` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record-2.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。阶段 0 没通过（条件不满足）时不要往下做，在 `record-2.md` 写明哪一条不满足，状态保持“受阻”。

## 报告（中文，简洁）

按哪一条解除；每条验收做到没有；协议和 record.md 不同的地方；样本和脱敏；测试数量；改了哪些文件；新设置和翻译键（应该没有）；要在真机上看的；需要维护者决定的（例如未登录时的提示文字）；可能冲突的文件。
