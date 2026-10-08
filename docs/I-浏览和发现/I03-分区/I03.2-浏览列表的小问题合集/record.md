# I03.2 浏览列表的小问题合集：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `d24c6757b` 开始），两个阶段各一个提交
- 设计或说明：[README.md](README.md)；任务书 [brief.md](brief.md)

## 阶段 1：分区（c1～c4）

### 根因

1. 断网预检：`apps/pure_live/lib/shared/rooms/room_feed.dart:427`（改前）只有 `refresh` 调 `precheck`，`open`/`ensure`/`_fill` 不调；分区房间页 `features/area_rooms/area_rooms_page.dart:72-81`、电视 `tv/pages/tv_area_rooms_page.dart:54` 没传 `precheck`；分区目录 `features/areas/area_catalog.dart` `_load` 直接请求。
2. 分区目录：`features/areas/areas_page.dart:52`（改前）`_catalogs` 在页面 State 里，`dispose`（`:62-72`）全部释放；首页切走标签就销毁页面。
3. 借图：`features/areas/area_artwork.dart:104-121`（改前）`learn` 不等 `load()`，`:117` 把内存里的表整份写回，覆盖还没读进来的存档。
4. 分区房间页：`area_rooms_page.dart:71`（改前）只在 `initState` 读一次 `showUnplayableInDiscover`。

### 做了什么

- c1：`RoomFeed._fill` 在请求前也调 `precheck`（第一次加载、加载更多都查；`refresh` 照旧查），断网时 `error` 是 `Offline`，列表区显示离线状态（`loadErrorStatus` → “没有网络连接”，连上自动重试，是 4.x 已确认的离线状态页；3.x 是 toast“网络已断开”）。分区房间页、电视分区房间页传 `precheck: () => MobileDataNotice.precheck(probe)`（`networkProbeProvider`，照热门），移动数据时列表上方有流量提示。分区目录 `AreaCatalog` 加 `precheck`，由 `areaCatalogsProvider` 传“只查断网”（横幅由房间列表负责）。
- c2：`features/areas/areas_common.dart` 新增 `AreaCatalogs` 和应用级 `areaCatalogsProvider`（每个平台一份目录，`ref.onDispose` 释放）；`areas_page.dart` 从它取，页面 `dispose` 不再释放；平台列表变了时 `_sync` 调 `retain(ids)` 释放不在列表里的。下拉刷新、回到前台刷新照旧。
- c3：`AreaPictures.learn` 开头 `await load()`。
- c4：分区房间页订阅 `settings.changes`，`showUnplayableInDiscover` 变了就 `setState` + `_feed.visibilityChanged()`，`dispose` 取消订阅；“显示隐藏的”按钮照旧临时打开。

### 测试（改之前 6 个都失败）

- `test/features/popular/popular_test.dart`：`I03.2 c1: the first load and loading more also check the network`（`open`、`loadMore` 各查一次；断网 `error` 是 `Offline`、不发请求）。
- `test/features/areas/areas_test.dart` 新组 `I03.2 browsing lists`：分区房间页移动数据有 `mobile-data-notice`、断网显示“没有网络连接”；分区页断网显示“没有网络连接”且不请求；首页 分区 → 热门 → 分区：第一帧就有分区、`getCategories` 次数不变；借图：存档里已有的和新学的都在；分区房间页开着时改设置，不能播放的房间出现、消失。
- 改后 `apps/pure_live` 全部通过（997 个）。

### 说明

- 内存：每个平台一份目录（分类和分区列表，几十 KB），应用运行期间留着，和热门一样。
- 电视的分区目录（`tv/pages/tv_areas_pane.dart`）有自己的一份目录表，不在本任务范围（任务书只要电视分区房间页传 `precheck`），没改。
- 搜索页的断网预检照 README“留下的问题”，归 I05。
