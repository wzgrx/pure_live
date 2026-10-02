# T05h.2 切换直播间面板（竖屏、横屏、全屏一致；原地换台；去掉重复入口）

- 日期：2026-10-02（本地 worktree 任务，只提交到 worktree 分支，没有推送、没有开 PR；按维护者提醒两次合并本地 master：第一次含 T05f.1、T08b.3、T14b.2，第二次含 T01d.1，面板头、提示条、备用底部面板改用 T01d.1 的统一组件）
- 用户原话：问题 06“竖屏点击右上角 切换直播间，弹出的切换直播间的ui不太行，需要重新设计优化”；问题 08“横屏，右上角最左边的切换直播间，和右上角的，最右边的功能图标（点击也有切换直播间的功能），功能重合，还有切换直播间的ui也不行，需要重新设计，还要考虑和竖屏的联系”；GitHub issue #37“感觉旧版那种小的好看看的还多，新版就变了，加个新旧切换开关吧”
- 设计：[docs/T05/T05h/T05h.2/README.md](README.md)（第 1 版；用户已授权“所有决定你选择”，待选 X1～X5 按建议 A 做）
- 审查报告：A-06、A-08（[audit-2026-10-02.md](../../../T15/T15b/audit-2026-10-02.md)）

## 根因

1. **4.0.0 的切换直播间是另一种东西**：`features/live_play/dialogs/room_switcher.dart` 是 70% 高的底部表单加普通 `ListTile`（头像、名字、“平台 · 标题”），没有封面和人数，看不到当前房间，观看记录看不出谁在播，刷新失败不提示；横屏全屏也是这个底部表单，393 高只露两三行，压在画面中间。v3 是靠右的小卡片对话框（`play_other.dart`），竖屏、横屏同一个；4.0.0 换成了表单，issue #37 说的“旧版小的好看看的还多”就是这个。
2. **选中后整页替换**：表单里点一行调 `AppNavigator.offAndToRoomDetail`（`pushReplacement`），退出全屏、新页面先初始化旧页面后释放（用不上保留的播放器）、来源列表丢失。页面里已经有上下滑换台用的 `_switchRoom`（同一个播放器、不建新页），表单没用它。v3 是 `controller.switchRoom` 原地换。
3. **重复入口**：横屏顶栏 `_trailing(switchRoom: true)` 有 ⇄、投屏，下栏有画面比例；右上角四宫格菜单用和竖屏同一份 `roomMenuGroups`，三项又列一遍。竖屏全屏第二行的 ⇄、投屏也一样。

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 先出设计，产出放 `docs/T05/T05h/T05h.2` | ✅ | README（界面清点、v3 样子、问题、改动、按钮表、卡片数表、待选）、`src/gen.py` 和 16 个 `src/*.html`、18 张效果图（v3 竖屏和横屏还原、4.0.0 现状、新设计竖屏网格和列表、来源列表、横屏网格和列表、窄横屏、竖屏全屏、竖屏流三档面板、平板、六种状态、横屏菜单现状和新设计、并排数卡片）、3 张编号图、`page.json`、14 张导出章节图。效果图都看过。评审页在本机 `~/ref/design/compare/U.2m.html`，没有发布成 claude.ai 页面（全部按建议定稿） |
| c1 | 做成 `RoomPanelKind.switchRoom`（`RoomSidePanel`，和录制、弹幕设置同一套） | ✅ | `layout/room_panel.dart` 加 `switchRoom`；面板 `switch_room/room_switch_panel.dart` 用 `RoomSidePanel`，位置全由页面已有的 `_panelLayer` 决定 |
| c1 | 位置：竖屏普通布局从画面下沿升起盖住聊天区；竖屏流三档面板里；竖屏全屏底部 60%；横屏全屏和平板右侧 360 全高 | ✅ | 同录制、弹幕设置面板，测试固定竖屏、竖屏全屏、横屏全屏、平板四种的位置和尺寸 |
| c1 | 头部：标题、刷新（显示上次刷新时间，失败要提示）、关闭 | ✅ | 头部是 `RoomSidePanel` 里 T01d.1 的统一 `PanelHeader`（52 高、标题 17 号）。刷新按钮带时间（“5 分钟前”“刚刚”，没刷新过写“刷新”），每分钟更新；刷新中转圈写“正在刷新”、不能再点；失败变红写“刷新失败”，并弹 T01d.1 的统一提示条 `AppToast`“N 个直播间刷新失败，显示的是上次的状态”带“重试”（X5 A）。时间取关注页的 `lastFullRefreshAt`，失败数取 `lastFailed`，由 `app/app.dart` 接上（和以前一样，功能目录不互相引用） |
| c1 | 分段：关注在播（数量）/ 来源列表（从热门、分区、搜索进来时才有）/ 观看记录 / 关注回放 | ✅ | 在播和回放按人数排（v3 `_compareAudience`，用现有的 `AudiencePolicy.rank`）；来源列表是进直播间时带的列表，原样顺序；从关注进来（列表里全是关注的直播间）时不显示（X3 A）。打开时停在：同一页面里上次选的，否则有来源列表时停在来源列表，否则关注在播（X1 A）。见“偏差 1” |
| c1 | 按主播名过滤的搜索框 | ✅ | 头部搜索按钮，点了出现搜索框，按主播名（不分大小写）筛选当前分组；再点收起并清空 |
| c1 | 网格 / 列表两种样式，头部切换，记住（新设置 `roomSwitcherLayout`，默认网格） | ✅ | 按钮图标是切过去的样式（网格时显示列表图标） |
| c1 | 网格照 v3 小卡片：内边距 6、间距 5、按宽度算列数，封面 + 一行主播名，左上“直播中”和人数；一屏不少于 v3 | ✅ | `logic/room_switch.dart`：`roomSwitchColumns`（最小卡宽 168，525 宽以内和 v3 的 `resolveRoomHistoryColumns` 完全一样，更宽时多列，X2 A）、`roomSwitchCardHeight`（v3 的规则：16:9 封面 + 名字行，两列时压到两行放得下，最低 96）。封面左上“直播中”（红）和人数（按人数类型的图标），标题放在封面下沿的渐变上，下面一行主播名；列表里有多个平台时名字右边写平台名（X4 A）。卡片数对照见下表 |
| c1 | 列表每行：16:9 封面 112×63、主播名、标题一行、“平台 · 分区” | ✅ | 行高 75；封面左上同样的标记 |
| c1 | 未开播压暗写“未开播 · 上次看 X 前” | ✅ | 封面压 54% 黑；网格写在封面左上，列表写在第三行。观看记录里关注的直播间用关注的最新状态（关注会被刷新），保留观看时间 |
| c1 | 最上面固定一行“正在观看”（当前房间，不可点） | ✅ | 36 高，主播名 · 标题，跟着房间信息更新；各分组不再列出当前房间 |
| c1 | 空状态和出错状态 | ✅ | 每个分组一句话（关注在播另有“看看观看记录，或者点刷新”）；筛选没结果“没有名字包含“X”的主播”；读关注或观看记录出错“列表读取失败”加“重试” |
| c2 | 点一行调 `_switchRoom(room)`：同一个播放器、保持全屏和方向、播放列表换成所选分组 | ✅ | 页面新加 `_pickRoom(room, group)`：所选分组（去掉已下线平台）变成竖屏全屏上下滑的列表，再调 `_switchRoom`。平台已下线时提示“该平台已下线”不换 |
| c2 | 长按弹出卡片菜单（和房间卡片同一个对话框） | ✅ | `shared/rooms/room_menu.dart` 的 `showRoomMenu` |
| c2 | 去掉旧的 `dialogs/room_switcher.dart` 底部表单 | ✅ | 删除；没有房间页面的地方（理论上不会出现）同一个面板放进 T01d.1 的 `showAdaptivePanel` 底部面板（60% 高），选中后照旧整页替换 |
| c3 | 保留横屏顶栏和竖屏全屏的 ⇄；`roomMenuGroups` 加参数，画面上的菜单不再列出栏上已有的项；竖屏普通布局的菜单不变 | ✅ | `roomMenuGroups(onBars:)`；`menuEntriesOnBars(landscape:, cast:)`：横屏去掉切换直播间、投屏、画面比例；竖屏全屏去掉切换直播间、投屏，**画面比例留着**（竖屏全屏下栏只有“竖屏全屏画面模式”，没有画面比例按钮，去掉就没入口了）。投屏只在支持投屏的平台（Android）算栏上已有 |
| c3 | 三个入口（竖屏菜单、全屏 ⇄、未开播或失败状态的按钮）都打开这个面板 | ✅ | 都调 `showRoomSwitchPanel` |
| 验收 | 三种布局里是同一个面板、同样的分组和样式；网格一屏的卡片数不少于 v3；网格和列表能切换并记住；换台不退出全屏、不重新进页面、复用播放器；菜单里没有和栏上重复的项 | ✅ | 见“测试” |

### 一屏能看到几张卡片（`python3 docs/T05/T05h/T05h.2/src/gen.py --counts`，测试里用同样的公式）

| 布局 | v3 对话框 | v3 完整/过半 | 新面板 | 新网格 完整/过半 | 新列表 |
|---|---|---|---|---|---|
| 竖屏手机 393×852 | 280×720，1 列 | 3/3 | 393×523，2 列 | 4/6 | 5 行 |
| 竖屏全屏 | 280×720，1 列 | 3/3 | 393×495，2 列 | 4/6 | 4 行 |
| 横屏手机 852×393 | 418×377，2 列 | 4/4 | 360×393，2 列 | 4/4 | 3 行 |
| 窄横屏 740×360 | 362×344，2 列 | 4/4 | 360×360，2 列 | 4/4 | 3 行 |
| 平板横屏 1280×800 | 620×720，2 列 | 4/6 | 360×720，2 列 | 8/10 | 7 行 |
| 平板竖屏 800×1280 | 380×720，2 列 | 8/8 | 800×734，4 列 | 16/16 | 8 行 |

## 偏差和原因

1. **分组打开时停在来源列表**：任务单把关注在播写在第一个，分组顺序照写；但从热门、分区、搜索进来时打开停在来源列表（X1 A），因为用户正在翻那个列表。
2. **列数在宽处多于 v3**：v3 最多 2 列；照抄的话竖着拿的平板（宽 800）一屏只有 4 张完整卡片，少于 v3 的 8 张，违反“不少于 v3”。手机上（525 宽以内）和 v3 完全一样。
3. **竖屏全屏菜单留着“画面比例”**：见 c3 说明。
4. **卡片底下只写主播名**：v3 底栏是标题加主播名两行（36 高）；按任务单“封面 + 一行主播名”，标题移到封面下沿，卡片矮 10，同样高度能多放。
5. **改了任务单可改目录以外的几个文件**（都是必须的）：`packages/live_store`（新设置，和 T05f.1 加设置的做法一样）、`apps/pure_live/lib/app/app.dart`（刷新的接线，原来就在这里）、`assets/translations`、`tools/gate/ui_baseline.json`（删掉旧表单里的一个 `Icons.live_tv_rounded`，`live_play` 的直接图标数从 8 降到 7，门禁要求跟着降）。

## 改了哪些文件

- 设计：`docs/T05/T05h/T05h.2`（README、`src/gen.py` 和 `src/*.html`、效果图、`page.json`、`page/` 章节图）
- 新：`apps/pure_live/lib/features/live_play/logic/room_switch.dart`（分组、列数、卡高、筛选、时间）、`switch_room/room_switch_panel.dart`（面板、`showRoomSwitchPanel`、`FollowsRefresher`）、`switch_room/room_switch_tiles.dart`（卡片、列表行）
- 删：`apps/pure_live/lib/features/live_play/dialogs/room_switcher.dart`
- 改：`live_play_page.dart`（`_panelOf` 加面板、`_pickRoom`、来源列表和分组记忆）、`layout/room_panel.dart`、`buttons/room_menu_button.dart`（`onBars`、`menuEntriesOnBars`、菜单项打开面板）、`player/player_controls.dart`（`_roomActions` 加 `landscape` 参数传 `onBars`；⇄ 打开面板）、`player/player_status.dart`（状态里的按钮打开面板）、`app/app.dart`
- `packages/live_store/lib/src/settings/settings.dart`（`roomSwitcherLayout`）、`packages/live_ui/lib/src/icons/app_icons.dart`（6 个图标，只加）
- `apps/pure_live/assets/translations/zh.json`、`en.json`；`tools/gate/ui_baseline.json`
- 测试：新 `test/features/live_play/room_switch_test.dart`；改 `test/features/live_play/room_extras_test.dart`、`packages/live_store/test/stores_test.dart`

## 新设置和翻译键

- 新设置 `roomSwitcherLayout`（`player` 分区，`grid` / `list`，默认 `grid`；面板头部的按钮改它，不在设置页里）。3.x 键名都没动。
- 新翻译键 26 个：`room_switch_on_air`、`room_switch_source`、`room_switch_replays`、`room_switch_watching`、`room_switch_search`、`room_switch_show_grid`、`room_switch_show_list`、`room_switch_live`、`room_switch_replay`、`room_switch_offline`、`room_switch_offline_watched`、`room_switch_watched`、`room_switch_ago_now`、`room_switch_ago_minutes`、`room_switch_ago_hours`、`room_switch_ago_days`、`room_switch_refreshing`、`room_switch_refresh_failed`、`room_switch_refresh_failed_count`、`room_switch_empty_on_air`、`room_switch_empty_on_air_hint`、`room_switch_empty_source`、`room_switch_empty_history`、`room_switch_empty_replays`、`room_switch_no_match`、`room_switch_load_failed`。
- 删掉只给旧表单用的 2 个：`live_play_switch_empty`、`live_play_switch_replays`。

## 测试

- 新写 17 个（`room_switch_test.dart`）：逻辑 6 个（各手机宽度下列数和 v3 一样、宽处多列；六种布局一屏卡片数不少于 v3（按 v3 代码的公式算）；卡高规则；分组去掉当前房间、按人数排、观看记录取关注状态、来源列表从关注进来时不显示、打开时的分组；筛选和时间；菜单去重）；面板 11 个（竖屏从画面下沿升起、列数、正在观看、数量；横屏全屏 ⇄ 打开在右侧 360 全高、点一个原地换台：同一个播放器、同一个页面、还在全屏；竖屏全屏底部 60%、换台后上下滑列表换成所选分组；平板右侧 360；状态里的按钮打开面板；网格和列表切换并记住；来源列表、分组切换和记忆；未开播压暗和长按卡片菜单；筛选、空状态、没有结果；刷新时间、转圈、失败变红和提示；横屏和竖屏全屏菜单去重、竖屏普通菜单不变）。
- 改 3 个：`room_extras_test.dart` 删掉旧表单的刷新测试（新测试 c8 代替），“应用接上刷新”改查 `RoomSwitchPanel.follows`；`live_play_layouts_test.dart` 的“各平台的房间菜单”原来断言全屏菜单和竖屏一样，按 c12 改成全屏菜单少了栏上已有的项（横屏少画面比例，竖着的全屏不少）；`live_store` 加 1 个新设置的测试。
- 跑过：`apps/pure_live`、`packages/live_store`、`packages/live_ui` 的 `dart format --set-exit-if-changed`、`flutter analyze` / `dart analyze`（都无问题）；第二次合并 master（含 T01d.1）后重跑：`live_store` 46 个、`live_ui` 148 个、`apps/pure_live` 全部 797 个都通过；`python3 tools/gate/check_ui_structure.py` 通过。
- 没改 Android 原生代码和资源，没构建 APK。没往手机安装。

## 要在 K90 上看的地方

1. 竖屏进一个直播间，点右上角四宫格 → 切换直播间：面板从画面下沿升起盖住信息行和聊天区，画面照常播；默认两列小卡片，有封面、左上红色“直播中”和人数，封面下沿一行标题，下面主播名；最上面一行“正在观看 · 主播 · 标题”。
2. 点头部的列表图标：变成每行一个 16:9 小封面加三行字；关掉再打开（或换个直播间再打开）还是列表；再点切回网格。
3. 点刷新：转圈写“正在刷新”，完了写“刚刚”；过几分钟再打开写“X 分钟前”。断网时刷新：按钮变红写“刷新失败”，底部提示条说几个直播间刷新失败。
4. 横过手机进全屏，点顶栏 ⇄：面板在右侧（宽 360、全高），一屏 2×2 四张；点一个直播间：面板关上，画面原地换台，**还在全屏**，没有退出再进的闪动。
5. 横屏全屏点右上角四宫格：菜单里没有“切换直播间”“投屏”“画面比例”，只剩定时关闭、房间音量、获取直链、分享、在平台打开、本地互动。竖屏普通布局的菜单不变。
6. 竖屏流进竖屏全屏，点第二行 ⇄：面板占底部 60%；选一个后，打开“竖屏全屏上下滑换台”时上下滑按刚才那个分组走。
7. 从热门或分区点进直播间再打开面板：多一个“来源列表 N”，打开就停在它；从关注点进来的没有。
8. 观看记录分组：没开播的卡片封面压暗，左上写“未开播 · 上次看 2 小时前”；长按任一卡片弹出房间卡片的对话框（分享、标签、关注）。
9. 搜索：点放大镜输入主播名的一部分，只剩匹配的；输不存在的名字显示“没有名字包含……的主播”。

## 需要维护者决定的

- 没有必须决定的。X1～X5 都按建议 A 做了（见设计 README），如果想要“打开时总在关注在播”（X1 B）或“v3 那样最多两列”（X2 B）各是一两行的改动。
- 设计的评审页没有发布到 claude.ai（本机 `~/ref/design/compare/U.2m.html`），需要给用户看时按 PROCESS 第 4 步发布。

## 可能和别的任务冲突的文件

- `player/player_controls.dart`：`_roomActions` 加了必填参数 `landscape`（T08b.3 刚给它加了 `time`，已合并 master 后在其上改）。
- `live_play_page.dart`：`_panelOf`、`dispose`、`initState` 各加了几行；T05g.2、T05f.2 会碰同一个文件。
- `buttons/room_menu_button.dart`：`roomMenuGroups` 改成按组过滤（结果不变时等价）。
- `packages/live_ui/lib/src/icons/app_icons.dart`：末尾加了一节（T01d.1 也可能在 live_ui 里加东西，只是相邻追加）。
- `packages/live_store/lib/src/settings/settings.dart`、翻译文件：只加行。
