# A03.2 记录：翻页和通用面板——弹簧带上松手速度、翻页阈值照 ViewPager

- 任务单：[tasks/P03.md](brief.md)；依据：[调研报告](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 2.3 节、2.5 节 S2（只做 `side_panel`）、S3
- 日期：2026-10-02；本地 worktree 任务（不建 `cloud/` 分支、不推送、不开 PR），基于 master `00a4508e5`（A03.1 之后），提交前合并了本地 master `7298301ef`（A02.2、A07.13 之后）
- 没有出设计；改变手感的地方，前后对比写在下面。用户原话：要“上下滑动、左右滑动的流畅度、阻尼感”

## 逐条对照

| 条 | 做了没有 | 说明 |
|---|---|---|
| c1 | 做了 | 新建 `packages/live_ui/lib/src/theme/motion.dart`，`AppMotion` 一处定义：标签翻页弹簧 1/600/1，快滑 400 dp/s、25 dp；面板弹簧 1/500/1（下拉刷新的 `appRefreshSpring` 挪进来，改名 `AppMotion.refreshSpring`，数值不变）；面板快滑 700 dp/s（4.0 自己定的 600 改成 700）；3.x 来的阈值原样保留（三档面板拉进全屏 900 dp/s 且 28 dp、上滑回面板 850 dp/s 且 24 dp）；换台弹簧 1/400/1 和快滑 800 dp/s、48 dp；越界回弹弹簧 1/250/1（周期 0.4 秒）和橡皮筋公式 `rubberBand`；小控件 0.9/1400。现在引用它的：标签翻页物理、下拉刷新、侧面板。直播间里的几处（`room_layout.dart` 的 900/28、850/24，`room_details.dart` 的 600，`room_swipe.dart`、`portrait_panel.dart`）在 `features/live_play/`，本任务不能改，常量已备好，由 A03.3 改成引用（见最后） |
| c2 | 做了 | `PureLivePageScrollPhysics`（在 `scrolling.dart`，继承 `PureLiveBoundedScrollPhysics`，只覆盖 `spring`、`minFlingVelocity=400`、`minFlingDistance=25`）。用在 5 个 `TabBarView`：热门（平台）、关注（平台）、关注的分区、分区（分类）、直播间聊天区。`room_switcher.dart`：按要求没有碰；合并 master 后这个文件已被 A07.13 删掉，新的“切换直播间”面板里没有 `TabBarView`（它用 `RoomSidePanel`，所以 c3 的下拉手感它也有了）。`PureLiveBoundedScrollPhysics` 没改，标签条照旧用它 |
| c3 | 做了 | `shared/panels/side_panel.dart`：标题栏下拉用 `AnimationController.unbounded` 记位移，一直跟手到面板完全移出（以前拉到 400 dp 就不动）；松手后 `animateRelease(ReleaseSpringSimulation(...))`，用面板弹簧带着手指速度走：关闭时滑出视野再调 `onClose`，回位时回到原处、不越过。只重建位移（`AnimatedBuilder`），不再每帧 `setState` 整个面板。系统“移除动画”时不做动画，直接关或回位 |

### 验收

| 项 | 结果 |
|---|---|
| 翻页约 0.27 秒停稳 | 达到：600 dp/s 翻页，0.27 s 到位（以前 0.56 s） |
| 300 dp/s 不翻页 | 达到（以前会翻） |
| 600 dp/s 翻页 | 达到 |
| 翻页停稳 ≤300 ms | 达到：0.27 s；慢慢拖过半页松手 0.24 s |
| 斜着上下滑不误翻 | 达到：起手先往侧边偏 24 dp（横滑先抢到手势）再快速上滑，以前翻到下一页，现在不翻 |
| 侧面板松手第一帧位移 / 松手前最后一帧 0.8～1.25 | 快甩达到：往下甩 3000 dp/s 是 1.11，往上甩 2000 dp/s 是 0.92。慢速松手不在这个范围，原因见“说明 2” |
| 侧面板停稳 ≤350 ms | 达到：甩出关闭 0.27 s，慢慢拉过 72 dp 松手关闭 0.29 s，拉一点松手回位 0.32 s，往上甩回位 0.28 s |

说明 1（“停稳”怎么算）：和调研报告 2.3 节一样，按“离最终位置不到 1%”算（1/600/1 的弹簧从静止出发 0.27 秒；Flutter 自己的 `AnimationController.fling` 也是到 1% 就停）。按 Flutter 滚动的严格容差（离目标不到 1 个物理像素即 1/3 dp、速度低于 6.7 dp/s）算“完全停住”，600 dp/s 翻页是 0.39 s（以前 0.83 s），下表两列都写了。到位之后每帧移动不到 1 dp 并且越来越慢，看不出来。

说明 2（为什么慢速松手的第一帧比例不在 0.8～1.25）：任务单要求的是 1/500/1 这种临界阻尼弹簧。松手时弹簧的起始速度就是手指速度（单元测试验证 `dx(0)` 等于手指速度），速度本身是连续的；但离目标远时弹簧的拉力很大（关闭时离移出还有 500 多 dp，起始加速度约 25 万 dp/s²），离目标近又往回拉。所以：快甩时速度占主导，第一帧比例在 1 附近；慢慢松手时，关闭会被弹簧加速带走（第一帧约 2.5 倍），回位会先顺着手指方向减速再弹回（约 0.7 倍），都不是“断速”。按 120 Hz 算，关闭时手指速度要到约 2400 dp/s 以上比例才落进 1.25 以内，这是弹簧本身的性质，Flutter 的 BottomSheet 也一样。

说明 3（松手第一帧原地不动的问题）：任何从触摸事件里启动的 `AnimationController`，第一帧的动画时间都是 0，画面和松手前最后一帧一模一样，等于停一帧（这也是改之前测出比例 0 的原因之一）。`animateRelease` 把模拟的起点对齐到屏幕上正在显示的那一帧，第一帧就接着走一帧的距离；最多补一帧（按屏幕刷新率），手指停了一会儿再抬起也不会跳。`TabBarView` 翻页的惯性是 Flutter 的 `PageScrollPhysics` 自己建的，仍然从下一帧计时，这次没动（见“需要维护者决定的”第 4 条）。

## 根因

- **翻页软、斜滑误翻**：6 个 `TabBarView` 都传了 `PureLiveBoundedScrollPhysics`，它没有覆盖 `spring` 和快滑阈值。`TabBarView` 外面包的 `PageScrollPhysics` 从父物理读这几个值，于是用的是 Flutter 默认滚动弹簧（质量 0.5、刚度 100、阻尼比 1.1，到位 0.56 s，完全停 0.83 s），快滑门槛是 `kMinFlingVelocity` 50 dp/s、`kTouchSlop` 18 dp。上滑时只要横滑先抢到手势，松手时一点点横向速度（超过 50 dp/s）就翻页。点标签的动画却只有 220 ms，两者对不上。
- **侧面板松手断速**：`_released` 要么立刻 `onClose()`，要么 `setState(() => _drag = 0)`，手指速度直接丢掉：回位是一帧跳回；关闭在直播间是 `AnimatedSwitcher` 的 160 ms easeInCubic 从速度 0 开始滑出，在多屏页（没有切换动画）是当帧消失。另外拖动夹在 0～400 dp，超过 400 不再跟手；往上甩也会因为已经拉过 72 dp 而关闭。

## 前后对比（K90：400×869 dp、3 倍、120 Hz；widget 测试量的）

测量方法：在 widget 测试里按 K90 的屏幕，每 8.33 ms 发一次触摸移动并画一帧（和 Android 每帧交一次触摸事件一样），松手后逐帧记录位置。“到位”= 离最终位置不到 1% 页宽（4 dp），“完全停”= Flutter 的停止容差。

### 标签页左右翻（热门、关注、分区、关注的分区、直播间聊天区）

| 情况 | 改之前 | 改之后 |
|---|---|---|
| 横滑 60 dp，300 dp/s 松手 | 翻到下一页，0.57 s 到位、0.83 s 完全停 | 不翻，回原页，0.17 s / 0.29 s |
| 横滑 60 dp，600 dp/s 松手 | 翻页，0.56 s / 0.83 s | 翻页，**0.27 s** / 0.39 s |
| 快速一甩只有 20 dp（600 dp/s） | 翻页，0.57 s / 0.84 s | 不翻（不到 25 dp） |
| 慢慢拖过半页（240 dp，200 dp/s）松手 | 翻页，0.48 s / 0.76 s | 翻页，0.24 s / 0.37 s |
| 起手往左偏 24 dp 再快速上滑（横向 240 dp/s） | 误翻到下一页 | 不翻，0.14 s 回位 |
| 点标签 | 220 ms | 220 ms（不变） |
| 算快滑 | >50 dp/s 且最近约 100 ms 移动 >18 dp | ≥400 dp/s 且 >25 dp（照 ViewPager）；否则过半才翻（不变） |
| 弹簧 | 质量 0.5、刚度 100、阻尼比 1.1 | 1、600、1（不过冲） |

### 弹簧从静止出发到位（1%）的时间

| 弹簧 | 时间 |
|---|---|
| 标签翻页 1/600/1 | 0.27 s |
| 面板、下拉刷新 1/500/1 | 0.30 s |
| 换台 1/400/1（A03.3 用） | 0.33 s |
| Flutter 默认滚动弹簧 0.5/100/1.1（翻页以前用的） | 0.57 s（报告写“约 0.5 秒”） |

### 侧面板下拉关闭（录制、弹幕设置、本地互动、切换直播间、多屏页的面板；竖屏 16:9 画面下面，面板 644 dp 高）

| 情况 | 改之前 | 改之后 |
|---|---|---|
| 一直往下拉 | 跟手，拉到 400 dp 就不动了 | 一直跟手到完全移出 |
| 拉 200 dp 往下甩（3000 dp/s） | 直播间：从松手处开始 160 ms easeInCubic 滑出（从 0 速起步，明显顿一下）；多屏页：当帧消失 | 带着手指速度滑出，第一帧位移是松手前一帧的 1.11 倍，0.27 s 移出后关闭 |
| 拉 100 dp 慢慢松手（600 dp/s，不算快滑） | 同上 | 弹簧加速带走，0.29 s 关闭 |
| 拉 30 dp 松手 | 一帧跳回原位（−30 dp） | 顺着手指再走约 2.5 dp、减速后弹回，0.32 s 停稳，不越过原位 |
| 拉 300 dp 再快速往回甩（2000 dp/s，松手时还拉着 100 dp） | 超过 72 dp → 关闭 | 留着，第一帧比 0.92，0.28 s 回到原位 |
| 快滑阈值 | 600 dp/s | 700 dp/s（和 Flutter BottomSheet、Dismissible 一样） |
| 拖动时 | 每次移动 `setState` 整个面板 | 只重建位移 |

下拉刷新（A03.1）的回弹弹簧只是换了地方，数值不变，手感不变。

## 改了哪些文件

- `packages/live_ui/lib/src/theme/motion.dart`（新）：`AppMotion`（弹簧、阈值、`rubberBand`、`tolerance`）、`ReleaseSpringSimulation`（带松手速度、不越过目标，可以“瞄准目标外一点、到目标就停”）、`AnimationController.animateRelease`（从屏幕上的那一帧开始计时）
- `packages/live_ui/lib/src/widgets/scrolling.dart`：`PureLivePageScrollPhysics`
- `packages/live_ui/lib/src/widgets/refresh_view.dart`：去掉顶层的 `appRefreshSpring`，改用 `AppMotion.refreshSpring`
- `packages/live_ui/lib/live_ui.dart`：导出 `motion.dart`
- `apps/pure_live/lib/shared/panels/side_panel.dart`：下拉关闭（合并 master 时和 A02.2 的 `PanelFrame`/`PanelHeader` 合在一起）
- 只改 physics 一行：`features/popular/popular_page.dart`、`features/favorite/favorite_page.dart`、`features/areas/favorite_areas_view.dart`、`features/areas/platform_areas_view.dart`、`features/live_play/danmaku/chat_panel.dart`
- 测试：见下

## 新设置和翻译键

无。

## 测试

新增 18 个测试，另有 4 个文件加了断言：

- `packages/live_ui/test/motion_test.dart`（13，新）：`TabBarView` 里确实读到新弹簧和阈值；300 dp/s 不翻（旧物理翻）、600 dp/s 翻且 ≤300 ms 到位（旧的 >0.45 s）、20 dp 快甩不翻（旧的翻）、拖过半页翻且 ≤300 ms、起手偏横的上滑不翻（旧的翻）；各弹簧的到位时间、阻尼比和阈值数值；橡皮筋单调、越来越沉、最多 R/3；`ReleaseSpringSimulation` 起始速度等于手指速度、不越过目标、72 dp 回位 ≤350 ms、瞄准目标外到目标就停；普通 `animateWith` 第一帧原地不动，`animateRelease` 第一帧就走了约一帧的距离（0.8～1.25 倍）；手指停了半秒再抬起最多补一帧。
- `apps/pure_live/test/shared/side_panel_test.dart`（5，新）：往下甩第一帧比例 0.8～1.25、单调、≤350 ms 关闭；慢慢拉过 72 dp 松手不停顿、≤350 ms 关闭；拉一点松手不跳、不越过原位、≤350 ms 回位；往上甩不关闭、比例 0.8～1.25、≤350 ms 回位；一直跟手到 500 dp 以上、拉回去停在原位。**这 5 个在旧代码上全部失败**（换回旧的 `side_panel.dart` 跑过：关闭当帧消失、回位一帧跳 −30 dp、往上甩关掉了、400 dp 后不跟手）。
- 加断言（5 处物理是 `PureLivePageScrollPhysics`）：`popular_test.dart`、`favorite_test.dart`、`areas_test.dart`（分类页；平台那层仍是 `NeverScrollable`；关注的分区）、`live_play_room_test.dart`（聊天区）。

跑过的检查（本地任务，没跑完整门禁；都是合并本地 master `7298301ef` 之后）：

- `packages/live_ui`：`dart format --output=none --set-exit-if-changed .` 通过；`dart analyze` 无问题；`flutter test` 全部 161 个通过。
- `apps/pure_live`：`dart format --output=none --set-exit-if-changed .` 通过；`flutter analyze` 无问题；`flutter test` 全部 802 个通过。
- 根目录 `python3 tools/gate/check_ui_structure.py` 通过。
- 没有改 Android 原生代码，没有编 apk。

## 要在 K90 上看的（维护者做）

准备：装这次的 debug 包。

1. **热门页左右翻平台**：手指横着拖，页面跟手；快速一甩翻页，约 0.27 秒停稳，不再有半秒的软尾巴；轻轻一拨（慢、短）回到原页不翻；拖过半页松手翻页。点标签切换和以前一样快（220 ms）。
2. **斜着上下滑 20 次**：在热门的房间列表上快速上下滑，故意斜一点、起手稍往侧边偏，20 次一次也不翻页。
3. **其他标签页一样**：关注（平台）、分区（分类）、关注的分区、直播间聊天区（聊天 / 醒目留言 / 弹幕设置 / 屏蔽词）。
4. **侧面板下拉关闭**：竖屏进直播间（16:9 画面在上），打开录制面板（弹幕设置、本地互动、切换直播间同样）：
   - 按住标题栏一直往下拉：面板一路跟手，可以拉到底（以前拉到一半多就不动）。
   - 快速往下甩：面板顺着手的速度滑出、关闭，中间不顿。
   - 拉一点就松手：顺势弹回原位，不闪回，也不会弹过头。
   - 往下拉一大段再快速往上甩：面板回到原位，不关闭（以前会关）。
   - 竖屏直播的全屏（面板从下方升起）、多屏页竖屏的弹幕面板，同样试一遍。
   - 任务单写的是“横屏全屏”，但横屏时面板从右侧进来，没有下拉关闭（A07.6），所以在竖屏和竖屏全屏里看。
5. **下拉刷新不变**：热门下拉刷新、松手回弹和 A03.1 一样（同一个弹簧，只是换了地方）。

## 需要维护者决定的

1. **往上甩不再关闭面板。** 以前只要拉过 72 dp，不管松手方向都关；现在照 Android 和 Flutter 的底部面板：快甩（≥700 dp/s）看方向，往下关、往上留；不是快甩才看拉了多远。想恢复旧行为改 `side_panel.dart` 一行。
2. **慢慢拉过 72 dp 松手时，弹簧会把面板加速带走**（第一帧约 2.5 倍，0.29 秒关完）。这是 1/500/1 弹簧的性质（Flutter BottomSheet 一样）。如果真机上觉得“猛”，可以只给关闭换一条更柔的弹簧，或者关闭改成“保持手指速度匀加速离开”。
3. **“停稳”按 1% 算**（和调研报告一致）。按 Flutter 的严格容差，翻页完全停是 0.39 秒。
4. **标签页翻页松手的第一帧仍会原地停一帧**（Flutter 自己的翻页惯性从下一帧计时，侧面板已经用 `animateRelease` 解决）。要解决得在 `TabBarView` 外面换掉 `PageScrollPhysics` 的模拟，收益是 120 Hz 下少停 8 ms，建议以后有空再做。
5. **侧面板往上拉到原位是硬停**（报告 S6 列了 `side_panel.dart:63`，要改橡皮筋）。S6 不在 A03.2 的任务里，A03.3 又只能改 `features/live_play/`，所以现在没有任务管它。面板往上本来就没地方去（和底部面板一样），我建议保持硬停；要加的话用 `AppMotion.rubberBand` 几行就够。

## 可能和别的任务冲突的文件

- **A03.3**：要用这次的 `AppMotion`（换台 1/400/1、面板 1/500/1、越界 1/250/1、`rubberBand`、各快滑阈值）和 `ReleaseSpringSimulation` / `animateRelease`，不要在 `features/live_play/` 里再定义一遍。`room_details.dart` 的 600 改成 `AppMotion.panelFlingVelocity`（700），`room_layout.dart` 的 900/28、850/24、`room_swipe` 的 800/48 改成引用对应常量（数值不变）。
- `apps/pure_live/lib/shared/panels/side_panel.dart`：A02.2 刚改过（`PanelFrame`、`PanelHeader`），这次合并时已经合好；之后再改面板外观的任务注意 `AnimatedBuilder` 和 `onVerticalDragStart`。
- `packages/live_ui/lib/src/widgets/refresh_view.dart`：`appRefreshSpring` 没有了（仓库里没有别处用），A03.1 记录里“改 `appRefreshSpring` 一处”现在是改 `AppMotion.refreshSpring`。
- `packages/live_ui/lib/live_ui.dart`：各任务都会加导出，按字母顺序合并即可。
- 5 个页面文件各只改了 physics 一行（`popular_page.dart`、`favorite_page.dart`、`favorite_areas_view.dart`、`platform_areas_view.dart`、`chat_panel.dart`），A02.1、A04.1 改这些页面时一般不会撞到。
- `room_switcher.dart`：没有碰；A07.13 已删掉它，新面板没有 `TabBarView`。

## K90 复查（2026-10-08，master ce7640a5b）

- 热门标签页：慢慢横拖约 60 dp 松手，停在原页 ✓；快速一甩翻到下一页（哔哩哔哩 → 斗鱼）✓，反向一甩回来 ✓。
