# M12 应用骨架：入口、路由、首页外壳、多语言、Android 和 Windows 原生部分

- 日期：2026-10-01
- 目标：新成员 `apps/pure_live`（Flutter 应用，包名 `pure_live`），依赖方向按 `tools/gate/check_deps.py`：`live_ui`、`live_player`、`live_media`、`live_record`、`live_danmaku`、`live_iptv`、`live_store`、`live_core`、`live_net`（`live_cast` 允许但现在用不到）
- v3 来源：标签 `v3.2.11` 的 `lib/main.dart`、`lib/common/global/initialized.dart`（启动）、`lib/routes/`、`lib/modules/home/`、`lib/common/widgets/menu_button.dart`、`common_appbar_actions.dart`、`lib/common/utils/windows_multi_instance_launcher.dart`、`lib/common/global/app_path_manager.dart`（数据目录、注册表）、`lib/plugins/locale_helper.dart`、`assets/translations/`、`android/`、`windows/`、`plugins/built_in_kotlin/`
- 设计参考：归档 v4 的 `apps/pure_live`（借鉴了数据目录 `UserData` 的做法，见 `lib/app/data_root.dart`；它的页面结构、slang 多语言与 v3 不同，没有采用）

## 做法

- **启动**（`lib/app/bootstrap.dart`，对应 v3 `AppInitializer.initialize`）：
  1. 读命令行（`LaunchArgs`：`--instance`、`--open-room`、`--config-file`，规则照 v3）；
  2. 数据目录（`resolveDataRoot`）：Windows 是 exe 旁的 `UserData`（不可写时用应用支持目录），Android 是应用支持目录；额外窗口用 `instances\<id>` 子目录（同 v3 每个实例一份数据）；
  3. 用平台密钥（`platformSecretCipher`）打开 `LiveStore`；
  4. 主窗口导入 3.x 数据：`legacyHiveFiles()` 给 `LegacyLocations`（Android 文档目录；Windows exe 目录、支持目录、文档目录和注册表卸载项里的安装目录），`LegacyMigration.importHiveFiles` 只读、记账本；
  5. 新窗口的交接文件走 `NewWindowHandoff.restore` → `BackupService.restoreAll`；
  6. `AppBootstrap.wire` 建 HTTP 客户端（`IoLiveHttp` + 按设置的 `SettingsProxyPolicy`）、`StoreCookieVault`、33 个平台和 IPTV（`buildSiteRegistry`）、弹幕登记（`buildDanmakuRegistry`）、IPTV 导入器（GBK 解码注入）、共用的 `MediaOpener`；
  7. 后台：虎牙的播放 UA（`loadPlayUserAgent`）、身份迁移（`IdentityMigration.run`，结果是 `AppServices.followsReady`，关注刷新要先等它）、3 秒后 IPTV 自动同步（平台列表里有网络电视且开关打开）。
- **服务怎么交给页面**：一个 `AppServices` 对象，经 Riverpod 的 `appServicesProvider` 下发（`main` 里 override），另有几个直接的 provider，见下文“页面怎么取服务”。
- **路由**：go_router。路径常量 `RoutePath` 和 v3 完全一样（含拼错的 `/record_mannager` 和旧别名 `/douyu_cookie`）；路由表 `pageRoutes` 每条路径指向 `lib/pages/<页面>/<页面>_page.dart` 里固定类名的页面（现在都是“建设中”占位），M13 只替换自己的目录，不改路由表。页面名就是路径，路由观察者照旧按 `RoutePath` 匹配。
- **导航**：`AppNavigator` 保留 v3 的静态方法（`toLiveRoomDetail`、`offAndToRoomDetail`、`toCategoryDetail`、`toMultiview`、`toBiliBiliLogin`），并补上 `toNamed`、`offAllNamed`、`offAndToNamed`、`back` 对应 v3 的 `Get.toNamed` 等，页面可以逐个调用替换。提示（v3 `ToastUtil.show`）是 `AppNavigator.toast`，应用接到根 `ScaffoldMessenger` 的 SnackBar。
- **首页外壳**（`lib/home/`）：手机底部 `NavigationBar`、宽于 680 时侧边 `NavigationRail`，菜单来自设置 `savedMenuIds`；外观、图标、侧栏动作（菜单、多画面、链接、搜索、录制中心）和 v3 一样。首页各 Tab 用的是同一套页面类（`RouteArgs(inHome: true)`），手机上标题栏左边菜单、右边搜索菜单（v3 的 `showAction`）。`MenuButton`、`CommonAppBarActions` 照 v3 的菜单项和路由。
- **多语言**：保留 v3 的 `assets/translations/zh.json`、`en.json` 和用法：全局函数 `i18n(key, args:)`、`i18nOr`、`i18nExists` 同名同参，`{name}` 占位符同 easy_localization。语言来自设置 `language`（`简体中文`/`English`）；用户没选过时跟随系统（同 v3 实际行为），都不匹配时中文。`LiveUiScope` 的文字（`LiveUiStrings`）从同一份翻译取。
- **主题和界面基础**：`LiveDynamicColorBuilder` + `LiveTheme`（种子色或系统动态色、五档字体大小、字体）、`themeMode`、`MaterialUiThemeBridge`、`LiveUiScope`（文字、加载样式和颜色）、文字缩放、Android 的 `AdaptiveRefreshRateScope`（刷新率策略来自设置，经原生 `pure_live/display_mode`）、滚动行为 `AppScrollBehavior`（v3 `MyCustomScrollBehavior`）；`pubspec.yaml` 写了 `uses-material-design: true`。
- **Android 原生**（`apps/pure_live/android`，照 v3 改）：
  - 包名：release 保持 `com.mystyle.purelive`（M15 覆盖安装 3.x）；debug 和 profile 加后缀 `.v4dev`、应用名“纯粹直播 v4dev”，和手机上的 3.x 并存；签名照 v3 读 `key.properties`（不进 Git）；
  - `MainActivity` 改为 `FlutterActivity`（v3 的 `AudioServiceActivity` 属于后台播放，随系统媒体通知一起回来），保留 v3 的 `pure_live/display_mode`、`pure_live/background_playback`、`pure_live/predictive_back`，加 `pure_live/app`（返回键退到后台，代替 v3 的 move_to_desktop 插件）；
  - `AppChannelsPlugin`（不依赖 Activity）：`pure_live/secret_cipher`（Android Keystore 的 AES-256-GCM，密钥不可导出，名字作附加数据）、`pure_live/native_http`（系统 TLS 的 HTTPS，只放行白名单主机）、`pure_live/text_codec`（严格 GBK 解码）、`pure_live/multicast_lock`（DLNA 发现用的组播锁）；
  - 清单：v3 的权限、深链和分享入口照旧，加 `CHANGE_WIFI_MULTICAST_STATE`；去掉 Firebase（`google-services`）、录制前台服务和 audio_service 的声明（随 M8/M13 的原生部分回来）、调试探针。
- **Windows 原生**（`apps/pure_live/windows`，照 v3 改）：`runner/main.cpp` 在启动 Flutter 之前按窗口 id 建互斥体：主窗口重复启动时把已有窗口提到前台并退出，额外窗口同一 id 只留一个；DPAPI 和 GBK（代码页 936）在 Dart 里用 FFI 直接调系统 DLL，不需要插件；注册表读取用 `win32_registry`（v3 同款）。安装包脚本（`windows/packaging`）留给 M15。

## 页面怎么取服务

页面是 `ConsumerWidget`/`ConsumerStatefulWidget`（`flutter_riverpod`），在 `build` 里 `ref.watch`，在事件里 `ref.read`：

| 要什么 | 写法 | v3 写法 |
|---|---|---|
| 存储、设置 | `ref.read(storeProvider)`；设置值并随改动刷新：`watchSetting(ref, Settings.xxx)`；写：`ref.read(storeProvider).settings.set(Settings.xxx, v)` | `SettingsService.to.xxx.v`、`Obx` |
| 平台 | `ref.read(sitesProvider).of(id)`（`maybeOf`、`ids`、`availableIds(saved)`） | `Sites.of(id)` |
| 弹幕连接 | `ref.read(danmakuProvider).connectionFor(platform)`、`supports(platform)` | `site.getDanmaku()` |
| 播放会话 | `ref.read(playbackSessionFactoryProvider)(config: ...)`，页面持有并在离开时 `dispose`/`stop`；所有会话共用 `AppServices.mediaOpener`（一个中继） | `GlobalPlayerService.instance.playerManager` |
| 录制器 | `ref.read(recorderProvider)`；现在是 null（缺 FFmpeg 实现，见“留给其他模块”），录制中心要处理 null | `Get.find<RecorderController>()` |
| 其他 | `ref.read(appServicesProvider)`：`http`、`proxy`、`cookies`、`launch`、`dataRoot`、`iptvImporter`、`cipher`、`followsReady` | 各种单例 |
| 路由参数 | 页面构造参数 `RouteArgs route`：`route.arguments`（直播间是 `LiveRoom`，分区房间是 `[LiveSite, LiveArea]`），`route.inHome` | `Get.arguments` |
| 跳转、提示 | `AppNavigator.toNamed(RoutePath.kXxx, arguments: ...)`、`AppNavigator.toLiveRoomDetail(liveRoom: room)`、`AppNavigator.back()`、`AppNavigator.toast(i18n('key'))` | `Get.toNamed`、`AppNavigator.*`、`ToastUtil.show` |
| 首页信号 | `HomeSignals.favoritesReselected`（关注页监听后刷新）、`HomeSignals.resumedAfterBackground`（热门、分区监听后刷新） | `favoriteController.tabBottomIndex`、`Get.find<PopularController>()` |
| 路由事件 | `liveRouteObserver.addListener(...)`、`currentRoute` | `RouteObserverController.to.currentRoute`、`LiveRouteObserver` |

M13 每个页面任务只改 `lib/pages/<页面>/`：保留类名和构造参数 `({required RouteArgs route})`，页面私有的控制器、组件放在同一目录。需要新的共享服务时，在 M13 记录里写明，由合并的人加进 `lib/app/services.dart`。

## 对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `main.dart` | 210 | `lib/main.dart`、`lib/app/app.dart` | `GetMaterialApp` 改 `MaterialApp.router`；`Obx` 改 `watchSetting` |
| `common/global/initialized.dart` | 176 | `lib/app/bootstrap.dart` | 单例改成一次性的启动函数，返回 `AppServices` |
| `common/utils/windows_multi_instance_launcher.dart` | 190 | `lib/app/launch_args.dart` | 参数规则不变；交接文件改见问题 3 |
| `common/global/app_path_manager.dart`（数据目录、注册表） | 402 | `lib/app/data_root.dart` + M9 的 `LegacyLocations` | 只留应用侧：目录选择、注册表 |
| `routes/route_path.dart` | 116 | `lib/routes/route_path.dart` | 不变 |
| `routes/app_pages.dart` | 258 | `lib/routes/app_router.dart`、`lib/pages/*/` | 页面一目录一个，先占位 |
| `routes/app_navigation.dart` | 109 | `lib/routes/app_navigator.dart` | 同名方法；浮窗交接留给播放（M13） |
| `routes/navigation_observer.dart`、`route_observer_controller.dart` | 148 | `lib/routes/route_observer.dart` | 只报事件，见问题 7 |
| `modules/home/*.dart` | 554 | `lib/home/` | 外观、行为照旧 |
| `common/widgets/menu_button.dart`、`common_appbar_actions.dart` | 163 | `lib/home/menu_button.dart` | 同上 |
| `plugins/locale_helper.dart`、`assets/translations/` | 15 + 2×2066 键 | `lib/i18n/i18n.dart`、`apps/pure_live/assets/translations/` | 去掉 easy_localization |
| `android/`（`MainActivity`、`NativeHttpChannel` 等 5 个 Kotlin 文件，1330 行） | — | `android/`（2 个 Kotlin 文件） | 录制服务（806 行）属于 M8 原生部分，后补 |
| `plugins/built_in_kotlin/`（better_player_plus、flutter_inappwebview_android、share_handler_android、mobile_scanner、floating、flutter_exit_app 的 AGP 9 补丁） | — | 不搬 | v4 不用 better_player（只用 mpv）；网页、分享、扫码、画中画、退出的插件在用到它们的页面（M13）引入时再看是否还要补丁 |
| `windows/` | — | `windows/` | `main.cpp` 改单实例；`packaging/` 留给 M15 |

v3 调用方（`git grep` v3.2.11 的 `lib`）：`AppNavigator` 被 13 个文件调用（卡片、搜索、关注、分区、历史、链接解析、多画面、直播间），`RoutePath` 被 23 个文件使用，`i18n(` 共 2273 处，`AppInitializer().takeInitialRoom()` 只在首页。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 中英文翻译各缺两个键（`count_wan`、`videofit_scaleDown` 只有中文，`count_k`、`double_click_to_exit` 只有英文），中文界面直接显示键名 | `assets/translations/*.json` | easy_localization 的回退语言是中文，缺中文时没有再回退 | 缺的键依次回退中文、英文，最后才是键名 |
| 2 | 语言有两个来源：Hive 的 `language`（默认“简体中文”）和 easy_localization 自己存的语言/系统语言；没选过语言的英文手机界面是英文，设置页却显示“简体中文” | `theme_settings_controller.dart:20,161-165`、`main.dart:33-37` | 设置只在用户选择时同步给 easy_localization | 只有一个来源：设置写过就用设置，没写过跟随系统（`AppLanguage.resolve`），不再读 SharedPreferences 里的 `locale` |
| 3 | 新窗口的交接文件是带 Cookie 明文的完整备份，写在临时目录；新窗口用 `recoverAndDelete` 导入，绕过恢复锁和校验 | `windows_multi_instance_launcher.dart:118-128`、`initialized.dart:94-100` | 交接直接复用了“含敏感数据的备份” | 备份不带密钥，密钥另用平台密钥（DPAPI，同一 Windows 用户才能解开）封装后放进文件；导入走 `restoreAll`；文件读后连目录删除（M9 问题 12） |
| 4 | 启动对象是全局单例，服务靠 GetX 注册，页面到处 `Get.find` | `initialized.dart:35-46`、`initial_services.dart` | GetX 结构 | `AppServices` 一次建好，经 provider 下发 |
| 5 | 单实例只在没有参数时由原生层拦截；带参数的启动交给 windows_single_instance 插件，插件只把旧窗口提前、丢掉参数，而且要先起一个 Flutter 引擎 | `windows/runner/main.cpp:44-58`、`initialized.dart:131-139` | 两层各管一半 | 原生层按窗口 id 一律拦截（主窗口提到前台），不再需要插件 |
| 6 | 分区房间页取参数用 `Get.arguments[0]`、`[1]`，没有参数时直接崩 | `app_pages.dart:105` | 路由参数无类型 | 参数放在 `RouteArgs.arguments`，页面自己判断（占位页显示参数） |
| 7 | 路由观察者直接找 `LivePlayController`、调播放器，路由层和播放、直播间互相引用 | `navigation_observer.dart:11-139` | 用观察者当事件总线 | 观察者只发出进出事件，直播间和播放（M13）自己监听 |
| 8 | Android 的 Kotlin 源码目录是 `com/mystyle/pure_live`，包名却是 `com.mystyle.purelive` | `android/app/src/main/kotlin/` | 改过包名没挪目录 | 目录改为 `com/mystyle/purelive` |
| 9 | debug 构建和正式版同一个包名，开发时装到手机会覆盖用户的 3.x | `android/app/build.gradle.kts`（没有后缀） | — | debug、profile 加 `.v4dev` 后缀和名字 |
| 10 | 应用带着 Firebase（`google-services` 插件、`firebase_core`、`firebase_auth`、`cloud_firestore`） | `android/app/build.gradle.kts:6-12`、`google-services.json` | 账号功能用了 Firebase（PLAN 第 5 节列为 GMS 问题） | 去掉；账号页（M13）要的话另议 |
| 11 | 原生 HTTP 通道只会发 Twitch 的 POST，回答只有状态和文字，没有响应头 | `NativeHttpChannel.kt:41-111` | 为一个请求写的 | 通用的 `send`（方法、头、二进制体、代理），回答带头和字节；仍然只放行白名单主机 |
| 12 | Cookie、密码明文 | `cookie_settings_controller.dart`（M9 问题 1） | — | M9 的密钥库 + 本块的 Keystore/DPAPI 实现 |
| 13 | Android 收组播没持有 `MulticastLock`，很多手机丢 SSDP 通告（M10 记录） | — | — | 原生加组播锁和权限，Dart 侧 `MulticastLock.hold` |

## 保留的 v3 行为

- 路由路径、首页菜单 id 和默认顺序（`favorites`、`popular`、`areas`、`record`）、宽度 680 的分界、平板侧栏不放录制中心而放成动作、只有一个菜单时不显示底栏、没有菜单时的提示、再次点关注会刷新、后台 15 秒以上回来刷新当前页（延迟 450 ms）、命令行房间在首页出来后打开、返回键退到后台。
- `toLiveRoomDetail`：平台名去空格转小写，已下线平台提示 `platform_retired`，房间号空提示 `get_room_info_failed_retry`，打开中再点忽略；CC 官方入口用外部浏览器打开，打不开提示 `external_browser_not_opened`。
- 命令行：实例 id 的过滤规则（含 Windows 设备名）、房间参数只带卡片字段、交接文件只认 `<临时目录>/pure_live_instance_*/<id>.json`。
- 图片解码缓存上限（桌面 240 张/72 MB，手机 160 张/48 MB）；框架错误完整打印。
- Android：v3 的权限、深链、分享入口、显示模式和预测返回的原生逻辑原样搬过来。

## 有意差异

| 差异 | 原因 |
|---|---|
| 启动页暂不出现，直接进首页 | 启动页是 M13 最后一页；`showSplashPage` 设置保留，启动页做好后由它决定初始路由 |
| 首页的 Tab 和路由用同一个页面类 | M13 一个页面只改一个目录 |
| 打开直播间的防重复只管 0.5 秒 | v3 等 `Get.toNamed` 的结果，它在直播间关闭时才完成，所以直播间开着时别处的“打开房间”全被忽略（直播间里点推荐房间无效）；现在只挡住进场期间的重复点击 |
| 提示用 SnackBar | v3 的 flutter_smart_dialog 只为了不带 context 弹提示；`AppNavigator.toast` 同样不需要 context |
| 启动时不检查更新 | 检查更新属于“关于和版本”页（M13），它负责首页启动后 2 秒的检查 |
| IPTV 库暂时在内存里 | M6 把持久化实现（drift）记在 M9，M9 没有做（它把 IPTV 库记回 M6）；现在网络电视能用，但导入的列表重启后要重新导入。留给网络电视页（M13）前补上 |
| 不读 SharedPreferences 的 `locale` | 见问题 2；v3 只有用户选语言时才写它，同时也写了 Hive 的 `language`，M9 已导入 |

## 界面改进

（2026-10-01 用户授权：界面、设置分类、默认值、选项、存储键名都可以改进，前提是 3.x 的数据能完整迁移过来，键名改了要在迁移里对照。本块只做了下面几处，其余外观先照 v3，留给各页面在 M13 里改进。）

- 没选过语言时界面和设置页一致：跟随系统语言（v3 界面跟随系统、设置页却显示“简体中文”）。
- 缺翻译的键显示另一种语言的文字，不再显示键名。
- 提示改成浮动 SnackBar（同一时刻只显示最新一条），不依赖弹窗插件。
- 其余外观（底栏、侧栏、菜单）照 v3，没有改。

## 已批准的升级（docs/UPGRADES.md）

| 编号 | 本块做了什么 |
|---|---|
| X-1 恢复 Kick | 部分完成：Android 原生网络层做成通用的 `AndroidNativeHttp`（`LiveHttp`，系统 TLS、走应用代理、白名单主机），Twitch 已作为 GraphQL 备用传输注入。余下：Kick 适配器和弹幕（参考 pure_live_TV e1cca224）、白名单加 Kick 的主机（Kotlin `ALLOWED_HOSTS` 和 Dart `allowedHosts` 两处）、`SiteIds.retired` 去掉 `kick`；Windows 的 WinHTTP 通道 |
| B-2 握手不带 `Dart/` 前缀 | 部分完成：留开关和说明。`live_net` 的 `connectIoSocket` 加了可选参数 `plainUserAgent`（只添加，默认关）；应用里的开关是编译参数 `--dart-define=PURE_LIVE_PLAIN_WS_UA=true`，打开后用 dart:io 握手的弹幕平台（YY、FC2 除外）都不带前缀。余下：Android 真机逐平台验证（v3 实测自定义直连客户端可能让握手挂到超时），通过后改成默认开 |
| 17-1、23-1、抖音 room_id → web_rid | 应用接上 M9 的 `IdentityMigration`：niconico、YouTube 用 `resolveRoomId` 加 `watchUrl`/`roomLink`，抖音用 `getRoomDetailForRefresh`；在启动后台运行，`followsReady` 给关注刷新等待。余下 M13 的页面 |
| B-13 YouTube“显示全部聊天” | 弹幕登记按连接时的设置 `youtubeShowAllChat` 创建连接 |
| B-6 SOOP 弹幕走代理 | 登记时传 `proxy` |
| 统一原则“默认编码” | 设置 `preferH264` 传给虎牙、快手、Twitch、映客、TikTok、酷狗、百度、17LIVE 的适配器（每次请求读取） |
| 2-1、8-3 | 斗鱼 `forceRenewal`、Twitch `languages` 读设置 |

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 录制（M8 留给 M12 的）：`FfmpegRunner` 的实现（v3 用 ffmpeg_kit_extended_flutter 0.6.2 + 自建 FFmpeg 9.0.2 包）；Android/Linux 的 CA 包（v3 的 `assets/certificates/mozilla-ca-bundle.pem`）给 `caFile`；Android 前台服务（v3 `RecorderForegroundService.kt`、`RecorderBackgroundPlugin.kt`，806 行）实现 `RecordKeepAlive`，被系统停掉时调 `keepAliveInterrupted`；存储权限 `storageAccess`。已做好位置：`lib/app/recording.dart` 的 `buildRecorder`（站点表、`RecordStorage` 和默认目录、配方打开器 FC2/Bigo/niconico、任务持久化到 `meta` 的 `recorder.tasks`）、`savedRecorderTasks`（没有 v4 任务时读 3.x 的 `recorder_tasks`）、`AppServices.recorder`/`recorderProvider`。有了 FFmpeg 实现后：启动时 `buildRecorder` → `restore(await savedRecorderTasks(store))`，录制设置改动后调 `settingsChanged()` | M12 后续（录制原生部分），录制设置的存储在 M9 |
| 录制设置的读写（3.x Hive 键 `segmentTime` 等）和 `RecordSettings` 的来源 | M9 |
| 后台播放、系统媒体通知（v3 `audio_service`、`AudioServiceActivity`）、前后台生命周期接 `PlaybackSession.pause/resume`、画中画和窗口、全屏 | M12 后续 / M13 直播间 |
| 播放设置（硬解、输出、兼容模式）组成 `MpvEngineConfig` 传给 `playbackSessionFactoryProvider` | M13（设置在 M9） |
| Windows 桌面外壳：自绘标题栏、窗口尺寸和位置记忆、托盘、关闭行为、开机自启（v3 `desktop_manager.dart` 848 行、`desktop_tray_service.dart`、`win_auto_start.dart`，用 window_manager、tray_manager） | M12 后续，和 Windows 主机构建一起做 |
| Twitch 的无界面 WebView 传输和 KPSDK 令牌（M4.08） | M13 账号/网页登录引入 WebView 时 |
| 分享和深链的接收（v3 `share_handler`、`SharedMediaIntake`）、剪贴板识别 | M13（链接解析、网络电视导入） |
| 启动后检查更新（首页 2 秒后） | M13 关于和版本 |
| IPTV 库的持久化 | M13 网络电视页之前（见有意差异） |
| 下载的字体注册（`resolveAppFontFamily` 的 `customFonts`） | M13 字体设置 |
| 日志（v3 `core_log`、诊断） | M13 |
| Windows 构建和实机检查 | 主机上做，本次没做：在 Windows 用 `flutter build windows` 构建，检查单实例、新窗口交接（DPAPI）、3.x 安装目录的导入、GBK 列表 |
| Android 真机检查 | 本次不往手机安装：Keystore 加解密、组播锁、Twitch 原生通道、刷新率、返回键退到后台 |

## 依赖变化

- 新成员 `apps/pure_live` 加进根 `pubspec.yaml` 的 `workspace`。
- 第三方包：`flutter_riverpod` 3.4.3、`go_router` 18.0.2（PLAN 第 4 节）、`path_provider` 2.1.6、`url_launcher` 6.3.2、`win32_registry` 3.0.3（v3 同款）、`ffi`、`path`、`flutter_localizations`。根 `pubspec.lock` 新增 riverpod、go_router、url_launcher 系列、win32、win32_registry 等。
- 比 v3 少：easy_localization、GetX、flutter_smart_dialog、windows_single_instance、move_to_desktop、charset_converter、Firebase 三件套、better_player_plus 等。
- 对其他包只做了一处添加：`live_net` 的 `webSocketClientFor`、`connectIoSocket` 加可选参数 `plainUserAgent`（默认关，行为不变）。

## 构建

- WSL：`flutter analyze` 无问题；`flutter build apk --debug` 成功，产物包名 `com.mystyle.purelive.v4dev`、名字“纯粹直播 v4dev”、targetSdk 37。构建产物不进 Git。
- Windows：在主机上构建，本次没做（见上表）。

## 测试

23 个用例（`flutter test`，加速流程，只覆盖主要路径和审查出的问题）：

| 测试文件 | 内容 |
|---|---|
| `launch_args_test.dart`（5） | 移植 v3 `windows_multi_instance_launcher_test` 的 4 个用例：房间参数往返不带平台数据、实例 id 过滤和坏参数、下播状态、只认启动器写的交接文件；新窗口交接带上数据和 Cookie、文件里没有明文、读后删除（问题 3） |
| `i18n_test.dart`（4） | 翻译文件保留且差异只有 4 个键；`i18n` 取词、命名参数、缺键回退（问题 1）；语言来源规则（问题 2）；共享组件的文字 |
| `platforms_test.dart`（9） | 33 个平台和 IPTV 都登记、适配器复用；弹幕登记的平台（CC、映客、小红书、微博、LiveMe、TikTok、IPTV 不登记）；代理随设置变化；Cookie 来自密钥库并通知变化；斗鱼登录信息；身份迁移不动其他平台；原生 HTTP 的白名单、参数和回答、平台错误转成传输失败（问题 11） |
| `home_test.dart`（5） | v3 注册的路由全部存在；菜单顺序、未知和重复 id、平板不放录制中心；手机底栏、再点关注发出刷新信号、只剩一个菜单时没有底栏；平板侧栏、录制中心动作、没有菜单的提示；打开直播间带房间参数、已下线平台被拒、返回 |
