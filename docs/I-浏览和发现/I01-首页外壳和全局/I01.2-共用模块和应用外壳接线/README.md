# I01.2 共用模块和应用外壳接线

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（工程整理 + 接线）
- 来源：I02.1～I08.1 各页面记录的“缺的共享服务”“留给后续”；`~/ref/notes/m13_notes.md` 的 “M13 shared” 条目
- 旧编号：M12.2、T07a.2
- 相关：I01.1（骨架）；I02.1～I08.1（各页面，各自写了一份卡片和菜单）；N01.1（多画面跨目录引用直播间的弹幕层）；之后的 O03.1（`share_plus`、`flutter_cache_manager`）、A09.1（卡片和卡片对话框的界面重做）；提交 `cc48756fb`；记录 [record.md](record.md)

## 目标

页面任务是并行做的，每页在自己目录里各写了一份卡片转换、卡片长按菜单、错误文字、取数逻辑（五份菜单、两套翻页取数）。把它们并成 `lib/shared/` 里的一份，让五个卡片页（热门、关注、分区房间、搜索、历史）行为一致；同时把启动页、启动后检查更新、关注核验、哔哩哔哩登录核验、定时关闭、图片请求头这些外壳上的线接好。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做之前（页面各写一份） | 现在（文件:行） |
|---|---|---|---|
| 卡片和长按菜单 | `lib/common/widgets/room_card.dart`：一个卡片，长按菜单只有分享、标签两个小图标 | 五个页面五份菜单（`popular/room_menu.dart` 338 行等） | 一份：I01.2 时 `shared/rooms/room_menu.dart`（497 行）；之后 A09.1 改成居中对话框 `CardDialog`，文件还在 `shared/rooms/room_menu.dart` |
| 卡片文字、标记、人数 | 各页各算 | 四份 `*_cards.dart` | `shared/rooms/room_texts.dart`（`platformName`、`readableAudience`、`roomMark`、`describeLoadError`……）、`room_cards.dart`（`AudiencePolicy`、`cannotPlayHere` `:20`） |
| 翻页取数 | 热门 `PopularController`、分区 `AreaRoomsController` 各一套 | `popular_feed.dart`、`area_rooms/room_feed.dart` 两套 | 一个 `RoomFeed`（`shared/rooms/room_feed.dart:251`），分区是 `AreaRoomSource`（`:215`），见 I02、I03 |
| 发现页隐藏不能播放的房间 | 热门和分区规则不同 | 两套 | 都按 `cannotPlayHere`（看该平台有没有 Cookie） |
| 图片请求头 | `common/utils/network_image_url.dart`：哔哩哔哩图带 Referer、所有图带桌面 UA | 没设，哔哩哔哩分区图、封面 403 | `shared/images.dart` 的 `networkImageHeaders`，`app.dart:183` 交给 `LiveUiConfig` |
| 启动页等关注核验 | `app_pages.dart`：最多等 350 毫秒 | 没有 | `startup.dart:21`、`:84` |
| 启动后检查更新 | 首页 | 没有 | `features/home/home_page.dart:75`（2 秒后，只在主窗口） |
| 哔哩哔哩登录核验 | `bilibili_account_service.dart`：启动 1 秒后 | 没有 | `startup.dart:85-91`、`verifyBilibiliLogin` `:116` |
| 定时关闭 | 服务启动时 | 没有 | `AppStartup.start` 里 `AutoExitTimer.instance.attach`（`startup.dart:74`） |

## 结果

- 做了什么（详见 [record.md](record.md)）：
  - 合并重复：删掉 10 个页面文件、挪走 5 个，`lib/` 净少约 940 行；共用模块 `shared/rooms/`（`room_texts.dart`、`room_cards.dart`、`room_feed.dart`、`room_menu.dart`、`share_code.dart`、`play_quality.dart`）、`shared/danmaku/`（多画面要用的弹幕层和设置面板）、`shared/images.dart`。
  - 卡片菜单统一（界面改进，用户授权）：标题、简介（升级 11-5）、平台和房间号、一列操作（进入、设置标签、分享、复制链接、页面自己的操作）、关注 / 取消关注（先确认、之后可撤销放回原位）。这部分后来由 A09.1 按设计重做成卡片对话框。
  - 统一后的规则 7 条：隐藏不能播放的房间、分区房间翻页（一次取到多一个能显示的为止，最多 5000）、每页都按 `roomMark` 标记、空标题写“未命名直播间”、人数换算一致、“已播时长”可选、“需登录”说明一致。
  - 外壳接线：图片请求头、清除图片缓存后换新缓存键（`imageCacheEpoch`）、启动页、启动后检查更新、首帧后关注核验、哔哩哔哩登录核验、定时关闭。
  - 翻译键删 119 个、加 37 个（`room_mark_*`、`load_error_*`、`room_*`）。
  - 小修：`live_ui` 的 `PureLiveScrollPhysics` 直接用时没有边界、列表能滚出内容（加 `live_ui/test/scrolling_test.dart` 2 个）。
- 提交 `cc48756fb`（2026-10-01）。
- 测试：应用 178 个（新 8 个：`test/shared/shared_test.dart` 7 个、`home_test.dart` 1 个）；`live_ui` 37 个。

## 验证

- 自动测试：`apps/pure_live/test/shared/shared_test.dart`（现在 8 个：标记、人数、错误说明、卡片和外观、卡片对话框、哔哩哔哩核验）；`test/features/home/home_test.dart` 的 `splash first when it is on, then home; start-up work and image settings are wired`（`:446`）。
- 真机：当时没装机。之后 S02.2、S02.3 在 K90 上走过五个卡片页的卡片、长按、关注和取消关注、哔哩哔哩封面（请求头）；哔哩哔哩登录过期的提示没有真机记录（要一个过期的 Cookie）。

## 留下的问题

- record.md“留给后续”现在的去向：`share_plus` 和 `flutter_cache_manager` → O03.1（已加，`apps/pure_live/pubspec.yaml:41`、`:74`）；卡片带开播时间和简介 → A09.1 和 I02.1 之后（`roomClockProvider`、卡片对话框里的简介）；工具箱、账号页各自 `i18n('site_$id')` 取平台名 → 现在已没有这种写法；直播间“看其他”用共用卡片 → A07.13（已合并，待真机）；热门的 `*_directory_scope` 说明改写 → 热门页用改写过的 `popular_scope_<平台>`（20 个键，`features/popular/popular_grid.dart:14-18` 优先取它，没有才用平台的 `directoryNoticeKey` 原文）；20 个 `*_directory_scope` 原文还在，见 [I02](../../I02-热门/README.md)。
- 菜单本身后来被 A09.1 换成居中对话框（`CardDialog`），本任务写的“一列操作”的样子已不是现在的样子；规则（先确认再撤销、未关注先问再设标签）保留。
- 首帧后才开始关注核验（不是 3.x 的服务启动时）：I04.1 记录“留给后续”里的一条，已由本任务做掉（`app.dart:95-97`、`startup.dart:84`）。
