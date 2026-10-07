# I03 分区

分区相关的三块数据和行为：每个平台的分区目录（一次取全、借图、刷新保留选中分类）、一个分区里的房间（一页接一页、去重、隐藏不能播放的）、关注的分区，以及“平台显示”（首页热门和分区用哪些平台、什么顺序）。

## 范围

- 包括：
  - 分区目录：`apps/pure_live/lib/features/areas/area_catalog.dart`（`AreaCatalog`、`filterAreas`）、`areas_page.dart` 的加载时机（平台列表、首选平台、800 毫秒预取下一个、后台回来刷新）、`platform_areas_view.dart` 的分类切换和电脑本地页码。
  - 分区图片：`features/areas/area_artwork.dart`（`AreaPictures`：自己的图、借同名 / 别名 / 包含的图、学到的存进 meta `areas.pictures`；`categoryArtworkAlignment`、`isCategoryIconSprite`：猫耳两态图标）、`areas_common.dart` 的 `areaPicturesProvider`。
  - 关注分区：`areas_common.dart`（`toggleAreaFollow`、`followedAreaKeysProvider`、`followedAreasProvider`、`openArea`）、`favorite_areas_view.dart`（`favoriteAreaTabs`、`resolveFavoriteAreaSiteIndex`）、`features/area_rooms/follow_area_button.dart`；存储在 `live_store` 的 `followAreas`。
  - 分区房间：`features/area_rooms/area_rooms_page.dart`（`AreaRoomsView` 建 `RoomFeed`、隐藏规则、最多 5000）和 `shared/rooms/room_feed.dart` 里分区用的 `areaRoomLoader`、`areaRoomPageSize`、`AreaRoomSource`（`RoomFeed` 本身归 [I02](../I02-热门/README.md)）。
  - 平台显示：`features/hot_areas/hot_areas_page.dart` 的 `toggleHotArea`、`reorderHotAreas`、`preferredAfter`、恢复默认（设置 `hotAreasList`、`preferPlatform`）。
- 不包括（归哪里）：
  - 分区页、分区卡片、分区房间页、关注分区页、平台显示页**长什么样** → [A09.4 分区](../../A-界面设计/A09-浏览界面/A09.4-分区/README.md)、[A09.5 分区房间](../../A-界面设计/A09-浏览界面/A09.5-分区房间/README.md)、[A09.6 热门分区、关注的分区](../../A-界面设计/A09-浏览界面/A09.6-热门分区、关注的分区/README.md)；`area_card.dart` 的 `AreaCard`、`AreaGrid`、`AreaGridSkeleton` 是界面，归 A09。
  - 各平台的分区接口（`getCategories`、`getCategoryRooms`、目录翻页、CC 官方入口、网络电视频道）→ [E 直播平台](../../E-直播平台/README.md)；点分区后的跳转 `AppNavigator.toCategoryDetail`（CC 官方入口用浏览器、网络电视频道直接播放）→ [I01](../I01-首页外壳和全局/README.md)。
  - 关注分区的存储格式和备份 → J02、J03；电视的分区 → X03。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - **分区页**（首页“分区”或 `/areas`）：标题位置是平台标签（同热门，来自“平台显示”，第一次停在首选平台），平台之间只能点标签切换（3.x 为了不和分类的左右滑抢手势）；每个平台的分类是第二排标签，可左右滑；只有一个分类的平台不显示分类标签。第一次显示骨架。加载完 800 毫秒后预取下一个平台。下拉刷新；刷新失败保留已显示的分区，上方横幅可重试。电脑上每个分类的分区按页显示（本地切片，页码栏和 ← →）。后台 15 秒以上回来、当前是分区时刷新当前平台。
  - **分区卡片**：图（自己的，没有就借：同名不分大小写 → 别名表 → 名字互相包含；猫耳两态图标只显示彩色一半、也不借出去）、名字（空时“未命名分区”）。点：网络电视频道直接播放、CC 官方入口用浏览器、其他进分区房间。长按或右键：卡片对话框里关注 / 取消关注（取消先确认）；已关注的卡片右上角心形。
  - **关注分区**（右下“关注分区”按钮，或 `/favoriteAreas`）：“全部”加有关注分区的平台各一个标签（只为有关注的平台建标签）；平台列表变了按 id 留在原标签；没有关注时说明并给“去分区”。
  - **分区房间**（`/area_rooms`，参数 `[LiveSite, LiveArea]`）：一页接一页（原生目录看平台说的“还有没有”、游标不前进就停；其他按页号，某页没有新房间就到底），每页 30 个（SOOP、TwitCasting 60），按房间身份去重，房间的分区名改成当前分区，最多留 5000 个。不能播放的默认隐藏，顶上“已隐藏 N 个……”点“显示”只在本页显示。手机下拉刷新、离底自动加载；电脑页码栏（A09.5 改回 3.x 的页码）。标题栏右边“关注分区”胶囊（`FollowPill`，不带数量，A09.5 c3）。平台有目录说明时显示原文（`*_directory_scope`）。
  - **平台显示**（设置或“全部平台”面板里的入口）：开关显示哪些平台、拖动排序（只排显示的）、至少留一个（“至少保留一个平台”）、首选平台被隐藏时改成第一个显示的、“恢复默认”先确认。
- 内部怎么工作：

```text
AreasView（areas_page.dart:40）
  _sync（:86）：availableIds(hotAreasList) → TabController（首次停在 preferPlatform）；移除的平台的目录释放
  _loadCurrent（:120）→ _catalog(id).ensureLoaded() → 800 ms 后 _warmNext（:131）
  _catalogs（:52）：每个平台一个 AreaCatalog，放在页面 State 里（页面销毁就没了）
AreaCatalog（area_catalog.dart:11）
  refresh（:62，合并并发）→ _load（:74）：site.getCategories(1, 1000)；按 id 保留选中分类；
      成功后 AreaPictures.learn(categories)；失败保留旧分类、记 error
AreaPictures（area_artwork.dart:49）：load（读 meta areas.pictures）/ learn（学到新的就整份写回）/ pictureFor / borrow
AreaRoomsView（area_rooms_page.dart:46）
  initState（:68）：读一次 showUnplayableInDiscover → RoomFeed(source: AreaRoomSource(areaRoomLoader(site, area)), visible, maxRooms: 5000)
  → RoomFeedView（同热门，I02）
toggleAreaFollow（areas_common.dart:107）→ store.followAreas 增删；followedAreasProvider 让卡片和按钮跟着变
```

- 完成度（和 3.x 对照）：
  - 一致的：平台标签和首选平台、平台只能点击切换、分类左右滑、`getCategories(1, 1000)` 一次取全、800 毫秒预取、后台回来刷新、点分区的三种去向、借图（同名、别名、包含）、两态图标、关注分区的“全部”和按 id 保留、分区房间的去重和改分区名、电脑页码和 ← →、平台显示的开关排序和至少一个、首选平台跟着改。
  - 确认过的改动：斗鱼每页 120 个只显示 40 个（升级 A-1）、SOOP 缺房间（A-4）、快手只取第一页（A-2）都改成整页逐页显示；没有路由参数时不崩（I01.1 问题 6）；“需要登录”按错误类型判断；刷新失败保留内容；隐藏不能播放的直播；抖音按分类分标签（C-12 之后“游戏”下约 156 个分区）；关注状态看得见（心形）；平台显示分两组和恢复默认（A09.6）；分区卡片长按改成卡片对话框（A09.4 X3）；去掉 I03.1 加的分区筛选和刷新按钮（A09.4 照 3.x，`filterAreas` 还在但没有入口）；分区房间电脑改回页码（A09.5）；“关注分区”按钮不再带数量（A09.4、A09.6）。
  - 有意差异：借图不做相似度匹配（3.x 用 `string_similarity` 兜底，容易借到不相干的图）；分区房间最多 5000 个（3.x 20000）；学到的图存在 meta `areas.pictures`，不读 3.x 的 `cached_area_pics`。
  - 还缺：见“已知问题”。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/areas/area_catalog.dart`（122 行） | `AreaCatalog`（`:11`）：`categories`、`allAreas`（去重）、`select`、`ensureLoaded`（`:59`）、`refresh`（`:62`，合并并发）、`_load`（`:74`，`getCategories(1, 1000)`、按 id 保留选中、学图）、`clearError`；`filterAreas`（`:114`，应用里没有调用，只有测试用） |
| `features/areas/area_artwork.dart`（217） | `categoryArtworkAlignment`（`:22`）、`isCategoryIconSprite`（`:42`）、`AreaPictures`（`:49`：`metaKey` = `areas.pictures`、`load` `:84`、`learn` `:104`、`pictureFor` `:124`、`borrow` `:131`）、`AreaArtwork`（`:164`，界面） |
| `features/areas/areas_common.dart`（146） | `areaPicturesProvider`（`:16`）、`areaDisplayName`（`:24`）、`showAreaDialog`（`:50`，卡片对话框）、`openArea`（`:82`）、`toggleAreaFollow`（`:107`）、`followedAreaKeysProvider`（`:134`）、`followedAreasProvider`（`:140`）、`gridSpacing` |
| `features/areas/areas_page.dart`（259） | `AreasPage`（`:24`，`/areas` 和 `/favoriteAreas` 按路径分开）、`AreasView`（`:40`）：`_catalog`（`:75`）、`_sync`（`:86`）、`_loadCurrent`（`:120`）、`_warmNext`（`:131`）、`_onResumed`（`:138`）；`_FollowedAreasButton`（`:204`，界面） |
| `features/areas/platform_areas_view.dart`（318） | `PlatformAreasView`（`:24`，一个平台：分类标签 `_syncTabs` `:77`、状态、刷新横幅）、`_AreaPages`（`:179`，电脑本地页码 `:222-282`） |
| `features/areas/favorite_areas_view.dart`（165） | `resolveFavoriteAreaSiteIndex`（`:17`）、`favoriteAreaTabs`（`:31`，只为有关注分区的平台建标签）、`FavoriteAreasView`（`:49`） |
| `features/areas/area_card.dart`（291） | `AreaCard`、`AreaGridSkeleton`、`AreaGrid`（界面，A09.4） |
| `features/area_rooms/area_rooms_page.dart`（142） | `AreaRoomsPage`（`:20`，没有参数时说明）、`AreaRoomsView`（`:46`：`initState` `:68` 建 `RoomFeed`、读一次隐藏设置 `:71`、`maxRooms: 5000` `:79`；`_showHidden` `:83`；`_notice` `:94`） |
| `features/area_rooms/follow_area_button.dart`（55） | `FollowAreaButton`（`:14`，调 `toggleAreaFollow`，忙时不能再点） |
| `features/hot_areas/hot_areas_page.dart`（252） | `toggleHotArea`（`:13`，不能关最后一个）、`reorderHotAreas`（`:25`）、`preferredAfter`（`:35`）、`HotAreasPage`（`:55`：`_save`、`_toggle`、`_reset` `:79`，最宽 720） |
| `apps/pure_live/lib/shared/rooms/room_feed.dart` | 分区用的 `areaRoomPageSize`（`:163`）、`areaRoomLoader`（`:179`：原生目录 / CC 的分类目录 / 游标目录（游标不前进就停 `:193-196`）/ 按页号）、`AreaRoomSource`（`:215`，给房间改分区名） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/areas/areas_test.dart`（14） | 分区：筛选函数；借图（同名、别名、包含、两态图标不外借）；刷新按 id 保留分类、失败保留分区；整页（首选平台、分类标签、卡片对话框、关注和心形、关注分区页）；关注分区标签按 id 保留。分区房间：整页显示、无新房间到底、隐藏不能播放；SOOP 和 TwitCasting 60 个、游标不前进时停；刷新失败保留、重试；进分区、显示隐藏的、关注分区。平台显示：开关（不能关最后一个、首选平台跟着）、纯函数。抖音按分类分标签。没有关注时的说明（U.4f c5）。平台显示页最宽 720、拖动把手、两组（U.4f c7、c9、c10） |

## 3.x 基线

- `~/ref/v3ref/lib/modules/areas/`（`git show v3.2.11:lib/modules/areas/...`）：`areas_controller.dart`（171 行：每个平台 `Get.lazyPut(() => AreasListController(site), fenix: true)` `:57`，首选平台 `:92-97`）、`areas_list_controller.dart`（205：`getCategories(1, 1000)`）、`areas_page.dart`（88：平台只能点标签 `:34-40`）、`areas_grid_view.dart`（289）、`widgets/area_card.dart`（149）、`favorite_areas_page.dart`（143）；`AreasController` 在 `lib/common/global/initial_services.dart:36` 注册（`lazyPut`，`fenix: true`）；首页回来刷新 `lib/modules/home/home_page.dart:161-162`。
- `lib/modules/area_rooms/`：`area_rooms_binding.dart`（44：`Get.arguments[0]` `:9-10`；斗鱼切片 `:30-31`、SOOP `:35`）、`area_rooms_controller.dart`（95：“需要登录”靠 `-352`、`NoSuchMethodError` 字符串 `:22-26`）、`area_rooms_page.dart`（288）。
- `lib/modules/hot_areas/`：`hot_areas_controller.dart`（87）、`hot_areas_page.dart`（132）。
- `lib/plugins/area_pic_mapper.dart`（212，借图和相似度）、`lib/common/utils/category_artwork.dart`（两态图标）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（卡片长按或右键 = 操作菜单，分区卡片也是）；另照 3.x：平台标签只能点击切换、电脑 ← → 翻页。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 分区目录放在页面 State 里，切首页标签（页面销毁）再回来要重新请求全部平台的分区；热门放在 provider 里不会 | `features/areas/areas_page.dart:52`、`:75`；对照 `features/popular/popular_catalog.dart:91` | 来回切首页标签时每次都闪骨架、多发请求 | 没有任务；3.x 是 `fenix: true` 的懒注册，行为接近（控制器随页面释放再建），要改成 provider 先确认真机上的感受（写进本单元报告） |
| `AreaPictures.learn` 可能在 `load()` 读完 meta 之前跑完，这时整份写回会覆盖掉存着的、别的平台学到的图 | `area_artwork.dart:104-120`（`learn` 不等 `load`）；`areas_common.dart:16-21`（`load` 不等待） | 重启后部分借来的图暂时没有，等那些平台再打开一次又学回来 | 没有任务；小改（`learn` 先 `await load()`），顺手修 |
| 分区房间页只在打开时读一次“显示不能播放的直播”，开着时改设置不生效；也没有 `precheck`（没有断网检查和移动网络提示） | `area_rooms_page.dart:71`、`:72-80`（`RoomFeed` 没传 `precheck`） | 要退出再进才生效；用移动数据刷新分区房间时没有流量提示（热门有） | 没有任务；建议和 I02 的 `precheck` 问题一起改 |
| `filterAreas` 应用里没有调用（A09.4 照 3.x 去掉了筛选入口），只剩测试在用 | `area_catalog.dart:114`；`test/features/areas/areas_test.dart:139` | 死代码 | 有意去掉入口（A09.4 记录）；函数留着还是删，下次改这个文件时决定 |
| `areaRoomLoader` 的按页号分支以“这页是空的”判断到底，平台在最后一页之后返回重复的房间时靠 `RoomFeed` 的“连续两块没有新房间” | `room_feed.dart:205-209`、`:476-481` | 多请求一两次 | 照 3.x，不做 |
| I03.1 记录里不符的：“留给后续”的图片请求头（`app.dart:183` 已设）、卡片菜单的分享和标签（I01.2 统一菜单已有）、共享的取数和卡片（已挪到 `shared/rooms/`）都已做；记录说“分区房间桌面改成连续加载”，A09.5 改回了页码；“关注分区”按钮不再带数量 | [I03.1 记录](I03.1-分区/record.md) | 只是记录过时 | I03.1 README 已注明 |
| I03.1 登记“完成”，没有 K90 记录；S02.3 看过分区和分区房间（[记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)） | — | 关注分区、平台显示的拖动没有真机记录 | 建议并入 S02.6 第 3 阶段（写进本单元报告） |

## 相关决定和规范

- D-009（下拉刷新回弹）、D-017（测试不访问真实平台）、D-018（`hotAreasList`、`preferPlatform`、`showUnplayableInDiscover` 照 3.x 的键）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：A-1、A-2、A-4（分区页部分）、8-10、10-5、19-1、24-5、26-1、20-1、25-1、33-1、31-4、C-12、统一原则“受限”。
- 界面决定：A09.4 X3（分区卡片长按用卡片对话框）、A09.5（电脑页码）、A09.6（平台显示两组）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/areas`（14 个）。缺的：没有“切首页标签后分区不重新请求”的用例（现在会重新请求）；`AreaPictures` 的 `learn` 早于 `load` 的竞态没有用例。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节（关注、搜索、分区、历史）；S02.3 走过分区和分区房间。

## 路线

本子分类没有未完成的任务。“已知问题”前三条是小改，建议下次改这些文件的任务顺手做，或由维护者单独登记一个第三档任务（三条一起，约 1 小时）。分区页的样子由 A09.4～A09.6 管（已完成）；平台的分区接口变了由 E 组开任务。新想法（例如分区搜索加回来）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/areas/`、`area_rooms/`、`hot_areas/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I03.1 | 分区：分区列表、分区房间、热门分区 | 功能 | 完成 | 2026-10-01 | 023936ebe | [设计或说明](I03.1-分区/README.md)、[记录](I03.1-分区/record.md) |

<!-- docs:生成结束 -->
