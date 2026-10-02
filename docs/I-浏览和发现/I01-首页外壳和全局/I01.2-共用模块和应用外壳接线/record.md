# I01.2 共用模块和应用外壳接线

- 日期：2026-10-01
- 范围：`apps/pure_live`（新目录 `lib/shared/`、`lib/app/startup.dart`，各卡片页、直播间、多画面、启动页、首页、设置页的图片缓存）；`packages/live_ui` 只修 `PureLiveScrollPhysics`
- 来源：I02.1～I08.1 各页面记录的“缺的共享服务”“留给后续”，`~/ref/notes/m13_notes.md` 的 “M13 shared” 条目
- v3 对照：`lib/common/widgets/room_card.dart`（卡片和长按菜单、`FollowButton`、标签选择框）、`common/utils/share_command_handler.dart`（分享口令）、`common/utils/network_image_url.dart`（图片地址和请求头）、`common/services/settings/cache_controller.dart`（`imageCacheEpoch`）、`common/services/settings/bilibili_account_service.dart`（启动核验）、`routes/app_pages.dart`（启动页等关注核验 350 毫秒）、`modules/home`（启动后检查更新）

## 合并了哪些重复

M13 的页面并行开发，每页在自己目录里写了一份卡片转换、卡片菜单和文字。现在只留一份：

| 原来的文件（行数） | 内容 | 现在 |
|---|---|---|
| `popular/popular_rooms.dart`（231） | 卡片转换 `AudiencePolicy`、受限文字、`cannotPlayHere`、卡片外观；推荐页的 `PopularCatalog`、每页条数 | 共用部分 → `shared/rooms/room_cards.dart`；推荐页自己的部分 → `popular/popular_catalog.dart`（106） |
| `favorite/favorite_cards.dart`（112） | 平台名、人数简写、已播时长、受限/轮播/封禁/已下线标记、卡片转换、外观、字号 | `shared/rooms/room_cards.dart`、`room_texts.dart` |
| `history/history_cards.dart`（119） | 卡片转换、外观、图片地址规范化、人数简写、平台名、受限文字、房间短名 | 同上（图片地址用 `live_core` 已有的 `normalizeImageUrl`） |
| `search/search_cards.dart`（92） | 卡片转换、外观、人数简写、简化版图片地址、受限文字 | 同上 |
| `area_rooms/room_cards.dart`（204） | 卡片转换、外观、字号、人数简写、受限文字、卡片菜单 | 同上 + `shared/rooms/room_menu.dart` |
| `popular/room_menu.dart`（338）、`favorite/room_menu.dart`（334）、`history/history_room_menu.dart`（211）、`search/search_room_sheet.dart`（142）、上一行的菜单部分 | 五种长按菜单（关注按钮、标签选择框各写了两三份） | `shared/rooms/room_menu.dart`（497，一种菜单） |
| `popular/share_command.dart`（49） | 分享口令 | `shared/rooms/share_code.dart`（加系统分享接口） |
| `popular/popular_feed.dart`（422）、`area_rooms/room_feed.dart`（239） | 推荐页的分块取数 `PopularFeed`，分区页的翻页 `AreaRoomFeed`（两套“去重、刷新失败保留、加载更多、隐藏不可播放”） | `shared/rooms/room_feed.dart`：一个 `RoomFeed`；分区页的取数变成 `AreaRoomSource`（`areaRoomLoader` 不变） |
| `areas/areas_common.dart` 的 `describeLoadError`、`isLoginError`、`platformLabel`；`popular/popular_grid.dart` 的 `popularErrorText` | 两套列表错误说明、平台名 | `shared/rooms/room_texts.dart` |
| `search/search_capability.dart` 的 `searchPlatformName`、`settings/settings_catalog.dart` 的 `platformName` | 平台名 | `room_texts.dart` 的 `platformName(id, fallback:)` |
| `live_play/room_texts.dart`（130） | 平台名、人数、受限文字和原因、播放失败、未开播文字（多画面跨目录引用） | 挪到 `shared/rooms/room_texts.dart` 并并入上面几项 |
| `live_play/danmaku_overlay.dart`、`player_view.dart` 的 `danmakuLookOf`、`chat_panel.dart` 的 `DanmakuSettingsPanel`、`chat_feed.dart` 的 `retracts` | 多画面跨目录引用的飞行弹幕层和设置面板 | `shared/danmaku/danmaku_overlay.dart`、`danmaku_settings.dart` |
| `live_play/room_controller.dart` 的 `defaultQualityIndex`、多画面复制的 `defaultMultiviewQuality` | 默认画质选择 | `shared/rooms/play_quality.dart` |

合计：`lib/` 删了约 2400 行、加了约 1470 行（净少约 940 行）；删掉 10 个页面文件，挪走 5 个。

## 共用模块怎么用

| 文件 | 接口 | 谁在用 |
|---|---|---|
| `shared/rooms/room_texts.dart` | `platformName(id, fallback:)`；`readableAudience`（`5.6万`/`5.6k`，平台已带单位的也能换算）；`roomMark(room)`（平台已下线 → 轮播 → 封禁 → 受限类型）；`restrictionLabel`/`restrictionReason`；`liveDuration`（卡片上的“已播”）；`describeLoadError`、`isLoginError`（列表）；`failureText`、`offlineText`、`audienceFigures`、`startedAgo` 等（直播间、多画面）；`roomLabel`（对话框里的短名） | 所有卡片页、直播间、多画面、分区、设置、搜索 |
| `shared/rooms/room_cards.dart` | `AudiencePolicy`（人数口径：`of(settings)`、`rank`、`audienceOf`、`cardOf(room, now:)`）、`watchAudiencePolicy(ref)`；`cardAppearanceOf(settings, phone:)`、`watchCardAppearance(ref)`、`watchFontSizes(ref)`；`cannotPlayHere(room, signedIn:)`、`signedInOn(cookies, platform)`（发现页隐藏不能播放的房间） | 推荐、关注、分区房间、搜索、历史 |
| `shared/rooms/room_feed.dart` | `RoomFeed`（`refresh(count:)`、`ensure(count)`、`loadMore()`、`retry(count:)`、桌面分页 `goToPage`/`pageRooms`、`visible` 过滤、`maxRooms`）；推荐页的 `popularSourceFor`；分区页的 `areaRoomLoader` + `AreaRoomSource` | 推荐（每个平台一个）、分区房间 |
| `shared/rooms/room_menu.dart` | `showRoomMenu(context, store:, room:, onOpen:, detail:, actions:)`；单独可用的 `followRoom`、`unfollowRoom`（确认 + 撤销）、`editRoomTags`、`shareRoom`、`RoomTagPicker` | 推荐、关注、分区房间、搜索、历史（`detail` 是观看时间，`actions` 加“删除记录”） |
| `shared/rooms/share_code.dart` | `encodeRoomShareCode`（3.x 的 MessagePack 口令）；`SystemShare.sheet`（系统分享面板的接口，O03.1 加 `share_plus` 后在 `main` 里设置；没设置时复制口令） | 卡片菜单 |
| `shared/rooms/play_quality.dart` | `defaultQualityIndex` | 直播间、多画面 |
| `shared/danmaku/` | `DanmakuOverlay`、`DanmakuLook`、`retracts`、`danmakuLookOf(ref)`、`DanmakuSettingsPanel` | 直播间、多画面 |
| `shared/images.dart` | `networkImageHeaders`（3.x：`hdslb.com` 带 Referer，所有图片带桌面浏览器 UA）、`imageCacheEpoch` | `app.dart`、设置页的图片缓存 |

页面目录里只留页面自己的东西（例如推荐页的 `PopularCatalog`、历史页的分组和观看时间、关注页的分组规则）。以后加卡片页：`watchAudiencePolicy(ref).cardOf(room)` + `watchCardAppearance(ref)` + `showRoomMenu(...)`。

## 卡片菜单（界面改进，用户授权）

以 v3 的 `RoomCard.onLongPress` 为基线，五页统一成一种：

- 标题：平台图标 + 主播名（缺名时平台名）。
- 内容：标题框里是直播标题和**简介**（UPGRADES 11-5，原来只有搜索页显示）；下面一行是平台、房间号（可选中复制）、分区、页面附加信息（历史页的观看时间）和**房间标记**（红色）。
- 操作改成一列：**进入直播间**、**设置标签**、**分享**、**复制链接**（有链接时）、页面自己的操作（历史页“删除这条记录”）。v3 只有分享、标签两个小图标，进入、复制要退出菜单；现在一处都有。
- 底部：关注/取消关注 + 关闭。**取消关注先确认，之后提示条可“撤销”**，放回原位置（原来只有关注页有撤销）。关注后提示“已关注 某某”。
- 设置标签：未关注的房间先问是否关注（v3 `tags_need_follow_tip`），关注后打开标签选择；“新建标签”打开标签页的编辑框（`showTagEditor`，名字、描述、重名检查同标签页），建好自动选中；右上角进标签管理页。
- 分享：手机上有系统分享面板时用它，否则复制分享口令（v3 桌面复制、手机分享）；口令格式同 v3。
- 搜索页原来是底部弹出面板，现在和其他页一样是对话框；历史页、分区页的菜单补上了分享和标签。

## 统一后的规则（行为变化）

| 内容 | 原来 | 现在 |
|---|---|---|
| 发现页隐藏不能播放的房间 | 推荐页：轮播 + 不能播放的受限类型，需登录/年龄验证只在没登录时隐藏；分区页：固定一组受限类型，轮播不隐藏，登录类始终显示 | 都按推荐页的规则（`cannotPlayHere`，看该平台有没有 Cookie） |
| 分区房间翻页 | 每次取一页，被隐藏的房间多时靠列表底部再触发下一页 | 和推荐页一样一次取到至少多一个能显示的房间为止（每次最多 20 次请求），最多保留 5000 个；连续两页没有新房间才算到底 |
| 卡片标记 | 关注页标“已下线/轮播/封禁/受限”，其他页只标受限（推荐页另标轮播） | 每页都按 `roomMark` 标；关注页对未开播的受限房间也标 |
| 卡片标题为空 | 历史、搜索显示“未命名直播间”，其他页空着 | 都显示“未命名直播间” |
| 人数简写 | 卡片只换算纯数字；直播间能换算“5.6万”这类并有“亿”“M” | 都用直播间的换算（英文 `k` 照 v3 的 `count_k`） |
| 关注页“已播时长” | 只在关注页 | `cardOf(room, now:)` 可选，现在仍只有关注页传 `now` |
| 推荐页“需登录”说明 | `login_required_subtitle`（3.x 的“已被风控隐藏”） | `load_error_login`（“该平台要登录后才能查看……”），各列表页一致 |

## 翻译键

两个翻译文件仍按键排序、4 空格缩进，中英文键一致（`i18n_test` 的“差 4 个键”不变）。删 119 个，加 37 个：

| 新键 | 代替 |
|---|---|
| `room_mark_{adult,app_only,needs_login,paid,password,private,region_blocked,subscribers_only,unplayable,carousel,banned,retired}` | `area_rooms_restriction_*`（10）、`history_restriction_*`（9）、`search_restriction_*`（9）、`popular_restriction_*`（9）、`favorite_mark_*`（12）、`live_play_restriction_*`（10）、`popular_status_carousel` |
| `room_mark_*_hint`（9） | `live_play_restriction_*_hint`（10，含空的 `none`） |
| `load_error_{login,rate_limited,cookie,risk,region,changed,network,unknown}` | `areas_error_*`（7）、`popular_error_*`（6） |
| `room_live_minutes`、`room_live_hours` | `favorite_live_*` |
| `room_followed`、`room_unfollowed`、`room_undo`、`room_open`、`room_tags_empty`、`room_tags_new` | `area_rooms_follow_done`、`area_rooms_unfollow_done`、`area_rooms_link_copied`、`popular_followed`、`popular_unfollowed`、`popular_no_tags`、`favorite_tags_empty`、`favorite_unfollowed`、`favorite_undo`、`history_followed`、`history_unfollowed`、`history_open_room`、`search_followed`、`search_unfollowed` |

不再使用的 3.x 旧键一并删除：`search_coverage_*`（13 个；`search_coverage_acfun` 搜索页还在用，保留）、`multiview_error_resolve`、`multiview_error_start`、`toolbox_support_content`、`toolbox_room_jump`、`toolbox_get_parse`、`toolbox_detect_link`、`app_legalese`。`search_room_enter` 搜索页的链接提示条还在用，保留。

## 外壳接线

| 接线 | 做法 | 状态 |
|---|---|---|
| 图片请求头 | `app.dart` 的 `LiveUiConfig.imageHeaders = networkImageHeaders`（哔哩哔哩分区图、封面不再 403） | 完成 |
| 刷新封面 | 设置页清除图片缓存时 `imageCacheEpoch` 加一，`app.dart` 跟着改 `LiveUiConfig.imageCacheEpoch`，屏幕上的封面和头像换新缓存键重新下载（v3 同） | 完成；磁盘文件的清除（`ImageCacheTools.clearDisk = DefaultCacheManager().emptyCache`）要应用直接依赖 `flutter_cache_manager`，会改根 `pubspec.lock`，留给 O03.1 |
| 启动页 | `buildAppRouter(initialLocation: splashInitialLocation(settings))`；启动页离开前最多等 350 毫秒首轮关注核验（`AppStartup.followCheck`，v3 `app_pages.dart`） | 完成 |
| 启动后检查更新 | 首页首帧后，主窗口（`launch.isPrimary`）等 `startupUpdateCheckDelay`（2 秒）调 `checkForUpdateOnStartup`；离开首页时取消 | 完成 |
| 关注核验 | `AppStartup.start()` 在应用首帧后 `ref.read(favoriteControllerProvider)`（每个窗口，同 v3）；`FavoriteController.firstCheck` 给启动页等待 | 完成 |
| 哔哩哔哩 Cookie 核验 | 启动 1 秒后 `verifyBilibiliLogin`（复用 `accountVerifierProvider`、`AccountActions`）：有效记 uid，失效提示 `bilibili_login_expired` 并退出登录，失败提示 `bilibili_user_info_failed`（同 v3）；Cookie 中途变了不处理 | 完成 |
| 定时关闭 | `AppStartup.start()` 里 `AutoExitTimer.instance.attach(store.settings)` | 完成 |
| 系统分享面板 | `SystemShare.sheet` 接口已留，菜单会用它 | 留给 O03.1（`share_plus`） |
| 定时刷新封面（`autoRefreshThumbnails`） | 要磁盘缓存清除，见上 | 留给 O03.1 |

`AppStartup` 在 `lib/app/startup.dart`，由 `appStartupProvider` 持有，应用退出时取消等待中的核验和定时关闭。

## 小修

- `live_ui` 的 `PureLiveScrollPhysics`：没经过 `applyTo` 直接用时（作为别的物理效果的 `parent`，或作为滚动行为的默认物理效果）是一个没有边界的 `ScrollPhysics`，列表可以滚出内容（I02.1 发现；历史页、分区页正是 `AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics())`）。现在实例本身把边界、惯性、拖动阈值交给平台的物理效果（iOS/macOS 回弹，其他硬边），`applyTo` 不变。加了 `live_ui/test/scrolling_test.dart`（2 个）。
- `docs/I-浏览和发现/I01-首页外壳和全局/I01.1-应用骨架/record.md`：删掉“启动页暂不出现”“启动时不检查更新”“IPTV 库暂时在内存里”三条有意差异和“启动后检查更新”“IPTV 库的持久化”两条去向，结尾指向本记录。
- D01.13、D01.15、D01.17、D01.30 记录：“多画面弹幕是否接入 → M13”改为已完成（N01.1）。

## 测试

- 应用 `flutter test`：178 个全部通过（原 170 个 + 新 8 个）；`flutter analyze` 无问题。
- 新增 `test/shared/shared_test.dart`（7 个）：房间标记、人数换算（中英文、带单位）、列表错误说明；卡片（缺标题、已播时长、标记）和卡片外观（预设、坏值回退）；卡片菜单（简介、复制链接、分享口令、页面操作；未关注先关注、标签页编辑框新建标签并选中、取消关注确认和撤销）；哔哩哔哩核验（有效记 uid、网络失败提示且保留、失效退出）。
- `home_test.dart` 加 1 个：启动页开着时先进启动页再进首页，首帧后开始关注核验，图片请求头和缓存代数传到 `LiveUiScope`，2 秒后的更新检查没网时不打扰。
- 改了的断言：分区房间的取数测试改用 `RoomFeed` + `AreaRoomSource`（登录类房间在“已登录”时显示）；关注、推荐、历史、搜索的菜单测试改用统一菜单的键（`room-menu-*`、`room-tags-*`、`unfollow-confirm`）和新提示文字；历史、搜索的卡片测试改用 `AudiencePolicy.cardOf`；用 `PureLiveApp` 的推荐、分区、首页测试关掉启动页（默认开）。
- `live_ui`：37 个全部通过。

## 留给后续

| 内容 | 去向 |
|---|---|
| `share_plus`（`SystemShare.sheet`）、`flutter_cache_manager`（磁盘缓存清除、定时刷新封面） | O03.1 |
| `live_ui` 的 `RoomCardData` 加开播时间、简介字段（现在已播时长接在主播名后，简介只在菜单里） | 需要时改 `live_ui` |
| 工具箱（`toolbox_page.dart`）、账号（`account_platforms.dart`）还各自 `i18n('site_$id')` 取平台名，结果相同，没有改 | 顺手时换成 `platformName` |
| 直播间“看其他”弹窗、推荐房间用卡片时直接用 `room_cards.dart`/`room_menu.dart` | M13.3b |
| 推荐页的 `*_directory_scope` 说明文字改写（14-6、20-6） | 平台文字整理 |

## 合并时注意（冲突点）

- `assets/translations/zh.json`、`en.json`：删改了上面这些键；其他分支加键时按键名排序合并即可，删掉的键如果别的分支还在用要换成新键。
- 挪走的文件：`pages/live_play/room_texts.dart`、`danmaku_overlay.dart`（M13.3b 直播间第二部分会改它们，要改到 `lib/shared/` 下）；`chat_panel.dart` 的 `DanmakuSettingsPanel`、`player_view.dart` 的 `danmakuLookOf` 已挪到 `shared/danmaku/danmaku_settings.dart`。
- `lib/app/app.dart`、`lib/home/home_page.dart`、`pages/splash/splash_page.dart`、`pages/favorite/favorite_controller.dart`、`pages/settings/data_tools.dart`：O03.1（插件、桌面外壳）也会改 `app.dart`/`main.dart`。
- 测试：`home_test.dart`、`popular_test.dart`、`areas_test.dart` 的启动辅助函数加了“关掉启动页”一行。
