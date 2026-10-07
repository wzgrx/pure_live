# Q03 原生HTTP和WebSocket

两类 `dart:io` 的 HTTP 客户端办不好的通信：要用系统 TLS 才过得去的请求（Twitch GraphQL 在代理后、Kick 的 Cloudflare），以及弹幕用的长连接 WebSocket（握手、代理隧道、重连、心跳、半开检测、握手的 User-Agent）。

## 范围

- 包括：
  - `apps/pure_live/lib/platform/native_http.dart`：`AndroidNativeHttp`（`LiveHttp` 的实现，经通道 `pure_live/native_http` 用 Android 的 `HttpURLConnection` 和系统 TLS），和 Kotlin 一侧 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/AppChannelsPlugin.kt:191-230`（白名单、8 MiB 上限）。
  - `apps/pure_live/lib/platform/twitch_webview_http.dart`：`TwitchWebViewHttp`（无界面浏览器打开 twitch.tv 的空白页，跑 KPSDK 拿完整性令牌再发 GraphQL；Android 的 WebView 代理覆盖是全进程的，一次只开一个页面）。
  - `packages/live_net/lib/src/socket.dart`：`SocketChannel`、`SocketConnector`、`webSocketClientFor`、`connectIoSocket`、`LiveSocket`（多地址轮换、有限次数重连、心跳和沉默检测、分代、关闭握手时限）。
  - 弹幕握手 User-Agent 的开关：`apps/pure_live/lib/app/platforms.dart:240-258`（`plainDanmakuUserAgent`、`danmakuHandshake`）和它在弹幕登记里的传递（`:200`，传给 21 个平台）——Q03.1。
- 不包括（归哪里）：
  - 各平台弹幕的协议、帧、心跳内容、登录包，以及 `packages/live_danmaku` 的 `DanmakuSocketConnection`（`socket_connection.dart`）怎么用 `LiveSocket` → [D01](../../D-弹幕/D01-平台弹幕协议/README.md)。YY、SOOP 的“保留大小写的握手”`exact_websocket.dart` 也归 D01（本子分类只关心它和 Q03.1 开关的关系）。
  - 普通 HTTP 请求 → [Q01](../Q01-请求和编码/README.md)；代理路线 → [Q02](../Q02-代理和镜像/README.md)。
  - Twitch、Kick 的接口内容和回退顺序（`TwitchSite(gqlFallbacks:)`、`KickSite(apiHttp:)`）→ E03.2、E03.16；Windows 上的 WinHTTP 通道 → X01.2。
  - FC2 的媒体控制连接（`Fc2LiveControl.connect`，每 15 秒 ping）→ E03.13、G01 的配方。

## 现状：做到哪、怎么工作的

- 用户看得到的：Android 上能播 Twitch（GraphQL 先走 `dart:io`，失败时依次走原生通道和无界面浏览器）和 Kick（全部接口走原生通道；只有 Android 登记了 Kick，`platforms.dart:172`）；各平台弹幕连上后断网会显示状态行、恢复后自动重连，连续 8 次失败才放弃。
- 内部怎么工作：
  - 原生通道：`AndroidNativeHttp.send`（`native_http.dart:38-65`）只放行 `allowedHosts`（`:23`：`gql.twitch.tv`、`kick.com`，必须 https），带上应用代理的主机和端口（`HttpProxyRoute` 时），超时用请求的超时；取消时不等通道结果；`decodeNativeAnswer`（`:68`）把状态、头、体变回 `LiveResponse`。`open` 只是一次读完的包装（`:83-92`），不是真流式。Kotlin 侧在 `AppChannelsPlugin.kt:196`（`ALLOWED_HOSTS`）、`:197`（`MAX_RESPONSE_BYTES` 8 MiB）、`:216`（https 和白名单检查）。
  - 应用里：`bootstrap.dart:160` 只在 Android 建它；`:175-178` 把它和 `TwitchWebViewHttp` 作为 Twitch 的 GraphQL 回退；`kickApi: native`（`:179`）。
  - WebSocket：`LiveSocket`（`socket.dart:135`）按 `endpoints` 顺序连接，失败立即换下一个，每轮之后等 `reconnectBaseDelay ×（轮数 + 1）`（最多 6 倍），收到任何消息清零，连续 `maxReconnects`（8）次失败放弃并报 `onClosed`；有心跳时 max(3 个心跳, 90 秒) 没有消息当半开、替换；每次握手读一次代理路线；`close` 中止挂起的握手、最多等 2 秒关闭握手。默认连接器 `connectIoSocket`（`:74-98`）：`WebSocket.connect(customClient: webSocketClientFor(route))`，**直连时用 `dart:io` 的默认客户端**（`:56-66`，3.x 在 Android 上给直连握手传自定义客户端会挂到超时），走代理时建一个只用于握手的客户端，握手完就关。
  - 握手 User-Agent：`dart:io` 的 `WebSocket` 会在调用方给的 `user-agent` 前面加上 `Dart/<版本> (dart:io)`。`webSocketClientFor(plainUserAgent: true)` 总是建客户端并把它的 `userAgent` 清空（`:64`），这样只发调用方的头；开关 `plainDanmakuUserAgent`（编译参数 `PURE_LIVE_PLAIN_WS_UA`，默认关，`platforms.dart:245`）打开时 `danmakuHandshake()`（`:249-258`）给出这样的连接器，`buildDanmakuRegistry`（`:196-238`）把它传给 21 个平台；默认关时传 `null`，各平台用自己的默认连接器。
- 完成度（和 3.x 对照）：
  - 一致：WebSocket 的重连、换地址、半开检测、关闭时限、直连用默认客户端（移植 3.x 的 9 个用例）；Twitch 的回退链（3.x 的 `android_native_http.dart`、`twitch_web_integrity.dart`）。
  - 确认过的改动：代理不再是全局可变函数，每次握手读注入的策略（Q01.1 问题 8）；Kick 恢复（UPGRADES X-1，3.x 因 Cloudflare 下线了 Kick）；SOOP 弹幕跟随应用代理（B-6）。
  - 还缺：握手 UA 去掉前缀没有默认打开（Q03.1）；原生通道、Twitch 令牌没有真机验证（S02.4）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_net/lib/src/socket.dart`（418 行） | `SocketStatus`（`:7`）、`SocketChannel`（`:19`）、`SocketConnector`（`:38`）、`webSocketClientFor`（`:56`，直连默认 null，`plainUserAgent` 时清空 UA `:64`）、`connectIoSocket`（`:74`，可选 `pingInterval`）、`LiveSocket`（`:135`：参数 `:137-157`，`connect` `:240`，沉默检测 `:319`，放弃 `:342`，`send` `:358`，`reconnect` `:369`，`close` `:404`） |
| `apps/pure_live/lib/platform/native_http.dart`（96） | `AndroidNativeHttp`（`:16`）、`allowedHosts`（`:23`）、`allows`（`:35`）、`send`（`:38`）、`decodeNativeAnswer`（`:68`）、`open`（`:83`） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/AppChannelsPlugin.kt`（281） | 通道 `pure_live/native_http`（`:191-230`）：白名单 `:196`、8 MiB `:197`、`allowedHosts` 查询 `:209`、https 检查 `:216` |
| `apps/pure_live/lib/platform/twitch_webview_http.dart` | `HeadlessBrowser` 接口、`TwitchWebViewHttp`（只服务 Twitch GraphQL 一个端点，令牌缓存到过期前 1 分钟，一次一个页面） |
| `apps/pure_live/lib/app/platforms.dart` | `PlatformDeps.twitchFallbacks`、`kickApi`（`:102-126`）；Twitch 的回退（`:155`）、Kick 只在有原生通道时登记（`:172`）；`buildDanmakuRegistry`（`:196`，`connector` `:200`）；`plainDanmakuUserAgent`（`:245`）、`danmakuHandshake`（`:249`） |
| `apps/pure_live/lib/app/bootstrap.dart` | 建原生通道（`:160`）、Twitch 回退（`:175-178`）、`kickApi`（`:179`） |
| `packages/live_danmaku/lib/src/socket_connection.dart`（416）、`exact_websocket.dart`（656） | 弹幕连接用 `connector ?? connectIoSocket`（`:302`）；YY、SOOP 的保留大小写握手 `connectExactWebSocket`、`connectExactWebSocketViaRoute`（D01 的文件） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_net/test/socket_test.dart`（13） | 移植 3.x 的 9 个：半开换地址、有流量时保持、关闭码和原因、中止挂起的握手、重复连接合并、真实握手可放弃、关闭握手时限；另加每次握手读代理、达到最大次数放弃、本机回声服务器双向收发、直连不建客户端（`:141-146`，**没有 `plainUserAgent` 的用例**） |
| `apps/pure_live/test/platforms_test.dart`、`apps/pure_live/test/platform/twitch_webview_http_test.dart` | 原生通道的 `decodeNativeAnswer` 和白名单、弹幕登记（没有 `danmakuHandshake` 的用例）；Twitch 无界面浏览器的令牌和回退 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下：

- `core/common/web_socket_util.dart`（354 行）：`_connectIoWebSocket`（`:33-47`，`IOWebSocketChannel.connect(customClient:)`）、`_createWebSocketHttpClient`（`:49-62`，只在走代理时建客户端，注释写着只回答 DIRECT 的自定义客户端会让握手挂起），代理是全局可变函数（`:17-60`）；所以握手的 UA 一直带 `Dart/` 前缀。
- `core/common/android_native_http.dart`（Twitch GraphQL 走系统 TLS）、`android/.../NativeHttpChannel.kt:16`（3.x 的原生通道）。
- `core/utils/twitch/twitch_web_integrity.dart:9`、`:163`（`WebViewProxyScope.run`，无界面浏览器拿令牌）。
- 3.x 没有 Kick（Cloudflare 拒绝 `dart:io` 的 TLS 指纹后下线）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| **SOOP 也收到了 `danmakuHandshake()` 的连接器**：SOOP 的默认连接器是保留大小写的 `connectExactWebSocketViaRoute`（`packages/live_danmaku/lib/src/sites/soop.dart:162-166`，SOOP 的边缘只认浏览器写法的握手头，`exact_websocket.dart:9-16`），而登记时传了 `connector: connector`（`platforms.dart:214`）；现在开关默认关、`connector` 是 null，不受影响；**开关一打开，SOOP 的握手就被 `connectIoSocket` 顶掉，握手挂到超时，SOOP 弹幕连不上**。注释 `platforms.dart:248` 只写了“YY 和 FC2 有自己的握手”，漏了 SOOP。其他 20 个平台的默认连接器本来就是 `connectIoSocket`（逐个核对过），不受影响 | `apps/pure_live/lib/app/platforms.dart:214`、`:248` | Q03.1 打开开关时 SOOP 坏 | Q03.1 第一步：SOOP 登记时不再传 `connector`（D01 已在已知问题里写明） |
| 打开开关后，握手头里没有 `user-agent` 的平台会不带任何 UA：`plainUserAgent` 把 `dart:io` 的默认 UA 清空，只发调用方的头；`live_danmaku` 里哔哩哔哩、斗鱼、虎牙、Twitch、AcFun、猫耳的连接没有写 UA，要看平台给的 `*DanmakuArgs.headers` 是否带 | `socket.dart:64`；`packages/live_danmaku/lib/src/sites/` | 个别服务器可能拒绝没有 UA 的握手 | Q03.1 阶段 1 逐平台抓包确认，没有 UA 的补上浏览器 UA 或保持默认 |
| 直连握手不能用自定义客户端（3.x 在 Android 上实测会挂到超时，原因没查明） | `socket.dart:46-55` | 去掉 `Dart/` 前缀必须冒这个风险 | Q03.1 在 K90 上逐平台验证 |
| `socket_test.dart` 没有 `plainUserAgent` 的用例（Q03.1 的旧说明以为有） | `packages/live_net/test/socket_test.dart:141-146` | 清空 UA 的行为没有测试 | Q03.1 补用例（本机回环服务器检查收到的 `user-agent`） |
| 原生通道的 `open` 不是流式，最多 8 MiB | `native_http.dart:83-92`、`AppChannelsPlugin.kt:197` | 只给 Twitch GraphQL、Kick 接口用，够用 | 不做 |
| 原生通道、Twitch 令牌只在 Android；Windows 上 Kick 没有登记 | `platforms.dart:172`；`TwitchWebViewHttp.isAvailable` | Windows 看不了 Kick | X01.2（WinHTTP） |
| F-AND-09（原生通道）、F-NET-04（Twitch 令牌）没有真机验证 | [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 7 条 | — | S02.4 |

## 相关决定和规范

- D-017：WebSocket 测试用假连接器和本机回声服务器，不访问真实平台。
- D-019：Q03.1 在 K90 上逐平台测。
- [specs/UPGRADES.md](../../specs/UPGRADES.md) 附录 B-2（握手 UA，Q03.1）、B-6（SOOP 弹幕跟随代理）、X-1（Kick 和原生通道）。

## 测试和验证

- 自动测试：`cd packages/live_net && dart test test/socket_test.dart`；`cd apps/pure_live && flutter test test/platforms_test.dart test/platform/twitch_webview_http_test.dart`。缺的：`plainUserAgent` 的握手头、`danmakuHandshake` 对 SOOP 的处理（Q03.1 补）。
- 真机：CHECKLIST 第 2 节第 1 条（五大平台弹幕和断网重连）；第 5 节第 7 条（有代理时进 Twitch、Kick，S02.4）；Q03.1 的逐平台握手表。

## 路线

1. Q03.1（第三档，小）：先让 SOOP 不再传 `connector`、补测试；再在 K90 上逐平台测两种构建；按结果改默认值。
2. S02.4 看原生通道和 Twitch 令牌。
3. 以后：Windows 的 WinHTTP 通道接进同一个 `LiveHttp` 接口（X01.2）；电视版的 Kick（X03）。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Q 网络和代理](../README.md)。

- 代码：`platform/native_http.dart`、`packages/live_net`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Q03.1 | 弹幕握手的 User-Agent 去掉 Dart 前缀：在 K90 上逐平台验证后默认打开（UPGRADES B-2） | 功能 | 未开始 | — | — | [设计或说明](Q03.1-弹幕握手的UA去掉Dart前缀/README.md)、[任务书](Q03.1-弹幕握手的UA去掉Dart前缀/brief.md) |

## 还没完成的

- **Q03.1 弹幕握手的 User-Agent 去掉 Dart 前缀：在 K90 上逐平台验证后默认打开（UPGRADES B-2）**（未开始，第三档，规模 小）
  - 阶段：K90 上逐平台测两种构建 → 按结果改默认值
  - 来源：UPGRADES 附录 B-2（V03.3 核对）

<!-- docs:生成结束 -->
