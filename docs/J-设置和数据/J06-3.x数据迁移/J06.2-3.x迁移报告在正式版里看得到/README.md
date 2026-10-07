# J06.2 3.x 迁移报告在正式版里看得到，清掉京东、酷狗、百度的占位名

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：2026-10-07 docs v2 核对：J、K、L、N 组（迁移报告只写 `dart:developer` 日志，`app/bootstrap.dart:119`、`:131`，正式版看不到；占位值不清）；E 组（[E02 说明](../../../E-直播平台/E02-其他国内平台/README.md)“已知问题”：3.x 存下的 `JD Live`、`Kugou Live`、`Baidu Live` 迁移时没清；[E02.9 记录](../../../E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md)第 265 行起的数据清理建议）
- 相关：迁移本身 [J02.1](../../J02-存储和加密/J02.1-存储和迁移/README.md)；真机核对 [J06.1](../J06.1-3.x数据迁移的真机验证/README.md)（本任务最好先合并，J06.1 核对时就能在日志页看到报告）、[S04.1](../../../S-质量和验证/S04-覆盖安装验证/S04.1-覆盖安装3.x验证/README.md)；占位名的表由 [E05.4](../../../E-直播平台/E05-平台框架和模型/E05.4-平台层小问题合集/README.md) 第 3 阶段给出；应用日志 [I01.3](../../../I-浏览和发现/I01-首页外壳和全局/I01.3-应用服务补全/README.md)（`AppLog`、日志管理页）；UPGRADES X-2（占位值规则）、28-2；决定 D-018、D-019（3.x 数据只在模拟器上造）
- 任务书：[brief.md](brief.md)

## 目标

1. **迁移报告看得到**：覆盖安装 3.x 后第一次启动，迁移导入了几个来源、多少关注和观看记录、哪些值没读出来、哪些登录没能加密保存、网络电视导入了什么——这些现在只写进 `dart:developer` 的日志，正式版（release）里谁也看不到；J06.1 核对、用户反馈“迁移后少了东西”时都没有依据。做完以后：报告写进应用日志（设置 → 数据与备份 → 日志管理能看到、导出），并留一份摘要，以后导出日志时带在开头。
2. **占位名清掉**：3.x 不知道名字时给京东、酷狗、百度的房间写了 `JD Live`、`Kugou Live`、`Baidu Live`（还有京东用场次号当 `userId`、用封面当头像），4.x 适配器不再写占位，但迁移过来的这些值一直留着：关注卡上主播名是 `JD Live`，直到哪次刷新带回真名（京东的播放接口根本没有名字，可能永远带不回来）。做完以后：新的迁移不再带进这些占位值；已经迁移过的（4.0.0 用户）在下次启动时清一次；清掉后界面显示平台名（E02.9 的 28-2），之后看到真名再补上。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 迁移报告 | 3.x 自己的“设置升级”只写调试日志 | `apps/pure_live/lib/app/bootstrap.dart:114-135`：`LegacyMigration.importHiveFiles` 的报告 `log('3.x import: $report', name: 'AppBootstrap')`（`:119`），网络电视的 `log('3.x IPTV import: $report')`（`:131`），失败也只 `log`（`:122`、`:133`）；`log` 是 `dart:developer`，release 里没有输出。报告类 `LegacyImportReport`（`packages/live_store/lib/src/legacy/legacy_import.dart:92-121`：来源数、已导入、失败的来源、关注数、观看记录数、读不出的值 `skipped`、没能加密的登录 `skippedSecrets`）；网络电视的报告 `apps/pure_live/lib/app/iptv_legacy.dart:27-55` | 同样的内容写进 `AppLog`（成功 info、有失败或跳过时 warning，tag `legacy`）；摘要存进 meta，日志导出时写在开头 |
| 应用日志 | — | `apps/pure_live/lib/app/app_log.dart:144` `AppLog`：内存 2000 条，开着“写日志文件”时写文件；`attach`（`:183`）在 `main.dart:89`，**在迁移之后**；`attach` 打开文件时把内存里已有的条目先写进去（`:226-228`），所以迁移时写的条目不会丢。日志页 `apps/pure_live/lib/features/backup/log_page.dart`（看、分享 `_share` `:83-93`、清空） | 迁移的条目在内存里就能被日志页看到；导出时开头带摘要 |
| 占位值 | `lib/core/site/jdlive/jd_live_api.dart:231-232`、`:261-262`；`lib/core/site/kugoulive/kugou_live_api.dart:396-397`、`:505-506`；`lib/core/site/baidulive/baidu_live_api.dart:390`；合并时按“等于占位”换掉（`jd_live_api.dart:52-53` 等） | 迁移读房间 `legacy_snapshot.dart:266` 只清陈旧公告（`LegacyRules.clearStaleNotice`，`legacy_rules.dart:28`）；`mergeFrom` 只在新值为空时保留旧值（`packages/live_core/lib/src/live_room.dart:587-640`），占位值不为空，一直留着 | 迁移时清；已迁移的清一次 |

## 方案

- c1 报告进应用日志：`bootstrap.dart` 的四处 `log` 改成同时 `AppLog.instance.info('legacy', …)`（失败、`skipped`、`skippedSecrets`、`failedSources` 不为空时 `warning`）；内容是报告的 `toString()` 再加 `skipped` 的值名（只有键名，不含值；`AppLog` 写入前会 `redactSecrets`），`skippedSecrets` 只写个数和 `SecretRefs` 名字（不含 Cookie）。只在真的读了来源（`importedSources > 0` 或有失败）时写，平常启动不刷屏。
- c2 摘要：读了来源时把摘要（时间、来源数、关注、观看记录、跳过数、没加密的登录数、网络电视的数字）存进 meta `legacy.lastImport`（JSON）；`AppLog.export`（日志页的“分享”）在文件开头写一行 `3.x import (<时间>): …`。不加新的界面文字。
- c3 新迁移不带占位：`LegacyRules` 加 `clearPlaceholders(LiveRoom room)`：平台在 `legacyPlaceholderNames`（E05.4 给的表；E05.4 还没合并时先在 `LegacyRules` 里放这张表，E05.4 再改成引用）里、`nick` 或 `title` 等于占位 → 空；京东另外：`userId == roomId` → 空，`avatar == cover` → 空（3.x 用封面顶替头像）。`legacy_snapshot.dart:266` 的 `_room` 先后套 `clearStaleNotice`、`clearPlaceholders`。
- c4 已迁移的清一次：`LegacyMigration` 加 `clearPlaceholdersOnce(LiveStore store)`：meta `legacy.placeholdersCleared` 没有时，对关注和观看记录各 `replaceAll` 一次（只改命中的房间），写上标记；`bootstrap.dart` 在导入之后调（只在主窗口），写一条 info 日志（清了几个）。
- 不改：迁移的其他规则、账本格式（`legacy.importedSources`）；`LegacyReloginNotice`；`mergeFrom`；界面（显示平台名的规则已有）。

## 验证

- 自动测试：`packages/live_store/test/migration_test.dart`（占位值在新迁移里被清、只清命中的平台、京东的 `userId` 和头像规则、已迁移的清一次且只一次）；`apps/pure_live/test/` 里 bootstrap 或 `services_test.dart`（迁移报告进了 `AppLog`、`legacy.lastImport` 写了、导出文件开头有摘要）。
- 真机：随 J06.1 在模拟器覆盖安装时看日志页（任务书“真机验证”）；做之前“未开始”。

## 留下的问题

- 封面分不清是不是 3.x 的模糊图（京东），不动（E02.9 记录的建议）。
- 迁移报告没有专门的界面（不加新文字）；以后要做“迁移结果”页时进 V01 提议。
