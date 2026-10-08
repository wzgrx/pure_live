# Q03.1 弹幕握手的 User-Agent 去掉 Dart 前缀：记录

## 2026-10-08 阶段 1 的代码部分（c1、c2）

### c1 SOOP 不再拿通用连接器

- 根因：`apps/pure_live/lib/app/platforms.dart` 的 `buildDanmakuRegistry` 把 `danmakuHandshake()` 的结果传给 21 个平台，其中有 SOOP（原 `:214`）。SOOP 自己的默认连接器是保留大小写的握手（`packages/live_danmaku/lib/src/sites/soop.dart:162-166` 的 `connectExactWebSocketViaRoute`），开关一打开就被 `connectIoSocket` 顶掉，SOOP 的边缘不回答 dart:io 小写的握手头。
- 改法：新常量 `genericDanmakuHandshakeSites`（20 个走 dart:io 握手的平台），登记表里每个平台用 `connector(SiteIds.x)` 取：在集合里才给通用连接器。SOOP 不再传 `connector`；注释写全了不在集合里的原因：SOOP、YY 自己的保留大小写握手，FC2 自己的 socket，快手、niconico、YouTube、Steam、百度没有我们要握手的 WebSocket。
- 默认构建行为不变（开关默认关，`danmakuHandshake()` 是 null）。

### c2 `plainUserAgent` 的测试

- `packages/live_net/test/socket_test.dart`“the handshake User-Agent (UPGRADES B-2, Q03.1)”：本机回环 `HttpServer` 升级 WebSocket，记下每次握手的 `user-agent`。
  - 默认握手：调用方给 `Mozilla/5.0 test`，服务器收到的以 `Dart/` 开头。
  - `plainUserAgent: true`：收到的正好是 `Mozilla/5.0 test`；调用方不给时没有 `user-agent`。
- `apps/pure_live/test/platforms_test.dart`“the plain danmaku handshake”：开关默认关、打开有连接器；集合 20 个，没有 SOOP、YY、FC2，也没有快手、niconico、YouTube、Steam、百度。

### 没做的（要真机）

- c3：两种构建（默认、`--dart-define=PURE_LIVE_PLAIN_WS_UA=true`）在 K90 上逐平台测握手时间和 UA（brief“真机验证”）；海外平台走代理（电脑的 Clash 192.168.1.238:7897 手机能用，见 E03.17 的复查）。
- 阶段 2（按结果改默认值、UPGRADES B-2 的状态）等 c3 的数字。

## 真机上要看的

照 [brief.md](brief.md)“真机验证”：两种构建 × 21 个平台（海外只测代理）× 直连 / 代理，每格握手时间（3 次中位数）或“超时”，打开开关的构建抓握手 UA。
