# A05.1 无障碍检查：读屏文字、键盘焦点、对比度、48dp 触控区域全应用过一遍：设计（第 0 版，未开始）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（未开始，第三档，规模中）
- 旧编号：T01f.1（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：手机和宽屏（Android、Windows）的全部页面、弹窗、直播间：读屏文字（TalkBack、讲述人能念出每个能点的东西是什么、现在是什么状态）、键盘焦点（Tab 能走到、顺序和看到的一样、焦点框只在用键盘时出现、Esc 返回）、对比度（文字 4.5:1、大字和图标 3:1，深浅两套和纯黑都看）、触控区域（48×48），再加两项核对：跟随系统“减少动态效果”、大字不截断。电视的遥控器焦点归 A17（`apps/pure_live/lib/tv/widgets/tv_focusable.dart:59` 已做），本任务只看电视上的读屏文字
- 对应：[specs/UI.md](../../../specs/UI.md) 第 3 节第 3 条（修 v3 的对比度不够、点击区域太小）、第 5.3 节（系统字体 1.3、1.5 倍不截断）、第 5.4 节（点击区域至少 48×48、间距至少 8；焦点框只在用键盘时显示；Tab 顺序和视觉顺序一致；Esc 返回链）、第 8.1 节（深浅两套分别检查对比度）、第 8.6 节（跟随“减少动态效果”）、第 12 节（验收：悬停、快捷键、焦点框正确）；[inventory/UI.md](../../../inventory/UI.md)（逐项界面，检查时按它逐个过）；D-005（读屏念的文字也走翻译）
- 评审页：无。这是检查和修补任务，不改样子；如果某一处要改看得见的样子（例如次要文字加深、按钮变大），在那一处所属的界面任务里出图确认，或在本文件“待选和决定”里列出交维护者定
- 依赖：A02.1（焦点框、组件的状态，待真机）、A01.2（颜色和字重角色，开发中）、A04.1（字号上限和触控区域的自动检查，暂停）；和 A04.1 的分工：A04.1 做尺寸相关的部分（高度分档、字号上限、主要页面的 `androidTapTargetGuideline`），本任务做其余三项和全应用的清单
- 任务书：[brief.md](brief.md)

## 界面清点表

按区域分；每个区域都要过“状态”一列的四项。区域的逐项界面见 [inventory/UI.md](../../../inventory/UI.md) 对应任务。

| 编号 | 界面 | 从哪打开 | 形态 | 状态（要查的） |
|---|---|---|---|---|
| A05.1-01 | 通用组件：状态页、横幅、对话框、面板、提示条、小菜单、设置行、计数、芯片、标签、头像、卡片（`packages/live_ui/lib/src/widgets/`） | 全应用 | 竖屏、横屏、宽屏；浅色、深色、纯黑 | 读屏、焦点、对比度、触控、减少动态效果 |
| A05.1-02 | 首页外壳（底部导航、侧边导航、首页菜单）A06.1、A06.2 | 启动 | 竖屏、宽屏 | 同上 |
| A05.1-03 | 浏览：热门、关注、分区、分区房间、搜索、网页搜索、观看记录、标签（A09） | 首页 | 竖屏、宽屏（电脑翻页栏） | 同上；← → 翻页 |
| A05.1-04 | 直播间竖屏：顶栏、信息行、聊天、详情、三档面板（A07.1、A07.2） | 卡片 | 竖屏、竖屏全屏 | 同上；把手的“增大 / 减小” |
| A05.1-05 | 直播间全屏和宽屏：控制层、锁定、手势提示（A07.4、A07.5） | 双击、全屏键 | 横屏全屏、宽屏分栏 | 同上；画面上的文字对比度；键盘快捷键 |
| A05.1-06 | 直播间的面板和小菜单：清晰度、线路、录制、弹幕设置、长按弹幕、切换直播间（A07.6、A07.12、A07.13） | 直播间按钮 | 竖屏、横屏、宽屏 | 同上 |
| A05.1-07 | 弹幕：聊天列表、醒目留言、弹幕设置页、屏蔽页（A08） | 直播间、设置 | 竖屏、宽屏 | 同上；平台给的颜色上的字 |
| A05.1-08 | 录制：录制中心、录制设置、录制按钮和状态（A10） | 首页、直播间 | 竖屏、宽屏 | 同上；录制状态不只靠颜色 |
| A05.1-09 | 设置：总览、外观、播放、通用和网络、数据（A11） | 首页菜单 | 竖屏、宽屏两栏 | 同上；Ctrl/Cmd+F 搜索、Esc |
| A05.1-10 | 账号和数据：账号、扫码登录、Cookie、备份、WebDAV、设备同步（A12） | 设置 | 竖屏、宽屏 | 同上；二维码状态 |
| A05.1-11 | 网络电视、多画面（A13） | 首页菜单 | 竖屏、横屏、宽屏 | 同上；多画面格子 |
| A05.1-12 | 小页面：工具箱、关于、版本（A15）；启动页、全局弹窗（A06.3、A06.4） | 首页菜单 | 竖屏、宽屏 | 同上 |
| A05.1-13 | 桌面窗口：标题栏、托盘、关闭时的选择（A16） | Windows | 宽屏 | 读屏（讲述人）、焦点、窗口按钮 |
| A05.1-14 | 系统界面：通知、画中画、小窗（A14、A07.8） | 后台播放、离开直播间 | 系统 | 通知的文字、小窗按钮的读屏 |

## 3.x 的样子和问题

### 3.x（`v3.2.11`，`lib/` 下）

- 读屏：`Semantics(` 44 处（含 GetX 自带代码）、`semanticLabel` 25 处、`semanticsLabel` 9 处、`tooltip:` 122 处（`IconButton(` 98 处）。能用读屏调大小的：三档面板把手（`lib/modules/live_play/widgets/layout/live_play_content.dart:314-317` 的 `onIncrease`/`onDecrease`）、音量（`lib/modules/live_play/widgets/video_player/volume_control.dart:289-295`，念“房间音量 50%”，±5%）、网络电视输入框高度（`lib/modules/iptv/iptv_page.dart:622-623`）。
- 键盘：直播间 `lib/modules/live_play/widgets/keyboard/video_keyboard.dart:53-80`（Esc 依次退全屏、退宽屏、返回；空格和媒体键暂停；R 刷新；↑↓ 音量 ±5%）；列表页电脑翻页 ← →（`lib/common/base/base_page_view_extension.dart:8-20`）。没有焦点框：主题关了水波（`lib/common/style/theme.dart:114` 的 `NoSplash`），焦点只是底色（A02.1 P21）。
- 对比度：默认蓝 `Colors.blue` 上的白字 3.1:1（规范候选 C-3）；设置组标题主色 65% 约 2.9:1、说明提示色 75% 约 3.3:1（A02.1 P12）；计数按钮深色主题白图标约 1.7:1（A02.1 P8）；开关打开时 50% 透明的底约 2.8:1（A02.1 P14）。
- 触控：回到顶部 40 的小按钮（`lib/common/base/base_page_view_extension.dart:64-99`，A02.1 P20）。
- 文字缩放：`lib/main.dart:184` 用应用倍数替换系统字号，系统字体调大在应用里没用（A04.1）。

### 4.x 现在（2026-10-03 读代码）

- 已经修了的：品牌蓝 `#2E6FE0` 白字 4.7:1（A11.2，`packages/live_ui/lib/src/theme/live_theme.dart:177`）；设置行说明、组标题、横幅、状态页、计数、开关的对比度（A02.1 c10、c14、c15，测试 `packages/live_ui/test/components_test.dart:166-168`、`:222-224`、`:501-504`）；回到顶部点击区域 48（`jump_buttons.dart`）；键盘焦点框：按钮、芯片、标签由主题和组件画（`live_theme.dart:31` 的 `FocusFrame`、`app_chip.dart:73`、`tab_label.dart:62-66`），自绘的可点组件用 `FocusRing`（`focus_ring.dart:12`，只在 `focusFramesShown` 时，`:5`）；设置行（`settings_row.dart:475-480`）、房间卡片（`live_room_card.dart:137`）自己画焦点框。
- 读屏：`IconButton` 102 个，按粗查都写了 `tooltip`；自绘的 `InkWell`、`GestureDetector` 86 个（62 个文件，不含电视），没有逐个查过有没有读屏文字；`Semantics(`（含 `MergeSemantics`）应用 25 处、`live_ui` 18 处；`semanticLabel` 应用 4 处、`live_ui` 16 处；三档面板把手照 3.x 能“增大 / 减小”（`apps/pure_live/lib/features/live_play/layout/portrait_panel.dart:255-267`）；音量改成了 Flutter 的 `Slider`（`features/live_play/player/bar_parts.dart:206`，自带读屏）。测试里只有 `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` 用了读屏的查找（2 处），没有 `meetsGuideline`。
- 键盘：直播间 `features/live_play/live_play_page.dart:736-753`（Esc、F、空格、↑↓、R、媒体键）；设置 `features/settings/settings_page.dart:235-239`（Ctrl/Cmd+F 搜索、Esc 清搜索）；房间列表 ← → 翻页（`shared/rooms/room_grid.dart:583`、`features/favorite/favorite_page.dart:510`、`features/areas/platform_areas_view.dart:244`）；对话框回车 = 主要按钮、Esc = 取消（`packages/live_ui/lib/src/widgets/dialog_keys.dart:12`）；Esc 返回（`escape_back.dart:10`）只用在搜索、网页搜索、观看记录（`features/search/search_view.dart:371`、`search/web_search_view.dart:163`、`history/history_page.dart:229`），加上直播间、多画面（`features/multiview/multiview_page.dart:380`）。其他二级页面（设置的子页、关于、版本、标签、屏蔽、工具箱、账号、录制中心等）在电脑上按 Esc 不返回（应用里没有全局的处理，`apps/pure_live/lib/app/`、`routes/` 里搜不到 `escape`；桌面上的 Flutter 不会把没人处理的 Esc 变成返回，3.x `lib/modules/live_play/widgets/keyboard/video_keyboard.dart:36-40` 的注释写了这一点；真机上再按一次确认）。`FocusTraversalGroup` 手机界面只有 1 处。
- 对比度还要看的：画面上的次要白 `OnVideoColors.secondary`（70% 白，`packages/live_ui/lib/src/theme/live_colors.dart:17`，用了 20 处）在最亮的画面上、60% 黑渐变上约 3.8:1（白字是 5.7:1，`:22-24` 的注释）；平台给的颜色上的字由 `InkOnColor` 按对比度选（`live_colors.dart:258`，测试 `widgets_test.dart` 的 `InkOnColor.contrastOn`）；`hintColor` 还有 8 处（应用 3、`live_ui` 5）。
- 减少动态效果：小菜单（`anchored_menu.dart:62`）、录制图形（`record_glyph.dart:80`）、侧面板（`apps/pure_live/lib/shared/panels/side_panel.dart:105`）、直播间几处（`live_play_page.dart:895`、`:1048`、`:1247`、`room_swipe.dart:182` 等）跟随；下拉刷新头不跟随（`packages/live_ui/lib/src/widgets/refresh_view.dart` 没有判断，A03.1 留下）；回到顶部按钮的 200 毫秒缩放（`jump_buttons.dart:98-100`）不跟随。
- 触控：可能不到 48 的 `VisualDensity.compact` 8 处、`MaterialTapTargetSize.shrinkWrap` 1 处（清单在 [A04.1](../../A04-尺寸和适配/A04.1-尺寸和字号适配/README.md)）；直播间详情把手 20 高（A03.3）。

### 问题

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | 自绘的可点组件（`InkWell` 66、`GestureDetector` 20）没有逐个查读屏文字；卡片、格子、头像、芯片念出来的是什么没有测试 | 见上；`apps/pure_live/lib/features/multiview/widgets/cell_view.dart`、`app/desktop/title_bar.dart`、`features/live_play/player/player_view.dart` 等 |
| P2 | 二级页面在电脑上 Esc 不返回（规范 5.4“Esc 依次关弹层、退全屏、返回”） | 只有 6 处处理 Esc，见上 |
| P3 | 没有自动的无障碍检查（`meetsGuideline` 0 处），以后改页面时会退回去 | `apps/pure_live/test`、`packages/live_ui/test` |
| P4 | 画面上的次要白在亮画面上约 3.8:1，不到 4.5:1 | `live_colors.dart:17` |
| P5 | 下拉刷新头、回到顶部按钮不跟随“减少动态效果” | `refresh_view.dart`、`jump_buttons.dart:98-100` |
| P6 | Tab 顺序没有检查过（宽屏两栏的设置、直播间分栏、多画面） | `features/settings/settings_page.dart`、`live_play_page.dart`、`multiview_page.dart` |
| P7 | 状态只靠颜色区分的地方没有查过（录制中的红、已关注的灰、当前项的主色——当前项已有勾，A02.2 c3） | 各页面 |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| — | 没开始；登记时（T01f.1）只写了标题 | — |

## 对比页（按章节导出）

无（检查任务，没有评审页）。

## 单张图

无。

## 确认的改动

还没有确认的改动。下面是建议的做法，开工时由维护者确认（D-003 可按建议 A）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 增强 | 每个区域的布局测试加 `androidTapTargetGuideline`、`labeledTapTargetGuideline`、`textContrastGuideline` 三条（浅色、深色各一次），作为以后不退回的锁 | P3 |
| c2 | 修改 | 自绘的可点组件补读屏文字（`Semantics(button: true, label: …)` 或改用带 `tooltip` 的按钮），状态（选中、开关、进行中）念出来；文字走翻译（zh、en） | P1、P7 |
| c3 | 修改 | 二级页面统一用 `EscapeBack`（`packages/live_ui/lib/src/widgets/escape_back.dart`），或在路由层统一处理 Esc = 返回 | P2 |
| c4 | 修改 | 画面上的次要文字：A 把 `OnVideoColors.secondary` 从 70% 白提到 85%（在最亮画面上约 4.7:1；80% 只有 4.4:1）；B 保持，只用于大字和图标 | P4 |
| c5 | 修改 | 下拉刷新头、回到顶部按钮跟随“减少动态效果” | P5 |
| c6 | 保留 | 3.x 的读屏调节（三档面板把手、音量）、键盘快捷键（规范附录 A 第 16 条）、焦点框只在键盘时出现 | — |

## 按钮的作用和用法

不加新按钮。要逐页核对的键盘操作（宽屏）：

| 编号 | 按键 | 期望 |
|---|---|---|
| 1 | Tab / Shift+Tab | 按看到的顺序走过每个能点的东西，焦点框 2 像素主色；走不到的、走到看不见的地方都算问题 |
| 2 | 回车、空格 | 按下有焦点的按钮、开关、行；对话框里回车 = 主要按钮 |
| 3 | Esc | 先关弹层，再退全屏，再返回上一页（规范 5.4） |
| 4 | 方向键 | 菜单和选项里上下移动；计数、滑块左右调；房间列表 ← → 翻页（电脑） |
| 5 | 直播间：空格、F、R、↑↓、媒体键 | 照 3.x（规范附录 A 第 16 条） |
| 6 | 设置：Ctrl/Cmd+F | 跳到搜索框 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | TalkBack 走一遍各区域；K90 上系统“移除动画”“字体最大”各开一次；触控区域靠测试 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 键盘走一遍（上表）；Windows 讲述人念主要页面；鼠标悬停有按钮名称 |
| 电视 | 遥控器焦点归 A17（已做）；本任务只看读屏文字（TalkBack 在电视上也能开） |
| 苹果平台差异 | VoiceOver 只设计不验证（本机没有 Mac）；快捷键用 Cmd |

## 待选和决定

- X1 自动检查放在哪：A 加在每个区域已有的布局测试里（建议，离改动最近）；B 单独一个 `accessibility_test.dart` 把主要页面都开一遍。
- X2 对比度标准：A 正文 4.5:1、18 号以上或加粗 14 号以上的大字和图标 3:1、不可用的不算（WCAG AA，建议）；B 全部 4.5:1。
- X3 画面上的次要白（P4）：A 提到 85%（建议）；B 保持 70%（画面多数时候不是全白，渐变也不止 60%）。
- X4 Esc 返回：A 每个二级页面套 `EscapeBack`（建议，和 A02.1 一致，页面能先做自己的一步）；B 路由层统一处理（改动少，但页面不能先关自己的筛选）。

## 实现和验证（开发后补）

- 实现：没开始。
- 验证：没开始；完成后写 `verify.md`（TalkBack、键盘、移除动画、字体最大四轮）。
- 留下的问题和去向：本任务只修“看不见的”部分（读屏文字、焦点、点击区）；要改看得见的样子的（颜色深浅、按钮大小），写进“待选和决定”交维护者，定了在所属的界面任务里做。
