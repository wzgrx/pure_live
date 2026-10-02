# Q03.1 弹幕握手的 User-Agent 去掉 Dart 前缀

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：已批准升级附录 [B-2](../../../specs/UPGRADES.md)（“弹幕握手的 User-Agent 不再带 `Dart/3.13 (dart:io)` 前缀”）。I01.1 只留了开关（默认关），余下“Android 真机逐平台验证后改为默认开”原来写“K90（未列入 S02.3 条目）”，没有任务；V03.3 核对时开了本任务。
- 相关：I01.1（[记录](../../../I-浏览和发现/I01-首页外壳和全局/I01.1-应用骨架/record.md) 的 B-2 一行）；Q01.1（v3 实测 Android 直连时自定义客户端会让握手挂到超时，[记录](../../Q01-请求和编码/Q01.1-网络/record.md)）；D01 各平台弹幕任务

## 目标

各平台的弹幕 WebSocket 握手只带应用自己设的 User-Agent（和网页一致），不再被 dart:io 加上 `Dart/<版本> (dart:io)` 前缀。用户看不出变化；好处是请求更像浏览器，以后平台按 UA 拦截时不受影响。前提是 Android 真机上逐平台确认改了以后握手不会挂起。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 握手的 UA | dart:io 默认，带 `Dart/` 前缀：各平台经 `core/common/web_socket_util.dart:39-46` 的 `IOWebSocketChannel.connect`，`:50-60` 的 `_createWebSocketHttpClient` 直连时不建自定义客户端 | 同 3.x：`packages/live_net/lib/src/socket.dart:56-66` 的 `webSocketClientFor`，直连时返回 null（用默认客户端）；`plainUserAgent` 为真时新建 `HttpClient` 并把它的 `userAgent` 清空（`:64`）；`connectIoSocket(plainUserAgent:)`（`:75-90`） | 默认不带前缀 |
| 开关 | 无 | `apps/pure_live/lib/app/platforms.dart:245` 的 `plainDanmakuUserAgent = bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA')`，`:249-258` 的 `danmakuHandshake()` 只在开时给连接器；`:200` 起的弹幕登记把它传给 21 个平台（哔哩哔哩、斗鱼、虎牙、抖音、Twitch、SOOP、AcFun、Picarto、TwitCasting、猫耳 FM、克拉克拉、SHOWROOM、CHZZK、Kick、BIGO、PandaTV、京东、酷狗、六间房、LOOK、17LIVE），YY、FC2、快手、niconico、YouTube、Steam、百度不走它 | 21 个平台在 K90 上验证通过后默认开 |
| 风险来源 | v3 曾给直连握手传自定义 `HttpClient`，Android 上握手挂到超时（原因没查明） | `socket.dart:45-50` 的注释写着同一个风险 | 每个平台在 K90 上直连和走代理各连一次 |

## 方案

- c1 用 `--dart-define=PURE_LIVE_PLAIN_WS_UA=true` 构建测试包，在 K90 上直连逐个平台进直播间，记握手时间（进房到弹幕状态“已连接”）和有没有超时；海外平台在开着应用代理时测。
- c2 同一批平台用默认构建再测一次作对照。
- c3 全部通过：把 `plainDanmakuUserAgent` 的默认值改成 `true`（`bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA', defaultValue: true)`），保留编译参数可以关；有平台挂起：只给通过的平台打开（`danmakuHandshake` 按平台给），挂起的写进记录并查原因。
- c4 更新升级表 B-2 的状态。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 握手到“已连接”的时间 | 默认构建：待测 | 打开后不慢于默认构建 500 毫秒以上，没有超时 | 进房到弹幕状态行变“已连接”，`adb logcat` 里弹幕连接的日志时间差，每个平台 3 次 |

## 验证

- 自动测试：`packages/live_net/test/` 已有 `webSocketClientFor` 的用例（清空 `userAgent`）；改默认值后在 `apps/pure_live/test/platforms_test.dart` 加一条“默认构建下 `danmakuHandshake()` 不为 null”。
- 真机：待真机（brief 的真机步骤）。

## 留下的问题

- YY、FC2 有自己的握手，不在本任务里（`platforms.dart:250` 的注释）。
