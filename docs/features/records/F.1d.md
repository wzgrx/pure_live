# F.1d 冷门的播放设置

- 日期：2026-10-02
- 任务：[F.1d/README.md](../F.1d/README.md)
- 改动：`features/live_play/`（`live_play_page.dart`、`logic/player_standby.dart`（新）、`logic/room_runtime.dart`、`logic/mini_window.dart`、`mini/floating_window.dart`、`mini/room_mini_window.dart`、`player/player_view.dart`、`player/portrait_diagnostics.dart`（新））、`app/app.dart`；翻译 2 个键

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 退出时销毁播放器（X1 = A） | ✅ | `PlayerStandby`（跟着 provider 作用域，一次只留一个）。离开直播间且不转应用内悬浮窗时：设置“关”（默认，同 3.x）→ 房间的其他部分照常释放，会话 `stop()` 完再放进来（先停完再交出，避免停止还在跑时下一个房间已经开始播），播放器由会话自己留 45 秒；下一个直播间的播放器配置（解码、输出驱动、兼容模式等 8 项）一样就直接用，不一样就释放旧的再新建。设置“开”→ 和原来一样立即释放。应用内悬浮窗的关闭（✕、多画面、换房间）照旧释放 |
| c2 小窗跟随竖屏源 | ✅ | `miniPictureSize`：竖屏画面在“小窗跟随真实画面比例”关时固定 9:16，开时按真实比例（第一帧前用 F.1b 的声明）；横屏照旧按真实比例。用在应用内悬浮窗、画中画进入、自动画中画（设置改动立即重新登记）、桌面小窗 |
| c3 竖屏诊断 | ✅ | “显示识别状态”开时画面左上角（常规 62 高，全屏在顶栏下）显示：宽×高、比例、方向（竖屏 / 横屏 / 近方形 / 等待尺寸）、手动覆盖（自动识别 / 强制竖屏 / 强制横屏），第二行依据（解码尺寸 / 平台预判）。v4 没有置信度、稳定次数、时间，不显示（偏差） |
| c4 小窗弹幕预览 | ✅（核对） | U.6c 已做完（`PipDanmakuPreviewBinding`、`live_ui` 的 `PipDanmakuPreview`，测试在 U.6c 的记录里）；清点 F-MINI-04 改成完成，统计同步 |
| c5 内存紧张清图片 | ✅ | `app/app.dart` 接 `didHaveMemoryPressure` → `releaseImageMemory`：清缓存，并清“正在用的图片”记录（Flutter 自己只清前者） |
| c6 键盘媒体键 | ✅ | 直播间加播放 → 继续、暂停 → 暂停、播放/暂停 → 切换（照 v3） |

## 根因

- P1：v4 每个直播间一个会话（M13.3），离开即释放，`useHardStopOnExit` 没人读；会话的 `stop()` 本来就留播放器 45 秒，只是没有下一个房间来接。
- P2、P3：搬小窗（U.2j）和竖屏识别（M7）时两个设置只留了设置行。
- P4：应用没接 `didHaveMemoryPressure`。
- P5：搬快捷键（M13.14）时漏了媒体键。

## v3 → v4

`player_manager.dart:3640-3681` → `logic/player_standby.dart` + `RoomRuntime.dispose(keep:)` + `live_play_page.dart`；`portrait_stream_support.dart:770-778` → `logic/mini_window.dart` 的 `miniPictureSize`；`video_controller_panel.dart:704-745` → `player/portrait_diagnostics.dart`；`desktop_manager.dart:774-781` → `app/app.dart` 的 `releaseImageMemory`；`video_keyboard.dart:56-59` → `live_play_page.dart` 的快捷键。

## 设置

没有新设置；`useHardStopOnExit`（默认关）、`portraitPipFollowSource`（默认开）、`showPortraitDiagnostics`（默认关）键名和含义不变，设置行早已在 `settings_catalog.dart`（U.6c）。新翻译键：`portrait_evidence_decoder`、`portrait_evidence_platform`（zh、en）。

## 测试

`test/features/live_play/room_extras_test.dart` 7 个：留给下一个房间 / 开关打开立即释放 / 配置变了换新的；小窗尺寸规则；悬浮窗跟随开关；诊断文字；诊断开关；内存紧张清正在用的图片；媒体键。

改了已有测试 2 处（`live_play_mini_window_test.dart`）：“关掉离开小窗播放时不留东西”和桌面小窗 ✕ 原来断言离开后播放器立即释放；现在默认（播放器强制销毁关）留 45 秒给下一个房间，改成断言 45 秒后释放。

## 要在 K90 上看的

- 关着“播放器强制销毁”：退出一个直播间马上进另一个，起播是否更快；退出后等 45 秒内存回落。打开它：退出即释放。
- TASKS 第 5 节 5.1 第 11、12 条：竖屏直播进画中画、离开转悬浮窗，“小窗跟随真实画面比例”开关两种情况的窗口比例。
- 5.1 第 8 条：打开“显示识别状态”，进抖音竖屏主播，起播时显示“平台预判”，出画面后变“解码尺寸”。
- 外接键盘（有的话）的播放/暂停键。

## 合并时注意

- 默认行为变了：原来离开直播间（不转悬浮窗）立即释放播放器，现在照 3.x 默认留 45 秒。换房间（切换直播间对话框）时新页面先建好，旧页面后关，所以这一种不复用（旧的留着等下一个或 45 秒后释放）。
- `RoomRuntime.dispose` 多了可选参数 `keep`，构造多了可选 `playerConfig`；电视的直播间没用这些，不受影响。
