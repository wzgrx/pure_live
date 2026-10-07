# Y01.4 正式签名方案：任务书

## 背景

- 来源：4.0.0 发布（2026-10-02）时查明 3.2.11 正式包用的是维护者的调试密钥，4.x 只能用同一把才能覆盖安装（D-006）；“正式签名方案”留到以后（登记时的旧编号 T16a.4）。
- 现象：正式包的证书是 `CN=Android Debug`；本机没有 `android/key.properties`，release 构建靠“没有正式密钥就落到调试密钥”的兜底（`apps/pure_live/android/app/build.gradle.kts:66-71`，只打一行警告）；密钥文件在维护者两台机器上，没有离线备份的记录；GitHub 仓库里还存着 4 个对应另一把旧密钥的签名机密。
- 为什么现在做：第三档；现在能正常发布，但密钥丢了或被覆盖，就再也发不了能覆盖安装的更新（所有用户要卸载重装、丢数据）。在 4.1（Windows）之前定下来比较好。
- 已经做过的：Y01.2、Y01.3 用调试密钥发布；Y01 子分类说明写了发布时确认证书的命令。

## 目标和验收

1. `README.md` 的方案 A～D 有结论（维护者定；规模小，可按 D-003 用建议 A），写进 `record.md` 和 DECISIONS（维护者加一条新决定，补充 D-006）。
2. 方案 A 时：
   - 维护者本机有 `apps/pure_live/android/key.properties`（不进 git），指向一个名字明确的密钥库，证书和现在一样（SHA-256 `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`）；
   - 发布构建命令加 `-PpureLive.requireReleaseSigning=true`，缺了正式密钥就失败；
   - 有一个发布检查（脚本 `tools/release/check_apk.sh` 或 PROCESS 第 11 节第 4 条写明的命令），证书不对就失败；
   - `record.md` 写了备份：日期、位置的类别（例如“维护者的离线加密存储两份”）、恢复步骤；**不写口令、不写密钥内容、不写具体路径以外的秘密**。
3. 方案 B 时：轮换记录生成、构建和签名流程写成脚本，在测试设备上验证 Android 8.x 和 9 以上都能从 4.0.0 覆盖安装（需要模拟器）。
4. `build.gradle.kts:9` 的注释改成指向本子分类（现在写的 `docs/specs/ENGINEERING.md §9` 不存在）。
5. 门禁通过；用新流程构建的正式包覆盖安装验证通过（和 S04.1 一起）。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/android/app/build.gradle.kts`：`:9-10` 注释；`:11-16` 读 `rootProject.file("key.properties")`；`:17-20` `hasReleaseSigning`（`keyAlias`、`keyPassword`、`storePassword` 都有、`storeFile` 是文件）；`:21-25` `pureLive.requireReleaseSigning`；`:53-62` 有正式密钥时建 `release` 签名配置；`:66-71` release 用它，没有就用 `debug` 并 `logger.warn`。
- `.gitignore`：`**/key.properties`、`**/*.jks`、`**/*.keystore`、`**/*.pfx`、`**/*.key`、`**/*.csr`。
- 调试密钥：`~/tools/purelive-env.sh` 设 `ANDROID_USER_HOME="$HOME/.android-purelive"`（注释：和 Windows 主机共用的调试密钥，调试版和预览版能互相覆盖），密钥库 `~/.android-purelive/debug.keystore`。
- 发布页的 5001 包（`~/ref/release/v4.0.0-5001/`）：`apksigner verify --print-certs` → `CN=Android Debug, O=Android, C=US`，SHA-256 如上；只有 v2 签名。
- GitHub 机密（`gh secret list --repo wzgrx/pure_live` 只看名字）：`PURELIVE_KEYSTORE_BASE64`、`PURELIVE_KEY_ALIAS`、`PURELIVE_KEY_PASSWORD`、`PURELIVE_STORE_PASSWORD`，2026-08-12 设置；对应的证书不是上面这张，只签过更早的 3.x 版本。

## 3.x 基线

- `git show v3.2.11:android/app/build.gradle.kts:15-29`、`:61-75`：同样的读取和兜底；3.x 还认 `pureLiveRequireReleaseSigning`。
- 3.x 的签名工作流 `git show v3.2.11:.github/workflows/publish-signed-android.yml`、`sign-staged-android.yml`：从机密解出密钥库签名（4.x 不用 Actions）。
- 必须保留：**和 3.2.11 正式包同一张证书**（或在它的轮换记录里），否则 3.x 用户无法覆盖安装。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 7 节“不给的东西：签名文件、密钥”、第 11 节发布、第 14 节规则）、`docs/DECISIONS.md` 的 D-006、D-008。
2. 本文件夹的 `README.md`；`docs/Y-发布和运营/Y01-版本签名和发布/README.md`（发布步骤和检查命令）；`apps/pure_live/android/app/build.gradle.kts`。
3. Android 文档：APK 签名方案 v3 和密钥轮换（`apksigner rotate`、`--lineage`）。

## 范围

- 可以改：`apps/pure_live/android/app/build.gradle.kts`（只改注释，或在方案需要时改签名配置）；新建 `tools/release/`（发布检查脚本和测试）；本文件夹的文档。
- 不能改：版本号、`assets/version.json`、`assets/releases.json`；`.gitignore` 里关于签名文件的规则（只能加，不能删）；任何功能代码。
- 绝对不能：把密钥库、`key.properties`、口令、密钥内容提交到 git、写进文档、写进日志、发给其他执行者（PROCESS 第 7 节）；删除或覆盖 `~/.android-purelive/debug.keystore`；删除 GitHub 机密（维护者决定）；用 GitHub 机密那把密钥签 4.x。
- 其他 AI 执行时：只能做“方案文档 + 检查脚本 + 注释”，密钥相关的操作全部列成步骤交给维护者。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 方案定稿（A～D 的结论，维护者确认） | `README.md`、`record.md` | 验收 1；维护者加 DECISIONS |
| 2 | 方案 A：维护者在本机建密钥库副本和 `key.properties`、做离线备份；执行者写发布检查脚本、改注释 | （本机，不进 git）；`tools/release/check_apk.sh`、`tools/gate/tests/test_check_apk.py`、`build.gradle.kts:9` | 验收 2、4；`-PpureLive.requireReleaseSigning=true` 构建成功，检查脚本通过 |
| 3 | 覆盖安装验证 | `record.md`（结果） | 验收 5（和 S04.1 一起） |

方案 B 时第 2 阶段换成轮换记录和签名脚本，并加模拟器验证。

## 测试

- 发布检查脚本的测试（`tools/gate/tests/test_check_apk.py`，假的 `aapt2`、`apksigner` 输出）：包名不对、versionCode 不对、证书 SHA-256 不对、缺 `audio_service_*` 图标时分别失败；全对时通过。
- 不在测试里放真实的 APK 或证书文件。

## 真机验证（维护者做）

| 步骤 | 期望 |
|---|---|
| 1. 用新流程（`-PpureLive.requireReleaseSigning=true`）构建正式包，`apksigner verify --print-certs` | 证书 SHA-256 和 3.2.11、4.0.0 相同 |
| 2. 在一台装着 4.0.0（构建号 5001）正式包、有关注和设置的设备（不是用户日常用的 K90 上的 3.x）上 `adb install -r` 新包 | 直接覆盖，关注、设置都在 |
| 3. 在一台装着 3.2.11 的设备或模拟器上覆盖安装（S04.1） | 直接覆盖，首次启动导入 3.x 数据 |
| 4. 故意让 `key.properties` 指向不存在的文件再构建 | 构建失败，提示正式密钥不完整 |

## 风险和注意

- 最大的风险是签错：任何一个用错密钥的正式包发出去，装了它的用户以后就只能卸载重装。发布检查必须在上传前跑。
- 改口令不改密钥：复制密钥库并改库口令、条目口令不会改变证书；改之后立刻 `apksigner verify` 核对证书 SHA-256。
- 方案 B 不可逆：一旦发布了带轮换记录的包，以后都要用新密钥和轮换记录。
- K90 上的正式包 `com.mystyle.purelive` 是用户每天用的 3.x，不能拿来做覆盖安装验证（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（`apksigner`、`aapt2`、`zipalign` 在 `~/Android/Sdk/build-tools/37.0.0/`）。
- 分支 `ai/Y01.4` 或本机工作区；提交信息以 `[Y01.4]` 开头（英文）；不推 master。
- 提交前：`git status` 确认没有任何签名文件、`key.properties` 被加进来；`python3 -m unittest discover -s tools/gate/tests`；`bash tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。密钥相关的步骤做到一半时，写清哪些已经在本机完成（不写内容）。

## 报告（中文，简洁）

方案结论和理由；维护者要做的步骤（本机密钥库、备份、`key.properties`）；发布检查脚本和测试；覆盖安装验证结果；GitHub 机密的建议；需要维护者决定的。
