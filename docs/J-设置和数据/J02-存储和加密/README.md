# J02 存储和加密

数据库、设置存储、Cookie 和密码加密。

`packages/live_store` 这个包：一个 SQLite 文件里放下用户的全部数据（关注、历史、关注分区、分组、屏蔽、设置、密钥、WebDAV、内部记录），Cookie 和密码用平台密钥加密；以及应用一侧的数据目录、加密实现和多窗口共用。

## 范围

- 包括：
  - `packages/live_store/lib/src/`：`database.dart`（drift、表、事务、变更通知）、`live_store.dart`（`LiveStore`、`MetaStore`）、`rooms.dart`（关注、历史、关注分区）、`tags.dart`（分组）、`block_lists.dart`（屏蔽词和屏蔽用户）、`secrets.dart`（密钥库）、`webdav.dart`（WebDAV 配置）、`settings/`（设置的存储部分；设置项本身归 J01）、`backup/`（备份服务，格式归 J03）、`legacy/`（3.x 迁移，核对归 J06）。
  - 应用一侧：数据目录 `apps/pure_live/lib/app/data_root.dart`；加密 `apps/pure_live/lib/platform/secret_cipher.dart`（Android Keystore 经通道 `pure_live/secret_cipher`，Windows DPAPI）；启动时打开库 `app/bootstrap.dart:107-111`；`StoreCookieVault`、`StoreDouyuLogin`（`app/platforms.dart:52`、`:68`，把密钥库交给平台适配器）；网络电视表借用同一个库（`app/iptv_library.dart`，表的定义归 L01）。
  - 多个桌面窗口共用一个库：`LiveStore.open(shared: true)`、`syncExternal`（`live_store.dart:100-135`）。
- 不包括（归哪里）：
  - 每个设置的键、默认值、范围、生效位置 → J01；备份文件的格式和恢复预览 → J03；3.x 数据的转换规则是否对 → J06（代码在这里）。
  - 原生的 Keystore 实现（`AppChannelsPlugin.kt` 的 `SecretCipherChannel`）→ 由 O 组维护，这里只管接口和用法；登录、Cookie 的取得和核验 → K；Keystore 在真机上能不能解开 → K02.1。
  - 网络电视的表结构和 3.x 网络电视库的读取 → L01（`StoreIptvLibrary`、`LegacyIptvMigration`）。

## 现状：做到哪、怎么工作的

- 用户看得到的：没有专门的界面。用户感觉到的是：关注、历史、设置改了立即存下、重启还在；从 3.x 覆盖安装后数据还在（J06）；换手机或重装后账号要重新登录（Cookie 解不开，账号页顶部提示哪些平台要重新填写，A12.1）；Windows 上开第二个窗口时两个窗口看到同样的关注和设置。
- 内部怎么工作：

```text
AppBootstrap.start（bootstrap.dart:98）
  → resolveDataRoot（data_root.dart:21）：Android getApplicationSupportDirectory（/data/user/0/<包名>/files）；
    Windows exe 旁边的 UserData，写不了时用应用支持目录（从不用 3.x 的 <exe>\AppData）
  → platformSecretCipher（secret_cipher.dart:11）：Android AES-256-GCM（Keystore 里不可导出的密钥 pure_live.secrets.v1，
    密钥名作附加数据，AppChannelsPlugin.kt:147-187）；Windows CryptProtectData（当前用户，密钥名作 entropy）
  → LiveStore.open(dataRoot, cipher:, shared: true)（live_store.dart:100）
      StoreDatabase.file：NativeDatabase.createInBackground（database.dart:71，后台 isolate），共享时 busy_timeout 5 秒（:73、:82）
      建表（:45-55，11 张表，schemaVersion 1）→ SettingsStore.load（整表进内存）→ SecretStore.load（逐个解密进内存，解不开的进 unreadable）
      → _upgradeThemeColor（一次性，:154）
  → 主窗口：LegacyMigration.importHiveFiles（3.x 设置）→ LegacyIptvMigration（3.x 网络电视库）（J06）
  → wire：StoreCookieVault(store.secrets) 交给平台适配器；后台 IdentityMigration.run（按主播关注，_moveFollows bootstrap.dart:242）
写：每个仓库的写都走 StoreDatabase.write(tables, action)（:109，一个事务）→ drift 的表变更通知 → watch 流（:131）重新查询
读：设置、密钥同步读内存；关注、历史等 Future 查询或 watch 流
另一个进程写了：PRAGMA data_version（:118）变了 → settings.reload + secrets.reload + notifyAllTables
```

- 表（`database.dart:45-55`）：`follows`（身份主键、位置、房间 JSON）、`history`（身份、序号、房间）、`follow_areas`、`tags`、`room_tags`、`block_rules`（种类、折叠后的值、原值、位置）、`settings`（键、JSON 值）、`secrets`（名字、密文 BLOB）、`webdav_profiles`（名字、位置、地址、用户名；**没有密码列**）、`meta`（内部记录：迁移账本、`webdav.current`、搜索记录、多画面上次的画面、礼物开关等）、`legacy_values`（3.x 其他模块的原值，等主人接走）。网络电视另有 6 张 `iptv_` 表（L01.2，版本记在 `meta` 的 `iptv.schemaVersion`）。
- 密钥的名字（`secrets.dart:21-35`）：`cookie/<平台>`、`cookie/douyu.ltp0`、`cookie/douyu.did`、`webdav/<服务器名>`。
- 完成度：J02.1（2026-10-01，`d2fbe3072`）一次做完，之后 A16.1 加了多窗口共用（`shared`、`syncExternal`）、A11.2 加了主题色迁移。保留了 3.x 的行为（关注和历史的有效性、历史顺序和上限、清空只删当时显示的、屏蔽词去重保留第一次写法、分组名不分大小写唯一、平台列表版本表 1～38、Cookie 规范化）；确认过的改动见 J02.1 README。**真机上从没验证过 Keystore 加解密和“重装后解不开”的提示**（K02.1）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_store/lib/live_store.dart` | 对外导出（`LiveStore`、各仓库、`Settings`、`BackupService`、`LegacyMigration`、`IdentityMigration`、`SecretCipher` 等） |
| `packages/live_store/lib/src/database.dart`（163 行） | `StoreTables`（表名，`:8`）；建表语句（`:45-55`）；`StoreDatabase`：`file`/`memory`、后台 isolate（`:71`）、共享时 `busy_timeout`（`:73`）、`rows`（`:101`）、`run`（`:105`）、`write`（事务 + 变更通知，`:109`）、`dataVersion`（`:118`）、`notifyAllTables`（`:122`）、`watch`（`:131`） |
| `packages/live_store/lib/src/live_store.dart`（203 行） | `MetaStore`（`:16`：`get`/`set`、`legacyValue`、`legacyKeys`、`forgetLegacyValues`、`keepLegacyValues`）；`LiveStore`（`:83`：`open` `:100`、`syncExternal` `:113`、`memory` `:138`、`_upgradeThemeColor` `:154`、`close` `:198`） |
| `packages/live_store/lib/src/rooms.dart`（307 行） | `isStorableRoom`（`:14`，平台非空、房间号不是空/0/null/undefined/nan/none）、`fillEmptyFields`（`:27`）、`uniqueRooms`（`:32`）；`FollowStore`（`:47`：`all`、`count`、`find`、`add`、`remove`、`update` 用 `mergeFrom`、`replaceAll`、`mutate`）；`HistoryStore`（`:152`：`record` 移到最前、`clear(shown)`、`setLimit`，0 = 不限）；`FollowAreaStore`（`:248`） |
| `packages/live_store/lib/src/tags.dart`（212 行） | `StoreTag`、`TagStore`（`validateName` `:81`、`add`、`update`、`delete`、`reorder`、`pinToTop`、`tagsOf`、`assignments`、`setTagsOf`、`replaceAll`、`moveRoom` `:180`〔身份迁移时把分组跟过去〕） |
| `packages/live_store/lib/src/block_lists.dart`（78 行） | `BlockKind`（关键词、用户）、`BlockListStore`（不分大小写去重；`maxKeywordLength = 40` 只给设置页用，`:26`） |
| `packages/live_store/lib/src/secrets.dart`（217 行） | `SecretCipher` 接口（`:10`）、`SecretRefs`（`:21`）、`normalizeCookie`（`:41`）、`SecretStore`（`:51`：`load` `:55`、`reload` `:87`、`unreadable` `:133`、`cookieFor` `:139`、`writeAll` `:152`〔先全部加密再一个事务写〕、`setCookie` `:199`、`clearCookies` `:202`、`cookieChanges` `:211`） |
| `packages/live_store/lib/src/webdav.dart`（180 行） | `WebDavConfig`、`WebDavStore`（当前服务器只按名字记在 `meta` 的 `webdav.current` `:85`；密码进密钥库；`replaceAll(withPasswords:)` `:149`） |
| `packages/live_store/lib/src/settings/settings_store.dart` | 设置的存储（J01 子分类页有细节） |
| `packages/live_store/lib/src/backup/backup_service.dart`、`legacy/*` | 备份（J03）、3.x 迁移（J06） |
| `apps/pure_live/lib/app/data_root.dart`（110 行） | `resolveDataRoot`（`:21`）、`instanceFolder`（`:31`，额外窗口只放日志）、`portableDataDir`（`:34`）、`legacyHiveFiles`（`:51`，3.x 的 Hive 文件位置）、`windowsInstallLocations`（`:73`，从卸载项找 3.x 的安装目录） |
| `apps/pure_live/lib/platform/secret_cipher.dart`（108 行） | `platformSecretCipher`（`:11`；其他平台抛 `UnsupportedError`）、`AndroidKeystoreCipher`（`:20`）、`WindowsDpapiCipher`（`:45`） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/AppChannelsPlugin.kt` | `SecretCipherChannel`（`:147`：密钥别名 `pure_live.secrets.v1`，AES/GCM/NoPadding，IV 12 字节放在密文前） |
| `apps/pure_live/lib/app/platforms.dart` | `StoreCookieVault`（`:52`）、`StoreDouyuLogin`（`:68`，斗鱼 LTP0、DID、保存时间） |
| `apps/pure_live/lib/app/bootstrap.dart` | 打开库和迁移的顺序（`:98-137`）、`_moveFollows`（`:242`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_store/test/stores_test.dart`（18） | 关注的有效性、去重、不分大小写的平台、刷新不被空名字覆盖、变更流；历史的顺序、上限、清空保留之后又看的；分组名唯一、删分组；屏蔽词；设置；Cookie 加密和“换设备读不出”；WebDAV 密码进密钥库、地址规则 |
| `packages/live_store/test/shared_store_test.dart`（6） | 两个连接开同一个文件：对方写的设置、密钥、关注能 `syncExternal` 进来，自己的新写不被旧读覆盖 |
| `packages/live_store/test/migration_test.dart`（8）、`backup_test.dart`（10）、`theme_color_test.dart`（4） | 迁移（J06）、备份（J03）、主题色迁移（J01） |
| `packages/live_store/test/support.dart` | 测试用的假 `SecretCipher`（可以模拟“解不开”） |

## 3.x 基线

- 一个 Hive box `app_settings` 放全部数据（`git show v3.2.11:lib/common/utils/hive_pref_util.dart:41-44`），每改一项就把整个关注或历史列表重新编码写一遍；`lib/common/services/utils/hive_rx.dart`（115 行）用 GetX `Rx` + `ever` 自动落盘；`lib/common/services/settings_service.dart`（83 行）懒加载 21 个控制器。
- Cookie 明文存在设置 box 里（`lib/common/services/settings/cookie_settings_controller.dart:10-35`）；WebDAV 当前配置另存一份完整 JSON，含第二份明文密码（`web_dav_controller.dart:62-65`）。
- 数据目录：Android `<应用文档目录>/PURE_LIVE/HIVE_DB/`（`lib/common/global/app_path_manager.dart:20-25`、`:54`），Windows `<exe 目录>\AppData` 等（`_selectWindowsDataRoot`）。
- 必须保留：J02.1 记录“保留的 v3 行为”一节的全部规则（有效性、顺序、上限、清空、去重、分组、平台列表版本、Cookie 规范化、WebDAV 地址规则）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| Keystore 加解密、杀掉重开仍登录、重装后解不开时的提示，都没在真机上看过 | `secret_cipher.dart:20`、`AppChannelsPlugin.kt:147-187`、`secrets.dart:55-70` | 某些机型的 Keystore 出错时 Cookie 存不进去（迁移时会跳过并提示一次重新登录，`LegacyReloginNotice`），平常登录时会怎样没验证 | [K02.1](../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md) |
| 平常保存 Cookie 时 Keystore 出错，`SecretStore.writeAll` 直接抛出，调用方没有接住 | `secrets.dart:164-168`；`features/account/account_services.dart:101-107`（`save`）；`cookie_editor.dart:234-239`（只有 `finally`）；`platform_cookie_view.dart:94-123` | 用户点“保存”后按钮恢复、输入框仍是“未保存”，**没有任何提示**，异常进未处理错误；扫码登录时保存出错按轮询失败处理（`bilibili_qr_login.dart:150-159`，提示一次轮询失败），但 `_key` 已清空（`:136`），之后的轮询直接返回，页面停在“核验中” | K02.1 真机先确认 K90 上不会出错；建议开小任务：保存失败时提示“无法在本机加密保存”，并加一个用假密钥抛错的测试 |
| 数据库 `schemaVersion` 还是 1，没有升级路径（加列、改表时要写 drift 的 `onUpgrade`） | `database.dart:85` | 现在没影响；以后第一次改表结构的任务要先补升级框架和测试 | 以后改表的任务里做，任务书写明 |
| 解不开的密文一直留在 `secrets` 表里，直到同名重新写入或用户在账号页“退出” | `secrets.dart:46-50` | 占一点空间；账号页一直显示“无法在本机读取”，用户退出一次就清掉 | 照设计，不做 |
| `legacy_values` 里没人接走的 3.x 原值（例如 `record_history`）一直留着 | `live_store.dart:57-64`、`legacy_snapshot.dart:422-427` | 几 KB；3.x 自己也只写不读 | 不做 |
| 备份口令加密（把备份文件加密）没做 | — | 备份默认不带账号（同 3.x），带账号的只有设备同步 | 不做（J02.1 记录：改 3.x 的“可选明文”要先问用户） |

## 相关决定和规范

- D-018（设置键不变）、D-019（不碰 3.x 的数据）、D-006（签名不变，覆盖安装后 Android 的数据目录和 3.x 是同一个应用）。
- [specs/ENGINEERING.md](../../specs/ENGINEERING.md)：`live_store` 只依赖 `live_core`（所以网络电视的表在应用里实现，L01.2）；不把真实 Cookie、账号写进仓库。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“房间身份”“按主播关注”“占位信息”，11-8、17-1、23-1、6-5、C-17、C-22（J02.1 README 有逐条）。

## 测试和验证

- 自动测试：`cd packages/live_store && dart test`（46 个）；应用里用 `LiveStore.memory(cipher: …)`（假密钥）。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6 条（扫码登录后杀掉重开仍登录 = Keystore 解密正常）→ K02.1；覆盖安装后的数据 → J06.1。查库：`adb shell run-as com.mystyle.purelive.v4dev ls files/`（debug 构建），拉出 `files/pure_live.db` 用 `sqlite3` 看表（不要拉正式包的）。

## 路线

1. **K02.1**（第二档）：K90 上验证 Keystore 加密存储、杀掉重开、重装后解不开的提示；结果写回本页的已知问题。
2. **J06.1**（第一档）：用 3.x 的真实格式数据走一遍迁移，验证这一层的合并规则。
3. 以后：第一次要改表结构的任务先补 drift 的升级框架（`onUpgrade`、迁移测试）；需要时再评估备份加密（先进 V01 提议）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [J 设置和数据](../README.md)。

- 代码：`packages/live_store`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| J02.1 | 存储、设置、备份、3.x 数据迁移（模块重构） | 功能 | 完成 | 2026-10-01 | d2fbe3072 | [设计或说明](J02.1-存储和迁移/README.md)、[记录](J02.1-存储和迁移/record.md) |

<!-- docs:生成结束 -->
