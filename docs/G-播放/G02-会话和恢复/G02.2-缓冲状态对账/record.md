# G02.2 缓冲状态对账：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；代码、测试和本记录一个提交（`[G02.2]`）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 进度心跳 | 做了 | 接在 G02.3 的位置事件上（`_onEvent` 的 `EnginePosition` 分支先走 G02.3 的 `_onPosition`，缓冲中再走 `_onBufferingPosition`），没有另做一套；点播也对账（同样会被卡住的标志拖到 12 秒重开），拖动的跳变用墙钟上限排除 |
| c2 看门狗兜底 | 做了 | 缓冲看门狗到点先用同一个判断（`_progressed`）对账一次 |
| c3 不对账的情况 | 做了 | 用户暂停（`_wantPlaying` 假）、来源换代或打开中（`_accepting` 假）、断网（`_offline`）、纯音频的画面帧 |
| c4 恢复原因 | 做了 | `PlaybackState.recoveryCause`；应用每次恢复一行 `playback: recovering #N <代码>`（应用日志 info 级 + `debugPrint` 给 logcat） |
| c5 Android 画面停住 | 评估，不做 | 见“c5 结论” |
| c6 根因 | 只记录 | 加了诊断行，K90 上还没抓到，见“根因” |
| 先写失败的测试 | 做了 | 8 个会话测试里 5 个改前失败，应用 1 个改前失败（见“测试”） |

验收：

| 验收 | 结果 |
|---|---|
| 1. 位置前进 ≥1 秒（≤ 墙钟 + 2 秒）或 1 秒内 ≥10 帧 → 这次事件里变成 `playing`、取消缓冲看门狗 | 自动测试过 |
| 2. 位置不走时 12 秒后照旧 `buffering_stall_timeout` | 自动测试过；原用例“buffering that never ends …”照旧通过 |
| 3. 暂停后、换代后、点播拖动时位置不改状态 | 自动测试过 |
| 4. 只升不降；位置事件不多发状态 | 自动测试过：对账那一次发一个 `playing`，其余位置事件一个都不发 |
| 5. `recoveryCause` 恢复期间有、结束后空；应用日志每次恢复一行 | 自动测试过 |
| 6. 根因确认 | 没确认：要 K90 上的诊断行（见“真机上要看的”） |
| 7. Android 画面停住检测的结论 | 写了（不做，条件见下） |
| 8. 测试和门禁 | 通过 |

## 3.x 基线

- `v3.2.11:lib/player/core/player_manager.dart:2610-2638`：一次缓冲一个 12 秒期限，不被重复通知重置，“在播”不算媒体到达；3.x 同样只信适配器的缓冲标志，没有按位置或画面对账，也有这个问题。这些规则都保留了（缓冲看门狗本身没改，只在到点时多一次对账）。

## 根因

- 会话层（修在这里）：直播只信引擎的缓冲标志。G02.3 之后，位置事件已经进了会话（`packages/live_player/lib/src/session.dart` 的 `_onPosition`），但只在 `!_buffering` 时把状态补回播放（原 `:799` `if (waited && _playing && !_buffering)`）；标志卡在真时，位置一直在走，缓冲看门狗到点照样只看 `_buffering`（原 `:809`），报 `buffering_stall_timeout` → `_recover` → 刷新地址重开。测试“positions advancing during a stuck buffering …”改前在第 13 秒有 2 次打开（换到线路 2）。
- 引擎层：`MpvEngine._bind` 原样转发 media_kit 的 `stream.buffering`，打开后补发当时的 `player.state.buffering`（`mpv_engine.dart:190`）。
- media_kit 分支（根因候选，没改）：`third_party/media_kit/lib/src/player/native/player/real.dart` 里 `MPV_EVENT_START_FILE` 置真（`:1374`），`core-idle` 为 0 或 `paused-for-cache` 为 0 时置假（`:1402-1427`），打开时允许位设假（`:240`）吞掉打开后第一个 `core-idle=1`；mpv 只在属性变化时通知，`START_FILE` 后两个属性都没再变化，标志就停在真。
- 证据：K90 上还没抓到卡住的现场。本任务在 `MpvEngine` 加了诊断：缓冲标志为真 3 秒后还是真，就读一次 `core-idle`、`paused-for-cache`、`time-pos`，写一行 `mpv: buffering for 3 s: core-idle=… paused-for-cache=… time-pos=… (N us)`（只在 debug、profile 构建；`debugPrint`，应用日志里是 debug 级）。判读：如果这行里 `core-idle=no`、`paused-for-cache=no` 而 `time-pos` 在两行之间前进，就是分支的标志卡住，建议在 G01 开任务修分支（例如 `START_FILE` 之后主动读一次两个属性的当前值）；本任务的对账保留作兜底。

## c5 结论：Android 画面停住检测，这次不做

- 原因：
  1. 开销没法在本机量：读 mpv 属性要真机（这次不碰 adb）。上面的诊断行顺带记下连读三个属性的耗时（`N us`），真机上看到这个数后再定。
  2. 收益变小了：G02.3 已经按位置判断直播流，解复用或网络卡住时 `time-pos` 不走，4 秒内出“正在重连”、12 秒恢复；Android 上剩下的只有“声音在走、画面冻住”（解码器或输出面卡住）。这类问题目前没有用户反馈。
- 以后做的条件：有用户反馈冻画面（声音正常），或诊断行显示三个属性的读取 <1 毫秒。做法照 README c5：播放中、画面可见、非纯音频时每 2 秒读一次 `estimated-frame-number`，10 秒不变当作画面停住，走现有的 `video_frame_stall_timeout`。

## 改了哪些文件

- `packages/live_player/lib/src/session.dart`：
  - 对账：`_onBufferingPosition`（`:852`）、`_progressed`（`:875`）、`_reconcile`（`:886`，就是 `_buffering = false; _onBuffering(false, …)`，不另写状态切换）、`_reconcilable`（`:836`）；`_onFrame`（`:819`）数缓冲中的画面帧；
  - 基准在进入或离开缓冲、打开新来源时清掉（`_resetProgress`）；
  - 缓冲看门狗到点先对账（`:921`）；
  - 阈值是类常量：`bufferingProgress`（1 秒）、`bufferingProgressSlack`（2 秒）、`bufferingProgressFrames`（10）；`SessionTimings` 默认值没动；
  - 恢复原因：`_recover`、`_noticeStall`、`_retryRound`、`_probe`、断网（`networkLostCode`）、恢复中重开的来源都带上 `recoveryCause`。
- `packages/live_player/lib/src/state.dart`：`recoveryCause`（只添加）；`copyWith` 在 `recovery` 为 0 时一律清空它。
- `packages/live_player/lib/src/mpv_engine.dart`：`_watchBuffering`（诊断行，release 不做）。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`_logRecovery`（`:325`），`start` 里订阅会话状态，恢复次数变大时写一行。

阈值的理由：mpv 在 `paused-for-cache` 时 `time-pos` 不走，前进 1 秒的媒体时间足以说明数据在到；以“这次缓冲里看到的第一个位置”为基准、位置增量不超过墙钟增量 + 2 秒，排除流的起始时间戳、拖动和时间戳跳变（跳了就以新位置重新计）。画面帧 1 秒 10 帧，低于任何正常直播的帧率，又远高于偶发的一两帧。

## 新设置、翻译键、门禁基线

- 没有新设置、没有新翻译键、没有改门禁基线、没有新依赖。
- 新状态字段 `PlaybackState.recoveryCause`；新日志格式 `playback: recovering #<次数> <代码>`（不带地址和请求头）；诊断行 `mpv: buffering for 3 s: …`。

## 测试

- `packages/live_player/test/session_test.dart` 新增 8 个（`G02.2 buffering reconciliation` 组）：位置在走补回播放且 13 秒内不重开、只发一次状态（改前失败）；位置不走 12 秒照旧恢复、原因 `buffering_stall_timeout`（改前失败：没有原因）；Windows 画面帧（改前失败）；纯音频的画面帧不算；用户暂停不被位置改掉；点播拖动跳 60 秒不算、之后正常前进算（改前失败）；旧代的位置不算；恢复结束 `recoveryCause` 清空（改前失败）。改前 5 个失败、3 个守住原有行为。
- `apps/pure_live/test/features/live_play/live_play_controller_test.dart` 新增 1 个：每次恢复一行 `recovering #N <代码>`，格式化后是 `[INFO] playback: recovering #1 transport`（改前失败）。
- 全部通过：`live_player` 49、`apps/pure_live` 920；`dart format`、`dart analyze --fatal-infos`、`check_ui_structure.py`、`docs.py --check` 通过。

## 真机上要看的

K90，profile 包（`com.mystyle.purelive.v4dev`），`adb -s 192.168.1.2:5555 logcat -s flutter`：

1. 哔哩哔哩、斗鱼、虎牙、抖音、快手各连续播 15 分钟：每次恢复 logcat 有一行 `playback: recovering #N <代码>`；数 `buffering_stall_timeout`，不多于改前；没有“画面在动却一直转圈”。
2. 出现 `mpv: buffering for 3 s: …` 的行全部抄进本记录（两个属性的值、`time-pos` 是否在走、耗时），据此定 c6、c5。
3. 播放中关 Wi-Fi 10 秒再开：转圈，几秒后“正在重连（第 1 次）”，日志原因是 `playback_stall_timeout`、`buffering_stall_timeout` 或 `network_lost`；联网后恢复、转圈消失。
4. 暂停 30 秒再继续：暂停期间不重连，继续后几秒内播放。
5. 网络电视的回放拖动进度条：短暂转圈，出画面后消失，没有误报重连。

## 和其他任务的关系

- G03.1、G01.2 也改 `session.dart`；本任务改了 `_onEvent`、`_onFrame`、`_openSource`、缓冲看门狗和几处 `_emit`。
- 应用日志里的恢复原因可以直接给 G03.1 的测量用。

## K90 复查（2026-10-08）

- 哔哩哔哩、虎牙、斗鱼各连续播 15 分钟：日志里 0 次 `playback: recovering`，没有“画面在动却一直转圈”；暂停 10 秒再继续、进出全屏、换线路都没误报重连（A07.10、G02.3 复查）✓。抖音、快手的 15 分钟和 `mpv: buffering for 3 s` 行没看到（没出现）。
