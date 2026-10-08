# 功能清点（v3 → v4）

- 更新：2026-10-08（F-NET-01“部分”→“没验证”：Q02.1 让图片走应用代理，等 K90；F-MINI-05“缺失”→“没验证”：G05.1 音频焦点，等 K90）；2026-10-07（docs v2 收尾：F-NET-01、F-NET-03 改“部分”，补 F-MINI-05 音频焦点，见“统计”一节）；2026-10-03（第 3 版：逐项对照当前代码和各任务的记录重新核对，改动和依据见 [V03.3](../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)）；2026-10-02（第 2 版：整理进新文档）
- 计划：[PLAN.md](../PLAN.md)；任务：[TASKS.md](../TASKS.md)；做法：[PROCESS.md](../PROCESS.md)
- 范围：v3（标签 `v3.2.11`，本机只读副本 `~/ref/v3ref`）里用户能用到的每一个功能点。界面怎么画不在这里（见 [specs/UI.md](../specs/UI.md) 和各界面任务），这里只管“能做什么、做了没有、对不对”。
- **本阶段只判断 Android（手机和平板）**（用户 2026-10-02 决定）。Windows、Linux、电视、苹果平台的功能以后再清点；Windows 专属的功能点列在第 13 节，只写“以后”。

## 怎么读

- **编号**：`F-<模块>-<序号>`，例如 `F-ROOM-13`。任务（[TASKS.md](../TASKS.md)）按编号引用；功能点编号不是任务编号，保持不变。
- **v3 位置**：`lib/` 下的路径省略 `lib/`；Android 原生写 `android/...`；`文件:行` 指主要实现的起点。
- **依据**：v4 代码路径省略 `apps/pure_live/lib/`；包写 `packages/<包>`；`C01.1` 这类是任务编号，记录在任务的文件夹里（旧编号见 [MAPPING.md](../MAPPING.md)）。
- **Android**：是 / 否 / 部分（只在某种条件下适用）。
- **v4 现状**：

| 现状 | 意思 |
|---|---|
| 完成 | 代码和测试都在，记录写明行为同 v3（或是确认过的改动）；关键部分不靠原生、系统服务或联网，或者已在 K90 上看过。最后仍在 K90 上统一验证（[S02 的 CHECKLIST.md](../S-质量和验证/S02-真机验证/CHECKLIST.md)） |
| 部分 | 做了一部分，缺的写在备注 |
| 缺失 | master 上没有（有半成品的写明分支） |
| 有问题 | 有入口或设置，但不生效，或行为和 v3 不同又不是确认过的改动 |
| 没验证 | 代码在，但关键部分靠原生、系统服务、联网或真机，单元测试覆盖不到，K90 上还没看过；备注写明由哪个任务验证。K90 真机验证前不算完成 |
| 不做 | 用户或计划已决定不恢复 |

## 统计

| 模块 | 功能点 | 完成 | 部分 | 缺失 | 有问题 | 没验证 | 不做 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 应用和全局 APP | 24 | 18 | 0 | 0 | 0 | 6 | 0 |
| 2 Android 系统集成 AND | 9 | 4 | 0 | 0 | 0 | 5 | 0 |
| 3 网络和代理 NET | 4 | 0 | 1 | 0 | 0 | 3 | 0 |
| 4 推荐和分区 BRW | 9 | 9 | 0 | 0 | 0 | 0 | 0 |
| 5 房间卡片 CARD | 5 | 5 | 0 | 0 | 0 | 0 | 0 |
| 6 关注 FAV | 8 | 8 | 0 | 0 | 0 | 0 | 0 |
| 7 搜索和历史 SRC、HIS | 7 | 6 | 0 | 0 | 0 | 1 | 0 |
| 8 直播间 ROOM、RT、PORT、MINI | 47 | 43 | 0 | 0 | 0 | 3 | 1 |
| 9 弹幕和本地互动 DM、LOC | 20 | 20 | 0 | 0 | 0 | 0 | 0 |
| 10 多画面 MV | 6 | 4 | 1 | 0 | 0 | 1 | 0 |
| 11 录制 REC | 13 | 9 | 0 | 0 | 0 | 4 | 0 |
| 12 网络电视、账号、备份、工具、标签 | 25 | 19 | 0 | 0 | 0 | 5 | 1 |
| **合计** | **177** | **145** | **2** | **0** | **0** | **28** | **2** |

2026-10-07 docs v2 收尾核对后改了 3 项：F-NET-01 应用代理“完成”→“部分”（封面和头像不走应用代理 → Q02.1）；F-NET-03 断网预检和移动数据提示“完成”→“部分”（只有热门做了 → I03.2）；新增 F-MINI-05 音频焦点（3.x 有、v4 缺失 → G05.1）。下面是第 3 版的说明。

和第 2 版（2026-10-02 的统计：完成 127、部分 3、缺失 15、有问题 3、没验证 26、不做 2）比，26 项状态变了：

- 缺失、有问题、部分 21 项都已由后来的任务做完：17 项改“完成”（C02.1、C03.1、G04.1、D05.1、D03.2、A08.4、H01.3、J04.1、O03.2），4 项改“没验证”——代码已合并，但关键部分靠原生或系统服务、K90 上还没看过：F-AND-01 剪贴板口令、F-AND-08 预测返回、F-NET-02 播放代理、F-ROOM-13 屏幕常亮（上一版在行里写成了“完成”）。
- 没验证 4 项在 K90 上看过，改“完成”：F-AND-06、F-AND-07、F-MINI-01、F-REC-03（S02.2、S02.3 的记录）。
- 完成 1 项改“部分”：F-MV-05 多画面的弹幕不跟弹幕帧率设置（→ N01.2）。
- 26 项“没验证”各自写明由哪个任务验证：S02.4、S02.6、H01.4、J06.1、S04.1、K02.1、O04.1、R02.2、A06.5。

另：第 13 节 Windows 专属 14 项（以后）；第 14 节 35 个平台（33 个 v3 平台、Kick、网络电视）的能力表；第 15 节设置项核对。

v3 没有的、不在清点里的：开播提醒（v3 没有通知开播的功能）、WebDAV 定时备份（v3 没有）、录制历史页（v3 只有路由 `kRecordHistory`，没有页面）。已批准的升级（[specs/UPGRADES.md](../specs/UPGRADES.md)）不是 v3 功能，不在这里；它们的余项和去向写在 UPGRADES 的状态列。

---

## 1 应用和全局（APP）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-APP-01 | 首次启动导入 3.x 数据（设置、关注、历史、分组、屏蔽、Cookie、WebDAV、录制任务） | `common/global/initialized.dart:69`、`common/services/utils/settings_upgrade_migration.dart:29` | 是 | 没验证 | `packages/live_store` 的 `LegacyMigration`（J02.1）、`app/bootstrap.dart`（I01.1）；测试用造的 Hive 文件 | 测试包 `.v4dev` 读不到 3.x 的私有目录，只有覆盖安装才会真走这条路 → J06.1、S04.1 |
| F-APP-02 | 导入 3.x 的网络电视库 `pure_live_tv.db` | `core/iptv/local/database.dart:42` | 是 | 没验证 | `app/iptv_legacy.dart`（L01.2） | 同上 → J06.1、S04.1 |
| F-APP-03 | 启动页（可关） | `modules/splash/splash_screen.dart:6`、`main.dart:197` | 是 | 完成 | `features/splash/`（I08.1、A06.4） | |
| F-APP-04 | 启动后检查更新、新版本对话框（可关） | `modules/home/home_page.dart:205`、`plugins/update.dart:18` | 是 | 完成 | `features/version/update_prompt.dart`（I08.1、I01.2、A06.3） | |
| F-APP-05 | 应用内下载更新包并安装（断点续传、“安装未知应用”权限） | `common/widgets/download_apk_dialog.dart:32`、`:148` | 是 | 没验证 | `app/downloads.dart`、`features/version/update_download.dart`（I01.3） | 权限页跳转、系统安装器没在真机走过 → S02.4（CHECKLIST 5 第 4 条） |
| F-APP-06 | 多语言（简体中文、英文、跟随系统） | `common/services/settings/theme_settings_controller.dart:20` | 是 | 完成 | `i18n/`（I01.1） | |
| F-APP-07 | 主题模式、主题色、动态取色 | `theme_settings_controller.dart:17`、`main.dart:145` | 是 | 完成 | J01.1、A11.2 | |
| F-APP-08 | 文字缩放、五种字号 | `main.dart:140`、`common/services/settings/font_settings_controller.dart:40` | 是 | 完成 | J01.1 | |
| F-APP-09 | 下载字体、设置应用字体 | `plugins/font_download_manager.dart:12`、`modules/settings/pages/font_family_manager_page.dart:13` | 是 | 没验证 | `app/fonts.dart`（I01.3） | 下载和注册后的界面没在真机看 → S02.4（CHECKLIST 5 第 5 条） |
| F-APP-10 | 加载动画样式（85 种） | `modules/settings/pages/loading_style_settings_page.dart:10` | 是 | 完成 | J01.1 | |
| F-APP-11 | 首页菜单（关注、热门、分区、录制），可排序、隐藏 | `modules/home/home_page.dart:113`、`modules/settings/pages/navigation_settings_page.dart:7` | 是 | 完成 | `features/home/`（I01.1、A06.1） | |
| F-APP-12 | 再点“关注”刷新关注 | `modules/home/home_page.dart:108` | 是 | 完成 | I01.1、I04.1 | |
| F-APP-13 | 后台 15 秒以上回来刷新当前页 | `modules/home/home_page.dart:151` | 是 | 完成 | I01.1（`HomeSignals`） | |
| F-APP-14 | 返回键退到后台，不退出应用 | `modules/home/home_page.dart:220` | 是 | 完成 | 原生通道 `pure_live/app`（I01.1） | |
| F-APP-15 | 界面刷新率三档（省电、均衡、性能），显示当前和最高刷新率 | `common/widgets/adaptive_refresh_rate_scope.dart:88`、`common/services/display_mode_service.dart:5` | 是 | 没验证 | I01.1、`platform/display_mode.dart`（I01.3）；播放时按帧率切换 `matchVideoFrameRate`（R02.1）、策略修正（R02.2） | 真机看当前和最高刷新率、播放时的帧率匹配 → R02.2 的真机验证（R02.2 待真机） |
| F-APP-16 | 图片解码缓存上限 | `common/global/initialized.dart:31` | 是 | 完成 | I01.1 | |
| F-APP-17 | 系统内存紧张时清图片缓存 | `common/global/platform/desktop_manager.dart:774` | 是 | 完成 | `app/app.dart:116` 的 `didHaveMemoryPressure` → `releaseImageMemory`（清缓存，并清“正在用的图片”记录）；C02.1 c5，测试 `test/features/live_play/room_extras_test.dart` | 2026-10-02 C02.1（提交 `7b37e6f5f`） |
| F-APP-18 | 图片请求头（哔哩哔哩 Referer、浏览器 UA） | `common/utils/network_image_url.dart:29` | 是 | 完成 | `shared/images.dart`（I01.2） | |
| F-APP-19 | 清除图片缓存、刷新直播缩略图、显示缓存大小 | `modules/settings/pages/cache_data_settings_page.dart:9` | 是 | 完成 | `features/settings/data_tools.dart`（O03.1、I01.3） | |
| F-APP-20 | 定时刷新封面 | `common/services/settings/cache_controller.dart:234` | 是 | 完成 | `data_tools.dart` 的 `CoverRefreshTimer`（O03.1） | |
| F-APP-21 | 定时关闭应用 | `common/services/settings/exit_settings_controller.dart:9`、`modules/settings/pages/general_settings_page.dart:91` | 是 | 完成 | `features/settings/settings_editors.dart` 的 `AutoExitTimer`，`app/startup.dart:49` 启动时接上 | |
| F-APP-22 | 日志（最近 2000 条、写文件、查看、导出） | `common/services/settings/log_controller.dart:10` | 是 | 完成 | `app/app_log.dart`、`features/backup/log_page.dart`（路由 `RoutePath.kLogs`，I01.3） | v3 用本机网页看日志，v4 改为应用内页面 |
| F-APP-23 | 边到边显示、透明状态栏和导航栏、四个方向可转 | `common/global/platform/mobile_manager.dart:11` | 是 | 没验证 | `app/system_bars.dart`（A06.5，2026-10-08）：`SystemBarsScope` 放在 `app.dart` 的 `MaterialApp.builder` 里，所有页面底下是透明状态栏和导航栏、导航栏分隔线透明，图标深浅跟主题（3.x 导航栏图标固定深色，深色主题下看不清），主题切换时随之更新；启动页的 `AnnotatedRegion` 用同一个样式（以前用 Flutter 的 `SystemUiOverlayStyle.light/dark`，带黑色导航栏和浅色图标）；首页 `features/home/home_page.dart` 只设 `edgeToEdge`（同 3.x）；`android/app/src/main/res/values/styles.xml` 的 `android:navigationBarColor` 透明；直播间全屏在 `live_play_page.dart` 切换 `immersiveSticky`、`edgeToEdge`；不调 `setPreferredOrientations`，默认四个方向 | 真机看启动页、首页、设置页、直播间退出全屏后的状态栏和导航栏（浅色、深色，手势、三键）→ A06.5 待真机 |
| F-APP-24 | 配置预览（各模块原始配置、复制） | `modules/settings/pages/local_config_preveiw.dart:8` | 是 | 完成 | `data_tools.dart`（J01.1） | |

## 2 Android 系统集成（AND）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-AND-01 | 剪贴板识别分享口令（启动时、回前台 1 秒后），弹“进入直播间” | `common/global/platform/desktop_manager.dart:621`、`plugins/share_command_handler.dart:28`、`common/widgets/share_command_import_dialog.dart:6` | 是 | 没验证 | O03.2 c1：`app/intake/clipboard_rooms.dart:34` 的 `ClipboardRoomWatcher`（启动时、回前台 1 秒后检查；Android 先经原生通道读剪贴板的变化时间，没变不读内容）、`shared/rooms/share_code.dart:69` 的 `decodeRoomShareCode`、`:181` 的 `OwnClipboardTexts`；提示用 A06.3 的 `showRoomPrompt`；设置 `detectClipboardRooms`；测试 `test/intake_test.dart` | 2026-10-02 O03.2（提交 `8cf3c21b7`）合并；K90 上没试过（S02.3 记录“没测的”：剪贴板口令），读剪贴板变化时间靠原生 → S02.6 |
| F-AND-02 | 接收系统分享和“打开方式”：直播链接进房，m3u/txt 导入网络电视，xml/gz/json 导入节目单 | `main.dart:105`、`common/utils/shared_media_intake.dart:9`、`common/utils/shared_live_link_opener.dart:12`、`android/app/src/main/AndroidManifest.xml:38,78` | 是 | 完成 | O03.2 c3：`app/intake/share_intake.dart:52` 的 `ShareIntake`、`platform/share_channel.dart:75`、`android/.../ShareIntakePlugin.kt`（通道 `pure_live/share_intake`）；测试 `test/intake_test.dart` | 2026-10-02 O03.2；K90 上从别的应用分享哔哩哔哩直播链接直接进房，通过（S02.3 记录）。分享 m3u、节目单文件导入没在真机试 → S02.6 |
| F-AND-03 | 打开后台播放、助眠时申请通知权限和“忽略电池优化”，被拒时说明并给系统设置入口 | `player/core/live_audio_service.dart:207` | 是 | 完成 | O03.2 c4：`shared/permission_prompts.dart:72` 的 `BackgroundPermissions`、`platform/system_permissions.dart`、`android/.../PermissionsPlugin.kt`（`notificationState`） | 2026-10-02 O03.2；K90 上打开后台播放：说明 → 系统通知权限 → 电池说明 → 系统电量页，回来开关是开的，通过（S02.2 记录） |
| F-AND-04 | Android 17 本地网络权限（代理指向局域网、设备同步） | `common/services/local_network_access.dart:10` | 是 | 没验证 | `platform/system_access.dart`（I01.3）；4.0.0 发布前修复（Y01.1 第 4 节）：投屏搜索和局域网直播源也先申请 `ACCESS_LOCAL_NETWORK`（`ensureLocalNetworkFor`），请求码改成 `20261003` | K90 就是 Android 17（S02.2 记录），可以直接验证 → O04.1 |
| F-AND-05 | Cookie、密码加密存储 | `common/services/settings/cookie_settings_controller.dart:9`（v3 明文） | 是 | 没验证 | `platform/secret_cipher.dart`（Android Keystore，I01.1） | v3 明文，v4 加密；Keystore 没在真机跑 → K02.1 |
| F-AND-06 | 系统画中画（系统关了画中画时说明并去设置） | `player/core/player_manager.dart:2808`、`modules/live_play/widgets/video_player/video_controller_panel.dart:423` | 是 | 完成 | `features/live_play/mini/room_mini_window.dart`、`MainActivity` 的 `pure_live/pip`（C01.2、A07.8） | 2026-10-02 K90：直播间上栏小窗按钮进入系统画中画，画面在别的应用上方继续播，通过（S02.3 记录）。从画中画回来后控制条卡住（第二轮发现，S02.1 已防御性修改）没复验 → O02.1 |
| F-AND-07 | 系统媒体通知（标题、主播、封面、播放暂停、停止） | `player/core/live_audio_handler.dart:12` | 是 | 完成 | `features/live_play/logic/background_playback.dart`（C01.2） | 2026-10-02 K90：通知标题是直播间标题、正文是主播名，“暂停”“停止”是中文，通过（S02.2 记录）。v4 只在后台播放或助眠打开时显示（C01.2 确认的改动） |
| F-AND-08 | Android 14 起的预测返回手势 | `modules/live_play/services/android_predictive_back_service.dart:7`、`android/.../MainActivity.kt:26` | 是 | 没验证 | C03.1 c3：`features/live_play/logic/predictive_back.dart:15` 的 `RoomBackChannel`（原生通道 `pure_live/predictive_back`，`MainActivity.kt:92`）；直播间打开时接管返回（`live_play_page.dart:262`），按对话框 → 面板、全屏 → 退出直播间的顺序处理（`:646` 的 `_nativeBack`）；测试 `room_extras_test.dart` | 2026-10-02 C03.1（提交 `7b37e6f5f`）合并；K90 验证用的构建（`288fec0ec`）在它之前，接管后的手势返回没在真机走过 → S02.6；ColorOS 另见 O06.1 |
| F-AND-09 | 原生 HTTP 通道（系统 TLS，Twitch、Kick 用） | `android/.../NativeHttpChannel.kt:16`、`core/common/android_native_http.dart:13` | 是 | 没验证 | `platform/native_http.dart`（I01.1、E03.16） | 有代理时进 Twitch、Kick → S02.4（CHECKLIST 5 第 7 条） |

## 3 网络和代理（NET）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-NET-01 | 应用代理（平台请求、弹幕、图片、WebDAV） | `common/services/settings/proxy_settings_controller.dart:16`、`common/global/initialized.dart:81` | 是 | 没验证 | `app/platforms.dart` 的 `SettingsProxyPolicy`（Q01.1、I01.1）；图片 `app/image_cache.dart` 的 `AppImageCache`（Q02.1） | 平台请求、弹幕、WebDAV、录制走它；封面、头像、表情图 2026-10-08 起也走（Q02.1，照 3.x `plugins/cache_manager.dart:6`：每个新连接读应用代理，320 个、30 分钟），本机回环测试过，K90 上开着代理看 Twitch 封面由 Q02.1 验证 |
| F-NET-02 | 播放代理（独立的一组设置，播放走它，关掉时直连；录制的中继走应用代理，`common/global/initialized.dart:94`） | `player/core/playback_proxy_policy.dart:6`、`modules/settings/pages/network_proxy_settings_page.dart:16` | 是 | 没验证 | O03.2 c5：`app/platforms.dart:35` 的 `PlaybackProxyPolicy`（`enableProxy`、`proxyHost`、`proxyPort` 照 3.x 管播放），`app/bootstrap.dart:233` 交给 `MediaOpener`（直播间、多画面、小窗共用）；录制仍走应用代理；测试 `test/platforms_test.dart` | 2026-10-02 O03.2 合并；媒体请求真的走代理要在真机上看 → S02.4（CHECKLIST 5 第 6 条；原 Q04.1 的验证并入） |
| F-NET-03 | 断网预检、移动数据提示 | `common/base/base_controller.dart:19` | 是 | 部分 | `app/network.dart`（O03.1） | 只有热门在下拉刷新前检查（`features/popular/popular_catalog.dart:57`、`shared/rooms/room_feed.dart:427`）；分区、分区房间、第一次加载和加载更多不查，3.x 都查（`common/base/live_directory_controller.dart:167` 等）→ I03.2（2026-10-07 核对） |
| F-NET-04 | Twitch 网页完整性令牌（无界面浏览器） | `core/utils/twitch/twitch_web_integrity.dart:9` | 是 | 没验证 | `platform/twitch_webview_http.dart`（UPGRADES X-1） | → S02.4（CHECKLIST 5 第 7 条） |

## 4 推荐和分区（BRW）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-BRW-01 | 推荐页按平台浏览（平台来自“平台显示”，首选平台） | `modules/popular/popular_page.dart:7` | 是 | 完成 | `features/popular/`（I02.1、A09.2） | |
| F-BRW-02 | 各平台的翻页方式、按人数排序 | `modules/popular/popular_grid_controller.dart:35`、`modules/popular/popular_controller.dart:50` | 是 | 完成 | `shared/rooms/room_feed.dart` | |
| F-BRW-03 | 下拉刷新、滚动加载、回到顶部 | `common/base/base_controller.dart`、`common/services/settings/page_settings_controller.dart:8` | 是 | 完成 | I02.1 | 桌面页码栏手机上不出现（同 v3） |
| F-BRW-04 | 分区页：分类标签、分区网格、借图 | `modules/areas/areas_page.dart:8`、`plugins/area_pic_mapper.dart:8` | 是 | 完成 | `features/areas/`（I03.1、A09.4） | |
| F-BRW-05 | 分区房间 | `modules/area_rooms/area_rooms_page.dart:9` | 是 | 完成 | `features/area_rooms/`（I03.1、A09.5） | |
| F-BRW-06 | 关注分区（分区房间页的按钮、关注的分区页） | `modules/area_rooms/area_rooms_page.dart:104`、`modules/areas/favorite_areas_page.dart:8` | 是 | 完成 | I03.1、A09.6 | |
| F-BRW-07 | 平台显示（开关、排序、首选平台） | `modules/hot_areas/hot_areas_page.dart:5`、`common/services/settings/favorite_room_controller.dart:20,24` | 是 | 完成 | `features/hot_areas/` | |
| F-BRW-08 | 网络电视频道在分区页直接播放；CC 官方入口用浏览器打开 | `routes/app_navigation.dart:18,23` | 是 | 完成 | `routes/app_navigator.dart` | |
| F-BRW-09 | 人数口径（热度或在线，按平台选） | `common/services/settings/app_settings_controller.dart:54`、`modules/settings/pages/audience_metric_settings_page.dart:4` | 是 | 完成 | `shared/rooms/room_cards.dart` 的 `AudiencePolicy` | |

## 5 房间卡片（CARD）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-CARD-01 | 点卡片进直播间 | `common/widgets/room_card.dart:121` | 是 | 完成 | `shared/rooms/room_grid.dart`、`live_ui` 的 `LiveRoomCard`（A09.1） | |
| F-CARD-02 | 长按菜单：房间信息、关注、取消关注（先确认） | `common/widgets/room_card.dart:177`、`:1232` | 是 | 完成 | `shared/rooms/room_menu.dart`（I01.2、A09.1） | |
| F-CARD-03 | 设置标签（未关注先问关注、就地新建标签） | `common/widgets/room_card.dart:234` | 是 | 完成 | `shared/rooms/room_tags_dialog.dart` | |
| F-CARD-04 | 分享（系统分享面板，内容是 3.x 格式的口令） | `common/utils/share_command_handler.dart:18` | 是 | 完成 | `shared/rooms/share_code.dart`、share_plus（O03.1） | K90 第二轮看过分享面板 |
| F-CARD-05 | 卡片外观（手机和桌面各一份、预设、显示内容） | `common/services/settings/room_card_settings_controller.dart:25`、`modules/settings/pages/room_card_settings_page.dart:5` | 是 | 完成 | J01.1、A11.2 | |

## 6 关注（FAV）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-FAV-01 | 已开播、录播、未开播三组；平台栏；标签筛选 | `modules/favorite/favorite_page.dart:9`、`modules/favorite/favorite_controller.dart:20` | 是 | 完成 | `features/favorite/`（I04.1、A09.3） | K90 第一轮看过 |
| F-FAV-02 | 启动核验关注（“正在核验”“状态待确认”），启动页最多等 350 毫秒 | `modules/favorite/favorite_startup_policy.dart:10` | 是 | 完成 | `app/startup.dart`（I01.2） | |
| F-FAV-03 | 下拉、刷新按钮、再点“关注”刷新 | `modules/favorite/favorite_controller.dart` | 是 | 完成 | I04.1 | |
| F-FAV-04 | 定时刷新关注 | `modules/favorite/favorite_controller.dart:162` | 是 | 完成 | I04.1 | |
| F-FAV-05 | 回到前台刷新关注 | `modules/favorite/favorite_controller.dart:131` | 是 | 完成 | I04.1 | |
| F-FAV-06 | 刷新并发上限、单个 10 秒超时、失败冷却 | `modules/favorite/favorite_controller.dart:772` | 是 | 完成 | `features/favorite/` 的刷新器 | |
| F-FAV-07 | 紧凑关注卡片 | `modules/favorite/room_grid_view.dart:33` | 是 | 完成 | `Settings.enableDenseFavorites` 有读取 | |
| F-FAV-08 | 按主播关注的身份迁移（niconico、YouTube、抖音） | 3.x 没有（v4 迁移 3.x 旧关注） | 是 | 完成 | `app/platforms.dart`、`IdentityMigration`（J02.1、I01.1） | 联网解析没在真机跑过：要有 3.x 的旧关注，覆盖安装时看 → J06.1、S04.1 |

## 7 搜索（SRC）和观看历史（HIS）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-SRC-01 | “全部”和单个平台搜索、并发、翻页 | `modules/search/search_controller.dart:17` | 是 | 完成 | `features/search/`（I05.1、S02.1；界面 A09.7） | K90 第一轮看过国内平台 |
| F-SRC-02 | 包含未开播、四种排序 | `modules/search/search_ranking.dart:5` | 是 | 完成 | I05.1 | |
| F-SRC-03 | 部分平台失败的提示、继续网页搜索 | `modules/search/search_controller.dart` | 是 | 完成 | S02.1 改为温和提示和“搜索范围” | |
| F-SRC-04 | 网页搜索（应用内浏览器，认出直播间后问是否进入） | `modules/search/web_search_controller.dart:19` | 是 | 没验证 | `shared/in_app_web.dart`（O03.1，flutter_inappwebview 预发布版） | → S02.6 |
| F-SRC-05 | 搜索结果的卡片菜单 | `common/widgets/room_card.dart:177` | 是 | 完成 | 同 F-CARD-02 | |
| F-HIS-01 | 进房成功后记观看历史 | `modules/live_play/controllers/live_play_controller.dart:752` | 是 | 完成 | C01.1 | |
| F-HIS-02 | 历史列表、条数上限、清空、删除、刷新状态 | `modules/history/history_page.dart:7`、`common/services/settings/history_controller.dart:52` | 是 | 完成 | `features/history/`（I06.1；界面 A09.9） |  |

## 8 直播间

### 8.1 播放和画面（ROOM）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-ROOM-01 | 进房取详情、合并卡片信息、更新关注快照 | `modules/live_play/controllers/live_play_controller.dart:249`、`:753` | 是 | 完成 | `features/live_play/logic/room_controller.dart`（C01.1） | K90 第一轮 7 个国内平台能播 |
| F-ROOM-02 | 默认清晰度（WLAN、移动数据各一个偏好） | `modules/live_play/controllers/player_controller.dart:594`、`:613` | 是 | 完成 | `shared/rooms/play_quality.dart`、`app/network.dart`（O03.1） | |
| F-ROOM-03 | 切换清晰度和线路（不重建播放器，旧流继续播） | `player_controller.dart:686`、`modules/live_play/widgets/resolution_selector/line_selector.dart:5` | 是 | 完成 | C01.1、A07.6 | |
| F-ROOM-04 | 播放失败浮层、重试、自动恢复（刷新地址、换线、软解、延迟重试） | `modules/live_play/widgets/video_player/playback_failure_overlay.dart:5`、`player/core/player_manager.dart:213` | 是 | 完成 | `packages/live_player` 的 `PlaybackSession`（G02.1）、A07.7 | 高通 HEVC 硬解失败后软解回退已有（G02.1），真机评估 → G01.2 |
| F-ROOM-05 | 未开播、封禁、轮播的占位和刷新 | `modules/live_play/widgets/placeholder/not_living_video_widget.dart:9` | 是 | 完成 | A07.7；v4 另外每 60 秒刷新、开播自动播放 | |
| F-ROOM-06 | 刷新直播间 | `modules/live_play/widgets/video_player/video_controller.dart:1269` | 是 | 完成 | C01.1 | |
| F-ROOM-07 | 全屏、横屏、转向规则、默认全屏 | `video_controller.dart:1323`、`:1388`、`:626` | 是 | 完成 | A07.4 | K90 第二轮看过全屏 |
| F-ROOM-08 | 单击显示/隐藏控制层、双击全屏 | `video_controller.dart:936` | 是 | 完成 | specs/UI.md 附录 A 第 1、3 条有测试 | |
| F-ROOM-09 | 左侧上下滑调亮度、右侧调音量 | `video_controller.dart:854` | 是 | 完成 | `features/live_play/player/player_gestures.dart`（C01.2） | K90 第二轮看过音量手势 |
| F-ROOM-10 | 锁定 | `modules/live_play/widgets/video_player/video_controller_panel.dart:247` | 是 | 完成 | A07.4 | |
| F-ROOM-11 | 全屏顶栏的时间和电量 | `video_controller_panel.dart:33`、`video_controller.dart:761` | 是 | 完成 | `features/live_play/logic/device_battery.dart`（A07.4） | |
| F-ROOM-12 | 画面比例 | `video_controller.dart:1518` | 是 | 完成 | `features/live_play/dialogs/player_dialogs.dart` | |
| F-ROOM-13 | 屏幕常亮（可关） | `modules/live_play/controllers/live_play_controller.dart:177` | 是 | 没验证 | O05.1：`packages/live_player/lib/src/screen_wake.dart:9` 的 `ScreenWake`（全应用一个计数）、`video_view.dart` 的 `keepScreenOn`（只在播放或缓冲时常亮）；直播间 `player_view.dart:503-516`、应用内小窗 `floating_window.dart:187` 读 `enableScreenKeepOn`，改了立即生效；测试 `live_player` 2 个、直播间 1 个 | 2026-10-02 O05.1（提交 `b8462638a`）合并；记录写明“没验证”（唤醒锁靠系统服务），K90 上没看 → S02.6。和 3.x 的差别：暂停时不常亮（同 media_kit 原来的行为） |
| F-ROOM-14 | 默认音量、全局静音、进房不改设备音量 | `common/services/settings/volume_settings_controller.dart:8` | 是 | 完成 | C01.1 | |
| F-ROOM-15 | 房间音量（对话框、按房间记住） | `modules/live_play/dialogs/room_volume_dialog.dart:7`、`player/core/live_room_volume_manager.dart:7` | 是 | 完成 | `features/live_play/dialogs/room_dialogs.dart` | 3.x 键名照旧 |
| F-ROOM-16 | 关注按钮（取消前确认） | `modules/live_play/widgets/button/favorite_floating_button.dart:7` | 是 | 完成 | `features/live_play/buttons/follow_button.dart` | |
| F-ROOM-17 | 人数显示 | `modules/live_play/widgets/resolution_selector/audience_info.dart:4` | 是 | 完成 | 在线、热度、累计分开（C01.1） | |
| F-ROOM-18 | 标题栏信息、直播间详情（公告、简介） | `modules/live_play/widgets/layout/live_play_header.dart:8` | 是 | 完成 | A07.1 | |
| F-ROOM-19 | 纯音频模式 | `video_controller.dart:1246` | 是 | 完成 | C01.2 | |
| F-ROOM-20 | 自动助眠（进房即纯音频并定时） | `live_play_controller.dart:118` | 是 | 完成 | C01.2 | 通知权限见 F-AND-03 |
| F-ROOM-21 | “退出时销毁播放器”（关时复用播放器给下一个房间） | `common/services/settings/player_settings_controller.dart:52` | 是 | 完成 | C02.1 c1：`features/live_play/logic/player_standby.dart:15` 的 `PlayerStandby`；`live_play_page.dart:491` 读 `useHardStopOnExit`（关：会话停完放进来，45 秒内下一个房间配置一样就复用；开：立即释放）；测试 `room_extras_test.dart` | 2026-10-02 C02.1（提交 `7b37e6f5f`），默认照 3.x（关） |
| F-ROOM-22 | 抖音竖屏流的画面比例预判（避免起播时跳） | `player/core/live_stream_geometry_hint.dart:8` | 是 | 完成 | G04.1：`packages/live_core` 的 `LivePlayLine.width`/`height`/`declaredAspectRatio`、`DouyinApi.pictureSize`；`packages/live_player` 的 `PlaybackState.expectedAspectRatio`；直播间竖屏判断、小窗、画中画都用预判 | 2026-10-02 G04.1（提交 `7b37e6f5f`），只有抖音（照 3.x） |
| F-ROOM-23 | 硬解、兼容模式、自定义输出（vo、ao、hwdec） | `common/services/settings/player_settings_controller.dart:39`、`modules/settings/pages/player_kernel_settings_page.dart:16` | 是 | 完成 | `MpvEngineConfig`（C01.1） | |
| F-ROOM-24 | 播放内核切换（fvp、exo、ijk） | `player_settings_controller.dart:34` | 否 | 不做 | v4 只用 mpv（PLAN 第 4 节） | |
| F-ROOM-25 | 键盘快捷键（空格、方向键、R、F、Esc、媒体键） | `modules/live_play/widgets/keyboard/video_keyboard.dart:56` | 部分（外接键盘） | 完成 | C01.1、C01.2 有空格、方向键、R、F、Esc；C02.1 c6 加媒体键：`live_play_page.dart:750-752`（播放、暂停、播放/暂停）；测试 `room_extras_test.dart` | 2026-10-02 C02.1；Android 上耳机按键走媒体通知 |

### 8.2 直播间菜单和工具（RT）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-RT-01 | 投屏（DLNA） | `modules/live_play/dialogs/live_dlna_dialog.dart:6`、`common/utils/live_url_tool.dart:405` | 是 | 没验证 | `packages/live_cast`（N02.1）、`features/live_play/dialogs/stream_dialogs.dart` | 没对真电视试过 → S02.6 |
| F-RT-02 | 获取直链（选清晰度、线路、复制） | `common/utils/live_url_tool.dart:388`、`modules/live_play/dialogs/known_room_link_dialog.dart:10` | 是 | 完成 | `stream_dialogs.dart`（C01.2） | |
| F-RT-03 | 分享直播间 | `modules/live_play/widgets/button/live_play_menu_button.dart:8` | 是 | 完成 | `features/live_play/buttons/room_menu_button.dart` | |
| F-RT-04 | 在平台 App 或浏览器打开（哔哩哔哩、斗鱼、抖音、虎牙、CC 有 App 跳转） | `modules/live_play/services/room_external_opener.dart:33` | 是 | 完成 | `room_menu_button.dart:30` | |
| F-RT-05 | 快手 App 跳转（按 `liveStreamId`） | `room_external_opener.dart:193` | 是 | 完成 | C03.1 c1：`features/live_play/buttons/room_menu_button.dart:55-66`（`kuaishouStreamId` 先看详情的 `KuaishouRoomData`，再看弹幕参数；`kuaishouAppLink` 照 3.x），没开播只开网页；测试 `room_extras_test.dart` | 2026-10-02 C03.1（提交 `7b37e6f5f`）；打开 App 的方式和 F-RT-04 相同 |
| F-RT-06 | 切换直播间（已开播的关注、关注的回放、历史） | `modules/live_play/dialogs/play_other.dart:11` | 是 | 完成 | `features/live_play/switch_room/room_switch_panel.dart`（A07.13 换成各布局同一个面板） |  |
| F-RT-07 | 切换直播间里的刷新按钮（刷新关注） | `modules/live_play/dialogs/play_other.dart:119` | 是 | 完成 | C03.1 c2 加刷新，A07.13 搬进新面板：`switch_room/room_switch_panel.dart:22` 的 `FollowsRefresher`、`:409` 的 `_RefreshButton`（刷新中转圈、不能再点，失败提示可重试）；`app/app.dart:86` 接上关注的 `refreshAll(visible: false)` | 2026-10-02 C03.1、A07.13（A07.13 待真机） |
| F-RT-08 | 直播间定时关闭 | `modules/live_play/dialogs/room_timer_dialog.dart:6` | 是 | 完成 | `room_dialogs.dart`（C01.2） | |
| F-RT-09 | 录制按钮和录制选项 | `modules/live_play/widgets/button/record_action_button.dart:11` | 是 | 完成 | `features/live_play/record/record_panel.dart`（A07.6） | |
| F-RT-10 | 网络电视节目单、回看、返回直播 | `modules/live_play/widgets/video_player/iptv_schedule_dialog.dart:10`、`iptv_programme_policy.dart:7` | 是 | 完成 | `features/live_play/dialogs/iptv_guide.dart`（C01.2） | |
| F-RT-11 | 网络电视播放带自定义 UA 和频道请求头 | `player/core/playback_header_resolver.dart:144` | 是 | 完成 | `room_controller.dart` 的 `iptvPlayHeaders` | |

### 8.3 竖屏直播（PORT）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-PORT-01 | 竖屏流自适应高度和布局模式 | `modules/live_play/widgets/content_first_panel_layout.dart:16`、`player/core/portrait_stream_support.dart:33` | 是 | 完成 | A07.2 | |
| F-PORT-02 | 竖屏全屏（三档面板、上滑退出）和显示模式 | `modules/live_play/widgets/layout/portrait_fullscreen_interaction.dart:47`、`video_controller.dart:1417` | 是 | 完成 | A07.2 | |
| F-PORT-03 | 方向选择、按房间记住 | `modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart:5` | 是 | 完成 | `features/live_play/logic/room_orientation.dart` | |
| F-PORT-04 | 竖屏时的弹幕模式 | `modules/settings/pages/portrait_live_settings_page.dart:6` | 是 | 完成 | C01.2 | |
| F-PORT-05 | 小窗跟随竖屏源的比例 | `modules/settings/pages/portrait_live_settings_page.dart:6` | 是 | 完成 | C02.1 c2：`features/live_play/logic/mini_window.dart:83` 的 `miniPictureSize`（开：按真实比例，第一帧前用 G04.1 的预判；关：竖屏固定 9:16）；用在应用内小窗、画中画、自动画中画 | 2026-10-02 C02.1 |
| F-PORT-06 | 竖屏诊断信息 | `modules/settings/pages/portrait_live_settings_page.dart:154` | 是 | 完成 | C02.1 c3：`features/live_play/player/portrait_diagnostics.dart:14` 的 `PortraitDiagnosticsBadge`（宽×高、比例、方向、手动覆盖、依据），`player_view.dart` 读 `showPortraitDiagnostics` | 2026-10-02 C02.1；3.x 的置信度、稳定次数、时间 v4 没有，不显示 |

### 8.4 小窗和后台（MINI）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-MINI-01 | 后台播放（离开应用 1.5 秒后暂停；开关打开时继续，持有唤醒锁和 Wi-Fi 锁） | `player/core/playback_lifecycle_coordinator.dart:25`、`player/core/background_playback_policy.dart:11` | 是 | 完成 | `features/live_play/logic/background_playback.dart`（C01.2） | 2026-10-02 K90：直播间里按 Home，媒体会话 PLAYING，后台继续播放，通过（S02.2 记录） |
| F-MINI-02 | 离开直播间时应用内悬浮小窗 | `player/core/player_manager.dart:2970` | 是 | 完成 | `features/live_play/mini/floating_window.dart`、`logic/room_runtime.dart`（A07.8） | |
| F-MINI-03 | 小窗弹幕（13 项设置） | `modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:6`、`modules/settings/pages/pip_danmaku_settings_page.dart:12` | 是 | 完成 | `features/live_play/mini/compact_danmaku.dart`（A07.8） | |
| F-MINI-04 | 小窗弹幕设置的实时预览 | `modules/settings/pages/pip_danmaku_settings_page.dart:31` | 是 | 完成 | `features/settings/playback_tiles.dart` 的 `PipDanmakuPreviewBinding`、`packages/live_ui` 的 `PipDanmakuPreview`（A11.3） | 清点时 A11.3 还没合并，C02.1 核对后改 |
| F-MINI-05 | 音频焦点：来电、别的应用要独占声音时暂停，结束后继续；提示音时压低到 20%；拔耳机、蓝牙断开时暂停 | `player/core/live_audio_handler.dart:98`（`audio_session`，`:103` 中断、`:163` 拔耳机） | 是 | 没验证 | G05.1 第 1、2 阶段：`features/live_play/logic/audio_focus.dart` 的 `RoomAudioFocus`（`audio_session`，开播时拿焦点、离开直播间释放；来电暂停、结束只恢复自己暂停的；压低到 20%；别的应用永久拿走焦点时暂停不恢复；拔耳机暂停），接在 `RoomRuntime`（Android）；测试 `audio_focus_test.dart`。多画面没做 | 2026-10-07 docs v2 G 组核对补登；2026-10-08 G05.1 合并，来电、导航播报、拔耳机要在 K90 上看 → G05.1 |

## 9 弹幕（DM）和本地互动（LOC）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-DM-01 | 弹幕连接、状态行、断线重连 | `modules/live_play/controllers/danmaku_controller.dart:19` | 是 | 完成 | `packages/live_danmaku`（D01） | K90 第一轮 5 个国内平台有弹幕 |
| F-DM-02 | 飞行弹幕（显示开关、画面上显示） | `modules/live_play/widgets/video_player/video_controller.dart:179` | 是 | 完成 | `shared/danmaku/danmaku_overlay.dart` | |
| F-DM-03 | 区域、上下留白、透明度、速度、字号、粗细、描边 | `modules/live_play/pages/danmaku_settings_page.dart:9` | 是 | 完成 | `shared/danmaku/danmaku_settings.dart`（A07.6） | |
| F-DM-04 | 弹幕帧率（跟随屏幕或固定） | `video_controller.dart:90` | 是 | 完成 | D05.1 c1：直播间把 `resolvedDanmakuFps`（`player_view.dart:475`）传给弹幕层，弹幕层按刷新率的整数分之一画（`shared/danmaku/danmaku_overlay.dart:130` 的 `danmakuFrameDivisor`）；测试 `live_play_page_test.dart` | 2026-10-02 D05.1（提交 `b8462638a`）。多画面没传帧率，见 F-MV-05 |
| F-DM-05 | 弹幕字体 | `video_controller.dart:91` | 是 | 完成 | D05.1 c2：`shared/danmaku/danmaku_settings.dart:25`（`danmakuLookOf` 读 `danmakuFontFamilyName`，`Default` 用系统字体）；字体由 I01.3 注册 | 2026-10-02 D05.1 |
| F-DM-06 | 纯文字模式（不显示表情） | `video_controller.dart:76` | 是 | 完成 | D05.1 c3：`danmaku_settings.dart:26`（`textOnly` 读 `noEmojiMode`），开时跳过表情，只剩表情的弹幕不飞 | 2026-10-02 D05.1 |
| F-DM-07 | 观看模板（预设、保存、恢复） | `modules/live_play/widgets/danmaku/danmaku_viewing_preset.dart:3` | 是 | 完成 | `danmaku_templates.dart`（C01.2、A07.6） | 3.x 存的模板照旧可用 |
| F-DM-08 | 合并重复、相似过滤 | `modules/live_play/controllers/repeated_danmaku_filter.dart:11`、`danmaku_similarity_filter.dart:9` | 是 | 完成 | `packages/live_danmaku` 的 `DanmakuMessageFilter` | |
| F-DM-09 | 屏蔽关键词、屏蔽用户（直播间和设置页） | `modules/live_play/pages/keyword_block_page.dart:6`、`modules/shield/danmu_shield_page.dart:6` | 是 | 完成 | `shared/danmaku/block_manager.dart`、`features/shield/`（I07.1、A08.1） | |
| F-DM-10 | 斗鱼疑似机器弹幕过滤 | `core/danmaku/douyu_danmaku.dart:15` | 是 | 完成 | `app/platforms.dart:184` | |
| F-DM-11 | 弹幕列表（跟随到底、新消息提示） | `modules/live_play/widgets/danmaku/danmaku_list_view.dart:41` | 是 | 完成 | `features/live_play/danmaku/chat_list.dart`（A08.1） | |
| F-DM-12 | 弹幕列表长按：复制、屏蔽此用户、屏蔽关键词 | `modules/live_play/widgets/danmaku/danmaku_message_actions.dart:6`、`:48` | 是 | 完成 | `chat_list.dart:521`（A07.6） | |
| F-DM-13 | 画面上的弹幕点按、长按（同上三项） | `video_controller.dart:132` | 是 | 完成 | A08.4：`shared/danmaku/danmaku_overlay.dart:292` 的 `messageAt`（命中检测），`player_view.dart` 按 `enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction` 接点按、长按，弹出和列表长按同样的三项 | 2026-10-02 A08.4（提交 `b8462638a`） |
| F-DM-14 | 醒目留言（进房拉取、到时移除） | `modules/live_play/pages/super_chat_page.dart:5` | 是 | 完成 | `features/live_play/danmaku/super_chats.dart` | |
| F-DM-15 | 聊天列表里的表情图片 | `plugins/emoji_manager.dart:7` | 是 | 完成 | `shared/danmaku/emotes.dart`（S02.1） | |
| F-DM-16 | 飞行弹幕里的表情图片 | `core/emoji/models/unified_emoji_model.dart:4` | 是 | 完成 | D03.2、D05.1 c3：飞行弹幕画表情图（`danmaku_overlay.dart:73`，1.3 × 字号），表情表来自 `shared/danmaku/emotes.dart` | 2026-10-02 D03.2（提交 `cd42f89b1`）；K90 冒烟看到飞行弹幕带表情图（S02.2 记录） |
| F-DM-17 | 播放器上的弹幕设置按钮（全屏也能调） | `video_controller_panel.dart:1843` | 是 | 完成 | A07.6 | |
| F-LOC-01 | 本地弹幕输入（列表下、全屏） | `modules/live_play/widgets/local_interaction/local_interaction_controller.dart:3` | 是 | 完成 | `features/live_play/local_interaction/`（A08.2） | |
| F-LOC-02 | 本地礼物特效、体验币、等级、本地弹幕样式 | `modules/live_play/pages/live_play_page.dart:28`、`local_interaction/local_danmaku_style_editor.dart` | 是 | 完成 | A08.2 | |
| F-LOC-03 | 本地互动设置页 | `modules/settings/pages/local_interaction_settings_page.dart:5` | 是 | 完成 | 设置总览入口已接（提交 `0eb94e4b1`） | |

## 10 多画面（MV）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-MV-01 | 四种布局、一大多小加格（手机最多 4 格） | `modules/multiview/multiview_controller.dart:49` | 是 | 完成 | `features/multiview/`（N01.1、A13.2） | |
| F-MV-02 | 声音焦点、全部静音、每格音量 | `multiview_controller.dart:649` | 是 | 完成 | N01.1 | |
| F-MV-03 | 每格清晰度、线路、小格省流 | `multiview_controller.dart:414` | 是 | 完成 | N01.1 | |
| F-MV-04 | 选台（关注、历史、搜索） | `modules/multiview/widgets/multiview_room_picker.dart:31` | 是 | 完成 | N01.1、A13.2 | |
| F-MV-05 | 多画面弹幕 | `modules/multiview/danmaku/multiview_danmaku_session.dart:26` | 是 | 部分 | N01.1；字体、纯文字跟设置（`multiview_page.dart:873` 用 `danmakuLookOf`） | 弹幕帧率没传给多画面的弹幕层（`multiview_page.dart:878` 的 `DanmakuOverlay` 没有 `fps`，每个刷新周期都画；3.x `modules/multiview/multiview_page.dart:1306` 按 `danmakuFps`、`danmakuAutoFps`）→ N01.2 |
| F-MV-06 | 4 路同时解码、沉浸、全屏和返回 | `modules/multiview/multiview_page.dart:36` | 是 | 没验证 | N01.1 留给真机 | N01.1 留给真机 → S02.6 |

## 11 录制（REC）

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-REC-01 | 添加录制（立即录、等开播）、停止、删除 | `recorder/pages/recorder/recorder_controller.dart:693` | 是 | 完成 | `packages/live_record`（H01.1）、`features/live_play/record/record_panel.dart` | |
| F-REC-02 | 录制中心（状态筛选、任务卡片、操作） | `recorder/pages/recorder/recorder_page.dart:12` | 是 | 完成 | `features/recorder/`（H02.1、A10.1） | |
| F-REC-03 | FFmpeg 录制、分段、合并成 MP4 | `recorder/services/ffmpeg_service.dart:51`、`recorder/services/video_processor_service.dart:14` | 是 | 完成 | H01.1、H02.1 | 2026-10-02 K90：录一场过 5 分钟，两段合成一个 MP4（339.7 秒，H.264 720p + AAC），分段文件清掉，通过（S02.3 记录） |
| F-REC-04 | 断线重连、重试、退避、开播轮询检测 | `recorder/services/recorder_continuation_policy.dart:1`、`recorder_controller.dart:87` | 是 | 完成 | H01.1 | |
| F-REC-05 | 启动时恢复任务 | `common/global/initial_services.dart:85` | 是 | 完成 | `app/recording.dart` | |
| F-REC-06 | 前台服务、通知、唤醒锁；划掉应用后继续录 | `android/.../RecorderForegroundService.kt:20`、`android/.../RecorderBackgroundPlugin.kt:21` | 是 | 没验证 | `RecorderForegroundService.kt`（H02.1、H01.2） | HyperOS 可能划掉即杀；K90 上划掉没成功（S02.3 记录）→ H01.4 |
| F-REC-07 | 存储权限（Android 11 起“所有文件访问”） | `recorder/pages/recorder/recorder_controller.dart:665` | 是 | 没验证 | `RecorderPlugin.requestStorage`（H02.1） | → H01.4 |
| F-REC-08 | 录制目录、缓存上限清理 | `recorder/services/cache_service.dart:19`、`recorder/consts/recorder_config.dart:135` | 是 | 完成 | `packages/live_record` 的 `RecordStorage` | |
| F-REC-09 | 录制设置（清晰度、分段、超时、并发、拼音目录等 19 项） | `recorder/pages/record_settings/record_settings_page.dart:10` | 是 | 完成 | `features/record_settings/`（H01.2；界面 A10.2） |  |
| F-REC-10 | 同时录制弹幕（XML） | `recorder/services/recording_danmaku_service.dart:11` | 是 | 没验证 | `packages/live_record` 的 `chat.dart`（H01.2） | → H01.4 |
| F-REC-11 | HLS 预取和保留窗口（减少漏段） | `recorder/services/hls_relay_prefetch.dart:182` | 是 | 没验证 | `packages/live_media` 的 `HlsMediaWindow`（H01.2） | 效果没在真机量 → H01.4 |
| F-REC-12 | 打开录制文件夹 | `recorder/pages/recorder/recorder_controller.dart:1599` | 是 | 完成 | H01.2（应用专属目录改为复制路径） | |
| F-REC-13 | 合并进度（v3 只发进度事件，界面没接） | `recorder/services/video_processor_service.dart:26` | 是 | 完成 | H01.3：`packages/live_record/lib/src/merge.dart:67-78`（`merge(onProgress:)` 听 FFmpeg 统计，`mergeProgress` 照 3.x 的公式）；`shared/record/record_status_card.dart:414-425`（“正在整理文件”显示百分比和进度条，录制面板和录制中心同一张卡）；测试 `merge_progress_test.dart` | 2026-10-02 H01.3（提交 `d145aa930`）；FFmpeg 统计在录制计时里已在 K90 上用过（S02.2 记录），合并时的显示没在真机看 → H01.4 的真机步骤。录制通知里不显示进度 → H05.3 |

## 12 网络电视、账号、备份、工具、标签

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-IPTV-01 | 导入播放列表（网络、本地文件） | `core/iptv/services/iptv_import_manager.dart:24`、`modules/iptv/iptv_page.dart:13` | 是 | 完成 | `features/iptv/`（L01.3、A13.1）；本地文件用系统选择器（O03.1） | |
| F-IPTV-02 | 导入节目单（网络、本地、默认节目单） | `core/iptv/services/epg_import_manager.dart:19`、`core/iptv/services/auto_sync_scheduler.dart:56` | 是 | 完成 | L01.3 | |
| F-IPTV-03 | 自动同步（按间隔）、手动同步 | `core/iptv/services/auto_sync_scheduler.dart:12` | 是 | 完成 | 启动 3 秒后自动同步（I01.1） | |
| F-IPTV-04 | 订阅源管理（删除、打开文件、切换节目单） | `modules/iptv/iptv_manage.dart:15` | 是 | 完成 | L01.3 | |
| F-IPTV-05 | 自定义请求头 | `common/services/settings/iptv_settings_controller.dart:26` | 是 | 完成 | L01.3、C01.2 | |
| F-ACC-01 | 账号列表（各平台状态、退出） | `modules/account/account_page.dart:9` | 是 | 完成 | `features/account/`（K01.1、A12.1） | |
| F-ACC-02 | 哔哩哔哩扫码登录 | `modules/account/bilibili/qr_login_page.dart:8` | 是 | 完成 | K01.1 | |
| F-ACC-03 | 哔哩哔哩网页（短信）登录；退出时清浏览器 Cookie | `modules/account/bilibili/web_login_page.dart:6` | 是 | 没验证 | `features/account/bilibili_web_login.dart`（O03.1） | → S02.6 |
| F-ACC-04 | 虎牙、抖音、快手、YY、Twitch、SOOP 的 Cookie 页 | `modules/account/widgets/account_cookie_editor.dart:34`、`modules/account/huya/huya_cookie_page.dart:5` | 是 | 完成 | K01.1、A12.2 | |
| F-ACC-05 | 斗鱼 Cookie 和 LTP0 续期 | `modules/account/douyu/douyu_cookie_controller.dart:5` | 是 | 完成 | K01.1 | |
| F-ACC-06 | 启动时核验哔哩哔哩登录 | `common/services/settings/bilibili_account_service.dart:13` | 是 | 完成 | `app/startup.dart`（I01.2） | |
| F-ACC-07 | 登录后取流（高画质、受限房间） | `core/site/*`（Cookie 进请求） | 是 | 没验证 | 适配器经 `StoreCookieVault` 读 Cookie | 没用真实登录 Cookie 在真机看过画质 → S02.6 |
| F-ACC-08 | 云账号（Firebase 登录、云端配置） | `modules/auth/auth_controller.dart:8` | 否 | 不做 | 用户已决定（I01.1、A12.3） | |
| F-BAK-01 | 完整备份和恢复（3.x 格式） | `plugins/backup_recovery_service.dart:13`、`modules/backup/backup_page.dart:14` | 是 | 完成 | `features/backup/`（J03.1；界面 A12.4） |  |
| F-BAK-02 | 仅关注备份和恢复 | `plugins/backup_recovery_service.dart:46` | 是 | 完成 | J03.1 | |
| F-BAK-03 | 备份目录 | `plugins/backup_recovery_service.dart:14` | 是 | 没验证 | J03.1 | Android 11 起 `Download/PureLive` 免权限写入没在真机试 → S02.4（CHECKLIST 5 第 1 条） |
| F-BAK-04 | WebDAV（配置、浏览、上传、恢复、删除、帮助） | `modules/web_dav/web_dav_page.dart:12`、`modules/web_dav/web_dav_controller.dart:50` | 是 | 完成 | `features/web_dav/`（J03.1）；J04.1 加 Digest：`features/web_dav/web_dav_auth.dart:18` 的 `parseAuthChallenges`、`:69` 的 `DigestChallenge`、`:127` 的 `digestAuthorization`，按服务器的要求选认证方式；测试 `web_dav_auth_test.dart`（含本机回环的真实 HTTP 栈） | 2026-10-02 J04.1（提交 `c168fdb99`）；坚果云真机 → S02.4（CHECKLIST 5 第 2 条） |
| F-BAK-05 | 设备同步（局域网配对、收发、和 3.x 设备互相发现） | `modules/remote_receiver/remote_sync_service.dart:14`、`:45` | 是 | 没验证 | `features/remote_receiver/`（I08.1、I01.3） | → S02.4（CHECKLIST 5 第 3 条） |
| F-BAK-06 | 扫码（设备同步、同步到电视） | `modules/backup/scan_page.dart:50` | 是 | 没验证 | `shared/qr_scan.dart`（O03.1） | → S02.4（CHECKLIST 5 第 3 条） |
| F-BAK-07 | 同步到电视 | `plugins/backup_recovery_service.dart:123` | 是 | 完成 | `features/backup/tv_sync.dart` | |
| F-TOOL-01 | 工具箱：链接跳转、获取直链 | `modules/toolbox/toolbox_page.dart:7`、`modules/toolbox/toolbox_direct_link_flow.dart:9` | 是 | 完成 | `features/toolbox/`（I08.1） | |
| F-TOOL-02 | 工具箱打开时把剪贴板里的链接填进框 | `modules/toolbox/toolbox_controller.dart:250` | 是 | 完成 | I08.1 | |
| F-TOOL-03 | 关于（版本、许可证、项目主页、声明） | `modules/about/about_page.dart:8` | 是 | 完成 | `features/about/` | |
| F-TOOL-04 | 版本页、历史版本 | `modules/version/version_page.dart:16`、`modules/about/version_history.dart` | 是 | 完成 | `features/version/` | |
| F-TAG-01 | 标签管理（增删改、置顶、排序） | `modules/tags/tag_management_page.dart:9` | 是 | 完成 | `features/tags/`（I07.1） | |

## 13 Windows 专属（以后）

本阶段不做，列出以免以后漏掉。都是“Android：否”。

| 编号 | 功能 | v3 位置 |
|---|---|---|
| F-WIN-01 | 自绘标题栏（拖动时显示尺寸） | `common/global/platform/desktop_manager.dart:263` |
| F-WIN-02 | 窗口大小（立即应用）、位置 | `common/services/settings/window_size_controller.dart:6` |
| F-WIN-03 | 托盘（显示、隐藏、退出） | `common/global/platform/desktop_tray_service.dart:7` |
| F-WIN-04 | 关闭窗口时：询问、最小化到托盘、退出 | `plugins/utils.dart:7` |
| F-WIN-05 | 开机启动（注册表） | `common/global/win_auto_start.dart:8`、`common/services/settings/startup_controller.dart:12` |
| F-WIN-06 | 单实例、在新窗口打开直播间 | `common/utils/windows_multi_instance_launcher.dart:18` |
| F-WIN-07 | 桌面小窗（置顶、记住位置） | `player/utils/window_helper.dart` |
| F-WIN-08 | 窗口内全屏按钮 | `modules/live_play/widgets/video_player/video_controller_panel.dart:1882` |
| F-WIN-09 | 控制栏音量按钮（悬停出滑块、一键静音） | `modules/live_play/widgets/video_player/volume_control.dart:10` |
| F-WIN-10 | Windows 动态刷新率信息 | `modules/settings/pages/general_settings_page.dart:24` |
| F-WIN-11 | RTX 超分 | `common/services/settings/player_settings_controller.dart` |
| F-WIN-12 | Kick 的 WinHTTP 通道 | UPGRADES X-1 |
| F-WIN-13 | 鼠标悬停显示控制层、右键菜单 | `modules/live_play/widgets/layout/control_hover_region.dart` |
| F-WIN-14 | 退出前写盘（`didRequestAppExit`） | `common/global/platform/desktop_manager.dart:765` |

## 14 平台能力表（Android）

v4 的平台层（`packages/live_core`、`packages/live_danmaku`）在各平台任务（E01.1～E03.16）和弹幕任务（D01.2～D01.31）里一个平台一个记录做完，已批准升级的余项在 E06.1 做完平台层、E06.2 接界面，下表只写 Android 上的现状。“K90 看过”指 2026-10-01 两轮真机测试（`~/ref/notes/m13_notes.md` 的 DEVICE TEST）；其余“完成”是样本和探针测过、没在真机播放。海外平台在国内要代理。

图例：完成；无（v3 也没有）；新增（v3 没有、v4 加的）；受阻（UPGRADES 里写明原因）；— 不适用。

| 平台 | 播放 | 清晰度和线路 | 弹幕 | 登录（Cookie） | 搜索 | 分区 | 关注状态 | 备注 |
|---|---|---|---|---|---|---|---|---|
| 哔哩哔哩 | 完成，K90 看过 | 完成 | 完成，K90 看过 | 扫码、网页、Cookie | 直播和未开播、主播 | 完成 | 完成 | 1-1 游客播放轮播：平台层完成（E06.1），直播间接上 → E06.2 |
| 斗鱼 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie、续期 | 直播和未开播、主播 | 完成 | 完成 | C-5 进房补拉超级弹幕受阻（找不到网页接口） |
| 虎牙 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie | 只搜直播中、主播 | 完成 | 完成 | |
| 抖音 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie | 只搜直播中 | 完成（新增游戏分区） | 完成 | 竖屏比例预判完成（G04.1，F-ROOM-22） |
| 快手 | 完成，K90 看过 | 完成 | 完成，K90 看过 | Cookie | 直播和未开播、主播 | 完成 | 完成 | App 跳转完成（C03.1，F-RT-05）；详情标题用卡片标题（A-3，E06.1）；登录后直播搜索 C-17 未排（要登录 Cookie） |
| YY | 完成，K90 看过 | 完成 | 完成 | Cookie | 只搜直播中、主播 | 完成 | 完成 | 6-1 FLV 优先：平台层有开关，应用没打开 → E06.3 |
| 网易 CC | 完成，K90 看过 | 完成 | 无（匿名加入不回应，C-22 要登录 Cookie 后再试，未排） | 只存，未用于请求 | 直播和未开播、主播 | 完成 | 完成 | |
| SOOP | 完成 | 完成 | 完成 | Cookie | 只搜直播中 | 完成 | 完成 | 7-8 密码房输入密码受阻；7-9 分享带 App 深链未排（要先定分享格式） |
| Twitch | 完成（原生 TLS + 浏览器令牌，没验证） | 完成 | 完成 | Cookie | 直播和未开播 | 完成 | 完成 | B-7 Cookie 失效提示：平台层完成（E06.1），直播间提示 → E06.2；8-8 按引擎能力请求编码 → E06.2；播放没在真机看 → S02.4 |
| AcFun | 完成 | 完成 | 新增 | — | 直播和未开播、主播 | 完成 | 完成 | |
| Picarto | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | 11-1 恢复后显示实际画质：平台层完成（E06.1），界面 → E06.2；11-5 搜索卡片简介 → A09.11 |
| TwitCasting | 完成 | 完成 | 新增 | — | 只搜直播中 | 完成 | 完成 | |
| 猫耳 FM | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| 映客 | 完成 | 完成 | 无 | — | 推荐里筛选 | 完成 | 完成 | |
| 克拉克拉 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| 小红书 | 完成 | 完成 | 无 | — | 只能按房间号查 | 无（v3 同） | 只能按场次 | 16-5 按主播关注受阻 |
| niconico | 完成 | 完成 | 新增 | — | 只搜直播中 | 完成 | 完成（按主播） | |
| 微博直播 | 完成 | 完成 | 无 | — | 只能按房间号查 | 完成 | 只能按场次 | 18-10 按主播关注受阻 |
| SHOWROOM | 完成 | 完成 | 新增 | — | 只搜直播中 | 完成 | 完成 | 19-5 付费标注受阻 |
| CHZZK | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| LiveMe | 完成 | 完成 | 受阻（要登录 IM） | — | 直播和未开播 | 无（v3 同） | 完成 | |
| TikTok | 完成（受限房间说明原因） | 完成 | 受阻（要签名） | — | 只能精确查频道 | 受阻（无推荐和分区） | 完成 | |
| YouTube | 完成 | 完成 | 新增 | — | 只搜直播中 | 无（v3 同） | 完成（按频道） | 推荐是“直播”频道页（23-2，E03.10） |
| BIGO LIVE | 完成 | 完成 | 新增 | — | 推荐里筛选 | 完成 | 完成 | |
| PandaTV | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| FC2 LIVE | 完成 | 完成（三档） | 新增 | — | 直播和未开播 | 完成 | 完成 | 探测的控制连接交给播放 → E06.2 |
| Steam 直播 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | 27-3 国内 CDN 受阻 |
| 京东直播 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | 28-7 标题和店铺名受阻；28-3 直播间模糊背景 → A07.16 |
| 酷狗直播 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | B-16 PK 对方聊天：弹幕层完成（E06.1），“对方”标记 → E06.2 |
| 百度直播 | 完成 | 完成 | 新增 | — | 只能按房间号查 | 完成 | 完成 | |
| 六间房 | 完成 | 完成 | 新增 | — | 直播和未开播 | 完成 | 完成 | |
| LOOK 直播 | 完成 | 完成 | 新增 | — | 只能按房间号查 | 完成 | 完成 | |
| 17LIVE | 完成 | 完成 | 新增 | — | 只搜直播中 | 新增 | 完成 | B-14 名字颜色和徽章：弹幕层完成（E06.1），界面 → E06.2 |
| Kick（v3.2.11 已下线） | 新增，只在 Android（原生 HTTP），没验证 → S02.4 | 完成 | 新增 | — | 一页频道 | 完成 | 完成 | |
| 网络电视 | 完成 | 完成 | — | — | 本机频道 | 按播放列表 | — | |

依据：播放、清晰度、线路、分区、关注状态见各平台任务（E01.1～E03.16）的记录；弹幕见 D01.2～D01.31 的记录（登记在 `app/platforms.dart`）；搜索能力见 `features/search/search_capability.dart`；登录平台见 `features/account/`；“受阻”“没做（升级）”见 [specs/UPGRADES.md](../specs/UPGRADES.md)。

## 15 设置项核对

2026-10-03 重新扫了一遍（V03.3），方法：

1. 从 `packages/live_store/lib/src/settings/settings.dart` 取出每个 `static const xxx = …Setting('键', …)`，和 `Settings.all`（`:1413`，直接列 170 个，加上展开的 `recorder` 19 个、`localInteraction` 29 个）对过，一共 **218 个**，都在 `Settings.all` 里；其中 10 个是 `SettingScope.internal`（本机记录，不进备份）。
2. 在 `apps/pure_live/lib` 和 `packages/*/lib`（不含测试）里找 `Settings.<名字>`，看设置页（`features/settings/`）以外有没有读取它的代码。
3. 3.x 的键：从 `v3.2.11` 的 `lib/` 取 `hiveBool/hiveInt/hiveDouble/hiveString/hiveStringList('键', …)`、`RecorderKeys` 和 `HivePrefUtil` 用到的键，和 v4 的键名比。

### 数量

| 分节（`section`） | 个数 | 分节 | 个数 |
|---|---:|---|---:|
| `danmaku` 弹幕 | 42 | `iptv` 网络电视 | 6 |
| `player` 播放 | 29 | `proxy` 代理 | 6 |
| `localInteraction` 本地互动 | 29 | `page` 翻页 | 5 |
| `app` 应用 | 25 | `volume`、`roomCard`、`exit` | 各 4 |
| `recorder` 录制 | 19 | `favorite`、`meta`、`cache`、`log`、`cookie` | 各 2 |
| `theme` 主题、`font` 字体 | 各 9 | `history`、`startup`、`backup` | 各 1 |
| `windowSize` 窗口 | 8 | `refresh` 刷新 | 6 |

- **198 个沿用 3.x 的键名和含义**（D-018）。
- **20 个是 v4 新加的**：`skippedUpdateVersion`（A06.3）、`matchVideoFrameRate`（R02.1）、`showUnplayableInDiscover`（UPGRADES 统一原则，J02.1）、`detectClipboardRooms`（O03.2）、`douyuForceRenew`（UPGRADES 2-1）、`twitchLanguages`（8-3）、`preferH264`（22-3）、`youtubeShowAllChat`（B-13）、`pureBlackTheme`、`themeColorMigration`（A11.2）、`autoPipOnLeave`（A07.8）、`portraitFullscreenSwipeSwitch`（A07.3）、`livePlayChatCollapsed`（A07.5）、`roomSwitcherLayout`（A07.13）、`danmakuListStyle`（A07.1）、`danmakuPausedBehavior`（A07.10）、`enableLocalLog`、`logLevel`（I01.3）、`uiMode`（X03.1）、`tvFocusZoom`（A17.1）。上一版（213 个）之后加了 5 个：`danmakuPausedBehavior`、`detectClipboardRooms`、`matchVideoFrameRate`、`portraitFullscreenSwipeSwitch`、`roomSwitcherLayout`。
- **3.x 有、v4 不作为设置的键 24 个**，都在 `packages/live_store/lib/src/legacy/legacy_snapshot.dart` 里导入到别处或有意丢掉：各平台 Cookie（`bilibiliCookie` 等 8 个 `<平台>Cookie`，加 `douyuLtp0`、`douyuDid`）→ 加密的 `SecretStore`（`:353-366`）；`favoriteRooms`、`favoriteAreas`、`historyRooms`、`shieldList`、`blockedDanmakuUsers`、`webDavConfigs`、`currentWebDavConfig` → 各自的存储（`:414-420` 的 `_consumed`）；`recorder_tasks` → 录制任务（换算画质 id）；`audienceMetricMigration`、`danmakuInteractionMigration`、`siteCatalogMigration`、`enableHighRefreshRate`（换成 `refreshRateMode`）是迁移标记；`cached_area_pics` 是缓存；`record_history` 3.x 只写不读（没有页面），v4 原样留在 `otherValues`。另有 `audioOnly`、`taobaoCookie` 两个旧键 3.x 自己启动时就删掉（`common/global/initial_services.dart:72`、`cookie_settings_controller.dart:42`），v4 导入时同样丢掉（`legacy_snapshot.dart:419`），不算在 24 个里。

### 读取

210 个设置在设置页以外有读取它的代码（行为对不对由各功能点和真机验证判断）；另有 4 个只在设置页的文件里读（见表下）；下表 4 个没人读。上一版这里的 9 行问题（11 个设置：`enableScreenKeepOn`、`useHardStopOnExit`、`portraitPipFollowSource`、`showPortraitDiagnostics`、`proxyPort`、`danmakuFps`、`danmakuAutoFps`、`danmakuFontFamilyName`、`noEmojiMode`、`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction`）现在都有读取：O05.1、C02.1、O03.2、D05.1、A08.4（见对应功能点）。

| 设置（键） | 3.x 的行为 | v4 | 对应功能点 |
|---|---|---|---|
| `videoPlayerKey` | 播放内核 | 只为备份往返保留 | F-ROOM-24（不做） |
| `autoRefreshTime`、`enableRotateScreen`、`m3uDirectory` | 3.x 里也没有读取的代码（只存、只进备份） | 同 3.x | 不是功能 |

另有 4 个只在 `features/settings/` 里读，但读它的就是功能本身，不算问题：`autoRefreshThumbnails`、`thumbnailRefreshInterval`（`data_tools.dart` 的 `CoverRefreshTimer`，`app/startup.dart` 启动时接上，F-APP-20）；`autoShutDownTime`、`enableAutoShutDownTime`（`settings_editors.dart` 的 `AutoExitTimer`，F-APP-21）。

### 默认值（留给 J01.2）

按 3.x 的 `hive*('键', 默认值)` 调用比（括号按层次配对，跨行的调用也算）：218 个里 172 个在 3.x 是 `hive*` 存的，其中 **106 个默认值的字面值和 v4 一样**；2 个写法不同、意思一样（`roomVolumes`、`portraitRoomOverrides`：3.x 存 JSON 字符串 `'{}'`，v4 存映射 `{}`）；**64 个 3.x 写的是常量或表达式**（如 `defaultDanmakuSpeed`、`PlayerConsts.resolutions.first`、`_initialRefreshRateMode()`），要展开再比。另 46 个 3.x 不是用 `hive*` 存的：20 个是 v4 新加的（上面的列表）；19 个录制设置（3.x 经 `HivePrefUtil` 按 `RecorderKeys` 读写，默认值在 `recorder/consts/recorder_config.dart`）；7 个 3.x 用常量键直接读写（`historyLimit`、`room_card_mobile_config`、`room_card_desktop_config`、`autoSyncHoursInterval`、`downloadDirectoryPath`、`downloadDirectoryDecisionMade`、`remote_sync_device_id`）。上一次的初比（172 个里 96 个一样、76 个用常量）用的正则在第一个右括号处截断，把跨行的调用都算成了“常量”，这里改正。逐条核对默认值、取值范围和生效位置是 J01.2 的事。
