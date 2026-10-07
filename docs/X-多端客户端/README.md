# X 多端客户端

Android 以外的客户端各自要做的“专属”工作：Windows、Linux、电视（Android TV）、iOS 和 iPadOS、macOS 的构建、打包、签名、原生代码、平台差异和键鼠或遥控器操作。按 D-004 现在只做 Android，所以这一组的任务都排在以后（第三档），这一组的说明主要写清**每个客户端开工前要具备什么、按什么顺序做**。

## 范围

- 管什么：
  - **Windows**（X01）：`apps/pure_live/windows/`（运行器 `runner/main.cpp`、`flutter_window.cpp`、`win32_window.cpp`）、桌面外壳的 Dart 部分 `apps/pure_live/lib/app/desktop/`（7 个文件）、`lib/app/launch_args.dart`、`lib/app/data_root.dart` 的 Windows 分支、`lib/platform/secret_cipher.dart` 的 DPAPI；键盘鼠标操作；Windows 专属功能（功能清点第 13 节 14 项）；安装包和自动更新。
  - **Linux**（X02）：Linux 运行器（仓库 master 上**没有** `apps/pure_live/linux/`，有一份没合并的半成品，见 X02 说明）、打包。
  - **电视**（X03）：电视外壳和焦点导航的代码 `apps/pure_live/lib/tv/`（28 个文件）、`lib/app/ui_mode.dart`、`lib/routes/tv_router.dart`、Android 清单里的 leanback 部分；以 pure_live_TV（`~/ref/pure_live_TV`，AGPL-3.0）为基线并入。
  - **iOS 和 iPadOS**（X04）、**macOS**（X05）：构建、签名、平台差异（仓库里**没有** `ios/`、`macos/` 运行器）。
- 不管什么（归哪里）：
  - 各客户端的**界面设计和界面实现** → A16（桌面）、A17（电视）、A18（苹果平台）；X 只管打包、原生、平台能力和输入方式。例如 Windows 标题栏的样子在 A16.1，标题栏背后的 `window_manager` 和运行器在 X01。
  - 共用的功能逻辑（播放、弹幕、录制……）→ 各功能组；某个功能在某个客户端上不一样时，在功能组的任务里写“各客户端”，平台原生部分在这里。
  - 版本号、`version.json` 里各平台的块 → Y01、Y02；X 提供安装包和平台块的内容。
  - 点播和音乐的核心包 `packages/live_vod`（给电视用）→ L03。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [X01 Windows](X01-Windows/README.md) | Windows 运行器、桌面外壳、键鼠、专属功能、安装包和更新 | 界面在 A16.1（完成）；4.1 的主体；Kick 在 Windows 要 WinHTTP 通道（UPGRADES X-1 余项） |
| [X02 Linux](X02-Linux/README.md) | Linux 运行器、平台服务、打包 | 复用 X01 的桌面外壳；没合并的 M12.6 半成品是起点 |
| [X03 电视](X03-电视/README.md) | 电视外壳、焦点导航、遥控器输入、电视模式的判断 | 界面在 A17（A17.1 完成，A17.2～A17.9 已确认）；点播音乐在 L03 |
| [X04 iOS和iPadOS](X04-iOS和iPadOS/README.md) | 苹果移动端的运行器、构建、签名、平台差异 | 差异设计在 A18.1；需要 Mac |
| [X05 macOS](X05-macOS/README.md) | macOS 的运行器、构建、签名、菜单栏、快捷键 | 差异设计在 A18.2；需要 Mac；X05.1、X05.2（以后） |

## 现状（2026-10-07）

- 客户端顺序（D-004）：Android → Windows → 电视 → Linux → 苹果平台；**当前只做 Android**。版本路线（`docs/PLAN.md` 第 5 节）：4.1 Windows、4.2 电视、4.3 Linux、以后苹果平台。
- 做到哪：
  - **Windows**：代码大部分在（O03.1 / M12.3 的桌面外壳：自绘标题栏、托盘、关闭询问、开机自启 `PureLiveV4`、窗口大小和位置、单实例和新窗口进程、桌面小窗；A16.1 的界面完成），但 4.x **从来没在 Windows 上构建、运行过**（O03.1 记录）。`DesktopShell.supported` 只在 Windows 为真（`lib/app/desktop/desktop_window.dart:257`）。X01.1～X01.3 都没开始。
  - **Linux**：master 上没有运行器；`worktree-agent-ab1a5d264e55120e5`（`0dc0df759`，2026-10-01）有一份没合并的 M12.6：Linux 运行器、平台服务（XDG 数据目录、OpenSSL 加密、iconv）、桌面外壳在 Linux 上启用、XDG 自启，36 个文件；它基于界面目录搬家（Z02.1）之前的 `lib/pages/` 结构，合并要重做路径。X02.1 没开始。
  - **电视**：X03.1 完成（2026-10-01，`781586ff7`）：电视模式判断、外壳、焦点导航、直播浏览、基本直播间，`test/tv/` 37 个测试；**但没在真电视或盒子上运行过**（记录“没验证的部分”）。之后的电视界面是 A17（A17.1 完成，其余已确认未开发）。
  - **iOS、iPadOS、macOS**：只有 A18.1、A18.2 的差异设计（已确认）；没有运行器；本机没有 Mac，不能构建。
- 和 3.x 比：3.x 发布 Android、Windows（Inno Setup 安装包、MSIX、便携 ZIP）、Linux，iOS 有未签名 IPA（`git show v3.2.11:.github/workflows/build-ios-unsigned.yml`），macOS 有工程但不发布；电视版是另一个仓库 pure_live_TV。4.x 现在只发 Android；电视并进了同一个应用（按设备自动切到电视界面）。
- 主要的代码：`apps/pure_live/windows/`、`apps/pure_live/lib/app/desktop/`、`apps/pure_live/lib/tv/`、`apps/pure_live/lib/app/ui_mode.dart`、`apps/pure_live/lib/routes/tv_router.dart`；平台判断在 `apps/pure_live/lib/app/platforms.dart`。

## 当前重点和顺序

1. 现在什么都不开（D-004：当前只做 Android）。可以提前做、不需要 Windows 的：X01.1 的第 1、2 阶段（读代码列清单、写测试、修直播间普通状态下 Esc 不离开的回归）。
2. **4.1 Windows** 开工时的顺序：X01.3 第 1 阶段（在 Windows 上能构建运行）→ X01.1（键鼠核对）和 X01.2（14 项专属功能，含 Kick 的 WinHTTP）→ X01.3 其余阶段（安装包、自动更新、发布）。
3. **4.2 电视**：A17.2～A17.9 的界面，加 X03 的真机验证（需要一台电视或盒子）。
4. **4.3 Linux**：X02.1，先决定 M12.6 半成品怎么并入。
5. **苹果平台**：X04.1，前提是有 Mac 和 Apple 开发者账号；macOS 是 X05.1（工程和构建）、X05.2（签名和分发）。

## 风险和注意

- **不碰用户的 3.x**：Windows 上 `D:\Soft\PureLive`、`D:\Soft\pure_live` 和开机启动项 `pure_live`（HKCU Run）都是用户每天用的 3.x，不能动（AGENTS.md、PROCESS 第 10 节）。4.x 的开机自启用自己的名字 `PureLiveV4`（`lib/app/desktop/startup_entry.dart:12`），不读不改 3.x 的。
- **Windows 上跑集成测试一律写 `--device-id=windows`**：2026-09-25 在 PowerShell 里 `-d` 被当成 `-Debug`，flutter 选中了手机，卸载了手机上的 3.x 并清掉了数据。
- **单实例**：运行器在创建 Flutter 引擎之前用互斥量判断（`windows/runner/main.cpp:85-104`），主窗口重复启动只把已有窗口带到前面；新窗口进程带 `--instance=`，各自一个互斥量。
- **数据目录**：Windows 默认在 exe 旁边的 `UserData`（便携），写不了时用用户的应用数据目录（`lib/app/data_root.dart:10-13`）；3.x 的 `<exe 目录>\AppData` 只在导入时读。
- **加密存储**：Android Keystore、Windows DPAPI，其他平台没有加密器（`lib/platform/secret_cipher.dart:12-14`），Linux、苹果平台开工时必须先补，否则账号无处可存。
- **苹果平台**：本机没有 Mac，不能构建、不能签名；3.x 的 iOS 只出过未签名 IPA。
- **电视**：同一个 APK 同时装在手机和电视上（`leanback`、触摸屏都声明为“不强制”），改清单时不能让手机的行为变化。

## 相关

- 规范：[specs/UI.md](../specs/UI.md) 第 5.4 节（输入方式：键鼠、遥控器）和附录 A（必须保留的操作习惯，第 13、14、16 条是键鼠）；[specs/ENGINEERING.md](../specs/ENGINEERING.md) 第 3 节（只在本机构建：Android 在 WSL，Windows 在主机）、第 6 节（Windows 测试版放在工作目录，不碰 `D:\Soft`）。
- 决定：D-004（客户端顺序）、D-019（设备规则）、D-006（签名，Android）。
- 其他组：A16、A17、A18（界面）；Y01、Y02（发布和更新通道）；L03（点播和音乐）；E03.16、Q（Kick 和原生 HTTP 通道）；inventory/FEATURES.md 第 13 节（Windows 专属 14 项）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`██░░░░░░░░░░░░░░░░░░` 11%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [X01 Windows](X01-Windows/README.md) | Windows 专属功能、键鼠、安装包和更新。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 3 |
| [X02 Linux](X02-Linux/README.md) | Linux 构建和打包。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |
| [X03 电视](X03-电视/README.md) | 电视外壳、焦点导航、以 pure_live_TV 为基线的并入。 | `████████████████████` 100% | 1 / 1 |
| [X04 iOS和iPadOS](X04-iOS和iPadOS/README.md) | 构建、签名、平台差异。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |
| [X05 macOS](X05-macOS/README.md) | 构建、签名、平台差异。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 2 |

## 还没完成的（7）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [X01.1](X01-Windows/X01.1-键盘鼠标操作核对/README.md) 键盘鼠标操作核对 | 未开始 | 第三档 | — |
| [X01.2](X01-Windows/X01.2-Windows专属功能/README.md) Windows 专属功能（功能清点第 13 节的 14 项） | 未开始 | 第三档 | — |
| [X01.3](X01-Windows/X01.3-Windows安装包和自动更新/README.md) Windows 安装包和自动更新 | 未开始 | 第三档 | — |
| [X02.1](X02-Linux/X02.1-Linux构建和打包/README.md) Linux 构建和打包 | 未开始 | 第三档 | — |
| [X04.1](X04-iOS和iPadOS/X04.1-苹果平台的构建和签名/README.md) 苹果平台的构建和签名 | 未开始 | 第三档 | — |
| [X05.1](X05-macOS/X05.1-macOS工程和构建/README.md) macOS 工程和构建：生成 macos/、沙盒和权限、Keychain 加密、桌面外壳，能在 Mac 上运行 | 未开始 | 第三档 | — |
| [X05.2](X05-macOS/X05.2-macOS签名和分发/README.md) macOS 签名、公证和分发，应用内更新 | 未开始 | 第三档 | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
