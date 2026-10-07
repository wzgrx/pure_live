# L02 节目单和回看

节目单、回看。

网络电视的节目单（XMLTV、JSON，网络或本地导入、同步、两天的保留期）、频道和节目单的对应（映射和兜底匹配），以及在直播间里看节目单、点已经播完的节目回看、回到直播。节目单面板的样子归 A07.7，导入节目单的入口在 L01 的管理页。

## 范围

- 包括：
  - `packages/live_iptv/lib/src/guide/guide_parser.dart`（`parseGuide`、`GuideFormat` 按内容识别 XMLTV / JSON、拉取式 XMLTV 解析、时区写法、gzip 魔数）。
  - `packages/live_iptv/lib/src/guide/matcher.dart`（`GuideIndex`、`rebuildMappings` 导入列表时只认唯一答案；`resolveGuideChannel` 房间页兜底：已存映射 → tvg-id → 名字；`resolveGuideReference`；模糊分和 Dice 系数）。
  - `packages/live_iptv/lib/src/importer.dart` 的节目单部分：`importGuide`（`:423`）、`importGuideFromUrl`（`:493`）、`importGuideFile`（`:517`）、`syncGuide`（`:543`）、`deleteGuide`（`:560`）、`loadDefaultGuide`（`:565`）、导入后清掉两天前结束的节目（`pruneProgrammes`，`programmeRetention` `:120`）。
  - `packages/live_iptv/lib/src/catchup.dart`：节目阶段 `classifyIptvProgramme`（`:45`）、能不能回看 `evaluateIptvCatchupAvailability`（`:68`）、回看地址 `buildIptvCatchupUrl`（`:109`；append、shift、timeshift、playseek、offset、flussonic、Xtream Codes、vod、模板占位符）。
  - 直播间：`apps/pure_live/lib/features/live_play/dialogs/iptv_guide.dart`（`loadChannelGuide` 读节目、`IptvGuideScope` 决定节目单在哪个位置展开）、`logic/iptv_guide_rows.dart`（按天分组、滚到正在播、回看说明文字）、`logic/room_controller.dart` 的 `playCatchup`（`:642`）和 `backToLive`（`:705`）。
- 不包括（归哪里）：
  - 节目单面板、回看条、节目行的样子和三种布局里的位置 → A07.7（`iptv_guide.dart` 的界面部分）；管理页里的节目单卡片、“当前使用的节目单” → A13.1。
  - 播放列表的导入和频道身份 → L01；回看地址交给播放器以后的事（线路、点播模式、请求头）→ G、C01。
  - 3.x 网络电视库里的节目单源和节目的迁移 → L01.2、J06.1。

## 现状：做到哪、怎么工作的

- 用户看得到的：网络电视管理页导入节目单（网络、本地、默认节目单 `epg.zsdc.eu.org/t.xml.gz`），选一个作为“当前使用的节目单”。进一个网络电视频道：竖屏时节目单在画面下面、横屏全屏时从右侧打开（画面上的节目单按钮）、宽屏在右栏；按天分组，打开时滚到正在播的节目；已经播完、频道支持回看的节目可以点，点了播回看（画面上有回看标记和“回到直播”）；还没开始的节目点了提示“节目还没开始”；频道不支持回看时节目单顶部写“不支持回看”，支持时写“可回看 N 天”。
- 内部怎么工作：

```text
导入节目单：IptvImporter.importGuide*（importer.dart:423-560）
  下载（桌面 Chrome UA，整次 2 分钟）→ decodeGuideBytes（gzip 魔数 1f 8b 就解压；Latin-1 声明照 3.x）→ parseGuide（guide_parser.dart:45，按内容判断格式）
  → 同名源合并（确认替换）→ library.saveGuide → pruneProgrammes（结束早于 2 天前的删掉）
映射：导入或同步播放列表时 rebuildMappings（matcher.dart，用“当前使用的节目单”；只认唯一答案；锁定和手动的不动）
房间：IptvSite.getRoomDetail 时 resolveGuideChannel（matcher.dart:97）：已存映射 → tvg-id → 名字（第一个词，去掉“综合、高清、超清、中央、电视台、频道、hd”:148，
  互相包含、同名优先、再按模糊分）→ room.epgId（epgChannelKey）
直播间：loadChannelGuide（iptv_guide.dart:19）= resolveGuideReference(选中的源, room.epgId) → library.programmes(key, from, to) → 按开始时间排序
  → guideEntries（iptv_guide_rows.dart:59，按天）→ 面板；guideCatchupNote（:139）
回看：playCatchup（room_controller.dart:642）
  classifyIptvProgramme：没开始 → 'program_scheduled_hint'；正在播 → backToLive；已结束 →
  evaluateIptvCatchupAvailability（频道的 mode、source、days）不行 → 'catchup_unavailable'
  → buildIptvCatchupUrl(原地址, 开始, 结束, CatchupUrlType.playseek, mode, source, correctionHours)（地址写错 → 'invalid_play_url'）
  → 局域网地址先申请本地网络权限 → session.open(PlaybackPlan…onDemand: true)
backToLive（:705）：清掉回看状态，重新开直播流
```

- 完成度：规则在 L01.1（`414fe49a6`）移植 3.x 并修了节目单的 4 个问题（JSON 字符串时间戳、XMLTV 时区、gzip 识别、整份 DOM）；直播间的节目单和回看在 C01.2 接上、A07.7 按设计重做（三种布局里的位置、滚到正在播、回看标记）。清点里没有单独的节目单功能点，并在 F-IPTV-02（导入节目单）和 F-RT-10、F-RT-11（直播间的节目单和回看）里；**没有 K90 结果**（CHECKLIST 第 1 节第 17 条 → S02.6 第 2 阶段）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_iptv/lib/src/guide/guide_parser.dart`（286 行） | `ParsedGuide`（`:10`）、`GuideFormat`（`:27`，`detect`）、`parseGuide`（`:45`）；XMLTV 拉取式解析（CDATA、实体、`±hh:mm`、`Z`，坏节目跳过、坏 XML 整体失败）、JSON 字段别名和 10 / 13 位数字时间 |
| `packages/live_iptv/lib/src/guide/matcher.dart`（201 行） | `GuideIndex`（`:14`）、`rebuildMappings`、`resolveGuideChannel`（`:97`，空名不参与）、`resolveGuideReference`（`:137`）、`_roomSuffix`（`:148`）、`fuzzyScore`（`:156`）、`diceCoefficient`（`:181`） |
| `packages/live_iptv/lib/src/catchup.dart`（342 行） | `IptvProgrammePhase`（`:6`）、`CatchupUrlType`（`:18`）、`IptvCatchupAvailability`（`:30`）、`classifyIptvProgramme`（`:45`，区间左闭右开）、内置模式（`:51-64`）、`evaluateIptvCatchupAvailability`（`:68`）、`buildIptvCatchupUrl`（`:109`）、模板展开（`:171`，`{Y}{m}{d}{H}{M}{S}` 用 UTC，同 Kodi iptvsimple；`playseek` 用本地时间）、Flussonic（`:230`）、Xtream Codes（`:255`） |
| `packages/live_iptv/lib/src/importer.dart` | 节目单的导入、同步、删除、默认节目单（见“范围”的行号）；`guideUserAgent`（`:116`） |
| `packages/live_iptv/lib/src/model.dart` | `EpgSource`（`:275`）、`epgChannelKey`（`:335`）、`EpgChannel`（`:359`）、`EpgProgramme`（`:381`）、`EpgMapping`（`:446`） |
| `apps/pure_live/lib/features/live_play/dialogs/iptv_guide.dart`（568 行） | `loadChannelGuide`（`:19`）、`IptvGuideScope`（`:40`）、`showIptvGuide`（`:57`）、`IptvGuideView`（`:78`）；其余是界面（A07.7） |
| `apps/pure_live/lib/features/live_play/logic/iptv_guide_rows.dart`（161 行） | `GuideDay`、`GuideProgramme`（`:29`、`:38`）、`guideEntries`（`:59`）、`guideAnchorOffset`（`:108`）、`guideDayLabel`（`:121`）、`guideCatchupNote`（`:139`）、`guideTime`（`:157`） |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart` | `catchup`（`:242`）、`playCatchup`（`:642`）、`backToLive`（`:705`）；进房时清回看状态（`:365`） |
| `apps/pure_live/lib/features/live_play/live_play_page.dart`、`player/player_controls.dart` | `IptvGuideScope` 放在页面上（`live_play_page.dart:714`）；画面上的节目单按钮（`player_controls.dart:391`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_iptv/test/guide_test.dart`（8） | XMLTV（CDATA、实体、时区写法、坏节目跳过、坏 XML 失败）、gzip 魔数、Latin-1、JSON 字符串时间；导入索引、映射重建、房间匹配（空名不参与）、Dice 系数 |
| `packages/live_iptv/test/catchup_test.dart`（9） | 移植 3.x `iptv_programme_policy_test`：区间、三种无属性地址、模板、append 校正、shift、catch-up id、vod、Flussonic、Xtream Codes、禁用和未知模式、可否回看 |
| `apps/pure_live/test/features/live_play/live_play_more_test.dart` | 网络电视：自定义 UA 在列表请求头之下；播完的节目能回看、回到直播（`:149`）；局域网地址先申请本地网络权限（`:197`） |
| `apps/pure_live/test/features/live_play/live_play_states_test.dart` | 天的标签、回看说明、时间（`:401`）；竖屏节目单在画面下（`:539`）；全屏从右侧打开、Esc 先关它（`:564`）；按天分组、正在播的标记、还没开始的提示（`:640`） |

## 3.x 基线

- `git show v3.2.11:lib/core/iptv/parsers/xmltv_parser.dart`（168 行，DOM、只认 `+0800`）、`json_epg_parser.dart`（189 行）；`services/epg_import_manager.dart`（348 行，按扩展名判断 gzip）、`epg_sync_engine.dart`（114 行，本地来源同步也去 HTTP 下载 `:29`）、`epg_auto_mapper.dart`（死代码）。
- 房间匹配：`lib/core/site/iptv/iptv_site.dart:147-160`（`_resolveEpgChannelId`，空名会匹配任意频道）。
- 直播间：`lib/modules/live_play/widgets/video_player/iptv_programme_policy.dart`（400 行，回看规则）、`iptv_schedule_dialog.dart`（455 行）、`video_controller.dart:1007`（`loadFullChannelSchedule`）、`:1083-1179`（选节目、回看用 `CatchupUrlType.playseek` `:1143`、`returnToLive` `:1179`）。
- 必须保留：节目阶段的区间规则、回看地址的各种写法（和 Kodi iptvsimple 一致）、同名节目单源合并、两天保留期、`epgChannelKey` 的格式（3.x 房间里存的 `epgId` 继续有效）、房间匹配的顺序。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 节目单和回看没在 K90 上看过 | — | 真实的节目单源、回看服务器、三种布局里的面板都没实测 | [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 2 阶段（CHECKLIST 第 1 节第 17 条） |
| 切换“当前使用的节目单”、导入或同步节目单后，不重建频道到节目单的映射（只在导入、同步播放列表时重建） | `importer.dart:252`（只在播放列表路径）；`features/iptv/iptv_page.dart:70-100`（切换只改设置） | 直播间靠 `resolveGuideChannel` 的 tvg-id 和名字兜底，多数情况能找到；名字模糊的频道可能对不上 | 3.x 也没做（L01.1、L01.3 记录）；建议在 `IptvImporter` 加 `rebuildGuideMappings()`（在导入队列里执行），切换和节目单同步后调用；没有任务，S02.6 发现对不上时再开 |
| 回看只按 `CatchupUrlType.playseek` 生成没有模板的地址 | `room_controller.dart:667` | 只认 `timeshift` 或 `offset` 写法的源回看失败（模板和 append 类不受影响） | 同 3.x（`video_controller.dart:1143`）；有反馈再加选择 |
| 节目单只保留 2 天、只读当前使用的那个源 | `importer.dart:120`；`iptv_guide.dart:19-31` | 回看窗口长于 2 天的频道，更早的节目在节目单里看不到 | 同 3.x |
| 完整备份不带节目（只带节目单源） | `shared/backup/backup_iptv.dart` | 恢复后要同步一次才有节目 | 照设计（J03） |

## 相关决定和规范

- D-017（测试不访问真实服务；用到样本时间的固定“现在”）、D-019。
- A07.7 的设计（节目单在三种布局里的位置、回看标记）；UPGRADES 统一原则“容错”（坏节目只跳过这一条）。

## 测试和验证

- 自动测试：`cd packages/live_iptv && dart test test/guide_test.dart test/catchup_test.dart`；`cd apps/pure_live && flutter test test/features/live_play/live_play_more_test.dart test/features/live_play/live_play_states_test.dart`。
- 真机：CHECKLIST 第 1 节第 17 条：导入带回看属性的 m3u 和节目单，进频道，节目单滚到正在播，点一个播完的节目回看，再回到直播；局域网的回看服务器顺带看本地网络权限（O04.1）。

## 路线

1. S02.6 第 2 阶段：真机走一遍；对不上节目单的频道记下来。
2. 视结果开小任务：切换节目单后重建映射（`rebuildGuideMappings`）。
3. 电视端 A17.5（第三档）复用同一套节目单和回看逻辑。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [L 网络电视和点播](../README.md)。

- 代码：`packages/live_iptv`
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
