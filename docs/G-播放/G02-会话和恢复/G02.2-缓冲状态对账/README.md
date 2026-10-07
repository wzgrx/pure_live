# G02.2 缓冲状态对账：画面帧在走时补回“播放中”，不再被当成卡住去重连

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：上游对照 [W01.1](../../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)（2026-10-03）：media_core 提交 `44710e1`、`2edc721` 修了“缓冲结束的事件丢了时，画面在动但状态一直是缓冲”；4.x 同样有这个问题
- 旧编号：T04b.2
- 相关：决定 D-001、D-017；前置 [G02.1](../G02.1-播放器/README.md)；和 [G03.1](../../G03-起播速度和弱网/G03.1-起播速度和弱网/README.md) 都改 `session.dart`（先做本任务）；任务书 [brief.md](brief.md)

## 目标

- 正常播放中，即使引擎的“缓冲结束”事件丢了（或缓冲标志卡住），只要画面或播放位置在走，会话就把状态补回“播放中”：界面上不再有压在流畅画面上的转圈，12 秒后也不会被缓冲看门狗当成卡住去刷新地址、重连。
- 真的卡住（位置不走）时，缓冲看门狗照旧 12 秒后恢复，行为同 3.x。
- 恢复的原因写进应用日志，真机上能数出“因为缓冲超时而重连”的次数，改前改后对比。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 缓冲状态从哪来 | 适配器的 `buffering` 流（`media_kit_adapter.dart:692`） | `MpvEngine` 把 media_kit 的 `stream.buffering` 转成 `EngineBuffering`（`mpv_engine.dart:115-120`）；media_kit 由 mpv 的 `core-idle` 和 `paused-for-cache` 两个属性共同驱动（`third_party/media_kit/lib/src/player/native/player/real.dart:1401-1427`） | 不变；会话另外有心跳兜底 |
| 缓冲看门狗 | `player_manager.dart:2610-2638`：一次缓冲一个 12 秒期限，到点还在“加载”就报 `buffering_stall_timeout` | `session.dart:687-701`：同 3.x | 到点前如果位置或画面在走，先对账，不报错 |
| 画面帧 | Windows 的帧进度，只用来判断画面停住 | `_onFrame`（`session.dart:679-682`）只记时间、重排画面看门狗；Android 引擎不报画面帧（`mpv_engine.dart:99-100`） | 画面帧（Windows）和位置前进（所有平台）都能把“缓冲中”补成“播放中” |
| 位置事件 | 直播不用 | `session.dart:572-573`：只有点播才用 `EnginePosition` | 直播也用来对账（不改状态里的 `position`） |
| 打开后的状态 | 打开成功后按适配器的真实状态补发一次（`player_manager.dart:1920-1938`） | `MpvEngine.open` 打开后补发 `EngineBuffering`、`EnginePlaying`（`mpv_engine.dart:186-191`） | 不变 |
| 恢复原因 | 有日志（`developer.log`） | 会话不说为什么恢复；应用不记录 | 状态带上恢复原因（只添加），应用写进日志 |

上游的做法（media_core 当前代码 `packages/media_core_live/lib/src/live_playback_pipeline.dart`）：`_reconcileMirroredPlayback`（第 200 行起）把每个位置事件当心跳，镜像状态说“没在播”而引擎说“在播”时补成播放中，**只升不降**（降为暂停只走用户命令）；`_seedPlaybackState` 在引擎接上前已经在播时补发一次状态。

## 方案

- c1 进度心跳：会话在“想播（`_wantPlaying`）、引擎在播（`_playing`）、状态是缓冲”时，把直播的 `EnginePosition` 和（Windows 的）`EngineFrame` 当进度；位置比缓冲开始时前进了至少 1 秒（媒体时间）、或者 1 秒内来了至少 10 个画面帧，就当缓冲已经结束：`_buffering = false`，走 `_onBuffering(false, session)` 的同一条路（状态改播放中、取消缓冲看门狗、开画面看门狗和预算计时）。只升不降：心跳从不把状态改成缓冲或暂停。
- c2 看门狗兜底：缓冲看门狗到点时（`session.dart:689-700`），如果期间有 c1 的进度但还没满足对账条件，先对账一次再决定；没有进度才报 `buffering_stall_timeout`。
- c3 不干扰的情况：用户暂停（`_wantPlaying` 假）、点播的拖动（位置跳变不算进度：只认“前进量不超过墙钟时间 + 2 秒”的增量）、来源换代（`_accepting` 假）、纯音频（只认位置，不认画面帧）时都不对账。
- c4 恢复原因：`PlaybackState` 加只读字段 `recoveryCause`（错误代码，例如 `buffering_stall_timeout`，`recovery` 为 0 时为空；只添加，现有字段不变）；`room_controller.dart` 在恢复次数变化时写一行应用日志（`AppLog.instance.info`），同时 `debugPrint` 同一行给 logcat：`playback: recovering #2 buffering_stall_timeout`。
- c5 评估 Android 的画面停住检测：Android 引擎不报画面帧，冻住的画面（声音还在）不会被发现。评估能不能用 mpv 的 `estimated-frame-number` 或 `frame-drop-count` 低频轮询代替；结论写进记录。能用且开销小（每 2 秒最多读一次属性）就在本任务做，否则写“不做”的原因和以后的条件。

## 验证

- 自动测试（`packages/live_player/test/session_test.dart`，用 `fake_async`）：
  - 缓冲中位置在走 → 状态回到播放中、12 秒后没有重开（改之前会失败）；
  - 缓冲中位置不走 → 12 秒后照旧恢复（不变）；
  - Windows：缓冲中画面帧在来 → 播放中；
  - 用户暂停后位置事件不改状态；点播拖动的位置跳变不算进度；
  - 恢复时 `recoveryCause` 是触发它的错误代码，恢复结束后清空。
- 真机：见 [brief.md](brief.md) 的“真机验证”（K90 上各平台连续播放，数日志里的 `buffering_stall_timeout` 次数，改前改后对比）。

## 留下的问题

- 如果日志证明是 media_kit 的缓冲标志本身卡住（`core-idle` 和 `paused-for-cache` 先后到达），在分支里修根因另开任务（G01），本任务的心跳保留作兜底。
