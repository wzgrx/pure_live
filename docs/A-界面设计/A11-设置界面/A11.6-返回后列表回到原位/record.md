# A11.6 从子页面返回后列表回到原来的位置（设置和同类页面）：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-a1968e94fd6e6499a`（从 master `d70f973ff` 开始），提交 `[A11.6] …`
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)

## 根因

不是路由的问题：`AppNavigator.toNamed`（`apps/pure_live/lib/routes/app_navigator.dart:58-59`）是 GoRouter 的 `push`，设置分页里打开子页是嵌套导航器的 `Navigator.push`（`settings_tiles.dart` 的 `SettingLinkTile`、`openSettingsSubpage`），压在上面的页面都不拆下面的页，下面的列表连同位置一直在。

丢位置的是**原地换内容**的地方（行号是改之前的 `d70f973ff`）：

1. 设置总览（用户报的）：`apps/pure_live/lib/features/settings/settings_page.dart`
   - 点总览的一行：`_openSection`（`:97`）只 `setState(() => _open = section)`（`:104`）；
   - `build`：手机一栏时 `_open` 不空就 `page = _contentNavigator(section, twoPane: false)`（`:216-217`），总览的 `Scaffold` 和 `ListView`（`:320-321`，键是普通的 `ValueKey('settings-overview')`，不是 `PageStorageKey`）从树上拆掉；
   - 返回：`_closeSection`（`:129`）清空 `_open`，总览重新建一个 `ListView`，滚动位置是新的 0。
2. 设置搜索结果：`_reveal`（`:112-115`）同样原地换成结果所在的页；结果列表（`:382`）回来也是 0。
3. 跨 840：两栏（`:177-215`）和一栏是两棵不同的树，总览重建、回到 0；打开的页在 `GlobalKey` 的导航器（`_content`，`:48`）里跟着搬家，本来就保留。
4. 首页标签（同类问题，切回来时）：`apps/pure_live/lib/features/home/home_page.dart:129`、`:147` 只挂当前标签的页，切走的页整个拆掉、回来重建。关注页的网格原来就有 `PageStorageKey`（`features/favorite/favorite_page.dart:472`），切回来在原位；热门和分区房间（`shared/rooms/room_grid.dart:543`）、分区（`features/areas/platform_areas_view.dart:233`、`:259`）、录制中心（`features/recorder/recorder_page.dart:647`）没有，切回来都在最上面。

清点过、不是原因的：路由用 `go`（没有，`offAllNamed` 只在启动和导入时用）；页面换键（`settings-content-<页>-<次数>` 只在打开另一页时变）；`ScrollController` 在 `build` 里建（没有）；宽屏的左栏（一直挂着）；搜索状态（搜索词在 State 里）；`watchSetting` 重建（只重建行，列表的键不变）。

## 清点表

“下一级”指压在上面的页面（新路由或嵌套导航器）；“原地”指同一页换内容。

| 页面 | 怎么到下一级 | 改之前返回后 | 原因 | 处理 |
|---|---|---|---|---|
| 设置总览（手机一栏）→ 任一分页（外观、视频、弹幕、缓存…） | 原地换 | **丢**，回到顶部 | 总览列表被拆掉重建，没有 `PageStorageKey` | 修：`KeepScrollPosition('settings-overview')` |
| 设置搜索结果 → 结果所在的页 | 原地换 | **丢** | 同上 | 修：`KeepScrollPosition('settings-search:<搜索词>')`，换词从顶上开始 |
| 设置总览 → 路由页（网络电视、录制、本地互动、备份、日志） | `push` | 保留 | 总览一直在 | 不改；测试守着（备份） |
| 设置分页 → 子页，两层（视频 → 竖屏直播适配 / 观看数据；外观 → 房间卡片、字体、加载动画；播放内核 → 驱动选项；弹幕 → 弹幕字体） | 嵌套导航器 `push` | 保留 | 下面的页一直在 | 不改；测试：总览 → 视频 → 竖屏 → 返回 → 返回 |
| 宽屏两栏（1280×800、横屏手机 852×393） | 左栏一直在；右栏嵌套导航器 `push` | 保留 | — | 不改；测试两种宽度 |
| 宽屏两栏左栏点另一页 | 右栏换一页 | 新页从顶上开始 | 换了一页，不是返回 | 不改（应该如此） |
| 跨 840（转屏、分屏改宽度） | 布局整个换 | 总览**丢**；打开的页保留 | 总览重建；导航器有 `GlobalKey` | 修：同第一行；测试两条 |
| 设置 → 弹幕 → 弹幕屏蔽（路由）、弹幕字体 | `push` | 保留 | | 不改；测试（屏蔽） |
| 弹幕屏蔽页 | 只有对话框 | 不涉及 | | — |
| 本地互动设置页 | 只有对话框（没有下一级页） | 不涉及 | | — |
| 录制设置页（A10.2） | 只有对话框 | 不涉及 | | — |
| 账号 → 各平台页 | `push` | 保留 | | 不改；测试 |
| 数据：缓存与数据管理、本地配置预览（设置分页，同上）；备份与恢复 → WebDAV、设备同步、日志、我的 | `push` | 保留 | | 不改（读代码） |
| 首页“关注”→ 直播间 | `push` | 保留 | | 不改；测试 |
| 首页“关注”切到别的标签再回来 | 原地换标签 | 保留 | 原来就有 `PageStorageKey` | 不改 |
| 首页“热门”→ 直播间 | `push` | 保留 | | 测试 |
| 首页“热门”切到别的标签再回来 | 原地换标签 | **丢** | 页面重建，网格没有 `PageStorageKey` | 修：`RoomFeedView` 的网格 `KeepScrollPosition('popular:<平台>')`（平台标签之间各记各的） |
| 首页“分区”→ 分区房间 → 直播间 | `push` | 两层都保留 | | 测试 |
| 首页“分区”切到别的标签再回来 | 原地换标签 | **丢** | 同上 | 修：分区网格 `KeepScrollPosition('areas:<平台>:<大类>')` |
| 搜索结果 → 直播间 | `push` | 保留 | | 不改；测试 |
| 观看记录 → 直播间 | `push` | 保留：像素位置不变；看过的房间回来时排到“今天”最前，它原来上面的卡片顺延一格 | 记录在后台更新，列表不重建 | 不改；测试（含回来时记录更新） |
| 首页“录制中心”→ 录制设置、直播间 | `push` | 保留 | | 测试 |
| 首页“录制中心”切到别的标签再回来 | 原地换标签 | **丢** | 同上 | 修：任务列表 `KeepScrollPosition('recorder-list')`（筛选之间和以前一样共用一个位置） |
| 电视：设置面板、关注、热门、分区、历史各栏 | 设置面板没有下一级页；进直播间是 `push` | 保留（读代码） | | 不改，没加测试 |
| WebDAV 文件夹：进子文件夹，再点路径回上一级 | 原地换列表并重新向服务器要 | 回到顶部 | 是重新拉的一份列表，没有返回栈，不是“返回” | 不改，记在这里 |
| 直播间里的本地互动面板 → 样式 | 面板原地换 | 没细查 | 直播间的面板和弹层这次不碰（A07.23 在改） | 不改 |

## 共用的做法

- `packages/live_ui/lib/src/widgets/scrolling.dart`：`KeepScrollPosition({required String id, required Widget child})`，自己的键是 `PageStorageKey<String>('scroll:<id>')`。下面的 `Scrollable` 停下来时把位置写进所在路由的 `PageStorage`，列表被拆掉再建时从那里读回（Flutter 自带的机制，控制器的 `keepScrollOffset` 默认开；`keepScrollOffset: false` 的列表不记）。
- 约定写进 [specs/UI.md](../../../specs/UI.md) 第 5.3 节“滚动位置”：压在上面的新页面不用管；原地换内容或会被拆掉重建的列表包一层；内容换了应该从顶上看的换 id 或跳到 0（翻页原来就 `jumpTo(0)`）。
- 没加新包；没有新的翻译键；门禁基线不变。

## 改了哪些文件

- `packages/live_ui/lib/src/widgets/scrolling.dart`：`KeepScrollPosition`。
- `apps/pure_live/lib/features/settings/settings_page.dart`：总览、搜索结果包一层（只加一层，原来的 `ValueKey` 不变，测试照样找得到）。
- `apps/pure_live/lib/shared/rooms/room_grid.dart`：`RoomFeedView` 的网格（热门、分区房间）。
- `apps/pure_live/lib/features/areas/platform_areas_view.dart`：`_AreaPages` 加 `storageId`（平台和大类），手机和电脑两处网格。
- `apps/pure_live/lib/features/recorder/recorder_page.dart`：任务列表。
- 测试：见下一节；新的共用测试帮手 `apps/pure_live/test/scroll_support.dart`（`scrollPositionOf`、`scrollDown`）。
- 文档：本文件夹；`docs/tasks.toml`；`docs/specs/UI.md` 第 5.3 节；[A11 README](../README.md)（内部怎么工作、测试表）；`tools/docs/settings_audit.py` 重新生成的 J01.2 `settings.md`（只是 `platform_areas_view.dart` 的行号变了）。

## 测试

新增 17 个用例；改之前失败的标“改前失败”（把改过的源文件换回 `d70f973ff` 的跑过），其余是守护（改之前就保留，防以后改坏）：

- `apps/pure_live/test/features/settings/settings_scroll_position_test.dart`（新，9 个）：
  - 手机 400×800：总览 → 网络与代理 → 左上角返回，再 → 弹幕 → 系统返回，总览都在原位（改前失败：750 → 0）；
  - 两层：总览 → 视频 → 竖屏直播适配 → 返回 → 返回，视频页和总览各在原位（改前失败：总览 461 → 0）；
  - 总览 → 备份（路由）→ 返回（守护）；
  - 弹幕页 → 弹幕屏蔽（路由）→ 返回，弹幕页在原位（守护）；
  - 搜索“弹幕”，翻到“弹幕屏蔽”在顶上 → 点它进视频页 → 返回，结果在原位；换搜索词从 0 开始（改前失败：361 → 0）；
  - 宽屏 1280×800、横屏手机 852×393：总览不动；右栏视频页 → 竖屏 → 返回在原位；→ 备份 → 返回两栏都不动（守护，两个）；
  - 跨 840：打开的页在原位（守护）；总览在原位，来回各一次（改前失败：280 → 0）。
- `popular_test.dart`“A11.6”：热门往下翻 → 直播间 → 返回在原位；切到“关注”再切回“热门”在原位（改前失败：681 → 0）。
- `areas_test.dart`“A11.6”：分区网格往下翻 → 分区房间往下翻 → 直播间 → 返回、返回，两层都在原位；切到“热门”再回“分区”在原位（改前失败：380 → 0）。
- `recorder_centre_test.dart`“A11.6”：12 个任务往下翻 → 上面压一页再关 → 原位；切走标签再回来在原位（改前失败：580 → 0）。
- `favorite_test.dart`、`history_page_test.dart`（回来时这个房间重新记进观看记录）、`search_test.dart`、`account_page_test.dart` 各一个“A11.6”：返回后在原位（守护）。
- `packages/live_ui/test/scrolling_test.dart`“A11.6”：拆掉再建回到原位、换 id 从 0 开始（组件是新的，改前没法编译）。

## 门禁

- 2026-10-09 本机 `bash tools/gate/gate.sh --all`（提交 `8a3381264`，四个 `[A11.6]` 提交的内容）：`gate: passed (all, 14 members)`。第一次跑时新测试里有 7 条分析提示（多余的 `unawaited`、和默认值一样的参数）、`KeepScrollPosition` 注释里一处引用，改掉后通过。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包），逐条见 [verify.md](verify.md)，要点：

1. 竖屏：设置往下翻到“数据”组 → 点“缓存与数据管理”→ 返回（左上角、手势返回各一次）：设置停在“数据”组，不回顶上。
2. 设置 → 视频 → 往下翻 → 竖屏直播适配 → 返回 → 返回：视频页、设置各在原位。
3. 设置搜索“弹幕”，往下翻，点一个会跳页的结果 → 返回：结果在原位。
4. 横屏拿手机（两栏）：左栏往下翻、右栏打开的页往下翻，开子页再返回，两栏都不动；竖屏 ↔ 横屏转一次，设置的位置不变。
5. 首页热门、分区、录制中心各往下翻，切到别的标签再切回来：在原位；关注本来就保留，确认没变。
6. 热门、分区房间、关注、搜索结果、观看记录各往下翻 → 进直播间 → 返回：在原位；在直播间里横屏全屏再退出、返回，看位置是否还对（按像素保留，列数变了会有偏差，记下）。
