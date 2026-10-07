# I03.2 浏览列表的小问题合集

断网预检和移动网络提示只在热门、分区目录切标签重新请求、借图竞态、分区房间页设置只读一次、重试忽略条数、关注无适配器不进冷却、观看记录把已下线平台算失败、标签长度上限写两份。

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 核对：H、I 组（[I02](../../I02-热门/README.md)、[I03](../README.md)、[I04](../../I04-关注/README.md)、[I06](../../I06-观看历史/README.md)、[I07](../../I07-标签和分组/README.md) 各自“已知问题”里“没有任务”的小改）；G、Q、R 组（功能清点 F-NET-03“断网预检、移动数据提示”写“完成”只核对了热门，随本任务改“部分”）
- 相关：列表的共用部件 `RoomFeed`（I02.1、I03.1 建的）；[E05.4](../../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md) 也改 `room_feed.dart`（空页不到底）；网络状态 Q04（`app/network.dart`）；决定 D-001、D-017、D-018
- 任务书：[brief.md](brief.md)

## 目标

八个都很小的问题，分在两类：

**分区（用户最常碰到的）**

1. 断网时打开分区、分区房间、以及第一次打开热门的某个平台：现在显示的是请求失败的原因（多半“网络有问题”），应该和 3.x 一样直接说“网络已断开”；用移动数据看分区房间时也要有“您当前正在使用移动蜂窝流量”的提示（现在只有热门下拉刷新时才有）。
2. 首页在“热门”“分区”“关注”之间切换，每次回到分区都重新请求全部平台的分区目录、闪骨架；应该像热门一样留在应用里。
3. 分区图片“借图”（一个平台没有图时借别的平台同名分区的图）偶尔在重启后丢失一部分，要等那些平台再打开一次才回来。
4. 分区房间页开着时去设置改“显示不能播放的直播”，回来不生效，要退出再进。

**列表通用和其他页**

5. 加载更多失败后点“重试”，只再取一块（可能只多出几个房间），应该按要的条数取。
6. 关注里有平台已经没有适配器（例如某个构建去掉了它）时，每次定时刷新都算“失败”、不进冷却。
7. 观看记录里有已下线平台的记录时，每次刷新都提示“有 M 个刷新失败”；关注页对同样的情况是跳过不请求。
8. 标签名（15 字）和说明（40 字）的长度上限在两个文件里各写一份，改一处会忘另一处。

## 3.x 和现状

| 问题 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 1 断网和移动网络 | 每次请求前都查：`lib/common/base/base_controller.dart:29-45` `checkNetworkBeforeRequest`（断网提示、移动网络时显示横幅）；用在热门、分区房间、分区目录（`live_directory_controller.dart:167`、`server_fixed_page_controller.dart:111`、`server_remote_page_controller.dart:88`、`:184`、`server_all_page_controller.dart:90`）；横幅 `base_page_view.dart:260-300` | `MobileDataNotice.precheck`（`apps/pure_live/lib/app/network.dart:82-86`）只有热门传给 `RoomFeed`（`features/popular/popular_catalog.dart:57`），而且 `RoomFeed` 只在 `refresh` 里调（`shared/rooms/room_feed.dart:427`），`open`（`:348`）、`ensure`（`:355`）不调；分区房间页 `features/area_rooms/area_rooms_page.dart:72-81` 没传；分区目录 `AreaCatalog`（`features/areas/area_catalog.dart`）也没有；电视分区房间 `tv/pages/tv_area_rooms_page.dart:54` 没传。横幅组件 `MobileDataBanner`（`shared/rooms/room_grid.dart:221-245`）在所有房间网格里都有，但 `onMobileData` 只被热门更新 | `precheck` 挪进 `RoomFeed._fill` 和 `refresh` 两处（第一次加载、加载更多、刷新都查）；分区房间页、电视分区房间页传 `precheck`；分区目录加载前也查（断网显示“网络已断开”） |
| 2 分区目录 | `fenix: true` 的懒注册，控制器随页面释放、再进来重建（行为接近现在） | `features/areas/areas_page.dart:52` `_catalogs` 在页面状态里，`:75-76` 建；首页只挂当前页（`features/home/home_page.dart:133-138` 的 `_page` 只给选中的标签建），切走就 `dispose`（`areas_page.dart:62-72`）；热门放在 `popularCatalogProvider`（`popular_catalog.dart:91`），切走不丢 | 目录放进应用级的 provider（照热门），页面只拿；平台列表变了时去掉不用的 |
| 3 借图 | 3.x 没有借图（4.x 加的，A09.4） | `AreaPictures`（`features/areas/area_artwork.dart`）：`load()`（`:84`）读存着的图，`areaPicturesProvider`（`features/areas/areas_common.dart:16-21`）里不等待；`learn`（`:104-121`）在 `AreaCatalog` 加载后调（`area_catalog.dart:85`），**不等 `load` 读完**就把内存里的表整份写回 meta（`:117`），会覆盖存着的、别的平台学到的图 | `learn` 先 `await load()` |
| 4 分区房间页的设置 | — | `area_rooms_page.dart:71` 在 `initState` 读一次 `showUnplayableInDiscover`；热门的 `visible` 每次都读（`popular_catalog.dart:44-49`），并跟着设置变（`_settingChanged`） | 跟着设置变：`watchSetting` 或订阅，变了就 `_feed.visibilityChanged()` |
| 5 重试的条数 | — | `room_feed.dart:372-373` `retry({required int count})`：不是刷新时 `ensure(rooms.length + 1)`，忽略 `count`；调用 `room_grid.dart:729` 传 `rooms.length + 20` | `ensure(count)` |
| 6 关注无适配器 | — | `features/favorite/follow_refresher.dart:91-93`：`site == null` 直接返回 null（算失败），不写 `_failedAt`，不受 5 分钟冷却限制；已下线的平台在前面单独跳过（`:64`） | 没有适配器的当已下线处理：不请求、不算失败、原样保留 |
| 7 观看记录已下线平台 | — | `features/history/history_refresh.dart:13-20` `siteHistoryLoader`：`site == null` 抛 `StateError`（`:15`），`refreshHistoryRooms` 算失败 | 跳过：不请求、不算失败、原样保留（和关注一致） |
| 8 标签长度 | 3.x 两个对话框各写 `maxLength: 15`、`40` | `features/tags/tag_editor_dialog.dart:10`、`:13`（`tagNameMaxLength`、`tagDescriptionMaxLength`）；`shared/rooms/room_tags_dialog.dart:13`、`:16`（`roomTagNameMaxLength` 等） | 一处定义（`packages/live_store/lib/src/tags.dart` 的 `TagStore` 或 `shared/`），两个对话框都引用；数值不变 |

## 方案

- c1 `room_feed.dart`：`precheck` 从 `refresh`（`:427`）挪到“发请求之前”的公共位置（`_fill` 开头和 `refresh` 里各一次），失败时按现在的 `Offline` 处理（`room_texts.dart:141` 显示“网络已断开”）；`area_rooms_page.dart`、`tv_area_rooms_page.dart` 传 `precheck: () => MobileDataNotice.precheck(probe)`（`probe` 来自 `networkProbeProvider`，照热门）；`AreaCatalog.refresh` 开头也调一次（只断网检查，横幅由房间列表负责）。
- c2 分区目录：新 `areaCatalogsProvider`（`features/areas/areas_common.dart`，`Provider` 持有 `Map<String, AreaCatalog>`，`ref.onDispose` 释放），`areas_page.dart` 改从它取；页面 `dispose` 不再释放目录；平台列表变了时（`_sync`，`:85-100`）照旧去掉不在列表里的。
- c3 `area_artwork.dart` `learn`：开头 `await load()`。
- c4 `area_rooms_page.dart:71`：`_showUnplayable` 改成订阅 `Settings.showUnplayableInDiscover`（`store.settings.watch(...)`），变了 `setState` + `_feed.visibilityChanged()`；“显示隐藏的”按钮（`_showHidden`，`:83-86`）照旧临时打开。
- c5 `room_feed.dart:373`：`ensure(count)`（`count` 小于等于现有条数时取一块，保持现在“至少多一个”的意思：`ensure(math.max(count, rooms.length + 1))`）。
- c6 `follow_refresher.dart:91-93`：`site == null` 时返回原房间（不算失败），和已下线平台同样处理；`FollowRefreshResult.failed` 不计它。
- c7 `history_refresh.dart`：`siteHistoryLoader` 对没有适配器的返回原房间，或 `refreshHistoryRooms` 加一个“跳过”的判断（看哪种改动小），不计入 `failed`。
- c8 把两组常量合成一处（例如 `TagStore.maxNameLength = 15`、`maxDescriptionLength = 40`，3.x 的值），两个对话框引用；数值不变，不是设置（D-018 不涉及）。
- 文档：功能清点 F-NET-03 已改“部分”（只有热门），完成后改回“完成”。

## 验证

- 自动测试：`apps/pure_live/test/features/popular/popular_test.dart`（第一次打开和加载更多也查断网、重试按条数取）、`test/features/areas/areas_test.dart`（分区房间页断网说明和移动网络横幅、设置变化生效、目录切走再回来不重新请求、借图先读再写）、`test/features/favorite/`、`test/features/history/`（已下线平台不算失败）、`test/features/tags/`（长度上限）。
- 真机：断网打开分区、移动数据看分区房间、来回切首页标签（任务书“真机验证”）；做之前“未开始”。

## 留下的问题

- 搜索页、关注页的断网预检：3.x 搜索也查（`server_remote_page_controller.dart`），4.x 搜索走自己的流程（I05），这次不改，记在 I05 说明里。
- E05.4 也改 `room_feed.dart`（`:483` 空页不到底），两个任务先后做。
