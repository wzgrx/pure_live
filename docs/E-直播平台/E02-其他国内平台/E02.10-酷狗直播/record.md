# E02.10 酷狗直播

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/kugoulive/`（`kugoulive_api.dart` 纯解析，含链接；`kugoulive_site.dart` 请求编排）
- 样本：`fixtures/kugoulive`，12 个，全部来自归档（2026-09-27 直连录制，匿名）：首页 `S01-home`，推荐两页 `S02-recommend-p1`、`-p2`，舞蹈分区 `S03-area-7024-p1`，房间信息 `S04-room-live`、`-mobile`（手机开播）、`-offline`、`-notfound`，取流 `S05-stream-live`、`-offline`，搜索 `S06-search`、`-empty`。v3 没有酷狗弹幕，归档也没有弹幕样本，所以没有 `danmaku` 目录。
- 参考：
  - 归档 v4 的酷狗适配器和规格（`spec/sites/kugoulive.md`）。规格没有 REG-KUGOULIVE 条目，只有 §10“踩过的坑”两条（见“回归条目的覆盖”）；
  - pure_live_TV `lib/platforms/kugoulive/`：与 v3 逐行相同，只改了导入路径，卡片缺的在线、热度、粉丝写空串而不是 null（对照笔记 `small_diffs.txt`、`sub_A.md` 的 kugoulive 一节），没有行为修复。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

> T02.U（2026-09-29）按用户批准的升级改了列表的手机开播状态、详情的标题和公告、搜索的在线人数、分享页链接、公告文字、取流地址的 `token` 校验和 HEVC 标记，另按统一原则填了开播时间和受限类型，并查明 v3 当作“受限”的 `limitType` 其实是公聊限制（受限房间照常显示直播中、照常播放），见文末“升级落地（T02.U）”（29-1～29-8）。本节以下是 E02.10 时的做法。

## 做法

- **接口照 v3**：`LiveSite` 和 v3 实现过的全部可选能力——原生目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `kugoulive_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、带实际画质的取流（`LivePlayUrlResolver`，给出线路）、恢复时重新取流（`LivePlayRecoveryResolver`）、租期查询（`LivePlayLeaseMetadata`），另加 `LiveSiteLinks`。3.x 的 JSON 不变。
- **匿名，照 v3**：所有请求以 `kugoulive` 的名义发出（代理路由由应用按平台注入），带 v3 的请求头（桌面 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Origin: https://fanxing.kugou.com`、`Referer: https://fanxing.kugou.com/`，首页和取流接口也是这一组），**不跟随跳转**，不带 Cookie，每个请求 20 秒。v3 没有酷狗的登录和 Cookie 设置，所以不注入 `CookieVault`，也没有账号请求。
- **请求照 v3**：

  | 调用 | 请求 | 次数 |
  |---|---|---|
  | 分类 | `GET https://fanxing.kugou.com/`，读一次、在适配器的生命周期内保留（读失败下次再读） | 首次 1，之后 0 |
  | 推荐、推荐分区（8000） | `GET fx1.service.kugou.com/mfanxing-home/h5/cdn/room/index/list?<v3 的 15 个参数>&page=<n>` | 1 |
  | 其他分区 | 同上，路径 `index/list_v4`，另加 `cid=<分区 id>` | 1 |
  | 关键词搜索 | `GET /pt_search/pcsearch/v1/type_all.jsonp?keywords=<词>&nums=200,0,0,0&callback=pureLive<微秒>`，每页都重新请求，在本地按页切 | 1 |
  | 房间号或房间链接搜索（第 1 页） | `GET service2.fanxing.kugou.com/roomcen/room/web/cdn/getEnterRoomInfo?roomId=<号>` | 1 |
  | 关注刷新、开播状态 | `getEnterRoomInfo` | 1 |
  | 进房、录制详情、恢复取流 | `getEnterRoomInfo`；直播中再 `GET /video/pc/live/pull/mutiline/streamaddr?std_rid=<号>&…&_=<毫秒>`（v3 的 10 个参数） | 1～2 |
  | 没有 `data` 的房间取流 | 同进房 | 1～2（v3 直接失败） |

  查询参数的顺序和编码与 v3 的 `Uri.replace(queryParameters:)` 逐字节相同，测试逐个对照冻结输出里记下的请求。
- **房间身份与 v3 一致**：房间号是 3～11 位数字（`^[1-9]\d{2,10}$`），保持请求时的写法；房间链接（`fanxing.kugou.com/<号>`、`mfanxing.kugou.com/?roomId=<号>`）换成号码，同 v3 的 `_roomId`。主播的 `userId`、`kugouId` 不作身份，照 v3 写进 `userId`（有 `userId` 用它，否则 `kugouId`）。样本里所有房间号都与 `expected.json` 一致。
- **分类照 v3**：一个分类“酷狗直播”（id `kugoulive`），分区是首页里带 `title` 的 `/pcindex/category/<id>` 链接，按页面顺序、每个 id 一次，去掉关注、我看过的、我管理的、我守护的四个个人页，“推荐”（8000）保留为第一个分区；分区类型 `official`，`typeName` 是“酷狗直播”；首页一个分区链接都没有时用 v3 写死的 14 个；`pageSize` 照 v3 截取。分区名的实体解码用通用的 `decodeHtmlEntities`。
- **卡片照 v3**（推荐、分区、搜索共用）：
  - 状态取 `liveStatus`，没有时 `status`，再没有 `liveType`：1 直播中，0、-1 未开播，其他（包括手机开播的 6）未知；
  - 标题依次 `label`、`topicContent`、`performContent`、昵称，都没有时 `Kugou Live`；昵称 `nickName`，空时 `Kugou Live`；
  - 头像 `userLogo`（字段不存在时 `logo`），空时用封面；封面 `imgPath`，不存在时 `imagePath`。图片按 v3 的规则整理：修正重复的 `/v2/fxuserlogo/`，协议相对地址补 https，以 `/` 开头的补 `https://p3.fx.kgimg.com`，http 换 https，只接受 `kgimg.com`、`kugou.com` 及其子域的默认端口地址；
  - 在线 `viewerNum`（分区是 `getViewerNum`）、热度 `hot`、粉丝 `fansCount` 各放各的，有在线时口径是在线，否则热度，再否则未知（3.x 的人数能力表：酷狗有热度和列表在线）；
  - 分区一律写“酷狗直播”，链接是房间页，公告是 3.x 的中文“酷狗远端聊天尚待接入；……”（`KugouLiveApi.chatNotice`）。
- **详情照 v3**（`getEnterRoomInfo`）：
  - 状态：`limitType` 大于 0 是受限（显示为未知，公告前加 v3 的“该酷狗直播受访问范围限制，……”），`liveType` -1 未开播，有 `liveSessionId` 直播中，其余未知；
  - 标题依次 `publicMesg`、`privateMesg`、昵称；头像 `userLogo`、封面 `imgPath`、粉丝 `fansCount`；没有在线和热度（列表卡片有，界面按 3.x 的做法保留卡片的人数）；
  - 房间不存在（`normalRoomInfo` 没有昵称且 `kugouId` 为 0）是 `NotFound`（问题 1）。
- **画质和线路照 v3**：
  - 取流接口每条线路（`sid`）的每个 `streamProfiles` 按“协议:码率档:编码:布局”分组（`flv:4:1:2`），`httpsFlv` 是 FLV、`httpsHls` 是 HLS；同一地址只取一次（先出现的线路为准）；只收 v3 认可的地址：https、`liveplay.live.kugou.com` 及其子域、默认端口、没有用户名和片段、`/live/` 下的 `.flv`（HLS 为 `.m3u8`）、带 `txSecret`、十六进制的 `txTime` 和以 `0-<房间号>-` 开头的 `token`；没有地址的组丢掉；按码率档从高到低，同档按回答里的顺序；
  - 名称 `FLV 码率档 4`（3.x `zh.json` 的 `kugoulive_quality_rate`），id 是组名，排序值码率档 × 10 加 2（FLV）或 1（HLS）；确认的画质就是组名（v3）；
  - 每个地址一条线路：请求头是 v3 `KugouLiveApi.mediaHeaders` 那一组（UA、`Origin`、`Referer` 房间页，见问题 2），格式 FLV/HLS，编码 `codec` 1 写 `avc`（归档规格读 FLV 头核实过），其他编码不写，线路编号 `sid<号>`（样本是 `sid5`、`sid40`，对应 `tx105`、`tx2` 两个腾讯云主机）；
  - **租期**：`txTime` 是十六进制的到期 Unix 秒（签发后约 12 小时），提前 5 分钟续期（v3 的 `mediaRefreshAt`），腾讯云只在建连时校验签名，所以 `cutsConnection` 为假；`LivePlayLeaseMetadata` 按地址给出同一份时间，续期时间已过时返回“现在”（v3）。
- **取流前的检查**：进房的 `KugouLiveRoomData` 带着各组线路，取画质、取地址都不再请求；不能播放时说明原因：未开播、没有直播场次、回答里没有流 `StreamUnavailable`，受限 `NeedsLogin`。平台明确未开播的房间不发请求直接报。恢复时重新进房（v3），同一个画质 id 必须还在，旧地址不复用。
- **弹幕**：v3 的酷狗是 `EmptyDanmaku`，传给弹幕连接的参数为空，所以没有弹幕参数类，`getDanmaku()` 仍是空的（同 E03.10 YouTube）。
- **链接**（`roomIdFromUrl`，不发请求）：照搬 v3 的 `KugouLiveLink.parseRoomId` 的链接部分——http(s)，主机 `fanxing.kugou.com`、`mfanxing.kugou.com`，默认端口，没有用户名和片段，路径只有一段房间号，或路径为空而 `roomId` 查询参数是房间号；解码失败的地址不算链接。搜索和详情还接受单独的房间号（v3）。酷狗没有短链。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/kugoulive/kugou_live_api.dart`，`S` = `core/site/kugoulive/kugou_live_site.dart`，`L` = `core/site/kugoulive/kugou_live_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 不存在的房间显示成一个叫“Kugou Live”、状态未知的房间；按任意不存在的号码搜索都会得到这张假卡片，开播状态报 `access` | A:378；S:164-172、S:211-216 | 不存在的房间 `kugouId` 是数字 0，`_string(0)` 是 `'0'`，不为空，判断“不存在”的条件永远不成立（样本 `S04-room-notfound`） | `NotFound`；搜索得到空列表 |
| 2 | 酷狗的媒体请求从来没带平台请求头：v3 为每个房间写了 `httpHeaders`（UA、`Origin`、`Referer`），播放和录制却都没用 | S:120、A:150-154；phr:143-149、phr:195-196；`modules/live_play/controllers/player_controller.dart:289-293` | `PlaybackHeaderResolver` 没有酷狗分支，走 `default` 得到空表；房间的 `httpHeaders` 只在 IPTV 分支里读 | 线路带 v3 写好的这组请求头（2026-09-28 实测：不带 UA、`libmpv` UA、这组请求头三种都能拉到 FLV）；房间不再写 `httpHeaders` |
| 3 | 房间信息说在播、取流回答却是 `status 0` 或没有可用地址时，整个房间打不开，录制详情也失败 | A:281-296、A:412-414、A:452；S:190-197 | “不能播”当成“详情失败”（`mediaUnavailable` 从 `room` 抛出） | 照常进房（直播中），取画质时报 `StreamUnavailable`；其他取流失败仍让进房失败（同 v3） |
| 4 | 列表卡片、刷新过的关注取画质报 `identity`；恢复也要先有进房的快照 | S:220-230、S:252-253 | 只认进房时放进 `data` 的 `KugouLiveRoom` | 先进房再取（2 个请求）；恢复直接重新进房 |
| 5 | 未开播的房间取画质得到空列表，播放器拿不到原因；受限、没有场次的房间报笼统的 `mediaUnavailable` | S:235、S:226-228 | 用空列表表示“不能播” | 未开播、没有场次 `StreamUnavailable`，受限 `NeedsLogin`；已知不能播的都不发请求 |
| 6 | 适配器用一个不设上限的 `_known` 表记下进程里见过的每个列表、搜索、详情房间，用来给详情补人数、头像等 | S:29、S:81-85、S:193-195；A:88-101 | 共享可变缓存；`nick == 'Kugou Live'` 这类哨兵值判断“缺失” | 去掉。详情只给房间信息里有的字段；进房时界面本来就用卡片的人数兜底（`live_play_controller.dart:701` 的 `withAudienceFallbackFrom`），关注刷新用 `mergeFrom` 保留旧值（`favorite_room_controller.dart:327`） |
| 7 | 分区房间只接受“已加载的分类”（没加载时是写死的 14 个）里的 id；关注的分区在平台新增分区后，或重启后没先打开分类页时，会被当成非法分区 | S:68-79 | 用可能过时的列表校验调用方 | 接受任何 1～8 位数字 id（平台自己会回答）；别的平台、别的分区类型仍是调用方错误 |
| 8 | 失败都是平台自己的 `KugouLiveException`：`access` 同时表示 401/403/451 和“状态未知”，3xx 算 `transport`；调用方传错页码、分区、超长关键词报 `schema`/`identity` | A:11-30、A:587-598、A:234-236、A:266；S:214-216 | 平台自定义异常 | 类型化错误（差异 7） |
| 9 | 平台层依赖全局 `HttpClient`，自己实现流式读取（4 MiB、严格 UTF-8）和请求作用域；进房的两个请求共用一个 20 秒期限 | A:117-215 | 结构问题 | 注入 `LiveHttp`，每个请求 20 秒；4 MiB 在解析前按字符数检查；非法 UTF-8 变成替换字符 |
| 10 | 平台层调用界面翻译（平台名、分区、两种公告、画质名），公告按当时的界面语言写进房间，随关注存下 | S:36、S:91-94、S:103、S:241-244 | `i18n` 写在适配器里 | 用 3.x `zh.json` 的中文（`KugouLiveApi.siteName`、`chatNotice`、`restrictedNotice`、`directoryScope`），界面翻译在 M13 |
| 11 | 路径或查询参数解不开的链接（`/%FF`）让 `parseRoomId` 抛 `FormatException`，搜索和链接导入直接失败；取流地址里有这种参数时整个回答失败 | L:25、L:27；A:467-468 | `pathSegments`、`queryParameters` 解码失败没有捕获 | 不算链接；这个地址不收 |
| 12 | 手机开播（列表 `liveStatus` 6）的房间在推荐列表里显示“未知”，进房后才是直播中 | A:494-499 | 只认 1 为直播（归档规格 §10） | 按 v3 保留（列表显示的状态不改）；升级候选 1 |
| 13 | 详情标题是 `publicMesg`（常是开播时间、招募之类的公告），列表标题是 `label`，进房后标题会变 | A:397、A:506 | 取标题的顺序（归档规格 §10） | 按 v3 保留；升级候选 2。归档规格说 `privateMesg` 与列表的 `label` 一致，样本里并不一致（`S04-room-live` 与 `S02-recommend-p1` 第 1 条） |
| 14 | 搜索结果的 `viewerNum` 一律是 0，未开播的主播也显示“0 在线” | A:509；样本 `S06-search` | 0 也当作人数 | 按 v3 保留；升级候选 3 |
| 15 | 3～11 位的数字关键词只按房间号查（如搜“520”只会得到 520 号房间） | S:164-172 | 搜索先认房间号 | 按 v3 保留（搜索页的能力表是“含未开播、可翻页”） |
| 16 | 取流地址必须带 `0-<房间号>-` 开头的 `token`，平台一改签名格式所有地址都会被丢掉 | A:471-472 | 校验签名内容 | 按 v3 保留（当前回答符合，2026-09-28 实测 `0-5192416-…`）；升级候选 7 |

## 样本与 v3 的冻结输出

归档没有酷狗的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了）。本模块用 `fixtures/kugoulive/legacy_expected.dart` 生成，做法同 E03.12 PandaTV：

- 把 v3 的 `KugouLiveApi`、`KugouLiveLink`、`KugouLiveSite`（`legacy/lib/core/site/kugoulive/` 三个文件）原样搬进一个 Dart 程序。v3 本来就把传输做成可注入的函数（`KugouLiveRequest`），所以只换了它：按主机、路径和查询参数（不比时钟值 `_` 和 `callback`）读样本；状态码不是 200 时正文为空（样本都是 200）；没有样本的请求抛 StateError，v3 的 `_scope` 会把它变成 `transport`，所以另外记下、在调用结束后重新抛出，缺样本会让生成失败；
- 搜索样本是用 `callback=pureLive1` 录的，服务器原样回显调用方给的函数名，所以脚本用 v3 自己的函数名替换回答开头的 `pureLive1(`；
- 网络路径上的 `_defaultRequest`、`_readBody` 没有搬；Dio 的 `CancelToken` 只留 v3 用到的成员，v3 的 `withRequestCancellation` 原样搬入；`KugouLiveSite` 保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`，构造函数改为必须注入 API；`i18n` 返回 3.x `zh.json` 的文字（带参数替换）；v3 的模型只搬用到的部分；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记下发出的请求（地址和请求头，`_` 和 `callback` 换成占位符）；
- 在仓库根目录运行：`dart run fixtures/kugoulive/legacy_expected.dart`，只用 Dart SDK。连续运行两次，输出逐字节相同。

12 个样本都有 `expected.json`：

- `S01-home`：`parseCategoriesHtml`、没有分区链接时的写死列表、`getCategores` 的几种参数（含第二次调用不再请求）、平台 id、名称、目录说明键；
- `S02-recommend-p1`、`-p2`：目录页、推荐（30 条）、推荐分区 8000（同一个接口）；第 1 页另有第 0 页、每页 0 条和列表卡片取画质；
- `S03-area-7024-p1`（配 `S01-home`）：分区目录页、`getCategoryRooms`，别的平台、别的分区类型、目录外的分区 id（加载分类前后）；
- `S04-room-live`（配 `S05-stream-live`）：刷新、开播状态、进房、录制、进房时的分组、画质、每档地址和租期、`getPlayUrls`、不存在的画质、恢复、刷新后的房间取画质、按链接进房、别的平台和非法号码、卡片取画质、按号码和两种链接搜索、31 个链接向量的 `parseRoomId`、`watchUrl`、`mediaHeaders`、9 个 `validateMediaUri` 向量、7 个租期向量；
- `S04-room-mobile`：刷新、开播状态、按号码搜索（进房要取流，这个房间没有录取流回答）；
- `S04-room-offline`：各深度的房间、开播状态、画质、恢复、按号码和链接搜索；
- `S04-room-notfound`：刷新、开播状态、进房、按号码和链接搜索；
- `S05-stream-live`、`S05-stream-offline`：`parseMediaJson` 本身（含请求的房间号不符）；
- `S06-search`：按页搜索（1、2、4、5 页，每页 30；每页 100、101、0；第 0 页；空白；101 个字的关键词）和 JSONP 的函数名检查；`S06-search-empty`：没有结果。

**样本的脱敏检查**：复制后按访客编号、设备编号、token、Cookie、出口 IP 查了一遍。回答没有 `Set-Cookie`，没有访客或设备编号，也没有 IP 地址（唯一的点分四段数字是请求头 UA 里的 `140.0.0.0`）；响应头里的 `x-ws-request-id`、`x-via` 是 CDN 节点和请求编号，不是用户标识，照归档保留；主播的公开资料照归档保留。取流地址的 `txSecret` 和 `token` 已由归档脱敏。

**一处修正**：归档把 `S05-stream-live` 的 FLV `token` 整体换成了同形的数字，连开头的房间号段也换了（`0-7379016-…`）。v3 只收以 `0-<房间号>-` 开头的 `token`，这样的样本在 v3 看来一个地址都没有。2026-09-28 实测一个在播房间（5192416）的回答，`token` 就是 `0-5192416-…`；房间号是公开的（请求地址里就有），所以本仓库的副本把 8 个 FLV 地址的这一段恢复成 `0-3197156-`，其余部分仍是合成值。RTMP 和 WebRTC 地址（v3 不读）没有改。

## 与 v3 输出的对照

对照方式：用同一份录下的回答跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序；地址、确认的画质、租期逐条比较；请求比较地址（逐字节）、请求头和次数。所有房间只有 `httpHeaders` 一个键不同（差异 2）。

| 样本 | 结果 |
|---|---|
| S01 首页 | 14 个分区（推荐、一起玩……网游竞技）的 id、名称、顺序和 `LiveArea` 各字段一致；分类只请求一次、之后不再请求一致；第 2 页、每页 0 条不请求一致；没有分区链接时的写死列表一致 |
| S02 推荐（51 条、50 条） | 房间、顺序、各字段、是否还有下一页一致；两条手机开播的房间（6）仍是未知；推荐的 30 条、推荐分区的全部房间一致；请求地址逐字节一致 |
| S03 舞蹈分区（5 条） | `star` 包装、`getViewerNum`、末页一致；请求带 `cid=7024` 一致。v3 对别的平台和别的类型报 `identity`，现在是 `ArgumentError`，都不发请求；目录外的分区 id v3 报 `identity`，现在照常请求（问题 7） |
| S04 在播（+S05） | 刷新、开播状态 1 个请求，进房、录制 2 个请求，地址和请求头逐项相同；房间逐键一致（标题 `publicMesg`、没有人数、粉丝 10984）；一档 `FLV 码率档 4`（`flv:4:1:2`，排序 42），两条线路的地址、确认的画质、失效和续期时间一致；恢复 2 个请求、地址一致；按号码、带空格的号码和两种链接搜索各 1 个请求、结果一致；链接、`watchUrl`、媒体请求头（名称改小写）、地址校验、租期向量全部一致 |
| S04 手机开播 | 刷新是直播中、开播状态 true、搜索结果一致 |
| S04 未开播 | 各深度 1 个请求，房间逐键一致；v3 取画质得到空列表，现在 `StreamUnavailable`（不发请求） |
| S04 不存在 | v3 各深度返回名为“Kugou Live”的未知房间，开播状态报 `access`，搜索得到这张卡片；现在都是 `NotFound`，搜索为空（问题 1） |
| S05 取流 | 分组一致；已下播的回答 v3 报 `mediaUnavailable`，现在 `StreamUnavailable`；别的房间的回答 v3 报 `mediaUnavailable`，现在 `ApiChanged` |
| S06 搜索（98 位主播） | 全部房间逐键一致（6 位在播、92 位未开播，头像是 `logo` 的 45×45 小图，在线都是 0）；1、2、4、5 页和每页 100 条的切分一致，每页 1 个请求且地址一致；每页 101 条、0 条、第 0 页、空白不请求一致；101 个字的关键词 v3 报 `identity`，现在是 `ArgumentError`，都不发请求；函数名不符报错一致 |
| S06 没有结果 | 空列表、1 个请求一致 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 不存在的房间是 `NotFound`，按它的号码或链接搜索没有结果 | 问题 1。v3 本意就是“不存在则没有结果”，只是判断条件写错 |
| 2 | 房间不写 `httpHeaders`；线路自带请求头、格式、编码、线路编号和有效期 | 问题 2。请求头就是 v3 自己写好、却从没发出的那一组；三种请求头实测都能拉流，用户看到的内容不变。3.x 存下的旧值照读、`mergeFrom` 照留 |
| 3 | 在播却取不到流的房间照常进入，取流时说明原因 | 问题 3。状态和公告不变 |
| 4 | 没有 `data` 的房间取流前先进房；恢复直接重新进房 | 问题 4。正常进房流程不受影响，请求数与 v3 进房相同 |
| 5 | 已知不能播的房间取画质不发请求，未开播和没有场次 `StreamUnavailable`，受限 `NeedsLogin` | 问题 5 |
| 6 | 显示为未知的房间查开播状态：受限 `NeedsLogin`，没有场次 `ApiChanged`（v3 都是 `access`） | 问题 8。仍然不把它当成“未开播” |
| 7 | 出错抛类型化错误：401/403 `RiskControl`，451 `RegionBlocked`，404/410 `NotFound`，429 `RateLimited`，400/422、看不懂的回答、`code` 不为 0、没有 `normalRoomInfo`、别的房间的取流回答 `ApiChanged`，5xx、其他状态（含跳转）和传输失败 `NetworkFailure`；取消原样抛出；调用方的参数错误 `ArgumentError`/`RangeError`，不是房间号的房间 `NotFound`，同 v3 都不发请求 | 问题 8。界面看到的仍是加载失败 |
| 8 | 不再有 `_known` 缓存：详情只给房间信息里有的字段 | 问题 6。进房和关注刷新时界面本来就保留卡片或旧的人数 |
| 9 | 分区 id 只检查格式，不再对照已加载的分类 | 问题 7。只在 v3 报错的地方有区别 |
| 10 | 解码失败的链接和地址不算数，不再让搜索或取流整体失败 | 问题 11 |
| 11 | 进房不再有 20 秒的总期限，由每个请求各自的 20 秒超时代替；回答在解析前按字符数查 4 MiB；非法 UTF-8 变成替换字符 | 问题 9；同 E03.7 等模块 |
| 12 | 分区名的实体解码用通用的 `decodeHtmlEntities` | v3 只替换 5 种实体（且先换 `&amp;`，会二次解码）；录到的首页两者结果相同 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **手机开播（6）的列表卡片仍显示未知**（问题 12）。归档 v4 把正数都算直播（规格 §2.4），会改变列表里显示的状态，列为升级候选 1。
- **详情标题仍是 `publicMesg`，公告是聊天说明**（问题 13）。归档 v4 标题用 `privateMesg`、`publicMesg` 放公告，会改变标题和公告，列为升级候选 2。
- **“推荐”（8000）是一个分区，分类只有“酷狗直播”一个**。归档 v4 的分类叫“分类”（id `fanxing`），去掉了推荐分区，会改变分区页和已关注的分区。
- **首页没有分区链接时用 v3 写死的 14 个分区**。归档 v4 报 `ApiChanged`。
- **画质按“协议:码率档:编码:布局”分组**，名称 `FLV 码率档 4`。归档 v4 固定一档“原画”、每个 `sid` 一条线路，会改变画质菜单和存下的画质 id；上游笔记指出它在一条线路有多个 profile 时会把不同编码混在一档里，v3 的分组没有这个问题。
- **取流地址照 v3 校验主机、路径、签名参数和 `token` 前缀**（问题 16）。归档 v4 不校验签名内容。
- **没有场次、也不是 `liveType` -1 的房间显示未知**。归档 v4 报 `ApiChanged`，会让关注刷新整个失败（上游笔记 `sub_A.md` 也指出这是风险）。
- **搜索照 v3**：数字先按房间号查（问题 15）、一次 200 位主播本地分页、每页 1～100 条、在线 0 照样显示（问题 14）。
- **链接照 v3**：只认 `fanxing.kugou.com`、`mfanxing.kugou.com`，`roomId` 查询参数只在路径为空时认。归档 v4 另收 `fanxing2.kugou.com` 和任何路径上的 `roomId`，没有样本证明这些分享地址存在，列为升级候选 4。
- **请求头照 v3**：首页和取流接口也用 JSON 的 `Accept` 和站点根作 `Referer`（归档 v4 首页用 HTML 的 `Accept`，取流用房间页 `Referer`）。
- **提前 5 分钟续期**（v3）。归档 v4 提前 10 分钟。
- **进房时就取流**（2 个请求），刷新只读房间信息。归档 v4 每次取流都重新读房间信息。
- 显示名仍是“酷狗直播”，目录说明键仍是 `kugoulive_directory_scope`，公告是 3.x 的中文原文，头像缺时用封面。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复；它把缺的在线、热度、粉丝写空串，这里同样写空串（`mergeFrom` 因此保留存下的值）。

## 后续升级候选（2026-09-28 用户已采用，编号 29-1～29-8，落地见文末“升级落地（T02.U）”）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 列表里 `liveStatus` 为 6（手机、游戏开播）及其他正数显示为直播中 | 显示未知 | 问题 12；归档规格 §2.4、§10；样本 `S02-recommend-p2` 两条、`S04-room-mobile` |
| 2 | 详情标题用 `privateMesg`（或与列表一致的 `label`），`publicMesg` 作公告 | 标题 `publicMesg`，公告是聊天说明 | 问题 13；归档规格 §4 |
| 3 | 搜索结果只在直播中且人数大于 0 时显示在线 | 一律“0 在线” | 问题 14；归档 v4 |
| 4 | 识别更多分享地址（`fanxing2.kugou.com`，任何路径上的 `roomId`） | 只认 v3 的两种写法 | 归档规格 §1；需要先录到真实的分享链接 |
| 5 | 酷狗弹幕（繁星的私有 WebSocket 协议） | 没有弹幕 | 归档规格 §7、§12 第 4 条：匿名接入方式待确认，没有样本；由 D01 决定 |
| 6 | 公告改成用户能看懂的说明（现在是“远端聊天尚待接入；viewerNum/getViewerNum 按……”这类开发说明） | 3.x 原文 | M13 翻译时一并考虑 |
| 7 | 不再校验 `token` 的格式 | 必须以 `0-<房间号>-` 开头 | 问题 16；归档 v4 |
| 8 | 核实 `codec` 2 是否为 HEVC 并标出编码 | 只有 1 标为 `avc` | 归档规格 §12 第 2 条 |

## 回归条目的覆盖

归档规格没有 REG-KUGOULIVE 条目。§10“踩过的坑”两条都属于平台层，都有测试：

- 手机开播的房间显示状态未知（列表 `liveStatus` 6）：按 v3 保留，测试断言样本 `S02-recommend-p2` 的两条仍是未知、`S04-room-mobile` 的房间信息是直播中；改法是升级候选 1。
- 房间标题是开播时间表（`publicMesg`）：按 v3 保留，测试断言详情标题是 `publicMesg`，并记下归档规格“`privateMesg` 与 `label` 一致”的说法在样本里不成立；改法是升级候选 2。

规格 §9 的错误表（401/403、429、`code` 不为 0、不存在、首页没有分区、不在播、受限）也都有测试；其中“首页没有分区”按 v3 退回写死的列表，不报错。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕：`getDanmaku()`（v3 是 `EmptyDanmaku`） | D01（升级候选 5）；同 E01.1，D01 用一张“平台 → 弹幕连接”的表 |
| 目录说明（`kugoulive_directory_scope`）、两种公告、画质名（`kugoulive_quality_rate`）、平台名（`site_kugoulive`）的繁体和英文 | M13 多语言。本模块给出 3.x 的中文（`KugouLiveApi.directoryScope`、`chatNotice`、`restrictedNotice`、`siteName`） |
| 目录说明常驻（`LiveDirectoryNotice`） | M13 热门页、分区页 |
| 搜索能力表：含未开播、可翻页、没有网页搜索（3.x `modules/search/search_capability.dart:96-100`） | M13 搜索页 |
| 外部打开 `https://fanxing.kugou.com/<号>`（3.x `modules/live_play/services/room_external_opener.dart:133-134`） | M13；地址由 `KugouLiveApi.roomUrl` 和房间的 `link` 提供 |
| 本地互动包（3.x `local_interaction_controller.dart:481-488`） | M13 |
| 平台注册和图标（3.x `core/sites.dart:198`、`256`、`385-390`） | I01.1 应用骨架；平台 id 已在 M3 的 `SiteIds.kugouLive` |
| 平台列表升级时追加酷狗（`favorite_room_controller.dart:91`，`siteCatalogMigration` 第 35 版；3.x `test/kugou_live_catalog_migration_test.dart`） | J02.1 |
| 播放和录制按线路的请求头、有效期打开（3.x 的 `PlaybackHeaderResolver` 没有酷狗分支） | G、H01.1 |
| 录制平台契约（3.x `test/recording_platform_contract_test.dart:39`） | H01.1 |
| 人数能力（列表在线、热度，没有累计） | 已在 E05.1 的 `audience.dart` |
| 3.x 的链接工具和网页搜索解析里的酷狗分支（`live_url_tool.dart:123`、`251-252`，`web_search_room_parser.dart:118-121`） | 已由本模块的 `LiveSiteLinks` 加 M3 的 `LinkParser` 代替 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。JSON 读取用 `json.dart`（`jsonInt`、`jsonString`、`decodeHtmlEntities`），主机判断用 M3 的 `RoomPaths.hostIs`，链接用 `LiveSiteLinks`、`LinkParser`。

## 测试

71 个用例，`live_core` 共 2483 个，全部通过：

- `kugoulive_api_test.dart`（37 个）：逐个样本对照 v3 的输出（首页分区和分类、两页推荐、分区、四种房间信息、取流分组、画质和线路、搜索），有意的差异逐条断言（`httpHeaders`、不存在的房间、取流回答的错误类型）；v3 测试里解析部分的移植（卡片的三种人数、首页排除个人页、JSONP 函数名、地址绑定房间和租期）；卡片的各种兜底和状态值、图片规则、重复和坏行、答案的形状错误；受限、未开播、没有场次的状态和取流原因；多档、多线路、HLS、别的房间的地址；地址校验和租期向量；请求地址与 v3 逐字节相同；链接规则（31 个 v3 向量）；状态码映射；§10 两条。
- `kugoulive_site_test.dart`（34 个），用样本回放加合成回答：
  - 平台名、目录说明、能力、没有弹幕和短链；
  - 分类：请求、结果、只读一次、读失败下次再读、不请求的参数；
  - 目录：推荐两页、推荐分区、舞蹈分区的请求（地址、请求头、不跟随跳转）和结果与 v3 一致；第 0 页、每页 0 条不请求；别的平台、别的类型、非法 id、超出页码的调用方错误；目录外的分区照常请求；
  - 搜索：按页切分和每页 1 个请求与 v3 一致；不请求的情况；超长关键词；没有结果；按号码和链接搜索、第 2 页、不存在的房间、其他错误不当成“没有结果”；取消（请求前、请求中）；
  - 房间：进房、录制 2 个请求，刷新、开播状态 1 个请求，与 v3 相同；链接作房间号；未开播、手机开播、不存在、非法号码；受限、没有场次（合成）；取不到流照常进房；取流失败让进房失败；刷新合并进 3.x 存下的关注；
  - 取流：进房得到的房间不再请求，画质、地址、`resolvePlayUrlsRaw` 与 v3 一致，线路属性；卡片、刷新后的房间、别的房间的数据先进房；未开播的卡片不请求；别的平台；恢复 2 个请求、地址一致；恢复时下播或画质没了；租期查询与 v3 一致；
  - 错误映射（传输失败、取消、各状态码、`code` 不为 0）；
  - 链接（经 `LinkParser`）：分享文本里的房间页、`mfanxing` 的 `roomId`，其他页面和主机不识别，不发请求。

## 升级落地（T02.U）

- 日期：2026-09-29（E02.10）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 8 行（29-1～29-8）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。“落地方式”只有 29-7、29-8（开发预填）写了，其余按上面“后续升级候选”的原文做。29-5（弹幕）属于 D01，本次不做。
- 改了的文件：本平台的 `kugoulive_api.dart`（解析）、`kugoulive_site.dart`（请求编排）、两份测试和两个新样本。没有改通用文件，没有加通用能力，没有新依赖。
- 实测：2026-09-28 20:17～20:48 UTC，直连、匿名、适配器的请求头，只读：推荐列表 1～4 页（约 200 个房间）的房间信息和取流回答，其中带 `limitType` 的 5 个房间另查了网站的 `RoomService.getInfo` 并读了 FLV 开头（看视频编码）；两个关键词搜索里在播的主播的房间信息；房间页 `https://fanxing.kugou.com/3197156` 和它引用的脚本（`roomFunction`、`user_room_limit`、`fx.jsPlayer`、房间页内联的取流格式化代码），`fanxing2.kugou.com/3197156` 和手机分享页。下面的结论都来自这些回答、网站自己的代码和已有样本。

### 查明的根因：`limitType` 是公聊限制，不是观看限制

v3（问题表里没有列）把房间信息 `normalRoomInfo.limitType` 大于 0 当作“受访问范围限制”：状态显示“未知”，公告写“该酷狗直播受访问范围限制”，取流报 `NeedsLogin`，开播状态查询也报错。实测：

- 网站的 `RoomService.getInfo` 把同一对值叫 `publicTalkLimit {limitType, limitValue}`，房间页脚本 `sendChatMessage.chatSet` 的含义是：0 谁都能公聊，1 “仅允许本直播间的守护者和管理员公聊”，2 “仅允许 <财富等级 limitValue> 及以上用户公聊”。查了 5 个带 `limitType` 的在播房间（1 有 3 个、2 有 2 个；两次各扫 100 个房间，分别有 4 个、3 个带 `limitType`），两边的值全部相同；
- 这 5 个房间匿名取流都是 `status 1`、两条线路，FLV 开头是 H.264（codec id 7），能正常拉流。推荐列表里也把它们列为直播中。

所以 `limitType` 只管谁能发言，不影响观看。v3 让这些房间显示“未知”、不能播放，是误判。现在不再读 `limitType`（`KugouLiveState` 去掉 `restricted`）：这些房间照常是直播中、照常播放，受限类型按取流回答判断（见“按统一原则补的”）。新样本 S04-room-chatlimit（`limitType 2`、`limitValue 3`）和 S05-stream-chatlimit 固定了这一点。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 29-1 手机、游戏开播显示为直播中 | 卡片的状态（`liveStatus`，没有时 `status`，再没有 `liveType`）任何正数都是直播中（`KugouLiveApi.cardState`）；0、-1 仍是未开播，其他（空、非数字、其他负数）仍是未知。依据：手机、游戏开播的列表值是 6（样本 S02-recommend-p2 两条，实测推荐第 1 页 3 条），它们的房间信息是 `liveType 2` 带场次（S04-room-mobile），取流正常 | 推荐页里手机、游戏开播的房间显示“直播中”，关注分组也在直播中（v3 显示“未知”） | 完成（T02.U） |
| 29-2 详情标题与列表一致，原标题放进公告 | 房间信息没有直播标题：v3 当标题的 `publicMesg` 和兜底的 `privateMesg` 分别是公聊公告和私聊公告（房间页脚本渲染成 `declaration`“公聊公告”、`declarationPrivate`“私聊公告”；实测 25 个在播房间，`privateMesg` 没有一个等于列表的 `label`，归档规格的说法不成立）。列表的 `label` 只在列表里有，房间信息、搜索、取流都没有。所以详情（关注刷新、进房、录制、按号码或链接搜索）的标题留空：`mergeFrom` 遇到空标题保留存下的，进房和关注刷新不再把列表或关注里的标题换掉。公告改为：公聊公告、私聊公告（相同或为空的只写一次）、再加 29-6 的说明，各占一行 | 从推荐页进房后，标题仍是列表上的那句（v3 换成主播的公告，如“通宵主播！！！！王者女侠……”）；房间公告里能看到主播的公聊公告和私聊公告。没有列表标题的房间（用链接打开、按号码搜到）标题为空，界面显示昵称（M13） | 平台层完成，余下 J02.1/M13 |
| 29-3 搜索结果只在直播中且人数大于 0 时显示在线 | 搜索卡片（`card(search: true)`）的 `viewerNum` 只在直播中且大于 0 时算在线人数，否则当作没有；搜索行没有热度，所以人数和口径是空、“未知”。推荐、分区卡片不变（列表里在播的 0 是真实值） | 搜索结果不再对每个主播都显示“0 在线”（样本 S06 的 98 个，在播的 6 个也是 0） | 完成（T02.U） |
| 29-4 识别更多分享地址 | 录到的真实分享地址：房间页对手机浏览器跳转到 `http://mfanxing.kugou.com/staticPub/rmobile/sharePage/normalRoom/views/index.html?roomId=<房间号>`（手机分享页，2026-09-28 从 `fanxing.kugou.com/3197156` 的页面里录到；这个页面在电脑上又按 `roomId` 跳回 `fanxing.kugou.com/<房间号>`）。所以 `roomId` 查询参数在任何路径上都认（v3 只认路径为空的），路径只有一段房间号时仍以路径为准（v3）。网站其他带 `roomId` 的房间页（`fanxing.kugou.com/ether/party_pc_diversion.html?roomId=`）同样认。`fanxing2.kugou.com` 没有加，见“受阻和存疑” | 在手机上复制的酷狗直播间地址（分享页）能直接打开、导入 | 完成（T02.U，任何路径上的 `roomId`）；`fanxing2.kugou.com` 受阻 |
| 29-5 酷狗弹幕 | 本次不做（D01） | 无 | 待做（不变） |
| 29-6 公告改成用户看得懂的说明 | 文字键不变，M13 按平台翻译：<br>- 聊天说明 `chatNotice`（`kugoulive_chat_notice`）：v3“酷狗远端聊天尚待接入；viewerNum/getViewerNum 按当前观看人数展示，hot 按平台热度展示，fansCount 单独作为粉丝数。”→“这里暂时看不到酷狗直播间的聊天。人数是正在观看的人数，没有时显示热度；粉丝数单独显示。”<br>- `restrictedNotice`（`kugoulive_restricted_notice`）：v3“该酷狗直播受访问范围限制，界面保持未知状态，不将其显示成未开播。”（配的是被误判的公聊限制）→“这个直播间要登录酷狗才能观看，本应用暂时无法播放。”，只在取流回答要求登录时放在公告第一行<br>- 目录说明 `directoryScope`（`kugoulive_directory_scope`）：v3“官网推荐与分类目录采用原生分页；原生搜索同时返回开播和未开播主播，精确房间号及 fanxing.kugou.com 官方链接可直接解析房间状态。”→“推荐和分区是酷狗直播官网的列表，可以一直往下翻。搜索会列出相关的主播，未开播的也在内；也可以输入房间号，或粘贴酷狗直播的直播间链接（网页或手机分享页）直接打开。” | 公告和目录说明是看得懂的话（M13 显示和翻译） | 平台层完成，余下 M13 |
| 29-7 不再检查 `token` 的格式 | `mediaUrl` 不再要求 `token` 以 `0-<房间号>-` 开头（也不要求有 `token`）；主机、端口、`/live/` 路径、扩展名、`txSecret`、十六进制的 `txTime` 照 v3 检查。回答属于哪个房间仍由回答的 `roomId` 保证（不符是 `ApiChanged`）。实测 153 个房间的 `token` 都是 `0-<房间号>-…`，所以现在看不出变化 | 看不出变化；平台以后改签名格式时不会一下子所有房间都放不了 | 完成（T02.U） |
| 29-8 核实另一种编码是否为 HEVC 并标出 | 核实：网站房间页的取流格式化代码写着 `v = MediaSource.isTypeSupported('video/mp4; codecs="hvc1.1.6.L93.B0"'), y = 2, h = 1`，浏览器不支持 hvc1 时就不选 `codec` 为 2 的档，退回别的编码；网站的 FLV 播放器能解 HEVC（codec id 12）。所以 `codec` 2 是 HEVC（`KugouLiveApi.hevcCodec`），线路标 `hevc`（`codecName`；1 仍标 `avc`，其他不标），档位有 `isHevc`。画质名称和 id 照 v3（同一码率档的 H.264 和 HEVC 名字相同，同 v3）；按统一原则的“优先 H.264”（见“设置项”）排顺序。实测 153 个房间只有 `codec` 1，没有录到 HEVC 的流 | 平时看不出变化；遇到 HEVC 档时，默认仍播 H.264，线路标明 HEVC（G 据此处理硬解） | 平台层完成，余下 G/M9/M13 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 三处都有，只在直播中填，UTC：<br>- 房间信息（关注刷新、进房、录制、按号码或链接搜索）：`liveSessionId` 的格式是“开播时刻的十六进制 Unix 秒 + `h` + 主播 `kugouId` 的十六进制”（`6ab93a1bh56ef48b4` = 2026-09-27T15:45:31Z、kugouId 1458522292；样本和实测约 200 个房间里有场次的都是这个格式，`h` 后面是 7～8 位）。取前 8 位（`KugouLiveApi.sessionStart`）；`h` 后面不是这个主播的 `kugouId`、不在 2000～2099 年、晚于回答自己的时间（`times`，允许 5 分钟）都不填。依据：搜索回答的 `lastLiveTime`（网站显示成“4小时55分钟前”）与它相差不超过 2 秒（实测 5 个在播房间）。<br>- 推荐列表卡片：列表回答的 `times`（毫秒）减去卡片的 `livetime`（已播秒数），`KugouLiveApi.listStart`。实测 193 个房间里 176 个比场次开始晚 9～26 秒，另外 17 个晚几分钟到几天：`livetime` 从最近一次推流（断线重连）算起，场次不变。进房或关注刷新后以房间信息的为准（`mergeFrom` 用新值）。<br>- 搜索卡片：在播的行的 `lastLiveTime`（Unix 秒）。<br>分区列表（`list_v4`）的卡片没有这类字段，不填 |
| 受限类型 | 房间信息看不出观看限制（`limitType` 是公聊限制，见上），所以卡片和关注刷新留空（null）。进房、录制详情按取流回答填（`KugouLiveApi.withRestriction`）：有能播的地址 → `none`；回答 `code` 为 -1 → `needsLogin`（网站房间页的写法：`-1 === responseCode` 时提示“需要登录才能观看直播”），公告第一行是 `restrictedNotice`，取流报 `NeedsLogin`；说在播却没有流（`status` 不是 1、没有能用的地址）→ `unplayable`，取流报 `StreamUnavailable`。未开播、没有场次的房间不请求取流，不填。v3 这三种情况分别是：正常、`ApiChanged`（进房失败）、进房失败 |
| 受限的直播改为直播中 | v3 唯一的“受限”（`limitType`）是误判，见上；现在这些房间直播中、能播放。要求登录、没有流的直播仍是直播中（`isLiveNow` 为真，分组在直播中），只标受限类型 |
| 回放、“不可播放” | 酷狗没有回放。在播却拿不到流的标 `unplayable`（见上） |
| 占位信息 | 去掉 v3 的占位 `Kugou Live`：卡片和房间信息没有昵称时昵称留空（界面显示平台名，`displayNick`），没有任何标题时标题留空。卡片在没有 `label` 等时用昵称作标题是 v3 的卡片样式（搜索行都没有 `label`，网站搜索也只显示昵称），用的是真实数据，保留。头像缺时用封面（真实图片）保留 |
| 画质命名 | 表里没有改名条目，保留 v3 的名字（`FLV 码率档 4`）和 id（`flv:4:1:2`） |
| 默认编码 | 加“优先 H.264”（见“设置项”），29-8 |
| 房间身份 | 不变：3～11 位数字房间号，不涉及大小写 |
| 按主播关注 | 不涉及：房间号就是主播的直播间 |
| 容错 | E02.10 已是：一行坏数据只跳过这一行，一个坏地址只让它自己不可用、一档没有地址才去掉这一档。29-7 去掉了一项可能让所有地址失效的校验 |
| 翻页 | 关键词搜索：v3 每翻一页都重新请求同一份 200 个主播的回答再在本地切。现在第 1 页（下拉刷新）总是请求，第 2 页起 30 秒内（`KugouLiveSite.snapshotLifetime`）用同一个关键词第 1 页的回答切，超过 30 秒或时钟倒退再请求；失败不留快照；最多留 8 个关键词。推荐和分区是平台原生的 `page` 分页（样本两页没有重复），跨页去重留给 M13 的列表（按房间身份），同 PandaTV |
| 弹幕 | 29-5（D01） |
| 说明文字 | 29-6 |

### 请求数

| 场景 | E02.10 | 现在 | 原因 |
|---|---|---|---|
| 分类 | 首次 1，之后 0 | 不变 | — |
| 推荐、分区的一页 | 1 | 1 | — |
| 关键词搜索第 1 页 | 1 | 1 | — |
| 关键词搜索第 2 页起 | 1 | 30 秒内 0，否则 1 | 统一原则“翻页” |
| 房间号或链接搜索（第 1 页） | 1 | 1 | — |
| 关注刷新、开播状态 | 1 | 1 | — |
| 进房、录制详情 | 直播中 2，其他 1 | 不变（公聊限制的房间由 1 变 2，因为它们是直播中） | `limitType` 的根因 |
| 取流：带进房数据的房间 | 0 | 0 | — |
| 取流：没有进房数据的卡片 | 2；明确未开播 0 | 不变 | — |
| 恢复取流 | 2 | 2 | — |

关注刷新和列表没有多请求。

### 画质 id 对照（给 J02.1）

不变：画质 id 仍是 v3 的“协议:码率档:编码:布局”（`flv:4:1:2`），名称仍是 `<FLV|HLS> 码率档 <n>`，不需要迁移，本平台没有对照表。29-8 只给线路加了 `hevc` 标记，“优先 H.264”只改顺序。

### 设置项

| 名字 | 默认 | 含义 | 接口 | 留给 |
|---|---|---|---|---|
| `preferH264`（“优先 H.264”，统一原则的全局设置，与 8-8、14-5、22-3、33-2 共用） | 开 | 开：画质列表里 H.264 的档在前、HEVC（`codec` 2）的档在后，各自按 v3 的顺序（码率档从高到低），默认播 H.264；关：v3 的顺序（码率档从高到低，同档按回答的顺序） | `KugouLiveSite(http, preferH264: () => 设置值)`，每次取画质时读，改了不用重建适配器 | J02.1 存储；M13 设置界面；G 评估默认值 |

### 身份迁移规则（给 J02.1）

- 房间身份不变（数字房间号），`link` 不变（`https://fanxing.kugou.com/<房间号>`），画质 id 不变，没有要迁移的身份。
- 3.x 存下的酷狗关注，`title` 是 v3 取的 `publicMesg`（公聊公告；为空时是私聊公告、昵称或占位 `Kugou Live`），关注刷新会一直写进去。现在详情不给标题，刷新不再覆盖它（29-2），所以建议 J02.1 迁移时清空酷狗关注的 `title`（公告在下次刷新时写进 `notice`），昵称为 `Kugou Live` 的也清空（占位）；清空后界面显示昵称、平台名（M13）。
- 3.x 存下的 `notice` 是旧的开发说明，刷新时由新文字覆盖，不用迁移。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出，原因写条目编号；3.x 从来没写过的 `startedAt`、`restriction` 由 `_expectParity` 的 `added` 逐个断言；`expected.json` 没有改：

- 所有房间：`notice`（29-6；房间信息的另有 29-2 的两条公告），以及 E02.10 起就有的 `httpHeaders`。
- 房间信息给的房间（S04 在播、手机开播、未开播的刷新、进房、录制、按号码和链接搜索）：`title` 为空（29-2）；在播的加 `startedAt`；进房、录制加 `restriction: none`。
- 推荐列表：两条手机开播（S02-recommend-p2 的 50595748、50236352）`liveStatus`、`status` 变为直播中（29-1）；带 `livetime` 的卡片加 `startedAt`（第 1 页 51 条里 50 条，第 2 页 50 条）。
- 分区列表（S03）：只有 `notice`。
- 搜索（S06）：`watching`、`onlineViewers`、`audienceMetricType`（29-3，v3 是“0 在线”）；6 个在播的加 `startedAt`。第 2、4、5 页 30 秒内不再请求（v3 每页 1 个），切出的房间与 v3 相同。
- 链接：v3 的向量 `https://mfanxing.kugou.com/share?roomId=3197156` 现在是 3197156（29-4），其余 30 个不变。
- 取流地址：v3 的向量“another room”（S05 的地址配另一个房间号，`token` 对不上）现在接受（29-7），其余 8 个不变。
- 画质、线路、租期、请求地址和请求头：与 v3 相同。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 29-5 酷狗弹幕：没有查协议，没有弹幕参数类，`getDanmaku()` 仍是空的弹幕源。平台层现在能给的：房间号、主播 `kugouId`（卡片和房间的 `userId` 在 `userId` 为空时就是它）。房间页的配置里有聊天服务的主机（`chatfm1.fanxing.kugou.com` 等），归档规格 §7 说是私有 WebSocket 协议、匿名接入方式待确认。查明后在平台层加参数类。另：`limitType`/`limitValue` 是公聊发言限制，D01 若支持发弹幕可以用它提示 |
| G | 线路带 `codec`（`avc`/`hevc`）、`lineId`、租期；HEVC 档的硬解（高通真机）和“优先 H.264”的默认值评估；“优先 H.264”开时默认选画质列表第一档 |
| J02.1 | “优先 H.264”设置的存储（与其他平台共用）；上面的关注标题清理；按 E05.2 存 `startedAt`、`restriction` |
| M13 | 标题为空时显示昵称（29-2：从链接打开、按号码搜到的房间，以及 J02.1 清空标题后的关注）；三段文字（29-6）的多语言，英文建议：“Kugou Live chat is not shown here yet. The number is viewers now, or popularity when there is none; followers are shown apart.”“This room needs a Kugou login to watch; this app cannot play it yet.”“Recommendations and areas are the Kugou Live website's lists and keep loading as you scroll. Search lists matching streamers, offline ones included; you can also enter a room number or paste a Kugou Live room link (web or phone share page).” 卡片按 `restriction` 标出“需要登录”“不可播放”；开播时间只在直播中显示；“优先 H.264”设置界面；推荐、分区跨页去重 |

### 受阻和存疑

- **29-4 的 `fanxing2.kugou.com`：受阻**。没有录到用这个主机的分享链接：房间页、手机分享页和它们的脚本里都没有出现，网站的分享函数（`fxShare`）用的是调用方给的当前地址。实测 `https://fanxing2.kugou.com/3197156` 能打开同一个房间页（200，标题是这个房间的主播），但只凭能打开不算分享地址。以后录到真实链接，把它加进 `KugouLiveApi` 的 `_hosts` 即可。
- **29-8 的核实方式**：依据是网站自己的代码（取流格式化代码把 `codec` 2 与 `hvc1` 的支持绑在一起，FLV 播放器能解 codec id 12），没有录到 `codec` 2 的流：推荐列表 3 页 153 个房间的取流回答全是 `codec` 1，所以没能读 HEVC 流的 FLV 开头核对。
- **要求登录（`code` -1）**：依据是网站房间页的代码，没有找到这样的房间，测试用合成回答。
- **推荐卡片的开播时间**：`livetime` 从最近一次推流算起，断线重连过的房间（实测约一成）比房间信息的场次开始晚，进房或刷新后改为场次开始。两者都是平台给的，没有更好的统一来源。
- **关注里的标题**：29-2 之后，适配器不再给详情标题，关注保留关注时的标题（从推荐页关注的是列表的 `label`，其中有些是平台的推荐语，如“距离你附近1公里”“新人主播”），刷新不会更新它。这是“与列表一致”的代价；如果以后要改，M13 可以在关注页改为显示昵称。

### 新样本

两个，2026-09-28 20:47 UTC 直连、匿名、用适配器的请求头录制（`meta.json` 的 `tool` 写明是临时脚本，按 fixtures/README.md 的格式）：

- `S04-room-chatlimit`：房间 5171815 的 `getEnterRoomInfo`，在播，`limitType 2`、`limitValue 3`（同一时刻网站 `RoomService.getInfo` 的 `publicTalkLimit` 也是 2、3）。没有需要脱敏的字段（主播公开资料照录，没有访客或设备编号、Cookie、令牌）。
- `S05-stream-chatlimit`：同一房间的取流回答，两条线路（`sid` 5、40）、一档 `flv:5:1:2`。每个地址的 `txSecret` 换成同长度的随机十六进制，`token` 在 `0-5171815-` 之后的部分换成同形的随机值（相同的原值换成相同的值，所以回答里重复的地址仍然相同），共 28 处，逐条记在 `meta.json` 的 `scrubbed`；`txTime` 保留真实值（租期用）。
- 两个样本的响应头只有 CDN 节点和请求编号（`x-via`、`x-ws-request-id`），没有回显调用方地址；回答里唯一的点分四段数字是请求头 UA 里的 `140.0.0.0`。门禁的 `fixture privacy` 通过。
- 没有 `expected.json`（v3 的冻结输出只针对 E02.10 的 12 个样本）；测试直接断言新做法。

### 测试

本平台 84 个用例（E02.10 是 71 个，新增 13 个，另改写了样本对照、房间、取流、搜索、链接的用例），`live_core` 共 3411 个，全部通过；把时钟往后推 30 天、1 年、5 年再跑本平台的测试也全部通过（用到的时间都来自样本或固定的 `now`）：

- `kugoulive_api_test.dart`（47 个）：
  - 样本对照：上面列出的 `changed:` 和 `added`，改了的键逐个断言新值（手机开播是直播中、详情标题为空、公告是两条公告加说明、搜索没有“0 在线”、开播时间按样本字段另行算出）；
  - 29-1：卡片状态表（正数、0、-1、其他）、样本里的两条手机开播、分组；
  - 29-2：从推荐卡片进房后标题不变、公告第一行是 v3 的标题；两条公告相同或为空时的写法；
  - 29-3：搜索在播且大于 0 才有人数；
  - 29-4：手机分享页、`ether` 房间页、路径优先、`fanxing2` 不认；v3 的 31 个向量；
  - 29-6：三段文字没有字段名和开发说明；
  - 29-7：v3 的地址向量（“another room”改为接受）、`token` 缺失或别的格式照收；
  - 29-8：`codec` 2 标 `hevc`、未知编码不标、“优先 H.264”两种顺序；
  - `limitType`：S04-room-chatlimit 是直播中、S05-stream-chatlimit 有流；合成的 1、2 不影响状态；
  - 开播时间：场次格式、大小写、别的 `kugouId`、坏格式和越界、晚于回答；列表 `livetime` 的各种坏值；在播样本的场次与列表相差 14、16 秒；搜索的 `lastLiveTime` 与网站显示的“4小时55分钟前”一致；
  - 受限类型：`withRestriction` 的三种；`code` -1 是 `NeedsLogin`；
  - 占位：昵称、标题为空；
  - 原有的分类、列表、图片、坏行、状态码、JSONP、租期、请求地址。
- `kugoulive_site_test.dart`（37 个）：
  - 请求与 v3 对照（地址、请求头、次数），房间与 v3 对照（按上面的差异）；
  - 搜索快照：第 1 页与 v3 同样请求、之后的页不请求；30 秒、换关键词、第 1 页、时钟倒退、失败、最多 8 个关键词；有快照时取消仍生效；
  - 按手机分享页搜索和进房；
  - 公聊限制的房间：进房 2 个请求、直播中、`none`、画质和地址、开播状态为真；
  - 要求登录：直播中、`needsLogin` 和公告、取流 `NeedsLogin`、没有进房数据时重新进房；没有流：`unplayable`；其他取流失败仍让进房失败；
  - “优先 H.264”：每次读、默认开、关时 HEVC 在前、线路标 `hevc`；
  - 关注合并：详情的空标题不覆盖存下的标题，受限类型同一场保留；
  - 原有的分类、目录、错误映射、恢复、租期、链接。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.26 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.26-酷狗直播弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
