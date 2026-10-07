# A16 桌面界面

Windows（以后 Linux）窗口本身的样子和操作：自绘标题栏、窗口大小和位置、托盘、点 ✕ 时的选择、“在新窗口打开”和多个窗口共用数据、第二次启动、窗口内全屏时藏起标题栏。

## 范围

- 包括（A16.1）：标题栏（高 32、图标、“纯粹直播 · 主播名”、最小化 / 最大化或向下还原 / 关闭、改大小时“[宽 × 高]”、全屏和小窗时藏起来）、系统窗口菜单、关闭窗口对话框（含录制中的提示）、托盘图标和菜单、窗口大小和位置的记忆、最小窗口 360×400、在新窗口打开、新窗口和主窗口共用数据、第二次启动把主窗口带到前面；登记的代码目录 `apps/pure_live/lib/app/desktop/`，加上 Windows 运行器 `apps/pure_live/windows/runner/`。
- 不包括（归哪里）：
  - Windows 专属功能（功能清点第 13 节的 F-WIN-01～14：开机启动、RTX 超分、动态刷新率等）的实现和验证、安装包、自动更新在 [X01 Windows](../../X-多端客户端/X01-Windows/README.md)；Linux 在 [X02](../../X-多端客户端/X02-Linux/README.md)；macOS 的窗口按钮在左上、菜单栏在 [A18.2](../A18-苹果平台界面/A18.2-macOS差异设计/README.md)。
  - 设置里的“关闭窗口时”“开机窗口尺寸”“新建独立播放窗口”“开机启动”这几行在 [A11.4](../A11-设置界面/A11.4-通用和网络/README.md)；直播间菜单里的“在新窗口打开”这一项在 [A07](../A07-直播间界面/README.md)（菜单本身，A16.1 只给接口）；桌面小窗（应用内小窗的大小、位置、置顶）在 [A07.8](../A07-直播间界面/A07.8-小窗/README.md)；首页的宽屏布局在 [A06.2](../A06-首页和全局/A06.2-宽屏首页/README.md)。
  - 窗口内全屏（直播间在窗口里铺满）属于直播间的横屏全屏（[A07.4](../A07-直播间界面/A07.4-横屏全屏/README.md)），这里只管全屏时标题栏藏起来；键盘鼠标操作的核对在 [X01.1](../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md)。
  - Windows 上没有系统通知、任务栏按钮（A14.1 c16）。

## 现状：做到哪、怎么工作的

- **用户看得到的**（Windows；代码完成、只有组件测试，**没在 Windows 上构建和看过**）：
  - 标题栏 32 高，底色跟页面（表面色，深色不是纯黑），不随系统字体放大；左边 16 的图标（24 的点击区，点一下或右键弹系统窗口菜单），“纯粹直播”13 号 600，进直播间写“纯粹直播 · 晚风”，任务栏和 Alt+Tab 写“晚风 - 纯粹直播”；空白处拖动、双击最大化 / 还原、右键窗口菜单；改大小时中间“[宽 × 高]”。右边三个按钮各 46×32，悬停 0.5 秒显示名称，最大化后中间换成“向下还原”，关闭悬停红底白叉（`#E81123`）。全屏和桌面小窗时标题栏藏起来。
  - 点 ✕：对话框“关闭窗口 / 退出应用，还是最小化到托盘继续运行？”，左“最小化到托盘”、右红底“退出应用”，下面“不再询问”和小字“以后可以在‘设置 → 通用 → 关闭窗口时’里改”；没有托盘时写“最小化到任务栏”。正在录制时多一块浅红提示“正在录制 N 个直播间”和说明，勾了不再询问、记住“退出”也照样问（记住“最小化”时直接最小化，录制照常）。
  - 托盘只有主窗口有：左键显示，右键菜单（录制中第一行灰色“正在录制 N 个直播间”、显示 / 隐藏窗口、退出应用），提示“纯粹直播 · 正在录制 2 个”；托盘退出时录制中先显示窗口再问（没有“不再询问”）。
  - 第一次打开 1280×720 居中，之后主窗口记住大小、位置、最大化；位置不在任何显示器上时回到正中；最小 360×400。
  - 首页菜单有“新建独立播放窗口”（有桌面外壳且设置开时），新窗口是独立进程、和主窗口共用关注、历史、设置，任何一个窗口改了别的窗口马上跟着变；新窗口点 ✕ 直接关（录制中先问）。第二次双击图标把主窗口带到前面（藏在托盘里也显示）。
- **内部怎么工作**：
  - 启动：`lib/main.dart:106` 调 `DesktopShell.start`；`DesktopShell`（`apps/pure_live/lib/app/desktop/desktop_window.dart:227`）只在 `supported`（`:257`，现在只看 `Platform.isWindows`）时启动，`_start`（`:286`）摆窗口（最小 `minimumSize` 360×400 `:261`；大小读 3.x 的 `window_width` / `window_height` `:289-290`；位置和最大化读 `meta` 的 `window.position`、`window.maximized` `:188`、`:192`；位置不在显示器上 `center()` `:308`，判断用 `titleRowOnScreen` `:567`），装上窗口动作、小窗宿主、新窗口启动器（`:318-321`）和共用数据监听（`:343`）。改大小、移动后 0.5 秒存（`_saveGeometry` `:514`，只有主窗口存）。
  - `DesktopWindow`（`:48`）给页面用：`fullScreen`（`:51`）、`resizing`（`:57`）、`maximized`（`:61`）、`controls`（`:65`）、`mini`（`:73`）、`newWindowLauncher`（`:80`）、`canOpenNewWindow`（`:85`）、`offersNewWindow`（`:89` = 有桌面外壳且设置“新建独立播放窗口”开）、`openNewWindow`（`:94`，失败提示“新窗口启动失败，请重试”）。窗口动作的接口 `WindowControls`（`:26`），真实实现 `_WindowManagerControls`（`:195`，系统菜单 `windowManager.popUpWindowMenu()` `:208`），测试里换成假的。
  - 标题栏：`lib/app/app.dart:238` 用 `DesktopFrame`（`title_bar.dart:318`）包住整个应用，`DesktopFrame` 用 `Overlay.wrap`（`:333`）给标题栏自己的浮层（悬停名称），全屏或小窗时不画标题栏（`:335-338`）；主播名 `roomNameOf`（`:15`）取 `LiveRouteObserver.topPage`（`routes/route_observer.dart:27`，菜单、对话框不算页面），系统窗口标题 `nativeWindowTitle`（`:25`），路由变化时 `app.dart:140` 调 `DesktopShell.relabel`（`desktop_window.dart:539`）。
  - 关闭：`WindowCloser`（`close_dialog.dart:48`）读 `dontAskExit` + `exitChoose`，问 `CloseWindowDialog`（`:170`），录制个数来自 `AppRecording.activeCount`（准备中、录制中、重连中、合并中），退出时先停录制器（最多等 3 秒）；托盘 `DesktopTray`（`tray.dart:49`），菜单行 `trayMenuRows`（`:25`），提示 `trayTooltip`（`:41`）。
  - 多窗口共用数据：所有窗口用同一个数据文件夹（`app/data_root.dart:21` 的 `resolveDataRoot`，便携版是程序旁的 `UserData` `:34`；新窗口只有日志在 `instances\<id>\logs`），数据库以共用方式打开（等对方写完最多 5 秒）；别的窗口写了以后靠文件夹变化事件（`SharedDataWatch`，`shared_data.dart:16`，不轮询，停 0.2 秒）调 `LiveStore.syncExternal()`，用 SQLite 的 `data_version` 判断是不是别的进程写的，再重读设置和登录、通知所有表的监听者；新窗口的录制任务单独存 `recorder.tasks.<窗口 id>`。新窗口由 `startWindowProcess`（`app/launch_args.dart:108`）启动，参数见 `LaunchArgs`（`:15`）；3.x 的交接文件（`--config-file`）不再读。
  - Windows 运行器：`apps/pure_live/windows/runner/main.cpp` 用互斥量只开一个（`:98`），给主窗口加属性 `PureLive.PrimaryWindow`（`:26`、`:131`），第二次启动用 `EnumWindows` 按属性找主窗口带到前面（`:43`，标题会变，不能只按标题找；找不到时退回按标题 `:47`）；`win32_window.cpp:190` 在 `WM_DESTROY` 时去掉属性。
- **完成度**（和 3.x 对照）：
  - 一致的：标题栏高度、图标和字号、拖动、双击最大化、三个按钮尺寸、关闭红、改大小时的尺寸提示；托盘左键显示、右键菜单；点 ✕ 时问和“不再询问”（`dontAskExit`、`exitChoose`）；只开一个；新窗口是独立进程、带着直播间；桌面小窗置顶（A07.8）；3.x 的窗口相关设置键都不变（D-018）。
  - 确认过的改动：A16.1 c1～c15（T1～T4 按建议 A，T3 = 新窗口共用数据），D-003。
  - 还缺：c2（Linux）代码按“有没有桌面外壳 / 托盘 / 能不能开新窗口”写，但桌面外壳只在 Windows 启动、仓库里没有 `linux/` 运行器；c12 的直播间菜单那一半没有接上；**没有任何 Windows 真机结果**（D-004：现在只做 Android），登记为“完成”和 PROCESS 不符（见“已知问题”）。

## 代码地图

| 文件 | 职责 | 设计 |
|---|---|---|
| `apps/pure_live/lib/app/desktop/desktop_window.dart`（599 行） | `WindowControls`（`:26`）、`DesktopWindow`（`:48`，页面用的状态和新窗口入口 `:85-94`）、记录键 `windowPositionKey`（`:188`）、`windowMaximizedKey`（`:192`）、`_WindowManagerControls`（`:195`）、`DesktopShell`（`:227`：`supported` `:257`、`minimumSize` `:261`、`_start` `:286`、最大化记录 `:485`、`_saveGeometry` `:514`、`relabel` `:539`）、`titleRowOnScreen`（`:567`）、`parseWindowPosition`（`:573`）、`formatWindowPosition`（`:583`）、`StartupEntryState`（`:590`，开机启动状态，A11.4） | A16.1 c2、c6、c10、c12、c14 |
| `apps/pure_live/lib/app/desktop/title_bar.dart`（345） | `roomNameOf`（`:15`）、`nativeWindowTitle`（`:25`）、`DesktopTitleBar`（`:34`：高 32 `:42`、按钮宽 46 `:45`、不随字体放大 `:55`、拖动和双击 `:73-74`、右键菜单 `:75`、尺寸提示 `:87-93`、关闭红 `:129`）、`_RoomName`（`:151`）、`_IconButton`（`:207`，16 的图标、24 的点击区）、`_WindowButton`（`:243`，悬停名称 `:311`）、`DesktopFrame`（`:318`，全屏和小窗时藏标题栏 `:331-338`） | A16.1 c1、c3、c4、c11、c13 |
| `apps/pure_live/lib/app/desktop/close_dialog.dart`（357） | `CloseAction`（`:11`）、`CloseChoice`（`:28`）、`CloseAsk`（`:31`）、`WindowCloser`（`:48`，主窗口 / 新窗口 / 托盘退出三种流程）、`showCloseWindowDialog`（`:155`）、`CloseWindowDialog`（`:170`，宽 440，“不再询问”`:216`、小字 `:267`、红底“退出应用”`:293`）、`_RecordingNote`（`:310`，浅红提示） | A16.1 c7～c10 |
| `apps/pure_live/lib/app/desktop/tray.dart`（169） | `TrayRow`（`:10`）、`trayMenuRows`（`:25`）、`trayRowLabel`（`:33`）、`trayTooltip`（`:41`）、`DesktopTray`（`:49`） | A16.1 c9 |
| `apps/pure_live/lib/app/desktop/shared_data.dart`（67） | `SharedDataWatch`（`:16`，数据文件夹变化 → 0.2 秒后 `syncExternal`）、`isDatabaseFile`（`:67`） | A16.1 c14 |
| `apps/pure_live/lib/app/desktop/mini_window.dart`（244） | 桌面小窗：`MiniWindowHost`（`:14`）、`miniWindowSize`（`:46`）、最小 140×90（`:62`）、`resolveMiniWindowBounds`（`:68`）、`desktopRefusesOnTop`（`:104`）、`WindowManagerMiniHost`（`:112`） | A07.8；A16.1 c15 |
| `apps/pure_live/lib/app/desktop/startup_entry.dart`（55） | 开机启动：注册表 `Run` 键（`:7`）、值名 `PureLiveV4`（`:12`，不碰 3.x 的）、`applyStartupEntry`（`:36`） | A11.4、X01.2 |
| `apps/pure_live/lib/app/data_root.dart`（110）、`launch_args.dart`（115） | `resolveDataRoot`（`data_root.dart:21`，所有窗口共用）、`instanceFolder`（`:17`，新窗口的日志）、`portableDataDir`（`:34`）；`LaunchArgs`（`launch_args.dart:15`）、`startWindowProcess`（`:108`）、旧的 `launchNewWindow`（`:115`，直播间菜单还在用，参数已用不上） | A16.1 c14 |
| `apps/pure_live/lib/app/app.dart` | 接线：`DesktopFrame` 包住应用（`:238`）、路由变化时 `relabel`（`:140`） | A16.1 c11 |
| `apps/pure_live/lib/main.dart` | `DesktopShell.start`（`:106`，传主窗口、录制、数据文件夹、窗口 id） | — |
| `apps/pure_live/lib/routes/route_observer.dart`（123） | `LiveRouteObserver.topPage`（`:27`，最上面的页面，不算菜单和对话框） | A16.1 c11 |
| `apps/pure_live/lib/features/home/menu_button.dart` | 首页菜单“新建独立播放窗口”：条件 `:56`（`canOpenNewWindow` + 设置）、点了 `DesktopWindow.openNewWindow`（`:84`） | A16.1 c12 |
| `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart` | 直播间菜单的“在新窗口打开”：还是旧做法（按 `windows` 参数 `:173`、旧文字和图标 `:300`、调 `launchNewWindow` `:257`） | A16.1 c12 没接上（见“已知问题”） |
| `apps/pure_live/lib/features/settings/settings_editors.dart` | “开机窗口尺寸”编辑框的下限 `max(设置下限, minimumSize)`（`:577-578`，即 400×400）、开机启动状态（`:1028`） | A11.4 |
| `apps/pure_live/windows/runner/main.cpp`、`win32_window.cpp` | 单实例互斥量、按窗口属性找主窗口（`main.cpp:26`、`:43`、`:131`）、`WM_DESTROY` 去掉属性（`win32_window.cpp:190`） | A16.1 c1、c11 |
| `packages/live_store`（`StoreDatabase.file(shared:)`、`LiveStore.open(shared:)`、`LiveStore.syncExternal()`、`SettingsStore.reload()`、`SecretStore.reload()`） | 多个进程共用一个数据库：等对方写完、判断别的进程写过、重新读并通知监听者 | A16.1 c14 |
| `packages/live_ui`（`AppIcons.windowMinimize`、`windowMaximize`、`windowRestore`、`windowClose`、`newPlayerWindow`；`WindowButtonColors.closeHover`；`LiveSemanticColors.recordingNote`） | 窗口按钮图标、关闭红、录制提示的浅红底 | A16.1 c1、c9 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/desktop_window_test.dart`（26） | 标题栏 9 个（按钮顺序和位置、名称、向下还原、关闭红、窗口菜单、拖动和双击、尺寸提示、底色、主播名、360×400 加 1.5 倍字体、1920×1080）、关闭对话框 5 个、关闭流程 6 个、托盘 1 个、窗口 3 个（拔掉显示器回正中、新窗口入口和附录 A 第 15 条、最上面的页面）、共用数据 1 个、首页菜单 1 个 |
| `apps/pure_live/test/launch_args_test.dart`（4） | 启动参数；新窗口共用数据文件夹、日志和录制任务列表是自己的、旧的 `--config-file` 不再读取 |
| `apps/pure_live/test/plugins_test.dart`（8） | 原有的标题栏和插件测试 |
| `packages/live_store/test/shared_store_test.dart`（6） | 两个进程打开同一个文件：自己的写入不算、设置变化只报告一次、关注刷新、登录和退出、写入和重读交错、同时写不失败 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/` 下（本机副本 `~/ref/v3ref/lib/`）：

- 窗口和标题栏：`common/global/platform/desktop_manager.dart`（848 行）：`DesktopManager`（`:44`），窗口选项 `WindowOptions`（`:57`，最小尺寸 `:59`）和 Mica / hudWindow 效果（`:80`、`:87`）、托盘（`:139-239`）、`CustomTitleBar`（`:263-381`）、标题栏的项目主页链接 `TitleBarProjectLink`（`:383`，点图标和名字打开浏览器，c13 去掉）、`WindowControlButton`（`:501-580`）。
- 托盘：`common/global/platform/desktop_tray_service.dart`（107）。
- 关闭：`plugins/utils.dart`（652）：`exitDesktopApplication`（`:16`）、`_minimizeOrHideDesktopWindow`（`:96`）、`_ExitDecisionDialog`（`:321-393`，“不再询问”和两个按钮）。
- 窗口大小：`common/services/settings/window_size_controller.dart`（355，最小 400×300 `:99-100`）。
- 多开：`common/utils/windows_multi_instance_launcher.dart`（190，把全部设置和 Cookie 写到临时文件交给新窗口，新窗口有自己的数据；v4 改成共用数据）。
- 运行器：`windows/runner/main.cpp`（按标题“纯粹直播”找主窗口 `:22`，互斥量 `:54`）；Linux `linux/my_application.cc:102`（每次另开一个进程）。
- 必须保留（[specs/UI.md](../../specs/UI.md) 附录 A 第 15 条）：Windows 在新窗口打开直播间；小窗可选置顶。3.x 的 `window_width`、`window_height`、`dontAskExit`、`exitChoose`、`enableNewWindowPlay`、`windowsPipAlwaysOnTop` 键不变（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A16.1 登记为“完成”，但**没有任何 Windows 真机结果**（Windows 没构建过；记录“没有在真机上看的”整节都没看） | A16.1 [record.md](A16.1-桌面窗口/record.md) | 不符合 PROCESS“完成要有真机结果” | 写进本单元报告；建议维护者决定改回“待真机”或并入 [X01.1](../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md) |
| 直播间菜单的“在新窗口打开”还是旧做法：按平台（`windows` 参数）而不是设置显示，文字是旧的“在新窗口播放此直播间”（`open_room_in_new_window`）、图标 `AppIcons.newWindow`，调旧的 `launchNewWindow` | `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart:173`、`:257`、`:300` | 关掉设置“新建独立播放窗口”后直播间菜单里仍有这一项；文字、图标和 c12 不一致 | 没有登记任务；建议 X01 开工前登记一个小任务：改调 `DesktopWindow.offersNewWindow` / `openNewWindow`、图标 `AppIcons.newPlayerWindow`、放在“在哔哩哔哩打开”后面 |
| A16.1 加的翻译键 `open_in_new_window`“在新窗口打开”因为直播间菜单没用上，被 `00f5edf18`（清理不用的键）删掉了 | `apps/pure_live/assets/translations/zh.json`、`en.json` | 上一条的小任务要重新加这个键 | 同上一条；D-024（以后清理先列清单） |
| 窗口大小设置的下限是 400×300（3.x），新的最小窗口是 360×400：窄于 400 的窗口存成 400 宽；“开机窗口尺寸”编辑框的下限是 400×400 | `packages/live_store/lib/src/settings/settings.dart:822-837`；`apps/pure_live/lib/features/settings/settings_editors.dart:577-578` | 很窄的窗口不能原样恢复 | A16.1“需要决定的事”1，没有登记；改设置定义要先过 D-018 |
| 托盘菜单录制中只有一行（A16.1 设计），A18.2 写的是两行（加“录制中心…”）；第一行没有红点 | `tray.dart:25` | 两个设计不一致 | A16.1“需要决定的事”2，A18.2 开发时一起定 |
| 新窗口的录制任务不在主窗口的录制中心里 | `recorder.tasks.<窗口 id>` | 两个窗口各录各的（和 3.x 一样） | A16.1“需要决定的事”3；要合并需要只让主窗口录制，没有登记 |
| 主播名为空（只用房间号打开、详情还没回来）时标题栏只写“纯粹直播”，详情回来后不更新 | `title_bar.dart:15`（取路由参数 `LiveRoom.nick`） | 少数情况下标题栏没有主播名 | 直播间页面没有钩子，没有登记 |
| 桌面外壳只在 Windows 启动，仓库里没有 `linux/` 运行器 | `desktop_window.dart:257` | Linux 版没有标题栏、托盘、单实例 | [X02.1](../../X-多端客户端/X02-Linux/X02.1-Linux构建和打包/README.md) |
| 代码注释里还用旧编号（`U.13`、`U.2j`、`M12.6`） | `title_bar.dart:331`、`desktop_window.dart` 等 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003（A16.1 的 T1～T4 由维护者按建议 A 定，T3 = 新窗口和主窗口共用数据）、D-004（客户端顺序：Windows 第二，现在只做 Android，所以 A16.1 的真机验证等 X01）、D-018（窗口相关的 3.x 键不变）、D-024（翻译键以后清理先列清单）。
- [specs/UI.md](../../specs/UI.md) 第 4 节（平台差异集中在 A16.1、A14.1、A18）、第 5.3 节（桌面窗口最小 360×400、记住大小位置和最大化）、第 5.4 节（悬停显示按钮名称、焦点框只在键盘时显示）、第 9.3 节（Windows 不用 Mica）；附录 A 第 15 条。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/desktop_window_test.dart test/launch_args_test.dart test/plugins_test.dart`；`cd packages/live_store && dart test test/shared_store_test.dart`。窗口动作用假的 `WindowControls`，测试里不开真窗口；缺：没有真的两个进程同时开窗口的测试（`shared_store_test.dart` 用两个连接模拟）、系统菜单和托盘是系统画的。
- 真机：要在 Windows 上构建（D-004，现在只做 Android）。A16.1 记录“没有在真机上看的”就是要看的清单：系统窗口菜单的灰项、Alt+空格、最大化记忆和拔显示器回正中、第二次启动按属性找主窗口（包括藏在托盘里）、托盘菜单灰色第一行、两个窗口同时开时设置 / 关注 / 登录是否马上同步、Windows 11 无边框窗口的圆角。S02 的 CHECKLIST 里没有 Windows 的条目；等 [X01.1](../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md)、[X01.2](../../X-多端客户端/X01-Windows/X01.2-Windows专属功能/README.md) 一起看（前提是 [X01.3](../../X-多端客户端/X01-Windows/X01.3-Windows安装包和自动更新/README.md) 第一阶段能在 Windows 上构建运行）。

## 路线

1. X01 开工前：登记并做直播间菜单的“在新窗口打开”（接到 `DesktopWindow`、重新加 `open_in_new_window` 键，小任务）。
2. [X01.3](../../X-多端客户端/X01-Windows/X01.3-Windows安装包和自动更新/README.md) 第一阶段能在 Windows 上构建后，[X01.1](../../X-多端客户端/X01-Windows/X01.1-键盘鼠标操作核对/README.md)、[X01.2](../../X-多端客户端/X01-Windows/X01.2-Windows专属功能/README.md) 按 A16.1 记录逐项看，补上真机结果；顺带定窗口大小下限、托盘行数（A18.2 开发前）。
3. [X02.1](../../X-多端客户端/X02-Linux/X02.1-Linux构建和打包/README.md)：加 `linux/` 运行器后打开桌面外壳（`supported` 加 Linux），做单实例。
4. 以后：新窗口的录制合进主窗口的录制中心（要先决定，V01 提议）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`app/desktop/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A16.1 | 桌面窗口：标题栏、托盘、窗口内全屏 | 界面 | 完成 | 2026-10-01 | 99a8f8f53 | [设计或说明](A16.1-桌面窗口/README.md)、[记录](A16.1-桌面窗口/record.md)、[评审页](A16.1-桌面窗口/page/01-说明.jpg) |

<!-- docs:生成结束 -->
