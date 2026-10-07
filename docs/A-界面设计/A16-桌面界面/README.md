# A16 桌面界面

桌面窗口、标题栏、托盘、窗口内全屏。

一句话：Windows（以后 Linux）窗口本身的样子和操作：自绘标题栏、窗口大小和位置、托盘、点 ✕ 时的选择、“在新窗口打开”和多个窗口共用数据、第二次启动。

## 范围

- 包括（A16.1）：标题栏（高 32、图标、“纯粹直播 · 主播名”、最小化 / 最大化或向下还原 / 关闭、改大小时“[宽 × 高]”、全屏和小窗时藏起来）、系统窗口菜单、关闭窗口对话框（含录制中的提示）、托盘图标和菜单、窗口大小和位置的记忆、最小窗口 360×400、在新窗口打开、新窗口和主窗口共用数据、第二次启动把主窗口带到前面。
- 不包括（归哪里）：
  - Windows 专属功能（开机启动、安装包、自动更新等）的实现和验证在 [X01 Windows](../../X-多端客户端/X01-Windows/README.md)；Linux 在 [X02](../../X-多端客户端/X02-Linux/README.md)；macOS 的窗口按钮在左上、菜单栏在 [A18.2](../A18-苹果平台界面/A18.2-macOS差异设计/README.md)。
  - 设置里的“关闭窗口时”“开机窗口尺寸”“新建独立播放窗口”这几行在 [A11.4](../A11-设置界面/A11.4-通用和网络/README.md)；直播间菜单里的“在新窗口打开”这一项在 [A07](../A07-直播间界面/README.md)；桌面小窗（应用内小窗的置顶）在 [A07.8](../A07-直播间界面/A07.8-小窗/README.md)。
  - 窗口内全屏（直播间在窗口里铺满）属于直播间的横屏全屏（[A07.4](../A07-直播间界面/A07.4-横屏全屏/README.md)），这里只管全屏时标题栏藏起来。

## 现状：做到哪、怎么工作的

- **用户看得到的**（Windows，代码完成、没在 Windows 真机上看）：标题栏底色跟页面（表面色，深色不是纯黑），图标和名字点一下或右键弹系统窗口菜单，空白处拖动、双击最大化；三个按钮 46×32、悬停 0.5 秒显示名称、关闭悬停红底；进直播间标题栏写“纯粹直播 · 晚风”，任务栏和 Alt+Tab 写“晚风 - 纯粹直播”。点 ✕：“关闭窗口 / 退出应用，还是最小化到托盘继续运行？”，左“最小化到托盘”、右红底“退出应用”，下面“不再询问”和“以后可以在设置 → 通用 → 关闭窗口时里改”；正在录制时退出总会先问并写“正在录制 N 个直播间”。托盘：左键显示，右键菜单（录制中第一行灰色“正在录制 N 个直播间”），提示“纯粹直播 · 正在录制 2 个”。第一次打开 1280×720 居中，之后记住大小、位置、最大化；位置不在任何显示器上回到正中。
- **内部怎么工作**：
  - `DesktopShell`（`apps/pure_live/lib/app/desktop/desktop_window.dart:227`）在启动时摆窗口（`supported` 现在只看 `Platform.isWindows`，:257；最小 360×400，:261），记大小到 3.x 的 `window_width` / `window_height`、位置和最大化到 `meta`（`window.position`、`window.maximized`，:188、:192）；`DesktopWindow`（:48）给页面用：窗口动作、最大化状态、能不能开新窗口（`offersNewWindow` :89 = 有桌面外壳且设置“新建独立播放窗口”开）、`openNewWindow`（:94）。
  - 标题栏 `DesktopTitleBar`（`title_bar.dart:34`）在 `DesktopFrame`（:318）里，主播名取路由观察器的最上面一页（`roomNameOf` :15，`LiveRouteObserver.topPage`），系统窗口标题 `nativeWindowTitle`（:25）。
  - 关闭 `WindowCloser`（`close_dialog.dart:48`）：读 `dontAskExit` + `exitChoose`，问 `CloseWindowDialog`（:170），录制个数来自 `AppRecording.activeCount`；托盘 `DesktopTray`（`tray.dart:49`）。
  - 多窗口共用数据：所有窗口用同一个数据文件夹（`app/data_root.dart`），数据库共用方式打开；别的窗口写了以后靠文件夹变化事件（`SharedDataWatch`，`shared_data.dart:16`，不轮询）调 `LiveStore.syncExternal()` 重新读；新窗口的录制任务单独存 `recorder.tasks.<窗口 id>`。
  - Windows 运行器：`apps/pure_live/windows/runner/main.cpp` 给主窗口加属性 `PureLive.PrimaryWindow`，第二次启动按属性找主窗口带到前面（标题会变，不能按标题找），`win32_window.cpp` 在 `WM_DESTROY` 时去掉属性。
- **完成度**：A16.1 完成（2026-10-01 合并）。c2（Linux）代码按“有没有桌面外壳 / 托盘 / 能不能开新窗口”写，但桌面外壳只在 Windows 启动、仓库里没有 `linux/` 运行器；c12 的直播间菜单那一半没有接上（见“已知问题”）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/desktop/desktop_window.dart` | 窗口动作接口 `WindowControls`（:26）、页面用的 `DesktopWindow`（:48）、位置和最大化的记录键（:188、:192）、外壳 `DesktopShell`（:227：启动摆窗口、最小尺寸、记几何、托盘、关闭、共用数据）、位置的解析（:567～:583）、开机启动状态（:590） |
| `apps/pure_live/lib/app/desktop/title_bar.dart` | 主播名（:15）、系统窗口标题（:25）、标题栏 `DesktopTitleBar`（:34：图标按钮 :207、三个窗口按钮 :243、改大小时的尺寸）、外框 `DesktopFrame`（:318，给标题栏自己的浮层，标题栏不随系统字体放大） |
| `apps/pure_live/lib/app/desktop/close_dialog.dart` | 关闭动作 `CloseAction`（:11）、关闭流程 `WindowCloser`（:48）、对话框 `CloseWindowDialog`（:170）、录制提示 `_RecordingNote`（:310） |
| `apps/pure_live/lib/app/desktop/tray.dart` | 托盘菜单的行 `TrayRow`（:10）、`trayMenuRows`（:25）、提示（:41）、`DesktopTray`（:49） |
| `apps/pure_live/lib/app/desktop/shared_data.dart` | 数据文件夹的变化事件 `SharedDataWatch`（:16）、哪些是数据库文件（:67） |
| `apps/pure_live/lib/app/desktop/mini_window.dart` | 桌面小窗的大小和位置（A07.8 的窗口部分） |
| `apps/pure_live/lib/app/desktop/startup_entry.dart` | 开机启动的注册表项（设置“开机启动”，A11.4） |
| `apps/pure_live/lib/app/data_root.dart`、`launch_args.dart` | 数据文件夹（所有窗口共用、新窗口的日志在 `instances\<id>\logs`）；启动参数和开新窗口进程（`startWindowProcess` :108；旧的 `launchNewWindow` :115 还在，直播间菜单在用） |
| `apps/pure_live/lib/routes/route_observer.dart` | `LiveRouteObserver.topPage`（最上面的页面，不算菜单和对话框） |
| `apps/pure_live/lib/features/home/menu_button.dart` | 首页菜单“新建独立播放窗口”（:84 调 `DesktopWindow.openNewWindow`） |
| `apps/pure_live/windows/runner/main.cpp`、`win32_window.cpp` | 单实例、按窗口属性找主窗口 |
| `packages/live_store`（`StoreDatabase.file(shared:)`、`LiveStore.syncExternal()`、`SettingsStore.reload()`） | 多个进程共用一个数据库：等待对方写完、判断别的进程写过、重新读并通知监听者 |
| `packages/live_ui`（`AppIcons.windowMinimize` 等、`WindowButtonColors.closeHover`、`LiveSemanticColors.recordingNote`） | 窗口按钮图标、关闭红、录制提示的浅红底 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/desktop_window_test.dart` | 标题栏 9 个（按钮顺序和位置、名称、向下还原、关闭红、窗口菜单、拖动和双击、尺寸提示、底色、主播名、360×400 加 1.5 倍字体、1920×1080）、关闭对话框 5 个、关闭流程 6 个、托盘 1 个、窗口 3 个（拔掉显示器回正中、新窗口入口、最上面的页面）、共用数据 1 个、首页菜单 1 个 |
| `apps/pure_live/test/launch_args_test.dart` | 新窗口共用数据文件夹、日志和录制任务列表是自己的、旧的 `--config-file` 不再读取 |
| `packages/live_store/test/shared_store_test.dart` | 两个进程打开同一个文件：自己的写入不算、设置变化只报告一次、关注刷新、登录和退出、写入和重读交错、同时写不失败 |
| `apps/pure_live/test/plugins_test.dart` | 原有的标题栏和插件测试 |

## 3.x 基线

- 窗口和标题栏：`git show v3.2.11:lib/common/global/platform/desktop_manager.dart`（848 行）：窗口选项和 Mica `:48-99`、托盘 `:139-239`、`CustomTitleBar` `:263-381` 和 `:540-580`；托盘服务 `lib/common/global/platform/desktop_tray_service.dart`；关闭和 `_ExitDecisionDialog` `lib/plugins/utils.dart:16-108`、`:228-393`；窗口大小 `lib/common/utils/window_size_controller.dart`；多开 `lib/common/utils/windows_multi_instance_launcher.dart`（3.x 把全部设置和 Cookie 写到临时文件交给新窗口，v4 改成共用数据）；运行器 `windows/runner/main.cpp`（按标题“纯粹直播”找主窗口）。
- 必须保留（[specs/UI.md](../../specs/UI.md) 附录 A 第 15 条）：Windows 在新窗口打开直播间；小窗可选置顶。3.x 的 `window_width`、`window_height`、`dontAskExit`、`exitChoose`、`enableNewWindowPlay`、`windowsPipAlwaysOnTop` 键不变（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 直播间菜单的“在新窗口打开”还是旧做法：按平台（`windows` 参数）而不是设置显示，文字是旧的“在新窗口播放此直播间”、图标是 `AppIcons.newWindow`，调旧的 `launchNewWindow` | `apps/pure_live/lib/features/live_play/buttons/room_menu_button.dart:173`、`:257`、`:300` | 关掉设置“新建独立播放窗口”后直播间菜单里仍有这一项；文字、图标和 A16.1 c12 不一致 | A16.1 记录把接口交给了直播间任务，但没有登记任务；建议在 X01（Windows）开工前登记一个小任务，改调 `DesktopWindow.offersNewWindow` / `openNewWindow`、文字 `open_in_new_window`、图标 `AppIcons.newPlayerWindow` |
| 窗口大小设置的下限是 400×300（3.x），新的最小窗口是 360×400：窄于 400 的窗口下次打开是 400 宽 | `live_store` 的 `windowWidth` / `windowHeight` 定义 | 很窄的窗口不能原样恢复 | A16.1“需要决定的事”1，没有登记；改设置定义要先过 D-018 |
| 托盘菜单录制中只有一行（A16.1 设计），A18.2 写的是两行（加“录制中心…”） | `tray.dart` | 两个设计不一致 | A16.1“需要决定的事”2，A18.2 开发时一起定 |
| 新窗口的录制任务不在主窗口的录制中心里 | `recorder.tasks.<窗口 id>` | 两个窗口各录各的（和 3.x 一样） | 要合并需要只让主窗口录制，没有登记 |
| 桌面外壳只在 Windows 启动，仓库里没有 `linux/` 运行器 | `DesktopShell.supported` | Linux 版没有标题栏、托盘、单实例 | [X02.1](../../X-多端客户端/X02-Linux/README.md) |
| 系统窗口菜单的灰项、Alt+空格、拔显示器、按属性找主窗口、两个窗口同步、Windows 11 圆角都没在 Windows 上看 | Windows 真机 | 只有组件测试 | [X01.1](../../X-多端客户端/X01-Windows/README.md)、[X01.2](../../X-多端客户端/X01-Windows/README.md) |

## 相关决定和规范

- D-003（T1～T4 按建议 A，T3 = 新窗口和主窗口共用数据）、D-004（客户端顺序：Windows 第二，现在只做 Android，所以 A16.1 的真机验证等 X01）、D-018（窗口相关的 3.x 键不变）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（桌面窗口最小 360×400、记住大小位置和最大化）、第 5.4 节（悬停显示按钮名称、焦点框只在键盘时显示）、第 9.3 节（Windows 不用 Mica）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/desktop_window_test.dart test/launch_args_test.dart test/plugins_test.dart`；`cd packages/live_store && dart test test/shared_store_test.dart`。窗口动作用假的 `WindowControls`，测试里不开真窗口。
- 真机：要在 Windows 上构建（D-004，现在只做 Android），A16.1 记录的“没有在真机上看的”列出了要看的东西，等 [X01.1](../../X-多端客户端/X01-Windows/README.md) 一起看；S02 的 CHECKLIST 里没有 Windows 的条目。

## 路线

1. X01 开工前：把直播间菜单的“在新窗口打开”接到 `DesktopWindow`（上面第一条问题，小任务）。
2. [X01.1](../../X-多端客户端/X01-Windows/README.md)、[X01.2](../../X-多端客户端/X01-Windows/README.md)：在 Windows 上构建并按 A16.1 记录逐项看；顺带定窗口大小下限、托盘行数。
3. [X02.1](../../X-多端客户端/X02-Linux/README.md)：加 `linux/` 运行器后打开桌面外壳，做单实例。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`app/desktop/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A16.1 | 桌面窗口：标题栏、托盘、窗口内全屏 | 界面 | 完成 | 2026-10-01 | 99a8f8f53 | [设计或说明](A16.1-桌面窗口/README.md)、[记录](A16.1-桌面窗口/record.md)、[评审页](A16.1-桌面窗口/page/01-说明.jpg) |

<!-- docs:生成结束 -->
