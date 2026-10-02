# E03.7 CHZZK

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/chzzk/`（`chzzk_api.dart` 纯解析，`chzzk_site.dart` 请求编排）
- 样本：`fixtures/chzzk`，全部来自归档（2026-09-27 直连录制，匿名）：
  - v3 会请求的：热门目录 `S03-lives-p1`、`S03-lives-p2`（按游标翻页），频道搜索 `S04-search-channels`、`S04-search-empty`，频道 `S05-channel-live`、`-offline`、`-notfound`，`v3.1 live-detail` 的在播、未开播、地区受限、成人、不存在（`S06-live-detail-*`），同一场直播的两个 HLS 主列表 `S07-master-hls`、`S07-master-llhls`；
  - v3 不请求、只供升级候选和 D01 用的：平台分类 `S01-categories-p1`～`p4`，分区房间 `S02-category-lives-*`，弹幕凭据 `S08-chat-token`，弹幕帧 `danmaku/S09-live`。
- 参考：
  - 归档 v4 的 CHZZK 适配器和规格（`spec/sites/chzzk.md`，回归条目 REG-CHZZK-001～004）；
  - pure_live_TV `e1cca224`：与 v3 逐行相同，只是改了导入路径、可空字段改写空串、详情用 `copyWith`（对照笔记 `small_diffs.txt`、`sub_B.md` 的 chzzk 一节），没有行为修复。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

> E06 平台层升级（2026-09-29）按用户批准的升级改了分类、翻页的条数、搜索、链接、进房和取画质的请求、不在播时的状态、地区受限的判断、公告和目录说明，见文末“升级落地（E06 平台层升级）”（20-1～20-10）。本节以下是 E03.7 时的做法。

## 做法

- **接口照 v3**：`LiveSite` 和 v3 实现过的全部可选能力——游标目录（`LiveSiteCursorDirectoryPager`，含按页码的 `LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `chzzk_directory_scope`）、可取消的搜索、关注刷新、录制详情、恢复（`LivePlayRecoveryResolver`），另加取流（`LivePlayUrlResolver`，给出线路）和 `LiveSiteLinks`。v3 没有的 `LiveSearchPaginationPolicy`、`LiveQualityDiscovery` 不加。3.x 的 JSON 不变。
- **匿名，照 v3**：所有请求以 `chzzk` 的名义发出（代理路由由应用按平台注入），带 v3 的请求头（桌面 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Origin`、`Referer: https://chzzk.naver.com/`），**不跟随跳转**，不带 Cookie。v3 没有 CHZZK 的登录和 Cookie 设置，所以不注入 `CookieVault`。
- **请求照 v3**：
  - 目录只有一个固定分区“公开热门直播”，不发请求；
  - 目录页：`/service/v1/lives?size=30`；之后按游标 `size=31&concurrentUserCount=…&liveId=…`（v3 认为游标包含边界，多取一条再去掉重复的那条）。游标是 v3 的不透明 JSON `{"v":人数,"l":liveId}`；
  - 按页码取（推荐、分区房间）从第 1 页逐页重放到第 N 页，N 最多 20，整个重放 20 秒内完成，超时取消在途请求并报 `NetworkFailure`（v3 同样）。v3 的目录页面用游标接口，一页一个请求；
  - 搜索：`/service/v1/search/channels?keyword=…&offset=(页码-1)×每页&size=每页`，每页 1～30 条（默认 30），页码小于 1 或每页越界返回空、不发请求（v3）；关键词超过 100 字、偏移超过 1000000 是调用方错误（`ArgumentError`，v3 同样拒绝）；
  - 关注刷新、开播状态：`/service/v1/channels/<id>` 和 `/service/v3.1/channels/<id>/live-detail`，两个请求；
  - 进房、录制详情、恢复：上面两个请求，再按 `livePlaybackJson` 的顺序请求 `HLS`、`LLHLS` 两个主列表（在播时共 4 个请求，与 v3 相同）。主列表请求用的也是上面那组请求头（v3 同样）。
- **房间身份与 v3 一致**：房间号是频道号 `channelId`（32 位小写十六进制），`userId` 相同；链接里的大写会转成小写，详情只接受小写（v3 的 `_channelId`）。直播号 `liveId` 每场都变，不作身份。样本里所有房间号都与 `expected.json` 一致。
- **卡片照 v3**：
  - 目录卡片：标题 `liveTitle`，主播名、头像来自行里的 `channel`；封面是 `liveImageUrl` 把 `{type}` 换成 480，没有时用 `defaultThumbnailImageUrl`（REG-CHZZK-003）；分区 `liveCategoryValue`（为 null 时 `liveCategory`）；人数只在 `cvExposure` 为 true 时取 `concurrentUserCount`（REG-CHZZK-002），口径“在线”；成人直播带公告“成人分级房间未返回公开匿名媒体源。”；同一页里一个频道只出现一次；
  - 搜索卡片：标题和昵称都是频道名，封面是头像，状态按 `openLive`（直播中或未开播），带粉丝数和简介；
  - 图片只接受 `pstatic.net`、`akamaized.net` 及其子域名上的 https 地址（v3 的白名单），其他写空。
- **详情照 v3**：
  - 频道接口给出主播名、头像、简介、粉丝数和 `openLive`；
  - 必须用 `v3.1 live-detail`：v2 对海外受限的直播返回 HTTP 500 / 9004，整页失败（REG-CHZZK-001）；
  - `status` 为 `OPEN` 是直播中，`CLOSE`、`CLOSED` 不在播，其他值是 `ApiChanged`，不当作未开播；
  - 不在播（或从没直播过，`content` 为 null）时房间就是频道卡片，状态按频道的 `openLive`；
  - 在播时是直播卡片，加上频道的粉丝数和简介；标题为空时用频道名；公告按 v3 的顺序：地区受限（`krOnlyViewing`）→ 成人且没有播放数据 → 可回看（`timeMachineActive`）→ 成人。公告文字是 3.x `zh.json` 的中文（`ChzzkApi.regionNotice` 等）。
- **画质和线路照 v3**：
  - 两个主列表用共享的 `HlsMasterPlaylist`（E03.5 移植的 3.x `hls_master_selection.dart`）解析，看不懂的主列表是 `ApiChanged`，与 v3 相同；
  - 每个视频变体按 `<高>p`、帧率 ≥ 50 加 `60` 归档，名称 `1080p60 · HLS`，id `1080p60`，排序值是高度 × 10⁷ + 该档第一个变体的码率，从高到低。两个主列表的同名档合并；
  - 每档的线路按地址去重、按主列表顺序：`HLS` 在前，`LLHLS`（低延迟）在后。线路编号是 `mediaId`；格式 HLS；编码取变体的 `CODECS`（`avc1` → avc，`hvc1`/`hev1` → hevc）；请求头是 v3 `PlaybackHeaderResolver` 里 CHZZK 的那一组（UA、`Referer: https://chzzk.naver.com/`）；
  - **有效期**：主列表带 Akamai 令牌 `hdnts=st=…~exp=…`，变体路径带 `hdntl=exp=…`，实测约 17 小时。`PlayLease` 的到期取变体的 `exp`（没有时取主列表的），提前 10 分钟（最多寿命的四分之一）续期；HLS 每个分片都是新请求，到期会断流，所以 `cutsConnection` 为真。v3 没有租期，只在失败后恢复；
  - 服务端不降档，所以应用的画质就是请求的画质。
- **取流前的检查**：进房的 `ChzzkRoomData` 带着画质和线路，取画质、取地址都不再请求；不能播放时说明原因：不在播 `StreamUnavailable`，地区受限（`krOnlyViewing` 或 `blindType: ABROAD`）`RegionBlocked`，成人 `NeedsLogin`，其他没有播放数据的直播 `StreamUnavailable`。恢复时重新进房（v3），同一个画质 id 必须还在。
- **弹幕**：v3 没有 CHZZK 弹幕（`EmptyDanmaku`），`getDanmaku()` 仍是空的。进房时只记下 `live-detail` 里的 `chatChannelId`（`ChzzkDanmakuArgs`，不多发请求），由 D01 决定要不要做（同 E02.6 克拉克拉的做法）。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/chzzk/chzzk_api.dart`，`S` = `core/site/chzzk/chzzk_site.dart`，`L` = `core/site/chzzk/chzzk_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 目录翻页可能每页漏掉一场直播 | A:201-219 | v3 认为游标包含边界，翻页时要 31 条、去掉重复的第一条后截成 30 条，但下一页游标仍用服务端的 `page.next`，而它指的是**服务端发来的最后一条**。服务端真返回 31 条时，被截掉的第 31 条永远不显示。录制（`S03-lives-p1` 末条就是 `next`，`S03-lives-p2` 从它之后开始）证明游标不含边界 | 请求照旧（31 条、去掉重复的第一条）；只在真的截掉了行时，下一页游标改为本页最后保留的那条。服务端返回不超过 30 条时（包括录到的样本）结果与 v3 完全相同 |
| 2 | 一行数据不合预期，整页目录或搜索都失败 | A:209、A:236-239、A:297-322 | 列表的每一行都按详情的严格规则检查：标题不能为空（A:302）、`adult` 必须是布尔（A:306）、`liveId` 必须为正（A:300）、频道名不能为空（A:317）、频道号不合规报 identity（A:409-413） | 没有频道号或 `liveId` 的行跳过；标题为空用频道名（详情的规则，A:279）；其他字段取不到就留空。只在 v3 失败的地方生效 |
| 3 | 不存在的频道报 identity 错误 | A:242-249、A:409-413 | 频道接口对不存在的 id 也回 200，`channelId` 为 null（样本 `S05-channel-notfound`，名字是“(알 수 없음)”），被当成身份不符 | `NotFound`；另一个频道的回答仍是 `ApiChanged` |
| 4 | 播放数据格式一变，关注刷新和开播状态也跟着失败 | A:268、A:324-344、S:260-266 | 每次读 `live-detail` 都解析 `livePlaybackJson`，刷新也不例外，一项不合规整页 schema | 只为在播的直播读取；读不了时房间照常，原因记在 `ChzzkLive.mediaError`，进房（要取主列表时）才报 `ApiChanged`，与 v3 进房的结果相同 |
| 5 | 未开播的房间取画质得到空列表，播放器拿不到原因 | S:271 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 6 | 没有 `data` 的房间（列表卡片、搜索卡片、刷新过的关注）取画质报“无媒体” | S:272-275 | 只认进房时的 `_ChzzkPlayback` | 先进房再取；正常进房流程不受影响 |
| 7 | 地区受限、成人直播取流时只报“无媒体” | S:272-275、S:241-247 | 原因只写进公告，取流一律 `mediaUnavailable` | `RegionBlocked`（`krOnlyViewing` 或 `blindType: ABROAD`）、`NeedsLogin`（成人）；公告不变 |
| 8 | 主列表里出现纯音频变体（没有分辨率）时整个房间打不开 | S:201-205 | 高度为 0 报 schema | 跳过这种变体；一个视频变体都没有才 `StreamUnavailable`。`livePlaybackJson` 的 `encodingTrack` 里已经有 `audioOnly`，只是现在的主列表没列它 |
| 9 | 各种失败都是平台自己的 `ChzzkException`，播放和录制只能按种类名判断 | A:9-18、A:155-194 | 平台自定义异常 | 类型化错误：401/403 `RiskControl`，404 `NotFound`（主列表 404 是 `StreamUnavailable`），429 `RateLimited`，5xx、其他状态（含跳转）和传输失败 `NetworkFailure`，400、`code` 不是 200、结构不符 `ApiChanged`；取消原样抛出 |
| 10 | 平台层依赖全局 `HttpClient`，自己实现流式读取（2 MiB、20 秒）和请求作用域 | A:93、A:111-153、S:44 | 结构问题 | 注入 `LiveHttp`；20 秒由 live_net 的请求超时负责；2 MiB 在解析前按字符数检查一次（同 v3 `_read` 的第二道检查） |
| 11 | 媒体请求头按平台写在播放层，列表卡片还带着一份没人读的 `httpHeaders` | phr:174-176、S:74、phr:143-148 | 地址和请求头分开放；`httpHeaders` 是 IPTV 的字段，解析器只在 IPTV 时读它 | 线路自带请求头；卡片不再写 `httpHeaders` |
| 12 | 签名地址没有有效期，只能等断流后再恢复 | S:287-297 | 没有读令牌里的 `exp` | 线路带 `PlayLease`（见“做法”） |
| 13 | 平台层调用界面翻译（分区名、三种公告） | S:15、S:73、S:102、S:241-247 | `i18n` 写在适配器里 | 用 3.x 的中文作默认文字（`ChzzkApi.directoryAreaName` 等），界面的翻译在 M13 |
| 14 | 调用方传错参数（页码、游标、分区、别的平台的房间）报平台错误 | S:110-115、S:124-127、S:140、S:233、S:270 | 本地校验失败用 schema、identity | `ArgumentError`/`RangeError`，不发请求；不是频道号的房间号是 `NotFound`，不发请求 |
| 15 | 空关键词报错 | A:230 | 与超长关键词同样处理 | 返回空，不发请求（界面不会发空关键词） |

另外两处按 v3 保留：

- **不在播的房间状态取自频道的 `openLive`**（S:236）。两次请求之间主播刚下播或刚开播时，频道和直播可能不一致，房间会显示直播中而没有播放数据（取流报 `StreamUnavailable`）。见升级候选 7。
- **按页码取目录要从第 1 页重放**（S:138-165），第 N 页要 N 个请求。v3 的目录页面用游标接口，只有 `getRecommendRooms`、`getCategoryRooms` 的调用方受影响，请求数与 v3 相同。

## 样本与 v3 的冻结输出

归档没有 CHZZK 的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了）。本模块用 `fixtures/chzzk/legacy_expected.dart` 生成，做法同小红书、猫耳：

- 把 v3 的 `ChzzkApi`、`ChzzkLink`、`ChzzkSite` 和 `hls_master_selection.dart` 里的 `HlsMasterPlaylist.parse` 原样搬进一个 Dart 脚本。v3 本来就把传输做成可注入的函数（`ChzzkRequest`），所以只换了它：按主机、路径和查询参数（不比 `size` 和已脱敏的 `hdnts`、`vp`）读样本，状态码不是 200 时正文为空（同 v3），没有样本的请求抛 StateError（`_read` 放它通过，不让它变成 transport）；
- Dio 的取消令牌、请求作用域、网络路径上的 `readBody` 没有搬；`i18n` 返回 3.x `zh.json` 的文字；v3 的模型只搬用到的部分；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求数；
- 地区受限和成人直播录制时没有录频道接口，脚本用 `live-detail` 自己的 `channel` 对象回答（没有简介和粉丝数），站点测试也这样做；
- 搜索样本是按每页 20 条录的，脚本也按 20 条调用（v3 默认 30 条，回答的形状相同）；目录第 2 页是按 30 条录的，v3 要 31 条，按 `size` 以外的参数匹配。

14 个样本有 `expected.json`：目录两页（固定目录、目录说明键、按页码、按游标、推荐、分区房间）、搜索两个、频道三个、`live-detail` 五个（进房、刷新、录制详情、开播状态、画质、每档地址、恢复；不存在的只有 `liveDetail`）、主列表两个（单独一个主列表得到的画质）。S01、S02、S08 和弹幕帧 v3 不请求，没有期望值。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和每档地址，另比较请求数。

| 样本 | 结果 |
|---|---|
| S03-lives-p1、p2 | 30 + 30 个房间、顺序、各字段一致（成人公告、`cvExposure`、封面 480、分区为空），只差 `httpHeaders`（见差异 7）；下一页游标、是否还有下一页一致；按游标 1 个请求、按页码第 2 页 2 个请求，与 v3 相同 |
| S04 | 20 个频道卡片（直播中和未开播都有）逐键一致；空结果一致；各 1 个请求 |
| S05 | 频道的 id、名字、头像、简介、粉丝数、`openLive` 一致；不存在的频道 v3 报 identity，现在是 `NotFound`（问题 3） |
| S06-live-detail-live | 进房、刷新、录制详情的房间逐键一致（只差 `httpHeaders`），公告是可回看的那句；画质 `1080p60 · HLS`、`720p60 · HLS`、`480p · HLS`、`360p · HLS`、`144p · HLS` 的名称、id、排序一致，每档 2 个地址（HLS、LLHLS）逐字相同，恢复的地址和应用的画质一致；请求数：进房 4、刷新 2、开播状态 2、录制 4、恢复 4，与 v3 相同 |
| S06-live-detail-offline | 房间是频道卡片（标题是频道名、封面是头像、未开播）逐键一致；v3 取画质得到空列表，现在是 `StreamUnavailable`（问题 5）；进房 2 个请求 |
| S06-live-detail-region、adult | 房间逐键一致（直播中、公告“当前地区受到播放限制。”/“成人分级房间未返回公开匿名媒体源。”、没有封面）；v3 取画质报 `mediaUnavailable`，现在是 `RegionBlocked`、`NeedsLogin`（问题 7）；进房 2 个请求，不请求主列表 |
| S06-live-detail-notfound | v3 报 missing，现在是 `NotFound` |
| S07-master-hls、llhls | 单个主列表的 5 档画质名称、id、排序、地址逐字一致 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 截掉第 31 条时，下一页游标指向本页最后保留的一条 | 问题 1。请求和页大小不变；服务端返回不超过 30 条时与 v3 相同 |
| 2 | 列表里不合规的行跳过或留空，不让整页失败 | 问题 2。只在 v3 失败的地方生效；录到的页面结果相同 |
| 3 | 不存在的频道是 `NotFound` | 问题 3。界面看到的仍是加载失败 |
| 4 | `livePlaybackJson` 读不了时只有进房失败 | 问题 4。进房的结果与 v3 相同，刷新和开播状态不再受影响 |
| 5 | 出错抛类型化错误；未开播、地区受限、成人直播取流时报具体原因 | 问题 5、7、9。状态和公告不变 |
| 6 | 没有 `data` 的房间取流前先进房 | 问题 6。只在播放路径上，v3 在这里报错 |
| 7 | 卡片不写 `httpHeaders`，线路自带请求头、格式、编码、线路编号和有效期 | 问题 11、12。请求头与 `PlaybackHeaderResolver` 的 CHZZK 分支逐项相同；3.x 存下的 `httpHeaders` 读进来照旧保留（`mergeFrom` 只替换 IPTV 的） |
| 8 | 纯音频变体跳过 | 问题 8。现在的主列表没有这种变体，结果相同 |
| 9 | 进房的房间带 `ChzzkDanmakuArgs`（`chatChannelId`） | 给 D01 用，不发请求；`getDanmaku()` 仍是空的 |
| 10 | 调用方的参数错误是 `ArgumentError`/`RangeError`，不是频道号的房间号是 `NotFound`；空关键词返回空 | 问题 14、15。同 v3 一样不发请求 |
| 11 | 响应只在解析前按字符数查 2 MiB；非法 UTF-8 变成替换字符而不是报错 | 问题 10；live_net 没有逐请求的大小上限 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

（E06 平台层升级 已按升级决定改掉其中的固定分区、31 条翻页、搜索的条数和超长关键词、频道主页链接、地区受限的公告、进房时取主列表、不在播时按 `openLive`；累计观看数受阻。见文末“升级落地（E06 平台层升级）”。）

- **目录只有一个固定分区“公开热门直播”**。归档 v4 接了平台真实的分类（`categories/live` 最多 4 页、约 200 个分区，`v2/categories/<类型>/<分区>/lives`，REG-CHZZK-004），会改变发现页和分区页的内容，列为升级候选 1。样本 S01、S02 已经一起复制。
- **翻页照 v3 要 31 条并去掉重复的第一条**：归档 v4 实测游标不含边界，只要 30 条。
- **搜索每页条数按调用方（默认 30）**：归档 v4 固定 20 条；超过 100 字的关键词 v3 拒绝，归档 v4 截断后搜索。
- **频道主页链接 `chzzk.naver.com/<id>` 不识别**：v3 只认 `/live/<id>`，归档 v4 新增了频道主页，列为升级候选 4。
- **没有累计观看数**：归档 v4 把 `accumulateCount` 写成累计，但 3.x 的人数能力表（`audience.dart`）写的是 CHZZK 没有累计，界面会因此多出一个数，列为升级候选 3。
- **标题不做 HTML 实体解码**：归档 v4 解码，v3 原样显示。
- **地区受限的公告只看 `krOnlyViewing`**：归档 v4 把 `blindType: ABROAD` 也算受限。这里只在取流报错时同时看两者，公告和列表卡片照 v3（列表里 `blindType: ABROAD` 的直播照常显示）。
- **不在播的房间是频道卡片**（标题是频道名、封面是头像），状态按 `openLive`。
- **进房时就取两个主列表**（4 个请求），主列表失败则进房失败：归档 v4 在取流时重新请求 `live-detail` 再取主列表。
- **主列表请求带 v3 的整组 API 请求头**，线路只带媒体请求头。
- **图片只接受 NAVER 的两个 CDN**（v3 和上游 TV 的白名单），归档 v4 接受任何 http(s)。
- **主列表用 v3 的严格解析**（现在是共享的 `HlsMasterPlaylist`），归档 v4 用宽松的解析。
- **画质名称带 ` · HLS`**：归档 v4 只写 `1080p60`。
- **详情只接受小写的频道号**，链接里的大写转成小写（v3）。
- 显示名仍是“CHZZK”，目录说明键仍是 `chzzk_directory_scope`。

## 后续升级候选（2026-09-28 用户已采用，编号 20-1～20-10，落地见文末“升级落地（E06 平台层升级）”）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 平台真实的分类和分区房间（REG-CHZZK-004） | 只有一个“公开热门直播” | 归档 v4 规格 §2.1、§2.2；样本 S01、S02。会改变发现页和分区页 |
| 2 | CHZZK 弹幕（匿名只读） | 没有弹幕 | 归档 v4 规格 §7：`comm-api.game.naver.com` 取 accessToken（样本 S08），连 `wss://kr-ss<n>.chat.naver.com/chat`；弹幕帧样本 `danmaku/S09-live`。进房已经记下 `chatChannelId`，由 D01 决定 |
| 3 | 累计观看数（`accumulateCount`） | 不显示 | 归档 v4；需要同时改人数能力表 |
| 4 | 识别频道主页链接 `https://chzzk.naver.com/<id>` | 不识别 | 归档 v4；分享主播时常见 |
| 5 | 超过 100 字的关键词截断后搜索；每页 20 条（与网页一致） | 报错；每页按调用方 | 归档 v4 |
| 6 | 翻页只要 30 条；目录说明里“包含边界项的游标分页”改成实际情况 | 要 31 条；说明文字与录制不符 | 归档 v4 规格 §2.3 的复核（`S03-lives-p1`/`p2`） |
| 7 | 直播已结束而频道仍说 `openLive` 时，以 `live-detail` 为准显示未开播 | 显示直播中，取流报错 | 问题清单后的第一条 |
| 8 | 地区受限的公告也看 `blindType: ABROAD`，列表卡片也提示 | 只看 `krOnlyViewing` | 归档 v4；样本里受限直播两者同时出现 |
| 9 | 进房只读频道和 `live-detail`，取流时再取主列表 | 进房 4 个请求，主列表失败则进房失败 | 归档 v4；进房更快，主列表失败时仍能看到房间 |
| 10 | 可回看的公告（“实时 HLS 已启用；独立时光机回看会话纳入下一协议批次。”）改成用户能看懂的说明 | 3.x 的原文 | 这是开发阶段的说明，M13 翻译时一并考虑 |

## 回归条目的覆盖

归档规格有 4 条，都属于平台层：

- 001（海外受限的直播整页失败）：只请求 `v3.1 live-detail`，从不请求 v2；受限直播照常进房、显示公告，取流报 `RegionBlocked`。样本 `S06-live-detail-region` 和移植的 v3 `chzzk_live_detail_test.dart` 都有测试。
- 002（在线人数显示了平台要求隐藏的值）：目录和详情都只在 `cvExposure` 为 true 时取 `concurrentUserCount`。有测试。
- 003（封面是模板地址）：`{type}` 换成 480，没有时用默认缩略图，都没有则无封面；样本里没有剩下的 `{type}`。有测试。
- 004（发现页只有一个“公开目录”）：按规则保持 v3，测试固定了现在的目录（一个分区，不发请求）；改法见升级候选 1。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 分区名、目录说明（`chzzk_directory_scope`）、三种公告、平台名的繁体和英文 | M13 多语言。本模块给出 3.x 的中文（`ChzzkApi.directoryAreaName`、`directoryScope`、`adultNotice`、`regionNotice`、`timeMachineNotice`） |
| 目录页用游标接口逐页加载、目录说明常驻（3.x `common/base/live_directory_controller.dart:176-199`） | M13 热门页、分区页 |
| 搜索能力表：频道搜索、含未开播、可翻页、没有网页搜索（3.x `modules/search/search_capability.dart:44-48`） | M13 搜索页 |
| 外部打开 `https://chzzk.naver.com/live/<id>`（3.x `modules/live_play/services/room_external_opener.dart:85-87`） | M13；地址由 `ChzzkApi.roomUrl` 和房间的 `link` 提供 |
| 工具箱的链接说明（3.x `zh.json` `toolbox_support_content` 的 CHZZK 一行） | M13 |
| 本地互动包（3.x `local_interaction_controller.dart:401-408`） | M13 |
| 平台列表升级时追加 CHZZK（`favorite_room_controller.dart:72`，`siteCatalogMigration` 第 16 版） | J02.1 |
| 播放和录制按线路的请求头、有效期打开（3.x `playback_header_resolver.dart:174-176`）；令牌到期后是否立即断流（归档规格 §12 待确认 1） | G、H01.1 |
| 录制平台契约（3.x `test/recording_platform_contract_test.dart:29`） | H01.1 |
| 弹幕：`getDanmaku()`、`ChzzkDanmakuArgs`、样本 S08 和 `danmaku/S09-live` | D01 |
| 人数能力（`cvExposure` 决定是否有在线人数） | 已在 E05.1 的 `audience.dart`；3.x `live_room_audience_metric_test.dart` 的 CHZZK 部分已移植为 `live_room_test.dart` |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。主列表用 E03.5 带来的共享 `HlsMasterPlaylist`（未改动），链接用 M3 的 `LiveSiteLinks`、`LinkParser`，JSON 读取用 `json.dart`。

## 测试

93 个用例，`live_core` 共 2056 个（含已合并的 E02.8、E03.6），全部通过：

- `chzzk_api_test.dart`（58 个）：逐个样本对照 v3 的输出（固定目录、目录两页、搜索、频道、五种 `live-detail`、两个主列表和合并后的画质、每档地址），有意的差异逐条断言（`httpHeaders`、不存在、取流原因）；游标（不含边界的录制、v3 的 31 条和去重、截掉时的新游标、非法游标）；不合规的行；REG-CHZZK-001～003；公告顺序；`livePlaybackJson` 的读取和拒绝；画质的排序、合并、纯音频、解析失败；线路的请求头、格式、编码、线路编号、有效期（变体、主列表、四分之一规则）；状态码和 `code` 的映射；链接规则。
- `chzzk_site_test.dart`（35 个），用样本回放加合成回答：
  - 能力、固定目录不请求；
  - 目录：请求地址、请求头、不跟随跳转、第 2 页的 31 条和游标参数、按页码重放的请求数、推荐和分区房间、目录提前结束、调用方错误不请求、20 秒期限和取消在途请求、调用方取消；
  - 搜索：请求参数、偏移、v3 的边界、取消；
  - 房间：进房的 4 个请求（顺序、请求头、不跟随跳转）和与 v3 一致的请求数，只请求 v3.1（REG-CHZZK-001），刷新和开播状态 2 个请求、录制详情、未开播、成人、不存在、非法房间号不请求、刷新合并进 3.x 存下的关注、主列表失败（403 后不再请求 LLHLS、404、看不懂）、`livePlaybackJson` 读不了；
  - 取流：进房得到的房间不再请求、每档地址与 v3 一致、线路属性、卡片先进房、未开播卡片不请求、恢复 4 个请求且地址一致、恢复时画质没了、别的房间的数据不用、别的平台；
  - 错误映射（传输失败、取消、各状态码、`code` 不是 200）；
  - 链接（经 `LinkParser`）：分享文本里的直播页、频道主页和其他主机不识别、不发请求。

## 升级落地（E06 平台层升级）

- 日期：2026-09-29（E03.7）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 10 行（20-1～20-10）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。“落地方式”只有 20-8（模型部分已完成）、20-9（开发预填）写了，其余按上面“后续升级候选”的原文做。20-2（弹幕）的连接属于 D01，这里只给出它要的参数。
- 只改了本平台：`chzzk_api.dart`（解析）、`chzzk_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件（20-3 受阻，人数能力表 `audience.dart` 没有动），没有新依赖，没有新样本。
- 实测：2026-09-28 18:40～19:15 UTC，直连、匿名、用适配器的请求头，只读：全站热门 20 页（600 场）、`categories/live` 翻到底（6 页、228 个分区）、十几个 `live-detail` 和 `polling/v3.1/.../live-status`、两个分区的房间页；最后用新适配器实际走了一遍（分类、分区两页、推荐、进房、取画质、取地址并读到变体列表、地区受限和成人的房间、超长关键词、搜索第 2 页、频道主页链接、刷新）。下面的结论都来自这些回答和已有样本。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 20-1 分类 | 分类改为平台真实的分区（归档 v4 的做法，REG-CHZZK-004）：<br>- `getCategories(1)` 依次读 `/service/v1/categories/live?size=50`，下一页把上一页的 `page.next`（`concurrentUserCount`、`openLiveCount`、`categoryId`）原样作查询参数，最多 4 页（`ChzzkApi.maxCategoryPages`；平台按在线人数排，实测 4 页 200 个分区覆盖 1298 场里的 1269 场，后面的分区都只有一两场）；没有 `next` 或空页就停。第 1 页失败整个分类失败；后面的页失败只到此为止，保留已读的分区。第 2 页起 `getCategories` 仍是空（v3）。<br>- 一级分类是 `categoryType`，顺序固定：游戏（`GAME`）、娱乐（`ENTERTAINMENT`）、体育（`SPORTS`）、其他（`ETC`），不认识的类型排在后面、用原名；没有分区的类型不显示。<br>- 分区：`areaType` 是 `categoryType`，`typeName` 是上面的中文名，`areaId` 是 `categoryId`，`areaName` 是 `categoryValue`（平台的名字，多是韩文，空时用 id），`areaPic` 是 `posterImageUrl`（NAVER CDN 白名单）。平台按人数排，翻页之间人数会变，所以同一个分区可能出现两次（S01 的 200 行里 6 个重复），只留第一次。坏行（类型或 id 不合规）只跳过这一行，整页都是坏行才 `ApiChanged`。<br>- 分区房间：`/service/v2/categories/<类型>/<id>/lives?size=30`，id 按路径段编码（实测有 `Mount_&_Blade2_Bannerlord`，`&` 原样发平台能认）；翻页与热门相同（游标 `concurrentUserCount`、`liveId`，不含边界，S02）；不存在的分区是空的最后一页（S02-category-lives-empty）。行的解析、卡片、受限类型和热门完全相同。<br>- 推荐仍是全站热门 `/service/v1/lives`。v3 的“公开热门直播”（`directory/popular`）不再出现在分类里（它就是推荐页的内容），但仍能打开：`ChzzkApi.popularArea`、`getCategoryRooms`、`getDirectoryPage(AtCursor)` 照 v3 列出全站热门。<br>- 分区的检查：本平台、类型是字母和下划线、id 非空且不含空白、控制字符、`/`、`\`、`?`、`#`，不是 `.`、`..`；`directory` 类型只认 `popular`。不合规是调用方错误（`ArgumentError`），不发请求 | 分类页从一个“公开热门直播”变成游戏、娱乐、体育、其他四组约 200 个分区（英雄联盟、GTA5、Talk、音乐……），每个分区有海报；点进去是这个分区的直播，能继续往下翻。v3 存下的“公开热门直播”分区照常能打开 | 平台层完成，余下 M13（J02.1 不需要迁移分区） |
| 20-2 弹幕 | 平台层只提供参数：进房（`getRoomDetail`）在播且有 `chatChannelId` 时带 `ChzzkDanmakuArgs(channelId, chatChannelId)`，新加的 `channelId` 是房间的频道号——主播重新开播后聊天频道可能换，D01 可以用它重读 `live-detail`。不多发请求；地区受限、成人、未开播的没有（`chatChannelId` 为 null）。`getDanmaku()` 仍是空的弹幕源 | 看不出变化；弹幕在 D01 接入 | 平台层完成，余下 D01 |
| 20-3 累计观看数 | **受阻，没有做**。平台在直播中的所有公开接口都把 `accumulateCount` 写成 0：<br>- 样本：S03 两页、S02 两页共 120 行全是 0；S06 在播、地区受限、成人三场的 `live-detail` 也是 0；只有已结束那场（S06-live-detail-offline）是 161；<br>- 2026-09-29 实测：全站热门 20 页 600 场全是 0；十几场在播直播的 `v3.1 live-detail`、`v2 live-detail`、`polling/v3.1/.../live-status` 都是 0。<br>也就是说累计数只在下播后给出上一场的数字，而 `LiveRoom.totalViewers` 是“这一场的累计”，未开播的房间填上一场的数字会让关注卡片显示一个过时的人数（人数的默认显示顺序里累计排在在线前面）。所以人数能力表不改，`totalViewers` 不填 | 不变：只有在线人数 | 受阻：平台在直播中不给累计数（列表、`live-detail`、`live-status` 的 `accumulateCount` 都是 0，下播后才给上一场的数，2026-09-29 实测 600 场） |
| 20-4 频道主页链接 | `roomIdFromUrl` 另认频道主页 `https://chzzk.naver.com/<频道号>`，允许后面跟一个子页（`/videos`、`/clips`、`/community`、`/about`……），http、https、大小写和 v3 的直播页规则相同，返回小写频道号；不发请求。`/live/<id>/x`、`/<id>/videos/1`、`/video/<号>`、`m.chzzk.naver.com` 仍不认 | 粘贴主播的频道主页链接（分享主播时最常见）能直接打开房间 | 完成（E06 平台层升级） |
| 20-5 搜索 | 每页固定 20 条（`ChzzkApi.searchPageSize`，与网页一致；3.x 的搜索页本来就传 20），偏移 `(页码-1)×20`，调用方的 `pageSize` 不再影响请求（v3 超出 1～30 时返回空）。关键词超过 100 个字符（UTF-16 单位，v3 的量法）截到 100、不切开代理对、再去空白（`ChzzkApi.searchKeyword`），不再报错；实测 100 字的关键词平台正常回答。页码小于 1、空关键词仍返回空不发请求，偏移超过 1000000 仍是调用方错误（v3） | 很长的关键词（例如粘贴了一大段文字）也能搜，不再显示搜索失败；翻页每页 20 个 | 完成（E06 平台层升级） |
| 20-6 翻页和目录说明 | 游标之后也只要 30 条（`ChzzkApi.livesQuery`；v3 要 31 条再去掉重复的第一条）：录制证明游标不含边界（S03-lives-p1 的最后一条就是 `next`，p2 从它之后开始；S02 同样）。去掉与游标同一场的第一行的保护、超过 30 行时截断并把游标指向保留的最后一行（E03.7 问题 1）都还在。<br>目录说明的默认文字 `ChzzkApi.directoryScope` 改成用户看得懂的说法，去掉“包含边界项的游标分页”和 `cvExposure`、`concurrentUserCount` 这些字段名，并说明了新的分类：“推荐是 CHZZK 全站正在直播的频道，按在线人数排序；分类是平台自己的分区。搜索按频道名查找，未开播的频道也会列出。主播关闭人数显示时不显示在线人数。”键仍是 `chzzk_directory_scope`，界面文字和翻译在 M13（英文建议见“留给其他模块”） | 翻页不再多要一条（看不出变化）；目录上方的说明是一句用户看得懂的话（M13 显示） | 平台层完成，余下 M13 |
| 20-7 以直播详情为准 | `live-detail` 说没在播（`CLOSE`、`CLOSED`，或从没直播过）时，房间一律是未开播，不再按频道接口的 `openLive`（两次请求之间主播刚下播时频道还说在播）。关注刷新、`getLiveStatus`、进房、录制详情都一样。反过来 `live-detail` 在播而 `openLive` 还是假时，E03.7 已经按直播详情显示直播中。搜索卡片只有频道接口的数据，仍按 `openLive` | 主播刚下播时关注页不再显示“直播中”、点进去又播不了 | 完成（E06 平台层升级） |
| 20-8 地区受限 | 地区受限的判断看 `krOnlyViewing` 或 `blindType == ABROAD`（实测列表里只有 `blindType`，这些直播的详情两个字段同时为真）：<br>- 详情：公告“当前地区受到播放限制。”也按 `blindType` 出（v3 只看 `krOnlyViewing`），受限类型 `regionBlocked`，取流 `RegionBlocked`（E03.7 已是）；<br>- 列表卡片（热门、分区）：`blindType == ABROAD` 的卡片带同一句公告和 `regionBlocked`（v3 照常显示、没有提示）；成人的卡片照旧带成人公告，受限类型 `adult`；两者都有时按详情的顺序先说地区。<br>用新适配器实测：热门前 6 页 180 场里 10 场地区受限、3 场成人，进房后取流分别是 `RegionBlocked`、`NeedsLogin` | 列表卡片就能看出哪些直播在当前地区看不了（标记在 M13 显示；发现页默认隐藏不能播放的直播也在 M13），不用点进去才发现 | 平台层完成，余下 M13 |
| 20-9 进房两个请求 | 进房（`getRoomDetail`）、录制详情只读频道和 `live-detail`（2 个请求，v3 是 4 个）；`ChzzkRoomData` 只记主列表地址（`media`）或不能播放的原因（`unavailable`）。<br>- 取画质（`getPlayQualities`，另实现 `LiveQualityDiscovery`，取消会传到请求）时才读两个主列表，两个同时发；读到的画质（带线路）跟着这个房间的数据保留（按对象弱引用），之后的 `getPlayUrls`、`resolvePlayUrls` 直接用，不再请求；线路的租期到了（令牌到期前 10 分钟）就重读主列表，主列表的令牌也快到期了就重新进房再读。<br>- 一个主列表失败（403、404、看不懂）只少它的线路（统一原则“容错”，v3 整个进房失败）；两个都失败时报第一个的错误。<br>- `livePlaybackJson` 读不了时进房照常，取画质报 `ApiChanged`（v3 进房就失败）；录制详情仍直接报 `ApiChanged`（录制要的是能取流的详情）。<br>- 恢复（`resolvePlayUrlsForRecovery`）照旧重新进房再读主列表（4 个请求），新线路替换这个房间之前的线路，之后换档用新的 | 进房更快（少两个请求，房间信息先出来）；播放列表出问题时仍能看到房间信息和公告。进房 + 开始播放的请求总数不变（4 个） | 完成（E06 平台层升级） |
| 20-10 回看公告 | 可回看（`timeMachineActive`）的公告从开发说明“实时 HLS 已启用；独立时光机回看会话纳入下一协议批次。”改成“这场直播在 CHZZK 网页上可以回看，本应用只播放实时画面。”（`ChzzkApi.timeMachineNotice`）。出现的条件和顺序不变 | 房间公告是一句看得懂的话 | 平台层完成，余下 M13 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 列表（热门、分区）的每张卡片和在播的详情（进房、刷新、录制）都填 `openDate`：`yyyy-MM-dd HH:mm:ss`，韩国时间（UTC+9）换成 UTC（`ChzzkApi.seoulTime`）。时区的依据：全站热门里最新的开播时间按韩国时间是请求前 4 分钟，按北京时间是一小时后（2026-09-29 实测）；S06 的在播直播按 UTC 理解会晚于录制时刻。未开播（`CLOSE` 的 `openDate` 是上一场的）、格式不对、2000 年以前的不填。搜索卡片（频道搜索）没有开播时间 |
| 受限类型 | 在播的详情：有播放数据 → `none`；否则按取流的报错顺序：地区（`krOnlyViewing` 或 `blindType` 为 `ABROAD`）→ `regionBlocked`，成人 → `adult`，带付费商品（`paidProduct`、`paidProductId`、`watchPartyPaidProductId`）→ `paid`，其他 → `unplayable`；`livePlaybackJson` 读不了 → 不填（看不出来）。列表卡片：地区 → `regionBlocked`，成人 → `adult`，带付费商品 → 不填（没见过，看不出能不能播），其余 → `none`（实测没有标记的 600 场都能播）。未开播、搜索卡片不填。关注刷新读的是完整的 `live-detail`，照样填 |
| 受限的直播改为直播中 | E03.7 已是：地区受限、成人的直播都是直播中。取流：地区 `RegionBlocked`、成人 `NeedsLogin`（E05.2 的表）、付费 `StreamUnavailable`（说明 `paid live`）、其他没有播放数据的 `StreamUnavailable`（`live without playback`），都不请求主列表 |
| 回放、“不可播放” | 不涉及：CHZZK 的直播没有回放状态，时光机是网页上的回看（20-10 的公告） |
| 占位信息 | 适配器没有占位文字。未开播的房间是频道卡片（标题是频道名、封面是头像）、在播标题为空时用频道名，都是 v3 的规则、用的是真实数据，保留。不存在的频道平台给“(알 수 없음)”，E03.7 起就是 `NotFound`，不会当名字 |
| 画质命名 | 表里没有本平台的改名、合并条目，照统一原则保留 v3 的 `1080p60 · HLS` 等名字和 id。`HLS`、`LLHLS` 两个主列表本来就是同一档的两条线路 |
| 默认编码 | 不涉及：实测只有 H.264（`avc1`），线路标了 `avc` |
| 房间身份 | 不变：32 位小写十六进制频道号，已规范成小写，不加进 `SiteIds.caseInsensitiveRoomIds` |
| 按主播关注 | 不涉及：房间本来就是频道 |
| 容错 | 分类的坏行只跳过这一行（20-1）；`livePlaybackJson` 里一个坏的主列表地址只跳过它，都不能用才 `ApiChanged`（v3 整场失败）；一个主列表失败或看不懂只少它的线路（20-9）。列表、搜索的坏行 E03.7 已经只跳过 |
| 翻页 | 不涉及快照：热门、分区、搜索都是平台原生分页，每页一个请求。按页码取第 N 页（`getDirectoryPage`）要从第 1 页重放，重放时前几页出现过的频道不再出现在第 N 页（人数变动会把一场直播挤到下一页）；游标翻页（界面用的）的跨页去重留给 M13 的列表（按房间身份），同斗鱼、niconico |
| 弹幕 | 20-2 |
| 说明文字 | 目录说明（20-6）、回看公告（20-10）；成人公告“成人分级房间未返回公开匿名媒体源。”也是开发说明，改成“成人直播需要登录 CHZZK 并通过年龄验证，本应用暂时无法播放。”（`ChzzkApi.adultNotice`）。地区公告“当前地区受到播放限制。”本来就看得懂，不变 |

### 请求数

| 场景 | v3 / E03.7 | 现在 | 原因 |
|---|---|---|---|
| 分类 | 0 | 最多 4 个，依次发 | 20-1 |
| 热门、分区的一页（游标） | 1 | 1 | — |
| 按页码第 N 页 | N | N | — |
| 搜索 | 1 | 1 | — |
| 关注刷新、`getLiveStatus` | 2 | 2 | — |
| 进房、录制详情 | 4 | 2 | 20-9 |
| 取画质 | 0 | 2（同时发） | 20-9 |
| 取地址、换档 | 0 | 0（线路到期后 2 个；主列表令牌也到期时 4 个） | 20-9 |
| 恢复 | 4 | 4 | — |
| 没有详情数据的卡片取画质、取地址 | 各 4 | 各 4 | — |

进房加开始播放合计 4 个，与 v3 相同；关注刷新和列表没有多请求。

### 画质 id 对照（给 J02.1）

没有变化，不需要对照：画质 id 仍是 `<高>p`（帧率 50 以上加 `60`），名字是 `<id> · HLS`。

### 设置项

无。本平台的 10 行都不需要开关。

### 身份迁移规则（给 J02.1）

- 房间身份不变（频道号），没有按主播关注的条目，不需要迁移。20-4 的频道主页链接解析到同一个频道号。
- 关注的分区：v3 存下的只可能是 `{platform: chzzk, areaType: directory, areaId: popular}`（“公开热门直播”），适配器照常接受，列出全站热门，**不需要迁移**；新目录里没有它，J02.1 保留原样即可。新分区的身份是“平台 + `categoryId`”（`LiveArea.identityKeyFor` 不看父分类），请求时要用存下的 `areaType`（`categoryType`），所以存分区时 `areaType` 不能丢。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出，原因写条目编号；v4 的新键 `startedAt`、`restriction` 由 `_expectParity` 的 `added` 逐个断言；`expected.json` 没有改：

- S03 热门两页：成人卡片的 `notice`（统一原则“说明文字”）；地区受限卡片多了 `notice`（20-8，v3 没有这个键）；每张卡片的 `startedAt`（韩国时间的 `openDate`）和 `restriction`（`regionBlocked`、`adult`、`none`）。房间、顺序、游标、是否还有下一页与 v3 相同。
- S06 在播：`notice`（20-10）；`startedAt`、`none`。地区受限：`startedAt`、`regionBlocked`（公告文字不变）。成人：`notice`（说明文字）；`startedAt`、`adult`。未开播：与 v3 相同。
- S04 搜索、S05 频道、S07 画质和每档地址：与 v3 相同。
- 分类：v3 的一个固定分区换成平台的分区（20-1）；测试断言 v3 的分区 JSON 与 `ChzzkApi.popularArea` 逐字段相同、仍能列出全站热门。
- 请求数：分类 0 → 4（20-1）；进房、录制详情 4 → 2，取画质 0 → 2（20-9，合计不变）；游标翻页要 30 条而不是 31 条（20-6，回放不比较 `size`，测试检查发出的值）。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 弹幕（20-2）：`ChzzkDanmakuArgs(channelId, chatChannelId)`；凭据 `comm-api.game.naver.com/nng_main/v1/chats/access-token?channelId=<chatChannelId>&chatType=STREAMING`（样本 S08-chat-token），服务器 `wss://kr-ss<n>.chat.naver.com/chat`，协议见归档规格 §7 和弹幕帧样本 `danmaku/S09-live`。聊天频道换了（重连被拒）时可以用 `channelId` 重读 `live-detail` |
| G | 取画质会发 2 个请求（可取消，`discoverPlayQualities`）；线路带租期（令牌约 17 小时，提前 10 分钟续，`cutsConnection` 为真），续期走恢复（重新进房，4 个请求）。没有要 G 新做的 |
| H01.1 | 录制详情只有 2 个请求，画质和地址在录制开始取画质时读（2 个请求）；`livePlaybackJson` 读不了时录制详情就报 `ApiChanged` |
| J02.1 | 画质、房间身份、分区都不需要迁移（见上）；按 E05.2 存 `startedAt`、`restriction` |
| M13 | 分类名“游戏、娱乐、体育、其他”的多语言（`ChzzkApi.categoryTypeNames`）；分区名是平台的名字，不翻译。目录说明 `chzzk_directory_scope` 的新文字（20-6），英文建议：“Recommendations are CHZZK's live channels site-wide, by viewers; categories are the platform's own. Search finds channels by name, offline ones included. Viewer counts are hidden when the streamer hides them.” 回看公告（20-10），英文建议：“This stream can be rewound on the CHZZK website; this app plays it live only.” 成人公告，英文建议：“Adult streams need a CHZZK login with age verification, which this app cannot play yet.” 3.x 的键 `chzzk_time_machine_notice`、`chzzk_adult_notice` 的中文照上面改。卡片按 `restriction` 标出地区受限、成人（20-8），发现页默认隐藏不能播放的直播；开播时间只在直播中显示。“公开热门直播”（`chzzk_public_directory`）只剩已关注的分区会用到。工具箱的链接说明（`toolbox_support_content` 的 CHZZK 一行）加上频道主页 `https://chzzk.naver.com/<频道号>`（20-4）。搜索页不用再为 CHZZK 传每页条数 |

### 受阻

- **20-3 累计观看数**：平台在直播中不给累计数，见上表。以后平台在直播中给出非 0 的 `accumulateCount` 时，把它填进 `totalViewers`、人数能力表的 CHZZK 行改成有累计即可；测试 “20-3 is blocked” 守着现在的样本。

没有样本、只靠实测或字段名的部分：
- 付费直播：没有找到在播的例子（600 场里 `paidProductId`、`watchPartyPaidProductId` 都是 null，详情的 `paidProduct` 也是 null）。按字段名判断：详情没有播放数据且带付费商品时标 `paid`；列表卡片带付费商品时受限类型不填。
- `blindType` 除 `ABROAD` 以外的取值（归档规格 §12 待确认 5）：没有见到。

### 新样本

无。分类和分区房间用归档已有的 S01、S02（E03.7 已复制，当时 v3 不请求）。实测的请求只用于核实，没有录成样本。

### 测试

本平台 121 个用例（E03.7 是 93 个，新增 28 个，另改写了分类、翻页、搜索、进房、取流的用例），`live_core` 共 3284 个，全部通过：

- `chzzk_api_test.dart`（75 个）：
  - 20-1：S01 四页的分类（类型的顺序和名字、194 个分区、去重、字段、平台顺序）、`next` 与下一页的查询一致、坏行和未知类型、v3 的分区仍有效、分区检查、分区房间的地址（`&`、中文和 `%` 的编码）；S02 两页、游标不含边界、不存在的分区；
  - 样本对照：上面列出的 `changed:` 和 `added`；
  - 20-8：热门里地区受限、成人、普通卡片的公告和受限类型，两者都有、只有 `krOnlyViewing` 的行；带付费商品的行；
  - 开播时间：韩国时间换算、坏值；`seoulTime`；
  - 20-6：30 条的查询、录制里发出的条数、保护和截断；目录说明不含开发术语；
  - 20-5：关键词截断（代理对、再去空白）；
  - 20-7：频道仍说在播、从没直播过都是未开播；
  - 20-10 和成人公告的文字；
  - 详情的受限类型和取流原因（有播放数据、地区、成人、付费、其他、读不了）；房间数据；
  - 20-3 受阻的证据（样本里在播的 `accumulateCount` 都是 0，人数能力表没有累计）；
  - 容错：`livePlaybackJson` 里的坏地址只跳过它；一个主列表看不懂只少它的线路；
  - 线路的租期、续期判断（`linesFresh`、`mastersFresh`、`masterExpiry`）；画质 id 与 v3 相同；
  - 20-4：频道主页（带或不带子页、大小写、http），仍不认的地址。
- `chzzk_site_test.dart`（46 个）：
  - 20-1：分类的 4 个请求（查询、请求头、不跟随跳转）、第 2 页不请求；没有 `next` 就停、后面的页失败保留前面、第 1 页失败报错、最多 4 页；分区按游标和按页码、不存在的分区；v3 的分区列出全站热门；
  - 按页码重放时去掉前几页出现过的频道；调用方错误不请求（别的平台、不安全的 id、`directory` 的其他 id）；
  - 20-6：第 2 页请求 30 条，与录制的查询相同；
  - 20-5：每页 20 条、偏移、不看 `pageSize`；超长关键词截断后请求；v3 的边界；
  - 20-9：进房 2 个请求（与 v3 的 4 个对照）、房间数据、弹幕参数带频道号；录制详情 2 个、加取画质共 4 个（与 v3 相同）；取画质读两个主列表，之后取地址、换档、再取画质都不请求；取地址在取画质之前也只读一次；线路到期重读主列表、令牌到期重新进房；取消传到主列表请求；一个主列表 403 或 404 只少它的线路；两个都失败报第一个；`livePlaybackJson` 读不了时进房照常、取画质和录制详情报 `ApiChanged`；
  - 20-7：频道说在播、详情说已结束时刷新、开播状态、进房都是未开播，不请求主列表；
  - 恢复 4 个请求、地址与 v3 相同、新线路替换旧线路；
  - 20-4：频道主页经 `LinkParser`（含分享文本）不发请求；
  - 原有的地区受限、成人、未开播、不存在、非法房间号、合并进 3.x 的关注、错误映射。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.17 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.17-CHZZK弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
