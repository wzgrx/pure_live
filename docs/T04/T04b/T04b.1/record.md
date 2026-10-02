# T04b.1 播放器

- 日期：2026-10-01
- 目标包：`packages/live_player`（Flutter 包，依赖 `live_media`、`live_core`、`live_net`、`third_party/` 里的 media_kit 分支、`clock`、`meta`；测试另用 `fake_async`）
- 范围：v3 `lib/player/` 里依赖 Flutter 和引擎的部分（`adapters/media_kit_adapter.dart`、`interface/`、`player_manager.dart` 的会话和恢复、`global_player_service.dart`、`background_playback_policy.dart`、`live_room_volume_manager.dart`、`utils/live_buffer_policy.dart`、`utils/mpv_platform_profile.dart`），v3 的 `third_party/media_kit`、`third_party/media_kit_video`、`third_party/fvp`，以及 libmpv 的取得方式。
- 参考：归档 v4 `packages/live_player`（`MpvEngine`、mpv 选项、`audioOnly` 等图像的做法）、`third_party/`（同一分支同步到上游 803c4a27）、`spec/modules/playback.md`；`docs/T04/T04a/T04a.1/record.md`。

## 做法

1. **media_kit 分支**：v3 的本地补丁分支（Predidit/media-kit 加 PureLive 补丁：`setVideoOutputEnabled`、Windows `frameRevision`、`setSize(force:)`、Android Surface 统一管理、Windows 退出释放顺序）放进 `third_party/media_kit`、`third_party/media_kit_video`，用归档 v4 同步到上游 `803c4a27` 的版本（`toolchain.env` 已固定这个提交；比 v3.2.11 的 `d13fc22b` 多了上游对空属性数据的保护和 `MPV_FORMAT_FLAG` 按 32 位读取的修正）。根 `pubspec.yaml` 的 `dependency_overrides` 写这两个路径；分支把 `xml` 钉在 6.x、`wakelock_plus` 钉在 1.3.3，覆盖成最新稳定版 7.1.0、1.8.1（只用到两版都有的接口）。
2. **原生库**：照 v3，由 media_kit 的构建钩子（Native Assets，`third_party/media_kit/hook/native_bundles.json`）在构建时下载并校验 SHA-256，缓存在构建目录，不进 git：
   - Android arm64、armeabi-v7a、x86_64 和 Linux x64：本仓库 Releases 的 `native-libmpv-android-0.41.0-ff9.0.2-b1`、`native-libmpv-linux-0.41.0-ff9.0.2-b1`（mpv 0.41.0 + FFmpeg 9.0.2）；
   - Windows x64/arm64：Predidit `libmpv-win32-video-cmake` 20260915（mpv 0.41.0 开发版 + FFmpeg master）；
   - Android x86、Linux arm64、iOS、macOS：Predidit 的预编译包（FFmpeg 版本未标明）。
   `flutter test` 也会跑这个钩子（Linux x64 包下到 `packages/live_player/build/`，已忽略）。
3. **引擎**：`PlayerEngine` 接口（v3 `UnifiedPlayer` 按单一 mpv 引擎收窄）：`open(EngineMedia)`、`play`、`pause`、`stop`、`seek`、`setVolume`、`setAudioOnly`、`dispose`，事件流 `EngineEvent`（`EnginePlaying`、`EngineBuffering`、`EngineCompleted`、`EngineVideoSize`、`EnginePosition`、`EngineDuration`、`EngineFrame`、`EngineError`）。`MpvEngine` 是唯一实现：
   - 建播放器后按 v3 顺序设一次直播属性（`MpvEngineConfig.liveProperties`：探测 2 MiB/2 秒、内存缓存 32 MiB/4 MiB、不借用前向缓冲、`network-timeout=15`、`hwdec-software-fallback=1`、按平台的 `ao`、macOS 关硬解、Windows RTX 超分）；
   - 每次打开设 `hwdec`（会话软解回退时为 `no`）和 `http-proxy`（本地中继输入为空），带请求头加载；
   - mpv 的错误日志经 `NativeDiagnosticGate`：只看 v3 认的日志前缀；致命错误立即上报；可恢复的等 1.2 秒，同一解码器出画面或进入播放就取消；打开期间的日志先压住，打开后该解码器已有输出就丢弃；同一文本两秒内只报一次；
   - 纯音频：Android 走分支的 `setVideoOutputEnabled`，桌面选 `vid=no`；切回视频等到解码出画面（最多 2.8 秒）；
   - Windows 把 `frameRevision` 转成 `EngineFrame`（画面停住检测）。
4. **会话**：`PlaybackSession`（v3 `PlayerManager` 的会话和恢复部分，纯 Dart，不引 Flutter）：
   - `open(PlaybackRequest(site:, plan:, refresh:, audioOnly:, volume:))`：`plan` 是 T04a.1 的 `PlaybackPlan`，`refresh` 是重新取同一画质的回调（v3 `PlaybackSourceResolver`）；第一次打开时才建引擎；输入经 `MediaOpener` 和 `PlaybackTransport`，旧输入在新输入被引擎接受后才释放；
   - 状态 `PlaybackState`：`idle`、`opening`、`buffering`、`playing`、`paused`、`completed`、`error`、`stopped`，带线路序号、解码方式、视频宽高、点播位置和时长、平台实际给的画质；`states` 流同步发出；
   - 事件按 `SourceEventFence` 分代，打开期间的事件只记标志，打开成功后按标志定状态；
   - 看门狗（v3 默认值）：缓冲 12 秒（重复通知不重置）、意外暂停 350 毫秒后让引擎播放、再 5 秒算失败、Windows 10 秒没出画面算失败、打开 18 秒、刷新 12 秒；持续播放 30 秒恢复预算；
   - 恢复顺序（v3）：刷新计划后重开同一线路，第二次换下一条（最多两次）→ 换没失败过的线路（`LineFallback`，按 `lineId`）→ 画面停住时重建一次引擎 → 非音频的解码类错误改软解（`DecoderFallback`）→ 直播再等 0.75 秒、2 秒各一轮（每轮预算重置）→ 发布错误；同一来源代的同一错误只处理一次，恢复中新到的错误排队；
   - 平台说不能播（下播、要登录、地区、不存在）立即发布，不换线；
   - **租期**：切断连接的由中继续签（T04a.1）；不切断的在 `refreshAt` 预取新地址，不碰正在播的连接，下次断线先用预取结果（过了 `expiresAt` 就不用），每轮按新地址的 `refreshAt` 再排；
   - **点播**：`plan.onDemand` 时播完是 `completed`，不算失败，`seek` 可拖动，播完后拖动接着播；
   - `stop()` 释放输入、停引擎，45 秒没再打开才释放引擎（v3 `idlePlayerReleaseDelay`）；`dispose()` 全部释放。
5. **视频**：`LiveVideoView(session:, fit:, outputSize:)`：会话还没有 mpv 引擎时是黑底；有了就是 media_kit 的 `Video`，无控件，不随前后台自动暂停（交给应用的生命周期策略，v3 同）；`outputSize` 打开时原生输出跟随显示尺寸（180 毫秒防抖，v3 只在 Windows 用）。
6. **引擎能力**：`mpvEngineProfile()` 按当前 ABI 查原生包的 FFmpeg：9.0.2 和 master 能读 codec 12 的 HEVC FLV，不改写；版本未标明的包（Android x86、Linux arm64、iOS、macOS）打开 `rewriteLegacyHevcFlv`，由 T04a.1 的中继改写。
7. **策略**：`shouldContinueInBackground`（v3 后台播放规则）、`roomVolumeKey`、`roomVolume`（v3 每个房间的音量，键名不变，T09b.1 直接读 3.x 存的值）。

## 对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `player/core/player_manager.dart`（会话、恢复、看门狗、续签、预取） | 5028 中约 1800 | `session.dart` `PlaybackSession` | 恢复顺序、时限、去重、排队照 v3；GetX 状态换成 `PlaybackState` |
| `player_manager.dart`（画中画、应用内小窗、纯音频界面、竖屏几何、Windows 热备切换） | 其余 | 不在本块 | 见“放到其他模块的部分”和有意差异 |
| `player/global_player_service.dart` | 98 | 删除 | 全局单例换成应用持有的 `PlaybackSession`（T07a.1 的 provider） |
| `player/interface/unified_player_interface.dart`、`media_kit_player_accessor.dart` | 148 | `engine.dart` | 七个可选能力接口合进一个 `PlayerEngine` |
| `player/adapters/media_kit_adapter.dart` | 1266 | `mpv_engine.dart`、`diagnostics.dart`、`mpv_options.dart` | 诊断窗口、打开期间压住日志、纯音频、帧进度照 v3 |
| `player/adapters/fijk_adapter.dart`、`video_player_adapter.dart`、`fvp_adapter.dart`、`player_adapter_factory.dart`、`interface/fijk_player_accessor.dart`、`video_player_accessor.dart`、`utils/fijk_helper.dart` | 1260 | 删除 | 只留 mpv（有意差异 1） |
| `player/models/player_state.dart` | 14 | `state.dart` `PlaybackStatus` | 去掉只属于适配器的几步 |
| `player/utils/live_buffer_policy.dart`、`mpv_platform_profile.dart`、`player_consts.dart`（解码器、输出列表） | 238 | `mpv_options.dart` | 值不变，设置从参数传入 |
| `player/core/background_playback_policy.dart` | 21 | `policies.dart` | 规则不变，去掉没用的参数 |
| `player/core/live_room_volume_manager.dart` | 34 | `policies.dart` | 改成纯函数，键名不变 |
| `player/widgets/video_output_viewport_sizer.dart` | 155 | `video_view.dart` | 简化为按显示尺寸设输出（防抖） |
| `player/utils/media_kit_content_probe.dart`、`active_video_content_analyzer.dart` | 242 | 删除 | v3 默认关（`player_manager.dart:313` `enableActiveContentProbe = false`，截图探测会让 ColorOS/高通设备丢帧） |
| `player/core/linux_mpv_runtime.dart` | 65 | 留给 T07a.1 | 和 Linux 打包的备用库列表一起 |
| `player/core/live_audio_service.dart`、`live_audio_handler.dart`、`background_playback_service.dart`、`playback_lifecycle_coordinator.dart` | 779 | 留给 T07a.1 | 系统媒体通知、前后台；会话已有 `pause`/`resume` 可接 |
| `player/core/portrait_stream_support.dart`、`live_stream_geometry_hint.dart` | 1175 | 留给 M13、live_core | 会话给出视频宽高和 `isPortrait`；平台提示要 live_core 抖音数据带宽高 |
| `player/utils/fullscreen.dart`、`window_helper.dart`、`pip_window_widget.dart`、`popup_route_tracker.dart`、`mpv_option_labels.dart` | 1041 | 留给 T07a.1/M13 | 窗口、全屏、画中画、设置页文字 |
| `third_party/media_kit`、`media_kit_video` | — | `third_party/`（上游 803c4a27） | 补丁同 v3，见 `PURELIVE_PATCH.md` |
| `third_party/fvp` | — | 删除 | 有意差异 1 |

v3 调用方（`git grep` v3.2.11 `lib`，`lib/player` 之外）：`modules/live_play/widgets/video_player/video_controller.dart`（37 处）、`video_controller_panel.dart`（14）、`routes/navigation_observer.dart`（10）、`live_play_controller.dart`（10）、`video_keyboard.dart`（4）、`player_controller.dart`（3）、`player_kernel_settings_page.dart`（3）、`main.dart`、`home_page.dart`、`live_play_content.dart`、`multiview_controller.dart`（各 2）、`live_play_page.dart`、`video_player.dart`、`multiview_cell_player.dart`、`portrait_live_settings_page.dart`、`app_navigation.dart`（各 1）。M13 的替换：

| v3 | v4 |
|---|---|
| `GlobalPlayerService.instance.playerManager` | 应用持有的 `PlaybackSession`（T07a.1 provider） |
| `playSource(source, urls, headers, room:, audioOnly:)` + `sourceRefreshResolver` | `open(PlaybackRequest(site:, plan: PlaybackPlan.of(...), refresh:, audioOnly:, volume:))` |
| `pause`、`resume`、`togglePlayPause`、`retry` | 同名 |
| `close`、`softStop` | `stop` |
| `setAudioOnlyMode(bool)` | `setAudioOnly(enabled:)` |
| `setVolume` | `setVolume` |
| `currentLineIndex`、`lineCount`、`hasError`、`isPlayingNow`、`isVerticalVideo` | `state.lineIndex`、`state.lineCount`、`state.status == error`、`state.isActive`、`state.isPortrait` |
| `getVideoWidget(fit)`、`videoFitIndex` | `LiveVideoView(session:, fit:)` |
| `onPlaying`、`onStateChanged`、`onError` | `states` |
| `switchEngine` | 删除；改设置时用新的 `MpvEngineConfig` 建会话 |
| 多画面每格 `UnifiedPlayer` | 每格一个 `PlaybackSession`，共用一个 `MediaOpener`（共用中继） |

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 播放器是全局单例，界面、路由、设置、音频服务互相引用 | `global_player_service.dart:16`、`player_manager.dart:29-52`（引用路由、弹幕、设置、悬浮窗） | 一个类承担会话、恢复、画中画、小窗、界面 | 会话只管播放（纯 Dart），由应用注入；界面部分留给 T07a.1/M13 |
| 2 | 适配器直接读全局设置，测试和多画面要靠全局状态 | `media_kit_adapter.dart:106-127,266-303` | 设置单例 | `MpvEngineConfig` 由调用方传入 |
| 3 | 多引擎降级引入专有组件（fvp/libmdk）和三套适配器 | `player_adapter_factory.dart:10-22`、`global_player_service.dart:49-54` | 早期用换引擎绕开解码问题 | 只留 mpv，降级改成硬解 → 软解（有意差异 1） |
| 4 | 打开时由适配器读房间存的音量，手机端强制 1.0 | `media_kit_adapter.dart:615-620` | 音量策略写在引擎里 | 音量由 `PlaybackRequest.volume` 给出，规则是 `roomVolume` 纯函数 |
| 5 | 虎牙在 Windows 上 40 秒热备切换，平台判断写在播放器里，还要两个原生播放器轮换 | `player_manager.dart:216-226,4170-4230,4582-4597` | 线路不说租期是否切断连接 | 租期切断连接由 live_core 在线路上标出，中继续签拼接（T04a.1）；播放器不再按平台判断，热备切换删除（有意差异 2） |
| 6 | 分支按 8 位读 mpv 的 flag 属性，属性数据为空时不检查 | v3 `third_party/media_kit/lib/src/player/native/player/real.dart:1267,1394-1426` | 上游旧代码 | 跟进上游 803c4a27 |
| 7 | 后台规则带一个不参与判断的参数 | `background_playback_policy.dart:15` | 为防误用而留 | 去掉，规则不变 |
| 8 | 画面截图探测默认关，但代码和定时器一直在 | `player_manager.dart:307-313`、`active_video_content_analyzer.dart` | 发现 ColorOS/高通丢帧后只关了开关 | 删除 |

## 保留的 v3 行为

- 恢复顺序、预算（刷新两次、每轮重置、两轮延迟 0.75 秒和 2 秒、持续 30 秒恢复预算）、各个时限、同一错误去重、恢复中新错误排队。
- 刷新时第一次同一线路、第二次换线；刷新回来和原来一样的地址也重开（v3：地址相同不代表连接还好）。
- 不切断连接的租期只预取，不替换正在播的连接；预取失败 10 秒后再试。
- 用户暂停不会被看门狗恢复；直播的意外暂停先让引擎播放，再算失败；缓冲看门狗不被重复通知重置。
- 打开期间的诊断先压住；解码器已有输出就丢弃。
- 音频解码错误不走视频软解。
- mpv 属性的值和顺序；Android 打开后不重发 `vid=auto`；Windows 的帧进度。
- 停止后 45 秒才释放引擎。

## 有意差异

1. **只用 mpv**：v3 在手机上还有 fijk、exo、fvp 三个备用引擎（桌面只有一个）。PLAN §4 定为全平台 mpv：fvp 依赖专有的 libmdk，fijk/exo 只为旧 FFmpeg 读不了的流兜底，而 v4 的 Android 原生包是 FFmpeg 9.0.2。v3 用 fvp 处理的情况（17LIVE 等 codec 12 HEVC 在高通硬解上丢帧）现在由“优先 H.264”排序、`hwdec-software-fallback` 和会话的软解回退处理，留待真机验证；如果某平台还必须用别的引擎，实现 `PlayerEngine` 交给 `PlaybackSession(engine:)` 即可，会话不用改。
2. **删掉 Windows 热备切换**：见问题 5。租期没标切断的平台照 v3 只预取。
3. **刷新回调返回 `PlaybackPlan`**：v3 返回地址列表加首选下标；现在线路自带请求头、租期，换线按 `lineId` 找。
4. **帧级探测简化**：v3 在 Windows 上另外观察 `video-frame-info/picture-type`、`estimated-vf-fps` 判断解码进度（每帧都回调）；现在用视频参数和播放状态作进度，Windows 画面停住仍由 `frameRevision` 检测。
5. **“首帧就绪”时限不移植**：v3 默认值是 0（关），只靠缓冲看门狗。
6. **会话不管界面**：画中画、小窗、纯音频界面、竖屏布局、全屏、窗口都不在会话里。

## T04a.1 留下的事

| 事项 | 处理 |
|---|---|
| 在 `refreshAt` 预取不断开的租期 | 完成：`PlaybackSession` 预取并在下次断线时使用 |
| 点播播完不算失败、可以拖动 | 完成：`PlaybackStatus.completed`、`seek` |
| 画面比例提示 | 部分：会话给出解码后的宽高和 `isPortrait`；平台给的提示（v3 `live_stream_geometry_hint`，抖音）要 live_core 抖音数据带宽高，留给 live_core 和 M13 |
| “优先 H.264”默认值 | 未定：保持默认开，等高通真机硬解验证（T07a.1/M13 真机） |
| 按构建的 FFmpeg 版本填 `EngineProfile` | 完成：`mpvEngineProfile()` |

## 放到其他模块的部分

- **T07a.1**：应用里建 `MediaOpener`（共用中继、平台的配方打开器、`mpvEngineProfile()`）和 `PlaybackSession` 的 provider；Linux 打包的 libmpv 备用库（v3 `linux_mpv_runtime.dart` 和 `linux/CMakeLists.txt`）；系统媒体通知和后台播放服务（v3 `live_audio_service`、`live_audio_handler`、`audio_service`）；前后台生命周期（v3 `playback_lifecycle_coordinator`，接 `pause`/`resume` 和 `shouldContinueInBackground`）；画中画和窗口。
- **M13**：直播间、多画面按上表替换 v3 调用；音量、亮度手势（`volume_controller`、`screen_brightness`）；竖屏呈现；纯音频界面；Picarto 恢复时原档位没了改取最好的一档（在刷新回调里选）；设置页（播放器内核、输出、解码）。
- **live_core**：抖音数据带宽高（画面比例提示）；Twitch 按引擎能力请求 HEVC/AV1（8-8）；LiveMe、TikTok 租期是否切断连接（真机看到断开再改标记）。
- **T09b.1**：设置项（“优先 H.264”、硬解、兼容模式、输出、RTX 超分、每房间音量）传给 `MpvEngineConfig` 和 `PlaybackRequest`。
- **真机验证（T07a.1/M13）**：播放、低延迟参数、高通 HEVC 硬解、Windows 画面停住重建、纯音频切换。

## 依赖变化

- 新包 `live_player` 加入根 `pubspec.yaml` 的 workspace，依赖方向按 `tools/gate/check_deps.py`（`live_media`、`live_core`、`live_net`）。
- 新增 `third_party/media_kit`（1.1.11）、`third_party/media_kit_video`（1.2.5），上游 Predidit/media-kit `803c4a27`，MIT，保留上游 `LICENSE`。
- 根 `dependency_overrides`：`media_kit`、`media_kit_video` 路径；`xml` 7.1.0、`wakelock_plus` 1.8.1（分支钉的旧版本覆盖为最新稳定版）。
- 随 media_kit 进来的传递依赖：`archive`、`image`、`native_toolchain_c`、`safe_local_storage`、`uri_parser`、`universal_platform`、`wakelock_plus` 等（`pubspec.lock`）。

## 升级条目

UPGRADES 中模块列含 T04 的条目已逐条更新：6-4 完成（T04b.1）；3-1、18-5、30-4 的 T04 部分完成（点播），余下 M13；6-1、22-2 的 T04 部分完成，余下平台层或 T09b.1；8-8、11-1、14-5、22-3、30-2、33-2 写明 T04b.1 做了什么、还剩哪个模块；9-1、26-2、27-7、29-8 无变化。

## 测试

23 个用例（`flutter test`，不需要 libmpv 运行）：
- `session_test.dart`（13）：假引擎上的打开和播放、无刷新时换线、刷新后同一线路、不切断租期的预取及断线时使用、硬解失败改软解（音频错误不改）、平台拒绝立即发布、恢复用尽后的延迟轮次和最终错误、缓冲看门狗不被重复通知重置、用户暂停与意外暂停、点播播完和拖动（直播结束算失败）、打开期间的诊断被播放否定、停止后闲置释放引擎、打开超时换线；
- `diagnostics_test.dart`（4）：日志前缀、致命错误去重、可恢复错误被同一解码器的进度取消、打开期间压住的日志；
- `options_test.dart`（5）：直播属性、解码和输出选择、按原生包决定 HEVC 改写、显示尺寸与旋转、后台规则和房间音量（移植 v3 `background_playback_policy_test` 的用例）；
- `view_test.dart`（1）：没有引擎时是黑底。
