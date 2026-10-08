# A06 首页和全局

应用打开后最先看到、一直在的那层外壳：启动页、首页（手机底部导航、宽屏侧边栏、各首页标签顶栏的菜单和搜索）、应用自己弹出的全局对话框（新版本、选择下载目录、下载安装包、口令导入）和它们的先后，以及 Android 状态栏和导航栏的样式。

## 范围

- 包括：
  - 启动页 `apps/pure_live/lib/features/splash/`（A06.4）。
  - 首页外壳 `apps/pure_live/lib/features/home/`：手机底部导航（A06.1）、宽屏侧边栏（A06.2）、左上“菜单”和右上“搜索 + 更多”两个按钮及它们弹出的小菜单（关注、热门、分区、录制中心四个标签的顶栏都用它们）。
  - 全局弹窗：新版本 `features/version/update_prompt.dart`、选择下载目录 `features/version/download_directory_dialog.dart`、下载安装包 `features/version/update_download.dart`、口令导入 `shared/rooms/room_prompt.dart`，以及启动后提示的排队 `shared/app_prompts.dart`（A06.3、A06.4）。
  - 系统栏（状态栏、导航栏）的底色和图标深浅（A06.5）。
- 不包括（归哪里）：
  - 首页四个标签页的内容：关注 A09.3、热门 A09.2、分区 A09.4、录制中心页面 A10.1；房间卡片 A09.1。
  - 首页的功能和数据：应用骨架、路由、关注核验和刷新在 I01（I01.1、I01.2）；“导航栏显示控制”设置页在 A11。
  - 版本页、关于页和“检查更新”按钮在 A15.2（它们复用这里的新版本、下载对话框）。
  - 口令和分享的识别逻辑（读剪贴板、解码分享口令、系统分享接收）在 O03.2（`app/intake/`），这里只管它弹出的对话框和排队。
  - Android 系统启动画面、通知、启动图标在 A14.1；桌面标题栏、托盘、“新建独立播放窗口”打开的窗口本身在 A16.1；电视首页外壳在 A17.2；苹果平台差异在 A18。
  - 键盘焦点、读屏文字、电脑上二级页面按 Esc 返回在 A05.1。

## 现状：做到哪、怎么工作的

**用户看得到的行为**

- 冷启动：设置“启动动画”（`showSplashPage`，默认开）开着时先进启动页：图标 150、“欢迎使用”（20 号 600）、主色进度条，0.4 秒淡入（0.9→1 放大、不回弹），背景是主题表面色带一点主色容器色；1 秒后（点一下、电脑上按任意键立即）离开，离开前最多再等 0.35 秒关注核验，然后进首页。关着时直接进首页。
- 首页（宽度 <600，手机排法）：底部 `NavigationBar` 四项（关注 `Remix.heart_3`、热门 `Remix.fire`、分区三个形状 `Remix.shapes`、录制中心 `Remix.download_2`），显示和顺序照设置“导航栏显示控制”（`savedMenuIds`），只剩一项时不显示导航栏；再点“关注”刷新关注；各标签顶栏左边“菜单”（设置、关于、备份与恢复，Windows 开着“新建独立播放窗口”时多一项），右边“搜索”（点一下进搜索页）和“更多”（观看记录、链接解析、多画面；多画面关掉时没有）；录制中心标签顶栏右边是打开文件夹、设置、搜索、更多。
- 首页（宽度 ≥600，宽屏排法）：左侧自绘的侧边栏（宽 80）：最上面菜单，下面四个带名称的工具按钮（搜索直播、观看记录、链接解析、多画面），一条短分隔线，再下面四个导航项（录制中心也是导航项，在首页里切换，不盖住窗口）；窗口矮时只有上面的菜单和工具按钮滚动，导航项一直看得见；页面顶栏不再显示菜单和搜索按钮。跨过 600 拉窗口时页面状态保留。
- 首页按系统返回：应用退到后台，不退出（`moveTaskToBack`）；从后台回来、离开超过 15 秒：450 毫秒后通知当前标签刷新。
- 首页出现 2 秒后自动检查更新（设置“自动检查更新”开着、版本没被“不再提醒”）：“发现新版本 v…”对话框只在首页在最上面时弹，有口令导入在等时排在它后面；“下载并安装”直接在应用里下载本机的安装包（挑最快的下载源，失败换下一个），先查“安装未知应用”权限，再问下载目录，再开下载对话框（八种状态，取消和失败保留已下载的部分）。
- 剪贴板或系统分享里识别到直播间（O03.2）：弹“打开分享的直播间”（头像、标题、“主播 · 平台中文名 · 房间号”，“取消”“进入房间”），和新版本同一时间只开一个，它先。
- Android 系统栏：首页第一帧后设状态栏透明、`edgeToEdge`；启动页用 `AnnotatedRegion` 设状态栏透明和图标深浅，但带着 Flutter 常量里的黑色导航栏和浅色导航栏图标（A06.5 待核对）。

**内部怎么工作**

```text
main → app/bootstrap.dart → PureLiveApp（app/app.dart）
  └ _buildRouter：splashInitialLocation(settings) → /splash 或 /home（routes/app_router.dart:76、:91-102）
SplashPage（features/splash/splash_page.dart）
  └ 1 秒计时 / 点按 / 按键 → _leave：等 AppStartup.followCheck 最多 splashFollowWait → AppNavigator.offAllNamed(/home)
HomePage（features/home/home_page.dart）
  ├ LayoutBuilder → isHomeRailWidth(宽) ? HomeTabletView : HomeMobileView（home_views.dart）
  ├ HomeLayoutScope(phone:) → 各标签页 showsHomeBarButtons → MenuButton / CommonAppBarActions（menu_button.dart）
  ├ HomeSignals.favoritesReselected / resumedAfterBackground → 关注、热门、分区页监听
  └ 第一帧后：启动参数里的直播间 → AppNavigator.toLiveRoomDetail；主窗口 2 秒后 checkForUpdateOnStartup
checkForUpdateOnStartup（features/version/update_prompt.dart:34）
  └ AppPrompts.instance.show(update, ready: 首页在最上面) → NewVersionDialog → showUpdateDownload
       → ensureDownloadDirectory（update_download.dart:125）→ DownloadDirectoryDialog → UpdateDownloadDialog
app/intake/system_intake.dart → ClipboardRoomWatcher / ShareIntake → showRoomPrompt（shared/rooms/room_prompt.dart:25）
  └ AppPrompts.instance.show(share) → RoomPromptDialog → 进入房间
```

- `AppPrompts`（`shared/app_prompts.dart:26`）是应用自己弹的提示的队列：同一时间只开一个，`AppPromptKind.share` 排在 `update` 前面；每次路由变化（`liveRouteObserver`）和一个提示关掉一帧后重新看等着的提示的 `ready`。
- 首页标签页一律用全局键保存（`home_page.dart:135-138`），所以跨 600 换排法时不重建；导航栏显示控制里没有可用项时显示全部四项（`home_menu.dart:51-54`）。

**完成度**（和 3.x 对照）

- 一致的：底部导航四项的图标、文字、只剩一项不显示、再点关注刷新、返回键回桌面、回前台 15 秒刷新、启动动画开关和 1 秒 + 0.35 秒的时序、启动 2 秒后检查更新、下载前先查安装权限再问目录、同一时间一个下载、口令导入的内容（A06.1 c1、A06.2 c1、A06.3 c1、A06.4 c1）。
- 确认过的改动（用户 2026-10-01 确认，选择按建议 A）：观看记录挪到“更多”、右上拆成搜索 + 更多、两个菜单同一个小菜单组件、分区图标换成三个形状（A06.1 c2～c7）；600 起侧边栏、工具按钮带名字、录制中心成导航项（A06.2 c2～c7）；新版本标题带版本号、“不再提醒这个版本”、应用内直接下载、下载对话框有“关闭”和失败重试（A06.3 c2～c11）；启动页跟主题、动画 0.4 秒、提示排队（A06.4 c2～c7）。
- 还缺的：A06.5 系统栏样式和 3.x 核对（未开始）；A06.4 c8 系统启动画面同底色交给 A14.1；苹果平台的更新方式交给 X、A18。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/splash/splash_page.dart` | 启动页 `SplashPage`（`:31`）：`splashInitialLocation`（`:16-17`，按 `showSplashPage` 选起点）、0.4 秒动画（`:42`、`:49-55`）、离开时等关注核验（`:72-82`）、点按和按键跳过（`:84-88`、`:108`）、系统栏 `AnnotatedRegion`（`:95-98`）、主题渐变背景（`:109-124`） |
| `apps/pure_live/lib/features/home/home_page.dart` | 首页 `HomePage`（`:36`）：第一帧后设系统栏和 `edgeToEdge`（`:58-67`）、启动参数里的直播间和更新检查（`:69-71`）、回前台刷新（`:94-112`）、再点关注刷新（`:114-120`）、返回键退到后台（`:122-131`）、按宽度选排法（`:141-160`）、四个标签页（`buildHomeTab` `:165-170`） |
| `apps/pure_live/lib/features/home/home_menu.dart` | `HomeMenu` 四项（`:6-38`）、分界 `homeTabletBreakpoint = 600`（`:42`）和 `isHomeRailWidth`（`:45`）、`visibleHomeMenus`（`:51-54`）、`HomeLayoutScope`（`:58-71`）、`showsHomeBarButtons`（`:76-79`，各标签页决定顶栏要不要菜单和搜索）、`HomeSignals`（`:83-95`） |
| `apps/pure_live/lib/features/home/home_views.dart` | 手机排法 `HomeMobileView`（`:14`，只剩一项不显示导航栏 `:34`）、侧边栏尺寸 `HomeRailMetrics`（`:55-69`：宽 80、菜单行 68、工具行 66、分隔 21、导航项 68）、宽屏排法 `HomeTabletView`（`:80`，上面滚动、导航项固定的算法 `:129-147`）、侧边栏的项 `_RailItem`、`_RailTool`、`_RailDestination` |
| `apps/pure_live/lib/features/home/menu_button.dart` | 左上菜单 `AppMenuItem`（`:15`）和 `MenuButton`（`:50`）；右上 `HomeAction`（`:92`：搜索、观看记录、链接解析、多画面）和 `CommonAppBarActions`（`:131`：搜索按钮 + “更多”菜单） |
| `apps/pure_live/lib/features/version/update_prompt.dart` | 启动检查 `checkForUpdateOnStartup`（`:34`，2 秒 `startupUpdateCheckDelay` `:19`，排队和 `ready`）、`NewVersionDialog`（`:108`，`newVersionWideFrom = 480` `:97` 起“不再提醒”和按钮同一行） |
| `apps/pure_live/lib/features/version/update_download.dart` | `showUpdateDownload`（`:74`，同一时间一个下载 `_active` `:90`）、`ensureDownloadDirectory`（`:125`）、下载状态 `UpdateDownloadPhase`（`:170`）、上下排的字体倍数 1.5（`:183`）、`UpdateDownloadDialog`（`:191`） |
| `apps/pure_live/lib/features/version/download_directory_dialog.dart` | 选择下载目录 `showDownloadDirectoryDialog`（`:20`）、`DownloadDirectoryDialog`（`:30`） |
| `apps/pure_live/lib/shared/rooms/room_prompt.dart` | 口令导入 `showRoomPrompt`（`:25`）、`RoomPromptDialog`（`:44`）；`RoomPromptChoice` 只有进入和取消（`:9-15`） |
| `apps/pure_live/lib/shared/app_prompts.dart` | 提示队列 `AppPromptKind`（`:9`）、`AppPrompts`（`:26`） |
| `apps/pure_live/lib/app/app.dart` | 选起点（`:118-121`）；`MaterialApp.builder` 里把应用内小窗 `FloatingRoomLayer` 盖在所有页面上（`:231`，A07.8） |
| `apps/pure_live/lib/app/intake/system_intake.dart` | 剪贴板和系统分享识别后调 `showRoomPrompt`（`:36-41`，O03.2） |
| `apps/pure_live/lib/routes/app_router.dart` | `/splash`（`:76`）、`/home`（`:100-102`） |
| `packages/live_ui/lib/src/widgets/app_menu.dart` | 首页两个菜单用的小菜单 `showAppMenu`、`AppMenuButton`（A06.1 c2 新加，A02 维护） |
| `packages/live_ui/lib/src/widgets/dialog_keys.dart`、`dialog_buttons_theme.dart` | 对话框的回车、Esc 和 14 号按钮字（A06.3 新加） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` | `pure_live/app` 通道的 `moveToBack`（`:251`，首页返回键） |
| `apps/pure_live/android/app/src/main/res/values/styles.xml`、`values-night/styles.xml` | 原生主题的导航栏透明（`:17`，A06.5 核对） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/home/home_test.dart`（15 个） | 菜单的存取和去重；手机底部导航四项的顺序和图标、再点关注刷新；顶栏菜单、搜索、更多的顺序、图标、位置和点击区域；Windows 的“新建独立播放窗口”条件；录制中心标签顶栏；600 起侧边栏（599 是底部导航）、侧边栏从上到下的顺序；横屏手机导航项不被挤出屏幕；字体 1.3 倍不溢出；跨 600 不重建页面；启动参数进直播间；启动页开关和启动接线 |
| `apps/pure_live/test/features/splash/splash_page_test.dart`（7 个） | 起点按设置；1 秒后进首页；点按、按键跳过；0.4 秒内只增不回弹；尺寸和间距；深浅色背景跟主题 |
| `apps/pure_live/test/features/version/update_dialogs_test.dart`（10 个） | 新版本的标题、按钮、宽窄排法、横屏日志滚动、“不再提醒”、等首页在最上面才弹；下载的各状态、标题、按钮、取消保留部分文件；下载目录的提问和取消 |
| `apps/pure_live/test/shared/app_prompts_test.dart`（5 个） | 一次一个、口令导入在前、没到时机等路由变化；口令导入的内容、窄屏和大字体头像在上、横屏最宽 400 |
| `packages/live_ui/test/app_menu_test.dart`、`dialog_support_test.dart` | 小菜单的尺寸、颜色、位置、上方弹出、Esc；对话框按钮 14 号、回车、Esc |

## 3.x 基线

- 首页（`git show v3.2.11:lib/modules/home/home_page.dart`）：`:232` 父组件宽度 >680 用宽屏排法；`:187-191` 再点关注刷新；`:218-222` 返回键 `MoveToDesktop`；`:141-165` 回前台超过 15 秒刷新；`:99-104`、`:198-216` 第一帧后 2 秒检查更新；`:73-80` 第一帧后设状态栏透明、导航栏颜色取 `navigationBarTheme`。手机排法 `mobile_view.dart:28-64`（四项图标）、`:68`（只剩一项不显示）；宽屏排法 `tablet_view.dart:95-170`（`NavigationRail`、菜单、多画面、链接解析、搜索、录制中心按钮）。
- 顶栏按钮：`lib/common/widgets/menu_button.dart`（左上菜单，`:35-61`）、`common_appbar_actions.dart`（右上搜索菜单，`:32-72`）；关注、热门、分区页按整屏宽度 `Get.width <= 680` 决定要不要显示（`favorite_page.dart:17` 等）。
- 启动页：`lib/modules/splash/splash_screen.dart:50-58`（2 秒动画）、`:86-111`（图标、文字、进度条）；`lib/routes/app_pages.dart:188-235`（青色渐变、1 秒、0.35 秒等关注核验）；`main.dart:197` 选起点。
- 全局弹窗：`lib/modules/about/widgets/version_dialog.dart:26-86`（检查更新）、`lib/plugins/update.dart`（下载流程，`:81-146`）、`lib/common/widgets/download_directory_dialog.dart:17-64`、`download_apk_dialog.dart:489-702`、`share_command_import_dialog.dart`；口令识别的时机 `lib/common/global/platform/desktop_manager.dart:595-650`。
- 系统栏：`lib/common/global/initialized.dart:131` 启动时调 `MobileManager.initialize()`（`lib/common/global/platform/mobile_manager.dart:7-58`：`edgeToEdge`、状态栏和导航栏透明、分隔线透明、导航栏图标固定深色、四个方向）。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条卡片长按或右键是操作菜单（首页各标签的卡片，A09.1）；第 15 条 Windows 在新窗口打开（左上菜单的“新建独立播放窗口”，A06.1 c1）；第 17 条回到前台时识别剪贴板中的分享口令（口令导入对话框和排队在这里，识别在 O03.2）。另外 3.x 的首页习惯：再点“关注”刷新、返回键回桌面而不退出、回前台 15 秒以上刷新，都已保留并有测试。
- 详细的 3.x 样子、问题和文件对照：[inventory/V3_UI.md](../../inventory/V3_UI.md) 第 1 节（首页外壳）；逐项界面：[inventory/UI.md](../../inventory/UI.md) 的 A06.1～A06.4。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理（任务编号或“不做”） |
|---|---|---|---|
| 启动页的 `AnnotatedRegion` 用 Flutter 的 `SystemUiOverlayStyle.light/dark`，带黑色导航栏和浅色导航栏图标，首页不改回；3.x 启动时全局设透明、图标固定深色，v4 没有对应代码 | `features/splash/splash_page.dart:95-98`、`features/home/home_page.dart:58-67` | 浅色主题下三键导航可能看不清，导航栏可能是一条黑带（待 K90 截图确认） | A06.5 |
| 宽屏首页、下载对话框、启动页没有在真机上看过（S02.2 冒烟只看了手机首页的底部导航和冷启动 198 毫秒） | — | 平板侧边栏、应用内更新的下载流程、启动页的观感只有组件测试 | 应用内更新归 S02.4 第 5 节第 4 条；宽屏首页等有平板时再看（S03.1） |
| Android 默认下载目录在 `Android/data` 下，系统文件管理器打不开，“打开文件夹”会走“打开文件夹失败”并写出文件位置 | `features/version/update_download.dart:191` 的 `UpdateDownloadDialog`（下载完成后“打开文件夹”失败的状态行） | 设计里就是这个状态，用户能看到路径 | 不做（设计确认的样子，A06.3 偏差 1） |
| 选的下载目录没有写入权限时只提示，不像 3.x 那样打开应用设置页（`SystemAccess` 没有打开应用设置的方法） | `features/version/update_download.dart:125` 起的 `ensureDownloadDirectory` | 用户要自己去系统设置授权 | 无任务（要加原生方法时并进 O 组） |
| 应用内小窗为了躲开首页底部导航，另存了一份 600 的分界（功能目录之间不能互相引用） | `features/live_play/logic/mini_window.dart:127` 的 `homeRailMinWidth`，对应 `features/home/home_menu.dart:42` | 改首页分界时要两处一起改，否则小窗离底边的距离不对 | 无任务（改分界时一起改；或挪到 `shared/`） |
| iOS、macOS 的更新方式（有没有安装包、走不走下载对话框）没定 | `features/version/` | 苹果平台以后才构建 | A18.1、A18.2 和 X |

## 相关决定和规范

- D-001：3.x 的界面和操作是基线；D-003：设计里“需要你选的”按建议 A（A06.1 X1～X3、A06.2 Y1～Y3、A06.3 Z1～Z2、A06.4 K1～K2 都是 A）；D-004：只做 Android（Windows 第二），电视和苹果平台以后。
- D-011：首页各标签的标题位置照 3.x 实际运行的样子（录制中心、热门、分区居中）。
- D-015：`assets/version.json`、`assets/releases.json` 留在 master（3.x 从这里检查更新，新版本对话框读的也是这条线路）。
- D-018：3.x 的设置键名不变；这里新加的只有 `skippedUpdateVersion`（本机，不进备份），`downloadDirectoryDecisionMade` 沿用 3.x 的键。
- specs/UI.md 第 5.3 节：导航紧凑用底部导航、中等以上用侧边栏（A06.2 把分界从 680 改成 600 的依据）；第 7 节：弹窗四种（这里的四个都是居中对话框，照 3.x 弹法）；第 8.6 节：动效 250–350 毫秒、不回弹（启动页动画）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/home test/features/splash test/features/version test/shared/app_prompts_test.dart`；`live_ui` 的小菜单和对话框测试在 `packages/live_ui/test/`。覆盖了排法分界、按钮顺序和图标、菜单内容、字体放大、提示排队、新版本和下载的全部状态。
- 缺的：系统栏样式没有测试（A06.5 阶段 2 加）；首页回前台 15 秒刷新和返回键退到后台只在 Android 生效，Linux 上的测试跑不到（A06.1 记录）。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 19 条（F-APP-23 状态栏和导航栏，A06.5）、第 4 节第 1 条（冷启动、再点关注刷新、后台 20 秒回来刷新）、第 4 节第 11 条（剪贴板口令弹“进入直播间”）、第 5 节第 4 条（应用内更新的下载和安装）。已经看过的：[S02.2](../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（首页底部四个导航、冷启动 198 毫秒）。

## 路线

1. **A06.5**（第二档）：先在 K90 上截启动页、首页、二级页面、直播间退出全屏后的系统栏（浅色深色 × 手势导航和三键导航）；有差别再改成启动时按主题设一次、启动页不再带黑色导航栏。依赖：无。
2. 应用内更新的真机验证跟着 S02.4（装一个版本号更低的测试包，走一遍“下载并安装”）。
3. 以后：苹果平台的更新入口（A18、X）；电视首页外壳（A17.2）复用这里的新版本对话框的电视样式。新想法（例如首页加“观看记录”标签）先进 V01。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/home/`、`features/splash/`、`app/`
- 进度：`██████████████████░░` 89%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A06.1 | 手机首页 | 界面 | 完成 | 2026-10-01 | 6e00ef1dc | [设计或说明](A06.1-手机首页/README.md)、[记录](A06.1-手机首页/record.md)、[评审页](A06.1-手机首页/page/01-说明.jpg) |
| A06.2 | 宽屏首页 | 界面 | 完成 | 2026-10-01 | 6e00ef1dc | [设计或说明](A06.2-宽屏首页/README.md)、[记录](A06.2-宽屏首页/record.md)、[评审页](A06.2-宽屏首页/page/01-说明.jpg) |
| A06.3 | 全局弹窗 | 界面 | 完成 | 2026-10-01 | 6e00ef1dc | [设计或说明](A06.3-全局弹窗/README.md)、[记录](A06.3-全局弹窗/record.md)、[评审页](A06.3-全局弹窗/page/01-说明.jpg) |
| A06.4 | 启动页 | 界面 | 完成 | 2026-10-01 | 6e00ef1dc | [设计或说明](A06.4-启动页/README.md)、[记录](A06.4-启动页/record.md)、[评审页](A06.4-启动页/page/01-说明.jpg) |
| A06.5 | 状态栏和导航栏样式和 3.x 核对：3.x 启动时全局设透明，v4 启动页留下黑色导航栏和浅色导航栏图标 | 界面 | 未开始 | — | — | [设计或说明](A06.5-首页状态栏和导航栏颜色/README.md)、[任务书](A06.5-首页状态栏和导航栏颜色/brief.md)、[记录](A06.5-首页状态栏和导航栏颜色/record.md) |

## 还没完成的

- **A06.5 状态栏和导航栏样式和 3.x 核对：3.x 启动时全局设透明，v4 启动页留下黑色导航栏和浅色导航栏图标**（未开始，第二档，规模 小）
  - 阶段：K90 截图核对 → 启动时按主题设系统栏，启动页不再带黑色导航栏
  - 说明：读代码（V03.3）：3.x 的 MobileManager.initialize 启动时设透明、分隔线透明、导航栏图标固定深色；v4 没有对应代码，启动页的 AnnotatedRegion 用 Flutter 的 SystemUiOverlayStyle.light/dark（带黑色导航栏、浅色图标），首页不改回。先在 K90 截图确认（上一次没留下来的核对记过“首页导航栏是主题色、3.x 是透明”），没有差别就只改清点
  - 来源：V03.3 功能清点 F-APP-23

<!-- docs:生成结束 -->
