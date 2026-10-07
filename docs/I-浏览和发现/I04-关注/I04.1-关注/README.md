# I04.1 关注

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/favorite/`（`favorite_controller.dart` 842 行、`favorite_page.dart` 319 行、`favorite_startup_policy.dart` 127 行、`room_grid_view.dart` 139 行）和它用到的卡片菜单、标签选择框、`local_reactive_page_controller.dart`、`base_page_view.dart`
- 旧编号：M13.2、T07e.1
- 相关：I01.1（首页信号 `HomeSignals`、`followsReady`）；J02.1（身份迁移、`FollowStore.update` 合并）；E05.2（`pendingAfterError`）；I01.2（卡片和菜单挪到 `shared/rooms/`、首帧后核验）；之后的 A09.3（关注界面）、A07.13（直播间“看其他”用这里的刷新）；提交 `dc167d266`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的关注页（首页第一个标签）：三组（已开播、录播、未开播）、平台和标签筛选、排序、启动核验和四种刷新，并修掉 3.x 刷新时清空名字头像、已下线平台一直“状态待确认”、平台栏漏平台、刷新失败用户看不到这几个问题。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 刷新结果写回 | `favorite_startup_policy.dart:82`、`:121`：整条替换，缺的名字、头像被清空 | `FollowStore.update`（`LiveRoom.mergeFrom`）合并 | `features/favorite/favorite_controller.dart:265` |
| 失败的房间 | `:123` 手写 `status: false` 快照 | `pendingAfterError()` | `follow_refresher.dart:79` |
| 已下线平台 | 每次都请求、永远“状态待确认”（`favorite_controller.dart:813`） | 不请求、归未开播、标“平台已下线” | `follow_refresher.dart:64`、`favorite_rules.dart:13` |
| 平台栏 | 只列平台列表里的（`:67-75`） | 列出所有有关注的平台 | `favorite_rules.dart:22`（A09.3 c9） |
| 刷新入口 | 下拉只在手机或窄屏；宽屏没有可见入口 | 平台栏右侧加刷新按钮 | 按钮已没有；电脑翻页栏有“刷新”（`favorite_page.dart:542`），手机下拉 |
| 分页 | 本地数据套服务器分页 | 去掉分页，一次给出全部 | A09.3 c1 照 3.x 在电脑上恢复翻页栏（`favorite_page.dart:524-544`），手机一次全部 |
| 刷新失败 | 只写日志（`:821-838`） | 提示“N 个直播间暂时获取失败” | `favorite_page.dart:142-146`（A09.3 c11） |
| 没有关注 | 按钮“重试”（`favorite_page.dart:289-297`） | “搜索直播” | 同（A09.3 c7） |
| 启动核验 | 应用首帧后开始 | 第一次打开关注页时才开始 | 首帧后开始（I01.2：`lib/app/startup.dart:84`） |
| 直播间“看其他”要求刷新 | 事件 `refresh_favorite_rooms`（`:238`） | 留了 `refreshAll()` | 已接上（`lib/app/app.dart:86-93`，`refreshAll(visible: false)`） |
| 卡片和菜单 | `room_card.dart` | 自己的 `favorite_cards.dart`、`room_menu.dart` | I01.2 挪到 `shared/rooms/room_cards.dart`、`room_menu.dart`；之后 A09.1 卡片对话框 |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：`favorite_rules.dart`（纯函数：分组、平台栏、排序、筛选、可选标签、数量）、`follow_refresher.dart`（一个房间一个请求、并发、10 秒、5 分钟冷却、已下线不请求、`bindToFollow`）、`favorite_controller.dart`（整个应用一个、监听存储、一轮一次写回、四种时机和排队合并）、页面、卡片和菜单。
- 3.x 功能逐项对照（record.md 16 行）：除分享（当时只有复制链接，后来 I01.2 统一菜单补上）外都有。
- 修了 3.x 问题 8 条（record.md“审查发现的 v3 问题”）；界面改进 11 条（之后由 A09.3 定稿，分页和刷新按钮两条改回或去掉）。
- 已批准的升级：统一原则“受限”、1-1、3-1、17-1、23-1、28-2、X-2 关注页完成；7-9、10-3、25-12、33-7（开播时间）关注页部分完成。
- 没有新设置键，3.x 数据不用额外迁移。
- 提交 `dc167d266`（2026-10-01）。
- 测试：当时 11 个（`favorite_test.dart`）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/favorite/favorite_test.dart` 16 个（之后 A09.3、A07.2 加的：手机标签不截断、标签并到顶栏、“全部”卡片标平台、未开播紧凑行、点卡片带本组房间、没有在播的说明）。
- 真机：record.md 写“本次没装机”。之后 S02.2、S02.3（[记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）在 K90 上看过关注冷启动、核验、下拉刷新、取消关注和撤销。定时刷新、回到前台刷新没有真机记录。

## 留下的问题

- record.md“留给后续”现在的去向：卡片和菜单共用 → I01.2（完成）；分享 → I01.2、O03.1（完成）；首帧后核验 → I01.2（完成，`startup.dart:84`）；直播间“看其他”刷新 → `app.dart:86-93`（完成）；`RoomCardData` 开播时间 → `roomClockProvider`（完成）；图片请求头 → I01.2（完成）；真机检查 → S02.3（部分），其余见[子分类说明](../README.md)“已知问题”。
- 平台没有适配器时失败不进冷却（`follow_refresher.dart:91-93`）：见子分类“已知问题”，没有任务。
