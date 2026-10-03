# A02.3 贴着按钮的小菜单：按实测高度定位、从按钮方向展开（横屏清晰度和线路菜单）：任务书

> 本任务的开发已经合并（开发提交 `39b570ee6`，合并提交 `66492c34c`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及看出问题时的修补。下面保留开工时的全部要求（原任务单，旧编号 B03），按任务书模板 v2 重排，“现状”一节是合并后读代码写的。

## 背景

- 来源：用户问题 03：“手机横屏的时候，点击画质和线路弹出的UI动画不行，是从上面然后显示的，不整齐，应该是从下到上”；全面审查 A-03（横屏手机清晰度、线路菜单从上往下展开，位置对不齐）、B-7（直播间各弹窗不统一），见 [V03.1](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)。
- 现象：横屏全屏点下栏“原画 ⌄”“线路1 ⌄”，菜单先在按钮上方远处出现一条线再往下长到按钮；7 档时菜单压住按钮外框 11 个点；菜单和看得见的按钮隔 12。
- 规模：中；分组：组件；依赖：无；能否和别的任务同时做：改 `packages/live_ui` 的菜单；和 A02.2 **不要同时开**（A02.2 在它之后）。
- 出设计：不用（照已确认的设计和本任务书）：菜单的样子见 A02.2（小菜单）和 A07.6。

## 目标和验收

1. `packages/live_ui` 的 `showSmallMenu`（`src/widgets/stream_menu_button.dart`）和 `showAppMenu`（`src/widgets/app_menu.dart`）不再用 Flutter 的 `showMenu`，改成自己的 `PopupRoute`：`CustomSingleChildLayout` 按**实测高度**定方向（按钮上方放得下且偏好向上时向上：`y = 按钮顶 − 4 − 菜单高度`；否则向下：`y = 按钮底 + 4`）；水平方向贴按钮、靠屏幕边的一侧对齐；最大高度限制为所选一侧的空间，长列表在菜单里滚动，不压住按钮和底栏。
2. 动画：淡入 + 从按钮那一侧展开（向上时从下往上），约 150 毫秒；系统要求减少动态效果时不做动画。
3. 保留：Esc、返回键关闭，方向键和回车选择，当前项主色加勾，说明行、标题行、危险项（红）。
4. 所有用到这两个函数的地方（清晰度、线路、画面比例、竖屏全屏画面模式、首页和其他页面的菜单）都自动受益；逐个检查位置是否正确。
5. 验收：横屏手机底栏点清晰度和线路，菜单贴着按钮从下往上展开，整齐，不越过屏幕，选项多时可滚动；竖屏和平板照旧正确。
6. 测试：横屏 852×393、竖屏 393×852、平板 1280×800 下菜单的位置（上方放得下 / 放不下）、动画方向、长列表滚动、键盘操作。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-03）：

- `packages/live_ui/lib/src/widgets/anchored_menu.dart`：`anchoredMenuGap`（`:15`）、`anchoredMenuMargin`（`:18`）、时长（`:22`、`:25`）、`showAnchoredMenu`（`:47`，`still` 读减少动态效果 `:62`）、路由 `closedLoop`（`:89`）、尺寸变化关掉（`:124-129`）、最大高度（`:178`）、方向（`:192-209`）、展开动画 `_MenuUnfold` 和裁剪 `_UnfoldClipper`（`:221` 起、`:264` 起）。
- `stream_menu_button.dart`：`StreamMenuButton`（`:24`，外框键 `_outline` `:80`）、`showSmallMenu`（`:174`）；`app_menu.dart`：`AppMenuEntry`（`:11`）、`appMenuGap`（`:67`）、`showAppMenu`（`:88`）、`AppMenuButton`（`:177`）。
- 调用处：`apps/pure_live/lib/features/live_play/buttons/stream_menu.dart`、`player/bar_parts.dart`（`preferAbove`）、首页菜单、搜索排序、备份、WebDAV、录制中心、多画面、翻页栏每页条数（`shared/rooms/paging.dart:219`）。
- 之后的改动：A07.12 加了 `AppMenuEntry.description`、`showAppMenu(title:)`、`AppMenuButton.onMenu`、`showSmallMenu(footer:)`（`menu_additions_test.dart`）；A02.1 加了 `AppMenuEntry.switchValue`、`AppMenuButton.enabled`/`buttonKey`/`show()`。

## 3.x 基线

- 3.x 用 Flutter 的 `PopupMenuButton`：清晰度、线路 `lib/modules/live_play/widgets/resolution_selector/resolution_selector.dart:24-80`（表面容器最高色、圆角 8、`offset: Offset(0, 5)`）；首页 `lib/common/widgets/menu_button.dart:14-84`、`common_appbar_actions.dart:13-68`；搜索排序 `lib/modules/search/search_page.dart:261-280`。都从按钮往下长，3.x 的横屏下栏菜单同样有“从上往下”的问题。
- 要保留：换画质和线路不重建播放器、以最后一次选择为准（[specs/UI.md](../../../specs/UI.md) 附录 A 第 9 条）；返回链（第 7 条）；菜单行的样子（A07.6）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 7 节、第 8.6 节。
3. 本文件夹的 `README.md`、[record.md](record.md)；`docs/A-界面设计/A02-组件/A02.2-弹窗组件/README.md`（小菜单）、`docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md`；审查报告 A-03、B-7。

## 范围

- 可以改：`packages/live_ui`；调用处只在需要时小改（`features/live_play/buttons/`、`player/bar_parts.dart`）。当时调用处都没改。
- 不能改：其他目录；菜单的样子（颜色、圆角、行高、字号）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

一个阶段做完：

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 自己的路由按实测高度定位；c2 展开动画；c3 保留键盘和样子；c4 逐个检查调用处 | `anchored_menu.dart`（新）、`stream_menu_button.dart`、`app_menu.dart`、`small_menu_test.dart`（新）、`live_play_popups_test.dart`（加断言） | 12 条新测试通过（改之前 8 条失败）；全部测试通过 |

## 测试

- 已有：`packages/live_ui/test/small_menu_test.dart`（12 条：横屏 7 档向上和滚动、3 档向上和右对齐、展开方向和淡入、减少动态效果、长列表当前项可见、标题行和说明行按实测高度、转屏关闭、`showAppMenu` 横屏向上并滚动、竖屏向下和左对齐、方向键和回车、返回键和 Esc、平板上下两种）；`apps/pure_live/test/features/live_play/live_play_popups_test.dart` 横屏一条“菜单底 = 外框顶 − 4、不出屏幕”。
- 修补时：先写能复现的测试；横屏、竖屏、平板各一个；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 横屏全屏点“原画”“线路1” | 从下往上展开、紧贴按钮 |
| 2. 竖屏信息行的清晰度菜单 | 照旧向下展开 |

完整步骤见 [verify.md](verify.md)（7 条）。

## 风险和注意

- `app_menu.dart`、`stream_menu_button.dart`、`anchored_menu.dart`：A02.2、A02.1、A07.12 都会改到小菜单，应在本任务合并后再开（已按此顺序做）。
- 展开用裁剪而不是改排版尺寸：方向判断不受动画影响；裁剪四周留 16 给阴影。
- 从触摸事件里推的路由第一帧动画时间是 0（A03.2 的 `animateRelease` 讲的同一件事），150 毫秒的展开里看不出来，不用处理。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A02.3` 或本机工作区；提交信息以 `[A02.3]` 开头（英文）；不推 master。
- 提交前：`packages/live_ui`、`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 末尾写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；根因（附实测数字）；测试数量（改之前失败几条）；改了哪些文件；要在真机上看的；需要维护者决定的；可能冲突的文件。
