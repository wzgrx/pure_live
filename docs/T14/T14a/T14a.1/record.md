# T14a.1 记录：渲染性能——基准测试、去掉多余的离屏绘制、图片缓存上限

- 任务单：[tasks/P05.md](brief.md)；依据：[调研报告](../../research-2026-10-02.md) 第 4 节（P1、P2、P4）、3.3 节 D2；[specs/UI.md](../../../specs/UI.md) 第 9 节（9.4 基准场景）
- 日期：2026-10-02；本地 worktree 任务（不建 `cloud/` 分支、不推送、不开 PR），基于本地 master `00a4508e5`（含 T14c.1），提交前合并了本地 master `61363d6a7`（含 T14c.2、T05g.2、T06d.3）
- 没有出设计；改变手感的地方（浮窗拖动、加载指示）在下面写了前后对比
- 这次没有往手机上装东西、没有点手机；基准测试在本机无头方式跑通，K90 上的数字由维护者跑（命令见“要在 K90 上看的”）

## 逐条对照

| 条 | 做了没有 | 说明 |
|---|---|---|
| c1 P1 | 做了（K90 数字待跑） | `apps/pure_live/integration_test/perf_test.dart`：计划书 9.4 的 5 个场景 + P4 的封面圆角对比，共 9 组数字：热门快速滚动（`hot_scroll`）、直播间每秒 50/200 条弹幕（`danmaku_50`、`danmaku_200`）、4 格多画面（`multiview_4`）、设置页滚动（`settings_scroll`）、进出直播间 20 次（`room_enter_exit_20`，附内存）、封面圆角三种画法（`cover_corners_*`）。用 `SchedulerBinding.addTimingsCallback` 收每帧的 build、raster、总时长，算 P50/P90/P99/最大/平均、卡顿帧数和卡顿率、最长连续卡顿，按报告 4.1 节判定，写成 JSON。数据全是假的：真实的 `PureLiveApp` + 内存数据库 + 假平台（300 个直播间，每页 300 ms 才返回，像网络）+ 本机 127.0.0.1 上的封面服务器（每个房间自己的封面地址，照真实情况各自下载、解码）+ 测试自己发的弹幕 + 不出画面的假播放器，不连任何真实平台。本机用 `flutter test ... -d flutter-tester` 无头跑通（7 个测试全部通过）；`flutter build apk --profile -t integration_test/perf_test.dart` 编译通过 |
| c2 P2 | 做了 | ① 浮窗拖动时不再给视频加 80% 透明（`floating_window.dart` 去掉 `AnimatedOpacity`）；② 默认加载转圈不用 `ShaderMask`，改成 `CustomPaint` 用 `Paint.shader`（扫描渐变）直接描边，外面包 `RepaintBoundary`；③ `room_grid.dart`：核对过，顶部进度条和列表尾转圈本来就只在 `busy` 时出现、静止时不出帧；实际的问题是列表尾转圈在“刷新”时也转（刷新不是在加载更多），已改成只在加载更多时转；两个指示器各自包 `RepaintBoundary`，转动时只重画自己 |
| c3 D2 | 做了（数值有偏差） | 应用启动处（`AppBootstrap.start` → `configureDecodedImageCache`）按 `/proc/meminfo` 的 `MemTotal` 分档：≤4 GiB 或读不到 → 160 张 / 48 MiB（3.x 的值，不变）；>4 GiB → 320 张 / 128 MiB；电脑照旧 240 张 / 72 MiB。偏差见下面第 1 条 |
| c4 P4 | 没改（待 K90 数字） | 本次不能在手机上跑，没法测；按任务单“改善超过 0.5 ms 才改”，卡片（`room_card.dart:396`、`live_room_card.dart:362,718`）保持 `ClipRRect`。基准里加了专门的对比（`cover_corners_clipOverFade` / `clip` / `decoration`），维护者在 K90 上跑一次就能按规则决定 |

### 验收

| 项 | 结果 |
|---|---|
| 基准测试能跑并输出 P90/P99 | 本机无头跑通（7 个测试、9 组数字、JSON 写到 `build/perf/`）。无头方式是 debug 模式，而且无头测试器在把窗口改成手机尺寸后不做光栅（raster 全是 0），所以本机数字没有意义，只证明能跑；手机上用 `flutter drive --profile` |
| 浮窗拖动没有 saveLayer | 达到：拖动时视频上方没有 `Opacity`/`AnimatedOpacity`/`FadeTransition`（测试，改之前会失败） |
| 加载转圈没有 saveLayer | 达到：没有 `ShaderMask`，层树里没有 `ShaderMaskLayer`、`OpacityLayer`；画的是一个 3.5 宽、半径 14.25（32 的框）的描边圆，画笔带渐变着色器（绘制测试，改之前会失败） |
| 空闲时不持续出帧 | 达到：热门列表加载完后没有任何进度条和转圈，`hasScheduledFrame` 为假（测试）；加载更多时出现、加载完消失（测试） |

### 偏差和原因

1. **≤4 GB 的设备没有用任务单举例的 64 MB，而是保留 48 MiB。** 调研报告说“`ImageCache` 没设上限，用的是默认的 1000 张、100 MB”，核对后不对：v4 从 3.x 起就在启动时设了 160 张 / 48 MiB（电脑 240 张 / 72 MiB，`bootstrap.dart` 的 `configureDecodedImageCache`）。所以“加上限”这件事本来就有；改成 64 MB 反而会让低端机多用内存。现在只给内存大的设备放宽到 128 MiB（K90 这类机器来回滑热门时少重新解码封面）。需要维护者确认（见最后）。
2. **c4 没有改。** 原因见上；另外核对了代码：`ClipRRect` 默认 `Clip.antiAlias`，本身不做 saveLayer；它之所以成为一个独立的裁剪层，是因为 cached_network_image（octo_image）给异步到达的封面套了一个不透明度为 1 的 `FadeTransition`（`RenderAnimatedOpacity` 在 alpha>0 时就是重绘边界）。基准的三种画法正好把这两部分分开：`clipOverFade` = 现在的卡片，`clip` = 只有裁剪，`decoration` = `BoxDecoration` 带圆角画图（没有裁剪层）。
3. **浮窗拖动不再有反馈。** 3.x（和 T05j.1 确认的设计）拖动时整个小窗 80% 不透明；按任务单去掉，拖动时画面保持原样，只是跟着手指走。阴影保持不变。
4. **下拉刷新时顶部进度条照旧也显示**（和下拉头的转圈同时出现，v3 也是这样），只去掉了列表尾那个不该转的转圈。要不要连顶部进度条也不显示，见最后。
5. **基准测试的数字不含视频本身的开销。** 播放器是假的（不出画面），所以直播间、多画面两组是“界面部分”的开销；报告 4.1 节“直播间光栅 P90 ≤ 0.6 个周期”照样拿来判定，留出视频的余量。
6. **只统计应用自己要的帧。** 集成测试的绑定在引擎画过一帧后会自己一直要下一帧（应用不会这样，没变化就不画），这些空帧会把卡顿率和 P90 拉得好看。基准记下每一帧是不是应用要的（`frame_requests.dart`），只统计应用要的；JSON 里 `extra.idleFramesLeftOut` 是去掉的空帧数。测试本身的 `pump` 也不再强制出帧（`benchmarkLive`，Flutter 推荐的真机基准方式）。
7. **加了两个开发依赖**：`integration_test`、`flutter_driver`（都是 Flutter SDK 自带），`pubspec.lock` 多了 5 个包（`flutter_driver`、`fuchsia_remote_debug_protocol`、`integration_test`、`sync_http`、`webdriver`）。只在 debug/profile 构建里，release 不带。
8. **基准复用了 `test/` 里的假数据**（`support.dart`、`live_play_support.dart` 的 `FakeSite`、`FakeDanmaku`、`FakeEngine`），用相对路径引用，没有复制一份。
9. **改了 `test/features/live_play/live_play_mini_window_test.dart`** 里一处断言（原来断言拖动时 0.8 不透明）。`features/live_play/` 下的代码只改了 `mini/floating_window.dart`。

## 根因

- **浮窗拖动**：`_FloatingWindow` 把整个小窗（视频纹理 + 控件 + 阴影）包在 `AnimatedOpacity` 里，拖动时 0.8。不透明度小于 1 的 `OpacityLayer` 在光栅线程要先离屏画一遍再合成（saveLayer），拖动的每一帧都做，而视频每一帧都在变。
- **默认转圈**：`DefaultLoadingIndicator` 用 `ShaderMask` 给一个白色圆环套扫描渐变。`ShaderMask` 是 `ShaderMaskLayer`，每帧先把圆环画到离屏缓冲再用着色器混合；转圈一直在转，所以加载期间每帧都有一次 saveLayer。同样的效果可以直接把渐变放进描边画笔，一次画完。另外转圈没有自己的重绘边界，每转一帧都要重录它所在的整页图层。
- **热门列表的指示器**：顶部进度条和列表尾转圈都只在 `RoomFeed.busy` 时构建，加载结束就移除，静止时没有动画（原有测试的 `pumpAndSettle` 能结束也说明这一点）。但 `busy` 同时包括“刷新”和“加载更多”，列表尾在刷新时也显示转圈；列表短、列表尾在屏幕上时，下拉刷新会同时转下拉头、顶部进度条和列表尾三处。两个指示器也都没有自己的重绘边界。
- **图片缓存**：见偏差 1。

## 前后对比（会影响手感和外观的）

| 地方 | 改之前 | 改之后 |
|---|---|---|
| 应用内浮窗拖动 | 拖动时整个小窗变成 80% 不透明（看得到后面的页面），松手 120 ms 变回 | 拖动时画面不变，跟着手指走；阴影不变 |
| 默认加载转圈（“加载样式”选默认时：页面加载、下拉头、直播间画面中央等） | 圆环 + 渐变尾巴，每秒一圈 | 外观相同（同样 3.5 宽、同样的渐变和起点、每秒一圈），画法不同 |
| 热门、分区房间：下拉刷新时 | 下拉头转圈 + 顶部进度条 +（列表尾在屏幕上时）列表尾转圈 | 下拉头转圈 + 顶部进度条；列表尾保持原来的文字（“加载更多”或“没有更多数据了”） |
| 热门、分区房间：滑到底加载更多时 | 列表尾转圈 + 顶部进度条 | 不变 |
| 图片缓存 | 手机 160 张 / 48 MiB | 内存 >4 GiB 的手机 320 张 / 128 MiB；其他不变 |

## 改了哪些文件

- `apps/pure_live/integration_test/perf_test.dart`（新）：基准场景和封面圆角对比（`CornerGrid`、`CoverCorners`）
- `apps/pure_live/integration_test/perf_driver.dart`（新）：`flutter drive` 的主机端，把结果写成 `build/perf/perf-<时间>.json` 并逐行打印
- `apps/pure_live/integration_test/perf/frame_report.dart`（新）：`FrameRecorder`、`appFrames`、`Percentiles`、`FrameReport`（P90/P99、卡顿、4.1 节判定、JSON）
- `apps/pure_live/integration_test/perf/frame_requests.dart`（新）：记下哪些帧是应用要的
- `apps/pure_live/integration_test/perf/bench_app.dart`（新）：基准用的应用（假平台、封面服务器、弹幕、设置、等待工具）
- `apps/pure_live/lib/features/live_play/mini/floating_window.dart`：拖动时不加透明
- `packages/live_ui/lib/src/widgets/loading_styles.dart`：默认转圈改成 `CustomPaint` + `Paint.shader`，加 `RepaintBoundary`
- `apps/pure_live/lib/shared/rooms/room_grid.dart`：列表尾转圈只在加载更多时出现；进度条和转圈各自包 `RepaintBoundary`（键 `<前缀>-progress`、`<前缀>-load-more-busy`）
- `apps/pure_live/lib/app/bootstrap.dart`：`decodedImageBudget`、`readTotalMemoryBytes`，启动时按内存设图片缓存
- `apps/pure_live/pubspec.yaml`、`pubspec.lock`：开发依赖 `integration_test`、`flutter_driver`
- 测试：见下

## 新设置和翻译键

- 新设置：无。
- 新翻译键：无（基准测试和日志不面向用户）。

## 测试

新增 10 个测试，改了 1 个，外加基准本身 7 个集成测试：

- `packages/live_ui/test/loading_ring_test.dart`（1，新）：默认转圈没有 `ShaderMask`、没有 `ShaderMaskLayer`/`OpacityLayer`；画一个 3.5 宽、半径 14.25 的描边圆，画笔带渐变着色器且抗锯齿；每秒一圈；在自己的重绘边界里。改之前会失败（有 `ShaderMask`）。
- `apps/pure_live/test/features/popular/popular_test.dart`（+2）：静止时没有任何进度条和转圈、不要帧；下拉刷新时下拉头和顶部进度条在、列表尾不转（改之前会失败）；滑到底加载更多时列表尾转圈和顶部进度条在、加载完都消失；两个指示器各自是重绘边界。
- `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart`（改 1）：拖动中视频上方没有 `Opacity`/`AnimatedOpacity`/`FadeTransition`（原来断言 0.8）。改之前会失败（已核对）。
- `apps/pure_live/test/image_cache_budget_test.dart`（3，新）：分档（3.7 GiB、4 GiB、5.6 GiB、16 GiB、未知、电脑）；`MemTotal` 解析、读不到为空；设到缓存上。
- `apps/pure_live/test/perf_frame_report_test.dart`（4，新）：最近秩百分位；120 Hz 下卡顿帧、最长连续、4.1 节各项判定和 JSON；直播间 0.6 周期和 200 条弹幕 3 ms 的限制；只留录制期间、应用要的帧，帧号对不上时全留。
- `apps/pure_live/integration_test/perf_test.dart`（7 个集成测试，9 组数字）：本机 `flutter test integration_test/perf_test.dart -d flutter-tester --dart-define=PERF_QUICK=true` 全部通过；不加 `PERF_QUICK` 的完整版也跑通一次（结果见下）。

跑过的检查（本地任务，没跑完整门禁）：

- `packages/live_ui`：`dart format --output=none --set-exit-if-changed .` 通过；`flutter analyze` 无问题；`flutter test` 全部 166 个通过（合并本地 master 之后）。
- `apps/pure_live`：`dart format --output=none --set-exit-if-changed .` 通过；`flutter analyze` 无问题（含 `integration_test/`）；`flutter test` 全部 838 个通过（合并本地 master 之后）；无头基准快速版合并后再跑一次，7 个通过。
- 根目录 `python3 tools/gate/check_ui_structure.py`、`python3 tools/gate/check_deps.py` 通过。
- `flutter build apk --profile --target-platform android-arm64 -t integration_test/perf_test.dart` 编译通过（在合并 T05g.2 之前的 `63e7e694f` 上编的；T05g.2 没有改原生代码；基准的 profile 包 146 MB，含 `integration_test` 的 Android 插件），之后 `./gradlew --stop`。没有改 Android 原生代码和资源。第一次构建失败在 media_kit 的构建钩子：新 worktree 里要下载 libmpv 预编译包，下载中途断了（`archive.zip.partial`），和本任务的代码无关；从主仓库的 `.dart_tool` 缓存拷过同一个包（按哈希命名）后重编通过。

本机无头跑的结果只说明能跑（debug 模式；改成手机尺寸后无头测试器不做光栅，raster 是 0），不要拿来判定。完整版（不加 `PERF_QUICK`，3 分 47 秒，7 个测试通过）的帧数：

| 场景 | 帧数（应用要的） | 去掉的空帧 | 其他 |
|---|---|---|---|
| hot_scroll | 480 | 35 | 平台共交出 360 个房间（含重复），滑到了 300 个的底 |
| danmaku_50 | 279 | 2 | 发了 500 条 |
| danmaku_200 | 334 | 1 | 发了 2000 条 |
| multiview_4 | 598 | 1 | 4 格都有房间，选中格弹幕 500 条 |
| settings_scroll | 132 | 626 | — |
| room_enter_exit_20 | 892 | 2521 | 常驻内存 640 → 646 MiB（最高 670，无头测试器的进程） |
| cover_corners_clipOverFade / clip / decoration | 756 / 740 / 755 | 0 | — |

“去掉的空帧”很多的场景（设置页、进出直播间）说明了为什么要只统计应用要的帧：不去掉的话卡顿率会被大量没事可做的帧摊薄。

## 要在 K90 上看的（维护者做）

### 1. 跑基准（约 5 分钟，跑的时候不要碰手机）

```bash
source ~/tools/purelive-env.sh
adb connect 192.168.1.2:5555
cd apps/pure_live
flutter drive --profile -d 192.168.1.2:5555 \
  --driver=integration_test/perf_driver.dart \
  --target=integration_test/perf_test.dart \
  --dart-define=PERF_HZ=120
```

- 会把基准的 profile 包装成 `com.mystyle.purelive.v4dev`（覆盖手机上现有的 v4dev 测试包，不碰 3.x 的 `com.mystyle.purelive`）。跑完要用回平时的测试包，重新装一次 debug 包即可。
- 跑之前：屏幕常亮、解锁、竖屏；“界面刷新率”不用管（基准自己用内存数据库，设成“性能”档，一直最高刷新率）。`PERF_HZ=120` 让预算固定按 120 Hz（8.33 ms）算；不加时按系统报的刷新率算。
- 结果：控制台每个场景一行（帧数、build/raster 的 P90 和 P99、卡顿率、最长连续卡顿、PASS/FAIL），完整 JSON 在 `apps/pure_live/build/perf/perf-<时间>.json`（`device` 里有刷新率、内存、图片缓存上限，可以顺便确认 K90 读到了内存、缓存是 128 MiB）。
- 判定（报告 4.1 节，JSON 的 `checks`）：build、raster 的 P90 ≤ 8.33 ms（直播间和多画面的 raster ≤ 5.0 ms）；P99 ≤ 12.5 ms；卡顿帧 <1%；没有连续两帧卡顿；`danmaku_200` 的 build P90 还要 ≤ 3 ms（计划书 9.4）。`room_enter_exit_20` 的 `extra.residentMiB` 是每次退出后的常驻内存，看是否一直涨。
- **P4 的决定**：比较 `cover_corners_clipOverFade`（现在的卡片）和 `cover_corners_decoration` 的 raster P90。差 >0.5 ms 才把卡片封面改成装饰圆角（另开任务改 `room_card.dart:396`、`live_room_card.dart:362,718`）；否则保持不改。
- 请把控制台的那几行和结论追加到本记录末尾。

### 2. 手动看

1. **浮窗拖动时视频不变暗**：设置里打开“退出小窗播放”→ 进任一直播间 → 返回，右下角出现小窗 → 按住拖来拖去：画面和松手时一样亮，不透出后面的页面；松手后停在原地。
2. **默认加载转圈外观不变**：“加载样式”选默认 → 进直播间时画面中央、热门页下拉刷新的下拉头：仍是带渐变尾巴的圆环，每秒一圈，颜色跟主题。
3. **热门列表的加载指示**：热门 → 下拉刷新：下拉头转圈、顶部细进度条在走，刷新完都消失；列表尾不会跟着转。快速滑到底：列表尾转圈 + 顶部细进度条，新房间出来后都消失；停下后开发者选项“显示刷新率”看得到刷新率回落（“均衡”档时）。
4. （可选，D2）热门页快速来回滑 2 分钟，`adb shell dumpsys meminfo com.mystyle.purelive.v4dev` 看 PSS 预热后不再增长。

## 需要维护者决定的

1. **≤4 GB 设备的图片缓存**：现在保留 3.x 的 48 MiB（任务单举例 64 MB，但那是基于“没设上限”的误判）。要按任务单改成 64 MB，只改 `decodedImageBudget` 一处。
2. **P4（封面圆角）**：等 K90 上 `cover_corners_*` 的数字。
3. **浮窗拖动要不要别的反馈**：现在拖动时没有任何变化。如果想要一点“被拿起来”的感觉，可以拖动时把阴影加深（不需要离屏绘制）。
4. **下拉刷新时顶部进度条**：现在照 v3，下拉头和顶部进度条同时出现。要不要下拉时只留下拉头。

## 可能和别的任务冲突的文件

- `apps/pure_live/lib/shared/rooms/room_grid.dart`：只改了底部 `Stack` 里的进度条和 `_phoneFooter`，在 T14c.1 的 `list(physics)` 之外。
- `apps/pure_live/lib/features/live_play/mini/floating_window.dart`、`apps/pure_live/test/features/live_play/live_play_mini_window_test.dart`：T05h.2 在改 `features/live_play/`，这两处各只有一小段。
- `packages/live_ui/lib/src/widgets/loading_styles.dart`：只改了 `DefaultLoadingIndicator` 的 `build` 和新的私有画笔类。
- `apps/pure_live/lib/app/bootstrap.dart`：只改了 `configureDecodedImageCache` 和它的调用。
- `apps/pure_live/pubspec.yaml`、`pubspec.lock`：开发依赖；别的任务改依赖时按块合并即可。
- `apps/pure_live/test/features/popular/popular_test.dart`：`_FakeSite` 加了 `gate`，加了一个 `group`。
