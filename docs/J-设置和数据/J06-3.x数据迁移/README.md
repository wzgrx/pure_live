# J06 3.x 数据迁移

覆盖安装 3.x 后自动导入关注、历史、设置、账号。

用户把 4.x 覆盖安装在 3.x 上（同一个包名、同一个签名，D-006），第一次启动时 4.x **只读**地找到 3.x 留下的 Hive 文件和网络电视库，把设置、关注、历史、分组、屏蔽、Cookie、WebDAV、录制任务、本地互动、网络电视列表、下载的字体接过来；3.x 的文件原样留着。代码在 J02 的 `legacy/` 和应用的启动流程里；这个子分类管“迁得对不对”，以及真机核对（J06.1）。

## 范围

- 包括：
  - 找文件：`apps/pure_live/lib/app/data_root.dart` 的 `legacyHiveFiles`（`:51`）、`packages/live_store/lib/src/legacy/legacy_import.dart` 的 `LegacyLocations`（`:23`，Android 一个位置，Windows 最多 32 个根目录）、`app/iptv_legacy.dart` 的 `legacyIptvDatabases`（`:16`）、`app/fonts.dart` 的 `legacyFontRoots`（`:411`）。
  - 读和转：`legacy/hive_reader.dart`（直接解析 Hive 文件的字节）、`legacy/legacy_snapshot.dart`（`fromHive`：原始键值 → v4 类型并修复）、`legacy/legacy_rules.dart`（平台列表版本、首选平台、人数口径、菜单、主题色、画质 id、陈旧公告、要换身份的房间）。
  - 合并和记账：`LegacyMigration.importHiveFiles` / `merge`（`legacy_import.dart:137`、`:218`）、`adoptLegacyValues`（`:192`，录制和本地互动后来变成注册设置时接走）、`IdentityMigration.run`（`:316`，按主播关注）；网络电视 `LegacyIptvMigration.importDatabases`（`app/iptv_legacy.dart:111`）。
  - 启动时的顺序和失败处理：`app/bootstrap.dart:114-135`、`:242`；Keystore 失败时一次性的“请重新登录”提示 `LegacyReloginNotice`（`app/startup.dart:30`、`:86`）。
  - 覆盖安装后的真机核对（J06.1）。
- 不包括（归哪里）：
  - 覆盖安装能不能装上（签名、versionCode、包名）、装上后应用能不能起来 → [S04.1](../../S-质量和验证/S04-覆盖安装验证/README.md)（和 J06.1 同一次做）、Y01。
  - 3.x 备份文件的读取（`LegacySnapshot.fromBackup`）→ J03（同一个类，另一条路）；设备同步收到的 3.x 数据 → J05。
  - 存储本身、密钥库 → J02；网络电视的表和转换细节 → L01（L01.2）；各设置之后怎么生效 → J01 和各功能组。

## 现状：做到哪、怎么工作的

- 用户看得到的：覆盖安装后第一次打开，关注、历史、分组、设置、账号、WebDAV、网络电视列表、录制任务都在，不用做任何事；如果这台手机的 Keystore 加密失败，账号没迁过来，启动 1 秒后提示一次“请重新登录”（`legacy_import_relogin`）；3.x 关注里按场次存的抖音、niconico、YouTube 房间，联网后自动换成按主播（`IdentityMigration`，在第一次关注刷新之前）。
- 内部怎么工作：

```text
AppBootstrap.start（bootstrap.dart:98，只在主窗口）
 1 legacyHiveFiles（data_root.dart:51）
     Android：getApplicationDocumentsDirectory()/PURE_LIVE/HIVE_DB/app_settings.hive
             （覆盖安装时是 /data/user/0/com.mystyle.purelive/app_flutter/…，3.x 自己的目录；4.x 的库在 files/pure_live.db，互不覆盖）
     Windows：LegacyLocations.windows（exe 旁 AppData、应用支持目录、文档目录、同级的 pure_live 安装、卸载项里的安装目录、
             previous_install_locations.txt 账本，最多 32 个根）
 2 LegacyMigration.importHiveFiles（legacy_import.dart:137）
     每个文件：指纹 路径|大小|修改时间；在账本 meta[legacy.importedSources]（或 3.x 自己的 settingsUpgradeImportedSources）里就跳过
     HiveBoxReader.read（只读字节，不打开、不建 .lock、不压缩）→ LegacySnapshot.fromHive（legacy_snapshot.dart:20）
       设置：Settings.all 里每个键，decode → normalize；坏值记 skipped
       修复：平台列表按 siteCatalogMigration 补新平台（版本 1～38）、首选平台不在列表里改第一个、realOnlinePlatforms 按
             audienceMetricMigration 补平台、danmakuInteractionMigration < 1 打开点按和长按、enableHighRefreshRate → refreshRateMode、
             3.x 默认蓝 → 品牌蓝、savedMenuIds 只留认识的（:181-204、:374-412）
       集合：favoriteRooms / historyRooms（2.1 的 {"list": [...]}、2.0 的字符串列表都认；无效房间丢掉；按 v4 身份去重；清陈旧公告）、
             favoriteAreas、user_custom_tags_v5 + room_to_tags_mapping_v1（旧的只有房间号的键给关注和历史里同号的房间）、
             shieldList、blockedDanmakuUsers（去空白、不分大小写去重）、webDavConfigs、currentWebDavConfig（:206-264）
       密钥：<平台>Cookie（淘宝丢掉）、douyuLtp0、douyuDid（:355-372）
       其他：recorder_tasks（换算画质 id）、localInteraction.* 等原样进 otherValues（:422-446）
     LegacyMigration.merge（:218）：设置、Cookie、WebDAV 只在库里没有时写；集合按身份合并、库里的在前、空字段互补；
       先写不需要加密的，最后一次写入全部 Cookie 和新服务器的密码；Keystore 失败时只跳过这一次写，返回跳过的名字
     → LegacyReloginNotice.record（startup.dart:35）
 3 LegacyIptvMigration.importDatabases（iptv_legacy.dart:111）：<同一个根>/IPTV_CACHE/pure_live_tv/pure_live_tv.db，复制到临时目录再打开读，
     账本 meta[legacy.iptvImportedSources]；列表、频道（id 原样）、映射、节目单源和没过期的节目；本地列表文件复制到应用的 iptv 目录
 4 wire → 后台 _moveFollows（bootstrap.dart:242）= IdentityMigration.run（联网解析，失败的下次再试）
 另：main.dart:101 用 legacyFontRoots(<根>/DOWNLOADS/fonts) 认出 3.x 下载过的字体；录制（app/recording.dart:254、:568）和本地互动
     （local_interaction_scope.dart:24）启动时 adoptLegacyValues / 读 legacyValue('recorder_tasks')
```

- 完成度：代码 J02.1（`d2fbe3072`）、L01.2（`27385a999`）、I01.1、I01.3（字体）、H01.1（录制）都已合并，单元测试用 hive_ce 按 3.x 的写法造文件（`packages/live_store/test/migration_test.dart` 8 个、`apps/pure_live/test/iptv_store_test.dart` 2 个）。**从没用真实的 3.x 数据跑过**：测试包 `.v4dev` 读不到 3.x 的私有目录，规则又不许动用户的 3.x（D-019）；4.0.0 已经发给用户覆盖安装 3.x，这是本组最大的风险（PLAN 的风险表第一条）。功能点 F-APP-01、F-APP-02“没验证”→ J06.1、S04.1。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_store/lib/src/legacy/hive_reader.dart`（145 行） | `HiveBoxReader.read`：帧（长度、键、值、CRC32），后写的覆盖先写的，删除帧生效，遇到坏帧停在那里；只有 Hive 内置类型（3.x 没注册适配器） |
| `packages/live_store/lib/src/legacy/legacy_snapshot.dart`（452 行） | `LegacySnapshot.fromHive`（`:20`）、`fromBackup`（`:47`，J03）；`_readSettings`（`:181`）、`_readCollections`（`:206`）、`_rekeyRoomTags`（`:272`）、`_objectList`（`:318`，三种列表格式）、`_readSecrets`（`:355`）、`_applyHiveCounters`（`:383`）、`_consumed`（`:414`，被消化掉的 3.x 键）、`_keepOtherValues`（`:422`）、`_recorderTasks`（`:431`） |
| `packages/live_store/lib/src/legacy/legacy_rules.dart`（160 行） | `isStaleNotice`（`:11`）、`themeColor`（`:19`）、`clearStaleNotice`（`:28`）、`qualityId`（`:35`）、`needsIdentityMigration`（`:52`：抖音 room_id、niconico 节目号、YouTube 视频号）、`catalogAdditions`（`:62`）、`currentCatalogVersion = 38`（`:102`）、`homePlatforms`（`:108`）、`preferredPlatform`（`:130`）、`realOnlinePlatforms`（`:139`）、`menuIds`（`:151`） |
| `packages/live_store/lib/src/legacy/legacy_import.dart`（345 行） | `LegacyLocations`（`:23`；`android` `:29`、`windows` `:40`）、`LegacyImportReport`（`:92`：`importedSources`、`alreadyImported`、`failedSources`、`follows`、`history`、`skipped`、`skippedSecrets`）、`LegacyMigration`（`:130`：账本键 `legacy.importedSources` `:131`、`importHiveFiles` `:137`、`adoptLegacyValues` `:192`、`merge` `:218`、`_join` `:282`）、`IdentityMigration.run`（`:316`） |
| `apps/pure_live/lib/app/data_root.dart` | `legacyHiveFiles`（`:51`）、`windowsInstallLocations`（`:73`） |
| `apps/pure_live/lib/app/iptv_legacy.dart` | `legacyIptvDatabases`（`:16`）、`LegacyIptvReport`（`:28`）、`LegacyIptvMigration`（`:104`：账本 `legacy.iptvImportedSources` `:106`、`importDatabases` `:111`、`read` `:155` 复制到临时目录再开） |
| `apps/pure_live/lib/app/bootstrap.dart` | 迁移的顺序和兜底（`:114-135`，每一步失败只记日志不影响启动）、`_moveFollows`（`:242`） |
| `apps/pure_live/lib/app/startup.dart` | `LegacyReloginNotice`（`:30`：`record` `:35`、`showOnce` `:41`；启动 1 秒后显示 `:86`） |
| `apps/pure_live/lib/app/fonts.dart` | `legacyFontRoots`（`:411`） |
| `apps/pure_live/lib/app/platforms.dart` | `identityResolver`（`:261` 起的说明）：抖音 `getRoomDetailForRefresh`、niconico、YouTube 的解析 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_store/test/migration_test.dart`（8） | `HiveBoxReader` 读各种类型、后写覆盖、删除（`:46`）；坏尾保留前面的帧（`:76`）；导入关注、历史、分组、屏蔽、账号、设置并修复（`:149`）；Keystore 加密失败时其余照导、账号跳过一次（`:206`）；第二次不重复、库里已有的优先（`:228`）；Windows 位置跟着账本（`:242`）；身份迁移（`:261`）；画质 id（`:295`） |
| `apps/pure_live/test/iptv_store_test.dart`（2） | 按 3.x schema 9 造的 `pure_live_tv.db` 只读导入一次、频道 id 不变、3.x 目录的文件和字节不变（`:232`） |

## 3.x 基线

- 3.x 自己也有迁移：`git show v3.2.11:lib/common/global/initialized.dart:69`（启动时调 `SettingsUpgradeMigration.migrate`）、`lib/common/services/utils/settings_upgrade_migration.dart`（275 行：每次启动把旧文件复制出来用 Hive 打开、按来源指纹账本 `settingsUpgradeImportedSources` 跳过）；数据根 `lib/common/global/app_path_manager.dart:20-25`（`PURE_LIVE`、`HIVE_DB`、`IPTV_CACHE`）、`:54`（Android 用应用文档目录）。
- 3.x 的网络电视库：`lib/core/iptv/local/database.dart:42`（`IPTV_CACHE/pure_live_tv/pure_live_tv.db`，drift schema 9）。
- 必须保留：3.x 的文件只读不改（用户可能回退到 3.x）；3.x 的账本也认（3.x 导过的来源不再导）；键名和含义（D-018）；房间身份按 v4 规则（UPGRADES 统一原则“房间身份”、11-8）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 从没用真实的 3.x 数据跑过迁移（Android 覆盖安装、真机 Keystore） | 整个子分类 | 真实的 Hive 文件里可能有测试没造出来的写法（例如 3.x 早期版本的格式、超大列表、损坏的帧），迁移出错就是用户丢数据 | [J06.1](J06.1-3.x数据迁移的真机验证/README.md)（第一档）、S04.1 |
| 3.x 存下的京东、酷狗、百度占位值（`JD Live`、`Kugou Live`、`Baidu Live`，`userId` 等于房间号、`avatar` 等于封面，酷狗的标题是公聊公告）迁移时没清 | `legacy_rules.dart` 只有 `isStaleNotice` 一条清理 | 老用户的关注卡上显示占位名，直到一次刷新带回真名（刷新带不回的就一直显示）；E02.9、E02.10、E02.11 的 README 都记了 | J06.1 用含这三个平台的 3.x 数据看实际效果，再决定要不要在 `LegacyRules` 加清理（开 J02 的小任务） |
| 迁移按指纹记账：改了转换规则，已经导入过的用户不会重跑 | `legacy_import.dart:139-168` | 以后修迁移的 bug 只对还没升级的用户有效 | 需要时另写一次性的修复（像 `_upgradeThemeColor` 那样带标记），写进那个任务的任务书 |
| 迁移的报告只写进 `dart:developer` 的日志（`bootstrap.dart:119`、`:131`），不进应用日志，release 构建里看不到 | `bootstrap.dart:119` | 用户反馈“关注没了”时没有现成的诊断；真机核对只能查库 | 建议：把两份报告的数字（不含路径和内容）写进 `AppLog`；小改动，J06.1 做完后决定 |
| 身份迁移要联网，第一次启动没网时不做，等下次 | `legacy_import.dart:316-344` | 期间这些关注刷新不到（按场次的房间号已失效） | 照设计 |
| 3.x 留在 `app_flutter/PURE_LIVE/` 下的文件一直留着（Hive、网络电视库、字体） | — | 占空间（通常几 MB，字体可能几十 MB） | 照设计（用户可能回退）；以后可以在“缓存与数据”里给清理入口，先进 V01 |

## 相关决定和规范

- D-006（签名和 3.x 相同，覆盖安装的前提）、D-018（键名不变）、D-019（真机不碰用户的 3.x 和它的数据）、D-001。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“房间身份”“按主播关注”“画质命名”，11-8、17-1、23-1（J02.1 README 有逐条）。
- [PLAN.md](../../PLAN.md) 的风险表：“3.x 数据迁移出错，用户丢关注和设置”。

## 测试和验证

- 自动测试：`cd packages/live_store && dart test test/migration_test.dart`；`cd apps/pure_live && flutter test test/iptv_store_test.dart`。
- 真机：按 J06.1 的任务书和 [verify 步骤](J06.1-3.x数据迁移的真机验证/brief.md)（模拟器上装 3.2.11 造数据后覆盖安装，以及把模拟器上的 3.x 文件放进 K90 测试包的目录）；[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 9 条。

## 路线

1. **J06.1**（第一档，和 S04.1 一起）：照任务书在模拟器上覆盖安装、在 K90 测试包里读入 3.x 文件，逐项核对；发现的问题写失败的测试，修复开到 J02。
2. 根据 J06.1 的结果决定：占位值清理规则、迁移报告进应用日志。
3. Windows 覆盖 3.x（`D:\Soft\` 下的用户安装不能碰，要另找一份 3.2.11 的便携版在别的目录）→ X01 开工时登记。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [J 设置和数据](../README.md)。

- 代码：`packages/live_store/lib/src/legacy/`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| J06.1 | 3.x 数据迁移的真机验证（覆盖安装时用真实数据核对） | 验证 | 未开始 | — | — | [设计或说明](J06.1-3.x数据迁移的真机验证/README.md) |

## 还没完成的

- **J06.1 3.x 数据迁移的真机验证（覆盖安装时用真实数据核对）**（未开始，第一档，规模 中）
  - 阶段：准备装着 3.x 和真实数据的手机 → 覆盖安装 4.x → 逐项核对关注、历史、设置、账号

<!-- docs:生成结束 -->
