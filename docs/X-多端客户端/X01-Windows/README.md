# X01 Windows

4.x 的 Windows 客户端（4.1 的主体）：Windows 运行器和原生部分、桌面外壳（窗口、标题栏、托盘、关闭、开机自启、单实例、新窗口、桌面小窗）背后的逻辑、键盘鼠标操作、Windows 专属功能，以及安装包和自动更新。

## 范围

- 包括：
  - `apps/pure_live/windows/`：CMake 工程、运行器（`runner/main.cpp` 单实例和新窗口进程、`flutter_window.cpp` 的显示模式通道、`win32_window.cpp`、`Runner.rc` 版本信息、图标）。
  - 桌面外壳的逻辑 `apps/pure_live/lib/app/desktop/`、命令行和新窗口进程 `lib/app/launch_args.dart`、数据目录的 Windows 分支 `lib/app/data_root.dart`、DPAPI 加密 `lib/platform/secret_cipher.dart:45`。
  - 键鼠操作在各页面的实现是否和 3.x 一致（X01.1）；功能清点第 13 节的 14 项（X01.2）；安装包、MSIX、便携 ZIP、应用内更新（X01.3）。
- 不包括（归哪里）：
  - 桌面界面的样子（标题栏、托盘菜单、关闭对话框、窗口内全屏、宽屏布局）→ A16.1（完成）和 A 组各区域的“宽屏”部分。
  - Linux → X02（复用这里的桌面外壳）；macOS → X05。
  - `version.json` 的 `platforms.windows` 块、发布页 → Y01、Y02（X01.3 提供包）。
  - 播放内核在 Windows 上的原生包（libmpv）→ G01；录制的 FFmpeg Windows 包（`tools/ffmpeg_kit/bundles.txt`、`fetch.ps1`）→ Z04。

## 现状：做到哪、怎么工作的

- **从来没在 Windows 上构建、运行过**（O03.1 记录“Windows：一直没构建、没运行”；A16.1 的实现也只在测试里用 `TargetPlatform.windows` 跑过）。Windows 主机的环境在：克隆 `C:\Users\123\claude-work\pure_live`、Flutter 3.47.5 `C:\Users\123\claude-work\flutter`（不在 PATH，用 `flutter\bin\flutter.bat` 全路径）、JDK `C:\Users\123\claude-work\jdk\jdk-27+35`、Visual Studio Community 2026。
- 已有的代码（M12.3 / O03.1 的 `c0218fb7a`，A16.1 的界面）：
  - **启动**：`windows/runner/main.cpp:85-104` 在创建 Flutter 引擎之前判断单实例：没带 `--instance=` 的是主窗口，互斥量 `kPrimaryInstanceMutex`（`:13`），已存在就把主窗口带到前面（`BringPrimaryWindowToFront` `:41`，按窗口属性 `PureLive.PrimaryWindow` `:26` 找）并退出；带 `--instance=<id>` 的是新窗口，各自一个互斥量。3.x 只在这里挡无参数的启动，其余交给 `windows_single_instance` 插件（会丢参数）。
  - **外壳**：`lib/app/desktop/desktop_window.dart`（599 行）的 `DesktopShell`：`supported` 只在 Windows 为真（`:257`）；最小 360×400（`:261`）；第一次 1280×720 居中，记住大小、位置、是否最大化（meta `window.position`、`window.maximized`，`:187-192`）；`exit()`（`:406`）保存几何、停录制（最多 3 秒）、销毁窗口。`title_bar.dart`（自绘标题栏）、`tray.dart`（托盘，录制时写“正在录制 N 个直播间”）、`close_dialog.dart`（关闭询问，`exitChoose`、`dontAskExit` 沿用 3.x 键）、`startup_entry.dart`（开机自启写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\PureLiveV4`，`:7`、`:12`，3.x 的 `PureLive`/`pure_live` 不读不改）、`mini_window.dart`（桌面小窗：默认尺寸、最小 140×90、记住位置、置顶）、`shared_data.dart`（多个窗口共用一份数据库，监听文件变化同步）。
  - **新窗口**：`lib/app/launch_args.dart:108` `startWindowProcess`：每个新窗口是独立进程，带 `--instance`、可选 `--open-room`，和主窗口共用数据目录（A16.1 c14，3.x 是复制一份配置）。
  - **数据目录**：exe 旁边的 `UserData`（便携），写不了（Program Files、只读介质）时用用户的应用数据目录（`lib/app/data_root.dart:10-13`、`:34`）；3.x 的 `<exe 目录>\AppData` 只由 3.x 导入读取。
  - **加密**：DPAPI，当前用户，秘密名作熵（`lib/platform/secret_cipher.dart:42-45`）。
  - **显示模式**：运行器的 `pure_live/display_mode` 通道（`flutter_window.cpp:40-53`，`ReadDisplayMode` `:113` 用 `EnumDisplaySettings` 读刷新率），给刷新率设置用（F-WIN-10）。
  - **RTX 超分**：设置“RTX 视频超分辨率”只在 Windows 显示（`lib/features/settings/settings_catalog.dart:1274-1281`），传给 mpv（`packages/live_player/lib/src/mpv_options.dart:62`、`:154`）。
  - **键鼠**：直播间快捷键（`lib/features/live_play/live_play_page.dart:736-753`）、滚轮音量、悬停显示控制层、右键等于长按、标签栏滚轮、←→ 翻页、设置页 Ctrl+F（逐项对照见 X01.1 的 README）。
- 功能清点第 13 节 14 项（`docs/inventory/FEATURES.md`）的代码现状：

| 编号 | 功能 | 4.x 代码 | 状态 |
|---|---|---|---|
| F-WIN-01 | 自绘标题栏（拖动时显示尺寸） | `lib/app/desktop/title_bar.dart:34` | 有代码，没在 Windows 上看过 |
| F-WIN-02 | 窗口大小（立即应用）、位置 | `desktop_window.dart:286` 起 | 同上 |
| F-WIN-03 | 托盘 | `tray.dart:49` | 同上 |
| F-WIN-04 | 关闭时询问、最小化到托盘、退出 | `close_dialog.dart:48`、`:170` | 同上 |
| F-WIN-05 | 开机启动 | `startup_entry.dart:36` | 同上（只有 release 构建按设置补写或删除） |
| F-WIN-06 | 单实例、在新窗口打开直播间 | `windows/runner/main.cpp:85-104`、`launch_args.dart:108` | 同上 |
| F-WIN-07 | 桌面小窗（置顶、记住位置） | `mini_window.dart` | 同上 |
| F-WIN-08 | 窗口内全屏按钮 | `RoomDisplay.windowFullscreen`（`lib/features/live_play/logic/room_layout.dart:6`） | 同上 |
| F-WIN-09 | 控制栏音量（悬停出滑块、一键静音） | `lib/features/live_play/player/bar_parts.dart:150` `VolumeSlider` | 同上 |
| F-WIN-10 | Windows 动态刷新率信息 | `flutter_window.cpp:40-53` | 同上 |
| F-WIN-11 | RTX 超分 | `settings_catalog.dart:1274`、`mpv_options.dart:154` | 同上 |
| F-WIN-12 | Kick 的 WinHTTP 通道 | **没有**：`lib/app/bootstrap.dart:160` 只在 Android 建原生 HTTP 通道，Windows 上 Kick 不可用（E03.16“仅 Android”） | 缺 |
| F-WIN-13 | 悬停显示控制层、右键菜单 | `player_view.dart:799`、各处 `onSecondaryTap` | 有代码 |
| F-WIN-14 | 退出前写盘（3.x `didRequestAppExit`） | 没有 `didRequestAppExit`；4.x 的存储是 SQLite，每次写入即提交，`exit()` 只存窗口几何、停录制 | 要核对进行中的写入 |

- 完成度：A16.1（界面）完成；X01.1、X01.2、X01.3 都没开始。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/windows/CMakeLists.txt` | 工程（`BINARY_NAME` `pure_live`，`:21`） |
| `apps/pure_live/windows/runner/main.cpp`（147 行） | 单实例、新窗口进程、主窗口属性 |
| `apps/pure_live/windows/runner/flutter_window.cpp`（242 行） | Flutter 视图、`pure_live/display_mode` 通道 |
| `apps/pure_live/windows/runner/win32_window.cpp`（295 行）、`utils.cpp` | 窗口、命令行参数 |
| `apps/pure_live/windows/runner/Runner.rc` | 版本信息（公司 `com.mystyle`、产品“纯粹直播 Pure Live”、版权写着 2025） |
| `apps/pure_live/lib/app/desktop/desktop_window.dart`（599） | `DesktopWindow`（页面要的全屏、小窗、新窗口）、`DesktopShell`（启动、几何、关闭、退出） |
| `apps/pure_live/lib/app/desktop/title_bar.dart`（345）、`tray.dart`（169）、`close_dialog.dart`（357）、`startup_entry.dart`（55）、`mini_window.dart`（244）、`shared_data.dart`（67） | 见上 |
| `apps/pure_live/lib/app/launch_args.dart`（115） | 命令行（`--instance`、`--open-room`）、`startWindowProcess` |
| `apps/pure_live/lib/app/data_root.dart` | 数据目录（便携 `UserData`） |
| `apps/pure_live/lib/platform/secret_cipher.dart` | `WindowsDpapiCipher` |
| `apps/pure_live/lib/app/platforms.dart`（278） | 平台判断和各平台能力 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/desktop_window_test.dart`（26 个） | 标题栏、托盘菜单、关闭询问和录制中退出、几何记忆和不在显示器上时居中、新窗口、桌面小窗的位置 |
| `apps/pure_live/test/launch_args_test.dart`（4） | 命令行参数解析、实例 id 清洗 |
| `apps/pure_live/test/platforms_test.dart`（11） | 平台能力 |
| 用 `TargetPlatform.windows` 的界面测试（8 个文件） | 直播间宽屏、快捷键（Esc 退全屏、媒体键）等 |
| （没有） | 运行器的 C++ 没有测试；Windows 上的真实运行没有任何记录 |

## 3.x 基线

- 3.x 的 Windows 代码（`git show v3.2.11:lib/...`）：`common/global/platform/desktop_manager.dart:263`（标题栏）、`:765`（`didRequestAppExit` 写盘）、`common/services/settings/window_size_controller.dart:6`、`common/global/platform/desktop_tray_service.dart:7`、`plugins/utils.dart:7`（关闭询问）、`common/global/win_auto_start.dart:8`、`common/utils/windows_multi_instance_launcher.dart:18`、`player/utils/window_helper.dart`（桌面小窗）、`modules/live_play/widgets/video_player/volume_control.dart:10`、`common/global/windows_portable_path_provider.dart`（便携数据目录）。
- 3.x 的打包：`windows/packaging/exe/inno_setup.iss`、`local_release.iss`（Inno Setup 安装包）、`windows/packaging/msix/make_config.yaml`（MSIX），工作流 `.github/workflows/build_pure_live_release.yml:212` 起（EXE + MSIX + 便携 ZIP）；`docs/MSIX_INSTALL.md`（自签名 MSIX 要手动信任证书）。
- 必须保留的操作习惯：[specs/UI.md](../../specs/UI.md) 附录 A 第 13、14、16 条（快捷键、滚轮、右键）；3.x 的设置键 `exitChoose`、`dontAskExit`、`window_width`、`window_height`（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 4.x 从没在 Windows 上构建、运行过 | — | 所有 Windows 代码都没验证；可能连编译都过不了（插件的 Windows 部分、FFmpeg 包、libmpv） | X01.3 第 1 阶段 |
| 直播间普通状态下按 Esc 不离开（3.x 会离开） | `lib/features/live_play/live_play_page.dart:662-673` 的 `_back()` 没有这一支 | 和 3.x 不一致，疑似回归 | X01.1 |
| Kick 在 Windows 上没有原生 HTTP 通道 | `lib/app/bootstrap.dart:160` | Windows 上 Kick 不可用（UPGRADES X-1 余项） | X01.2 |
| 本地互动的礼物和徽章 emoji 用 COLRv1 字体，Windows 10 的 DirectWrite 可能画成空白 | `lib/features/live_play/local_interaction/local_interaction_scope.dart:58` | Windows 10 上礼物图案看不见 | A08 的已知问题，在 X01.2 里验证，不行就让 Windows 用系统 emoji |
| 退出时没有等进行中的数据库写入（3.x 有 `didRequestAppExit` 写盘） | `lib/app/desktop/desktop_window.dart:406-419` | 极端情况下最后一次写入可能丢（SQLite 有事务，不会写坏） | X01.2（F-WIN-14） |
| `Runner.rc` 的版权写 2025、公司写 `com.mystyle` | `windows/runner/Runner.rc:92-98` | 文件属性里的信息不准 | X01.3（安装包的发布者信息一起定） |
| 3.x 的 Windows 用户还在 3.2.11（`version.json` 的 `platforms.windows`） | `assets/version.json` | 4.1 发布前他们不会收到 4.x | 有意的；X01.3 发布时改 |

## 相关决定和规范

- D-004（客户端顺序：Android → Windows → …；当前只做 Android）、D-018（3.x 设置键不变）、D-019（设备规则：Windows 上不碰 `D:\Soft` 的 3.x）。
- ENGINEERING 第 3 节（Windows 在主机上构建）、第 6 节（Windows 测试版放在工作目录）；specs/UI.md 第 5.4 节和附录 A。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/desktop_window_test.dart test/launch_args_test.dart`，以及带 `TargetPlatform.windows` 的界面测试。
- 真机（Windows 主机）：PowerShell 里 `C:\Users\123\claude-work\flutter\bin\flutter.bat build windows --release`（在 `apps\pure_live`），运行 `build\windows\x64\runner\Release\pure_live.exe`；集成测试一律写全 `--device-id=windows`；GUI 检查用 `C:\Users\123\claude-work\wingui.ps1` + `~/tools/wg.sh`（后台截窗口和点按，不抢鼠标）。

## 路线

1. X01.3 第 1 阶段：在 Windows 上构建运行（4.1 的前提）。
2. X01.1：键鼠逐项核对（第 1、2 阶段现在就能在 WSL 做：列清单、写测试、修 Esc）。
3. X01.2：14 项专属功能逐项在 Windows 上验证、补缺（Kick 的 WinHTTP、退出写盘、Windows 10 的 emoji）。
4. X01.3 其余阶段：安装包（Inno Setup / MSIX / 便携 ZIP 选哪些）、应用内更新、签名、发布 4.1。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [X 多端客户端](../README.md)。

- 代码：`apps/pure_live/windows/`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| X01.1 | 键盘鼠标操作核对 | 功能 | 未开始 | — | — | [设计或说明](X01.1-键盘鼠标操作核对/README.md)、[任务书](X01.1-键盘鼠标操作核对/brief.md) |
| X01.2 | Windows 专属功能（功能清点第 13 节的 14 项） | 功能 | 未开始 | — | — | [设计或说明](X01.2-Windows专属功能/README.md)、[任务书](X01.2-Windows专属功能/brief.md) |
| X01.3 | Windows 安装包和自动更新 | 发布 | 未开始 | — | — | [设计或说明](X01.3-Windows安装包和自动更新/README.md)、[任务书](X01.3-Windows安装包和自动更新/brief.md) |

## 还没完成的

- **X01.1 键盘鼠标操作核对**（未开始，第三档，规模 小）
- **X01.2 Windows 专属功能（功能清点第 13 节的 14 项）**（未开始，第三档，规模 大）
- **X01.3 Windows 安装包和自动更新**（未开始，第三档，规模 中）

<!-- docs:生成结束 -->
