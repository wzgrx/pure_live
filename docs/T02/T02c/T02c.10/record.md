# T02c.10 YouTube

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/youtube/`（`youtube_api.dart` 纯解析和链接规则，`youtube_site.dart` 请求编排）
- 样本：`fixtures/youtube`，22 个真实接口录制和 1 组聊天帧：
  - 9 个来自归档（2026-09-27，经代理）：直播频道页 `S01-browse-live`、直播搜索 `S02-search-p1`/`-p2`、`navigation/resolve_url` 的 `S03-*`、ANDROID `player` 的 `S04-player-live`/`-missing`、频道 RSS `S05-feed-offline`。它们是归档 v4 设计的 InnerTube 请求，v3 一个都不发，所以没有 `expected.json`；`S04` 的两个 `player` 回答用来测“只读 `player`”的恢复路径；
  - 13 个本模块补录（2026-09-28 12:23，同一分钟，经代理 `127.0.0.1:7897`），都是 v3 自己的请求，请求头、`player` 的请求体和 `key` 与 v3 逐字相同：
    - `S07-channel-live`（`/@LofiGirl/live`）、`S07-watch-live`、`S07-player-live`、`S07-hls-live`：在播的频道页，它指向的直播（`nI725iVsyoQ`）的观看页、`player` 回答和 HLS 主列表；
    - `S08-channel-offline`：未开播频道（`UCX6OQ3DkcsbYNE6H8uQQuVA`）的 `/live` 页；
    - `S09-*`（已结束的直播 `9njefMDxzqw`）、`S10-*`（预告 `32myp8UqPOE`）、`S11-*`（普通视频 `dQw4w9WgXcQ`）、`S12-*`（不存在的 `aaaaaaaaaaa`）：各一个观看页和 `player` 回答；
  - 聊天帧 `danmaku/S06-live`（T06a 用）。
- 参考：
  - 归档 v4 的 YouTube 适配器和规格（`spec/sites/youtube.md`）。规格没有 REG-YOUTUBE 条目，只有 §10“踩过的坑”三条（见“回归条目的覆盖”）；
  - pure_live_TV `lib/platforms/youtube/`：与 v3 逐行相同，只改了导入路径和两处可空标注（`onlineViewers: current ?? ''`），没有行为修复（对照笔记 `small_diffs.txt`、`sub_B.md` 的 youtube 一节）。

照 T02a.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称和顺序、列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变。v3 实现过的可选能力全部保留：目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `youtube_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、取流（`LivePlayUrlResolver`）、恢复（`LivePlayRecoveryResolver`）、租期查询（`LivePlayLeaseMetadata`）。另加 `LiveSiteLinks`。
- **房间身份与 v3 一致：房间号是 11 位视频 id**（一场直播一个）。v3 的详情返回请求的视频 id，链接和搜索里的频道都先换成它当前的直播；3.x 存下的关注就是视频 id。频道号记在 `userId`（v3 同样）。
- **请求照 v3**：全部匿名，以 `youtube` 的名义发出（代理由应用按平台注入），25 秒时限（v3 的接收时限），跟随跳转（v3 的 dio 最多 5 次）：
  - 页面请求头：Chrome 140 UA、`Accept`、`Accept-Language: en-US,en;q=0.9`、同意页 Cookie `SOCS=CAI`（v3 的常量，欧盟出口不会被带到同意页）、`Referer` 为观看页（频道页是站点根）；
  - 房间：观看页 `watch?v=<id>`（取 `INNERTUBE_API_KEY`、网页版的 `ytInitialPlayerResponse`、`ytInitialData`），再 `POST youtubei/v1/player?key=<key>`，请求体是 v3 的 ANDROID 客户端（`platform: DESKTOP`、`clientScreen: EMBED` 等，逐字相同），两份回答按 v3 合并（`player` 的字段优先）；
  - 进房和录制时，直播中的房间再读 HLS 主列表（媒体请求头），共 3 个请求；刷新和开播状态 2 个；未开播的房间都是 2 个；
  - 搜索：只找一个引用（视频 id、视频链接、`@handle`、3～30 个字符的裸名字、频道链接）；频道先读它的 `/live` 页（1 个请求）找当前直播，再读房间（2 个请求），卡片是刷新深度（没有流）。只有第 1 页；
  - 没有分类、推荐和目录（v3）：推荐为空、目录是一页空列表，都不发请求。
- **状态照 v3**：
  - 私密、需要登录、年龄或内容确认（`isPrivate`，`LOGIN_REQUIRED`/`AGE_CHECK_REQUIRED`/`CONTENT_CHECK_REQUIRED`，原因里有 sign in、private）：封禁；
  - `isLive`（或网页微格式的 `liveBroadcastDetails.isLiveNow`）且状态 `OK`：直播中；
  - 其他直播内容（已结束、预告、直播中但不能播放）和 `LIVE_STREAM_OFFLINE`：未开播；
  - 没有任何状态：未知；
  - 其他（普通视频）：不是直播间，`NotFound`（v3 的 `notLive`）。
- **卡片和房间照 v3**：标题、主播名（`author`，必须有，否则 `ApiChanged`）、封面和头像都是视频缩略图（最后一张 `ytimg.com`/`ggpht.com` 的 https 图片，超过 64 张不取），分区是网页微格式的 `category`（没有时 `YouTube Live`），简介 `shortDescription`，链接是观看页，公告是 3.x 的中文 `youtube_chat_notice`，房间带 v3 的媒体请求头（`httpHeaders`，3.x 的 JSON 里有）。在线人数只在直播中取，来自观看页里 `isLive` 的 `videoViewCountRenderer`（“1,256 watching now”），口径是在线人数。
- **画质和线路照 v3**：
  - 来源：HLS 主列表拆成各个变体（按高度，帧率超过 30 时写进名称，如 `720p60`），主列表读不到或不合 v3 的规矩（重复的画质 id、超过 64 个变体、属性不合规、变体地址不在 YouTube 媒体主机上）时，改为主列表本身“HLS 自动”；再加 `player` 回答里带明文地址的渐进格式（`http:<itag>`，最多 64 个）和 DASH 清单（“DASH 自动”）；
  - 名称、id、排序与 v3 相同：`1080p · H264 · HLS`（id `hls:1080:0:h264`）、`HLS 自动 · HLS`（`hls:auto`）、`360p · H264 · HTTP`（`http:18`）、`DASH 自动 · DASH`（`dash:auto`）；排序值是高度 × 1000 + 帧率 + 协议（HLS 30、渐进 20、DASH 10），从高到低，同值按 id；
  - 每个来源一条线路：带 v3 `PlaybackHeaderResolver` 里 YouTube 的媒体请求头（UA、`Referer` 为观看页、`Origin`），格式（HLS；渐进文件是 `other`；DASH 不标），编码（`avc`、`hevc`、`vp9`、`av1`），线路编号是主机名；
  - 租期：地址的 `expire` 查询参数或 `/expire/<秒>/` 路径段（签发后约 6 小时），提前 10 分钟续期（v3 的 `getPlayUrlRefreshAt`），过期不切断已建立的连接；`LivePlayLeaseMetadata` 仍然按地址给出同一份时间；
  - 确认的画质就是请求的画质 id（v3）。
- **进房时的流数据**（`YouTubeRoomData`）：直播中的房间在进房时读好全部来源；来源读不出来（`player` 没有任何来源、地址不在 YouTube 主机上）时房间照常打开，取画质时报错。刷新不带流数据（v3 同样）。
- **恢复**：只请求 `player`（用最近一次观看页的 `key`，没有时用 v3 内置的公开 key）和 HLS 主列表（请求的是 HLS 变体时才读），不再读 1.4 MB 的观看页。画质 id 不在新回答里、或已经不是直播，就报错，不悄悄换档（v3 同样）。
- **链接照 v3 的 `YouTubeLink`**：http(s)、`youtu.be`/`youtube.com`/`youtube-nocookie.com` 及其子域、没有用户名和片段（`#`）：
  - 视频链接（`youtu.be/<id>`、`watch?v=<id>`、`live/<id>`、`embed/<id>`、`v/<id>`）不发请求，直接得到房间号（v3 的 `parseDurableVideoId`，网页搜索的链接识别也用它）；
  - 频道链接（`@handle`、`channel/UC…`、`c/<名>`、`user/<名>`，都可带 `/live`；`embed/live_stream?channel=UC…`）要请求一次频道的 `/live` 页（经 `ShortLinkSession`，不跟随跳转，跳转目标交给链接解析重新解析），按 v3 的顺序找当前直播：最终地址是视频、`<link rel="canonical">` 是视频、页面播放器正在直播、`ytInitialData` 里第一个看起来在直播的视频；频道没开播就没有结果（v3 抛 `notLive`，工具箱同样提示“解析失败”）。
- **没有弹幕参数、没有登录**：v3 的 YouTube 是 `EmptyDanmaku`，传给弹幕连接的参数为空，所以没有弹幕参数类；没有账号和 Cookie 设置，所以不注入 `CookieVault`。

## 审查发现的 v3 问题

位置简写：`A` = `legacy/lib/core/site/youtube/youtube_api.dart`，`S` = 同目录的 `youtube_site.dart`，`L` = `youtube_link.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 不存在的视频报“身份不符”（`identity`），而且搜索一个不存在的 11 位 id 时整个搜索报错，不是“没有结果”（冻结输出 `S12-watch-missing`） | A:228-232；S:134-137 | 先核对 `videoDetails.videoId` 与请求的 id，再看播放状态；不存在的视频没有 `videoDetails`。搜索只把 `missing`、`notLive` 当成“没有结果” | 没有 `videoDetails` 时按状态分：`ERROR` 是 `NotFound`，需要登录是 `NeedsLogin`，`UNPLAYABLE` 是 `StreamUnavailable`，其他 `ApiChanged`；搜索得到空列表 |
| 2 | 直播中的房间只要取不到来源（`player` 没有任何地址），或任何一个地址不在 YouTube 媒体主机上，整个房间打不开，录制详情也失败 | S:88-94；A:293、A:342、A:358 | 进房时就检查来源，列表为空抛 `mediaUnavailable`，地址不合规抛 `schema`（后两处在 try 之外） | 房间照常打开（直播中），取画质时报 `StreamUnavailable` 或 `ApiChanged` |
| 3 | 列表卡片、刷新得到的房间、存下的关注取画质都报 `identity`，只能先进房 | S:140-151 | 画质只从进房时 `data` 里的 `YouTubeRoom` 读，没有就报错 | 先发进房的 3 个请求再给画质 |
| 4 | 明确未开播或封禁的房间取画质得到空列表，播放器拿不到原因 | S:155 | 直接返回 `[]` | 未开播 `StreamUnavailable`，封禁 `NeedsLogin`，都不发请求 |
| 5 | 恢复时重新读整个房间：约 1.4 MB 的观看页、`player`、HLS 主列表 | S:174-176 | 用 `getRoomDetail` 取新地址 | 只请求 `player` 和（HLS 变体时）主列表；结果相同 |
| 6 | 平台层调用界面翻译（公告、两个“自动”画质名），公告按当时的界面语言写进房间，随关注存下 | S:75、S:160-163 | `i18n` 写在适配器里 | 写 3.x `zh.json` 的中文（与中文界面下 3.x 存下的相同），界面翻译在 M13 |
| 7 | 错误没有类型：11 种 `YouTubeFailure`；跳转等 3xx 算“传输错误”；调用方传错页码或分区报“结构变化” | A:11-32、A:447-455；S:43 | 平台自己的异常 | 类型化错误：401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，400 和空回答、结构不符 `ApiChanged`，5xx 和其他状态 `NetworkFailure`；取消原样抛出；页码和分区错误是 `ArgumentError`，不发请求 |
| 8 | 平台层用全局 `HttpClient`，自己实现流式读取（16 MiB、严格 UTF-8、25 秒） | A:117-170 | 结构问题 | 注入 `LiveHttp`，请求时限 25 秒（v3 的值）；不再有 16 MiB 上限，非法 UTF-8 按替换字符处理（同 SHOWROOM、TwitCasting 的处理） |
| 9 | 媒体请求头按平台写在播放层；续期时间另走 `LivePlayLeaseMetadata` | phr:186-187；S:203-222 | 诊断报告里的“旁路” | 线路自带请求头和租期，`LivePlayLeaseMetadata` 仍保留 |
| 10 | 字段类型稍有不符（布尔写成字符串、标题是数字）整个房间报 `schema` | A:614-626 | `_text`、`_bool` 对类型严格 | 只认 `true`，其他值按文字读；必填的标题和主播名仍然要有 |
| 11 | 直播中但本客户端不能播放（`UNPLAYABLE`、地区限制）的直播显示为未开播 | A:254-262 | 只有 `OK` 算直播，其余直播内容一律“未开播” | 按 v3 保留（用户看到的分组不变），`YouTubeVideo.playability` 记下原因；升级候选 5 |
| 12 | 头像是视频缩略图，不是频道头像 | S:61-62 | 只读 `videoDetails.thumbnail` | 按 v3 保留；升级候选 4（观看页里有频道头像） |
| 13 | 关注的是“这一场”：频道下次开播换了视频 id，关注就对不上；频道链接只能打开当前那场 | S:57；`legacy/lib/common/utils/live_url_tool.dart:235-240` | 以视频 id 为房间身份 | 按 v3 保留（身份必须与 3.x 存下的关注一致）；升级候选 1 |
| 14 | 频道页找直播时，`ytInitialData` 里任何带 `"label":"live"` 子串的视频都算直播，可能误认 | A:538-544 | 按编码后的文字匹配 | 按 v3 保留（样本里没有误认） |
| 15 | 搜索一个 3～30 个字符的普通单词（如 `lofi`）会当成 `@lofi` 去请求频道页；11 个字符的单词（`hello_world`）当成视频 id | L:48-56、L:68-72 | 搜索只支持精确引用 | 按 v3 保留（搜索页的能力表写明“频道查找”） |
| 16 | 带片段的链接（`watch?v=<id>#t=1`）不识别 | L:15 | 有意拒绝 `#` | 按 v3 保留 |
| 17 | 每次刷新关注都下载约 1.4 MB 的观看页，只为了在线人数和 `key` | A:197-200 | 在线人数只在观看页里 | 按 v3 保留（请求次数和内容不变）；升级候选 6 |

## 样本与 v3 的冻结输出

归档没有 YouTube 的 `expected.json`（旧版对照工具只做了前五个平台，v3 也构建不了），而且归档的样本是归档 v4 的 InnerTube 请求，v3 不发。所以本模块先补录 v3 自己的请求，再用 `fixtures/youtube/legacy_expected.dart` 生成冻结输出。

**补录**（13 个样本，同一分钟，脚本不入库，做法同 T02b.5 映客）：

- 请求逐字照 v3：请求头、`player` 的请求体、观看页里的 `key`（就是 v3 内置的公开 key）、主列表地址取自 `player` 回答；
- 观看页和频道页只保留 v3 读取的部分：canonical 链接、`INNERTUBE_API_KEY`、`ytInitialPlayerResponse` 和 `ytInitialData`（观看页的 `ytInitialData` 只留 `contents.twoColumnWatchNextResults.results` 和 `currentVideoEndpoint`，去掉约 30 万字节的相关推荐）。每个页面都按 v3 的算法在原始页和精简页上各取一次（两个对象、`key`、canonical、在线人数、频道页的直播查找），结果必须相同；新代码在原始页和精简页上的结果也逐字段相同。`meta.json` 的 `raw` 记的是原始页的长度和 SHA-256，`trimmed` 写明保留了什么；
- 脱敏沿用归档规则（`visitorData`、`heartbeatServerData`、`serializedExperimentFlags`、`botguardData`、`playerAttestationRenderer`，参数 `vm`、`cpn`、`plid`、`ei`、`of`、`sig`、`ip`），并补上归档漏掉的：路径段 `/ip/`、`/mip/`、`/sig/`、`/lsig/`、`/ei/`，参数 `lsig`、`mip`、`pot`，百分号编码在 `signatureCipher` 里的同名参数，统计参数里的 `visitor_data`。出口 IP 一律换成 `203.0.113.7`，其余换成同形的合成值（百分号转义原样保留），同一个原值在所有样本里换成同一个值，所以 `player` 回答里的主列表地址仍然指向主列表样本。任何原值（6 个字符以上）或其他 IPv4 地址残留，脚本就拒绝写入；
- `Set-Cookie` 等响应头不记录；`SOCS=CAI` 是 v3 的常量，不算机密。

归档的 `S02-search-*`、`S04-player-*` 在 `serviceTrackingParams` 里还留着真实的 `visitor_data`（匿名访客编号），归档的规则没有覆盖。合并时已把这 4 个值换成同形的合成值，其余内容与归档相同；适配器不读这个字段。

**生成**：`legacy_expected.dart` 把 v3 的 `YouTubeApi`、`YouTubeSite`、`YouTubeLink` 原样搬进一个 Dart 脚本（只去掉导入、基类、`@override` 和弹幕 getter）。v3 本来就把传输做成可注入的函数（`YouTubeRequest`），所以只换了它：按方法、主机、路径、查询参数和（POST 的）JSON 请求体读样本，非 200 的正文为空（同 v3），最终地址就是请求地址（样本没有跳转）；没有样本的请求抛 StateError 并记在 `unmatched`。`i18n` 换成用到的三个键的中文；Dio 的 `CancelToken`、`DioException`、`Headers` 和 v3 的模型只搬用到的部分；网络路径上的 `_defaultRequest`、`readBody` 没有搬，所以 `YouTubeApi` 必须传 `request`、`YouTubeSite` 必须传 `api`。输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求（方法、地址、请求头）。运行：`dart run fixtures/youtube/legacy_expected.dart`。

7 个样本有 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S07-watch-live` | 与 `S07-player-live`、`S07-hls-live` 一起：进房、刷新、录制、开播状态、v3 进房时的全部来源、画质、每档地址和租期、恢复、刷新后的房间取画质；按视频 id 和三种视频链接搜索、翻页、空白和自由文字；推荐、目录、目录说明、平台名；别的平台、非法 id、没有数据的卡片、未开播卡片 |
| `S07-channel-live` | 与 S07 其余样本一起：4 种频道写法（`@LofiGirl`、`LofiGirl`、频道链接、带 `/live`）的引用解析和搜索；38 个链接的 `YouTubeLink.parse` 和 `parseDurableVideoId`，11 个搜索词的 `parseOrReference`，`videoUrl`，5 个地址的租期 |
| `S08-channel-offline` | 未开播频道的引用解析（`notLive`）和搜索（空） |
| `S09-watch-ended`、`S10-watch-upcoming` | 与各自的 `player` 样本一起：三种深度、开播状态、画质（空）、恢复、搜索 |
| `S11-watch-video`、`S12-watch-missing` | 与各自的 `player` 样本一起：各入口的错误、搜索 |

`S07-player-live`、`S07-hls-live` 和各个 `player` 样本没有单独的 `expected.json`，随观看页一起回放。

## 与 v3 输出的对照

对照方式：用同一份录下的回答跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和 `data`；地址、确认的画质、租期逐条比较；请求比较方法、地址和请求头（名称不分大小写）。

| 样本 | 结果 |
|---|---|
| S07 直播 | 三种深度的房间一致（标题、主播、频道号、缩略图、分区 `Music`、在线 1256、公告、媒体请求头、链接）；请求一致（进房、录制 3 个，刷新、开播状态 2 个，请求头逐项相同）；v3 进房时的 7 个来源（6 个 HLS 变体、DASH）和 7 档画质的名称、id、排序一致；每档的地址、确认的画质、失效和续期时间一致 |
| S07 搜索 | 视频 id 和三种视频链接：卡片和 2 个请求一致；4 种频道写法：卡片和 3 个请求（频道页、观看页、`player`）一致；翻页、每页 0 条、空白、`lofi girl`：空，都不发请求，一致 |
| S07 恢复 | 地址和确认的画质一致；现在 2 个请求（`player`、主列表），v3 是 3 个（多一个观看页） |
| S07 刷新后的房间取画质 | v3 报 `identity`；现在先发进房的 3 个请求，得到同样的 7 档（问题 3） |
| S07 链接 | 38 个链接、11 个搜索词、`videoUrl`、5 个租期地址全部一致 |
| S08 未开播频道 | 找不到直播，搜索为空，1 个请求，一致 |
| S09 已结束、S10 预告 | 三种深度的房间一致（未开播、没有在线人数）；v3 取画质是空列表，现在是 `StreamUnavailable`，都不发请求（问题 4） |
| S11 普通视频 | v3 各入口报 `notLive`，搜索为空；现在是 `NotFound`，搜索为空 |
| S12 不存在 | v3 各入口报 `identity`，搜索也报错；现在是 `NotFound`，搜索为空（问题 1） |
| 目录和推荐 | 推荐为空、目录一页空列表、目录说明键、平台名 `YouTube Live` 一致；v3 对第 0 页和分区报 `schema`，现在是 `ArgumentError` |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 不存在的视频是 `NotFound`，搜索它得到空列表 | 问题 1。v3 本意就是“不存在则没有结果”，只是身份检查先失败 |
| 2 | 直播中但取不到来源的房间照常打开，取画质时报错 | 问题 2。房间资料和状态与 v3 相同，只是失败的位置从“进房”移到“播放” |
| 3 | 没有流数据的房间取画质时先发进房的请求 | 问题 3 |
| 4 | 未开播取画质报 `StreamUnavailable`，封禁报 `NeedsLogin` | 问题 4 |
| 5 | 恢复只请求 `player` 和主列表（v3 3 个请求，现在 1～2 个） | 问题 5。结果相同 |
| 6 | 错误是类型化的 `SiteError`，调用方错误是 `ArgumentError`，都不发请求 | 问题 7 |
| 7 | 线路带媒体请求头和租期，值与 v3 的 `PlaybackHeaderResolver`、`getPlayUrlRefreshAt` 相同 | 问题 9 |
| 8 | 不再有 16 MiB 上限和严格的 UTF-8 校验；字段类型不再严格 | 问题 8、10。只在 v3 整个失败时有区别 |
| 9 | 频道链接的解析经 `ShortLinkSession`，不跟随跳转，跳转目标重新解析；没开播时没有结果 | 链接解析的统一做法（T02d.1）。v3 跟随跳转并看最终地址；没开播时抛异常，工具箱同样提示“解析失败” |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **房间号是视频 id**。归档 v4 让频道 id 也能当房间（每次经 `navigation/resolve_url` 找当前直播，未开播时读 RSS 拿名字），关注就不会随每场直播失效；但 3.x 存下的关注都是视频 id，改身份会让它们对不上。列为升级候选 1。
- **没有推荐、目录和关键词搜索**。归档 v4 用“直播”频道页（`browse`，`UC4R8DWoMoI7CAwX8_LjQHig`）做推荐，用带“直播”过滤器的搜索（续页令牌翻页）；v3 的推荐为空、搜索只查精确引用，界面有目录说明。列为升级候选 2，样本 S01、S02 已复制。
- **画质按 HLS 变体拆开，另有渐进格式和 DASH**（v3、上游 TV）。归档 v4 只给一档“自动”，会改变画质菜单和已存的画质 id。
- **在线人数取自观看页**（v3、上游 TV）。归档 v4 的详情不读观看页，只有累计观看数。
- **受限视频（需要登录、年龄验证、私密）照常显示详情，状态是封禁**（v3、上游 TV）。归档 v4 在详情就抛 `NeedsLogin`，关注的卡片会刷新失败（对照笔记 `sub_B.md` 待补清单第 3 条也建议按 v3）。
- **提前 10 分钟续期**（v3）。归档 v4 提前 30 分钟。
- **媒体请求头带 UA、`Referer`、`Origin`**（v3）。归档 v4 只带 UA。
- **`player` 带观看页的 `key`，请求体是 v3 的 ANDROID 客户端**（`platform`、`clientScreen` 等字段）。归档 v4 不带 `key`，客户端字段是 `hl`、`gl`。
- **进房读观看页、`player` 和主列表，刷新读观看页和 `player`**（v3）。归档 v4 不读观看页。
- **没有聊天**。归档 v4 用 `next` 加 `live_chat/get_live_chat` 轮询聊天；v3 没有，列为升级候选 3。
- 平台名 `YouTube Live`（v3 的 `name`）；归档 v4 是 `YouTube`，上游改成了多语言文字。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 可以关注频道：频道 id 当房间，每次经频道的 `/live`（或 `navigation/resolve_url`）找当前直播，未开播时显示频道名 | 关注的是一场直播，频道下次开播要重新关注 | 问题 13；归档规格 §1、§4.1；样本 S03、S05 |
| 2 | 推荐用“直播”频道页，搜索用带“直播”过滤器的关键词搜索并能翻页 | 推荐为空，搜索只查精确引用 | 归档规格 §2、§3；样本 S01、S02 |
| 3 | 聊天当作弹幕：`next` 取续页令牌，`get_live_chat` 按 `timeoutMs`（1～5 秒）轮询，付费留言按聊天行显示 | 没有聊天 | 归档规格 §7；聊天帧样本 `danmaku/S06-live` 已复制（T06a） |
| 4 | 头像用频道头像（观看页 `videoSecondaryInfoRenderer.owner.videoOwnerRenderer.thumbnail`） | 头像是视频缩略图 | 问题 12；S07 观看页样本里有 |
| 5 | 直播中但不能播放的直播显示为直播中，取流时报 `StreamUnavailable`/`RegionBlocked` | 显示为未开播 | 问题 11 |
| 6 | 刷新关注不再下载约 1.4 MB 的观看页：只用 `player` 定状态，在线人数另取（如 `next` 回答里的 “N watching”） | 每次刷新 2 个请求、约 1.6 MB | 问题 17；对照笔记 `sub_B.md` 待补清单第 4 条 |

> 2026-09-28 用户答复全部采用，落地见文末“升级落地（T02.U）”（23-1～23-6）。

## 回归条目的覆盖

归档规格没有 REG-YOUTUBE 条目。§10“踩过的坑”三条：

- 网页客户端的 `player` 回答“视频不可用”（需要浏览器证明）：用 ANDROID 客户端。测试核对请求体与 v3、录制样本逐字相同。
- 媒体地址绑定请求方的出口 IP（地址里的 `/ip/`）：接口和媒体必须走同一个出口。线路都带媒体请求头，走哪条代理由播放层决定（T04，见下表）。
- 频道页下载慢：v3 的做法（读频道的 `/live` 页，约 1.3 MB）按 v3 保留，只在搜索和解析频道链接时发生；刷新的同类问题是升级候选 6。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 目录说明（`youtube_directory_scope`）、公告（`youtube_chat_notice`）、画质名（`youtube_quality_*`）、平台名（`site_youtube`）的繁体和英文 | M13 多语言。本模块给出 3.x 的中文 |
| 搜索能力表：频道查找、不翻页、没有网页搜索（3.x `modules/search/search_capability.dart:64-68`） | M13 搜索页 |
| 外部打开观看页（3.x `modules/live_play/services/room_external_opener.dart:109-111`） | M13；地址由 `YouTubeLink.videoUrl` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:434-435`） | M13 |
| 平台列表升级时追加 YouTube（`favorite_room_controller.dart:77`，第 21 版） | T09b.1 |
| 人数口径（只有在线人数，3.x `common/models/live_room.dart:145-149`） | 已在 T02g.1 的 `audience.dart` |
| 媒体地址绑定出口 IP：播放和录制要与 `youtube` 的接口走同一个代理 | T04、T08a.1；应用的按平台代理（T03a.1 的 `ProxyPolicy`）在 T07a.1 注入 |
| 链接解析的请求以 `links` 的名义发出（`LinkParser` 的 `ShortLinkSession`），频道链接在需要代理的地区是否走 `youtube` 的代理 | M13 链接解析入口（M3 的 `LinkParser` 目前用一个站点名） |
| 聊天（v3 没有）；`getDanmaku()` | T06a（升级候选 3）；同 T02a.1，T06a 用一张“平台 → 弹幕连接”的表 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。嵌入 JSON 的提取（v3 的 `_embeddedObject`）和 HLS 主列表的读取按 v3 的规矩写在本平台文件里：v3 对 YouTube 主列表的要求（接受 `VIDEO-RANGE` 等属性，重复的画质 id 整体放弃）与通用的 `HlsMasterPlaylist`（遇到不认识的属性就失败）不同。

## 测试

69 个用例，`live_core` 共 2032 个，全部通过：

- `youtube_api_test.dart`（34 个）：逐个样本对照 v3 的输出——S07 的房间（三种深度）、观看页的 `key` 和 canonical、7 个来源、画质、每档线路（地址、确认的画质、租期、请求头、格式、编码、线路编号）；S09、S10 的未开播房间；S11、S12 的 `NotFound`（与 v3 的错误对照）；S07、S08 频道页；全部链接、搜索词、`videoUrl` 和租期地址；归档的 S04 `player` 回答（只读 `player` 时的直播房间、来源和不存在的视频）。另有 v3 规则的合成用例：封禁的几种写法、不能播放的直播仍是未开播、没有状态、别的视频和缺名字、没有 `videoDetails` 的三种错误、观看页补 `player` 缺的字段、缩略图主机和数量、渐进格式、媒体主机、HLS 变体的名称和 v3 拒绝的七种主列表、租期、`player` 请求、状态码、没有嵌入对象的页面、解码失败的嵌入对象。
- `youtube_site_test.dart`（35 个），用样本回放加少量合成回答：
  - 三种深度的请求（方法、地址、请求头、站点名、25 秒时限）和房间与 v3 一致，`player` 的 POST 请求体和内容类型，开播状态；
  - 已结束、预告、普通视频、不存在的视频，非法房间号不发请求，取不到来源的直播照常进房；
  - 画质和线路不发请求并与 v3 一致，租期查询，卡片和刷新后的房间先发进房请求，未开播和封禁不发请求，别的平台，卡片的直播已经结束，主列表读不到时的“HLS 自动”；
  - 恢复：请求和地址与 v3 一致（少了观看页），DASH 和“HLS 自动”不读主列表，画质没了或已下播报错，用最近一次观看页的 `key`；
  - 搜索：视频 id 和视频链接、4 种频道写法、未开播频道、普通和不存在的视频、翻页和自由文字不发请求、取消、其他错误不当成“没有结果”；
  - 目录和推荐不发请求，传输错误和状态码映射；
  - 链接（经 `LinkParser`）：视频链接不发请求，频道链接 1 个请求（v3 的请求头、不跟随跳转），未开播频道没有结果，跳转被重新解析，别的链接不识别；关注合并保留流数据，身份不变。

## 升级落地（T02.U）

- 日期：2026-09-29（T02c.10）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 23-1～23-6（“落地方式”只有 23-5、23-6 写了，其余按上面“后续升级候选”的原文做）；模型字段按 [T02g.2](../../T02g/T02g.2/record.md)。23-3（聊天）的连接属于 T06a，这里只给出它要的参数。
- 只改了本平台：`youtube_api.dart`（解析）、`youtube_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖。新样本 5 个（见下文）。
- 实测：2026-09-28 19:20～19:30 UTC，经本机代理（127.0.0.1:7897）、匿名，用适配器的请求头：`navigation/resolve_url` 的 7 种路径（在播的频道、只有预告的频道、未开播的频道、handle 的 `/live`、自定义名 `c/`、不存在的 handle、不存在的频道号）、`updated_metadata` 的 5 个视频（在播 2 个、预告、已结束、不存在）、`next`、不存在的频道号的 `/live` 页和 RSS。下面的结论来自这些回答。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 23-1 | **房间身份改成频道**：房间号是频道号 `UC…`（`UC` 加 22 位，`YouTubeApi.isChannelId`），`userId` 同样是频道号。`YouTubeApi.video` 给出的房间是视频所属的频道；链接在播时是这一场的观看页，不在播时是 `https://www.youtube.com/channel/<频道号>/live`（`YouTubeApi.roomLink`）。<br>- **进房、录制**：读频道的 `/live` 页。在播时它就是这一场的观看页（S07-channel-live），标题、频道头像、在线人数、开播时间、分区都在上面，再读 `player` 和主列表，共 3 个请求（与 v3 进房相同）；不在播时它是频道页，给出频道名、头像、简介（`YouTubeApi.channel`、`offlineRoom`），1 个请求；只有预告时再读预告的 `player`，2 个。`/live` 页点名的视频如果不属于这个频道，不算它的直播。YouTube 对不存在的频道号回 200 和“This channel does not exist.”（实测），没有频道信息，报 `NotFound`。<br>- **刷新**：见 23-6。<br>- **仍接受 3.x 的 11 位视频号**：进房读它的观看页和 `player`（v3 的请求），在播就返回频道的房间、放这一场；已结束、预告或普通视频时再读频道的 `/live` 页，因为频道可能正在播另一场。刷新读 `player`，在播再读 `updated_metadata`，否则再读 `navigation/resolve_url`。普通视频（不是直播）也换成它的频道（3.x 是 `notLive`）；不存在的视频仍是 `NotFound`。`resolveRoomId` 只换身份：频道号不发请求，视频号 1 个 `player` 请求，给 T09b.1 迁移用。<br>- **同一频道同时有几场直播**很常见（S02 第 1 页 20 行里 Lofi Girl 占 8 行）：列表、搜索里一个频道只出一张卡（第一张，站点的顺序），卡片的链接是这一场。适配器记住卡片、精确搜索、进房给某个频道展示的那一场 30 分钟（构造参数 `broadcastLifetime`，0 关闭；最多 256 个频道）：这期间进这个频道的房间直接打开那一场（观看页、`player`、主列表，3 个请求），那一场已结束或不存在时再读频道的 `/live` 页。刷新和开播状态不用它。<br>- **画质数据**：`YouTubeRoomData` 加了 `channelId`，`videoId` 是进房时在播的那一场；线路的 `Referer` 仍是这一场的观看页。恢复只请求这一场的 `player`（和主列表）；这一场结束就报错，播放器重新取详情时跟到频道的下一场。<br>- **链接**：视频链接仍不发请求，得到视频号（进房时换成频道、打开这一场）；`channel/UC…`、`embed/live_stream?channel=UC…` 直接得到频道号，不发请求（v3 读 1.3 MB 的 `/live` 页找当前直播）；`@handle`、`c/<名>`、`user/<名>` 经链接解析的会话 POST 一次 `navigation/resolve_url`（约 1 KB），得到频道号；YouTube 不认识的 handle 回 404，没有结果 | 关注的是频道：频道下次开播还是这一个关注，关注页照常刷新；未开播时关注卡片显示频道名（和上一场的标题）。列表、搜索里一个频道一张卡，点开是卡上那一场。粘贴频道链接、`@handle` 能打开和关注频道。3.x 存下的视频号关注在 T09b.1 迁移后换成频道（迁移前刷新不会合并，见“房间身份迁移规则”） | 平台层完成，余下 T09b.1/M13 |
| 23-2 | **推荐和目录**：WEB 客户端 `browse` 的“直播”频道页（`UC4R8DWoMoI7CAwX8_LjQHig`，`YouTubeApi.listing`）。只要在播的行（直播角标、`LIVE` 时长遮罩或“N watching”），已结束、预告的行不要；一个频道一张卡。这一页没有续页：第 1 页 1 个请求，之后的页为空、不发请求。S01：49 行，28 行在播，26 张卡。<br>**搜索**：精确引用（链接、`@handle`、频道号、裸视频号，`YouTubeLink.parseOrReference`）照旧查这一个，只有第 1 页；其余是带“直播”过滤器（`EgJAAQ%3D%3D`）的关键词搜索：第 N 页用第 N−1 页最后一个 `continuationItemRenderer` 的令牌（按关键词记，最多 16 个关键词），第 1 页重新开始，前面几页出过的频道不再出卡（跨页去重）。每页约 20 行，与 `pageSize` 无关；一页没有在播的行就没有下一页。`LiveSearchPaginationPolicy`：精确引用不翻页，关键词翻页。<br>3.x 把 3～30 个字符的裸名字当成 `@handle`（问题 15），现在是关键词（`LofiGirl`、`lofi` 按关键词搜）；11 个小写字母的词（`programming`）也是关键词；其余 11 位的词先当视频号查，查不到（`NotFound`）再按关键词搜。<br>**卡片**：房间号是频道号，标题、主播名、封面（这一场的缩略图）、频道头像（23-4）、在线人数（“N watching”）、直播中、链接是这一场的观看页；会员限定角标标 `subscribersOnly`，其他限制在卡片上看不出（留空）。缺视频号、频道号、标题或名字的在播行只跳过这一行，全部在播行都坏时 `ApiChanged`；`browse` 没有任何视频行时 `ApiChanged` | 推荐页有 YouTube 正在直播的频道；搜索任意关键词能找到直播并能翻页；输入 `@handle`、频道或视频链接仍直接找到那个频道 | 平台层完成，余下 M13 |
| 23-3 | 平台层：在播的房间（进房、刷新、录制、搜索卡片）带 `danmakuData: YouTubeDanmakuArgs(roomId: 频道号, videoId: 这一场)`，不多发请求。T06a 用 `YouTubeApi.webContext`、`apiUrl`、`apiHeaders` 请求 `next` 和 `live_chat/get_live_chat`（归档规格 §7，样本 `danmaku/S06-live`），付费留言按普通聊天行显示。`getDanmaku()` 仍是空的弹幕源 | 看不出变化；聊天在 T06a 接入 | 平台层完成，余下 T06a |
| 23-4 | 头像用频道头像：进房的观看页 `videoOwnerRenderer.thumbnail` 最大的一张（`yt3.ggpht.com`，S07 是 176 px）；未开播的频道页 `channelMetadataRenderer.avatar`（`yt3.googleusercontent.com`，头像允许这个主机，封面不允许）；列表卡片 `channelThumbnailSupportedRenderers`。刷新和只读 `player` 的地方没有频道头像，留空，合并时保留存下的 | 头像是频道头像，不再是视频截图 | 完成（T02.U） |
| 23-5 | 在播（`isLive` 或 `liveBroadcastDetails.isLiveNow`，且状态不是 `LIVE_STREAM_OFFLINE`）就是直播中，不管本客户端能不能播（3.x：受限的是封禁，不能播的是未开播）。受限类型（`YouTubeApi.restrictionOf`）：`OK` 为 `none`；私密 `private`；会员 `subscribersOnly`；年龄 `adult`；国家、地区 `regionBlocked`；付费、购买 `paid`；其他登录、内容确认 `needsLogin`；其余（`UNPLAYABLE`、`ERROR`）`unplayable`（按 `player` 的状态和原因文字；请求头是 `Accept-Language: en-US`，S10 的原因是英文。认不出的原因按状态码退回 `needsLogin` 或 `unplayable`，仍是直播中、仍报错）。进房时受限的直播不读主列表（2 个请求），`YouTubeRoomData.streamError` 记下原因，取画质时报：`regionBlocked` 为 `RegionBlocked`，`needsLogin`、`adult` 为 `NeedsLogin`，其余 `StreamUnavailable`（写明种类和 YouTube 的原因），都不发请求。不是直播的受限视频仍是封禁（3.x），带受限类型；已结束、预告的受限直播是未开播 | 受限直播显示为直播中，关注分组在直播中，卡片可以标出受限（M13），播放时说明原因 | 平台层完成，余下 M13 |
| 23-6 | 刷新不读观看页：`navigation/resolve_url`（频道的 `/live` 路径，约 1 KB）找到这一场，`player`（约 165 KB）给状态、标题、封面、受限类型，在播时 `updated_metadata`（3～160 KB，S13 是 Lofi Girl 的 157 KB，大半是周边商品）给在线人数（“1,331 watching now”，`YouTubeApi.viewers`）。在播 3 个请求（v3 2 个：约 1.4 MB 的观看页和 `player`），多的一个就是条目的“在线人数另取”；未开播 1 个，只有预告 2 个。在线人数请求失败时人数留空，不让刷新失败（取消照常抛出）。刷新没有头像、分区、开播时间（只有观看页有），都留空，合并时保留存下的；进房时读完整页面，更新标题和头像（落地方式）。开播状态（`getLiveStatus`）不要人数：1～2 个请求 | 刷新关注快得多、省流量（在播约 0.2～0.3 MB，v3 约 1.6 MB） | 完成（T02.U） |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 进房读的页面有：microformat 的 `liveBroadcastDetails.startTimestamp`（带时区的 ISO 时间，转 UTC；不在 2005～2286 年的不填），只在在播时填。S07：2026-09-23T16:47:51Z。刷新和卡片没有：ANDROID `player` 没有 microformat，`updated_metadata` 的 `dateText` 只有日期（“Started streaming on Sep 23, 2026”），列表行没有；留空，T02g.2 合并时保留同一场存下的 |
| 受限类型 | 23-5。`player` 回答（进房、刷新、精确搜索）在播时填 `none` 或种类，不在播不填；列表卡片只认会员角标，其余留空（看不出年龄、地区限制） |
| 受限直播改为直播中 | 23-5 |
| 占位信息 | 去掉 v3 的默认分区 `YouTube Live`（`defaultArea`）：没有分类时留空。刷新不读观看页以后，它会盖掉存下的真实分类（如 `Music`）。名字、标题没有占位；`navigation/resolve_url` 说未开播的频道，刷新时名字留空（关注保留存下的），搜索卡片读 RSS 取名字 |
| 回放、轮播、“不可播放” | 不涉及：直播结束后是普通视频，不是房间状态；房间是频道，结束就是未开播 |
| 画质命名 | 表里没有本平台的改名、合并条目，照统一原则保留 v3 的名称和 id（`1080p · H264 · HLS`、`hls:1080:0:h264` 等） |
| 默认编码 | 不涉及：直播的 HLS 主列表只有 H.264（S07 全是 `avc1`），渐进格式也是 H.264，DASH 由播放器选 |
| 房间身份 | 频道号、视频号都区分大小写，不加进 `SiteIds.caseInsensitiveRoomIds` |
| 按主播关注 | 23-1 |
| 容错 | 列表坏行只跳过（23-2）；在线人数取不到不影响刷新（23-6）；图片不合规只丢图片（v3） |
| 翻页 | 搜索按站点的续页令牌翻页，跨页按频道去重；推荐只有一页。没有本地切片，不涉及 20～30 秒快照 |
| 说明文字 | 目录说明 `youtube_directory_scope` 的 3.x 文字（“首阶段接入精确视频 ID……公开推荐目录与关键词分页仍按官网会话继续补齐”）已不对；说明文字是界面的，平台层不改文字键，只改了它的文档注释，建议的新文字见“留给其他模块”。房间公告 `youtube_chat_notice`（“远端聊天尚待接入……”）现在仍然成立，T06a 接入聊天后由 M13 改写 |

### 请求数

| 场景 | v3 / T02c.10 | 现在 |
|---|---|---|
| 进房、录制：频道在播 | —（3.x 没有频道房间） | 3（`/live` 页、`player`、主列表） |
| 进房：频道未开播 / 只有预告 | — | 1 / 2 |
| 进房：卡片、搜索或上次进房记住的那一场 | — | 3（观看页、`player`、主列表） |
| 进房、录制：3.x 的视频号在播 | 3 | 3（不变） |
| 进房：3.x 的视频号已结束或预告 | 2 | 3（再读频道的 `/live` 页）；频道正在播另一场时 5 |
| 刷新：频道在播 | —（v3 刷新视频号：2 个，约 1.6 MB） | 3（约 1 KB、165 KB、3～160 KB；多的一个是 23-6 的“在线人数另取”） |
| 刷新：频道未开播 / 只有预告 | — | 1 / 2 |
| 刷新：3.x 的视频号在播 / 已结束 | 2 / 2 | 2（`player`、`updated_metadata`）/ 2（`player`、`resolve_url`；频道正在播另一场时再加 2） |
| 开播状态 | 2 | 频道在播 2，未开播 1 |
| 推荐、目录 | 0（空） | 第 1 页 1，之后 0 |
| 搜索：关键词 | 0（3～30 个字符的名字当 handle：3） | 每页 1 |
| 搜索：视频号、视频链接 | 2 | 2（`player`、`updated_metadata`） |
| 搜索：handle、频道链接 | 在播 3 / 未开播 1（没有结果） | 在播 3（`resolve_url`、`player`、`updated_metadata`）/ 未开播 2（`resolve_url`、RSS） |
| 链接识别：视频 / `channel/UC…` | 0 / 1 | 0 / 0 |
| 链接识别：`@handle`、`c/`、`user/` | 1（约 1.3 MB 的 `/live` 页） | 1（约 1 KB 的 `resolve_url`） |
| 恢复 | 1～2（T02c.10） | 不变 |
| `resolveRoomId`（新） | — | 视频号 1，频道号 0 |

### 画质 id 对照（给 T09b.1）

没有变化，不需要对照：画质仍按 v3 拆 HLS 变体、渐进格式和 DASH，名称和 id 不变。

### 设置项

无。记住卡片那一场的时长是构造参数 `broadcastLifetime`（默认 30 分钟），不是用户设置。

### 房间身份迁移规则（给 T09b.1）

| 存下的房间号 | 新房间号 |
|---|---|
| 频道号 `UC…`（`UC` 加 22 位） | 不变 |
| 11 位视频号 | 调 `YouTubeSite.resolveRoomId('<视频号>')`：POST 一次 ANDROID `player`（请求同 v3，`youtube` 的代理路由），取 `videoDetails.channelId`。直播、已结束的直播、普通视频都有频道。纯函数是 `YouTubeApi.channelOf(player 回答, 视频号)` |

- 换身份时：JSON 的 `roomId` 换成频道号，`userId` 本来就是频道号；`link` 换成 `YouTubeApi.roomLink(频道号)`（或删掉，下次刷新补上）；名字、标题、头像、封面、标签、公告保留，下次刷新、进房更新。
- 合并：几个视频号关注是同一个频道，或者已经关注了这个频道时，按 T02g.2 的规则合并成一条（保留先关注的那条，合并标签）。
- 失败：`NotFound`（视频已删除，S12）换不了，保留原来的视频号（进房显示加载失败，由用户删除）；`NeedsLogin`（私密视频，匿名看不到频道）同样保留；网络等其他错误保留原值，下次启动再试。迁移前后适配器都接受视频号。
- 迁移前：适配器对视频号返回频道身份的房间，`mergeFrom` 因为身份不同会忽略它，所以关注刷新要排在迁移之后（测试 “a 3.x follow (a video id) is merged only once migrated”）。
- 迁移请求逐个发，不要并发。观看历史里的视频号可以不迁移：进房时适配器返回频道的房间，那一场还在播就打开它。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| T06a | 聊天（23-3）：在播房间的 `danmakuData` 是 `YouTubeDanmakuArgs(roomId, videoId)`；`next` 取 `liveChatRenderer` 的续页令牌，`live_chat/get_live_chat` 按 `timeoutMs` 轮询（归档规格 §7），请求用 `YouTubeApi.webContext`、`apiUrl`、`apiHeaders`，走 `youtube` 的代理路由；付费留言按普通聊天行显示。频道换了一场（聊天结束，或房间详情的 `videoId` 变了）要重新取。`getDanmaku()` 仍是空的弹幕源，接入时换成“平台 → 弹幕连接”的表 |
| T04、T08a.1 | 不变：线路自带媒体请求头和租期；媒体地址绑定出口 IP，播放、录制要与 `youtube` 的接口走同一个代理。房间是频道：一场结束后恢复报错，重新取房间详情就跟到频道的下一场。受限直播取画质时报 `RegionBlocked`、`NeedsLogin` 或 `StreamUnavailable`（带原因） |
| T09b.1 | 上面的身份迁移；按 T02g.2 存 `startedAt`、`restriction`。没有设置、画质要迁移 |
| M13 | 关注按适配器返回的房间号（用视频号或视频链接进房，得到的是频道）；未开播的频道房间标题可能为空，名字用 `displayNick`。卡片按 `restriction` 标受限（列表只能看出会员限定），发现页是否隐藏；开播时间只在直播中显示。搜索页的能力表（3.x `search_capability.dart:64-68` 写的是“频道查找、不翻页”）改成：关键词搜索正在直播的、能翻页，链接、`@handle`、频道号、视频号直接找（`supportsSearchPaginationFor`）。外部打开用房间的 `link`（在播时是这一场的观看页，否则是频道的 `/live` 页）。目录说明 `youtube_directory_scope` 改写，建议：“推荐是 YouTube 的‘直播’频道页，只列正在直播的；搜索会按关键词找正在直播的并能翻页，也可以输入视频或频道链接、@handle、频道号直接打开。关注的是频道，开播后自动跟到新的一场。暂不支持聊天。”英文：“Recommendations are YouTube's Live destination, live broadcasts only. Search finds live broadcasts by keyword, page by page; a video or channel link, an @handle or a channel id opens it directly. You follow channels, which lead to each new broadcast. Chat is not supported yet.” |

### 受阻和未核实

没有受阻的条目。以下没有样本，按字段实现、用合成数据测试：

- 受限的在播直播（会员限定、年龄、地区、付费、私密）：按 `player` 的状态和英文原因判断（`restrictionOf`）。这次没有找到可以匿名录制的这类直播。
- 同一频道几场同时在播时，`/live` 页和 `resolve_url` 选哪一场由 YouTube 决定（S07 录制时 Lofi Girl 的 `/live` 是 nI725iVsyoQ，S02 的第一场是 rFZHOHl-L8A）；从卡片进房由“记住那一场”保证打开卡片上的那一场，关注刷新显示 `/live` 那一场。
- 不存在的频道号：`resolve_url` 照样回“频道”（实测 `UCaaaaaaaaaaaaaaaaaaaaaa`），所以刷新看不出来，一直是未开播；进房（频道页的“This channel does not exist.”）和搜索（RSS 404）能认出是 `NotFound`。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（写明条目编号），并断言这些键确实变了：

- S07 三种深度（观看页和 `player`）：`roomId`（23-1）、`avatar`（23-4）。刷新（`resolve_url`、`player`、`updated_metadata`）另有 `area`、`watching`、`onlineViewers`（23-6；人数来自 7 小时后录的 S13）。
- S09、S10：`roomId`、`link`（23-1：不在播时是频道的 `/live` 页）、`avatar`（23-4）；S09 的刷新另有 `area`（23-6）。
- S11 普通视频：3.x 各入口报 `notLive`，现在是它的频道的房间（未开播，23-1）。
- 搜索：视频号、视频链接的卡片同刷新；`@LofiGirl` 等 3 种频道写法同刷新；`LofiGirl`、`lofi` 不再是 handle（23-2，`parseOrReference` 的两项）；S08 的未开播频道有了卡片（23-1）。
- 推荐：3.x 为空，现在是“直播”频道页（23-2）。

T02g.2 的新键（`startedAt`、`restriction`）和 `danmakuData`（23-3）单独断言。

### 新样本

2026-09-28 19:29 UTC 经本机代理录制，匿名，请求就是适配器的请求（WEB 客户端上下文、`prettyPrint=false`、`SOCS=CAI`）。`raw` 记原始回答的 SHA-256 和长度。脱敏的值（访客编号 `visitorData` 和统计参数里的 `visitor_data`，两处同一个值）换成同形的随机值（百分号转义原样保留），写入前检查原值都已不在，记进 `meta.json` 的 `scrubbed`。v3 不发这些请求，没有 `expected.json`。门禁的 `fixture privacy` 通过。

| 样本 | 内容 | 脱敏、精简 |
|---|---|---|
| `S03-resolve-handle-live` | `@LofiGirl/live` → `watchEndpoint` nI725iVsyoQ（handle 搜索） | 访客编号 |
| `S03-resolve-channel-upcoming` | Joel Osteen 的 `/channel/…/live` → 预告 32myp8UqPOE（与 S10 同一场） | 同上 |
| `S03-resolve-custom` | `c/LofiGirl` → Lofi Girl 的频道号（链接识别） | 同上 |
| `S03-resolve-handle-missing` | 不存在的 handle → 404 `NOT_FOUND` | 没有要脱敏的 |
| `S13-metadata-live` | nI725iVsyoQ 的 `updated_metadata`：1,331 watching now | 访客编号；只留适配器读的在线人数、日期、标题三个动作，去掉简介、周边商品、互动面板、轮询令牌等（`meta.json` 的 `trimmed`） |

归档的 S01～S05 现在也用上了（请求体与适配器的逐字相同）：S01 推荐、S02 搜索两页、S03 的三个 `resolve_url`、S05 RSS。

### 测试

本平台 103 个用例（T02c.10 是 69 个），`live_core` 共 3329 个，全部通过，门禁 `--all` 通过：

- `youtube_api_test.dart`（47 个）：S07 按频道身份对照 v3（三种深度）、开播时间、受限类型、聊天参数、`forVideo`；S09、S10 按频道身份对照 v3；S11 普通视频是频道、S12 不存在；频道页（S07 在播、S08 未开播的名字头像简介、不存在的频道）和 3.x 的查找顺序；`resolve_url` 的 7 个样本和 404、RSS 名字、`updated_metadata` 人数、WEB 请求体与录制逐字相同；S01、S02 的列表（在播行、一个频道一张卡、续页令牌就是第 2 页的请求）和坏行、会员角标；房间号和链接（频道号链接、`parseOrReference` 的两项变化）、`channelOf`；十种受限直播的受限类型和报错、非直播的受限视频、开播时间的写法；3.x 的来源、HLS 变体、租期、状态码。
- `youtube_site_test.dart`（56 个）：频道在播进房（请求、对照 v3）、真实的 `/live` 回答、3.x 视频号进房的 3 个请求、刷新的 3 个请求和对照、视频号刷新、开播状态、未开播频道（1 个请求、刷新合并保留名字）、只有预告的频道、3.x 的已结束和预告视频号、别的频道的直播不算、普通视频、不存在的视频和频道、非法房间号；来源读不出和受限直播（不读主列表、播放时报原因）；记住那一场（视频链接搜索、搜索卡片、目录、过期和关闭、那一场结束或不存在）；画质和线路、租期、卡片和刷新后的房间先进房、未开播和封禁不发请求、恢复（请求、DASH、画质没了、卡片、`key`）；搜索（视频、handle、频道号、未开播频道、不存在的 handle、普通视频、查不到再按关键词、关键词翻页和跨页去重、第 2 页要先有第 1 页、裸名字是关键词、不发请求的情况、取消、错误）；推荐和目录；传输错误、四种请求的状态码、人数失败不影响刷新；链接（不发请求的视频和频道号链接、handle 和自定义名各 1 个请求、不存在的 handle、别的链接）；关注合并、`resolveRoomId`、3.x 关注迁移前后。

## 后续（T06a 弹幕）

本平台的聊天（弹幕）已由 T06a.20 完成，见 [记录](../../../T06/T06a/T06a.20/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 T02 当时的情况，不再改动。
