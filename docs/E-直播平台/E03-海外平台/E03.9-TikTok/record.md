# E03.9 TikTok

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/tiktok/`（`tiktok_api.dart` 纯解析和链接规则，`tiktok_site.dart` 请求编排）
- 样本：`fixtures/tiktok`，4 个真实接口录制，来自归档（2026-09-27，经代理，匿名）：
  - 用户的直播 `api-live/user/room`：在播 `S01-user-live`（`@qvc`）、未开播 `S01-user-offline`（`@cnn`）、不存在 `S01-user-missing`（`@nasa`）；
  - 直播间号换主播 `webcast/room/info`：`S02-room-live`（`@qvc` 这一场）。
  - 媒体地址的 `sign`、图片的 `x-signature` 已由归档脱敏（`meta.json` 的 `scrubbed`）。归档没有 TikTok 的弹幕样本（v3 和归档 v4 都没有 TikTok 弹幕），所以没有 `danmaku` 目录。
- 参考：
  - 归档 v4 的 TikTok 适配器和规格（`spec/sites/tiktok.md`；没有回归条目，§10 有两条“踩过的坑”）；
  - pure_live_TV `e1cca224`：`lib/platforms/tiktok/` 与 v3 逐行相同，只是改了导入路径、人数和粉丝缺值写空串（对照笔记 `small_diffs.txt`、`sub_B.md` 的 tiktok 一节），没有行为修复。`sub_B.md` 建议“v4 补读 `hevcStreamData`”指的是归档 v4，v3 本来就读，这里照 v3。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变。v3 实现过的可选能力全部保留：目录分页（`LiveSiteDirectoryPager`）、目录范围说明（`LiveDirectoryNotice`，文字键 `tiktok_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、取流（`LivePlayUrlResolver`）、恢复时重新取流（`LivePlayRecoveryResolver`），另加 `LiveSiteLinks`。显示名仍是 v3 的“TikTok LIVE”。
- **仅链接，照 v3**：TikTok 没有匿名目录和搜索（归档规格 §0 逐个实测：`webcast/feed` 空正文、`api/live/discover` 要 X-Bogus 签名、`api/search/live` 要登录），v3 的目录永远为空并常驻显示范围说明，搜索只做精确查找。这里相同。
- **请求照 v3**：两个匿名 GET，以 `tiktok` 的名义发出（代理路由由应用按平台注入），不跟随跳转，20 秒期限，不带 Cookie：
  - 用户的直播 `https://www.tiktok.com/api-live/user/room/?aid=1988&sourceType=54&staleTime=600000&uniqueId=<用户名>`，请求头是 v3 的 Chrome 140 UA、`Accept`、`Accept-Language: en-US`、`Origin`、`Referer: https://www.tiktok.com/@<用户名>/live`；
  - 直播间号换主播 `https://webcast.tiktok.com/webcast/room/info/?aid=1988&room_id=<直播间号>`，`Referer: https://www.tiktok.com/live`。
- **请求次数与 v3 相同**：

  | 场景 | 请求 | 次数 |
  |---|---|---|
  | 关注刷新、开播状态 | `user/room`（不读取流） | 1 |
  | 进房、录制详情 | `user/room`（读取流） | 1 |
  | 播放（进房后） | 无，用进房时的流 | 0 |
  | 恢复取流 | `user/room` | 1 |
  | 搜索：用户名、`@用户名`、主页或直播页链接 | `user/room` | 1 |
  | 搜索：`share/live/<直播间号>` 链接 | `room/info`、`user/room` | 2 |
  | 链接导入：主页、直播页 / `share/live` / 短链 | 无 / `room/info` / 读一次跳转 | 0 / 1 / 1 |

- **房间身份与 v3 一致**：房间号是小写的用户名（`uniqueId`），v3 的详情把请求的号码去空白、转小写后作为 `roomId`（S:82-87、S:56），样本对照里所有 `roomId` 都与 `expected.json` 一致。数字直播间号（`user.roomId`）每场都变，只用于 `share/live` 链接和以后的弹幕，放进 `TikTokRoomData.liveRoomId`；账号 id `user.id` 是房间的 `userId`（v3 相同）。
- **卡片照 v3**：昵称；标题（为空时用昵称，未开播时是上一场的标题）；头像 `avatarLarger`、封面 `coverUrl`（只收可信主机的 https 图片）；简介 `signature`；粉丝数；分区固定为“TikTok LIVE”；只在直播时有人数：`userCount` 是在线（同时写进 `watching`），`enterCount` 是累计进房，口径 `onlineViewers`；公告是 v3 `tiktok_chat_notice` 的文字（“TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。”）。
- **状态照 v3**：`liveRoom.status`（没有时用 `user.status`）2 是直播，4 是未开播，其他是“未知”；私密账号（`user.secret`）、订阅者专享（`liveSubOnly` 为 1）、付费直播（`paidEvent.paid_type` 大于 0）按 v3 显示为“封禁”（`LiveStatus.banned`），原因记在 `TikTokRoomData.restriction`。
- **严格校验照 v3**：`statusCode` 19881007（或消息里有 not exist、not_found）是 `NotFound`，其他非 0 码是 `ApiChanged`；回答必须是请求的用户（`uniqueId`，大小写不论）；昵称、账号 id、直播间号、流 id、人数、粉丝数、`secret`、`verified`、`paidEvent` 等字段按 v3 逐项检查，不合格整个回答 `ApiChanged`，不给残缺的房间。
- **流照 v3**（A:296-360）：只在进房和录制时、且直播中未受限时读。`streamData`（默认 H.264）和 `hevcStreamData`（默认 H.265）都读；`pull_data.stream_data` 和 `sdk_params` 都是字符串里的 JSON，两层解码；每档（`hd`、`origin`、`uhd_60` 等，最多 32 档）每种协议（FLV、HLS）是一个画质，编码以 `sdk_params.VCodec`（或 `v_codec`）为准，同编码、同档、同协议的合并，每个地址只留一次，只有声音的 `ao` 不要。媒体地址必须是可信主机上的 https，不带用户名、片段、空白，否则整个回答 `ApiChanged`。
- **画质照 v3**：名称 `<档位> · <分辨率> · <编码> · <协议>`，如“原始画质 · 1080x1920 · H264 · FLV”，档位名用 3.x `tiktok_quality_*` 的中文，不认识的档位显示大写键名；id 是 `h264:origin:flv`；排序值是档位（原画 10000 …… 自动 3000，其他 1000）加 H.264 100、FLV 20 或 HLS 10，从高到低。样本里有 14 个画质，第一个是 `hevcStreamData` 里的 H.264 原画。
- **线路**：一个画质通常一个地址，一条线路，带 v3 播放层发的媒体请求头（UA、`Origin`、`Referer: https://www.tiktok.com/@<用户名>/live`，即 v3 `TikTokApi.mediaHeaders`）、格式（按协议）、编码（`avc`、`hevc`）、线路编号（CDN 主机名）和租期：地址的 `expire` 是过期时刻（签发后约 14 天），到期前 1 小时（不超过寿命的四分之一）续期，过期不断开已建立的连接。`appliedQualityData` 是请求的画质 id（v3）。
- **不能播放时在取流时报错**：受限报 `NeedsLogin`；未开播、状态未知、直播中却没有流报 `StreamUnavailable`；画质不在报 `StreamUnavailable`。房间已知不能播（卡片是未开播或封禁、进房数据说不能播）时，取画质和取流都不发请求。没有进房数据的房间（关注卡片、搜索结果）取流前先进房一次。
- **链接**：`TikTokLink` 照 v3 的规则。
  - 主页 `/@<用户名>`、直播页 `/@<用户名>/live`（主机 `tiktok.com`、`www.tiktok.com`、`m.tiktok.com`，http 或 https，不带用户名和片段）直接得到房间，不发请求；视频页不是房间；
  - `share/live/<15～25 位直播间号>` 经 `room/info` 找主播（`needsResolving`、`resolveUrl`，经 `ShortLinkSession` 请求）；
  - 短链 `vm.tiktok.com/<码>`、`vt.tiktok.com/<码>`（v3）和 `www.tiktok.com/t/<码>`（见差异 7）读一次跳转，不跟随，目标交给 `LinkParser` 再解析（可以是任何平台，v3 相同）；
  - 搜索框另认用户名，带不带 `@` 都行（v3 的 `parseOrUsername`）。
- **没有 Cookie、登录和弹幕**：v3 的 TikTok 全部匿名，弹幕是 `EmptyDanmaku`，设置里也没有 TikTok 的 Cookie，所以不注入 `CookieVault`，也没有弹幕参数类。网页评论（`webcast/im/fetch` 和 WebSocket）要 X-Bogus 签名和 `msToken`（归档规格 §7），以后要做时，直播间号已在 `TikTokRoomData.liveRoomId`。

## 审查发现的 v3 问题

位置简写：`A` = `legacy/lib/core/site/tiktok/tiktok_api.dart`，`S` = `tiktok_site.dart`，`L` = `tiktok_link.dart`，`lut` = `legacy/lib/common/utils/live_url_tool.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 美区 CDN 的直播进不去、录不了：样本 `@qvc` 的拉流地址和图片都在 `*.tiktokcdn-us.com`，v3 进房和录制都报 `schema`（整个房间打不开），关注刷新能成功但头像、封面都是空的 | A:473-501（`_image`、`_mediaUri`、`_trustedHost`） | 可信主机表只有 `tiktokcdn.com`、`tiktokv.com`、`byteoversea.com`，没有地区 CDN 的域名 | 加上 `tiktokcdn-us.com`、`tiktokcdn-eu.com`（各含子域名）；https、无用户名、无片段、无空白等其他规则不变 |
| 2 | 直播中但没有可用的流时，进房整个失败，看不到房间信息 | S:89-95 | 进房的详情里顺带判断“能不能播” | 进房照常给房间，取画质、取流报 `StreamUnavailable`；录制详情照 v3 直接报错 |
| 3 | 未开播、受限的房间取画质返回空列表，播放器拿不到原因 | S:166-169 | 用空列表表示“不能播” | 未开播 `StreamUnavailable`，受限 `NeedsLogin`，都不发请求 |
| 4 | 没有进房数据的房间（关注卡片、搜索结果、历史记录）取画质报 `identity` | S:141-152 | 只认进房时存在房间里的快照 | 先进房（一个请求）再给画质；进房后的房间不再请求 |
| 5 | 错误全是 `TikTokException`：`access` 同时表示 401/403 和空回答，`transport` 同时表示 3xx 和网络失败，播放和录制只能按种类名字判断 | A:11-31、A:174-208、S:109-116、S:141-152、S:183-196 | 平台自己的异常类型 | 类型化错误：401/403 和空回答 `RiskControl`，404 和 19881007 `NotFound`，420/429 `RateLimited`，5xx 和其他状态码 `NetworkFailure`，400、格式和未知业务码 `ApiChanged`；受限 `NeedsLogin`，不能播 `StreamUnavailable` |
| 6 | 不是用户名的房间号报 `identity`；目录的页码和分区报 `schema` | S:41-44、S:82-87 | 调用方的参数错误当成响应错误 | 非用户名 `NotFound`，不发请求；页码 `RangeError`、分区 `ArgumentError`，不发请求 |
| 7 | 编码名 `bytevc1`（字节的 H.265 写法）会让整个房间失败 | A:455-465 | 只认 `avc`、`hevc`、`h264`、`h265` | `bytevc1` 算 H.265（归档 v4 的做法）；其他未知编码仍 `ApiChanged` |
| 8 | 头像、封面只看第一个不为 null 的字段：`avatarLarger` 是空串或不可信时不再看 `avatarMedium`、`avatarThumb` | A:271-272 | `??` 只跳过 null | 取第一个合格的；协议相对地址补 https（通用的 `normalizeImageUrl`） |
| 9 | App 分享的新式短链 `www.tiktok.com/t/<码>` 不认 | L:9-33；lut:264-277 | 短链只认 `vm`、`vt` 两个主机 | 也认（归档 v4 的做法），同样只读一次跳转 |
| 10 | `share/live` 链接导入失败时抛异常，分享文本里后面的链接不再尝试 | lut:229-234；A:283-294 | 平台异常直接穿出解析 | 返回“没有房间”，`LinkParser` 继续看后面的链接；3.x 工具箱对两种情况都提示“解析失败”，用户看到的一样 |
| 11 | 媒体请求头按平台写在播放层；v3 又把它写进房间的 `httpHeaders`，而那个字段只有 IPTV 读 | phr:183-185、phr:143-147；S:77 | 地址和请求头分开放（诊断报告里的“旁路”） | 线路自带请求头；房间不再写 `httpHeaders` |
| 12 | 平台层调用界面翻译（公告、画质名；站点名在 `sites.dart:244`） | S:76、S:154-164 | `i18n` 写在适配器里 | 用 3.x `zh.json` 的中文作默认文字，界面按键翻译（M13） |
| 13 | 平台层依赖全局 `HttpClient`，自己读响应体、计时；12 MiB 上限读的时候按字节查一次，解析前又按字符数查一次 | A:125-172、A:202 | 结构问题 | 注入 `LiveHttp`，20 秒期限由请求超时负责；上限只在解析前按 UTF-8 字节查一次 |
| 14 | 受限直播（私密账号、订阅者专享、付费）显示为“封禁”，进房提示“服务器错误,请稍后获取”，录制按封禁停止 | A:249-259；S:66-71；`live_play_controller.dart:789`、`stream_resolver_service.dart:148` | 借用 `banned` 表示“需要权限” | 按 v3 保留（状态和分组不改）；取流报 `NeedsLogin` |
| 15 | 同一档的 FLV 和 HLS 是两个画质，一个失败时另一个不作为备用线路 | S:166-181；A:316-335 | 每个协议算一个画质 | 按 v3 保留（画质名称和列表不变） |
| 16 | 最好的一档是 H.265 时它排在 H.264 之前成为默认（先比档位，同档才比编码） | A:362-377 | 档位优先 | 按 v3 保留；样本里的原画是 H.264，不受影响 |
| 17 | 搜索框里粘贴短链搜不到 | S:130；L:35-41 | 搜索只认主页、直播页和 `share/live` | 按 v3 保留 |
| 18 | 用不到的字段（`verified`、`secUid`、`signature`、`streamId`）形状不对，整个房间打不开 | A:410-447 | 严格校验 | 按 v3 保留 |

## 样本与 v3 的冻结输出

归档没有 TikTok 的 `expected.json`：归档的旧版对照工具只做了前五个平台，v3 应用现在也构建不了。本模块用 `fixtures/tiktok/legacy_expected.dart` 生成：

- 把 v3 的 `TikTokApi`、`TikTokLink`、`TikTokSite`，3.x `LiveRoom` 用到的 `HttpHeaderPolicy.normalize`，以及 `LiveUrlTool._parseLiveUrl`（lut:229-234）和 `WebSearchRoomParser.parse`（web_search_room_parser.dart:98-99）里 TikTok 的那一步，原样搬进一个纯 Dart 脚本。v3 本来就把传输做成可注入的函数（`TikTokRequest`），所以只换了它：按主机、路径和查询读样本；状态码不是 200 时正文为空（同 v3）；没有样本的请求记下来并让脚本失败，`_json` 原样抛出这个 `StateError`（v3 代码里唯一的改动），不会被记成 v3 的“传输失败”。只在网络路径上用到的 `_defaultRequest`、`readBody` 没有搬。
- `i18n` 换成用到的九个键的中文（`zh.json`）；基类声明、`@override` 和弹幕 getter 去掉；Dio 的 `CancelToken`、`DioException` 和 v3 的 `LiveRoom` 等只搬用到的部分（3.x 的 `toJson` 写原始的 `isRecord` 和规范化后的 `httpHeaders`）。
- **可信主机的对照**：样本的流和图片都在 `tiktokcdn-us.com`，v3 不收（问题 1），它的画质和地址本来无从对照。所以对 `S01-user-live`、`S01-user-offline` 另记一份 `trustedHosts`：同样的调用，只把回答里的 `tiktokcdn-us.com` 写成 v3 信任的 `tiktokcdn.com`，别的不改。
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个调用还记下了它发出的请求。
- 重新生成：在仓库根目录运行 `dart run fixtures/tiktok/legacy_expected.dart`。

4 个样本都有 `expected.json`：

- `S01-*`：三种深度（刷新另用大写和带 `@` 的号码各一次）、开播状态、7 种搜索输入和第 2 页、目录两页、推荐、画质、每个画质的地址和取流、恢复、没有进房数据的卡片取画质，21 种输入的链接规则（`parse`、`parseOrUsername`、`parseDurableUsername`、`normalizeUsername`、`WebSearchRoomParser`）和 `TikTokLink.url`；
- `S02-room-live`（同时读 `S01-user-live`）：`resolveReference`、用 `share/live` 链接搜索、分享文本导入。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序值；地址、请求逐字比较。

| 样本 | 结果 |
|---|---|
| S01-user-live 刷新、搜索（`qvc`、`@qvc`、`QVC`、直播页链接） | 一致，房间号都是 `qvc`，每个 1 个请求；只有头像、封面：v3 不收 `tiktokcdn-us.com`，是空的，现在有图 |
| S01-user-live 进房、录制 | v3 报 `schema`（问题 1）；现在给出房间和 14 个画质。与 `trustedHosts` 的 v3 输出比较：房间除头像、封面的主机外一致 |
| S01-user-live 画质和地址（`trustedHosts`） | 14 个画质的名称、id、排序值、顺序全部一致；每个画质的地址一致（主机按录制写回 `tiktokcdn-us.com`），`appliedQualityData` 一致；取流不发请求，恢复 1 个请求，与 v3 相同 |
| S01-user-live 开播状态 | `true`，一致 |
| S01-user-offline | 三种深度、搜索、开播状态（`false`）一致，只有头像、封面同上；`trustedHosts` 下完全一致。v3 取画质是空列表、取流是 `mediaUnavailable`，现在都是 `StreamUnavailable`，不发请求 |
| S01-user-missing | v3 三种深度和开播状态都是 `missing`，现在是 `NotFound`；四种搜索都是空结果、1 个请求，一致 |
| S02-room-live | 直播间号换到 `qvc`，1 个请求，一致；用 `share/live` 链接搜索，2 个请求和卡片一致（头像、封面同上）；分享文本导入得到 `qvc`，1 个请求，一致 |
| 链接规则 | 21 种输入的 `parse`、`lookup`（`parseOrUsername`）、用户名规范化、主页和直播页识别全部一致 |
| 目录、推荐 | 都是空的，不发请求，一致 |
| 请求 | 地址逐字相同；请求头与 v3 相同（名称小写） |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 美区、欧区 CDN（`tiktokcdn-us.com`、`tiktokcdn-eu.com`）的流和图片可信 | 问题 1。这类房间现在能进、能播、能录，关注卡片有头像和封面 |
| 2 | 直播中但没有流：进房给出房间，播放报 `StreamUnavailable`（录制详情照 v3 报错） | 问题 2 |
| 3 | 出错抛类型化错误；不能播时取画质、取流报原因，不发请求 | 问题 3、5、6。界面看到的仍是加载失败或“无法播放”（M13 用 `pendingAfterError`），状态和分组不变 |
| 4 | 没有进房数据的房间取流前先进房一次 | 问题 4。只在播放路径上多一个请求，v3 这里直接失败 |
| 5 | `bytevc1` 算 H.265 | 问题 7 |
| 6 | 头像、封面取第一个合格的字段 | 问题 8。样本结果与 v3 相同（`trustedHosts` 下） |
| 7 | 认 `www.tiktok.com/t/<码>` 短链；短链请求带 v3 的 Chrome UA（v3 的短链会话发的是 Dart 默认 UA） | 问题 9。跳转的真实形状没有样本（归档规格 §12 第 3 条），用合成回答覆盖 |
| 8 | `share/live` 链接导入失败时是“没有房间”，不抛错 | 问题 10 |
| 9 | 线路自带请求头、格式、编码、线路编号和租期；房间 JSON 里不再有 `httpHeaders` | 问题 11。请求头与 v3 播放层实际发的逐项相同；3.x 存下的关注里的旧值由 `mergeFrom` 保留（非 IPTV 不覆盖），不影响播放 |
| 10 | 12 MiB 上限在下载完后判定，非法 UTF-8 变成替换字符而不是报错；路径解码失败的链接不认（v3 抛 FormatException） | 传输统一由 `live_net` 负责（同 Picarto、微博） |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **显示名仍是“TikTok LIVE”**。归档 v4 叫“TikTok”。
- **受限直播仍显示为“封禁”**（问题 14）。归档 v4 照常显示状态、取流时报 `NeedsLogin`，也不把私密账号算作受限。
- **未知状态显示为“未知”**。归档 v4 报 `ApiChanged`，房间打不开。
- **两个容器都读，画质照 v3**（问题 15、16）：归档 v4 只读 `streamData`，样本里只能给 720p；名称用平台的 `options.qualities[].name`（`720p`），每档 FLV、HLS 两条线路。这些都会改变画质名称和列表。
- **进房时就读流，播放用进房的数据，恢复才重新请求**。归档 v4 每次取流都重新请求。
- **关注刷新不读流**：流的格式问题不影响刷新（v3）。归档 v4 每次都解析。
- **保留搜索，认不带 `@` 的用户名**。归档 v4 去掉了搜索，只认 `@用户名`（担心与别的平台冲突；搜索是按平台进行的，不会冲突）。
- **保留空目录和目录范围说明**。归档 v4 没有目录能力。
- **严格校验照 v3**（问题 18）。归档 v4 只看用到的字段，缺了就用默认值。
- **短链的跳转目标交给所有平台解析**（v3）。归档 v4 要求目标还在 tiktok.com。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 受限直播标为“直播中”，播放时说明需要关注、订阅或付费 | 显示“封禁”，进房提示“服务器错误,请稍后获取”，录制按封禁停止 | 问题 14；归档 v4 的做法 |
| 2 | 同一档的 FLV、HLS 合成一个画质的两条线路，互为备用 | 两个画质，没有备用线路 | 问题 15 |
| 3 | 默认画质优先 H.264，HEVC 档只供手动选择 | 按档位排序，最好的档是 H.265 时它是默认 | 问题 16；上游对照笔记 `sub_B.md` 第 1 条（HEVC 走 FLV 的硬解未验证，REG-PLAY-022），由 G 决定 |
| 4 | 画质名称用平台给的 `options.qualities[].name`（`720p`、`1080p60`） | 中文档位名加分辨率、编码、协议 | 归档 v4 |
| 5 | 搜索框里的短链跟随跳转后查找 | 没有结果 | 问题 17；链接导入已经能做 |
| 6 | 用不到的字段放宽校验 | 整个房间失败 | 问题 18；归档 v4 |
| 7 | TikTok 评论弹幕 | 没有 | 需要 X-Bogus 签名和 `msToken`（归档规格 §7），直播间号已在 `TikTokRoomData.liveRoomId` |
| 8 | 推荐或分区目录 | 空，只有说明 | 需要签名或登录（归档规格 §0 实测） |

## 回归条目的覆盖

归档规格没有 TikTok 的回归条目（REG-TIKTOK-…）。§10 “踩过的坑”两条都有测试：

- 没有匿名目录：目录、推荐永远为空，不发请求（与 v3 相同）。
- `stream_data`、`sdk_params` 是字符串里的 JSON：两层解码，样本 S01 的 14 个画质逐个对照；坏的内层 JSON 报 `ApiChanged`。

规格 §12 “待确认”里与平台层有关的几项：`status` 的其他取值按 v3 算“未知”（合成回答）；其他档位和 HEVC 线路由样本 S01 的 `hevcStreamData` 覆盖（`origin`、`uhd_60`、`hd_60`、`hd`、`sd`、`ld`，其中 `origin` 是 H.264）；短链的跳转没有真实样本，用合成回答覆盖（绝对和相对 `Location`、跳到 `share/live`、跳到视频、404）。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕：v3 没有（`EmptyDanmaku`），匿名评论要签名 | D01（无需实现；直播间号在 `TikTokRoomData.liveRoomId`） |
| `getDanmaku()` | 同 E01.1：D01 用一张“平台 → 弹幕连接”的表 |
| 站点名、公告、画质名的多语言（`site_tiktok`、`tiktok_chat_notice`、`tiktok_quality_*`）。公告会随刷新写进关注，界面要按当前语言显示，不直接显示存下的中文 | M13 |
| 目录范围说明 `tiktok_directory_scope`（v3 在目录页上方常驻显示） | M13 目录页 |
| 搜索能力：精确账号查找、不翻页、没有网页搜索（`search_capability.dart:59-63`） | M13 搜索页 |
| 打开官网：`TikTokApi.externalRoomUrl`（v3 `room_external_opener.dart:103-108`，只用房间号拼直播页） | M13 |
| 按错误类型提示：受限是 `NeedsLogin`，但没有 TikTok 登录，应说明需要关注、订阅或付费，不引导登录 | M13 直播间 |
| 人数口径（`userCount` 在线、`enterCount` 累计，v3 `live_room.dart:136-142`） | 已在 E05.1 的 `audience.dart` |
| 本地互动的平台名（`local_interaction_controller.dart:426-427`）；平台图标 `tiktok.png`（`sites.dart:206`） | A01.1、I01.1、M13 |
| 热门平台列表的 v20 迁移把 TikTok 加进去（`favorite_room_controller.dart:76`）；3.x 关注里存下的 TikTok `httpHeaders` 可以在迁移时丢掉 | J02.1 |
| 链接的请求：`share/live` 和短链经 `ShortLinkSession` 以 `links` 的名义发出。TikTok 在中国大陆要走代理，应用的 `ProxyPolicy.routeFor(site, url)` 要按主机把 `tiktok.com` 分给 TikTok 的代理 | J02.1、I01.1 |
| 录制对 `access`、`unknownState`、`mediaUnavailable` 的重试或停止（v3 `StreamResolverService`）；现在是 `NeedsLogin`、`StreamUnavailable`，受限房间的状态仍是封禁 | H01.1 |
| 播放、录制读线路的请求头和租期 | G、H01.1 |
| 响应大小上限（v3 边读边限制 12 MiB） | live_net（Q01.1）没有逐请求的大小上限，同 Picarto |

## 新增的通用能力

没有。只在 `live_core.dart` 里按字母顺序加了两行导出；用到的 `json.dart` 的 `normalizeImageUrl`、`LiveSiteLinks`、`ShortLinkSession`、`LinkParser`（E04.1）都已存在。

## 测试

65 个用例，`live_core` 共 1973 个，全部通过：

- `tiktok_api_test.dart`（37 个）：逐个样本对照 v3 的输出（刷新、进房、录制三种深度，大写号码，在播和未开播，`trustedHosts` 下完全一致），有意的差异逐条断言（地区 CDN、`httpHeaders` 移到线路、未开播的画质、不存在）；14 个画质的名称、id、排序和每个画质的地址；线路的请求头、格式、编码、线路编号和租期；3 个样本各 21 种输入的链接规则、短链、打开官网。合成回答覆盖 v3 `tiktok_api.dart` 的每项检查：三种受限及其先后、`paidEvent` 的各种写法、状态和 `user.status` 兜底、空标题、图片的兜底和主机、23 种字段形状错误、数字 id 和大写用户名、业务码、HTTP 状态、空回答、非 JSON、12 MiB 上限（按字节）、`room/info` 的各种回答；两个容器的合并、`ao`、编码名（含 `bytevc1`）、分辨率、未知档位、媒体地址的主机和格式、12 种坏容器、不读流的情形、直播中没有流。
- `tiktok_site_test.dart`（28 个），用样本回放加少量合成回答：
  - 请求地址、请求头、不跟随跳转、20 秒期限；能力和显示名；传输错误和 HTTP 状态的映射；
  - 目录和推荐为空、不发请求，参数错误；
  - 搜索：3 个样本各 7 种输入的结果和请求与 v3 一致，第 2 页不发请求，`share/live` 链接 2 个请求，不存在的直播间为空，其他错误照抛，取消（请求前、随请求、应答后）；
  - 房间：三种深度各 1 个请求，只有进房和录制带流；号码规范化和非法号码不发请求；3.x 关注经 `mergeFrom` 刷新；不存在；开播状态的四种情况；录制时直播中没有流报错；
  - 取流：进房后取画质和地址不发请求、恢复 1 个请求且与 v3 相同；卡片先进房；未开播和封禁的卡片、刷新后下播的房间不发请求；受限、没有流、未知状态的原因；恢复时下播或画质不在；别的平台的房间；
  - 链接（经 `LinkParser`）：主页和直播页不发请求、`@qvc` 这类文字不算链接，`share/live` 一个请求并与 v3 的导入一致，不存在或失败时没有房间，三种短链（绝对和相对跳转），短链跳到 `share/live`、视频或 404。

## 升级落地（T02.U）

- 日期：2026-09-29（E03.9）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 8 行（22-1～22-8）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。“落地方式”写了的是 22-1（模型部分已完成）、22-3（“优先 H.264”设置）、22-6（开发预填：只在 v3 原本失败的地方生效），其余按上面“后续升级候选”的原文做。
- 22-7（评论弹幕）整条留给 D01，本次不动（平台层需要的直播间号 E03.9 已放在 `TikTokRoomData.liveRoomId`）。22-8 只读地探查过，受阻（见“受阻”）。
- 只改了本平台：`tiktok_api.dart`（解析）、`tiktok_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖，没有新样本（`expected.json` 没有改）。
- 上面“保持 v3 行为”一节里的这几条现在改了：受限直播显示为“封禁”（问题 14）、同一档 FLV 和 HLS 是两个画质（问题 15）、最好的档是 H.265 时它是默认（问题 16）、画质名用中文档位加分辨率（归档 v4 的做法现在采用了，而且两个容器都读）、搜索框里的短链没有结果（问题 17）、用不到的字段严格校验（问题 18）。“做法”里“受限报 `NeedsLogin`”改成按受限类型报 `StreamUnavailable`（带原因）。其余照旧：显示名“TikTok LIVE”、未知状态显示“未知”、进房时读流、关注刷新不读流、空目录和目录说明、请求地址和请求头。
- 实测：2026-09-29（北京时间）经代理只读地请求了 `@qvc` 的 `user/room`：新代码解析出 7 个画质（原画、720p、1080p60 · H.265、720p60 · H.265、720p · H.265、540p · H.265、360p · H.265），与样本 S01 相同；这次回答里每档只有 FLV（`hls` 为空），所以每个画质一条线路。原画、720p（H.264）、720p · H.265 三条 FLV 线路都读到了 FLV 文件头。开播时间、`none` 都填上了。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 22-1 受限直播 | `TikTokState` 去掉 `restricted`：状态只看 `status`（2 直播、4 未开播、其他未知）。受限情况另算（`TikTokApi.restrictionOf`，3.x 的检查顺序）：私密账号 `user.secret` → `private`（仅粉丝可看）；`liveSubOnly` 为 1 → `subscribersOnly`；`paidEvent.paid_type` 大于 0 → `paid`；都不是 → `none`。只在直播中填 `LiveRoom.restriction` 和 `TikTokRoomData.restriction`（关注刷新、搜索卡片、进房、录制都一样；未开播、状态不明留空）。受限的直播状态是 `live`，关注分组在直播中，照常显示在线和累计人数；照 v3 不读它的流。<br>取流时按类型报 `StreamUnavailable`，原因写明谁能看（“a private account's LIVE, for its followers only”“a LIVE for subscribers only”“a paid LIVE”），不再报 `NeedsLogin`（本应用没有 TikTok 登录，登录也没用）。开播状态查询 `getLiveStatus` 对受限直播返回真（v3 假）。录制详情照常返回受限的房间（直播中 + 受限类型；v3 返回“封禁”）。<br>3.x 存下的“封禁”只可能是当时的受限直播，取流时不再直接拒绝，改为先进房一次看现在的状态 | 私密、订阅专属、付费的直播显示为“直播中”，卡片标出受限类型（M13），点进去提示需要关注、订阅或付费（M13 按 `restriction` 显示），不再是“封禁”和“服务器错误,请稍后获取” | 平台层完成，余下 H01.1/M13 |
| 22-2 FLV、HLS 合成一档 | 画质按“编码 + 档位”分，不再按协议：`TikTokStream` 改为 `flvUrls`、`hlsUrls` 两组地址，id 从 `h264:origin:flv` 变成 `h264:origin`。取流时一个画质给出 FLV 线路在前、HLS 在后（互为备用），线路编号 `flv`、`hls`（同一协议第二个地址是 `flv#2`，两个容器给了同编码同档的地址时出现），编码、请求头、租期照旧。旧 id 照样能取流（按对照当作新 id，确认画质报新 id） | 画质菜单从 14 项变成 7 项（样本 S01）；一条线路失败时播放器换另一条（G） | 平台层完成，余下 G/M9 |
| 22-3 优先 H.264 | 新设置 `preferH264`（见“设置项”），适配器每次取画质时读：开（默认）时所有 H.264 画质在前（从好到差），H.265 画质排在后面，默认播 H.264，H.265 只供手动选；关时照 v3 按档位排（最好的档在前，同档 H.264 在前）。H.265 画质的名字带“ · H.265”，已存的“原画”偏好只会对上 H.264 的原画 | 默认播放 H.264；H.265 的档在列表后面、名字带“H.265”，手动选才播。关掉“优先 H.264”后最好的档（可能是 H.265）排第一 | 平台层完成，余下 G/M9/M13 |
| 22-4 画质名 | 名字按顺序取：档位 `origin` 叫“原画”（统一原则；平台叫 `Original`）；否则用这个容器 `pull_data.options.qualities[]` 里 `sdk_key` 对应的 `name`（`720p`、`1080p60`，去空白，最长 32 字）；没有时按平台的规则从分辨率拼（`720x1280` → `720p`，`_60` 档加 `60`）；再没有时用 3.x 的中文档位名（`自动` 等），最后是大写键名。H.265 加“ · H.265”。同名的（例如两档分辨率相同又没有平台名）后面加档位键 | 画质名从“原始画质 · 1080x1920 · H264 · FLV”变成“原画”，从“超清 60 帧 · 1080x1920 · H265 · FLV”变成“1080p60 · H.265”，与 TikTok 网页的叫法一致 | 平台层完成，余下 J02.1 |
| 22-5 搜索框里的短链 | 搜索词是短链（`vm.tiktok.com/<码>`、`vt.tiktok.com/<码>`、`www.tiktok.com/t/<码>`）时，先读它的跳转（`http.open`，不跟随、不读正文，请求头同链接导入的短链：v3 的 Chrome UA，以 `tiktok` 的名义发出）：跳到主页或直播页就查这个用户，跳到 `share/live` 就先查主播；跳到另一个 TikTok 短链就再读一次，总共最多 3 次（`TikTokApi.maxShortLinkHops`），绕回来就停。跳到视频、首页、别的网站，不是跳转（2xx）、400/404/410、跳转没有可用的 `Location`，都是没有结果；401/403 `RiskControl`、420/429 `RateLimited`、其他 `NetworkFailure`（`TikTokApi.shortLinkTarget`），取消照常 | 在 TikTok 的搜索框粘贴 App 分享的短链，能直接搜到这位主播（v3 没有结果） | 完成（T02.U） |
| 22-6 放宽检查 | 只影响名片的字段不再让整个回答失败，形状不对就留空：`verified` 不再读；`nickname`（空白或不是字符串）、`user.id`、`secUid`、`user.roomId`、`streamId`、`title`、`signature`、`stats`、`followerCount`、`liveRoomStats` 和两个人数、`sdk_params.vbitrate`、`resolution`。关系到身份、状态和受限情况的字段照 v3 严格检查：`uniqueId`（必须是请求的用户）、`data`/`user`/`liveRoom` 是对象、`secret` 是布尔、`paidEvent` 是对象（或空）。<br>同时按统一原则“容错”处理流（v3 一处坏就整个房间 `ApiChanged`）：一个坏地址只丢这条线路；一个坏档（键名、`main`、`sdk_params`、编码不对）只丢这一档；一个容器解不开（不是对象、`stream_data` 不是 JSON、超过 32 档）只丢这个容器。丢掉的记在 `TikTokRoomData.skipped`；一个流都没剩下时取流报 `ApiChanged`（说明哪里坏了），本来就没有流时仍是 `StreamUnavailable` | 平时看不出变化；平台某个字段或某条地址出问题时，房间照常打开、其余画质照常播放（v3 整个房间打不开） | 完成（T02.U） |
| 22-7 评论弹幕 | 本次不做，整条留给 D01：网页评论（`webcast/im/fetch` 和 WebSocket）要 X-Bogus 签名和 `msToken`（归档规格 §7）。平台层需要的直播间号（`user.roomId`）已在 `TikTokRoomData.liveRoomId`（E03.9） | 不变 | 未改（整条留给 D01，UPGRADES 的状态仍是“待做”） |
| 22-8 推荐、分区 | 没有做，受阻：匿名能用的目录接口都要签名或登录，见“受阻” | 不变：目录为空，常驻目录说明 | 受阻 |

### 按统一原则补的

| 原则 | 做了什么 |
|---|---|
| 开播时间 | 直播中（包括受限的直播）填 `liveRoom.startTime`（Unix 秒，按 UTC；不是整数、2000 年以前、2100 年以后的不填，`TikTokApi.startTime`）。关注刷新、搜索卡片、进房、录制都有。未开播的回答也带 `startTime`（上一场的），不填 |
| 受限类型 | 见 22-1：直播中填 `none`、`private`、`subscribersOnly`、`paid` 之一；未开播、状态不明留空 |
| 受限的直播改为直播中 | 见 22-1（原来用 `banned`） |
| 占位信息 | 平台没有占位的名字、标题：昵称空白（或形状不对）时留空，界面显示平台名（E05.2 的 `displayNick`），不再让房间打不开；没有标题时用昵称（v3 的做法，是真实的名字）。封面 `coverUrl` 常常就是头像图，是真实图片，照旧 |
| 回放、不可播放 | 不适用：TikTok 的 `user/room` 只有直播和未开播，没有回放 |
| 房间身份 | 不变：用户名，E05.2 已把 `tiktok` 放进不分大小写的平台 |
| 按主播关注 | 本来就是：房间号就是用户名，每场变化的直播间号只在 `TikTokRoomData.liveRoomId` 里 |
| 容错 | 见 22-6 |
| 翻页 | 不适用：没有目录，搜索只有第 1 页 |
| 画质命名、默认编码 | 见 22-2～22-4 |
| 弹幕 | 见 22-7（D01） |
| 说明文字 | 每个房间的公告 `chatNotice`（3.x `tiktok_chat_notice`：“TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。”）改成“TikTok 直播的评论暂时不能在这里显示。在线人数是正在看的人数，累计是进过直播间的人数。”（键不变，M13 做多语言）。目录说明 `tiktok_directory_scope` 的文字在界面里（M13），建议见“留给其他模块” |

### 请求数

| 场景 | E03.9 | 现在 | 原因 |
|---|---|---|---|
| 关注刷新、开播状态 | 1 | 1 | — |
| 进房、录制详情 | 1 | 1 | — |
| 播放（进房后）、切换画质 | 0 | 0 | — |
| 恢复取流 | 1 | 1 | — |
| 搜索：用户名、`@用户名`、主页或直播页链接 / `share/live` 链接 | 1 / 2 | 1 / 2 | — |
| 搜索：短链 | 0（没有结果） | 短链 1～3 次 + 查找 1～2 次 | 22-5（条目本身要求） |
| 取流：3.x 存下的“封禁”卡片 | 0（报 `NeedsLogin`） | 1（先进房） | 22-1 |
| 链接导入 | 不变 | 不变 | — |

### 画质 id 对照（给 J02.1）

| v3 的 id（v3 的名字，样本 S01） | 新 id（新名字） |
|---|---|
| `h264:origin:flv`、`h264:origin:hls`（原始画质 · 1080x1920 · H264 · FLV / HLS） | `h264:origin`（原画） |
| `h264:hd:flv`、`h264:hd:hls`（高清 · 720x1280 · H264 · FLV / HLS） | `h264:hd`（720p） |
| `h265:uhd_60:flv`、`h265:uhd_60:hls`（超清 60 帧 · 1080x1920 · H265 · …） | `h265:uhd_60`（1080p60 · H.265） |
| `h265:hd_60:*`、`h265:hd:*`、`h265:sd:*`、`h265:ld:*` | `h265:hd_60`（720p60 · H.265）、`h265:hd`（720p · H.265）、`h265:sd`（540p · H.265）、`h265:ld`（360p · H.265） |
| 规则：`<编码>:<档位>:<flv 或 hls>` | `<编码>:<档位>`（编码、档位转小写） |
| 其他 | 不变 |

- 代码：`TikTokApi.qualityIdFromLegacy(id)`（去首尾空白，按上面的规则去掉协议；不是 3.x 形状的原样返回；套用两次结果不变）。适配器取流、恢复时也认旧 id，漏迁的也能播。
- 3.x 的全局画质偏好按名字存（原画、蓝光8M……），不是本平台的 id。3.x 的名字对不上任何偏好，一律按比例落档；现在“原画”能直接对上 H.264 的原画，H.265 的原画叫“原画 · H.265”，对不上，所以不会因为偏好“原画”选中 H.265。

### 设置项

| 名字 | 默认 | 含义 | 接口 | 留给 |
|---|---|---|---|---|
| `preferH264`（“优先 H.264”，统一原则的全局设置，与 8-8、14-5、33-2 共用） | 开 | 开：H.264 画质全部在前，H.265 画质在后（名字带“ · H.265”），默认播 H.264；关：按档位排，最好的档在前（v3 的顺序） | `TikTokSite(http, preferH264: () => 设置值)`，每次取画质时读，改了不用重建适配器；`TikTokApi.qualities(data, preferH264: …)` | J02.1 存储；M13 设置界面；G 评估默认值 |

注意（给 G，同映客）：v3 选默认画质时先按名字匹配偏好，匹配不上按比例落到列表的某一档。“优先 H.264”开着时，偏好不是“原画”的用户按比例可能落到后面的 H.265 档，应改为只在 H.264 的档里按比例选（线路的 `codec` 是 `hevc` 的跳过）。

### 身份迁移规则（给 J02.1）

不需要：房间身份仍是用户名（比较不分大小写，E05.2），没有按场次关注的旧数据。3.x 关注里存成“封禁”（`liveStatus` 4）的 TikTok 房间不用迁移：下一次关注刷新就会变成直播中 + 受限类型或未开播；在那之前取流会先进房。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed` 列出、原因写在旁边；`expected.json` 没有改：

- 所有样本的房间（刷新、进房、录制、搜索、`share/live` 搜索）：`notice`（说明文字原则）。S01 在播的房间多了 `startedAt`（2026-09-27T18:12:04Z）和 `restriction: none` 两个键，测试断言 3.x 的输出里没有这两个键；未开播的没有。
- S01 在播的画质：14 个变成 7 个，名字、id、顺序都变了（22-2、22-3、22-4）。测试断言：3.x 的每个 id 经 `qualityIdFromLegacy` 都对得上一个新画质，而且按 3.x 的顺序去重后就是“优先 H.264”关时的顺序；每个新画质的地址就是 3.x 两个画质的地址（FLV 在前、HLS 在后）；用 3.x 的 id 取流也能取到。
- S01 搜索短链 `https://vm.tiktok.com/ZMabcdef/`：v3 不发请求、没有结果；现在读跳转（22-5），用合成的跳转回答测试。
- 受限直播、坏字段、坏地址只有合成用例（22-1、22-6）。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| 评论弹幕（22-7）：要 X-Bogus 签名和 `msToken`；直播间号在 `TikTokRoomData.liveRoomId`。接上后把公告 `chatNotice` 的第一句去掉 | D01 |
| 一个画质两条线路（FLV 在前、HLS 在后），出错时换下一条；线路编号 `flv`、`hls`，续期时按编号换回同一种；H.265（FLV 里是 HEVC）的硬解在高通真机上验证（REG-PLAY-022）后再评估“优先 H.264”的默认值；默认档见上面的注意 | G |
| 录制受限的直播：录制详情是直播中 + 受限类型，取流报 `StreamUnavailable`，应按 `restriction` 停下或等待，不要当作临时失败反复重试（v3 按“封禁”停止） | H01.1 |
| 存 `preferH264`；按上面的对照迁移存下的 TikTok 画质 id | J02.1 |
| “优先 H.264”的设置界面；卡片按 `restriction` 标“仅粉丝”“仅订阅者”“付费”；受限直播的播放错误说明需要关注、订阅或付费，不引导登录；开播时间只在直播中显示；昵称为空时显示平台名；画质名“原画”和“ · H.265”的多语言；公告 `tiktok_chat_notice` 的新文字（见上）| M13 |
| 目录说明 `tiktok_directory_scope`（3.x：“首阶段接入精确账号、@账号、官方主页/直播间/直播分享链接；游客公开推荐目录依赖网页会话，当前入口保留范围说明。”）改写，建议：“TikTok 没有可以直接浏览的直播列表。请在搜索页输入用户名（可以带 @），或粘贴 TikTok 主页、直播间、直播分享链接或 App 分享的短链。” 英文：“TikTok offers no public list of live streams. Search for a username (with or without @), or paste a TikTok profile, LIVE, LIVE share link or app short link.” | M13 |

### 受阻

- **22-8 推荐、分区**：2026-09-29（北京时间）经代理、不带 Cookie 和签名只读地请求了：
  - `webcast.tiktok.com/webcast/feed/?aid=1988&channel_id=86…`、`webcast.us.tiktok.com/webcast/feed/?aid=1988`：HTTP 200，空正文；
  - `www.tiktok.com/api/live/discover/get/?aid=1988&count=20`：`status_msg: url doesn't match`（缺 X-Bogus 等签名）；
  - `webcast.tiktok.com/webcast/room/recommend/?aid=1988`：`status_code 10013, Url does not match`；
  - `www.tiktok.com/api/search/live/full/?aid=1988&keyword=qvc`：`status_code 2483, Please login your account first`；
  - `www.tiktok.com/api-live/recommend/?aid=1988`：HTTP 404 `not_found`；
  - `www.tiktok.com/live` 页面的服务端数据（`__UNIVERSAL_DATA_FOR_REHYDRATION__`）只有应用配置、导航和翻译，没有房间，房间由前端带签名请求加载。

  与归档规格 §0（2026-09-28）的结论相同：目录和推荐要 X-Bogus/X-Gnarly 签名或登录。照任务要求不绕过平台限制，目录保持为空、常驻说明。
- 22-7 不在本次范围（D01）。

没有样本、只靠合成回答的部分：受限直播（私密账号、订阅专属、付费）、短链的真实跳转（E03.9 同样没有）、坏字段和坏地址。

### 测试

本平台 77 个用例（E03.9 是 65 个；新增 12 个，另改写了画质、受限、字段检查、流容错、取流的用例），`live_core` 共 3307 个，全部通过：

- `tiktok_api_test.dart`（43 个）：
  - 与 v3 的对照：三种深度（`notice` 的新文字）、开播时间和 `none` 两个新键、未开播不填；
  - 画质：S01 的 7 个画质在“优先 H.264”开和关时的名字、id、排序和顺序；3.x 的 14 个 id 的对照；每个画质的线路是 3.x 两个画质的地址（FLV 在前）、旧 id 能取流；线路的请求头、格式、编码、编号、租期；
  - 22-1：三种受限及其先后都是直播中 + 受限类型、有人数和开播时间、不读流、取流原因；未开播不填；`startTime` 的范围；
  - 22-6：身份、状态、受限字段仍严格（8 种）；15 种只影响名片的坏字段留空、房间照常；
  - 流：两个容器按编码和档位合并、FLV 和 HLS 分组、同协议第二个地址的线路编号；22-4 的命名顺序（平台名、原画、分辨率、3.x 档位名、键名、H.265 后缀、同名加档位）；编码名；分辨率；可信主机（坏地址只丢这条线路）；12 种坏容器或坏档只丢自己、什么都不剩时报 `ApiChanged`；不读流的情形；直播中没有流。
- `tiktok_site_test.dart`（34 个）：
  - 搜索：3 个样本 6 种输入与 v3 一致；22-5 的三种短链（绝对和相对跳转、请求头、不跟随）、跳到 `share/live`（3 个请求）、连续短链、最多 3 次、绕圈、跳到视频、首页、别的网站、非跳转、400/404、没有 `Location` 都没有结果；403、429、503、网络失败照抛；取消；
  - 房间：受限直播在四种深度和 3.x 关注合并后都是直播中 + `private`、有开播时间；开播状态对受限直播为真；录制：没有流报错、流全坏报 `ApiChanged`、受限的房间照常返回；
  - 取流：进房后 7 个画质不发请求、原画两条线路与 v3 的两个画质地址一致、恢复 1 个请求；“优先 H.264”每次读、开关两种顺序、默认开；卡片先进房、旧 id 取两条线路；未开播不发请求、3.x 的“封禁”卡片先进房；受限、没有流、一个容器坏、未知状态的原因；恢复时认旧 id。

## 后续（D01 弹幕）

本平台的聊天在 D01.19 做了调查，受阻（要签名），调查结果见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.19-TikTok弹幕/record.md)，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文“弹幕留给 D01”等说法是 E 当时的情况。
