# F.1a 屏幕常亮跟随设置

- 日期：2026-10-02
- 任务：[F.1a/README.md](../F.1a/README.md)
- 改动：`packages/live_player`（`lib/src/screen_wake.dart` 新、`video_view.dart`、`pubspec.yaml` 加 `wakelock_plus`）、`features/live_play/player/player_view.dart`、`features/live_play/mini/floating_window.dart`

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 `LiveVideoView` 自己管常亮 | ✅ | 新参数 `keepScreenOn`（默认开 = 原来的行为：播放或缓冲时常亮）；media_kit `Video` 的 `wakelock` 关掉；全应用一个计数（`ScreenWake`），几个画面不会互相关掉；参数变了立即生效；画面销毁时释放 |
| c2 直播间、应用内小窗按设置 | ✅ | 直播间画面（含竖屏的两种呈现）和应用内小窗传 `enableScreenKeepOn`，改设置立即生效（设置页、直播间外改都一样） |

和 v3 的差别（README 已写）：v3 在直播间里一直常亮，暂停也亮；这里只在播放或缓冲时常亮，和 v4 原来（media_kit）一样。

## 根因

v4 搬直播间（M13.3）时常亮交给了 media_kit `Video` 的默认值 `wakelock: true`，`enableScreenKeepOn` 没人读；而且 media_kit 只在建立时读这个参数，改了也不生效。

## v3 → v4

`live_play_controller.dart:177-179`、`:252-260`，`video_controller.dart:494`、`:1527` → `packages/live_player/lib/src/screen_wake.dart` + `video_view.dart`；直播间传设置在 `player_view.dart` 的 `_picture`。

## 设置

没有新设置；`enableScreenKeepOn` 键名和含义不变（默认开）。

## 测试

`packages/live_player` 2 个（关时不请求、开时立即请求、关掉释放、销毁释放；两个画面一个计数、暂停释放）；直播间 1 个（默认开时请求，关掉立即释放，再开立即请求，离开释放）。

## 没验证的

K90：TASKS 第 5 节 5.1 第 7 条（开时 3 分钟不灭屏，关时按系统超时灭屏）。

## 合并时注意

多画面（`features/multiview/widgets/cell_view.dart`）、电视（`tv/room/tv_live_play_page.dart`）不在本批目录，用默认值（播放时常亮，不看设置）；要跟设置时各加一个 `keepScreenOn:` 参数。
