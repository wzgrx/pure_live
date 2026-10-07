# R01 基准和测量

怎么用数字判断“顺不顺”：profile 模式下的帧基准（热门快速滚动、每秒 50/200 条弹幕、4 格多画面、设置页滚动、进出直播间 20 次、封面圆角三种画法）、在 K90 上怎么跑和怎么判定，以及由基准数字决定的渲染开销改动。

## 范围

- 包括：
  - `apps/pure_live/integration_test/`：`perf_test.dart`（场景）、`perf_driver.dart`（`flutter drive` 的主机端，写 JSON）、`perf/frame_report.dart`（`FrameRecorder`、`Percentiles`、`FrameReport` 和 V03.2 调研 4.1 节的判定）、`perf/frame_requests.dart`（只统计应用要的帧）、`perf/bench_app.dart`（假平台、本机封面服务器、弹幕源、等待工具、`residentMiB`）。
  - 判定标准（V03.2 调研 4.1 节、specs/UI.md 第 9.4 节）和在 K90 上的跑法。
  - 由基准决定的渲染开销改动：R01.1 的浮窗不透明、默认转圈改画法、列表尾转圈只在加载更多时出现、图片缓存上限（D2）；R01.2 的封面圆角（P4）。
- 不包括（归哪里）：
  - 起播时间的打点和测量 → G03.1；弹幕每秒 200 条的单元基准（`apps/pure_live/test/features/live_play/chat_benchmark_test.dart`）→ D04.1；刷新率和帧率匹配 → R02；内存的专门测量 → R03.1（用本子分类的 `room_enter_exit_20` 场景）；启动时间 → R04.1；耗电 → R05.1。
  - 拖动手感、动画曲线 → A03（它们的帧时间可以用本基准的写法测）。

## 现状：做到哪、怎么工作的

- 用户看得到的（R01.1 c2、c3，已合并、待真机）：应用内浮窗拖动时画面不再变暗（以前 80% 不透明）；默认加载转圈外观不变、画法改了（不再离屏绘制）；热门、分区下拉刷新时列表尾不再跟着转圈；内存大于 4 GiB 的手机来回滑热门时少重新解码封面。
- 基准怎么工作：
  1. `perf_test.dart` 用真实的 `PureLiveApp` + 内存数据库 + 假平台（`BenchSite`，300 个直播间，每页 300 毫秒才返回）+ 本机 127.0.0.1 上的封面服务器（每个房间自己的封面地址，照真实情况下载解码）+ 测试自己发的弹幕（`DanmakuHub`，每 20 毫秒一批）+ 不出画面的假播放器，不连任何真实平台。
  2. 每个场景 `measure(...)` 期间 `FrameRecorder`（`frame_report.dart:11`）用 `SchedulerBinding.addTimingsCallback` 收每帧的 build、raster、总时长；`frame_requests.dart` 记下哪些帧是应用要的，只统计这些（集成测试的绑定画过一帧后会自己一直要下一帧，空帧会把卡顿率摊薄；JSON 的 `extra.idleFramesLeftOut` 是去掉的数）。
  3. `FrameReport`（`:128`）算 P50/P90/P99/最大/平均、卡顿帧数和卡顿率、最长连续卡顿，按 4.1 节判定：build 和 raster 的 P90 ≤ 1 个刷新周期（直播间和多画面的 raster ≤ 0.6 个周期）、P99 ≤ 1.5 个周期（`:249-250`）、卡顿帧 <1%、没有连续两帧卡顿；`danmaku_200` 另要 build P90 ≤3 毫秒。
  4. 刷新周期：`--dart-define=PERF_HZ=120` 固定按 120 Hz（8.33 毫秒），不加时按系统报的刷新率（`bench_app.dart:35-37`、`:88`）；基准把“界面刷新率”设成最高档，一直最高刷新率。
  5. `perf_driver.dart` 把结果写成 `apps/pure_live/build/perf/perf-<时间>.json`，控制台每个场景一行（帧数、P90/P99、卡顿率、PASS/FAIL）；`device` 里有刷新率、内存、图片缓存上限。
  6. `PERF_QUICK=true` 缩短窗口（3 秒、3 次甩动、3 次进出），只用来确认能跑。
- 场景（9 组数字）：`hot_scroll`（热门 300 个房间快速甩到底再回来）、`danmaku_50`、`danmaku_200`（直播间每秒 50、200 条，列表和画面上都有）、`multiview_4`（4 格，选中格每秒 50 条）、`settings_scroll`、`room_enter_exit_20`（从热门进出直播间 20 次，附每次退出后的常驻内存）、`cover_corners_clipOverFade` / `clip` / `decoration`（P4 的三种封面圆角画法）。
- 完成度：基准在本机无头跑通（7 个集成测试），profile 包能编译；**K90 上一次没跑过**，所以 4.1 节的标准、specs/UI.md 9.4 节的指标都没判定，P4 也没法决定（R01.2）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/integration_test/perf_test.dart`（359 行） | 场景：窗口 10 秒 / 甩 12 次 / 进出 20 次（快速版 3 / 3 / 3，`:37-46`）；热门 `:125`、直播间弹幕 `:138`、多画面 `:161`、设置 `:201`、进出直播间 `:218`、封面圆角 `:246`；`CoverCorners`（`:272`）、`CornerGrid`（`:287`，`clipOverFade` `:312`、`clip` `:319`、`decoration` `:323`）；手机尺寸 1200×2607（`:83`） |
| `apps/pure_live/integration_test/perf_driver.dart`（39） | 主机端：30 分钟超时，写 JSON |
| `apps/pure_live/integration_test/perf/frame_report.dart`（297） | `FrameRecorder`（`:11`，收尾等 1.5 秒 `:25`）、`Percentiles`（`:87`，最近秩）、`FrameReport`（`:128`，判定 `checks` `:244-252`、`passed` `:257`、JSON `:259` 起） |
| `apps/pure_live/integration_test/perf/frame_requests.dart`（46） | `FrameRequests`：记下应用要的帧 |
| `apps/pure_live/integration_test/perf/bench_app.dart`（401） | `perfQuick`（`:33`）、`perfHz`（`:37`）、`benchRoomCount` 300（`:40`）、`BenchEnvironment`（`:43`，设和应用一样的图片缓存上限）、`CoverServer`（`:99`）、`BenchSite`（`:211`）、`DanmakuHub`（`:241`）、`BenchApp`（`:296`）、`residentMiB`（`:401`，`ProcessInfo.currentRss`） |
| `packages/live_ui/lib/src/widgets/loading_styles.dart` | 默认转圈：`CustomPaint` + `Paint.shader`，自己的重绘边界（R01.1 c2） |
| `apps/pure_live/lib/features/live_play/mini/floating_window.dart` | 浮窗拖动不再包 `AnimatedOpacity`（R01.1 c2） |
| `apps/pure_live/lib/shared/rooms/room_grid.dart` | 顶部进度条和列表尾转圈各自 `RepaintBoundary`，列表尾只在加载更多时转（R01.1 c2） |
| `apps/pure_live/lib/app/bootstrap.dart:31-77` | `configureDecodedImageCache`（`:34`）、`largeImageBudgetAbove` 4 GiB（`:43`）、`decodedImageBudget`（`:54`）、`readTotalMemoryBytes`（`:65`） |
| `packages/live_ui/lib/src/widgets/live_room_card.dart:362` | 卡片封面唯一的裁剪 `ClipRRect`（P4 的对象；`:718` 是列表行 16 像素平台标志的小裁剪） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/integration_test/perf_test.dart`（7 个集成测试） | 基准本身；本机 `flutter test integration_test/perf_test.dart -d flutter-tester --dart-define=PERF_QUICK=true` 能跑 |
| `apps/pure_live/test/perf_frame_report_test.dart`（4） | 最近秩百分位；120 Hz 下卡顿、最长连续、4.1 节各项判定和 JSON；直播间 0.6 周期和 200 条弹幕 3 毫秒；只留录制期间、应用要的帧 |
| `apps/pure_live/test/image_cache_budget_test.dart`（3） | 分档（3.7、4、5.6、16 GiB、未知、电脑）、`MemTotal` 解析、设到缓存上 |
| `packages/live_ui/test/loading_ring_test.dart`（1） | 转圈没有 `ShaderMask`/`ShaderMaskLayer`/`OpacityLayer`，画法和每秒一圈 |
| `apps/pure_live/test/features/popular/popular_test.dart`（R01.1 加的 2 个）、`live_play/live_play_mini_window_test.dart`（改 1 个） | 静止时不要帧、刷新时列表尾不转；浮窗拖动没有透明层 |

## 3.x 基线

- 3.x 没有帧基准；`git show v3.2.11:lib/common/global/initialized.dart:31-35`：`configureDecodedImageCache`（手机 160 张 / 48 MiB、电脑 240 张 / 72 MiB）——4.x 保留，只给大内存手机放宽。
- 3.x 浮窗拖动 80% 不透明、转圈用 `ShaderMask`（4.x 早期照搬，R01.1 去掉）；封面用 `ClipRRect` 裁圆角。
- specs/UI.md 第 9.4 节的“v3 基线（归档 v4 实测）”：Windows 首页 481 MB、一个直播间 801 MB、3 格多画面 1054 MB；Android 直播间 PSS 462 MB。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 基准没在 K90 上跑过，4.1 节标准和 9.4 节指标一个都没判定 | R01.1 记录“要在 K90 上看的” | 不知道现在顺不顺；P4 没法决定 | R01.1 的 verify.md、R01.2 |
| 基准的直播间和多画面不含视频本身的开销（假播放器不出画面） | `bench_app.dart` 的 `FakeEngine` | 数字只是界面部分；4.1 节“直播间 raster ≤0.6 周期”留出了视频的余量 | 接受；视频和界面一起的帧时间用 Perfetto 在真机上另看（R05.1、G03.1 顺带） |
| 无头方式的数字没有意义（debug 模式，改成手机尺寸后不做光栅） | R01.1 记录“验收” | 本机只能证明能跑 | 只在 K90 上用 `flutter drive --profile` |
| 跑基准会把 profile 基准包装成 `com.mystyle.purelive.v4dev`，覆盖手机上现有的测试包 | `flutter drive` 的行为 | 跑完要重装平时的测试包 | verify.md 写明 |
| R01.1 记录写的封面裁剪位置 `room_card.dart:396` 已过时：`packages/live_ui/lib/src/widgets/room_card.dart` 现在只是数据类（126 行），没有裁剪；卡片封面的裁剪在 `live_room_card.dart:362` | R01.1 记录、V03.2 调研 4.2 节 | 按旧位置找不到 | R01.2 的任务书用新位置 |
| ≤4 GiB 设备的图片缓存保留 48 MiB（任务单举例 64 MB，是基于“没设上限”的误判），记录里“需要维护者决定的”第 1 条还没回复 | `bootstrap.dart:54-59` | — | 维护者表态；不改也行（低端机不多用内存） |
| 代码注释里的旧编号（P05、D2、UI_PLAN §9.4） | `perf_test.dart:1-8`、`bootstrap.dart:45` | 找文档先查 MAPPING | Z 组统一替换 |

## 相关决定和规范

- [specs/UI.md](../../specs/UI.md) 第 9.2 节（局部刷新、分层、图片按显示尺寸解码、进出直播间 20 次内存不涨）、第 9.3 节（圆角用装饰不用裁剪、不用模糊）、第 9.4 节（指标）。
- [V03.2 调研报告](../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 4 节（4.1 帧预算和通过标准、4.2 卡顿来源、4.3 在手机上怎么测、4.4 改动清单 P1～P4）。
- D-017（单元测试的定时器至少 1 秒；基准本身不受限，它是集成测试）、D-019（K90 随时可用，基准会覆盖测试包）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/perf_frame_report_test.dart test/image_cache_budget_test.dart`；`cd packages/live_ui && flutter test test/loading_ring_test.dart`；基准能跑：`flutter test integration_test/perf_test.dart -d flutter-tester --dart-define=PERF_QUICK=true`。
- 真机：[R01.1 的 verify.md](R01.1-基准测试和渲染开销/verify.md)（跑基准 + 手动看浮窗、转圈、列表指示）；[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 18 条（界面刷新率“性能”时滚动流畅）。

## 路线

1. 维护者按 R01.1 的 verify.md 在 K90 上跑一次基准，结果追加进 R01.1 的记录。
2. R01.2：用那次的 `cover_corners_*` 数字决定封面圆角（差 >0.5 毫秒才改），写进记录。
3. 以后每个影响滚动、直播间、弹幕的大任务合并后在 K90 上跑一次基准（specs/UI.md 9.4“每个任务完成后 profile 模式看一次帧时间”），数字有回退时开任务。R03.1 用 `room_enter_exit_20` 的内存；Windows 上的基准在 X01。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [R 性能和流畅度](../README.md)。

- 代码：`apps/pure_live/integration_test/`
- 进度：`████████████░░░░░░░░` 60%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| R01.1 | 基准测试和渲染开销：profile 基准、浮窗和转圈不再离屏绘制、图片缓存上限 | 性能 | 待真机 | 2026-10-02 | 2ec6f598e | [设计或说明](R01.1-基准测试和渲染开销/README.md)、[任务书](R01.1-基准测试和渲染开销/brief.md)、[记录](R01.1-基准测试和渲染开销/record.md)、[真机验证](R01.1-基准测试和渲染开销/verify.md) |
| R01.2 | 在 K90 上跑基准，按数字决定封面圆角画法 | 性能 | 未开始 | — | — | [设计或说明](R01.2-在K90上跑基准/README.md)、[任务书](R01.2-在K90上跑基准/brief.md) |

## 还没完成的

- **R01.2 在 K90 上跑基准，按数字决定封面圆角画法**（未开始，第二档，规模 小）
  - 阶段：跑基准 → 判定并记录

<!-- docs:生成结束 -->
