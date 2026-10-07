# H05.1 录制通知按状态写标题，“录制已停止”提醒换新图标

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（含 Android 资源）
- 来源：[A10.3 录制按钮和状态图标](../../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/README.md)的待选 X4（“‘录制已停止’提醒的小图标、准备中和合成中的前台通知文字”）：A10.3 定稿时按 D-003 选建议 A，但它要改 `RecorderForegroundService.kt` 和 `app/recording_notice.dart`，超出 A10.3 可改的范围，交维护者补做
- 旧编号：T08e.1
- 相关：A10.3（录制图形，通知小图标 `ic_stat_recording` 的新形状，c10）；A14.1（通知的设计 c3～c5）；A08.5 c3（提醒定位到任务，提交 `6a599edee`）；后续 H05.2、H05.3；真机验证 [verify.md](verify.md)，任务书 [brief.md](brief.md)

## 目标

前台录制通知说的和录制面板、录制中心一致：只有真正在写文件时才写“正在录制”，准备、重连、整理文件时各写各的；“录制已停止”提醒用一个看得出“停了、出事了”的小图标，不再和“正在录制”的通知长得一样。用户下拉通知栏就能分清“在录”“在重连”“在整理”和“已经停了”。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做之前（4.0.0，A14.1 之后） | 现在（`79ecb5d2b` 之后） |
|---|---|---|---|
| 一个直播间时的标题 | 永远“直播录制进行中”（`lib/recorder/services/recorder_background_service.dart:117-121`） | 永远“正在录制 · 晚风”，准备中、重连中、整理文件时也是（`recording_notice.dart` 只有 `record_notify_one`） | 按状态：准备中“准备录制 · 晚风”、录制中“正在录制 · 晚风”、重连中“正在重连 · 晚风”、整理文件“正在整理录像 · 晚风”（`apps/pure_live/lib/app/recording_notice.dart:43`、`_oneTitleKey` `:59-64`） |
| 几个直播间时 | 同上 | “正在录制 N 个直播间”，正文主播名 | 不变（`:49-54`） |
| “录制已停止”提醒 | 没有这种提醒 | 有（A14.1 c5），小图标和前台通知同一个 `ic_stat_recording` | 自己的小图标 `ic_stat_record_stopped.xml`：“未录”的圆环和圆点，右下角开口放一个“!”（`RecorderForegroundService.kt:135`） |
| 前台通知的小图标 | 应用图标前景 `ic_launcher_foreground`（3.x `RecorderForegroundService.kt:240`） | `ic_stat_recording`（A14.1 c2 时是圆环圆点） | A10.3 c10 改成实心圆挖出圆角方块（`ic_stat_recording.xml`，`RecorderForegroundService.kt:331`），不在本任务 |

## 结果

- c1 按状态写标题：`recordNotificationContent` 一个活动任务时用 `_oneTitleKey(task.status)` 选键；新键三个（中英文都加）：`record_notify_one_preparing`“准备录制 · {name}”、`record_notify_one_reconnecting`“正在重连 · {name}”、`record_notify_one_processing`“正在整理录像 · {name}”（`assets/translations/zh.json:1369-1371`）；`running` 和其他状态照旧 `record_notify_one`“正在录制 · {name}”。文字一变，`RecordingNotices.changed` → `AndroidRecordKeepAlive.refresh` 就把新标题发给原生（只发变了的，`recording_platform.dart:216`），不用改原生。
- c2 提醒的新图标：`apps/pure_live/android/app/src/main/res/drawable/ic_stat_record_stopped.xml`（24dp 单色矢量：开口圆环 + 中心圆点 + 右下角圆底“!”）；`RecorderForegroundService.alert` 的 `setSmallIcon` 改成它（`:135`）。它由 Kotlin 直接引用（`R.drawable`），发布版资源压缩会保留，不用加进 `res/raw/keep.xml`（那个文件只管 Dart 按名字查的图，见 `system_surfaces_test.dart:232`）。
- 提交 `79ecb5d2b`（2026-10-02，维护者补做，直接在 master）。改动 7 个文件、45 行：`recording_notice.dart`（+14）、`RecorderForegroundService.kt`（1 行）、`ic_stat_record_stopped.xml`（新）、两个翻译文件（各 +3）、测试（+8）、当时的云端记录 `docs/cloud/records/B04.md`（已不在仓库，内容见 `git show 79ecb5d2b`）。
- 没有单独的 `record.md`：改动小，记录写在提交说明和上面这一节。
- 测试：`apps/pure_live/test/platform/system_surfaces_test.dart` 新增 1 个 `one room says what it does: only writing is "正在录制" (U.2a2 X4)`（`:52-58`）：录制中、准备中、重连中、整理文件四种标题。

## 验证

- 自动测试：上面那 1 个用例；同文件 `recording notification (c3, c4)`、`"录制已停止" (c5)` 两组照常通过（几个直播间、计时起点、提醒的原因和已保存时长、什么时候发提醒）。图标的样子没有自动测试。
- 真机：**待真机**。步骤见 [verify.md](verify.md)；和 A10.3 的 [verify.md](../../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/verify.md) 第 7、8、12、13 条、S02.5 任务书清单 2B-02、2B-05、2B-06、4B-01 是同一批检查，用同一个构建一起做。

## 留下的问题

- 点前台通知只到录制中心、不定位任务：[H05.2](../H05.2-只录一个直播间时点前台录制/README.md)。
- 整理文件时没有进度、右上角计时还在走（“正在整理录像”下面的时间容易被当成还在录）：[H05.3](../H05.3-录制通知显示合并进度/README.md)。
- “排队中”（名额满）的任务不算活动任务（`RecordStatus.isActive` 不含 `queued`），只有排队任务时通知是 3.x 的兜底文字“直播录制进行中”——实际上排队时前台服务已经开了（`Recorder._start` 先取前台服务再入队，`packages/live_record/lib/src/recorder.dart:340-350`）。影响小（排队通常只在名额满时、而那时已有别的任务在录，标题是“正在录制 N 个直播间”）；只有“最大同时录制任务数”刚被调小时会单独出现。没有任务管，记在 H05 已知问题的路线里，需要时 H05.2 顺手处理。
