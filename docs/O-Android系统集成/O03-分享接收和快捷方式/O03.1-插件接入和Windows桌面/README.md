# O03.1 插件接入和 Windows 桌面外壳

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：接入第三方插件，含 Windows 原生外壳）
- 来源：模块重构计划 M12.3；I01.1、I01.2、I02.1/3/4/7/8/10/11/13/15 记录里“缺的共享服务”“留给后续”（例如分享一直只能复制口令、网络电视只能输入路径导入、直播间不知道是不是移动数据），以及 `~/ref/notes/m13_notes.md`
- 旧编号：M12.3、T13c.1
- 相关：依赖 I01.1（应用骨架）、I01.2（共享模块和外壳接线）；后续 I01.3（应用服务补全：应用内下载更新、和 3.x 的 mDNS 互相发现）、E03.2（Twitch 的 WebView 通道）、O03.2（分享接收）、X01（Windows 客户端）；决定 D-004、D-018；记录 [record.md](record.md)

## 目标

把 3.x 用的 Flutter 插件按 4.x 的结构接进来，让之前留了空接口的功能真正能用：手机上分享走系统面板、文件用系统选择器选、移动数据时提示并用移动数据清晰度、能扫码、网页搜索和哔哩哔哩网页登录在应用里打开、图片磁盘缓存能清和定时刷新；同时给 Windows 做出和 3.x 一样的桌面外壳（自绘标题栏、托盘、关闭询问、开机自启、窗口大小记忆）。插件统一用当时 pub.dev 的最新版，不再维护 3.x 那样的本地补丁副本（只有 flutter_inappwebview 用预发布版，原因见“结果”）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做之前（I01.2 之后） | 现在（`apps/pure_live/lib/` 下） |
|---|---|---|---|
| 分享 | share_plus 打开系统面板（`pubspec.yaml`） | `SystemShare.sheet` 空接口，所有平台都复制口令 | `platform/plugins.dart:38` 接上 share_plus；桌面仍复制口令（同 3.x） |
| 图片缓存 | flutter_cache_manager；`cache_controller.dart` 定时刷新封面 `refreshImageCache(refreshVisible: false)` | 只清内存，定时刷新只存设置 | `ImageCacheTools.clearDisk`（`plugins.dart:39`）；`CoverRefreshTimer`（`app/startup.dart:75`）跟随 `autoRefreshThumbnails`、`thumbnailRefreshInterval` |
| 选文件和目录 | file_picker | 输入路径的对话框、应用内浏览框 `showFileBrowser` | 系统选择器（`pluginOverrides`，`plugins.dart:49-55`）：网络电视导入、备份、录制目录、下载目录；不申请“所有文件访问” |
| 打开本地文件 | `url_launcher`、open_filex | `url_launcher` 打不开应用私有文件 | `AppNavigator.openFile = openLocalFile`（`plugins.dart:40`），Android 用 open_filex 的 FileProvider |
| 网络类型 | connectivity_plus；`base_controller.dart` 断网预检、移动数据提示；`player_controller.dart` `_setDefaultResolution` 按网络选偏好 | 不知道网络类型 | `app/network.dart`（`NetworkKind`、`networkProbeProvider`）；推荐页预检和流量提示；直播间首个清晰度 `room_controller.dart:407-410` |
| 扫码 | mobile_scanner | 只能手输地址 | `shared/qr_scan.dart`（只认二维码、手电筒、相机不可用时说明），设备同步和同步到电视的地址框旁 |
| 内置浏览器 | flutter_inappwebview（git 分支再打补丁） | 网页搜索用系统浏览器，网页登录路由显示 Cookie 页 | `shared/in_app_web.dart`：网页搜索在应用里打开、遇到直播间询问进入；哔哩哔哩网页登录（`kBiliBiliWebLogin`） |
| Windows 外壳 | window_manager、tray_manager；`desktop_manager.dart`、`desktop_tray_service.dart`、`win_auto_start.dart`、`window_size_controller.dart`、`plugins/utils.dart`（关闭询问） | 系统标题栏，没有托盘和自启 | `app/desktop/`：`title_bar.dart`、`tray.dart`、`close_dialog.dart`、`startup_entry.dart`、`desktop_window.dart`（窗口大小和位置） |

## 结果

- 提交：`032ddd863`（插件依赖；分享面板、图片缓存、文件选择）、`fb70b3f43`（网络类型）、`f8baba215`（扫码）、`c0218fb7a`（Windows 外壳）、`765973e90`（内置浏览器的网页搜索和哔哩哔哩网页登录）、`e96a134aa`（在 Android 文件管理器里打开录制目录），记录 `9ded26f50`，合并 `828e14ca9`（2026-10-01）；登记表的 `9ded26f50` 是记录的提交。
- 插件和版本（2026-10-01 的最新）：share_plus 13.3.0、flutter_cache_manager 3.4.5、file_picker 13.1.0、open_filex 4.7.0、connectivity_plus 7.3.1、mobile_scanner 7.4.2、flutter_inappwebview **6.2.0-beta.3**、window_manager 0.5.2、tray_manager 0.7.0、screen_retriever 0.2.2；根 `pubspec.yaml` 加了 `nm: 0.6.0`、`dbus: 0.8.0` 两条覆盖（3.x 也有，只在 Linux 用到）。
- 为什么用 beta：稳定版 6.1.5 的 Android 子包 1.1.3 用 `getDefaultProguardFile('proguard-android.txt')`，AGP 9 直接报错；1.2.0-beta.3 已改好，不需要本地补丁。
- Windows 外壳做到：隐藏系统标题栏、自绘标题栏（图标和“纯粹直播”、拖动区、最小化、最大化/还原、关闭）、最小 400×300、尺寸写回 3.x 的 `window_width`/`window_height`，**位置记忆是新加的**（meta `window.position`，标题栏那一行还在某个显示器上才用）；关闭询问（最小化到托盘 / 退出 + 不再询问，`exitChoose`）；托盘（单击显示、右键菜单）；开机自启写 `HKCU\...\Run\PureLiveV4`（3.x 是 `PureLive`，不读不改），只有 release 构建按设置补写或删除；直播间和多画面全屏让整个窗口全屏。没做：3.x 拖动时显示窗口尺寸的小字、启动页的渐变背景。
- 当时没做、后来由别的任务做完的：和 3.x 设备互相发现（bonsoir 依赖加了，接线没做）→ I01.3（`features/remote_receiver/mdns_peers.dart`）；应用内下载和安装更新包 → I01.3（`features/version/update_download.dart`，安装权限走 O04 的 `pure_live/system_access`）；Twitch 的 WebView 传输 → E03.2（`platform/twitch_webview_http.dart`，提交 `43688c03b`）。
- 测试：新增 `apps/pure_live/test/plugins_test.dart` 8 个；`live_play_controller_test.dart` +1（移动数据时首个清晰度用移动数据偏好）；`recorder_page_test.dart` +1（系统选择器选的目录直接保存）。当时应用 194 个测试，193 个通过（失败的 1 个是分支基线的旧问题，master 已修）；`flutter analyze` 无问题；`flutter build apk --debug` 通过，包里有 `CAMERA` 权限（mobile_scanner，`required=false`）。

## 验证

- 自动测试：`cd apps/pure_live && flutter test test/plugins_test.dart`（图片缓存、定时刷新封面、网络类型、断网预检和移动数据提示、扫码按钮、窗口位置和自启项、标题栏、内置浏览器）。
- 真机（Android）：当时没装到手机。之后的 K90 验证用到了一部分：S02.2、S02.3 看过分享面板（卡片菜单分享）、移动数据清晰度（CHECKLIST 第 1 节第 1 条，“移动数据下进”没单独记结果）、扫码登录（K01）。没看过的：文档选择器选备份和播放列表（S02.4）、open_filex 打开文件、扫码的相机权限请求（S02.4 第 3 条设备同步）、网页搜索和哔哩哔哩网页登录（S02.6 第 3 阶段）。
- Windows：**一直没构建、没运行**。由 X01.3 第一阶段（能在 Windows 上构建运行）接手，之后 X01.1、X01.2 逐项看标题栏、托盘、关闭询问、自启项（不要动 3.x 的 `PureLive` 和 `D:\Soft\` 下的安装）。登记表是“完成”，是按当时“只做 Android”（D-004）的口径：Android 一侧的插件构建通过即可。

## 留下的问题

- Android 上没逐项真机看的插件行为：归 S02.4（备份和文档选择器、扫码）、S02.6 第 3 阶段（网页搜索、哔哩哔哩网页登录）；open_filex 打开网络电视文件没有任务，回归时看（CHECKLIST 第 1 节第 17 条导入网络电视时顺带）。
- Windows 外壳整体没验证：X01.3、X01.1、X01.2。
- 选择目录在 Android 上得到的路径不一定可写（备份页会检查并提示换目录）；Android 11+ 的 `Download/`、`Documents/` 应该可写，没实测，归 S02.4 第 1 条。
- tray_manager 0.7 依赖的 `nativeapi`/`cnativeapi`（FFI）在 Android 构建里也会编进去（3.x 一样），包体积多一点；不做。
