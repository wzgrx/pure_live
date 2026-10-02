# 4.0.0 发布前修复（2026-10-02）

发布前审查发现的问题，只管 Android。每条一次提交。

## 1. release 包删掉了媒体通知按钮的图标

- **根因**：release 打开了资源压缩（`isShrinkResources = true`）。`raw/keep.xml` 只保留了 `ic_stat_playback`。媒体通知的按钮（`background_playback.dart` 的 `mediaControls`）用 `MediaControl.pause/play/stop.androidIcon`，即 `drawable/audio_service_pause`、`audio_service_play_arrow`、`audio_service_stop`；这些名字只出现在 Dart 里，audio_service 用 `getIdentifier` 按名字查，压缩器看不到引用就删了，查到的 id 是 0。Android 13 起 audio_service 把“停止”做成 `PlaybackStateCompat.CustomAction`，`CustomAction.Builder(..., 0)` 抛 `IllegalArgumentException`，媒体通知和前台服务都起不来。3.x 的 `keep.xml` 保留的正是这三个。
- **改动**：`keep.xml` 加回三个图标，和 `ic_stat_playback` 一起保留。
- **测试**：`test/platform/system_surfaces_test.dart`“every drawable named only from Dart survives the release resource shrinker”：从 `mediaControls` 取出全部图标名，加上通知小图标，逐个检查 `keep.xml` 里有。改之前失败（缺 `audio_service_*`）。
- **验证**：见文末“release 构建”。
