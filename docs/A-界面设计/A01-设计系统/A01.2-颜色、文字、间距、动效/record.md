# A01.2 颜色、文字、间距、动效：记录（第 3 阶段“其余页面”）

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区（从 master `ce7640a5b` 开始），代码提交 `52a429e8e`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)
- 同时在做的：A03.3（直播间拖动手感，`features/live_play/`）、A04.1（尺寸和字号适配）。本任务没有改 `features/live_play/`，没有碰文字缩放（`AppTextScaler`）和高度判断；任务书说 A01.2 和 A04.1 不要并行，这次是协调者安排的，冲突点见最后。

## 逐条对照（任务书“目标和验收”）

| 条 | 做了没有 | 说明 |
|---|---|---|
| 1 圆角和时长常量 | 做了 | 新文件 `packages/live_ui/lib/src/theme/metrics.dart`，从 `live_ui.dart` 导出：`AppRadii.card` 16、`button` 12、`textButton` 8、`listRow` 12、`input` 12、`dialog` 24、`menu` 8（也用于提示条、标签的按下块）、`chip` 8、`panelTop` 顶角 16、`panelSide` 侧边面板 16；`AppDurations.instant` 100、`fast` 150、`normal` 200、`slow` 300。`live_theme.dart` 的组件主题（卡片、按钮、文字按钮、列表行、输入框、底部面板、对话框、提示条、标签）和 `live_ui` 组件里对得上角色的圆角（小菜单、计数、焦点框、状态页卡片、二维码卡片、输入框、面板、设置组、设置行焦点框、清晰度按钮、芯片）、动画时长（小菜单开 / 关、取色、电视行放大、回到顶部、下拉刷新）改用它们，数值不变。徽标、色块这类和自身尺寸配套的小圆角留着数字 |
| 2 不写死字号 | 做了 | 直播间、电视以外：应用里 46 处（含多画面 `_markStyle` 的 10 个调用和按条件写死的 2 处）、`live_ui` 组件 26 处（含设置行、计数的电视分支 7 处）。等于某个角色默认值的直接用那个角色的大小（保留原来的样式底子，只换 `fontSize`，所以默认设置下像素不变）；其他按最近的角色成比例：面板标题 17 = 卡片标题 × 17/15、标题栏标题 17 = 标题 × 17/20、版本历史的版本号 17 = 卡片标题 × 17/15、数据统计的数字 22 = 标题 × 22/20、设备同步配对码 28 = 标题 × 28/20、两栏设置里嵌入的标题 18 = 标题 × 18/20；电视的大一级（17、16、15、14）同样按比例。新函数 `settingsValueFontSize`（设置行的值、计数的数字共用） |
| 3 字重只有 400、600 | 做了 | 页面和组件 30 处：500 → 400（次要信息：房间卡片主播名、分区卡片说明、多画面音量、历史记录“自定义”、标签页的数量、卡片弹窗正文、标签名未选中）或 600（按钮、标题、强调：卡片弹窗按钮、“新建标签”、搜索历史标题、多画面布局按钮）；700 / bold → 600（含 Markdown 粗体、日志级别、下载百分比、多画面格子编号）。主题那一层按 D-003 取 README 的建议：`titleMedium`、`titleSmall`、`labelLarge` 和文字按钮 500 → 600，`LiveTheme.medium`、`LiveTheme.bold` 和 `AppTextStyles` 的 18 个 `*Medium`/`*Bold` 删掉（受影响的页面见 README“待选和决定”） |
| 4 弹幕预设色进 `live_ui` | 做了 | `LivePalettes.danmaku`（十个颜色，原样）和 `LivePalettes.danmakuStroke`（飞行弹幕描边的黑）；`danmakuColorSwatches` 留作别名，`shared/` 里不再有 `Color(0x…)` |
| 5 锁住 2、3 | 做了（门禁） | `tools/gate/check_ui_structure.py` 第 5 条：`features/`（除 `live_play/`）、`shared/`、`app/` 和 `packages/live_ui/lib/src/widgets/` 不许 `fontSize: <数字>`、`fontSize: x ? <数字> : <数字>`、`FontWeight.w500/w700/w800/w900/bold`。不查的：直播间、电视、画面上的三个组件（`video_state_view`、`record_glyph`、`pip_danmaku_preview`）、弹幕模板的数据（`danmaku_templates.dart`）、桌面标题栏（32 高的窗口边框，本来就不跟系统字号）。选门禁不选 Dart 测试：门禁已经按文件扫源码，基线和失败信息现成 |
| 6 门禁、测试 | 做了 | 见下 |

## 顺手修的

- 多画面选房列表的行高固定 56（`room_picker.dart` 的 `itemExtent`）：字号调大（或系统字体放大 1.3 倍）时两行字放不下，溢出 3 像素。改成默认 56、字大时按两行的实际高度加高。默认设置下不变。

## 改了哪些文件

- `packages/live_ui/lib/`：`live_ui.dart`、`theme/metrics.dart`（新）、`theme/live_theme.dart`、`theme/text_styles.dart`、`theme/live_colors.dart`；`widgets/` 的 `adaptive_panel`、`anchored_menu`、`app_chip`、`app_dialog`、`card_dialog`、`color_picker`、`count_button`、`focus_ring`、`jump_buttons`、`json_tree`、`live_room_card`、`page_title`、`pip_danmaku_preview`（只换圆角）、`qr_code_widget`、`refresh_view`、`settings_page_frame`、`settings_row`、`status_view`、`stream_menu_button`、`tab_label`。
- `apps/pure_live/lib/`：`features/` 的 `about`、`areas`、`backup/log_page`、`history`、`iptv/iptv_cards`、`multiview`（页面、格子、控制、选房、工具栏）、`remote_receiver`、`search`、`settings`（外观、人数口径、数据工具、播放、对话框、编辑器、设置行外壳）、`tags/tag_tile`、`version`（版本页、版本历史、下载、Markdown）；`shared/danmaku/`（预设色、描边、设置行）、`shared/rooms/`（翻页栏、标签对话框）。
- 测试：`packages/live_ui/test/metrics_test.dart`（新，6 条）、`theme_test.dart`；`apps/pure_live/test/features/version/version_page_test.dart`、`features/multiview/multiview_page_test.dart` 各加一条。
- 门禁：`tools/gate/check_ui_structure.py`、`tools/gate/tests/test_check_ui_structure.py`（第 5 条的测试）。

## 测试

- `packages/live_ui`：`flutter test` 全过（新 6 条：主题圆角取自常量且数值不变、时长、字重、默认字号下设置类页面标题 20 / 标题栏标题 17 / 面板标题 17 / 行标题 15 / 说明 12 / 值 14、五个字号调到最大时 26 / 22.1 / 22.7 / 20 / 15 / 18、电视行 17 / 14 / 16 且跟着变）。
- `apps/pure_live`：`flutter test` 全过，含 A05.1 的 `accessibility_test.dart`（对比度、触控、读屏在浅色、深色都还合格）。新两条：版本历史（标题 20、版本号 17 → 最大时 26、22.7）、关于（应用名 20 → 26）；多画面选房（标题 15、主播名 14、格子提示 13 → 20、18、17），竖屏、横屏、宽屏在最大字号下不溢出。
- `python3 tools/gate/check_ui_structure.py` 通过；`python3 -m unittest discover -s tools/gate/tests` 通过。

## 留下的

- 直播间（`features/live_play/`）写死字号 54 处，画面上的三个组件（`video_state_view.dart`、`record_glyph.dart`、`pip_danmaku_preview.dart`）：要不要跟五个字号走由直播间任务定（规范只说画面上的字随系统放大最多 1.3 倍）。
- 电视（`tv/`）归 A17；桌面标题栏是窗口边框，不跟字号。
- 应用页面里的圆角 139 处、时长 36 处（直播间另有 56、23 处）没有换成常量：大多是徽标、色块、进度这类配套尺寸，或者计时器；以后改到哪个页面顺手换。
- 间距没有做常量。

## 真机（K90）

1. 默认字号下打开设置 → 视频、关于、版本历史、多画面、设备同步配对码：大小和改之前一样。
2. 设置 → 外观 → 精细化字号：五个都调到最大，回到第 1 步的页面：设置行的标题、说明、值，页面标题，版本号，多画面选房的名字都变大，不截断；多画面选房列表的行跟着变高。
3. 浅色、深色、纯黑各看一遍设置页和多画面：颜色和改之前一样。
4. 字重（看得见的改动）：用“卡片标题”字号又没另设字重的字（各页的小标题、对话框里的选项标题等）和按钮字从 500 变成 600（略粗）；房间卡片的主播名、下拉刷新头的字从 500 变成 400（略细）。看着别扭的告诉我，主题那三行可以改回。
5. （Windows，以后）设置页、版本历史没有“发虚的半粗体”。

## 可能和并行任务冲突的文件

- A04.1：`packages/live_ui/lib/src/widgets/settings_page_frame.dart`（第 22 行标题字号，A04.1 改第 21 行的高度判断，相邻）、`settings_tiles.dart`（应用里的 `settingsPageAppBar` 外壳，同样相邻）、`about_page.dart`、`release_history_view.dart`、`text_styles.dart`（本任务删了 `*Medium`/`*Bold`，A04.1 改文件末尾的 `AppTextScaler`）、`live_ui.dart` 的导出列表、`multiview_page.dart`、`playback_tiles.dart`。合并时以两边的改动都保留为准。
- 别的分支如果用了 `t13Medium`、`t12Bold` 这类名字或 `LiveTheme.medium`，合并后编译不过，改成 `t13`、`t12.emphasis`。
- A03.3：没有共同文件（`motion.dart` 没动）。
