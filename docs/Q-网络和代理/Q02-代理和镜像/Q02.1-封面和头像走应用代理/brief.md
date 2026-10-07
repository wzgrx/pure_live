# Q02.1 封面和头像走应用代理（3.x 的 CustomImageCacheManager）：任务书

## 背景

- 来源：2026-10-07 docs v2 G、Q、R 组核对（[Q02 说明](../README.md)“已知问题”）：`LiveUiConfig.imageCacheManager` 没人设置，图片用 flutter_cache_manager 的默认客户端直连；3.x 的 `CustomImageCacheManager` 让图片走应用代理。功能清点 F-NET-01 写“完成”不对，已改“部分”。维护者登记为本任务。
- 现象：设置 → 网络 → 应用代理开（指向能翻墙的代理），推荐 → Twitch：列表出来了，卡片封面和主播头像都是占位图；直播间里主播头像同样。关掉代理、开系统级 VPN 时正常（VPN 对所有连接透明）。
- 为什么现在做：第二档；海外平台的用户每天都会看到。规模小（约 1.5 小时）。
- 已经做过的：应用代理的策略和 HTTP 客户端（Q01.1）；图片组件和缓存键（A01、`imageCacheEpoch`）；清空缓存（A11.5）。

## 目标和验收

1. 应用代理开：封面、头像、分区图、聊天和飞行弹幕里的网络表情都经代理下载（代理日志里能看到这些主机）；关：直连。
2. 改代理设置后，新的图片请求马上按新设置走（不用重启）。
3. 设置 → 数据里“图片缓存”的大小和“清空”都对应新的缓存；升级后旧的默认缓存目录清一次。
4. 缓存规则照 3.x：30 分钟过期、最多 320 个文件。
5. 内存里的解码缓存预算、图片请求头、`imageCacheEpoch` 的换键行为不变；测试和门禁通过；没有新设置、没有新文字。

## 现状（读代码得出，写文件:行）

- 图片组件：`packages/live_ui/lib/src/widgets/network_image.dart:40-57` `LiveNetworkImage.build`：`CachedNetworkImage(cacheKey: config.imageCacheKey(url), httpHeaders: config.imageHeaders?.call(url), cacheManager: config.imageCacheManager, …)`（`:42-46`）。配置：`packages/live_ui/lib/src/scope.dart:218-285` `LiveUiConfig`（`imageCacheManager` `:224`、`:242`；`imageCacheEpoch` `:226`、`:249`；`imageCacheKey` `:253`）。
- 应用：`apps/pure_live/lib/app/app.dart:179-185` 建 `LiveUiConfig`，没有 `imageCacheManager`。
- 代理：`apps/pure_live/lib/app/platforms.dart:13-26` `SettingsProxyPolicy`（读 `enableAppProxy`、`appProxyHost`、`appProxyPort`，每次都读）；`packages/live_net/lib/src/proxy.dart`：`ProxyRoute.directive`（`:9`），直连 `'DIRECT'`（`:18`），代理 `'PROXY host:port'`（`:40`，IPv6 加方括号），`:91` 起的注释说明 Android 上 `findProxy` 的坑；HTTP 客户端的用法 `packages/live_net/lib/src/io_http.dart:38`、WebSocket `socket.dart:62`。
- 清缓存：`apps/pure_live/lib/platform/plugins.dart:39` `ImageCacheTools.clearDisk = () => DefaultCacheManager().emptyCache()`；`apps/pure_live/lib/features/settings/data_tools.dart:29-45` `ImageCacheTools.folder`（固定 `<临时目录>/libCachedImageData`）、`size()`。
- 别的网络图片：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:890-893` `_load`（没有打包的表情用 `NetworkImage(emote.url)`）；`packages/live_ui/lib/src/widgets/emote_text.dart:122`（`LiveNetworkImage`，跟着改好）；`features/version/release_history_view.dart:378`（`Image.network`，不在本任务）。
- 测试：`apps/pure_live/test/image_cache_budget_test.dart`；`apps/pure_live/test/platforms_test.dart`（代理策略）；`packages/live_ui/test/`（图片组件）。

## 3.x 基线

- `git show v3.2.11:lib/plugins/cache_manager.dart`：`CustomImageCacheManager`（`:6`）：`key = 'pureLiveImagesV2'`（`:7`）；`_createManager`（`:12-34`）：`HttpClient`、`idleTimeout` 30 秒、`findProxy` 每个连接读 `_proxyDirectiveProvider`（`:19-25`，读不到就 `DIRECT`）、`Config(stalePeriod: 30 分钟, maxNrOfCacheObjects: 320, fileService: HttpFileService(httpClient: IOClient(client)))`（`:26-33`）；`initialize`（`:39-42`）；`remove`（`:44` 起，删文件重试 5 次）。
- `lib/common/global/initialized.dart:111-119`：用应用代理的三个设置初始化。
- 要保留：走应用代理（不是播放代理）；过期和数量上限；设置键名（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 4 节：网络“按平台分配代理”）。
3. 本文件夹的 `README.md`；`docs/Q-网络和代理/Q02-代理和镜像/README.md`；`docs/Q-网络和代理/Q01-请求和编码/Q01.1-网络/README.md`。

## 范围

- 可以改：新文件 `apps/pure_live/lib/app/image_cache.dart`；`apps/pure_live/lib/app/app.dart`（只传管理器）；`apps/pure_live/lib/platform/plugins.dart`（`clearDisk`）；`apps/pure_live/lib/features/settings/data_tools.dart`（`folder`）；`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（只改网络表情的 provider）；（需要时）`apps/pure_live/pubspec.yaml` 直接依赖 `http`（`IOClient`，已是间接依赖）；测试；`docs/inventory/FEATURES.md` 的 F-NET-01（完成后改状态）；本文件夹。
- 不能改：`live_ui` 的接口（`imageCacheManager` 已经有）；代理策略和设置；播放代理；内存解码缓存预算；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 管理器（照 3.x 的配置，`findProxy` 读 `SettingsProxyPolicy`）；c2 接到 `LiveUiConfig`、`clearDisk`、`folder`；c3 旧缓存清一次；c4 弹幕层的网络表情用同一个管理器 | 见“可以改” | 验收 1～5 |

只有一个阶段（规模小）。

## 测试

- 改之前会失败：新文件 `apps/pure_live/test/image_cache_test.dart`：
  - “images follow the app proxy (Q02.1)”：`LiveStore.memory` 设 `enableAppProxy = true`、`127.0.0.1:7897`，取管理器里 `HttpClient` 的 `findProxy`（把客户端的建法抽成可测的函数 `imageHttpClient(settings)`）→ `PROXY 127.0.0.1:7897`；关掉 → `DIRECT`；地址没填完 → `DIRECT`（`proxyRouteFrom` 的规则）。
  - “the app gives live_ui its image cache”：pump `PureLiveApp`（照 `desktop_window_test.dart:692` 的写法），`LiveUiScope.of(context).imageCacheManager` 不为空。
  - “clearing the image cache clears the app's manager; the old default cache once”：`clearDisk` 调新管理器；meta 标记后不再清旧的。
- 弹幕层：`apps/pure_live/test/shared/danmaku_overlay_test.dart` 的网络表情用例（如果有）照样通过；不发真实请求（测试里给管理器换成假的 `FileService`）。
- 测试里的定时器至少 1 秒（D-017）；不访问真实网络。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 用户开着电脑上的代理（Clash，局域网地址由用户给）；K90 设置 → 网络 → 应用代理开，填地址和端口；推荐 → Twitch | 列表封面和头像都显示（之前是占位） |
| 2. 进一个 Twitch 直播间 | 主播头像显示；聊天里的 Twitch 表情是图片 |
| 3. 关掉应用代理，回推荐下拉刷新 | 国内平台照常；Twitch 的图片按直连的结果（多半失败），说明设置立即生效 |
| 4. 设置 → 数据 → 图片缓存：看大小，点清空 | 大小不是 0（有图后）；清空后变小 |

## 风险和注意

- Android 上 `findProxy` 返回的字符串不能带多余的东西（`proxy.dart:91` 起的注释：整串会被当成 DNS 名解析）；直接用 `ProxyRoute.directive`。
- 局域网代理在 Android 17 要“本地网络”权限（Q04 的 `LocalNetworkGuard`），图片请求和平台请求一样受它管，不用另外处理。
- 新缓存键会让升级后的第一次全部重新下载图片（一次性流量）；可以接受，写进记录。
- `CachedNetworkImageProvider` 用在弹幕层时注意 `ResizeImage` 包装（`danmaku_overlay.dart:893`）不变。
- 可能冲突的文件：`app.dart`（A 组界面任务改主题配置）；`danmaku_overlay.dart`（D03.3 只加测试，不冲突）；`data_tools.dart`（A11.5）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/Q02.1` 或本机工作区；提交信息以 `[Q02.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；管理器的配置；测试数量（改之前失败几个）；改了哪些文件；加没加直接依赖；FEATURES F-NET-01 的新状态；要在真机上看的；可能冲突的文件。
