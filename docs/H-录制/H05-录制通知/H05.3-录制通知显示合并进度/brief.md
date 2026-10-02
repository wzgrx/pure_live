# H05.3 录制通知在合并时显示进度：任务书

## 背景

- 来源：H01.3 记录（`docs/H-录制/H01-录制核心/H01.3-合并进度/record.md`）“没做的”第 2 条；V03.3（2026-10-03）开了本任务。
- 现象：录了 30 分钟后点“停止录制”，录制面板和录制中心显示“正在整理文件 42%”，但下拉通知栏，前台通知只有“正在整理录像 · 晚风 / 标题 · 超清”，没有百分比和进度条，计时还在跳。
- 为什么现在做：第三档；H01.3 做完了进度数据，通知只差最后一步。
- 已经做过的：H01.3（`RecordTask.mergeProgress`、面板和录制中心的百分比，提交 `d145aa930`）；H05.1（通知按状态写标题，提交 `79ecb5d2b`，待真机）。

## 目标和验收

1. 只录一个直播间、停止后整理时：通知正文末尾有“42%”这样的百分比，下面有系统进度条，和录制中心同一个数。
2. 整理时通知不再显示录制计时。
3. 同时录几个直播间（通知标题“正在录制 N 个直播间”）时不显示进度条。
4. 整理时通知最多每秒更新一次；最后 100% 和整理结束立即更新。
5. 测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 进度数据：`packages/live_record/lib/src/recorder.dart:818-840` 的 `_mergePending`：`task.mergeProgress` 在第一次和每过一个整数百分比时 `_update(task, persist: false)`，结束清成 null。
- 取整：`apps/pure_live/lib/shared/record/record_state.dart:101` 的 `recordMergePercent(double?)`。
- 通知文字：`apps/pure_live/lib/app/recording_notice.dart:13` 的 `RecordNotificationContent`（`title`、`text`、`stop`、`since`）；`:22-55` 的 `recordNotificationContent`：一个活动任务时标题 `_oneTitleKey`（`:59-64`，整理时 `record_notify_one_processing`“正在整理录像 · {name}”），正文“标题 · 清晰度”（`:44`），`since` 是最早开始录的时间。
- 跟随：`recording_notice.dart:94` 的 `RecordingNotices`，`:147` 的 `changed` 每次任务列表变化调 `refresh`。
- 发送：`apps/pure_live/lib/platform/recording_platform.dart:166` 的 `AndroidRecordKeepAlive`；`:212` 的 `_words()`（`title`、`text`、`extra`）；`:216-228` 的 `refresh`：和上次发的一样就不发，否则 `invokeMethod('update', words)`；`:362-379` 建 keep-alive 时给 `extra`（`since`、按钮文字、通知渠道名）。
- 原生：`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderPlugin.kt:82` 收到 `update`；`RecorderForegroundService.kt:27-37` 的 `RecordWords`，`:41` 的 `from`；`:113-124` 的 `update` 重发通知；`:323-344` 的 `buildNotification`（标题、正文、两个按钮、`CATEGORY_PROGRESS`、`setOnlyAlertOnce`，有 `since` 时 `setUsesChronometer(true)`）。

## 3.x 基线

- `git show v3.2.11:android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt:229-247`：通知只有标题、正文，没有进度。
- `git show v3.2.11:lib/recorder/services/video_processor_service.dart:26`：合并有进度事件流，但界面和通知都没接。
- 本任务是 v4 的增强（3.x 没有），沿用 H01.3 的进度口径；不改通知的渠道、按钮和点按去向。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/H-录制/H01-录制核心/H01.3-合并进度/record.md`；`docs/A-界面设计/A14-系统界面/A14.1-系统界面/README.md`（通知的样子 c3～c5）。

## 范围

- 可以改：`apps/pure_live/lib/app/recording_notice.dart`；`apps/pure_live/lib/platform/recording_platform.dart`（`AndroidRecordKeepAlive` 的 `extra` 和 `refresh` 节流）；`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`（`RecordWords`、`buildNotification`）；`apps/pure_live/test/platform/system_surfaces_test.dart`；需要新文字时 `apps/pure_live/assets/translations/zh.json`、`en.json`（按键名排序，4 空格缩进）。
- 不能改：`packages/live_record` 的进度计算（H01.3）；通知渠道、按钮、点通知的去向（H05.2）；“录制已停止”提醒；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2、c3、c4：文字带百分比和 `progress`，节流，原生画进度条，整理时不显示计时 | 上面“可以改”的文件 | 验收 1～5；`flutter build apk --debug` 能编过（原生改动） |

## 测试

- 改之前会失败：`system_surfaces_test.dart` 新用例“一个任务 `processing`、`mergeProgress` 0.42：正文以 42% 结尾、`progress` 42、`since` 为空”（现在正文没有百分比、`since` 有值）。
- 加：两个活动任务时 `progress` 为空；`mergeProgress` 为 null（FFmpeg 还没报）时不带百分比；节流：用假的 `MethodChannel` 和可控时钟，1 秒内两次进度只发一次 `update`，状态从 `processing` 变 `completed` 立即发。
- 测试里的定时器至少 1 秒；不访问真实平台。
- `apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`；原生改动后本机 `flutter build apk --debug` 一次（门禁不在跑的时候）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 在一个国内直播间开始录制，录 10 分钟以上（分段设置 5 分钟），点“停止录制”，马上下拉通知栏 | 标题“正在整理录像 · 主播名”，正文末尾百分比在涨，下面有进度条；没有计时 |
| 2. 同时打开录制中心对照 | 通知的百分比和录制中心卡片上的一致（最多差 1 秒的更新） |
| 3. 等整理完 | 通知消失（或变成没有任务时的样子），录制中心显示“已保存” |
| 4. 同时录两个直播间，停止其中一个 | 通知标题“正在录制 2 个直播间”…，没有进度条 |
| 5. 整理时把应用划到后台、锁屏 1 分钟再看 | 进度继续走，没有卡在某个数 |

## 风险和注意

- Android 对同一通知的频繁更新会限流（丢掉中间的更新）：节流到每秒一次，并保证最后一次一定发出。
- `setProgress` 设过之后要在不整理时清掉，否则进度条会留在“正在录制”的通知上。
- 可能冲突的文件：`RecorderForegroundService.kt`（H05.2 改点按去向）、`recording_notice.dart`（H05.1 改过标题）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/H05.3` 或本机工作区；提交信息以 `[H05.3]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`（`apps/pure_live`）；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；测试数量；改了哪些文件（含原生）；新翻译键（应为无）；要在真机上看的；可能冲突的文件。
