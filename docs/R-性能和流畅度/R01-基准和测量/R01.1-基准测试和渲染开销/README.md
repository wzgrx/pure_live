# R01.1 基准测试和渲染开销：profile 基准、浮窗和转圈不再离屏绘制、图片缓存上限

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：[V03.2 流畅度、刷新率、分辨率调研](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md)（2026-10-02）第 4.4 节的 P1、P2、P4 和第 3.3 节的 D2；[specs/UI.md](../../../specs/UI.md) 第 9.4 节“基准场景写成集成测试”
- 旧编号：P05、T14a.1
- 相关：依赖 A03.1（同改 `room_grid.dart`，在它之后）；后续 [R01.2](../R01.2-在K90上跑基准/README.md)（按 K90 数字决定封面圆角）、[R03.1](../../R03-内存和图片/R03.1-内存/README.md)（用进出直播间的内存）；任务单 [brief.md](brief.md)（旧格式，开发时用的）、记录 [record.md](record.md)、真机步骤 [verify.md](verify.md)

## 目标

- 有一套能在手机上跑的帧基准，覆盖最常用的滑动面和直播间，输出 build、raster 的 P90/P99 和卡顿率并按调研 4.1 节判定，以后每个大任务合并后都能跑一次比对。
- 去掉三处没必要的绘制开销：浮窗拖动时给视频加透明（每帧离屏绘制）、默认转圈的 `ShaderMask`（每帧离屏绘制）、刷新时列表尾多转的一个转圈。
- 图片缓存按设备内存分档：大内存手机少重新解码封面，低端机不比以前多用内存。
- 封面圆角先测再改（P4）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`，文件:行） | 改之前（4.x） | 现在（文件:行） |
|---|---|---|---|
| 帧基准 | 没有 | 没有 | `apps/pure_live/integration_test/perf_test.dart`（9 组数字）、`perf/frame_report.dart`（4.1 节判定） |
| 浮窗拖动 | 整个小窗 80% 不透明 | 同 3.x（`AnimatedOpacity`） | 拖动时不变（`features/live_play/mini/floating_window.dart`） |
| 默认转圈 | `ShaderMask` 给白色圆环套扫描渐变 | 同 3.x（`live_ui` 的 `loading_styles.dart:173`） | `CustomPaint` + `Paint.shader` 直接描边，自己的 `RepaintBoundary`（`packages/live_ui/lib/src/widgets/loading_styles.dart`） |
| 热门列表的指示器 | 刷新时下拉头、顶部进度条和列表尾三处转 | 同 3.x | 刷新时下拉头和顶部进度条；列表尾只在加载更多时转；两个指示器各自重绘边界（`shared/rooms/room_grid.dart`） |
| 图片缓存 | 手机 160 张 / 48 MiB、电脑 240 / 72（`lib/common/global/initialized.dart:31-35`） | 同 3.x | 内存 >4 GiB 的手机 320 张 / 128 MiB，其他不变（`app/bootstrap.dart:34-77`） |
| 封面圆角 | `ClipRRect` | 同 3.x | 不变，等 K90 数字（R01.2；裁剪在 `packages/live_ui/lib/src/widgets/live_room_card.dart:362`） |

## 结果

- 改动（合并提交 `2ec6f598e`，2026-10-02）：
  - c1 P1 基准：`integration_test/perf_test.dart`（热门快速滚动、直播间每秒 50/200 条弹幕、4 格多画面、设置页滚动、进出直播间 20 次附内存、封面圆角三种画法）、`perf_driver.dart`、`perf/frame_report.dart`、`perf/frame_requests.dart`、`perf/bench_app.dart`；数据全是假的（真实应用 + 内存数据库 + 假平台 + 本机封面服务器 + 假播放器），不连真实平台。
  - c2 P2：浮窗拖动不再透明；默认转圈改画法；列表尾转圈只在加载更多时出现、两个指示器各自重绘边界。
  - c3 D2：启动时按 `/proc/meminfo` 的 `MemTotal` 分档设图片缓存。
  - c4 P4：没改（没法在手机上测）；基准里加了 `cover_corners_clipOverFade` / `clip` / `decoration` 三种画法的对比。
- 偏差（详见记录“偏差和原因”）：≤4 GiB 的设备保留 3.x 的 48 MiB（任务单举例 64 MB 是基于“没设上限”的误判）；浮窗拖动不再有任何反馈；下拉刷新时顶部进度条照 3.x 保留；基准不含视频本身的开销；只统计应用要的帧；加了开发依赖 `integration_test`、`flutter_driver`（只在 debug/profile）。
- 测试：新增 10 个、改 1 个，外加基准本身 7 个集成测试（`loading_ring_test` 1、`popular_test` +2、`live_play_mini_window_test` 改 1、`image_cache_budget_test` 3、`perf_frame_report_test` 4）。本机无头跑通（数字没有意义，只证明能跑）；`flutter build apk --profile -t integration_test/perf_test.dart` 编译通过。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 各场景 build、raster 的 P90 | 没有数字 | ≤8.33 毫秒（120 Hz）；直播间和多画面 raster ≤5.0 毫秒 | `flutter drive --profile`，JSON 的 `buildMs.p90`、`rasterMs.p90`（待真机） |
| 各场景 P99 | 没有数字 | ≤12.5 毫秒 | 同上（待真机） |
| 卡顿帧比例、最长连续卡顿 | 没有数字 | <1%、没有连续两帧 | JSON 的 `jank`（待真机） |
| `danmaku_200` 的 build P90 | 没有数字 | ≤3 毫秒（计划书 9.4） | 同上（待真机） |
| 进出直播间 20 次的常驻内存 | 没有数字 | 不一直涨 | `room_enter_exit_20` 的 `extra.residentMiB`（待真机；本机无头 640 → 646 MiB，最高 670，只作参考） |
| 封面圆角：`clipOverFade` 和 `decoration` 的 raster P90 差 | 没有数字 | 差 >0.5 毫秒才改 | `cover_corners_*`（R01.2 判定） |
| 浮窗拖动、转圈的离屏绘制 | 每帧一次 saveLayer | 没有 | 层树测试（已过）；真机看 Perfetto 或 `checkerboardOffscreenLayers`（待真机） |

## 验证

- 自动测试：`cd packages/live_ui && flutter test test/loading_ring_test.dart`；`cd apps/pure_live && flutter test test/perf_frame_report_test.dart test/image_cache_budget_test.dart test/features/popular/popular_test.dart test/features/live_play/live_play_mini_window_test.dart`；基准能跑：`flutter test integration_test/perf_test.dart -d flutter-tester --dart-define=PERF_QUICK=true`。
- 真机：**待真机**，步骤见 [verify.md](verify.md)（跑基准约 5 分钟 + 手动看浮窗、转圈、列表指示、图片缓存）。

## 留下的问题

- P4 的决定 → [R01.2](../R01.2-在K90上跑基准/README.md)。
- 记录里“需要维护者决定的”四条还没回复：≤4 GiB 设备的缓存是否改 64 MB；P4；浮窗拖动要不要别的反馈（例如加深阴影）；下拉刷新时顶部进度条要不要去掉。
- 记录写的封面裁剪位置 `room_card.dart:396` 已过时（那个文件现在只是数据类），实际在 `live_room_card.dart:362`。
