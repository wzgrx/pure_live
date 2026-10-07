# Z01.2 例行依赖升级检查：任务书

## 背景

- 来源：[PROCESS.md](../../../PROCESS.md) 第 12 节维护表“每月：依赖和工具链检查（`check_latest`）”；ENGINEERING 第 2 节第 4 条“工具链和依赖用最新稳定版，升级时连同本机环境一起验证”。登记时的旧编号 T00a.2。
- 现象：`tools/check_latest` 只在 2026-09-28（Z01.1）跑过一次，当时 workspace 只有它自己一个成员、5 个直接依赖。2026-10-01 各模块合并后成员变成 13 个、pub.dev 直接依赖 46 个，没人再看过有没有落后。
- 为什么现在做：第三档；没有用户反馈的问题依赖于此，但每月固定做一次能及时拿到安全修复和平台改动（例如 Android SDK、AGP 对新系统的适配）。
- 已经做过的：Z01.1（`4aaeb0fda`）建了 `toolchain.env` 和 `check_latest`。

## 目标和验收

1. 跑一次 `check_latest`，完整输出表（工具链 10 项、media_kit 上游 1 项、pub 依赖 46 项）存进本文件夹 `record.md`，写日期和提交。
2. `record.md` 有一张“版本写在几处”的核对表：`toolchain.env` 的每一项和仓库里其他写着同一版本的地方是否一致（见“现状”）。
3. 每个落后的项目有结论：升 / 不升（原因）/ 等（等什么）。
4. 决定升的：在独立分支上升级，门禁 `--all` 通过、release 构建成功，合并后 `toolchain.env` 或 `pubspec.lock` 已更新。
5. 每月步骤写进本文件夹 `README.md` 的“方案”下面一节“每月步骤”，下个月照做（登记表另开新任务或在本任务的 `record.md` 追加，由维护者定）。

## 现状（读代码得出，写文件:行）

- `tools/check_latest/bin/check_latest.dart:8-12`：参数 `--root`、`--json`、`--report-only`（落后也返回 0）、`--skip-pub`；`:46-53` 打印结果，`behind > 0` 且没加 `--report-only` 时退出码 1。
- `tools/check_latest/lib/check_latest.dart:159` 的 `collect`：工具链 Flutter、Gradle、AGP、Kotlin、JDK、NDK、compileSdk、build-tools、mpv、FFmpeg（`:175-224`），media_kit 上游最新提交（`:225-229`），然后每个 pub 依赖（`:230-235`，`pub.dev/api/packages/<名>`）；`Fetcher`（`:129`）每个请求 60 秒超时，带 `GITHUB_TOKEN` 时加授权头。
- 版本写在几处（除 `toolchain.env` 外）：
  - Gradle：`apps/pure_live/android/gradle/wrapper/gradle-wrapper.properties`（`gradle-9.8.0-all.zip`）。
  - AGP：`apps/pure_live/android/settings.gradle.kts:23`（`com.android.application` `9.4.1`）。
  - compileSdk、targetSdk、minSdk：`apps/pure_live/android/app/build.gradle.kts`（`compileSdk = 37`、`targetSdk = 37`、`minSdk = 26`）；NDK 用 `flutter.ndkVersion`。
  - Dart SDK 约束：根 `pubspec.yaml` 的 `sdk: ^3.13.0` 和各成员的 `environment`。
  - FFmpeg 原生包：`tools/ffmpeg_kit/bundles.txt`（3 个包和 SHA-256，`native-ffmpeg-9.0.2-b1`）。
  - 本机：`~/tools/purelive-env.sh`（`FLUTTER_ROOT=~/tools/flutter-sdk/3.47.5`、`JAVA_HOME=~/tools/temurin27`）；Windows 主机的 Flutter 在 `C:\Users\123\claude-work\flutter`。
- 被覆盖压住的依赖（根 `pubspec.yaml:26-64`，每项有原因）：`wakelock_plus 1.8.1`、`xml 7.1.0`、`test_api 0.7.14`、`code_assets 2.1.0`、`nm 0.6.0`、`dbus 0.8.0`；`media_kit`、`media_kit_video` 指向 `third_party/`。

## 3.x 基线

- 3.x 用 dependabot（`git show v3.2.11:.github/dependabot.yml:3-20`）：pub 和 Gradle 每月各最多 5 个 PR；没有人工核对和验证流程。4.x 改成人工每月看一次、验证后再升。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 8 节合并审查、第 12 节维护、第 14 节规则）。
2. `docs/specs/ENGINEERING.md` 第 2～4 节。
3. 本文件夹的 `README.md`；[Z01.1 记录](../Z01.1-工程底座/record.md)（上次的结果和查询方式）；`toolchain.env`；根 `pubspec.yaml` 的 `dependency_overrides` 注释。

## 范围

- 可以改：`toolchain.env`；成员的 `pubspec.yaml` 依赖版本和根 `pubspec.lock`；根 `pubspec.yaml` 的 `dependency_overrides`（原因不在了就删）；`gradle-wrapper.properties`、`settings.gradle.kts`、`build.gradle.kts` 里的版本号；本文件夹的文档。
- 不能改：功能代码（升级需要改代码适配时，停下另开任务）；`third_party/media_kit*` 的补丁（G01）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。
- 不在 WSL 上装或改 Windows 主机的 Flutter（X01.3 的事）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 跑检查、c2 核对版本写在几处、c3 逐项结论 | `record.md` | 验收 1～3 |
| 2 | c4 升级：补丁版和次版本的 pub 依赖一次升；工具链（Flutter、AGP、Kotlin、NDK、JDK）每样单独一个分支 | `toolchain.env`、`pubspec.yaml`、`pubspec.lock`、Gradle 文件 | 门禁 `--all` 通过；`flutter build apk --release --split-per-abi` 成功；合并 |
| 3 | c5 写每月步骤 | `README.md` | 下个月的人只读 README 就能做 |

没有落后的项目时第 2 阶段跳过。

## 测试

- 不写新测试。验证靠门禁 `bash tools/gate/gate.sh --all`（13 个成员的格式、分析、测试，加 `tools/gate/tests`）和 release 构建。
- 升级了 Flutter 或 `flutter_test` 相关时，注意根 `pubspec.yaml` 的 `test_api` 覆盖（Flutter 3.47.5 的 `flutter_test` 锁 0.7.12、纯 Dart 成员的 `test 1.32.0` 要 0.7.14）。

## 真机验证（维护者在 K90 上做）

只有升级了工具链或播放、录制相关的依赖时需要：

| 步骤 | 期望 |
|---|---|
| 1. 装升级后同一提交的测试包（`flutter build apk --profile --split-per-abi`，arm64） | 覆盖安装测试包成功，不影响正式包 |
| 2. 启动，首页下拉刷新，进一个哔哩哔哩直播间 | 几秒内出画面和声音，弹幕在飞 |
| 3. 开始录制 30 秒再停止 | 录制中心里有这次录制，能播放 |
| 4. 横屏全屏、退出直播间 | 正常，没有崩溃 |

## 风险和注意

- 没有 `GITHUB_TOKEN` 时 GitHub 接口返回 403，那几项显示“查询失败”；用 `gh auth token` 取。
- Flutter 升级会连带 `flutter_test` 锁定的包版本变化，常见是 `test_api`、`material_color_utilities` 冲突：看根 `pubspec.yaml` 覆盖的注释。
- `gradle.properties` 关了 `skipDependencyChecks` 和依赖验证，Gradle 侧冲突要到真正构建才暴露：升级 AGP、Kotlin、Gradle 后一定做一次 release 构建。
- 门禁运行时不要在同一份代码里构建正式包（PROCESS 第 8 节第 5 条）。
- 可能冲突的文件：`pubspec.lock`（任何加依赖的任务都会改）；合并时以重新 `flutter pub get` 的结果为准。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 检查：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart --report-only`。
- 分支 `ai/Z01.2` 或本机工作区；提交信息以 `[Z01.2]` 开头（英文）；不推 master。
- 提交前：`bash tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪些项已经有结论、哪个升级分支做到哪）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

检查日期和提交；工具链和 pub 各落后几项；每项结论；升级了什么、门禁和构建结果；“版本写在几处”里不一致的地方；需要维护者决定的（大版本升级、要改代码的升级）。
