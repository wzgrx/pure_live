# X01.3 Windows 安装包和自动更新：任务书

## 背景

- 来源：版本路线 4.1 = Windows（`docs/PLAN.md` 第 5 节）；D-004 定了客户端顺序 Android → Windows → 电视 → Linux → 苹果平台。登记时的旧编号 T17d.1。
- 现象：4.x 的 Windows 代码（运行器、桌面外壳、DPAPI、显示模式通道）都在仓库里，但**从没在 Windows 上构建过**（O03.1 记录）；没有安装包和打包脚本；`assets/version.json` 的 `platforms.windows` 还指向 3.2.11。
- 为什么现在做：第三档，**等 4.1 开工**（当前只做 Android）。本任务的第 1 阶段是 X01.1（第 3 阶段）、X01.2 的前置条件，4.1 开工时第一个做。
- **前置条件**：维护者同意开始 Windows 客户端（D-004 的顺序到了）；Windows 主机可用（`C:\Users\123\claude-work\`）。
- 已经做过的：O03.1（`c0218fb7a` Windows 桌面外壳）；A16.1（桌面窗口界面）；R02.1（显示模式通道）；I01.3（应用内下载更新，含 Windows 的包类型）。

## 目标和验收

1. 从干净的克隆在 Windows 主机上 `flutter build windows --release` 成功，`pure_live.exe` 启动到首页，能进一个哔哩哔哩直播间播放、有弹幕，能开始和停止录制（FFmpeg Windows 包）；问题和修法写进 `record.md`。
2. 包的方案定了（README c2，建议 A：安装包 + 便携 ZIP），写进 `record.md`，维护者确认。
3. 打包脚本 `tools/release/windows/build.ps1` 从构建产物做出约定的包和 `SHA256SUMS.txt`；便携 ZIP 不含 `UserData`；安装包装到用户目录、可卸载、卸载时删 `PureLiveV4` 启动项。
4. 应用内更新：一个更低版本的 4.x Windows 版能检查到新版本、下载对的包、运行安装包（或打开 ZIP 所在文件夹）。
5. 4.1 发布按 PROCESS 第 11 节（版本号由维护者定），最后改 `platforms.windows`。
6. 不碰 `D:\Soft\PureLive`、`D:\Soft\pure_live` 和 HKCU Run 的 `pure_live`。

## 现状（读代码得出，写文件:行）

- 工程：`apps/pure_live/windows/CMakeLists.txt`（`project(pure_live)` `:6`、`BINARY_NAME` `:21`）；`runner/main.cpp`（147 行，单实例 `:85-104`）、`flutter_window.cpp`（242 行）、`win32_window.cpp`（295 行）、`Runner.rc`（`:92-98` 版本信息，版权写 2025）、`resources/app_icon.ico`。
- 原生包：录制 FFmpeg `tools/ffmpeg_kit/bundles.txt` 的 `bundle-base-windows-x86_64-shared-lgpl.zip`，Windows 上用 `tools/ffmpeg_kit/fetch.ps1`（37 行）下载并链接到 `.ffmpeg_kit/`，根 `pubspec.yaml:66-72` 指向它；libmpv 由 `third_party/media_kit/hook/native_bundles.json` 的 `windows_x64`（`:38`）在构建时下载。
- 插件（`apps/pure_live/pubspec.yaml`）：`window_manager ^0.5.2`、`tray_manager ^0.7.0`、`screen_retriever ^0.2.2`、`file_picker`、`url_launcher`、`share_plus`、`connectivity_plus`、`bonsoir`、`flutter_inappwebview 6.2.0-beta.3`（Windows 要 WebView2）、`mobile_scanner`（Windows 不支持，要确认不会让构建失败）、`ffmpeg_kit_extended_flutter 0.6.2`。
- 数据目录：`apps/pure_live/lib/app/data_root.dart:10-13`、`:23`、`:34`（exe 旁边的 `UserData`，写不了时用户的应用数据目录）。
- 应用内更新：`apps/pure_live/lib/features/version/update_feed.dart:213-221`（`windowsSetup` `windows-x64-setup.exe`、`windowsMsix`、`windowsPortable` `windows-x64-portable.zip`）、`:305` `currentUpdatePlatform`（Windows → `windows`）；`update_download.dart:295-340`（Windows 运行安装包；ZIP 打开文件夹 `explorer.exe /select,`）；`version_page.dart:22` `platformPackages`；测试 `apps/pure_live/test/features/version/version_page_test.dart:158` 起（现在读到 Windows 3.2.11）。
- 开机启动：`apps/pure_live/lib/app/desktop/startup_entry.dart:7`、`:12`、`:36`。

## 3.x 基线

- 打包：`git show v3.2.11:windows/packaging/exe/inno_setup.iss`（`AppId`、`DefaultDirName`、`PrivilegesRequired`、`CloseApplications=yes` `:18`、`[Run]` `:60`）、`windows/packaging/exe/local_release.iss`、`windows/packaging/msix/make_config.yaml`（`identity_name: com.mystyle.purelive`、自签名证书）、`docs/MSIX_INSTALL.md`（用户手动信任证书的教程）。
- 构建：`.github/workflows/build_pure_live_release.yml:212` 起（`windows-latest`、`flutter_distributor --targets exe,msix`、便携 ZIP 且检查不含运行时数据 `:325-365`）。
- 便携数据：`lib/common/global/windows_portable_path_provider.dart`（3.x 的 `<exe 目录>\AppData`）。
- 要保留：包的命名风格（`PureLive-<版本>-<构建号>-windows-x64-…`）；`version.json` 的格式和 `windows_msix_available` 字段（3.x 的 Windows 版读它）；3.x 的设置键（D-018）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 10 节、第 11 节发布、第 14 节）。
2. `docs/specs/ENGINEERING.md` 第 3 节（构建只在本机，Windows 在主机）、第 6 节（Windows 测试版放在工作目录，不碰 `D:\Soft`）。
3. 本文件夹的 `README.md`；`docs/X-多端客户端/X01-Windows/README.md`；`docs/Y-发布和运营/Y01-版本签名和发布/README.md`、`Y02-更新通道/README.md`；`docs/O-Android系统集成/O03-分享接收和快捷方式/O03.1-插件接入和Windows桌面/record.md`。

## 范围

- 可以改：`apps/pure_live/windows/`（编译和启动需要的修复、版本信息）；Windows 编译需要的 Dart 侧条件判断（例如不支持的插件在 Windows 上不调用）；新建 `tools/release/windows/`（打包脚本、`.iss`）；对应测试；本文件夹的文档。发布阶段（第 4 阶段）由维护者改版本号和 `assets/version.json`、`assets/releases.json`。
- 不能改：Android 的原生代码和构建配置；桌面界面的设计（A16.1）；3.x 的设置键名和含义；签名配置（Android）。
- 绝对不能：动 `D:\Soft\PureLive`、`D:\Soft\pure_live`、HKCU Run 的 `pure_live`；在 Windows 主机上用 `-d`（必须写全 `--device-id=windows`）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 能构建运行 | `windows/`、必要的 Dart 条件判断、`record.md` | 验收 1；X01.1、X01.2 可以开工 |
| 2 | c2 定方案、c3 打包脚本 | `tools/release/windows/`、`record.md` | 验收 2、3；在干净的 Windows 用户账户里装、卸载各一次 |
| 3 | c4 应用内更新 | 发现的问题的修复、测试 | 验收 4 |
| 4 | c5 发布 4.1（等 X01.1、X01.2 完成） | 维护者：版本号、`version.json`、`releases.json`、发布页 | 验收 5 |

## 测试

- 第 1 阶段修编译问题时，凡是改了 Dart 的地方加测试（例如“Windows 上不调用 `mobile_scanner`”）。
- `version_page_test.dart`：Windows 的包挑选（已有 `:158` 起）；第 3 阶段如果改了挑包逻辑加用例。
- 打包脚本：在 `record.md` 里贴一次完整运行的输出（文件名、大小、SHA-256）。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 Windows 主机上做）

| 步骤 | 期望 |
|---|---|
| 1. 干净克隆、`fetch.ps1`、`flutter pub get`、`flutter build windows --release` | 构建成功；`build\windows\x64\runner\Release\` 里有 `pure_live.exe`、libmpv、FFmpeg 的 DLL |
| 2. 运行 `pure_live.exe` | 自绘标题栏、首页；exe 旁边出现 `UserData` |
| 3. 进一个哔哩哔哩直播间；录制 30 秒再停 | 出画面和声音、有弹幕；录制中心里有文件，能播放 |
| 4. 运行安装包，装到默认位置 | 不要管理员；开始菜单有“纯粹直播”；启动后数据在用户的应用数据目录（安装目录不可写时） |
| 5. 卸载 | 程序删掉；问要不要删数据；注册表 `HKCU\…\Run` 里没有 `PureLiveV4`；3.x 的 `pure_live` 还在 |
| 6. 解压便携 ZIP 到一个新文件夹运行 | 数据在旁边的 `UserData`；ZIP 里本来没有 `UserData` |
| 7. 装一个版本号更低的 4.x，打开 | 弹“发现新版本”；下载的是 Windows 安装包；点安装后运行安装包，关闭应用、覆盖安装、再启动，数据还在 |

## 风险和注意

- PowerShell 里 flutter 的设备参数一律写全 `--device-id=windows`；2026-09-25 `-d` 被当成 `-Debug`，flutter 选了手机，卸载了手机上的 3.x 并清掉数据。
- 安装包装进 `Program Files` 时 exe 旁边不可写，数据会落到用户目录（`data_root.dart` 的回退）；默认装到用户目录可以避开，但要在 README 里写清数据在哪。
- 自签名 MSIX 要用户手动信任证书（3.x 的 `MSIX_INSTALL.md`），不建议默认发布。
- 没有代码签名证书时 SmartScreen 会提示“未知发布者”，发布说明里写清楚。
- 可能冲突的文件：`apps/pure_live/windows/runner/`（X01.2 的 WinHTTP 通道）；`apps/pure_live/pubspec.yaml`（插件版本）。

## 环境和提交

- Windows 主机：克隆 `C:\Users\123\claude-work\pure_live`（拉分支）、Flutter `C:\Users\123\claude-work\flutter\bin\flutter.bat`（不在 PATH，全路径）、JDK `C:\Users\123\claude-work\jdk\jdk-27+35`、Visual Studio Community 2026；从 WSL 调 PowerShell 用 `"/mnt/c/Program Files/PowerShell/7/pwsh.exe"`。GUI 检查：`C:\Users\123\claude-work\wingui.ps1` + WSL 的 `~/tools/wg.sh`。
- 打包需要 Inno Setup（3.x 用的版本见它的工作流 `:275` 起），装在 Windows 主机上。
- 分支 `ai/X01.3` 或本机工作区；提交信息以 `[X01.3]` 开头（英文）；不推 master。
- 提交前（WSL）：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`bash tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（构建到哪一步卡住、错误信息）、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

能不能构建运行、修了什么；包的方案；打包脚本和产物（文件名、大小）；安装、卸载、便携、应用内更新的结果；需要维护者决定的（包的方案、3.x Windows 用户怎么升级、代码签名证书、版本号）；可能冲突的文件。
