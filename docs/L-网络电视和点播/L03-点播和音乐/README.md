# L03 点播和音乐

哔哩哔哩点播和音乐（电视端主要使用）。

`packages/live_vod`：哔哩哔哩的视频点播（热门、排行、推荐、详情、取流、字幕、弹幕、评论、动态、UP 主、收藏、稍后再看、历史、搜索）、番剧和影视（时间表、索引、季详情、取流）、音乐（分 P 当歌、UP 主合集当歌单、BGM 歌词、第三方歌词、网易云 / 酷狗 / QQ 歌单导入和匹配、每日推荐、播放队列、音频缓存规则）。这些是从电视版 pure_live_TV 搬来的核心逻辑，**还没有任何界面用它**；电视端的点播、音乐界面是 A17.6、A17.7（第三档）。

## 范围

- 包括：
  - `packages/live_vod/lib/src/` 全部：`client.dart`（`BilibiliVodClient`：Cookie、游客 buvid、WBI 密钥、请求、写接口的 csrf）、`ugc_api.dart`（`BilibiliUgcApi`）、`pgc_api.dart`（`BilibiliPgcApi`）、`streams.dart`（`VodStreams`：DASH 视频档和音频档、请求头、到期时间、变成 `LivePlayLine`）、`danmaku.dart`（点播弹幕分段的 protobuf 和 XML）、`parse.dart`（纯函数解析）、`models.dart`、`pgc_models.dart`、`store.dart`（存储接口 `VodKeyValueStore`）、`music/`（`music_api.dart`、`third_party.dart`、`matcher.dart`、`lyrics.dart`、`daily.dart`、`queue.dart`、`audio_cache.dart`）。
  - 样本 `fixtures/live_vod/`（38 个，2026-10-01 匿名只读录制，已脱敏）。
  - 以后应用一侧要补的实现：`VodKeyValueStore`（用 `live_store`）、`AudioCacheFiles`（用 `dart:io`）、DASH 外挂音轨交给播放器。
- 不包括（归哪里）：
  - 电视端的点播、番剧、音乐界面和播放页 → [A17.6](../../A-界面设计/A17-电视界面/A17.6-电视点播/README.md)、[A17.7](../../A-界面设计/A17-电视界面/A17.7-电视音乐/README.md)（设计已确认，第三档）；手机上要不要点播和音乐没有决定（先进 V01）。
  - 哔哩哔哩直播（`packages/live_core` 的 `BilibiliSite`）→ E01.1；WBI 签名、buvid 直接复用它的实现。
  - 登录 Cookie 的存取 → K、J02（`CookieVault.cookieFor('bilibili')`，和直播同一个登录）；播放器支持外挂音轨 → G（`live_player`、`live_media`）。
  - 对照 pure_live_TV 之后的修复 → W01。

## 现状：做到哪、怎么工作的

- 用户看得到的：**什么都没有**。`apps/pure_live/pubspec.yaml` 不依赖 `live_vod`（依赖了 `live_iptv`、`live_cast`），应用里没有点播或音乐的入口。
- 内部怎么工作（给以后接界面的人）：

```text
BilibiliVodClient（client.dart:26，注入 LiveHttp 和 CookieVault）
  请求：平台 id bilibili（和直播同一条代理和限速规则）；登录 Cookie 从 cookieFor('bilibili')，没登录用 finger/spi 的游客 buvid
  取流和媒体：只带登录 Cookie（游客带 buvid 会 412），用不签名的 x/player/playurl
  WBI 签名：复用 BilibiliSite.wbiSign、BilibiliApi.wbiKeys（6 小时）；-352 续签重试一次，再失败 RiskControl
  写接口（点赞、投币、收藏、关注、发弹幕、发评论、进度上报）：没登录先抛 NeedsLogin，不发请求；带 bili_jct 作 csrf
  错误一律 live_core 的 SiteError：-101 NeedsLogin、-352 RiskControl、412 RateLimited、-404 NotFound、其余 ApiChanged
BilibiliUgcApi（ugc_api.dart:20）/ BilibiliPgcApi（pgc_api.dart:16）/ BilibiliMusicApi（music/music_api.dart:50）编排请求，VodParse（parse.dart:15）解析
VodStreams（streams.dart:133）：videoFor / bestAudio / linesOf → G 的线路回退和租期；DASH 音视频分离，要播放器把音频作外挂音轨（mpv audio-files）
音乐：PlaylistImportSource（third_party.dart:119，网易云、酷狗、QQ 的分享链接识别和曲目）→ PlaylistImporter（matcher.dart:194，逐首搜索，间隔 1.2 秒，可取消）
  → TrackMatcher（:47，打分规则照电视版）；LyricLookup（lyrics.dart:220：手选 > 已存 > 各来源）；DailyRecommender（daily.dart:22）；
  PlayQueue（queue.dart:49，洗牌顺序）；AudioCache（audio_cache.dart:47，默认 1 GB，按最近播放淘汰）
```

- 完成度：L03.1（2026-10-01，`11d579e05`）做完核心包，48 个测试；修了电视版 13 个问题（弹幕未知字段错位、BGM 歌词取不到、删掉 DASH 导致画质封顶、rangotec 歌词全丢、酷狗歌名歌手对调、随机播放重复、推荐历史无限增长、音频缓存不清、评论翻页错、游客取流 412 等）。**登录后才能用的接口一个都没实测**（点赞、投币、收藏、关注、追番、发弹幕、发评论、进度上报、登录后的画质和字幕），参数照电视版和公开的接口说明写；`sendDanmaku` 用的是 `x/v2/dm/post`（电视版写的是 `x/v2/dm/send`），登录后要核对。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_vod/lib/src/client.dart`（206 行） | `BilibiliVodClient`（`:26`）：`get`、`stream`（只带登录 Cookie）、`file`、`signed`（WBI，-352 续签一次）、`post`（csrf，未登录先抛） |
| `.../ugc_api.dart`（450 行） | `BilibiliUgcApi`（`:20`）：热门、排行（`ranking/v2?rid=`）、推荐、相关、详情、取流（DASH / MP4）、`playerInfo`、字幕、弹幕分段和 XML、发弹幕、评论（真正的游标）和楼中楼、点赞评论、发评论、动态、UP 主空间和投稿、关注、点赞 / 投币 / 三连、收藏夹和收藏、稍后再看、历史和进度上报、搜索视频和用户、热词、联想 |
| `.../pgc_api.dart`（117 行）、`pgc_models.dart`（286 行） | `BilibiliPgcApi`（`:16`）：时间表、索引、季详情、取流、追番列表、追番、搜索；`PgcType`、`PgcCard`、`PgcTimelineDay`、`PgcEpisode`、`PgcSeason`（会员集标记 `need_vip`、试看） |
| `.../streams.dart`（245 行） | `VodQuality`（`:6`）、`VodRendition`（`:44`，带备用地址）、`VodSegment`（`:99`）、`VodStreams`（`:133`：请求头、`deadline`、`linesOf`） |
| `.../danmaku.dart`（171 行） | `VodDanmakuParse`（`:21`）：protobuf 分段（按线型跳过未知字段）、XML 回退 `comment.bilibili.com/{cid}.xml` |
| `.../parse.dart`（833 行）、`models.dart`（727 行） | `VodParse`（`:15`）纯函数解析；`VodArchive`、`VodPart`、`VodOwner`、`VodStat`、`VodComment`、`VodFavFolder`、`VodHistoryEntry` 等（需要存的带 `toJson`/`fromJson`） |
| `.../store.dart`（28 行） | `VodKeyValueStore` 接口（`:4`）、`MemoryVodStore`（`:16`） |
| `.../music/music_api.dart`（146 行） | `MusicTrack`（`:12`，一个分 P 是一首）、`BilibiliMusicApi`（`:50`：`tracks`、`resolve` 补 cid、`audio` 最好的音频档、UP 主合集和系列、`bgmLyric` 读 `mv_lyric` 地址再下载） |
| `.../music/third_party.dart`（418 行） | `ThirdPartyEndpoints`（`:23`，可改的地址，不合法回默认）、`PlaylistPlatform`（`:87`）、`PlaylistImportSource`（`:119`）、`ThirdPartyLyrics`（`:303`，lrc.cx、rangotec、网易云） |
| `.../music/matcher.dart`（238 行） | `TrackMatcher`（`:47`，分区过滤、切词、基础分、时长差、播放量）、`PlaylistImporter`（`:194`） |
| `.../music/lyrics.dart`（309 行） | `Lrc`（`:70`：解析、rangotec 的区间时间戳、offset、`cleanTitle`、`plausible`）、`LyricLookup`（`:220`） |
| `.../music/daily.dart`（171 行）、`queue.dart`（252 行）、`audio_cache.dart`（173 行） | `DailyRecommender`（`:22`，推荐历史保留 2000 个）；`PlayMode`、`PlayQueue`（洗牌一轮每首一次、上一首沿洗牌顺序）；`AudioCacheFiles`（`:9`）、`AudioCacheKey`（`:24`）、`AudioCache`（`:47`，LRU、正在播和预取的不删、启动删残留 `.part`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_vod/test/parse_test.dart`（23） | 每个样本的解析；DASH 画质和编码选择、最好的音频档、到期时间和线路；会员集试看；评论游标；游客的 -101、-352、-404；弹幕分段、XML、未知字段不错位；网易云、酷狗、rangotec、lrc.cx、BGM 歌词 |
| `packages/live_vod/test/client_test.dart`（10） | 取流不带游客 buvid；登录后 Cookie 和 csrf；WBI 签名和 -352 续签；写接口未登录不发请求；进度上报的表单；评论游标；番剧；音乐补 cid 和音频档；BGM 歌词 |
| `packages/live_vod/test/music_test.dart`（15） | 匹配器、导入（间隔、进度、取消）、第三方地址设置、分享链接识别、LRC、歌词链、队列、每日推荐、音频缓存 |

## 3.x 基线

- 3.x 手机版**没有**点播和音乐。基线是电视版 pure_live_TV（`b9d2f739`，本机 `~/ref/pure_live_TV`）的 `lib/modules/vod/api/*`、`models/*`（23 个 freezed 模型）、`domain/*`，`lib/modules/music/api/*`、`services/*`，以及 `vod/controllers/music_player_controller.dart` 的队列部分（L03.1 记录有逐文件对照）。
- 必须保留：电视版的接口覆盖面、匹配器的打分规则、第三方服务的默认地址（可改）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 应用里没有任何地方用 `live_vod` | `apps/pure_live/pubspec.yaml` | 包在门禁里跑测试，但不随应用发布；接口变了没人发现 | 等 A17.6、A17.7（第三档）；开工前先跑一次样本对照 |
| 登录后才能用的接口没实测；`sendDanmaku` 的路径和电视版不同 | `ugc_api.dart`、`pgc_api.dart` | 接界面后可能有参数错 | 接界面的任务里用维护者的测试账号核对（不把 Cookie 写进仓库） |
| 评论对游客受限（只给 3 条热评、没有下一页） | 平台限制（L03.1 实测） | 没登录时评论区几乎空 | 界面要说明“登录后可看全部评论” |
| 第三方服务是别人运营的（网易云、酷狗镜像在 `u2x1.work`，QQ 走 `timelessq.com`，歌词 rangotec、lrc.cx），导入歌单和找歌词会把歌单号、歌名发出去；网易云镜像直连时 TLS 被断开 | `third_party.dart:23` | 隐私和可用性 | 界面要写明并允许改地址（L03.1 记录“第三方服务”）；请求平台 id `music_third_party`，可单独配代理 |
| DASH 音视频分离要播放器支持外挂音轨 | `streams.dart`；`live_player` | 没有它只能用 MP4（画质封顶） | 接界面时在 G 组开任务（`PlaybackSession` 支持 `audio-files`） |
| 样本录于 2026-10-01，接口可能已变 | `fixtures/live_vod/` | 测试过但真实接口坏了 | 接界面前重录对照；平时由 W01 对照电视版的修复 |

## 相关决定和规范

- D-004（客户端顺序：电视排在 Android 手机、Windows 之后，所以第三档）、D-017（测试用样本，不访问真实平台）；样本脱敏规则（门禁 `fixture privacy`）。
- 用户看得到的文字（`SiteError` 的提示、来源名的中文）在接界面的任务里加（D-005）。

## 测试和验证

- 自动测试：`cd packages/live_vod && dart test`（48 个，用 `fixtures/live_vod` 的样本和假的 HTTP）。
- 真机：无（没有界面）。

## 路线

1. 电视端界面 A17.6（点播）、A17.7（音乐）开工时：应用依赖 `live_vod`，补 `VodKeyValueStore`、`AudioCacheFiles` 的实现，G 组加外挂音轨，用测试账号核对登录后的接口，重录样本。
2. 手机上要不要点播和音乐：没有决定，先进 V01 提议。
3. W01 每周对照 pure_live_TV 的点播和音乐修复，4.x 也有的问题开到这里。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [L 网络电视和点播](../README.md)。

- 代码：`packages/live_vod`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| L03.1 | 哔哩哔哩点播和音乐核心包 | 功能 | 完成 | 2026-10-01 | 11d579e05 | [设计或说明](L03.1-哔哩哔哩点播和音乐核心包/README.md)、[记录](L03.1-哔哩哔哩点播和音乐核心包/record.md) |

<!-- docs:生成结束 -->
