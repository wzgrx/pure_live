# I03.1 分区：分区列表、分区房间、热门分区

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/areas/`（11 个文件）、`lib/modules/area_rooms/`（3 个）、`lib/modules/hot_areas/`（3 个）和它们用到的 `common/base/`、`plugins/area_pic_mapper.dart`、`common/utils/category_artwork.dart`
- 旧编号：M13.5、T07c.1
- 相关：I01.1（路由 `/areas`、`/favoriteAreas`、`/area_rooms`、`/hot_areas`）；I01.2（卡片、菜单、取数挪到 `shared/rooms/`，分区房间改用 `RoomFeed`）；E05.1（类型化错误 `NeedsLogin`、`RiskControl`）；之后的 A09.4、A09.5、A09.6（界面重做）；提交 `023936ebe`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的分区三页（分区列表、分区房间、关注分区）和“平台显示”，并修掉分区房间漏房间的三个平台问题（斗鱼、SOOP、快手）、没参数就崩、靠字符串判断“要登录”、刷新失败整页变错误这几条 3.x 问题。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 分区目录 | `areas_list_controller.dart`：`getCategories(1, 1000)`，每个平台一个 GetX 控制器 | `AreaCatalog`（`ChangeNotifier`），刷新合并、按 id 保留选中、失败保留 | 同（`features/areas/area_catalog.dart:11`），放在页面 State 里（`areas_page.dart:52`） |
| 斗鱼分区房间 | `area_rooms_binding.dart:30-31`：每页 120 个只切出 40 个（升级 A-1） | 整页显示，逐页请求 | `shared/rooms/room_feed.dart:179` `areaRoomLoader` |
| SOOP | `:35`、`area_rooms_controller.dart:57`：按 60 算页号却只要 30 个（A-4） | 每页 60 | `areaRoomPageSize`（`room_feed.dart:163`） |
| 快手 | “全部数据”控制器只请求一次（A-2） | 逐页请求 | 同上 |
| 没有路由参数 | `Get.arguments[0]` 直接崩 | 说明“没有收到要打开的分区” | `area_rooms_page.dart:28-44` |
| 要登录 | 错误文字里有没有 `-352`、`NoSuchMethodError`（`area_rooms_controller.dart:22-26`） | 按 `NeedsLogin`、`RiskControl` | `room_texts.dart:153` `isLoginError` |
| 刷新失败 | 整页变错误 | 保留内容，错误在上方或底部 | 同 |
| 借图 | `area_pic_mapper.dart`：同名、别名、包含、相似度 | 同名、别名、包含；不做相似度 | `area_artwork.dart:49` `AreaPictures` |
| 抖音分区 | 合成一页 | 分类标签 | A09.4 设计照 3.x 合成一页，合并后又改回分类标签（`427334723`，C-12 之后约 156 个分区） |
| 分区筛选、刷新按钮 | 没有 | 分类行右边加筛选和刷新 | A09.4 照 3.x 去掉入口；`filterAreas`（`area_catalog.dart:114`）还在、没有调用 |
| 分区房间翻页 | 电脑页码、手机连续 | 都改成连续加载 | A09.5 电脑改回页码（`RoomFeedView`） |
| 分区房间取数 | `AreaRoomsController` | 自己的 `AreaRoomFeed` | I01.2 并进 `RoomFeed` + `AreaRoomSource`（`room_feed.dart:215`） |
| “关注分区”按钮 | 关注后缩成头像 | 带数量、心形角标 | 不带数量（`FollowPill`，A09.4、A09.6） |
| 卡片长按 | 分区卡片无菜单；房间卡片菜单 | 分区卡片长按直接关注 / 取消；房间卡片自己的菜单 | 分区卡片用卡片对话框（`areas_common.dart:50`，A09.4 X3）；房间卡片用共用对话框（A09.1） |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：分区列表（平台标签、首选平台、分类左右滑、800 毫秒预取、后台回来刷新、点分区的三种去向、借图和两态图标）；关注分区（“全部”加各平台、按 id 保留标签）；分区房间（原生目录、游标、按页号三种取法，去重和改分区名，隐藏不能播放的，卡片和菜单，关注分区按钮，目录说明）；平台显示（开关、拖动、至少一个、首选平台跟着改）。
- 修了 3.x 问题 8 条（record.md“v3 问题及处理”）。
- 有意差异 3 条：借图不做相似度、分区房间最多 5000 个、学到的图存在 meta `areas.pictures`。
- 已批准的升级：A-1、A-2 完成；A-4、8-10、10-5、19-1、24-5、26-1 分区页部分完成；20-1、25-1、33-1、31-4、C-12 显示完成；统一原则“受限”分区页完成。
- 翻译键中英文各 38 个（`area_rooms_*`、`areas_*`、`hot_areas_*`）；其中 `area_rooms_restriction_*` 等由 I01.2 换成通用的 `room_mark_*`。
- 提交 `023936ebe`（2026-10-01）。当时的 `area_rooms/room_cards.dart`、`room_feed.dart` 已由 I01.2 挪到 `shared/rooms/`；现在三个目录 10 个文件 1967 行。
- 测试：当时 11 个（`areas_test.dart`）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/areas/areas_test.dart` 14 个（之后 A09.4～A09.6 加的：抖音分类、没有关注时的说明、平台显示页的布局）。
- 真机：当时没装机。S02.3（[记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）走过分区和分区房间；关注分区、平台显示的拖动、电脑页码没有真机记录（见[子分类说明](../README.md)“已知问题”）。

## 留下的问题

- record.md“留给后续”现在的去向：共享的卡片、菜单、取数、错误文字 → I01.2（完成）；卡片菜单的分享和标签 → I01.2 统一菜单、A09.1 卡片对话框（完成）；图片请求头 → I01.2（`app.dart:183`，完成）；`*_directory_scope` 原文改写 → 热门用改写的 `popular_scope_*`，分区房间仍用原文（`area_rooms_page.dart:96`），没有任务；热门、搜索页的 A-4、10-5、19-1 余下部分 → I02.1、I05.1（完成）；Windows 和 Android 真机检查 → X01、S02。
- 读代码发现的三个小问题（分区目录切标签重新请求、借图写回的竞态、分区房间只读一次隐藏设置且没有流量提示）记在[子分类说明](../README.md)“已知问题”，没有任务。
