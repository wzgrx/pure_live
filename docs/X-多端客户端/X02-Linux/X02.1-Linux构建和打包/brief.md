# X02.1 Linux 构建和打包：任务书

## 背景

- 来源：版本路线 4.3 = Linux（`docs/PLAN.md` 第 5 节）；D-004 的客户端顺序 Android → Windows → 电视 → Linux → 苹果平台。登记时的旧编号 T17e.1。
- 现象：master 上没有 `apps/pure_live/linux/`，不能构建 Linux 版；Linux 上没有加密器（`apps/pure_live/lib/platform/secret_cipher.dart:12-14` 抛异常）、桌面外壳不启用（`apps/pure_live/lib/app/desktop/desktop_window.dart:257`）、版本页没有 Linux 的包类型。2026-10-01 做过一次（M12.6），停在界面重做之前，没合并。
- 为什么现在做：第三档，**等 4.3**（Windows 4.1、电视 4.2 之后）。
- **前置条件**：维护者同意开始 Linux 客户端；X01.3 第 1 阶段（Windows 能构建）做过，桌面外壳的问题先在 Windows 上暴露。
- **半成品**：分支 `worktree-agent-ab1a5d264e55120e5`（工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-ab1a5d264e55120e5`，最后提交 `0dc0df759`，2026-10-01），相对 master 36 个文件、+1536 −56：`96ef79583`（Linux 运行器）、`b6c86b695`（平台服务）、`2da83938d`（桌面外壳在 Linux 上）、`a63c38299`（合并当时的 master）、`0dc0df759`（Navigator 构建时改路由名的修复）。它基于 Z02.1（`4e8e9998f`）搬目录之前的 `lib/pages/` 结构。
- 已经做过的：A16.1（c2 写了 Linux 的做法，代码只看“有没有桌面外壳、托盘”，不看平台名）；`mini_window.dart:102` 已经处理 Wayland 不能置顶。

## 目标和验收

1. `apps/pure_live/linux/` 进 master；`flutter build linux --release` 在 WSL 上成功，运行到首页，进一个哔哩哔哩直播间能播放、有弹幕、能录制。
2. Linux 上：数据在 `$XDG_DATA_HOME/com.mystyle.purelive`；账号加密存储（方案维护者定）；GBK 播放列表能导入；libmpv 优先用系统库。
3. 桌面外壳在 Linux 上启用：自绘标题栏、拖边改大小、记住大小、关闭询问；托盘只在有 StatusNotifierItem 宿主时出现，否则“最小化”到任务栏；只开一个主窗口，再次启动把它带到前面；新窗口；开机自启（XDG autostart，默认关，只动自己的文件）。
4. `tools/release/linux/build.sh` 打出 `PureLive-<版本>-<构建号>-linux-x64.tar.gz` 和 SHA-256；版本页在 Linux 上能挑到它。
5. `test/linux_test.dart` 在现在的结构下通过；全部测试和门禁通过。
6. （发布时，维护者）`platforms.linux` 换到 4.x。

## 现状（读代码得出，写文件:行）

- master：没有 `apps/pure_live/linux/`；`desktop_window.dart:254-257`（`supported => Platform.isWindows`，注释写 Linux 暂停）；`secret_cipher.dart:9-14`；`apps/pure_live/lib/app/data_root.dart`（Windows 和 Android 两个分支）；`apps/pure_live/lib/features/version/update_feed.dart:204-226`（`PackageKind` 没有 Linux）、`:310`（`currentUpdatePlatform` 认 Linux）；`apps/pure_live/lib/app/desktop/startup_entry.dart`（只有 Windows 注册表）；`packages/live_player/lib/src/mpv_options.dart:4`（`MpvPlatform.linux`）；`tools/ffmpeg_kit/bundles.txt`（Linux 的 FFmpeg 包，门禁已在用）。
- 分支 `0dc0df759` 的文件（`git diff --stat master...0dc0df759`）：`apps/pure_live/linux/`（`CMakeLists.txt` 163 行、`flutter/` 4 个、`runner/CMakeLists.txt`、`runner/main.cc`、`runner/my_application.cc` 201 行、`my_application.h`、`runner/stubs/flutter_inappwebview_linux_plugin.h`、`inappwebview_stub.cc`）；`lib/platform/linux.dart`（71）、`linux_mpv_runtime.dart`（67）、`platform_services.dart`（+60）、`plugins.dart`、`secret_cipher.dart`（+191）；`lib/app/app.dart`、`bootstrap.dart`、`data_root.dart`、`desktop/desktop_window.dart`（+93）、`desktop/startup_entry.dart`（+101）、`desktop/title_bar.dart`、`desktop/tray.dart`；`lib/routes/route_observer.dart`；`lib/pages/backup/backup_files.dart`、`lib/pages/iptv/iptv_import.dart`、`lib/pages/settings/settings_catalog.dart`、`settings_editors.dart`、`settings_model.dart`（现在都在 `lib/features/` 下）；`pubspec.yaml`、`analysis_options.yaml`、翻译文件；`test/linux_test.dart`（214）、`test/pages/settings/settings_page_test.dart`。
- 读分支用 `git show 0dc0df759:<路径>` 或 `git diff master...0dc0df759 -- <路径>`，不要在那个工作区里改东西。

## 3.x 基线

- `git show v3.2.11:linux/my_application.cc`（`:92-93` 激活和命令行，`:102` `G_APPLICATION_NON_UNIQUE`）、`linux/CMakeLists.txt`。
- `git show v3.2.11:.github/workflows/build_pure_live_release.yml:395-504`：Linux 构建依赖（`:409` 起装的桌面依赖）、`flutter build linux`、校验 FFmpeg 包、打 `tar.gz`。
- 3.x 在 Linux 上 Cookie 明文；GBK 用 `charset_converter`；libmpv 用 `LinuxMpvRuntime`。
- 要保留：3.x 的设置键；3.x 在 Linux 上的数据位置（导入照读）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 3 节、第 7 节）；`docs/specs/UI.md` 第 5.4 节。
3. 本文件夹的 `README.md`；`docs/X-多端客户端/X02-Linux/README.md`、`X01-Windows/README.md`；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md`（c2）；分支上 4 个提交的说明（`git log master..0dc0df759`）。

## 范围

- 可以改：新建 `apps/pure_live/linux/`；`apps/pure_live/lib/platform/`（Linux 文件、加密器）、`lib/app/data_root.dart`、`lib/app/desktop/`（Linux 分支）、`lib/app/bootstrap.dart`、`lib/features/backup/`、`lib/features/iptv/`、`lib/features/settings/`（只加 Linux 的行和分支）、`lib/features/version/update_feed.dart`（Linux 包类型）；`apps/pure_live/pubspec.yaml`（Linux 需要的依赖）；翻译文件（只加键）；`test/`；新建 `tools/release/linux/`；本文件夹的文档。
- 不能改：Android、Windows 的原生代码和行为；桌面界面的设计（A16.1）；3.x 的设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`（发布时维护者改）；签名配置。
- 不在分支 `worktree-agent-ab1a5d264e55120e5` 的工作区里提交或改动（它是参考）。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 取回运行器，构建运行 | `apps/pure_live/linux/` | WSL 上构建运行到首页；其他平台的测试照样通过 |
| 2 | c2 平台服务（数据目录、加密器、iconv、libmpv） | `lib/platform/`、`lib/app/data_root.dart`、`bootstrap.dart`、`test/linux_test.dart` | 验收 2；能播放、录制 |
| 3 | c3 桌面外壳在 Linux 上启用 | `lib/app/desktop/`、`lib/features/settings/`、测试 | 验收 3 |
| 4 | c4 打包和应用内更新 | `tools/release/linux/`、`update_feed.dart`、`version_page_test.dart` | 验收 4；发布 4.3 时维护者做验收 6 |

每个阶段都要能单独合并（门禁通过，Linux 运行器的存在不影响 Android、Windows）。

## 测试

- `test/linux_test.dart`（从分支取，按新路径改）：数据目录选择；加密器读写、密钥文件权限 0600、目录 0700；自启文件只写自己的、别人的同名文件不动；外壳在有、没有托盘宿主时的“最小化”。
- 设置页：Linux 上显示窗口一组和自启一行（`test/features/settings/` 里 `TargetPlatform.linux`）。
- 版本页：Linux 挑出 `linux-x64.tar.gz`。
- 门禁本身在 Linux 上跑全部测试，Linux 分支的代码会被执行到；定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者做）

| 步骤 | 期望 |
|---|---|
| 1. WSL：`flutter build linux --release`，运行 `build/linux/x64/release/bundle/pure_live` | 自绘标题栏“纯粹直播”，首页 |
| 2. 再运行一次 | 不开第二个主窗口，已有窗口到前面 |
| 3. 进哔哩哔哩直播间，录制 30 秒 | 播放、弹幕、录制都正常；`~/.local/share/com.mystyle.purelive` 里有数据库 |
| 4. 设置 → 账号 粘一个 Cookie，退出再开 | 还在；`~/.config/com.mystyle.purelive/secret.key` 权限 600 |
| 5. GNOME（Wayland）：点 ✕ 选最小化；看托盘 | 没有托盘宿主时最小化到任务栏；小窗不能置顶时图钉不可用 |
| 6. KDE（X11）：同上 | 有托盘图标，单击显示窗口 |
| 7. 打开开机自启，重新登录 | 自动启动；`~/.config/autostart/` 只多了 `com.mystyle.purelive.desktop` |
| 8. 解压 `tar.gz` 到新目录运行 | 能启动；包里没有用户数据 |

## 风险和注意

- 分支上的 Dart 改动基于旧目录，**不要直接 `git merge`**，按文件重做；运行器目录可以 `git checkout 0dc0df759 -- apps/pure_live/linux` 取。
- `flutter_inappwebview` 的 Linux 插件需要 WPE WebKit，分支用桩把它从生成的插件列表里过滤掉；Flutter 重新生成 `generated_plugins.cmake` 时要保持过滤。
- 加密密钥文件放在用户目录，备份时不要带走它（否则换机器后加密的值打不开，等于丢失）。
- 可能冲突的文件：`lib/app/desktop/`（X01.1、X01.2）、`lib/app/bootstrap.dart`、`lib/features/settings/settings_catalog.dart`（A11、A04.1）。

## 环境和提交

- WSL 就是 Linux：`source ~/tools/purelive-env.sh`；需要 GTK 3、`libmpv`（或用 `lib/fallback`）、`libsecret`（如果选系统密钥环）、CMake、Ninja、clang（照 3.x 工作流 `:409` 起的依赖清单装）；WSLg 能显示窗口。
- 根目录 `bash tools/ffmpeg_kit/fetch.sh linux`，再 `flutter pub get`。
- 分支 `ai/X02.1` 或本机工作区；提交信息以 `[X02.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`bash tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（分支上的哪些文件已经重做）、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

每个阶段做到没有；从 M12.6 取了什么、重做了什么；加密方案；在哪些桌面环境上看过；测试数量；改了哪些文件；需要维护者决定的（加密方案、包的格式、M12.6 分支的去留）；可能冲突的文件。
