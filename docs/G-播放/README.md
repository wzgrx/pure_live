# G 播放

直播画面和声音从“拿到一个画质的线路”到“屏幕上在动”的全部行为：用哪个引擎、怎么取流和中转、怎么打开和恢复、多快出第一帧、画面比例怎么判断、声音和系统媒体控制。看直播是这个应用最核心的事，画面出不来其他一切都没意义，所以排在界面（A）、直播间（C）、弹幕（D）、平台（E）之后的第一个功能组；其中起播速度和弱网（G03.1）是全项目第一档的任务。

## 范围

- 管什么：
  - 引擎（G01）：`third_party/media_kit`、`third_party/media_kit_video`（media_kit 的本地补丁分支，libmpv 和 FFmpeg 原生包由构建钩子下载）、`packages/live_player` 的 `MpvEngine`、`MpvEngineConfig`（mpv 属性、软硬解、输出）、`mpvEngineProfile()`；`packages/live_media`（纯 Dart）的选源 `PlaybackPlan`、选路 `MediaRoute`、开源 `MediaOpener`、本地中继 `LoopbackRelay`（FLV 续签拼接、HEVC FLV 改写、HLS 改写和续签、Bigo/FC2/niconico 的配方输入）、错误分类 `NativeDiagnostic`；“优先 H.264”的排序和它的默认值（G01.2）。
  - 会话和恢复（G02）：`packages/live_player/lib/src/session.dart` 的 `PlaybackSession`（打开、分代、看门狗、刷新地址、换线、重建引擎、软解、延迟重试、租期预取、点播、停止和闲置释放）和它发出的 `PlaybackState`；应用里直播间、多画面、小窗怎么用会话（`room_controller.dart` 的打开和刷新、`player_standby.dart`、`reconnect_watch.dart`）。
  - 起播速度和弱网（G03）：点进直播间到第一帧的时间、mpv 的探测和缓冲参数、弱网下的缓冲和恢复时限。
  - 画面（G04）：画面比例和竖屏的判断（`PlaybackState.isPortrait`、`expectedAspectRatio`、平台声明的宽高）、画面方向。
  - 声音和媒体控制（G05）：纯音频、音量（全局、每个房间）、系统媒体会话和通知、音频焦点。
- 不管什么：
  - 播放器上面的一切界面（控制层、转圈、“正在重连（第 N 次）”、失败浮层、清晰度和线路菜单、画面比例菜单、纯音频封面）→ [A07 直播间界面](../A-界面设计/A07-直播间界面/README.md)。本组只管状态从哪来、什么时候变。
  - 直播间什么时候开始播、换房、小窗和后台的生命周期、菜单里的工具 → [C 直播间](../C-直播间/README.md)；小窗和画中画的系统部分 → [O02](../O-Android系统集成/README.md)。
  - 各平台怎么取画质和线路、线路上的请求头、编码标记、租期 → [E 直播平台](../E-直播平台/README.md)（E05 管模型 `LivePlayLine`、`LivePlayUrlResolution`）。
  - 播放代理的设置和 `PlaybackProxyPolicy` → [Q02](../Q-网络和代理/Q02-代理和镜像/README.md)；本组只把它交给 mpv 和中继。
  - 录制复用的中继和 HLS 预取窗口（`relay/hls_window.dart`）→ [H01](../H-录制/README.md)。
  - 刷新率和视频帧率匹配 → [R02](../R-性能和流畅度/R02-刷新率/README.md)（帧率由本组的 `MpvEngine` 读出来交给它）；多画面的调度 → N01；电视直播间 → A17、X03。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [G01 引擎](G01-引擎/README.md) | media_kit 分支和原生包、mpv 属性、软硬解、取流管线（选源、选路、中继、配方、错误分类）；G01.1 完成，G01.2 高通硬解评估未开始 | 线路和编码标记来自 E 组；会话（G02）调用它；录制（H01）复用中继 |
| [G02 会话和恢复](G02-会话和恢复/README.md) | `PlaybackSession`：打开、看门狗、恢复顺序、租期、点播、状态对账；G02.1 完成，G02.2 未开始 | “正在重连”和转圈怎么画在 A07.7、A07.10；直播间怎么调在 C01 |
| [G03 起播速度和弱网](G03-起播速度和弱网/README.md) | 首帧时间的测量和优化、缓冲策略、弱网体验；G03.1 未开始（第一档） | 改的是 G01 的 mpv 属性和 G02 的时限，先等 G02.2 合并；界面上的加载提示在 A07.7 |
| [G04 画面](G04-画面/README.md) | 画面比例、竖屏预判、旋转；G04.1 完成 | 竖屏排版、三档面板在 A07.3；平台声明的宽高来自 E 组（抖音） |
| [G05 声音和媒体控制](G05-声音和媒体控制/README.md) | 纯音频、音量、系统媒体会话、音频焦点；还没有任务 | 媒体通知和后台在 C01.2、O03；纯音频界面在 A07 |

## 现状（2026-10-07）

- 做到哪（登记表 6 个任务）：
  - 完成 3 个：G01.1 播放核心（`b4fb966e8`）、G02.1 会话和引擎（`4e8cd6c67`）、G04.1 竖屏比例预判（`7b37e6f5f`）。前两个在 K90 冒烟（S02.2）和主流程（S02.3）里随国内平台播放一起看过；**断网重连、高通 HEVC 硬解、纯音频切换、斗鱼续签拼接、Bigo/FC2/niconico 配方没有真机记录**；G04.1 合并在 K90 验证用的构建 `288fec0ec` 之后，CHECKLIST 第 1 节第 8 条至今没结果。这三项登记“完成”而真机证据不全，不符合 PROCESS 3.2（见“当前重点”第 4 条）。
  - 未开始 3 个：G01.2（第二档）、G02.2（第二档）、G03.1（第一档）。
- 和 3.x 比：
  - 一致：恢复顺序、预算和时限（缓冲 12 秒、打开 18 秒、刷新 12 秒、意外暂停 0.35 + 5 秒、两轮延迟 0.75 秒和 2 秒、持续 30 秒恢复预算、停止 45 秒后释放引擎）、mpv 属性（探测 2 MiB / 2 秒、缓存 6 秒、32 MiB / 4 MiB）、错误分类、事件分代、每个房间的音量键名。
  - 有意的差异：只用 mpv（3.x 手机上还有 fijk、exo、fvp，F-ROOM-24 不做）；引擎降级改成硬解 → 软解；请求头跟着线路走，不在播放器里按平台写；HLS 中继改成纯 Dart；删掉 Windows 的虎牙 40 秒热备切换；原生包换成 mpv 0.41.0 + FFmpeg 9.0.2（能直接读 codec 12 的 HEVC FLV）。
  - 多了：FLV 续签无缝拼接修掉 3.x 推迟一个 GOP 的问题；租期切断连接的 HLS（CHZZK、PandaTV）也续签；不切断的租期按 `refreshAt` 预取；线路回退按 CDN 代号记；“优先 H.264”；会话说出“正在恢复、第几次”（B02）；视频帧率（给 R02）；抖音竖屏预判。
  - 少了（本轮读代码发现）：**音频焦点**——3.x 用 `audio_session` 在来电、通知时暂停或压低音量，拔耳机时暂停（`git show v3.2.11:lib/player/core/live_audio_handler.dart:98-176`），4.x 没有接（G05）；Android 上没有画面停住检测（只有 Windows 报画面帧，G02.2 评估）。
- 主要的代码：

| 包或目录 | 职责 |
|---|---|
| `packages/live_media/lib/src/`（`source.dart`、`input.dart`、`transport.dart`、`fallback.dart`、`errors.dart`、`fence.dart`、`proxy.dart`、`relay/`、`inputs/recipes.dart`） | 取流管线，纯 Dart，只依赖 `live_core`、`live_net`；测试 40 个（`dart test`） |
| `packages/live_player/lib/src/`（`session.dart`、`state.dart`、`engine.dart`、`mpv_engine.dart`、`mpv_options.dart`、`diagnostics.dart`、`frame_rate.dart`、`engine_profile.dart`、`video_view.dart`、`screen_wake.dart`、`policies.dart`） | 会话（纯 Dart 部分不引 Flutter）、mpv 引擎绑定、画面组件；测试 36 个 |
| `third_party/media_kit`、`third_party/media_kit_video` | media_kit 1.1.11 / media_kit_video 1.2.5 的补丁分支（上游 Predidit/media-kit `803c4a27`），`hook/native_bundles.json` 列原生包和 SHA-256 |
| `apps/pure_live/lib/app/bootstrap.dart:232-236`、`app/services.dart:78` | 应用里建共用的 `MediaOpener`（播放代理、引擎能力、配方打开器）和 `PlaybackSession` |
| `apps/pure_live/lib/features/live_play/logic/`（`room_controller.dart` 的 `_openQuality`、`_plan`、`_refreshPlan`；`player_standby.dart`；`reconnect_watch.dart`；`background_playback.dart`） | 直播间怎么用会话；多画面在 `features/multiview/logic/multiview_controller.dart` |

## 当前重点和顺序

1. **第一档：G03.1 起播速度和弱网**。用户感觉最直接（PLAN 原则 4“速度优先”），目标是 specs/UI.md 第 9.4 节的“点击直播间到画面出现不超过 v3 的 70%”。先测量（打点、K90 上逐平台各 5 次），再按数字决定改哪一段。依赖：G02.2 先合并（两者都改 `session.dart` 的打开和事件路径）。
2. **第二档：G02.2 缓冲状态对账**。小任务，消掉“画面在动却一直转圈、12 秒后莫名重连”；同时给会话加上恢复原因的日志，G03.1 的测量要用它数重连。
3. **第二档：G01.2 高通硬解评估**。K90 上逐平台看 HEVC 硬解，定“优先 H.264”的默认值；它也是 E06.2（Twitch 按引擎能力请求编码）的输入，并且关系到映客默认就播 HEVC 的问题（见 G01 已知问题）。
4. **补真机证据**：G01.1、G02.1 的断网重连、纯音频切换、斗鱼续签（CHECKLIST 第 1 节第 3、9 条）和 G04.1 的抖音竖屏（第 1 节第 8 条），建议并入 S02.6；看不过的开修补任务。
5. **需要维护者决定开任务的**（本轮发现，没有任务管）：G05 的音频焦点（来电暂停、拔耳机暂停，3.x 有）；G01 的 Steam 分档画质实际仍是自适应（见 G01 已知问题）；映客默认清晰度落在 HEVC 档。

## 风险和注意

- **原生库和分支**：libmpv、FFmpeg 由构建钩子从 Releases 下载并校验 SHA-256，不进 git；换原生包要同时改 `third_party/media_kit/hook/native_bundles.json` 和 `packages/live_player/lib/src/engine_profile.dart` 的 FFmpeg 版本表（决定要不要改写 HEVC FLV）。分支的补丁见 `third_party/media_kit_video/PURELIVE_PATCH.md`，跟进上游时逐条保留。
- **厂商和芯片**：高通、联发科的 MediaCodec 对 HEVC 的表现不同；只在 K90（高通）上测过的结论要写明适用范围。ColorOS、高通设备上截图探测会丢帧（3.x 因此关掉了内容探测，4.x 删除），不要再加每帧截图类的检测。
- **平台改接口**：线路、请求头、租期都来自 E 组，地址失效时会话靠刷新回调重新取；不要在播放层按平台写特例（3.x 的 `playback_header_resolver.dart` 就是这么烂掉的）。
- **并发**：会话的每次打开是一“代”，晚到的结果和事件一律丢弃（`SourceEventFence`、`_session` 计数）；改会话时保持“新输入被引擎接受后才释放旧输入”“用户暂停不被任何看门狗恢复”“缓冲看门狗不被重复通知重置”这三条 3.x 规则，它们都有现成用例。
- **测试**：会话用假引擎（`packages/live_player/test/support/fake_engine.dart`）和 `fake_async`，定时器至少 1 秒、不访问真实平台（D-017）；中继测试在本机回环上起真实 HTTP 服务。
- **设置**：3.x 的播放设置键（`enableCodec`、`videoHardwareDecoder`、`playerCompatMode`、`customPlayerOutput`、`room_vol_*`……）键名和含义不变（D-018）；`preferH264`、`matchVideoFrameRate` 是 4.x 新加的，可以改默认值。
- 代码注释里的旧编号（M7.1、M7.2、U.2i、F.1b、P01、B02）：找文档时先查 [MAPPING.md](../MAPPING.md)。

## 相关

- 规范：[specs/ENGINEERING.md](../specs/ENGINEERING.md)（第 4 节分层：`live_media` 纯 Dart、`live_player` 的会话不引 Flutter；第 5 节上游仓库）；[specs/UI.md](../specs/UI.md) 第 9.2～9.4 节（视频不圆角不裁剪、播放器只有一份、起播时间指标）；[specs/UPGRADES.md](../specs/UPGRADES.md) 统一原则“默认编码”和 6-1、6-4、8-8、11-1、14-5、22-2、22-3、26-2、27-7、29-8、30-2、33-2。
- 决定：D-001、D-017、D-018、D-019（K90 随时可用）、D-027（上游对照，G02.2 来自它）。
- 其他组：A07（直播间界面：转圈、重连提示、清晰度菜单、纯音频封面）、C01、C02（直播间、播放器复用）、E 组（线路、编码、租期）、H01（中继复用）、N01（多画面）、O02、O03（小窗、后台、媒体通知）、Q02（播放代理）、R02（帧率和刷新率）、S02（真机清单第 1 节）、W01.1（上游对照）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`█████████████████░░░` 85%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [G01 引擎](G01-引擎/README.md) | media_kit 分支、libmpv 和 FFmpeg 原生包、软硬解、取流管线。 | `█████████████░░░░░░░` 65% | 2 / 4 |
| [G02 会话和恢复](G02-会话和恢复/README.md) | 打开、恢复重连、换线、卡住检测、状态对账。 | `████████████████████` 98% | 2 / 3 |
| [G03 起播速度和弱网](G03-起播速度和弱网/README.md) | 首帧时间、缓冲策略、弱网体验。 | `██████████████████░░` 90% | 0 / 1 |
| [G04 画面](G04-画面/README.md) | 画面比例、方向、竖屏预判。 | `████████████████████` 100% | 1 / 1 |
| [G05 声音和媒体控制](G05-声音和媒体控制/README.md) | 纯音频、音量、系统媒体会话。 | `██████████████████░░` 90% | 0 / 1 |

## 还没完成的（5）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [G03.1](G03-起播速度和弱网/G03.1-起播速度和弱网/README.md) 起播速度和弱网：测首帧时间，找出慢的环节，改进后真机对比 | 待真机 | 第一档 | 4/4 |
| [G01.2](G01-引擎/G01.2-高通硬解评估/README.md) 高通硬解评估：在 K90 上看 HEVC 硬解，定“优先 H.264”的默认值（UPGRADES 22-3） | 未开始 | 第二档 | 0/2：下一阶段“K90 上逐平台测 HEVC 硬解” |
| [G02.2](G02-会话和恢复/G02.2-缓冲状态对账/README.md) 缓冲状态对账：画面帧在走时补回“播放中”，不再被当成卡住去重连 | 待真机 | 第二档 | — |
| [G05.1](G05-声音和媒体控制/G05.1-音频焦点/README.md) 音频焦点：来电时暂停、拔耳机时暂停（3.x 用 audio_session） | 待真机 | 第二档 | 2/2 |
| [G01.4](G01-引擎/G01.4-Steam选清晰度实际仍是自适应/README.md) Steam 选清晰度实际仍是自适应：用档位限定 HLS 变体 | 待真机 | 第三档 | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
