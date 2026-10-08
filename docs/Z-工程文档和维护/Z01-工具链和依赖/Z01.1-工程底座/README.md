# Z01.1 工程底座：工具链、门禁、代码规范

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：工程
- 来源：2026-09-28 用户决定在 3.x 的代码上逐块重构、master 清空重来（D-001、D-002）；重构开始前先把工程底座放进空的 master。
- 旧编号：M0、T00a.1
- 相关：决定 D-002（只借鉴归档 v4 的工程工具）、D-007（推送前门禁必须通过）；后续 Z02.1（界面结构检查）、Z02.2（文档检查）、Z01.2（每月依赖检查）；记录 [record.md](record.md)

## 目标

在清空后的 master 上先有一套能用的工程底座：工具链版本只写一处、所有包在一个 pub workspace 里共用锁文件、推送前有一条命令能检查格式、依赖方向、分析和测试，并且能随时查工具链是不是最新。之后每个模块重构都在这个底座上加成员，不再各自配置。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 做完以后（`4aaeb0fda`） | 现在 |
|---|---|---|---|
| CI 和门禁 | 11 个 GitHub Actions 工作流（`.github/workflows/`），没有 push、PR 触发；发布工作流引用了不存在的 Secret | 不用 Actions；本机 `tools/gate/gate.sh`（128 行）：依赖方向、格式、`dart analyze --fatal-infos`、测试，全局锁 | 同一个脚本，后来加了样本隐私（`check_fixtures.py`）、界面结构（Z02.1）、文档（Z02.2）、FFmpeg 包，`--all` 再跑门禁自己的测试 |
| 工具链版本 | 散在 `.fvmrc`、`pubspec.yaml`、各工作流 | `toolchain.env`（19 行）唯一来源 | 不变 |
| 结构 | 单个包，`lib/` 下按模块分目录 | 根 `pubspec.yaml` 定义 pub workspace（一开始只有 `tools/check_latest` 一个成员），共用一个 `pubspec.lock`，依赖覆盖只能写在根 | 13 个成员（2026-10-01 各模块合并时逐个加） |
| 依赖方向 | 靠约定（平台层、播放层、界面层互相引用） | `tools/gate/check_deps.py` 按分层表强制；新成员不在表里就报错 | 表里 14 项（`tools/live_cli` 2026-10-08 由 E07.1 取回） |
| 脚本 | `tool/` 下 174 个，约 2.56 万行，多数一次性 | 只保留门禁和版本检查 | 另加了 `tools/docs`、`tools/ui`、`tools/ffmpeg_kit`、`tools/timeshift`、`tools/brotli` |
| 版本检查 | 无（靠 dependabot） | `tools/check_latest`：对照官方渠道查工具链、media_kit 上游和 pub 依赖 | 不变；之后没再跑过（Z01.2） |
| Claude Code 钩子 | 无 | `.claude/settings.json`：改完 Dart 文件自动 `dart format`（`tools/gate/hooks/format_dart.sh`），结束时跑 `gate.sh --hook` | 不变 |
| 签名文件 | 部分进过仓库的工作流配置 | `.gitignore` 排除 `key.properties`、`*.jks`、`*.keystore`、`*.pfx`、`*.key`、`*.csr` | 不变 |

## 结果

- 提交：`4aaeb0fda`（2026-09-28，“build: engineering base for the v3 refactor (M0)”），20 个文件、2149 行：`.claude/settings.json`、`.gitattributes`、`.gitignore`、`AGENTS.md`、`CLAUDE.md`、`LICENSE`（AGPL-3.0，661 行）、当时的 `docs/PLAN.md` 和模块记录、根 `pubspec.yaml`/`pubspec.lock`、`toolchain.env`、`tools/check_latest/`（4 个文件）、`tools/gate/`（`gate.sh`、`check_deps.py`、`hooks/format_dart.sh`、`tests/test_check_deps.py`）。
- 从归档 v4（分支 `archive/v4`、标签 `v4-archive`）沿用的只有工程工具，不涉及界面（D-002）；对照表在 [record.md](record.md)“从归档 v4 沿用的部分”。
- 当天核对的版本（全部最新稳定版）：Flutter 3.47.5（Dart 3.13.4）、Gradle 9.8.0、AGP 9.4.1、Kotlin 2.4.20、JDK 27、NDK 30.0.16248370、compileSdk 37.2、build-tools 37.0.0、mpv 0.41.0、FFmpeg 9.0.2、media_kit 上游 `803c4a2`；`check_latest` 16 项、落后 0、失败 0。
- 偏差：清空 master 时把已安装的 3.x 检查更新要读的 `assets/version.json`、`assets/releases.json` 也删了，3.x 的更新检查返回 404；`ac40984d8` 原样恢复，AGENTS.md 写明不能删（后来成了 D-015）。
- 测试：`tools/check_latest/test/check_latest_test.dart` 5 个、`tools/gate/tests/test_check_deps.py` 5 个。

## 验证

- 自动测试：上面两组测试；门禁 `bash tools/gate/gate.sh --all` 通过（当时只有 `tools/check_latest` 一个成员）。
- 真机：不适用（工程任务，没有用户看得到的变化）。完成的证据是门禁和 `check_latest` 的输出（PROCESS 第 2 节“工程”）。

## 留下的问题

- `check_deps.py` 的允许表从归档 v4 带来了 `tools/live_cli`（`:34`、`:41`），这个工具没有取回 master → E07.1 取回，或不取回时删掉这两处。
- 当时 `check_deps.py` 的注释写的是“docs/PLAN.md 第 4 节的分层”，现在指向 `docs/specs/ENGINEERING.md` 第 4 节（`c613b73f9` 改的），已一致。
- 每月的依赖检查没有固定下来 → Z01.2。
