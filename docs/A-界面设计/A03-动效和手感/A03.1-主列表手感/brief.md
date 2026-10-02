# A03.1 主列表的滑动手感：照 3.x 两端回弹 + 经典下拉刷新头：任务书

> 本任务的开发已经合并（合并提交 `42638dc3c`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看、请用户对比手感，以及两个待定的选择（见“风险和注意”）。下面保留开工时的全部要求（原任务单，旧编号 P02），按任务书模板 v2 重排，“现状”一节是合并后读代码写的。

## 背景

- 来源：用户 2026-10-02：要“上下滑动、左右滑动的流畅度、阻尼感”；调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 0 节第 1 条（最高优先）、第 2.1～2.3 节、2.5 节 S1、S10。
- 现象（开工前）：热门、关注等列表在 Android 上是 Clamping + 拉伸，500 dp/s 只滑 58 dp、0.29 秒就停；下拉是 Material 圆圈，列表不跟手；3.x 用户习惯的是 iOS 式减速、两端回弹和经典刷新头。
- 决定：维护者选了报告的**方案 A**（D-009）：所有能下拉刷新的列表（热门、分区房间、关注、历史、分区列表、WebDAV、备份）照 3.x 用两端回弹（Bouncing 系）、不画拉伸、经典下拉头；其他列表（设置、详情等）保持 Android 的 Clamping + 拉伸。理由：3.x 用户的习惯（[specs/UI.md](../../../specs/UI.md) 原则 1），国内系统应用也是回弹。3.x 关注页原来是 Material 圆圈，这次为了一致也换成经典头，记录里写明。
- 规模：中；分组：手感；依赖：无；能否和别的任务同时做：和 A03.2、R01.1 依次做（都会改 `scrolling.dart` 或 `room_grid.dart`）；和其他组可以同时。
- 出设计：不用（照调研报告和本任务书；改变手感的地方在记录里写清前后对比）。

## 目标和验收

1. 所有能下拉刷新的列表手感一致、和 3.x 一样两端回弹；下拉头文字正确。
2. 固定 500 / 3000 / 6000 dp/s 的滑行距离和时长，和报告 2.2 节表里 3.x 一列误差 <1%。
3. 下拉位移随手指距离单调变沉；到头部高度触发；刷新期间头部停住；完成后 ≤400 毫秒收回。
4. 文字和状态有测试。
5. 真机：热门页快速上滑、到底、到顶两端回弹不出现拉伸；下拉热门：箭头 → 松开刷新 → 转圈 → 刷新成功，头部停住再收回；设置页到头仍然是拉伸。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-03）：

- `packages/live_ui/lib/src/widgets/refresh_view.dart`：`AppRefreshFailure`（`:23`）、`AppRefreshMode`（`:32`）、`AppRefreshView`（`:73`，`onRefresh`、`builder`、`stopAtEnd`）、`minTriggerOffset` 70（`:83`）、`AppRefreshViewState.show()`（`:113`）、`_RefreshTracker`（`:197`）、`_RefreshScrollPhysics`（`:448`）、`_HeaderLayout`（`:479`）、`_RefreshHeader`（`:544`）。弹簧 `AppMotion.refreshSpring`（`packages/live_ui/lib/src/theme/motion.dart:41`，A03.2 挪过去的）。
- 用在：`apps/pure_live/lib/shared/rooms/room_grid.dart:616`（网格）、`:699`（状态页）；`features/favorite/favorite_page.dart:509`；`features/history/history_page.dart:386`；`features/areas/platform_areas_view.dart:229`；`features/web_dav/web_dav_page.dart:506`、`:526`；`features/backup/backup_page.dart:280`。应用里没有 `RefreshIndicator`。
- 其他列表：`apps/pure_live/lib/app/app.dart:283-302` 的 `AppScrollBehavior` 给 `PureLiveScrollPhysics`（`packages/live_ui/lib/src/widgets/scrolling.dart:12`）。
- 文字：`apps/pure_live/assets/translations/zh.json` 的 `refresh_pull_to_refresh`、`refresh_release_to_refresh`、`refresh_refreshing`、`refresh_succeeded`、`refresh_failed`、`refresh_last_updated_at`。

## 3.x 基线

- 列表套在 `EasyRefresh` 里：`lib/common/base/base_page_view_extension.dart:46`、`lib/modules/history/history_page.dart:202`；自己不写 physics，实际用 easy_refresh 3.5.1 的 `_ERScrollPhysics`（`easy_refresh-3.5.1/lib/src/physics/scroll_physics.dart:10`，在 `:492` 建 `BouncingScrollSimulation`）；`ERScrollBehavior.buildOverscrollIndicator` 不画拉伸；`hitOver: false`。可以 `dart pub cache add easy_refresh --version 3.5.1` 下来看。
- 头和尾：`lib/plugins/global.dart:17-38`（`ClassicHeader`，触发距离 = 头部高度）、`:40-62`（`ClassicFooter`）；字写反了（A02.1 P19）。关注页 `lib/modules/favorite/room_grid_view.dart:129-134`（`MaterialHeader(triggerOffset: 72, clamping: true)`）。
- 其他列表 Clamping（`lib/common/widgets/pure_live_scroll_physics.dart:6-17`）。
- 要保留：滑行减速和下拉曲线和 3.x 一样；快滑到顶停住；上拉加载“没有更多数据了”。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 8.6 节、第 9.2 节。
3. 调研报告 `docs/V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md` 第 2.1～2.3 节、2.5 节 S1、S10；下拉刷新头的文字和状态：`docs/A-界面设计/A02-组件/A02.1-通用组件/README.md` 界面清点表“列表外壳”一行、P19、c19。
4. 本文件夹的 `README.md`、[record.md](record.md)。

## 范围

- 可以改：`packages/live_ui`；c3、c4 列出的文件（`shared/rooms/room_grid.dart`、`features/favorite/favorite_page.dart`、`features/history/history_page.dart`、`features/areas/platform_areas_view.dart`、`features/web_dav/web_dav_page.dart`、`features/backup/backup_page.dart`、`features/search/search_widgets.dart`）；当时另改了 `features/areas/area_card.dart`（加 `physics` 参数，记录里写明）。
- 不能改：其他目录；设置等非刷新类列表的物理；版本号、`assets/version.json`、`assets/releases.json`；不加新的第三方依赖。

## 方案和阶段

一个阶段做完：

| 编号 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| c1 | 方案 A：刷新类列表照 3.x，其他不动 | 见 c3 | 设置页仍有拉伸（测试） |
| c2 | `live_ui` 的下拉刷新组件 `AppRefreshView`：经典头（向下箭头 → 松手前箭头朝上 → 刷新中小转圈 → 完成或失败），文字用 A02.1 c19 改对后的（下拉刷新 / 松开刷新 / 正在刷新... / 刷新成功 / 刷新失败，下面一行“上次刷新时间”）；触发距离 = 头部高度；刷新期间头部停在顶部，完成后弹簧收回（质量 1、刚度 500、阻尼比 1）；行为照 easy_refresh 3.5.1；上拉加载照 3.x（到底自动加载，“没有更多数据了”） | `packages/live_ui/lib/src/widgets/refresh_view.dart`（新）、`scope.dart`、`app_icons.dart`、`live_ui.dart` | `refresh_view_test.dart` 13 条通过 |
| c3 | 替换全部 `RefreshIndicator`：当时的 `shared/rooms/room_grid.dart:666,746`、`features/favorite/favorite_page.dart:549`、`features/history/history_page.dart:415`、`features/areas/platform_areas_view.dart:262`、`features/web_dav/web_dav_page.dart:515,535`、`features/backup/backup_page.dart:294` | 同左 | `lib/` 里没有 `RefreshIndicator` |
| c4 | S10：`features/search/search_widgets.dart:100` 的 `overscroll: false` 去掉，横条和其他横条一样 | 同左 | 搜索平台条有拉伸 |
| c5 | 平板和电脑布局照旧（电脑没有下拉，用刷新按钮） | — | 电脑布局测试不变 |

## 测试

- 已有：`packages/live_ui/test/refresh_view_test.dart`（13 条）；`apps/pure_live` 的热门、观看记录、WebDAV、设置页各 +1，关注、分区、备份、搜索、多语言加断言（见 [README.md](README.md)“验证”）。
- 固定 500 / 3000 / 6000 dp/s 的滑行距离和时长（和报告 2.2 节表里 3.x 一列误差 <1%）；下拉位移随手指距离单调变沉、到头部高度触发、刷新期间头部停住、完成后 ≤400 ms 收回；文字和状态。
- 定时器至少 1 秒（“刷新成功”停 1 秒）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 热门页快速上滑、到底、到顶 | 两端回弹，不出现拉伸 |
| 2. 下拉热门 | 箭头 → 松开刷新 → 转圈 → 刷新成功，头部停住再收回 |
| 3. 设置页到头 | 仍然是拉伸（不变） |

完整步骤见 [verify.md](verify.md)（9 条）。

## 风险和注意

- 两个待定（真机时请维护者定）：快滑到顶要不要也像 iOS 那样弹（要的话在 `refresh_view.dart` 去掉“快滑到顶停住”，刷新头会被惯性带出来一点但不触发）；弹簧要不要回到 3.x 的软弹簧（改 `motion.dart:41` 的 `AppMotion.refreshSpring`）。
- `shared/rooms/room_grid.dart`：R01.1 在它之后改过（顶部进度条和转圈），网格包成了 `list(physics)` 函数。
- 翻译文件、`scope.dart`、`app_icons.dart` 各任务都会往里加，按键名排序合并。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A03.1` 或本机工作区；提交信息以 `[A03.1]` 开头（英文）；不推 master。
- 提交前：`packages/live_ui`、`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 末尾写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；前后对比的数字（滑行、下拉、收回）；根因；测试数量；改了哪些文件；新翻译键；要在真机上看的；需要维护者决定的；可能冲突的文件。
