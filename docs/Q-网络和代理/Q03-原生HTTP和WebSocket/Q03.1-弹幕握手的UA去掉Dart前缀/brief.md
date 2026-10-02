# Q03.1 弹幕握手的 User-Agent 去掉 Dart 前缀：任务书

## 背景

- 来源：`docs/specs/UPGRADES.md` 附录 B-2：弹幕握手的 User-Agent 不再带 `Dart/3.13 (dart:io)` 前缀（用户 2026-09-30 “按建议全部处理”）。I01.1 只做了开关，默认关，余下“Android 真机逐平台验证后改为默认开”没有任务；V03.3（2026-10-03）开了本任务。
- 现象：用户看不到；抓包能看到握手请求的 `User-Agent` 是 `Dart/3.13 (dart:io) Mozilla/5.0 …` 这样带前缀的。
- 为什么现在做：第三档，收益是请求更像浏览器；风险是 v3 实测 Android 直连时自定义 `HttpClient` 会让握手挂到超时（Q01.1 记录），所以要先在真机上逐平台确认。
- 已经做过的：I01.1（`connectIoSocket(plainUserAgent:)`、编译参数 `PURE_LIVE_PLAIN_WS_UA`）。

## 目标和验收

1. `record.md` 里有一张表：21 个平台 × 默认构建 / 打开开关的构建 × 直连 / 代理，每格写握手时间或“超时”。
2. 全部通过：默认构建就不带前缀（开关默认开，编译参数可以关）；有平台挂起：只对通过的平台打开，挂起的平台写明现象和原因线索。
3. `docs/specs/UPGRADES.md` 附录 B-2 的状态改“完成（Q03.1）”或写明哪些平台例外。
4. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- `packages/live_net/lib/src/socket.dart:45-55`：说明直连时用默认客户端的原因（v3 在 Android 上自定义直连客户端会挂起）。
- `socket.dart:56-66` 的 `webSocketClientFor(route, plainUserAgent:)`：直连且 `plainUserAgent` 时新建 `HttpClient()`；`:64` 把 `client.userAgent` 设成 null，这样只发调用方给的 `user-agent` 头。
- `socket.dart:75-90` 的 `connectIoSocket(...)`：`WebSocket.connect(endpoint, headers:, protocols:, customClient: client).timeout(connectTimeout)`，握手完关掉客户端。
- `apps/pure_live/lib/app/platforms.dart:245`：`const bool plainDanmakuUserAgent = bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA');`
- `platforms.dart:249-258`：`danmakuHandshake({bool plain = plainDanmakuUserAgent})` 开时返回调用 `connectIoSocket(..., plainUserAgent: true)` 的 `SocketConnector`，否则 null。
- `platforms.dart:196-238` 的 `buildDanmakuRegistry`：`final connector = danmakuHandshake();`，传给 21 个平台的连接（见 README 的列表）；YY（`YyDanmakuConnection.new`）、FC2、快手、niconico、YouTube、Steam、百度不用它。

## 3.x 基线

- `git show v3.2.11:lib/core/common/web_socket_util.dart`：`:39-46` 用 `IOWebSocketChannel.connect(…, customClient:)`；`:50-60` 的 `_createWebSocketHttpClient` 只在走代理时建 `HttpClient`，直连时不建（注释写着只回答 DIRECT 的自定义客户端会让握手挂起），所以 UA 带 dart:io 前缀。各平台握手的头（Origin、Referer、Cookie）照旧。
- v3 试过给直连握手传自定义客户端，在 Android 上挂到超时（Q01.1 记录写了现象，没查到原因）——这就是本任务要在真机上验证的风险。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 10 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/I-浏览和发现/I01-首页外壳和全局/I01.1-应用骨架/record.md`（B-2 一行）；`docs/Q-网络和代理/Q01-请求和编码/Q01.1-网络/record.md`（直连握手挂起）。

## 范围

- 可以改：`apps/pure_live/lib/app/platforms.dart`（`plainDanmakuUserAgent`、`danmakuHandshake`）；`apps/pure_live/test/platforms_test.dart`；必要时 `packages/live_net/lib/src/socket.dart` 和它的测试（只为修真机上发现的挂起）。
- 不能改：各平台弹幕协议（`packages/live_danmaku/lib/src/sites/`）；YY、FC2 的握手；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。不加用户设置（这是实现细节）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2：两种构建在 K90 上逐平台测 | `record.md` | 验收第 1 条的表填满 |
| 2 | c3、c4：按结果改默认值（全开或按平台开） | `app/platforms.dart`、`test/platforms_test.dart`、`UPGRADES.md` | 验收第 2～4 条 |

## 测试

- `platforms_test.dart`：默认构建下 `danmakuHandshake()` 不为 null（全开时）；按平台开时断言例外平台拿到 null。
- `packages/live_net/test/`：已有 `webSocketClientFor` 清空 UA 的用例，改了 `socket.dart` 时补用例（本机回环服务器检查收到的 `user-agent` 头；定时器至少 1 秒）。
- 改过的包跑 format、analyze、测试；`apps/pure_live` 跑全部 `flutter test`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 默认构建，直连：哔哩哔哩、斗鱼、虎牙、抖音、AcFun、猫耳 FM、克拉克拉、京东、酷狗、六间房、LOOK 各进一个直播间 | 弹幕状态几秒内变“已连接”，记下时间 |
| 2. `--dart-define=PURE_LIVE_PLAIN_WS_UA=true` 构建，同样的平台 | 同样几秒内连上，没有超时；时间和第 1 步差不多 |
| 3. 开着应用代理，两种构建各测 Twitch、SOOP、Picarto、TwitCasting、SHOWROOM、CHZZK、Kick、BIGO、PandaTV、17LIVE | 同上 |
| 4. 改完默认值后的正式测试包，抽 5 个平台再进一次 | 连得上；抓包（如电脑代理）看到握手的 `User-Agent` 没有 `Dart/` 前缀 |

## 风险和注意

- 挂起可能只在某些网络（直连、IPv6）出现；测试时写清网络环境。
- 不要把真实 Cookie 写进记录；抓包截图打码。
- 可能冲突的文件：`app/platforms.dart`（E06.2、E06.3 也改这里）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/Q03.1` 或本机工作区；提交信息以 `[Q03.1]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（测到哪个平台）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每个平台的结果；默认值怎么定的；改了哪些文件；测试数量；要在真机上再看的；可能冲突的文件。
