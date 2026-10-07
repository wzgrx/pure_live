# A17 电视界面

电视设计系统和通用组件、外壳、直播浏览、直播间、网络电视和影片、点播、音乐、壁纸、设置。

一句话：Android 电视和电视盒子上、用遥控器操作的那一套界面（`uiMode` 为电视时整个应用换成它）：焦点和组件、首页外壳和导航轨、直播浏览各页、电视直播间、网络电视和链接放映、哔哩哔哩点播和音乐、界面壁纸、电视设置。基线是上游的电视版 pure_live_TV（`~/ref/pure_live_TV`），不是 3.x——3.x 只在清单里声明了电视启动器，界面还是手机的。

## 范围

- 包括：
  - `apps/pure_live/lib/tv/` 下的全部界面代码（28 个文件，6754 行）：设计系统和通用组件（`tv_theme.dart`、`widgets/`，A17.1）、首页外壳（`home/tv_home_page.dart`，A17.2）、直播浏览各页（`pages/`，A17.3）、电视直播间（`room/`，A17.4）、网络电视页（`pages/tv_iptv_pane.dart`，A17.5），以及还没有代码的点播（A17.6）、音乐（A17.7）、壁纸（A17.8）、电视设置的完整目录（A17.9，现在只有 `pages/tv_settings_pane.dart` 一页常用项）。
  - 电视界面的路由表 `apps/pure_live/lib/routes/tv_router.dart`（直播间、分区房间、搜索三条路径换成电视页面）和外框 `tv/tv_app.dart`（方向键导航模式、Esc 当返回、电视调色板）的样子部分。
  - `packages/live_ui` 里电视专用的 `TvIcons`（`src/icons/tv_icons.dart:9`）、`TvColors`（`src/theme/tv_colors.dart:6`）。
- 不包括（归哪里）：
  - 电视模式怎么判断和切换（`app/ui_mode.dart` 的 `UiMode`、`TvDevice.detect`、原生通道 `isTelevision`、`inputText`）、Android 清单的 leanback 和横幅、电视客户端的构建和真机：[X03 电视](../../X-多端客户端/X03-电视/README.md)（X03.1 已完成）。A17 只管这些界面长什么样、遥控器怎么走。
  - 直播间、网络电视、点播和音乐的逻辑：进房、换台、画质线路由手机的 `LiveRoomController` 负责（[C 直播间](../../C-直播间/README.md)）；网络电视的订阅源、节目单在 [L01](../../L-网络电视和点播/L01-网络电视/README.md)、[L02](../../L-网络电视和点播/L02-节目单和回看/README.md)；点播和音乐的接口、解析、队列在 `packages/live_vod`（[L03](../../L-网络电视和点播/L03-点播和音乐/README.md)，L03.1 已完成）。
  - 手机和宽屏的同一功能：设计系统 [A01](../A01-设计系统/README.md)、组件 [A02](../A02-组件/README.md)、首页 [A06](../A06-首页和全局/README.md)、直播间 [A07](../A07-直播间界面/README.md)、弹幕 [A08](../A08-弹幕界面/README.md)、浏览 [A09](../A09-浏览界面/README.md)、设置 [A11](../A11-设置界面/README.md)、账号和数据 [A12](../A12-账号和数据界面/README.md)、网络电视 [A13](../A13-网络电视和多画面界面/README.md)。电视用的是这些组件的电视样式（[specs/UI.md](../../specs/UI.md) 第 5.5 节最后一句），内容和文字以手机为准。
  - 录制：pure_live_TV 没有录制；A17.4 c10 定了电视直播间也给录制面板（A07.6 同一个），录制本身在 [H 录制](../../H-录制/README.md)。
  - 苹果平台没有电视版（不做 Apple TV，见 [A18](../A18-苹果平台界面/README.md)）。

## 现状：做到哪、怎么工作的

- **用户看得到的**（2026-10-01 X03.1 做的外壳加 A17.1 换上的组件；之后电视代码没有再改过，`git log 727e184ad..master -- apps/pure_live/lib/tv` 只有两次文档路径替换）：
  - **进入**：Android 电视（`UI_MODE_TYPE_TELEVISION` 或有 `android.software.leanback`）上 `uiMode = auto` 自动进电视界面；手机上可以在设置 → 外观的“界面模式”选“电视”。改设置立即换路由，不用重启（`app/app.dart:174-176`、`:118-129`）。电视界面固定深色（`app.dart:219`）。
  - **首页**（`tv/home/tv_home_page.dart`）：左边导航栏一直展开，宽 `pxText(200)`（`:338`），表面容器低底色加右边分隔线（`:340-341`）；从上到下时钟（`_Clock` `:411`，时分加日期）、关注（启动时的目的地）、推荐、分区、历史、搜索、网络电视，最下面设置（`TvPane` `:28-77`；视频、音乐、壁纸三项 `available: false` 不显示，内容是“建设中”`:314-316`）。导航项上按 OK 切换并进入页面（`_select` `:260`，回到上次停留的那一项 `_enter` `:248`），按右也进（`_menuKey` `:301`）；页面最左一列按左回到**选中的**导航项（`_remember` `:214`）。访问过的页面留在 `IndexedStack` 里（`:365`），切回来标签、滚动和焦点都在。返回键：页面自己的一层 → 导航栏 → 提示“再按一次返回键退出”，2 秒内再按退到后台（`_back` `:276`，`moveToBack`）。没有退出确认、模式按钮、协议页、启动解锁（A17.2 要做）。
  - **浏览各页**（`tv/pages/`）：关注（状态标签带数量 + 平台标签，`tv_favorites_pane.dart:95`、`:110-112`）、推荐（每平台一个 `RoomFeed`，每页 24 个 `tv_popular_pane.dart:19`）、分区（第一个标签是“关注的分区”`tv_areas_pane.dart:93`，然后每个平台、分类、6 列分区卡片）、分区房间（`tv_area_rooms_page.dart`，顶部 `TvPageHeader` 带“关注分区”）、历史（网格、清空先确认 `tv_history_pane.dart:48-50`）、搜索（一页：输入框、平台标签含“全部”、最近搜索、结果网格，`tv_search_page.dart`）。房间网格 4 列，文字放大时减列（`tvRoomColumns` `tv_theme.dart:185`）。卡片 OK 进直播间、当前列表就是换台列表（`openTvRoom` `tv_navigation.dart:41`）；长按 OK 或菜单键打开统一的卡片弹窗（`showTvRoomDialog` `widgets/tv_room_dialog.dart:61`）；分区卡片长按仍是直接关注 / 取消关注（`toggleAreaFollow`，`tv_areas_pane.dart:218`、`tv_area_rooms_page.dart:116`）。
  - **直播间**（`tv/room/tv_live_play_page.dart`）：始终全屏，画面 + 飞行弹幕；上下键（和频道键）换台，300 毫秒内连按合并（`switchWindow` `:93`），换台横幅 3 秒（`bannerTime` `:96`，`TvChannelBanner` `room/tv_room_overlays.dart:101`）；OK 显示控制层（6 秒自动隐藏 `controlsTimeout` `:90`），房间失败、未开播时 OK 改为重试 / 刷新（`_onKey` `:256-299`）；左、右、菜单、信息键都打开右侧房间列表（`:291-297`，`TvRoomList` `tv_room_overlays.dart:338`），列表里按左关闭。控制层按钮：画质、线路（多于一条时）、弹幕开关、关注、刷新、房间列表（`TvRoomControls` `tv_room_overlays.dart:162`，按钮 `:266-316`），画质和线路是选择框（`:307`、`:325`）。没有播放设置面板、弹幕设置、屏蔽、录制、节目单（A17.4、A17.5）。
  - **网络电视**（`tv/pages/tv_iptv_pane.dart`）：左边播放列表（内置热门 + 导入的，`loadTvPlaylists` `:36`），右边频道；“IPTV管理”打开手机的网络电视页（`:112-113`、`:165-169`）。没有电视样式的 IPTV 设置和链接放映（A17.5）。
  - **设置**（`tv/pages/tv_settings_pane.dart`）：三组：界面模式、主题颜色（6 个预设 `tvThemeColors` `:20`）、文字大小（90%～160% `tvTextScales` `:30`）、焦点放大；默认清晰度、显示弹幕、弹幕大小、弹幕透明度；网络与代理、更多设置（打开手机的设置页 `:145-157`）。其余设置都靠手机设置页加 Flutter 自带的方向键焦点操作（A17.9 要做电视目录）。
  - **组件**（A17.1 c1～c16 都做了，c15 只有外壳）：近白 3 像素描边加放大 1.05、整行不放大、没有光晕；选中是主色容器底、焦点是描边；最小字号 14；危险确认框焦点在“取消”；状态页、骨架、卡片角标、卡片弹窗、设置房间标签、手机推送直播间的对话框。
- **内部怎么工作**：
  - 外框：`PureLiveApp` 在电视时用 `buildTvRouter`（`routes/tv_router.dart`：根路径 `TvHomePage`，`tvPageRoutes` 把 `kLivePlay`、`kAreaRooms`、`kSearch` 换成电视页，其余 `pageRoutes` 原样保留），外面包 `TvAppFrame`（`tv/tv_app.dart:28`：`NavigationMode.directional` `:43`、`TvTheme`、Esc = 返回 `TvBackIntent` `:11`、`tvFocusZoom` 设置 `:67`）。
  - 焦点：全部用 Flutter 自带的焦点树，不用 dpad 包（X03.1 记录“焦点方案”）。`TvFocusable`（`widgets/tv_focusable.dart:59`）统一处理 OK（`isTvConfirmKey` `:9`：select、Enter、手柄 A、空格）、长按 0.5 秒（`tvLongPressDelay` `:21`）和菜单键（`isTvMenuKey` `:18`），按下缩到 0.97（`:28`），描边 3（`:31`）；网格 `TvGrid`（`widgets/tv_grid.dart:24`）按下标走、目标行先跳进视野再取焦点、第一列按左交给几何（到导航栏）、第一行按上交给标签；首页记住每个目的地最后的焦点（`_memory`）。
  - 颜色和尺寸：`TvPalette`（`tv_theme.dart:15`）直接取手机深色 `ColorScheme` 的角色，主题色作种子；`TvScale`（`:88`）按 1920×1080 换算，720p 面板文字放大（最多 1.6）；字号表 `TvTextSize`（`:146`）、圆角 `TvRadius`（`:164`）、焦点动画 120 毫秒（`tvFocusDuration` `:180`）。
  - 数据：各页只调手机已有的公开接口：`favoriteControllerProvider`、`popularCatalogProvider`、`AreaCatalog`、`SearchModel`、`history.watchAll()`、`LiveRoomController`、`RoomBackgroundPolicy`；`tv/` 不复制手机界面。
- **完成度**：
  - A17.1 登记“完成”（2026-10-01，合并 `727e184ad`），但记录写明“没有在电视上看过”（见“已知问题”）。
  - A17.2～A17.9：设计 2026-10-01 都已确认（用户“后续全部通过”，待选按建议 A，D-003），都没开发；按 D-004 的客户端顺序（Android → Windows → 电视），排在 Windows 之后，第三档。
  - 和 pure_live_TV 比，现在缺：模式（视频、音乐）和它们的全部界面、壁纸、49 个设置页里的大多数、IPTV 设置、链接放映、协议页、启动解锁、退出确认、新版本对话框的电视样式、直播间的播放设置和弹幕设置面板、手机推送的接收端、网页遥控。

## 代码地图

外壳和设计系统（`apps/pure_live/lib/tv/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `tv_app.dart`（85 行） | `TvBackIntent`（`:11`，Esc 当返回）、`TvAppFrame`（`:28`，方向键导航模式、电视调色板、焦点放大设置、提示条样式） | X03.1、A17.1 c2 |
| `tv_theme.dart`（238） | `TvPalette`（`:15`，手机深色角色）、`TvScale`（`:88`，1920 设计稿换算、720p 放大）、`TvTextSize`（`:146`）、`TvRadius`（`:164`）、`tvFocusDuration`（`:180`）、`tvRoomColumns`（`:185`）、`TvTheme`（`:192`）、`TvBackground`（`:216`，纯色背景，A17.8 要换成壁纸层） | A17.1 c4、c5 |
| `tv_navigation.dart`（64） | `TvRoomArgs`（`:13`，房间 + 换台列表）、`openTvRoom`（`:41`，平台已下线时提示） | X03.1 |
| `home/tv_home_page.dart`（462） | `TvPane`（`:28`，十个目的地，视频、音乐、壁纸占位）、`TvHomeHost`（`:78`）、`TvHomeScope`（`:92`）、`TvHomePage`（`:124`：导航栏 `:335-358`、`_select` `:260`、`_back` `:276`、恢复后刷新 `:188`、启动检查更新 `:176`）、`_Clock`（`:411`） | A17.2 |
| `widgets/tv_focusable.dart`（254） | `isTvConfirmKey`（`:9`）、`isTvMenuKey`（`:18`）、`tvLongPressDelay`（`:21`）、`tvFocusZoom` 1.05（`:24`）、`tvPressScale`（`:28`）、`tvFocusRingWidth` 3（`:31`）、`TvFocusable`（`:59`）、`tvFocusFirstInRoute`（`:245`） | A17.1 c1、c2、c10 |
| `widgets/tv_button.dart`（125） | `TvButtonKind`（`:6`）、`TvButton`（`:22`，表面容器底，主要动作主色字、删除类红字） | A17.1 c4 |
| `widgets/tv_nav_item.dart`（92） | `TvNavItem`（`:9`，导航栏一项，选中主色容器底） | A17.1、A17.2 c2 |
| `widgets/tv_tabs.dart`（205） | `TvTab`（`:9`）、`TvTabBar`（`:36`，OK 切换、当前标签再按 OK 刷新加进度线） | A17.1 c3 |
| `widgets/tv_grid.dart`（250） | `TvGrid`（`:24`，按下标走、跳进视野、到底取下一页、焦点记忆） | X03.1、A17.1 c1 |
| `widgets/tv_room_grid.dart`（148） | `TvRoomGrid`（`:25`，房间网格，长按 `:136` 打开卡片弹窗 `:94`）、`tvFollowKeysProvider`（`:146`） | A17.1 c9 |
| `widgets/tv_room_card.dart`（419） | `TvRoomCard`（`:25`）、`audienceIcon`（`:215`）、`TvCover`（`:225`）、`TvCoverPlaceholder`（`:257`）、`TvCoverChip`（`:276`）、`TvMarquee`（`:321`，焦点时标题滚动） | A17.1 c5、c7、c8 |
| `widgets/tv_area_card.dart`（116） | `TvAreaCard`（`:13`，自己的底色、已关注心形） | A17.1 c6 |
| `widgets/tv_room_dialog.dart`（408） | `TvRoomAction`（`:19`）、`showTvRoomDialog`（`:61`）、`TvRoomDialog`（`:86`）、`tvUnfollowRoom`（`:205`）、`tvEditRoomTags`（`:228`）、`TvRoomTagsDialog`（`:252`，末尾“新建标签”）、`TvTick`（`:385`） | A17.1 c9、c11 |
| `widgets/tv_dialogs.dart`（681） | `showTvDialog`（`:15`，遮罩 60%）、`TvDialog`（`:23`）、`showTvConfirm`（`:135`，`danger` 时焦点在“取消”，非危险 0.5 秒防误触）、`TvChoice`/`showTvChoice`（`:203`、`:225`）、`TvOptionRow`（`:271`）、`TvTextInput`（`:386`，Android 走原生输入对话框）、`showTvInput`（`:443`）、`TvInputDialog`（`:468`）、`TvInputField`（`:604`） | A17.1 c3、c12、c16 |
| `widgets/tv_settings_rows.dart`（470） | `TvSettingsGroup`（`:12`）、`TvSettingsRow`（`:60`）、`TvSwitchIndicator`（`:166`）、`TvSwitchRow`（`:202`）、`TvLinkRow`（`:261`）、`TvChoiceRow`（`:295`，OK 弹选择框）、`TvSliderRow`（`:365`，←→ 调、到头放行） | A17.1 c1、A17.9 c2 |
| `widgets/tv_page_header.dart`（54） | `TvPageHeader`（`:9`，子页没有“返回”按钮：标题、副标题、右边动作） | A17.1 c13 |
| `widgets/tv_status.dart`（230） | `TvStatusAction`（`:17`）、`TvStatusView`（`:40`，出错按原因、需要登录）、`TvSkeletonGrid`（`:162`） | A17.1 c14 |
| `widgets/tv_room_push_dialog.dart`（122） | `TvRoomPushChoice`（`:11`）、`showTvRoomPush`（`:30`）、`TvRoomPushDialog`（`:37`）；没有调用处（接收端还没有） | A17.1 c15 |

页面和直播间：

| 文件 | 职责 | 设计 |
|---|---|---|
| `pages/tv_favorites_pane.dart`（125） | `TvFavoritesPane`（`:22`）：状态标签（`:95`）、平台标签（`:110-112`）、刷新 | A17.3 c2、c3 |
| `pages/tv_popular_pane.dart`（182） | `tvPageSize` 24（`:19`）、`TvFeedGrid`（`:26`，分页网格，搜索结果也用）、`TvPopularPane`（`:91`，平台全关时 `:137`） | A17.3 c5 |
| `pages/tv_areas_pane.dart`（223） | `TvAreasPane`（`:27`，“关注的分区”`:93`、平台、分类 `:157`）、`_AreaGrid`（`:184`，长按 `:218`） | A17.3 c6、c7、c9 |
| `pages/tv_area_rooms_page.dart`（135） | `TvAreaRoomsPage`（`:28`，`TvPageHeader` + 关注分区 `:116`） | A17.3 c8 |
| `pages/tv_history_pane.dart`（114） | `tvHistoryProvider`（`:19`）、`TvHistoryPane`（`:27`，清空 `:48-50`、删除一条 `:103-105`） | A17.3 c10 |
| `pages/tv_search_page.dart`（270） | `TvSearchPage`（`:23`，路由页）、`TvSearchPane`（`:48`：输入、平台 `:174-176`、结果、最近搜索 `:235`、清空先确认 `:132-134`） | A17.3 c11、c12 |
| `pages/tv_iptv_pane.dart`（177） | `TvPlaylist`（`:19`）、`loadTvPlaylists`（`:36`）、`TvIptvPane`（`:56`） | A17.5 |
| `pages/tv_settings_pane.dart`（164） | `tvThemeColors`（`:20`）、`tvTextScales`（`:30`）、`tvDanmakuSizes`（`:33`）、`tvDanmakuOpacities`（`:36`）、`TvSettingsPane`（`:46`，三组） | A17.9（现在是过渡版） |
| `room/tv_live_play_page.dart`（473） | `TvLivePlayPage`（`:59`）、`TvLivePlayPageState`（`:71`：换台 `switchBy`、按键 `_onKey` `:256`、画质 `:307`、线路 `:325`）、`_Picture`（`:451`） | A17.4 |
| `room/tv_room_overlays.dart`（468） | `TvRoomStatus`（`:14`，加载、失败、未开播、播放出错）、`TvChannelBanner`（`:101`）、`TvRoomControls`（`:162`）、`TvRoomList`（`:338`） | A17.4 |

别处和电视界面有关的：

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/routes/tv_router.dart` | `tvPageRoutes`、`buildTvRouter` |
| `apps/pure_live/lib/app/ui_mode.dart` | `UiMode`（`:10`）、`TvDevice`（`:37`）、`televisionDeviceProvider`（`:67`）、`showsTvInterface`（`:70`）（X03） |
| `apps/pure_live/lib/app/app.dart` | 选路由（`:60-64`、`:118-129`、`:174-176`）、电视固定深色（`:219`）、电视时不放应用内小窗层（`:231`）、包 `TvAppFrame`（`:239`） |
| `packages/live_ui/lib/src/icons/tv_icons.dart`、`src/theme/tv_colors.dart` | `TvIcons`（`:9`，按用途命名的电视图标）、`TvColors`（`:6`，焦点描边 `#F1F3F9`、遮罩、心形） |
| `packages/live_store/lib/src/settings/settings.dart` | `uiMode`（`:1389`，作用域 internal，不进备份）、`tvFocusZoom`（`:1400`，默认开） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | 通道 `pure_live/app` 的 `moveToBack`（`:251`）、`isTelevision`（`:252`、`:348`）、`inputText`（`:257`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/tv/tv_test.dart`（8 个） | X03.1：模式和列数规则；自动模式和切换；首页焦点（菜单、标签、网格、返回两次）；进房、合并换台、横幅、控制层、房间列表、返回落在最后看的卡片；长按 OK 出卡片弹窗；搜索；电视设置改界面模式；可聚焦控件的按下和长按 |
| `apps/pure_live/test/tv/tv_components_test.dart`（29 个用例声明，记录写 31） | A17.1：调色板对比度（四种主题色）、描边和放大、选中和焦点、按钮文字色、1080p 最小字号 14、卡片各状态和角标、标题滚动、长按 / 菜单键 / 右键、分区卡片、四种设置行、危险确认框、选择框、输入框、卡片弹窗在三种面板上不出屏、标签对话框、状态页、子页顶栏、手机推送两种状态 |
| `packages/live_store/test/` 的 `uiMode`、`tvFocusZoom` 用例 | 默认值、取值、作用域 |

## 3.x 基线

- **3.x 没有电视界面**。`git show v3.2.11:android/app/src/main/AndroidManifest.xml` 第 45 行有 `android:banner`、第 63 行 `LEANBACK_LAUNCHER`、第 132 行 `android.software.leanback required="false"`：3.x 能出现在电视启动器里，但打开是手机界面，没有方向键焦点处理（`git grep -l "LogicalKeyboardKey.select" v3.2.11 -- lib` 没有结果）。所以 A17 的基线是上游电视版。
- **pure_live_TV**（AGPL-3.0，本机 `~/ref/pure_live_TV`）：设计时用的是提交 `b9d2f739`；本机副本已更新到 `37660afc`（2026-10-02，[W01.1](../../W-上游借鉴/W01-定期对照/W01.1-2026-10-03上游对照/README.md)：167 个提交，大部分是点播、音乐和电视界面，`a3b61953` 给长按卡片加了“弹窗开着时不响应”的锁）。目录对应：`lib/core/`（焦点、组件、对话框、主题）→ A17.1；`lib/features/home/`、`agreement/` → A17.2；`lib/modules/live/{hot,favorite,areas,favorite_areas,history,search}` → A17.3；`modules/live/playback/` → A17.4；`modules/live/iptv/`、`movie_playback/` → A17.5；`modules/video/`、`modules/vod/` → A17.6；`modules/music/` → A17.7；`features/wallpaper/`、`services/background_config/` → A17.8；`features/settings/`（49 页） → A17.9。逐项界面在 [inventory/UI.md](../../inventory/UI.md) 的 A17.1～A17.9 节（共 102 个页面、34 个对话框等）。
- 要保留的电视习惯（pure_live_TV 有、各设计的 c1 “保留”行）：长按 OK 0.5 秒算长按且松开不再点按；在当前标签上再按 OK 刷新；直播间上下键换台、300 毫秒合并、首尾循环；返回键逐级退出；对话框关闭后焦点回到原处；选择框打开时焦点在当前项；滑块 ←→ 到头才放行；从直播间回来焦点落在最后看的房间。手机的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）里第 14 条（长按 = 右键 = 菜单键）也适用于电视。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A17.1 登记“完成”，但没有在电视或盒子上看过（记录“真机”一节：“没有在电视上看过”）；X03.1 也只在测试里用键盘事件模拟 | [A17.1 记录](A17.1-电视设计系统和通用组件/record.md)、[X03.1 记录](../../X-多端客户端/X03-电视/X03.1-电视外壳和焦点导航/record.md) | 不符合 PROCESS 3.2“完成必须有真机结果”；焦点描边在亮封面上是否醒目、720p 盒子字号、遥控器 OK 实际发的键都没确认 | 写进报告，建议改回“待真机”；电视真机验证随电视客户端阶段（D-004）做，步骤见 [A17.1 README](A17.1-电视设计系统和通用组件/README.md)“实现和验证” |
| Android 电视上的文字输入仍是原生对话框，不是设计的 `TvInputDialog` | `widgets/tv_dialogs.dart:386`（`TvTextInput`）、`MainActivity.kt:257` | 输入框样子和设计不同（部分盒子上 Flutter 输入调不出键盘，flutter#154924） | A17.1 偏差 1；要一样得像 pure_live_TV 那样嵌原生输入视图（改原生），等电视阶段由维护者定 |
| 手机推送直播间只有对话框，没有接收端（网页遥控、局域网推送） | `widgets/tv_room_push_dialog.dart:30` 没有调用处 | 设计 c15 没法用 | 接线写在 A17.1 记录；接收端随 A17.5（链接放映的手机网页）、A17.9（扫码到手机）一起做 |
| 分区卡片长按还是直接关注 / 取消关注，没有菜单 | `pages/tv_areas_pane.dart:218`、`tv_area_rooms_page.dart:116` | 看不出将要做什么，取消关注不确认 | A17.3 c7（注意：2026-10-01 的跨任务记录定了“分区卡片长按用 A17.1 c9 统一的卡片弹窗”，和 A17.3 README 的 c7“小菜单”不同，开发时以统一弹窗为准，见 A17.3 任务书） |
| 导航栏固定展开 200，没有收起和焦点进入时展开；没有模式按钮；返回是“再按一次退出”而不是退出确认 | `home/tv_home_page.dart:338`、`:28-77`、`:276` | 和确认的设计（A17.2 c2、c6、c8）不同 | A17.2 |
| 设置只有一页常用项，其余打开手机设置页；选择行原来 ←→ 改值已按 A17.1 偏差 2 改成 OK 弹框 | `pages/tv_settings_pane.dart:46-160` | 手机设置页的行没有电视焦点样子、字小 | A17.9 |
| 直播间的控制层按钮带字、一行六个；没有播放设置面板、弹幕设置、屏蔽、录制、节目单；左右键都开房间列表 | `room/tv_room_overlays.dart:266-316`、`room/tv_live_play_page.dart:291-297` | 和 A17.4 c3～c11 不同 | A17.4、A17.5 c6 |
| 旧分支 M14.2～M14.5 的电视半成品建在 4.x 重构前的目录（`lib/pages/`、`lib/app/`），没有合并，也不能直接合并 | 工作区 `agent-af79805552a6c7d0e`（`69f12f418`，直播间）、`agent-a3224b95b79a5b0be`（`e6dd43c8f`，点播）、`agent-a38e678e236092db4`（`e5a6ede7f`、`f712f2bd9`，音乐）、`agent-af3e4f5945df78e33`（`37ef8cbf0`，网页遥控和 pure_live_TV 备份导入）；提交时间之后工作区里没有再改过的文件 | 逻辑可以参考，界面要照新设计重写 | 各任务书写明参考哪个提交；工作区要不要留由维护者在月度清理（PROCESS 第 12 节）时定 |
| pure_live_TV 本机副本比设计基线新 167 个提交 | `~/ref/pure_live_TV`（`37660afc`，设计用 `b9d2f739`） | 开发时看到的代码和设计里的行号对不上 | 各任务书第一步：对照设计里引用的文件看有没有变，变了的照新代码理解行为，设计不改 |
| A17.5 的 README 标题是“电视网络电视和链接放映”，登记表是“电视网络电视和影片” | `A17.5-电视网络电视和影片/README.md:1`、`docs/tasks.toml` | 名字不一致（pure_live_TV 导航叫“链接放映”） | 写进报告，建议登记表改成“电视网络电视和链接放映” |
| A17.8 内置随机壁纸接口里有“性感美女”分组和“黑丝”“白丝”来源，电视常是全家一起用 | pure_live_TV `features/wallpaper/` 的 `wallpaper_api_source.dart:136-160`（A17.8 README“拿不准的地方”） | 设计照代码保留，用户没表态 | A17.8 任务书第一阶段请维护者定（保留、加开关或去掉） |
| A17.1～A17.9 的设计正文里还有“改动（待确认）”“用户意见：待评审”等定稿前的字样 | 各任务 README | 读起来像没确认 | 设计正文不改；确认记录写在各任务“实现和验证”（2026-10-01 用户“后续全部通过”，待选按建议 A） |

## 相关决定和规范

- D-003：A17.1～A17.9 的待选（A1～A4、B1～B4、C1～C4、T1～T4、N1～N4、X1～X4、Y1～Y3、Z1～Z3、N1/D1/T1/I1）都按建议 A。
- D-004：客户端顺序 Android → Windows → 电视 → Linux → 苹果平台；当前只做 Android，所以 A17.2～A17.9 是第三档。
- D-005：电视上的文字同样中文、走翻译（`tv_` 前缀的键）。
- D-018：电视设置和手机写同一批设置键（`textScaleFactor`、`themeColorSwitch`、`danmaku*`），新设置只加不改（`uiMode`、`tvFocusZoom` 是新加的）。
- D-020、D-021、D-022：手机面板、取消关注小菜单、切换直播间的决定，电视对应的界面用同一个组件的电视样式。
- [specs/UI.md](../../specs/UI.md)：第 5.5 节（电视细则：960×540、48 / 28 安全边距、导航轨收起焦点进入时展开、4 列、1.05 加 3 像素近白描边、正文 ≥14、只有深色、直播间按键）；第 3 节第 6、7 条（同一件事一种做法、同一组件）；第 7 节（弹窗和面板）；第 9.3 节（不用模糊，A17.1 c2 去掉光晕、A17.8 h7）；附录 A 第 14 条。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 5 节：pure_live_TV 是 AGPL-3.0，借鉴代码要注明来源仓库和提交，不照搬架构。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/tv/`（37 个用例声明）。按键都用 `sendKeyEvent` 模拟，返回键用 `handlePopRoute`。覆盖了 X03.1 的主要路径和 A17.1 的每个改动；缺的：没有截图对照；没有 720p（`devicePixelRatio = 1`）下整页的布局测试（只有卡片弹窗测了三种面板）；直播间只测了换台和列表，没有测播放失败时的 OK 重试。
- 真机：没有电视设备的记录。S02 的 [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 目前只有手机；电视的检查清单要在电视客户端阶段补（建议放进 S02，按 X03.1 记录“没验证的部分”和 A17.1 记录“真机”一节列：`isTelevision` 判断、启动器横幅、遥控器 OK 的键码、长按的重复事件、返回键、原生输入法、720p 字号、mpv 硬解、飞行弹幕帧率、焦点描边在亮封面上是否醒目）。K90 上可以把“界面模式”改成“电视”、接蓝牙键盘或用 `adb shell input keyevent` 粗看焦点路线，但不能代替电视。

## 路线

按 D-004，电视排在 Android 和 Windows 之后；开工时按依赖排：

1. 先补 A17.1 的电视真机验证（改回“待真机”的话），同时确认 X03.1 的“没验证的部分”。这一步决定焦点描边、字号是否要调，后面八个任务都受影响。
2. A17.2 电视外壳：导航轨收起展开、模式按钮、退出确认、新版本、协议页、启动解锁。模式按钮是 A17.6、A17.7 的入口，导航栏显示控制是 A17.9 的一部分。
3. A17.3 电视直播浏览和 A17.4 电视直播间（直播是电视最常用的部分）；A17.4 依赖手机 A07.6 的面板组件、A08 的弹幕设置和屏蔽组件；可参考 M14.2 的半成品。
4. A17.9 电视设置（目录、设置行、选项对话框、扫码到手机组件）——A17.5、A17.8 的入口都在设置里，扫码块也被 A17.5 用。
5. A17.5 电视网络电视和链接放映（依赖 A17.4 的播放设置面板放“节目单”行、A17.9 的扫码块）。
6. A17.6 点播、A17.7 音乐（依赖 `packages/live_vod` 接进应用、A17.2 的模式按钮；A17.7 用 A17.6 的卡片、控制栏和状态组件，必须先做 A17.6）；可参考 M14.3、M14.4 的半成品。
7. A17.8 壁纸（依赖 A17.9 的入口、A17.2 的外壳背景层；先请维护者定敏感壁纸来源）。

新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：电视模式代码
- 进度：`████████░░░░░░░░░░░░` 38%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A17.1 | 电视设计系统和通用组件 | 界面 | 完成 | 2026-10-01 | 537428abf | [设计或说明](A17.1-电视设计系统和通用组件/README.md)、[记录](A17.1-电视设计系统和通用组件/record.md)、[评审页](A17.1-电视设计系统和通用组件/page/01-说明.jpg) |
| A17.2 | 电视外壳 | 界面 | 已确认 | — | — | [设计或说明](A17.2-电视外壳/README.md)、[评审页](A17.2-电视外壳/page/01-说明.jpg) |
| A17.3 | 电视直播浏览 | 界面 | 已确认 | — | — | [设计或说明](A17.3-电视直播浏览/README.md)、[评审页](A17.3-电视直播浏览/page/01-说明.jpg) |
| A17.4 | 电视直播间 | 界面 | 已确认 | — | — | [设计或说明](A17.4-电视直播间/README.md)、[评审页](A17.4-电视直播间/page/01-说明.jpg) |
| A17.5 | 电视网络电视和影片 | 界面 | 已确认 | — | — | [设计或说明](A17.5-电视网络电视和影片/README.md)、[评审页](A17.5-电视网络电视和影片/page/01-说明.jpg) |
| A17.6 | 电视点播 | 界面 | 已确认 | — | — | [设计或说明](A17.6-电视点播/README.md)、[评审页](A17.6-电视点播/page/01-说明.jpg) |
| A17.7 | 电视音乐 | 界面 | 已确认 | — | — | [设计或说明](A17.7-电视音乐/README.md)、[评审页](A17.7-电视音乐/page/01-说明.jpg) |
| A17.8 | 电视壁纸 | 界面 | 已确认 | — | — | [设计或说明](A17.8-电视壁纸/README.md)、[评审页](A17.8-电视壁纸/page/01-说明.jpg) |
| A17.9 | 电视设置 | 界面 | 已确认 | — | — | [设计或说明](A17.9-电视设置/README.md)、[评审页](A17.9-电视设置/page/01-说明.jpg) |

## 还没完成的

- **A17.2 电视外壳**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机
  - 说明：旧分支 M14.2～M14.5（工作区 agent-af79805552a6c7d0e 等，2026-10-01 停在界面重做前）有电视各界面的半成品，逻辑部分可以参考
- **A17.3 电视直播浏览**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机
- **A17.4 电视直播间**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机
- **A17.5 电视网络电视和影片**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机
- **A17.6 电视点播**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机
- **A17.7 电视音乐**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机
- **A17.8 电视壁纸**（已确认，第三档，规模 小）
  - 阶段：✓ 设计 → 开发 → 真机
- **A17.9 电视设置**（已确认，第三档，规模 中）
  - 阶段：✓ 设计 → 开发 → 真机

<!-- docs:生成结束 -->
