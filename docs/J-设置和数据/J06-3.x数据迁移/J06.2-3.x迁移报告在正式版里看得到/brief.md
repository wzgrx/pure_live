# J06.2 3.x 迁移报告在正式版里看得到，清掉京东、酷狗、百度的占位名：任务书

## 背景

- 来源：2026-10-07 docs v2 核对：J、K、L、N 组（`app/bootstrap.dart:119`、`:131` 的迁移报告只写 `dart:developer` 日志，release 看不到；京东、酷狗、百度的占位值迁移时没清）和 E 组（E02 说明、E02.9 记录的清理建议）。维护者登记为本任务。
- 现象：
  1. 覆盖安装 3.x 后打开设置 → 数据与备份 → 日志管理，看不到任何和迁移有关的内容；迁移少了东西时没有线索（J06.1 的核对只能看界面和查库，见 J06.1 任务书“现状”）。
  2. 老用户（3.x 关注过京东、酷狗、百度的主播）升级后，关注卡上的名字是 `JD Live`、`Kugou Live`、`Baidu Live`；京东的头像是模糊封面。
- 为什么现在做：第二档；最好在 J06.1（第一档，覆盖安装核对）之前合并，核对时就有报告可看。规模小（两个阶段各约 1 小时）。
- 已经做过的：迁移（J02.1，`LegacyMigration`、`LegacyRules`、`IdentityMigration`）；占位值不再写（E02.9、E02.10、E02.11 的 X-2、28-2）；应用日志（I01.3）。

## 目标和验收

1. 读了 3.x 来源的那次启动：日志管理里有 tag `legacy` 的条目：导入了几个来源、之前导入过几个、失败的来源、关注和观看记录总数、读不出的值（只有键名）、没能加密保存的登录（个数和名字，不含 Cookie）、网络电视的导入结果；有失败或跳过时是警告级别。平常启动（没有新来源）不写。
2. meta 里有 `legacy.lastImport`（JSON 摘要）；日志管理“分享”导出的文件开头有一行 `3.x import (<时间>): …`，以后的启动导出也带。
3. 新迁移：京东、酷狗、百度的房间，`nick`、`title` 等于 3.x 占位值的变成空；京东另外 `userId == roomId` 的 `userId`、`avatar == cover` 的 `avatar` 变成空；其他平台、其他字段不动。关注卡显示平台名（现有规则）。
4. 已经迁移过的数据：下次启动清一次（关注和观看记录），写 meta `legacy.placeholdersCleared`，之后不再跑；清了几个写一条 info 日志。
5. 现有 `migration_test.dart` 照样通过；新测试改之前失败；门禁通过；没有新设置、没有新翻译键。

## 现状（读代码得出，写文件:行）

- 启动：`apps/pure_live/lib/app/bootstrap.dart:98-137` `AppBootstrap.start`，只在主窗口（`launch.isPrimary`，`:113`）：`legacyHiveFiles()`、`LegacyMigration.importHiveFiles`（`:118`）→ `log('3.x import: $report')`（`:119`）→ `LegacyReloginNotice.record`（`:120`）；失败 `log`（`:122`）；`LegacyIptvMigration.importDatabases`（`:125-130`）→ `log`（`:131`）、失败（`:133`）。`log` 来自 `dart:developer`。之后 `wire`；身份迁移 `IdentityMigration.run`（`:244`，后台）。
- 报告：`packages/live_store/lib/src/legacy/legacy_import.dart:92-121` `LegacyImportReport`（`toString` `:118-120` 只有数量）；网络电视 `apps/pure_live/lib/app/iptv_legacy.dart:28-55` `LegacyIptvReport`（`toString` `:52`）。
- 应用日志：`apps/pure_live/lib/app/app_log.dart`：`AppLog.instance`（`:150`）、`info`/`warning`（`:256`、`:259`）、写入前 `redactSecrets`（`:127-134`）、`attach`（`:183`，`main.dart:89`，在迁移之后；打开文件时把内存条目补写进去 `:226-228`）、`export`（`:302`）。日志页 `apps/pure_live/lib/features/backup/log_page.dart`（`_share` `:83-93` 调 `export`）。`main.dart:26` 很早就 `AppLog.instance.install()`，迁移时 `AppLog.instance` 已可用。
- 迁移的房间：`packages/live_store/lib/src/legacy/legacy_snapshot.dart:266` `_room(json) => LegacyRules.clearStaleNotice(LiveRoom.fromJson(json))`；`legacy_rules.dart:5-30`（`isStaleNotice`、`clearStaleNotice`、主题色）。存储：`store.follows.all()` / `replaceAll`、`store.history.all()` / `replaceAll`（`IdentityMigration.run` `legacy_import.dart:316-343` 的写法可以照抄）。
- 占位名的表：E05.4 第 3 阶段在 `live_core` 加 `legacyPlaceholderNames`；没合并时本任务先放在 `LegacyRules`。
- 测试：`packages/live_store/test/migration_test.dart`（用 hive_ce 造的 3.x 文件）；`apps/pure_live/test/services_test.dart`（日志、脱敏）。

## 3.x 基线

- 占位值：`git show v3.2.11:lib/core/site/jdlive/jd_live_api.dart:231-232`、`:261-262`（`JD Live`，没有头像时用封面、没有店铺账号时用场次号）；`lib/core/site/kugoulive/kugou_live_api.dart:396-397`、`:505-506`（`Kugou Live`）；`lib/core/site/baidulive/baidu_live_api.dart:390`（`Baidu Live`）。3.x 合并时按“等于占位”换掉（`jd_live_api.dart:52-53`、`kugou_live_api.dart:92-93`、`baidu_live_api.dart:89-90`）。
- 3.x 没有迁移报告（4.x 才有这一步）。
- 要保留：迁移只读不改 3.x 的文件；账本 `legacy.importedSources`；数据已经在 4.x 里的优先（`importHiveFiles` 的文档）；D-019：3.x 数据只在模拟器上造，不碰用户手机上的正式包。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UPGRADES.md` 的 X-2、28-2；`docs/DECISIONS.md` 的 D-018、D-019。
3. 本文件夹的 `README.md`；`docs/J-设置和数据/J06-3.x数据迁移/README.md`；`docs/J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/brief.md`（“现状”和核对表 V15）；`docs/E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md`（第 265 行起）。

## 范围

- 可以改：`apps/pure_live/lib/app/bootstrap.dart`（迁移那一段）；`apps/pure_live/lib/app/app_log.dart`（只让 `export` 带摘要）；`packages/live_store/lib/src/legacy/`（`legacy_rules.dart`、`legacy_snapshot.dart`、`legacy_import.dart`）；对应测试；本文件夹。
- 不能改：迁移的其他规则和账本格式；`LegacyReloginNotice`；`mergeFrom`；日志页的界面和文字；3.x 的设置键名和含义（D-018）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。不把任何 Cookie、密码写进日志或测试样本。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 迁移报告写进应用日志并留一份摘要 | c1：`bootstrap.dart` 四处 `log` 旁边写 `AppLog.instance.info/warning('legacy', …)`；`LegacyImportReport` 加 `summary()`（键名列表，不含值）。c2：`legacy.lastImport` 写 meta；`AppLog.export` 开头写摘要（摘要从哪读：`AppLog` 加一个 `header` 回调，由 `bootstrap` 或 `main` 设，避免 `AppLog` 依赖存储） | `bootstrap.dart`、`app_log.dart`、`legacy_import.dart`、测试 | 验收 1、2 |
| 2 清掉占位名（新迁移和已经迁移过的） | c3：`LegacyRules.clearPlaceholders`，`legacy_snapshot.dart:266` 套上；c4：`LegacyMigration.clearPlaceholdersOnce`，`bootstrap.dart` 导入后调 | `legacy_rules.dart`、`legacy_snapshot.dart`、`legacy_import.dart`、`bootstrap.dart`、`migration_test.dart` | 验收 3、4 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

## 测试

- 阶段 1（改之前会失败）：`apps/pure_live/test/services_test.dart`（或新文件 `legacy_report_test.dart`）：用 `LiveStore.memory` 和造的 Hive 文件跑一遍迁移的那段（把 `bootstrap.dart` 里迁移那一段抽成可测的函数，例如 `importLegacyData(store, files, log:)`），`AppLog` 里有 `legacy` 的 info 条目，内容含来源数、关注数；有 `skippedSecrets` 时是 warning 且不含 Cookie 原文；meta 有 `legacy.lastImport`；`export` 的文件第一行含 `3.x import`。没有新来源时不写条目。
- 阶段 2（改之前会失败）：`packages/live_store/test/migration_test.dart`：
  - “3.x stand-in names are cleared on import (JD Live, Kugou Live, Baidu Live)”：造三家的关注各一个（名字、标题是占位；京东 `userId == roomId`、`avatar == cover`），导入后这些字段为空；同名但别的平台（例如哔哩哔哩主播真叫 `JD Live`）不动。
  - “rooms imported before are cleared once”：先导入一份带占位的（模拟 4.0.0 的数据：直接 `follows.replaceAll`），`clearPlaceholdersOnce` 后清掉，meta 有标记；再改回占位、再跑一次，不再清。
- 测试里的定时器至少 1 秒（D-017）；样本是合成的，不含真实账号。

## 真机验证（维护者做，随 J06.1 / S04.1 在模拟器上）

| 步骤 | 期望 |
|---|---|
| 1. 模拟器上 3.2.11 造好数据（J06.1 的 D1，含京东、酷狗、百度各一个关注），覆盖安装 master 的包，第一次启动 | 设置 → 数据与备份 → 日志管理：有“3.x import: …”“3.x IPTV import: …”两条（`legacy`），数字和 J06.1 的基准一致 |
| 2. 日志管理 → 分享，导出的文件 | 第一行是 `3.x import (<时间>): …` |
| 3. 关注页 | 京东、酷狗、百度的主播名显示平台名（不是 `JD Live` 等），刷新后能取到名字的换成真名 |
| 4. 冷启动第二次 | 日志里没有新的 `legacy` 导入条目；占位清理不再跑 |

## 风险和注意

- 日志不能带出隐私：`skipped` 只写键名；`skippedSecrets` 是 `SecretRefs` 的名字（例如 `cookie.bilibili`），不是值；`AppLog` 的 `redactSecrets` 再兜一层。
- `AppLog` 不能依赖 `live_store`（它在 `app/`，可以；但别让 `live_store` 依赖应用）：摘要的读写放在 `bootstrap`，`AppLog` 只接一个回调。
- c4 对所有用户跑一次：只改命中的房间；`replaceAll` 前后数量一致；失败（存储出错）只记日志，下次再试（不写标记）。
- 京东 `avatar == cover` 的判断：4.x 自己存的数据里也可能真的相等（主播头像就是封面），清掉后界面用平台名和默认头像，之后见到卡片再补；可以接受（E02.9 记录的建议）。
- 可能冲突的文件：`bootstrap.dart`（O 组、X 组改启动）；`legacy_*`（J06.1 修迁移问题时）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/J06.2` 或本机工作区；提交信息以 `[J06.2]` 开头（英文）；不推 master。
- 提交前：改过的包（`packages/live_store`、`apps/pure_live`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`；样本隐私检查（门禁里的）通过。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；日志条目的样子（贴一条脱敏后的）；占位名的表放在哪（E05.4 合并没有）；测试数量（改之前失败几个）；改了哪些文件；要在模拟器上看的；可能冲突的文件。
