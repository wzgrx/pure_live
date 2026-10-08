# H05.2 只录一个直播间时，点前台录制通知也定位到那条任务：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（agent worktree），提交以 `[H05.2]` 开头
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；真机步骤：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 `RecordNotificationContent.task` | 做了 | 一个活动任务时是它的 `taskId`（`recording_notice.dart:49`），没有、几个时 `null`（`:34`、`:57`） |
| c2 `extra` 带 `task` | 做了 | `recording_platform.dart:373`；`refresh` 比较整张表，任务换了会重发 `update`，`setActive` 启动时也带上 |
| c3 原生 `RecordWords.task` | 做了 | `RecorderForegroundService.kt:52` 读 `task`（去空白，空或超过 200 字当没有）；`:340`、`:342` 点按和“录制中心”按钮带上它，请求码 0、4 不变 |

## 根因

- 前台通知的点按和“录制中心”按钮一直是 `openRecordings(this, 0)`、`openRecordings(this, 4)`，不带任务 id（原 `RecorderForegroundService.kt:334`、`:336`）；Dart 给原生的文字里也没有任务 id（原 `recording_notice.dart:13` 的 `RecordNotificationContent` 只有 `title`、`text`、`stop`、`since`）。A08.5 c3 只给“录制已停止”提醒接了 `EXTRA_TASK`。
- 3.x（`v3.2.11` 的 `RecorderForegroundService.kt:229-240`）点通知只回到应用，没有录制中心入口；本任务是 4.x 的增强。

## 改了哪些文件

- `apps/pure_live/lib/app/recording_notice.dart`：`RecordNotificationContent` 加 `task`，三个分支各写一处。
- `apps/pure_live/lib/platform/recording_platform.dart`：`extra` 加 `'task'`。
- `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`：`RecordWords.task`、`from`、`buildNotification`。
- `apps/pure_live/test/platform/system_surfaces_test.dart`：2 个用例。

## 新设置、翻译键、门禁基线

- 没有新设置、没有翻译键、门禁基线不变。

## 测试

- 新增 2 个：`one room names its task; several or none name none (H05.2)`（改之前编不过：`task` 不存在，整个文件失败）；`the keep-alive sends the task again when the recording changes (H05.2)`（`a` → `b` → `null` 各发一次 `update`）。
- `apps/pure_live` 全部 986 个测试通过；`dart analyze --fatal-infos` 无问题。
- 原生没有单元测试；按本次的规则没有在本机构建 APK（`flutter build apk --debug` 没跑），Kotlin 的改动靠下次构建和真机确认。

## 真机上要看的

- 见 [verify.md](verify.md)：只录一个时点通知和“录制中心”按钮都滚到那条并闪描边；录两个时到顶上不高亮；从两个变回一个又能定位；停在录制中心时点通知不叠第二个；“录制已停止”提醒照旧。

## 和其他任务的关系

- H05.3 紧接着改同一个 `RecordWords` 和 `buildNotification`（加 `progress`），在本任务的基础上加字段。

## K90 复查（2026-10-08，master 660b488b7）

- 只录 YY“小颖儿”一个，按 Home，下拉通知栏点“正在录制 · 小颖儿”：打开录制中心，列表定位到这条、蓝色描边闪一下后淡出 ✓。
- 小毛病：定位后这张卡片的标题行（房间名、平台）被顶到屏幕外，只看到状态卡。另开 H05.4。
- 录两个时、已在录制中心时点通知：没看。
