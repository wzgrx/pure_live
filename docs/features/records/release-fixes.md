# 4.0.0 发布前修复（2026-10-02）

发布前审查发现的问题，只管 Android。每条一次提交。

## 1. release 包删掉了媒体通知按钮的图标

- **根因**：release 打开了资源压缩（`isShrinkResources = true`）。`raw/keep.xml` 只保留了 `ic_stat_playback`。媒体通知的按钮（`background_playback.dart` 的 `mediaControls`）用 `MediaControl.pause/play/stop.androidIcon`，即 `drawable/audio_service_pause`、`audio_service_play_arrow`、`audio_service_stop`；这些名字只出现在 Dart 里，audio_service 用 `getIdentifier` 按名字查，压缩器看不到引用就删了，查到的 id 是 0。Android 13 起 audio_service 把“停止”做成 `PlaybackStateCompat.CustomAction`，`CustomAction.Builder(..., 0)` 抛 `IllegalArgumentException`，媒体通知和前台服务都起不来。3.x 的 `keep.xml` 保留的正是这三个。
- **改动**：`keep.xml` 加回三个图标，和 `ic_stat_playback` 一起保留。
- **测试**：`test/platform/system_surfaces_test.dart`“every drawable named only from Dart survives the release resource shrinker”：从 `mediaControls` 取出全部图标名，加上通知小图标，逐个检查 `keep.xml` 里有。改之前失败（缺 `audio_service_*`）。
- **验证**：见文末“release 构建”。

## 5. 两个插件用同一个权限请求码

- **根因**：`PermissionsPlugin.kt` 的通知权限和 `SystemAccessPlugin.kt` 的本地网络权限都用 `20261001`。Flutter 把每个权限结果交给所有插件的监听器，两个请求同时在等时，一个插件会拿另一个的结果答复自己的请求（例如通知被拒，本地网络也当成被拒）。
- **改动**：本地网络改成 `20261003`（通知 `20261001`、电池 `20261002`、录制存储 `20260907` 不变；依赖插件用的都是小数值，不冲突）。
- **测试**：`system_surfaces_test.dart`“the plugins' permission and activity request codes are unique”扫描 `android/app/src/main/kotlin` 里所有 `*_REQUEST` 常量，值不能重复。改之前失败（`NOTIFICATION_REQUEST reuses 20261001`）。
- **验证**：release 构建编译通过（见文末）。没有装到手机上试。

## 6. 外部意图可以打开任意页面

- **根因**：`MainActivity` 是启动图标的界面，必须导出，任何应用都能给它发 `com.mystyle.purelive.OPEN`。`ShareIntakePlugin.kt` 把 `route` 原样交给 Dart，`share_intake.dart` 直接 `openRoute` → `AppNavigator.toNamed`，别的应用因此能直接打开设置、备份、WebDAV 等任何页面。
- **改动**：只允许启动图标快捷方式（U.14 c15）和录制通知用到的两个页面：`/search`（搜索直播）、`/record_mannager`（录制中心）。Dart 侧 `ShareIntake.openableRoutes`，其他路由记日志后忽略（不提示）；Kotlin 侧 `OPENABLE_ROUTES` 在入口先丢掉，两边都挡。打开直播间的快捷方式（`platform` + `roomId`）不变，和分享链接一样。
- **测试**：`test/intake_test.dart`“an outside intent opens only the shortcut pages, anything else is ignored quietly”：`/settings`、`/backup`、`/web_dav`、`/live_play`、`/search/../settings` 都返回 `unsupported`、不导航、不提示；`/search` 照常打开。改之前失败（`/settings` 返回 `opened`）。
- **验证**：release 构建编译通过（见文末）。没有在手机上用 `am start` 试。
