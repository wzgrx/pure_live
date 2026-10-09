# A07.23 横屏右上角菜单的样子升级，以及同类老样子的菜单和弹出层：任务书

## 背景

- 来源：用户 2026-10-09：“1.横屏，右上角点击打开，ui、界面很古老，需要升级优化，顺便看看还没有这种问题，全部修复”。
- 现象：直播间横屏全屏时，点上栏最右的四宫格，弹出的是一个浅色的小菜单，挤在画面右上角，样子像桌面右键菜单，和横屏的其他面板不是一套。
- 为什么现在做：第一档，用户日常用横屏看直播。
- 已经做过的：A07.6（右上角菜单分组、加“画面比例”）、A07.12（菜单里的子弹窗改成直播间面板）、A07.13 c12（全屏菜单去掉栏上已有的项）。

## 目标和验收

1. 横屏全屏点四宫格，打开的菜单和横屏的其他面板一致（右侧面板或画面上的深色菜单，维护者选），在画面上看得清（4.5:1），躲开刘海和控制层。
2. 分组、图标、文字和竖屏菜单相同；3.x 的每一项都在（D-001）；点按的行为不变。
3. 字放大到 2 倍不溢出；浅色、深色、纯黑三套主题都对。
4. 清点全应用里还在用 Material 默认样子的菜单和弹出层（`PopupMenuButton`、`showMenu`、`PopupMenuItem`、`AlertDialog`/`SimpleDialog`、不走面板组件的 `showModalBottomSheet`、`DropdownButton`），小的这次改掉，大的写进 README“留下的问题”（文件:行）。
5. 不出评审页，直接做（D-003）。

## 现状（读代码得出）

- `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart`：`RoomMenuButton`（画面上 `onVideo: true`，`player/player_controls.dart:401`；顶栏 `layout/room_header.dart:106`）都开 `live_ui` 的 `AppMenuButton` 小菜单。
- `packages/live_ui/lib/src/widgets/app_menu.dart:88`（`showAppMenu`，`PopupMenuItem` 行）、`anchored_menu.dart:50`（贴着按钮放、`surfaceContainerHighest`、圆角 8）。
- 横屏的面板：`apps/pure_live/lib/features/live_play/live_play_page.dart` 的 `_panelOf`、`_withSidePanel`（右侧 360 全高），外框 `apps/pure_live/lib/shared/panels/side_panel.dart` 的 `RoomSidePanel`。

## 3.x 基线

- `v3.2.11:lib/modules/live_play/widgets/button/live_play_menu_button.dart:23`：Material `PopupMenuButton`，九项。要保留：九项（打开直播间、切换直播间、投屏、定时关闭、房间音量、获取直链、分享、本地互动、Windows 的在新窗口打开）和各自的行为。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/UI.md`（第 3、5.3、7、8 节）；`docs/DECISIONS.md` 的 D-001、D-003、D-038。
3. A01 设计系统和 `packages/live_ui`（`AppMenu`、面板、`AppIcons`）；A07 的 README（横屏上栏、右上角菜单）。

## 范围

- 可以改：`apps/pure_live/lib/features/live_play/`（`buttons/`、`layout/room_panel.dart`、`live_play_page.dart`）；清点出来的小问题所在的文件；对应测试；翻译文件（需要时）。
- 不能改：设置页的导航和滚动（A11.6 在改）；A07.6 确认过的清晰度、线路小菜单的样子；3.x 的设置键；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 画面上的右上角菜单改成直播间面板；清点；改小的 | 见“范围” | 测试和门禁通过；`record.md` 写好；状态“待真机” |

## 测试

- 新菜单：横屏 869×400 和 2608×1200 一类的尺寸、竖屏；所有 3.x 项都在；点按行为不变；2 倍字不溢出；三套主题。
- 清点里改了的弹出层：各一个测试或扩展原有测试。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)。

## 风险和注意

- 原有测试按 `room-menu-<项>` 找行、按纵坐标排顺序：面板的行沿用同样的键。
- 面板不是路由：返回键由直播间的返回链先关面板（和其他面板一样）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；新工作区先 `bash tools/ffmpeg_kit/fetch.sh android`、`linux`。
- 提交信息以 `[A07.23]` 开头（英文）；不推 master。

## 报告（简洁）

每条做到没有；根因；清点表；测试数量；改了哪些文件；真机上要看的；可能冲突的文件。
