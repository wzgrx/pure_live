# T02c.13 FC2 LIVE

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/fc2live/`（`fc2live_api.dart` 纯解析，`fc2live_control.dart` 媒体控制连接，`fc2live_site.dart` 请求编排）；`live_net` 的 `connectIoSocket` 加了可选的 WebSocket ping。
- 样本：`fixtures/fc2live`：
  - 来自归档（2026-09-27 直连录制）：目录 `S01-directory`（63 行：61 个公开房间，其中 5 个受限，2 个两人房）、在播频道 `S02-member-live`、不存在的频道 `S02-member-missing`、控制授权 `S03-control`、控制连接 `control/S04-control`（`frames.jsonl`：加入、HLS 回答、人数、3 条历史评论）、低延迟主列表 `S05-master`、弹幕连接 `danmaku/S06-live`（T06a 用）；
  - 本模块新录（2026-09-28，同一格式，`PHPSESSID` 已替换）：存在但未开播的频道 `S02-member-offline`（10608314）、受限的在播频道 `S02-member-restricted`（3024638，仅限登录）。归档没有这两种回答，而第一种正好暴露了 v3 最大的问题（问题 1）。
- 参考：
  - 归档 v4 的 FC2 适配器和规格（`spec/sites/fc2live.md`）。规格没有 REG-FC2 条目，只有 §10“踩过的坑”；`spec/regressions.md` 里与本平台有关的通用条目是 REG-LEASE-013、REG-LEASE-017、REG-NET-005（见“回归条目的覆盖”）。
  - pure_live_TV `e1cca224`：`lib/platforms/fc2live/` 与 v3 相同，只改了导入路径和可空标注（人数缺值写空串，对照笔记 `small_diffs.txt`、`sub_C.md` 的 fc2live 一节），没有行为修复。TV 的播放器只读 URL，这个平台在 TV 里其实播不了（`sub_C.md` 结论 2）；`sub_C.md` 清单第 1 条“`streams()` 并发开两个控制连接”是归档 v4 的问题，这里没有采用那种由适配器持有连接的做法，不存在这个竞态。

照 T02a.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称、公告和列表内容都按 v3；关注刷新和列表的请求不比 v3 多。

## 做法

- **接口和输出沿用 v3**：`LiveSite` 和 v3 实现过的全部可选能力——目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，键 `fc2live_directory_scope`）、可取消的搜索、关注刷新、录制详情、取流（`LivePlayUrlResolver`）、恢复（`LivePlayRecoveryResolver`），外加 `LiveSiteLinks`。3.x 的 JSON 不变。
- **请求照 v3**：
  - 全部是表单 POST，带 v3 的请求头（Chrome 140 UA、`Accept`、`Accept-Language: ja,en-US;q=0.9,en;q=0.8`、`Origin`、`Referer: https://live.fc2.com/`、`X-Requested-With`、`Content-Type: …; charset=UTF-8`），**不跟随跳转**，以 `fc2live` 的名义发出，代理由应用按平台注入；
  - 匿名：v3 的 FC2 没有 Cookie、没有登录，所以不注入 `CookieVault`；
  - 目录、推荐、分区房间、关键词搜索都来自同一个 `contents/allchannellist.php` 快照（一次给出全部在播频道），在本地分页；
  - 房间：`api/memberApi.php`（`channel=1&profile=1&user=1&streamid=<频道号>`），进房、刷新、录制、开播状态各 1 个请求，与 v3 相同；
  - 取流不发请求，得到配方；播放和录制打开配方时才请求 `memberApi.php`、`getControlServer.php`（表单与 v3 逐项相同，含 `client_version=2.1.0\n [1]`）并连控制 WebSocket。
- **快照的复用照 v3**：不带取消令牌的调用（推荐、分区房间、`searchRooms`）共用一份快照 20 秒；带令牌的调用（v3 的目录页和搜索页总是带）每次都重新请求，不碰共用的那份。v3 在第一份回答到达前，每个调用各发一次请求；现在共用进行中的那一次（只减少请求）。失败的请求不缓存。
- **目录、推荐、搜索照 v3**：
  - 一个分类 `FC2 Live`（id `fc2live`），六个分区（`areaType: public`）：`all` 全部公开直播、`1` 闲聊、`2` 游戏 / 作业（含 category 3）、`4` 视频、`9` 音频、`5` 其他。分区名写 3.x `zh.json` 的中文，界面按分区 id 翻译（M13）；
  - 只收 `type` 为 1 的公开房间，按站点顺序，同一频道只留第一行；**受限房间（`pay`、`login`、`tid` 不为 0）照 v3 留在目录里，状态“未知”，公告写明受限**；
  - 原生目录每页 20 个；`getRecommendRooms`、`getCategoryRooms`、搜索按 v3 的 `_page` 切片：页码或条数小于 1、条数超过 100 都给空；
  - 搜索没有平台接口：频道号或频道链接走 `memberApi` 精确查找（只有第 1 页，未开播也能找到）；其他关键词在快照里按频道号、名字、标题、卡片上的分区名（包含，忽略大小写）过滤。以 0 开头的数字不是频道号，按包含匹配（v3 同样）。
- **卡片和房间照 v3**：
  - **房间号就是频道号**：v3 的详情返回请求时的频道号（去掉空白，链接取其中的频道号），并核对回答里的 `channelid` 与它相同；列表的房间号是行里的 `id`。3.x 存下的关注都是频道号；
  - 标题是 `title`，没有时用名字，再没有时用频道号；名字是 `name`（详情是 `profile_data.name`，没有时 `tname`），没有时用频道号；空白合并成一个空格；
  - 封面只收 `fc2.com` 及其子域的 https 地址，**头像也用封面**（v3）；
  - 卡片的分区名是 v3 的英文（`Idle Chat`、`Game / Work`、`Video`、`Other`、`Audio`，其他值 `FC2 Live`），详情的分区名是回答里的 `category_name`（日文，`雑談`）；
  - 在线人数 `count`（口径 `onlineViewers`，缺值时口径未知、人数为空），累计 `total`；
  - 状态：`is_publish` 为 1 是直播中，其他值是未开播；直播中而 `fee`、`login_only`、`ticketid`、`ticket_only`、`is_limited` 任一不为 0 是受限，显示为“未知”；
  - 公告：受限的写受限说明，成人房间写成人说明，其余写“远端聊天尚待接入”（3.x `zh.json` 的原文）；
  - 每个房间带 `Fc2LiveRoomData`（频道号、状态、分区号、成人标记，不写进 JSON）：界面用它显示自己语言的公告和分区名（M13），取流用它在不发请求时就拒绝受限房间；
  - 不再写 `httpHeaders`（见差异 7）。
- **严格校验照 v3**：目录的 `time` 要是正整数，最多 1000 行，每行是对象、`type` 是整数；公开行的频道号、`pay`、`login`、`tid`、`category`（0～99）、名字或标题、人数的类型都要对，否则整个目录 `ApiChanged`。详情同样逐项检查（状态、五个受限标记、`adult`、`category`、文字字段的类型、`version` 最长 256）。图片不合规只丢图片，负的人数当作没有。回答超过 4 MiB（按 UTF-8）是 `ApiChanged`。
- **取流是会话型输入，照 v3 用“配方”，不是线路**：
  - FC2 的 HLS 由一个媒体控制 WebSocket 授权：变体列表在控制连接关闭后就 403（规格 §6.3 实测），授权约一分钟后失效（`control_disconnection` 4500）。线路的一组固定请求头和有效期表达不了“播放期间一直开着一条连接”，所以本平台不给 `LivePlayUrlResolution.lines`，也没有 `PlayLease`；
  - 画质只有 v3 的一档：`auto`“自适应 HLS”（`zh.json` 原文），不发请求；
  - 取流：返回 `LivePlayUrlResolution.owned(Fc2LiveInputRecipe(频道号))`，身份 `fc2live:<频道号>:auto`（v3 的写法），确认的画质是 `auto`；恢复相同；
  - 播放和录制按配方各自调用 `Fc2LiveSite.openControl` 取新授权、开控制连接、读它给出的主列表，媒体请求带 `Fc2LiveControl.mediaHeaders`（v3 `Fc2Api.mediaHeaders` 的值：UA、`Origin`、`Referer: https://live.fc2.com/<频道号>/`），播放期间保持连接（T04、T08a.1）。
- **控制连接**（`Fc2LiveControl`，3.x 的 `Fc2ControlSession`）：
  - 授权（`controlGrant`）：先读 `memberApi`，未开播 `StreamUnavailable`、受限 `NeedsLogin`，都不发第二个请求；再请求 `getControlServer.php`，`status` 不为 0 是 `StreamUnavailable`；地址必须是 `wss://`、`live.fc2.com` 或其子域、路径 `/control/channels/<频道号>`、没有用户名、查询和片段，`control_token`、`orz_raw` 长度和字符按 v3 检查；
  - 连接：`<地址>?control_token=…`，握手带 `Origin`、UA 和 `Cookie: l_ortkn=<orz_raw>`（v3）；经 `live_net` 的 `SocketConnector` 按 `fc2live` 的代理路由连接，与 HTTP 同一出口；WebSocket ping 每 15 秒（v3，见“新增的通用能力”）；
  - 协议照 v3：收到 `connect_complete` 后发一次 `{"name":"get_hls_information","arguments":{},"id":1}`（逐字相同），回答里 `playlists` 的 mode 0 主列表就是输入（https、`live.fc2.com` 或其子域、`/a/stream/<频道号>/0/master_playlist`，查询只能有 `c`、`d`、`targets`）；只收 2 MiB 以内的文本帧；
  - 结束：`control_disconnection`、连接断开、出错、二进制或不合规的帧都结束控制连接，`done` 给出原因（断开和 `control_disconnection` 是 `NetworkFailure`，可以重试），不用用过的授权重连；关闭最多等 2 秒；
  - 启动（握手到拿到主列表）总共最多 20 秒（见问题 10）；取消令牌同时作用于两个请求和连接，但只管打开的过程，打开之后由拥有者关闭（v3 同样）。
- **没有弹幕参数、没有登录**：v3 的 FC2 是 `EmptyDanmaku`，没有账号和 Cookie 设置，所以不注入 `CookieVault`，也不输出弹幕参数类。评论走同一种控制连接，T06a 用公开的 `controlGrant` 自己取授权（升级候选 3）。

## 审查发现的 v3 问题

位置简写（都在 `legacy/lib/` 下）：`A` = `core/site/fc2live/fc2_api.dart`，`S` = `fc2_site.dart`，`C` = `fc2_control_session.dart`，`HI` = `recorder/services/fc2_hls_input.dart`，`PI` = `player/core/fc2_playback_input.dart`，`phr` = `player/core/playback_header_resolver.dart`。“按 v3 保留”的，改法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | **所有未开播的频道都报“结构变化”**：关注的 FC2 频道下播后刷新失败，永远显示不出“未开播”；进房、录制详情、开播状态、按频道号搜索同样失败。搜索能力表写着“直播和未开播”、目录说明写着“精确频道号也可解析未开播房间”，实际都做不到 | A:265、A:354-358、A:391-395 | `parseMember` 要求 `version` 非空，而站点对每个不在播的频道都回答 `version: ''`（`S02-member-offline`；2026-09-28 另查 29745829 也是如此）。`version` 只有控制授权需要，却在每次解析时检查 | 解析时 `version` 可以为空；只在取授权时要求（在播却没有 `version` 是 `ApiChanged`）。未开播按 v3 自己的映射（`is_publish` 不为 1）显示为未开播 |
| 2 | 不存在的频道也报“结构变化”，搜索这个频道号时整页出错 | A:251；S:183-192 | 站点对不存在的频道也回答 `status: 1`，只是 `profile_data.userid` 为空（`S02-member-missing`）；v3 只把 `status` 不为 1 和 HTTP 404 当作不存在，搜索里“不存在就返回空”的分支从未触发，错误落到问题 1 的检查上 | `profile_data.userid` 为空是 `NotFound`（归档 v4 的判断）；搜索得到空列表（v3 的本意） |
| 3 | 错误没有类型：9 种 `Fc2Failure`；调用方传错页码、分区也报 `schema`、`identity` | A:11-20、A:431-442；S:89-99、S:145 | 平台自己的异常类型 | 类型化错误：401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，400/422 和结构不符 `ApiChanged`，5xx、跳转和其他状态 `NetworkFailure`，不能播 `StreamUnavailable`/`NeedsLogin`；页码和分区错误是 `ArgumentError`，同 v3 一样不发请求 |
| 4 | 平台层依赖全局 HTTP 单例，自己实现流式读取（4 MiB、严格 UTF-8、20 秒）和 25 秒总时限、取消 | A:82、A:107-149、A:151-168 | 结构问题 | 注入 `LiveHttp`（20 秒由请求超时负责）；解析前仍按 4 MiB 检查；非法 UTF-8 按替换字符处理 |
| 5 | 平台层调用界面翻译：分区名、公告、画质名按当时的界面语言写进房间，随关注一起存下 | S:11、S:78-83、S:133-137、S:248 | `i18n` 写在适配器里 | 写 3.x `zh.json` 的中文（与 3.x 中文界面存下的相同）；状态和标记放进 `Fc2LiveRoomData`，由界面翻译（M13） |
| 6 | 只有进房得到的房间能取画质：刷新得到的房间、列表卡片直接播放报 `schema`；受限房间也是 `schema`；未开播得到空列表，播放器拿不到原因 | S:139、S:235-249 | 画质检查要求 `data` 是进房时放进去的 `Fc2Room`（只有进房和录制详情、且在播时才放） | 每个房间都带 `Fc2LiveRoomData`；在播就给出 `auto`；未开播 `StreamUnavailable`，受限 `NeedsLogin`，状态未知 `StreamUnavailable`，都不发请求 |
| 7 | 媒体请求头写进每个房间的 `httpHeaders`，随关注存下，但没人读 | S:138；A:98-102；phr:143-148、HI:80 | `httpHeaders` 是 IPTV 的字段，播放层只在 IPTV 分支读它；FC2 的中继直接用 `Fc2Api.mediaHeaders` | 房间不再写；请求头在控制连接上（`Fc2LiveControl.mediaHeaders`），值与 v3 相同 |
| 8 | 并发的调用各自请求快照 | S:44-66 | 缓存只在回答到达后才生效（`_directoryAt` 在完成时才写，S:55） | 共用进行中的请求（只减少请求，内容相同） |
| 9 | 目录翻页和搜索每一页都重新下载全部在播频道，各页来自不同的快照（房间会重复或漏掉） | S:45；`common/base/live_directory_controller.dart`、`modules/search/search_controller.dart` 总带取消令牌 | 带取消令牌的调用绕过 20 秒缓存 | 按 v3 保留（请求数和列表内容都不变），升级候选 1 |
| 10 | 控制连接的启动最坏要 60 秒才报错 | C:112-124、C:145-155 | 握手（20 秒）、`connect_complete`（20 秒）、主列表（20 秒）各有自己的时限，依次相加 | 从握手到拿到主列表总共 20 秒（录下的对话里主列表 245 毫秒就到） |
| 11 | 控制连接出错后不主动断开：收到 `control_disconnection`、坏帧后只标记“不可用”，连接、订阅和 HTTP 客户端要等消费方轮询到 `isClosed` 再关闭 | C:72-77、C:98-99 | 失败只改标志 | 出错即结束并关闭连接，`done` 给出原因；消费方据此重新获取（T04、T08a.1） |
| 12 | 控制连接在平台层直接用 `dart:io` 和调用方传入的全局代理函数 | C:145-155；HI:40；PI:173 | 结构问题 | 经 `live_net` 的 `SocketConnector` 和 `ProxyPolicy` 按 `fc2live` 路由（与 HTTP 同一出口，REG-NET-005）；ping 由 `connectIoSocket` 提供 |
| 13 | HLS 回答的 `status` 不为 0 报 `access`，和 HTTP 403、受限频道混在一起 | C:162 | — | `StreamUnavailable`（归档 v4 的判断；受限频道在授权前已经报 `NeedsLogin`） |
| 14 | 标题、名字里的 HTML 实体原样显示（`Clubs, Events &amp; Festivals`，样本 S01、`S02-member-restricted`） | A:236-237、A:269-270 | 没有解码 | 按 v3 保留（同 SOOP、CHZZK 等），升级候选 4 |
| 15 | 头像用的是直播截图 | S:124 | `avatar: room.cover`；详情里其实有 `profile_data.icon`/`image`（`S02-member-restricted`） | 按 v3 保留，升级候选 5 |
| 16 | 简介解析了却没用上 | A:271；S:118-140 | `Fc2Room.description` 没有传给 `LiveRoom` | 详情带简介（v3 缺的数据，差异 3） |
| 17 | 同一个房间，列表上的分区名是英文（`Idle Chat`），进房后是日文（`雑談`）；关注卡片刷新后分区名换了语言 | A:241、A:274 | 目录用写死的英文名，详情用回答里的 `category_name` | 按 v3 保留（`Fc2LiveRoomData` 带分区号，界面可以统一翻译），升级候选 6 |
| 18 | 目录里任一行字段不对，整个目录、推荐、分区、搜索全部失败 | A:216-248 | 逐行严格检查 | 按 v3 保留（样本里全部合格），升级候选 7 |
| 19 | 纯数字关键词总被当作频道号精确查找，搜不到频道号的一部分（除非以 0 开头） | S:183-192 | 先认频道号 | 按 v3 保留 |

## 样本与 v3 的冻结输出

归档没有 FC2 的 `expected.json`（归档的旧版对照工具只做了前五个平台，v3 应用也构建不了）。本模块用 `fixtures/fc2live/legacy_expected.dart` 生成，做法同 T02c.6 SHOWROOM：

- 把 v3 的 `Fc2Api`、`Fc2Link`、`Fc2Site`、`Fc2InputRecipe` 和 `Fc2ControlSession.parseHlsResponse` 原样搬进一个 Dart 脚本。v3 本来就把传输做成可注入的函数（`Fc2Request`），所以只换了它：按路径和表单字段读样本、给出录下的状态码，没有样本的请求让脚本失败；只在网络路径上的 `_defaultRequest`、`_readBody` 没有搬。控制连接的 WebSocket 部分要实时连接，没有搬，只用它的消息解析器读录下的 `_response_` 帧；
- `i18n` 换成用到的十个键的中文；Dio 的取消令牌、v3 的 `withRequestCancellation`、`LiveRoom`、`LiveArea`、`LiveCategory`、`LivePlayQuality`、`LivePlayUrlResolution`、`LiveDirectoryPage`、`LiveInputRecipe` 只搬用到的部分（包括 `toJson` 里 v3 的 `HttpHeaderPolicy.normalize`）；
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），每个入口另记请求；房间投影另记 `data` 的类型（v3 只在进房、在播时放 `Fc2Room`）。运行：`dart run fixtures/fc2live/legacy_expected.dart`。

7 个样本有 `expected.json`：

| 样本 | 内容 |
|---|---|
| `S01-directory` | 分类（第 1、2 页，条数 0）；原生目录（全部 4 页、6 个分区各两页、第 0 页、分区 3、别的平台）；推荐的 9 种切片；分区的 9 种切片；6 个关键词、`fc2user` 每页 5 条翻 3 页、5 个精确查找（频道号、带语言前缀的链接、不存在、未开播、受限，用 S02 的回答）、空白、无效切片的搜索；20 秒缓存 |
| `S02-member-live` | 进房、刷新、录制、开播状态、按链接进房；画质、取流（`auto` 和别的画质）、恢复、`getPlayUrls`、刷新得到的房间取画质；与 `S03-control` 一起的控制授权；22 个输入的 `Fc2Link.parseChannelId`、`channelUrl`、媒体请求头、配方身份 |
| `S02-member-restricted` | 同上（受限：状态未知、开播状态和取流被拒、授权 `access`） |
| `S02-member-offline`、`S02-member-missing` | 各入口的错误（v3 都是 `schema`，问题 1、2） |
| `S03-control` | 授权的地址、令牌、`orz`；别的频道 |
| `control/S04-control` | `_response_` 帧解析出的主列表；v3 发出的请求帧；别的频道 |

`S05-master`（主列表正文，v3 在录制层的中继里读）、`danmaku/S06-live`（T06a）没有 `expected.json`。

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；另比较请求（路径和表单）。

| 样本 | 结果 |
|---|---|
| S01 分类 | 一致：1 个分类 `FC2 Live`，6 个分区，id、名称、`areaType`、`typeName` 一致。v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S01 目录、推荐、分区 | 全部 4 页（20、20、20、1）和 6 个分区各两页的房间、顺序、每个字段（标题、名字、封面兼头像、英文分区名、在线、累计、状态、受限房间的“未知”和公告）、页码和“还有下一页”都一致，只差 `httpHeaders`（差异 7）；推荐和分区的切片一致；请求一致，只有 v3 先请求再给空的无效切片现在不发请求 |
| S01 搜索 | 关键词（名字、标题、英文分区名、`fc2user` 三页、带前导 0 的数字、无结果）的房间和请求都一致；精确查找在播和受限频道的房间一致（受限频道多了简介），各 1 个请求；未开播和不存在的频道 v3 报错，现在分别得到未开播的房间和空列表（问题 1、2） |
| S02 在播 | 进房、刷新、录制、按链接进房的房间一致，房间号都是 `62996200`，各 1 个请求；开播状态一致；画质“自适应 HLS”（`auto`）一致；取流、恢复都是没有地址的配方 `fc2live:62996200:auto`，确认的画质 `auto`；控制授权的两个请求（表单逐项）和地址、令牌、`orz` 一致；刷新得到的房间 v3 取画质报 `schema`，现在可以播放（问题 6） |
| S02 受限 | 三种深度的房间一致（状态未知、受限公告、实体原样），只差 `httpHeaders` 和简介；开播状态、取画质、授权 v3 分别是 `access`、`schema`、`access`，现在是 `NeedsLogin`（取画质不发请求，授权只发 `memberApi`） |
| S02 未开播、不存在 | v3 全部是 `schema`；现在分别是未开播的房间和 `NotFound` |
| S02 链接 | 22 个输入全部一致 |
| S03、S04 | 授权和主列表一致；换成别的频道都被拒绝（v3 `schema`，现在 `ApiChanged`）；请求帧逐字相同 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | **未开播的频道显示为未开播**（进房、刷新、录制详情、开播状态、按频道号搜索） | 问题 1。v3 在这里全部报“结构变化”，用户看到的是加载失败；状态按 v3 自己的映射（`is_publish`），不是新的分组。这是用户能看到的变化，请确认 |
| 2 | 不存在的频道是 `NotFound`，按频道号搜索得到空列表 | 问题 2。v3 的本意 |
| 3 | 详情带简介（`channel_data.info`，空白合并） | 问题 16。v3 解析了却没传；列表卡片没有简介（目录不给），与 v3 相同 |
| 4 | 出错抛类型化错误，调用方错误是 `ArgumentError`，都不发请求 | 问题 3。界面看到的仍是加载失败（M13 用 `pendingAfterError`），状态和分组不变 |
| 5 | 列表卡片和刷新得到的房间也能直接播放；未开播、受限、状态未知的房间在取画质时就报原因 | 问题 6。画质仍只有 `auto` 一档 |
| 6 | 共用进行中的快照请求；无效切片不发请求 | 问题 8。只减少请求 |
| 7 | 房间不再写 `httpHeaders`；媒体请求头在控制连接上 | 问题 7。值与 v3 相同；3.x 存下的旧值照读，`mergeFrom` 照留（非 IPTV 不覆盖），不影响播放 |
| 8 | 控制连接从握手到主列表总共 20 秒；出错即关闭并给出原因；HLS 回答被拒是 `StreamUnavailable` | 问题 10、11、13 |
| 9 | 控制连接与 HTTP 走同一平台路由，由 `live_net` 提供 ping | 问题 12 |
| 10 | 不再逐字节限制下载大小和严格 UTF-8；解析前仍按 4 MiB 检查 | 问题 4。传输由 live_net 统一负责，20 秒请求时限；非法 UTF-8 按替换字符处理 |
| 11 | 房间多带 `Fc2LiveRoomData`（频道号、状态、分区号、成人标记），不写进 JSON | 问题 5、6，给界面翻译公告和分区、给取流判断受限用 |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

- **只有一档“自适应 HLS”，取流是配方，播放和录制各自持有控制连接**。归档 v4 给出高画質、標準、低画質三档，每档用高延迟一族的变体列表，控制连接由适配器持有、按 60/150 秒的租期续期（规格 §5、§6.3），会改变画质菜单和播放方式；对照笔记 `sub_C.md` 还指出它同一频道并发取流会开两个连接、先开的没人管。列为升级候选 2。
- **受限房间留在目录里，状态“未知”，公告写明受限**（v3 和上游 TV）。归档 v4 从目录里去掉受限房间，详情标成直播中。
- **目录按站点的顺序，每页 20 个**。归档 v4 按在线人数排序，一次给出一页全部。
- **分区 id 是 `all`、`1`、`2`、`4`、`9`、`5`，名称用 3.x 的中文，分类名 `FC2 Live`**（3.x 存下的关注分区要对得上）。归档 v4 是 `1`、`2,3`…，日文名，分类名“FC2ライブ”。
- **有关键词搜索**（在快照里过滤，频道号和链接精确查找）。归档 v4 没有搜索；上游 TV 与 v3 相同。
- **快照缓存 20 秒**（v3、上游 TV）。归档 v4 每次都重新请求。
- **严格校验**：目录一行不对整个失败，详情逐项检查（v3 的测试和上游 TV 同样）。归档 v4 跳过坏行，宽松处理缺失的字段。
- **`status` 不为 1 是 `NotFound`，`is_publish` 不为 1 就是未开播**（v3 的映射）。归档 v4 把两者都当作 `ApiChanged`。
- **未开播的房间照 v3 的写法带人数**（样本里是 0）。归档 v4 只在直播时给人数；列为升级候选 8。
- **头像用封面、标题和名字不解码 HTML 实体**（v3）。归档 v4 用 `profile_data.image`/`icon`，解码实体。
- **卡片的分区名是英文**（v3）。归档 v4 用日文。
- **控制握手带 UA**（v3、上游 TV）。归档 v4 不带（笔记 `sub_C.md` 建议补上）。
- **媒体请求头的 `Referer` 是频道页**（v3）。归档 v4 是站点首页。
- **没有评论**：归档 v4 做了控制连接上的评论，v3 没有，列为升级候选 3。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 目录翻页和搜索翻页共用同一份快照（例如 20 秒内），下拉刷新时再取新的 | 每一页都重新下载全部在播频道，各页来自不同的快照，房间可能重复或漏掉 | 问题 9；T02c.6 SHOWROOM 同类候选 |
| 2 | 分高、标准、低三档，每档播单个变体列表（优先高延迟一族），控制连接按租期共享 | 只有“自适应 HLS”，经中继播主列表 | 归档 v4 规格 §5（ffmpeg 直接打开主列表会同时拉全部变体、卡住）、§6.3；样本 `S05-master`、`control/S04-control` 有全部列表；需要 T04 的中继配合，注意 `sub_C.md` 指出的并发竞态 |
| 3 | 评论（弹幕）：自己取授权、开控制连接，收 `comment`，丢掉 `history: 1` 的历史评论，每 30 秒 `heartbeat`；`user_count` 更新人数 | 没有评论，公告写“远端聊天尚待接入” | 归档规格 §7；样本 `danmaku/S06-live` 已复制；`controlGrant` 已公开（T06a） |
| 4 | 标题、名字解码 HTML 实体 | 显示 `&amp;` | 问题 14；样本 S01、`S02-member-restricted` |
| 5 | 头像用 `profile_data.icon`（没有时用封面） | 头像是直播截图 | 问题 15；`S02-member-restricted` 有 `smallicon`/`largeicon` |
| 6 | 分区名统一：按 `Fc2LiveRoomData.categoryId` 由界面翻译，或都用站点的日文名 | 列表英文、详情日文 | 问题 17 |
| 7 | 目录里单行坏数据只跳过这一行 | 整个目录失败 | 问题 18；归档 v4 |
| 8 | 未开播的房间不显示人数 | 显示 0（v3 的写法，v3 本身显示不出未开播） | 归档 v4 |
| 9 | 受限房间在目录里另外标明（或隐藏），详情标成直播中、播放时提示需要登录 | 状态“未知”，播放报需要登录 | 归档 v4 规格 §2、§4 |

## 回归条目的覆盖

归档规格没有 REG-FC2 条目。§10“踩过的坑”和 `spec/regressions.md` 里涉及本平台的通用条目，属于平台层的部分都有测试：

- **变体列表 403（控制连接在第一次请求变体前就关了）**：控制连接只在拥有者关闭、服务器断开、授权失效或出错时结束；人数、评论、之后再来的回答都不影响它；两个拥有者各有各的连接（关闭一个不影响另一个）。播放和录制在播放期间持有它由 T04、T08a.1 负责。
- **重连后立即被断开（授权约 60 秒后 4500）**：控制连接从不用用过的授权重连；每次 `openControl` 都重新取授权（每次两个请求）；`control_disconnection` 结束连接，原因是可重试的 `NetworkFailure`。
- REG-LEASE-017（会话型输入不导出私有地址）：取流结果没有地址（`urls` 为空，`inputRecipe` 只有频道号），房间 JSON 里没有授权、令牌和主列表；同一频道打开两次得到两个独立的授权和连接。
- REG-NET-005（代理出口轮换导致 403）：接口请求和控制连接都按 `fc2live` 的路由（测试核对连接用的是代理策略给 `fc2live` 的路由）；HTTP 403 是 `RiskControl`，不当作接口变化。媒体请求走同一路由由 T04、T08a.1 负责。
- REG-LEASE-013（FC2 播放列表没有 `.m3u8` 后缀）：属于中继，随 T08a.1（v3 `ffmpeg_hls_input_relay_test.dart` 的 FC2 用例）；本模块保证主列表地址原样给出（`/a/stream/<频道号>/0/master_playlist?…`）。
- **旧弹幕刷屏（加入时推送 30 条历史）**：属于评论，随 T06a。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 按配方打开输入：`openControl`，播放期间保持控制连接，`done` 完成时结束并重新获取；主列表经中继播放（没有 `.m3u8` 后缀按内容识别），媒体请求带 `control.mediaHeaders`（3.x 的 `Fc2HlsInput`、`Fc2PlaybackInput`、`live_input_playback_binding.dart:17`、`live_input_recording_binding.dart:29,44-52`、`ffmpeg_hls_input_relay.dart:83`） | T04 播放、T08a.1 录制 |
| 投屏和复制直链遇到会话型输入时提示“需要会话”（REG-LEASE-017） | T12c.1、M13 |
| 评论（弹幕）连接 | T06a（升级候选 3）；`getDanmaku()` 同 T02a.1，用“平台 → 弹幕连接”的表 |
| 目录说明 `fc2live_directory_scope`、分区名 `fc2live_category_*`、公告（`fc2live_chat_notice`、`fc2live_access_restricted`、`fc2live_adult_notice`）、画质名 `fc2live_quality_auto`、平台名 `site_fc2live` 的多语言，按 `Fc2LiveRoomData` 和分区 id 显示 | M13 |
| 搜索能力表：直播和未开播、可翻页、没有网页搜索（3.x `search_capability.dart:81-85`） | M13 搜索页 |
| 外部打开 `https://live.fc2.com/<频道号>/`，先用 `Fc2LiveApi.channelId` 检查存下的房间号，无效时不拼地址（3.x `room_external_opener.dart:127-128`） | M13 |
| 网页搜索结果的房间识别（3.x `web_search_room_parser.dart:106-109`），用 `roomIdFromUrl` | M13 |
| 本地互动的平台包（3.x `local_interaction_controller.dart:458-459`） | M13 |
| 3.x 设置迁移：热门平台列表第 31 版追加 FC2（`favorite_room_controller.dart:87`，测试 `fc2live_catalog_migration_test.dart`）；3.x 关注里存下的 FC2 `httpHeaders` 可以在迁移时丢掉 | T09b.1 |
| 人数口径（在线 `count`、累计 `total`，3.x `live_room.dart:177-183`） | 已在 T02g.1 的 `audience.dart` |
| 平台注册、每个平台都能录制的约定（3.x `recording_platform_contract_test.dart`） | T08a.1、T07a.1 |

## 新增的通用能力

- `live_net` 的 `connectIoSocket` 加了可选参数 `pingInterval`：设置 `dart:io` WebSocket 的 ping 间隔（收不到 pong 时自己关闭）。v3 的 FC2 控制连接每 15 秒 ping 一次，`live_net` 原来没有这个能力。只是加了一个可选参数，现有的 `SocketConnector` 和调用方不受影响。新增两个测试（经 TCP 中转观察客户端发出的帧：设置时发 ping 帧，不设置时不发）。
- `live_core.dart` 按字母顺序加了三行导出。其余用到的 `LiveDirectoryPage`、`LiveInputRecipe`、`LivePlayUrlResolution.owned`、`jsonString`、`live_net` 的 `SocketConnector`/`ProxyPolicy` 都已存在。

## 测试

新增 58 个用例（`live_core` 共 2238 个），另有 `live_net` 的 2 个，全部通过：

- `fc2live_api_test.dart`（22 个）：逐个样本对照 v3 的输出（分类、全部目录页、推荐和分区切片、关键词搜索、精确查找、在播和受限频道的各种深度、画质、配方、媒体请求头、授权、HLS 回答、22 个链接），有意的差异逐条断言（`httpHeaders`、简介、未开播、不存在）；移植 v3 `fc2live_site_test.dart` 的目录、详情、授权载荷；v3 的逐项检查：目录的 15 种坏回答、6 种不合规的图片、负数和字符串人数、重复频道、两人房；详情的五个受限标记及其与未开播的先后、`is_publish` 取值、名字和标题的兜底、分区名兜底、空白合并、成人和受限公告的先后、空 `version`、不存在的两种写法、12 种坏回答；授权的 13 种不合规；HLS 回答的跳过规则和 20 种不合规；状态码映射、非 JSON、4 MiB 上限；配方。
- `fc2live_site_test.dart`（36 个），用样本回放、少量合成回答和录下的控制连接对话（假 WebSocket）：
  - v3 的请求头、表单、不跟随跳转、平台名；能力、目录说明、没有弹幕；传输错误和状态码的映射；
  - 快照：20 秒共用（手动时钟）、带令牌的调用每次重新请求且不碰共用的那份（与 v3 的 `cache` 请求一致）、并发共用、失败不缓存；
  - 分类不发请求；全部目录页和请求与 v3 一致；调用方错误和无效切片不发请求；切片与 v3 一致；
  - 搜索：关键词和翻页与 v3 一致；频道号、链接、受限频道各 1 个请求；未开播和不存在；空白、第 2 页、无效切片不发请求；取消令牌传到请求、取消后不发请求、回答晚于取消被丢弃；
  - 房间：三种深度各 1 个请求、房间号是频道号（含链接和空白）、非频道号不发请求；未开播、受限、不存在；与 3.x 存下的关注合并；
  - 取流：进房、刷新、卡片得到的房间都能取画质，不发请求；配方、恢复、确认的画质；未开播、受限、状态未知、别的平台、非频道号、别的画质都在请求前被拒；
  - 授权：请求和结果与 v3 一致；未开播、受限、不存在只发 `memberApi`；在播却没有 `version`；授权被拒；
  - 控制连接：录下的对话（握手地址、令牌、请求头、代理路由、启动时限、请求帧逐字相同、主列表、媒体请求头、关闭）；请求只发一次且在 `connect_complete` 之后；请求前到达的回答不算数；打开后 6 种结束方式；人数、屏蔽词、之后的回答不影响连接；HLS 回答被拒和没有主列表；静默超时、握手失败；打开前和打开中取消、晚到的握手被关闭、打开后取消不影响连接；两个拥有者各有各的连接、房间里没有私有数据（REG-LEASE-017）；关闭有时限；
  - 链接（经 `LinkParser`）：频道链接、带语言前缀和查询的链接、分享文本，站点页面、别的主机、带片段的链接和纯数字不识别，不发请求。

## 升级落地（T02.U）

- 日期：2026-09-29（T02c.13）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 9 行（26-1～26-9）；“落地方式”只有 26-1（同 19-1，20 秒）、26-7（开发预填：只在 v3 原本失败的地方生效）、26-9（模型部分已完成）写了，其余按上面“后续升级候选”的原文做。26-2 另有主会话的补充决定（2026-09-29，用户已授权主会话判断）：实测发现的 40、50 两档（2 Mbps、3 Mbps β）一并列出，排在 30 之上，名字照平台叫法译成中文，频道没有时不列出。模型字段按 [T02g.2](../../T02g/T02g.2/record.md)。26-3（评论）的连接属于 T06a，26-2（三档画质）的播放要 T04 的中继，这里只做平台层能给的部分。
- 只改了本平台：`fc2live_api.dart`（解析）、`fc2live_control.dart`（控制连接）、`fc2live_site.dart`（请求编排）和两份测试，另加一个样本（见“新样本”）。没有改 `live_core` 的通用文件，没有新依赖。
- 实测：2026-09-28 19:50～20:10 UTC 直连、匿名，用新适配器实际走了一遍（临时脚本，没有提交）：
  - 目录 57 行（56 个公开房间），第 1、2、3 页 20、20、16 个，一共 56 个没有重复，只发了 1 个请求；关键词搜索第 1、2 页也只 1 个请求；
  - 5 个受限房间都是 `login` 1 或 2（没有 `pay`、`tid`），都显示为直播中 + `needsLogin`，取画质报 `NeedsLogin`；卡片都有开播时间，分区名是中文；
  - 进房 10200498、10506791：有开播时间、`none`、弹幕参数；头像分别是 `smallicon`（`icon`）和 `largeicon`（`icon` 为空时的 `image`）；打开控制连接，`30` 播 `/31/playlist`（高延迟一族），`auto` 播 `/0/master_playlist`（v3 的主列表）；
  - 10200498 的 HLS 回答除了 10、20、30、90 还有 40、50（网页播放器叫 2Mbps、3Mbps(β)），10506791 没有。20:47 UTC 录下 10200498 的控制连接（`control/S07-control-hd`）：推流是 1920×1080，三族列表各有 0、10、20、30、40、50、90 七个 mode，主列表的 `targets` 是 `10,20,30,40,50,90`；用补充后的适配器取画质得到 50、40、30、20、10、自动六档，`50` 播 `/51/playlist`。
- 另查了网页脚本（`channelListManager.bundle.js`、`liveView.bundle.js`，首页和频道页的文案）确定各字段的含义：
  - 目录卡片的受限标记按 `pay` 1（按分钟付积分）→ `tid`（门票、付费节目）→ `login` 1（“ログイン限定番組”）→ `login` 2（“ポイント所持ユーザー限定番組”：持有积分的登录用户，免费看）的顺序标出；
  - 详情的 `is_limited` 是“配信規制中”：被 FC2 限制，网页把标题、简介、头像换成这句话并把观众请出房间；
  - 网页自己对标题、名字、简介做 HTML 解码（`htmlDecode`）；
  - 分区表 `category_list`：0 不明、1 雑談、2 ゲーム、3 作業、4 動画、5 その他、6 プレミアム、7 公式、8 不明、9 音声。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 26-1 | 快照的复用改为（同 19-1，时长用 v3 的 20 秒）：目录（`getDirectoryPage`）和可取消搜索（`searchRoomsCancellable`）的**第 1 页**（下拉刷新）总是重新请求 `allchannellist.php`，成功后作为共用快照；**第 2 页起**以及取分类、推荐和分区切片、不带令牌的 `searchRooms`，都用 20 秒内（`Fc2LiveSite.snapshotLifetime`）的这份快照，不管它是谁取的。带令牌的调用只复用已经到达的快照，否则用自己的令牌单独请求（取消它不会让别的调用失败）；不带令牌的调用照旧共用进行中的请求。失败或取消的请求不留快照，之前的快照照常可用；时钟倒退时不复用。频道号、频道链接的精确查找照旧走 `memberApi`，不碰快照 | 目录和搜索结果往下翻时不再等待网络，每页来自同一份在播列表，不会重复或漏掉房间（v3 每翻一页都重新下载全部在播频道，约 30 KB）；下拉刷新仍取最新的 | 平台层完成，余下 M13 |
| 26-2 | 平台层：画质改为分档加 v3 的一档，全部可能的画质按顺序是 `50`“超清 3M（β）”、`40`“超清 2M”、`30`“高清”、`20`“标清”、`10`“流畅”、`auto`“自适应 HLS”（`Fc2LiveApi.qualities`，`sort` 50、40、30、20、10、0）。id 是该档在控制连接 HLS 回答里的 mode（归档 v4 的做法）。名字：50、40 照网页播放器的叫法（`mode50` 3Mbps(β)、`mode40` 2Mbps）译成“超清”加码率；30、20、10 用共用的高、标准、低的中文名（`LiveQualityLabel` 对 high、standard、low 的写法；网页叫 1.2Mbps、400Kbps、150Kbps）。各档都是网站转码的，最高一档也不是原画。`auto` 的 id、名字与 v3 相同，排到最后。<br>**只列频道有的档**：只有控制连接的 HLS 回答说明频道有哪几档（S04 的 62996200 只有 10～30，S07 的 1080p 频道还有 40、50），所以取画质改为探测（`LiveQualityDiscovery`：`getPlayQualities` 即 `discoverPlayQualitiesRaw`）：先照旧在不发请求时拒绝不能播的房间，再打开一条控制连接（`memberApi`、`getControlServer` 和连接）读回答（`Fc2LiveApi.qualitiesOf`：任一族有该档的变体才列出，有主列表才列 `auto`），返回前关闭连接；取消令牌作用于请求和连接。v3 列 `auto` 不发请求，现在多 2 个请求和一条打开即关的连接（见“请求数”）。<br>取流给出 `Fc2LiveInputRecipe(频道号, quality: id)`，身份 `fc2live:<频道号>:<id>`（`auto` 仍是 v3 的 `fc2live:<频道号>:auto`），确认的画质就是请求的 id；别的 id 是调用方错误。<br>控制连接：`Fc2LiveApi.hlsPlaylists` 读出回答里三族列表（低延迟 `playlists`、高延迟 `playlists_high_latency`、中延迟 `playlists_middle_latency`）的全部列表，按 mode 给出；`Fc2LiveApi.playlistFor` 选要播的：一档优先它的高延迟单变体（mode + 1；归档规格 §5：ffmpeg 读主列表会同时拉全部变体而卡住，长分片也更适合中继），没有时退回低延迟、中延迟；频道（此刻）没有这一档时依次退到更低一档、更高一档、主列表；`auto` 播 v3 的低延迟主列表（mode 0），没有时用高延迟、中延迟主列表，再没有就用最好的一档。`Fc2LiveSite.openControl(频道号, quality: …)` 和 `Fc2LiveControl.open(…, quality: …)` 接收画质，打开后 `playlist` 是要播的列表，`quality` 是实际播的画质（退档时与请求的不同），`playlists` 是全部列表（v3 的 `master` 改名为 `playlist`，`auto` 时就是它）。请求和握手与 v3 相同（2 个请求 + 1 条连接） | 画质菜单按频道列出：多数频道是高清、标清、流畅、自适应 HLS，1080p 等高码率推流的频道最前面还有超清 3M（β）、超清 2M；默认第一档。打开画质菜单要先连一次控制连接（约半秒）。要等 T04 的中继能播单个变体列表后才能真正按档播放（见“留给其他模块”） | 平台层完成，余下 T04/M8 |
| 26-3 | 平台层：新类 `Fc2LiveDanmakuArgs(频道号)`，进房和录制详情放在 `danmakuData`（在播、受限、未开播都给；刷新、卡片不给），不多发请求。评论走各自的控制连接，连接自己用公开的 `Fc2LiveSite.controlGrant` 取授权；`getDanmaku()` 仍是 `EmptyDanmaku`，由 T06a 的“平台 → 弹幕连接”表接上 | 平台层看不出变化；评论和用评论更新人数在 T06a 接入 | 平台层完成，余下 T06a |
| 26-4 | 标题、名字（`name`、`profile_data.name`、`tname`）、简介（`info`）解码 HTML 字符（`decodeHtmlEntities`，解码后再合并空白），目录和详情都一样；关键词搜索按解码后的文字匹配 | `Clubs, Events &amp; Festivals` 显示为 `Clubs, Events & Festivals`；搜 `&` 能找到，搜 `&amp;` 不再能 | 完成（T02.U） |
| 26-5 | 详情（进房、刷新、录制、按频道号搜索）的头像用 `profile_data.icon`，没有时用 `profile_data.image`，再没有才用封面；只收 `fc2.com` 及其子域的 https 图片，类型不对、地址不合规只当作没有，不让回答失败。目录卡片没有主播头像，照旧用封面 | 关注列表、房间页显示主播自己的头像，不再是直播截图（设了头像的主播才有） | 完成（T02.U） |
| 26-6 | 卡片和详情的分区名统一为目录分区的中文名（`Fc2LiveApi.areaName`，与分类页的分区名相同，即 3.x zh.json 的 `fc2live_category_*`）：1 闲聊、2 和 3 游戏 / 作业、4 视频、5 其他、9 音频；站点的“不明”（0、8）和目录之外的分类（6 プレミアム、7 公式）没有分区名（v3 卡片写 `FC2 Live`，详情写站点的 `category_name`，如 `ライブ配信`）。详情不再读 `category_name`。`Fc2LiveRoomData.categoryId` 照旧带分区号，界面按它显示自己语言的名字（M13）。关键词搜索匹配显示的中文名，也照旧匹配 v3 的英文名（`Fc2LiveApi.legacyAreaName`），所以 v3 的搜索结果不变；分区号 0 的房间不再因为 `FC2 Live` 被“fc2”“live”搜到 | 同一个房间在列表和进房后的分区名都是“闲聊”，不再一个是 `Idle Chat`、一个是 `雑談`；关注卡片刷新后分区名不再换语言 | 平台层完成，余下 M13 |
| 26-7 | 目录里读不出来的一行只跳过这一行：不是对象、`type` 不是整数；公开行的频道号、`pay`、`login`、`tid`、`category`（0～99）不对，名字、标题、人数类型不对（v3 整个目录 `ApiChanged`，T02c.13 照留）。外壳仍严格：`time` 不是正整数、没有 `channel` 列表、超过 1000 行仍是 `ApiChanged`；有公开行但一行都读不出来也是 `ApiChanged`，接口改版不会显示成空目录；只有非公开行（两人房）是正常的空。<br>控制连接的 HLS 回答同样：一行列表不合规（缺 mode、状态，地址不对、路径与 mode 不符、查询参数不对）或一族列表不是列表、超过 32 行，只少这些列表（v3 整个回答 `ApiChanged`）；一个可用的列表都没有仍是 `ApiChanged`，`arguments.status` 不为 0 仍是 `StreamUnavailable` | 平时看不出变化；站点某一行数据异常时，其他房间照常显示 | 完成（T02.U） |
| 26-8 | 未开播的详情（进房、刷新、录制、按频道号搜索）`watching`、`onlineViewers`、`totalViewers` 留空（v3 写回答里的 0）；人数口径仍是 `onlineViewers`。目录卡片都在播，照旧有人数 | 未开播的房间不再显示“0 人”。关注列表里刚下播的房间合并时会保留上次的人数（T02g.2 的空值不覆盖），要由界面在未开播时不显示人数 | 平台层完成，余下 M13 |
| 26-9 | 受限的直播（目录 `pay`、`tid`、`login` 不为 0；详情 `fee`、`ticketid`、`ticket_only`、`login_only`、`is_limited` 不为 0）状态改为直播中，填受限类型（`Fc2LiveApi.directoryRestriction`、`memberRestriction`，按网页标记的先后）：`is_limited`（配信規制中）→ `unplayable`；`pay`、`fee`、`tid`、`ticketid`、`ticket_only` → `paid`；`login`、`login_only` 1（仅限登录）和 2（仅限持有积分的登录用户，免费看）→ `needsLogin`。关注分组在直播中，人数、开播时间照常。目录照 v3 保留受限房间（隐藏与否由发现页的设置决定，M13）。<br>`getLiveStatus` 对受限直播返回真（v3 报 `access`）；取画质、取流、恢复、`controlGrant`（`openControl`）按受限类型拒绝（`Fc2LiveApi.refusal`）：`needsLogin` 报 `NeedsLogin`，`paid`、`unplayable` 报带原因的 `StreamUnavailable`，都不发请求（授权只发 `memberApi`）。从存储读回、没有 `Fc2LiveRoomData` 的房间按它的 `restriction` 拒绝。`Fc2LiveState.restricted` 和受限公告（`fc2live_access_restricted`）保留 | 受限房间显示为“直播中”，卡片标出“需要登录”或“付费”（M13），点进去提示需要登录（本应用没有 FC2 账号）或付费，不再是“待定” | 平台层完成，余下 M13 |

### 按统一原则补的

| 事项 | 做法 |
|---|---|
| 开播时间 | 两处都能取到，不多发请求：目录每行的 `start_time`（Unix 毫秒；`start` 是日本时间的文字，不用），详情的 `channel_data.start`（Unix 毫秒，只在在播时填；未开播时是 0）。0、2000 年以前、2100 年以后、不是整数的都不填，也不让回答失败（`Fc2LiveApi.startTime`）。S01 的 10200498 是 2026-09-27 04:51:54.285 UTC（`start` 写的是 13:51:54 JST），S02 的 62996200 是 2026-09-26 07:17:46.410 UTC（控制连接 `connect_data.publish_start_time` 同值）。`getLiveStatus` 只返回是否在播 |
| 受限类型 | 目录和详情都能判断，在播时一律填（没有限制填 `none`），未开播留空（见 26-9）。成人标记（`adult`）不算受限：匿名访客的 `user_data.adult_access` 是 1，v3 也只给公告，照旧只给成人公告 |
| 受限的直播改为直播中 | 见 26-9（原来用 `unknown`） |
| 占位信息 | 名字没有时留空（v3 写频道号）；标题没有时用名字，名字也没有就留空（v3 写频道号）；封面、头像只收站点的图片，没有就空。界面在名字为空时显示平台名（`displayNick`，M13）；关注里存下的名字不会被空值覆盖 |
| 回放、轮播、“不可播放” | 不适用：接口只有在播和未开播，本平台没有回放入口（网页的“録画”“タイムシフト”不在 v3 的范围）。`unplayable` 只用于 `is_limited` 的在播频道 |
| 画质命名 | 表里有 26-2 这一条：新增的分档都是转码，不叫原画；30、20、10 用共用的高清、标清、流畅，50、40 照网页的码率叫“超清 3M（β）”“超清 2M”；v3 的“自适应 HLS”名字和 id 都不变 |
| 默认编码 | 不涉及：只有 H.264（主列表 `CODECS="avc1…"`） |
| 房间身份 | 不变：数字频道号，没有大小写问题（T02g.2） |
| 按主播关注 | 本来就是：频道就是主播，没有单场身份 |
| 容错 | 见 26-7（目录行、HLS 列表行）。详情仍是一个对象，照 v3 严格检查用到的字段；不再读的 `category_name` 不再检查，新读的头像、开播时间不合规只当作没有 |
| 翻页 | 见 26-1 |
| 弹幕 | 见 26-3 |
| 说明文字 | 平台层没有改文字键和文字（`fc2live_directory_scope`、`fc2live_chat_notice`、`fc2live_access_restricted`、`fc2live_adult_notice`），建议的新文字见“留给其他模块” |

### 请求数

| 场景 | T02c.13 | 现在 | 原因 |
|---|---|---|---|
| 目录、搜索第 1 页（带令牌） | 1 | 1 | — |
| 目录、搜索第 2 页起（带令牌） | 每页 1 | 20 秒内 0；超过 20 秒 1 | 26-1 |
| 取分类 | 0 | 0 | — |
| 推荐和分区切片、`searchRooms`（不带令牌） | 20 秒内共用 1 个 | 不变，也能用目录、搜索取到的快照 | 26-1 |
| 不带令牌的 `getDirectoryPage` 第 1 页 | 20 秒内共用 | 1（刷新） | 26-1：第 1 页就是下拉刷新；v3 的目录页总是带令牌，所以实际请求不变 |
| 按频道号、链接搜索 | 1 | 1 | — |
| 进房、刷新、录制、开播状态 | 各 1 | 各 1 | 开播时间、受限类型、头像、弹幕参数都来自同一个回答 |
| 取画质 | 0 | 2 个 + 1 条连接（读到回答即关） | 26-2：只有控制连接的回答说明频道有哪几档（补充决定：频道没有 40、50 时不列出） |
| 取流、恢复 | 0 | 0 | — |
| 打开控制连接（播放、录制） | 2 个 + 1 条连接 | 不变 | 画质只决定读回答里的哪个列表 |
| 受限、未开播的频道打开控制连接 | 1 | 1 | — |

### 画质 id 对照（给 T09b.1）

| v3 的 id（v3 的名字） | 现在 | 说明 |
|---|---|---|
| `auto`（自适应 HLS） | `auto`（自适应 HLS），排在最后 | 不变 |
| — | `50`（超清 3M（β））、`40`（超清 2M）、`30`（高清）、`20`（标清）、`10`（流畅） | 新增（26-2），频道有的才列出，默认第一档 |

- 没有 id 变化，不需要旧 id → 新 id 的对照：代码里 `Fc2LiveApi.qualityIds` 包含 v3 的 `auto`（有测试）。
- 3.x 的全局画质偏好按名字存（原画、蓝光8M、蓝光4M、超清、流畅），“流畅”现在能直接对上最低一档；对不上名字时按比例选下标，“自适应 HLS”排在最后，按比例选时应跳过它（见 T04）。

### 设置项

无。本平台的 9 行都不需要开关。

### 身份迁移规则（给 T09b.1）

- 房间身份不变（数字频道号，3.x 存的就是它），没有按主播关注的条目，不需要旧 id → 新 id 的规则。
- 占位名字：3.x 在频道没有名字时把频道号写进 `nick`（标题同样）。现在留空，而合并时空值不覆盖，所以存下的频道号会一直留着。T09b.1 迁移 3.x 的 FC2 关注时，`nick` 等于房间号的清空（`title` 等于房间号的也清空），界面改显示平台名。
- 3.x 存下的受限房间是“未知”（`liveStatus` 3），不用迁移：刷新后变成直播中 + 受限类型（有测试）。3.x 存下的分区名（英文或日文）刷新后被中文名替换。3.x 存下的 `httpHeaders` 可以在迁移时丢掉（T02c.13 已写）。

### 与 v3 冻结输出的新差异

`expected.json` 没有改。样本对照测试里用 `changed:` 列出（注释写条目编号），T02g.2 的新键用 `added:` 单独断言：

- S01 全部目录页、推荐和分区切片、关键词搜索：房间、顺序和其余键与 v3 一致；每张卡片的 `area` 变了（26-6）；5 个受限房间的 `liveStatus`、`status` 变了（26-9）；3024638 的 `title`（26-4）、5185474 的 `nick`（占位）变了；新键是每行的 `start_time` 和受限类型（`none` 或 `needsLogin`）。
- S02 在播（62996200）：进房、刷新、录制、按链接进房只有 `area` 变了（`その他` → `其他`）；新键是开播时间和 `none`；进房另有弹幕参数（不在 JSON 里）。
- S02 受限（3024638）：`liveStatus`、`status`（26-9）、`title`（26-4）、`avatar`（26-5，`smallicon`）、`area`（26-6）变了，`introduction` 同 T02c.13（差异 3）；新键是开播时间和 `needsLogin`；v3 的开播状态 `access` 现在是真，取画质 `schema`、授权 `access` 现在是 `NeedsLogin`。
- S02 未开播（10608314，v3 报错）：人数为空（26-8），分区名“闲聊”，没有开播时间和受限类型。
- S04 控制连接：`auto` 的列表与 v3 的主列表逐字相同，请求帧逐字相同；另外读出 15 个列表，列出 30、20、10、自动（没有 40、50）。
- 画质：v3 的 `auto`（名字、id、`sort`）不变，前面多了频道有的分档（26-2）；`auto` 的配方身份、恢复与 v3 相同。v3 取画质不发请求，现在打开一条控制连接。
- S07 控制连接（新样本，v3 没有）：21 个列表，列出 50、40、30、20、10、自动。
- 快照缓存的请求（`cache`）：与 v3 一样是 2 个。
- 坏行、坏列表只跳过自己（26-7），只有合成用例；`fee`、`ticketid`、`is_limited` 的受限也只有合成用例（见“受阻和未核实”）。

### 留给其他模块

| 模块 | 内容 |
|---|---|
| T06a | FC2 评论（26-3）：进房和录制详情的 `danmakuData` 是 `Fc2LiveDanmakuArgs(channelId)`。按归档规格 §7：用 `Fc2LiveSite.controlGrant(channelId)` 取授权（未开播 `StreamUnavailable`，受限 `NeedsLogin` 或 `StreamUnavailable`，不存在 `NotFound`，都只发 `memberApi`），经 `proxy.routeFor('fc2live', grant.socket)` 连 `grant.endpoint`，握手带 `grant.handshakeHeaders`，WebSocket ping 15 秒（`Fc2LiveControl.connect`）；收到 `connect_complete` 算加入，每 30 秒发 `{"name":"heartbeat","arguments":{},"id":<递增>}`；`comment` 的 `arguments.comments[]` 里 `history: 1` 是加入时推的旧评论，丢掉；`user_count` 只带变化的字段，在线 = `pc_user_count + mobile_user_count`，累计 = `pc_total_count + mobile_total_count`，要保留上一次的值再相加，用它更新人数（26-3 的“并用它更新人数”）；`control_disconnection`（4500 授权过期）后重新取授权再连。授权约一分钟有效，一个授权只连一次。样本 `danmaku/S06-live`。接入后 `fc2live_chat_notice`（“远端聊天尚待接入”）就不对了，要和 M13 一起改 |
| T04 | 26-2 的播放：按配方 `Fc2LiveInputRecipe(channelId, quality)` 调 `openControl(channelId, quality: recipe.quality)`，经中继播 `control.playlist`（一档是单个变体的媒体列表，`auto` 是 v3 的主列表，都没有 `.m3u8` 后缀），媒体请求带 `control.mediaHeaders`，播放期间一直持有控制连接，`done` 完成时重新获取；`control.quality` 与请求的不同时（频道没有这一档）显示实际的画质。<br>候选里的“控制连接按租期共享”（同一频道的播放和录制共用一条连接，归档 v4 用 60 秒预取、150 秒过期的租期）由 T04 决定做不做；要做就注意对照笔记 `sub_C.md` 的竞态：同一频道同时打开时要共用进行中的那一次，不能开两条。平台层照 T02c.13 每次打开各自取授权、各自一条连接（REG-LEASE-017 不变）。<br>取画质要连一次控制连接：房间页用 `discoverPlayQualities`（`LiveQualityDiscoveryScope`）取，离开房间时取消；取到的列表随频道而变（有的频道有 50、40），不要按平台写死。播放再打开自己的连接，所以开播前一共 4 个请求和 2 条连接；要省掉一次，可以在做租期共享时把探测用的连接直接交给播放（探测连接现在读到回答就关）。<br>默认画质是列表第一档；v3 的全局偏好对不上名字时（“超清”对不上“超清 2M”）按比例选下标，应跳过排在最后的“自适应 HLS”。90（只有声音）没有列出，`control.playlists` 里能看到 |
| T08a.1 | 录制按同样的配方打开自己的控制连接；录哪一档由 T08a.1 决定（`auto` 与 v3 相同）。录制详情带弹幕参数，录不录评论由 T08a.1 定。受限直播的开播状态现在是真，录制开始时取流会报 `NeedsLogin` 或 `StreamUnavailable`，要当作“不能录”，不要反复重试 |
| T09b.1 | 按 T02g.2 存 `startedAt`、`restriction`。没有设置、画质 id 要迁移；占位名字的清理见“身份迁移规则” |
| M13 | 目录页、搜索页下拉刷新时重新取第 1 页（v3 已是这样），之后的页 20 秒内来自同一份快照（26-1）。<br>分区名按 `Fc2LiveRoomData.categoryId` 显示界面语言的名字（1 闲聊、2/3 游戏 / 作业、4 视频、5 其他、9 音频，键 `fc2live_category_*`；26-6）。<br>未开播的房间不显示人数：关注列表合并刷新结果时会保留上次在播时的人数，卡片要按 `isLiveNow` 决定是否显示人数（26-8）。开播时间只在直播中显示。<br>受限直播：卡片按 `restriction` 标“需要登录”“付费”“受限”；发现页默认隐藏不能播放的直播（本应用没有 FC2 账号，FC2 的 `needsLogin` 也播不了），关注和搜索照常显示（26-9）。名字为空时显示平台名（`displayNick`）。<br>画质菜单按频道列出（26-2）：超清 3M（β）、超清 2M（频道有时）、高清、标清、流畅、自适应 HLS；打开菜单前要等一次控制连接的探测。<br>文字建议（中 / 英）：<br>- `fc2live_directory_scope`：“这里是 FC2 此刻所有正在直播的公开房间，按分区筛选；搜索只在这些房间里按频道号、名字、标题和分区查找。输入频道号或粘贴频道链接可以打开没有在直播的频道。” / “All public FC2 channels live right now, filtered by area. Search looks only through these channels, by number, name, title or area. Enter a channel number or paste a channel link to open a channel that is not live.”<br>- `fc2live_access_restricted`：“这场直播需要登录 FC2、持有积分、购买门票或付费才能观看，本应用暂不支持。” / “This broadcast needs an FC2 account, points, a ticket or payment, which this app does not support yet.”<br>- `fc2live_chat_notice`：T06a 接入评论后删去；接入前可改为“FC2 的评论暂未接入。” / “FC2 comments are not connected yet.”<br>- `fc2live_adult_notice`：“主播把这个房间标为成人内容。” / “The streamer marked this room as adult content.” |

### 受阻和未核实

没有受阻的条目。以下只有合成用例，没有真实样本：

- **付费、门票的在播频道**（目录 `pay`、`tid`，详情 `fee`、`ticketid`、`ticket_only`）：2026-09-27、28 两份目录里都没有（受限的全是 `login` 1、2）。按网页脚本的卡片标记判断为 `paid`，取流报带原因的 `StreamUnavailable`，没有实测这种频道的控制授权会回答什么。
- **`is_limited` 的在播频道**：只在未开播的 S02-member-offline 见到（`is_limited` 1）；按网页脚本（“配信規制中”，请出观众）判断为 `unplayable`。
- 26-2 的分档要等 T04 的中继才能播放；平台层已用录下的两份回答（S04、S07）和实测验证列出的档和选中的列表。40、50 以外，网页脚本里没有更高的档。

### 新样本

- `S02-member-points`：频道 5185474 的 `memberApi.php` 回答（2026-09-28 20:05:33 UTC 直连、匿名，请求头与适配器相同）。在播、`login_only` 2（仅限持有积分的登录用户）、主播名和 `tname` 都为空、没有 `icon`/`image`，用来测 `login_only` 2 的受限类型、空名字不填频道号、头像退回封面。
- 脱敏：响应头 `set-cookie` 的 `PHPSESSID` 换成同形（26 位小写字母和数字）的合成值，记在 `meta.json` 的 `scrubbed`（`set-cookie:PHPSESSID`，`secret`）；`raw` 记原始正文的 SHA-256 和长度。正文里 `user_data` 是匿名访客（`userid` 0），没有出口地址、访客编号、设备编号、令牌；门禁的 `fixture privacy` 通过。
- 没有 `expected.json`：v3 没有录过这个回答。
- `control/S07-control-hd`：频道 10200498 的控制连接（2026-09-28 20:47:52 UTC 直连、匿名，用适配器的 `openControl` 加一个记录帧的连接器），格式同 S04（`frames.jsonl` 和 `meta.json`）。推流 1920×1080，HLS 回答有 40、50 两档，用来测 26-2 的“频道有才列出”。
  - 脱敏：三族列表地址里的 `c`、`d` 换成同形（同长度、同字符类）的合成值，所有地址用同一对；握手地址的 `control_token` 同样替换；记录器没有留下握手的请求头，`meta.json` 里写的是适配器的请求头，`l_ortkn` 是合成值（`notes` 写明）。一条 `comment`（历史评论，含加密用户号和 `orz_token`）和一条 `ng_comment`（屏蔽词表）整帧删去，记在 `notes`。剩下的帧只有加入、人数、推流分辨率、积分和 HLS 回答，没有出口地址、用户编号、令牌；门禁的 `fixture privacy` 通过。
  - 没有 `expected.json`：v3 只读 mode 0 的主列表。

### 测试

本平台 76 个用例（T02c.13 是 58 个；新增 18 个，另改写了快照、目录容错、画质、详情、控制连接的用例），`live_core` 共 3360 个，门禁 `--all` 通过：

- `fc2live_api_test.dart`（30 个）：
  - 样本对照：S01 每张卡片的 `changed`（分区名、受限、实体、占位名字）和 `added`（开播时间、受限类型），卡片上的变化逐项断言；S02 在播、受限、未开播、积分限定（新样本）的详情；精确查找；
  - 画质：五档加 v3 的 `auto`、名字、顺序和 `sort`、`auto` 与 v3 相同、各档的配方身份；S04 读出全部 15 个列表、只列 30、20、10、自动，`auto` 是 v3 的主列表、各档选高延迟变体、要 50、40 时退到 30、不认识的画质；S07 读出 21 个列表、列出六档、50、40 选高延迟变体；`qualitiesOf` 按任一族列档、有主列表才列自动、只有声音时为空；缺档时退到更低、更高一档、主列表，`auto` 没有主列表时用最好的一档；
  - 容错：目录 10 种坏行只跳过自己、只有坏行仍报错、外壳错误仍报错；HLS 回答 17 种坏列表单独时报错、与好列表同在时只少自己，坏的一族被跳过，同一 mode 先到的为准；
  - 受限：目录 6 种标记及先后、详情 6 种标记及先后、未开播不填、成人只给公告；`refusal` 的错误类型和原因；
  - 实体解码（名字、标题、简介）、占位名字和标题留空、开播时间的取值范围、头像的先后和容错、`category_name` 不再读。
- `fc2live_site_test.dart`（46 个），测试时钟固定为样本的录制时间：
  - 26-1：第 1 页刷新、后几页不再请求、61 个房间不重复不遗漏；分区第 2 页、取分类、推荐和分区切片也用它；19 秒复用、20 秒重新请求并再次共用；第 1 页带不带令牌都刷新；时钟倒退不复用；搜索翻页同样，并供目录使用，精确查找仍走 `memberApi`；带令牌的后续页不等进行中的共用请求；失败、取消不留快照；v3 的缓存场景仍是 2 个请求；
  - 详情：三种深度的开播时间和 `none`，进房和录制带弹幕参数、刷新不带；受限和积分限定是直播中 + `needsLogin`、开播状态为真；未开播没有人数、开播时间、受限类型；3.x 存下的受限关注刷新后变成直播中；空名字不覆盖存下的名字；下播后合并清掉开播时间和受限类型；
  - 取画质：进房、刷新、卡片得到的房间各打开一条控制连接（请求与 v3 的授权相同）、读到回答后关闭，S04 列出四档；S07 的频道列出六档、`50` 的配方和控制连接播 `/51/playlist`；取消令牌（打开前、打开中）和启动超时都不留下连接；
  - 取流：六个画质的配方和恢复、确认的画质，不发请求；受限、积分限定、存储读回的受限房间按类型拒绝，不发请求；错误的画质 id；
  - 授权：受限按类型拒绝，付费和 `is_limited` 是带原因的 `StreamUnavailable`，都只发 `memberApi`；
  - 控制连接：录下的对话里 `auto` 是 v3 的主列表，三档各自打开高延迟变体（请求和握手与 v3 相同）；缺档时退档并报出实际画质，只有声音时打不开；不在六档里的画质不发请求、不连接。
- 时间炸弹：被测代码不拿样本时间和“现在”比较（开播时间的范围是固定的 2000～2100 年），网站测试的时钟固定为录制时间。两份测试把时间放后 30 天、1 年、5 年（`tools/timeshift` 的 `shift.c`）都通过：30 天用 `dart test`；1 年和 5 年时 `dart test` 运行器本身启动后就停住不动（主会话已查明并修好：`run.sh` 改为逐个测试文件直接运行），这里同样用 `dart run` 直接运行测试文件，全部通过。

## 后续（T06a 弹幕）

本平台的聊天（弹幕）已由 T06a.23 完成，见 [记录](../../../T06/T06a/T06a.23/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 T02 当时的情况，不再改动。
