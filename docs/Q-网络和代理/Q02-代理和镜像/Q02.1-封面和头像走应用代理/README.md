# Q02.1 封面和头像走应用代理（3.x 的 CustomImageCacheManager）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 G、Q、R 组核对：[Q02 说明](../README.md)“已知问题”——封面和头像不走应用代理（`LiveUiConfig.imageCacheManager` 没人设置），3.x 走（`CustomImageCacheManager`）；功能清点 F-NET-01（应用代理：平台请求、弹幕、图片、WebDAV）写“完成”不对，随本任务改“部分”
- 相关：应用代理的策略 `SettingsProxyPolicy`（[Q01.1](../../Q01-请求和编码/Q01.1-网络/README.md)、`apps/pure_live/lib/app/platforms.dart:13-26`）；局域网代理的权限 [Q04](../../Q04-网络状态和权限/README.md)；图片组件 `LiveNetworkImage`（`packages/live_ui`，A01）；清空缓存（设置 → 数据，A11.5）；决定 D-001、D-018
- 任务书：[brief.md](brief.md)

## 目标

开着“应用代理”时，海外平台（Twitch、YouTube、Kick、SOOP……）的列表能刷出来、直播间能进，但卡片上的封面和头像全是灰的占位——因为图片是另一个 HTTP 客户端直连下载的，不走代理。3.x 专门修过这个（`CustomImageCacheManager` 的注释：“Covers and avatars previously used flutter_cache_manager's separate DIRECT client, so API cards could load through the app proxy while all images still failed DNS independently”）。

做完以后：封面、头像、分区图、飞行弹幕和聊天里的表情图都按“应用代理”的设置走（开着走代理，关着直连），改了设置立即对新的图片请求生效；清空图片缓存、显示缓存大小照旧正确。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 图片的下载客户端 | `lib/plugins/cache_manager.dart:6-34` `CustomImageCacheManager`：自己的 `HttpClient`，`findProxy` 每个新连接读应用代理（`:19-25`），缓存键 `pureLiveImagesV2`、30 分钟过期、最多 320 个（`:27-31`）；`lib/common/global/initialized.dart:111-119` 用 `enableAppProxy`、`appProxyHost`、`appProxyPort` 初始化 | `packages/live_ui/lib/src/widgets/network_image.dart:42-46` `CachedNetworkImage(cacheManager: config.imageCacheManager)`；`LiveUiConfig.imageCacheManager`（`packages/live_ui/lib/src/scope.dart:224`、`:242`）**没人设置**（`apps/pure_live/lib/app/app.dart:179-185` 只给了 `imageHeaders`、`imageCacheEpoch`），所以用 flutter_cache_manager 的默认管理器，直连 | 应用给一个自己的缓存管理器，下载走应用代理 |
| 代理的读法 | `buildProxyDirective(enabled:, host:, port:)` | 已有：`SettingsProxyPolicy.routeFor(site, url)`（`platforms.dart:21-25`）→ `ProxyRoute.directive`（`packages/live_net/lib/src/proxy.dart:9`、`:18`、`:40`，`PROXY host:port` / `DIRECT`）；HTTP 客户端就是这样用的（`packages/live_net/lib/src/io_http.dart:38`） | 图片客户端 `findProxy = (url) => policy.routeFor('image', url).directive`，每个新连接都读 |
| 飞行弹幕的表情图 | 3.x 用打包的表情图集（不联网） | `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:890-893`：没有打包的表情用 `NetworkImage(emote.url)`（Flutter 自带的客户端，直连）；聊天列表的表情 `packages/live_ui/lib/src/widgets/emote_text.dart:122` 用 `LiveNetworkImage`（会跟着改好） | 弹幕层的网络表情也走同一个管理器（`CachedNetworkImageProvider(url, cacheManager: …)`） |
| 清缓存和大小 | `CustomImageCacheManager.remove` 等 | `apps/pure_live/lib/platform/plugins.dart:39` `ImageCacheTools.clearDisk = () => DefaultCacheManager().emptyCache()`；大小读固定目录 `libCachedImageData`（`apps/pure_live/lib/features/settings/data_tools.dart:29-32`） | 清和量都改成新管理器的；旧的默认缓存目录升级后清一次 |
| 其他直连的图片 | — | 版本历史页 `features/version/release_history_view.dart:378` `Image.network`（GitHub 的图，走镜像规则另说） | 不在本任务（见“留下的问题”） |

## 方案

- c1 新文件 `apps/pure_live/lib/app/image_cache.dart`：`appImageCacheManager(SettingsStore settings)` 建一个 `CacheManager(Config('pureLiveImages', stalePeriod: 30 分钟, maxNrOfCacheObjects: 320, fileService: HttpFileService(httpClient: IOClient(client))))`，`client.findProxy = (url) => SettingsProxyPolicy(settings).routeFor('image', url).directive`、`idleTimeout` 30 秒（照 3.x）；单例，应用退出时不用关。
- c2 `app.dart:179-185` 的 `LiveUiConfig(imageCacheManager: …)` 传它；`plugins.dart:39` 的 `clearDisk` 改清它；`data_tools.dart:31-32` 的 `folder` 改成它的目录（新键名）。
- c3 旧缓存：第一次用新管理器时（meta `images.legacyCacheCleared` 没有），`DefaultCacheManager().emptyCache()` 一次，免得旧目录占空间、不再被清。
- c4 弹幕层：`danmaku_overlay.dart:892` 的 `NetworkImage(emote.url)` 换成用同一个管理器的 provider（`live_ui` 已依赖 `cached_network_image`；`shared/danmaku` 从 `LiveUiScope` 或一个全局的入口拿管理器）。
- 不改：图片请求头（`networkImageHeaders`）；内存缓存预算（`configureDecodedImageCache`）；播放代理（视频流）；设置键名（D-018）。

## 验证

- 自动测试：`apps/pure_live/test/` 加：代理开时图片客户端的 `findProxy` 返回 `PROXY 127.0.0.1:7897`，关时 `DIRECT`，改设置后下一次读到新值；`LiveUiConfig.imageCacheManager` 不为空；清缓存调的是新管理器；`image_cache_budget_test.dart` 照样通过。
- 真机：开着代理看 Twitch 推荐的封面（任务书“真机验证”）；做之前“未开始”。功能清点 F-NET-01 完成后改回“完成”（或“没验证”，看真机）。

## 留下的问题

- 版本历史页的 GitHub 图片（`release_history_view.dart:378`）走不走代理、要不要镜像，归 Y02（更新通道）一起定。
- 图片按平台分路（例如国内平台的图直连、海外的走代理）：`ProxyPolicy.routeFor` 留了接口，现在两套策略都不分平台（Q02 说明），不在本任务。
