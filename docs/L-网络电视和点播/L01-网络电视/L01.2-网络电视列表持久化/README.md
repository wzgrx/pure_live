# L01.2 网络电视列表持久化

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：`IptvLibrary` 的持久化和 3.x 网络电视库的迁移）
- 来源：模块重构计划 M12.1。L01.1 只给了内存版 `MemoryIptvLibrary`，说持久化由 J02.1 做；J02.1 又记回 L01.1；I01.1 只好先用内存版，**导入的列表重启后就没了**（I01.1 记录“有意差异”）
- 旧编号：M12.1、T11a.2
- 相关：L01.1（接口）、J02.1（`LiveStore` 的库）、I01.1（启动流程）；之后的 L01.3（页面订阅表变更）、J03（备份里的网络电视列表）、J06.1（真机核对迁移）；记录 [record.md](record.md)

## 目标

网络电视的列表、频道、映射、节目单源、节目单频道、节目存进 `pure_live.db`，重启还在；覆盖安装 3.x 时把 3.x 的 `pure_live_tv.db` 只读导入一次，频道 id 原样保留，这样 3.x 的关注、历史里的网络电视频道继续能播。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| 存在哪 | 单独的 drift 库 `IPTV_CACHE/pure_live_tv/pure_live_tv.db`（`lib/core/iptv/local/database.dart:42`，schema 9） | `pure_live.db` 里的 6 张 `iptv_` 表（`apps/pure_live/lib/app/iptv_library.dart:14-34`），同一个连接（`LiveStore.database`） | 完成 |
| 实现放哪 | — | 应用里（`StoreIptvLibrary`，`:64`）：`live_store` 只能依赖 `live_core`，拿不到 `IptvPlaylist`；应用是唯一同时依赖两者的 | 完成 |
| 频道顺序 | 没有 `ORDER BY`（`database.dart:229`） | `position` 列记文件顺序 | 完成 |
| 3.x 库 | — | `LegacyIptvMigration`（`app/iptv_legacy.dart:104`）：复制到临时目录再开，后台 isolate 读，账本 `legacy.iptvImportedSources` | 完成；真机没验证 |

## 结果

- 提交：`27385a999`（2026-10-01 合并）。改了 `apps/pure_live/lib/app/iptv_library.dart`（新）、`iptv_legacy.dart`（新）、`bootstrap.dart`；`apps/pure_live/pubspec.yaml` 加直接依赖 `drift`、`sqlite3`（版本和根 lock 一致）。没有改其他包。
- 做了什么（详见 [record.md](record.md)）：
  - c1 表：`iptv_playlists`、`iptv_channels`（主键是频道 id，`position` 记顺序，请求头存 JSON）、`iptv_epg_mappings`（带 `origin`、`locked`）、`iptv_epg_sources`、`iptv_epg_channels`、`iptv_epg_programmes`（按 `channel_key` 和开始时间建索引）；第一次用到时建表，版本记在 `meta` 的 `iptv.schemaVersion`（现在 1）。
  - c2 行为照 `MemoryIptvLibrary`：每次写一个事务；带 `expected` 的写入逐列比对，变了就抛 `StaleIptvSnapshot` 什么都不写；删列表连频道和映射，删节目单源连它的频道、节目和指向它的映射；大批量用 drift 的 `batch`；写后发表变更通知（`IptvTables`）。
  - c3 3.x 迁移：位置由 J02.1 找到的 Hive 文件推出来（同一个根下的 `IPTV_CACHE/…`）；只读（3.x 目录的文件和字节不变，测试里比对过）；导入列表（类型不是 m3u/m3u8/txt 的跳过）、频道（id 原样）、映射（含手动和锁定）、节目单源、节目单频道、两天内没结束的节目；本地导入的列表文件复制一份到应用的 `iptv` 目录；库里已有的优先（同 id 或同名的跳过）；不导 3.x 的死表和 Xtream 的账号密码。
  - c4 启动流程：打开 `LiveStore` → 建 `StoreIptvLibrary` →（主窗口）J02.1 设置导入 → 网络电视导入 → `wire`（`bootstrap.dart:111-136`）。
- 测试：2 个（`apps/pure_live/test/iptv_store_test.dart`：写入后重开读回；3.x 样例库导入一次）；当时应用 25 个测试全部通过。

## 验证

- 自动测试：`cd apps/pure_live && flutter test test/iptv_store_test.dart`。
- 真机：重启后列表还在——S02.6 第 2 阶段导入后重启时顺带看；3.x 库的迁移用真实数据核对 → [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)（record 写明“本次按规则不读真实 3.x 数据”）。

## 留下的问题

- 网络电视页随数据刷新（用 `IptvTables` 的变更通知）→ L01.3 做完（`iptv_data.dart:19`）。
- 备份带不带网络电视列表 → E06.1 做了（`shared/backup/backup_iptv.dart`，完整备份带列表、频道、映射、节目单源，不带节目）。
- 表结构以后要改时按 `iptv.schemaVersion` 升级，现在没有升级代码（版本 1）。
- 3.x 库迁移的真机核对 → J06.1。
