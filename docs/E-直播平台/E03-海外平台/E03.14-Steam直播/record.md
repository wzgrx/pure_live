# E03.14 Steam 直播

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/steambroadcast/`（`steambroadcast_api.dart` 纯解析和链接规则，`steambroadcast_site.dart` 请求编排）
- 样本：`fixtures/steambroadcast`，11 个真实接口录制和 1 组聊天帧：
  - 7 个来自归档（2026-09-27）：热门直播两页 `S01-directory-p1`/`-p2`，`getbroadcastinfo` 的 `S02-info-live`/`-offline`，迷你资料 `S03-profile`，`getbroadcastmpd` 的 `S04-mpd-live`/`-offline`。其中 `S02`、`S03` 是归档 v4 设计的详情接口，v3 不发，所以没有 `expected.json`，留给升级候选 2；
  - 4 个本模块补录（2026-09-28 13:05，同一分钟，本机默认出口，不经代理），都是 v3 自己的进房请求，请求头与 v3 逐字相同：在播主播 `76561199485215572` 的直播页 `S05-watch-live`、`getbroadcastmpd` 的 `S05-mpd-live`、它指向的 HLS 主列表 `S05-master-live`，以及未开播账号 `76561197960287930` 的直播页 `S05-watch-offline`（与归档的 `S04-mpd-offline` 配对，同一个账号，回答不带时间）。归档没有录直播页和主列表，没有它们就无法对照 v3 的详情；
  - 聊天帧 `danmaku/S07-live`（D01 用）。
- 参考：
  - 归档 v4 的 Steam 适配器和规格（`spec/sites/steambroadcast.md`）。规格没有 REG-STEAM 条目，只有 §10“踩过的坑”两条（见“回归条目的覆盖”）；
  - pure_live_TV `lib/platforms/steambroadcast/`：与 v3 逐行相同，只改了导入路径和两处可空标注（`onlineViewers: viewers ?? ''`），没有行为修复（对照笔记 `small_diffs.txt`、`sub_C.md` 的 steambroadcast 一节）。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 v3 实现过的全部可选能力——目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `steambroadcast_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、取流（`LivePlayUrlResolver`）、恢复（`LivePlayRecoveryResolver`），外加 `LiveSiteLinks`。3.x 的 JSON 不变，平台名仍是 `Steam Broadcasts`。
- **请求照 v3**：全部匿名，以 `steambroadcast` 的名义发出（代理由应用按平台注入），带 v3 的请求头（Chrome 140 的 UA、`Accept`、`Accept-Language: en-US`、`Referer`，JSON 接口另带 `X-Requested-With`），**不跟随跳转**，不带 Cookie（v3 的 Steam 没有账号）。一次列表调用、一次房间调用（包括它的全部请求）共用一个 25 秒的总时限（v3 的 `_scope`），超时是 `NetworkFailure`，调用方取消原样抛出取消；单个请求 20 秒（v3 的接收时限，live_net 的默认值）。
- **目录照 v3**：
  - 一个分类 `Steam Broadcasts`，一个分区“热门社区直播”（`areaType: community`，`areaId: trending`），只在第 1 页、每页条数至少 1 时给出，不发请求；
  - 原生目录、推荐、分区房间都是 `apps/allcontenthome?l=english&browsefilter=trend&appHubSubSection=13&forceanon=1&p=<页>&broadcastsoffset=<(页-1)×10>&numperpage=10`（HTML 片段，每页 10 个 `Broadcast_Card`），页尾隐藏表单的 `p == 页+1` 且 `broadcastsoffset == 页×10`、本页有卡片时还有下一页；
  - 推荐和分区房间取该页的前 `pageSize` 个（最多 60，v3）；页码或条数小于 1 给空、原生目录页码小于 1 给空页，都不发请求（v3）；
  - 同一主播只留第一张卡片；卡片解析用 `live_core` 的 `HtmlElement`（v3 用 `package:html`），卡片里嵌套的作者链接、隐藏表单都与 v3 的结果相同。
- **卡片照 v3**：房间号和 `userId` 是 64 位 Steam id；标题是内容类型去掉 `: Broadcast`（即游戏名，列表没有直播标题），分区是游戏名；主播名取作者链接的文字，再取作者块，再取 id；封面只收 `steambroadcast.akamaized.net` 上本主播路径下的 https 缩略图（v3 的规则）；**头像显示封面**（v3 实际显示的，见问题 1）；`N viewers` 作为在线人数（口径 `onlineViewers`）；状态直播中；公告是 3.x 的聊天说明；房间带 v3 的 `httpHeaders`（3.x 的 JSON 里有）；`link` 是直播页。
- **搜索照 v3**（Steam 没有匿名的直播搜索）：Steam id 或直播页链接只在第 1 页查这个账号的房间（直播页和 `getbroadcastmpd` 两个请求，没有直播页的账号算没有结果）；其他关键词请求第 `page` 页目录，按 id、主播名、标题、游戏筛选（忽略大小写），取前 `pageSize` 个。空白、页码小于 1、条数不在 1～100 给空，不发请求。
- **房间照 v3**：
  - 直播页（`broadcast/watch/<id>`）：`#application_config` 的 `data-broadcastsinfo` 必须是同一个账号；主播名取 `og:title`（没有时取 `<title>`）`Steam Community :: <名字> :: Broadcast`，取不到写 `Steam broadcaster`。没有这个配置是 `NotFound`（搜索里算没有结果），账号对不上或配置坏了是 `ApiChanged`。不存在的账号也有直播页，标题写的是 id（2026-09-28 实测）；
  - `getbroadcastmpd?broadcastid=0&steamid=<id>&viewertoken=0&sessionid`：`success` 的 `ready` 是直播中；`unavailable`、`offline`、`not_live`、`no_broadcast` 是未开播；`user_restricted` 是“受限”，显示为状态未知并用 3.x 的受限公告；`waiting*` 和不认识的值是状态未知（v3）；标题是 `title`，空时写 `Steam Broadcast`（Steam 总是给空），分区写 `Steam Community`，没有封面和头像；`num_viewers` 作为在线人数（未开播时没有）；
  - **进房和录制详情另取 HLS 主列表并按 v3 校验**（三个请求；刷新两个）：变体和音轨都要在主列表同一主机、本账号路径 `/broadcast/<id>/…/hls_manifest/0/` 下，带 Steam 的 `broadcast_origin`，1～16 个变体；顺便读出 `CODECS` 里的视频编码；
  - **记住列过的主播**（v3 的 `_known`）：房间回答缺的主播名（为 id 或占位）、标题（占位）、游戏、封面、头像、人数从最近一次见到的卡片或房间补上，补完的房间再记下来。现在最多记 1000 个主播（v3 不设上限）；
  - 房间号是 64 位 Steam id，请求时写成直播页链接也一样（v3）；不是 id 的输入是 `NotFound`，不发请求；
  - 详情带 `SteamBroadcastRoomData`：Steam id、状态、进房时校验过的主列表和编码、媒体问题。界面按状态显示自己语言的公告（M13）。进房详情另带弹幕参数 `SteamBroadcastDanmakuArgs`（Steam id，不多发请求）。
- **媒体问题不再让房间失败**（问题 2、3）：`hls_url` 或 CDN 参数不合 v3 的规则、主列表取不到或校验不过，房间照样显示直播中，原因记在房间数据里，取流时报出（`ApiChanged`、`NotFound`、`NetworkFailure` 等）。v3 在这些情况下整个详情失败，关注刷新也失败。
- **取流照 v3，改为线路**：
  - 画质只有一档“自适应 HLS”（id `auto`），不发请求；
  - `resolvePlayUrlsRaw` 给出进房时校验过的主列表，确认的画质是 `auto`，不发请求；恢复时重新请求房间和主列表（三个请求，v3，REG-LEASE-005）；
  - 线路：HLS，编码取自主列表（样本是 `avc`），线路编号 `steamcontent`（CDN 主机每次回答都换，`cache6-lax1`、`cache7-lax1`，不能当线路身份）；**请求头为空**：v3 的 `PlaybackHeaderResolver` 没有 Steam 分支，播放器和录制器实际什么都不发（房间里的 `httpHeaders` 从未被用到），2026-09-28 实测不带请求头主列表照样 200；没有 `PlayLease`（地址不带到期参数，归档规格 §6 实测不发心跳 6 分钟后仍能拉到新分片）；
  - 不能播时说明原因：卡片、刷新得到的房间（没有校验过的主列表）、未开播、受限、状态未知都是 `StreamUnavailable`；别的画质、别的平台的房间是 `ArgumentError`。
- **开播状态**：刷新的两个请求（v3）；受限和状态未知报 `StreamUnavailable`，不当作未开播。
- **链接照 v3**：只认纯 id 和 http(s) 的 `steamcommunity.com/broadcast/watch/<id>`（恰好这三段，可带查询，不带用户信息和片段，默认端口）；个人资料页、`www.` 子域、`steam.tv` 都不认，不发请求。
- **没有 Cookie、登录**：v3 的 Steam 全部匿名，所以不注入 `CookieVault`。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/steambroadcast/steam_broadcast_api.dart`，`S` = `steam_broadcast_site.dart`，`L` = `steam_broadcast_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 目录的头像全部丢失，界面把封面当头像显示（样本 S01 两页 20 张卡片都是 `avatars.fastly.steamstatic.com`，expected.json 的 `avatar` 全为空） | A:439-450；S:87 | 头像只收 `avatars.akamai.steamstatic.com`，Steam 已换到 fastly 主机（归档规格 §10） | 解析不再限主机；**显示仍按 v3 用封面**（用户一直看到的样子），真头像只在没有封面时兜底；改显示真头像列为升级候选 1 |
| 2 | 在播房间的 `hls_url` 或 CDN 参数不合规则时，整个详情失败，关注刷新也失败（刷新并不取流） | A:312-318、A:368-385、A:387-411、A:452-455 | 解析 `getbroadcastmpd` 时总是按取流的规则校验媒体地址，只认 `*.steamcontent.com`。Steam 页面的 CSP 还列着 `broadcast.st.dl.eccdnx.com`、`lv.queniujq.cn` 等 CDN（样本 S01 的响应头），一旦下发这些主机，v3 的房间就打不开 | 房间照常（状态、人数都来自回答），媒体问题记在房间数据里，取流时报 `ApiChanged`；规则本身按 v3 保留，放宽主机列为升级候选 3 |
| 3 | 进房时主列表取不到或校验不过，整个房间打不开 | A:222-230 | 预取主列表的失败直接抛出 | 同上：房间照常，取流时报出原因（`NotFound`、`NetworkFailure`、`ApiChanged`） |
| 4 | 错误没有类型：9 种 `SteamBroadcastFailure`；调用方传错分区、画质也报 `identity`、`schema`；`_scope` 把任何非平台异常（包括解析时的程序错误）都记成 `transport` | A:13-32、A:159-176；S:61-66、S:172-177、S:228 | 平台自己的异常类型 | 类型化错误：401/403 `RiskControl`（Akamai 拒绝页），404 `NotFound`，429 `RateLimited`，400/422 `ApiChanged`，5xx、跳转和其他状态 `NetworkFailure`，结构不符 `ApiChanged`，不能播 `StreamUnavailable`；分区和画质错误是 `ArgumentError`，第 10000 页以后是 `RangeError`，都不发请求 |
| 5 | 明确未开播的房间取画质得到空列表，播放器拿不到原因 | S:221 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 6 | 开播状态在受限、状态未知时报 `access` | S:201-207 | 同问题 4 | `StreamUnavailable`，仍然不当作未开播 |
| 7 | 平台层用全局 HTTP 单例，自己实现流式读取（4 MiB、严格 UTF-8、20 秒）；平台名以外的文字（分区名、公告、画质名）调用界面翻译，公告按当时的界面语言写进房间并随关注存下 | A:120-157；S:53、S:95-97、S:223 | 结构问题；`i18n` 写在适配器里 | 注入 `LiveHttp`，下载后按 UTF-8 字节检查 4 MiB（主列表 1 MiB，v3）；写 3.x `zh.json` 的中文（与 3.x 中文界面存下的相同），状态放进 `SteamBroadcastRoomData`，由界面翻译（M13） |
| 8 | 房间写了媒体请求头（`httpHeaders`），但播放器和录制器从不用它：`PlaybackHeaderResolver` 没有 Steam 分支，只对 IPTV 读房间请求头 | S:98；phr:52-195；`recorder/services/ffmpeg_header_factory.dart:9` | 请求头按平台写在播放层 | 线路不带请求头（v3 实际的行为，实测 CDN 不要求）；房间的 `httpHeaders` 按 3.x 的 JSON 保留 |
| 9 | 记住的主播没有上限，浏览越久占用越多 | S:28、S:68-72、S:179-186 | `Map` 只增不删 | 最多 1000 个，最旧的先忘；平常的浏览量用不到这个上限，结果与 v3 相同 |
| 10 | 已经下播的主播，刷新后仍显示最近一张卡片的人数 | A:66 | 补全时 `currentViewers ?? known.currentViewers` 不看状态；未开播的回答没有 `num_viewers`（样本 S04-mpd-offline） | 按 v3 保留（用户看到的内容），列为升级候选 5 |
| 11 | 直接进房（关注、链接）时标题是占位的 `Steam Broadcast`、分区是 `Steam Community`，没有封面和头像；关注刷新会用这个占位标题盖掉卡片存下的游戏名 | A:319-330 | 房间只读直播页和 `getbroadcastmpd`，它们不给游戏和图片 | 按 v3 保留，列为升级候选 2（`getbroadcastinfo` 有游戏名和截图，样本 S02） |
| 12 | 搜索只筛请求的那一页目录（10 个），目录说明也这么写 | S:156-169 | Steam 没有匿名的直播搜索 | 按 v3 保留 |
| 13 | 分享主播时常用的个人资料页 `steamcommunity.com/profiles/<id>` 认不出 | L:30 | 只认直播页 | 按 v3 保留，列为升级候选 4 |
| 14 | 刷新得到的房间不能播放 | S:99、S:209-217 | 只有进房和录制详情带 `data`（刷新不取主列表） | 按 v3 保留（刷新的请求数不变）；现在报 `StreamUnavailable` 并说明要先进房 |

## 样本与 v3 的冻结输出

归档没有 Steam 的 `expected.json`（归档的旧版对照工具只做了前五个平台，规格 §11 也写明没有旧版期望值）。本模块用 `fixtures/steambroadcast/legacy_expected.dart` 生成，做法同 BIGO LIVE、TwitCasting：

- 把 v3 的 `SteamBroadcastApi`、`SteamBroadcastLink`、`SteamBroadcastSite` 原样搬进一个 Dart 脚本。v3 本来就把传输做成可注入的函数（`SteamBroadcastRequest`），所以只换了它：按主机、路径和查询参数读样本，回给录下的状态码和正文；没有样本的请求抛 StateError，v3 的 `_scope` 把它记为 `transport`，脚本另记在 `unmatched` 里（生成结果里没有出现）。只在网络路径上用到的 `_defaultRequest`、`_readBody` 没有搬，构造函数改为必须注入传输；站点类保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`（`EmptyDanmaku`）。
- `withRequestCancellation` 照抄，Dio 的取消令牌换成桩；`i18n` 返回 3.x `zh.json` 的文字；v3 的 `LiveRoom` 等模型只搬用到的部分（`toJson` 里有 v3 的 `HttpHeaderPolicy.normalize`）。
- v3 用 `package:html` 解析网页，工作区不依赖它，所以脚本用临时的包配置运行（`html: 0.15.6`，同 TwitCasting、niconico、小红书；命令写在脚本开头）。
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求的地址和请求头。

8 个样本有 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S01-directory-p1` | 分类（第 1、2 页，条数 0）；`parseDirectoryHtml`（第 1 页和当作第 2 页）；原生目录（推荐、分区、第 0 页、第 10001 页、别的分区）；推荐的 6 种切片；分区的 2 种切片和别的平台；13 个关键词的搜索（游戏、名字、大小写、id 片段、无结果、在播和未开播的 id、两种直播页链接、个人资料页、空白）、条数 101、第 0 页、条数 0、第 2 页的 id；26 个链接的 `parseSteamId`、`watchUrl`；10 个 `parseViewerCount` |
| `S01-directory-p2` | 第 2 页的 `parseDirectoryHtml`、原生目录、推荐和两个关键词的搜索 |
| `S04-mpd-live` | `parseBroadcastJson`：录下的回答、别的账号；14 种 `success`、5 种 `title`、9 种 `num_viewers`、13 种 CDN 参数、9 种 `hls_url`（http、中国 CDN 主机、路径主机不一致、别的账号、缺 `broadcast_origin`、别的来源、非 443 端口、空、null）；不是对象 |
| `S04-mpd-offline`、`S05-mpd-live` | `parseBroadcastJson` |
| `S05-watch-live` | 与 `S05-mpd-live`、`S05-master-live` 一起：三种深度的详情、开播状态，进房和刷新得到的房间的画质、地址、恢复、`getPlayUrls` 和别的画质；直播页链接、别的平台、不是 id；先看目录再进房（记住的卡片）；`parseWatchHtml` 的 8 种页面 |
| `S05-watch-offline` | 与 `S04-mpd-offline` 一起：三种深度的详情、开播状态、画质和地址；`parseWatchHtml` |
| `S05-master-live` | `validateMaster`：录下的主列表和 9 种改动（别的账号、别的主机、变体或音轨在别的主机、缺 `broadcast_origin`、没有变体、不是 HLS、相对地址、17 个变体） |

**脱敏**：补录脚本按归档规则把 `Set-Cookie` 的 `sessionid`、`steamCountry` 和 `getbroadcastmpd` 的 `viewertoken` 换成同形的合成值；直播页正文里的 `g_sessionID` 与 Cookie 是同一个会话编号，换成同一个合成值。原值还能找到就拒绝写入。复制后又检查了全部样本（包括归档的 7 个和聊天帧）：会话编号、`viewertoken` 都是合成值，聊天帧里观众的 `steamid` 不是 `7656119` 开头、名字是随机串（归档已换）；没有出口 IP（唯一的 IPv4 是 CSP 里的 `127.0.0.1`）、访客或设备编号；`webapi_token` 为空；直播页里的 `country_code: US` 只是国家，保留。主播名、头像、账号 id 是公开信息，保留（同归档规格 §11）。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；另比较请求的地址和请求头。

| 样本 | 结果 |
|---|---|
| S01 分类 | 一致：1 个分类 `Steam Broadcasts`，1 个分区“热门社区直播”（`community`/`trending`）。v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S01 目录、推荐、分区 | 两页 20 张卡片、顺序和每个字段（id、`userId`、游戏名标题、主播名、封面兼头像、分区、在线人数、公告、请求头、链接）一致；“还有下一页”一致；6 种推荐切片、2 种分区切片的结果和请求一致；v3 先请求再报错的第 10001 页现在不发请求 |
| S01 搜索 | 13 个关键词的结果和请求一致（id 和链接各两个请求，其余一个）；无效的条数、页码不发请求 |
| S01 解析 | `parseDirectoryHtml` 的每个字段一致，只有 `avatar`：v3 为空（问题 1），现在是 fastly 的头像地址（只作兜底，不显示）；`parseViewerCount`、26 个链接一致 |
| S04、S05 `getbroadcastmpd` | 录下的三个回答一致；`success`、`title`、`num_viewers` 的全部变体一致（v3 的 `schema` 现在是 `ApiChanged`）；CDN 参数的合法写法一致，v3 报 `schema` 的 6 种和 9 种 `hls_url` 现在房间照常、带媒体错误（问题 2） |
| S05 直播 | 三种深度的房间逐字段一致（标题 `Steam Broadcast`、分区 `Steam Community`、人数 7994），请求一致（进房和录制三个，刷新和开播状态两个）；主列表地址一致；先看目录再进房时补上的游戏名、封面一致 |
| S05 取流 | 画质“自适应 HLS”/`auto`、地址、确认的画质一致，都不发请求；恢复的请求（三个）和地址一致；刷新得到的房间 v3 报 `mediaUnavailable`，现在报 `StreamUnavailable` |
| S05 未开播 | 三种深度的房间一致（主播名 `Rabscuttle`，没有人数），请求一致（两个，不取主列表）；开播状态为假；v3 取画质给空列表，现在报 `StreamUnavailable` |
| S05 直播页、主列表 | 8 种直播页和 10 种主列表的结果一致（v3 的 `missing` 现在是 `NotFound`，`identity`、`schema` 是 `ApiChanged`） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 媒体地址、CDN 参数、主列表有问题时房间照常，取流时报出原因 | 问题 2、3。v3 在这里整个房间和关注刷新都失败；房间的其他字段与 v3 相同 |
| 2 | 明确未开播的房间取画质报 `StreamUnavailable`（v3 给空列表）；卡片、刷新得到的房间、受限、状态未知报 `StreamUnavailable`（v3 `mediaUnavailable`）；别的画质、别的平台是 `ArgumentError`（v3 `schema`、`identity`） | 问题 4、5。只在播放路径上，状态和分组不变 |
| 3 | 开播状态在受限、状态未知时报 `StreamUnavailable`（v3 `access`） | 问题 6。仍然不当作未开播 |
| 4 | 出错抛类型化错误；调用方错误不发请求；不是 id 的房间号是 `NotFound` | 问题 4 |
| 5 | 卡片没有封面时，头像显示主播头像（v3 为空） | 问题 1 的兜底。有封面时与 v3 相同（样本里全部有封面） |
| 6 | 取流结果是线路：HLS、编码、线路编号，请求头为空，没有租期 | 问题 8。地址与 v3 相同 |
| 7 | 进房详情带弹幕参数 `SteamBroadcastDanmakuArgs`；各种深度的详情都带 `SteamBroadcastRoomData`（不写进 JSON；刷新得到的不含主列表） | 留给 D01 和 M13，不多发请求 |
| 8 | 记住的主播最多 1000 个 | 问题 9 |
| 9 | 不再有逐字节的 4 MiB 流式读取和严格 UTF-8；下载后仍按 UTF-8 字节检查 4 MiB | 问题 7。传输由 live_net 统一负责，25 秒总时限相同；非法 UTF-8 按替换字符处理（同 BIGO LIVE、SHOWROOM） |
| 10 | 网页用 `HtmlElement` 解析（v3 `package:html`） | 不增加依赖；两页目录、两个直播页的结果与 v3 逐字段相同 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **详情仍读直播页和 `getbroadcastmpd`**。归档 v4 改用 `getbroadcastinfo`（游戏名、截图、在线人数、回放标记）加迷你资料（主播名、头像）：标题、分区、封面、头像都会变，而且硬依赖迷你资料，它返回 403 时整个详情失败（对照笔记 `sub_C.md`）。列为升级候选 2。
- **有分类和分区“热门社区直播”**，也有搜索。归档 v4 没有分类（分区房间报 `NotFound`），也没有搜索。
- **`user_restricted` 显示为状态未知，取流报 `StreamUnavailable`**。归档 v4 报 `NeedsLogin`，但应用没有 Steam 登录，界面按“需要登录”引导只会走不通。
- **`waiting`、`waiting_to_start`、`waiting_for_start` 和不认识的 `success` 是状态未知**（v3、上游 TV）。归档 v4 漏了 `waiting_for_start`，不认识的值报 `ApiChanged`。
- **头像显示封面**（v3 实际的样子）。归档 v4 显示真头像；列为升级候选 1。
- **标题的占位 `Steam Broadcast`、分区的占位 `Steam Community`**。归档 v4 用 `app_title`。
- **画质名称“自适应 HLS”、id `auto`**。归档 v4 叫“自动”，会改变画质菜单。
- **线路不带请求头**（v3 播放和录制实际发的）。归档 v4 带 UA、`Origin`、`Referer`；实测不需要。
- **媒体地址按 v3 限定主机和路径，主列表按 v3 校验**。归档 v4 收任何 https 的 `.m3u8`，不取主列表。
- **链接只认直播页**。归档 v4 还认个人资料页；列为升级候选 4。
- **进房时预取主列表**（v3 的请求数）。归档 v4 不取。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 卡片和房间显示主播真头像（`avatars.fastly.steamstatic.com`），封面仍用直播截图 | 头像位置显示直播截图 | 问题 1；归档规格 §10；解析已经拿到真头像 |
| 2 | 房间标题、分区、封面改用 `getbroadcastinfo`（`app_title`、`thumbnail_url`；样本 S02），主播名和头像可另取迷你资料（样本 S03，失败时退回直播页的名字） | 直接进房是占位标题 `Steam Broadcast`、没有封面；关注刷新会盖掉卡片存下的游戏名 | 问题 11；归档 v4；对照笔记 `sub_C.md` 建议迷你资料失败时退回 |
| 3 | 媒体地址接受 Steam 的其他 CDN（CSP 里的 `broadcast.st.dl.eccdnx.com`、`lv.queniujq.cn`、`steambroadcast-test.akamaized.net`） | 只认 `*.steamcontent.com`，其他主机不能播 | 问题 2；需要在中国大陆网络下录样本确认 |
| 4 | 认出个人资料页 `steamcommunity.com/profiles/<id>`；自定义地址 `/id/<名字>` 需要一次请求换成 id | 只认直播页 | 问题 13；归档 v4、归档规格 §1、§12 第 2 条 |
| 5 | 已下播的房间不再沿用卡片的人数 | 显示最后一次卡片的人数 | 问题 10 |
| 6 | 聊天（只读，按聊天日志的时钟 HTTP 轮询） | 没有聊天，公告写“远端聊天尚待接入” | 归档规格 §7；样本 `danmaku/S07-live`；本模块已输出 `SteamBroadcastDanmakuArgs` |
| 7 | 按主列表的变体提供可选画质 | 只有“自适应 HLS” | 归档规格 §5、§12 第 3 条；进房时已经取了主列表 |

## 回归条目的覆盖

归档规格没有 REG-STEAM 条目。§10“踩过的坑”和 `spec/regressions.md` 里涉及平台层的通用条目，都有测试：

- **目录没有头像**（§10）：解析不再限主机，两页样本都拿到 fastly 的头像；显示按 v3 用封面，没有封面时用头像（问题 1）。
- **聊天越读越落后**（§10）：属于聊天协议，在 D01 覆盖；本模块提供弹幕参数，样本已复制。
- REG-COMMON-001（失败不等于下播）：传输失败、各种状态码都是类型化错误；受限、状态未知的开播状态报错，不当作未开播；媒体问题不改变房间状态。
- REG-COMMON-002（错误有类型）：7 种状态码和传输失败的映射、调用方错误。
- REG-COMMON-003（五态）：直播、未开播、受限和等待中是“未知”。
- REG-COMMON-004（人数口径）：在线人数，缺值时口径未知，不写 0。
- REG-COMMON-005（画质以确认为准）：确认的画质是 `auto`。
- REG-COMMON-008（请求头随线路走）：线路自带请求头（空，与 v3 实际发的一致）。
- REG-COMMON-011（链接识别）：26 个链接与 v3 一致，经 `LinkParser` 的分享文本、个人资料页和别的页面不认，不发请求。
- REG-LEASE-001、005（租期是结果的一部分；恢复重新取）：没有租期；恢复重新请求直播页、`getbroadcastmpd` 和主列表，不复用旧地址。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 聊天（v3 没有，归档 v4 的 `getchatinfo` 日志轮询）；`getDanmaku()` | D01（升级候选 6）；本模块输出 `SteamBroadcastDanmakuArgs`，样本在 `fixtures/steambroadcast/danmaku/S07-live`；同 E01.1，D01 用一张“平台 → 弹幕连接”的表 |
| 播放、录制按线路打开主列表（v3 的 `PlaybackHeaderResolver`、`ffmpeg_header_factory.dart` 没有 Steam 分支） | G、H01.1 |
| 目录说明 `steambroadcast_directory_scope`、分区名 `steambroadcast_category_trending`、公告 `steambroadcast_chat_notice`/`steambroadcast_restricted_notice`、画质名 `steambroadcast_quality_auto`、平台名 `site_steambroadcast` 的繁体和英文，按 `SteamBroadcastRoomData.state` 显示公告 | M13 多语言。本模块给出 3.x 的中文 |
| 搜索能力表：原生搜索、可翻页、没有网页搜索（3.x `search_capability.dart:86-90`） | M13 搜索页 |
| 外部打开直播页（3.x `room_external_opener.dart:129-130`） | M13；地址由 `SteamBroadcastApi.link` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:466-467`） | M13 |
| 平台列表升级时追加 Steam（`favorite_room_controller.dart:88`，第 32 版） | J02.1 |
| 人数口径（列表和 `getbroadcastmpd` 都是在线人数，3.x `live_room.dart:184-190`） | 已在 E05.1 的 `audience.dart` |
| 录制平台清单（3.x `test/recording_platform_contract_test.dart:37`） | H01.1 |

## 新增的通用能力

没有。用到的 `HtmlElement`、`LivePlayLine`、`LivePlayUrlResolution.lines`、`LiveDirectoryPage` 都已存在；`live_core.dart` 按字母顺序加了两行导出。没有新的第三方依赖（生成期望值用的 `package:html` 只在临时包配置里）。

## 测试

新增 45 个用例，`live_core` 共 2375 个，全部通过：

- `steambroadcast_api_test.dart`（24 个）：逐个样本对照 v3 的输出（分类、两页 20 张卡片和“还有下一页”、搜索筛选、人数文字、26 个链接、三个 `getbroadcastmpd` 回答及其全部变体、8 种直播页、10 种主列表、进房和未开播的房间、先看目录再进房的补全），有意的差异逐条断言；移植 v3 `steam_broadcast_site_test.dart` 的样本（akamai 头像的卡片、直播页、`getbroadcastmpd`、主列表和换了账号的主列表）；另有缩略图规则、头像兜底、重复卡片、受限和等待中的状态、房间数据的不能播原因、线路、状态码和大小上限。
- `steambroadcast_site_test.dart`（21 个），用样本回放加少量合成回答：
  - 请求的地址和请求头与 v3 逐个相同、不跟随跳转、平台名、目录说明、没有弹幕；传输错误和 6 种状态码；25 秒总时限；调用方取消；
  - 目录：分类不发请求；原生目录两页、分区与 v3 一致；第 0 页、别的分区、第 10001 页不发请求；推荐的 6 种切片和分区房间的结果和请求与 v3 一致；
  - 搜索：13 个关键词的结果和请求与 v3 一致；无效的条数和页码不发请求；第 2 页；没有直播页或 404 的账号算没有结果，403 抛出；
  - 房间：直播和未开播各三种深度的房间和请求与 v3 一致，主列表只在进房和录制时取，弹幕参数只在进房时给；直播页链接；非法 id 不发请求；开播状态（直播、未开播、受限、等待中、不认识的值）；先看目录再进房的补全；只记 1000 个主播；
  - 取流：画质、地址、线路（HLS、`avc`、没有请求头和租期），不发请求；恢复重新取三个请求；卡片、刷新得到的房间、未开播不能播；媒体问题（中国 CDN 主机、主列表 404、换了账号的主列表、主列表连不上）不影响房间，取流时报出；恢复时已经下播；
  - 链接（经 `LinkParser`）：分享文本、带查询和中文标点的直播页，个人资料页、别的页面和 `steam.tv` 不认，不发请求。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.14）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 7 行（27-1～27-7）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。“落地方式”只有 27-3 写了（开发预填：先在中国大陆网络下录样本再做），其余按上面“后续升级候选”的原文做；27-2 的“主播名和头像另取、失败时退回”照归档 v4 的适配器和对照笔记（迷你资料失败时退回直播页的名字）。
- 27-6（聊天）属于 D01，这里只把弹幕参数补全；27-3 录不到样本，受阻（见“受阻”）。
- 只改了本平台：`steambroadcast_api.dart`（解析）、`steambroadcast_site.dart`（请求编排）、两份测试和 8 个新样本。没有改 `live_core` 的通用文件（用到的 `HlsMasterPlaylist`、`HlsMasterSelection`、`decodeHtmlEntities` 都已存在），没有新依赖，`expected.json` 没有改。
- 上面“保持 v3 行为”里的这几条现在改了：头像显示封面（改为真头像）、详情读直播页和 `getbroadcastmpd`（改为迷你资料和 `getbroadcastinfo`，直播页和 `getbroadcastmpd` 作退回）、标题和分区的占位（留空）、`user_restricted` 显示为状态未知（改为封禁，见下）、链接只认直播页（加个人资料页和自定义地址）。其余照旧：分类、目录、关键词搜索、平台名、画质“自适应 HLS”、线路不带请求头、媒体地址和主列表按 v3 校验、进房时预取主列表。

### 核实 `user_restricted` 的含义

E03.14 照 v3 把 `getbroadcastmpd` 的 `user_restricted` 理解为“主播限制了谁能看”，E05.2 据此把 Steam 列进“受限直播改为直播中 + 受限类型”。这次读了 Steam 直播页自己的脚本（`community.fastly.steamstatic.com/public/javascript/broadcast_watch.js`，2026-09-29 取）处理 `getbroadcastmpd` 的分支，原文是：

- `user_restricted`：“%s's account is currently restricted from broadcasting on Steam”——**主播的账号被限制直播**，谁来看都一样，没有直播可看；
- `missing_subscription`：“Missing subscription to watch %s's broadcast”——这才是观众受限（要订阅）；
- 另有 `waiting`、`waiting_for_start`、`waiting_for_reconnect`（等待）、`end`（已结束）、`noservers`、`system_not_supported`、`client_out_of_date`、`poor_upload_quality`、`request_failed`，其余一律“暂时不可用”。

所以 `user_restricted` 不按“受限直播”处理，改为**封禁**（`LiveStatus.banned`：平台明确不在播，关注分组在未开播），公告改为“这位主播的 Steam 账号目前被限制直播，暂时不能观看。”；`missing_subscription` 按统一原则显示为直播中 + `subscribersOnly`。其余值照 v3（`waiting*` 和不认识的值是状态未知；`end` 等也仍是状态未知，没有列入升级表，未改）。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 27-1 真头像 | 卡片和房间的 `avatar` 用主播自己的头像，不再用直播截图。卡片的头像地址是 32 px 的 `<hash>.jpg`，改用同一张图的 184 px 版本 `<hash>_full.jpg`（迷你资料给的就是这个地址，样本 S01 与 S03 同一个 hash；个人资料 XML `S10-vanity` 也列出 `.jpg`、`_medium.jpg`、`_full.jpg` 三种尺寸）；不是 `avatars.*.steamstatic.com/<40 位 hash>.jpg` 形式的地址照原样。Steam 的默认头像（问号，hash `fef49e7f…`）算没有头像，留空（S01 两页 20 张卡片里有 4 张）。房间的头像来自迷你资料（27-2）；迷你资料失败退回直播页时没有头像，留空（关注里存下的照旧） | 列表卡片和房间页显示主播头像（v3 显示直播截图）；没有自定义头像的主播显示界面自己的默认头像 | 完成（T02.U） |
| 27-2 另一个详情接口 | 房间的主播名和头像读迷你资料 `miniprofile/<账号 id>/json`（账号 id = Steam id − 76561197960265728；`persona_name` 解码 HTML 字符，`avatar_url` 按 27-1 的规则）；标题、分区、封面读 `getbroadcastinfo?steamid=<id>&broadcastid=0&location=5`（直播页自己也这么取：`title`，空时用 `app_title`；分区 `app_title`；封面 `thumbnail_url`，按 v3 的缩略图规则；人数 `viewer_count`）。<br>- **关注刷新、开播状态、按 id 搜索**：迷你资料 + `getbroadcastinfo`（两个请求，与 v3 的直播页 + `getbroadcastmpd` 一样多）。状态也取自 `getbroadcastinfo`：`success: 42` 未开播；`success: 1` 且 `is_online` 为直播（`is_replay` 为真是回放），否则未开播；其他 `success` 是 `ApiChanged`。<br>- **进房、录制详情**：迷你资料 + `getbroadcastmpd`（状态、受限、人数、主列表，照 v3）；不是未开播也不是账号被限制时再读 `getbroadcastinfo` 补标题、分区、封面（它失败只少这些字段），然后取主列表。在播房间四个请求（v3 三个），未开播两个。<br>- **失败时退回**：迷你资料失败（任何 `SiteError`，取消除外）改读 v3 的直播页取名字（直播页的错误照 v3 抛出，没有配置是 `NotFound`）；刷新时 `getbroadcastinfo` 失败改读 v3 的 `getbroadcastmpd`。<br>- 名字等于 Steam id 的（不存在的账号，Steam 用 id 当名字，样本 `S08-profile-unknown`）算没有名字。只影响名片的字段（`title`、`app_title`、`thumbnail_url`、`viewer_count`）形状不对时留空，不让房间失败 | 直接进房、从关注进房、关注刷新时显示游戏名作标题和分区、直播截图作封面（v3 是占位的 “Steam Broadcast”“Steam Community”、没有封面，关注刷新还会用占位标题盖掉卡片存下的游戏名）；关注列表里的人数改为 `getbroadcastinfo` 的（Steam 缓存一分钟） | 完成（T02.U） |
| 27-3 国内 CDN | 没有做：录不到中国大陆网络下的样本，见“受阻”。媒体地址仍只认 `*.steamcontent.com`，别的主机照旧是媒体错误，取流时报 `ApiChanged`，房间照常显示 | 不变 | 受阻 |
| 27-4 个人资料页链接 | `steamcommunity.com/profiles/<id>`（与直播页同样的主机、端口、协议规则）不发请求就认出是这个主播，链接导入、搜索框、房间号都认。自定义地址 `steamcommunity.com/id/<名字>`（名字是 1～64 个字母、数字、`_`、`-`）要一次请求：`/id/<名字>/?xml=1` 的 `<steamID64>`；Steam 回答 `<response><error>`（没有这个资料）时没有结果，其他形状 `ApiChanged`（链接导入里当作认不出）。链接导入经 `LinkParser` 的 `needsResolving`/`resolveUrl`，请求头 `SteamBroadcastApi.xmlHeaders` | 粘贴或搜索主播的个人资料页、自定义地址都能找到这位主播的直播（v3 认不出） | 完成（T02.U） |
| 27-5 下播后不沿用人数 | 用记住的卡片补全房间时，人数只在这次回答是直播中且自己没有人数时才补（`SteamBroadcast.enrich`）；未开播、封禁、状态未知的房间不再带上最后一张卡片的人数。名字、标题、游戏、封面、头像照 v3 补 | 下播的主播不再显示下播前的在线人数 | 完成（T02.U） |
| 27-6 聊天 | 平台层：`SteamBroadcastDanmakuArgs` 加 `broadcastId`（进房时 `getbroadcastmpd` 的 `broadcastid`，未开播时为空），聊天的 `getchatinfo` 要用它（`broadcastid=0` 会 500，归档规格 §7），D01 不必再请求一次 `getbroadcastmpd`。仍只在进房时给，不多发请求；加了 `==`。连接、轮询、解帧在 D01 | 看不出变化；聊天在 D01 接入 | 平台层完成，余下 D01 |
| 27-7 按档位选画质 | 进房时本来就取了主列表（v3），现在另用通用的 `HlsMasterPlaylist` 读出它的变体：每档一个画质，名字和 id 照 Steam 播放器的叫法 `<高>p`，帧率高于 30 时加上帧率（`1080p60`、`720p`、`480p`、`360p`，Steam 的 `dash_player.js`：`MAX_STANDARD_FRAMERATE = 30`）；同名的只留码率最高的；从好到差（高度、帧率、码率）。只有一个变体时不列（与 Steam 播放器一样，只有一档时不给选择；S05 就是这样）。画质列表是“自适应 HLS”（v3 的，id `auto`，仍排第一、仍是默认）后跟各档；各档的 `sort` 都是 0，列表顺序就是顺序。<br>Steam 的变体没有自己的音频（音频是单独的 `#EXT-X-MEDIA`），所以一档的线路仍是主列表，档位写在画质的 `data` 里：`SteamBroadcastVariant`（id、宽高、帧率、码率、编码），`selectIn(主列表文本, source:)` 在任何一份新取的主列表里找到同 id、码率最接近的变体并连同它的音频给出 `HlsMasterSelection`（CDN 主机每次都变，所以按档位而不是按地址选）。取流不发请求，确认的画质是所选的 id；恢复只取 `getbroadcastmpd` 和主列表（两个请求，v3 三个），新主列表没有这一档时改播“自适应 HLS”并如实报 `auto`。共享解析器读不了的主列表只给“自适应 HLS”，照常能播 | 多档的直播（S09 是 1080p60/720p/480p/360p）可以在画质菜单里选档（G 接上后生效）；只有一档的直播菜单不变 | 平台层完成，余下 G |

### 按统一原则补的

| 原则 | 做了什么 |
|---|---|
| 开播时间 | Steam 不提供：卡片、`getbroadcastinfo`、`getbroadcastmpd`、直播页、迷你资料都没有开播时间字段。`startedAt` 不填 |
| 受限类型 | 进房、录制详情填：`ready` 为 `none`，`missing_subscription` 为 `subscribersOnly`；关注刷新（`getbroadcastinfo` 不说）、卡片（热门页是 `forceanon=1` 的公开列表，但每张卡片不说）、未开播、封禁、状态未知留空 |
| 受限的直播改为直播中 | `missing_subscription` 显示为直播中 + `subscribersOnly`，取流报 `StreamUnavailable`（“a broadcast for the broadcaster's subscribers only”），不取主列表；`user_restricted` 核实后不是受限直播，改为封禁（见上），取流报 `StreamUnavailable`（“the broadcaster's account is restricted from broadcasting”），开播状态为假（v3 报错） |
| 占位信息 | 标题 `Steam Broadcast`、分区 `Steam Community`、主播名 `Steam broadcaster`、等于 Steam id 的名字、Steam 默认头像都留空（关注里存下的值不被覆盖，界面名字为空时显示平台名）。3.x 的三个占位保留为常量 `SteamBroadcastApi.legacyTitle`、`legacyArea`、`legacyBroadcaster`，给 J02.1 |
| 回放、不可播放 | `getbroadcastmpd` 的 `ready` 带 `is_replay`、`getbroadcastinfo` 在线带 `is_replay` 时标回放（Steam 的播放器同样按它切成回放模式）；回放照样给主列表，能播，所以不需要“不可播放”。主列表有问题时同直播，取流报媒体错误。没有真实的回放样本，只有合成用例（归档规格 §12 第 5 条也没录到） |
| 容错 | 目录里一张读不了的卡片（例如超长文字）只跳过自己（v3 整页失败）；`getbroadcastinfo`、迷你资料里只影响名片的字段坏了留空；主列表的某个变体读不了只少这一档 |
| 翻页 | 不适用：热门页是服务端分页（每页 10 个），不是一次给全的快照；不变 |
| 房间身份 | 不变：64 位 Steam id（数字，与大小写无关）。个人资料页链接作房间号时同样换成 id |
| 按主播关注 | 本来就是：房间号是主播的 Steam id，每场变化的 `broadcastid` 只在弹幕参数里 |
| 画质命名 | 没有改名条目：“自适应 HLS”、`auto` 不变；新增的档用 Steam 播放器的叫法（27-7） |
| 默认编码 | 不适用：录到的变体都是 H.264（`avc1`） |
| 弹幕 | 27-6（D01） |
| 说明文字 | 公告 `chatNotice`（3.x `steambroadcast_chat_notice`：“Steam 远端聊天尚待接入；界面人数来自平台明确返回的当前并发观看数。”）改为“Steam 直播的聊天暂时不能在这里显示。人数是正在观看的人数。”；`restrictedNotice`（3.x：“该 Steam 直播受账号访问范围限制，界面保持未知状态，不将其显示成未开播。”）改为“这位主播的 Steam 账号目前被限制直播，暂时不能观看。”（键不变，M13 做多语言）。目录说明的建议文字见“留给其他模块” |

### 请求数

| 场景 | E03.14（= v3） | 现在 | 原因 |
|---|---|---|---|
| 关注刷新、开播状态、按 id / 直播页 / 个人资料页搜索 | 2（直播页、`getbroadcastmpd`） | 2（迷你资料、`getbroadcastinfo`） | 27-2；迷你资料失败时多 1 个（直播页），`getbroadcastinfo` 失败时多 1 个（`getbroadcastmpd`） |
| 进房、录制详情：在播 | 3（直播页、`getbroadcastmpd`、主列表） | 4（迷你资料、`getbroadcastmpd`、`getbroadcastinfo`、主列表） | 27-2 本身要求另取主播名、头像和详情 |
| 进房、录制详情：未开播、主播账号被限制 | 2 | 2（迷你资料、`getbroadcastmpd`） | — |
| 进房、录制详情：仅订阅者、状态未知 | 2 | 3（多 `getbroadcastinfo`，没有主列表） | 27-2 |
| 取画质、取地址（进房后） | 0 | 0 | — |
| 恢复取流 | 3 | 2（`getbroadcastmpd`、主列表） | 只取新地址，少一个请求 |
| 目录、推荐、分区、关键词搜索 | 1 | 1 | — |
| 搜索：个人资料页链接 | 1（筛目录，没有结果） | 2 | 27-4 |
| 搜索：自定义地址 | 1（筛目录，没有结果） | 3（资料 XML、迷你资料、`getbroadcastinfo`）；没有这个资料时 1 | 27-4 |
| 链接导入：直播页、个人资料页 | 0（个人资料页不认） | 0 | — |
| 链接导入：自定义地址 | 不认 | 1 | 27-4 |

字节数上，刷新从约 26 KB 的直播页 + 0.7 KB 变成约 0.2 KB + 0.4 KB。

### 画质 id 对照（给 J02.1）

不需要迁移：v3 唯一的画质 `auto`（“自适应 HLS”）名字和 id 都没变，仍排第一。新增的档 id 就是名字（`1080p60`、`720p`……，`SteamBroadcastApi.variantId(高, 帧率)`，`isVariantId` 判断形状），v3 没有，存下的偏好不会指向它们。

### 设置项

没有：本平台的 7 行都没有要求设置开关。

### 身份迁移规则（给 J02.1）

- 房间身份不变（Steam id），不需要迁移关注。
- 3.x 存下的占位值：标题 `Steam Broadcast`、分区 `Steam Community`、主播名 `Steam broadcaster`（常量 `SteamBroadcastApi.legacyTitle`、`legacyArea`、`legacyBroadcaster`）。适配器不再写它们，但已存的不会被空值覆盖（E05.2 的合并规则），迁移时可以按这三个常量清空，下次刷新会补上真实的游戏名和名字。
- 3.x 存下的头像是直播截图（`steambroadcast.akamaized.net/broadcast/<id>/…/thumbnail/`，问题 1）：刷新时迷你资料给的真头像会覆盖它；迁移时也可以清空主机是 `steambroadcast.akamaized.net` 的头像。
- 3.x 把 `user_restricted` 存成状态未知（`liveStatus` 3），不用迁移：下次刷新或进房会变成未开播或封禁。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| 聊天（27-6）：`SteamBroadcastDanmakuArgs(steamId, broadcastId:)`；`broadcastId` 为空（未开播时进房）或换场后，先请求 `getbroadcastmpd` 取新的；`getchatinfo` 必须用真实的直播 id；日志时钟轮询的做法见归档规格 §7，样本 `danmaku/S07-live`。接上后把公告 `chatNotice` 的第一句去掉 | D01 |
| 按档播放（27-7）：画质的 `data` 是 `SteamBroadcastVariant` 时，线路（主列表）要限定到这一档：取回主列表后用 `variant.selectIn(文本, source: 线路地址)` 得到 `HlsMasterSelection`（视频和它的音频），再用 `rewrite` 得到只含这一档的主列表交给播放器；或者用播放器的变体选择（mpv 的 `hls-bitrate` 取 `variant.bandwidth`）。没接上之前播放器按自适应播放，界面却显示所选的档，所以 G 接上前不要把档位暴露给界面。`resolveAppliedPlayQuality` 找到的已确认画质带着这个 `data`。恢复时返回的是新主列表，同一个 `SteamBroadcastVariant` 照样能选中（按档位，不按地址） | G |
| 录制按档：录制按列表顺序选（各档 `sort` 都是 0），默认是“自适应 HLS”；录某一档时同样要用 `SteamBroadcastVariant` 限定主列表（ffmpeg 按码率选流） | H01.1 |
| 按上面的规则清空 3.x 存下的占位值和截图头像（可选） | J02.1 |
| 仅订阅者（`subscribersOnly`）和封禁（主播账号被限制直播）的卡片标记和播放提示，不引导登录（本应用没有 Steam 账号）；公告 `steambroadcast_chat_notice`、`steambroadcast_restricted_notice` 的新文字（见上）；名字为空时显示平台名；目录说明 `steambroadcast_directory_scope` 改写，建议：“Steam 热门社区直播，每页 10 个。关键词只在当前页里按主播名、游戏筛选；输入 SteamID64，或粘贴直播页、个人资料页、自定义地址链接，可以直接找到这位主播。” 英文：“Trending Steam community broadcasts, ten a page. Keywords filter the current page by broadcaster and game; enter a SteamID64 or paste a broadcast, profile or custom profile URL to find that broadcaster.”；搜索页能力表（3.x `search_capability.dart:86-90`）加上个人资料页和自定义地址 | M13 |

### 受阻

- **27-3 国内 CDN**：落地方式要求先在中国大陆网络下录样本。2026-09-29（北京时间）试了两条路，都拿不到：
  - 本机默认出口：经系统层隧道在境外（Cloudflare trace `loc=US`），`getbroadcastmpd` 给的都是 `*.steamcontent.com`（今天 5 个在播主播的 `hls_url` 都是 `cache3/cache11-lax2.steamcontent.com`）；
  - 测试机（中国大陆网络，Cloudflare trace `loc=CN`）上用系统自带的 curl 只读请求 `getbroadcastmpd`：域名能解析，但 TCP 连接一直建立不起来，20 秒、40 秒都超时（curl 退出码 28）。也就是说，在中国大陆直连时连 Steam 社区的接口都访问不到，拿不到会下发国内 CDN 的回答。
  
  国内 CDN 的主机只出现在 Steam 页面的 CSP 里（`broadcast.st.dl.eccdnx.com`、`lv.queniujq.cn`、`steambroadcast-test.akamaized.net`），不知道它们的路径形状、`broadcast_origin` 和 CDN 参数，放宽规则就是猜，所以没有做。用户在中国大陆本来就要经代理访问 Steam 社区（应用按平台注入代理），经境外代理时 Steam 给的正是 `steamcontent.com`；需要这一条的是“从中国大陆 IP 直接到达 Steam 社区”的情形（例如某些加速工具），本机没有这样的出口，也不绕过网络限制去造一个。媒体问题仍不会让房间失败，取流时报 `ApiChanged` 并带上地址片段，以后有了样本再按实际形状放宽。
- 没有真实样本、只靠合成回答的部分：回放（`is_replay`）、仅订阅者（`missing_subscription`）、主播账号被限制（`user_restricted`；含义来自 Steam 网页脚本的原文）、单个卡片读不了、变体重复或缺分辨率。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed` 列出、原因写在旁边；`expected.json` 没有改：

- 所有卡片（目录、推荐、分区、关键词搜索）：`avatar`（27-1：v3 是封面）、`notice`（说明文字）。
- S05 在播房间（进房、录制、先看目录再进房、直播页链接）：`title`、`area`、`cover`（27-2：v3 是占位和空）、`avatar`（27-1）、`notice`；多了 `restriction: none` 一个键，测试断言 3.x 的输出里没有它。关注刷新（和按 id 搜索）另有 `watching`、`onlineViewers`：取自 `getbroadcastinfo`（6862，v3 的 `getbroadcastmpd` 是 7994；两个样本相隔一天）。
- S05 未开播房间（三种深度、按 id 搜索）：`avatar`（27-1，迷你资料的头像）、`title`、`area`（X-2：v3 是占位）、`notice`。
- 请求：刷新从“直播页、`getbroadcastmpd`”变成“迷你资料、`getbroadcastinfo`”；进房多了迷你资料和 `getbroadcastinfo`，`getbroadcastmpd` 和主列表的地址、请求头与 v3 逐字相同；恢复少了直播页。
- `getbroadcastmpd` 的全部变体：`title`（X-2：v3 空标题写 `Steam Broadcast`）；`user_restricted` 的 `state`（v3 `restricted`，现在 `accountRestricted`，见上）。
- 直播页的名字：没有标题、名字为空时 v3 写 `Steam broadcaster`，名字等于 id 时 v3 写 id，现在都留空（X-2）。
- 链接：`steamcommunity.com/profiles/<id>` v3 认不出，现在是这个 id（27-4）；个人资料页链接的搜索 v3 筛目录没有结果，现在找到这位主播。
- 取流：S05 的主列表只有一个变体，画质仍只有“自适应 HLS”，地址和确认的画质与 v3 相同；多档画质只有 S09（新样本，v3 没有对应输出）。

### 新样本

2026-09-28 20:00:34～20:00:40 UTC 直连（本机默认出口）录制，匿名，只读，不跟随跳转，请求头是适配器的（`SteamBroadcastApi.roomHeaders(json: true)`、`mediaHeaders`、`xmlHeaders`），脚本同 E03.14 的做法；`raw` 记原始回答的 SHA-256 和长度，JSON 正文按 2 格缩进写出。v3 不发这些请求（S09 的 `getbroadcastmpd` 和主列表 v3 会发，但这个主播没有 v3 的冻结输出），都不带 `expected.json`。门禁的 `fixture privacy` 通过。

| 样本 | 内容 | 脱敏（`meta.json` 的 `scrubbed`） |
|---|---|---|
| `S08-profile-offline` | 未开播账号 76561197960287930（Rabscuttle）的迷你资料，与 S04、S05 的未开播样本配对 | Set-Cookie `sessionid`、`steamCountry`（国家码后的部分）换成同形的随机值 |
| `S08-profile-unknown` | 不存在的账号 76561199999999990 的迷你资料：名字是 id、头像是 Steam 默认头像（它的个人资料页是错误页） | 同上 |
| `S09-profile-live` | 在播主播 76561198843011284（SCS Software）的迷你资料 | 同上 |
| `S09-info-live` | 同一主播的 `getbroadcastinfo`：Euro Truck Simulator 2，2483 人，`permission: 3`，`is_replay: 0` | Set-Cookie `steamCountry` |
| `S09-mpd-live` | 同一主播的 `getbroadcastmpd`：`ready`，2490 人，`broadcastid` 与缩略图路径里的相同 | Set-Cookie `sessionid`、`steamCountry`；正文的 `viewertoken`（本次观看的令牌） |
| `S09-master-live` | 它指向的 HLS 主列表：1080p60、720p、480p、360p 四个变体，共用一路音频（27-7 的依据） | 无（地址不带令牌，`broadcast_origin` 是 Steam 的服务器） |
| `S10-vanity` | 自定义地址 `id/gabelogannewell/?xml=1`：`steamID64` 就是 76561197960287930 | 无 |
| `S10-vanity-missing` | 不存在的自定义地址：`<response><error>` | 无 |

没有出口 IP、访客或设备编号（响应头里唯一的 IPv4 是 CSP 里的 `127.0.0.1`）；主播名、头像、账号 id、公开资料 XML 里的字段是公开信息，按 E03.14 的口径保留。

### 测试

本平台 65 个用例（E03.14 是 45 个；新增 20 个，另改写了卡片、房间、请求、搜索、链接、取流的用例），`live_core` 共 3362 个，全部通过。时间炸弹：本平台的测试不拿样本里的时间和“现在”比，也没有租期；把时钟往后推 +30 天、+1 年、+5 年跑 `live_core` 的全部用例都通过。其中 +1 年、+5 年没能用 `tools/timeshift/run.sh` 跑完：它调用的 `dart test` 在时钟推后一年以上时卡在 dartdev 里（0 CPU、只等一个计时器，还没开始跑测试；本机另一处同时运行的 +5 年也卡在同一步），所以用同样的 LD_PRELOAD 垫片直接运行 `test` 包的 `bin/test.dart`（绕过 dartdev）；+30 天两种方式都通过。

- `steambroadcast_api_test.dart`（38 个）：
  - 与 v3 的对照：两页卡片（`avatar`、`notice` 以外逐字段相同，4 个默认头像留空，真头像与迷你资料同一张图）、搜索筛选、人数文字、26 个链接（个人资料页改认）、`getbroadcastmpd` 的全部变体（占位标题、`user_restricted`）、8 种直播页（三种占位留空）、10 种主列表、进房和未开播的房间（新旧字段逐个断言）、先看目录再进房；
  - 27-1：卡片头像规则（`_medium`/`.jpg` → `_full`、默认头像、别的主机照原样）；27-2：`getbroadcastinfo` 三个样本、标题优先、回放、宽松字段、HTML 字符、别的 `success`，迷你资料四个样本和错误，与 `getbroadcastmpd` 合并；27-4：`vanityOf` 的 10 种输入、资料 XML、新接口的地址与样本一致；27-5：补全只在直播中带人数；27-6：弹幕参数；27-7：S09 的四档、S05 的一档不列、`selectIn` 在换了主机的新主列表里选中同一档并带音频、`rewrite`、档位命名、同名去重、缺分辨率、解析器拒绝时只剩自适应；
  - 状态：封禁、仅订阅者、状态未知、回放；房间数据的不能播原因和画质；状态码映射（新增三个接口）和大小上限。
- `steambroadcast_site_test.dart`（27 个），用样本回放加少量合成回答：
  - 请求的地址和请求头（保留的与 v3 逐个相同）、不跟随跳转、传输错误、状态码（先迷你资料再直播页）、取消（不当作失败去退回）、25 秒总时限；
  - 目录和搜索与 v3 一致（`avatar`、`notice` 以外）；按 id、直播页、个人资料页搜索用刷新的两个请求；自定义地址先解析（3 个请求），不存在的 1 个请求、第 2 页不发请求；没有页面的账号算没有结果、403 抛出；
  - 房间：直播和未开播各三种深度的房间和请求、S09 一分钟内录的四个回答、两种退回、个人资料页作房间号、开播状态（封禁为假、状态未知报错、回放为假）、先看目录再进房（下播后不带人数）、只记 1000 个主播；
  - 取流：S05 的一档、恢复两个请求；S09 选档（线路是主列表、确认的 id、`data` 是 `SteamBroadcastVariant`、没有数据的 id 也能用），恢复保持档位、新主列表没有时改播自适应；不能播的房间、仅订阅者和封禁不取主列表、媒体问题不影响房间、恢复时已下播；
  - 链接（经 `LinkParser`）：直播页、个人资料页不发请求，自定义地址一个请求，不存在的认不出。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.24 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.24-Steam直播弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
