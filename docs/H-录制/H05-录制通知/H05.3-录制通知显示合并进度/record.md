# H05.3 录制通知在合并时显示进度：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（agent worktree），提交以 `[H05.3]` 开头；在 H05.2（`c371a9ae3`）之后
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；真机步骤：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 `progress` 和正文的百分比 | 做了 | `recording_notice.dart:57`：只有一个活动任务、状态 `processing`、`recordMergePercent` 不为空时给出；正文“标题 · 清晰度 · 42%”（`:63`，和录制中心卡片同一个写法 `'$percent%'`，没有新翻译键） |
| c2 `extra` 带 `progress`，节流 | 做了 | `recording_platform.dart:416`；`refresh`（`:229-250`）：同一个任务（标题、`task` 不变）整理中、上次也有进度、这次不到 100 时，离上次发送不到 1 秒（`progressGap`，`:207`）就等，到点发最新的那份（`_later`，`:237`）；100%、整理结束、任务变了立即发；服务停时取消等待（`:329`） |
| c3 原生进度条 | 做了 | `RecorderForegroundService.kt:55` 读 `progress`（夹到 0～100）；`:352-353` 有进度时 `setProgress(100, progress, false)`，否则 `setProgress(0, 0, false)` 清掉 |
| c4 整理时不显示计时 | 做了 | `since` 只按录制中、重连中的任务算（`recording_notice.dart:52`）；只有一个任务在整理（或准备中）时为空，通知不设计时 |

## 根因

- 进度数据早就有（H01.3 的 `RecordTask.mergeProgress`），但通知这条路上没有字段：`RecordNotificationContent`（原 `recording_notice.dart:13`）只有 `title`、`text`、`stop`、`since`（H05.2 后加了 `task`），原生 `buildNotification`（原 `RecorderForegroundService.kt:323-344`）不画进度条。H01.3 的范围不含 `app/recording_notice.dart`，留下了这一步。
- 计时：`since` 原来取所有活动任务里最早的开始时间（原 `recording_notice.dart:35-39`），整理中的任务也算，所以停止后计时还在跳。
- 3.x（`v3.2.11` 的 `RecorderForegroundService.kt:229-247`）通知只有固定的标题和正文；`video_processor_service.dart:26` 有进度事件流但界面和通知都没接。本任务是 4.x 的增强。

## 改了哪些文件

- `apps/pure_live/lib/app/recording_notice.dart`：`RecordNotificationContent.progress`、正文的百分比、`since` 只算录制中和重连中。
- `apps/pure_live/lib/platform/recording_platform.dart`：`extra` 加 `'progress'`；`AndroidRecordKeepAlive` 的节流（`progressGap`、`_progressWait`、`_later`），构造参数 `now`（测试用的时钟）。
- `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`：`RecordWords.progress`、`from`、`buildNotification` 的进度条。
- `apps/pure_live/test/platform/system_surfaces_test.dart`：2 个用例。

## 新设置、翻译键、门禁基线

- 没有新设置、没有翻译键、门禁基线不变。

## 测试

- 新增 2 个，改之前都失败（编不过：`progress`、`now` 不存在）：
  - `one room joining shows how far, without the clock; several show no bar (H05.3)`：0.42 → 正文以“42%”结尾、`progress` 42、`since` 为空；进度未知时不带百分比；两个任务时 `progress` 为空、计时取录制中的那个；准备中没有计时。
  - `the keep-alive sends the join progress at most once a second, the end at once (H05.3)`：可控时钟，1 秒内 43、44 不发，到点补发 44（等 1.1 秒）；100% 和整理结束立即发。
- `apps/pure_live` 全部 988 个测试通过；`dart analyze --fatal-infos` 无问题。
- 原生没有单元测试；按本次的规则没有在本机构建 APK，Kotlin 的改动靠下次构建和真机确认。

## 真机上要看的

- 见 [verify.md](verify.md)：整理时正文百分比在涨、有进度条、没有计时；和录制中心一致；整理完进度条消失；两个直播间时没有进度条；锁屏后进度继续。

## 和其他任务的关系

- 建在 H05.2 之上（同一个 `RecordWords`、`buildNotification`、`system_surfaces_test.dart`）。
- 留下的问题：两个直播间、其中一个在整理时，通知里看不到它的进度（按设计不显示进度条）；“整理中”的任务不再算进计时，所以几个任务里只剩整理中的时标题仍是“正在录制 N 个直播间”但没有计时，影响小。

## K90 复查（2026-10-08，master 660b488b7）

- 录了 2 分钟（约 50 MB）后停止，立刻下拉通知栏：合并已经做完，没赶上看进度条。要录 20 分钟以上（几百 MB）再看。
