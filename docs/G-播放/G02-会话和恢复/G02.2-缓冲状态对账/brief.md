# G02.2 缓冲状态对账：任务书

## 背景

- 来源：上游对照 [W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)（2026-10-03）“4.x 也有的问题”表第 4 行：media_core `44710e1`、`2edc721` 修了“缓冲结束的事件丢了时，画面在动但状态一直是缓冲”；4.x 的 `session.dart` `_onFrame` 只记时间不对账，12 秒后会被缓冲看门狗当成卡住去重连。
- 现象：直播正常在播（画面在动、声音在响），画面中间却一直转圈（A07.7 的缓冲状态）；约 12 秒后画面闪一下、重新加载（会话刷新地址或换线），聊天区可能出现“正在重连（第 1 次）”。复现条件不确定：取决于 mpv 的 `core-idle`、`paused-for-cache` 两个属性的事件顺序，偶发。
- 为什么现在做：第二档；改动小（一个文件为主），能消掉一类“莫名其妙重连”。和 G03.1（第一档）都改 `packages/live_player/lib/src/session.dart`，先做本任务，G03.1 的计时点在它之后加。
- 已经做过的：G02.1（会话，`4e8cd6c67`）；B02（`50143b27e`，会话说出恢复次数，`ReconnectWatch` 只信它）。

## 目标和验收

1. 会话处于“缓冲中”、用户想播、引擎在播时，直播的播放位置前进 ≥1 秒（媒体时间），或 1 秒内收到 ≥10 个画面帧（Windows），状态在下一个事件里变成 `playing`，缓冲看门狗被取消。
2. 位置不前进时，缓冲看门狗照旧在 12 秒后报 `buffering_stall_timeout` 并恢复（现有用例“buffering that never ends is recovered once its first deadline passes”仍然通过）。
3. 用户暂停后、来源换代后、点播拖动时，位置事件不改变状态。
4. 心跳只把“缓冲中”改成“播放中”，从不反过来；每秒几十个位置事件不产生多余的状态通知（只在真正对账那一次 `_emit`）。
5. `PlaybackState.recoveryCause` 在恢复期间是触发它的错误代码，恢复结束（回到播放中、用户重开、发布错误）后为空；应用日志里每次恢复一行，带次数和原因。
6. Android 画面停住检测的评估结论写进 `record.md`（做了，或不做的原因和以后的条件）。

## 现状（读代码得出）

- 事件入口 `session.dart:556-587` `_onEvent`：
  - `EngineBuffering` → `_buffering = buffering`，放行时 `_onBuffering`（`:642-659`）：`true` 时取消画面看门狗和预算计时、发 `buffering`、开缓冲看门狗；`false` 时取消缓冲看门狗，在播就 `_onPlaying(true)`。
  - `EnginePosition` → 只有点播才更新 `position`（`:572-573`），直播丢掉。
  - `EngineFrame` → `_onFrame`（`:679-682`）：`_lastFrame = clock.now()`、`_armFrameWatchdog`，不看 `_buffering`。
- 缓冲看门狗 `_armBufferingWatchdog`（`:687-701`）：定时器 12 秒（`SessionTimings.bufferingStall`），到点 `if (!_current(session) || !_buffering || !_wantPlaying) return;` 否则 `_handleError(buffering_stall_timeout)` → `_recover` → `_tryRefresh`（刷新地址、重开同一线路）。所以只要 `_buffering` 卡在 `true`，就一定会重连。
- `_onPlaying(true)`（`:609-628`）在 `_buffering` 为真时也只发 `buffering`、开缓冲看门狗——“在播”不能把状态拉回来。
- 缓冲标志从哪来：`MpvEngine._bind`（`mpv_engine.dart:115-120`）转发 media_kit 的 `stream.buffering`；media_kit 的分支里 `core-idle` 为 1 时置真（受 `isBufferingStateChangeAllowed` 限制）、为 0 时置假，`paused-for-cache` 直接置真或假（`third_party/media_kit/lib/src/player/native/player/real.dart:1401-1427`），`START_FILE` 和结束时置假（`:270-285`、`:1790-1800`）。两个属性先后到达时最后一个事件说了算，这是“标志卡住”的根因线索（要用日志确认，见阶段 1）。
- Android 的 `MpvEngine.reportsFrames` 是假（`mpv_engine.dart:99-100`，只有 Windows 有分支的 `frameRevision`），所以 Android 上 `_onFrame` 根本不会被调用——**上游说的“画面帧”在 Android 上要换成“位置”**。`MpvEngine` 对所有来源都转发位置（`mpv_engine.dart:139`）。
- 状态里没有恢复原因：`PlaybackState.error` 只在 `status == error` 时保留（`state.dart:188-192`）；应用里没有任何地方记录恢复（`room_controller.dart` 的 `developer.log` 只记详情、弹幕等失败，`developer.log` 在 profile/release 里也到不了 logcat）。
- 上游参考：本机 `~/ref/media_core` 当前代码 `packages/media_core_live/lib/src/live_playback_pipeline.dart:189-228`（`_reconcileMirroredPlayback`：每个位置事件对账，只升不降；`_seedPlaybackState`：引擎接上前已在播时补发）。两个提交的具体改动用 `git -C ~/ref/media_core show 44710e1`、`git -C ~/ref/media_core show 2edc721` 看。

## 3.x 基线

- `git show v3.2.11:lib/player/core/player_manager.dart`：缓冲看门狗 `_scheduleBufferingStallRecovery`（`:2610-2638`），一次缓冲一个 12 秒期限，“Playing/paused notifications do not prove media arrived”，不被通知重置；到点还在 `_loadingSubject` 就报 `buffering_stall_timeout`。3.x 同样没有按位置或画面对账。
- 打开成功后按适配器真实状态补发一次（`:1920-1938`）——4.x 的 `MpvEngine.open` 末尾已经做了同样的事。
- 要保留：缓冲看门狗不被重复的“缓冲中”通知重置；用户暂停不被任何看门狗恢复；12 秒的时限。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层：`live_player` 的会话不引 Flutter）。
3. 本文件夹的 `README.md`；`docs/G-播放/G02-会话和恢复/README.md`（会话怎么工作）；`docs/G-播放/G02-会话和恢复/G02.1-播放器/record.md`（保留的 3.x 行为）。
4. 代码：`packages/live_player/lib/src/session.dart`（全文）、`state.dart`、`engine.dart`、`mpv_engine.dart`；`packages/live_player/test/session_test.dart`、`test/support/fake_engine.dart`；`apps/pure_live/lib/features/live_play/logic/room_controller.dart`、`reconnect_watch.dart`。

## 范围

- 可以改：`packages/live_player/lib/src/session.dart`、`state.dart`（只添加字段）、`mpv_engine.dart`（只为 c5 读属性时）、`packages/live_player/test/`；`apps/pure_live/lib/features/live_play/logic/room_controller.dart`（只加恢复日志）；本任务文件夹的 `record.md`。
- 不能改：其他组的界面和逻辑（A07 的转圈和重连提示怎么画不动）；`SessionTimings` 的默认值（12 秒、18 秒等，属于 G03.1 按数字决定）；`third_party/media_kit`（根因修在分支里另开任务）；`PlaybackState` 现有字段的含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 进度心跳、c2 看门狗兜底、c3 排除情况、c4 恢复原因和日志 | `session.dart`（`_onEvent` 的 `EnginePosition`、`EngineFrame` 分支，新私有方法 `_onProgress`，`_armBufferingWatchdog` 的到点判断，`_recover`/`_retryRound` 设 `recoveryCause`）；`state.dart`（`recoveryCause`、`copyWith`）；`room_controller.dart`（听 `session.states`，`recovery` 变大时用 `AppLog.instance.info('playback', ...)` 写进应用日志（日志页能看、能导出），并 `debugPrint` 同一行（logcat 的 `I/flutter` 能看到；`debugPrint` 进应用日志是 debug 级，默认不保存，所以两样都要））；`session_test.dart` | 新用例全部通过、改之前第一条会失败；`packages/live_player` 和 `apps/pure_live` 的全部测试通过；门禁通过 |
| 2 | c5 评估 Android 画面停住检测（只在开销小时实现：每 2 秒最多读一次 mpv 属性，且只在播放中、画面可见、非纯音频时读） | `mpv_engine.dart`（如果实现）、`session.dart`、`record.md` | `record.md` 写清结论和数据（读属性的耗时、K90 上的行为）；实现了的话有测试 |

阶段 2 很小，可以和阶段 1 一起合并；登记表现在没有分阶段，如果分两次合并，先在登记表加 `stages`。

实现要点：
- 对账只在 `_accepting`（来源代对）且 `_wantPlaying && _playing && _buffering` 时判断；记下进入缓冲时的位置（第一个位置事件）和墙钟时间（`clock.now()`），位置增量满足 `1 秒 ≤ 增量 ≤ 墙钟增量 + 2 秒` 才算前进（排除拖动和开头的时间戳跳变）。
- 画面帧（Windows）：缓冲开始后计数，1 秒内 ≥10 帧算前进；纯音频时不计。
- 对账就是 `_buffering = false; _onBuffering(false, session);`，不另写一套状态切换。
- 位置事件每秒可能几十个：热路径里只做比较，不分配对象、不 `_emit`。
- 新状态字段走 `copyWith`，`recoveryCause` 在 `recovery == 0` 时一律清空（`_onPlaying` 发 `recovery: 0` 的地方、`pause`、`stop`、`_publishError`）。

## 测试

- 修 bug，先写会失败的用例（`packages/live_player/test/session_test.dart`，新 `group('G02.2 buffering reconciliation')`）：
  - `positions advancing during a stuck buffering bring playing back; no reopen after 12 s`：假引擎打开后发 `EngineBuffering(true)`、`EnginePlaying(true)`，每 200 毫秒发一个前进 200 毫秒的 `EnginePosition`，推 13 秒：状态 `playing`、`engine.opens.length == 1`。改之前：13 秒时 `opens.length == 2`（被刷新重开）。
- 其他用例：
  - `positions that stand still keep the buffering deadline`：位置不变，12 秒后恢复（`opens.length == 2`，`recoveryCause == 'buffering_stall_timeout'`）。
  - `presented frames during buffering bring playing back (Windows)`：`reportsFrames = true`，1 秒内发 12 个 `EngineFrame`。
  - `a user pause is not undone by positions`：`pause()` 后发前进的位置，状态保持 `paused`、`calls` 里没有 `play`。
  - `a seek jump is no progress`：点播，位置一次跳 60 秒，状态保持缓冲。
  - `recoveryCause clears once playing again`：恢复后发 `playing()`，`recoveryCause` 为空、`recovery == 0`。
- 应用：`apps/pure_live/test/features/live_play/live_play_room_test.dart` 加一个：会话恢复时应用日志多一行 `playback: recovering #1 <代码>`。
- 定时器都用 `fake_async`，时限按 `SessionTimings` 默认值；不访问真实平台。

## 真机验证（维护者在 K90 上做）

准备：装本任务分支的 profile 包（`com.mystyle.purelive.v4dev`）；设置 → 数据 → 日志管理里打开“启用本地日志”（`enableLocalLog`），结束后在同一页导出；或者直接看 `adb -s <K90 的 adb 地址> logcat -s flutter`。

| 步骤 | 期望 |
|---|---|
| 1. 改之前的包：哔哩哔哩、斗鱼、虎牙、抖音各开一个直播间，每个连续播 15 分钟，不碰手机；记下 `logcat` 里 `buffering_stall_timeout` 的次数（改之前没有日志行时，数画面上“正在重连”出现的次数） | 得到基线（可能是 0：偶发问题） |
| 2. 本任务的包重复第 1 步 | 日志里每次恢复都有一行 `playback: recovering #N <代码>`；`buffering_stall_timeout` 不多于基线；没有“画面在动却一直转圈”的时候 |
| 3. 播放中关 Wi-Fi 10 秒再打开（S02 清单第 1 节第 3 条） | 断网时转圈，约 12 秒后出现“正在重连（第 1 次）”，日志原因是 `buffering_stall_timeout` 或网络错误；联网后恢复播放、转圈消失 |
| 4. 播放中按暂停，等 30 秒，再继续 | 暂停期间状态不变、不重连；继续后几秒内恢复播放 |
| 5. 网络电视播一个回放节目，拖动进度条 | 拖动后短暂转圈，出画面后转圈消失；没有误报重连 |

## 风险和注意

- **误判真缓冲为播放中**：mpv 在 `paused-for-cache` 时 `time-pos` 不前进，所以“位置前进 ≥1 秒”可靠；但开头第一个位置可能是流的起始时间戳，必须以“进入缓冲后的第一个位置”为基准，并用墙钟上限排除跳变。
- **和 G03.1 冲突**：G03.1 第一阶段要在 `session.dart` 的打开路径加计时点。本任务合并后再开 G03.1 的代码阶段；如果并行，`_openSource` 和 `_onEvent` 两处必然冲突。
- **多画面**：每格一个会话，位置事件更多；对账逻辑必须是常数时间。
- **不要动缓冲看门狗“不被重复通知重置”的规则**（3.x 行为，有现成用例）。
- 根因如果在 media_kit 分支（缓冲标志本身卡住），本任务不修分支，在记录里写清日志证据，建议开 G01 的任务。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/G02.2` 或本机工作区；提交信息以 `[G02.2]` 开头（英文）；不推 master。
- 提交前：`packages/live_player` 和 `apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；根目录 `python3 tools/gate/check_ui_structure.py`、`python3 tools/gate/check_deps.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪些用例写了、哪些通过）、更新登记表的 `next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；对账的条件（阈值）和理由；c5 的结论；测试数量（新增、改动）；改了哪些文件；新加的状态字段和日志格式；要在真机上看的；需要维护者决定的（例如根因在分支里时要不要另开任务）；可能冲突的文件（`session.dart`、`room_controller.dart`）。
