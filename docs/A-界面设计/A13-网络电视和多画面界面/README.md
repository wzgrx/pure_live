# A13 网络电视和多画面界面

两块相对独立的界面：设置里的“IPTV 设置”页（播放列表和节目单的导入、同步、选择，3.x 的“IPTV 设置”和“订阅源管理”两页合一），以及多画面页（多个直播同时看，选中格的控制、选台、沉浸和全屏）。

## 范围

- 包括：
  - 网络电视管理（A13.1）：`features/iptv/` 的一页——统计、播放列表组、节目单组、同步和播放组；导入方式、网络导入、粘贴文本、本地文件、同名替换、删除、选节目单、同步间隔、请求头对话框；卡片的“更多”菜单；各种状态（骨架、读取失败、两组空状态、未启用、全部同步进度、默认节目单导入中）。
  - 多画面（A13.2）：`features/multiview/` 的界面——四种布局（单个、左右两格、2×2、1+3）、格子的编号和状态、选中格的控制（清晰度、线路、暂停、刷新、换台、进入直播间、关闭、房间音量）、选台、工具条（布局、弹幕、弹幕设置、全部静音、小格省流）、恢复上次的提示、沉浸和全屏、1+3 大格控制条、格子面板、弹幕设置面板、返回和 Esc 链。
- 不包括（归哪里）：
  - 导入、解析 m3u、节目单、同步的逻辑（`packages/live_iptv` 的 `IptvImporter`、`IptvLibrary`）→ [L01 网络电视](../../L-网络电视和点播/L01-网络电视/README.md)；网络电视频道在分区页里浏览 → [A09](../A09-浏览界面/README.md)；直播间里的节目单和回看 → [A07.7](../A07-直播间界面/A07.7-直播间的状态/README.md)、[L02](../../L-网络电视和点播/L02-节目单和回看/README.md)；分享 m3u 文件导入 → O03.2。
  - 多画面的播放会话、格数、声音来源、省流、弹幕连接（`logic/multiview_controller.dart` 的行为）→ [N01 多画面](../../N-多画面和投屏/N01-多画面/README.md)；多画面飞行弹幕的帧率 → N01.2。直播间的清晰度、线路小菜单（`StreamMenuButton`）、面板外壳（`RoomSidePanel`）、弹幕设置内容（`DanmakuSettingsContent`）是 A07.6、A08 的组件，A13.2 把它们挪到共用位置后直接用。
  - 设置总览里的“IPTV 设置”入口行（“直播来源”组，`features/settings/settings_model.dart:55`）、多画面开关 `enableMultiView` → [A11](../A11-设置界面/README.md)；首页的多画面入口按钮 → A06。
  - 电视上的网络电视页 → [A17.5](../A17-电视界面/A17.5-电视网络电视和影片/README.md)；pure_live_TV 没有多画面，电视不做。

## 现状：做到哪、怎么工作的

- 用户看得到的（A13.1、A13.2 登记为完成，2026-10-01 合并；**都没有 K90 结果**，见“已知问题”）：
  - **网络电视管理**（设置 → 直播来源 → IPTV 设置，路由 `RoutePath.kIptv`，`routes/app_router.dart:53`）：标题“IPTV 设置”（靠左，D-011），标题栏右边“同步”同步全部网络来源（`iptv_page.dart:427-438`）。一页从上到下（`build` `:416`）：未启用时黄色提醒卡和“启用”（`_enableNotice` `:498`）→ 统计（播放列表、频道、节目单，20 号等宽数字，`IptvStats` `iptv_cards.dart:427`；全部同步时换成“正在同步网络来源 1 / 3”和进度条，`IptvSyncProgress` `:471`）→ 播放列表组（导入行 + 卡片，`_playlistSection` `iptv_page.dart:531`）→ 节目单组（导入行、“当前使用的节目单”一行 + 卡片，`_guideSection` `:588`）→ 同步和播放（启动时全自动同步、同步间隔 2～72 小时、请求头，`_settingsSection` `:686`）。卡片（`IptvSourceCard` `iptv_cards.dart:24`）：左边 v3 的图标和格式标记（播放列表 `primaryContainer`、节目单暖色容器 `LiveSemanticColors.warmContainer`），名字、地址、“1,024 个频道 · 今天 08:00 更新”，“网络 / 本地”灰标签（`IptvTag` `:291`），使用中的节目单主色描边 +“使用中”；按钮同步、删除、自动同步开关，卡片宽 ≥520 一行、更窄两行（`iptvCardOneRowWidth` `:17`），本地来源只有删除，忙时变灰。点卡片不打开地址；右上角“更多”或右键：在浏览器中打开 / 打开文件、复制地址（`_menu` `:90-108`、`:194`）。导入方式对话框照 3.x 的顺序（本地、网络，再加“粘贴文本”或“默认节目单”，`chooseImportOrigin` `iptv_import.dart:84`）；网络导入带标签的“订阅地址”“名称（可选）”，失败原因在框下、按钮变“重试”，同名先问（`IptvNetworkImportDialog` `:273`、`confirmReplace` `:240`）；本地文件走系统选择器（标题“选择播放列表文件 / 选择节目单文件”，`importPickerTitle` `:48`）。删除写清后果，删正在使用的节目单改用下一个（`_delete` `iptv_page.dart:342`）；节目单只在“当前使用的节目单”一行切换（`_chooseGuide` `:99`，提示“已改用“名字””）。第一次进来自动导入一次默认节目单（`_maybeLoadDefaultGuide` `:124`，`meta` 标记 `defaultGuideMetaKey` `:42`）。一栏最宽 720 居中（`ReadableContent` `:489`）。
  - **多画面**（首页的“多画面”按钮，设置 `enableMultiView` 打开时才有，`features/home/menu_button.dart:103`、`:118`）：三种排法按页面宽高定（`_arrangementOf` `multiview_page.dart:437-442`）：
    - 竖屏：工具条一行（布局只写文字），格子按 16:9 在上（最多占页面一半，1+3 大格在上、三小格一排），下面是选中格的控制和选台（`_portraitBody` `:547`）。
    - 横屏手机（高 <480 且横向）：工具条并进顶栏，右栏宽 = 页面宽 − 画面区宽（256～360，`:575-604`），平时放控制，点空格或“换台”换成选台（选完一个目标跳到下一个空格），右栏能收起（`_FoldHandle` `:908`）。
    - 宽屏（宽 ≥840）：布局带图标，右栏 360 同时放控制和选台（`_wideBody` `:606`）。
    - 格子（`MultiviewCellView` `widgets/cell_view.dart:15`）：编号、声音来源 2 像素描边和角标、选台目标虚线框（`_DashedFrame` `:445`）、省流标（`:117-123`）、暂停压暗写“已暂停”、空格 / 解析中 / 未开播 / 出错都是黑底白字（`_Placeholder` `:246`，出错原因 `cellFailureText` `:358`）；电脑 1+3 末尾“添加画面”槽（`AddCellSlot` `:473`）。点格子 = 选中并成为声音来源（附录 A 第 13 条）；1+3 点小格晋升大格；普通模式长按 / 右键 = 选中（不换声音），沉浸和全屏下打开格子面板（`_onCellTap` `multiview_page.dart:270`、`_onCellLongPress` `:309`）。
    - 选中格的控制（`MultiviewCellControls` `widgets/cell_controls.dart:46`）：房间行和“原画 ⌄”“线路1 ⌄”两个小菜单按钮（`_StreamButtons` `:248`）、五个按钮（暂停、刷新、换台、进入直播间、关闭这一格，圆 40、点击区 48，`_Buttons` `:307`）、房间音量（窄于 384 时换到下一行，`_VolumeRow` `:386`，松手保存到 `roomVolumes`）。
    - 选台（`MultiviewRoomPicker` `widgets/room_picker.dart:128`）：关注 / 历史记录、搜索、开播的在前，已在格子里的标“第 N 格”排最后、点了选中那一格（`pickerRooms` `:40`）；格子都满时标题写“第 N 格换台”。
    - 工具条（`widgets/toolbar.dart`）：布局分段（`LayoutSegments` `:10`）、弹幕开关、弹幕设置、全部静音、小格省流（只在 1+3）（`ToolbarToggles` `:75`，圆 38、点击区 48）。弹幕设置是 A07.6 的面板（竖屏画面下方、横屏和宽屏右侧 360，`_danmakuPanel` `multiview_page.dart:716`），标题旁写“只在声音来源这一格显示 · 改动立即生效”。上次看过的格子在格子上方提示“上次看了 N 个直播间，要恢复吗？”（`_restoreBar` `:739`）。
    - 沉浸和全屏（`_bare` `:779`）：只有格子；退出按钮同一位置和样子（左上角安全区内 12、48 圆形，`_ExitButton` `:939`），16:9 屏幕没有黑边时被盖住的格子把编号和名字右移（`nameInset`）；1+3 大格控制条只在这两种模式出现（`FocusControlBar` `widgets/focus_bar.dart:15`：暂停、刷新、弹幕、弹幕设置、原画 ⌄、线路1 ⌄、音量、全屏，放不下横向滑动）；长按格子的面板横屏在右侧、竖屏在下方（`_overlayPanel` `:814`）。返回和 Esc：先关面板，再退沉浸 / 全屏，最后停掉所有格子再退出（`PopScope` `:445`、`_onBack` `:417`、Esc `:380`）。
- 内部怎么工作：
  - 网络电视：`iptvOverviewProvider`（`iptv_data.dart:19`）用 `database.watch(IptvTables.all, …)` 在 IPTV 表变化时重读 `IptvOverview.load`（`:40`：卡片排序网络在前、再按名字，内置热门列表最后）；导入、同步、删除经 `iptvImporterProvider`（`:10`，`packages/live_iptv` 的 `IptvImporter`）；“今天 08:00 更新”由 `updatedText`（`:127`）按 `iptvClockProvider`（`:15`，测试固定时钟）算；页面里一次只做一个导入（`_import` `iptv_page.dart:182`），单个卡片的操作经 `_runItem`（`:258`）记忙。
  - 多画面：`MultiviewController`（`logic/multiview_controller.dart:146`）管格子（`MultiviewCell` `:78`、阶段 `CellStage` `:48`）、布局（`MultiviewLayout` `:19`、`setLayout` `:407`、`promote` `:436`）、声音来源和房间音量（`_roomVolume` `:766`）；格数 `maxCells`（手机 4，`:155-162`；电脑按处理器数，`multiviewMaxCells` `logic/multiview_geometry.dart:10`）；格子位置 `WallGeometry`（`:43`，16:9，1+3 在“小格在下”和“小格在右”里取大格更大的一种）；每格只挂一次画面（`GlobalKey`，`widgets/wall.dart:16`）；看不见的格（1+3 滚出视野、应用隐藏）`setOffscreen`（`:623`）关视频解码只留声音；上次的画面存在 `multiview.session`（`logic/multiview_session.dart:10`）。
- 完成度（和 3.x 对照）：
  - 一致的：网络电视的全部设置项和存储键、导入方式、同名替换、同步间隔六档、请求头 500 字、一次只做一个导入；多画面的入口、四种布局（默认 2×2）、点格子换声音、1+3 晋升、长按 / 右键、点空格选台、选台内容、沉浸和全屏（手机全屏自动横屏）、返回和 Esc 先退模式、弹幕只在声音来源格、格数上限、小格省流、房间音量记住。
  - 确认过的改动：A13.1 c1～c17（H1～H4 按建议 A）、A13.2 c1～c15（W1～W4 按建议 A），都按 D-003。
  - 还缺：两块都没有 K90 结果；多画面飞行弹幕不跟弹幕帧率设置（N01.2）；IPTV 卡片“更多”仍是 Flutter 的 `showMenu`（见“已知问题”）。

## 代码地图

网络电视管理（`apps/pure_live/lib/features/iptv/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `iptv_page.dart`（730 行） | `IptvPage`（`:29`）；默认节目单标记 `defaultGuideMetaKey`（`:42`）；选节目单（`_select` `:83`、`_chooseGuide` `:99`）、默认节目单（`:124`、`:136`）、导入（`_import` `:182`、结果提示 `_announce` `:233`）、单个同步 / 全部同步 / 自动同步 / 删除（`:277`、`:295`、`:332`、`:342`）、卡片菜单动作（`:382`）、页面（`build` `:416`）、四组（`:498`、`:531`、`:588`、`:686`） | A13.1 c1、c2、c7、c11～c13、c16 |
| `iptv_cards.dart`（670） | `IptvCardAction`（`:6`）、一行按钮的分界 520（`:17`）、卡片 `IptvSourceCard`（`:24`，“更多”菜单 `:90`、右键 `:194`）、格式标记 `_Leading`（`:252`）、标签 `IptvTag`（`:291`）、按钮 `_CardButton`（`:331`）、自动同步行（`:372`）、菜单行（`:408`）、统计 `IptvStats`（`:427`）、同步进度 `IptvSyncProgress`（`:471`）、状态卡 `IptvStateCard`（`:514`）、骨架 `IptvSkeleton`（`:622`） | A13.1 c3～c6、c8、c16 |
| `iptv_import.dart`（539） | `IptvImportKind`（`:12`）、`IptvImportOrigin`（`:21`）、文件选择 `iptvFilePickerProvider`（`:41`，应用里是 `file_picker`，`askForFilePath` `:159` 是后备）、扩展名和选择器标题（`:44`、`:48`）、对话框标题 `IptvDialogTitle`（`:53`）、导入方式 `chooseImportOrigin`（`:84`）、同名替换 `confirmReplace`（`:240`）、网络导入 `IptvNetworkImportDialog`（`:273`）、粘贴文本 `IptvTextImportDialog`（`:430`） | A13.1 c9、c10、c15 |
| `iptv_settings.dart`（115） | 同步间隔选项（`:7`）和对话框 `chooseSyncInterval`（`:12`）、请求头上限 500（`:29`）和对话框 `editUserAgent`（`:35`） | A13.1 c14、c17 |
| `iptv_data.dart`（161） | `iptvImporterProvider`（`:10`）、`iptvClockProvider`（`:15`）、`iptvOverviewProvider`（`:19`）、`IptvOverview`（`:35`，`load` `:40`）、格式标记（`:85`、`:93`）、名字（`:102-109`）、千分位 `groupDigits`（`:115`）、`updatedText`（`:127`）、`sourceDetails`（`:143`）、失败原因 `failureText`（`:154`） | A13.1 c4、c10 |

多画面（`apps/pure_live/lib/features/multiview/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `multiview_page.dart`（962） | `MultiviewPage`（`:41`）；显示模式（`:58`）、排法（`:62`）、浮层（`:76`）、右栏宽 360 / 最小 256（`:92`、`:96`）；选台和选中（`_pick` `:217`、`_select` `:241`、`_openPicker` `:257`、`_onCellTap` `:270`、`_onCellLongPress` `:309`）、进入直播间（`:327`）、看不见的格（`:343`、`:352`）、Esc（`:380`）、模式切换（`:385`）、返回链（`:417`、`:424`）、排法判断（`:437`）、三种排法（`:547`、`:575`、`:606`）、弹幕设置面板（`:716`）、恢复提示（`:739`）、沉浸和全屏（`:779`、`:814`）、弹幕层（`:873-878`）；收起把手 `_FoldHandle`（`:908`）、退出按钮 `_ExitButton`（`:939`） | A13.2 c1～c3、c5、c11～c13、c15 |
| `logic/multiview_controller.dart`（952） | `MultiviewLayout`（`:19`）、`CellStage`（`:48`）、`MultiviewCell`（`:78`）、`MultiviewController`（`:146`：格数 `:155-162`、`setLayout` `:407`、`promote` `:436`、`setOffscreen` `:623`、房间音量 `:766`） | N01.1（逻辑）；A13.2 加了 `setOffscreen` |
| `logic/multiview_geometry.dart`（160）、`multiview_session.dart`（45） | 格数 `multiviewMaxCells`（`:10`）、1+3 可见范围 `visibleRailRange`（`:21`）、`cellAspect` 16:9（`:37`）、格子位置 `WallGeometry`（`:43`）；上次的画面 `multiview.session` 的读写（`:10-31`） | A13.2 c2、c3；N01.1 |
| `widgets/wall.dart`（191）、`cell_view.dart`（514） | 画面区 `MultiviewWall`（`:16`，每格一个 `GlobalKey`）；一格 `MultiviewCellView`（`:15`：角标 `_CornerMarks` `:175`、占位和各状态 `_Placeholder` `:246`、重试 `:334`、`cellFailureText` `:358`、播放层 `:364`、虚线框 `:445`、`AddCellSlot` `:473`） | A13.2 c6～c8 |
| `widgets/cell_controls.dart`（451） | 选中格的控制 `MultiviewCellControls`（`:46`）：按钮 40、点击区 48（`:16-24`）、房间行 `_RoomRow`（`:180`）、清晰度和线路 `_StreamButtons`（`:248`）、五个按钮 `_Buttons`（`:307`）、音量 `_VolumeRow`（`:386`） | A13.2 c4 |
| `widgets/toolbar.dart`（183）、`focus_bar.dart`（159） | 布局分段 `LayoutSegments`（`:10`）、开关 `ToolbarToggles`（`:75`）、`ToolbarToggle`（`:146`，圆 38 `:136`、点击区 48）；1+3 大格控制条 `FocusControlBar`（`:15`） | A13.2 c10、c14 |
| `widgets/room_picker.dart`（363） | `PickerSource`（`:11`）、排序 `compareMultiviewRooms`（`:21`）、`pickerRooms`（`:40`，“第 N 格”排最后）、标题 `PickerHeader`（`:70`）、`MultiviewRoomPicker`（`:128`）、一行 `_RoomTile`（`:256`）、开播状态 `_LiveStatus`（`:336`） | A13.2 c9 |

共用（A13.2 从直播间挪出来的）：`apps/pure_live/lib/shared/panels/side_panel.dart`（209：`roomSidePanelWidth` 360 `:13`、`RoomSidePanel` `:24`、`PanelLink` `:180`）、`shared/danmaku/danmaku_settings_content.dart`（`DanmakuSettingsContent`，直播间、多画面、设置的弹幕页共用）、`packages/live_ui/lib/src/widgets/stream_menu_button.dart`（清晰度、线路小菜单按钮）、`packages/live_ui/lib/src/theme/live_colors.dart`（`OnVideoColors` `:9` 的 `accent`、`error`；`LiveSemanticColors` `:160` 的暖色容器 `:213-219`）。

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/iptv/iptv_page_test.dart`（15 个声明，其中一个在循环里跑 1280×800 和 852×393 两种尺寸，共 16 个） | 一页的顺序和图标、竖屏卡片两行；宽屏 / 横屏一栏 ≤720、卡片按钮一行；“更多”菜单和右键、点卡片不打开；默认节目单只导入一次和空状态里的入口；导入方式顺序；网络导入、同名替换、失败原因；进行中关闭对话框导入继续；粘贴文本和本地文件；单个 / 全部同步、自动同步、删除；节目单只从“当前使用”切换、删除改用下一个；启用、自动同步、间隔、请求头；骨架；读取失败；340 宽 1.3 倍字号 |
| `apps/pure_live/test/iptv_store_test.dart`（2） | IPTV 数据写入 `pure_live.db` 再读回；3.x 的 `pure_live_tv.db` 只读导入一次（L01.2） |
| `apps/pure_live/test/features/multiview/multiview_page_test.dart`（7） | 竖屏（工具条、16:9 格子、编号、选台和声音、控制、“第 N 格”、清晰度小菜单、已暂停、关闭这一格、弹幕设置面板、沉浸退出）；暂停时的弹幕（A07.10）；点击区 48（A07.9 收尾）；竖屏 1+3；横屏手机；宽屏和全屏大格控制条；格子状态（深色主题） |
| `apps/pure_live/test/features/multiview/multiview_geometry_test.dart`（4）、`multiview_controller_test.dart`（6） | 格数按设备、可见范围、格子位置 16:9；选台和声音、未开播和失败、布局、弹幕跟着选中格、保存和恢复、看不见的格只有声音（N01.1、A13.2） |
| `apps/pure_live/test/features/multiview/multiview_support.dart` | 假会话和假房间（测试共用），不是测试用例 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下：

- 网络电视：`modules/iptv/iptv_page.dart`（943 行，“IPTV 设置”：四组 `:116-228`、默认节目单 `:72-96`、导入方式 `:302-430`、间隔 `:240-300`、请求头 `:501-691`、网络导入 `:693-806`、选 EPG `:808-943`）、`modules/iptv/iptv_manage.dart`（902 行，“订阅源管理”：页面 `:221-321`、统计 `:353-434`、卡片 `:448-619`，点卡片打开地址 `:481`，按钮一行的分界 680 `:523`，删除 `:833-901`）；同名对话框和文件选择 `core/iptv/services/iptv_import_manager.dart:261-276`、`epg_import_manager.dart:215-228`；设置页写法 `common/widgets/widget_extensions.dart:21-258`；设置总览的入口 `modules/settings/settings_page.dart:66-74`。
- 多画面：`modules/multiview/multiview_page.dart`（1390 行：显示模式 `:22-27`、`:353-419`，返回和 Esc `:131-169`，顶栏 `:360-375`，工具条 `:436-556`，格子 `:576-698`、`:933-1220`，1+3 控制条 `:700-790`，各底部面板 `:249-339`、`:793-883`，沉浸恢复按钮 `:1360-1390`）、`multiview_controller.dart`（1424 行，默认 2×2 `:291`，手机 4 格、电脑 9 格 `:73`、`:84`）、`widgets/multiview_room_picker.dart`、`widgets/multiview_fullscreen_surface.dart`（全屏退出按钮 `:30-56`）、`widgets/focus_rail_visibility.dart`；入口 `common/widgets/common_appbar_actions.dart:56-66`、`tablet_view.dart:109-118`。
- 必须保留（[specs/UI.md](../../specs/UI.md) 附录 A）：第 13 条（点格子切换声音焦点；一大多小中点小格晋升；长按或右键打开格子操作——现在普通模式是选中、沉浸和全屏是格子面板；点空格选直播间）；第 7 条（返回和 Esc 先关面板、先退沉浸和全屏）。网络电视：存储键 `isAutoSyncEnabled`、`autoSyncHoursInterval`、`customIptvUserAgent`、`selectedSourceId/Name` 不变；一次只做一个导入。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A13.1、A13.2 登记为“完成”，记录里没有 K90 结果（S02.3 写明“多画面、网络电视”没测） | 各任务 `record.md`；[S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) | 不符合 PROCESS 3.2；4 路同时解码的流畅度、真实 m3u 导入、系统文件选择器只在测试里模拟 | 写进本单元报告；真机在 [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)（CHECKLIST 第 1 节第 16、17 条，F-MV-06）；建议改回“待真机”或 S02.6 后补记 |
| IPTV 卡片的“更多”菜单仍是 Flutter 的 `showMenu`（`PopupMenuItem`），是应用里唯一剩下的一处；A02.3 定了所有小菜单用自己的 `showAppMenu`（实测高度定位、从按钮方向展开），`9f68079cc` 写“the last popup menus go”但没改这里 | `features/iptv/iptv_cards.dart:90-108` | 这个菜单还是从上往下长、动画不看“减少动态效果”（A02.3 的 P1、P4） | 归 [A02.3](../A02-组件/A02.3-贴着按钮的小菜单/README.md)（待真机）补改；写进本单元报告 |
| 多画面的飞行弹幕不跟弹幕帧率设置（`DanmakuOverlay` 没传 `fps`，3.x 跟 `danmakuFps`、`danmakuAutoFps`） | `multiview_page.dart:873-878`；3.x `modules/multiview/multiview_page.dart:1306` | 多画面弹幕每个刷新周期都画，费电 | [N01.2](../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)（未开始，V03.3 新开） |
| “小格自动降画质”按 3.x 的“小格省流”（手动开关）做，没有按格子尺寸自动选低清晰度 | `logic/multiview_controller.dart`；A13.2 记录“需要决定的事”第 1 条 | 不开省流时小格仍拉高清晰度 | 没有登记任务；要做时走 V01 提议（D-026） |
| 默认节目单导入失败的状态设计没画，沿用读取失败卡（标题“默认节目单导入失败”，按钮“重试”“导入节目单”） | `features/iptv/iptv_page.dart`、`iptv_cards.dart:514` 的 `IptvStateCard` | 文字和按钮是开发时定的 | 真机看时一并确认 |
| 电脑 1+3 超过 4 格时右栏和小格一列是否太挤，只在 1280×800 测过（取“小格在下”） | `logic/multiview_geometry.dart:95-99` | 1920 宽以上没有看过 | A13.2“拿不准的地方”第 5 条；X01（Windows）验证时看 |
| 代码注释、测试名还用旧编号（`U.2f`、`U.8`、`M13`、`B02` 等），本子分类的代码和测试约 18 处 | 例如 `multiview_page.dart:79`、`:91`、`widgets/focus_bar.dart:13`、`test/features/multiview/multiview_page_test.dart:296` | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003：A13.1 H1～H4、A13.2 W1～W4 都按建议 A。
- D-011：标题位置照 3.x 实际运行的样子，IPTV 设置、多画面都靠左（A13.1 记录里“本页自己设 `centerTitle: true`”已在 A02.1 的 `914784264` 去掉）。
- D-017：测试里的“现在”固定（`iptvClockProvider`，A13.1 记录里过零点失败的测试已改）。
- D-018：`isAutoSyncEnabled`、`autoSyncHoursInterval`、`customIptvUserAgent`、`selectedSourceId/Name`、`enableMultiView`、`roomVolumes`、`multiview.session` 等键不变。
- D-020：格子面板、弹幕设置面板往上甩不关闭（`RoomSidePanel`）。
- D-026：多画面的新需求（自动降清晰度、更多布局）先进 V01。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（阅读型内容最宽 720；多画面按父组件宽高排、宽屏右栏 360）、第 5.4 节（点击区域 48）、第 7 节（弹幕设置、格子面板是面板；IPTV 的对话框照 3.x；小菜单贴着按钮）、第 8.1 节（语义色：暖色容器、“正在直播”成功绿）、第 9.3 节（多格的播放器：格数按设备、看不见的格停解码）；附录 A 第 7、13 条。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/iptv test/iptv_store_test.dart test/features/multiview`（上表）。覆盖了每个确认的改动；缺的：多画面真实解码的帧时间（只用假会话）、IPTV 系统文件选择器（测试用后备的输入路径对话框）、截图对照。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 16 条（多画面 2×2 放 4 个国内直播、点格子换声音、沉浸和全屏进退、返回安全退出，F-MV-01～06）、第 17 条（网络电视导入 m3u、播放、节目单和回看，F-IPTV-01～05）、第 4 节第 11 条（分享 m3u 文件导入）。都还没有结果（S02.6 未开始）；S02.2、S02.3 都没有看这两块。

## 路线

1. [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)（第一档，阶段 c2）：K90 上走 CHECKLIST 第 1 节第 16、17 条，多画面 4 路时顺带记 `dumpsys gfxinfo` 的掉帧数；结果写回 A13.1、A13.2 的“实现和验证”。
2. [N01.2](../../N-多画面和投屏/N01-多画面/N01.2-多画面弹幕跟随帧率设置/README.md)（第二档，小）：多画面弹幕层接上帧率设置。
3. A02.3 补改 IPTV 卡片的“更多”菜单（`iptv_cards.dart:90`，几行，建议随 A02.3 的真机验证一起）。
4. 电视的网络电视页 [A17.5](../A17-电视界面/A17.5-电视网络电视和影片/README.md) 开发时复用这里的数据层（`IptvOverview`、导入对话框的逻辑），界面换电视样式。
5. 多画面的新需求（自动降清晰度、更多布局）先进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/iptv/`、`multiview/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A13.1 | 网络电视管理 | 界面 | 完成 | 2026-10-01 | 7c6d685cb | [设计或说明](A13.1-网络电视管理/README.md)、[记录](A13.1-网络电视管理/record.md)、[评审页](A13.1-网络电视管理/page/01-说明.jpg) |
| A13.2 | 多画面 | 界面 | 完成 | 2026-10-01 | b601b444e | [设计或说明](A13.2-多画面/README.md)、[记录](A13.2-多画面/record.md)、[评审页](A13.2-多画面/page/01-说明.jpg) |

<!-- docs:生成结束 -->
