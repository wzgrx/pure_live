# H05 录制通知

Android 上录制时的两种通知写什么、什么时候发、点了去哪：一直显示的前台录制通知（谁在录、录了多久、“停止录制”“录制中心”两个按钮），和录制在后台出事时的“录制已停止”提醒。文字由 Dart 算、原生只负责显示。

## 范围

- 包括：
  - 通知的文字：`apps/pure_live/lib/app/recording_notice.dart` 的 `recordNotificationContent`（前台通知的标题、正文、按钮字、计时起点）、`_oneTitleKey`（一个直播间时按状态写标题，H05.1）、`recordStoppedContent`（“录制已停止”的原因和已保存的时长）。
  - 什么时候发：同一文件的 `RecordingNotices`（跟着录制器的任务列表，变了就刷新前台通知；任务变“录制失败”且是被系统停掉或应用不在前台时发提醒）、`stopAll`（通知上的“停止录制 / 全部停止”）。
  - 把文字送到原生：`apps/pure_live/lib/platform/recording_platform.dart` 的 `AndroidRecordKeepAlive.refresh`、`alert`、`extra`（`:166-308`）和 `platformAppRecording` 里接线的部分（`:362-402`）。
  - 原生显示：`android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt` 的 `RecordWords`（`:27-59`）、`update`（`:113`）、`alert`（`:130`）、`channels`（`:152`）、`openRecordings`（`:171`）、`taskRequest`（`:187`）、`buildNotification`（`:323`）；`RecorderPlugin.kt` 的 `update`、`alert` 通道（`:82-99`）、`stopAll`（`:160`）。
  - 点通知去哪：前台通知和“录制中心”按钮打开录制中心（`ShareIntakePlugin.ROUTE_RECORDINGS`）；“录制已停止”提醒带任务 id（`EXTRA_TASK`）打开录制中心并定位到那条任务。
- 不包括（归哪里）：
  - 通知的样子：小图标（`ic_stat_recording.xml`、`ic_stat_record_stopped.xml` 的形状）→ [A10.3](../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/README.md)；通知的整体排法、按钮、通知类别名 → [A14.1](../../A-界面设计/A14-系统界面/A14.1-系统界面/README.md)（c3～c5 的设计在那里，这里是它背后的逻辑）。
  - 前台服务本身的启停、唤醒锁、Wi-Fi 锁、绑定媒体服务（划掉应用后继续录）、Android 15 时限 → [H02](../H02-录制中心/README.md)（`AndroidRecordKeepAlive.acquire`/`release`、服务的生命周期）；通知权限的申请和说明 → [O01](../../O-Android系统集成/O01-通知和前台服务/README.md)。
  - 录制中心收到任务 id 后怎么滚动和高亮 → [A10.1](../../A-界面设计/A10-录制界面/A10.1-录制中心/README.md)（实现在 A08.5 c3，提交 `6a599edee`）；分享和快捷方式的入口 `ShareIntakePlugin` → O03。
  - 合并进度的数据 `RecordTask.mergeProgress` → [H01](../H01-录制核心/README.md)（H01.3）。
  - Windows、Linux 没有录制通知（D-004，当前只做 Android）。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - **前台录制通知**（类别“录制”，低重要性、不响、不显示角标）：一个直播间时标题按状态写——“准备录制 · 晚风”“正在录制 · 晚风”“正在重连 · 晚风”“正在整理录像 · 晚风”（H05.1），正文“直播间标题 · 清晰度”；几个直播间时“正在录制 3 个直播间”，正文“晚风、星河长明、……”。右上角的时间由系统按最早一个任务的开始时间走秒（`setUsesChronometer`，不每秒刷新）。两个按钮“停止录制”（几个时“全部停止”，停掉所有在录和排队的任务、已录的保存）和“录制中心”；点通知本身也打开录制中心（**不定位到任务**，H05.2 要改）。小图标是录制中的形状（A10.3）。
  - **“录制已停止”提醒**（类别“录制提醒”，默认重要性、点了自动消失）：标题“录制已停止 · 晚风”；正文是原因 + 已保存多少——“系统给后台录制的时间用完了。”（Android 15 的 dataSync 时限）、“后台录制被系统停掉了。”、“录制出错停止了。”，后面接“已录下的 12:34 已保存，回到应用可以重新开始。”或“回到应用可以重新开始。”。每个任务一条（标签 `record_alert:<任务 id>`），点开或点“打开录制中心”到录制中心并滚到那条任务、闪一下主色边框。小图标是圆环开口加“!”（H05.1）。
  - 什么时候发提醒：任务从别的状态变成“录制失败”时，原因是系统停掉了前台服务（`lastErrorStage == 'background'`，不论应用在不在前台），或者其他失败但应用不在前台（`recording_notice.dart:152-153`）。应用在前台时普通失败只在录制中心和面板里显示。
- 内部怎么工作：

```text
Recorder.changes（每次任务变化）
  → RecordingNotices.changed（recording_notice.dart:147）
      ├ refresh() → AndroidRecordKeepAlive.refresh（recording_platform.dart:216）
      │     服务没开或正在开关 → 不发；文字和上次一样（_same）→ 不发
      │     否则 invokeMethod('update', {title, text, since, stop, center, open, channel…})
      │       → RecorderPlugin（:82）→ RecorderForegroundService.update（:113）→ notify(NOTIFICATION_ID)
      └ 每个变成 failed 的任务：被系统停 或 不在前台 → recordStoppedContent → alert(id, title, text)
            → RecorderPlugin（:87）→ RecorderForegroundService.alert（:130）
                PendingIntent 请求码 = taskRequest(id)（:187，每个任务一个，避免都打开最后一个任务）
前台通知第一次出现：Recorder._start → keepAlive.acquire → setActive {active: true, …同样的文字}
通知上“停止录制”：服务收到 ACTION_STOP_ALL → onStopRequested → Dart 'stopAll' → RecordingNotices.stopAll
```

- 文字只由 Dart 给：原生 `RecordWords.from`（`RecorderForegroundService.kt:41-57`）只在缺字时退回 3.x 的“直播录制进行中”和固定中文按钮字，所以翻译、状态判断都在 Dart 测试里覆盖。
- 完成度（和 3.x 对照）：
  - 3.x：通知永远是“直播录制进行中 / 录制与封装由独立后台服务保护，点按返回应用”（`lib/recorder/services/recorder_background_service.dart:117-121`），类别名英文“Recording”，没有按钮，小图标用应用图标前景，点了回到应用首页；后台录制被系统停掉时只在应用里标失败。
  - 确认过的改动（A14.1 c3～c5，X1、X2 选 A）：通知写清谁、几个、多久；“停止录制”“录制中心”两个按钮；“录制已停止”提醒和第二个通知类别。H05.1（A10.3 X4 选 A）：一个直播间时按状态写标题，提醒换自己的小图标。A08.5 c3：提醒定位到任务。
  - 还缺：点前台通知不定位任务（H05.2）；整理文件时通知没有进度、计时还在走（H05.3）；H05.1 没有真机结果（待真机）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/recording_notice.dart`（174 行） | `RecordNotificationContent`（`:13`，`title`、`text`、`stop`、`since`）；`recordNotificationContent`（`:22-55`：没有活动任务时 3.x 的两句、一个时按状态的标题 + “标题 · 清晰度”、几个时数量 + 主播名；`since` = 最早的 `displayStartTime`）；`_oneTitleKey`（`:59-64`）；`formatRecordDuration`（`:67`）；`recordStoppedContent`（`:76-86`，三种原因 + 已保存时长）；`RecordingNotices`（`:94`：`start`、`changed` `:147`、`stopAll` `:165`、`dispose`） |
| `apps/pure_live/lib/platform/recording_platform.dart`（404） | `AndroidRecordKeepAlive`（`:166`）：`_words`（`:212`）、`refresh`（`:216`，只发变了的文字）、`alert`（`:231`）、`_same`（`:241`）、`_native`（`:300`，收 `stopAll`、`interrupted`）；`platformAppRecording`（`:348`）里给 `extra`（`since`、按钮字、两个类别的名字和说明，`:368-379`）并建 `RecordingNotices`（`:401`） |
| `android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`（344） | `RecordWords`（`:27`）和 `from`（`:41`）；常量（`:95-99`：两个类别 id、通知 id `20260906`，提醒用 `+1` 和标签区分）；`update`（`:113`）、`alert`（`:130`，`ic_stat_record_stopped`、`CATEGORY_ERROR`、自动消失）、`channels`（`:152`，类别名每次按 Dart 给的字重建，把 3.x 的英文“Recording”改掉）、`openRecordings`（`:171`，带任务时加 `EXTRA_TASK`）、`taskRequest`（`:187`，`0x1000 + hash`，避开前台通知的 0～4）；`buildNotification`（`:323-343`：`ic_stat_recording`、标题、正文、`openRecordings(this, 0)`、“停止录制”`:335`、“录制中心”`openRecordings(this, 4)` `:336`、`CATEGORY_PROGRESS`、`setOnlyAlertOnce`、有 `since` 时系统计时） |
| `android/.../RecorderPlugin.kt`（242） | 通道 `pure_live/recorder`：`setActive`（`:107`，带同样的文字启动服务）、`update`（`:82`）、`alert`（`:87-99`，标题最多 120 字、正文 400 字）、`onStopRequested` → Dart `stopAll`（`:158-161`） |
| `android/.../ShareIntakePlugin.kt` | `ROUTE_RECORDINGS`（`:68`）、`EXTRA_TASK`（`:66`）、`openRoute`（`:78`）；读意图时只有录制中心带任务（`:268-270`）——录制通知借用它，代码归 O03 |
| `android/app/src/main/res/drawable/ic_stat_recording.xml`、`ic_stat_record_stopped.xml` | 两个小图标（形状归 A10.3） |
| `apps/pure_live/assets/translations/zh.json`、`en.json` | `record_notify_*`（`:1367-1374`）、`record_stopped_*`（`:1435-1440`）、`record_channel_*`、`record_alert_channel_*`、3.x 的 `recorder_background_notification_*`（`:1447-1448`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/platform/system_surfaces_test.dart` 的 `recording notification (c3, c4)` 一组（3 个，`:37-103`） | 一个 / 几个直播间的标题、正文、计时起点；一个直播间按状态写标题（H05.1，`:52`）；`refresh` 只在文字变时发、“停止录制”停掉全部 |
| 同上 `"录制已停止" (c5)` 一组（2 个，`:105-162`） | 三种原因和已保存时长；被系统停掉时发、应用在后台的失败发、前台的失败不发，每次变化都刷新前台通知 |
| 同上 `Android resources`（`:214` 起） | 单色小图标、只在 Dart 里引用的图片不被发布版资源压缩删掉、各插件请求码不冲突 |
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart` 的定位用例（`:777-817`） | 带任务 id 打开录制中心时滚到并高亮；任务后来才恢复出来；任务不在了不高亮 |
| `apps/pure_live/test/intake_test.dart`（`:233`、`:357`、`:385`） | 提醒的路由和任务 id 只交给录制中心、录制中心在最上面时原地替换 |

## 3.x 基线

- `git show v3.2.11:android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt`（249 行）：类别 `CHANNEL_NAME` 英文、说明 “Active live-stream recording”（`:216-227`）；`buildNotification`（`:229-248`）：应用图标前景当小图标、点了 `CLEAR_TOP` 回 `MainActivity`、没有按钮；文字从 Dart 的 `setActive` 带来，之后不更新。
- `git show v3.2.11:lib/recorder/services/recorder_background_service.dart:110-121`：`setActive` 时固定送 `recorder_background_notification_title`、`_text`（“直播录制进行中”“录制与封装由独立后台服务保护，点按返回应用”）。
- 3.x 没有“录制已停止”提醒：服务被系统停掉时 `onTimedOut`、`onStopped` 回到 Dart，只把任务标失败。
- 要保留的：两个 3.x 翻译键还在用（没有活动任务时的兜底文字）；通知类别 id `pure_live_recording` 不变（改了用户的通知设置会丢）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 只录一个直播间时点前台通知（或“录制中心”按钮）只到录制中心顶上，不定位那条任务 | `RecorderForegroundService.kt:334`、`:336`（`openRecordings(this, 0)`、`(this, 4)` 不带任务） | 任务多时要自己找 | [H05.2](H05.2-只录一个直播间时点前台录制/README.md) |
| 整理文件时通知只有“正在整理录像 · 晚风”，没有百分比，右上角计时还在走 | `recording_notice.dart:40-47`；`RecorderForegroundService.kt:340-341` | 以为还在录、不知道要等多久 | [H05.3](H05.3-录制通知显示合并进度/README.md) |
| 几个直播间时标题永远是“正在录制 N 个直播间”，即使其中有的在重连、整理 | `recording_notice.dart:49-54` | 看不出哪个出了问题 | A14.1 c3 的设计如此（几个时只列主播）；要改先在 V01 提议 |
| 应用在前台时普通的录制失败不发提醒 | `recording_notice.dart:153` | 用户在别的页面（不在录制中心）时只看到录制按钮变“!” | 有意（A14.1 c5：提醒是给看不到应用的时候用的），不做 |
| 用户关掉通知权限时前台通知和提醒都不显示，录制照常 | `RecorderForegroundService.kt:121`、`:146`（吞掉异常） | 看不到录制状态 | 权限说明在 O01；不做 |
| H05.1 待真机；A14.1 的通知各状态只在 S02.2 看过“正在录制 · 主播” | [S02.2 记录](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md) | 准备、重连、整理三种标题和新图标没在 K90 上看过 | [H05.1 verify.md](H05.1-录制通知按状态写标题/verify.md)；和 A10.3 的 verify 同一轮做 |

## 相关决定和规范

- D-004：只做 Android（Windows、Linux 没有录制通知）。D-005：通知文字中文，`zh.json`、`en.json` 一起加。D-019：验证只在测试包上做。
- A14.1 的 X1（通知加“停止录制”“录制中心”两个按钮）、X2（被系统停掉时发提醒）、A10.3 的 X4（按状态写标题、提醒另做图标）都按建议 A（D-003）。
- [specs/UI.md](../../specs/UI.md)：通知文字和应用里的说法一致（“整理文件”“正在重连”）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/platform/system_surfaces_test.dart test/features/recorder test/intake_test.dart`。原生（`RecorderForegroundService.kt`）没有单元测试，只能真机看；改原生后本机 `flutter build apk --debug` 一次。
- 真机：A10.3 的 [verify.md](../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/verify.md) 第 7、8、12、13 条和 [H05.1 的 verify.md](H05.1-录制通知按状态写标题/verify.md) 同一轮做；S02.2 看过“正在录制 · 主播”和两个按钮。

## 路线

1. H05.1 待真机：随 A10.3 的真机验证一起看（同一个构建），通过后两个一起改“完成”。
2. H05.2（第三档，小）：前台通知只录一个直播间时带任务 id。
3. H05.3（第三档，小）：整理时显示进度、去掉计时。H05.2 和 H05.3 都改 `RecorderForegroundService.kt` 的 `buildNotification` 和 `RecordWords`，建议同一个人连着做（或一起做），后做的合并先做的。
4. 新想法（例如通知上显示文件大小、按任务分开的通知）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [H 录制](../README.md)。

- 代码：`app/recording_notice.dart`、`RecorderForegroundService.kt`
- 进度：`██████████████░░░░░░` 72%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| H05.1 | 录制通知按状态写标题，“录制已停止”提醒换新图标 | 功能 | 待真机 | 2026-10-02 | 79ecb5d2b | [设计或说明](H05.1-录制通知按状态写标题/README.md)、[任务书](H05.1-录制通知按状态写标题/brief.md)、[真机验证](H05.1-录制通知按状态写标题/verify.md) |
| H05.2 | 只录一个直播间时，点前台录制通知也定位到那条任务 | 功能 | 待真机 | 2026-10-08 | — | [设计或说明](H05.2-只录一个直播间时点前台录制/README.md)、[任务书](H05.2-只录一个直播间时点前台录制/brief.md)、[记录](H05.2-只录一个直播间时点前台录制/record.md)、[真机验证](H05.2-只录一个直播间时点前台录制/verify.md) |
| H05.3 | 录制通知在合并时显示进度（H01.3 记录“没做的”第 2 条） | 功能 | 待真机 | 2026-10-08 | — | [设计或说明](H05.3-录制通知显示合并进度/README.md)、[任务书](H05.3-录制通知显示合并进度/brief.md)、[记录](H05.3-录制通知显示合并进度/record.md)、[真机验证](H05.3-录制通知显示合并进度/verify.md) |
| H05.4 | 点录制通知定位到任务后，卡片标题被顶出屏幕 | 界面 | 未开始 | — | — | [设计或说明](H05.4-通知定位后卡片标题被顶出屏幕/README.md) |

## 还没完成的

- **H05.4 点录制通知定位到任务后，卡片标题被顶出屏幕**（未开始，第三档，规模 小）
  - 来源：K90 复查 H05.2（2026-10-08）

<!-- docs:生成结束 -->
