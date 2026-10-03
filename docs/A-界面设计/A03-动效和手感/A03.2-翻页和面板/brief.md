# A03.2 翻页和通用面板：弹簧带上松手速度、翻页阈值照 ViewPager：任务书

> 本任务的开发已经合并（合并提交 `5f904f7cc`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及确认几处手感上的选择。下面保留开工时的全部要求（原任务单，旧编号 P03），按任务书模板 v2 重排，“现状”一节是合并后读代码写的。

## 背景

- 来源：用户 2026-10-02：要“上下滑动、左右滑动的流畅度、阻尼感”；调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 2.3 节（推荐参数）、2.5 节 S2（只做侧面板 `side_panel`）、S3（翻页）。
- 现象（开工前）：标签页左右翻软绵绵（约 0.5 秒才停稳），斜着上下滑会误翻页；侧面板下拉关闭时松手断速：回位一帧跳回，关闭从 0 速起步或当帧消失，拉到 400 dp 不再跟手。
- 规模：中；分组：手感；依赖：A03.1；能否和别的任务同时做：手感组，A03.1 之后。
- 出设计：不用（照调研报告和本任务书；改变手感的地方在记录里写清前后对比）。

## 目标和验收

1. 翻页不再软绵绵（约 0.27 秒停稳）、斜着上下滑不误翻；侧面板松手不断速。
2. 测试：300 dp/s 不翻页、600 dp/s 翻页、停稳 ≤300 ms；侧面板松手后第一帧位移和松手前最后一帧之比在 0.8～1.25，停稳 ≤350 ms。
3. 弹簧和阈值常量一处定义，各处引用。
4. 真机：热门页左右翻分类跟手、停得干脆，上下滑列表 20 次（斜着滑）不误翻；侧面板下拉关闭跟手，松手顺滑。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-03）：

- `packages/live_ui/lib/src/theme/motion.dart`：`AppMotion`（`:16`，弹簧 `:21`、`:36`、`:41`、`:64`、`:74`、`:78`；阈值 `:25`、`:31`、`:46`、`:50`、`:53`、`:57`、`:60`、`:67`、`:70`；`rubberBand` `:87`；`tolerance` `:96`）、`ReleaseSpringSimulation`（`:112`）、`animateRelease`（`:154`）。
- `packages/live_ui/lib/src/widgets/scrolling.dart`：`PureLivePageScrollPhysics`（`:97`，`spring` `:109`、`minFlingVelocity` `:112`、`minFlingDistance` `:115`）；`PureLiveBoundedScrollPhysics`（`:64`）没改。
- 5 个 `TabBarView`：`apps/pure_live/lib/features/popular/popular_page.dart:214`、`favorite/favorite_page.dart:264`、`areas/favorite_areas_view.dart:140`、`areas/platform_areas_view.dart:147`、`live_play/danmaku/chat_panel.dart:115`。
- 侧面板 `apps/pure_live/lib/shared/panels/side_panel.dart`：`_closeDistance` 72（`:65`）、位移控制器（`:68`）、拖动（`:94`）、松手（`:104-120`）、减少动态效果（`:105`）。
- 还没引用 `AppMotion` 的（在 `features/live_play/`，归 A03.3）：`logic/room_layout.dart:166-170`（900 / 28）、`:178-179`（850 / 24）、`:208-215`（800 / 48）；`layout/room_details.dart:115`（600）；`player/room_swipe.dart:182`（220 毫秒）；`layout/portrait_panel.dart:207`（180 毫秒）。

## 3.x 基线

- 3.x 的 `TabBarView` 也用 `PureLiveBoundedScrollPhysics`（`lib/modules/popular/popular_page.dart:38`、`modules/favorite/favorite_page.dart:152`、`modules/areas/areas_grid_view.dart:213`、`modules/areas/favorite_areas_page.dart:108`、`modules/live_play/widgets/danmaku/danmaku_tab.dart:26`、`modules/live_play/dialogs/play_other.dart:198`），翻页同样是 Flutter 默认弹簧和 50 dp/s 的阈值——这次是照 Android ViewPager 改进，不是还原 3.x。点标签 220 毫秒（`lib/common/widgets/pure_live_scroll_physics.dart:52`）保留。
- 3.x 的面板阈值（`lib/modules/live_play/widgets/layout/portrait_fullscreen_interaction.dart:12-41`：30% 夹在 72–144、900 且 28；上滑 64 或 −850 且 24）原样进 `AppMotion`。
- 要保留：点标签的 220 毫秒；分区页平台那一层 `NeverScrollable`（只能点标签切，照 3.x，避免两层横滑打架，`apps/pure_live/lib/features/areas/areas_page.dart:186`）；D-020。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 8.6 节、第 9.2 节。
3. 调研报告 `docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 2.3 节、2.5 节 S2（只做 `side_panel`）、S3。
4. 本文件夹的 `README.md`、[record.md](record.md)；[A03.1](../A03.1-主列表手感/README.md)。

## 范围

- 可以改：`packages/live_ui`；c2 列出的 6 个文件（只改 physics 一行）；`apps/pure_live/lib/shared/panels/side_panel.dart`。
- 不能改：其他目录（直播间里的拖动归 A03.3）；`PureLiveBoundedScrollPhysics`（标签条在用）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

一个阶段做完：

| 编号 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| c1 | 新建 `packages/live_ui/lib/src/theme/motion.dart`：报告 2.3 节的弹簧和阈值常量（标签翻页 1/600/1；面板 1/500/1；小控件 0.9/1400；快滑阈值：3.x 来的保留，4.x 自己定的 600 改成 700），各处引用它 | `motion.dart`（新）、`refresh_view.dart`、`live_ui.dart` | `motion_test.dart` 的常量组通过 |
| c2 | S3：新建 `PureLivePageScrollPhysics`（覆盖 `spring`、`minFlingVelocity=400`、`minFlingDistance=25`），给当时的 6 个 `TabBarView` 用：`popular_page.dart:211`、`favorite_page.dart:258`、`favorite_areas_view.dart:138`、`platform_areas_view.dart:176`、`chat_panel.dart:109`、`room_switcher.dart:103`（A07.13 合并后已删）；不改 `PureLiveBoundedScrollPhysics` | `scrolling.dart`、5 个页面 | 翻页测试通过 |
| c3 | S2：`side_panel.dart` 当时 `:62-71,119-124` 的下拉关闭：跟手，松手后用带速度的弹簧（`AnimationController.unbounded` + 带速度的 `SpringSimulation`）关闭或回位，不再直接跳回 | `shared/panels/side_panel.dart` | `side_panel_test.dart` 5 条通过（旧代码全失败） |

## 测试

- 已有：`packages/live_ui/test/motion_test.dart`（13）、`apps/pure_live/test/shared/side_panel_test.dart`（5）；热门、关注、分区、直播间的测试加了物理断言。
- 300 dp/s 不翻页、600 dp/s 翻页、停稳 ≤300 ms；侧面板松手后第一帧位移和松手前最后一帧之比在 0.8～1.25，停稳 ≤350 ms。
- 测试里逐帧推（8.33 毫秒一帧）；定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 热门页左右翻分类 | 跟手、停得干脆 |
| 2. 上下滑列表 20 次（斜着滑） | 一次也不误翻 |
| 3. 打开录制面板，下拉标题栏关闭（原任务单写横屏全屏；横屏时面板在右侧、没有下拉关闭，所以在竖屏和竖屏全屏看） | 跟手，松手顺滑 |

完整步骤见 [verify.md](verify.md)（8 条）。

## 风险和注意

- A03.3 要用这里的 `AppMotion`（换台 1/400/1、面板 1/500/1、越界 1/250/1、`rubberBand`、各快滑阈值）和 `ReleaseSpringSimulation` / `animateRelease`，不要在 `features/live_play/` 里再定义一遍；`room_details.dart` 的 600 改成 `AppMotion.panelFlingVelocity`（700），`room_layout.dart` 的 900/28、850/24 和换台的 800/48 改成引用（数值不变）。
- `shared/panels/side_panel.dart` 和 A02.2 的 `PanelFrame`、`PanelHeader` 合在一起，改面板外观时注意 `AnimatedBuilder` 和 `onVerticalDragStart`。
- 待维护者确认的手感选择见 [README.md](README.md)“结果”。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A03.2` 或本机工作区；提交信息以 `[A03.2]` 开头（英文）；不推 master。
- 提交前：`packages/live_ui`、`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 末尾写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；前后对比的数字（到位时间、第一帧比例）；根因；测试数量（旧代码上失败几条）；改了哪些文件；要在真机上看的；需要维护者决定的；可能冲突的文件。
