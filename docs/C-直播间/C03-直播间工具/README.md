# C03 直播间工具

右上角菜单里的功能：定时关闭、投屏入口、获取直链、App 跳转、返回手势。

直播间菜单里那些“用一下就走”的工具的行为，以及 Android 的返回键和返回手势在直播间里怎么走。

## 范围

- 包括：
  - 菜单项和它们的动作（`buttons/room_menu_button.dart` 的 `RoomMenuButton.run`）：切换直播间（打开面板）、定时关闭、房间音量、画面比例、投屏、获取直链、分享、在平台打开、在新窗口播放（Windows）、本地互动。
  - 定时关闭和自动助眠的计时（`LiveRoomController.setSleepTimer`，到时暂停并提示）和它的面板（`dialogs/room_dialogs.dart`）；房间音量（按房间记住，3.x 键 `room_vol_<平台>_<房间>`）。
  - 获取直链和投屏的选择流程（`dialogs/stream_dialogs.dart`：清晰度 → 线路 → 复制或选接收器），投屏搜索前申请本地网络权限。
  - 外部打开（`externalRoomTarget`、`openRoomExternally`）：网页用平台适配器给的 `room.link`，Android 先试平台 App（哔哩哔哩、斗鱼、抖音、虎牙、CC、快手）。
  - Android 返回的接管：`logic/predictive_back.dart` 的 `RoomBackChannel` 和页面里的 `_nativeBack`。
  - 画面比例、本直播间画面方向两个小菜单的行为（`dialogs/player_dialogs.dart`）；节目单的入口和回看动作（`dialogs/iptv_guide.dart`，规则在 L01）。
- 不包括（归哪里）：
  - 菜单、面板、小菜单的样子 → A07.6、A07.12；切换直播间面板 → A07.13（换台的逻辑在 [C01](../C01-进房和房间逻辑/README.md)）。
  - DLNA 协议和设备控制 → N02（`packages/live_cast`）；分享口令的格式和系统分享面板 → O03（`shared/rooms/share_code.dart`、`platform/plugins.dart`）。
  - 返回的原生部分（`MainActivity.kt` 的 `pure_live/predictive_back`、`onBackPressed`）和在厂商系统上的验证 → O06。
  - 录制按钮和录制面板 → A07.6、H02；关注按钮 → A07.12。

## 现状：做到哪、怎么工作的

用户看得到的：

- **菜单**（标题栏右上角四方块图标，3.x `LivePlayMenuButton`）分三组（A07.6 M1）：切换直播间、定时关闭、房间音量、画面比例｜投屏（只有 Android）、获取直链、分享、在<平台>打开、在新窗口播放（Windows）｜本地互动（打开本地互动时）。全屏栏上已有的（切换直播间、投屏、横屏的画面比例）不在那里的菜单里重复（A07.13 c12）。定时关闭项第二行显示“N 分钟后暂停”，画面比例显示当前比例；没在播时投屏和获取直链是灰的。网络电视没有分享和在平台打开。
- **定时关闭**：预设 15、30、45、60、90、120、240、480 分钟和自定义分钟；到时暂停并提示。自动助眠（设置“新直播间自动助眠”，Android）进房即纯音频，按 `asmrSleepMinutes` 开同一个计时器，菜单里能看到、能改（C01.2 问题 4）。
- **获取直链、投屏**：一个面板里先选清晰度（正在播的打勾，只有一档时跳过）、再选线路（显示地址）；复制后关闭并提示“已复制直链”；投屏再列接收器，搜 20 秒（`packages/live_cast/lib/src/controller.dart:131`），点了转圈、投上后打勾。网络电视回看时给回看地址。
- **在平台打开**：Android 先跳 App，打不开提示“无法打开APP，将使用浏览器打开”再开网页；快手要正在播（有本场的 `liveStreamId`），没开播只开网页。
- **返回（Android）**：直播间打开期间整个返回交给页面：上面有弹窗或面板先关它；全屏先退全屏；详情先关详情；否则离开直播间；直播间是第一页时交给系统。直播间里没有系统的预测返回动画（3.x 也没有）。

内部怎么工作：

```text
菜单选中 → RoomMenuButton.run（buttons/room_menu_button.dart:228）按 RoomMenuEntry 分派
直播间 initState → RoomBackChannel.instance.hold(this, _nativeBack)（live_play_page.dart:262）
  → 通道 setEnabled(true) → MainActivity 在 Android 13+ 以 PRIORITY_OVERLAY 注册回调（MainActivity.kt:639-650），
    返回键还送到 onBackPressed 的厂商系统也接住（:665-671）
  → 返回时通道 backInvoked → _nativeBack（live_play_page.dart:646）：
       上面有路由 → maybePop；_poppable 为假 → _back()（面板 → 全屏 → 详情）；否则 maybePop 或 SystemNavigator.pop
直播间 dispose → RoomBackChannel.release(this)：只有持有者自己能放开（logic/predictive_back.dart:42-47）
```

- 完成度：清点 8.2（RT）11 项里 10 项“完成”，F-RT-01 投屏是“没验证”（没对真电视试过，归 [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 1 阶段）。C03.1 的快手跳转（F-RT-05）和切换直播间刷新（F-RT-07）没在真机看，V03.3 按 D-029 判为完成（打开 App 走系统、刷新走关注的同一套逻辑，组件测试覆盖），没有专门的真机任务。S02.3 在 K90 上看过菜单各项能打开、返回逐级退出；接管后的手势返回（F-AND-08）归 S02.6，ColorOS 另见 O06.1。

## 代码地图

`apps/pure_live/lib/features/live_play/` 下：

| 文件 | 职责 |
|---|---|
| `buttons/room_menu_button.dart`（344 行） | `externalRoomTarget`（:30，网页 + 各平台 App 地址）、`kuaishouStreamId`（:66）、`kuaishouAppLink`（:78）、`openRoomExternally`（:86，先 App 再网页）、`RoomMenuEntry`（:111）、`castSupported`（:148，只有 Android）、`roomMenuGroups`（:158）、`menuEntriesOnBars`（全屏栏上已有的不进菜单）、`RoomMenuButton`（:199，`run` :228） |
| `buttons/stream_menu.dart`（115 行） | 清晰度和线路两个按钮 `StreamPickers`，条上和全屏栏共用（A07.6） |
| `buttons/follow_button.dart`（250 行）、`buttons/record_button.dart`（217 行） | 关注按钮（A07.12、D-021）和录制按钮（A07.6、H02）；行为不在本子分类，列出供定位 |
| `dialogs/room_dialogs.dart`（425 行） | 定时关闭：`showSleepTimer`（:18）、预设 `sleepTimerPresets`（:33）、`RoomSleepTimerPanel`（:43）；房间音量：`showRoomVolume`（:244）、`RoomVolumePanel`（:275，滑块即时生效，确定才保存，取消还原） |
| `dialogs/stream_dialogs.dart`（434 行） | `StreamUse`（:16）、`showStreamPanel`（:27）、`RoomStreamPanel`（:50，清晰度 → 线路 → 复制 :140 或接收器）、`castDiscovery`（:282）、`CastDevices`（:290，`_discover` :335 先申请本地网络权限） |
| `dialogs/player_dialogs.dart`（156 行） | 画面比例 `showVideoFitMenu`（:49，存 3.x 的 `videoFitIndex` 下标）、`advanceVideoFit`（:41）；本直播间画面方向 `showRoomOrientationMenu`（:83） |
| `dialogs/iptv_guide.dart`（568 行） | 节目单 `IptvGuideView`（:78）、入口 `showIptvGuide`（:57）、`loadChannelGuide`（:19）；回看和返回直播调用控制器的 `playCatchup`、`backToLive` |
| `logic/predictive_back.dart`（72 行） | `RoomBackChannel`（:15）：`hold`（:31）、`release`（:42）、通道 `pure_live/predictive_back`，只处理 `backInvoked`（:68-71） |
| `apps/pure_live/lib/shared/rooms/room_menu.dart` | `shareRoom`（:236：有系统分享面板时用它，否则复制口令），共享模块，列出供定位 |
| `apps/pure_live/lib/app/launch_args.dart` | `launchNewWindow`（:115，Windows 新窗口），列出供定位 |

测试（`apps/pure_live/test/features/live_play/`）：

| 测试文件 | 覆盖什么 |
|---|---|
| `room_extras_test.dart`（“F.1c”组） | 快手 App 地址（详情、弹幕参数、没开播）；切换直播间刷新；Android 返回（打开时接管、对话框先关、全屏先退、再退出并放开；换房间时旧页面不放掉新页面的） |
| `live_play_more_test.dart`、`live_play_more_page_test.dart` | 外部打开的目标；定时关闭（剩余分钟在菜单里）；获取直链选清晰度和线路后复制；投屏列出接收器、先申请本地网络权限 |
| `live_play_popups_test.dart`（22 个）、`room_popups_test.dart`（12 个） | 菜单分组和各布局里面板的位置（A07.6、A07.12） |

## 3.x 基线

- `lib/modules/live_play/widgets/button/live_play_menu_button.dart`（217 行）：九项菜单（:189-206），顺序是打开直播间、切换直播间、投屏、定时关闭、房间音量、获取直链、分享、本地互动、新窗口（Windows）。
- `lib/modules/live_play/services/room_external_opener.dart`（245 行）：25 个平台分支写死网页地址（:44-210），快手 App 地址（:193-200），Android 先试 App、打不开提示后开网页（:228-240）。
- `lib/modules/live_play/dialogs/room_timer_dialog.dart`（175 行）、`controllers/timer_controller.dart`（45 行，`toggleTimer` :26）；`dialogs/room_volume_dialog.dart`（289 行）；`dialogs/known_room_link_dialog.dart`（299 行）+ `common/utils/live_url_tool.dart:388`、`:405`（获取直链、投屏要重新取详情）；`dialogs/live_dlna_dialog.dart`（543 行）。
- `lib/modules/live_play/services/android_predictive_back_service.dart`（50 行，一组全局回调）、`widgets/layout/live_play_back_scope.dart`（130 行：`_handleNativeBack` 有 `_handlingBack` 防重入，上面有路由先 `maybePop`，否则退出呈现或 `maybePop`）。
- 必须保留：[specs/UI.md](../../specs/UI.md) 附录 A 第 7 条（返回链：弹层 → 全屏 → 普通 → 离开）、第 18 条（定时关闭）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| `_nativeBack` 没有防重入（3.x 的 `_handlingBack` 有） | `live_play_page.dart:646-658` | 很快连按两次返回时，第一次的 `maybePop` 还没完成第二次又进来，可能连退两层（读代码得出，未复现） | O06.1 的真机步骤里看一下；复现就开任务 |
| 投屏没对真电视试过 | `dialogs/stream_dialogs.dart:290` | 不知道真实设备上能不能投 | S02.6 第 1 阶段（CHECKLIST 第 1 节第 13 条）；Android 17 本地网络权限的申请在 [O04.1](../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md) |
| 快手跳转、切换直播间刷新没在真机看 | `buttons/room_menu_button.dart:55-83`、`switch_room/room_switch_panel.dart:409` | 快手 App 的 `kwai://` 地址格式要是变了，只会退回网页，不会出错 | 没有专门的任务（D-029）；日常回归照 CHECKLIST 第 1 节第 14 条看 |
| 在 ColorOS 14 上开着预测返回会不会像上游那样卡死，没验证 | `AndroidManifest.xml:61`、`:68`（`enableOnBackInvokedCallback`） | 可能整个应用的手势返回卡住 | O06.1 |

## 相关决定和规范

- D-018（`room_vol_<平台>_<房间>`、`videoFitIndex`、`asmrSleepMinutes`、`enableAsmrSleepMode` 键不变）、D-021（在直播间里取消关注用小菜单）、D-022（切换直播间默认小卡片网格）。
- [specs/UI.md](../../specs/UI.md) 附录 A 第 7、18 条；A07.6（菜单分组 M1）、A07.12（子弹窗统一：定时关闭、房间音量、投屏、获取直链、画面比例）、A07.13 c12（栏上已有的不进菜单）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/room_extras_test.dart test/features/live_play/live_play_more_test.dart test/features/live_play/live_play_more_page_test.dart test/features/live_play/live_play_popups_test.dart`。外部 App 是否真的打开、DLNA 设备、原生返回的分派只能在真机看。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 5（返回）、9（定时关闭）、13（投屏）、14（获取直链、分享、外部打开、切换直播间）、15（房间音量、画面比例）条。

## 路线

1. S02.6 第 1 阶段：投屏到真电视、接管后的手势返回和 HyperOS 的返回键（`onBackPressed` 路径）。
2. O06.1：ColorOS 14 上的返回手势（整个应用，含直播间接管），顺带看连按两次返回。
3. S02.5 第一阶段 1A 组（第 1A-12～1A-15 条）：A07.12 改过的菜单、画面比例小菜单、取消关注小菜单（界面任务的真机，行为不变）。
4. 之后这个子分类没有登记的任务；新的菜单工具先走 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [C 直播间](../README.md)。

- 代码：`features/live_play/buttons/`、`dialogs/`
- 进度：`█████████████░░░░░░░` 67%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| C03.1 | 直播间小项：快手 App 跳转、切换直播间的刷新按钮、预测返回手势 | 功能 | 完成 | 2026-10-02 | 7b37e6f5f | [设计或说明](C03.1-直播间小项/README.md)、[记录](C03.1-直播间小项/record.md) |
| C03.2 | HyperOS 拦截“在快手打开”：跳转失败时说清楚怎么放行 | 原生 | 未开始 | — | — | [设计或说明](C03.2-HyperOS拦截跳转到平台App/README.md) |

## 还没完成的

- **C03.2 HyperOS 拦截“在快手打开”：跳转失败时说清楚怎么放行**（未开始，第三档，规模 小）
  - 来源：K90 S02.6 第 11 步（2026-10-08）

<!-- docs:生成结束 -->
