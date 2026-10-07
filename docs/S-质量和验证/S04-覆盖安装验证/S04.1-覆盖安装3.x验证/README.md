# S04.1 覆盖安装 3.x 验证（和 J06.1 一起做）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：4.0.0 发布说明对用户的承诺“可以直接覆盖安装 3.x，关注、历史、设置、账号都会保留”（[releases/v4.0.0.md](../../../Y-发布和运营/Y03-发布说明和README/releases/v4.0.0.md)）；功能清点 F-APP-01、F-APP-02 “没验证”，归 J06.1 和本任务（[V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)）；旧任务清单 T15d.1
- 旧编号：T15d.1
- 相关：决定 D-006（签名）、D-008（构建号 5001）、D-018（设置键不变）、D-019（不碰 K90 上的 3.x）；同一次覆盖安装的 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)（数据内容）；[S02 的 CHECKLIST](../../S02-真机验证/CHECKLIST.md) 第 4 节第 10 条、第 5 节第 9 条；任务书 [brief.md](brief.md)

## 目标

在一台装着 3.2.11 和一份覆盖各类数据的设备上，用 4.0.0 构建号 5001 的正式包覆盖安装，证明：系统接受覆盖（同包名、同证书、版本号更大）；第一次启动导入 3.x 的设置和网络电视、不崩溃、不卡在启动页；导入只跑一次；3.x 的原文件没被改动；已授予的权限和通知类别还在；装完主要功能能用。做完以后发布说明的承诺有了真机依据；J06.1 拿同一份数据核对内容。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 4.x（现在） | 要做到 |
|---|---|---|---|
| 包名 | `com.mystyle.purelive`（`android/app/build.gradle.kts:49`） | 同（`apps/pure_live/android/app/build.gradle.kts:44`） | 覆盖而不是并存 |
| 签名 | 没有正式密钥时用调试密钥（`:74-78`）；发布页的包写“debug-signed” | 同样的写法（`:63-75`），用维护者调试密钥（D-006） | `apksigner verify --print-certs` 两个包的证书 SHA-256 一样 |
| versionCode | `3.2.11+4134`：arm64 6134、x86_64 8134 | `4.0.0+5001`：arm64 7001、x86_64 9001（`aapt2 dump badging` 已核对 `~/ref/release/v4.0.0-5001/` 的两个包） | 系统不报 `VERSION_DOWNGRADE` |
| 3.x 数据位置 | `app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive`（`lib/common/global/initialized.dart:65`）；网络电视库在同一个根下的 `IPTV_CACHE/pure_live_tv/pure_live_tv.db` | 只读：`packages/live_store/lib/src/legacy/legacy_import.dart:29-31`、`apps/pure_live/lib/app/iptv_legacy.dart:16` | 覆盖前后这两个文件的 SHA-256 不变 |
| 首次启动导入 | 3.x 自己从更老版本升级时 `SettingsUpgradeMigration.migrate`（`lib/common/services/utils/settings_upgrade_migration.dart:29`），账本 `settingsUpgradeImportedSources` | `apps/pure_live/lib/app/bootstrap.dart:114-135`：`LegacyMigration.importHiveFiles`、`LegacyIptvMigration.importDatabases`，账本 `legacy.importedSources`（也认 3.x 的） | 日志里第一次 `imported: 1`，第二次 `before: 1`；没有 `failed` |
| 加密失败 | 3.x 存的是明文 | Cookie、WebDAV 密码要用 Keystore 加密；失败时其余照导，`LegacyReloginNotice` 提示一次（`apps/pure_live/lib/app/startup.dart:30-47`） | 正常设备上不出现这条提示；出现时只出现一次 |
| 回退 | — | 装回 3.2.11 时系统拒绝（版本号更小） | 记下实际现象，给发布说明用 |

## 方案

- 设备：**不用 K90**。用 Android 模拟器（x86_64，Google APIs 镜像，能 `adb root` 看数据文件），或用户提供的一台备用 Android 手机（这时用 arm64 包、看不到数据文件，只做安装和界面那几步）。
- 3.x：从 GitHub 发布页下载 `PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk`，核对 `SHA256SUMS.txt`；装好后按任务书的清单造一份数据（关注 10 个以上含 niconico、YouTube、抖音、哔哩哔哩等，历史、标签、屏蔽、改过的设置、一个假 Cookie、一个 WebDAV 配置、录制任务、网络电视播放列表、关注的分区、平台顺序），并导出一个 3.x 备份（给 S02.4 第 1 阶段用）；记下每一项，给 J06.1 对照。
- 覆盖：先用发布页上用户实际拿到的 `PureLive-4.0.0-5001-...-x86_64-release.apk`（本机副本在 `~/ref/release/v4.0.0-5001/`）；master 上代码有变化后，再用 master 的 release 构建覆盖同一个快照看一次。
- 每一步前给模拟器存快照（3.2.11 + 数据），出问题可以回到覆盖前重来。
- 结果写进本文件夹的 `verify.md`；数据内容的逐项对照由 J06.1 写进它自己的文件。

## 验证

- 自动测试：无新增；导入逻辑的测试在 `packages/live_store/test/migration_test.dart`、`apps/pure_live/test/iptv_store_test.dart`。
- 真机：本任务本身就是真机（模拟器）验证，步骤见 [brief.md](brief.md)。

## 留下的问题

- 从模拟器取出的 3.x `app_settings.hive` 能不能（脱敏后）做成 `live_store` 的测试样本，由 J06.1 决定；原文件不进仓库。
- “覆盖后不能装回 3.x、回退只能卸载”要不要写进发布说明，由维护者定（Y03）。
- 规模登记是“小”，实际要准备模拟器、造数据、两次覆盖，按任务书估约 3 小时；登记表 2026-10-07 已改“中”、三个阶段（准备、覆盖、回退和收尾）。
