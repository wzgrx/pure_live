# I01 首页外壳和全局

应用从启动到首页出来的那一段逻辑，和所有页面共用的“底座”：入口和启动（数据目录、存储、3.x 导入、平台和弹幕登记、服务对象）、路由和跳转、首页外壳的行为（菜单、再点刷新、回到前台刷新、命令行房间）、多语言、启动后的后台工作（关注核验、哔哩哔哩登录核验、定时关闭、本地网络权限），以及字体、日志、下载这几个应用级服务。

## 范围

- 包括：
  - 入口和启动：`apps/pure_live/lib/main.dart`、`lib/app/bootstrap.dart`（`AppBootstrap.start`、`wire`）、`lib/app/services.dart`（`AppServices` 和各个 provider）、`lib/app/launch_failure.dart`（启动失败页）、`lib/app/data_root.dart`（数据目录、3.x 数据的位置）、`lib/app/launch_args.dart`（命令行：`--instance`、`--open-room`）。
  - 启动后的工作：`lib/app/startup.dart`（`AppStartup`、`LegacyReloginNotice`、`verifyBilibiliLogin`、`splashFollowWait`）。
  - 应用外壳：`lib/app/app.dart`（`PureLiveApp`：主题、语言、文字缩放、图片请求头和缓存代数、手机和电视界面切换、提示条）、`lib/app/ui_mode.dart`（界面模式和电视检测）。
  - 路由：`lib/routes/`（`RoutePath`、`buildAppRouter`、`pageRoutes`、`AppNavigator`、`RouteArgs`/`LiveRoomArgs`、`LiveRouteObserver`、电视路由 `tv_router.dart`）。
  - 首页外壳的行为：`lib/features/home/`（`HomeMenu`、`visibleHomeMenus`、`HomeSignals`、`HomePage` 的再点刷新、回到前台刷新、返回键退到后台、命令行房间、启动后检查更新的时机）。
  - 多语言：`lib/i18n/i18n.dart`（`AppLanguage`、`AppStrings`、`i18n()`）。
  - 应用级服务（I01.3 加的）：`lib/app/fonts.dart`（字体下载和注册）、`lib/app/app_log.dart`（日志和脱敏）、`lib/app/downloads.dart`（断点续传的下载器、下载目录）。
- 不包括（归哪里）：
  - 首页、启动页、全局弹窗**长什么样**（底栏、侧栏、顶栏按钮、菜单、启动页画面、更新对话框的样子）→ [A06 首页和全局](../../A-界面设计/A06-首页和全局/README.md)；小页面的样子 → [A15](../../A-界面设计/A15-小页面/README.md)。
  - `lib/app/` 里别的组的文件：`desktop/`（窗口、标题栏、托盘、关闭对话框）→ [A16](../../A-界面设计/A16-桌面界面/README.md)、[X01](../../X-多端客户端/X01-Windows/README.md)；`intake/`（分享、快捷方式、剪贴板口令）→ [O03](../../O-Android系统集成/O03-分享接收和快捷方式/README.md)；`iptv_legacy.dart`、`iptv_library.dart` → [L01](../../L-网络电视和点播/L01-网络电视/README.md)；`recording.dart`、`recording_notice.dart` → [H02](../../H-录制/H02-录制中心/README.md)、[H03](../../H-录制/H03-录制设置和存储/README.md)、[H05](../../H-录制/H05-录制通知/README.md)；`network.dart`（网络类型）→ [Q04](../../Q-网络和代理/Q04-网络状态和权限/README.md)、代理策略（`platforms.dart` 的 `SettingsProxyPolicy`、`PlaybackProxyPolicy`）→ [Q02](../../Q-网络和代理/Q02-代理和镜像/README.md)；`platforms.dart` 的平台登记本身是这里的接线，平台适配器在 [E](../../E-直播平台/README.md)。
  - `lib/platform/`（原生通道的 Dart 侧）：`display_mode.dart` → O05、R02；`screen_orientation.dart` → O05；`system_access.dart`、`system_permissions.dart` → O04、Q04；`native_http.dart`、`twitch_webview_http.dart` → Q03；`share_channel.dart` → O03；`recording_platform.dart` → H02；`secret_cipher.dart` → J02；`plugins.dart`、`platform_services.dart`（插件接入）→ O03.1。
  - 启动速度 → [R04](../../R-性能和流畅度/R04-启动速度/README.md)；图片解码缓存的预算（`bootstrap.dart` 的 `configureDecodedImageCache`）→ [R03](../../R-性能和流畅度/R03-内存和图片/README.md)；翻译文件本身的整理 → [Z05](../../Z-工程文档和维护/Z05-多语言/README.md)；版本检查和更新下载的规则 → [Y02](../../Y-发布和运营/Y02-更新通道/README.md)；3.x 数据导入的规则 → [J06](../../J-设置和数据/J06-3.x数据迁移/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 冷启动：启动页（开着“启动页”时，默认开）→ 首页。启动页最多多等 350 毫秒让第一轮关注核验跑完（`splashFollowWait`，`lib/app/startup.dart:21`），3.x 同（`app_pages.dart`）。启动前就失败（数据库打不开、平台登记出错）时不再卡在启动画面，而是一页说明 + “重试”“导出日志”（`launch_failure.dart:58`，2026-10-02 发布修复第 7 项）。
  - 首页：手机底部导航、宽 ≥ 600 侧边导航（3.x 是 > 680，A06.2 改），目的地来自设置 `savedMenuIds`（关注、热门、分区、录制中心，去掉未知和重复的 id，`home_menu.dart:51`）；只有一个目的地时没有底栏。再点“关注”刷新关注（`HomeSignals.favoritesReselected`，`home_page.dart:116`）；应用在后台 15 秒以上回来，450 毫秒后让当前标签刷新（`HomeSignals.resumedAfterBackground`，`home_page.dart:95-112`）；Android 返回键退到后台不退出；命令行带的房间在首页出来后打开（Windows 新窗口）；主窗口首帧后 2 秒检查更新，只在首页在最上面、别的提示都关了之后才弹（A06.3 c7）。
  - 启动 1 秒后：核验哔哩哔哩登录（失效提示“登录已过期”并退出登录，`verifyBilibiliLogin` `startup.dart:116`）；3.x 导入时没能解开的登录提示一次“请重新登录”（`LegacyReloginNotice`）；打码昵称屏蔽清理一次（D02.1）；定时关闭、定时刷新封面开始计时；Android 上有代理指向局域网时申请一次本地网络权限（Android 17）。
  - 语言：设置写过就用设置，没写过跟随系统，都不匹配用中文；缺的键先回退中文、再英文，最后才是键名（I01.1 问题 1、2）。
  - 提示：`AppNavigator.toast` 是页面底部的浮动提示条（A02 的 `AppToaster`，同一时刻一条）。
- 内部怎么工作：

```text
main（main.dart:22）
  AppLog.install → launchOrExplain(_prepare)
  _prepare → AppBootstrap.start（bootstrap.dart:98）
      LaunchArgs.parse → resolveDataRoot（data_root.dart:21）
      → 平台密钥 → LiveStore.open → 主窗口：3.x Hive 和网络电视数据库导入（只读，记账本）
      → wire（:142）：HTTP（LoggingHttp + IoLiveHttp + 设置的代理）、Cookie 库、
           buildSiteRegistry（33 个平台 + 网络电视）、buildDanmakuRegistry、媒体中继、
           录制（platformAppRecording）、followsReady（身份迁移，关注刷新要先等它）
  → _finish：插件钩子、字体恢复（首帧前注册已选字体）、语言 → AppServices
  runApp(ProviderScope(appServicesProvider 覆盖…, PureLiveApp))；SystemIntake.start
PureLiveApp.initState（app.dart:74）
  AppNavigator.router / toast；RoomSwitchPanel.follows（:86-93）；首帧后 AppStartup.start（:95-97）
页面：ConsumerWidget，ref.watch(storeProvider / sitesProvider / …)，watchSetting(ref, Settings.x)
```

- 页面怎么取服务（I01.1 定下、现在仍是这样）：`ref.read(storeProvider)`、`watchSetting(ref, Settings.xxx)`、`ref.read(sitesProvider).of(id)`、`ref.read(danmakuProvider)`、`ref.read(playbackSessionFactoryProvider)`、`ref.read(recordingProvider)`；路由参数是页面构造参数 `RouteArgs route`；跳转和提示 `AppNavigator.*`。
- 完成度（和 3.x 对照）：
  - 一致的：路由路径（含拼错的 `/record_mannager` 和旧别名 `/douyu_cookie`）、首页菜单 id 和默认顺序、再点刷新、后台 15 秒刷新、命令行房间、返回键退到后台、启动页等关注核验、启动后检查更新、哔哩哔哩登录核验和文字、翻译文件和 `i18n()` 用法、图片解码缓存上限、图片请求头（哔哩哔哩 Referer、桌面浏览器 UA，`app.dart:183`）。
  - 确认过的改动：GetX 换成 Riverpod + go_router，服务是一个 `AppServices`（I01.1 问题 4）；打开直播间的防重复只挡 0.5 秒（3.x 直播间开着时别处打不开房间）；语言只有一个来源；新窗口和主窗口共用数据目录（A16.1 c14，3.x 每个窗口一份拷贝、关窗就丢）；侧栏从 600 宽开始（A06.2）；启动失败有说明页；日志在应用内看并脱敏（I01.3）；更新包应用内断点续传（I01.3、Y02）。
  - 还缺：无功能缺口。Windows 上的启动、单实例、注册表导入、字体目录、日志目录没在主机上跑过（X01）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/main.dart`（114 行） | `main`（`:22`，框架错误完整打印、装日志）、`_launch`（`:33`，`launchOrExplain` 包住启动）、`_exportLog`（`:58`）、`_prepare`/`_finish`（`:69`、`:83`：插件钩子、字体、语言） |
| `lib/app/bootstrap.dart`（273） | `configureDecodedImageCache`（`:34`，桌面 240 张 / 72 MB、手机 160 张 / 48 MB，按内存调，R03）、`readTotalMemoryBytes`（`:65`）、`AppBootstrap.start`（`:98`：参数、数据目录、存储、3.x 导入）、`wire`（`:142`：HTTP、平台、弹幕、网络电视导入器、录制、`followsReady`） |
| `lib/app/services.dart`（146） | `AppServices`（`:21`：`store`、`sites`、`danmaku`、`http`、`proxy`、`cookies`、`launch`、`dataRoot`、`recording`……，`newPlaybackSession` `:78`，`close` `:95`）；`appServicesProvider`（`:104`）、`storeProvider`、`sitesProvider`、`danmakuProvider`、`playbackSessionFactoryProvider`、`recorderProvider`、`recordingProvider`、`settingProvider`/`watchSetting` |
| `lib/app/startup.dart`（131） | `splashFollowWait` 350 毫秒（`:21`）、`bilibiliCheckDelay` 1 秒（`:25`）、`LegacyReloginNotice`（`:30`）、`AppStartup.start`（`:70`：定时关闭、定时刷新封面、本地网络守卫、显示模式、打码昵称清理、首轮关注核验 `:84`、1 秒后登录核验 `:85-91`）、`appStartupProvider`（`:106`）、`verifyBilibiliLogin`（`:116`） |
| `lib/app/app.dart`（302） | `PureLiveApp`（`:41`）：`initState`（`:74`，导航、提示、“看其他”的关注刷新 `:86-93`、首帧后启动工作 `:95-97`）、内存紧张时释放图片（`:116`）、手机 / 电视路由切换（`:118-133`）、语言跟随（`:135`）、`build`（`:144`：主题、文字缩放、刷新率策略、`LiveUiConfig` 的图片请求头和缓存代数 `:179-185`） |
| `lib/app/launch_failure.dart`（141） | `launchOrExplain`（`:16`）、`launchFailureReason`（`:42`，只留第一行、截短）、`LaunchFailureApp`（`:58`） |
| `lib/app/data_root.dart`（110） | `resolveDataRoot`（`:21`：Windows exe 旁 `UserData`，不可写时用支持目录；Android 支持目录；所有窗口共用）、`instanceFolder`（`:31`，额外窗口只放日志）、`legacyHiveFiles`（`:51`）、`windowsInstallLocations`（`:73`，注册表里的 3.x 安装目录） |
| `lib/app/launch_args.dart`（115） | `LaunchArgs`（`:15`）：`--instance=`、`--open-room=`（只带卡片字段）、`sanitizeInstanceId`（`:39`，含 Windows 设备名）、`build`（`:99`）；`startWindowProcess`、`launchNewWindow`（`:108`、`:115`） |
| `lib/app/platforms.dart`（278） | `SettingsProxyPolicy`、`PlaybackProxyPolicy`（Q02）、`StoreCookieVault`、`StoreDouyuLogin`、`PlatformDeps`（`:95`）和平台、弹幕登记 |
| `lib/app/ui_mode.dart`（71） | `UiMode`（自动、手机、电视）、`TvDevice.detect`、`showsTvInterface`（X03） |
| `lib/app/fonts.dart`（425）、`app_log.dart`（349）、`downloads.dart`（220） | I01.3 的三个服务：`FontLibrary`（57 个云端字体、镜像竞速、`.pending` 原子替换、从 3.x 字体目录复制）；`AppLog`（2000 条、写文件、等级、`redactSecrets` `:127`）；`FileDownloader`（`.part` 续传、换源接着下） |
| `lib/routes/route_path.dart`（146） | `RoutePath`：3.x 的全部路径常量 |
| `lib/routes/app_router.dart`（147） | `pageRoutes`（`:42` 起，每条路径一个页面类）、`buildAppRouter`（`:90`）、`liveRoomPage`（`:135`，直播间的进场动画） |
| `lib/routes/app_navigator.dart`（166） | `AppNavigator`：`toNamed`、`offAllNamed`、`toCategoryDetail`（`:75`）、`toLiveRoomDetail`（已下线平台、空房间号、0.5 秒防重复，`_usable` `:97`、`_openable` `:104`）、`liveRoomArguments`（`:117`）、`toast`、`openExternal`、`openFile` |
| `lib/routes/route_args.dart`（48）、`route_observer.dart`（123）、`tv_router.dart`（51） | `RouteArgs`（`:10`）、`LiveRoomArgs`（`:32`，从列表进直播间时带上列表，竖屏全屏上下滑用）；`LiveRouteObserver`（只发进出事件）；电视路由 |
| `lib/features/home/home_menu.dart`（95） | `HomeMenu`（`:6`，四个目的地）、`homeTabletBreakpoint` 600、`visibleHomeMenus`（`:51`）、`HomeLayoutScope`、`HomeSignals`（`:83`） |
| `lib/features/home/home_page.dart`（170） | `HomePage`（`:36`）：状态栏样式、`_checkForUpdate`（`:75`）、后台 15 秒刷新（`:95-112`）、`_select`（`:114`，再点关注刷新） |
| `lib/features/home/home_views.dart`（329）、`menu_button.dart`（167） | 底栏和侧栏（样子归 A06）；`AppMenuItem`（设置、关于、备份……、Windows 的“新窗口”）、`HomeAction`（搜索、多画面、链接、录制中心） |
| `lib/i18n/i18n.dart` | `AppLanguage`（`:8`，`resolve` `:41`）、`AppStrings`（`:61`，`tr` 的回退顺序 `:96`）、全局 `i18n`、`i18nOr`、`i18nExists` |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/home/home_test.dart`（15） | 3.x 的路由都在；菜单顺序和去重；手机底栏、再点关注刷新；顶栏按钮顺序；侧栏从 600 开始；横屏手机；大字体不溢出；跨过侧栏宽度不重建页面；打开直播间带房间、已下线平台被拒；启动页 → 首页、首帧后的启动工作和图片设置 |
| `test/launch_args_test.dart`（4）、`test/launch_failure_test.dart`（1） | 命令行房间往返、实例 id 过滤；启动失败页 |
| `test/i18n_test.dart`（6） | 翻译文件中英文键一致（只差固定的 4 个）、取词和参数、缺键回退、语言来源 |
| `test/platforms_test.dart`（11） | 33 个平台和网络电视都登记；弹幕登记的平台；代理随设置；Cookie 来自密钥库；身份迁移；原生 HTTP 白名单 |
| `test/services_test.dart`（13） | 日志脱敏、等级、写文件；下载续传和换源；字体清单、下载、注册、从 3.x 复制；显示模式；本地网络权限只问一次；设备同步的 mDNS |
| `test/shared/shared_test.dart`（8） | 共用卡片、文字、卡片对话框；哔哩哔哩登录核验的三种结果 |
| `test/image_cache_budget_test.dart`（3） | 图片解码缓存按内存调整（R03） |

## 3.x 基线

- 入口：`git show v3.2.11:lib/main.dart`（210 行，`GetMaterialApp` `:153`，`initialRoute` 按启动页开关 `:197`）；`lib/common/global/initialized.dart`（176 行，`AppInitializer` 单例）；`lib/common/global/initial_services.dart`（服务注册，`:80-89` 启动时只在需要时建录制器）。
- 路由：`lib/routes/route_path.dart`（116 行）、`app_pages.dart`（258 行，`:105` 分区房间 `Get.arguments[0]`）、`app_navigation.dart`（109 行）、`navigation_observer.dart`、`route_observer_controller.dart`。
- 首页：`lib/modules/home/home_page.dart`（`:83` 命令行房间 `takeInitialRoom`、`:118` 宽 > 680 平板、`:151` 后台 15 秒、`:157` 450 毫秒后刷新、`move_to_desktop` 退到后台 `:7`）、`mobile_view.dart`、`tablet_view.dart`；`lib/common/widgets/menu_button.dart`、`common_appbar_actions.dart`。
- 多语言：`lib/plugins/locale_helper.dart`、easy_localization；`assets/translations/zh.json`、`en.json`（各约 2066 键）。
- 数据目录和多窗口：`lib/common/global/app_path_manager.dart`（402 行）、`lib/common/utils/windows_multi_instance_launcher.dart`（190 行，`--config-file` 交接，A16.1 c14 已取消）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 15 条（Windows 在新窗口打开直播间，`launch_args.dart`）、第 17 条（回到前台识别剪贴板口令，`SystemIntake`，归 O03）、第 18 条（定时关闭，`AppStartup.start` 接上 `AutoExitTimer`）。附录 A 没列、但照 3.x 保留的：再点“关注”刷新、后台 15 秒回来刷新、Android 返回键退到后台、命令行房间。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| I01.1 记录里写的 `MainActivity` 改成 `FlutterActivity`，后来 C01.2 改回 `AudioServiceActivity`（后台播放、划掉应用后继续录要它缓存引擎） | `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt:88` | 只是记录过时 | I01.1 README 已注明；记录不改 |
| I01.1 记录的新窗口交接（`NewWindowHandoff`、`--config-file`、`instances\<id>` 单独的数据）已被 A16.1 c14 换成共用数据目录，`instances\<id>` 只放日志 | `data_root.dart:9-31`、`launch_args.dart:9-14` | 同上 | 同上 |
| 代码注释还写“`lib/pages/`”“M13 替换目录 / 占位页”（页面已经在 `lib/features/`，不是占位） | `routes/app_router.dart:39-41`、`routes/route_args.dart:7-8`、`features/home/home_page.dart:21-23` | 按注释找不到目录 | Z 组一次性改注释（和 A08 记的“注释里的旧编号”一起） |
| `lib/app/` 里的文件分属六七个组，目录本身没有归属说明 | `lib/app/` | 改一个文件不知道该在哪开任务 | 本页“范围”逐个写了；需要时在 `lib/app/` 加一个说明文件（Z03） |
| Windows 上的启动、单实例、3.x 注册表导入、日志和字体目录没在主机上跑过 | `windows/runner/main.cpp`、`data_root.dart:73` | — | X01（D-004：当前只做 Android） |
| 启动后哔哩哔哩登录核验失败时（网络不通）只提示一次，不再重试 | `startup.dart:127-129` | 登录其实已失效时要等下次启动才知道 | 照 3.x，不做 |
| 三个任务（I01.1～I01.3）登记“完成”，但记录里都写“本次不往手机装”；之后的 S02.2、S02.3 冒烟走过启动、首页、语言、提示，Android 17 本地网络权限、字体下载、日志分享、应用内安装没有 K90 记录 | 各任务 `record.md`“没验证的部分” | 不符合 PROCESS 3.2 | 字体下载、应用内更新、本地网络权限已在 [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 第 4 阶段；日志导出没有归属，建议并入 S02.4（写进本单元报告） |

## 相关决定和规范

- D-001（在 3.x 代码上逐块重构）、D-002（只借鉴归档 v4 的工程工具，`data_root.dart` 借了它的数据目录做法）、D-004（只做 Android）、D-005（文字中文、翻译文件中英文一起加）、D-018（设置键不变，`savedMenuIds`、`language` 照 3.x）、D-025（编号）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md)：第 4 节分层（`apps/pure_live` 只经 provider 取服务）、第 7 节（功能目录之间不互相引用，共用的放 `shared/`）。
- [specs/UI.md](../../specs/UI.md)：附录 A 第 15、17、18 条；提示条同一时刻一条（第 7 节）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/home test/launch_args_test.dart test/launch_failure_test.dart test/i18n_test.dart test/platforms_test.dart test/services_test.dart test/shared/shared_test.dart test/image_cache_budget_test.dart`（上表约 61 个）。缺的：没有真的走一遍 `AppBootstrap.start`（用的是 `wire` 和内存数据库），3.x 导入在 `packages/live_store` 的测试里；Windows 的单实例只有 C++，没有测试。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节（启动、首页、语言、返回键）；S02.2 冒烟看过冷启动、首页、四个目的地。

## 路线

本子分类没有未完成的任务。

1. 真机余项（本地网络权限、字体下载、应用内安装在 S02.4；日志导出建议并入 S02.4），不在这里开任务。
2. 过时注释随 Z 组的一次性注释清理改。
3. 启动速度（冷启动到首页的时间）由 R04 量；首页、启动页的样子由 A06 改。新想法写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`app/`、`routes/`、`features/home/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I01.1 | 应用骨架：入口、路由、首页外壳、多语言、Android 和 Windows 原生部分 | 功能 | 完成 | 2026-10-01 | 6e2376d6e | [设计或说明](I01.1-应用骨架/README.md)、[记录](I01.1-应用骨架/record.md) |
| I01.2 | 共用模块和应用外壳接线 | 功能 | 完成 | 2026-10-01 | cc48756fb | [设计或说明](I01.2-共用模块和应用外壳接线/README.md)、[记录](I01.2-共用模块和应用外壳接线/record.md) |
| I01.3 | 应用服务补全 | 功能 | 完成 | 2026-10-01 | 0e4ecb34e | [设计或说明](I01.3-应用服务补全/README.md)、[记录](I01.3-应用服务补全/record.md) |

<!-- docs:生成结束 -->
