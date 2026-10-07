# Z01.2 例行依赖升级检查

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：[PROCESS.md](../../../PROCESS.md) 第 12 节“每月：依赖和工具链检查（`check_latest`）”；ENGINEERING 第 2 节第 4 条“工具链和依赖用最新稳定版”。
- 旧编号：T00a.2
- 相关：Z01.1（建了 `check_latest`）；Z02（升级后跑门禁）；Z07.1（每月维护，同一天做）；G01（`third_party/media_kit` 跟上游）

## 目标

每月固定看一次工具链和 pub 依赖有没有新的稳定版，有落后的逐项决定升不升、在独立分支上升级并验证；结果有记录，下个月接着看。这个任务是“第一次做一遍并把步骤写清楚”，以后每月照着做，每次的结果追加到 `record.md`。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 怎么发现新版本 | `.github/dependabot.yml` 每月对 pub 和 Gradle 各开最多 5 个 PR（`git show v3.2.11:.github/dependabot.yml:3-20`），没人合的就一直挂着 | `tools/check_latest`（`lib/check_latest.dart:159` 的 `collect`）：10 项工具链、media_kit 上游提交，加 workspace 里 46 个 pub.dev 直接依赖；需要 `GITHUB_TOKEN` | 每月跑一次，输出存档 |
| 上一次检查 | — | 2026-09-28（Z01.1 记录：16 项、落后 0）；之后成员从 1 个加到 13 个，直接依赖从 5 个变成 46 个，没再跑过 | 每月一次 |
| 版本写在几处 | `.fvmrc`、`pubspec.yaml`、各工作流 | `toolchain.env`；另外 Gradle 在 `apps/pure_live/android/gradle/wrapper/gradle-wrapper.properties`（`gradle-9.8.0-all.zip`），AGP 在 `apps/pure_live/android/settings.gradle.kts:23`（`9.4.1`），compileSdk/targetSdk 在 `build.gradle.kts`（`compileSdk = 37`），本机路径在 `~/tools/purelive-env.sh` | 列成清单，升级时一起改 |
| 升级后的验证 | CI 构建 | 门禁 `gate.sh --all`；release 构建；K90 冒烟 | 写进步骤 |

## 方案

- c1 跑检查：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart --report-only > <scratchpad>/check_latest-<日期>.md`，结果表贴进 `record.md`。
- c2 核对“版本写在几处”：`toolchain.env` 和 `gradle-wrapper.properties`、`settings.gradle.kts`、`build.gradle.kts`、`~/tools/purelive-env.sh` 是否一致，不一致的记下来（不在本任务改）。
- c3 逐项判断：落后的每一项写“升 / 不升（原因）/ 等（等什么）”。原则：补丁版和次版本直接升；大版本、Flutter、AGP、Kotlin、NDK 单独开分支并看更新说明；被 `dependency_overrides` 压住的（`xml`、`wakelock_plus`、`test_api`、`code_assets`、`nm`、`dbus`）看覆盖的原因还在不在。
- c4 升级（如果有）：分支 `ai/Z01.2-<日期>`；改 `toolchain.env`（工具链）或成员的 `pubspec.yaml` + 根 `flutter pub upgrade`（pub）；门禁 `--all`；`flutter build apk --release --split-per-abi`；K90 装同一提交的测试包冒烟。
- c5 把 c1～c4 的步骤写进 [Z01 子分类说明](../README.md) 的“路线”或本 README 的“每月步骤”，以后照做。

## 验证

- 自动测试：门禁 `bash tools/gate/gate.sh --all` 通过（日志有 `gate: passed`）。
- 构建：release 构建成功（有升级时）。
- 真机：有工具链或播放相关的升级时，K90 冒烟（[S02 真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 1 节“看直播”的前几条：启动、首页、进直播间播放、弹幕、退出）；没有升级时不需要。

## 留下的问题

- 还没开始。`check_latest` 不查 `gradle-wrapper.properties`、`settings.gradle.kts` 和 `toolchain.env` 是否一致，第一次做时人工核对（c2），以后是否加进脚本由维护者决定。
