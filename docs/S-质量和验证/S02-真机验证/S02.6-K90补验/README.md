# S02.6 K90 补验：S02.3 漏掉的 8 项（2026-10-07 起还包括登记完成但没有真机结果的国内部分）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：
  - [V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)（2026-10-03，云端新加）：S02.3 登记为“完成”，但它的记录（[S02.3/record.md](../S02.3-K90验证主流程/record.md) 的“没测的”）写明多画面、网络电视、投屏、剪贴板口令、断网重连、账号登录没测；另有 C03.1、O05.1 合并在 K90 用的构建（`288fec0ec`）之后，它们的真机步骤也没走过。功能清点因此有 8 个功能点是“没验证”、归给本任务。
  - 2026-10-07 docs v2 核对：各组写 v2 文档时发现一批“登记完成但没有真机结果”的任务和没有归属的真机步骤（见[子分类说明](../README.md)“已知问题”第 1、2 行）。**国内的、K90 上能直接看的**并进本任务：A07.2、A07.3、A07.7、A07.8；A08.1～A08.4；A09 的观看记录、标签管理、平台显示、关注分区、网页搜索；A10.1、A10.2；A12.1、A12.2；A13.1、A13.2；A14.1 的原生部分；A15.1；D01 的国内平台弹幕；E06.1 能直接看的 6 条里的 5 条（快手卡片标题、AcFun“已播”、观看记录“轮播”标记、投屏标题、目录说明文字；第 6 条备份恢复网络电视和多画面在 S02.4）；I02.1～I08.1 的移动网络提示、关注定时和回前台刷新、标签管理、观看记录刷新和保留数量、工具箱获取直链；C02.1、C03.1、O05.1。海外和数据类在 S02.4，设置各页在 S03.1。
- 相关：决定 D-019（K90 随时可用，只点测试包）、D-029（功能点“完成”的规则）；清单 [CHECKLIST.md](../CHECKLIST.md)（“由谁验证”写 S02.6 的 53 条）；同一次上机可以连着做的：S02.5（同一个构建）、[O02.1](../../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md)（画中画回来）、[K02.1](../../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)（扫码登录后重开）、[O04.1](../../../O-Android系统集成/O04-权限/O04.1-Android17本地网络权限/README.md)（投屏时的本地网络权限）、[O06.1](../../../O-Android系统集成/O06-返回手势、平板和折叠屏/O06.1-预测返回在ColorOS14/README.md)（返回的步骤相同，K90 的结果两边共用）；任务书 [brief.md](brief.md)

## 目标

把归给 S02.6 的功能点和任务在 K90 上逐条走一遍：通过的功能点在清点里改“完成”，对应任务的“实现和验证”补上真机结果；不通过的找根因、开任务。做完以后，直播间、多画面、网络电视、账号和浏览、国内平台弹幕、录制界面和 Android 系统界面这几块在清点和各任务里不再有“没验证”或“没有真机结果”。

原来的 8 个功能点：

| 功能点 | 内容 | CHECKLIST |
|---|---|---|
| F-ROOM-13 | 屏幕常亮跟设置（开：播放时不灭屏；关：按系统超时灭屏） | 1.7 |
| F-AND-08 | 直播间接管返回：先关对话框和面板、再退全屏、再退出直播间 | 1.5（返回部分） |
| F-RT-01 | 投屏（DLNA） | 1.13 |
| F-MV-06 | 多画面 4 路同时解码、沉浸、全屏和返回 | 1.16 |
| F-SRC-04 | 网页搜索（应用内浏览器认出直播间后问是否进入） | 4.3 |
| F-ACC-03 | 哔哩哔哩网页（短信）登录 | 4.7 |
| F-ACC-07 | 登录后取流（高画质） | 4.8 |
| F-AND-01 | 剪贴板识别分享口令（连同 F-AND-02 的文件分享导入） | 4.11 |

2026-10-07 并进来的（按阶段）：

| 阶段 | 任务 | CHECKLIST |
|---|---|---|
| 1 直播间 | A07.2、A07.3 竖屏流和上下滑换台；A07.7 状态；A07.8 应用内小窗；C02.1 播放器复用、小窗比例、竖屏诊断、键盘媒体键；C03.1 快手 App 跳转、切换刷新、HyperOS 返回键；O05.1 常亮；I02.1 移动网络提示；E06.1 投屏标题 | 1.1、1.3、1.4、1.8、1.9、1.12、1.14、1.20～1.24 |
| 2 多画面和网络电视 | A13.1 网络电视管理（系统文件选择器、默认节目单的导入卡和失败卡）、A13.2 多画面（横屏右栏收起把手、全屏退出按钮的位置） | 1.16、1.17 |
| 3 账号、搜索和浏览 | A09.8 网页搜索；A09.9、I06.1 观看记录；A09.10、I07.1 标签管理；A09.6、I03.1 平台显示和关注的分区；I04.1 定时和回前台刷新；A15.1、I08.1 工具箱；A12.1、A12.2 账号和 Cookie 页；E06.1 的 AcFun“已播”、轮播标记、快手标题、目录说明 | 4.2～4.9、4.11～4.18 |
| 4 弹幕（建议新增） | A08.1～A08.4；D01.2～D01.7 国内五大平台和 YY；D01.10、D01.13、D01.14、D01.25～D01.29 其他国内平台 | 2.1～2.9 |
| 5 录制界面和系统界面（建议新增） | A10.1 录制中心、A10.2 录制设置；A14.1 的 c2、c3、c7～c15 | 3.8、3.9、6.1～6.9 |

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`，文件:行） | 现在（`apps/pure_live/lib/`，文件:行） | 要做到 |
|---|---|---|---|
| 屏幕常亮 | `modules/live_play/controllers/live_play_controller.dart:177-179`、`:252-260`：`WakelockPlus` 跟 `enableScreenKeepOn`，直播间里一直亮（暂停也亮） | `packages/live_player/lib/src/screen_wake.dart:9` 的 `ScreenWake` 计数；`video_view.dart:79` 只在播放或缓冲时请求；直播间 `features/live_play/player/player_view.dart:503` 读设置，小窗 `mini/floating_window.dart:187`（O05.1） | 开时 3 分钟不灭屏；关时按系统超时灭屏；暂停后按系统超时灭屏（确认过的差别） |
| 返回 | `modules/live_play/services/android_predictive_back_service.dart:7`、`live_play_back_scope.dart` | `features/live_play/logic/predictive_back.dart:15` 的 `RoomBackChannel`（通道 `pure_live/predictive_back`，`MainActivity.kt:92`）；`live_play_page.dart:262` 打开时接管，`:646` 的 `_nativeBack` 按顺序处理（C03.1） | 手势返回和返回键都按“对话框 → 面板 → 全屏 → 退出直播间”一级一级退 |
| 投屏 | `modules/live_play/dialogs/live_dlna_dialog.dart:6` | `features/live_play/dialogs/stream_dialogs.dart:146`（`StreamUse.cast`，`:336` 先申请本地网络权限）；`packages/live_cast` 的 `DlnaCastController`；电视上显示“主播名 - 标题”（E06.1 第 5 条） | 同一 Wi-Fi 的电视或盒子出现在列表里，投出去能播 |
| 多画面 | `modules/multiview/multiview_page.dart:36`、`multiview_controller.dart:73` | `features/multiview/multiview_page.dart:41`、`logic/multiview_controller.dart:155-162`（手机最多 4 格）；沉浸 `multiview_page.dart:402`（N01.1、A13.2） | 2×2 放 4 个国内直播同时播不卡，点格切换声音，沉浸、全屏可进可退，返回安全退出 |
| 网页搜索 | `modules/search/web_search_controller.dart:19` | `shared/in_app_web.dart:45` 的 `InAppWebPage`（flutter_inappwebview 预发布版，O03.1） | 打开平台网页、进到直播间页时询问是否进入，进入后正常播放 |
| 网页登录 | `modules/account/bilibili/web_login_page.dart:6` | `features/account/bilibili_web_login.dart:46` 的 `BilibiliWebLoginView`（O03.1） | 短信登录完成后回到账号页显示用户名；退出时清浏览器 Cookie |
| 登录后画质 | `core/site/*`：Cookie 进请求 | `app/platforms.dart:52` 的 `StoreCookieVault`，适配器经它读 Cookie | 登录后进一个游客只有“超清”的直播间，能选并播放“原画” |
| 剪贴板口令 | `common/global/platform/desktop_manager.dart:595-651`、`plugins/share_command_handler.dart:28` | `app/intake/clipboard_rooms.dart:34`（启动时和回前台 1 秒后检查，`:93` 先比剪贴板的变化时间）；`shared/rooms/share_code.dart:69` 解码、`:181` 的 `OwnClipboardTexts`（本次运行自己写的不问）；设置 `detectClipboardRooms`（O03.2） | 复制一个口令后切回应用，约 1 秒后弹“进入直播间”，同一口令只问一次；关掉设置后不再问 |
| 文件分享 | `common/utils/shared_media_intake.dart:9` | `app/intake/share_intake.dart:52`、`android/.../ShareIntakePlugin.kt:84`（O03.2） | 分享 m3u 或用“打开方式”打开 m3u：导入网络电视 |
| 移动网络提示 | `common/base/base_page_view.dart:258`（每次请求前查网络 `base_controller.dart:29-47`） | `app/network.dart:73` 的 `MobileDataNotice`（只在刷新前 `precheck` `:82`）、`shared/rooms/room_grid.dart:234` 的提示“您当前正在使用移动蜂窝流量，请注意流量消耗。”和“不再显示” | 用移动数据刷新列表时出现，“不再显示”后本次运行不再出现 |
| 关注的定时和回前台刷新 | `modules/favorite/favorite_controller.dart`：冷却 5 分钟 `:43`、回到前台 15 秒 `:48`、10 秒超时 `:49` | `features/favorite/follow_refresher.dart`（并发上限、10 秒超时、5 分钟冷却）；设置 `autoRefreshFavorite`、`autoRefreshInterval`（默认 30 分钟，5～360）、`refreshFavoriteOnResume`（默认开）（I04.1） | 定时到了静默刷新；回前台刷新，15 秒内不重复 |
| 弹幕（国内） | 3.x 各平台的弹幕 | `packages/live_danmaku/lib/src/sites/`；D01 的 28 个“完成”任务没有单独的 K90 记录，CHECKLIST 第 2 节原来只列国内五大平台 | 国内五大平台的连接、断网、设置、屏蔽、列表、点按、醒目留言都有结果；其他 9 个国内平台各抽查 2 分钟 |
| 系统界面（A14.1） | 3.x 的通知、图标、启动画面 | 原生 `apps/pure_live/android/app/src/main/`：`res/drawable/ic_stat_playback.xml`、`ic_stat_recording.xml`、`ic_pip_play.xml`、`res/mipmap-anydpi-v26/ic_launcher.xml`、`res/values-v31/styles.xml`、`ShareIntakePlugin.kt:139`（快捷方式） | c2、c7～c15 都有 K90 结果（S02.2 只看过 c3、c4、c6 和 c12 的一部分） |

## 方案

不改代码，只在 K90 上逐条走、记结果：

- 阶段 1～3 是登记的三个阶段，各自扩充了 2026-10-07 并进来的条目；阶段 4、5 是 2026-10-07 新增的（已登记，规模改“大”）。
- 每个阶段照 CHECKLIST 里“由谁验证”写着这个阶段的条目走，步骤和期望见 [brief.md](brief.md) 的“真机验证”表。
- 结果写进本文件夹的 `verify.md`（照 [templates/verify.md](../../../templates/verify.md)），截图放 `verify/`；CHECKLIST 的“结果”一列同步填；通过的功能点在 [FEATURES.md](../../../inventory/FEATURES.md) 改成“完成”并写日期和本任务；对应任务 README 的“实现和验证”或“验证”一节加一行“K90（S02.6，日期）：通过 / 有问题（去向）”；不通过的写现象和根因线索，在对应组开任务。

## 性能任务：测量

无：这是功能验证。多画面 4 路时顺带记下 `adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev` 的掉帧数、播放器复用时记下 `dumpsys meminfo` 的 PSS，留给 R 组参考，不作为验收。

## 验证

- 自动测试：无新增（各功能的测试在原任务里：`apps/pure_live/test/features/live_play/room_extras_test.dart`、`test/intake_test.dart`、`test/platform/system_surfaces_test.dart`、`test/features/favorite/favorite_test.dart`、`packages/live_player/test/` 的常亮用例、`packages/live_danmaku/test/` 的各平台用例等）。
- 真机：本任务就是真机验证，步骤见 [brief.md](brief.md)；做完写 `verify.md`。

## 留下的问题

- 画中画回来后控制条卡住的复验不在这里（O02.1）；Keystore 加密存储在 K02.1，可以和第 3 阶段一起做；ColorOS 14 的预测返回在 O06.1。
- 录制核心的真机项（划掉应用后继续录、所有文件访问、弹幕 XML、HLS 预取、H01.3 的清晰度标签和合并进度）在 H01.4；备份、WebDAV、设备同步、应用内更新、播放代理、Twitch 和 Kick、海外平台弹幕在 S02.4；设置各页（A11）、宽屏首页和宽屏分栏在 S03.1。
- E06.1 里要等界面接上才看得到的 5 条（哔哩哔哩轮播播放、酷狗 PK“对方”、Twitch 提示、17LIVE 徽章、Picarto 档名）随 [E06.2](../../../E-直播平台/E06-平台层升级/E06.2-平台层新数据接到界面/README.md) 的真机验证。
- 登记表 2026-10-07 已加阶段 4、5，规模改“大”；标题还没改，可以改成“K90 补验：S02.3 漏掉的 8 项和登记完成但没有真机结果的国内部分”。
