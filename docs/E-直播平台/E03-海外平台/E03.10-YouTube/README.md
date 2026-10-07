# E03.10 YouTube

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 23-1～23-6）记在 [record.md](record.md)；聊天由 D01.20 接上
- 旧编号：M4.23、M4.U.23、T02c.10
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.20](../../../D-弹幕/D01-平台弹幕协议/D01.20-YouTube弹幕/README.md)（用 `YouTubeDanmakuArgs`）；视频号关注迁移成频道 J02.1、启动时的 `IdentityMigration`（I01.1）、覆盖安装验证 J06.1；推荐页 I02.1、搜索页 I05.1、关注页 I04.1；直播间说明受限原因 C01.1；决定 D-001、D-017
- 代码：`packages/live_core/lib/src/sites/youtube/`（`youtube_api.dart` 1439 行纯解析和链接规则，`youtube_site.dart` 721 行请求编排）；应用在 `apps/pure_live/lib/app/platforms.dart:175` 建适配器，`:262-273` 把 3.x 的视频号换成频道；样本 `fixtures/youtube/`（27 组接口录制，另有聊天帧 `danmaku/` 和生成 3.x 冻结输出的 `legacy_expected.dart`）

## 目标

把 3.x 的 YouTube 适配器（`lib/core/site/youtube/` 三个文件共 1020 行，自带 16 MiB 流式读取的传输层，房间号是一场直播的视频号）重构进 `live_core`：观看页加 ANDROID `player` 定状态和来源，HLS 变体、渐进格式、DASH 三类画质和租期都和 3.x 一样；修掉 3.x 的 17 个问题里不改界面的那些（不存在的视频报“身份不符”、取不到来源时整个房间打不开、恢复要重读 1.4 MB 的观看页等）。升级落地后房间身份改为频道（关注频道，开播自动跟到新的一场），有推荐和关键词搜索，头像用频道头像，受限的直播显示为直播中，刷新不再下载观看页。

## 平台接口要点

| 功能 | 接口（`www.youtube.com`；全部匿名；页面请求头 Chrome 140 UA、`Accept-Language: en-US,en;q=0.9`、同意页 Cookie `SOCS=CAI`；25 秒时限；以 `youtube` 的名义发出，走代理） | 位置 |
|---|---|---|
| 请求 | `_send`/`_get`/`_post`；401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，400 和空回答 `ApiChanged`，5xx `NetworkFailure` | `youtube_site.dart:13`、`:112-134`；`youtube_api.dart:449-480`、`:531` |
| 观看页 | `watch?v=<视频号>`：`INNERTUBE_API_KEY`、`ytInitialPlayerResponse`、`ytInitialData`（频道头像、在线人数、开播时间、分区） | `youtube_site.dart:147`；`youtube_api.dart:554-596`、`:1393` |
| player | `POST youtubei/v1/player?key=<key>`，请求体是 3.x 的 ANDROID 客户端（逐字相同；网页客户端会被要求浏览器证明）；没有 key 时用 3.x 内置的公开 key | `youtube_site.dart:155-177`；`youtube_api.dart:392`、`:504-509`、`:863-902` |
| 频道 | 进房读频道的 `/live` 页（在播时就是这一场的观看页，未开播时是频道页）；刷新和链接用 WEB 客户端的 `navigation/resolve_url`（约 1 KB）；未开播的搜索卡片读 RSS `feeds/videos.xml` 取名字 | `youtube_site.dart:184-185`、`:424`、`:494-502`；`youtube_api.dart:427-431`、`:484`、`:500`、`:655-665` |
| 在线人数 | 进房从观看页的 `videoViewCountRenderer`；刷新另请求 `updated_metadata`（“1,331 watching now”），失败时人数留空 | `youtube_site.dart:191-194`；`youtube_api.dart:497`、`:677`、`:1100` |
| 推荐和目录 | WEB `browse` 的“直播”频道页（`UC4R8DWoMoI7CAwX8_LjQHig`），只要在播的行，一个频道一张卡；没有续页，第 2 页起为空；目录说明键 `youtube_directory_scope` | `youtube_site.dart:104`、`:268-280`；`youtube_api.dart:403`、`:487`、`:693-753` |
| 搜索 | 精确引用（视频或频道链接、`@handle`、频道号、视频号）只查这一个；其余是带“直播”过滤器（`EgJAAQ%3D%3D`）的关键词搜索，按续页令牌翻页，跨页按频道去重 | `youtube_site.dart:284-353`；`youtube_api.dart:108`、`:406`、`:490-493` |
| 状态和受限 | `isLive`（或 `isLiveNow`）且不是 `LIVE_STREAM_OFFLINE` 是直播中；受限类型按 `player` 的状态和英文原因：私密、会员、年龄、地区、付费、要登录、不能播；受限直播进房不读主列表，取画质报 `RegionBlocked`、`NeedsLogin` 或 `StreamUnavailable` | `youtube_api.dart:998-1020` |
| 画质 | HLS 主列表拆成变体（`1080p · H264 · HLS`，id `hls:1080:0:h264`），读不懂时用“HLS 自动”；再加明文的渐进格式（`http:<itag>`）和“DASH 自动”；排序高度 × 1000 + 帧率 + 协议 | `youtube_site.dart:207`、`:594-617`；`youtube_api.dart:439-442`、`:1155-1297` |
| 取流和租期 | 每个来源一条线路，带 3.x 的媒体请求头（UA、`Referer` 为观看页、`Origin`）；租期按地址的 `expire`（约 6 小时），提前 10 分钟续；恢复只请求 `player` 和（HLS 变体时）主列表 | `youtube_site.dart:624-637`；`youtube_api.dart:436`、`:467`、`:1323-1344` |
| 记住那一场 | 同一频道常有几场同时在播：卡片、精确搜索、进房展示的那一场记 30 分钟（`broadcastLifetime`，最多 256 个频道），这期间进房直接打开它 | `youtube_site.dart:52-79`、`:239-255` |
| 聊天参数 | 在播房间（进房、刷新、录制、搜索卡片）带 `YouTubeDanmakuArgs(roomId: 频道号, videoId: 这一场)` | `youtube_api.dart:251`、`:410` |
| 身份迁移 | `resolveRoomId`：频道号不发请求，视频号请求一次 `player` 取 `videoDetails.channelId`（`channelOf`） | `youtube_site.dart:556`；`youtube_api.dart:1034` |
| 链接 | `youtu.be`、`youtube.com`、`youtube-nocookie.com`：视频链接不发请求得到视频号；`channel/UC…`、`embed/live_stream?channel=` 直接得到频道号；`@handle`、`c/`、`user/` 经会话 POST 一次 `navigation/resolve_url` | `youtube_api.dart:27-166`；`youtube_site.dart:701-707` |

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/youtube/`） | 现在 | 说明 |
|---|---|---|---|
| 房间身份 | `youtube_site.dart:57` 视频号，一场直播一个，频道下次开播关注就对不上 | 频道号 `UC…`；仍接受视频号，`resolveRoomId` 给迁移用 | 23-1；迁移规则在 record.md |
| 不存在的视频 | `youtube_api.dart:232` 先核对视频号，报 `identity`，搜索整个报错 | `NotFound`，搜索为空 | 3.x 问题 1 |
| 取不到来源 | 进房时检查，列表为空或地址不在 YouTube 主机上整个房间打不开 | 照常进房，取画质时报错 | 3.x 问题 2 |
| 取画质 | `youtube_site.dart:144`、`:155` 没有进房数据报 `identity`，未开播和封禁返回空列表 | 先进房；未开播、受限报原因，不发请求 | 3.x 问题 3、4 |
| 恢复 | `youtube_site.dart:176` 重读整个房间（观看页约 1.4 MB） | 只请求 `player` 和主列表 | 3.x 问题 5 |
| 推荐和搜索 | `youtube_site.dart:49`、`:128-135` 推荐为空，搜索只查精确引用，3～30 个字符的词当 `@handle` | “直播”频道页；关键词搜索带直播过滤，能翻页 | 23-2 |
| 头像 | `youtube_site.dart:61-62` 是视频缩略图 | 频道头像 | 23-4 |
| 受限和不能播 | `youtube_api.dart:250-262` 受限是封禁，直播中但不能播是未开播 | 直播中 + 受限类型，播放时说明原因 | 23-5 |
| 刷新 | 观看页加 `player`（约 1.6 MB） | `resolve_url`、`player`、`updated_metadata`（在播约 0.2～0.3 MB） | 23-6 |
| 默认分区 | `youtube_site.dart:63` 没有分类时写 `YouTube Live` | 留空（刷新不读观看页后它会盖掉真实分类） | 统一原则的占位信息 |
| 错误 | 11 种 `YouTubeFailure`，3xx 算传输错误 | 类型化的 `SiteError`，调用方错误是 `ArgumentError` | 3.x 问题 7 |
| 传输 | `youtube_api.dart` 全局 `HttpClient`、16 MiB、严格 UTF-8 | 注入 `LiveHttp`，25 秒时限 | 3.x 问题 8 |
| 聊天 | `youtube_site.dart:39` `EmptyDanmaku` | 平台层给参数，连接在 `live_danmaku/lib/src/sites/youtube.dart`（D01.20） | 23-3 |

## 结果

- 首次重构（2026-09-28，提交 `af6e14961`）：补录 13 个 3.x 自己的请求样本（同一分钟、经代理、脱敏，观看页只留 3.x 读的部分），17 个 3.x 问题、9 条有意差异见 record.md。
- 升级落地（2026-09-29）：23-1～23-6 全部完成（23-1 的迁移由 J02.1、I01.1 接上，关注页 I04.1；23-2 的推荐页、搜索页由 I02.1、I05.1 接上；23-3 平台层给参数，连接 D01.20；23-5 的说明由 C01.1 接上）；新录 5 个样本（`S03-resolve-*` 四个、`S13-metadata-live`）。按统一原则补了开播时间（`liveBroadcastDetails.startTimestamp`，只在进房时有）、受限类型、去掉默认分区。房间公告 `chatNotice` 在 D01.20 后改为只说人数口径（`youtube_api.dart:396`），3.x 的旧文字留在 `legacyChatNotice`。
- 测试：`packages/live_core/test/sites/youtube_api_test.dart` 46 个 `test(` 写法、`youtube_site_test.dart` 56 个（record.md 写的是 47 个和 56 个）；聊天 `packages/live_danmaku/test/sites/youtube_test.dart` 归 D01.20。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`fixtures/youtube/legacy_expected.dart`）：在播直播三种深度、7 个来源和画质、每档地址和租期、恢复；已结束、预告、普通视频、不存在；38 个链接、11 个搜索词；升级后按频道身份重新对照，另测 `resolve_url` 的 7 个样本、“直播”频道页和关键词搜索的续页、十种受限直播、记住那一场、3.x 关注迁移前后（“a 3.x follow (a video id) is merged only once migrated”）。
- 真实接口：2026-09-28 12:23 补录 3.x 的请求；19:20～19:30 UTC 经本机代理、匿名跑了 `resolve_url` 的 7 种路径、5 个视频的 `updated_metadata`、`next`、不存在的频道号的 `/live` 页和 RSS。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节只记“完成”，推荐是“直播”频道页）；要用户开着代理，媒体地址绑定出口 IP，播放和接口必须走同一个代理。

## 留下的问题

- 3.x 存下的视频号关注要逐个迁移成频道（不并发；视频已删除或私密的保留原值）；迁移前关注刷新会被 `mergeFrom` 忽略。覆盖安装的真机核对归 J06.1。
- 受限的在播直播（会员、年龄、地区、付费、私密）没有样本，只按 `player` 的英文原因判断；认不出的原因退回 `needsLogin` 或 `unplayable`。没有任务管。
- 同一频道几场同时在播时 `/live` 页和 `resolve_url` 选哪一场由 YouTube 决定；关注刷新显示 `/live` 那一场。
- 不存在的频道号 `resolve_url` 照样回“频道”，刷新看不出来，一直显示未开播；进房和搜索能认出是 `NotFound`。没有任务管。
- 链接解析的请求以链接的名义发出，频道链接在需要代理的地区要按主机分给 YouTube 的代理（记给链接解析入口，没有单独任务）。
