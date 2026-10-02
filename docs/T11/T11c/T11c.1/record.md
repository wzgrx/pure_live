# T11c.1 哔哩哔哩点播和音乐的核心包

- 日期：2026-10-01
- 目标包：`packages/live_vod`（纯 Dart，依赖 `live_core`、`live_net`、`meta`；没有界面）
- 来源：pure_live_TV `b9d2f739`（本机副本 `~/ref/pure_live_TV` 的 HEAD；本任务在隔离的 worktree 里，不能对参考仓库执行 `git pull`，副本当天 13:22 已拉取过）
  - `lib/modules/vod/api/*`、`lib/modules/vod/models/*`、`lib/modules/vod/domain/*`
  - `lib/modules/music/api/*`、`lib/modules/music/services/*`（`playlist_matcher`、`daily_recommendation_service`、`music_lyric_service`、`music_audio_cache` 里与界面无关的部分）
  - `lib/modules/vod/controllers/music_player_controller.dart` 的队列和播放模式
  - 歌单导入流程取自 `lib/modules/music/pages/playlist/music_playlist_import_dialog.dart`（去掉界面）
- 样本：`fixtures/live_vod`，38 个，2026-10-01 05:36～05:43 UTC 匿名只读录制

## 做法

- **请求只走注入的 `LiveHttp`**，平台 id 用 `bilibili`（和直播同一条代理、限速规则）；第三方服务用 `music_third_party`，应用可以单独给它配代理。
- **登录态复用直播的哔哩哔哩账号**：`BilibiliVodClient` 从 `CookieVault.cookieFor('bilibili')` 取 Cookie（T09b.1 的 `secrets` 表），`DedeUserID` 是 mid，`bili_jct` 是写接口的 csrf。没登录时用 `finger/spi` 的游客 buvid。
- **复用 T02a.1 的哔哩哔哩实现**：WBI 签名直接用 `BilibiliSite.wbiSign`，密钥解析用 `BilibiliApi.wbiKeys`，buvid 用 `BilibiliApi.buvid`/`cookie`，UA 用 `BilibiliApi.userAgent`。没有重写签名。
- **解析写成纯函数**（`VodParse`、`VodDanmakuParse`、`Lrc`、`PlaylistImportSource.neteaseTracks/kugouTracks`），用录下的样本测；请求编排在 `BilibiliUgcApi`、`BilibiliPgcApi`、`BilibiliMusicApi`。错误一律是 `live_core` 的 `SiteError`（-101 → `NeedsLogin`，-352 → `RiskControl`，412/-412 → `RateLimited`，-404 等 → `NotFound`，其余 → `ApiChanged`），不再像电视版那样抛 `Exception('…')` 或吞成空列表。
- **模型是普通 Dart 类**（不用 freezed），需要存的（`VodArchive`、`VodPart`、`VodOwner`、`VodStat`、`VodFavFolder`、`MusicTrack`）带 `toJson`/`fromJson`。
- **存储和文件读写都注入**：`VodKeyValueStore`（每日推荐、歌词选择和缓存），`AudioCacheFiles`（音频缓存目录）。M14.4 用 `live_store` 和 `dart:io` 实现，本包不碰存储。
- **点播的 DASH 怎么交给播放器**：`VodStreams` 同时给出视频档和音频档（各带备用地址）、请求头和到期时间（`deadline`）。`linesOf(rendition)` 把一档变成 `LivePlayLine`（带请求头、编码、`os=` CDN 代号作线路 id、租期），所以 T04a.1 的线路回退、租期都能直接用。音视频分离要播放器把音频档作为外挂音轨（mpv `audio-files`），这一步在 M14.3（见“留给后续”）。

## 包结构和对外接口

| 文件 | 内容 |
|---|---|
| `client.dart` | `BilibiliVodClient`：Cookie、游客 buvid、WBI 密钥（6 小时）、`get`、`stream`（只带登录 Cookie）、`file`、`signed`（-352 续签重试一次）、`post`（csrf，未登录先抛 `NeedsLogin`，不发请求） |
| `ugc_api.dart` | `BilibiliUgcApi`：`popular`、`ranking(rid)`、`recommended`、`related`、`detail`、`streams`（DASH/MP4）、`playerInfo`、`subtitleCues`、`danmakuSegments`/`danmakuSegment`/`danmakuXml`/`sendDanmaku`、`comments`（游标）/`replies`/`likeComment`/`addComment`、`dynamics`、`userSpace`/`relationStat`/`uploads`/`setFollowing`/`followings`、`setLike`/`addCoin`/`triple`/`relation`、`favFolders`/`collectedFolders`/`favItems`/`setFavorites`/`createFolder`、`toView`/`addToView`/`removeToView`、`history`（游标）/`reportProgress`/`deleteHistory`、`searchVideos`/`searchUsers`/`hotwords`/`suggestions` |
| `pgc_api.dart` | `BilibiliPgcApi`：`timeline`、`index`、`season`、`streams`、`followed`、`setFollowing`、`search`（番剧/影视） |
| `music/music_api.dart` | `MusicTrack`（一个分P是一首歌）、`BilibiliMusicApi`：`tracks`、`resolve`（列表行补 cid）、`audio`（最好的音频档，可选 Hi-Res）、`collections`/`collectionArchives`（UP 主的合集和系列，当作 UP 主歌单）、`bgmLyric` |
| `music/third_party.dart` | `ThirdPartyEndpoints`（可配置地址）、`PlaylistImportSource`（网易云、酷狗、QQ，`parse` 识别分享链接）、`ThirdPartyLyrics`（lrc.cx、rangotec、网易云） |
| `music/matcher.dart` | `TrackMatcher`（打分规则见下）、`PlaylistImporter`（逐首匹配、间隔 1.2 秒、进度、可取消） |
| `music/lyrics.dart` | `Lrc`（解析、`cleanTitle`、`plausible`）、`LyricLookup`（手选 > 已存 > 各来源） |
| `music/daily.dart` | `DailyRecommender` |
| `music/queue.dart` | `PlayQueue<T>`、`PlayMode` |
| `music/audio_cache.dart` | `AudioCacheKey`、`AudioCache`（LRU 淘汰）、`AudioCacheFiles` |
| `models.dart`、`streams.dart`、`pgc_models.dart`、`parse.dart`、`danmaku.dart`、`store.dart` | 模型、解析、存储接口 |

## 与电视版的对照

| 电视版文件 | 行数 | 重构后 | 说明 |
|---|---|---|---|
| `vod/api/bilibili_api_client.dart` | 75 | `client.dart` | 单例和全局设置改为注入；Cookie 来自 `CookieVault` |
| `vod/api/bilibili_ugc_api.dart` | 474 | `ugc_api.dart`、`parse.dart` | 全部接口保留；评论改用真正的游标；写接口统一 `post` |
| `vod/api/bilibili_music_api.dart` | 222 | `ugc_api.dart`（目录、详情、取流）、`music/music_api.dart` | 取流恢复 DASH（见问题 3），MP4 仍可选 |
| `vod/api/bilibili_pgc_api.dart` | 173 | `pgc_api.dart` | 改用时间表和索引（任务要求）；电视版的 `pgc/page/web/feed` 没有搬（返回的是推荐流，索引可以代替） |
| `vod/api/bilibili_danmaku_api.dart` | 277 | `danmaku.dart`、`ugc_api.dart` | 修跳字段错误（问题 1）；XML 回退改用 `comment.bilibili.com/{cid}.xml` |
| `vod/api/bilibili_lyric_api.dart` | 92 | `music/music_api.dart` `bgmLyric` | 修 `mv_lyric`（问题 2） |
| `vod/models/*`（23 个 freezed 模型，约 8000 行含生成代码） | — | `models.dart`、`streams.dart`、`pgc_models.dart`（约 1100 行） | 普通类；`MusicArchive`→`VodArchive`，`MusicPart`→`VodPart`，`MusicPlayUrls`/`MusicStreamOption`→`VodStreams`/`VodRendition`，`MusicPlayMode`→`PlayMode` |
| `vod/domain/*`（仓库接口和 Riverpod provider） | 197 | 不搬 | 接口层就是 `BilibiliUgcApi` 等具体类，界面用 Riverpod 包一层即可（M14.3/M14.4） |
| `music/api/music_provider.dart` | 117 | `music/third_party.dart` `PlaylistImportSource` | 地址可配；酷狗歌名歌手修正（问题 6） |
| `music/api/third_party_lyric_api.dart` | 134 | `music/third_party.dart` `ThirdPartyLyrics` | 地址可配 |
| `music/services/playlist_matcher.dart` | 148 | `music/matcher.dart` | 规则不变；搜索交给调用方注入 |
| `music/services/daily_recommendation_service.dart` | 186 | `music/daily.dart` | 存储注入；历史有上限（问题 8） |
| `music/services/music_lyric_service.dart` | 333 | `music/lyrics.dart` | 改成解析器（问题 4、5） |
| `music/services/music_audio_cache.dart` | 89 | `music/audio_cache.dart` | 加淘汰（问题 9）；文件操作注入 |
| `vod/controllers/music_player_controller.dart` 的队列部分（约 200 行） | — | `music/queue.dart` | 随机改为洗牌顺序（问题 7） |

## 电视版的问题和处理

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 点播弹幕的元素里有不认识的字符串字段（midHash、idStr）时，后面的字段全读错 | `bilibili_danmaku_api.dart` `parseDanmakuSegment` 的 `default:` 分支 | 跳过未知字段时重新读了一遍键，没有按类型跳过值，值被当成下一个键 | 按线型跳过；测试用一个带 midHash 的元素守着 |
| 2 | 哔哩哔哩 BGM 歌词从来取不到 | `bilibili_lyric_api.dart` `fetchBgmLyric` | `bgm/detail` 的 `mv_lyric` 是 LRC 文件的地址（样本 M01），电视版当成歌词正文，再被“必须含 `[00:`”的检查丢掉 | 读地址再下载文件（样本 M02），http 改 https |
| 3 | 电视版删掉了 DASH，只播合流 MP4，画质封顶、没有音频档 | `bilibili_music_api.dart` `getPlayUrls` 的注释 | 注释说 COS 节点对 FFmpeg 播放器回 400。实测（问题外的发现）：所有节点带浏览器 UA 和 Referer 都回 206；UA 换成 FFmpeg 默认的 `Lavf/…` 回 403，没有 Referer 回 403。根因是请求头，不是节点 | 恢复 DASH（`fnval=4048`，全部画质和音频档），线路带浏览器 UA 和稿件页 Referer；MP4（`mp4: true`）保留作备选 |
| 4 | rangotec 的歌词全被丢掉 | `music_lyric_service.dart` `_normalize` | rangotec 用 `[00:04:772,00:06:262]`（开始,结束），电视版的正则只认单个时间戳，转换后找不到 `[mm:ss.xx]` 就丢弃 | `Lrc.parse` 认这种写法，并保留结束时间 |
| 5 | 第一句在 1 分钟以后的歌词被丢掉 | 同上 | 要求正文含 `[00:` | 只要有带时间的行就算 |
| 6 | 酷狗导入的歌名和歌手对调 | `music_provider.dart` `fetchKuGouPlaylistTracks` | 酷狗的 `name` 是“歌手 - 歌名”（样本 T02），电视版按“歌名-歌手”切 | 歌手优先用 `singerinfo[].name`，歌名取“ - ”之后 |
| 7 | 随机播放可能很快重复同一首；随机时“上一首”跳到列表里的邻居 | `music_player_controller.dart` `next`/`previous` | 每次重新随机挑一首；上一首按列表下标 | 洗牌顺序：一轮每首一次，新一轮第一首不是刚放完的；上一首沿洗牌顺序回退 |
| 8 | “推荐过”历史无限增长 | `daily_recommendation_service.dart` `_historyKey` | 只加不删 | 保留最近 2000 个 |
| 9 | 音频缓存从不清理 | `music_audio_cache.dart` | 没有淘汰 | 上限默认 1 GB，按最近播放淘汰，正在播放和预取的不删；启动时删掉残留的 `.part` |
| 10 | 评论翻页错：第 2 页起发的是 `{"offset":2}` 这样的页码 | `bilibili_ugc_api.dart` `getComments` | 接口要的是上一页 `cursor.pagination_reply.next_offset` 的原文，电视版自己拼了页码，还把页码当“下一页游标”返回 | 原样传 `next_offset`；没有时就是最后一页 |
| 11 | 游客取流 412 | `bilibili_api_client.dart` `headers`（所有请求都带游客 buvid） | 实测：`x/player/playurl` 带 `finger/spi` 的游客 buvid 回 412，不带 Cookie 回 200；`x/player/wbi/playurl` 对游客也 412 | 取流和媒体请求只带登录 Cookie（游客不带）；用不签名的 `x/player/playurl` |
| 12 | 进度上报、删除历史、收藏等是“发出去不等结果”，失败没人知道 | `reportHistory`、`deleteHistory`、`favDeal` 没有 `await` | — | 都返回 Future，失败抛类型化错误，由调用方决定是否提示 |
| 13 | 分区最新（`dynamic/region`）已下线 | — | 实测 -404（样本 V04） | 分区用 `ranking/v2?rid=`（电视版的分区页也是这个） |

## 实测（2026-10-01 05:36～05:45 UTC，直连，匿名只读，合计不到 3 分钟）

| 接口 | 游客结果 |
|---|---|
| 热门、排行（`rid=3` 音乐）、首页推荐（WBI）、详情、相关推荐 | 正常 |
| 取流 `x/player/playurl`（DASH、MP4） | 不带 Cookie 正常；**带游客 buvid 回 412**；游客最高 480P（有登录才有更高画质） |
| 取流 `x/player/wbi/playurl` | **412**（样本 V07），不用 |
| 媒体 CDN（bd、cos、hw、estg 各节点） | 带浏览器 UA 和 Referer：206；无 Referer：403；`Lavf` UA：403 |
| 番剧时间表、索引、季详情、免费集取流 | 正常 |
| 会员集取流（鬼灭之刃 柱训练篇 第 2 话） | 返回 3 分钟试看（`is_preview` 1、`status` 13、`error_code` -10403、各画质 `need_vip`），照实标记 |
| `x/player/wbi/v2` | 正常；游客没有字幕；有 BGM 信息 |
| 评论 `reply/wbi/main` | **受限**：游客只给 3 条热评、`is_end` 为真、没有下一页游标（总数 4461）；楼中楼 `reply/reply` 正常 |
| 弹幕 `dm/web/view`、`dm/wbi/web/seg.so`、`comment.bilibili.com/{cid}.xml` | 正常；不签名的 `dm/web/seg.so` 这次也返回同样内容（电视版说它对游客返回空），仍用签名版 |
| 搜索视频、用户、热词、联想 | 正常；搜索结果里夹着课程（`ketang`），已过滤 |
| UP 主 `acc/info`、`arc/search`（WBI） | **受限**：游客 -352 |
| UP 主合集和系列 `seasons_series_list`、`relation/stat` | 正常（这个 UP 没有合集） |
| 动态、历史、稍后再看 | **要登录**（-101） |
| 收藏夹列表（别人的） | 游客 `data: null` |
| BGM 详情、歌词文件 | 正常 |
| 网易云镜像 `rp.u2x1.work` | 直连 TLS 被断开，走本机代理正常（100 首） |
| 酷狗镜像 `kg.u2x1.work` | 正常（54 首）；猜的歌单号回 502，用它自己的搜索找到真实的 `collection_…` 号 |
| rangotec、lrc.cx | 正常 |

没有实测（要登录，不登录就不碰）：点赞、投币、三连、收藏、关注、追番、发弹幕、发评论、进度上报、登录后的画质和字幕。这些接口的参数照电视版和公开的接口说明写，`sendDanmaku` 用的是 `x/v2/dm/post`（电视版写的是 `x/v2/dm/send`，公开说明里发弹幕是 `dm/post`），登录后要核对。

## 第三方服务

| 服务 | 默认地址（照电视版） | 发出去的内容 | 用途 | 设置项（`ThirdPartyEndpoints`） |
|---|---|---|---|---|
| 网易云歌单镜像（NeteaseCloudMusicApi） | `https://rp.u2x1.work` | 歌单号 | 导入网易云歌单 | `neteasePlaylist` |
| 酷狗歌单镜像（KuGouMusicApi） | `https://kg.u2x1.work` | 歌单号 | 导入酷狗歌单 | `kugouPlaylist` |
| 酷狗官网 | `https://www.kugou.com/songlist/{gcid}/` | 分享链接里的 gcid | 把 gcid 换成歌单号 | 不可改（官方） |
| QQ 音乐歌单代理 | `https://api.timelessq.com` | 歌单号 | 导入 QQ 音乐歌单（电视版有，本次未实测） | `tencentPlaylist` |
| rangotec 歌词 | `https://tools.rangotec.com` | 歌名、歌手 | 歌词 | `rangotecLyric` |
| lrc.cx 歌词 | `https://api.lrc.cx` | 歌名、歌手 | 歌词 | `lrcCxLyric` |
| 网易云官方接口 | `https://music.163.com` | 歌名（加歌手） | 歌词最后的回退 | `neteaseLyric` |

- 这些都是别人运营的服务：导入歌单会把歌单号发给镜像，找歌词会把歌名和歌手发给歌词服务。设置页要写明这一点（M14.4）。
- 地址都可以改成自建的同类服务；不合法的地址（非 http/https、没有主机）读出时用默认值。
- 请求的平台 id 是 `music_third_party`，可以按平台走代理（网易云镜像在本机直连不通）。

## 匹配器的打分（照电视版）

搜索“歌名 - 歌手”（歌手为空时只搜歌名；电视版会多一个“ - ”），对每个视频结果：

1. 分区是 `音Mad`、`音乐现场`、`翻唱`、`学科科普`、`运动综合` 的丢掉。
2. 标题按“字母、数字、下划线、汉字”切词（小写）。
   - 歌名的词和歌手的词都连续出现：基础分 100000；
   - 否则时长差超过 20 秒的丢掉；
   - 只出现其一：10；
   - 有任何一个查询词出现：5；
   - 查询和标题有连续 4 个以上相同汉字：0；
   - 都不满足：丢掉。
3. 分区是 `MV`、`音乐综合`、`电台`：加 1000。
4. 减去时长差（秒）。
5. 加 5 × log10(播放量)。

取最高分，同分保留搜索顺序。逐首搜索之间隔 1.2 秒（参考项目的节奏，搜索太快会 -412）。

## 留给后续

| 内容 | 去向 |
|---|---|
| 视频页、详情页、播放页、评论区、动态、UP 主空间、收藏夹、稍后再看、历史、搜索页、番剧时间表和索引页、会员集的试看提示 | M14.3 |
| DASH 播放：把 `VodStreams.videoFor` 的视频档和 `bestAudio` 的音频档交给播放器（mpv `audio-files` 外挂音轨，两条都带 `headers`），线路回退用 `linesOf`；在 `expiresAt` 前重新取流；MP4 作为备选 | M14.3（需要 T04b.1 的会话支持外挂音轨） |
| 点播弹幕的显示（按 6 分钟分段预取，`isPlain` 以外的高级弹幕不画）、字幕显示 | M14.3 |
| 进度上报的节奏（电视版每首开始报一次；网页每 15 秒报一次） | M14.3 |
| 音乐页、播放器、歌词显示和手选、歌单导入对话框（平台选择、进度、可取消）、每日推荐页、音频缓存的预取和设置项（上限、清空）、第三方地址设置和说明 | M14.4 |
| `VodKeyValueStore`、`AudioCacheFiles` 的实现（`live_store`、`dart:io`），播放队列的保存和恢复（`MusicTrack.toJson`） | M14.4 |
| 所有用户能看到的文字（`SiteError` 的提示、来源名 `bilibili`/`rangotec` 等的中文名） | M14.3/M14.4 的 i18n |

## 依赖和门禁

- 根 `pubspec.yaml` 的 `workspace:` 加 `packages/live_vod`；根 `pubspec.lock` 没有变化（没有新的第三方包）。
- `tools/gate/check_deps.py`：`ALLOWED` 加 `'packages/live_vod': {'live_core', 'live_net'}`，`PURE_DART` 加它，`apps/pure_live` 可以依赖 `live_vod`。`gate.sh` 从根 `pubspec.yaml` 读成员，不用改。
- 没有改其他包。

## 样本

`fixtures/live_vod/<编号>-<情况>/`，`body.*` 和 `meta.json`（格式同其他平台，`tool` 写明是 scratchpad 里的 Python 录制脚本，不进仓库）。

- 脱敏：请求里的游客 buvid 换成同形的合成值；取流地址里的 `oi=`（客户端地址的整数）换成 `3405803783`（203.0.113.7），`upsig`、`trid`、`qn_dyeid`、`e=` 换成同形的合成值；`x/player/wbi/v2` 的 `ip_info`（地址、机房地址、地区）换成文档段和“北京”；搜索的 `seid` 换成同长度的 1；弹幕的 midHash 换成同长度的合成值；酷狗的 `userid` 清零。响应头只留 `content-type` 和 `bili-status-code`。
- 截短：排行、相关推荐、搜索、弹幕分段、网易云、酷狗、rangotec 的长列表只留前几条（`meta.json` 的 `scrubbed` 里记了 `trimmed`）。
- 门禁的 `fixture privacy` 通过；另外检查过样本里没有录制时的出口地址（明文和整数）和真实 buvid。

## 测试

48 个用例（`dart test`），全部通过：

- `parse_test.dart`（23）：每个样本的解析；DASH 的画质选择、编码偏好、最好的音频档、到期时间和线路；会员集试看；评论游标；游客的 -101、-352、-404；弹幕分段、XML 和“未知字段不错位”；网易云、酷狗、rangotec、lrc.cx、BGM 歌词。
- `client_test.dart`（10）：取流不带游客 buvid、其他请求带；登录后 Cookie 和 csrf；WBI 签名和 -352 续签一次、第二次报 `RiskControl`；写接口和个人列表未登录不发请求；进度上报的表单；评论游标原样发出；番剧时间表和季详情回放；音乐补 cid、取音频档；BGM 歌词跟随文件地址。
- `music_test.dart`（15）：匹配器（录下的“晴天 - 周杰伦”搜索、各条打分规则、汉字连续匹配）、导入（间隔、进度、取消）、第三方地址设置、分享链接识别、LRC 各种写法和 offset、标题清理和比对、歌词链（校验、存储、手选、候选列表）、队列（顺序、单曲、洗牌、插队、删除、移动、失败上限）、每日推荐（筛选、当天缓存、换收藏夹、历史）、音频缓存（键、提交、LRU、保留、残留文件）。
