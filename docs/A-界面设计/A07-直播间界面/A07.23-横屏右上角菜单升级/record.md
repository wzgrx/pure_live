# A07.23 横屏右上角菜单的样子升级，以及同类老样子的菜单和弹出层：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-ab4bcb939ca55e68d`，提交 `[A07.23] …`
- 任务书：[brief.md](brief.md)；设计和清点：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 横屏菜单和横屏面板一致 | 做了 | 选“右侧面板”（README c1），不做画面上的深色菜单：规范第 3 节第 7 条要求全屏时弹窗配色跟主题、不另换一套；菜单里多数项本来就打开右侧面板 |
| 1 看得清 4.5:1 | 做了 | 面板不透明，跟主题；测试里三套主题算名字和图标对卡片的对比度 |
| 1 躲开刘海和控制层 | 做了 | 用 `RoomSidePanel`（右边 `SafeArea`），面板开着时控制层不隐藏（原有的 `player_view.dart:334`） |
| 2 分组、图标和竖屏一致 | 做了 | `roomMenuItems` 两边共用 |
| 2 3.x 各项都在 | 做了 | 栏上已有的（⇄、投屏、横屏的画面比例）不在面板里重复（A07.13 c12，原来就是这样） |
| 2 点按行为不变 | 做了 | 打开面板的项在原处换面板；分享、在平台打开、新窗口先关面板再执行；画面比例在行旁弹小菜单 |
| 3 2 倍字、三套主题 | 做了 | |
| 4 清点 | 做了 | 改了网络电视卡片“更多”、日志级别；其余见 README 清点表和“留下的问题” |
| 5 不出评审页 | 做了 | |

## 根因

- 横屏上栏的四宫格（`apps/pure_live/lib/features/live_play/player/player_controls.dart:401` 的 `RoomMenuButton(onVideo: true)`）和竖屏顶栏的是同一个 `AppMenuButton`：`onVideo` 只把图标改白（改之前 `buttons/room_menu_button.dart:304`），弹出的是给页面用的浅色小菜单（`packages/live_ui/lib/src/widgets/app_menu.dart:88` 的 `showAppMenu`，Material `PopupMenuItem` 行 `:126`、`PopupMenuDivider` `:123`；`anchored_menu.dart:340-346` 的 `surfaceContainerHighest`、圆角 8、宽最多 280），贴着按钮挤在画面右上角。全屏时的其他弹出（A07.6、A07.12、A07.13）早就是右侧 360 全高的直播间面板，只有这个菜单没跟着换，所以在画面上显得是另一套、像旧的桌面右键菜单。
- 网络电视卡片“更多”（改之前 `apps/pure_live/lib/features/iptv/iptv_cards.dart:91`）直接用 Material `showMenu`，没走 `live_ui` 的小菜单；日志级别（改之前 `apps/pure_live/lib/features/backup/log_page.dart:184`）是 Material `DropdownButton`，设置里其他选择行都是“值 + 选项对话框”。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart`：新 `RoomMenuItem`、`roomMenuItems`（小菜单和面板共用的行）、`roomMenuOpensPanel`；`RoomMenuButton` 在画面上且有直播间面板时开面板（再点一次关）。
- `apps/pure_live/lib/features/live_play/buttons/room_menu_panel.dart`（新）：`RoomMenuPanel`、`RoomMenuRow`、`roomMenuRowHeight`（52）、`roomMenuGroupGap`（8）。
- `apps/pure_live/lib/features/live_play/layout/room_panel.dart`：`RoomPanelKind.menu`。
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：`_panelOf` 加菜单面板（横屏、竖屏全屏各传栏上已有的项）。
- `apps/pure_live/lib/features/iptv/iptv_cards.dart`：“更多”换成 `AppMenuButton`，右键在按钮处打开同一个菜单；去掉 `_MenuRow`、`showMenu`。
- `apps/pure_live/lib/features/backup/log_page.dart`：“日志级别”换成 `SettingsLinkRow` + `showAppOptionDialog`。
- 测试：`test/features/live_play/room_menu_panel_test.dart`（新）、`test/features/backup/log_page_test.dart`（新）、`test/features/iptv/iptv_page_test.dart`（扩展）。
- 文档：本文件夹；`docs/tasks.toml` 和生成的文件。

## 新设置、翻译键、门禁基线

- 没有新设置，没有新翻译键（用了已有的 `menu`、各项的名字），没有新 `AppIcons`（用了已有的 `forward`）；门禁基线不变。

## 测试

- 新增 13 个用例，扩展 1 个：
  - `apps/pure_live/test/features/live_play/room_menu_panel_test.dart`（10 个）：
    - 869×400 横屏 × 浅色、深色、纯黑三个：四宫格打开右侧面板（869−360、0、360×400），不是小菜单；标题“菜单”；三组 [定时关闭、房间音量]、[获取直链、分享、在哔哩哔哩打开]、[本地互动体验]；栏上有 ⇄、投屏、画面比例；每行的 3.x 图标、› 只在打开面板的行、行高 ≥52、在面板里；最后一行底边 ≤400（K90 横着不滚动）；名字和图标对卡片 ≥4.5:1；面板是主题的 `surface`；开着 10 秒控制层还在。
    - 2608×1200：同样 360 宽贴右、全高，三组相同。
    - 竖屏：顶栏仍是小菜单（`PopupMenuItem`），八项都在；竖屏全屏开底部面板（宽 393、贴底），三组多了“画面比例 / 默认比例”；再点四宫格关掉。
    - 点按：“定时关闭”在原处（同一个矩形）换成定时关闭面板，✕ 关；返回键先关菜单面板、仍在全屏；房间音量、获取直链、本地互动各开自己的面板；“在哔哩哔哩打开”关面板并打开页面。
    - 竖屏全屏“画面比例”：小菜单在行旁，选“居中裁剪”写进设置并关面板；点外面（Esc）取消时面板留着，第二行变成新比例。
    - 2 倍字 × 869×400、393×852 两个：不溢出，滚到“本地互动体验”点开它的面板。
  - `apps/pure_live/test/features/backup/log_page_test.dart`（新，3 个，三套主题）：没有 `DropdownButton`；行末显示当前级别；点开应用的选项对话框，四个级别都在、当前的带勾；选另一个写进设置、行末跟着变。
  - `apps/pure_live/test/features/iptv/iptv_page_test.dart` 扩展“更多”用例：是应用的小菜单（两行 `PopupMenuItem<IptvCardAction>`）、图标、在按钮下方并和按钮右边对齐；右键照旧打开。
- 原有直播间测试（`test/features/live_play` 全部、`test/accessibility_test.dart`、`test/shared/shared_test.dart`，654 个）不改照样通过：面板的行用和小菜单相同的键 `room-menu-<项>`。
- 门禁：见下一节。

## 门禁

- （运行后填）

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包），逐条见 [verify.md](verify.md)，要点：

1. 横屏全屏点四宫格：右侧面板、三块卡片、六行一屏放下；三套主题都看；倒过来横拿看挖孔那边。
2. 点“定时关闭”等：在原处换成那一项的面板；分享、在哔哩哔哩打开先关面板；返回键先关面板。
3. 定时关闭开着时第二行“N 分钟后暂停”。
4. 系统字体调到最大：换行、不出红黄条、能滑到最后一行。
5. 竖屏全屏：底部面板，“画面比例”的小菜单在行旁，选了关面板；四宫格再点关面板。
6. 竖屏顶栏的菜单照旧是小菜单。
7. 网络电视卡片“更多”、设置 → 日志 →“日志级别”的新样子。
