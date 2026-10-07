# Q02.1 封面和头像走应用代理：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，`97050a8e4`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `apps/pure_live/lib/app/image_cache.dart`：`imageHttpClient`（`idleTimeout` 30 秒，`findProxy` 每个新连接读 `routeFor('image', url).directive`）、`imageFileService`、`appImageCacheConfig`（键 `pureLiveImages`，30 分钟，320 个）、`AppImageCache.install`（单例）。代理策略用的是 `AppServices.proxy`，就是 `SettingsProxyPolicy`（`bootstrap.dart:151`） |
| c2 | 做了 | `app.dart` 把 `AppImageCache.manager` 传给 `LiveUiConfig`；`plugins.dart` 的 `clearDisk` 改清它（`installPluginHooks` 多了 `services` 参数，`main.dart` 传）；`data_tools.dart` 的 `folder` 改成 `<临时目录>/pureLiveImages` |
| c3 | 做了 | `AppImageCache.clearLegacyOnce`：meta `images.legacyCacheCleared` 没有时 `DefaultCacheManager().emptyCache()` 一次，成功后记下；失败下次启动再试 |
| c4 | 做了 | `danmaku_overlay.dart`：网络表情用 `CachedNetworkImageProvider(url, cacheManager:, headers: networkImageHeaders(url))`，`ResizeImage` 照旧；没装管理器时（测试、应用外）仍是 `NetworkImage`。请求头和聊天列表里同一张表情一样（以前飞行弹幕不带请求头） |
| 验收 1～5 | 做到 | 1 在本机回环上测了，代理日志要在 K90 上看 |

## 根因

- `LiveUiConfig.imageCacheManager`（`packages/live_ui/lib/src/scope.dart:242`）整个应用没人设置（`app.dart:180-186`），`CachedNetworkImage` 用 flutter_cache_manager 的默认管理器，它自己的 `http.Client` 不知道应用代理，直连；飞行弹幕的网络表情用 Flutter 自带的 `NetworkImage`，也直连。3.x 用 `CustomImageCacheManager` 专门修过（`lib/plugins/cache_manager.dart:6-34`）。

## 改了哪些文件

- 新：`apps/pure_live/lib/app/image_cache.dart`。
- `apps/pure_live/lib/app/app.dart`、`apps/pure_live/lib/main.dart`、`apps/pure_live/lib/platform/plugins.dart`、`apps/pure_live/lib/features/settings/data_tools.dart`、`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`。
- `apps/pure_live/pubspec.yaml`：加直接依赖 `http: ^1.6.0`（`IOClient`）和 `cached_network_image: ^4.0.4`（弹幕层的 provider），两个本来就是间接依赖（锁文件里的版本 1.6.0、4.0.4），`pubspec.lock` 没变。
- 文档：`docs/inventory/FEATURES.md` F-NET-01“部分”→“没验证”（统计表跟着改）；`docs/Q-网络和代理/Q02-代理和镜像/README.md` 几处“图片不走”。

## 新设置、翻译键、门禁基线

- 没有新设置、没有新文字。新 meta 键 `images.legacyCacheCleared`（不是设置）。

## 测试

- 新增 5 个：`apps/pure_live/test/image_cache_test.dart` 4 个（本机回环上起一个“代理”和一个“图片站”：开着代理时请求按绝对地址发到代理、关掉后下一张直连、地址没填完直连；缓存规则和目录；单例和旧缓存只清一次、失败下次再试；`PureLiveApp` 给 `LiveUiScope` 的管理器就是应用的）；`apps/pure_live/test/shared/danmaku_overlay_test.dart` 1 个（网络表情经应用的管理器下载、能飞）。
- 改之前：新增的 5 个都失败（没有 `image_cache.dart` 编译不过；弹幕层用 `NetworkImage` 时假的下载服务收不到请求）。
- 全部通过：`apps/pure_live` 902 个；`dart analyze --fatal-infos` 无问题；`check_deps.py`、`check_ui_structure.py`、`docs.py --check` 通过。

## 真机上要看的

- 电脑开着 Clash（局域网地址由维护者给）；K90 设置 → 网络 → 应用代理开、填地址端口；推荐 → Twitch：封面和头像都显示（以前是占位）；Clash 的连接里能看到图片主机。
- 进一个 Twitch 直播间：主播头像显示；聊天里和飞行弹幕里的 Twitch 表情是图片。
- 关掉应用代理，推荐下拉刷新：国内平台照常；Twitch 图片按直连的结果（多半失败），说明设置马上生效。
- 设置 → 数据 → 图片缓存：有图后大小不是 0；清空后变小。
- 升级后第一次打开，所有图片会重新下载一次（新缓存键，一次性流量）；旧的默认缓存被清掉。

## 留下的问题

- 版本历史页的 GitHub 图片（`release_history_view.dart:378`，`Image.network`）没改，归 Y02。
- 图片不按平台分路（`imageProxySite` 只有一个名字），同 Q02 说明。
