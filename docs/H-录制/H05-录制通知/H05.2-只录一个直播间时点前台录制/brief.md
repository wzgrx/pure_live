# H05.2 只录一个直播间时，点前台录制通知也定位到那条任务：任务书

## 背景

- 来源：[A14.1](../../../A-界面设计/A14-系统界面/A14.1-系统界面/README.md)“实现和验证”的偏差 ①：c5 设计“点开到录制中心”，A08.5 c3（提交 `6a599edee`，2026-10-02）让“录制已停止”提醒定位到任务，但“只录一个直播间时点**前台**录制通知仍不定位”，登记为本任务。
- 现象：录制中心里有十几条任务（等待开播的、已保存的），正在录的只有一条。下拉通知栏，点“正在录制 · 晚风”这条通知或它的“录制中心”按钮，录制中心打开在最上面（筛选每次打开都是“全部”，`recorder_page.dart:126`）；正在录的卡片按 `recordCardOrder` 排在前面，但重连中、整理文件中的任务排在录制中的后面，多列的宽屏上也不一定在第一屏，而且没有高亮，要自己找。点“录制已停止”提醒则会滚到那条并闪一下。两种通知行为不一样。
- 为什么现在做：第三档；规模小（Dart 两处、Kotlin 一处），定位的接口 A08.5 都做好了。
- 已经做过的：A14.1（通知、按钮，c3～c5）、A08.5 c3（`EXTRA_TASK`、录制中心按 id 定位、每个提醒一个请求码）、H05.1（按状态写标题，`79ecb5d2b`，待真机）。

## 目标和验收

1. 只有一个活动任务（准备中、录制中、重连中、整理文件中任一）时，点前台录制通知：录制中心打开，滚到这条任务，主色描边约 2 秒后淡掉（和提醒一样）。
2. 同样情况下点通知上的“录制中心”按钮：效果同第 1 条。
3. 同时录两个以上时点通知或按钮：录制中心打开在顶上，不高亮任何卡片（同现在）。
4. 从一个任务变成两个、再变回一个时，通知点开的去向跟着变（不会定位到已经不在录的任务）。
5. 已经停在录制中心时点通知：不叠出第二个录制中心（A08.5 c5 已有的规则照样生效）。
6. “录制已停止”提醒的行为不变。
7. 测试和门禁通过；`flutter build apk --debug` 能编过。

## 现状（读代码得出，写文件:行）

- 文字：`apps/pure_live/lib/app/recording_notice.dart:13` `RecordNotificationContent = ({String title, String text, String stop, DateTime? since})`；`recordNotificationContent`（`:22-55`）三个分支：没有活动任务（`:27-34`）、一个（`:40-48`）、几个（`:49-54`）。
- 送到原生：`apps/pure_live/lib/platform/recording_platform.dart:363` `content()`；`:368-379` `extra` 返回 `since`、`stop`、`center`、`open`、两个类别的名字和说明；`AndroidRecordKeepAlive._words`（`:212`）合并 `title`、`text` 和 `extra`；`refresh`（`:216-228`）用 `_same`（`:241-242`）比较整张表，变了才发 `update`；`_set`（`:286-298`）启动时 `setActive` 带同一张表。
- 原生：`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`：`RecordWords`（`:27-38`）、`from`（`:41-57`）；`update`（`:113-124`）重建通知；`openRecordings(context, request, task)`（`:171-179`）带 `task` 时 `putExtra(ShareIntakePlugin.EXTRA_TASK, task)`，`FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE`；`buildNotification`（`:323-343`）：点按 `openRecordings(this, 0)`（`:334`）、“停止录制”请求码 3（`:324-329`）、“录制中心”`openRecordings(this, 4)`（`:336`）。提醒的请求码 `taskRequest`（`:187`）= `0x1000 + hash`，避开 0～4。
- 接收：`ShareIntakePlugin.kt:268-270`（只给录制中心带 `task`，最长 200 字 `MAX_TASK_ID` `:91`）→ `apps/pure_live/lib/platform/share_channel.dart:27-37`（`SharedPayload.task`）→ `apps/pure_live/lib/app/intake/share_intake.dart:123-124`（录制中心的路由参数）→ `features/recorder/recorder_page.dart:110`（`recorderTaskOf`）、`:131`（`_target`）、`:166-197`（`_seek`、`_reveal`：一屏一屏往下找，恢复中的任务后来出现也能定位）。
- `RecordTask.taskId`：`packages/live_record/lib/src/task.dart:249`（例如 `bilibili_6`）。

## 3.x 基线

- `git show v3.2.11:android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt:229-248`：点通知 `CLEAR_TOP | SINGLE_TOP` 打开 `MainActivity`（回到应用当时的页面），没有按钮，没有录制中心的入口。
- 本任务是 4.x 的增强（A14.1 c3、c4 之上）；要保留的只有“点通知回到应用”这件事本身（现在是回到录制中心）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（原生代码规则）。
3. 本文件夹的 [README.md](README.md)；[H05 子分类说明](../README.md)；`docs/A-界面设计/A14-系统界面/A14.1-系统界面/README.md`（c3～c5、偏差 ①）；`docs/A-界面设计/A08-弹幕界面/A08.5-设置里的弹幕页/README.md` 和 `record.md`（c3 提醒定位的做法）。
4. 代码：上面“现状”列的文件；测试 `apps/pure_live/test/platform/system_surfaces_test.dart:37-103`、`test/features/recorder/recorder_centre_test.dart:777-817`、`test/intake_test.dart:233-240`。

## 范围

- 可以改：`apps/pure_live/lib/app/recording_notice.dart`（`RecordNotificationContent`、`recordNotificationContent`）；`apps/pure_live/lib/platform/recording_platform.dart`（`extra` 加 `task`）；`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`（`RecordWords`、`from`、`buildNotification`）；`apps/pure_live/test/platform/system_surfaces_test.dart`；本文件夹的 `record.md`。
- 不能改：`ShareIntakePlugin.kt` 和 `app/intake/`（O03，接口已够用）；录制中心的定位和高亮（A10.1、A08.5）；提醒（`alert`、`taskRequest`）；通知的文字、按钮数量、类别；`packages/live_record`；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：`RecordNotificationContent` 加 `task`（一个活动任务时是它的 id）；c2：`extra` 带 `task`；c3：原生 `RecordWords.task`，`buildNotification` 的点按和“录制中心”按钮带上它 | `recording_notice.dart`、`recording_platform.dart`、`RecorderForegroundService.kt`、`system_surfaces_test.dart` | 验收 1～7；新测试改之前失败；`flutter build apk --debug` 成功 |

- c3 的写法：`task = (map["task"] as? String)?.trim()?.takeIf { it.isNotEmpty() && it.length <= 200 }`；`setContentIntent(openRecordings(this, 0, words.task))`、`addAction(... words.center, openRecordings(this, 4, words.task))`。请求码不变（0、4）；`FLAG_UPDATE_CURRENT` 替换附加数据，`task` 为 `null` 时新意图没有 `EXTRA_TASK`，旧的会被去掉。
- 和 H05.3 的关系：H05.3 也给 `RecordNotificationContent`、`RecordWords` 加字段（`progress`），`buildNotification` 也要改。先做哪个都行，后做的在对方的基础上加字段，不要两边各写一份 `RecordWords.from`。

## 测试

- 改之前会失败：`system_surfaces_test.dart` 的 `recording notification (c3, c4)` 组加 `one room names its task; several or none name none`：`recordNotificationContent([_task('a', '晚风')]).task == 'a'`；`status: RecordStatus.reconnecting`、`processing` 时也是 `'a'`；两个活动任务时 `null`；只有 `waitingLive` 的任务时 `null`。
- 加：`the keep-alive sends the task again when the recording changes`：照 `:60-103` 的写法用假的 `MethodChannel`，`extra` 返回 `{'task': task}`，`acquire` 后把 `task` 从 `'a'` 换成 `'b'` 再 `refresh`，最后一次调用是 `update` 且参数 `task == 'b'`；换成 `null` 再 `refresh` 又发一次。
- 原生没有单元测试；本机 `flutter build apk --debug` 一次。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 录制中心里先留十几条别的任务（已保存、等待开播，能多就多，让正在录的那条不在第一屏也行）；在一个直播间开始录制，回到桌面 | 通知“正在录制 · 主播名” |
| 2. 下拉通知栏，点通知本身 | 录制中心打开（筛选“全部”），滚到这条任务，主色描边约 2 秒后淡掉 |
| 3. 回桌面，点通知上的“录制中心”按钮 | 同第 2 步 |
| 4. 再录第二个直播间，点通知 | 录制中心打开在顶上，没有高亮 |
| 5. 停掉第二个，等它整理完；再点通知 | 又定位到第一个任务 |
| 6. 停在录制中心时点通知，然后按一次返回 | 不叠出第二个录制中心；返回到进录制中心之前的页面 |
| 7. 让一个录制在后台失败（关“自动断线重连”后断网，见 H05.1 verify 第 7 步），点“录制已停止”提醒 | 照旧定位到失败的那条 |

（定位只在当前筛选的列表里找（`recorder_page.dart:169`），打开时筛选总是“全部”，所以一定找得到；找不到时不高亮，那是 A10.1 的行为，记下现象交维护者，不在本任务改。）

## 风险和注意

- `PendingIntent` 按请求码复用：只靠附加数据区分不了两个意图，所以提醒用每个任务一个请求码（`taskRequest`）。前台通知只有一条，请求码 0、4 固定，靠 `FLAG_UPDATE_CURRENT` 每次替换附加数据；不要改成 `FLAG_CANCEL_CURRENT`（会让已经展开的通知点了没反应）。
- 文字没变、只有任务变了时，`refresh` 也要发（`_same` 比较整张表，`task` 在表里就会发）；但服务没开时 `refresh` 不发，第一次的 `task` 靠 `setActive` 带上。
- 可能冲突的文件：`RecorderForegroundService.kt`、`recording_notice.dart`（H05.3）；`system_surfaces_test.dart`（H05.3、A14.1 的后续）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/H05.2` 或本机工作区；提交信息以 `[H05.2]` 开头（英文），例如 `[H05.2] The recording notification opens the centre at its one task`；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`；原生改动后 `flutter build apk --debug`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（c1～c3 做到哪个）、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；测试数量（改之前失败几个）；改了哪些文件（含原生）；新翻译键（应为无）；要在真机上看的（上表）；可能冲突的文件（H05.3）。
