# H04 自动录制和排队

录制“什么时候开始”的逻辑：开播检测（等待开播的任务定时查房间）、开播自动录（每个任务自己的“下播后接着等”）、同时录制的名额和排队、应用启动时恢复上次的任务。代码都在 `packages/live_record` 的 `Recorder` 和 `RecordScheduler` 里，应用里只有开关和动作。

## 范围

- 包括：
  - 排队：`RecordScheduler`（`packages/live_record/lib/src/scheduler.dart`）——先来先录、名额 = 设置“最大同时录制任务数”、两次开始至少隔 5 秒；`Recorder._start` 把任务放进队列（状态“排队中”）。
  - 开播检测：`Recorder` 的 `_canPoll`、`_schedulePoll`、`_poll`、`_doPoll`、`refreshTaskStatus`（录制中心的“立即检测”）、`settingsChanged`（开播检测开关变了）；时间规则 `RecordPolicy.pollingDelay`（`policy.dart:6-17`）。
  - 开播自动录：`RecordTask.autoRecord`（`task.dart:377`，v4 新加的每任务选择）、`Recorder.setTaskOptions`、`monitorTask`、`_endsAfterBroadcast`；应用里的 `setAutoRecord`、`enableRecordPolling`、`recordTaskAgain`（`apps/pure_live/lib/shared/record/record_actions.dart`）和判定 `autoRecordOn`（`shared/record/record_state.dart:70`）。
  - 启动时恢复：`Recorder.restore`、`_recover`（`recorder.dart:1203-1303`）；应用在 `AppRecording.start()`（`apps/pure_live/lib/app/recording.dart:422-440`）里调它。
  - 名额的显示规则：`recordSlotsInUse`（`record_state.dart:57`）、“排队但有空位的显示成准备中”（`record_state.dart:44`）。
- 不包括（归哪里）：
  - 一次录制里面的断线重连、重试上限、合并 → [H01](../H01-录制核心/README.md)（H01.5 改下播后的去向，会碰到本子分类的 `_schedulePoll`）。
  - 开播检测、启动时恢复、最大任务数这几项设置的存储、默认值、迁移 → [H03](../H03-录制设置和存储/README.md)（这里只管它们怎么生效）。
  - 看得见的部分：录制面板的“开播自动录”开关和“改上限”按钮 → [A07.6](../../A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md)；录制中心卡片菜单的“开播自动录”、顶部“开播检测关着”提示、等待开播和排队的状态图形 → [A10.1](../../A-界面设计/A10-录制界面/A10.1-录制中心/README.md)、[A10.3](../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/README.md)；录制设置页的“开播检测”一组 → [A10.2](../../A-界面设计/A10-录制界面/A10.2-录制设置/README.md)。
  - 前台服务（只在真正录的时候持有）→ [H02](../H02-录制中心/README.md)；通知 → [H05](../H05-录制通知/README.md)。
  - 关注列表的开播检查（关注页的刷新，和录制无关）→ [I04](../../I-浏览和发现/I04-关注/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - **开播自动录**：直播间录制面板和录制中心卡片菜单里一个开关（3.x 叫“添加监控 / 取消监控”）。打开时：没有任务就建一个“等待开播”的任务；任务停了、失败了、已保存就重新等；正在录的任务照录，下播后接着等。同时如果“开播检测”关着，自动打开并提示“已打开开播检测，每 30 秒检查一次”（`enableRecordPolling`，`record_actions.dart:27-32`）。关掉时：正在录的照录，下播后结束为“已保存”；只在等待的任务直接删掉（3.x 的“取消监控”，`:57-64`）。
  - **立即录**（面板的“开始录制”）建的任务 `autoRecord = false`（`features/live_play/record/record_panel.dart:252`）：这一场下播（平台说未开播）就结束、合成、“已保存”；“再录一次”保留任务原来的选择（`recordTaskAgain`，`record_actions.dart:69-73`）。3.x 留下的任务 `autoRecord` 为空，照 3.x：开了“自动断线重连”就下播后接着等。
  - **开播检测**（设置“开播检测”，默认关）：开着时每个“等待开播”的任务按“检测间隔”（默认 30 秒，10～300）查一次房间，开了“指数退避”时每次没开播间隔翻倍，最多“最大检测间隔”（默认 300 秒）；查到开播就开始录。关着时“等待开播”的任务不动，录制中心顶上提示“‘开播检测’关着……”和“打开”（`recorder_page.dart:526`、`:552`）；卡片菜单的“立即检测”随时可以查一次（`refreshTaskStatus`，只查、开播才开始，H02.1 修了 3.x 强制开始的问题）。
  - **名额和排队**：超过“最大同时录制任务数”（默认 3，1～10）的任务“排队中”，有空位按先后自动开始；两个任务开始至少隔 5 秒。界面上的名额只数准备中、录制中、整理文件中（重连中的不占），排队的任务在有空位时显示成“准备中”（`record_state.dart:44`）；“改上限”打开录制设置并定位到这一行（`openRecordLimit`，`record_actions.dart:22`）。
  - **启动时恢复**（设置“启动时恢复”，默认关）：应用启动时读回上次的任务列表；上次在录的（准备中、录制中、重连中、整理中）先把留下的分段合成 MP4，成功“已停止”、失败“录制失败”；开着“启动时恢复”时，上次没被用户停掉的排队、录制、重连、等待开播任务三个一批立即查房间，开播就录。关着时这些任务全部变“已停止”（照 3.x）。
- 内部怎么工作：

```text
等待开播的任务
  _schedulePoll（recorder.dart:1071）：开播检测关 或 _canPoll 为假 → 不排
    └ Timer(pollingDelay) → _poll（:1101，同一任务只有一个检测在跑）
        → _doPoll（:1117）：getRoomDetailForRefresh（没有就 getRoomDetail），最多 20 秒
            ├ 开播（isPlayableNow）→ retryCount 清零 → _start（:327）
            ├ 没开播 → waitingLive，pollFailures + 1
            └ 出错 → markFailure(stage: 'status')，pollFailures + 1
        → 结束后再 _schedulePoll（检测永远只有一个定时器）
_start：取前台服务（keepAlive.acquire）→ 状态 queued → RecordScheduler.enqueue
RecordScheduler._next（scheduler.dart:113）：运行数 < capacity() 且离上次开始 ≥ 5 秒 → _run
一场结束（H01 的 _doFinalize / _run 的 notLive 分支）：
  autoRecord == false 且录到过东西 → 合并 → 已保存
  否则 → waitingLive → _schedulePoll
```

- `_canPoll`（`recorder.dart:1057-1069`）要求：任务还在、不是用户停的、没有正在开始 / 停止 / 恢复 / 删除 / **整理文件（`finalizing`）**、不在队列也不在录。最后一条是 H01.5 要注意的坑（见“已知问题”）。
- 完成度（和 3.x 对照）：
  - 一致的：开播检测的开关、间隔、退避、最大间隔、20 秒超时，检测用刷新接口；开关打开时立即查所有等待的任务、关掉时取消定时器（3.x `_onPollingChanged`）；名额从设置读、每次决定都读（3.x 后台启动时读不到设置会退回 1，H01.1 修了）；两次开始隔 5 秒；启动时恢复的条件、三个一批、关着时任务变“已停止”；受限房间（付费、私密）不进检测循环（H01.1、升级 22-1）。
  - 确认过的改动：每个任务自己的“开播自动录”（A07.6 F2、F3：立即录的任务下播就结束；打开开播自动录时顺带打开开播检测）；“立即检测”只检测不强制开始（H02.1）；界面名额只数真正占位的状态（A10.1）。
  - 还缺：见“已知问题”第 1、2 条（下播后不合并）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_record/lib/src/scheduler.dart`（150 行） | `RecordCancelToken`（`:9`，取消一次运行，回调晚设也会执行）；`RecordScheduler`（`:49`）：`enqueue`（`:65`，同一 id 只排一次）、`cancel`（`:73`，从队列删或取消运行、最多等 20 秒）、`clear`、`isRunning`/`isQueued`/`runningCount`/`queuedCount`、`_next`（`:113`，名额和 5 秒间隔）、`_start`（`:131`，运行结束自动接下一个） |
| `packages/live_record/lib/src/recorder.dart`（1362） | 本子分类的部分：构造时建 `RecordScheduler(capacity: () => settings().maxTaskCount)`（`:144`）；`addTask`（`:230`，`startImmediately: false` 时直接“等待开播”）；`setTaskOptions`（`:260`）；`monitorTask`（`:272`，停了的任务重新等）；`_start`（`:327`，取前台服务后入队）；`_canPoll`（`:1057`）、`_schedulePoll`（`:1071`）、`_stopPolling`（`:1093`）、`_poll`（`:1101`）、`_doPoll`（`:1117`）、`refreshTaskStatus`（`:1157`）、`settingsChanged`（`:1170`）；`restore`（`:1203`）、`_recover`（`:1292`）；`_endsAfterBroadcast`（`:773`） |
| `packages/live_record/lib/src/policy.dart`（61） | `pollingDelay`（`:6-17`：基数 1～86400 秒，退避时按失败次数翻倍、不超过最大值） |
| `packages/live_record/lib/src/task.dart`（647） | `RecordStatus.queued`、`waitingLive` 和 `order`（`:37`）；`RecordTask.autoRecord`（`:377`，空 = 照 3.x 跟“自动断线重连”）、`lastLiveCheckAt`、`retryCount`；`toJson` 写 `autoRecord`（`:534`，只在设过时写） |
| `packages/live_record/lib/src/settings.dart`（109） | `enablePolling` 默认关、`liveCheckInterval` 30（10～300）、`enableBackoff` 关、`maxCheckInterval` 300（300～3600）、`autoStartOnBoot` 关、`maxTaskCount` 3（1～10）（`:14-43`） |
| `apps/pure_live/lib/shared/record/record_actions.dart`（90） | `openRecordLimit`（`:22`）、`enableRecordPolling`（`:27`）、`setAutoRecord`（`:38`，开：先开检测，再建任务 / 设选择 / `monitorTask`；关：录着的设选择，只在等的删除）、`recordTaskAgain`（`:69`） |
| `apps/pure_live/lib/shared/record/record_state.dart`（169） | `recordCardState` 的排队规则（`:44`）、`recordSlotsInUse`（`:57`）、`recordBusy`（`:65`）、`autoRecordOn`（`:70`，等待开播的一定算开；停了、失败、已保存的算关；其余看 `autoRecord ?? true`） |
| `apps/pure_live/lib/app/recording.dart`（574） | `AppRecording.start()`（`:422`）：读设置、`recorder.settingsChanged()`（`:431`，设置一变就转给录制器）、`restore`（`:436`） |
| `apps/pure_live/lib/features/recorder/recorder_page.dart`（637） | “开播检测关着”提示：`pollingOff`（`:334`）、只在有等待开播的任务时显示（`:526`）、`_PollingOffBanner`（`:552`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_record/test/recorder_test.dart` 的 `an offline room waits for the live check`（`:210`） | 未开播的房间转“等待开播” |
| 同上 `开播自动录: off finishes after the broadcast, on waits again; on for a stopped task resumes`（`:284`） | 关：下播后合成、“已保存”；开：下播后“等待开播”；停了的任务 `monitorTask` 后重新等、“立即检测”记下检测时间 |
| 同上 `the queue holds tasks above the concurrency limit`（`:315`） | 名额 1 时第二个任务“排队中”，第一个停了第二个开始 |
| 同上 `restore joins an interrupted recording and drops unsupported platforms`（`:230`） | 启动时合并上次在录的任务、丢掉不支持的平台 |
| `packages/live_record/test/ffmpeg_test.dart` 的 `reconnect, polling and lease timing follow 3.x`（`:111`） | `pollingDelay` 的退避和上限 |
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart` | “开播检测关着”提示和“打开”、卡片菜单的“开播自动录” |

## 3.x 基线

- 排队：`git show v3.2.11:lib/recorder/ffmpeg/ffmpeg_scheduler.dart`：`FFmpegScheduler`（`:8`），5 秒间隔（`:9`），名额从 `Get.find<RecordSettingsController>()` 读、没注册时退回 1（`:24-31`）。
- 检测：`lib/recorder/pages/recorder/recorder_controller.dart`：`addTask`（`:693`，`startImmediately: false` 直接等待开播）、`_schedulePoll`（`:1295`）、`_pollTask`（`:1336`，刷新接口 `:1353-1355`）、`refreshTaskStatus`（`:1392`）、`_onPollingChanged`（`:1399-1416`）、`ever(enablePolling)`（`:129`）；`lib/recorder/services/recorder_continuation_policy.dart` 的 `pollingDelay`（`:42`）、`shouldMonitorAfterExit`（`:4`）。
- 下播：`recorder_controller.dart:962-967`：取流说未开播 → 等待开播，**不合并**（4.x 同，见已知问题）。
- 启动时恢复：`recorder_controller.dart:1470-1566`（`_restoreAndAutoPoll`：非结束状态全变“已停止”`:1504`，开了“开机自启”才三个一批检测 `:1547-1566`）；`lib/common/global/initial_services.dart:80-89`（只有开了“开机自启”且有任务才在启动时建录制器；4.x 启动时总是建，空闲时不跑 FFmpeg）。
- 直播间：`lib/modules/live_play/widgets/button/record_action_button.dart`：“添加监控 / 取消监控”（`:127`、`:295-309`），`addTask(startImmediately: false)`（`:181`），取消是 `unRecorder`（`:198`）。4.x 的“开播自动录”是同一件事，多了“这一场录完就停”的选择。
- 必须保留的操作习惯：无专门条目（[specs/UI.md](../../specs/UI.md) 附录 A 不涉及录制）；3.x 的“取消监控”删除只在等待的任务，4.x 照做。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 主播下播、平台说“未开播”时，开着开播自动录的任务直接转“等待开播”，**这一场的分段不合并**；下一场开始时也不合并（`_start` 不清待合并），要等用户停止才一起合成。一直挂着自动录的任务一直没有 MP4 | `packages/live_record/lib/src/recorder.dart:495-501`（`_run` 的 `notLive` 分支）；3.x `recorder_controller.dart:962-967` 同 | 开播自动录的用户每场都要手动停一次才拿到录像；分段一直占空间 | [H01.5](../H01-录制核心/H01.5-主播下播后不再无限快速重试/README.md) c3（本轮写任务书时补进去：下播的两条路——重试用完、平台说未开播——都先合并再等） |
| 重试用完转“等待开播”时同样不合并 | `recorder.dart:906-914` | 同上 | H01.5 c3 |
| `_doFinalize` 合并之后调 `_schedulePoll`，但这时 `rt.finalizing` 还没清，`_canPoll` 为假，检测排不上 | `recorder.dart:749-753`、`:1057-1069` | 现在直播录制走不到这个分支（直播的“正常结束”只有用户停止），是潜在的坑；H01.5 让下播后先合并再等，会踩到 | H01.5 c3（检测改在 `finalizing` 结束后排） |
| 关着“启动时恢复”时，重启应用后所有“等待开播”的任务变“已停止”，开播自动录跟着变关，没有提示 | `recorder.dart:1236`（`if (!task.status.isFinished) task.status = RecordStatus.stopped`）、`:1272`；`record_state.dart:71` | HyperOS 杀掉应用或手机重启后，用户以为还在等开播，其实不等了 | 照 3.x，不做；要改（例如打开开播自动录时提示“启动时恢复”）先在 [V01](../../V-需求和反馈/V01-新功能提议/README.md) 提议 |
| 等待开播时没有前台服务（只在真正录的时候持有），应用长时间在后台可能被系统冻结或杀掉，检测就停了 | `recorder.dart:327-360`（`_start` 才取 `keepAlive`）；`_schedulePoll` 用普通 `Timer` | 关屏几小时后主播开播可能录不到 | 没在真机上看过（[真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 3 节第 5 条没做）；建议并入 [H01.4](../H01-录制核心/H01.4-录制余项/README.md) 阶段 1 顺带看，有问题再开任务 |
| 检测出错时任务记“最近失败（状态）”，但还是“等待开播”、继续检测 | `recorder.dart:1145-1153` | 卡片上同时有“等待开播”和一条失败说明，可能让人以为停了 | 照 3.x（`recorder_controller.dart` 同样 `markFailure`），不做 |
| 功能清点 F-REC-04（重连、重试、退避、开播检测）、F-REC-05（启动时恢复）标“完成”，但真机清单第 3 节第 4、5 条没有结果 | [inventory/FEATURES.md](../../inventory/FEATURES.md) 第 11 节 | 按 D-029：逻辑全在纯 Dart、有单元测试，可算完成；后台检测靠系统 | 第 4 条随 H01.5 的真机步骤 6 看；第 5 条见上一行 |

## 相关决定和规范

- D-018：3.x 的设置键名和含义不变（`enable_polling`、`liveCheckInterval`、`enable_backoff`、`maxCheckInterval`、`auto_start_on_boot`、`maxTaskCount`）；任务 JSON 的 `autoRecord` 只加不改，3.x 读到会忽略。
- D-017：测试定时器至少 1 秒（`recorder_test.dart` 现有的 50 毫秒录制时长不符，见 [H01](../H01-录制核心/README.md) 已知问题）。
- 界面决定：A07.6 的 F2（打开开播自动录时顺带打开开播检测）、F3（立即录的任务下播就结束）；A10.1 的名额显示。

## 测试和验证

- 自动：`cd packages/live_record && dart test`（上表 5 个用例覆盖本子分类）；`cd apps/pure_live && flutter test test/features/recorder`。缺的：没有“开播检测开着、等到开播后自动开始”的端到端用例（H01.5 测试第 4 条会补）；没有启动时恢复且开着“启动时恢复”的用例（只测了合并和丢掉不支持的平台）；没有 5 秒开始间隔的用例（构造时可传 `startGap`，测试都传了 0）。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 3 节第 5 条（给未开播的关注加“等开播”、重启应用）还没做。

## 路线

1. H01.5（第一档）：下播后的两条路都先合并再等开播；检测在整理文件结束后排上。改的是本子分类和 H01 共用的 `recorder.dart`，H01.5 做完后回来更新本页的“已知问题”。
2. 真机：第 3 节第 5 条和“后台长时间等待开播”随 H01.4 一起看；不通过时在本子分类开任务。
3. 新想法（按优先级排队、定时录制、只录某个时段）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [H 录制](../README.md)。

- 代码：`packages/live_record`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
