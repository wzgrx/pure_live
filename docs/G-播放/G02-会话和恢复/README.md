# G02 会话和恢复

一个播放器从“打开这个画质”到“停止”之间的全部状态和恢复：`PlaybackSession` 怎么打开、怎么跟引擎的事件、什么时候算卡住、出错时按什么顺序恢复（刷新地址、换线、重建引擎、软解、延迟重试）、租期怎么预取、点播怎么结束，以及它对外发出的 `PlaybackState`。

## 范围

- 包括：
  - `packages/live_player/lib/src/session.dart`（`PlaybackSession`、`PlaybackRequest`、`SessionTimings`、`PlanRefresher`）和 `state.dart`（`PlaybackStatus`、`PlaybackState`）——会话本身不引 Flutter。
  - 引擎事件的含义（`engine.dart` 的 `EngineEvent`）和 `MpvEngine` 怎么把 media_kit 的状态变成这些事件（`mpv_engine.dart:106-154`、`:186-191`）；缓冲状态和画面、位置的对账（G02.2）。
  - 应用里会话的用法中和“恢复”有关的部分：直播间的刷新回调 `_refreshPlan`（`room_controller.dart:546`）、`ReconnectWatch`（只信会话说的恢复次数）、`PlayerStandby`（关掉直播间时把停好的会话留给下一个房间）、多画面每格一个会话。
- 不包括（归哪里）：
  - 取流管线（选源、选路、中继、配方、错误分类）和 mpv 属性 → [G01](../G01-引擎/README.md)。
  - 打开到首帧的速度、探测和缓冲参数、超时数值的调整 → [G03](../G03-起播速度和弱网/README.md)（G03.1 要改的 `SessionTimings` 默认值归它按数字决定）。
  - 转圈、“正在重连（第 N 次）”、“播放已中断”浮层、暂停按钮的样子 → A07.7、A07.10；直播间什么时候开始和停止播放、换房、前后台、小窗 → C01、C02、O02、O03（`background_playback.dart` 的 `RoomBackgroundPolicy`）。
  - 画面比例的判断（`PlaybackState` 里的 `aspectRatio`、`expectedAspectRatio` 这几个读数）→ [G04](../G04-画面/README.md)；纯音频和音量 → [G05](../G05-声音和媒体控制/README.md)；视频帧率怎么用 → R02。

## 现状：做到哪、怎么工作的

- 用户看得到的：进直播间先“正在连接直播流…”，出画面后是播放中；网络抖一下（缓冲）只转圈；流断了（出错、12 秒缓冲不结束、5 秒意外暂停不恢复、Windows 10 秒没画面）时画面上写“正在重连（第 N 次）”并自动恢复，恢复不了才出“播放已中断”和重试按钮；平台说下播、要登录、地区限制时立即说原因、不乱换线；用户暂停后不会被自动继续；回放（虎牙、微博、百度）播完是“已结束”可拖动，不当失败；关掉直播间 45 秒内进下一个房间不用重建播放器。
- 内部怎么工作：
  1. `open(PlaybackRequest(site:, plan:, refresh:, audioOnly:, volume:))`（`session.dart:195-231`）：开一代（`_begin` `:396`，取消上一代所有定时器）、重置线路和解码回退、发 `opening`，第一次打开时才建引擎（`_engineNow` `:406`）。
  2. `_openSource`（`:444-538`）：`SourceEventFence.begin` 开一代事件；经 `PlaybackTransport` 让 `MediaOpener` 开输入、`engine.open` 加载（整体 18 秒期限 `sourceOpen`，超时报 `source_open_timeout`）；成功后按引擎的标志定状态（`_settle` `:591`），安排租期预取（`_schedulePrefetch` `:795`）。打开期间的引擎错误先压住，出画面或进入播放就作废（`_openingError`，3.x 的打开诊断）。
  3. 事件（`_onEvent` `:556-587`）：`EnginePlaying`、`EngineBuffering` 改状态并开对应的看门狗；`EngineFrame`（只有 Windows）重排画面看门狗；`EnginePosition`、`EngineDuration` 只用于点播；`EngineVideoSize`、`EngineFrameRate` 写进状态；`EngineError` 进恢复。
  4. 看门狗（时限都在 `SessionTimings` `:41-88`）：缓冲 12 秒（`_armBufferingWatchdog` `:687`，重复的缓冲通知不重置）；意外暂停 0.35 秒后让引擎播放、再 5 秒算失败（`:705`）；画面 10 秒不更新（`:730`，只在引擎报画面帧、看得见、非纯音频时）；持续播放 30 秒恢复全部预算（`:769`）。
  5. 恢复（`_recover` `:881-934`，3.x 的顺序）：先发 `buffering` 和恢复次数；网络或来源错误且有刷新回调 → 刷新地址（第一次用预取的结果）重开同一线路，第二次换下一条（`_tryRefresh` `:938`，每轮最多两次）；仍不行 → 换一条没失败过的线路（`LineFallback`，按 CDN 代号）；画面停住 → 重建一次引擎；非音频的解码类错误 → 改软解；直播再等 0.75 秒、2 秒各一轮（`_scheduleRetryRound` `:969`，每轮预算重置）；都不行才发布错误。同一代里同一个错误只处理一次，恢复中新到的错误排队（`_handleError` `:850`、`_drain` `:864`）。
  6. 租期：切断连接的由中继续签（G01）；不切断的在 `refreshAt` 预取新地址、不碰正在播的连接，下次出错先用预取结果（过了 `expiresAt` 不用），预取失败 10 秒后再试（`:795-846`）。
  7. 停止：`stop()`（`:343`）释放输入、停引擎，45 秒没有再打开才释放引擎；`dispose()` 等正在创建的引擎也释放（`:371`）。
- 应用怎么用：直播间 `room_controller.dart:503-513` 打开，刷新回调是 `_refreshPlan`（`:546`，调平台的 `resolvePlayUrlsForRecovery`）；`ReconnectWatch`（`features/live_play/logic/reconnect_watch.dart:16`）只在 `state.recovering` 且缓冲或打开中时说“正在重连”（B02）；`PlayerStandby`（`player_standby.dart:15`）在关闭直播间时收下停好的会话，下一个房间引擎配置一样就接着用（C02.1）；多画面每格一个会话、共用一个 `MediaOpener`（`multiview_controller.dart`）；后台策略看不见画面时调 `setPresentationVisible(false)` 关掉画面看门狗（`session.dart:324`）。
- 完成度（和 3.x 对照）：
  - 一致：恢复顺序、预算、各个时限、去重、排队；刷新回来同一地址也重开；不切断的租期只预取；用户暂停不被看门狗恢复；缓冲看门狗不被重复通知重置；音频解码错误不走软解；停止后 45 秒释放。
  - 确认过的改动：会话不是全局单例、不管界面（G02.1 有意差异 6）；刷新回调返回 `PlaybackPlan`；删掉 Windows 虎牙热备切换；“首帧就绪”时限不移植（3.x 默认 0）；会话说出恢复次数（B02，`50143b27e`）；创建中被释放、重叠的停止不误释放（`47721f9f5`、`2f4aed12b`）。
  - 还缺：缓冲状态不和画面、位置对账（G02.2）；Android 没有画面停住检测；恢复原因不进日志（G02.2 c4）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_player/lib/src/session.dart`（1011 行） | `PlanRefresher`（`:13`）、`PlaybackRequest`（`:17`）、`SessionTimings`（`:41`）、`PlaybackSession`（`:109`）：`open` `:195`、`selectLine` `:234`、`retry` `:248`、`pause` `:266`、`resume` `:280`、`seek` `:297`、`setAudioOnly` `:309`、`setPresentationVisible` `:324`、`setVolume` `:332`、`stop` `:343`、`dispose` `:371`；内部 `_openSource` `:444`、`_renewer` `:542`、`_onEvent` `:556`、`_settle` `:591`、`_onPlaying` `:609`、`_onBuffering` `:642`、`_onCompleted` `:661`、`_onFrame` `:679`、看门狗 `:687-787`、预取 `:795-846`、恢复 `:850-1010` |
| `packages/live_player/lib/src/state.dart`（214） | `PlaybackStatus`（`:7`，空闲、打开中、缓冲、播放、暂停、播完、出错、停止）、`PlaybackState`（`:35`：线路、序号、解码方式、纯音频、音量、宽高、帧率、点播位置、实际画质、`recovery` `:119`、`recovering` `:122`、`isActive` `:126`）；`copyWith` 只在出错时保留错误（`:187-188`） |
| `packages/live_player/lib/src/engine.dart`（198） | `EngineMedia`（`:9`）、事件 `EnginePlaying`（`:64`）、`EngineBuffering`（`:76`）、`EngineCompleted`、`EngineVideoSize`、`EngineFrameRate`、`EnginePosition`（`:125`）、`EngineDuration`、`EngineFrame`（`:144`）、`EngineError`；`PlayerEngine` 接口（`:165`，`reportsFrames`） |
| `packages/live_player/lib/src/mpv_engine.dart`（283） | 事件来源：`_bind`（`:106-154`）把 media_kit 的 `playing`、`buffering`、`completed`、`videoParams`、`position` 转成事件，Windows 的 `frameRevision` 转成 `EngineFrame`；`open` 末尾补发当前的缓冲和播放标志（`:186-191`） |
| `packages/live_player/lib/src/video_view.dart`（141）、`screen_wake.dart`（45） | `LiveVideoView`（`:21`，没有引擎时黑底，`keepScreenOn` 只在播放或缓冲时）、`ScreenWake`（全应用一个常亮计数，O05.1） |
| `third_party/media_kit/lib/src/player/native/player/real.dart` | `buffering` 标志的真正来源：`START_FILE` 置真（`:1374-1388`）、`core-idle`（`:1402-1420`，打开后第一个为真的通知被 `isBufferingStateChangeAllowed` 吞掉，`:240`）、`paused-for-cache`（`:1421-1427`）；打开时先清成假（`:270-285`） |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（1064） | `_openQuality`（`:462-513`，`session.open`）、`_plan`（`:515`）、`_refreshPlan`（`:546`）、`_volume`（`:551`）、网络电视点播（`:693`） |
| `apps/pure_live/lib/features/live_play/logic/reconnect_watch.dart`（49） | `ReconnectWatch`（`:16`）：“正在重连（第 N 次）”只看 `state.recovering` |
| `apps/pure_live/lib/features/live_play/logic/player_standby.dart`（63） | `PlayerStandby`（`:15`）、`playerStandbyProvider`：关闭的直播间留下会话给下一个房间 |
| `apps/pure_live/lib/app/services.dart:78` | `newPlaybackSession({config})`：应用建会话（共用 `MediaOpener`） |
| `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`（952） | 多画面每格一个会话（`:636` 建计划） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_player/test/session_test.dart`（21） | 打开和播放；没有刷新回调时换线；刷新后同一线路；不切断的租期预取和使用；硬解失败改软解、音频错误不改；平台拒绝立即发布；恢复用尽后的延迟轮次；缓冲看门狗不被重复通知重置；B02 的恢复次数（两个）；用户暂停和意外暂停；点播播完和拖动；打开期间的诊断被播放否定；停止后闲置释放；重叠的停止；创建中被释放（两个）；打开超时换线；看不见的画面不算停住；线路声明的宽高（G04.1） |
| `packages/live_player/test/support/fake_engine.dart` | 假引擎：记下调用，测试直接发事件 |
| `apps/pure_live/test/features/live_play/live_play_states_test.dart`、`live_play_room_test.dart`、`room_extras_test.dart`、`room_switch_test.dart` | 直播间对会话状态的反应（转圈、重连提示、出错浮层）、播放器复用（`PlayerStandby`）、换房 |

## 3.x 基线

- `git show v3.2.11:lib/player/core/player_manager.dart`（5028 行，其中约 1800 行是会话和恢复）：时限 `:297-306`（打开 18 秒等）；缓冲看门狗 `_scheduleBufferingStallRecovery`（`:2610-2638`，“Playing/paused notifications do not prove media arrived”，一次缓冲一个期限）；画面停住 `video_frame_stall_timeout`（`:2538`）；恢复入口和错误代码到恢复类型的对照（`:2595-2596`、`:3847-3848`）；打开成功后按适配器真实状态补发（`:1920-1938`）；Windows 虎牙热备切换（`:216-226`、`:4170-4230`、`:4582-4597`，4.x 删除）。
- `lib/player/global_player_service.dart:16`：全局单例（4.x 改成应用持有、每个播放器一个会话）。
- 必须保留的行为（[specs/UI.md](../../specs/UI.md) 附录 A 和 G02.1 记录“保留的 v3 行为”）：用户暂停不被自动继续；直播的意外暂停先让引擎播放再算失败；刷新第一次同一线路、第二次换线；不切断的租期不替换正在播的连接。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| **缓冲标志卡住时会被当成卡住去重连**：会话只信引擎的 `buffering`，`_onPlaying(true)` 在 `_buffering` 为真时也只发缓冲（`session.dart:616-618`），`_onFrame` 不对账（`:679-682`），直播的位置事件被丢掉（`:572-573`），缓冲看门狗到点只看 `_buffering`（`:691`）。标志来自 media_kit：`START_FILE` 置真（`real.dart:1384`），之后要等 `core-idle` 或 `paused-for-cache` 的**变化**通知才清掉；mpv 只在属性值变化时通知，打开时第一个 `core-idle=1` 又被 `isBufferingStateChangeAllowed` 吞掉（`:240`、`:1407`），两者顺序不对时最后的值可能停在真。`MpvEngine.open` 末尾还会把这个值补发一次（`mpv_engine.dart:190`） | `packages/live_player/lib/src/session.dart:572-573`、`:609-628`、`:679-701`；`third_party/media_kit/lib/src/player/native/player/real.dart:1374-1427` | 画面在动却一直转圈，12 秒后刷新地址重开（画面闪一下），偶尔出现“正在重连（第 1 次）” | G02.2（上游 media_core `44710e1`、`2edc721` 修了同样的问题） |
| Android 没有画面停住检测：只有 Windows 的引擎报画面帧（`mpv_engine.dart:100`），Android 上画面冻住、声音还在时不会被发现 | `mpv_engine.dart:99-100`、`session.dart:730-760` | 偶发的冻画面只能用户手动刷新 | G02.2 c5 评估（读 `estimated-frame-number` 之类的属性，每 2 秒最多一次） |
| 恢复原因不进日志：`PlaybackState` 只有次数，错误只在 `status == error` 时保留；应用不记录恢复 | `state.dart:119`、`:187-188`；`room_controller.dart` | 真机上数不出“因为什么重连了几次”，G03.1 的测量也缺这个数 | G02.2 c4 |
| 断网重连、纯音频切换、Windows 画面停住重建没有真机记录（S02.3 记“没测”） | [S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) | G02.1 登记“完成”但关键恢复路径没有 K90 结果 | CHECKLIST 第 1 节第 3、9 条，建议并入 S02.6；Windows 在 X01 |
| 长时间暂停后继续：输入可能已经不可用（签名过期），`resume` 走 `retry` 重开，界面是“正在连接直播流…”而不是马上继续 | `session.dart:280-291` | 暂停很久再继续要等一次打开 | A07.10 已写进“留下的问题”，按现状接受 |
| 代码注释里的旧编号（M7.2、B02、F.1b） | `session.dart`、`state.dart` | 找文档先查 MAPPING | Z 组统一替换 |

## 相关决定和规范

- D-001：恢复顺序、时限照 3.x。
- D-012（暂停后单击只切控制层）：会话的 `pause` 是用户暂停，不被任何看门狗恢复。
- D-017：会话测试用假引擎和 `fake_async`，定时器至少 1 秒。
- D-027：上游对照发现的问题开到目标组（G02.2 来自 W01.1）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 4 节：会话是纯 Dart 逻辑，不引 Flutter（`session.dart`、`state.dart` 只引 `clock`、`meta`、`live_core`、`live_media`）。

## 测试和验证

- 自动测试：`cd packages/live_player && flutter test test/session_test.dart`（21 个，假引擎，不需要 libmpv）；应用侧 `cd apps/pure_live && flutter test test/features/live_play/`。缺的：缓冲标志卡住、Android 画面停住（G02.2 补）；没有用真 mpv 的会话测试。
- 真机：[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节第 2 条（切清晰度和线路不退出，S02.2、S02.3 看过）、第 3 条（关 Wi-Fi 10 秒再开，显示正在重连、恢复后继续，没有结果）、第 9 条（纯音频）。A07.10 的 [verify.md](../../A-界面设计/A07-直播间界面/A07.10-暂停状态/verify.md) 第 13～16 步也看会话的重连提示。

## 路线

1. G02.2（第二档，小）：缓冲状态对账 + 恢复原因进日志 + 评估 Android 画面停住检测。先于 G03.1 合并，两者都改 `session.dart`。
2. G03.1 测量时用 G02.2 的日志数重连次数；如果测量结果要求改 `SessionTimings`（例如弱网下 12 秒缓冲期限太短），由 G03.1 改。
3. 补真机证据：CHECKLIST 第 1 节第 3、9 条随 S02.6 一起看。
4. 以后：Windows 画面停住重建在 X01 验证；电视直播间的会话行为在 X03。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [G 播放](../README.md)。

- 代码：`packages/live_player`
- 进度：`███████████████░░░░░` 76%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| G02.1 | 播放器：会话、恢复、Flutter 绑定 | 功能 | 完成 | 2026-10-01 | 4e8cd6c67 | [设计或说明](G02.1-播放器/README.md)、[记录](G02.1-播放器/record.md) |
| G02.2 | 缓冲状态对账：画面帧在走时补回“播放中”，不再被当成卡住去重连 | 功能 | 未开始 | — | — | [设计或说明](G02.2-缓冲状态对账/README.md)、[任务书](G02.2-缓冲状态对账/brief.md) |
| G02.3 | 断网时播放器不提示“正在重连”、约 40 秒后报“解码失败”、网络恢复后不自己接上 | 功能 | 待真机 | 2026-10-08 | bd6ab89d6 | [设计或说明](G02.3-断网不提示重连且不自己接上/README.md)、[任务书](G02.3-断网不提示重连且不自己接上/brief.md)、[记录](G02.3-断网不提示重连且不自己接上/record.md) |

## 还没完成的

- **G02.2 缓冲状态对账：画面帧在走时补回“播放中”，不再被当成卡住去重连**（未开始，第二档，规模 小）
  - 说明：参考 media_core 44710e1、2edc721
  - 来源：上游 media_core 44710e1、2edc721（W01.1 对照）

<!-- docs:生成结束 -->
