# J06.1 3.x 数据迁移的真机验证

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：J02.1、L01.2 记录的“没验证”（测试包读不到 3.x 的私有目录，只用造出来的文件测过）；功能清点 F-APP-01、F-APP-02（[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 1 节）；PLAN 的风险表第一条
- 旧编号：F.4a、T09f.1
- 相关：J02.1（迁移代码）、L01.2（网络电视库迁移）、I01.3（字体）、H01.1（录制任务）；同一次做的 [S04.1](../../../S-质量和验证/S04-覆盖安装验证/README.md)（覆盖安装本身）；决定 D-006、D-018、D-019；任务书 [brief.md](brief.md)
- 涉及代码：一般不改代码；发现问题时先写失败的测试，修复在 `packages/live_store/lib/src/legacy/`、`apps/pure_live/lib/app/iptv_legacy.dart`（开 J02 的新任务或在本任务分支单独提交）

## 目标

用 3.2.11 真正写出来的数据（不是测试里用 hive_ce 造的文件），在 Android 上走一遍“覆盖安装 → 第一次启动 → 自动导入”，逐项确认 3.x 的设置、关注、历史、分组、屏蔽、账号、WebDAV、录制、网络电视、字体都在、都对，3.x 的文件一个字节没变，第二次启动不重复导入。全程**不碰用户手机上的 3.x**（D-019）。

## 3.x 和现状

| 功能点 | 3.x（`v3.2.11`） | 4.x 现在 | 要做到 |
|---|---|---|---|
| F-APP-01 首次启动导入 3.x 数据 | `lib/common/global/initialized.dart:69` 调 `SettingsUpgradeMigration.migrate`（`settings_upgrade_migration.dart:29`） | `LegacyMigration.importHiveFiles`（`packages/live_store/lib/src/legacy/legacy_import.dart:137`），`app/bootstrap.dart:114-123` 调用；单元测试 `migration_test.dart` 用造的 Hive 文件 | 设置、关注、历史、分组、屏蔽、Cookie、斗鱼续期凭据、WebDAV、录制设置和任务、本地互动都在且正确 |
| F-APP-02 导入 3.x 网络电视库 | `lib/core/iptv/local/database.dart:42`（`IPTV_CACHE/pure_live_tv/pure_live_tv.db`） | `LegacyIptvMigration.importDatabases`（`app/iptv_legacy.dart:111`），`bootstrap.dart:124-134`；单元测试 `iptv_store_test.dart:232` 用造的库 | 播放列表、频道（id 不变，关注的频道能播）、映射、节目单源、选中的节目单都在 |
| 字体 | `DOWNLOADS/fonts` 下载的字体 | `legacyFontRoots`（`app/fonts.dart:411`），`main.dart:101` | 3.x 选的字体仍显示为已安装、生效 |
| 身份迁移 | 3.x 按场次存抖音 room_id 等 | `IdentityMigration.run`（`legacy_import.dart:316`），联网后后台跑 | 抖音按场次的关注换成按主播，分组跟着走 |
| 3.x 文件 | — | 只读（`HiveBoxReader`；网络电视库复制到临时目录再开） | 前后 SHA-256 一样，没有多出 `.lock` 等文件 |

## 验证方式（原来的 X1）

原来的选择 A（3.x 里导出备份给测试包恢复）、B（把用户 3.x 的文件复制给测试包）、C（全部留到发布）要么验证不到 Hive 直读，要么要动用户的 3.x。按 D-019 和 D-003，本任务书定为两条路一起做，都不碰用户手机上的正式包：

- **路 A：模拟器上的真正覆盖安装**。WSL 里装 Android 模拟器（有 `/dev/kvm`），装 GitHub 发布页的 `PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk`（包名 `com.mystyle.purelive`，和 4.x 同一个调试密钥签名），在 3.x 里造齐数据，再用 master 构建的 x86_64 release 包 `adb install -r` 覆盖安装。这是用户实际走的路径。
- **路 B：K90 上的测试包读入 3.x 文件**。把模拟器上 3.x 写出的 `app_flutter/PURE_LIVE/` 整个目录复制进 K90 上 debug 测试包 `com.mystyle.purelive.v4dev` 的 `app_flutter/PURE_LIVE/`，冷启动后同一段迁移代码会把它当作 3.x 的数据导入。验证真机的 Keystore（Cookie 加密）和真机上的文件路径。
- 顺带 **路 C：3.x 导出的备份**（J03）：模拟器上的 3.x 导出一份完整备份，在 K90 测试包里“从文件恢复”，看预览和恢复结果（F-BAK-01）。

详细步骤、要造的数据和逐项核对表在 [brief.md](brief.md)。

## 方案

- c1 准备：模拟器、3.2.11、造数据（清单见任务书），记下基准（截图、数量、文件的 SHA-256）。
- c2 覆盖安装（路 A）和测试包读入（路 B）。
- c3 逐项核对（任务书的核对表），查库确认（`files/pure_live.db` 的表和 `meta` 的两个账本），第二次启动不重复。
- c4 问题处理：每个问题写现象、根因线索（文件:行）、一个改之前会失败的测试；修复开新任务。

## 验证

- 本任务就是验证；结果写在 `record.md`（每条核对项的结果和截图放 `verify/`）。完成条件：任务书核对表全部通过，或不通过的都开了任务、登记表写清。
- 自动测试：不新增（发现问题时新增失败的测试，见 c4）。

## 留下的问题

- 3.x 存下的京东、酷狗、百度占位值迁移时不清（J06 子分类页“已知问题”）：本任务要在核对时记录实际效果，决定是否开清理任务。
- 迁移报告只进 `dart:developer` 日志：本任务做完后决定要不要写进应用日志。
- Windows 覆盖 3.x 不在本任务（D-004 当前只做 Android），X01 开工时另登记。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点），等用户选验证方式（X1） |
| 2026-10-07 | docs v2：按 D-019 定为“模拟器覆盖安装 + K90 测试包读入”，写任务书 |
