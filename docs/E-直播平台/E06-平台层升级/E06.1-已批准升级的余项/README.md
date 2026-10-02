# E06.1 已批准升级里还没做的（原 M13.18 收尾）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 档位：可以以后；规模：大
- 功能点：不是 v3 功能（[specs/UPGRADES.md](../../../specs/UPGRADES.md) 的余项）（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：多处，见下
- 依赖：F.0～F.4 的“必须”完成后
- 来源：scratchpad `rest/m13_18_closing.md`（没开始）、M13.17 任务说明第 7 项
- 评审页：发评审页（条目多，逐条表态）
- 记录：[records/F.5a.md](../../../TASKS.md)（开发后）；第 2、4 条：[records/F.5a1.md](record-2.md)

## 要做的（逐条核对代码后再定范围）

1. 回填 `docs/specs/UPGRADES.md` 状态列（约 60 条还写着“余下 M13”或“待做”）。
2. 平台和直播间：A-3 快手详情标题、A-6、B-7 Twitch Cookie 失效提示、B-16 酷狗 PK 对方聊天、11-1 Picarto 恢复时取最好一档、1-1 登录后播放哔哩哔哩轮播、B-14 名字颜色和徽章、8-8 Twitch 按引擎能力请求 HEVC/AV1。
3. 列表：卡片显示开播时间和简介（7-9、10-3、11-5、25-12、33-7）；1-1 轮播和封禁在历史卡片上的标识；搜索翻页共用快照（19-1、24-5、26-1）。
4. `live_core` 收尾（G01.1 留下）：YouTube 和 PandaTV 主列表读法合并、FC2 画质探测交出控制连接、哔哩哔哩轮播从 `play_time` 开始、LiveMe 和 TikTok 租期是否断开。
5. 数据：备份带上网络电视列表、搜索历史、多画面会话（恢复 3.x 备份照旧）；投屏给电视的标题改成“主播 - 标题”（N02.1 记录说要先问用户）。
6. 文字整理：`*_directory_scope` 目录说明、`audience_*_detail` 改通俗；清理不再引用的旧键；工具箱和账号页的 `i18n('site_$id')` 换成 `platformName`。

WebDAV Digest 已拆到 J04.1。

## 第 2 条：平台和直播间（平台层、弹幕层）

按授权直接开发：都是 UPGRADES 已批准的条目；只改 `live_core`、`live_danmaku`，界面上要显示的只给数据和接口，界面部分写进记录交回。两处选择按 A 做。

### v3 的行为（`~/ref/v3ref/lib`，v3.2.11）

| 条目 | v3 | 位置 |
|---|---|---|
| A-3 | 快手详情的标题是主播简介（换行变空格），进房后卡片上的直播标题被简介盖掉 | `core/site/kuaishou/kuaishou_site.dart:292`、`:469` |
| A-6 | 网易 CC 未开播主播进房是“状态未知”、刷新抛 RangeError；百度预告房间报“接口变了” | E02.2 问题 3、E02.11（v4 已改为未开播） |
| B-7 | Twitch 弹幕用失效的令牌一直重连；播放令牌被拒后整个实例不再用 Cookie，不提示 | `core/danmaku/twitch_danmaku.dart:76-88`；`core/site/twitch/twitch_site.dart:38`、`:146` |
| B-16 | 酷狗没有弹幕（`EmptyDanmaku`） | `core/site/kugoulive/kugou_live_site.dart:42` |
| 11-1 | Picarto 恢复时按旧画质 id 找，主播换了档位就一直失败 | `core/site/picarto/picarto_site.dart:117` |
| 1-1 | 哔哩哔哩轮播（`live_status` 2）当未开播，不能播 | `core/site/bilibili/bilibili_site.dart:700-711` |
| B-14 | 17LIVE 没有弹幕（`EmptyDanmaku`） | `core/site/seventeenlive/seventeenlive_site.dart:38` |
| 8-8 | Twitch usher 不带 `supported_codecs`（只有 H.264） | `core/site/twitch/twitch_site.dart:560-577` |

### v4 现在和根因

| 编号 | 现状和根因 |
|---|---|
| P1（A-3） | `KuaishouApi.roomDetail` 仍把简介写进 `title`（`kuaishou_api.dart:261`）；进房 `fillFromDetail` 不补标题（`live_room.dart:650-658`），定时刷新和关注刷新用 `mergeFrom`，非空的简介会盖掉卡片标题 |
| P2（A-6） | 已经是新做法（CC `S05`、百度 `S02-room-preview` 都是未开播，有测试），只差确认 |
| P3（B-7） | 弹幕层已在登录被拒时提示一次（D01 后续升级（原 M5.F））；平台层播放令牌被拒时 `_accessToken` 只记下 `_rejectedSession` 改匿名（`twitch_site.dart:549-565`），没有任何出口告诉界面 |
| P4（B-16） | `LiveMessage` 没有来源字段，`KugouLiveDanmakuProtocol.decode` 不读 400305（`kugoulive.dart:176`、`:420-444`） |
| P5（11-1） | 平台层恢复时已改播最好一档，只给出 id（`appliedQualityData`）；新档不在播放器手上的列表里，`resolveAppliedPlayQuality` 只能把旧名称标“未确认”（`live_site.dart:183-195`） |
| P6（1-1） | 取流不挡轮播，但游客的 `getRoomPlayInfo` 对轮播不给地址（`bilibili_api.dart:351-366`），平台层没有轮播视频的取法 |
| P7（B-14） | 17LIVE 评论的 `name.textColor` 和各种徽章没有读，`LiveMessage` 也没有这两个字段（`seventeenlive.dart:702-735`） |
| P8（8-8） | 关掉“优先 H.264”时一律请求 `av1,h265,h264`（`twitch_api.dart:355`），不管引擎能不能解 |

### 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | 快手详情不再把简介当标题（`title` 留空，简介仍在 `introduction`、`notice`）；`fillFromDetail` 在详情没有标题时用进房前卡片的标题；`mergeFrom` 本来就不让空标题盖掉存下的标题 | P1 |
| c2 | 保留 | 未开播显示为未开播（CC、百度），引用已有测试，不改代码 | P2 |
| c3 | 补上 | 新接口 `LiveSiteCookieRefusals`（`cookieRefusals` 流）：Twitch 播放令牌拒绝存下的 Cookie 时，每份 Cookie 报一次，界面据此提示一次 | P3 |
| c4 | 补上 | `LiveMessage.sourceRoomId`（说话的房间不是本房间时填）；酷狗 400305 在 `source.tags & 1` 时作为聊天上报，带对方房间号 | P4 |
| c5 | 增强 | `LivePlayUrlResolution.appliedQuality`：平台换了档时给出那一档（名称、id）；`resolveAppliedPlayQuality` 用它，不再标“未确认”；Picarto 恢复和列表卡片取流换档时填 | P5 |
| c6 | 补上 | 哔哩哔哩轮播：`getRoomPlayInfo` 给了地址（登录后）照常播；不给时取 `getRoundPlayVideo` 的视频，经 `x/player/playurl`（html5 MP4）给一条线路；画质只有一档“轮播” | P6 |
| c7 | 补上 | `LiveMessage.nameColor`、`LiveMessage.badges`（`LiveBadge`：图片地址和平台的徽章编号）；17LIVE 填 `name.textColor` 和评论的徽章图片 | P7 |
| c8 | 增强 | `TwitchSite(codecs:)`：引擎能解的视频编码（`avc`、`hevc`、`av1`）；关掉“优先 H.264”时只请求其中能解的（H.264 一直在），不给时照旧三种都要 | P8 |

### 需要选的

| 编号 | A（建议，按 A 做） | B |
|---|---|---|
| 1 快手从链接进房（没有卡片标题） | 标题为空，简介照旧在房间信息里 | 仍用简介当标题（要界面另做回退） |
| 2 游客看哔哩哔哩轮播 | 游客也能看（轮播视频最高 480P，登录后 `getRoomPlayInfo` 给地址就用它的） | 只有登录后 `getRoomPlayInfo` 给地址时能看 |

## 第 4 条：`live_core` 收尾（G01.1 留下）

| 编号 | v4 现在（根因） | 改动 |
|---|---|---|
| P9 / c9 合并 | YouTube（`youtube_api.dart:1191-1240`）和 PandaTV（`pandalive_api.dart:1017-1105`）各写了一遍 `#EXT-X-STREAM-INF` 的读法，属性解析也是两套 | `hls_master.dart` 加共用的宽松读法 `HlsStreamInf.read` 和 `HlsStreamInf.attributes`（严格、宽松两种），两个平台改用它；各自的规则（YouTube 整体拒绝、PandaTV 只丢坏的那一档）不变。唯一的行为差别：PandaTV 的 `STREAM-INF` 和地址之间夹了别的标签时不再丢掉这一档（同 YouTube） |
| P10 / c10 补上 | FC2 画质探测开了控制连接，读完就关（`fc2live_site.dart:431-439`），播放再开一条；`live_media` 的 `Fc2RecipeOpener.adopt` 已能接手，平台层没有交出的出口 | `Fc2LiveSite(probeControl:)`：给了就把探测的控制连接交给它（它负责关），没给照旧关掉。控制连接里有全部档位的地址（`Fc2LiveApi.playlistFor`），接手的一方可以播任何一档 |
| P11 / c11 补上 | `PlaybackPlan.start` 已能从指定位置开始（G01.1），但平台层不给起点 | `LivePlayUrlResolution.start`：c6 的轮播视频从 `play_time` 秒开始；播完按直播流结束处理，恢复时再取当时在轮播的那一个 |
| P12 / c12 保留 | 租期是否切断连接 | LiveMe 已在 E06 平台层升级（21-8）实测：过期不断流，线路不带租期；TikTok 的 `expire` 是签发后约 14 天，只预取、不切断（`tiktok_api.dart:667-675`）。都不改，用已有测试确认 |

## 测试和验证（第 2、4 条）

- 单元测试：每条 c 至少一个（`live_core`、`live_danmaku`），用仓库里的样本（快手 S09、酷狗 `S09-pk-chat`、17LIVE `S06-live`、`live_vod/V09-playurl-mp4`、Picarto、YouTube、PandaTV 的样本）和合成回答；`getRoundPlayVideo` 没有录过样本，按 E01.1 记录的字段写合成回答。
- K90：这些都要界面接上后才看得到（见记录“交给界面”）：快手从推荐卡片进房显示卡片标题；哔哩哔哩找一个轮播房间进房能播放并从中途开始；酷狗 PK 时对方的聊天带“对方”；海外的（Twitch、Picarto、17LIVE）有代理时再看。

## 风险和性能（第 2、4 条）

- 不加常驻任务和定时器；`LiveMessage` 多三个字段（默认值共用常量）。
- 3.x 的数据和设置不变：新字段都不存盘；没有新设置。
- 轮播视频多两个请求（`getRoundPlayVideo`、`playurl`），只在游客进轮播房间时发生。
- FC2 交出的控制连接由接手的一方关闭；没接上时照旧关掉，不会多开连接。

## 第 1、3、5、6 条的功能对比（2026-10-02）

按授权直接开发（v3 没有的部分都是已批准的升级或记录里的“留给后续”；要选的按 A 做）。投屏标题（第 5 条后半）协调员 2026-10-02 授权按“主播名 - 标题”做。

### 第 1 条：回填 UPGRADES 状态列

- v3：无（文档）。
- v4 现在：约 75 行写着“余下 M13”“待做”“部分完成”，其中多数已在 M13.x、U.x、F.x 做完。
- P1：M13 各页面和界面任务做完后没有回头改状态列（M13.18 收尾没开）。
- c1（修复）：逐行照代码和 `docs/TASKS.md`、`docs/TASKS.md`、`docs/TASKS.md` 核对；做了的写“完成（位置）”，没做的写去向（E06.1 其他条、F.x、受阻、不做）。本任务做掉的条目一起改。
- 测试：无（文档）。

### 第 3 条：列表

| v3 的行为 | 位置 |
|---|---|
| 卡片信息区只有标题和主播名；房间没有开播时间字段 | `lib/common/widgets/room_card.dart:1172-1221` |
| 观看历史用同一张卡片；v3 没有轮播、封禁状态 | `lib/modules/history/history_page.dart:219` |
| SHOWROOM 目录 30 秒内共用一份快照；搜索第 1 页新搜，之后 `_currentPage + 1` | `lib/core/site/showroom/showroom_site.dart:52`、`lib/modules/search/search_controller.dart:220-227` |

v4 现在：
- `AudiencePolicy.cardOf(room, now:)` 有 `now` 时把“已播 N”接在主播名后（`shared/rooms/room_cards.dart:82`）。只有关注页传了 `now`（`features/favorite/favorite_page.dart:448`、`:531`）；推荐和分区房间（`shared/rooms/room_grid.dart:601`）、搜索（`features/search/search_view.dart:587`）、观看历史（`features/history/history_page.dart:440-442`）都没传。
- 简介：`LiveRoom.introduction` 有值，但 A09.1 卡片信息区只有标题、主播名两行，长按对话框也去掉了简介（A09.1 记录“和设计不一样的地方”第 1 条）。
- 历史卡片走 `cardOf` → `roomMark`（`shared/rooms/room_texts.dart:129`），轮播、已封禁、平台已下线已标在封面左下（A09.9 换卡片时带上的），没有测试。
- 搜索：新搜索请求第 1 页、翻页 `_page + 1`（`features/search/search_model.dart:286`、`:298`），经 `searchRoomsWithCancellation` 到平台的 `searchRoomsCancellable`：SHOWROOM、FC2 第 1 页取新快照，之后的页在 30 / 20 秒内共用（`showroom_site.dart:246-251`、`fc2live_site.dart:265-270`）；BIGO 搜索一直用目录那份（`bigo_site.dart:328`）。所以搜索翻页已经共用快照，I03.1 写“余下搜索页”时没有核对，也没有测试。

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 推荐、分区房间、搜索的卡片不显示开播时间（7-9、10-3、25-12、33-7） | `RoomGridCard` 只在调用方传 `now` 时显示，I02.1、I03.1、A09.7 没传 |
| P2 | 卡片不显示简介（11-5） | A09.1 设计的信息区只有两行，没有简介的位置 |
| P3 | 历史卡片的轮播 / 封禁标识、搜索翻页共用快照都已做到，但没有测试，UPGRADES 仍写“余下” | 做的任务没有专门核对这几条 |

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 增强 | `RoomGridCard` 没传 `now` 时取共用时钟（`roomClockProvider`，测试可换）：推荐、分区房间、搜索的直播中卡片在主播名后显示“已播 N”，和关注页同一个位置、同一种写法；不加定时器，随页面重建更新 | P1 |
| c2 | 保留 | 简介不上卡片（照 A09.1 信息位，不硬加），写进记录；要显示得先改 A09.1 设计 | P2 |
| c3 | 保留 | 历史卡片的轮播、已封禁标识，补测试 | P3 |
| c4 | 保留 | 搜索翻页共用快照，补测试（真的 SHOWROOM 适配器 + 假网络：第 1 页取一次，翻页不再取，再搜一次取新的） | P3 |

需要选的：A1（建议）观看历史卡片不显示“已播”（历史是上次看时的快照，刷新前时间会过时）；B 也显示。

测试和 K90：c1 推荐页和搜索的卡片显示“已播 12 分钟”、没开播或没开播时间的不显示；c3、c4 如上。K90：推荐页 AcFun 卡片主播名后有“已播”；搜索 AcFun 关键词同样；观看记录里一个哔哩哔哩轮播房间标“轮播”。

风险：没有新的常驻任务；时间只在页面重建时更新（同关注页）；主播名很长时“已播”会被省略号挤掉（同关注页）。

### 第 5 条：数据

| v3 的行为 | 位置 |
|---|---|
| 完整备份的分区：`favorite`、`history`、`iptv`（只有网络电视的设置）、`tags`、`webdav`、`cookie`；没有网络电视列表；v3 没有搜索记录和多画面会话 | `lib/common/services/settings/backup_controller.dart:56-90` |
| 恢复按分区名逐个解析，不认识的分区不管 | 同文件 `:185-196` |
| 投屏只给地址，电视上的标题就是地址 | `lib/modules/live_play/dialogs/live_dlna_dialog.dart:56-57` |

v4 现在：
- `exportBackup` 在 `BackupService.exportAll` 的结果上加了 `search` 分区（搜索记录，J03.1，`shared/backup/backup_data.dart:28-44`），本地备份和 WebDAV 都走它。
- 网络电视列表在 `iptv_*` 表（L01.2，`app/iptv_library.dart`），多画面上次的会话在 `meta` 的 `multiview.session`（`features/multiview/logic/multiview_controller.dart:170`、`:354`），都不在备份里（L01.2、N01.1 记录“留给后续”）。
- 投屏：`DlnaCastController` 只调 `setSource(地址)`（`packages/live_cast/lib/src/controller.dart:346`），`DlnaRenderer.setSource` 建的 `CastMedia` 没有标题（`renderer.dart:191`），元数据标题回退成地址（`renderer.dart:44`）。

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 换设备或重装后网络电视列表要重新导入 | 备份只写 `BackupService` 的分区和搜索记录，IPTV 库是 L01.2 后加的 |
| P2 | 多画面“上次看的直播间”恢复不了 | 同上，N01.1 留给后续 |
| P3 | 电视上显示一串地址 | N02.1 没接标题（当时要先问用户） |

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 增强 | 完整备份加 `iptvLibrary` 分区：播放列表（不含内置的“hot”）连同频道（保留频道 id，关注的电视频道仍对得上）和节目单对应关系；节目单源只存名字和地址。恢复时文件里有这个分区就把播放列表换成文件里的（同 id 覆盖、文件里没有的删掉、内置的不动），节目单源只补上没有的（节目内容下次同步再取）；3.x 的备份没有这个分区，不动。分区名不用 `iptv`（3.x 的网络电视设置在那里）。预览多一行“网络电视列表” | P1 |
| c2 | 增强 | 完整备份加 `multiview` 分区（上次的布局、省流、弹幕开关和各格房间）；恢复时替换，3.x 的备份不动；预览多一行“多画面” | P2 |
| c3 | 保留 | 搜索记录照旧（J03.1），本条只核对 | — |
| c4 | 修复 | 投屏标题“主播名 - 直播间标题”（主播名为空只写标题，都为空照旧用地址）。`live_cast` 加可选接口 `CastMediaTarget`（`setMedia`），`DlnaRenderer` 实现；控制器有标题时用它；直播间的投屏传房间的主播名和标题 | P3 |

需要选的：
- A1（建议）播放列表恢复时整份替换（同关注、历史）；B 只补上没有的。
- A2（建议）带上频道（恢复后不联网就能看，关注的频道对得上；几千个频道的列表约多 1 MB）；B 只带地址，恢复后要同步。
- A3（建议）节目单源只带地址，节目内容不进备份（量大，重新同步即可）；B 连节目一起带。

测试和 K90：单元测试覆盖导出、预览、恢复、3.x 备份不动、内置列表不动、投屏标题拼法和控制器发出的元数据。K90：完整备份 → 删一个播放列表、关掉多画面 → 恢复，列表和“恢复上次”回来；投屏到电视看标题（要用户的电视，TASKS 第 5 节投屏条目）。

风险：备份文件随频道数变大；3.x 读 v4 的文件时忽略新分区；设备同步和同步到电视走 `BackupService`（不在本任务目录），不带这三样，写进记录。

### 第 6 条：文字整理

| v3 的行为 | 位置 |
|---|---|
| 目录说明、人数口径说明是开发说明式的原文（“原生会话分页”“cvExposure”“view_num”） | `assets/translations/zh.json:1590`（`audience_bilibili_detail`）、`:1843`（`showroom_directory_scope`）等 |

v4 现在：
- 分区房间页顶部说明读 `*_directory_scope`（`features/area_rooms/area_rooms_page.dart:96`），推荐页没有改写的平台也读（`features/popular/popular_grid.dart:17`）；设置“各平台口径说明”读 `audience_<id>_detail`（`features/settings/audience_pages.dart:196`）。推荐页的 `popular_scope_*` A09.2 已改通俗。
- 账号页 `i18n(nameKey ?? 'site_$id')`（`features/account/account_platforms.dart:71`）、工具箱支持平台列表 `i18nOr('site_${site.id}', site.name)`（`shared/links/supported_platforms.dart:61`）没走 `platformName`（I01.2 统一的入口）。
- 翻译文件中英各约 830 个键代码里已经没人用（3.x 的旧页面、Firebase、v4 改版前的文字，如 I 记录的 `shield_tab_*`、`shield_clear*`、`version_history_desc`、`about_installed_version`、`version_file_size`）。

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 说明是开发笔记，部分已经不准（14-6 映客“部分在播间暂无公开播放地址”、克拉克拉“弹幕暂未接入”、20-6 CHZZK“包含边界项的游标分页”） | 照搬 v3 原文，UPGRADES“说明文字”留给 M13 |
| P2 | 平台名两套入口 | I01.2 统一时这两处没换 |
| P3 | 不用的键占翻译文件三成，改文字时容易改错 | 页面改版后旧键没删（A13.2、I 记录“留在翻译文件里”） |

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修复 | `*_directory_scope` 改写：这个列表是什么、不包括什么、人数什么意思；中英都改，去掉不准的说法 | P1 |
| c2 | 修复 | `audience_*_detail` 改通俗（不出现接口字段名），口径说明页的开头一句跟着改 | P1 |
| c3 | 修复 | 账号页、工具箱的平台名用 `platformName` | P2 |
| c4 | 修复 | 用脚本找出全仓库代码里没有字面量、也不符合动态拼键（`'site_$id'`、`'room_mark_${…}'` 等）的键，从 zh、en 删掉，清单写进记录 | P3 |

测试：说明文字里没有接口字段名（ASCII 下划线词）；代码里 `i18n('…')` 用到的键在 zh、en 里都有（删键的保护）；账号、工具箱的平台名测试照旧。K90：分区页（SHOWROOM、FC2）顶部说明、设置“各平台口径说明”看文字。

风险：别的分支如果用到了被删的旧键，合并后会显示键名；上面“用到的键都在”的测试会在合并后的门禁里查出来。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 第 2、4 条：写功能对比，按授权直接开发（两处选择按 A） |
| 2026-10-02 | 第 2、4 条平台层、弹幕层完成，界面部分交回；待界面接上后 K90 验证（快手标题下次装机即可看） |

| 2026-10-02 | 第 1、3、5、6 条写功能对比、开发完成（投屏标题按协调员授权一起做），待 K90 验证 |
