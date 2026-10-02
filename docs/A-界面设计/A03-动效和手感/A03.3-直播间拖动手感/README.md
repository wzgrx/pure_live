# A03.3 直播间拖动手感：换台、三档面板、详情面板带松手速度的弹簧和橡皮筋

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（暂停，第二档，规模中，阶段 0/4）
- 类型：性能（手感）
- 来源：用户 2026-10-02：要“上下滑动、左右滑动的流畅度、阻尼感”；调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 0 节第 2、6、8、11、12 条，第 2.3～2.5 节（S2 直播间部分、S4、S6、S7、S8、S9、S11）、3.2 节（切房间预览解码）
- 旧编号：P04、T05k.1（见 [MAPPING.md](../../../MAPPING.md)）
- 相关：依赖 [A07.11](../../A07-直播间界面/A07.11-直播间小问题合集/brief.md)（直播间小问题合集，待真机，已合并）和 [A03.2](../A03.2-翻页和面板/README.md)（`AppMotion`、`ReleaseSpringSimulation`、`animateRelease`）；关联 A07.2（三档面板和竖屏全屏）、A07.3（竖屏全屏上下滑换台）、A07.1（直播间详情）；D-020
- 任务书：[brief.md](brief.md)；暂停时登记的工作区 `worktree-agent-a770fdd52c3109749`（“刚开始，未提交”，这个仓库里 `git branch -a` 查不到，只可能在维护者本机）

## 目标

直播间里所有拖动 1:1 跟手、松手不断速、到头有阻力：

- 竖屏全屏上下滑换台：松手按手指速度用弹簧换走或回位，到没有上一个 / 下一个房间的一边是越拉越沉的橡皮筋而不是硬停；松手时就开始连新房间，不等动画。
- 竖屏三档面板：松手带速度吸到最近一档；拖动时播放器不重建（现在每帧重建）；起拖不跳。
- 直播间详情面板：把手热区 48 dp，下拉跟手，用弹簧关闭。
- 亮度和音量手势：每帧最多调一次平台方法。
- 切房间时的预览封面按实际展示方式解码。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 竖屏全屏换台 | 3.x 没有（A07.3 新加，C-9） | `apps/pure_live/lib/features/live_play/player/room_swipe.dart`：拖动 `update`（`:67-76`）在没有邻居的一边硬停（`:70-71`）；松手 `_settleTo`（`:94-105`）用 220 毫秒（`:182`）easeOutCubic（`:111`），从 0 速起步；动画完了 `_finish`（`:121-128`）才 `onSwitch` 开始换房间；阈值 1/3 屏或 800 dp/s 且 48 dp（`logic/room_layout.dart:208-215`，写死的数） | `ReleaseSpringSimulation(spring: AppMotion.roomSwipeSpring)` 带松手速度、夹住目标不过冲；没有邻居时 `AppMotion.rubberBand`（最多 R/3）、`overscrollSpring` 约 0.4 秒回 0；松手就 `onSwitch`；阈值引用 `AppMotion.roomSwipeFlingVelocity`/`roomSwipeFlingDistance`（数值不变） |
| 三档面板 | `lib/modules/live_play/widgets/layout/live_play_content.dart:279`（180 毫秒）；阈值 `portrait_fullscreen_interaction.dart:12-41`（30% 夹在 72–144、900 且 28；上滑 64 或 −850 且 24） | `layout/portrait_panel.dart`：`_drag`（`:127-149`）每帧 `setState` 整个布局；`build` 里 `widget.player(covered)`（`:212`），`live_play_page.dart:1225` 每次新建 `RoomPlayer`；松手 `_release`（`:151-159`）→ `_settle`（`:161-171`）用 `AnimatedPositioned` 180 毫秒 easeOutCubic（`:207-216`）；把手 `DragStartBehavior.down`（`:275`，越过起拖阈值时跳约 8 dp）；阈值 `room_layout.dart:166-170`、`:178-179` 写死 | 带速度的弹簧（`AppMotion.panelSpring`）吸到最近一档；拖动只重建面板（播放器按 `covered` 缓存，或把拖动状态放进只包住面板的子组件）；`DragStartBehavior.start`；阈值引用 `AppMotion.panelFullscreenFling*`、`panelRestoreFling*`（数值不变） |
| 详情面板 | 3.x 没有（A07.1 c6 新加） | `layout/room_details.dart`：越界下拉 64 关（`:59`、`_onScroll` `:71-88`）；把手拖动 >600 dp/s 关（`:108-117`），拖动时面板不跟手；把手只有 20 高（`:119`） | 把手热区 48 dp；下拉时面板跟手；`AppMotion.panelSpring` 关闭或回位；快滑阈值 `AppMotion.panelFlingVelocity`（700） |
| 亮度和音量 | `lib/modules/live_play/widgets/video_player/video_controller_panel.dart:817`（`BrightnessVolumnDargArea`）：同样每次移动调一次 `setBrightness`/`setVolume`（`:896`、`:898`）；整屏高拖动改 1.2 | `player/player_gestures.dart`：`_onDragUpdate`（`:185-200`）每次手指移动都 `unawaited(_apply(...))`（`:199`）→ `DeviceControls.setVolume` / `setBrightness`（`:126`、`:128`、`:133`） | 合并成每帧最多一次平台调用 |
| 切房间预览 | — | `room_swipe.dart:254-257`：按屏宽 × 像素比（夹在 240–1080）解码，`BoxFit.cover` 铺满竖长屏幕，横版封面放大约 4 倍 | 按实际展示方式解码（横版直播在竖屏全屏里是 contain） |
| 触摸重采样 | — | 没开 | 试开 `GestureBinding.instance.resamplingEnabled`，记录结论，默认不开 |

## 方案

- 改动清单（和登记表的四个阶段对应，详见 [brief.md](brief.md)）：
  - c1（阶段 1“换台和面板的弹簧”）S2：`room_swipe.dart` 换台回位、`portrait_panel.dart` 三档面板、`room_details.dart` 详情面板改成带松手速度的弹簧（常量用 `AppMotion`），夹住目标不过冲；换台在松手时就开始连新房间。
  - c2（阶段 2“到头的橡皮筋”）S6：`room_swipe.dart:70-71` 等硬停处改成橡皮筋 d = R·(x − x² + x³/3)，最多 R/3，回弹约 0.4 秒。
  - c3（阶段 3“拖面板不重建播放器”）S4：三档面板拖动时不再每帧重建 `RoomPlayer`；S8：`portrait_panel.dart:275` 改成 `DragStartBehavior.start`。
  - c4（阶段 4“把手和手势细节”）S7：详情面板把手热区 48 dp、下拉跟手、弹簧关闭；S9：亮度和音量每帧最多调一次平台方法。
  - c5（阶段 4）切房间预览按实际展示方式解码。
  - c6（阶段 4，实验）S11：试开触摸重采样，写结论，默认不开。
- 不做：侧面板往上的橡皮筋（`shared/panels/side_panel.dart:94`，D-020 定为拉到最上面直接停住；A03.2 记录建议保持）。

## 性能任务：测量

| 指标 | 改之前（读代码和调研报告） | 目标 | 怎么测 |
|---|---|---|---|
| 换台松手后第一帧位移 / 松手前最后一帧 | 0（220 毫秒曲线从 0 速起步） | 0.8～1.25（快甩） | widget 测试逐帧（8.33 毫秒）推，同 `apps/pure_live/test/shared/side_panel_test.dart` 的做法 |
| 换台停稳 | 220 毫秒曲线 | ≤350 毫秒（1/400/1 约 0.33 秒） | 同上，按 1% 算 |
| 换台开始连新房间 | 动画结束后（+220 毫秒） | 松手当帧 | 测试：松手后下一帧 `onSwitch` 已被调用 |
| 没有邻居时越界 | 硬停（0） | 单调、≤R/3、400 毫秒内回 0 | 单元测试 `AppMotion.rubberBand` 已有；加换台的 widget 测试 |
| 拖三档面板 2 秒 `RoomPlayer` 重建次数 | 每帧一次（120 Hz 下约 240 次） | 0 | widget 测试数 build 次数；真机 DevTools 的 Track widget builds |
| 拖面板时 UI 线程 | 每帧整个布局 `setState` | 120 Hz 下 P90 ≤4 毫秒 | `flutter run --profile`，DevTools 帧图没有红帧 |
| 起拖第一帧位移 | 约 8 dp 跳动（`DragStartBehavior.down`） | ≤1 dp | widget 测试 |
| 详情把手热区 | 20 dp 高 | 48 dp | `meetsGuideline(androidTapTargetGuideline)` |
| 亮度音量平台调用 | 每次手指移动一次（120 Hz 触摸约每 8 毫秒） | 每个 vsync ≤1 次 | 测试计调用次数；真机 Perfetto 看主线程 binder |

## 验证

- 自动测试：每条 c 至少一个（松手速度连续、橡皮筋单调且 ≤R/3、`RoomPlayer` 拖动 2 秒重建 0 次、起拖第一帧位移 ≤1 dp、把手热区 48 dp），写在 `apps/pure_live/test/features/live_play/` 下（现有 `room_swipe_test.dart`、`live_play_layouts_test.dart`、`live_play_room_test.dart` 可以加）。
- 真机：竖屏全屏上下滑换台（跟手，快滑一下就换，到最后一个房间有橡皮筋）；竖屏拖三档面板（跟手、松手顺滑；`flutter run --profile` 下 DevTools 没有红帧）。完成后写 `verify.md`。

## 留下的问题

- 暂停的工作区在维护者本机（如果还在）：接手前先 `git worktree list` 看有没有 `worktree-agent-a770fdd52c3109749`，有改动就先看能不能用；没有就从 master 重做。
- 侧面板往上的硬停不在本任务（见“方案”的“不做”）。
