# Z 工程文档和维护

管“让别的组能稳定地干活”的那一层：工具链和依赖的版本、推送前的门禁、把代码和界面逐个分到任务的清点脚本、构建和装机、翻译文件、docs 本身和登记表，以及定期要做的清理和复查。它不直接产出用户看得到的功能，所以排在最后；但门禁和登记表一坏，所有组都推不了代码、看不到进度。

## 范围

- 管什么：
  - **工具链和依赖**（Z01）：`toolchain.env`（Flutter 3.47.5、Dart 3.13.4、Gradle 9.8.0、AGP 9.4.1、Kotlin 2.4.20、JDK 27、NDK 30.0.16248370、compileSdk 37.2、build-tools 37.0.0、mpv 0.41.0、FFmpeg 9.0.2、media_kit 上游提交）、根 `pubspec.yaml` 的 workspace（13 个成员）和 `dependency_overrides`（7 项，每项写了原因）、检查最新版的 `tools/check_latest/`。
  - **门禁**（Z02）：`tools/gate/gate.sh` 和它调用的三个检查脚本 `check_deps.py`（依赖方向）、`check_fixtures.py`（样本隐私）、`check_ui_structure.py`（界面结构，基线 `ui_baseline.json`），门禁自己的测试 `tools/gate/tests/`，Claude Code 钩子 `.claude/settings.json` 和 `tools/gate/hooks/format_dart.sh`。
  - **清点和归属**（Z03）：`tools/ui/inventory.py`（3.x 和 pure_live_TV 的界面文件分到任务）、它生成的 `docs/inventory/UI.md`、`UI_FILES.md`，以及计划中的全项目归属清点（代码文件、功能点、设置项、平台、原生插件）。
  - **构建和装机**（Z04）：Android 测试包和正式包怎么构建（`apps/pure_live/android/app/build.gradle.kts` 的三种构建类型）、录制用的 FFmpeg 包（`tools/ffmpeg_kit/`）、K90 装机和截图的助手（现在在仓库外的 `~/tools/pl-adb.sh`）。
  - **多语言**（Z05）：`apps/pure_live/assets/translations/zh.json`、`en.json`（各 2545 个键）、`lib/i18n/i18n.dart`、翻译相关的测试 `test/i18n_test.dart`；运行时拼出来的键；平台层给界面的中文文字。
  - **文档和登记表**（Z06）：`docs/` 的结构、`docs/tasks.toml`、生成和检查脚本 `tools/docs/docs.py`、`docs/templates/`、`docs/CHANGELOG.md` 和文档版本标签（`docs-archive-2026-10-02`、`docs-v1`）。
  - **定期维护**（Z07）：[PROCESS.md](../PROCESS.md) 第 12 节表里“每月、每次发布后、每季度”的事：清理分支和工作区、发布后更新 STATUS 和路线、复查文档和决定。
- 不管什么（归哪里）：
  - 测试本身的稳定和覆盖、K90 真机验证 → [S 质量和验证](../S-质量和验证/README.md)；本组只管门禁怎么跑测试。
  - 版本号、签名、发布页、`assets/version.json`、`assets/releases.json` → [Y 发布和运营](../Y-发布和运营/README.md)；本组的 Z04 只管“怎么构建出包”，不管“发哪个包”。
  - Windows、Linux、电视、苹果平台的构建和打包 → [X 多端客户端](../X-多端客户端/README.md)；Z04 现在只有 Android。
  - 上游对照（每周） → [W 上游借鉴](../W-上游借鉴/README.md)；Z01 只管依赖和工具链的版本。
  - 平台巡检工具 `tools/live_cli`（现在 master 上没有）→ [E07.1](../E-直播平台/E07-平台巡检/E07.1-平台巡检工具/README.md)；本组只把它在门禁和文档里的引用列为已知问题。
  - 界面规范（`docs/specs/UI.md`）和效果图工具 `tools/ui/mock/` 的使用 → A 组；Z03 只管 `tools/ui/inventory.py`。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [Z01 工具链和依赖](Z01-工具链和依赖/README.md) | `toolchain.env`、workspace、依赖覆盖、`check_latest` | 升级后必须跑 Z02 的门禁；媒体内核的分支 `third_party/media_kit` 归 G01 |
| [Z02 门禁](Z02-门禁/README.md) | `gate.sh` 和三个检查脚本、基线、钩子 | 文档检查那一步调用 Z06 的 `docs.py --check`；样本规则来自 E 组的 `fixtures/` |
| [Z03 清点和归属](Z03-清点和归属/README.md) | 界面清点脚本、全项目归属清点 | 结果写在 `docs/inventory/`；功能清点 `FEATURES.md` 是 V03.3 核对过的手写表 |
| [Z04 构建和装机](Z04-构建和装机/README.md) | Android 构建类型、FFmpeg 包、装机和截图助手 | 正式包的签名和发布在 Y01；真机验证在 S02 |
| [Z05 多语言](Z05-多语言/README.md) | 翻译文件、键名、运行时拼出来的键、平台层的中文 | 规则来自 D-005、D-016、D-024；平台层的常量在 E 组的适配器里 |
| [Z06 文档和登记表](Z06-文档和登记表/README.md) | docs 结构、`tasks.toml`、`docs.py`、模板、文档版本 | 门禁的“docs”一步；PROCESS 第 13 节的文档规范 |
| [Z07 定期维护](Z07-定期维护/README.md) | 每月、每次发布后、每季度的维护 | 每周的上游对照在 W01；发布后的 issue 回复在 V02 |

## 现状（2026-10-07）

- 做到哪：
  - 完成（10 个里 6 个）：Z01.1 工程底座（2026-09-28，`4aaeb0fda`，master 清空后第一个提交）、Z02.1 界面代码搬目录和“界面结构”检查（10-01，`4e8e9998f`）、Z02.2 门禁加“文档”检查（10-03，`c613b73f9`）、Z03.1 界面清点脚本（10-01，`2707a2869`、`62606ef5d`）、Z06.1 docs 重写为 20 组（`c613b73f9`）、Z06.2 docs v1（`9dfbb424d`，标签 `docs-v1`）。登记表里除了 Z01.1 都没写 `commit`。
  - 没开始：Z01.2（每月依赖检查）、Z03.2（全项目归属清点）、Z03.3（清点脚本改新编号）、Z04.1（装机助手进仓库）、Z05.1（清理 18 个不用的翻译键）、Z05.2（英文界面里平台层的中文）、Z07.1～Z07.3（三种定期维护）。
  - **docs v2 正在进行**（2026-10-03 的骨架 `64046b98b`、10-07 起各组的重写），还没登记任务（维护者合并后登记 Z06.3）；`docs/tasks.toml` 第 1 行和 `docs/README.md` 还写“docs v1”，`CHANGELOG.md` 没有 v2。
- 和 3.x 比：3.x 有 11 个 GitHub Actions 工作流（`.github/workflows/`，没有 push、PR 触发）、`tool/` 下 174 个脚本（多数一次性），版本散落在 `.fvmrc`、`pubspec.yaml`、工作流里，依赖方向靠约定；文档是根目录 `MAINTENANCE_POLICY.md`、`BUILD_POLICY.md`、`UPSTREAM_REVIEW_POLICY.md` 和 `docs/` 下的一次性报告。4.x 不用 Actions，只在本机构建；版本只在 `toolchain.env`；依赖方向、样本隐私、界面结构、文档都由门禁强制；文档按 20 组、一个登记表、生成的进度。
- 主要的代码：`toolchain.env`、根 `pubspec.yaml`、`tools/gate/`（4 个脚本 + 3 个测试文件 23 个用例）、`tools/docs/docs.py`（571 行）、`tools/ui/inventory.py`（241 行）、`tools/check_latest/`（`lib/check_latest.dart` 255 行，1 个测试文件）、`tools/ffmpeg_kit/`（`fetch.sh`、`fetch.ps1`、`bundles.txt`）、`tools/timeshift/`、`apps/pure_live/assets/translations/`。

## 当前重点和顺序

1. **第二档**：Z03.3（小，清点脚本输出新编号，之后 `docs/inventory/UI.md` 才能重新生成）→ Z03.2（中，三个阶段，全项目归属清点；Z03.3 的编号表可以复用）；Z07.1、Z07.2（小，各做一次，把步骤固定下来）。Z07.1 先做：本机有 25 个工作区、26 个本地分支，只有 7 个已合并，三个暂停任务的半成品工作区要确认还要不要。
2. **第三档**：Z01.2（每月 `check_latest`，2026-09-28 之后没跑过）、Z05.1（D-024 定了“这次不清理”，等 D-016 的清单）、Z04.1、Z05.2（大，英文界面）、Z07.3（第一次季度复查定在 2026-12 底）。
3. 不在登记表里但要尽快处理的（见“风险和注意”）：代码注释里 16 处被改坏的文档路径；docs v2 本身的登记（Z06.3）。

## 风险和注意

- **门禁只减不增**：`tools/gate/ui_baseline.json` 的跨功能引用（现在 17 条）和直接写的颜色图标（现在 0）只能变少（PROCESS 第 12 节）；脚本发现“基线里有、代码里没了”也报错，逼着同时改基线。
- **门禁运行时不要在同一份代码里构建正式包**（PROCESS 第 8 节第 5 条）：两边都会改 `.dart_tool/` 和生成的插件注册文件。门禁有全局锁 `${TMPDIR:-/tmp}/pure_live-gate.lock`，同一时间只跑一个，第二个最多等 1 小时。
- **代码里的文档路径检查有漏洞**：`docs.py` 按行用正则找 `docs/...`，路径在注释里换行时只匹配到行尾，16 处 `docs/README.md/`、`docs/TASKS.md/` 开头的坏路径因此没被拦住（Z06 已知问题）。
- **悬空的工具引用**（已解决，2026-10-08）：`tools/live_cli` 由 E07.1 取回并按现在的接口重写（`probe`、`patrol`）；`docs/specs/ENGINEERING.md`、`tools/gate/check_deps.py`、`fixtures/README.md` 已改成和它一致（录样本的 `fixture capture` 仍在 `v4-archive`）。
- **翻译键不要随手删**：4.0.0 清理时误删了刷新率说明的键，界面显示成键名（D-016）；D-024 定了这次不清理，以后先列运行时拼出来的键再删。
- **登记表是唯一来源**：改状态只改 `docs/tasks.toml`，再运行 `python3 tools/docs/docs.py`；生成的文件（STATUS、TASKS、MAPPING、各 README 的生成区）不手改（PROCESS 第 13 节）。
- 签名文件、密钥、`key.properties` 不进 git（D-006）；`.gitignore` 里已有这些规则，加新工具时不要输出到仓库里。

## 相关

- 规范：[specs/ENGINEERING.md](../specs/ENGINEERING.md) 第 3 节（工程底座、门禁）、第 4 节（分层）、第 7 节（代码规则）；[PROCESS.md](../PROCESS.md) 第 8 节（合并审查）、第 12 节（维护）、第 13 节（文档规范和版本）。
- 决定：D-002（master 清空重来，只借鉴工程工具）、D-005（用户看得到的文字中文）、D-007（推送前门禁必须通过）、D-014、D-025、D-028（文档的组和版本）、D-016、D-024（翻译键）。
- 其他组：S01（测试）、Y01（发布构建）、X（其他客户端的构建）、W01（上游对照）、E07.1（`tools/live_cli`）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`█████████████████░░░` 86%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [Z01 工具链和依赖](Z01-工具链和依赖/README.md) | Flutter、Dart、Gradle、JDK、mpv、FFmpeg、pub 依赖的版本和升级。 | `█████████████████░░░` 87% | 1 / 2 |
| [Z02 门禁](Z02-门禁/README.md) | 格式、依赖方向、分析、测试、界面结构、样本隐私、文档。 | `████████████████████` 100% | 3 / 3 |
| [Z03 清点和归属](Z03-清点和归属/README.md) | 代码文件、功能点、设置项、平台、原生插件、界面都归到子分类。 | `████████████████████` 100% | 3 / 3 |
| [Z04 构建和装机](Z04-构建和装机/README.md) | 测试包和正式包的构建，K90 装机和截图助手。 | `██████████████████░░` 90% | 0 / 1 |
| [Z05 多语言](Z05-多语言/README.md) | 中文和英文翻译、键名检查、运行时拼出来的键。 | `█████████████████░░░` 84% | 0 / 2 |
| [Z06 文档和登记表](Z06-文档和登记表/README.md) | docs 的结构、登记表、生成脚本、模板、文档版本。 | `████████████████████` 100% | 4 / 4 |
| [Z07 定期维护](Z07-定期维护/README.md) | 定期要做的事：清理分支和工作区、发布后更新文档、文档和决定复查。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 3 |

## 还没完成的（7）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [Z07.1](Z07-定期维护/Z07.1-每月维护/README.md) 每月：清理已合并的分支和工作区（含暂停任务确认后的旧工作区）、本机中间文件 | 未开始 | 第二档 | — |
| [Z07.2](Z07-定期维护/Z07.2-每次发布后维护/README.md) 每次发布后：更新 STATUS 的待真机、版本路线、发布说明和 README | 未开始 | 第二档 | — |
| [Z01.2](Z01-工具链和依赖/Z01.2-例行依赖升级检查/README.md) 例行依赖升级检查（每月用 check_latest 查一次，升级后跑门禁） | 开发中 | 第三档 | — |
| [Z04.1](Z04-构建和装机/Z04.1-装机和截图助手进仓库/README.md) 装机和截图助手进仓库：K90 截图、带前台检查的点按 | 待真机 | 第三档 | — |
| [Z05.1](Z05-多语言/Z05.1-翻译键/README.md) 翻译键：列出运行时拼出来的键，再清理不用的键（18 个） | 待确认 | 第三档 | 2/3：下一阶段“删除并跑全部测试” |
| [Z05.2](Z05-多语言/Z05.2-英文界面里平台给的中文/README.md) 英文界面下平台层给的文字还是中文：公告、目录说明、分区名、画质名（3.x 在平台层用翻译键；UPGRADES 20-10、25-7、25-8、26-6、29-6、30-10） | 待真机 | 第三档 | 3/3 |
| [Z07.3](Z07-定期维护/Z07.3-每季度复查/README.md) 每季度：复查文档和决定（过时的规则、被取代的决定、没人管的子分类） | 未开始 | 第三档 | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
