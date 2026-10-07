# J01 设置

设置项、设置搜索、设置项核对。

管每一个设置“是什么”：键名、类型、默认值、取值范围、属于备份的哪个分区、坏值怎么修，存在哪里、谁在读它（生效位置），以及设置页目录里每一行改的是哪几个设置。设置页长什么样归 A11。

## 范围

- 包括：
  - 设置注册表 `packages/live_store/lib/src/settings/settings.dart`（`Settings`，218 个 `static const`，`Settings.all` 在 `:1413`）和设置类型 `setting.dart`、读写 `settings_store.dart`。
  - 应用里读设置的方式：`watchSetting`（`apps/pure_live/lib/app/services.dart:143`，界面只重建用到的行）、`store.settings.get/watch`（逻辑代码）、`writeSetting`（`features/settings/settings_tiles.dart:16`）。
  - 设置页的**目录和设置的对应**：`features/settings/settings_catalog.dart` 的每一行 `SettingsEntry.settings`（这一行改哪些设置，“已修改”计数和“恢复默认”都按它算）、各页“恢复默认”的设置清单（`portraitSettings`、`kernelSettings` 等，文件末尾）、搜索（`settings_model.dart` 的 `searchSettings`）的匹配规则。
  - 设置项逐条核对（J01.2）：默认值、范围、生效位置对照 3.x。
  - 启动时就要跟着设置跑的后台计时：定时退出 `AutoExitTimer`（`settings_editors.dart:767`）、定时刷新封面 `CoverRefreshTimer`（`data_tools.dart:87`），由 `app/startup.dart:74-75` 接上。
- 不包括（归哪里）：
  - 设置页的布局、行组件、对话框、搜索框和宽屏两栏 → [A11](../../A-界面设计/A11-设置界面/README.md)；设置里的弹幕页 → A08.5、A08.6；录制设置页 → A10.2；电视设置面板（复用 `settings_catalog.dart` 的选项）→ A17.9。
  - 设置生效后的行为：弹幕 → D05；播放、画质、硬解 → G；录制设置 → H03；刷新率 → R02；代理 → Q02；屏幕常亮、后台播放的权限 → O05、O04；网络电视 → L01。
  - 存储引擎（SQLite、事务、多窗口同步）→ J02；设置随备份导出和恢复 → J03；3.x Hive 里的设置怎么导进来 → J06（代码在 J02 的 `legacy/`）。

## 现状：做到哪、怎么工作的

- 用户看得到的：设置 → 五组 17 个入口（A11.1）；每页的行改的是注册表里的设置，改了立即写库、立即生效（滑块拖动时只改显示，松手 200 毫秒后写一次，`settings_tiles.dart:250`）；每页有改动时可以“恢复本页默认”；搜索按标题、说明、关键词、分组和页名匹配，多个词都要命中。
- 内部怎么工作：

```text
Settings.xxx（settings.dart，类型化常量：键 = 3.x 的 Hive 键，section/backupKey = 3.x 备份的分区和字段，defaultValue，min/max 或可选值）
  → SettingsStore（settings_store.dart）：LiveStore.open 时整表读进内存（:15-28），get 同步（:83）；
    set/setAll（:90、:93）先写 settings 表（JSON 值）再更新内存并发出变更；watch（:140）是“当前值 + 之后的变更”
  → 读：界面 watchSetting(ref, Settings.xxx)；逻辑 store.settings.get / watch(...).skip(1)
  → 坏值：Setting.read（setting.dart:59）= decode（类型不对返回 null）→ normalize（Int/Double 夹到 min/max，:113、:150）→ 否则 defaultValue；不抛错
  → 另一个桌面窗口写了库：LiveStore.syncExternal → SettingsStore.reload（:55）只报真正变了的设置
```

- 设置的来源：218 个里 **198 个沿用 3.x 的键名和含义**（D-018），**20 个是 v4 新加的**（清点第 15 节逐个列了来自哪个任务，例如 `matchVideoFrameRate` R02.1、`danmakuPausedBehavior` A07.10、`roomSwitcherLayout` A07.13）；10 个是 `SettingScope.internal`（本机记录：迁移计数、`remote_sync_device_id`、`themeColorMigration` 等，不进备份、不被“恢复默认”）。3.x 有、v4 不作为设置的 24 个键（Cookie、关注、历史、屏蔽、WebDAV、录制任务、迁移标记）在 `legacy/legacy_snapshot.dart` 里导到各自的存储（J06）。
- 生效位置（清点第 15 节“读取”，2026-10-03 重做）：210 个在设置页以外有读取的代码；4 个只在 `features/settings/` 里读，但读它的就是功能本身（`autoRefreshThumbnails`、`thumbnailRefreshInterval` → `CoverRefreshTimer`；`autoShutDownTime`、`enableAutoShutDownTime` → `AutoExitTimer`）；4 个没人读：`videoPlayerKey`（只为备份往返保留，播放内核切换不做）和 `autoRefreshTime`、`enableRotateScreen`、`m3uDirectory`（3.x 也不读）。上一版的 11 个“有设置不生效”都已由 O05.1、C02.1、O03.2、D05.1、A08.4 接上。
- 设置页目录：`settingsCatalog`（`settings_catalog.dart:321`）一共 129 行（`..toggle` 47、`..add` 49、`..slider` 18、`..link` 11、`..number` 3、`..choice` 2），分在 11 个目录页（`appearance :326`、`navigation :518`、`platforms :537`、`refresh :600`、`video :672`、`pipDanmaku :1085`、`playerKernel :1238`、`general :1341`、`network :1463`、`cache :1483`、`danmaku :1526`）；网络电视、录制、本地互动、备份、日志是别的路由（`SettingsSection` 的 `route:`，`settings_model.dart:35` 起）。
- 完成度：J01.1（2026-10-01，`9a90cbf6c`）把 3.x 的 23 个设置页全部迁进目录驱动的设置页，之后 A11.1～A11.5 按确认的设计重做了样子。确认过的改动：去掉播放内核切换（只有 mpv）；弹幕上下留白的范围 0～300 像素（照 3.x，J02.1 原来夹到 0～1）；文字缩放和五种字号加上 3.x 的范围；默认主题色从 3.x 的 `Colors.blue` 改成品牌蓝 `#2E6FE0`（A11.2 C-3，`LiveStore._upgradeThemeColor` 对 3.x 的默认蓝迁移一次，`live_store.dart:154-162`）。**默认值、范围没有逐条核对过**（J01.2）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_store/lib/src/settings/setting.dart`（214 行） | `SettingScope`（`synced` / `internal`，`:6`）；`Setting<T>`（`:22`：`key`、`section`、`backupKey`、`legacyKeys`、`defaultValue`、`scope`；`read` `:59`）；`BoolSetting`（`:72`）、`IntSetting`（`:86`，`min`/`max` 夹紧 `:113`）、`DoubleSetting`（`:121`）、`StringSetting`（`:158`，可带可选值，不在里面的回默认）、`StringListSetting`（`:182`）、`JsonSetting`（`:195`） |
| `packages/live_store/lib/src/settings/settings.dart`（1592 行） | 218 个设置；`brandThemeColor`；`recorder`（19 个录制设置）、`localInteraction`（29 个本地互动设置）两组展开进 `all`；`Settings.all`（`:1413`）；`byKey`（`:1591`，3.x 键 → 设置，迁移和 `adoptLegacyValues` 用） |
| `packages/live_store/lib/src/settings/settings_store.dart`（155 行） | `SettingsStore`：`load`（`:15`）、`reload`（`:55`）、`get`（`:83`）、`isSet`（`:86`，迁移时“库里已有的优先”靠它）、`set`/`setAll`（`:90`、`:93`）、`reset`（`:113`）、`resetAll`（`:120`，应用里没有调用）、`watch`（`:140`） |
| `apps/pure_live/lib/app/services.dart` | `watchSetting`（`:143`）：界面读设置并在变化时只重建这一处 |
| `apps/pure_live/lib/features/settings/settings_model.dart`（314 行） | `SettingsArea`（五组，`:10`）、`SettingsSection`（17 个入口，`:35`）、`SettingsSubpage`（`:145`）、`SettingsEnv`（平台、宽窄，`:170`）、`SettingsEntry`（`:212`，含 `settings` 列表）、`searchWords`/`searchSettings`（`:285`、`:291`）、`groupsOf`（`:302`） |
| `apps/pure_live/lib/features/settings/settings_catalog.dart`（1785 行） | 目录 `settingsCatalog`（`:321`）、`_Catalog` 的 `add`/`toggle`/`slider`/`number`/`choice`/`link`（`:96` 起）；各页“恢复默认”的设置清单（文件末尾，例如 `portraitSettings`、`kernelSettings`） |
| `apps/pure_live/lib/features/settings/settings_tiles.dart`（713 行） | `writeSetting`（`:16`）、`SettingRequirement`（依赖项变灰，`:22`）；绑定设置的行：开关 `:75`、滑块 `:132`（`:250` 停 200 毫秒再写）、选项 `:260`、数字 `:352`、计数 `:442`、跳转 `:517`、动作 `:585` |
| `apps/pure_live/lib/features/settings/playback_tiles.dart` | `RestoreDefaultsTile`（`:437`：确认后逐个 `reset`）、`switchGateProvider`（`:72`，后台播放等开关先过权限，O04） |
| `apps/pure_live/lib/features/settings/settings_editors.dart`（1045 行） | 播放器专家选项按平台过滤（`mpvOptionsFor` `:91`）、首选平台、代理地址、首页菜单、窗口大小、`AutoExitTimer`（`:767`） |
| `apps/pure_live/lib/features/settings/data_tools.dart`（592 行） | `CoverRefreshTimer`（`:87`）、图片缓存、下载目录（`DownloadResetTile` `:378`）、配置预览 `ConfigPreviewPage`（`:408`） |
| `apps/pure_live/lib/app/startup.dart` | 启动后 `AutoExitTimer.instance.attach`（`:74`）、`CoverRefreshTimer(...).start()`（`:75`） |
| 其余 `features/settings/` 文件 | 界面为主（`settings_page.dart`、`settings_section_view.dart`、`settings_dialogs.dart`、`appearance_pages.dart`、`audience_pages.dart`、`danmaku_page.dart`、`font_manager_page.dart`、`loading_style_names.dart`），代码地图在 [A11](../../A-界面设计/A11-设置界面/README.md) |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_store/test/stores_test.dart`（18 个，设置部分） | 默认值、夹紧、可选值、`watch` 的顺序 |
| `packages/live_store/test/theme_color_test.dart`（4） | 3.x 默认蓝迁移成品牌蓝一次；用户选过的颜色不动 |
| `packages/live_store/test/shared_store_test.dart`（6） | 两个连接共用一个库时设置和密钥的 `reload`（桌面多窗口） |
| `apps/pure_live/test/features/settings/settings_page_test.dart`（26） | 总览、分区、搜索、恢复本页默认、两栏、按平台出现的行、条目 id 唯一 |
| `.../settings_playback_test.dart`（20）、`settings_general_test.dart`（10）、`settings_data_test.dart`（7）、`settings_danmaku_test.dart`（6）、`refresh_rate_limited_test.dart`（2）、`match_frame_rate_test.dart`（1） | 各页的行写对了设置、依赖变灰、权限守门、刷新率提示、帧率匹配开关 |

## 3.x 基线

- 存储：一个 Hive box `app_settings`（`git show v3.2.11:lib/common/utils/hive_pref_util.dart`，`:41-44` 打开），每个控制器用 `hiveBool/hiveInt/hiveDouble/hiveString/hiveStringList('键', 默认值)`（`lib/common/services/utils/hive_rx.dart`）声明设置，`ever` 自动落盘；23 个控制器在 `lib/common/services/settings/`（例如 `app_settings_controller.dart:42-69`、`danmaku_settings_controller.dart:7-31` 的默认值常量、`theme_settings_controller.dart:8-23`）。
- 设置页：`lib/modules/settings/`（23 个文件约 7600 行），`settings_page.dart`（184 行）11 组入口，大多数一组一两行再进二级页；直播间的弹幕设置只能在直播间里改。
- 默认值：3.x 用 `hive*` 存的 172 个设置里 106 个默认值和 v4 字面相同、2 个写法不同意思一样（`roomVolumes`、`portraitRoomOverrides`：3.x 存 JSON 字符串 `'{}'`，v4 存映射）、64 个是常量或表达式（例如 `defaultDanmakuSpeed`、`PlayerConsts.resolutions.first`、`_initialRefreshRateMode()`，`app_settings_controller.dart:36-40`），要展开再比（J01.2）。
- 必须保留：键名和含义（D-018）；3.x 的备份分区和字段名（`section`、`backupKey`，3.x 读 v4 的备份、v4 读 3.x 的备份都靠它）；范围照 3.x（例如弹幕上下留白 0～300 像素、自动刷新间隔 5～360 分钟）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 64 个默认值是 3.x 的常量或表达式，没展开比；另 46 个（20 个新加、19 个录制、7 个常量键）没单独查；范围（`min`/`max`、可选值）和生效位置没逐条对 | `settings.dart` 全文；3.x `lib/common/services/settings/` | 某个默认值和 3.x 不同时，新用户（和没改过这个设置的老用户）的行为悄悄变了 | [J01.2](J01.2-设置项逐条核对/README.md) |
| `refreshRateMode` 的默认值：3.x 没存时由旧开关 `enableHighRefreshRate` 推出（`_initialRefreshRateMode`），v4 注册表写 `'powerSaving'`，旧开关的换算放在迁移里（`legacy_snapshot.dart:409-411`） | `settings.dart:64` | 只有从 3.x 迁过来的才走换算；从没装过 3.x 的新用户默认“省电”是否等于 3.x 新装的默认，要在 J01.2 核对 | J01.2 |
| `page_default_size` 3.x 默认随屏幕宽度（宽于 960 为 20，否则 12），v4 默认 0 表示“由界面按宽度决定” | `settings.dart:718`；`appearance_pages.dart:1009` `recommendedPageSizes` | 纯 Dart 包拿不到屏幕宽度（J02.1 有意差异）；导出备份时写 0，3.x 读回会按 0 处理 | J01.2 确认 3.x 读到 0 的行为；不对就开小任务 |
| 4 个设置没人读：`videoPlayerKey`、`autoRefreshTime`、`enableRotateScreen`、`m3uDirectory` | `settings.dart` | 后三个 3.x 也不读；`videoPlayerKey` 只为备份往返 | 不做（清点第 15 节） |
| `SettingsStore.resetAll` 没有调用方；`changed` 计数和“恢复本页默认”只看目录里登记了的设置 | `settings_store.dart:120`；`settings_catalog.dart` | 没登记进 `SettingsEntry.settings` 的设置（例如某些子页里改的）不计“已修改”、不随本页恢复 | J01.2 核对“生效位置”时顺带核对每个设置在目录里有没有登记 |
| 3.x 说明文字里还有偏技术的旧键（`audience_*_detail` 等）没删 | 翻译文件 | 不显示就没影响 | 不清理（D-024） |

## 相关决定和规范

- D-018（键名和含义不变，新设置只加不改）、D-001（3.x 是基线）、D-010（刷新率只用帧率声明）、D-024（翻译键不再清理）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“受限”（`showUnplayableInDiscover`）、“默认编码”和 22-3（`preferH264`）、2-1（`douyuForceRenew`）、8-3（`twitchLanguages`）、B-13（`youtubeShowAllChat`）。
- [inventory/FEATURES.md](../../inventory/FEATURES.md) 第 15 节（数量、读取、默认值）；[specs/UI.md](../../specs/UI.md) 第 3 节（设置页的界面原则，归 A11）。

## 测试和验证

- 自动测试：`cd packages/live_store && dart test`（设置、迁移、备份）；`cd apps/pure_live && flutter test test/features/settings/`。缺的：没有“每个设置的默认值等于 3.x”的表驱动测试（J01.2 要加）。
- 真机：设置本身不靠原生；各设置的生效在对应组的真机清单里看（[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1、2、5 节）。覆盖安装后 3.x 改过的设置还在，归 J06.1。

## 路线

1. **J01.2**（第二档）：脚本列出 218 个设置的 v4 默认值、范围和 3.x 对应值，展开 64 个常量，逐条标“一样 / 确认过的改动 / 不一样”；不一样的开修复任务或写进决定；加表驱动测试守住。
2. 以后新加设置：在注册表里加（写清默认值和范围、3.x 没有这个键）、在目录里登记（`SettingsEntry.settings`）、在清点第 15 节的“新加”名单里补一行。
3. 新想法（例如设置导入导出单页、按房间的设置）写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [J 设置和数据](../README.md)。

- 代码：`features/settings/`、`packages/live_store/lib/src/settings/`
- 进度：`██████████░░░░░░░░░░` 50%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| J01.1 | 设置 | 功能 | 完成 | 2026-10-01 | 9a90cbf6c | [记录](J01.1-设置/record.md) |
| J01.2 | 设置项逐条核对：218 个设置的默认值、取值范围和生效位置对照 3.x | 功能 | 未开始 | — | — | [设计或说明](J01.2-设置项逐条核对/README.md) |

## 还没完成的

- **J01.2 设置项逐条核对：218 个设置的默认值、取值范围和生效位置对照 3.x**（未开始，第二档，规模 中）
  - 说明：读取检查（功能清点第 15 节）2026-10-03 重做过，没人读的只剩 3.x 也不读的 3 个和不做的播放内核；剩下默认值：3.x 用 hive* 存的 172 个里 106 个字面值一样、2 个写法不同意思一样、64 个要展开 3.x 的常量或表达式，另 46 个（20 个 v4 新加、19 个录制、7 个常量键）要单独查（V03.3）

<!-- docs:生成结束 -->
