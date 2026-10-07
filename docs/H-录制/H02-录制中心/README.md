# H02 录制中心

录制在应用里的接入（一个 `AppRecording`：录制器、设置、目录、FFmpegKit、前台服务）和录制中心页背后的逻辑（筛选、排序、操作、失败说明、打开文件夹、打开时定位任务）。

## 范围

- 包括：`apps/pure_live/lib/app/recording.dart` 的 `AppRecording`、`buildAppRecording`、任务的保存键和 3.x 任务的读取；`lib/platform/recording_platform.dart` 的 `FfmpegKitRunner`、`RecordCaBundle`、`AndroidRecordKeepAlive`、`platformAppRecording`；`lib/app/services.dart` 的 `recordingProvider`、`recorderProvider`；`features/recorder/`（页面、卡片动作、文字、筛选和排序）；`shared/record/record_state.dart`、`record_actions.dart`（录制面板和录制中心共用的状态和动作）；`RecorderPlugin.kt` 的 `setActive` 通道。
- 不包括（归哪里）：卡片、筛选条、状态卡的样子在 A10.1、A10.3；直播间的录制面板在 A07.6（用同一个 `AppRecording` 和 `shared/record/`）；录制设置页和目录在 H03；开播检测、排队在 H04；通知文字在 H05；`Recorder` 内部在 H01。

## 现状：做到哪、怎么工作的

- 用户看得到的：首页“录制”标签或路由 `/record_mannager`（`RoutePath.kRecordPage`，沿用 3.x 拼错的路径）进录制中心。顶部五个筛选（全部、进行中、等待开播、已保存、失败）带数量，下面每个任务一张卡（手机一列；横屏两列；宽屏按最小宽 400 排）。卡片头是封面、主播、平台、清晰度，下面是直播间录制面板同一张状态卡的紧凑版（九种状态）；“⋮”、长按、右键是同一个菜单（开播自动录、删除任务……）。开播检测关着且有等待开播的任务时，顶部提示“‘开播检测’关着……”和“打开”。没有 FFmpeg 的构建显示“录制不可用”。从“录制已停止”提醒点进来（路由参数是任务 id）时，列表滚到那条任务并闪一下。
- 内部怎么走：

```text
AppBootstrap.wire → platformAppRecording（recording_platform.dart:348）
  ├ FfmpegKitRunner（:23，FFmpegKit 0.6.2 + 自建 FFmpeg 9.0.2 原生包）
  ├ AndroidRecordKeepAlive（:166，通道 pure_live/recorder：setActive / update / alert）
  ├ androidStorageAccess（:322，所有文件访问权限）、RecordCaBundle（:109，CA 证书包）
  └ buildAppRecording（recording.dart:512）→ AppRecording（:369）
       start()（:422）：读设置 → 3.x 录像搬家 → recorder.restore(保存的任务；没有就读 3.x 的 recorder_tasks)
       addTask / startTask（:475、:483）：用户操作，先 allowUserRetry
页面：ref.read(recordingProvider) → recorder.changes 刷新、recorder.notices 弹提示
  recorderStates / recorderVisible（features/recorder/logic/recorder_view.dart）算卡片状态、筛选、排序
```

- 完成度：3.x 录制中心的全部功能都在（H02.1 记录“与 v3 的功能对照”）；确认过的改动：九个筛选改五个带数量（A10.1 U1 A）、卡片用状态卡、“立即检测”只检测不强制开始、失败说明本地化、平台标签用图标和中文名、按钮有进行中状态（H02.1、A10.1）；还缺：无。待改：合并失败的说明是英文（H01.5 阶段 2）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/recording.dart`（574 行） | `recorderTasksKey`（`recorder.tasks`，:17）和额外桌面窗口的键（:23）；`recipeOpeners`（FC2、Bigo、niconico，:32）；`recordChatConnector`（:43）；`defaultRecordDirectory`、`legacyRecordDirectory`、`moveLegacyRecordings`（:91-205，见 H03）；`RecordSettingsStore`（:212，见 H03）；`RecordingKeepAlive`（:356）；`AppRecording`（:369：`available`、`start`、`taskFor`、`addTask`、`startTask`）；`buildAppRecording`（:512）；`savedRecorderTasks`（:565，没有 v4 任务时读 3.x 的 `recorder_tasks`） |
| `apps/pure_live/lib/platform/recording_platform.dart`（404） | `platformHasFfmpeg`（Android、Windows、Linux）；`FfmpegKitRunner`（日志、统计、退出码、取消转成 `FfmpegExecution`）；`RecordCaBundle`（Android、Linux 把 Mozilla CA 包写到数据目录）；`AndroidRecordKeepAlive`（第一个持有者启动服务、最后一个释放时停止，系统停掉时调 `keepAliveInterrupted`，之后拒绝自动重试直到用户手动开始）；`androidStorageAccess`；`platformAppRecording` |
| `apps/pure_live/lib/app/services.dart` | `AppServices.recording`；`recorderProvider`（:126）、`recordingProvider`（:130） |
| `features/recorder/recorder_page.dart`（637） | `openRecordFolder`（:55，桌面打开文件管理器，Android 公共目录发意图、应用专属目录复制路径）；`RecorderPage`（:94）；`recorderTaskOf`（路由参数里的任务 id）；定位并高亮任务（`_seek`、`_reveal`）；筛选条、任务网格、开播检测关着的提示（`_PollingOffBanner`，:582） |
| `features/recorder/recorder_task_card.dart`（426） | 一张任务卡：卡片头、状态卡、菜单动作（`RecorderCardActions`） |
| `features/recorder/recorder_texts.dart`（143） | 筛选名、失败阶段、FFmpeg 失败类型、取流失败类型、受限原因的文字；`recordFailureText`（:72-90）；`recordNoticeText`；大小和时长格式 |
| `features/recorder/logic/recorder_view.dart` | `RecorderFilter`（五个筛选）、`recorderStates`、`recorderVisible`（按状态顺序、再按开始时间倒序）、各筛选的数量 |
| `shared/record/record_state.dart`（169） | `RecordCardState`（九种卡片状态）和 `recordCardState`（排队但有空位的显示成准备中）、`recordSlotsInUse`、“开播自动录”的判定、“这次录制”的清晰度选项、计时和大小文字 |
| `shared/record/record_actions.dart`（90） | 面板和录制中心共用的动作：“改上限”（打开录制设置并定位到最大任务数）、打开开播检测、再录一次、播放、查看原因 |
| `shared/record/record_status_card.dart`（701）、`record_look.dart`（58）、`saved_file.dart`（58） | 状态卡（界面属 A10、A07.6）、七种状态图形的选择（A10.3）、在后台确认录像文件还在 |
| `android/app/src/main/kotlin/com/mystyle/purelive/RecorderPlugin.kt` | 通道 `pure_live/recorder`：`setActive`（等服务真正进前台再回答，15 秒超时）、`update`、`alert`、存储权限申请、服务被停时发 `interrupted` |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart`（23） | 标题栏、五个筛选和数量、卡片顺序、卡片头和状态卡、录制图形只在录制中是红的、已保存的播放和打开文件夹、筛选为空、开播检测关着的提示、菜单、删除确认、横屏和宽屏的列数、3.x 默认目录的录像搬家、从提醒打开时定位任务 |
| `test/features/recorder/recorder_page_test.dart`（5） | 录制设置读 3.x 的键、没有 FFmpeg 时“录制不可用”、设置迁移、Android 文件夹地址 |
| `test/features/recorder/recording_wiring_test.dart`（3） | 受限房间的提示（22-1）、FFmpeg 失败类型的说明、前台服务启动一次和被系统停掉后的处理 |

## 3.x 基线

- `git show v3.2.11:lib/recorder/pages/recorder/recorder_page.dart`（842 行）：九个状态筛选的固定网格（:111-171）、按状态的按钮（:397-443）、失败原样显示 `task.lastError`（:682）；`recorder_controller.dart:1599-1601` 打开文件夹（返回值被忽略，点了没反应）。
- `lib/common/global/initial_services.dart:80-89`：只有开了“开机自启”且有存下的任务时才在启动时建录制器；4.x 启动时总是建（`AppBootstrap.wire`），但录制器空闲时不跑 FFmpeg。
- 直播间按钮怎么用录制器：`lib/modules/live_play/widgets/button/record_action_button.dart:166-198`（`forceStartTask`、`addTask(startImmediately:)`、`unRecorder`），4.x 对应 `startTask`、`addTask`、`removeTask`。
- 必须保留的操作习惯：卡片长按或右键 = 操作菜单（[specs/UI.md](../../specs/UI.md) 附录 A 第 14 条）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 合并失败的说明是英文 “Joining the recording failed” | `recorder_texts.dart:72-90`（`merge` 阶段没有说明）、`packages/live_record/lib/src/recorder.dart:891` | 卡片“最近失败（文件合并）”后面是英文 | [H01.5](../H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md) 阶段 2 |
| 点前台录制通知只到录制中心，不定位任务 | `RecorderForegroundService.kt:334` | 只录一个直播间时还要自己找 | [H05.2](../H05-录制通知/H05.2-只录一个直播间时点前台录制/README.md) |
| 没有录制历史页 | — | 3.x 也没有（只有路由 `kRecordHistory`） | 不做（H02.1 记录） |
| Windows 上的录制、合并、打开文件夹没在主机上跑过 | `recording_platform.dart`、`openRecordFolder` | — | X 组（D-004，当前只做 Android） |

## 相关决定和规范

- D-004（当前只做 Android）、D-005（文字中文）、D-018（3.x 设置键不变，`recorder_tasks` 照读）、D-019（只在测试包上验证）。
- 录制中心的界面决定见 [A10.1](../../A-界面设计/A10-录制界面/A10.1-录制中心/README.md)（U1 A：五个筛选）、[A10.3](../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/README.md)（红色只给录制中）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/recorder`（31 个）；用假的录制器和 `LiveStore.memory()`，不跑 FFmpeg。缺的：`AndroidRecordKeepAlive` 和真 FFmpegKit 只有通道层的测试。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节第 1、5、6 条；S02.2、S02.3 看过录制中心的“已保存”卡片和停止、合并。

## 路线

1. H01.5 阶段 2 修合并失败的中文说明（在 `recorder_texts.dart`）。
2. H05.2 点前台通知定位任务（录制中心的定位接口已经有了）。
3. 新想法（录制历史、批量删除、按主播分组）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [H 录制](../README.md)。

- 代码：`features/recorder/`、`app/recording.dart`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| H02.1 | 录制中心与录制设置（含录制接入） | 功能 | 完成 | 2026-10-01 | de14b3c8e | [设计或说明](H02.1-录制中心与录制设置/README.md)、[记录](H02.1-录制中心与录制设置/record.md) |

<!-- docs:生成结束 -->
