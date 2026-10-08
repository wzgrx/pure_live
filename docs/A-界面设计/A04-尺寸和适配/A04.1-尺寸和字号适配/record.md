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
