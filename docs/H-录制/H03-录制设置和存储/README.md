# H03 录制设置和存储

录制的 19 项设置（读写、迁移、默认值和范围）和录制文件放在哪：录制目录、`PureLiveRecords` 子文件夹、Android 的所有文件访问权限、缓存上限清理、打开录制文件夹、3.x 默认目录里的录像搬家。

## 范围

- 包括：`live_store` 的 `Settings.recordXxx`（19 项，`packages/live_store/lib/src/settings/settings.dart:907-1029`）；`live_record` 的 `RecordSettings`（`packages/live_record/lib/src/settings.dart`，录制器每次决定时读）和 `RecordStorage`（`storage.dart`）；应用的 `RecordSettingsStore`、`defaultRecordDirectory`、`legacyRecordDirectory`、`moveLegacyRecordings`（`apps/pure_live/lib/app/recording.dart:91-355`）；`features/record_settings/` 的逻辑（目录选择和可写校验、整数输入的范围、清空前确认的大小）；`androidStorageAccess` 和 `RecorderPlugin.requestStorage`；`openRecordFolder`（`features/recorder/recorder_page.dart:55`）。
- 不包括（归哪里）：录制设置页的布局和文字在 A10.2；设置注册表、备份格式、3.x 设置导入的机制在 J01、J02、J03（这里只管录制那一段）；开播检测、重试几项设置的“行为”在 H01、H04（这里只管存和读）。

## 现状：做到哪、怎么工作的

- 用户看得到的：设置 → 录制设置（或录制中心标题栏的齿轮、`RoutePath.kRecordSettings`），五组：基础配置（默认录制清晰度五档、拼音文件夹名、同时录制弹幕）、录制文件（录制文件目录、限制占用空间、上限、当前大小、清空）、录制性能与画质（只录主画面和主音轨、读写超时三档、输入缓冲五档、切片时长、最大同时录制任务数 − / +）、自动重连（开关、最大重试次数、重连间隔）、开播检测（开关、间隔、退避、最大间隔、启动时恢复）。单位写成“15 秒”“5 分钟”“3.5 GB”；“改上限”从直播间或录制中心打开时滚到“最大同时录制任务数”并高亮两秒。目录行打开系统目录选择器，写不进去就说明；Android 选公共目录前先说明，再打开“所有文件访问”页。
- 内部怎么走：设置存在 `live_store`（键名就是 3.x 的 Hive 键，`segmentTime`、`maxTaskCount`、`default_quality`……），`RecordSettingsStore.of`（`recording.dart:261-281`）把它们组成 `RecordSettings`，录制器每次决定都同步读；`changes` 只在录制那 19 个键变时发（恢复备份、恢复默认也算），`AppRecording` 转给 `Recorder.settingsChanged()`。目录：用户选的只是父目录，实际写进它下面带标记文件 `.pure_live_recording_root` 的 `PureLiveRecords/`（`storage.dart:11-60`）；空 = 默认目录（Android 是应用外部存储下的 `Records`，不要权限，`recording.dart:91-99`）；正在录的目录受保护，缓存上限清理（每分钟查一次，开了才查）和“清空”都不删它（`storage.dart:92-186`）。
- 迁移：3.x 的值由 J02.1 导入；H02.1 期间存在 `meta['recorder.settings']` 的 v4 值和 J02.1 停放在 `legacy_values` 的 3.x 值，由 `RecordSettingsStore.load()` 和 `LegacyMigration.adoptLegacyValues` 各采纳一次（v4 的优先）。3.x 默认目录 `<文档>/PURE_LIVE/RECORDS`（应用私有）里已完成的录像，启动时一次搬到 4.x 的默认目录，未完成的尝试（分段、日志、`.partial`）留在原地给导入的任务恢复（`moveLegacyRecordings`，`recording.dart:123`）。
- 备份：19 项进 v4 备份的 `recorder` 分区（3.x 读到会忽略），录制目录 `recordSavePath` 是本机路径，标 `internal` 不进备份。
- 完成度：3.x 的 19 项设置、默认值、范围都在；确认过的改动：默认目录不再写死（H02.1 问题 5）、滑块松手才保存、单位写成中文（A10.2）、最大任务数直接在行上加减（A10.2 c9）、设置进备份（H01.2）；还缺：无。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_store/lib/src/settings/settings.dart:907-1029` | 19 个 `Settings.recordXxx`：键名、分区 `recorder`、默认值、范围（例如 `segmentTime` 300、60～3600；`max_retry_count` 5、1～20；`enable_polling` 关；`recordSavePath` 是 `internal`） |
| `packages/live_record/lib/src/settings.dart`（109 行） | `RecordSettings`：同样的默认值和范围（构造时规整，3.x `normalizeStoredValues`）；读写超时只认 15/30/60，输入缓冲只认 512～8192 五档；`recordQualityPreferences` 五档 |
| `packages/live_record/lib/src/storage.dart`（186） | `RecordStorage`：`PureLiveRecords` 和标记文件、Android 私有目录不能选、`prepare`（证明可写）、`protect`/`release`、`sizeMB`、`enforceLimit`（删最旧的未保护文件）、`clearAll` |
| `apps/pure_live/lib/app/recording.dart:91-205` | `defaultRecordDirectory`、`legacyRecordDirectory`、`legacyRecordingsMovedKey`、`moveLegacyRecordings`（3.x 默认目录的录像搬家，只一次，重名加 `-1`） |
| `apps/pure_live/lib/app/recording.dart:212-355` | `RecordSettingsStore`：`current`、`changes`、`load()`（一次性迁移）、`of`、`fromValues`（3.x 宽松的类型）、`set` |
| `features/record_settings/record_settings_page.dart`（626） | 录制设置页的五组和每一行的读写；“改上限”参数 `recordSettingsMaxTasks` 时定位并高亮 |
| `features/record_settings/record_settings_dialogs.dart`（347） | `recordDirectoryPickerProvider`（系统目录选择器，`platform/plugins.dart` 装上）、单选框、整数输入框（上限）、清空确认、目录输入框（没有选择器时） |
| `features/record_settings/record_settings_texts.dart`（60） | 单位文字（秒、分钟、小时、GB）和每个值的含义 |
| `apps/pure_live/lib/platform/recording_platform.dart:322-345` | `androidStorageAccess`：可写就通过；用户操作时先说明再申请；自动恢复时不弹 |
| `android/.../RecorderPlugin.kt:173-215` | `requestStorage`：API 30+ 打开本应用的“所有文件访问”页（不行就开总页），API 26～29 申请存储权限，返回后再查 |
| `features/recorder/recorder_page.dart:15-80` | `openRecordFolder`：桌面打开文件管理器；Android 公共目录发 DocumentsUI 的文件夹意图（`android_intent_plus`），应用专属目录和 `Android/data` 复制路径并提示 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/record_settings/record_settings_page_test.dart`（12） | 单位和含义文字；五组和每一行；3.x 存的值照样显示；最大任务数 − / +；“改上限”定位和高亮；单选框；上限输入的校验；清空确认；系统目录选择器和写不进去的说明；没有选择器时输入路径；横屏和宽屏 720 宽 |
| `apps/pure_live/test/features/recorder/recorder_page_test.dart`（5） | 录制设置读 3.x 的键（类型宽松、超范围规整）、v4 值优先、Android 文件夹地址 |
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart` 的 “3.x's default folder” | 3.x 默认目录的录像搬家（只一次、子文件夹保留、未完成的尝试留下） |
| `packages/live_store/test/` 的备份测试 | `recorder` 分区进备份、目录不进、3.x 停放值只采纳一次 |
| `packages/live_record/test/task_test.dart` 的 “settings clamp” | `RecordSettings` 规整超范围的值 |

## 3.x 基线

- `git show v3.2.11:lib/recorder/consts/recorder_config.dart`（297 行，默认值；`:39` 开播检测默认关）、`recorder_keys.dart`（61 行，19 个 Hive 键）。
- `lib/recorder/pages/record_settings/record_settings_page.dart`（622 行，`:10` 起）、`record_settings_controller.dart`（348 行；`:339-347` 第一次进设置就把默认目录写进 `recordSavePath`）。
- `lib/recorder/services/cache_service.dart:19`（`PureLiveRecords`、标记文件、在用目录不清理）、`path_helper.dart`（安全文件名、拼音）。
- `lib/recorder/pages/recorder/recorder_controller.dart:665`（存储权限）、`:1599-1601`（打开文件夹）。
- 3.x 的录制设置不进备份；3.x 默认目录是应用私有的 `<文档>/PURE_LIVE/RECORDS`。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 默认目录在 `Android/data` 下，Android 11 起系统文件管理进不去 | `recording.dart:91-99`、`recorder_page.dart:15-80` | “打开文件夹”只能复制路径，要在别的应用里看录像得换到公共目录 | 不做（换目录要所有文件访问权限，默认不申请；提示里说明怎么换） |
| 所有文件访问权限页没在真机走过 | `RecorderPlugin.kt:173-215` | 不知道 HyperOS 返回后能不能正确判断 | [H01.4](../H01-录制核心/H01.4-录制余项/README.md) |
| 默认值和范围写在两处（`live_store` 的 `Settings.recordXxx` 和 `live_record` 的 `RecordSettings`） | 两个 `settings.dart` | 改一处忘了另一处会不一致 | 改录制设置时两处一起改，测试 `task_test.dart` 的规整用例 |
| Windows 上 3.x 导入的 `recordSavePath` 可能指向 3.x 安装目录 | H02.1 记录 | 会在 3.x 目录里建 `PureLiveRecords` | X 组（D-004） |

## 相关决定和规范

- D-018：3.x 的设置键名和含义不变，新设置只加不改（19 个键沿用 Hive 键）。
- D-006、D-019：覆盖安装 3.x 后设置照旧生效；验证时只操作测试包。
- 界面：[A10.2 录制设置](../../A-界面设计/A10-录制界面/A10.2-录制设置/README.md)。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/record_settings test/features/recorder`；`packages/live_store` 的 `dart test`（备份和迁移）。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节第 6 条（换到 `Download/`、所有文件访问、打开文件夹），归 H01.4。

## 路线

本子分类没有登记的任务。所有文件访问的真机验证在 H01.4；以后要改的（例如按大小分段、默认目录改到公共目录）先在 [V01](../../V-需求和反馈/V01-新功能提议/README.md) 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [H 录制](../README.md)。

- 代码：`features/record_settings/`、`app/recording.dart`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
