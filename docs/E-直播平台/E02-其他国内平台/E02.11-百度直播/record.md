# E02.11 百度直播

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/baidulive/`（`baidulive_api.dart` 纯解析，含链接；`baidulive_site.dart` 请求编排）
- 样本：`fixtures/baidulive`，6 个真实接口录制，全部来自归档（2026-09-27 本机默认出口，匿名）：推荐流第 1、2 页 `S01-feed-rec-p1`、`-p2`（同一会话），购物频道 `S01-feed-shopping-p1`，房间命令的在播、已结束、不存在 `S02-room-live`、`-ended`、`-notfound`。都是 v3 会发的请求。归档没有百度的弹幕样本（v3 和归档 v4 都没有百度弹幕），所以没有 `danmaku` 目录。
- 参考：
  - 归档 v4 的百度适配器和规格（`spec/sites/baidulive.md`；没有回归条目，§10 有三条“踩过的坑”）；
  - pure_live_TV `e1cca224`：`lib/platforms/baidulive/` 与 v3 逐行相同，只改了导入路径，在线、粉丝缺值时写空串而不是 null（对照笔记 `~/ref/notes/tvcore/small_diffs.txt`、`sub_A.md` 的 baidulive 一节），没有行为修复。笔记里“TV 已坏”的判断见问题 1、2 的实测，并不成立。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

## 做法

> E06 平台层升级（2026-09-29）按用户批准的升级改了画质（“原画 + 720p/480p”、平台现在的 CDN 作备用线路、H.265 单列）、已结束房间的回放、付费和封禁的状态、推荐的会话、简介、http 链接、“FLV 原始线路”的 http、公告和昵称兜底，另按统一原则补了开播时间和受限类型，并修好了 v3 打不开的预告房间，见文末“升级落地（E06 平台层升级）”（30-1～30-10）。本节以下是 E02.11 时的做法。

- **接口照 v3**：`LiveSite` 和 v3 实现过的全部可选能力——原生目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `baidulive_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、关注刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、带实际画质的取流（`LivePlayUrlResolver`，给出线路）、恢复时重新取流（`LivePlayRecoveryResolver`），另加 `LiveSiteLinks`。3.x 的 JSON 不变。
- **匿名，照 v3**：所有请求以 `baidulive` 的名义发出（代理路由由应用按平台注入），带 v3 的请求头（桌面 Chrome 140 UA、`Accept: application/json, text/plain, */*`、`Origin`/`Referer` 为 `live.baidu.com`），**不跟随跳转**，不带 Cookie。v3 没有百度的登录和 Cookie 设置，所以不注入 `CookieVault`，也没有账号请求。
- **请求照 v3**：

  | 调用 | 请求 | 次数 |
  |---|---|---|
  | 分类 | 不请求：一个分类“百度直播”，分区是频道。第一次读到推荐流第 1 页之前用 v3 写死的七个频道（推荐 570、购物 574、财经 611、健康 612、教育 613、新闻 575、休闲 616），之后用第 1 页 `tab` 块里平台给的列表 | 0 |
  | 目录、推荐、分区房间 | `POST tiebac.baidu.com/livefeed/feed`，签名表单（下一段）；推荐就是第一个频道 | 1 |
  | 房间号或房间链接搜索（第 1 页） | 房间命令（下一段） | 1 |
  | 进房、关注刷新、录制、开播状态、恢复 | 房间命令 `GET mbd.baidu.com/searchbox?cmd=371&…` | 1 |
  | 没有播放数据的房间取流（列表卡片、刷新过的关注） | 房间命令 | 1（v3 直接失败） |

  - 表单字段和顺序照 v3：`appname=pclive&sid&ua=320_480_pc_1.0_0&uid=<设备>&timestamp=<秒>&source=pclive&resource=<第 1 页 banner,tab,feed，之后 feed>&scene=pc_channel&session_id=<第 1 页空，之后上一页的会话>&refresh_type=<0/1>&refresh_index=<第 1 页 1，之后上一页的值 + 1>&tab=<频道>&channel_id=<编号>&sign=<签名>`。签名是除 `sign` 外的字段按名字排序、拼成 `k=v&k=v`，后接 `&` 和网页常量，取 md5。正文照 v3 的 Dart `Uri(queryParameters:)` 编码，空字段写成 `sid&`（归档的录制工具写成 `sid=&`，2026-09-28 实测两种平台都接受），内容类型不带 charset；
  - 房间命令的查询参数照 v3 逐字相同（`data` 是 JSON，含房间号和设备号），空的 `bd_vid` 同样写成 `bd_vid&`；
  - 设备号照 v3：推荐流每个适配器一个 `pc-<时钟>purelivedev`，房间命令每次新造 `pc-<时钟>baidulive`（`uid` 和 `data.device_id` 相同）。
- **目录照 v3**：
  - 每个频道一个推荐流会话。第 1 页开新会话；之后只能请求这个会话的下一页，别的页码返回空、没有下一页，不发请求（v3 的 `_BaiduDirectorySequence`）；
  - 一页只保留这个会话还没出现过的房间；满 10 条、有新房间、`refresh_index` 前进了，才有下一页；
  - 推荐和“推荐”分区是同一个频道 `rec`，共用一个会话（v3 如此）；请求失败不动会话，同一页可以重试；
  - 第 1 页带回的频道列表替换分类（`tab` 块失败时保留原来的，见问题 7）；
  - `getRecommendRooms`、`getCategoryRooms` 取这一页的前 `pageSize` 个房间。
- **卡片照 v3**：房间号 `room_id`，`userId` 是主播 `host.uk`（没有时用房间号），标题 `title`（空时昵称），昵称 `host.name`（空时 `Baidu Live`），头像 `host.avatar`（空时用封面），封面 `cover`，分区 `live_tag`（空时 `left_label.text`，再空时“百度直播”），只有直播中才有在线人数 `audience_count`，没有粉丝数；状态 `live_status` 1 直播，0、2、3 未开播，其他未知；公告是 v3 的聊天说明。图片只接受 `bdstatic.com`、`bdimg.com`、`bcebos.com`（及子域）上的 https 地址（v3 的白名单）。
- **房间照 v3**：
  - `data.371` 为 null、`error_code` 1 或 4、`host` 和 `video` 都没有：不存在（`NotFound`）；其他 `error_code`（或没有）、`share_url` 指向别的房间：`ApiChanged`；
  - 付费（`has_pay_service`）、禁止播放（`is_forbidden_url`）、封禁（`ban_status`）显示为“未知”，公告前加 v3 的限制说明；否则 `status` 0 直播，-1、1（预告）、2、20、3（已结束）未开播，其他未知；
  - 标题 `video.title`（空时昵称），昵称 `host.nick_name`（空时 `name`，再空时 `Baidu Live`），头像 `host.image.image_33`，封面 `cover_100`（空时 `vertical_cover`），分区 `category`，直播中的在线人数 `online_users`，粉丝 `real_fans_num`（空时 `host.fans`）；
  - 之前见过的卡片或房间（v3 的 `_known`）补上这次没给的字段（见差异 6、9）。
- **房间身份与 v3 一致**：房间号是一场直播的 `room_id`（同一主播再开播是新房间号，v3 的公告就是这样告诉用户的），**保持请求时的号码**；v3 的详情返回请求时的号码，进房和搜索也接受房间链接（取出其中的号码）。样本对照里所有 `roomId` 都与 `expected.json` 一致。房间只需要这一个编号，所以没有另外的 RoomData 编号；进房时把解析结果 `BaiduLiveRoom`（含线路）放进 `LiveRoom.data`，同 v3。
- **画质和线路照 v3**：
  - 画质是 v3 的“协议 × 分辨率”：`url_clarity_list` 每项（`avc_flv`、`flv` 为 FLV，`hls` 为 HLS）、`url_list` 每项、`live_hls_url`（分辨率取 `url_list` 里同名文件的那一档）、没有清晰度列表时 `live_flv_url` 和 `live_flv_url_origin`（源画质，分辨率 0）；只接受 v3 的主机（`hls-live.bdstatic.com`、`flv-live.bdstatic.com`、`*.liveshow.bdstatic.com`，http 改 https）、`/live/` 路径、扩展名对、路径里写着这个房间号的地址；
  - 名称照 3.x 的 zh.json：`HLS 720P · AVC`、`FLV 原始线路 · AVC`；id `<协议>:<分辨率>:avc`；排序值 分辨率 × 10 + FLV 2 / HLS 1；按分辨率从高到低、同分辨率 FLV 在前；
  - 每个地址一条线路：**请求头是 v3 写在房间 `httpHeaders` 里的那一组（UA、`Origin`、`Referer` 房间页）**，格式 FLV/HLS，编码 AVC，线路编号是主机名；地址不带签名和过期参数，没有租期；
  - 服务端不降档，应用的画质就是请求的画质；
  - v3 的主机一个地址都给不出时，才按平台现在的 CDN（`*.liveshow.lss-user.baidubce.com`，保持 http）再读一遍，另加 `avc_url`、`play_url`、`live_hls_url_origin`（归档 v4 读的字段），见问题 2。
- **取流前的检查**：进房得到的房间带着线路，取画质、取地址都不再请求；没有播放数据的房间先读一次房间命令；平台明确未开播的房间直接报 `StreamUnavailable`，不发请求。不能播放时说明原因：未开播或已结束、封禁、禁止播放、在播却没有地址 `StreamUnavailable`，付费 `NeedsLogin`。恢复时重新读房间命令，同一个画质 id 必须还在，旧地址不复用。
- **弹幕**：v3 是 `EmptyDanmaku`，传给弹幕连接的参数为空，所以没有弹幕参数类，`getDanmaku()` 仍是空的。
- **链接**（`roomIdFromUrl`，不发请求）：照搬 v3 的 `BaiduLiveLink.parseRoomId`——只认 https、主机 `live.baidu.com`、默认端口、没有用户信息和片段；路径（忽略空段）`/m/room/<房间号>`，或 PC 播放页 `/m/media/pclive/pchome/live.html`、分享页 `/m/media/multipage/liveshow/index/<短码>` 上的 `room_id`；房间号 6～20 位数字、不以 0 开头。路径或参数解不开的链接不算（见问题 10）。百度没有短链。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/baidulive/baidu_live_api.dart`，`S` = `core/site/baidulive/baidu_live_site.dart`，`L` = `core/site/baidulive/baidu_live_link.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 所有 FLV 画质都播不出来（403）。有清晰度列表的房间（如新闻频道）默认选中的第一个画质就是 `FLV 720P · AVC`，一进房就失败 | S:159、A:153-157；phr:143-148、phr:195-196 | FLV 在 `hls-live.bdstatic.com` 上，这个主机不带 `live.baidu.com` 的 `Referer` 一律 403（2026-09-28 实测：不带请求头、`libmpv`/`Lavf`/Chrome UA、只带 `Origin` 都是 403，带 `Referer` 即 200）。v3 把正确的请求头写进了房间的 `httpHeaders`，但 `PlaybackHeaderResolver` 没有百度分支，`httpHeaders` 又只有 IPTV 分支会读，播放器和录制器实际什么都没发 | 线路自带 v3 的这组媒体请求头；画质菜单不变 |
| 2 | 在播房间只要 v3 的主机白名单一个地址都挑不出，整个房间就打不开 | A:314-316、A:548-549 | “不能播”当成“详情失败”（`room` 在进房时抛 `mediaUnavailable`）；白名单不含平台现在的 CDN `*.liveshow.lss-user.baidubce.com` | 进房照常，取流时报 `StreamUnavailable`；v3 的主机给不出地址时才用平台现在的 CDN 兜底。2026-09-28 实测推荐、购物、新闻三个频道 17 个在播房间，都有 v3 能用的 `live_hls_url` 和 `live_flv_url`，所以用户看到的画质不变 |
| 3 | 列表卡片和刷新过的关注（没有进房快照）取画质、取地址都报“身份错误”；恢复也要先有进房的快照 | S:247-257、S:261-263、S:288-289 | 只认进房时放进 `data` 的快照 | 先读一次房间命令再取；恢复直接重新读 |
| 4 | 未开播的房间取画质得到空列表，播放器拿不到原因 | S:262 | 直接返回 `[]` | `StreamUnavailable`，不发请求 |
| 5 | 失败都是平台自己的 `BaiduLiveException`，播放、录制只能按种类名判断；付费、封禁时开播状态报 `access` | A:12-31、A:622-633、S:239-245 | 平台自定义异常 | 类型化错误（见差异 3） |
| 6 | 已结束的房间仍显示当前在线人数 | A:94、S:220-222 | `enrich` 在这次回答没有在线人数时，沿用之前见到的卡片（当时还在播）的人数，并标成“当前观看” | 只有这次仍在播才沿用（差异 6） |
| 7 | 推荐流的频道块（`tab`）出错时，整页房间都加载失败 | A:342、A:355 | 频道块和房间列表一起严格检查 | 频道块出错时只丢频道，房间照常，分类保留原来的 |
| 8 | 记住的房间只增不减 | S:31、S:127-131、S:220-222 | 没有上限 | 最多记 512 个，最久没用的先丢 |
| 9 | 平台层依赖全局 `HttpClient`，自己实现流式读取（4 MiB）、15 秒接收超时和 20 秒总期限、请求作用域 | A:162-232 | 结构问题 | 注入 `LiveHttp`；超时由 live_net 的逐请求超时（20 秒）负责；大小上限在解析前按字符数检查 |
| 10 | 路径或参数解不开的链接（如 `%FF`）让 `parseRoomId` 抛 `FormatException`，搜索和链接导入直接失败 | L:25、L:29 | `pathSegments`、`queryParameters` 解码失败没有捕获 | 不算链接 |
| 11 | 平台层调用界面翻译（平台名、两条公告、两种画质名、分区的兜底名） | S:39、S:136-137、S:147、S:269-280 | `i18n` 写在适配器里 | 用 3.x 的中文作默认文字（`BaiduLiveApi.siteName`、`chatNotice`、`restrictedNotice`、`qualityName`、`directoryScope`），界面的翻译在 M13 |
| 12 | 调用方传错参数（别的平台或类型的分区、不在分类里的频道、不是房间号的房间）报平台错误 | S:70-81、S:210-215、A:243-256 | 本地校验失败用 `identity` | `ArgumentError`，不发请求；不是房间号的房间 `NotFound`，不发请求 |
| 13 | `flv-live.bdstatic.com` 的 https 证书与主机名不符，“FLV 原始线路”的第二条线路在校验证书时打不开（http 可以） | A:412-424 | 平台给的就是 https；v3 只把 http 升级成 https | 按 v3 保留（第一条线路能播）；播放层是否校验证书见“放到其他模块的部分”（E06 平台层升级 30-9 已改用 http） |
| 14 | 预告房间（新闻频道里 `live_status` 0 的卡片）点进去、按房间号搜索都是加载失败（E06 平台层升级 实测时发现，当时没有样本） | A:344-347 | 预告的房间命令是另一种形状：没有 `error_code`（`template` 是 `preview`，字段在顶层），v3 把缺失的 `error_code` 当作未知错误 | E06 平台层升级 已改：按预告的形状读，显示为未开播，见文末“升级落地（E06 平台层升级）”的“容错” |

另外几处按 v3 保留：

- **推荐和“推荐”分区共用一个会话**（S:72、S:84-88）：一边翻到第 1 页，另一边的会话就重新开始。
- **同一页再请求一次返回空、列表就此结束**（S:90-98）：界面重复触发同一页时会提前结束。
- **付费、封禁的房间显示“未知”**，不按 `status` 显示直播中（v3 的公告就是这样说明的）。
- **预告、已结束都显示未开播**，不显示回放（已结束的房间有回放地址，v3 不播）。
- **房间命令每次新造设备号**。

## v3 的冻结输出

归档没有百度的 `expected.json`（旧版对照工具只做了前五个平台，v3 应用也已经构建不了）。本模块用 `fixtures/baidulive/legacy_expected.dart` 生成，做法同 PandaTV、LiveMe：

- 把 v3 的 `BaiduLiveApi`、`BaiduLiveLink`、`BaiduLiveSite`（`legacy/lib/core/site/baidulive/` 三个文件）原样搬进一个 Dart 程序。v3 本来就把传输做成可注入的函数（`BaiduLiveRequest`），所以只换了它：按方法、主机、路径读样本，推荐流再比表单（不比设备号、时钟和签名），房间命令再比查询参数（不比设备号和时钟）和 `data` 里的房间号；没有样本的请求抛 StateError，v3 的 `_scope` 会把它变成 `transport`，所以另外记下、在调用结束后重新抛出，缺样本会让生成失败；
- 网络路径上的 `_defaultRequest`、`_readBody` 没有搬，API 的构造函数改为必须注入传输；Dio 的 `CancelToken` 只留 v3 用到的成员，v3 的 `withRequestCancellation` 原样搬入；`BaiduLiveSite` 保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`，构造函数改为必须注入 API；`i18n` 返回 3.x `zh.json` 的文字（按 easy_localization 替换 `{name}` 参数）；v3 的模型只搬用到的部分（同 PandaTV 的脚本）；输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记下发出的请求（设备号、时钟、签名写成 `<device>`、`<time>`、`<sign>`）；
- 另外记下 v3 对录制表单算出的签名：三个推荐流样本都与录制时的 `sign` 相同；
- 在仓库根目录运行：`dart run fixtures/baidulive/legacy_expected.dart`（只依赖 v3 用来算 md5 的 `package:crypto`，已在工作区）。连续运行两次，输出逐字节相同。

6 个样本都有 `expected.json`：

- `S01-feed-rec-p1`：平台名、目录说明键，读推荐流前后的分类，第 2 页和每页 0 条的分类，目录第 1 页、推荐（两种条数）、推荐分区，第 0 页、第 1 页之后直接要第 3 页、别的平台和不认识的频道（都不发请求），列表卡片取画质（v3 报 `identity`），昵称搜索（不发请求），`parseDirectoryJson`，签名；
- `S01-feed-rec-p2`：同一会话的第 2 页、再要一次第 2 页，推荐第 2 页取 5 个，`parseDirectoryJson`，签名；
- `S01-feed-shopping-p1`：购物频道第 1 页、分区房间，签名；
- `S02-room-live`：进房、刷新、录制、开播状态、画质、每档地址、`resolvePlayUrlsRaw`、恢复，刷新过的房间取画质（v3 报 `identity`），按房间号（含前后空格）、房间页、PC 播放页、分享页搜索和第 2 页，`parseRoomJson`（本房间和别的房间），先看过目录再进房，26 个链接向量的 `parseRoomId`、`watchUrl`、两组请求头，10 个媒体地址向量的 `validateMediaUri`；
- `S02-room-ended`：同上的房间入口、两种搜索、`parseRoomJson`；
- `S02-room-notfound`：房间入口、两种搜索、`parseRoomJson`（v3 全是 `missing`）。

**脱敏**：归档的三个房间命令样本在响应头里留着 `x-bfe-svbbrers`，前半是 Base64 编码的录制时的出口 IP（与 `fixtures/xiaohongshu` 的 `xhs-real-ip`、`fixtures/acfun` 的 `x-ksclient-ip` 是同一个地址，这两处已在合并时一并替换）。已换成 `203.0.113.7`（文档保留地址）的 Base64 `MjAzLjAuMTEzLjc=`。其余字段查过：观众列表、聊天列表地址的 `authorization` 归档已脱敏；设备号是录制脚本自造的；`uk`、`nid`、`logid` 是主播和场次的公开编号。小红书、AcFun 那几个样本里的同一个 IP 不属于本模块，没有改。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和每档地址；请求比较方法、地址、查询参数、表单（含字段顺序）和请求头（名字不分大小写）。所有房间只有 `httpHeaders` 一个键不同（差异 1）。

| 样本 | 结果 |
|---|---|
| 分类 | 读推荐流前七个频道、读后平台给的七个频道，逐项一致（v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价）；第 2 页和每页 0 条为空，都不发请求 |
| S01 推荐第 1 页（10 个） | 表单、字段顺序、签名与 v3 相同（签名与录制时的逐字相同）；房间、顺序、各字段一致；有下一页一致；推荐（30 条和 4 条）、推荐分区各 1 个请求、结果一致。第 0 页、跳页不发请求；别的平台、不认识的频道 v3 报 `identity`，现在是 `ArgumentError`，都不发请求；昵称搜索不发请求、没有结果 |
| S01 推荐第 2 页（10 个） | 会话号、`refresh_index` 2、`refresh_type` 1、`resource=feed` 与 v3 相同，签名与录制时的相同；房间一致、有下一页；再要一次第 2 页为空、没有下一页，不发请求；推荐第 2 页取 5 个一致 |
| S01 购物频道 | `tab=shopping&channel_id=574`，房间一致 |
| S02 在播 | 进房、刷新、录制、开播状态各 1 个请求，地址与 v3 逐字相同；房间逐键一致（刷新不带播放数据）；画质 `HLS 720P · AVC`、`FLV 原始线路 · AVC` 的名称、id、排序和地址逐字一致，`resolvePlayUrlsRaw` 不发请求、应用的画质一致；恢复各 1 个请求、地址一致；五种搜索各 1 个请求、结果一致，第 2 页不发请求；先看过目录再进房的结果一致。v3 对刷新过的房间取画质报 `identity`，现在读一次房间后给出同样的画质（差异 4） |
| S02 已结束 | 未开播，粉丝 336，没有在线人数，逐键一致；开播状态 false；v3 取画质是空列表，现在 `StreamUnavailable`（不发请求） |
| S02 不存在 | v3 进房、刷新、录制、开播状态都是 `missing`，现在 `NotFound`；两种搜索都没有结果 |
| 链接 | 26 个向量逐个一致 |
| 媒体地址 | v3 的规则 10 个向量逐个一致（兜底的 CDN 只在兜底时接受） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 线路自带请求头（v3 写进房间 `httpHeaders` 的那一组：UA、`Origin`、`Referer` 房间页）、格式、编码、线路编号；房间不再写 `httpHeaders` | 问题 1。v3 的 FLV 画质因此能播了；画质菜单和默认选中的画质不变。3.x 存下的旧 `httpHeaders` 照读、`mergeFrom` 照留（非 IPTV 不覆盖） |
| 2 | 在播却挑不出地址的房间照常进入，取流时报 `StreamUnavailable`；v3 的主机给不出地址时，改读平台现在的 CDN | 问题 2。只在 v3 失败的地方生效 |
| 3 | 出错抛类型化错误：400/422 `ApiChanged`，401/403 `RiskControl`，451 `RegionBlocked`，404/410 和不存在的房间 `NotFound`，429 `RateLimited`，5xx、其他状态（含跳转）和传输失败 `NetworkFailure`，看不懂的回答、`errno` 非 0、未知的 `error_code`、别的房间的 `share_url` `ApiChanged`；取消原样抛出。开播状态：付费 `NeedsLogin`，封禁或禁止播放 `StreamUnavailable`，未知状态 `ApiChanged`（v3 都是 `access`） | 问题 5。界面看到的仍是加载失败 |
| 4 | 没有播放数据的房间取流前先读一次房间命令；平台明确未开播的房间直接报 `StreamUnavailable`，不发请求；恢复直接重新读 | 问题 3、4。正常进房流程不受影响 |
| 5 | 推荐流的频道块出错时，房间照常显示，分类保留原来的 | 问题 7。只在 v3 失败的地方生效 |
| 6 | 已结束的房间不再沿用之前卡片上的在线人数 | 问题 6。改正的是错标的数据；关注列表里存下的人数仍由 `mergeFrom` 保留 |
| 7 | 路径或参数解不开的链接不算链接 | 问题 10。v3 能认的链接结果不变 |
| 8 | 调用方的参数错误是 `ArgumentError`，不是房间号的房间是 `NotFound`，同 v3 不发请求 | 问题 12 |
| 9 | 记住的房间最多 512 个 | 问题 8。只影响很久以前看过的卡片能否补字段 |
| 10 | 不再有 20 秒的总期限和 15 秒的接收超时，由每个请求各自的 20 秒超时代替；响应在解析前按字符数查 4 MiB；非法 UTF-8 变成替换字符而不是报错 | 问题 9；同 E03.7 等模块 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **画质仍是 v3 的“协议 × 分辨率”**（`HLS 720P · AVC`、`FLV 原始线路 · AVC`，只取 v3 的主机）。归档 v4 改成“原画”（`avc_url`）加 `url_list` 的 720p、480p，每档 FLV 两个 CDN 再加 HLS，画质菜单会变；它读的字段只用作兜底。归档规格说“旧版取不到可用地址”，2026-09-28 实测并非如此：v3 的 HLS 地址（`hls.liveshow.bdstatic.com`，http 和 https 都行，分片不需要请求头）一直能播，FLV 只是缺 `Referer`（问题 1）；而 `url_list` 里的 480p 有的房间是 404，第二个 CDN（`flv2`、`hls2`）本机解析不到。
- **分类照 v3**：一个分类“百度直播”，七个频道都是分区（含“推荐”），分区 id 是频道名（`shopping`）。归档 v4 另设分类“频道”、去掉“推荐”分区、分区 id 写成 `shopping:574`，3.x 存下的关注分区会对不上。
- **目录翻页照 v3**：按页码、会话内去重、满 10 条且有新房间且 `refresh_index` 前进才有下一页。归档 v4 用游标、本页非空就继续，平台是个性化无限流，全是重复时会一直请求下去（上游笔记 `sub_A.md` 第 2 条待修项）。2026-09-28 实测三个频道每页都是 10 条，v3 的规则能一直翻下去。
- **搜索照 v3**：只认房间号和房间链接，第 1 页。归档 v4 没有搜索。
- **状态照 v3**：预告、已结束显示未开播，付费、封禁显示“未知”加限制说明，未知的 `status` 显示“未知”。归档 v4 付费、封禁照常按 `status` 显示、未知的 `status` 报 `ApiChanged`。
- **链接只认 https**（v3 的测试明确拒绝 http）。归档 v4 也接受 http。
- **图片照 v3 的白名单**；归档 v4 接受任何地址。
- **读粉丝数 `real_fans_num`**（v3、上游有，归档 v4 没有）；**不读简介 `video.description`**（v3 没有，归档 v4 有），列为升级候选。
- **标题、昵称不做 HTML 实体解码**（v3）；归档 v4 解码。样本里没有实体。
- **设备号照 v3**：推荐流每个适配器一个，房间命令每次新造。归档 v4 每个适配器一个。
- **房间号保持请求时的号码**，同 v3 和归档 v4。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复；它把在线、粉丝缺值写空串，这里同样写空串（`mergeFrom` 因此保留存下的值）。

## 后续升级候选（由用户决定）

（2026-09-28 用户已全部采用，编号 30-1～30-10，落地见文末“升级落地（E06 平台层升级）”。）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 画质改成归档 v4 的“原画 + 720p/480p”，或把平台现在的 CDN 作为同档的备用线路 | v3 的“协议 × 分辨率”，只用 `bdstatic.com` 的地址 | 归档规格 §5；会改变画质菜单和存下的画质偏好 |
| 2 | 清晰度列表里的 HEVC（`hevc_flv`）作为单独的画质 | 只读 AVC | 2026-09-28 实测清晰度列表带 HEVC 地址 |
| 3 | 百度弹幕（HLS 轮询的消息列表） | 没有弹幕 | 归档规格 §7：房间命令给出 `chat_msg_hls_url` 等三个列表，5 秒轮询；实测聊天量很小 |
| 4 | 已结束的房间播放回放（`replay_list`），或显示为回放 | 未开播，不能播 | 样本 `S02-room-ended` 有回放地址；会改变状态显示 |
| 5 | 付费、封禁的房间按 `status` 显示直播中，播放时提示原因 | “未知”加限制说明 | 归档 v4 |
| 6 | 推荐和“推荐”分区各用一个会话；同一页再请求时重放上次的结果 | 共用会话；再请求为空并结束 | 问题清单后的前两条 |
| 7 | 显示简介 `video.description` | 不显示 | 归档 v4 |
| 8 | 接受 http 的房间链接 | 不接受（v3 测试固定） | 归档 v4 |
| 9 | “FLV 原始线路”的 `flv-live.bdstatic.com` 改用 http | https，证书与主机名不符 | 问题 13 |
| 10 | 公告改成用户能看懂的说明（现在是“百度远端聊天尚待接入；目录 audience_count……”这类开发说明）；昵称兜底 `Baidu Live` 随界面语言 | 3.x 原文 | M13 翻译时一并考虑 |

## 回归条目的覆盖

归档规格没有百度的回归条目（REG-BAIDULIVE-…）。§10 “踩过的坑”三条都有测试：

- 在播房间没有可用地址：实测根因是 FLV 缺 `Referer`（问题 1），线路带请求头有测试；v3 的主机给不出地址时的兜底（问题 2）有合成用例。
- 已结束的房间仍给出地址：先看 `status`，不在播不组线路（`S02-room-ended` 的 `url_list` 仍有地址，测试断言没有画质、取流报 `StreamUnavailable`）。
- 推荐只翻一页：v3 的规则在每页 10 条时会继续翻，样本第 1、2 页都有下一页；停止条件（不满 10 条、全是重复、`refresh_index` 不前进）都有测试。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕：`getDanmaku()`（v3 为空）；协议见归档规格 §7 | D01（升级候选 3） |
| 平台名、目录说明（`baidulive_directory_scope`）、两条公告、两种画质名、昵称兜底的繁体和英文 | M13 多语言。本模块给出 3.x 的中文（`BaiduLiveApi.siteName`、`directoryScope`、`chatNotice`、`restrictedNotice`、`qualityName`、`anonymousName`） |
| 目录说明常驻（`LiveDirectoryNotice`） | M13 热门页、分区页 |
| 搜索能力表：只按房间查找、不翻页、没有网页搜索（3.x `modules/search/search_capability.dart:101-105`） | M13 搜索页 |
| 外部打开 `https://live.baidu.com/m/room/<房间号>`（3.x `modules/live_play/services/room_external_opener.dart:135-136`） | M13；地址由 `BaiduLiveApi.roomUrl` 和房间的 `link` 提供 |
| 本地互动的平台名（3.x `local_interaction_controller.dart:490-491`） | M13 |
| 平台注册和图标（3.x `core/sites.dart:71`、`106`、`199`、`257`、`391-395`） | I01.1 应用骨架；平台 id 已在 M3 的 `SiteIds.baiduLive` |
| 平台列表升级时追加百度直播（`favorite_room_controller.dart:92`，`siteCatalogMigration` 第 36 版；3.x `test/baidu_live_catalog_migration_test.dart`） | J02.1 |
| 播放和录制按线路的请求头打开（FLV 缺 `Referer` 就是 403）；“FLV 原始线路”第二条线路的证书与主机名不符，播放层若校验证书会打不开（问题 13） | G、H01.1 |
| 人数能力（`audience_count`、`online_users` 是在线，没有累计和热度） | 已在 E05.1 的 `audience.dart` |
| 3.x 的链接工具和网页搜索解析里的百度分支（`live_url_tool.dart:124`、`253-254`，`web_search_room_parser.dart:122-125`） | 已由本模块的 `LiveSiteLinks` 加 M3 的 `LinkParser` 代替 |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出。签名用工作区已有的 `package:crypto`（md5），链接用 M3 的 `LiveSiteLinks`、`LinkParser`，JSON 读取用 `json.dart`。

## 测试

58 个用例，`live_core` 共 2528 个，全部通过：

- `baidulive_api_test.dart`（27 个）：逐个样本对照 v3 的输出（两种分类、推荐流两页和购物频道的解析与卡片、三个房间命令的解析、三种详情、画质、每档地址、应用的画质），有意的差异逐条断言（`httpHeaders`、已结束房间取画质、频道块出错、已结束房间的人数）；表单字段、顺序和签名（三个样本的签名与录制时的逐字相同，v3 测试的 `b=2&a=1`）；移植了 v3 `baidu_live_site_test.dart` 的解析用例（十张卡片和两个频道、清晰度列表加 `url_list` 的房间、别的房间和 `lss-user` 的地址不收、链接的认与不认）；卡片的状态、兜底和图片主机；房间的七种 `status`、付费、封禁、禁止播放和它们的组合；v3 拒绝的回答；状态码映射；兜底的 CDN；媒体地址规则（v3 的 10 个向量和兜底）；`enrich` 的规则；链接（v3 的 26 个向量，解不开的链接）。
- `baidulive_site_test.dart`（31 个），用样本回放加合成回答：
  - 平台名、目录说明、能力、没有弹幕；推荐流和房间命令的设备号（v3 的写法）；
  - 分类：不请求，第 1 页之后换成平台的频道，新出现的频道能请求，下一次第 1 页再替换；
  - 目录：请求地址、表单、字段顺序、签名、请求头、不跟随跳转与 v3 相同（正文与录制时的相同，只是空字段按 v3 写成 `sid&`）；第 2 页的会话和序号；不发请求的页码；调用方错误；推荐和分区房间的条数；购物频道；会话内去重和三种停止条件；每个频道各自的会话；失败后重试同一页；取消（请求前、请求中）；
  - 搜索：五种输入与 v3 的请求和结果相同，第 2 页、0 条、昵称、http 链接、别的页面不发请求，已结束和不存在的房间，其他失败照抛，取消；
  - 房间：进房、刷新、录制各 1 个请求（地址与 v3 相同，空的 `bd_vid` 按 v3 写成 `bd_vid&`），已结束、不存在，房间链接当房间号，非法房间号不请求，开播状态的各种情况，先看过目录再进房、卡片补字段、已结束的房间不沿用卡片人数；
  - 取流：进房得到的房间不再请求，画质、地址、应用的画质与 v3 相同，线路的请求头；恢复与 v3 相同、画质没了报错；没有播放数据的卡片读一次、未开播不请求、别的平台；不能播放的房间照常进入、取流时说明原因；兜底的 CDN；
  - 错误映射（传输失败、取消、各状态码）；
  - 链接（经 `LinkParser`）：分享文本里的房间页、PC 播放页、分享页，别的页面、主机和 http 不识别，没有短链，不发请求。

## 升级落地（E06 平台层升级）

- 日期：2026-09-29（E02.11）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 30-1～30-10（“落地方式”只有 30-1、30-4、30-9 有内容，其余按上面“后续升级候选”的原文做）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。30-1 按落地方式采用“原画 + 720p/480p”，平台现在的 CDN 作同档备用线路。30-3（弹幕）属于 D01，本任务不做。
- 改动：只改了本平台：`baidulive_api.dart`（解析）、`baidulive_site.dart`（请求编排）、两份测试和 5 个新样本（见“新样本”）。没有改 `live_core` 的通用文件，没有新依赖。
- 实测：2026-09-28 20:55～21:20 UTC，直连、匿名、只读，请求头同 v3：
  - 7 个频道的推荐流第 1 页（70 张卡片，64 个房间），和这 64 个房间的房间命令：60 个在播、1 个已结束、3 个预告（`status` -1）；新闻、财经、推荐频道再往下翻到第 12 页找已结束和预告的房间；
  - 60 个在播房间逐个读了“原始”流（`live_flv_url_origin` 改用 http）和 `live_flv_url` 的 FLV 头：57 个的原始流是 H.264，3 个是 H.265（见 30-2）；
  - 一个 H.265 原始流的房间（11586291324）逐个打开了房间命令里的全部地址，带和不带 `Referer`：`hls-live.bdstatic.com` 不带 `Referer` 是 403（E02.11 问题 1），`flv-live.bdstatic.com` 的 https 证书与主机名不符、http 能播（30-9），`*.liveshow.bdstatic.com` 的 http、https 都能播，`flv.`、`hls.liveshow.lss-user.baidubce.com` 的 http 能播，`flv2.`、`hls2.` 本机解析不到；
  - 两个已结束房间的回放录像（样本 `S02-room-ended` 那场和 11562145409）：`replay_list` 的 `video`、`clarityUrl` 和 `video_hevc` 都是 `p2.bdstatic.com` 上的点播 m3u8，http、https 都能取，不要请求头；读了第一个 TS 分片的 PMT：`clarityUrl`（“标清”）是 H.264，`video_hevc`（“720p”）是 H.265。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 30-1 | 画质从 v3 的“协议 × 分辨率”改为按档：“原画”（源流）和每个分辨率一档（`url_list` 的 720p、480p；有清晰度列表 `url_clarity_list` 的房间另有 1080p、540p），同一档的 FLV、HLS 和两个 CDN 合成这一档的多条线路，互为备用（`BaiduLiveApi.liveVariants`）。<br>**地址按流名归档**：流名（地址的文件名）是 `…_<房间号>` 的是源流；带后缀的（`-L3`、`-mid-LV720`）归到 `url_list` 或清晰度列表里列出同一个流名的那一档。读的字段：清晰度列表每项的 `avc_flv`、`flv`、`hls`、`hevc_flv`；`url_list` 每项的 `flv`、`hls`；`live_flv_url`、`avc_url`、`play_url`、`live_hls_url`、`avc_hls_url` 按流名归档；`live_flv_url_origin`、`live_hls_url_origin` 是源流；`hevc_url` 是 H.265 的源流（30-2）。流名哪一档都对不上的地址不要（例如 v3 测试房间的 `-L1.flv`）。<br>**线路顺序**：v3 的主机（`hls-live.bdstatic.com`、`flv-live.bdstatic.com`、`*.liveshow.bdstatic.com`）在前，就是 v3 播的那几条；平台现在的 CDN `*.liveshow.lss-user.baidubce.com`（`flv`、`flv2`、`hls`、`hls2`，保持 http）作备用线路在后；各自 FLV 在前、HLS 在后；同一主机同一个流只留一条。线路编号是主机名，同一档里同一主机的第二个流写成 `<主机>#2`。<br>**排序和 id**：原画最前，其余按分辨率从高到低；id 是 `source`（原画）和 `<高度>p`；`sort` 是档位 × 10 加编码（H.264 2、不知道 1、H.265 0），原画的档位按 100000 算。v3 的 id 仍能取流（按下面的对照换成新 id，确认的画质报新 id）。<br>E02.11 的“v3 的主机给不出地址才用平台现在的 CDN”（问题 2）由此变成每一档都带备用线路 | 画质菜单从“HLS 720P · AVC”“FLV 原始线路 · AVC”两项变成“原画”“720p”“480p”三项（新闻、财经等有清晰度列表的房间是“1080p”“720p”“540p”“480p”“原画”）。默认画质从“HLS 720P”变成“原画”（源流，画质最好）。多了 480p。每档多了几条备用线路，一条打不开换下一条（G）。“原画”的前两条就是 v3“FLV 原始线路”的两条 | 平台层完成，余下 J02.1 |
| 30-2 | H.265 单列为画质，名字加“ · H.265”，id 加 `:hevc`：清晰度列表的 `hevc_flv`（该档的 H.265）、`hevc_url`（`…_wz_hevc.flv`，源流的 H.265 版）。<br>**源流的编码**：平台不说。实测 60 个在播房间有 3 个的源流是 H.265，这时平台的 H.264 字段（`live_flv_url`、`avc_url`）都指向 720p 的转码，而源流是 H.264 的 57 个房间里它们都指向源流。所以：H.264 字段指向源流时，源流是 H.264；没有清晰度列表、而 H.264 字段指向转码时，源流是 H.265（“原画 · H.265”，id `source:hevc`，与 `hevc_url` 合成一档）；有清晰度列表的房间，H.264 字段指向清晰度列表的默认档（`avc_default`），看不出源流的编码（实测 3 个这样的房间有 1 个是 H.265），这时“原画”的编码写空（`codec` 为 null）。<br>**“优先 H.264”**（统一原则“默认编码”，与 8-8、14-5、22-3、33-2 共用的设置，默认开）：适配器每次取画质时读（`BaiduLiveSite(http, preferH264: …)`、`BaiduLiveApi.qualities(room, preferH264: …)`）。开：H.264 的档在前（从好到差），编码不知道的在其后，H.265 最后，默认播 H.264；关：按档位排，同档 H.264 在前（`BaiduLiveApi.ordered`）。线路的 `codec` 写 `avc`、`hevc` 或空 | 源流是 H.265 的房间：v3 的“FLV 原始线路 · AVC”其实是一条 720p 的 H.264 加一条 H.265 的源流，现在分开：“原画 · H.265”排最后，默认播 720p（H.264）。有清晰度列表的房间默认播 1080p（v3 默认也是它），“原画”排最后。关掉“优先 H.264”后原画排第一 | 平台层完成，余下 G/M9/M13 |
| 30-3 | 本任务不做（D01）。平台层没有新增数据，见“留给其他模块” | 无 | 待做（不变） |
| 30-4 | 已结束（`status` 3、卡片 `live_status` 3）改为回放（v3 显示未开播）。录像取 `replay_list` 里第一个有录像的条目（`BaiduLiveApi.replayVariants`）：`videoInfo.ext.clarityUrl` 每项一档（H.264，名字用平台的 `title`，没有时用 `key`，id `replay:<key>`），没有清晰度时用 `video`（“回放”，id `replay`）；再加 `video_hevc`（JSON 文本，键是清晰度，H.265，名字 `<键> · H.265`，id `replay:<键>:hevc`）。录像地址要是 `*.bdstatic.com` 上、路径在这个房间的流目录（`_<房间号>/`）下的 m3u8（http 改 https，`BaiduLiveApi.replayUrl`）。每档一条 HLS 线路，带媒体请求头，线路编号是主机名，没有租期。<br>有录像：回放、受限类型 `none`，关注分组在回放；拿不到录像：回放 + `unplayable`，分组归入未开播，取流报 `StreamUnavailable`（without a recording）。列表卡片：`play_url` 是合规的录像地址时 `none`，否则 `unplayable`。付费、封禁的回放分别是 `paid`、`unplayable`（30-5）。已结束房间残留的 `url_list` 仍然不播（归档规格 §10）。开播状态查询对回放返回未开播 | 关注和新闻频道里已结束的直播显示为回放，点进去能从头看这一场的录像：“标清”（S02-room-ended 那场实际是 720p 的 H.264 转码）和“720p · H.265”，默认 H.264。拿不到录像的归入未开播并标“不可播放”（M13） | 平台层完成，余下 G/M13 |
| 30-5 | 付费（`has_pay_service`）、禁止播放（`is_forbidden_url`）、封禁（`ban_status`）不再显示“未知”，按 `status` 显示（`BaiduLiveState.restricted` 去掉）：受限类型付费是 `paid`，禁止播放或封禁是 `unplayable`（两者都有时 `unplayable`），只在直播中和回放时填。取流报 `StreamUnavailable`，说明里写 `(paid)` 或 `(unplayable: forbidden or banned)`（E05.2 的受限类型表；E02.11 付费报 `NeedsLogin`，本平台没有登录）。开播状态查询对受限的直播返回在播（E02.11 报 `NeedsLogin`、`StreamUnavailable`）。卡片只有 `has_pay_service`：付费是 `paid`，是 0 是 `none`，没有这个字段不填 | 付费、封禁的直播从“待定”变成直播中，关注分组在直播中，卡片标“付费”“不可播放”（M13），播放时说明原因。实测 70 张卡片、64 个房间命令都没有付费和封禁，平时看不出变化 | 平台层完成，余下 M13 |
| 30-6 | 推荐（`getRecommendRooms`、不带分区的 `getDirectoryPage`）用自己的推荐流会话，“推荐”分区（`rec` 频道）用另一个，两者都请求 `tab=rec`；v3 共用一个，一边翻到第 1 页，另一边的会话就重新开始。同一个会话再要一次它最后给出的那一页时，直接重放上次的结果（同一个 `LiveDirectoryPage`），不发请求；v3 回空页，列表就此结束。第 1 页照旧每次开新会话（下拉刷新）；跳页照旧为空 | 推荐页和“推荐”分区来回切换时，已经翻到的位置不再被打断；界面重复加载同一页时不会提前结束 | 完成（E06 平台层升级） |
| 30-7 | 进房、刷新、录制、按房间号搜索的房间带简介：`video.description`（空时不写）；预告房间取它自己的 `description` | 房间页显示直播简介（实测 60 个在播房间 59 个有简介） | 完成（E06 平台层升级） |
| 30-8 | 房间链接也认 http（`BaiduLiveApi.roomIdFromUrl`）：http 用 80 端口、https 用 443 端口（写明默认端口也认），其余规则不变。搜索、进房、链接导入都认 | 粘贴 `http://live.baidu.com/m/room/…` 能找到房间（v3 没有结果） | 完成（E06 平台层升级） |
| 30-9 | `flv-live.bdstatic.com` 的地址改用 http（`BaiduLiveApi.mediaUrl`）：它的 https 证书与主机名不符，http 实测能播。其他 `bdstatic.com` 主机仍把 http 改成 https（v3），`lss-user` 保持平台给的写法 | 原画（v3 的“FLV 原始线路”）的第二条线路能打开了 | 完成（E06 平台层升级） |
| 30-10 | 公告改成用户看得懂的话（多语言键不变，M13 按界面语言显示）：`baidulive_chat_notice` 从“百度远端聊天尚待接入；目录 audience_count 与房间 online_users 按当前观看人数展示，主播粉丝数单独展示。”改为“这里暂时看不到百度直播间的聊天。人数是正在观看的人数，主播的粉丝数另外显示。”；`baidulive_restricted_notice` 从“该百度直播受付费或访问范围限制，界面保持未知状态，不将其显示成未开播。”改为“这场直播需要付费观看或受到平台限制，暂时不能在这里播放。”（付费、禁止播放或封禁时加在前面，同 v3）；目录说明 `baidulive_directory_scope` 的中文默认文字（`BaiduLiveApi.directoryScope`）改为“这里是百度直播官网的推荐和各个频道，往下翻会继续加载。搜索只能输入房间号，或粘贴百度直播的直播间、分享链接，还不能按主播名字搜索。”<br>昵称兜底 `Baidu Live` 去掉（`BaiduLiveApi.anonymousName` 删除）：没有名字时 `nick` 为空，标题没有时用昵称、昵称也没有时为空（v3 两处都写 `Baidu Live`）；`enrich` 按“是否为空”补（v3 按“是否等于 `Baidu Live`”）。界面用 `displayNick(本地化的平台名)` 显示（E05.2） | 公告不再是开发说明。没有名字的房间显示界面语言的平台名（M13）；关注刷新不再把存下的主播名、标题换成 `Baidu Live` | 平台层完成，余下 M13 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 房间命令的 `create_time`（Unix 秒），只在直播中填（`BaiduLiveApi.startedAt`，0、负数、非整数、超过 10 位的不填）。依据：两个已结束房间的录像第一个分片（`#EXT-X-PROGRAM-DATE-TIME`）都在 `create_time` 之后 26 秒；房间号按创建先后分配，而 60 个在播房间里有 3 个的 `create_time` 比号码更大的房间还晚 8～21 小时（例如样本 S02-room-live 的 11560887291 是 09-16 15:59，号码更大的 11561568187 是 09-16 06:54），说明先建好（预告）的房间开播时 `create_time` 会改成开播的时刻，而不是建房的时刻。又守着一个预告房间开播直接对照：11586395672 预定 2026-09-28 23:30:19 UTC 开播，房间号在录制时（21:02）已经分配，23:37 第一次读到在播，`create_time` 是 23:35:18，正是开播的时刻。卡片、预告房间、回放没有开播时间，不填 |
| 受限类型 | 见 30-4、30-5。房间命令：直播中和回放一律填（`none`、`paid`、`unplayable`），直播中却没有本客户端能用的地址也是 `unplayable`（E05.2，E02.11 问题 2 的情况）；预告、未开播、状态未知不填。卡片：直播中按 `has_pay_service` 填，回放按 `play_url` 和 `has_pay_service` 填，其他不填 |
| 受限的直播改为直播中 | 见 30-5（E05.2 点名的“用 `unknown` 表示受限”的平台之一） |
| 占位信息 | 见 30-10。封面、头像没有占位图：头像缺时用封面（v3），封面缺时为空 |
| 回放、“不可播放” | 见 30-4 |
| 画质命名 | 见 30-1、30-2：源画质叫“原画”，同档的格式和 CDN 合成一档；回放的清晰度用平台的名字，没有清晰度时叫“回放” |
| 默认编码 | 见 30-2 |
| 房间身份 | 不变：房间号是数字，大小写无关，不加入 `SiteIds.caseInsensitiveRoomIds`。表里没有按主播关注的条目，仍按场次（房间号）关注 |
| 容错 | 一个地址不合规、流名对不上只少这一条线路（30-1）；一个回放条目没有录像就看下一个（30-4）；清晰度列表里没有分辨率的一项只跳过这一项（v3 当成源流）。**预告房间**（新发现的 v3 问题）：预告的房间命令是另一种形状，没有 `error_code`、`template` 是 `preview`，标题、封面、主播名（`source`）、头像、`uk`、简介都在顶层（样本 `S02-room-preview`）；v3 因为没有 `error_code` 报 `ApiChanged`，新闻频道里的预告卡片点进去、搜它的房间号都是加载失败。现在按这种形状读，显示为未开播。只在 v3 失败的地方生效：`error_code` 缺失而不是预告形状的回答仍是 `ApiChanged` |
| 翻页 | 见 30-6。推荐流是平台的个性化会话，没有一次取全的列表；会话内去重（v3 已有） |
| 弹幕 | 见 30-3 |
| 说明文字 | 见 30-10 |

### 请求数

| 场景 | E02.11 | 现在 | 说明 |
|---|---|---|---|
| 分类 | 0 | 不变 | — |
| 目录、推荐、分区房间每页 | 1 | 1；再要一次同一个会话最后给出的那页 0 | 30-6 |
| 房间号、房间链接搜索 | 1 | 不变 | http 链接也发（30-8） |
| 进房、关注刷新、录制、开播状态 | 1 | 不变 | 回放、简介、开播时间、受限类型都来自同一个回答 |
| 取流：带进房数据的房间 | 0 | 不变 | 回放也是 0 |
| 取流：没有进房数据的卡片 | 1；明确未开播 0 | 不变 | 回放卡片 1 |
| 恢复取流 | 1 | 不变 | — |
| 链接导入 | 0 | 不变 | — |

### 画质 id 对照（给 J02.1）

| 旧 id（v3 的名字） | 新 id（新名字） | 说明 |
|---|---|---|
| `flv:0:avc`（FLV 原始线路 · AVC） | `source`（原画） | 源流是 H.265 的房间没有 `source`，只有 `source:hevc`（原画 · H.265）；存下的 `flv:0:avc` 在这种房间里对不上，照常按默认画质选 |
| `hls:0:avc`（HLS 原始线路 · AVC） | `source`（原画） | v3 只在兜底时出现 |
| `flv:<高度>:avc`（FLV <高度>P · AVC） | `<高度>p`（<高度>p） | 录到的高度：1080、720、540、480 |
| `hls:<高度>:avc`（HLS <高度>P · AVC） | `<高度>p`（<高度>p） | 同上 |
| 其他 | 不变 | 新的 id：`source`、`<高度>p`、`source:hevc`、`<高度>p:hevc`、`replay`、`replay:<键>`、`replay:<键>:hevc` |

- 代码：`BaiduLiveApi.legacyQualityIds`（录到的高度的常量表）、`BaiduLiveApi.qualityIdFromLegacy(id)`（任何高度：去掉首尾空白、不分大小写，`<flv|hls>:<高度>:avc` 换成新 id，表外的 id 原样返回，重复调用不变）。取流（`resolvePlayUrlsRaw`、恢复取流）直接接受旧 id，给出新档的全部线路，确认的画质报新 id，所以漏迁的也能播。
- 两个旧 id（同一分辨率的 FLV 和 HLS）变成同一个新 id；旧 id 是 HLS 的，如果要保留“先播 HLS”的意思，可以把这一档里 `format` 是 HLS 的线路排到前面（G 决定）。
- 3.x 的全局画质偏好按名字存（原画、蓝光 8M、蓝光 4M、超清、流畅），v3 的百度画质名都不在其中；改名后全局偏好“原画”能直接对上。这张表给 v4 按房间存下的画质用。百度的房间号是一场直播，按房间存下的画质只在同一场里有用。

### 设置项

| 设置 | 默认 | 含义 | 适配器怎么收 | 留给 |
|---|---|---|---|---|
| `preferH264`（“优先 H.264”，统一原则的全局设置，与 8-8、14-5、22-3、33-2 共用） | 开 | 开：H.264 画质全部在前，编码不知道的其次，H.265 最后（名字带“ · H.265”），默认播 H.264；关：按档位排，最好的档在前，同档 H.264 在前 | `BaiduLiveSite(http, preferH264: () => 设置值)`，每次取画质时读，改了不用重建适配器；`BaiduLiveApi.qualities(room, preferH264: …)`、`BaiduLiveApi.ordered` | J02.1 存储；M13 设置界面；G 评估默认值 |

注意（给 G，同 TikTok、映客）：v3 选默认画质时先按名字匹配偏好，匹配不上按比例落到列表的某一档。“优先 H.264”开着时，应只在 H.264 的档里按比例选（线路的 `codec` 是 `hevc` 或空的跳过）。

### 身份迁移规则（给 J02.1）

无：房间身份仍是房间号（v3 起就是），没有旧 id → 新 id 的规则，也没有大小写不同的重复关注。30-8 只是多认了 http 链接，得到的房间号相同。

数据清理建议（J02.1，可选）：3.x 在没有名字时存下了 `Baidu Live`，改完以后刷新不会再写，但也不会自己清掉。迁移 `baidulive` 的关注时，`nick`、`title` 等于 `Baidu Live` 的可以清空（界面显示平台名，下次看到这场的卡片或进房时补上）。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（测试里的常量 `_changed`、`_changedLive`、`_changedEnded` 的注释写明了编号），新键另外断言：

- 所有房间：`notice`（30-10），以及 E02.11 起就有的 `httpHeaders`（E02.11 差异 1）。
- S01 推荐两页、购物频道：卡片的其他字段、顺序、有下一页都与 v3 相同；新键 `restriction: none`（卡片都有 `has_pay_service: 0`）。
- S02 在播：`introduction`（30-7）；新键 `startedAt`（2026-09-16 15:59:58 UTC）、`restriction: none`。画质（30-1）：v3 的 `hls:720:avc`、`flv:0:avc` 换成 `720p`、`source` 以后，这两档最前面的线路就是 v3 的地址（`flv-live` 改为 http，30-9）；另多了 480p 和各档的备用线路。解析结果的 `variants` 另行对照，其余字段相同。
- S02 已结束：`liveStatus` 1 → 2、`isRecord` false → true（30-4）；新键 `restriction: none`。v3 取画质是空列表，现在是“标清”“720p · H.265”两档回放。
- S02 不存在：没有变化。
- 26 个链接向量：`http://live.baidu.com/m/room/11560887291` 从不认变为认（30-8），其余相同。10 个媒体地址向量：`flv-live` 的 https 变为 http（30-9），两个 `lss-user` 的地址从不收变为收（30-1），其余相同。
- S02 同一页再请求：v3 为空、没有下一页，现在重放上次的结果（30-6）。
- 付费、封禁、预告房间、回放录像、H.265、清晰度列表：v3 的输出里没有（或只有 v3 失败的），用新样本和合成数据测试。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 30-3 百度弹幕（HLS 轮询的消息列表），协议见归档规格 §7。房间命令里有 `chat_msg_hls_url`、`host_msg_hls_url`、`reliable_msg_hls_url`（`liveshowstatic.baidu.com` 上的 m3u8，带 BCE 签名 `authorization`）、`msg_hls_pull_internal_in_second`（5 秒）、`chat_mcast_id` 等。平台层没有加弹幕参数类，`getDanmaku()` 仍是空的；D01 做时从房间命令读这几个字段，在平台层加参数类 |
| G | 30-1：每档多条线路，前面的打不开换下一条；`hls-live.bdstatic.com` 的 FLV 必须带线路的 `Referer`（否则 403）；`lss-user` 是 http，`flv2`、`hls2` 在本机解析不到。30-2：H.265 的硬解在高通真机上验证后再评估“优先 H.264”的默认值；有清晰度列表的房间“原画”的 `codec` 为空，可能是 H.265；默认档见上面的注意。30-4：回放是点播 HLS（带 `#EXT-X-ENDLIST`，S02-room-ended 那场约 10 小时），可以拖动、播完就结束，不能当断流反复恢复 |
| H01.1 | 回放房间的 `getRoomDetailForRecording` 照常返回（带录像），录制只在直播中（`isLiveNow`）进行；受限的直播录制时取流报 `StreamUnavailable` |
| J02.1 | 30-1 画质 id 按上表迁移；`preferH264` 的存储；按 E05.2 存 `startedAt`、`restriction`；可选的 `Baidu Live` 清理 |
| M13 | 30-2 “优先 H.264”的设置界面，画质名“原画”“<高度>p”“ · H.265”“回放”进多语言（v3 的 `baidulive_quality_resolution`、`baidulive_quality_source` 不再用）。30-4、30-5：卡片按 `restriction` 标“付费”“不可播放”，发现页默认隐藏；回放在关注的回放分组，不可播放的回放归入未开播；回放按点播显示进度条。30-7 房间页显示简介。30-10：名字为空时显示平台名（`displayNick`）；公告 `baidulive_chat_notice`、`baidulive_restricted_notice` 和目录说明 `baidulive_directory_scope` 按上面的新文字翻译，英文建议：“Chat from Baidu Live rooms is not shown here yet. The count is the number of people watching now; the streamer's followers are shown separately.”、“This broadcast is paid or restricted by the platform and cannot be played here.”、“Recommendations and channels from the Baidu Live website; scroll for more. Search takes a room number or a Baidu Live room or share link, not a streamer's name.”。开播时间只在直播中显示 |

### 受阻和未核实

没有受阻的条目（30-3 属于 D01，不在本任务）。没有核实的：

- **开播时间**：`create_time` 是开播时刻，预告房间开播时也会更新（见上面的依据，11586395672 实测）。一个房间下播后再开播（`status` 2 再回到 0）时它会不会更新没有见到（60 个在播房间里有 24 小时不停的，最早的 08-19 开播）。
- **付费、封禁的真实样本**：实测 70 张卡片、64 个房间命令的 `has_pay_service`、`is_forbidden_url`、`ban_status` 都是 0，用合成数据测试。付费直播是否照样给地址没有试，受限的一律不播、取流报原因。
- **清晰度列表里的 `hevc_flv`**：E02.11 时（2026-09-28）见过，这次 3 个有清晰度列表的房间都只有 `avc_flv`、`flv`（两者相同）和空的 `asr`，用合成数据测试。
- **`flv_avc_high`**（`-enhance-LV1080`，H.264）：源流是 H.265 或有清晰度列表的房间才有，平台没写它的分辨率，没有用。以后要加，可以作 1080p 档的线路。
- **`flv2`、`hls2`**：本机解析不到，仍作备用线路（平台给的，别的网络可能能用）；E02.11 记的“有的房间 480p 是 404”这次没有遇到。
- **回放录像的其他主机、多个回放条目**：只见过 `p2.bdstatic.com`、每场一个条目（`replay_list_whole`、`replay_list_clips` 与 `replay_list` 相同）。录像在别的主机上时标 `unplayable`（不会报错）。

### 新样本

2026-09-28 21:02 UTC 直连录制，匿名、只读，请求头是 v3 的 `apiHeaders`，设备号是已有样本的 `pc-purelivefixturedevice01`，请求照 v3 的写法（表单、`data` 的字段顺序）；`raw` 记原始回答的 SHA-256 和长度。v3 对它们没有冻结输出（v3 不认预告房间、不分 H.265、不播回放），不带 `expected.json`。

| 样本 | 内容 |
|---|---|
| `S01-feed-news-p1` | 新闻频道推荐流第 1 页：6 场直播（含两个有清晰度列表的房间）、1 张已结束卡片（11562145409，`play_url` 是回放录像）、3 张预告卡片 |
| `S02-room-clarity` | 11586212983（长江新闻号）：有清晰度列表（1080、720、540），`url_list` 是 `-L1`/`-L2`，源流是 H.264（实测） |
| `S02-room-clarity-hevc` | 11585517323：有清晰度列表，源流是 H.265（实测），清晰度列表的 720 就是 `url_list` 的 `-L3` |
| `S02-room-hevc` | 11586291324：没有清晰度列表，源流是 H.265（实测），`avc_url`、`live_flv_url` 指向 720p 的转码，有 `hevc_url` |
| `S02-room-preview` | 11586142356：预告（`status` -1），没有 `error_code`、`template` 是 `preview`，字段在顶层 |

脱敏，按归档录制工具的百度规则（`tools/live_cli/lib/src/fixture/rules/baidulive.dart`），记在各自 `meta.json` 的 `scrubbed`：

- 三个在播房间的 `online_user_list`（每个 10 名观众）：`uid` 换成随机 10 位数，`name`、`nick_name` 换成“观众N”，`avatar` 换成同形的随机字母；
- 聊天列表地址（`video.msg_hls_url`、`chat_msg_hls_url`、`host_msg_hls_url`、`reliable_msg_hls_url`）的 BCE 签名 `authorization`：换成同形的随机值；
- 四个房间命令的响应头 `x-bfe-svbbrers`（Base64 的出口 IP）：换成 `203.0.113.7` 的 Base64 `MjAzLjAuMTEzLjc=`（同已有样本），记为 `header:x-bfe-svbbrers`。

另外查过：请求没有 Cookie；`set-cookie` 只有 `MBD_AT=0`（常量，已有样本同样保留）；推荐流的回答没有观众和访客信息；`tracecode`、`logid`、`nid` 是请求和场次的公开编号；主播的 `uk`、名字、头像、`pa_uid` 是公开信息（归档规则同样保留）。门禁的 `fixture privacy` 通过。

### 新增的通用能力

无。

### 测试

本平台 78 个用例（E02.11 是 58 个；新增 20 个，另改写了受影响的对照用例），`live_core` 共 3450 个，全部通过，门禁 `--all` 通过，`tools/timeshift/run.sh 30 1825` 的 `live_core` 全部 ok（本平台的地址没有租期，开播时间只和固定值比较，测试不看真实时钟）：

- `baidulive_api_test.dart`（39 个）：
  - 对照：推荐两页和购物频道的解析与卡片、三个房间命令的解析和三种详情、签名（含新闻频道样本），改变的键用 `changed:` 列出并写编号；v3 的每个画质经 `qualityIdFromLegacy` 对上一档，那一档最前面的线路就是 v3 的地址；v3 的 26 个链接向量、10 个媒体地址向量，变了的逐个写明；
  - 30-1：S02 在播的三档和每条线路、排序、线路编号、请求头；v3 的主机都没有地址时每一档仍能从平台现在的 CDN 播；媒体地址规则（主机、协议、端口、流名）；
  - 30-2：S02-room-clarity 的五档和线路（原画编码不知道）、S02-room-clarity-hevc、S02-room-hevc（原画 · H.265、`hevc_url`、旧 id 对不上），`hevc_flv` 单列一档，“优先 H.264”开和关两种顺序；旧 id 对照表；
  - 30-4：S02-room-ended 的两档回放和线路；回放条目的清晰度、`video` 兜底、`video_hevc`、坏地址、没有录像时 `unplayable`；录像地址规则；卡片的回放；
  - 30-5：付费、禁止播放、封禁是直播中并标出、取流说明原因；未开播的付费不填；
  - 30-7、30-10、统一原则：简介、没有名字时为空、`displayNick`、新的公告；`create_time` 和各种坏值；卡片的受限类型；预告房间（S02-room-preview）；新闻频道（S01-feed-news-p1）的回放卡片和预告卡片。
- `baidulive_site_test.dart`（39 个）：
  - 30-6：推荐和“推荐”分区各用一个会话（请求的会话号和序号）、同一页再请求重放、会话结束后也重放、第 1 页总是新会话；
  - 30-8：http 链接搜索、进房、经 `LinkParser` 识别；
  - 30-5：开播状态对受限的直播为在播；受限的直播进房、取流说明原因，不多发请求；
  - 30-1、30-2：进房后三档不发请求，v3 的旧 id 取流、恢复取流，线路的请求头；“优先 H.264”每次读、默认开；S02-room-clarity 进房一个请求、1080p 在前；
  - 30-4：回放进房、取流、列表卡片 1 个请求、恢复 1 个请求；
  - 30-10：刷新的回答没有名字时，合并后关注保留存下的名字；
  - 预告房间进房、开播状态、搜索，取流不请求；新闻频道的请求和卡片；
  - 其余照 E02.11，房间对照改用 `changed:`。

## 后续（D01 弹幕）

本平台的聊天（弹幕）已由 D01.27 完成，见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 E 当时的情况，不再改动。
