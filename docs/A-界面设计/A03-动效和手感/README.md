# A03 动效和手感

滑动、翻页、拖动的手感：列表减速和到头的回弹、下拉刷新、标签页翻页、面板和直播间里的拖动松手后怎么走，以及全应用的弹簧和快滑阈值。目标是 3.x 用户的肌肉记忆（[specs/UI.md](../../specs/UI.md) 第 3 节原则 1）加上“跟手、松手不断速、到位不拖尾、到头有阻力”。

## 范围

- 包括：
  - `packages/live_ui/lib/src/theme/motion.dart`（弹簧、阈值、橡皮筋、带松手速度的模拟）。
  - `packages/live_ui/lib/src/widgets/scrolling.dart`（列表、标签条、翻页的滚动物理，Windows 滚轮，标签切换时长）、`refresh_view.dart`（下拉刷新和它的物理）、`scrollable_tab_bar.dart` 的滚轮横滚。
  - 应用里的滚动行为和自建拖动：`apps/pure_live/lib/app/app.dart` 的 `AppScrollBehavior`、5 个 `TabBarView`、`shared/panels/side_panel.dart`（面板下拉关闭）、直播间的换台、三档面板、详情面板、亮度和音量手势（`features/live_play/player/room_swipe.dart`、`layout/portrait_panel.dart`、`layout/room_details.dart`、`player/player_gestures.dart`、`logic/room_layout.dart` 的阈值）。
- 不包括（归哪里）：
  - 动效时长的常量（100–150、150–250、250–350 毫秒）→ A01.2 第 3 阶段；小菜单的展开动画 → A02.3（已做）。
  - 刷新率（按下和滚动时临时高刷、播放时按帧率）→ R02（`packages/live_ui/lib/src/widgets/refresh_rate.dart` 是 3.x 搬来的，归 R）；滚动和拖动时的帧耗时、重建 → R01（A03.3 的“拖面板不重建播放器”在这里）。
  - 三档面板的档位高度、换台的顺序和规则 → A07.2、A07.3；聊天列表跟到底部 → D04.1（已改成 `reverse: true`，`features/live_play/danmaku/chat_list.dart:434`）。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - **能下拉刷新的列表**（热门、分区房间、关注、观看记录、分区列表、WebDAV、备份）照 3.x：iOS 式减速（500 dp/s 滑 246 dp、2.17 秒，和 3.x 逐帧相同）、手指拉过头越拉越沉（最多手指的 0.52）、松手回弹、不画拉伸；快滑到顶停住、不带出刷新头；经典下拉头“下拉刷新 → 松开刷新 → 正在刷新... → 刷新成功 / 刷新失败”，第二行“上次刷新时间 H:mm”（A03.1，D-009）。
  - **其他列表**（设置、详情等）保持 Android 的 Clamping + 拉伸；苹果平台回弹。Windows 滚轮用 Chromium 的平滑曲线。
  - **标签页左右翻**（热门、关注、分区、关注的分区、直播间聊天区）约 0.27 秒停稳，和点标签的 220 毫秒对齐；快滑要 ≥400 dp/s 且 ≥25 dp（照 ViewPager），否则过半才翻，斜着上下滑不误翻（A03.2）。分区页的两层标签只能点、不能滑（照 3.x，`features/areas/areas_page.dart:181-186`）。
  - **面板**（直播间和多画面的录制、弹幕设置、本地互动、切换直播间）下拉一路跟手，松手顺着手的速度滑出或回位，往上甩不关闭、拉到最上面直接停住（A03.2，D-020）。
  - **直播间里的拖动**还是旧的：竖屏全屏换台松手后按 220 毫秒曲线从 0 速起步、到头硬停、动画完了才开始连新房间；三档面板 180 毫秒吸档、拖动时整个布局每帧重建；详情面板把手 20 高、不跟手；亮度音量每次手指移动都调一次系统接口（A03.3，暂停）。
- 内部怎么工作：
  - 所有弹簧和阈值在 `AppMotion`（`packages/live_ui/lib/src/theme/motion.dart:16`）一处定义，现在引用它的有：`PureLivePageScrollPhysics`（翻页）、`AppRefreshView`（`refreshSpring`）、`RoomSidePanel`（`panelSpring`、`panelFlingVelocity`）。直播间的几处（`room_layout.dart` 的 900/28、850/24、800/48，`room_details.dart` 的 600）还写着数字，由 A03.3 改成引用。
  - 松手：`AnimationController.unbounded` 记位移 → 松手时 `animateRelease(ReleaseSpringSimulation(spring, start, end, velocity: 手指速度))`：从屏幕上正在显示的那一帧开始计时（不停一帧，最多补一帧，`motion.dart:146-161`），到目标就停、不越过（`:112-143`）；移出屏幕的瞄准目标外 1%（`beyond`），免得慢尾巴。系统“移除动画”时直接到位。
  - 列表：`MaterialApp.scrollBehavior` = `AppScrollBehavior`（`apps/pure_live/lib/app/app.dart:283-302`，物理 `PureLiveScrollPhysics`，鼠标不能拖列表）；能下拉刷新的列表必须用 `AppRefreshView` 的 `builder` 给的物理（`_RefreshScrollPhysics`，照 easy_refresh 3.5.1 的 `_ERScrollPhysics` 移植，没有加依赖）。
- 完成度：A03.1、A03.2 已合并、待真机（手感要请用户和 3.x 对比）；A03.3 暂停（阶段 0/4，工作区在维护者本机，这里查不到）。和 3.x 比：列表减速和下拉曲线一致；回弹弹簧比 3.x 硬（0.34 秒对 0.65 秒，任务书定的 1/500/1，待用户定）；翻页阈值和弹簧是有意的改动（报告方案）；3.x 没有的换台、详情面板、侧面板下拉是 4.x 新设计的手感。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_ui/lib/src/theme/motion.dart` | `AppMotion`（`:16`）：`pageSpring` 1/600/1（`:21`）、`pageFlingVelocity` 400（`:25`）、`pageFlingDistance` 25（`:31`）、`panelSpring` 1/500/1（`:36`）、`refreshSpring`（`:41`）、`panelFlingVelocity` 700（`:46`）、`panelFullscreenFlingVelocity` 900 / `Distance` 28（`:50`、`:53`，3.x 值）、`panelRestoreFlingVelocity` 850 / `Distance` 24（`:57`、`:60`，3.x 值）、`roomSwipeSpring` 1/400/1（`:64`）、`roomSwipeFlingVelocity` 800 / `Distance` 48（`:67`、`:70`）、`overscrollSpring` 1/250/1（`:74`）、`controlSpring` 0.9/1400（`:78`）、`rubberBand`（`:87`，R·(x − x² + x³/3)，最多 R/3）、`tolerance`（`:96`）；`ReleaseSpringSimulation`（`:112`）；`ReleaseAnimation.animateRelease`（`:154`）；`_FromLastFrame`（`:165`） |
| `packages/live_ui/lib/src/widgets/scrolling.dart` | `pureLiveTabTransitionDuration` 220 毫秒（`:8`）；`PureLiveScrollPhysics`（`:12`，iOS、macOS 回弹，其他 Clamping；单独当父物理时也要有边界）；`PureLiveBoundedScrollPhysics`（`:64`，标签条和筛选条，内容变短时夹住位置）；`PureLivePageScrollPhysics`（`:97`，翻页的弹簧和阈值）；`createPureLiveScrollController`（`:121`，Windows 滚轮平滑）；`PureLiveRouteScrollScope`（`:135`，每个路由一个动画主滚动控制器）；`KeepAliveWrapper`（`:154`） |
| `packages/live_ui/lib/src/widgets/refresh_view.dart` | `AppRefreshFailure`（`:23`）、`AppRefreshMode`（`:32`）、`AppRefreshView`（`:73`，`onRefresh`、`builder`、`stopAtEnd`）、`minTriggerOffset` 70（`:83`）、`AppRefreshViewState.show()`（`:113`，代码触发刷新）、`_RefreshTracker`（`:197`，头部状态机）、`_RefreshScrollPhysics`（`:448`）、`_HeaderLayout`（`:479`，按文字量出头部高度）、`_RefreshHeader`（`:544`） |
| `packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart` | `ScrollableTabBar`（`:7`）、`_CrossPlatformTabBarScrollBehavior`（`:220`，鼠标能拖、滚轮横滚） |
| `apps/pure_live/lib/app/app.dart` | `AppScrollBehavior`（`:283-302`） |
| `apps/pure_live/lib/routes/app_router.dart`、`tv_router.dart` | `:111`、`:47` 每个页面套 `PureLiveRouteScrollScope` |
| `apps/pure_live/lib/features/popular/popular_page.dart:214`、`favorite/favorite_page.dart:264`、`areas/favorite_areas_view.dart:140`、`areas/platform_areas_view.dart:147`、`live_play/danmaku/chat_panel.dart:115` | 5 个 `TabBarView` 用 `PureLivePageScrollPhysics` |
| `apps/pure_live/lib/features/areas/areas_page.dart:181-186` | 分区页的 `TabBarView` 用 `NeverScrollableScrollPhysics`（照 3.x，避免两层横滑打架） |
| `apps/pure_live/lib/shared/rooms/room_grid.dart:616`、`:699`；`features/favorite/favorite_page.dart:509`；`history/history_page.dart:386`；`areas/platform_areas_view.dart:229`；`web_dav/web_dav_page.dart:506`、`:526`；`backup/backup_page.dart:280` | 用 `AppRefreshView` 的 8 处 |
| `apps/pure_live/lib/shared/panels/side_panel.dart` | `RoomSidePanel`（`:24`）：`AnimationController.unbounded` 记下拉位移（`:68`）、一直跟手（`:94`，往上硬停）、快甩 ≥700 看方向（`:104`）、减少动态效果直接关或回位（`:105`）、`animateRelease(ReleaseSpringSimulation(...))`（`:111-120`） |
| `apps/pure_live/lib/features/live_play/player/room_swipe.dart` | 竖屏全屏换台（A03.3 要改）：`RoomSwipeController`（`:18`）、`update`（`:67-76`，没有邻居时硬停 `:70-71`）、`_settleTo`（`:94-105`）、220 毫秒（`:182`）、预览封面解码（`:254-257`） |
| `apps/pure_live/lib/features/live_play/layout/portrait_panel.dart` | 三档面板（A03.3 要改）：`_drag`（`:127-149`，每次移动 `setState`）、`_release`/`_settle`（`:151-171`）、`AnimatedPositioned` 180 毫秒（`:207-216`）、读屏的增大减小（`:255-267`）、把手 `DragStartBehavior.down`（`:275`） |
| `apps/pure_live/lib/features/live_play/layout/room_details.dart` | 详情面板（A03.3 要改）：越界下拉 64 关（`:59`、`_onScroll` `:72-88`）、把手拖动 >600 关（`:108-130`，把手 20 高 `:119`） |
| `apps/pure_live/lib/features/live_play/player/player_gestures.dart` | 画面手势：左亮度右音量、换台的三栏；每次移动调平台（`:185-200`、`:199`，A03.3 要改） |
| `apps/pure_live/lib/features/live_play/logic/room_layout.dart` | 阈值：`panelDragEntersFullscreen`（`:166-170`）、`swipeRestoresPanel`（`:178-179`）、`swipeSwitchStep`（`:208-215`），数字还没引用 `AppMotion` |
| `apps/pure_live/lib/features/live_play/player/player_view.dart` | `_SwipeUpRegion`（`:845`，竖屏全屏底部上滑回到面板） |
| `apps/pure_live/lib/features/live_play/mini/floating_window.dart` | 应用内小窗拖动（`:191-194`，每次移动 `setState`，松手停在原处） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_ui/test/motion_test.dart`（13） | 翻页读到新弹簧和阈值、300 dp/s 不翻、600 dp/s 翻且 ≤300 毫秒、20 dp 快甩不翻、拖过半页翻、起手偏横的上滑不翻；各弹簧时间和阈值；橡皮筋单调且 ≤R/3；`ReleaseSpringSimulation` 起速等于手指、不越过、外瞄到目标就停；`animateRelease` 第一帧就走 |
| `packages/live_ui/test/refresh_view_test.dart`（13） | 500 / 1000 / 3000 / 6000 dp/s 的滑行；没有拉伸；下拉曲线和 3.x 一样；触发、刷新中停住、成功、1 秒后收回、失败写原因；快滑到顶停、到底弹回、`stopAtEnd`；`show()`；字放大头部变高 |
| `packages/live_ui/test/scrolling_test.dart`（2） | 当父物理或没 `applyTo` 时仍有边界（Android 硬边、iOS 回弹）；列表停在末尾 |
| `apps/pure_live/test/shared/side_panel_test.dart`（5） | 面板往下甩第一帧比 0.8～1.25、≤350 毫秒关；慢拉过 72 不停顿；拉一点不跳、不越过；往上甩不关；一直跟手到 500 dp 以上（改之前全部失败） |
| `apps/pure_live/test/features/live_play/room_swipe_test.dart`（9）、`live_play_layouts_test.dart:473`、`:519`、`:547`、`live_play_room_test.dart:365` | 换台的列表、阈值、预览；三档面板；详情关闭方式（还没有手感数字的测试，A03.3 要加） |
| `apps/pure_live/test/features/popular/popular_test.dart`、`favorite/favorite_test.dart`、`areas/areas_test.dart`、`history/history_page_test.dart`、`web_dav/web_dav_page_test.dart`、`settings/settings_page_test.dart` | 各列表用了 `AppRefreshView` 和 `PureLivePageScrollPhysics`；设置页仍有拉伸 |

## 3.x 基线

- 列表：`lib/common/widgets/pure_live_scroll_physics.dart`（52 行）：`PureLiveScrollPhysics`（`:6-17`，iOS、macOS 回弹，其他 Clamping）、`PureLiveBoundedScrollPhysics`（`:25`）、标签切换 220 毫秒（`:52`）；Windows 滚轮 `pure_live_scroll_controller.dart`（41 行）。
- 能刷新的列表套在 `EasyRefresh(child:)` 里（`lib/common/base/base_page_view_extension.dart:46`、`lib/modules/history/history_page.dart:202`），列表自己不写物理，实际是 easy_refresh 3.5.1 的 `_ERScrollPhysics`（继承 Bouncing，越界阻力 0.52(1−x)²，不画拉伸，`hitOver: false` 快滑到顶不出头）；头和尾 `lib/plugins/global.dart:17-38`、`:40-62`（字写反了）；关注页 `MaterialHeader(clamping: true)`（`lib/modules/favorite/room_grid_view.dart:129-134`）。
- 翻页：`TabBarView(physics: PureLiveBoundedScrollPhysics())`（`lib/modules/popular/popular_page.dart:38`、`lib/modules/favorite/favorite_page.dart:152`），没覆盖弹簧和阈值，Flutter 默认滚动弹簧（0.5/100/1.1，约 0.57 秒到位）、50 dp/s 就翻。
- 三档面板：`lib/modules/live_play/widgets/layout/live_play_content.dart:279`（`AnimatedSlide` 180 毫秒 easeOutCubic）；阈值 `portrait_fullscreen_interaction.dart:12-27`（30% 夹在 72–144，或 ≥900 且 ≥28）、`:39-41`（上滑 ≥64，或 ≤−850 且 ≥24）。
- 亮度和音量：`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:817`（`BrightnessVolumnDargArea`），每次移动调 `setBrightness`/`setVolume`（`:896`、`:898`）。
- 3.x 没有：竖屏全屏换台（A07.3 新加）、直播间详情面板（A07.1 新加）、直播间侧面板的下拉（A07.6 新加）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 4 条（左侧亮度、右侧音量，锁定锁住所有手势）、第 5 条（三档面板，拖过最低档或点把手进竖屏全屏，底部上滑退出）、第 9 条（换画质线路不重建播放器）；3.x 的阈值数值一个不改（`AppMotion` 原样保留了）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A03.1、A03.2 没在 K90 上看，手感没请用户对比 | 两个任务的 `verify.md` | — | A03.1、A03.2 待真机 |
| 回弹弹簧比 3.x 硬；快滑到顶要不要也弹一下 | `motion.dart:41`；`refresh_view.dart` | 和 3.x 不完全一样（0.34 对 0.65 秒） | 真机时请用户定（A03.1“留下的问题”） |
| 直播间的换台、三档面板、详情面板、亮度音量还是旧手感（固定时长曲线、硬停、每帧重建、20 高的把手、每次移动调平台） | 见代码地图里标“A03.3 要改”的行 | 直播间里最常用的拖动不顺 | A03.3（暂停，阶段 0/4） |
| 下拉刷新头不跟随“减少动态效果” | `refresh_view.dart`（没有 `disableAnimations` 判断） | 开了“移除动画”的用户还看到头部动画 | A05.1（c5） |
| 标签翻页松手第一帧停一帧（Flutter 的 `PageScrollPhysics` 从下一帧计时） | `TabBarView` 外包的物理 | 120 Hz 下 8 毫秒，几乎看不出 | 以后有空再做（A03.2“留下的问题”），没有任务 |
| 侧面板往上是硬停，没有橡皮筋 | `apps/pure_live/lib/shared/panels/side_panel.dart:94` | — | 不做（D-020，A03.2 建议保持） |
| 应用内小窗拖动每次移动 `setState`，松手没有惯性 | `features/live_play/mini/floating_window.dart:191-194` | 拖小窗时整层重建 | 没有任务管，建议在 A07.8 或 R01 登记 |
| `KeepAliveWrapper` 应用里没人用 | `scrolling.dart:154` | 多余的公开接口 | 下次改 `scrolling.dart` 时删掉 |

## 相关决定和规范

- D-009（能下拉刷新的列表照 3.x 两端回弹、经典下拉头；其他列表保持 Android 拉伸；快滑到顶直接停住）、D-020（往上甩面板不关闭；拉到最上面直接停住）。
- [specs/UI.md](../../specs/UI.md) 第 3 节原则 1（3.x 的操作习惯）、第 8.6 节（动效时长、减速曲线、跟随减少动态效果）、第 9.2 节（流畅度：局部刷新、滚动中不做重活）、附录 A 第 4、5、9 条。
- 调研报告 [V03.2](../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 2 节（S1～S11 改动清单、2.3 推荐参数）。

## 测试和验证

- 自动测试：`cd packages/live_ui && flutter test test/motion_test.dart test/refresh_view_test.dart test/scrolling_test.dart`；应用里 `flutter test test/shared/side_panel_test.dart test/features/live_play/room_swipe_test.dart`。手感的测法：widget 测试里按 K90（400×869 dp、3 倍、120 Hz）每 8.33 毫秒发一次触摸移动并 `pump`，松手后逐帧记位置，算第一帧比例、停稳时间（见 A03.2 README“测量”）。缺的：直播间拖动没有手感数字的测试（A03.3 加）。
- 真机：照 [A03.1 的 verify.md](A03.1-主列表手感/verify.md)（9 步，最好请用户在同一台手机上和 3.x 对比）、[A03.2 的 verify.md](A03.2-翻页和面板/verify.md)（8 步）；看手感用 profile 构建。[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)里相关的：第 1 节第 6 条（亮度、音量手势）、第 8 条（竖屏全屏三档面板、上滑退出）、第 4 节第 1 条（下拉刷新）。

## 路线

1. 维护者在 K90 上按 A03.1、A03.2 的 `verify.md` 看，请用户定“回弹软硬”“快滑到顶弹不弹”，定了改 `motion.dart:41` 一处。
2. [A03.3](A03.3-直播间拖动手感/README.md)（第二档，暂停）：换台和面板的弹簧 → 到头的橡皮筋 → 拖面板不重建播放器 → 把手和手势细节；常量已在 `AppMotion` 备好。直播间组同时只交给一个执行者。
3. 以后：小窗拖动、标签翻页的第一帧；“减少动态效果”在 A05.1 一起查。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`packages/live_ui`（motion、scrolling、refresh_view）、`features/live_play/`
- 进度：`████████████░░░░░░░░` 60%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A03.1 | 主列表手感：照 3.x 两端回弹，经典下拉刷新头 | 性能 | 待真机 | 2026-10-02 | 6e9e0da7e | [任务书](A03.1-主列表手感/brief.md)、[记录](A03.1-主列表手感/record.md) |
| A03.2 | 翻页和面板：弹簧带上松手速度，翻页阈值照 ViewPager | 性能 | 待真机 | 2026-10-02 | 7e1124e01 | [任务书](A03.2-翻页和面板/brief.md)、[记录](A03.2-翻页和面板/record.md) |
| A03.3 | 直播间拖动手感：换台、三档面板、详情面板带松手速度的弹簧和橡皮筋 | 性能 | 暂停 | — | — | [任务书](A03.3-直播间拖动手感/brief.md) |

## 还没完成的

- **A03.3 直播间拖动手感：换台、三档面板、详情面板带松手速度的弹簧和橡皮筋**（暂停，第二档，规模 中）
  - 阶段：换台和面板的弹簧 → 到头的橡皮筋 → 拖面板不重建播放器 → 把手和手势细节
  - 接着做：按任务书从头做
  - 分支：worktree-agent-a770fdd52c3109749（刚开始，未提交）

<!-- docs:生成结束 -->
