# A07.4 横屏全屏

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏/README.md](README.md)（第 3 版，用户已确认；G1～G3 按建议 A）；计划书 [specs/UI.md](../../../specs/UI.md) 第 3、5、7–10 节
- 和 A07.2、A07.5 一起做：直播间画面的控制层是**一个组件、三种排法**（内嵌、横屏、竖屏全屏，`ControlsArrangement`），按 specs/UI.md 第 5 节的尺寸分档切换；播放器只挂一份（`GlobalKey`），切换排法时移动不重建。共用部分（尺寸分档、显示状态、`live_ui` 新增）记在本文件，A07.2、A07.5 的记录只写各自的部分。
- 改动的目录：`apps/pure_live/lib/features/live_play/`、`packages/live_ui`（只做添加）、`packages/live_player`（只加一个参数）、`packages/live_store`（只加一个设置，见 A07.5）、Android `MainActivity.kt`（加电量）、翻译文件、文档。
- 原生改动：`MainActivity.kt` 的 `pure_live/device_controls` 加 `getBattery`（`BatteryManager.BATTERY_PROPERTY_CAPACITY`）；已构建 debug APK 确认能编译，没有安装。**Windows 没有原生改动**：电量用 `dart:ffi` 调 `kernel32.dll` 的 `GetSystemPowerStatus`（`ffi` 包已是依赖），请在 Windows 上构建时看一眼时间旁的电量（台式机没有电池时不显示）。

## 共用：显示状态、尺寸分档、控制层

| 内容 | 文件 | 说明 |
|---|---|---|
| 显示状态 | `logic/room_layout.dart` 的 `RoomDisplay` | 内嵌、全屏、竖屏全屏、窗口内全屏（电脑）；系统画中画照旧跟着 `PictureInPicture.active` |
| 页面排法 | `roomPageLayout` | 宽 ≥840 左右分栏；<840 手机排法（竖屏流且开着自适应高度时是三档面板）；**高 <480、横着且宽 ≥600**（横着拿的手机）按横屏手机：左右分栏，聊天栏最窄 300（A08.1 c17 已确认横屏是窄聊天栏，不用手机的上下排法） |
| 控制层排法 | `controlsArrangement` | 内嵌 → 一行上栏一行下栏；全屏 → 横屏排法，手机上屏幕竖着时自动换成竖屏全屏的两行排法（电脑永远是横屏排法） |
| 一个播放器 | `live_play_page.dart` 的 `_playerKey`、`player/player_view.dart` | 各种排法都用同一个 `RoomPlayer`，换排法、换页面布局、进出全屏只移动它；测试固定“同一个 State” |
| 画面上的层 | `RoomPlayer` | 画面铺满整块；弹幕、状态层（`RoomStatusLayer`，A07.7 负责样子）、手势、控制层只排在 `overlayBottom` 以上（A07.2 三档面板用）。飞行弹幕加了矩形裁剪：宽屏时从画面右边缘飞进来的弹幕原来会画到聊天栏上 |
| 状态覆盖层 | `RoomPlayer` 里 `RoomStatusLayer` 那一层 | 位置不变、构造参数不变，A07.7 只需改 `player/player_status.dart` |
| 本地弹幕输入框 | A08.2 的 `LocalDanmakuComposer.onVideo` | 见下面“输入框” |

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 进入退出、按钮位置顺序和图标、锁定、手势、键盘照 v3 | ✅ | 全屏按钮、双击、F 进入；返回、退出全屏按钮、双击、Esc、返回键退出；左右半边上下滑调亮度音量；Esc / 空格 / R / 上下键照旧。锁定按钮挪回 v3 的位置：右侧中间，50×50、38% 黑圆底（v4 原来放在下栏左边），所有平台的全屏都有（v3 `fullscreenUI`）；锁住后上下栏和手势都停，只剩解锁按钮，点画面显示 / 隐藏它 |
| c2 | 全屏顶栏加录制和四宫格菜单 | ✅ | 和竖屏顶栏是同一个 `RecordButton`、`RoomMenuButton`（画面上用白色：录制的灰圈改白圈，菜单图标白色）；打开的录制面板在右侧（A07.6）；“● 录制中 12:34”角标在上栏下方左侧，可以点开录制面板 |
| c3 | 窄屏输入框收成按钮，其他按钮一个不少 | ✅ | 下栏中间放 A08.2 的输入框（最宽 420）；中间的空间不到 180 时它自己收成 40×40 星形按钮，点开在下栏上方出一行输入框（A08.2 c14），740 宽的窄手机就是星形按钮；刷新、已关注、画面比例不再消失。窄到 640 以下整行改为可横向滚动，仍然一个不少 |
| c4 | 时间电量都在左边 | ✅ | 返回键后面：时间（14 号等宽，每分钟整点刷新一次）、电量（35×15 白框，每分钟读一次、变了才重绘）。电量来源：Android `getBattery`，Windows `GetSystemPowerStatus`（没有电池时不显示），Linux `/sys/class/power_supply/BAT*/capacity`；macOS、iOS 暂时只显示时间 |
| c5 | 切换直播间去掉深色圆底 | ✅ | 和其他图标一样的 `VideoIconButton` |
| c6 | 画面比例改成图标加小菜单；已关注用胶囊 | ✅ | 图标是菜单里“画面比例”同一个（`AppIcons.aspectRatio`），点开是 A07.6 的小菜单（在按钮上方，当前项主色加勾）；“已关注”是 32 高的胶囊（画面上：已关注 18% 白底，关注主色实心） |
| c7 | 渐变 60% 黑，图标带阴影 | ✅ | 沿用 A07.1 的 `OnVideoColors.shade` 和图标阴影 |
| c8 | 清晰度和线路两个按钮 | ✅ | A07.6 的 `StreamPickers`，菜单在按钮上方 |
| c9 | 电脑悬停显示名称；Windows 音量条 | ✅ | 每个按钮都有提示；音量条（图标点一下静音 / 恢复，滑块 96 宽，松手时存为房间音量）在**所有电脑平台**显示（A07.5 的设计写“音量条（电脑）”；v3 只有 Windows） |

### 选择

| 编号 | 决定 | 做到 |
|---|---|---|
| G1 | 全屏顶栏加录制和菜单 | ✅ |
| G2 | 窄屏输入框收成星形按钮 | ✅ |
| G3 | 时间电量都在左边 | ✅ |

### 跨任务待同步（TASKS.md 第 7 节）

| 来源 | 内容 | 做到 |
|---|---|---|
| A07.8 c5 | 小窗按钮在 Linux、macOS、iOS 也显示 | ✅ 上栏所有平台都放这个位置（`topBarSlots(platform:)`），显不显示由 `RoomMiniScope.maybeOf(context)?.supported()` 决定（Android 系统画中画、桌面小窗），点了调 `enter(context)`，`preparing` 时按钮里转圈、不能点 |
| A18.1 | iOS 上栏有小窗、没有投屏，菜单里没有“投屏” | ✅ 投屏只在 Android 上栏；`roomMenuGroups(cast:)` 在 iOS 不放“投屏” |
| A07.7 c6 | 全屏没在播放时的精简上栏 | ✅ 横屏和竖屏全屏的精简上栏照样有返回、时间电量、标题、切换直播间、录制、菜单，只去掉纯音频、投屏、小窗（`PlayerBarActions.reduced`）；内嵌时没在播放照 A07.7 不出上下栏 |
| A08.2 c7 | 全屏输入框提示“发送本地弹幕，只有你看得到” | ✅ 输入框就是 A08.2 的组件（三个输入框同一个，c6） |

### 输入框（本地互动 A08.2）

开发时 A08.2 由另一个代理同时在做，这边先留了一个接口；合并 master 后改成直接放 A08.2 的 `LocalDanmakuComposer.onVideo(onHold: onMenu)`，接口删掉：

- 横屏全屏：下栏中间（左右两组按钮之间，最宽 420）；空间不够时它自己收成星形按钮；
- 竖屏全屏：下方第一行，后面是原画、线路1；
- 本地互动关着时它什么都不画，其他按钮照常排；
- 输入框有焦点、或窄屏输入行开着时，控制层不自动隐藏（`onHold` 走菜单的同一个计数）。

星形按钮的颜色：A08.2 的收起按钮是白色星形，展开后输入框里的星形是本地弹幕颜色（EXTRA 要求星形用本地弹幕颜色、默认白，A08.2 的组件只在输入框里这样做，收起按钮没改，以 A08.2 为准）。

## 新增和改动的文件

| 文件 | 内容 |
|---|---|
| `logic/room_layout.dart`（新） | 显示状态、页面排法、控制层排法、三档面板的高度和手势判定、竖屏全屏画面模式、聊天栏宽度；纯 Dart |
| `logic/device_battery.dart`（新） | 电量 |
| `player/bar_parts.dart`（新） | 时间、电量、音量条、画面比例按钮和小菜单、竖屏全屏画面模式按钮和小菜单（A07.2）、锁定按钮、竖屏全屏进入提示（A07.2） |
| `player/player_controls.dart` | 上栏、下栏按三种排法重写；`RoomPlatform`；`PlayerBarActions`（各排法共用的一组动作） |
| `player/player_view.dart` | `RoomPlayer`：排法、画面呈现（普通 / 两边沉浸背景 / 竖屏全屏四种模式）、`overlayBottom`、锁定、进入提示、点按规则；合并 master 后接上 A07.8 的小窗（`MiniPlayerSurface`、`RoomMiniScope`）、A07.7 的回看角标和“没在播放不出控制栏”、A08.2 的礼物层 |
| `player/player_gestures.dart` | 竖屏全屏底部上滑恢复面板（A07.2） |
| `buttons/stream_menu.dart` | 小菜单抽成 `showSmallMenu`（可带标题和每项说明），清晰度、线路、画面比例、竖屏全屏画面模式共用 |
| `buttons/follow_button.dart`、`record_button.dart`、`room_menu_button.dart` | 画面上的样子（胶囊、白圈、白图标），菜单打开期间控制层不隐藏 |
| `packages/live_ui` | `AppIcons` 8 个、`OnVideoColors` 5 个颜色角色和沉浸背景的兜底渐变（输入框用 A08.2 已有的 `fieldOutline`、`localStyle`）、`AmbientBackdrop`（A07.2）、`LiveNetworkImage.filterQuality`、`RecordGlyph.ringColor` |
| `packages/live_player` | `LiveVideoView.fill`（画面以外填什么颜色，默认黑；沉浸背景要透明）。设计要求画面两边是沉浸背景，media_kit 的 `Video` 默认填黑会盖住它，只能加这个参数 |

## v3 文件 → v4 文件

| v3（`lib/modules/live_play/widgets/`） | v4（`features/live_play/`） |
|---|---|
| `video_player/video_controller_panel.dart` 的 `TopActionBar`、`BottomActionBar`、`DatetimeInfo`、`BatteryInfo`、`LockButton`、`VideoFitSetting`、`ExpandButton`、`ExpandWindowButton`、`FullscreenLocalDanmakuComposer`（位置） | `player/player_controls.dart`、`player/bar_parts.dart`、`player/room_composer.dart` |
| `video_player/volume_control.dart`（`OverlayVolumeControl`） | `player/bar_parts.dart` 的 `VolumeSlider` |
| `video_player/video_controller.dart` 的电量（battery_plus） | `logic/device_battery.dart` + `MainActivity.kt` |
| `keyboard/video_keyboard.dart` | `live_play_page.dart` 的快捷键（照旧） |
| `video_player/video_controller.dart` 的全屏进出、方向 | `live_play_page.dart` 的 `_enterFullscreen`、`_exitFullscreen` |

## 门禁

- `live_play` 直接写的颜色和图标：**9 → 9**（新代码全部走 `AppIcons` 和 `OnVideoColors`），`ui_baseline.json` 不用改。
- 没有新增跨功能引用；`logic/` 没有引用 material（`device_battery.dart` 用 `foundation`、`services`、`dart:ffi`）。

## 测试

- 新文件 `test/features/live_play/live_play_layouts_test.dart` 共 24 个（A07.2、A07.4、A07.5 合在一起），其中这个任务的：
  - 手机横屏：上栏顺序和图标（返回、时间、标题、切换直播间、纯音频、投屏、菜单）、切换直播间没有圆底、下栏顺序（播放、刷新、已关注、弹幕开关、弹幕设置、A08.2 输入框、原画、线路、方向、画面比例、退出全屏）、画面比例图标、胶囊高 32、输入框最宽 420、渐变 60%、锁定在右侧中间 50×50；
  - 窄屏 740：输入框收成星形按钮，点开在下栏上方出输入行，按钮一个不少；
  - 本地互动关闭时不显示输入框，其他按钮照排；
  - 锁定：上下栏消失、只剩解锁，解锁后恢复；
  - Windows：有时间、没有方向、音量条在退出全屏前、测试里没有桌面小窗所以没有小窗按钮（有小窗时由 A07.8 的 `live_play_mini_window_test` 固定）、Esc 退出全屏；
  - 电量有值显示、没有电池不显示；
  - 附录 A 第 1 条：手机单击隐藏播放中的控制层，电脑单击只显示。
- `live_ui`：`design_system_test.dart` 加 2 个（`AmbientBackdrop`、白圈录制图标），`AppIcons` 对照表加 8 个图标。
- 合并本地 master（A08.1、A07.7、A07.8、A08.2）后：`apps/pure_live` 全部 370 个通过（本分支删 1 个、加 24 个）；`live_ui` 51、`live_player` 24、`live_store` 32 个通过；`flutter analyze` 无问题；`check_ui_structure.py` 通过；合并前构建过 debug APK（`MainActivity.kt` 的电量），合并后原生部分没再改。

### 和新设计冲突、照实改了的原有断言

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `live_play_room_test` 全屏上下栏 | 下栏顺序画面比例在方向前；画面比例是文字“默认比例”，点一下换下一种 | 方向在画面比例前（v3 的顺序）；画面比例是图标，点开小菜单选“居中裁剪” | c6 |
| `live_play_room_test` 上栏按钮 | `topBarSlots(android: false)` 只有纯音频 | 电脑、iOS 也有小窗 | A07.8 c5 |

## 没做的和原因

1. **iOS 画中画**：`RoomMiniWindow.supported()` 在 iOS 返回否，按钮不显示（A07.8、A18.1 的范围）。
2. **macOS、iOS 的电量**：本机不能构建这两个平台，暂时只显示时间。
3. **窄屏星形按钮点开后的输入行贴键盘**（A08.2 c14）：输入行的位置这边先放在下栏上方，贴键盘的细节随 A08.2。
4. **“在新窗口打开”等桌面窗口功能**不在这个任务（A16.1）。
