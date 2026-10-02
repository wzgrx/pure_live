# A02.3 记录：贴着按钮的小菜单（按实测高度定位、从按钮方向展开）

- 日期：2026-10-02
- 任务单：[tasks/B03.md](brief.md)；用户问题 03：“手机横屏的时候，点击画质和线路弹出的UI动画不行，是从上面然后显示的，不整齐，应该是从下到上”。
- 范围：只改 `packages/live_ui` 的小菜单；调用处不用改（`features/live_play/buttons/`、`player/bar_parts.dart` 都没动），只在 `live_play_popups_test.dart` 补了横屏位置的断言。没有新设置、没有新翻译键、没有改 Android 原生代码。
- 做法：本地 worktree 任务，没有出效果图（任务单写“不用”）；用 widget 测试把展开过程渲染成图片自己看过（见“自己看的结果”）。

## 逐条对照

| 编号 | 条目 | 做了没有 | 内容和偏差 |
|---|---|---|---|
| c1 | 自己的 `PopupRoute`，按实测高度定位 | 完成 | 新文件 `live_ui/src/widgets/anchored_menu.dart`：`showAnchoredMenu` 推一个 `PopupRoute`（不变暗、点外面关），里面是 `CustomSingleChildLayout`。菜单先排版，`getPositionForChild` 拿到**实测高度**再定方向：偏好向上且上方放得下 → 向上（`y = 按钮顶 − 4 − 菜单高度`）；放得下下方 → 向下（`y = 按钮底 + 4`）；都放不下 → 去空间大的一侧。`getConstraintsForChild` 把最大高度限制为两侧中较大的一侧（放不下时选的就是这一侧，所以等于“所选一侧的空间”），长列表在菜单里滚动，不压按钮和底栏。水平方向贴按钮、和靠屏幕边的那条边对齐，离屏幕边和安全区至少 8。`showSmallMenu`、`showAppMenu` 都改用它，`showMenu` 和估算高度的 `_menuPosition`、`_position` 删掉 |
| c2 | 淡入 + 从按钮一侧展开，约 150ms；减少动态效果时不做 | 完成 | 打开 150ms：淡入（`easeOut`）+ 从按钮那条边展开（`easeOutCubic`，向上时从下往上，向下时从上往下）；关闭 100ms 只淡出（specs/UI.md 8.6“退出比进入快”）。展开用绘制时的裁剪（`ClipRect` + 自定义裁剪），不改排版尺寸，所以方向判断不受动画影响；裁剪四周留 16 给阴影。系统“减少动态效果”时（`MediaQuery.disableAnimations`）不包动画，第一帧就是完整菜单 |
| c3 | 保留 Esc、返回键、方向键和回车、当前项主色加勾、说明行、标题行、危险项 | 完成 | 行还是 `PopupMenuItem`（样子、行高、按下效果、语义、`Navigator.pop` 返回值都不变），分组线还是 `PopupMenuDivider`；路由用 `TraversalEdgeBehavior.closedLoop`（同 Material 菜单，焦点在菜单里循环），Esc 由 `ModalRoute` 的关闭动作处理。标题行改成普通组件（不再需要给估算用的高度）。当前项在长列表里打开时自动滚进可见区 |
| c4 | 所有调用处自动受益，逐个检查位置 | 完成 | 见下面“各调用处的位置”。只有一处行为变化需要说明：`StreamMenuButton`（清晰度、线路）的菜单改为贴着按钮**可见的外框**（32 高），不再贴 48 高的点击区，所以菜单离外框正好 4（以前是 12） |

验收：横屏 852×393 点清晰度、线路：从下往上展开、紧贴按钮、不越出屏幕、7 档时在菜单里滚动；竖屏信息行照旧向下；平板 1280×800 下方放得下时向下、放不下时向上——都有测试（见“测试”）。

## 根因（核对过）

1. **展开方向**：Flutter 3.47.5 `material/popup_menu.dart` 的 `_PopupMenuRouteLayout.getPositionForChild` 只用 `y = position.top`，`_PopupMenu` 的动画是 `Align(alignment: topEnd, heightFactor: 动画值)`，永远从顶边往下长。旧代码向上时把顶边算成“按钮顶 − 4 − 估计高度”，于是菜单先在按钮上方远处出现一条线，再往下长到按钮。实测（3 档，横屏，按钮外框顶 349）：动画 60ms 时菜单底边在 221，160ms 时 301，最后停在 333——底边一路往下走到按钮，就是“从上面往下”。
2. **高度靠估算**：旧 `_menuPosition` 用“条数 × 48 + 16”（标题行按 36）。7 档在 393 高的横屏上估计 352，大于按钮上方的空间，仍选向上，顶边算成负数，被 `showMenu` 的 `_fitInsideScreen` 推回到 y=8，菜单底边到 360，**压住按钮外框（顶 349）11 个点**；标题行实际 33 高，估成 36，带标题的菜单底边离按钮差 3。
3. **贴的是点击区**：`StreamMenuButton` 把自己的 context（48 高的点击区）交给菜单，外框只有 32 高、居中，所以菜单和看得见的按钮之间隔 12，不是 4。
4. `showMenu` 的动画固定 300ms，不看“减少动态效果”。

改之前跑新测试：12 条里 8 条失败（数字见上），改之后全过。

## 各调用处的位置（c4）

| 调用处 | 方向 | 检查 |
|---|---|---|
| 直播间竖屏信息行 清晰度、线路（`StreamPickers`） | 向下，离外框 4 | `live_play_popups_test` “portrait: … under the button”；`small_menu_test` 竖屏 |
| 横屏全屏下栏 清晰度、线路（`preferAbove`） | 向上，离外框 4，放不下时滚动 | `live_play_popups_test` “fullscreen …”（新加：菜单底 = 外框顶 − 4、不出屏幕）；`small_menu_test` 横屏 7 档、3 档 |
| 平板（1280×800） | 照空间 | `live_play_popups_test` 方向键测试；`small_menu_test` 平板两条 |
| 全屏下栏 画面比例（`VideoFitButton`） | 向上，离 48 的按钮区 4 | 渲染图看过（见下） |
| 竖屏全屏 画面模式（`PortraitModeButton`，标题行 + 说明行 + 固定宽度） | 向上，按实测高度 | `small_menu_test` “a titled menu …”；`live_play_layouts_test` “picture mode” |
| 多画面 焦点栏（`preferAbove`）、格子控制条 | 照空间 | `multiview_page_test` |
| 首页左上菜单、右上“更多”（`AppMenuButton`） | 向下；左边的按钮左对齐，右边的右对齐 | `app_menu_test` |
| 搜索排序、备份文件行、WebDAV 文件行和“更多” | 向下，列表底部放不下时向上 | `search`、`backup`、`web_dav`、`recorder_centre` 测试 |

图标按钮（画面比例、首页菜单、搜索排序的 `ActionChip` 等）贴的仍是 48 的点击区：图标没有外框，和 Material 菜单的习惯一致；搜索排序不在本任务可改的目录里，没动。

## 自己看的结果（渲染图）

用临时 widget 测试（载入 Noto Sans CJK、Material Icons、Remix 字体，打开阴影）把展开过程按 0、25、50、75、100、150ms 和打开后渲染成 PNG，拼成对照图，放在本地 scratchpad（`.../scratchpad/B03/`：`sheet-land-quality.jpg`、`sheet-land-line.jpg`、`sheet-port-quality.jpg`、`sheet-land-fit-scrolled.jpg`、`tablet-open.jpg`，原始帧在 `frames/`，脚本 `zz_frames_test.dart`、`sheets.sh`），不进仓库。结论：

- 横屏 852×393 清晰度（7 档）、线路（3 档）：菜单底边一直停在按钮外框上方 4，向上长出来，25ms 时已看到最靠近按钮的两三行，100ms 基本完整；右边和按钮外框右边对齐，和 A07.6 已确认的样子一致；7 档时顶边离屏幕 8，最后一行可滚出来，菜单不压下栏。
- 竖屏信息行：从外框下方 4 往下长；平板全屏：7 档整块放在按钮上方，不滚动。
- 画面比例：菜单底边离图标按钮区 4，和右边对齐。它和清晰度按钮的外框不在同一高度（图标没有外框），各自贴自己的按钮。
- 展开时前沿是一条直边（裁剪），角和阴影在最后几帧出现；150ms 内看不出来。

## 测试

- `packages/live_ui`：新 `test/small_menu_test.dart` 12 条（横屏 7 档向上和滚动、3 档向上和右对齐、展开方向和淡入、减少动态效果、长列表当前项可见、标题行和说明行按实测高度、转屏关闭、`showAppMenu` 横屏向上并滚动、竖屏向下和左对齐、方向键和回车、返回键和 Esc、平板上下两种）；原有 `app_menu_test.dart` 不用改。全部 111 条通过；`dart format`、`flutter analyze` 无问题。
- `apps/pure_live`：`live_play_popups_test.dart` 横屏一条加了“菜单底 = 外框顶 − 4、不出屏幕”；`flutter analyze` 无问题；全部 `flutter test` 741 条通过。
- 根目录 `python3 tools/gate/check_ui_structure.py` 通过。

## 改了哪些文件

- 新增 `packages/live_ui/lib/src/widgets/anchored_menu.dart`（不从 `live_ui.dart` 导出，只给两个菜单函数用）。
- `packages/live_ui/lib/src/widgets/stream_menu_button.dart`：`showSmallMenu` 改用新路由；按钮的菜单贴外框；标题行改为普通组件。
- `packages/live_ui/lib/src/widgets/app_menu.dart`：`showAppMenu` 改用新路由；`appMenuGap` 仍是 4。
- 新增 `packages/live_ui/test/small_menu_test.dart`；`apps/pure_live/test/features/live_play/live_play_popups_test.dart` 加断言。

## 和以前不同的地方（偏差）

- 菜单贴清晰度、线路按钮的外框（32 高），不贴点击区（48 高），见根因 3。任务单写“按钮顶 − 4”，这里按“看得见的按钮”理解。
- 屏幕尺寸变化（转屏、分屏改大小）时菜单直接关掉：按钮已经挪了位置，留着会悬在旧位置。键盘弹出收起不算（只看尺寸，不看 insets）。
- 没有照搬 Flutter 菜单对折叠屏铰链的避让（`DisplayFeatureSubScreen`），这一轮只做手机和平板。
- 宽度规则照旧：最小 128、最大 280（或调用处给的固定宽度），按 56 一档取整（Material 菜单的做法），所以菜单宽度和以前一样。

## 新设置和翻译键

没有。

## 要在 K90 上看的地方（Redmi K90 Pro Max，Android 17，120Hz）

1. 进一个哔哩哔哩直播间，横屏全屏，点下栏“原画 ⌄”：菜单紧贴按钮上方，从下往上展开（约 0.15 秒），不压住按钮；档位多时菜单顶离屏幕边留一点，菜单里能上下滑；选一档后菜单关闭、按钮转圈。
2. 同一处点“线路1 ⌄”：同样从下往上、紧贴按钮、右边和按钮对齐。
3. 横屏点“画面比例”图标：菜单在图标上方，从下往上展开。
4. 竖屏信息行点“原画 ⌄”“线路1 ⌄”：照旧在按钮下方，从上往下展开，离按钮外框很近。
5. 竖屏全屏点画面模式图标：带标题和说明的菜单在按钮上方，不盖住按钮。
6. 打开菜单时转屏：菜单关掉，不会悬在旧位置；再点能正常打开。
7. 系统设置 → 无障碍 → 移除动画打开后再点：菜单直接出现，没有动画。

## 需要维护者决定的

- 无必须决定的事。可以看一眼：图标按钮（画面比例等）的菜单贴 48 的点击区，看起来离图标比清晰度菜单离外框远一点；要统一成贴图标的 40 圆形区域时，改 `bar_parts.dart` 两处的 anchor 即可。

## 可能和别的任务冲突的文件

- `packages/live_ui/lib/src/widgets/app_menu.dart`、`stream_menu_button.dart`、新文件 `anchored_menu.dart`：A02.2（弹窗组件，依赖 A02.3）、A02.1、A07.12（直播间子弹窗，依赖 A02.3）会改到小菜单，应在本任务合并后再开。
- `apps/pure_live/test/features/live_play/live_play_popups_test.dart`：只加了几行断言，A07.12 等改直播间弹窗的任务可能同时改这个测试文件。
