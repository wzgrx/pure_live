# A03.2 翻页和面板：弹簧带上松手速度，翻页阈值照 ViewPager

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机：代码 2026-10-02 合并）
- 类型：性能（手感）
- 来源：用户 2026-10-02：要“上下滑动、左右滑动的流畅度、阻尼感”；调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 0 节第 2、5 条，第 2.3 节、2.5 节 S2（只做侧面板）、S3
- 旧编号：P03、T14c.2（见 [MAPPING.md](../../../MAPPING.md)）
- 相关：决定 D-020（往上甩面板不关闭、拉到最上面直接停住）；依赖 [A03.1](../A03.1-主列表手感/README.md)；常量给 [A03.3](../A03.3-直播间拖动手感/README.md) 用；侧面板的外观在 A02.2、A07.6
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)；真机：[verify.md](verify.md)

## 目标

- 标签页（热门、关注、分区、关注的分区、直播间聊天区）左右翻不再软绵绵：约 0.27 秒停稳（和点标签的 220 毫秒对齐），斜着上下滑不误翻（快滑要 ≥400 dp/s 且 ≥25 dp，照 Android ViewPager）。
- 直播间和多画面的侧面板（录制、弹幕设置、本地互动、切换直播间）下拉关闭时一路跟手，松手顺着手的速度走，不顿、不闪回。
- 全应用的弹簧和阈值在一个文件里定义（`motion.dart`），各处引用，不再各写各的数。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 改之前（4.0） | 现在（文件:行） |
|---|---|---|---|
| 标签页翻页物理 | `TabBarView(physics: PureLiveBoundedScrollPhysics())`（如 `lib/modules/popular/popular_page.dart:38`、`modules/favorite/favorite_page.dart:152`），没有覆盖 `spring` 和阈值：Flutter 默认滚动弹簧（质量 0.5、刚度 100、阻尼比 1.1），50 dp/s 就翻 | 同 3.x（6 个 `TabBarView`） | `PureLivePageScrollPhysics`（`packages/live_ui/lib/src/widgets/scrolling.dart:97`）：`spring` = 1/600/1（`:109`）、`minFlingVelocity` 400（`:112`）、`minFlingDistance` 25（`:115`）；用在 5 个 `TabBarView`（`features/popular/popular_page.dart:214`、`favorite/favorite_page.dart:264`、`areas/favorite_areas_view.dart:140`、`areas/platform_areas_view.dart:147`、`live_play/danmaku/chat_panel.dart:115`） |
| 点标签 | 220 毫秒（`lib/common/widgets/pure_live_scroll_physics.dart:52`） | 220 毫秒 | 220 毫秒（`scrolling.dart:8`，不变） |
| 侧面板下拉关闭 | 3.x 没有这个面板（直播间的面板是 A07.6 新设计）；3.x 的底部面板是 Material 的（700 dp/s 快滑） | `shared/panels/side_panel.dart:62-71,119-124`：拉到 400 dp 就不动；松手要么立刻关、要么 `setState` 跳回；关闭在直播间是 160 毫秒 easeInCubic 从 0 速起步，在多屏页当帧消失；往上甩也会因为已经拉过 72 而关闭；快滑阈值 600 | `RoomSidePanel`（`apps/pure_live/lib/shared/panels/side_panel.dart:24`）：`AnimationController.unbounded` 记位移（`:68`）、一直跟手到移出（`:94`）、快甩 ≥700 看方向（`:104`）、`animateRelease(ReleaseSpringSimulation(...))`（`:111-120`）、减少动态效果直接关或回位（`:105`） |
| 弹簧和阈值 | 各处写数字（3.x 面板 900 / 28、850 / 24） | 各处写数字（600 / 800 / 850 / 900 四种） | `AppMotion`（`packages/live_ui/lib/src/theme/motion.dart:16`），见下“结果” |

## 结果

- 改动（任务书 c1～c3 都做了，逐条见 [record.md](record.md)）：
  - c1 新建 `packages/live_ui/lib/src/theme/motion.dart`：`AppMotion` 一处定义——标签翻页弹簧 1/600/1、快滑 400 dp/s 和 25 dp；面板弹簧 1/500/1（A03.1 的 `appRefreshSpring` 挪进来改名 `AppMotion.refreshSpring`，数值不变）；面板快滑 700 dp/s（4.0 自己定的 600 改成 700）；3.x 来的阈值原样保留（三档面板拉进全屏 900 dp/s 且 28 dp、上滑回面板 850 dp/s 且 24 dp）；换台弹簧 1/400/1 和快滑 800 dp/s、48 dp；越界回弹弹簧 1/250/1（周期 0.4 秒）和橡皮筋公式 `rubberBand`；小控件 0.9/1400。现在引用它的：标签翻页物理、下拉刷新、侧面板。直播间里的几处（`room_layout.dart` 的 900/28、850/24，`room_details.dart` 的 600，`room_swipe.dart`、`portrait_panel.dart`）在 `features/live_play/`，本任务不能改，常量已备好，由 A03.3 改成引用。另加 `ReleaseSpringSimulation`（`:112`，带松手速度、不越过目标，可瞄准目标外一点、到目标就停）和 `animateRelease`（`:154`，从屏幕上正在显示的那一帧开始计时，最多补一帧）。
  - c2 `PureLivePageScrollPhysics`（继承 `PureLiveBoundedScrollPhysics`，只覆盖 `spring`、`minFlingVelocity`、`minFlingDistance`），用在 5 个 `TabBarView`；第 6 个（`room_switcher.dart`）没碰，合并 master 后 A07.13 已把它删掉，新的切换直播间面板没有 `TabBarView`（它用 `RoomSidePanel`，所以也有了 c3 的下拉手感）。`PureLiveBoundedScrollPhysics` 没改，标签条照旧用它。
  - c3 侧面板：标题栏下拉用 `AnimationController.unbounded` 记位移，一直跟手到完全移出；松手后用面板弹簧带着手指速度走：关闭时滑出视野再调 `onClose`，回位时回到原处、不越过；只重建位移（`AnimatedBuilder`），不再每帧 `setState` 整个面板；系统“移除动画”时直接关或回位。
- 根因：6 个 `TabBarView` 传的 `PureLiveBoundedScrollPhysics` 没有覆盖 `spring` 和快滑阈值，`TabBarView` 外包的 `PageScrollPhysics` 从父物理读这几个值，于是用的是 Flutter 默认滚动弹簧（到位 0.56 秒、完全停 0.83 秒）和 `kMinFlingVelocity` 50 dp/s、`kTouchSlop` 18 dp；上滑时只要横滑先抢到手势，一点点横向速度就翻页。侧面板 `_released` 要么立刻 `onClose()`，要么 `setState(() => _drag = 0)`，手指速度直接丢掉；拖动夹在 0～400；往上甩也关。
- 需要维护者决定的（[record.md](record.md)）：往上甩不再关闭面板（现在照 Android 和 Flutter 的底部面板，D-020）；慢慢拉过 72 dp 松手时弹簧会把面板加速带走（第一帧约 2.5 倍，0.29 秒关完，Flutter BottomSheet 一样）；“停稳”按 1% 算（按 Flutter 严格容差翻页完全停是 0.39 秒）；标签翻页松手第一帧仍原地停一帧（Flutter 的翻页惯性从下一帧计时，建议以后再做）；侧面板往上拉到原位是硬停（S6，没有任务管，建议保持）。
- 没有新设置、没有新翻译键、没有改 Android 原生代码。
- 提交：合并提交 `5f904f7cc`（2026-10-02，“Merge P03: pager and panel springs carry the release velocity; ViewPager fling thresholds”）；记录 `7e1124e01`（登记表写的是这个）、`39fccf783`（完成）。

## 性能任务：测量

测量方法：widget 测试里按 K90（400×869 dp、3 倍、120 Hz），每 8.33 毫秒发一次触摸移动并画一帧（和 Android 每帧交一次触摸事件一样），松手后逐帧记录位置。“到位”= 离最终位置不到 1% 页宽（4 dp），“完全停”= Flutter 的停止容差（1/3 dp、6.7 dp/s）。

标签页左右翻（热门、关注、分区、关注的分区、直播间聊天区）：

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

弹簧从静止出发到位（1%）的时间：

| 弹簧 | 时间 |
|---|---|
| 标签翻页 1/600/1 | 0.27 s |
| 面板、下拉刷新 1/500/1 | 0.30 s |
| 换台 1/400/1（A03.3 用） | 0.33 s |
| Flutter 默认滚动弹簧 0.5/100/1.1（翻页以前用的） | 0.57 s（报告写“约 0.5 秒”） |

侧面板下拉关闭（竖屏 16:9 画面下面，面板 644 dp 高）：

| 情况 | 改之前 | 改之后 |
|---|---|---|
| 一直往下拉 | 跟手，拉到 400 dp 就不动了 | 一直跟手到完全移出 |
| 拉 200 dp 往下甩（3000 dp/s） | 直播间：从松手处 160 ms easeInCubic 滑出（从 0 速起步，明显顿一下）；多屏页：当帧消失 | 带着手指速度滑出，第一帧位移是松手前一帧的 1.11 倍，0.27 s 移出后关闭 |
| 拉 100 dp 慢慢松手（600 dp/s，不算快滑） | 同上 | 弹簧加速带走，0.29 s 关闭 |
| 拉 30 dp 松手 | 一帧跳回原位（−30 dp） | 顺着手指再走约 2.5 dp、减速后弹回，0.32 s 停稳，不越过原位 |
| 拉 300 dp 再快速往回甩（2000 dp/s，松手时还拉着 100 dp） | 超过 72 dp → 关闭 | 留着，第一帧比 0.92，0.28 s 回到原位 |
| 快滑阈值 | 600 dp/s | 700 dp/s（和 Flutter BottomSheet、Dismissible 一样） |
| 拖动时 | 每次移动 `setState` 整个面板 | 只重建位移 |

验收对照：翻页约 0.27 秒停稳（达到）；300 dp/s 不翻、600 dp/s 翻（达到）；翻页停稳 ≤300 ms（0.27 s；拖过半页 0.24 s）；斜着上下滑不误翻（达到）；侧面板松手第一帧比 0.8～1.25（快甩达到：往下 3000 dp/s 是 1.11、往上 2000 dp/s 是 0.92；慢速松手不在这个范围，是临界阻尼弹簧的性质：离目标远时拉力大，关闭时被加速带走约 2.5 倍、回位先减速约 0.7 倍，都不是断速；120 Hz 下手指速度要到约 2400 dp/s 以上比例才落进 1.25 以内）；侧面板停稳 ≤350 ms（甩出 0.27 s、慢拉过 72 dp 0.29 s、拉一点回位 0.32 s、往上甩回位 0.28 s）。

另外：任何从触摸事件里启动的 `AnimationController`，第一帧动画时间都是 0，画面和松手前最后一帧一样，等于停一帧（改之前测出比例 0 的原因之一）；`animateRelease` 把模拟起点对齐到屏幕上正在显示的那一帧，第一帧就接着走（最多补一帧）。`TabBarView` 翻页的惯性是 Flutter 的 `PageScrollPhysics` 自己建的，仍从下一帧计时，没动。

## 验证

- 自动测试：新增 18 个，另有 4 个文件加了断言：
  - `packages/live_ui/test/motion_test.dart`（13）：`TabBarView` 读到新弹簧和阈值；300 dp/s 不翻（旧物理翻）、600 dp/s 翻且 ≤300 ms（旧的 >0.45 s）、20 dp 快甩不翻、拖过半页翻、起手偏横的上滑不翻；各弹簧时间和阈值数值；橡皮筋单调、越来越沉、最多 R/3；`ReleaseSpringSimulation` 起始速度等于手指速度、不越过、72 dp 回位 ≤350 ms、瞄准外侧到目标就停；`animateRelease` 第一帧就走、手指停了半秒再抬起最多补一帧。
  - `apps/pure_live/test/shared/side_panel_test.dart`（5）：往下甩比例 0.8～1.25、≤350 ms 关；慢拉过 72 不停顿；拉一点不跳、不越过；往上甩不关、比例 0.8～1.25；一直跟手到 500 dp 以上。**这 5 个在旧代码上全部失败**。
  - 加断言（物理是 `PureLivePageScrollPhysics`）：`popular_test.dart`、`favorite_test.dart`、`areas_test.dart`、`live_play_room_test.dart`。
  - 合并时 `live_ui` 161 条、`apps/pure_live` 802 条通过；`python3 tools/gate/check_ui_structure.py` 通过。
- 真机：待真机，步骤在 [verify.md](verify.md)。任务书写的是“横屏全屏打开录制面板下拉”，但横屏时面板从右侧进来，没有下拉关闭（A07.6），所以在竖屏和竖屏全屏里看。

## 留下的问题

- 直播间里的拖动（换台、三档面板、详情面板）还没用 `AppMotion` → [A03.3](../A03.3-直播间拖动手感/README.md)（暂停）。
- 侧面板往上是硬停（`side_panel.dart:94` 的 `clamp(0, _height)`）：建议保持（D-020）；要加橡皮筋用 `AppMotion.rubberBand` 几行。
- 标签翻页松手第一帧停一帧：120 Hz 下 8 毫秒，以后有空再做（要换掉 `TabBarView` 外面 `PageScrollPhysics` 的模拟）。
