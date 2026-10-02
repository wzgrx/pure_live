# R01.1 渲染性能：基准测试、去掉多余的离屏绘制、图片缓存上限

- 规模：中；分组：性能；依赖：A03.1；能否和别的任务同时做：和 A03.1 都改 `room_grid.dart`，A03.1 之后；和其他组可以同时
- 出设计：不用（照调研报告和本任务单；改变手感的地方在记录里写清前后对比）
- 先读：调研报告 `docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 4 节（P1、P2、P4）、3.3 节 D2；`docs/specs/UI.md` 第 9 节（9.4 基准场景）
- 可以改：`apps/pure_live/integration_test/`（新）、`features/live_play/mini/floating_window.dart`、`packages/live_ui`、`shared/rooms/room_grid.dart`、`app/`（只加图片缓存上限）；其他目录不改。

## 要做的

- c1 P1：把计划书 9.4 的基准场景（热门快速滚动、每秒 50/200 条弹幕、4 路多画面、设置页滚动、进出直播间 20 次）写成 `apps/pure_live/integration_test/` 下的 profile 模式集成测试，用 `SchedulerBinding.addTimingsCallback` 统计 build、raster 的 P90/P99 和卡顿率，结果写成 JSON；数据源用假数据（不连真实平台）。云端没有真机，只要求能编译、能在桌面或模拟方式下跑通一次；在记录里写清在 K90 上怎么跑（`flutter drive --profile`）。
- c2 P2：`mini/floating_window.dart:170` 拖动时不再给视频加 80% 透明；`live_ui` 的 `loading_styles.dart:173` 转圈不用 ShaderMask，改成 `Paint.shader` 直接描边；`room_grid.dart` 顶部进度条和转圈只在真的在加载时显示（不一直出帧）。
- c3 D2：按设备内存给 `imageCache.maximumSizeBytes` 设上限（例如内存 ≤4 GB 取 64 MB，否则 128 MB），写在应用启动处。
- c4 P4：封面圆角裁剪（`room_card.dart:396`、`live_room_card.dart:362,718`）先用基准测一下，光栅 P90 改善超过 0.5 ms 才改成装饰圆角，否则不改，记录里写数字或说明没法在云端测。

## 验收

- 基准测试能跑并输出 P90/P99；浮窗拖动和加载转圈没有 saveLayer；空闲时不持续出帧。
- 测试：基准测试本身；转圈画法的金样（golden）或绘制测试；进度条只在加载中出现。

## 真机上看的（写进记录，维护者在 K90 上看）

- 维护者在 K90 上跑 `flutter drive --profile` 一遍，按报告 4.1 节标准判定，把结果追加进记录。
- 浮窗拖动时视频不变暗。

