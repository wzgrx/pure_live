# S04 覆盖安装验证

用装着 3.x 数据的设备覆盖安装 4.x 正式包，证明“直接覆盖安装 3.x、数据保留”这个 4.0.0 的承诺在真实安装上成立：签名和版本号让系统接受覆盖、首次启动导入只跑一次、3.x 的原文件不被改动、装完能正常用。

## 范围

- 包括：
  - 安装这一层：同包名 `com.mystyle.purelive`、同签名证书（D-006）、versionCode 比 3.2.11 大（D-008 的构建号 5001）、`adb install -r` 或系统安装器能覆盖、3.x 已授予的权限和通知类别保留。
  - 首次启动这一层：`AppBootstrap` 里的 3.x 导入（设置盒子和网络电视库）跑一次、记进账本、第二次启动跳过；没有崩溃、没有卡在启动页；需要重新登录时的提示只出一次。
  - 3.x 的原文件（`app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive`、网络电视库）只读不改。
  - 覆盖以后能不能回退（装回 3.2.11）以及回退的后果。
  - 验证用的设备：Android 模拟器或另一台不是用户日常用的 Android 设备（K90 上的 3.x 不能动，D-019）。
- 不包括（归哪里）：
  - 导入后数据**内容**逐项对照（设置值、关注、历史、分组、屏蔽、Cookie、WebDAV、录制任务、网络电视的频道和节目单）归 [J06.1](../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)；两者是同一次覆盖安装，S04.1 只看安装和启动，J06.1 拿同一份数据核对内容。
  - 迁移代码本身（`packages/live_store/lib/src/legacy/`、`apps/pure_live/lib/app/iptv_legacy.dart`）的修改归 J06（J02.1、L01.2 写的）。
  - 签名方案、发布页、更新通道归 Y01、Y02；Windows 覆盖 3.x 的安装目录归 X01（D-004：现在只做 Android）。
  - 测试包 `.v4dev` 的日常验证归 S02（测试包和正式包包名不同，覆盖安装只能用正式包验证）。

## 现状：做到哪、怎么工作的

- **没开始**：S04.1 未开始（第一档）。3.x 数据导入至今只用造的 Hive 文件测过（`packages/live_store/test/migration_test.dart`、`packages/live_store/test/support.dart` 的 `v3Room()`），没有在一台装着 3.x 的设备上真的覆盖过。4.0.0 已经按“覆盖安装 3.x”发给用户（发布说明第一段），这是第一档的原因。
- **为什么 K90 不行**：K90 上的 3.x 是用户每天用的（D-019 不碰）；Android 上同一个包名的代码是所有系统用户共用的，在 K90 上开第二个用户装 3.x 再覆盖，也会把用户主空间里的 3.x 一起升级。所以只能用模拟器或另一台设备。
- **覆盖安装时发生什么**（读代码得出）：
  1. 系统比包名（`com.mystyle.purelive`，`apps/pure_live/android/app/build.gradle.kts:44`）、签名证书（维护者调试密钥，和 3.2.11 同一个，D-006）、versionCode（Flutter 按 ABI 拆包：`ABI 序号 × 1000 + 构建号`，4.0.0+5001 的 arm64 是 7001、x86_64 是 9001；3.2.11+4134 的 arm64 是 6134、x86_64 是 8134）。证书不同报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，版本号小报 `INSTALL_FAILED_VERSION_DOWNGRADE`。
  2. 数据目录 `/data/data/com.mystyle.purelive/` 保留。3.x 的设置盒子在 `app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive`（`packages/live_store/lib/src/legacy/legacy_import.dart:29-31` 的 `LegacyLocations.android`），4.x 的数据库在 `files/pure_live.db`（`apps/pure_live/lib/app/data_root.dart` 的 `resolveDataRoot` 取应用支持目录，`packages/live_store/lib/src/live_store.dart:165` 的 `fileName`）。
  3. 第一次启动（`apps/pure_live/lib/app/bootstrap.dart:114-137`，只在主窗口）：`legacyHiveFiles()`（`app/data_root.dart:51`）找到 3.x 的盒子 → `LegacyMigration.importHiveFiles`（`legacy_import.dart` 的 `LegacyMigration`）：按 `路径|大小|修改时间` 记账（`legacy.importedSources`，也认 3.x 自己的 `settingsUpgradeImportedSources`），只读字节（`HiveBoxReader`），已有的数据优先，读不了的下次再试；Keystore 加密失败的 Cookie 和 WebDAV 密码跳过并由 `LegacyReloginNotice`（`app/startup.dart:30`）在启动 1 秒后提示一次“部分平台需要重新登录……”；再 `LegacyIptvMigration.importDatabases`（`app/iptv_legacy.dart:104`）把 3.x 的网络电视库复制到临时目录后读。两次导入的结果都写日志（`log('3.x import: $report', name: 'AppBootstrap')`）。
  4. 录制设置里 3.x 的值（导入时 4.x 还没有对应设置的）由 `LegacyMigration.adoptLegacyValues` 在录制服务启动时接管（`app/recording.dart:254`）。
- **和 3.x 比**：3.x 自己从更老的版本升级时也有一套导入（`v3.2.11:lib/common/global/initialized.dart:69` 调 `SettingsUpgradeMigration.migrate`，`lib/common/services/utils/settings_upgrade_migration.dart:29`），账本格式就是 4.x 认的那个；3.x 没有“覆盖安装验证”的流程。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/build.gradle.kts:42-50` | 正式包包名、`minSdk 26`、`targetSdk 37`、版本号取 `pubspec.yaml`（`4.0.0+5001`） |
| `apps/pure_live/android/app/build.gradle.kts:9-24`、`:63-75` | 签名：有 `android/key.properties` 用它，没有就用调试密钥（`~/.android-purelive/debug.keystore`，`ANDROID_USER_HOME` 指过去）并打警告 |
| `apps/pure_live/lib/app/bootstrap.dart:114-137` | 启动时的两次 3.x 导入（设置盒子、网络电视库），只在主窗口 |
| `apps/pure_live/lib/app/data_root.dart:21-27`、`:51-58` | 4.x 的数据目录；Android 上 3.x 盒子的位置 |
| `packages/live_store/lib/src/legacy/legacy_import.dart` | `LegacyLocations`（各平台 3.x 盒子的位置）、`LegacyImportReport`、`LegacyMigration`（导入、账本、合并、`adoptLegacyValues`） |
| `packages/live_store/lib/src/legacy/hive_reader.dart` | 只读解析 Hive 文件的字节 |
| `packages/live_store/lib/src/legacy/legacy_snapshot.dart`、`legacy_rules.dart` | 3.x 的键到 4.x 设置、关注、历史、分组、屏蔽、Cookie 的转换规则（`audioOnly`、`taobaoCookie` 丢掉 `:419`） |
| `apps/pure_live/lib/app/iptv_legacy.dart` | 3.x 网络电视库的位置（`:16` `legacyIptvDatabases`）、复制后读（`:152-164`）、账本、本地播放列表文件的复制（`:414`） |
| `apps/pure_live/lib/app/startup.dart:30-47` | `LegacyReloginNotice`：加密失败时提示重新登录，只提示一次 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_store/test/migration_test.dart` | 造的 3.x Hive 文件：各类型的值和“后写的赢”（`:46`）、文件尾损坏（`:76`）、关注、历史、分组、屏蔽、账号、设置一起导入（`:149`）、Keystore 加密失败时其余照导、登录只跳过一次（`:206`）、第二次不重复导入且已有数据优先（`:228`）、Windows 的搬家账本（`:242`）、按场次的关注换成主播（`:261`）、清晰度编号换算（`:295`） |
| `apps/pure_live/test/iptv_store_test.dart` | 造的 3.x 网络电视库导入（`LegacyIptvMigration`）：播放列表、频道、本地文件复制、账本 |

## 3.x 基线

- 3.x 的包：GitHub 发布页 `wzgrx/pure_live` 的 `v3.2.11`（2026-09-27），四个 Android 包 `PureLive-3.2.11-4134-debug-signed-android-{arm64-v8a,armeabi-v7a,x86_64}-release.apk`，带 `SHA256SUMS.txt`；包名 `com.mystyle.purelive`（`v3.2.11:android/app/build.gradle.kts:49`）、`minSdk 26`（`:53`），同样“没有正式密钥就用调试密钥”（`:74-78`）。
- 3.x 的数据位置：`v3.2.11:lib/common/global/initialized.dart:65` 的 `AppPathManager().getDir(AppPathManager.dirHiveDB)`；它自己的升级导入见上。
- 用户的习惯：从 3.x 的“检查更新”或发布页下载新版直接装，不卸载；所以覆盖安装是 4.x 唯一的升级路径。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 从没在装着 3.x 数据的设备上覆盖过 | — | “直接覆盖安装”的承诺没有真机依据 | S04.1（第一档） |
| 导入只用造的 Hive 文件测过，没有真实 3.x 文件的样本 | `packages/live_store/test/migration_test.dart` | 真实数据的边角情况测不到 | S04.1 准备阶段从模拟器取出 3.x 的 `app_settings.hive`，脱敏后交给 J06.1 决定要不要做成样本（不直接进仓库） |
| 覆盖后不能直接装回 3.2.11（versionCode 更小，系统拒绝），要回退只能卸载，数据会丢 | Android 安装规则 | 用户想回到 3.x 时会丢数据 | S04.1 记下实际现象；发布说明要不要写“回退前先在 4.x 里备份”由维护者定（Y03） |
| K90 不能用于覆盖安装验证 | D-019；Android 多用户共用代码 | 要另找设备 | 用 Android 模拟器（x86_64 包）或用户提供的备用机 |
| 正式包的 R8 和资源压缩只在 release 有 | `build.gradle.kts:63-75` | 测试包看不到的问题（例如被删掉的通知图标）只在覆盖安装时第一次看到 | S04.1 用 release 包，顺带看后台播放通知和录制通知 |

## 相关决定和规范

- D-006：4.x 正式包用维护者调试密钥签名，和 3.2.11 同一个证书，能覆盖安装。
- D-008：4.0.0 覆盖发布为构建号 5001（已装 4.0.0 构建号 5000 的收不到应用内提示）。
- D-018：3.x 的设置键名和含义不变（导入的前提）。
- D-019：不碰 K90 上的 3.x 和正式包。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md) 第 6 节（测试包和正式包）；[PROCESS.md](../../PROCESS.md) 第 11 节（发布：版本号、签名检查）。

## 测试和验证

- 自动：`cd packages/live_store && dart test test/migration_test.dart`；`cd apps/pure_live && flutter test test/iptv_store_test.dart`。
- 真机：本子分类就是真机（模拟器）验证，步骤在 [S04.1 的任务书](S04.1-覆盖安装3.x验证/brief.md)；S02 的 [CHECKLIST.md](../S02-真机验证/CHECKLIST.md) 第 5 节第 9 条、第 4 节第 10 条（旧关注换成主播身份）归这里。

## 路线

1. **S04.1**（第一档）：模拟器装 3.2.11、造一份覆盖各类数据的 3.x 使用痕迹、覆盖安装 4.0.0 构建号 5001 的正式包，看安装和首次启动；和 J06.1 同一次做。
2. 以后每次发正式包前（PROCESS 第 11 节），用同一个模拟器快照（3.2.11 + 数据）覆盖一次新包，作为发布检查的一步（发布前冒烟）；需要时登记 S04.n。
3. Windows 覆盖 3.x 的安装目录（`D:\Soft\PureLive` 这类）等 Windows 客户端开工（X01）时再加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [S 质量和验证](../README.md)。

- 代码：—
- 进度：`██████░░░░░░░░░░░░░░` 30%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| S04.1 | 覆盖安装 3.x 验证（和 J06.1 一起做） | 验证 | 开发中 | — | — | [设计或说明](S04.1-覆盖安装3.x验证/README.md)、[任务书](S04.1-覆盖安装3.x验证/brief.md)、[记录](S04.1-覆盖安装3.x验证/record.md) |

## 还没完成的

- **S04.1 覆盖安装 3.x 验证（和 J06.1 一起做）**（开发中，第一档，规模 中）
  - 阶段：✓ 准备 → 覆盖 → 回退和收尾
  - 接着做：从 3.x 应用内“更新”下载安装 4.0.0 的那条路

<!-- docs:生成结束 -->
