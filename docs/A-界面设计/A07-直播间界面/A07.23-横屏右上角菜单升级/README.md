# A07.23 横屏右上角菜单的样子升级，以及同类老样子的菜单和弹出层

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：用户 2026-10-09：“1.横屏，右上角点击打开，ui、界面很古老，需要升级优化，顺便看看还没有这种问题，全部修复”
- 相关：决定 D-001（3.x 的功能一个不少）、D-003（设计由维护者选，不出评审页，直接做）、D-038（单击画面的规则不变）；[specs/UI.md](../../../specs/UI.md) 第 3 节第 7、8 条、第 5.3 节、第 7 节；直播间弹窗 [A07.6](../A07.6-直播间弹窗/README.md)（右上角菜单 c6）、子弹窗统一 [A07.12](../A07.12-直播间子弹窗统一/README.md)、切换直播间 [A07.13](../A07.13-切换直播间面板/README.md)（c12：全屏菜单去掉栏上已有的项）；任务书 [brief.md](brief.md)、记录 [record.md](record.md)、真机步骤 [verify.md](verify.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A07.23-01 | 右上角菜单（画面上） | 横屏全屏上栏最右的四宫格；竖屏全屏上栏最右的四宫格；电脑窗口内全屏 | 横屏、竖屏全屏、窗口内全屏 | 默认；定时关闭开着（第二行“N 分钟后暂停”）；没在播放（投屏、获取直链变灰）；本地互动开 / 关；网络电视频道（没有分享、在平台打开） |
| A07.23-02 | 右上角菜单（直播间页顶栏） | 竖屏、宽屏、手机横着不全屏时顶栏的四宫格 | 竖屏、宽屏 | 同上（不改） |
| A07.23-03 | 网络电视卡片“更多” | 网络电视管理的节目源卡片右上 ⋮、右键卡片 | 竖屏、宽屏 | 网络、本地 |
| A07.23-04 | 日志级别 | 设置 → 日志 →“日志级别” | 竖屏、宽屏 | 当前级别 |

## 改之前的样子和问题（读代码得出）

- **横屏右上角打开的是什么**：横屏全屏上栏的菜单按钮是 `RoomMenuButton(onVideo: true)`（`apps/pure_live/lib/features/live_play/player/player_controls.dart:401`），改之前它和直播间页顶栏（`layout/room_header.dart:106`）是同一个东西：`live_ui` 的贴着按钮的小菜单 `AppMenuButton` → `showAppMenu`（`packages/live_ui/lib/src/widgets/app_menu.dart:88`）→ `showAnchoredMenu`（`anchored_menu.dart:50`），里面一行一个 Material `PopupMenuItem`（`app_menu.dart:126`）、组间是 `PopupMenuDivider`（`:123`）。`onVideo` 只把按钮图标改成白色，菜单本身没有任何画面上的处理。
- **为什么看着老**：
  - P1 样子是桌面右键菜单：浅色主题下是 `surfaceContainerHighest` 的浅灰小方块（`anchored_menu.dart:340-346`，圆角 8、阴影 3），压在黑色画面的右上角，和横屏的其他东西（右侧 360 宽、全高的面板：切换直播间、定时关闭、房间音量、录制、弹幕设置，`shared/panels/side_panel.dart:152`）不是一套。
  - P2 挤在角落：宽最多 280（`app_menu.dart:109`），贴着按钮往下开（`anchored_menu.dart:209`）；K90 横着只有 400 高，按钮下面约 336 能放，六行加两条分隔线正好塞满，定时关闭开着（多一行“N 分钟后暂停”）就要滚动；组之间只是一条细线，没有分组的块。
  - P3 点一项后跳到另一处：菜单关掉，再从右侧滑出那一项的面板，眼睛要从右上角的小菜单跳到右侧面板。
- **竖屏的菜单**：直播间页顶栏的四宫格打开的是同一个小菜单（三组：切换直播间、定时关闭、房间音量、画面比例 ｜ 投屏、获取直链、分享、在<平台>打开、在新窗口打开 ｜ 本地互动，`buttons/room_menu_button.dart:158` 的 `roomMenuGroups`），在页面的顶栏下面、不压画面，和首页的“更多”等菜单一致，不算老样子，不改。
- 3.x：`v3.2.11:lib/modules/live_play/widgets/button/live_play_menu_button.dart:23` 是 Material `PopupMenuButton`，全屏时同样是这个浅色小菜单（九项：打开直播间、切换直播间、投屏、定时关闭、房间音量、获取直链、分享、本地互动、在新窗口打开）。

## 设计（维护者按 D-003 定，不出评审页）

| 编号 | 内容 | 理由 |
|---|---|---|
| c1 | 画面上的右上角菜单（横屏全屏、竖屏全屏、电脑窗口内全屏）改成直播间面板 `RoomMenuPanel`（`RoomPanelKind.menu`）：横屏在右侧 360 宽、全高，竖屏全屏在底部 60%，和其他面板同一个位置、同一个外框（`RoomSidePanel`：标题“菜单”、✕、竖屏下拉关闭、返回键先关它） | 规范第 5.3 节：横屏的弹出放右侧；菜单里八成的项本来就打开右侧面板（P3），现在在原处换成那一项的面板，不跳；横屏只有 400 高，面板全高放得下 |
| c2 | 内容：和竖屏菜单同样的分组、顺序、图标、第二行（`roomMenuItems`，两边共用）；每组一个圆角卡片（`PanelCard`，和弹幕设置、定时关闭面板一样），组间 8；每行最少 52 高（可点 48 以上）、24 号图标（次要色）、名字 15 号、第二行 13 号次要色；打开面板的行末尾有 ›（定时关闭、房间音量、投屏、获取直链、切换直播间、本地互动），直接执行的没有（分享、在<平台>打开、在新窗口打开、画面比例） | 和竖屏菜单一致（同一份数据）；52 高让 K90 横着的 400 高里六行加标题不用滚动 |
| c3 | 配色跟应用主题（`scheme.surface` 上的卡片），三套主题（浅、深、纯黑）都一样做；不另做一套画面上的深色菜单 | 规范第 3 节第 7 条“弹窗配色跟应用主题，全屏时不另换一套”；面板不透明，画面不影响对比度，名字和图标在卡片上至少 4.5:1（测试里算） |
| c4 | 点按：打开面板的项在原处换成那个面板；分享、在<平台>打开、在新窗口打开先关面板再执行；画面比例在这一行旁边弹小菜单，选了比例才关面板，点外面取消时面板留着；没在播放时投屏、获取直链变灰（和以前一样）；竖屏全屏时再点一次四宫格关掉面板（横屏时面板盖住按钮，用 ✕ 或返回键） | 3.x 和以前的行为不变，只是换了地方 |
| c5 | 全屏菜单仍去掉栏上已有的项（A07.13 c12）：横屏去掉切换直播间、投屏、画面比例，竖屏全屏去掉切换直播间、投屏；3.x 的九项加 4.x 的画面比例，在面板或栏上一个不少 | D-001 |
| c6 | 刘海和挖孔：面板在右侧时躲开右边的安全区（`SafeArea`），和其他面板一样；控制层在面板开着时不自动隐藏（`player_view.dart:334`） | 规范第 5.3 节 |
| c7 | 字放大到 2 倍：名字和第二行换行，不截断、不溢出；放不下时列表滚动 | A04.1 |
| c8 | 直播间页顶栏的菜单（不在画面上）仍是贴着按钮的小菜单 | 竖屏顶栏的菜单不压画面，样子和首页的“更多”一样；规范第 7 节右上角菜单是小菜单 |

## 同类老样子的清点（`PopupMenuButton`、`showMenu`、`PopupMenuItem`、`showDialog` 配 `AlertDialog`/`SimpleDialog`、不走面板组件的 `showModalBottomSheet`、`DropdownButton`）

在 `apps/pure_live/lib` 和 `packages/*/lib` 里搜（2026-10-09），不走 `live_ui` 组件的：

| 位置 | 是什么 | 结果 |
|---|---|---|
| `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart`（画面上的 `RoomMenuButton`） | 横屏、竖屏全屏的右上角菜单 | 改了（c1～c8） |
| `apps/pure_live/lib/features/iptv/iptv_cards.dart:91`（改之前） | 网络电视节目源卡片的“更多”：Material `showMenu` 和 `PopupMenuItem`（`:96`、`:101`），自己的行 `_MenuRow`（图标 20），右键在指针处弹 | 改了：`live_ui` 的 `AppMenuButton`（行 48、图标 24、字 14、圆角 8，和其他“更多”一样），右键在“更多”按钮处打开同一个菜单 |
| `apps/pure_live/lib/features/backup/log_page.dart:184`（改之前） | 日志页“日志级别”：Material `DropdownButton`，弹的是 Material 的下拉菜单 | 改了：和设置里其他选择行一样，`SettingsLinkRow` 末尾显示当前级别，点开 `live_ui` 的选项对话框（当前项主色加勾） |
| `apps/pure_live/lib/app/desktop/close_dialog.dart:161` | 电脑关闭窗口的对话框：`showDialog` 直接调用，内容是 `Dialog` 加 `DialogButtonsTheme`、`DialogKeys`（A16.1 的设计） | 不改：外观就是应用对话框（`showAppDialog` 也只是 `showDialog`），不是老样子 |
| `apps/pure_live/lib/tv/widgets/tv_dialogs.dart:16` | 电视外壳的对话框 | 不改：电视有自己的设计系统（A17.1） |
| `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart:494` | 画面上本地弹幕的输入行（`showGeneralDialog`） | 不改：是输入框，不是菜单（A08.2、A08.13） |
| `packages/live_ui/lib/src/widgets/app_menu.dart:126`、`stream_menu_button.dart:204`、`adaptive_panel.dart:53`/`:75`/`:85`、`app_dialog.dart:456` | 设计系统自己的小菜单、面板、对话框 | 是组件本身，不改 |
| `apps/pure_live/lib/features/version/update_prompt.dart:201`、`update_download.dart:606` | 新版本、下载更新对话框（`showAppDialog` 里的 `Dialog`，`DialogButtonsTheme`） | 不改：应用对话框 |
| `apps/pure_live/lib/features/about/about_page.dart:59` | “开源许可”打开 Flutter 自带的 `showLicensePage` | 不改，见“留下的问题” |
| `apps/pure_live/lib/shared/links/supported_platforms.dart:37` | `ExpansionTile`（可以展开的列表行） | 不是弹出层，不改 |

## 结果

- c1、c2、c4、c5：`apps/pure_live/lib/features/live_play/buttons/room_menu_panel.dart`（`RoomMenuPanel`、`RoomMenuRow`、`roomMenuRowHeight`、`roomMenuGroupGap`）；`buttons/room_menu_button.dart` 的 `roomMenuItems`（两边共用的行）、`roomMenuOpensPanel`、`RoomMenuButton`（在画面上且有直播间面板时开面板，否则开小菜单）；`layout/room_panel.dart` 的 `RoomPanelKind.menu`；`live_play_page.dart` 的 `_panelOf`（传入栏上已有的项）。
- c3、c6、c7：用现成的 `RoomSidePanel`、`PanelCard`，主题颜色；测试里三套主题算对比度，2 倍字不溢出、最后一行能滚到、点得开。
- 清点：网络电视卡片“更多”（`apps/pure_live/lib/features/iptv/iptv_cards.dart`）、日志级别（`apps/pure_live/lib/features/backup/log_page.dart`）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 横屏全屏：右侧 360 面板；竖屏全屏：底部面板；直播间页顶栏：小菜单 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 全屏和电脑的窗口内全屏：右侧 360 面板（Windows 多“在新窗口打开”）；分栏布局的顶栏：小菜单 |
| 电视 | 不涉及（电视直播间是 A17.4） |
| 苹果平台差异 | 无（iOS 没有投屏，和以前一样） |

## 验证

- 自动测试：见 [record.md](record.md)“测试”。
- 真机：[verify.md](verify.md)；待真机。

## 留下的问题

- 全屏下栏的清晰度、线路、画面比例、画面方向、竖屏全屏画面模式的小菜单（`apps/pure_live/lib/features/live_play/buttons/stream_menu.dart:69`、`:89`，`player/bar_parts.dart:229`、`:267`，`player/player_controls.dart:932`）保持浅色小菜单：用户 2026-10-09 定了“不统一修改成右侧面板”（A07.6 第五版的样子不变），不再开任务。
- “关于 → 开源许可”是 Flutter 自带的许可页（`apps/pure_live/lib/features/about/about_page.dart:59`），是整页不是弹出层，样子是 Material 默认；要换得自己写许可列表页，另开小任务。
- 横屏时面板盖住了右上角的四宫格（和其他面板一样），所以横屏只能用 ✕ 或返回键关，不能再点四宫格关；竖屏全屏可以。
