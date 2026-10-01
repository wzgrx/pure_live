# U.13 桌面窗口

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.13/README.md](../compare/U.13/README.md)（第 1 版，用户已确认；T1～T4 按建议 A）；计划书 [UI_PLAN.md](../UI_PLAN.md) 第 3 节（第 7 条）、第 5.3 节（桌面窗口最小 360×400）、第 9.3 节（Windows 不用 Mica）；跨任务：U.17b → U.13（托盘菜单录制中的行）
- 范围：自绘标题栏、窗口大小和位置、托盘、关闭时的选择、在新窗口打开（含新窗口和主窗口共用数据）、第二次启动、桌面小窗置顶的入口
- 改动的目录：`apps/pure_live/lib/app/desktop/`（`desktop_window.dart`、`title_bar.dart`、`tray.dart`，新文件 `close_dialog.dart`、`shared_data.dart`）、`apps/pure_live/lib/app/`（`bootstrap.dart`、`data_root.dart`、`launch_args.dart`、`recording.dart`）、`lib/main.dart`、`lib/platform/recording_platform.dart`（只加一个参数）、`lib/routes/route_observer.dart`（只加“最上面的页面”）、`lib/features/home/menu_button.dart`（首页菜单“新建独立播放窗口”的条件，c12）、`packages/live_ui`（只做添加）、`packages/live_store`（只做添加，见下）、翻译文件、Windows 原生、文档
- 没有改 `features/settings/`（设置行是 U.6d 的）和 `features/live_play/`（直播间菜单在 U.2b～U.2d 手里，只提供接口，见“给其他任务的接口”）
- 原生：改了 Windows 运行器（见“Windows 原生改动”），需要在 Windows 上构建；没有改 Android 原生

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留：标题栏高 32、图标 16 + “纯粹直播”13 号 600、拖动、双击最大化、三个按钮 46×32、关闭悬停红底、改大小时“[宽 × 高]”、全屏和小窗时藏起来；托盘左键显示、右键菜单；点 ✕ 时问；只开一个、再点图标带到前面；新窗口是独立进程、带着直播间 | ✅ | 拖动和双击改成自己的手势区（原来用 window_manager 的 `DragToMoveArea`，测试里没法换掉），行为相同。“只开一个”是原有的 `main.cpp` 互斥量，找主窗口的方法改了（c11） |
| c2 | Linux 同一个标题栏；系统里的窗口名“纯粹直播”；只开一个 | ⚠️ 代码完成 | 标题栏、托盘、关闭、新窗口都只看“有没有桌面外壳 / 有没有托盘 / 能不能开新窗口”，不看平台名；窗口名由 `WindowOptions.title` 设成“纯粹直播”（Linux 上同样生效）。**桌面外壳现在只在 Windows 启动**（`DesktopShell.supported`，Linux 版 M12.6 暂停）；仓库里没有 `linux/` 运行器，“只开一个”（GApplication 不用 `NON_UNIQUE`、激活时带到前面）要等 M12.6 加运行器时做 |
| c3 | 最大化以后中间换成“向下还原”（`filter_none`）；三个按钮悬停显示名称 | ✅ | `DesktopWindow.maximized` 跟着 window_manager 的最大化 / 还原事件；名称用 `Tooltip`（停 0.5 秒出现），`DesktopFrame` 用 `Overlay.wrap` 给标题栏一个自己的浮层（v3 因为标题栏在导航器外面没有名称）。文字“最小化 / 最大化 / 向下还原 / 关闭” |
| c4 | 底色跟页面：浅色、深色都是表面色；启动页同一个底色 | ✅ | 一律 `colorScheme.surface`、字 `onSurface`（深色不再纯黑）；启动页顶部本来就是表面色（U.3c c3 的渐变在右下角），所以标题栏不再单独画渐变 |
| c5 | 去掉 Mica | ✅ | v4 本来就没有（运行器和 Dart 都没开），这次没有改动 |
| c6 | 记住大小、位置、最大化；位置不在任何显示器上回到正中；第一次 1280×720 居中；最小 360×400 | ✅（有偏差） | 最大化记在 `meta` 的 `window.maximized`（新），启动时先摆好位置再最大化；位置不在显示器上时调 `center()`（原来是不设位置，停在运行器的 10,10）。只有主窗口记，新窗口不记（数据共用，免得把主窗口的大小改掉）。偏差：大小仍存在 3.x 的 `window_width` / `window_height`，这两个设置的下限是 400×300（live_store 只做添加，没有改），窗口拖到 360 宽时记成 400 宽，见“需要决定的事”1 |
| c7 | 标题“关闭窗口”、“退出应用，还是最小化到托盘继续运行？”、左“最小化到托盘”、右“退出应用”；没有托盘时“最小化”到任务栏 | ✅ | `close_dialog.dart` 的 `CloseWindowDialog`：宽 440，左文字按钮、右红底白字（`colorScheme.error`），两端对齐；没有托盘时问题换成“…最小化到任务栏继续运行？”。点外面、Esc 等于取消 |
| c8 | “不再询问”下面一行小字告诉在哪里改 | ✅（设置行交给 U.6d） | “以后可以在“设置 → 通用 → 关闭窗口时”里改”，12 号次要色，和“不再询问”左对齐。设置里显示记住的选择是 U.6d 的 |
| c9 | 正在录制时退出先确认：红色提示（勾了不再询问也问）；托盘“退出应用”同样先问；托盘提示和菜单第一行显示“正在录制 N 个直播间” | ✅ | 录制个数 = 本窗口录制器里“准备中、录制中、重连中、合并中”的任务（`AppRecording.activeCount`）。勾了不再询问、记住“最小化”时直接最小化（录制照常，不问）；记住“退出”时照样弹框，“不再询问”保持勾着。托盘退出：先显示窗口再问（对话框没有“不再询问”，见偏差 2）。托盘提示“纯粹直播 · 正在录制 2 个”，菜单第一行灰色“正在录制 2 个直播间”加分隔线；个数变化时只改提示，菜单在打开前刷新（照 v3）。退出时先停录制器（最多等 3 秒），已录的部分照录制器原有的方式保存 |
| c10 | 只有主窗口有托盘；新窗口 ✕ 直接关，录制时先问 | ✅ | 新窗口录制时弹同一个对话框（没有托盘的写法：“最小化”到任务栏 / “退出应用”，没有“不再询问”） |
| c11 | 标题栏“纯粹直播 · 晚风”，任务栏和 Alt+Tab“晚风 - 纯粹直播”；主窗口进直播间也这样 | ✅ | 主播名取最上面的页面（直播间路由的参数 `LiveRoom.nick`）；菜单、对话框盖在上面不算页面。`route_observer.dart` 加了 `topPage`。换直播间（路由替换）跟着变；主播名为空（只有房间号打开、详情还没回来）时只显示“纯粹直播”——直播间页面在 U.2b～U.2d 手里，没有加“详情回来后更新”的钩子。Windows 运行器找主窗口不再按标题（标题会变），改按窗口属性（见“Windows 原生改动”） |
| c12 | 两个入口都跟设置“新建独立播放窗口”；直播间菜单叫“在新窗口打开”、图标 `add_to_photos`、放在“在哔哩哔哩打开”后面；Linux 也有 | ⚠️ 首页完成、直播间菜单交出 | 首页菜单改成 `DesktopWindow.canOpenNewWindow` 加设置（原来 `Platform.isWindows`），点了调 `DesktopWindow.openNewWindow()`。直播间菜单的改动在 `features/live_play/`，按任务书不动，接口和文字已备好（下节）；`AppIcons.newWindow` 改图标是 U.1b 的（只做添加，没有改它的值） |
| c13 | 图标和名字不再打开浏览器；点图标、右键标题栏弹系统窗口菜单 | ✅ | 图标 24×24 点击区、悬停圆角 4 浅底；左键、右键都弹菜单；名字和空白处右键弹菜单（`windowManager.popUpWindowMenu()`，Windows 用系统菜单，Linux 用 GTK 的 `gdk_window_show_window_menu`） |
| c14 | 新窗口和主窗口共用同一份关注、历史和设置（T3 选 A） | ✅ | 没有退到“拿不准的地方”第 5 条。做法见下面“共用数据” |
| c15 | 桌面小窗置顶的入口：图钉和设置同一个开关 | ✅ | U.2j 已做，这次没有改；数据共用后两个窗口的“小窗始终置顶”也是同一个值 |

偏差和原因：

1. **大小的下限**：见 c6 和“需要决定的事”1。
2. **从托盘退出时的对话框没有“不再询问”**：托盘退出是“已经选了退出”，只为录制确认；如果在这里勾“不再询问”，会改掉 ✕ 的行为，容易误会。新窗口的对话框同样没有。
3. **托盘菜单第一行没有红点**：系统画的菜单只放文字（tray_manager 的菜单项图标要图片资源，这次没加），灰色不可点。U.17b 写的“录制中的两行（正在录制、录制中心…）”和本任务确认的设计（一行）不一致，照 U.13 做了一行，见“需要决定的事”2。
4. **标题栏不随系统字体放大**：窗口外框用 `MediaQuery.withNoTextScaling`，32 高放得下；页面照常放大。
5. **按钮的键盘焦点**：照 v3 加 2 像素主色框，只在用键盘时显示。

### 按钮的作用和用法

| 编号 | 控件 | 做到 | 说明 |
|---|---|---|---|
| 1 | 图标 | ✅ | 点一下弹窗口菜单 |
| 2 | 名字和空白处 | ✅ | 拖动、双击最大化 / 还原、右键窗口菜单；贴靠和拖到顶上最大化由系统处理（`startDragging` 走系统的移动） |
| 3–5 | 最小化、最大化 / 向下还原、关闭 | ✅ | 窗口拒绝时提示“窗口操作失败，请重试” |
| 6–8 | 不再询问、最小化到托盘、退出应用 | ✅ | 照 3.x：选择总是存下（`exitChoose` + `dontAskExit`），动作失败时放回原来的值；记住的动作失败时下次重新问 |
| 9–11 | 托盘图标、显示 / 隐藏窗口、退出应用 | ✅ | |
| 12 | 在新窗口打开 | ⚠️ | 首页的“新建独立播放窗口”完成；直播间菜单交给 U.2b～U.2d |
| — | 键盘 | ✅（系统） | Alt+F4 走同一个关闭；Alt+空格、Win+方向键是系统的（隐藏标题栏后系统菜单还在），没在真机上看 |
| — | 第二次打开 | ✅ | `main.cpp`：找带主窗口属性的窗口，藏在托盘里也显示出来 |

### 共用数据（c14）

- 所有窗口用同一个数据文件夹（`resolveDataRoot` 不再给新窗口 `instances\<id>`），新窗口只有日志写在 `instances\<id>\logs`。字体、直播源文件、下载、默认录制文件夹也随之共用（原来新窗口里看不到主窗口下载的字体）。
- 数据库以“共用”方式打开（`LiveStore.open(shared: true)`：写入时等对方最多 5 秒，不直接失败）。
- 别的窗口写了以后：数据文件夹的文件变化事件（数据库和它的日志文件，没有轮询）→ 停 0.2 秒 → `LiveStore.syncExternal()`：用 SQLite 的 `data_version` 判断是不是别的进程写的（自己的写入不算），是就重新读设置和登录信息、通知所有表的监听者（关注、历史、分组、屏蔽词、直播源列表都会刷新）。窗口回到前台时再查一次。
- 只由主窗口做的：3.x 导入（原来就是）、关注按主播合并、直播源自动同步、记住窗口大小和位置。
- 录制：每个窗口还是自己录。新窗口的任务列表存在 `recorder.tasks.<窗口 id>`（两个窗口都整份写各自的列表，放一起会互相覆盖），窗口关闭时删掉；所以主窗口的录制中心看不到新窗口的任务（和 3.x、原来的 v4 一样）。
- 去掉了“交接文件”（3.x 把全部设置和 Cookie 写到临时文件交给新窗口，v4 原来加了封存；现在不需要），`--config-file` 参数不再读取，避免把旧副本写回共用数据。
- 两个窗口同时改同一项设置时，后写的为准；同一窗口里“读到一半自己又写了”的情况已处理（不会被旧值盖掉，有测试）。

## 给其他任务的接口

直播间菜单（U.2b～U.2d，`features/live_play/buttons/room_menu_button.dart`）的“在新窗口打开”：

```dart
// 显示条件（c12：跟设置走，不看平台名；Linux 有桌面外壳时也有）
DesktopWindow.offersNewWindow(settings)   // = canOpenNewWindow && enableNewWindowPlay
// 点了（失败时它自己提示“新窗口启动失败，请重试”，返回 false）
await DesktopWindow.openNewWindow(room: room);
```

- 文字：新加 `open_in_new_window`“在新窗口打开”（原来的 `open_room_in_new_window`“在新窗口播放此直播间”留着）；图标用 `AppIcons.newPlayerWindow`（`add_to_photos_outlined`），位置在“在哔哩哔哩打开”（`RoomMenuEntry.external`）后面。
- 原来的 `launchNewWindow(store, cipher, room:)` 还在（参数已经用不上），菜单改过去之前照常能用。

U.6d（设置 → 通用）：

- “关闭窗口时：询问 / 最小化到托盘 / 退出应用”合成一项：询问 = `dontAskExit` 关；另外两项 = `dontAskExit` 开、`exitChoose` 为 `minimize` / `exit`。对话框里的小字已经指向“设置 → 通用 → 关闭窗口时”。
- “开机窗口尺寸”默认 1280 × 720；最小 360 × 400（`DesktopShell.minimumSize`），存的设置下限见“需要决定的事”1。
- “新建独立播放窗口”的说明改成“首页菜单和直播间菜单里显示‘在新窗口打开’”。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `common/global/platform/desktop_manager.dart:48-99`（窗口选项、Mica） | `app/desktop/desktop_window.dart`（`DesktopShell._start`） |
| `desktop_manager.dart:263-381`、`:540-580`（`CustomTitleBar`） | `app/desktop/title_bar.dart`（`DesktopTitleBar`、`DesktopFrame`） |
| `desktop_manager.dart:139-239`、`common/global/platform/desktop_tray_service.dart` | `app/desktop/tray.dart`（`DesktopTray`、`trayMenuRows`） |
| `plugins/utils.dart:16-108`、`:228-393`（退出、`_ExitDecisionDialog`） | `app/desktop/close_dialog.dart`（`WindowCloser`、`CloseWindowDialog`） |
| `common/utils/window_size_controller.dart` | `desktop_window.dart`（`_saveGeometry`、`resizing`、`maximized`） |
| `common/utils/windows_multi_instance_launcher.dart`、`common/utils/app_path_manager.dart:140-141` | `app/launch_args.dart`（`startWindowProcess`）、`app/data_root.dart`、`app/desktop/shared_data.dart`、`live_store` 的 `syncExternal` |
| `common/base/desktop_components.dart` | 没有对应（3.x 的桌面通用小部件，宽屏页面已由各任务重做） |
| `windows/runner/main.cpp` | `apps/pure_live/windows/runner/main.cpp` |

## 新设置

没有新的设置项。`meta` 里新加两类记录（不进备份）：

| 键 | 值 | 说明 |
|---|---|---|
| `window.maximized` | `1` / `0` | 主窗口上次是否最大化（c6） |
| `recorder.tasks.<窗口 id>` | 任务列表 JSON | 新窗口自己的录制任务，关窗口时删除（c14） |

3.x 的 `window_width`、`window_height`、`dontAskExit`、`exitChoose`、`enableNewWindowPlay`、`windowsPipAlwaysOnTop` 照旧生效，键没有改。

## `live_ui`、`live_store` 和其他共用部分（只做添加）

| 内容 | 说明 |
|---|---|
| `AppIcons.windowMinimize`、`windowMaximize`、`windowRestore`、`windowClose` | 3.x 的 `remove`、`crop_square`，新的 `filter_none`，`close` |
| `WindowButtonColors.closeHover`、`onCloseHover` | `#E81123` 和白（3.x，Windows 的关闭红） |
| `LiveSemanticColors.recordingNote(brightness)` | 录制提示的浅红底（浅色 `#FCEEEE`、深色 `#3A1A18`），字用主题的 `error`，对比度测试 ≥4.5 |
| `StoreDatabase.file(shared:)`、`busyTimeout`、`dataVersion()`、`notifyAllTables()` | 共用打开、判断别的进程写过、通知所有表 |
| `SettingsStore.reload()`、`SecretStore.reload()` | 重新读，只报告变了的；为了不被旧值覆盖，`setAll`、`reset`、`resetAll`、`writeAll` 内部加了写入计数（行为不变） |
| `LiveStore.open(shared:)`、`LiveStore.syncExternal()` | 见“共用数据” |
| `LiveRouteObserver.topPage` | 最上面的页面（不算菜单、对话框） |
| `AppRecording.activeCount`、`activeCounts`、`tasksKey`；`recorderTasksKeyFor`、`activeRecordings` | 录制个数、新窗口自己的任务列表 |
| `DesktopWindow.controls`、`maximized`、`newWindowLauncher`、`canOpenNewWindow`、`offersNewWindow`、`openNewWindow` | 标题栏的窗口动作、在新窗口打开 |

去掉的：`NewWindowHandoff`、`LaunchArgs.configFile` / `configFileFromArgs` / `configPrefix`（交接文件，c14 后不需要）；`resolveDataRoot` 的 `instanceId` 参数（改为 `instanceFolder`）。

## Windows 原生改动（请在 Windows 上构建）

- `windows/runner/main.cpp`：主窗口创建后加窗口属性 `PureLive.PrimaryWindow`；第二次启动时 `EnumWindows` 找类名 `FLUTTER_RUNNER_WIN32_WINDOW` 且带这个属性的窗口带到前面（原来 `FindWindowW` 按标题“纯粹直播”找，进了直播间标题变成“晚风 - 纯粹直播”就找不到了）；找不到时退回按标题找。
- `windows/runner/win32_window.cpp`：`WM_DESTROY` 时 `RemovePropW` 去掉这个属性。

## 门禁

- `check_ui_structure.py` 通过；功能目录直接写的颜色和图标没有变化（`home` 仍是 0），基线不用改。`app/desktop/` 不在门禁范围里，这次也把原来的 `Colors.*`、`Icons.*`、`Color(0xFFE81123)` 换成了 `live_ui` 的角色和 `AppIcons`（`app/desktop/` 10 处 → 0）。
- 没有新增功能之间的引用；首页引用 `app/desktop/desktop_window.dart`（外壳，不是功能目录）。

## 测试

- 新增 `test/desktop_window_test.dart` 26 个：
  - 标题栏 9 个：1280×800 按钮顺序、图标、位置（各 46×32 贴右边）、图标 16、名字 13 号 600；三个按钮的名称、最大化后“向下还原”和它的名称（出现在按钮下方、页面上面）；关闭悬停红底白叉；点图标、右键名字和空白处弹窗口菜单，单击名字不做事，双击最大化，拖动移动窗口；改大小时“[1280 × 800]”，全屏和小窗时藏起来；浅色、深色底色是表面色（深色不是纯黑），启动页同色；直播间里“ · 晚风”、任务栏名“晚风 - 纯粹直播”，对话框盖上去不变，退出直播间恢复，没有主播名时不显示；最小窗口 360×400 加 1.5 倍系统字体不溢出、一行；1920×1080 按钮贴右。
  - 关闭对话框 5 个：文字、两端按钮、红底白字、小字位置和颜色、勾选后返回；Esc 和点外面取消；录制中红色提示（位置、颜色、底色）、“不再询问”保持勾着；没有托盘时的文字和“最小化”、不显示“不再询问”；360×400 深色 1.5 倍字体不溢出。
  - 关闭流程 6 个：主窗口问、执行、存选择、取消不做事；不再询问直接做（有托盘藏起、没有托盘最小化）；录制中退出照样问、记住最小化时不问；窗口拒绝时放回原值并提示，记住的动作失败后下次重问；新窗口直接关、录制时问且没有“不再询问”、最小化到任务栏；托盘退出（不录制直接退，录制时先显示窗口再问）。
  - 托盘 1 个：菜单各行、文字、提示。
  - 窗口 3 个：记住的位置在拔掉的显示器上时回到正中、最小 360×400；新窗口入口跟能力和设置走、把直播间交给新窗口、失败提示（附录 A 第 15 条“在新窗口打开直播间”）；“最上面的页面”不算菜单和对话框。
  - 共用数据 1 个：另一个窗口写了设置，本窗口靠文件夹事件收到（不轮询）。
  - 首页菜单 1 个：有桌面外壳且设置开时有“新建独立播放窗口”（文字、图标），点了开新的首页窗口；设置关掉后没有。
- `launch_args_test.dart`：两个交接文件的测试（“只导入启动器写的交接文件”“新窗口带着数据和 Cookie”）删掉，换成“新窗口共用数据文件夹，日志和录制任务列表是自己的、旧的 `--config-file` 不再读取”1 个。原因：c14 改成共用数据，交接文件去掉了。
- `live_store` 新增 `test/shared_store_test.dart` 6 个（两个进程打开同一个文件：自己的写入不算、设置变化只报告一次、关注监听者刷新、登录和退出登录、写入和重读交错不丢新值、两边同时写不失败），共 39 → 45 个。
- `live_ui` 新增 1 个（关闭红和录制提示的对比度），`AppIcons` 对照表加 4 个图标；共 67 → 68 个。
- `apps/pure_live` 全部测试 413 个通过（这次之前 388 个：加 26 + 1、删 2）；`flutter analyze` 无问题；`check_ui_structure.py` 通过。`plugins_test.dart` 原有的标题栏测试没有改，照样通过。
- 附录 A：第 15 条（Windows 在新窗口打开直播间）写成了测试；“小窗可选置顶”U.2j 已有测试。

## 没有在真机上看的

- Windows（需要构建）：系统窗口菜单的“还原 / 最大化”是否按当前状态变灰（window_manager 直接弹系统菜单）；Alt+空格；最大化记忆和拔显示器回正中；第二次启动按属性找主窗口（包括藏在托盘里）；托盘菜单灰色第一行；两个窗口同时开时设置、关注、登录是否马上同步（文件夹事件在 Windows 上是 `ReadDirectoryChangesW`）；Windows 11 无边框窗口的圆角。
- Linux：桌面外壳没有启动，以上都没看；Wayland 上拉边改大小、托盘随桌面环境，等 M12.6。

## 需要决定的事

1. **窗口大小设置的下限**：`window_width` / `window_height` 的下限是 400 / 300（3.x 的范围），新的最小窗口是 360×400。按“live_store 只做添加”没有改：窄于 400 的窗口下次打开是 400 宽；矮于 400 的旧值打开时按 400。要把下限改成 360 / 400 需要改设置定义（不是添加），U.6d 的“开机窗口尺寸”范围说明也跟着这个。
2. **托盘菜单录制中的行数**：U.13 确认的设计是一行灰色“正在录制 N 个直播间”；U.17b（macOS 菜单栏图标）写的是两行（“正在录制 N 个直播间”“录制中心…”），跨任务表里要求 U.13 和它一致。这次照 U.13 做了一行；要加“录制中心…”（点了显示窗口并进录制中心）告诉我。
3. **新窗口的录制任务不在主窗口的录制中心里**：数据共用后，录制任务列表仍然每个窗口一份（两个录制器同时整份写同一个列表会互相覆盖）。要合成一个录制中心，需要只让主窗口录制、新窗口把录制请求交给主窗口，这是更大的改动。
