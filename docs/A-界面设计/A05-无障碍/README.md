# A05 无障碍

让看不清、点不准、不用触摸的人也能用：读屏（TalkBack、讲述人、VoiceOver）念得出每个能点的东西和它的状态，键盘能走到每个控件、焦点看得见、Esc 能返回，文字和图标的对比度够，点击区域够大，跟随系统的“移除动画”。代码分散在全部界面里，这个子分类管规则、共用的部件和全应用的检查。

## 范围

- 包括：
  - 共用的无障碍部件：`packages/live_ui/lib/src/widgets/focus_ring.dart`（焦点框）、`escape_back.dart`（Esc 返回）、`dialog_keys.dart`（对话框的回车和 Esc）；主题里的焦点框和对比度角色（`live_theme.dart` 的 `FocusFrame`、`app_chip.dart` 的 `AppChipSide`、`live_colors.dart` 的 `InkOnColor`、`OnVideoColors`）；组件里的读屏文字（`Semantics`、`semanticLabel`、`tooltip`）。
  - 应用里的键盘快捷键和读屏调节（直播间、设置、房间列表、多画面、三档面板把手）。
  - 全应用的检查：读屏文字、键盘焦点、对比度、48dp 触控区域、跟随“减少动态效果”（A05.1）。
- 不包括（归哪里）：
  - 尺寸和字号适配（高度分档、字号上限、主要页面的触控区域自动检查）→ [A04](../A04-尺寸和适配/README.md)（A04.1）；颜色和字重角色本身 → [A01](../A01-设计系统/README.md)；组件的样子 → [A02](../A02-组件/README.md)。
  - 电视的遥控器焦点（焦点放大、近白描边、方向键可达）→ A17.1（`apps/pure_live/lib/tv/widgets/tv_focusable.dart:59`）。
  - 看得见的改动（颜色深浅、按钮变大）→ 提出它的界面任务出图确认，本子分类只提出。

## 现状：做到哪、怎么工作的

- 用户看得到的（或听得到的）：
  - 键盘焦点：用键盘（或遥控器）移动焦点时才画焦点框，触摸时不画（`packages/live_ui/lib/src/widgets/focus_ring.dart:5` 的 `focusFramesShown` 看 `FocusHighlightMode.traditional`）。按钮、芯片、标签由主题和组件画 2 像素主色框（`live_theme.dart:31`、`app_chip.dart:73`、`tab_label.dart:62-66`）；头像、回到顶部用 `FocusRing`；设置行、房间卡片自己画（`settings_row.dart:475-480`、`live_room_card.dart:137`、`:757`）。
  - 键盘操作：直播间空格和媒体键暂停、R 刷新、↑↓ 音量 ±5%、F 全屏、Esc 依次退出（`apps/pure_live/lib/features/live_play/live_play_page.dart:736-753`，照 3.x）；设置 Ctrl/Cmd+F 搜索、Esc 清搜索（`features/settings/settings_page.dart:235-239`）；电脑上房间列表 ← → 翻页（`shared/rooms/room_grid.dart:583`、`features/favorite/favorite_page.dart:510`、`features/areas/platform_areas_view.dart:244`）；对话框回车 = 主要按钮、Esc = 取消、危险确认焦点在“取消”（`packages/live_ui/lib/src/widgets/dialog_keys.dart:12`）；小菜单方向键、回车、Esc，焦点在菜单里循环（`anchored_menu.dart:89`）；计数 ← → 调（`count_button.dart:204`）。Esc 返回（`EscapeBack`）只用在搜索、网页搜索、观看记录，加上直播间、多画面（`features/multiview/multiview_page.dart:380`）；其他二级页面没有。
  - 读屏：`IconButton` 102 个，粗查（看构造参数里有没有 `tooltip:`）都写了按钮名称（悬停和长按显示，读屏念）；三档面板把手能“增大 / 减小”（`features/live_play/layout/portrait_panel.dart:255-267`，照 3.x）；设置的数值行能增减（`features/settings/settings_tiles.dart:497-498`、`appearance_pages.dart:222-223`、`features/record_settings/record_settings_page.dart:567-568`）；开着读屏时带操作的提示条不自动消失（`packages/live_ui/lib/src/widgets/app_toast.dart:63`、`:137`）；状态页、横幅、面板标题、对话框、设置行、画面中间按钮、录制图形、表情、卡片封面上的标签都有读屏信息（`status_view.dart:162`、`status_banner.dart:103`、`adaptive_panel.dart:125`、`app_dialog.dart:186`、`:357`、`settings_row.dart:216`、`:492`、`video_centre_button.dart:51`、`record_glyph.dart:370`、`emote_text.dart:100`、`live_room_card.dart:559`、`danmaku_icon.dart:56`）。自绘的可点组件（`InkWell` 66、`GestureDetector` 20，62 个文件，不含电视）没逐个查过。
  - 对比度：品牌蓝白字 4.7:1（A11.2）；设置行说明、组标题、横幅、状态页、计数、开关在深浅主题下 ≥4.5:1（A02.1，有测试）；画面上的白字在最亮画面上 5.7:1；平台给的颜色上按对比度选深字或白字（`InkOnColor`）。画面上的次要白（70%）在最亮画面上约 3.8:1，还没处理。
  - 触控：A02.1 的组件都到 48；其余见 A04。
  - 减少动态效果：小菜单、录制图形、小窗弹幕预览、侧面板、直播间的面板和换台都跟随；下拉刷新头、回到顶部按钮不跟随。
- 内部怎么工作：焦点框靠 Flutter 的 `FocusManager.highlightMode`（最后一次输入是键盘还是触摸）决定画不画；主题里的 `FocusFrame` 是一个 `WidgetStateProperty<BorderSide?>`，按钮在 `WidgetState.focused` 且用键盘时画框，相等的框比较相等，主题重建不触发动画。读屏文字和用户看到的文字一样走翻译（`apps/pure_live/assets/translations/zh.json`、`en.json`）。
- 完成度：没有专门的无障碍任务做完过；焦点框、对比度、触控是 A02.1 顺带做的，读屏和 Esc 返回零散。全应用的检查是 [A05.1](A05.1-无障碍检查/README.md)（未开始，第三档）。和 3.x 比：3.x 没有焦点框（主题 `NoSplash`，焦点只是底色）、对比度几处不够（默认蓝 3.1:1、设置组标题约 2.9:1、说明约 3.3:1），4.x 已修；3.x 的读屏调节（三档面板、音量）保留了（音量改成自带读屏的 `Slider`，`features/live_play/player/bar_parts.dart:206`）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_ui/lib/src/widgets/focus_ring.dart` | `focusFramesShown`（`:5`）、`FocusRing`（`:12`，自绘可点组件的 2 像素主色框）、`FocusRingPainter`（`:82`） |
| `packages/live_ui/lib/src/widgets/escape_back.dart` | `EscapeBack`（`:10`）：`CallbackShortcuts` 把 Esc 交给 `onEscape`（默认 `maybePop`），`FocusScope` 在页面打开时取焦点（`:24-26`）；要放在 `Scaffold` 外面 |
| `packages/live_ui/lib/src/widgets/dialog_keys.dart` | `DialogKeys`（`:12`）：回车 = 主要按钮、Esc = `onEscape`，打开时取焦点（`:46`） |
| `packages/live_ui/lib/src/theme/live_theme.dart` | `FocusFrame`（`:31`，按钮的焦点框）；按钮主题里用它（`:289-319`）；`_TabOverlay`（`:64`） |
| `packages/live_ui/lib/src/widgets/app_chip.dart`、`tab_label.dart`、`settings_row.dart`、`live_room_card.dart`、`jump_buttons.dart`、`avatar.dart` | 各自的焦点框：`app_chip.dart:73`、`tab_label.dart:62-66`、`settings_row.dart:470-480`、`live_room_card.dart:131-137`、`jump_buttons.dart:101-103`（隐藏时 `ExcludeFocus`）、`avatar.dart:112` |
| `packages/live_ui/lib/src/widgets/count_button.dart` | ← → 调值（`:204`）；读屏的增减（`Semantics`） |
| `packages/live_ui/lib/src/widgets/app_toast.dart` | 开着读屏时带操作的提示条不自动消失（`:63`、`:137`） |
| `packages/live_ui/lib/src/widgets/anchored_menu.dart` | 小菜单焦点循环（`:89`）、读屏的关闭标签（`:63`）、减少动态效果（`:62`） |
| `packages/live_ui/lib/src/theme/live_colors.dart` | `OnVideoColors`（`:9`，`secondary` 70% 白 `:17`、`scrim` 60% 黑 `:24`）；`InkOnColor`（`:258`，`contrastOn` 按对比度选字色） |
| `apps/pure_live/lib/features/live_play/live_play_page.dart` | `:736-753` 直播间快捷键（照 3.x `video_keyboard.dart`） |
| `apps/pure_live/lib/features/settings/settings_page.dart` | `:235-239` Ctrl/Cmd+F、Esc |
| `apps/pure_live/lib/shared/rooms/room_grid.dart:583`、`features/favorite/favorite_page.dart:510`、`features/areas/platform_areas_view.dart:244` | 电脑 ← → 翻页 |
| `apps/pure_live/lib/features/search/search_view.dart:371`、`search/web_search_view.dart:163`、`history/history_page.dart:229` | 用 `EscapeBack` 的三页 |
| `apps/pure_live/lib/features/multiview/multiview_page.dart:380` | 多画面的 Esc |
| `apps/pure_live/lib/features/account/cookie_editor.dart:398` | Cookie 编辑器的快捷键 |
| `apps/pure_live/lib/features/live_play/layout/portrait_panel.dart:255-267` | 三档面板把手的读屏“增大 / 减小” |
| `apps/pure_live/lib/features/settings/settings_tiles.dart:497-498`、`appearance_pages.dart:222-223`、`features/record_settings/record_settings_page.dart:567-568` | 数值设置的读屏增减 |
| `apps/pure_live/lib/tv/widgets/tv_focusable.dart:59` | 电视的焦点（A17.1，这里只列出） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_ui/test/components_test.dart` | 焦点框只在键盘时、主题重建后相等；`EscapeBack` 返回和页面自己的一步；对比度（`_contrast` `:20`；`:166-168` 状态页、`:222-224` 横幅、`:501-504` 设置行说明和主色）；计数 ← → |
| `packages/live_ui/test/dialog_support_test.dart` | `DialogKeys` 回车和 Esc |
| `packages/live_ui/test/popups_test.dart` | 对话框回车 / Esc、危险确认焦点在“取消” |
| `packages/live_ui/test/widgets_test.dart` | `InkOnColor.contrastOn`；二维码和暖色容器的对比度 |
| `packages/live_ui/test/design_system_test.dart` | 关闭按钮红和录制提示 4.5:1；录制图形减少动态效果时静止 |
| `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` | 读屏查找（2 处） |

没有 `meetsGuideline`（`androidTapTargetGuideline`、`labeledTapTargetGuideline`、`textContrastGuideline`）的测试。

## 3.x 基线

- 读屏：`Semantics(` 44 处（含 GetX 自带代码）、`semanticLabel` 25、`semanticsLabel` 9、`tooltip:` 122（`IconButton(` 98）；能调的：三档面板 `lib/modules/live_play/widgets/layout/live_play_content.dart:314-317`、音量 `lib/modules/live_play/widgets/video_player/volume_control.dart:289-295`（念“房间音量 x%”）、网络电视输入框高度 `lib/modules/iptv/iptv_page.dart:622-623`。
- 键盘：`lib/modules/live_play/widgets/keyboard/video_keyboard.dart:53-80`（Esc 链、空格、媒体键、R、↑↓；`:36-40` 的注释说桌面上 Flutter 不会把没人处理的 Esc 变成返回）；`lib/common/base/base_page_view_extension.dart:8-20`（← → 翻页）。没有焦点框（`lib/common/style/theme.dart:114` 的 `NoSplash`）。
- 对比度：默认 `Colors.blue` 白字 3.1:1；设置组标题主色 65%、说明提示色 75%（`lib/common/widgets/widget_extensions.dart:28-31`、`:136`、`:203`）；计数按钮深色白图标约 1.7:1（`count_button.dart:69-71`）。
- 触控：回到顶部 40（`base_page_view_extension.dart:64-99`）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 7 条（返回链，Esc 和 iOS 滑动返回走同一条）、第 16 条（键盘快捷键）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 二级页面在电脑上 Esc 不返回 | 只有 6 处处理 Esc（见代码地图）；`apps/pure_live/lib/app/`、`routes/` 没有全局处理 | 规范 5.4 的 Esc 返回链不全 | A05.1 c3 |
| 自绘可点组件的读屏文字没查过 | `InkWell` 66、`GestureDetector` 20 处（62 个文件） | 读屏可能只念“按钮”或什么都不念 | A05.1 c2 |
| 没有自动的无障碍检查 | `apps/pure_live/test`、`packages/live_ui/test` 0 处 `meetsGuideline` | 以后改页面会退回去 | A05.1 c1（主要页面的触控在 A04.1） |
| 画面上的次要白在最亮画面上约 3.8:1 | `live_colors.dart:17`（20 处用到） | 节目单一行、提示在亮画面上看不清 | A05.1 X3，维护者定（看得见的改动） |
| 下拉刷新头、回到顶部按钮不跟随减少动态效果 | `refresh_view.dart`、`jump_buttons.dart:98-100` | 开了“移除动画”还有动画 | A05.1 c5 |
| Tab 顺序没查过 | 设置两栏、直播间分栏、多画面 | 键盘用户可能乱跳 | A05.1 |
| 可能不到 48 的按钮 | `VisualDensity.compact` 8 处、`shrinkWrap` 1 处（清单在 A04.1 README）；直播间详情把手 20 高 | 难点 | A04.1 阶段 3、A03.3 |

## 相关决定和规范

- D-005（用户看得到、听得到的文字一律中文，走翻译）、D-003（看得见的改动由维护者按建议 A 定）。
- [specs/UI.md](../../specs/UI.md) 第 3 节第 3 条（修 v3 的对比度和点击区域）、第 5.3 节（系统字体 1.3、1.5 倍不截断）、第 5.4 节（48×48、间距 8、悬停显示按钮名称、焦点框只在键盘时、Tab 顺序和视觉一致、Esc 返回链）、第 8.1 节（深浅两套分别检查对比度）、第 8.6 节（跟随减少动态效果）、第 12 节（验收：焦点框、快捷键、遥控器可达）、附录 A 第 7、16 条。

## 测试和验证

- 自动测试：上表（`cd packages/live_ui && flutter test test/components_test.dart test/dialog_support_test.dart test/popups_test.dart`）。缺的：每个区域的 `meetsGuideline` 三条、读屏文字的 `matchesSemantics` 断言、Tab 顺序、减少动态效果——都写在 A05.1 任务书里。
- 真机：TalkBack 走主要流程、Windows 只用键盘走一遍并试讲述人、系统“移除动画”和“字体最大”各一轮；步骤在 [A05.1 任务书](A05.1-无障碍检查/brief.md)“真机验证”。[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)里没有无障碍的条目（第 1 节第 19 条深浅色下状态栏图标看得清算半条），A05.1 完成后写 `verify.md`。

## 路线

1. 先做完 A01.2 第 3 阶段（颜色和字重）和 A04.1（尺寸、字号上限、主要页面的触控检查），免得对比度和触控查两遍。
2. [A05.1](A05.1-无障碍检查/README.md)（第三档）：自动检查和通用组件 → 首页、浏览、设置、账号 → 直播间、弹幕、录制、多画面 → 桌面和真机；登记表里要补阶段（见报告）。
3. 以后：VoiceOver（苹果平台，等能构建时）；新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：全部界面代码
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A05.1 | 无障碍检查：读屏文字、键盘焦点、对比度、48dp 触控区域全应用过一遍 | 界面 | 未开始 | — | — | — |

## 还没完成的

- **A05.1 无障碍检查：读屏文字、键盘焦点、对比度、48dp 触控区域全应用过一遍**（未开始，第三档，规模 中）

<!-- docs:生成结束 -->
