# Q02 代理和镜像

请求经哪条路出去：两套用户设置的 HTTP 代理（应用代理管平台请求、弹幕、录制；播放代理管视频流）怎么变成每个请求的路线，地址输错时怎么纠正，指向局域网时的权限；以及 GitHub 上的更新文件、字体在国内连不上时用的镜像和竞速。

## 范围

- 包括：
  - `packages/live_net/lib/src/proxy.dart`：`ProxyRoute`（`DirectRoute`、`HttpProxyRoute`）、`ProxyPolicy`、`FixedProxyPolicy`、`proxyRouteFrom`、`normalizeProxyHost`、端口校验和修复、`isLocalNetworkProxyHost`。
  - 应用的两套策略：`SettingsProxyPolicy`（应用代理，`apps/pure_live/lib/app/platforms.dart:13-26`）、`PlaybackProxyPolicy`（播放代理，`:35-48`）；它们交给谁（`bootstrap.dart` 的 HTTP 客户端、原生通道、Twitch 无界面浏览器、录制、弹幕；播放的 `MediaOpener`）。
  - 镜像和竞速：`packages/live_net/lib/src/race.dart`（`raceFirst`、`raceJson`、`fastestUrl`、`GitHubMirror`）；更新检查和下载的镜像表（`apps/pure_live/lib/features/version/update_feed.dart:12`、`:273-301`、`:341-345`）、字体仓库（`app/fonts.dart:73-74`、`:343-345`）；设置 `useGitHubOriginForUpdates`。
  - 图片（封面、头像）走不走代理（现在不走，见“已知问题”）。
- 不包括（归哪里）：
  - 代理设置页的样子（两组开关、地址、端口的编辑框）→ A11（`features/settings/settings_editors.dart:395-398`）；设置的存储 → J 组。
  - 本地网络权限的申请和提示 → [Q04](../Q04-网络状态和权限/README.md)（`LocalNetworkGuard`）；它在代理指向局域网时触发。
  - mpv 的 `http-proxy` 和中继的上游怎么用播放代理 → G01（`packages/live_media/lib/src/proxy.dart:10` 的 `engineProxyUrl`）；录制怎么用应用代理 → H01。
  - 更新的流程（检查、下载、安装）→ Y02；字体下载和应用 → I01.3。
  - Android 系统的代理和 VPN：`dart:io` 只看环境变量，不读 Android 系统设置里的 HTTP 代理（3.x 一样）；VPN 模式的代理工具对所有连接透明生效，不需要应用做什么。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 设置 → 网络（A11）有“应用代理”和“播放代理”两组，各有开关、地址、端口（默认 7897，本机 Clash 的端口）。地址用中文输入法打出的“。”“．”“：”“［］”自动纠正；地址或端口没填完时不用代理（直连），不会让所有请求失败。
  - 应用代理开着时：平台列表、搜索、进房的接口、弹幕、Twitch 的原生通道和无界面浏览器、录制都走它；**封面和头像不走**。
  - 播放代理开着时：直播间、多画面、小窗的视频流（mpv 直连 CDN 时的 `http-proxy`，以及本地中继的上游请求）走它；关着时视频直连，哪怕应用代理开着（照 3.x，F-NET-02）。本地中继的地址本身不走代理。
  - 代理地址是局域网（`192.168.x.x`、`10.x`、`172.16-31.x`、`169.254.x`、`.local`/`.lan`/`.home.arpa`、IPv6 唯一本地和链路本地）时，Android 17 先申请“本地网络”权限（Q04）。
  - 检查更新、看发布历史、下载安装包、下载字体时，默认依次或竞速访问 GitHub 镜像；设置“仅从 GitHub 获取更新”（`useGitHubOriginForUpdates`）打开时只访问 GitHub 本身。
- 内部怎么工作：
  1. 两个策略都在每次请求、每次握手时读设置（`settings.get`），改设置立即生效，不用重建客户端（3.x 要重建 dio）。
  2. `proxyRouteFrom`（`proxy.dart:108-116`）：没开、地址空、端口无效、地址含 `;` 或换行 → `DirectRoute`；否则纠正地址、去掉 IPv6 的方括号 → `HttpProxyRoute`；`directive`（`:40`）给 `HttpClient.findProxy`，IPv6 加方括号。
  3. `IoLiveHttp` 按路线分连接池（Q01）；`LiveSocket` 每次握手读路线（Q03）；`engineProxyUrl` 给 mpv 一个 `http://host:port` 或空串（G01）。
  4. 镜像：`GitHubMirror.mirrors(path)`（`race.dart:128`）= raw 地址 + 14 个前缀（`rawPrefixes` `:107-122`）+ kkgithub + jsDelivr 两个节点；更新检查用 `raceJson` 取第一个 200 的 JSON（`UpdateFeed`，`update_feed.dart:341-345`，每个地址加时间戳防缓存）；安装包下载用 `downloadSources`（`:296-302`，17 个前缀，`:273-291`，能续传的在前）；字体用 `fastestUrl` 先探测最快的镜像（1 字节的范围请求，`fonts.dart:343-345`）。
- 完成度（和 3.x 对照）：
  - 一致：两套代理的分工（播放代理只管视频，录制走应用代理）；地址纠错、默认端口 7897；局域网判断；镜像表和顺序；“仅从 GitHub 获取更新”。
  - 确认过的改动：按平台选路（`ProxyPolicy.routeFor(site, url)`，现在两个策略都不分平台，留了接口）；局域网判断四段都校验（Q01.1 问题 11）；播放代理恢复成独立的一组（O03.2 c5，F-NET-02）。
  - 还缺：**图片不走应用代理**（3.x 走）；F-NET-02（播放代理）的真机验证在 S02.4。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_net/lib/src/proxy.dart`（138 行） | `ProxyRoute`（`:5`）、`DirectRoute`（`:13`）、`HttpProxyRoute`（`:28`，`directive` `:40`）、`ProxyPolicy`（`:50`）、`FixedProxyPolicy`（`:56`）、`defaultProxyPort` 7897（`:71`）、`isValidProxyPort`、`normalizeStoredProxyPort`、`parseProxyPortInput`（`:83`）、`normalizeProxyHost`（`:93`）、`proxyRouteFrom`（`:108`）、`isLocalNetworkProxyHost`（`:121`） |
| `packages/live_net/lib/src/race.dart`（140） | `raceFirst`（`:14`，全部结束即返回、赢家出来取消其余）、`raceJson`（`:54`）、`fastestUrl`（`:72`，`range: bytes=0-0`，接受 200 和 206）、`GitHubMirror`（`:92`，`rawPrefixes` `:107`、`raw`、`mirrors` `:128`） |
| `apps/pure_live/lib/app/platforms.dart` | `SettingsProxyPolicy`（`:13`，`enableAppProxy`、`appProxyHost`、`appProxyPort`）、`PlaybackProxyPolicy`（`:35`，`enableProxy`、`proxyHost`、`proxyPort`） |
| `apps/pure_live/lib/app/bootstrap.dart` | 应用代理交给 HTTP 客户端（`:151-155`）、原生通道（`:160`）、Twitch 浏览器（`:177`）、录制（`:199-210`）；播放代理交给 `MediaOpener`（`:232-236`） |
| `packages/live_media/lib/src/proxy.dart`（16） | `engineProxyUrl`（`:10`）：本地输入不走代理 |
| `apps/pure_live/lib/features/version/update_feed.dart` | `updateRepository`（`:12`，`wzgrx/pure_live`）、`downloadMirrorPrefixes`（`:273`）、`downloadSources`（`:296`）、`UpdateFeed` 的来源（`:341-345`） |
| `apps/pure_live/lib/app/fonts.dart` | `fontRepository`（`:74`，`liuchuancong/fonts`）、下载时 `fastestUrl`（`:343-345`） |
| `packages/live_store/lib/src/settings/settings.dart` | `useGitHubOriginForUpdates`（`:39`）、播放代理（`:802-808`）、应用代理（`:811-817`） |
| `apps/pure_live/lib/features/settings/settings_editors.dart:395-398` | 两组代理的编辑项（A11 管样子） |
| `packages/live_ui/lib/src/scope.dart:240-242`、`widgets/network_image.dart:46`；`apps/pure_live/lib/platform/plugins.dart:39` | 图片的磁盘缓存管理器（`LiveUiConfig.imageCacheManager`，没有设置时用 flutter_cache_manager 的默认管理器）；清缓存用 `DefaultCacheManager().emptyCache()` |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_net/test/proxy_test.dart`（8） | 移植 3.x 两个测试文件的全部用例（全角符号、端口、注入、IPv6）、`192.168.1.999` 这类非法地址、按平台选路 |
| `packages/live_net/test/race_test.dart`（6） | 第一个结果获胜并取消其余、全部失败立即结束、超时、`raceJson`、`fastestUrl` 的范围请求和 206 |
| `apps/pure_live/test/platforms_test.dart` | 播放代理和应用代理分开（O03.2）、各平台登记 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下：

- `core/common/proxy_routing.dart`（78 行）：`buildProxyDirective`、地址纠错，局域网只看前两段（`:70`）；`common/services/settings/proxy_settings_controller.dart:11-18`（两组设置）。
- `player/core/playback_proxy_policy.dart`（29）：播放代理，只看全局设置（`:11`）。
- `common/global/initialized.dart:81-104`：应用代理同时配给录制（`configureRecorderProxyRouting`）、WebSocket（`configureWebSocketProxyRouting`）和**图片缓存**（`CustomImageCacheManager.initialize(proxyDirectiveProvider:)`）。
- `plugins/cache_manager.dart:6-34`：`CustomImageCacheManager`，自己建 `HttpClient`，`findProxy` 每次读应用代理（`:19-25`，注释写着“以前图片用 flutter_cache_manager 自己的直连客户端，接口走代理而图片全部 DNS 失败”），`maxNrOfCacheObjects: 320`、`stalePeriod: 30 分钟`（`:29-30`）。
- 镜像：`common/utils/githup_mirror.dart`（`GitHubMirror.mirrors` `:48`）、`plugins/update.dart:26`（下载镜像表）、`:51`（`getMirrorUrls`，`githubOriginOnly`）、`common/utils/version_util.dart:39`。
- `common/services/local_network_access.dart`（Android 17 本地网络权限，4.x 在 Q04）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| **封面和头像不走应用代理**：`LiveUiConfig.imageCacheManager` 全应用没有人设置（只有测试设了），`CachedNetworkImage` 用 flutter_cache_manager 的默认管理器（自己的直连 `HttpClient`、200 个、30 天）；3.x 专门为此建了跟随应用代理的 `CustomImageCacheManager`。功能清点 F-NET-01 写“应用代理（平台请求、弹幕、图片、WebDAV）完成”，图片一项不对 | `packages/live_ui/lib/src/widgets/network_image.dart:46`；`packages/live_ui/lib/src/scope.dart:240-242`；`apps/pure_live/lib/platform/plugins.dart:39` | 开着应用代理看海外平台（Twitch、YouTube、Kick、SOOP 等）时卡片封面和头像加载失败或很慢；国内平台不受影响 | 需要维护者开任务（建议 Q02，第二档，小）：照 3.x 建一个 `CacheManager`（`HttpFileService` + 跟随 `SettingsProxyPolicy` 的 `HttpClient`，320 个、30 分钟），在应用的 `LiveUiConfig` 里设置；`ImageCacheTools.clearDisk` 和设置里的缓存大小（`features/settings/data_tools.dart:25-30`）一起改到新管理器；FEATURES 的 F-NET-01 改回“部分”，验证并入 S02.4 |
| 两个策略都不分平台：`routeFor(site, url)` 的 `site` 没用上，海外平台和国内平台同一条路线 | `platforms.dart:21-25`、`:43-47` | 开应用代理时国内平台也绕代理（照 3.x） | 照 3.x；“按平台代理”是新功能，先进 V01 提议 |
| 两张镜像表不同（`GitHubMirror.rawPrefixes` 14 个、`downloadMirrorPrefixes` 17 个），都是写死的第三方镜像，会失效；没有定期检查 | `race.dart:107-122`、`update_feed.dart:273-291` | 某些镜像挂了时检查更新变慢（竞速会跳过）、下载要多试几个 | 照 3.x 两张表；Z 组定期维护时检查一次（PROCESS 第 12 节“每月”） |
| 不读 Android 系统设置里的 HTTP 代理 | `dart:io` 的 `HttpClient` 默认 | 用户只在系统 Wi-Fi 设置里配了代理时应用不走 | 照 3.x；VPN 模式的工具透明生效；不做 |
| F-NET-02 播放代理：媒体请求真的走代理没有真机验证 | [CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 6 条 | — | S02.4（原 Q04.1 的验证并入） |

## 相关决定和规范

- D-018：`enableProxy`、`proxyHost`、`proxyPort`、`enableAppProxy`、`appProxyHost`、`appProxyPort`、`useGitHubOriginForUpdates` 键名和含义不变。
- D-029：Q04.1 不做，缺的播放代理由 O03.2 做完。
- D-015：`assets/version.json`、`assets/releases.json` 留在 master，镜像读的就是它们。
- [specs/ENGINEERING.md](../../../specs/ENGINEERING.md) 第 4 节：`live_net` 不依赖设置，策略由应用注入。

## 测试和验证

- 自动测试：`cd packages/live_net && dart test test/proxy_test.dart test/race_test.dart`；`cd apps/pure_live && flutter test test/platforms_test.dart`。缺的：图片走代理（功能没做）。
- 真机：CHECKLIST 第 5 节第 6 条（播放代理指向局域网代理，进海外直播间；关掉再进）、第 7 条（有代理时进 Twitch、Kick）、第 8 条（本地网络权限）——都在 S02.4、O04.1，还没看。

## 路线

1. 请维护者为“图片走应用代理”开任务（建议第二档，小）；FEATURES 的 F-NET-01 同时改准。
2. S02.4 看播放代理和有代理时的 Twitch、Kick。
3. 以后：镜像表的定期检查（Z 组）；“按平台走代理”“读系统代理”这类新行为先进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Q 网络和代理](../README.md)。

- 代码：`packages/live_net`、`app/network.dart`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
