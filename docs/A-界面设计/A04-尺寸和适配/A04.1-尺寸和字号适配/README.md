# A04.1 尺寸和字号适配：高度分档、分屏、折叠屏、字号上限、触控区域

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机，第二档，规模中，阶段 3/3：高度分档 → 字号上限 → 触控区域；做法和结果见 [record.md](record.md)）
- 类型：性能（适配）
- 来源：调研报告 [V03.2](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md)（2026-10-02，用户要求调研“流畅度、刷新率、分辨率”）第 0 节第 9、11 条，第 3.1～3.3 节的 D1、D3、D4；[A02.1](../../A02-组件/A02.1-通用组件/README.md) 留下的“状态页按窗口判断：A04.1 做高度分档时复查”；[A02.3](../../A02-组件/A02.3-贴着按钮的小菜单/README.md) 留下的“折叠屏铰链没有避让”
- 旧编号：P06、T14g.1（见 [MAPPING.md](../../../MAPPING.md)）
- 相关：规范 [specs/UI.md](../../../specs/UI.md) 第 5.1 节（宽度、高度分档，高度紧凑优先，只读约束）、第 5.3 节（系统字体 1.3、1.5 倍不截断；桌面最小 360×400）、第 5.4 节（点击区域至少 48×48）、第 8.2 节（画面上的文字最多 1.3 倍）；D-018（`textScaleFactor` 键名和 0.5～2 的范围不变）；依赖 A02.1（待真机，已合并）；关联 [A05.1](../../A05-无障碍/A05.1-无障碍检查/README.md)（触控区域、读屏，A05.1 管全应用的检查，本任务只管尺寸相关的部分）、[A03.3](../../A03-动效和手感/A03.3-直播间拖动手感/README.md)（详情把手 48 dp 在那里做）
- 任务书：[brief.md](brief.md)；暂停时登记的工作区 `worktree-agent-a39fe9339ffb138a9`（“做了大半，未提交”）在维护者本机找到了，能用的改动已合并过来（见 [record.md](record.md)“旧工作区”）

## 目标

- 手机横着拿（高度 <480）、竖屏分屏（约 400×420）、折叠屏内屏、平板、桌面小窗口这些尺寸，页面都按**自己拿到的空间**排，而不是看整个屏幕：分屏时不会误当成横屏手机，折叠屏的铰链不压住内容。
- 字再大也有底：系统字号 × 应用“文字大小”最多 2 倍（3.x 最多也是 2 倍，因为它直接用应用的倍数替换了系统字号），画面上的控制层仍最多 1.3 倍。
- 主要页面上能点的东西都至少 48×48 dp，并且有测试锁住。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 宽度分档 | 一个分界 680、读整屏：`lib/common/base/base_page_view.dart:57`（`currentWidth > 680 && !PlatformUtils.isMobile` 才用电脑翻页）；网格固定断点 640 / 960 / 1280（`lib/modules/area_rooms/area_rooms_page.dart:52`、`modules/areas/areas_grid_view.dart:263`、`modules/favorite/room_grid_view.dart:38-40`） | `WindowWidthClass`（`packages/live_ui/lib/src/theme/grid_columns.dart:5`，<600 / 600–839 / 840–1199 / 1200–1599 / ≥1600）和 `GridColumns`（`:38`，列数按网格自己的宽度算）；用在 `shared/rooms/room_grid.dart`、`features/popular/popular_page.dart`、`favorite/favorite_page.dart`、`areas/area_card.dart` | 不变（已经照规范 5.1、5.3） |
| 高度分档 | 没有统一的；直播间各自判断：`lib/modules/live_play/widgets/content_first_panel_layout.dart:25`（宽 <720 或高 <520 算紧凑）、`video_controller_panel.dart:2131`（横屏且高 <620）、`iptv_schedule_dialog.dart:49`（高 ≤600 或字大于 1.5 倍） | 没有定义，各处写 480：9 处读**整屏**高度 `MediaQuery.sizeOf(context).height < 480`（见下表）；`features/multiview/multiview_page.dart:439`、`settings/playback_tiles.dart:627`、`recorder/recorder_page.dart:315` 按约束判断；直播间自己定义了 `roomCompactMaxHeight = 480`（`features/live_play/logic/room_layout.dart:62`，按 `LayoutBuilder` 的约束，`live_play_page.dart:1087-1092`）；状态页 `statusSideBySideHeight = 480`（`packages/live_ui/lib/src/widgets/status_view.dart:39`，按窗口，`:236`，有意的，见 A02.1） | `live_ui` 里有 `WindowHeightClass`（<480 / 480–899 / ≥900）和“横屏手机”的判断；9 处改成按约束；分屏 400×420 不算横屏手机 |
| 折叠屏 | 没有处理 | 没有处理：`apps/pure_live/lib` 和 `packages/live_ui/lib` 里没有 `displayFeatures`；小菜单没照搬 Flutter 的 `DisplayFeatureSubScreen`（A02.3 偏差） | 读 `MediaQuery.displayFeatures`，铰链两边分开排，内容和弹窗不跨铰链 |
| 文字缩放 | `lib/main.dart:184`：`TextScaler.linear(currentFactor)` **替换**系统字号，`currentFactor` 是 `textScaleFactor`，0.5～2（`lib/common/services/settings/font_settings_controller.dart:16-18`）；系统字号在应用里不起作用，所以总倍数最多 2 | `apps/pure_live/lib/app/app.dart:242-247`：`AppTextScaler(MediaQuery.textScalerOf(context), textScale)`（`packages/live_ui/lib/src/theme/text_styles.dart:175`）= 系统的（可能非线性的）倍数 × 应用倍数，没有上限：系统 2 倍 × 应用 2 倍约 4 倍；画面控制层 `features/live_play/player/player_view.dart:746-747` 用 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` | 总倍数每个字号最多 2 倍（`min(系统.scale(s) × 应用倍数, 2s)`），保留系统的非线性曲线；控制层 1.3 不变 |
| 触控区域 | 计数按钮 48×48（`lib/common/widgets/count_button.dart`）；回到顶部是 40 的小按钮（`base_page_view_extension.dart:64-99`，A02.1 P20） | A02.1 已把回到顶部、计数、头像等组件做到 48；没有任何 `meetsGuideline` 测试（`apps/pure_live/test`、`packages/live_ui/test` 里 0 处）；可能不到 48 的：`VisualDensity.compact` 8 处（`shared/links/supported_platforms.dart:63`、`features/search/search_widgets.dart:194`、`:633`、`search/search_view.dart:613`、`:633`、`live_play/switch_room/room_switch_panel.dart:516`、`settings/font_manager_page.dart:392`、`backup/log_page.dart:216`）、`MaterialTapTargetSize.shrinkWrap` 1 处（`room_switch_panel.dart:515`）；直播间详情把手 20 高（`live_play/layout/room_details.dart:119`，归 A03.3） | 主要页面 `meetsGuideline(androidTapTargetGuideline)` 通过；不到 48 的扩到 48（视觉不变，只扩点击区） |

整屏高度判断的 9 处（都是“矮窗口时标题栏 48 高，否则 56”）：

| 文件:行 | 用来做什么 |
|---|---|
| `packages/live_ui/lib/src/widgets/settings_page_frame.dart:21` | `settingsPageAppBar` 的 `toolbarHeight`（`:40`） |
| `apps/pure_live/lib/features/settings/settings_tiles.dart:652` | `settingsAppBar` 的 `toolbarHeight`（`:660`） |
| `features/settings/settings_page.dart:172` | 宽屏两栏时左栏标题区高度（`:183`） |
| `features/toolbox/toolbox_page.dart:153` | 工具箱标题栏 |
| `features/shield/shield_page.dart:30` | 屏蔽页标题栏 |
| `features/version/version_page.dart:156` | 版本页标题栏 |
| `features/version/release_history_view.dart:75` | 版本历史标题栏 |
| `features/about/about_page.dart:75` | 关于页标题栏 |
| `features/tags/tags_page.dart:182` | 标签管理标题栏 |

这些页面整屏读高度在竖屏分屏（400×420）时会把标题栏压成 48，算不上错；问题在于规范要求“只读父组件给的约束”，而且以后加别的高度判断（例如状态页横排、对话框高度）时没有一个统一的定义可用。

## 方案

- 改动清单（和登记表的三个阶段对应，详见 [brief.md](brief.md)）：
  - c1（阶段 1“高度分档”，D1）：`grid_columns.dart` 加 `WindowHeightClass`（紧凑 <480、中等 480–899、展开 ≥900）和“横屏手机”（高度紧凑且宽 > 高）的判断，写法可以借鉴之前从零写的版本 `git show v4-archive:packages/live_ui/lib/src/window_class.dart`（`HeightClass`、`isShortLandscape`）；上表 9 处改成按约束（`LayoutBuilder` 或调用处传入的尺寸）判断并引用常量；`roomCompactMaxHeight`、`statusSideBySideHeight`、`multiview_page.dart:439` 的 480 改成引用同一个常量（数值不变）；竖屏分屏（400×420）按“紧凑 / 紧凑”排，不出现横屏手机布局；折叠屏读 `MediaQuery.displayFeatures`：铰链（`DisplayFeatureType.hinge`、`fold` 的半开）横穿时内容不压在铰链上（至少：首页网格、设置两栏、对话框和面板用 `DisplayFeatureSubScreen` 或等效的避让）。
  - c2（阶段 2“字号上限”，D3）：`AppTextScaler` 加上限：每个字号 `min(system.scale(s) × factor, 2 × s)`，`textScaleFactor` 的线性估计同样封顶；写法照 `git show v4-archive:packages/live_ui/lib/src/text_scale.dart` 的 `CombinedTextScaler`（2026-09-28 提交 `c48cceb5d`、测试 `a43618912`，master 清空重来后没带过来）；控制层的 1.3 保留；设置里“文字大小”的范围（0.5～2）和键名不变（D-018）。
  - c3（阶段 3“触控区域”，D4）：首页（竖屏、宽屏）、热门、关注、分区、搜索、观看记录、设置总览和外观页、录制中心、直播间竖屏加 `expect(tester, meetsGuideline(androidTapTargetGuideline))`；不达标的扩点击区到 48（视觉尺寸不变），上表 `VisualDensity.compact` 和 `shrinkWrap` 的 9 处逐个确认。
- 不做：直播间详情把手（A03.3 的 c4）；读屏文字和对比度（A05.1）；宽度分档和网格列数（已经照规范，不动）。

## 性能任务：测量

| 指标 | 改之前（读代码） | 目标 | 怎么测 |
|---|---|---|---|
| 读整屏高度做布局的地方 | 9 处 `MediaQuery.sizeOf(context).height < 480` | 0 处（`grep` 为 0，状态页的窗口判断有注释说明例外） | `grep -rn "sizeOf(context).height <" apps/pure_live/lib packages/live_ui/lib` |
| 高度分档的定义 | 0 个（各处写 480） | 1 个，在 `live_ui` 导出 | 代码 |
| 尺寸 × 字号组合不溢出 | 没有测试 | 360×400、400×420、400×869、821×400、673×841、841×673、1280×800、1500×1000 各配 1.3 / 1.5 / 2.0 倍字号，主要页面 0 个溢出 | widget 测试 `tester.view.physicalSize` + `MediaQuery(textScaler:)`，断言 `tester.takeException()` 为空 |
| 最大文字倍数 | 系统 2 × 应用 2 ≈ 4 倍 | ≤2 倍（每个字号） | 单元测试 `AppTextScaler(TextScaler.linear(2), 2).scale(14) == 28` |
| 主要页面触控区域 | 没有检查 | `androidTapTargetGuideline` 全部通过 | widget 测试 |
| 竖屏分屏 400×420 | 设置类页面标题栏按整屏高度变 48 | 按约束判断；不出现横屏手机布局（直播间、多画面） | widget 测试 + K90 分屏 |

## 验证

- 自动测试（要加的，见任务书）：`packages/live_ui/test/` 的高度分档和 `AppTextScaler` 上限单元测试；`apps/pure_live/test/` 的尺寸 × 字号布局测试（8 个尺寸 × 3 个倍数，至少设置、热门、关注、直播间竖屏、多画面）和触控区域测试。现有可以参考的：`apps/pure_live/test/desktop_window_test.dart:459`、`:619`（360×400 最小窗口）、`features/live_play/live_play_layouts_test.dart`（直播间各布局）。
- 真机：没开始，完成后写 `verify.md`；步骤在 [brief.md](brief.md)“真机验证”（`wm size`、`wm density` 模拟其他机型，系统字体最大 + 应用 2 倍，分屏）。

## 留下的问题

- 暂停的工作区：已经看过并用上（2026-10-08，见 record.md）；那个工作区可以删了。
- 状态页按窗口（不是约束）判断横排是 A02.1 有意保留的（`SliverFillRemaining` 里不能用 `LayoutBuilder`），本任务只把 480 换成常量，不改判断方式。
- 规范第 5.3 节说“系统字体放大到 1.3 倍和 1.5 倍不截断”，上限 2 倍之后最坏情况是 2 倍；布局测试按 2.0 跑。
