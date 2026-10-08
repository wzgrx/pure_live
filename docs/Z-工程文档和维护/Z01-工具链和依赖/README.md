# Z01 工具链和依赖

管 4.x 用哪个版本的 Flutter、Dart、Gradle、AGP、Kotlin、JDK、NDK、Android SDK、mpv、FFmpeg 和 pub 依赖，版本写在哪里、怎么查有没有新的、升级时怎么验证。

## 范围

- 包括：
  - `toolchain.env`：工具链的唯一来源（13 个键，见下面“现状”）。
  - 根 `pubspec.yaml`：pub workspace 的 13 个成员、共用的 `pubspec.lock`、`dependency_overrides`（只能写在这里）、录制用 FFmpeg 包的 `ffmpeg_kit_extended_config`。
  - `tools/check_latest/`：对照官方渠道查最新稳定版的命令行工具。
  - 本机环境脚本 `~/tools/purelive-env.sh`（不在仓库里）和 `toolchain.env` 一致。
- 不包括（归哪里）：
  - 自维护的 media_kit 分支 `third_party/media_kit`、`third_party/media_kit_video` 的补丁内容 → G01（引擎）；本子分类只管 `toolchain.env` 里记的上游提交和 `check_latest` 对它的检查。
  - FFmpeg 原生包的下载和缓存（`tools/ffmpeg_kit/`）→ Z04；版本号 `FFMPEG_VERSION` 在这里。
  - 门禁本身 → Z02；升级后跑门禁是这里的要求。
  - Windows 主机上的 Flutter（`C:\Users\123\claude-work\flutter`）→ X01.3。

## 现状：做到哪、怎么工作的

- 版本（`toolchain.env`，2026-09-28 核对时全部是最新稳定版）：

| 键 | 值 | 用在哪 |
|---|---|---|
| `FLUTTER_VERSION`、`DART_VERSION` | 3.47.5、3.13.4 | 全部成员；根 `pubspec.yaml` 的 `sdk: ^3.13.0` |
| `GRADLE_VERSION`、`AGP_VERSION`、`KOTLIN_VERSION` | 9.8.0、9.4.1、2.4.20 | `apps/pure_live/android/`（AGP 9 自带 Kotlin，`gradle.properties` 的 `android.builtInKotlin=true`） |
| `JDK_FEATURE_VERSION` | 27 | Gradle 运行时；字节码目标 17（`build.gradle.kts` 的 `JavaVersion.VERSION_17`） |
| `ANDROID_COMPILE_SDK`、`ANDROID_BUILD_TOOLS`、`ANDROID_NDK_VERSION` | 37.2、37.0.0、30.0.16248370 | `build.gradle.kts`（`compileSdk = 37`、`targetSdk = 37`、`minSdk = 26`） |
| `MPV_VERSION`、`FFMPEG_VERSION` | 0.41.0、9.0.2 | 播放内核（`third_party/media_kit` 的原生包）、录制的 FFmpeg（`tools/ffmpeg_kit/bundles.txt`） |
| `MEDIA_KIT_UPSTREAM_REPO`、`MEDIA_KIT_UPSTREAM_COMMIT` | `Predidit/media-kit`、`803c4a27` | 自维护分支对应的上游提交 |

- 依赖：13 个 workspace 成员（`apps/pure_live`、11 个 `packages/live_*`、`tools/check_latest`）直接依赖 63 个包，其中 46 个来自 pub.dev。`dependency_overrides` 7 项：`media_kit`、`media_kit_video`（指向 `third_party/`）、`wakelock_plus 1.8.1`、`xml 7.1.0`、`test_api 0.7.14`、`code_assets 2.1.0`、`nm 0.6.0`、`dbus 0.8.0`（根 `pubspec.yaml:26-64`，每项上面写了为什么、3.x 有没有同样的覆盖）。
- 检查最新版：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`。`collect`（`tools/check_latest/lib/check_latest.dart:159`）依次查 Flutter（官方 releases JSON）、Gradle（`services.gradle.org`）、AGP、Kotlin、JDK（Adoptium）、NDK、compileSdk、build-tools（`dl.google.com` 的 `repository2-3.xml`）、mpv、FFmpeg（GitHub）、media_kit 上游最新提交，再对 workspace 里每个 pub.dev 依赖查 `pub.dev/api/packages/<名>`；输出 Markdown 表（落后的排前面，`renderMarkdown` `:241`），有落后的退出码 1（`--report-only` 改成 0），`--json`、`--skip-pub` 可选（`bin/check_latest.dart:8-12`）。不带令牌时 GitHub 接口会 403。
- 升级的规矩（ENGINEERING 第 2 节第 4 条、第 3 节）：用最新稳定版；升级时连同本机环境（`~/tools/purelive-env.sh` 里的 Flutter、JDK、SDK 路径）一起改并验证，`toolchain.env` 只在验证过以后改。
- 完成度：Z01.1（2026-09-28）把以上全部建好，`check_latest` 当天 16 项、落后 0；之后**没有再跑过**（Z01.2 每月一次，未开始）。`toolchain.env` 只在 `c613b73f9` 改过注释里的文档路径，版本没动。

## 代码地图

| 文件 | 职责 |
|---|---|
| `toolchain.env`（19 行） | 工具链版本，唯一来源；注释写明只在验证过的升级后改 |
| `pubspec.yaml`（根，72 行） | workspace 成员（`:10-23`）、`dependency_overrides`（`:26-64`）、`ffmpeg_kit_extended_config`（`:66-72`） |
| `pubspec.lock`（根） | 全部成员共用的锁文件 |
| `tools/check_latest/lib/check_latest.dart`（255 行） | `Finding`（`:13`，`isBehind` 按版本号比较）、`readEnvFile`（`:64`）、`readWorkspaceDirectDependencies`（`:93`）、`readWorkspaceMembers`（`:108`）、`highestStable`（`:113`，跳过预发布）、`Fetcher`（`:129`，60 秒超时，带 `GITHUB_TOKEN`）、`collect`（`:159`）、`renderMarkdown`（`:241`） |
| `tools/check_latest/bin/check_latest.dart`（54 行） | 命令行参数、读 `toolchain.env` 和锁文件、退出码 |
| `apps/pure_live/android/gradle.properties` | Gradle 守护进程、并行、配置缓存、AGP 内置 Kotlin、`skipDependencyChecks=true`（Flutter 3.47 的 Kotlin 版本检查不认 AGP 内置的编译器） |
| `apps/pure_live/android/gradle/wrapper/gradle-wrapper.properties` | Gradle 版本（要和 `GRADLE_VERSION` 一致） |
| `~/tools/purelive-env.sh`（仓库外） | 本机的 `FLUTTER_ROOT`、`JAVA_HOME`（temurin27）、`ANDROID_HOME`、`ANDROID_USER_HOME=~/.android-purelive`、`GRADLE_USER_HOME=~/.gradle-purelive-v4`、代理、`FLUTTER_STORAGE_BASE_URL` 镜像 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `tools/check_latest/test/check_latest_test.dart`（5 个） | 读 env 跳过注释；只取直接的 hosted 依赖；`highestStable` 跳过预发布和不匹配的前缀；`isBehind` 按版本比较；workspace 成员的直接依赖从各自 pubspec 取、版本从锁文件取 |

## 3.x 基线

- 3.x 是单个包（`git show v3.2.11:pubspec.yaml`，`version: 3.2.11+4134`），Flutter 版本写在 `.fvmrc` 和各工作流的 `FLUTTER_VERSION`（例如 `.github/workflows/build-ios-unsigned.yml` 的 `env.FLUTTER_VERSION: 3.47.5`），依赖更新靠 `.github/dependabot.yml`；本地依赖补丁放在 `plugins/` 和 `third_party/`。
- 3.x 的依赖覆盖（`code_assets`、`nm`、`dbus`）4.x 照样需要，根 `pubspec.yaml` 的注释写了“3.x shipped the same override”。
- 要保留的：用最新稳定版；FFmpeg 9.0.2 的原生包沿用 3.x 验证过的构建（`native-ffmpeg-9.0.2-b1`）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 2026-09-28 之后没跑过 `check_latest`，不知道现在落后多少 | `tools/check_latest/` | 安全修复和平台改动可能漏掉 | Z01.2 |
| `check_latest` 只对照 `toolchain.env`，不查 `gradle-wrapper.properties` 和 `build.gradle.kts` 里写的版本是不是和它一致 | `tools/check_latest/lib/check_latest.dart:159` | 两处不一致时不会被发现 | Z01.2 第 1 次做时顺手核对，长期在 Z01.2 的说明里写成检查项 |
| `check_deps.py` 的允许表里有不存在的成员 `tools/live_cli` | `tools/gate/check_deps.py:34`、`:41` | 规则表和仓库不一致（不会报错，因为只检查 workspace 里有的成员） | E07.1 取回 `tools/live_cli` 时成立；不取回就删掉这两处 |
| `gradle.properties` 关掉了依赖检查（`skipDependencyChecks=true`）和依赖验证（`org.gradle.dependency.verification=off`） | `apps/pure_live/android/gradle.properties` | 升级 Flutter 后 Gradle 侧的版本冲突不会在配置阶段报出 | 升级 Flutter 时在 Z01.2 的步骤里专门做一次 release 构建 |

## 相关决定和规范

- D-002：master 清空重来，只借鉴归档 v4 的工程工具（Z01.1 的来源）。
- D-007：推送前门禁必须通过（升级依赖也一样）。
- ENGINEERING 第 2 节第 4 条（最新稳定版）、第 3 节（工具链和结构）、第 4 节（核心依赖和分层）。

## 测试和验证

- `dart test tools/check_latest`（门禁 `--all` 里对它跑格式、分析和测试）。
- 升级后的验证：`bash tools/gate/gate.sh --all` 全部通过；`apps/pure_live` 里 `flutter build apk --release --split-per-abi` 成功；K90 上装同一提交的测试包冒烟（S02 的 CHECKLIST 第 1 节“看直播”）。

## 路线

1. Z01.2（第三档，小）：每月跑一次 `check_latest`，结果写进任务的 `record.md`；有落后的逐个判断要不要升，升级在独立分支上做、门禁和构建通过才合并。第一次做时把“版本写在几处、要一起改”的清单写进本说明。
2. 以后加 Windows（X01.3）、Linux（X02.1）构建时，把它们需要的版本（Visual Studio、CMake、GTK）也写进 `toolchain.env` 并让 `check_latest` 能查。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`toolchain.env`、`tools/check_latest/`
- 进度：`█████████████████░░░` 87%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z01.1 | 工程底座：工具链、门禁、代码规范 | 工程 | 完成 | 2026-09-28 | 4aaeb0fda | [设计或说明](Z01.1-工程底座/README.md)、[记录](Z01.1-工程底座/record.md) |
| Z01.2 | 例行依赖升级检查（每月用 check_latest 查一次，升级后跑门禁） | 工程 | 开发中 | — | — | [设计或说明](Z01.2-例行依赖升级检查/README.md)、[任务书](Z01.2-例行依赖升级检查/brief.md)、[记录](Z01.2-例行依赖升级检查/record.md) |

## 还没完成的

- **Z01.2 例行依赖升级检查（每月用 check_latest 查一次，升级后跑门禁）**（开发中，第三档，规模 小）
  - 接着做：工具链：Flutter 3.47.6、Gradle 9.8.1（改 toolchain.env，跑门禁和一次构建）；之后每月一次

<!-- docs:生成结束 -->
