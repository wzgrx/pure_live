# A07 直播间界面

直播间看得见的一切：各种布局（竖屏、竖屏流三档面板、竖屏全屏、横屏全屏、横屏手机、宽屏分栏和窗口内全屏、网络电视频道）、画面上的控制层和手势、直播间里弹出的面板和小菜单、画面状态、三种小窗（应用内小窗、系统画中画、桌面小窗），以及它们之间怎么切换。全项目最复杂的一块界面。

## 范围

- 包括：
  - 页面和布局：`apps/pure_live/lib/features/live_play/live_play_page.dart`、`layout/`（顶栏、信息行、直播间详情、三档面板、面板位置）。竖屏普通布局 A07.1；竖屏流和竖屏全屏 A07.2；竖屏全屏上下滑换台 A07.3；横屏全屏 A07.4；宽屏分栏和窗口内全屏 A07.5。
  - 画面和控制层：`player/`（上栏、下栏、时间电量、锁定、手势、画面状态、换台拖动）、`buttons/`（关注、录制、右上角菜单、清晰度和线路）。暂停状态 A07.10；单击、全屏状态保持等小问题 A07.11；双击飞行弹幕 A07.14；手势避开系统手势区 A07.15。
  - 直播间的面板和小菜单：`dialogs/`、`record/`、`switch_room/`、`layout/room_panel.dart` 和 `danmaku/message_panel.dart`（长按弹幕）。A07.6（清晰度线路、录制、弹幕设置、菜单、长按弹幕）、A07.12（定时关闭、房间音量、投屏、获取直链、画面比例和方向、取消关注）、A07.13（切换直播间）。
  - 画面状态：加载、未开播、出错、受限、重连、纯音频、回放播完、网络电视节目单和回看（`player/player_status.dart`、`dialogs/iptv_guide.dart`），A07.7。
  - 小窗：`mini/`（应用内小窗、系统画中画、桌面小窗、小窗弹幕），A07.8。
  - 直播间背景图（京东的模糊封面）A07.16；已合并任务的收尾 A07.9。
  - `packages/live_ui` 里只给直播间用的组件：画面上的颜色角色 `OnVideoColors`、沉浸背景 `AmbientBackdrop`、画面状态 `VideoStateView`、中间的 ▶ `VideoCentreButton`、录制图标和角标 `RecordGlyph`、`RecordingBadge`、弹幕按钮图标 `DanmakuIcon`。
- 不包括（归哪里）：
  - 弹幕列表、醒目留言、弹幕设置页的内容、屏蔽管理、画面弹幕的点按和长按菜单的内容：A08（A08.1、A08.4）；本地互动的输入框、面板、礼物（代码在 `features/live_play/local_interaction/`）：A08.2；飞行弹幕引擎：D03。
  - 录制按钮和状态图标的样子：A10.3；录制面板里的录制逻辑：H。
  - 直播间的功能和数据：进房、房间控制器 `LiveRoomController`、后台播放、菜单里的工具的行为：C（C01～C03）；播放引擎、会话、重连：G；刷新率：R02；方向翻转、返回手势：O05、O06。
  - 多画面：A13.2；电视直播间：A17.4；系统画中画窗口上系统画的按钮、通知：A14.1；桌面窗口本身（标题栏、在新窗口打开）：A16.1；苹果平台：A18。
  - 拖动的手感（弹簧、橡皮筋、松手速度）：A03.3；尺寸和字号适配的全应用检查：A04.1；无障碍：A05.1。

## 现状：做到哪、怎么工作的

### 各布局（用户看得到的）

页面只读父组件给的宽高（`LayoutBuilder`），不读整屏；进出全屏、换布局、进出画中画时播放器只挂一份（`live_play_page.dart:771` 的 `_playerKey`），只移动不重建。

| 布局 | 什么时候 | 样子 | 代码 |
|---|---|---|---|
| 竖屏普通布局 | 宽 <840，不是竖屏流（或竖屏适配关、“兼容 16:9”） | 顶栏（返回、头像、主播名 15/600、“平台 · 分区”、关注胶囊、录制、四宫格菜单）；16:9 画面（高 = 宽 × 9/16，最多可用高度的 60%），上栏标题 + 纯音频、投屏、小窗，下栏播放、刷新、弹幕开关、弹幕设置｜方向、全屏；两行信息行（标题、详情 ⌄；人数、开播时长、原画 ⌄、线路1 ⌄）；四个标签和弹幕列表；直播间详情盖在弹幕区上；面板从画面下沿升起盖住下面全部 | `live_play_page.dart:1204-1216`（`_phone`）、`:1077`（`_chatColumn`）、`:935`（`_withPanelBelow`）；`layout/room_header.dart`、`room_info_bar.dart`、`room_details.dart` |
| 竖屏流（三档面板） | 宽 <840、竖屏直播、“竖屏直播适配”和“普通页自适应视频高度”开着、布局不是“兼容 16:9”（`room_layout.dart:94-99`） | 画面铺满，下面一块可拖到三个高度的面板（最低 250、中 44%、最高 68%；“沉浸”从最低档开始，其余从中档）；把手行“下滑进入竖屏全屏”，右边“横屏全屏”胶囊；控制层、飞行弹幕、状态只排在面板上方露出的画面里 | `live_play_page.dart:1218-1231`、`layout/portrait_panel.dart:28`、`logic/room_layout.dart:137-148`（三档）、`:166-170`（拖过最低档进竖屏全屏） |
| 竖屏全屏 | 竖屏流往下拖过最低档、点把手、双击、下栏全屏按钮；只在手机 | 沉浸式、锁竖屏；上方两行（返回、标题、关注、录制、菜单；时间电量、切换直播间、纯音频、投屏、小窗），下方两行（输入框、原画、线路；播放、刷新、弹幕、弹幕设置、画面模式、方向、退出全屏）；四种画面模式；进入提示 3 秒；最下面 96 内上滑回到面板；开着“竖屏全屏上下滑换台”且有来源列表时中间三分之一上下滑换台；面板在底部 60% | `live_play_page.dart:563-574`（进入）、`:993-1040`（`_fullscreen`）、`:947`（底部 60%）；`player/room_swipe.dart` |
| 横屏全屏 | 全屏按钮、双击、F、默认全屏（横屏直播，或设置“始终横屏”）；“横屏全屏”胶囊（一次性，退出后转回竖屏） | 上栏：返回、时间、电量、标题、切换直播间、纯音频、投屏、小窗、录制、菜单；下栏：播放、刷新、已关注、弹幕开关、弹幕设置、本地弹幕输入框（窄时收成星形）、原画、线路、方向、画面比例、退出全屏；右侧中间锁定；面板在右侧 360 全高 | `live_play_page.dart:526-561`（进入）、`:913`（`_withSidePanel`）；`player/player_controls.dart`、`player/bar_parts.dart` |
| 横屏手机（不全屏） | 高 <480、横着且宽 ≥600 | 左右分栏，聊天栏最窄 300（A08.1 c17） | `logic/room_layout.dart:66-71`（`RoomPageLayout.landscape`） |
| 宽屏分栏 | 宽 ≥840 | 画面区（横屏直播居中 16:9 框，竖屏直播用满高度、两边沉浸背景）+ 右侧聊天栏（34%，300–400，顶上信息行）；下栏右边音量条（电脑）、收起聊天栏、窗口内全屏（电脑）、全屏；边缘把手随控制层显隐；收起记住（`livePlayChatCollapsed`）；面板盖在聊天栏上 | `live_play_page.dart:1239-1323`（`_wide`）、`:1327`（`_ColumnHandle`）；`room_layout.dart:254`（栏宽） |
| 窗口内全屏（电脑） | 下栏“窗口内全屏” | 画面铺满窗口，顶栏和聊天栏隐藏，控制层用横屏排法，右下“退出窗口内全屏” | `live_play_page.dart:613-619` |
| 网络电视频道 | 网络电视来源 | 竖屏：16:9 画面 + 下面节目单；宽屏：节目单占右栏可收起；全屏：节目单在右侧面板 | `live_play_page.dart:1133-1200`（`_channel`）、`dialogs/iptv_guide.dart:78` |
| 应用内小窗 | 设置“退出小窗播放”开、离开直播间时房间在播 | 屏幕短边 × 0.56（220–360）宽，右下角，直角加阴影；回到直播间、关闭、播放暂停三个按钮；小窗弹幕；有弹层时隐藏 | `app/app.dart:231`、`mini/floating_window.dart`、`mini/mini_player.dart`、`logic/mini_window.dart:98-170` |
| 系统画中画、桌面小窗 | 上栏小窗按钮（Android 系统画中画；桌面把主窗口缩成小窗）；可选离开应用时自动画中画 | 只剩画面和小窗弹幕；桌面小窗多置顶图钉、滚轮音量 | `player/player_view.dart:560-576`（画中画时换成 `MiniPlayerSurface`）、`mini/room_mini_window.dart:31` |

### 内部怎么工作

```text
LivePlayPage（live_play_page.dart:95）
  initState（:196）：路由参数 LiveRoom 或 LiveRoomArgs(room, playlist)
    → FloatingRoom.claim（应用内小窗里同一个房间就接过来）
    → 否则 PlayerStandby.take（上一个房间留下的播放器）或新建 PlaybackSession
    → _newRuntime（:266）：RoomRuntime(LiveRoomController, session, RoomOrientationChoice, ReconnectWatch, RoomBackgroundPolicy)
    → _attachRoom（:300）：LocalRoomSession（本地互动）、RoomMiniWindow（小窗）
  build（:690）：RoomMiniScope → LocalRoomScope → RoomPanelScope → IptvGuideScope → KeyedSubtree(_roomEpoch) → _page
  _page（:730）：PopScope + 快捷键（Esc、F、空格、↑↓、R、媒体键，:736-754）
    → _pip ? 只有画面 : _display == inline ? _buildInline（:1087）: _buildFullscreen（:990）
  _buildInline：AppBar(RoomHeader) + roomPageLayout(宽, 高) → _phone / _portraitPanel / _wide / _channel
  _buildFullscreen：_toastsAboveBars（提示条在下栏上方）→ controlsArrangement → 竖着 ? _withPanelAtBottom : _withSidePanel
  换台：_swipeTo（:333，上下滑）、_pickRoom（:342，切换直播间面板）→ _switchRoom（:360）：新 RoomRuntime 沿用旧 session，旧的停完（_handover 排队）新的才 start
  dispose（:450）：shouldFloatOnLeave → FloatingRoom.show(runtime) 或 runtime.dispose（keep: PlayerStandby）

RoomPlayer（player/player_view.dart:67）——同一个组件，三种排法（ControlsArrangement：inline / landscape / portraitFullscreen）
  _picture（:500）：plain / ambient（AmbientBackdrop + 透明底画面）/ portraitModes（四种画面模式）
  PlayerGestureLayer（亮度、音量、底部上滑、中间换台）
    ⊃ GestureDetector（onTap → _onTap :333：单击立即生效，300 毫秒内第二下撤销并切全屏；长按画面弹幕）
        ⊃ AudioOnlyCover + 飞行弹幕 DanmakuOverlay（running = danmakuRunning(状态, 暂停时的弹幕)）
    ⊃ RoomStatusLayer（画面状态，player_status.dart:32）
  PlayerTopBar / PlayerBottomBar（player_controls.dart:260、:557）由 PlayerBarActions（:117）供动作
  锁定 LockButton、竖屏全屏进入提示、录制角标、回看角标、礼物条、宽屏边缘把手（edge）
  控制层 4 秒自动隐藏（_scheduleHide :312）；暂停、菜单或面板开着时不隐藏
```

- **显示状态**只有一个：`RoomDisplay`（`logic/room_layout.dart:6`：内嵌、全屏、竖屏全屏、窗口内全屏），系统画中画和桌面小窗另由 `RoomMiniWindow.compact` 跟着（页面的 `_pip`）。
- **返回链**（`live_play_page.dart:662` 的 `_back`，Android 返回键先由 `RoomBackChannel` 接住，`:646` 的 `_nativeBack`）：桌面小窗 → 面板 → 全屏 → 直播间详情 → 离开。弹层（菜单、对话框）由导航器先关。
- **面板**：`RoomPanelController`（`layout/room_panel.dart`）一次只开一个，种类 `RoomPanelKind`（录制、弹幕设置、节目单、本地互动、本地弹幕样式、切换直播间、定时关闭、房间音量、获取直链、投屏、长按弹幕）；位置由页面定：竖屏在画面下方（`_withPanelBelow`），竖屏全屏底部 60%（`_withPanelAtBottom`），其余在右侧 360（`_withSidePanel`，窄时不超过一半宽）；外框是 `shared/panels/side_panel.dart` 的 `RoomSidePanel`（多画面也用）。
- **小菜单**：清晰度、线路、画面比例、画面方向、竖屏全屏画面模式、取消关注、右上角菜单都是 `live_ui` 的贴着按钮的小菜单（`showSmallMenu`、`showAppMenu`），画面上的放得下就在按钮上方。

### 完成度（和 3.x 对照）

- 和 3.x 一致的：顶栏、画面上下栏的按钮顺序和图标（A07.1 c2、c4，A07.4 c1）；三档面板的比例、吸附、进入竖屏全屏的判定和四种画面模式（A07.2 c1）；宽屏 34%（300–400）的聊天栏（A07.5 c1）；手势（左亮度右音量、锁定）、键盘（空格、R、↑↓、Esc、F、媒体键）；返回链；小窗的入口和 3.x 的大小规则（A07.8 c1）；附录 A 的 18 条里和直播间有关的 12 条（见“3.x 基线”的表）。
- 确认过的改动（2026-10-01～02，用户确认或按 D-003 用建议 A）：竖屏顶栏和信息行重排、直播间详情、紧凑弹幕行（A07.1）；面板内容和控制层只排在露出的画面里、竖屏全屏两行、画面模式小菜单（A07.2）；竖屏全屏上下滑换台（A07.3，设置默认关）；全屏加录制和菜单、时间电量统一在左、清晰度线路两个按钮（A07.4）；840 起分栏、收起聊天栏（A07.5）；所有弹窗“弹法照 v3、只修具体问题”的五版设计（A07.6）；18 种画面状态一个组件、节目单进面板（A07.7）；三种小窗一套按钮（A07.8）；暂停时控制层常显、▶ 有底、单击立即响应（A07.10、A07.11，D-012）；直播间里不再有居中对话框（A07.12，D-021）；切换直播间面板网格和列表、原地换台（A07.13，D-022）。
- 还缺的：A07.14（双击飞行弹幕时面板一闪）、A07.15（手势避开系统底部手势区）、A07.16（京东模糊背景）没开始；A07.10～A07.13 代码已合并、待真机；“完成”的 A07.2、A07.3、A07.5、A07.7 和 A07.8 的大部分没有在真机上逐项看过（见“已知问题”）。

## 代码地图

`apps/pure_live/lib/features/live_play/` 下（省略这个前缀）：

| 文件 | 职责 |
|---|---|
| `live_play_page.dart` | 直播间页面 `LivePlayPage`（`:95`）：建房间（`:196`）、显示状态和进出全屏（`:526`、`:563`、`:576`、`:595` 恢复系统栏）、布局选择（`:1087`、`:990`）、四种页面排法（`_phone` `:1204`、`_portraitPanel` `:1218`、`_wide` `:1239`、`_channel` `:1133`）、面板的三种位置（`:913`、`:935`、`:947`）和面板内容（`_panelOf` `:807`）、全屏提示条位置（`:967`）、返回链（`:639-676`）、快捷键（`:736-754`）、原地换台（`:333-411`）、离开时交给小窗或待机（`:450-506`）；宽屏边缘把手 `_ColumnHandle`（`:1327`） |
| `layout/room_header.dart` | 顶栏 `RoomHeader`（`:24`）：可点的头像 `CommonAvatar` 和名字（打开详情）、关注、录制、菜单；窄时按钮变圆（`roomHeaderTitleMinWidth`）；骨架条 `SkeletonBar`（`:213`，进房时的占位） |
| `layout/room_info_bar.dart` | 信息行 `RoomInfoBar`（`:26`）：标签（回放、受限、未开播 `offlineMark` `:80`）、标题、详情 ⌄；人数 `AudienceStrip`（`:193`）、开播时长 `OnAirClock`（`:287`，“2 小时 18 分”）、清晰度和线路 |
| `layout/room_details.dart` | 直播间详情 `RoomDetailsPanel`（`:43`）：主播、状态行（`startedText` `:20`）、标题、四格数字、公告和简介、房间号和链接、分享、在平台打开；盖在弹幕区或聊天栏上 |
| `layout/portrait_panel.dart` | 竖屏流三档面板 `PortraitPanelLayout`（`:28`）：拖动吸附、拖过最低档或点把手进竖屏全屏、“横屏全屏”胶囊（`:312`）、读屏的档位名（`:9`）、`overlayBottom` 只在松手时改 |
| `layout/room_panel.dart` | `RoomPanelKind`（`:11`）、`RoomPanelController`、没有直播间页面时的 `showRoomPanelSheet`（`:84`）、`RoomPanelScope`（`:102`）；导出 `shared/panels/side_panel.dart` 的 `RoomSidePanel`（宽 `roomSidePanelWidth = 360`） |
| `layout/room_view_memory.dart` | `RoomViewMemory`（`:10`）：换布局、进出全屏时保留聊天标签、聊天位置、三档面板档位（A07.11 c4） |
| `player/player_view.dart` | 画面组件 `RoomPlayer`（`:67`）：排法、画面呈现 `PicturePresentation`（`:42`）、`overlayBottom`、单击和双击（`:333-386`）、点中飞行弹幕（`:389-398`、`:413-438`）、锁定（`:404`、`:775`）、暂停时常显（`:292-305`、`:312-319`）、自动隐藏、画中画时换成 `MiniPlayerSurface`（`:560`）、控制层下点击不触发弹幕 `danmakuTapAllowed`（`:830`）、竖屏全屏下栏的上滑 `_SwipeUpRegion`（`:845`） |
| `player/player_controls.dart` | 上栏 `PlayerTopBar`（`:260`）、下栏 `PlayerBottomBar`（`:557`）、三种排法共用的动作 `PlayerBarActions`（`:117`）、平台 `RoomPlatform`（`:55`）、上栏槽位 `topBarSlots`（`:96`）、宽屏的下栏动作 `WideBarActions`（`:103`）、放不下时横向滚动的 `_InlineRow`（`:803`）；尺寸：栏高 52（`:37`）、竖屏全屏一行 48（`:40`）、渐变延伸 28（`:34`）、输入框收起的宽度 640（`:49`） |
| `player/bar_parts.dart` | 时间 `PlayerClock`（`:22`）、电量 `PlayerBattery`（`:78`）、音量条 `VolumeSlider`（`:150`）、画面比例按钮 `VideoFitButton`（`:229`）、竖屏全屏画面模式按钮和小菜单 `PortraitModeButton`（`:267`）、锁定 `LockButton`（`:314`）、竖屏全屏进入提示 `PortraitEntryHint`（`:344`） |
| `player/player_gestures.dart` | `PlayerGestureLayer`（`:44`）：左亮度右音量（`:143-169`）、竖屏全屏底部上滑回面板、中间三分之一换台、滚轮音量、中间的音量亮度卡片 |
| `player/player_status.dart` | 画面状态层 `RoomStatusLayer`（`:32`，加载较慢 8 秒、恢复画面的计时）、`PictureStateView`（`:158`，暂停 ▶ 和缓冲转圈 `:254`、`:264`）、纯音频封面 `AudioOnlyCover`（`:333`）、回看角标 `CatchupBadge`（`:388`）、暗封面 `_DimmedCover`（`:451`） |
| `player/room_swipe.dart` | 竖屏全屏上下滑换台：`RoomSwipeController`（`:18`）、`RoomSwipeStage`（`:142`）、下一个直播间的预览 `RoomSwipePreview`（`:225`） |
| `player/recording_badge.dart` | 画面上的“● 录制中 12:34”角标 `RoomRecordingBadge`（`:18`） |
| `player/portrait_diagnostics.dart` | 设置“显示识别状态”开着时画面上的竖屏识别信息（`:14`，C02.1） |
| `buttons/follow_button.dart` | 关注按钮 `FollowButton`（`:32`）：顶栏、详情、画面上三种样子（`FollowButtonPlace` `:14`）；取消关注是贴着按钮的小菜单，之后提示条带“撤销”（A07.12） |
| `buttons/record_button.dart` | 录制按钮 `RecordButton`（`:23`）：图标随录制状态（A10.3），点了打开录制面板 |
| `buttons/room_menu_button.dart` | 右上角菜单：`RoomMenuEntry`（`:111`）、分组 `roomMenuGroups`（`:158`）、全屏菜单去掉栏上已有的项 `menuEntriesOnBars`（`:188`）、投屏只在 Android `castSupported`（`:148`）、`RoomMenuButton`（`:199`）；在平台或 App 打开 `openRoomExternally`（`:86`） |
| `buttons/stream_menu.dart` | 清晰度和线路两个按钮 `StreamPickers`（`:14`），竖屏在信息行、全屏在下栏 |
| `dialogs/player_dialogs.dart` | 画面比例小菜单 `showVideoFitMenu`（`:49`）、本直播间画面方向小菜单 `showRoomOrientationMenu`（`:83`） |
| `dialogs/room_dialogs.dart` | 定时关闭面板 `RoomSleepTimerPanel`（`:43`）、房间音量面板 `RoomVolumePanel`（`:275`，手机上是系统媒体音量） |
| `dialogs/stream_dialogs.dart` | 获取直链和投屏面板 `RoomStreamPanel`（`:50`，清晰度 → 线路 → 设备三页）、投屏设备 `CastDevices`（`:290`） |
| `dialogs/iptv_guide.dart` | 网络电视节目单 `IptvGuideView`（`:78`），竖屏在画面下、宽屏右栏、全屏右侧面板 |
| `danmaku/message_panel.dart` | 长按弹幕面板 `RoomMessagePanel`（`:50`）和第二页“屏蔽弹幕关键词”；入口 `showRoomMessageActions`（`:20`） |
| `danmaku/chat_panel.dart`、`chat_list.dart`、`chat_feed.dart`、`super_chats.dart`、`danmaku_settings_panel.dart` | 四个标签、弹幕列表、醒目留言、弹幕设置面板（内容归 A08，位置和面板外框归这里） |
| `record/record_panel.dart` | 录制面板 `RoomRecordPanel`（`:46`）、`RecordPanelBody`（`:145`）：九种状态卡、这次录制、开播自动录（A07.6） |
| `switch_room/room_switch_panel.dart`、`room_switch_tiles.dart` | 切换直播间面板 `RoomSwitchPanel`（`:75`）、入口 `showRoomSwitchPanel`（`:39`）、刷新 `FollowsRefresher`（`:22`）；卡片 `RoomSwitchCard`（`:265`）和列表行 `RoomSwitchRow`（`:347`）（A07.13） |
| `mini/room_mini_window.dart` | `RoomMiniWindow`（`:31`）：Android 画中画和桌面小窗的进出、自动画中画；`RoomMiniScope`（`:303`）；系统关了画中画时的提示条 `showPipDisabledToast`（`:316`） |
| `mini/mini_player.dart` | 三种小窗共用的外观和按钮 `MiniPlayerSurface`（`:47`） |
| `mini/floating_window.dart` | 应用内小窗 `FloatingRoomLayer`（`:24`）：位置、拖动（`:191-194`）、有弹层时隐藏（`:90`） |
| `mini/compact_danmaku.dart` | 小窗弹幕 `CompactDanmakuLayer`（`:24`） |
| `local_interaction/` | 本地互动的输入框、面板、样式、礼物条（归 A08.2；输入框在竖屏、横屏、竖屏全屏的位置归这里：`local_composer.dart:49`、`:437`） |
| `logic/room_layout.dart` | 纯 Dart 的布局规则：`RoomDisplay`（`:6`）、`RoomPageLayout`（`:26`）、`ControlsArrangement`（`:45`）、分界 840 和 480（`:59`、`:62`）、`roomPageLayout`（`:66`）、`controlsArrangement`（`:75`）、竖屏流和竖屏全屏的条件（`:94`、`:105`）、全屏方向设置（`:113`）、三档高度（`:137`）、拖动判定（`:166`、`:178`）、画面拖动分区 `pictureDragAt`（`:197`）、换台判定（`:208`）、画面模式（`:219`）、平衡填充（`:240`）、聊天栏宽（`:254`） |
| `logic/room_status.dart` | 画面状态：`PictureStateKind`（`:10`）、按钮 `PictureAction`（`:72`）、`pictureHasControls`（`:185`）、`pictureStateOf`（`:194`） |
| `logic/room_switch.dart` | 切换直播间的分组、列数（`roomSwitchColumns` `:60`）、卡高（`:70`）、分组列表（`:134`）、筛选（`:172`） |
| `logic/mini_window.dart` | 小窗规则：应用内小窗大小（`:98-120`）、离底边（`:132`）、位置（`:142`）、什么时候转成小窗（`:163`）、自动画中画（`:178`）、小窗弹幕尺寸和帧率（`:195`、`:232`） |
| `logic/room_runtime.dart` | `RoomRuntime`（`:19`，一个房间的全部部件）、`FloatingRoom`（`:90`，应用内小窗接手） |
| `logic/room_controller.dart`、`background_playback.dart`、`predictive_back.dart`、`reconnect_watch.dart`、`room_orientation.dart`、`room_playlist.dart`、`room_refresh_rate.dart`、`player_standby.dart`、`device_battery.dart`、`iptv_guide_rows.dart`、`area_lookup.dart` | 房间逻辑（C 组）、后台和画中画通道（O03）、预测返回（C03.1）、重连计数（A07.10 c4）、本直播间方向、换台列表、刷新率（R02）、播放器待机（C02.1）、电量、节目单行、按名字找分区；界面只读它们 |

直播间用到的 `packages/live_ui` 组件：

| 文件 | 职责 |
|---|---|
| `packages/live_ui/lib/src/theme/live_colors.dart` | `OnVideoColors`（`:9`：前景白、60% 黑渐变、45% 按钮底、黄色“非默认”、沉浸背景兜底渐变、小窗阴影）、`LiveSemanticColors`（`:160`：直播红、录制红） |
| `packages/live_ui/lib/src/widgets/ambient_backdrop.dart` | 沉浸背景 `AmbientBackdrop`（`:17`）：封面按 24 像素宽解码一次再放大 1.14 倍 + 15% 黑，不实时模糊 |
| `packages/live_ui/lib/src/widgets/video_state_view.dart` | 画面状态 `VideoStateView`（`:38`）：转圈或图标、一句话、原因、最多两个按钮 |
| `packages/live_ui/lib/src/widgets/video_centre_button.dart` | 中间的 ▶ 和缓冲转圈 `VideoCentreButton`（`:20`，64） |
| `packages/live_ui/lib/src/widgets/record_glyph.dart` | 录制图标 `RecordGlyph`（`:41`）、角标 `RecordingBadge`（`:328`） |
| `packages/live_ui/lib/src/widgets/stream_menu_button.dart`、`app_menu.dart`、`adaptive_panel.dart`、`follow_pill.dart`、`listenable_selector.dart` | 贴着按钮的小菜单 `showSmallMenu`（`:174`）、右上角菜单 `AppMenuButton`、面板外框 `PanelFrame`（`:155`）和头 `PanelHeader`（`:79`）、关注胶囊、只在选中部分变化时重建 |
| `packages/live_ui/lib/src/icons/app_icons.dart`、`danmaku_icon.dart` | 直播间用到的全部图标（按用途命名）、v3 的弹幕 SVG |

测试（`apps/pure_live/test/features/live_play/` 的 20 个测试文件，括号里是用例和分组数）：

| 测试文件 | 覆盖什么 |
|---|---|
| `live_play_layouts_test.dart`（34） | 竖屏流、竖屏全屏、横屏全屏、宽屏、窗口内全屏、横屏手机的排法和按钮顺序；一个播放器（同一个 State）；锁定；电量；暂停时常显（A07.10 c1）；单击和双击（A07.11 c1）；窄屏不溢出（A07.11 c3）；三档面板档位保持；各平台的菜单 |
| `live_play_room_test.dart`（14） | 顶栏、竖屏上下栏、全屏上下栏、信息行、占位、详情、紧凑弹幕、菜单、重连和纯音频（A07.1）；`ReconnectWatch`、方向的记住 |
| `live_play_popups_test.dart`（22） | 清晰度和线路小菜单、录制面板九种状态、面板位置、弹幕设置面板、右上角菜单、长按弹幕（A07.6） |
| `room_popups_test.dart`（12） | 定时关闭、房间音量、获取直链、投屏、长按弹幕在各布局的位置；房间音量 = 系统音量；画面比例小菜单；全屏提示条位置（A07.12） |
| `room_switch_test.dart`（17） | 切换直播间的列数、卡片数不少于 v3、分组、筛选、刷新、原地换台、全屏菜单去重（A07.13） |
| `room_swipe_test.dart`（9） | 上下滑换台的列表、分区、松手判定、同一个播放器、连续快滑（A07.3） |
| `live_play_states_test.dart`（21） | 18 种画面状态、按钮顺序、节目单（A07.7）；纯音频暂停（A07.10）；锁定后能解锁（A07.10 c5） |
| `live_play_mini_window_test.dart`（23） | 应用内小窗、桌面小窗、Android 画中画（A07.8）；小窗暂停和弹幕（A07.10） |
| `live_play_page_test.dart`（12） | 手机布局、详情、宽窗口、画中画回来、全屏、飞行弹幕点按（A08.4、A07.11 c1） |
| `chat_list_follow_test.dart`、`live_play_tabs_test.dart`、`chat_feed_test.dart`、`chat_names_test.dart`、`chat_benchmark_test.dart` | 弹幕区（A08.1；`chat_list_follow_test` 里有进出全屏位置不变，A07.11 c4） |
| `live_play_controller_test.dart`、`live_play_more_test.dart`、`live_play_more_page_test.dart`、`room_extras_test.dart`、`room_refresh_rate_test.dart`、`local_interaction_test.dart` | 房间逻辑（C）、菜单工具、竖屏识别、预测返回、刷新率、本地互动 |
| `live_play_support.dart` | 测试用的假播放引擎和房间 |

`packages/live_ui/test/`：`design_system_test.dart`（`AppIcons` 对照、`DanmakuIcon`、`RecordGlyph`、`AmbientBackdrop`）、`widgets_test.dart`（`VideoStateView`、`VideoCentreButton`）、`small_menu_test.dart`、`menu_additions_test.dart`（小菜单）。

## 3.x 基线

文件在 `git show v3.2.11:lib/modules/live_play/...`（下面省略这个前缀），播放和小窗在 `lib/player/`：

- 页面和布局：`pages/live_play_page.dart:9`（`LivePlayPage`，GetX）；`widgets/layout/live_play_content.dart`：`:20-22` 宽 ≤680 竖屏堆叠、>680 左右分栏，`:30-120` `LivePlayNormalLayout`（分栏聊天栏 34%、300–400，`:96`），`:123` 三档面板 `PortraitLiveRoomLayout`，`:479` `LivePlayContent`（画中画 `:490`、普通 `:497`、全屏和竖屏全屏），`:549` 顶栏宽 <600 时紧凑，`:606` 背景图取法，`:623` 实时模糊的 `PortraitFullscreenPresentation`；`widgets/layout/live_play_video.dart:63-77`（占位选哪个）、`:120` 16:9 框 `LivePlayVideoFrame`；`widgets/layout/live_play_header.dart:8`（顶栏）。
- 显示状态：`states/ui_state.dart:3` 的 `VideoMode { normal, widescreen, fullscreen, portraitFullscreen }`；进出全屏 `widgets/video_player/video_controller.dart:1311-1520`（`toggleFullScreenFromGesture` `:1355`、`enterLandscapeFullScreen` `:1398`、`enterPortraitFullScreen` `:1417`、`applyFullscreenOrientationPolicy`、`toggleWindowFullScreen` `:1496`）。
- 控制层：`widgets/video_player/video_controller_panel.dart`（2213 行）：`:99` `VideoControllerPanel`；`:196-249` 单击（播放中隐藏，暂停时**继续播放**）、长按弹幕、双击全屏；`:299` 上栏 `TopActionBar`；`:817-1006` 亮度音量拖动（左右两半，没有避开系统手势区；竖屏全屏底部 96 上滑回面板 `:904-930`）；`:1009` 锁定；`:1048` 全屏清晰度线路合并按钮；`:1394` 下栏 `BottomActionBar`（宽度不到 760 去掉三个按钮 `:1439-1441`）。
- 键盘和返回：`widgets/keyboard/video_keyboard.dart:8`（Esc、空格、R、↑↓、媒体键，`:55-80`），`:89-101` Esc 的退出顺序；`widgets/layout/live_play_back_scope.dart:14`（Android 返回）。
- 弹窗：`dialogs/play_other.dart`（切换直播间）、`room_timer_dialog.dart`、`room_volume_dialog.dart`、`known_room_link_dialog.dart`、`live_dlna_dialog.dart`；`widgets/button/live_play_menu_button.dart`（菜单）、`record_action_button.dart`（录制五个动作）、`favorite_floating_button.dart`（关注）；`widgets/video_player/portrait_playback_picker_dialog.dart`（画面模式、方向）、`iptv_schedule_dialog.dart`（节目单）。
- 状态：`widgets/placeholder/not_living_video_widget.dart`、`widgets/video_player/playback_failure_overlay.dart`、`video_loading.dart`；纯音频 `lib/player/core/player_manager.dart:3292-3477`。
- 小窗：`lib/player/core/player_manager.dart:2808`（`enablePip`）、`:2970`（`showAppFloating`）、`:3219`（`buildPiPOverlay`）、`:4737`（`resolveAppFloatingSize`）；`lib/player/utils/window_helper.dart`（Windows 小窗）、`popup_route_tracker.dart`（有弹层时隐藏）；`widgets/danmaku/compact_danmaku_overlay.dart`。
- 详细的样子和问题：[inventory/V3_UI.md](../../inventory/V3_UI.md) 第 5～7 节（竖屏、横屏全屏、宽屏），逐项界面：[inventory/UI.md](../../inventory/UI.md) 的 A07.1～A07.8；每个任务 README 的“3.x 的样子和问题”。

**必须保留的操作习惯**（[specs/UI.md](../../specs/UI.md) 附录 A，和直播间有关的 12 条）：

| 附录 A | 内容 | v4 的位置 | 测试 |
|---|---|---|---|
| 1 | 手机单击显示或隐藏控制层，从不继续播放；暂停时控制层常显、中间 ▶；桌面单击只显示 | `player/player_view.dart:333-386`（`_onTap`、`_tapControls`）、`:312-319` | `live_play_layouts_test.dart` 的 paused、A07.10 c1、B09 c1 用例 |
| 2 | 控制条范围内的点击不触发弹幕命中 | `player_view.dart:830`（`danmakuTapAllowed`）、`:413-438` | `live_play_page_test.dart` 的“never on the bars” |
| 3 | 双击：竖屏源进竖屏全屏，其余进全屏；全屏中先退出 | `player_view.dart:338-350`；`live_play_page.dart:526-561`（`portraitFullscreenEligible`） | `live_play_layouts_test.dart` |
| 4 | 左侧上下滑调亮度、右侧调音量；锁定锁住所有手势 | `player/player_gestures.dart:143-169`；`player_view.dart:643`（`enabled: !_locked`） | `live_play_layouts_test.dart` 锁定；`room_popups_test.dart` 音量 |
| 5 | 竖屏三档面板；拖过最低档或点把手进竖屏全屏；竖屏全屏底部上滑退出 | `layout/portrait_panel.dart`；`logic/room_layout.dart:166-178`；`player_gestures.dart:148-151` | `live_play_layouts_test.dart` 竖屏流 |
| 6 | 点击或长按命中的弹幕，打开复制和屏蔽菜单 | `player_view.dart:389-398`、`:659-666`；`danmaku/message_panel.dart` | `live_play_page_test.dart` F.2b 组 |
| 7 | 返回链：弹层 → 全屏 → 普通 → 离开；Esc 同一条 | `live_play_page.dart:639-676`、`:738` | `live_play_page_test.dart`、`live_play_popups_test.dart` |
| 8 | 应用内小窗：有弹层时隐藏；手机第一次点显示控件、再点回直播间；只有有画面且没出错才转小窗 | `mini/floating_window.dart:90`；`mini/mini_player.dart`；`logic/mini_window.dart:163-176` | `live_play_mini_window_test.dart` |
| 9 | 切换画质和线路不重建播放器，以最后一次为准 | `buttons/stream_menu.dart`（调控制器，C/G 负责） | `live_play_popups_test.dart` |
| 10 | 进入直播间不改设备音量 | `logic/room_controller.dart:551`（`_volume`，手机上不改系统音量） | `live_play_controller_test.dart` |
| 11 | 强制横屏全屏退出后恢复竖屏 | `live_play_page.dart:595-607`（转回竖屏，3 秒后放开） | `live_play_layouts_test.dart` 的“横屏全屏” |
| 12 | 可选的“默认全屏” | `live_play_page.dart:244-258`（`enableFullScreenDefault`） | — |
| 15、16、18 | 小窗可选置顶；键盘空格、R、↑↓、Esc；定时关闭 | `mini/room_mini_window.dart`（图钉）；`live_play_page.dart:736-754`；`dialogs/room_dialogs.dart:43` | `live_play_mini_window_test.dart`、`room_popups_test.dart` |

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理（任务编号或“不做”） |
|---|---|---|---|
| 双击飞行弹幕：第一下立即打开弹幕面板，第二下撤销时关掉，面板一闪（3.x 双击弹幕直接全屏） | `player/player_view.dart:333-366`（`_onTap`）、`:389-398`（`_tapMessage`） | 想双击全屏时看到面板闪一下 | A07.14 |
| 画面上下滑没避开系统底部手势区：从底边上滑回桌面时先调了亮度或音量 | `player/player_gestures.dart:143-169`（`_onDragStart` 不看系统手势区） | 每次手势回桌面都可能误调 | A07.15（参考上游 pure_live `1cdcb7b2a`） |
| 京东直播间背景只有渐变（没见过卡片时没有封面），平台给的模糊图 `JdLiveRoom.background` 没用上 | `player/player_view.dart:494-497`（`_cover`）、`player/player_status.dart:321`、`:351` | 京东的沉浸背景和纯音频封面不如 3.x | A07.16 |
| 应用内小窗拖动时每次移动都整层重建（`setState` 让 `LayoutBuilder`、`StreamBuilder`、`MiniPlayerSurface` 和画面一起重建），松手没有惯性、不吸边 | `mini/floating_window.dart:191-194`（`onDragUpdate` 里 `setState`） | 拖动可能掉帧（没量过），手感生硬 | 无任务：建议在 R01 开一个“小窗拖动只改位置”的性能任务（或并进 A03.3 的手感），见报告 |
| 全屏里还剩一个居中对话框：弹幕设置面板“小窗弹幕”一节的“弹幕颜色” | `danmaku/danmaku_settings_panel.dart:197`（`showDanmakuColorDialog`） | 全屏时压在画面中间（A07.11 待决定第 6 条） | 无任务（要做时在 A07 登记，改成行下展开色板） |
| 取消关注两种确认：直播间是贴着按钮的小菜单，首页卡片长按是居中危险确认 | `buttons/follow_button.dart`；`shared/rooms/room_menu.dart` | 同一个动作两种样子（D-021 定的） | 维护者决定（A07.12 待决定）；目前按 D-021 |
| 未开播房间每 60 秒查一次，应用在后台也照查 | `logic/room_controller.dart:325-327` | 后台多发请求（A07.7 没做的第 3 条） | 无任务（逻辑归 C01；建议登记） |
| A07.10 之后不再用的参数和图标：`onReopen`（`layout/room_info_bar.dart:32`、`buttons/stream_menu.dart:20`）、`AppIcons.pausedOverlay`、`miniPlay`、`miniPause` | 见左 | 无（死代码） | 以后清理（改 `buttons/`、`player/` 的任务顺手做） |
| “完成”的 A07.2、A07.3、A07.5、A07.7 和 A07.8 的应用内小窗、桌面小窗没有在真机上逐项看过；S02.2、S02.3 只看了竖屏控制层、横屏全屏、清晰度菜单、录制面板、系统画中画、直播间菜单 | — | 完成的证据不全（PROCESS 第 3.2 节要求真机结果） | 登记表问题，见报告；补验并入 S02.6 或单开 |
| macOS、iOS 全屏只显示时间，没有电量 | `logic/device_battery.dart:14` | 苹果平台以后才构建 | A18 |
| Linux、macOS 的桌面小窗代码已在，但只有 Windows 启动桌面外壳 | `app/desktop/desktop_window.dart`（`DesktopWindow.miniHost`） | Linux、macOS 看不到小窗按钮 | X（Linux 桌面版暂停） |
| `inventory/V3_UI.md` 第 5 节“v4 现在（偏差最大）”还是 A07.1 之前的 v4 | `docs/inventory/V3_UI.md:128-133` | 读清单的人会误会现状 | Z（文档维护），见报告 |

已经解决、记在这里免得重复查的：A07.3 发现的 `PlaybackSession.stop()` 叠加时漏掉空闲释放定时器的问题已在 `packages/live_player/lib/src/session.dart:343-367` 修好（提交 `2f4aed12b`，“只有最后一次 stop 设释放”）；A07.8 c11 的“离开应用时自动小窗”设置行已加在设置页（`features/settings/settings_catalog.dart:833`）。

## 相关决定和规范

- D-001（3.x 是基线）、D-003（选择按建议 A，A07.10～A07.13 的选择都是这样定的）、D-004（先 Android）。
- D-012：暂停后单击画面只显示或隐藏控制层，不继续播放；暂停时控制层不自动隐藏（A07.10）。
- D-020：往上甩面板不关闭，拉到最上面停住（三档面板、直播间面板，A03.2）。
- D-021：直播间里取消关注用贴着按钮的小菜单（A07.12）。
- D-022：切换直播间默认 3.x 的小卡片网格，可切换成列表并记住（A07.13，issue #37）。
- D-023：横屏全屏按传感器翻转（O05.2，改的是 `live_play_page.dart` 的 `_enterFullscreen`）。
- D-010：播放中刷新率只用帧率声明（R02.2，`logic/room_refresh_rate.dart`）。
- specs/UI.md：第 3 节原则（第 7 条各客户端一致、第 8 条弹法照 v3 都来自 A07.6 的教训）；第 5.2 节形态清单（竖屏、横屏全屏、竖屏全屏、宽屏、应用内小窗、系统画中画）；第 5.3 节（只有一个展示状态枚举、画面只挂载一个、宽屏聊天栏 34%）；第 5.4 节输入方式；第 7 节弹窗和面板（面板竖屏在画面下方、横屏和宽屏右侧 360）；第 8.1 节画面区域黑底白字、画面上的颜色角色；第 9.3 节性能约束（不模糊、视频不裁圆角、播放器只有一份）；附录 A。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play`（全部直播间测试）；`cd packages/live_ui && flutter test`。主要形态（竖屏、竖屏流、竖屏全屏、横屏全屏、窄横屏 740×360、宽屏 1280×800、窗口内全屏）都有布局测试，按钮顺序和图标、面板位置和尺寸、小菜单位置、画面状态、小窗规则有断言。
- 缺的：没有外观截图测试（`test/goldens/` 还没有，A07.1 记录第 7 条）；拖动手感、帧时间只能真机看（A03.3、R01）；系统画中画、桌面小窗的原生部分只有假的窗口系统和通道。
- 真机（K90）：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 2～15 条（换清晰度线路、重连、未开播、双击全屏和锁定、亮度音量、竖屏主播和三档面板、纯音频和定时关闭、后台、画中画、应用内小窗、投屏、获取直链和切换直播间、房间音量和画面比例），第 2 节第 5、6 条（长按弹幕、画面弹幕点按）。已看过：[S02.2](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（进直播间、竖屏控制层、清晰度小菜单、横屏全屏、录制面板）、[S02.3](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)（系统画中画、直播间菜单、返回链）。待真机的 A07.10～A07.13 各有 `verify.md`。

## 路线

1. **A07.10～A07.13 的真机验证**（待真机）：照各自的 `verify.md` 在 K90 上一次看完（同一个构建，可以和 O05.2、A02.2、A02.3、A10.3、R02.2 一起），通过后登记表改“完成”。顺带补看“完成”但没真机结果的 A07.2、A07.3、A07.5（平板）、A07.7、A07.8 的应用内小窗。
2. **A07.14**（第二档，小）：双击飞行弹幕不再一闪。要先请维护者在 README 的两个方案里选一个；改 `player/player_view.dart` 的 `_onTap`。
3. **A07.15**（第二档，小）：上下滑避开系统底部手势区，用系统给的 `MediaQuery.systemGestureInsets`。改 `player/player_gestures.dart`。和 A07.14 改的是相邻的文件，依次做。
4. **A07.16**（第三档，小）：先出图评审，再让沉浸背景和暗封面优先用 `JdLiveRoom.background`。
5. 和别的组一起的：A03.3（拖动手感，暂停中，改 `layout/portrait_panel.dart`、`player/room_swipe.dart`）、A04.1（尺寸和字号适配，暂停中）、R01.2（K90 基准）；小窗拖动的性能（建议新任务）；V01.5（小窗拖角改尺寸、尺寸设置，提议）。新想法先进 V01。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/live_play/`
- 进度：`███████████████████░` 97%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A07.1 | 竖屏普通布局 | 界面 | 完成 | 2026-10-01 | a7d0e8d2a | [设计或说明](A07.1-竖屏普通布局/README.md)、[记录](A07.1-竖屏普通布局/record.md)、[评审页](A07.1-竖屏普通布局/page/01-对比.jpg) |
| A07.2 | 竖屏流和竖屏全屏 | 界面 | 完成 | 2026-10-01 | 121280824 | [设计或说明](A07.2-竖屏流和竖屏全屏/README.md)、[记录](A07.2-竖屏流和竖屏全屏/record.md)、[评审页](A07.2-竖屏流和竖屏全屏/page/01-说明.jpg) |
| A07.3 | 竖屏全屏上下滑换台 | 界面 | 完成 | 2026-10-02 | cf01bf011 | [设计或说明](A07.3-竖屏全屏上下滑换台/README.md)、[记录](A07.3-竖屏全屏上下滑换台/record.md) |
| A07.4 | 横屏全屏 | 界面 | 完成 | 2026-10-01 | 121280824 | [设计或说明](A07.4-横屏全屏/README.md)、[记录](A07.4-横屏全屏/record.md)、[评审页](A07.4-横屏全屏/page/01-说明.jpg) |
| A07.5 | 宽屏左右分栏 | 界面 | 完成 | 2026-10-01 | 121280824 | [设计或说明](A07.5-宽屏左右分栏/README.md)、[记录](A07.5-宽屏左右分栏/record.md)、[评审页](A07.5-宽屏左右分栏/page/01-说明.jpg) |
| A07.6 | 直播间弹窗：清晰度、线路、录制、弹幕设置、右上角菜单、长按弹幕 | 界面 | 完成 | 2026-10-01 | a6609f0c3 | [设计或说明](A07.6-直播间弹窗/README.md)、[记录](A07.6-直播间弹窗/record.md)、[评审页](A07.6-直播间弹窗/page/01-对比.jpg) |
| A07.7 | 直播间的状态：加载、未开播、失败和重连、受限、纯音频；节目单和回看 | 界面 | 完成 | 2026-10-01 | 05793a4c8 | [设计或说明](A07.7-直播间的状态/README.md)、[记录](A07.7-直播间的状态/record.md)、[评审页](A07.7-直播间的状态/page/01-说明.jpg) |
| A07.8 | 小窗：应用内小窗和系统画中画 | 界面 | 完成 | 2026-10-01 | 62e8b34dd | [设计或说明](A07.8-小窗/README.md)、[记录](A07.8-小窗/record.md)、[评审页](A07.8-小窗/page/01-说明.jpg) |
| A07.9 | 已合并界面任务的收尾（横屏、宽屏、多画面、账号、平台名） | 界面 | 完成 | 2026-10-02 | 085fb71a3 | [设计或说明](A07.9-已合并界面任务的收尾/README.md)、[记录](A07.9-已合并界面任务的收尾/record.md) |
| A07.10 | 暂停状态：中间 ▶、控制层常显、“暂停时的弹幕”设置、重连误报、锁定后能解锁 | 功能 | 待真机 | 2026-10-02 | 7cd3a0463 | [设计或说明](A07.10-暂停状态/README.md)、[任务书](A07.10-暂停状态/brief.md)、[记录](A07.10-暂停状态/record.md)、[真机验证](A07.10-暂停状态/verify.md) |
| A07.11 | 直播间小问题合集：单击立即响应、全屏状态保持、全屏不再有居中对话框等 | 功能 | 待真机 | 2026-10-02 | d3272b9b1 | [设计或说明](A07.11-直播间小问题合集/README.md)、[任务书](A07.11-直播间小问题合集/brief.md)、[记录](A07.11-直播间小问题合集/record.md)、[真机验证](A07.11-直播间小问题合集/verify.md) |
| A07.12 | 直播间子弹窗统一：定时关闭、房间音量、投屏、获取直链、画面比例 | 界面 | 待真机 | 2026-10-02 | c112f5415 | [设计或说明](A07.12-直播间子弹窗统一/README.md)、[任务书](A07.12-直播间子弹窗统一/brief.md)、[记录](A07.12-直播间子弹窗统一/record.md)、[真机验证](A07.12-直播间子弹窗统一/verify.md)、[评审页](A07.12-直播间子弹窗统一/page/01-说明.jpg) |
| A07.13 | 切换直播间面板：各布局同一个面板、3.x 小卡片网格、原地换台、去掉重复入口（issue #37） | 界面 | 待真机 | 2026-10-02 | 4a09a48bc | [设计或说明](A07.13-切换直播间面板/README.md)、[任务书](A07.13-切换直播间面板/brief.md)、[记录](A07.13-切换直播间面板/record.md)、[真机验证](A07.13-切换直播间面板/verify.md)、[评审页](A07.13-切换直播间面板/page/01-说明.jpg) |
| A07.14 | 双击飞行弹幕时弹幕面板会一闪再关上 | 界面 | 待真机 | 2026-10-08 | — | [设计或说明](A07.14-双击飞行弹幕面板一闪/README.md)、[任务书](A07.14-双击飞行弹幕面板一闪/brief.md)、[记录](A07.14-双击飞行弹幕面板一闪/record.md) |
| A07.15 | 画面上下滑避开系统底部手势区：上滑回桌面时不再误调亮度或音量 | 功能 | 完成 | 2026-10-08 | — | [设计或说明](A07.15-画面上下滑避开系统手势区/README.md)、[任务书](A07.15-画面上下滑避开系统手势区/brief.md)、[记录](A07.15-画面上下滑避开系统手势区/record.md) |
| A07.16 | 京东直播间用模糊封面作背景（UPGRADES 28-3，先改直播间设计） | 界面 | 待真机 | 2026-10-08 | — | [设计或说明](A07.16-京东直播间模糊背景/README.md)、[任务书](A07.16-京东直播间模糊背景/brief.md)、[记录](A07.16-京东直播间模糊背景/record.md) |
| A07.17 | 直播间真机对照修正：信息行折行、手机横屏分栏太挤、竖屏流弹幕只露两行和画面上方黑边、竖屏控制层没有暗角、详情数字截断 | 界面 | 完成 | 2026-10-08 | dc87bcac4 | [设计或说明](A07.17-直播间真机对照修正/README.md)、[任务书](A07.17-直播间真机对照修正/brief.md)、[记录](A07.17-直播间真机对照修正/record.md) |
| A07.18 | 切换直播间面板里筛选主播时，键盘盖住结果和“没有名字包含……”的提示 | 界面 | 待真机 | 2026-10-08 | — | [设计或说明](A07.18-切换面板筛选时键盘盖住结果/README.md)、[任务书](A07.18-切换面板筛选时键盘盖住结果/brief.md)、[记录](A07.18-切换面板筛选时键盘盖住结果/record.md) |
| A07.19 | 直播间里键盘弹起时，返回先收键盘（现在会连面板一起关，或直接退出直播间） | 界面 | 完成 | 2026-10-08 | — | [设计或说明](A07.19-键盘弹起时返回先收键盘/README.md)、[记录](A07.19-键盘弹起时返回先收键盘/record.md) |
| A07.20 | 语音直播（猫耳FM、克拉克拉）画面换成房间封面：不再把 16×16 的占位画面或纯色背景拉满 | 界面 | 完成 | 2026-10-08 | — | [设计或说明](A07.20-语音直播显示房间封面/README.md)、[记录](A07.20-语音直播显示房间封面/record.md) |
| A07.21 | 直播间顶栏和详情不显示平台的占位分区名（京东直播间写成“京东直播 · JD Live”） | 界面 | 待真机 | 2026-10-08 | — | [设计或说明](A07.21-顶栏不显示平台的占位分区名/README.md)、[记录](A07.21-顶栏不显示平台的占位分区名/record.md) |

<!-- docs:生成结束 -->
