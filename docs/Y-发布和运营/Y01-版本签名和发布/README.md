# Y01 版本签名和发布

一次发布从改版本号到发布页上线的全部步骤：版本号和构建号写在哪、正式包用哪把密钥签、发布前要检查什么、发布页放什么，以及 4.0.0 两次发布的经过。

## 范围

- 包括：
  - 版本号和构建号：`apps/pure_live/pubspec.yaml:5`（`version: 4.0.0+5001`）、`apps/pure_live/lib/features/version/app_version.dart:5`（`pubspecVersion`）、`:8`（`pubspecBuild`）；Android 的 versionCode 由 Flutter 按 ABI 算。
  - release 签名：`apps/pure_live/android/app/build.gradle.kts:9-25`（读 `android/key.properties`）、`:53-62`（签名配置）、`:66-71`（没有就用调试密钥）；用哪把密钥（D-006）、密钥放在哪、怎么备份（Y01.4）。
  - 发布前的修复和检查、发布页（GitHub Releases）、`SHA256SUMS.txt`、安装包命名。
- 不包括（归哪里）：
  - 构建类型、FFmpeg 包、装机 → Z04；发布用的构建命令写在这里，构建系统本身在 Z04。
  - 发布后改 `assets/version.json`、`assets/releases.json` 和应用内更新 → Y02（它们是 Y01 发布步骤的最后一步，但文件和规则归 Y02）。
  - 发布说明的内容 → Y03。
  - 其他客户端的安装包和签名（Windows 安装包、MSIX 证书、苹果签名）→ X01.3、X04.1。

## 现状：做到哪、怎么工作的

- 发布步骤（PROCESS 第 11 节）：改版本号和构建号（`pubspec.yaml`、`app_version.dart` 两处，测试 `apps/pure_live/test/features/version/version_page_test.dart:133` 保证一致）→ 写发布说明（Y03 `releases/`）→ `flutter build apk --release --split-per-abi`（门禁不在跑时）→ 检查（见下）→ 同一提交的测试包在 K90 冒烟 → 打标签、建发布页、上传 APK 和 `SHA256SUMS.txt` → **最后**改 `assets/version.json`、`assets/releases.json`，门禁通过后推送。
- versionCode：`build.gradle.kts:48` `versionCode = flutter.versionCode`；`--split-per-abi` 时 Flutter 给 armeabi-v7a、arm64-v8a、x86_64 分别加 1000、2000、4000，构建号 5001 → 6001、7001、9001（2026-10-07 用 `aapt2 dump badging` 看发布页的 arm64 包：`versionCode='7001' versionName='4.0.0'`、`minSdkVersion:'26'`）。
- 签名：本机没有 `android/key.properties`，release 构建用调试密钥签名并打一行警告（`build.gradle.kts:69`）。调试密钥是维护者的 `~/.android-purelive/debug.keystore`（环境脚本设 `ANDROID_USER_HOME=~/.android-purelive`，和 Windows 主机共用一份）；它也签了 3.2.11 的正式包（文件名里的 `debug-signed` 就是这个意思），所以 4.x 正式包能覆盖安装 3.x、保留数据（D-006）。发布页的 5001 包：`apksigner verify --print-certs` 得到 `CN=Android Debug, O=Android, C=US`，证书 SHA-256 `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`，只有 APK v2 签名（minSdk 26 不需要 v1）。GitHub 仓库里存着 4 个签名机密（`PURELIVE_KEYSTORE_BASE64`、`PURELIVE_KEY_ALIAS`、`PURELIVE_KEY_PASSWORD`、`PURELIVE_STORE_PASSWORD`），对应另一张证书，只签过更早的 3.x 版本，**不用于 4.x**，但先保留（可能是那张证书唯一的副本）。
- 安装包命名（沿用 3.x）：`PureLive-<版本>-<构建号>-debug-signed-android-<ABI>-release.apk`；正式包和 `SHA256SUMS.txt` 留在本机 `~/ref/release/<版本>[-<构建号>]/`，另有当时的发布页正文 `body.md`。
- 4.0.0 的经过（详见各任务）：

| 任务 | 时间（北京时间 2026-10-02） | 提交 | 内容 |
|---|---|---|---|
| Y01.1 发布前修复 | 08:16 之前 | 到 `c5bc87666` | 发布前审查发现的 9 个问题（媒体按钮图标被压缩器删掉、3.x 导入遇到加密失败、播放会话释放时引擎还在创建、本地网络权限、请求码冲突、外部意图打开任意页面、启动失败没有兜底、3.x 默认目录的录像、重叠的 stop） |
| Y01.2 发布 | 08:58～09:18 | `e3a0799cf`（版本 4.0.0+5000、`version.json`、`releases.json`）、`da69896ba`（安装包大小） | 发布页 09:16 上线，三个 5000 的 APK |
| Y01.3 覆盖发布 | 22:46～23:01 | `4b039e0c7`（构建号 5001、发布说明加“更新”一节）、`e3f644d67`（`version.json`、`releases.json` 指向 5001） | 标签 `v4.0.0` 移到 `4b039e0c7`（22:57 重新打），22:59 上传 5001 的三个 APK，替换 5000（D-008） |

- 完成度：Y01.1～Y01.3 完成；Y01.4（正式签名方案）未开始。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/pubspec.yaml:4-5` | 版本号和构建号（注释：只在发布时改） |
| `apps/pure_live/lib/features/version/app_version.dart`（61 行） | `pubspecVersion`（`:5`）、`pubspecBuild`（`:8`）、`appVersion`、`appBuild`（Flutter 编译进去的版本，没有时用前两个）、`isNewerVersion`（`:34`）、`compareVersions`（`:48`） |
| `apps/pure_live/android/app/build.gradle.kts` | 读 `key.properties`（`:9-25`，`-PpureLive.requireReleaseSigning=true` 时缺了就失败）、签名配置（`:53-62`）、release 用哪个签名和压缩（`:65-77`） |
| `apps/pure_live/android/app/src/main/res/raw/keep.xml` | release 资源压缩时保留的图标（Y01.1 第 1 条） |
| `.gitignore` | `**/key.properties`、`**/*.jks`、`**/*.keystore`、`**/*.pfx`、`**/*.key`、`**/*.csr` 不进 git |
| `~/.android-purelive/debug.keystore`（仓库外） | 正式包和测试包的签名密钥 |
| `~/ref/release/`（仓库外） | 4.0.0 两次发布的安装包、校验和、发布页正文 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/version/version_page_test.dart` | `:133` 安装的版本就是 `pubspec.yaml` 的；`:140` 按 3.x 的方式读仓库的更新文件（`version.json` 的 5001、三个 ABI） |
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 只在 Dart 里引用的图标都在 `keep.xml` 里；权限请求码不重复（Y01.1 第 1、5 条） |
| （没有） | 签名证书没有自动检查（靠发布时 `apksigner verify`） |

## 3.x 基线

- `git show v3.2.11:android/app/build.gradle.kts:15-29`、`:61-75`：同样的 `key.properties` 读取、`pureLive.requireReleaseSigning`（3.x 还认 `pureLiveRequireReleaseSigning`）、没有密钥时用调试密钥；4.x 照搬。
- 3.x 的发布在 GitHub Actions：`.github/workflows/publish-signed-android.yml`、`sign-staged-android.yml`、`local-signed-android.yml`、`build_pure_live_release.yml`（Android、Windows EXE + MSIX + 便携 ZIP）、`update_releases.yml`；4.x 不用 Actions（Z01.1）。
- 3.2.11 版本 `3.2.11+4134`，正式包同一种命名、同一把调试密钥签名。3.x 有 `android/app/google-services.json`（Firebase 云账号），4.x 去掉了。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 正式包用调试密钥签名：证书名是“Android Debug”，密钥文件在维护者两台机器上，没有书面的备份和轮换方案 | `~/.android-purelive/debug.keystore` | 密钥丢了就再也发不了能覆盖安装的更新；有些商店和安全软件对“Android Debug”证书有提示 | Y01.4 |
| 同一版本号换包时应用内收不到更新（4.0.0 构建号 5000 → 5001） | `apps/pure_live/lib/features/version/update_feed.dart:88` 只比版本号 | 装了 5000 的用户不知道有 5001 | Y02.1；D-008 写明以后换包一律改版本号 |
| `build.gradle.kts:9` 注释写“Release signing (docs/specs/ENGINEERING.md §9)”，ENGINEERING 只有 7 节（原文是旧 `docs/PLAN.md §9`） | 同左 | 按注释找不到签名说明 | Z06 已知问题；改成指向 Y01 |
| 发布检查没有脚本：包名、versionCode、证书、保留的资源、16 KB 对齐都是手动命令 | — | 容易漏一项 | 建议并入 Y01.4（发布检查脚本 `tools/release/check_apk.sh`，需要维护者决定） |
| 16 KB 页对齐没有固定检查（2026-10-07 补查发布页的 5001 arm64 包：`zipalign -c -P 16` 全部 `.so` 显示 OK；ELF 段对齐没查） | — | Android 15 起 16 KB 页的设备上原生库要对齐 | 每次发布按“测试和验证”的两条命令查 |
| `pubspec.yaml:4` 的注释还写“3.x's version until the first v4 release”，4.0.0 已经发布 | `apps/pure_live/pubspec.yaml:4` | 注释过时 | 下次发布改版本号时一起改注释 |

## 相关决定和规范

- D-006：4.x 正式包用维护者的调试密钥签名（和 3.2.11 同一证书，能覆盖安装 3.x）；签名文件和密钥不进 git；GitHub 上保留的 4 个签名密钥不用于 4.x。
- D-007：版本号只在发布时改；不强推（D-008 是例外）。
- D-008：4.0.0 覆盖发布：版本名不变、构建号改 5001，`v4.0.0` 标签移到新提交；以后换包一律改版本号。
- PROCESS 第 11 节（发布）；ENGINEERING 第 3 节（安全）、第 6 节（正式包）。

## 测试和验证

发布前在 `apps/pure_live` 里（build-tools 37.0.0 的工具）：

- 包名、版本：`aapt2 dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | head -2`，看 `package: name='com.mystyle.purelive' versionCode='7xxx' versionName='…'`、`minSdkVersion:'26'`。
- 证书：`apksigner verify --print-certs <apk>`，SHA-256 必须是 `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`（和 3.2.11 一样）。
- 保留的资源：`aapt2 dump resources <apk> | grep -E 'audio_service_(pause|play_arrow|stop)|ic_stat_playback'` 四个都在（Y01.1 第 1 条）。
- 16 KB 对齐：`zipalign -c -P 16 -v 4 <apk>`，原生库（`lib/*/*.so`）都显示 `(OK)`；ELF 段对齐：解出 `.so` 后 `llvm-readelf -lW <so> | grep LOAD`（NDK 里的 `llvm-readelf`），`Align` 列是 `0x4000` 或更大。
- 冒烟：同一提交的测试包装到 K90（Z04），按 S02 的 CHECKLIST 第 1 节走一遍。
- 发布后：用另一台没装过的设备或模拟器从发布页下载安装；覆盖安装 3.x 的验证是 S04.1。

## 路线

1. Y01.4（第三档，小）：正式签名方案——保持调试密钥并写清备份，或用 APK 签名方案 v3 的密钥轮换换到正式密钥（老设备仍按旧证书验证），或其他；只出方案，维护者定。
2. 下一次发布：照上面的步骤，版本号由维护者定；发布后照 Z07.2 的清单收尾。
3. Windows 发布（4.1，X01.3）时，本子分类加 Windows 安装包的检查（签名、MSIX 证书）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Y 发布和运营](../README.md)。

- 代码：`apps/pure_live/pubspec.yaml`、`features/version/app_version.dart`
- 进度：`█████████████████░░░` 86%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Y01.1 | 4.0.0 发布前修复 | 发布 | 完成 | 2026-10-02 | c5bc87666 | [记录](Y01.1-4.0.0发布前修复/record.md) |
| Y01.2 | 4.0.0 发布（Android） | 发布 | 完成 | 2026-10-02 | — | [设计或说明](Y01.2-4.0.0发布/README.md) |
| Y01.3 | 4.0.0 覆盖发布为构建号 5001 | 发布 | 完成 | 2026-10-02 | e3f644d67 | [设计或说明](Y01.3-4.0.0覆盖发布/README.md) |
| Y01.4 | 正式签名方案（现在用维护者调试密钥，和 3.x 同一证书） | 发布 | 未开始 | — | — | [设计或说明](Y01.4-正式签名方案/README.md) |

## 还没完成的

- **Y01.4 正式签名方案（现在用维护者调试密钥，和 3.x 同一证书）**（未开始，第三档，规模 小）

<!-- docs:生成结束 -->
