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
| `AppTextScaler` 上限 | 第 2 阶段用 |
| 尺寸 × 字号的布局测试、几个页面的溢出修复（分区、日志、平台管理、设备同步、配置预览、小窗弹幕、状态页滚动） | 第 2 阶段按现在的代码重跑后再定 |
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
