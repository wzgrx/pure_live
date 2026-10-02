# E03.8 LiveMe

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/liveme/`（`liveme_api.dart` 纯解析，含链接和签名；`liveme_site.dart` 请求编排）
- 样本：`fixtures/liveme`，12 个真实接口录制（2026-09-27，直连，匿名），来自归档；全部附有 v3 的冻结输出 `expected.json`，生成方法见下文。LiveMe 没有弹幕样本（v3 和归档 v4 都没有 LiveMe 弹幕）。
- 参考：
  - 归档 v4 的 LiveMe 适配器和规格（`spec/sites/liveme.md`）。规格没有 REG 编号的回归条目，§10“踩过的坑”有三条，见“回归条目的覆盖”；
  - pure_live_TV `e1cca224`：`lib/platforms/liveme/` 与 v3 相同，只改了导入路径，卡片的粉丝、在线、累计缺值时写空串而不是 null，没有行为修复；对照笔记 `~/ref/notes/tvcore/sub_B.md` 的 liveme 一节。

照 E01.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## v3 的冻结输出

归档只给五个大站生成过 `expected.json`。本模块用 `fixtures/liveme/legacy_expected.dart` 生成：

- 把 v3 的 `LiveMeApi`、`LiveMeLink`、`LiveMeSigner`、`LiveMeSite`（`legacy/lib/core/site/liveme/` 四个文件）原样搬进一个程序。v3 本来就把传输做成可注入的函数（`LiveMeRequest`），所以只换了它：按方法、主机、路径和查询参数读样本（时钟参数 `_time` 不比），POST 另按表单的 `videoid` 匹配（签名字段每次都变）；状态码不是 200 时正文为空（同 v3）；没有样本的请求抛 StateError 并原样抛出，不会被当成 v3 的传输失败。记下的请求把 `_time` 写成 `<time>`，POST 附上 `videoid`。
- 只在网络路径上用到的 `_defaultRequest`、`readBody` 没有搬；`LiveMeSite` 保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`（`EmptyDanmaku`），两个构造函数改为必须注入传输。
- dio 的 `CancelToken`、`DioException`，v3 的 `LiveRoom`（含 `httpHeaders`）、`LiveArea`、`LivePlayQuality`、`LivePlayUrlResolution`、`LiveDirectoryPage`、`HttpHeaderPolicy` 只搬用到的部分；`i18n` 返回 3.x `zh.json` 的文字。链接导入用 v3 `LiveUrlTool._parseLiveUrl` 里 LiveMe 的那一段（`live_url_tool.dart:223-228`）。
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），另记下每个调用发出的请求。
- 只依赖 `package:crypto`（v3 签名用，已在工作区），在仓库根目录运行：`dart run fixtures/liveme/legacy_expected.dart`。连续运行两次，输出逐字节相同。

各样本的期望值：

- `S01-featurelist-p1`、`-p2`：`getDirectoryPage`、`getRecommendRooms`（每页 20）；第 1 页另有带分区的目录、第 0 页（都不发请求，报错）、`directoryNoticeKey`、列表卡片取画质（v3 报 `identity`）；
- `S02-search-p1`、`-p2`、`-empty`：`searchRooms`（每页 30），以及 v3 API 层的 `hasMore`；
- `S03-mapping-live`（配 `S04-profile-live`、`S05-query-live`）、`S03-mapping-offline`（配 `S04-profile-offline`）、`S03-mapping-notfound`：刷新、进房、录制、开播状态、按短号和房间链接搜索、第 2 页，画质、地址、恢复取流，每项带请求；
- `S04-profile-*`：主页链接 `/u/<uid>` 的导入和搜索；
- `S05-query-live`：30 个链接向量的 `LiveMeLink.parse` / `parseOrShortId`，分享页（直播信息里的 `shareurl`）和 `/v/` 链接的导入、搜索。

## 做法

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变。v3 实现过的可选能力全部保留：原生目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，`liveme_directory_scope`）、可取消的搜索（`LiveCancellableSearch`）、刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、带实际画质的取流（`LivePlayUrlResolver`）、恢复时重新取流（`LivePlayRecoveryResolver`）。另加 `LiveSiteLinks`。
- **房间身份是短号**（`ushortid` / `short_id`，5–12 位、不以 0 开头），与 v3 相同：房间号、链接都来自请求的短号，详情里平台回显的短号必须与之相同，样本对照里每个房间的 `roomId` 都与 `expected.json` 一致，3.x 存下的关注都能对上。用户 id（`uid`）和本场直播 id（`vid`）放在 `LiveMeRoomData` 里，不存储。
- **请求照 v3**：全部匿名，带 v3 的请求头（UA、`Accept`、`Accept-Language`、`Origin`，`Referer` 是房间页或热门页），不跟随跳转；没有 Cookie（v3 没有 LiveMe 登录，设置里也没有它的 Cookie），所以不注入 `CookieVault`。

  | 调用 | 请求 | 次数 |
  |---|---|---|
  | 分类 | 不请求（没有分类，同 v3） | 0 |
  | 推荐、目录分页 | `lvapi.liveme.com/live/featurelist?countryCode=GLOBAL&page_index=&page_size=&pid=3&posid=3002&h5=1`（目录每页 20，推荐按调用方 1–50） | 1（同 v3） |
  | 关键词搜索 | `live.liveme.com/search/searchKeyword`（访客参数加 `type=1&page=&pageSize=&keyword=&tuid=&uid=&token=&androidid=`，每页按调用方 1–40，平台固定回 20 条） | 1（同 v3） |
  | 短号、房间链接搜索 | 同进房（不取流） | 2～3（同 v3） |
  | 主页链接、分享链接搜索 | 先 `user/getinfo` 或签名的 `live/queryinfosimple` 取短号，再同进房 | 3～4（同 v3） |
  | 进房、关注刷新、录制、开播状态 | `uid_vid_by_short_id`；然后并行 `user/getinfo` 和（在播时）签名的 `queryinfosimple` | 2～3（同 v3） |
  | 没有 `data` 的房间取流、恢复取流 | `uid_vid_by_short_id` 和 `queryinfosimple` | 2（v3 恢复是 3，列表卡片取流直接失败） |
  | 链接导入（主页、分享页） | `user/getinfo` 或 `queryinfosimple`，经 `ShortLinkSession` | 1（同 v3） |

- **签名照 v3 的算法**（`LiveMeSigner`）：表单加 `lm_s_id`、`lm_s_ts`、`lm_s_str=md5(lm_s_ts)`、`lm_s_ver=1`、`h5=1`，查询参数和表单按键名排序拼“键+值”，再拼 `lm_s_id`、`lm_s_ts` 和网页密钥取 md5，作为请求头 `lm-s-sign`。用录制样本的签名和归档 v4 的独立向量（Python hashlib）核对。时间戳的计数后缀改成一位（见问题 8）。POST 的内容类型照 v3 写 `application/x-www-form-urlencoded`，不带 charset。
- **解析照 v3 的严格程度**：
  - 目录：没有 `ushortid` 的卡片（联合直播间）跳过，其余卡片的短号、用户 id、名字、文本字段、人数有一处不对，整页报 `ApiChanged`（v3 测试固定的行为）；超过 100 行也是 `ApiChanged`；私密（`ispvt`=1）、付费（`livebptype`=7 或标签对象的 `text` 是 “Paid broadcast”）不列出；同一页按短号去重；`next_page`=1 才有下一页。
  - 搜索：行的短号、用户 id、名字不对整页报 `ApiChanged`；名字优先 `nickname`，没有时用 `uname`，同时作标题；粉丝优先 `fans_num`；`is_live`=1 是直播，`is_live`=0 且 `project` 是 `liveme` 是未开播，其余（联合项目 `emolm`、`lmpro` 等）是未知（v3：联合项目在播时也报 0）。
  - 详情：短号映射的 `uid`、`vid`，资料的 `uid`（或 `userid`、`cm_openid`）和短号，直播信息的 `vid`、短号、用户 id 都必须是请求的那个，否则 `ApiChanged`；资料必须有 `count_info`。
- **状态照 v3**：`online`=1、`status`=0、`roomstate`=0 是直播；`online`=0 或另两个非 0 是未开播；都没说是未知；私密和付费是“封禁”（`banned`）。没有当前直播的主播是未开播。
- **卡片字段照 v3**：
  - 在播时热度是 `popularity`（也写进旧的 `watching`），`playnumber` 是在线，`watchnumber` 是累计，人数口径是热度；不在播或搜索结果没有热度，口径是在线（值为空）；
  - 标题为空时用名字；封面 `videocapture`，没有时 `smallcover`；头像 `uface`；
  - 进房时封面、头像、简介、地区缺的用资料补，粉丝取资料的 `count_info.follower_count`；简介优先直播信息里 `user_info.desc`，没有时用资料的 `usign`；
  - 未开播时标题是名字，头像、封面用资料的大图（`big_face`、`big_cover`），简介 `usign`；
  - 每个房间的公告是 3.x 的“LiveMe 远端聊天尚待接入；热度、当前观看和累计观看分别展示。”（`liveme_chat_notice` 的中文，与 3.x 中文界面存下的相同），界面可以按平台显示自己的翻译（M13）。
- **画质照 v3**：`原始画质 · FLV`（`source-flv`，`videosource` 和 `videosourcemore`）、`流畅画质 · FLV`（`smooth-flv`，`smallsource` 和 `smallsourcemore`）、`HLS 自动 · HLS`（`hls`，`hlsvideosource`），排序值 300、200、100，没有地址的不列出。地址照 v3 的规则：字段可以是网址、JSON 文本、列表或对象（三层以内），只收 `linkv.fun`、`emolm.com`、`liveme.com` 及其子域、路径以 `.flv` / `.m3u8` 结尾、没有用户信息和片段的地址，一律改成 https，去重。
- **线路**：每个地址一条线路，带 v3 `PlaybackHeaderResolver` 里 LiveMe 的请求头（UA、`Origin`、`Referer` 房间页）、格式和线路编号（画质 id，`*more` 里的备用地址依次加 `#2`、`#3`；媒体主机随调度变化，不能当线路身份）。租期取地址里网宿签名的 `wsABStime`（十六进制的到期 Unix 秒，样本里是签发后约 4 小时），到期前 min(10 分钟, 寿命的 1/4) 续期；过期后已建立的连接会不会断还没确认（规格 §12），标为只预取。v3 没有 LiveMe 的租期。编码不写：平台接口不说（归档 v4 按一次实测写了 AVC）。
- **取流时才判断能不能播**：进房照样返回房间（私密、付费仍显示封禁，状态照 v3）；取画质时私密、付费、未开播、状态未知、在播却没有合规地址都报 `StreamUnavailable`。平台明确未开播或封禁、又没有 `data` 的房间直接报，不发请求。
- **链接**：`LiveMeLink.parse` 照搬 v3 的规则：`liveme.com`、`www.liveme.com`（http 或 https，不带用户信息），可选的地区段（`us`、`zh-tw`），然后
  - `livehot/streaming/<短号>`：房间，直接得到（`roomIdFromUrl`）；
  - `u/<uid>`、`v/<vid>`、`m/v/<vid>/index.html`（直播信息的 `shareurl` 就是这种）：要请求一次（`needsResolving`、`resolveUrl`，经 `ShortLinkSession`）。
- **弹幕**：v3 没有 LiveMe 弹幕（`EmptyDanmaku`），规格 §7 也没找到匿名可用的实时通道（`chatSystem`=3，私有 IM）。v3 没有给弹幕连接传任何参数，所以不输出弹幕参数类；本场直播 id（与 `TCRoomId` 相同）在 `LiveMeRoomData.videoId` 里，D01 需要时可用。

## 审查发现的 v3 问题

位置简写：`A` = `legacy/lib/core/site/liveme/liveme_api.dart`，`L` = `liveme_link.dart`，`S` = `liveme_site.dart`，`G` = `liveme_signer.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`，`lut` = `legacy/lib/common/utils/live_url_tool.dart`，`sc` = `legacy/lib/modules/search/search_controller.dart`。“按 v3 保留”的，修法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 失败都是 `LiveMeException`，播放、录制只能按种类名判断；主播不存在（业务 500 “user not exist”）算 `service` | A:12-32、A:225-231 | 平台自己的异常类型 | 类型化错误（见差异 1） |
| 2 | 在播、但地址都不合规的直播进房直接失败，房间页打不开 | S:95-101 | 进房用取流模式，把“不能播”当成“详情失败” | 进房照常返回房间，取流时报 `StreamUnavailable` |
| 3 | 没有 `data` 的房间（列表卡片、刷新得到的关注）取画质报 `identity` | S:151-162 | 只认进房时放进 `data` 的快照 | 先查当前直播（2 个请求）再给画质 |
| 4 | 未开播、封禁的房间取画质得到空列表，播放器拿不到原因 | S:180 | 返回 `[]` | 报 `StreamUnavailable`，不发请求 |
| 5 | 恢复取流要求旧快照是在播的：进房时未开播的房间，主播开播后也恢复不了；恢复还要多请求一次主播资料 | S:193-195 | 先校验旧快照，再整套进房 | 恢复时直接查当前直播（映射和直播信息 2 个请求），不复用旧地址 |
| 6 | 地址是网宿签名地址（`wsABStime` 约 4 小时后到期），却没有续期时间 | S:193-206 | 没有实现 `LivePlayLeaseMetadata` | 线路自带租期 |
| 7 | 平台层依赖全局 `HttpClient`；播放请求头按平台写在播放层；房间 JSON 里另存一份媒体请求头 `httpHeaders`，只有 IPTV 分支会读 | A:141-156；phr:180-181、phr:143-148；S:83 | 结构问题（诊断报告里的“旁路”） | 注入 `LiveHttp`；线路自带请求头，与 v3 的值相同；房间不再写 `httpHeaders`（差异 7） |
| 8 | 签名时间戳的计数后缀是 `% 10000`：同一进程第 10 个签名请求起，`lm_s_ts` 从官网的 14 位变成 15～17 位 | G:27 | 计数没有限制在一位 | 一位计数，0～9 循环（同归档 v4、规格 §6.1） |
| 9 | 链接的路径解不开（如 `%FF`）时 `LiveMeLink.parse` 抛 `FormatException`，搜索框里输入这样的链接，LiveMe 的搜索直接失败 | L:17 | `pathSegments` 解码失败没有捕获 | 不算链接，按关键词搜索 |
| 10 | 分享页、主页链接的导入遇到不存在的主播时把异常抛给工具箱 | lut:223-228 | `resolveReference` 的错误没有收住 | `resolveUrl` 返回“没有房间”；工具箱对两种情况都提示“解析失败”，用户看到的一样 |
| 11 | 每个回答都边读边限 8 MiB，另有 20 秒读取期限 | A:113、A:166-188 | 自带的读取器 | 传输统一由 `live_net` 负责；下载后检查 8 MiB 上限（超过是 `ApiChanged`），期限由请求超时覆盖（同 E03.3、E02.6） |
| 12 | 平台层调用界面翻译（公告、三个画质名） | S:82、S:164-169 | `i18n` 写在适配器里 | 写 3.x `zh.json` 的中文（与 3.x 中文界面存下、显示的相同），多语言在 M13 |
| 13 | 付费标签 `hot_label_v2` 只按对象读，但平台发的是 JSON 文本（两页样本里都是），这条判断从来没有生效 | A:474 | 没有解开 JSON 文本 | 按 v3 保留（修好会改变目录内容） |
| 14 | 封面、头像、资料大图的兜底只在字段缺失（null）时生效，字段是空串时就没有图（`videocapture ?? smallcover`、`big_face ?? face`、`big_cover ?? cover`、`uface ?? face`） | A:494-495、A:409-410 | 用了 `??` | 按 v3 保留 |
| 15 | 在播房间的简介取直播信息里的 `user_info.desc`（样本里就是昵称），资料里真正的签名 `usign` 被盖住 | A:496、A:538 | 合并时直播信息优先 | 按 v3 保留 |
| 16 | 5～12 位的数字一律当短号查房间，不做关键词搜索 | S:135 | `parseOrShortId` | 按 v3 保留（这是 v3 的设计：按短号直达房间） |
| 17 | 规格和上游笔记说“搜索永远只有一页”（A:343 的 `hasMore` 用“条数 ≥ pageSize”判断） | A:343；sc:342-366、sc:380 | —— | 查明不是问题：`hasMore` 是死代码，v3 站点层从不读它；搜索页只要本页有新房间就继续翻页（每页请求 20 条，平台回 20 条）。样本 S02 两页 20 条、互不重叠，空页结束 |

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序、地址和 `appliedQualityData`；请求比较地址和次数（`_time` 按 `<time>` 比）。所有房间只有 `httpHeaders` 一个键不同（差异 7）。

| 样本 | 结果 |
|---|---|
| S01 精选（第 1、2 页各 20 个） | 一致：房间、顺序、各字段、页码和是否还有下一页；`getRecommendRooms` 给出同样的列表，请求相同 |
| S02 搜索（`andre` 第 1、2 页各 20 人，无结果） | 一致：名字同时作标题、头像、地区、粉丝、状态（直播、未开播、未知）；请求相同 |
| S03+S04+S05 在播 | 刷新、进房、录制、按短号和房间链接搜索一致（含粉丝 33933、简介）；开播状态 true；请求相同（各 3 个）。三个画质的名称、id、排序、地址、`appliedQualityData` 逐字节一致；恢复取流的地址一致，请求 2 个（v3 是 3 个） |
| S03+S04 未开播 | 一致：未开播、标题是名字、大头像、没有封面、简介 `usign`；请求相同（各 2 个）。v3 取画质得到空列表，现在报 `StreamUnavailable`（不发请求） |
| S03 短号不存在（业务 400） | 一致：详情是“不存在”，搜索没有结果，请求 1 个 |
| S04 主页链接 | 在播、未开播的导入都得到短号，请求 1 个；搜索得到同一个房间，请求相同。不存在的主播：v3 导入和搜索都报 `service`，现在导入返回“没有房间”、搜索没有结果 |
| S05 分享页、`/v/` 链接 | 导入得到 `209683072`，1 个签名 POST；搜索得到房间，请求相同（4 个）。30 个链接向量中 29 个与 v3 相同，`%FF` 那个 v3 抛异常，现在不算链接 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 错误类型化：HTTP 400 `ApiChanged`，401/403 `RiskControl`，404 `NotFound`，420/429 `RateLimited`，5xx 和其他状态 `NetworkFailure`；业务 400/404 `NotFound`，401/403 `RiskControl`，420/429 `RateLimited`，500 “not exist” `NotFound`，其他 5xx `NetworkFailure`，其他 `ApiChanged`；身份不符、格式不对 `ApiChanged`；参数错误（带分区的目录、第 0 页、超过 256 字的关键词）`ArgumentError`，同 v3 不发请求 | 问题 1；分类与规格 §9 一致。界面看到的仍是加载失败或播放失败 |
| 2 | 进房不因“不能播”失败；取流时报 `StreamUnavailable` | 问题 2；房间的状态照 v3 |
| 3 | 没有 `data` 的房间取流时先查当前直播；明确未开播或封禁的房间直接 `StreamUnavailable` | 问题 3、4。正常进房流程不受影响 |
| 4 | 恢复取流只请求映射和直播信息，不再要求旧快照在播 | 问题 5；请求比 v3 少 |
| 5 | 线路带请求头、格式、线路编号和租期 | 问题 6、7；请求头的值与 v3 相同 |
| 6 | 签名时间戳固定 14 位 | 问题 8 |
| 7 | 房间 JSON 不再写 `httpHeaders` | 这份媒体请求头 3.x 里只有 IPTV 分支会读（phr:143-148），LiveMe 的播放和录制都按平台另查一遍；现在它在线路上。3.x 存下的旧值照读、`mergeFrom` 照留，3.x 读 v4 的备份也照样播放 |
| 8 | 主播不存在：搜索没有结果、链接导入返回“没有房间”（v3 都报错） | 问题 1、10 |
| 9 | 解不开的链接按关键词搜索 | 问题 9 |
| 10 | 图片地址先经 `normalizeImageUrl`（协议相对地址等也能显示），再照 v3 只收三个 CDN 主机、改成 https | 与其他平台一致；样本里都是完整的 https 地址，结果相同 |
| 11 | 响应只在下载完后查 8 MiB 上限；非法 UTF-8 变成替换字符而不是报错 | 问题 11 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **联合项目的主播搜索时状态未知**：归档 v4 一律按未开播显示（它没有“未知”），会把在播的联合项目主播显示成未开播。
- **私密、付费直播显示“封禁”，也不列进目录**：归档 v4 照常显示为直播，取流时报 `NeedsLogin`。应用没有 LiveMe 登录，提示登录也没有出路，所以取流报 `StreamUnavailable`。
- **状态未知不当错误**：归档 v4 把三个字段都没说的直播信息当 `ApiChanged`；这里照 v3 显示未知，只有开播状态查询报错（v3 的 `unknownState`）。
- **画质是 v3 的三个**：归档 v4 改成“原画”（FLV 和 HLS 两条线路）、“流畅”两个，画质菜单会变。
- **媒体地址照 v3 限定主机并改成 https**：归档 v4 保留原样（平台换 CDN 时不至于全部失效），上游与 v3 相同。实测 https 可用。
- **`*more` 字段照 v3 展开成备用线路**：归档 v4 只在主字段缺失时用 `videosourcemore`，不读 `smallsourcemore`；上游与 v3 相同。样本里 `*more` 与主字段相同，去重后只有一条。
- **进房的三个请求照 v3 并行**：归档 v4 依次请求。
- **目录、搜索照 v3 严格**：归档 v4 跳过坏行；这里照 v3 整页报错（v3 测试固定的行为）。
- **搜索每页照调用方的条数发送**（1～40）：归档 v4 固定 30。平台总是回 20 条。
- **标题不解码 HTML 实体**，同 v3。归档 v4 会解，样本里没有实体。
- **封面、简介的取法**（问题 14、15）、**付费标签**（问题 13）、**数字当短号**（问题 16）照 v3。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复；它把粉丝、在线、累计缺值写空串，这里同样写空串（`mergeFrom` 因此保留存下的值）。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 付费标签按 JSON 文本读，“Paid broadcast” 的直播不进目录 | 标签从来没有生效 | 问题 13；规格 §12 第 4 条（还没有付费直播的真实样本） |
| 2 | 封面、头像字段是空串时也用备用字段 | 空串时没有图 | 问题 14 |
| 3 | 在播房间的简介用资料的签名 `usign` | 显示 `user_info.desc`（样本里是昵称） | 问题 15 |
| 4 | 联合项目的主播搜索时显示未开播，进房以详情为准 | 未知 | 规格 §3；归档 v4 |
| 5 | 私密、付费直播正常显示为直播，取流时说明原因 | 封禁、不列出 | 归档 v4 规格 §4.3 |
| 6 | 媒体地址不限主机、不改协议 | 限定三个主机、改成 https | 规格 §5；平台换 CDN 时不至于全部失效 |
| 7 | 画质改成“原画”（FLV、HLS 两条线路）和“流畅” | 三个画质 | 归档 v4 |
| 8 | 确认 `wsABStime` 过期后连接是否断开，再决定线路的 `cutsConnection` | 只预取 | 规格 §12 第 1 条 |
| 9 | LiveMe 弹幕 | 没有弹幕 | 规格 §7：私有 IM，匿名通道待确认 |

## 回归条目的覆盖

规格没有 REG 编号的条目。§10“踩过的坑”三条都属于平台层，都有测试：

- 搜索只有一页：查明 v3 站点层不读 `hasMore`（问题 17）。测试断言 v3 的 `hasMore` 是 false、而两页各 20 条互不重叠、空页没有结果，站点层照样返回每一页。
- 联合项目的 `is_live` 不可靠：照 v3 显示未知，只有 `liveme` 项目的 0 才是未开播；进房以详情为准。
- 不存在的主播报服务错误：业务 500 “user not exist” 映射为 `NotFound`（S04-profile-notfound），搜索没有结果、链接没有房间。

规格 §7 的弹幕、§12 的待确认事项不属于平台层。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕：v3 没有（`EmptyDanmaku`），规格 §7 说直播间走私有 IM | D01 决定；本场直播 id 在 `LiveMeRoomData.videoId` |
| `getDanmaku()` | 同 E01.1：D01 用一张“平台 → 弹幕连接”的表 |
| 站点名、目录说明、公告、三个画质名（`site_liveme`、`liveme_directory_scope`、`liveme_chat_notice`、`liveme_quality_*`）的多语言 | M13 |
| 搜索能力“含未开播、可翻页、没有网页搜索”（`search_capability.dart:54-58`） | M13 搜索页 |
| 网页搜索结果里的 LiveMe 链接（`web_search_room_parser.dart:96-97` 的 `parseDurableRoomId`：房间页，或者纯短号） | M13；可用 `LiveMeLink.parse` 和 `normalizeShortId` |
| 外部打开房间页（`room_external_opener.dart:97-102`） | M13；地址就是房间的 `link`（`LiveMeLink.url`） |
| 直播间本地互动包里的 LiveMe 条目（`local_interaction_controller.dart:417-424`） | M13 直播间 |
| 热门平台列表的 v19 迁移把 LiveMe 加进去（`favorite_room_controller.dart:75`） | J02.1 |
| 平台图标（`sites.dart:205`） | I01.1 |
| 播放、录制读线路的请求头和租期 | G、H01.1 |
| 录制对错误的重试 | H01.1 决定哪些错误重试 |

## 新增的通用能力

- `ShortLinkSession.send`（`packages/live_core/lib/src/links.dart`）：在会话的规则下发送任意请求（例如签名的表单 POST）并读正文：方法和地址计入请求预算，不跟随跳转，站点、超时和取消用会话的。LiveMe 的分享页要用签名的 `queryinfosimple` POST 才能查到短号，原来的会话只有 GET。`sites_links_test.dart` 加了一个用例。
- 另在 `live_core.dart` 里按字母顺序加了两行平台导出。
- 没有新的第三方依赖（签名用的 `crypto` 已是 `live_core` 的依赖）。

## 测试

新增 59 个用例，`live_core` 共 1823 个，全部通过：

- `liveme_api_test.dart`（32 个）：
  - 逐个样本对照 v3 的输出（精选 2 页、搜索 3 页、在播和未开播的房间、映射、资料、直播信息、画质和地址、30 个链接向量），有意的差异逐条断言；
  - 移植 v3 `liveme_directory_test.dart`：没有短号的卡片跳过、短号不对的卡片整页失败；
  - v3 的其他解析规则：私密和付费、标签是 JSON 文本时不生效、去重、100 行上限、坏行；搜索的状态规则、名字和粉丝的取法；映射、资料、直播信息的身份校验和 `user_info` 兜底；四种状态、只在直播时读人数；封面兜底只认 null；图片主机和协议；
  - 取流：地址的主机、后缀、协议、片段、用户信息、空白，`*more` 的展开和去重，线路的请求头、格式、编号、租期（样本 `wsABStime` 和合成的短寿命、过期、畸形值），各种不能播的情况；
  - 签名：录制样本的 `lm-s-sign`、归档 v4 的独立向量、14 位时间戳和 `vali` 的字母表；
  - HTTP 状态和业务状态的映射、非 JSON、非对象、缺状态、超过 8 MiB。
- `liveme_site_test.dart`（26 个），用样本回放加少量合成响应：
  - 请求头、访客参数、不跟随跳转，签名 POST 的表单顺序、内容类型和签名，传输错误的映射，取消（请求前、应答后、传输出错后，以及短号查找的每个请求）；
  - 目录：两页和推荐的请求与 v3 逐个相同，推荐的每页条数 1～50，带分区和第 0 页不发请求；
  - 搜索：关键词的请求与 v3 相同，每页条数 1～40，空白、坏页码不发请求，超长关键词拒绝，四位数字和其他网站的链接按关键词搜索；短号、房间链接、主页链接、分享页只在第 1 页、请求与 v3 相同，不存在的房间和主播没有结果，其他失败报错；
  - 详情：进房、刷新、录制、开播状态的请求与 v3 相同，未开播 2 个请求，不存在的短号和非短号的房间号，别的房间或主播的回答，关注跨直播保持身份、3.x 存下的关注能合并，状态未知，私密、付费、未开播、没有合规地址的直播能进房、取流说明原因且不多发请求；
  - 取流：进房得到的房间不再请求、地址与 v3 相同，列表卡片先查直播（2 个请求），明确未开播和封禁不请求，恢复跟到新的直播、不复用旧地址，恢复 `source-flv` 的地址与 v3 相同；
  - 链接：房间页不请求，主页、分享页经 `LinkParser` 各一个请求（与 v3 的导入相同，走会话），查不到时没有房间。
- `sites_links_test.dart`（+1）：`ShortLinkSession.send` 的站点、跳转、超时、取消、正文、预算和关闭。
- v3 测试里 LiveMe 相关的只有 `liveme_directory_test.dart`（已移植）和 `recording_platform_contract_test.dart` 的平台注册（LiveMe 实现 `LiveSiteRecordRoomResolver`，由本模块的录制详情覆盖；注册表在 I01.1）。

## 升级落地（E06 平台层升级）

- 日期：2026-09-29（E03.8）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 21-1～21-9（“落地方式”只有 21-1、21-5、21-6、21-8 有内容，其余按上面“后续升级候选”的原文做）；模型字段按 [E05.2](../../E05-平台框架和模型/E05.2-模型扩展/record.md)。21-9（弹幕）属于 D01，本任务不做。
- 改动：只改了本平台：`liveme_api.dart`（解析）、`liveme_site.dart`（请求编排）和两份测试。没有改 `live_core` 的通用文件，没有新依赖，没有新样本（见“新样本”）。
- 实测：2026-09-28 18:40～19:10 UTC，直连、匿名、只读，请求头同适配器：
  - 精选目录（`countryCode=GLOBAL`）第 1～10 页，199 张卡片（187 个主播）；另取了 22 个国家和地区的第 1 页（52 个主播），看默认标题的语言；
  - 3 场 `wsABStime` 已经过期 1.5～6.7 小时的直播：新建的 FLV 连接（读前 192～256 KB，是 FLV 头）、HLS 主列表、子列表和 TS 分片都是 200；
  - 7 场在播直播走完短号映射、主播资料、签名的直播信息三步：`wsABStime` 与列表里的相同；`user_info.desc` 都等于昵称；`TCRoomId` 都等于 `vid`；`time - videolength` 都等于 `vtime`；
  - 精选里 27 个在播主播（21 个 `emolm`、4 个 `liveme`、`lmtlive` 和 `highlive` 各 1 个）的短号映射都给出列表里的那一场；
  - 官网网页端的脚本（`www.liveme.com/static/CLaEtC7T.js`）：付费和私密的判断、媒体地址的处理，引用见下面各条。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 21-1 | 付费标签按平台的实际格式读（`LiveMeApi.isPaidLabel`）：`hot_label_v2` 是 JSON 文本（官网网页端 `JSON.parse(e.hot_label_v2)`，样本里的 H2H、Multi-beam 标签也是），`text` 去掉首尾空白、不分大小写等于 “paid broadcast” 是付费；v3 的对象写法也认；解析不了的当作没有标签（网页端同样当 `{}`）。受限类型按网页端的同一条规则（`LiveMeApi.restrictionOf`）：`ispvt` 为 1 是 `private`，`livebptype` 为 7 或付费标签是 `paid`，都没有是 `none`，两者都有时取 `private`。精选目录不再在适配器里剔除这些直播，照常列出、状态直播中、标出受限类型；“发现页默认隐藏”由 M13 按 `restriction` 做（官网网页端自己也把它们从列表里去掉，`mde`） | M13 做隐藏以后，发现页默认仍看不到付费、私密直播，设置打开后能看到并标“付费”“私密”；关注和搜索照常显示。实测 199 张卡片和样本的 40 张里都没有付费和私密直播，平时看不出变化 | 平台层完成，余下 M13 |
| 21-2 | 图片取第一个能用的字段（`_firstImage`）：封面 `videocapture` → `smallcover`；头像 `uface` → 直播信息 `user_info` 的 `face` → `icon`（实际的回答里只有 `icon`）；资料的头像 `big_face` → `face`、封面 `big_cover` → `cover`。前一个是空串或不合规（不在三个图片 CDN 上）也用下一个，v3 只在字段缺失（null）时才用。进房时直播信息仍缺的，照旧用资料补 | 封面或头像字段是空串的直播，卡片和房间不再没有图。样本和实测里都有图，平时看不出变化 | 完成（E06 平台层升级） |
| 21-3 | 在播房间的简介用资料的签名 `usign`（`withProfile` 以资料为准，资料没有签名时才用直播信息里的 `usign`）。不再读 `user_info.desc`：样本和 7 场实测里它都等于昵称。资料没有签名时简介为空 | 在播房间的简介从主播昵称变成主播签名（S03 是 “NVIPSupport-I'm the OG Nightclub…”，v3 是 “LIVEME-NIGHTCLUB 🔆⃤”）；没写签名的主播简介为空（v3 显示昵称）。未开播的房间本来就是签名，不变 | 完成（E06 平台层升级） |
| 21-4 | 搜索行的 `is_live` 为 1 是直播中、为 0 是未开播，不再看项目（v3 只有 `liveme` 项目的 0 是未开播，联合项目 `emolm`、`lmpro`、`royal` 等是“未知”）；没有这个字段或是别的值仍是未知。进房、刷新以详情为准：实测 27 个在播主播（含 21 个 `emolm`）的短号映射都能取到当前直播 | 搜索结果里联合项目的主播从“待定”变成“未开播”（S02 两页 40 个结果里 19 个）。正在直播的联合项目主播在搜索里也显示未开播（平台就是这样报的），点进去按实际状态显示 | 完成（E06 平台层升级） |
| 21-5 | `LiveMeState` 去掉 `restricted`。私密、付费的在播直播状态是直播中，`restriction` 标 `private`、`paid`：目录卡片、进房、刷新、录制都是（开播状态查询因此返回在播）。取流时 `LiveMeApi.qualities` 报 `StreamUnavailable`，说明里写 `(private)` 或 `(paid)`（E05.2 的受限类型表；本平台没有登录，不报 `NeedsLogin`）；带受限类型的列表卡片、关注卡片不发请求直接报。受限直播的媒体地址不读。未开播的受限直播就是未开播（v3 是封禁）。3.x 存下的“封禁”关注刷新后变成直播中并标受限，下播后受限类型和开播时间一起清掉（E05.2 的合并规则） | 私密、付费直播从“封禁”变成直播中，关注分组在直播中；卡片标受限类型、播放时显示原因由 M13 做 | 平台层完成，余下 M13 |
| 21-6 | 媒体地址不限主机（`LiveMeApi.mediaUrl`）：任何 http(s) 主机、路径以 `.flv` / `.m3u8` 结尾、没有用户信息和片段的地址都收。按落地方式“只在 v3 原本失败的地方生效”：v3 认的三个 CDN 主机（`linkv.fun`、`emolm.com`、`liveme.com` 及子域，且没写端口）照 v3 改成 https（实测可用，官网网页端也对所有媒体地址 `forceHttps`）；v3 丢弃的其他主机（和写了端口的地址）原样保留，不改协议 | 平时看不出变化：样本和实测的地址都在三个主机上，与 v3 逐字节相同。平台换 CDN 时不至于整场“没有可播放的地址” | 完成（E06 平台层升级） |
| 21-7 | 画质改为两个：“原画”（id `source`，排序 300）：FLV 线路（`videosource`，再是 `videosourcemore` 的备用地址）在前，HLS 线路（`hlsvideosource`）在后；“流畅”（id `smooth`，排序 200）：FLV 线路（`smallsource`、`smallsourcemore`）。线路编号是格式名 `flv`、`hls`，备用地址依次加 `#2`、`#3`；确认的画质是新 id。某档没有地址就不列出（实测和样本的 239 张卡片里 96 张没有流畅档的地址），一个地址不合规只少这一条线路。v3 的 id 仍能取流（对照见下） | 画质菜单从“原始画质 · FLV”“流畅画质 · FLV”“HLS 自动 · HLS”三项变成“原画”“流畅”两项。默认仍先播 FLV（v3 默认第一档也是 FLV），FLV 打不开时换 HLS 由播放器做（G）。3.x 的全局画质偏好“原画”“流畅”现在能按名字对上 | 平台层完成，余下 J02.1 |
| 21-8 | 确认了：<br>- **到期时间跟着这一场直播，不跟着请求**：`wsABStime` 是开播时间（`vtime`）加固定时长，`zglive` CDN 是 10 小时（S01 的 39 行 9.85～10.0 小时，实测 197 行 9.44～10.0 小时），`game.live11` 是 24 小时（S01 的 1 行、实测 2 行）；同一场直播再请求，`wsABStime` 不变（7 场实测；样本 S01 和 S05 也相同）。所以“续期”拿到的还是同一个到期时间；<br>- **过期不断流**：3 场已过期 1.5～6.7 小时的直播，新建的 FLV 连接、HLS 的主列表、子列表和 TS 分片都照常 200；平台自己也照常下发过期的地址（S01 第 1 页的 30269538 在录制时已过期约 5 小时，仍在精选里）。<br>所以续期方式定为不续期：线路不再带租期（去掉 `LiveMeApi.lease`、`leaseLead` 和 `LiveMeRoomData.issuedAt`）；连接真的断了，照常走恢复取流（重新请求当前直播） | 看不出变化。播放到开播 10 小时以后，不会因为地址“到期”被换线或中断 | 完成（E06 平台层升级） |
| 21-9 | 本任务不做（D01）。平台层现在能给的：本场直播 id `LiveMeRoomData.videoId`，等于直播信息的 `TCRoomId`（`chatSystem` 为 3 的聊天室）。匿名能不能进聊天室、需要哪些参数（网页端用 `/app/spa/js/im.js` 的 IM SDK）没有查，所以没有加弹幕参数类，留给 D01 查明后再定 | 无 | 待做（不变） |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 直播信息和精选卡片的 `vtime`（Unix 秒；回答的 `time` 减 `videolength` 正好是它，样本 S05 和 7 场实测）。只在直播中填；0、负数、不是整数、超过 10 位（毫秒）的不填，坏的开播时间只丢这一项（`LiveMeApi.startedAt`）。目录卡片、进房、刷新、录制、按短号和链接搜索都有；关键词搜索的行没有这个字段，不填。S01、S03 的 209683072 是 2026-09-26 21:31:02 UTC |
| 受限类型 | 在播的直播信息和精选卡片都能判断，填 `private`、`paid` 或 `none`（21-1、21-5）。未开播、状态未知、关键词搜索的行、没有当前直播的主播都不填（看不出来） |
| 受限的直播改为直播中 | 见 21-5（v3 用 `banned`，E05.2 点名要改的三个平台之一） |
| 占位信息 | 标题：平台给没起标题的直播填 App 的默认标题，按主播界面的语言有多种写法。实测精选 199 张卡片里 129 张是它（“Click for fun!” 91、“¡Haz clic para divertirte!” 18、“Нажмите и веселитесь!” 14、“Clique e divirta-se!” 6），另在埃及、黎巴嫩的列表里有阿拉伯语的 “انقر للمتعة!”。这 5 种写法（`LiveMeApi.defaultTitles`，逐字比较）当作没有标题，照 v3 对没有标题的直播的做法用主播名（同映客的“正在直播中”）。其他语言的默认标题没有见到，照原样显示。名字没有占位值（没有名字的行跳过或报错）；封面、头像是主播自己的图（`is_default_videocapture` 在所有卡片上都是 1，不是占位的标志），没有默认图 |
| 回放、轮播、“不可播放” | 不适用：房间是主播，没在播就是未开播，不出回放（资料的 `has_replay` 是主播有没有回放录像，v3 不用） |
| 画质命名 | 见 21-7 |
| 默认编码 | 平台接口不说编码，线路不写 `codec`（归档 v4 按一次实测写了 AVC）；只有一种编码，“优先 H.264”对本平台没有影响 |
| 房间身份 | 不变：数字短号，大小写无关，不加入 `SiteIds.caseInsensitiveRoomIds` |
| 按主播关注 | 本来就是：短号是主播的，一个主播一个房间；没有单场的身份，没有迁移 |
| 容错 | 精选目录、关键词搜索：一行读不出来（不是对象，短号、用户 id 不对，没有名字，文字字段不是文字，人数是负数或小数）只跳过这一行（v3 整页 `ApiChanged`，v3 的测试固定了这一点，E03.8 照做过）；一页有坏行而没有一行能用时仍报 `ApiChanged`，信封、列表形状不对、超过 100 行也仍报错，接口改版不会显示成空列表。没有 `ushortid` 的联合直播间照旧跳过（不算坏行）。进房、刷新的回答仍然严格（身份对不上就是 `ApiChanged`）。一个媒体地址不合规只少这一条线路（本来就是） |
| 翻页 | 目录和搜索都是平台分页（目录每页 20，搜索平台固定回 20 条），没有一次取全的列表，不共用快照。跨页的重复（实测 10 页 199 张卡片只有 187 个不同的主播；S01 第 1 页最后一张就是第 2 页第一张）由列表去重：v3 的 `live_directory_controller.dart:209` 按 `identityKey` 去掉已列出的房间，M13 照做 |
| 弹幕 | 见 21-9 |
| 说明文字 | 每个房间的公告 `LiveMeApi.chatNotice` 改成用户看得懂的话：v3 “LiveMe 远端聊天尚待接入；热度、当前观看和累计观看分别展示。” → “这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。”（多语言键 `liveme_chat_notice` 不变，M13 按平台显示自己语言的文字）。目录说明 `liveme_directory_scope` 是界面的文字键，平台层不改，建议的新文字见“留给其他模块” |

### 请求数

| 场景 | E03.8 | 现在 | 说明 |
|---|---|---|---|
| 分类 | 0 | 不变 | — |
| 精选目录、推荐每页 | 1 | 不变 | 私密、付费的卡片也列出，不多请求 |
| 关键词搜索每页 | 1 | 不变 | — |
| 短号、房间链接搜索 | 2～3 | 不变 | — |
| 主页链接、分享链接搜索 | 3～4 | 不变 | — |
| 进房、关注刷新、录制、开播状态 | 在播 3、未开播 2 | 不变 | 开播时间、受限类型来自已有的直播信息 |
| 取流：带进房数据的房间 | 0 | 不变 | — |
| 取流：没有进房数据的卡片 | 2；明确未开播 0 | 2；明确未开播 0；标了私密、付费的卡片 0 | 21-5 |
| 恢复取流 | 2 | 不变 | 21-8 不续期，不会因为租期多请求 |
| 链接导入 | 1 | 不变 | — |

### 画质 id 对照（给 J02.1）

| 旧 id（v3 的名字） | 新 id（新名字） | 对应的线路 |
|---|---|---|
| `source-flv`（原始画质 · FLV） | `source`（原画） | `lineId` 为 `flv` 的线路（`flv#2`… 是它的备用地址） |
| `hls`（HLS 自动 · HLS） | `source`（原画） | `lineId` 为 `hls` 的线路 |
| `smooth-flv`（流畅画质 · FLV） | `smooth`（流畅） | `lineId` 为 `flv` 的线路 |
| 其他 | 不变 | — |

- 代码：`LiveMeApi.legacyQualityIds`（常量表）、`LiveMeApi.qualityIdFromLegacy(id)`（去掉首尾空白、不分大小写查表，表外的 id 原样返回）。取流（`resolvePlayUrlsRaw`、恢复取流）直接接受旧 id，按新画质给出全部线路，确认的画质报新 id，所以漏迁的也能播。
- 3.x 的全局画质偏好按名字存（原画、蓝光 8M、蓝光 4M、超清、流畅），“原始画质 · FLV”这些不在其中；改名后全局偏好“原画”“流畅”能直接对上。这张表给 v4 自己按房间存下的画质用。
- 旧 id 是 `hls` 的，如果要保留“先播 HLS”的意思，可以把 `lineId` 为 `hls` 的线路排到前面（G 决定）。

### 设置项

无。本平台的 9 行都不需要开关。

### 身份迁移规则（给 J02.1）

无。房间身份仍是主播的数字短号（v3 起就是），没有旧 id → 新 id 的规则，也没有大小写不同的重复关注。3.x 存下的“封禁”（`liveStatus` 4）关注不用迁移：刷新后按 21-5 变成直播中并标受限，或者未开播。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（注释写原因），新键另外断言：

- 所有房间：`notice`（说明文字原则），以及 E03.8 起就有的 `httpHeaders`（E03.8 差异 7）。
- S01 精选两页：默认标题的卡片 `title` 变成主播名（第 1 页 10 张、第 2 页 11 张，占位信息）；新键是每张卡片的 `startedAt` 和 `restriction: none`。房间、顺序、页码、是否还有下一页、推荐的结果都与 v3 相同。
- S02 搜索：联合项目主播的 `liveStatus` 从 3（未知）变为 1（未开播），两页共 19 个（21-4）；没有新键。
- S03+S04+S05 在播：进房、刷新、录制、按短号和房间链接搜索的 `introduction` 从昵称变为签名（21-3）；新键 `startedAt`、`restriction: none`。画质由三个变成两个（21-7）：“原画”的线路就是 v3 `source-flv` 和 `hls` 的地址，“流畅”就是 v3 `smooth-flv` 的地址，逐字节相同；恢复 `source-flv` 时第一条线路就是 v3 恢复的地址，确认的画质从 `source-flv` 变为 `source`。线路不再有租期（21-8）。
- S03+S04 未开播：只有 `notice`；没有新键。
- S04、S05 的链接导入和搜索、S03 不存在的短号：没有变化。
- 私密、付费（v3 封禁、不进目录）、坏行只跳过、空串图片的兜底、其他主机的媒体地址：样本里没有，用合成数据测试。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 | 21-9 LiveMe 弹幕：本场直播 id 在 `LiveMeRoomData.videoId`（进房、录制的 `data`），等于聊天室 `TCRoomId`；通道和参数待 D01 查明，查明后在平台层加弹幕参数类 |
| G | 21-7 线路：“原画”的 FLV 打不开或断开时换 HLS 线路（`flv#2` 等是同档的备用地址）；旧 id `hls` 是否先播 HLS。21-8：线路没有租期，不用按时换地址 |
| J02.1 | 21-7 存下的画质 id 按上表迁移；按 E05.2 存 `startedAt`、`restriction`。没有设置和身份要迁移 |
| M13 | 21-1、21-5：发现页（精选）默认隐藏 `restriction` 为 `private`、`paid` 的直播，设置里可以打开；卡片标“私密”“付费”，播放失败时按 `StreamUnavailable` 说明原因。开播时间只在直播中显示。21-4：联合项目的主播在搜索里显示未开播，进房后以详情为准。21-7：画质名“原画”“流畅”进多语言，v3 的 `liveme_quality_source`、`liveme_quality_smooth`、`liveme_quality_hls` 不再用。公告 `liveme_chat_notice` 按上面的新文字翻译。目录说明 `liveme_directory_scope` 建议改为：“这里是 LiveMe 官网的热门直播，往下翻会继续加载。搜索主播名字也能找到没在直播的主播；还可以输入主播的短号，或粘贴 LiveMe 的直播间、主页、分享链接。”英文：“Popular live rooms from the LiveMe website; scroll for more. Searching a name also finds streamers who are not live; you can also enter a streamer's short ID or paste a LiveMe room, profile or share link.”列表去重：精选跨页会重复，按 `identityKey` 去掉已列出的房间（v3 已是这样） |

### 受阻和未核实

没有受阻的条目。没有核实的：

- **付费、私密直播的真实样本**：实测 199 张卡片和样本的 40 张，`ispvt` 都是 0、`livebptype` 是 0 或 4、标签只有 H2H 和 Multi-beam，没有遇到。判断规则来自官网网页端的代码（见 21-1），付费直播的直播信息接口是否照样给地址没有试；受限直播一律不读地址、取流报原因。
- **`livebptype` 为 4**：2 张卡片（含样本的 209683072），网页端只把 7 当作付费，这里同样当作没有限制，能正常播放（S05 就是它）。
- **其他语言的默认标题**：只收了见到的 5 种。见到新的写法时加进 `LiveMeApi.defaultTitles`。
- **24 小时的 `game.live11` 地址过期以后**：实测过期的 3 场都在 `zglive` 上，`game.live11` 的直播没有等到过期；已建立的连接没有一直挂到过期（新建的连接用过期地址都能播，已建立的不会因为到期被断）。

### 新样本

无。实测只用于核对（上面列出的请求和结果），没有存成样本：媒体地址带网宿签名，而 21-8 要的证据（过期地址照常下发、同一场到期时间不变、`vtime` 与到期时间的关系）现有样本 S01、S05 里已经有，测试直接用它们。

### 新增的通用能力

无。

### 测试

本平台 65 个用例（E03.8 是 58 个；新增 7 个，另改写了受影响的对照和取流用例），`live_core` 共 3263 个，门禁 `--all` 通过：

- `liveme_api_test.dart`（38 个）：
  - 对照：S01 两页（默认标题的卡片、开播时间、`none`）、S02 三页（联合项目的状态）、在播和未开播的房间（简介、开播时间、`none`），改变的键用 `changed:` 列出并写原因；
  - 21-1：网页端格式的付费标签、样本里的标签都不是付费、解析不了的标签；精选里私密和付费照常列出并标出；
  - 21-2：空串和不合规的封面、头像、资料图的兜底，`user_info.icon`；
  - 21-3：签名优先、没有签名时的取法、不读 `desc`；
  - 21-4：`is_live` 的各种值、所有项目的 0；
  - 21-5：私密、付费是直播中并标出，分组在直播中，未开播的受限直播是未开播；取流说明原因、不读地址；
  - 21-6：其他主机原样保留、三个主机改 https、写了端口的保留、各种不合规的地址；
  - 21-7：两个画质、线路顺序和编号、旧 id 对照和取流、只有 HLS 或只有流畅；
  - 21-8：线路没有租期；样本里同一场直播的到期时间相同、到期时间是开播后 24 小时、精选里有已过期约 5 小时的地址；
  - 统一原则：`vtime` 和各种坏值、只在直播中；默认标题；坏行只跳过、全坏仍报错；新的公告文字。
- `liveme_site_test.dart`（27 个）：
  - 进房、刷新、录制的开播时间和 `none`，请求与 v3 逐个相同；
  - 21-5：私密、付费（含 JSON 标签）的直播能进房、开播状态为在播、取流说明原因且不多发请求；3.x 存下的“封禁”关注刷新后是直播中并标付费，默认标题用主播名，下播后受限类型和开播时间清掉；
  - 21-7：进房后两个画质、线路与 v3 的地址对应、没有租期、v3 的三个旧 id 都能取流；列表卡片取流 2 个请求，标了私密、付费的卡片不请求；恢复跟到新的直播、两条线路、确认新 id；恢复 v3 的 `source-flv` 时第一条线路就是 v3 的地址。

## 后续（D01 弹幕）

本平台的聊天在 D01.18 做了调查，受阻（要登录），调查结果见 [记录](../../../D-弹幕/D01-平台弹幕协议/D01.18-LiveMe弹幕/record.md)，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文“弹幕留给 D01”等说法是 E 当时的情况。
