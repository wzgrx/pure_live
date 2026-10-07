# X01.3 Windows 安装包和自动更新

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：版本路线 4.1 = Windows（`docs/PLAN.md` 第 5 节、D-004）；3.x 在 Windows 上发布安装包、MSIX 和便携 ZIP，应用内能下载更新；4.x 的 Windows 部分从没构建过（O03.1 记录）。
- 旧编号：T17d.1
- 相关：决定 D-004、D-007、D-015；X01.1、X01.2（都依赖本任务第 1 阶段）；Y01（发布步骤）、Y02（`version.json` 的 `platforms.windows`、应用内下载）；Z04（FFmpeg 的 Windows 包 `fetch.ps1`）；G01（libmpv 的 Windows 原生包）

## 目标

1. 4.x 能在 Windows 主机上从干净的克隆构建出 release 版并正常启动（这是 X01.1、X01.2 的前提）。
2. 定下 Windows 发什么包（安装包、MSIX、便携 ZIP 里选哪些），做出来、能安装、能卸载、能覆盖安装上一个 4.x。
3. 应用内更新在 Windows 上能用：读 `platforms.windows`，挑对包，下载后运行安装包或打开 ZIP 所在文件夹。
4. 4.1 发布：发布页上传 Windows 包，最后改 `platforms.windows`（D-015）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 构建 | GitHub Actions `windows-latest`，`flutter_distributor --platform windows --targets exe,msix`（`.github/workflows/build_pure_live_release.yml:212-365`） | 没有在 Windows 上构建过；工程 `apps/pure_live/windows/CMakeLists.txt`（`BINARY_NAME pure_live`）；FFmpeg 的 Windows 包 `tools/ffmpeg_kit/fetch.ps1`、`bundles.txt` 的 `bundle-base-windows-x86_64-shared-lgpl.zip`；libmpv 由 `third_party/media_kit/hook/native_bundles.json` 的 `windows_x64` 下载 | 本机 Windows 主机能构建 |
| 安装包 | Inno Setup：`windows/packaging/exe/inno_setup.iss`（`CloseApplications=yes`，`ChineseSimplified.isl`）、`local_release.iss` | 无 | 定方案后做 |
| MSIX | `windows/packaging/msix/make_config.yaml`（`identity_name: com.mystyle.purelive`，自签名证书 `MSIX_CERT_PATH`，用户要手动信任证书，`docs/MSIX_INSTALL.md`） | 无；`version.json` 的 `windows_msix_available: false` | 维护者定要不要 |
| 便携 ZIP | `PureLive-<版本>-windows-x64-portable.zip`，检查不含运行时数据（工作流 `:325-365`） | 数据目录默认就是 exe 旁边的 `UserData`（`apps/pure_live/lib/app/data_root.dart:10-13`），天然便携 | 打包时不能带 `UserData` |
| 应用内更新 | 下载安装包运行、ZIP 打开文件夹 | `apps/pure_live/lib/features/version/update_feed.dart:214-221` 的 `PackageKind.windowsSetup`（`windows-x64-setup.exe`）、`windowsMsix`、`windowsPortable`；`update_download.dart:295-340` Windows 运行安装包、ZIP 用 `explorer.exe /select,` | 实际在 Windows 上走通 |
| 更新文件 | `platforms.windows` | 还是 3.2.11 / 4134（`assets/version.json`） | 4.1 发布时改成 4.x |
| 3.x 用户升级 | — | 3.x 便携版数据在 `<exe 目录>\AppData`，4.x 只在导入时读 | 写清 3.x 用户怎么升级（覆盖还是另装）；导入验证在 X01.2 c5 和 J06 |
| 开机启动 | 3.x 的 `pure_live`（用户机器上有） | 4.x 写 `PureLiveV4`，只 release 构建按设置写（`lib/app/desktop/startup_entry.dart:12`） | 安装包卸载时删掉 `PureLiveV4` |
| 版本信息 | — | `windows/runner/Runner.rc:92-98`（公司 `com.mystyle`、版权 2025） | 定发布者信息 |

## 方案

- c1（第 1 阶段）能构建运行：Windows 主机拉分支，`tools\ffmpeg_kit\fetch.ps1`、`flutter pub get`、`flutter build windows --release`；修编译和启动的问题（插件的 Windows 部分、原生包下载、`flutter_inappwebview` 预发布版在 Windows 上的情况）；启动到首页、能进一个哔哩哔哩直播间播放。
- c2 包的方案（维护者定，建议 A）：A 安装包 + 便携 ZIP（和 3.x 一样，不做 MSIX：自签名 MSIX 要用户手动信任证书，体验差）；B 三种都做；C 只做便携 ZIP。安装包用 Inno Setup（照 3.x 的 `.iss`），默认装到用户目录（不需要管理员），卸载时删开机启动项 `PureLiveV4`，不删 `UserData`（问用户）。
- c3 打包脚本：`tools/release/windows/`（`build.ps1`：构建、打 ZIP（排除 `UserData`）、调 Inno Setup 编译 `.iss`、算 SHA-256），命名照 3.x：`PureLive-<版本>-<构建号>-windows-x64-setup.exe`、`…-windows-x64-portable.zip`。
- c4 应用内更新：在 Windows 上从一个更低版本的 4.x 走一遍检查更新、下载、运行安装包（或打开 ZIP 文件夹）。
- c5 发布 4.1：照 PROCESS 第 11 节，最后改 `platforms.windows`；发布说明写 Windows 一节（Y03）。

## 验证

- 自动测试：打包脚本没有单元测试条件（PowerShell）；应用内挑包的逻辑已有测试（`apps/pure_live/test/features/version/version_page_test.dart` 的“按平台和 ABI 挑包”，`:158` 起已经有 Windows 的用例：读 `platforms.windows` 得到 3.2.11、挑出安装包和便携 ZIP）；发布 4.1 改 `version.json` 后这个用例要跟着改。
- 真机：Windows 主机（brief 的真机步骤）；不碰 `D:\Soft` 下的 3.x。

## 留下的问题

- 还没开始。3.x 的 Windows 用户怎么升级到 4.x（覆盖安装进 3.x 的目录，还是另装再导入）要维护者定；3.x 便携版的数据在 exe 旁边，覆盖解压会和 4.x 的 `UserData` 并存。
- Windows 代码签名证书（让 SmartScreen 不拦）没有；要不要买、发布者名字写什么，维护者定（Y01.4 的 Windows 部分）。
