# I04.1 页面：关注

- 日期：2026-10-01
- 目标：`apps/pure_live/lib/features/favorite/`（路由 `RoutePath.kFavorite`，也是首页第一个标签）
- v3 来源：标签 `v3.2.11` 的 `lib/modules/favorite/`（`favorite_controller.dart` 842 行、`favorite_page.dart` 319 行、`favorite_startup_policy.dart` 127 行、`room_grid_view.dart` 139 行），以及它用到的 `common/widgets/room_card.dart` 的长按菜单和标签选择框、`common/base/local_reactive_page_controller.dart`、`base_page_view.dart`（分页、进度条、回到顶部）、`modules/home/home_page.dart`（再点关注刷新）

## 做法

| 文件 | 内容 |
|---|---|
| `favorite_rules.dart` | 纯函数：分组（`groupOf`：`LiveRoom.followGroup`，已下线平台一律归入未开播）、平台栏（`platformTabs`）、排序（`FollowOrder`：直播中和回放按人数，选了标签时先按标签顺序，同 v3）、筛选（`roomsOf`）、可选标签（`tagsOf`）、各分组数量 |
| `follow_refresher.dart` | 刷新：一个房间一个请求（有 `LiveSiteRoomRefresher` 用 `getRoomDetailForRefresh`，否则 `getRoomDetail`），同时最多 `maxConcurrentRefresh` 个，每个平台一个适配器，单个请求 10 秒超时，失败的房间 5 分钟内不再请求（手动、启动、回到前台的刷新不受限），都同 v3。成功的结果先 `bindToFollow`（平台回答了另一个房间号时按关注的身份写回）再 `withAudienceFallbackFrom`；失败的用存下的房间 `pendingAfterError()`；已下线平台不请求 |
| `favorite_controller.dart` | `FavoriteController`（`ChangeNotifier`），由 `favoriteControllerProvider` 提供，整个应用期间只有一个（首页只构建当前标签，页面会被销毁重建；v3 也是 GetX 单例）。监听 `store.follows.watchAll()`、`store.tags.watchAll()`、`watchAssignments()` 和设置变化；一次刷新的全部结果用一次 `store.follows.update`（`LiveRoom.mergeFrom`）写回，卡片不会随单个请求完成而跳动（同 v3） |
| `favorite_page.dart` | 页面：标题栏的三个状态标签（已开播、录播、未开播），平台栏 + 刷新按钮，标签条，每个平台一个网格（左右滑动切换平台）；空状态、骨架屏、刷新进度、回到顶部 |
| `favorite_cards.dart` | `LiveRoom` → `RoomCardData`（人数格式化同 v3 `readableCount`，受限类型等标记，已播时长，没有名字时显示平台名）、按设备取卡片外观（同 v3 `RoomCardSettingsController.resolve`）、字体大小 |
| `room_menu.dart` | 卡片长按/右键菜单：设置标签（可就地新建标签、可去标签管理）、复制链接、取消关注（确认后可撤销） |

刷新时机：

| 时机 | 范围 | v3 |
|---|---|---|
| 启动（第一次打开关注页时） | 全部；先等 `AppServices.followsReady`（身份迁移），期间卡片显示“正在核验” | 同（v3 在应用首帧后就开始） |
| 下拉、刷新按钮、再点首页的“关注”（`HomeSignals.favoritesReselected`） | 当前平台和标签（不分状态） | 同（v3 没有刷新按钮） |
| 定时（`autoRefreshFavorite`、`autoRefreshInterval`） | 全部，不显示进度，遵守失败冷却 | 同 |
| 回到前台（`HomeSignals.resumedAfterBackground`，设置 `refreshFavoriteOnResume`） | 全部；距上次全部刷新不到 15 秒不刷 | 同（v3 自己监听生命周期） |

同一时间只跑一轮刷新；正在跑“全部”时再来的请求等它结束后直接返回（v3 同样合并到启动那一轮），其他情况排队。

## 与 v3 的功能对照

| v3 功能 | v4 |
|---|---|
| 标题栏三个状态标签（已开播、录播、未开播），手机上左边菜单、右边搜索菜单 | 有；标签上加了数量 |
| 平台栏：“全部”+ 有关注的平台，平台列表变化时按 id 保留当前平台 | 有；列出所有有关注的平台（见问题 3） |
| 标签条：当前状态和平台下关注用到的标签，按标签顺序；切换平台或状态时回到“全部”；标签被删时回到“全部” | 有 |
| 网格：列数随宽度（1～4，紧凑 2～5）、间距设置、卡片外观设置、字号 | 有；卡片高度按字号算（A01.1 问题 10） |
| 排序：直播中、回放按人数（真实在线设置），选了标签先按标签顺序；未开播按关注顺序 | 有 |
| 启动核验：卡片显示“正在核验”，留在原分组；失败的“状态待确认” | 有 |
| 下拉刷新（手机或窄于 680） | 有 |
| 再点“关注”刷新、定时刷新、回到前台刷新、失败冷却、并发上限、10 秒超时 | 有 |
| 空状态：没有任何关注；当前筛选为空（按状态的标题、关注数量）；有未开播时“查看未开播”，否则“重试” | 有；没有任何关注时按钮改为“搜索直播” |
| 点卡片进直播间 | 有（`AppNavigator.toLiveRoomDetail`，已下线平台提示） |
| 长按/右键菜单：主播、标题、房间号、设置标签（可新建）、关注/取消关注、分享 | 有；分享改为复制链接（见“留给后续”） |
| 关注或房间在别处变化后刷新显示（v3 事件 `refresh_room_changed`、关注列表变化） | 有：直接监听存储 |
| 直播间“看其他”弹窗发事件 `refresh_favorite_rooms` 要求刷新 | 提供 `favoriteControllerProvider.refreshAll()`，直播间（M13）调用 |
| 回到顶部按钮（设置 `page_show_scroll_top`） | 有 |
| 分页：桌面翻页、手机加载更多、每页数量选择 | 去掉（见问题 6） |
| 启动页最多等 350 毫秒核验结果 | 启动页（M13）可等 `favoriteControllerProvider` 的首轮刷新 |
| Firebase 账号同步读关注 | 不需要（I01.1 已去掉 Firebase） |

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 刷新结果整条替换存下的房间，结果里缺的名字、头像、标题被清空（京东、Steam 等只给占位名的平台重启后显示占位名） | `favorite_startup_policy.dart:82`、`:121` | `updated.copyWith(tagIds: …)` 只保留了标签 | 用 `FollowStore.update`（`LiveRoom.mergeFrom`）：空值和占位值不覆盖存下的值（m13_notes、UPGRADES X-2） |
| 2 | 刷新失败改成 `status: false` + 未知，`watching` 的默认 `'0'` 留着 | `favorite_startup_policy.dart:123` | 手写的失败快照 | `LiveRoom.pendingAfterError()`（E05.2） |
| 3 | 平台栏只列“平台列表”设置里的平台：用户从平台列表去掉的平台、已下线平台的关注只能在“全部”里找到 | `favorite_controller.dart:67-75` | 复用了首页平台列表 | 列出所有有关注的平台：平台列表里的按其顺序在前，其余按应用的平台顺序，已下线和未知的最后 |
| 4 | 已下线平台（Kick 等）的关注每次刷新都去请求，失败后永远“状态待确认”，还可能停在“直播中”分组 | `favorite_controller.dart:813`（`Sites.of` 抛错算失败） | 没区分“下线”和“失败” | 不请求；一律归入未开播，卡片标“平台已下线” |
| 5 | 桌面和宽屏没有可见的刷新入口（下拉只在手机或窄屏，再点侧栏“关注”无从发现） | `room_grid_view.dart:6-11` | — | 平台栏右侧加刷新按钮，刷新时显示进度 |
| 6 | 本地关注列表套用服务器分页组件：桌面要翻页，手机要“加载更多”，每页数量选择对本地数据没有意义，刷新后回到第 1 页 | `favorite_page.dart:139-147`、`local_reactive_page_controller.dart` | 通用分页基类 | 懒加载网格（`GridView.builder` 只建看得见的卡片）一次给出全部；滚动位置按平台和状态保存 |
| 7 | 刷新失败只写日志，用户看不到 | `favorite_controller.dart:821-838` | — | 手动刷新后有失败时提示“N 个直播间暂时获取失败，已标为状态待确认” |
| 8 | 没有任何关注时空页的按钮是“重试”，无事可做 | `favorite_page.dart:289-297` | 和“筛选为空”共用按钮 | 改为“搜索直播”，打开搜索页 |

## 界面改进

（2026-10-01 用户授权，UPGRADES 统一原则“界面和操作”。存储仍全部走 `live_store`，没有新的设置键，3.x 数据不需要额外迁移。）

- 状态标签显示当前平台下各分组的数量：不用切换就知道有几个在播。
- 平台栏列出所有有关注的平台（问题 3）。
- 平台栏右侧刷新按钮；刷新时顶部细进度条和按钮上的圆形进度按完成比例前进（v3 只有不定长的进度条）。
- 手动刷新有失败时提示数量（问题 7）。
- 取消关注后底部提示可“撤销”，放回原来的位置（v3 取消后只能重新去找）。
- 卡片菜单改成列表项：设置标签、复制链接、取消关注（红色）；标签框里可直接输入名字新建标签，右上角可去标签管理。
- 卡片标出受限类型（付费、私密、仅限 App、加锁、地区受限、需登录、订阅专享、需年龄验证、不可播放）以及轮播、已封禁、平台已下线（统一原则“受限……”“回放、轮播”）。
- 直播中的卡片在主播名后显示已播时长（平台给了开播时间时，UPGRADES“开播时间”）。
- 没有关注时按钮改为“搜索直播”（问题 8）。
- 首次读取关注时显示骨架卡片，不再闪一下空页。
- 去掉分页（问题 6）。

## 已批准的升级（docs/specs/UPGRADES.md）

| 编号 | 本页做了什么 | 状态 |
|---|---|---|
| 统一原则“受限……” | 关注照常显示，卡片标出受限类型 | 关注页完成；发现页隐藏、播放说明属于其他页面 |
| 1-1 哔哩哔哩轮播 | 轮播归入“未开播”，卡片标“轮播” | 关注页完成 |
| 3-1 虎牙回放 | 不可播放的回放归入“未开播”，卡片标“不可播放”；可播放的回放在“录播” | 关注页完成 |
| 17-1、23-1 按主播关注 | 首轮刷新先等 `followsReady`；身份迁移动过关注时重新读一遍再刷新；刷新结果按关注身份合并 | 关注页完成 |
| 28-2、X-2 占位信息 | 刷新经 `FollowStore.update` 合并；没有名字时卡片显示平台名（`displayNick`） | 关注页完成 |
| 7-9、10-3、25-12、33-7 开播时间 | 关注卡片显示已播时长 | 部分完成，余下其他页面和直播间 |

UPGRADES.md 里以上各行的状态已追加“I04.1 …”。

## 留给后续

| 内容 | 去向 |
|---|---|
| 卡片数据转换（`favorite_cards.dart`）和卡片菜单（`room_menu.dart`）热门、分区、搜索、历史也要用；受限类型等文字的键现在叫 `favorite_mark_*` | 合并时可移到共享目录、改成通用前缀 |
| 分享（v3 `ShareCommandHandler` 的分享口令和系统分享面板）：现在只有“复制链接” | 链接/分享任务（M13） |
| v3 在应用首帧后就开始核验关注；现在第一次打开关注页时才开始（关注不是第一个标签时会晚） | 应用外壳可在首帧后 `ref.read(favoriteControllerProvider)`；启动页可等它的首轮刷新 |
| 直播间“看其他”弹窗要求刷新关注（v3 事件 `refresh_favorite_rooms`） | 直播间（M13）调用 `ref.read(favoriteControllerProvider).refreshAll()` |
| `RoomCardData` 没有开播时间字段，已播时长暂时接在主播名后 | 需要时在 `live_ui` 加字段 |
| 卡片封面、头像的请求头（v3 `networkImageHeaders`） | 应用的 `LiveUiConfig.imageHeaders`（A01.1 记录） |
| 真机检查（手机下拉、平板侧栏、Windows 右键菜单） | 本次没装机 |

## 测试

`apps/pure_live/test/favorite_test.dart`，11 个用例（加速流程，只覆盖主要路径）：

| 组 | 内容 |
|---|---|
| rules（3） | 分组（受限直播、可播放回放、不可播放回放、轮播、待定、已下线平台）；平台栏顺序；按人数排序、未开播保持关注顺序、标签筛选、可选标签、各分组数量 |
| refresh（3） | 合并：空名字保留存下的、失败变待定并保留人数、已下线平台不请求、一个房间一个请求；并发上限和进度、失败冷却和手动绕过；另一个房间号的结果绑定到关注 |
| controller（2） | 启动等 `followsReady`、期间“正在核验”；再点“关注”只刷当前平台；回到前台刷新全部、15 秒内不重复、设置关掉后不刷 |
| page（3） | 没有关注的空页；状态标签、平台栏、受限和轮播标记、人数格式、待定和已下线标记、“查看未开播”；长按菜单新建并设置标签、标签条筛选、取消关注和撤销（放回原位） |

另外改了 `test/home_test.dart` 一行：首页的关注标签原来是“建设中”占位，标题栏文字是“关注”，现在标题栏是状态标签，检查改为“已开播”。
