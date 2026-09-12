# Android 首页滚动帧节奏审计（2026-09-12）

## 范围与结论

本轮先审查首页、热门平台页签、网格布局、卡片图片和分页控制器，再在用户指定的 K90 Pro Max 上执行 A1-06 的首轮原生量化：

- 热门直播网格向上 20 次、向下 20 次；
- 相邻平台页面向左 20 次、向右 20 次；
- 每次输入前核对 Pure Live 为精确 `topResumedActivity`；
- 每组分别采集 SurfaceFlinger `--timestats`、Flutter BLAST layer 帧间隔直方图和主线程 `/proc/PID/task/PID/schedstat`；
- 同时保留 UI 层级、前后截图、内存、温控和进程日志。

两组各 40 次手势完整执行，页面仍可操作，无 FATAL/ANR，SurfaceFlinger layer 均为 120 Hz、`droppedFrames=0`。竖向组仍出现一个 102 ms 离群帧间隔，且当前输入是 Debug APK，因此 A1-06 从 `NR` 更新为 `RUN`，不提升为 `PASS`。

## 源码审查

本轮覆盖以下关键路径：

- `lib/modules/home/home_page.dart`
- `lib/modules/home/mobile_view.dart`
- `lib/modules/home/tablet_view.dart`
- `lib/modules/popular/popular_page.dart`
- `lib/modules/popular/popular_grid_view.dart`
- `lib/modules/popular/popular_controller.dart`
- `lib/common/base/base_page_view.dart`
- `lib/common/base/base_page_view_extension.dart`
- `lib/common/widgets/room_card.dart`

当前实现已经具备与此次量化直接相关的约束：

1. 热门网格使用懒构建 `SliverList` 行，不一次创建整页卡片；每张可见卡片有独立 `RepaintBoundary` 和稳定房间 identity。
2. 封面按控件逻辑宽度与 DPR 限制内存解码宽度，关闭淡入/淡出，并以静态占位替代每张卡片各自的无限动画。
3. 平台切换只在 Tab 动画稳定后加载目标页，80 ms 合并快速切换；相邻平台预热延迟到当前网格空闲后执行。
4. 页签与 PageView 使用有边界的滚动物理规则；卡片行保持自然文字高度，避免大字号下固定高度裁切。
5. 滚动控制器只在跨越浮动按钮阈值时发布响应式状态，而不是每一帧重建完整页面。

原生数据没有把问题收敛到其中某一条产品代码路径；Debug 包的单个离群点也不足以支持盲目扩大缓存或预建更多图片。本轮保留产品实现，新增可重复、可解析的性能验收工具作为后续 Release 对照基线。

## 新增测量工具

提交 `09dce413bd85c7b6b5e7b906b15487470057e8bd` 增加：

- `tool/android_home_scroll_performance.ps1`：身份、Root、候选 APK 哈希、前台所有权、手势次数、原始统计、致命日志和退出清理一体化门禁；
- `tool/android_surfaceflinger_timestats.ps1`：从全设备 timestats 中精确选择目标应用当前 BLAST layer，解析计数、刷新率、P50/P90/P95/P99、两帧/四帧间隔阈值和主线程调度差值；
- `tool/test_android_surfaceflinger_timestats.ps1`：覆盖多 layer 选择、直方图、阈值、schedstat 与缺失/空证据失败路径；
- `tool/local_ci.ps1`：每轮质量门禁固定运行上述纯解析测试。

旧的 `dumpsys gfxinfo` 只看到 Android View 帧，未覆盖 Flutter Surface。本工具改用 SurfaceFlinger 当前 BLAST layer 的真实 present-to-present 数据；当 `totalTimelineFrames=0` 时，也明确不把分类字段里的 `jankyFrames=0` 外推成零卡顿，而是报告帧间隔直方图和调度数据。

## 自动化门禁

精确工具提交 `09dce413` 完成：

- SurfaceFlinger/schedstat 解析回归通过；
- 热门自然高度懒网格、加载动画释放、平板导航、边界滚动物理与桌面滚动相邻测试 **45/45 PASS**；
- 全库 analyze：`No issues found`；
- 记录：`local-artifacts/build-records/20260912T144507273Z-quality-focused.json`。

## 原生输入与候选身份

- 设备：`25102RKBEC / myron / Android 17`
- Root：`su -c id` 返回 `uid=0(root)`
- 应用：`3.1.8+6121`
- 已安装 APK SHA-256：`0F28A5F0C61A1794F72E905A1E3C0CFA015FE412B9BB50FCAFFB6D21A7D4CD7F`
- APK 对应产品提交：`039f8ff37ef05d668ebfb462e34512755afd392f`
- 测量工具提交：`09dce413bd85c7b6b5e7b906b15487470057e8bd`
- 原始证据：`local-artifacts/diagnostics/android-home-scroll-performance-20260912T224129353/summary.json`

没有重新安装、清理应用数据或修改 Root/LSP、网络、调试授权及 ADB 端口。

## 120 Hz SurfaceFlinger 结果

### 竖向直播网格：20 上 + 20 下

| 指标 | 结果 |
|---|---:|
| 测量时间 | 26,143 ms |
| BLAST frames / histogram intervals | 2,924 / 2,924 |
| SurfaceFlinger averageFPS | 116.806 |
| P50 / P90 / P95 / P99 present gap | 8 / 8 / 16 / 24 ms |
| `>=16 ms` 间隔 | 160，5.472% |
| `>=33 ms` 间隔 | 2，0.068% |
| 最大非空 bucket | 102 ms |
| dropped / lateAcquire / badDesiredPresent | 0 / 0 / 0 |
| 主线程运行 / run-queue delay | 13,623.905 / 597.481 ms |
| 主线程调度片 | 9,204 |

### 横向平台页面：20 左 + 20 右

| 指标 | 结果 |
|---|---:|
| 测量时间 | 24,456 ms |
| BLAST frames / histogram intervals | 2,842 / 2,842 |
| SurfaceFlinger averageFPS | 121.557 |
| P50 / P90 / P95 / P99 present gap | 8 / 8 / 8 / 16 ms |
| `>=16 ms` 间隔 | 66，2.322% |
| `>=33 ms` 间隔 | 3，0.106% |
| 最大非空 bucket | 42 ms |
| dropped / lateAcquire / badDesiredPresent | 0 / 0 / 0 |
| 主线程运行 / run-queue delay | 15,101.158 / 564.505 ms |
| 主线程调度片 | 8,082 |

`averageFPS` 是 SurfaceFlinger 原始字段，可能因时间窗口边界和毫秒 bucket 量化略高于 120；验收判断同时查看刷新率、帧间隔分布和丢帧计数。

## 清理与后续

脚本结束后 Pure Live 进程停止、MIUI 桌面恢复前台，stay-awake 从临时 `7` 恢复原值 `0`，`user_rotation=0`。

A1-06 后续仍需：

1. 在同一设备安装精确 Release 候选，使用同一工具复跑并与 Debug 数据分列；
2. 对 102 ms 竖向离群点用 Perfetto/Flutter timeline 定位 Dart build/raster、图片解码、GPU 或调度来源；
3. 补充关注页长列表、二级分区列表、封面首次冷缓存与完全热缓存对照；
4. 加入温升后的持续轮次，观察 P95/P99、run-queue delay 和内存平台期。

本批 Astra Light 使用 0 次。
