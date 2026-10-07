# I02 热门

首页“热门”（3.x 叫推荐）背后的数据和行为：每个平台一份推荐列表怎么取（按平台选翻页方式）、怎么去重和排序、怎么隐藏不能播放的直播、刷新失败怎么办、切平台和后台回来时什么时候加载；以及热门和分区房间共用的取数类 `RoomFeed`。

## 范围

- 包括：
  - 热门的数据：`apps/pure_live/lib/features/popular/popular_catalog.dart`（`PopularCatalog`：每个平台一个 `RoomFeed`、排序设置变了标旧、可见规则）、`popular_page.dart` 里的加载时机（平台列表、停稳 80 毫秒再加载、700 毫秒后预取下一个、后台回来刷新、首选平台）、`popular_grid.dart` 的平台说明取词（`popularNoticeOf`）。
  - 共用的取数：`apps/pure_live/lib/shared/rooms/room_feed.dart` 的 `RoomFeed`、四种 `RoomSource`（`DirectorySource`、`WindowSource`、`PagedSource`、`SingleSource`）、`popularWindowSizes`、`popularSourceFor`；分区用的 `AreaRoomSource`、`areaRoomLoader`、`areaRoomPageSize` 写在同一个文件，行为归 [I03](../I03-分区/README.md)。
  - 列表共用的规则：`shared/rooms/room_cards.dart` 的 `cannotPlayHere`、`signedInOn`、`AudiencePolicy.rank`（按人数排）、`mixesPlatforms`；`shared/rooms/room_texts.dart` 的 `describeLoadError`、`isLoginError`；`shared/rooms/paging.dart` 的 `phonePageSize`、`usesDesktopPages`、`pageSizesOf`（每页条数的规则）；`app/network.dart` 的 `MobileDataNotice.precheck`（刷新前查断网和移动网络，网络类型本身归 Q04）。
- 不包括（归哪里）：
  - 热门页、平台标签、“全部平台”面板、卡片、网格、骨架、翻页栏、横幅、状态页**长什么样** → [A09.2 热门](../../A-界面设计/A09-浏览界面/A09.2-热门/README.md)、[A09.1 房间卡片](../../A-界面设计/A09-浏览界面/A09.1-房间卡片/README.md)；`shared/rooms/room_grid.dart` 的 `RoomFeedView`（列表外壳：下拉刷新、离底 600 自动加载、电脑页码和 ← →、页脚）是界面，归 A09，这里只管它调 `RoomFeed` 的哪个方法。
  - 卡片对话框、关注和标签（`room_menu.dart`、`room_tags_dialog.dart`）→ A09.1、[I07](../I07-标签和分组/README.md)；分享口令 `share_code.dart` → O03。
  - 各平台的推荐接口（`getRecommendRooms`、目录翻页）→ [E 直播平台](../../E-直播平台/README.md)；“平台显示”（`hotAreasList`）设置页 → [I03](../I03-分区/README.md) 的 `hot_areas_page.dart`；人数口径（实时在线）的设置 → J01、A11.2。
  - 电视的热门 → [X03](../../X-多端客户端/X03-电视/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 标题位置是平台标签（来自“平台显示”，第一次打开停在“首选平台”，列表变了停在原平台、原平台被移除时停在原位置），末尾 ⌄ 打开“全部平台”。平台都关掉时说明并给“平台显示”按钮。
  - 切到一个平台：停稳 80 毫秒后加载（快速滑过的平台不请求），加载完 700 毫秒后预取下一个平台（最后一个预取上一个）。第一次加载显示骨架，之后的列表按人数从高到低（网络电视保持播放列表顺序）。
  - 手机：下拉刷新；离列表底部 600 像素自动加载下一块；页脚“加载更多 / 没有更多数据了 / 加载失败，重试”。电脑（宽 > 680 且不是手机系统）：页码栏（刷新、上一页、页码、下一页、每页条数、跳转）和 ← → 翻页；每页条数默认宽 > 960 时 20、否则 12。
  - 设置“在发现页显示不能播放的直播”关（默认）时隐藏轮播和不能播放的受限房间（需登录、年龄限制只在这个平台没登录时隐藏），列表底部“已隐藏 N 个……”和“显示”。改设置立即生效，不重新请求。
  - 刷新失败：旧列表留着，顶上横幅写原因（网络、太频繁、风控、Cookie 过期、地区、接口变了）可重试；第一次就失败时整页状态（需要登录时是登录状态）。断网时“网络已断开”，联网后自动重试（`ReloadWhenOnline`）。用移动数据刷新时顶上提示“正在使用移动网络”。
  - 改“优先实时在线”或实时在线的平台：所有平台标旧，当前平台 160 毫秒后刷新，其他平台下次打开时刷新（3.x 只刷当前的）。应用在后台 15 秒以上回来、当前是热门时刷新当前平台。
  - 某些平台的推荐只是站点的一部分（平台实现 `LiveDirectoryNotice`）：列表上方一条说明，优先用热门页改写过的 `popular_scope_<平台>`，没有就用平台的 `*_directory_scope` 原文（`popular_grid.dart:14-18`）。
- 内部怎么工作：

```text
PopularPage（popular_page.dart:33）
  _syncTabs（:93）：availableIds(hotAreasList) → TabController；首选平台 preferPlatform
  _tabChanged（:123）→ 停稳 80 ms → _load（:137）→ catalog.feedOf(id).open(count)
      → 有房间 → 700 ms 后 feedOf(下一个).open(count)
popularCatalogProvider（popular_catalog.dart:91，应用期间一直在）
  feedOf（:51）= RoomFeed(source: popularSourceFor(site), rank: AudiencePolicy.rank, visible, precheck)
RoomFeed（room_feed.dart:251）
  open → 标旧了就 refresh，没加载过就 ensure(count)
  ensure/loadMore → _fill → _collect（:462）：一块一块取，去重（identityKey），每块排序，
      直到能显示的够 count、或没有更多、或这次已 20 个请求、或连续两块没有新房间
  refresh（:413）：precheck（断网 / 移动网络）→ 新建列表 → 成功才替换；失败保留旧的、errorOnRefresh
  goToPage / pageRooms（电脑页码就是同一份列表切片）
popularSourceFor（:146）：
  有原生目录（LiveSiteDirectoryPager，含游标）→ DirectorySource
  网络电视、快手 → SingleSource（一次取完，最多 1000）
  斗鱼 40、虎牙 120、SOOP 60、TwitCasting 60、Twitch 100、CC 100、抖音 20 → WindowSource（不足一窗就是最后一页）
  其他 → PagedSource（每次 30 个，空页结束）
```

- 完成度（和 3.x 对照）：
  - 一致的：每个平台的翻页方式和窗口大小、按人数排序、80 毫秒 / 700 毫秒的时机、首选平台、平台列表变化时的停留规则、手机和电脑两种翻页、电脑 ← →、20 个请求和“两块没有新房间”的停止条件、移动网络提示和“不再显示”、后台 15 秒刷新、160 毫秒刷新当前平台。
  - 确认过的改动：刷新失败保留列表并说明原因（I02.1 问题 3、4）；不满一屏自动加载（问题 5）；通用翻页固定 30 个（问题 1：3.x 每次只要“还缺的条数”、页号照加，平台切页不衔接）；“显示跳转按钮”设置生效（问题 2）；隐藏不能播放的直播并说明；平台说明改写（问题 6、升级 20-6）；没有平台时的空状态（问题 7）；全部平台面板、标签回到标题位置、骨架、列数公式（A09.2 c1～c9）；改实时在线后其他平台下次打开时也刷新。
  - 还缺：见“已知问题”第 1 条（首次加载不做断网检查）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/popular/popular_catalog.dart`（95 行） | `PopularCatalog`（`:14`）：`currentPlatform`、`pageSize`（电脑选的每页条数，会话内记住）、`visible`（`:47`）、`feedOf`（`:51`）、`_settingChanged`（`:60-77`：隐藏设置 → 只重画；实时在线设置 → 全部标旧、160 毫秒后刷新当前）；`popularCatalogProvider`（`:91`） |
| `features/popular/popular_page.dart`（373） | `PopularPage`（`:33`）：`_firstCount`（`:74`，手机 20、电脑按每页条数）、`_resumed`（`:80`）、`_syncTabs`（`:93`）、`_tabChanged`（`:123`，80 毫秒 `:134`）、`_load`（`:137`，700 毫秒预取 `:145`）、`_pickPlatform`（`:152`）；`PlatformPicker`（`:225`，“全部平台”，界面归 A09.2） |
| `features/popular/popular_grid.dart`（49） | `popularNoticeOf`（`:14`）、`PopularPlatformView`（`:23`，把一个平台的 `RoomFeed` 交给 `RoomFeedView`，空状态和隐藏说明的文字） |
| `apps/pure_live/lib/shared/rooms/room_feed.dart`（537） | `RoomChunk`、`RoomSource`（`:10-30`）；`DirectorySource`（`:34`）、`WindowSource`（`:65`）、`PagedSource`（`:92`，30）、`SingleSource`（`:116`，1000）；`popularWindowSizes`（`:132`）、`popularSourceFor`（`:146`）；分区的 `areaRoomPageSize`（`:163`）、`areaRoomLoader`（`:179`）、`AreaRoomSource`（`:215`）；`RoomFeed`（`:251`：`maxRequests` 20、`open` `:348`、`ensure` `:355`、`loadMore` `:369`、`retry` `:372`、`refresh` `:413`、`_collect` `:462`、`goToPage` `:491`、`pageRooms` `:506`） |
| `shared/rooms/room_cards.dart`（164） | `cannotPlayHere`（`:20`）、`signedInOn`（`:30`）、`AudiencePolicy`（`:34`：`rank` `:54`、`audienceOf`、`cardOf` `:82`）、`mixesPlatforms`（`:104`，列表里有几个平台时卡片才标平台） |
| `shared/rooms/room_texts.dart`（200） | `describeLoadError`（`:140`）、`isLoginError`（`:153`，`RiskControl` 也算要登录）、`readableAudience`、`roomMark` |
| `shared/rooms/paging.dart`（277） | `phonePageSize` 20（`:14`）、`usesDesktopPages`（`:18`，宽 > 680 且不是手机系统）、`pageSizesOf`（`:22`）；`PaginationBar`（界面，A09） |
| `shared/rooms/room_grid.dart`（750） | 界面归 A09；和数据有关的：`roomClockProvider`（`:86`，卡片“已播”的时钟）、`MobileDataBanner`（`:221`）、`ReloadWhenOnline`（`:250`）、`RoomFeedView`（`:357`：手机离底 600 `loadMore` `:621`、页脚重试 `:729`、电脑页码 `:583-611`） |
| `apps/pure_live/lib/app/network.dart`（87） | `MobileDataNotice`（`:73`）、`precheck`（`:82`：没网抛 `Offline`，只有移动数据时亮提示） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/popular/popular_test.dart`（19） | 取数 4 个（分页去重和每块排序、空页结束；3.x 窗口大小、快手和网络电视一次取完；原生目录游标、隐藏的不计数；刷新失败保留、首次失败为空）；卡片的人数、标记、隐藏规则；分享口令；手机首选平台、排序、隐藏和“显示”、点卡进房；标签停稳时的切换（M13.16）；出错、重试、平台列表变化停在原平台；自动加载和平台说明；下拉回弹和刷新进度线（P02、P05）；电脑页码、每页条数、刷新失败横幅；卡片对话框关注和分享；“全部平台”面板竖屏和宽屏；各尺寸的列数；空平台 |
| `test/shared/room_lists_test.dart`（2） | 卡片没有自己的时间时用共用时钟显示“已播”；搜索页共用平台快照（升级 19-1） |

## 3.x 基线

- `~/ref/v3ref/lib/modules/popular/`（`git show v3.2.11:lib/modules/popular/...`）：`popular_controller.dart`（300 行：平台和翻页方式 `:40-90`，斗鱼 `fixedSize: 40` `:66`、虎牙 120 `:70`；改实时在线 160 毫秒刷新 `:134`；`_initTabController` `:140`，首选平台 `:167`；停稳 80 毫秒 `:212`；700 毫秒预取 `:242`，上一个还在加载时 450 毫秒后再试 `:254`）、`popular_grid_controller.dart`（106：本地、全部、固定、远程四种控制器）、`popular_grid_view.dart`（89）、`popular_page.dart`（46）。
- `lib/common/base/`：`base_controller.dart`（81：请求前查网络 `checkNetworkBeforeRequest` `:29-47`，出错文字靠字符串判断 `:49-68`）、`server_remote_page_controller.dart`（269：通用翻页，`:102`、`:209` 问题 1）、`server_fixed_page_controller.dart`（204）、`server_all_page_controller.dart`（158）、`live_directory_controller.dart`（287）、`base_page_view.dart`（308：宽 > 680 且不是手机系统才用页码 `:57`，移动网络横幅 `:258`）、`desktop_components.dart`（285，页码栏）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（卡片长按或右键 = 操作菜单）；另照 3.x：电脑 ← → 翻页、再点“热门”不刷新（3.x 只有关注再点刷新）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 断网检查和移动网络提示只在**刷新**前做（`precheck`），第一次打开平台、加载更多、电脑翻页都不做；3.x 每次请求前都查 | `shared/rooms/room_feed.dart:427`（只在 `refresh` 里）；`open` `:348`、`ensure` `:355` 不调；3.x `server_fixed_page_controller.dart:111`、`server_remote_page_controller.dart:88`、`:184` | 第一次打开时没网显示的是请求失败的原因（多半“网络有问题”），不是“网络已断开”；用移动数据第一次打开热门时没有流量提示，下拉刷新后才有 | [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md) 第 1 阶段（2026-10-07 登记：`precheck` 挪进 `_fill`，分区房间也传） |
| 加载更多失败后点“重试”只再取一块：`retry` 非刷新时用 `ensure(rooms.length + 1)`，忽略传进来的 `count` | `room_feed.dart:372-373`；调用 `room_grid.dart:729`（传 `rooms.length + 20`） | 重试后可能只多出几个房间（被隐藏的多时） | [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md) 第 2 阶段 |
| `isLoginError` 把风控（`RiskControl`）也当“要登录” | `room_texts.dart:153` | 风控时页面显示登录状态和“去登录”，登录了也可能还是风控 | 有意（3.x 风控多数登录后能过）；不做 |
| I02.1 记录“留给后续”的分享面板、移动网络提示、开播时间都已做（`share_plus` + `SystemShare.sheet` `lib/platform/plugins.dart:38`、`MobileDataBanner`、`roomClockProvider`），记录里的 `popular_feed.dart`、`room_menu.dart`、`popular_rooms.dart` 已挪到 `shared/rooms/` | [I02.1 记录](I02.1-推荐首页/record.md) | 只是记录过时 | I02.1 README 已注明 |
| I02.1 登记“完成”，记录里没有 K90 结果；S02.2、S02.3 冒烟看过热门的切平台、下拉刷新、卡片 | 记录；[S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) | 移动网络提示、电脑翻页没有真机记录 | 移动网络提示没有归属的真机步骤，建议并入 [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 1 阶段（写进本单元报告）；电脑翻页归 X01 |

## 相关决定和规范

- D-009：能下拉刷新的列表照 3.x 两端回弹（`RoomFeedView` 用 `AppRefreshView`）。D-017：测试不访问真实平台（`popular_test.dart` 用假平台）。D-018：`hotAreasList`、`preferPlatform`、`showUnplayableInDiscover`、`pageDefaultSize` 等设置键照 3.x。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“受限”（发现页默认隐藏、卡片标类型）、“翻页”、“说明文字”；1-1、3-1、10-5、14-3、19-1、19-4、20-6、20-8、21-1、24-2、24-5、26-1、26-8、26-9、32-4（I02.1 做了属于热门的部分）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 7 节：热门和分区共用的取数放 `shared/rooms/`。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/popular test/shared/room_lists_test.dart`（21 个）。缺的：没有“第一次打开就断网”“加载更多失败后重试取够一页”的用例（见已知问题）。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节（关注、搜索、分区、历史）没有热门专门的一条；S02.2、S02.3 冒烟走过。

## 路线

本子分类没有未完成的任务。热门页的样子由 A09.2 管（已完成）；平台推荐接口坏了由 E 组巡检开任务；“已知问题”前两条 2026-10-07 已并进 [I03.2](../I03-分区/I03.2-浏览列表的小问题合集/README.md)（第三档）。新想法写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/popular/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I02.1 | 推荐首页 | 功能 | 完成 | 2026-10-01 | 414996596 | [设计或说明](I02.1-推荐首页/README.md)、[记录](I02.1-推荐首页/record.md) |

<!-- docs:生成结束 -->
