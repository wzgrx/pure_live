# T13c.1 插件接入和 Windows 桌面外壳

- 日期：2026-10-01
- 范围：`apps/pure_live`（`pubspec.yaml`、`lib/platform/plugins.dart`、`lib/app/network.dart`、`lib/app/desktop/`、`lib/shared/qr_scan.dart`、`lib/shared/in_app_web.dart`、`lib/pages/account/bilibili_web_login.dart` 和各页面的接线）；根 `pubspec.yaml` 加两条依赖覆盖
- 来源：T07a.1、T07a.2、T07b.1/3/4/7/8/10/11/13/15 记录里“缺的共享服务”“留给后续”，`~/ref/notes/m13_notes.md`
- v3 对照：`pubspec.yaml`（v3.2.11）、`lib/common/global/platform/desktop_manager.dart`、`desktop_tray_service.dart`、`lib/common/global/win_auto_start.dart`、`lib/common/services/settings/window_size_controller.dart`、`lib/plugins/utils.dart`（关闭询问）、`lib/common/base/base_controller.dart`（断网预检、移动数据提示）、`player_controller.dart`（`_setDefaultResolution`）、`cache_controller.dart`（定时刷新封面）

## 插件

版本都是 pub.dev 当前最新（2026-10-01）；只有 flutter_inappwebview 用了预发布版，原因见下表。

| 插件 | 版本 | 用在哪 | 原生配置 | 替换了什么 |
|---|---|---|---|---|
| share_plus | 13.3.0 | 卡片菜单“分享”在手机上打开系统分享面板（`SystemShare.sheet`，`main` 里由 `installPluginHooks` 设置；桌面仍复制口令，同 v3） | 无（插件自带） | T07a.2 留的空接口；之前所有平台都复制口令 |
| flutter_cache_manager | 3.4.5 | 设置页“清除图片缓存”清磁盘（`ImageCacheTools.clearDisk = DefaultCacheManager().emptyCache`）；“定时刷新封面”（`CoverRefreshTimer`，跟随 `autoRefreshThumbnails`、`thumbnailRefreshInterval`，到点清磁盘和不在屏幕上的解码图片，不让整屏重载，同 v3 `refreshImageCache(refreshVisible: false)`） | 无 | 之前只清内存；定时刷新只存设置 |
| file_picker | 13.1.0 | 网络电视本地导入（`iptvFilePickerProvider`）、备份的“恢复其他文件”和“选择备份目录”（`backupPickerProvider`）、录制目录（`recordDirectoryPickerProvider`，目录框里加“选择文件夹”按钮，输入路径和“使用默认目录”保留） | 无；Android 用系统文档选择器（选文件时插件复制到应用缓存），**不申请“所有文件访问”**。清单里的 `MANAGE_EXTERNAL_STORAGE` 仍在，只给录制写公共目录用（T08b.1） | 输入路径的对话框、应用内浏览框 `showFileBrowser`（还在，测试和没有插件时用） |
| open_filex | 4.7.0 | `AppNavigator.openFile`：Android 用它打开本地文件（网络电视卡片“打开文件”），其他平台仍走 `url_launcher` | 插件自带 FileProvider | `url_launcher` 打不开应用私有文件的问题（T11a.3） |
| connectivity_plus | 7.3.1 | `lib/app/network.dart`：`NetworkKind`（无网络/仅移动数据/其他）、`networkProbeProvider`。推荐页每次刷新前预检：断网不请求，直接显示“当前无网络连接”；移动数据时列表上方显示 v3 的流量提示（“不再显示”本次运行内有效，同 v3）。直播间首个画质：移动数据用 `preferResolutionCellular`，否则 `preferResolution` | 无（`ACCESS_NETWORK_STATE` 已有） | T07b.1、T05a.1 记录的缺口 |
| mobile_scanner | 7.4.2 | `lib/shared/qr_scan.dart`：扫码页（只认二维码，可开手电筒，相机不可用时说明）。设备同步的手动地址框、同步到电视的地址框旁出现扫码按钮（`QrScan.scan`，只在 Android/iOS 设置；桌面不显示） | 插件清单带 `CAMERA`（`required=false`）；默认用**打包进 APK 的 ML Kit 模型**，不依赖 Play 服务 | 之前只能手输地址或粘贴二维码文字 |
| flutter_inappwebview | **6.2.0-beta.3** | `lib/shared/in_app_web.dart`：`InAppWeb.available`（启动时检测：Android 有；Windows 有 WebView2 运行时才有；Linux、测试没有）和 `InAppWebPage`（只放行 http(s)、拒绝不受信任的证书、返回键先后退网页、加载进度和失败说明）。① 网页搜索在应用内打开，页面是直播间时询问是否进入（用 `LinkParser` 识别，每个房间只问一次），标题栏可改用系统浏览器；② 哔哩哔哩网页登录（`kBiliBiliWebLogin`）：手机 UA 打开 passport 登录页，先删掉 WebView 里旧的哔哩哔哩 Cookie，跳到主站时读 Cookie、核验后保存（规则同扫码登录）；③ `AppNavigator.toBiliBiliLogin`：手机且有内置浏览器时才给“短信登录/二维码登录”选择，否则直接二维码（名字保留，现在名副其实） | 无额外配置。**为什么用 beta**：稳定版 6.1.5 的 Android 子包 1.1.3 用 `getDefaultProguardFile('proguard-android.txt')`，AGP 9 直接报错；1.2.0-beta.3 已改为 `proguard-android-optimize.txt`、`compileSdk = flutter.compileSdkVersion`（v3 当年用的 git 分支就是这一版再打补丁）。不需要 vendored 补丁 | 系统浏览器打开网页搜索、网页登录路由显示 Cookie 页 |
| window_manager | 0.5.2 | Windows 外壳，见下节 | `windows/runner` 与 v3 相同（v3 也用 window_manager），未改 | — |
| tray_manager | 0.7.0 | Windows 托盘，见下节 | 依赖 `nativeapi`/`cnativeapi`（FFI 插件，Android 构建里也会编进去，v3 同样如此） | — |
| screen_retriever | 0.2.2 | 记住的窗口位置是否还在某个显示器上 | — | — |

根 `pubspec.yaml` 新加两条覆盖（v3 也有这两条）：`nm: 0.6.0`（connectivity_plus 7.3.1 要 `nm ^0.5.0`，其 `dbus ^0.7.0` 与 wakelock_plus 1.8.1 的 `dbus ^0.8.0` 冲突）、`dbus: 0.8.0`（bonsoir 7.1.5 的 Linux 部分要 `dbus ^0.7.12`）。两者都只在 Linux 上用到。

### bonsoir（加了依赖，接线没做）

`bonsoir: ^7.1.5` 已在依赖里（Android 构建通过），但和 3.x 设备互相发现（`_purelive-sync._tcp`，TXT 里 id/name/platform/version/ip）的接线**没来得及做**，设备同步仍只有 v4 之间的 UDP 广播。要做的：在 `remote_sync_service.dart` 里开始/停止服务时同时 `BonsoirBroadcast`（同 3.x 的 TXT）和 `BonsoirDiscovery`，发现结果并进 `_discovered()`；Android 持有组播锁（`MulticastLock.hold` 已有）。

## Windows 桌面外壳（`lib/app/desktop/`）

| 功能 | 做法 |
|---|---|
| 启动 | `main` 在 `runApp` 前调 `DesktopShell.start(store, primary:)`（只在 Windows）：隐藏系统标题栏、最小 400×300、按设置 `window_width`/`window_height`（3.x 同名键）开窗 |
| 位置记忆（新） | 主窗口移动、调整大小 0.5 秒后保存：尺寸写回 3.x 的两个设置，位置写 `meta` 的 `window.position`（`x,y`）；最大化、最小化、全屏时不存。下次启动时，标题栏那一行还在某个显示器上才用这个位置，否则居中（3.x 只记尺寸、总是居中） |
| 自绘标题栏 | `DesktopTitleBar`：图标和“纯粹直播”（点击打开项目主页，同 v3）、拖动区、最小化、最大化/还原、关闭（悬停红色）。`DesktopFrame` 在 `app.dart` 的 `builder` 里把它放在应用上方，全屏时隐藏。没做 v3 拖动时显示窗口尺寸的小字和启动页的渐变背景 |
| 关闭窗口 | 关闭按钮和系统关闭（`setPreventClose`）都走 `requestClose`：额外窗口直接关闭；主窗口在“退出不再询问”关时弹框（最小化到托盘/退出应用 + 不再询问），开时按“关闭窗口时”（`exitChoose`）执行；没有托盘时“最小化”改为最小化到任务栏 |
| 托盘 | `DesktopTray`（主窗口）：单击显示窗口；右键菜单“隐藏/显示窗口”“退出应用”，打开前按窗口状态改文字；对象只建一次（同 v3 的修正）；切换语言后更新文字 |
| 开机自启 | `startup_entry.dart`：写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 下 **`PureLiveV4`**（3.x 是 `PureLive`，不读不改；也不碰 `D:\Soft\pure_live`、`D:\Soft\PureLive`），值是当前 exe 加引号。跟随设置 `enableStartUp` 的改动；**只有 release 构建**才在启动时按设置补写/删除（3.x 默认开，开发版不应自己注册） |
| 直播间、多画面全屏 | 桌面上 `DesktopWindow.setFullScreen` 让整个窗口全屏（之前只是窗口内全屏），标题栏同时隐藏；离开页面时退出全屏 |

## 应用内下载和安装更新包

**没做，留给 T16a**（和安装包、签名一起做）。现在版本页仍在系统浏览器里下载。要做的：下载目录设置（3.x 缓存页里）、带进度和断点续传的下载（走应用的 HTTP 客户端和代理）、Android 安装（`open_filex` 打开 APK 会走它的 FileProvider 和 `REQUEST_INSTALL_PACKAGES`，权限已在清单里）、Windows 下载完打开安装包或所在文件夹。

## Twitch 的 WebView 传输

**没做**。约定见 T02c.2 记录“GraphQL 传输的接口约定”：实现一个 `LiveHttp`，在无界面 WebView（`HeadlessInAppWebView`，打开 twitch.tv 后用 `callAsyncJavaScript` 发 `fetch`）里发 `gql.twitch.tv` 的请求，作为 `gqlFallbacks` 的第二项注入（`bootstrap.dart`，现在只有 Android 原生 TLS 通道）；只在 Android。v3 的实现是 `core/utils/twitch/twitch_web_integrity.dart`（422 行）。

## 没在真机或 Windows 上验证的

- **Windows 全部没构建、没运行**。在主机上构建：拉取本分支到 `C:\Users\123\claude-work\pure_live`，`C:\Users\123\claude-work\flutter\bin\flutter.bat pub get`，在 `apps\pure_live` 执行 `...\flutter.bat build windows --release`（或 `--debug`）。要检查：标题栏和拖动、最大化/还原、关闭询问和两种选择、托盘（图标、单击、右键菜单、退出）、尺寸和位置记忆（多显示器、拔掉显示器后）、`HKCU\...\Run\PureLiveV4` 的写入和删除（不要动 `PureLive`）、直播间和多画面全屏、WebView2 检测和网页搜索、file_picker 的 Windows 对话框、`cnativeapi` 是否能在 VS 2026 下编译（tray_manager 0.7 的原生部分）。
- **Android 没装到手机**：系统分享面板、文档选择器（选备份/播放列表/目录）、open_filex 打开文件、扫码（相机权限请求）、网络类型（移动数据提示、移动数据画质）、网页搜索和哔哩哔哩网页登录（Cookie 读取的域名、登录后跳转的地址）都只在 WSL 上跑了单元测试。
- 选择目录在 Android 上得到的路径不一定可写（备份页会检查并提示换目录）；Android 11+ 上 `Download/`、`Documents/` 下应可写，未实测。

## 测试

- 新增 `test/plugins_test.dart`（8 个）：图片缓存清除走缓存管理器、定时刷新只清不在屏幕上的；定时刷新封面跟随开关和间隔；网络类型的判定；列表刷新的断网预检和移动数据提示；同步电视对话框有扫码时读二维码、没有时不显示按钮；窗口位置的存取、自启项命令的判定（不认 3.x 的路径）；标题栏在应用上方、关闭按钮、全屏时隐藏；网页只放行 http(s)、哔哩哔哩登录落地判断和 Cookie 拼接。
- `live_play_controller_test.dart` 加 1 个：移动数据时首个画质用移动数据偏好。
- `recorder_page_test.dart` 加 1 个：目录框用系统选择器选的目录直接保存。
- 应用 `flutter test`：194 个，193 个通过；失败的 `recording_wiring_test` “a refused restricted room…”是本分支基线（T07a.2 合并后）就有的（录制提示还在用 T07a.2 删掉的 `live_play_restriction_*_hint` 键），master 上已由 8df75a12a 修好，合并后会消失。`flutter analyze` 无问题。

## 构建

- WSL：`flutter build apk --debug` 成功（全部插件，最后一次在 765973e90 上），包名 `com.mystyle.purelive.v4dev`，含 `CAMERA` 权限（mobile_scanner）。没有往手机安装。
- Windows：没构建（见上）。

## 合并时注意（冲突点）

- 本分支从 ecac9fda9（T07a.2 合并）开始；之后 master 又合并了 8df75a12a（录制受限文字）和 T05a.2（直播间第二部分），后者改了 `live_play_page.dart`、`room_controller.dart`（本分支：桌面全屏、移动数据画质、`network` 参数），很可能冲突。
- `lib/main.dart`、`lib/app/app.dart`（`DesktopFrame`、托盘文字）、`lib/app/startup.dart`（定时刷新封面）、`lib/routes/app_navigator.dart`（`openFile`、`navigatorContext`、`toBiliBiliLogin`）。
- 翻译文件新加 4 个键：`select_folder`、`qr_scan_hint`、`qr_scan_torch`、`web_search_room_found`（中英文都有），按键名排序合并即可。
- `apps/pure_live/pubspec.yaml`、根 `pubspec.yaml`（`nm`、`dbus` 覆盖）、`pubspec.lock`：合并后在根目录重新 `flutter pub get`。
- `lib/shared/rooms/room_feed.dart` 加了可选的 `precheck`；`room_texts.dart` 的 `describeLoadError` 认 `Offline`。
