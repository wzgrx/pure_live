# Q 网络和代理

应用和外面所有通信的底座：HTTP 客户端和它的超时、取消、重定向、压缩；请求头和 User-Agent 的策略；Brotli 解码；应用代理和播放代理怎么按平台选路；GitHub 镜像和竞速请求；走系统 TLS 的原生 HTTP 通道；弹幕用的 WebSocket（重连、心跳、代理）；断网检测和 Android 17 的本地网络权限。平台、弹幕、播放、录制、更新、字体下载都建在它上面，但它本身少有用户直接看得到的东西，所以排在各功能组之后。

## 范围

- 管什么：
  - 请求和编码（Q01）：`packages/live_net`（纯 Dart，只依赖 `meta` 和 `dart:io`）：`LiveHttp` 接口、`IoLiveHttp`（每条代理路线一个连接池、gzip 和 deflate、超时、取消）、`LiveRequest`/`LiveResponse`/`LiveStreamedResponse`、`getText`/`getJson`/`postJson`/`head`/`download`、`HttpHeaderPolicy`、`BrowserUserAgent`、`LoggingHttp`（失败只记结构）、`ThrottledHttp`（按平台限速）、`TransportFailure`/`HttpStatusFailure`、`brotliDecode`。
  - 代理和镜像（Q02）：`live_net/proxy.dart`（`ProxyRoute`、`ProxyPolicy`、地址纠错、端口校验、局域网判断）；应用里的两套代理 `SettingsProxyPolicy`（应用代理）和 `PlaybackProxyPolicy`（播放代理，`apps/pure_live/lib/app/platforms.dart:13`、`:35`）；`GitHubMirror`、`raceFirst`、`raceJson`、`fastestUrl`（`live_net/race.dart`）和更新、字体用的镜像表。
  - 原生 HTTP 和 WebSocket（Q03）：`apps/pure_live/lib/platform/native_http.dart` 的 `AndroidNativeHttp`（Twitch GraphQL 的回退、Kick 的全部接口）、`platform/twitch_webview_http.dart`（无界面浏览器拿 Twitch 完整性令牌）；`live_net/socket.dart` 的 `LiveSocket`、`connectIoSocket`、`webSocketClientFor`；弹幕握手的 User-Agent 开关（`app/platforms.dart:245-258`，Q03.1）。
  - 网络状态和权限（Q04）：`apps/pure_live/lib/app/network.dart`（`NetworkKind`、断网预检、移动数据提示）；`platform/system_access.dart`（Android 17 本地网络权限、`LocalNetworkGuard`、`ensureLocalNetworkFor`）。
- 不管什么：
  - 各平台发什么请求、带什么头、签名怎么算 → [E 直播平台](../E-直播平台/README.md)；Cookie 的存储和加密 → J、K 组（本组只定义 `CookieVault` 接口）。
  - 弹幕协议本身（帧格式、心跳内容、登录包）→ [D01](../D-弹幕/D01-平台弹幕协议/README.md)；本组只管 socket 的连接、重连、代理。
  - 播放的中继和 mpv 的 `http-proxy` → [G01](../G-播放/G01-引擎/README.md)（用本组的 `ProxyPolicy`）；录制的上游连接 → H01。
  - 代理设置页、网络错误提示文字、离线状态页的样子 → A11（设置界面）、A02.1（离线状态组件）；版本更新的流程 → Y02；字体下载 → I01.3。
  - 投屏（`packages/live_cast`，直连局域网）→ N02；设备同步（局域网）→ J05。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [Q01 请求和编码](Q01-请求和编码/README.md) | HTTP 客户端、拦截和诊断、请求头和 UA、压缩、Brotli（Q01.1、Q01.2 完成） | 所有平台（E）、更新（Y02）、字体（I01.3）、WebDAV（J04）都用它；Brotli 给哔哩哔哩、猫耳弹幕（D01） |
| [Q02 代理和镜像](Q02-代理和镜像/README.md) | 应用代理、播放代理、地址纠错、局域网代理、GitHub 镜像和竞速（还没有任务） | 播放代理交给 G01 的 `MediaOpener`；局域网代理要 Q04 的权限；镜像给 Y02、I01.3 |
| [Q03 原生HTTP和WebSocket](Q03-原生HTTP和WebSocket/README.md) | 系统 TLS 的原生通道、Twitch 无界面浏览器、WebSocket 框架、握手 UA（Q03.1 未开始） | 平台层（Twitch、Kick，E03）、弹幕（D01，21 个平台用 `connector`） |
| [Q04 网络状态和权限](Q04-网络状态和权限/README.md) | 断网检测、移动数据提示、本地网络权限（Q04.1 不做，D-029） | 离线状态的界面在 A02.1；权限的真机验证在 O04.1；功能清点余项的验证在 S02.4 |

## 现状（2026-10-07）

- 做到哪（登记表 4 个任务）：
  - 完成 2 个：Q01.1 网络（`9b70c640d`）、Q01.2 Brotli 解码（`a2b5c0610`）。网络层在 K90 冒烟（S02.2）里随各平台的请求一起工作；Brotli 在哔哩哔哩弹幕（protover 3，D01.2）、猫耳弹幕里在用。
  - 未开始 1 个：Q03.1（第三档，握手 UA 去掉 Dart 前缀）。
  - 不做 1 个：Q04.1（功能清点余项：缺的播放代理已由 O03.2 做完，验证并入 S02.4，D-029）。
  - Q02 没有任务：应用代理、播放代理、镜像都在别的任务里做完了（Q01.1、I01.1、O03.2、Y02.1）。
- 和 3.x 比：
  - 一致：20 秒超时语义、查询串逐字节保留、请求头规范化、代理地址纠错（中文输入法的“。”“：”）、默认端口 7897、失败日志只记结构、WebSocket 的重连和半开检测、竞速请求、下载先写 `.part`、两套代理（应用代理管请求和弹幕、播放代理管视频流，录制走应用代理）。
  - 修掉的 3.x 问题：Q01.1 记录的 13 个（伪造 UA 的版本号、竞速不提前结束、代理读全局单例、网络层调界面翻译、下载失败留 `.part`、`192.168.1.999` 算局域网等）。
  - 多了：纯 Dart 的 Brotli 解码器（pub 上的包装不上 Dart 3）；按平台选路；`ThrottledHttp`；回放样本测试（`ReplayHttp`）。
  - 少了（本轮读代码发现）：**封面和头像的磁盘缓存不走应用代理**——3.x 的 `CustomImageCacheManager` 给图片单独建了跟随应用代理的 `HttpClient`（`git show v3.2.11:lib/plugins/cache_manager.dart:12-33`，320 个、30 分钟），4.x 用 flutter_cache_manager 的默认管理器（直连、200 个、30 天），`LiveUiConfig.imageCacheManager` 没有人设置。功能清点 F-NET-01 写着“应用代理（平台请求、弹幕、图片、WebDAV）完成”，图片这一项不对（见 Q02 已知问题）。
- 主要的代码：

| 包或目录 | 职责 |
|---|---|
| `packages/live_net/lib/src/`（16 个文件约 1700 行，另有 Brotli 三个文件约 2540 行，其中字典 1474 行是生成的） | HTTP、代理、WebSocket、竞速和镜像、诊断、Brotli；测试 84 个（`dart test`） |
| `apps/pure_live/lib/app/platforms.dart:13-48`、`:245-258` | 两套代理策略；弹幕握手开关 |
| `apps/pure_live/lib/app/bootstrap.dart:150-160` | 建 `LoggingHttp(IoLiveHttp(proxy:))`、原生通道、交给平台 |
| `apps/pure_live/lib/platform/native_http.dart`、`twitch_webview_http.dart`；Android `AppChannelsPlugin.kt:191-230` 的 `pure_live/native_http` | 系统 TLS 通道、无界面浏览器 |
| `apps/pure_live/lib/app/network.dart`、`platform/system_access.dart` | 网络状态、本地网络权限 |
| `apps/pure_live/lib/features/version/update_feed.dart:271-301`、`app/fonts.dart:73-74` | 下载镜像表、GitHub 镜像的用法 |

## 当前重点和顺序

1. **第二档（建议，需要维护者开任务）：图片走应用代理**。开着应用代理看海外平台（Twitch、YouTube、Kick 等）时，卡片封面和头像直连失败或很慢；改法是给 `LiveUiConfig.imageCacheManager` 设一个跟随 `SettingsProxyPolicy` 的 `CacheManager`（照 3.x 的 `CustomImageCacheManager`），清缓存的入口一起改。
2. **第三档：Q03.1**。打开开关前先让 SOOP 不再传 `connector`（SOOP 有自己保留大小写的握手，开关会把它顶掉，SOOP 弹幕就连不上）；然后在 K90 上逐平台测两种构建。
3. **验证**：F-NET-02 播放代理、F-NET-04 Twitch 完整性令牌、F-AND-09 原生通道在 S02.4（CHECKLIST 第 5 节第 6、7 条）；F-AND-04 本地网络权限在 O04.1。

## 风险和注意

- **TLS 指纹和证书**：Cloudflare 拒绝 `dart:io` 的 TLS 指纹（Kick，UPGRADES X-1），所以 Kick 全部接口走原生通道；有的代理在 CONNECT 之后会断开 `dart:io` 的 TLS（Twitch GraphQL）。原生通道只放行白名单主机（`AndroidNativeHttp.allowedHosts`，和 Kotlin `AppChannelsPlugin.kt:196` 的 `ALLOWED_HOSTS` 两处要一起改，上限 `:197`），单次最多 8 MiB，不能变成通用请求工具。
- **Android 的 WebSocket 握手**：3.x 实测 Android 上给直连握手传自定义 `HttpClient` 会挂到超时（原因没查明），所以直连默认用 `dart:io` 的默认客户端；Q03.1 要在真机上逐平台验证再改。
- **代理的输入**：用户在手机上输入代理地址，中文输入法会打出全角符号；地址半截时不能让所有请求失败（`proxyRouteFrom` 不完整就直连）；主机名里的 `;` 和换行会注入第二条指令，必须拒绝。
- **Android 17 本地网络权限**：代理指向局域网（PC 上的 Clash）时要先申请 `ACCESS_LOCAL_NETWORK`，拒绝后所有请求都会失败；回环地址不需要。
- **隐私**：失败日志只记结构（来源、方法、状态码、路径段数、参数名），不记查询值、Cookie、请求体；样本要脱敏（门禁查样本隐私）。
- **测试**：网络测试在本机回环上起真实服务，不访问真实平台；定时器至少 1 秒（D-017）。
- **设置**：`enableProxy`/`proxyHost`/`proxyPort`（播放代理）、`enableAppProxy`/`appProxyHost`/`appProxyPort`（应用代理）、`useGitHubOriginForUpdates` 是 3.x 的键，键名和含义不变（D-018）。

## 相关

- 规范：[specs/ENGINEERING.md](../specs/ENGINEERING.md)（第 4 节：`live_net` 只依赖 `meta`、`dart:io`，`tools/gate/check_deps.py` 检查；样本隐私）；[specs/UPGRADES.md](../specs/UPGRADES.md) 附录 B-2（握手 UA）、B-3（哔哩哔哩 protover 3）、X-1（Kick、原生通道）。
- 决定：D-017、D-018、D-019、D-029（Q04.1 不做）。
- 其他组：D01（弹幕连接）、E 组（平台请求、Twitch、Kick）、G01（播放代理、中继）、H01（录制的上游）、I01.3（字体镜像）、J04（WebDAV）、O04.1（本地网络权限真机）、S02.4（代理、原生通道的真机验证）、Y02（更新镜像）、A02.1（离线状态组件）、A11（代理设置页）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`████████████████░░░░` 82%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [Q01 请求和编码](Q01-请求和编码/README.md) | HTTP 客户端、拦截器、请求头策略、压缩（含 Brotli）。 | `████████████████████` 100% | 2 / 2 |
| [Q02 代理和镜像](Q02-代理和镜像/README.md) | 系统代理、自定义代理、局域网代理、GitHub 镜像。 | `██████████████████░░` 90% | 0 / 1 |
| [Q03 原生HTTP和WebSocket](Q03-原生HTTP和WebSocket/README.md) | 系统 TLS 的原生 HTTP（Twitch、Kick）、WebSocket。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |
| [Q04 网络状态和权限](Q04-网络状态和权限/README.md) | 离线检测、本地网络权限。 | — | 0 / 0 |

## 还没完成的（2）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [Q02.1](Q02-代理和镜像/Q02.1-封面和头像走应用代理/README.md) 封面和头像走应用代理（3.x 的 CustomImageCacheManager） | 待真机 | 第二档 | 1/1 |
| [Q03.1](Q03-原生HTTP和WebSocket/Q03.1-弹幕握手的UA去掉Dart前缀/README.md) 弹幕握手的 User-Agent 去掉 Dart 前缀：在 K90 上逐平台验证后默认打开（UPGRADES B-2） | 开发中 | 第三档 | 0/2：下一阶段“K90 上逐平台测两种构建” |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
