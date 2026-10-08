# A05.1 无障碍检查：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d34ad44d1` 开始）
- 设计或说明：[README.md](README.md)；任务书 [brief.md](brief.md)
- 这一轮的范围：Android 手机（当前只做 Android）。读屏文字、对比度、48dp 触控区域三项；键盘焦点、Esc 返回、减少动态效果留给下一轮（见最后）。

## 怎么查的

- 用 Flutter 自带的三条指南：`androidTapTargetGuideline`（能点的至少 48×48）、`labeledTapTargetGuideline`（能点的有读屏名字）、`textContrastGuideline`（WCAG AA：正文 4.5:1，18 号以上或 14 号加粗以上 3:1，不可用的不算）。README X2 选 A，就是这个标准。
- 开整个应用（`PureLiveApp`、真实主题、简体中文），手机竖屏 393×852，浅色、深色、深色 + 纯黑各一遍：首页四个页签（关注、热门、分区、录制中心）；搜索、观看记录、标签、工具箱、关注分区、设置总览和设置的每一页、录制设置、弹幕设置、屏蔽、平台管理、账号、备份、设备同步、日志、WebDAV、网络电视、本地互动、关于、版本、版本历史、网页搜索、多画面；直播间（横的画面在竖屏、竖屏直播流、横屏全屏）和它的清晰度、线路、更多、弹幕设置、录制、详情、切换直播间面板。长页面另外往下滚着查了一遍。
- 每个不合格的地方由测试辅助函数（`apps/pure_live/test/accessibility.dart`）从读屏节点反查到建它的代码（`文件:行`），下表的位置就是这样得出的（修之前的行号）。
- 纯黑主题没有多出来的问题；往下滚到一半、被固定标题栏压住的行（只露出 9～20 高）是滚动造成的假问题，不算。

## 查到的问题

| # | 类别 | 哪里 | 现象 | 怎么处理 |
|---|---|---|---|---|
| 1 | 读屏文字 | 直播间画面 `apps/pure_live/lib/features/live_play/player/player_view.dart:706` | 能点（显示 / 隐藏控制按钮、双击全屏），读屏没有名字，只念“按钮” | 修：念“直播画面”，提示“显示或隐藏控制按钮” |
| 2 | 读屏文字 | 平台管理每行的开关 `apps/pure_live/lib/features/hot_areas/hot_areas_page.dart:109` | 开关没有名字（平台名在另一个节点） | 修：开关念平台名，加“开关，已开启 / 已关闭” |
| 3 | 读屏状态 / 对比度 | 屏蔽页的滑条行（相似度阈值、缓存时间、最大缓存数量）`apps/pure_live/lib/shared/danmaku/setting_rows.dart:231`、`:240` | 关掉去重时标题和数值变灰（2.3:1），读屏却不知道它不可用 | 修：标成“不可用”（灰字本来就该是不可用的样子，对比度不再算） |
| 4 | 对比度 | 录制中心筛选“全部 1”选中时的数字 `apps/pure_live/lib/features/recorder/recorder_page.dart:489` | 主色底上 80% 的白，3.49:1（13 号） | 修：选中时数字用整色（4.54:1）；没选中的不变 |
| 5 | 对比度 | 直播间聊天上方“B 站名字”提示条的“去登录”`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:555` | 浅色主题主色字在次要容器色上 4.18:1（13 号） | 修：按钮字用提示条自己的字色（`onSecondaryContainer`，≥4.5:1）；深色主题本来就够，看起来一样 |
| 6 | 触控 | 录制中心任务卡片的“⋮”`apps/pure_live/lib/features/recorder/recorder_task_card.dart:391`（`packages/live_ui/lib/src/widgets/app_menu.dart:243`） | 40×40，而且移出行外的那部分点不到（只有约 34×34 真能点） | 修：按钮放到卡片角上，点击区 48×48，图标和按下的圆位置、大小不变 |
| 7 | 触控 | 竖屏直播流聊天右下的“本地弹幕”星 `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart:489` | 40×40（`shrinkWrap`） | 修：看起来仍 40、离角 12，点击区 48 |
| 8 | 触控 | 竖屏聊天下的本地弹幕输入条 `local_composer.dart:177`（样式星）、`:275`（输入框） | 星 48×46；输入框只有文字那一行 21 高能点，点条上下的空白不弹键盘 | 修：描边改画在上层，星和输入框占满 48；输入框和条一样高，文字仍在正中 |
| 9 | 触控 | 直播间顶栏的头像 `packages/live_ui/lib/src/widgets/avatar.dart:114`（`apps/pure_live/lib/features/live_play/layout/room_header.dart:164`） | 32×32 一个单独的读屏节点，和外面的“名字”区域做同一件事 | 修：读屏只留一个节点（头像、名字、“平台 · 分区”合成一句，提示“直播间详情”）；键盘焦点仍在头像上（B09 c9）；整块至少 48 高（原来 47） |
| 10 | 触控 | 弹幕设置页“更换弹幕字体”这类跳页的行 `apps/pure_live/lib/features/settings/danmaku_page.dart:136` | 39 高 | 修：至少 48，和旁边带开关的行一样 |
| 11 | 触控 | 直播间信息行（标题 + “详情 ⌄”）`apps/pure_live/lib/features/live_play/layout/room_info_bar.dart:113` | 40 高 | 没改，README X5 |
| 12 | 触控 | 画面上的本地弹幕输入框 `local_composer.dart:239`（星）、`:259`（发送）、`:275`（输入框） | 框 40 高，星和发送 44×40 | 没改，README X6 |
| 13 | 触控 | 搜索的“直播间 / 主播”分段按钮 `apps/pure_live/lib/features/search/search_widgets.dart:196`、两行的“搜索范围”行 `:326` | 紧凑密度 40；范围行 44 | 没改，README X7 |
| 14 | 触控 | 日志页的级别筛选 `apps/pure_live/lib/features/backup/log_page.dart:213` | 紧凑密度 40 | 没改，README X7 |
| 15 | 触控 | 切换直播间面板的分组芯片 `apps/pure_live/lib/features/live_play/switch_room/room_switch_panel.dart:509` | 40 高的栏里 32～34 | 没改，README X7 |
| 16 | 触控 | 配置预览的 JSON 树 `packages/live_ui/lib/src/widgets/json_tree.dart:158`（`apps/pure_live/lib/features/settings/data_tools.dart:582`） | 每行 36～40 | 没改，README X8 |
| 17 | 触控 | 多画面工具栏的布局分段按钮 `apps/pure_live/lib/features/multiview/widgets/toolbar.dart:45` | 44 高 | 没改，README X9 |
| 18 | 假问题 | 设备同步页的配对码 `apps/pure_live/lib/features/remote_receiver/remote_receiver_page.dart:490` | `SelectableText`（能选中复制的文字）被指南当成 36 高的按钮 | 不算：检查里跳过只读文字 |

按类别：读屏文字 2 处（1、2）、读屏状态 1 处（3）、对比度 2 处（4、5，加上 3 的灰字）、触控区域 12 处（修了 5 处：6～10；7 处要让看得见的地方变高，交维护者：11～17）。`IconButton` 全部都有按钮名称（脚本逐个看了构造参数，应用和 `live_ui` 一个不缺）。

## 改了什么

- 读屏文字（新翻译键两个，中英文都加，按键名排好）：`live_play_picture`“直播画面” / “Stream picture”；`live_play_picture_tap_hint`“显示或隐藏控制按钮” / “show or hide the controls”。平台管理的开关直接念平台名（已有的文字）。
- `apps/pure_live/lib/features/live_play/player/player_view.dart`：画面的手势外面加 `Semantics(container, label, onTapHint)`。读屏双击画面照旧显示 / 隐藏控制按钮。
- `apps/pure_live/lib/features/hot_areas/hot_areas_page.dart`：开关外面加 `Semantics(container, label: 平台名)`。
- `apps/pure_live/lib/shared/danmaku/setting_rows.dart`：滑条行的标题和数值放进 `Semantics(container, enabled:)`。
- `apps/pure_live/lib/features/recorder/recorder_page.dart`：选中的筛选芯片里数字不再减淡。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：“去登录”的字色用 `onSecondaryContainer`。
- `apps/pure_live/lib/features/recorder/recorder_task_card.dart`：“⋮”从卡片头部的行里挪到卡片的 `Stack` 角上（上、右各 2，48×48，按钮本身仍 40 居中，所以图标中心还在原来离卡片角 26 的位置）；头部原来的位置留 40 宽的空，文字可用宽度不变。
- `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart`：聊天上的星 `tapTargetSize: padded`（各平台都是 48 点击、40 看得见），位置从离角 12 改成 8，看起来不动；输入条的描边改用 `foregroundDecoration`（画在上层，不再占 1 像素的内边距）；输入框 `textAlignVertical: center` 加 `InputDecoration.constraints`（最小高度 = 条的高度）。
- `apps/pure_live/lib/features/live_play/layout/room_header.dart`：名字区域 `Semantics(container, tooltip: 直播间详情)`，头像 `ExcludeSemantics`；名字区域最小高 48。
- `apps/pure_live/lib/features/settings/danmaku_page.dart`：跳页的行最小高 48。
- 看得见的变化只有三处，都很小：4 的数字从 80% 变成整色；5 的“去登录”从主色变成提示条的深色字（浅色主题；深色主题下颜色接近）；10 的跳页行从 39 变成 48。其余都是只改读屏或只扩点击区。

## 自动检查（以后不退回）

- `apps/pure_live/test/accessibility.dart`：`expectAccessible(tester, '页面名', known: …)` 跑三条指南；不合格时每条写出节点的文字、尺寸或对比度、位置，以及建它的代码（`文件:行 < 文件:行`）。跳过只读文字；`known` 是暂时留着的已知问题（按建节点的文件和指南匹配）。各区域以后的布局测试也可以直接调用它。
- `apps/pure_live/test/accessibility_test.dart`：浅色、深色各两个用例，共 4 个：
  - 首页四个页签和常用页面、设置每一页（窗口 393×2000，整页的列表都在屏幕上，不用滚）；
  - 直播间：竖屏、控制按钮出来时、清晰度 / 线路 / 更多 / 弹幕设置 / 录制 / 详情；竖屏直播流和它的控制按钮；横屏全屏、控制按钮、更多、切换直播间。
- `_known` 里 6 条，对应 X5～X8；维护者定了以后改代码、删掉对应的一条。
- 验证过这个检查拦得住：把本轮 `lib/` 的改动全部撤掉再跑，4 个用例都失败，报出的就是上表 1、4、5、6、9 等。
- 原有测试改了一处：`apps/pure_live/test/features/live_play/room_on_phone_test.dart` 星的位置改为按看得见的 40 量（点击区 48）。

## 真机（K90，TalkBack）

1. 打开 TalkBack，首页底栏四个页签逐个点：念“关注，第 1 个标签，共 4 个”这类；关注页的卡片念出主播、标题、平台和开播状态。
2. 进一个直播间：顶栏名字处念一次“主播名，平台 · 分区”，提示“直播间详情”，双击打开详情（头像不再单独停一次）；画面念“直播画面”，双击显示 / 隐藏控制按钮；控制按钮（清晰度、线路、全屏、录制、关注、更多）都念出名字。
3. 竖屏直播流（竖着的画面）：聊天右下的星念“发送本地弹幕”，双击打开输入条；输入条上点框的上下空白处也能弹出键盘（不开 TalkBack 时试）。
4. 录制中心：卡片右上“⋮”念“更多”，手指点在图标外一点（离图标 4～5 像素）也能打开小菜单，不会误进直播间；筛选“全部”选中时数字看得清。
5. 设置 → 平台管理：每个开关念“哔哩哔哩，开关，已开启”。设置 → 弹幕 → 屏蔽：关掉“去重”后，相似度阈值等几行念“已停用”。
6. B 站直播间，聊天上方“名字”提示条的“去登录”（浅色主题）看得清。
7. 维护者定 X5～X9 时，可以在手机上对照：直播间信息行、全屏时画面上的输入框、搜索的“直播间 / 主播”、切换直播间的分组芯片。

## 留下的（下一轮，电脑上做）

- 键盘焦点和 Tab 顺序（P6）、二级页面 Esc 返回（c3、X4）、宽屏和 Windows 讲述人（A05.1-13）。
- 画面上的次要白（c4、X3）、下拉刷新头和回到顶部跟随“减少动态效果”（c5）。
- 状态只靠颜色的地方（P7）没有逐个查；这轮的指南不查这一项。
- 多画面、网络电视的格子和电视界面只看了读屏名字和点击区，没有进一步。
