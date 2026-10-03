# A03.1 主列表手感：照 3.x 两端回弹，经典下拉刷新头

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机：代码 2026-10-02 合并）
- 类型：性能（手感）
- 来源：用户 2026-10-02：要“上下滑动、左右滑动的流畅度、阻尼感”；调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 0 节第 1 条（最高优先：主列表手感和 3.x 不一样）、第 2.1～2.3 节、2.5 节 S1、S10；维护者选报告的方案 A
- 旧编号：P02、T14c.1（见 [MAPPING.md](../../../MAPPING.md)）
- 相关：决定 D-009；下拉头的文字和状态来自 [A02.1](../../A02-组件/A02.1-通用组件/README.md) 第 41 行（界面清点表的列表外壳一行）、P19、c19；后续 [A03.2](../A03.2-翻页和面板/README.md)（把弹簧常量挪进 `motion.dart`）；R01.1 在它之后改 `room_grid.dart`
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)；真机：[verify.md](verify.md)

## 目标

能下拉刷新的列表（热门、分区房间、关注、观看记录、分区列表、WebDAV、备份）滑起来和 3.x 一样：iOS 式减速、拉过头越拉越沉、松手回弹、不画拉伸，下拉露出 3.x 的经典刷新头（文字改对）；其他列表（设置、详情等）保持 Android 的 Clamping + 拉伸不变。原因：这是 3.x 用户的肌肉记忆（[specs/UI.md](../../../specs/UI.md) 第 3 节原则 1），国内系统应用也是回弹；4.0 把这些列表换成了 Clamping + 拉伸和 Material 圆圈，500 dp/s 只滑 58 dp。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 改之前（4.0） | 现在（文件:行） |
|---|---|---|---|
| 刷新类列表的物理 | 套在 `EasyRefresh(child:)` 里（`lib/common/base/base_page_view_extension.dart:46`、`modules/history/history_page.dart:202`），列表自己不写 physics，用 easy_refresh 3.5.1 的 `_ERScrollPhysics`（继承 `BouncingScrollPhysics`，摩擦 0.135，越界阻力 0.52(1−x)²，不画拉伸） | `PureLiveScrollPhysics`（Android 是 Clamping + Material 3 拉伸） | `AppRefreshView` 的 `_RefreshScrollPhysics`（`packages/live_ui/lib/src/widgets/refresh_view.dart:448`），照 `_ERScrollPhysics` 移植，没有加依赖 |
| 下拉头 | `ClassicHeader`（`lib/plugins/global.dart:17-38`）：箭头 + 文字，触发距离 = 头部高度；字写反了（往下拉写“上拉刷新”，A02.1 P19）；关注页是 `MaterialHeader(clamping: true)`、触发 72（`modules/favorite/room_grid_view.dart:129-134`） | Material `RefreshIndicator` 圆圈（8 处） | 经典头 `_RefreshHeader`（`refresh_view.dart:544`）：“下拉刷新 → 松开刷新 → 正在刷新... → 刷新成功 / 刷新失败”，第二行“上次刷新时间 H:mm”；触发 = 头部高度（至少 70，`:83`） |
| 快滑到顶 | 停住，不带出刷新头（`hitOver: false`） | 停 + 拉伸 | 停住（照 3.x） |
| 上拉加载 | `ClassicFooter`（`global.dart:40-62`），离底 70 加载，到底“没有更多数据了” | 列表尾，离底 600 加载 | 列表尾照旧（离底 600）；还有更多时 `stopAtEnd` 让快滑停在列表尾（`AppRefreshView` 的参数） |
| 其他列表 | Clamping，无效果 | Clamping + 拉伸 | 不变（`apps/pure_live/lib/app/app.dart:283-302` 的 `AppScrollBehavior`） |
| 搜索平台条 | — | `overscroll: false`（唯一没有拉伸的横条） | 有拉伸（`features/search/search_widgets.dart`） |

## 结果

- 改动（任务书 c1～c5 都做了，逐条见 [record.md](record.md)）：
  - c1 方案 A：热门、分区房间（列表和空 / 出错状态）、关注、观看记录、分区列表、WebDAV、备份全部换成同一个组件；设置、详情等不动（加了测试）。关注页 3.x 是 Material 圆圈，这次为了一致也换成经典头。
  - c2 `AppRefreshView`（`refresh_view.dart:73`）：照 easy_refresh 3.5.1 的 `_ERScrollPhysics` + `ClassicHeader` 移植。向下箭头 + “下拉刷新” → 拉到头部高度箭头转 180° + “松开刷新” → 小转圈（随“加载样式”）+ “正在刷新...”，头部停在顶部 → “刷新成功”（✓）或“刷新失败”（红色 ⓘ + 原因）停 1 秒 → 弹簧收回（质量 1、刚度 500、阻尼比 1）。头部高度按文字量出来，字大了会变高。`AppRefreshViewState.show()`（`:113`）：观看记录标题栏的刷新按钮回到顶部、200 毫秒拉出头部再松手（照 3.x `callRefresh`）。
  - c3 8 处 `RefreshIndicator` 全部替换（`room_grid.dart` 网格和状态页、`favorite_page.dart`、`history_page.dart`、`platform_areas_view.dart`、`web_dav_page.dart` 两处、`backup_page.dart`），`lib/` 里已经没有 `RefreshIndicator`。现在的位置：`shared/rooms/room_grid.dart:616,699`、`features/favorite/favorite_page.dart:509`、`history/history_page.dart:386`、`areas/platform_areas_view.dart:229`、`web_dav/web_dav_page.dart:506,526`、`backup/backup_page.dart:280`。
  - c4 搜索平台条去掉 `overscroll: false`。
  - c5 电脑布局（`usesDesktopPages`）照旧：没有下拉，用翻页栏的刷新按钮；平板走手机布局，有下拉。
- 偏差和原因：
  1. 快滑到顶停住，不回弹；手指往下拉才有橡皮筋和刷新头——这是 3.x 的实际行为（`hitOver: false`），本机用 easy_refresh 3.5.1 量过：从 300 dp 以 3000 dp/s 往上滑，最低点 0.00。“两端回弹”指手指拉过头。
  2. 回弹弹簧比 3.x 硬：任务书定 1/500/1；3.x 用 Flutter 默认滚动弹簧（0.5/100/1.1）。松手到开始刷新、完成后收回、拉一点弹回从约 650 毫秒变成 342 毫秒；底部冲出从 58 dp 变成 39 dp。减速本身和 3.x 完全一样。
  3. 第二行写“上次刷新时间”（A02.1 图上是“上次加载时间”），翻译键沿用 3.x 的 `refresh_last_updated_at`，占位符从 `%T` 改成 `{time}`。
  4. 松手后、到位前（3.x 的 ready）显示“正在刷新...”和转圈（3.x 写“加载中...”）。
  5. 上拉加载没有搬进组件：房间列表已有 I 组确认过的列表尾（离底 600 自动加载），只加了 `stopAtEnd`。
  6. WebDAV 下拉时不再整页转圈（`_load(keepRows: true)`）。
  7. 改了任务书没列的 `features/areas/area_card.dart`（给 `AreaGrid` 加 `physics` 参数，默认值不变）。
  8. 不算安全区（这几处列表都在标题栏或标签栏下面）。
  9. 3.x 的 WebDAV、备份页没有下拉刷新（4.0 加的），现在和其他列表一样。
- 根因：3.x 的列表套在 `EasyRefresh` 里、自己不写 physics，实际用 `_ERScrollPhysics`；4.0 换成 `PureLiveScrollPhysics`（Android 上 Clamping + 拉伸）和 Material `RefreshIndicator`：减速快得多、列表在顶部不跟手、下拉的是圆圈；3.x 的字还是反的。
- 新翻译键（中 / 英）：`refresh_pull_to_refresh` 下拉刷新、`refresh_release_to_refresh` 松开刷新、`refresh_refreshing` 正在刷新...（3.x 键名）、`refresh_succeeded` 刷新成功、`refresh_failed` 刷新失败、`refresh_last_updated_at` 上次刷新时间 {time}（3.x 键名）；`AppIcons` 加 `refreshPull`、`refreshSucceeded`、`refreshFailed`。没有新设置。
- 后来：A03.2 把弹簧常量 `appRefreshSpring` 挪进 `packages/live_ui/lib/src/theme/motion.dart`，改名 `AppMotion.refreshSpring`（`:41`），数值不变；“要回到 3.x 的软弹簧”现在改那一处。
- 提交：合并提交 `42638dc3c`（2026-10-02，“Merge P02: refreshable lists feel like 3.x”）；记录 `6e9e0da7e`（登记表写的是这个）、`00a4508e5`（完成）。

## 性能任务：测量

测量方法：widget 测试里放一个 200 行、每行 100 dp 的列表，跳到 8000 dp 处，按给定速度松手（`goBallistic`，和真手指 `fling` 量出来一样），每 8.33 毫秒推一帧直到停；屏幕按 K90（400×869 dp、3 倍、120 Hz）。3.x 一列是在本机临时工程里用 easy_refresh 3.5.1 按 3.x 的配置（`ClassicHeader`、`ClassicFooter`）、同一个 Flutter 3.47.5 量的（临时工程不在仓库里）。

松手后的滑行：

| 松手速度 | 改之前（4.0：Clamping） | 改之后（`AppRefreshView`） | 3.x 实测 | 报告 2.2 节 3.x 一列 |
|---|---|---|---|---|
| 500 dp/s | 58.3 dp，0.29 s | 246.4 dp，2.17 s | 246.4 dp，2.17 s | 250 dp，约 2.2 s |
| 1000 dp/s | 194.3 dp，0.47 s | 496.1 dp，2.52 s | 496.1 dp，2.52 s | 499 dp，约 2.5 s |
| 3000 dp/s | 1308.9 dp，1.04 s | 1494.9 dp，3.07 s | 1494.9 dp，3.07 s | 1498 dp，约 3.0 s |
| 6000 dp/s | 4361.0 dp，1.73 s | 2993.0 dp，3.41 s | 2993.0 dp，3.41 s | 2996 dp，约 3.4 s |

体感：慢滑（500～1000）比改之前滑得远 2.5～4 倍、停得慢（拖尾长，iOS 的“滑溜”）；快滑（6000）反而短三分之一，单次最远约 3000 dp（连续快滑会叠加速度）。报告表里的距离是 iOS 减速公式的极限值 v ÷ ln(1/0.135)；Flutter 在速度低于 20/dpr dp/s（K90 是 6.67 dp/s）时就停，所以屏幕上停在极限前 3.33 dp：500 dp/s 时直接比差 1.4%，加上这 3.33 dp 差 0.06%；3000、6000 直接比差 0.2%、0.1%。时长和公式比差 0.3%～0.5%（120 Hz 一帧的取整）。

到头和下拉：

| 情况 | 改之前（4.0） | 改之后 | 3.x |
|---|---|---|---|
| 设置等其他列表到头 | 拉伸 | 拉伸（不变） | Clamping，无效果 |
| 刷新类列表到头（手指） | 拉伸 | 跟手，越拉越沉（最多手指的 0.52），松手弹回 342 ms | 同左，弹回 642 ms |
| 快滑到顶 | 停 + 拉伸 | 停，无效果，不出刷新头 | 同左 |
| 快滑到底（没有更多） | 停 + 拉伸 | 冲出 39 dp 弹回，共 0.48 s | 冲出 58 dp，0.82 s |
| 快滑到底（还有更多） | 停 + 拉伸，离底 600 dp 加载 | 停在列表尾，离底 600 dp 加载 | 停在加载尾，离底 70 dp 加载 |
| 下拉时列表 | 不动，圆圈落下 | 跟着往下走，头部在露出的空白里 | 同左 |
| 手指拉多远会刷新 | 约 220 dp（屏高的四分之一） | 约 150 dp（头部 70 dp） | 同左 |
| 手指 100 / 200 / 300 dp 时头部露出 | — | 49.1 / 93.0 / 132.5 dp | 同左 |
| 松手到开始刷新 | 167 ms | 342 ms（先弹到头部高度） | 650 ms |
| 刷新中 | 圆圈转 | 头部停在顶部，转圈 + “正在刷新...” | 同左（字一样） |
| 完成后 | 圆圈缩回约 0.2 s | “刷新成功”停 1 s，再用 342 ms 收回 | “加载成功”停 1 s，约 700 ms 收回 |
| 搜索平台条到头 | 无效果 | 拉伸（和其他横条一样） | — |

验收对照：500 / 3000 / 6000 dp/s 和报告误差 <1%（达到，和 3.x 实测逐帧相同）；下拉位移随手指距离单调变沉（达到，每 25 dp 的位移和 3.x 差 <0.05 dp）；到头部高度触发（70 dp，字放大 2 倍时按新高度）；刷新期间头部停住（2 秒中一直是 −70）；完成后 ≤400 ms 收回（342 ms）；文字和状态（中英文都有）。

## 验证

- 自动测试：新增 18 个、另有 6 处已有测试加了断言（改之前都会失败）：
  - `packages/live_ui/test/refresh_view_test.dart`（13）：各速度滑行；没有拉伸和光晕；下拉曲线和 3.x 一样；不够头部高度弹回；松开刷新、刷新中停住、刷新成功、1 秒后收回；失败写原因；快滑到顶停、到底弹回、`stopAtEnd`；手指拉过底弹回；`show()`；刷新中列表变长头部不动；手指按在头部上也能拖；字放大后头部变高。
  - `design_system_test.dart`：三个新图标。
  - `apps/pure_live/test/features/popular/popular_test.dart`（+1）、`history/history_page_test.dart`（+1）、`web_dav/web_dav_page_test.dart`（+1）、`settings/settings_page_test.dart`（+1，设置页仍有拉伸）；`favorite_test.dart`、`areas_test.dart`、`backup_page_test.dart`、`search_test.dart`、`i18n_test.dart` 加断言。
  - 合并时 `live_ui` 126 条、`apps/pure_live` 781 条通过；`python3 tools/gate/check_ui_structure.py` 通过。
- 真机：待真机，步骤在 [verify.md](verify.md)；手感要请用户本人和 3.x 对比。

## 留下的问题

- 需要维护者决定（[record.md](record.md)）：快滑到顶要不要也弹一下（现在照 3.x 停住）；弹簧要不要回到 3.x 的软弹簧（现在 0.35 秒停稳，3.x 约 0.65 秒，改 `motion.dart:41` 一处）。真机时一起定。
- 刷新头不看“减少动态效果”（`refresh_view.dart` 没有 `disableAnimations` 判断）：A05.1 检查时列入。
