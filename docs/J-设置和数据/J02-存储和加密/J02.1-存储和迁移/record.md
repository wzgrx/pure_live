# J02.1 存储、设置、备份、3.x 数据迁移

- 日期：2026-10-01
- 目标包：`packages/live_store`（纯 Dart，依赖 `live_core`、`drift`、`sqlite3`、`path`、`meta`；测试另用 `hive_ce` 按 3.x 的写法造样本）
- v3 来源：标签 `v3.2.11` 的 `plugins/db_service.dart`、`plugins/backup_recovery_service.dart`、`common/utils/hive_pref_util.dart`、`common/services/settings_service.dart`、`common/services/settings/*`、`common/services/utils/*`（`hive_rx`、`settings_upgrade_migration`、`backup_migration_util`）、`modules/tags/tag_management_controller.dart`、`modules/web_dav/webdav_config.dart`、`common/global/app_path_manager.dart`（数据位置）
- 设计参考：归档 v4 的 `spec/modules/store.md` 和 `packages/live_store`（只借鉴思路，代码重写；与 v3 冲突处以 v3 为准）

## 做法

- **存储方式：drift + sqlite3（PLAN 第 4 节），不用代码生成。** 一个数据库文件 `<数据目录>/pure_live.db`，在后台 isolate 打开（`NativeDatabase.createInBackground`），界面线程不做读写。表很少（关注、历史、关注分区、分组、分组分配、屏蔽、设置、密钥、WebDAV、内部记录、3.x 其他模块的原值），SQL 直接写在各自的仓库类里，用 drift 的事务和表变更通知做 `watch…` 流。理由：
  - v3 所有数据在一个 Hive box 里，每改一项就把整个关注或历史列表重新编码写一遍；SQLite 按行写、有事务，失败不会写一半；
  - drift 提供后台 isolate、事务、变更通知，正好对应 v3 用 GetX `Rx` 做的“改了就刷新界面”；
  - 不用 build_runner 生成代码：表少且简单，手写 SQL 比生成的 6000 行代码好审查，依赖也少（不需要 drift_dev、build_runner）。
- **设置**：`Settings` 里每个设置一个类型化常量（`BoolSetting`、`IntSetting`、`DoubleSetting`、`StringSetting`、`StringListSetting`、`JsonSetting`），键就是 3.x 的 Hive 键，默认值、取值范围照 3.x 各控制器；`section`/`backupKey` 是 3.x 备份文件里的分区和字段名。`SettingsStore` 打开时整表读进内存，`get` 同步，`set` 写库后才更新内存并发出变更。存的值不合法（类型不对、越界、不在可选值里）读出时夹紧或用默认值，不抛错。
- **密钥**：Cookie、斗鱼 LTP0/DID、WebDAV 密码放在 `secrets` 表，用应用提供的 `SecretCipher`（Android Keystore、Windows DPAPI，I01.1 实现）加密；打开时全部解密进内存，`cookieFor` 同步，应用实现 live_net 的 `CookieVault` 只需转接 `cookieFor` 和 `cookieChanges`。解不开的（换设备、重装）当作未登录，列在 `unreadable`。
- **对外接口照 v3 的用法**（`LiveStore` 的成员对应 v3 的 `SettingsService.to.xxx`）：

| v3 | v4 |
|---|---|
| `FavoriteRoomController.favoriteRooms`、`addRoomDurably`、`removeRoomDurably`、`updateRoomDurably`、`replaceRoomsDurably`、`mutateRoomsDurably`、`getRoomById`、`isFavorite` | `store.follows`：`all`/`watchAll`、`add`、`remove`、`update`（刷新结果，`LiveRoom.mergeFrom`）、`replaceAll`、`mutate`、`find`、`contains`/`watchContains` |
| `favoriteAreas`、`addAreaDurably`、`removeAreaDurably` | `store.followAreas` |
| `shieldList`、`blockedDanmakuUsers`、`addShieldList`、`removeShieldList` | `store.blockLists`（`BlockKind.keyword`/`user`） |
| `HistoryController`（`addRoomToHistoryDurably`、`clearHistorySnapshotDurably`、`applyRefreshedRoomsDurably`、`setHistoryLimitDurably`） | `store.history`：`record`、`clear(shown)`、`update`、`setLimit` |
| `TagManagementController`（`addTag`、`updateTag`、`deleteTag`、`pinToTop`、`setRoomTags`、`getTagsForRoom`、`validateTagName`） | `store.tags`：`add`、`update`、`delete`、`pinToTop`、`reorder`、`setTagsOf`、`tagsOf`、`assignments`、`validateName`（按 id 操作，不再按下标） |
| `CookieSettingsController` | `store.secrets`：`cookieFor`、`setCookie`、`clearCookies`、`read`/`write` |
| `WebDavController` | `store.webdav`：`all`、`add`、`update`、`remove`、`select`、`current`、`replaceAll` |
| 其余 20 个设置控制器的 `hiveBool/Int/...` 字段 | `store.settings.get(Settings.xxx)`、`set`、`watch`、`reset`、`resetAll` |
| `BackupController`、`BackupRecoveryService` | `BackupService`：`exportAll`、`exportFollows`、`restoreAll`、`restoreFollows`、`writeFile`、`readFile`（选目录、权限、提示留给页面） |
| `SettingsUpgradeMigration`、`AppPathManager` 的旧数据查找 | `LegacyLocations`、`LegacyMigration.importHiveFiles`、`IdentityMigration.run` |

- **备份格式**：沿用 3.x 的分区布局（`app`、`theme`、`player`、`danmaku`、`favorite`、`history`、`tags`……），写 `backupVersion: 4`。3.x 读到大于 3 的版本按“最新兼容”导入，不认识的键忽略，所以 v4 的备份 3.x 也能恢复（回退时有用）。读：无版本的扁平格式、2～4 版、仅关注文件（`backupScope: favorites`）。Cookie 和 WebDAV 密码只在要求时写入（同 3.x）。
- **3.x 数据迁移**：
  - 位置：Android `<应用文档目录>/PURE_LIVE/HIVE_DB/app_settings.hive`；Windows `<exe 目录>\AppData`、回退目录 `<应用支持目录>\PURE_LIVE`、3.x 自己迁移过的旧目录、同级的 `pure_live` 安装、应用传入的注册表安装目录，并沿 `previous_install_locations.txt` 账本继续找（最多 32 个位置），每处看 `app_settings.hive` 和 `HIVE_DB\app_settings.hive`。
  - 读取：`HiveBoxReader` 直接解析 Hive 文件的字节（帧长、键、值、CRC32，后写的覆盖先写的，删除帧生效，遇到坏帧停在那里），**不打开 box、不建 .lock、不压缩、不改不删**。
  - 转换：`LegacySnapshot.fromHive` 把原始键值转成 v4 类型并修复（见下“升级”和“保留的行为”），再由 `LegacyMigration.merge` 写入：库里已有的设置、Cookie、WebDAV 优先；关注、历史、分区、分组、屏蔽按身份合并，空字段互补（同 3.x `mergeRawSettings`）。
  - 账本：每个来源记 `路径|大小|修改时间`（3.x 的格式，3.x 账本 `settingsUpgradeImportedSources` 里的来源也算已导入），下次启动跳过；读不了的来源不记，下次重试。
  - 3.x 其他模块的值（录制设置和 `recorder_tasks`、`localInteraction.*` 等）原样存进 `legacy_values`，由 H01.1/M13 读取（`store.meta.legacyValue`）。

## 对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `plugins/db_service.dart` | 11 | — | 只是打开 IPTV 库的 GetX 服务；IPTV 库归 L01.1 |
| `common/utils/hive_pref_util.dart` | 139 | `database.dart`、`settings/settings_store.dart` | Hive 单 box 改 SQLite；批量写改事务 |
| `common/services/utils/hive_rx.dart` | 115 | `settings/setting.dart`、`settings_store.dart` | `Rx` + `ever` 自动落盘改为显式 `set` + `watch` |
| `common/services/settings_service.dart` | 83 | `live_store.dart`（`LiveStore`） | GetX 懒加载 21 个控制器改为一个对象的成员 |
| `common/services/settings/*_controller.dart`（设置项部分） | 约 4500 | `settings/settings.dart` | 153 个设置（含 6 个新增）的键、默认值、范围；界面逻辑（窗口、字体下载、刷新率通道）留给 A01.1～M13 |
| `favorite_room_controller.dart` | 648 | `rooms.dart`（`FollowStore`、`FollowAreaStore`）、`block_lists.dart`、`legacy/legacy_rules.dart` | 平台列表版本表、首选平台修复移到迁移规则 |
| `history_controller.dart` | 236 | `rooms.dart`（`HistoryStore`） | 行为相同 |
| `modules/tags/tag_management_controller.dart`（存储部分） | 427 | `tags.dart` | 键改为 v4 房间身份 |
| `cookie_settings_controller.dart`、`cookie_value.dart` | 147 | `secrets.dart` | 加密存储 |
| `web_dav_controller.dart`、`webdav_config.dart` | 167 | `webdav.dart` | 密码进密钥库，当前服务器按名字记 |
| `backup_controller.dart`、`plugins/backup_recovery_service.dart` | 653 | `backup/backup_service.dart`、`legacy/legacy_snapshot.dart` | 先整体解析校验再写入 |
| `utils/settings_upgrade_migration.dart`、`backup_migration_util.dart`、`app_path_manager.dart`（旧数据查找） | 约 420 | `legacy/hive_reader.dart`、`legacy/legacy_import.dart`、`legacy/legacy_snapshot.dart` | 只读字节，不打开旧 box |

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | Cookie、WebDAV 密码明文存在设置 box 里 | `cookie_settings_controller.dart:10-35`、`web_dav_controller.dart:17-26` | 所有数据共用一个 Hive box | 放进 `secrets` 表，由平台密钥加密 |
| 2 | WebDAV 当前配置另存一份完整 JSON，含第二份明文密码；删掉配置后这份还在 | `web_dav_controller.dart:62-65` | 用整份配置当“当前”的标记 | 只按名字记当前服务器 |
| 3 | 恢复一个只含部分分区的备份时，缺的分区被重置为默认值 | `backup_controller.dart:241-281`（`data['x'] ?? {}`） | 缺分区当作空分区导入 | 文件里没有的部分保持不变 |
| 4 | 恢复逐个控制器写入，出错再重新导入旧快照“回滚”；回滚也可能失败 | `backup_controller.dart:435-455` | 没有事务 | 先整体解析和校验（格式错一律在写入前报错），再按部分写入；同一时间只允许一个恢复 |
| 5 | 备份里某个字段类型不对（如 `bilibiliUid` 是字符串、标签 `order` 是字符串）整个恢复失败 | `cookie_settings_controller.dart:96-107` 的 `as String`/`as int`；`live_tag.dart` 的 `json['order'] ?? 0` | 强制类型转换 | 逐项解码，不合法的项用默认值并记入 `skipped` |
| 6 | 每次启动都做一遍迁移检查：整个 box 转 Map、两次 `jsonEncode` 比较、解码关注和历史 | `settings_upgrade_migration.dart:45-99` | 迁移没有“已完成”判断，只有来源指纹 | 迁移由应用在需要时调用；来源按指纹账本跳过，没有新来源时只做文件状态查询 |
| 7 | 迁移要把旧文件复制到工作目录再用 Hive 打开、关闭、删除副本和锁文件 | `settings_upgrade_migration.dart:57-73` | 只能用 Hive 读 Hive 文件 | `HiveBoxReader` 直接解析字节，不复制、不打开、不留锁文件 |
| 8 | 合并 WebDAV 配置时用了配置里不存在的 `url` 字段作身份 | `settings_upgrade_migration.dart:224` | 字段名写错，实际只按名字 | 明确按名字合并 |
| 9 | 旧的“只有房间号”的分组键只迁移给关注，历史里的同号房间丢了分组 | `modules/favorite/favorite_controller.dart:86` | 只传了关注列表 | 关注和历史里房间号相同的都给 |
| 10 | 刷新时 `mergeFrom` 保留存下的公告，3.x 存的“远端聊天尚待接入”永远不消失 | `LiveRoom.mergeFrom`（E05.2）对空公告保留旧值；3.x 的翻译 `*_chat_notice` | 公告当作普通字段存 | 迁移和恢复时清掉这类公告（`LegacyRules.isStaleNotice`） |
| 11 | 不区分大小写的平台（Twitch、Picarto 等）同一主播可能关注两次 | 3.x `identityKey` 区分大小写（E05.2 已改） | 身份规则 | 导入时按 v4 身份合并，第一条的位置和写法保留，空字段由后一条补上 |
| 12 | 新窗口交接文件 `recoverAndDelete` 绕过恢复锁和回滚，直接导入 | `backup_controller.dart:476-504` | 走了另一条路径 | 交接改用 `restoreAll`（I01.1 接） |

## 保留的 v3 行为

- 关注、历史的有效性：平台非空，房间号不是空、`0`、`null`、`undefined`、`nan`、`none`（不分大小写）。
- 关注的顺序就是用户的顺序；历史新的在前，重看移到最前，按 `historyLimit` 截断，0 = 不限；“清空”只删页面当时显示的那些（之后又看的保留，按 `lastWatchedAt` 判断）。
- 刷新历史时保留观看时间和人数兜底（`withAudienceFallbackFrom`）。
- 屏蔽词、屏蔽用户：去首尾空白、不为空、不分大小写去重，保留第一次的写法；导入不限长度（`maxKeywordLength = 40` 只给设置页用）。
- 分组：名字不分大小写唯一；删分组时从所有房间去掉；id 为空或重复时重新分配（3.x `_normalizeTags`），名字重复的导入照旧保留。
- 平台列表：小写、去重、只留支持的平台；按 `siteCatalogMigration` 补上之后版本新增的平台，退役平台保留版本号但不再加入（3.x 版本表 1～38）；首选平台不在列表里时改为列表第一个。
- `realOnlinePlatforms` 按 `audienceMetricMigration` 补 twitch、soop、acfun、picarto、twitcasting；`danmakuInteractionMigration` < 1 时打开点按和长按互动；没有 `refreshRateMode` 时由旧的 `enableHighRefreshRate` 推出（true → balanced）；`savedMenuIds` 只留已知菜单，空时只留关注。
- 3.x 的 Cookie 规范化（去控制字符、去首尾空白）；淘宝 Cookie 丢弃。
- WebDAV 地址校验规则（http/https、有主机、无用户信息、无查询和片段）。
- 备份写文件：先写 `.part`，旧文件先改名 `.previous`，新文件就位后删除；上次中断留下的 `.previous` 先恢复。
- 仅关注备份不能用“恢复全部”导入；“仅恢复关注”接受完整备份和仅关注文件，其他设置不动。

## 有意差异

| 差异 | 原因 |
|---|---|
| 存储从 Hive 单 box 换成 SQLite（drift） | PLAN 第 4 节；按行写、有事务，后台 isolate |
| Cookie、密码加密存储 | PLAN 第 4 节和 AGENTS.md 安全规则 |
| 恢复时文件里没有的部分保持不变（3.x 重置为默认） | v3 问题 3：只含部分分区的备份会清掉其它设置 |
| 读 3.x 的 Hive 文件不再经过 Hive | v3 问题 7；也满足“只读 3.x 的文件，不改不删” |
| 房间身份按 v4 规则（部分平台不分大小写），导入时合并重复 | UPGRADES 统一原则“房间身份”、11-8 |
| 导入时清掉“远端聊天尚待接入”公告 | 弹幕已接入（D01），见 v3 问题 10 |
| 3.x 的 `page_default_size` 默认值随屏幕宽度计算；v4 默认 0 表示“由界面按宽度决定” | 纯 Dart 包拿不到屏幕宽度；界面照 3.x 规则（宽于 960 逻辑像素 20 条，否则 12 条） |
| `videoPlayerKey` 默认 `mpv`（3.x iOS 默认 ijk） | v4 全平台只用 mpv；保留这个键只为备份往返 |
| 分组操作按 id，不再按列表下标 | 下标在并发刷新时会指错分组；页面换接口时一并改 |
| v4 备份写 `backupVersion: 4`（3.x 写 3），布局不变 | 区分来源；3.x 仍能读 |

## 已批准的升级（docs/specs/UPGRADES.md）

| 编号 | 本包里做了什么 |
|---|---|
| 统一原则“受限……” | 新设置 `showUnplayableInDiscover`（发现页显示不能播放的直播，默认关） |
| 统一原则“默认编码”、22-3、14-5、33-2、8-8 | 新设置 `preferH264`（默认开），适配器和播放器读取由 G/M12 接上 |
| 统一原则“画质命名”、9-1、13-1、15-6、16-3、21-7、22-2、22-4、25-5、30-1 | `LegacyRules.qualityId` 按各平台 `*Api.qualityIdFromLegacy` 换算 3.x 的画质 id；导入时换算 `recorder_tasks` 的 `selectedQualityId`（只对 3.x 数据做一次） |
| 统一原则“按主播关注”、17-1、23-1，抖音 room_id → web_rid（m13_notes） | `LegacyRules.needsIdentityMigration` 找出要换身份的关注和历史；`IdentityMigration.run(store, resolver)` 迁移名字、分组、位置，换掉旧链接和公告，合并重复；联网解析由应用传入（I01.1/M13 接 `DouyinSite.getRoomDetailForRefresh`、`NiconicoSite.resolveRoomId`、`YouTubeSite.resolveRoomId`），解析失败的保留原样，下次再试 |
| 统一原则“房间身份”、11-8 | 导入、恢复、写入都按 v4 身份去重合并 |
| 统一原则“占位信息”、X-2、28-2 | `FollowStore.update` 用 `LiveRoom.mergeFrom`：空名字、标题、封面不覆盖存下的值 |
| 2-1 | 新设置 `douyuForceRenew`（登录后强制续期，默认关） |
| 8-3 | 新设置 `twitchLanguages`（默认空 = 不筛选），`Settings.twitchLegacyLanguages` 是 3.x 的中文 + 韩语预设 |
| B-13 | 新设置 `youtubeShowAllChat`（默认关） |
| 6-5 | 关注分区只增删、不被分类页的数据覆盖，3.x 存的 `shortName` 保留 |
| 9-4、31-4、20-1、33-1 | 分区 id 不变，不需要迁移（核对了各平台记录） |
| C-17、C-22 | 密钥库按平台存 Cookie（任何平台 id，含 `cc`、`kuaishou`），余下验证和接入在 T02.D2/M5 |
| m13_notes：FC2 等“聊天尚待接入”公告 | 导入时清掉（`LegacyRules.isStaleNotice`） |

## 留给其他模块

| 内容 | 去向 |
|---|---|
| `SecretCipher` 的平台实现（Android Keystore、Windows DPAPI）；`CookieVault` 转接；数据目录选择（Windows `{exe}\UserData` 等）；注册表里的旧安装位置；首次启动调用 `LegacyMigration.importHiveFiles` 和 `IdentityMigration.run`（要在第一次关注刷新之前） | I01.1 |
| 选目录、存储权限、提示文字；WebDAV 上传下载；局域网同步；旧电视接口 `/api/setSettings` 不再提供 | M13 |
| 新窗口交接文件改用 `restoreAll`（v3 问题 12），不带 Cookie 明文 | I01.1 |
| 录制设置和 `recorder_tasks`（已换算画质 id）从 `store.meta.legacyValue` 读取；录制设置加进注册表 | H01.1 |
| `localInteraction.*`、`record_history` 等其他 3.x 值 | M13 |
| IPTV 库（`IPTV_CACHE/pure_live_tv/pure_live_tv.db`）、`db_service` | L01.1 |
| 3.x 的 `roomVolumes`、`portraitRoomOverrides` 照旧是 JSON 设置；改成按房间的表留到用到它们的页面 | M13 |
| SharedPreferences 里 easy_localization 的 `locale` | I01.1（多语言） |
| 备份口令加密（归档 v4 的设想） | 不做：3.x 的做法是“可选明文”，改变要先问用户 |

## 依赖变化

- v3：hive_ce、hive_ce_flutter、path_provider、shared_preferences、webdav_client、file_picker，全部通过 GetX 控制器使用。
- v4 本包：`drift` 2.35.1、`sqlite3` 3.7.0（预编译库由 sqlite3 的构建钩子提供）、`path`、`meta`、`live_core`；开发依赖 `hive_ce` 2.20.1 只用来在测试里按 3.x 的写法造 box 文件。根 `pubspec.lock` 新增 drift、sqlite3、hooks、code_assets、native_toolchain_c、ffi、platform、process、record_use、hive_ce、isolate_channel、json_annotation。

## 测试

30 个用例（加速流程：只测主要路径和审查出的问题）：

| 测试文件 | 内容 |
|---|---|
| `stores_test.dart`（15） | 关注的有效性、去重、不分大小写的平台、刷新不被空名字覆盖、变更流；历史的顺序、上限、不限、清空保留之后又看的（移植 3.x `history_metadata_test`）；分组名唯一、删分组；屏蔽词；设置默认值、夹紧、可选值、`watch`；Cookie 加密和换设备读不出；WebDAV 密码进密钥库、地址规则 |
| `migration_test.dart`（7） | 用 hive_ce 按 3.x 的写法造 box：`HiveBoxReader` 读各种类型、删除、坏尾；导入 2.0 和 2.1 两种列表格式、无效房间、重复合并、陈旧公告、分组旧键、屏蔽去重、Cookie、WebDAV、设置修复、平台列表版本、录制任务画质 id、源文件字节不变且不留锁文件；第二次导入跳过、库里已有的优先（移植 3.x `settings_upgrade_migration_test`）；Windows 账本；身份迁移；画质 id |
| `backup_test.dart`（8） | 3.x 完整备份恢复；缺的分区不动；格式错误什么都不写；v4 导出往返、默认不含账号；仅关注文件（移植 3.x `backup_roundtrip_test` 的主要用例）；无版本扁平格式；并发恢复被拒；`.part` 写文件 |
