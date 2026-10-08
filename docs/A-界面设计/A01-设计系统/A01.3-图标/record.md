# A01.3 图标：记录（第 3 阶段“其余页面”）

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区（从 master `ce7640a5b` 开始），代码提交 `cf5988255`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)
- 同时在做的：A03.3（直播间拖动手感）、A04.1（尺寸和字号适配）。本任务没有改 `features/live_play/`；`live_ui` 组件文件和 A04.1 可能都改到（见最后）。

## 逐条对照（任务书“目标和验收”）

| 条 | 做了没有 | 说明 |
|---|---|---|
| 1 `live_ui` 组件不直接写图标 | 做了 | 22 处全部换成 `AppIcons`，字形不变：`count_button`（`decrease`、`increase`）、`jump_buttons`（`toTop`、`toBottom`）、`app_chip`、`color_picker`（`selected`）、`status_banner`（`info`、`warning`、新 `bannerError`、`close`、`navigate`）、`status_view`（新 `statusEmpty`、`statusError`，`restricted`、`networkError`、`login`、`retry`）、`qr_code_widget`（新 `qrCardRefresh`、`qrCardScanned`、`qrCardFailed`）、`settings_row`（新 `choiceRow`、`navigate`，新 `searchField`、`clearQuery`）、`avatar`（新 `avatarPlaceholder`） |
| 2 `shared/` 不直接写图标 | 做了 | 翻页栏 `shared/rooms/paging.dart` 三处：`previousPage`、`nextPage` 改成 3.x 翻页栏的字形（`arrow_back_ios_new_rounded`、`arrow_forward_ios_rounded`，原来的 `chevron_*` 没人用过，所以看到的不变），新 `pageSize`（`arrow_drop_down_rounded`） |
| 3 `newWindow` 换字形 | 做了 | `Icons.add_to_photos_outlined`（A16.1 c12），对照表跟着改。直播间菜单的文字 `open_room_in_new_window` → `open_in_new_window` 不在本任务范围，交直播间任务 |
| 4 没人用的名字 | 做了 | 接上 6 个：`toBottom`、`previousPage`、`nextPage`、`decrease`、`increase`（上面），`settingsDanmakuFont`（弹幕字体行显式传它；`FontFamilyTile` 的图标改成必填，应用字体行传 `appFont`）。删掉 10 个：`chatListStyle`、`pausedOverlay`、`recordQueued`、`recordReconnecting`、`recordFailed`、`miniPlay`、`miniPause`（小窗的播放暂停在直播间里，没用它们）、`loginRequired`、`hiddenNote`、`settingsUnmuted`（2026-10-03 之后多出来的）。`allPlatforms` 开工时已经有人用。删之前全仓库搜过（含 `tv/` 和测试），对照表和 A01.4 的“同一意思”测试里去掉了对应几行 |
| 5 同一字形多个用途 | 做了（建议） | 四组的建议写在 [README.md](README.md)“待选和决定”（G1 保留；G2～G4 各改两三个用途到现成的同义图标）。都是看得见的改动，没有改字形，等维护者定 |
| 6 门禁锁住 1、2 | 做了 | `tools/gate/check_ui_structure.py`：第 2 条扫描范围加上 `shared/`（扩的时候有 11 处，都是弹幕预设色和描边，记进基线；A01.2 把它们移进 `live_ui` 后基线回到空）和 `packages/live_ui/lib/src/widgets/`（不许 `Icons.*`、`Remix.*`）；新第 4 条：`AppIcons` 的每个名字在 `apps/pure_live/lib` 或 `packages/*/lib` 里至少用一处 |
| 7 门禁、测试 | 做了 | 见下 |

`AppIcons` 现在 485 个名、350 个字形（加 11、删 10，加上开工后别的任务加的）。

## 改了哪些文件

- `packages/live_ui/lib/src/icons/app_icons.dart`：上面的增删改；新的一节“live_ui's shared components”。
- `packages/live_ui/lib/src/widgets/`：`app_chip`、`avatar`、`color_picker`、`count_button`、`jump_buttons`、`qr_code_widget`、`settings_row`、`status_banner`、`status_view`（只换图标写法和 import）。
- `apps/pure_live/lib/shared/rooms/paging.dart`；`apps/pure_live/lib/features/settings/settings_catalog.dart`、`appearance_pages.dart`（`FontFamilyTile` 的图标）。
- `packages/live_ui/test/design_system_test.dart`：对照表加 26 行（接上和新加的名字），`newWindow` 改成新字形，去掉删掉的名字。
- `tools/gate/check_ui_structure.py`、`tools/gate/tests/test_check_ui_structure.py`（新 4 条测试：`shared/` 算一个区、组件图标按行列出、没人用的名字、失败信息）。

## 测试

- `packages/live_ui`：`flutter test` 全过（对照表一条覆盖改动的名字）。
- `apps/pure_live`：`flutter test` 全过（含 A05.1 的 `accessibility_test.dart`）。
- `python3 tools/gate/check_ui_structure.py` 通过；`python3 -m unittest discover -s tools/gate/tests` 通过。

## 真机（K90）

1. 设置总览、热门、关注、录制中心、计数（弹幕设置的顶部留白 ±）、二维码登录（刷新、已扫码、失效）、提示条（开移动流量）、状态页（断网、空列表）：图标和改之前一样。
2. 设置 → 外观 → 字体、设置 → 弹幕 → 弹幕字体：两行都是字体图标。
3. （Windows，以后）直播间右上角菜单：“在平台打开”是 ↗，“在新窗口……”是叠放的方块；热门翻页栏的箭头和改之前一样。

## 留下的和要维护者定的

- README 里 G2～G4 的建议（定了只改 `app_icons.dart` 和对照表）。
- 直播间菜单“在新窗口打开”的文字（`open_in_new_window`）交直播间任务。
- 可能和并行任务冲突的文件：`packages/live_ui/lib/src/widgets/settings_row.dart`、`status_view.dart`、`count_button.dart`（A04.1 的字号上限和触控区域可能改到）；`app_icons.dart` 新名字加在文件末尾。
