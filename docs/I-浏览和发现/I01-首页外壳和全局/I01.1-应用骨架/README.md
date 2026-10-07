# I01.1 应用骨架：入口、路由、首页外壳、多语言、Android 和 Windows 原生部分

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构，含原生）
- 来源：模块重构计划（D-001：在 3.x 的代码上逐块重构）；3.x 的 `lib/main.dart`、`lib/common/global/initialized.dart`、`lib/routes/`、`lib/modules/home/`、`menu_button.dart`、`common_appbar_actions.dart`、`windows_multi_instance_launcher.dart`、`app_path_manager.dart`、`locale_helper.dart`、`android/`、`windows/`
- 旧编号：M12、T07a.1
- 相关：J02.1（3.x 数据导入、密钥库）；之后的 I01.2（共用模块和外壳接线）、I01.3（应用服务）、L01.2（网络电视列表持久化）、O03.1（插件和 Windows 桌面外壳）、H02.1（录制接入）；提交 `6e2376d6e`；记录 [record.md](record.md)

## 目标

建出新的 Flutter 应用 `apps/pure_live`，让后面每个页面任务只换自己的目录就能接上：一个启动流程建好全部服务（存储、33 个平台、弹幕、媒体中继）并经 provider 交给页面；路由路径、首页菜单、多语言的用法和 3.x 完全一样；Android 包名能和用户手机上的 3.x 并存（开发版加 `.v4dev`），Windows 单实例。修掉审查出的 3.x 问题（13 条），不改 3.x 的界面。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 启动 | `lib/common/global/initialized.dart`（176 行）全局单例 `AppInitializer`，服务靠 GetX 注册，页面到处 `Get.find` | `lib/app/bootstrap.dart` 一次性建 `AppServices`，经 Riverpod 的 `appServicesProvider` 下发 | 同；之后加了启动失败页（`app/launch_failure.dart`）、图片解码缓存按内存调（`bootstrap.dart:34`）、录制（`:199`） |
| 应用外壳 | `lib/main.dart`（210 行）`GetMaterialApp`，`Obx` 读设置 | `MaterialApp.router` + `watchSetting` | `lib/app/app.dart:41` `PureLiveApp` |
| 路由 | `lib/routes/route_path.dart`、`app_pages.dart`（`Get.arguments[0]` 无类型，`:105` 没参数时崩） | `RoutePath` 原样；go_router；每个路径一个页面类，参数在 `RouteArgs.arguments` | `lib/routes/app_router.dart:42` `pageRoutes`；页面从当时的 `lib/pages/` 挪到了 `lib/features/` |
| 导航 | `app_navigation.dart`，打开直播间等 `Get.toNamed` 返回（直播间开着时别处打不开房间） | `AppNavigator` 同名方法，防重复只挡 0.5 秒 | `lib/routes/app_navigator.dart` |
| 首页 | `lib/modules/home/`，宽 > 680 平板 | `lib/home/`，外观照 3.x | 挪到 `lib/features/home/`；侧栏从 600 开始（A06.2） |
| 多语言 | easy_localization；语言两个来源；缺中文时显示键名 | `lib/i18n/i18n.dart`：`i18n()` 同名同参；一个来源；缺键回退 | 同 |
| Android 包名 | debug 和正式版同包名，开发时会覆盖用户的 3.x | debug、profile 加 `.v4dev` 和“纯粹直播 v4dev” | 同（Z04） |
| `MainActivity` | `AudioServiceActivity` | 改成 `FlutterActivity`（后台播放还没做） | 又改回 `AudioServiceActivity`（`MainActivity.kt:88`，C01.2：后台播放和划掉应用后继续录要它缓存引擎） |
| 多窗口 | `--config-file` 交接带 Cookie 明文的完整备份，每个窗口一份数据 | 交接改成密钥另用 DPAPI 封装、`restoreAll` 导入 | A16.1 c14 取消交接：所有窗口共用数据目录，`instances\<id>` 只放日志（`data_root.dart:9-31`、`launch_args.dart:9-14`） |
| Windows 单实例 | 原生层只拦无参数启动，带参数的交给插件 | `runner/main.cpp` 按窗口 id 一律拦截 | 同 |
| Firebase | `google-services`、`firebase_*` | 去掉 | 同 |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：启动七步（参数、数据目录、密钥、存储、3.x 导入、`wire` 建平台和弹幕、后台身份迁移）；`AppServices` 和 provider；go_router 路由表和 `AppNavigator`；首页外壳（底栏、侧栏、菜单、再点关注刷新、后台 15 秒回来刷新、命令行房间、返回键退到后台）；多语言；主题和刷新率策略的接线；Android 原生（包名后缀、`AppChannelsPlugin`：密钥、原生 HTTP、GBK、组播锁）；Windows 原生（单实例、DPAPI 和 GBK 走 FFI）。
- 修了审查出的 3.x 问题 13 条（record.md“审查发现的 v3 问题”），例如：翻译缺键显示键名、语言两个来源、新窗口交接带 Cookie 明文、单实例两层各管一半、分区房间没参数就崩、路由观察者直接调播放器、Kotlin 目录和包名不一致、debug 会覆盖 3.x、Android 收组播没持有锁。
- 有意差异 4 条：首页的标签和路由用同一个页面类；打开直播间防重复只管 0.5 秒；提示用浮动提示条；不读 SharedPreferences 的 `locale`。
- 已批准的升级：X-1（Kick 在 Android 走原生 HTTP，E03.16）完成；B-2（握手不带 `Dart/` 前缀）只留了开关（`app/platforms.dart:245` 编译参数 `PURE_LIVE_PLAIN_WS_UA`，默认关），真机逐平台验证在 Q03.1；17-1、23-1、抖音 room_id 换 web_rid 的身份迁移接上；B-13、B-6、默认编码、2-1、8-3 读设置。
- 提交 `6e2376d6e`（2026-10-01）；新第三方包 `flutter_riverpod` 3.4.3、`go_router` 18.0.2、`url_launcher`、`win32_registry`（3.x 同款）等；去掉 easy_localization、GetX、flutter_smart_dialog、windows_single_instance、move_to_desktop、Firebase 等。
- 测试 23 个（当时）：`launch_args_test.dart` 5、`i18n_test.dart` 4、`platforms_test.dart` 9、`home_test.dart` 5。

## 验证

- 自动测试：现在 `test/features/home/home_test.dart` 15 个、`test/launch_args_test.dart` 4 个（新窗口交接的用例随 A16.1 c14 删掉）、`test/i18n_test.dart` 6 个、`test/platforms_test.dart` 11 个。
- 真机：当时“本次不往手机装”（record.md“构建”）。之后 S02.2 冒烟（[记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)）在 K90 上走过冷启动、首页四个目的地、语言、返回键退到后台；Android Keystore 加解密靠 3.x 登录信息的导入在 S02.3、S04 覆盖安装验证里走过。Windows 没在主机上构建过（X01）。

## 留下的问题

- record.md“放到其他模块的部分”现在的去向：录制原生部分 → H02.1（完成）；录制设置读写 → J02.1、H01.2（完成）；后台播放和 `AudioServiceActivity` → C02（完成）；Windows 桌面外壳 → O03.1、A16.1（完成）；Twitch 无界面 WebView → E03.2（`platform/twitch_webview_http.dart`）；分享和深链 → O03.1（完成）；字体、日志 → I01.3（完成）；Windows 构建和实机检查 → X01（没做，D-004）；Android 真机检查 → S02。
- B-2 的默认开 → Q03.1。
- 代码注释里“`lib/pages/`”“M13 替换”已过时（`routes/app_router.dart:39-41`、`routes/route_args.dart:7-8`、`features/home/home_page.dart:21-23`）→ Z 组注释清理（见[子分类说明](../README.md)“已知问题”）。
