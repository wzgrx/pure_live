# A01.3 图标：设计（照 3.x 每个位置的图标，没有单独出图）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机，阶段 3/3：设计 ✓、直播间要用的部分 ✓、其余页面 ✓）
- 范围：`AppIcons`：3.x 每个位置用的图标（Remix、Material、`CustomIcons`、弹幕 SVG）按用途命名，页面只写用途；`DanmakuIcon`、`CustomIcons`、`PlatformLogos` 的打包；同一个图标在两处表示不同意思的地方提出替换。
- 旧编号：U.1b、T01b.1（见 [MAPPING.md](../../../MAPPING.md)）
- 对应：[specs/UI.md](../../../specs/UI.md) 第 8.4 节（图标）、第 10 节（门禁）、第 14 节 C-2；[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 0 节（3.x 用了 193 种 Remix、182 种 Material 和几个 `CustomIcons`）；各页面任务的 README 里写的 3.x 图标原名
- 评审页：无。原则就是“每个位置照 3.x 的图标”（规范第 3 节第 2 条），不需要出图；要换的个别图标在提出它的页面任务里确认（例如 A16.1 c12、A07.7 的“换线路”）
- 依赖：Z02.1（搬目录，完成）；样板 [A07.1](../../A07-直播间界面/A07.1-竖屏普通布局/README.md)、[A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md)
- 任务书：[brief.md](brief.md)（第 3 阶段“其余页面”）

## 界面清点表

没有单独的界面。按图标的来源列，状态写现在做到哪。

| 编号 | 图标组 | 用在哪 | 形态 | 状态 |
|---|---|---|---|---|
| A01.3-01 | `AppIcons`（`packages/live_ui/lib/src/icons/app_icons.dart`）：485 个用途名、350 个字形 | 全部页面和 `live_ui` 组件（门禁让 `features/`、`shared/`、`tv/` 和 `live_ui` 组件只能用它，每个名字至少用一处） | — | 完成（第 3 阶段 2026-10-08：`shared/`、`live_ui` 组件 0 处） |
| A01.3-02 | `DanmakuIcon`（3.x `danmu_open/close/setting.svg`） | 直播间下栏、全屏、小窗弹幕开关 | 画面上（带阴影） | 完成（A07.1） |
| A01.3-03 | `CustomIcons`（3.x 图标字体，13 个字形） | 搜索、小窗、投屏、热门、弹幕 | — | 完成（A01.1，随包打包） |
| A01.3-04 | `PlatformLogos`（35 个平台 + 应用标志） | 卡片、平台列表、账号 | — | 完成（A01.1；不认识的 id 给应用标志） |
| A01.3-05 | `RecordGlyph`（录制按钮的圆环和方块） | 直播间、录制中心、通知 | 画面上、页面上 | 完成（A07.1 起，A10.3 重画） |
| A01.3-06 | `TvIcons` | 电视外壳 | 电视 | 归 A17.1 |

## 3.x 的样子和问题

- 样子：3.x 没有统一入口，每个页面直接写 `Remix.*`、`Icons.*`、`CustomIcons.*`，弹幕开关是 SVG 图片（`assets/images/video/danmu_*.svg`）；`lib/common/widgets/custom_icons.dart`（61 行）定义字体里的 13 个字形；平台标志在 `lib/core/sites.dart` 的 `logoForId`。各位置用哪个图标见各页面任务 README 的“3.x 的样子”。
- 问题：
  - P1 没有统一入口：换图标库、统一一个用途的图标要改几十个文件；重构前从零写的页面（界面重构之前）大多换成了别的 Material 图标，和 3.x 对不上（[inventory/V3_UI.md](../../../inventory/V3_UI.md) 第 0 节“v4 现在”）。
  - P2 `logoForId` 对不认识的平台 id 抛异常（`core/sites.dart:213`），已下线平台的旧关注会让卡片菜单出错（A01.1 已修）。
  - P3 同一个图标在两处表示不同意思（规范 8.4“修 v3”），例如 3.x 的“备份与恢复”和 WebDAV 都是 `Remix.cloud_line`（A12.3 记下）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 规范第 8.4 节（2026-10-01） | 按用途命名、每个用途对应 3.x 在该位置的图标；C-2（全换 Material Symbols Rounded）作为候选 | 随计划书确认；C-2 待定（先保留 3.x 图标） |

## 对比页（按章节导出）

无。

## 单张图

无。

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | `AppIcons` 按用途命名，页面只写用途（`AppIcons.roomMenu`），一个用途一个图标；换库只改 `app_icons.dart` | P1 |
| c2 | 保留 | 每个用途的字形照 3.x 在那个位置用的图标（`design_system_test.dart:18` 起的对照表锁住） | P1 |
| c3 | 修改 | 门禁：`features/`、`tv/` 不直接写 `Icons.*`、`Remix.*`（`tools/gate/check_ui_structure.py` 第 2 条） | P1 |
| c4 | 修改 | 不认识的平台 id 给应用标志 | P2 |
| c5 | 修改 | 同一图标两种意思的，在提出它的任务里换（已定的：A16.1 c12 直播间菜单“在新窗口打开”用 `add_to_photos`；A07.7 加“换线路”`alt_route`、封禁 `block`、状态未知 `help_outline`） | P3 |

## 按钮的作用和用法

无（图标本身没有操作）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 同一套 `AppIcons` |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同上；桌面标题栏的窗口按钮图标也在 `AppIcons`（`:926` 起，A16.1） |
| 电视 | `TvIcons`（同样按用途命名，A17.1）；和手机共用的用途从 `AppIcons` 取 |
| 苹果平台差异 | 无（不换 SF Symbols） |

## 待选和决定

- C-2（全部换 Material Symbols Rounded）：待定，先保留 3.x 图标；`AppIcons` 已按用途命名，以后换只改一个文件。
- 同一图标两种意思的几组（第 3 阶段 2026-10-08 的建议；字形没有改，维护者按 D-003 定了再改 `app_icons.dart` 和对照表测试）：

| 组 | 现在谁用 | 建议 | 理由 |
|---|---|---|---|
| G1 `Icons.open_in_new_rounded` | `openExternal`（直播间菜单“在平台打开”）、`enterRoom`（录制中心卡片、多画面格子“进入直播间”）；`newWindow` 已按 A16.1 c12 改成 `add_to_photos_outlined` | A：保留 | 剩下两个不在同一个菜单里出现；↗ 两处都是“离开这里去看那个直播间”，3.x 也是这个字形 |
| G2 `Remix.tv_2_line` | `cast`（投屏）、`changeRoom`（多画面“换台”）、`guide`（网络电视节目单）、`uiMode`（设置“界面模式”） | A：`cast` 保留（3.x 的投屏）；`guide` 改成 `iptvGuide` 的 `Icons.assignment_outlined`（同一个“节目单”一个图标）；`changeRoom` 改成 `switchRoom` 的 `Icons.swap_horiz_outlined`（同一个“换直播间”）；`uiMode` 改成 `Remix.device_line`（手机或电视） | 规范第 3 节第 6 条“一个意思一个图标”；改的三处都有现成的同义图标，换过去后同义的地方一致 |
| G3 `Remix.cloud_line` | `backup`（首页菜单“备份与恢复”）、`settingsBackup`（设置“备份与恢复”）、`webDav`（备份页、账号页的 WebDAV） | A：`backup`、`settingsBackup` 保留（同一个意思，3.x 的字形）；`webDav` 改成 `Remix.upload_cloud_2_line` | A12.3 记下的“图标和 WebDAV 重复”；WebDAV 是“传到自己的网盘”，带箭头的云能和“备份与恢复”分开，又仍是云 |
| G4 `Remix.heart_3_line` | `homeFavorites`（首页“关注”）、`followHeart`（直播间详情“关注”）、`unfollow`（关注按钮菜单“取消关注”）、`settingsPreferPlatform`（设置“首先打开的平台”） | A：前两个保留（同一个“关注”）；`unfollow` 改成 `Remix.dislike_line`（和 `unfollowArea` 一致）；`settingsPreferPlatform` 改成 `Remix.star_line` | “取消关注”用空心心看起来像“关注”；“首先打开的平台”和关注无关 |

  G2～G4 改的是直播间（`unfollow`）、网络电视、多画面、设置和备份页上的图标，属于看得见的改动；定了以后只改 `app_icons.dart` 的字形和 `design_system_test.dart` 的对照表，页面不用动。

## 实现和验证（开发后补）

- 第 1 阶段“设计”：即规范第 8.4 节。
- 第 2 阶段“直播间要用的部分”（2026-10-01，随 A07.1，[A07.1 记录](../../A07-直播间界面/A07.1-竖屏普通布局/record.md)）：新建 `AppIcons`（按用途命名，每个用途对应 3.x 在该位置用的图标，`CustomIcons.float_window` 0xe806 已对照字体核对）、`DanmakuIcon`（新依赖 `flutter_svg` 2.3.0，阴影用一份下移 1 像素的副本）。`live_play` 里直接写的颜色和图标 115 → 28；剩下的 28 处在后来的 A07.6、A07.12 换掉。之后各页面任务往 `AppIcons` 里加自己的用途（A07.7 的 `switchLine`、`banned`、`statusUnknown` 等，A09～A16 各节），现在 483 个名、346 个字形（Remix 275 个名、Material 206 个、`CustomIcons` 2 个）。
- 第 3 阶段“其余页面”（2026-10-08，[记录](record.md)）：`live_ui` 组件 22 处、翻页栏 3 处改用 `AppIcons`（字形不变）；`newWindow` 换成 `add_to_photos_outlined`；没人用的名字接上或删掉；门禁扩到 `shared/` 和 `live_ui` 组件，并检查每个名字至少用一处；上面四组的建议。下面是开工前（2026-10-03）读代码的清单：
  - `live_ui` 自己的组件 22 处直接写 `Icons.*`（清单见[子分类页](../README.md)已知问题）。
  - `apps/pure_live/lib/shared/rooms/paging.dart:188`（上一页 `arrow_back_ios_new_rounded`）、`:204`（下一页 `arrow_forward_ios_rounded`）、`:237`（每页条数的 `arrow_drop_down_rounded`）：3.x 的翻页栏也是这三个（`lib/common/base/desktop_components.dart:127`、`:145`、`:278`），而 `AppIcons.previousPage`/`nextPage`（`app_icons.dart:584`、`:587`）写的是 `chevron_left/right` 且没人用。
  - `AppIcons.newWindow`（`app_icons.dart:289`）仍是 `Icons.open_in_new_rounded`，和上一行“在平台打开”`openExternal`（`:184`）同一个图标（直播间菜单 `features/live_play/buttons/room_menu_button.dart:295-300`）；A16.1 c12 定的是 `add_to_photos`（`AppIcons.newPlayerWindow`，`:68`，首页菜单已用）。
  - 没人用的名字 15 个：`chatListStyle`（`:219`）、`pausedOverlay`（`:257`）、`recordQueued`（`:301`）、`recordReconnecting`（`:304`）、`recordFailed`（`:310`）、`miniPlay`（`:486`，只有测试）、`miniPause`（`:489`，只有测试）、`loginRequired`（`:537`）、`hiddenNote`（`:564`）、`toBottom`（`:570`）、`previousPage`（`:584`）、`nextPage`（`:587`）、`allPlatforms`（`:950`）、`decrease`（`:1348`，只有测试）、`increase`（`:1351`，只有测试）。
  - 同一字形多个用途的有 77 组；意思明显不同的几组：`Icons.open_in_new_rounded`（`openExternal`、`newWindow`、`enterRoom`）；`Remix.tv_2_line`（`cast` `:116`、`changeRoom` `:634`、`guide` `:679`、`uiMode` `:846`）；`Remix.cloud_line`（`backup` `:65`、`webDav` `:755`、`settingsBackup` `:811`；A12.3 的说明页用了 `backupFiles` 的 `save_3_line` 区分）；`Remix.heart_3_line`（`homeFavorites`、`followHeart`、`unfollow`、`settingsPreferPlatform`）。
- 验证：`packages/live_ui/test/design_system_test.dart`（`AppIcons` 对照表，含第 3 阶段接上的名字）、`widgets_test.dart`（平台标志、图标字体）；门禁 `python3 tools/gate/check_ui_structure.py`（第 2 条扩到 `shared/` 和 `live_ui` 组件，第 4 条每个名字至少用一处）和它的测试 `tools/gate/tests/test_check_ui_structure.py`。真机照[任务书](brief.md)“真机验证”看。
