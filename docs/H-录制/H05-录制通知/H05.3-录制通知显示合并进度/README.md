# H05.3 录制通知在合并时显示进度

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（含 Android 原生的一小处）
- 来源：H01.3 记录“没做的”第 2 条（[H01.3 记录](../../H01-录制核心/H01.3-合并进度/record.md)）：“录制通知在合并时不显示进度（`app/recording_notice.dart` 不在本任务目录）”。V03.3 核对功能清点 F-REC-13 时发现没有任务管它。
- 相关：H01.3（`RecordTask.mergeProgress`、录制面板和录制中心的百分比）；H05.1（通知按状态写标题，待真机）；H05.2（点通知定位任务，同一个原生文件）；A14.1（系统界面，通知的样子）

## 目标

停止录制后，FFmpeg 把分段合成 MP4 的这段时间（长录像可能要几十秒到几分钟），前台通知除了“正在整理录像 · 晚风”，还显示百分比和进度条，和录制面板、录制中心同一个数。用户在桌面或别的应用里下拉通知栏就能知道还要等多久，不用回到应用。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 合并进度 | `lib/recorder/services/video_processor_service.dart:26` 的事件流发进度，界面没接（功能清点 F-REC-13） | `packages/live_record/lib/src/recorder.dart:818-840` 的 `_mergePending`：`RecordTask.mergeProgress`（0～1，只在内存），第一次和每过一个整数百分比发一次变化（`persist: false`）；`apps/pure_live/lib/shared/record/record_state.dart:101` 的 `recordMergePercent` 取整 | 不变 |
| 面板和录制中心 | 无 | `apps/pure_live/lib/shared/record/record_status_card.dart:410-430`：“正在整理文件”旁边显示百分比、图标画进度（H01.3） | 不变 |
| 前台通知 | 3.x 原生 `android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt:229-247`：只有标题和正文（“直播录制进行中”），没有进度 | 文字：`apps/pure_live/lib/app/recording_notice.dart:22-56` 的 `recordNotificationContent`，一个直播间时标题按状态取（`:59-64` 的 `_oneTitleKey`，整理时“正在整理录像 · {name}”），正文是“标题 · 清晰度”（`:44`）；原生 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:323-344` 的 `buildNotification` 只设标题、正文、按钮、计时 | 一个直播间在整理时：正文末尾加“42%”，并显示系统进度条（`Notification.Builder.setProgress`）；几个直播间时不显示进度条 |
| 更新频率 | — | 任务列表一变 `RecordingNotices.changed`（`recording_notice.dart:147`）就调 `refresh`；`apps/pure_live/lib/platform/recording_platform.dart:216-228` 的 `refresh` 只在文字变了时发 `update` | 整理时最多每秒更新一次通知（系统对频繁更新会限流、丢更新） |

## 方案

- c1 `recordNotificationContent` 的返回加 `progress`（`int?`，0～100）：只有一个活动任务、状态是 `processing`、`recordMergePercent(task.mergeProgress)` 不为 null 时给出；正文改成“标题 · 清晰度 · 42%”（数字用已有的百分比写法，不加新翻译键；要加的话 zh、en 都加）。
- c2 `AndroidRecordKeepAlive`（`recording_platform.dart:166`）的 `extra` 带上 `progress`；`refresh` 按时间节流：同一个任务整理中，两次 `update` 至少隔 1 秒（最后一次 100% 或状态变了立即发）。
- c3 原生 `RecordWords`（`RecorderForegroundService.kt:27-37`）加 `progress: Int?`，`from`（`:41`）读它；`buildNotification` 在 `progress != null` 时 `setProgress(100, progress, false)`，否则不设（之前设过的要清掉：`setProgress(0, 0, false)`）。
- c4 整理时不再显示录制计时（`setUsesChronometer`）：计时是录了多久，整理阶段显示它会让人以为还在录；改成只在 `running`、`reconnecting` 时带 `since`（`recordNotificationContent` 里按状态给 `since`）。

## 性能任务：测量

无：通知更新每秒最多一次，不影响合并速度。

## 验证

- 自动测试：`apps/pure_live/test/platform/system_surfaces_test.dart`（已有 `recordNotificationContent` 的用例）加：一个任务 `processing`、`mergeProgress` 0.42 → 正文以“42%”结尾、`progress` 是 42、`since` 为空；两个任务时 `progress` 为空；`AndroidRecordKeepAlive.refresh` 在 1 秒内收到 0.42、0.43 只发一次 `update`（用假的方法通道）。原生改动没有单元测试，靠真机。
- 真机：待真机（brief 的真机步骤）。

## 留下的问题

- H05.2 也改 `RecorderForegroundService.kt`（点通知的去向），两个任务先做哪个都行，后做的合并对方的改动。
