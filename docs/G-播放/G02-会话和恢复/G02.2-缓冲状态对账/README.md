# G02.2 缓冲状态对账：画面帧在走时补回“播放中”，不再被当成卡住去重连

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：上游对照 [W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)（2026-10-03）“4.x 也有的问题”：media_core 提交 `44710e1`、`2edc721` 修了“缓冲结束的事件丢了时，画面在动但状态一直是缓冲”；4.x 同样有这个问题
- 旧编号：T04b.2
- 相关：决定 D-001、D-017、D-027；前置 [G02.1](../G02.1-播放器/README.md)；和 [G03.1](../../G03-起播速度和弱网/G03.1-起播速度和弱网/README.md)、[G01.2](../../G01-引擎/G01.2-高通硬解评估/README.md) 都改 `session.dart`（先做本任务）；界面上的转圈和重连提示 A07.7、A07.10；任务书 [brief.md](brief.md)

## 目标

- 正常播放中，即使引擎的“缓冲结束”通知丢了（或缓冲标志卡在“真”），只要播放位置或画面在走，会话就把状态补回“播放中”：画面上不再有压在流畅画面上的转圈，12 秒后也不会被缓冲看门狗当成卡住去刷新地址、重连。
- 真的卡住（位置不走）时，缓冲看门狗照旧 12 秒后恢复，行为同 3.x。
- 每次恢复的原因写进应用日志，真机上能数出“因为缓冲超时而重连”的次数，改前改后对比；G03.1 的测量也用它。
- 评估 Android 上的画面停住检测（Android 的引擎不报画面帧）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 缓冲状态从哪来 | 适配器的 `buffering` 流（`lib/player/adapters/media_kit_adapter.dart:692`） | `MpvEngine._bind` 把 media_kit 的 `stream.buffering` 原样转成 `EngineBuffering`（`packages/live_player/lib/src/mpv_engine.dart:115-120`）；打开后再补发一次当时的 `player.state.buffering`（`:190`） | 不变；会话另外用位置和画面兜底 |
| 缓冲看门狗 | `lib/player/core/player_manager.dart:2610-2638`：一次缓冲一个 12 秒期限，到点还在“加载”就报 `buffering_stall_timeout` | `packages/live_player/lib/src/session.dart:687-701`：同 3.x，到点只看 `_buffering`（`:691`） | 到点前如果位置或画面在走，先对账，不报错 |
| “在播”能不能结束缓冲 | 不能（“Playing/paused notifications do not prove media arrived”） | 不能：`_onPlaying(true)` 在 `_buffering` 为真时仍发缓冲、开缓冲看门狗（`session.dart:616-618`） | 不变（“在播”仍不算证据），改为位置前进才算 |
| 画面帧 | Windows 的帧进度，只用来判断画面停住 | `_onFrame`（`session.dart:679-682`）只记时间、重排画面看门狗；Android 不报画面帧（`mpv_engine.dart:99-100`） | 画面帧（Windows）和位置前进（所有平台）都能把缓冲补成播放 |
| 位置事件 | 直播不用 | `session.dart:572-573`：只有点播才用 `EnginePosition`，直播的丢掉；`MpvEngine` 对所有来源都转发（`mpv_engine.dart:139`） | 直播也用来对账（不写进状态的 `position`） |
| 打开后的状态 | 打开成功后按适配器的真实状态补发一次（`player_manager.dart:1920-1938`） | `MpvEngine.open` 末尾补发（`mpv_engine.dart:186-191`） | 不变 |
| 恢复原因 | `developer.log` 有记录 | 会话只说次数（`state.dart:119` 的 `recovery`），错误只在出错时保留（`:187-188`）；应用不记录 | 状态带上恢复原因（只添加），应用写进日志 |
| Android 画面停住 | 没有（3.x 只有 Windows 的帧进度） | 没有 | 评估，开销小就做 |

上游的做法（本机 `~/ref/media_core` 的 `packages/media_core_live/lib/src/live_playback_pipeline.dart`）：`_reconcileMirroredPlayback`（`:200` 起）把每个位置事件当心跳，镜像状态说“没在播”而引擎说“在播”时补成播放中，**只升不降**（降为暂停只走用户命令）；`_seedPlaybackState`（`:221`）在引擎接上前已经在播时补发一次状态。

## 根因（位置）

问题由三层叠在一起，修在会话层（第 1 层），根因在 media_kit 分支（第 3 层）：

1. **会话只信引擎的缓冲标志**：`packages/live_player/lib/src/session.dart`
   - `:563-565` `EngineBuffering` 直接写 `_buffering`；
   - `:609-618` `_onPlaying(true)` 遇到 `_buffering` 为真时只发 `buffering`、开缓冲看门狗；
   - `:572-573` 直播的位置事件被丢掉，`:679-682` `_onFrame` 不看 `_buffering`——两种“媒体在走”的证据都没被用来纠正标志；
   - `:687-701` 缓冲看门狗到点 `if (!_current(session) || !_buffering || !_wantPlaying) return;`，否则报 `buffering_stall_timeout` → `_recover`（`:881`）→ `_tryRefresh`（`:938`）刷新地址重开。所以标志一卡住，12 秒后必然重连。
2. **引擎层原样转发并补发**：`packages/live_player/lib/src/mpv_engine.dart:115-120` 把 media_kit 的 `stream.buffering` 原样转发；`:190` 打开后把当时的 `player.state.buffering` 再发一次——如果这时 media_kit 的标志已经卡在真，会话收到的就是错的初值。
3. **media_kit 分支的缓冲标志**（`third_party/media_kit/lib/src/player/native/player/real.dart`）由三处写：
   - `:1374-1388` `MPV_EVENT_START_FILE` 时置真并通知；
   - `:1402-1420` `core-idle`：为 1 时只有 `isBufferingStateChangeAllowed` 才置真，为 0 时置假；每次之后把允许位设回真。`open()` 开头把允许位设成假（`:240`，`pause` 也会触发 `core-idle`），所以打开后**第一个** `core-idle=1` 被吞掉；
   - `:1421-1427` `paused-for-cache`：直接照值置真或假。
   - mpv 的属性观察只在值**变化**时通知。`START_FILE` 置真以后，要等 `core-idle` 变成 0 或 `paused-for-cache` 从 1 变成 0 才会清掉；如果这两个属性在 `START_FILE` 前后没有再变化（例如 `core-idle` 在加载前已经是 0、加载中的 1 被吞掉），或者两个属性的通知顺序是“`core-idle=0` 先到、`paused-for-cache=1` 后到、之后没有 `paused-for-cache=0`”，标志就停在真。这是根因候选，阶段 1 用日志确认（记下每次 `EngineBuffering` 前后的两个属性值）。

## 方案

- c1 进度心跳：会话在“想播（`_wantPlaying`）、引擎在播（`_playing`）、状态是缓冲、来源代对（`_accepting`）”时，把直播的 `EnginePosition` 和（Windows 的）`EngineFrame` 当进度：位置比进入缓冲后的第一个位置前进了至少 1 秒（媒体时间，且不超过墙钟时间 + 2 秒，排除拖动和时间戳跳变），或者 1 秒内来了至少 10 个画面帧，就当缓冲已经结束：`_buffering = false`，走 `_onBuffering(false, session)` 的同一条路（状态改播放中、取消缓冲看门狗、开画面看门狗和预算计时）。只升不降：心跳从不把状态改成缓冲或暂停。
- c2 看门狗兜底：缓冲看门狗到点时（`session.dart:689-700`）先按 c1 的条件对账一次，满足就不报错；不满足才报 `buffering_stall_timeout`。
- c3 不对账的情况：用户暂停（`_wantPlaying` 假）、点播的拖动（位置跳变）、来源换代（`_accepting` 假）、纯音频（只认位置，不认画面帧）。
- c4 恢复原因：`PlaybackState` 加只读字段 `recoveryCause`（触发这次恢复的错误代码，例如 `buffering_stall_timeout`；`recovery` 为 0 时为空；只添加）；`room_controller.dart` 在恢复次数变大时写一行应用日志（`AppLog.instance.info('playback', …)`），并 `debugPrint` 同一行给 logcat：`playback: recovering #2 buffering_stall_timeout`。
- c5 评估 Android 的画面停住检测：每 2 秒最多读一次 mpv 的 `estimated-frame-number`（或 `frame-drop-count` 之外的帧计数），只在播放中、画面可见、非纯音频时读；连续 10 秒不变当作画面停住。量一下读属性的耗时，开销小（单次 <1 毫秒）就在本任务做，否则写“不做”的原因和以后的条件。
- c6（只记录）：阶段 1 的日志确认根因在 media_kit 分支时，把证据写进 `record.md`，建议在 G01 开任务修分支（例如 `START_FILE` 后主动读一次两个属性的当前值）；本任务的心跳保留作兜底。

## 验证

- 自动测试（`packages/live_player/test/session_test.dart`，`fake_async`）：
  - 缓冲中位置在走 → 状态回到播放中、12 秒后没有重开（改之前会失败）；
  - 缓冲中位置不走 → 12 秒后照旧恢复，`recoveryCause == 'buffering_stall_timeout'`；
  - Windows：缓冲中画面帧在来 → 播放中；
  - 用户暂停后位置事件不改状态；点播拖动的位置跳变不算进度；
  - 恢复结束后 `recoveryCause` 清空；
  - 应用：恢复时应用日志多一行 `playback: recovering #1 <代码>`。
- 真机：见 [brief.md](brief.md) 的“真机验证”（K90 上五个平台各连续播 15 分钟，数日志里的 `buffering_stall_timeout`，改前改后对比；断网、暂停、回放拖动不误判）。

## 留下的问题

- 如果日志证明是 media_kit 的缓冲标志本身卡住，修分支另开任务（G01），本任务的心跳保留作兜底。
- c5 不做时，Android 的冻画面检测留到以后（条件：有用户反馈冻画面，或者 media_kit 分支在 Android 上也能报画面帧）。
