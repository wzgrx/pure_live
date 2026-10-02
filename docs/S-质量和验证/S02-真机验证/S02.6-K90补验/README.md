# S02.6 K90 补验：S02.3 漏掉的 8 项

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：[V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md) 核对功能清点时发现：S02.3 登记为“完成”，但它的记录（[S02.3/record.md](../S02.3-K90验证主流程/record.md) 的“没测的”）写明多画面、网络电视、投屏、剪贴板口令、断网重连、账号登录没测；另有 C03.1、O05.1 合并在 K90 用的构建（`288fec0ec`）之后，它们的真机步骤也没走过。
- 相关：决定 D-019（K90 随时可用，只点测试包）、D-029；清单 [CHECKLIST.md](../CHECKLIST.md)；关联任务 S02.4（数据和其他）、H01.4（录制）、K02.1（Keystore）、O02.1（画中画回来后的控制条）、O04.1（Android 17 本地网络权限）

## 目标

把功能清点里归给 S02.6 的 8 个“没验证”功能点在 K90 上逐条走一遍，通过的改成“完成”，不通过的找根因、开任务。做完以后，直播间、多画面、账号和搜索这几块在清点里不再有“没验证”的项。

| 功能点 | 内容 | 清单条目 |
|---|---|---|
| F-ROOM-13 | 屏幕常亮跟设置（开：播放时不灭屏；关：按系统超时灭屏） | CHECKLIST 1 第 7 条 |
| F-AND-08 | 直播间接管返回：先关对话框和面板、再退全屏、再退出直播间 | CHECKLIST 1 第 5 条（返回部分） |
| F-RT-01 | 投屏（DLNA） | CHECKLIST 1 第 13 条 |
| F-MV-06 | 多画面 4 路同时解码、沉浸、全屏和返回 | CHECKLIST 1 第 16 条 |
| F-SRC-04 | 网页搜索（应用内浏览器认出直播间后问是否进入） | CHECKLIST 4 第 3 条 |
| F-ACC-03 | 哔哩哔哩网页（短信）登录 | CHECKLIST 4 第 7 条 |
| F-ACC-07 | 登录后取流（高画质） | CHECKLIST 4 第 8 条 |
| F-AND-01 | 剪贴板识别分享口令（连同 F-AND-02 的文件分享导入） | CHECKLIST 4 第 11 条 |

顺带回归 S02.3 也没测的：断网重连（CHECKLIST 1 第 3 条、2 第 1 条）、网络电视的播放和节目单回看（1 第 17 条），以及 E06.1 留下的“快手卡片进房后标题是卡片标题”（[E06.1 record-2](../../../E-直播平台/E06-平台层升级/E06.1-已批准升级的余项/record-2.md)“要在 K90 上看的”第 1 条）。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 屏幕常亮 | `modules/live_play/controllers/live_play_controller.dart:177-179`、`:252-260`：`WakelockPlus` 跟 `enableScreenKeepOn`，直播间里一直亮（暂停也亮） | `packages/live_player/lib/src/screen_wake.dart:9` 的 `ScreenWake` 计数；`video_view.dart:79` 只在播放或缓冲时请求；直播间 `features/live_play/player/player_view.dart:503-516`、小窗 `mini/floating_window.dart:187` 读设置（O05.1） | 开时 3 分钟不灭屏；关时按系统超时灭屏；暂停后按系统超时灭屏（确认过的差别） |
| 返回 | `modules/live_play/services/android_predictive_back_service.dart:7`、`live_play_back_scope.dart` | `features/live_play/logic/predictive_back.dart:15` 的 `RoomBackChannel`（通道 `pure_live/predictive_back`，`MainActivity.kt:92`）；`live_play_page.dart:262` 打开时接管，`:646` 的 `_nativeBack` 按顺序处理（C03.1） | 手势返回和返回键都按“对话框 → 面板 → 全屏 → 退出直播间”一级一级退 |
| 投屏 | `modules/live_play/dialogs/live_dlna_dialog.dart:6` | `features/live_play/dialogs/stream_dialogs.dart`（`StreamUse.cast`，`:336` 先申请本地网络权限）；`packages/live_cast` 的 `DlnaCastController`；电视上显示“主播名 - 标题”（E06.1 5-c4） | 同一 Wi-Fi 的电视或盒子出现在列表里，投出去能播 |
| 多画面 | `modules/multiview/multiview_page.dart:36`、`multiview_controller.dart:49` | `features/multiview/multiview_page.dart:41`、`logic/multiview_controller.dart:155-162`（手机最多 4 格）（N01.1、A13.2） | 2×2 放 4 个国内直播同时播不卡，点格切换声音，沉浸、全屏可进可退，返回安全退出 |
| 网页搜索 | `modules/search/web_search_controller.dart:19` | `shared/in_app_web.dart:45` 的 `InAppWebPage`（flutter_inappwebview 预发布版，O03.1） | 打开平台网页、进到直播间页时询问是否进入，进入后正常播放 |
| 网页登录 | `modules/account/bilibili/web_login_page.dart:6` | `features/account/bilibili_web_login.dart:46` 的 `BilibiliWebLoginView`（O03.1） | 短信登录完成后回到账号页显示用户名；退出时清浏览器 Cookie |
| 登录后画质 | `core/site/*`：Cookie 进请求 | `app/platforms.dart:52` 的 `StoreCookieVault`，适配器经它读 Cookie | 登录后进一个游客只有“超清”的直播间，能选并播放“原画” |
| 剪贴板口令 | `common/global/platform/desktop_manager.dart:621`、`plugins/share_command_handler.dart:28` | `app/intake/clipboard_rooms.dart:34`（启动时和回前台 1 秒后检查，Android 先读剪贴板的变化时间）；`shared/rooms/share_code.dart:69` 解码、`:181` 的 `OwnClipboardTexts`（本次运行自己写的不问）；设置 `detectClipboardRooms`（O03.2） | 复制一个口令后切回应用，约 1 秒后弹“进入直播间”，同一口令只问一次；关掉设置后不再问 |
| 文件分享 | `common/utils/shared_media_intake.dart:9` | `app/intake/share_intake.dart:52`、`android/.../ShareIntakePlugin.kt:84`（O03.2） | 分享 m3u 或用“打开方式”打开 m3u：导入网络电视 |

## 方案

不改代码，只在 K90 上逐条走、记结果：

- c1 直播间：常亮、返回、断网重连、投屏（含 Android 17 的本地网络权限弹窗，结果同时记给 O04.1）。
- c2 多画面和网络电视：4 路、沉浸和全屏、返回；网络电视导入、播放、节目单回看。
- c3 账号和搜索：哔哩哔哩网页登录、登录后画质（顺带扫码登录和重启后仍登录，结果同时记给 K02.1）、网页搜索、剪贴板口令和文件分享、快手标题。
- 结果写进本文件夹的 `verify.md`（照 [templates/verify.md](../../../templates/verify.md)），截图放 `verify/`；通过的功能点在 [FEATURES.md](../../../inventory/FEATURES.md) 改成“完成”并写日期和本任务；不通过的写现象和根因线索，在对应组开任务。

## 性能任务：测量

无：这是功能验证。多画面 4 路时可以顺带记下 `adb shell dumpsys gfxinfo com.mystyle.purelive.v4dev` 的掉帧数，留给 R 组参考，不作为验收。

## 验证

- 自动测试：无新增（各功能的测试在原任务里：`test/features/live_play/room_extras_test.dart`、`test/intake_test.dart`、`packages/live_player/test/` 的常亮用例等）。
- 真机：本任务就是真机验证，步骤见 [brief.md](brief.md)；做完写 `verify.md`。

## 留下的问题

- 画中画回来后控制条卡住的复验不在这里（O02.1）；Keystore 加密存储在 K02.1，可以和第 3 阶段一起做。
- 录制相关的真机项在 H01.4，备份、WebDAV、设备同步、播放代理、Twitch 和 Kick 在 S02.4。
