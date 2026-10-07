# X02.1 Linux 构建和打包

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：版本路线 4.3 = Linux（`docs/PLAN.md` 第 5 节、D-004）；3.x 发布过 Linux 便携包（`platforms.linux` 停在 3.2.10）。
- 旧编号：T17e.1
- 相关：决定 D-004；X01（桌面外壳同一套代码）；A16.1 c2（Linux 的界面做法）；没合并的 M12.6（分支 `worktree-agent-ab1a5d264e55120e5`，最后提交 `0dc0df759`）；Y01、Y02（发布和更新通道）；Z04（FFmpeg 的 Linux 包）

## 目标

4.x 能在 Linux 上构建、运行、打包发布：Linux 运行器进 master；数据目录、加密存储、编码、libmpv 在 Linux 上可用；桌面外壳（自绘标题栏、托盘、关闭、只开一个、新窗口、开机自启）在 Linux 上打开；做出便携包，版本页能在 Linux 上挑到它；发布 4.3 时 `platforms.linux` 从 3.2.10 换到 4.x。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | master 现在 | 没合并的 M12.6（`0dc0df759`） | 要做到 |
|---|---|---|---|---|
| 运行器 | `linux/`（`my_application.cc:102` `G_APPLICATION_NON_UNIQUE`，每次另开进程；应用 id `com.example.pure_live`） | 没有 `apps/pure_live/linux/` | 有：应用 id `com.mystyle.purelive`、中文窗口名、主窗口单实例、`flutter_inappwebview` Linux 插件过滤并打桩、libmpv 备用库 | 运行器进 master |
| 数据目录 | `<documents>/PURE_LIVE/…` | 没有 Linux 分支（`apps/pure_live/lib/app/data_root.dart`） | `$XDG_DATA_HOME/com.mystyle.purelive`，3.x 的 `HIVE_DB` 照读 | 同 M12.6 |
| 加密存储 | 明文 | 没有（`apps/pure_live/lib/platform/secret_cipher.dart:12-14` 在 Linux 上抛异常） | OpenSSL AES-256-GCM，密钥文件 `$XDG_CONFIG_HOME/com.mystyle.purelive/secret.key`（0600） | 同 M12.6 或用系统的密钥环（维护者定） |
| 桌面外壳 | 隐藏系统标题栏但没画自己的 | `DesktopShell.supported` 只有 Windows（`desktop_window.dart:257`） | Linux 上打开；Wayland 下没有位置；托盘只在有 StatusNotifierItem 宿主时出现 | 同 M12.6 |
| 开机自启 | 没有 | 只有 Windows 注册表（`startup_entry.dart`） | `~/.config/autostart/com.mystyle.purelive.desktop`（带标记行），Linux 默认关 | 同 M12.6 |
| 包 | `PureLive-<版本>-linux-x64.tar.gz`（`.github/workflows/build_pure_live_release.yml:395-504`） | 无；`update_feed.dart:204-226` 没有 Linux 包类型 | 无 | `tar.gz`（加不加 AppImage、deb 维护者定），版本页能挑到 |

## 方案

- c1（第 1 阶段）取回运行器：从 `0dc0df759` 取 `apps/pure_live/linux/`（`CMakeLists.txt`、`flutter/`、`runner/`、`runner/stubs/`），在 WSL（WSLg）上 `flutter build linux --release` 并运行到首页。
- c2（第 2 阶段）平台服务：按现在的目录结构重做 M12.6 的 Dart 部分——`lib/platform/linux.dart`、`linux_mpv_runtime.dart`、`secret_cipher.dart` 的 Linux 加密器、`data_root.dart` 的 Linux 分支、iconv；原来改的 `lib/pages/backup/backup_files.dart`、`lib/pages/iptv/iptv_import.dart`、`lib/pages/settings/settings_catalog.dart`、`settings_model.dart`、`settings_editors.dart` 现在在 `lib/features/backup/`、`lib/features/iptv/`、`lib/features/settings/` 下；带上 `test/linux_test.dart`。
- c3（第 3 阶段）桌面外壳：`DesktopShell.supported` 加 Linux；标题栏、托盘（检测 StatusNotifierItem）、关闭、新窗口、自启照 M12.6；A16.1 c2 的“只开一个”在运行器里。
- c4（第 4 阶段）打包和更新：`tools/release/linux/build.sh` 打 `PureLive-<版本>-<构建号>-linux-x64.tar.gz`（不含用户数据）；`PackageKind` 加 `linuxTarGz`（3.x 的键名照旧，如果 3.x 有）；发布 4.3 时改 `platforms.linux`（维护者）。

## 验证

- 自动测试：`test/linux_test.dart`（数据目录、加密器的读写和权限、自启文件只动自己的、外壳开关）；版本页挑包加 Linux 用例。
- 真机：WSLg 上构建运行；一台真正的 Linux 桌面（GNOME/Wayland、KDE/X11）看托盘、置顶、自启、单实例（brief 的真机步骤）。

## 留下的问题

- 还没开始。M12.6 的分支登记表没有记录；维护者先决定是保留到 X02.1 开工，还是现在就把运行器取进 master（运行器不影响其他平台）。
- 加密存储用自己的密钥文件还是系统的密钥环（libsecret），维护者定；M12.6 选了前者（不依赖桌面环境）。
