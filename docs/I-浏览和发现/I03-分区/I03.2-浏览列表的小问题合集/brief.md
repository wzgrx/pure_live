# I03.2 浏览列表的小问题合集：任务书

## 背景

- 来源：2026-10-07 docs v2 核对，H、I 组在 I02、I03、I04、I06、I07 的说明里列了几条“没有任务、顺手改”的小问题；G、Q、R 组指出功能清点 F-NET-03（断网预检、移动数据提示）写“完成”只核对了热门。维护者合成本任务（第三档）。逐条的对照见本文件夹 `README.md`。
- 现象（按问题编号）：
  1. 关掉网络打开首页 → 分区：显示“网络有问题”之类的请求失败，而不是“网络已断开”；用移动数据进分区房间：没有“您当前正在使用移动蜂窝流量，请注意流量消耗。”的提示（热门下拉刷新后才有）。第一次打开热门的某个平台（不是下拉刷新）时也一样。
  2. 首页在“分区”和别的标签之间来回切，每次回到分区都闪骨架、重新请求。
  3. 重启后，有些分区的借来的图暂时没有。
  4. 分区房间页开着时改设置“显示不能播放的直播”，回来不变。
  5. 列表底部“加载失败，点击重试”，点了只多出几个房间。
  6. 关注里有没有适配器的平台时，定时刷新每轮都报它失败。
  7. 观看记录刷新时，已下线平台的记录每次都算“刷新失败”。
  8. （开发者）标签长度上限写了两份。
- 为什么现在做：第三档；都是小改，一起做约 2 小时（两个阶段）。
- 已经做过的：`RoomFeed`、`MobileDataNotice`（I02.1、O03.1）；分区和借图（I03.1、A09.4）；关注刷新和冷却（I04.1）；观看记录刷新（I06.1）；标签（I07.1）。

## 目标和验收

1. 热门、分区房间（手机和电视）、分区目录：第一次加载、加载更多、下拉刷新之前都检查网络；断网时列表区显示“网络已断开”（`network_disconnected_msg`）；移动数据时房间列表上方出现流量提示（“不再显示”后本次运行不再出现，同现在）。
2. 首页切到别的标签再切回分区：已经加载过的平台目录直接显示，不重新请求、不闪骨架；下拉刷新照旧重新请求；平台列表里去掉的平台，它的目录释放。
3. 借图：`learn` 一定在存着的图读完之后才写回；重启后之前学到的图都在（不用再打开那些平台）。
4. 分区房间页开着时改“显示不能播放的直播”，回到页面马上按新设置显示或隐藏。
5. 加载更多失败后点“重试”：按调用方要的条数取（`room_grid.dart` 传的 `rooms.length + 20`），至少多一个。
6. 关注刷新：没有适配器的平台不请求、不算失败、原样保留（和已下线平台一样）。
7. 观看记录刷新：没有适配器的平台不请求、不算失败、原样保留；提示里的失败数不含它们。
8. 标签名 15、说明 40 的上限只定义一处，两个对话框都用它，数值和 3.x 一样。
9. 没有新设置、没有新文字；测试和门禁通过。

## 现状（读代码得出，写文件:行）

- 1：`apps/pure_live/lib/app/network.dart:73-87` `MobileDataNotice`（`onMobileData`、`dismissed`、`precheck(probe)`：断网抛 `Offline`，记是不是移动数据）；`apps/pure_live/lib/shared/rooms/room_feed.dart`：构造参数 `precheck`（`:260`、`:280`），只在 `refresh`（`:413-455`）里 `await precheck?.call()`（`:427`）；`open`（`:348`）、`ensure`（`:355-365`）、`_fill`（`:375-407`）不调。`Offline` 的文字：`shared/rooms/room_texts.dart:141`。横幅：`shared/rooms/room_grid.dart:221-245` `MobileDataBanner`，`:641` 在有内容时显示。传了 `precheck` 的只有 `features/popular/popular_catalog.dart:57`；`features/area_rooms/area_rooms_page.dart:72-81`、`tv/pages/tv_area_rooms_page.dart:54` 没传；分区目录 `features/areas/area_catalog.dart`（`ensureLoaded` `:59`、`refresh`）不查。网络探测 `networkProbeProvider`（热门用的 `_probe`）。
- 2：`features/areas/areas_page.dart`：`_catalogs`（`:52`）、`_catalog`（`:75-76`）、`dispose` 释放全部（`:62-72`）、`_sync`（`:85-110`）去掉不在列表的；`features/home/home_page.dart:133-138` 只建当前标签的页面（`_page`），切走就销毁。热门的做法：`popular_catalog.dart:91` `popularCatalogProvider`。
- 3：`features/areas/area_artwork.dart`：`load()`（`:84`，`_loading ??= _read()`）、`_read`（`:86-101`，`putIfAbsent`）、`learn`（`:104-121`，`:117` 整份写回 `metaKey`）；`features/areas/areas_common.dart:16-21`（`pictures.load().ignore()`，不等）；调用 `area_catalog.dart:85`。
- 4：`area_rooms_page.dart:65-81`（`initState` 读 `Settings.showUnplayableInDiscover` 一次，`:71`）、`_showHidden`（`:83-86`）。
- 5：`room_feed.dart:371-373` `retry`；调用 `room_grid.dart:729`。
- 6：`features/favorite/follow_refresher.dart`：已下线的跳过（`:64`，`SiteIds.isRetired`），`_load`（`:90-105`）`site == null` 返回 null（`:91-93`）→ `failed++`（`:77-79`）。
- 7：`features/history/history_refresh.dart:13-20` `siteHistoryLoader`（`:15` 抛 `StateError`）、`refreshHistoryRooms`（`:47` 起）。
- 8：`features/tags/tag_editor_dialog.dart:9-13`；`shared/rooms/room_tags_dialog.dart:12-16`；`packages/live_store/lib/src/tags.dart`（`TagStore`，没有上限常量）。
- 测试：`apps/pure_live/test/features/popular/popular_test.dart`（`feed(...)` 辅助 `:150-161`，`:201` “a failed refresh keeps the rooms”）、`test/features/areas/areas_test.dart`、`test/features/favorite/`、`test/features/history/`、`test/features/tags/`。

## 3.x 基线

- `git show v3.2.11:lib/common/base/base_controller.dart:19-45`：`readRequestConnectivity`、`checkNetworkBeforeRequest`（断网提示、移动网络横幅 `showCellularBanner`，`neverShowCellularBanner` 本次运行不再显示）；调用 `lib/common/base/live_directory_controller.dart:167`、`server_fixed_page_controller.dart:111`、`server_remote_page_controller.dart:88`、`:184`、`server_all_page_controller.dart:90`（热门、分区房间、分区目录都用）；横幅 `base_page_view.dart:260`、`:299`。
- 分区目录：3.x 的控制器是懒注册（`fenix: true`），随页面释放再建——第 2 条是改进，不是恢复 3.x；改前先在 K90 上确认来回切换的感受（写进记录）。
- 标签：3.x 两个对话框 `maxLength: 15`、`40`。
- 要保留：横幅的文字、“不再显示”只在本次运行有效；“显示不能播放的直播”的键名和默认值（D-018）；关注的 5 分钟冷却；已下线平台的处理方式。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 9.2 节（列表流畅度）。
3. 本文件夹的 `README.md`；`docs/I-浏览和发现/I02-热门/README.md`、`I03-分区/README.md`、`I04-关注/README.md`、`I06-观看历史/README.md`、`I07-标签和分组/README.md` 的“已知问题”；`docs/E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/brief.md`（同改 `room_feed.dart`）。

## 范围

- 可以改：`apps/pure_live/lib/shared/rooms/room_feed.dart`（`precheck` 的位置、`retry`）；`features/area_rooms/area_rooms_page.dart`；`tv/pages/tv_area_rooms_page.dart`（只传 `precheck`）；`features/areas/`（`areas_page.dart`、`areas_common.dart`、`area_artwork.dart`、`area_catalog.dart`）；`features/favorite/follow_refresher.dart`；`features/history/history_refresh.dart`；`features/tags/tag_editor_dialog.dart`、`shared/rooms/room_tags_dialog.dart`、`packages/live_store/lib/src/tags.dart`（只加常量）；对应测试；`docs/inventory/FEATURES.md` 的 F-NET-03（完成后改回“完成”）；本文件夹。
- 不能改：`room_feed.dart:483`（E05.4 改）；横幅的样子和文字；设置键名和含义（D-018）；搜索页（I05）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 分区：断网预检和移动网络提示、目录留在应用里、借图竞态、隐藏设置跟着变 | c1、c2、c3、c4 | `room_feed.dart`（只 `precheck`）、`area_rooms_page.dart`、`tv_area_rooms_page.dart`、`features/areas/*`、测试 | 验收 1～4 |
| 2 列表通用和其他页：重试条数、关注和观看记录的已下线平台、标签长度上限 | c5、c6、c7、c8；FEATURES F-NET-03 | `room_feed.dart`（只 `retry`）、`follow_refresher.dart`、`history_refresh.dart`、两个标签对话框、`tags.dart`、测试 | 验收 5～8 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1（改之前会失败）：
  - `popular_test.dart`：“the first load and loading more also check the network”：`precheck` 计数，`open` 和 `loadMore` 各调一次；断网时 `error` 是 `Offline`。
  - `areas_test.dart`：分区房间页断网 → 显示“网络已断开”；移动数据 → 有 `mobile-data-notice`；改 `showUnplayableInDiscover` 后不能播放的房间出现 / 消失；首页切到热门再切回分区，假平台的 `getCategories` 调用次数不变；`AreaPictures`：先 `learn` 再完成 `load` 的顺序下，meta 里同时有存着的和新学的。
- 阶段 2（改之前会失败）：`popular_test.dart`：加载更多失败后 `retry(count: rooms.length + 20)` 取够 20 个（假平台每块 5 个）；`test/features/favorite/` 的刷新用例：没有适配器的平台 `failed == 0`、房间原样；`test/features/history/` 同样；`test/features/tags/`：两个对话框的 `maxLength` 等于同一个常量。
- 测试里的定时器至少 1 秒（D-017）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 只断测试包的网（或开飞行模式），首页 → 分区，再进一个分区 | 分区和分区房间都写“网络已断开”，有重试 |
| 2. 维护者手持手机，关掉 Wi-Fi 只用移动数据（这一步不用 adb）：进分区房间 | 列表上方有流量提示和“不再显示”；回到 Wi-Fi 后重新 `adb connect` |
| 3. 首页：分区（等目录出来）→ 热门 → 分区 | 第二次进分区直接显示，没有骨架 |
| 4. 分区房间页开着，去设置 → 推荐和分区（或对应页）改“显示不能播放的直播”，返回 | 列表马上变 |
| 5. 观看记录里有已下线平台的记录（没有就跳过）时下拉刷新 | 提示里没有把它算成失败 |

## 风险和注意

- c1 把 `precheck` 放进 `_fill` 后，热门每次加载更多都会探一次网络（`connectivity_plus` 的一次查询，很便宜）；探测失败（插件异常）不能挡住加载：照现在 `precheck` 抛什么就是什么，只有确定断网才抛 `Offline`。
- c2 目录挪到应用级后，平台列表（`savedSites`）变化、退出账号这类事件要照旧清掉（看 `_sync` 现在怎么处理）；内存里多留几份目录（每个平台一份，几十 KB）。
- c4 订阅设置要在 `dispose` 取消。
- 可能冲突的文件：`room_feed.dart`（E05.4 改 `:483`）；`areas_page.dart`（A09.4 系列界面任务）；`follow_refresher.dart`（I04 后续）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/I03.2` 或本机工作区；提交信息以 `[I03.2]` 开头（英文）；不推 master。
- 提交前：改过的包（`apps/pure_live`、加常量时 `packages/live_store`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

八条各做到没有；测试数量（改之前失败几个）；改了哪些文件；分区目录挪走后内存和切换的感受；FEATURES F-NET-03 的新状态；要在真机上看的；可能冲突的文件。
