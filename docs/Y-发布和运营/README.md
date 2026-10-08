# Y 发布和运营

把做好的东西交到用户手里：版本号和构建号、正式包的签名、发布页和安装包检查、已安装的应用怎么知道有新版本（更新通道）、发布说明和项目 README、隐私和许可证。排在工程组 Z 前面、功能组后面：它不产出功能，但一次发布做错（签名不同、版本号没改、更新文件删了）会让已经装了 3.x 或 4.x 的用户升不上去，而这些用户是 4.x 的全部用户。

## 范围

- 管什么：
  - **版本、签名和发布**（Y01）：`apps/pure_live/pubspec.yaml:5` 的 `version`、`apps/pure_live/lib/features/version/app_version.dart` 的 `pubspecVersion`、`pubspecBuild`；release 签名的读取逻辑（`apps/pure_live/android/app/build.gradle.kts:9-25`、`:53-71`）和用哪把密钥（D-006）；发布前修复、构建、检查（包名、versionCode、签名证书、保留的资源、16 KB 对齐）、GitHub 发布页、`SHA256SUMS.txt`（PROCESS 第 11 节）。
  - **更新通道**（Y02）：仓库 master 上的 `assets/version.json`、`assets/releases.json`（已安装的 3.x 和 4.x 都从这里检查更新，D-015），应用内的检查和下载 `apps/pure_live/lib/features/version/`。
  - **发布说明和 README**（Y03）：`docs/Y-发布和运营/Y03-发布说明和README/releases/`（每个版本一份）、根目录 `README.md` 和它的配图 `readme/`。
  - **隐私和合规**（Y04）：不收集数据的承诺、样本脱敏（门禁 `tools/gate/check_fixtures.py`）、`LICENSE`（AGPL-3.0）、免责声明。
- 不管什么（归哪里）：
  - 怎么构建出包（构建类型、FFmpeg 包、装机）→ [Z04](../Z-工程文档和维护/Z04-构建和装机/README.md)；本组管“发哪个包、用哪把密钥签、怎么检查”。
  - 关于和版本页、更新提示的界面 → [A15.2](../A-界面设计/A15-小页面/A15.2-关于和版本/README.md)、A06.3；本组管更新通道的数据和比较规则。
  - 回复和关闭 issue → [V02](../V-需求和反馈/V02-用户反馈和issue/README.md)。
  - 发布后的真机验证 → [S02](../S-质量和验证/S02-真机验证/README.md)（S02.5 是 4.0.0 构建号 5001 那一批）；覆盖安装验证 → S04.1。
  - Windows、Linux、苹果平台的安装包和签名 → [X](../X-多端客户端/README.md)（X01.3、X02.1、X04.1）；它们的版本块写在同一个 `version.json` 里，由本组改。
  - 3.x 数据导入 → J06。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [Y01 版本签名和发布](Y01-版本签名和发布/README.md) | 版本号、构建号、签名、发布前修复、发布页、安装包检查 | 发布后改 Y02 的两个文件；构建命令在 Z04；签名决定 D-006 |
| [Y02 更新通道](Y02-更新通道/README.md) | `version.json`、`releases.json`、应用内检查更新和下载 | 3.x 和 4.x 共用同一份文件（D-015）；界面在 A15.2、A06.3 |
| [Y03 发布说明和README](Y03-发布说明和README/README.md) | 每个版本的发布说明、根目录 README、配图 | 发布页正文来自 `releases/`；发布后的更新在 Z07.2 |
| [Y04 隐私和合规](Y04-隐私和合规/README.md) | 不收集数据、样本脱敏、许可证、免责声明 | 样本检查在 Z02 门禁；Cookie 加密存储在 J、K |

## 现状（2026-10-07）

- 做到哪：
  - **4.0.0（Android）已发布**：2026-10-02 上午发布构建号 5000（Y01.2，`e3a0799cf`），当天修了 9 个发布前审查的问题（Y01.1，到 `c5bc87666`）；晚上把同一个版本号换成构建号 5001 的新包覆盖发布（Y01.3，`4b039e0c7`、`e3f644d67`，D-008），`v4.0.0` 标签移到新提交。发布页 [v4.0.0](https://github.com/wzgrx/pure_live/releases/tag/v4.0.0) 现在有 5001 的三个 APK（arm64-v8a、armeabi-v7a、x86_64）和 `SHA256SUMS.txt`；截至 2026-10-07 下载 319、15、12 次。
  - 签名：正式包没有 `key.properties`，用维护者的调试密钥签名（证书 `CN=Android Debug`，SHA-256 `1e832295…8f237ff7b9`），和 3.2.11 正式包同一张证书，所以能直接覆盖安装 3.x（D-006）；只有 APK v2 签名。
  - 更新通道：`assets/version.json` 顶层和 `platforms.android` 是 4.0.0 / 5001，`windows` 块还是 3.2.11 / 4134，`linux` 块 3.2.10；`releases.json` 有 4.0.0 一条。**装了 5000 的用户收不到 5001**：3.x 和 4.x 都只比较版本号（Y02.1）。
  - README 和发布说明：Y03.1 完成（`dd16f0b26`）；根目录 README 411 行（亮点、截图、功能、平台、安装和升级、构建、路线图、许可、免责声明），发布说明 `releases/v4.0.0.md` 136 行。
  - 隐私：README 已有“隐私”一节（`README.md:218-223`）；样本隐私由门禁检查；Y04.1（把隐私说明写完整、核对说法和代码一致）未开始。
- 和 3.x 比：3.x 用 GitHub Actions 构建和签名（`.github/workflows/publish-signed-android.yml` 等），发布 Android、Windows（EXE、MSIX、便携 ZIP）、Linux，iOS 有未签名的 IPA；4.x 只在本机构建，目前只发 Android。3.x 的应用内更新、`version.json` 的格式 4.x 原样保留。
- 主要的代码：`apps/pure_live/lib/features/version/`（8 个文件：`app_version.dart`、`update_feed.dart`、`update_prompt.dart`、`update_download.dart`、`version_page.dart`、`release_history_view.dart`、`markdown_text.dart`、`download_directory_dialog.dart`）、`assets/version.json`、`assets/releases.json`、`apps/pure_live/android/app/build.gradle.kts` 的签名部分、`tools/gate/check_fixtures.py`、`LICENSE`、根目录 `README.md`。

## 当前重点和顺序

1. **Y02.1（第二档）**：下一次发布之前定下来——一律改版本号（PROCESS 第 11 节第 1 条已经这么写），还是让 4.x 的比较带上构建号。不定的话再出一次“同版本换包”就又有人收不到。
2. **Y01.4（第三档）**：正式签名方案。现在的调试密钥能覆盖 3.x，换密钥会让所有人必须卸载重装（丢数据）；方案要先回答“要不要换、怎么换才不丢数据”。
3. **Y04.1（第三档）**：隐私说明写完整，核对 README 里的说法和代码一致。
4. 下一次发布：照 PROCESS 第 11 节，发布后照 Z07.2 的清单收尾；新版本号由维护者在发布时定（D-007）。

## 风险和注意

- **签名不能变**：同一个包名换了签名证书，Android 拒绝覆盖安装，用户只能卸载重装、丢掉全部数据（D-006）。正式包只用维护者的调试密钥签名；GitHub 上保留的 4 个签名机密对应另一张证书，只签过更早的版本，不能用于 4.x。签名文件、密钥、密码一律不进 git、不写进文档（只写放在哪、怎么用）。
- **版本号**：换安装包就必须改版本号（3.x 和 4.x 的应用内更新只比较版本号，PROCESS 第 11 节第 1 条）；D-008 是唯一的例外，以后不再这样。版本号只在发布时改（D-007）。
- **更新文件必须留在 master**：已安装的 3.x 从 `raw.githubusercontent.com/wzgrx/pure_live/master/assets/version.json`（和镜像）读更新，删了或改了格式，3.x 用户就再也收不到更新（D-015；2026-09-28 清空 master 时出过一次，`ac40984d8` 恢复）。
- **顺序**：先建发布页、上传安装包，**最后**改 `version.json`、`releases.json`（PROCESS 第 11 节第 7 条），否则用户会被提示去下载还不存在的文件。
- 门禁运行时不要在同一份代码里构建正式包（PROCESS 第 8 节第 5 条）；正式包要用和测试包同一个提交在 K90 上冒烟。

## 相关

- 规范：[PROCESS.md](../PROCESS.md) 第 11 节（发布）、第 12 节（发布后维护）；[specs/ENGINEERING.md](../specs/ENGINEERING.md) 第 3 节（安全：签名文件和密钥不进 git）、第 6 节（测试包和正式包）。
- 决定：D-006（签名）、D-007（版本号只在发布时改）、D-008（4.0.0 覆盖发布为构建号 5001）、D-015（更新文件留在 master）、D-005（用户看得到的文字中文，含发布说明）。
- 其他组：Z04（构建）、Z07.2（发布后清单）、S02.5、S04.1（发布相关的真机和覆盖安装验证）、V02（issue）、A15.2（关于和版本页）、X（其他客户端的安装包）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`████████████████░░░░` 82%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [Y01 版本签名和发布](Y01-版本签名和发布/README.md) | 版本号、构建号、签名、发布页、安装包检查。 | `█████████████████░░░` 86% | 3 / 4 |
| [Y02 更新通道](Y02-更新通道/README.md) | `assets/version.json`、`assets/releases.json`、应用内更新。 | `████████████████████` 100% | 1 / 1 |
| [Y03 发布说明和README](Y03-发布说明和README/README.md) | 发布说明、项目 README 和配图（本子分类的 `releases/`、`readme/`）。 | `████████████████████` 100% | 1 / 1 |
| [Y04 隐私和合规](Y04-隐私和合规/README.md) | 不收集数据、样本脱敏、许可证、免责声明。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 1 |

## 还没完成的（2）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [Y01.4](Y01-版本签名和发布/Y01.4-正式签名方案/README.md) 正式签名方案（现在用维护者调试密钥，和 3.x 同一证书） | 未开始 | 第三档 | — |
| [Y04.1](Y04-隐私和合规/Y04.1-隐私说明写进README/README.md) 隐私说明写进 README：不收集数据、样本脱敏规则 | 未开始 | 第三档 | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
