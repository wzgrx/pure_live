# A09 浏览界面

找直播间的那些页面长什么样、怎么点：房间卡片和它的长按对话框、首页的热门、关注、分区三页，分区房间、关注分区、平台显示，搜索、网页搜索、观看记录、标签管理，以及它们共用的网格、骨架、翻页栏、状态页的接法。

## 范围

- 包括：
  - 房间卡片和网格：`packages/live_ui` 的 `LiveRoomCard`、`RoomRow`、`RoomCardSkeleton`、`CardDialog`、`FollowPill`、`GridColumns`（样子由 A09.1 定），应用侧 `apps/pure_live/lib/shared/rooms/` 的网格外壳（`room_grid.dart`、`paging.dart`）、卡片长按对话框和关注 / 取消关注（`room_menu.dart`）、设置房间标签（`room_tags_dialog.dart`）。
  - 页面：热门 `features/popular/`、关注 `features/favorite/favorite_page.dart`、分区 `features/areas/`、分区房间 `features/area_rooms/`、平台显示 `features/hot_areas/`、搜索和网页搜索 `features/search/`（`search_view.dart`、`search_widgets.dart`、`search_scope.dart`、`web_search_view.dart`）、观看记录 `features/history/`（`history_page.dart`、`history_limit_dialog.dart`）、标签管理 `features/tags/`。
  - 这些页面的状态（骨架、空、出错、需要登录、刷新中）、横幅（平台说明、移动流量提示）、回到顶部 / 底部、电脑翻页栏怎么摆。
- 不包括（归哪里）：
  - 数据和逻辑：热门的平台目录和翻页来源（`features/popular/popular_catalog.dart`、`shared/rooms/room_feed.dart`）→ [I02](../../I-浏览和发现/I02-热门/README.md)；分区目录、分区图片、关注分区的存取（`area_catalog.dart`、`area_artwork.dart` 的取图规则、`areas_common.dart` 的 `followedAreasProvider`）→ [I03](../../I-浏览和发现/I03-分区/README.md)；关注的核验、刷新、分组和排序（`favorite_controller.dart`、`favorite_rules.dart`、`follow_refresher.dart`）→ [I04](../../I-浏览和发现/I04-关注/README.md)；搜索的请求、并发、排序、范围存取、历史（`search_model.dart`、`search_capability.dart`、`search_ranking.dart`、`search_history.dart`、`SearchScopeStore`）→ [I05](../../I-浏览和发现/I05-搜索/README.md)；观看记录的刷新和分组规则（`history_refresh.dart`、`history_sections.dart`）→ [I06](../../I-浏览和发现/I06-观看历史/README.md)；标签和分组的存储 → [I07](../../I-浏览和发现/I07-标签和分组/README.md)；人数口径 `AudiencePolicy`、平台名、出错文字（`room_cards.dart`、`room_texts.dart`）是 I 组和 E 组的数据，A09 只用它们。
  - 平台层（搜索结果、目录、房间资料怎么解析）→ [E](../../E-直播平台/README.md)；分享口令 `share_code.dart`、剪贴板口令对话框 `room_prompt.dart` → O03、A06.3；应用内网页 `shared/in_app_web.dart` → O03.1（网页搜索只用它）。
  - 首页外壳（底部导航、侧边导航、顶栏左右的菜单按钮 `MenuButton` 和搜索菜单 `CommonAppBarActions`，`features/home/`）→ [A06](../A06-首页和全局/README.md)；卡片外观的设置页（预设、圆角、显示项）→ A11.2；通用组件本身（状态页、横幅、小菜单、面板、提示条）→ [A02](../A02-组件/README.md)；下拉刷新和列表手感 → A03.1；高度分档、折叠屏 → A04.1；读屏和 Esc → A05.1。
  - 电视的直播浏览（`apps/pure_live/lib/tv/`，`TvRoomCard`）→ A17.3；弹幕屏蔽页 → A08.3。

## 现状：做到哪、怎么工作的

- 用户看得到的（A09.1～A09.10 登记为完成；A09.11 未开始）：
  - **房间卡片**（热门、关注、分区房间、搜索、观看记录、设置里的卡片预览共用 `LiveRoomCard`，`packages/live_ui/lib/src/widgets/live_room_card.dart:36`）：16:9 封面，左上平台标（平台图标 + 中文名；“自动”= 列表里混有多个平台时才显示，由页面传 `mixedPlatforms`），左下受限标记（付费、需登录、订阅专享、私密、仅限 App、地区受限、密码房、年龄限制、轮播、已封禁、平台已下线），右上“录播”或历史的删除按钮，右下人数（12 号等宽数字）或“正在核验 / 状态待确认”；未开播时封面压暗加“未开播”；加载中和失败同一个直播图标占位；下面头像、标题一行（600）、主播名一行（在播时后面加“· 已播 N”）。卡片底色浅色 `surfaceContainerLowest`、深色 `surfaceContainer`，圆角跟卡片设置（默认 20）。点按进直播间，长按或右键打开居中对话框（`CardDialog`），电脑悬停变浅灰并提示完整标题，键盘焦点 3 像素主色描边。第一次加载是和真卡同尺寸的静态骨架（`RoomGridSkeleton`）。
  - **长按对话框**（`apps/pure_live/lib/shared/rooms/room_menu.dart:60` 的 `showRoomMenu`）：平台图标、主播名、“平台 · 房间号”、完整标题、“分享”“设置标签”两个带字按钮，下面是 `FollowPill`（“＋ 关注”主色 / “✓ 已关注”灰）和“关闭”；取消关注先确认（红色“取消关注”，`confirmUnfollowRoom` `:158`），之后提示条带“撤销”；没关注时点“设置标签”先问“先关注再设置标签”。观看记录在这里多一行观看时间和“从观看记录删除”。设置标签（`RoomTagPicker`，`room_tags_dialog.dart:32`）写明直播间、原地“＋ 新建标签”、“确认”一直可用，对话框内容宽 400 以上排两列（`roomTagTwoColumnWidth` `:20`）。
  - **网格**：列数 = 按窗口宽度分档的最小卡宽（房间卡片紧凑 160、中等和展开 180、大和超大 200，2～8 列；分区卡片 110 / 130 / 150，3～10 列，`packages/live_ui/lib/src/theme/grid_columns.dart:58`、`:66`）随页面自己的宽度连续变化；393 宽手机 2 列，852 横屏 4 列，1280 宽 5～6 列（首页有侧边栏时 5 列）。各页边距统一 6（`roomGridPadding`，`shared/rooms/room_grid.dart:26`）。
  - **热门**：平台标签放在标题位置（可横滑，电脑滚轮能滚），末尾 ⌄ 打开“全部平台”面板（竖屏底部、宽 600 起右侧 360，当前平台打勾，右上“平台显示”，`features/popular/popular_page.dart:155`、`PlatformPicker` `:225`）；每个平台一页网格，左右滑切平台；平台说明是带 ⓘ 的浅色条（点开全文）、移动流量提示；平台全关时说明原因并给“平台显示”按钮；空、出错（按原因一句话）、需要登录各有说明。
  - **关注**：状态标签“已开播 / 录播 / 未开播”带数量在标题位置；宽 840 以上平台标签并到顶栏右边、状态标签按文字宽（`favoriteOneRowWidth`，`features/favorite/favorite_page.dart:27`），窄时平台标签在下一行；分组标签行 48 高；“全部”里卡片标平台；未开播页是紧凑行 `RoomRow`（宽屏按最小 320 排多列，`favoriteRowMinWidth` `:34`），行尾在“正在核验”或有标记时多一个小标签；紧凑模式关时大号卡片最小 300（`:31`）。刷新照 3.x：下拉、再点底部“关注”、电脑翻页栏的“刷新”；刷新后部分失败提示几个。
  - **分区**：平台标签在标题位置（只能点，页面不能左右滑切平台）；分类标签是次级样式（14 号、铺满的指示条、分隔线、从左排），只有一个分类时不显示；卡片只写分区名（关注分区页“全部”写“平台 · 分类”）；长按或右键分区卡片是和房间卡片同一个居中对话框（“关注分区 / 取消关注”），已关注的图片右上实心心形；右下“关注分区”浮动按钮（电脑在翻页栏上方）；加载中静态骨架。抖音也按分类分标签（合并后改的，C-12 后约 156 个分区）。
  - **分区房间**：标题分区名，下面一行“平台 · 大类”；关注是顶栏右边的 `FollowPill`；列表和热门是同一个 `RoomFeedView`；没有直播时“未发现直播 / 这个分区现在没有人在播，可以稍后刷新 / 刷新”；“前往登录”用登录图标。
  - **关注分区、平台显示**：关注分区页只列“全部”和有关注分区的平台，没关注时“未发现分区”加“去分区”；平台显示页内容最宽 720，分“显示（n）”“隐藏（n）”两组，六点把手只在显示组，隐藏组那一格留空、开关对齐；说明写明这份列表用于热门、分区、关注和搜索；“显示”组标题右边有 v4 留下的“恢复默认”。
  - **搜索**：竖屏是搜索框（返回、粘贴 / 清除、搜索；焦点时圆角仍 24）、平台条、筛选区（直播间 / 主播、包含未开播、排序“综合 ⌄”、单个平台时“继续网页搜索”，放不下换行）、一句范围说明（点开搜索范围面板）；页宽 600 起搜索框和平台条一行（`searchOneRowWidth`，`features/search/search_widgets.dart:20`），框最宽 480（`:23`）；往下滑收起筛选区（竖屏连平台条）；“还有 N 个平台在搜索…”、失败说明卡（查看是哪些、重试、搜索范围、代理设置、继续网页搜索）、四种空状态、搜索历史、识别到直播链接；“全部”的结果卡片标平台；Windows 缺 WebView2 只在点网页搜索时问（取消 / 打开下载页 / 用系统浏览器打开）；Esc 返回。
  - **网页搜索**：两行标题“网页搜索 / 平台 · 关键词”靠左；顶栏“使用系统浏览器打开”和 ✕；返回先在网页里后退；认出直播间时底部提示条（平台标志、“这是一个直播间”、“平台 · 房间号 N”、“进入”、✕），竖屏左右 12，页宽 600 起靠右宽 420，1200 起右下角宽 440；进入时压在网页上面，返回回到网页；失败页多“使用系统浏览器打开”；没有应用内网页（Linux、Windows 缺 WebView2）时是系统浏览器页；手机上用电脑版网页（3.x 的 Windows Chrome User-Agent）。
  - **观看记录**：标题“观看记录”下面一行“18 / 50 条”（不限时“18 条 / 不限”），居中（D-011）；顶栏筛选、刷新、保留数量、清空四个按钮；按今天、昨天、近 7 天、更早分组；卡片右上删除（先确认）；保留数量对话框恢复 3.x 的整宽“应用”按钮；改小数量时提醒删几条；Esc、返回键先关筛选。
  - **标签管理**：所有宽度一列、最宽 720；每行把手、名字、描述（没有时“暂无描述”斜体）、“N 个直播间”、置顶 / 编辑 / 删除三个 48 的按钮（3.x 的 Remix 图标），第一个标签的置顶是实心、不能点；说明一行小字；空状态 `AppStatusView` 加“＋ 添加标签”；详情加直播间数、按钮“编辑标签”“关闭”；编辑对话框字数提示、错误写在框下。
- 内部怎么工作：
  - 卡片数据：页面拿到 `LiveRoom` → `AudiencePolicy.cardOf`（`shared/rooms/room_cards.dart:82`）转成 `RoomCardData`（`packages/live_ui/lib/src/widgets/room_card.dart:44`：标题、主播名、头像、封面、在播、录播、人数、受限文字、平台名、未开播）→ `RoomGridCard`（`room_grid.dart:92`）接上卡片外观设置（`cardAppearanceOf`，`room_cards.dart:128`，手机和电脑各一份，读 3.x 的旧键）、点按进房和长按菜单 → `LiveRoomCard`。
  - 列表外壳没有做成一个组件（A02 已记）：热门、分区房间用 `RoomFeedView`（`room_grid.dart:357`，骨架、空、出错 `loadErrorStatus` `:290`、出错横幅 `refreshErrorBanner` `:329`、移动流量 `MobileDataBanner` `:221`、回到顶部 / 底部 `JumpButtons` `:198`、电脑 ← → 翻页）；关注、搜索、观看记录、分区各自拼这些块。
  - 电脑翻页：`usesDesktopPages`（`shared/rooms/paging.dart:18`：窗口宽 >680 且不是手机系统，照 3.x 的输入方式判断）时底部 `PaginationBar`（`:37`：刷新、上一页、页码、下一页、每页条数、跳转），否则下拉刷新、滑到底加载。
  - 列数：`RoomGridGeometry`（`room_grid.dart:30`）用页面 `LayoutBuilder` 的宽度和窗口宽度分档调 `GridColumns.rooms`（`grid_columns.dart:73`）；分区用 `GridColumns.areas`（`:78`）。
  - 状态：除了骨架都是 `live_ui` 的 `AppStatusView`（第一个按钮浅色实心、第二个文字按钮，A02.1 C1）和 `StatusBanner`。
- 完成度（和 3.x 对照）：
  - 一致的：卡片结构和角标位置、点按 / 长按 / 右键；三个预设和显示项、圆角 20；热门、关注、分区的标签都在标题位置；左右滑；下拉刷新和滑到底加载；电脑翻页栏和 ← →（v4 之前关注、分区、分区房间没有，这次补上）；回到顶部 / 底部；15 秒回到前台刷新；首选平台；搜索的四种排序、包含未开播、继续网页搜索、离底 480 自动加载；网页搜索只放行 http(s)、取消过的房间不再问；观看记录的三个对话框；标签管理的三个操作和图标、长按拖动。
  - 确认过的改动：A09.1 c1～c15（A1～A4）、A09.2 c1～c9（B1～B3）、A09.3 c1～c11（C1～C4）、A09.4 c1～c8（X1、X2、X4 按 A，X3 改用对话框）、A09.5 c1～c8（Y1、Y2）、A09.6 c1～c10（Z1～Z3）、A09.7 c1～c16（X1～X4）、A09.8 c1～c8（Y1～Y3）、A09.9 c1～c8（Z1～Z3）、A09.10 c1～c7（J1、J2）；都按 D-003 用建议 A，另有协调员当时的补充（分区卡片长按用对话框、取消关注按钮写“取消关注”、状态页按钮样式）。
  - 还缺：A09.11（Picarto 等“标题就是主播名”的卡片显示简介）；观看记录、标签管理、平台显示、关注分区、网页搜索没有 K90 记录（见“已知问题”）。

## 代码地图

`packages/live_ui`（卡片和网格的组件，样子由 A09.1 定）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `packages/live_ui/lib/src/widgets/live_room_card.dart`（767 行） | `LiveRoomCard`（`:36`）、`LiveRoomCardColors`（`:162`）、`LiveRoomCardMetrics`（`:177`）、封面角标 `CoverChip`（`:495`）、骨架 `RoomCardSkeleton`（`:566`）、紧凑行 `RoomRow`（`:649`，关注的未开播） | A09.1、A09.3 c5 |
| `packages/live_ui/lib/src/widgets/room_card.dart`（127） | `RoomAudienceKind`（`:4`）、`RoomAudience`（`:25`）、卡片的输入 `RoomCardData`（`:44`） | A09.1 |
| `packages/live_ui/lib/src/widgets/room_card_appearance.dart`（362） | 卡片外观、三个预设、3.x 旧键的读写；`RoomCardLayoutMetrics`（`:314`，行高跟字号） | A01.1、A11.2 |
| `packages/live_ui/lib/src/widgets/card_dialog.dart`（171） | `CardDialogAction`（`:8`）、`CardDialog`（`:38`，房间卡片和分区卡片的长按对话框） | A09.1 c10、A09.4 X3 |
| `packages/live_ui/lib/src/widgets/follow_pill.dart`（70） | `FollowPill`（`:10`，“＋ 关注 / ✓ 已关注”，长按对话框和分区房间顶栏） | A09.1 c11、A09.5 c3 |
| `packages/live_ui/lib/src/theme/grid_columns.dart`（85） | `WindowWidthClass`（`:5`）、`GridColumns`（`:38`：`roomMinWidth` `:58`、`areaMinWidth` `:66`、`rooms` `:73`、`areas` `:78`） | A09.1 c15、A09.4 c5 |
| `packages/live_ui/lib/src/widgets/page_title.dart`（55） | `PageTitle`（`:11`，两行标题，网页搜索、观看记录） | A09.8 c2、A09.9 c2 |
| `packages/live_ui/lib/src/widgets/adaptive_panel.dart` | `showAdaptivePanel`（全部平台、搜索范围：竖屏底部、宽 600 起右侧 360） | A02.2、A09.2 c2、A09.7 c6 |

应用侧（`apps/pure_live/lib/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `shared/rooms/room_grid.dart`（750） | `roomGridPadding` 6（`:26`）、`RoomGridGeometry`（`:30`）、`RoomGridCard`（`:92`）、`RoomGridSkeleton`（`:146`）、`JumpButtons`（`:198`）、`MobileDataBanner`（`:221`）、`ReloadWhenOnline`（`:250`）、`loadErrorStatus`（`:290`）、`refreshErrorBanner`（`:329`）、`RoomFeedView`（`:357`，热门和分区房间的整页） | A09.1、A09.2、A09.5 |
| `shared/rooms/paging.dart`（277） | `phonePageSize`（`:14`）、`usesDesktopPages`（`:18`）、`PaginationBar`（`:37`，电脑翻页栏） | A09.2 c1、A09.3 c1、A09.4 c1 |
| `shared/rooms/room_menu.dart`（290） | `RoomMenuAction`（`:18`）、`showRoomMenu`（`:60`）、`confirmUnfollowRoom`（`:158`）、`followRoom`（`:169`）、`unfollowRoom`（`:188`，撤销）、`shareRoom`（`:236`）、`editRoomTags`（`:261`） | A09.1 c10～c12 |
| `shared/rooms/room_tags_dialog.dart`（488） | `roomTagNameMaxLength` 15（`:13`）、`roomTagNoteMaxLength` 40（`:16`）、`roomTagTwoColumnWidth` 400（`:20`）、`RoomTagPicker`（`:32`） | A09.1 c13、c14 |
| `shared/rooms/room_cards.dart`（164） | `AudiencePolicy`（`:34`）、`cardOf`（`:82`）、`mixesPlatforms`（`:104`）、`cardAppearanceOf`（`:128`） | 数据（I01.2），界面用 |
| `features/popular/popular_page.dart`（373） | `PopularPage`（`:33`，标签在标题位置、⌄、`showsHomeBarButtons` 决定左右按钮 `:168-175`）、`PlatformPicker`（`:225`）、`_PlatformTile`（`:304`） | A09.2 |
| `features/popular/popular_grid.dart`（49） | `popularNoticeOf`（`:14`，平台说明）、`PopularPlatformView`（`:23`，配文字后交给 `RoomFeedView`） | A09.2 c4～c6 |
| `features/favorite/favorite_page.dart`（606） | `favoriteOneRowWidth` 840（`:27`）、`favoriteLargeCardMinWidth` 300（`:31`）、`favoriteRowMinWidth` 320（`:34`）、`FavoritePage`（`:49`）、`_TagStrip`（`:323`）、`_FollowGrid`（`:362`，网格 / 紧凑行 `:433-451`、`mixedPlatforms` `:486`、`PaginationBar` `:526`）、`_RowNote`（`:592`） | A09.3 |
| `features/areas/areas_page.dart`（259） | `AreasPage`（`:24`）、`AreasView`（`:40`，平台标签在标题位置）、`_FollowedAreasButton`（`:204`） | A09.4 c1、c7 |
| `features/areas/platform_areas_view.dart`（318） | `areasButtonClearance` 80（`:15`）、`PlatformAreasView`（`:24`，次级分类标签、只有一个分类不显示）、`_AreasSkeleton`（`:287`） | A09.4 c2、c4、c8 |
| `features/areas/area_card.dart`（291） | `AreaCaption`（`:13`）、`AreaCard`（`:29`）、`AreaGridSkeleton`（`:155`）、`AreaGrid`（`:227`） | A09.4 c3、c5、c6 |
| `features/areas/areas_common.dart`（146） | `areaCardExtent`（`:33`）、`areaPlatformAndCategory`（`:42`）、`showAreaDialog`（`:50`）、`openArea`（`:82`）、`toggleAreaFollow`（`:107`）、`confirmUnfollow`（`:131`） | A09.4 c6、A09.6 c2 |
| `features/areas/favorite_areas_view.dart`（165） | `favoriteAreaTabs`（`:31`，只列有关注的平台）、`FavoriteAreasView`（`:49`） | A09.6 c1～c6 |
| `features/areas/area_artwork.dart`（217） | `AreaPictures`（`:49`）、`AreaArtwork`（`:164`，图片三种占位） | A09.4 c1 |
| `features/area_rooms/area_rooms_page.dart`（142）、`follow_area_button.dart`（55） | `AreaRoomsPage`（`:20`）、`AreaRoomsView`（`:46`，标题两行、`RoomFeedView`）；`FollowAreaButton`（`:14`，`FollowPill`） | A09.5 |
| `features/hot_areas/hot_areas_page.dart`（252） | `toggleHotArea`（`:13`）、`reorderHotAreas`（`:25`）、`preferredAfter`（`:35`）、`hotAreasMaxWidth` 720（`:39`）、`HotAreasPage`（`:55`） | A09.6 c7～c10 |
| `features/search/search_view.dart`（767） | `webView2DownloadPage`（`:29`）、`SearchView`（`:41`，排法、往下滑收起、Esc、WebView2 提问、结果网格 `RoomGridCard` `:569`） | A09.7 |
| `features/search/search_widgets.dart`（641） | `searchPlatformStripHeight` 56（`:15`）、`searchOneRowWidth` 600（`:20`）、`searchFieldMaxWidth` 480（`:23`）、`SearchPlatformStrip`（`:28`）、`SearchOptionsBar`（`:141`）、`_SortButton`（`:235`）、`SearchCoverageLine`（`:276`）、`_LeadThenRest`（`:354`）、`SearchLinkBanner`（`:453`）、`SearchPendingRow`（`:505`）、`SearchHistoryPanel`（`:535`）、`AnchorResultTile`（`:597`） | A09.7 c2～c13 |
| `features/search/search_scope.dart`（263） | `overseasPlatforms`（`:14`）、`SearchScopeStore`（`:34`，数据）、`showSearchScopePanel`（`:71`）、`SearchScopePanel`（`:92`） | A09.7 c6 |
| `features/search/web_search_view.dart`（452） | `WebSearchRequest`（`:15`，3.x 的 `{url, platform}` 加可选 `keyword`）、`WebSearchView`（`:65`，两行标题 `:167-169`）、`WebSearchRoomBar`（`:264`）、`WebSearchFailure`（`:346`）、`_StateBody`（`:382`） | A09.8 |
| `features/history/history_page.dart`（434）、`history_limit_dialog.dart`（194） | `HistoryPage`（`:44`，标题居中 `:234-238`、四个按钮、分组、`LiveRoomCard` `:411`）；`showHistoryLimitDialog`（`:20`）、`HistoryLimitDialog`（`:32`） | A09.9 |
| `features/tags/tags_page.dart`（298）、`tag_tile.dart`（235）、`tag_editor_dialog.dart`（249） | `TagsPage`（`:39`）；`followedTagCounts`（`:10`）、`TagTile`（`:25`）、`showTagDetails`（`:189`）；`tagNameMaxLength` 15（`:10`）、`tagDescriptionMaxLength` 40（`:13`）、`showTagEditor`（`:18`） | A09.10 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_ui/test/live_room_card_test.dart`（14）、`room_card_test.dart`（4） | A09.1：卡片各状态、平台标三种模式、12 号等宽、颜色角色深浅两套、点按 / 长按 / 右键、悬停和焦点、紧凑行、骨架、`RoomRow`、`FollowPill`、房间和分区的列数表、面板位置；卡片高度和外观 JSON |
| `apps/pure_live/test/shared/shared_test.dart`（8）、`room_lists_test.dart`（2） | 长按对话框结构和顺序、Esc、关注后关闭并提示、先问再关注、原地新建标签、红色取消关注和撤销、横屏两列 |
| `apps/pure_live/test/features/popular/popular_test.dart`（19） | A09.2：全部平台面板（竖屏底部、宽屏右侧）、393 / 852 / 1280 的列数和边距、空状态文字、标签在标题位置、翻页栏 |
| `apps/pure_live/test/features/favorite/favorite_test.dart`（16） | A09.3：竖屏两行 / 宽 1000 一行、“全部”标平台、未开播紧凑行、都没开播的说明和按钮、数量不截断、标签筛选、撤销取消关注 |
| `apps/pure_live/test/features/areas/areas_test.dart`（14） | A09.4～A09.6：次级分类标签、卡片只写名字、长按对话框、取消关注先确认、抖音分类、只有一个分类；分区房间的副标题、关注胶囊、隐藏不能播放的房间；关注分区只列有关注的平台、“去分区”；平台显示 720、把手、开关对齐 |
| `apps/pure_live/test/features/search/search_test.dart`（27）、`web_search_test.dart`（4 个用例声明） | A09.7：搜索框、竖屏和一行排法、列数和标平台、往下滑收起、排序菜单、搜索范围面板、骨架和空状态、WebView2、滚轮横滚、右键 = 长按、Esc；A09.8：参数、系统浏览器页、提示条位置、失败页 |
| `apps/pure_live/test/features/history/history_page_test.dart`（17） | A09.9：标题和条数、四个按钮、列数、Esc 先关筛选、右键菜单、空页面、保留数量对话框 |
| `apps/pure_live/test/features/tags/tags_page_test.dart`（7） | A09.10：一行一个、按钮顺序和 48、置顶不能点、详情和编辑对话框、横屏和宽屏 720 |

## 3.x 基线

文件在 `git show v3.2.11:lib/` 下：

- 卡片：`common/widgets/room_card.dart`（1411 行）：卡片 `:1053-1229`（`Card` 白 / `grey[900]` `:1073`，长按和右键 `:1076-1078`）、封面角标 `:1092-1171`、人数 `CoverMetricBadge` `:1350-1411`、紧凑信息行 `:978-1051`、长按对话框 `:177-316`、关注确认 `:125-175`、设置标签 `:318-856`、取消关注 `:1260-1273`；`common/widgets/room_card_layout.dart`（52）；外观设置 `common/services/settings/room_card_settings_controller.dart:52-61`（默认“标准”预设、圆角 20）。
- 列表外壳：`common/base/base_page_view.dart`（308：页顶说明和流量提示 `:66-134`、状态 `:137-223`、第一次加载转圈 `:170`）、`base_page_view_extension.dart`（100：← → 翻页 `:6-61`、回到顶部 / 底部 `:64-100`）、`desktop_components.dart`（285：翻页栏 `:44-185`）。
- 页面：`modules/popular/popular_page.dart`（46）、`popular_grid_view.dart`（89，列数 `:16`）；`modules/favorite/favorite_page.dart`（319）、`room_grid_view.dart`（139）；`modules/areas/areas_page.dart`（88）、`areas_grid_view.dart`（289，列数 3/5/7/9 `:263`）、`widgets/area_card.dart`（149）、`favorite_areas_page.dart`（143）；`modules/area_rooms/area_rooms_page.dart`（288，关注浮动按钮 `:90-288`）；`modules/hot_areas/hot_areas_page.dart`（132）；`modules/search/search_page.dart`（370）、`search_platform_strip.dart`（105）、`web_search_page.dart`（215）；`modules/history/history_page.dart`（407）；`modules/tags/tag_management_page.dart`（736）；首页 `modules/home/tablet_view.dart`（176）、顶栏按钮 `common/widgets/menu_button.dart`（84）、`common_appbar_actions.dart`（79）。
- 列数：热门、分区房间、搜索、历史 `>1280` 五列、`>960` 四列、`>640` 三列、其余两列；关注“紧凑模式”关时 4/3/2/1；分区 3/5/7/9；各页边距热门 6、关注 12、搜索 8；判断宽屏读整屏宽度（`Get.width`，680 一个分界）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（卡片长按或右键 = 操作菜单）、第 7 条（返回链：对话框、面板、筛选先关；Esc 同一条）、第 16 条（键盘：← → 翻页是 3.x 电脑翻页栏的快捷键）；另有 3.x 的再点底部“关注”刷新、回到前台超过 15 秒刷新热门和分区、首选平台、预取下一个平台、分区页平台之间不能左右滑。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 观看记录、标签管理、平台显示、关注分区在 K90 上没有记录；网页搜索（F-SRC-04）明确“没验证”；这些任务登记为“完成” | [S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)“观看记录、账号页：没在真机上看”；[S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)（F-SRC-04） | 不符合 PROCESS 3.2“完成必须有真机结果” | 写进本单元报告；建议这几项并入 S02.6 或改回“待真机” |
| 首页三页（热门、关注、分区）和录制中心从 `features/home/` 引用 `MenuButton`、`home_menu.dart`（顶栏左右按钮和 `homeTabletBreakpoint`）；`area_rooms` 引用 `areas/areas_common.dart`；`search` 引用 `settings/settings_model.dart` | `tools/gate/ui_baseline.json` 的 `cross_feature_imports`；`features/popular/popular_page.dart:168-175`、`features/areas/areas_page.dart:12-13`、`:214` | 违反“功能目录之间不互相引用”，靠基线放行 | 顶栏按钮挪到 `shared/` 归 A06；分区共用部分挪到 `shared/` 可在下一个改分区的任务里做；没有专门任务 |
| `filterAreas` 没有入口（A09.4 去掉了分区筛选按钮，函数留着） | `features/areas/area_catalog.dart:114` | 死代码 | 下次改分区时删掉，或者确认要恢复筛选（需要维护者决定） |
| 平台显示页“显示”组标题右边的“恢复默认”是 v4 加的，设计没画也没列为偏差 | `features/hot_areas/hot_areas_page.dart:54`、`:79-84`（`_reset`，确认框“恢复默认”） | 设计和实现不一致（小） | A09.6 记录“保留的 v4 内容”，维护者看一眼，不要就删这一个按钮 |
| 分区、关注分区、平台显示、标签管理、分区房间在电脑上按 Esc 不返回（只有搜索、网页搜索、观看记录处理了） | `features/search/search_view.dart`、`web_search_view.dart`、`history/history_page.dart` 用 `EscapeBack`；其余页面没有 | 规范 5.4 的 Esc 返回链不全 | A05.1 c3 |
| 电视的卡片是另一个组件 `TvRoomCard`，不是 `LiveRoomCard` 的电视样式 | `apps/pure_live/lib/tv/widgets/tv_room_grid.dart:126` | 违反“同一功能各客户端同一组件” | A17.3 |
| Picarto、CHZZK 频道搜索的卡片两行都是频道名，简介没地方显示 | `shared/rooms/room_cards.dart:82-99` | 已批准升级 11-5 只做了一半 | A09.11 |
| 代码注释里还用旧编号（`U.4a c15`、`U.5a c12`、`U.4c c6` 等），本子分类的文件里约 74 处；`search_widgets.dart:16` 的注释里还有一个换坏的路径“docs/TASKS.md/ U.5a c12” | `shared/rooms/room_grid.dart:25`、`features/favorite/favorite_page.dart:29` 等 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换（单元 2 已建议） |
| `inventory/V3_UI.md` 第 2、3、4 节有几处和 3.x 代码对不上（空状态原文、录播标、默认不标平台、卡片圆角 20、分页不止回到顶部、关注列数等），A09.1～A09.3 的 README 写了更正，清点文件本身没改 | `docs/inventory/V3_UI.md` 第 2～4 节 | 只看清点会被误导 | Z 组（文档维护）照各任务 README 的“更正”改清点 |

## 相关决定和规范

- D-003：A09.1～A09.10 的全部待选由维护者按建议 A 定（A09.4 X3 由协调员改成对话框）。
- D-009：能下拉刷新的列表照 3.x 两端回弹、经典刷新头（热门、关注、分区房间、观看记录；A03.1）。
- D-011：标题位置照 3.x 实际运行的样子：热门、分区、观看记录、关注（窄屏）居中，其余靠左（`centredPageTitle`，`packages/live_ui/lib/src/theme/live_theme.dart:24`）。
- D-021：直播间里取消关注用小菜单，首页长按卡片仍是居中确认框（`confirmUnfollowRoom`）。
- [specs/UI.md](../../specs/UI.md)：第 3 节第 4 条（状态统一用 `live_ui`）、第 6、7 条（卡片和长按对话框各处一个）；第 5.1 节第 5 条（只读父组件的宽度）、第 5.3 节（网格列数公式、内容最宽 720）；第 7 节（对话框、面板、提示条带“撤销”4 秒）；第 8.1 节（卡片颜色角色）；第 8.2 节（人数等宽、“1.2万”）；第 9.3 节（骨架静态无扫光、阴影只用于浮层）；附录 A 第 7、14、16 条。

## 测试和验证

- 自动测试：`cd packages/live_ui && flutter test test/live_room_card_test.dart test/room_card_test.dart`；`cd apps/pure_live && flutter test test/features/popular test/features/favorite test/features/areas test/features/search test/features/history test/features/tags test/shared/shared_test.dart test/shared/room_lists_test.dart`（上表）。覆盖了每个确认的改动和 393×852、852×393、1280×800 三种尺寸的列数；缺的：没有截图对照（深色主题下的卡片颜色只断言颜色值）；应用内网页（平台视图）在测试里跑不起来，网页搜索的真实网页没覆盖；没有滚动帧时间的基准（规范 9.4 的“热门快速滚动”）。
- 真机：[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节第 1 条（关注冷启动、下拉、再点“关注”）、第 2 条（搜索）、第 3 条（网页搜索，S02.6）、第 4 条（热门、分区、关注分区）、第 5 条（观看记录）、第 9 条（卡片长按：关注、设标签、分享）。已有结果：S02.2 冒烟（2026-10-02，`288fec0ec`）首页“关注”和“热门”通过；S02.3 搜索、分区、分区房间通过，观看记录没看。

## 路线

1. 补真机：观看记录、标签管理、平台显示、关注分区、卡片长按三项、网页搜索（S02.6 的 F-SRC-04），结果写回各任务的“实现和验证”；看出问题的开新任务（标题写“接 A09.x”）。
2. A09.11：先列出“标题就是主播名、带简介”的来源（Picarto、CHZZK 频道搜索……），出图定规则，再改 `cardOf` 的第二行（第三档，小）。
3. 顺手的清理（没有单独任务，放进下一个改到这些文件的任务）：`filterAreas` 删或恢复入口；平台显示的“恢复默认”去留；首页顶栏按钮挪到 `shared/`（A06）。
4. 以后：Esc 返回补全（A05.1）；电视卡片换成同一组件的电视样式（A17.3）；滚动帧时间基准（R01）。新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`shared/rooms/`、`features/popular/`、`favorite/`、`areas/`、`search/`、`history/`、`tags/`
- 进度：`███████████████████░` 95%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A09.1 | 房间卡片 | 界面 | 完成 | 2026-10-01 | 7daeb3805 | [设计或说明](A09.1-房间卡片/README.md)、[记录](A09.1-房间卡片/record.md)、[评审页](A09.1-房间卡片/page/01-说明.jpg) |
| A09.2 | 热门 | 界面 | 完成 | 2026-10-01 | 7daeb3805 | [设计或说明](A09.2-热门/README.md)、[记录](A09.2-热门/record.md)、[评审页](A09.2-热门/page/01-说明.jpg) |
| A09.3 | 关注 | 界面 | 完成 | 2026-10-01 | 7daeb3805 | [设计或说明](A09.3-关注/README.md)、[记录](A09.3-关注/record.md)、[评审页](A09.3-关注/page/01-说明.jpg) |
| A09.4 | 分区 | 界面 | 完成 | 2026-10-01 | 7daeb3805 | [设计或说明](A09.4-分区/README.md)、[记录](A09.4-分区/record.md)、[评审页](A09.4-分区/page/01-说明.jpg) |
| A09.5 | 分区房间 | 界面 | 完成 | 2026-10-01 | 7daeb3805 | [设计或说明](A09.5-分区房间/README.md)、[记录](A09.5-分区房间/record.md)、[评审页](A09.5-分区房间/page/01-说明.jpg) |
| A09.6 | 热门分区、关注的分区 | 界面 | 完成 | 2026-10-01 | 7daeb3805 | [设计或说明](A09.6-热门分区、关注的分区/README.md)、[记录](A09.6-热门分区、关注的分区/record.md)、[评审页](A09.6-热门分区、关注的分区/page/01-说明.jpg) |
| A09.7 | 搜索 | 界面 | 完成 | 2026-10-02 | 480a8d8ac | [设计或说明](A09.7-搜索/README.md)、[记录](A09.7-搜索/record.md)、[评审页](A09.7-搜索/page/01-说明.jpg) |
| A09.8 | 网页搜索 | 界面 | 完成 | 2026-10-02 | 773f31fa5 | [设计或说明](A09.8-网页搜索/README.md)、[记录](A09.8-网页搜索/record.md)、[评审页](A09.8-网页搜索/page/01-说明.jpg) |
| A09.9 | 观看历史 | 界面 | 完成 | 2026-10-02 | cbd96fcc6 | [设计或说明](A09.9-观看历史/README.md)、[记录](A09.9-观看历史/record.md)、[评审页](A09.9-观看历史/page/01-说明.jpg) |
| A09.10 | 标签管理 | 界面 | 完成 | 2026-10-01 | 3b00b519f | [设计或说明](A09.10-标签管理/README.md)、[记录](A09.10-标签管理/record.md)、[评审页](A09.10-标签管理/page/01-说明.jpg) |
| A09.11 | Picarto 搜索卡片显示频道简介（UPGRADES 11-5，先改卡片设计） | 界面 | 未开始 | — | — | [设计或说明](A09.11-Picarto搜索卡片简介/README.md)、[任务书](A09.11-Picarto搜索卡片简介/brief.md) |

## 还没完成的

- **A09.11 Picarto 搜索卡片显示频道简介（UPGRADES 11-5，先改卡片设计）**（未开始，第三档，规模 小）
  - 阶段：列出受影响的来源，出图和评审 → 卡片第二行显示简介
  - 说明：平台层的 introduction 已有（E03.3）；现在卡片两行都是频道名。CHZZK 频道搜索也是标题等于主播名，规则通用时一起受影响
  - 来源：UPGRADES 11-5（V03.3 核对；E06.1 第 3 条 c2 没做）

<!-- docs:生成结束 -->
