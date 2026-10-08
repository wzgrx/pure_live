# G03 起播速度和弱网

点进直播间到第一帧画面要多久、慢在哪一段、怎么变快；网络差的时候（高延迟、低带宽、丢包）播放怎么撑住、什么时候才算卡住、恢复多快。这是用户最直接感觉到的“快不快”，PLAN 原则 4 写着“速度（起播、滑动、响应）优先”，所以 G03.1 是全项目第一档。

## 范围

- 包括：
  - 起播时间的测量方法和打点（从直播间页 `initState` 到第一帧，逐段拆开）、各平台的数字、和 3.x 的对比。
  - 起播路径上属于播放的环节：引擎创建（`MpvEngine.create`）、输入打开（`MediaOpener.open`、本地中继启动和首个上游请求）、mpv 的探测和缓存参数（`mpv_options.dart:133-158` 的 `demuxer-lavf-probesize`、`demuxer-lavf-analyzeduration`、`cache-secs`、`demuxer-readahead-secs`、`network-timeout`）、会话的时限（`SessionTimings`：打开 18 秒、缓冲 12 秒、刷新 12 秒）。
  - 起播路径上属于直播间的编排（谁先谁后、能不能并行）：`LiveRoomController.start` → `load` → `_startStream` → `_openQuality` → `session.open`；换房时等旧房间释放（`live_play_page.dart:380-395`）。这部分代码在 C01，改动由 G03.1 按测量结果提出、在任务书范围里写明。
  - 弱网：缓冲多久算卡住、弱网下的重连节奏、要不要降清晰度的建议。
- 不包括（归哪里）：
  - 平台接口本身慢（要两三个请求才拿到地址、签名计算）→ E 组对应平台的任务；G03.1 只给出各平台“取详情、取画质、取地址”各花多少，交给 E 组。
  - 加载时画面上显示什么（转圈、“正在连接直播流…”、封面模糊底）→ A07.7；首页卡片点下去的反馈 → A03。
  - 应用冷启动到首页 → [R04](../../R-性能和流畅度/R04-启动速度/README.md)；列表滑动帧率 → R01。
  - 会话的恢复顺序和对账 → [G02](../G02-会话和恢复/README.md)；取流管线的正确性 → [G01](../G01-引擎/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：从首页点一个直播间，页面推进来（约 300 毫秒的转场），画面区域先是封面或黑底加“正在连接直播流…”，然后出画面；K90 冒烟（S02.2）时国内平台“几秒内出画面”，**没有任何具体数字**——3.x 和 4.x 都没测过。
- 起播路径（一次冷进房，按代码顺序）：
  1. `LivePlayPage.initState`（`features/live_play/live_play_page.dart:196-262`）：读设置、建 `MpvEngineConfig`（`:399`），从 `PlayerStandby` 取上一个房间留下的会话（配置一样时），否则 `newPlaybackSession`；建 `LiveRoomController`（`:274`）并 `unawaited(controller.start())`（`:259`）。页面转场和下面的网络请求同时进行。
  2. `LiveRoomController.start`（`logic/room_controller.dart:304-328`）：订阅弹幕和设置，**先 `await _reloadFilter()`（读屏蔽词和屏蔽用户两张表，`:316`、`:340-357`）和礼物开关的 meta（`:317-319`），再 `load()`**——这两次本地读库排在第一个网络请求之前。
  3. `load`（`:360-404`）：`site.getRoomDetail`（网络，一到几个请求，视平台）；判断开播。
  4. `_startStream`（`:413-444`）：`LiveQualityDiscoveryScope.discover` 取画质（有的平台要再请求一次）；`_preferredQuality` 查一次网络类型（`connectivity_plus`，`:407-411`）；`defaultQualityIndex` 选默认档。
  5. `_openQuality`（`:462-513`）：`site.resolvePlayUrls`（网络，多数平台要签名地址）；局域网地址先要 Android 17 的本地网络权限；然后 `session.open`。
  6. 会话（`packages/live_player/lib/src/session.dart:195-231`、`:444-538`）：第一次打开才建引擎（`_engineNow` `:406`：`MpvEngine.create`，`mpv_engine.dart:54-75`，逐个 `await setProperty` 设 13 个直播属性，再建 `VideoController`，Android 上要等 Surface）；`MediaOpener.open`（`packages/live_media/lib/src/input.dart:112`）——直连只拼地址，`flvSplice`/`hlsRelay` 要先启动本地中继（只第一次）并由中继发首个上游请求；`MpvEngine.open`（`mpv_engine.dart:162-193`）设 `hwdec`、`http-proxy` 后 `player.open`。
  7. mpv：连接 CDN → 探测（最多 2 MiB / 2 秒）→ 填缓存 → 解出第一帧（`videoParams` 有尺寸，会话发 `EngineVideoSize`）→ `core-idle` 变 0（缓冲结束，状态 `playing`）。
  8. 播放开始后才连弹幕（`_syncDanmaku`，`:442`）和取醒目留言。
- 换房（竖屏全屏上下滑、切换直播间面板）：`_switchRoom`（`live_play_page.dart:359-395`）先等旧房间 `dispose`（停会话、关输入）完成，才 `controller.start()` 新房间——新房间的取详情、取地址都排在旧房间释放之后。
- 弱网相关的现值：mpv `network-timeout` 15 秒、缓存 6 秒、前向缓冲 32 MiB；会话打开期限 18 秒、缓冲期限 12 秒、刷新期限 12 秒、两轮重试 0.75 秒和 2 秒（`session.dart:41-88`）；全部照 3.x，没有为弱网单独调过。
- 完成度：3.x 也没有起播打点和弱网策略；4.x 的结构比 3.x 更容易打点（会话和直播间分开）。G03.1 之前没有任何数字。

## 代码地图

| 文件 | 和起播、弱网有关的部分 |
|---|---|
| `apps/pure_live/lib/features/live_play/live_play_page.dart`（1366 行） | `initState`（`:196-262`，建会话或接手 `PlayerStandby` 的会话、`controller.start()`）、`_switchRoom`（`:359-395`，换房先等旧房间释放）、`_engineConfig`（`:399`） |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（1064） | `start`（`:304`，先读屏蔽表和 meta）、`load`（`:360`，取详情）、`_preferredQuality`（`:407`，查网络类型）、`_startStream`（`:413`，取画质）、`_openQuality`（`:462`，取地址、`session.open`）、`_plan`（`:515`）、`_refreshPlan`（`:546`） |
| `apps/pure_live/lib/features/live_play/logic/player_standby.dart`（63） | 关闭的直播间留下会话，下一个房间配置一样时不用重建引擎（C02.1） |
| `packages/live_player/lib/src/session.dart`（1011） | `SessionTimings`（`:41-88`）、`open`（`:195`）、`_engineNow`（`:406`，第一次打开才建引擎）、`_openSource`（`:444`，18 秒期限 `:492-502`） |
| `packages/live_player/lib/src/mpv_engine.dart`（283） | `create`（`:54-75`，逐个设属性、建 `VideoController`）、`open`（`:162-193`）、帧率探测在打开后 2 秒（`:192`） |
| `packages/live_player/lib/src/mpv_options.dart`（159） | `liveProperties`（`:133-158`）：探测 2 MiB / 2 秒、缓存 6 秒、32 MiB / 4 MiB、预读 2 秒、`network-timeout` 15 |
| `packages/live_media/lib/src/input.dart`（256） | `MediaOpener._relayNow`（`:105`，第一次要中继时才启动）、`open`（`:112`） |
| `packages/live_media/lib/src/relay/loopback_relay.dart`（326）、`relay/hls_relay.dart`（543） | 中继启动、HLS 主列表首个上游请求 |
| `packages/live_core/lib/src/live_site.dart` 等 | 各平台的 `getRoomDetail`、`getPlayQualities`、`resolvePlayUrls`（E 组） |

测试：没有起播时间的自动测试（`integration_test/perf_test.dart` 的 `room_enter_exit_20` 用假播放器，只量界面帧和内存，见 R01.1）；会话的打开期限有 `session_test.dart` 的“a stalled open is bounded and the next line is tried”。

## 3.x 基线

- 3.x 的起播路径（`git show v3.2.11:lib/`）：`modules/live_play/controllers/live_play_controller.dart:249`（进房取详情、合并卡片信息）→ `player_controller.dart:594`、`:613`（默认清晰度）→ `player/core/player_manager.dart` 的 `playSource`（打开 18 秒期限 `:297`、`:2296-2301`）；播放器是全局单例 `player/global_player_service.dart`，在 `main.dart:91` 初始化编排器，原生解码器在第一次播放时才建（“keep native decoders … cold”）。
- mpv 属性同 4.x：`player/adapters/media_kit_adapter.dart:84`（探测 2 MiB）、`:89`（分析 2 秒）、`:98`（`network-timeout` 15），`player/utils/live_buffer_policy.dart`（缓存、预读 2 秒）。
- 3.x 没有起播打点、没有弱网专门的策略；换房（`switchRoom`）同样先关旧的再开新的。
- 目标来自 [specs/UI.md](../../specs/UI.md) 第 9.4 节：“点击直播间到画面出现：不超过 v3 的 70%”。手机上的 3.x 是用户的正式包，**不能拿来测**（D-019、不碰 3.x 安装和数据），要对比只能另装一个改了包名的 3.x 构建（见 G03.1 任务书）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有任何起播时间的数字（3.x、4.x 都没测过），specs/UI.md 9.4 的目标无法判定 | — | 不知道慢不慢、慢在哪 | G03.1 阶段 1 |
| 第一个网络请求前先读两张屏蔽表和一个 meta（顺序 `await`） | `room_controller.dart:316-319`、`:328` | 进房多等几次本地读库（量级待测） | G03.1 阶段 3 候选（和取详情并行） |
| 引擎在拿到地址之后才建（取详情、取画质、取地址都完成后） | `session.dart:473`（`_engineNow` 在 `_openSource` 里） | 冷进房时建引擎和 Surface 的时间串在网络之后 | G03.1 阶段 3 候选（进房即预建引擎，和网络并行） |
| 换房先等旧房间释放完才开始取新房间的详情 | `live_play_page.dart:380-395` | 上下滑换房多一段停旧会话的时间 | G03.1 阶段 3 候选（取详情、取地址先做，只有 `session.open` 等释放） |
| mpv 探测 2 MiB / 2 秒是 3.x 照搬的值，没为直播起播调过 | `mpv_options.dart:136-138` | 码率低的流要等满 2 秒分析才出画面（待测） | G03.1 阶段 2 用 A/B 测；改了要防音轨、流信息识别错 |
| 弱网下的时限没调过：12 秒缓冲期限对 1 Mbps 下的原画可能太短（反复重连），18 秒打开期限对高延迟可能太短 | `session.dart:44-48` | 弱网下“正在重连”反复出现 | G03.1 阶段 2、3 |
| 缓冲标志卡住会被当成卡住去重连（打乱起播和弱网的测量） | 见 G02 已知问题 | 测量里混进假的重连 | G02.2（先做） |
| 没有恢复原因的日志 | `state.dart` | 弱网测试数不清重连原因 | G02.2 c4 |

## 相关决定和规范

- [specs/UI.md](../../specs/UI.md) 第 9.4 节：点击直播间到画面出现不超过 v3 的 70%；第 9.2 节第 4 条（重活不在界面线程）。
- PLAN 原则 4：速度优先；第一档列有 G03.1。
- D-017：测试里定时器至少 1 秒、不访问真实平台；起播的真实数字只在 K90 上量。
- D-019：K90 随时可用，只点测试包；不碰 3.x 和正式包。

## 测试和验证

- 自动测试：G03.1 加的打点要有单元测试（假引擎、假平台，断言各段都有记录、顺序对、只在一次打开里记一次）；改并行编排时直播间测试（`apps/pure_live/test/features/live_play/`）要证明“取详情不再等读库”“换房时新房间的取详情在旧房间释放前开始”。
- 真机：G03.1 的任务书写了完整的 K90 测量矩阵（5 个平台 × 5 次 × 冷 / 复用引擎，加弱网 3 个平台）；CHECKLIST 第 1 节第 1 条的“几秒内出画面”改成具体数字后补进清单。

## 路线

1. G02.2 先合并（会话对账和恢复原因日志）。
2. G03.1 阶段 1：打点代码合并，K90 测现状（可选：装一个改了包名的 3.x 构建测基线）。
3. G03.1 阶段 2：按数字找出最慢的两三段，A/B 试 mpv 参数，写清每个改动的预期收益，需要维护者确认取舍的（例如探测变小可能认错音轨）列出来。
4. G03.1 阶段 3、4：改进、再测对比；平台接口慢的部分交给 E 组开任务。
5. 以后：弱网自动降清晰度、加载时显示缓冲百分比（media_kit 已有 `bufferingPercentage`）这类新行为先进 V01 提议；多画面同时起播 4 路的时间在 N01 看。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [G 播放](../README.md)。

- 代码：`packages/live_player`、`packages/live_media`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| G03.1 | 起播速度和弱网：测首帧时间，找出慢的环节，改进后真机对比 | 性能 | 开发中 | — | — | [设计或说明](G03.1-起播速度和弱网/README.md)、[任务书](G03.1-起播速度和弱网/brief.md)、[记录](G03.1-起播速度和弱网/record.md) |

## 还没完成的

- **G03.1 起播速度和弱网：测首帧时间，找出慢的环节，改进后真机对比**（开发中，第一档，规模 中）
  - 阶段：测量现状 → 找出慢的环节 → 改进 → 真机对比
  - 接着做：阶段 1 c2：K90 上按 README“真机验证”测量（c1 打点已做，收集：adb logcat -s flutter | grep playback-timing）

<!-- docs:生成结束 -->
