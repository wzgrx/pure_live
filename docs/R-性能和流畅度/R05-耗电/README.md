# R05 耗电

看直播费不费电：前台播放（不同刷新率档位、硬解和软解、弹幕多少）、纯音频、后台播放和锁屏、长时间挂着时的耗电，以及和 3.x 的对比。耗电没有单独的代码，是刷新率、解码、渲染、网络、唤醒锁这些选择的总和，所以本子分类只管测量和结论，改动开到对应的组。

## 范围

- 包括：
  - 测量方法：`dumpsys batterystats`（按应用的估算耗电）、`dumpsys battery`（电量）、`dumpsys thermalservice`（温度）、可选 Perfetto 的电源轨道；固定条件（亮度、音量、网络、不充电）。
  - 耗电相关的开关和它们的代价：“界面刷新率”三档和帧率匹配（R02）、硬解 / 软解和“优先 H.264”（G01、G01.2）、弹幕帧率（D03、D05）、纯音频（G05：Android 只关视频输出，解码照旧）、后台播放的唤醒锁和 Wi-Fi 锁（`features/live_play/logic/background_playback.dart` 的 `BackgroundKeepAlive`）、屏幕常亮（O05.1）、持续出帧的动画（R01.1 去掉的转圈）。
  - 和 3.x 的对比结论（specs/UI.md 9.1 节和 V03.2 调研：新做法的省电档不能比 3.x 的省电档更耗电）。
- 不包括（归哪里）：
  - 上面那些开关本身的实现和默认值 → R02（刷新率）、G01（解码）、D03/D05（弹幕帧率）、G05（纯音频）、C02/O03（后台）、O05（常亮）；本子分类测出问题后开到这些组。
  - 录制的耗电（前台服务、FFmpeg）→ H 组。
  - 发热导致的系统降频（`thermal_limit_refresh_rate`）只记录，不处理。

## 现状：做到哪、怎么工作的

- 用户看得到的：没有耗电相关的界面；相关的选择分散在设置里——“界面刷新率”默认省电（3.x 默认）、“播放时匹配视频帧率”默认开、“硬件解码”默认开、“优先 H.264”默认开、“屏幕常亮”默认开、“后台播放”默认关。
- 和耗电有关的现有行为：
  - 刷新率：默认省电档播放时只声明视频本身的帧率，系统选整数倍（多半 60 Hz）；均衡档空闲 60、操作时 120，24/25/50 帧空闲也是 120（D-010，R02.2 的“手感和耗电的变化”：更匀也更耗电）；最高档一直最高（明显更耗电）。
  - 渲染：弹幕层没有弹幕时停（D03.1）；R01.1 去掉了浮窗透明和转圈的离屏绘制、列表尾多余的转圈；静止的列表不出帧（`popular_test` 有用例）。
  - 解码：硬解 `auto-safe`（`packages/live_player/lib/src/mpv_options.dart:88-96`），失败时软解（软解明显更耗电、更热）。
  - 纯音频：Android 关控制器的视频输出（`mpv_engine.dart:232-233`），mpv 仍在解码视频（切回更快，但省电不如不解码）。
  - 后台：开着后台播放或助眠时持有唤醒锁和 Wi-Fi 锁（`BackgroundKeepAlive`，通道 `pure_live/background_playback`），离开直播间释放；没开时离开应用 1.5 秒后暂停。
  - 屏幕常亮：只在播放或缓冲时（O05.1，`packages/live_player/lib/src/screen_wake.dart`）。
- 完成度：**没有任何耗电数字**。R02.1 的设计“以后在 K90 上怎么测”和 V03.2 调研 4.3 节写了方法，R02.2 的记录把耗电对比交给了后面，一直没人测；“省电档不高于 3.x”没判定。

## 代码地图

本子分类没有自己的代码；和耗电直接相关的位置：

| 文件 | 和耗电的关系 |
|---|---|
| `apps/pure_live/lib/platform/display_mode.dart:142-148`（`playbackRefreshRate`）、`packages/live_ui/lib/src/widgets/refresh_rate.dart`（三档） | 刷新率（R02） |
| `packages/live_player/lib/src/mpv_options.dart:88-99`、`:133-158` | 硬解选择、缓冲（G01） |
| `packages/live_store/lib/src/settings/settings.dart:289`（`enableCodec`）、`:293`（`preferH264`）、`:64`（`refreshRateMode`）、`:73`（`matchVideoFrameRate`）、`:33`（`enableScreenKeepOn`）、`:21`（`enableBackgroundPlay`） | 默认值 |
| `packages/live_player/lib/src/mpv_engine.dart:230-258` | 纯音频只关视频输出（G05） |
| `apps/pure_live/lib/features/live_play/logic/background_playback.dart`（`BackgroundKeepAlive`、`RoomBackgroundPolicy`） | 后台的唤醒锁、离开应用后暂停（C02、O03） |
| `packages/live_player/lib/src/screen_wake.dart`、`video_view.dart` | 屏幕常亮只在播放或缓冲（O05.1） |
| `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`、`danmaku_templates.dart` 的 `resolvedDanmakuFps` | 弹幕帧率（D03、D05） |

测试：没有耗电测试（只能真机测）。相关的行为测试在各组：`room_refresh_rate_test.dart`（选法）、`popular_test.dart`（静止不出帧）、O05.1 的常亮用例。

## 3.x 基线

- 3.x 的“界面刷新率”默认省电（`git show v3.2.11:lib/common/widgets/adaptive_refresh_rate_scope.dart`），播放时不按帧率选；弹幕帧率省电档上限 60（`lib/common/services/settings/danmaku_settings_controller.dart:158`）。
- 3.x 有截图探测（默认关）和多引擎（fvp 等），4.x 都去掉了。
- 3.x 在 K90 上是用户的正式包，**不能拿来测**；对比要另装改包名的 v3.2.11 构建（`com.mystyle.purelive.v3bench`，和 G03.1、R04.1 共用）。
- specs/UI.md 第 9.1 节、V03.2 调研 1.5 节和 4.3 节第 6 条：`dumpsys batterystats --reset`，固定亮度看 30 分钟，新做法的省电档不能比 3.x 省电档更耗电。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有任何耗电数字；“省电档不高于 3.x”没判定 | — | 不知道 4.x 比 3.x 费不费电 | R05.1 |
| 均衡档看 24/25/50 帧时空闲也用 120 Hz（144/165 Hz 屏用最高），更耗电 | `display_mode.dart:146` | R02.2 记录已写明的代价；144/165 Hz 屏的上限等维护者决定 | R05.1 测 K90 上的代价；R02 决定是否限 120 |
| 纯音频仍在解码视频 | `mpv_engine.dart:232-233` | 纯音频省电不如 `vid=no`（3.x 同样） | R05.1 测差多少；差得多时在 G05 开任务（例如纯音频超过 N 分钟改 `vid=no`） |
| HEVC 硬解和 H.264 的耗电差没测 | G01.2 | “优先 H.264”默认值缺依据 | G01.2 测 15 分钟的电量差，R05.1 引用 |

## 相关决定和规范

- D-010：刷新率策略（耗电是它的代价之一）。
- D-019：不碰 3.x 和正式包；K90 随时可用。
- [specs/UI.md](../../specs/UI.md) 第 9.1 节（省电默认、最高档更耗电）；[V03.2 调研](../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 1.5 节（耗电来自屏幕和每帧渲染；LTPO 在不出帧时自己降）、4.3 节第 6 条。

## 测试和验证

- 自动测试：无（耗电只能真机）。
- 真机：R05.1 的测量矩阵；结论写进 R05.1 的记录。

## 路线

1. R05.1（第三档）：K90 上前台播放 30 分钟 × 三档刷新率、纯音频、后台锁屏的耗电，和 v3bench 包对比。
2. 测出明显的问题时开到对应的组（R02、G05、D05、O05），不在本子分类改代码。
3. 以后：Windows 笔记本的耗电（X01）。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [R 性能和流畅度](../README.md)。

- 代码：横跨
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| R05.1 | 耗电：播放 30 分钟耗电对比（省电档不高于 3.x） | 性能 | 未开始 | — | — | [设计或说明](R05.1-耗电/README.md)、[任务书](R05.1-耗电/brief.md) |

## 还没完成的

- **R05.1 耗电：播放 30 分钟耗电对比（省电档不高于 3.x）**（未开始，第三档，规模 中）

<!-- docs:生成结束 -->
