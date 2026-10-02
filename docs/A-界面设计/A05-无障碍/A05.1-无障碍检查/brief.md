# A05.1 无障碍检查：读屏文字、键盘焦点、对比度、48dp 触控区域全应用过一遍：任务书

## 背景

- 来源：界面重构计划书 [specs/UI.md](../../../specs/UI.md) 第 3 节第 3 条（修 v3 的对比度不够、点击区域太小）、第 5.4 节（48×48、焦点框只在键盘时、Tab 顺序和视觉一致、Esc 返回链）、第 8.1 节（深浅两套分别检查对比度）、第 8.6 节（跟随“减少动态效果”）。登记时（旧编号 T01f.1）只有标题，没有任务单；这一页是第一份任务书。
- 现象（读代码得出，真机还没看过）：
  - 电脑上在设置的子页、关于、版本、标签、屏蔽、工具箱、账号、录制中心按 Esc 不返回；只有搜索、网页搜索、观看记录、直播间、多画面、设置搜索处理了 Esc。
  - 自绘的可点组件（`InkWell` 66 个、`GestureDetector` 20 个，不含电视）有没有读屏文字没人查过；读屏打开后念出来的是什么没有测试。
  - 画面上的次要文字（节目单一行、提示）是 70% 白，在很亮的画面上约 3.8:1。
  - 下拉刷新头、回到顶部按钮不跟随系统“移除动画”。
  - 没有任何自动的无障碍检查（`meetsGuideline` 0 处）。
- 为什么现在做：第三档（以后）。A02.1、A01.2、A04.1 把组件、颜色、尺寸做好之后，用一遍全应用的检查把剩下的补上，并加自动检查防止退回。
- 规模：中；分组：组件；依赖：A02.1（待真机）、A01.2 第 3 阶段（暂停中，颜色和字重角色）、A04.1（暂停，触控区域和字号上限）——**最好在 A01.2、A04.1 之后做**，否则对比度和触控要查两遍；能否和别的任务同时做：会碰很多页面，和其他界面任务按区域错开。
- 出设计：不用。只修看不见的部分（读屏文字、焦点、点击区、动画开关）；要改看得见的样子的（颜色深浅、按钮大小）先写进 `README.md`“待选和决定”交维护者，定了再做。
- 已经做过的：A02.1（焦点框 `FocusRing`、`FocusFrame`、`EscapeBack`、设置行和横幅的对比度测试）；A11.2（品牌蓝 4.7:1）；A02.2（对话框回车 / Esc、当前项“主色 + 勾”）；A03.2、A02.3（侧面板、小菜单跟随减少动态效果）。

## 目标和验收

1. 每个区域（[README.md](README.md) 界面清点表 A05.1-01～14）过一遍四项，结果写进 `record.md` 的检查表（区域 × 四项，每格“通过”或问题和修法）。
2. 读屏：所有能点的东西有读屏文字（中英文都有，走翻译），状态（选中、开关、进行中、已关注）念得出来；纯装饰的图不念。
3. 键盘（宽屏）：Tab 能走到所有能点的东西、顺序和看到的一样；焦点框只在用键盘时出现；二级页面 Esc 返回（先关页面自己的弹层或筛选）。
4. 对比度：正文 4.5:1，大字（18 号以上或 14 号加粗以上）和图标 3:1；浅色、深色、纯黑都看；不可用的状态不算。
5. 触控：能点的东西至少 48×48（主要页面由 A04.1 加测试；本任务补其余页面）。
6. 跟随“减少动态效果”：下拉刷新头、回到顶部按钮，以及检查中发现的其他动画。
7. 每个区域的布局测试加 `androidTapTargetGuideline`、`labeledTapTargetGuideline`、`textContrastGuideline`（浅色、深色），以后改页面时自动拦住退回。
8. 门禁通过；`live_ui`、`apps/pure_live` 全部测试通过。

## 现状（读代码得出，写文件:行）

- 读屏：`IconButton` 102 个（应用和 `live_ui`），粗查都写了 `tooltip`；`Semantics(`（含 `MergeSemantics`）应用 25 处、`live_ui` 18 处；`semanticLabel` 应用 4、`live_ui` 16；`semanticsLabel` 应用 2；`ExcludeSemantics` 只有 `live_ui` 1 处。自绘可点组件最多的文件：`packages/live_ui/lib/src/widgets/color_picker.dart`（5）、`apps/pure_live/lib/app/desktop/title_bar.dart`（3）、`features/live_play/local_interaction/local_interaction_panel.dart`（3）、`features/live_play/player/player_view.dart`（3）、`shared/rooms/room_tags_dialog.dart`、`shared/rooms/paging.dart`、`features/multiview/multiview_page.dart`、`multiview/widgets/cell_view.dart`、`features/iptv/iptv_cards.dart`、`live_play/danmaku/chat_list.dart`、`live_play/layout/room_details.dart`、`live_play/switch_room/room_switch_tiles.dart`、`live_play/record/record_panel.dart`、`live_play/player/player_status.dart`、`settings/appearance_pages.dart`（各 2）；共 62 个文件。读屏能调的：三档面板把手 `features/live_play/layout/portrait_panel.dart:255-267`（照 3.x）；计数 `packages/live_ui/lib/src/widgets/count_button.dart`（`Semantics` 8 处）；设置里的数值行 `features/settings/settings_tiles.dart:497-498`、`appearance_pages.dart:222-223`、`features/record_settings/record_settings_page.dart:567-568`。
- 键盘：焦点框 `packages/live_ui/lib/src/widgets/focus_ring.dart:5`（`focusFramesShown`，只在 `FocusHighlightMode.traditional`）、`:12`（`FocusRing`，用在 `jump_buttons.dart:103`、`avatar.dart:112`）；主题 `packages/live_ui/lib/src/theme/live_theme.dart:31`（`FocusFrame`，按钮）、`app_chip.dart:73`、`tab_label.dart:62-66`、`settings_row.dart:475-480`、`live_room_card.dart:137`、`:757`。快捷键：`apps/pure_live/lib/features/live_play/live_play_page.dart:736-753`；`features/settings/settings_page.dart:235-239`；`shared/rooms/room_grid.dart:583`、`features/favorite/favorite_page.dart:510`、`features/areas/platform_areas_view.dart:244`（← → 翻页）；`features/account/cookie_editor.dart:398`；对话框 `packages/live_ui/lib/src/widgets/dialog_keys.dart:12`。Esc 返回：`escape_back.dart:10`，用在 `features/search/search_view.dart:371`、`search/web_search_view.dart:163`、`history/history_page.dart:229`；另外 `features/multiview/multiview_page.dart:380`、直播间 `:738`。`apps/pure_live/lib/app/`、`routes/` 没有全局的 Esc 处理；桌面上的 Flutter 不会把没人处理的 Esc 变成返回（3.x 在 `lib/modules/live_play/widgets/keyboard/video_keyboard.dart:36-40` 的注释里写了这一点，所以直播间自己处理）；真机上再按一次确认。`FocusTraversalGroup` 手机界面 1 处。
- 对比度：已有的测试 `packages/live_ui/test/components_test.dart:20`（`_contrast`）、`:166-168`、`:222-224`、`:501-504`；`widgets_test.dart`（`InkOnColor.contrastOn`、二维码颜色）；`design_system_test.dart`（关闭按钮红、录制提示 4.5:1）。还要看的：`OnVideoColors.secondary`（`packages/live_ui/lib/src/theme/live_colors.dart:17`，70% 白，20 处用到）在 60% 黑渐变（`:24`）上、最亮画面下约 3.8:1；`hintColor` 8 处（`apps/pure_live/lib/shared/rooms/paging.dart`、`features/web_dav/web_dav_help.dart`、`features/backup/log_page.dart` 和 `live_ui` 5 处）。
- 减少动态效果：跟随的有 `anchored_menu.dart:62`、`record_glyph.dart:80`、`pip_danmaku_preview.dart:110`、`apps/pure_live/lib/shared/panels/side_panel.dart:105`、`features/live_play/live_play_page.dart:895`、`:1048`、`:1247`、`layout/portrait_panel.dart:206`、`player/room_swipe.dart:182`、`player/bar_parts.dart:378`、`local_interaction/*`、`features/recorder/recorder_page.dart:180`；不跟随的：`packages/live_ui/lib/src/widgets/refresh_view.dart`（没有判断，A03.1 留下）、`jump_buttons.dart:98-100`（200 毫秒缩放）。
- 触控：`VisualDensity.compact` 8 处、`MaterialTapTargetSize.shrinkWrap` 1 处（清单在 [A04.1 的 README](../../A04-尺寸和适配/A04.1-尺寸和字号适配/README.md)），直播间详情把手 20 高（A03.3）。
- 测试：读屏的查找只有 `apps/pure_live/test/features/live_play/live_play_layouts_test.dart`（2 处）；`meetsGuideline` 0 处。

## 3.x 基线

- 读屏：`Semantics(` 44 处、`semanticLabel` 25、`semanticsLabel` 9、`tooltip:` 122（`IconButton(` 98）；能调的：`lib/modules/live_play/widgets/layout/live_play_content.dart:314-317`（三档面板）、`lib/modules/live_play/widgets/video_player/volume_control.dart:289-295`（音量，念“房间音量 x%”）、`lib/modules/iptv/iptv_page.dart:622-623`（输入框高度）。
- 键盘：`lib/modules/live_play/widgets/keyboard/video_keyboard.dart:53-80`（Esc 链、空格、媒体键、R、↑↓）；`lib/common/base/base_page_view_extension.dart:8-20`（← → 翻页）。没有焦点框（`lib/common/style/theme.dart:114` 的 `NoSplash`）。
- 对比度和触控的问题见 [README.md](README.md)“3.x 的样子和问题”（默认蓝 3.1:1、设置组标题约 2.9:1、说明约 3.3:1、回到顶部 40）——4.x 已修。
- 要保留（[specs/UI.md](../../../specs/UI.md) 附录 A）：第 7 条（返回链：弹层 → 全屏 → 普通 → 离开，Esc 走同一条）、第 16 条（键盘：空格和媒体键、R、↑↓、Esc）；三档面板和音量的读屏调节；用户看得到的样子（本任务不改）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3、5.4、8.1、8.6、12 节和附录 A。
3. 本文件夹的 `README.md`；[A05 子分类页](../README.md)；`docs/A-界面设计/A02-组件/A02.1-通用组件/README.md` 的 c21（焦点框）和 `record-2.md`（焦点框、Esc 的测试写法）；`docs/A-界面设计/A04-尺寸和适配/A04.1-尺寸和字号适配/brief.md`（和本任务的分工）。
4. `packages/live_ui/lib/src/widgets/focus_ring.dart`、`escape_back.dart`、`dialog_keys.dart`、`refresh_view.dart`、`jump_buttons.dart`；`packages/live_ui/lib/src/theme/live_colors.dart`（`OnVideoColors`、`InkOnColor`）；`packages/live_ui/test/components_test.dart`（对比度测试的写法）。
5. Flutter 的 `flutter_test` 里 `androidTapTargetGuideline`、`labeledTapTargetGuideline`、`textContrastGuideline` 的说明（`textContrastGuideline` 只查能取到前景和背景色的文字，画面上的文字要手算）。

## 范围

- 可以改：`packages/live_ui/lib/src/widgets/`（读屏文字、焦点、减少动态效果）、`packages/live_ui/test/`；`apps/pure_live/lib/features/**`、`shared/**`（只加 `Semantics`、`tooltip`、`EscapeBack`、焦点顺序、点击区）；`apps/pure_live/assets/translations/zh.json`、`en.json`（读屏文字，键名排序、4 空格缩进）；`apps/pure_live/test/`；本文件夹的 `record.md`、`verify.md`、`README.md`（“待选和决定”）。
- 不能改：看得见的样子（颜色、字号、尺寸、布局、图标）——要改的写进“待选和决定”；`apps/pure_live/lib/tv/`（A17）；`packages/live_ui/lib/src/theme/live_colors.dart` 的数值（P4 定了以后才改）；3.x 的设置键名和含义（D-018）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

登记表里还没有阶段（中规模应该有，见报告）；建议这样分，开工前写进登记表：

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 自动检查和通用组件 | c1 的写法定下来（一个测试辅助函数，跑三条指南、浅色深色各一次）；`live_ui` 组件逐个过四项并补上；c5 下拉刷新头和回到顶部跟随减少动态效果 | `packages/live_ui/lib/src/widgets/*`、`packages/live_ui/test/*` | 区域 A05.1-01 的检查表填完；`live_ui` 测试全过 |
| 2 首页、浏览、设置、账号、小页面 | 区域 A05.1-02、03、09、10、12：c2 补读屏文字、c3 二级页面 Esc 返回、Tab 顺序（设置两栏）；布局测试加 c1 | 对应的 `features/*`、`shared/*` 和测试 | 这些区域的检查表填完、测试全过 |
| 3 直播间、弹幕、录制、多画面、网络电视 | 区域 A05.1-04～08、11、14：画面上的控件读屏文字、全屏和分栏的 Tab 顺序、录制状态不只靠颜色；P4 的数值等维护者定 | `features/live_play/*`、`features/multiview/*`、`features/recorder/*`、`features/iptv/*`、`shared/danmaku/*` 和测试 | 同上（直播间组同时只交给一个执行者，开工前确认 A03.3 不在做） |
| 4 桌面和真机 | 区域 A05.1-13（标题栏、托盘、关闭对话框的讲述人和键盘）；写 `verify.md`（TalkBack、键盘、移除动画、字体最大四轮） | `app/desktop/*`、`verify.md` | 维护者按 `verify.md` 看完 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- c1：每个区域至少一个页面的测试加三条指南：`await expectLater(tester, meetsGuideline(androidTapTargetGuideline));`、`labeledTapTargetGuideline`、`textContrastGuideline`；浅色、深色各跑一次。指南失败时先看是不是测试里的假数据（例如空字符串的按钮），不要为了过测试改样子。
- 读屏：关键控件用 `tester.ensureSemantics()` 和 `find.bySemanticsLabel` / `matchesSemantics(label:, isButton:, isToggled:)` 断言念出来的文字和状态（卡片、格子、头像、芯片、开关、录制按钮）。
- 键盘：`tester.sendKeyEvent(LogicalKeyboardKey.tab)` 走一遍设置两栏、直播间分栏，断言焦点顺序；`LogicalKeyboardKey.escape` 在二级页面返回（照 `components_test.dart` 里 `EscapeBack` 的用例）。
- 减少动态效果：`MediaQuery(data: MediaQueryData(disableAnimations: true))` 下刷新头和回到顶部没有动画（一帧到位）。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 打开 TalkBack，从首页走到热门、点进一个直播间、打开清晰度菜单、返回，再走设置 → 外观 | 每个能点的东西都念出它是什么（和状态，例如“已关注”“开关，已开启”）；不念装饰图；能完成这些操作 |
| 2. TalkBack 下在竖屏直播间找到三档面板把手，上下滑调节 | 念“增大 / 减小”，面板跟着变 |
| 3. Windows 上只用键盘：Tab 走首页、设置两栏、直播间；在设置子页、关于、版本、标签按 Esc | 焦点框 2 像素主色、顺序和看到的一样；Esc 返回上一页 |
| 4. 系统设置 → 无障碍 → 移除动画打开后，下拉刷新、滑到回到顶部出现 | 没有动画，直接到位；测完关掉 |
| 5. 浅色、深色、纯黑各看一遍设置、关注、直播间横屏全屏 | 文字都看得清；画面上的次要文字在亮画面上也能看清（P4 定了之后） |

## 风险和注意

- 这是全应用的检查，会碰到很多其他任务正在改的文件：按区域分阶段、每个阶段开工前合并最新 master，和当时在做的界面任务错开。
- 读屏文字是用户看不到但听得到的文字，同样走翻译（D-005）；不要写死中文。
- `textContrastGuideline` 取不到画面上的颜色（视频不是 Flutter 画的），画面上的文字按 `OnVideoColors` 的渐变手算（README 里的 3.8:1 就是这样算的）。
- 不要为了读屏把能点的大区域拆成很多小节点；卡片这类用 `MergeSemantics` 合成一句。
- Esc 返回不能破坏页面自己的“先关一步”（例如搜索先清空、设置先关搜索）：照 `EscapeBack` 的 `onEscape`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A05.1` 或本机工作区；提交信息以 `[A05.1]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪些区域的检查表填完了）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；每个区域四项的结果（通过 / 修了什么 / 留给谁）；新加的读屏文字和翻译键；加了指南检查的测试文件；测试数量；改了哪些文件；“待选和决定”里要维护者定的（对比度、看得见的改动）；要在真机上看的；可能冲突的文件。
