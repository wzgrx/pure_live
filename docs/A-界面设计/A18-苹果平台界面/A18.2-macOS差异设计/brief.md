# A18.2 macOS 差异：任务书

## 背景

- 来源：界面重做的苹果平台部分（旧编号 U.17b、T19b.1）。设计第 1 版 2026-10-01 评审确认（确认记录 `62391fdd2`），待选按建议 A（D-003）：关闭窗口照 Mac 的习惯——红色按钮和 ⌘W 只关窗口、应用留在程序坞继续录制，⌘Q 退出、录制中先确认（K1）；菜单栏图标默认显示、单色、点了出菜单、设置里可以关（K2）；菜单栏完整（文件、编辑、显示、播放、窗口、帮助，K3）；统一标题栏，窗口按钮放进应用顶上那一行（K4）。设计正文在本文件夹 [README.md](README.md)（界面清点表 A18.2-01～08、M1～M9、c1～c10、HIG 依据、快捷键、“交给其他任务的”），评审页导出在 `page/`。
- 设计写的时候 A16.1（Windows、Linux 的标题栏、托盘、关闭时的选择）还没设计，所以 README 以 v3 的 Windows 做法对照；**现在 A16.1 已完成**（登记的提交 `99a8f8f53`）：Mac 的关闭和托盘要和 A16.1 现在的 `app/desktop/` 对齐（同一组命令、录制中的提示同一句）。
- 现象：4.x 没有 macOS 客户端（没有 `macos/` 工程）；桌面外壳只在 Windows 启用（`apps/pure_live/lib/app/desktop/desktop_window.dart:257` 的 `DesktopShell.supported => Platform.isWindows`，注释“macOS is U.17b”）。
- 为什么现在做：第三档，客户端顺序的最后（D-004）。**本机没有 Mac**；开工要等有 Mac，并先有 macOS 的工程任务（X05 现在没有任务，见“需要维护者决定的”）。
- 半成品：没有。

## 目标和验收

1. （前提）有 macOS 工程，能在 Mac 上构建、打开首页和直播间。
2. （c2，K4 A）用系统的三个窗口按钮，不画自绘标题栏；应用顶上那一行（52～56 高）就是标题栏，三个按钮在这一行左边（左 20）垂直居中；首页侧边栏顶上让出这一行、菜单按钮下移；直播间顶栏的返回键右移到按钮右边；这一行空白处能拖动窗口，双击按系统设置缩放或最小化。
3. （c3）没有窗口毛玻璃，背景是应用的表面色。
4. （c4，K3 A）菜单栏中文、Mac 标准顺序：纯粹直播（关于、检查更新…、设置… ⌘,、服务、隐藏 ⌘H、隐藏其他 ⌥⌘H、全部显示、退出 ⌘Q）、文件（链接解析… ⌘L、多画面、关闭窗口 ⌘W）、编辑（撤销、重做、剪切、拷贝、粘贴、全选、搜索直播… ⌘F）、显示（关注 ⌘1、热门 ⌘2、分区 ⌘3、录制中心 ⌘4、历史记录 ⌘Y、返回 ⌘[、进入全屏幕 ⌃⌘F）、播放（直播间里可用：暂停、刷新 ⌘R、音量、显示弹幕、弹幕设置、纯音频、清晰度、线路、画面比例、录制、小窗、窗口内全屏）、窗口（系统的）、帮助（项目主页、更新日志）。
5. （c5）Cmd 快捷键就是菜单里的那一组，和 iPad（A18.1 c10）同一套；v3 的单键照旧。
6. （c6，K1 A）红色按钮和 ⌘W 只关窗口，录制和开播检测照常；点程序坞图标或菜单栏图标重新打开窗口；⌘Q、菜单“退出纯粹直播”、程序坞右键“退出”才退出，有录制或开播自动录时先问“要退出纯粹直播吗？正在录制 2 个直播间……”；Mac 上不显示“关闭窗口时”和“不再询问”。
7. （c7，K2 A）菜单栏图标单色、跟菜单栏深浅变；录制中右下角红点；左键、右键都出菜单：录制中时先列“正在录制 N 个直播间”“录制中心…”，然后“隐藏窗口 / 显示窗口”“退出纯粹直播 ⌘Q”；设置里可以关。
8. （c8）直播间里画面的全屏按钮、绿色按钮、⌃⌘F、菜单“进入全屏幕”是同一件事（画面铺满并进系统全屏空间）；用任何方式离开全屏空间，直播间同时退出全屏；其他页面里绿色按钮让整个窗口进全屏空间。
9. （c9）直播间同 Windows：小窗（桌面小窗时隐藏三个窗口按钮）、音量条、窗口内全屏。
10. （c10）版本页同 v3（macOS 通用 ZIP）；下载完只有一个按钮“在访达中显示”。
11. Windows、Linux、Android 的界面一点不变；`flutter test` 全部通过。

## 现状（读代码得出，写文件:行）

- 工程：`apps/pure_live/` 没有 `macos/`；3.x 的 `macos/Runner/`（`AppDelegate.swift`、`Base.lproj/MainMenu.xib`、`Configs/AppInfo.xcconfig`、`Release.entitlements`）在 4.x 没有。
- 桌面外壳（A16.1，只在 Windows）：`apps/pure_live/lib/app/desktop/desktop_window.dart`：`DesktopShell`（`:227`）、`supported`（`:257`）、`minimumSize` 360×400；`title_bar.dart:34` 的 `DesktopTitleBar`（自绘，Mac 不用它）；`tray.dart`：`TrayRow`（`:10`）、`DesktopTray`（`:49`）；`close_dialog.dart`：`CloseAction`（`:11`）、`WindowCloser`（`:48`）、`showCloseWindowDialog`（`:155`）、录制中的说明 `_RecordingNote`（`:310`）；`mini_window.dart:112` 的 `WindowManagerMiniHost`，macOS 上隐藏标题栏（`:166-199`）。
- 直播间：`features/live_play/player/player_controls.dart:55` 的 `RoomPlatform`（音量条、窗口内全屏只给 Windows、Linux、macOS 中的哪些，要核对）；快捷键 `features/live_play/live_play_page.dart:737-750`，没有 Cmd 组合；Cookie 编辑器有 ⌘S（`features/account/cookie_editor.dart:401`）。
- 设置：`settings_model.dart:200` 的 `isOtherDesktop`（Linux、macOS）；`settings_editors.dart:779` 在桌面（含 macOS）`exit(0)`；开机启动只在 Windows（`app/desktop/startup_entry.dart:36`）。
- 更新：`features/version/update_feed.dart:308` 认 `macos`；下载对话框 `features/version/update_download.dart:191` 的按钮没有 Mac 分支。
- 菜单栏：Dart 里没有 `PlatformMenuBar`（4.x 和 3.x 都没有）。

## 3.x 基线

- 原生：`git show v3.2.11:macos/Runner/AppDelegate.swift`（`:6` 最后一个窗口关了就退出）、`macos/Runner/Base.lproj/MainMenu.xib`（模板英文菜单，`:36` “Preferences…” 没接功能）、`macos/Runner/Configs/AppInfo.xcconfig:8`、`macos/Runner/Release.entitlements`（没有 `com.apple.security.network.server`）。
- Dart：`lib/common/global/platform/desktop_manager.dart:57-137`（`TitleBarStyle.hidden`、毛玻璃 `:85-92`、`setPreventClose` `:67`、托盘点击 `:213-239`、离开全屏空间不处理 `:729`、⌘Q `:765-768`）、`lib/plugins/utils.dart:242-385`（退出确认）、`lib/common/global/platform/desktop_tray_service.dart:17-63`、`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:52-61`、`:1571-1573`、`lib/modules/live_play/widgets/keyboard/video_keyboard.dart:53-80`、`lib/common/widgets/download_apk_dialog.dart:675`、`:688`（设计 README 的“v3 在 macOS 上的样子”逐条写了）。
- 要保留（c1）：界面同 Windows 宽屏；v3 的单键快捷键；分享复制口令；弹性滚动。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.6 节、第 9.3 节。
3. 本文件夹 `README.md` 和 `page/`；`A18.1-iOS和iPadOS差异设计/README.md`（快捷键同一套、台前调度窗口按钮同一个做法）。
4. `docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md` 和 `record.md`（标题栏、托盘、关闭时的选择、桌面小窗）；`docs/A-界面设计/A07-直播间界面/A07.5-宽屏左右分栏/README.md`（音量条、窗口内全屏）、`A07.8-小窗/README.md`；`docs/A-界面设计/A06-首页和全局/A06.2-宽屏首页/README.md`、`A06.3-全局弹窗/README.md`。
5. `docs/X-多端客户端/X05-macOS/README.md`。

## 范围

- 可以改：`apps/pure_live/lib/app/desktop/`（让外壳在 macOS 启用、按平台选标题栏和关闭行为）、菜单栏定义（新文件，例如 `app/desktop/mac_menu_bar.dart`，用 `PlatformMenuBar`）、快捷键命令表（和 A18.1、A16.1 共用一份）、`features/live_play/` 的平台分支、`features/version/` 的 Mac 下载按钮、设置的显示条件；`apps/pure_live/macos/` 里的界面相关原生部分（窗口按钮位置、`applicationShouldTerminateAfterLastWindowClosed` 返回 false、菜单栏图标的模板图）——**前提是 macOS 工程已经建好**；翻译文件（只加键）；测试；本文件夹。
- 不能改：Windows、Linux 的标题栏、托盘、关闭行为（A16.1 已完成）；设置键名和含义（D-018；Mac 上不显示的设置只是隐藏）；签名、公证（X05 的事）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 前提检查：macOS 工程能构建；核对设计“拿不准的地方”1～5 条（菜单本地化、窗口按钮能否移到 56 高的一行、全屏空间里上栏和系统标题栏、托盘模板图、离开全屏空间的事件）；结论写 record.md | record.md | 每条有结论 |
| 2 | 窗口和关闭（c2、c3、c6）：外壳在 macOS 启用，不画自绘标题栏，顶上一行让出窗口按钮、可拖动；关窗不退出、⌘Q 退出前录制确认 | `app/desktop/`、`macos/Runner/AppDelegate.swift` | Dart 测试（`debugDefaultTargetPlatformOverride = TargetPlatform.macOS`）：没有 `DesktopTitleBar`，侧边栏和直播间顶栏让出左边；关闭窗口不退出；录制中退出先确认；Windows 测试不改断言照样通过 |
| 3 | 菜单栏和快捷键（c4、c5）：`PlatformMenuBar` 中文菜单，“播放”菜单在直播间里才可用；命令表和 A18.1、A16.1 共用 | 新菜单栏文件、命令表 | 测试：菜单项和快捷键逐项对上；直播间外“播放”菜单不可用 |
| 4 | 菜单栏图标（c7）、全屏空间（c8）、直播间同 Windows（c9）、更新“在访达中显示”（c10） | `app/desktop/tray.dart`、`features/live_play/`、`features/version/` | 测试：录制中菜单前两行；离开全屏空间（模拟 `onWindowLeaveFullScreen`）直播间退出全屏；Mac 下载完只有一个按钮 |

每个阶段都要能单独合并。登记表没有写阶段，开工时按上表补。

## 测试

- 改之前会失败（Linux 上能跑）：加“macOS 上桌面外壳启用、没有自绘标题栏”（现在 `DesktopShell.supported` 只有 Windows）。
- 每个阶段的用例见上表；`window_manager`、`tray_manager` 用测试替身（照 A16.1 的测试写法，`apps/pure_live/test/desktop_window_test.dart`）；定时器至少 1 秒；不访问网络。

## 真机验证（要一台 Mac，在 Mac 上构建）

| 步骤 | 期望 |
|---|---|
| 1. 打开应用 | 三个窗口按钮在顶上一行左边，不压菜单按钮；顶上空白处能拖动窗口；没有毛玻璃 |
| 2. 进直播间 | 返回键在窗口按钮右边；有小窗、音量条、窗口内全屏 |
| 3. 看菜单栏 | 全是中文；“设置… ⌘,”能打开设置；在直播间里“播放”菜单可用，出直播间变灰 |
| 4. ⌘F、⌘1～⌘4、⌘[、⌘R | 各自生效 |
| 5. 开始录制，点红色按钮 | 窗口关了，应用还在程序坞；录制继续；点程序坞图标窗口回来 |
| 6. 录制中按 ⌘Q | 先问“要退出纯粹直播吗？正在录制 1 个直播间……” |
| 7. 菜单栏图标 | 单色；录制中有红点；左键右键都出菜单，前两行是录制 |
| 8. 直播间点全屏按钮，再按绿色按钮离开 | 进系统全屏空间；离开时直播间也退出全屏 |
| 9. 下载更新完成 | 只有“在访达中显示” |

## 风险和注意

- 没有 Mac 就做不了；第 2～4 阶段的 Dart 部分可以先在 Linux 写测试，但窗口按钮位置、菜单本地化、全屏空间都要真机看。
- 让外壳在 macOS 启用会把 A16.1 为 Windows 写的行为带过来（关闭对话框、开机启动、新窗口），要逐项按平台分开，Windows 行为不变。
- 设计交给 A12.6 的问题：macOS 正式版权限文件缺 `com.apple.security.network.server`（3.x 就缺），设备同步在正式版收不到连接——建 macOS 工程时一起加（X05）。
- 可能冲突的文件：`app/desktop/`（X01 的 Windows 任务）、快捷键命令表（A18.1、A16.1、X01.1）、`features/version/`（Y02）。

## 需要维护者决定的

1. macOS 的工程、构建、签名、公证在 X05 还没有任务，要先登记（建议 X05.1，照 X04.1 的样子）。
2. 菜单栏图标默认显示（K2 A）和 A16.1 的托盘设置是否共用一个设置键。

## 环境和提交

- Linux / WSL：`source ~/tools/purelive-env.sh` 或按 `toolchain.env` 装 Flutter；只能跑 Dart 测试，**不能构建 macOS**。
- Mac：Xcode、CocoaPods，`flutter build macos`；签名和证书不进 git。
- 分支 `ai/A18.2`；提交信息以 `[A18.2]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；第 1 阶段各条的结论；外壳在 macOS 启用后 Windows 是否受影响；测试数量（改之前失败几个）；改了哪些文件（Dart 和原生分开列）；新设置和翻译键；要在 Mac 上看的；可能冲突的文件。
