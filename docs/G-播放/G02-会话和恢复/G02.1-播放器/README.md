# G02.1 播放器：会话、恢复、Flutter 绑定

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构）
- 来源：4.x 逐块重构计划（D-001）的播放第二块：3.x `lib/player/` 里依赖 Flutter 和引擎的部分（`player_manager.dart` 的会话和恢复、`media_kit_adapter.dart`、`global_player_service.dart` 等），以及 media_kit 分支和 libmpv 的取得方式，搬进 `packages/live_player`
- 旧编号：M7.2、T04b.1
- 相关：决定 D-001、D-017、D-018；前一块 [G01.1](../../G01-引擎/G01.1-播放核心/README.md)；接入应用 I01.1、直播间 C01（当时的 M13）；后续 [G02.2](../G02.2-缓冲状态对账/README.md)、[G04.1](../../G04-画面/G04.1-竖屏流的画面比例预判/README.md)；记录 [record.md](record.md)

## 目标

- 3.x 一个 5028 行的 `PlayerManager` 同时管会话、恢复、画中画、小窗、界面，还是全局单例；拆出只管播放的 `PlaybackSession`（纯 Dart，不引 Flutter），由应用注入，多画面每格一个。
- 只留 mpv 一个引擎（PLAN、ENGINEERING 第 4 节），引擎降级改成硬解 → 软解。
- 恢复顺序、预算、时限、去重、排队全部照 3.x，用假引擎写成能单测的形式。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 现在（文件:行） | 结果 |
|---|---|---|---|
| 会话和恢复 | `player/core/player_manager.dart`（约 1800 行，时限 `:297-306`） | `packages/live_player/lib/src/session.dart` `PlaybackSession` | 顺序、时限、去重照 3.x；GetX 状态换成 `PlaybackState` |
| 全局播放器 | `player/global_player_service.dart:16`（单例） | 删除；应用持有会话（`app/services.dart:78` `newPlaybackSession`） | 有意差异 |
| 引擎接口 | `player/interface/unified_player_interface.dart` 等七个可选能力接口 | `engine.dart` 一个 `PlayerEngine` | 收窄 |
| mpv 适配 | `player/adapters/media_kit_adapter.dart`（1266 行，读全局设置 `:106-127,266-303`） | `mpv_engine.dart`、`diagnostics.dart`、`mpv_options.dart`（设置由 `MpvEngineConfig` 传入） | 诊断窗口、纯音频、帧进度照 3.x |
| 备用引擎 | `fijk_adapter.dart`、`video_player_adapter.dart`、`fvp_adapter.dart`（1260 行） | 删除 | 只用 mpv（F-ROOM-24 不做） |
| 音量 | `media_kit_adapter.dart:615-620` 打开时读房间音量，手机强制 1.0 | `PlaybackRequest.volume` + `policies.dart` `roomVolume`（键名不变） | 规则不变，位置变了 |
| Windows 热备切换 | `player_manager.dart:216-226,4170-4230,4582-4597`（虎牙 40 秒） | 删除；租期切断由线路标明、中继续签 | 有意差异 |
| 截图探测 | `media_kit_content_probe.dart`、`active_video_content_analyzer.dart`（默认关，`player_manager.dart:313`） | 删除 | 3.x 也没在用 |
| media_kit 分支 | `third_party/media_kit`（`d13fc22b`） | `third_party/media_kit`、`media_kit_video`（上游 `803c4a27`，补丁同 3.x） | 跟进上游的空属性保护和 flag 按 32 位读 |
| 原生库 | libmpv + FFmpeg 7.1 | 构建钩子下载 mpv 0.41.0 + FFmpeg 9.0.2（Android arm64、armeabi-v7a、x86_64，Linux x64），校验 SHA-256 | 能直接读 codec 12 的 HEVC FLV |

## 结果

- 改动（提交 `4e8cd6c67`，2026-10-01，“feat(live_player): media_kit fork, mpv engine and playback session”）：
  - c1 media_kit 分支放进 `third_party/`，根 `pubspec.yaml` 的 `dependency_overrides` 指向它；`xml`、`wakelock_plus` 覆盖成最新稳定版。
  - c2 原生库由 media_kit 的构建钩子按 `third_party/media_kit/hook/native_bundles.json` 下载、校验，不进 git。
  - c3 `PlayerEngine` 接口和 `MpvEngine`：建播放器后设一次直播属性；每次打开设 `hwdec` 和 `http-proxy`；诊断门；纯音频（Android 用分支的 `setVideoOutputEnabled`，桌面 `vid=no`，切回等出画面最多 2.8 秒）；Windows 的 `frameRevision`。
  - c4 `PlaybackSession`：打开、状态、分代、看门狗、恢复顺序、租期预取、点播、停止和 45 秒闲置释放。
  - c5 `LiveVideoView`：没有引擎时黑底，有了是 media_kit 的 `Video`（无控件，不随前后台自动暂停）。
  - c6 `mpvEngineProfile()`：按 ABI 查原生包的 FFmpeg，决定要不要改写 HEVC FLV。
  - c7 策略：`shouldContinueInBackground`、`roomVolumeKey`、`roomVolume`。
- 修掉的 3.x 问题：8 个（记录“审查发现的 v3 问题”表：全局单例、适配器读全局设置、多引擎、音量写在引擎里、热备切换、分支读 flag 的位数、多余参数、截图探测残留）。
- 后来的改动（同一文件，按时间）：`c6def3c0b` 视频帧率（R02.1）；`47721f9f5` 创建中被释放；`2f4aed12b` 重叠的停止不误释放；`50143b27e` 会话说出“正在恢复、第几次”（B02）。
- 测试：当时 23 个（`session_test` 13、`diagnostics_test` 4、`options_test` 5、`view_test` 1）；现在 `session_test` 21 个、另有 `frame_rate_test` 5 个。

## 验证

- 自动测试：`cd packages/live_player && flutter test`（假引擎，不需要 libmpv 运行）。
- 真机：没有单独的 verify.md。K90 冒烟（[S02.2](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）里进直播间、出画面、切清晰度、后台播放通过；断网重连、高通 HEVC 硬解、Windows 画面停住重建、纯音频切换在 S02.3 记为“没测”（[S02.3 记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) 末尾）。

## 留下的问题

- 缓冲状态没有和画面、位置对账：[G02.2](../G02.2-缓冲状态对账/README.md)。
- Android 上没有画面停住检测（只有 Windows 报画面帧）：在 G02.2 里评估。
- “优先 H.264”默认值等高通真机硬解验证：[G01.2](../../G01-引擎/G01.2-高通硬解评估/README.md)（V03.3 核对时开的）。
- 断网重连、纯音频切换、Windows 画面停住重建没有真机结果：任务登记为“完成”但关键恢复路径缺 K90 记录，建议 CHECKLIST 第 1 节第 3、9 条并入 S02.6。
- 系统媒体通知、后台、生命周期（记录里“放到 I01.1”的部分）已在 C01.2、O03.2 接上；音频焦点（3.x 的来电、拔耳机暂停）没有接，见 [G05](../../G05-声音和媒体控制/README.md#已知问题和限制)。
