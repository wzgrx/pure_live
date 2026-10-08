# J06.2 3.x 迁移报告在正式版里看得到，清掉京东、酷狗、百度的占位名：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；两个阶段的代码、测试和本记录一个提交（`[J06.2]`），两个阶段都完整
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 报告进应用日志 | 做了 | 迁移那一段从 `AppBootstrap.start` 抽成 `importLegacyData`（`bootstrap.dart`，可注入读盒子的函数和 `AppLog`），`dart:developer` 的 `log` 留着（logcat 照旧有）；`LegacyImportReport` 加 `read`、`hasProblems`、`summary()`；网络电视的摘要在 `bootstrap.dart` 里拼（`iptv_legacy.dart` 不在范围内，没动） |
| c2 摘要 | 做了 | meta `legacy.lastImport`（JSON：时间、设置盒子和网络电视各自的数字，只有个数）；`AppLog.header` 回调，`export` 先写这一行；回调在 `start` 里设（每个窗口都设，导出都带） |
| c3 新迁移清占位 | 做了 | `LegacyRules.placeholderNames` 和 `clearPlaceholders`；`legacy_snapshot.dart` 的 `_room` 先清陈旧公告再清占位 |
| c4 已迁移的清一次 | 做了 | `LegacyMigration.clearPlaceholdersOnce`（只在有命中的列表上 `replaceAll`，两次写完才写标记 `legacy.placeholdersCleared`）；`importLegacyData` 导入之后调，清了几个写一条 info；失败写 warning、不写标记、下次再试 |

验收：

| 验收 | 结果 |
|---|---|
| 1. 读了 3.x 来源那次启动：tag `legacy` 的条目；有失败或跳过时警告；平常启动不写 | 自动测试过 |
| 2. meta `legacy.lastImport`；导出文件第一行 `3.x import (<时间>): …`，以后的导出也带 | 自动测试过（`legacyImportHeader` 每次导出现读 meta） |
| 3. 新迁移清京东、酷狗、百度的占位 `nick`、`title`；京东 `userId == roomId`、`avatar == cover` 清掉；其他平台、其他字段不动 | 自动测试过（用 hive_ce 造的 3.x 盒子） |
| 4. 已迁移的数据清一次，写标记，之后不再跑；清了几个写 info | 自动测试过 |
| 5. 原有迁移测试通过；新测试改之前失败；没有新设置、新翻译键 | 是 |

日志条目的样子（测试里的合成数据）：

```
[WARN] legacy: 3.x import: sources 1, before 0, failed 0, follows 1, history 2, unreadable 1 (currentWebDavConfig), sign-ins not stored 1 (cookie/bilibili)
[INFO] legacy: 3.x stand-in names (JD Live, Kugou Live, Baidu Live) cleared from 1 rooms
```

导出文件第一行：`3.x import (2026-10-08 09:30): sources 1, follows 1, history 2, unreadable 1, sign-ins not stored 1, failed 0`（有网络电视时后面接 `; IPTV: sources …`）。

## 根因

- 报告看不到：`bootstrap.dart:119`、`:131`（改前行号）只用 `dart:developer` 的 `log`，release 没有输出，应用日志（`AppLog`）里什么都没有。
- 占位名：3.x 在不知道名字时写 `JD Live` / `Kugou Live` / `Baidu Live`（`git show v3.2.11:lib/core/site/jdlive/jd_live_api.dart` `:231-232`、`:261-262`；`kugoulive/kugou_live_api.dart:396-397`、`:505-506`；`baidulive/baidu_live_api.dart:390`），京东另外用场次号当 `userId`、用封面当头像（`jdlive/jd_live_site.dart:85`、`:88`）。迁移读房间 `legacy_snapshot.dart:266` 只清陈旧公告；`LiveRoom.mergeFrom` 只在新值为空时保留旧值，占位不是空的，就一直留着（京东的播放接口没有名字，永远带不回来）。
- 3.x 自己在合并时按“等于占位”换掉（`jd_live_api.dart:52-53` 等），所以 3.x 里看不出来。

## 占位名的表放在哪

- E05.4 第 3 阶段还没合并（`live_core` 里没有 `legacyPlaceholderNames`），表先放在 `LegacyRules.placeholderNames`；E05.4 合并时改成引用。

## 改了哪些文件

- `packages/live_store/lib/src/legacy/legacy_rules.dart`：`placeholderNames`、`clearPlaceholders`
- `packages/live_store/lib/src/legacy/legacy_snapshot.dart`：`_room` 套上 `clearPlaceholders`
- `packages/live_store/lib/src/legacy/legacy_import.dart`：`LegacyImportReport.read`、`hasProblems`、`summary()`；`LegacyMigration.placeholdersClearedKey`、`clearPlaceholdersOnce`
- `apps/pure_live/lib/app/bootstrap.dart`：`importLegacyData`、`legacyLastImportKey`、`legacyLogTag`、`legacyImportHeader`；`start` 设 `AppLog.instance.header`
- `apps/pure_live/lib/app/app_log.dart`：`header` 回调，`export` 先写它（再过一遍 `redactSecrets`）
- 测试：`packages/live_store/test/migration_test.dart`（3 个）、`apps/pure_live/test/legacy_report_test.dart`（新，4 个）

## 新设置、翻译键、门禁基线

- 没有新设置、没有新翻译键。新 meta 键：`legacy.lastImport`、`legacy.placeholdersCleared`。

## 测试

- 新增 7 个：`live_store` 3 个（导入时清占位、已迁移的清一次且只一次、报告摘要不带值），`apps/pure_live` 4 个（读了来源时的 warning 条目和摘要、导出第一行；干净的导入是 info、平常启动不写；导入失败是 warning、占位照样清一次；没有摘要时导出没有头一行）。
- 改之前：live_store 的“导入时清占位”先只加了接口不接 `_room`，确认失败（`JD Live` 原样留着）；其余几个改之前编译不过（新接口）。
- `packages/live_store` 全部 49 个、`apps/pure_live` 全部通过；`dart analyze --fatal-infos` 无问题。

## 真机上要看的

- 任务书“真机验证”四步（随 J06.1 / S04.1 在模拟器上，D-019）：覆盖安装后日志管理有 `legacy` 的“3.x import: …”（有网络电视时还有“3.x IPTV import: …”）；分享导出的第一行；关注页京东、酷狗、百度显示平台名；第二次冷启动没有新的 `legacy` 导入条目。
- 注意：迁移时应用日志还没接上设置（`main.dart` 的 `attach` 在迁移之后），条目按默认的 info 级别记下；日志页自己有按级别筛选，看 info 条目时筛选不要高于“信息”。

## 可能冲突的文件

- `bootstrap.dart`（O 组、X 组改启动）；`legacy_*`（J06.1 修迁移问题时）；E05.4 第 3 阶段（占位名的表）。
