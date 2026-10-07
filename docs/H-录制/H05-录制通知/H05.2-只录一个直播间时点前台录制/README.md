# H05.2 只录一个直播间时，点前台录制通知也定位到那条任务

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（含 Android 原生的一小处）
- 来源：A14.1 记录的偏差 ①（“c5 点开当时只到录制中心”）和 A08.5 c3 之后的余项：A08.5（提交 `6a599edee`）让“录制已停止”提醒定位到任务，[A14.1 README](../../../A-界面设计/A14-系统界面/A14.1-系统界面/README.md)“实现和验证”写明“只录一个直播间时点**前台**录制通知仍不定位 → H05.2”
- 旧编号：T08e.2
- 相关：A08.5 c3（录制中心按任务 id 定位、`EXTRA_TASK`）；A10.1（录制中心的滚动和高亮）；H05.1（同一个通知的标题）；H05.3（同一个原生文件 `RecorderForegroundService.kt`、同一个 `RecordWords`）；任务书 [brief.md](brief.md)

## 目标

只录一个直播间时，点前台录制通知（或通知上的“录制中心”按钮），录制中心打开后滚到这条任务并闪一下主色描边，和点“录制已停止”提醒一样；同时录几个时照旧打开录制中心顶上（不知道用户想看哪个）。任务多（等待开播的、已保存的一大串）的人不用再自己翻找正在录的那条。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 点前台通知 | 回到应用当时的页面（`CLEAR_TOP` 打开 `MainActivity`，`android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt:229-240`），不进录制中心 | 打开录制中心顶上：`buildNotification` 的 `setContentIntent(openRecordings(this, 0))`（`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:334`） | 只有一个活动任务时带它的 id，录制中心定位 |
| “录制中心”按钮 | 没有按钮 | `openRecordings(this, 4)`（`:336`），同上不定位 | 同上 |
| “录制已停止”提醒 | 没有 | 已定位：`openRecordings(context, taskRequest(id), id)`（`:133`），`EXTRA_TASK`（`:176`） | 不变 |
| 通知的文字从哪来 | 固定 | Dart 的 `recordNotificationContent`（`apps/pure_live/lib/app/recording_notice.dart:22-55`）→ `AndroidRecordKeepAlive` 的 `extra`（`apps/pure_live/lib/platform/recording_platform.dart:368-379`）→ 原生 `RecordWords.from`（`RecorderForegroundService.kt:41-57`） | 同一条路多带一个 `task` |
| 录制中心收任务 id | — | 已有：`ShareIntakePlugin.kt:268-270` 只给录制中心带 `task`；`share_channel.dart:27-37`；`share_intake.dart:123-124`；`RecorderPage` 的 `recorderTaskOf`（`features/recorder/recorder_page.dart:110`）、`_seek`/`_reveal`（`:166`、`:176`） | 不变 |

## 方案

- c1 `RecordNotificationContent`（`recording_notice.dart:13`）加 `String? task`：活动任务正好一个时是它的 `taskId`，没有或几个时为 `null`（`:27-54` 三个分支各写一处）。
- c2 `platformAppRecording` 的 `extra`（`recording_platform.dart:368-379`）加 `'task': now.task`。`AndroidRecordKeepAlive.refresh` 比较整张表（`_same`，`:241`），任务换了也会重发 `update`；`setActive` 启动时同样带上。
- c3 原生 `RecordWords`（`RecorderForegroundService.kt:27-38`）加 `val task: String?`，`from` 读 `map["task"] as? String`，`trim` 后为空当 `null`、超过 200 字（和 `ShareIntakePlugin.MAX_TASK_ID` 一致）当 `null`。`buildNotification`（`:323-343`）的点按和“录制中心”按钮改成 `openRecordings(this, 0, words.task)`、`openRecordings(this, 4, words.task)`。请求码 0 和 4 不变：`FLAG_UPDATE_CURRENT` 会用新意图的附加数据整个替换旧的，所以从“一个任务”变成“几个任务”时，任务 id 也会被去掉。
- 不改：提醒的定位（A08.5）；录制中心的滚动、高亮（A10.1）；`ShareIntakePlugin`（O03）。

## 验证

- 自动测试：`apps/pure_live/test/platform/system_surfaces_test.dart`：一个活动任务（录制中、重连中、整理中都算）时 `task` 是它的 id、两个时为 `null`、只有等待开播的任务时为 `null`；`AndroidRecordKeepAlive` 用假的 `MethodChannel`：活动任务从 a 换成 b 时再发一次 `update`、参数里 `task` 是 b。录制中心按 id 定位已有测试（`test/features/recorder/recorder_centre_test.dart:777-817`），不用改。原生没有单元测试。
- 真机：待开发；步骤在任务书“真机验证”。

## 留下的问题

- 只有“排队中”的任务时（名额刚被调小），活动任务为空，通知是兜底文字、点了到顶上（`queued` 不算 `isActive`，见 [H05.1](../H05.1-录制通知按状态写标题/README.md)“留下的问题”）：本任务不改，影响小。
- 用户在录制中心以外的页面点通知时，录制中心叠在当前页面上；在录制中心时原地替换（A08.5 c5 的规则，`system_intake.dart:72-75`），不在本任务。
