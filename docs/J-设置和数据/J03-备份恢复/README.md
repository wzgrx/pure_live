# J03 备份恢复

备份和恢复。

备份文件长什么样（3.x 的分区布局，`backupVersion: 4`）、怎么导出和恢复、恢复前怎么比较出“会改什么”、文件放在哪里、叫什么，以及把关注和弹幕设置发给电视。备份页长什么样归 A12.4。

## 范围

- 包括：
  - `packages/live_store/lib/src/backup/backup_service.dart`：`exportAll`、`exportFollows`、`restoreAll`、`restoreFollows`、`writeFile`、`readFile`，同一时间一个恢复；解析在 `legacy/legacy_snapshot.dart` 的 `LegacySnapshot.fromBackup`（和 3.x 备份共用一套规则）。
  - 应用一侧加的分区和逻辑 `apps/pure_live/lib/shared/backup/`：`backup_data.dart`（搜索记录 `search`、多画面上次的画面 `multiview`、恢复预览 `previewRestore`）、`backup_iptv.dart`（网络电视列表 `iptvLibrary`）、`backup_files.dart`（文件名、默认目录、列出目录里的备份）、`backup_preview_dialog.dart`（预览 → 确认 → 恢复 → 提示的流程 `restoreWithPreview`，备份页和 WebDAV 页共用）。
  - 备份页里的逻辑部分 `features/backup/backup_page.dart`（创建、从目录恢复、选文件恢复、改目录、删除）和 `features/backup/tv_sync.dart`（同步到电视的文档和发送）。
- 不包括（归哪里）：
  - 备份页、预览对话框、同步电视扫码页的样子 → [A12.4](../../A-界面设计/A12-账号和数据界面/A12.4-备份与恢复/README.md)；日志页（`features/backup/log_page.dart`，放在这个目录里但属于日志）→ A12、I01.3。
  - 把备份传到 WebDAV → J04；在局域网两台设备之间传 → J05（都用这里的格式）。
  - 选文件、选目录的系统选择器（`platform/plugins.dart:51` 的 `pickBackupPath`）→ O03；`Download/PureLive` 的存储权限 → O04。

## 现状：做到哪、怎么工作的

- 用户看得到的（设置 → 数据 → 备份与恢复）：“创建备份”直接写进备份目录（Android 默认 `Download/PureLive`），文件名照 3.x `purelive_<时间>.txt`，重名加 `_2`；“仅导出关注”写 `purelive_favorites_<时间>.txt`；目录里的备份按新到旧列出，点一个先看预览（每部分“现在 → 恢复后”，新增几个、移除几个；文件里没有的部分写“保持不变”；读不了的条目数；文件来源是 3.x 第几版还是 v4、仅关注），确认后才写入；选了仅关注的文件做“恢复全部”时自动只恢复关注；不是备份文件、读不了、另一个恢复正在进行分开提示。手机上“同步 TV 数据”扫电视上的二维码（电脑上输入地址），把关注、历史、弹幕设置、网络电视 UA 发过去。
- 内部怎么工作：

```text
创建：exportBackup(service, store, scope)（backup_data.dart:40）
   = BackupService.exportAll()（3.x 分区：app、theme、roomCard、font、player、danmaku、volume、favorite、history、
     webdav、iptv、cookie〔只在 includeSensitiveData 时〕、proxy、windowSize、exit、startup、refresh、page、tags；backupVersion 4）
   + search{history}（搜索记录）+ iptvLibrary（网络电视列表，内置热门除外）+ multiview{session}（有才写）
   → BackupService.writeFile（先写 .part，旧文件改名 .previous，就位后删；上次中断留下的 .previous 先恢复）
恢复：readFile → previewRestore（backup_data.dart:248，用 LegacySnapshot.fromBackup 解析，格式错在这里就报）
   → 用户确认 → restoreBackup（:59）= BackupService.restoreAll（:91，_exclusive：同时只一个，否则 StateError）
     + 有 search 就替换搜索记录、有 iptvLibrary 就替换网络电视列表、有 multiview 就写上次的画面（3.x 的文件没有这些：保持不变）
同步到电视：tvSyncDocument（tv_sync.dart:31）= danmaku + favorite + history 三个分区摊平 + customIptvUserAgent
   → sendToTv（:49）POST <电视>/api/setSettings，正文 {"settings": …}（3.x 放在查询串里，太长会超限）
```

- 完成度：J03.1（2026-10-01，`1b730f77e`）做了本地备份、恢复预览、搜索记录进备份、同步电视；A12.4（`965d41956`）按确认的设计重做了页面；E06.1（`f8acb92b6`，2026-10-02）让完整备份带上网络电视列表和多画面上次的画面。备份格式 3.x 能读回（3.x 读到大于 3 的版本按最新兼容，不认识的分区忽略）。
- 和 3.x 比：去掉了 Firebase 云端备份（不做）；日志管理移出备份页；多了恢复预览、一键备份到固定目录、目录里的备份列表、分开的失败提示；同步电视改用请求体。**真机上没看过**：`Download/PureLive` 在 Android 11 起不申请权限能不能写、3.x 留在公共目录的备份能不能读（F-BAK-03 → S02.4 第 1 条）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_store/lib/src/backup/backup_service.dart`（191 行） | `BackupService.version = 4`（`:30`）、`exportAll`（`:34`，`includeSensitiveData` 时带 `cookie` 分区）、`exportFollows`（`:77`，`backupScope: favorites`）、`restoreAll`（`:91`）、`restoreFollows`（`:118`）、`_exclusive`（`:137`，一个恢复锁）、`writeFile`（`:150`，`.part` / `.previous`）、`readFile`（`:186`） |
| `packages/live_store/lib/src/legacy/legacy_snapshot.dart` | `fromBackup`（`:47`：版本检查、扁平格式和分区格式、`windowsPip` 和 `rememberPipPosition` 的旧位置、只认识的分区格式错才报错 `:123-126`、3.x 的文件做主题色迁移 `:116`） |
| `apps/pure_live/lib/shared/backup/backup_data.dart`（355 行） | `backupServiceProvider`（`:14`，备份页和 WebDAV 页共用一个，恢复锁对两页都有效）、`BackupScope`（`:19`）、`searchSection`（`:31`）、`multiviewSection`（`:35`）、`exportBackup`（`:40`）、`restoreBackup`（`:59`）、`searchWordsIn`（`:90`，去空白、截断、去重、最多 20 条）、`RestorePart`（`:158`）、`RestorePreview`（`:196`）、`previewRestore`（`:248`） |
| `apps/pure_live/lib/shared/backup/backup_iptv.dart`（226 行） | `iptvLibrarySection = 'iptvLibrary'`（`:9`）、`exportIptvLibrary`（`:21`，列表、频道、映射、节目单源，不含节目）、`iptvBackupIn`（`:37`，坏条目和重复 id 跳过）、`restoreIptvLibrary`（`:57`） |
| `apps/pure_live/lib/shared/backup/backup_files.dart`（127 行） | `backupFileName`（`:9`）、`freeBackupFile`（`:18`，重名加 `_2`）、`LocalBackupFile`、`listBackupFiles`（`:51`）、`defaultBackupFolder`（`:73`：Android 先 `/storage/emulated/0/Download/PureLive`，写不了用外部应用目录 `backup`，再不行用应用支持目录）、`isWritableFolder`（`:103`） |
| `apps/pure_live/lib/shared/backup/backup_preview_dialog.dart`（183 行） | `backupSourceText`（`:11`）、`confirmRestore`（`:31`）、`restoreWithPreview`（`:140`，各种失败分开提示） |
| `apps/pure_live/lib/features/backup/backup_page.dart`（569 行） | 页面内 provider：时钟（`:22`）、默认目录（`:25`）、选择器（`:38`，默认是应用内浏览框，`plugins.dart:51` 换成系统选择器）；`_create`（`:126`）、`_restoreFile`（`:150`）、`_restoreOther`（`:163`）、`_delete`（`:181`）、`_chooseFolder`（`:202`）、`_resetFolder`（`:228`）、`_sendToTv`/`_syncTv`（`:239`、`:250`） |
| `apps/pure_live/lib/features/backup/file_browser.dart`（175 行） | 应用内的目录/文件浏览框（没有系统选择器的平台的替代） |
| `apps/pure_live/lib/features/backup/tv_sync.dart`（244 行） | `normalizeTvAddress`（`:13`）、`tvSyncDocument`（`:31`）、`sendToTv`（`:49`）、`askTvAddress`（`:64`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_store/test/backup_test.dart`（10） | 3.x 完整备份恢复；缺的分区不动；格式错误什么都不写；v4 导出往返、默认不含账号；仅关注文件；无版本扁平格式；并发恢复被拒；`.part` 写文件 |
| `apps/pure_live/test/features/backup/backup_page_test.dart`（18） | 预览的增删计数和保持不变的部分；仅关注文件自动改为恢复关注；搜索记录往返；文件名、电视文档和地址；页面：创建、从目录恢复（取消不改、确认后写入）、菜单和删除确认、读不了的目录、选目录和改回默认、非备份文件不改任何东西、同步电视（手机扫码、电脑输入地址）、横屏和宽屏；扫码页的几种状态 |
| `apps/pure_live/test/shared/backup_extras_test.dart`（4） | 完整备份带网络电视列表（不含内置热门）和多画面上次的画面；恢复时替换列表、加节目单源、写上次的画面；3.x 的备份不动它们；坏条目和重复 id 跳过 |

## 3.x 基线

- `git show v3.2.11:lib/plugins/backup_recovery_service.dart`（131 行）：选目录和文件（file_picker）、完整备份文件名只到秒（`:28`，同一秒两次后一次覆盖）、本地恢复不确认（`:79-92`）、失败一律“恢复备份失败”（`:88-91`）、同步电视把整份数据放进 URL 查询参数（`:122-125`）。
- `lib/common/services/settings/backup_controller.dart`（522 行）：分区格式、`backupVersion: 3`、恢复时缺的分区当空分区导入（`:241-281`）、逐个控制器写入再“回滚”（`:435-455`）、新窗口交接 `recoverAndDelete` 绕过恢复锁（`:476-504`）。
- `lib/modules/backup/backup_page.dart`（317 行）、`scan_page.dart`（325 行）：云端备份（Firebase）、WebDAV 入口、设备同步入口、同步 TV 数据（扫码）、创建和恢复、仅关注导出导入、备份目录、日志管理；Android 申请“所有文件访问”（`file_utils.dart:69-86`）。
- 必须保留：文件名格式、分区和字段名（3.x 能读回 v4 的备份，v4 能读 3.x 的）；仅关注备份不能“恢复全部”、“仅恢复关注”两种文件都接受；本地和 WebDAV 备份默认不带账号；同步电视的接口 `/api/setSettings`（电视版 pure_live_TV 保留给 3.x 手机用）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| `Download/PureLive` 免权限写入、3.x 公共目录里的备份能否读、系统选择器选到的目录能否写，都没在真机上看过 | `backup_files.dart:73-92`；`backup_page.dart:202` | Android 11 起应该可写，没实测；写不了时会退到应用自己的目录（用户在文件管理器里不好找） | [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 第 1 条（CHECKLIST 第 5 节第 1 条） |
| 同步到电视没对真的 pure_live_TV 试过（v4 改成放请求体） | `tv_sync.dart:49-62` | 电视版只读查询串时会失败；J03.1 记录说电视版两种都读，没实测 | 手边有电视盒子时在 S02.4 顺带；没有任务 |
| 完整备份里的网络电视列表不含节目（只有节目单源） | `backup_iptv.dart:21-35` | 恢复后节目单要等一次同步才有 | 照设计（节目体积大、两天就过期） |
| 3.x 读 v4 的完整备份时，`iptvLibrary`、`search`、`multiview` 三个分区被忽略 | 3.x `backup_controller.dart` | 回退到 3.x 时这三样带不过去 | 照设计 |
| 恢复时如果 `restoreAll` 成功、之后写网络电视列表失败，前面的不回滚 | `backup_data.dart:59-73` | 列表没变，其余已经恢复；提示是失败 | 少见；不做（`BackupService` 自己的部分是先校验再写） |

## 相关决定和规范

- D-018（键名和分区不变）、D-019（真机不碰 3.x 的数据：3.x 的备份文件要从模拟器上的 3.x 导出，或用户自己提供）。
- J02.1 的有意差异：恢复时文件里没有的部分保持不变（3.x 重置成默认）；备份口令加密不做。
- J03.1 的决定：搜索记录进完整备份（record“做法”）。

## 测试和验证

- 自动测试：`cd packages/live_store && dart test test/backup_test.dart`；`cd apps/pure_live && flutter test test/features/backup/ test/shared/backup_extras_test.dart`。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 1 条（创建备份、恢复 3.x 导出的备份）→ S02.4；3.x 导出的备份文件来自模拟器上的 3.2.11（J06.1 任务书写了怎么造）。

## 路线

1. S02.4 第 1 条做完后把结果写回 J03.1 README 的“验证”。
2. J06.1 里用模拟器上 3.2.11 导出的备份，在测试包里走一遍“恢复 3.x 备份”（真机）。
3. 以后：备份要不要带上更多 v4 新加的东西（例如录制任务列表、本地互动的历史）由用户反馈决定，先进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [J 设置和数据](../README.md)。

- 代码：`features/backup/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| J03.1 | 备份与 WebDAV | 功能 | 完成 | 2026-10-01 | 1b730f77e | [设计或说明](J03.1-备份与WebDAV/README.md)、[记录](J03.1-备份与WebDAV/record.md) |

<!-- docs:生成结束 -->
