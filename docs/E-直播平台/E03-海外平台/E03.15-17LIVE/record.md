# E03.15 17LIVE

- 日期：2026-09-28
- 平台 id：`17live`（`SiteIds.seventeenLive`）。Dart 的文件名和类名不能以数字开头，所以代码目录、类名用 `seventeenlive` / `SeventeenLive`（与 v3 的 `legacy/lib/core/site/seventeenlive/` 相同）。
- 目标：`packages/live_core/lib/src/sites/seventeenlive/`（`seventeenlive_api.dart` 纯解析，含链接；`seventeenlive_site.dart` 请求编排）
- 样本：`fixtures/17live`，全部来自归档（2026-09-27 直连录制，匿名）：
  - v3 会请求的：日本区推荐第 1 页和按游标的第 2 页 `S01-sections-jp`、`S01-sections-jp-p2`，搜索 `S03-search`（花音）、`S03-search-none`（`[]`），房间 `S04-live-live`、`S04-live-offline`、`S04-live-notfound`（HTTP 520）；
  - v3 不请求的：台湾区推荐 `S02-sections-tw`（只用来多对照一次目录解析，见下文），弹幕帧 `danmaku/S05-live`（D01 用）。
- 参考：
  - 归档 v4 的 17LIVE 适配器和规格（`spec/sites/17live.md`，回归条目 REG-17LIVE-001～004）；
  - pure_live_TV `lib/platforms/seventeenlive/`：与 v3 逐行相同，只改了导入路径，卡片的在线、累计、粉丝缺值时写空串（对照笔记 `~/ref/notes/tvcore/small_diffs.txt`、`sub_B.md` 的 seventeenlive 一节），没有行为修复。笔记列为“不建议照搬”的“420 等于限流”，这里改掉了（差异 2）。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口照 v3**：`LiveSite` 和 v3 实现过的全部可选能力——游标目录（`LiveSiteCursorDirectoryPager`，含按页码的 `LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `seventeen_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、带实际画质的取流（`LivePlayUrlResolver`，给出线路）、恢复时重新取流（`LivePlayRecoveryResolver`），另加 `LiveSiteLinks`。v3 没有的 `LiveSearchPaginationPolicy`、`LivePlayLeaseMetadata` 不加。3.x 的 JSON 不变。
- **没有分类**：v3 没有覆盖 `getCategores`、`getCategoryRooms`（基类返回空），这里同样用 `LiveSite` 的默认实现，不发请求。
- **匿名，照 v3**：所有请求以 `17live` 的名义发出（代理路由由应用按平台注入），**不跟随跳转**，不带 Cookie。v3 没有 17LIVE 的登录和 Cookie 设置，所以不注入 `CookieVault`，也没有账号请求。请求头是 v3 的两组（桌面 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Origin: https://17.live`）：
  - 推荐区块和搜索：`Accept-Language: ja-JP,ja;q=0.9,en;q=0.8`，`Referer: https://17.live/`（`SeventeenLiveApi.catalogHeaders`）；
  - 房间：`Accept-Language: en-US,en;q=0.9`，`Referer` 是房间页 `https://17.live/en/live/<号>`（`requestHeaders`）。
- **请求照 v3**（都在 `api-dsa.17app.co`）：

  | 调用 | 请求 | 次数 |
  |---|---|---|
  | 分类、分区房间 | 不请求，空列表（v3 的基类默认） | 0 |
  | 目录一页（按游标） | `GET /api/v1/sections?count=20&typeTab=2&region=JP&cursor=<游标>`，第 1 页游标为空 | 1 |
  | 目录第 N 页（按页码，1～20）、推荐 | 从第 1 页逐页重放；推荐取第 N 页的前 `pageSize` 个 | N |
  | 搜索（只有第 1 页） | 房间号或 17LIVE 链接：`GET /api/v1/lives/<号>`；其他关键词：`GET /api/v1/liveStreams/search?query=<关键词>` | 1 |
  | 关注刷新、开播状态、进房、录制详情、恢复 | `GET /api/v1/lives/<号>`（回答里就有拉流地址） | 1 |
  | 取画质、取地址（进房得到的房间） | 不请求 | 0 |
  | 没有 `data` 的房间取流 | 同进房 | 1（v3 直接失败） |

- **房间身份与 v3 一致**：房间号是主播固定的 `liveStreamID`（等于 `userInfo.roomID`），按请求时的写法（去掉首尾空白），必须是 1～12 位、不以 0 开头的数字。`userId` 是主播的 UUID `userID`，也是拉流文件名。样本里所有房间号都与 `expected.json` 一致。
- **卡片照 v3 的 `_card`**：标题 `caption`（空时主播名），主播名 `displayName`（空时 `openID`），头像 `userInfo.picture`，封面 `coverPhoto`（为 null 时 `thumbnail`），简介 `userInfo.bio`，粉丝 `followerCount`；`audioOnly == 1` 时分区显示“音频直播”，否则为空；人数口径“在线”，直播中才有在线 `liveViewerCount` 和本场累计 `viewerCount`（未开播时回答里是上一场的，不显示）；每个房间都带公告“17LIVE 要求观看者年满 18 周岁。”；`link` 是 `https://17.live/en/live/<号>`，`watching` 为空。图片只接受 `cdn.17app.co`、`assets-17app.akamaized.net` 或裸文件名（拼到 `cdn.17app.co`），一律 https。
- **列表照 v3**：
  - 目录：跳过 `TopBanner`、`ArchiveVideo`、`Vod` 区块，其余区块（标签、新人、PK、连麦等）里只收直播中的房间，同一页一个房间只出现一次；下一页游标为空或与本页相同时结束；
  - 搜索：官网的当前直播搜索，一页，截成 `pageSize` 个；
  - 列表的每一行都按 v3 `_room` 的规则检查（房间号、主播、`userID` 一致，名字不为空，文字、人数的类型），不合规的行跳过，与 v3 完全相同（v3 在这里就是跳过）。目录的行没有 `userInfo.roomID`，不要求；搜索的行要求有，与 v3 相同。
- **详情照 v3**：`lives/<号>` 的 `liveStreamID`、`userInfo.roomID`（必须有）要等于请求的房间号，`userID` 要等于 `userInfo.userID`，否则 `ApiChanged`（v3 的 identity）；`status` 2 是直播中、0 是未开播，其他值是“未知”状态（v3 同样），开播状态查询这时报 `ApiChanged`。
- **画质和线路照 v3**：
  - 拉流地址取 `pullURLsInfo.rtmpURLs`（没有时 `rtmpUrls`），每项是一个 CDN（腾讯 `tencent-global-pull-rtmp.17app.co`、网宿 `wansu-global-pull-rtmp-latency.17app.co`），按回答的顺序；
  - 四档，顺序、名称、排序值照 v3：`增强高清 · FLV`（`enhanced`，400，`urlQualityEnhancedHD`）、`高清 · FLV`（`hd`，300，`urlLowBitrateHD`、`webUrl`、`url`）、`H.264 · FLV`（`h264`，200，`url264`）、`标准 · FLV`（`standard`，100，`urlLowQuality`、`webUrlLowQuality`、`urlHighQuality`）；每个 CDN 的每个字段都是一条线路，同一地址只留一次，没有地址的档不列出；
  - 地址必须是 `*.17app.co` 上含 `pull-rtmp` 的主机、`.flv` 路径，照原样使用（腾讯的是 http，v3 就这样播放）；
  - 每条线路带 v3 `PlaybackHeaderResolver` 里 17LIVE 的请求头（UA、`Origin`、`Referer` 房间页），格式 FLV，线路编号是 CDN（`tencent`、`wansu`），H.264 档标编码 `avc`（其他档跟随主播的编码，可能是 FLV codec 12，不标）；地址没有签名，不设有效期；
  - 服务端不降档，应用的画质就是请求的画质。
- **取流前的检查**：进房的 `SeventeenLiveRoomData` 带着画质和线路，取画质、取地址都不再请求。不能播放时说明原因：未开播 `StreamUnavailable`，未知状态 `ApiChanged`，直播中却没有拉流地址 `StreamUnavailable`。平台明确未开播的房间、进房时已知不能播的房间，取流和恢复都直接报，不发请求（v3 同样）；恢复时重新进房（v3），同一个画质 id 必须还在。
- **弹幕**：v3 没有 17LIVE 弹幕（`EmptyDanmaku`），传给弹幕连接的参数为空，所以不输出弹幕参数类，`getDanmaku()` 仍是空的。归档规格的 Ably 频道名就是房间号，令牌由 `messenger/auth` 匿名取得，进房时不需要多记任何东西（D01）。
- **链接**（`roomIdFromUrl`，不发请求）：照搬 v3 的 `SeventeenLiveLink.parse`——http(s)，主机正好是 `17.live`（不分大小写，端口不限），没有用户信息，路径（忽略空段，段名不分大小写）`/live/<号>`、`/<语言>/live/<号>`、`/profile/r/<号>`、`/<语言>/profile/r/<号>`，语言是两个字母加可选的 `-` 后缀。17LIVE 没有短链。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/seventeenlive/seventeenlive_api.dart`，`S` = `core/site/seventeenlive/seventeenlive_site.dart`，`L` = `core/site/seventeenlive/seventeenlive_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 不存在的房间报“服务故障”；用房间号或链接搜索一个不存在的房间，整个搜索失败（REG-17LIVE-004） | A:133-138、A:259-267、S:155-161 | 17LIVE 用 **HTTP 520** `{"errorMessage":"stream not found"}` 表示房间不存在（样本 `S04-live-notfound`）；`_defaultRequest` 丢掉非 200 的正文，`_fetch` 把 5xx 一律当 `service`，而搜索只对 `missing`（404）返回空 | 非 200 时读错误正文，`stream not found` 是 `NotFound`；搜索没有结果 |
| 2 | 参数被拒当成“限流” | A:264 | 把 HTTP 420 当成 Twitter 式的限流；归档规格实测 420 `errorCode 7` 是参数错误（`invalid channel type`、`no such section`） | `ApiChanged`（上游笔记同样建议不照搬） |
| 3 | 直播中却没有拉流地址时，房间直接打不开 | S:113-118 | “不能播”当成“详情失败”（`mediaUnavailable` 从 `_detail` 抛出） | 进房照常返回直播中的房间，取流时报 `StreamUnavailable` |
| 4 | 未开播的房间取画质得到空列表，播放器拿不到原因 | S:203 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 5 | 没有 `data` 的房间（列表卡片、搜索结果、刷新过的关注）取画质报 identity；恢复也要先有进房的快照 | S:169-174、S:216-218 | 只认进房时放进 `data` 的快照 | 先进房再取（1 个请求）；恢复本来就重新进房 |
| 6 | 拉流数据一变，关注刷新、开播状态和按房间号搜索也跟着失败 | A:166-175、A:297、S:129-131、S:157 | `room()` 每次都解析拉流地址（`includeStreams` 默认为真），刷新也不例外 | 刷新和搜索不读拉流地址；进房读不懂拉流数据时仍失败（同 v3） |
| 7 | 详情里一个字段不合预期（名字为空、标题或简介不是文字、人数为负），整个房间打不开 | A:295-313、A:403-431 | 列表行的严格规则也用在详情上 | 详情里这些字段留空；房间号、主播、`userID` 的核对仍严格（`ApiChanged`）。列表行照 v3 跳过，列表内容不变 |
| 8 | 一个区块或格子不是对象（或 `grids` 不是列表），整页目录失败；区块超过 80 个、格子超过 200 个、搜索结果超过 100 条也整页失败 | A:188、A:192-195、A:228 | 这几处在逐行的 `try` 之外检查 | 跳过这个区块或格子；数量上限去掉（解析前已按 4 MiB 限制大小） |
| 9 | 路径解不开的链接（如 `%FF`）让 `SeventeenLiveLink.parse` 抛 `FormatException`，搜索和链接导入直接失败 | L:12 | `pathSegments` 解码失败没有捕获 | 不算链接 |
| 10 | 失败都是平台自己的 `SeventeenLiveException`，播放、录制只能按种类名判断 | A:11-30 | 平台自定义异常 | 类型化错误（见差异 3） |
| 11 | 平台层依赖全局 `HttpClient`，自己实现流式读取（4 MiB、20 秒）和请求作用域 | A:81-84、A:115-164 | 结构问题 | 注入 `LiveHttp`；超时由 live_net 的逐请求超时（20 秒）负责；4 MiB 在解析前按字符数检查（同 v3 `_fetch` 的第二道检查） |
| 12 | 媒体请求头按平台写在播放层，每个房间还带着一份没人读的 `httpHeaders`；房间号不合规时 `mediaHeaders` 抛 `FormatException` | phr:177-179；S:102；A:109-113、L:38-42 | 地址和请求头分开放；`httpHeaders` 是 IPTV 的字段 | 线路自带请求头（值与 v3 相同，由已校验的房间号生成）；房间不再写 `httpHeaders` |
| 13 | 平台层调用界面翻译（分区、公告、四个画质名） | S:88、S:101、S:185-191 | `i18n` 写在适配器里 | 用 3.x 的中文作默认文字（`SeventeenLiveApi.audioRoom`、`ageNotice`、`qualityNames`、`directoryScope`），界面的翻译在 M13 |
| 14 | 调用方传错参数（页码、游标、分区、每页条数、别的平台的房间）报平台的 schema、identity 错误 | S:47-49、S:63、S:76、S:106-111、A:180-182 | 本地校验失败用平台错误 | `ArgumentError`/`RangeError`，不发请求；不是房间号的 id 是 `NotFound`，不发请求 |

另外几处按 v3 保留：

- **带“冒号”的关键词不搜索**（S:164）：`Uri.tryParse(query)?.hasScheme` 把 `Re:Zero` 这类关键词也当成网址，直接返回空。改了会让搜索结果变多，列为升级候选 5。
- **详情要求 `userInfo.roomID`**（A:282-285）：录到的 `lives/<号>` 都有，列表行都没有；归档 v4 允许详情里缺它。
- **第 2 页可能出现第 1 页已有的房间**（样本里连麦区块的 `28571668`）：v3 只在一页内去重，跨页去重由目录页面做（3.x `live_directory_controller.dart:209`，M13）。

## v3 的冻结输出

归档没有 17LIVE 的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了）。本模块用 `fixtures/17live/legacy_expected.dart` 生成，做法同 PandaTV、CHZZK：

- 把 v3 的 `SeventeenLiveApi`、`SeventeenLiveLink`、`SeventeenLiveSite`（`legacy/lib/core/site/seventeenlive/` 三个文件）原样搬进一个 Dart 程序。v3 本来就把传输做成可注入的函数（`SeventeenLiveRequest`），所以只换了它：按主机、路径和查询参数读样本；状态码不是 200 时正文为空（同 v3 的 `_defaultRequest`）；没有样本的请求抛 StateError，v3 的 `_fetch` 会把它变成 `transport`，所以另外记下、在调用结束后重新抛出，缺样本会让生成失败；
- 网络路径上的 `_defaultRequest`、`readBody` 没有搬；Dio 的 `CancelToken` 只留 v3 用到的成员；`SeventeenLiveSite` 保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`，构造函数改为必须注入 API；`i18n` 返回 3.x `zh.json` 的文字；v3 的模型只搬用到的部分（同 CHZZK 的脚本）；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记下发出的请求地址；
- v3 只请求日本区。台湾区样本 `S02-sections-tw` 是把日本区的请求用它来回答（匹配时不比 `region`），只作为目录解析的第二份对照；
- 在仓库根目录运行：`dart run fixtures/17live/legacy_expected.dart`，只用 Dart SDK。连续运行两次，输出逐字节相同。

8 个样本都有 `expected.json`：

- `S01-sections-jp`：平台名、目录说明键、按游标第 1 页、按页码第 1 页、推荐（30 个、每页 5 个），调用方错误（第 0 页、第 1 页带游标、第 2 页没有或是空游标、带分区、第 0 页和第 21 页、每页 0 个，都不发请求），列表卡片取画质（v3 报 `identity`）；
- `S01-sections-jp-p2`：第 1 页的游标，按游标第 2 页，按页码第 2 页和第 3 页；`S02-sections-tw`：台湾区的第 1 页（见上）；
- `S03-search`、`S03-search-none`：搜索（默认、每页 1 个、第 2 页、每页 0 个）；
- `S04-live-live`、`S04-live-offline`、`S04-live-notfound`：进房、刷新、录制、开播状态、别的平台，按房间号、直播页链接、主播页链接和第 2 页搜索；能进房的另有画质、每档地址、`resolvePlayUrlsRaw`、恢复和不存在的画质；`S04-live-live` 另有非法房间号、三组请求头和 28 个链接向量的 `parse`、`parseOrId`、`normalizeRoomId`。

## 样本的脱敏

复制后按“访客编号、设备编号、令牌、Cookie、出口 IP 等真实标识”搜了一遍全部样本。归档的录制规则漏掉了两处，已换成同形的合成值，并在各自的 `meta.json` 的 `scrubbed` 里记为 `synthetic (E03.15)`：

- **`S03-search`**：17LIVE 的搜索接口会把**主播完整的私人账户记录**放进 `userInfo`（访问令牌、密码散列、邮箱、电话、设备编号等），归档规则只处理了守护者字段。替换的是：`userInfo.accessToken`（UUID）、`password_bcrypt`（bcrypt 形）、`email`、`localPhoneNumber`、`internationalPhoneNumber`、`deviceID`、`appsflyerID`、`birthday`、`pontaMemberID`、`referralV2Code`、`contract.id`、`contract.streamerID`，以及 `deviceInfo.publicIP`（换成文档保留地址 `203.0.113.7`）、`deviceInfo.deviceID`。除 IP 外长度都与原值相同，JSON 其余内容逐字节不变；适配器不读这些字段。
- **`S01-sections-jp`、`S01-sections-jp-p2`**：连麦区块 `groupCallInfo` 的观众令牌 `viewerToken`（Agora，`007eJx…`）和 `referralCode`。
- 已确认样本里不再有任何原值，也没有别的 IPv4 地址（只剩 UA 里的 `Chrome/140.0.0.0` 和替换后的 `203.0.113.7`）。响应头里的 `trace-id` 与斗鱼、虎牙等平台的样本一样保留；弹幕帧的令牌、连接编号、观众编号和昵称归档时已经换过。
- **注意**：GitHub 上的归档分支 `archive/v4`（`fixtures/17live/S03-search/body.json`、`S01-sections-jp*/body.json`）仍是原值，是否处理由用户决定（本模块不改归档分支）。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和每档地址；请求比较地址和次数。所有房间只有 `httpHeaders` 一个键不同（差异 8）。

| 样本 | 结果 |
|---|---|
| S01 日本区第 1 页（30 个） | 房间、顺序、各字段一致；下一页游标、是否还有下一页一致；按游标、按页码都是 1 个请求，地址与 v3 相同；推荐 30 个、每页 5 个一致 |
| S01 第 2 页 | 1 个房间（连麦区块）、没有下一页，一致；按游标 1 个请求、按页码第 2 页 2 个请求；第 3 页 2 个请求、空页，一致 |
| S02 台湾区（只对照解析） | 20 个房间逐键一致，游标一致 |
| S03 搜索 | 1 个房间逐键一致（有粉丝和本场累计）；空结果一致；每页 1 个一致；第 2 页、每页 0 个不发请求 |
| S04 直播中 | 进房、刷新、录制的房间逐键一致，各 1 个请求；四档画质的名称、id、排序和每档 2 个地址逐字一致，`resolvePlayUrlsRaw` 不发请求、应用的画质一致；恢复 1 个请求、地址一致；开播状态 true；按房间号、直播页、主播页搜索各 1 个请求、结果一致 |
| S04 未开播 | 房间逐键一致（没有在线和累计）；开播状态 false；v3 取画质得到空列表，现在 `StreamUnavailable`，两者都不发请求 |
| S04 不存在（520） | v3 进房、刷新、录制、开播状态、按房间号和链接搜索都报 `service`；现在详情是 `NotFound`，搜索没有结果 |
| 调用方错误 | v3 报 `schema`/`identity`，现在是 `ArgumentError`/`RangeError`/`NotFound`，都不发请求 |
| 链接 | 28 个向量中 27 个与 v3 相同；`%FF` 的 v3 抛异常，现在不算链接 |
| 请求头 | 三组与 v3 逐项相同（名称改成小写） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | HTTP 520 `stream not found` 是 `NotFound`：房间打不开时报“不存在”，按房间号或链接搜索没有结果 | 问题 1（REG-17LIVE-004）。只在 v3 失败的地方生效 |
| 2 | HTTP 420 是 `ApiChanged` | 问题 2 |
| 3 | 出错抛类型化错误：401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，400 和 420 `ApiChanged`，其他 5xx、其他状态（含跳转）和传输失败 `NetworkFailure`，看不懂的回答、答非所问的房间、未知状态 `ApiChanged`；取消原样抛出；调用方的参数错误 `ArgumentError`/`RangeError`，不是房间号的 id `NotFound`，同 v3 不发请求 | 问题 10、14。界面看到的仍是加载失败 |
| 4 | 直播中却没有拉流地址的房间照常进入，取流时报 `StreamUnavailable`；未开播的房间取画质报 `StreamUnavailable` 而不是空列表 | 问题 3、4。状态和公告不变 |
| 5 | 没有 `data` 的房间取流前先进房 | 问题 5。只在播放路径上，v3 在这里报错 |
| 6 | 刷新和按房间搜索不读拉流地址 | 问题 6。结果相同，拉流数据异常时不再连带失败 |
| 7 | 详情里不合规的字段留空；目录里不是对象的区块、格子跳过，不让整页失败 | 问题 7、8。录到的页面和房间结果相同；列表行的跳过规则不变 |
| 8 | 房间不写 `httpHeaders`；线路自带请求头、格式、编码（H.264 档）和线路编号 | 问题 12。请求头的值与 `PlaybackHeaderResolver` 的 17LIVE 分支逐项相同；3.x 存下的旧值照读、`mergeFrom` 照留 |
| 9 | 路径解不开的文字不算链接 | 问题 9 |
| 10 | 没有 20 秒的读取总期限，由每个请求的 20 秒超时代替；响应在解析前按字符数查 4 MiB；非法 UTF-8 变成替换字符而不是报错 | 问题 11；同 E03.7 等模块 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **目录只有日本区推荐，没有分类**：归档 v4 有日本、台湾、香港三个区（`S02-sections-tw` 已复制），会改变发现页，列为升级候选 1。
- **画质名称和顺序照 v3**：`增强高清 · FLV`、`高清 · FLV`、`H.264 · FLV`、`标准 · FLV`。归档 v4 实测“标准”就是主播推上来的原始流，改名“原画”排第一，并默认选 H.264 档避开 FLV codec 12（REG-17LIVE-001）。v3 在播放层用 `FlvLegacyHevcRelay` 处理 codec 12（G），画质菜单和默认档位会变，列为升级候选 2。
- **拉流地址照原样**（腾讯是 http）：归档 v4 升级成 https（实测可用），列为升级候选 3。
- **每个 CDN 的每个字段都是一条线路**：归档 v4 每个 CDN 只取第一个非空字段。样本里同一 CDN 的几个字段地址相同，结果一样。
- **媒体请求头是 UA、`Origin`、`Referer` 房间页**（v3、上游 TV 相同）；归档 v4 只带 UA 和站点根的 `Referer`。两者都能播。
- **API 请求头分两组、房间请求的 `Referer` 是房间页**；归档 v4 用一组。
- **`ArchiveClip` 区块不跳过**（v3）：归档 v4 跳过它。这个区块里没有直播中的房间，结果相同。
- **搜索照 v3**：只有第 1 页，截成 `pageSize` 个；超过 100 字没有结果（归档 v4 截断后搜索）；房间号形式的关键词只按房间查，不做关键词搜索；带网址格式（有 scheme）的关键词没有结果。
- **房间链接写 `/en/live/<号>`**（v3 的 `url`），归档 v4 写 `/ja/`；**`www.17.live` 不识别**（归档 v4 识别，它会 301 跳到 `17.live`），列为升级候选 6。
- **详情要求 `userInfo.roomID`**、**其他状态值是未知状态**：归档 v4 允许缺 `roomID`，把其他状态值当 `ApiChanged`。
- **没有开播时间**：归档 v4 读 `beginTime`，`LiveRoom` 没有这个字段，列为升级候选 7。
- **标题不做 HTML 实体解码**，同 v3 和归档 v4。
- 显示名仍是“17LIVE”，目录说明键仍是 `seventeen_directory_scope`，公告和音频分区是 3.x 的中文原文。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复；它把在线、累计、粉丝缺值写空串，这里同样写空串（`mergeFrom` 因此保留存下的值）。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 增加台湾、香港区（`region=TW`、`HK`），做成分类和分区 | 只有日本区推荐，没有分类 | 归档 v4 规格 §2.1；样本 `S02-sections-tw`。会改变发现页和分区页 |
| 2 | “标准”改名“原画”并排第一；默认选 H.264 档 | 四档照 v3，播放层用中转处理 codec 12 | 归档 v4 规格 §5、§6.4（REG-17LIVE-001）；等高通硬解验证（REG-PLAY-022，G）后再定默认档 |
| 3 | 拉流地址一律 https | 腾讯 CDN 用 http | 归档 v4 实测腾讯两种都能用 |
| 4 | 17LIVE 弹幕（Ably，匿名令牌） | 没有弹幕 | 归档 v4 规格 §7：`POST messenger/auth` 取令牌，连 `wss://17media.realtime.ably.net`，ATTACH 频道名就是房间号，消息 gzip+base64；弹幕帧样本 `danmaku/S05-live`（D01） |
| 5 | 带冒号的关键词（`Re:Zero`）照常搜索；超过 100 字截断后搜索 | 没有结果 | 问题清单后的第一条；归档 v4 |
| 6 | 识别 `www.17.live` 的链接 | 不识别 | 归档 v4 规格 §1 |
| 7 | 显示开播时间（`beginTime`） | 不显示 | 归档 v4；`LiveRoom` 没有开播时间字段 |

## 回归条目的覆盖

归档规格有 4 条，都属于平台层（001 另有播放层的部分）：

- 001（部分房间只有声音或黑屏：手机开播的原始流和增强档是 FLV codec 12）：平台层给 H.264 档的线路标上 `avc`，其他档不标编码，播放层据此判断（有测试）。默认档位按规则保持 v3（升级候选 2）；v3 的 codec 12 中转在 G。
- 002（一半线路 404：同一时刻只有列表里第一个 CDN 在服务）：线路按回答里 CDN 的顺序给出（样本里腾讯在前），有测试。
- 003（拉流 403：拉流主机检查 Referer）：每条线路都带 `Referer`（和 `Origin`、UA），值与 v3 相同，有测试。
- 004（不存在的房间报“服务故障”）：HTTP 520 `stream not found` 是 `NotFound`，按房间号和链接搜索没有结果；样本 `S04-live-notfound` 和合成回答都有测试。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕（v3 没有）；`getDanmaku()`；弹幕帧样本 `danmaku/S05-live` | D01（升级候选 4）；同 E01.1，D01 用一张“平台 → 弹幕连接”的表 |
| 目录说明（`seventeen_directory_scope`）、年龄公告、音频分区、四个画质名、平台名的繁体和英文 | M13 多语言。本模块给出 3.x 的中文（`SeventeenLiveApi.directoryScope`、`ageNotice`、`audioRoom`、`qualityNames`、`displayName`） |
| 目录页用游标接口逐页加载、跨页去重、目录说明常驻（3.x `common/base/live_directory_controller.dart:176-209`） | M13 热门页 |
| 搜索能力表：只有当前直播、不能翻页、没有网页搜索（3.x `modules/search/search_capability.dart:49-53`） | M13 搜索页 |
| 外部打开 `https://17.live/en/live/<号>`（3.x `modules/live_play/services/room_external_opener.dart:91-96`） | M13；地址由 `SeventeenLiveApi.roomUrl` 和房间的 `link` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:409-416`） | M13 |
| 平台注册和图标（3.x `core/sites.dart:74`、`201`、`261-264`、`409-413`） | I01.1 应用骨架；平台 id 已在 M3 的 `SiteIds.seventeenLive` |
| 平台列表升级时追加 17LIVE（`favorite_room_controller.dart:74`，`siteCatalogMigration` 第 18 版） | J02.1 |
| 播放和录制按线路的请求头打开（3.x `playback_header_resolver.dart:177-179`）；codec 12 的 FLV 中转（3.x `player/core/flv_legacy_hevc_relay.dart`、`fvp_adapter.dart:73` 及其测试）；录制时改写成 enhanced FLV | G、H01.1 |
| 录制平台契约（3.x `test/recording_platform_contract_test.dart:30`） | H01.1 |
| 人数能力（`liveViewerCount` 在线、`viewerCount` 累计） | 已在 E05.1 的 `audience.dart` |
| 3.x 的链接工具和网页搜索解析里的 17LIVE 分支（`live_url_tool.dart:114`，`web_search_room_parser.dart:92-95`） | 已由本模块的 `LiveSiteLinks` 加 M3 的 `LinkParser` 代替 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。链接用 M3 的 `LiveSiteLinks`、`LinkParser`；v3 的整数、文字、图片规则逐条照搬在本平台的解析里（与 `json.dart` 的 `jsonInt` 等规则不同，例如 `2.0` 不算整数），所以没有改用通用工具。

## 测试

64 个用例，`live_core` 共 2697 个，全部通过：

- `seventeenlive_api_test.dart`（34 个）：逐个样本对照 v3 的输出（日本区两页、台湾区、两个搜索、三个房间、四档画质和每档地址、请求头、28 个链接向量），有意的差异逐条断言（`httpHeaders`、520、未开播取画质、`%FF`）；v3 `seventeenlive_public_catalog_test.dart` 里解析部分的移植（区块、游标、搜索、详情的 `roomID`）；列表行的 12 种跳过规则；不是对象的区块和格子；游标的检查；身份核对、未知状态、详情字段留空、音频分区；拉流：没有地址、读不懂、`rtmpUrls` 兜底、每个字段一条线路、缺档、地址规则；线路的请求头、格式、编码、线路编号、没有租期；状态码映射；图片规则；REG-17LIVE-001～004。
- `seventeenlive_site_test.dart`（30 个），用样本回放加合成回答：
  - 平台名、目录说明、能力、没有分类、没有弹幕；
  - 目录：请求地址、请求头、不跟随跳转、第 2 页的游标、按页码重放的请求数、第 3 页的空页、推荐的条数、调用方错误不请求、取消（请求前、重放中）；
  - 搜索：地址、请求头、结果与 v3 一致；只有第 1 页、截成每页条数；不搜索的情况（空白、超长、网址、`www.17.live`、`%FF`、带冒号）；按房间号、直播页、主播页搜索（直播中和未开播）；不存在的房间没有结果，其他失败照抛；取消；
  - 房间：进房、刷新、录制、开播状态各 1 个请求，地址和请求头与 v3 相同；不存在、非法房间号不请求；未知状态；读不懂的拉流数据只让进房失败；刷新合并进 3.x 存下的关注；
  - 取流：进房得到的房间不再请求、每档地址与 v3 一致；恢复 1 个请求、地址一致；恢复时画质没了、已下播；未开播不请求；直播中没有地址；卡片先进房；别的主播的数据不用；别的平台；
  - 错误映射（传输失败、取消、各状态码、看不懂的回答）；
  - 链接（经 `LinkParser`）：分享文本里的直播页和主播页，`www.17.live` 和其他页面不识别，没有短链，不发请求。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.15）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 7 行（33-1～33-7）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。“落地方式”写了的是 33-2（“标准”改名“原画”排第一，默认档用 22-3 的“优先 H.264”设置）、33-3（开发预填：看不出变化）、33-7（模型部分已完成），其余按上面“后续升级候选”的原文做。33-4（弹幕）属于 D01，本次只在平台层给出弹幕参数（见 33-4）。
- 改动：只改了本平台：`seventeenlive_api.dart`（解析）、`seventeenlive_site.dart`（请求编排）、两份测试和 2 个新样本（见“新样本”）。没有改 `live_core` 的通用文件（新类 `SeventeenLiveDanmakuArgs` 在本平台的文件里，经已有的导出公开），没有新依赖，`expected.json` 没有改。
- 上面几节里的这些说法现在改了：“没有分类”（33-1）；“保持 v3 行为”里的目录只有日本区（33-1）、画质名称和顺序（33-2）、拉流地址照原样（33-3）、搜索的冒号和 100 字（33-5）、`www.17.live` 不识别（33-6）、没有开播时间（33-7）；“做法”里的“弹幕：不输出弹幕参数类”（33-4）和“进房读不懂拉流数据时仍失败”（容错，见“按统一原则补的”）。其余照旧：房间身份、卡片字段、公告、音频分区、请求地址和请求头、状态码映射、线路的请求头和编号。
- 实测：2026-09-28 20:50～21:01 UTC，经本机代理（出口不在中国大陆）、匿名、只读，请求头同 v3：
  - 日本、台湾、香港三个区的 `sections` 第 1 页都是 HTTP 200，结构与 S01 相同（香港区另有 `Post`、`JPSubtitle` 区块，`Post` 的格子没有 `stream`，照旧跳过），在播分别约 34、21、32 个；
  - 腾讯 CDN 的拉流地址改成 https 后照常出流：2 个日本区直播间（28600349、29153029）的原画和 H.264，http 和 https 都读到 `FLV` 文件头；军团房间 376827 的 H.264 两种都是 HTTP 200 并持续出数据（与归档 v4 的实测一致）；列表里第二个 CDN（网宿）这时不出流，同 REG-17LIVE-002；
  - 搜索 `Re:Zero`（`Re%3AZero`）和 150 个字符的关键词都是 HTTP 200 `[]`，接口接受冒号，也不拒绝长关键词；
  - 官网网页脚本（`17.live/assets/entry-*.js`）里受限直播的判断：`premiumContent.premiumType` 的枚举是 `NONE 0`、`PAID 1`、`ARMY 2`、`NEW_USER 3`，`isLocked = premiumType 非 0 且 paymentInfo.paid 为假`，锁住的直播网页不进房（`sn` 返回 `!isLocked`）；
  - 香港区里的军团限定直播 376827（`premiumType 2`，`armyInfo.requiredArmyRank 1`）：列表和 `lives/376827` 都是直播中，**回答里照样带着两个 CDN 的拉流地址**，匿名能读到流（v3 会直接播放）。约 8 分钟后再请求时它已下播。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 33-1 台湾、香港区 | 新增一个分类（`SeventeenLiveApi.category`：id `region`，名字“地区”），三个分区：日本 `JP`、台湾 `TW`、香港 `HK`（`LiveArea` 的 `areaType` 是 `region`、`areaId` 是 `region` 参数的值）。`getCategories` 第 1 页返回这个分类，不发请求。分区房间和目录：`getDirectoryPageAtCursor`、`getDirectoryPage`、`getCategoryRooms` 接受这三个分区，请求 `sections?count=20&typeTab=2&region=<区>&cursor=<游标>`，解析、游标、请求头与推荐完全相同；按页码的第 N 页照旧从第 1 页重放 N 个请求。推荐仍是日本区（v3），日本分区与推荐是同一个请求。别的平台的分区、别的 id（如 `US`：归档 v4 实测它只是日本和香港的混合）是调用方错误（`ArgumentError`），不发请求。3.x 存下的分区（`LiveArea.fromJson`）照样能用，`areaId` 不分大小写。<br>目录说明 `seventeen_directory_scope` 的文字改成用户看得懂的中文，并提到三个区（见“按统一原则补的”） | 分区页多了“地区”分类：日本、台湾、香港三个分区，各自是官网该区首页推荐里正在直播的房间（样本：台湾区 20 个、香港区 32 个），可以按游标一直翻到底。推荐页不变 | 平台层完成，余下 M13（J02.1 不需要迁移：v3 没有 17LIVE 的分区） |
| 33-2 原画排第一、默认 H.264 | 3.x 的“标准”就是主播推上来的原始流（地址没有后缀，归档规格 §5），id 从 `standard` 改成 `source`，名字“原画 · FLV”，`sort` 500（最高；v3 是 100，最低）；其余三档的 id、名字、`sort` 不变。画质按“原画、增强高清、高清、H.264”存放（`SeventeenLiveRoomData.qualities`）；列出时按“优先 H.264”排（`SeventeenLiveApi.playQualities`，适配器每次取画质时读设置）：开（默认）时 H.264 档排第一（它是唯一一定是 AVC 的档，其余档跟随主播的编码，可能是 FLV codec 12，REG-17LIVE-001），然后原画、增强高清、高清；关时原画排第一。没有 H.264 档时两种顺序相同。<br>名字保留 v3 的“ · FLV”后缀：v3 的全局画质偏好按名字精确匹配（“原画”“蓝光8M”…），“原画 · FLV”对不上“原画”，所以默认偏好“原画”的用户落到列表第一个，“优先 H.264”开时就是 H.264（见“留给其他模块”的 G 一条）。<br>取流、恢复取流照样接受 3.x 的 id `standard`（按对照当作 `source`，确认的画质报新 id），漏迁的也能播 | 画质菜单从“增强高清、高清、H.264、标准”变成“H.264、原画、增强高清、高清”（“优先 H.264”关时“原画、增强高清、高清、H.264”），“标准”改叫“原画”；默认播放 H.264 档，手机开播的房间不再默认落到可能只有声音或黑屏的档 | 平台层完成，余下 G/M9/M13 |
| 33-3 拉流地址一律 https | `SeventeenLiveApi.pullUrl` 把 http 地址改成 https（主机转小写，去掉显式的 80 端口，路径和查询不变）；带其他显式端口的 http 地址照原样（不知道它的 https 端口，样本和实测里没有）。同一条流的 http 和 https 地址算同一条线路。线路编号、请求头、编码、格式不变 | 看不出变化（腾讯 CDN 两种都能播，实测见上） | 完成（T02.U） |
| 33-4 弹幕 | 平台层：新类 `SeventeenLiveDanmakuArgs(roomId)`，进房（`getRoomDetail`）和录制详情的房间在 `danmakuData` 里带着它，直播中、未开播、受限都带（Ably 频道名就是房间号，属于主播，不随场次变）；关注刷新、列表和搜索卡片不带。不发请求。连接（`messenger/auth` 匿名令牌、`wss://17media.realtime.ably.net`、ATTACH 频道、gzip+base64 消息）留给 D01，照归档规格 §7 和弹幕帧样本 `danmaku/S05-live` | 本次不变（仍没有弹幕，`getDanmaku()` 仍是空的） | 平台层完成，余下 D01 |
| 33-5 冒号和超长关键词 | 不再用“有没有 URI scheme”判断网址（`Re:Zero` 的 `Re` 被当成 scheme），改为只有 `<scheme>://` 开头的才算网址（`SeventeenLiveApi.isUrl`）：不是 17LIVE 房间链接的网址照旧没有结果、不发请求；`Re:Zero`、`mailto:x`、`12:30` 这类照常搜索。关键词去首尾空白后截到 100 个 UTF-16 码元，不切开代理对，再去一次空白（`SeventeenLiveApi.searchKeyword`，同 CHZZK 20-5）。房间号和房间链接的判断在截断之前，照旧 | 搜 `Re:Zero` 这类带冒号的词、超过 100 字的词都有结果了（v3 直接返回空） | 完成（T02.U） |
| 33-6 `www.17.live` | 链接的主机可以是 `17.live` 或 `www.17.live`（`SeventeenLiveApi.webHosts`，不分大小写；归档规格 §1 实测 `www` 会 301 跳到 `17.live`），路径规则不变；其他子域名（`m.17.live`）仍不算。链接导入（`LinkParser`）、分享文本和搜索框都认 | 粘贴或搜索 `https://www.17.live/…/live/<号>`、`…/profile/r/<号>` 能直接打开房间（v3 不认） | 完成（T02.U） |
| 33-7 开播时间 | `startedAt` 取 `beginTime`（Unix 秒，按 UTC；不是整数、2000 年以前、2100 年以后的不填，`SeventeenLiveApi.startTime`），只在直播中填；未开播的回答也带 `beginTime`（上一场的，S04-live-offline），不填。`lives/<号>` 和搜索结果有这个字段，所以关注刷新、进房、录制详情、按房间号和链接搜索、关键词搜索都有；目录的区块行没有这个字段（S01、S02 都没有），目录卡片没有开播时间，关注刷新后补上 | 直播中的房间显示开播时间（M13 决定怎么显示） | 平台层完成，余下 M13 |

### 按统一原则补的

| 原则 | 做了什么 |
|---|---|
| 开播时间 | 见 33-7 |
| 受限类型 | 按官网的判断（见“实测”）读 `premiumContent`：`premiumType` 1（付费的 Premium Live）→ `paid`，2（军团限定）→ `subscribersOnly`，其他非 0 的（3 `NEW_USER` 和以后的新种类）→ `unplayable`；没有 `premiumContent`（`lives/<号>` 不写这个键，搜索结果写 null）、`premiumType` 为 0 或空、`paymentInfo.paid` 为真 → `none`；`premiumContent` 不是对象 → 留空（看不出来）。只在直播中填，未开播、状态不明留空。目录行、搜索结果、关注刷新、进房、录制都一样（都是完整的直播对象，所以轻量刷新也能看出来）。3.x 不读这些字段，形状不对只留空，不会让列表行被跳过 |
| 受限的直播改为直播中 | 状态本来就是直播中（3.x 不看受限），现在标出受限类型。进房照常，但不读受限直播的拉流地址：取画质、取地址、恢复都报 `StreamUnavailable`，原因写明（“a live for the broadcaster's army members only”“a premium live, for viewers who paid”“a locked live (unplayable)”），`SeventeenLiveApi.lockedLive`。回答里其实带着地址（v3 会播放），但官网对未入团、未付费的观众锁住这些直播，照统一原则不绕过。开播状态查询对受限直播返回真；录制详情照常返回（直播中 + 受限类型），取流报错 |
| 占位信息 | 没有占位的名字、标题、封面：名字为空时留空（E03.15 已如此，界面显示平台名），没有标题时用主播名（v3 的做法，是真实的名字），封面是截图或主播图。台湾区常见的标题“<名字> 正在開播，快來看播喔！”是 17LIVE 自己给没写标题的直播生成、在官网上照样显示的标题，不算占位，照旧 |
| 回放、不可播放 | 不适用：`lives/<号>` 只有直播中（2）和未开播（0），目录照旧跳过回放区块（`ArchiveVideo`、`Vod`） |
| 房间身份 | 不变：数字房间号，大小写无关（E05.2 表里的“不忽略”一栏） |
| 按主播关注 | 本来就是：房间号是主播固定的 `roomID`，不按场次 |
| 容错 | 拉流数据：一个 CDN 不是对象、一个地址字段不是文字只丢掉它自己（v3 让整个房间打不开），超过 16 个 CDN 只读前 16 个，`rtmpURLs` 不是列表只丢掉拉流数据；丢掉的记下原因。什么都读不出来时，房间照常进入，取流报 `ApiChanged` 并写明丢掉了什么（本来就没有地址时仍是 `StreamUnavailable`）。列表行、区块、格子的跳过规则不变 |
| 翻页 | 按游标翻页本身就是一份快照（游标里带着时间）；按页码的重放、跨页去重（目录页，M13）照旧 |
| 画质命名、默认编码 | 见 33-2 |
| 弹幕 | 见 33-4（D01） |
| 说明文字 | 目录说明（键 `seventeen_directory_scope`，`SeventeenLiveApi.directoryScope`）从“官网日本区公开推荐按原生游标加载，不代表全站目录；搜索覆盖官网当前直播窗口……”改成“推荐和分区里是 17LIVE 官网日本、台湾、香港区首页推荐的直播，不是全部直播。搜索只能找到正在直播的主播；也可以输入房间号，或粘贴 17LIVE 的直播间或主页链接。”。年龄公告、“音频直播”本来就是给用户看的，不变 |

### 请求数

| 场景 | E03.15 | 现在 | 原因 |
|---|---|---|---|
| 分类 | 0（没有分类） | 0 | 33-1：分类是固定的 |
| 分区房间：按游标一页 / 按页码第 N 页 | 没有 | 1 / N | 33-1：与推荐相同 |
| 推荐、目录（日本区） | 1 / N | 1 / N | — |
| 关注刷新、开播状态、进房、录制详情、恢复 | 1 | 1 | — |
| 取画质、取地址（进房得到的房间） | 0 | 0 | — |
| 受限直播取流（进房后 / 卡片） | 0 / 1（v3 能播） | 0 / 1（报原因） | 统一原则 |
| 搜索：带冒号的关键词、超过 100 字的关键词 | 0（没有结果） | 1 | 33-5（条目本身要求） |
| 搜索、链接导入：`www.17.live` 的链接 | 0（没有结果） | 1 / 0 | 33-6（搜索按房间号查 1 次，链接导入不发请求） |
| 拉流数据读不懂的房间：进房 / 取流 | 1（失败） / — | 1 / 0（报 `ApiChanged`） | 容错 |

### 画质 id 对照（给 J02.1）

| v3 的 id（v3 的名字） | 新 id（新名字） |
|---|---|
| `standard`（标准 · FLV） | `source`（原画 · FLV） |
| `enhanced`（增强高清 · FLV） | 不变 |
| `hd`（高清 · FLV） | 不变 |
| `h264`（H.264 · FLV） | 不变 |

- 代码：`SeventeenLiveApi.legacyQualityIds`（常量表 `{'standard': 'source'}`）、`SeventeenLiveApi.qualityIdFromLegacy(id)`（去首尾空白、不分大小写查表，表外的 id 原样返回，套用两次结果不变）。取流、恢复取流直接接受旧 id。
- 3.x 的全局画质偏好按名字存（原画、蓝光8M、蓝光4M、超清、流畅），17LIVE 的四个名字都带“ · FLV”，改名前后都对不上，偏好不用迁移；这张表给 v4 按房间存下的画质用。

### 设置项

| 名字 | 默认 | 含义 | 接口 | 留给 |
|---|---|---|---|---|
| `preferH264`（“优先 H.264”，统一原则的全局设置，与 8-8、14-5、22-3 共用） | 开 | 开：H.264 档排第一（默认播放），然后原画、增强高清、高清；关：原画、增强高清、高清、H.264（最好的档在前） | `SeventeenLiveSite(http, preferH264: () => 设置值)`，每次取画质时读，改了不用重建适配器；`SeventeenLiveApi.playQualities(data, preferH264: …)` | J02.1 存储；M13 设置界面；G 评估默认值 |

### 身份迁移规则（给 J02.1）

不需要：房间身份仍是主播固定的 `liveStreamID`（数字，大小写无关），没有按场次关注的旧数据。3.x 没有 17LIVE 的分区，没有要迁移的已关注分区。3.x 存下的房间 JSON 照读（新字段 `startedAt`、`restriction` 只在有值时写）。

### 与 v3 冻结输出的新差异

样本对照测试里写明，原因写条目编号；`expected.json` 没有改：

- 直播中的房间（S01、S02 台湾区的卡片，S03 搜索，S04 直播中的进房、刷新、录制）多了 `restriction: none`；S03 和 S04 直播中另有 `startedAt`（2026-09-27T17:54:44Z）。测试断言 3.x 的输出里没有这两个键；未开播的房间两个都没有。进房和录制的房间另带 `danmakuData`（`toJson` 不写）。
- S04 直播中的画质：名字、id、顺序、原画的 `sort` 变了（33-2），测试按对照逐档比较：3.x 的每个 id 经 `qualityIdFromLegacy` 对上一个新画质，名字按“标准 → 原画”对上，每档地址就是 3.x 的地址换成 https（33-3），用 3.x 的 id 取流也能取到。3.x 的“不存在的画质”用的是 id `source`，现在就是原画（33-2）。
- 28 个链接向量里 `https://www.17.live/ja/live/27484154` 从“不是链接”变成房间（33-6），其余 27 个照旧（`%FF` 仍按 E03.15 不算链接）。
- 搜索：`Re:Zero`、超过 100 字的关键词、`www.17.live` 的链接从“没有结果、不发请求”变成各 1 个请求（33-5、33-6）。
- 分类：3.x 没有（基类默认的空列表），现在是一个分类三个分区（33-1）；台湾区样本经 `region=TW` 的请求读出的房间、游标与 3.x 的解析一致。
- 读不懂的拉流数据不再让进房失败（容错）。

### 新样本

两个都是 2026-09-28 经本机代理（`127.0.0.1:7897`）用 curl 只读地请求，请求头同 v3（桌面 Chrome UA、`Accept`、`Accept-Language`、`Origin`、`Referer`），正文按归档格式（两格缩进）写出，`meta.json` 的 `tool` 写明 `manual capture (E03.15): curl, checked by hand`，`raw` 是原始正文的 SHA-256 和长度。v3 不会请求它们，所以没有 `expected.json`（与 CHZZK 的补录样本相同），测试里直接断言：

- **`S02-sections-hk`**（20:52:47 UTC）：香港区推荐第 1 页，32 个在播房间，其中军团限定的 376827 在播（`premiumContent.premiumType 2`）。脱敏：`Post` 区块两条帖子里 `taggedOpenID` 标注的观众昵称（主播感谢入团的粉丝）按归档的 `person` 规则换成“观众1”“观众2”，帖子正文 `caption` 里 `@<昵称>` 的提及同样替换；记进 `scrubbed`（`$.sections[*].grids[*].post.taggedOpenID[*]`、`$.sections[*].grids[*].post.caption`）。主播的名字、头像、帖子是公开信息，保留。没有 `groupCallInfo` 令牌和守护者字段。
- **`S04-live-army`**（20:53:08 UTC）：`lives/376827`，军团限定的直播中房间，回答里带着拉流地址。脱敏同归档规则：守护者（观众）`guardianUserID`（`person`）、`guardianPicture`（`secret`）换成同形的合成值。
- 两个样本都按“访客编号、设备编号、令牌、Cookie、IP、邮箱、电话”等字段名和 UUID 逐一检查过：没有这类字段（`lives` 回答不带搜索接口那种私人账户记录），没有任何 IPv4（`device` 字段里的 `2.252.0.0` 是 App 版本号）；替换前的原值在输出里都找不到；门禁的 `fixture privacy` 通过。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| 17LIVE 弹幕连接（33-4）：`SeventeenLiveDanmakuArgs.roomId` 就是 Ably 频道名；令牌 `POST https://api-dsa.17app.co/api/v1/messenger/auth`（JSON `{}`，`provider` 不是 1 时不连）；`wss://17media.realtime.ably.net/?access_token=…&format=json&heartbeats=true&v=3`，ATTACH（10）频道、服务端 15 秒心跳、`MESSAGE`（15）的 `data` 是 gzip+base64 的 JSON（归档规格 §7，样本 `danmaku/S05-live`） | D01 |
| 默认画质：v3 选默认画质时先按名字精确匹配偏好，对不上就按比例落档。“优先 H.264”开时，偏好“原画”的用户落到第一个（H.264），但偏好“蓝光8M”“超清”“流畅”的用户按比例会落到原画、增强高清、高清（可能是 codec 12）。应改为“优先 H.264”开时只在标了 `codec: avc` 的档里选（17LIVE 只有 H.264 档标 `avc`，其余档编码未知）；如果改成去掉“ · FLV”后缀再按名字匹配，同样要跳过没标 `avc` 的档。codec 12 的播放（v3 的 `FlvLegacyHevcRelay`）、高通硬解验证（REG-PLAY-022）后再评估“优先 H.264”的默认值；线路全是 https | G |
| 录制：原画的 `sort` 现在最高（500），按 `sort` 选档的录制会默认录原画（v3 录增强高清）；原画、增强高清、高清可能是 FLV codec 12，写入时改写成 enhanced FLV。受限直播的录制详情是直播中 + 受限类型，取流报 `StreamUnavailable`，应按 `restriction` 停下，不要当作临时失败反复重试 | H01.1 |
| 存 `preferH264`；按上面的对照迁移存下的 17LIVE 画质 id（`standard` → `source`） | J02.1 |
| “优先 H.264”的设置界面；分类“地区”和分区“日本”“台湾”“香港”、画质名“原画”（3.x 的 `seventeen_quality_standard`）的多语言；目录说明的新文字（见“按统一原则补的”）和它的繁体、英文，英文建议：“Recommended and area pages list the live streams on the 17LIVE website's Japan, Taiwan and Hong Kong home pages, not every stream. Search finds only broadcasters who are live; you can also enter a room number or paste a 17LIVE live or profile link.”；卡片按 `restriction` 标“仅军团成员”“付费”“不可播放”，发现页默认隐藏（关注和搜索照常显示），播放错误说明需要加入军团或付费，不引导登录（本应用没有 17LIVE 登录）；开播时间只在直播中显示；3.x 搜索能力表（`search_capability.dart`）里 17LIVE 的说明可以去掉“带冒号的关键词不搜索”这类限制 | M13 |

### 受阻

没有。33-4 的连接部分按计划属于 D01，平台层需要的参数已经给出。

没有样本、只靠合成回答的部分：付费的 Premium Live（`premiumType 1`）和 `NEW_USER`（3）的直播（实测时三个区都没有在播的）；带显式端口的 http 拉流地址；读不懂的拉流数据。

### 测试

本平台 85 个用例（E03.15 是 64 个；新增 21 个，另改写了画质、地址、链接、搜索、拉流容错的用例），`live_core` 共 3471 个，全部通过：

- `seventeenlive_api_test.dart`（47 个）：
  - 与 v3 的对照：目录（日本区两页、台湾区）、搜索、三个房间的 `startedAt` 和 `restriction` 两个新键（3.x 没有；未开播不填）；画质按 id 和名字对照、地址换成 https 后逐字一致、3.x 的 id 能取流；28 个链接向量（`www.17.live` 一条改为房间）；
  - 33-1：分类和三个分区、`regionOf`（3.x 存下的分区、大小写、别的 id 和别的平台是调用方错误）、`sectionsQuery` 的区参数、香港区样本（32 个房间、军团房间是直播中 + `subscribersOnly`）、台湾区里未开播的军团行不列出；
  - 33-2：两种顺序、没有 H.264 档时的顺序、`legacyQualityIds` 和 `qualityIdFromLegacy`、`source` 取流；
  - 33-3：`pullUrl` 的升级规则（大小写、80 端口、其他端口、已是 https）、http 和 https 同一条流只算一条线路；
  - 33-5：`searchKeyword` 的截断（代理对、再去空白）、`isUrl`；
  - 33-6：`www.17.live` 的各种写法和不算的主机；
  - 33-7：`beginTime` 的范围、类型、未开播、目录行带了也读；
  - 受限：军团样本（进房和刷新都是直播中 + 受限、开播时间、取流原因、弹幕参数），`premiumContent` 的 12 种形状在刷新和搜索行里一致、未开播和状态不明留空、三种锁的原因、读不懂的照常播放；
  - 容错：读不懂的拉流数据进房成功、取流 `ApiChanged`；一个坏 CDN、坏字段只丢自己并记下原因；超过 16 个 CDN。
- `seventeenlive_site_test.dart`（38 个）：
  - 分类不发请求；台湾、香港区按游标 1 个请求（地址、请求头、不跟随跳转）、分区房间截成每页条数、台湾区房间与 3.x 的解析一致；日本分区就是推荐（请求与 3.x 相同）；3.x 存下的香港分区按页码重放、每个请求都带 `region=HK`；不是分区的参数不发请求；
  - 搜索：带冒号、`mailto:`、超过 100 字（含代理对）各 1 个请求且关键词正确；网址和空白不发请求；`www.17.live` 链接 1 个请求、结果有开播时间；
  - 房间：读不懂的拉流数据进房成功、取流报错不再请求；军团样本在进房、刷新、录制、按房间号搜索里都是直播中 + 受限，开播状态为真，取流、取地址、恢复都报原因且不发请求，卡片先进房一次；进房和录制带弹幕参数，刷新和卡片不带；
  - 取流：进房后四档不发请求、默认顺序、地址是 3.x 的地址换成 https、旧 id 能取流；“优先 H.264”每次读、开关两种顺序、默认开；恢复 1 个请求、地址一致、确认的画质报新 id；
  - 链接：`www.17.live` 在分享文本里、大写主机、主页链接都识别，不发请求；`m.17.live` 等仍不识别。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.30 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.30-17LIVE弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
