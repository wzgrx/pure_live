# live_store

Pure Live v4 的存储层（纯 Dart）：drift 主库和各个数据仓库、设置注册表、加密的密钥库、v4 备份和 3.x 备份导入、分享口令。行为依据 [spec/modules/store.md](../../spec/modules/store.md)，决策见 [ADR 0004](../../docs/adr/0004-storage-and-migration.md) 和 [draft-store](../../docs/adr/draft-store.md)。只依赖 `live_core`。

## 打开

```dart
final store = await LiveStore.open(dataRoot);          // <dataRoot>/DB/pure_live.db，后台 isolate，WAL
final secrets = await SecretStore.open(
  cipher: platformCipher,                               // Android Keystore / Windows DPAPI 的实现，由应用提供
  backend: FileSecretBackend.inRoot(dataRoot),          // <dataRoot>/DB/secrets.json
);
```

`LiveStore.open` 返回时设置已经读进内存，界面可以直接同步读取（REG-STORE-001：存储就绪是构建界面的前提）。测试用 `LiveStore.inMemory()` 和 `SecretStore.memory()`。

## 数据仓库

| 属性 | 内容 | 主要方法 |
|---|---|---|
| `store.follows` | 关注（`FollowedRoom`：房间快照、关注时间、自定义顺序、标签 id） | `watchAll()`、`watch(ref)`、`watchContains(ref)`、`follow(snapshot)`、`unfollow(ref)`（返回被删的项，用于撤销）、`restore(entries)`、`reorder(refs)`、`count()` |
| `store.rooms` | 关注、历史、标签共用的房间快照 | `update(snapshots)`（刷新结果，只更新已有房间）、`get` / `watch(ref)`、`prune()` |
| `store.history` | 观看历史，最新在前，上限 `Settings.historyLimit`（0 = 不限） | `watchAll()`、`record(snapshot)`、`remove(ref)`、`clear(shownSnapshot)`（只删清空时看到的记录）、`restore(entries)`、`trim()` |
| `store.tags` | 标签（关注分组），名称不区分大小写唯一 | `watchAll()`、`create`、`rename`、`describe`、`delete`、`reorder`、`setTagsOf(ref, ids)`、`addRooms` / `removeRooms`、`watchTagsOf(ref)` |
| `store.blockRules` | 弹幕屏蔽词和屏蔽用户，按去空白小写后唯一 | `watchAll([kind])`、`add(kind, value)`、`remove(kind, value)` |
| `store.followAreas` | 关注的分区（身份：平台、命名空间、分区 id） | `watchAll()`、`follow`、`unfollow`、`contains` |
| `store.roomPrefs` | 房间级偏好（`volume`、`portraitLayout`） | `get` / `set`、`volumeOf` / `setVolume` |
| `store.settings` | 设置 | `get(setting)`（同步）、`set`、`reset`、`resetAll`、`watch(setting)`、`changes` |
| `store.iptv` | IPTV 播放列表、条目、节目单源、节目单频道和节目（[iptv.md](../../spec/modules/iptv.md) §7） | `watchPlaylists()`、`addPlaylist`、`replaceEntries`（整体替换，一次事务）、`recordPlaylistFailure`、`groups`、`channels`（按名称去重分页）、`sources(name)`；`watchGuideSources()`、`addGuideSource`（第一个自动设为当前）、`selectGuideSource`、`replaceGuide`、`programmes`、`programmesAt`、`pruneProgrammes` |
| `store.meta` | 内部记录（导入账本、设备 id） | `get` / `set` |

房间一律用 `live_core` 的 `RoomRef` 表示：平台小写，房间号区分大小写，`0`、`null`、`undefined`、`nan`、`none` 无效。写入方法在数据真正落库后才完成；`watch…` 流在相关表变化后重新发出。`StoredRoom.lastState` 只是缓存，关注页启动时应一律显示“未知”，等第一次刷新（store.md §6.4.10）。

## 设置注册表

`Settings` 里每个常量是一条定义：id、默认值、校验（数值夹紧、枚举集合）、JSON 编解码、3.x 旧键和旧值转换、作用域（`synced` / `device` / `internal`）。备份范围、重置和导入都从 `Settings.all` 派生。加一个设置：在 `lib/src/settings/registry.dart` 声明常量并加进 `all`。

预览版用到的设置：`themeMode`（跟随系统 / 浅 / 深）+ `pureBlack`（深色时纯黑，spec/design/principles.md §2 规定纯黑是开关而不是第四种模式）、`denseFollows`（关注页紧凑卡片）、`startPage`、`qualityWifi` / `qualityMobile`、`hardwareDecoding`、`danmakuEnabled` 和弹幕样式（字号、字重、透明度、速度、显示区域、描边）等。屏蔽词不是设置，在 `store.blockRules`。

`set` 会校验并夹紧；非法值抛 `ArgumentError`。库里存的非法值读取时回退默认值并通过 `StoreLog` 记一条警告。

## 密钥库

- 引用名见 `SecretRefs`：`cookie/<平台>`、`cookie/douyu.ltp0`、`cookie/douyu.did`、`webdav/<id>`、`iptv/xtream/<id>`。
- 打开时全部解密进内存，`read` / `cookieFor` 是同步的；`changes`、`cookieChanges` 在写入落盘后发出。应用对接 `live_net` 的 `CookieVault` 只需要：`cookieFor(site) => secrets.cookieFor(site)`，`changes => secrets.cookieChanges`（`live_store` 不能依赖 `live_net`，所以适配放在应用里）。
- 加密接口是 `SecretCipher`（`seal` / `open`），不是“取密钥”：Android Keystore 和 DPAPI 都不导出密钥。`AesGcmSecretCipher` 是调用方自带 32 字节密钥的实现（AES-256-GCM，随机 12 字节 nonce，附加认证数据绑定引用名）。
- 解不开的密钥（换设备、重装、密钥丢失）按“未登录”处理，列在 `unreadable`，文件里的密文保留到该引用名被重新写入；不会崩溃。
- 值不进日志、`toString`、异常、主库和默认备份。

**威胁模型。** 防：主库、备份文件、日志、临时文件、诊断包泄露 Cookie；别的应用读到密钥文件；密文被挪到另一个引用名下（附加认证数据）；密文被篡改（GCM 标签）。不防：以当前用户身份运行的恶意程序或 root（它可以直接调用 Keystore / DPAPI，或读进程内存）；`AesGcmSecretCipher` 的密钥和密文放在一起时只是混淆，安全性等于密钥的保管方式。

## 备份

```dart
final backup = BackupService(store, secrets: secrets);      // platform 默认 Platform.operatingSystem
final file = await backup.exportToDirectory(dir);            // v4 完整备份，不含密钥
await backup.exportToDirectory(dir, scope: BackupScope.follows);
await backup.export(passphrase: '…');                        // 含账号：PBKDF2-SHA256 60 万次 + AES-256-GCM

final plan = await backup.plan(json);                         // 只解析校验，可先给用户看报告
final report = await backup.apply(plan);                      // 一次事务写入，然后写密钥
await backup.restoreFile(file, mode: RestoreMode.follows);    // 仅恢复关注
```

- 识别格式看内容不看文件名：v4（`format: pure_live.backup`）、3.x 无版本扁平、v2、v3、仅关注（`backupScope: favorites`）、局域网包（`type: pure_live_sync` 的 version 1 / 2）。
- 先整体解析和校验成 `ImportPlan`，出错抛 `FormatException`（版本高于 4 抛 `BackupTooNewException`），什么都不写；同一时间只能有一个恢复（`StateError`）。
- 完整恢复：文件里有的分区整体替换本机数据，没有的分区不动。v4 的 settings 分区替换 `synced` 作用域（同一平台家族时再加 `device`）；3.x 只写文件里出现的键。仅关注恢复只替换关注和关注分区。
- 3.x 导入按 store.md §6.4 规范化：无效房间丢弃、按 RoomRef 去重（先出现的保留位置，后出现的补空字段）、虎牙 onlineViewers 转人气、标签以 `roomTagsMap` 为准（纯房间号键匹配导入的关注和历史，名称重复合并）、`roomVolumes` / `portraitRoomOverrides` 转房间偏好、Cookie 进密钥库、历史按文件里的上限截断。
- `ImportReport` 给出每类数据的读入、写入、丢弃数和原因（只含房间号、键名，不含密钥）。
- 口令错误或没给口令：其余部分照常导入，`report.secretsSkipped` 为真。PBKDF2 在另一个 isolate 里算（桌面 JIT 约 1.4 秒）。

## 分享口令

`ShareCode(ref, title: …).encode()` / `ShareCode.decode(text)`：与 3.x 互通的 base64url + MessagePack 格式（store.md §8）。

## 数据库结构和迁移

- 表定义在 `lib/src/database/tables.dart`，生成代码 `database.g.dart` 提交进仓库。
- 改结构：`schemaVersion` 加一，在 `migration.onUpgrade` 写这一步，然后在本目录运行

  ```sh
  dart run build_runner build
  dart run drift_dev make-migrations
  dart format .
  ```

  `drift_schemas/store/` 保存每个版本的结构，`test/drift/store/` 的测试检查新库与最新结构一致；有两个以上版本时 `make-migrations` 会生成逐版本迁移测试。

## 已知缺口

- 3.x Hive 数据的自动迁移（store.md §6）：需要旧应用的私有目录，`.next` 预览包读不到，也还没有 `hive_ce` 读取层。扁平的 3.x 键值格式已经由 `LegacyFormat` 处理（与 Hive 键同名），缺的是读 `.hive` 文件、来源发现、指纹账本、`siteCatalogMigration` 等计数器和“只补缺”的合并（§6.5）。
- `record_tasks`、`record_files`、`webdav_profiles` 表还没有；备份里对应的分区读到时写进报告并跳过（本机数据不变）。IPTV 在 schema 2（备份只含网址来源，iptv.md §7）；旧版 IPTV 库的只读导入还没做。
- 房间的 `extra`（IPTV 字段、公告、简介）导入时保存，但还不进 v4 备份。
- 设置注册表先覆盖预览版需要的约 60 项；其余 3.x 设置在导入报告里列为 `unknownKey`。
