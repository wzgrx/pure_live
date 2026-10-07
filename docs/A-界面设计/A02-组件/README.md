# A02 组件

`live_ui` 的组件：页面共用的状态页、横幅、头像、计数、二维码、标签、芯片、设置行、房间卡片，四种弹窗（小菜单、对话框、面板、提示条）和它们在应用里的接线。同一件事全应用只有一个组件、一种样子（[specs/UI.md](../../specs/UI.md) 第 3 节第 6、7 条）。

## 范围

- 包括：
  - `packages/live_ui/lib/src/widgets/` 下的组件（42 个文件，清单见“代码地图”），以及它们的状态（默认、悬停、键盘焦点、按下、禁用、进行中）和深浅主题下的样子。
  - 应用里把组件接到页面的共用部分：`apps/pure_live/lib/shared/rooms/room_grid.dart`（列表外壳：状态页、横幅、回到顶部、翻页快捷键）、`shared/rooms/paging.dart`（电脑翻页栏）、`shared/rooms/room_menu.dart`（卡片对话框、撤销提示条）、`shared/panels/side_panel.dart`（直播间和多画面的面板 `RoomSidePanel`）、`routes/app_navigator.dart`（`AppNavigator.toast`）、`app/app.dart:70`（提示条的根 `AppToaster`）。
- 不包括（归哪里）：
  - 颜色、字号、图标的定义 → [A01](../A01-设计系统/README.md)；滚动物理、下拉刷新、弹簧（`scrolling.dart`、`refresh_view.dart`、`motion.dart`）→ [A03](../A03-动效和手感/README.md)；尺寸分档 → [A04](../A04-尺寸和适配/README.md)；全应用的读屏、焦点、对比度检查 → [A05](../A05-无障碍/README.md)。
  - 组件在具体页面里的样子和内容：房间卡片的设计 → A09.1；直播间画面上的状态、中间按钮 → A07.7、A07.10；录制图形 → A10.3；设置页 → A11；电视样式（焦点放大、近白描边）→ A17.1。这些组件的文件在 `widgets/` 里，代码地图照列，设计由那些任务管。

## 现状：做到哪、怎么工作的

- 用户看得到的（A02.1、A02.2、A02.3 已合并，都“待真机”）：
  - 状态：一个 `AppStatusView` 管加载、空、出错、受限、离线五种，三种场合（整页 80 圆圈 + 40 图标 + 标题 15/600 + 原因 13 + 最多两个按钮；区块里 32 图标不带圆圈；卡片封面迷你）；列表第一次加载是静态骨架（`StatusSkeleton`）；出错写人话，原始报错收进“详情”可复制；横屏手机（窗口高 <480 且宽 > 高）左图右文。有内容时的说明、提醒、出错用页顶横幅 `StatusBanner`（三种颜色、✕ 48）。
  - 小组件：头像（加载中浅灰、没头像首字、没名字人形；可点时悬停和焦点框）；计数（描边样式，36 高、每半 48 可点，到上下限变灰，长按每 100 毫秒连加，← → 可调）；二维码（一直白底黑码，状态盖在原位置）；标签（数量、角标、二级标签、焦点框）；芯片（一种：36 高、圆角 8、选中次色容器加勾）；回到顶部 / 底部（滚过 400 出现，点击区 48）。
  - 设置行：一个 `SettingsRow` 家族（跳转 ›、选择“值 ⌄”、开关、滑块、计数、芯片、色块、搜索框），标题 15/400、说明 12 次要色，窄于 360 或字放大 1.5 倍以上值换到标题下，内容最宽 720 居中；设置类页面的标题栏 `settingsPageAppBar`。
  - 弹窗：小菜单贴着按钮、按实测高度放在放得下的一边、从按钮那边展开（150 毫秒，关 100 毫秒，减少动态效果时没有动画）；对话框宽 = 屏宽减 32 最宽 400（长内容 560），标题和按钮固定只滚内容，取消在左、动作写明（危险的红色），回车 = 主要按钮、Esc = 取消；面板竖屏从底部升起带把手、宽 600 起在右侧 360，标题栏 52 高、✕ 48、滚动后出线；提示条反色、圆角 8、底部导航栏上方 16、宽屏居中最宽 560，3 秒（带操作 4 秒，要用户选的不自动消失），同一句不叠加。
  - 卡片：`LiveRoomCard`（A09.1）、卡片长按的 `CardDialog`、关注按钮 `FollowPill`。
- 内部怎么工作：
  - 组件只依赖 Flutter 和 `live_ui` 自己；页面的数据由应用转成小的输入类型（`RoomCardData`、`RoomAudience`、`VideoStateAction`、`AppMenuEntry`、`AppDialogOption`），文字和加载样式从 `LiveUiScope` 读（`packages/live_ui/lib/src/scope.dart:289`）。
  - 提示条：页面调 `AppNavigator.toast(…)`（`apps/pure_live/lib/routes/app_navigator.dart:33`、`:38`）→ 应用根的 `AppToaster`（`apps/pure_live/lib/app/app.dart:70`）→ 根 `ScaffoldMessenger` 上 `showAppToastOn`（`packages/live_ui/lib/src/widgets/app_toast.dart:130`，新的替换旧的，同一句显示期间不重复）；全屏时直播间把提示条抬到下栏上方（`features/live_play/live_play_page.dart` 的 `_toastsAboveBars`）。
  - 小菜单：`showAppMenu`（`app_menu.dart:88`）和 `showSmallMenu`（`stream_menu_button.dart:174`）都走 `showAnchoredMenu`（`anchored_menu.dart:47`）：推一个不变暗的 `PopupRoute`，先排版拿到菜单高度，再由 `_AnchoredMenuLayout.getPositionForChild`（`:192-209`）定上下；屏幕尺寸变了直接关掉（`:124-129`）。
  - 对话框：所有 `showAppConfirmDialog`、`showAppOptionDialog` 等都包一层 `AppDialog`（`app_dialog.dart:42`），`DialogKeys`（`dialog_keys.dart:12`）管回车和 Esc，`DialogButtonsTheme`（`dialog_buttons_theme.dart:6`）把按钮字放到 14。
  - 列表外壳没有做成一个组件：每个列表页用 `AppRefreshView`（A03.1）+ `room_grid.dart` 的 `loadErrorStatus`（`:290`）、`StatusBanner`（`:230`、`:335`、`:635`）、`ScrollJumpButtons`（`:197-209`）拼起来。
- 用在页面（2026-10-03，`apps/pure_live/lib` 里用到它的文件数）：`AppStatusView` 22、`AppDialog` 20、`showAppDialog` 28、`DialogActionButton` 19、`ListenableSelector` 17、`SettingsGroup` 16、`showAppConfirmDialog` 16、`CommonAvatar` 14、`SettingsLinkRow` 12、`SettingsSwitchRow` 11、`ReadableContent` 10、`AppToast` 8、`AppChip` 7、`settingsPageAppBar` 7、`TabLabel` 6、`AppRefreshView` 6、`showAppMenu` 5、`AppMenuButton` 5、`showAdaptivePanel` 4、`ScrollableTabBar` 4、`DialogOptionRow` 4、`showAppOptionDialog` 3、`StreamMenuButton` 3、`LiveRoomCard` 3、`EscapeBack` 3；应用里（除电视）已经没有 `AlertDialog(`、`SimpleDialog(`、`showModalBottomSheet`、`RefreshIndicator`、`PopupMenuButton`、`activeThumbColor`。
- 完成度（和 3.x 对照）：
  - 一致的：状态出现的时机、“加载样式”（85 种）、头像尺寸和缓存、计数长按连加、二维码画法、一级标签的样子和滚轮横滚、设置页结构（组标题 + 卡片 + 行、左边图标）、窄屏换行、回到顶部 / 底部、电脑翻页栏、四种弹法和用在哪、对话框主题（圆角 24、标题 20/600）、取消在左、提示条 3 秒和同一句不重复。
  - 确认过的改动：A02.1 的 c1～c21（C1～C4 按 A）、A02.2 的 c1～c14（D1～D4 按 A）、A02.3 的 c1～c4；维护者另定的“设置类对话框写明动作”“剩下 3 个原生弹出菜单换成小菜单”；D-011（标题位置）、D-021（直播间取消关注用小菜单）。
  - 还缺：三个任务的真机验证；Esc 返回只做了三页（见“已知问题”）。

## 代码地图

`packages/live_ui/lib/src/widgets/`，按用途分组；“设计”一列是定这个组件样子的任务。

| 文件 | 职责 | 设计 |
|---|---|---|
| `status_view.dart` | `AppStatusType`（`:18`，五种）、`statusSideBySideHeight` 480（`:39`）、`AppStatusView`（`:64`，整页 / 区块 / 迷你，按窗口判断横排 `:236`）、`showStatusDetails`（`:352`，原始报错可选中复制）、`EmptyView`（`:380`）、`StatusSkeleton`（`:463`，静态骨架） | A02.1 c2～c7 |
| `status_banner.dart` | `StatusBannerKind`（`:7`，说明、提醒、出错）、`StatusBanner`（`:30`，18 图标、13 号字、按钮在字下、✕ 48 或 ›） | A02.1 c8 |
| `loading_styles.dart` | `LoadingStyles`（`:10`，3.x 的 85 种加载动画按名字查表）、`DefaultLoadingIndicator`（`:145`，默认圆环，自己持有动画） | A01.1（照 3.x） |
| `video_state_view.dart` | `VideoStateAction`（`:10`）、`VideoStateView`（`:38`，画面上的状态：转圈或头像、一句话、原因、两个按钮、遮暗）、`VideoStateAvatar`（`:187`） | A07.7 c2 |
| `video_centre_button.dart` | `VideoCentreButton`（`:20`，画面中间 64 的圆按钮，暂停时 ▶，等数据时转圈） | A07.10 c2 |
| `avatar.dart` | `CommonAvatar`（`:12`，图片、首字、人形；可点时 `FocusRing` `:112`） | A02.1 c9 |
| `network_image.dart` | `LiveNetworkImage`（`:8`，照 3.x：缓存、请求头、缓存代数来自 `LiveUiScope`，不淡入，换地址保留旧图） | A01.1 |
| `count_button.dart` | `CounterControl`（`:15`，− 值 + 的描边控件，← → 可调 `:204`）、`CountButton`（`:218`，整数步进，长按从上一次的值连加） | A02.1 c10 |
| `qr_code_widget.dart` | `QrColors`（`:6`）、`QrCodeWidget`（`:21`，逐模块画、白底黑码）、`QrCodeStatus`（`:71`）、`QrCodeCard`（`:99`，状态盖在原位置） | A02.1 c11 |
| `tab_label.dart` | `TabLabel`（`:12`，标签字、数量或角标、键盘焦点框 `:62-66`）、`SecondaryTabBar`（`:79`，二级标签） | A02.1 c12 |
| `scrollable_tab_bar.dart` | `ScrollableTabBar`（`:7`，电脑上滚轮和鼠标拖动横滚标签条，来自上游 liuchuancong/pure_live） | A01.1（照 3.x） |
| `app_chip.dart` | `appChipHeight` 36（`:5`）、`AppChip`（`:14`）、`appChipTheme`（`:38`，主题里的芯片）、`AppChipSide`（`:58`，按状态的描边和焦点框） | A02.1 c13 |
| `settings_row.dart` | `settingsRowNarrowWidth` 360（`:18`）、`settingsRowLargeText` 1.5（`:21`）、`SettingsRowStyle`（`:26`，手机或电视样式）、`SettingsHighlight`/`HighlightedText`（`:42`、`:58`，搜索命中高亮）、`SettingsGroup`（`:118`）、`SettingsGroupTitle`（`:198`）、`SettingsNote`（`:232`）、`SettingsRow`（`:261`，焦点框 `:475-480`）、`SettingsLinkRow`（`:500`）、`SettingsSwitchRow`（`:640`）、`SettingsSliderRow`（`:720`）、`SettingsCounterRow`（`:886`）、`SettingsChipsRow`（`:994`）、`SettingsChoiceChips`（`:1042`）、`SettingsSwatch`（`:1072`）、`SettingsSearchField`（`:1095`） | A11.1、A02.1 c14～c17 |
| `settings_tiles.dart` | `readableContentMaxWidth` 720（`:12`）、`ReadableContent`（`:16`）；3.x 的设置构建函数已删（`:3-8` 的注释） | A02.1 c18 |
| `settings_page_frame.dart` | `settingsPageAppBar`（`:13`，标题 20/600 靠左、可带一行副标题、矮窗口 48 高）、`SettingsPageList`（`:49`，一列最宽 720） | A11.1、D-011 |
| `color_picker.dart` | `LiveColorPickerLabels`（`:7`）、`parseColorCode`/`formatColorCode`（`:47`、`:62`，照 3.x）、`LiveColorPicker`（`:73`，推荐色、Material 色板、色轮、深浅、透明度、色码） | A11.2 c10 |
| `app_dialog.dart` | `appDialogMaxWidth` 400、`appDialogWideMaxWidth` 560、`appDialogMargin` 16（`:18-24`）；`AppDialog`（`:42`）；`DialogActionButton`（`:214`，写明动作、`danger` 红、`busy` 转圈）；`DialogCancelButton`（`:281`）；`DialogOptionRow`（`:309`，当前项主色加勾）；`dialogFieldDecoration`（`:414`）；`showAppDialog`（`:450`）、`showAppConfirmDialog`（`:466`）、`showAppMessageDialog`（`:508`）、`AppDialogOption`（`:549`）、`showAppOptionDialog`（`:585`）、`showAppInputDialog`（`:638`） | A02.2 c5～c9 |
| `dialog_buttons_theme.dart` | `DialogButtonsTheme`（`:6`，弹窗里的按钮字 14） | A02.2 c5 |
| `dialog_keys.dart` | `DialogKeys`（`:12`，回车 = 主要按钮、Esc = 取消、打开时取焦点） | A02.2 c6 |
| `card_dialog.dart` | `CardDialogAction`（`:8`）、`CardDialog`（`:38`，卡片长按或右键的居中对话框：标志、标题、正文、描边按钮、“关闭”） | A09.1 c10、A09.4 X3 |
| `adaptive_panel.dart` | `sidePanelWidth` 360（`:9`）、`sidePanelBreakpoint` 600（`:14`）、`showAdaptivePanel`（`:23`，竖屏底部带把手、宽屏右侧）、`PanelHeader`（`:79`，52 高、标题 17/600、✕ 48）、`PanelFrame`（`:155`，滚动后出线） | A02.2 c10 |
| `app_toast.dart` | `appToastMaxWidth` 560（`:11`）、`AppToast`（`:23`，一句或两句、一个操作、✕、`persistent`）、`appToastWidth`（`:119`）、`showAppToast`/`showAppToastOn`（`:123`、`:130`）、`AppToaster`（`:145`，同一句显示期间不重复） | A02.2 c11～c13 |
| `anchored_menu.dart`（不导出） | `anchoredMenuGap` 4、`anchoredMenuMargin` 8、打开 150 / 关闭 100 毫秒（`:15-25`）；`showAnchoredMenu`（`:47`）；`_AnchoredMenuRoute`（`:81`，尺寸变化时关 `:124-129`）；`_AnchoredMenuLayout`（`:152`，最大高度 `:178`、上下和左右对齐 `:192-209`）；`_MenuUnfold`（`:220`，从按钮那边展开的裁剪） | A02.3 c1～c2 |
| `app_menu.dart` | `AppMenuEntry`（`:11`，行：图标、说明、危险、禁用、`switchValue` `:54`、分隔线）、`appMenuMinWidth` 128（`:64`）、`showAppMenu`（`:88`）、`AppMenuButton`/`AppMenuButtonState`（`:177`、`:222`，`show()`） | A02.2 c2～c4、A02.3 |
| `stream_menu_button.dart` | `streamMenuMinWidth` 128（`:12`）、`StreamMenuButton`（`:24`，当前选择 + ⌄，菜单贴看得见的外框 `:80`，切换中转圈）、`showSmallMenu`（`:174`，直播间的小菜单：标题行、说明行、底部开关） | A07.6、A02.3 c4 |
| `jump_buttons.dart` | `jumpButtonsThreshold` 400（`:5`）、`ScrollJumpButtons`（`:13`，看起来 40、点击区 48、焦点框） | A02.1 c20 |
| `focus_ring.dart` | `focusFramesShown`（`:5`，只在用键盘时）、`FocusRing`（`:12`）、`FocusRingPainter`（`:82`） | A02.1 c21 |
| `escape_back.dart` | `EscapeBack`（`:10`，页面上 Esc = 返回，可先做页面自己的一步） | A02.1 第 7 节 |
| `page_title.dart` | `PageTitle`（`:11`，标题 17/600 + 一行 12 号副标题，可居中） | A09.8、A09.9 |
| `follow_pill.dart` | `FollowPill`（`:10`，“＋ 关注”主色、“✓ 已关注”灰、进行中转圈） | A07.1 c12 |
| `live_room_card.dart` | `LiveRoomCard`（`:36`）、`LiveRoomCardColors`（`:162`）、`LiveRoomCardMetrics`（`:177`）、`CoverChip`（`:495`）、`RoomCardSkeleton`（`:566`）、`RoomRow`（`:649`，紧凑行） | A09.1 |
| `room_card.dart` | `RoomAudienceKind`（`:4`）、`RoomAudience`（`:25`）、`RoomCardData`（`:44`，卡片的输入） | A01.1、A09.1 |
| `room_card_appearance.dart` | `RoomCardViewport`、`RoomCardPlatformBadgeMode`、`RoomCardLayout`、`RoomCardPreset`（`:7`～`:37`）、`RoomCardAppearance`（`:58`，外观、预设、3.x 旧键的 JSON 读写）、`RoomCardLayoutMetrics`（`:314`，网格高度跟随字号） | A01.1、A11.2 |
| `ambient_backdrop.dart` | `ambientCoverDecodeWidth` 24（`:7`）、`AmbientBackdrop`（`:17`，竖屏画面后的沉浸背景，封面只解码一次） | A07.2 change 12 |
| `record_glyph.dart` | `RecordGlyphState`（`:10`，七种）、`RecordGlyph`（`:41`）、`RecordGlyphPainter`（`:154`）、`formatRecordingTime`（`:314`）、`RecordingBadge`（`:328`） | A10.3 |
| `pip_danmaku_preview.dart` | `PipDanmakuPreview`（`:12`，设置页的小窗弹幕预览，自己一层、减少动态效果时静止） | A11.3 |
| `emote_text.dart` | `ChatSegment`、`ChatTextSegment`、`ChatEmoteSegment`（`:6`、`:12`、`:30`）、`EmoteText`（`:57`，文字和表情图混排） | A01.1（B-12、B-13） |
| `json_tree.dart` | `JsonTreeLine`（`:7`）、`jsonTreeLines`（`:30`）、`jsonTreeOpenLevels`（`:53`）、`JsonTreeSliver`（`:79`，3.x flutter_json 的树，只建屏幕上的行；设置 → 数据里看设置的 JSON，`apps/pure_live/lib/features/settings/data_tools.dart:582`） | A11.5 |
| `listenable_selector.dart` | `ListenableSelector`（`:6`，只在选中的部分变化时重建，局部刷新） | A07.1 |
| `refresh_rate.dart` | `RefreshRateMode`（`:7`）、`AdaptiveRefreshRateController`（`:29`）、`AdaptiveRefreshRateScope`（`:137`）：Android 界面刷新率三档 | A01.1（照 3.x），R02 |
| `scrolling.dart`、`refresh_view.dart` | 滚动物理和下拉刷新 | 见 [A03](../A03-动效和手感/README.md) |

应用里的接线：

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/app.dart` | `:70` `AppToaster`（根 `ScaffoldMessenger`）；`:240` `LiveUiScope` |
| `apps/pure_live/lib/routes/app_navigator.dart` | `:15` `ToastPresenter`、`:33` `toast`、`:38` 带操作的提示条 |
| `apps/pure_live/lib/shared/rooms/room_grid.dart` | 列表外壳：`ScrollJumpButtons` 的应用版（`:197-209`）、流量提醒横幅（`:230`）、`loadErrorStatus`（`:290`）、出错横幅（`:335`）、电脑 ← → 翻页（`:583`）、`AppRefreshView`（`:616`、`:699`）、说明横幅（`:635`） |
| `apps/pure_live/lib/shared/rooms/paging.dart` | `usesDesktopPages`（`:18`，宽 >680 且不是手机系统）、电脑翻页栏（上一页 `:188`、下一页 `:204`、每页条数 `:237`） |
| `apps/pure_live/lib/shared/rooms/room_menu.dart` | 卡片对话框的内容、取消关注后的“撤销”提示条 |
| `apps/pure_live/lib/shared/rooms/room_cards.dart` | 房间模型 → `RoomCardData`；`isPhoneDevice`（`:123`） |
| `apps/pure_live/lib/shared/panels/side_panel.dart` | `RoomSidePanel`（`:24`）：直播间和多画面的面板，标题栏下拉关闭（带速度的弹簧，A03.2） |
| `apps/pure_live/lib/shared/danmaku/setting_rows.dart` | 面板里的组标题、弹幕设置行（直播间和设置页共用） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_ui/test/components_test.dart`（26） | A02.1：状态页（类型、文字、图标、圆圈、无入场动画、横排、“详情”）、横幅、头像、计数、二维码、标签、芯片、设置行和开关、列表行、回到顶部、`EscapeBack`、焦点框、对比度 |
| `packages/live_ui/test/status_view_test.dart`（8） | 空和出错的默认文字、重试、按钮图标、第二个按钮、迷你、加载样式和颜色、85 种样式 |
| `packages/live_ui/test/popups_test.dart`（16 个用例声明） | A02.2：对话框（宽度、标题固定、按钮、回车和 Esc、危险确认焦点）、面板（底部和右侧、标题栏、滚动线）、提示条（反色、位置、时长、操作、不重复） |
| `packages/live_ui/test/small_menu_test.dart`（12） | A02.3：横屏 852×393 向上展开、竖屏 393×852 向下、平板 1280×800，展开过程逐帧，菜单不压按钮 |
| `packages/live_ui/test/app_menu_test.dart`（5）、`menu_additions_test.dart`（4） | 小菜单的样子、向上、当前项、页面标题、危险行；标题行、说明行、底部开关、选项行的尾部 |
| `packages/live_ui/test/dialog_support_test.dart`（1） | `DialogButtonsTheme` 14 号；`DialogKeys` 回车和 Esc |
| `packages/live_ui/test/settings_row_test.dart`（18） | 设置行、颜色选择器、主题（品牌蓝、纯黑、文字大小） |
| `packages/live_ui/test/settings_playback_widgets_test.dart`（5） | 长值换行、危险行、计数长按、弹幕预览、JSON 树 |
| `packages/live_ui/test/live_room_card_test.dart`（14）、`room_card_test.dart`（4） | 房间卡片、紧凑行、关注按钮、网格列数、`showAdaptivePanel`；卡片高度和外观 JSON |
| `packages/live_ui/test/widgets_test.dart`（18）、`loading_ring_test.dart`（1） | 计数、刷新率控制器、`EmoteText`、二维码、标签条滚轮、`VideoStateView`、`VideoCentreButton`、`ReadableContent`；默认转圈不离屏绘制 |
| `apps/pure_live/test/shared/side_panel_test.dart` | `RoomSidePanel` 的下拉关闭手感（A03.2） |
| `apps/pure_live/test/features/live_play/room_popups_test.dart`、`live_play_popups_test.dart` | 直播间里的提示条位置、小菜单贴按钮（A02.3、A07.12） |

## 3.x 基线

- 通用组件（`lib/common/widgets/`，`v3.2.11`）：`app_status_view.dart`（532 行，`loading / empty / error` 三种 `:10`，空和出错的圆圈 15% 透明加 1 秒弹跳 `:426-445`，加载不显示标题 `:407-413`）、`empty_view.dart`（43）、`common_avatar.dart`（65）、`count_button.dart`（205，两块 48×48 主色实心）、`qr_code_widget.dart`（71）、`scrollable_tab_bar.dart`（178）、`widget_extensions.dart`（455，`buildGroupTitle`、`buildModernCard`、`buildSwitchTile`、`buildTile`、`buildSliderTile`，靠类型名认行 `:47-53`，最宽 960 `:8`）、`section_listtile.dart`（61）、`keep_alive_wrapper.dart`（21）、`menu_button.dart`（84）、`room_card.dart`（1411）。列表外壳 `lib/common/base/base_page_view.dart`（308）、`base_page_view_extension.dart`（100，回到顶部 40 `:64-99`）、`desktop_components.dart`（285，翻页栏）；下拉刷新头 `lib/plugins/global.dart:17-62`（字写反了）。
- 弹窗：`lib/plugins/utils.dart`（`showAlertDialog` `:110-131`、`showMessageDialog` `:137-147`、`showRightDialog` `:149-201`、`showEditTextDialog` `:212-222`、`showOptionDialog` `:224-226`）；各页 `showDialog` 76 处（40 个文件）；`PopupMenuButton` 10 处（首页左上 `lib/common/widgets/menu_button.dart:14-84`、右上 `common_appbar_actions.dart:13-68`、清晰度和线路 `lib/modules/live_play/widgets/resolution_selector/resolution_selector.dart:24-80`、搜索排序 `lib/modules/search/search_page.dart:261-280` 等）；提示条 `lib/common/utils/toast_util.dart`（SmartDialog，225 处，3 秒、同一句 3 秒内不重复 `:13-18`）和 `SnackBar` 21 处。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 6 条（点按或长按弹幕出复制和屏蔽菜单）、第 7 条（返回链：弹层 → 全屏 → 普通 → 离开，Esc 同一条）、第 14 条（卡片长按或右键 = 操作菜单）；规范第 3 节第 8 条（弹法照 3.x）、第 7 节（四种弹窗的位置和关闭方式）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A02.1、A02.2、A02.3 都没在 K90 上逐项看 | 各任务的 `verify.md` | 状态、弹窗、小菜单在真机上的样子和手感没确认 | A02.1、A02.2、A02.3 待真机 |
| 二级页面在电脑上 Esc 不返回；`EscapeBack` 只用在三页 | `features/search/search_view.dart:371`、`search/web_search_view.dart:163`、`history/history_page.dart:229` | 规范 5.4 的 Esc 返回链不全 | A05.1（c3） |
| 状态页按窗口判断横排（不是约束） | `status_view.dart:236` | 分屏、小窗时可能按整窗口排 | 有意的（`SliverFillRemaining` 里不能用 `LayoutBuilder`）；A04.1 换常量时复查 |
| 设置行的标题、说明、值、计数的字号写死 | `settings_row.dart:363`、`:369`、`:591`、`:622`；`count_button.dart:144` | 不跟五个字号设置走 | A01.2 第 3 阶段 |
| 组件里直接写 `Icons.*` 22 处 | `count_button.dart:191`、`status_view.dart:139-142` 等（清单在 A01.3 任务书） | `AppIcons` 不是唯一入口 | A01.3 第 3 阶段 |
| 图标按钮（画面比例等）的小菜单贴 48 的点击区，离图标比清晰度菜单离外框远一点 | `apps/pure_live/lib/features/live_play/player/bar_parts.dart` 两处 anchor | 看起来不完全一致 | A02.3“待选和决定”，维护者看一眼 |
| `showAppMessageDialog`、`showAppInputDialog` 应用里没人用；`KeepAliveWrapper` 应用里没人用 | `app_dialog.dart:508`、`:638`；`scrolling.dart:154` | 多余的公开接口 | 保留（有测试，以后的页面会用）；`KeepAliveWrapper` 可在下次改 `scrolling.dart` 时删掉 |
| 还有三处不是统一组件：版本的三个 `Dialog`、启动失败页的原生 `SnackBar`、本地发送星标行的 `showGeneralDialog` | `features/version/release_history_view.dart:256`、`update_prompt.dart:202`、`update_download.dart:606`；`app/launch_failure.dart:119`；`features/live_play/local_interaction/local_composer.dart:344` | 版本的是 A06.3 有意保留的版式；启动失败页在主题之前，可以接受 | A02.2 偏差里记下，不另开任务 |
| 效果图工具 `kit.css` 没有提示条深色反色、菜单说明行和禁用项、对话框按钮规则，500 字重被映射成粗体 | `tools/ui/mock/kit/kit.css:125` 等 | 以后出图要在任务里自己补样式 | 没有任务管，建议在 Z 组登记 |
| 代码注释里的旧编号（`U.1c c13`、`U.1d c7`、`UI_PLAN §7` 等） | `packages/live_ui/lib/src/widgets/` 多处 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | 同 A01，建议在 Z 组一次性替换 |

## 相关决定和规范

- D-003（A02.1 的 C1～C4、A02.2 的 D1～D4 由维护者按建议 A 定）、D-011（标题位置）、D-020（往上甩面板不关闭）、D-021（直播间里取消关注用小菜单，首页长按卡片仍是居中对话框）。
- [specs/UI.md](../../specs/UI.md) 第 3 节第 4、6、7、8 条（状态统一用 `live_ui` 组件、一个动作一个组件、各客户端一致、弹法照 3.x）；第 7 节（四种弹窗）；第 8.5 节（通用组件和它们的状态）；第 5.4 节（48×48、焦点框、Esc）。

## 测试和验证

- 自动测试：`cd packages/live_ui && flutter test`（上表 18 个测试文件，178 个用例声明，有几个按尺寸或主题循环）；应用里组件的用法在 `apps/pure_live/test/` 各页面的测试里（例如热门、搜索、扫码登录、分区、观看记录的状态页断言，8 处“主要按钮写明动作”的断言）。缺的：没有 `meetsGuideline`（A04.1、A05.1 加）；没有截图对照测试。
- 真机：照 [A02.1 的 verify.md](A02.1-通用组件/verify.md)（12 步）、[A02.2 的 verify.md](A02.2-弹窗组件/verify.md)（9 步）、[A02.3 的 verify.md](A02.3-贴着按钮的小菜单/verify.md)（7 步）。[S02 的真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)里相关的：第 4 节第 1 条（关注下拉刷新、状态）、第 9 条（卡片长按：关注、设标签、分享）。

## 路线

1. 维护者在 K90 上按三个 `verify.md` 看完 A02.1、A02.2、A02.3，通过的改“完成”；看出问题的照各自任务书的范围修，大的开新任务（标题写“接 A02.x”）。
2. 组件里剩下的直接写图标和写死字号由 A01.3、A01.2 第 3 阶段收掉（改的是组件文件，和 A02 的修补错开）。
3. A04.1 做高度分档时复查状态页、对话框、面板、小菜单的尺寸和折叠屏避让；A05.1 做全应用的读屏、焦点、Esc 返回。
4. 新组件只在出现第二个用处时才放进 `live_ui`；新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`packages/live_ui/lib/src/widgets/`
- 进度：`███████████████░░░░░` 77%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A02.1 | 通用组件：状态页、头像、计数、二维码、标签、芯片、设置行 | 界面 | 待真机 | 2026-10-02 | 097a60963 | [设计或说明](A02.1-通用组件/README.md)、[任务书](A02.1-通用组件/brief.md)、[记录](A02.1-通用组件/record.md)、[记录 2](A02.1-通用组件/record-2.md)、[真机验证](A02.1-通用组件/verify.md)、[评审页](A02.1-通用组件/page/01-说明.jpg) |
| A02.2 | 弹窗组件：对话框、面板、提示条 | 界面 | 待真机 | 2026-10-02 | 1c572a5cc | [设计或说明](A02.2-弹窗组件/README.md)、[任务书](A02.2-弹窗组件/brief.md)、[记录](A02.2-弹窗组件/record.md)、[真机验证](A02.2-弹窗组件/verify.md)、[评审页](A02.2-弹窗组件/page/01-说明.jpg) |
| A02.3 | 贴着按钮的小菜单：按实测高度定位、从按钮方向展开 | 界面 | 待真机 | 2026-10-02 | 39b570ee6 | [设计或说明](A02.3-贴着按钮的小菜单/README.md)、[任务书](A02.3-贴着按钮的小菜单/brief.md)、[记录](A02.3-贴着按钮的小菜单/record.md)、[真机验证](A02.3-贴着按钮的小菜单/verify.md) |
| A02.4 | 带“撤销”的提示条在开着无障碍服务时一直不消失且没有关闭按钮 | 界面 | 未开始 | — | — | [设计或说明](A02.4-撤销提示条不消失/README.md)、[任务书](A02.4-撤销提示条不消失/brief.md) |

## 还没完成的

- **A02.4 带“撤销”的提示条在开着无障碍服务时一直不消失且没有关闭按钮**（未开始，第二档，规模 小）
  - 来源：S02.5 清单 1A-14（2026-10-08 K90）

<!-- docs:生成结束 -->
