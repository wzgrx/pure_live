# R 性能和流畅度

全应用的“快不快、顺不顺、费不费”：用数字说话的基准和测量方法（帧时间、内存、耗电、启动时间），屏幕刷新率的策略和视频帧率匹配，图片和长时间播放的内存，冷启动到首页可用的时间，播放和后台的耗电。功能能用以后，用户最先感觉到的就是这些，但它们横跨各组、每一项都要先测再改，所以排在功能组和网络之后。

## 范围

- 管什么：
  - 基准和测量（R01）：`apps/pure_live/integration_test/`（profile 模式的帧基准，`perf_test.dart` 9 组场景、`perf/frame_report.dart` 的 P90/P99/卡顿判定）；在 K90 上怎么跑、怎么判定；基准驱动的渲染开销决定（封面圆角）。
  - 刷新率（R02）：`platform/display_mode.dart`（`DisplayMode`：请求刷新率、读回当前值、厂商限制检测）、`live_ui` 的 `AdaptiveRefreshRateController`（省电 / 均衡 / 最高三档）、`features/live_play/logic/room_refresh_rate.dart`（播放中按视频帧率声明）、Android `MainActivity.kt` 的 `applyRefreshRate`、`applySurfaceFrameRate`；设置“界面刷新率”“播放时匹配视频帧率”的行为。
  - 内存和图片（R03）：解码后图片的缓存上限（`app/bootstrap.dart` 的 `decodedImageBudget`）、图片按显示尺寸解码（`memCacheWidth`）、长时间播放和进出直播间的内存。
  - 启动速度（R04）：从点图标到首页可用的时间（`main.dart`、`app/bootstrap.dart`、`app/startup.dart`、启动页）。
  - 耗电（R05）：播放、后台、高刷新率下的耗电测量和对比。
- 不管什么：
  - 手感（拖动、回弹、动画曲线）→ [A03 动效和手感](../A-界面设计/A03-动效和手感/README.md)；尺寸分档和窗口适配 → A04。
  - 起播速度（点进直播间到第一帧）和弱网 → [G03](../G-播放/G03-起播速度和弱网/README.md)（R01 的方法可以复用，但任务在 G03.1）。
  - 弹幕的帧率、排队、Picture 缓存和每秒 200 条的基准 → D03、D04（`chat_benchmark_test.dart`）；本组的基准只把弹幕当场景之一。
  - 刷新率的系统部分（方向、常亮、画中画）→ O05；设置页“界面刷新率”一行的样子 → A11.1（本组管行为和下面的限制提示）。
  - 多画面的格数上限按设备能力 → N01。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [R01 基准和测量](R01-基准和测量/README.md) | profile 帧基准、K90 实测、帧时间统计、渲染开销（R01.1 待真机、R01.2 未开始） | 给 R03（进出直播间 20 次的内存）、A03（拖动手感的帧时间）、D04（弹幕）提供测量工具 |
| [R02 刷新率](R02-刷新率/README.md) | 30～240 Hz 屏的刷新率策略、视频帧率匹配、厂商限制提示（R02.1 完成、R02.2 待真机） | 帧率来自 G01 的 `MpvEngine`；弹幕帧率跟刷新率（D03.1）；D-010 |
| [R03 内存和图片](R03-内存和图片/README.md) | 图片解码和缓存、长时间播放的内存（R03.1 未开始） | 图片的磁盘缓存和代理在 Q02；封面组件在 `live_ui`（A02） |
| [R04 启动速度](R04-启动速度/README.md) | 冷启动到首页可用的时间（R04.1 未开始） | 启动页的样子 A06.4；启动时的数据迁移 J06 |
| [R05 耗电](R05-耗电/README.md) | 播放 30 分钟、后台、高刷新率的耗电（R05.1 未开始） | 刷新率策略（R02）是耗电的主要变量；后台播放 C02、O03 |

## 现状（2026-10-07）

- 做到哪（登记表 7 个任务）：
  - 完成 1 个：R02.1 刷新率和帧率匹配（`b8462638a`，有设计和评审页）。**它的真机验证其实是 R02.2 的 verify 一起做，R02.1 本身没有 K90 记录**（记录“没验证的”写着 K90 支持哪些刷新率、闪不闪屏、耗电都要真机看；K90 的显示模式后来由 V03.2 调研只读测过）。
  - 待真机 2 个：R01.1 基准测试和渲染开销（`2ec6f598e`）、R02.2 刷新率策略修正（`584da6662`）；各有 `verify.md`。
  - 未开始 4 个：R01.2（第二档，K90 跑基准、按数字决定封面圆角）、R04.1（第二档，启动速度）、R03.1（第三档，内存）、R05.1（第三档，耗电）。
- 和 3.x 比：
  - 一致：“界面刷新率”三档（省电交给系统、均衡按下和滚动时最高、停下 1.5 秒回落、进后台释放、画中画保持），默认省电；手机图片缓存 160 张 / 48 MiB（电脑 240 张 / 72 MiB）。
  - 多了：播放中按视频帧率声明刷新率（R02.1、R02.2，D-010）；厂商把应用限制在 60 Hz 时设置里提示（R02.2）；内存大于 4 GiB 的手机图片缓存放宽到 320 张 / 128 MiB（R01.1 c3）；去掉浮窗拖动的透明和转圈的 ShaderMask（R01.1 c2）；profile 帧基准（3.x 没有）。
  - 没有数字：3.x 和 4.x 的启动时间、内存、耗电都没测过；R01.1 的基准没在 K90 上跑过——specs/UI.md 第 9.4 节的五个指标（冷启动不超过 v3 的 60%、进房不超过 v3 的 70%、滚动 P90 ≤8 毫秒、弹幕 200 条 ≤3 毫秒、进出 50 个直播间内存不涨）一个都没判定。
- 主要的代码：

| 包或目录 | 职责 |
|---|---|
| `apps/pure_live/integration_test/`（`perf_test.dart` 359 行、`perf_driver.dart`、`perf/bench_app.dart`、`perf/frame_report.dart`、`perf/frame_requests.dart`） | profile 帧基准：假平台、本机封面服务器、假播放器，结果写 `build/perf/perf-<时间>.json` |
| `apps/pure_live/lib/platform/display_mode.dart`（376） | `DisplayMode`：刷新率请求、`playbackRefreshRate` 的选法、厂商限制检测 |
| `packages/live_ui/lib/src/widgets/refresh_rate.dart` | `RefreshRateMode`、`AdaptiveRefreshRateController`、`AdaptiveRefreshRateScope`（3.x 的三档） |
| `apps/pure_live/lib/features/live_play/logic/room_refresh_rate.dart`（77） | `RoomRefreshRate`：播放中把帧率和档位交给 `DisplayMode` |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | `applyRefreshRate`（`:784`）、`applySurfaceFrameRate`（`:842`）、`displayModeInfo`（`:875`） |
| `apps/pure_live/lib/app/bootstrap.dart:31-77` | 图片缓存上限 `configureDecodedImageCache`、`decodedImageBudget`、`readTotalMemoryBytes` |
| `apps/pure_live/lib/main.dart`、`app/bootstrap.dart`、`app/startup.dart`、`features/splash/splash_page.dart` | 启动路径（R04） |

## 当前重点和顺序

1. **待真机的两个先看**（R02.2、R01.1 的 verify.md）：R02.2 关系到每天看直播的刷新率和耗电；R01.1 的基准跑一次就能给 R01.2（封面圆角）、R03.1（进出直播间的内存）提供第一批数字。两个可以同一次连 K90 做。
2. **第二档：R01.2**（跑完 R01.1 的基准就能决定，规模小）、**R04.1 启动速度**（PLAN 第二档列有“K90 上跑基准、启动速度”；先测量）。
3. **第三档：R03.1 内存、R05.1 耗电**：R05.1 的对比对象是 3.x 省电档，3.x 在 K90 上是用户的正式包、不能动，要另装改包名的 3.x 构建（和 G03.1 的 3.x 基线共用一个包）。
4. 建议：把 R02.1 的“完成”和真机证据对齐——R02.2 的 verify 通过后在 R02.1 的记录里补一句“K90 结果见 R02.2 verify.md”。

## 风险和注意

- **只在 profile 模式、真机上的数字算数**：debug 和无头测试器的帧时间没有意义（R01.1 记录：无头测试器改成手机尺寸后不做光栅，raster 全是 0）；`dumpsys gfxinfo` 统计普通 View 窗口，对 Flutter 画面不准（V03.2 调研 4.3 节）。用 `SchedulerBinding.addTimingsCallback`、Perfetto 的 FrameTimeline、`dumpsys SurfaceFlinger`。
- **厂商限制**：HyperOS 有自己的刷新率投票（`PRIORITY_MIUI_REFRESH_RATE`），应用压不过；OnePlus/OPPO 名单制；三星全屏视频降 60。对策是读回当前值、限制时提示用户（D-010），不追求绕过。只投具体数值，不投类别（K90 的 HIGH 类别只给 90）；清单不声明 `appCategory=game`（Android 15 起游戏默认 60 Hz），有测试守着。
- **测试和基准里的定时**：单元测试的定时器至少 1 秒（D-017）；基准只统计应用要的帧（`frame_requests.dart`），不然空帧会把卡顿率摊薄。
- **不碰 3.x**：3.x 在 K90 上是用户的正式包（D-019）；对比 3.x 只能另装改包名的构建，测完卸载。
- **耗电和内存测量的误差**：同一时段、同一房间、固定亮度和音量、不充电；每组至少两次。
- 代码注释里的旧编号（U.2i、P01、P05、D2）：找文档先查 [MAPPING.md](../MAPPING.md)。

## 相关

- 规范：[specs/UI.md](../specs/UI.md) 第 9 节（9.1 刷新率、9.2 流畅度要求、9.3 性能对设计的约束、9.4 指标和验证）；[V03.2 调研报告](../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md)（第 1 节刷新率、第 4 节渲染性能）。
- 决定：D-010（刷新率：播放中只用帧率声明、没有整数倍取最高、限制时提示）、D-017、D-019、D-003（R02.1 的 I1～I3 按建议 A）。
- 其他组：A03（手感）、A04（尺寸）、A11.1（设置页）、D03、D04（弹幕性能）、G01（视频帧率）、G03（起播速度）、O05（方向、刷新率的系统部分）、S02（真机清单第 1 节第 18 条）、N01（多画面）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`█████████░░░░░░░░░░░` 43%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [R01 基准和测量](R01-基准和测量/README.md) | profile 基准、K90 实测、帧时间统计、渲染开销。 | `████████████░░░░░░░░` 60% | 0 / 2 |
| [R02 刷新率](R02-刷新率/README.md) | 30～240 Hz 屏幕的刷新率策略和帧率匹配。 | `███████████████████░` 95% | 1 / 2 |
| [R03 内存和图片](R03-内存和图片/README.md) | 图片解码和缓存、长时间播放的内存。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |
| [R04 启动速度](R04-启动速度/README.md) | 冷启动到首页可用的时间。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |
| [R05 耗电](R05-耗电/README.md) | 播放、后台、高刷新率下的耗电。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |

## 还没完成的（6）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [R01.2](R01-基准和测量/R01.2-在K90上跑基准/README.md) 在 K90 上跑基准，按数字决定封面圆角画法 | 未开始 | 第二档 | 0/2：下一阶段“跑基准” |
| [R04.1](R04-启动速度/R04.1-启动速度/README.md) 启动速度：冷启动到首页可用的时间测量和优化 | 未开始 | 第二档 | 0/3：下一阶段“测量” |
| [R03.1](R03-内存和图片/R03.1-内存/README.md) 内存：长时间播放和快速滚动后内存稳定 | 未开始 | 第三档 | — |
| [R05.1](R05-耗电/R05.1-耗电/README.md) 耗电：播放 30 分钟耗电对比（省电档不高于 3.x） | 未开始 | 第三档 | — |
| [R01.1](R01-基准和测量/R01.1-基准测试和渲染开销/README.md) 基准测试和渲染开销：profile 基准、浮窗和转圈不再离屏绘制、图片缓存上限 | 待真机 | — | — |
| [R02.2](R02-刷新率/R02.2-刷新率策略修正/README.md) 刷新率策略修正：播放中只用帧率声明、没有整数倍取最高、系统限速提示 | 待真机 | — | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
