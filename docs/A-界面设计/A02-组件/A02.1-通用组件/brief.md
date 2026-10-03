# A02.1 通用组件开发：任务书

> 本任务的开发已经合并（合并提交 `349a4fce5`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及看出问题时的修补。下面保留开工时的全部要求（原任务单，旧编号 U01），按任务书模板 v2 重排，“现状”一节是合并后读代码写的。真机发现问题时，照本任务书的范围和规则修，或开新任务（标题写“接 A02.1”）。

## 背景

- 来源：界面重构计划书 [specs/UI.md](../../../specs/UI.md) 第 8.5 节（通用组件）；设计 [README.md](README.md)（第 1 版，“需要你选的”C1～C4 由维护者按 D-003 选 A）；整理前的跨任务清单（标签 `docs-archive-2026-10-02` 的 `docs/ui/TASKS.md` 第 7 节）写给本任务的条目。
- 现象（开工前）：状态页只有加载、空、出错三种，离线、受限和出错一个样，原始英文报错直接显示，圆圈 15% 透明加 1 秒弹跳；同类东西各页自己画（三种芯片、两套二维码、两种开关、三种行标题、两种 ›、刷新失败的 `MaterialBanner`）；3.x 的设置构建函数（组标题主色 65%、说明提示色 75% 一行、卡片 15% 透明、最宽 960）还留在网络电视、账号等几页；标题全部居中的说法和 3.x 实际不符。
- 规模：大；分组：组件；依赖：A02.3、A02.2、A03.1 之后；能否和别的任务同时做：组件组，依次做（A02.3 → A02.2 → A02.1 → A04.1）。
- 出设计：不用（照已确认的设计和本任务书）。
- 已经做过的：A02.3（小菜单，`66492c34c`）、A02.2（对话框、面板、提示条，`276925183`）、A03.1（下拉刷新组件 `AppRefreshView`，`42638dc3c`）。

## 目标和验收

1. 照 [README.md](README.md) 的 c1～c21 逐条实现：状态页、头像、计数、二维码、标签和芯片、列表行和设置行、滚动和列表外壳、回到顶部按钮点击区域、键盘焦点框。
2. 第 7 节写给本任务的条目都做：标题居中（按 D-011 照 3.x 实际运行的样子）、设置行说明对比度（约 3.4:1 → ≥4.5:1）、开关打开时滑块和底色同为主色看不出滑块、各页 Esc 返回（`CallbackShortcuts` + `FocusScope`，做成共用组件）。下拉刷新头和上拉加载（c19）已由 A03.1 做，这里只检查各列表都用了那个组件。
3. 设置里的卡片预览改用 `LiveRoomCard`（`features/settings/appearance_pages.dart`）。
4. 各页面改用统一组件，删掉重复实现；`tools/gate/ui_baseline.json` 降到实际值；直接写的颜色和图标只减不增。
5. 测试：组件的每种状态（默认、悬停、焦点、按下、禁用、进行中）、深浅主题、对比度。
6. 真机：见下表（[verify.md](verify.md)）。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-03）：

- 状态页：`packages/live_ui/lib/src/widgets/status_view.dart`：`AppStatusType`（`:18`，加载、空、出错、受限、离线）、`AppStatusView`（`:64`）、按窗口判断横排（`:236`）、`showStatusDetails`（`:352`）、`StatusSkeleton`（`:463`）；列表的出错统一走 `apps/pure_live/lib/shared/rooms/room_grid.dart:290` 的 `loadErrorStatus`。
- 横幅 `status_banner.dart:30`；头像 `avatar.dart:12`；计数 `count_button.dart:15`（`CounterControl`）、`:218`（`CountButton`）；二维码 `qr_code_widget.dart:21`、`:99`；标签 `tab_label.dart:12`、`:79`；芯片 `app_chip.dart:14`、`:38`；设置行 `settings_row.dart:118`～`:1095`；回到顶部 `jump_buttons.dart:13`；焦点框 `focus_ring.dart:12`；Esc 返回 `escape_back.dart:10`；主题 `live_theme.dart`（`centredPageTitle` `:24`、`FocusFrame` `:31`、标签叠层和芯片主题 `:277-288`、按钮焦点框 `:289-319`、列表行 `:324-337`）。
- 用在页面：`AppStatusView` 22 个文件 46 处、`SettingsGroup` 16 个文件、`TabLabel` 6 个文件、`AppChip` 7 个文件、`ScrollJumpButtons` 和 `StatusBanner` 在 `shared/rooms/room_grid.dart`（`:197-209`、`:230`）、`EscapeBack` 在搜索、网页搜索、观看记录；应用里没有 `RefreshIndicator`、`activeThumbColor`、原生 `PopupMenuButton`。
- 门禁：`tools/gate/ui_baseline.json` 的 `raw_styles` 为空（`features/`、`tv/` 0 处）。
- 留下的：`tools/ui/mock/kit/kit.css:125` 的 `.toast` 仍只有浅色深底（任务范围外，没做）。

## 3.x 基线

- `lib/common/widgets/app_status_view.dart`（532 行）、`empty_view.dart`、`common_avatar.dart`、`count_button.dart`、`qr_code_widget.dart`、`scrollable_tab_bar.dart`、`widget_extensions.dart`（455 行）、`section_listtile.dart`；`lib/common/base/base_page_view.dart`、`base_page_view_extension.dart`、`desktop_components.dart`；`lib/plugins/global.dart`（下拉刷新头）；逐项的样子和行号见 [README.md](README.md)“3.x 的样子”（例如状态页 `:407-413` 加载不显示标题、`:426-445` 圆圈和弹跳）。
- 标题：3.x 主题 `lib/common/style/theme.dart:119` 写了 `centerTitle: true`，但 `lib/main.dart:162-169` 用 `AppBarTheme(surfaceTintColor: …)` 整个替换了标题栏样式，从没生效；只有录制中心、关注、分区、热门、观看记录、工具箱 6 页自己写了居中（D-011）。
- 要保留：状态出现的时机、“加载样式”、头像尺寸和缓存、计数长按连加、二维码画法、一级标签的样子和滚轮横滚、设置页结构（组标题 + 卡片 + 行、左边图标）、窄屏换行、回到顶部 / 底部、电脑翻页栏、滚动手感（设计 c1）；3.x 的设置键名和含义（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3、5.4、7、8 节。
3. 本文件夹的 `README.md`（已确认，“需要你选的”按 A）、[record.md](record.md)、[record-2.md](record-2.md)；[A02 子分类页](../README.md)。

## 范围

- 可以改：`packages/live_ui`；各功能目录（只替换成统一组件）；本文件夹的 `record.md`、`record-2.md`。其他目录不改（当时 `features/live_play/` 由 A07.13、A07.12 在改，没动）。
- 不能改：其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；`tools/ui/`（效果图工具，范围外）。

## 方案和阶段

当时按一个大阶段做完（本地工作区，三次合并 master）。真机修补时按下表定位：

| 部分 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 状态 | c2～c8：一个状态组件（五种类型、三种场合）、骨架、出错写人话和“详情”、按钮 C1、圆圈实色不弹跳、横屏左图右文、页顶横幅 | `status_view.dart`、`status_banner.dart`、`shared/rooms/room_grid.dart`、各列表页 | `components_test.dart` 的 AppStatusView 和 StatusBanner 组通过 |
| 小组件 | c9～c13：头像、计数、二维码、标签、芯片 | `avatar.dart`、`count_button.dart`、`qr_code_widget.dart`、`tab_label.dart`、`app_chip.dart`、`live_theme.dart` | 对应测试组通过 |
| 行 | c14～c18：开关一种、设置配色、一个行组件、选择 ⌄ 跳转 ›、阅读内容 720 | `settings_row.dart`、`settings_tiles.dart`、各设置页 | 设置行和列表行测试通过；没有 3.x 构建函数 |
| 外壳和状态 | c19（检查）、c20 回到顶部 48、c21 悬停焦点按下禁用进行中；第 7 节：标题、Esc | `jump_buttons.dart`、`focus_ring.dart`、`escape_back.dart`、`live_theme.dart` | 焦点框只在键盘时；标题位置照 D-011 |

## 测试

- 已有：`packages/live_ui/test/components_test.dart`（26 条，见 [record-2.md](record-2.md)“测试”）；改了 `status_view_test`、`theme_test`、`widgets_test`、`room_card_test`、`settings_row_test`；`apps/pure_live` 按新设计改了热门、翻页栏、搜索、扫码登录、分区、观看记录的断言，新增 8 处“主要按钮写明动作”的断言。
- 真机修补时：先写一个能复现问题的 widget 测试（改之前会失败），再改；竖屏、横屏、宽屏至少各一个布局测试；定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 首页、设置、录制中心、搜索各页看标题 | 录制中心、观看记录（标题和条数一起）、工具箱、首页三个底部页标题居中；设置、录制设置、设备同步、网络电视、账号等靠左（原任务单写“各页标题居中”，按 D-011 改成这样） |
| 2. 浅色主题下设置 → 视频 | 每行说明深灰、清楚、最多两行；行标题不加粗；选择行“原画 ⌄”，跳转行 › |
| 3. 设置里任意开关打开；“后台播放”这类保存时有转圈的行 | 蓝底白滑块看得见；转圈在开关左边、开关变灰 |

完整步骤见 [verify.md](verify.md)（12 条）。

## 风险和注意

- `live_theme.dart` 的 `ListTile`、芯片、按钮主题全应用生效，直播间里的列表行、芯片、按钮也会跟着变（长按弹幕面板、切换直播间、录制面板）。
- `scope.dart`、`live_ui.dart` 多个任务常加词和导出；`settings_row.dart`、`count_button.dart`、`status_view.dart`、`app_menu.dart` 和 A02.2、A07.12 有交叉。
- 状态页按窗口判断（不是约束）是有意的：搜索页把状态放在 `SliverFillRemaining` 里，`LayoutBuilder` 会报错（全量测试里 30 多条因此失败过）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A02.1` 或本机工作区；提交信息以 `[A02.1]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在记录末尾写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；根因；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的；需要维护者决定的；可能冲突的文件。
