# J02.1 存储、设置、备份、3.x 数据迁移（模块重构）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：存储层）
- 来源：模块重构计划 M9（PLAN 第 4 节：存储从 Hive 单 box 换成 SQLite，Cookie 和密码加密）
- 旧编号：M9、T09b.1
- 相关：之后的 I01.1（应用接上：`SecretCipher` 的平台实现、数据目录、启动时迁移）、J01.1（设置页）、J03.1（备份页）、L01.2（网络电视表借用同一个库）、H01.1（录制设置从 `legacy_values` 接走）、K01.1（账号页用 `SecretStore`）、J06.1（真机核对迁移）；决定 D-018；记录 [record.md](record.md)

## 目标

把 3.x 的数据层（一个 Hive box、21 个 GetX 控制器、明文 Cookie）换成纯 Dart 的 `packages/live_store`：一个 SQLite 文件、按行写、有事务、在后台 isolate；设置是类型化的注册表，键名就是 3.x 的 Hive 键；Cookie 和 WebDAV 密码用平台密钥加密；备份格式照 3.x（3.x 和 4.x 能互相读）；第一次启动时**只读**地把 3.x 的数据导进来。对外接口照 3.x 控制器的用法，页面可以一个调用一个调用地换过来。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（`packages/live_store/lib/src/`） | 要做到 |
|---|---|---|---|
| 存储 | 一个 Hive box `app_settings`（`common/utils/hive_pref_util.dart:41-44`），改一项重写整个列表 | SQLite（drift，后台 isolate，`database.dart:71`），11 张表，每次写一个事务（`:109`） | 完成 |
| 设置 | 各控制器 `hive*('键', 默认值)` + `ever` 落盘（`common/services/utils/hive_rx.dart`） | `Settings` 注册表 + `SettingsStore`（J01） | 完成 |
| Cookie、密码 | 明文（`cookie_settings_controller.dart:10-35`、`web_dav_controller.dart:17-26`），当前 WebDAV 另存一份带密码的 JSON（`:62-65`） | `secrets` 表，`SecretCipher` 加密（`secrets.dart:51`）；当前服务器只按名字记（`webdav.dart:85`） | 完成；真机见 K02.1 |
| 恢复 | 缺的分区重置成默认（`backup_controller.dart:241-281`）；逐个控制器写、出错再“回滚”（`:435-455`） | 先整体解析校验再写，缺的部分保持不变，同一时间一个恢复（`backup_service.dart`） | 完成 |
| 迁移 | 每次启动把旧文件复制出来用 Hive 打开、比较两次 `jsonEncode`（`settings_upgrade_migration.dart:45-99`） | `HiveBoxReader` 直接解析字节，按指纹账本只导一次（`legacy/`） | 完成；真机见 J06.1 |

## 结果

- 提交：`d2fbe3072`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)“做法”“对照”）：
  - c1 存储：drift + sqlite3，不用代码生成（表少，手写 SQL 好审查，少两个开发依赖）；`LiveStore` 的成员对应 3.x 的 `SettingsService.to.xxx`（`follows`、`history`、`followAreas`、`tags`、`blockLists`、`settings`、`secrets`、`webdav`、`meta`）。
  - c2 设置注册表：当时 153 个设置（含 6 个新加），之后各任务加到 218 个（J01）。
  - c3 密钥：`secrets` 表 + 应用注入的 `SecretCipher`；打开时全部解密进内存，`cookieFor` 同步；解不开的当作未登录，列在 `unreadable`。
  - c4 备份：`BackupService`（`exportAll`、`exportFollows`、`restoreAll`、`restoreFollows`、`writeFile`、`readFile`），写 `backupVersion: 4`、3.x 的分区布局；读无版本的扁平格式、2～4 版、仅关注文件；账号只在要求时写入（同 3.x）。
  - c5 3.x 迁移：`LegacyLocations`（Android、Windows 的各种旧位置）、`HiveBoxReader`（不打开 box、不建锁、不改不删）、`LegacySnapshot`（转换和修复）、`LegacyMigration.merge`（库里已有的优先，集合按身份合并、空字段互补）、账本（3.x 自己的账本也认）、`IdentityMigration`（抖音 room_id → web_rid、niconico、YouTube 按主播关注，联网解析由应用传入）；3.x 其他模块的原值放进 `legacy_values`。
  - c6 修了 12 个 3.x 问题（record“审查发现的 v3 问题”：明文密码、恢复重置缺的分区、没有事务、类型不对整个恢复失败、每次启动都迁移、合并 WebDAV 用了不存在的字段、旧分组键只给关注、陈旧公告“远端聊天尚待接入”、大小写重复关注、新窗口交接绕过恢复锁等）。
  - c7 已批准升级 22 条（受限直播、优先 H.264、Twitch 语言、斗鱼续期、YouTube 全部聊天、画质命名换算、按主播关注、房间身份、占位信息不覆盖、关注分区只增删等，record 有逐条）。
- 有意差异：存储换成 SQLite；密钥加密；恢复时缺的部分保持不变；读 Hive 不经过 Hive；身份按 v4 规则合并重复；导入时清掉陈旧公告；`page_default_size` 默认 0 = 界面按宽度决定；`videoPlayerKey` 默认 `mpv`；分组按 id 操作；备份写版本 4。
- 测试：当时 30 个（`stores_test.dart` 15、`migration_test.dart` 7、`backup_test.dart` 8，移植了 3.x 的 `history_metadata_test`、`settings_upgrade_migration_test`、`backup_roundtrip_test` 的主要用例）；现在 `packages/live_store/test/` 共 46 个（之后加了多窗口共用和主题色迁移）。
- 依赖：`drift` 2.35.1、`sqlite3` 3.7.0；`hive_ce` 2.20.1 只作开发依赖，用来在测试里按 3.x 的写法造 box。

## 验证

- 自动测试：`cd packages/live_store && dart test`。
- 真机：没有。**迁移从没用真实的 3.x 数据跑过**（测试包 `.v4dev` 读不到 3.x 的私有目录），由 [J06.1](../../J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md) 和 [S04.1](../../../S-质量和验证/S04-覆盖安装验证/README.md) 做；Keystore 加解密由 [K02.1](../../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md) 做。登记表按当时“构建通过 + 单元测试”记成“完成”。

## 留下的问题

- 当时留给其他模块的（record“留给其他模块”）都已接走：平台密钥实现、数据目录、启动时迁移和身份迁移（I01.1）；新窗口交接改用 `restoreAll`（I01.1）；录制设置和任务（H01.1，`LegacyMigration.adoptLegacyValues`）；本地互动设置（A08.2）；网络电视库（L01.2）。
- 3.x 存下的京东、酷狗、百度占位值（`JD Live`、`Kugou Live`、`Baidu Live` 等）迁移时没有清理规则（E02.9、E02.10、E02.11 的 README 记了）→ J06.1 核对时看，需要时开任务。
- 数据库没有升级路径（`schemaVersion` 1）→ 第一次改表结构的任务补上（J02 子分类页“已知问题”）。
- 备份口令加密：不做（3.x 是“可选明文”，改变要先问用户）。
