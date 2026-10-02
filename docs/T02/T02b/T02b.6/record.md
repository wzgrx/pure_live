# T02b.6 克拉克拉

- 日期：2026-09-28
- 目标：`packages/live_core/lib/src/sites/kilakila/`（`kilakila_api.dart` 纯解析，含链接编解码；`kilakila_site.dart` 请求编排）
- 样本：`fixtures/kilakila`，15 个真实接口录制（2026-09-27，直连，匿名）和 29 个分享链接向量（`S09-share-vectors`），来自归档；另有弹幕样本 `danmaku/S07-live`（T06a 用）。其中 14 个录制和分享向量附有 v3 的冻结输出 `expected.json`，生成方法见下文。T02.U 另补了 1 个时间线样本 `S01-timeline-new-tail`（见文末“升级落地（T02.U）”）。
- 参考：
  - 归档 v4 的克拉克拉适配器和规格（`spec/sites/kilakila.md`，回归条目 REG-KILAKILA-001～005）；
  - pure_live_TV `e1cca224`：`lib/platforms/kilakila/` 与 v3 逐行相同，只改了导入路径、去掉可空标注和几个默认参数、补了注释，没有行为修复；对照笔记 `~/ref/notes/tvcore/sub_A.md` 的 kilakila 一节、`small_diffs.txt`。

照 T02a.1 哔哩哔哩：解析写成纯函数，请求编排单独一层，用样本对照 v3 的输出，差异逐条说明。用户能看到的状态、分组、画质名称和列表内容都按 v3；修好但会改变这些内容的地方，列入“后续升级候选”；关注刷新和列表的请求不比 v3 多。

## v3 的冻结输出

归档只给五个大站生成过 `expected.json`。本模块用 `fixtures/kilakila/legacy_expected.dart` 生成：

- 把 v3 的 `KilakilaApi`、`KilakilaLink`、`KilakilaSite`（`legacy/lib/core/site/kilakila/` 三个文件）原样搬进一个程序。v3 本来就把传输做成可注入的函数（`KilakilaRequest`），所以只换了它：按主机、路径和查询读样本；状态码不是 200 时正文为空（同 v3）；没有样本的请求抛 StateError 并原样抛出，不会被当成 v3 的传输失败。
- 只在网络路径上用到的 `_defaultRequest`、`readBody` 没有搬；`KilakilaSite` 保留方法体，去掉 `extends`/`implements`、`@override` 和 `getDanmaku`（`EmptyDanmaku`），两个构造函数改为必须注入传输。
- v3 的 `LiveRoom`、`LiveArea`、`LiveCategory`、`LivePlayQuality`、`LivePlayUrlResolution`、`LiveDirectoryPage` 只搬用到的部分；`i18n` 返回 3.x `zh.json` 的文字。分享链接的导入用 v3 `LiveUrlTool._parseLiveUrl` 里克拉克拉的那一段（`live_url_tool.dart:216-222`）。
- 输出格式同旧版工具（`roomProjection`、`errorProjection`、`{generator, value}`），另记下每个调用发出的请求。
- v3 用 `package:html` 读搜索页、用 `package:pointycastle` 解分享链接，这两个包不是工作区的依赖。运行方法写在脚本开头：在临时目录建一个依赖 `html 0.15.6`、`pointycastle 4.0.0`、`crypto 3.0.7` 的包（3.x 的 pubspec 是 `html ^0.15.4`、`pointycastle ^4.0.0`），再用 `dart --packages=<它的 package_config.json> fixtures/kilakila/legacy_expected.dart` 在仓库根目录运行。

有 `expected.json` 的样本：

- 时间线 4 个：`getDirectoryPage`（推荐和按分区两种调用）、`getRecommendRooms`、`getCategoryRooms`；热门第 1 页另有分类、`directoryNoticeKey`；
- 搜索 3 个：`searchRooms`（每页 20）、`supportsSearchPaginationFor`；
- 主播主页 3 个：刷新、进房、录制、开播状态、按 uid 和主页链接搜索、画质和地址、恢复取流，每项带请求（在播的主页配上 `S05-room-live`）；
- 直播 3 个：`KilakilaApi.detail` 不取流和取流两种；在播和不存在的另有分享链接的导入；
- `S06-room-redirect`：请求地址和跳转地址的链接解析、跳转地址的分享导入；
- `S09-share-vectors`：每个向量的 `KilakilaLink.parse`。

`S02-recommend`（`pcLive/recommend`）没有期望值：v3 的推荐用热门时间线，这个接口只在不被调用的 `recommendations()` 里（见问题 9）。

## 做法

- **接口和输出沿用 v3**：`LiveSite`、`LiveRoom` 等模型和 3.x 的 JSON 不变。v3 实现过的可选能力全部保留：原生目录分页（`LiveSiteDirectoryPager`）、目录说明（`LiveDirectoryNotice`，`kilakila_directory_scope`）、刷新（`LiveSiteRoomRefresher`）、录制详情（`LiveSiteRecordRoomResolver`）、恢复时重新取流（`LivePlayRecoveryResolver`）、可取消的搜索（`LiveCancellableSearch`）、按关键词决定是否翻页（`LiveSearchPaginationPolicy`）。另加 `LivePlayUrlResolver`（线路带请求头和租期）和 `LiveSiteLinks`。
- **房间身份是主播 uid**（REG-KILAKILA-001）：每场直播有新的 `roomIdStr`，只在当场有效；房间号、`userId` 都是 uid，链接是主播页 `https://live.hongrenshuo.com.cn/index/roomuser/uid/<uid>`，与 v3（S:39-47）相同，3.x 存下的关注都能对上。本场直播的 id 放在 `KilakilaRoomData.broadcast` 里，不存储。
- **请求照 v3**：全部匿名 GET，带 v3 的 `playHeaders`（`Referer: https://live.kilakila.cn/`、UA `Mozilla/5.0`），不跟随跳转；没有 Cookie（v3 没有克拉克拉登录，设置里也没有它的 Cookie），所以不注入 `CookieVault`。

  | 调用 | 请求 | 次数（与 v3 相同） |
  |---|---|---|
  | 分类 | 不请求：两个时间线 `0` 热门直播、`107` 萌星推荐 | 0 |
  | 推荐、分区、目录分页 | `pcLive/timeline?tag=0&type=<0/107>&genderType=0&pageNo=&pageSize=`（目录分页每页 10 条） | 1 |
  | 关键词搜索 | 官网用户搜索页 `/aboutus/serach/kw/<关键词>[/p/<页>]` | 1 |
  | uid 或主播页链接搜索 | 主页 `Tg/personalH5?uid=` | 1 |
  | 关注刷新、开播状态 | 主页 | 1 |
  | 进房、录制、恢复取流 | 主页，再查当前直播的 `LiveRoom/getRoomInfo?roomId=` | 2（没有当前直播时 1） |
  | 直播分享链接 | `getRoomInfo` | 1（v3 是 2，见差异 8） |

- **解析照 v3 的严格程度**：
  - 时间线要回显请求的页码和每页条数，`isLastPage` 必须是布尔值；接受的行（热门 `dataType` 8，萌星 8 或 2）必须有主播、直播 id、标题、名字，主播要对得上。有一行不对，整页报 `ApiChanged`。
  - 同一页里先按直播 id、再按主播去重（v3 的 API 层和站点层）。
  - 主页的 `liveCard` 只有两个路由字段（或为空）时是“没有当前直播”，状态未知；有别的内容就必须是这个主播的完整卡片。`getRoomInfo` 的直播和主播必须是请求的那个。
  - 回答超过 1 MiB 是 `ApiChanged`。
- **状态照 v3**：平台说 4 才是直播中，其他（10 已结束、未知取值、没有当前直播）一律“未知”（S:50-51、178-191）。
- **画质照 v3**：FLV、HLS 两个“画质”，FLV 在前，名称 `FLV`、`HLS`，id `flv`、`hls`，排序值都是 0。每个画质一条线路：
  - 地址必须是 `https://pull.live.hongrenshuo.com.cn/hrs/<直播 id>.flv|.m3u8`，恰好一个非空的 `auth_key`（v3 的 `mediaUrl`）；`rtmpPlayUrl` 和推流地址 `pushFlow` 从不读取（REG-KILAKILA-004）；
  - 带 v3 `PlaybackHeaderResolver` 里克拉克拉的请求头（与接口请求相同）；
  - 租期取 `auth_key` 的第一段（到期的 Unix 秒，签发后 30 天），到期前 min(10 分钟, 寿命的 1/4) 续期；HLS 标为“到期会断”（播放列表要反复请求），FLV 已建立的连接不断。v3 没有克拉克拉的租期。
- **取流时才判断能不能播**：进房照样读 `getRoomInfo`，房间照常显示；付费（`goldPrice` 不为 0）报 `NeedsLogin`，状态不是 4、没有合规的拉流地址报 `StreamUnavailable`，顺序同 v3。
- **链接**：`KilakilaLink.parse` 照搬 v3 的规则和官网加密分享链接的解法（REG-KILAKILA-002）：URL 安全的 base64、AES-128-CBC（两把公开密钥依次试）、明文里的 MD5 签名绑定原始的协议、主机和路径。
  - 主播页（`/zhubo/<uid>`、`/index/roomuser/uid/<uid 或密文>`）直接得到 uid（`roomIdFromUrl`）；
  - 直播页（`/room/<id 或密文>`、`/PcLive/index/detail?id=` 或 `?_specific_parameter=`）要查一次主播（`needsResolving`、`resolveUrl`，经 `ShortLinkSession`）。
- **弹幕**：v3 没有克拉克拉弹幕（`EmptyDanmaku`）。进房时只输出 `KilakilaDanmakuArgs`（本场直播 id，官网游客聊天室加入时用的就是它），不多发请求；是否启用由 T06a 决定。

## 审查发现的 v3 问题

位置简写：`A` = `legacy/lib/core/site/kilakila/kilakila_api.dart`，`L` = `kilakila_link.dart`，`S` = `kilakila_site.dart`，`phr` = `legacy/lib/player/core/playback_header_resolver.dart`，`lut` = `legacy/lib/common/utils/live_url_tool.dart`。“按 v3 保留”的，修法在“后续升级候选”。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 取流失败、付费、状态不对、不存在、服务端故障都是 `KilakilaException`，播放和录制只能按种类名字判断；不存在的直播（5201）和接口变化都算 `service` | A:12-32、A:236-241 | 平台自己的异常类型 | 类型化错误（见差异 1） |
| 2 | 进房遇到付费、非直播状态、没有拉流地址的直播直接失败，房间页打不开 | S:194 → A:368-376 | 进房用取流模式的 `detail()`，把“不能播”当成“详情失败” | 进房照常返回房间，取流时报 `NeedsLogin` / `StreamUnavailable` |
| 3 | 没有 `data` 的房间（列表卡片、刷新得到的关注）取画质报“媒体不可用” | S:211-219 | 只认进房时放进 `data` 的画质 | 先进房再给画质；平台明确未开播的房间直接 `StreamUnavailable`，不发请求 |
| 4 | 拉流地址是签名地址（`auth_key` 30 天后到期），却没有续期时间，录制拿到的 `refreshAt`、`invalidAt` 都是空 | S:229-239；v3 `kilakila_application_test.dart` 的录制用例 | 没有实现 `LivePlayLeaseMetadata` | 线路自带租期 |
| 5 | 平台层依赖全局 `HttpClient`；播放请求头按平台写在播放层 | A:95-115；phr:162-163 | 结构问题（诊断报告里的“旁路”） | 注入 `LiveHttp`；线路自带请求头，与 v3 的值相同 |
| 6 | 带冒号的关键词（`Re:Zero`、`C++:x`）搜不到任何东西，也不翻页 | S:142 | 把 `Uri.tryParse` 有 scheme 的输入都当成链接 | 只有 `scheme://主机` 形式才算链接（同 T02b.4 猫耳） |
| 7 | 分享直播链接导入时发两个请求 | A:503-509；lut:219 | 查到直播的主播后，又请求一次主页，只为确认主播存在；导入只用 uid | 只请求 `getRoomInfo`，主播的存在在进房时自然确认 |
| 8 | 主页里有主播简介和粉丝数，都没读 | A:453-489 | — | 详情带上（v3 缺的数据，不多发请求） |
| 9 | 不会被调用的代码：`recommendations()`、`detailForOwner()`、`numericRoomFromUri()`、`numericOwnerFromUri()` 只在测试里用 | A:430-435、A:491-498、A:277-322 | 重构后留下的 | 不移植；它们测试里固定的行为由 `KilakilaLink.parse` 和进房流程的测试覆盖 |
| 10 | 平台层调用界面翻译（站点名、两个时间线名） | S:31、S:121 | `i18n` 写在适配器里 | 用 3.x 的中文作默认名，界面按 `areaType: 'timeline'` 和 `areaId` 显示自己的翻译（M13） |
| 11 | 为了读搜索页和解分享链接引入 `package:html`、`package:pointycastle` | A:6、A:214；L:5-9 | — | 分享链接用新加的通用 `Aes128Cbc`；搜索页用平台内的小型 HTML 读取器（去掉注释和脚本，按标签建树）。两者都用样本和 29 个独立向量核对，与 v3 一致 |
| 12 | 每个回答都整段编码一次 UTF-8 来数字节 | A:176 | — | 只有长度超过上限三分之一的文本才编码计数 |
| 13 | 没有当前直播的主播、已结束的直播（10）都显示“未知” | S:50-51、S:178-191 | 平台只明确说了 4 | 按 v3 保留 |
| 14 | 搜索框里粘贴直播分享链接搜不到主播 | S:162 | 搜索只认主播链接 | 按 v3 保留 |
| 15 | 有在线人数（主页的 `onlineNumber`）和累计收听（`watchNumber`），都不显示 | S:48-53 | v3 当时没确认含义（REG-KILAKILA-003 已实测） | 按 v3 保留 |
| 16 | 时间线循环，热门到第 55 页才 `isLastPage`，萌星到第 300 页仍有数据，一直往下翻会反复出现同样的主播 | A:420-427 | 只按 `isLastPage` 结束（REG-KILAKILA-005） | 按 v3 保留 |
| 17 | 关键词超过 100 个字符、页码超过 10000 时，搜索页上克拉克拉显示失败 | A:199-201 | 参数校验当成响应校验 | 按 v3 保留（`ArgumentError`，不发请求） |
| 18 | 进房后的封面和列表、刷新里的不一样 | A:378-384 | 列表和主页卡片有 `backPic`；`getRoomInfo` 没有，只能退回 `defaultBackgroundPicUrl`（样本里是动图背景） | 按 v3 保留 |

## 与 v3 输出的对照

对照方式：用同一份录下的响应跑新代码，逐键比较 `toJson`（加 `link`）和 v3 的冻结输出；画质比较名称、id、排序和地址；请求比较地址和次数。

| 样本 | 结果 |
|---|---|
| S01 时间线（热门第 1、2、55 页，萌星第 1 页） | 一致：房间、顺序、各字段，页码和是否还有下一页（第 55 页结束）；`getRecommendRooms`、`getCategoryRooms` 给出同样的列表，请求相同 |
| 分类 | 一致：一个“克拉克拉”分类，`热门直播`、`萌星推荐`。v3 的 `areaPic`、`shortName` 写 `null`，新代码写空字符串，3.x 读取时两者等价 |
| S03 搜索（第 1、2 页各 10 人，无结果） | 一致：名字同时作标题，头像，状态未知；请求相同 |
| S04 在播主播 | 刷新、进房、录制、开播状态、按 uid 和主页链接搜索都一致，只多了简介和粉丝数；请求相同（1、2、2、1、1）。画质 `FLV`、`HLS` 的 id、排序、地址逐字节一致，恢复取流的地址和 `appliedQualityData` 一致 |
| S04 没有当前直播 | 一致：状态未知、没有标题；搜索给出 v3 的主页卡片。v3 取画质报 `mediaUnavailable`，现在 `StreamUnavailable`（不发请求） |
| S04 不存在（1013） | 一致：详情是“不存在”，搜索没有结果 |
| S05 在播直播 | `getRoomInfo` 的解析一致：两个 id、名字、封面、状态、价格、两个拉流地址 |
| S05 已结束（10） | 解析一致；v3 进房报 `stateUnsupported`，现在房间状态未知、取流报 `StreamUnavailable` |
| S05 不存在（5201） | v3 是 `service`，现在 `NotFound` |
| S06 跳转 | 请求地址和跳转到的加密链接都解析成同一场直播；分享导入得到同一个主播，请求 1 个（v3 是 2 个） |
| S09 分享向量（29 个） | 全部与 v3 和独立生成器（.NET）的结果一致，包括换主机、错签名、多余参数和畸形明文 |

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 错误类型化：HTTP 401/403 `RiskControl`，404 `NotFound`，429 `RateLimited`，5xx 和其他状态 `NetworkFailure`；主页 1013、`getRoomInfo` 5201 `NotFound`；5966（历史回放）`StreamUnavailable`；其他业务码和格式不对 `ApiChanged`；付费 `NeedsLogin`；参数错误 `ArgumentError`（同 v3 不发请求） | 问题 1；分类与规格 §9 一致。界面看到的仍是加载失败或播放失败 |
| 2 | 进房不因付费、状态、缺地址失败；取流时报 `NeedsLogin` / `StreamUnavailable` | 问题 2；房间的状态照 v3（付费直播仍是直播中，其他仍是未知） |
| 3 | 进房时主页说有直播、`getRoomInfo` 却说不存在或已成回放：`StreamUnavailable` | v3 是 `service` / `historicalReplay`。主播本身存在，不能报 `NotFound`（界面可能据此提示房间不存在） |
| 4 | 没有 `data` 的房间取画质时先进房；明确未开播的房间直接 `StreamUnavailable` | 问题 3。正常进房流程不受影响 |
| 5 | 线路带请求头、格式、线路编号和租期 | 问题 4、5；请求头的值与 v3 相同 |
| 6 | 详情（刷新、进房、录制）带主播简介和粉丝数 | 问题 8；不多发请求；3.x 的人数口径不用粉丝数，界面不变 |
| 7 | `scheme://` 形式才算链接，带冒号的关键词正常搜索 | 问题 6 |
| 8 | 直播分享链接只请求 `getRoomInfo`；查不到时返回“没有房间”，不再抛错 | 问题 7；v3 的工具箱对两种情况都提示“解析失败”，用户看到的一样 |
| 9 | 图片地址统一经 `normalizeImageUrl`（协议相对地址等也能显示），带用户信息的仍然丢弃 | 与其他平台一致；样本里都是完整的 https 地址，结果相同 |
| 10 | 进房时带弹幕参数 | v3 没有克拉克拉弹幕；参数留给 T06a，不多发请求 |
| 11 | 响应只在下载完后查 1 MiB 上限，只有长文本才编码计数；非法 UTF-8 变成替换字符而不是报错 | 传输统一由 `live_net` 负责，它没有逐请求的大小上限；20 秒的读取期限由请求超时覆盖（同 T02c.3、T02b.4） |

## 保持 v3 行为、没有采用归档 v4 或上游做法的地方

（T02.U 已按升级决定改掉其中的状态、人数、时间线的结束、画质、直播链接搜索、超长关键词和进房封面，见文末“升级落地（T02.U）”。）

- **没有当前直播、已结束的直播仍是“未知”**：归档 v4 把前者标成未开播、10 标成回放。回放在界面上算可播放，但 v4 不做回放录像，点进去只会报错。
- **不显示人数**：归档 v4 把主页的 `onlineNumber` 作在线、`watchNumber` 作累计（REG-KILAKILA-003）。加上后卡片会多出数字、“真实在线”排序会变。
- **关键词搜索一页一个请求，不逐个查主播**：归档 v4 对每个结果串行请求一次主页（一页 10 个请求，对照笔记 `sub_A.md` 第 7 条），拿到状态和标题。v3 只请求搜索页，状态一律未知，这里照做。
- **时间线只按 `isLastPage` 结束**：归档 v4 另加空页和 100 页的上限（REG-KILAKILA-005）。空页不结束是 v3 有测试固定的行为。
- **画质是 FLV、HLS 两个**：归档 v4 改成一个“原画”下两条线路、`原画` 的名字，画质菜单会变。
- **请求头照 v3**：UA 仍是 `Mozilla/5.0`；归档 v4 用完整的 Chrome UA，上游与 v3 相同。
- **搜索框里的直播分享链接搜不到**（问题 14）；**超长关键词报错不截断**（问题 17）。
- **进房后的封面用 `getRoomInfo` 的背景图**（问题 18）；归档 v4 没有当前直播时用头像作封面，v3 没有封面。
- **标题不解码 HTML 实体**，同 v3。归档 v4 会解，样本里没有实体。
- **推荐接口 `pcLive/recommend` 不用**：v3 的推荐就是热门时间线（归档 v4 同）。
- 上游 pure_live_TV 与 v3 相同，没有要采用的修复。

## 后续升级候选（由用户决定）

（2026-09-28 全部采用，编号 15-1～15-8，落地见文末“升级落地（T02.U）”。）

| # | 内容 | 现状（v3） | 依据 |
|---|---|---|---|
| 1 | 没有当前直播的主播显示为未开播；已结束的直播（10）也显示为未开播 | 未知 | 主页的空卡片是平台明确的“没有直播”（S04-owner-offline）；归档 v4 规格 §4 |
| 2 | 显示人数：主页的 `onlineNumber` 作在线（只有进房和刷新有），`watchNumber` 作累计 | 不显示 | REG-KILAKILA-003 的实测（累计只增不减） |
| 3 | 时间线到第 100 页结束，或跨页去重 | 只按 `isLastPage` | REG-KILAKILA-005；规格 §12 第 4 条（循环规律待确认） |
| 4 | 搜索框里的直播分享链接找到它的主播 | 没有结果 | 链接导入已经能做（一个 `getRoomInfo`），搜索再加一个主页请求 |
| 5 | 超长关键词截断到 100 个字符后搜索 | 报错 | 同 T02b.4 猫耳的候选 |
| 6 | 画质改成一个“原画”、两条线路 | FLV、HLS 两个画质 | 归档 v4 |
| 7 | 进房后的封面沿用主页卡片的 `backPic` | 换成 `getRoomInfo` 的默认背景 | 问题 18 |
| 8 | 克拉克拉弹幕（Socket.IO 游客房间） | 没有弹幕 | 归档 v4 已实现（规格 §7）；样本 `danmaku/S07-live` 已复制；本模块已输出 `KilakilaDanmakuArgs` |

## 回归条目的覆盖

五条都属于平台层，都有测试直接覆盖：

- 001（按一场直播的 id 保存，下次打不开）：房间号、链接都是 uid，`toJson` 里没有直播 id；主播换了一场直播后刷新、进房、恢复取流都跟到新的直播（移植 v3 的用例）。
- 002（加密的分享链接）：29 个向量、S06 的真实跳转链接，经 `LinkParser` 从分享文本里解析出主播；签名绑定协议、主机和路径。
- 003（`watchNumber` 不是在线人数）：不把它当任何人数，卡片不显示数字（照 v3，见候选 2）。
- 004（样本里的推流密钥）：`pushFlow` 从不读取，房间 JSON 里没有它；样本已整值脱敏。
- 005（时间线循环）：照 v3 按 `isLastPage` 结束（第 55 页），空页和被过滤的页不算结束；上限列为候选 3。

规格 §7 的弹幕、§12 的待确认事项不属于平台层。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 弹幕：v3 没有（多画面弹幕也不支持克拉克拉）；归档 v4 的做法是 Socket.IO 2 游客房间 `wss://wim.hongrenshuo.com.cn/socket.io/?roomId=<直播 id>&appId=111&clientType=1&EIO=3&transport=websocket`，文本帧加入命名空间，25 秒一次 `2` 心跳 | T06a；本模块输出 `KilakilaDanmakuArgs`，样本在 `fixtures/kilakila/danmaku/S07-live` |
| `getDanmaku()` | 同 T02a.1：T06a 用一张“平台 → 弹幕连接”的表 |
| 站点名、时间线名、目录说明（`site_kilakila`、`kilakila_hot`、`kilakila_newcomers`、`kilakila_directory_scope`）的多语言 | M13 |
| 网页搜索入口 `https://live.kilakila.cn/aboutus/serach/kw/<关键词>`（`search_controller.dart:111-112`）；搜索能力“含未开播、可翻页、有网页搜索”和说明文字 `search_coverage_kilakila`（`search_capability.dart:141-145`、`search_controller.dart:446`） | M13 搜索页 |
| 外部打开主播页（`room_external_opener.dart:144-146`） | M13；地址就是房间的 `link`（`KilakilaApi.ownerUrl`） |
| 人数设置：克拉克拉没有真实在线（`audience_metric_settings_page.dart:22`、`audience_kilakila_detail`） | M13 设置 |
| 热门平台列表的 v8 迁移把克拉克拉加进去（`favorite_room_controller.dart:64`） | T09b.1 |
| 播放、录制读线路的请求头和租期；HLS 线路到期会断，要在到期前换上新地址 | T04、T08a.1 |
| 录制对错误的重试（v3 的 `StreamResolverService` 把没有当前直播当作可重试的网络错误） | T08a.1 决定哪些错误重试 |
| 响应大小上限（v3 边读边限制 1 MiB，另有 20 秒读取期限） | live_net（T03a.1）没有逐请求的大小上限；需要时作为通用能力加到 `LiveRequest` |

## 新增的通用能力

- `packages/live_core/lib/src/aes.dart`：`Aes128Cbc`，AES-128-CBC 解密和 PKCS#7 去填充，取自归档 v4 的同名文件（archive/v4，AGPL-3.0，本项目）。用 SP 800-38A F.2.2 的向量和 29 个分享向量核对。v3 为此依赖 PointyCastle；现在 `live_core` 不增加依赖。已在 `live_core.dart` 导出（同 `tars.dart`）。
- 搜索页的 HTML 读取器只有这一个页面用，写在 `kilakila_api.dart` 里（私有），没有做成通用能力。
- 另在 `live_core.dart` 里按字母顺序加了两行平台导出。

## 测试

108 个用例，`live_core` 共 1077 个，全部通过：

- `kilakila_api_test.dart`（80 个）：
  - 逐个样本对照 v3 的输出（时间线 4 页、分类、搜索 3 页、主页 3 个、直播 3 个、跳转、29 个分享向量），有意的差异逐条断言；
  - 移植 v3 `kilakila_api_test.dart`、`kilakila_owner_test.dart`、`kilakila_link_test.dart`、`kilakila_directory_contract_test.dart` 中固定行为的部分：时间线的回显、去重、行类型和坏行，空卡片和坏卡片，主页和直播的身份校验，拉流地址的主机、端口、签名参数，付费和未知状态，HTTP 状态和业务码，1 MiB 上限，链接的全部畸形用例、载荷编码、签名绑定、随机密文；
  - 搜索页读取器：注释和脚本里的标记不算、只认列表的直接子元素、实体解码；
  - AES 的标准向量，租期。
- `kilakila_site_test.dart`（28 个），用样本回放加少量合成响应：
  - 请求头、不跟随跳转、传输错误的映射，取消（请求前、应答后、传输出错后）；
  - 分类不发请求；时间线各页与 v3 的请求逐个相同，每页条数照调用方，坏参数不发请求；
  - 搜索：关键词一页一个请求、不逐个查主播，uid 和主页链接一个请求、只在第 1 页，其他链接和补零的数字不发请求，带冒号的关键词，拒绝的参数不发请求；
  - 详情：刷新 1 个请求、进房和录制 2 个请求（与 v3 的请求相同），没有直播 1 个请求，不存在和非 uid 的房间号，关注跨直播保持身份并能合并，未知状态，直播在两次请求之间结束，付费、非直播、缺地址的直播能进房、取流说明原因；
  - 取流：进房得到的房间不再请求，列表卡片先进房，明确未开播不请求，恢复时跟到新的直播（移植 v3 的用例），恢复不复用旧地址；
  - 链接：主播页不请求，直播页经 `LinkParser` 请求一次 `getRoomInfo`（S06 的真实分享文本、29 个向量），查不到时没有房间。
- v3 测试里不属于平台层的部分没有移植，留给对应模块：`kilakila_catalog_migration_test.dart`（热门平台列表迁移、备份、搜索页）属于 T09b.1、M13；`kilakila_application_test.dart` 里的站点注册、热门和分区页控制器、分享命令、外部打开、播放和录制的请求头表属于播放、录制和界面（T04、T08a.1、M13）；`kilakila_api_test.dart` 里的 `readBody`（边读边限、读取期限、UTF-8）由 `live_net` 负责。

## 升级落地（T02.U）

- 日期：2026-09-29（T02b.6）
- 依据：[升级决定](../../../specs/UPGRADES.md) 的“统一原则”和本平台的 15-1～15-8；模型字段按 [T02g.2](../../T02g/T02g.2/record.md)。
  - 15-8（弹幕）属于 T06a，这里没有改：平台层要给的弹幕参数 `KilakilaDanmakuArgs` 在 T02b.6 已经给出，本次只核对它够用。
- 改动：
  - 本平台：`kilakila_api.dart`（解析）、`kilakila_site.dart`（请求编排）和两份测试；
  - 通用文件只做了添加：`audience.dart` 的人数能力表加了 `kilakila` 一行（见“新增的通用能力”）；
  - 新样本 1 个（见“新样本”）；没有新依赖。
- 实测：2026-09-28 17:40～18:10 UTC 直连，只读地请求了公开接口：
  - 热门第 1 页 10 个在播主播的主页，对照三个时间字段和在线人数；
  - 热门、萌星逐页翻到底，看循环和结尾；
  - 两条时间线全部 325 个在播主播的 `goldPrice` 和 `status`（都是 0 和 4）；
  - 100 字、150 字的关键词搜索页（都正常返回）；
  - 用新适配器走了一遍：目录、刷新、进房、画质和线路、关键词和超长关键词搜索、直播链接搜索。

### 逐条

| 编号 | 做了什么 | 用户会看到什么 | 状态 |
|---|---|---|---|
| 15-1 | `KilakilaApi.room`：平台说 10（已结束）的直播是未开播。主页卡片只有两个路由字段（没有当前直播）时，主播是未开播：刷新、进房、录制、按 uid 或链接搜索都是（`profileDetail`、`profileRoom`）。其他没见过的状态值仍是“未知”；关键词搜索页不说状态，仍是“未知”。未开播的房间取流时不发请求，直接 `StreamUnavailable` | 关注页里没在直播的主播从“待定”变成“未开播”，归入未开播分组；进房显示未开播 | 完成（T02.U） |
| 15-2 | 直播中的房间带人数：<br>- 主页卡片的 `onlineNumber` 作在线（`onlineViewers`），刷新、进房、录制、精确搜索有；<br>- `watchNumber` 作累计（`totalViewers`），列表、卡片、`getRoomInfo` 都有；进房时取 `getRoomInfo` 的，比卡片新；<br>- `audienceMetricType` 为 `onlineViewers`；不合法的数字不填，不报错。<br>未开播、状态未知的房间不带人数。`audience.dart` 加了克拉克拉的能力：有累计，在线只在房间里有（`roomRealtime`） | 列表卡片显示累计收听数；打开“真实在线”排序时，列表里显示待定，关注刷新和进房后显示在线人数。直播间显示在线人数。标签文字和 3.x 设置页的说明由 M13 改 | 平台层完成，余下 M13 |
| 15-3 | 时间线（推荐、两个分区、原生目录分页）：<br>- 到第 100 页结束（`KilakilaApi.maxPages`）：第 100 页的 `hasMore` 为假，之后的页直接为空，不发请求；<br>- 跨页去重：适配器按“时间线 + 每页条数”记下从第 1 页起列过的主播，后面的页不再列出；重读同一页结果不变，重读第 1 页（下拉刷新）从头算，没读过前面的页直接跳到某页时只在页内去重；<br>- 连续 3 页没有新主播时结束（`KilakilaSite.maxPagesWithoutNew`）。实测热门第 11 页后就只剩重复（第 12～41 页），只去重的话会连着返回 30 个空页；单独一页没有新主播不结束（实测第 3 页全是重复，第 4 页又有新的）；<br>- 没有任何行的页就是最后一页：萌星翻到底时返回 `{pageNo, pageSize, data: []}`，没有 `isLastPage`，v3 当作接口变化报错（新样本 `S01-timeline-new-tail`）。<br>不增加请求 | 热门、萌星往下翻不再反复出现同一批主播；翻到底会结束，不再显示加载失败，也不会一直翻 | 完成（T02.U） |
| 15-4 | 搜索框的输入是直播页链接（`/room/<id>`、`/PcLive/index/detail?id=`、官网的加密分享链接）时，先请求 `getRoomInfo` 找到主播，再请求主页，结果和按 uid 搜索相同：在播给当前直播的卡片，没在播给未开播的主播卡片。只有第 1 页，不翻页。直播不存在（5201）、历史回放（5966，回答里没有主播）时没有结果；其他失败照常报错（同 uid 搜索） | 在搜索框粘贴直播间链接或分享链接能找到主播，即使那一场已经结束 | 完成（T02.U） |
| 15-5 | `KilakilaApi.searchKeyword`：去掉首尾空白后超过 100 个 UTF-16 码元的关键词截到 100（不从代理对中间截断，截后再去掉末尾空白）再搜索，翻页也用截后的关键词。页码超过 10000、每页超过 100 条仍是参数错误（界面不会传） | 超长关键词按前 100 字搜索，不再显示失败。网站本身接受 150 字的关键词，100 是 v3 的限制，沿用 | 完成（T02.U） |
| 15-6 | 画质只有一个“原画”（`KilakilaApi.qualityName`，id `original`），数据是本场的拉流地址，线路 FLV 在前、HLS 在后，互为备用。每条线路带请求头、格式、`lineId`（`flv`、`hls`）和租期（HLS 到期会断）。一条地址不合规只少这一条线路。v3 的画质 id `flv`、`hls` 仍能取流，按“原画”处理（对照见下文） | 画质菜单从“FLV”“HLS”变成一个“原画”。默认仍先播 FLV（v3 默认第一档也是 FLV）；FLV 打不开时换 HLS 由播放器做（T04）。3.x 的全局画质偏好“原画”现在能对上 | 平台层完成，余下 T09b.1 |
| 15-7 | 进房和录制时，封面用主页卡片的封面（和列表、关注刷新相同的 `backPic`）；卡片没有封面、或卡片不是这一场直播时，才用 `getRoomInfo` 的默认背景（样本里是动图）。卡片的开播时间和在线人数也在这里带进房间（`KilakilaApi.enteredRoom`、`KilakilaBroadcast.withCard`） | 进房前后封面一样，不再换成动图背景 | 完成（T02.U） |
| 15-8 | 本任务不做（T06a）。核对：归档 v4 的弹幕连接（Socket.IO 游客房间）只需要本场直播 id，握手的请求头是协议常量；进房时的 `KilakilaDanmakuArgs(roomId)` 就是它，录制不带。没有当前直播的主播不带参数（聊天室按场次开，没有直播就没有房间） | 无 | 平台层完成，余下 T06a |

### 统一原则在克拉克拉上的落实

| 事项 | 做法 |
|---|---|
| 开播时间 | 主页卡片的 `actualTime`（毫秒，UTC）：<br>- 实测 10 个在播主播的 `actualTime` 都在抓取前 1～4 小时（北京时间晚上开播）；<br>- `liveStartTime`、`createTime` 是这一场直播建立的时间，常常早一天，不是开播时间：同一主播新一场直播的 `createTime` 正好是上一场的 `actualTime`（S04 的主播，09-27 和 09-28 两场）；<br>- 所以只用 `actualTime`，缺了就不填（归档 v4 缺时退回 `liveStartTime`，这里不退回）；<br>- 不是毫秒时间戳的值不填；只在直播中填。<br>时间线的行和 `getRoomInfo` 没有这个字段：刷新、进房、录制、精确搜索有开播时间，列表和关键词搜索没有。每个主播多请求一次才能在列表里有，不做 |
| 受限类型 | 直播中的直播：`goldPrice` 大于 0 填 `paid`，否则填 `none`（列表、主页卡片、`getRoomInfo` 都有这个字段）。未开播、状态未知、关键词搜索的结果不填。付费直播取流报 `StreamUnavailable`，说明里写 `(paid)`，仍在状态检查之前（v3 的顺序）。v3 报 `NeedsLogin`，但克拉克拉没有登录功能，按 T02g.2 的表，付费是 `StreamUnavailable` |
| 受限的直播改为直播中 | 付费直播本来就是直播中（v3 同样），现在另标 `paid` |
| 占位信息 | 没有找到平台的占位名字、标题或封面。没有直播时标题留空（T02b.6 起就是这样），不会覆盖关注里存下的标题。搜索卡片用主播名作标题是 v3 的卡片样式（搜索页没有直播标题），不是平台给的占位值，保留 |
| 回放、“不可播放” | 按 15-1，已结束的直播是主播“未开播”，不标回放，所以没有“不可播放”的回放。`getRoomInfo` 对已结束的直播给录像地址 `videoUrl`（S05-room-replay），不用：房间是主播，不是某一场直播；直播结束后主页给空卡片（S04-owner-offline），“已结束”只在两次请求之间下播、或打开一场旧直播时出现 |
| 画质命名 | 见 15-6 |
| 默认编码 | 规格 §6.4：FLV、HLS 都是 H.264（语音直播的背景画面），“优先 H.264”对本平台没有影响 |
| 房间身份 | 数字 uid，大小写无关，不加入 `SiteIds.caseInsensitiveRoomIds` |
| 按主播关注 | 本来就是（REG-KILAKILA-001），见“身份迁移规则” |
| 容错 | 时间线的坏行、搜索页的坏条目只跳过这一行（v3 整页 `ApiChanged`）：不是对象、没有类型、主播或标题或名字缺失或对不上、链接不是主播页、没有名字。一页里有坏行而没有一行能用时仍报 `ApiChanged`，页码回显、信封不对也仍报错，接口改版不会被当成空列表。一条拉流地址不合规只少这一条线路 |
| 翻页 | 见 15-3。目录和搜索都是平台分页，没有一次取全的列表，不共用快照；搜索不去重（网站的用户搜索页是稳定的序列，样本两页没有重复） |

### 请求数

| 场景 | T02b.6 | 现在 |
|---|---|---|
| 关注刷新、`getLiveStatus` | 主页 1 个 | 不变 |
| 分类 | 0 | 不变 |
| 目录、推荐、分区每页 | 1 个 | 不变；第 100 页之后、连续 3 页没有新主播之后不再有下一页 |
| 关键词搜索每页 | 1 个 | 不变 |
| uid、主播页链接搜索 | 1 个 | 不变 |
| 直播页链接搜索 | 0（没有结果） | 2 个：`getRoomInfo` 和主页（15-4 要求的） |
| 进房、录制 | 2 个（没有当前直播时 1 个） | 不变 |
| 取流 | 带进房数据的房间 0；列表卡片先进房 2；恢复 2；明确未开播 0 | 不变；“明确未开播”多了没有直播和已结束两种，这些房间取流不发请求 |
| 链接导入 | 直播链接 1 个 | 不变 |

### 画质 id 对照（给 T09b.1）

| 旧 id（旧名字） | 新 id（新名字） | 对应的线路 |
|---|---|---|
| `flv`（FLV） | `original`（原画） | `lineId` 为 `flv` 的第一条 |
| `hls`（HLS） | `original`（原画） | `lineId` 为 `hls` 的第二条 |
| 其他 | 不变 | — |

- 代码：`KilakilaApi.legacyQualityIds`（常量表）、`KilakilaApi.qualityIdFromLegacy(id)`（不分大小写，表外的 id 原样返回）。取流（`resolvePlayUrls`、恢复取流）直接接受旧 id，按“原画”给出两条线路。
- 3.x 的画质偏好是全局按名字存的（原画、蓝光 8M、蓝光 4M、超清、流畅），“FLV”“HLS”不在其中，所以 3.x 数据里没有要迁移的克拉克拉画质 id；改名后全局偏好“原画”能直接对上。这张表给 v4 自己存下的画质（比如按房间记住画质）用。
- 旧 id 是 `hls` 的，如果要保留“先播 HLS”的意思，可以把 `lineId` 为 `hls` 的线路排到前面（T04 决定）。

### 设置项

无。本平台的 8 行都不需要开关。

### 身份迁移规则（给 T09b.1）

无。3.x 的克拉克拉从接入起就按主播 uid 存关注（v3 S:39-47，REG-KILAKILA-001），本次房间号的含义和写法都没变，没有旧 id → 新 id 的规则。uid 是数字，也没有大小写不同的重复关注要合并。

### 留给其他模块

| 内容 | 去向 |
|---|---|
| 15-8 克拉克拉弹幕：用 `KilakilaDanmakuArgs.roomId` 连 Socket.IO 游客房间（见“放到其他模块的部分”），样本 `danmaku/S07-live` | T06a |
| 15-6 线路：FLV 打不开或断开时换 HLS 线路；HLS 线路按租期续签 | T04 |
| 15-6 存下的画质 id 按上表迁移 | T09b.1 |
| 15-2 人数的显示：列表显示累计（标“累计”），“真实在线”模式下列表显示待定，关注刷新和进房后显示在线；3.x 设置页的说明 `audience_kilakila_detail`（“克拉克拉没有真实在线”）要改写 | M13 |
| 15-3 目录列表：去重后一页可能是空的而 `hasMore` 仍为真（最多连续 2 页），列表要接着取下一页，不能当作到底 | M13 |
| 卡片上的“付费”标记和播放失败时的说明；开播时间只在直播中显示 | M13 |

### 受阻和未核实

没有受阻的条目。没有核实的：

- **付费直播**：2026-09-28 两条时间线的 325 个在播主播 `goldPrice` 都是 0，没有样本。付费时拉流地址是否照样下发（规格 §12 第 5 条）不去试，按 v3 在取流时直接拒绝，标 `paid`。
- **其他状态值**（规格 §12 第 1 条）：325 个都是 4，没见过 4、10 以外的值，它们仍是“未知”。
- **时间线的内容变化很大**：同一天几次翻页，热门有时 42 页里只有 100 个不同的主播，有时 21 页里 210 个各不相同；萌星的结尾有时是空页，有时空页之后又有数据（多次请求得到的不一样）。15-3 的规则对这些情况都适用：空页或连续 3 页没有新主播就结束，最多 100 页。

### 与 v3 冻结输出的新差异

样本对照测试里用 `changed:` 列出，注释写条目编号；新增的键另外断言：

- S01 时间线（4 页）：`totalViewers`（`watchNumber`）和 `audienceMetricType`（15-2）；新键 `restriction`（`none`）。房间、顺序、页码、是否还有下一页都与 v3 相同（样本都在 100 页以内，热门第 55 页是 `isLastPage`）。
- S03 搜索：没有变化。
- S04-owner-live：刷新详情和精确搜索多了人数三键（15-2）和新键 `startedAt`、`restriction`；进房另有 `cover`（15-7）。画质由两个变成一个“原画”（15-6），地址逐字节相同，顺序 FLV、HLS；v3 恢复取流的 FLV 地址是新的第一条线路。
- S04-owner-offline：`liveStatus` 由 3（未知）变为 1（未开播），刷新、进房、录制、精确搜索都是（15-1）。
- S05-room-replay：状态由未知变为未开播（15-1）。
- S05-room-live、S05-room-notfound、S06、S09：没有变化。

### 新样本

| 样本 | 内容 |
|---|---|
| `S01-timeline-new-tail` | 萌星时间线第 51 页：`b` 只有 `pageNo`、`pageSize` 和空的 `data`，没有 `isLastPage`（2026-09-28 17:52 UTC 直连录制） |

- 请求头是适配器的 `KilakilaApi.headers`（UA `Mozilla/5.0`、`Referer`），不带 Cookie。
- 脱敏：响应头 `set-cookie` 里的会话 `HDSESSION` 换成同形的合成值，记进 `meta.json` 的 `scrubbed`；正文没有行，也就没有推流地址，其余没有要脱敏的字段。`raw` 是原始正文的 SHA-256 和长度。
- 门禁的 `fixture privacy` 通过。

### 新增的通用能力

- `packages/live_core/lib/src/audience.dart`：`audienceCapabilities` 加 `kilakila` 一行（只添加）：没有热度，有累计（`watchNumber`），在线只在房间里有（`onlineAvailability: roomRealtime`，主页的 `onlineNumber`）。之前克拉克拉不在表里（没有任何人数），界面据此决定排序和“真实在线”模式下怎么显示。

### 测试

本平台 127 个用例（新增 19 个，另改写了受影响的对照用例），`live_core` 共 3076 个，门禁 `--all` 通过：

- `kilakila_api_test.dart`（89 个）：
  - 对照：新增的键逐个断言，改变的键用 `changed:` 列出并写条目编号；
  - 15-1：没有直播、已结束是未开播，其他状态仍是未知；
  - 15-2：列表的累计、卡片的在线，“真实在线”模式下的显示，不合法的人数，克拉克拉的人数能力；
  - 15-3：空尾页样本、没有 `isLastPage` 的空页和非空页、第 100 页；
  - 15-5：截断（100 个码元、代理对、截后去空白）；
  - 15-6：一个“原画”、两条线路、缺一条或一条不合规、旧 id 对照和取流；
  - 15-7：卡片封面、卡片没有封面、别的直播的卡片；
  - 统一原则：`actualTime` 和各种坏时间、`liveStartTime` 不用、付费标 `paid` 并在取流时说明、坏行和坏条目只跳过这一个、全坏仍报错。
- `kilakila_site_test.dart`（38 个）：
  - 15-3：跨页去重、重读同一页、重读第 1 页、不同每页条数和时间线分开记、直接跳页、连续 3 页没有新主播、第 100 页和之后不请求、萌星空尾页；
  - 15-4：真实分享链接、`/room/` 和详情页链接各 2 个请求、结果与按 uid 搜索相同、第 2 页不请求、不存在和历史回放没有结果、已下播的主播、改版和网络错误报错；
  - 15-5：超长关键词的请求路径和翻页；
  - 15-1、15-2、15-7：没有直播的主播刷新和进房都是未开播、取流不请求；刷新、进房、录制的人数、开播时间和封面；
  - 付费、已结束、状态未知、缺地址的直播能进房，取流说明原因；
  - 取流：一个“原画”两条线路，旧 id 取到同样的线路，恢复跟到新的直播且不复用旧地址。

## 后续（T06a 弹幕）

本平台的聊天（弹幕）已由 T06a.14 完成，见 [记录](../../../T06/T06a/T06a.14/record.md)；弹幕参数、登记方式和房间公告的现行文字以那份记录和代码为准，状态以 [升级决定](../../../specs/UPGRADES.md) 为准。上文里“弹幕待做”“没有弹幕参数类”“聊天尚待接入/暂时看不到”等说法是 T02 当时的情况，不再改动。
