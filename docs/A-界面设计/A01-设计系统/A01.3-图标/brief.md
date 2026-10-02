# A01.3 图标：任务书（第 3 阶段“其余页面”）

## 背景

- 来源：界面重构计划书 [specs/UI.md](../../../specs/UI.md) 第 8.4 节（按用途命名、每个用途照 3.x 在该位置的图标）；第 2 阶段 2026-10-01 随 A07.1 做完；各页面任务开发时又往 `AppIcons` 加了自己的用途。登记表 `next`：直播间以外页面的图标收尾。
- 现象：
  - 直播间右上角菜单（Windows、Linux）里“在平台打开”和“在新窗口播放此直播间”挨着，用同一个 ↗ 图标（`AppIcons.openExternal` 和 `AppIcons.newWindow` 都是 `Icons.open_in_new_rounded`），而 A16.1 c12 定的是 `add_to_photos`（和首页菜单的“新建独立播放窗口”同一个）。
  - `AppIcons` 不是唯一入口：`live_ui` 的组件自己写了 22 处 `Icons.*`，翻页栏 `shared/rooms/paging.dart` 写了 3 处；而 `AppIcons.previousPage`、`nextPage` 等 15 个名字没人用。
  - 设置里“备份与恢复”和“WebDAV”是同一个云图标；投屏、换台、节目单、界面模式是同一个电视图标。
- 为什么现在做：第二档；规范第 3 节第 6 条“一个动作一个图标”；以后真要做 C-2（换图标库）时，`AppIcons` 必须是唯一入口。
- 已经做过的：A07.1（`AppIcons`、`DanmakuIcon`）；A07.7（`switchLine`、`banned`、`statusUnknown`）；A16.1（`newPlayerWindow`、窗口按钮）；各页面任务让 `features/`、`tv/` 的直接写的图标降到 0（门禁基线 `tools/gate/ui_baseline.json` 的 `raw_styles` 为空）。

## 目标和验收

1. `packages/live_ui/lib/src/widgets/` 里不再直接写 `Icons.*`、`Remix.*`：都改成 `AppIcons` 的用途名（字形不变）。
2. `apps/pure_live/lib/shared/` 里不再直接写 `Icons.*`、`Remix.*`（翻页栏 3 处），字形照 3.x 不变。
3. `AppIcons.newWindow` 的字形改成 `Icons.add_to_photos_outlined`（A16.1 c12），对照表测试跟着改。
4. 没人用的 15 个名字：接上（例如 `toBottom` 给回到底部按钮、`previousPage`/`nextPage` 给翻页栏、`increase`/`decrease` 给计数）或删掉，最后 `apps/pure_live/lib` 和 `packages/live_ui/lib` 里每个名字至少有一处使用。
5. 列出“同一字形多个用途、意思不同”的组（至少下面“现状”里的 4 组），每组给出保留或替换的建议和理由，写进 `README.md` 的“待选和决定”，交维护者定；维护者定了的才改字形。
6. 门禁扫描范围扩到 `shared/`（或在测试里扫），锁住第 1、2 条。
7. 门禁通过；`live_ui`、`apps/pure_live` 全部测试通过。

## 现状（读代码得出，写文件:行）

- `packages/live_ui/lib/src/icons/app_icons.dart`：483 个 `static const IconData`，346 个字形；按区域分节（首页外壳 `:13`、直播间 `:84` 起、录制中心 `:312`、切换直播间 `:1523`）。对照表测试 `packages/live_ui/test/design_system_test.dart:18` 起（`newWindow` 在 `:50` 写的是 `Icons.open_in_new_rounded`）。
- `live_ui` 组件里直接写的图标（22 处）：`count_button.dart:191`（`remove_rounded`）、`:198`（`add_rounded`）；`jump_buttons.dart:118`（`arrow_upward/downward_rounded`）；`app_chip.dart:28`（`check_rounded`）；`status_banner.dart:82`（`info_outline_rounded`）、`:88`（`warning_amber_rounded`）、`:94`（`error_outline_rounded`）、`:171`（`close_rounded`）、`:177`（`chevron_right_rounded`）；`status_view.dart:139-142`（`live_tv`、`error_outline`、`lock_outline`、`wifi_off`）、`:324`（`login_rounded`、`refresh_rounded`）；`qr_code_widget.dart:155`（`refresh_rounded`）、`:162`（`check_circle_outline_rounded`）、`:166`（`error_outline_rounded`）；`settings_row.dart:598`（`expand_more`/`chevron_right`）、`:1144`（`search_rounded`）、`:1150`（`close_rounded`）；`avatar.dart:59`（`person_rounded`）；`color_picker.dart:395`（`check_rounded`）。已有同用途名字的：`AppIcons.decrease`/`increase`（`:1348`、`:1351`）、`toTop`/`toBottom`（`:567`、`:570`）、`selected`（`:175`）、`close`（`:262`）、`info`（`:525`）、`warning`（`:336`）。
- `shared/` 里：`apps/pure_live/lib/shared/rooms/paging.dart:188`（`Icons.arrow_back_ios_new_rounded`，12）、`:204`（`Icons.arrow_forward_ios_rounded`，12）、`:237`（`Icons.arrow_drop_down_rounded`，18）；`AppIcons.previousPage`/`nextPage`（`app_icons.dart:584`、`:587`）是 `chevron_left/right_rounded`，没人用。
- 门禁：`tools/gate/check_ui_structure.py` 的 `scan` 只看 `lib/features/**` 和 `lib/tv/**`。
- `newWindow`：`app_icons.dart:289`；用在 `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart:300`（文字还是 `open_room_in_new_window`“在新窗口播放此直播间”，A16.1 记录说新文字 `open_in_new_window`“在新窗口打开”已加好、由直播间改）；`newPlayerWindow`（`:68`，`Icons.add_to_photos_outlined`）首页菜单在用。
- 没人用的名字（只在 `app_icons.dart` 里出现，括号是只在测试里出现）：`chatListStyle`（`:219`）、`pausedOverlay`（`:257`）、`recordQueued`（`:301`）、`recordReconnecting`（`:304`）、`recordFailed`（`:310`）、`miniPlay`（`:486`，测试）、`miniPause`（`:489`，测试）、`loginRequired`（`:537`）、`hiddenNote`（`:564`）、`toBottom`（`:570`）、`previousPage`（`:584`）、`nextPage`（`:587`）、`allPlatforms`（`:950`）、`decrease`（`:1348`，测试）、`increase`（`:1351`，测试）。
- 意思不同却同一字形的组：`Icons.open_in_new_rounded` = `openExternal`（`:184`）、`newWindow`（`:289`）、`enterRoom`（`:327`）；`Remix.tv_2_line` = `cast`（`:116`）、`changeRoom`（`:634`）、`guide`（`:679`）、`uiMode`（`:846`）；`Remix.cloud_line` = `backup`（`:65`）、`webDav`（`:755`）、`settingsBackup`（`:811`）；`Remix.heart_3_line` = `homeFavorites`（`:16`）、`followHeart`（`:96`）、`unfollow`（`:283`）、`settingsPreferPlatform`（`:1211`）。

## 3.x 基线

- 3.x 每个位置的图标见各页面任务 README（例如首页菜单 `lib/common/widgets/menu_button.dart:35-61`：设置 `Remix.settings_5_line`、关于 `Remix.information_line`、历史记录 `Remix.history_line`、备份与恢复 `Remix.cloud_line`、Windows 的“新建独立播放窗口”`Icons.add_to_photos_outlined`）。
- 翻页栏 `lib/common/base/desktop_components.dart:117`（刷新 `Icons.refresh_rounded` 16）、`:127`（上一页 `arrow_back_ios_new_rounded` 12）、`:145`（下一页 `arrow_forward_ios_rounded` 12）、`:278`（每页条数 `arrow_drop_down_rounded` 18）——这次只把它们收进 `AppIcons`，字形不变。
- 3.x 的“备份与恢复”和 WebDAV 都用 `Remix.cloud_line`（A12.3 记下的“图标和 WebDav 重复”）。
- 要保留：每个位置的字形照 3.x（规范第 3 节第 2 条）；只有维护者确认过的才换。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 7 节）；`docs/specs/UI.md` 第 3 节、第 8.4 节、第 10 节。
3. 本文件夹的 `README.md`；[子分类页](../README.md)；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md` 的 c12；`docs/A-界面设计/A12-账号和数据界面/A12.3-云账号停用说明/README.md`（备份图标）；`packages/live_ui/lib/src/icons/app_icons.dart`、`packages/live_ui/test/design_system_test.dart`、`tools/gate/check_ui_structure.py`。

## 范围

- 可以改：`packages/live_ui/lib/src/icons/`、`packages/live_ui/lib/src/widgets/`（只换图标的写法）、`packages/live_ui/test/`；`apps/pure_live/lib/shared/rooms/paging.dart`；`tools/gate/check_ui_structure.py` 和 `tools/gate/ui_baseline.json`（扩到 `shared/`）；本文件夹的 `README.md`（“待选和决定”）和 `record.md`。
- 不能改：`apps/pure_live/lib/features/`（直播间菜单的文字和顺序归直播间任务；页面已经 0 处）；`apps/pure_live/lib/tv/` 和 `TvIcons`（A17）；任何字形（第 3 条和维护者定了的除外）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

这是登记表的第 3 阶段，分两步提交：

| 步 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 3a | `live_ui` 组件 22 处和翻页栏 3 处改用 `AppIcons`（缺的名字补上，例如 `pagerPrevious`，或把 `previousPage`/`nextPage` 改成 3.x 的字形后接上）；`newWindow` 换 `add_to_photos_outlined`；没人用的名字接上或删掉；门禁扫 `shared/` | `live_ui/lib/src/icons/app_icons.dart`、`live_ui/lib/src/widgets/*`、`shared/rooms/paging.dart`、`tools/gate/*`、`design_system_test.dart` | 第 1～4、6 条做到；对照表测试覆盖改动的名字；字形除 `newWindow` 外不变 |
| 3b | 同一字形多个用途的组逐个看，写建议到 `README.md`；维护者定了的改字形 | `README.md`；定了的才改 `app_icons.dart` | 第 5 条做到 |

## 测试

- `design_system_test.dart` 的对照表加上新接上的名字（`toBottom`、翻页栏、计数、芯片的勾、状态页四个图标、横幅三个图标），`newWindow` 改成 `Icons.add_to_photos_outlined`。
- 加一条：`app_icons.dart` 里的每个名字在 `lib/` 里至少用一次（扫源码），防止再出现没人用的名字。
- 门禁扫 `shared/` 后跑 `python3 tools/gate/check_ui_structure.py`，基线不变（0）。
- 不访问真实平台；定时器至少 1 秒。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置、热门、关注、录制中心、计数（弹幕设置的顶部留白）、二维码登录、横幅（开移动流量） | 图标和改之前一样 |
| 2. Windows 上进直播间，右上角菜单 | “在平台打开”是 ↗，“在新窗口……”是“添加到相册”样的叠放图标 |
| 3. Windows 上热门翻页栏 | 上一页、下一页、每页条数的箭头和改之前一样 |

## 风险和注意

- `AppIcons` 的名字是各页面任务一直在加的，开工前合并最新 master；删名字前全仓库搜一遍（含 `tv/`）。
- 字形换了会改变用户看到的东西，除了 `newWindow`（A16.1 已确认）都要维护者确认。
- 直播间菜单的文字（`open_room_in_new_window` → `open_in_new_window`）不在本任务范围，写进报告交直播间任务。
- `live_ui` 的组件文件 A02 的任务常改，按文件分批提交。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A01.3` 或本机工作区；提交信息以 `[A01.3]` 开头（英文）；不推 master。
- 提交前：`packages/live_ui`、`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；根目录 `python3 tools/gate/check_ui_structure.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；新加、改字形、删掉的 `AppIcons` 名字；门禁改动；测试数量；改了哪些文件；同一字形多用途各组的建议；要在真机上看的；需要维护者决定的；可能冲突的文件；交给直播间任务的（菜单文字）。
