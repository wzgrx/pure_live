# L01 网络电视

订阅源管理、导入、播放。

用户自己的电视直播源：导入播放列表（网络地址、本地文件、粘贴文本、分享过来的文件）、同步和自动同步、删除，频道在同步后保持身份不变，并作为“网络电视”平台出现在分区、推荐、搜索、关注和直播间里。节目单和回看的规则在 L02；管理页的样子在 A13.1。

## 范围

- 包括：
  - `packages/live_iptv` 的播放列表部分：`playlist/`（M3U、TXT 解析，格式识别）、`text.dart`（UTF-8 和注入的 GBK 解码）、`importer.dart`（导入、同步、删除、同名确认、本地副本、热门列表、自动同步，`IptvImporter`）、`reconcile.dart`（同步时保留频道 id）、`model.dart`（`IptvPlaylist`、`IptvChannel`、`IptvEntry`）、`library.dart`（存储接口 `IptvLibrary` 和内存版）、`iptv_site.dart`（`IptvSite`：分类 = 播放列表、分区 = 频道、推荐 = 热门列表、画质只有“默认”）。
  - 应用一侧：`app/iptv_library.dart`（`StoreIptvLibrary`，6 张 `iptv_` 表放在 `pure_live.db`）、`app/iptv_legacy.dart`（3.x `pure_live_tv.db` 的只读迁移）、`app/bootstrap.dart`（建 `IptvImporter` 和 `IptvSite` `:161-185`、启动 3 秒后自动同步 `:261`）、`app/intake/share_intake.dart`（分享来的列表和节目单 `:200-223`）、`features/iptv/` 的逻辑（`iptv_data.dart` 的 provider 和结果文字、`iptv_page.dart` 里调用导入器的流程）。
  - 网络电视的设置：`selectedSourceId`、`selectedSourceName`、`isAutoSyncEnabled`、`autoSyncHoursInterval`、`customIptvUserAgent`、`m3uDirectory`（键名照 3.x）。
- 不包括（归哪里）：
  - 管理页、导入对话框、卡片的样子 → [A13.1](../../A-界面设计/A13-网络电视和多画面界面/A13.1-网络电视管理/README.md)；电视端的网络电视界面 → A17.5。
  - 节目单（导入、匹配、清理）和回看 → L02。
  - 频道在直播间里怎么播（线路、请求头加自定义 UA 在 `room_controller.dart:521-536`、局域网权限）→ C01、G、O04；备份里的网络电视列表 → J03；3.x 库的迁移结果核对 → J06.1。

## 现状：做到哪、怎么工作的

- 用户看得到的（设置 → 网络电视，或首页分区的“网络电视”）：一页里从上到下是概览（播放列表数、频道总数、节目单数和导入按钮）→ 播放列表 → 节目单 → 同步与播放设置。导入方式：网络地址、本地文件（系统选择器）、粘贴文本；名称可留空（取文件名）；同名先问要不要替换；失败按原因说（格式不对、下载失败、内容被截断、跳过了几行）。网络来源能单个同步、全部同步（带进度）、开关自动同步；删除先确认（写明多少频道、关注里的会播不了）。网络电视不在平台列表里时页面顶部提醒，一键启用。别的应用分享 m3u 文件过来时直接导入并提示。频道在分区页按播放列表分类，搜索能搜到频道名，关注后和其他平台一样刷新（永远“直播中”）。
- 内部怎么工作：

```text
导入（iptv_page.dart:200-212 / share_intake.dart:210-217）
  IptvImporter.importPlaylistFromUrl / importPlaylistFile / importPlaylistText（importer.dart:279、:338、:316）
   → 全部排队执行（_serial :163，同 3.x 的 _importLock）
   → 下载走 LiveHttp（平台键 iptv，整次 2 分钟超时 :103）→ 字节 → decodePlaylistBytes（text.dart:13，UTF-8 失败用注入的 GBK 解码）
   → detectPlaylistFormat（playlist_parser.dart:16）→ M3uParser / TxtParser：坏段落跳过并记行号；只有最后停在半个段落才算截断（:193，保留旧列表）
   → 同名（不分大小写）→ confirmReplace 回调；替换时 reconcileChannels（reconcile.dart:26，8 步唯一匹配保留频道 id，模糊时整体放弃）
   → library.savePlaylist（一个事务；带 expected 的写入在库里的行变了时抛 StaleIptvSnapshot）→ 本地列表复制一份到应用的 iptv 目录
   → 有选中的节目单时 rebuildMappings（importer.dart:252）重建这个列表的映射
同步：syncPlaylist（:366）同一条路径；syncExpired（:578）只同步网络来源、自己开着自动同步、上次成功早于间隔的
启动：bootstrap.dart:261 _iptvAutoSync：3 秒后，网络电视在平台列表里且总开关开着才同步
平台：IptvSite（iptv_site.dart:22）读 library：getCategories（:48）、getCategoryRooms（:72）、getRecommendRooms（:81，热门列表 id 88888）、
  searchRooms（:92）、getRoomDetail（:104，房间号就是流地址时照 3.x 直接播，其他找不到的抛 NotFound）、画质只有 default（:39）
存储：StoreIptvLibrary（iptv_library.dart:64）：第一次用时 CREATE TABLE IF NOT EXISTS，版本记 meta[iptv.schemaVersion]=1（:69-72）；
  大批量用 drift batch（每批 500，:75）；写入后发表变更通知（IptvTables.all :34），管理页订阅它刷新（iptv_data.dart:19）
```

- 完成度：L01.1（内核，`414fe49a6`）、L01.2（持久化和 3.x 库迁移，`27385a999`）、L01.3（页面，`abf627e86`）、A13.1（按设计重做页面，`7c6d685cb`）；O03.1 接上系统文件选择器和“打开文件”，O03.2 接上分享导入；C01.2 让直播间用上自定义 UA（F-IPTV-05）。清点 F-IPTV-01～05 “完成”；**没有 K90 结果**（CHECKLIST 第 1 节第 17 条 → S02.6 第 2 阶段）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_iptv/lib/src/model.dart`（509 行） | `IptvStreamType`（`:9`）、`IptvEntry`（`:26`，解析结果，没有 id）、`IptvChannel`（`:107`，带持久 id、回看四项、请求头）、`IptvPlaylistFormat`（`:160`）、`IptvPlaylist`（`:191`，`isHot`、`autoUpdate`、本地 / 网络）、`EpgSource`（`:275`）、`epgChannelKey`（`:335`，和 3.x 逐字节相同）、`EpgMapping`（`:446`）、`isHttpUrl`（`:494`） |
| `packages/live_iptv/lib/src/playlist/`（m3u 389、txt 54、parser 22、result 40 行） | `M3uParser`（`m3u_parser.dart:26`：属性、`#EXTGRP`、请求头四层优先级、`#EXTHTTP`/`#KODIPROP`、回看属性；坏的百分号编码只作废这一条）、`TxtParser`（`txt_parser.dart:14`：分组行、`#` 多源改名“(线路N)”）、`parsePlaylist` / `detectPlaylistFormat`（`playlist_parser.dart:7`、`:16`）、`PlaylistParseResult`（`truncated`、带行号的 `issues`） |
| `packages/live_iptv/lib/src/text.dart`（44 行） | `IptvLegacyDecoder`（`:9`）、`decodePlaylistBytes`（`:13`）、`decodeGuideBytes`（`:27`） |
| `packages/live_iptv/lib/src/importer.dart`（645 行） | `IptvImportResult`（`:45`，状态 `imported`/`cancelled`/`unsupportedFormat`/`invalid`/`networkFailed`/`stale`/`failed`）、`IptvImporter`（`:86`：常量 `:100-129`〔热门列表地址、默认节目单地址、节目保留 2 天、自动同步 2～72 小时默认 24〕、`_serial` `:163`、`importPlaylist` `:174`、`importPlaylistFromUrl` `:279`、`importPlaylistText` `:316`、`importPlaylistFile` `:338`、`syncPlaylist` `:366`、`deletePlaylist` `:404`、`loadHotPlaylist` `:412`、`syncExpired` `:578`；节目单部分见 L02） |
| `packages/live_iptv/lib/src/reconcile.dart`（109 行） | `AmbiguousChannelIdentity`（`:7`）、`reconcileChannels`（`:26`：8 步唯一匹配、tvg-id 冲突不配、`autoUpdate` 关的整条保留） |
| `packages/live_iptv/lib/src/library.dart`（247 行） | `StaleIptvSnapshot`（`:6`）、`IptvLibrary` 接口（`:22`）、`MemoryIptvLibrary`（`:98`，测试和没有库时用） |
| `packages/live_iptv/lib/src/iptv_site.dart`（188 行） | `IptvSite`（`:22`），见上面的流程；`getRoomDetailForRecording`（`:118`，录制用） |
| `apps/pure_live/lib/app/iptv_library.dart` | `IptvTables`（`:14`）、`StoreIptvLibrary`（`:64`：`_write` `:95`、各查询 `:108` 起、`savePlaylist` `:141`、`updatePlaylist` `:196`）；搜索用 `instr(lower(name), lower(?))`（`%`、`_` 不当通配符） |
| `apps/pure_live/lib/app/iptv_legacy.dart` | 3.x 库的位置（`:16`）、报告（`:28`）、`LegacyIptvMigration`（`:104`，复制到临时目录再开，账本 `legacy.iptvImportedSources`） |
| `apps/pure_live/lib/app/intake/share_intake.dart` | 分享来的列表和节目单按扩展名分开导入（`:200-223`），同名确认、结果提示 |
| `apps/pure_live/lib/features/iptv/iptv_data.dart`（161 行） | `iptvImporterProvider`（`:10`）、`iptvClockProvider`（`:15`）、`iptvOverviewProvider`（`:19`，订阅 `IptvTables.all`）、`IptvOverview`（`:35`）、格式标记和显示名（`:85-115`）、导入结果到提示文字 |
| `apps/pure_live/lib/features/iptv/iptv_page.dart`（730 行）、`iptv_import.dart`（539）、`iptv_cards.dart`（670）、`iptv_settings.dart`（115） | 界面为主（A13.1）；逻辑相关：第一次进入自动导入默认节目单一次（`meta` 的 `iptv.defaultGuideLoaded`）、删除正在用的节目单改用下一个（`:70-100`）、全部同步包括关了自动同步的来源 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_iptv/test/playlist_test.dart`（15） | M3U 属性、显示名、引号、`#EXTGRP`、BOM、回看属性、请求头优先级、坏段落只跳过自己、截断判定；TXT；格式识别；GBK 只走注入的解码器 |
| `packages/live_iptv/test/import_test.dart`（7） | 导入 → 节目单 → 同步后映射 → 平台视图（分类、房间、画质、搜索、分页）；未知房间；本地副本、同名确认、删旧副本、同步、删除；截断、格式、网络失败保留旧列表；`hot` 名字；自动同步到期判断 |
| `packages/live_iptv/test/reconcile_test.dart`（3） | 换 token、改名、重排、去重、tvg-id 冲突、模糊时放弃、`autoUpdate` 关闭 |
| `apps/pure_live/test/iptv_store_test.dart`（2） | 写入后重开读回；3.x 样例库只读导入一次 |
| `apps/pure_live/test/features/iptv/iptv_page_test.dart`（15） | 一页的顺序、宽屏、更多菜单、默认节目单只导入一次、导入对话框、网络导入和同名确认、粘贴和本地导入、同步和全部同步、切换和删除节目单、设置、加载和失败、窄屏大字 |

## 3.x 基线

- `git show v3.2.11:lib/core/iptv/`（25 个文件，生成代码以外约 4700 行）：`parsers/m3u_parser.dart`、`txt_parser.dart`；`services/iptv_import_manager.dart`（539 行：坏一行整表失败 `:227-229`、名字叫 `hot` 就变成热门 `:238`）、`iptv_sync_engine.dart`（同步用 UTF-8 容错解码 `:31`，GBK 列表同步后乱码）、`auto_sync_scheduler.dart`（启动 3 秒后自动同步）、`playlist_channel_reconciler.dart`；`local/database.dart`（drift schema 9，`IPTV_CACHE/pure_live_tv/pure_live_tv.db` `:42`；查询没有 `ORDER BY` `:229`）。
- `lib/core/site/iptv/iptv_site.dart`（392 行）：分类、分区、推荐、搜索；找不到的房间号返回一个“直播中”的空房间。
- 页面：`lib/modules/iptv/iptv_page.dart`（943 行，“IPTV 设置”）、`iptv_manage.dart`（902 行，“订阅源管理”）。
- 必须保留：格式识别规则、名字取地址最后一段、同名先确认、频道 id 跨同步不变、节目单同名合并、自动同步 2～72 小时、热门列表和默认节目单地址（`iptv-org.github.io/iptv/countries/cn.m3u`、`epg.zsdc.eu.org/t.xml.gz`）、设置键名。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 网络电视整条路径没在 K90 上走过（导入、播放、分享 m3u、打开本地文件） | — | 真机的文件选择器、局域网源、GBK 列表都没实测 | [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 2 阶段（CHECKLIST 第 1 节第 17 条）、S02.4（分享 m3u） |
| 3.x 网络电视库的迁移没用真实数据跑过 | `app/iptv_legacy.dart` | 用户覆盖安装后列表可能不全 | [J06.1](../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md) |
| 非 UTF-8 的列表要注入解码器：Android（原生 `Charset`）、Windows（代码页 936）有（`platform/platform_services.dart:14` 的 `platformGbkDecoder`，`bootstrap.dart:167` 注入），其他平台没有时这类列表报“格式不对” | `text.dart:13` | 只影响以后的平台 | 做 X 组的客户端时补 |
| 列表接口第 2 页起返回空（3.x 每页都返回全部） | `iptv_site.dart:72`、`:81` | 只影响会翻页的调用方；界面只取第 1 页本地分页 | 有意差异（L01.1） |
| 3.x 的 Xtream 账号（`providers` 的 `username`/`password`）不迁移 | `iptv_legacy.dart` | 3.x 也没有界面用它 | 不做 |
| 管理页的“更多”菜单还是 Flutter 的 `showMenu` | `iptv_cards.dart` | 和全应用的小菜单样子不一致 | A13 的已知问题 |

## 相关决定和规范

- D-018（网络电视设置键不变）、D-017（测试不访问真实服务）、D-019；UPGRADES 统一原则“容错”（坏行只跳过这一行）。
- L01.1 的有意差异：坏行跳过、`hot` 名字不再变热门、未知房间号报 `NotFound`、房间头像留空（3.x 外链的图库图片有水印和版权问题）、频道按文件顺序。

## 测试和验证

- 自动测试：`cd packages/live_iptv && dart test`；`cd apps/pure_live && flutter test test/iptv_store_test.dart test/features/iptv/`。
- 真机：CHECKLIST 第 1 节第 17 条（导入 m3u、播放频道、节目单、回看、返回直播）、第 11 条（分享 m3u 文件）；局域网源顺带看 O04.1 的本地网络权限。

## 路线

1. 真机：S02.6 第 2 阶段、S02.4、J06.1（都是已登记的验证任务）。
2. 读代码看到的小问题按真机结果再定（见 L02：切换节目单后不重建映射）。
3. 电视端 A17.5（第三档）开工时，`IptvSite` 和管理逻辑直接复用。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [L 网络电视和点播](../README.md)。

- 代码：`packages/live_iptv`、`features/iptv/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| L01.1 | 网络电视内核 | 功能 | 完成 | 2026-10-01 | 414fe49a6 | [设计或说明](L01.1-网络电视内核/README.md)、[记录](L01.1-网络电视内核/record.md) |
| L01.2 | 网络电视列表持久化 | 功能 | 完成 | 2026-10-01 | 27385a999 | [设计或说明](L01.2-网络电视列表持久化/README.md)、[记录](L01.2-网络电视列表持久化/record.md) |
| L01.3 | 网络电视页面 | 功能 | 完成 | 2026-10-01 | abf627e86 | [设计或说明](L01.3-网络电视页面/README.md)、[记录](L01.3-网络电视页面/record.md) |

<!-- docs:生成结束 -->
