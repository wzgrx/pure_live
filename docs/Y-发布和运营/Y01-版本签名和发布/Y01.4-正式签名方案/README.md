# Y01.4 正式签名方案（现在用维护者调试密钥，和 3.x 同一证书）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：4.0.0 发布时（2026-10-02）确认 3.2.11 的正式包是维护者的调试密钥签的，4.x 只能继续用它才能覆盖安装（D-006）；当时记下“正式签名方案以后再定”。GitHub 上保留的 4 个签名机密要不要删，也要等这个方案。
- 旧编号：T16a.4
- 相关：决定 D-006；Y01.2、Y01.3（用调试密钥签的两次发布）；S04.1（覆盖安装验证）；X01.3、X04.1（其他平台的签名，不在本任务）

## 目标

定下 Android 正式包以后用什么密钥签、密钥怎么保管和备份、发布时怎么确认签对了；**前提是已安装 3.x 和 4.x 的用户永远能直接覆盖安装、不丢数据**。本任务只出方案和必要的工程改动（例如显式的 `key.properties`、发布检查），密钥本身的生成、备份由维护者自己做；签名文件、密钥、密码一律不进 git、不写进文档（D-006），文档只写放在哪、怎么用。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 签名逻辑 | `git show v3.2.11:android/app/build.gradle.kts:15-29`、`:61-75`：有完整的 `android/key.properties` 用它，否则用调试密钥 | 照搬：`apps/pure_live/android/app/build.gradle.kts:9-25`、`:53-71`；`-PpureLive.requireReleaseSigning=true` 时缺了就失败（`:21-25`） | 不变或小改 |
| 实际用的密钥 | 3.2.11 的正式包：维护者的调试密钥（文件名 `debug-signed`）；更早的版本用过另一把（GitHub 机密 `PURELIVE_KEYSTORE_BASE64` 等 4 个，2026-08-12 设置） | 本机没有 `key.properties`，release 构建落到调试密钥：`~/.android-purelive/debug.keystore`（环境脚本 `ANDROID_USER_HOME=~/.android-purelive`；和 Windows 主机的调试密钥是同一份）；证书 `CN=Android Debug, O=Android, C=US`，SHA-256 `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` | 方案定下来，写清放在哪 |
| 签名方案版本 | — | 只有 APK v2（`apksigner verify` 看 5001 包） | 视方案而定（轮换要 v3） |
| 发布时确认证书 | — | 手动 `apksigner verify --print-certs`（Y01 说明的“测试和验证”） | 发布检查固定下来 |
| 备份 | — | 两台机器上各一份，没有离线备份记录 | 写清备份在哪（不写内容） |

调试密钥做正式密钥的问题：证书名是“Android Debug”，有的安全软件和商店会提示；调试密钥库的口令按 Android 调试密钥的惯例并不保密，拿到文件就等于拿到签名权；Android Studio 等工具在没有这个文件时会悄悄生成一个新的调试密钥，一旦误删或覆盖，以后的包就签不对了。

## 方案（候选，维护者定）

- A（建议）**保持现在这把密钥，把它当正式密钥管理**：
  - 复制成一个名字明确的密钥库（例如 `~/.android-purelive/purelive-release.keystore`，内容和别名不变，口令可以改成只有维护者知道的），本机建 `apps/pure_live/android/key.properties` 指向它（`.gitignore` 已排除），发布时构建加 `-PpureLive.requireReleaseSigning=true`，缺了就失败，不再静默落到调试密钥。
  - 离线备份两份（维护者自己的位置，文档只写“维护者的离线备份”），写进本任务的 `record.md`：备份的日期、位置的类别、怎么恢复（不写口令）。
  - 发布检查加一步：证书 SHA-256 必须等于上面那一串（脚本或 PROCESS 第 11 节第 4 条写明命令）。
  - 优点：零风险，所有已安装的版本照样覆盖；缺点：证书名还是“Android Debug”。
- B **用 APK 签名方案 v3 的密钥轮换换成新的正式密钥**：生成新密钥，用 `apksigner rotate` 做“旧证书 → 新证书”的轮换记录，以后的包 v1/v2 仍用旧密钥签（Android 8.x 只认这两种）、v3 用新密钥加轮换记录（Android 9 起按轮换记录接受）。优点：以后证书名正常；缺点：两把密钥都要永久保管，构建要改成手动 `apksigner sign --lineage`（Flutter/Gradle 的签名配置不直接支持轮换记录），一旦出错用户就装不上；第三方商店对轮换的支持不一。
- C 直接换新密钥、不轮换：所有人必须卸载重装、丢数据。**不可接受**。
- D 改用 GitHub 机密里的那把：3.2.11 和 4.0.0 的用户装不上。**不可接受**（D-006）。
- 另：GitHub 上的 4 个机密在方案定下来之前保留（可能是那把旧密钥唯一的副本）；A 或 B 定了以后，维护者决定删不删。

## 验证

- 自动测试：不涉及（签名在构建时）。如果加了发布检查脚本，给它写一个用假 `apksigner` 输出的测试。
- 构建：方案 A 时 `flutter build apk --release --split-per-abi -PpureLive.requireReleaseSigning=true` 成功；`apksigner verify --print-certs` 证书 SHA-256 不变。
- 真机：用新流程签的测试包（正式包名）覆盖安装到一台装着 4.0.0 正式包的设备上（不能用 K90 上用户的 3.x），能直接覆盖、数据还在——和 S04.1 一起做。

## 留下的问题

- 还没开始。Windows（代码签名证书、MSIX 证书，3.x 的 `MSIX_INSTALL.md` 用过自签名证书）和苹果平台的签名不在本任务，归 X01.3、X04.1。
