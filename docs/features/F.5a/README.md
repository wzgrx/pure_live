# F.5a 已批准升级里还没做的（原 M13.18 收尾）

- 状态：第 2、4 条完成（2026-10-02，[记录](../records/F.5a1.md)；界面部分交回，见记录“交给界面”）
- 档位：可以以后；规模：大
- 功能点：不是 v3 功能（[UPGRADES.md](../../UPGRADES.md) 的余项）（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：多处，见下
- 依赖：F.0～F.4 的“必须”完成后
- 来源：scratchpad `rest/m13_18_closing.md`（没开始）、M13.17 任务说明第 7 项
- 评审页：发评审页（条目多，逐条表态）
- 记录：[records/F.5a.md](../records/F.5a.md)（开发后）；第 2、4 条：[records/F.5a1.md](../records/F.5a1.md)

## 要做的（逐条核对代码后再定范围）

1. 回填 `docs/UPGRADES.md` 状态列（约 60 条还写着“余下 M13”或“待做”）。
2. 平台和直播间：A-3 快手详情标题、A-6、B-7 Twitch Cookie 失效提示、B-16 酷狗 PK 对方聊天、11-1 Picarto 恢复时取最好一档、1-1 登录后播放哔哩哔哩轮播、B-14 名字颜色和徽章、8-8 Twitch 按引擎能力请求 HEVC/AV1。
3. 列表：卡片显示开播时间和简介（7-9、10-3、11-5、25-12、33-7）；1-1 轮播和封禁在历史卡片上的标识；搜索翻页共用快照（19-1、24-5、26-1）。
4. `live_core` 收尾（M7.1 留下）：YouTube 和 PandaTV 主列表读法合并、FC2 画质探测交出控制连接、哔哩哔哩轮播从 `play_time` 开始、LiveMe 和 TikTok 租期是否断开。
5. 数据：备份带上网络电视列表、搜索历史、多画面会话（恢复 3.x 备份照旧）；投屏给电视的标题改成“主播 - 标题”（M10 记录说要先问用户）。
6. 文字整理：`*_directory_scope` 目录说明、`audience_*_detail` 改通俗；清理不再引用的旧键；工具箱和账号页的 `i18n('site_$id')` 换成 `platformName`。

WebDAV Digest 已拆到 F.4b。

## 第 2 条：平台和直播间（平台层、弹幕层）

按授权直接开发：都是 UPGRADES 已批准的条目；只改 `live_core`、`live_danmaku`，界面上要显示的只给数据和接口，界面部分写进记录交回。两处选择按 A 做。

### v3 的行为（`~/ref/v3ref/lib`，v3.2.11）

| 条目 | v3 | 位置 |
|---|---|---|
| A-3 | 快手详情的标题是主播简介（换行变空格），进房后卡片上的直播标题被简介盖掉 | `core/site/kuaishou/kuaishou_site.dart:292`、`:469` |
| A-6 | 网易 CC 未开播主播进房是“状态未知”、刷新抛 RangeError；百度预告房间报“接口变了” | M4.09 问题 3、M4.30（v4 已改为未开播） |
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
| P3（B-7） | 弹幕层已在登录被拒时提示一次（M5.F）；平台层播放令牌被拒时 `_accessToken` 只记下 `_rejectedSession` 改匿名（`twitch_site.dart:549-565`），没有任何出口告诉界面 |
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

## 第 4 条：`live_core` 收尾（M7.1 留下）

| 编号 | v4 现在（根因） | 改动 |
|---|---|---|
| P9 / c9 合并 | YouTube（`youtube_api.dart:1191-1240`）和 PandaTV（`pandalive_api.dart:1017-1105`）各写了一遍 `#EXT-X-STREAM-INF` 的读法，属性解析也是两套 | `hls_master.dart` 加共用的宽松读法 `HlsStreamInf.read` 和 `HlsStreamInf.attributes`（严格、宽松两种），两个平台改用它；各自的规则（YouTube 整体拒绝、PandaTV 只丢坏的那一档）不变。唯一的行为差别：PandaTV 的 `STREAM-INF` 和地址之间夹了别的标签时不再丢掉这一档（同 YouTube） |
| P10 / c10 补上 | FC2 画质探测开了控制连接，读完就关（`fc2live_site.dart:431-439`），播放再开一条；`live_media` 的 `Fc2RecipeOpener.adopt` 已能接手，平台层没有交出的出口 | `Fc2LiveSite(probeControl:)`：给了就把探测的控制连接交给它（它负责关），没给照旧关掉。控制连接里有全部档位的地址（`Fc2LiveApi.playlistFor`），接手的一方可以播任何一档 |
| P11 / c11 补上 | `PlaybackPlan.start` 已能从指定位置开始（M7.1），但平台层不给起点 | `LivePlayUrlResolution.start`：c6 的轮播视频从 `play_time` 秒开始；播完按直播流结束处理，恢复时再取当时在轮播的那一个 |
| P12 / c12 保留 | 租期是否切断连接 | LiveMe 已在 M4.U（21-8）实测：过期不断流，线路不带租期；TikTok 的 `expire` 是签发后约 14 天，只预取、不切断（`tiktok_api.dart:667-675`）。都不改，用已有测试确认 |

## 测试和验证（第 2、4 条）

- 单元测试：每条 c 至少一个（`live_core`、`live_danmaku`），用仓库里的样本（快手 S09、酷狗 `S09-pk-chat`、17LIVE `S06-live`、`live_vod/V09-playurl-mp4`、Picarto、YouTube、PandaTV 的样本）和合成回答；`getRoundPlayVideo` 没有录过样本，按 M4.01 记录的字段写合成回答。
- K90：这些都要界面接上后才看得到（见记录“交给界面”）：快手从推荐卡片进房显示卡片标题；哔哩哔哩找一个轮播房间进房能播放并从中途开始；酷狗 PK 时对方的聊天带“对方”；海外的（Twitch、Picarto、17LIVE）有代理时再看。

## 风险和性能（第 2、4 条）

- 不加常驻任务和定时器；`LiveMessage` 多三个字段（默认值共用常量）。
- 3.x 的数据和设置不变：新字段都不存盘；没有新设置。
- 轮播视频多两个请求（`getRoundPlayVideo`、`playurl`），只在游客进轮播房间时发生。
- FC2 交出的控制连接由接手的一方关闭；没接上时照旧关掉，不会多开连接。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 第 2、4 条：写功能对比，按授权直接开发（两处选择按 A） |
| 2026-10-02 | 第 2、4 条平台层、弹幕层完成，界面部分交回；待界面接上后 K90 验证（快手标题下次装机即可看） |
