# A04.1 尺寸和字号适配：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区 `worktree-agent-a0aa96c1b7aaaa422`（从 master `ce7640a5b` 开始）
- 设计或说明：[README.md](README.md)；任务书 [brief.md](brief.md)
- 这一轮的范围：Android 手机优先；分屏、折叠屏、平板的尺寸只在 widget 测试里模拟（K90 是 1200×2608、480 dpi，约 400×869 dp）。

## 旧工作区

暂停时登记的工作区 `worktree-agent-a39fe9339ffb138a9` 还在本机（停在 `1d08cfa02`，改动没提交）。只读不动：把它和 `1d08cfa02` 比出改动，再三方合并到现在的代码上（`diff3`），逐个文件看过才拿过来。

| 旧改动 | 结果 |
|---|---|
| `live_ui`：`WindowHeightClass`、`WindowClass`（`isShort`、`isPhoneLandscape`）、`WindowClassScope`、`DisplayHinge`、`compactToolbarHeight`，单元测试 `window_layout_test.dart` | 用了；加了常量 `windowCompactHeight`（480）、`windowExpandedHeight`（900），测试加了边界和“横着拿的手机分屏”两个尺寸、对话框不跨铰链 |
| 9 处标题栏高度、设置两栏、版本历史两栏的铰链避让、小菜单和面板的铰链避让、状态页横排的判断 | 用了（合并时 `adaptive_panel.dart` 有一处冲突，手工合） |
| 多画面选台面板太矮时整体滚动（`room_picker.dart`） | 用了：新加的分屏测试在 400×420 下溢出 21～35，就是它要修的 |
| `AppTextScaler` 上限 | 用了（第 2 阶段），测试另写在 `text_scale_test.dart`，加了非线性系统曲线 |
| 尺寸 × 字号的布局测试、几个页面的溢出修复（分区、日志、平台管理、设备同步、配置预览、小窗弹幕、状态页滚动） | 用了（第 2 阶段）：先在现在的代码上跑布局测试，溢出的正好是这些地方，另外多一处弹幕设置的分组标题 |
| 搜索“直播间 / 主播”、日志级别筛选改成标准高度，搜索范围行最小 48 | 没用：A05.1 把这几处列为 X7，等维护者决定（按确认过的样子，决定 A） |

## 第 1 阶段：高度分档

- `packages/live_ui/lib/src/theme/grid_columns.dart`：高度分档 `WindowHeightClass`（紧凑 <480、中等 480～899、展开 ≥900）和 `WindowClass`。“横屏手机” `isPhoneLandscape` = 高度紧凑并且宽 ≥600（和直播间原来的判断一样）；竖屏分屏 400×420、横着拿的手机再左右分屏（约 410×392）都不算。
- `packages/live_ui/lib/src/widgets/window_layout.dart`（新）：`WindowClassScope`（应用在最外层放一个，按 `LayoutBuilder` 拿到的区域算分档，分档变了才通知下面重建）、`toolbarHeightOf`（矮时 48，否则 56）；`DisplayHinge`（铰链或半开的折痕，平放的折痕和摄像头挖孔不算）。
- 9 处整屏读高度的标题栏改用 `WindowClassScope.toolbarHeightOf`：`settings_page_frame.dart`、`settings_tiles.dart`、`settings_page.dart`（两栏左边，用自己的 `LayoutBuilder` 约束）、`toolbox_page.dart`、`shield_page.dart`、`version_page.dart`、`release_history_view.dart`、`about_page.dart`、`tags_page.dart`。`grep -rn "sizeOf(context).height <" apps/pure_live/lib packages/live_ui/lib` 为 0。
- 各写 480 的改成引用常量，数值不变：`roomCompactMaxHeight`（直播间，只改这一行和一个 `show` 引用）、`statusSideBySideHeight`、`playback_tiles.dart`、`recorder_page.dart`、`remote_receiver_page.dart`。
- 判断方式变了的两处：多画面 `_arrangementOf` 和状态页横排改用 `isPhoneLandscape`。以前“矮并且宽大于高”就算横屏，宽 480～599 的矮窗口（横着拿的手机分屏）会进横屏排法；现在保持竖屏排法。状态页仍按窗口判断（A02.1 有意保留，`SliverFillRemaining` 里不能用 `LayoutBuilder`），读的是最外层的分档。
- 折叠屏：小菜单排在按钮所在的那一半；`showAdaptivePanel` 的底部面板在开头那一半（横着的折痕在下半），侧边面板在末尾那一半；`showAppDialog` 用的是 Flutter 的 `showDialog`，本来就不跨铰链（加了测试）；设置和版本历史在书本姿势下按折痕分两栏，中间留铰链宽的空。首页网格没做铰链避让（见“留下的问题”）。
- 测试：`packages/live_ui/test/window_layout_test.dart`（10 个）；`apps/pure_live/test/window_sizes_test.dart` 第 1 组（分屏仍是底栏、各页标题栏 48，竖着 56，横屏手机是侧栏；折叠屏书本姿势设置分两半，平放时一页）；`multiview_page_test.dart` 加一个（400×420、410×392 不进横屏排法）。
- 默认尺寸和字号下各页面的样子不变（全部测试照旧通过）。

## 第 2 阶段：字号上限

- `packages/live_ui/lib/src/theme/text_styles.dart`：`appTextScaleLimit = 2`；`AppTextScaler.scale(s) = min(系统.scale(s) × 应用倍数, 2s)`，`textScaleFactor` 同样封顶。系统的非线性曲线在上限以内照旧；“文字大小”设置的键名、默认值、0.5～2 的范围不变（D-018）；设置里的字号预览用的是同一个类，也一起封顶。画面控制层的 1.3 倍不动（测试确认在 2 倍之下仍然生效）。
- 前后对比：系统字体最大（约 2 倍）+ 应用 200% 以前约 4 倍，现在 2 倍（和 3.x 一样）；只有这种叠加超过 2 倍的用户会看到字变小，这是有意的。
- 布局测试 `window_sizes_test.dart` 第 2 组：8 个尺寸（360×400、400×420、400×869、821×400、673×841、841×673、1280×800、1500×1000）× 3 个系统字号（1.3、1.5、2），每次打开首页、21 个页面（热门、分区、录制中心、搜索、观看记录、多画面、设置、关于、工具箱、版本、版本历史、标签、屏蔽、账号、平台管理、备份、网络电视、录制设置、设备同步、WebDAV、日志）和设置里的每一页，断言没有溢出；另一条测系统 2 倍 × 应用 2 倍时 14 号字是 28。直播间不在里面（它有自己的布局测试 `live_play_layouts_test.dart`，本任务不改直播间）。
- 第一次跑在 8 个尺寸上全部失败，溢出的地方（都是“只改布局，默认尺寸下样子不变”）：
  - 状态页（`status_view.dart`，34 次）：自己占一块有界高度、又不在列表里时，放不下就整体滚动；说明文字的最大宽 320 改成量高度时也按 320 量（`_MaxWidth`，以前按整宽量，少算行数）。在列表里（`SliverFillRemaining`）照旧不用 `LayoutBuilder`。
  - 设备同步（`remote_receiver_page.dart:511`）：状态文字换行。
  - 配置预览（`data_tools.dart`）：统计格子随字号变高，名字一行省略。
  - 日志（`log_page.dart`）：设置、级别、记录放进同一个滚动，数量和级别筛选放不下一行时折到下一行；级别筛选仍是紧凑密度（A05.1 X7）。
  - 平台管理（`hot_areas_page.dart`）：“恢复默认”换行；分区（`areas_page.dart`）：关注分区的标题省略；小窗弹幕（`playback_tiles.dart`）：说明和预览最多占一半高度，超出就滚动。
  - 弹幕设置的分组标题（`shared/danmaku/setting_rows.dart:32`，旧工作区没有）：右边的“改动立即生效”最多占半行，放不下就换行。
- 改完 24 个组合全部通过。

## 第 3 阶段：触控区域

- A05.1 已经在手机竖屏（393 宽）上用 `androidTapTargetGuideline` 查过全应用，并把要让看得见的地方变高的 X5～X9 留给维护者。本阶段把同样的检查放到别的尺寸上：`window_sizes_test.dart` 第 3 组，400×420（分屏）、821×400（横着拿）、673×841（折叠屏内屏）、1280×800（平板）各一条，打开首页、21 个页面和设置的每一页，只查 48×48 这一条，A05.1 的已知问题照旧跳过。
- 为了共用，A05.1 的已知问题表从 `accessibility_test.dart` 挪到 `accessibility.dart`（`knownAccessibilityFailures`），加上 X9（多画面工具栏的布局按钮 44 高，A05.1 的 README 里有，但自动检查没开多画面页，所以表里原来没有）；`expectAccessible` 可以只查指定的几条指南。
- 查出 1 处，只在横屏手机和平板（多画面有侧栏时）出现：多画面侧栏边上收起 / 展开的把手（`multiview_page.dart` `_FoldHandle`）22×56。改：看得见的把手和按下的水波纹仍是 22 宽，外面透明的点击区 48 宽（往画面那边多 26）；读屏只有一个按钮节点。`multiview_page_test.dart` 加了“点透明部分也能展开”。
- 任务书列的 `VisualDensity.compact` 9 处逐个看了：搜索“直播间 / 主播”、日志级别筛选、切换直播间的分组芯片是 A05.1 X7，等维护者决定，没改；搜索页（`search_view.dart` 两处）、`supported_platforms.dart`、字体管理（`font_manager_page.dart`）在这四个尺寸上都没被查出来；直播间详情把手归 A03.3。

## 测试

- 新增：`packages/live_ui/test/window_layout_test.dart` 10 个、`text_scale_test.dart` 3 个；`apps/pure_live/test/window_sizes_test.dart` 15 个（高度分档 2、尺寸 × 字号 8 + 1、触控区域 4）；`multiview_page_test.dart` 加 1 个、改 1 个。
- 全部测试：`live_ui` 209 个、`apps/pure_live` 全部通过；`dart analyze --fatal-infos`、格式检查、`check_ui_structure.py`、`docs.py --check`、`owners.py --check` 通过。没跑 `gate.sh --all`，没打包。
- 应用的全部测试从约 2.5 分钟变成约 12 分钟（1046 个），多出来的主要是尺寸 × 字号的 8 个用例（每个约 20 秒）和触控区域的 4 个。

## 真机要看的（K90）

照 [brief.md](brief.md)“真机验证”的 5 步。重点：

1. 上下分屏打开应用：首页仍是底栏；设置、工具箱、关于的标题栏是矮的（48）；多画面不进横屏排法，选台面板放不下时能整体滚动；直播间不变成横屏全屏的样子。
2. 横着拿：设置、工具箱、版本、关于的标题栏 48，和以前一样；多画面侧栏把手边上一点也能点中。
3. 系统字体调最大 + 应用“文字大小”200%：字最多是默认的 2 倍（以前约 4 倍）；首页、设置、录制中心、日志、设备同步、配置预览不溢出；画面上的控制层最多 1.3 倍。测完把两处设回去。
4. 默认字号、竖着拿：各页面和以前一样（日志页现在设置区和记录一起滚动，样子不变）。
5. 折叠屏铰链：K90 没有，只有测试；有折叠屏时再看。

## 留下的问题

- 首页网格没做铰链避让（任务书“至少首页网格”）：书本姿势时中间的卡片可能压在折痕上。要做得在 `RoomGrid` 里按铰链把网格分成两块，影响面大，K90 用不上，留到有折叠屏真机时再做。
- 尺寸 × 字号的布局测试没包含直播间（直播间组另有任务在做，本任务只改了 `room_layout.dart` 的一个常量引用）。
- X5～X9（A05.1）仍等维护者决定；决定改的话，`knownAccessibilityFailures` 里删掉对应一行，两处测试就会一起查。

## 可能冲突的文件

- A01.2 / A01.3（页面外的颜色、文字、图标）：本任务改了 `settings_tiles.dart`、`settings_page.dart`、`settings_page_frame.dart`、`about_page.dart`、`toolbox_page.dart`、`shield_page.dart`、`tags_page.dart`、`version_page.dart`、`release_history_view.dart`（只换标题栏高度和两栏宽度）、`log_page.dart`（结构改成一个滚动）、`areas_page.dart`、`hot_areas_page.dart`、`remote_receiver_page.dart`、`data_tools.dart`、`playback_tiles.dart`、`shared/danmaku/setting_rows.dart`、`live_ui` 的 `status_view.dart`；都是布局，合并时颜色和文字以对方为准。
- A03.3（直播间拖动）：只动了 `features/live_play/logic/room_layout.dart` 的 `roomCompactMaxHeight` 一行（数值不变）。
