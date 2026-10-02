# A03.3 直播间里的拖动手感：上下滑换台、三档面板、详情面板：任务书

## 背景

- 来源：用户 2026-10-02：要“上下滑动、左右滑动的流畅度、阻尼感”；调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 2.3～2.5 节（S2 直播间部分、S4、S6、S7、S8、S9、S11）、3.2 节（切房间预览解码）。原任务单旧编号 P04。
- 现象（K90，竖屏直播间）：
  - 竖屏全屏上下滑换台：松手后画面先顿一下再按固定 220 毫秒曲线走；拉到没有下一个房间的一边是硬停；换台要等动画走完才开始连新房间。
  - 竖屏三档面板：松手后按固定 180 毫秒吸到最近一档，速度丢掉；拖动时整个直播间布局每帧重建（包括播放器组件）；越过起拖阈值时面板跳约 8 dp。
  - 直播间详情：把手只有 20 dp 高，难拖；拖把手时面板不跟手，只有快甩（>600 dp/s）或拉够 64 才关。
  - 画面左右两边上下滑调亮度、音量：每次手指移动都调一次系统接口。
- 为什么现在做：第二档；A03.1、A03.2 已经把列表、翻页、侧面板做顺，直播间里的拖动是剩下最常用的手感面；`AppMotion` 已经备好直播间要用的常量。
- 规模：中；分组：直播间；依赖：A07.11（直播间小问题合集，已合并、待真机）、A03.2（已合并、待真机）；能否和别的任务同时做：直播间组最后一个（`features/live_play/` 同时只交给一个执行者）。
- 出设计：不用（照调研报告和本任务书；改变手感的地方在记录里写清前后对比）。
- 已经做过的：A03.2 的 `AppMotion`（`packages/live_ui/lib/src/theme/motion.dart:16`）、`ReleaseSpringSimulation`（`:112`）、`animateRelease`（`:154`）和侧面板的带速度弹簧（`apps/pure_live/lib/shared/panels/side_panel.dart:104-120`，可以照抄写法）。
- 暂停前：登记的工作区 `worktree-agent-a770fdd52c3109749`（“刚开始，未提交”）。这个仓库里查不到这个分支；在维护者本机先 `git worktree list` 看它还在不在、有没有改动，有就先看能不能用，没有就从最新 master 开始。

## 目标和验收

1. 直播间里所有拖动 1:1 跟手、松手不断速、到头有阻力；拖三档面板时播放器不重建。
2. 换台：松手后第一帧位移和松手前最后一帧之比 0.8～1.25（快甩），≤350 毫秒停稳，不越过目标；松手当帧就开始换房间（`onSwitch`），不等动画。
3. 没有上一个 / 下一个房间时越界：位移单调、≤R/3（R = 画面高度）、约 0.4 秒回到 0。
4. 三档面板：带松手速度吸到最近一档（或按 3.x 阈值进竖屏全屏）；拖 2 秒 `RoomPlayer` 重建 0 次；起拖越过阈值后第一帧位移 ≤1 dp。
5. 详情面板：把手热区 48 dp（`meetsGuideline(androidTapTargetGuideline)` 通过）；拖 30 dp 时面板跟着移动 30 dp；松手用弹簧关闭或回位。
6. 亮度和音量：每帧最多一次平台调用。
7. 切房间预览按实际展示方式解码，不再按屏宽解码后铺满。
8. 触摸重采样（S11）试过，记录里写结论，默认不开。
9. 所有阈值和弹簧引用 `AppMotion`，`features/live_play/` 里不再写 900、850、800、600、28、24、48 这些数和 220、180 毫秒的曲线。

## 现状（读代码得出，写文件:行）

- 换台 `apps/pure_live/lib/features/live_play/player/room_swipe.dart`：`RoomSwipeController`（`:18`）；`update`（`:67-76`）没有邻居时 `math.max(value, 0)` / `math.min(value, 0)` 硬停（`:70-71`）、再夹到 ±屏高（`:72`）；`end`（`:80-85`）→ `_settleTo`（`:94-105`）用 `AnimationController.forward(from: 0)`；`_onTick`（`:107-113`）`Curves.easeOutCubic`；`_finish`（`:121-128`）动画完了才 `onSwitch(step)`；时长 220 毫秒、减少动态效果时 0（`:182`）；预览封面解码（`:254-257`）。
- 阈值 `features/live_play/logic/room_layout.dart`：`panelDragEntersFullscreen`（`:166-170`，30% 夹在 72–144，或 ≥900 且 ≥28）、`swipeRestoresPanel`（`:178-179`，≥64 或 ≤−850 且 ≥24）、`swipeSwitchStep`（`:208-215`，1/3 屏或 ≥800 且 ≥48，反向快甩留下）。对应的常量 `AppMotion.panelFullscreenFlingVelocity` 900（`motion.dart:50`）、`panelFullscreenFlingDistance` 28（`:53`）、`panelRestoreFlingVelocity` 850（`:57`）、`panelRestoreFlingDistance` 24（`:60`）、`roomSwipeSpring` 1/400/1（`:64`）、`roomSwipeFlingVelocity` 800（`:67`）、`roomSwipeFlingDistance` 48（`:70`）、`overscrollSpring` 1/250/1（`:74`）、`rubberBand`（`:87`）、`panelSpring` 1/500/1（`:36`）、`panelFlingVelocity` 700（`:46`）。
- 三档面板 `features/live_play/layout/portrait_panel.dart`：`_drag`（`:127-149`）每次移动 `setState`；`_release`（`:151-159`）；`_settle`（`:161-171`）；`build`（`:201` 起）里 `Positioned.fill(child: widget.player(covered))`（`:212`）和 `AnimatedPositioned`（`:213`，180 毫秒 easeOutCubic，`:207`）；把手 `GestureDetector`（`:272-279`，`dragStartBehavior: DragStartBehavior.down` `:275`）。`features/live_play/live_play_page.dart:1225` 把 `player: (covered) => _player(controller, settings, arrangement: ControlsArrangement.inline, covered: covered)` 交给面板，`_player`（`:773`）每次 `new RoomPlayer(...)`（`:783`）。
- 详情 `features/live_play/layout/room_details.dart`：`_closePull` 64（`:59`）、`_onScroll`（`:71-88`）、把手 `GestureDetector`（`:108-130`：`onVerticalDragUpdate` 累加 `_pull`，`onVerticalDragEnd` >600 关，`SizedBox(height: 20)` `:119`）、列表 `AlwaysScrollableScrollPhysics`（`:165`）。
- 手势 `features/live_play/player/player_gestures.dart`：`_apply`（`:121-135`）调 `DeviceControls.setVolume`（`:126`）、`widget.controller.setVolume`（`:128`）、`DeviceControls.setBrightness`（`:133`）；`_onDragUpdate`（`:185-200`）每次 `unawaited(_apply(kind, _level))`（`:199`）；换台时转给 `widget.swipe?.update`（`:187`）。
- 测试现状：`apps/pure_live/test/features/live_play/room_swipe_test.dart`（9 条：列表、三栏、阈值、换台、预览、横屏房间）；`live_play_layouts_test.dart:473`、`:519`、`:547`（三档面板）；`live_play_room_test.dart:365`（详情关闭方式）。没有手感数字的测试。

## 3.x 基线

- 三档面板：`lib/modules/live_play/widgets/layout/live_play_content.dart:279`（`_settling ? 180 毫秒 : 0`）；阈值 `lib/modules/live_play/widgets/layout/portrait_fullscreen_interaction.dart:12-27`（`resolvePortraitPanelDragEnd`：30% 夹在 72–144，或 ≥900 且 ≥28）、`:39-41`（`shouldRestorePortraitPanelFromSwipe`：≥64 或 ≤−850 且 ≥24）；恢复手势区 96（`:7`）。
- 亮度和音量：`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:817`（`BrightnessVolumnDargArea`），每次移动调 `setBrightness`/`setVolume`（`:896`、`:898`）。
- 3.x 没有竖屏全屏上下滑换台（A07.3 新加，C-9）和直播间详情面板（A07.1 c6 新加）。
- 必须保留（[specs/UI.md](../../../specs/UI.md) 附录 A）：第 4 条（左侧上下滑亮度、右侧音量；锁定锁住所有手势）；第 5 条（三档面板；拖过最低档或点把手进竖屏全屏；竖屏全屏底部上滑退出）；第 9 条（换画质线路不重建播放器）。3.x 的阈值数值一个不改（`AppMotion` 原样保留了）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.3 节（直播间只挂载一个视频画面，切换时移动不重建）、第 8.6 节、第 9.2 节、附录 A。
3. 本文件夹的 `README.md`；调研报告第 2.3～2.5 节、3.2 节；[A03.2 的 README](../A03.2-翻页和面板/README.md) 和 `packages/live_ui/lib/src/theme/motion.dart`；`apps/pure_live/lib/shared/panels/side_panel.dart`（带速度弹簧的写法）；`apps/pure_live/test/shared/side_panel_test.dart`（逐帧测第一帧比例的写法）。
4. A07.2、A07.3 的 README（三档面板、换台的设计）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/`；`apps/pure_live/test/features/live_play/`；本文件夹的 `record.md`。
- 不能改：其他目录（`packages/live_ui` 的 `AppMotion` 已经有要用的常量，缺的话写进报告，不在本任务里加）；`shared/panels/side_panel.dart`（往上是硬停，D-020）；三档面板的档位高度、阈值数值、换台的顺序和规则（A07.2、A07.3）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 换台和面板的弹簧 | c1：`room_swipe.dart` 的 `_settleTo` 改成 `AnimationController.unbounded` + `animateRelease(ReleaseSpringSimulation(spring: AppMotion.roomSwipeSpring, velocity: 松手速度, ...))`，换走时 `beyond` 一点、到目标就停；`end` 里一判断要换就 `onSwitch`；`portrait_panel.dart` 的 `AnimatedPositioned` 改成弹簧控制的位移（`AppMotion.panelSpring`），松手带速度吸到最近一档；`room_details.dart` 的关闭用弹簧；`room_layout.dart` 的数改成引用 `AppMotion` | `room_swipe.dart`、`portrait_panel.dart`、`room_details.dart`、`logic/room_layout.dart` | 验收 2、4（吸档）、9；新测试过 |
| 2 到头的橡皮筋 | c2：`room_swipe.dart:70-71` 的硬停改成 `AppMotion.rubberBand(越界量, 画面高度)`，松手用 `overscrollSpring` 回 0 | `room_swipe.dart` | 验收 3 |
| 3 拖面板不重建播放器 | c3：S4 三档面板拖动时只重建面板（把 `_height`/`_dismiss` 放进只包住面板的子组件或 `ValueNotifier` + `AnimatedBuilder`，播放器按 `covered`（只在停稳时变）缓存）；S8 把手改 `DragStartBehavior.start` | `portrait_panel.dart`、必要时 `live_play_page.dart` | 验收 4（重建 0 次、起拖 ≤1 dp） |
| 4 把手和手势细节 | c4：详情把手热区 48 dp（视觉仍是 32×4 的条）、下拉跟手、弹簧关闭、快滑 700；S9 亮度音量每帧最多一次平台调用（例如记下最新值，用 `SchedulerBinding.instance.scheduleFrameCallback` 每帧发一次）；c5 预览封面按展示方式解码；c6 试 `GestureBinding.instance.resamplingEnabled`，写结论 | `room_details.dart`、`player_gestures.dart`、`room_swipe.dart` | 验收 5～8 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1：换台快甩（例如 3000 dp/s）松手后第一帧位移和最后一帧之比 0.8～1.25、≤350 毫秒停稳、不越过；松手当帧 `onSwitch` 被调用；三档面板快甩吸档、慢拉过半吸到下一档；详情快甩关闭。照 `side_panel_test.dart`：每 8.33 毫秒发一次触摸移动并 `pump`。
- 阶段 2：没有下一个房间时往上拉 1000 dp，位移单调增加且 ≤R/3；松手 400 毫秒内回 0。
- 阶段 3：拖三档面板 2 秒（240 帧），`RoomPlayer` 的 `build` 次数为 0（用测试里的计数包装或 `debugOnRebuildDirtyWidget`）；越过起拖阈值后第一帧位移 ≤1 dp。
- 阶段 4：`expect(tester, meetsGuideline(androidTapTargetGuideline))` 覆盖详情把手；拖把手 30 dp 面板移动 30 dp；一帧内 5 次手指移动只调 1 次 `DeviceControls.setVolume`（用假的 `DeviceControls`）。
- 竖屏、竖屏全屏、横屏各一个布局测试不变；定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 竖屏主播进竖屏全屏（打开“竖屏全屏上下滑换台”），上下滑换台 | 跟手，快滑一下就换，松手不顿；新房间开始加载得比以前早 |
| 2. 滑到列表最后一个房间再往上拉 | 越拉越沉的橡皮筋，松手弹回，不硬停 |
| 3. 竖屏拖三档面板，快甩、慢拉 | 跟手、松手顺滑地吸到一档；拖动时画面不闪不卡 |
| 4. `flutter run --profile` 下拖三档面板，看 DevTools 帧图 | 没有红帧；Track widget builds 里拖动时没有 `RoomPlayer` |
| 5. 点信息行打开详情，按住把手往下拖 | 好按（把手区域大），面板跟手，松手弹回或关闭 |
| 6. 画面左边、右边上下滑调亮度、音量 | 和以前一样跟手，数值变化平滑 |

## 风险和注意

- `live_play_page.dart`、`portrait_panel.dart`、`room_swipe.dart` 是直播间的核心文件，A07 组的任务常改；开工前合并最新 master，按阶段提交。
- 三档面板改成弹簧后，`onEnd: _slid`（进竖屏全屏的时机，`portrait_panel.dart` 的 `_enter`/`_slid`）要改成弹簧完成的回调，保持“动画而不是计时器决定进入”（3.x 的做法）。
- 换台松手就 `onSwitch`：上一个房间的停止和新房间的连接会和动画重叠，注意 A07.3 的“前一个房间还没停时连续滑只开最后一个”（`room_swipe_test.dart` 有用例）。
- 减少动态效果时（`MediaQuery.disableAnimationsOf`）现在是时长 0；改成弹簧后也要直接到位（照 `side_panel.dart:105`）。
- 从触摸事件里启动的动画第一帧时间是 0，要用 `animateRelease`，否则第一帧比例是 0。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A03.3` 或本机工作区；提交信息以 `[A03.3]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`；交给别的 AI 时 `git push origin <分支>:wip/A03.3`。

## 报告（中文，简洁）

每条验收做到没有；前后对比的数字（第一帧比例、停稳时间、重建次数、起拖位移、平台调用次数）；S11 的结论；根因；测试数量；改了哪些文件；要在真机上看的；需要维护者决定的；可能冲突的文件。
