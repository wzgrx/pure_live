# Q03.1 弹幕握手的 User-Agent 去掉 Dart 前缀：任务书

## 背景

- 来源：`docs/specs/UPGRADES.md` 附录 B-2：弹幕握手的 User-Agent 不再带 `Dart/3.13 (dart:io)` 前缀（用户 2026-09-30 “按建议全部处理”）。I01.1 只做了开关，默认关，余下“Android 真机逐平台验证后改为默认开”没有任务；V03.3（2026-10-03）开了本任务。
- 现象：用户看不到；抓包能看到握手请求的 `User-Agent` 是 `Dart/3.13 (dart:io) Mozilla/5.0 …` 这样带前缀的。
- 前置风险（D 组核对时发现，v2 文档已核对）：`apps/pure_live/lib/app/platforms.dart:214` 给 SOOP 也传了 `danmakuHandshake()` 的连接器。SOOP 自己的默认连接器是保留大小写的握手（`connectExactWebSocketViaRoute`），开关一打开就被 `connectIoSocket` 顶掉，SOOP 的边缘不回答小写的握手头，SOOP 弹幕连不上。**打开开关之前，SOOP 必须先不再传 `connector`。**
- 为什么现在做：第三档，收益是请求更像浏览器；风险是 3.x 实测 Android 直连时自定义 `HttpClient` 会让握手挂到超时（Q01.1 记录），所以要在真机上逐平台确认。
- 已经做过的：I01.1（`connectIoSocket(plainUserAgent:)`、编译参数 `PURE_LIVE_PLAIN_WS_UA`）。

## 目标和验收

1. SOOP 登记时不再传通用连接器，`platforms.dart` 的注释写全哪些平台有自己的握手；测试断言开关开时 SOOP、YY、FC2 拿不到通用连接器、其余 20 个拿到。这一条单独合并（不改默认行为）。
2. `plainUserAgent` 有测试：本机回环服务器收到的 `user-agent`，默认以 `Dart/` 开头，开了以后等于调用方给的值。
3. `record.md` 里有一张表：21 个平台 × 默认构建 / 打开开关的构建 × 直连 / 代理（海外平台只测代理），每格写握手时间（3 次中位数）或“超时”；另一列写抓到的握手 UA（打开开关的构建）。
4. 全部通过：默认就不带前缀（开关默认开，编译参数可以关）。有平台挂起或因为没有 UA 被拒：只对通过的平台打开，例外平台写明现象和原因线索。
5. `docs/specs/UPGRADES.md` 附录 B-2 的状态改“完成（Q03.1）”或写明哪些平台例外。
6. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- `packages/live_net/lib/src/socket.dart:46-55`：说明直连时用默认客户端的原因（3.x 在 Android 上自定义直连客户端会挂起）。
- `socket.dart:56-66` 的 `webSocketClientFor(route, plainUserAgent:)`：直连且 `plainUserAgent` 时新建 `HttpClient()`；`:64` 把 `client.userAgent` 设成 null，这样只发调用方给的 `user-agent` 头（调用方没给就没有 UA）。
- `socket.dart:74-98` 的 `connectIoSocket(...)`：`WebSocket.connect(endpoint, headers:, protocols:, customClient: client).timeout(connectTimeout)`，握手完关掉客户端。
- `apps/pure_live/lib/app/platforms.dart:245`：`const bool plainDanmakuUserAgent = bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA');`
- `platforms.dart:247-258`：注释“YY and FC2 keep their own”（`:248`，漏了 SOOP）；`danmakuHandshake({bool plain = plainDanmakuUserAgent})` 开时返回调用 `connectIoSocket(..., plainUserAgent: true)` 的 `SocketConnector`，否则 null。
- `platforms.dart:196-238` 的 `buildDanmakuRegistry`：`final connector = danmakuHandshake();`（`:200`），传给 21 个平台；SOOP 在 `:214`。YY（`YyDanmakuConnection.new`）、FC2、快手、niconico、YouTube、Steam、百度不用它。
- 各平台的默认连接器（不传 `connector` 时）：SOOP 是 `_withoutPlainCookie(connector ?? connectExactWebSocketViaRoute)`（`packages/live_danmaku/lib/src/sites/soop.dart:162-166`；保留大小写的握手见 `packages/live_danmaku/lib/src/exact_websocket.dart:9-46`）；YY 是 `connectExactWebSocket`（`yy.dart:659`，没传）；FC2 是 `Fc2LiveControl.connect`（`fc2live.dart:441`，没传）；其余 20 个是 `connectIoSocket`（`socket_connection.dart:302`，以及 Picarto `picarto.dart:474`、TwitCasting `twitcasting.dart:183`、PandaTV `pandalive.dart:345`、LOOK `looklive.dart:683`、酷狗 `kugoulive.dart:919`、17LIVE `seventeenlive.dart:889`、BIGO `bigo.dart:460` 各自的 `connector ?? connectIoSocket`）。
- 握手的 UA 从哪来：`live_danmaku` 里抖音、SOOP、Picarto、TwitCasting、克拉克拉、SHOWROOM、CHZZK、Kick、BIGO、PandaTV、京东、酷狗、六间房、LOOK、17LIVE 的连接代码里写了或转发了 UA；哔哩哔哩、斗鱼、虎牙、Twitch、AcFun、猫耳的连接代码里没有，要看平台适配器给的 `*DanmakuArgs.headers`。打开开关后没有 UA 的握手就真的不带 UA。
- 测试：`packages/live_net/test/socket_test.dart:141-146` 只测“直连不建客户端、代理建客户端”，没有 `plainUserAgent` 的用例；`apps/pure_live/test/platforms_test.dart` 没有 `danmakuHandshake` 的用例。

## 3.x 基线

- `git show v3.2.11:lib/core/common/web_socket_util.dart`：`:33-47` 的 `_connectIoWebSocket` 用 `IOWebSocketChannel.connect(…, customClient:)`；`:49-62` 的 `_createWebSocketHttpClient` 只在走代理时建 `HttpClient`，直连时不建（注释写着只回答 DIRECT 的自定义客户端会让握手挂起），所以 UA 带 `dart:io` 前缀。各平台握手的头（Origin、Referer、Cookie）照旧。
- 3.x 的 YY、SOOP 用 `connectCaseSensitiveWebSocket`（4.x 的 `exact_websocket.dart`），自己写握手请求，不受 `dart:io` 的 UA 影响。
- 3.x 给直连握手传自定义客户端，在 Android 上挂到超时（Q01.1 记录写了现象，没查到原因）——这就是本任务要在真机上验证的风险。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 10 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/Q-网络和代理/Q03-原生HTTP和WebSocket/README.md`（已知问题）；`docs/I-浏览和发现/I01-首页外壳和全局/I01.1-应用骨架/record.md`（B-2 一行）；`docs/Q-网络和代理/Q01-请求和编码/Q01.1-网络/record.md`（直连握手挂起）；`docs/D-弹幕/D01-平台弹幕协议/README.md` 的已知问题（SOOP）和 `D01.8-SOOP弹幕/record.md`、`D01.7-YY直播弹幕/record.md`（保留大小写的握手为什么需要）。

## 范围

- 可以改：`apps/pure_live/lib/app/platforms.dart`（`plainDanmakuUserAgent`、`danmakuHandshake`、SOOP 的登记、注释）；`apps/pure_live/test/platforms_test.dart`；`packages/live_net/test/socket_test.dart`（补用例）；必要时 `packages/live_net/lib/src/socket.dart`（只为修真机上发现的挂起）；`docs/specs/UPGRADES.md` 的 B-2 一行；本文件夹的 `record.md`。
- 不能改：各平台弹幕协议（`packages/live_danmaku/lib/src/sites/`）和平台适配器（`packages/live_core`）——缺 UA 的平台只在报告里列出，补 UA 由维护者决定开在 E/D 组；YY、FC2、SOOP 的握手；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。不加用户设置（这是实现细节）。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 SOOP 不再传 `connector`、注释写全；c2 补 `plainUserAgent` 测试；c3 两种构建在 K90 上逐平台测、抓握手 UA | `app/platforms.dart`、`test/platforms_test.dart`、`packages/live_net/test/socket_test.dart`、`record.md` | 验收第 1～3 条；c1、c2 合并进 master |
| 2 | c4 按结果改默认值（全开或按平台开）；c5 更新 B-2 | `app/platforms.dart`、`test/platforms_test.dart`、`UPGRADES.md` | 验收第 4～6 条 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- `apps/pure_live/test/platforms_test.dart`：
  - `with the plain handshake on, SOOP, YY and FC2 keep their own connectors`：用 `danmakuHandshake(plain: true)` 建登记（需要时给 `buildDanmakuRegistry` 加一个只给测试用的 `connector` 参数，或把“哪些平台拿通用连接器”提成一个常量集合来断言），断言 SOOP 的连接用的是它自己的默认连接器——改之前会失败。
  - 改默认值后：默认构建下 `danmakuHandshake()` 不为 null（全开时）；按平台开时断言例外平台拿到 null。
- `packages/live_net/test/socket_test.dart`：
  - `the default handshake sends dart:io's User-Agent prefix`：本机回环 `HttpServer` 升级 WebSocket，记下请求的 `user-agent`，`connectIoSocket(..., headers: {'user-agent': 'Mozilla/5.0 test'})` 时以 `Dart/` 开头。
  - `plainUserAgent sends only the caller's User-Agent`：同上，`plainUserAgent: true` 时等于 `Mozilla/5.0 test`；不给时请求里没有 `user-agent`。
  - 定时器至少 1 秒；不访问真实平台。
- 改过的包跑 format、analyze、测试；`apps/pure_live` 跑全部 `flutter test`。

## 真机验证（维护者在 K90 上做）

准备：本机构建两个 profile 包（都是 `com.mystyle.purelive.v4dev`，先后安装）：默认构建、加 `--dart-define=PURE_LIVE_PLAIN_WS_UA=true` 的构建；阶段 1 的 c1 先合并，两个包里 SOOP 都用自己的握手。`adb -s 192.168.1.2:5555 logcat -s flutter` 看弹幕连接日志；抓握手时电脑上开代理工具（例如 Clash 的连接日志或 mitmproxy），K90 的应用代理指向它（Android 17 先给“本地网络”权限，O04.1）。

| 步骤 | 期望 |
|---|---|
| 1. 默认构建，直连：哔哩哔哩、斗鱼、虎牙、抖音、AcFun、猫耳 FM、克拉克拉、京东、酷狗、六间房、LOOK 各进一个直播间，每个 3 次 | 弹幕状态几秒内变“已连接”，记下时间 |
| 2. 打开开关的构建，同样的平台 | 同样几秒内连上，没有超时；中位数和第 1 步差不到 500 毫秒 |
| 3. 开着应用代理，两种构建各测 Twitch、SOOP、Picarto、TwitCasting、SHOWROOM、CHZZK、Kick、BIGO、PandaTV、17LIVE | 同上；SOOP 两种构建都能连上 |
| 4. 打开开关的构建，开着应用代理，各平台进一次，在代理工具里看握手请求的 `User-Agent` | 是 `Mozilla/…` 的浏览器 UA，没有 `Dart/`；记下哪些平台的握手没有 UA |
| 5. 改完默认值后的测试包，抽 5 个平台（含 SOOP、哔哩哔哩）再进一次 | 连得上；握手 UA 没有 `Dart/` 前缀 |

## 风险和注意

- **SOOP**：c1 没做之前不要发打开开关的构建给别人用；c1 的测试要能挡住以后有人再给 SOOP 传通用连接器。
- **没有 UA 的握手**：清空 `dart:io` 的 UA 后，平台没给 UA 的握手就完全没有 UA，个别服务器可能拒绝；第 4 步记下这些平台，补 UA 要改平台代码（不在本任务范围），报告里列出。
- **挂起只在某些网络出现**：3.x 的挂起可能和直连、IPv6、运营商有关；测试时写清网络环境（Wi-Fi、IPv4/IPv6）；有条件时移动数据下再测几个国内平台。
- 不要把真实 Cookie 写进记录；抓包截图打码。
- 可能冲突的文件：`app/platforms.dart`（E06.2、E06.3 也改这里）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/Q03.1` 或本机工作区；提交信息以 `[Q03.1]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（测到哪个平台）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

c1 做了没有；每个平台的结果（握手时间、UA）；默认值怎么定的、例外平台和原因；没有 UA 的平台列表；改了哪些文件；测试数量（改之前失败几个）；要在真机上再看的；可能冲突的文件。
