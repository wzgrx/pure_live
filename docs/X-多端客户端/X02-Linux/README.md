# X02 Linux

4.x 的 Linux 桌面客户端（版本路线 4.3）：Linux 运行器、Linux 上的平台服务（数据目录、加密存储、编码转换、libmpv）、桌面外壳在 Linux 上启用，以及打包和发布。

## 范围

- 包括：`apps/pure_live/linux/` 运行器（master 上还没有）、Dart 侧的 Linux 分支（数据目录、加密器、播放内核的系统库、打开文件和文件夹、开机自启）、Linux 打包（3.x 是 `tar.gz` 便携包）、`version.json` 的 `platforms.linux` 块的内容。
- 不包括（归哪里）：
  - 桌面外壳本身（标题栏、托盘、关闭、新窗口、小窗）→ X01（同一套代码，Linux 只是打开开关）；界面 → A16.1（c2 写了 Linux 的做法：同一个标题栏、单实例、窗口名）。
  - 录制的 FFmpeg Linux 包 → Z04（`tools/ffmpeg_kit/bundles.txt` 已有 `bundle-base-linux-x86_64-shared-lgpl.zip`，门禁跑 `flutter test` 时就用它）。
  - 发布页和更新文件 → Y01、Y02。

## 现状：做到哪、怎么工作的

- **master 上没有 Linux 运行器**（`apps/pure_live/linux/` 不存在），所以 `flutter build linux` 做不了；`flutter test` 在 Linux 主机上跑（门禁），只说明 Dart 代码能在 Linux 的测试环境里运行。
- `DesktopShell.supported` 只在 Windows 为真（`apps/pure_live/lib/app/desktop/desktop_window.dart:257`，注释：“the Linux desktop build is paused (M12.6)”）；`secret_cipher.dart:12-14` 在 Linux 上抛 `UnsupportedError`（没有加密器）；`update_feed.dart:310` 能识别 Linux 平台，但 `PackageKind`（`:204-226`）没有 Linux 的包类型，版本页在 Linux 上挑不出安装包。
- **没合并的半成品 M12.6**：分支 `worktree-agent-ab1a5d264e55120e5`（工作区 `.claude/worktrees/agent-ab1a5d264e55120e5`，最后提交 `0dc0df759`，2026-10-01），4 个提交、36 个文件、约 1500 行：
  - `96ef79583` Linux 运行器：`flutter create --platforms=linux` 生成后照 3.x 改——应用 id `com.mystyle.purelive`（3.x 是 `com.example.pure_live`）、中文窗口名、图标、首次 1280×720；主窗口在会话总线上占用 id，再次启动把已有窗口带到前面（3.x 是 `G_APPLICATION_NON_UNIQUE`，`git show v3.2.11:linux/my_application.cc:102`），`--instance=` 的新窗口不占；`flutter_inappwebview` 的 Linux 插件被过滤掉并用桩代替（它要 WPE WebKit，Linux 上用系统浏览器）；3.x 的 libmpv 备用库拷进 `lib/fallback`。
  - `b6c86b695` Linux 平台服务：数据目录 `$XDG_DATA_HOME/com.mystyle.purelive`；加密存储用系统 OpenSSL 的 AES-256-GCM，密钥文件 `$XDG_CONFIG_HOME/com.mystyle.purelive/secret.key`（权限 0600，目录 0700；3.x 是明文）；GBK 播放列表用 glibc 的 iconv；3.x 的 `LinuxMpvRuntime`（系统缺的 libmpv 依赖才用 `lib/fallback` 里的）；`xdg-open` 打开文件和文件夹。
  - `2da83938d` 桌面外壳在 Linux 上启用：隐藏系统标题栏、画自己的（3.x 隐藏了却没画）、Linux 上的拖边改大小、记住大小（Wayland 没有位置）；托盘只在会话总线上有 StatusNotifierItem 宿主时出现，否则“最小化”到任务栏；开机自启写 `~/.config/autostart/com.mystyle.purelive.desktop`（带标记行，别人的同名文件不动），Linux 上默认关；设置加 Linux 的窗口一组和自启一行；测试 `test/linux_test.dart`（214 行）。
  - `0dc0df759` 修 Navigator 构建时改路由名的 `setState` 警告。
  - 它基于界面目录搬家（Z02.1，`4e8e9998f`）**之前**的结构：改的是 `lib/pages/backup/`、`lib/pages/iptv/`、`lib/pages/settings/`，这些现在在 `lib/features/` 下；直接合并会大量冲突，要按现在的路径重做 Dart 部分，运行器（`linux/` 目录）可以直接取。登记表没有记录这个分支（X02.1 没有 `branch` 或 `note`）。
- 完成度：X02.1 未开始。

## 代码地图

master 上的：

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/desktop/desktop_window.dart:254-257` | `DesktopShell.supported`（只有 Windows），Linux 打开开关的地方 |
| `apps/pure_live/lib/app/desktop/mini_window.dart:102` | Wayland 下不能置顶（GNOME 不允许）的判断，已经为 Linux 写好 |
| `apps/pure_live/lib/platform/secret_cipher.dart:9-14` | 加密器的平台选择（Linux 没有） |
| `apps/pure_live/lib/app/data_root.dart` | 数据目录（没有 Linux 分支，落到默认） |
| `apps/pure_live/lib/features/version/update_feed.dart:204-226`、`:305-313` | 包类型（没有 Linux）、当前平台 |
| `packages/live_player/lib/src/mpv_options.dart:4` | `MpvPlatform` 里有 `linux` |
| `tools/ffmpeg_kit/bundles.txt` | Linux 的 FFmpeg 包 |

没合并的（分支 `worktree-agent-ab1a5d264e55120e5`）：`apps/pure_live/linux/`（`CMakeLists.txt` 163 行、`runner/my_application.cc` 201 行、`runner/stubs/` 两个桩文件）、`lib/platform/linux.dart`（71）、`lib/platform/linux_mpv_runtime.dart`（67）、`lib/platform/secret_cipher.dart`（+191）、`lib/app/desktop/` 四个文件的 Linux 分支、`test/linux_test.dart`（214）。

测试：master 上没有 Linux 专门的测试（门禁在 Linux 上跑全部 `flutter test`）；分支上有 `test/linux_test.dart`。

## 3.x 基线

- `git show v3.2.11:linux/`：`CMakeLists.txt`、`main.cc`、`my_application.cc`（`G_APPLICATION_NON_UNIQUE` `:102`，每次启动另开一个进程）。
- 3.x 的 Linux 发布：`.github/workflows/build_pure_live_release.yml:395-504`（装桌面依赖、`flutter build linux`、校验 FFmpeg 包、打 `PureLive-<版本>-linux-x64.tar.gz`）；`assets/version.json` 的 `platforms.linux` 停在 3.2.10 / 4133。
- 3.x 的 `LinuxMpvRuntime`（libmpv 系统库和备用库）、`charset_converter`（GBK）。
- 要保留：3.x 的设置键；3.x 在 Linux 上的数据位置（`<documents>/PURE_LIVE/HIVE_DB`，分支上的导入已经照读）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| master 上没有 Linux 运行器；AGENTS.md 的“目录”一节写 `apps/pure_live` 有 Linux | `AGENTS.md` | 文档和代码不符 | X02.1；AGENTS.md 由维护者改（或 X02.1 合并后自然成立） |
| M12.6 半成品在一个代理工作区分支里，登记表没记，按“清理代理工作区”可能被删 | 分支 `worktree-agent-ab1a5d264e55120e5` | 丢掉 1500 行能用的 Linux 工作 | 建议维护者在 X02.1 的 `branch` 里登记；Z07.1 的规则里写了“没合并的先问” |
| Linux 上没有加密器 | `secret_cipher.dart:12-14` | 不补的话账号无处可存 | X02.1（分支上已有 OpenSSL 方案） |
| 版本页没有 Linux 的包类型 | `update_feed.dart:204-226` | Linux 上应用内更新只能打开发布页 | X02.1 |
| `platforms.linux` 停在 3.2.10 | `assets/version.json` | 3.x 的 Linux 用户不会被推到 4.x（有意） | X02.1 发布时改 |

## 相关决定和规范

- D-004（客户端顺序：Linux 在电视之后，版本路线 4.3）。
- A16.1 c2（Linux 用同一个标题栏、只开一个、窗口名“纯粹直播”）；ENGINEERING 第 3 节（只在本机构建）。

## 测试和验证

- 自动：分支上的 `test/linux_test.dart`（数据目录、加密器、自启文件、外壳开关）；X02.1 重做后放进现在的结构。
- 真机：WSL 本身就是 Linux（有 WSLg 可以开窗口），可以构建和运行；另需要一台真正的 Linux 桌面（GNOME/Wayland、KDE/X11 各一）看托盘、置顶、自启。

## 路线

1. X02.1（第三档，中）：按现在的目录结构把 M12.6 重做进来（运行器直接取、Dart 部分按新路径改），补 Linux 的包类型，打 `tar.gz`（是否加 AppImage 或 deb 由维护者定），发布 4.3。
2. 前提：Windows（4.1）和电视（4.2）之后（D-004）；但 M12.6 的分支越放越旧，建议维护者先决定它的去留。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [X 多端客户端](../README.md)。

- 代码：—
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| X02.1 | Linux 构建和打包 | 发布 | 未开始 | — | — | [设计或说明](X02.1-Linux构建和打包/README.md)、[任务书](X02.1-Linux构建和打包/brief.md) |

## 还没完成的

- **X02.1 Linux 构建和打包**（未开始，第三档，规模 中）
  - 分支：.claude/worktrees/agent-ab1a5d264e55120e5
  - 说明：没合并的 Linux 桌面外壳半成品（旧编号 M12.6，提交 0dc0df759，36 个文件）在 branch 的工作区里，清理工作区前先看 X02.1

<!-- docs:生成结束 -->
