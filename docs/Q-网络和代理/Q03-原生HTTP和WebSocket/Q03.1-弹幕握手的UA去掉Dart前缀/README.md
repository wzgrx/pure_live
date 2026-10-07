# Q03.1 弹幕握手的 User-Agent 去掉 Dart 前缀：在 K90 上逐平台验证后默认打开（UPGRADES B-2）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：已批准升级附录 [B-2](../../../specs/UPGRADES.md)（“弹幕握手的 User-Agent 不再带 `Dart/3.13 (dart:io)` 前缀”，用户 2026-09-30 批准）。I01.1 只留了开关（默认关），余下“Android 真机逐平台验证后改为默认开”原来没有任务；V03.3 核对时（2026-10-03）开了本任务。
- 相关：I01.1（[记录](../../../I-浏览和发现/I01-首页外壳和全局/I01.1-应用骨架/record.md) 的 B-2 一行，加了开关）；Q01.1（3.x 实测 Android 直连时自定义客户端会让握手挂到超时，[记录](../../Q01-请求和编码/Q01.1-网络/record.md)“保留的 v3 行为”）；D01 各平台弹幕任务，特别是 D01.8 SOOP（[D01 已知问题](../../../D-弹幕/D01-平台弹幕协议/README.md#已知问题和限制)）；任务书 [brief.md](brief.md)

## 目标

各平台弹幕的 WebSocket 握手只带应用自己设的 User-Agent（和网页一致），不再被 `dart:io` 加上 `Dart/<版本> (dart:io)` 前缀。用户看不出变化；好处是请求更像浏览器，以后平台按 UA 拦截时不受影响。前提是：（1）SOOP 不被开关误伤；（2）Android 真机上逐平台确认改了以后握手不会挂起、不会因为没有 UA 被拒。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 握手的 UA | `dart:io` 默认，带 `Dart/` 前缀：各平台经 `lib/core/common/web_socket_util.dart:33-47` 的 `_connectIoWebSocket`（`IOWebSocketChannel.connect`），`:49-62` 的 `_createWebSocketHttpClient` 直连时不建自定义客户端 | 同 3.x：`packages/live_net/lib/src/socket.dart:56-66` 的 `webSocketClientFor`，直连时返回 null（用默认客户端）；`plainUserAgent` 为真时新建 `HttpClient` 并把 `userAgent` 清空（`:64`）；`connectIoSocket(plainUserAgent:)`（`:74-98`） | 默认不带前缀 |
| 开关 | 无 | `apps/pure_live/lib/app/platforms.dart:245` 的 `plainDanmakuUserAgent = bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA')`，`:249-258` 的 `danmakuHandshake()` 只在开时给连接器；`:200` 起的弹幕登记把它传给 21 个平台（哔哩哔哩、斗鱼、虎牙、抖音、Twitch、SOOP、AcFun、Picarto、TwitCasting、猫耳 FM、克拉克拉、SHOWROOM、CHZZK、Kick、BIGO、PandaTV、京东、酷狗、六间房、LOOK、17LIVE）；YY、FC2、快手、niconico、YouTube、Steam、百度不走它 | 验证通过的平台默认开 |
| SOOP | 3.x 用保留大小写的握手（`connectCaseSensitiveWebSocket`） | SOOP 自己的默认连接器是 `connectExactWebSocketViaRoute`（`packages/live_danmaku/lib/src/sites/soop.dart:162-166`），但登记时传了 `connector: connector`（`platforms.dart:214`）；开关打开时会被 `connectIoSocket` 顶掉，SOOP 的边缘不回答小写的握手头，握手挂到超时 | SOOP 不再收这个连接器 |
| 其他 20 个平台的默认连接器 | — | 都是 `connectIoSocket`（`socket_connection.dart:302` 的 `connector ?? connectIoSocket`，以及 Picarto、TwitCasting、PandaTV、LOOK、酷狗、17LIVE、BIGO 各自 `connector ?? connectIoSocket`），开关只改 UA | 不受连接器替换影响 |
| 没有 UA 的握手 | — | `plainUserAgent` 清空 `dart:io` 的 UA 后只发调用方的头；`live_danmaku` 里哔哩哔哩、斗鱼、虎牙、Twitch、AcFun、猫耳的连接没有写 UA（要看平台给的 `*DanmakuArgs.headers`） | 逐平台确认握手里有浏览器 UA；没有的补上 |
| 风险来源 | v3 给直连握手传自定义 `HttpClient`，Android 上握手挂到超时（原因没查明） | `socket.dart:46-55` 的注释写着同一个风险 | 每个平台在 K90 上直连和走代理各连几次 |
| 测试 | — | `packages/live_net/test/socket_test.dart:141-146` 只测“直连不建客户端、代理建客户端”，**没有 `plainUserAgent` 的用例**；`apps/pure_live/test/platforms_test.dart` 没有 `danmakuHandshake` 的用例 | 补用例 |

## 方案

- c1 SOOP 先改：`platforms.dart:214` 改成 `SoopDanmakuConnection(proxy: proxy)`（不传 `connector`），`:248` 的注释写全“YY、FC2、SOOP 有自己的握手”；加测试断言开关开时 SOOP 拿不到通用连接器。这一步不改行为（开关默认关），可以先合并。
- c2 补 `plainUserAgent` 的测试：本机回环起一个 WebSocket 服务，记下收到的 `user-agent`；默认时以 `Dart/` 开头，`plainUserAgent: true` 时等于调用方给的值，调用方没给时没有这个头。
- c3 用 `--dart-define=PURE_LIVE_PLAIN_WS_UA=true` 构建测试包，在 K90 上逐个平台进直播间，记握手时间（进房到弹幕状态“已连接”）和有没有超时；海外平台开着应用代理测。同一批平台用默认构建再测一次作对照。逐平台抓一次握手（电脑代理上看请求头），确认 UA 是浏览器的、不是空的。
- c4 按结果改默认值：全部通过 → `bool.fromEnvironment('PURE_LIVE_PLAIN_WS_UA', defaultValue: true)`（保留编译参数可以关）；有平台挂起或被拒 → `danmakuHandshake` 改成按平台给（例外平台拿 null），例外写进记录并查原因；握手里没有 UA 的平台在它的 `*DanmakuArgs.headers`（E 组的平台适配器）或连接里补上浏览器 UA——补 UA 属于平台代码，写进报告由维护者决定开在 E 组还是放进本任务。
- c5 更新 UPGRADES 附录 B-2 的状态。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 握手到“已连接”的时间（每个平台） | 默认构建：待测 | 打开开关后中位数不比默认构建慢 500 毫秒以上，没有超时 | 进房到弹幕状态行变“已连接”：`adb logcat` 里弹幕连接的日志时间差，每个平台 3 次 |
| 握手的 User-Agent | `Dart/3.x (dart:io) Mozilla/…` | 只有 `Mozilla/…`（平台给的浏览器 UA） | 电脑上的代理工具看握手请求头（海外平台本来就走代理；国内平台测时临时开应用代理） |

## 验证

- 自动测试：`packages/live_net/test/socket_test.dart` 新用例（c2）；`apps/pure_live/test/platforms_test.dart` 新用例：开关开时 SOOP、YY、FC2 不拿通用连接器，其余 20 个拿到（c1）；改默认值后“默认构建下 `danmakuHandshake()` 不为 null”（或例外平台为 null）。
- 真机：待真机（任务书的真机步骤）；结果表写进 `record.md`。

## 留下的问题

- YY、FC2、SOOP 有自己的握手，不在本任务里改（YY、SOOP 的握手本来就只发调用方的头）。
- 3.x 遇到的“自定义客户端直连握手挂起”的原因还是没查明；如果 K90 上复现，记下网络环境（IPv4/IPv6、Wi-Fi/移动数据），本任务只按平台关掉，不深挖。
