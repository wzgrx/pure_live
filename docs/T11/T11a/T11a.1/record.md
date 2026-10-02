# T11a.1 IPTV 内核

- 日期：2026-10-01
- 目标包：`packages/live_iptv`（纯 Dart，依赖 `live_core`、`live_net`、`meta`、`path`，新增 `xml` 7.1.0）
- v3 来源：`lib/core/iptv/`（25 个文件，生成代码以外约 4700 行）、`lib/core/site/iptv/iptv_site.dart`，以及播放页里的纯逻辑 `modules/live_play/widgets/video_player/iptv_programme_policy.dart`（回看地址）
- 参考：归档 v4 的 `spec/modules/iptv.md` 和 `packages/live_iptv`。归档版把“频道”改成按名字合并、IPTV 不再算站点，和 v3 的界面不同，所以只借了 XMLTV 的拉取式解析写法和“存储由应用实现”的分层，行为照 v3。
- `docs/specs/UPGRADES.md` 里没有标 T11a.1 的条目，`~/ref/notes/m13_notes.md` 里也没有 T11a.1 待办。

## 做法

```text
IptvSite（live_core 的 LiveSite）──┐
IptvImporter（导入、同步、自动同步）─┼── IptvLibrary（存储接口；T09b.1 用 drift 实现，测试用 MemoryIptvLibrary）
解析：M3uParser、TxtParser、XmltvParser、JsonGuideParser
匹配：GuideIndex、rebuildMappings、resolveGuideChannel
身份：reconcileChannels        回看：buildIptvCatchupUrl 等
```

- **存储是接口**：v3 直接用 GetX 拿全局 drift 数据库。分层规定 `live_store` 只能依赖 `live_core`，所以本包定义 `IptvLibrary`（播放列表、频道、节目单源、节目单频道、节目、映射），由应用在 T09b.1 用 drift 实现；每次写入要么全部成功、要么不写，带 `expected` 的写入在已存的行变了时抛 `StaleIptvSnapshot`（对应 v3 事务里的“快照比对”）。
- **没有全局状态**：设置（当前节目单源、新列表是否自动同步）、网络（`LiveHttp`）、时钟、id 生成、GBK 解码都由构造函数注入。
- **结果用状态表示**：导入和同步返回 `IptvImportResult`（`imported`、`cancelled`、`unsupportedFormat`、`invalid`、`networkFailed`、`stale`、`failed`），提示文字由界面按状态给出；v3 在内核里直接弹 Toast 和确认框。“同名替换”确认改为回调 `IptvReplaceConfirm`。
- **导入串行**：所有导入、同步、删除排队执行（v3 的 `_importLock`）。

## 与 v3 的对照

| v3 文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `parsers/m3u_parser.dart` | 410 | `playlist/m3u_parser.dart` | 属性、`#EXTGRP`、请求头四层优先级、回看属性照 v3；坏段落只跳过自己（问题 1、2） |
| `parsers/txt_parser.dart` | 90 | `playlist/txt_parser.dart` | 行为不变（分组、`更新时间`/`提示` 不当分组、`#` 多源改名“(线路N)”、`p2p` 协议） |
| `parsers/playlist_parse_result.dart` | 12 | `playlist/playlist_parse_result.dart` | 错误带行号；新增 `truncated` |
| `parsers/xmltv_parser.dart` | 168 | `guide/guide_parser.dart` | DOM 改为拉取式解析（问题 9）；时区写法补全（问题 7） |
| `parsers/json_epg_parser.dart` | 189 | `guide/guide_parser.dart` | 字段别名照 v3；数字字符串时间修正（问题 6） |
| `services/iptv_import_manager.dart`、`iptv_sync_engine.dart` | 637 | `importer.dart` | 同名确认、保留本地副本、替换后删旧副本、映射重建照 v3 |
| `services/epg_import_manager.dart`、`epg_sync_engine.dart` | 462 | `importer.dart` | 同名合并、节目保留 2 天、Latin-1 声明照 v3；gzip 按内容识别（问题 8） |
| `services/auto_sync_scheduler.dart` | 92 | `importer.dart`（`syncExpired`、`loadHotPlaylist`、`loadDefaultGuide`） | 热门列表、默认节目单地址照 v3；同时调用共用一次（v3 的 `IptvResourceLoadGate`） |
| `services/playlist_channel_reconciler.dart` | 130 | `reconcile.dart` | 8 步唯一匹配、tvg-id 冲突不配、模糊时整体放弃，行为不变 |
| `iptv_import_manager.dart` 的 `_ImportEpgIndex`、`_rebuildEpgMappings` | — | `guide/matcher.dart`（`GuideIndex`、`rebuildMappings`） | 只认唯一答案，行为不变 |
| `site/iptv/iptv_site.dart` | 392 | `iptv_site.dart`、`guide/matcher.dart`（`resolveGuideChannel`） | 分类=播放列表、分区=频道、推荐=热门列表、单一“默认”画质照 v3（问题 5、10、11） |
| `core/fuzzy_match.dart` | 62 | `guide/matcher.dart`（`fuzzyScore`、`diceCoefficient`） | 只留房间匹配用到的部分；不再依赖 `string_similarity` |
| `local/epg_channel_identity.dart` | 5 | `model.dart`（`epgChannelKey`） | 逐字节相同，3.x 房间里存的 `epgId` 继续有效 |
| `local/tables.dart`、`database.dart`（+ 生成代码） | 9487 | `library.dart`（接口）+ T09b.1 | 见“留给其他模块” |
| `models/channel.dart`、`models/epg.dart` | 348 | `model.dart` | `IptvEntry`（解析结果，无 id）和 `IptvChannel`（带持久 id）分开 |
| `modules/live_play/.../iptv_programme_policy.dart` | 400 | `catchup.dart` | 节目阶段、可否回看、回看地址，行为不变 |

### 对外接口（M13 替换 v3 调用）

| v3 调用 | 替换为 |
|---|---|
| `IptvSite()` | `IptvSite(library:, importer:, selectedGuideSourceId:)` |
| `IptvImportManager().importFromLocalPicker()`、`importFromSharedMedia` | 界面选文件后 `importer.importPlaylistFile(file, confirmReplace: …)` |
| `importFromNetworkUrl(url, name)` | `importPlaylistFromUrl(url, name: name, confirmReplace: …)` |
| `importFromWebString(text, name)` | `importPlaylistText(text, name)` |
| `deleteProviderDurably(p)`、`IptvSyncEngine.syncPlaylist(p)` | `deletePlaylist(p)`、`syncPlaylist(p)` |
| `EpgImportManager` 的三种导入、`deleteSourceDurably`；`EpgSyncEngine.updateEpgCache` | `importGuideFile`、`importGuideFromUrl`、`importGuide`、`deleteGuide`；`syncGuide` |
| `AutoSyncScheduler.checkAndExecuteAutoSync()` | `syncExpired(hours: …)`（全局开关和“网络电视已启用”由调用方判断，同 v3） |
| `loadHotResources()`、`loadDefaultEpgResources()` | `loadHotPlaylist()`、`loadDefaultGuide()`（返回第一个节目单源，调用方在没选时选它） |
| `db.getAllProviders()`、`getAllEpgSources()`、`update…UpdateStatus` | `library.playlists()`、`guideSources()`、`updatePlaylist(p.copyWith(autoUpdate: …))` |
| `video_controller` 的 `resolveEpgChannelId` + `getProgrammes` | `resolveGuideReference(sourceId, room.epgId, …)` + `library.programmes(key, from:, to:)` |
| `classifyIptvProgramme`、`evaluateIptvCatchupAvailability`、`buildIptvCatchupUrl` | 同名函数 |

状态和 v3 提示的对应：`imported` → `sync_success` / `epg_import_success`；`unsupportedFormat` → `unsupported_file_format`；`networkFailed` → `download_failed`；`cancelled` 不提示；其余 → `sync_failed` / `epg_import_failed`。

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 列表里任何一行有问题（缺 `#EXTM3U`、一个不支持的地址、一条坏请求头），整个列表导入失败 | `services/iptv_import_manager.dart:227-229` | 用“有错误”代替“下载被截断”来保护已存的列表 | 坏段落跳过并记行号，其余照常导入（统一原则“容错”）；只有文件末尾停在半个段落（`#EXTINF` 后面没有地址）才判为截断，保留旧列表 |
| 2 | 地址后缀 `url|x=%zz` 这类坏的百分号编码让整个导入抛出未捕获的 `ArgumentError` | `parsers/m3u_parser.dart` 的 `_parseHeaderOptions` | `Uri.decodeQueryComponent` 抛的是 `ArgumentError`，代码只接 `FormatException` | 先检查编码，坏的只作废这一条 |
| 3 | 用户把列表命名为 `hot` 时，它变成内置热门列表：覆盖推荐，并从分类里消失 | `services/iptv_import_manager.dart:238`（`isHot \|\| providerName == 'hot'`） | 用名字识别内置列表 | 只有内置热门的导入（`isHot`）才写到热门 id `88888` |
| 4 | GBK 编码的网络列表：导入正常，同步后名字全变乱码而且显示同步成功 | `services/iptv_sync_engine.dart:31` | 同步用 `getText`（dio 按 UTF-8 容错解码），导入用字节加 GBK 回退，两条路不同 | 同步也取字节，和导入用同一个解码 |
| 5 | 房间页按名字找节目单：规范化后为空的名字（频道叫“高清”“频道”，或节目单名全是符号）会匹配任意节目单频道 | `site/iptv/iptv_site.dart` 的 `_resolveEpgChannelId` | `a.contains('')` 恒为真；导入时的索引排除了空名，这里没有 | 空名不参与 |
| 6 | JSON 节目单里写成字符串的 Unix 秒（`"1790000000"`）被读成公元 179000 年 | `parsers/json_epg_parser.dart` 的 `_parseDate` | 先 `DateTime.tryParse`，它把 10 位数字当“6 位年份+月+日” | 10 位、13 位数字先按 Unix 秒、毫秒读 |
| 7 | XMLTV 时间只认 `+0800`；`+08:00`、`Z` 的节目整条丢掉 | `parsers/xmltv_parser.dart` 的 `_parseXmltvDate` | 正则只写了 `[+-]\d{4}` | 支持 `±hh:mm`、`Z`，并检查月日时分范围 |
| 8 | 节目单只有地址以 `.gz` 结尾才解压；其它返回 gzip 的地址按 UTF-8 解码失败 | `services/epg_import_manager.dart` 的 `extensionForUrl`、`importEpgFile` | 按扩展名猜格式 | 按 gzip 魔数 `1f 8b` 解压；XMLTV / JSON 按内容判断 |
| 9 | 几十 MB 的 XMLTV 整份建成 DOM | `parsers/xmltv_parser.dart:11` | 用 `XmlDocument.parse` | 拉取式解析（借鉴归档 v4 `guide/xmltv.dart`）；坏的 XML 仍整体失败，旧数据不动（同 v3） |
| 10 | 找不到的房间号返回一个“直播中”的空房间，地址就是房间号，点开才失败 | `site/iptv/iptv_site.dart` 的 `getRoomDetail` | 用占位房间代替错误 | 房间号本身是流地址时照 v3 直接播放；其它抛 `NotFound`（v4 统一用 `SiteError` 报失败） |
| 11 | 房间头像是第三方图库带水印图片的外链 | `site/iptv/iptv_site.dart:25`（699pic） | — | 留空，M13 显示网络电视平台图标（见有意差异） |
| 12 | 同步后频道顺序不跟文件走：已有频道留在旧位置，新频道排到最后 | `local/database.dart:229` | 查询没有 `ORDER BY`，实际是 SQLite 的 rowid 顺序 | `IptvLibrary` 约定按文件顺序返回 |
| 13 | 本地导入的节目单存的是用户原文件路径（分享来的文件导入后就删掉了），之后“同步”去 HTTP 下载这个路径，必然失败 | `services/epg_sync_engine.dart:29` | 同步只走网络 | 本地来源同步时读文件，读不到报 `failed` |
| 14 | 死代码：`models/show.dart`（Trakt 剧集）、`UnifiedChannel`/`StreamSource`、`provider/provider.dart`、`storage/playlist_storage.dart`、`EpgAutoMapper`、`ChannelDetailController`（注册了但 `loadChannelEpg` 没人调）、`runAutoEpgMapping`，以及收藏夹、节目提醒、故障转移组、定时录制四组表（没有界面） | 各文件 | 从 clubTivi 搬来未清理 | 不移植；表的数据在 T09b.1 迁移时忽略 |
| 15 | 三套频道匹配：导入时只认唯一答案、房间页按名字取最像的、`ChannelDetailController` 又一套（死代码） | 见上 | — | 保留前两套（行为不变），删除第三套 |

## 保留的 v3 行为

- **格式识别**：网址导入 `#EXTM3U` 开头是 M3U，有 `,#genre#` 或地址以 `.txt` 结尾是 TXT，否则地址以 `.m3u`/`.m3u8` 结尾是 M3U，其它报“不支持的格式”；粘贴文本默认 M3U；同步时 M3U 必须以 `#EXTM3U` 开头、TXT 必须有逗号。
- **名字**：默认取地址或文件名最后一段，去掉所有扩展名；同名（不区分大小写）先确认再替换；同名有多个时按地址找唯一一个，找不到就失败。
- **频道身份**：同步保留频道 id（8 步唯一匹配），关注、房间、映射不断；频道的 `autoUpdate` 关闭时整条保留。
- **映射**：导入列表后按当前节目单源重建；锁定和手动的不动；没有频道或没有节目单频道时什么都不改。
- **房间匹配节目单**：已存映射 → tvg-id → 名字（取第一个词，去掉“综合、高清、超清、中央、电视台、频道、hd”，互相包含，同名优先，再按模糊分）。
- **房间内容**：标题是频道名；详情的主播名是 tvg-name 或频道名，分区房间和搜索的主播名是分组，推荐的主播名为空、简介是频道名；封面是台标；永远直播中；画质只有“默认”（`default`）；带回看四项和请求头。
- **节目单**：同名源合并为一个；导入后删掉结束早于 2 天前的节目；节目单下载带 v3 的桌面 Chrome UA。
- **自动同步**：间隔 2～72 小时（默认 24）；只同步网络来源、自己的自动同步打开、上次成功早于间隔的；新网络列表的自动同步开关跟随全局设置。
- **回看**：区间左闭右开；`playseek` 用本地时间 `yyyyMMddHHmmss`；模板的 `{Y}{m}{d}{H}{M}{S}` 用 UTC（同 Kodi iptvsimple）；Flussonic、Xtream Codes、vod、shift 规则不变；未知占位符报错不请求。
- **热门列表和默认节目单地址**：`iptv-org.github.io/iptv/countries/cn.m3u`、`epg.zsdc.eu.org/t.xml.gz`。

## 有意差异

| 差异 | 原因 |
|---|---|
| 坏行跳过而不是整表失败（问题 1） | `UPGRADES.md` 统一原则“容错：一行坏数据只跳过这一行”；截断仍保护旧数据 |
| 叫 `hot` 的用户列表不再变成热门（问题 3） | 修 bug，内置列表只认 id |
| 未知房间号报 `NotFound`（问题 10） | 平台层统一用 `SiteError` 报失败；房间号是地址的旧数据仍可播放 |
| 房间头像留空（问题 11） | 外链商业图库的带水印图片有版权问题；`LiveRoom` 约定拿不到真实信息时留空，界面用平台图标 |
| 列表接口第 2 页起返回空 | v3 每页都返回全部，界面只取第 1 页再本地分页；返回空避免别的调用方翻页时拿到重复内容 |
| 频道按文件顺序（问题 12） | 修 bug |
| 非 UTF-8 列表要注入解码器（`IptvLegacyDecoder`） | 纯 Dart 没有 GBK 解码；v3 用 Flutter 插件 `charset_converter`。没注入时这类列表报 `invalid` |
| 下载走 `live_net`，平台键 `iptv`，整次请求 2 分钟超时 | 按平台走代理规则；`live_net` 的超时管整个请求，几十 MB 的节目单 20 秒不够 |
| 节目单格式按内容判断，不看扩展名 | 地址常带查询串或不带扩展名（问题 8） |
| 节目单导入后的清理在保存之后单独执行 | v3 在同一事务里；清理失败只会多留旧节目，不影响新数据 |

## 留给其他模块

| 内容 | 去向 |
|---|---|
| `IptvLibrary` 的 drift 实现；3.x 的 `IPTV_CACHE/pure_live_tv/pure_live_tv.db`（schema 9）的读取和迁移（频道 id 原样保留，关注才不断）；设置 `selectedSourceId`/`selectedSourceName`、`isAutoSyncEnabled`、`autoSyncHoursInterval`、`customIptvUserAgent`、`m3uDirectory`；备份 | T09b.1 |
| 注册 `IptvSite`；注入 GBK 解码；启动 3 秒后自动同步（网络电视已启用且开关打开）；Android 分享导入 | T07a.1 |
| 网络电视页、管理页、导入对话框、同名确认、Toast；分区卡片点开直接进房间；节目单对话框和回看切换；切换节目单源后可调用映射重建（v3 没做，房间页按名字兜底） | M13 |
| 播放请求头：房间的 `httpHeaders` 加自定义 IPTV UA（v3 `playback_header_resolver`）；回看地址切换播放 | T04 |
| 录制用 `getRoomDetailForRecording`（与详情相同） | T08a.1 |

## 测试

42 个用例（加速流程，只覆盖主要路径和上面的问题）：

| 测试文件 | 内容 |
|---|---|
| `playlist_test.dart`（15） | 移植 v3 `m3u_parser_test` 的主要用例：属性读取、显示名、引号、`#EXTGRP`、BOM 和换行、回看属性、请求头优先级、`#EXTHTTP`/`#KODIPROP`；坏段落只跳过自己（问题 1、2）、截断判定；TXT；格式识别；GBK 只走注入的解码器 |
| `guide_test.dart`（8） | XMLTV（CDATA、实体、时区写法、坏节目跳过、坏 XML 失败）、gzip 魔数、Latin-1、JSON（问题 6）；导入索引、映射重建、房间匹配（问题 5）、Dice 系数 |
| `catchup_test.dart`（9） | 移植 v3 `iptv_programme_policy_test`：区间、三种无属性地址、模板、append 校正、shift、catch-up id、vod、Flussonic、Xtream Codes、禁用和未知模式、可否回看 |
| `reconcile_test.dart`（3） | 移植 v3 `iptv_import_manager_test` 的身份用例：换 token、改名、重排、去重、tvg-id 冲突、模糊时放弃、`autoUpdate` 关闭 |
| `import_test.dart`（7） | 网址导入→节目单导入→同步后映射→平台视图（分类、房间、画质、搜索、分页）；未知房间；本地副本、同名确认、删旧副本、同步、删除；截断/格式/网络失败保留旧列表；`hot` 名字（问题 3）和推荐；自动同步到期判断；节目单同名确认、坏 XML、清理 |
