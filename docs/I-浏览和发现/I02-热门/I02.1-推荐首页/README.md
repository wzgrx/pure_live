# I02.1 推荐首页（热门）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/popular/`（4 个文件 541 行）和它用到的 `lib/common/base/`（翻页控制器、桌面页码栏，约 2150 行）、`common/widgets/room_card.dart` 的菜单、分享口令
- 旧编号：M13.1、T07b.1
- 相关：I01.1（骨架和服务）；I01.2（卡片、菜单、取数挪到 `shared/rooms/`）；I03.1（分区房间共用 `RoomFeed`）；之后的 A09.2（热门界面）、A09.1（卡片）、O03.1（`share_plus`、`connectivity_plus`）；提交 `414996596`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的推荐首页：平台标签、每个平台的推荐列表（按平台选翻页方式）、按人数排序、手机下拉刷新和加载更多、电脑页码栏、卡片和长按菜单；同时修掉审查出的 3.x 问题（7 条）：翻页漏房间、出错只写异常原文、刷新失败看不出列表是旧的、不满一屏加载不了更多、平台全关时一片空白。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 每个平台的取数 | `popular_controller.dart:40-90` 按平台选四种控制器（目录、固定窗口、全部、远程） | 一个 `PopularFeed` + 四种 `RoomSource` | I01.2 把它并成 `shared/rooms/room_feed.dart` 的 `RoomFeed`（`:251`）和 `popularSourceFor`（`:146`） |
| 通用翻页 | `server_remote_page_controller.dart:102`、`:209`：每次只要“还缺的条数”，页号照加，平台切页不衔接 | 每次固定 30 个，页号加一 | `PagedSource`（`room_feed.dart:92`） |
| 数据的寿命 | GetX 控制器常驻 | `popularCatalogProvider` 保存每个平台的列表，切首页菜单不重新请求 | `features/popular/popular_catalog.dart:91` |
| 出错 | `base_controller.dart:49-68`：异常原文，靠字符串里有没有“未登录”判断要登录 | 按 `SiteError` 种类说原因 | `shared/rooms/room_texts.dart:140` `describeLoadError` |
| 刷新失败 | 弹一次提示，列表看不出是旧的 | 保留列表，顶部横幅可重试 | `RoomFeed.refresh`（`room_feed.dart:413`）、`refreshErrorBanner`（`room_grid.dart:329`） |
| 不满一屏 | 上拉加载要拖动，列表不能滚就加载不了 | 自动取下一块，底部“加载更多” | `RoomFeedView` 离底 600 自动加载（`room_grid.dart:621`） |
| 平台标签 | 在标题位置，手机一次只看得到三个左右 | 挪到标题栏下方占满宽度，加“全部平台” | A09.2 c1 又放回标题位置，c2 保留“全部平台”（`popular_page.dart:177-200`、`PlatformPicker` `:225`） |
| 分页 | 电脑页码栏；“显示跳转按钮”设置没读 | 页码栏，按设置显示跳转 | 页码栏在 `shared/rooms/paging.dart`，热门、关注、分区、分区房间共用 |
| 分享、流量提示、开播时间 | 手机系统分享面板；请求前查断网和移动网络（`base_controller.dart:29-47`） | 只复制口令；没有流量提示；卡片没有开播时间（缺插件和字段） | 都已做：`SystemShare.sheet`（`lib/platform/plugins.dart:38`，O03.1）、`MobileDataBanner`（`room_grid.dart:221`）、“已播”用 `roomClockProvider`（`room_grid.dart:86`） |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：服务照 I01.1 的取法；数据放在 provider 里；按平台选翻页（原生目录、固定窗口：斗鱼 40、虎牙 120、SOOP 60、TwitCasting 60、Twitch 100、CC 100、抖音 20、一次取完：快手和网络电视、其余每次 30）；一份列表两种翻页（手机接着取、电脑切片）；刷新先建新列表再替换；隐藏不能播放的直播（统一原则）；卡片人数和受限标记；页码设置。
- 3.x 的功能逐项对照（record.md“与 v3 的功能对照”15 行）：14 行“有”，当时缺的系统分享面板和移动网络提示后来补上。
- 修了 3.x 问题 7 条（record.md“审查发现的 v3 问题”）。
- 界面改进 12 条（record.md“界面改进”）：后来由 A09.2 按设计逐条定稿（c1～c9），标签位置等有改回。
- 已批准的升级：统一原则“受限”“翻页”“说明文字”的热门部分；1-1、3-1、10-5、14-3、19-1、19-4、20-6、20-8、21-1、24-2、24-5、26-1、26-8、26-9、32-4。
- 提交 `414996596`（2026-10-01）。当时的文件 `popular_feed.dart`、`popular_rooms.dart`、`room_menu.dart`、`share_command.dart`、`pagination_bar.dart` 已由 I01.2 挪到 `shared/rooms/`（`room_feed.dart`、`room_cards.dart`、`room_menu.dart`、`share_code.dart`、`paging.dart`）；现在 `features/popular/` 只剩 3 个文件 517 行。
- 测试：当时 11 个（`popular_test.dart`）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/popular/popular_test.dart` 19 个（之后 A09.2、P02、P05、M13.16 加的）；`test/shared/room_lists_test.dart` 2 个。
- 真机：当时没装机。S02.2 冒烟（[记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）看过“热门：哔哩哔哩列表、卡片、热度、到底部按钮”，通过；切平台、下拉刷新在 S02.3 走过。移动网络提示、刷新失败横幅、电脑页码栏没有真机记录（见[子分类说明](../README.md)“已知问题”）。

## 留下的问题

- record.md“留给后续”现在的去向：系统分享面板 → O03.1（完成）；移动网络提示和断网检查 → O03.1 加了 `connectivity_plus`、`MobileDataNotice`（完成，但只在刷新时查，见子分类“已知问题”第 1 条）；开播时间 → `roomClockProvider`（完成）；卡片、菜单、取数挪到共享位置 → I01.2（完成）；分区页的说明原文 → 还是 `*_directory_scope` 原文（`area_rooms_page.dart:96`），热门用改写的 `popular_scope_*`；标签的编辑和删除 → 标签管理页（I07.1、A09.10）。
- `PureLiveScrollPhysics` 当 `parent` 时没有边界 → I01.2 已修（`live_ui/test/scrolling_test.dart`）。
