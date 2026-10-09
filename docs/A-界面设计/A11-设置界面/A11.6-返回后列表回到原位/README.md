# A11.6 从子页面返回后列表回到原来的位置（设置和同类页面）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：界面
- 来源：用户 2026-10-09：“2.设置打开子功能，返回上级以后，设置界面会回到最上面，还需要用户手动继续下滑到原位置，顺便看看还没有这种问题，全部修复”
- 相关：[A11.1 设置总览](../A11.1-设置总览/README.md)（两栏、跨 840 保留打开的页）；[specs/UI.md](../../../specs/UI.md) 第 5.1 节第 5 条（窗口尺寸变化时保留滚动位置）、第 5.3 节“滚动位置”（本任务加的约定）
- 任务书 [brief.md](brief.md)；记录 [record.md](record.md)；真机 [verify.md](verify.md)

## 目标

用户往下翻到某一行，点进下一级页面，再返回：列表停在点之前的地方，不用再往下翻。设置是用户报的地方；其他同类的地方（首页各标签、分区、搜索、观看记录、录制中心、账号、数据、弹幕和屏蔽、本地互动）一起清点，丢位置的一起修。

## 根因

不是路由用错（`AppNavigator.toNamed` 是 `push`，压在上面的页面不拆下面的页），是**手机一栏时设置总览在原地换内容**：

- `features/settings/settings_page.dart`（改之前）：点总览的一行，`_openSection`（`:97`）只 `setState` 把 `_open` 设成那一页（`:104`）；`build` 里 `_open` 不空时整页换成右侧导航器（`:216-217`），总览的 `ListView`（`:320-321`，键是普通的 `ValueKey('settings-overview')`）从树上拆掉。返回走 `_closeSection`（`:129`）把 `_open` 清空，总览重新建一个新的 `ListView`，滚动位置从 0 开始。
- 同一处：搜索结果点“会打开别的页”的一行，`_reveal`（`:112-115`）同样原地换页，结果列表（`:382`）回来也是 0。
- 同一个原因的变体：宽度跨过 840（转屏、分屏改宽度）时两栏和一栏是两棵不同的树，总览也被重建、回到 0；打开的页在 `GlobalKey` 的导航器里，跟着搬家，本来就保留。
- 首页底部标签同样是“原地换内容”：`features/home/home_page.dart:129`、`:147` 只挂当前标签的页，切走的页整个拆掉。关注页的网格早就有 `PageStorageKey`（`favorite_page.dart:472`），切回来能回到原位；热门（`shared/rooms/room_grid.dart:543`）、分区（`features/areas/platform_areas_view.dart:233`、`:259`）、录制中心（`features/recorder/recorder_page.dart:647`）没有，切回来都在最上面。

清点过、不是原因的：路由用 `go`（没有，都是 `push`）；页面换键（打开的页的键只在换一页时变）；`ScrollController` 在 `build` 里建（没有，都在 State 里）；宽屏两栏换掉左栏（左栏一直在）；搜索状态重置（搜索词在 State 里，留着）；`watchSetting` 重建列表（只重建用到的行，列表的键不变）。

## 方案（统一的做法）

- `live_ui` 加一个小组件 `KeepScrollPosition`（`packages/live_ui/lib/src/widgets/scrolling.dart`）：给下面的列表一个 `PageStorageKey`，列表的位置记在**所在路由**的 `PageStorage` 里；列表被拆掉再建（原地换内容、标签切回来、跨分界）时回到记下的位置。同一个路由里的列表用不同的 id；内容换了、应该回到顶部的（另一次搜索）换一个 id。
- 约定（写进 [specs/UI.md](../../../specs/UI.md) 第 5.3 节）：压在上面的新页面不用它（下面的页还在）；**原地换内容或会被拆掉重建的列表**用它。
- 用在：设置总览、设置搜索结果（id 带搜索词）、热门和分区房间的网格（`RoomFeedView`，id 带平台）、分区网格（id 带平台和大类）、录制中心的任务列表。关注页原有的 `PageStorageKey` 是同一个机制，不改。

## 验证

- 自动测试：见 [record.md](record.md)“测试”。
- 真机：见 [verify.md](verify.md)。
