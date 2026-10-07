# D01.18 LiveMe 弹幕：任务书

> 状态“受阻”。**解除条件满足之前不要开工**；本任务书写清阻塞的原因、怎么判断已经解除、解除后怎么做。

## 背景

- 来源：已批准升级 21-9“LiveMe 弹幕”（`docs/specs/UPGRADES.md` 第 160 行，状态“受阻”）。3.x 的 LiveMe 没有弹幕（`EmptyDanmaku`），这是新增功能。
- 现象：进 LiveMe 直播间，聊天区只出现一次“该平台暂不支持弹幕”，没有任何聊天。
- 已经做过的：2026-09-29 的调查（提交 2d1994160，记录 `record.md`），读了官网网页脚本，查清了聊天协议和进聊天室的条件，结论是要登录，没写代码。平台层（E03.8）已有本场直播 id `LiveMeRoomData.videoId`（等于聊天室 id `TCRoomId`）。

## 阻塞和解除条件

**阻塞的原因**（record.md“受阻的原因”，读官网 `www.liveme.com/static/CLaEtC7T.js`、`CYslo3Yc.js` 得出）：

1. 官网只在登录后建 IM 连接：`app-im-kit` 状态监听登录状态，没登录就销毁 IM；`createIM` 还要求用户信息里有设备号。
2. 直播间只在登录分支里调用 `joinRoom(vid)`；游客走 `anonymous-user` 路径，只放流。
3. IM 的 `LOGIN` 包要账号的 uid（`userInfo.user.uid`）和登录令牌（`userInfo.token`），服务端回登录成功后客户端才发进聊天室的包；网页端没有给游客发 IM 令牌的接口。
4. 其他路子都不通：`msgfile` 在播时 404，`imapi.liveme.com` 只有要签名的私信接口，旧版 SDK `/app/spa/js/im.js` 也要令牌，App 端要抓包和签名（不做）。

**项目规则**：不绕过平台的限制（不用空的 uid、令牌去试 IM 服务器），不抓 App 的包，不注册账号。

**解除条件（满足任一条才能开工）**：

| # | 条件 | 怎么判断 | 谁来定 |
|---|---|---|---|
| A | 本项目决定支持 LiveMe 账号登录 | 按 D-026 先在 V01 登记新功能提议、写方案、用户确认；然后 K 组登记“LiveMe 登录”任务并完成：`CookieVault` 能存 LiveMe 的 uid、登录令牌和设备号，平台层能读出来 | 用户（新功能）；维护者登记任务 |
| B | LiveMe 开放了游客聊天 | 官网脚本里出现游客也能建 IM 连接、进聊天室的路径（例如未登录时也调用 `createIM`、`joinRoom`，或有给游客发 IM 令牌的接口）；平台巡检（E07.1）或定期复查时重读 `CLaEtC7T.js`、`CYslo3Yc.js` 确认 | 维护者 |

解除后：维护者把登记表的状态改成“已确认”、写档位，并在本任务书顶部注明按哪一条解除。

## 目标和验收（解除后）

1. 进一个在播的 LiveMe 直播间（条件 A 时已登录 LiveMe），聊天区显示“已连接”，有人发言时 3 s 内出现聊天（名字、文字）。
2. 断网 30 s 再恢复：出现一次“正在重连”，恢复后自动重新登录 IM、重新进聊天室、再次“已连接”。
3. 条件 A 时，没有登录 LiveMe 的用户进房：不连接，聊天区照现在只提示一次（文字由直播间决定），不出现“连接中”。
4. 主播下播：连接结束，不无限重连。
5. 令牌、uid、设备号不出现在任何事件的 `detail`、日志和样本里。
6. `live_danmaku` 的测试覆盖协议编解码（对照录制样本）、连接时序、登录被拒、断线重连；门禁通过。

## 现状（读代码得出）

- 平台表：`apps/pure_live/lib/app/platforms.dart:190～195` 的注释写明 LiveMe 受阻、不登记；`DanmakuRegistry.connectionFor('liveme')` 返回 `EmptyDanmakuConnection`（`packages/live_danmaku/lib/src/registry.dart`）。
- 直播间：`apps/pure_live/lib/features/live_play/logic/room_controller.dart:816～821`，`danmakuSupported` 为假时设 `ChatConnection.unsupported` 并只提示一次 `live_play_danmaku_unsupported`。
- 平台层：`packages/live_core/lib/src/sites/liveme/liveme_api.dart` 有 `LiveMeRoomData.videoId` 和公告 `chatNotice`（:422）；没有弹幕参数类，没有任何 Cookie 读取（E03.8：全程匿名，不注入 `CookieVault`）。
- 弹幕包：`packages/live_danmaku/lib/src/sites/` 下没有 `liveme.dart`；可复用的有 `src/codec/protobuf.dart`（`ProtoMessage`、`ProtoWriter`，抖音、AcFun 在用）和 KilaKila 的“只实现用到的那部分 Socket.IO”的写法（`sites/kilakila.dart:103` 起，只有文本事件；LiveMe 要二进制事件）。

## 3.x 基线

- `~/ref/v3ref/lib/core/site/liveme/liveme_site.dart:38`：`getDanmaku() => EmptyDanmaku()`。
- `~/ref/v3ref/lib/modules/live_play/controllers/danmaku_controller.dart:150`：没有弹幕的平台提示一次 `remote_danmaku_not_integrated`（“此平台的远端弹幕尚未接入；可在设置中开启本地互动，仅在本机显示。”）。
- 3.x 没有 LiveMe 登录，也没有它的 Cookie 设置。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 7 节交给其他 AI、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`、`record.md`（“查明的协议”是全部协议细节）。
4. `docs/D-弹幕/D01-平台弹幕协议/D01.1-弹幕框架和过滤/record.md`（连接接口、`DanmakuSocketConnection` 的四样、按 run 失效）；参考实现 `packages/live_danmaku/lib/src/sites/kilakila.dart`（Socket.IO）、`missevan.dart`（会话 Cookie、`onHandshakeFailure`）、`acfun.dart`（protobuf 和加入超时两级）。
5. 条件 A 时：K 组 LiveMe 登录任务的记录（Cookie 怎么存、怎么读）。

## 范围

- 可以改：`packages/live_danmaku/lib/src/sites/liveme.dart`（新建）、`packages/live_danmaku/lib/live_danmaku.dart`（加一行导出）、`packages/live_danmaku/test/sites/liveme_test.dart`（新建）、`packages/live_core/lib/src/sites/liveme/`（只加 `LiveMeDanmakuArgs` 和放进 `danmakuData` 的代码）、`fixtures/liveme/danmaku/`（新样本）、`apps/pure_live/lib/app/platforms.dart`（登记一行、改注释）。
- 不能改：框架文件（`connection.dart`、`connection_base.dart`、`socket_connection.dart`，需要改时先问维护者）；其他平台；直播间界面和提示文字（归 C、A 组）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；不能把任何真实的 uid、令牌、设备号、Cookie 写进代码、测试或样本。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 0 | 确认解除条件：A 时 K 组登录任务已完成并能从 `CookieVault` 读出 uid、令牌、设备号；B 时重读官网脚本，写清游客路径。重新核对 record.md“查明的协议”是否仍然成立（服务器、路径 `/live.me`、事件名、protobuf 字段） | `record-2.md`（新建） | 维护者确认，登记表改“已确认” |
| 1 | 录样本：维护者用自己的账号（条件 A）或游客（条件 B）只读进一个在播直播间 3～5 分钟，录 IM 的收发帧；脱敏 uid、令牌、设备号、观众名字和头像 | `fixtures/liveme/danmaku/S01-live/`（`frames.jsonl`、`meta.json`） | 门禁 `fixture privacy` 通过 |
| 2 | 平台层参数：`LiveMeDanmakuArgs(videoId, uid, token, deviceId)`，进房（`getRoomDetail`）在播且有登录时放进 `danmakuData`；录制详情、关注刷新不给 | `packages/live_core/lib/src/sites/liveme/` | `live_core` 的 LiveMe 测试通过，旧的不变 |
| 3 | 协议和连接：Socket.IO 二进制事件（`451-["LOGIN",{"_placeholder":true,"num":0}]` 加二进制帧）、Engine.IO ping、`LOGIN` → `LIVE`（ROOM_LOGIN）→ 收 `LIVE {cmd:20/50}`、`PULL {cmd:-100}` 回 `PULL`；登录成功前不发进聊天室；两台服务器轮换；聊天解成白色 `LiveMessage`（消息名和字段以样本为准） | `packages/live_danmaku/lib/src/sites/liveme.dart`、`live_danmaku.dart` | `liveme_test.dart`：样本回放的聊天逐条对上、连接时序、登录被拒以 `credentialsUnavailable` 结束、断线重连重新登录 |
| 4 | 登记：`SiteIds.liveme: () => LiveMeDanmakuConnection(proxy: proxy)`，改掉注释里的“blocked” | `apps/pure_live/lib/app/platforms.dart` | 应用的 `platforms_test.dart` 通过；门禁通过 |

## 测试

- `packages/live_danmaku/test/sites/liveme_test.dart`：
  - 协议：`LOGIN`、`LIVE`（ROOM_LOGIN）、`PULL` 的编码与样本逐字节相同；Socket.IO 二进制事件的拼包和拆包；坏帧丢掉这一帧不影响连接；
  - 录制回放：样本里每条聊天的名字、文字、时间逐条对上；
  - 连接：登录应答前不发进聊天室、`Ack.type` 6 后就绪、登录被拒（`statecode` 非 0）结束、两台服务器轮换、关闭后没有事件、详情不带令牌；本地 WebSocket 服务器端到端。
- `live_core`：`LiveMeDanmakuArgs` 只在在播且有登录时给出。
- 测试里的定时器至少 1 秒；不访问真实平台（只用 `fixtures/`）；用到样本时间的把“现在”固定成录制时间（D-017）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 条件 A：在账号页登录 LiveMe；进精选里人最多的在播直播间 | 聊天区“已连接”，1 分钟内出现聊天 |
| 2. 关 Wi-Fi 30 s 再开 | 出现一次“正在重连”，恢复后“已连接”，聊天继续 |
| 3. 退出 LiveMe 登录，再进同一直播间 | 只提示一次“该平台暂不支持弹幕”（或直播间定的登录引导），不出现“连接中” |
| 4. 等主播下播（或进一个即将下播的直播间） | 连接结束，不反复重连 |

## 风险和注意

- 官网脚本是压缩过的，函数名会随更新变；阶段 0 必须重新核对协议，不能直接照 record.md 写。
- 账号令牌是敏感信息：只从 `CookieVault` 读，不进日志、不进事件详情、不进样本；样本由维护者录制和脱敏，执行者不拿账号。
- 用户账号在 LiveMe 的风控：只读进聊天室、不发言；每个直播间只开一个 IM 连接。
- 和 E03.8（平台层）、K 组（登录）的文件可能冲突：同一时间只开一个。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/D01.18` 或本机工作区；提交信息以 `[D01.18]` 开头（英文）；不推 master。
- 提交前：`packages/live_danmaku`、`packages/live_core` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`apps/pure_live` 跑 `flutter test test/platforms_test.dart`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record-2.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。阶段 0 没通过（条件不满足）时不要往下做，在 `record-2.md` 写明哪一条不满足，状态保持“受阻”。

## 报告（中文，简洁）

按哪一条解除；每条验收做到没有；协议和 record.md 不同的地方；样本和脱敏；测试数量；改了哪些文件；要在真机上看的；需要维护者决定的（例如未登录时的提示文字）。
